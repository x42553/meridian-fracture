"""structures.py - base building sounds: construction complete cues, sell / repair / salvage, power up/down, unit-out cues,
hums, economy ticks.

`struct_online` = alternating hammer / servo build-up for BUILDUP s (1.5), then the accent of the building kind at
BUILDUP (audio spec 7.8b: accent at BUILDUP_SECONDS = 1.5 s, tail <= 1.5 s)."""
from __future__ import annotations

import numpy as np

from dsp import (
    SR, bandpass, colored_noise, crackle, env_exp, env_points, fm, highpass, lfo, lowpass, modal, n_of, place, saturate, saw, sine, snap_freq, square, sweep_filter, t_axis, widen)
from sfx import recipe
from sfx.kit import burst, finish, thump, verb

BUILDUP = 1.5


# ------------------------------------------------------------------------------------------------ building blocks
def hammer_hit(rng, at: float, n: int, k: float = 1.0, g: float = 1.0) -> np.ndarray:
    m = n_of(0.5)
    hit = burst(m, rng, 0.004, lo=700, hi=9000) * 0.9 + thump(m, 190 * k, 100, 0.01, 0.03) * 0.8
    hit += modal([1180 * k, 2760 * k, 4400 * k], [0.12, 0.07, 0.05], [0.5, 0.35, 0.2], m, rng, 0.01) * env_exp(m, 1.0, 0.0006)
    out = np.zeros(n)
    place(out, saturate(hit, 1.4) * g, n_of(at))
    return out


def servo_run(rng, at: float, dur: float, n: int, f0: float = 300, f1: float = 980, g: float = 1.0) -> np.ndarray:
    m = n_of(dur)
    t = t_axis(m)
    f = np.interp(t, [0, dur * 0.35, dur * 0.7, dur], [f0, f1, f1 * 0.98, f0 * 1.4]) * (1 + 0.012 * np.sin(2 * np.pi * 9 * t))
    amp = env_points(m, [(0, 0), (0.04, 1, 1), (dur - 0.15, 0.9), (dur, 0, -3)])
    mot = lowpass(saw(f, m) * 0.5 + sine(f, m) * 0.6 + 0.25 * sine(2 * f, m), 4500) * amp
    gear = bandpass(colored_noise(m, rng, 0.0), 900, 3200) * amp * 0.16
    out = np.zeros(n)
    place(out, (mot * 0.55 + gear) * g, n_of(at))
    return out


def buildup(rng, n: int, k: float) -> np.ndarray:
    """1.5 s of alternating hammer strikes and servo runs, getting denser."""
    x = np.zeros(n)
    for at, g in ((0.0, 0.85), (0.42, 0.75), (0.90, 0.85), (1.22, 0.9)):
        x += hammer_hit(rng, at + rng.uniform(0, 0.02), n, k * rng.uniform(0.96, 1.05), g)
    x += servo_run(rng, 0.20, 0.55, n, 320 * k, 900 * k, 0.55)
    x += servo_run(rng, 0.85, 0.6, n, 380 * k, 1100 * k, 0.6)
    return x


