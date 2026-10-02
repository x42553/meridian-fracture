"""movement.py - entity loops (engines, footsteps, aircraft) and air one-shots.

Loops are circular by construction: pulse trains placed with wrap-around, circular filters (`circ=True`), noise built
in the frequency domain, oscillators snapped to whole cycles.  Positional (mono)."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import (
    biquad, bandpass, colored_noise, crackle, env_exp, env_points, highpass, lfo, lowpass, modal, n_of, place, saturate, saw, sine, slow_noise, snap_freq, sweep_filter, t_axis)
from sfx import recipe
from sfx.kit import burst, finish, fsweep, thump


def _pulses(n: int, rng, rate: float, T: float, pulse, jitter: float, pattern=(1.0,), amp_jit: float = 0.1):
    x = np.zeros(n)
    for i in range(int(round(rate * T))):
        place(x, pulse, int(i / rate * dsp.SR + rng.normal(0, jitter)), pattern[i % len(pattern)] * (1 + amp_jit * rng.normal()), wrap=True)
    return x


@recipe
def engine_tracked(rng, v, heavy=False, amphibious=False):
    """Firing pulses through body resonances + track clatter + rumble; heavy = lower rate, more clatter."""
    T = 3.0
    n = n_of(T)
    rate = 18.0 if heavy else (24.0 if amphibious else 27.0)
    m = n_of(0.07)
    pulse = thump(m, 96 * (0.8 if heavy else 1.0), 40 if heavy else 44, 0.007, 0.012)
    x = _pulses(n, rng, rate, T, pulse, 14, amp_jit=0.12)
    x = biquad(lowpass(x, 240 if heavy else 300, 4, circ=True), "peak", 78 if heavy else 95, 2.0, 9.0, True)
    x = biquad(x, "peak", 160 if heavy else 190, 2.0, 5.0, True)
    cl = np.zeros(n)
    mm = n_of(0.06)
    links = 24 if heavy else 32
    link = 0.7 * burst(mm, rng, 0.003, lo=600 if heavy else 700, hi=4500) + modal([700, 1300, 2100] if heavy else [900, 1650, 2500], [0.014, 0.010, 0.006], [0.7, 0.5, 0.3], mm, rng, 0.02)
    for i in range(links):
        place(cl, link, int(i / links * n + rng.normal(0, 55)), rng.uniform(0.6, 1.0) * (1.4 if heavy else 1.0), wrap=True)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=100 if heavy else 110) * (0.7 if heavy else 0.5)
    y = (1.0 * x + (0.42 if heavy else 0.3) * cl + rumble) * (1 + 0.08 * lfo(1 / T, n))
    if amphibious:
        hiss = bandpass(colored_noise(n, rng, 1.0), 500, 4200, circ=True) * (0.7 + 0.3 * lfo(3 / T, n)) * 0.2
        gur = sine(160 + 60 * slow_noise(n, rng, 6.0, 1.0), n) * 0.05
        y = y * 0.8 + hiss + gur
    return saturate(y, 1.2)


@recipe
def engine_wheeled(rng, v):
    """Uneven 4-pulse firing group @ 44 Hz, intake + tyre noise, transmission whine."""
    T = 2.5
    n = n_of(T)
    m = n_of(0.04)
    pulse = (sine(fsweep(m, 150, 75, 0.008), m) + 0.35 * sine(fsweep(m, 300, 150, 0.008), m)) * env_exp(m, 0.011, 0.0006)
    x = _pulses(n, rng, 44.0, T, pulse, 10, (1.0, 0.7, 0.92, 0.62), 0.06)
    x = lowpass(x, 950, 4, circ=True)
    intake = bandpass(colored_noise(n, rng, 1.0), 300, 1300, circ=True) * (0.6 + 0.4 * lfo(2 / T, n)) * 0.20
    tire = bandpass(colored_noise(n, rng, 0.5), 900, 3800, circ=True) * 0.10
    whine = sine(snap_freq(780, T), n) * 0.03
    return saturate(x + intake + tire + whine, 1.3)


@recipe
def engine_boat(rng, v, large=False):
    """Irregular burble, water hiss, gurgle, propeller whine; large = slower and heavier with a wash."""
    T = 3.0 if large else 3.2
    n = n_of(T)
    rate = 8.0 if large else 12.5
    m = n_of(0.10 if large else 0.08)
    pulse = sine(fsweep(m, 100 if large else 130, 48 if large else 62, 0.014), m) * env_exp(m, 0.03 if large else 0.022, 0.001)
    x = _pulses(n, rng, rate, T, pulse, 90, (1.0,), 0.3)
    x = lowpass(x * (0.6 + 0.6 * rng.random()), 260 if large else 320, 4, circ=True)
    hiss = bandpass(colored_noise(n, rng, 1.0), 500 if large else 700, 4200 if large else 5200, circ=True) * (0.7 + 0.3 * lfo(2 / T, n)) * (0.34 if large else 0.26)
    gur = sine(140 + 45 * slow_noise(n, rng, 8.0, 1.0), n) * 0.06
    prop = sine(snap_freq(430 if large else 640, T), n) * 0.03
    wash = lowpass(colored_noise(n, rng, 2.0, lo=30, hi=400), 300, 2, circ=True) * (0.6 if large else 0.0)
    return saturate(x * 1.1 + hiss + gur + prop + wash, 1.2)


@recipe
def engine_sub(rng, v):
    """Submerged electric drive: deep hum, slow screw thumps, muffled water."""
    T = 4.0
    n = n_of(T)
    f0 = snap_freq(46.0, T)
    hum = sine(f0, n) * 0.6 + sine(2 * f0, n) * 0.3 + sine(3 * f0, n) * 0.12
    hum *= 1 + 0.06 * lfo(2 / T, n)
    m = n_of(0.12)
    thud = thump(m, 80, 40, 0.02, 0.04)
    screw = _pulses(n, rng, 5.0, T, thud, 60, (1.0, 0.85, 0.95, 0.8), 0.06)
    water = lowpass(colored_noise(n, rng, 1.5, lo=40, hi=900), 500, 2, circ=True) * 0.35
    whine = sine(snap_freq(410.0, T), n) * 0.02
    return saturate(hum + screw * 0.7 + water + whine, 1.15)


@recipe
def step_foot(rng, v):
    """Eight steps in 4 s with per-step variation and a faint gear jingle."""
    T = 4.0
    n = n_of(T)
    x = np.zeros(n)
    for i in range(8):
        m = n_of(0.30)
        f = 1.0 + 0.25 * (i % 2)
        st = burst(m, rng, 0.030, lo=150, hi=1400 * f, exponent=0.5) + 0.8 * thump(m, 105 * f, 62, 0.012, 0.05)
        st += 0.30 * highpass(crackle(m, rng, 900 * np.exp(-t_axis(m) / 0.05)), 1800) + \
            0.05 * modal([3200, 5100], [0.05, 0.03], [1, 0.6], m, rng, 0.02)
        place(x, saturate(st, 1.3), int(i * 0.5 * dsp.SR + rng.normal(0, 260)), 10 ** (rng.uniform(-2.0, 0.0) / 20), wrap=True)
    return x


@recipe
def air_jet(rng, v):
    """Jet engine idle-to-cruise: filtered roar, a periodic turbine whine and a high fizz."""
    T = 4.0
    n = n_of(T)
    jet = lowpass(colored_noise(n, rng, 0.9, lo=110, hi=11000), 3000, 2, circ=True) * (0.8 + 0.2 * lfo(2 / T, n))
    roar = colored_noise(n, rng, 2.0, lo=60, hi=520) * 1.0
    f = snap_freq(1180.0, T)
    whine = (sine(f, n) + 0.5 * sine(2 * f, n) + 0.22 * sine(3 * f, n)) * (1 + 0.05 * lfo(3 / T, n)) * 0.05
    fizz = highpass(colored_noise(n, rng, 0.0), 4500, circ=True) * 0.12
    return saturate(0.8 * jet + 0.6 * roar + whine + fizz, 1.2)


@recipe
def air_rotor(rng, v):
    """88 blade slaps in 4 s (22 Hz), 4-blade gain pattern, turbine whine, tail rotor."""
    T = 4.0
    n = n_of(T)
    bp = 22.0
    m = n_of(0.09)
    slap = burst(m, rng, 0.0045, lo=900, hi=3800)
    th = thump(m, 120, 55, 0.008, 0.028)
    blade = 0.8 * slap + 1.0 * th
    dry = _pulses(n, rng, bp, T, blade, 8, (1.0, 0.78, 0.92, 0.84), 0.05)
    am = 1.0 + 0.22 * np.sin(2 * np.pi * (bp / 4) * t_axis(n))
    whine = (sine(snap_freq(1450, T), n) + 0.4 * sine(snap_freq(2900, T), n)) * (1 + 0.1 * lfo(2 / T, n)) * 0.05
    tail = highpass(saw(snap_freq(118, T), n), 400, circ=True) * 0.07 * (0.6 + 0.4 * lfo(bp * 3 / 4, n))
    air = lowpass(colored_noise(n, rng, 1.0), 900, circ=True) * 0.22
    return saturate(dry * am * 0.85 + whine + tail + air, 1.6)


@recipe
def air_drone(rng, v):
    """Small multi-rotor drone: a high buzz made of 24 blade passes per second, jittery motor whine."""
    T = 2.0
    n = n_of(T)
    f = snap_freq(196.0, T)
    buzz = lowpass(saw(f * (1 + 0.004 * lfo(3 / T, n)), n) + 0.6 * saw(f * 1.503, n), 3600, 2, circ=True)
    blades = (0.55 + 0.45 * np.abs(np.sin(np.pi * snap_freq(24.0, T) * t_axis(n)))) ** 1.5
    whine = sine(snap_freq(1720, T) * (1 + 0.01 * lfo(5 / T, n)), n) * 0.05
    air = bandpass(colored_noise(n, rng, 0.5), 900, 5000, circ=True) * 0.12
    return saturate(buzz * blades * 0.5 + whine + air, 1.3)


# ------------------------------------------------------------------------------------------------ air one-shots
@recipe
def air_takeoff(rng, v):
    """Turbine spool-up with a pitch glide, roar swelling as the aircraft accelerates away."""
    L = 3.4
    n = n_of(L)
    t = t_axis(n)
    f = 180 + 1700 * (1 - np.exp(-t / 1.1))
    whine = (sine(f, n) + 0.5 * sine(2 * f, n) + 0.2 * sine(3.01 * f, n)) * env_points(n, [(0, 0), (0.3, 0.3, 1.5), (2.4, 0.6), (L - 0.05, 0.0, -2)])
    roar = sweep_filter(colored_noise(n, rng, 0.8, lo=100, hi=10000), 400 + 3600 * (1 - np.exp(-t / 1.4)), "lp", 0.9, 2, 16) * env_points(n, [(0, 0), (0.4, 0.3, 1.5), (2.2, 1.0), (L - 0.05, 0.0, -2)])
    low = colored_noise(n, rng, 2.0, lo=50, hi=300) * env_points(n, [(0, 0), (0.5, 0.5, 1.5), (2.4, 0.9), (L - 0.05, 0.0, -2)])
    x = saturate(0.12 * whine + 0.8 * roar + 0.6 * low, 1.2)
    return finish(x, L, 0.3)


@recipe
def air_landing(rng, v):
    """Approach, flare and spool-down: the mirror image of the take-off."""
    L = 3.4
    n = n_of(L)
    t = t_axis(n)
    f = 1800 - 1600 * (1 - np.exp(-np.maximum(t - 0.4, 0) / 1.3))
    whine = (sine(f, n) + 0.5 * sine(2 * f, n) + 0.2 * sine(3.01 * f, n)) * env_points(n, [(0, 0.5), (0.5, 0.7), (2.4, 0.3, -2), (L - 0.05, 0.0, -2)])
    roar = sweep_filter(colored_noise(n, rng, 0.8, lo=100, hi=10000), 400 + 3400 * np.exp(-np.maximum(t - 0.3, 0) / 1.4), "lp", 0.9, 2, 16) * env_points(n, [(0, 0.5), (0.4, 1.0), (2.0, 0.4, -2), (L - 0.05, 0.0, -2)])
    low = colored_noise(n, rng, 2.0, lo=50, hi=300) * env_points(n, [(0, 0.4), (0.5, 0.9), (2.4, 0.3, -2), (L - 0.05, 0.0, -2)])
    touch = thump(n, 90, 45, 0.02, 0.08, delay=0.9) * 0.4 + burst(n, rng, 0.02, lo=200, hi=2000, delay=0.9) * 0.2
    x = saturate(0.12 * whine + 0.8 * roar + 0.6 * low + touch, 1.2)
    return finish(x, L, 0.3)


@recipe
def air_crash_fall(rng, v):
    """Aircraft plummeting: a falling whine, sputtering engine, rising wind; ends before the impact."""
    L = 2.6
    n = n_of(L)
    t = t_axis(n)
    f = 1500 * np.exp(-t / 1.2) + 190
    whine = (sine(f, n) + 0.4 * sine(2 * f, n)) * env_points(n, [(0, 0.5), (0.3, 1.0), (2.3, 0.5), (L - 0.05, 0.0, -2)])
    gate = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (9 + 6 * t) * t))) * (0.35 + 0.65 * (rng.random(n) > 0.0))
    spit = lowpass(colored_noise(n, rng, 0.6, lo=100, hi=4000), 2600) * gate * env_points(n, [(0, 0.8), (1.6, 0.5), (L - 0.05, 0, -2)])
    wind = sweep_filter(colored_noise(n, rng, 0.6, lo=200, hi=9000), 500 + 2800 * (t / L) ** 1.5, "lp", 0.9, 2, 14) * env_points(n, [(0, 0.1), (L - 0.3, 1.0, 2), (L - 0.03, 0.0, -2)])
    x = saturate(0.16 * whine + 0.5 * spit + 0.8 * wind, 1.25)
    return finish(x, L, 0.15)
