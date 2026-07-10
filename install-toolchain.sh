#!/usr/bin/env bash
#
# install-toolchain.sh — installs the complete toolchain for developing add-ins
# for the Casio fx-9860GIII calculator (fxSDK + SH4 cross-compiler + gint).
#
# Targets macOS (Apple Silicon and Intel). Uses Homebrew and GiteaPC.
# The script is idempotent: anything already installed is skipped.
#
# Usage:
#   ./install-toolchain.sh              # interactive install
#   ./install-toolchain.sh --yes        # no confirmation prompts
#   ./install-toolchain.sh --verbose    # stream build output (for debugging)
#   ./install-toolchain.sh --skip-brew  # skip Homebrew packages
#   ./install-toolchain.sh --help
#
set -o pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PREFIX="$HOME/.local"
BIN_DIR="$PREFIX/bin"
GITEAPC_SRC="$PREFIX/share/GiteaPC"
LOG_DIR="${TMPDIR:-/tmp}/fx9860g-toolchain-logs"

# Homebrew packages required to build the toolchain and the fxSDK tools.
# 'pillow' provides the PIL module that fxSDK's fxconv needs to convert image
# assets (e.g. gint's fonts); the Homebrew formula makes it importable by the
# Homebrew python3 that fxconv runs under.
BREW_PKGS="python3 git cmake pkg-config libpng libusb sdl2 fmt gmp mpfr libmpc texinfo xz pillow"

# GCC version built by sh-elf-gcc (used by the prerequisite pre-seeding step).
GCC_VERSION="14.1.0"

# How many trailing log lines to show live under the progress bar.
PANEL_TAIL=10

# Flags
ASSUME_YES=false
VERBOSE=false
SKIP_BREW=false

# ---------------------------------------------------------------------------
# Colors / TUI helpers
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; CYAN=$'\033[36m'; MAGENTA=$'\033[35m'
else
    BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""
    BLUE=""; CYAN=""; MAGENTA=""
fi

CURRENT=0
TOTAL=0
CHILD_PID=""

restore_cursor() { tput cnorm 2>/dev/null || printf '\033[?25h'; }

# Recursively terminate a process and all of its descendants (make, gcc, …).
kill_tree() {
    local pid=$1 child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child"
    done
    kill "$pid" 2>/dev/null
}

on_interrupt() {
    trap '' INT TERM            # ignore further signals while cleaning up
    [ -n "$CHILD_PID" ] && kill_tree "$CHILD_PID"
    restore_cursor
    printf '\n'
    printf '  %s✗%s Interrupted by user.\n' "${RED}" "${RESET}" >&2
    exit 130
}
trap on_interrupt INT TERM
trap restore_cursor EXIT

