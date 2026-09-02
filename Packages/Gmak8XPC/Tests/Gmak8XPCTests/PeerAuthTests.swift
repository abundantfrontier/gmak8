import Darwin
import Testing

@testable import Gmak8XPC

struct PeerAuthTests {
    @Test func matchingTeamIDsAreAccepted() {
        let policy = PeerAuthPolicy()
        let daemon = PeerIdentity(pid: 1, teamID: "ABCDE12345")
        let peer = PeerIdentity(pid: 2, teamID: "ABCDE12345")
        #expect(policy.isAuthorized(peer: peer, daemon: daemon))
    }

    @Test func mismatchedTeamIDsAreRejected() {
        let policy = PeerAuthPolicy()
        let daemon = PeerIdentity(pid: 1, teamID: "ABCDE12345")
        let peer = PeerIdentity(pid: 2, teamID: "OTHER00000")
        #expect(!policy.isAuthorized(peer: peer, daemon: daemon))
    }

    @Test func emptyTeamIDsMatchForAdHocDevBuilds() {
        let policy = PeerAuthPolicy()
        let daemon = PeerIdentity(pid: 1, teamID: nil)
        let peer = PeerIdentity(pid: 2, teamID: nil)
        #expect(policy.isAuthorized(peer: peer, daemon: daemon))
    }

    @Test func unsignedPeerIsRejectedWhenDaemonHasTeamID() {
        let policy = PeerAuthPolicy()
        let daemon = PeerIdentity(pid: 1, teamID: "ABCDE12345")
        let peer = PeerIdentity(pid: 2, teamID: nil)
        #expect(!policy.isAuthorized(peer: peer, daemon: daemon))
    }

    @Test func sameProcessSecCodeIdentitiesMatch() throws {
        let resolver = SecCodePeerIdentityResolver()
        let pid = getpid()
        let selfIdentity = try resolver.identity(for: pid)
        let policy = PeerAuthPolicy()
        #expect(policy.isAuthorized(peer: selfIdentity, daemon: selfIdentity))
        #expect(selfIdentity.pid == pid)
    }

    @Test func missingProcessThrowsUnauthorized() {
        let resolver = SecCodePeerIdentityResolver()
        #expect(throws: EngineErrorCode.unauthorized) {
            try resolver.identity(for: 2_000_000_000)
        }
    }
}
