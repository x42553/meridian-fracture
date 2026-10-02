#!/usr/bin/env python3
"""Quit-stress (task HARD1): the app must exit by itself, with exit code 0, wherever and however it is asked to quit.

Every iteration starts the real app (`tools/gd run res://src/app/boot.tscn`, real renderer unless --headless) in one phase through the
`--screen=` / `--autostart=` flags plus the `AppQuitHook` flags `--quit-at-phase=<phase> --quit-after-ms=<random> --quit-mode=<how>` and
asserts: it exits within the timeout, exit code 0 (tools/gd forces 3 when engine ERROR lines were printed, e.g. `resources still in use
at exit`), no crash words and no `caller thread can't call` in the log.

Phases: splash, main_menu, skirmish_lobby, lan_browser (the first-run firewall dialog and with --no_help), lan_lobby (hosting on a random
port), options, credits, field_manual, replays, loading_map / loading_world / loading_view / loading_view_models, in_match, end_screen,
replay_playback. Quit modes: tree (orderly begin, then SceneTree.quit), raw (a bare SceneTree.quit(), the original hang; leak lines tolerated), close (the window close request = close button / Cmd+Q), state (AppState.quit_game =
the menu's Quit). Delays are random inside a per-phase window.

  python3 tools/py/quit_stress.py [--iterations 60] [--seed 1] [--headless | --both] [--phases a,b] [--audio-every 4] [--jobs 1]
                                  [--timeout 60] [--allow-exit-noise] [--out DIR] [--map-size 128] [--binary PATH]
`--binary PATH` (task QA2) runs the EXPORTED app instead of `tools/gd run` (e.g. "builds/macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture"): the same
phases / quit modes through the shipped binary and its .pck, the engine ERROR lines are scanned here (as tools/gd does: they become exit code 3).
Phases that need the test-only SimBot / replay fixture are adapted: `replay_playback` plays a replay recorded on the fly (--replay-src) when --binary is used.
Exit code 0 = every iteration passed; 1 = at least one failed (the log of each failure is kept under --out).
"""
from __future__ import annotations

import argparse
import json
import random
import re
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GD = ROOT / "tools" / "gd"
SCENE = "res://src/app/boot.tscn"
REPLAY = "res://tests/fixtures/net/replays/xplat_2p_ai.mfreplay"
REPLAY_FILE = ""  # --binary: an on-the-fly recording (the tests/ fixture is not in the .pck)
CRASH_WORDS = ("Program crashed", "handle_crash", "Segmentation fault", "SIGSEGV", "SIGABRT", "SIGBUS", "Abort trap", "Dumping the backtrace")
BAD_LINES = re.compile(r"caller thread can't call|SCRIPT ERROR|Stack overflow|Invalid call|Invalid access|Parse Error")
EXIT_NOISE = re.compile(r"still in use at exit|leaked at exit|ObjectDB instances|RID allocations|RIDs? of type|at: (cleanup|clear|finalize|_free_rids) \(|^\s*$")


def match_args(size: int, players: int = 4) -> list[str]:
    return ["--autostart=match", "--with-ui", "--bots=all", "--speed=0", "--family=0", f"--map-size={size}", "--map-seed=21", f"--players={players}"]