say()   { printf '%s\n' "$*"; }
info()  { printf '  %s›%s %s\n' "$CYAN" "$RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
ok()    { printf '  %s✔%s %s\n' "$GREEN" "$RESET" "$*"; }
err()   { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*" >&2; }

banner() {
    # Fixed inner width = 47 columns; content lines are padded to match.
    printf '\n%s%s' "$MAGENTA" "$BOLD"
    printf '   ┌─────────────────────────────────────────────────┐\n'
    printf '   │  fx-9860GIII · toolchain setup                  │\n'
    printf '   │  fxSDK · SH4 cross-GCC · gint                   │\n'
    printf '   └─────────────────────────────────────────────────┘\n'
    printf '%s\n' "$RESET"
}

progress_bar() {
    # progress_bar <done> <total>
    local done=$1 total=$2 width=30 j=0 bar=""
    [ "$total" -eq 0 ] && total=1
    local filled=$(( done * width / total ))
    while [ $j -lt $width ]; do
        if [ $j -lt $filled ]; then bar="$bar█"; else bar="$bar░"; fi
        j=$((j+1))
    done
    local pct=$(( done * 100 / total ))
    printf '\n  %s[%s]%s %s%3d%%%s  %s(%d/%d done)%s\n\n' \
        "$CYAN" "$bar" "$RESET" "$BOLD" "$pct" "$RESET" "$DIM" "$done" "$total" "$RESET"
}

step_header() {
    # step_header <text>
    progress_bar "$((CURRENT-1))" "$TOTAL"
    printf '%s▸ Step %d/%d — %s%s\n' "$BOLD" "$CURRENT" "$TOTAL" "$1" "$RESET"
}

live_panel() {
    # live_panel <label> <log> <pid>
    # Shows a spinner plus the last $PANEL_TAIL lines of <log>, refreshed in place,
    # until <pid> exits. The panel is erased afterwards.
    local label=$1 log=$2 pid=$3
    # Not a terminal (piped/redirected): skip the ANSI panel, just wait quietly.
    if [ ! -t 1 ]; then
        printf '  running: %s …\n' "$label"
        while kill -0 "$pid" 2>/dev/null; do sleep 1; done
        return
    fi
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local n=${#frames[@]} i=0 start=$SECONDS
    local cols; cols=$(tput cols 2>/dev/null || echo 80)
    local maxw=$(( cols - 4 )); [ "$maxw" -lt 20 ] && maxw=20
    local height=$(( PANEL_TAIL + 2 ))   # spinner line + header + body
    local drawn=false
    tput civis 2>/dev/null || printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
        local el=$(( SECONDS - start ))
        $drawn && printf '\033[%dA' "$height"   # jump back to the top of the panel
        # spinner line
        printf '\r\033[K  %s%s%s %s %s(%02d:%02d)%s\n' \
            "$CYAN" "${frames[i % n]}" "$RESET" "$label" \
            "$DIM" "$((el/60))" "$((el%60))" "$RESET"
        # panel header
        printf '\r\033[K  %s┄┄ live output (last %d lines) ┄┄%s\n' "$DIM" "$PANEL_TAIL" "$RESET"
        # body: last PANEL_TAIL lines, CR-stripped and truncated, padded to full height
        local shown=0 line
        while IFS= read -r line; do
            printf '\r\033[K  %s%.*s%s\n' "$DIM" "$maxw" "$line" "$RESET"
            shown=$((shown+1))
        done < <(tail -n "$PANEL_TAIL" "$log" 2>/dev/null | tr -d '\r')
        while [ "$shown" -lt "$PANEL_TAIL" ]; do printf '\r\033[K\n'; shown=$((shown+1)); done
        drawn=true
        i=$((i+1))
        sleep 0.2
    done
    # erase the panel so the result line takes its place
    if $drawn; then
        printf '\033[%dA' "$height"
        local k=0; while [ "$k" -lt "$height" ]; do printf '\r\033[K\n'; k=$((k+1)); done
        printf '\033[%dA' "$height"
    fi
    tput cnorm 2>/dev/null || printf '\033[?25h'
}

run_step() {
    # run_step <label> <command...>
    local label=$1; shift
    CURRENT=$((CURRENT+1))
    step_header "$label"
    local log="$LOG_DIR/step-$CURRENT.log"
    : > "$log"
    local start=$SECONDS rc
    if $VERBOSE; then
        info "output (verbose):"
        "$@" 2>&1 | tee "$log"
        rc=${PIPESTATUS[0]}
    else
        "$@" >"$log" 2>&1 &
        CHILD_PID=$!
        live_panel "$label" "$log" "$CHILD_PID"
        wait "$CHILD_PID" 2>/dev/null; rc=$?
        CHILD_PID=""
    fi
    local el=$(( SECONDS - start ))
    if [ "$rc" -ne 0 ]; then
        err "Step failed (exit $rc, after ${el}s): $label"
        printf '\n%s── last 30 log lines ──%s\n' "$DIM" "$RESET"
        tail -n 30 "$log" 2>/dev/null | sed 's/^/    /'
        printf '%s── full log: %s ──%s\n\n' "$DIM" "$log" "$RESET"
        err "Install aborted. Fix the issue and re-run — finished steps are skipped."
        exit 1
    fi
    ok "$label  ${DIM}(${el}s)${RESET}"
}

confirm() {
    # confirm <question>  -> 0 = yes
    $ASSUME_YES && return 0
    local reply
    printf '  %s?%s %s [y/N] ' "$YELLOW" "$RESET" "$1"
    read -r reply
    case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
    sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}
for arg in "$@"; do
    case "$arg" in
        --yes|-y)     ASSUME_YES=true ;;
        --verbose|-v) VERBOSE=true ;;
        --skip-brew)  SKIP_BREW=true ;;
        --help|-h)    usage ;;
        *) err "Unknown option: $arg"; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Install steps (as functions, so run_step can run them in the background)
