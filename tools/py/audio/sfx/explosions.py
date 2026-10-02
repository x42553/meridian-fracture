"""explosions.py - explosions by size (land and water), building collapses by footprint, unit deaths.

One size-parameterised blast (spike explosion_small/large generalised): crack -> sweep-filtered fireball roar -> sub
thump -> secondary pop -> debris rain -> rumble.  Every explosion starts with a real transient (attack <= 12 ms) so
it reads instantly; the sub is centred and the LF is mono-compatible."""
from __future__ import annotations

import numpy as np

from dsp import (
    bandpass, colored_noise, crackle, env_exp, env_points, highpass, lowpass, modal, n_of, place, saturate, saw, sine, sweep_filter, t_axis, widen)
from sfx import recipe
from sfx.kit import burst, finish, fsweep, thump, verb

# size index -> (length s, fireball cutoff Hz, roar tau, sub f0, sub f1, sub tau, body LP, debris density, debris tau, rumble tau, reverb)
_SIZES = {
    "small": (2.6, 9000.0, 0.22, 135.0, 44.0, 0.16, 240.0, 500.0, 0.9, 0.0, "hall"),
    "medium": (3.4, 8000.0, 0.34, 100.0, 34.0, 0.45, 280.0, 620.0, 1.2, 1.0, "hall"),
    "large": (5.2, 6500.0, 0.55, 62.0, 20.0, 0.95, 300.0, 700.0, 1.6, 1.7, "canyon"),
    "huge": (7.0, 5200.0, 0.85, 50.0, 17.0, 1.40, 340.0, 800.0, 2.4, 2.6, "canyon"),
}


@recipe
def explosion(rng, v, size="small"):
    L, sw, tau, f0, f1, stau, blp, dens, dtau, rtau, room = _SIZES[size]
    n = n_of(L)
    t = t_axis(n)
    k = 1.0 + 0.06 * (v - 1)
    crack = burst(n, rng, 0.005 if size != "small" else 0.004, lo=1200, hi=15000) * 0.95
    roar = sweep_filter(colored_noise(n, rng, 0.6, lo=90, hi=8000), sw * np.exp(-t / tau) + 260, "lp", 0.8, 2, 20)
    roar *= env_points(n, [(0, 0), (0.004, 1), (tau * 1.0, 0.8, -2), (tau * 4.5, 0.0, -3)])
    sub = thump(n, f0 * k, f1, 0.05 if size == "small" else 0.3, stau, drive=1.7)
    body = lowpass(colored_noise(n, rng, 0.0), blp, 4) * env_exp(n, tau * 0.9)
    mid = burst(n, rng, tau * 0.25, lo=250, hi=2400) * 0.9                  # keeps the boom audible on small speakers
    x = crack + roar + 1.05 * sub + 0.9 * body + mid
    pop_at = 0.34 if size != "small" else 0.0
    if pop_at:                                                               # secondary detonation
        x = x + thump(n, 95 * k, 38, 0.08, 0.25, delay=pop_at, drive=1.5) * 0.55 + burst(n, rng, 0.05, lo=200, hi=2200, delay=pop_at) * 0.35
    if size == "huge":
        x = x + thump(n, 34, 17, 0.4, 1.6, delay=0.05, drive=1.2) * 0.9      # 28 Hz-class boom
        for d, g in ((1.1, 0.5), (1.9, 0.35)):
            x = x + thump(n, 70, 28, 0.1, 0.4, delay=d, drive=1.5) * g + burst(n, rng, 0.08, lo=150, hi=1800, delay=d) * g * 0.5
    x = x + highpass(lowpass(crackle(n, rng, dens * np.exp(-t / (dtau * 0.6)) + 12), 6500), 1000) * 0.45 * env_exp(n, dtau, 0.05, 0.15)
    if rtau:
        x = x + colored_noise(n, rng, 2.0, lo=22, hi=140) * env_exp(n, rtau, 0.02) * 1.2
    x = saturate(x, 1.5)
    return finish(widen(verb(x, room, 0.30), 1.3), L, min(0.9, L * 0.15))


