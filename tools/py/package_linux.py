#!/usr/bin/env python3
"""Package the exported Linux build: tar.gz + Debian .deb (built in pure Python, no dpkg needed).

    tools/py/package_linux.py [--version 0.1.0] [--test-deb]

Inputs : builds/linux/MeridianFracture.x86_64 + MeridianFracture.pck   (tools/py/export.py export linux)
Outputs: builds/packages/meridian-fracture-<ver>-linux-x86_64.tar.gz
         builds/packages/meridian-fracture_<ver>_amd64.deb
The .deb installs to /opt/meridian-fracture/, adds /usr/bin/meridian-fracture (symlink), a .desktop entry and a
256px icon. --test-deb installs it inside a Debian 12 container (apt resolves the Depends: line against the real
archive), runs `--headless --smoke` from the installed location, checks the desktop entry and removes it again.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import struct
import subprocess
import sys
import tarfile
import time
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gdlib import env  # noqa: E402
import version  # noqa: E402

BUILDS = env.ROOT / "builds"
BIN = "MeridianFracture.x86_64"
PCK = "MeridianFracture.pck"
PKG = "meridian-fracture"
INSTALL_DIR = "opt/meridian-fracture"
# The engine dlopen()s every library below (only libc6 is a link-time need), so these are what makes a window, GPU and sound appear.
# Verified on Debian 12 (bookworm) and Debian 13 (trixie): `libasound2` is a virtual package on trixie (libasound2t64 provides it).
DEPENDS = ("libc6, libx11-6, libxcursor1, libxinerama1, libxext6, libxrandr2, libxrender1, libxi6, libxkbcommon0, "
           "libudev1, libfontconfig1, libvulkan1 | libgl1, libasound2 | libpulse0")
# Normally pulled in by apt on a desktop: a Vulkan ICD (Mesa), Mesa GL for the gl_compatibility fallback, PulseAudio client,
# Wayland client + decorations, D-Bus (screensaver inhibit / portals).
RECOMMENDS = ("mesa-vulkan-drivers | nvidia-vulkan-icd, libgl1-mesa-dri, libpulse0, libwayland-client0, libwayland-cursor0, "
              "libwayland-egl1, libdecor-0-0, libdbus-1-3")

DESKTOP = """[Desktop Entry]
Type=Application
Name=Meridian Fracture
Comment=Real-time strategy with deterministic LAN multiplayer
Exec=/opt/meridian-fracture/MeridianFracture.x86_64
Icon=meridian-fracture
Terminal=false
Categories=Game;StrategyGame;
StartupWMClass=Meridian Fracture
"""


def make_icon(size: int = 256) -> bytes:
    """The app icon PNG (tools/py/gen_app_icon.py renders game/assets/icons/set/app_icon_<n>.png)."""
    p = env.ROOT / "game" / "assets" / "icons" / "set" / f"app_icon_{size}.png"
    if not p.exists():
        env.die(f"{p} missing; run: python3 tools/py/gen_app_icon.py", 2)
    return p.read_bytes()


def _tarinfo(name: str, size: int = 0, mode: int = 0o644, typ: bytes = tarfile.REGTYPE, link: str = "") -> tarfile.TarInfo:
    ti = tarfile.TarInfo(name)
    ti.size, ti.mode, ti.type, ti.linkname = size, mode, typ, link
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = "root"
    ti.mtime = 1_700_000_000  # reproducible packages
    return ti


def build_tar_gz(dest: Path, version: str, files: dict) -> None:
    top = f"{PKG}-{version}"
    with open(dest, "wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, compresslevel=9) as gz, tarfile.open(fileobj=gz, mode="w") as tf:
        d = _tarinfo(top, typ=tarfile.DIRTYPE, mode=0o755)
        tf.addfile(d)
        for name, (data, mode) in files.items():
            tf.addfile(_tarinfo(f"{top}/{name}", len(data), mode), io.BytesIO(data))


def _tar_gz_bytes(members: list) -> bytes:
    """members: (TarInfo, bytes|None). Returns a .tar.gz blob."""
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0, compresslevel=9) as gz, tarfile.open(fileobj=gz, mode="w", format=tarfile.GNU_FORMAT) as tf:
        for ti, data in members:
            tf.addfile(ti, io.BytesIO(data) if data is not None else None)
    return buf.getvalue()


def _ar(members: list) -> bytes:
    out = bytearray(b"!<arch>\n")
    for name, data in members:
        header = f"{name + '/':<16}{1_700_000_000:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n"
        out += header.encode() + data
        if len(data) % 2:
            out += b"\n"
    return bytes(out)


def build_deb(dest: Path, version: str, payload: dict) -> None:
    data_members = []
    dirs = ["./", "./opt/", f"./{INSTALL_DIR}/", "./usr/", "./usr/bin/", "./usr/share/", "./usr/share/applications/",
            "./usr/share/icons/", "./usr/share/icons/hicolor/", "./usr/share/icons/hicolor/256x256/", "./usr/share/icons/hicolor/256x256/apps/"]
    for d in dirs:
        data_members.append((_tarinfo(d, typ=tarfile.DIRTYPE, mode=0o755), None))
    md5_lines = []
    installed = 0
    for path, (data, mode) in payload.items():
        data_members.append((_tarinfo("./" + path, len(data), mode), data))
        md5_lines.append(f"{hashlib.md5(data).hexdigest()}  {path}")
        installed += len(data)
    data_members.append((_tarinfo("./usr/bin/meridian-fracture", typ=tarfile.SYMTYPE, mode=0o777, link=f"/{INSTALL_DIR}/{BIN}"), None))
    control = (f"Package: {PKG}\nVersion: {version}\nSection: games\nPriority: optional\nArchitecture: amd64\n"
               f"Depends: {DEPENDS}\nRecommends: {RECOMMENDS}\nSuggests: pulseaudio | pipewire-pulse\nInstalled-Size: {installed // 1024 + 1}\nMaintainer: X42553 <noreply@example.invalid>\n"
               "Homepage: https://example.invalid/meridian-fracture\n"
               "Description: Meridian Fracture - real-time strategy game\n"
               " Command & Conquer style RTS with eight factions and deterministic lockstep\n"
               " LAN multiplayer, built with the Godot engine.\n").encode()
    postinst = b"#!/bin/sh\nset -e\nif command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q /usr/share/applications || true; fi\nexit 0\n"
    control_members = [
        (_tarinfo("./control", len(control), 0o644), control),
        (_tarinfo("./md5sums", len("\n".join(md5_lines).encode()) + 1, 0o644), ("\n".join(md5_lines) + "\n").encode()),
        (_tarinfo("./postinst", len(postinst), 0o755), postinst),
    ]
    control_members[1] = (_tarinfo("./md5sums", len(("\n".join(md5_lines) + "\n").encode()), 0o644), ("\n".join(md5_lines) + "\n").encode())
    dest.write_bytes(_ar([
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", _tar_gz_bytes(control_members)),
        ("data.tar.gz", _tar_gz_bytes(data_members)),
    ]))


TEST_IMAGES = ("debian:12-slim", "debian:13-slim")


def test_deb(deb: Path, images=TEST_IMAGES) -> int:
    """Install the .deb into CLEAN Debian containers (12 and 13, amd64) and prove it runs: minimal install (no recommends)
    -> headless smoke from /opt and the /usr/bin symlink + a 600-tick headless match; then the recommended GPU/audio stack
    plus xvfb -> the real window (Vulkan on lavapipe) comes up and quits by itself; then the .deb is removed again."""
    rc_all = 0
    for image in images:
        script = f"""
