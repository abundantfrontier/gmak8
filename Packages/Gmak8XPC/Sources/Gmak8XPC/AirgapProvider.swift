import Foundation
import Gmak8Kit

public struct AirgapLocalArchive: Equatable, Sendable {
    public var url: URL
    public var fileName: String
    public var byteCount: Int64

    public init(url: URL, fileName: String, byteCount: Int64) {
        self.url = url
        self.fileName = fileName
        self.byteCount = byteCount
    }
}

public protocol AirgapProviding: Sendable {
    func resolvedArchive() throws -> AirgapLocalArchive
}

public struct HostAirgapProvider: AirgapProviding {
    public var paths: HostPaths
    public var pin: AirgapPin
    public var publicKeyPEM: String

    public init(paths: HostPaths, pin: AirgapPin = .bundled, publicKeyPEM: String? = nil) {
        self.paths = paths
        self.pin = pin
        self.publicKeyPEM = publicKeyPEM ?? ((try? CosignPin.loadPublicKeyPEM()) ?? "")
    }

    public func resolvedArchive() throws -> AirgapLocalArchive {
        let store = AirgapStore(paths: paths, pin: pin, publicKeyPEM: publicKeyPEM)
        guard let url = try store.cachedFileIfValid() else {
            throw AirgapError.missingArchive(store.archiveURL.path(percentEncoded: false))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return AirgapLocalArchive(url: url, fileName: pin.fileName, byteCount: size)
    }
}
