package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	k3sBinaryPath        = "/usr/local/bin/k3s"
	k3sKubeconfigPath    = "/etc/rancher/k3s/k3s.yaml"
	k3sDataDir           = "/mnt/data/rancher"
	k3sServerDBDir       = "/mnt/data/rancher/server/db"
	k3sVersionFile       = "/mnt/data/rancher/server/k3s-version"
	k3sPinVersion        = "v1.33.3+k3s1"
	shippedDataDirMinor  = "1.33"
	k3sCommandTimeout    = 5 * time.Second
	k3sStartQueueTimeout = 15 * time.Second
)

var k8sVersionPattern = regexp.MustCompile(`v1\.\d+\.\d+\+k3s\d+`)

// K3sReport is GET /k3s. DataDirMinor is empty when the data dir is new
// or the on-disk Kubernetes minor cannot be read.
type K3sReport struct {
	Active        bool   `json:"active"`
	Version       string `json:"version,omitempty"`
	DataDirMinor  string `json:"data_dir_minor,omitempty"`
	DataDirExists bool   `json:"data_dir_exists"`
}

type NodeReport struct {
	Ready bool   `json:"ready"`
	Name  string `json:"name,omitempty"`
}

func (h *realHost) Kubeconfig() ([]byte, error) {
	return os.ReadFile(h.kubeconfigPath)
}

func (h *realHost) K3s() K3sReport {
	report := K3sReport{
		Active:        systemdActive("k3s"),
		Version:       k3sBinaryVersion(h.k3sPath),
		DataDirExists: dirHasEntries(h.serverDBDir),
	}
	if minor := readDataDirMinor(h.k3sVersionFile, h.serverDBDir, h.k3sPath, h.kubeconfigPath, report.Active); minor != "" {
		report.DataDirMinor = minor
	}
	return report
}

func (h *realHost) StartK3s() error {
	path, err := exec.LookPath("systemctl")
	if err != nil {
		return fmt.Errorf("systemctl: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), k3sStartQueueTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, "start", "--no-block", "k3s")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemctl start k3s: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func (h *realHost) Node() NodeReport {
	path := h.k3sPath
	if path == "" {
		path = k3sBinaryPath
	}
	out, err := runK3sKubectl(path, h.kubeconfigPath, "get", "nodes", "-o", "json")
	if err != nil {
		return NodeReport{}
	}
	return parseNodeList(out)
}

func checkDataDirCompatible(h *realHost) error {
	exists := dirHasEntries(h.serverDBDir)
	minor := readDataDirMinor(h.k3sVersionFile, h.serverDBDir, h.k3sPath, h.kubeconfigPath, false)
	if !exists {
		return nil
	}
	if minor == "" {
		return fmt.Errorf("on-disk k3s data exists but Kubernetes version could not be read; Reset the cluster or install a matching gmak8/guest pair")
	}
	if minor != shippedDataDirMinor {
		return fmt.Errorf("on-disk k3s data is Kubernetes %s, but this appliance ships %s (accepts %s); Reset the cluster or install a matching gmak8/guest pair", minor, k3sPinVersion, shippedDataDirMinor)
	}
	return nil
}

func systemdActive(unit string) bool {
	path, err := exec.LookPath("systemctl")
	if err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), k3sCommandTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, "is-active", "--quiet", unit)
	return cmd.Run() == nil
}

func k3sBinaryVersion(k3sPath string) string {
	if k3sPath == "" {
		k3sPath = k3sBinaryPath
	}
	ctx, cancel := context.WithTimeout(context.Background(), k3sCommandTimeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, k3sPath, "--version").Output()
	if err != nil {
		return ""
	}
	return parseK3sVersionLine(string(out))
}

func readDataDirMinor(versionFile, dbDir, k3sPath, kubeconfig string, active bool) string {
	if b, err := os.ReadFile(versionFile); err == nil {
		if m := kubernetesMinor(string(b)); m != "" {
			return m
		}
	}
	if m := preferredScannedMinor(scanDBMinors(dbDir)); m != "" {
		return m
	}
	if active {
		if v := kubectlServerVersion(k3sPath, kubeconfig); v != "" {
			return kubernetesMinor(v)
		}
	}
	return ""
}

func preferredScannedMinor(minors []string) string {
	if len(minors) == 0 {
		return ""
	}
	for _, m := range minors {
		if m != shippedDataDirMinor {
			return m
		}
	}
	return minors[0]
}

