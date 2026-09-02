import Foundation
import Virtualization

public final class LinuxEFIVirtualMachineRuntime: @unchecked Sendable {
    public let layout: VMDiskLayout
    public let hardware: VMHardware
    public let isSupported: Bool

    private let flock = DiskFlock()
    private var virtualMachine: VZVirtualMachine?

    public init(
        layout: VMDiskLayout,
        hardware: VMHardware,
        isSupported: Bool = VZVirtualMachine.isSupported
    ) {
        self.layout = layout
        self.hardware = hardware
        self.isSupported = isSupported
    }

    public var holdsDiskLocks: Bool {
        flock.isHolding
    }

    public func prepare() throws {
        if !isSupported {
            throw VirtualMachineError.unsupported
        }
        try layout.ensureFiles(osSize: hardware.osDiskBytes, dataSize: hardware.dataDiskBytes)
        try flock.acquire(urls: layout.lockURLs)
    }

    public func releaseLocks() {
        flock.release()
    }

    public func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        VirtualMachineQueue.shared.async { [weak self] in
            self?.startOnVMQueue(completion: completion)
        }
    }

    public func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        VirtualMachineQueue.shared.async { [weak self] in
            self?.stopOnVMQueue(completion: completion)
        }
    }

    private func startOnVMQueue(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        do {
            if !isSupported {
                throw VirtualMachineError.unsupported
            }
            try prepare()
            let config = try VMConfigurationBuilder.make(layout: layout, hardware: hardware)
            do {
                try config.validate()
            } catch {
                throw VirtualMachineError.configurationFailed(error.localizedDescription)
            }
            let vm = VZVirtualMachine(configuration: config, queue: VirtualMachineQueue.shared)
            virtualMachine = vm
            vm.start { [weak self] result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    self?.virtualMachine = nil
                    self?.flock.release()
                    completion(.failure(VirtualMachineError.startFailed(error.localizedDescription)))
                }
            }
        } catch {
            virtualMachine = nil
            flock.release()
            completion(.failure(error))
        }
    }

    private func stopOnVMQueue(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        guard let vm = virtualMachine else {
            flock.release()
            completion(.success(()))
            return
        }
        let finish: (Error?) -> Void = { [weak self] error in
            self?.virtualMachine = nil
            self?.flock.release()
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
        if vm.canStop {
            vm.stop { error in
                finish(error)
            }
        } else {
            finish(nil)
        }
    }
}
