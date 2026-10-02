"""Paths, engine binary resolution and small shared helpers for tools/gd.

Environment overrides (all optional):
  GD_ROOT      project root (default: the directory that contains tools/). Used by the self-tests to run
               gd against a throw-away project; every path below derives from it.
  GD_GAME_DIR  Godot project directory (default: <root>/game)
  GODOT_BIN    Godot executable to use instead of the one under tools/ (CI sets this)
  GD_TRACE_FILE  append lock/exec events to this file (used by the concurrency proof)
"""
from __future__ import annotations

import os
import platform
import shutil
import sys
from pathlib import Path

GODOT_VERSION = "4.7.2"
GODOT_STATUS = "stable"

TOOLS_DIR = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("GD_ROOT") or TOOLS_DIR.parent).resolve()
GAME = Path(os.environ.get("GD_GAME_DIR") or (ROOT / "game")).resolve()
CACHE = ROOT / ".cache"
BACKUPS = ROOT / ".backups"
DOCS_ROOT = TOOLS_DIR / "godot_docs"

MAC_BIN = TOOLS_DIR / "godot" / "Godot.app" / "Contents" / "MacOS" / "Godot"
LINUX_BINS = {
    "amd64": TOOLS_DIR / "godot-linux-x86_64" / f"Godot_v{GODOT_VERSION}-{GODOT_STATUS}_linux.x86_64",
    "arm64": TOOLS_DIR / "godot-linux-arm64" / f"Godot_v{GODOT_VERSION}-{GODOT_STATUS}_linux.arm64",
}


def host_arch() -> str:
    """'amd64' or 'arm64' for the machine gd runs on."""
    m = platform.machine().lower()
    return "arm64" if m in ("arm64", "aarch64") else "amd64"


def godot_bin() -> Path:
    """The Godot editor binary for the host OS (GODOT_BIN overrides)."""
    override = os.environ.get("GODOT_BIN")
    if override:
        return Path(override)
    if sys.platform == "darwin" and MAC_BIN.exists():
        return MAC_BIN
    if sys.platform.startswith("linux"):
        native = LINUX_BINS[host_arch()]
        if native.exists():
            return native
    found = shutil.which("godot") or shutil.which("Godot")
    if found:
        return Path(found)
    if sys.platform == "darwin":
        return MAC_BIN  # let the caller report a precise 'missing' error
    return LINUX_BINS[host_arch()]


def die(msg: str, code: int = 2) -> "None":
    print(f"gd: {msg}", file=sys.stderr)
    raise SystemExit(code)


def rel_to_root(p: "str | Path") -> str:
    """Project-root-relative display path (falls back to the input)."""
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except (ValueError, OSError):
        return str(p)


def res_to_display(res_path: str) -> str:
    """res://src/x.gd -> game/src/x.gd (relative to the project root, clickable in most terminals)."""
    if res_path.startswith("res://"):
        try:
            return str((GAME / res_path[len("res://"):]).relative_to(ROOT))
        except ValueError:
            return res_path
    return res_path


def to_res_path(arg: str) -> str:
    """Normalise a user supplied path to res://: accepts res://x, game/x, x (relative to game/), or an
    absolute path inside the game directory."""
    if arg.startswith("res://"):
        return arg
    p = Path(arg)
    if p.is_absolute():
        try:
            return "res://" + p.resolve().relative_to(GAME).as_posix()
        except ValueError:
            die(f"path is outside the Godot project ({GAME}): {arg}")
    parts = p.parts
    if parts and parts[0] == "game":
        p = Path(*parts[1:]) if len(parts) > 1 else Path(".")
    s = p.as_posix()
    return "res://" + ("" if s == "." else s)


def project_version() -> str:
    """application/config/version from game/project.godot (falls back to 0.0.0)."""
    import re
    try:
        m = re.search(r'^config/version="([^"]+)"', (GAME / "project.godot").read_text(), re.M)
        return m.group(1) if m else "0.0.0"
    except OSError:
        return "0.0.0"
