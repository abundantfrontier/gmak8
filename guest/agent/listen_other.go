//go:build !linux

package main

import (
	"fmt"
	"net"
)

func listenVsock(port uint32) (net.Listener, error) {
	return nil, fmt.Errorf("vsock listen is linux-only (port %d)", port)
}
