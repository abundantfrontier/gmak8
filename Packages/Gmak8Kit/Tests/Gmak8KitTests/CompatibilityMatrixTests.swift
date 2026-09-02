import Foundation
import Testing

@testable import Gmak8Kit

struct CompatibilityMatrixTests {
    @Test func bundledJSONAccepts133AndNewDataDir() throws {
        let matrix = try JSONDecoder().decode(CompatibilityMatrix.self, from: CompatibilityMatrix.jsonUTF8)
        #expect(matrix.k3s[K3sPin.version]?.dataDirMinorsAccepted == ["1.33"])
        #expect(CompatibilityMatrix.bundled.accepts(dataDirMinor: "1.33"))
        #expect(CompatibilityMatrix.bundled.accepts(dataDirMinor: nil))
        #expect(CompatibilityMatrix.bundled.accepts(dataDirMinor: ""))
        #expect(!CompatibilityMatrix.bundled.accepts(dataDirMinor: "1.32"))
        #expect(K3sPin.version == "v1.33.3+k3s1")
    }

    @Test func refusalNamesResetAndMatchingPair() {
        let message = CompatibilityMatrix.bundled.refusalMessage(dataDirMinor: "1.32")
        #expect(message.contains("1.32"))
        #expect(message.contains("v1.33.3+k3s1"))
        #expect(message.lowercased().contains("reset"))
        #expect(message.contains("matching gmak8/guest pair"))
    }

    @Test func shippedJSONFileMatchesBundledConstant() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Gmak8Kit/Compatibility/compatibility-matrix.json")
        let data = try Data(contentsOf: url)
        let fromFile = try JSONDecoder().decode(CompatibilityMatrix.self, from: data)
        let fromConstant = try JSONDecoder().decode(CompatibilityMatrix.self, from: CompatibilityMatrix.jsonUTF8)
        #expect(fromFile == fromConstant)
        #expect(fromFile == CompatibilityMatrix.bundled)
    }
}