@recipe
def explosion_water(rng, v, size="small"):
    """Underwater/surface blast: a sharp thump, a splash burst, a low-passed water column that collapses back."""
    L, s = {"small": (2.2, 0.7), "medium": (3.0, 1.0), "large": (4.2, 1.5)}[size]
    n = n_of(L)
    t = t_axis(n)
    crack = burst(n, rng, 0.006, lo=700, hi=12000) * 1.5
    thump_ = thump(n, 90 / s ** 0.5, 30, 0.06, 0.25 * s, drive=1.6)
    splash = burst(n, rng, 0.10 * s, lo=400, hi=9000, delay=0.02) * 0.9
    col = sweep_filter(colored_noise(n, rng, 1.0, lo=70, hi=2400), 600 + 900 * np.exp(-t / (0.5 * s)), "lp", 0.7071, 2, 14)
    col *= env_points(n, [(0, 0), (0.03, 0.0), (0.16 * s + 0.06, 0.9, 1.5), (0.7 * s + 0.3, 0.55), (L - 0.4, 0.0, -2.5)])
    foam = highpass(colored_noise(n, rng, 0.0), 3200) * env_points(n, [(0, 0), (0.2, 0.0), (0.4 * s + 0.2, 0.3, 1), (L - 0.3, 0.0, -2)]) * 0.5
    rain = highpass(crackle(n, rng, 350 * np.exp(-t / (0.6 * s)) + 10), 800) * 0.5 * env_exp(n, 0.9 * s, 0.05, 0.25)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=150) * env_exp(n, 0.7 * s, 0.01) * 1.0
    x = saturate(crack + 1.0 * thump_ + splash + col * 1.1 + foam + rain + rumble, 1.4)
    return finish(widen(verb(x, "water", 0.28), 1.25), L, 0.5)


@recipe
def building_collapse(rng, v, scale=1.0):
    """Structure failure: detonating first crack, rumble swell, groaning steel, random debris crashes, dust hiss, settle."""
    L = float(np.clip(3.0 + 1.7 * (scale - 1.0), 3.0, 8.0))       # 3 / 4.7 / 6.4 / 8 s (QA window for collapses: 1.5-8 s)
    n = n_of(L)
    t = t_axis(n)
    first = burst(n, rng, 0.008, lo=250, hi=9000) * 1.2 + thump(n, 85, 30, 0.05, 0.35, drive=1.6) * 1.0
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=180) * env_points(n, [(0, 0), (0.08, 0.8, 1), (0.6, 1.0, 1.5), (L * 0.5, 0.85), (L - 0.4, 0.0, -2)]) * 1.2
    groan = lowpass(saw(fsweep(n, 95, 48, 1.4), n), 320, 4) * env_points(n, [(0, 0), (0.3, 0.35), (2.2, 0.2), (L * 0.42, 0, -2)])
    x = first + rumble + groan
    for _ in range(int(9 * scale)):                                          # structural cracks
        at = rng.uniform(0.05, 1.8 * scale)
        m = n_of(0.25)
        cr = burst(m, rng, 0.006, lo=700, hi=9000) + modal(rng.uniform(300, 1800, 3), [0.05, 0.04, 0.03], [0.7, 0.5, 0.3], m, rng) * env_exp(m, 0.05)
        place(x, cr * rng.uniform(0.5, 1.0), n_of(at))
    for _ in range(int(55 * scale)):                                         # debris crashes, density falling over time
        at = rng.uniform(0.6, L - 1.2)
        if rng.random() > np.exp(-(at - 0.6) / (3.0 * scale ** 0.5)):
            continue
        m = n_of(0.35)
        fc = rng.uniform(300, 3800)
        cr = bandpass(colored_noise(m, rng, 0.0), fc * 0.7, fc * 1.5) * env_exp(m, rng.uniform(0.03, 0.16), 0.001)
        cr += 0.4 * modal([fc, fc * 2.3], [0.06, 0.04], [0.5, 0.3], m, rng, 0.02) * env_exp(m, 0.1)
        place(x, cr * rng.uniform(0.3, 1.0) * 0.5, n_of(at))
    dust = highpass(colored_noise(n, rng, 1.0), 1800) * env_points(n, [(0, 0), (1.0, 0.12, 1), (L * 0.55, 0.08), (L - 0.2, 0.0, -1)])
    x = x + dust
    x = x + thump(n, 80, 35, 0.05, 0.3, delay=L * 0.5, drive=1.4) * 0.6 + burst(n, rng, 0.08, lo=150, hi=1800, delay=L * 0.5) * 0.4   # settle
    x = saturate(x, 1.3)
    return finish(widen(verb(x, "hall", 0.24), 1.3), L, 0.7)


