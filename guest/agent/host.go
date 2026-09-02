package main

import (
	"fmt"
	"os/exec"
	"syscall"
	"time"
)

// Host is the guest environment the HTTP handlers inspect or mutate.
// Tests substitute a fake so they never set the clock or halt the machine.
type Host interface {
	Disks() DisksReport
	KVM() bool
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
	kvmPath       string
	mountPoint    string
	expectedLabel string
	labelSymlink  string
	mountinfoPath string
}

func defaultHost() *realHost {
	return &realHost{
		kvmPath:       kvmDevicePath,
		mountPoint:    dataMountPoint,
		expectedLabel: dataLabel,
		labelSymlink:  labelByPath,
		mountinfoPath: mountinfoPath,
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
