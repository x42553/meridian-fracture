#!/usr/bin/env python3
"""export_qa.py - headless proofs on an EXPORTED binary (task QA2): everything must load from the .pck, nothing from the project folder.

  python3 tools/py/export_qa.py --binary "builds/macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture" --label macos-app [--missions all]
  python3 tools/py/export_qa.py --docker amd64 --label linux-amd64          # builds/linux/MeridianFracture.x86_64 in meridian-linux-runner:amd64
  python3 tools/py/export_qa.py --docker arm64 --label linux-arm64          # the SAME .pck run by the arm64 release template (no arm64 preset is shipped)
  python3 tools/py/export_qa.py --compare a.json b.json c.json              # fingerprints (checksum chains) must be identical across targets

Steps: smoke (version line = VERSION file), match with the bare `--bots` flags, a 4-player all-AI match, missions (the tutorial must WIN: its steps are
time-gated; an operation needs a real player, so with the idle human slot it must END with `lose` after loading its data + objectives from the pck),
record a match then play the recording back (every `APPTEST_CK` line identical, `APPTEST_REPLAY ok=1`). NOTE: the exported build has no tests/ folder, so
the SimBot test class does not exist there (`--bots=all|human` print a warning and the slots use the real AI / stay idle); `--editor-compare` re-runs the
all-AI match and the missions through `tools/gd run` (editor) and requires the identical final checksum line.
Any engine ERROR / SCRIPT ERROR line (shutdown leak noise excluded) or a wrong result fails the step. Writes <out>/<label>.json.
Exit 0 only when every step passed.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINUX_DIR = ROOT / "builds" / "linux"
TEMPLATES = Path.home() / "Library/Application Support/Godot/export_templates/4.7.2.stable"
ERR = re.compile(r"^(ERROR|SCRIPT ERROR|FATAL|USER ERROR)|Program crashed|handle_crash|Segmentation fault|SIGABRT|caller thread can't call", re.M)
NOISE = re.compile(r"still in use at exit|leaked at exit|RID allocations|ObjectDB")
MISSIONS = ["tut_field_training", "op_napc", "op_nec", "op_olm", "op_def", "op_pd", "op_han", "op_ae", "op_sap"]
BASE = ["--fresh-settings", "--no-audio", "--no-banner"]


class Runner:
    def __init__(self, a):
        self.a = a
        self.scratch = Path(tempfile.mkdtemp(prefix="export_qa_", dir=str(ROOT / "docs" / "shots") if a.docker else None))
        self.arm_dir = None
        if a.docker == "arm64":
            self.arm_dir = Path(tempfile.mkdtemp(prefix="export_qa_arm_", dir=str(ROOT / "docs" / "shots")))
            shutil.copy(TEMPLATES / "linux_release.arm64", self.arm_dir / "MeridianFracture.arm64")
            shutil.copy(LINUX_DIR / "MeridianFracture.pck", self.arm_dir / "MeridianFracture.pck")
            (self.arm_dir / "MeridianFracture.arm64").chmod(0o755)

    def path(self, p: Path) -> str:
        """The scratch folder as the process sees it."""
        return str(p) if not self.a.docker else "/scratch/" + p.name

    def run(self, args: list[str], timeout: int) -> tuple[int, str, float]:
        t0 = time.time()
        if self.a.docker:
            exe = "./MeridianFracture.arm64" if self.a.docker == "arm64" else "./MeridianFracture.x86_64"
            src = self.arm_dir if self.a.docker == "arm64" else LINUX_DIR
            cmd = ["docker", "run", "--rm", "--platform", f"linux/{self.a.docker}", "-v", f"{src}:/b:ro", "-v", f"{self.scratch}:/scratch/{self.scratch.name}",
                   "-w", "/b", "meridian-linux-runner:" + self.a.docker, exe, "--headless"] + args
        else:
            cmd = [self.a.binary, "--headless"] + args
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            rc, out = p.returncode, (p.stdout or "") + (p.stderr or "")
        except subprocess.TimeoutExpired as e:
            rc, out = 124, ((e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else str(e.stdout or ""))
        return rc, out, time.time() - t0

    def close(self):
        shutil.rmtree(self.scratch, ignore_errors=True)
        if self.arm_dir:
            shutil.rmtree(self.arm_dir, ignore_errors=True)


def errors(out: str) -> list[str]:
    return [m.group(0) for ln in out.splitlines() if (m := ERR.search(ln)) and not NOISE.search(ln)]


def lines(out: str, prefix: str) -> list[str]:
    return [ln.strip() for ln in out.splitlines() if ln.startswith(prefix)]


def editor_final(args: list[str], prefix: str = "APPTEST_CK") -> str:
    p = subprocess.run([str(ROOT / "tools" / "gd"), "run", "res://src/app/boot.tscn", "--"] + args, capture_output=True, text=True, timeout=1500)
    ls = lines(p.stdout + p.stderr, prefix)
    return ls[-1] if ls else "?"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--binary", default="")
    ap.add_argument("--docker", choices=["amd64", "arm64"], default="")
    ap.add_argument("--label", default="")
    ap.add_argument("--ticks", type=int, default=2400)
    ap.add_argument("--missions", default="tut_field_training,op_napc", help="comma list, or 'all'")
    ap.add_argument("--out", default=str(ROOT / "builds" / "qa"))
    ap.add_argument("--timeout", type=int, default=1500)
    ap.add_argument("--editor-compare", action="store_true", help="local mode: also run the all-AI match + missions in the editor and compare the final checksum lines")
    ap.add_argument("--compare", nargs="+")
    a = ap.parse_args()
    if a.compare:
        fps = [json.loads(Path(p).read_text())["fingerprint"] for p in a.compare]
        keys = sorted(set().union(*fps))
        bad = [k for k in keys if len({json.dumps(f.get(k)) for f in fps}) != 1]
        for k in keys:
            print(f"  [{'DIFF' if k in bad else 'same'}] {k}  {fps[0].get(k)}")
        print("EXPORT_QA_COMPARE", "IDENTICAL" if not bad else f"DIVERGED in {bad}")
        return 1 if bad else 0
    if bool(a.binary) == bool(a.docker):
        print("give exactly one of --binary / --docker", file=sys.stderr)
        return 2
    label = a.label or (a.docker and "linux-" + a.docker) or "local"
    version = (ROOT / "VERSION").read_text().strip()
    missions = MISSIONS if a.missions == "all" else [m for m in a.missions.split(",") if m]
    r = Runner(a)
    steps: list[dict] = []
    fp: dict[str, str] = {}

    def step(name: str, ok: bool, detail: str, secs: float) -> None:
        steps.append({"step": name, "ok": ok, "detail": detail, "secs": round(secs, 1)})
        print(f"  [{'ok' if ok else 'FAIL'}] {name:34s} {detail}  ({secs:.1f}s)", flush=True)

    try:
        rc, out, dt = r.run(["--smoke"], 300)
        m = re.search(r"^MERIDIAN_BOOT .*", out, re.M)
        ok = bool(m) and "selftest=ok" in m.group(0) and f"version={version}" in m.group(0) and rc == 0
        step("smoke", ok, (m.group(0) if m else f"rc={rc} no MERIDIAN_BOOT line")[:150], dt)

        for name, extra in (("match --bots (2p)", ["--bots"]), ("match all-AI (4p 96)", ["--players=4", "--humans=0", "--map-size=96", "--map-seed=7"])):
            rc, out, dt = r.run(["--", "--autostart=match", f"--ticks={a.ticks}", "--speed=0", "--ck-lines"] + extra + BASE, a.timeout)
            fin = re.findall(r"APPTEST tick=%d chain=(\w+) checksum=(\w+)" % a.ticks, out)
            ok = bool(fin) and "APPTEST_END reason=ticks" in out and not errors(out) and rc == 0
            fp[name] = " ".join(f"{c}/{s}" for c, s in fin[-1:]) + " | " + " ".join(x.split("chain=")[1].replace(" checksum=", "/") for x in lines(out, "APPTEST_CK")[-3:])
            ed = ""
            if a.editor_compare and a.binary and "all-AI" in name:
                ed = editor_final(["--autostart=match", f"--ticks={a.ticks}", "--speed=0", "--ck-lines"] + extra + BASE)
                ok = ok and ed == (lines(out, "APPTEST_CK")[-1] if lines(out, "APPTEST_CK") else "?")
                ed = f" editor-equal={ed == (lines(out, 'APPTEST_CK')[-1] if lines(out, 'APPTEST_CK') else '?')}"
            step(name, ok, f"final chain/checksum {fin[-1] if fin else None} rc={rc} errors={errors(out)[:2]}{ed}", dt)

        for mid in missions:
            margs = [f"--autostart=mission={mid}", "--speed=0", "--ck-lines"] + BASE
            rc, out, dt = r.run(["--"] + margs, a.timeout)
            end = lines(out, "APPTEST_MISSION_END")
            res = re.search(r"result=(\w+)", end[0]).group(1) if end else "none"
            tick = re.search(r"tick=(\d+)", end[0]).group(1) if end else "?"
            ck = lines(out, "APPTEST_CK")
            fp["mission " + mid] = f"{res}@{tick} " + (ck[-1].split("chain=")[1] if ck else "")
            want = ("win",) if mid.startswith("tut_") else ("win", "lose")
            ed = ""
            if a.editor_compare and a.binary:
                eq = editor_final(margs, "APPTEST_MISSION_END") == (end[0] if end else "?")
                ed = f" editor-equal={eq}"
            ok = res in want and bool(re.search(r"objectives=\w+:\w+", end[0] if end else "")) and not errors(out) and rc == 0 and (not ed or "True" in ed)
            step(f"mission {mid}", ok, f"result={res} tick={tick} rc={rc} errors={errors(out)[:2]}{ed}", dt)

        rdir = r.scratch / "replays"
        rdir.mkdir(parents=True, exist_ok=True)
        rd = r.path(r.scratch) + "/replays"
        rc, rec, dt = r.run(["--", "--autostart=match", "--players=3", "--humans=1", "--bots=human", "--ticks=4000", "--speed=0", "--map-size=96", "--map-seed=11",
                             "--record-replays", f"--replay-dir={rd}", "--ck-lines"] + BASE, a.timeout)
        rfile = rdir / "autosave_1.mfreplay"
        step("replay: record", rfile.exists() and not errors(rec) and rc == 0, f"{rfile.name} {rfile.stat().st_size if rfile.exists() else 0} B rc={rc}", dt)
        if rfile.exists():
            rc, play, dt = r.run(["--", f"--autostart=replay={rd}/autosave_1.mfreplay", "--ck-lines"] + BASE, a.timeout)
            ck1, ck2 = lines(rec, "APPTEST_CK"), lines(play, "APPTEST_CK")
            res = lines(play, "APPTEST_REPLAY ok=")
            ok = bool(res) and "ok=1" in res[0] and ck1 == ck2 and len(ck1) > 10 and lines(rec, "APPTEST_PLAYER") == lines(play, "APPTEST_PLAYER") and not errors(play) and rc == 0
            fp["replay"] = (ck2[-1].split("chain=")[1] if ck2 else "none")
            step("replay: playback identical", ok, f"{len(ck1)} vs {len(ck2)} checksum lines, {res[0][:90] if res else 'no APPTEST_REPLAY'} rc={rc}", dt)
    finally:
        r.close()
    ok = all(s["ok"] for s in steps)
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{label}.json").write_text(json.dumps({"label": label, "version": version, "steps": steps, "fingerprint": fp, "pass": ok}, indent=1) + "\n")
    print(f"EXPORT_QA {label}: {sum(s['ok'] for s in steps)}/{len(steps)} steps passed")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
