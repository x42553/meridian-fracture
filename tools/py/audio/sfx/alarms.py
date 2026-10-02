"""alarms.py - siren loop, countdown beeps, base-attack ping, incoming klaxon, low-power pulse."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import (
    echo, env_exp, env_points, lfo, lowpass, n_of, place, saturate, saw, sine, snap_freq, square, t_axis, widen)
from sfx import recipe
from sfx.kit import finish, mono, thump, verb


@recipe
def sw_siren(rng, v):
    """Two wail cycles per 4 s, detuned pair, circular echo + reverb, 2 Hz pulse."""
    T = 4.0
    n = n_of(T)
    t = t_axis(n)
    lf = 520 * np.exp(np.log(880 / 520) * (0.5 - 0.5 * np.cos(2 * np.pi * 2 / T * t)))
    x = saw(lf, n) * 0.5 + saw(lf * 1.004, n) * 0.4 + sine(lf, n) * 0.4
    x = lowpass(x, 3400, 4, circ=True) * (0.85 + 0.15 * lfo(4 / T, n))
    x += sine(snap_freq(55, T), n) * 0.08 * (0.5 + 0.5 * lfo(8 / T, n))
    x = saturate(x, 1.5)
    st = np.stack([x, np.roll(x, n_of(0.009))], axis=1)
    st = echo(st, 0.25, 0.5, 0.35, 3, circular=True)
    return verb(st, "hangar", 0.20, circular=True)


@recipe
def countdown_tick(rng, v):
    """Short 880 Hz beep (the runtime pitches it x1.00 ... x1.26 towards zero)."""
    n = n_of(0.40)
    x = lowpass(square(880, n) * 0.6 + sine(880, n), 5000) * env_points(n, [(0, 0), (0.004, 1, 1), (0.09, 0.9), (0.12, 0, -3)])
    return finish(mono(verb(saturate(x, 1.3), "room", 0.12)), 0.40, 0.05)


@recipe
def countdown_final(rng, v):
    """Long 1.32 kHz launch tone."""
    n = n_of(1.2)
    x = lowpass(square(1320, n) * 0.5 + sine(1320, n) + 0.3 * sine(2640, n), 6000) * env_points(n, [(0, 0), (0.004, 1, 1), (0.6, 0.9), (0.95, 0, -3)])
    return finish(widen(verb(saturate(x, 1.3), "hangar", 0.2), 1.2), 1.2, 0.2)


@recipe
def base_attack(rng, v):
    """Two-tone ping: descending minor third, bell-like, urgent but not shrill (0.6 s)."""
    n = n_of(0.8)
    y = np.zeros(n)
    for f, at in ((1175.0, 0.0), (932.0, 0.21)):
        m = n - n_of(at)
        t = t_axis(m)
        b = (dsp.fm(f, 2.0, 1.6 * np.exp(-t / 0.08), m) + 0.3 * sine(f * 2, m)) * env_exp(m, 0.16, 0.002)
        place(y, b, n_of(at), 1.0)
    return finish(widen(verb(saturate(y, 1.25), "plate", 0.16), 1.2), 0.8, 0.15)


@recipe
def incoming(rng, v):
    """Three sharp klaxon bursts (1.5 s), higher and drier than the barrage warning."""
    n = n_of(1.6)
    y = np.zeros(n)
    for i in range(3):
        m = n_of(0.34)
        t = t_axis(m)
        f = 760 * (1 + 0.25 * t / 0.34)
        b = lowpass(saw(f, m) * 0.5 + square(f, m) * 0.4 + sine(f, m), 4200) * env_points(m, [(0, 0), (0.006, 1, 1), (0.28, 0.9), (0.34, 0, -3)])
        place(y, b, n_of(0.02 + i * 0.5))
    return finish(widen(verb(saturate(y, 1.3), "room", 0.1), 1.15), 1.6, 0.15)


@recipe
def low_power(rng, v):
    """Pulsing low tone: two soft down-sweeping pulses, unmistakably 'power is failing'."""
    n = n_of(1.3)
    y = np.zeros(n)
    for i, at in enumerate((0.0, 0.55)):
        m = n_of(0.5)
        t = t_axis(m)
        f = 330 * np.exp(-t / 0.4) + 150
        b = lowpass(saw(f, m) * 0.4 + sine(f, m), 1500) * env_points(m, [(0, 0), (0.02, 1, 1), (0.3, 0.7), (0.5, 0, -3)])
        place(y, b, n_of(at))
    y += thump(n, 90, 55, 0.05, 0.15, delay=0.0) * 0.4 + thump(n, 90, 55, 0.05, 0.15, delay=0.55) * 0.4
    return finish(widen(verb(saturate(y, 1.3), "room", 0.12), 1.15), 1.3, 0.2)
