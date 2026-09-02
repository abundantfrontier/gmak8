package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestKubernetesMinor(t *testing.T) {
	cases := map[string]string{
		"v1.33.3+k3s1":                        "1.33",
		"k3s version v1.33.3+k3s1 (236cbf2a)": "1.33",
		"v1.32.5+k3s1":                        "1.32",
		"1.33":                                "1.33",
		"":                                    "",
		"not-a-version":                       "",
	}
	for in, want := range cases {
		if got := kubernetesMinor(in); got != want {
			t.Fatalf("kubernetesMinor(%q)=%q want %q", in, got, want)
		}
	}
}

func TestParseK3sVersionLine(t *testing.T) {
	out := "k3s version v1.33.3+k3s1 (236cbf2a)\ngo version go1.24.4\n"
	if got := parseK3sVersionLine(out); got != "v1.33.3+k3s1" {
		t.Fatalf("got %q", got)
	}
}

func TestParseNodeListPrefersGmak8(t *testing.T) {
	body := []byte(`{
		"items": [
			{"metadata":{"name":"other"},"status":{"conditions":[{"type":"Ready","status":"True"}]}},
			{"metadata":{"name":"gmak8"},"status":{"conditions":[{"type":"Ready","status":"True"}]}}
		]
	}`)
	got := parseNodeList(body)
	if !got.Ready || got.Name != "gmak8" {
		t.Fatalf("got %+v", got)
	}

	notReady := parseNodeList([]byte(`{
		"items": [{"metadata":{"name":"gmak8"},"status":{"conditions":[{"type":"Ready","status":"False"}]}}]
	}`))
	if notReady.Ready {
		t.Fatal("expected not ready")
	}
}

func TestDirHasEntries(t *testing.T) {
	dir := t.TempDir()
	if dirHasEntries(filepath.Join(dir, "missing")) {
		t.Fatal("missing dir")
	}
	empty := filepath.Join(dir, "empty")
	if err := os.Mkdir(empty, 0o755); err != nil {
		t.Fatal(err)
	}
	if dirHasEntries(empty) {
		t.Fatal("empty dir")
	}
	if err := os.WriteFile(filepath.Join(empty, "state.db"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if !dirHasEntries(empty) {
		t.Fatal("expected entries")
	}
}

func TestReadDataDirMinorFromVersionFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "k3s-version")
	if err := os.WriteFile(path, []byte("v1.33.3+k3s1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := readDataDirMinor(path, filepath.Join(dir, "missing-db"), "/nope", "", false); got != "1.33" {
		t.Fatalf("got %q", got)
	}
	if got := readDataDirMinor(filepath.Join(dir, "missing"), filepath.Join(dir, "missing-db"), "/nope", "", false); got != "" {
		t.Fatalf("missing file got %q", got)
	}
}

func TestScanDBMinorsFromKineBytes(t *testing.T) {
	dir := t.TempDir()
	db := filepath.Join(dir, "state.db")
	payload := append([]byte("kine-header"), []byte("node kubeletVersion:v1.32.5+k3s1 trailer")...)
	if err := os.WriteFile(db, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	got := scanDBMinors(dir)
	if len(got) != 1 || got[0] != "1.32" {
		t.Fatalf("got %v", got)
	}
	if m := readDataDirMinor(filepath.Join(dir, "missing"), dir, "/nope", "", false); m != "1.32" {
		t.Fatalf("readDataDirMinor %q", m)
	}
}

func TestScanIgnoresCoreDNSAndShm(t *testing.T) {
	dir := t.TempDir()
	db := filepath.Join(dir, "state.db")
	payload := []byte("k3s v1.33.3+k3s1 chart coredns v1.12.1 metrics-server v0.7.2")
	if err := os.WriteFile(db, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	shm := filepath.Join(dir, "state.db-shm")
	if err := os.WriteFile(shm, []byte("binary v1.32.5+k3s1 noise"), 0o600); err != nil {
		t.Fatal(err)
	}
	got := scanDBMinors(dir)
	if len(got) != 1 || got[0] != "1.33" {
		t.Fatalf("got %v", got)
	}
	h := defaultHost()
	h.serverDBDir = dir
	h.k3sVersionFile = filepath.Join(dir, "missing-version")
	if err := checkDataDirCompatible(h); err != nil {
		t.Fatalf("1.33 plus chart versions: %v", err)
	}
}

func TestScanWALAndMixedK3sMinorsRefuse(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "state.db"), []byte("v1.33.3+k3s1"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "state.db-wal"), []byte("v1.32.5+k3s1"), 0o600); err != nil {
		t.Fatal(err)
	}
	got := scanDBMinors(dir)
	if len(got) != 2 {
		t.Fatalf("got %v", got)
	}
	if preferredScannedMinor(got) == "1.33" {
		t.Fatalf("mixed minors should prefer the foreign one: %v", got)
	}
	h := defaultHost()
	h.serverDBDir = dir
	h.k3sVersionFile = filepath.Join(dir, "missing-version")
	if err := checkDataDirCompatible(h); err == nil {
		t.Fatal("expected refuse mixed 1.33 and 1.32")
	}
}

func TestCheckDataDirCompatible(t *testing.T) {
	dir := t.TempDir()
	h := defaultHost()
	h.serverDBDir = filepath.Join(dir, "missing")
	h.k3sVersionFile = filepath.Join(dir, "missing-version")
	if err := checkDataDirCompatible(h); err != nil {
		t.Fatalf("empty dir: %v", err)
	}

	db := filepath.Join(dir, "db")
	if err := os.Mkdir(db, 0o755); err != nil {
		t.Fatal(err)
	}
	h.serverDBDir = db
	if err := os.WriteFile(filepath.Join(db, "state.db"), []byte("no versions here"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := checkDataDirCompatible(h); err == nil {
		t.Fatal("expected refuse unknown existing db")
	}

	if err := os.WriteFile(filepath.Join(db, "state.db"), []byte("v1.32.9+k3s1"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := checkDataDirCompatible(h); err == nil {
		t.Fatal("expected refuse 1.32")
	}

	if err := os.WriteFile(filepath.Join(db, "state.db"), []byte("v1.33.3+k3s1"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := checkDataDirCompatible(h); err != nil {
		t.Fatalf("1.33: %v", err)
	}
}
