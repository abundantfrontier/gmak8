package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode"
)

const (
	k3sImagesDir           = "/mnt/data/rancher/agent/images"
	dataTmpDir             = "/mnt/data/tmp"
	maxAirgapBytes         = 500 * 1024 * 1024
	maxKubevirtAirgapBytes = 1500 * 1024 * 1024
	defaultAirgapName      = "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"
)

// AirgapReport is GET /airgap. Present is true when k3s can import from agent/images.
type AirgapReport struct {
	Present bool     `json:"present"`
	Files   []string `json:"files"`
	Bytes   uint64   `json:"bytes"`
}

func (h *realHost) Airgap() AirgapReport {
	return listAirgap(h.imagesDir)
}

func (h *realHost) ImportAirgap(name string, r io.Reader, size int64) (AirgapReport, error) {
	clean, err := sanitizeAirgapName(name)
	if err != nil {
		return AirgapReport{}, err
	}
	max := int64(maxAirgapBytes)
	if strings.Contains(strings.ToLower(clean), "kubevirt") {
		max = maxKubevirtAirgapBytes
	}
	if size <= 0 || size > max {
		return AirgapReport{}, fmt.Errorf("airgap archive exceeds size budget")
	}
	disks := h.Disks()
	if disks.Gmak8Data != diskMounted {
		return AirgapReport{}, fmt.Errorf("data disk is not mounted")
	}
	needed := uint64(size) + uint64(size)/5
	if disks.BytesFree < needed {
		return AirgapReport{}, fmt.Errorf("data disk has %d bytes free; airgap import needs %d (archive + 20%%)", disks.BytesFree, needed)
	}
	if err := os.MkdirAll(h.imagesDir, 0o755); err != nil {
		return AirgapReport{}, err
	}
	if err := os.MkdirAll(h.tmpDir, 0o755); err != nil {
		return AirgapReport{}, err
	}
	tmpPath := filepath.Join(h.tmpDir, "."+clean+".tmp")
	_ = os.Remove(tmpPath)
	tmp, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return AirgapReport{}, err
	}
	ok := false
	defer func() {
		_ = tmp.Close()
		if !ok {
			_ = os.Remove(tmpPath)
		}
	}()
	if err := tmp.Chmod(0o600); err != nil {
		return AirgapReport{}, err
	}
	wrote, err := io.Copy(tmp, io.LimitReader(r, size))
	if err != nil {
		return AirgapReport{}, err
	}
	if wrote != size {
		return AirgapReport{}, fmt.Errorf("short airgap write: got %d want %d", wrote, size)
	}
	if err := tmp.Sync(); err != nil {
		return AirgapReport{}, err
	}
	if err := tmp.Close(); err != nil {
		return AirgapReport{}, err
	}
	dest := filepath.Join(h.imagesDir, clean)
	if err := os.Rename(tmpPath, dest); err != nil {
		return AirgapReport{}, err
	}
	ok = true
	_ = fsyncDir(h.imagesDir)
	return listAirgap(h.imagesDir), nil
}

func listAirgap(dir string) AirgapReport {
	report := AirgapReport{Files: []string{}}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return report
	}
	var total uint64
	for _, entry := range entries {
		if entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		if !isAirgapArchiveName(entry.Name()) {
			continue
		}
		info, err := entry.Info()
		if err != nil || info.Size() <= 0 {
			continue
		}
		report.Files = append(report.Files, entry.Name())
		total += uint64(info.Size())
	}
	report.Bytes = total
	report.Present = len(report.Files) > 0
	return report
}

func sanitizeAirgapName(name string) (string, error) {
	if name == "" {
		name = defaultAirgapName
	}
	if strings.ContainsAny(name, `/\`) || strings.Contains(name, "..") {
		return "", fmt.Errorf("invalid airgap name")
	}
	name = filepath.Base(name)
	if name == "." || name == ".." {
		return "", fmt.Errorf("invalid airgap name")
	}
	if !isAirgapArchiveName(name) {
		return "", fmt.Errorf("airgap name must end in .tar, .tar.gz, or .tar.zst")
	}
	for _, c := range name {
		if unicode.IsLetter(c) || unicode.IsDigit(c) || c == '.' || c == '-' || c == '_' {
			continue
		}
		return "", fmt.Errorf("invalid airgap name")
	}
	return name, nil
}

func isAirgapArchiveName(name string) bool {
	lower := strings.ToLower(name)
	return strings.HasSuffix(lower, ".tar.zst") || strings.HasSuffix(lower, ".tar.gz") || strings.HasSuffix(lower, ".tar")
}

func fsyncDir(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return f.Sync()
}
