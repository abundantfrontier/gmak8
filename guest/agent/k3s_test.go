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
	if got := readDataDirMinor(path, "/nope", false); got != "1.33" {
		t.Fatalf("got %q", got)
	}
	if got := readDataDirMinor(filepath.Join(dir, "missing"), "/nope", false); got != "" {
		t.Fatalf("missing file got %q", got)
	}
}
