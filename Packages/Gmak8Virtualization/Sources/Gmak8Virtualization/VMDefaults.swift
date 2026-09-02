import Foundation

public enum VMDefaults {
    /// Hidden bring-up override: `defaults write dev.gmak8.core osImage /path/to/disk.raw`.
    public static let osImageKey = "osImage"

    public static func osImageURL(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: osImageKey) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed)
    }
}
