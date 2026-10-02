"""build.py - render, encode and register the announcer lines (`voice`) and the unit responses (`responses`).

Announcer line: TTS (Kokoro, text+voice hash cache) -> trim -> 44.1 kHz -> chain (computer | officer | radio, numpy) -> fade ->
LUFS -18 through a look-ahead limiter (true peak <= -1.5 dBTP) -> 16-bit TPDF dither -> mono libvorbis (quality 0.50) -> decode
check.  Unit response: synthesised bleep -> faction radio profile -> LUFS -20 (<= -2.0 dBTP) -> mono OGG.
Incremental: an asset is re-rendered only when its recipe hash (sources + spec + model) changed or its file is missing.
"""
from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import numpy as np

import analyze
import catalog
import dsp
import manifest as mf
import oggtools
from catalog import voice as cv

VOICE_PREFIX = "vox/"
RESP_PREFIX = "resp/"


def owns(kind: str, aid: str) -> bool:
    """Which command manages an asset id: bleeps `resp/<f>/<c>_<t>_<n>`, barks `resp/<f>/voice/...`, lines `vox/...`."""
    if kind == "voice":
        return aid.startswith(VOICE_PREFIX)
    if kind == "barks":
        return aid.startswith(RESP_PREFIX) and "/voice/" in aid
    return aid.startswith(RESP_PREFIX) and "/voice/" not in aid
VOICE_QUALITY = oggtools.QUALITY["voice"]
RESP_QUALITY = 0.80           # bleeps are short synthetic tones over a hiss bed: fewer bits, same perceived result (spec 9.3: ~4.5 KB per clip)
_SRC_VOICE = ("build.py", "chains.py", "lines.py", "cache.py", "tts_kokoro.py", "tts_piper.py")
_SRC_RESP = ("build.py", "chains.py", "responses.py", "lines.py")
KOKORO_LICENCE_TOOLS = ["MIT (kokoro-onnx, onnxruntime)", "GPL-3.0-or-later (phonemizer / espeak-ng, build-time tool only, not shipped)"]
PIPER_VOICE_OF = {"m": "en_US-joe-medium", "f": "en_GB-cori-medium"}


def _src_hash(names: tuple[str, ...], extra: tuple[Path, ...] = ()) -> str:
    h = hashlib.sha256()
    for n in names:
        h.update((Path(__file__).parent / n).read_bytes())
    for p in extra:
        h.update(p.read_bytes())
    return h.hexdigest()


def encode_mono(y: np.ndarray, path: Path, seed: str, tp_ceiling: float, quality: float, snr_min: float | None = None) -> dict:
    """Quantise, encode, decode; re-encode (deterministically) while the decoded true peak exceeds the ceiling or the decoded first /
    last sample breaks the one-shot edge limits (codec pre-echo: the fix is a longer fade on the source)."""
    gain_db, fin, fout = 0.0, 0, 0
    for _ in range(7):
        z = y * dsp.db_to_lin(gain_db)
        if fin or fout:
            g = np.ones(len(z))
            if fin:
                g[:fin] = 0.5 - 0.5 * np.cos(np.pi * np.arange(fin) / fin)
            if fout:
                g[len(z) - fout:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fout) / fout)
            z = z * g
        q = dsp.quantize16(z, seed)
        src = dsp.dequantize16(q)
        nbytes = oggtools.encode_vorbis(src, path, quality)
        dec = oggtools.decode(path)
        tp = analyze.true_peak_db(dec)
        ok = True
        if tp > tp_ceiling:
            gain_db -= (tp - tp_ceiling) + 0.04
            ok = False
        if abs(dec[0]) > 0.016:
            fin, ok = max(fin * 2, 32), False
        if abs(dec[-1]) > 0.0022:
            fout, ok = max(fout * 2, 128), False
        if ok:
            break
    rt = analyze.codec_roundtrip(src, dec)
    if snr_min is not None and rt["snr_db"] < snr_min and quality > cv.QUALITY_MIN:
        return encode_mono(y, path, seed, tp_ceiling, round(quality - 0.1, 2), snr_min)      # noisy radio material: spend more bits
    return {"bytes": nbytes, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "pcm_sha256": dsp.sha_pcm(q), "dec": dec, "src": src,
            "quality": quality, **rt}


