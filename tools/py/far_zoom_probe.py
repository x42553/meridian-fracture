#!/usr/bin/env python3
"""VQ2A: far-camera stress matrix (regression for the unexplained SIGABRT of VQ1 on a cam-zoom=1.0 shot).

Runs real-renderer screenshots through tools/gd at the far end of the camera range and fails on any abnormal exit (SIGABRT = -6 / 134,
SIGSEGV, timeout) or crash text in the log:
  lab    tests/visual/terrain_lab.tscn --zoom=1.0 on map families 0..2 x sizes 192 / 256 x yaws, per renderer
  exit   quit WHILE THE MATCH IS STILL LOADING (--frames 60 on a 128+ map): found by this probe, the process does not exit (tools/gd exit 124,
         main thread stuck in NSApplication terminate -> Main::cleanup after every script-level _exit_tree finished); open issue
  match  live bot matches (boot.tscn --autostart=match --cam-zoom=1.0 [--cam-pitch --cam-yaw]) on families x sizes, per renderer
  python3 tools/py/far_zoom_probe.py [--mode lab|match|both|exit] [--renderers forward_plus,mobile,gl_compatibility] [--families 0,1,2]
                                     [--sizes 192,256] [--players 4] [--pitches 0,-30] [--out /tmp/far] [--quick]
Exit code 0 = every run ended normally (tools/gd exit 0 or 3 = engine ERROR lines only), 1 = a run crashed.
"""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CRASH_WORDS = ("Abort trap", "SIGABRT", "Segmentation fault", "CRASH HANDLER", "Program crashed", "Dumping the backtrace")


def run(cmd, log):
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    log.write_text(p.stdout + p.stderr)
    text = p.stdout + p.stderr
    crashed = p.returncode not in (0, 3) or any(w in text for w in CRASH_WORDS)
    return p.returncode, crashed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="both", choices=["lab", "match", "both", "exit"])
    ap.add_argument("--renderers", default="forward_plus,mobile,gl_compatibility")
    ap.add_argument("--families", default="0,1,2")
    ap.add_argument("--sizes", default="192,256")
    ap.add_argument("--players", type=int, default=4)
    ap.add_argument("--pitches", default="0")
    ap.add_argument("--yaws", default="0,137")
    ap.add_argument("--out", default="/tmp/far_zoom_probe")
    ap.add_argument("--quick", action="store_true", help="one family, one size, Forward+ only")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    renderers = ["forward_plus"] if a.quick else a.renderers.split(",")
    families = ["0"] if a.quick else a.families.split(",")
    sizes = ["192"] if a.quick else a.sizes.split(",")
    failures = 0
    runs = 0
    if a.mode == "exit":
        for size in sizes:
            png = out / f"exit_{size}.png"
            cmd = [str(ROOT / "tools/gd"), "shot", "res://src/app/boot.tscn", str(png), "--size", "1280x720", "--frames", "60", "--allow-errors", "--timeout", "60",
                   "--", "--autostart=match", "--with-ui", "--bots=all", "--fresh-settings", "--no-audio", "--speed=0", "--no-banner", "--family=0",
                   f"--map-size={size}", "--map-seed=21", f"--players={a.players}"]
            rc, crashed = run(cmd, png.with_suffix(".log"))
            runs += 1
            failures += crashed
            print(f"exit  size={size} exit={rc} {'HANG/CRASH' if crashed else 'ok'}", flush=True)
        print(f"{runs} runs, {failures} hung or crashed")
        return 1 if failures else 0
    for rm in renderers:
        for fam in families:
            for size in sizes:
                if a.mode in ("lab", "both"):
                    for yaw in a.yaws.split(","):
                        png = out / f"lab_{rm}_{fam}_{size}_{yaw}.png"
                        cmd = [str(ROOT / "tools/gd"), "shot", "res://tests/visual/terrain_lab.tscn", str(png), "--size", "1920x1080", "--frames", "40",
                               "--allow-errors", "--rendering-method", rm, "--timeout", "180", "--", f"--family={fam}", f"--size={size}", "--zoom=1.0", f"--yaw={yaw}"]
                        rc, crashed = run(cmd, png.with_suffix(".log"))
                        runs += 1
                        failures += crashed
                        print(f"lab   {rm:16s} fam={fam} size={size} yaw={yaw:4s} exit={rc} {'CRASH' if crashed else 'ok'}", flush=True)
                if a.mode in ("match", "both"):
                    for pitch in a.pitches.split(","):
                        png = out / f"match_{rm}_{fam}_{size}_{pitch}.png"
                        cmd = [str(ROOT / "tools/gd"), "shot", "res://src/app/boot.tscn", str(png), "--size", "1920x1080", "--frames", "1200", "--allow-errors",
                               "--rendering-method", rm, "--timeout", "400", "--", "--autostart=match", "--with-ui", "--bots=all", "--fresh-settings", "--no-audio",
                               "--speed=0", "--pause-at=1200", "--no-banner", "--cam-zoom=1.0", f"--cam-pitch={pitch}", f"--family={fam}", f"--map-size={size}",
                               f"--players={a.players}"]
                        rc, crashed = run(cmd, png.with_suffix(".log"))
                        runs += 1
                        failures += crashed
                        print(f"match {rm:16s} fam={fam} size={size} pitch={pitch:4s} exit={rc} {'CRASH' if crashed else 'ok'}", flush=True)
    print(f"{runs} runs, {failures} crashed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