# ---------------------------------------------------------------------------

do_brew_pkgs() {
    local missing="" p
    for p in $BREW_PKGS; do
        if ! brew list --versions "$p" >/dev/null 2>&1; then
            missing="$missing $p"
        fi
    done
    if [ -z "$missing" ]; then
        echo "All Homebrew packages are already installed."
        return 0
    fi
    echo "Installing missing packages:$missing"
    # shellcheck disable=SC2086
    brew install $missing
}

do_giteapc() {
    mkdir -p "$BIN_DIR" "$(dirname "$GITEAPC_SRC")"
    if [ -d "$GITEAPC_SRC/.git" ]; then
        echo "GiteaPC already cloned, updating…"
        git -C "$GITEAPC_SRC" pull --ff-only
    else
        git clone https://git.planet-casio.com/Lephenixnoir/GiteaPC.git "$GITEAPC_SRC"
    fi
    # Reliable wrapper in ~/.local/bin — does not depend on GiteaPC's self-install.
    cat > "$BIN_DIR/giteapc" <<EOF
#!/bin/sh
exec python3 "$GITEAPC_SRC/giteapc.py" "\$@"
EOF
    chmod +x "$BIN_DIR/giteapc"
    "$BIN_DIR/giteapc" --version >/dev/null 2>&1 \
        || python3 "$GITEAPC_SRC/giteapc.py" --help >/dev/null
    echo "GiteaPC ready at $BIN_DIR/giteapc"
}

setup_make_wrapper() {
    # GCC 14's libgcc has a parallel-build race: objects that #include the
    # generated "libgcc_tm.h" can compile before the header-generating rule runs
    # (frequent on many-core machines). We install a make/gmake wrapper that
    # builds `all-target-libgcc` serially (-j1) while keeping `all-gcc` parallel,
    # deterministically avoiding the race without slowing the bulk of the build.
    local dir="$PREFIX/share/fx9860g-toolchain/make-wrapper"
    mkdir -p "$dir"
    cat > "$dir/make" <<'WRAP'
#!/bin/sh
tool=$(basename "$0")
self_dir=$(cd "$(dirname "$0")" && pwd)

find_real() {
    _t=$1; _o=$IFS; IFS=:
    for _d in $PATH; do
        [ -z "$_d" ] && continue
        [ "$_d" = "$self_dir" ] && continue
        if [ -x "$_d/$_t" ]; then IFS=$_o; printf '%s' "$_d/$_t"; return; fi
    done
    IFS=$_o
}
real=$(find_real "$tool")
[ -z "$real" ] && real=$(find_real make)
[ -z "$real" ] && real="/usr/bin/make"

# Only special-case the libgcc build; everything else passes straight through.
has_libgcc=0
for a in "$@"; do [ "$a" = "all-target-libgcc" ] && has_libgcc=1; done
if [ "$has_libgcc" -eq 0 ]; then
    exec "$real" "$@"
fi

# Phase 1: original flags/goals minus all-target-libgcc (keeps -jN, all-gcc, …).
pre=""
for a in "$@"; do [ "$a" = "all-target-libgcc" ] && continue; pre="$pre $a"; done
# shellcheck disable=SC2086
"$real" $pre || exit $?

# Phase 2: build libgcc serially. Drop -j* and the goals, force -j1.
rest=""
for a in "$@"; do
    case "$a" in
        -j*|all-gcc|all-target-libgcc) continue ;;
        *) rest="$rest $a" ;;
    esac
done
# shellcheck disable=SC2086
exec "$real" $rest -j1 all-target-libgcc
WRAP
    chmod +x "$dir/make"
    ln -sf "$dir/make" "$dir/gmake"
    case ":$PATH:" in *":$dir:"*) : ;; *) export PATH="$dir:$PATH" ;; esac
}

