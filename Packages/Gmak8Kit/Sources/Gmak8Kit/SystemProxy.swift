import Foundation
import SystemConfiguration

public struct GuestProxyEnv: Equatable, Sendable {
    public var httpProxy: String?
    public var httpsProxy: String?
    public var noProxy: String

    public init(httpProxy: String? = nil, httpsProxy: String? = nil, noProxy: String = GuestProxyEnv.defaultNoProxy) {
        self.httpProxy = httpProxy
        self.httpsProxy = httpsProxy
        self.noProxy = noProxy
    }

    public static let defaultNoProxy =
        "127.0.0.1,localhost,192.168.127.0/24,10.42.0.0/16,10.43.0.0/16,.svc,.cluster.local"

    public var fileContents: String {
        var lines: [String] = []
        if let httpProxy, !httpProxy.isEmpty {
            lines.append("HTTP_PROXY=\(httpProxy)")
        }
        if let httpsProxy, !httpsProxy.isEmpty {
            lines.append("HTTPS_PROXY=\(httpsProxy)")
        }
        lines.append("NO_PROXY=\(noProxy)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

public enum SystemProxy {
    public static func fromProxySettings(_ settings: [String: Any]) -> GuestProxyEnv {
        let http = proxyURL(
            enabled: bool(settings["HTTPEnable"]),
            host: string(settings["HTTPProxy"]),
            port: int(settings["HTTPPort"]),
            scheme: "http"
        )
        let https = proxyURL(
            enabled: bool(settings["HTTPSEnable"]),
            host: string(settings["HTTPSProxy"]),
            port: int(settings["HTTPSPort"]),
            scheme: "https"
        )
        var noProxy = GuestProxyEnv.defaultNoProxy
        if let exceptions = settings["ExceptionsList"] as? [String], !exceptions.isEmpty {
            noProxy = (exceptions + GuestProxyEnv.defaultNoProxy.split(separator: ",").map(String.init))
                .joined(separator: ",")
        }
        return GuestProxyEnv(httpProxy: http, httpsProxy: https ?? http, noProxy: noProxy)
    }

    public static func fromSystem() -> GuestProxyEnv {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            return GuestProxyEnv()
        }
        return fromProxySettings(settings)
    }

    private static func proxyURL(enabled: Bool, host: String?, port: Int?, scheme: String) -> String? {
        guard enabled, let host, !host.isEmpty else {
            return nil
        }
        let portPart: String
        if let port, port > 0 {
            portPart = ":\(port)"
        } else {
            portPart = ""
        }
        return "\(scheme)://\(host)\(portPart)"
    }

    private static func bool(_ value: Any?) -> Bool {
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
