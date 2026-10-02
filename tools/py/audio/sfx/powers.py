"""powers.py - support-power cues: 8 classes x (activate 1.5-2.5 s, loop 4 s, end 1 s) plus the barrage warning / impact.

Classes: recon (radar sweep + sonar pings), repair (ratchet + rising motor), buff (rising fifth chord + shimmer, pitched
by `root_hz`), shield (metallic clunk + low tone), cloak (phasing shimmer), smoke (canister pops + hiss), barrage (klaxon +
incoming whistles + thumps), generic (neutral chime and whoosh).  Loops are circular (4 s)."""
from __future__ import annotations

import numpy as np

from dsp import (bandpass, colored_noise, crackle, env_exp, env_points, fm, highpass, lfo, lowpass, modal, n_of, place,
                 saturate, saw, sine, snap_freq, square, sweep_filter, t_axis, widen)
from sfx import recipe
from sfx.kit import burst, finish, fsweep, thump, verb

T_LOOP = 4.0


def _bell(f: float, n: int, tau: float, delay: float = 0.0, idx: float = 2.2, ratio: float = 3.5) -> np.ndarray:
    t = t_axis(n)
    return fm(f, ratio, idx * np.exp(-t / (tau * 0.5)), n) * env_exp(n, tau, 0.003, delay)


def _whistle(rng, n: int, at: float, dur: float, f0: float, f1: float, g: float = 1.0) -> np.ndarray:
    m = n_of(dur)
    t = t_axis(m)
    f = f1 + (f0 - f1) * np.exp(-t / (dur * 0.5))
    w = (sine(f, m) + 0.3 * sine(2 * f, m)) * env_points(m, [(0, 0), (dur * 0.25, 0.6, 1.5), (dur * 0.9, 1.0), (dur, 0.0, -2)])
    w += lowpass(colored_noise(m, rng, 0.4, lo=500), 3000) * env_points(m, [(0, 0), (dur * 0.6, 0.4, 1.5), (dur, 0.0, -2)]) * 0.8
    out = np.zeros(n)
    place(out, w * 0.3 * g, n_of(at))
    return out


def _klaxon(n: int, at: float, bursts: int = 3, f: float = 640.0, dur: float = 0.34, gap: float = 0.16) -> np.ndarray:
    y = np.zeros(n)
    for i in range(bursts):
        m = n_of(dur)
        t = t_axis(m)
        ff = f * (1 + 0.18 * (t / dur))
        b = lowpass(saw(ff, m) * 0.5 + square(ff * 0.5, m) * 0.3 + sine(ff, m), 3500) * env_points(m, [(0, 0), (0.01, 1, 1), (dur - 0.05, 0.9), (dur, 0, -3)])
        place(y, b * 0.55, n_of(at + i * (dur + gap)))
    return y