verify_sha512() {
    # verify_sha512 <file> <expected>
    local f=$1 want=$2 got
    got=$(shasum -a 512 "$f" 2>/dev/null | awk '{print $1}')
    [ -n "$got" ] && [ "$got" = "$want" ]
}

seed_prereq() {
    # seed_prereq <dir> <file> <sha512> <url1> [url2]
    # Ensures <dir>/<file> exists and matches the checksum, trying each URL.
    local dir=$1 file=$2 sum=$3 url1=$4 url2=${5:-}
    local dst="$dir/$file" u
    if [ -f "$dst" ] && verify_sha512 "$dst" "$sum"; then
        echo "  $file: present and valid"
        return 0
    fi
    for u in "$url1" "$url2"; do
        [ -z "$u" ] && continue
        echo "  $file: downloading from $u"
        if curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$dst.part" "$u" \
           && verify_sha512 "$dst.part" "$sum"; then
            mv -f "$dst.part" "$dst"
            echo "  $file: OK"
            return 0
        fi
        rm -f "$dst.part"
        echo "  $file: failed or checksum mismatch from $u"
    done
    echo "error: could not obtain a valid $file" >&2
    return 1
}

prepare_gcc_source() {
    # GCC's ./contrib/download_prerequisites fetches gmp/mpfr/mpc/isl/gettext from
    # gcc.gnu.org over plain HTTP, which is slow/unreliable and often stalls. We
    # pre-seed those tarballs from fast mirrors. configure.sh skips extraction (and
    # patching) when gcc-$VERSION/ already exists, and download_prerequisites skips
    # any tarball already present — so we reproduce extract+patch here, then seed.
    local repo="$GITEAPC_SRC/Lephenixnoir/sh-elf-gcc"
    local ver="$GCC_VERSION"
    local arch="gcc-$ver.tar.xz"

    # 1. Ensure the sh-elf-gcc repo exists (giteapc reuses this same clone later).
    if [ ! -d "$repo/.git" ]; then
        mkdir -p "$(dirname "$repo")"
        git clone https://git.planet-casio.com/Lephenixnoir/sh-elf-gcc.git "$repo"
    fi
    cd "$repo" || return 1

    # 2. Ensure the GCC source archive (fast GNU mirror).
    if [ ! -f "$arch" ]; then
        echo "  downloading $arch"
        curl -fL --retry 3 -o "$arch" "https://ftpmirror.gnu.org/gnu/gcc/gcc-$ver/$arch" || return 1
    fi

    # 3. Extract + patch exactly as configure.sh does, but only if not done yet.
    if [ ! -d "gcc-$ver" ]; then
        echo "  extracting $arch"
        unxz -c < "$arch" | tar -xf - || return 1
        echo "  applying patches/gcc-$ver-libgcc-use-soft-fp.patch"
        patch -u -N -p0 < "patches/gcc-$ver-libgcc-use-soft-fp.patch" || return 1
    else
        echo "  gcc-$ver/ already extracted — skipping extract+patch"
    fi

    # 4. Seed the download_prerequisites tarballs from fast mirrors (checksums are
    #    GCC's own contrib/prerequisites.sha512 values). Primary = fast mirror,
    #    fallback = gcc.gnu.org over HTTPS.
    local d="gcc-$ver"
    seed_prereq "$d" gmp-6.2.1.tar.bz2 \
        "8904334a3bcc5c896ececabc75cda9dec642e401fb5397c4992c4fabea5e962c9ce8bd44e8e4233c34e55c8010cc28db0545f5f750cbdbb5f00af538dc763be9" \
        "https://ftpmirror.gnu.org/gnu/gmp/gmp-6.2.1.tar.bz2" \
        "https://gcc.gnu.org/pub/gcc/infrastructure/gmp-6.2.1.tar.bz2" || return 1
    seed_prereq "$d" mpfr-4.1.0.tar.bz2 \
        "410208ee0d48474c1c10d3d4a59decd2dfa187064183b09358ec4c4666e34d74383128436b404123b831e585d81a9176b24c7ced9d913967c5fce35d4040a0b4" \
        "https://ftpmirror.gnu.org/gnu/mpfr/mpfr-4.1.0.tar.bz2" \
        "https://gcc.gnu.org/pub/gcc/infrastructure/mpfr-4.1.0.tar.bz2" || return 1
    seed_prereq "$d" mpc-1.2.1.tar.gz \
        "3279f813ab37f47fdcc800e4ac5f306417d07f539593ca715876e43e04896e1d5bceccfb288ef2908a3f24b760747d0dbd0392a24b9b341bc3e12082e5c836ee" \
        "https://ftpmirror.gnu.org/gnu/mpc/mpc-1.2.1.tar.gz" \
        "https://gcc.gnu.org/pub/gcc/infrastructure/mpc-1.2.1.tar.gz" || return 1
    seed_prereq "$d" isl-0.24.tar.bz2 \
        "aab3bddbda96b801d0f56d2869f943157aad52a6f6e6a61745edd740234c635c38231af20bc3f1a08d416a5e973a90e18249078ed8e4ae2f1d5de57658738e95" \
        "https://libisl.sourceforge.io/isl-0.24.tar.bz2" \
        "https://gcc.gnu.org/pub/gcc/infrastructure/isl-0.24.tar.bz2" || return 1
    seed_prereq "$d" gettext-0.22.tar.gz \
        "e2a58dde1cae3e6b79c03e7ef3d888f7577c1f4cba283b3b0f31123ceea8c33d7c9700e83de57104644de23e5f5c374868caa0e091f9c45edbbe87b98ee51c04" \
        "https://ftpmirror.gnu.org/gnu/gettext/gettext-0.22.tar.gz" \
        "https://gcc.gnu.org/pub/gcc/infrastructure/gettext-0.22.tar.gz" || return 1

    echo "  GCC source ready with all prerequisites pre-seeded."
}

