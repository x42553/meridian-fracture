"""render.py - the SFX pipeline for one asset: recipe -> master chain -> 16-bit dither -> libvorbis -> verify.

Master chain per asset (audio spec 7.8): stereo/mono per spec -> DC removal (one-shots) -> bass exciter -> LR4
mono-below-140 Hz (stereo) -> peak/LUFS normalisation (min(lufs_gain, peak ceiling)) -> 16-bit TPDF dither (seeded)
-> libvorbis with a fixed Ogg serial -> decode and re-measure the true peak; when the codec overshoots the ceiling the
level is lowered by the overshoot and the file re-encoded (max 4 passes, deterministic).
"""
from __future__ import annotations

import hashlib
import inspect
import json
from pathlib import Path

import numpy as np

import analyze
import dsp
import oggtools
import catalog
from catalog import AssetSpec

MASTER_CHAIN_VERSION = 1
EDGE_IN = 16          # samples: click guard on the first sample of one-shots
EDGE_OUT = 256        # samples: fade to silence at the end of one-shots
TP_TOLERANCE = 0.09   # dB the decoded true peak may exceed the spec ceiling


def _kit_hash() -> str:
    return hashlib.sha256((Path(__file__).parent / "sfx" / "kit.py").read_bytes()).hexdigest()


def recipe_hash(spec: AssetSpec, fn) -> str:
    """sha256(recipe source + kit helpers + json(spec fields) + DSP_VERSION + MASTER_CHAIN_VERSION)."""
    fields = {k: getattr(spec, k) for k in spec.__dataclass_fields__}
    h = hashlib.sha256()
    h.update(inspect.getsource(fn).encode())
    base = spec.params.get("base")                  # flavour wrappers depend on the recipe they wrap
    if base:
        import sfx
        h.update(inspect.getsource(sfx.RECIPES[base]).encode())
    h.update(_kit_hash().encode())
    h.update(json.dumps(fields, sort_keys=True, default=list).encode())
    h.update(f"|dsp{dsp.DSP_VERSION}|master{MASTER_CHAIN_VERSION}".encode())
    return h.hexdigest()


def seed_name(spec: AssetSpec, variant: int) -> str:
    """RNG seed name; the reference recipe keeps its spike seed via params['seed_name'] (format field {v})."""
    custom = spec.params.get("seed_name")
    return custom.format(v=variant) if custom else f"{spec.id}#{variant}"


def _master(spec: AssetSpec, x: np.ndarray, stereo: bool) -> np.ndarray:
    x = dsp.to_stereo(x) if stereo else dsp.to_mono(x)
    x = x - np.mean(x, axis=0)          # DC removal (for loops the mean of the whole period: seam stays continuous)
    if not spec.loop:
        # click guards only where the recipe left an edge (a fade-in would eat the energy of a 0.2 ms crack)
        g = np.ones(len(x))
        edge_in = float(np.max(np.abs(x[0]))) / max(float(np.max(np.abs(x))), 1e-9)
        edge_out = float(np.max(np.abs(x[-1]))) / max(float(np.max(np.abs(x))), 1e-9)
        if edge_in > 0.004:
            g[:EDGE_IN] = 0.5 - 0.5 * np.cos(np.pi * np.arange(EDGE_IN) / EDGE_IN)
        if edge_out > 0.0008:
            g[len(x) - EDGE_OUT:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(EDGE_OUT) / EDGE_OUT)
        x = x * (g[:, None] if stereo else g)
    if spec.exciter:
        x = dsp.bass_exciter(x, spec.exciter, circ=spec.loop)
    if x.ndim == 2:
        x = dsp.bass_mono(x, 140.0, circ=spec.loop)
    return x


def _level(spec: AssetSpec, x: np.ndarray, peak_db: float) -> np.ndarray:
    x = dsp.normalize(x, 0.0)
    if spec.lufs is not None:                      # loudness target, never above the peak ceiling
        return x * dsp.db_to_lin(min(spec.lufs - analyze.lufs_integrated(x), peak_db))
    return dsp.normalize(x, peak_db)


def _edges(x: np.ndarray, fade_in: int, fade_out: int) -> np.ndarray:
    g = np.ones(len(x))
    if fade_in:
        g[:fade_in] = 0.5 - 0.5 * np.cos(np.pi * np.arange(fade_in) / fade_in)
    if fade_out:
        g[len(x) - fade_out:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fade_out) / fade_out)
    return x * (g[:, None] if x.ndim == 2 else g)


