import Foundation

/// Try 127.0.0.1:6443 then 16443. Real bind failures are not treated as success.
public enum APIPortExpose {
    public static func choose(expose: (GVProxyExposeRequest) throws -> Void) throws -> Int {
        let primary = try GVProxyExposeRequest(
            hostPort: GuestNetwork.apiHostPort,
            guestPort: GuestNetwork.apiGuestPort
        )
        do {
            try expose(primary)
            return GuestNetwork.apiHostPort
        } catch {
            let fallback = try GVProxyExposeRequest(
                hostPort: GuestNetwork.apiFallbackHostPort,
                guestPort: GuestNetwork.apiGuestPort
            )
            try expose(fallback)
            return GuestNetwork.apiFallbackHostPort
        }
    }
}
