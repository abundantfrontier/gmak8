import Foundation

public enum EurekaProfileGate {
    public static func validateStart(
        settings: Settings,
        k3sYAML: String,
        host: HostSnapshot
    ) throws {
        switch settings.profile {
        case .kubernetes, .eurekaAPIOnly:
            return
        case .eureka:
            if case .refused(let refusal) = Profile.eureka.resourceDefaults(host: host) {
                throw refusal
            }
            if settings.disableLocalStorage || !K3sConfig.hasDataDiskLocalPath(k3sYAML) {
                throw ProfileRefusal.missingDataDiskLocalPath
            }
        }
    }

    public static func refusal(settings: Settings, host: HostSnapshot) -> ProfileRefusal? {
        switch settings.profile.resourceDefaults(host: host) {
        case .refused(let refusal):
            return refusal
        case .accepted:
            break
        }
        if settings.profile == .eureka, settings.disableLocalStorage {
            return .missingDataDiskLocalPath
        }
        return nil
    }
}
