import Virtualization

/// Nested virt is a macOS 15+ / M3+ VZ feature. The app stays macOS 14+; this
/// type gates the API and never enables the flag when the platform reports false.
public enum NestedVirtualization {
    public static var isSupported: Bool {
        if #available(macOS 15.0, *) {
            return VZGenericPlatformConfiguration.isNestedVirtualizationSupported
        }
        return false
    }

    public static func makePlatform() -> VZGenericPlatformConfiguration {
        let platform = VZGenericPlatformConfiguration()
        enableIfSupported(on: platform)
        return platform
    }

    public static func enableIfSupported(on platform: VZGenericPlatformConfiguration) {
        if #available(macOS 15.0, *) {
            if VZGenericPlatformConfiguration.isNestedVirtualizationSupported {
                platform.isNestedVirtualizationEnabled = true
            }
        }
    }
}