def _encode_checked(spec: AssetSpec, x: np.ndarray, path: Path, dither_seed: str) -> dict:
    """Level, quantise, encode; re-encode (deterministically) while the decoded file breaks the true-peak ceiling or the
    one-shot edge limits (codec pre-echo can lift the first sample; the fix is a short fade on the source)."""
    goal, fin, fout = spec.peak_db, 0, 0
    for _ in range(5):
        q = dsp.quantize16(_edges(_level(spec, x, goal), fin, fout), dither_seed)
        src = dsp.dequantize16(q)
        nbytes = oggtools.encode_vorbis(src, path, oggtools.QUALITY[spec.quality])
        dec = oggtools.decode(path)
        tp = analyze.true_peak_db(dec)
        ok = True
        if tp > spec.peak_db + TP_TOLERANCE:
            goal -= (tp - spec.peak_db) + 0.02
            ok = False
        if not spec.loop:
            if float(np.max(np.abs(dec[0]))) > 0.016:
                fin, ok = max(fin * 2, 24), False
            if float(np.max(np.abs(dec[-1]))) > 0.0022:
                fout, ok = max(fout * 2, 128), False
        if ok:
            break
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    rt = analyze.codec_roundtrip(src, dec)
    return {"bytes": nbytes, "sha256": sha, "pcm_sha256": dsp.sha_pcm(q), "dec": dec, "src": src, **rt}


def render_variant(spec: AssetSpec, variant: int, asset_id: str, out_root: Path, fn, rhash: str) -> dict:
    """Render, encode and measure one asset.  Returns the manifest entry (no timings: entries must be byte-stable)."""
    name = seed_name(spec, variant)
    rng = dsp.rng_for(name, spec.salt)
    params = {k: v for k, v in spec.params.items() if k != "seed_name"}
    x = fn(rng, variant, **params)
    if not np.all(np.isfinite(x)):
        raise ValueError(f"{asset_id}: recipe produced NaN/inf")
    files = catalog.files_of(spec, asset_id)
    entry: dict = {"bank": catalog.bank_of(asset_id), "category": catalog.category_of(asset_id), "loop": bool(spec.loop),
                   "recipe_hash": rhash, "flavour": spec.flavour}
    stereo_res = None
    if "stereo" in files:
        xs = _master(spec, x, True)
        stereo_res = _encode_checked(spec, xs, out_root / files["stereo"], asset_id)
    if "mono" in files:
        xm = _master(spec, x, False) if stereo_res is None else dsp.to_mono(_master(spec, x, True))
        mono_res = _encode_checked(spec, xm, out_root / files["mono"], asset_id + ".mono")
    else:
        mono_res = None
    prim = stereo_res if stereo_res is not None else mono_res
    dec = prim["dec"]
    m = analyze.metrics(dec, spec.loop)
    entry.update({
        "file": catalog.primary_file(spec, asset_id), "channels": 2 if stereo_res is not None else 1,
        "duration_samples": int(len(dec)), "bytes": prim["bytes"], "sha256": prim["sha256"], "pcm_sha256": prim["pcm_sha256"],
        "lufs_i": m["lufs_i"], "lufs_src": round(analyze.lufs_integrated(prim["src"]), 2), "true_peak_db": m["true_peak_db"],
        "seam_score": m.get("seam_score"), "seam_src": round(dsp.seam_score(prim["src"]), 2) if spec.loop else None,
        "len_delta": prim["len_delta"], "snr_db": prim["snr_db"]})
    if stereo_res is not None and mono_res is not None:
        entry.update({"mono_file": files["mono"], "mono_bytes": mono_res["bytes"], "mono_sha256": mono_res["sha256"],
                      "mono_pcm_sha256": mono_res["pcm_sha256"]})
    return entry


# ---------------------------------------------------------------------------------------------- worker entry
_CACHE: dict = {}


def _load() -> tuple[dict, dict]:
    if not _CACHE:
        import sfx
        sfx.load_all()
        _CACHE["specs"] = {s.id: s for s in catalog.all_specs()}
        _CACHE["fns"] = sfx.RECIPES
    return _CACHE["specs"], _CACHE["fns"]


def worker(job: tuple) -> tuple[str, dict | str]:
    """Process-pool entry point: job = (spec_id, variant, asset_id, out_root, recipe_hash)."""
    spec_id, variant, asset_id, out_root, rhash = job
    specs, fns = _load()
    spec = specs[spec_id]
    try:
        return asset_id, render_variant(spec, variant, asset_id, Path(out_root), fns[spec.recipe], rhash)
    except Exception as e:  # noqa: BLE001 - reported by the driver
        import traceback
        return asset_id, "ERROR " + "".join(traceback.format_exception(e))[-1500:]
