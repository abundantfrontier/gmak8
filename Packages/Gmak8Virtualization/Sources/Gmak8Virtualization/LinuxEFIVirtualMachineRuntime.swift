import Foundation
import Virtualization

public final class LinuxEFIVirtualMachineRuntime: @unchecked Sendable {
    public let layout: VMDiskLayout
    public let hardware: VMHardware
    public let isSupported: Bool
    public let network: GVProxyNetworkStack?

    private let flock = DiskFlock()
    private let mutex = NSLock()
    private let vmDelegate = VMDelegate()

    private var virtualMachine: VZVirtualMachine?
    private var nextTicket: UInt64 = 0
    private var rejectedTicket: UInt64 = 0
    private var inFlightTicket: UInt64?
    private var stopRequested = false
    private var pendingCancel = false
    private var pendingStopCompletions: [@Sendable (Result<Void, any Error>) -> Void] = []
    private var unexpectedStopHandler: (@Sendable (Error?) -> Void)?
    var prepareHook: (() -> Void)?

    public init(
        layout: VMDiskLayout,
        hardware: VMHardware,
        isSupported: Bool = VZVirtualMachine.isSupported,
        network: GVProxyNetworkStack? = nil
    ) {
        self.layout = layout
        self.hardware = hardware
        self.isSupported = isSupported
        self.network = network
        vmDelegate.owner = self
    }

    public var holdsDiskLocks: Bool {
        flock.isHolding
    }

    public func setUnexpectedStopHandler(_ handler: (@Sendable (Error?) -> Void)?) {
        mutex.lock()
        unexpectedStopHandler = handler
        mutex.unlock()
    }

    public func cancelInFlightStart() {
        mutex.lock()
        pendingCancel = true
        rejectedTicket = max(rejectedTicket, nextTicket)
        mutex.unlock()
    }

    public func prepare() throws {
        if !isSupported {
            throw VirtualMachineError.unsupported
        }
        if isCancelled() {
            throw VirtualMachineError.stoppedDuringStart
        }
        try network?.preflight()
        if isCancelled() {
            throw VirtualMachineError.stoppedDuringStart
        }
        try layout.ensureFiles(osSize: hardware.osDiskBytes, dataSize: hardware.dataDiskBytes)
        if isCancelled() {
            throw VirtualMachineError.stoppedDuringStart
        }
        try flock.acquire(urls: layout.lockURLs)
        prepareHook?()
        if isCancelled() {
            flock.release()
            throw VirtualMachineError.stoppedDuringStart
        }
    }

    public func releaseLocks() {
        flock.release()
    }

