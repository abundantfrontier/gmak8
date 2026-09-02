import Testing

@testable import Gmak8Kit

struct Gmak8LogTests {
    @Test func subsystemMatchesBundleIdentifier() {
        #expect(Gmak8Log.subsystem == "dev.gmak8.app")
        #expect(Gmak8Log.subsystem == Gmak8Kit.bundleIdentifier)
    }
}
