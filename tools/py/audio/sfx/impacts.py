"""impacts.py - bullet impacts by surface, energy / rail / kinetic / EMP hits, interception pops.
All short, all positional (mono), no reverb wash: an impact must read instantly and cheaply."""
from __future__ import annotations

import numpy as np

from dsp import (
    colored_noise, crackle, env_exp, fm, highpass, lowpass, modal, n_of, place, saturate, sine, t_axis)
from sfx import recipe
from sfx.kit import burst, finish, fsweep, thump, verb


@recipe
def bullet_dirt(rng, v):
    n = n_of(0.45)
    t = t_axis(n)
    k = 1.0 + 0.1 * (v - 1)
    puff = burst(n, rng, 0.05, lo=300, hi=3000 * k) * 1.0
    thud = thump(n, 130 * k, 62, 0.012, 0.05) * 0.8
    grain = highpass(crackle(n, rng, 900 * np.exp(-t / 0.08) + 20), 1500) * 0.6
    return finish(saturate(puff + thud + grain, 1.3), 0.45, 0.1)


@recipe
def bullet_concrete(rng, v):
    n = n_of(0.5)
    k = 1.0 + 0.12 * (v - 1)
    crack = burst(n, rng, 0.0035, lo=2000, hi=8000) * 1.2
    chips = modal(rng.uniform(1200, 4000, 4) * k, rng.uniform(0.02, 0.06, 4), [0.5, 0.4, 0.3, 0.25], n, rng, 0.01) * env_exp(n, 1.0, 0.0005, 0.004)
    dust = burst(n, rng, 0.04, lo=800, hi=5000, delay=0.006) * 0.4
    thud = thump(n, 160, 80, 0.008, 0.025) * 0.5
    return finish(saturate(crack + chips + dust + thud, 1.4), 0.5, 0.1)


