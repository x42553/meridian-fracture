"""kit.py - shared building blocks of the SFX recipes: reverb presets, exponential sweeps, noise bursts, thumps,
flavour post-processing.  Changing this file changes every recipe hash (all assets are re-rendered)."""
from __future__ import annotations

from functools import lru_cache

import numpy as np

import dsp
from dsp import (SR, Array, colored_noise, env_exp, env_points, fade, fit, highpass, lowpass, make_ir, n_of,
                 reverb, saturate, sine, t_axis, to_mono)

_PRESETS = {
    "room": dict(rt60=0.45, predelay=0.004, damping_hz=7000, size=0.5),
    "small": dict(rt60=0.75, predelay=0.006, damping_hz=6000, size=0.7),
    "field": dict(rt60=0.55, predelay=0.012, damping_hz=3800, size=0.9, low_mult=0.7),
    "outdoor": dict(rt60=1.0, predelay=0.020, damping_hz=3600, size=1.2, low_mult=0.8),
    "hangar": dict(rt60=1.6, predelay=0.010, damping_hz=8000, size=1.0),
    "hall": dict(rt60=2.6, predelay=0.028, damping_hz=5200, size=1.6),
    "canyon": dict(rt60=3.4, predelay=0.045, damping_hz=2800, size=2.0, low_mult=1.3),
    "plate": dict(rt60=1.8, predelay=0.002, damping_hz=9500, size=0.4),
    "water": dict(rt60=1.3, predelay=0.008, damping_hz=2600, size=1.0, low_mult=1.1),
    "tunnel": dict(rt60=2.0, predelay=0.006, damping_hz=4200, size=0.8, low_mult=1.2),
}


@lru_cache(maxsize=None)
def _ir(preset: str) -> Array:
    return make_ir(seed="ir_" + preset, **_PRESETS[preset])


def verb(x: Array, preset: str, wet: float = 0.3, dry: float = 1.0, circular: bool = False) -> Array:
    return reverb(x, _ir(preset), wet=wet, dry=dry, circular=circular)


def fsweep(n: int, f0: float, f1: float, tc: float) -> Array:
    """Exponential pitch glide f0 -> f1 with time constant tc (kick/boom/zap staple)."""
    return f1 + (f0 - f1) * np.exp(-t_axis(n) / tc)


def burst(n: int, rng: np.random.Generator, tau: float, lo: float | None = None, hi: float | None = None,
          exponent: float = 0.0, delay: float = 0.0, attack: float = 0.0004) -> Array:
    """Band-limited noise burst with an exponential decay."""
    return colored_noise(n, rng, exponent, lo, hi, 0.35) * env_exp(n, tau, attack, delay)


def thump(n: int, f0: float, f1: float, tc: float, tau: float, delay: float = 0.0, drive: float = 0.0) -> Array:
    """Pitch-dropping sine (kick drum body)."""
    y = sine(fsweep(n, f0, f1, tc), n) * env_exp(n, tau, 0.0015, delay)
    return saturate(y, drive) if drive else y


def finish(x: Array, seconds: float, fade_out: float = 0.05) -> Array:
    return fade(fit(x, n_of(seconds)), 0.0, fade_out)


def mono(x: Array) -> Array:
    return to_mono(x)


def gain_db(db: float) -> float:
    return 10.0 ** (db / 20.0)


def echo_taps(x: Array, taps: list[tuple[float, float]], lp: float = 5000.0, hp: float = 0.0) -> Array:
    """Distinct slap-back / distant-echo reflections: [(delay_s, gain)], each low-passed (and optionally high-passed)."""
    out = np.zeros_like(x)
    for d, g in taps:
        r = lowpass(x, lp * (1.0 - 0.25 * d))
        if hp:
            r = highpass(r, hp)
        dsp.place(out, r * g, n_of(d))
    return out


def rand_range(rng: np.random.Generator, lo: float, hi: float) -> float:
    return float(rng.uniform(lo, hi))


def pass_by(n: int, t0: float, dist: float, speed: float, c: float = 343.0):
    """Geometry of a straight fly-by: returns (near 0..1, doppler factor, pan -1..1) per sample."""
    t = t_axis(n)
    xp = speed * (t - t0)
    r = np.sqrt(dist ** 2 + xp ** 2)
    vr = speed * xp / r
    return dist / r, 1.0 / (1.0 + vr / c), np.clip(xp / (r + 1e-9), -1.0, 1.0)