def accent(rng, kind: str, n: int, at: float) -> np.ndarray:
    m = n - n_of(at)
    t = t_axis(m)
    d = 0.0
    if kind == "generator":              # turbine spool + low hum start
        f = 90 + 1400 * (1 - np.exp(-t / 0.5))
        y = (saw(f, m) * 0.4 + sine(f, m) * 0.5) * env_points(m, [(0, 0), (0.05, 0.8, 1), (0.8, 0.5), (m / SR, 0, -2)])
        y = lowpass(y, 3500) + sine(50, m) * env_points(m, [(0, 0), (0.3, 0.7, 1), (m / SR, 0.3)]) * 0.5
    elif kind == "refinery":             # clank + two chugs
        y = modal([420, 980, 1900], [0.2, 0.12, 0.07], [0.7, 0.45, 0.25], m, rng, 0.01) * env_exp(m, 1.0, 0.0005)
        for c in (0.22, 0.52):
            y += thump(m, 90, 45, 0.03, 0.08, delay=c, drive=1.3) * 0.8 + burst(m, rng, 0.06, lo=200, hi=1800, delay=c) * 0.4
    elif kind == "barracks":             # door slam + latch
        y = thump(m, 120, 50, 0.03, 0.14, drive=1.5) + burst(m, rng, 0.03, lo=250, hi=3500) * 0.9
        y += modal([330, 760, 1500], [0.09, 0.06, 0.04], [0.8, 0.5, 0.3], m, rng, 0.01) * env_exp(m, 1.0, 0.0005, 0.02)
        y += modal([2400, 3600], [0.02, 0.014], [0.5, 0.3], m, rng) * env_exp(m, 1.0, 0.0003, 0.28)
    elif kind == "factory":              # heavy doors sliding + slam
        y = bandpass(colored_noise(m, rng, 1.0), 120, 900) * env_points(m, [(0, 0), (0.1, 0.8, 1), (0.6, 0.8), (0.75, 0, -2)]) * 0.7
        y += thump(m, 100, 38, 0.04, 0.3, delay=0.7, drive=1.6) + burst(m, rng, 0.04, lo=200, hi=3000, delay=0.7) * 0.8
        y += modal([200, 510, 1100], [0.25, 0.15, 0.1], [0.5, 0.35, 0.2], m, rng, 0.01) * env_exp(m, 1.0, 0.0006, 0.7)
    elif kind == "dock":                 # ship horn: two low tones
        y = (saw(110, m) * 0.4 + sine(110, m) + sine(55, m) * 0.5)
        y = lowpass(y, 900, 4) * env_points(m, [(0, 0), (0.06, 1, 1), (0.6, 0.9), (0.75, 0, -3)])
        y2 = (saw(147, m) * 0.4 + sine(147, m)) * env_points(m, [(0, 0), (0.6, 0), (0.66, 1, 1), (1.3, 0.9), (1.5, 0, -3)])
        y = y + lowpass(y2, 1100, 4)
    elif kind == "radar":                # spin-up whir + ping
        f = 120 + 900 * (1 - np.exp(-t / 0.5))
        y = (saw(f, m) * 0.3 + sine(f, m)) * env_points(m, [(0, 0), (0.1, 0.6, 1), (1.0, 0.4), (1.4, 0, -2)]) * 0.5
        y += (sine(1180, m) + 0.15 * sine(2360, m)) * env_exp(m, 0.3, 0.006, 0.55)
    elif kind == "airfield":             # three beacon beeps
        y = np.zeros(m)
        for i in range(3):
            b = (square(1040, m) * 0.4 + sine(1040, m)) * env_points(m, [(0, 0), (0.005, 1), (0.09, 0.9), (0.12, 0)])
            place(y, lowpass(b, 4500)[: n_of(0.14)], n_of(0.05 + i * 0.22))
    elif kind == "laboratory":           # hum-up + shimmer
        f = 70 + 130 * (1 - np.exp(-t / 0.6))
        y = (sine(f, m) + 0.5 * sine(2 * f, m) + 0.25 * sine(3 * f, m)) * env_points(m, [(0, 0), (0.6, 0.9, 1.5), (1.4, 0.6), (m / SR, 0, -2)])
        y += fm(1500, 2.01, 1.5 * (0.5 + 0.5 * np.sin(2 * np.pi * 5 * t)), m) * env_points(m, [(0, 0), (0.5, 0.15, 1), (1.4, 0.15), (m / SR, 0, -2)])
    elif kind in ("watchtower", "turret", "aa_battery"):     # servo whir + lock click (different pitch)
        base = {"watchtower": 380, "turret": 260, "aa_battery": 620}[kind]
        f = np.interp(t, [0, 0.3, 0.6], [base, base * 2.2, base * 1.8])
        y = lowpass(saw(f, m) * 0.5 + sine(f, m), 3500) * env_points(m, [(0, 0), (0.03, 1, 1), (0.5, 0.8), (0.62, 0, -3)]) * 0.6
        y += modal([base * 3.1, base * 5.2], [0.02, 0.014], [0.6, 0.3], m, rng) * env_exp(m, 1.0, 0.0003, 0.6) + thump(m, 130, 65, 0.02, 0.06, delay=0.6) * 0.6
    elif kind == "relay":                # antenna deploy: telescoping rasp + ping
        y = bandpass(colored_noise(m, rng, 0.3), 1400, 5200) * (0.6 + 0.4 * np.sin(2 * np.pi * 26 * t)) * env_points(m, [(0, 0), (0.05, 0.7), (0.7, 0.7), (0.8, 0, -2)]) * 0.5
        y += (sine(1760, m) + 0.3 * sine(3520, m)) * env_exp(m, 0.4, 0.004, 0.75) * 0.6
    elif kind == "hq":                   # fanfare: metal strike + bell chord
        y = modal([260, 520, 1040, 2080], [0.5, 0.4, 0.3, 0.2], [0.6, 0.5, 0.4, 0.3], m, rng, 0.004) * env_exp(m, 1.0, 0.0006)
        for f in (392.0, 523.3, 659.3):
            y += fm(f, 3.5, 2.2 * np.exp(-t / 0.4), m) * env_exp(m, 0.7, 0.003, 0.06) * 0.35
        y += burst(m, rng, 0.02, lo=400, hi=6000) * 0.6 + thump(m, 110, 48, 0.03, 0.16, drive=1.4)
    elif kind == "superweapon":          # deep engine start
        f = 38 + 60 * (1 - np.exp(-t / 0.8))
        y = (saw(f, m) * 0.5 + sine(f, m)) * env_points(m, [(0, 0), (0.6, 0.9, 1.5), (1.6, 0.7), (m / SR, 0, -2)])
        y = lowpass(y, 500, 4) + lowpass(colored_noise(m, rng, 1.5, lo=30, hi=400), 350) * env_points(m, [(0, 0), (0.5, 0.5, 1.5), (1.4, 0.4), (m / SR, 0, -2)])
    elif kind == "adv_defense":          # shield-like charge + servo lock
        f = 300 + 1500 * (1 - np.exp(-t / 0.35))
        y = (sine(f, m) + 0.3 * sine(2 * f, m)) * env_points(m, [(0, 0), (0.4, 0.8, 1.5), (0.52, 0)])
        y += (sine(233, m) + 0.6 * sine(466, m)) * env_points(m, [(0, 0), (0.5, 0.0), (0.56, 0.9, 1), (1.3, 0.4), (m / SR, 0, -2)]) * 0.5
        y += thump(m, 140, 60, 0.02, 0.07, delay=0.5) * 0.7
    else:
        raise ValueError(kind)
    out = np.zeros(n)
    place(out, y, n_of(at))
    return out


