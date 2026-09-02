import Darwin
import Foundation
import Testing

@testable import Gmak8Virtualization

struct UnixgramPathTests {
    @Test func sunPathMatchesDarwinSockaddrUn() {
        #expect(MemoryLayout.size(ofValue: sockaddr_un().sun_path) == 104)
        #expect(UnixgramPath.sunPathByteCount == 104)
        #expect(UnixgramPath.sunPathByteCount == HostPathsSunPath.darwinByteCount)
    }

    @Test func fitsBoundaryAndRejectsOverlong() {
        let fits = URL(fileURLWithPath: "/" + String(repeating: "x", count: 102))
        let tooLong = URL(fileURLWithPath: "/" + String(repeating: "x", count: 103))
        #expect(UnixgramPath.fits(fits))
        #expect(!UnixgramPath.fits(tooLong))
        #expect(throws: VirtualMachineError.socketPathTooLong(tooLong)) {
            try UnixgramPath.require(tooLong)
        }
        let overLong = URL(
            fileURLWithPath:
                "/Users/\(String(repeating: "u", count: 80))/Library/Application Support/dev.gmak8.app/n.sock"
        )
        #expect(!UnixgramPath.fits(overLong))
        let message = VirtualMachineError.socketPathTooLong(overLong).recoveryMessage
        #expect(message.contains("too long"))
        #expect(message.contains("n.sock"))
    }
}

private enum HostPathsSunPath {
    static let darwinByteCount = 104
}
