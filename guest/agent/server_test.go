package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeHost struct {
	mu            sync.Mutex
	disks         DisksReport
	kvm           bool
	kubeconfig    []byte
	kubeconfigErr error
	k3s           K3sReport
	node          NodeReport
	services      ServiceListReport
	servicesErr   error
	times         []time.Time
	shutdowns     int
	k3sStarts     int
	startK3sErr   error
	airgap        AirgapReport
	airgapImports int
	importErr     error
	images        ImageListReport
	imagesErr     error
	imageImports  int
	lastImageBody []byte
	imageBusy     bool
	pruneErr      error
	prunes        int
}

func (f *fakeHost) Disks() DisksReport { return f.disks }
func (f *fakeHost) KVM() bool          { return f.kvm }
func (f *fakeHost) Kubeconfig() ([]byte, error) {
	if f.kubeconfigErr != nil {
		return nil, f.kubeconfigErr
	}
	if f.kubeconfig == nil {
		return nil, os.ErrNotExist
	}
	return f.kubeconfig, nil
}
func (f *fakeHost) K3s() K3sReport { return f.k3s }
func (f *fakeHost) StartK3s() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.startK3sErr != nil {
		return f.startK3sErr
	}
	f.k3sStarts++
	return nil
}
func (f *fakeHost) Node() NodeReport {
	return f.node
}
func (f *fakeHost) Airgap() AirgapReport {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.airgap.Files == nil {
		return AirgapReport{Files: []string{}}
	}
	return f.airgap
}
func (f *fakeHost) ImportAirgap(name string, r io.Reader, size int64) (AirgapReport, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.importErr != nil {
		return AirgapReport{}, f.importErr
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return AirgapReport{}, err
	}
	if int64(len(data)) != size {
		return AirgapReport{}, errString("short airgap write")
	}
	clean, err := sanitizeAirgapName(name)
	if err != nil {
		return AirgapReport{}, err
	}
	f.airgapImports++
	f.airgap = AirgapReport{
		Present: true,
		Files:   []string{clean},
		Bytes:   uint64(len(data)),
	}
	return f.airgap, nil
}
func (f *fakeHost) ListImages() (ImageListReport, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.imagesErr != nil {
		return ImageListReport{}, f.imagesErr
	}
	if f.images.Items == nil {
		return ImageListReport{Items: []Image{}}, nil
	}
	return f.images, nil
}
func (f *fakeHost) ImportImage(name string, r io.Reader, size int64) (ImageImportReport, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.imageBusy {
		return ImageImportReport{}, errImageBusy
	}
	if f.importErr != nil {
		return ImageImportReport{}, f.importErr
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return ImageImportReport{}, err
	}
	if int64(len(data)) != size {
		return ImageImportReport{}, errString("short image write")
	}
	clean, err := sanitizeImageName(name)
	if err != nil {
		return ImageImportReport{}, err
	}
	f.imageImports++
	f.lastImageBody = data
	img := Image{ID: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", Refs: []string{clean}, SizeBytes: size, System: false}
	f.images = ImageListReport{Items: []Image{img}}
	return ImageImportReport{Digest: img.ID, Refs: img.Refs}, nil
}
func (f *fakeHost) PruneImages() (ImagePruneReport, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.pruneErr != nil {
		return ImagePruneReport{}, f.pruneErr
	}
	f.prunes++
	deleted := make([]string, 0, len(f.images.Items))
	for _, img := range f.images.Items {
		if !img.System {
			deleted = append(deleted, img.ID)
		}
	}
	kept := make([]Image, 0)
	for _, img := range f.images.Items {
		if img.System {
			kept = append(kept, img)
		}
	}
	f.images.Items = kept
	return ImagePruneReport{Deleted: deleted}, nil
}
func (f *fakeHost) Services() (ServiceListReport, error) {
	if f.servicesErr != nil {
		return ServiceListReport{}, f.servicesErr
	}
	if f.services.Items == nil {
		return ServiceListReport{Items: []Service{}}, nil
	}
	return f.services, nil
}
func (f *fakeHost) SetTime(t time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.times = append(f.times, t.UTC())
	return nil
}
func (f *fakeHost) Shutdown() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.shutdowns++
	return nil
}