_KIND_K = {"hq": 1.0, "generator": 0.9, "refinery": 0.85, "barracks": 1.1, "factory": 0.8, "dock": 0.9, "radar": 1.15, "airfield": 1.0,
           "laboratory": 1.2, "watchtower": 1.05, "turret": 1.0, "aa_battery": 1.1, "relay": 1.25, "superweapon": 0.75, "adv_defense": 1.1}


@recipe
def struct_online(rng, v, kind="generator"):
    """Construction complete: 1.5 s build-up, then the accent of the structure kind (tail <= 1.5 s)."""
    L = 2.9 if kind in ("hq", "superweapon", "factory") else 2.6
    n = n_of(L)
    x = buildup(rng, n, _KIND_K[kind]) + accent(rng, kind, n, BUILDUP)
    x = saturate(x, 1.25)
    return finish(widen(verb(x, "hangar", 0.16), 1.15), L, 0.35)


@recipe
def struct_sell(rng, v):
    """Sell: winch cranking down, a clunk, and a coin jingle."""
    L = 2.0
    n = n_of(L)
    t = t_axis(n)
    f = np.interp(t, [0, 1.1], [900, 250])
    crank = lowpass(saw(f, n) * 0.4 + square(f * 0.5, n) * 0.2, 3000) * env_points(n, [(0, 0), (0.04, 1, 1), (1.0, 0.8), (1.15, 0, -3)]) * 0.7
    ticks = np.zeros(n)
    for i in range(14):
        place(ticks, burst(n_of(0.02), rng, 0.003, lo=1500, hi=7000), n_of(0.02 + i * 0.075), 0.5)
    clunk = thump(n, 120, 55, 0.02, 0.07, delay=1.15) * 0.9 + modal([310, 780], [0.06, 0.04], [0.7, 0.4], n, rng, 0.01) * env_exp(n, 1.0, 0.0005, 1.15)
    coins = np.zeros(n)
    for i, f0 in enumerate((2450, 3100, 3900)):
        place(coins, modal([f0, f0 * 1.63, f0 * 2.5], [0.09, 0.06, 0.04], [1.0, 0.6, 0.3], n_of(0.4), rng, 0.004), n_of(1.2 + i * 0.1), 0.6)
    x = saturate(crank + ticks + clunk + coins, 1.3)
    return finish(widen(verb(x, "room", 0.14), 1.15), L, 0.3)


