package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	kubevirtYAMLDir        = "/usr/local/share/gmak8/kubevirt"
	kubevirtApplyTimeout   = 2 * time.Minute
	kubevirtNamespace      = "kubevirt"
	kubevirtName           = "kubevirt"
	kubevirtApplyOrderFile = "apply-order.txt"
)

var kubevirtApplyOrder = []string{
	"kubevirt-operator.yaml",
	"kubevirt-cr.yaml",
	"cdi-operator.yaml",
	"cdi-cr.yaml",
	"local-path-storageprofile.yaml",
	"common-clusterinstancetypes.yaml",
	"common-clusterpreferences.yaml",
}

// KubeVirtReport is GET /kubevirt.
type KubeVirtReport struct {
	Installed bool   `json:"installed"`
	Phase     string `json:"phase,omitempty"`
	U1Nano    bool   `json:"u1_nano"`
	KVM       bool   `json:"kvm"`
}

func (h *realHost) KubeVirt() (KubeVirtReport, error) {
	report := KubeVirtReport{KVM: h.KVM()}
	phase, err := h.kubevirtPhase()
	if err == nil && phase != "" {
		report.Installed = true
		report.Phase = phase
	}
	report.U1Nano = h.hasU1Nano()
	return report, nil
}

func (h *realHost) InstallKubeVirt() (KubeVirtReport, error) {
	if err := h.importKubevirtImages(); err != nil {
		return KubeVirtReport{}, err
	}
	dir := h.kubevirtYAMLDir()
	for _, name := range kubevirtApplyFiles(dir) {
		path := filepath.Join(dir, name)
		if _, err := os.Stat(path); err != nil {
			return KubeVirtReport{}, fmt.Errorf("kubevirt yaml %s: %w", name, err)
		}
		if err := h.kubectlApply(path); err != nil {
			return KubeVirtReport{}, err
		}
	}
	return h.KubeVirt()
}

func (h *realHost) kubevirtYAMLDir() string {
	if h.kubevirtDir != "" {
		return h.kubevirtDir
	}
	return kubevirtYAMLDir
}

func (h *realHost) kubectlApply(path string) error {
	attempts := 8
	var last error
	for i := 0; i < attempts; i++ {
		_, err := h.runKubectl("apply", "--server-side", "--force-conflicts", "-f", path)
		if err != nil {
			_, err = h.runKubectl("apply", "-f", path)
		}
		if err == nil {
			return nil
		}
		last = err
		if i == attempts-1 {
			break
		}
		d := h.kubevirtPoll
		if d == 0 {
			d = 2 * time.Second
		}
		time.Sleep(d)
	}
	return fmt.Errorf("kubectl apply %s: %w", filepath.Base(path), last)
}

func (h *realHost) runKubectl(args ...string) ([]byte, error) {
	if h.kubectl != nil {
		return h.kubectl(args...)
	}
	k3sPath := h.k3sPath
	if k3sPath == "" {
		k3sPath = k3sBinaryPath
	}
	ctx, cancel := context.WithTimeout(context.Background(), kubevirtApplyTimeout)
	defer cancel()
	all := append([]string{"kubectl", "--request-timeout=60s"}, args...)
	cmd := exec.CommandContext(ctx, k3sPath, all...)
	cmd.Env = append(os.Environ(), "KUBECONFIG="+h.kubeconfigPath)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return out, fmt.Errorf("%w: %s", err, strings.TrimSpace(string(out)))
	}
	return out, nil
}

func (h *realHost) kubevirtPhase() (string, error) {
	out, err := h.runKubectl(
		"get", "kubevirt", kubevirtName, "-n", kubevirtNamespace,
		"-o", "jsonpath={.status.phase}",
	)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func (h *realHost) hasU1Nano() bool {
	out, err := h.runKubectl("get", "virtualmachineclusterinstancetype", "u1.nano")
	return err == nil && strings.Contains(string(out), "u1.nano")
}

func (h *realHost) importKubevirtImages() error {
	dir := h.imagesDir
	if dir == "" {
		dir = k3sImagesDir
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !isAirgapArchiveName(name) || !strings.Contains(strings.ToLower(name), "kubevirt") {
			continue
		}
		path := filepath.Join(dir, name)
		if _, err := h.ctr(kubevirtApplyTimeout, "images", "import", path); err != nil {
			return fmt.Errorf("import %s: %w", name, err)
		}
	}
	return nil
}

func kubevirtApplyFiles(dir string) []string {
	orderPath := filepath.Join(dir, kubevirtApplyOrderFile)
	data, err := os.ReadFile(orderPath)
	if err != nil {
		return kubevirtApplyOrder
	}
	var files []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		files = append(files, line)
	}
	if len(files) == 0 {
		return kubevirtApplyOrder
	}
	return files
}
