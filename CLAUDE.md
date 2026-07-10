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
- `.g1a` internal add-in name is limited to **8 characters** (e.g. `SAFELITE`).
- Runs in a darkroom: consider the backlight / a dim, high-contrast UI.

## Toolchain

- Installed via `./install-toolchain.sh` (Homebrew + GiteaPC) into `~/.local`.
- Requires `~/.local/bin` on `PATH` (`fxsdk`, `sh-elf-gcc`, `fxlink`).
- gint / fxSDK come from Planète Casio's Gitea forge (not GitHub); update with
  `giteapc install -u`.

## Common commands

```bash
fxsdk new <name>            # scaffold a new add-in project
fxsdk build-fx             # build -> .g1a (run inside a project dir)
fxsdk send -f <file>.g1a   # send to the calculator over USB (fxlink)
```

A gint add-in project uses CMake (`CMakeLists.txt`) with `find_package(Gint)`,
sources in `src/`, and assets (icon, images, fonts) under `assets-fx/`.

## Testing

There is **no reliable macOS emulator** for gint add-ins (gint bypasses the Casio OS
and drives hardware directly). Do not assume code can be run/verified locally — it is
tested on a **physical calculator**. When making changes, reason carefully about
correctness rather than relying on execution, and flag anything that can only be
confirmed on-device.

## Projects

- **penumbra/** — darkroom companion (the flagship app). A menu-driven add-in with
  calculators for black & white film and prints: chemistry dilution, development
  time/temperature compensation, a development timer, f-stop printing, and exposure
  rescaling. Scope is strictly darkroom (no in-camera/shooting features). Currently a
  building "hello world"; the menu and calculators are being built out.

The repo may hold other, unrelated fx-9860GIII add-ins over time — `install-toolchain.sh`
and the toolchain are generic, not tied to any single app.
