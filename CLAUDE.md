# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

Custom add-ins for the **Casio fx-9860GIII** graphing calculator, written in **C**
on top of the **gint** kernel and built with the **fxSDK** cross-toolchain.
Each program compiles to a `.g1a` add-in transferred to the calculator over USB.

The user (repo owner) is Czech — **reply in Czech** unless asked otherwise.
Repository files (code, README, comments) are written in **English**.

## Hardware constraints (keep these in mind for any code)

- CPU: SuperH SH-4A (SH7305), 32-bit, no FPU worth relying on — prefer integer math.
- Display: monochrome, **128×64 px**. Design UIs for that size; text is ~21×8 chars.
- ~61 kB user RAM — keep memory footprint small.
- `.g1a` internal add-in name is limited to **8 characters** (e.g. `PENUMBRA`).
- Runs in a darkroom: consider the backlight / a dim, high-contrast UI.

## Toolchain

- Installed via `./install-toolchain.sh` (Homebrew + GiteaPC) into `~/.local`.
- Requires `~/.local/bin` on `PATH` (`fxsdk`, `sh-elf-gcc`, `fxlink`).
- gint / fxSDK come from Planète Casio's Gitea forge (not GitHub); update with
  `giteapc install -u`.

## Common commands

```bash
cd penumbra                # work inside an add-in project
fxsdk build-fx             # build -> Penumbra.g1a
./deploy.sh                # TUI: build + install / reinstall / remove on the calc
```

- `fxsdk new` does **not** work here (needs Bash 4+; macOS ships 3.2). Scaffold a new
  add-in by copying an existing project's `CMakeLists.txt`, `src/`, `assets-fx/`.
- The G-III is **USB Mass Storage**: installing an add-in = copying its `.g1a` to the
  volume macOS auto-mounts under `/Volumes` (`deploy.sh` does this). `fxsdk send` is
  only for older, non-mass-storage models.

A gint add-in project uses CMake (`CMakeLists.txt`) with `find_package(Gint)`, sources
in `src/`, and the fx-9860 menu icon at `assets-fx/icon.png` (**30×19**, 1-bit; the OS
draws the menu-position letter over the icon's bottom-right corner, so leave a dark
block there).

## Deploy tool

`deploy.sh` launches `deploy_tui.py`, a **Textual** full-screen TUI (auto-provisions a
`.venv` on first run). It auto-discovers add-ins, live-detects the mounted calculator,
shows a colored status bar, and builds/installs/removes. Hash-compares the local `.g1a`
vs. the one on the calc to show install status.

## UI conventions (penumbra code)

- Default font is `gint_font5x7`: 5×7 px glyphs (~6 px advance, ~7 px line height).
  On 128×64 that's ~21 chars wide. The footer occupies rows ~57–63 — keep content above.
- `ui.c` / `ui.h`: shared helpers — `ui_title()` (centered title + rule at y=10),
  `ui_footer()` (bottom hint), `ui_intfield` (editable non-negative integer input).
- `main.c`: data-driven menu that dispatches to `screen_*()` functions declared in
  `screens.h`. Each feature is its own `src/<feature>.c` with a `screen_<feature>()`
  event loop that returns on `KEY_EXIT`.
- **No FPU**: format decimals with integer math (compute tenths, print with `%d.%d`).

## Testing

There is **no reliable macOS emulator** for gint add-ins (gint bypasses the Casio OS
and drives hardware directly). Do not assume code can be run/verified locally — it is
tested on a **physical calculator**. When making changes, reason carefully about
correctness rather than relying on execution, and flag anything that can only be
confirmed on-device.

## Projects

- **penumbra/** — darkroom companion (the flagship app). Menu-driven add-in for black &
  white film and prints. **Built:** main menu + chemistry dilution (`1+X` notation).
  **Stubs** (`screen_soon`): temperature compensation, development timer. **Planned:**
  f-stop printing, exposure rescaling. Scope is strictly darkroom (no in-camera/shooting
  features).

The repo may hold other, unrelated fx-9860GIII add-ins over time — `install-toolchain.sh`
and the toolchain are generic, not tied to any single app.
