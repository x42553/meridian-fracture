#!/usr/bin/env python3
"""Package the exported macOS app: compressed .dmg + .zip (macOS host only: hdiutil, ditto, codesign).

    tools/py/package_macos.py [--version X.Y.Z] [--background bg.png] [--no-dmg] [--verify-only]

Inputs : builds/macos/MeridianFracture.app   (tools/py/export.py export macos; ad-hoc signed by the exporter)
Outputs: builds/packages/meridian-fracture-<ver>-macos-universal.dmg   volume 'Meridian Fracture': the .app + an 'Applications' symlink
                                                                       (+ optional .background/background.png), UDZO compressed
         builds/packages/meridian-fracture-<ver>-macos-universal.zip   `ditto -c -k --keepParent` of the .app (keeps the signature)
Checks : the app's Info.plist (CFBundleIconFile resolves to a decodable .icns, CFBundleShortVersionString / CFBundleVersion == VERSION,
         bundle id), `codesign --verify --deep --strict`, then the .dmg is verified (`hdiutil verify`), attached read-only, listed
         (app + Applications link, signature still valid inside the image) and detached again.

Gatekeeper (this app is ad-hoc signed, NOT notarized: that needs a paid Apple Developer account, a 'Developer ID Application'
certificate, `codesign --options runtime --timestamp` with entitlements, `xcrun notarytool submit --wait` and `xcrun stapler staple`;
not attempted here). On the first launch of a downloaded copy: right click the app, choose Open, then Open again; or
`xattr -dr com.apple.quarantine /Applications/MeridianFracture.app`. Files copied over a LAN / built locally carry no quarantine flag.
"""
from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gdlib import env  # noqa: E402
import version  # noqa: E402

APP = env.ROOT / "builds" / "macos" / "MeridianFracture.app"
PACKAGES = env.ROOT / "builds" / "packages"
VOLNAME = "Meridian Fracture"
ICNS_MAGIC = b"icns"


def run(cmd: list, check: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    if check and r.returncode != 0:
        env.die(f"{' '.join(str(c) for c in cmd[:3])} failed rc={r.returncode}: {(r.stderr or r.stdout).strip()[-400:]}", 1)
    return r


def verify_app(app: Path, want_version: str) -> list:
    """Returns a list of problems (empty = ok): Info.plist keys, icon, version, signature."""
    bad = []
    plist_path = app / "Contents" / "Info.plist"
    if not plist_path.exists():
        return [f"{plist_path} missing"]
    info = plistlib.loads(plist_path.read_bytes())
    icon = info.get("CFBundleIconFile", "")
    if not icon:
        bad.append("Info.plist: CFBundleIconFile missing")
    else:
        res = app / "Contents" / "Resources"
        cand = res / icon if (res / icon).exists() else res / (icon + ".icns")
        if not cand.exists():
            bad.append(f"icon file {icon} not in Resources")
        else:
            data = cand.read_bytes()
            if data[:4] != ICNS_MAGIC:
                bad.append(f"{cand.name} is not an icns file")
            elif sys.platform == "darwin":
                with tempfile.TemporaryDirectory() as td:
                    r = run(["iconutil", "-c", "iconset", cand, "-o", Path(td) / "x.iconset"], check=False)
                    if r.returncode != 0 or not list((Path(td) / "x.iconset").glob("*.png")):
                        bad.append(f"{cand.name} does not decode (iconutil): {r.stderr.strip()[:200]}")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if info.get(key) != want_version:
            bad.append(f"Info.plist {key} = {info.get(key)!r}, want {want_version!r}")
    if not info.get("CFBundleIdentifier"):
        bad.append("Info.plist: CFBundleIdentifier missing")
    if sys.platform == "darwin":
        r = run(["codesign", "--verify", "--deep", "--strict", app], check=False)
        if r.returncode != 0:
            bad.append("codesign --verify failed: " + r.stderr.strip()[:200])
    return bad


def make_zip(app: Path, dest: Path) -> None:
    dest.unlink(missing_ok=True)
    run(["ditto", "-c", "-k", "--keepParent", app, dest])


def make_dmg(app: Path, dest: Path, background: Path | None) -> None:
    dest.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="meridian_dmg_") as td:
        stage = Path(td) / VOLNAME
        stage.mkdir()
        run(["ditto", app, stage / app.name])  # keeps xattrs / the signature
        (stage / "Applications").symlink_to("/Applications")
        if background is not None:
            (stage / ".background").mkdir()
            shutil.copy2(background, stage / ".background" / "background.png")
        icns = env.ROOT / "game" / "assets" / "icons" / "app_icon.icns"
        if icns.exists():  # volume icon (shown once the custom-icon flag is set; SetFile ships with the Xcode command line tools)
            shutil.copy2(icns, stage / ".VolumeIcon.icns")
            run(["SetFile", "-a", "C", stage], check=False)
        run(["hdiutil", "create", "-volname", VOLNAME, "-srcfolder", stage, "-fs", "HFS+", "-format", "UDZO", "-imagekey", "zlib-level=9", "-ov", dest])


