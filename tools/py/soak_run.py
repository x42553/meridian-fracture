#!/usr/bin/env python3
"""soak_run.py - long headless matches through the app path with the real AI in every slot.

  python3 tools/py/soak_run.py [--game-min 30] [--players 8] [--size 192] [--seed 5] [--mode both|plain|fx] [--out DIR] [--linux]

  plain  FX and audio off (`--no-audio`, no view): the sim + AI alone.
  fx     the real view + FX stage + audio facade on the dummy renderer / dummy audio driver (`--with-view`, headless).

Per run: gd run (counts every engine ERROR line; exit 3 on any), `--perf-log` samples every 600 ticks (30 game seconds): static memory,
object count, entities, sim step ms. Verdict: 0 engine errors, memory growth bounded (end-of-run vs the 25% mark, < 25 % and < 150 MB),
sim ms/tick avg + worst. Writes <out>/soak_<mode>.jsonl + soak_report.json and prints a table.
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
TICK_MS = 50


def run_mode(a, mode: str, out: Path) -> dict:
    ticks = int(a.game_min * 60 * 1000 / TICK_MS)
    log = out / f"soak_{mode}.jsonl"
    user = ["--autostart=match", f"--players={a.players}", "--humans=0", f"--map-size={a.size}", f"--map-seed={a.seed}", "--speed=0",
            f"--ticks={ticks}", "--fog=1", "--fresh-settings", "--quit-on-end", f"--perf-log={log}", f"--perf-label=soak_{mode}",
            "--perf-every-ticks=600", "--perf-warmup=20", f"--ai-level={a.ai_level}", f"--timeout-s={a.timeout}"]
    if mode == "plain":
        user += ["--no-audio"]
    else:
        user += ["--with-view"]
    if a.linux:
        out_log = log.with_suffix(".linux.jsonl")  # the container only copies back what it prints; stdout carries the summary
    cmd = [sys.executable, str(ROOT / "tools/gd")]
    if a.linux:
        cmd += ["linux", "--arch", a.arch]
    cmd += ["run", "--timeout", str(a.timeout + 300), "res://src/app/boot.tscn", "--"] + user
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    text = p.stdout + p.stderr
    (out / f"soak_{mode}.log").write_text(text)
    errs = [l for l in text.splitlines() if re.search(r"(^|\s)(ERROR|SCRIPT ERROR)[: ]", l)]
    perf = re.findall(r"^APPPERF (\{.*\})$", text, re.M)
    end = re.findall(r"^APPTEST_END (.*)$", text, re.M)
    summ = re.findall(r"^APPTEST_SUMMARY (.*)$", text, re.M)
    res = {"mode": mode, "rc": p.returncode, "wall_s": round(time.time() - t0, 1), "engine_errors": len(errs), "first_errors": errs[:5],
           "end": end[-1] if end else None, "summary": summ[-1] if summ else None, "game_min": a.game_min, "players": a.players}
    if perf:
        res.update(json.loads(perf[-1]))
    samples = []
    if log.exists():
        for line in log.read_text().splitlines():
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if "mem_mb" in d:  # sample lines only (not the summary, not {"slow": ...} hitch lines)
                samples.append(d)
    if samples:
        mems = [s["mem_mb"] for s in samples]
        q = max(1, len(mems) // 4)
        base = sum(mems[q - 1:q + 1]) / len(mems[q - 1:q + 1])  # the 25 % mark: caches are warm, the opening is over
        res["mem_mb_samples"] = len(mems)
        res["mem_mb_first"] = mems[0]
        res["mem_mb_at25"] = round(base, 1)
        res["mem_mb_last"] = mems[-1]
        res["mem_mb_max"] = max(mems)
        res["mem_growth_since25_mb"] = round(mems[-1] - base, 1)
        res["mem_growth_since25_pct"] = round(100.0 * (mems[-1] - base) / base, 1)
        res["objects_first"] = samples[0]["objs"]
        res["objects_last"] = samples[-1]["objs"]
        res["entities_max"] = max(s["ents"] for s in samples)
        res["step_ms_worst"] = max(s.get("step_max_ms", 0) for s in samples)
        res["bounded"] = res["mem_growth_since25_pct"] < 25.0 and res["mem_growth_since25_mb"] < 150.0
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-min", type=float, default=30.0)
    ap.add_argument("--players", type=int, default=8)
    ap.add_argument("--size", type=int, default=192)
    ap.add_argument("--seed", type=int, default=5)
    ap.add_argument("--ai-level", type=int, default=1)
    ap.add_argument("--mode", default="both", choices=["both", "plain", "fx"])
    ap.add_argument("--timeout", type=int, default=6000, help="seconds per run")
    ap.add_argument("--out", default=str(ROOT / "docs/perf"))
    ap.add_argument("--linux", action="store_true")
    ap.add_argument("--arch", default="amd64")
    a = ap.parse_args()
    out = Path(a.out).resolve()  # the game process needs an absolute --perf-log path
    out.mkdir(parents=True, exist_ok=True)
    modes = ["plain", "fx"] if a.mode == "both" else [a.mode]
    results = []
    ok = True
    for m in modes:
        r = run_mode(a, m, out)
        results.append(r)
        print(json.dumps({k: v for k, v in r.items() if k != "first_errors"}))
        ok &= r["engine_errors"] == 0 and r["rc"] == 0 and r.get("bounded", False) and r.get("end") is not None
        for e in r["first_errors"]:
            print("   ", e[:200])
    (out / "soak_report.json").write_text(json.dumps(results, indent=1))
    print("SOAK", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
