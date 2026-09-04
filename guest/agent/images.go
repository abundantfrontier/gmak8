package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
)

const (
	imageImportTimeout = 30 * time.Minute
	imageListTimeout   = 15 * time.Second
	imagePruneTimeout  = 2 * time.Minute
)

var imageDigestRe = regexp.MustCompile(`sha256:[a-fA-F0-9]{64}`)

// Image is one containerd k8s.io image (grouped by digest).
type Image struct {
	ID        string   `json:"id"`
	Refs      []string `json:"refs"`
	SizeBytes int64    `json:"size_bytes"`
	System    bool     `json:"system"`
}

// ImageListReport is GET /images.
type ImageListReport struct {
	Items []Image `json:"items"`
}

// ImageImportReport is PUT /images/import.
type ImageImportReport struct {
	Digest string   `json:"digest"`
	Refs   []string `json:"refs"`
}

// ImagePruneReport is POST /images/prune.
type ImagePruneReport struct {
	Deleted []string `json:"deleted"`
}

func (h *realHost) ListImages() (ImageListReport, error) {
	out, err := h.ctr(imageListTimeout, "images", "ls")
	if err != nil {
		return ImageListReport{}, err
	}
	return ImageListReport{Items: parseCtrImagesLS(string(out))}, nil
}

func (h *realHost) ImportImage(name string, r io.Reader, size int64) (ImageImportReport, error) {
	clean, err := sanitizeImageName(name)
	if err != nil {
		return ImageImportReport{}, err
	}
	if size <= 0 {
		return ImageImportReport{}, fmt.Errorf("invalid image archive size")
	}
	if !h.importing.CompareAndSwap(false, true) {
		return ImageImportReport{}, errImageBusy
	}
	defer h.importing.Store(false)

	disks := h.Disks()
	if disks.Gmak8Data != diskMounted {
		return ImageImportReport{}, fmt.Errorf("data disk is not mounted")
	}
	needed := uint64(size) + uint64(size)/5
	if disks.BytesFree < needed {
		return ImageImportReport{}, fmt.Errorf("data disk has %d bytes free; image import needs %d (archive + 20%%)", disks.BytesFree, needed)
	}
	if err := os.MkdirAll(h.tmpDir, 0o755); err != nil {
		return ImageImportReport{}, err
	}

	before, _ := h.ListImages()
	beforeIDs := imageIDSet(before.Items)

	tmpPath := filepath.Join(h.tmpDir, "."+clean+".tmp")
	_ = os.Remove(tmpPath)
	tmp, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return ImageImportReport{}, err
	}
	defer func() {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
	}()
	if err := tmp.Chmod(0o600); err != nil {
		return ImageImportReport{}, err
	}
	wrote, err := io.Copy(tmp, io.LimitReader(r, size))
	if err != nil {
		return ImageImportReport{}, err
	}
	if wrote != size {
		return ImageImportReport{}, fmt.Errorf("short image write: got %d want %d", wrote, size)
	}
	if err := tmp.Sync(); err != nil {
		return ImageImportReport{}, err
	}
	if err := tmp.Close(); err != nil {
		return ImageImportReport{}, err
	}

	out, err := h.ctr(imageImportTimeout, "images", "import", tmpPath)
	if err != nil {
		return ImageImportReport{}, fmt.Errorf("ctr images import: %w", err)
	}

	digest, refs := parseCtrImport(string(out))
	after, listErr := h.ListImages()
	if listErr == nil {
		for _, img := range after.Items {
			if _, existed := beforeIDs[img.ID]; existed {
				continue
			}
			if digest == "" {
				digest = img.ID
			}
			refs = mergeRefs(refs, img.Refs)
		}
		if digest != "" && len(refs) == 0 {
			for _, img := range after.Items {
				if img.ID == digest {
					refs = mergeRefs(refs, img.Refs)
					break
				}
			}
		}
	}
	if refs == nil {
		refs = []string{}
	}
	return ImageImportReport{Digest: digest, Refs: refs}, nil
}

func (h *realHost) PruneImages() (ImagePruneReport, error) {
	before, err := h.ListImages()
	if err != nil {
		return ImagePruneReport{}, err
	}
	beforeIDs := imageIDSet(before.Items)
	if _, err := h.ctr(imagePruneTimeout, "images", "prune"); err != nil {
		return ImagePruneReport{}, fmt.Errorf("ctr images prune: %w", err)
	}
	after, err := h.ListImages()
	if err != nil {
		return ImagePruneReport{}, err
	}
	afterIDs := imageIDSet(after.Items)
	deleted := make([]string, 0)
	for id := range beforeIDs {
		if _, ok := afterIDs[id]; !ok {
			deleted = append(deleted, id)
		}
	}
	return ImagePruneReport{Deleted: deleted}, nil
}

