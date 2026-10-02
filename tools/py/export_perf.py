#!/usr/bin/env python3
"""export_perf.py - startup / memory / frame-time measurements on the EXPORTED app (task QA2). macOS or Linux host with a display (windows are opened).

  python3 tools/py/export_perf.py --binary "builds/macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture" startup [--runs 5]
  python3 tools/py/export_perf.py --binary ... perf [--players 4] [--size 192] [--game-min 30] [--speed 200] [--label x]

startup: `--quit-at-phase=<main_menu|in_match> --quit-mode=raw` (AppQuitHook prints `at_ms` = engine clock when the phase was reached) and the wall
time of the whole process (fork -> exit); main menu, then a 4-player match at 96x96 and 192x192 (the in_match phase = the first frame of the game screen,
after the loading screen). The first run of each is the "cold" one (no file cache warm-up between phases is attempted: macOS cannot drop caches without root).
perf: one scripted GUI match (bots / AI in every slot, 1920x1080, vsync off, dummy audio) with `--perf-log` (AppPerfProbe: frame ms avg / p50 / p95 / p99,
hitches, draw calls, entities, static memory) and the process RSS sampled from `ps` every 5 s while it runs (menu RSS = a separate idle sample).
Prints one JSON object; `--out F` also writes it.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


def rss_mb(pid: int) -> float:
    r = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    try:
        return int(r.stdout.strip()) / 1024.0
    except ValueError:
        return -1.0


def startup_once(binary: str, phase: str, size: int, timeout: int = 120) -> dict:
    args = ["--fresh-settings", "--no-banner", "--no-audio", f"--quit-at-phase={phase}", "--quit-after-ms=0", "--quit-mode=raw"]
    if phase == "in_match":
        args += ["--autostart=match", "--with-ui", "--bots=all", "--speed=100", "--players=4", "--humans=1", f"--map-size={size}", "--map-seed=21"]
    t0 = time.time()
    p = subprocess.run([binary, "--", *args], capture_output=True, text=True, timeout=timeout)
    wall = time.time() - t0
    m = re.search(r"QUITHOOK phase=(\w+) .*at_ms=(\d+)", p.stdout + p.stderr)
    return {"phase": phase, "size": size, "wall_s": round(wall, 2), "engine_ms": int(m.group(2)) if m else None, "rc": p.returncode}


def startup(a) -> dict:
    out: dict = {}
    for name, phase, size in (("main_menu", "main_menu", 0), ("match_96", "in_match", 96), ("match_192", "in_match", 192)):
        runs = [startup_once(a.binary, phase, size) for _ in range(a.runs)]
        engine = [r["engine_ms"] for r in runs if r["engine_ms"] is not None]
        wall = [r["wall_s"] for r in runs]
        out[name] = {"first_engine_ms": runs[0]["engine_ms"], "first_wall_s": runs[0]["wall_s"],
                     "median_engine_ms": int(statistics.median(engine)) if engine else None, "min_engine_ms": min(engine) if engine else None,
                     "max_engine_ms": max(engine) if engine else None, "median_wall_s": round(statistics.median(wall), 2), "runs": runs}
        print(f"{name:10s} first {runs[0]['engine_ms']} ms (wall {runs[0]['wall_s']} s); median {out[name]['median_engine_ms']} ms, min {out[name]['min_engine_ms']}, "
              f"max {out[name]['max_engine_ms']} (n={len(runs)})", flush=True)
    return out


def idle_menu_rss(binary: str, secs: int = 12) -> float:
    p = subprocess.Popen([binary, "--", "--fresh-settings", "--no-banner", "--no-audio"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(secs)
        return round(rss_mb(p.pid), 1)
    finally:
        p.terminate()
        try:
            p.wait(15)
        except subprocess.TimeoutExpired:
            p.kill()


def perf(a) -> dict:
    d = Path(tempfile.mkdtemp(prefix="export_perf_"))
    log = d / "perf.jsonl"
    ticks = int(a.game_min * 60 * 1000 / 50)
    label = a.label or f"{a.players}p_{a.size}_{a.game_min}min"
    cmd = [a.binary, "--resolution", a.resolution, "--audio-driver", "Dummy", "--", "--autostart=match", "--with-ui", "--bots=all", f"--players={a.players}",
           "--humans=1", f"--map-size={a.size}", f"--map-seed={a.seed}", f"--speed={a.speed}", f"--ticks={ticks}", "--fog=1", "--quality=high", "--vsync=0",
           f"--window={a.resolution}", "--fresh-settings", "--quit-on-end", f"--perf-log={log}", f"--perf-label={label}", f"--timeout-s={a.timeout}"] + a.extra
    t0 = time.time()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    samples: list[tuple[float, float]] = []
    stop = threading.Event()

    def sampler() -> None:
        while not stop.is_set():
            r = rss_mb(p.pid)
            if r > 0:
                samples.append((round(time.time() - t0, 1), round(r, 1)))
            stop.wait(5)

    th = threading.Thread(target=sampler, daemon=True)
    th.start()
    try:
        text, _ = p.communicate(timeout=a.timeout + 120)
    except subprocess.TimeoutExpired:
        p.kill()
        text = ""
    stop.set()
    th.join(2)
    res = {}
    m = re.findall(r"^APPPERF (\{.*\})$", text, re.M)
    if m:
        res = json.loads(m[-1])
    errs = [ln for ln in text.splitlines() if re.match(r"(ERROR|SCRIPT ERROR)", ln)]
    rs = [r for _, r in samples]
    out = {"label": label, "players": a.players, "size": a.size, "game_min": a.game_min, "speed_pct": a.speed, "rc": p.returncode, "wall_s": round(time.time() - t0, 1),
           "engine_errors": len(errs), "error_lines": errs[:5], "perf": res, "rss_mb": {"samples": len(rs), "first": rs[0] if rs else None, "min": min(rs) if rs else None,
                                                              "max": max(rs) if rs else None, "last": rs[-1] if rs else None,
                                                              "at_25pct": rs[len(rs) // 4] if rs else None, "at_50pct": rs[len(rs) // 2] if rs else None},
           "rss_series": samples[:: max(1, len(samples) // 40)]}
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--binary", required=True)
    ap.add_argument("mode", choices=["startup", "perf", "menu_rss"])
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--players", type=int, default=4)
    ap.add_argument("--size", type=int, default=192)
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--game-min", type=float, default=30.0)
    ap.add_argument("--speed", type=int, default=200)
    ap.add_argument("--resolution", default="1920x1080")
    ap.add_argument("--timeout", type=int, default=3000)
    ap.add_argument("--label", default="")
    ap.add_argument("--out", default="")
    a, extra = ap.parse_known_args()
    a.extra = extra
    res = {"startup": startup, "perf": perf, "menu_rss": lambda x: {"menu_rss_mb": idle_menu_rss(x.binary)}}[a.mode](a)
    print(json.dumps(res))
    if a.out:
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        Path(a.out).write_text(json.dumps(res, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
