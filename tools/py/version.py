#!/usr/bin/env python3
"""Single source of truth for the release version: the VERSION file (semantic, MAJOR.MINOR.PATCH[-pre]).

    tools/py/version.py show
    tools/py/version.py check [--packages]     exit 1 on drift (CI step 'version consistency')
    tools/py/version.py bump patch|minor|major|X.Y.Z   rewrite every stamped file from the new version

Stamped files: game/project.godot (application/config/version, read at runtime by src/app/app_info.gd -> splash / main-menu footer /
smoke line / crash report), game/export_presets.cfg (macOS short_version + version, Windows file_version + product_version as
MAJOR.MINOR.PATCH.0), README.md (version badge line + package file names), CHANGELOG.md (a `## [X.Y.Z]` heading must exist).
--packages additionally checks every artifact in builds/packages (names, the .deb control Version, the macOS app Info.plist inside
the .zip / .dmg is checked by package_macos.py). Pure stdlib.
"""
from __future__ import annotations

import argparse
import re
import sys
import tarfile
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$")
PROJECT = ROOT / "game" / "project.godot"
PRESETS = ROOT / "game" / "export_presets.cfg"
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"
BADGE = "![version](https://img.shields.io/badge/version-{v}-blue)"
BADGE_RE = re.compile(r"!\[version\]\(https://img\.shields\.io/badge/version-([^-)]+(?:--[^-)]+)*)-blue\)")


def read_version() -> str:
    v = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not SEMVER.match(v):
        raise SystemExit(f"VERSION '{v}' is not semantic (MAJOR.MINOR.PATCH[-pre])")
    return v


def win_version(v: str) -> str:
    """Windows resources want four numeric fields: 0.1.0 -> 0.1.0.0 (a pre-release tag is dropped)."""
    return ".".join(SEMVER.match(v).groups()[:3]) + ".0"


def badge_value(v: str) -> str:
    return v.replace("-", "--")


# (file, regex with one capture group for the value, expected value) -------------------------------------------------------
def stamps(v: str) -> list:
    w = win_version(v)
    return [
        (PROJECT, r'^config/version="([^"]*)"', v, "project.godot application/config/version"),
        (PRESETS, r'^application/short_version="([^"]*)"', v, "export_presets macOS short_version"),
        (PRESETS, r'^application/version="([^"]*)"', v, "export_presets macOS version"),
        (PRESETS, r'^application/file_version="([^"]*)"', w, "export_presets Windows file_version"),
        (PRESETS, r'^application/product_version="([^"]*)"', w, "export_presets Windows product_version"),
    ]


def check(packages: bool = False) -> list:
    """Returns a list of drift messages (empty = consistent)."""
    v = read_version()
    bad = []
    for path, rx, want, label in stamps(v):
        m = re.search(rx, path.read_text(encoding="utf-8"), re.M)
        if not m:
            bad.append(f"{label}: key not found")
        elif m.group(1) != want:
            bad.append(f"{label}: '{m.group(1)}' != '{want}'")
    rd = README.read_text(encoding="utf-8")
    m = BADGE_RE.search(rd)
    if not m:
        bad.append("README.md: version badge line missing")
    elif m.group(1) != badge_value(v):
        bad.append(f"README.md badge: '{m.group(1)}' != '{badge_value(v)}'")
    for name in re.findall(r"meridian-fracture[-_](\d+\.\d+\.\d+[0-9A-Za-z.-]*?)[-_](?:windows|linux|amd64|macos)", rd):
        if name != v:
            bad.append(f"README.md package file name carries {name}, not {v}")
    if not re.search(r"^## \[" + re.escape(v) + r"\]", CHANGELOG.read_text(encoding="utf-8"), re.M):
        bad.append(f"CHANGELOG.md: no '## [{v}]' section")
    if packages:
        bad += check_packages(v)
    return bad


def deb_version(deb: Path) -> str:
    """Version field of a .deb's control file (ar -> control.tar.gz -> control)."""
    data = deb.read_bytes()
    pos = 8
    while pos < len(data):
        name = data[pos:pos + 16].decode().strip()
        size = int(data[pos + 48:pos + 58])
        body = data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size % 2)
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(body), mode="r:*") as tf:
                member = next(m for m in tf.getmembers() if m.name.lstrip("./") == "control")
                txt = tf.extractfile(member).read().decode()
            return re.search(r"^Version: (.+)$", txt, re.M).group(1).strip()
    raise ValueError(f"{deb}: no control member")


def check_packages(v: str) -> list:
    bad = []
    pk = ROOT / "builds" / "packages"
    if not pk.is_dir():
        return [f"{pk}: missing (build the packages first)"]
    for p in sorted(pk.iterdir()):
        if p.suffix == ".deb":
            try:
                dv = deb_version(p)
            except Exception as e:  # noqa: BLE001
                bad.append(f"{p.name}: {e}")
                continue
            if dv != v:
                bad.append(f"{p.name}: control Version {dv} != {v}")
        if p.name.startswith("meridian-fracture") and p.suffix in (".zip", ".gz", ".dmg", ".deb") and v not in p.name:
            bad.append(f"{p.name}: file name does not carry version {v}")
    return bad


def _sub(path: Path, rx: str, new: str) -> None:
    def rep(m: re.Match) -> str:
        off = m.start(0)
        return m.group(0)[:m.start(1) - off] + new + m.group(0)[m.end(1) - off:]

    out, n = re.subn(rx, rep, path.read_text(encoding="utf-8"), flags=re.M)
    if n == 0:
        raise SystemExit(f"{path}: pattern {rx} not found")
    path.write_text(out, encoding="utf-8")


def bump(spec: str) -> str:
    cur = read_version()
    major, minor, patch = (int(x) for x in SEMVER.match(cur).groups()[:3])
    if spec == "major":
        new = f"{major + 1}.0.0"
    elif spec == "minor":
        new = f"{major}.{minor + 1}.0"
    elif spec == "patch":
        new = f"{major}.{minor}.{patch + 1}"
    elif SEMVER.match(spec):
        new = spec
    else:
        raise SystemExit(f"bad bump '{spec}' (major|minor|patch|X.Y.Z)")
    (ROOT / "VERSION").write_text(new + "\n", encoding="utf-8")
    for path, rx, want, _label in stamps(new):
        _sub(path, rx, want)
    rd = README.read_text(encoding="utf-8")
    rd = BADGE_RE.sub(BADGE.format(v=badge_value(new)), rd)
    rd = re.sub(r"(meridian-fracture[-_])" + re.escape(cur) + r"(?=[-_](?:windows|linux|amd64|macos))", lambda m: m.group(1) + new, rd)
    README.write_text(rd, encoding="utf-8")
    cl = CHANGELOG.read_text(encoding="utf-8")
    if f"## [{new}]" not in cl:
        print(f"NOTE: add a '## [{new}]' section to CHANGELOG.md before release (check fails until then)")
    return new


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("show")
    c = sub.add_parser("check")
    c.add_argument("--packages", action="store_true", help="also check builds/packages/*")
    b = sub.add_parser("bump")
    b.add_argument("what")
    args = ap.parse_args(argv)
    if args.cmd == "show":
        print(read_version())
        return 0
    if args.cmd == "bump":
        print("bumped to " + bump(args.what))
        return 0
    bad = check(args.packages)
    for m in bad:
        print("version drift: " + m, file=sys.stderr)
    if not bad:
        print(f"version {read_version()} consistent")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
