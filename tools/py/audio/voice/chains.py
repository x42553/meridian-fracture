"""chains.py - numpy-only voice effect chains (replace the ffmpeg chains of the spike; no ffmpeg is required).

  computer(x)            EVA-style synthetic voice: pitch -5 % at constant tempo (phase vocoder), magnitude-only robotisation
                         blended 45 %, 14 / 29 ms metallic echo, presence EQ, compression, limiter
  officer(x, style)      light radio: gentle band limit, mild saturation, compression, faint hiss, soft squelch tail
  radio(x, style)        telephone band, companded low-bit crush, hard compression, tanh clip, squelch open / close, noise bed,
                         band-limited LAST (nothing above ~3.5 kHz survives)
  master(x, ...)         trim-free final level: LUFS target capped by the true-peak ceiling

`style` is the `radio.style` of the faction in game/data/audio/factions.json (clean_digital, crisp_wide, warm_analog,
noisy_clipped, smooth_digital, packet_chirp, crackly_hf, wobbly); `RadioProfile` carries its numbers.
Deterministic: all randomness comes from dsp.rng_for(seed).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

import analyze
import dsp
from dsp import Array, SR

CHAIN_VERSION = 1


# ------------------------------------------------------------------------------------------------ basics
def resample_fft(x: Array, sr_in: int, sr_out: int = SR) -> Array:
    """Band-limited FFT resampling (exact for the band below min(sr_in, sr_out) / 2)."""
    if sr_in == sr_out:
        return x.astype(np.float64)
    n_out = int(round(len(x) * sr_out / sr_in))
    spec = np.fft.rfft(x)
    out = np.zeros(n_out // 2 + 1, dtype=complex)
    k = min(len(spec), len(out))
    out[:k] = spec[:k]
    return np.fft.irfft(out * (n_out / len(x)), n_out)


def trim_speech(x: Array, sr: int, thr_db: float = -46.0, pad_ms: float = 25.0) -> Array:
    """Cut leading / trailing silence (absolute threshold), keep pad_ms, fade 6 ms in / 50 ms out."""
    idx = np.nonzero(np.abs(x) > dsp.db_to_lin(thr_db))[0]
    if idx.size == 0:
        return x
    p = int(sr * pad_ms / 1000)
    y = x[max(0, idx[0] - p): idx[-1] + p + 1].copy()
    fi, fo = min(int(sr * 0.006), len(y) // 4), min(int(sr * 0.05), len(y) // 4)
    y[:fi] *= np.linspace(0, 1, fi)
    y[-fo:] *= np.linspace(1, 0, fo)
    return y


def _frames(x: Array, n: int, hop: int) -> tuple[Array, int]:
    pad = n
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + n)])
    nfr = 1 + (len(xp) - n) // hop
    idx = np.arange(n)[None, :] + hop * np.arange(nfr)[:, None]
    return xp[idx], pad


def _ola(frames: Array, n: int, hop: int, length: int, pad: int, win: Array) -> Array:
    nfr = len(frames)
    out = np.zeros(hop * (nfr - 1) + n)
    norm = np.zeros_like(out)
    for i in range(nfr):
        out[i * hop:i * hop + n] += frames[i]
        norm[i * hop:i * hop + n] += win * win
    out = out / np.maximum(norm, 1e-6)
    return out[pad:pad + length]


def pitch_shift_keep_tempo(x: Array, ratio: float, n: int = 1024, hop: int = 256) -> Array:
    """Phase-vocoder time stretch by `ratio` (< 1 shortens), then varispeed by `ratio`: pitch x ratio, duration unchanged."""
    win = np.hanning(n)
    fr, pad = _frames(x, n, hop)
    spec = np.fft.rfft(fr * win, axis=1)
    mag, ph = np.abs(spec), np.angle(spec)
    omega = 2 * np.pi * np.arange(n // 2 + 1) / n
    hop_s = max(1, int(round(hop * ratio)))
    dphi = np.diff(ph, axis=0, prepend=ph[:1]) - omega * hop
    dphi = dphi - 2 * np.pi * np.round(dphi / (2 * np.pi))
    inst = omega + dphi / hop
    acc = np.cumsum(inst * hop_s, axis=0) + ph[:1]
    frames = np.fft.irfft(mag * np.exp(1j * acc), n, axis=1) * win
    y = _ola(frames, n, hop_s, int(len(x) * hop_s / hop), pad * hop_s // hop, win)
    return dsp.fit(dsp.resample_ratio(y, ratio), len(x))


def robotize(x: Array, n: int = 512, hop: int = 128) -> Array:
    """Magnitude-only resynthesis (zero-phase frames): the fundamental turns into a constant buzz at SR / hop."""
    win = np.hanning(n)
    fr, pad = _frames(x, n, hop)
    mag = np.abs(np.fft.rfft(fr * win, axis=1))
    frames = np.fft.fftshift(np.fft.irfft(mag, n, axis=1), axes=1) * win
    return _ola(frames, n, hop, len(x), pad, win)


def compress(x: Array, thr_db: float, ratio: float, attack_ms: float, release_ms: float, makeup_db: float = 0.0, blk: int = 32) -> Array:
    """Feed-forward compressor on per-block peaks; attack / release one-pole smoothing of the gain in dB."""
    n = len(x)
    nb = (n + blk - 1) // blk
    xp = np.concatenate([x, np.zeros(nb * blk - n)])
    lvl = 20 * np.log10(np.maximum(np.abs(xp).reshape(nb, blk).max(axis=1), 1e-9))
    over = np.maximum(lvl - thr_db, 0.0)
    target = -over * (1.0 - 1.0 / ratio)
    ca = np.exp(-blk / (attack_ms * 1e-3 * SR))
    cr = np.exp(-blk / (release_ms * 1e-3 * SR))
    g = np.empty(nb)
    s = 0.0
    for i in range(nb):
        t = target[i]
        s = t + (s - t) * (ca if t < s else cr)
        g[i] = s
    gi = np.interp(np.arange(n), (np.arange(nb) + 0.5) * blk, g)
    return x * dsp.db_to_lin(gi + makeup_db)


def echo_taps(x: Array, taps: list[tuple[float, float]]) -> Array:
    y = x.copy()
    for ms, g in taps:
        d = dsp.n_of(ms / 1000.0)
        y[d:] += g * x[:len(x) - d]
    return y


def soft_clip(x: Array, drive: float) -> Array:
    return np.tanh(x * drive) / np.tanh(drive)


def mulaw_crush(x: Array, bits: int, mix: float, hold: int = 1, mu: float = 255.0) -> Array:
    """Companded (mu-law) quantiser like ffmpeg acrusher mode=log; `hold` repeats every n-th sample (sample-rate crush)."""
    pk = max(float(np.max(np.abs(x))), 1e-9)
    u = np.clip(x / pk, -1, 1)
    c = np.sign(u) * np.log1p(mu * np.abs(u)) / np.log1p(mu)
    q = 2.0 ** (bits - 1)
    c = np.round(c * q) / q
    y = np.sign(c) * np.expm1(np.abs(c) * np.log1p(mu)) / mu * pk
    if hold > 1:
        y = np.repeat(y[::hold], hold)[: len(x)]
    return (1 - mix) * x + mix * y


def band(x: Array, lo: float, hi: float, order: int = 4) -> Array:
    return dsp.lowpass(dsp.highpass(x, lo, order), hi, order)


# ------------------------------------------------------------------------------------------------ radio profiles
@dataclass(frozen=True)
class RadioProfile:
    hp: float = 380.0
    lp: float = 3400.0
    bits: int = 10
    crush: float = 0.25
    hold: int = 1
    drive: float = 1.4
    thr_db: float = -26.0
    ratio: float = 6.0
    wobble: float = 0.0          # amplitude wobble depth (4.7 Hz)
    crackle: float = 0.0         # HF crackle density scale
    chirp: bool = False          # packet chirp at squelch open
    hiss_lo: float = 300.0
    hiss_hi: float = 3300.0
    open_ms: float = 55.0
    close_ms: float = 90.0
    hiss_db: float = -44.0


PROFILES: dict[str, RadioProfile] = {
    "clean_digital": RadioProfile(hp=360, lp=3600, bits=11, crush=0.15, drive=1.25),
    "crisp_wide": RadioProfile(hp=300, lp=4200, bits=11, crush=0.10, drive=1.15, ratio=5.0, hiss_hi=4000),
    "warm_analog": RadioProfile(hp=260, lp=3100, bits=12, crush=0.0, drive=1.8, ratio=5.0, hiss_lo=200, hiss_hi=2800, wobble=0.015),
    "noisy_clipped": RadioProfile(hp=420, lp=3300, bits=8, crush=0.45, drive=3.2, ratio=9.0, thr_db=-30.0),
    "smooth_digital": RadioProfile(hp=300, lp=3900, bits=12, crush=0.08, drive=1.15, ratio=4.0),
    "packet_chirp": RadioProfile(hp=400, lp=3500, bits=9, crush=0.35, hold=2, drive=1.5, chirp=True),
    "crackly_hf": RadioProfile(hp=350, lp=3700, bits=9, crush=0.30, drive=1.7, crackle=1.0),
    "wobbly": RadioProfile(hp=340, lp=3300, bits=10, crush=0.25, drive=1.4, wobble=0.09),
}


def profile(style: str, open_ms: float | None = None, close_ms: float | None = None, hiss_db: float | None = None) -> RadioProfile:
    p = PROFILES[style]
    kw = {}
    if open_ms is not None:
        kw["open_ms"] = float(open_ms)
    if close_ms is not None:
        kw["close_ms"] = float(close_ms)
    if hiss_db is not None:
        kw["hiss_db"] = float(hiss_db)
    return RadioProfile(**{**p.__dict__, **kw}) if kw else p


def squelch(kind: str, ms: float, seed: str, p: RadioProfile) -> Array:
    """Push-to-talk squelch.  open = click + band noise burst (+ 1.1 kHz blip or packet chirp); close = falling noise tail."""
    rng = dsp.rng_for(seed, 3)
    n = dsp.n_of(ms / 1000.0)
    if kind == "open":
        b = dsp.colored_noise(n, rng, 0.0, 900, 3400) * dsp.env_exp(n, ms / 1000.0 * 0.32, 0.0015) * 0.7
        b[:6] += np.linspace(0.5, 0.0, 6) * (1 if rng.random() < 0.5 else -1)
        if p.chirp:
            t = dsp.t_axis(n)
            f = 1200 + 1800 * np.clip(t / (ms / 1000.0), 0, 1)
            b += 0.16 * dsp.sine(f, n) * np.hanning(n)
        else:
            b += dsp.sine(1100, n) * dsp.env_exp(n, ms / 1000.0 * 0.22, 0.003) * 0.12
        return b
    return dsp.colored_noise(n, rng, 0.0, 700, 3200) * dsp.env_exp(n, ms / 1000.0 * 0.4, 0.0005) * 0.6


def radio_fx(x: Array, p: RadioProfile, seed: str, full: bool = True) -> Array:
    """Apply a radio profile to a dry mono signal and wrap it in squelch open / close.  full=False = the light `officer` version."""
    rng = dsp.rng_for(seed, 4)
    if full:
        y = band(x, p.hp, p.lp, 2)
        y = mulaw_crush(y, p.bits, p.crush, p.hold)
        y = compress(y, p.thr_db, p.ratio, 2.0, 45.0, 8.0)
        y = soft_clip(y, p.drive)
    else:
        y = band(x, max(p.hp * 0.55, 160.0), 6800.0, 2)
        y = compress(y, -24.0, 3.0, 4.0, 90.0, 4.0)
        y = soft_clip(y, 1.0 + 0.25 * (p.drive - 1.0))
    if p.wobble > 0:
        t = dsp.t_axis(len(y))
        y = y * (1.0 - p.wobble * (0.5 + 0.5 * np.sin(2 * np.pi * 4.7 * t + rng.uniform(0, 6.28))))
    head = squelch("open", p.open_ms, seed + "o", p) * (0.30 if full else 0.12)
    tail = squelch("close", p.close_ms, seed + "c", p) * (0.24 if full else 0.10)
    n = len(head) + len(y) + len(tail)
    z = np.zeros(n)
    z[len(head):len(head) + len(y)] += y
    z[:len(head)] += head
    z[len(head) + len(y):] += tail
    hiss = dsp.colored_noise(n, rng, 1.0, p.hiss_lo, p.hiss_hi) * dsp.db_to_lin(p.hiss_db + (0 if full else -8.0)) * 1.6
    hiss[: len(head) // 2] *= np.linspace(0.0, 1.0, len(head) // 2)
    z += hiss
    if p.crackle > 0:
        z += 0.05 * p.crackle * dsp.highpass(dsp.crackle(n, rng, 45.0), 1500, 2)
    if full:
        z = band(z, p.hp * 0.8, p.lp * 1.02, 4)          # band-limit LAST: the crusher / clipper aliasing must not leak upwards
        z = dsp.lowpass(z, p.lp * 1.05, 4)
    else:
        z = dsp.lowpass(z, 7200.0, 4)
    return z


# ------------------------------------------------------------------------------------------------ the three chains
def computer(x: Array, seed: str = "computer") -> Array:
    """EVA-style computer voice (see module docstring)."""
    y = dsp.highpass(x, 150.0, 2)
    y = pitch_shift_keep_tempo(y, 0.95)
    rob = robotize(y)
    z = 0.62 * y + 0.45 * rob * (dsp.rms(y) / max(dsp.rms(rob), 1e-9))
    z = echo_taps(z, [(14.0, 0.22), (29.0, 0.14)])
    z = dsp.biquad(z, "peak", 2600.0, 1.1, 4.0)
    z = compress(z, -22.0, 4.0, 4.0, 70.0, 3.0)
    z = dsp.lowpass(z, 9500.0, 2)
    return dsp.limit(z, -1.0, 0.004, 0.06)


def officer(x: Array, p: RadioProfile, seed: str) -> Array:
    return radio_fx(x, p, seed, full=False)


def radio(x: Array, p: RadioProfile, seed: str) -> Array:
    return radio_fx(x, p, seed, full=True)


def master(x: Array, lufs: float, tp_ceiling_db: float) -> Array:
    """DC removal and level: the LUFS target reached through a short look-ahead limiter that keeps the true peak under the
    ceiling (peaky radio material would otherwise be capped far below the target)."""
    x = x - np.mean(x)
    g = lufs - analyze.lufs_integrated(x)
    y = x
    for _ in range(5):
        y = dsp.limit(x * dsp.db_to_lin(g), tp_ceiling_db - 0.35, 0.004, 0.05)
        e = lufs - analyze.lufs_integrated(y)
        if abs(e) < 0.12:
            break
        g += e
    tp = analyze.true_peak_db(y)
    if tp > tp_ceiling_db:
        y = y * dsp.db_to_lin(tp_ceiling_db - tp)
    return y