func scanDBMinors(dbDir string) []string {
	entries, err := os.ReadDir(dbDir)
	if err != nil {
		return nil
	}
	seen := map[string]struct{}{}
	var minors []string
	for _, entry := range entries {
		if entry.IsDir() || !isKineScanFile(entry.Name()) {
			continue
		}
		for _, m := range scanFileMinors(filepath.Join(dbDir, entry.Name())) {
			if _, ok := seen[m]; ok {
				continue
			}
			seen[m] = struct{}{}
			minors = append(minors, m)
		}
	}
	return minors
}

func isKineScanFile(name string) bool {
	return name == "state.db" || name == "state.db-wal"
}

func scanFileMinors(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	buf := make([]byte, 1<<20)
	leftover := make([]byte, 0, 64)
	var minors []string
	seen := map[string]struct{}{}
	for {
		n, err := f.Read(buf)
		if n > 0 {
			chunk := append(leftover, buf[:n]...)
			for _, match := range k8sVersionPattern.FindAll(chunk, -1) {
				m := kubernetesMinor(string(match))
				if m == "" {
					continue
				}
				if _, ok := seen[m]; ok {
					continue
				}
				seen[m] = struct{}{}
				minors = append(minors, m)
			}
			if len(chunk) > 32 {
				leftover = append(leftover[:0], chunk[len(chunk)-32:]...)
			} else {
				leftover = append(leftover[:0], chunk...)
			}
		}
		if err != nil {
			break
		}
	}
	return minors
}

func kubectlServerVersion(k3sPath, kubeconfig string) string {
	out, err := runK3sKubectl(k3sPath, kubeconfig, "version", "-o", "json")
	if err != nil {
		return ""
	}
	var payload struct {
		ServerVersion struct {
			GitVersion string `json:"gitVersion"`
		} `json:"serverVersion"`
	}
	if err := json.Unmarshal(out, &payload); err != nil {
		return ""
	}
	return payload.ServerVersion.GitVersion
}

func runK3sKubectl(k3sPath, kubeconfig string, args ...string) ([]byte, error) {
	if k3sPath == "" {
		k3sPath = k3sBinaryPath
	}
	ctx, cancel := context.WithTimeout(context.Background(), k3sCommandTimeout)
	defer cancel()
	all := append([]string{"kubectl", "--request-timeout=5s"}, args...)
	cmd := exec.CommandContext(ctx, k3sPath, all...)
	cmd.Env = append(os.Environ(), "KUBECONFIG="+kubeconfig)
	return cmd.Output()
}

func parseK3sVersionLine(out string) string {
	for _, field := range strings.Fields(out) {
		if strings.HasPrefix(field, "v") && strings.Contains(field, ".") {
			return strings.TrimRight(field, ",")
		}
	}
	return ""
}

func kubernetesMinor(version string) string {
	for _, field := range strings.Fields(version) {
		field = strings.TrimPrefix(strings.TrimRight(field, ","), "v")
		parts := strings.SplitN(field, ".", 3)
		if len(parts) < 2 {
			continue
		}
		major := parts[0]
		minor := strings.Split(parts[1], "+")[0]
		if !isDigits(major) || !isDigits(minor) {
			continue
		}
		return major + "." + minor
	}
	return ""
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func dirHasEntries(path string) bool {
	entries, err := os.ReadDir(path)
	if err != nil {
		return false
	}
	return len(entries) > 0
}

func parseNodeList(data []byte) NodeReport {
	var list struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Status struct {
				Conditions []struct {
					Type   string `json:"type"`
					Status string `json:"status"`
				} `json:"conditions"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := json.Unmarshal(data, &list); err != nil {
		return NodeReport{}
	}
	var fallback NodeReport
	for _, item := range list.Items {
		ready := nodeReady(item.Status.Conditions)
		report := NodeReport{Ready: ready, Name: item.Metadata.Name}
		if item.Metadata.Name == "gmak8" {
			return report
		}
		if fallback.Name == "" {
			fallback = report
		}
	}
	return fallback
}

func nodeReady(conditions []struct {
	Type   string `json:"type"`
	Status string `json:"status"`
}) bool {
	for _, c := range conditions {
		if c.Type == "Ready" {
			return c.Status == "True"
		}
	}
	return false
}
