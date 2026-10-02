#!/usr/bin/env python3
"""perf_run.py - scripted GUI performance matches with a REAL renderer through the app path (boot.tscn --autostart=match --with-ui).

  python3 tools/py/perf_run.py --players 8 --size 192 --quality high --game-min 5 [--renderer forward_plus|mobile|gl_compatibility]
  python3 tools/py/perf_run.py --matrix                  4p/8p x High/Low, 5 game minutes each (writes docs/perf/qa1_perf.json)

Each run: bots play every slot, speed 200 %, vsync off, 1920x1080 window, silent audio (dummy driver), `--perf-log` (AppPerfProbe):
avg / p50 / p95 / p99 / worst frame ms, hitches > 33 ms, draw calls, entities, objects, static + video memory, sim step ms.
Needs a display (a window is opened); the exported or the editor binary can be used (--binary).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "tools/godot/Godot.app/Contents/MacOS/Godot"
TICK_MS = 50


def run_one(a, players: int, quality: str, renderer: str, game_min: float, out_dir: Path, label: str, fog: int = 1) -> dict:
    stress = max(0, (a.entities - 60) // players) if a.entities > 0 else 0
    ticks = int(game_min * 60 * 1000 / TICK_MS)
    log = out_dir / f"{label}.jsonl"
    cmd = [str(a.binary), "--path", str(ROOT / "game"), "--resolution", a.resolution, "--audio-driver", "Dummy"]
    if renderer:
        cmd += ["--rendering-method", renderer]
    cmd += ["--", "--autostart=match", "--with-ui", "--bots=all", f"--players={players}", "--humans=1", f"--map-size={a.size}",
            f"--map-seed={a.seed}", "--speed=%d" % a.speed, f"--ticks={ticks}", f"--fog={fog}", f"--quality={quality}", "--vsync=0",
            f"--window={a.resolution}", "--fresh-settings", "--quit-on-end", f"--perf-log={log}", f"--perf-label={label}",
            "--timeout-s=%d" % a.timeout] + ([f"--focus={a.focus}", f"--focus-zoom={a.zoom}"] if a.focus != "none" else []) + ([f"--stress-units={stress}"] if stress else []) + a.extra
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout + 120)
    out = p.stdout + p.stderr
    (out_dir / f"{label}.log").write_text(out)
    m = re.findall(r"^APPPERF (\{.*\})$", out, re.M)
    errs = [l for l in out.splitlines() if re.search(r"ERROR|SCRIPT ERROR", l)]
    res = json.loads(m[-1]) if m else {"label": label, "failed": True}
    res.update({"players": players, "quality": quality, "renderer": renderer or "default", "rc": p.returncode, "wall_s": round(time.time() - t0, 1),
                "engine_errors": len(errs)})
    ad = re.findall(r"adapter[^\n]*|Metal[^\n]*", out)[:1]
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--players", type=int, default=8)
    ap.add_argument("--size", type=int, default=192)
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--quality", default="high")
    ap.add_argument("--renderer", default="")
    ap.add_argument("--game-min", type=float, default=5.0)
    ap.add_argument("--speed", type=int, default=200)
    ap.add_argument("--resolution", default="1920x1080")
    ap.add_argument("--binary", default=str(GODOT))
    ap.add_argument("--timeout", type=int, default=1200)
    ap.add_argument("--matrix", action="store_true")
    ap.add_argument("--out", default=str(ROOT / "docs/perf"))
    ap.add_argument("--label", default="")
    ap.add_argument("--focus", default="crowd", help="camera: crowd (the densest spot, the worst case), fight, or none (the opening camera)")
    ap.add_argument("--zoom", type=float, default=0.5)
    ap.add_argument("--entities", type=int, default=480, help="drop extra units into the match so it reaches about this many entities (0 = natural AI growth only)")
    a, extra = ap.parse_known_args()
    a.extra = extra  # any other --flag goes to the game
    out_dir = Path(a.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    runs = []
    if a.matrix:
        for players in (4, 8):
            for q in ("high", "low"):
                runs.append((players, q, a.renderer))
    else:
        runs.append((a.players, a.quality, a.renderer))
    results = []
    for players, q, r in runs:
        label = a.label or f"{players}p_{q}_{r or 'default'}_{a.size}"
        res = run_one(a, players, q, r, a.game_min, out_dir, label)
        results.append(res)
        print(json.dumps(res))
        sys.stdout.flush()
    if a.matrix:
        (out_dir / "qa1_perf.json").write_text(json.dumps(results, indent=1))
    return 0 if all(not r.get("failed") for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
