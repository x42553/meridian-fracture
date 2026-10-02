#!/usr/bin/env python3
"""Download + verify the Godot 4.7.2 binaries this repo uses (sha512 against the official SHA512-SUMS.txt).

    tools/py/fetch_engines.py [--all] [--macos] [--linux-x86_64] [--linux-arm64] [--templates] [--verify-only]

Everything lands in .cache/ (archives) and tools/ (extracted engines, git-ignored):
    tools/godot/Godot.app                    macOS universal editor
    tools/godot-linux-x86_64/Godot_v4.7.2-stable_linux.x86_64   Linux editor used by `gd linux` (amd64 container)
    tools/godot-linux-arm64/Godot_v4.7.2-stable_linux.arm64     Linux editor for the arm64 container
    .cache/godot_export_templates.tpz        install with tools/py/export.py install-templates
Default (no flags): whatever is missing for the current host plus the Linux engines.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gdlib import env  # noqa: E402

BASE = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/"
V = "Godot_v4.7.2-stable"
ARCHIVES = {
    "macos": (f"{V}_macos.universal.zip", "godot_macos.zip"),
    "linux-x86_64": (f"{V}_linux.x86_64.zip", "godot_linux_x86_64.zip"),
    "linux-arm64": (f"{V}_linux.arm64.zip", "godot_linux_arm64.zip"),
    "windows": (f"{V}_win64.exe.zip", "godot_win64.zip"),
    "templates": (f"{V}_export_templates.tpz", "godot_export_templates.tpz"),
}
# binary inside each engine archive (relative to the extraction dir); the windows console build is used so stdout is captured
CI_BINARIES = {
    "macos": "Godot.app/Contents/MacOS/Godot",
    "linux-x86_64": f"{V}_linux.x86_64",
    "linux-arm64": f"{V}_linux.arm64",
    "windows": f"{V}_win64_console.exe",
}


def sha512(path: Path) -> str:
    h = hashlib.sha512()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def official_sums() -> dict:
    with urllib.request.urlopen(BASE + "SHA512-SUMS.txt", timeout=60) as r:
        text = r.read().decode()
    return {name: digest for digest, name in (line.split(None, 1) for line in text.splitlines() if line.strip())}


def download(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url, timeout=60) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)
    tmp.replace(dest)


def fetch(key: str, sums: dict, verify_only: bool) -> Path:
    remote, local = ARCHIVES[key]
    dest = env.CACHE / local
    env.CACHE.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        if verify_only:
            print(f"{key}: not downloaded")
            return dest
        print(f"{key}: downloading {remote} ...")
        download(BASE + remote, dest)
    digest = sha512(dest)
    ok = digest == sums.get(remote)
    print(f"{key}: sha512 {'OK' if ok else 'MISMATCH'} ({dest.stat().st_size / 1e6:.0f} MB)")
    if not ok:
        raise SystemExit(f"checksum mismatch for {dest}; delete it and retry")
    return dest


def extract_linux(key: str, archive: Path, target_dir: Path, binary: str) -> None:
    if (target_dir / binary).exists():
        return
    target_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extract(binary, target_dir)
    (target_dir / binary).chmod(0o755)
    print(f"{key}: extracted {target_dir / binary}")


def ci(key: str, dest: Path, github_env: bool) -> int:
    """CI mode: download + verify one engine (or the templates) into `dest` and print/export GODOT_BIN."""
    sums = official_sums()
    remote, local = ARCHIVES[key]
    dest = dest.resolve()
    dest.mkdir(parents=True, exist_ok=True)
    archive = dest / local
    if not archive.exists():
        print(f"downloading {remote} ...")
        download(BASE + remote, archive)
    if sha512(archive) != sums.get(remote):
        raise SystemExit(f"sha512 mismatch for {remote}")
    print(f"{remote}: sha512 OK")
    if key == "templates":
        print(f"TEMPLATES_TPZ={archive}")
        if github_env and os.environ.get("GITHUB_ENV"):
            with open(os.environ["GITHUB_ENV"], "a") as f:
                f.write(f"TEMPLATES_TPZ={archive}\n")
        return 0
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(dest / "engine")
    binary = dest / "engine" / CI_BINARIES[key]
    if not binary.exists():
        raise SystemExit(f"expected {binary} after extraction")
    if sys.platform != "win32":
        binary.chmod(0o755)
    print(f"GODOT_BIN={binary}")
    if github_env and os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a") as f:
            f.write(f"GODOT_BIN={binary}\n")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ci", choices=["macos", "linux-x86_64", "linux-arm64", "windows", "templates"],
                    help="CI mode: fetch one engine/templates archive into --dest and print GODOT_BIN (used by .github/workflows/build.yml)")
    ap.add_argument("--dest", default=".cache/ci", help="with --ci: download/extraction directory")
    ap.add_argument("--github-env", action="store_true", help="with --ci: also append GODOT_BIN / TEMPLATES_TPZ to $GITHUB_ENV")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--macos", action="store_true")
    ap.add_argument("--linux-x86_64", action="store_true")
    ap.add_argument("--linux-arm64", action="store_true")
    ap.add_argument("--templates", action="store_true")
    ap.add_argument("--verify-only", action="store_true", help="only check archives that already exist")
    a = ap.parse_args()
    if a.ci:
        return ci(a.ci, Path(a.dest), a.github_env)
    want = {"macos": a.macos, "linux-x86_64": a.linux_x86_64, "linux-arm64": a.linux_arm64, "templates": a.templates}
    if a.all or not any(want.values()):
        want = {"macos": sys.platform == "darwin" or a.all, "linux-x86_64": True, "linux-arm64": True, "templates": a.all}
    sums = official_sums()
    for key, wanted in want.items():
        if not wanted:
            continue
        archive = fetch(key, sums, a.verify_only)
        if a.verify_only or not archive.exists():
            continue
        if key == "linux-x86_64":
            extract_linux(key, archive, env.TOOLS_DIR / "godot-linux-x86_64", f"{V}_linux.x86_64")
        elif key == "linux-arm64":
            extract_linux(key, archive, env.TOOLS_DIR / "godot-linux-arm64", f"{V}_linux.arm64")
        elif key == "macos" and not env.MAC_BIN.exists():
            with zipfile.ZipFile(archive) as zf:
                zf.extractall(env.TOOLS_DIR / "godot")
            env.MAC_BIN.chmod(0o755)
            print(f"macos: extracted {env.MAC_BIN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
