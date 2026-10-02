"""ui.py - interface sounds from a tiny note DSL: each UI id is a list of notes
   [kind, freq_hz, start_s, dur_s, gain]  with kind in  bell | pluck | buzz | tick | sweep | ping
plus the recipe parameters `tail` (total seconds), `room`/`wet` (optional reverb) and `width`.
Everything is short (0.05-1.2 s), dry-ish, and peaks well below the effects."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import (
    colored_noise, env_exp, env_points, fm, lowpass, n_of, place, saturate, sine, saw, square, t_axis, widen)
from sfx import recipe
from sfx.kit import burst, finish, fsweep, verb


def _note(rng, kind: str, f: float, dur: float) -> np.ndarray:
    m = n_of(dur)
    t = t_axis(m)
    if kind == "bell":
        return fm(f, 3.5, 2.2 * np.exp(-t / 0.10), m) * env_exp(m, dur * 0.35, 0.002)
    if kind == "pluck":
        return (sine(f, m) + 0.35 * sine(2 * f, m) + 0.12 * sine(3 * f, m)) * env_exp(m, dur * 0.28, 0.0015)
    if kind == "buzz":
        return lowpass(square(f, m) * 0.6 + saw(f * 1.005, m) * 0.5, 1400) * env_points(m, [(0, 0), (0.008, 1, 1), (dur * 0.8, 0.8), (dur, 0, -3)])
    if kind == "tick":
        return burst(m, rng, min(0.004, dur * 0.3), lo=max(f * 0.5, 200), hi=min(f * 5, 15000)) * 0.6 + sine(f, m) * env_exp(m, min(0.008, dur * 0.4), 0.0004) * 0.8
    if kind == "sweep":                          # f = start, glides to f * 0.5 (down) or f * 2 (up) via negative / positive... see below
        return sine(fsweep(m, f, f * 0.5, dur * 0.4), m) * env_exp(m, dur * 0.5, 0.004)
    if kind == "sweepup":
        return sine(fsweep(m, f * 0.5, f, dur * 0.4), m) * env_points(m, [(0, 0), (0.01, 1, 1), (dur * 0.8, 0.9), (dur, 0, -3)])
    if kind == "ping":
        return (sine(f, m) + 0.15 * sine(2 * f, m)) * env_exp(m, dur * 0.3, 0.006)
    raise ValueError(kind)


@recipe
def ui_voice(rng, v, notes=(), tail=0.5, room="", wet=0.15, width=1.0, noise_sweep=None):
    n = n_of(tail)
    y = np.zeros(n)
    for kind, f, at, dur, g in notes:
        m = min(n_of(dur), n - n_of(at))
        if m > 8:
            place(y, _note(rng, kind, f, dur)[:m], n_of(at), g)
    if noise_sweep:                              # (f0, f1, gain): filtered-noise whoosh across the whole sound
        f0, f1, g = noise_sweep
        t = t_axis(n)
        w = dsp.sweep_filter(colored_noise(n, rng, 0.5, lo=200, hi=12000), f0 + (f1 - f0) * (t / tail), "lp", 1.2, 2, 12)
        y = y + w * env_points(n, [(0, 0), (tail * 0.35, 1.0, 1), (tail * 0.9, 0.5), (tail, 0, -2)]) * g
    y = saturate(y, 1.15)
    if room:
        y = verb(y, room, wet)
        y = widen(y, width) if width != 1.0 else y
    return finish(y, tail, min(0.08, tail * 0.3))