def _entry(aid: str, rel: str, res: dict, rhash: str, faction: str | None, extra: dict) -> dict:
    dec = res["dec"]
    e = {"bank": catalog.bank_of(aid), "category": catalog.category_of(aid), "loop": False, "recipe_hash": rhash, "flavour": faction,
         "file": rel, "channels": 1, "duration_samples": int(len(dec)), "bytes": res["bytes"], "sha256": res["sha256"],
         "pcm_sha256": res["pcm_sha256"], "lufs_i": round(analyze.lufs_integrated(dec), 2), "lufs_src": round(analyze.lufs_integrated(res["src"]), 2),
         "true_peak_db": round(analyze.true_peak_db(dec), 2), "seam_score": None, "seam_src": None, "len_delta": res["len_delta"], "snr_db": res["snr_db"]}
    e.update(extra)
    return e


# ------------------------------------------------------------------------------------------------ announcer
def _engine(name: str):
    from voice import tts_kokoro, tts_piper
    return {"kokoro": tts_kokoro, "piper": tts_piper}[name]


def voice_hash(v, engine: str, model_sha: str) -> str:
    fields = {k: getattr(v, k) for k in v.__dataclass_fields__}
    h = hashlib.sha256()
    h.update(_src_hash(_SRC_VOICE).encode())
    h.update(json.dumps({"v": fields, "engine": engine, "model": model_sha}, sort_keys=True).encode())
    h.update(f"|dsp{dsp.DSP_VERSION}|voice{VOICE_QUALITY}".encode())
    return h.hexdigest()


def render_line(v, engine: str, out_root: Path, rhash: str) -> dict[str, dict]:
    from voice import chains
    eng = _engine(engine)
    voice_name = v.voice if engine == "kokoro" else PIPER_VOICE_OF["m" if v.voice[1] == "m" else "f"]
    raw, sr = eng.synth(v.tts_text, voice_name, v.speed)
    x = chains.resample_fft(chains.trim_speech(raw, sr), sr)
    if v.chain == "computer":
        y = chains.computer(x)
    else:
        p = chains.profile(v.style, v.open_ms, v.close_ms, v.hiss_db)
        y = chains.officer(x, p, v.asset_id) if v.chain == "officer" else chains.radio(x, p, v.asset_id)
    y = dsp.fade(y, 0.002, 0.02)
    y = chains.master(y, cv.LINE_LUFS, cv.LINE_TP - 0.03)
    rel = v.asset_id + ".mono.ogg"
    res = encode_mono(y, out_root / rel, v.asset_id, cv.LINE_TP, VOICE_QUALITY, cv.LINE_SNR_MIN + 0.3)
    if engine == "kokoro":
        gen = mf.generator_info()
        prov = {"generator": f"kokoro-onnx {eng.versions()['kokoro_onnx']}", "model": eng.MODEL_NAME, "model_sha256": eng.model_sha256(),
                "voice": v.voice, "text": v.caption, "language": "en-us", "licence_model": "Apache-2.0", "licence_tools": KOKORO_LICENCE_TOOLS,
                "tool_versions": {**{k: gen[k] for k in ("python", "numpy", "soundfile", "libsndfile")}, **eng.versions()}}
    else:
        prov = {"generator": "piper-tts (subprocess, GPL-3.0+ build tool)", "model": voice_name + ".onnx", "model_sha256": None, "voice": voice_name,
                "text": v.caption, "language": "en-us", "licence_model": "CC0-1.0", "licence_tools": ["GPL-3.0-or-later (piper-tts, build-time tool only, not shipped)"]}
    e = _entry(v.asset_id, rel, res, rhash, v.pack if v.pack != "computer" else None,
               {"pack": v.pack, "line": v.line, "take": v.take, "chain": v.chain, "prov": prov, "engine": engine})
    return {v.asset_id: e}


