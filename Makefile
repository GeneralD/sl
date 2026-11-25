PREFIX ?= /opt/homebrew
export DEVELOPER_DIR := /Library/Developer/CommandLineTools

.PHONY: build install uninstall test clean release

build:
	swift build -c release

install: build
	install -d "$(PREFIX)/bin" "$(PREFIX)/share/man/man1"
	install -m 755 .build/release/sl "$(PREFIX)/bin/sl"
	install -m 644 sl.1 "$(PREFIX)/share/man/man1/sl.1"
	@echo "installed: $$(command -v sl || echo $(PREFIX)/bin/sl)"

uninstall:
	rm -f "$(PREFIX)/bin/sl" "$(PREFIX)/share/man/man1/sl.1"

test:
	scripts/gate

release: build
	@mkdir -p dist
	tar -czf "dist/sl-$$(cat VERSION)-macos-arm64.tar.gz" -C .build/release sl -C "$$(pwd)" sl.1 LICENSE README.md
	@echo "dist/sl-$$(cat VERSION)-macos-arm64.tar.gz"

clean:
	swift package clean
