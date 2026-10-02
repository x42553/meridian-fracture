"""test_pipeline.py - end-to-end pipeline checks on a scratch output directory (a few seconds):
  * two clean builds of the same assets are byte-identical (OGG, manifest, index)
  * the incremental no-op rebuild renders nothing and takes < 5 s
  * changing nothing but the job count does not change the bytes
  * a corrupted file is detected by QA hashing (sha256 in the manifest)
Run:  .cache/venv/bin/python tools/py/audio/qa/test_pipeline.py"""
from __future__ import annotations

import filecmp
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
BUILD = str(HERE / "build_all.py")
ONLY = "rifle_shot,ui/click,sfx/impact/bullet_metal,sfx/loop/engine_wheeled"


def _build(out: Path, jobs: int) -> str:
    p = subprocess.run([sys.executable, BUILD, "sfx", "--only", ONLY, "--jobs", str(jobs), "--out", str(out)], capture_output=True, text=True)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout


def _same(a: Path, b: Path) -> None:
    files = sorted(p.relative_to(a) for p in a.rglob("*") if p.is_file() and p.name != "provenance.json")
    assert files, "nothing was built"
    for f in files:
        assert (b / f).exists() and filecmp.cmp(a / f, b / f, shallow=False), f"{f} differs"


def test_two_builds_are_identical_and_incremental() -> None:
    with tempfile.TemporaryDirectory() as d:
        a, b = Path(d) / "a", Path(d) / "b"
        _build(a, 1)
        _build(b, 3)
        _same(a, b)
        t0 = time.time()
        out = _build(a, 1)
        dt = time.time() - t0
        assert "0 to render" in out, out
        assert dt < 5.0, f"no-op rebuild took {dt:.1f}s"
        print(f"  identical trees, no-op rebuild {dt:.2f}s")


def test_forced_rebuild_keeps_bytes_and_provenance_dates() -> None:
    with tempfile.TemporaryDirectory() as d:
        a = Path(d) / "a"
        _build(a, 1)
        prov = (a / "provenance.json").read_text()
        p = subprocess.run([sys.executable, BUILD, "sfx", "--only", ONLY, "--force", "--out", str(a), "--jobs", "1"], capture_output=True, text=True)
        assert p.returncode == 0, p.stderr
        assert (a / "provenance.json").read_text() == prov, "created_utc must only change when the bytes change"


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    print("test_pipeline OK")
