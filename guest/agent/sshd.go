package main

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

const sshUnit = "ssh"

// SSHDReport is GET /sshd.
type SSHDReport struct {
	Running bool `json:"running"`
}

func (h *realHost) SSHD() (SSHDReport, error) {
	active, err := h.systemctl("is-active", sshUnit)
	if err != nil {
		return SSHDReport{Running: false}, nil
	}
	return SSHDReport{Running: strings.TrimSpace(active) == "active"}, nil
}

func (h *realHost) StartSSHD() error {
	if _, err := h.systemctl("unmask", sshUnit); err != nil {
		return err
	}
	if _, err := h.systemctl("start", "--no-block", sshUnit); err != nil {
		return err
	}
	return nil
}

func (h *realHost) StopSSHD() error {
	_, err := h.systemctl("stop", "--no-block", sshUnit)
	return err
}

func (h *realHost) systemctl(args ...string) (string, error) {
	if h.runSystemctl != nil {
		return h.runSystemctl(args...)
	}
	path, err := exec.LookPath("systemctl")
	if err != nil {
		return "", fmt.Errorf("systemctl: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("systemctl %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}
