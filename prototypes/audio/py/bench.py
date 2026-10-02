"""bench.py - measure real-time playback cost of N simultaneous players in Godot (Dummy audio driver: same mixer, no sound out).

CPU time is taken from getrusage(RUSAGE_CHILDREN) deltas (all threads incl. the audio mixer thread), so the number is
"CPU seconds per wall second" = fraction of one core.  The n=0 run is the engine baseline (60 fps cap, empty scene).
"""
from __future__ import annotations

import json
import re
import resource
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT.parents[1] / "tools" / "godot" / "Godot.app" / "Contents" / "MacOS" / "Godot"

SCENARIOS = [
    dict(n=0, fmt="ogg_mono"),
    dict(n=16, fmt="ogg_mono"), dict(n=64, fmt="ogg_mono"), dict(n=128, fmt="ogg_mono"), dict(n=256, fmt="ogg_mono"),
    dict(n=64, fmt="ogg_stereo"), dict(n=64, fmt="pcm_mono"), dict(n=64, fmt="qoa_mono"),
    dict(n=64, fmt="ogg_mono", filter=0), dict(n=64, fmt="ogg_mono", mode="2d"), dict(n=64, fmt="ogg_mono", move=0),
]


def cpu() -> float:
    r = resource.getrusage(resource.RUSAGE_CHILDREN)
    return r.ru_utime + r.ru_stime


def run(sc: dict, secs: int = 8) -> dict:
    args = [str(GODOT), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "res://tests/t_bench.gd", "--", f"secs={secs}"]
    args += [f"{k}={v}" for k, v in sc.items()]
    c0 = cpu()
    p = subprocess.run(args, capture_output=True, text=True, timeout=120)
    used = cpu() - c0
    m = re.search(r"RESULT (\{.*\})", p.stdout)
    if not m:
        return {"error": (p.stdout + p.stderr)[-400:], **sc}
    r = json.loads(m.group(1))
    r["cpu_s_total"] = round(used, 2)
    return r


if __name__ == "__main__":
    results = []
    for sc in SCENARIOS:
        r = run(sc)
        results.append(r)
        print(json.dumps(r), flush=True)
    base = next((r for r in results if r.get("n") == 0 and "cpu_s_total" in r), None)
    if base:
        # startup/import overhead is identical for every run, so subtracting the n=0 run leaves audio + script cost
        print(f"\n{'scenario':44s} {'cpu_s':>7s} {'extra_cpu_s':>11s} {'core_%_extra':>12s} {'per_voice_%':>11s} {'fps':>6s} {'frame_max_ms':>12s} {'pos_upd_us':>10s}")
        for r in results:
            if "cpu_s_total" not in r:
                print("FAILED", r)
                continue
            extra = r["cpu_s_total"] - base["cpu_s_total"]
            pct = 100.0 * extra / r["secs"]
            per = pct / r["n"] if r["n"] else 0.0
            tag = f"n={r['n']:3d} {r['fmt']:10s} {r['mode']} filter={r['filter']}"
            print(f"{tag:44s} {r['cpu_s_total']:7.2f} {extra:11.2f} {pct:12.1f} {per:11.3f} {r['fps']:6.1f} {r['frame_max_ms']:12.2f} {r['pos_update_us_per_frame']:10.1f}")
    (ROOT / "analysis").mkdir(exist_ok=True)
    (ROOT / "analysis" / "bench.json").write_text(json.dumps(results, indent=1))
