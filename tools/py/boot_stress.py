#!/usr/bin/env python3
"""Boot stress (task HARD1): real-renderer boots of an autostart match, many times, to catch the rare boot-time crash (VQ1: SIGABRT / SIGSEGV right
after APP_READY with `ERROR: /root: The caller thread can't call the function propagate_notification()`: engine Node API reached from a worker
thread during match load).

Each iteration runs `tools/gd run res://src/app/boot.tscn --gui -- --autostart=match --with-ui --ticks=60 --speed=0 --quit-on-end ...` with
random family / map size / player count / map seed (and audio on every 4th run), waits for the process to quit by itself and fails on: exit code
other than 0, a timeout, crash words, `caller thread can't call`, a `SCRIPT ERROR` or any engine ERROR line (shutdown `resources still in use` / RID leak
lines are ERRORs: the run must exit clean; the `ObjectDB instances were leaked` WARNING is counted but tolerated). Prints one line per boot and a summary:
  BOOT_STRESS <n> boots: <ok> ok, <failed> failed (crashes <c>, caller-thread errors <t>, hangs <h>); <k> runs printed an ObjectDB leak warning

  python3 tools/py/boot_stress.py [--iterations 100] [--seed 1] [--batch-label x] [--timeout 90] [--out DIR] [--sizes 96,128,192] [--headless] [--binary PATH]
`--binary PATH` (task QA2): boot the EXPORTED app (the shipped binary + .pck) instead of `tools/gd run`; a timeout is a hang, engine ERROR lines are scanned here.
Exit code 0 = every boot was clean.
"""
from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def user_dir() -> Path:
    """The game's user data dir (`config/custom_user_dir_name`): `thread_guard.log` is written there by AppLogger when the engine reports a thread-guard error."""
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "MeridianFracture"
    if sys.platform.startswith("win"):
        import os
        return Path(os.environ.get("APPDATA", str(Path.home()))) / "MeridianFracture"
    return Path.home() / ".local" / "share" / "MeridianFracture"

GD = ROOT / "tools" / "gd"
SCENE = "res://src/app/boot.tscn"
CRASH_WORDS = ("Program crashed", "handle_crash", "Segmentation fault", "SIGSEGV", "SIGABRT", "SIGBUS", "Abort trap", "Dumping the backtrace")
CALLER = re.compile(r"caller thread can't call")
ERRS = re.compile(r"^(ERROR|SCRIPT ERROR)", re.M)
LEAKS = re.compile(r"^WARNING: (\d+) ObjectDB instances were leaked", re.M)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--iterations", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--timeout", type=int, default=90)
    ap.add_argument("--sizes", default="96,128,192")
    ap.add_argument("--headless", action="store_true", help="dummy renderer (default: the real renderer)")
    ap.add_argument("--audio-every", type=int, default=4)
    ap.add_argument("--out", default="")
    ap.add_argument("--binary", default="", help="the exported app binary to boot instead of the editor run")
    a = ap.parse_args()
    out = Path(a.out).resolve() if a.out else Path(tempfile.mkdtemp(prefix="boot_stress_"))
    out.mkdir(parents=True, exist_ok=True)
    guard_log = user_dir() / "thread_guard.log"
    if guard_log.exists():
        guard_log.unlink()
    rng = random.Random(a.seed)
    sizes = [int(x) for x in a.sizes.split(",")]
    ok = bad = crashes = caller = hangs = leaks = 0
    for i in range(a.iterations):
        fam, size, players, mseed = rng.randint(0, 2), rng.choice(sizes), rng.randint(2, 8), rng.randint(1, 9999)
        audio = a.audio_every > 0 and i % a.audio_every == a.audio_every - 1
        cmd = [a.binary] + (["--headless"] if a.headless else []) if a.binary else [sys.executable, str(GD), "run", SCENE, "--timeout", str(a.timeout)] + ([] if a.headless else ["--gui"])
        cmd += ["--", "--fresh-settings", "--no-banner", "--autostart=match", "--with-ui", "--bots=all", "--ticks=60", "--speed=0", "--quit-on-end",
                f"--family={fam}", f"--map-size={size}", f"--map-seed={mseed}", f"--players={players}"]
        if not audio:
            cmd.append("--no-audio")
        t0 = time.time()
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=a.timeout + 60)
            rc, text = p.returncode, p.stdout + p.stderr
        except subprocess.TimeoutExpired:
            rc, text = 124, ""
        dt = time.time() - t0
        why = ""
        if rc == 124:
            hangs += 1
            why = "HANG"
        elif any(w in text for w in CRASH_WORDS) or rc in (245, 134, 139, 138):
            crashes += 1
            why = "CRASH"
        if CALLER.search(text):
            caller += 1
            why = (why + " " if why else "") + "CALLER-THREAD"
        if not why and rc != 0:
            why = f"rc={rc}"
        if not why and ERRS.search(text):
            why = "ERRORS: " + ERRS.search(text).group(0)
        leak = LEAKS.search(text)
        if leak:
            leaks += 1
        if not why and "APPTEST_END" not in text:
            why = "no APPTEST_END"
        if why:
            bad += 1
            (out / f"fail_{i:03d}.log").write_text(" ".join(cmd) + "\n" + text, encoding="utf-8")
        else:
            ok += 1
        print(f"[{i + 1:3d}/{a.iterations}] fam={fam} size={size:3d} players={players} seed={mseed:4d} {'audio' if audio else '     '} rc={rc:3d} {dt:5.1f}s "
              f"{why or 'ok'}{' (objectdb leak warning)' if leak else ''}", flush=True)
    if guard_log.exists():
        print("thread_guard.log (caller thread id, main thread id, innermost script frame):\n" + guard_log.read_text(encoding="utf-8"))
    print(f"BOOT_STRESS {a.iterations} boots: {ok} ok, {bad} failed (crashes {crashes}, caller-thread errors {caller}, hangs {hangs}); "
          f"{leaks} runs printed an ObjectDB leak warning (not an error); logs in {out}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
