import Testing

@testable import Gmak8XPC

struct APIReadyzTests {
    @Test func acceptsReadyAndAnonymousAuth() {
        #expect(APIReadyz.accepts(200))
        #expect(APIReadyz.accepts(401))
        #expect(APIReadyz.accepts(403))
        #expect(!APIReadyz.accepts(0))
        #expect(!APIReadyz.accepts(404))
        #expect(!APIReadyz.accepts(500))
        #expect(!APIReadyz.accepts(503))
    }
}
