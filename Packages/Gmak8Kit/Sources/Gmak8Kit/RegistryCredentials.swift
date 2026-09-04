import Foundation
import Security

public struct RegistryHost: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var host: String
    public var username: String

    public var id: String { host }

    public init(host: String, username: String) {
        self.host = host
        self.username = username
    }
}

public enum RegistryKeychain {
    public static let service = "dev.gmak8.app.registry"

    public static func setPassword(_ password: String, host: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RegistryKeychainError.unhandled(status)
        }
    }

    public static func password(host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(host: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum RegistryKeychainError: Error, Equatable, Sendable {
    case unhandled(OSStatus)
}

public enum RegistriesFile {
    public static func render(userYAML: String, hosts: [RegistryHost], password: (String) -> String?) -> String {
        var body = userYAML.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.lowercased().contains("password:") {
            body = stripPasswordLines(body)
        }
        let authed = hosts.filter { host in
            !(password(host.host) ?? "").isEmpty && !host.username.isEmpty
        }
        if authed.isEmpty {
            return body.isEmpty ? "" : body + "\n"
        }
        var lines = body.isEmpty ? ["mirrors: {}"] : [body]
        lines.append("configs:")
        for host in authed {
            guard let secret = password(host.host) else {
                continue
            }
            lines.append("  \(host.host):")
            lines.append("    auth:")
            lines.append("      username: \(host.username)")
            lines.append("      password: \(secret)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func stripPasswordLines(_ yaml: String) -> String {
        yaml.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.lowercased().contains("password:") }
            .joined(separator: "\n")
    }
}
