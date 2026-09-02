package main

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
)

const sdListenFDSStart = 3

func Listen(addr string) (net.Listener, error) {
	if ln, err := systemdListener(); ln != nil || err != nil {
		return ln, err
	}
	if addr == "" {
		addr = fmt.Sprintf("vsock:%d", AgentVsockPort)
	}
	if strings.HasPrefix(addr, "vsock:") {
		port, err := strconv.ParseUint(strings.TrimPrefix(addr, "vsock:"), 10, 32)
		if err != nil {
			return nil, fmt.Errorf("vsock port: %w", err)
		}
		return listenVsock(uint32(port))
	}
	tcpAddr := strings.TrimPrefix(addr, "tcp:")
	return net.Listen("tcp", tcpAddr)
}

func systemdListener() (net.Listener, error) {
	n, err := strconv.Atoi(os.Getenv("LISTEN_FDS"))
	if err != nil || n < 1 {
		return nil, nil
	}
	if pid := os.Getenv("LISTEN_PID"); pid != "" && pid != strconv.Itoa(os.Getpid()) {
		return nil, nil
	}
	file := os.NewFile(uintptr(sdListenFDSStart), "LISTEN_FD")
	if file == nil {
		return nil, fmt.Errorf("LISTEN_FDS set but fd %d missing", sdListenFDSStart)
	}
	defer file.Close()
	return net.FileListener(file)
}