# ------------------------------------------------------------------------------------------- flavour post-process
def apply_flavour(x: Array, rng: np.random.Generator, fx: dict | None) -> Array:
    """Faction weapon flavour (audio spec 5.15 axes): pitch (semitones), bright (x), tail (x), drive (x), layer (name).
    Applied to a *mono* weapon signal after the recipe rendered it; an empty flavour is a no-op."""
    if not fx:
        return x
    y = to_mono(x)
    n0 = len(y)
    st = float(fx.get("pitch_st", 0.0))
    if st:
        y = dsp.pitch(y, st)
    br = float(fx.get("bright", 1.0))
    if abs(br - 1.0) > 1e-3:
        y = dsp.tilt(y, 4.5 * np.log2(br), 1800.0)
    tail = float(fx.get("tail", 1.0))
    if tail < 0.99:                                   # drier: the decay after the first 120 ms is faster
        y = y * np.exp(-np.maximum(t_axis(len(y)) - 0.12, 0.0) * (1.0 - tail) * 2.4 / (0.35 + 0.65 * tail))
    elif tail > 1.01:                                 # wetter: extra late reflections
        wet = to_mono(verb(y, "outdoor", 1.0, 0.0))
        y = fit(y, len(wet)) + 0.42 * (tail - 1.0) * wet
        y = y[:max(n0, len(y) // 2)] if len(y) > 2 * n0 else y
    drive = float(fx.get("drive", 1.0))
    if drive > 1.01:
        y = saturate(y * (1.0 + 0.8 * (drive - 1.0)), 1.0 + 1.6 * (drive - 1.0))
    elif drive < 0.99:
        y = y * (0.7 + 0.3 * drive)
    layer = fx.get("layer")
    if layer:
        y = y + flavour_layer(rng, str(layer), len(y))
    return fade(fit(y, n0), 0.0, 0.2)          # same duration as the base sound; the flavour never changes the length class


def flavour_layer(rng: np.random.Generator, name: str, n: int) -> Array:
    """Signature layers (5.15 last column): short, quiet, and spectrally distinct so factions stay recognisable."""
    t = t_axis(n)
    if name == "boom_clack":       # napc: breech clack after the boom
        return dsp.modal([1350, 2900], [0.012, 0.008], [0.35, 0.2], n, rng, 0.02) * env_exp(n, 1.0, 0.0004, 0.045)
    if name == "sensor_tick":      # nec: high sensor tick
        return sine(6200, n) * env_exp(n, 0.006, 0.0004, 0.004) * 0.22 + sine(3100, n) * env_exp(n, 0.01, 0.0004, 0.004) * 0.12
    if name == "energy_hum":       # olm: low energy hum under the shot
        return (sine(147, n) * 0.5 + sine(294, n) * 0.25) * env_points(n, [(0, 0), (0.05, 0), (0.09, 1, 1), (0.5, 0.5), (0.9, 0, -2)]) * 0.25
    if name == "brass_growl":      # def: low-brass growl
        f = 82.0 + 10.0 * np.exp(-t / 0.2)
        return lowpass(dsp.saw(f, n) + 0.6 * dsp.saw(f * 1.5, n), 700) * env_points(n, [(0, 0), (0.05, 0), (0.09, 1, 1), (0.35, 0.4), (0.75, 0, -2)]) * 0.2
    if name == "water_slap":       # pd: watery slap
        return burst(n, rng, 0.05, lo=300, hi=2200, delay=0.06) * 0.30 + dsp.fm(520 * np.exp(-t / 0.08) + 180, 1.6, 2.0, n) * env_exp(n, 0.12, 0.002, 0.05) * 0.16
    if name == "drone_buzz":       # han: buzzing drone layer
        return lowpass(dsp.saw(dsp.snap_freq(210.0, n / SR), n), 2600) * dsp.lfo(31.0, n) ** 2 * env_points(n, [(0, 0), (0.05, 0), (0.1, 1, 1), (0.5, 0.3), (0.9, 0, -2)]) * 0.16
    if name == "metal_clank":      # ae: metallic clank
        return dsp.modal([720, 1810, 2650, 4300], [0.06, 0.045, 0.03, 0.02], [0.5, 0.4, 0.3, 0.2], n, rng, 0.015) * env_exp(n, 1.0, 0.0006, 0.03) * 0.5
    if name == "shield_hum":       # sap: resonant shield hum
        return (sine(233, n) + 0.5 * sine(466.5, n) + 0.3 * sine(699, n)) * (1 + 0.15 * dsp.lfo(6.0, n)) * env_points(n, [(0, 0), (0.05, 0), (0.1, 1, 1), (0.6, 0.35), (1.1, 0, -2)]) * 0.14
    return np.zeros(n)
