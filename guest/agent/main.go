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
	flag.Parse()

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
