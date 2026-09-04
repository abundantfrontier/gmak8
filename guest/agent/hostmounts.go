package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

const hostMountsFile = "/mnt/config/host-mounts.json"

type HostMountSpec struct {
	Name     string `json:"name"`
	Tag      string `json:"tag"`
	Path     string `json:"path"`
	ReadOnly bool   `json:"read_only"`
}

type HostMountStatus struct {
	Name     string `json:"name"`
	Tag      string `json:"tag"`
	Path     string `json:"path"`
	ReadOnly bool   `json:"read_only"`
	Mounted  bool   `json:"mounted"`
	UID      uint32 `json:"uid,omitempty"`
	GID      uint32 `json:"gid,omitempty"`
}

type HostMountReport struct {
	Items []HostMountStatus `json:"items"`
}

func (h *realHost) HostMounts() (HostMountReport, error) {
	specs, err := readHostMountSpecs(h.hostMountsPath)
	if err != nil {
		return HostMountReport{Items: []HostMountStatus{}}, nil
	}
	items := make([]HostMountStatus, 0, len(specs))
	for _, spec := range specs {
		st := HostMountStatus{Name: spec.Name, Tag: spec.Tag, Path: spec.Path, ReadOnly: spec.ReadOnly}
		st.Mounted = isMountPoint(spec.Path)
		if uid, gid, ok := statOwner(spec.Path); ok {
			st.UID = uid
			st.GID = gid
		}
		items = append(items, st)
	}
	return HostMountReport{Items: items}, nil
}

func (h *realHost) ApplyHostMounts() (HostMountReport, error) {
	specs, err := readHostMountSpecs(h.hostMountsPath)
	if err != nil {
		return HostMountReport{Items: []HostMountStatus{}}, err
	}
	for _, spec := range specs {
		if err := mountVirtiofs(spec, h.runMount); err != nil {
			return HostMountReport{}, err
		}
	}
	return h.HostMounts()
}

func readHostMountSpecs(path string) ([]HostMountSpec, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var list struct {
		Items []HostMountSpec `json:"items"`
	}
	if err := json.Unmarshal(data, &list); err != nil {
		return nil, err
	}
	if list.Items == nil {
		return []HostMountSpec{}, nil
	}
	return list.Items, nil
}

func mountVirtiofs(spec HostMountSpec, run func(args ...string) error) error {
	if spec.Tag == "" || spec.Path == "" || spec.Name == "" {
		return fmt.Errorf("invalid host mount")
	}
	if err := os.MkdirAll(spec.Path, 0o755); err != nil {
		return err
	}
	if _, _, ok := statOwner(spec.Path); ok {
		if isMountPoint(spec.Path) {
			return nil
		}
	}
	args := []string{"-t", "virtiofs"}
	if spec.ReadOnly {
		args = append(args, "-o", "ro")
	}
	args = append(args, spec.Tag, spec.Path)
	if run != nil {
		return run(args...)
	}
	cmd := exec.Command("mount", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("mount %s: %w: %s", spec.Tag, err, string(out))
	}
	return nil
}

func statOwner(path string) (uid, gid uint32, ok bool) {
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return 0, 0, false
	}
	return st.Uid, st.Gid, true
}

func isMountPoint(path string) bool {
	var st, parent syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return false
	}
	if err := syscall.Stat(filepath.Dir(path), &parent); err != nil {
		return false
	}
	return st.Dev != parent.Dev
}
