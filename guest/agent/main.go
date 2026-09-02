package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	listen := flag.String("listen", fmt.Sprintf("vsock:%d", AgentVsockPort), "vsock:PORT, tcp:HOST:PORT, or HOST:PORT")
	checkDataDir := flag.Bool("check-data-dir", false, "exit 0 if k3s data dir is empty or compatible with v1.33")
	flag.Parse()

	if *checkDataDir {
		if err := checkDataDirCompatible(defaultHost()); err != nil {
			log.Printf("k3s data-dir: %v", err)
			os.Exit(1)
		}
		os.Exit(0)
	}

	ln, err := Listen(*listen)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	srv := &http.Server{
		Handler:           NewHandler(defaultHost()),
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("gmak8-agent listen %s (agent vsock %d; buildkit reserved %d)", ln.Addr(), AgentVsockPort, BuildkitVsockPort)
	if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
		log.Printf("serve: %v", err)
		os.Exit(1)
	}
}
