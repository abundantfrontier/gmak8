package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSanitizeAirgapName(t *testing.T) {
	got, err := sanitizeAirgapName("")
	if err != nil || got != defaultAirgapName {
		t.Fatalf("default %q %v", got, err)
	}
	got, err = sanitizeAirgapName("gmak8-k3s-airgap-v1.33.3-arm64.tar.zst")
	if err != nil || got != "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst" {
		t.Fatalf("got %q %v", got, err)
	}
	if _, err := sanitizeAirgapName("../escape.tar"); err == nil {
		t.Fatal("expected path traversal reject")
	}
	if _, err := sanitizeAirgapName("images.txt"); err == nil {
		t.Fatal("expected non-archive reject")
	}
}

func TestImportAirgapRejectsOversize(t *testing.T) {
	dir := t.TempDir()
	h := defaultHost()
	h.imagesDir = filepath.Join(dir, "images")
	h.tmpDir = filepath.Join(dir, "tmp")
	h.mountPoint = dir
	_, err := h.ImportAirgap("tiny.tar.zst", bytes.NewReader([]byte("x")), maxAirgapBytes+1)
	if err == nil || !strings.Contains(err.Error(), "size budget") {
		t.Fatalf("err %v", err)
	}
}

func TestListAirgapPresent(t *testing.T) {
	dir := t.TempDir()
	if listAirgap(dir).Present {
		t.Fatal("empty dir")
	}
	if err := os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if listAirgap(dir).Present {
		t.Fatal("non-archive must not count")
	}
	path := filepath.Join(dir, "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst")
	if err := os.WriteFile(path, []byte("tiny"), 0o600); err != nil {
		t.Fatal(err)
	}
	got := listAirgap(dir)
	if !got.Present || got.Bytes != 4 || len(got.Files) != 1 {
		t.Fatalf("got %+v", got)
	}
}

func TestImportAirgapWrites0600AndReports(t *testing.T) {
	dir := t.TempDir()
	images := filepath.Join(dir, "images")
	tmp := filepath.Join(dir, "tmp")
	mount := filepath.Join(dir, "mnt")
	if err := os.MkdirAll(mount, 0o755); err != nil {
		t.Fatal(err)
	}
	disk := filepath.Join(dir, "nvme1n1")
	if err := os.WriteFile(disk, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	label := filepath.Join(dir, "GMAK8_DATA")
	if err := os.Symlink(disk, label); err != nil {
		t.Fatal(err)
	}
	mountinfo := filepath.Join(dir, "mountinfo")
	content := "1 0 0:0 / " + mount + " rw - ext4 " + disk + " rw\n"
	if err := os.WriteFile(mountinfo, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	h := defaultHost()
	h.mountPoint = mount
	h.mountinfoPath = mountinfo
	h.labelSymlink = label
	h.imagesDir = images
	h.tmpDir = tmp

	body := []byte("tiny-airgap-fixture")
	report, err := h.ImportAirgap("gmak8-k3s-airgap-v1.33.3-arm64.tar.zst", bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	if !report.Present {
		t.Fatalf("report %+v", report)
	}
	dest := filepath.Join(images, "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst")
	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(body) {
		t.Fatalf("content %q", got)
	}
	st, err := os.Stat(dest)
	if err != nil {
		t.Fatal(err)
	}
	if st.Mode().Perm() != 0o600 {
		t.Fatalf("mode %o", st.Mode().Perm())
	}
	if leftovers, err := os.ReadDir(tmp); err != nil {
		t.Fatal(err)
	} else if len(leftovers) != 0 {
		t.Fatalf("temp leftovers %v", leftovers)
	}
}

func TestImportAirgapRefusesUnmountedDisk(t *testing.T) {
	dir := t.TempDir()
	images := filepath.Join(dir, "images")
	h := defaultHost()
	h.imagesDir = images
	h.tmpDir = filepath.Join(dir, "tmp")
	h.mountPoint = dir
	_, err := h.ImportAirgap("tiny.tar", bytes.NewReader([]byte("x")), 1)
	if err == nil || !strings.Contains(err.Error(), "not mounted") {
		t.Fatalf("err %v", err)
	}
	if _, err := os.Stat(images); !os.IsNotExist(err) {
		entries, _ := os.ReadDir(images)
		if len(entries) != 0 {
			t.Fatalf("wrote files despite error: %v", entries)
		}
	}
}