func (f *fakeHost) lastTime() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.times) == 0 {
		return time.Time{}
	}
	return f.times[len(f.times)-1]
}

func (f *fakeHost) shutdownCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.shutdowns
}

func TestHealthDoesNotReportDisks(t *testing.T) {
	host := &fakeHost{disks: DisksReport{Gmak8Data: diskMounted, KiteData: diskMounted}}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	body := rec.Body.String()
	if !strings.Contains(body, `"ok":true`) {
		t.Fatalf("body %s", body)
	}
	if strings.Contains(body, "gmak8_data") || strings.Contains(body, "kite_data") {
		t.Fatalf("health must not include disk status: %s", body)
	}
}

func TestDisksMountedAndUnmounted(t *testing.T) {
	host := &fakeHost{disks: DisksReport{
		Gmak8Data:  diskMounted,
		KiteData:   diskMounted,
		Mountpoint: dataMountPoint,
		Label:      dataLabel,
		BytesTotal: 100,
		BytesFree:  40,
	}}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/disks", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d body %s", rec.Code, rec.Body.String())
	}
	var got DisksReport
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Gmak8Data != diskMounted || got.KiteData != diskMounted {
		t.Fatalf("got %+v", got)
	}
	if got.BytesTotal != 100 || got.BytesFree != 40 || got.Label != dataLabel {
		t.Fatalf("got %+v", got)
	}

	host.disks = DisksReport{Gmak8Data: diskUnmounted, KiteData: diskUnmounted, Mountpoint: dataMountPoint}
	rec = httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/disks", nil))
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Gmak8Data != diskUnmounted || got.KiteData != diskUnmounted {
		t.Fatalf("got %+v", got)
	}
}

func TestKVM(t *testing.T) {
	host := &fakeHost{kvm: true}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/kvm", nil))
	var got kvmResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if !got.KVM {
		t.Fatal("expected kvm true")
	}
	host.kvm = false
	rec = httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/kvm", nil))
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.KVM {
		t.Fatal("expected kvm false")
	}
}

func TestPutTimeUnixAndRFC3339(t *testing.T) {
	host := &fakeHost{}
	h := NewHandler(host)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPut, "/time", bytes.NewReader([]byte(`{"unix":1756713600}`))))
	if rec.Code != http.StatusOK {
		t.Fatalf("unix status %d %s", rec.Code, rec.Body.String())
	}
	if host.lastTime().Unix() != 1756713600 {
		t.Fatalf("unix time %v", host.lastTime())
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPut, "/time", bytes.NewReader([]byte(`{"rfc3339":"2026-09-01T12:00:00Z"}`))))
	if rec.Code != http.StatusOK {
		t.Fatalf("rfc3339 status %d %s", rec.Code, rec.Body.String())
	}
	if host.lastTime().UTC().Format(time.RFC3339) != "2026-09-01T12:00:00Z" {
		t.Fatalf("rfc3339 time %v", host.lastTime())
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPut, "/time", bytes.NewReader([]byte(`"2026-09-01T00:00:00Z"`))))
	if rec.Code != http.StatusOK {
		t.Fatalf("string rfc3339 status %d %s", rec.Code, rec.Body.String())
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPut, "/time", bytes.NewReader([]byte(`1756713601`))))
	if rec.Code != http.StatusOK {
		t.Fatalf("raw unix status %d %s", rec.Code, rec.Body.String())
	}
	if host.lastTime().Unix() != 1756713601 {
		t.Fatalf("raw unix %v", host.lastTime())
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPut, "/time", bytes.NewReader([]byte(`{}`))))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("empty object status %d", rec.Code)
	}
}

func TestShutdownFlushesThenHalts(t *testing.T) {
	host := &fakeHost{}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/shutdown", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if host.shutdownCount() > 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("shutdown not called")
}

func TestKubeconfigBytesOr404(t *testing.T) {
	host := &fakeHost{}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/kubeconfig", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("missing kubeconfig status %d body %s", rec.Code, rec.Body.String())
	}

	yaml := []byte("apiVersion: v1\nkind: Config\n")
	host.kubeconfig = yaml
	rec = httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/kubeconfig", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d body %s", rec.Code, rec.Body.String())
	}
	if rec.Body.String() != string(yaml) {
		t.Fatalf("body %s", rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "yaml") {
		t.Fatalf("content-type %s", ct)
	}
}

