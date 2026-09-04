import Testing

@testable import Gmak8Kubernetes

struct NodeImagesTests {
    @Test func emptyCopyMatchesDesign() {
        #expect(ImagesCopy.empty == "Load an OCI or Docker tarball, or gmak8 build an image.")
        #expect(!ImagesCopy.empty.lowercased().contains("docker desktop"))
        #expect(!ImagesCopy.empty.lowercased().contains("kind"))
    }

    @Test func systemMatcherHidesRancherAndKeepsUser() {
        #expect(
            SystemImageMatcher.isSystem(refs: ["docker.io/rancher/mirrored-pause:3.6"])
        )
        #expect(SystemImageMatcher.isSystem(refs: ["rancher/klipper-lb:v0.4.13"]))
        #expect(!SystemImageMatcher.isSystem(refs: ["docker.io/library/nginx:dev"]))
        #expect(!SystemImageMatcher.isSystem(refs: ["ghcr.io/example/app:1"]))
    }

    @Test func sampleHidesSystemByDefault() {
        let visible = FakeNodeImages.sample.filter { !$0.system }
        #expect(visible.map(\.displayName) == ["nginx:dev"])
    }
}
