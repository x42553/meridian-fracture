#!/usr/bin/env python3
"""gdscript_race_probe.py - reproduces the Godot 4.7.2 GDScript first-execution race that crashed ~2 % of exported-build match boots (task QA2).

  python3 tools/py/gdscript_race_probe.py [--runs 6] [--iters 1500] [--threads 8] [--warm]

The VM caches the evaluator of an untyped operator (here the `match typeof(v)` patterns) in the function's bytecode on its FIRST execution and
publishes it without synchronisation (type pair, then function pointer). Threads that start the same fresh function together can read the half
published cache and call a null / torn pointer: SIGSEGV (signal 11) in a WorkerThread. Each iteration compiles a fresh script, so every iteration
is a first execution. Without --warm the engine is expected to crash in most runs (that is the engine bug, exit code 0 = reproduced); with --warm
one call runs alone on the main thread first (the game's mitigation: ViewModelBuilder.WARM_MAX, ViewTerrainBake._tasks) and every run must finish.
Exit codes: default mode 0 = bug reproduced, 1 = it did not reproduce (fixed engine?); --warm mode 0 = no crash, 1 = crash.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gdlib import env  # noqa: E402

SCRIPT = '''extends SceneTree

const SRC := """
extends RefCounted
func f(v):
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return 1
		TYPE_STRING:
			return 2
		_:
			return 3
"""
var obj: Object
var sink: int = 0


func work(_i: int) -> void:
	sink += obj.call("f", 5) as int


func _init() -> void:
	var iters: int = int(OS.get_environment("PROBE_ITERS"))
	var threads: int = int(OS.get_environment("PROBE_THREADS"))
	var warm: bool = OS.get_environment("PROBE_WARM") == "1"
	for k in iters:
		var s := GDScript.new()
		s.source_code = SRC
		s.reload()
		obj = s.new()
		if warm:
			obj.call("f", 5)
		var gid: int = WorkerThreadPool.add_group_task(work, threads * 4, threads, true)
		WorkerThreadPool.wait_for_group_task_completion(gid)
		obj = null
	print("PROBE_DONE ", iters)
	quit()
'''


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=6)
    ap.add_argument("--iters", type=int, default=1500)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--warm", action="store_true", help="run the function once on the main thread before the burst (the mitigation)")
    a = ap.parse_args()
    godot = str(env.godot_bin())
    crashed = 0
    with tempfile.TemporaryDirectory(prefix="race_probe_") as d:
        Path(d, "project.godot").write_text('config_version=5\n[application]\nconfig/name="race_probe"\n')
        Path(d, "probe.gd").write_text(SCRIPT)
        e = dict(os.environ, PROBE_ITERS=str(a.iters), PROBE_THREADS=str(a.threads), PROBE_WARM="1" if a.warm else "0")
        for i in range(a.runs):
            p = subprocess.run([godot, "--headless", "--path", d, "--script", "probe.gd"], capture_output=True, text=True, env=e, timeout=600)
            out = p.stdout + p.stderr
            ok = "PROBE_DONE" in out and p.returncode == 0 and "handle_crash" not in out
            crashed += not ok
            print(f"  run {i + 1}/{a.runs}: {'finished' if ok else 'CRASHED (rc=%d%s)' % (p.returncode, ', signal 11' if 'signal 11' in out else '')}")
    print(f"RACE_PROBE {'warm' if a.warm else 'cold'}: {crashed}/{a.runs} runs crashed")
    if a.warm:
        return 1 if crashed else 0
    return 0 if crashed else 1


if __name__ == "__main__":
    sys.exit(main())
