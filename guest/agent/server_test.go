package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeHost struct {
	mu        sync.Mutex
	disks     DisksReport
	kvm       bool
	times     []time.Time
	shutdowns int
}

func (f *fakeHost) Disks() DisksReport { return f.disks }
func (f *fakeHost) KVM() bool          { return f.kvm }
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

func TestWrongMethods(t *testing.T) {
	h := NewHandler(&fakeHost{})
	cases := []struct {
		method, path string
	}{
		{http.MethodPost, "/health"},
		{http.MethodGet, "/time"},
		{http.MethodGet, "/shutdown"},
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