func (h *realHost) ctr(timeout time.Duration, args ...string) ([]byte, error) {
	if h.runCtr != nil {
		return h.runCtr(timeout, args...)
	}
	bin := h.k3sPath
	if bin == "" {
		bin = k3sBinaryPath
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	all := append([]string{"ctr", "-n", "k8s.io"}, args...)
	cmd := exec.CommandContext(ctx, bin, all...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			return out, err
		}
		return out, fmt.Errorf("%w: %s", err, msg)
	}
	return out, nil
}

func parseCtrImagesLS(out string) []Image {
	byDigest := map[string]*Image{}
	var order []string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "REF") {
			continue
		}
		ref, digest, sizeText, ok := parseCtrImageLine(line)
		if !ok {
			continue
		}
		img, exists := byDigest[digest]
		if !exists {
			img = &Image{ID: digest, Refs: []string{}, SizeBytes: parseImageSize(sizeText)}
			byDigest[digest] = img
			order = append(order, digest)
		}
		if ref != "" && ref != "-" {
			img.Refs = mergeRefs(img.Refs, []string{ref})
		}
		if img.SizeBytes == 0 {
			img.SizeBytes = parseImageSize(sizeText)
		}
	}
	items := make([]Image, 0, len(order))
	for _, id := range order {
		img := byDigest[id]
		img.System = isSystemImage(img.Refs)
		items = append(items, *img)
	}
	return items
}

func parseCtrImageLine(line string) (ref, digest, size string, ok bool) {
	loc := imageDigestRe.FindStringIndex(line)
	if loc == nil {
		return "", "", "", false
	}
	digest = line[loc[0]:loc[1]]
	left := strings.TrimSpace(line[:loc[0]])
	if i := strings.LastIndex(left, " application/"); i >= 0 {
		left = strings.TrimSpace(left[:i])
	}
	ref = left
	rest := strings.Fields(strings.TrimSpace(line[loc[1]:]))
	if len(rest) >= 2 {
		size = rest[0] + " " + rest[1]
	} else if len(rest) == 1 {
		size = rest[0]
	}
	if ref == "" {
		return "", "", "", false
	}
	return ref, digest, size, true
}

func parseCtrImport(out string) (digest string, refs []string) {
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if d := imageDigestRe.FindString(line); d != "" && digest == "" {
			digest = d
		}
		if idx := strings.Index(line, "unpacking "); idx >= 0 {
			rest := strings.TrimSpace(line[idx+len("unpacking "):])
			if cut := strings.Index(rest, " ("); cut > 0 {
				refs = mergeRefs(refs, []string{strings.TrimSpace(rest[:cut])})
			}
		}
	}
	if refs == nil {
		refs = []string{}
	}
	return digest, refs
}

func parseImageSize(text string) int64 {
	fields := strings.Fields(strings.TrimSpace(text))
	if len(fields) == 0 {
		return 0
	}
	n, err := strconv.ParseFloat(fields[0], 64)
	if err != nil || n < 0 {
		return 0
	}
	unit := ""
	if len(fields) > 1 {
		unit = strings.ToLower(fields[1])
	}
	mult := 1.0
	switch unit {
	case "kb", "kib":
		mult = 1024
	case "mb", "mib":
		mult = 1024 * 1024
	case "gb", "gib":
		mult = 1024 * 1024 * 1024
	case "b", "bytes", "":
		mult = 1
	}
	return int64(n * mult)
}

func isSystemImage(refs []string) bool {
	for _, ref := range refs {
		r := strings.ToLower(ref)
		if strings.Contains(r, "/rancher/") || strings.HasPrefix(r, "rancher/") {
			return true
		}
	}
	return false
}

func sanitizeImageName(name string) (string, error) {
	if name == "" {
		name = "image.tar"
	}
	if strings.ContainsAny(name, `/\`) || strings.Contains(name, "..") {
		return "", fmt.Errorf("invalid image name")
	}
	name = filepath.Base(name)
	if name == "." || name == ".." {
		return "", fmt.Errorf("invalid image name")
	}
	lower := strings.ToLower(name)
	if !strings.HasSuffix(lower, ".tar") && !strings.HasSuffix(lower, ".tar.gz") && !strings.HasSuffix(lower, ".tar.zst") {
		return "", fmt.Errorf("image name must end in .tar, .tar.gz, or .tar.zst")
	}
	for _, c := range name {
		if unicode.IsLetter(c) || unicode.IsDigit(c) || c == '.' || c == '-' || c == '_' {
			continue
		}
		return "", fmt.Errorf("invalid image name")
	}
	return name, nil
}

func imageIDSet(items []Image) map[string]struct{} {
	out := make(map[string]struct{}, len(items))
	for _, img := range items {
		out[img.ID] = struct{}{}
	}
	return out
}

func mergeRefs(dst, src []string) []string {
	seen := make(map[string]struct{}, len(dst)+len(src))
	for _, r := range dst {
		seen[r] = struct{}{}
	}
	out := append([]string{}, dst...)
	for _, r := range src {
		if r == "" {
			continue
		}
		if _, ok := seen[r]; ok {
			continue
		}
		seen[r] = struct{}{}
		out = append(out, r)
	}
	return out
}

var errImageBusy = errString("image import already in progress")
