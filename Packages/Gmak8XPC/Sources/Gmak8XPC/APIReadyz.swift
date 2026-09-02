import Foundation

/// Host-side `https://127.0.0.1:<api-port>/readyz`. Never runs on `dev.gmak8.vm`.
public enum APIReadyz {
    public static func isReady(port: Int) async -> Bool {
        guard let url = URL(string: "https://127.0.0.1:\(port)/readyz") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let session = URLSession(
            configuration: .ephemeral,
            delegate: TrustGuestCertDelegate.shared,
            delegateQueue: nil
        )
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 || status == 401 || status == 403
        } catch {
            return false
        }
    }
}

private final class TrustGuestCertDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = TrustGuestCertDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
