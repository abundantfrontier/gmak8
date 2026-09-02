package main

// AgentVsockPort is the virtio-vsock HTTP control plane. gvproxy is vfkit
// unixgram, not vsock. BuildkitVsockPort is reserved for buildkitd (later PR).
const (
	AgentVsockPort    = 1024
	BuildkitVsockPort = 1025
)

const dataMountPoint = "/mnt/data"
const dataLabel = "GMAK8_DATA"
const kvmDevicePath = "/dev/kvm"
const labelByPath = "/dev/disk/by-label/" + dataLabel
const mountinfoPath = "/proc/self/mountinfo"
