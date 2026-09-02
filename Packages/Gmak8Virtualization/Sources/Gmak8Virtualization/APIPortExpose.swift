import Foundation

/// Try a loopback host port, then one fallback. Bind failures are not treated as success.
public enum HostPortExpose {
    public static func choose(
        hostPort: Int,
        fallbackHostPort: Int,
        guestPort: Int,
        expose: (GVProxyExposeRequest) throws -> Void
    ) throws -> Int {
        let primary = try GVProxyExposeRequest(hostPort: hostPort, guestPort: guestPort)
        do {
            try expose(primary)
            return hostPort
        } catch {
            let fallback = try GVProxyExposeRequest(hostPort: fallbackHostPort, guestPort: guestPort)
            try expose(fallback)
            return fallbackHostPort
        }
    }
}

/// Try 127.0.0.1:6443 then 16443. Real bind failures are not treated as success.
public enum APIPortExpose {
    public static func choose(expose: (GVProxyExposeRequest) throws -> Void) throws -> Int {
        try HostPortExpose.choose(
            hostPort: GuestNetwork.apiHostPort,
            fallbackHostPort: GuestNetwork.apiFallbackHostPort,
            guestPort: GuestNetwork.apiGuestPort,
            expose: expose
        )
    }
}
