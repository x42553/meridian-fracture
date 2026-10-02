"""superweapons.py - the 8 superweapon sound sequences (audio spec 5.12 table): charge (loop, bound to the launcher, pitch
follows the charge fraction), launch, loop (during the effect), impact (one voice per packet), end.  Each name uses only
the phases it needs.  Flat = stereo master; positional = mono."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import (
    bandpass, colored_noise, crackle, env_exp, env_points, fm, highpass, lfo, lowpass, modal, n_of, place, saturate, saw, sine, snap_freq, sweep_filter, t_axis, widen)
from sfx import recipe
from sfx.kit import burst, finish, fsweep, thump, verb

T = 4.0


def _whistle(rng, n: int, at: float, dur: float, f0: float, f1: float, g: float = 1.0) -> np.ndarray:
    m = n_of(dur)
    t = t_axis(m)
    f = f1 + (f0 - f1) * np.exp(-t / (dur * 0.5))
    w = (sine(f, m) + 0.3 * sine(2 * f, m)) * env_points(m, [(0, 0), (dur * 0.25, 0.6, 1.5), (dur * 0.9, 1.0), (dur, 0.0, -2)])
    w += lowpass(colored_noise(m, rng, 0.4, lo=500), 3200) * env_points(m, [(0, 0), (dur * 0.6, 0.4, 1.5), (dur, 0.0, -2)]) * 0.8
    out = np.zeros(n)
    place(out, w * 0.3 * g, n_of(at))
    return out


def _boom(rng, n: int, at: float, s: float = 1.0, mid: float = 1.0) -> np.ndarray:
    """A heavy detonation layer starting at `at`."""
    return (burst(n, rng, 0.006, lo=1200, hi=14000, delay=at) * 1.0 + thump(n, 60 / s ** 0.3, 22, 0.20 * s, 0.9 * s, delay=at, drive=1.8)
            + burst(n, rng, 0.06 * s, lo=220, hi=2600, delay=at) * 1.1 * mid
            + lowpass(colored_noise(n, rng, 0.0), 260, 4) * env_exp(n, 0.35 * s, 0.002, at)
            + colored_noise(n, rng, 2.0, lo=22, hi=140) * env_exp(n, 1.0 * s, 0.02, at) * 0.8)


def _debris(rng, n: int, at: float, dens: float = 600.0, tau: float = 1.4) -> np.ndarray:
    t = t_axis(n)
    return highpass(lowpass(crackle(n, rng, dens * np.exp(-np.maximum(t - at, 0) / (tau * 0.6)) * (t >= at) + 2), 6500), 1000) * 0.45 * env_exp(n, tau, 0.05, at)


# ------------------------------------------------------------------------------------------------ ATLAS (orbital kinetic)
@recipe
def sw_atlas_launch(rng, v):
    L = 5.0
    n = n_of(L)
    t = t_axis(n)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=200) * env_points(n, [(0, 0), (1.5, 0.7, 1.5), (3.6, 1.0), (L - 0.05, 0, -2)]) * 1.1
    rise = sine(300 + 2600 * (t / L) ** 2, n) * env_points(n, [(0, 0), (1.0, 0.15, 1.5), (3.6, 0.5), (L - 0.05, 0, -2)])
    y = rumble + 0.35 * lowpass(rise, 5000)
    for at, f0 in ((2.0, 2400), (2.7, 2800), (3.4, 3200)):
        y += _whistle(rng, n, at, 1.5, f0, 900, 1.0)
    y += burst(n, rng, 0.05, lo=200, hi=2500) * 0.6      # opening transient
    return finish(widen(verb(saturate(y, 1.25), "hall", 0.18), 1.3), L, 0.5)


@recipe
def sw_atlas_impact(rng, v):
    L = 4.5
    n = n_of(L)
    t = t_axis(n)
    y = _boom(rng, n, 0.0, 1.2) + burst(n, rng, 0.004, lo=1800, hi=15000) * 0.9
    y += fm(fsweep(n, 1800, 300, 0.05), 1.7, 3.0 * np.exp(-t / 0.05), n) * env_exp(n, 0.12, 0.001) * 0.4    # shock crack
    y += _debris(rng, n, 0.15, 800, 2.0)
    return finish(widen(verb(saturate(y, 1.5), "canyon", 0.3), 1.3), L, 0.8)


# ------------------------------------------------------------------------------------------------ AURORA (microwave)
@recipe
def sw_aurora_charge(rng, v):
    n = n_of(T)
    f = snap_freq(880, T)
    y = (sine(f, n) + 0.35 * sine(2 * f, n) + 0.15 * sine(3 * f, n)) * (1 + 0.25 * lfo(snap_freq(6, T) * T / T, n))
    y = y * 0.5 + sine(snap_freq(110, T), n) * 0.3 + highpass(colored_noise(n, rng, 0.0), 4500, circ=True) * 0.03
    return saturate(y, 1.2)


@recipe
def sw_aurora_launch(rng, v):
    L = 3.0
    n = n_of(L)
    t = t_axis(n)
    y = thump(n, 85, 30, 0.10, 0.6, drive=1.7) + burst(n, rng, 0.08, lo=300, hi=6000) * 0.9
    y += fm(fsweep(n, 3200, 400, 0.30), 1.41, 4.0 * np.exp(-t / 0.35), n) * env_exp(n, 0.9, 0.001) * 0.5
    y += highpass(crackle(n, rng, 900 * np.exp(-t / 0.6) + 20), 2200) * 0.6
    y += colored_noise(n, rng, 2.0, lo=25, hi=150) * env_exp(n, 0.9, 0.01) * 0.8
    return finish(widen(verb(saturate(y, 1.4), "hangar", 0.26), 1.3), L, 0.5)


@recipe
def sw_aurora_loop(rng, v):
    n = n_of(T)
    y = highpass(crackle(n, rng, 260), 1800) * 0.7
    y = lowpass(y, 9000, 2, circ=True)
    hold = int(0.04 * dsp.SR)
    sh = np.repeat(rng.uniform(900, 5200, n // hold + 2), hold)[:n]
    sparks = fm(sh, 2.13, 6.0, n) * (0.3 + 0.7 * (np.abs(y) > 0.05)) * 0.05
    hum = sine(snap_freq(100, T), n) * 0.25 + sine(snap_freq(200, T), n) * 0.1
    return saturate(y + sparks + hum, 1.25)


@recipe
def sw_aurora_impact(rng, v):
    L = 2.4
    n = n_of(L)
    t = t_axis(n)
    y = thump(n, 95, 34, 0.06, 0.4, drive=1.7) + burst(n, rng, 0.01, lo=500, hi=12000) * 0.9
    y += highpass(crackle(n, rng, 1600 * np.exp(-t / 0.5) + 40, 1.2), 2400) * 1.0
    y += sine(2600 * np.exp(-t / 0.35) + 120, n) * env_exp(n, 0.45, 0.003) * 0.3
    return finish(widen(verb(saturate(y, 1.4), "plate", 0.24), 1.3), L, 0.5)


@recipe
def sw_aurora_end(rng, v):
    L = 2.0
    n = n_of(L)
    t = t_axis(n)
    y = highpass(crackle(n, rng, 500 * np.exp(-t / 0.6) + 5), 2000) * 0.7
    y += (sine(1500 * np.exp(-t / 0.5) + 80, n) + 0.3 * sine(3000 * np.exp(-t / 0.5) + 160, n)) * env_exp(n, 0.7, 0.005) * 0.35
    y += thump(n, 90, 40, 0.06, 0.25, drive=1.3) * 0.6
    return finish(widen(verb(saturate(y, 1.3), "plate", 0.2), 1.2), L, 0.5)


# ------------------------------------------------------------------------------------------------ HELIOS (reflector)
@recipe
def sw_helios_charge(rng, v):
    n = n_of(T)
    t = t_axis(n)
    y = np.zeros(n)
    for i in range(6):                                            # glints: bell pings on a shimmering pad
        f = 2400 * (1 + 0.5 * (i % 3) * 0.25)
        m = n_of(0.6)
        place(y, (sine(f, m) + 0.4 * sine(2 * f, m)) * env_exp(m, 0.22, 0.004), int(i / 6 * n), 0.25, wrap=True)
    pad = sum(sine(snap_freq(f, T), n) * a for f, a in ((1320, 0.15), (1760, 0.12), (2640, 0.06))) * (1 + 0.3 * lfo(3 / T, n))
    return saturate(y + pad + sine(snap_freq(88, T), n) * 0.2, 1.15)


@recipe
def sw_helios_launch(rng, v):
    L = 3.0
    n = n_of(L)
    t = t_axis(n)
    ch = (saw(400 + 2600 * np.clip(t / 0.6, 0, 1) ** 2, n) * 0.5 + sine(600 + 3000 * np.clip(t / 0.6, 0, 1) ** 2, n)) * env_points(n, [(0, 0), (0.6, 1, 2.5), (0.62, 0)])
    ign = thump(n, 90, 32, 0.08, 0.6, delay=0.6, drive=1.7) + burst(n, rng, 0.1, lo=400, hi=9000, delay=0.6) * 0.9
    beam = (saw(220, n) * 0.4 + sine(220, n) * 0.5 + highpass(colored_noise(n, rng, 0.0), 2500) * 0.15) * env_points(n, [(0, 0), (0.6, 0), (0.68, 1, 1), (2.0, 0.6), (L - 0.05, 0, -2)])
    y = lowpass(ch, 6000) * 0.5 + ign + lowpass(beam, 4000) * 0.6
    return finish(widen(verb(saturate(y, 1.35), "hall", 0.22), 1.3), L, 0.5)


@recipe
def sw_helios_loop(rng, v):
    n = n_of(T)
    f = snap_freq(220, T)
    y = lowpass(saw(f, n) * 0.4 + sine(f, n) * 0.5 + sine(f / 2, n) * 0.4, 2600, 4, circ=True) * (1 + 0.1 * lfo(2 / T, n))
    y += highpass(crackle(n, rng, 240), 2500) * 0.35 + bandpass(colored_noise(n, rng, 0.0), 2800, 6500, circ=True) * 0.08
    return saturate(y, 1.2)


@recipe
def sw_helios_end(rng, v):
    L = 2.2
    n = n_of(L)
    t = t_axis(n)
    y = highpass(crackle(n, rng, 500 * np.exp(-t / 0.7) + 5), 2200) * 0.7
    y += (saw(220 * np.exp(-t / 0.4) + 50, n) * 0.4 + sine(220 * np.exp(-t / 0.4) + 50, n)) * env_exp(n, 0.4, 0.004) * 0.45
    for at in (0.5, 0.9, 1.4):                                    # cooling ticks
        y += modal([1900, 3100], [0.02, 0.014], [0.5, 0.3], n, rng) * env_exp(n, 1.0, 0.0003, at) * 0.4
    return finish(widen(verb(saturate(lowpass(y, 9000), 1.25), "room", 0.16), 1.2), L, 0.5)


# ------------------------------------------------------------------------------------------------ PERUN (missile complex)
@recipe
def sw_perun_launch(rng, v):
    L = 5.0
    n = n_of(L)
    t = t_axis(n)
    motor = sweep_filter(colored_noise(n, rng, 1.0, lo=100, hi=9000), 250 + 3400 * np.clip(t / 0.8, 0, 1) ** 1.4 * np.exp(-np.maximum(t - 2.0, 0) / 1.6) + 300, "lp", 0.9, 2, 20)
    amp = env_points(n, [(0, 0), (0.15, 0.85, 1.5), (2.2, 1.0), (L - 0.3, 0.0, -2.5)])
    rumble = colored_noise(n, rng, 2.0, lo=35, hi=200) * amp * 1.2
    fizz = highpass(crackle(n, rng, 900 * amp + 30), 2200) * amp * 0.5
    ign = burst(n, rng, 0.05, lo=300, hi=5000) * 0.9 + thump(n, 90, 32, 0.05, 0.5, drive=1.6)
    y = motor * amp * 0.9 + rumble + fizz + ign
    return finish(verb(saturate(y, 1.3), "canyon", 0.22), L, 0.6)


@recipe
def sw_perun_impact(rng, v):
    L = 4.5
    n = n_of(L)
    t = t_axis(n)
    y = thump(n, 52, 20, 0.15, 1.0, drive=1.8) + burst(n, rng, 0.015, lo=100, hi=3000) * 1.6         # bunker-buster thud
    y += burst(n, rng, 0.004, lo=1500, hi=14000) * 0.9 + lowpass(colored_noise(n, rng, 0.0), 220, 4) * env_exp(n, 0.5) * 1.2
    y += highpass(crackle(n, rng, 1300 * np.exp(-t / 0.7) + 15), 1800) * 0.7 * env_exp(n, 1.6, 0.01, 0.1)   # ring of fragmentation
    y += modal([160, 380, 900], [0.9, 0.6, 0.4], [0.3, 0.2, 0.12], n, rng, 0.02) * env_exp(n, 1.5, 0.001, 0.05)
    y += colored_noise(n, rng, 2.0, lo=22, hi=130) * env_exp(n, 1.7, 0.02) * 1.0
    return finish(verb(saturate(y, 1.5), "canyon", 0.3), L, 0.8)


# ------------------------------------------------------------------------------------------------ TEMPEST (drone swarm)
@recipe
def sw_tempest_launch(rng, v):
    L = 3.4
    n = n_of(L)
    t = t_axis(n)
    y = np.zeros(n)
    for i in range(24):                                           # 24 drones released in a burst
        at = rng.uniform(0.0, 1.3)
        m = n_of(1.2)
        f = rng.uniform(320, 640)
        d = (saw(f * (1 + 0.4 * np.exp(-t_axis(m) / 0.3)), m) * 0.4 + sine(f, m)) * env_points(m, [(0, 0), (0.05, 1, 1), (0.7, 0.5), (1.15, 0, -2)])
        place(y, lowpass(d, 3200) * 0.06, n_of(at))
    y += sweep_filter(colored_noise(n, rng, 0.8, lo=200, hi=9000), 400 + 3500 * np.exp(-((t - 0.6) / 0.6) ** 2), "lp", 1.0, 2, 14) * env_points(n, [(0, 0), (0.1, 0.5, 1), (1.6, 0.0, -2)]) * 0.6
    y += thump(n, 110, 45, 0.04, 0.25, drive=1.4) * 0.8 + burst(n, rng, 0.03, lo=300, hi=4500) * 0.8
    return finish(verb(saturate(y, 1.3), "outdoor", 0.2), L, 0.5)


@recipe
def sw_tempest_loop(rng, v):
    n = n_of(T)
    y = np.zeros(n)
    for i in range(18):                                           # swarm: detuned buzzes with individual wobble
        f = snap_freq(rng.uniform(170, 330), T)
        y += lowpass(saw(f * (1 + 0.006 * lfo(int(rng.integers(1, 5)) / T, n, rng.random())), n) * 0.5 + sine(f, n), 2600, 2, circ=True) * 0.05
    y += bandpass(colored_noise(n, rng, 0.5), 600, 4200, circ=True) * (0.7 + 0.3 * lfo(3 / T, n)) * 0.12
    return saturate(y, 1.2)


@recipe
def sw_tempest_end(rng, v):
    L = 2.4
    n = n_of(L)
    t = t_axis(n)
    y = np.zeros(n)
    for i in range(14):                                           # descending battery zings
        at = rng.uniform(0.0, 1.2)
        m = n_of(0.5)
        f = rng.uniform(1800, 4200)
        place(y, fm(fsweep(m, f, f * 0.25, 0.09), 1.5, 2.0 * np.exp(-t_axis(m) / 0.1), m) * env_exp(m, 0.18, 0.001), n_of(at), 0.18)
    y += lowpass(colored_noise(n, rng, 1.0, lo=100, hi=4000), 2000) * env_exp(n, 0.5, 0.01) * 0.3
    return finish(widen(verb(saturate(y, 1.3), "plate", 0.2), 1.25), L, 0.5)


# ------------------------------------------------------------------------------------------------ DRAGONFALL (capsule foundry)
@recipe
def sw_dragonfall_launch(rng, v):
    L = 4.0
    n = n_of(L)
    t = t_axis(n)
    reentry = sweep_filter(colored_noise(n, rng, 0.6, lo=150, hi=10000), 700 + 3800 * np.clip(t / 3.2, 0, 1) ** 2, "lp", 1.0, 2, 20) * env_points(n, [(0, 0), (0.6, 0.3, 1.5), (3.2, 1.0, 2), (L - 0.05, 0, -2)])
    rum = colored_noise(n, rng, 2.0, lo=30, hi=220) * env_points(n, [(0, 0), (1.0, 0.4, 1.5), (3.2, 1.0), (L - 0.05, 0, -2)]) * 1.0
    whine = sine(500 * np.exp(-t / 1.5) + 800 * (t / L), n) * env_points(n, [(0, 0), (1.0, 0.15), (3.2, 0.4), (L - 0.05, 0, -2)])
    y = reentry * 0.9 + rum + 0.2 * lowpass(whine, 5000)
    return finish(widen(verb(saturate(y, 1.25), "hall", 0.18), 1.3), L, 0.5)


@recipe
def sw_dragonfall_loop(rng, v):
    n = n_of(T)
    y = np.zeros(n)
    for i in range(3):                                            # unfolding servo phrases
        f0 = 240 + 90 * i
        m = n_of(1.1)
        tt = t_axis(m)
        f = np.interp(tt, [0, 0.4, 0.8, 1.1], [f0, f0 * 2.6, f0 * 2.4, f0 * 1.2])
        s = lowpass(saw(f, m) * 0.5 + sine(f, m) * 0.6, 4000) * env_points(m, [(0, 0), (0.04, 1, 1), (0.95, 0.9), (1.1, 0, -3)])
        place(y, s * 0.22, int((i * 1.3) / T * n), 1.0, wrap=True)
    for i in range(7):
        place(y, burst(n_of(0.08), rng, 0.006, lo=800, hi=6000) + thump(n_of(0.08), 120, 60, 0.01, 0.03) * 0.6, int(i / 7 * n), 0.4, wrap=True)
    y += lowpass(colored_noise(n, rng, 1.0, lo=50, hi=800), 500, circ=True) * 0.1 + sine(snap_freq(70, T), n) * 0.12
    return saturate(y, 1.2)


@recipe
def sw_dragonfall_impact(rng, v):
    L = 3.0
    n = n_of(L)
    t = t_axis(n)
    k = 1.0 + 0.1 * (v - 1)
    y = thump(n, 70 * k, 26, 0.10, 0.8, drive=1.8) + burst(n, rng, 0.008, lo=300, hi=9000) * 1.1
    y += burst(n, rng, 0.05, lo=180, hi=2400) * 1.3 + modal([140 * k, 330 * k, 720 * k], [0.4, 0.28, 0.18], [0.5, 0.35, 0.2], n, rng, 0.01) * env_exp(n, 1.0, 0.0004)
    y += _debris(rng, n, 0.05, 500, 1.4) + colored_noise(n, rng, 2.0, lo=25, hi=140) * env_exp(n, 1.0, 0.01) * 0.9
    return finish(verb(saturate(y, 1.5), "hall", 0.26), L, 0.6)


@recipe
def sw_dragonfall_end(rng, v):
    L = 2.6
    n = n_of(L)
    t = t_axis(n)
    f = 700 * np.exp(-t / 0.7) + 45
    y = lowpass(saw(f, n) * 0.5 + sine(f, n), 3500) * env_points(n, [(0, 0), (0.03, 1, 1), (1.6, 0.4, -2), (2.4, 0, -2)])
    y += sine(1500 * np.exp(-t / 0.5) + 70, n) * env_exp(n, 0.5, 0.01) * 0.25
    y += modal([300, 800, 1650], [0.06, 0.04, 0.03], [0.9, 0.5, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0006, 1.9) + thump(n, 100, 46, 0.03, 0.10, delay=1.9) * 0.8
    return finish(widen(verb(saturate(y, 1.3), "hangar", 0.2), 1.25), L, 0.5)


# ------------------------------------------------------------------------------------------------ HORIZON (mass driver)
@recipe
def sw_horizon_charge(rng, v):
    n = n_of(T)
    t = t_axis(n)
    ph = (t / T * 2.0) % 1.0
    f = snap_freq(320, T)
    y = (sine(f, n) + 0.4 * sine(2 * f, n)) * (0.3 + 0.7 * ph ** 1.5) * 0.35
    y += sine(snap_freq(60, T), n) * 0.35 * (0.5 + 0.5 * ph)
    y += highpass(colored_noise(n, rng, 0.0), 5000, circ=True) * ph * 0.03
    return saturate(y, 1.2)


@recipe
def sw_horizon_launch(rng, v):
    L = 5.0
    n = n_of(L)
    t = t_axis(n)
    y = np.zeros(n)
    for i, at in enumerate((0.0, 0.5, 1.0, 1.6, 2.4)):            # rail crack barrage
        m = n - n_of(at)
        c = burst(m, rng, 0.0012, lo=3000, hi=16000, attack=0.0002) * 1.2 + thump(m, 95, 36, 0.03, 0.2, drive=1.5) + burst(m, rng, 0.03, lo=250, hi=2600) * 0.8
        c += modal([2200, 3700, 5900], [0.4, 0.28, 0.18], [0.22, 0.18, 0.12], m, rng, 0.004) * env_exp(m, 2.0, 0.0006)
        place(y, c, n_of(at), 1.0 - 0.1 * i)
    y += colored_noise(n, rng, 2.0, lo=25, hi=160) * env_exp(n, 1.6, 0.02) * 0.8
    return finish(verb(saturate(y, 1.4), "canyon", 0.3), L, 0.7)


@recipe
def sw_horizon_impact(rng, v):
    L = 4.0
    n = n_of(L)
    t = t_axis(n)
    k = 1.0 + 0.08 * (v - 1)
    y = thump(n, 78 * k, 28, 0.06, 0.6, drive=1.7) + burst(n, rng, 0.004, lo=1600, hi=15000) * 1.1 + burst(n, rng, 0.03, lo=200, hi=2800) * 1.2
    y += modal([760, 1700, 3400], [0.5, 0.3, 0.2], [0.3, 0.2, 0.12], n, rng, 0.01) * env_exp(n, 1.0, 0.0005)
    y += highpass(colored_noise(n, rng, 0.2), 3500) * env_points(n, [(0, 0), (0.3, 0.3, 1), (2.6, 0.15), (L - 0.05, 0, -2)]) * 0.5     # debris hiss
    y += _debris(rng, n, 0.1, 500, 1.6)
    return finish(verb(saturate(y, 1.5), "canyon", 0.28), L, 0.7)


# ------------------------------------------------------------------------------------------------ TRIDENT (interception dome)
@recipe
def sw_trident_launch(rng, v):
    L = 3.5
    n = n_of(L)
    t = t_axis(n)
    f = 70 + 110 * (1 - np.exp(-t / 0.9))
    hum = (sine(f, n) + 0.5 * sine(2 * f, n) + 0.25 * sine(3 * f, n)) * env_points(n, [(0, 0), (1.5, 0.9, 1.5), (L - 0.05, 0.7, 0), (L, 0)])
    shimmer = fm(snap_freq(1400, L), 2.01, 1.5 * (0.5 + 0.5 * np.sin(2 * np.pi * 4 * t)), n) * env_points(n, [(0, 0), (1.6, 0.15, 1), (L - 0.05, 0.12), (L, 0)])
    lock = thump(n, 120, 50, 0.03, 0.15, delay=0.0, drive=1.4) * 0.6 + modal([320, 800, 1700], [0.1, 0.07, 0.04], [0.7, 0.4, 0.2], n, rng, 0.01) * env_exp(n, 1.0, 0.0005)
    y = hum * 0.7 + shimmer + lock
    return finish(widen(verb(saturate(y, 1.2), "hall", 0.2), 1.3), L, 0.4)


@recipe
def sw_trident_loop(rng, v):
    n = n_of(T)
    f = snap_freq(120, T)
    hum = (sine(f, n) + 0.5 * sine(2 * f, n) + 0.25 * sine(3 * f, n) + 0.12 * sine(5 * f, n)) * (1 + 0.1 * lfo(2 / T, n))
    shim = fm(snap_freq(1400, T), 2.01, 1.5 * (0.5 + 0.5 * lfo(4 / T, n)), n) * 0.06
    air = bandpass(colored_noise(n, rng, 0.8), 400, 3000, circ=True) * 0.06
    return saturate(hum * 0.5 + shim + air, 1.15)


@recipe
def sw_trident_end(rng, v):
    L = 4.0
    n = n_of(L)
    t = t_axis(n)
    f = 190 * np.exp(-t / 1.2) + 30
    hum = (sine(f, n) + 0.5 * sine(2 * f, n)) * env_exp(n, 1.5, 0.005) * 0.7
    arcs = highpass(crackle(n, rng, 900 * np.exp(-t / 0.6) + 5), 2200) * 0.7
    crash = burst(n, rng, 0.06, lo=200, hi=6000) * 0.9 + thump(n, 80, 30, 0.08, 0.5, drive=1.6) + modal([500, 1300, 2900], [0.4, 0.3, 0.2], [0.35, 0.25, 0.15], n, rng, 0.02) * env_exp(n, 1.0, 0.001)
    glass = np.zeros(n)
    for _ in range(26):
        m = n_of(0.25)
        f0 = rng.uniform(1800, 6500)
        place(glass, modal([f0, f0 * 1.6], [0.05, 0.03], [0.4, 0.25], m, rng) * env_exp(m, 0.08), n_of(rng.uniform(0.1, 1.8)), rng.uniform(0.1, 0.35))
    y = hum + arcs + crash + glass + colored_noise(n, rng, 2.0, lo=25, hi=150) * env_exp(n, 1.3, 0.01) * 0.7
    return finish(widen(verb(saturate(y, 1.35), "hall", 0.28), 1.3), L, 0.7)
