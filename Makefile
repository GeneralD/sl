PREFIX ?= /opt/homebrew
DESTDIR ?=
export DEVELOPER_DIR := /Library/Developer/CommandLineTools

.PHONY: build install uninstall test clean release

build:
	swift build -c release

install: build
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/share/man/man1" "$(DESTDIR)$(PREFIX)/share/sl/audio" "$(DESTDIR)$(PREFIX)/share/sl/models"
	install -m 755 .build/release/sl "$(DESTDIR)$(PREFIX)/bin/sl"
	@if [ -f sl.1 ]; then install -m 644 sl.1 "$(DESTDIR)$(PREFIX)/share/man/man1/sl.1"; fi
	install -m 644 share/sl/audio/*.wav "$(DESTDIR)$(PREFIX)/share/sl/audio/"
	install -m 644 share/sl/models/*.usdz "$(DESTDIR)$(PREFIX)/share/sl/models/"
	@echo "installed: $$(command -v sl || echo $(DESTDIR)$(PREFIX)/bin/sl)"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/sl" "$(DESTDIR)$(PREFIX)/share/man/man1/sl.1"
	rm -rf "$(DESTDIR)$(PREFIX)/share/sl"

test:
	scripts/gate

release: build
	@mkdir -p dist
	tar -czf "dist/sl-$$(cat VERSION)-macos-arm64.tar.gz" -C .build/release sl -C "$$(pwd)" sl.1 LICENSE README.md LICENSES.md share
	@echo "dist/sl-$$(cat VERSION)-macos-arm64.tar.gz"

clean:
	swift package clean
