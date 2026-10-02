#!/usr/bin/env python3
"""bootstrap.py - find or create the Python environment of the audio toolchain (build time only).

  python3 tools/py/audio/bootstrap.py            verify / create the venv, print the exact command to run build_all.py
  python3 tools/py/audio/bootstrap.py --voice    additionally require kokoro-onnx + onnxruntime (voice pipeline)
  python3 tools/py/audio/bootstrap.py --check    verify only (exit 1 when no usable venv exists; never creates anything)
  python3 tools/py/audio/bootstrap.py --python   print only the interpreter path (for scripts)

Rules (audio spec 7.8): the repo-local `.cache/venv` is reused when it satisfies the pins of requirements.txt
(numpy, soundfile with libvorbis, Pillow); otherwise `.cache/venv_audio` is created and populated.  A venv is never
deleted.  The system python3 numpy was broken on the dev machine (namespace stub without `__version__`), so this
script never trusts the interpreter that runs it: every candidate is probed in a subprocess and must report a real
`numpy.__version__`.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
CACHE = ROOT / ".cache"
CANDIDATES = ("venv", "venv_audio")
MIN_PY = (3, 10)
VOICE_PINS = {"kokoro_onnx": "kokoro-onnx", "onnxruntime": "onnxruntime"}

_PROBE = r"""
import json, sys
out = {"python": sys.version.split()[0], "ok": False, "problems": []}
try:
    import numpy
    out["numpy"] = numpy.__version__
except Exception as e:                                   # namespace stub, missing, ABI mismatch
    out["problems"].append("numpy: %s" % e)
try:
    import soundfile as sf
    out["soundfile"] = sf.__version__
    out["libsndfile"] = sf.__libsndfile_version__
    if "VORBIS" not in sf.available_subtypes("OGG"):
        out["problems"].append("libsndfile has no Vorbis encoder")
except Exception as e:
    out["problems"].append("soundfile: %s" % e)
try:
    import PIL
    out["Pillow"] = PIL.__version__
except Exception as e:
    out["problems"].append("Pillow: %s" % e)
for mod in @VOICE@:
    try:
        m = __import__(mod)
        out[mod] = getattr(m, "__version__", "?")
    except Exception as e:
        out["problems"].append("%s: %s" % (mod, e))
out["ok"] = not out["problems"]
print(json.dumps(out))
"""


def venv_python(venv: Path) -> Path:
    return venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def read_pins() -> dict[str, str]:
    pins: dict[str, str] = {}
    for line in (HERE / "requirements.txt").read_text().splitlines():
        line = line.split("#")[0].strip()
        if "==" in line:
            name, ver = line.split("==")
            pins[name.strip()] = ver.strip()
    return pins


def probe(py: Path, voice: bool = False) -> dict:
    """Run the probe script in `py`; returns the report dict (ok False + problems on any failure)."""
    if not py.exists():
        return {"ok": False, "problems": [f"{py} does not exist"]}
    code = _PROBE.replace("@VOICE@", repr(tuple(VOICE_PINS) if voice else ()))
    try:
        p = subprocess.run([str(py), "-c", code], capture_output=True, text=True, timeout=120)
        rep = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception as e:  # noqa: BLE001 - any failure means "not usable"
        return {"ok": False, "problems": [f"probe failed: {e}"]}
    pins = read_pins()
    for pkg, key in (("numpy", "numpy"), ("soundfile", "soundfile"), ("Pillow", "Pillow")):
        have = rep.get(key)
        if have is not None and pkg in pins and have != pins[pkg]:
            rep["ok"] = False
            rep.setdefault("problems", []).append(f"{pkg} {have} != pinned {pins[pkg]}")
    return rep


def find_python(voice: bool = False, create: bool = False, verbose: bool = False) -> Path | None:
    """First candidate venv that satisfies the pins; with create=True builds `.cache/venv_audio` when none does."""
    if sys.version_info < MIN_PY and verbose:
        print(f"note: running interpreter is {sys.version.split()[0]}; the venv interpreter is what matters")
    for name in CANDIDATES:
        py = venv_python(CACHE / name)
        rep = probe(py, voice)
        if verbose:
            state = "ok" if rep["ok"] else "unusable (" + "; ".join(rep.get("problems", [])) + ")"
            print(f"  .cache/{name}: {state}")
        if rep["ok"]:
            return py
    if not create:
        return None
    if sys.version_info < MIN_PY:
        raise SystemExit(f"need Python >= {MIN_PY[0]}.{MIN_PY[1]} to create the venv (have {sys.version.split()[0]})")
    venv = CACHE / "venv_audio"
    print(f"creating {venv} ...")
    subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
    py = venv_python(venv)
    reqs = ["-r", str(HERE / "requirements.txt")]
    if voice:
        vreq = HERE / "requirements-voice.txt"
        reqs += ["-r", str(vreq)] if vreq.exists() else list(VOICE_PINS.values())
    subprocess.run([str(py), "-m", "pip", "install", "--disable-pip-version-check", *reqs], check=True)
    rep = probe(py, voice)
    if not rep["ok"]:
        raise SystemExit("new venv is still not usable: " + "; ".join(rep.get("problems", [])))
    return py


def ensure_toolchain_or_reexec(script: str) -> None:
    """Called first thing by build_all.py: when the running interpreter lacks a working numpy/soundfile, re-exec the
    script under the repo venv (never installs anything; run bootstrap.py once to create the venv)."""
    try:
        import numpy  # noqa: F401
        import soundfile  # noqa: F401
        numpy.__version__  # noqa: B018 - the broken namespace stub has no __version__
        return
    except Exception:  # noqa: BLE001
        pass
    py = find_python()
    if py is None:
        raise SystemExit("no usable audio venv: run  python3 tools/py/audio/bootstrap.py  once")
    os.execv(str(py), [str(py), script, *sys.argv[1:]])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--voice", action="store_true", help="also require kokoro-onnx + onnxruntime")
    ap.add_argument("--check", action="store_true", help="verify only, never create")
    ap.add_argument("--python", action="store_true", help="print only the interpreter path")
    a = ap.parse_args()
    verbose = not a.python
    if verbose:
        print("audio toolchain venv:")
    py = find_python(a.voice, create=not a.check, verbose=verbose)
    if py is None:
        print("no usable venv (run without --check to create .cache/venv_audio)", file=sys.stderr)
        return 1
    if a.python:
        print(py)
        return 0
    rep = probe(py, a.voice)
    keys = ("python", "numpy", "soundfile", "libsndfile", "Pillow", *VOICE_PINS)
    print("using", py.relative_to(ROOT) if py.is_relative_to(ROOT) else py, "-", ", ".join(f"{k} {rep[k]}" for k in keys if k in rep))
    rel = py.relative_to(ROOT) if py.is_relative_to(ROOT) else py
    print(f"\nregenerate:  {rel} tools/py/audio/build_all.py sfx --jobs 4\ncheck:       {rel} tools/py/audio/build_all.py check [--verify] [--sheets]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
