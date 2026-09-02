import Darwin
import Foundation
import Security

public struct PeerIdentity: Equatable, Sendable {
    public var pid: pid_t
    public var teamID: String?

    public init(pid: pid_t, teamID: String?) {
        self.pid = pid
        self.teamID = teamID
    }
}

public protocol PeerIdentityResolving: Sendable {
    func identity(for pid: pid_t) throws -> PeerIdentity
}

public struct PeerAuthPolicy: Sendable {
    public init() {}

    /// Team IDs must match. Empty matches empty so ad-hoc/dev unsigned peers (UI + CLI) can connect;
    /// the unix socket is mode 0600 so same-uid is the other gate.
    public func isAuthorized(peer: PeerIdentity, daemon: PeerIdentity) -> Bool {
        peer.teamID == daemon.teamID
    }
}

public enum LocalPeerPID {
    public static var solLocal: Int32 { SOL_LOCAL }
    public static var option: Int32 { LOCAL_PEERPID }

    public static func processIdentifier(socketFD: Int32) throws -> pid_t {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        let result = getsockopt(socketFD, SOL_LOCAL, LOCAL_PEERPID, &pid, &length)
        guard result == 0, pid > 0 else {
            throw EngineErrorCode.unauthorized
        }
        return pid
    }
}

public struct FixedPeerIdentityResolver: PeerIdentityResolving, Sendable {
    public var teamID: String?

    public init(teamID: String?) {
        self.teamID = teamID
    }

    public func identity(for pid: pid_t) throws -> PeerIdentity {
        PeerIdentity(pid: pid, teamID: teamID)
    }
}

public struct SecCodePeerIdentityResolver: PeerIdentityResolving, Sendable {
    public init() {}

    public func identity(for pid: pid_t) throws -> PeerIdentity {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        guard copyStatus == errSecSuccess, let code else {
            throw EngineErrorCode.unauthorized
        }

        let validity = SecCodeCheckValidity(code, SecCSFlags(), nil)
        if validity == errSecCSUnsigned {
            return PeerIdentity(pid: pid, teamID: nil)
        }
        guard validity == errSecSuccess else {
            throw EngineErrorCode.unauthorized
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw EngineErrorCode.unauthorized
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard infoStatus == errSecSuccess, let information else {
            throw EngineErrorCode.unauthorized
        }

        let teamID = (information as NSDictionary)[kSecCodeInfoTeamIdentifier] as? String
        let normalized = teamID?.isEmpty == true ? nil : teamID
        return PeerIdentity(pid: pid, teamID: normalized)
    }
}