    public func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        let ticket = nextStartTicket()
        if shouldAbortStart(ticket) {
            completion(.failure(VirtualMachineError.stoppedDuringStart))
            return
        }
        do {
            try prepare()
        } catch let error as VirtualMachineError where error == .stoppedDuringStart {
            flock.release()
            completion(.failure(error))
            return
        } catch {
            if shouldAbortStart(ticket) {
                flock.release()
                completion(.failure(VirtualMachineError.stoppedDuringStart))
                return
            }
            completion(.failure(error))
            return
        }
        if shouldAbortStart(ticket) {
            flock.release()
            completion(.failure(VirtualMachineError.stoppedDuringStart))
            return
        }
        VirtualMachineQueue.shared.async {
            self.startOnVMQueue(ticket: ticket, completion: completion)
        }
    }

    public func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        mutex.lock()
        pendingCancel = false
        rejectedTicket = max(rejectedTicket, nextTicket)
        mutex.unlock()
        VirtualMachineQueue.shared.async {
            self.stopOnVMQueue(completion: completion)
        }
    }

    private func nextStartTicket() -> UInt64 {
        mutex.lock()
        nextTicket += 1
        let ticket = nextTicket
        mutex.unlock()
        return ticket
    }

    private func isRejected(_ ticket: UInt64) -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return ticket <= rejectedTicket
    }

    private func isCancelled() -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        if pendingCancel {
            return true
        }
        return nextTicket != 0 && nextTicket <= rejectedTicket
    }

    private func shouldAbortStart(_ ticket: UInt64) -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        if ticket <= rejectedTicket || pendingCancel {
            pendingCancel = false
            rejectedTicket = max(rejectedTicket, ticket)
            return true
        }
        return false
    }

    private func startOnVMQueue(
        ticket: UInt64,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        if isRejected(ticket) {
            cancelUnstarted(completion: completion)
            return
        }
        if virtualMachine != nil {
            completion(.failure(VirtualMachineError.startFailed("already running")))
            return
        }
        do {
            if !isSupported {
                throw VirtualMachineError.unsupported
            }
            if !flock.isHolding {
                try flock.acquire(urls: layout.lockURLs)
            }
            let attachment = try network?.start()
            if isRejected(ticket) {
                network?.stop()
                cancelUnstarted(completion: completion)
                return
            }
            let config = try VMConfigurationBuilder.make(
                layout: layout,
                hardware: hardware,
                networkAttachment: attachment
            )
            do {
                try config.validate()
            } catch {
                throw VirtualMachineError.configurationFailed(error.localizedDescription)
            }
            let vm = VZVirtualMachine(configuration: config, queue: VirtualMachineQueue.shared)
            vm.delegate = vmDelegate
            virtualMachine = vm
            inFlightTicket = ticket
            stopRequested = false
            vm.start { result in
                self.handleStartCompletion(ticket: ticket, vm: vm, result: result, completion: completion)
            }
        } catch {
            failStartCleanup()
            completion(.failure(error))
        }
    }

    private func handleStartCompletion(
        ticket: UInt64,
        vm: VZVirtualMachine,
        result: Result<Void, any Error>,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        guard virtualMachine === vm, inFlightTicket == ticket else {
            abandon(vm)
            completion(.failure(VirtualMachineError.stoppedDuringStart))
            return
        }
        inFlightTicket = nil
        switch result {
        case .success:
            if stopRequested || isRejected(ticket) {
                requestStop(vm: vm) { stopResult in
                    completion(.failure(VirtualMachineError.stoppedDuringStart))
                    self.finishPendingStops(stopResult)
                }
            } else {
                do {
                    try network?.exposeDefaultPorts()
                    completion(.success(()))
                } catch {
                    requestStop(vm: vm) { stopResult in
                        completion(.failure(error))
                        self.finishPendingStops(stopResult)
                    }
                }
            }
        case .failure(let error):
            retire(vm)
            finishPendingStops(.success(()))
            completion(.failure(VirtualMachineError.startFailed(error.localizedDescription)))
        }
    }

    private func stopOnVMQueue(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        stopRequested = true
        guard let vm = virtualMachine else {
            network?.stop()
            flock.release()
            stopRequested = false
            completion(.success(()))
            return
        }
        if inFlightTicket != nil, !vm.canStop {
            pendingStopCompletions.append(completion)
            return
        }
        requestStop(vm: vm, completion: completion)
    }

    private func requestStop(
        vm: VZVirtualMachine,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        guard vm.canStop else {
            pendingStopCompletions.append(completion)
            return
        }
        vm.stop { error in
            if let error {
                completion(.failure(VirtualMachineError.stopFailed(error.localizedDescription)))
                return
            }
            self.retire(vm)
            completion(.success(()))
        }
    }

    private func cancelUnstarted(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        failStartCleanup()
        completion(.failure(VirtualMachineError.stoppedDuringStart))
    }

    private func failStartCleanup() {
        virtualMachine = nil
        inFlightTicket = nil
        stopRequested = false
        network?.stop()
        flock.release()
        finishPendingStops(.success(()))
    }

    private func retire(_ vm: VZVirtualMachine) {
        guard virtualMachine === vm else {
            return
        }
        virtualMachine = nil
        inFlightTicket = nil
        stopRequested = false
        flock.release()
        network?.stop()
    }

    private func abandon(_ vm: VZVirtualMachine) {
        guard virtualMachine !== vm else {
            return
        }
        if vm.canStop {
            vm.stop { _ in }
        }
    }

    private func finishPendingStops(_ result: Result<Void, any Error>) {
        let completions = pendingStopCompletions
        pendingStopCompletions.removeAll()
        for completion in completions {
            completion(result)
        }
    }

    private func handleGuestDidStop(_ vm: VZVirtualMachine) {
        guard virtualMachine === vm else {
            return
        }
        let requested = stopRequested || inFlightTicket != nil
        retire(vm)
        finishPendingStops(.success(()))
        if !requested {
            notifyUnexpectedStop(nil)
        }
    }

    private func handleDidStopWithError(_ vm: VZVirtualMachine, error: Error) {
        guard virtualMachine === vm else {
            return
        }
        let requested = stopRequested
        retire(vm)
        finishPendingStops(.failure(error))
        if !requested {
            notifyUnexpectedStop(error)
        }
    }

    private func notifyUnexpectedStop(_ error: Error?) {
        mutex.lock()
        let handler = unexpectedStopHandler
        mutex.unlock()
        handler?(error)
    }

    private final class VMDelegate: NSObject, VZVirtualMachineDelegate {
        weak var owner: LinuxEFIVirtualMachineRuntime?

        func guestDidStop(_ virtualMachine: VZVirtualMachine) {
            owner?.handleGuestDidStop(virtualMachine)
        }

        func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
            owner?.handleDidStopWithError(virtualMachine, error: error)
        }
    }
}
