import Foundation

public enum VMDefaults {
    public static let suiteName = "dev.gmak8.core"

    /// Hidden bring-up override: `defaults write dev.gmak8.core osImage /path/to/disk.raw`.
    public static let osImageKey = "osImage"

    public static func osImageURL(defaults: UserDefaults? = nil) -> URL? {
        let store = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        guard let path = store.string(forKey: osImageKey) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed)
    }
}
