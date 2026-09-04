package main

import (
	"fmt"
	"io"
	"os/exec"
	"sync/atomic"
	"syscall"
	"time"
)

// Host is the guest environment the HTTP handlers inspect or mutate.
// Tests substitute a fake so they never set the clock or halt the machine.
type Host interface {
	Disks() DisksReport
	KVM() bool
	Kubeconfig() ([]byte, error)
	K3s() K3sReport
	StartK3s() error
	Node() NodeReport
	Airgap() AirgapReport
	ImportAirgap(name string, r io.Reader, size int64) (AirgapReport, error)
	ListImages() (ImageListReport, error)
	ImportImage(name string, r io.Reader, size int64) (ImageImportReport, error)
	PruneImages() (ImagePruneReport, error)
	HostMounts() (HostMountReport, error)
	ApplyHostMounts() (HostMountReport, error)
	KubeVirt() (KubeVirtReport, error)
	InstallKubeVirt() (KubeVirtReport, error)
	Services() (ServiceListReport, error)
	SetTime(t time.Time) error
	Shutdown() error
}

type okResponse struct {
	OK bool `json:"ok"`
}

type errorResponse struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

type kvmResponse struct {
	KVM bool `json:"kvm"`
}

type realHost struct {
	kvmPath        string
	mountPoint     string
	expectedLabel  string
	labelSymlink   string
	mountinfoPath  string
	kubeconfigPath string
	k3sPath        string
	serverDBDir    string
	k3sVersionFile string
	imagesDir      string
	tmpDir         string
	importing      atomic.Bool
	runCtr         func(timeout time.Duration, args ...string) ([]byte, error)
	hostMountsPath string
	runMount       func(args ...string) error
	kubevirtDir    string
	kubectl        func(args ...string) ([]byte, error)
	kubevirtPoll   time.Duration
}

func defaultHost() *realHost {
	return &realHost{
		kvmPath:        kvmDevicePath,
		mountPoint:     dataMountPoint,
		expectedLabel:  dataLabel,
		labelSymlink:   labelByPath,
		mountinfoPath:  mountinfoPath,
		kubeconfigPath: k3sKubeconfigPath,
		k3sPath:        k3sBinaryPath,
		serverDBDir:    k3sServerDBDir,
		k3sVersionFile: k3sVersionFile,
		imagesDir:      k3sImagesDir,
		tmpDir:         dataTmpDir,
		hostMountsPath: hostMountsFile,
	}
}

func (h *realHost) KVM() bool {
	return isCharDevice(h.kvmPath)
}

func (h *realHost) SetTime(t time.Time) error {
	tv := syscall.NsecToTimeval(t.UnixNano())
	if err := syscall.Settimeofday(&tv); err != nil {
		return err
	}
	// chrony may be present later; makestep is best-effort after SET_TIME.
	if path, err := exec.LookPath("chronyc"); err == nil {
		_ = exec.Command(path, "makestep").Run()
	}
	return nil
}

func (h *realHost) Shutdown() error {
	if path, err := exec.LookPath("systemctl"); err == nil {
		cmd := exec.Command(path, "poweroff", "--no-block")
		return cmd.Start()
	}
	if path, err := exec.LookPath("shutdown"); err == nil {
		cmd := exec.Command(path, "-h", "now")
		return cmd.Start()
	}
	return fmt.Errorf("no systemctl or shutdown in PATH")
}
