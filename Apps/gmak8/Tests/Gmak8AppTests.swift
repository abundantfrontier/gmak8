import Gmak8Kit
import Testing

struct Gmak8AppTests {
    @Test func kitVersionIsPinned() {
        #expect(Gmak8Kit.version == "0.0.1")
    }
}