# ------------------------------------------------------------------------------------------------ deaths
@recipe
def infantry_fall(rng, v):
    """Soft body thud with a gear rattle and a puff of dust (no gore)."""
    n = n_of(0.6)
    k = 1.0 + 0.1 * (v - 1)
    thud = thump(n, 130 * k, 58, 0.025, 0.09) * 1.0
    body = burst(n, rng, 0.05, lo=120, hi=1100 * k, exponent=0.4) * 1.0
    gear = np.zeros(n)
    for i in range(6):
        m = n_of(0.05)
        g = modal([rng.uniform(1600, 4200), rng.uniform(2600, 6000)], [0.012, 0.008], [0.4, 0.25], m, rng) * env_exp(m, 0.02, 0.0005)
        place(gear, g, n_of(0.02 + i * 0.03 + rng.uniform(0, 0.03)), rng.uniform(0.15, 0.4))
    dust = burst(n, rng, 0.12, lo=800, hi=5000, delay=0.03) * 0.18
    return finish(saturate(thud + body + gear + dust, 1.2), 0.6, 0.12)


@recipe
def decoy_pop(rng, v):
    """Decoy expiry: a small deflating pop and a fizzle."""
    n = n_of(0.5)
    t = t_axis(n)
    pop = burst(n, rng, 0.012, lo=300, hi=6000) * 1.0 + thump(n, 240, 90, 0.015, 0.05) * 0.7
    fizz = sine(fsweep(n, 1800, 300, 0.10), n) * env_exp(n, 0.16, 0.002, 0.02) * 0.3 + highpass(crackle(n, rng, 500 * np.exp(-t / 0.12) + 5), 2500) * 0.5
    return finish(saturate(pop + fizz, 1.3), 0.5, 0.1)


@recipe
def ship_sink(rng, v):
    """Hull failure: metal groans, a rush of water, rising bubbling, the last gurgle."""
    L = 5.0
    n = n_of(L)
    t = t_axis(n)
    hit = burst(n, rng, 0.02, lo=150, hi=4000) * 0.9 + thump(n, 80, 30, 0.06, 0.40, drive=1.6)
    groan = lowpass(saw(fsweep(n, 130, 52, 1.6) * (1 + 0.02 * np.sin(2 * np.pi * 3.1 * t)), n), 520, 4) * env_points(n, [(0, 0), (0.2, 0.4, 1), (2.6, 0.3), (3.6, 0.0, -2)])
    creak = modal([340, 720, 1330], [0.5, 0.4, 0.3], [0.2, 0.15, 0.1], n, rng, 0.03) * env_exp(n, 1.5, 0.05, 0.8) * (1 + 0.5 * np.sin(2 * np.pi * 5.5 * t))
    rush = sweep_filter(colored_noise(n, rng, 1.0, lo=80, hi=3500), 1800 * np.exp(-t / 2.6) + 300, "lp", 0.7071, 2, 14) * env_points(n, [(0, 0), (0.15, 0.9, 1), (2.4, 0.6), (4.6, 0.0, -2)])
    bub = highpass(lowpass(crackle(n, rng, 260 * (1 - np.exp(-t / 0.6)) * np.exp(-t / 2.4) + 4), 3000), 250) * 0.7
    x = saturate(hit + groan * 0.7 + creak + rush * 0.9 + bub, 1.3)
    return finish(widen(verb(x, "water", 0.3), 1.2), L, 0.9)


@recipe
def sub_implode(rng, v):
    """Pressure-hull implosion: a dull heavy thump, creaking metal, a bubbling collapse."""
    L = 3.2
    n = n_of(L)
    t = t_axis(n)
    thump_ = thump(n, 70, 24, 0.10, 0.50, drive=1.8)
    crush = burst(n, rng, 0.05, lo=120, hi=2600) * 1.1
    creak = modal([220, 470, 990], [0.4, 0.3, 0.2], [0.35, 0.25, 0.15], n, rng, 0.03) * env_exp(n, 1.2, 0.01) * (1 + 0.6 * np.sin(2 * np.pi * 9 * t))
    bub = highpass(lowpass(crackle(n, rng, 360 * np.exp(-t / 1.2) + 4), 2600), 250) * 0.7
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=130) * env_exp(n, 0.9, 0.005)
    x = saturate(1.1 * thump_ + crush + 0.5 * creak + bub + 0.8 * rumble, 1.5)
    return finish(verb(x, "water", 0.3), L, 0.6)


@recipe
def drone_pop(rng, v):
    """Drone shot down: a small electric pop, a falling buzz."""
    n = n_of(0.7)
    t = t_axis(n)
    pop = burst(n, rng, 0.008, lo=600, hi=9000) * 1.0 + thump(n, 210, 80, 0.015, 0.05) * 0.6
    buzz = lowpass(saw(fsweep(n, 900, 90, 0.22), n), 2500) * env_exp(n, 0.20, 0.001, 0.02) * 0.45
    sparks = highpass(crackle(n, rng, 600 * np.exp(-t / 0.15) + 5), 2600) * 0.6
    return finish(saturate(pop + buzz + sparks, 1.4), 0.7, 0.15)
