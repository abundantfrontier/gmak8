package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestParseMountinfo(t *testing.T) {
	line := "36 35 259:1 / /mnt/data rw,noatime shared:1 - ext4 /dev/nvme1n1 rw,noatime\n"
	src, ok := parseMountinfo([]byte(line), "/mnt/data")
	if !ok || src != "/dev/nvme1n1" {
		t.Fatalf("got %q %v", src, ok)
	}
	if _, ok := parseMountinfo([]byte(line), "/mnt/other"); ok {
		t.Fatal("wrong mountpoint matched")
	}
}

func TestRealHostDisksMountedWhenLabelMatches(t *testing.T) {
	dir := t.TempDir()
	disk := filepath.Join(dir, "nvme1n1")
	if err := os.WriteFile(disk, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	byLabel := filepath.Join(dir, "GMAK8_DATA")
	if err := os.Symlink(disk, byLabel); err != nil {
		t.Fatal(err)
	}
	mountinfo := filepath.Join(dir, "mountinfo")
	content := fmt.Sprintf("1 0 0:0 / %s rw - ext4 %s rw\n", dir, disk)
	if err := os.WriteFile(mountinfo, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	h := defaultHost()
	h.mountPoint = dir
	h.mountinfoPath = mountinfo
	h.labelSymlink = byLabel
	got := h.Disks()
	if got.Gmak8Data != diskMounted || got.KiteData != diskMounted {
		t.Fatalf("expected mounted, got %+v", got)
	}
	if got.Label != dataLabel {
		t.Fatalf("label %q", got.Label)
	}
	if got.BytesTotal == 0 {
		t.Fatalf("expected bytes_total, got %+v", got)
	}
}

func TestRealHostDisksUnmountedWithoutLabel(t *testing.T) {
	dir := t.TempDir()
	h := defaultHost()
	h.mountPoint = dir
	h.mountinfoPath = filepath.Join(dir, "missing-mountinfo")
	h.labelSymlink = filepath.Join(dir, "no-label")
	got := h.Disks()
	if got.Gmak8Data != diskUnmounted || got.KiteData != diskUnmounted {
		t.Fatalf("expected unmounted, got %+v", got)
	}
}
