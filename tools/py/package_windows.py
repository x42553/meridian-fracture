#!/usr/bin/env python3
"""Package the exported Windows build into a .zip (stdlib only; runs on any OS).

    tools/py/package_windows.py [--version 0.1.0]

Inputs : builds/windows/MeridianFracture.exe + MeridianFracture.pck   (tools/py/export.py export windows)
         (a *.console.exe next to them is included when present, e.g. from a debug export)
Output : builds/packages/meridian-fracture-<ver>-windows-x86_64.zip  containing a top folder meridian-fracture-<ver>/
The .pck must stay next to the .exe with the same base name. The archive is verified (zip CRC test + listing).
"""
from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gdlib import env  # noqa: E402
import version  # noqa: E402

README = ("Meridian Fracture\r\n\r\nRun MeridianFracture.exe (keep MeridianFracture.pck next to it).\r\n"
          "The exe carries the engine's default icon (no rcedit on the build host); the game icon is MeridianFracture.ico next to it, and the window\r\n"
          "icon at runtime is the game's. Needs a GPU with Vulkan 1.2 or Direct3D 12 support; LAN play uses UDP port 27615 (allow it in the firewall).\r\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", default=version.read_version())
    args = ap.parse_args()
    src = env.ROOT / "builds" / "windows"
    exe, pck = src / "MeridianFracture.exe", src / "MeridianFracture.pck"
    for p in (exe, pck):
        if not p.exists():
            env.die(f"{p} missing; run: tools/py/export.py export windows", 2)
    out = env.ROOT / "builds" / "packages"
    out.mkdir(parents=True, exist_ok=True)
    dest = out / f"meridian-fracture-{args.version}-windows-x86_64.zip"
    top = f"meridian-fracture-{args.version}"
    members = [exe, pck, *sorted(src.glob("*.console.exe"))]
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for p in members:
            info = zipfile.ZipInfo.from_file(p, f"{top}/{p.name}")
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100755 << 16 if p.suffix == ".exe" else 0o100644 << 16
            zf.writestr(info, p.read_bytes(), compresslevel=9)
        ico = env.ROOT / "game" / "assets" / "icons" / "app_icon.ico"
        if ico.exists():
            zf.writestr(f"{top}/MeridianFracture.ico", ico.read_bytes())
        zf.writestr(f"{top}/README.txt", README)
    with zipfile.ZipFile(dest) as zf:
        bad = zf.testzip()
        if bad:
            env.die(f"corrupt member {bad}", 1)
        names = [i.filename for i in zf.infolist()]
    print(f"{dest.relative_to(env.ROOT)}  {dest.stat().st_size / 1e6:.1f} MB")
    print("members: " + ", ".join(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
