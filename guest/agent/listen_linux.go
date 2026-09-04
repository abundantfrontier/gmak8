//go:build linux

package main

import (
	"fmt"
	"net"
	"os"
	"syscall"
	"time"
	"unsafe"
)

const (
	afVsock       = 40
	cidAny uint32 = 0xFFFFFFFF
)

type sockaddrVM struct {
	family    uint16
	reserved1 uint16
	port      uint32
	cid       uint32
	flags     uint8
	zero      [3]uint8
}

type vsockAddr struct {
	cid  uint32
	port uint32
}

func (a vsockAddr) Network() string { return "vsock" }

func (a vsockAddr) String() string {
	return fmt.Sprintf("vsock:%d:%d", a.cid, a.port)
}

type vsockListener struct {
	fd   int
	addr vsockAddr
}

type vsockConn struct {
	file   *os.File
	local  vsockAddr
	remote vsockAddr
}

func listenVsock(port uint32) (net.Listener, error) {
	fd, err := syscall.Socket(afVsock, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("vsock socket: %w", err)
	}
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
	return &vsockListener{fd: fd, addr: vsockAddr{cid: cidAny, port: port}}, nil
}

func (l *vsockListener) Accept() (net.Conn, error) {
	// syscall.Accept parses the peer sockaddr and returns EAFNOSUPPORT for AF_VSOCK.
	nfd, _, errno := syscall.Syscall6(syscall.SYS_ACCEPT4, uintptr(l.fd), 0, 0, uintptr(syscall.SOCK_CLOEXEC), 0, 0)
	if errno != 0 {
		return nil, errno
	}
	fd := int(nfd)
	if err := syscall.SetNonblock(fd, false); err != nil {
		syscall.Close(fd)
		return nil, err
	}
	file := os.NewFile(uintptr(fd), fmt.Sprintf("vsock:%d", l.addr.port))
	if file == nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("vsock accept: NewFile")
	}
	return &vsockConn{
		file:   file,
		local:  l.addr,
		remote: vsockAddr{},
	}, nil
}

func (l *vsockListener) Close() error {
	return syscall.Close(l.fd)
}

func (l *vsockListener) Addr() net.Addr {
	return l.addr
}

func (c *vsockConn) Read(b []byte) (int, error)  { return c.file.Read(b) }
func (c *vsockConn) Write(b []byte) (int, error) { return c.file.Write(b) }
func (c *vsockConn) Close() error                { return c.file.Close() }
func (c *vsockConn) LocalAddr() net.Addr         { return c.local }
func (c *vsockConn) RemoteAddr() net.Addr        { return c.remote }
func (c *vsockConn) SetDeadline(t time.Time) error {
	return c.file.SetDeadline(t)
}
func (c *vsockConn) SetReadDeadline(t time.Time) error {
	return c.file.SetReadDeadline(t)
}
func (c *vsockConn) SetWriteDeadline(t time.Time) error {
	return c.file.SetWriteDeadline(t)
}
