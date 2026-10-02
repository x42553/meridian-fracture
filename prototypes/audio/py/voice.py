"""voice.py - build-time announcer generator.

TTS (kokoro-onnx int8, Apache-2.0 weights)  ->  trim/fade  ->  ffmpeg style chain ('computer' | 'radio')
->  numpy squelch/noise bed (radio) -> LUFS normalise -> mono Vorbis (libvorbis via oggtools).
Also benchmarks Piper (CC0/public-domain voices) and macOS `say` (dev placeholder only - licence forbids shipping).

usage (inside .cache/venv):  python voice.py [--skip-faction] [--piper]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import wave
from pathlib import Path

import numpy as np

import analyze
import dsp
import oggtools
from dsp import SR

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT.parents[1]
TTS = PROJ / ".cache" / "tts"
BUILD = ROOT / ".build" / "voice"
OUT = ROOT / "assets" / "audio" / "voice"
ANA = ROOT / "analysis"

LINES: dict[str, str] = {
    "construction_complete": "Construction complete.",
    "unit_ready": "Unit ready.",
    "unit_lost": "Unit lost.",
    "low_power": "Low power.",
    "power_restored": "Power restored.",
    "superweapon_ready": "Superweapon ready.",
    "superweapon_detected": "Superweapon launch detected.",
    "enemy_superweapon_charging": "Enemy superweapon charging.",
    "base_under_attack": "Base under attack.",
    "collector_under_attack": "Collector under attack.",
    "insufficient_funds": "Insufficient funds.",
    "new_construction_options": "New construction options.",
    "reinforcements_arrived": "Reinforcements have arrived.",
    "research_complete": "Research complete.",
    "building_captured": "Building captured.",
    "structure_lost": "Structure destroyed.",
    "cannot_deploy": "Cannot deploy here.",
    "on_hold": "On hold.",
    "canceled": "Canceled.",
    "mission_accomplished": "Mission accomplished.",
    "victory": "You are victorious.",
    "defeat": "You have been defeated.",
}
RADIO_LINES = ("base_under_attack", "reinforcements_arrived", "unit_lost", "mission_accomplished", "collector_under_attack", "building_captured")
FACTION_VOICES = {"napc": "am_michael", "nec": "bf_emma", "olm": "am_fenrir", "def": "bm_george", "pd": "af_bella", "han": "af_nicole", "ae": "am_puck", "sap": "bf_isabella"}
FACTION_LINES = ("base_under_attack", "construction_complete", "superweapon_ready")
MAIN_VOICE = "af_heart"
LUFS_TARGET = -18.0

CHAINS = {
    # synthetic computer / EVA style: pitch -5 % (tempo kept), magnitude-only robotisation blended 45 %, tiny metallic echo, presence EQ, compression
    "computer": ("asetrate={sr_dn},aresample=44100,atempo=1.0526,highpass=f=150,asplit=2[a][b];"
                 "[b]afftfilt=real='hypot(re,im)*cos(0)':imag='hypot(re,im)*sin(0)':win_size=512:overlap=0.75[r];"
                 "[a][r]amix=inputs=2:weights='0.62 0.45':normalize=0,"
                 "aecho=0.7:0.55:14|29:0.22|0.14,equalizer=f=2600:t=q:w=1.1:g=4,"
                 "acompressor=threshold=0.08:ratio=4:attack=4:release=70:makeup=3,alimiter=limit=0.89"),
    # military radio: telephone band, light bit crush, hard compression, tanh soft clip (squelch + noise bed added in numpy)
    "radio": ("aresample=44100,highpass=f=420,lowpass=f=3400,acrusher=bits=9:mode=log:aa=1:mix=0.3,"
              "acompressor=threshold=0.04:ratio=9:attack=2:release=45:makeup=8,asoftclip=type=tanh,"
              "highpass=f=300,lowpass=f=3300,lowpass=f=3300"),   # band-limit LAST: crusher/clipper aliasing must not leak above the telephone band
}


def write_wav_sr(path: Path, x: np.ndarray, sr: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav_any(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as w:
        sr, ch, raw = w.getframerate(), w.getnchannels(), w.readframes(w.getnframes())
    y = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return (y.reshape(-1, ch).mean(axis=1) if ch > 1 else y), sr


def trim_speech(x: np.ndarray, sr: int, thr_db: float = -46.0, pad_ms: float = 25.0) -> np.ndarray:
    a = np.abs(x)
    idx = np.nonzero(a > dsp.db_to_lin(thr_db) * max(a.max(), 1e-9) ** 0.0)[0]
    if idx.size == 0:
        return x
    p = int(sr * pad_ms / 1000)
    y = x[max(0, idx[0] - p): idx[-1] + p + 1].copy()
    fi, fo = int(sr * 0.006), int(sr * 0.05)
    y[:fi] *= np.linspace(0, 1, fi)
    y[-fo:] *= np.linspace(1, 0, fo)
    return y


def run_chain(raw: Path, style: str, out_wav: Path, sr_in: int) -> None:
    chain = CHAINS[style].format(sr_dn=int(sr_in * 0.95))
    cmd = ["ffmpeg", "-y", "-nostats", "-hide_banner", "-loglevel", "error", "-i", str(raw)]
    cmd += ["-filter_complex", chain.replace(",asplit", ",asplit")] if "asplit" in chain else ["-af", chain]
    cmd += ["-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", str(out_wav)]
    subprocess.run(cmd, check=True)


def squelch(seed: str, kind: str) -> np.ndarray:
    """Push-to-talk squelch: 'open' = click + noise burst + 1.1 kHz blip; 'close' = falling noise tail."""
    rng = dsp.rng_for(seed, 3)
    if kind == "open":
        n = dsp.n_of(0.09)
        b = dsp.colored_noise(n, rng, 0.0, 900, 3400) * dsp.env_exp(n, 0.030, 0.002) * 0.7
        b += dsp.sine(1100, n) * dsp.env_exp(n, 0.02, 0.003) * 0.12
        return b
    n = dsp.n_of(0.14)
    return dsp.colored_noise(n, rng, 0.0, 700, 3200) * dsp.env_exp(n, 0.05, 0.0005) * 0.6


def finish_radio(x: np.ndarray, seed: str) -> np.ndarray:
    rng = dsp.rng_for(seed, 4)
    head, tail = squelch(seed + "o", "open"), squelch(seed + "c", "close")
    n = len(head) + len(x) + len(tail)
    y = np.zeros(n)
    y[len(head):len(head) + len(x)] += x
    y[:len(head)] += head
    y[len(head) + len(x):] += tail
    bed = dsp.colored_noise(n, rng, 1.0, 300, 3200) * 0.02
    bed[: len(head) // 2] *= np.linspace(0.0, 1.0, len(head) // 2)
    y += bed
    return dsp.lowpass(dsp.saturate(y, 1.15), 3500, 4)


def to_asset(wav: Path, ogg: Path, seed: str, style: str) -> dict:
    x = dsp.read_wav(str(wav))
    if style == "radio":
        x = finish_radio(x, seed)
    x = x - x.mean()
    gain_db = min(LUFS_TARGET - analyze.lufs_integrated(x), -1.5 - 20 * np.log10(dsp.true_peak(x) + 1e-12))
    x = x * dsp.db_to_lin(gain_db)
    ogg.parent.mkdir(parents=True, exist_ok=True)
    nbytes = oggtools.encode_vorbis(x, ogg, 0.5)
    m = analyze.metrics(x)
    m.update({"ogg_bytes": nbytes, "lufs_i": round(analyze.lufs_integrated(x), 1)})
    m.update({"true_peak_db": round(20 * np.log10(dsp.true_peak(x) + 1e-12), 1)})
    return m


def kokoro_batch(lines: dict[str, str], voice: str, speed: float = 1.0) -> tuple[dict[str, tuple[np.ndarray, int]], float]:
    from kokoro_onnx import Kokoro
    k = Kokoro(str(TTS / "kokoro-v1.0.int8.onnx"), str(TTS / "voices-v1.0.bin"))
    res, t0 = {}, time.time()
    for key, text in lines.items():
        s, sr = k.create(text, voice=voice, speed=speed, lang="en-us")
        res[key] = (np.asarray(s, dtype=np.float64), sr)
    return res, time.time() - t0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-faction", action="store_true")
    ap.add_argument("--packs", default="default,radio,factions")
    a = ap.parse_args()
    ANA.mkdir(exist_ok=True)
    manifest: dict[str, dict] = {}
    tiles: list[tuple[str, np.ndarray, str]] = []
    # ---- main announcer (computer style) + radio variants
    t0 = time.time()
    want = set(a.packs.split(","))
    jobs = []
    if "default" in want:
        synth, t_syn = kokoro_batch(LINES, MAIN_VOICE)
        audio_s = sum(len(x) / sr for x, sr in synth.values())
        print(f"kokoro int8 [{MAIN_VOICE}]: {len(LINES)} lines, {audio_s:.1f}s audio in {t_syn:.1f}s -> RTF {t_syn / audio_s:.3f} (incl. model load)")
        jobs += [("default", "computer", MAIN_VOICE, k, synth[k]) for k in LINES]
    if "radio" in want:
        radio_synth, _ = kokoro_batch({k: LINES[k] for k in RADIO_LINES}, "am_michael")
        jobs += [("radio", "radio", "am_michael", k, radio_synth[k]) for k in RADIO_LINES]
    if "factions" in want and not a.skip_faction:
        for fac, vname in FACTION_VOICES.items():
            fs, _ = kokoro_batch({k: LINES[k] for k in FACTION_LINES}, vname)
            jobs += [(fac, "computer", vname, k, fs[k]) for k in FACTION_LINES]
    for pack, style, vname, key, (x, sr) in jobs:
        raw = BUILD / "raw" / f"{pack}_{vname}" / f"{key}.wav"
        write_wav_sr(raw, trim_speech(x, sr), sr)
        proc = BUILD / "proc" / pack / f"{key}.wav"
        proc.parent.mkdir(parents=True, exist_ok=True)
        run_chain(raw, style, proc, sr)
        ogg = OUT / pack / f"{key}.ogg"
        m = to_asset(proc, ogg, f"{pack}.{key}", style)
        m.update({"pack": pack, "style": style, "engine": "kokoro-onnx-int8", "voice": vname, "text": LINES[key], "chars_per_s": round(len(LINES[key]) / m["duration_s"], 1)})
        manifest[f"{pack}/{key}"] = m
        if pack in ("default", "radio") and key in ("base_under_attack", "superweapon_detected", "construction_complete", "mission_accomplished"):
            tiles.append((f"{pack}/{key} [{style}] '{LINES[key]}'", dsp.read_wav(str(proc)) if style == "computer" else dsp.read_wav(str(proc)), f"{m['duration_s']}s lufs {m['lufs_i']} cen {m['centroid_hz']} tp {m['true_peak_db']}"))
    tot = sum(v["ogg_bytes"] for v in manifest.values())
    print(f"{len(manifest)} voice assets, {tot / 1024:.0f} KB total ({tot / len(manifest) / 1024:.1f} KB avg), wall {time.time() - t0:.1f}s")
    mp = OUT / "voice_manifest.json"
    old = json.loads(mp.read_text()) if mp.exists() else {}
    old.update(manifest)
    mp.write_text(json.dumps(old, indent=1))
    if tiles:
        analyze.contact_sheet(tiles, str(ANA / "voice_sheet.png"), cols=2, cell_w=640, cell_h=170)


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