func TestK3sAndNodeJSON(t *testing.T) {
	host := &fakeHost{
		k3s: K3sReport{
			Active:        true,
			Version:       "v1.33.3+k3s1",
			DataDirMinor:  "1.33",
			DataDirExists: true,
		},
		node: NodeReport{Ready: true, Name: "gmak8"},
	}
	h := NewHandler(host)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/k3s", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("k3s status %d %s", rec.Code, rec.Body.String())
	}
	var k3s K3sReport
	if err := json.Unmarshal(rec.Body.Bytes(), &k3s); err != nil {
		t.Fatal(err)
	}
	if !k3s.Active || k3s.Version != "v1.33.3+k3s1" || k3s.DataDirMinor != "1.33" || !k3s.DataDirExists {
		t.Fatalf("k3s %+v", k3s)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/node", nil))
	var node NodeReport
	if err := json.Unmarshal(rec.Body.Bytes(), &node); err != nil {
		t.Fatal(err)
	}
	if !node.Ready || node.Name != "gmak8" {
		t.Fatalf("node %+v", node)
	}

	host.node = NodeReport{Ready: false}
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/node", nil))
	if err := json.Unmarshal(rec.Body.Bytes(), &node); err != nil {
		t.Fatal(err)
	}
	if node.Ready {
		t.Fatal("expected node not ready")
	}
}

func TestServicesJSON(t *testing.T) {
	host := &fakeHost{
		services: ServiceListReport{Items: []Service{
			{
				Namespace: "default",
				Name:      "nginx",
				Type:      "NodePort",
				Ports: []ServicePort{
					{Name: "http", Port: 80, NodePort: 30080, Protocol: "TCP"},
				},
			},
		}},
	}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/services", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d %s", rec.Code, rec.Body.String())
	}
	var got ServiceListReport
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if len(got.Items) != 1 || got.Items[0].Name != "nginx" || got.Items[0].Ports[0].NodePort != 30080 {
		t.Fatalf("got %+v", got)
	}

	host.services = ServiceListReport{}
	rec = httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/services", nil))
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Items == nil || len(got.Items) != 0 {
		t.Fatalf("empty list %+v", got)
	}

	host.servicesErr = errString("kubectl: connection refused")
	rec = httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/services", nil))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("kubectl failure status %d %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "connection refused") {
		t.Fatalf("error body %s", rec.Body.String())
	}
}

func TestStartK3s(t *testing.T) {
	host := &fakeHost{}
	rec := httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/k3s/start", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d %s", rec.Code, rec.Body.String())
	}
	host.mu.Lock()
	starts := host.k3sStarts
	host.mu.Unlock()
	if starts != 1 {
		t.Fatalf("starts %d", starts)
	}

	host.startK3sErr = errString("compat")
	rec = httptest.NewRecorder()
	NewHandler(host).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/k3s/start", nil))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("error status %d", rec.Code)
	}
}

func TestWrongMethods(t *testing.T) {
	h := NewHandler(&fakeHost{})
	cases := []struct {
		method, path string
	}{
		{http.MethodPost, "/health"},
		{http.MethodGet, "/time"},
		{http.MethodGet, "/shutdown"},
		{http.MethodPost, "/k3s"},
		{http.MethodGet, "/k3s/start"},
		{http.MethodPost, "/node"},
		{http.MethodPost, "/services"},
		{http.MethodPost, "/kubeconfig"},
		{http.MethodPost, "/airgap"},
		{http.MethodGet, "/airgap/k3s"},
		{http.MethodPost, "/images"},
		{http.MethodGet, "/images/import"},
		{http.MethodGet, "/images/prune"},
		{http.MethodGet, "/nope"},
	}
	for _, tc := range cases {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(tc.method, tc.path, nil))
		if rec.Code == http.StatusOK {
			t.Fatalf("%s %s: unexpected 200", tc.method, tc.path)
		}
	}
}

