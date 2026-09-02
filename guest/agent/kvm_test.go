package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestKVMCharDevice(t *testing.T) {
	if !isCharDevice("/dev/null") {
		t.Fatal("/dev/null should be a char device")
	}
	if isCharDevice("/dev/no-such-gmak8-kvm") {
		t.Fatal("missing path must be false")
	}
	dir := t.TempDir()
	regular := filepath.Join(dir, "file")
	if err := os.WriteFile(regular, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if isCharDevice(regular) {
		t.Fatal("regular file must not count as kvm")
	}
	if isCharDevice(dir) {
		t.Fatal("directory must not count as kvm")
	}
}

func TestPorts(t *testing.T) {
	if AgentVsockPort != 1024 {
		t.Fatalf("agent port %d", AgentVsockPort)
	}
	if BuildkitVsockPort != 1025 {
		t.Fatalf("buildkit port %d", BuildkitVsockPort)
	}
}
