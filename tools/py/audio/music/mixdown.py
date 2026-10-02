"""mixdown.py - stems -> balanced, limited, encoded assets and manifest entries (audio spec 5.8, 7.8, 10.2 music row).

Track mastering
  1. DC removal per stem (mean of the whole period: keeps the loop seam continuous), bass folded to mono;
  2. every stem is balanced to its STEM_LUFS target (relative mix of the layers, dual-mono LUFS for the bass);
  3. ONE shared gain brings the sum to the track's LUFS target (combat -14.4, calm -16.1) while a CIRCULAR look-ahead limiter
     computes a single gain-reduction curve from the *sum* and applies it to every stem, so the four stems still add up to
     the reference mix and the game can crossfade layers freely;
  4. 16-bit TPDF dither, libvorbis (oggtools), decode, sum the decoded stems and lower the shared gain (re-encode, max 5
     passes) until the decoded sum stays below -2.0 dBTP.
Stingers go through render._encode_checked (one-shot level, edge guards, true-peak ceiling).
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
import oggtools
import render
from catalog import music as cm
from music.arrange import limiter_gr_db

MUSIC_VERSION = 1
SEAM_TARGET = 3.7             # re-encode a stem with more bits when its decoded loop seam exceeds this (QA limit 4.0)
MUSIC_QUALITY_MIN = 0.3
MUSIC_QUALITY = 0.5           # libvorbis quality of stems and stingers (spec 9.3 lever 0.45 -> 0.55; 0.5 keeps the 46 MB budget)
MUSIC_PREFIX = "mus/"
_SRC = ("flavours.py", "arrange.py", "stingers.py", "mixdown.py")


def _sources_hash() -> str:
    h = hashlib.sha256()
    for n in _SRC:
        h.update((Path(__file__).parent / n).read_bytes())
    h.update((Path(__file__).parent.parent / "catalog" / "music.py").read_bytes())
    return h.hexdigest()


def recipe_hash(spec) -> str:
    fields = {k: getattr(spec, k) for k in spec.__dataclass_fields__}
    h = hashlib.sha256()
    h.update(_sources_hash().encode())
    h.update(json.dumps(fields, sort_keys=True, default=list).encode())
    h.update(f"|dsp{dsp.DSP_VERSION}|master{render.MASTER_CHAIN_VERSION}|music{MUSIC_VERSION}".encode())
    return h.hexdigest()


def _dual(x: np.ndarray) -> np.ndarray:
    return np.stack([x, x], axis=1) if x.ndim == 1 else x


def _lufs(x: np.ndarray) -> float:
    return analyze.lufs_integrated(_dual(x))


def master_track(spec: cm.TrackSpec, stems: dict[str, np.ndarray]) -> tuple[dict[str, np.ndarray], dict]:
    """Balanced, limited stems ready for quantising (bass mono) and the mastering info."""
    style = "combat" if spec.style == "combat" else "calm"
    bal: dict[str, np.ndarray] = {}
    for k in cm.STEMS:
        x = stems[k]
        x = dsp.to_mono(x) if k in cm.MONO_STEMS else x
        x = x - np.mean(x, axis=0)
        bal[k] = x * dsp.db_to_lin(cm.STEM_LUFS[style][k] - _lufs(x))
    ceiling = cm.MIX_TP_MAX - 0.3          # margin for the codec's own overshoot (the encode loop trims what is left)
    g_db = spec.lufs - _lufs(sum(_dual(v) for v in bal.values()))
    gain = np.ones(spec.length_samples)
    for _ in range(10):
        mix = sum(_dual(v) for v in bal.values()) * dsp.db_to_lin(g_db)
        gr = limiter_gr_db(mix, ceiling, true_peak=True)
        gain = dsp.db_to_lin(-gr)
        err = spec.lufs - _lufs(mix * gain[:, None])
        if abs(err) < 0.03:
            break
        g_db += err
    out = {k: (v * dsp.db_to_lin(g_db) * (gain if v.ndim == 1 else gain[:, None])) for k, v in bal.items()}
    info = {"master_gain_db": round(float(g_db), 2), "max_gr_db": round(float(-20 * np.log10(gain.min())), 2),
            "mean_gr_db": round(float(np.mean(-20 * np.log10(gain))), 3)}
    return out, info


# ------------------------------------------------------------------------------------------------ entries
def _sum_decoded(decs: dict[str, np.ndarray]) -> np.ndarray:
    return sum(_dual(v) for v in decs.values())


def _entry(aid: str, spec_flavour: str | None, path_rel: str, x_src: np.ndarray, dec: np.ndarray, res: dict, rhash: str, loop: bool, extra: dict) -> dict:
    e = {"bank": catalog.bank_of(aid), "category": catalog.category_of(aid), "loop": loop, "recipe_hash": rhash, "flavour": spec_flavour,
         "file": path_rel, "channels": 1 if dec.ndim == 1 else 2, "duration_samples": int(len(dec)), "bytes": res["bytes"],
         "sha256": res["sha256"], "pcm_sha256": res["pcm_sha256"], "lufs_i": round(analyze.lufs_integrated(dec), 2),
         "lufs_src": round(analyze.lufs_integrated(x_src), 2), "true_peak_db": round(analyze.true_peak_db(dec), 2),
         "seam_score": round(dsp.seam_score(dec), 2) if loop else None, "seam_src": round(dsp.seam_score(x_src), 2) if loop else None,
         "len_delta": res["len_delta"], "snr_db": res["snr_db"]}
    e.update(extra)
    return e


def render_track(spec: cm.TrackSpec, out_root: Path, rhash: str) -> dict[str, dict]:
    from music import arrange
    from music.flavours import FLAVOURS
    stems = arrange.arrange(FLAVOURS[spec.flavour], spec.style, spec.bars)
    for k, v in stems.items():
        if len(v) != spec.length_samples or not np.all(np.isfinite(v)):
            raise ValueError(f"{spec.id}/{k}: bad stem ({len(v)} vs {spec.length_samples} samples)")
    mastered, info = master_track(spec, stems)
    trim = 0.0
    qual = {k: MUSIC_QUALITY for k in cm.STEMS}
    for _ in range(8):
        src, dec, paths, res = {}, {}, {}, {}
        for k in cm.STEMS:
            aid = f"{spec.folder}/{k}"
            rel = aid + (".mono.ogg" if k in cm.MONO_STEMS else ".ogg")
            x = mastered[k] * dsp.db_to_lin(-trim)
            q = dsp.quantize16(x, aid)
            src[k] = dsp.dequantize16(q)
            while True:          # the codec's start-up error can push the decoded seam over the limit: spend more bits on that stem
                nbytes = oggtools.encode_vorbis(src[k], out_root / rel, qual[k])
                dec[k] = oggtools.decode(out_root / rel)
                if dsp.seam_score(dec[k]) <= SEAM_TARGET or qual[k] <= MUSIC_QUALITY_MIN:
                    break
                qual[k] = round(qual[k] - 0.05, 2)
            paths[k] = rel
            rt = analyze.codec_roundtrip(src[k], dec[k])
            res[k] = {"bytes": nbytes, "sha256": hashlib.sha256((out_root / rel).read_bytes()).hexdigest(), "pcm_sha256": dsp.sha_pcm(q), **rt}
        tp = analyze.true_peak_db(_sum_decoded(dec))
        if tp <= cm.MIX_TP_MAX - 0.05:
            break
        trim += (tp - (cm.MIX_TP_MAX - 0.1))
    ref = spec.lufs
    out: dict[str, dict] = {}
    for k in cm.STEMS:
        aid = f"{spec.folder}/{k}"
        style = "combat" if spec.style == "combat" else "calm"
        extra = {"track": spec.id, "stem": k, "bpm": spec.bpm, "master_gain_db": round(info["master_gain_db"] - trim, 2),
                 "lufs_ref": round(cm.STEM_LUFS[style][k] + info["master_gain_db"] - trim - info["mean_gr_db"], 2), "quality": qual[k]}
        out[aid] = _entry(aid, spec.faction, paths[k], src[k], dec[k], res[k], rhash, True, extra)
    out[f"{spec.folder}/bass"]["mix_lufs_ref"] = ref
    out[f"{spec.folder}/drums"]["max_gr_db"] = info["max_gr_db"]
    return out


def render_stinger(spec: cm.StingerSpec, out_root: Path, rhash: str) -> dict[str, dict]:
    from music import stingers
    x = stingers.render(spec)
    if len(x) != spec.length_samples:
        x = dsp.fit(x, spec.length_samples)
    if not np.all(np.isfinite(x)):
        raise ValueError(f"{spec.id}: NaN")
    oggtools.QUALITY["music_lean"] = MUSIC_QUALITY
    aspec = catalog.AssetSpec(spec.id, "music_stinger", channels="stereo", peak_db=-2.1, lufs=cm.STINGER_LUFS, quality="music_lean")
    rel = spec.id + ".ogg"
    xs = render._master(aspec, x, True)
    res = render._encode_checked(aspec, xs, out_root / rel, spec.id)
    e = _entry(spec.id, spec.faction, rel, res["src"], res["dec"], res, rhash, False, {"kind": spec.kind, "stinger": spec.key})
    return {spec.id: e}


def worker(job: tuple) -> tuple[str, dict | str]:
    """Process-pool entry: job = ('track'|'stinger', spec_id, out_root, recipe_hash) -> (job key, {asset id: entry} | error)."""
    kind, sid, out_root, rhash = job
    try:
        if kind == "track":
            spec = next(t for t in cm.tracks() if t.id == sid)
            res = render_track(spec, Path(out_root), rhash)
        else:
            spec = next(s for s in cm.stingers() if s.id == sid)
            res = render_stinger(spec, Path(out_root), rhash)
        return f"{kind}:{sid}", res
    except Exception as e:  # noqa: BLE001 - reported by the driver
        import traceback
        return f"{kind}:{sid}", "ERROR " + "".join(traceback.format_exception(e))[-1800:]


# ------------------------------------------------------------------------------------------------ driver
def plan(prev_assets: dict, only: list[str], force: bool, root: Path):
    """Return (jobs, carried, expected asset ids).  A job renders one track (4 stems) or one stinger."""
    import fnmatch

    def sel(*names: str) -> bool:
        if not only:
            return True
        for p in only:
            for n in names:
                if any(c in p for c in "*?["):
                    if fnmatch.fnmatch(n, p):
                        return True
                elif n == p or n.startswith(p.rstrip("/") + "/") or n.startswith(p):
                    return True
        return False

    jobs, carried, expected = [], {}, set()
    for kind, specs in (("track", cm.tracks()), ("stinger", cm.stingers())):
        for spec in specs:
            ids = spec.stem_ids() if kind == "track" else [spec.id]
            rh = recipe_hash(spec)
            expected.update(ids)
            olds = [prev_assets.get(a) for a in ids]
            intact = all(o is not None and o.get("recipe_hash") == rh and (root / o["file"]).exists()
                         and (root / o["file"]).stat().st_size == o["bytes"] for o in olds)
            names = ids + [spec.id, getattr(spec, "key", spec.id), getattr(spec, "faction", None) or "menu"]
            if intact and not (force and sel(*names)):
                carried.update({a: o for a, o in zip(ids, olds)})
            elif sel(*names):
                jobs.append((kind, spec.id, str(root), rh))
            else:
                carried.update({a: o for a, o in zip(ids, olds) if o is not None})
    return jobs, carried, expected


def run_jobs(jobs: list[tuple], n_jobs: int) -> tuple[dict[str, dict], int]:
    results: dict[str, dict] = {}
    errors = 0
    t0 = time.time()
    order = sorted(jobs, key=lambda j: 0 if j[0] == "track" else 1)

    def take(key: str, res) -> None:
        nonlocal errors
        if isinstance(res, str):
            errors += 1
            print(f"FAILED {key}\n{res}")
        else:
            results.update(res)
            print(f"  rendered {key} ({time.time() - t0:.0f}s)", flush=True)

    if n_jobs <= 1 or len(order) <= 1:
        for j in order:
            take(*worker(j))
    else:
        import multiprocessing as mp
        from concurrent.futures import ProcessPoolExecutor
        with ProcessPoolExecutor(max_workers=n_jobs, mp_context=mp.get_context("spawn")) as ex:
            for key, res in ex.map(worker, order, chunksize=1):
                take(key, res)
    return results, errors