set -e
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends /pkg/{deb.name} >/dev/null 2>/tmp/apt.err || (cat /tmp/apt.err; exit 1)
dpkg-deb --info /pkg/{deb.name} | grep -E 'Depends|Recommends|Installed-Size'
cat /etc/debian_version
test -x /opt/meridian-fracture/{BIN}
echo '--- smoke run from /opt (headless, minimal install)'
/opt/meridian-fracture/{BIN} --headless --smoke | tee /tmp/smoke.txt
grep -q '^MERIDIAN_BOOT ' /tmp/smoke.txt
echo '--- via /usr/bin symlink'
meridian-fracture --headless --smoke | grep -q '^MERIDIAN_BOOT '
echo '--- headless match from the pck'
meridian-fracture --headless -- --autostart=match --ticks=600 --speed=0 --bots --fresh-settings --no-audio > /tmp/match.txt 2>&1
grep -E 'APPTEST tick=600|APPTEST_END' /tmp/match.txt | tail -2
grep -q 'APPTEST_END reason=ticks' /tmp/match.txt
! grep -E 'ERROR|FATAL' /tmp/match.txt
echo '--- recommended stack + xvfb: the real window'
apt-get install -y -qq xvfb xauth mesa-vulkan-drivers libgl1-mesa-dri libpulse0 >/dev/null 2>&1 || apt-get install -y -qq xvfb xauth mesa-vulkan-drivers libgl1-mesa-dri libpulse0 | tail -3
xvfb-run -a -s '-screen 0 1280x720x24' timeout 120 meridian-fracture --quit-after 200 --verbose -- --fresh-settings --no-audio > /tmp/gui.txt 2>&1 || true
grep -E 'Vulkan|OpenGL|Using|MERIDIAN_BOOT|boot complete|FATAL|ERROR' /tmp/gui.txt | grep -v 'Loading resource' | head -8
grep -q 'boot complete' /tmp/gui.txt
dpkg -r {PKG} >/dev/null
test ! -e /opt/meridian-fracture/{BIN}
echo 'DEB TEST OK ({image}): installed, ran and removed cleanly'
"""
        cmd = ["docker", "run", "--rm", "--name", f"meridian-deb-test-{int(time.time())}", "--platform", "linux/amd64",
               "-v", f"{deb.parent}:/pkg:ro", image, "sh", "-c", script]
        t0 = time.time()
        r = subprocess.run(cmd, text=True, capture_output=True)
        print(f"===== {image}\n" + r.stdout + r.stderr, end="")
        print(f"(container test took {time.time() - t0:.0f}s)")
        rc_all |= r.returncode
    return rc_all


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", default=version.read_version())
    ap.add_argument("--test-deb", action="store_true", help="install the .deb in a Debian 12 container and smoke-run it")
    args = ap.parse_args()
    src_bin, src_pck = BUILDS / "linux" / BIN, BUILDS / "linux" / PCK
    for p in (src_bin, src_pck):
        if not p.exists():
            env.die(f"{p} missing; run: tools/py/export.py export linux", 2)
    icon = make_icon()
    exe, pck = src_bin.read_bytes(), src_pck.read_bytes()
    out = BUILDS / "packages"
    out.mkdir(parents=True, exist_ok=True)
    tgz = out / f"{PKG}-{args.version}-linux-x86_64.tar.gz"
    deb = out / f"{PKG}_{args.version}_amd64.deb"
    tar_files = {BIN: (exe, 0o755), PCK: (pck, 0o644), f"{PKG}.desktop": (DESKTOP.replace("/opt/meridian-fracture/", "").encode(), 0o644),
                 f"{PKG}.png": (icon, 0o644),
                 "README.txt": (b"Meridian Fracture\nRun ./MeridianFracture.x86_64 (keep the .pck next to it).\nNeeds Vulkan or OpenGL 3.3 capable graphics.\n", 0o644)}
    build_tar_gz(tgz, args.version, tar_files)
    payload = {f"{INSTALL_DIR}/{BIN}": (exe, 0o755), f"{INSTALL_DIR}/{PCK}": (pck, 0o644),
               f"usr/share/applications/{PKG}.desktop": (DESKTOP.encode(), 0o644),
               f"usr/share/icons/hicolor/256x256/apps/{PKG}.png": (icon, 0o644)}
    build_deb(deb, args.version, payload)
    for p in (tgz, deb):
        print(f"{p.relative_to(env.ROOT)}  {p.stat().st_size / 1e6:.1f} MB")
    with tarfile.open(tgz) as tf:
        print("tar.gz members: " + ", ".join(m.name for m in tf.getmembers()))
    return test_deb(deb) if args.test_deb else 0


if __name__ == "__main__":
    sys.exit(main())
