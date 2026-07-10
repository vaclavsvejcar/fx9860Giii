#!/usr/bin/env python3
"""
Textual TUI to install / reinstall / remove this repo's fx-9860GIII add-ins on
the calculator over USB.

The fx-9860GIII (G-III series) connects as USB Mass Storage; on macOS its storage
mounts as a removable volume under /Volumes, and installing an add-in means copying
its .g1a onto that volume. A fixed status bar at the bottom reflects the connection
state (green = connected, orange = ambiguous, red = not connected) and refreshes on
its own every couple of seconds.

Launched by ./deploy.sh (which provisions the venv). Requires: textual.
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
from pathlib import Path

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Header, ListView, ListItem, Label, RichLog, Static

REPO = Path(__file__).resolve().parent
LOCAL_BIN = str(Path.home() / ".local" / "bin")
POLL_SECONDS = 2.0


# ---------------------------------------------------------------------------
# Discovery + detection (plain functions, safe to call from a worker thread)
# ---------------------------------------------------------------------------
def discover_apps() -> list[dict]:
    apps: list[dict] = []
    for cml in sorted(REPO.glob("*/CMakeLists.txt")):
        text = cml.read_text(errors="ignore")
        if "generate_g1a" not in text:
            continue
        block = re.search(r"generate_g1a\((.*?)\)", text, re.S)
        region = block.group(1) if block else text
        g1a = re.search(r'OUTPUT\s+"([^"]+\.g1a)"', region)
        name = re.search(r'NAME\s+"([^"]+)"', region)
        d = cml.parent
        apps.append(
            {
                "dir": d.name,
                "name": name.group(1) if name else d.name,
                "g1a": g1a.group(1) if g1a else f"{d.name}.g1a",
                "path": d,
            }
        )
    return apps


def _device_of(mount: Path) -> str | None:
    try:
        out = subprocess.run(
            ["df", str(mount)], capture_output=True, text=True, timeout=5
        ).stdout.strip().splitlines()
        return out[-1].split()[0] if out else None
    except Exception:
        return None


def detect_calc() -> tuple[Path | None, list[Path]]:
    """Return (single_volume_or_None, all_candidate_volumes).

    A candidate is a USB removable volume under /Volumes (the G-III's flash).
    Fixed external drives such as a Time Machine disk report "Fixed" and are
    excluded; system volumes are skipped by name.
    """
    candidates: list[Path] = []
    vroot = Path("/Volumes")
    if not vroot.exists():
        return None, []
    for mp in sorted(vroot.iterdir()):
        if not mp.is_dir():
            continue
        if mp.name in ("Macintosh HD", "Data", "TimeMachine") or mp.name.startswith("com.apple."):
            continue
        dev = _device_of(mp)
        if not dev:
            continue
        try:
            info = subprocess.run(
                ["diskutil", "info", dev], capture_output=True, text=True, timeout=5
            ).stdout
        except Exception:
            continue
        if re.search(r"Removable Media:\s*Removable", info):
            candidates.append(mp)
    return (candidates[0] if len(candidates) == 1 else None), candidates


# ---------------------------------------------------------------------------
# The app
# ---------------------------------------------------------------------------
class DeployApp(App):
    CSS = """
    Screen { layout: vertical; }

    #apps {
        height: 42%;
        border: round $accent;
        border-title-color: $accent;
        margin: 1 1 0 1;
    }
    #log {
        height: 1fr;
        border: round $surface-lighten-2;
        border-title-color: $text-muted;
        margin: 0 1;
        padding: 0 1;
    }

    #status {
        dock: bottom;
        height: 1;
        padding: 0 1;
        color: black;
        background: $warning;      /* default until first poll */
        text-style: bold;
    }
    #status.connected { background: $success; color: black; }
    #status.warning   { background: $warning; color: black; }
    #status.error     { background: $error;   color: white; }
    """

    BINDINGS = [
        Binding("i", "install", "Install"),
        Binding("b", "build", "Build only"),
        Binding("r", "remove", "Remove"),
        Binding("d", "detect", "Re-detect"),
        Binding("q", "quit", "Quit"),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.apps = discover_apps()
        self.calc_vol: Path | None = None
        self.calc_cands: list[Path] = []
        self.item_labels: list[Label] = []
        self._last_vol: object = "INIT"   # sentinel to force the first relabel
        self.busy = False

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        lv = ListView(id="apps")
        lv.border_title = "Add-ins  ·  ↑/↓ select"
        yield lv
        rl = RichLog(id="log", markup=True, wrap=True, highlight=False)
        rl.border_title = "Output"
        yield rl
        yield Static("", id="status")

    def on_mount(self) -> None:
        self.title = "fx-9860GIII"
        self.sub_title = "add-in deployment"
        lv = self.query_one("#apps", ListView)
        for a in self.apps:
            lbl = Label(self._app_label(a, None))
            self.item_labels.append(lbl)
            lv.append(ListItem(lbl))
        if self.apps:
            lv.index = 0
        lv.focus()
        self._log("[b]i[/] install/reinstall   [b]b[/] build only   [b]r[/] remove   [b]d[/] re-detect   [b]q[/] quit")
        if not self.apps:
            self._log("[red]No add-ins found (no */CMakeLists.txt with generate_g1a).[/]")
        self.refresh_status()
        self.set_interval(POLL_SECONDS, self.refresh_status)

    # -- helpers -----------------------------------------------------------
    def _log(self, msg: str) -> None:
        self.query_one("#log", RichLog).write(msg)

    @staticmethod
    def _sha256(p: Path) -> str:
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()

    def install_status(self, a: dict, vol: Path | None) -> str | None:
        """None (unknown/no calc) | absent | match | differ | present."""
        if vol is None:
            return None
        on_calc = vol / a["g1a"]
        if not on_calc.exists():
            return "absent"
        local = self._locate_g1a(a)
        if not local:
            return "present"
        try:
            return "match" if self._sha256(local) == self._sha256(on_calc) else "differ"
        except Exception:
            return "present"

    def _app_label(self, a: dict, vol: Path | None) -> str:
        badge = {
            None: "",
            "absent": "[dim]○ not installed[/]",
            "match": "[$success]✓ up to date[/]",
            "differ": "[$warning]▲ differs — reinstall[/]",
            "present": "[$accent]● installed[/]",
        }[self.install_status(a, vol)]
        return f"[b]{a['name']}[/]   [dim]{a['dir']}/  →  {a['g1a']}[/]   {badge}"

    def update_app_labels(self) -> None:
        vol = self.calc_vol or (self.calc_cands[0] if self.calc_cands else None)
        for lbl, a in zip(self.item_labels, self.apps):
            lbl.update(self._app_label(a, vol))

    def _selected(self) -> dict | None:
        lv = self.query_one("#apps", ListView)
        i = lv.index
        if i is None or not (0 <= i < len(self.apps)):
            return None
        return self.apps[i]

    def refresh_status(self) -> None:
        if self.busy:
            return
        vol, cands = detect_calc()
        self.calc_vol, self.calc_cands = vol, cands
        # Recompute install badges only when the connected volume changes, to
        # avoid re-hashing files over USB on every 2 s poll.
        effective = vol or (cands[0] if cands else None)
        if effective != self._last_vol:
            self._last_vol = effective
            self.update_app_labels()
        sb = self.query_one("#status", Static)
        sb.remove_class("connected", "warning", "error")
        keys = "[i] install   [b] build   [r] remove   [d] re-detect   [q] quit"
        if vol:
            sb.add_class("connected")
            sb.update(f" ● CONNECTED   {vol}          {keys}")
        elif len(cands) > 1:
            sb.add_class("warning")
            names = ", ".join(p.name for p in cands)
            sb.update(f" ● MULTIPLE removable volumes ({names}) — first is used          {keys}")
        else:
            sb.add_class("error")
            sb.update(" ○ NOT CONNECTED   plug USB, choose 'USB Flash' on the calc          [d] re-detect   [q] quit")

    def _env(self) -> dict:
        env = dict(os.environ)
        env["PATH"] = LOCAL_BIN + ":" + env.get("PATH", "")
        return env

    def _target_volume(self) -> Path | None:
        vol, cands = detect_calc()
        return vol or (cands[0] if cands else None)

    def _locate_g1a(self, a: dict) -> Path | None:
        for p in (a["path"] / a["g1a"], a["path"] / "build-fx" / a["g1a"]):
            if p.exists():
                return p
        return None

    # -- actions -----------------------------------------------------------
    def action_install(self) -> None:
        a = self._selected()
        if a and not self.busy:
            self.run_task(a, copy=True)

    def action_build(self) -> None:
        a = self._selected()
        if a and not self.busy:
            self.run_task(a, copy=False)

    def action_remove(self) -> None:
        a = self._selected()
        if a and not self.busy:
            self.remove_task(a)

    def action_detect(self) -> None:
        self.refresh_status()
        self._log("[dim]Re-detected.[/]")

    # -- workers -----------------------------------------------------------
    @work(thread=True, exclusive=True)
    def run_task(self, a: dict, copy: bool) -> None:
        self.busy = True
        try:
            self.call_from_thread(self._log, f"\n[b]▸ Building {a['name']}…[/]")
            proc = subprocess.Popen(
                ["fxsdk", "build-fx"],
                cwd=str(a["path"]),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=self._env(),
            )
            assert proc.stdout is not None
            for line in proc.stdout:
                self.call_from_thread(self._log, "  [dim]" + line.rstrip() + "[/]")
            if proc.wait() != 0:
                self.call_from_thread(self._log, "[red]✗ Build failed.[/]")
                return
            src = self._locate_g1a(a)
            if not src:
                self.call_from_thread(self._log, f"[red]✗ Built .g1a not found ({a['g1a']}).[/]")
                return
            size = src.stat().st_size // 1024
            self.call_from_thread(self._log, f"[green]✓ Built {a['g1a']} ({size} kB).[/]")
            if not copy:
                return
            vol = self._target_volume()
            if not vol:
                self.call_from_thread(
                    self._log,
                    "[yellow]Calculator not connected — plug USB, choose 'USB Flash', then press [b]i[/] again.[/]",
                )
                return
            try:
                shutil.copy2(src, vol)
                subprocess.run(["sync"])
                self.call_from_thread(
                    self._log,
                    f"[green]✓ Copied {a['g1a']} → {vol}[/]  [dim]Eject safely; the add-in appears in the main menu.[/]",
                )
                self.call_from_thread(self.update_app_labels)
            except Exception as exc:
                self.call_from_thread(self._log, f"[red]✗ Copy failed: {exc}[/]")
        finally:
            self.busy = False

    @work(thread=True)
    def remove_task(self, a: dict) -> None:
        vol = self._target_volume()
        if not vol:
            self.call_from_thread(self._log, "[yellow]Calculator not connected.[/]")
            return
        target = vol / a["g1a"]
        if target.exists():
            try:
                target.unlink()
                subprocess.run(["sync"])
                self.call_from_thread(self._log, f"[green]✓ Removed {a['g1a']} from {vol}.[/]")
                self.call_from_thread(self.update_app_labels)
            except Exception as exc:
                self.call_from_thread(self._log, f"[red]✗ {exc}[/]")
        else:
            self.call_from_thread(
                self._log,
                f"[yellow]{a['g1a']} is not on {vol}.[/] [dim]An installed add-in is removed on the calc: MENU → MEMORY.[/]",
            )


if __name__ == "__main__":
    DeployApp().run()