# ------------------------------------------------------------------------------------------------ responses
def resp_hash(s) -> str:
    from voice import lines
    fac = json.loads((lines.DATA / "factions.json").read_text(encoding="utf-8"))["factions"][s.faction]["radio"]
    resp = json.loads((lines.DATA / "responses.json").read_text(encoding="utf-8"))["classes"][s.cls]
    h = hashlib.sha256()
    h.update(_src_hash(_SRC_RESP, (Path(__file__).parent.parent / "music" / "flavours.py",)).encode())
    h.update(json.dumps({"spec": s.__dict__, "radio": fac, "cls": resp}, sort_keys=True).encode())
    h.update(f"|dsp{dsp.DSP_VERSION}|resp{RESP_QUALITY}".encode())
    return h.hexdigest()


def render_response(s, out_root: Path, rhash: str) -> dict[str, dict]:
    from voice import chains, responses
    y = responses.render(s)
    y = dsp.fade(y, 0.003, 0.03)
    y = chains.master(y, cv.RESP_LUFS, cv.RESP_TP - 0.03)
    rel = s.asset_id + ".mono.ogg"
    res = encode_mono(y, out_root / rel, s.asset_id, cv.RESP_TP, RESP_QUALITY)
    return {s.asset_id: _entry(s.asset_id, rel, res, rhash, s.faction, {"cls": s.cls, "type": s.typ})}


def bark_hash(b, engine: str, model_sha: str) -> str:
    return voice_hash(b, engine, model_sha)


def render_bark(b, engine: str, out_root: Path, rhash: str) -> dict[str, dict]:
    """Unit bark: the faction's announcer voice through its full radio profile, -20 LUFS (like the bleeps), mono."""
    from voice import chains
    eng = _engine(engine)
    voice_name = b.voice if engine == "kokoro" else PIPER_VOICE_OF["m" if b.voice[1] == "m" else "f"]
    raw, sr = eng.synth(b.tts_text, voice_name, b.speed)
    x = chains.resample_fft(chains.trim_speech(raw, sr, pad_ms=12.0), sr)
    y = chains.radio(x, chains.profile(b.style, b.open_ms, b.close_ms, b.hiss_db), b.asset_id)
    y = dsp.fade(y, 0.003, 0.03)
    y = chains.master(y, cv.RESP_LUFS, cv.RESP_TP - 0.03)
    rel = b.asset_id + ".mono.ogg"
    res = encode_mono(y, out_root / rel, b.asset_id, cv.RESP_TP, VOICE_QUALITY, cv.BARK_SNR_MIN + 0.3)
    if engine == "kokoro":
        gen = mf.generator_info()
        prov = {"generator": f"kokoro-onnx {eng.versions()['kokoro_onnx']}", "model": eng.MODEL_NAME, "model_sha256": eng.model_sha256(), "voice": b.voice,
                "text": b.caption, "language": "en-us", "licence_model": "Apache-2.0", "licence_tools": KOKORO_LICENCE_TOOLS,
                "tool_versions": {**{k: gen[k] for k in ("python", "numpy", "soundfile", "libsndfile")}, **eng.versions()}}
    else:
        prov = {"generator": "piper-tts (subprocess, GPL-3.0+ build tool)", "model": voice_name + ".onnx", "model_sha256": None, "voice": voice_name,
                "text": b.caption, "language": "en-us", "licence_model": "CC0-1.0", "licence_tools": ["GPL-3.0-or-later (piper-tts, build-time tool only, not shipped)"]}
    return {b.asset_id: _entry(b.asset_id, rel, res, rhash, b.faction, {"cls": b.cls, "type": b.typ, "bark": True, "prov": prov, "engine": engine})}


