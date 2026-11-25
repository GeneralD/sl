# sl

![license](https://img.shields.io/badge/license-MIT-blue) ![platform](https://img.shields.io/badge/platform-macOS%2013+-black) ![swift](https://img.shields.io/badge/swift-6.3-orange) ![release](https://img.shields.io/github/v/release/GeneralD/sl) ![checks](https://img.shields.io/github/actions/workflow/status/GeneralD/sl/ci.yml?label=checks)

<!-- hero: assets/hero.png (generating; swap in when it lands) -->

A `3D` steam locomotive that runs across your **actual desktop** — over
every open window, on every Space — when you typo `ls` into `sl`.

The original [`sl`](https://github.com/mtoyoda/sl) by Toyoda Masashi
punishes you inside the terminal. This one punishes you **everywhere**.

## Install

```sh
# homebrew (recommended)
brew install generald/tap/sl3d   # installs a binary still named `sl`

# or from source — needs only Command Line Tools, no Xcode
git clone https://github.com/GeneralD/sl && cd sl
make install                      # installs to /opt/homebrew (PREFIX=…)

# staged install — verify without touching the system
make install PREFIX=/usr/local DESTDIR=/tmp/sl-dest
/tmp/sl-dest/usr/local/bin/sl -v
man -M /tmp/sl-dest/usr/local/share/man sl
```

## Homebrew

`sl3d` ships via the [`GeneralD/tap`](https://github.com/GeneralD/tap) tap:

```sh
brew install GeneralD/tap/sl3d
```

The formula installs the `sl` binary and its man page; it declares
`conflicts_with "sl"` because the core `sl` formula owns that name.
The installed binary is still `sl` — flags and `man sl` are unchanged.

## Usage

```sh
sl          # a D51 crosses your desktop. you cannot stop it.
sl -e       # …unless you pass -e, then Ctrl+C works
sl -F       # Galaxy Express 999 — it flies away
sl -4       # locomotive + 4 cars
sl -l       # little train
sl -w       # windy: faster
sl -a       # screaming passengers
sl -c       # C51 instead of D51
sl -d       # disco mode
sl -s       # chuff & whistle (off by default)
sl --all    # traverse every connected display
sl --model engine.usdz   # your own USDZ/SCN/DAE locomotive
man sl
```

## How it works

`sl` is a bare Swift CLI that opens a borderless, transparent,
click-through `NSWindow` at `.screenSaver` level — above the Dock, the
menu bar, and fullscreen Spaces — renders a live SceneKit locomotive
into it, and deletes itself from existence when the train leaves the
screen. No permissions, no Dock icon, no focus stolen.

## Uninstall

```sh
make uninstall   # or: brew uninstall generald/tap/sl3d
```

## License

MIT — same as the original `sl`. You were warned.
