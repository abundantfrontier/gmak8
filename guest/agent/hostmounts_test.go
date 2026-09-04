package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadHostMountSpecsEmptyMissing(t *testing.T) {
	specs, err := readHostMountSpecs(filepath.Join(t.TempDir(), "missing.json"))
	if err != nil || len(specs) != 0 {
		t.Fatalf("%v %+v", err, specs)
	}
}

func TestMountVirtiofsUsesTagAndRecordsStatUID(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "projects")
	var got []string
	spec := HostMountSpec{Name: "projects", Tag: "gmak8-host-projects", Path: dest, ReadOnly: false}
	if err := mountVirtiofs(spec, func(args ...string) error {
		got = append([]string{}, args...)
		return os.MkdirAll(dest, 0o755)
	}); err != nil {
		t.Fatal(err)
	}
	if len(got) < 4 || got[1] != "virtiofs" || got[len(got)-2] != spec.Tag || got[len(got)-1] != dest {
		t.Fatalf("mount args %v", got)
	}
	uid, gid, ok := statOwner(dest)
	if !ok {
		t.Fatal("expected stat")
	}
	if uid != uint32(os.Getuid()) || gid != uint32(os.Getgid()) {
		t.Fatalf("uid/gid %d:%d want %d:%d", uid, gid, os.Getuid(), os.Getgid())
	}
}

func TestApplyHostMountsReadsJSON(t *testing.T) {
	dir := t.TempDir()
	jsonPath := filepath.Join(dir, "host-mounts.json")
	body := `{"items":[{"name":"src","tag":"gmak8-host-src","path":"` + filepath.Join(dir, "src") + `","read_only":true}]}`
	if err := os.WriteFile(jsonPath, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	h := defaultHost()
	h.hostMountsPath = jsonPath
	h.runMount = func(args ...string) error {
		return os.MkdirAll(args[len(args)-1], 0o755)
	}
	report, err := h.ApplyHostMounts()
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Items) != 1 || report.Items[0].Name != "src" || !report.Items[0].ReadOnly {
		t.Fatalf("%+v", report)
	}
	if report.Items[0].UID != uint32(os.Getuid()) {
		t.Fatalf("uid %d", report.Items[0].UID)
	}
	if report.Items[0].Mounted {
		t.Fatalf("mkdir is not a virtio-fs mount: %+v", report.Items[0])
	}
}
