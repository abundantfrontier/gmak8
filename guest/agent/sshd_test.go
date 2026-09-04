package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestSSHDStartAndGet(t *testing.T) {
	host := &fakeHost{}
	h := NewHandler(host)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/sshd/start", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d %s", rec.Code, rec.Body.String())
	}
	var report SSHDReport
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatal(err)
	}
	if !report.Running {
		t.Fatalf("%+v", report)
	}
	if host.sshdStarts != 1 {
		t.Fatalf("starts %d", host.sshdStarts)
	}
	get := httptest.NewRecorder()
	h.ServeHTTP(get, httptest.NewRequest(http.MethodGet, "/sshd", nil))
	if get.Code != http.StatusOK || !strings.Contains(get.Body.String(), `"running":true`) {
		t.Fatalf("%d %s", get.Code, get.Body.String())
	}
}

func TestRealHostStartSSHDUsesSSHUnit(t *testing.T) {
	var got []string
	h := defaultHost()
	h.runSystemctl = func(args ...string) (string, error) {
		got = append(got, strings.Join(args, " "))
		if args[0] == "is-active" {
			return "active\n", nil
		}
		return "", nil
	}
	if err := h.StartSSHD(); err != nil {
		t.Fatal(err)
	}
	report, err := h.SSHD()
	if err != nil || !report.Running {
		t.Fatalf("%+v %v", report, err)
	}
	joined := strings.Join(got, ";")
	if !strings.Contains(joined, "unmask ssh") || !strings.Contains(joined, "start --no-block ssh") {
		t.Fatalf("%v", got)
	}
	if strings.Contains(joined, "0.0.0.0") {
		t.Fatal(got)
	}
}