@recipe
def struct_repair(rng, v):
    """Repair loop: ratcheting wrench pulses over a rising-falling motor whirr."""
    T = 3.0
    n = n_of(T)
    t = t_axis(n)
    f = snap_freq(360, T) * (1 + 0.5 * (0.5 - 0.5 * np.cos(2 * np.pi * t / T)))
    motor = lowpass(saw(f, n) * 0.4 + sine(f, n), 3500, 2, circ=True) * 0.35
    rat = np.zeros(n)
    for i in range(18):
        place(rat, burst(n_of(0.05), rng, 0.005, lo=900, hi=6000) + modal([2200, 3400], [0.012, 0.008], [0.4, 0.3], n_of(0.05), rng), int(i / 18 * n), 0.6 + 0.2 * (i % 3), wrap=True)
    hiss = bandpass(colored_noise(n, rng, 0.5), 1500, 6000, circ=True) * 0.05
    return saturate(motor + rat * 0.7 + hiss, 1.2)


@recipe
def struct_salvage(rng, v):
    """Salvage loop: cutting torch hiss, crunching metal and clanks."""
    T = 3.0
    n = n_of(T)
    torch = bandpass(colored_noise(n, rng, 0.2), 1800, 9000, circ=True) * (0.7 + 0.3 * lfo(snap_freq(11, T), n)) * 0.28
    crunch = np.zeros(n)
    for i in range(9):
        m = n_of(0.18)
        c = bandpass(colored_noise(m, rng, 0.0), rng.uniform(300, 1200), rng.uniform(2200, 5200)) * env_exp(m, rng.uniform(0.03, 0.09), 0.001)
        c += modal([rng.uniform(500, 2400)], [0.08], [0.5], m, rng) * env_exp(m, 0.08)
        place(crunch, c, int(i / 9 * n + rng.normal(0, 800)), rng.uniform(0.4, 0.9), wrap=True)
    spark = highpass(crackle(n, rng, 250), 3500) * 0.4
    motor = sine(snap_freq(95, T), n) * 0.08
    return saturate(torch + crunch * 0.6 + spark + motor, 1.25)