def worker(job: tuple) -> tuple[str, dict | str]:
    """Process-pool entry: ('vox'|'resp'|'bark', asset_id, out_root, recipe_hash, engine)."""
    kind, aid, out_root, rhash, engine = job
    try:
        if kind == "vox":
            v = next(x for x in _lines_cached() if x.asset_id == aid)
            return aid, render_line(v, engine, Path(out_root), rhash)
        if kind == "bark":
            b = next(x for x in _barks_cached() if x.asset_id == aid)
            return aid, render_bark(b, engine, Path(out_root), rhash)
        s = next(x for x in _resp_cached() if x.asset_id == aid)
        return aid, render_response(s, Path(out_root), rhash)
    except Exception as e:  # noqa: BLE001 - reported by the driver
        import traceback
        return aid, "ERROR " + "".join(traceback.format_exception(e))[-1800:]


_LC: dict = {}


def _lines_cached():
    if "l" not in _LC:
        from voice import lines
        _LC["l"] = lines.all_lines()
    return _LC["l"]


def _barks_cached():
    if "b" not in _LC:
        from voice import lines
        _LC["b"] = lines.all_barks()
    return _LC["b"]


def _resp_cached():
    if "r" not in _LC:
        from voice import responses
        _LC["r"] = responses.all_specs()
    return _LC["r"]


# ------------------------------------------------------------------------------------------------ driver
def _selected(only: list[str], aid: str, extra: tuple[str, ...] = ()) -> bool:
    import fnmatch
    if not only:
        return True
    for p in only:
        for n in (aid,) + extra:
            if any(c in p for c in "*?["):
                if fnmatch.fnmatch(n, p):
                    return True
            elif n == p or n.startswith(p.rstrip("/") + "/") or n.startswith(p):
                return True
    return False


def plan(kind: str, prev_assets: dict, only: list[str], force: bool, root: Path, engine: str = "kokoro"):
    """(jobs, carried, expected ids).  kind = 'voice' | 'responses' | 'barks'."""
    jobs, carried, expected = [], {}, set()
    model_sha = ""
    if kind in ("voice", "barks") and engine == "kokoro":
        from voice import tts_kokoro
        model_sha = tts_kokoro.model_sha256() if tts_kokoro.MODEL.exists() else "missing"
    items = {"voice": _lines_cached, "barks": _barks_cached, "responses": _resp_cached}[kind]()
    for it in items:
        aid = it.asset_id
        expected.add(aid)
        rh = resp_hash(it) if kind == "responses" else voice_hash(it, engine, model_sha)
        old = prev_assets.get(aid)
        intact = (old is not None and old.get("recipe_hash") == rh and (root / old["file"]).exists()
                  and (root / old["file"]).stat().st_size == old["bytes"])
        extra = (getattr(it, "pack", None) or getattr(it, "faction", ""), getattr(it, "line", "") or getattr(it, "cls", ""))
        if kind == "barks":
            extra = extra + ("bark", "barks")
        sel = _selected(only, aid, tuple(x for x in extra if x))
        if intact and not (force and sel):
            carried[aid] = old
        elif sel:
            jobs.append(({"voice": "vox", "barks": "bark", "responses": "resp"}[kind], aid, str(root), rh, engine))
        elif old is not None:
            carried[aid] = old
    return jobs, carried, expected


def run_jobs(jobs: list[tuple], n_jobs: int) -> tuple[dict[str, dict], int]:
    results: dict[str, dict] = {}
    errors = 0
    t0 = time.time()
    done = 0

    def take(aid: str, res) -> None:
        nonlocal errors, done
        done += 1
        if isinstance(res, str):
            errors += 1
            print(f"FAILED {aid}\n{res}", flush=True)
        else:
            results.update(res)
        if done % 50 == 0:
            print(f"  ... {done}/{len(jobs)} ({time.time() - t0:.0f}s)", flush=True)

    if n_jobs <= 1 or len(jobs) <= 2:
        for j in jobs:
            take(*worker(j))
    else:
        import multiprocessing as mp
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=n_jobs, mp_context=mp.get_context("spawn")) as ex:
            for aid, res in ex.map(worker, jobs, chunksize=4):
                take(aid, res)
    return results, errors
