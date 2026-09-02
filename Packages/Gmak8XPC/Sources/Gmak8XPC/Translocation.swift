import Foundation

public protocol TranslocationChecking: Sendable {
    func shouldRefuseRegister(bundleURL: URL) -> Bool
}

public struct TranslocationChecker: TranslocationChecking, Sendable {
    public init() {}

    public func shouldRefuseRegister(bundleURL: URL) -> Bool {
        isTranslocated(bundleURL) || !isInsideApplications(bundleURL)
    }

    public func isTranslocated(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.contains("/AppTranslocation/")
    }

    public func isInsideApplications(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        return path == "/Applications" || path.hasPrefix("/Applications/")
    }
}