def verify_dmg(dmg: Path, want_version: str) -> list:
    """hdiutil verify + attach (read-only, no Finder window) + content check + detach."""
    bad = []
    r = run(["hdiutil", "verify", dmg], check=False)
    if r.returncode != 0:
        return ["hdiutil verify failed: " + (r.stderr or r.stdout).strip()[-200:]]
    with tempfile.TemporaryDirectory(prefix="meridian_mnt_") as td:
        mnt = Path(td) / "mnt"
        mnt.mkdir()
        r = run(["hdiutil", "attach", dmg, "-readonly", "-nobrowse", "-noverify", "-mountpoint", mnt], check=False)
        if r.returncode != 0:
            return ["hdiutil attach failed: " + (r.stderr or r.stdout).strip()[-200:]]
        try:
            app = mnt / "MeridianFracture.app"
            if not app.is_dir():
                bad.append("MeridianFracture.app missing in the image")
            else:
                bad += ["in image: " + m for m in verify_app(app, want_version)]
            link = mnt / "Applications"
            if not link.is_symlink() or str(link.readlink()) != "/Applications":
                bad.append("Applications symlink missing")
        finally:
            for _ in range(5):
                if run(["hdiutil", "detach", mnt], check=False).returncode == 0:
                    break
                run(["hdiutil", "detach", "-force", mnt], check=False)
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", default=version.read_version())
    ap.add_argument("--background", type=Path, help="optional PNG shown behind the icons (stored in .background/)")
    ap.add_argument("--no-dmg", action="store_true")
    ap.add_argument("--verify-only", action="store_true", help="only verify the existing .app and packages")
    ap.add_argument("--app", type=Path, default=APP)
    args = ap.parse_args()
    if sys.platform != "darwin":
        env.die("package_macos.py needs a macOS host (hdiutil, ditto, codesign); on CI it runs on the macos runner", 2)
    if not args.app.is_dir():
        env.die(f"{args.app} missing; run: tools/py/export.py export macos", 2)
    bad = verify_app(args.app, args.version)
    for b in bad:
        print("app check: " + b, file=sys.stderr)
    if bad:
        return 1
    print(f"app ok: icon + version {args.version} + ad-hoc signature")
    stem = f"meridian-fracture-{args.version}-macos-universal"
    PACKAGES.mkdir(parents=True, exist_ok=True)
    zip_p, dmg_p = PACKAGES / f"{stem}.zip", PACKAGES / f"{stem}.dmg"
    if not args.verify_only:
        make_zip(args.app, zip_p)
        if not args.no_dmg:
            make_dmg(args.app, dmg_p, args.background)
    for p in (zip_p, dmg_p):
        if p.exists():
            print(f"{p.relative_to(env.ROOT)}  {p.stat().st_size / 1e6:.1f} MB")
    if zip_p.exists():
        r = run(["unzip", "-tq", zip_p], check=False)
        if r.returncode != 0:
            print("zip test failed", file=sys.stderr)
            return 1
    if dmg_p.exists():
        bad = verify_dmg(dmg_p, args.version)
        for b in bad:
            print("dmg check: " + b, file=sys.stderr)
        if bad:
            return 1
        print("dmg verified: hdiutil verify, attached read-only, app + Applications link, signature valid, detached")
    return 0


if __name__ == "__main__":
    sys.exit(main())
