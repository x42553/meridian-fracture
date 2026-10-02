#!/usr/bin/env python3
"""Export helper: install export templates, export Windows/Linux/macOS builds, smoke-test them.

    tools/py/export.py install-templates [--tpz .cache/godot_export_templates.tpz] [--force]
    tools/py/export.py export windows|linux|macos|all [--debug] [--no-smoke]
    tools/py/export.py smoke  windows|linux|macos|all          # run the exported binary with --smoke (host OS only)
    tools/py/export.py report                                   # sizes of everything under builds/

Presets live in game/export_presets.cfg ('Windows Desktop', 'Linux', 'macOS'); output goes to
builds/<platform>/. Exports hold the EXCLUSIVE gd lock (an export rescans and may rewrite game/.godot).
Windows export needs neither rcedit nor wine: resource modification is disabled in the preset.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from gdlib import commands, env  # noqa: E402
from gdlib.godotrun import run_process  # noqa: E402

VERSION_DIR = "4.7.2.stable"
APP_NAME = "MeridianFracture"
PLATFORMS = {
    # key: (preset name, output path relative to builds/, host smoke binary relative to builds/)
    # the release .exe is a GUI-subsystem program without stdout; the console wrapper next to it (preset option
    # debug/export_console_wrapper=2) is what smoke tests and players' log capture use
    "windows": ("Windows Desktop", f"windows/{APP_NAME}.exe", f"windows/{APP_NAME}.console.exe"),
    "linux": ("Linux", f"linux/{APP_NAME}.x86_64", f"linux/{APP_NAME}.x86_64"),
    # the Godot exporter names the Mach-O after application/config/name ("Meridian Fracture", with a space)
    "macos": ("macOS", f"macos/{APP_NAME}.app", f"macos/{APP_NAME}.app/Contents/MacOS/Meridian Fracture"),
}
BUILDS = env.ROOT / "builds"


def templates_dir() -> Path:
    if sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot" / "export_templates"
    elif sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", str(Path.home()))) / "Godot" / "export_templates"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "godot" / "export_templates"
    return base / VERSION_DIR


def install_templates(tpz: Path, force: bool) -> int:
    dest = templates_dir()
    if not tpz.exists():
        env.die(f"template archive not found: {tpz} (download Godot_v4.7.2-stable_export_templates.tpz from the official release)", 2)
    with zipfile.ZipFile(tpz) as zf:
        bad = zf.testzip()
        if bad:
            env.die(f"corrupt archive, first bad member: {bad}", 1)
        members = [m for m in zf.infolist() if m.filename.startswith("templates/") and not m.is_dir()]
        version = zf.read("templates/version.txt").decode().strip()
        if version != VERSION_DIR:
            env.die(f"archive is for {version}, this project needs {VERSION_DIR}", 1)
        dest.mkdir(parents=True, exist_ok=True)
        todo = []
        for m in members:
            target = dest / m.filename[len("templates/"):]
            if force or not target.exists() or target.stat().st_size != m.file_size:
                todo.append((m, target))
        t0 = time.time()
        for m, target in todo:
            with zf.open(m) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)
            os.chmod(target, 0o755 if target.suffix in ("", ".x86_64", ".arm64", ".arm32", ".x86_32") and "linux" in target.name else 0o644)
    total = sum(p.stat().st_size for p in dest.iterdir() if p.is_file())
    print(f"templates: {len(members)} files ({total / 1e9:.2f} GB) in {dest}; installed {len(todo)} this run in {time.time() - t0:.0f}s; "
          f"version.txt = {(dest / 'version.txt').read_text().strip()}")
    return 0


def dir_size(p: Path) -> int:
    if p.is_file():
        return p.stat().st_size
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file())


def export_one(ctx: commands.Ctx, key: str, debug: bool) -> dict:
    preset, rel_out, _smoke = PLATFORMS[key]
    out = BUILDS / rel_out
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.is_dir():
        shutil.rmtree(out)  # our own previous .app bundle
    elif out.exists():
        out.unlink()
    flag = "--export-debug" if debug else "--export-release"
    t0 = time.time()
    res = run_process(ctx.godot("--headless", flag, preset, str(out)), timeout=900, stall_after_error=120, verbose=ctx.verbose, prefix=f"  export[{key}]> ")
    ok = res.rc == 0 and out.exists() and not any("ERROR: Cannot export" in l or "ERROR: Export" in l for l in res.error_lines)
    report = {"platform": key, "preset": preset, "ok": ok, "seconds": round(time.time() - t0, 1), "path": str(out.relative_to(env.ROOT)),
              "bytes": dir_size(out) if out.exists() else 0, "engine_errors": res.error_lines[:5]}
    siblings = [p for p in sorted(out.parent.iterdir()) if p != out]
    report["siblings"] = {p.name: dir_size(p) for p in siblings}
    return report


def smoke(key: str) -> dict:
    _preset, _out, rel_bin = PLATFORMS[key]
    binary = BUILDS / rel_bin
    host_ok = {"macos": sys.platform == "darwin", "linux": sys.platform.startswith("linux"), "windows": sys.platform.startswith("win")}[key]
    if not host_ok:
        return {"platform": key, "smoke": "skipped (different host OS)"}
    if not binary.exists():
        return {"platform": key, "smoke": "FAILED: binary missing"}
    lines = {}
    runs = [("headless", ["--headless", "--smoke"])]
    # A real window + renderer needs a display and a GPU: skipped on CI runners (no GPU / no display) and on headless Linux.
    if not os.environ.get("CI") and (not sys.platform.startswith("linux") or os.environ.get("DISPLAY")):
        runs.append(("windowed", ["--smoke"]))
    for label, extra in runs:
        res = run_process([str(binary), *extra], timeout=60, stall_after_error=None, echo=False)
        boot = next((l for l in res.lines if l.startswith("MERIDIAN_BOOT")), None)
        lines[label] = {"rc": res.rc, "line": boot}
    ok = all(v["rc"] == 0 and v["line"] for v in lines.values())
    result = {"platform": key, "smoke": "OK" if ok else "FAILED", "runs": lines}
    if key == "macos":
        cs = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(BUILDS / f"macos/{APP_NAME}.app")], capture_output=True, text=True)
        result["codesign_verify"] = "OK (ad-hoc)" if cs.returncode == 0 else f"FAILED: {cs.stderr.strip()}"
    return result


def cmd_export(args: argparse.Namespace) -> int:
    keys = list(PLATFORMS) if args.platform == "all" else [args.platform]
    if not templates_dir().joinpath("version.txt").exists():
        env.die("export templates are not installed; run: tools/py/export.py install-templates", 2)
    ctx = commands.Ctx.create(verbose=args.verbose)
    reports = []
    with ctx.lock.exclusive("export"):
        ok_import, res = commands.import_locked(ctx, echo=False)
        if not ok_import:
            for l in res.lines[-20:]:
                print("  import> " + l, file=sys.stderr)
            env.die("import failed before export", 1)
        for key in keys:
            reports.append(export_one(ctx, key, args.debug))
    if not args.no_smoke:
        for r in reports:
            if r["ok"]:
                r.update(smoke(r["platform"]))
    BUILDS.mkdir(parents=True, exist_ok=True)
    (BUILDS / "export_report.json").write_text(json.dumps(reports, indent=1))
    for r in reports:
        extra = f", smoke: {r['smoke']}" if "smoke" in r else ""
        print(f"{r['platform']:8s} {'OK ' if r['ok'] else 'FAIL'} {r['bytes'] / 1e6:8.1f} MB  {r['path']}  ({r['seconds']}s){extra}")
        for name, size in r.get("siblings", {}).items():
            print(f"           + {name} {size / 1e6:.1f} MB")
        for e in r["engine_errors"]:
            print("           ! " + e)
    return 0 if all(r["ok"] and r.get("smoke", "OK") in ("OK", "skipped (different host OS)") for r in reports) else 1


def cmd_smoke(args: argparse.Namespace) -> int:
    keys = list(PLATFORMS) if args.platform == "all" else [args.platform]
    bad = 0
    for k in keys:
        r = smoke(k)
        print(json.dumps(r))
        bad += 0 if r["smoke"] in ("OK",) or r["smoke"].startswith("skipped") else 1
    return 1 if bad else 0


def cmd_report(_args: argparse.Namespace) -> int:
    if not BUILDS.exists():
        print("no builds/ directory yet")
        return 1
    for p in sorted(BUILDS.rglob("*")):
        if p.is_file() and p.parent != BUILDS:
            print(f"{p.stat().st_size / 1e6:9.2f} MB  {p.relative_to(env.ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("install-templates")
    s.add_argument("--tpz", default=str(env.CACHE / "godot_export_templates.tpz"))
    s.add_argument("--force", action="store_true")
    for name in ("export", "smoke"):
        s = sub.add_parser(name)
        s.add_argument("platform", choices=["windows", "linux", "macos", "all"])
        if name == "export":
            s.add_argument("--debug", action="store_true", help="debug template instead of release")
            s.add_argument("--no-smoke", action="store_true")
            s.add_argument("-v", "--verbose", action="store_true")
    sub.add_parser("report")
    args = ap.parse_args()
    if args.cmd == "install-templates":
        return install_templates(Path(args.tpz), args.force)
    return {"export": cmd_export, "smoke": cmd_smoke, "report": cmd_report}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