@recipe
def bullet_metal(rng, v):
    n = n_of(0.6)
    k = 1.0 + 0.1 * (v - 1)
    ping = modal([1600 * k, 2900 * k, 4700 * k, 6800 * k], [0.18, 0.11, 0.07, 0.05], [0.8, 0.6, 0.45, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0004, 0.001)
    tick = burst(n, rng, 0.002, lo=2500, hi=12000) * 0.9
    clang = modal([410 * k, 880 * k], [0.05, 0.035], [0.5, 0.3], n, rng, 0.02) * env_exp(n, 1.0, 0.0004)
    return finish(saturate(0.55 * ping + tick + 0.4 * clang, 1.3), 0.6, 0.12)


@recipe
def bullet_flesh(rng, v):
    n = n_of(0.35)
    k = 1.0 + 0.1 * (v - 1)
    thud = thump(n, 240 * k, 95, 0.01, 0.045) * 1.0
    soft = burst(n, rng, 0.03, lo=150, hi=900 * k, exponent=0.5) * 1.0
    cloth = burst(n, rng, 0.05, lo=1500, hi=5000, delay=0.008) * 0.25
    return finish(saturate(thud + soft + cloth, 1.2), 0.35, 0.08)


@recipe
def bullet_wood(rng, v):
    n = n_of(0.45)
    k = 1.0 + 0.1 * (v - 1)
    knock = modal([280 * k, 610 * k, 1100 * k], [0.06, 0.04, 0.025], [0.9, 0.6, 0.35], n, rng, 0.02) * env_exp(n, 1.0, 0.0004)
    tick = burst(n, rng, 0.004, lo=1000, hi=6000) * 0.7
    spl = np.zeros(n)
    for _ in range(5):
        m = n_of(0.02)
        place(spl, burst(m, rng, 0.003, lo=2500, hi=9000), n_of(rng.uniform(0.01, 0.12)), rng.uniform(0.15, 0.4))
    return finish(saturate(knock + tick + spl, 1.3), 0.45, 0.1)


@recipe
def bullet_water(rng, v):
    n = n_of(0.5)
    t = t_axis(n)
    k = 1.0 + 0.12 * (v - 1)
    plip = fm(fsweep(n, 900 * k, 260, 0.05), 1.5, 2.0 * np.exp(-t / 0.04), n) * env_exp(n, 0.10, 0.001)
    hiss = burst(n, rng, 0.08, lo=1500, hi=9000) * 0.5
    drop = sine(fsweep(n, 1500 * k, 500, 0.03), n) * env_exp(n, 0.04, 0.001, 0.07) * 0.3
    return finish(saturate(plip * 0.9 + hiss + drop, 1.2), 0.5, 0.12)


@recipe
def energy_small(rng, v):
    n = n_of(0.5)
    t = t_axis(n)
    k = 1.0 + 0.1 * (v - 1)
    zap = fm(fsweep(n, 3200 * k, 700, 0.03), 1.41, 4.0 * np.exp(-t / 0.05), n) * env_exp(n, 0.08, 0.0006)
    sizzle = highpass(crackle(n, rng, 1100 * np.exp(-t / 0.10) + 30), 2500) * 0.8
    pop = burst(n, rng, 0.006, lo=800, hi=8000) * 0.6
    return finish(saturate(0.8 * zap + sizzle + pop, 1.4), 0.5, 0.1)


@recipe
def energy_large(rng, v):
    n = n_of(1.0)
    t = t_axis(n)
    crack = burst(n, rng, 0.003, lo=2500, hi=15000) * 1.1
    ring = modal([1900, 3300, 5200, 7600], [0.30, 0.22, 0.15, 0.10], [0.4, 0.3, 0.22, 0.15], n, rng, 0.006) * env_exp(n, 1.0, 0.0005)
    body = fm(fsweep(n, 900, 180, 0.09), 1.41, 3.5 * np.exp(-t / 0.12), n) * env_exp(n, 0.25, 0.001) * 0.7
    thump_ = thump(n, 110, 48, 0.04, 0.16, drive=1.4)
    arcs = highpass(crackle(n, rng, 800 * np.exp(-t / 0.2) + 20), 2200) * 0.5
    return finish(verb(saturate(crack + ring * 0.6 + body + thump_ + arcs, 1.4), "room", 0.16), 1.0, 0.2)


@recipe
def rail_hit(rng, v):
    n = n_of(0.9)
    t = t_axis(n)
    thump_ = thump(n, 80, 32, 0.03, 0.22, drive=1.7)
    crack = burst(n, rng, 0.004, lo=1400, hi=12000) * 1.1
    slam = burst(n, rng, 0.03, lo=250, hi=2600) * 0.9
    ring = modal([720, 1650, 3300], [0.16, 0.10, 0.07], [0.4, 0.3, 0.2], n, rng, 0.01) * env_exp(n, 1.0, 0.0005)
    return finish(verb(saturate(thump_ + crack + slam + 0.5 * ring, 1.5), "room", 0.12), 0.9, 0.2)


@recipe
def kinetic_hit(rng, v):
    """Orbital / heavy kinetic slug: sub thump, shockwave crack, tearing debris."""
    n = n_of(1.7)
    t = t_axis(n)
    sub = thump(n, 60, 22, 0.08, 0.40, drive=1.8)
    crack = burst(n, rng, 0.004, lo=1600, hi=14000) * 1.2
    slam = burst(n, rng, 0.05, lo=200, hi=3200) * 1.3
    shock = lowpass(colored_noise(n, rng, 0.0), 220, 4) * env_exp(n, 0.30)
    deb = highpass(lowpass(crackle(n, rng, 700 * np.exp(-t / 0.4) + 12), 6500), 1200) * 0.5 * env_exp(n, 0.8, 0.01, 0.05)
    return finish(verb(saturate(sub + crack + slam + shock + deb, 1.6), "hall", 0.22), 1.7, 0.3)


@recipe
def emp_hit(rng, v):
    n = n_of(1.3)
    t = t_axis(n)
    thoom = thump(n, 100, 36, 0.06, 0.28, drive=1.6)
    arcs = highpass(crackle(n, rng, 1200 * np.exp(-t / 0.30) + 40, 1.2), 2400) * 1.0
    whine = sine(2400 * np.exp(-t / 0.28) + 100, n) * env_exp(n, 0.4, 0.004) * 0.3
    pop = burst(n, rng, 0.02, lo=400, hi=6000) * 0.7
    return finish(verb(saturate(thoom + arcs + whine + pop, 1.4), "plate", 0.18), 1.3, 0.25)


@recipe
def aps_pop(rng, v):
    """Active-protection intercept: sharp clang and a whoosh of counter-charge."""
    n = n_of(0.5)
    t = t_axis(n)
    clang = modal([1200, 2350, 3800], [0.10, 0.07, 0.05], [0.7, 0.5, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0003)
    pop = burst(n, rng, 0.008, lo=700, hi=9000) * 1.0
    whoosh = burst(n, rng, 0.09, lo=800, hi=7000, delay=0.01) * 0.5
    return finish(saturate(clang * 0.7 + pop + whoosh, 1.4), 0.5, 0.1)


@recipe
def zone_snap(rng, v):
    """Interception zone snap: electrical snap with a short zippering decay."""
    n = n_of(0.6)
    t = t_axis(n)
    snap = burst(n, rng, 0.004, lo=1500, hi=14000) * 1.2
    zip_ = fm(fsweep(n, 4200, 700, 0.05), 1.7, 4.0 * np.exp(-t / 0.06), n) * env_exp(n, 0.10, 0.0005) * 0.8
    arcs = highpass(crackle(n, rng, 900 * np.exp(-t / 0.10) + 20), 2500) * 0.7
    return finish(verb(saturate(snap + zip_ + arcs, 1.4), "room", 0.10), 0.6, 0.12)