func TestAirgapGetAndPut(t *testing.T) {
	host := &fakeHost{airgap: AirgapReport{Files: []string{}}}
	h := NewHandler(host)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/airgap", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d %s", rec.Code, rec.Body.String())
	}
	var report AirgapReport
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if report.Present {
		t.Fatalf("expected empty airgap %+v", report)
	}

	body := []byte("tiny-airgap-fixture")
	req := httptest.NewRequest(http.MethodPut, "/airgap/k3s", bytes.NewReader(body))
	req.Header.Set("Content-Length", strconv.Itoa(len(body)))
	req.Header.Set("X-Gmak8-Name", "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst")
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("put status %d %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if !report.Present || len(report.Files) != 1 || report.Bytes != uint64(len(body)) {
		t.Fatalf("after put %+v", report)
	}
	host.mu.Lock()
	imports := host.airgapImports
	host.mu.Unlock()
	if imports != 1 {
		t.Fatalf("imports %d", imports)
	}

	req = httptest.NewRequest(http.MethodPut, "/airgap/k3s", bytes.NewReader(body))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("missing length status %d", rec.Code)
	}

	oversize := httptest.NewRequest(http.MethodPut, "/airgap/k3s", bytes.NewReader([]byte("x")))
	oversize.Header.Set("Content-Length", strconv.FormatInt(maxAirgapBytes+1, 10))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, oversize)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversize status %d %s", rec.Code, rec.Body.String())
	}
}

func TestImagesListImportPrune(t *testing.T) {
	host := &fakeHost{}
	h := NewHandler(host)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/images", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("list status %d %s", rec.Code, rec.Body.String())
	}
	var listed ImageListReport
	if err := json.Unmarshal(rec.Body.Bytes(), &listed); err != nil {
		t.Fatal(err)
	}
	if listed.Items == nil || len(listed.Items) != 0 {
		t.Fatalf("empty list %+v", listed)
	}

	body := []byte("tiny-oci-tar")
	req := httptest.NewRequest(http.MethodPut, "/images/import?name=nginx.dev.tar", bytes.NewReader(body))
	req.Header.Set("Content-Length", strconv.Itoa(len(body)))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("import status %d %s", rec.Code, rec.Body.String())
	}
	var imported ImageImportReport
	if err := json.Unmarshal(rec.Body.Bytes(), &imported); err != nil {
		t.Fatal(err)
	}
	if imported.Digest == "" || len(imported.Refs) != 1 {
		t.Fatalf("imported %+v", imported)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/images", nil))
	if err := json.Unmarshal(rec.Body.Bytes(), &listed); err != nil {
		t.Fatal(err)
	}
	if len(listed.Items) != 1 {
		t.Fatalf("after import %+v", listed)
	}

	req = httptest.NewRequest(http.MethodPut, "/images/import", bytes.NewReader(body))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("missing length status %d", rec.Code)
	}

	host.mu.Lock()
	host.imageBusy = true
	host.mu.Unlock()
	busy := httptest.NewRequest(http.MethodPut, "/images/import?name=nginx.dev.tar", bytes.NewReader(body))
	busy.Header.Set("Content-Length", strconv.Itoa(len(body)))
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, busy)
	if rec.Code != http.StatusConflict {
		t.Fatalf("busy status %d %s", rec.Code, rec.Body.String())
	}
	host.mu.Lock()
	host.imageBusy = false
	host.mu.Unlock()

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/images/prune", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("prune status %d %s", rec.Code, rec.Body.String())
	}
	var pruned ImagePruneReport
	if err := json.Unmarshal(rec.Body.Bytes(), &pruned); err != nil {
		t.Fatal(err)
	}
	if len(pruned.Deleted) != 1 {
		t.Fatalf("pruned %+v", pruned)
	}
}

func TestListenTCPHealth(t *testing.T) {
	ln, err := Listen("tcp:127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	srv := &http.Server{Handler: NewHandler(&fakeHost{kvm: true}), ReadHeaderTimeout: time.Second}
	go srv.Serve(ln)
	defer srv.Close()

	url := "http://" + ln.Addr().String() + "/health"
	resp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 || !bytes.Contains(body, []byte(`"ok":true`)) {
		t.Fatalf("status %d body %s", resp.StatusCode, body)
	}
	if _, ok := ln.Addr().(*net.TCPAddr); !ok {
		t.Fatalf("addr %T", ln.Addr())
	}
}
