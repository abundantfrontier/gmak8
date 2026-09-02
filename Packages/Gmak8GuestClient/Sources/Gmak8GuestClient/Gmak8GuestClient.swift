public enum Gmak8GuestClient {
    /// Guest agent HTTP over virtio-vsock. gvproxy is vfkit unixgram, not vsock.
    public static let agentVsockPort: UInt32 = 1024
    /// Reserved for guest buildkitd (not implemented in this package).
    public static let buildkitVsockPort: UInt32 = 1025
}