do_toolchain() {
    # GDB requires GMP 4.2+ / MPFR 3.1+ host libraries with headers. On Apple
    # Silicon Homebrew lives in /opt/homebrew, which GDB's configure does not
    # search by default, so point CPPFLAGS/LDFLAGS at it. Scoped to this function
    # (run_step runs it in a subshell) so it does not leak into the gint build.
    local brewp
    brewp=$(brew --prefix 2>/dev/null)
    if [ -n "$brewp" ]; then
        export CPPFLAGS="-I$brewp/include -I$brewp/opt/gmp/include -I$brewp/opt/mpfr/include${CPPFLAGS:+ $CPPFLAGS}"
        export LDFLAGS="-L$brewp/lib -L$brewp/opt/gmp/lib -L$brewp/opt/mpfr/lib${LDFLAGS:+ $LDFLAGS}"
    fi

    # :noudisks2 — udisks2 is a Linux-only disk daemon that fxlink pulls in;
    # it does not exist on macOS, so disable that backend (USB transfer still works).
    #
    # -Wno-implicit-function-declaration — fxsdk-gdb-bridge.c is missing a <string.h>
    # include; Apple Clang treats implicit declarations as errors by default (GCC on
    # Linux only warns). Passed via FXSDK_CONFIGURE straight to fxSDK's CMake configure.
    FXSDK_CONFIGURE="-DCMAKE_C_FLAGS=-Wno-implicit-function-declaration" \
    giteapc install -y \
        Lephenixnoir/fxsdk:noudisks2 \
        Lephenixnoir/sh-elf-binutils \
        Lephenixnoir/sh-elf-gcc \
        Lephenixnoir/sh-elf-gdb
}

do_libs() {
    giteapc install -y \
        Lephenixnoir/OpenLibm \
        Vhex-Kernel-Core/fxlibc
}

do_gcc_rebuild() {
    # Rebuild GCC — now that the C/math libs exist it also builds libstdc++.
    giteapc install -y Lephenixnoir/sh-elf-gcc
}

