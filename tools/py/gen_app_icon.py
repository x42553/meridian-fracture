#!/usr/bin/env python3
"""Render the Meridian Fracture app icon (shield + star emblem, no text) deterministically with Pillow.

    tools/py/gen_app_icon.py [--check]

The geometry is the `Emblem` class of game/src/app/app_splash.gd (hexagonal shield, inner outline, ten-point star) in the
default skin accent (#7fb0e6, game/src/ui/ui_skin.gd) on the UI deep background (#06080b / #0b1016).
Outputs (all under game/assets/icons/):
  app_icon.png            1024 master, full-bleed dark square (the Godot project icon, window icon at runtime)
  set/app_icon_<n>.png    16 32 48 64 128 256 512 (Linux 256 is the .desktop/.deb icon; 'set/' has a .gdignore: not imported)
  app_icon.icns           macOS (rounded tile on a transparent margin, 16..1024 incl. @2x), Pillow writer
  app_icon.ico            Windows, 16 24 32 48 64 128 256
--check regenerates into memory and fails when a committed file differs (Pillow encoder drift is tolerated for the container files:
only the master pixels are compared). Needs `pip install pillow`.
"""
from __future__ import annotations

import argparse
import io
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
    sys.exit("gen_app_icon.py needs Pillow: pip install pillow")

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "icons"
SET = OUT / "set"
SET_SIZES = (16, 32, 48, 64, 128, 256, 512)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)
ICNS_SIZES = (16, 32, 64, 128, 256, 512, 1024)
ACCENT = (0x7F, 0xB0, 0xE6)
BG_TOP = (0x0B, 0x10, 0x16)
BG_DEEP = (0x06, 0x08, 0x0B)
SS = 4  # supersampling factor
MASTER = 1024


def _blend(base: tuple, col: tuple, a: float) -> tuple:
    return tuple(round(b * (1 - a) + c * a) for b, c in zip(base, col))


def shield_points(cx: float, cy: float, s: float) -> list:
    """Same six points as Emblem._draw (y down)."""
    return [(cx - s, cy - s * 0.72), (cx, cy - s), (cx + s, cy - s * 0.72), (cx + s, cy + s * 0.32), (cx, cy + s), (cx - s, cy + s * 0.32)]


def star_points(cx: float, cy: float, s: float) -> list:
    pts = []
    for i in range(10):
        r = s * (0.46 if i % 2 == 0 else 0.19)
        a = -math.pi * 0.5 + i * math.pi / 5.0
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r + s * 0.02))
    return pts


def render_master(size: int = MASTER) -> Image.Image:
    n = size * SS
    img = Image.new("RGB", (n, n), BG_DEEP)
    # vertical gradient + soft accent glow behind the shield
    px = ImageDraw.Draw(img)
    for y in range(n):
        t = y / (n - 1)
        px.line([(0, y), (n, y)], fill=_blend(BG_TOP, BG_DEEP, t * 0.9))
    glow = Image.new("L", (n, n), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([n * 0.18, n * 0.18, n * 0.82, n * 0.82], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(n * 0.09))
    img.paste(Image.new("RGB", (n, n), ACCENT), (0, 0), glow.point(lambda v: v * 0.55))
    d = ImageDraw.Draw(img, "RGBA")
    cx, cy, s = n / 2, n / 2 + n * 0.012, n * 0.37
    sh = shield_points(cx, cy, s)
    d.polygon(sh, fill=ACCENT + (46,))
    lw = max(2, round(n * 0.017))
    d.line(sh + [sh[0], sh[1]], fill=ACCENT + (255,), width=lw, joint="curve")
    for p in sh:
        d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill=ACCENT + (255,))
    inner = [(cx + (x - cx) * 0.82, cy + (y - cy) * 0.82) for x, y in sh]
    d.line(inner + [inner[0], inner[1]], fill=ACCENT + (110,), width=max(1, round(lw * 0.5)), joint="curve")
    d.polygon(star_points(cx, cy, s), fill=ACCENT + (255,))
    return img.resize((size, size), Image.LANCZOS)


def macos_tile(master: Image.Image, size: int = MASTER) -> Image.Image:
    """Apple icon grid: an 824/1024 rounded tile (radius ~22.5%) centred on a transparent canvas."""
    n = size * SS
    tile = master.resize((round(n * 824 / 1024),) * 2, Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile.size[0] - 1, tile.size[1] - 1], radius=round(tile.size[0] * 0.225), fill=255)
    out = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    off = (n - tile.size[0]) // 2
    out.paste(tile, (off, off), mask)
    return out.resize((size, size), Image.LANCZOS)


def outputs() -> dict:
    """path -> bytes (PNG set, icns, ico)."""
    master = render_master()
    res: dict = {}

    def png(im: Image.Image) -> bytes:
        b = io.BytesIO()
        im.save(b, "PNG", optimize=True)
        return b.getvalue()

    res[OUT / "app_icon.png"] = png(master)
    for n in SET_SIZES:
        res[SET / f"app_icon_{n}.png"] = png(master.resize((n, n), Image.LANCZOS))
    tile = macos_tile(master)
    b = io.BytesIO()
    tile.save(b, "ICNS", sizes=[(n, n) for n in ICNS_SIZES])
    res[OUT / "app_icon.icns"] = b.getvalue()
    b = io.BytesIO()
    master.convert("RGBA").save(b, "ICO", sizes=[(n, n) for n in ICO_SIZES])
    res[OUT / "app_icon.ico"] = b.getvalue()
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    outs = outputs()
    if args.check:
        bad = []
        for p, data in outs.items():
            if not p.exists():
                bad.append(f"{p.relative_to(ROOT)} missing")
            elif p.suffix == ".png" and Image.open(p).tobytes() != Image.open(io.BytesIO(data)).tobytes():
                bad.append(f"{p.relative_to(ROOT)} differs")
        for b in bad:
            print("icon drift: " + b, file=sys.stderr)
        return 1 if bad else 0
    SET.mkdir(parents=True, exist_ok=True)
    (SET / ".gdignore").write_text("", encoding="utf-8")
    for p, data in outs.items():
        p.write_bytes(data)
        print(f"{p.relative_to(ROOT)}  {len(data)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
