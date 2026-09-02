# Guest HTTP agent. Default listen is vsock:1024 (not gvproxy; 1025 is buildkitd).
GO ?= go
CGO_ENABLED ?= 0
GOOS ?= linux
GOARCH ?= arm64
BIN ?= gmak8-agent
PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: all build test install clean

all: build

build:
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) $(GO) build -trimpath -ldflags='-s -w' -o $(BIN) .

test:
	$(GO) test ./...

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(BIN) $(DESTDIR)$(PREFIX)/bin/$(BIN)

clean:
	rm -f $(BIN)