def scenarios(size: int) -> dict[str, dict]:
    m = match_args(size)
    return {
        "splash": {"phase": "splash", "delay": (0, 700), "args": []},
        "main_menu": {"phase": "main_menu", "delay": (0, 2500), "args": []},
        "skirmish_lobby": {"phase": "skirmish_lobby", "delay": (0, 2500), "args": ["--screen=lobby"]},
        "lan_browser": {"phase": "lan_browser", "delay": (0, 2500), "args": ["--screen=lan_browser"]},
        "lan_browser_nohelp": {"phase": "lan_browser", "delay": (0, 2500), "args": ["--screen=lan_browser", "--no_help=1"]},
        "lan_lobby": {"phase": "lan_lobby", "delay": (0, 2500), "args": ["--screen=lobby", "--lan-host={port}"]},
        "options": {"phase": "options", "delay": (0, 2000), "args": ["--screen=options"]},
        "credits": {"phase": "credits", "delay": (0, 1500), "args": ["--screen=credits"]},
        "field_manual": {"phase": "field_manual", "delay": (0, 3000), "args": ["--screen=field_manual"]},
        "replays": {"phase": "replays", "delay": (0, 2000), "args": ["--screen=replays"]},
        "loading_map": {"phase": "loading_map", "delay": (0, 150), "args": m},
        "loading_world": {"phase": "loading_world", "delay": (0, 50), "args": m},
        "loading_view": {"phase": "loading_view", "delay": (0, 2500), "args": m},
        "loading_view_models": {"phase": "loading_view_models", "delay": (0, 1500), "args": m},
        "in_match": {"phase": "in_match", "delay": (0, 6000), "args": m},
        # paced (--speed=100, real time): an unpaced run can end the match (the human surrenders at tick 100 of 131) before the game screen has bound the session, so
        # `match_ended` is missed and the end screen never comes (a test-only race; QA2 measured 3 of 4 runs stuck on the real renderer)
        "end_screen": {"phase": "end_screen", "delay": (0, 2500), "args": [x for x in m if x != "--speed=0"] + ["--speed=100", "--surrender-at=100"]},
        "replay_playback": {"phase": "replay_playback", "delay": (0, 4000), "args": [f"--autostart=replay={REPLAY_FILE or REPLAY}", "--with-ui", "--speed=100"]},
    }


# the dummy renderer has no view stage (headless runs build no view), and a headless autostart match / replay ends the process by itself the moment it is over
HEADLESS_SKIP = {"loading_view", "loading_view_models", "end_screen", "replay_playback"}


ENGINE_ERR = re.compile(r"^(SCRIPT ERROR:|ERROR:|USER ERROR:|Parse Error:)", re.M)
BINARY = ""  # --binary: the exported app


