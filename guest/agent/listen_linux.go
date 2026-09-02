//go:build linux

package main

import (
	"fmt"
	"net"
	"os"
	"syscall"
	"unsafe"
)

const (
	afVsock        = 40
	cidAny  uint32 = 0xFFFFFFFF
)

type sockaddrVM struct {
	family    uint16
	reserved1 uint16
	port      uint32
	cid       uint32
	flags     uint8
	zero      [3]uint8
}

func listenVsock(port uint32) (net.Listener, error) {
	fd, err := syscall.Socket(afVsock, syscall.SOCK_STREAM, 0)
	if err != nil {
		return nil, fmt.Errorf("vsock socket: %w", err)
	}
	syscall.CloseOnExec(fd)
	sa := sockaddrVM{family: afVsock, port: port, cid: cidAny}
	_, _, errno := syscall.RawSyscall(syscall.SYS_BIND, uintptr(fd), uintptr(unsafe.Pointer(&sa)), unsafe.Sizeof(sa))
	if errno != 0 {
		syscall.Close(fd)
		return nil, fmt.Errorf("vsock bind %d: %w", port, errno)
	}
	if err := syscall.Listen(fd, syscall.SOMAXCONN); err != nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("vsock listen: %w", err)
	}
	file := os.NewFile(uintptr(fd), fmt.Sprintf("vsock:%d", port))
	defer file.Close()
	ln, err := net.FileListener(file)
	if err != nil {
		return nil, err
	}
	return ln, nil
}
