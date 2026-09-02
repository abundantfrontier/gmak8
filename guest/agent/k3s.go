package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"strings"
)

const (
	k3sBinaryPath     = "/usr/local/bin/k3s"
	k3sKubeconfigPath = "/etc/rancher/k3s/k3s.yaml"
	k3sDataDir        = "/mnt/data/rancher"
	k3sServerDBDir    = "/mnt/data/rancher/server/db"
	k3sVersionFile    = "/mnt/data/rancher/server/k3s-version"
)

// K3sReport is GET /k3s. DataDirMinor is empty when the data dir is new
// or the on-disk Kubernetes minor cannot be read yet.
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
	if minor := readDataDirMinor(h.k3sVersionFile, h.k3sPath, report.Active); minor != "" {
		report.DataDirMinor = minor
	}
	return report
}

func (h *realHost) Node() NodeReport {
	path := h.k3sPath
	if path == "" {
		path = k3sBinaryPath
	}
	cmd := exec.Command(path, "kubectl", "get", "nodes", "-o", "json")
	cmd.Env = append(os.Environ(), "KUBECONFIG="+h.kubeconfigPath)
	out, err := cmd.Output()
	if err != nil {
		return NodeReport{}
	}
	return parseNodeList(out)
}

func systemdActive(unit string) bool {
	path, err := exec.LookPath("systemctl")
	if err != nil {
		return false
	}
	cmd := exec.Command(path, "is-active", "--quiet", unit)
	return cmd.Run() == nil
}

func k3sBinaryVersion(k3sPath string) string {
	if k3sPath == "" {
		k3sPath = k3sBinaryPath
	}
	out, err := exec.Command(k3sPath, "--version").Output()
	if err != nil {
		return ""
	}
	return parseK3sVersionLine(string(out))
}

func readDataDirMinor(versionFile, k3sPath string, active bool) string {
	if b, err := os.ReadFile(versionFile); err == nil {
		if m := kubernetesMinor(string(b)); m != "" {
			return m
		}
	}
	if active {
		if v := kubectlServerVersion(k3sPath); v != "" {
			return kubernetesMinor(v)
		}
	}
	return ""
}

func kubectlServerVersion(k3sPath string) string {
	if k3sPath == "" {
		k3sPath = k3sBinaryPath
	}
	out, err := exec.Command(k3sPath, "kubectl", "version", "-o", "json").Output()
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
