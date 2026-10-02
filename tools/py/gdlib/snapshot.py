"""`gd snapshot [label]`: tar.zst of the source tree into .backups/ (cheap insurance while many agents edit)."""
from __future__ import annotations

import datetime
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import List, Tuple

from . import env

# Directories (matched against the project-root-relative posix path) that are pruned entirely.
EXCLUDE_DIRS = [
    "tools/godot", "tools/godot-*", "tools/godot_*",   # engines + class reference: re-downloadable, hundreds of MB
    ".cache", ".backups", "builds", "game/.godot", "game/.import", "prototypes/*/.godot",
]
# File / directory base names excluded anywhere.
EXCLUDE_NAMES = ["__pycache__", ".DS_Store", "*.pyc"]


def excluded_dir(rel: str) -> bool:
    return any(fnmatch.fnmatch(rel, pat) for pat in EXCLUDE_DIRS) or any(fnmatch.fnmatch(rel.rsplit("/", 1)[-1], pat) for pat in EXCLUDE_NAMES)


def excluded_file(rel: str) -> bool:
    return any(fnmatch.fnmatch(rel.rsplit("/", 1)[-1], pat) for pat in EXCLUDE_NAMES)


def gather(root: Path) -> Tuple[List[Path], int]:
    files: List[Path] = []
    skipped = 0
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root).replace(os.sep, "/")
        rel_dir = "" if rel_dir == "." else rel_dir
        dirnames[:] = sorted(d for d in dirnames if not excluded_dir(f"{rel_dir}/{d}".lstrip("/")))
        for name in sorted(filenames):
            rel = f"{rel_dir}/{name}".lstrip("/")
            if excluded_file(rel):
                skipped += 1
                continue
            files.append(Path(dirpath) / name)
    return files, skipped


def cmd_snapshot(args: "object") -> int:
    if getattr(args, "list", False):
        for p in sorted(env.BACKUPS.glob("meridian-*.tar.*")):
            print(f"{p.stat().st_size / 1e6:8.2f} MB  {p.relative_to(env.ROOT)}")
        return 0
    label = re.sub(r"[^a-z0-9_]+", "_", (getattr(args, "label", "") or "").lower()).strip("_")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    env.BACKUPS.mkdir(parents=True, exist_ok=True)
    zstd = shutil.which("zstd")
    suffix = ".tar.zst" if zstd else ".tar.gz"
    dest = env.BACKUPS / f"meridian-{stamp}{'-' + label if label else ''}{suffix}"
    files, _ = gather(env.ROOT)
    vanished = 0
    tmp = dest.with_suffix(dest.suffix + ".part")
    if zstd:
        with open(tmp, "wb") as out:
            proc = subprocess.Popen([zstd, "-q", "-T0", "-3", "-c"], stdin=subprocess.PIPE, stdout=out)
            assert proc.stdin is not None
            with tarfile.open(fileobj=proc.stdin, mode="w|") as tf:
                for p in files:
                    try:
                        tf.add(p, arcname=str(p.relative_to(env.ROOT)), recursive=False)
                    except (FileNotFoundError, PermissionError):
                        vanished += 1  # edited/removed by another agent while we archive: skip
            proc.stdin.close()
            rc = proc.wait()
        if rc != 0:
            env.die(f"zstd failed (exit {rc})", 1)
        check = subprocess.run([zstd, "-t", "-q", str(tmp)])
        if check.returncode != 0:
            env.die("archive failed its zstd integrity test", 1)
    else:
        print("gd snapshot: zstd not found, falling back to .tar.gz", file=sys.stderr)
        with tarfile.open(tmp, "w:gz") as tf:
            for p in files:
                try:
                    tf.add(p, arcname=str(p.relative_to(env.ROOT)), recursive=False)
                except (FileNotFoundError, PermissionError):
                    vanished += 1
    tmp.replace(dest)
    print(f"{dest}\n{dest.stat().st_size / 1e6:.2f} MB, {len(files) - vanished} files"
          + (f", {vanished} vanished while archiving" if vanished else ""))
    return 0
