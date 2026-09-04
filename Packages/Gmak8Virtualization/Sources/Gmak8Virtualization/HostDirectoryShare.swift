import Foundation

public struct HostDirectoryShare: Equatable, Sendable {
    public var tag: String
    public var url: URL
    public var readOnly: Bool

    public init(tag: String, url: URL, readOnly: Bool = false) {
        self.tag = tag
        self.url = url
        self.readOnly = readOnly
    }
}
