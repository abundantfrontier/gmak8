import Foundation

/// Pinned gvproxy/vfkit address plan. Do not change MAC, guest IP, or subnet independently.
public enum GuestNetwork {
    public static let subnet = "192.168.127.0/24"
    public static let gatewayIPv4 = "192.168.127.1"
    public static let guestIPv4 = "192.168.127.2"
    public static let guestMACAddress = "5a:94:ef:e4:0c:ee"
    public static let hostLoopback = "127.0.0.1"
    public static let mtu = 1500
    public static let anyAddress = "0.0.0.0"

    /// Host ports that would require a privileged helper. Never bind these on the Mac.
    public static let forbiddenHostPorts: Set<Int> = [22, 80, 443]

    public static let apiHostPort = 6443
    public static let apiFallbackHostPort = 16_443
    public static let apiGuestPort = 6443
    public static let httpHostPort = 8080
    public static let httpGuestPort = 80
    public static let httpsHostPort = 8443
    public static let httpsGuestPort = 443
}
