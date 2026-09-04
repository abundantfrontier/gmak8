package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestKubevirtApplyOrderHasNoGitHubFetch(t *testing.T) {
	src, err := os.ReadFile("kubevirt.go")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(src), "https://github.com/kubevirt") {
		t.Fatal("installer must not curl GitHub at runtime")
	}
}

func TestInstallKubeVirtAppliesYAMLAndChecksU1Nano(t *testing.T) {
	dir := t.TempDir()
	for _, name := range kubevirtApplyOrder {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("# "+name+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	var applied []string
	h := defaultHost()
	h.kubevirtDir = dir
	h.kubevirtPoll = time.Millisecond
	h.kubectl = func(args ...string) ([]byte, error) {
		joined := strings.Join(args, " ")
		if len(args) >= 2 && args[0] == "apply" {
			applied = append(applied, args[len(args)-1])
			return []byte("applied"), nil
		}
		if strings.Contains(joined, "get kubevirt") {
			return []byte("Deployed"), nil
		}
		if strings.Contains(joined, "virtualmachineclusterinstancetype") {
			return []byte("u1.nano"), nil
		}
		return []byte(""), nil
	}
	report, err := h.InstallKubeVirt()
	if err != nil {
		t.Fatal(err)
	}
	if !report.Installed || report.Phase != "Deployed" || !report.U1Nano {
		t.Fatalf("%+v", report)
	}
	if len(applied) != len(kubevirtApplyOrder) {
		t.Fatalf("applied %d want %d %v", len(applied), len(kubevirtApplyOrder), applied)
	}
}

func TestInstallKubeVirtImportsMatchingAirgapTar(t *testing.T) {
	dir := t.TempDir()
	images := t.TempDir()
	if err := os.WriteFile(filepath.Join(images, "gmak8-kubevirt-airgap-1.6.1-arm64.tar"), []byte("tar"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(images, "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"), []byte("k3s"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, name := range kubevirtApplyOrder {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	var ctr []string
	h := defaultHost()
	h.kubevirtDir = dir
	h.imagesDir = images
	h.kubevirtPoll = time.Millisecond
	h.kubectl = func(args ...string) ([]byte, error) {
		joined := strings.Join(args, " ")
		if strings.Contains(joined, "get kubevirt") {
			return []byte("Deployed"), nil
		}
		if strings.Contains(joined, "virtualmachineclusterinstancetype") {
			return []byte("u1.nano"), nil
		}
		return []byte("ok"), nil
	}
	h.runCtr = func(_ time.Duration, args ...string) ([]byte, error) {
		ctr = append(ctr, strings.Join(args, " "))
		return nil, nil
	}
	if _, err := h.InstallKubeVirt(); err != nil {
		t.Fatal(err)
	}
	if len(ctr) != 1 || !strings.Contains(ctr[0], "gmak8-kubevirt-airgap") || strings.Contains(ctr[0], "k3s-airgap") {
		t.Fatalf("ctr %v", ctr)
	}
}

func TestVendoredYAMLHasFeatureGatesAndU1Nano(t *testing.T) {
	root := filepath.Join("..", "kubevirt", "yaml")
	cr, err := os.ReadFile(filepath.Join(root, "kubevirt-cr.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(cr)
	if !strings.Contains(text, "VMExport") || !strings.Contains(text, "EnableVirtioFsConfigVolumes") {
		t.Fatal(text)
	}
	profile, err := os.ReadFile(filepath.Join(root, "local-path-storageprofile.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(profile), "cloneStrategy: copy") || !strings.Contains(string(profile), "name: local-path") {
		t.Fatal(string(profile))
	}
	it, err := os.ReadFile(filepath.Join(root, "common-clusterinstancetypes.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(it), "kind: VirtualMachineClusterInstancetype") || !strings.Contains(string(it), "name: u1.nano") {
		t.Fatal("missing cluster u1.nano")
	}
}

func TestInstallKubeVirtReturnsBeforePhaseDeployed(t *testing.T) {
	dir := t.TempDir()
	for _, name := range kubevirtApplyOrder {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	gets := 0
	h := defaultHost()
	h.kubevirtDir = dir
	h.kubevirtPoll = time.Millisecond
	h.kubectl = func(args ...string) ([]byte, error) {
		joined := strings.Join(args, " ")
		if len(args) >= 2 && args[0] == "apply" {
			return []byte("applied"), nil
		}
		if strings.Contains(joined, "get kubevirt") {
			gets++
			return []byte(""), nil
		}
		if strings.Contains(joined, "virtualmachineclusterinstancetype") {
			return []byte("u1.nano"), nil
		}
		return []byte(""), nil
	}
	report, err := h.InstallKubeVirt()
	if err != nil {
		t.Fatal(err)
	}
	if report.Phase != "" || !report.U1Nano {
		t.Fatalf("%+v", report)
	}
	if gets != 1 {
		t.Fatalf("phase probes %d; install must not poll Deployed", gets)
	}
}