@recipe
def power_activate(rng, v, cls="generic", root_hz=220.0):
    L = {"recon": 2.2, "repair": 2.0, "buff": 2.2, "shield": 1.8, "cloak": 2.2, "smoke": 2.2, "barrage": 2.5, "generic": 1.6}[cls]
    n = n_of(L)
    t = t_axis(n)
    if cls == "recon":
        sweep = sweep_filter(colored_noise(n, rng, 0.8, lo=200, hi=9000), 300 + 5000 * np.clip(t / 1.4, 0, 1) ** 1.5, "lp", 1.5, 2, 14) * env_points(n, [(0, 0), (0.1, 0.6, 1), (1.4, 0.8), (1.7, 0, -2)])
        y = 0.5 * sweep
        for i, at in enumerate((0.6, 1.1, 1.55)):
            y += (sine(1320, n) + 0.2 * sine(2640, n)) * env_exp(n, 0.28, 0.005, at) * (0.5 - 0.1 * i)
    elif cls == "repair":
        y = np.zeros(n)
        for i in range(10):
            place(y, burst(n_of(0.05), rng, 0.005, lo=900, hi=6000) + modal([2200, 3400], [0.012, 0.008], [0.4, 0.3], n_of(0.05), rng), n_of(0.05 + i * 0.09), 0.6)
        f = 180 + 900 * np.clip(t / 1.4, 0, 1) ** 1.6
        y += lowpass(saw(f, n) * 0.4 + sine(f, n), 4000) * env_points(n, [(0, 0), (0.05, 0.6, 1), (1.5, 0.7), (1.9, 0, -2)]) * 0.45
    elif cls == "buff":
        y = np.zeros(n)
        for i, r in enumerate((1.0, 1.5, 2.0)):
            m = n - n_of(0.09 * i)
            b = _bell(root_hz * r * 2, m, 0.9)
            y[n_of(0.09 * i):] += b * (0.6 - 0.1 * i)
        y += highpass(colored_noise(n, rng, 0.0), 5000) * env_points(n, [(0, 0), (0.2, 0.05, 1), (1.4, 0.03), (2.1, 0, -2)])
    elif cls == "shield":
        y = modal([170, 420, 950, 2200], [0.2, 0.12, 0.08, 0.05], [0.8, 0.5, 0.3, 0.2], n, rng, 0.01) * env_exp(n, 1.0, 0.0005) + thump(n, 110, 48, 0.03, 0.18, drive=1.4)
        y += (sine(147, n) + 0.5 * sine(220, n)) * env_points(n, [(0, 0), (0.1, 0.0), (0.3, 0.6, 1.5), (1.1, 0.5), (1.75, 0, -2)]) * 0.5
    elif cls == "cloak":
        base = colored_noise(n, rng, 0.3, lo=400, hi=9000)
        y = sweep_filter(base, 6000 * np.exp(-t / 0.9) + 500, "lp", 2.5, 2, 20) * env_points(n, [(0, 0), (0.05, 0.8, 1), (1.6, 0.6), (2.15, 0, -2)])
        y = y * (0.6 + 0.4 * np.sin(2 * np.pi * (14 - 9 * t / L) * t)) * 0.5
        y += sine(fsweep(n, 1500, 300, 0.7), n) * env_exp(n, 0.9, 0.01) * 0.12
    elif cls == "smoke":
        y = np.zeros(n)
        for i, at in enumerate((0.0, 0.14, 0.31)):
            m = n - n_of(at)
            pop = thump(m, 160, 70, 0.015, 0.05) + burst(m, rng, 0.03, lo=300, hi=4500)
            y[n_of(at):] += pop * 0.8
        y += highpass(colored_noise(n, rng, 0.3), 1500) * env_points(n, [(0, 0), (0.15, 0.7, 1), (1.3, 0.45), (2.15, 0, -2)]) * 0.4
    elif cls == "barrage":
        y = _klaxon(n, 0.0, 2, dur=0.30, gap=0.10) * 0.8
        for i, at in enumerate((0.85, 1.05, 1.28)):
            y += _whistle(rng, n, at, 1.0, 2600, 1200, 0.9)
        for at in (0.95, 1.4, 1.75):
            y += thump(n, 120, 48, 0.03, 0.16, delay=at, drive=1.5) * 0.7 + burst(n, rng, 0.04, lo=200, hi=2500, delay=at) * 0.5
    else:  # generic
        y = _bell(root_hz * 2, n, 0.9) * 0.6
        y[n_of(0.1):] += _bell(root_hz * 3, n - n_of(0.1), 0.8) * 0.5
        y += sweep_filter(colored_noise(n, rng, 0.8, lo=200, hi=8000), 400 + 3000 * np.clip(t / 0.6, 0, 1), "lp", 1.0, 2, 12) * env_points(n, [(0, 0), (0.2, 0.3, 1), (0.9, 0)]) * 0.5
    return finish(widen(verb(saturate(y, 1.2), "plate" if cls in ("buff", "generic", "cloak") else "hangar", 0.18), 1.2), L, 0.35)


@recipe
def power_loop(rng, v, cls="generic", root_hz=220.0):
    T = T_LOOP
    n = n_of(T)
    t = t_axis(n)
    if cls == "recon":
        ph = (t / T * 2.0) % 1.0
        y = lowpass(colored_noise(n, rng, 1.0, lo=200, hi=5000), 2400, circ=True) * (0.15 + 0.5 * np.exp(-((ph - 0.5) / 0.2) ** 2)) * 0.5
        y += sine(snap_freq(1320, T), n) * np.exp(-(((ph - 0.5) % 1.0) / 0.04)) * 0.25
        y += sine(snap_freq(110, T), n) * 0.12
    elif cls == "repair":
        y = np.zeros(n)
        for i in range(16):
            place(y, burst(n_of(0.05), rng, 0.005, lo=900, hi=6000) * 0.6, int(i / 16 * n), 1.0, wrap=True)
        f = snap_freq(520, T)
        y = y * 0.6 + lowpass(saw(f, n) * 0.3 + sine(f, n), 3000, circ=True) * 0.22 * (1 + 0.2 * lfo(2 / T, n))
    elif cls == "buff":
        y = sum(sine(snap_freq(root_hz * r, T), n, 0.1 * i) * a for i, (r, a) in enumerate(((1, 0.4), (1.5, 0.3), (2, 0.25), (3, 0.08)))) * (1 + 0.15 * lfo(2 / T, n))
        y += highpass(colored_noise(n, rng, 0.0), 5000, circ=True) * (0.5 + 0.5 * lfo(3 / T, n)) * 0.03
    elif cls == "shield":
        y = (sine(snap_freq(147, T), n) * 0.5 + sine(snap_freq(220, T), n) * 0.3 + sine(snap_freq(294, T), n) * 0.12) * (1 + 0.2 * lfo(2 / T, n))
        y += bandpass(colored_noise(n, rng, 0.5), 900, 3200, circ=True) * 0.05 * (0.5 + 0.5 * lfo(5 / T, n))
    elif cls == "cloak":
        y = bandpass(colored_noise(n, rng, 0.3), 700, 6500, circ=True) * (0.5 + 0.5 * np.sin(2 * np.pi * snap_freq(3.0, T) * t)) * 0.2
        y += sine(snap_freq(660, T), n) * (0.5 + 0.5 * lfo(3 / T, n)) * 0.03
    elif cls == "smoke":
        y = highpass(lowpass(colored_noise(n, rng, 0.4), 6500, circ=True), 900, circ=True) * (0.8 + 0.2 * lfo(2 / T, n)) * 0.3
    elif cls == "barrage":
        y = np.zeros(n)
        for at in (0.4, 1.9, 2.7):
            place(y, thump(n_of(0.6), 110, 42, 0.03, 0.15, drive=1.4) * 0.7 + burst(n_of(0.6), rng, 0.05, lo=150, hi=2000) * 0.4, n_of(at), 1.0, wrap=True)
        for at in (0.9, 2.3):
            place(y, _whistle(rng, n_of(0.9), 0.0, 0.9, 2200, 1100, 0.8), n_of(at), 1.0, wrap=True)
        y += lowpass(colored_noise(n, rng, 2.0, lo=30, hi=200), 160, circ=True) * 0.4
    else:
        y = (sine(snap_freq(root_hz, T), n) * 0.5 + sine(snap_freq(root_hz * 1.5, T), n) * 0.25) * (1 + 0.15 * lfo(2 / T, n))
        y += lowpass(colored_noise(n, rng, 1.0), 1200, circ=True) * 0.05
    return saturate(y, 1.15)