do_gint() {
    # libprof (optional profiler) is intentionally omitted. Its build also targets
    # the fx-CP (ClassPad), for which gint has no build here, so `fxsdk build-cp`
    # fails with "Could NOT find Gint". gint alone is all we need for fx-9860G add-ins.
    giteapc install -y Lephenixnoir/gint
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
banner
mkdir -p "$LOG_DIR"

if [ "$(uname -s)" != "Darwin" ]; then
    warn "This script is tuned for macOS. On another OS it may need adjustments."
fi

if ! xcode-select -p >/dev/null 2>&1; then
    err "Xcode Command Line Tools are missing (git, compilers)."
    info "Install them with:  xcode-select --install"
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew is not installed."
    info "Install it from https://brew.sh and re-run this script."
    exit 1
fi

# ~/.local/bin must be on PATH for this session (giteapc, sh-elf-gcc, fxsdk…)
case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) export PATH="$BIN_DIR:$PATH" ;;
esac

# Compute the total number of steps
TOTAL=6
$SKIP_BREW || TOTAL=$((TOTAL+1))

say "Toolchain will be installed into: ${BOLD}$PREFIX${RESET}"
say "Per-step logs:                    ${DIM}$LOG_DIR${RESET}"
say ""
warn "Building the SH4 cross-compiler can take ${BOLD}30–60 minutes${RESET} and compiles a lot."
$VERBOSE || info "Tip: run with ${BOLD}--verbose${RESET} if you want to watch the build output."
say ""
if ! confirm "Start the installation?"; then
    say "Cancelled."
    exit 0
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
# binutils, GCC and GDB all bundle an old zlib whose zutil.h defines
# `#define fdopen(fd,mode) NULL` on any Apple platform (TARGET_OS_MAC is set),
# which clashes with the system <stdio.h> and breaks the build on macOS.
# Defining fdopen as a self-referential macro makes zlib's `#ifndef fdopen`
# skip that line, while real fdopen() calls still resolve to the function.
export CPPFLAGS="-Dfdopen=fdopen${CPPFLAGS:+ $CPPFLAGS}"

# Install the make wrapper that serialises the libgcc build (see the function).
setup_make_wrapper

$SKIP_BREW || run_step "Homebrew dependencies"          do_brew_pkgs
run_step "GiteaPC (package installer)"                  do_giteapc
run_step "Prepare GCC source + prerequisites"           prepare_gcc_source
run_step "fxSDK + binutils + GCC + GDB"                 do_toolchain
run_step "OpenLibm + fxlibc"                            do_libs
run_step "Rebuild GCC (libstdc++)"                      do_gcc_rebuild
run_step "gint"                                         do_gint

progress_bar "$TOTAL" "$TOTAL"   # 100%

# ---------------------------------------------------------------------------
# Persist PATH in ~/.zshrc
# ---------------------------------------------------------------------------
ZRC="$HOME/.zshrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
# Consider it handled if .zshrc already references .local/bin in any (uncommented)
# form — avoids nagging users who added it with different wording/ordering.
if grep -qsE '^[[:space:]]*[^#].*\.local/bin' "$ZRC" 2>/dev/null; then
    ok "${BOLD}$BIN_DIR${RESET} is already on your PATH via $ZRC — nothing to do."
else
    warn "Directory ${BOLD}$BIN_DIR${RESET} is not permanently on PATH yet."
    if confirm "Add the line to $ZRC?"; then
        {
            printf '\n# fx-9860GIII toolchain (fxSDK / gint) — added by install-toolchain.sh\n'
            printf '%s\n' "$PATH_LINE"
        } >> "$ZRC"
        ok "Added to $ZRC (effective in a new terminal, or run: source $ZRC)"
    else
        info "Add it manually:  $PATH_LINE"
    fi
fi

# ---------------------------------------------------------------------------
# Summary / verification
# ---------------------------------------------------------------------------
say ""
printf '%s%s══ Verifying installation ══%s\n' "$BOLD" "$GREEN" "$RESET"
check() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1  ${DIM}$($1 --version 2>&1 | head -1)${RESET}"
    else
        err "$1 not found on PATH"
    fi
}
check fxsdk
check sh-elf-gcc
check fxlink

say ""
ok "${BOLD}Done!${RESET} The toolchain is installed."
say ""
info "Open a ${BOLD}new terminal${RESET} (or run ${BOLD}source ~/.zshrc${RESET}) and verify: ${BOLD}fxsdk --version${RESET}"
info "Build an add-in project (CMakeLists.txt + src/) with: ${BOLD}fxsdk build-fx${RESET}"
say ""
