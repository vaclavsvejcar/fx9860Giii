# fx-9860GIII

A collection of custom programs (add-ins) for the **Casio fx-9860GIII** graphing calculator.

Programs are written in **C** on top of the **[gint](https://git.planet-casio.com/Lephenixnoir/gint)**
kernel and built with the **[fxSDK](https://git.planet-casio.com/Lephenixnoir/fxsdk)** (a SuperH SH4
cross-compiler). The output is a `.g1a` add-in that is transferred to the calculator over USB.

## About the calculator

| | |
|---|---|
| CPU | SuperH SH-4A (SH7305), 32-bit |
| Display | monochrome, 128×64 px |
| RAM | ~61 kB for user programs |
| Add-in format | `.g1a` (internal name max. 8 characters) |

## Projects

| Project | Description | Status |
|---------|-------------|--------|
| [**penumbra/**](penumbra/) | A darkroom companion — a menu of calculations for black & white film and prints (chemistry dilution, development time/temperature compensation, development timer, f-stop printing, exposure rescaling…). | 🚧 in progress |

## Environment setup (macOS)

Install the full toolchain (fxSDK + SH4 cross-GCC + gint) with the bundled script:

```bash
./install-toolchain.sh          # interactive install
./install-toolchain.sh --help   # options
```

The script uses Homebrew and [GiteaPC](https://git.planet-casio.com/Lephenixnoir/GiteaPC),
is idempotent (just re-run it after a failure) and installs into `~/.local`.
Building the cross-compiler takes **30–60 minutes**.

After installation, open a new terminal and verify:

```bash
fxsdk --version
sh-elf-gcc --version
```

## Development workflow

```bash
cd <app>                   # e.g. cd penumbra
fxsdk build-fx             # compile -> .g1a
```

> `fxsdk new` is unavailable here (it relies on Bash 4+; macOS ships Bash 3.2).
> New add-ins are scaffolded by hand — copy an existing project's `CMakeLists.txt`,
> `src/` and `assets-fx/icon.png` as a starting point.

## Deploying to the calculator

The fx-9860GIII (G-III series) connects as **USB Mass Storage**; on macOS its storage
mounts as a removable volume under `/Volumes`, and installing an add-in means copying
its `.g1a` onto that volume. The bundled TUI handles build + detect + copy:

```bash
./deploy.sh                # full-screen TUI: install / reinstall / remove
```

It auto-discovers every add-in in the repo, builds them, and copies the `.g1a` to the
calculator. A fixed status bar shows the USB connection state live — **green** when the
calculator is mounted, **red** when it isn't (with on-screen guidance). Keys: `i` install,
`b` build only, `r` remove, `d` re-detect, `q` quit.

The TUI is built with [Textual](https://textual.textualize.io/); `./deploy.sh` provisions
a private `.venv` with it automatically on first run (needs `python3`).

> **Note on testing:** there is no reliable emulator for gint add-ins on macOS —
> gint bypasses the Casio OS and drives the hardware directly, so the official Casio
> emulator does not run them correctly. The primary test device is a **physical
> calculator** (the USB iteration loop is fast, at least).

## License

[MIT](LICENSE) © 2026 Vaclav Svejcar
