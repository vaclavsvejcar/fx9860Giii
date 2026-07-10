#!/usr/bin/env bash
#
# deploy.sh — launcher for the fx-9860GIII add-in deployment TUI.
#
# Provisions a private virtualenv with Textual (one-time) and runs deploy_tui.py,
# a full-screen TUI to build / detect / install / remove this repo's add-ins on
# the calculator over USB.
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
VENV="$REPO/.venv"
PY="$VENV/bin/python"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required (install it via Homebrew: brew install python3)." >&2
    exit 1
fi

# Create the venv and install Textual on first run (macOS python is PEP 668
# externally-managed, so an isolated venv is the clean way to add packages).
if [ ! -x "$PY" ]; then
    echo "Setting up the TUI environment (one-time)…"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet textual
fi

# Self-heal if the venv exists but Textual is missing/broken.
if ! "$PY" -c "import textual" >/dev/null 2>&1; then
    echo "Installing Textual…"
    "$VENV/bin/pip" install --quiet textual
fi

exec "$PY" "$REPO/deploy_tui.py" "$@"
