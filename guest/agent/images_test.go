package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseCtrImagesLSGroupsByDigestAndMarksSystem(t *testing.T) {
	const digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	out := `REF                                    TYPE                                      DIGEST                                                                  SIZE      PLATFORMS   LABELS
docker.io/rancher/mirrored-pause:3.6   application/vnd.oci.image.manifest.v1+json ` + digest + ` 25.0 MiB  linux/arm64 -
docker.io/library/nginx:dev            application/vnd.oci.image.manifest.v1+json sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 18.7 MiB  linux/arm64 -
`
	items := parseCtrImagesLS(out)
	if len(items) != 2 {
		t.Fatalf("items %d", len(items))
	}
	if !items[0].System || items[0].ID != digest || items[0].SizeBytes != 25*1024*1024 {
		t.Fatalf("system image %+v", items[0])
	}
	if items[1].System || items[1].Refs[0] != "docker.io/library/nginx:dev" {
		t.Fatalf("user image %+v", items[1])
	}
}

func TestIsSystemImageOnlyRancher(t *testing.T) {
	if !isSystemImage([]string{"docker.io/rancher/mirrored-coredns-coredns:1.12.1"}) {
		t.Fatal("rancher ref is system")
	}
	if isSystemImage([]string{"docker.io/library/nginx:1.27"}) {
		t.Fatal("library nginx is not system")
	}
}

func TestSanitizeImageName(t *testing.T) {
	got, err := sanitizeImageName("")
	if err != nil || got != "image.tar" {
		t.Fatalf("default %q %v", got, err)
	}
	got, err = sanitizeImageName("nginx.dev.tar")
	if err != nil || got != "nginx.dev.tar" {
		t.Fatalf("got %q %v", got, err)
	}
	if _, err := sanitizeImageName("../escape.tar"); err == nil {
		t.Fatal("expected path traversal reject")
	}
	if _, err := sanitizeImageName("image.txt"); err == nil {
		t.Fatal("expected non-archive reject")
	}
}

func TestParseCtrImport(t *testing.T) {
	digest := "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	out := "unpacking docker.io/library/nginx:dev (" + digest + ")...done\n"
	gotDigest, refs := parseCtrImport(out)
	if gotDigest != digest {
		t.Fatalf("digest %q", gotDigest)
	}
	if len(refs) != 1 || refs[0] != "docker.io/library/nginx:dev" {
		t.Fatalf("refs %v", refs)
	}
}

func TestImportImageWritesTempRunsCtrUnlinksAndReports(t *testing.T) {
	dir := t.TempDir()
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

	digest := "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
	var sawImportPath string
	h := defaultHost()
	h.mountPoint = mount
	h.mountinfoPath = mountinfo
	h.labelSymlink = label
	h.tmpDir = filepath.Join(dir, "tmp")
	h.runCtr = func(timeout time.Duration, args ...string) ([]byte, error) {
		if len(args) >= 2 && args[0] == "images" && args[1] == "ls" {
			if sawImportPath == "" {
				return []byte("REF TYPE DIGEST SIZE PLATFORMS LABELS\n"), nil
			}
			line := "docker.io/library/nginx:dev application/vnd.oci.image.manifest.v1+json " + digest + " 1.0 MiB linux/arm64 -\n"
			return []byte(line), nil
		}
		if len(args) >= 3 && args[0] == "images" && args[1] == "import" {
			sawImportPath = args[2]
			body, err := os.ReadFile(args[2])
			if err != nil {
				t.Fatalf("temp missing: %v", err)
			}
			if string(body) != "tiny-image-tar" {
				t.Fatalf("body %q", body)
			}
			return []byte("unpacking docker.io/library/nginx:dev (" + digest + ")...done\n"), nil
		}
		t.Fatalf("unexpected ctr %v", args)
		return nil, nil
	}

	body := []byte("tiny-image-tar")
	report, err := h.ImportImage("nginx.dev.tar", bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	if report.Digest != digest {
		t.Fatalf("digest %+v", report)
	}
	if len(report.Refs) == 0 || report.Refs[0] != "docker.io/library/nginx:dev" {
		t.Fatalf("refs %+v", report)
	}
	if _, err := os.Stat(sawImportPath); !os.IsNotExist(err) {
		t.Fatalf("temp %s should be unlinked", sawImportPath)
	}
}

func TestImportImageRefusesWhenDiskTight(t *testing.T) {
	dir := t.TempDir()
	h := defaultHost()
	h.tmpDir = filepath.Join(dir, "tmp")
	h.mountPoint = dir
	_, err := h.ImportImage("nginx.tar", bytes.NewReader([]byte("x")), 100)
	if err == nil || !strings.Contains(err.Error(), "not mounted") && !strings.Contains(err.Error(), "bytes free") {
		t.Fatalf("err %v", err)
	}
}

func TestImportImageUnlinksTempWhenCtrFails(t *testing.T) {
	dir := t.TempDir()
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
	if err := os.WriteFile(mountinfo, []byte("1 0 0:0 / "+mount+" rw - ext4 "+disk+" rw\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var tmpPath string
	h := defaultHost()
	h.mountPoint = mount
	h.mountinfoPath = mountinfo
	h.labelSymlink = label
	h.tmpDir = filepath.Join(dir, "tmp")
	h.runCtr = func(timeout time.Duration, args ...string) ([]byte, error) {
		if len(args) >= 2 && args[1] == "ls" {
			return []byte("REF TYPE DIGEST SIZE PLATFORMS LABELS\n"), nil
		}
		tmpPath = args[2]
		return []byte("containerd restarting"), errString("ctr failed")
	}
	_, err := h.ImportImage("nginx.tar", bytes.NewReader([]byte("tiny")), 4)
	if err == nil || !strings.Contains(err.Error(), "ctr images import") {
		t.Fatalf("err %v", err)
	}
	if tmpPath == "" {
		t.Fatal("expected import path")
	}
	if _, err := os.Stat(tmpPath); !os.IsNotExist(err) {
		t.Fatalf("temp should be unlinked after ctr failure")
	}
}
