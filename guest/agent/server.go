package main

import (
	"encoding/json"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type Server struct {
	host Host
}

func NewHandler(host Host) http.Handler {
	s := &Server{host: host}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /disks", s.handleDisks)
	mux.HandleFunc("GET /kvm", s.handleKVM)
	mux.HandleFunc("GET /kubeconfig", s.handleKubeconfig)
	mux.HandleFunc("GET /k3s", s.handleK3s)
	mux.HandleFunc("POST /k3s/start", s.handleK3sStart)
	mux.HandleFunc("GET /node", s.handleNode)
	mux.HandleFunc("GET /airgap", s.handleAirgap)
	mux.HandleFunc("PUT /airgap/k3s", s.handleAirgapImport)
	mux.HandleFunc("PUT /airgap/kubevirt", s.handleKubevirtAirgapImport)
	mux.HandleFunc("GET /kubevirt", s.handleKubeVirt)
	mux.HandleFunc("POST /kubevirt/install", s.handleKubeVirtInstall)
	mux.HandleFunc("GET /images", s.handleImages)
	mux.HandleFunc("PUT /images/import", s.handleImageImport)
	mux.HandleFunc("POST /images/prune", s.handleImagePrune)
	mux.HandleFunc("GET /host-mounts", s.handleHostMounts)
	mux.HandleFunc("POST /host-mounts/apply", s.handleHostMountsApply)
	mux.HandleFunc("GET /services", s.handleServices)
	mux.HandleFunc("PUT /time", s.handleTime)
	mux.HandleFunc("POST /shutdown", s.handleShutdown)
	return mux
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	// Agent process is up. Data-disk mount status is GET /disks, not here.
	writeJSON(w, http.StatusOK, okResponse{OK: true})
}

func (s *Server) handleDisks(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.host.Disks())
}

func (s *Server) handleKVM(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, kvmResponse{KVM: s.host.KVM()})
}

func (s *Server) handleKubeconfig(w http.ResponseWriter, _ *http.Request) {
	data, err := s.host.Kubeconfig()
	if err != nil {
		if os.IsNotExist(err) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/yaml")
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func (s *Server) handleK3s(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.host.K3s())
}

func (s *Server) handleK3sStart(w http.ResponseWriter, _ *http.Request) {
	if err := s.host.StartK3s(); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, okResponse{OK: true})
}

func (s *Server) handleNode(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.host.Node())
}

func (s *Server) handleAirgap(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.host.Airgap())
}

func (s *Server) handleAirgapImport(w http.ResponseWriter, r *http.Request) {
	name := r.Header.Get("X-Gmak8-Name")
	if q := r.URL.Query().Get("name"); q != "" {
		name = q
	}
	cl := r.Header.Get("Content-Length")
	if cl == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "content-length required"})
		return
	}
	size, err := strconv.ParseInt(cl, 10, 64)
	if err != nil || size <= 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid content-length"})
		return
	}
	max := int64(maxAirgapBytes)
	if strings.Contains(strings.ToLower(name), "kubevirt") {
		max = maxKubevirtAirgapBytes
	}
	if size > max {
		writeJSON(w, http.StatusRequestEntityTooLarge, errorResponse{Error: "airgap archive exceeds size budget"})
		return
	}
	report, err := s.host.ImportAirgap(name, io.LimitReader(r.Body, size), size)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleImages(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.ListImages()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleImageImport(w http.ResponseWriter, r *http.Request) {
	name := r.Header.Get("X-Gmak8-Name")
	if q := r.URL.Query().Get("name"); q != "" {
		name = q
	}
	cl := r.Header.Get("Content-Length")
	if cl == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "content-length required"})
		return
	}
	size, err := strconv.ParseInt(cl, 10, 64)
	if err != nil || size <= 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid content-length"})
		return
	}
	report, err := s.host.ImportImage(name, io.LimitReader(r.Body, size), size)
	if err != nil {
		if err == errImageBusy {
			writeJSON(w, http.StatusConflict, errorResponse{Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleImagePrune(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.PruneImages()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleKubevirtAirgapImport(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("X-Gmak8-Name") == "" && r.URL.Query().Get("name") == "" {
		r.Header.Set("X-Gmak8-Name", "gmak8-kubevirt-airgap-1.6.1-arm64.tar.zst")
	}
	name := r.Header.Get("X-Gmak8-Name")
	if q := r.URL.Query().Get("name"); q != "" {
		name = q
	}
	if !strings.Contains(strings.ToLower(name), "kubevirt") {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "airgap name must contain kubevirt"})
		return
	}
	s.handleAirgapImport(w, r)
}

func (s *Server) handleKubeVirt(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.KubeVirt()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleKubeVirtInstall(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.InstallKubeVirt()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleHostMounts(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.HostMounts()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleHostMountsApply(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.ApplyHostMounts()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleServices(w http.ResponseWriter, _ *http.Request) {
	report, err := s.host.Services()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func (s *Server) handleTime(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "read body"})
		return
	}
	t, err := parseTimeBody(body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		return
	}
	if err := s.host.SetTime(t); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, okResponse{OK: true})
}

func (s *Server) handleShutdown(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, okResponse{OK: true})
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	go func() {
		time.Sleep(50 * time.Millisecond)
		if err := s.host.Shutdown(); err != nil {
			log.Printf("shutdown: %v", err)
		}
	}()
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		http.Error(w, `{"ok":false,"error":"encode"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	w.WriteHeader(status)
	_, _ = w.Write(b)
}

type timeRequest struct {
	Unix    *json.Number `json:"unix"`
	RFC3339 *string      `json:"rfc3339"`
	Time    *string      `json:"time"`
}

func parseTimeBody(body []byte) (time.Time, error) {
	trimmed := strings.TrimSpace(string(body))
	if trimmed == "" {
		return time.Time{}, errBadTime
	}
	var req timeRequest
	if err := json.Unmarshal(body, &req); err == nil {
		if req.Unix != nil {
			return unixNumber(*req.Unix)
		}
		if req.RFC3339 != nil {
			return parseTimeString(*req.RFC3339)
		}
		if req.Time != nil {
			return parseTimeString(*req.Time)
		}
	}
	var n json.Number
	if err := json.Unmarshal(body, &n); err == nil {
		return unixNumber(n)
	}
	var s string
	if err := json.Unmarshal(body, &s); err == nil {
		return parseTimeString(s)
	}
	return parseTimeString(trimmed)
}

func parseTimeString(s string) (time.Time, error) {
	s = strings.TrimSpace(s)
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t.UTC(), nil
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t.UTC(), nil
	}
	if i, err := strconv.ParseInt(s, 10, 64); err == nil {
		return time.Unix(i, 0).UTC(), nil
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		sec, frac := math.Modf(f)
		return time.Unix(int64(sec), int64(frac*1e9)).UTC(), nil
	}
	return time.Time{}, errBadTime
}

func unixNumber(n json.Number) (time.Time, error) {
	if i, err := n.Int64(); err == nil {
		return time.Unix(i, 0).UTC(), nil
	}
	f, err := n.Float64()
	if err != nil {
		return time.Time{}, errBadTime
	}
	sec, frac := math.Modf(f)
	return time.Unix(int64(sec), int64(frac*1e9)).UTC(), nil
}

var errBadTime = errString("expected unix timestamp or RFC3339")

type errString string

func (e errString) Error() string { return string(e) }
