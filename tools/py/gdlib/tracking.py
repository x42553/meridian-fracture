"""Import-staleness detection: is game/.godot/ (class cache, imported assets) older than the sources?

`godot --import` is only needed when something changes that the editor caches:
  * a script that declares `class_name` appears, disappears, or changes its header (class_name / extends / @tool /
    @icon / @abstract lines) -> global_script_class_cache.cfg;
  * a scene, resource, shader, image, audio, font or model appears, disappears or is modified -> uid cache / imported/;
  * project.godot changes (autoloads, settings).
Editing the BODY of a script, or adding a script without class_name, needs no import, so it does not count. Without this
rule every keystroke of a busy agent would send everybody through a 2-second exclusive import.

snapshot() maps relative path -> signature ('m:<mtime_ns>:<size>' or 'g:<header hash>'). A per-file cache keyed on
(mtime_ns, size) (.cache/sig_cache.json, best effort, safe to delete) avoids re-reading unchanged scripts, so a full
scan is one stat() per file.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
from pathlib import Path
from typing import Dict, Tuple

from . import env

# Non-script files whose change requires `godot --import` (uid cache, imported assets, project settings).
ASSET_EXT = frozenset({
    ".tscn", ".tres", ".res", ".gdshader", ".gdshaderinc", ".godot",
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga", ".exr", ".hdr",
    ".wav", ".ogg", ".mp3", ".ttf", ".otf", ".woff", ".woff2",
    ".glb", ".gltf", ".obj", ".fbx", ".csv", ".po",
})
# Files the editor itself generates next to sources; they must not make the tree look modified.
GENERATED_SUFFIXES = (".uid", ".import")
HEADER_RE = re.compile(rb"^[ \t]*(?:@(?:tool|icon|abstract|static_unload)\b[^\n]*|class_name\b[^\n]*|extends\b[^\n]*)", re.M)


def _script_signature(path: str) -> str:
    """'' for scripts without class_name (irrelevant to the class cache), else a hash of the header lines."""
    try:
        data = Path(path).read_bytes()
    except OSError:
        return ""
    if b"class_name" not in data:
        return ""
    return hashlib.blake2b(b"\n".join(m.group(0).strip() for m in HEADER_RE.finditer(data)), digest_size=8).hexdigest()


def _load_sig_cache(path: Path) -> Dict[str, list]:
    try:
        return json.loads(path.read_text()).get("files", {})
    except (OSError, ValueError, AttributeError):
        return {}


def _save_sig_cache(path: Path, files: Dict[str, list]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(f".{os.getpid()}.tmp")
        tmp.write_text(json.dumps({"v": 1, "files": files}))
        os.replace(tmp, path)
    except OSError:
        pass  # purely an optimisation


def snapshot(game: Path, sig_cache: "Path | None" = None) -> Dict[str, str]:
    """rel path -> signature for every file that matters to the import cache (see module docstring)."""
    cached = _load_sig_cache(sig_cache) if sig_cache else {}
    fresh: Dict[str, list] = {}
    out: Dict[str, str] = {}
    stack = [game]
    while stack:
        d = stack.pop()
        try:
            entries = sorted(os.scandir(d), key=lambda e: e.name)
        except OSError:
            continue
        if d != game and any(e.name == ".gdignore" for e in entries):
            continue
        for e in entries:
            if e.name.startswith("."):
                continue
            try:
                if e.is_dir(follow_symlinks=False):
                    stack.append(Path(e.path))
                    continue
                if e.name.endswith(GENERATED_SUFFIXES):
                    continue
                ext = os.path.splitext(e.name)[1].lower()
                if ext != ".gd" and ext not in ASSET_EXT:
                    continue
                st = e.stat()
            except OSError:
                continue  # vanished while scanning
            rel = os.path.relpath(e.path, game).replace(os.sep, "/")
            if ext == ".gd":
                hit = cached.get(rel)
                if hit and hit[0] == st.st_mtime_ns and hit[1] == st.st_size:
                    sig = hit[2]
                else:
                    sig = _script_signature(e.path)
                fresh[rel] = [st.st_mtime_ns, st.st_size, sig]
                if sig:
                    out[rel] = "g:" + sig
            else:
                out[rel] = f"m:{st.st_mtime_ns}:{st.st_size}"
    if sig_cache and fresh != cached:
        _save_sig_cache(sig_cache, fresh)
    return out


def digest(snap: Dict[str, str]) -> str:
    h = hashlib.blake2b(digest_size=16)
    for rel in sorted(snap):
        h.update(f"{rel}\0{snap[rel]}\n".encode())
    return h.hexdigest()


def engine_id(binary: Path) -> str:
    try:
        st = binary.stat()
        return f"{binary}|{st.st_size}|{st.st_mtime_ns}"
    except OSError:
        return f"{binary}|missing"


def diff_reason(old: Dict[str, str], new: Dict[str, str], limit: int = 3) -> str:
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(k for k in set(old) & set(new) if old[k] != new[k])
    parts = []
    for label, items in (("new", added), ("removed", removed), ("changed", changed)):
        if items:
            parts.append(f"{label}: {', '.join(items[:limit])}" + (f" (+{len(items) - limit} more)" if len(items) > limit else ""))
    return "; ".join(parts) or "project files changed"


class ImportState:
    """Marker file stored next to the lock (default .cache/import_state.json)."""

    def __init__(self, path: Path, game: Path, binary: Path, required: Tuple[str, ...] = ("global_script_class_cache.cfg",)) -> None:
        self.path = path
        self.game = game
        self.binary = binary
        self.required = required
        self.sig_cache = path.parent / "sig_cache.json"

    def snapshot(self) -> Dict[str, str]:
        return snapshot(self.game, self.sig_cache)

    def load(self) -> Dict[str, object]:
        try:
            return json.loads(self.path.read_text())
        except (OSError, ValueError):
            return {}

    def is_stale(self) -> Tuple[bool, str]:
        """(stale?, reason)."""
        state = self.load()
        if not state:
            return True, "no import marker yet"
        for name in self.required:
            if not (self.game / ".godot" / name).exists():
                return True, f".godot/{name} is missing"
        if state.get("engine") != engine_id(self.binary):
            return True, "engine binary changed"
        now = self.snapshot()
        old = state.get("entries", {})
        if isinstance(old, dict) and old != now:
            return True, diff_reason(old, now)  # type: ignore[arg-type]
        return False, "up to date"

    def save(self, snap: Dict[str, str], seconds: float) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(f".{os.getpid()}.tmp")
        tmp.write_text(json.dumps({
            "fingerprint": digest(snap),
            "files": len(snap),
            "engine": engine_id(self.binary),
            "imported_unix": int(time.time()),
            "seconds": round(seconds, 2),
            "entries": snap,
        }))
        os.replace(tmp, self.path)  # atomic
