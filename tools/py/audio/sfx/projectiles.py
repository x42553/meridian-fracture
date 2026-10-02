"""projectiles.py - flight sounds: path voices of missiles/torpedoes (seamless loops) and the falling whistles of
arcing shells and bombs (one-shots that end just before the impact)."""
from __future__ import annotations

import numpy as np

from dsp import (
    colored_noise, crackle, env_points, highpass, lfo, lowpass, n_of, saturate, sine, snap_freq, saw, sweep_filter, t_axis)
from sfx import recipe
from sfx.kit import finish


@recipe
def missile_flight(rng, v):
    """Missile in flight (path voice loop): hissing motor, a low tonal rumble, a faint fizz of sparks."""
    T = 3.0
    n = n_of(T)
    kk = 1.0 + 0.07 * (v - 1)
    hiss = sweep_filter(colored_noise(n, rng, 0.8, lo=300, hi=11000), 2600 * kk + 1100 * lfo(2 / T, n), "lp", 0.9, 2, 12, circ=True)
    hiss *= 0.75 + 0.25 * lfo(snap_freq(9.0, T), n, 0.2)
    rum = colored_noise(n, rng, 2.0, lo=60, hi=340 * kk) * (0.8 + 0.2 * lfo(3 / T, n))
    whine = sine(snap_freq(520 * kk, T), n) * 0.03
    fizz = highpass(crackle(n, rng, 500), 3000) * 0.3
    return saturate(hiss * 0.7 + rum * 0.55 + whine + fizz, 1.2)


@recipe
def torpedo_flight(rng, v):
    """Torpedo under way (path voice loop): screw churn, cavitation bubbles, a steady motor whine."""
    T = 3.2
    n = n_of(T)
    kk = 1.0 + 0.06 * (v - 1)
    churn = lowpass(colored_noise(n, rng, 1.0, lo=80, hi=3000), 900 * kk, 4, circ=True) * (0.75 + 0.25 * lfo(snap_freq(6.0, T), n))
    bub = highpass(crackle(n, rng, 420), 500) * 0.35
    bub = lowpass(bub, 4500, 2, circ=True)
    whine = (sine(snap_freq(310 * kk, T), n) + 0.4 * sine(snap_freq(620 * kk, T), n)) * 0.05 * (1 + 0.1 * lfo(2 / T, n))
    blade = sine(snap_freq(24.0, T), n) * 0.25
    return saturate(churn * 0.9 + bub + whine + blade * lowpass(colored_noise(n, rng, 0.0), 300, 2, circ=True) * 0.2, 1.2)


@recipe
def shell_whistle(rng, v):
    """Falling shell: a descending whistle with turbulence that ends a moment before the impact."""
    L = 1.5
    n = n_of(L)
    t = t_axis(n)
    kk = 1.0 + 0.06 * (v - 1)
    f = (3400 * np.exp(-t / 0.9) + 1250) * kk
    whistle = (sine(f, n) + 0.35 * sine(2 * f, n)) * env_points(n, [(0, 0), (0.25, 0.5, 1.5), (1.2, 1.0, 1.0), (1.42, 0.0, -2)])
    air = sweep_filter(colored_noise(n, rng, 0.4, lo=500), 2500 + 1500 * np.exp(-t / 0.7), "lp", 1.2, 2, 12)
    air *= env_points(n, [(0, 0), (0.3, 0.3, 1.5), (1.25, 0.7), (1.42, 0.0, -2)])
    x = whistle * 0.35 * (1 + 0.06 * lfo(11.0, n)) + air * 0.6
    return finish(saturate(x, 1.2), L, 0.06)


@recipe
def bomb_whistle(rng, v):
    """Falling bomb: lower, wobbling siren-like scream with rumbling air, cut just before impact."""
    L = 1.8
    n = n_of(L)
    t = t_axis(n)
    kk = 1.0 + 0.06 * (v - 1)
    f = (1700 * np.exp(-t / 1.1) + 620) * kk * (1 + 0.012 * np.sin(2 * np.pi * 7 * t))
    scream = (saw(f, n) * 0.4 + sine(f, n)) * env_points(n, [(0, 0), (0.3, 0.45, 1.5), (1.5, 1.0, 1.0), (1.72, 0.0, -2)])
    scream = lowpass(scream, 3600)
    air = lowpass(colored_noise(n, rng, 1.0, lo=80), 2200) * env_points(n, [(0, 0), (0.4, 0.4, 1.5), (1.65, 0.9), (1.75, 0.0, -2)])
    x = scream * 0.3 + air * 0.55
    return finish(saturate(x, 1.2), L, 0.06)
