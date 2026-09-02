import Foundation
import Testing

@testable import Gmak8Kit

struct CompatibilityMatrixTests {
    @Test func bundledJSONAccepts133AndNewDataDir() throws {
        let matrix = try CompatibilityMatrix.loadFromModule()
        #expect(matrix.k3s[K3sPin.version]?.dataDirMinorsAccepted == ["1.33"])
        #expect(matrix == CompatibilityMatrix.bundled)
        #expect(CompatibilityMatrix.bundled.accepts(dataDirMinor: "1.33", dataDirExists: true))
        #expect(CompatibilityMatrix.bundled.accepts(dataDirMinor: nil, dataDirExists: false))
        #expect(CompatibilityMatrix.bundled.accepts(dataDirMinor: "", dataDirExists: false))
        #expect(!CompatibilityMatrix.bundled.accepts(dataDirMinor: nil, dataDirExists: true))
        #expect(!CompatibilityMatrix.bundled.accepts(dataDirMinor: "", dataDirExists: true))
        #expect(!CompatibilityMatrix.bundled.accepts(dataDirMinor: "1.32", dataDirExists: true))
        #expect(K3sPin.version == "v1.33.3+k3s1")
        #expect(K3sPin.displayVersion == "1.33.3")
    }

    @Test func refusalNamesResetAndMatchingPair() {
        let message = CompatibilityMatrix.bundled.refusalMessage(dataDirMinor: "1.32")
        #expect(message.contains("1.32"))
        #expect(message.contains("v1.33.3+k3s1"))
        #expect(message.lowercased().contains("reset"))
        #expect(message.contains("matching gmak8/guest pair"))
        let unknown = CompatibilityMatrix.bundled.refusalMessage(dataDirMinor: "")
        #expect(unknown.contains("unknown"))
    }
}