def run_one(i: int, name: str, sc: dict, mode: str, delay: int, headless: bool, audio: bool, timeout: int, out: Path, allow_noise: bool, rng_port: int) -> dict:
    args = [a.replace("{port}", str(rng_port)) for a in sc["args"]]
    if BINARY:
        cmd = [BINARY] + (["--headless"] if headless else []) + ["--"]
    else:
        cmd = [str(GD), "run", SCENE, "--timeout", str(timeout)]
        if not headless:
            cmd.append("--gui")
        cmd += ["--"]
    cmd += ["--fresh-settings", "--no-banner", f"--quit-at-phase={sc['phase']}", f"--quit-after-ms={delay}", f"--quit-mode={mode}"]
    if not audio:
        cmd.append("--no-audio")
    cmd += args
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=timeout + 60)
        rc, text = p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired as e:
        rc, text = 124, (e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else str(e.stdout or "")
    dt = time.time() - t0
    if BINARY and rc == 0 and ENGINE_ERR.search(text):
        rc = 3  # tools/gd does the same: engine ERROR lines turn an exit code 0 into 3
    verdict = "ok"
    why = ""
    fired = "QUITHOOK" in text
    if rc == 124:
        verdict, why = "HANG", "timeout"
    elif any(w in text for w in CRASH_WORDS) or rc in (245, 134, 139, 138):
        verdict, why = "CRASH", f"rc={rc}"
    elif BAD_LINES.search(text):
        verdict, why = "ERRORS", BAD_LINES.search(text).group(0)
    elif not fired:
        verdict, why = "NOHOOK", f"rc={rc}, the quit hook never fired (phase {sc['phase']} not reached)"
    elif rc == 3:
        allow_noise = allow_noise or mode == "raw"  # a bare SceneTree.quit() leaves coroutines suspended: leak lines are expected, a hang or crash is not
        extra = [ln for ln in text.splitlines() if (ln.startswith("ERROR") or ln.startswith("WARNING")) and not EXIT_NOISE.search(ln)]
        if extra or not allow_noise:
            verdict, why = ("ERRORS", extra[0][:160]) if extra else ("NOISE", "exit code 3: shutdown leak lines")
        else:
            verdict = "noise"
    elif rc != 0:
        verdict, why = "EXIT", f"rc={rc}"
    rec = {"i": i, "scenario": name, "phase": sc["phase"], "mode": mode, "delay_ms": delay, "headless": headless, "audio": audio, "rc": rc, "secs": round(dt, 1),
           "verdict": verdict, "why": why}
    if verdict not in ("ok", "noise"):
        (out / f"fail_{i:03d}_{name}_{mode}_{delay}.log").write_text(" ".join(cmd) + "\n" + text, encoding="utf-8")
    return rec


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--iterations", type=int, default=60)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--headless", action="store_true", help="dummy renderer only (default: the real renderer)")
    ap.add_argument("--both", action="store_true", help="alternate real renderer and headless")
    ap.add_argument("--phases", default="", help="comma separated scenario names (default: all, round robin in random order)")
    ap.add_argument("--audio-every", type=int, default=4, help="every Nth iteration runs with the audio system on (0 = never)")
    ap.add_argument("--modes", default="tree,close,state,raw")
    ap.add_argument("--map-size", type=int, default=128)
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--allow-exit-noise", action="store_true", help="exit code 3 with only shutdown leak lines counts as pass (reported as noise)")
    ap.add_argument("--out", default="")
    ap.add_argument("--binary", default="", help="the exported app binary to stress instead of the editor run (task QA2)")
    a = ap.parse_args()
    global BINARY
    BINARY = a.binary

    out = Path(a.out).resolve() if a.out else Path(tempfile.mkdtemp(prefix="quit_stress_"))
    out.mkdir(parents=True, exist_ok=True)
    if BINARY:
        global REPLAY_FILE
        rdir = out / "replay_src"
        rdir.mkdir(exist_ok=True)
        subprocess.run([BINARY, "--headless", "--", "--autostart=match", "--players=2", "--humans=1", "--ticks=3000", "--speed=0", "--map-size=96", "--map-seed=3",
                        "--record-replays", f"--replay-dir={rdir}", "--fresh-settings", "--no-audio", "--no-banner"], capture_output=True, timeout=300)
        REPLAY_FILE = str(rdir / "autosave_1.mfreplay")
        if not Path(REPLAY_FILE).exists():
            print("could not record the replay source with the exported binary", file=sys.stderr)
            return 3
    table = scenarios(a.map_size)
    names = [n for n in a.phases.split(",") if n] if a.phases else list(table)
    for n in names:
        if n not in table:
            print(f"unknown scenario {n}; known: {', '.join(table)}", file=sys.stderr)
            return 3
    rng = random.Random(a.seed)
    modes = a.modes.split(",")
    plan = []
    order: list[str] = []
    for i in range(a.iterations):
        headless = a.headless or (a.both and i % 2 == 1)
        if not order:
            order = names[:]
            rng.shuffle(order)
        name = order.pop()
        if headless and name in HEADLESS_SKIP:
            name = "in_match" if name in ("end_screen", "replay_playback") else "loading_world"
        sc = table[name]
        lo, hi = sc["delay"]
        plan.append((i, name, sc, rng.choice(modes), rng.randint(lo, hi), headless, a.audio_every > 0 and i % a.audio_every == a.audio_every - 1, rng.randint(47100, 47900)))

    results: list[dict] = []
    lock = threading.Lock()

    def job(item: tuple) -> None:
        i, name, sc, mode, delay, headless, audio, port = item
        rec = run_one(i, name, sc, mode, delay, headless, audio, a.timeout, out, a.allow_exit_noise, port)
        with lock:
            results.append(rec)
            print(f"[{len(results):3d}/{a.iterations}] {name:20s} {mode:5s} +{delay:5d}ms {'headless' if headless else 'gpu     '} {'audio' if audio else '     '} "
                  f"rc={rec['rc']:3d} {rec['secs']:5.1f}s {rec['verdict']}{(' ' + rec['why']) if rec['why'] else ''}", flush=True)

    with ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        list(ex.map(job, plan))

    bad = [r for r in results if r["verdict"] not in ("ok", "noise")]
    noise = [r for r in results if r["verdict"] == "noise"]
    (out / "results.jsonl").write_text("\n".join(json.dumps(r) for r in sorted(results, key=lambda r: r["i"])) + "\n", encoding="utf-8")
    by: dict[str, list[int]] = {}
    for r in results:
        by.setdefault(r["scenario"], [0, 0])
        by[r["scenario"]][0] += 1
        by[r["scenario"]][1] += r["verdict"] not in ("ok", "noise")
    print("per scenario (runs/failed): " + ", ".join(f"{k} {v[0]}/{v[1]}" for k, v in sorted(by.items())))
    print(f"QUIT_STRESS {len(results)} runs: {len(results) - len(bad)} passed ({len(noise)} with shutdown noise), {len(bad)} failed; logs and results.jsonl in {out}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