@recipe
def power_end(rng, v, cls="generic", root_hz=220.0):
    L = 1.2
    n = n_of(L)
    t = t_axis(n)
    if cls == "recon":
        y = (sine(1320 * np.exp(-t / 0.4) + 300, n) + 0.2 * sine(2640 * np.exp(-t / 0.4) + 600, n)) * env_exp(n, 0.3, 0.004) * 0.6
    elif cls == "repair":
        f = 900 * np.exp(-t / 0.3) + 100
        y = lowpass(saw(f, n) * 0.4 + sine(f, n), 3500) * env_exp(n, 0.35, 0.004) * 0.6 + thump(n, 110, 50, 0.02, 0.06, delay=0.35) * 0.6
    elif cls == "buff":
        y = sum(_bell(root_hz * r * 2, n, 0.5) * (0.5 - 0.1 * i) for i, r in enumerate((3.0, 2.0, 1.5)))
    elif cls == "shield":
        y = (sine(147 * np.exp(-t / 0.5) + 60, n) + 0.5 * sine(220 * np.exp(-t / 0.5) + 90, n)) * env_exp(n, 0.4, 0.005) * 0.6
        y += highpass(crackle(n, rng, 400 * np.exp(-t / 0.2) + 5), 2500) * 0.5
    elif cls == "cloak":
        y = sweep_filter(colored_noise(n, rng, 0.3, lo=400, hi=9000), 500 + 6000 * (t / L) ** 2, "lp", 2.5, 2, 16) * env_points(n, [(0, 0), (0.8, 0.8, 1.5), (1.15, 0, -2)]) * 0.4
    elif cls == "smoke":
        y = highpass(colored_noise(n, rng, 0.3), 1500) * env_exp(n, 0.35, 0.02) * 0.35 + thump(n, 130, 60, 0.02, 0.05) * 0.3
    elif cls == "barrage":
        y = thump(n, 100, 40, 0.04, 0.3, drive=1.5) * 0.7 + lowpass(colored_noise(n, rng, 2.0, lo=30, hi=250), 200) * env_exp(n, 0.4) * 0.7
    else:
        y = _bell(root_hz * 3, n, 0.5) * 0.5
        y[n_of(0.12):] += _bell(root_hz * 2, n - n_of(0.12), 0.5) * 0.5
    return finish(widen(verb(saturate(y, 1.2), "room", 0.14), 1.15), L, 0.3)


@recipe
def barrage_warning(rng, v):
    """Incoming-fire klaxon: three rising bursts."""
    L = 2.2
    n = n_of(L)
    y = _klaxon(n, 0.0, 3, f=560, dur=0.42, gap=0.2)
    return finish(widen(verb(saturate(y, 1.25), "hangar", 0.16), 1.15), L, 0.3)


@recipe
def barrage_impact(rng, v):
    """One barrage shell landing: rising whistle, sharp crack, thump, debris."""
    L = 2.4
    n = n_of(L)
    t = t_axis(n)
    y = _whistle(rng, n, 0.0, 0.7, 2800, 1300, 1.0)
    at = 0.7
    y += burst(n, rng, 0.005, lo=1400, hi=14000, delay=at) * 1.1 + thump(n, 105, 36, 0.04, 0.32, delay=at, drive=1.6) + burst(n, rng, 0.05, lo=250, hi=2600, delay=at) * 1.0
    y += highpass(lowpass(crackle(n, rng, 500 * np.exp(-np.maximum(t - at, 0) / 0.35) * (t > at) + 1), 6000), 1000) * 0.4 * env_exp(n, 0.7, 0.01, at)
    return finish(verb(saturate(y, 1.4), "hall", 0.24), L, 0.4)