@recipe
def power_down(rng, v):
    """Frequency-collapsing hum, closing low-pass, falling whine, relay clunk (spike reference)."""
    n = n_of(2.6)
    t = t_axis(n)
    fh = 100 * np.exp(-t / 1.1) + 26
    hum = (saw(fh, n) * 0.5 + sine(fh / 2, n) * 0.6)
    hum = sweep_filter(hum, 3000 * np.exp(-t / 0.7) + 120, "lp", 0.9, 2, 20) * env_points(n, [(0, 0), (0.02, 1, 1), (1.6, 0.35, -2), (2.2, 0.0, -2)])
    whine = sine(1600 * np.exp(-t / 0.5) + 70, n) * env_exp(n, 0.5, 0.01) * 0.28
    relay = modal([310, 830, 1700], [0.06, 0.05, 0.03], [0.9, 0.5, 0.25], n, rng, 0.01) * env_exp(n, 1.0, 0.0006, 2.05) + thump(n, 110, 55, 0.02, 0.05, delay=2.05) * 0.8
    return finish(widen(verb(saturate(hum + whine + relay, 1.3), "hangar", 0.18), 1.2), 2.6, 0.3)


@recipe
def power_up(rng, v):
    """Capacitor-charge sweep, opening filter, relay slam, stable 100 Hz hum (spike reference)."""
    n = n_of(3.0)
    t = t_axis(n)
    tc = 1.8
    ph = np.clip(t / tc, 0, 1)
    fu = 60 + 1500 * ph ** 2.2
    charge = (saw(fu, n) * 0.5 + sine(fu, n)) * env_points(n, [(0, 0), (tc, 1, 2.5), (tc + 0.02, 0)])
    charge = sweep_filter(charge, 150 + 6000 * ph ** 2, "lp", 1.0, 2, 20)
    relay = modal([340, 900, 1900], [0.07, 0.05, 0.03], [0.9, 0.55, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0006, tc) + thump(n, 120, 50, 0.02, 0.07, delay=tc) * 0.9
    spark = highpass(crackle(n, rng, 500 * np.exp(-np.maximum(t - tc, 0) / 0.15) * (t > tc)), 2500) * 0.7
    hold = (saw(100, n) * 0.3 + sine(50, n) * 0.5 + sine(200, n) * 0.15) * env_points(n, [(0, 0), (tc, 0), (tc + 0.05, 1, 1), (2.7, 0.8), (3.0, 0, -3)])
    return finish(widen(verb(saturate(0.7 * charge + relay + spark + 0.8 * hold, 1.3), "hangar", 0.18), 1.2), 3.0, 0.3)


@recipe
def defense_offline(rng, v):
    """Defence structure loses power: a fast winding-down whine, a servo droop, a dull relay click."""
    L = 1.6
    n = n_of(L)
    t = t_axis(n)
    whine = (saw(700 * np.exp(-t / 0.35) + 60, n) * 0.4 + sine(700 * np.exp(-t / 0.35) + 60, n)) * env_exp(n, 0.4, 0.004)
    whine = lowpass(whine, 2500)
    droop = thump(n, 90, 40, 0.06, 0.20, delay=0.05, drive=1.3) * 0.8
    click = modal([420, 1200], [0.04, 0.025], [0.8, 0.4], n, rng, 0.01) * env_exp(n, 1.0, 0.0005, 0.85) + burst(n, rng, 0.008, lo=500, hi=4000, delay=0.85) * 0.5
    return finish(widen(verb(saturate(whine * 0.7 + droop + click, 1.3), "room", 0.14), 1.1), L, 0.3)


@recipe
def unit_out(rng, v, kind="infantry"):
    """A unit leaves its production structure: door / ramp / rollout cues per unit class."""
    L = 1.9 if kind != "aircraft" else 2.4
    n = n_of(L)
    t = t_axis(n)
    if kind == "infantry":       # hatch hiss + boots
        y = burst(n, rng, 0.12, lo=1500, hi=9000) * 0.5
        for i, at in enumerate((0.25, 0.55, 0.85)):
            y += (burst(n, rng, 0.03, lo=150, hi=1400, exponent=0.5) + 0.7 * thump(n, 110, 60, 0.012, 0.05)) * 0.8 * env_exp(n, 1.0, 0.0004, at)
        y += modal([690, 1400], [0.05, 0.03], [0.5, 0.3], n, rng) * env_exp(n, 1.0, 0.0004)
    elif kind == "vehicle":      # ramp lowering + engine catch
        y = bandpass(colored_noise(n, rng, 1.0), 150, 1200) * env_points(n, [(0, 0), (0.08, 0.7), (0.6, 0.7), (0.72, 0, -2)]) * 0.5
        y += thump(n, 100, 40, 0.03, 0.18, delay=0.65, drive=1.5) + modal([250, 640], [0.1, 0.06], [0.8, 0.4], n, rng) * env_exp(n, 1.0, 0.0005, 0.65)
        f = 60 + 40 * (1 - np.exp(-np.maximum(t - 0.8, 0) / 0.2))
        y += lowpass(saw(f, n) + sine(f, n), 500) * env_points(n, [(0, 0), (0.8, 0), (0.9, 0.5, 1), (1.6, 0.5), (1.85, 0, -2)]) * 0.5
    elif kind == "aircraft":     # hangar door + turbine idle
        y = bandpass(colored_noise(n, rng, 1.0), 100, 700) * env_points(n, [(0, 0), (0.1, 0.8), (0.8, 0.8), (0.95, 0, -2)]) * 0.5
        f = 200 + 700 * (1 - np.exp(-np.maximum(t - 0.9, 0) / 0.6))
        y += (sine(f, n) + 0.4 * sine(2 * f, n)) * env_points(n, [(0, 0), (0.9, 0), (1.1, 0.4, 1), (2.1, 0.3), (2.4, 0, -2)]) * 0.3
        y += thump(n, 90, 40, 0.04, 0.2, delay=0.95, drive=1.3)
    else:                        # ship: dock horn + splash
        y = (saw(98, n) * 0.4 + sine(98, n)) * env_points(n, [(0, 0), (0.05, 1, 1), (0.6, 0.9), (0.8, 0, -3)])
        y = lowpass(y, 800, 4) * 0.8 + burst(n, rng, 0.2, lo=300, hi=6000, delay=0.85) * 0.6 + thump(n, 80, 40, 0.05, 0.2, delay=0.85) * 0.6
    return finish(widen(verb(saturate(y, 1.25), "hangar", 0.16), 1.15), L, 0.3)


@recipe
def struct_captured(rng, v):
    """Capture: a rising three-note motif with a flag snap."""
    L = 1.8
    n = n_of(L)
    y = np.zeros(n)
    for i, f in enumerate((392.0, 523.3, 784.0)):
        m = n - n_of(0.12 * i)
        t = t_axis(m)
        y[n_of(0.12 * i):] += fm(f, 2.0, 2.0 * np.exp(-t / 0.15), m) * env_exp(m, 0.35, 0.003) * (0.7 + 0.15 * i)
    snap = burst(n, rng, 0.03, lo=800, hi=7000) * 0.6 + thump(n, 130, 60, 0.02, 0.07) * 0.6
    return finish(widen(verb(saturate(y * 0.7 + snap, 1.25), "plate", 0.2), 1.2), L, 0.3)


@recipe
def hq_deploy(rng, v):
    """Headquarters deploys: unfolding servos, clanking locks, a short fanfare."""
    L = 3.4
    n = n_of(L)
    x = np.zeros(n)
    for a, d, f0, f1 in ((0.0, 0.7, 200, 700), (0.75, 0.7, 300, 950), (1.5, 0.6, 250, 800)):
        x += servo_run(rng, a, d, n, f0, f1, 0.7)
    for at in (0.7, 1.45, 2.1):
        x += hammer_hit(rng, at, n, 0.9, 0.8)
    x += accent(rng, "hq", n, 2.1)
    return finish(widen(verb(saturate(x, 1.25), "hangar", 0.2), 1.2), L, 0.5)


@recipe
def struct_hum(rng, v, kind="generator"):
    """Tonal structure bed, locked to whole cycles: generator 100 Hz drone, radar sweep tick, lab shimmer, airfield beacon
    tick, refinery churn."""
    T = 4.0
    n = n_of(T)
    t = t_axis(n)
    if kind == "generator":
        f = snap_freq(100, T)
        y = (saw(f, n) * 0.25 + sine(f, n) * 0.6 + sine(f / 2, n) * 0.5 + sine(2 * f, n) * 0.15) * (1 + 0.05 * lfo(2 / T, n))
        y = lowpass(y, 1400, 4, circ=True)
    elif kind == "radar":
        y = sine(snap_freq(220, T), n) * 0.25 + bandpass(colored_noise(n, rng, 0.5), 1500, 4500, circ=True) * 0.15
        ph = (t / T * 2.0) % 1.0                          # two sweeps per loop
        y *= 0.5 + 0.5 * np.exp(-((ph - 0.5) / 0.12) ** 2)
        y += (sine(snap_freq(1180, T), n) * np.exp(-((ph - 0.5) / 0.02) ** 2)) * 0.25
    elif kind == "lab":
        y = sum(sine(snap_freq(f, T), n, 0.13 * i) * a for i, (f, a) in enumerate(((72, 0.6), (144, 0.3), (432, 0.1), (1280, 0.03))))
        y = y * (1 + 0.12 * lfo(3 / T, n)) + fm(snap_freq(1500, T), 2.0, 1.2 + lfo(2 / T, n), n) * 0.025
    elif kind == "airfield":
        y = sine(snap_freq(60, T), n) * 0.3 + lowpass(colored_noise(n, rng, 1.0, lo=60, hi=2000), 900, circ=True) * 0.12
        b = np.exp(-(((t / T * 2.0) % 1.0) / 0.03)) * 0.6
        y += sine(snap_freq(1040, T), n) * b * 0.25
    else:  # refinery
        y = np.zeros(n)
        m = n_of(0.2)
        chug = thump(m, 85, 42, 0.03, 0.06) + burst(m, rng, 0.03, lo=150, hi=1200) * 0.5
        y = _wrap_pulses(n, chug, 6, T)
        y = lowpass(y, 700, 4, circ=True) + bandpass(colored_noise(n, rng, 0.8), 200, 2000, circ=True) * 0.08 + sine(snap_freq(55, T), n) * 0.2
    return saturate(y, 1.2)


def _wrap_pulses(n: int, pulse: np.ndarray, count: int, T: float) -> np.ndarray:
    x = np.zeros(n)
    for i in range(count):
        place(x, pulse, int(i / count * n), 1.0, wrap=True)
    return x


# ------------------------------------------------------------------------------------------------ economy
@recipe
def cash_tick(rng, v):
    """Metallic coin tick (spike reference)."""
    n = n_of(0.30)
    f = 1.0 + 0.05 * (v - 1)
    x = modal([2450 * f, 4020 * f, 6100 * f], [0.05, 0.035, 0.02], [1.0, 0.6, 0.3], n, rng, 0.004) + burst(n, rng, 0.0015, lo=3000, hi=12000) * 0.5
    return finish(x, 0.30, 0.06)


@recipe
def cash_big(rng, v):
    """Three-coin flourish: a rising coin cascade with a small register ring."""
    n = n_of(1.2)
    y = np.zeros(n)
    for i, f in enumerate((2450, 3100, 3900)):
        m = n_of(0.45)
        c = modal([f, f * 1.63, f * 2.5], [0.09, 0.06, 0.04], [1.0, 0.6, 0.3], m, rng, 0.004) + burst(m, rng, 0.0015, lo=3000, hi=12000) * 0.5
        place(y, c, n_of(0.07 * i), 0.8)
    ring = modal([1568, 2093, 3136], [0.35, 0.28, 0.2], [0.35, 0.3, 0.2], n, rng, 0.002) * env_exp(n, 1.0, 0.001, 0.2)
    return finish(widen(verb(y + ring, "plate", 0.16), 1.2), 1.2, 0.3)
