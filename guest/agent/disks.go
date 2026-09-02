package main

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

const (
	diskMounted   = "mounted"
	diskUnmounted = "unmounted"
)

// DisksReport is GET /disks. gmak8_data and kite_data are mounted only when
// /mnt/data is the GMAK8_DATA filesystem. Health does not include this.
type DisksReport struct {
	Gmak8Data  string `json:"gmak8_data"`
	KiteData   string `json:"kite_data"`
	Mountpoint string `json:"mountpoint"`
	Label      string `json:"label"`
	BytesTotal uint64 `json:"bytes_total"`
	BytesFree  uint64 `json:"bytes_free"`
}

func (h *realHost) Disks() DisksReport {
	report := DisksReport{
		Gmak8Data:  diskUnmounted,
		KiteData:   diskUnmounted,
		Mountpoint: h.mountPoint,
	}
	data, err := os.ReadFile(h.mountinfoPath)
	if err != nil {
		return report
	}
	source, ok := parseMountinfo(data, h.mountPoint)
	if !ok {
		return report
	}
	labelPath, err := filepath.EvalSymlinks(h.labelSymlink)
	if err != nil {
		return report
	}
	sourcePath, err := filepath.EvalSymlinks(source)
	if err != nil {
		sourcePath = source
	}
	if !sameFile(sourcePath, labelPath) {
		return report
	}
	report.Gmak8Data = diskMounted
	report.KiteData = diskMounted
	report.Label = h.expectedLabel
	var st syscall.Statfs_t
	if err := syscall.Statfs(h.mountPoint, &st); err == nil {
		bsize := uint64(st.Bsize)
		report.BytesTotal = uint64(st.Blocks) * bsize
		report.BytesFree = uint64(st.Bavail) * bsize
	}
	return report
}

func parseMountinfo(data []byte, mountpoint string) (source string, ok bool) {
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, " - ", 2)
		if len(parts) != 2 {
			continue
		}
		fields := strings.Fields(parts[0])
		if len(fields) < 5 {
			continue
		}
		if unescapeMount(fields[4]) != mountpoint {
			continue
		}
		right := strings.Fields(parts[1])
		if len(right) < 2 {
			continue
		}
		return unescapeMount(right[1]), true
	}
	return "", false
}

func unescapeMount(s string) string {
	// mountinfo uses octal escapes (\040 for space). /mnt/data needs none.
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+3 < len(s) {
			n := int(s[i+1]-'0')*64 + int(s[i+2]-'0')*8 + int(s[i+3]-'0')
			b.WriteByte(byte(n))
			i += 3
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func sameFile(a, b string) bool {
	fa, err := os.Stat(a)
	if err != nil {
		return false
	}
	fb, err := os.Stat(b)
	if err != nil {
		return false
	}
	return os.SameFile(fa, fb)
}
