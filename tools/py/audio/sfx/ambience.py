"""ambience.py - stereo ambience beds (16-24 s loops): wind, city hum, coast waves (spike) + river, forest, distant battle.
Every bed is circular: frequency-domain noise, integer-cycle modulation, circular filters, wrap-around placement."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import (
    SR, bandpass, colored_noise, crackle, env_exp, highpass, lfo, lowpass, n_of, place, sine, slow_noise, sweep_filter, t_axis)
from sfx import recipe
from sfx.kit import thump


def _chan_rng(name: str, c: int):
    return dsp.rng_for(name, c)


@recipe
def amb_wind_open(rng, v):
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    for c in range(2):
        r = _chan_rng("wind", c)
        base = colored_noise(n, r, 1.0, lo=50, hi=9000)
        g = 0.5 + 0.5 * (0.55 * slow_noise(n, r, 0.25) * 3 / 1.5 + 0.35 * np.sin(2 * np.pi * (2 / T) * t + c) + 0.2 * np.sin(2 * np.pi * (5 / T) * t + 2 * c))
        g = np.clip(g, 0.0, 1.0)
        f = sweep_filter(base, 320 + 2700 * g ** 1.6, "lp", 0.8, 2, 16, circ=True) * (0.22 + 0.78 * g ** 1.3)
        wh = colored_noise(n, r, 0.0, lo=950, hi=1500) * g ** 4 * 0.18
        chans.append(f + wh)
    return np.stack(chans, axis=1)


@recipe
def amb_city_hum(rng, v):
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    hum = sum(a * sine(60.0 * k, n, 0.1 * k) for k, a in ((1, 0.5), (2, 0.35), (3, 0.18), (4, 0.10), (6, 0.05))) * (1 + 0.05 * lfo(3 / T, n))
    chans = []
    for c in range(2):
        r = _chan_rng("city", c)
        hvac = lowpass(colored_noise(n, r, 1.0, lo=60, hi=3000), 700, circ=True) * (0.7 + 0.3 * np.sin(2 * np.pi * (3 / T) * t + c)) * 0.32
        traffic = colored_noise(n, r, 2.0, lo=30, hi=160) * (0.55 + 0.45 * slow_noise(n, r, 0.2, 0.03) * 3 / 1.5) * 0.6
        fizz = colored_noise(n, r, -1.0, lo=4000, hi=12000) * 0.006
        blips = np.zeros(n)
        for _ in range(5):
            m = n_of(0.25)
            f0 = r.choice([1320.0, 1760.0, 990.0])
            place(blips, sine(f0, m) * env_exp(m, 0.06, 0.004) * 0.02, int(r.uniform(0, n)), 1.0, wrap=True)
        chans.append(0.6 * hum + hvac + traffic + fizz + blips)
    return np.stack(chans, axis=1)


@recipe
def amb_coast_waves(rng, v):
    T = 24.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    for c in range(2):
        r = _chan_rng("coast", c)
        bed = lowpass(colored_noise(n, r, 1.0, lo=60, hi=6000), 900, circ=True) * 0.05
        wave = np.zeros(n)
        for i in range(3):
            centre = (i + 0.5 + 0.08 * c + r.uniform(-0.06, 0.06)) * T / 3
            dt = ((t - centre + T / 2) % T) - T / 2
            swell = np.exp(-((dt + 0.6) / 1.8) ** 2) * (dt < 0.6) + np.exp(-((dt + 0.6) / 4.5) ** 2) * (dt >= 0.6)
            cutoff = 250 + 3600 * np.exp(-((dt) / 1.5) ** 2)
            body = sweep_filter(colored_noise(n, r, 1.0, lo=60, hi=9000), cutoff, "lp", 0.8, 2, 16, circ=True) * swell
            fenv = np.clip((dt + 1.2) / 1.2, 0, 1) ** 2 * np.exp(-np.maximum(dt, 0) / 1.8)
            foam = highpass(colored_noise(n, r, 0.0), 3200, circ=True) * fenv * 0.25
            wave += body * (0.8 + 0.4 * r.random()) + foam
        chans.append(bed + wave)
    return np.stack(chans, axis=1)


@recipe
def amb_river_flow(rng, v):
    """Band-passed noise for the bulk flow + a scatter of burbles (short rising modal blips) and a slow swirl."""
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    for c in range(2):
        r = _chan_rng("river", c)
        flow = bandpass(colored_noise(n, r, 0.8, lo=150, hi=9000), 250, 5200, circ=True)
        flow *= 0.75 + 0.25 * slow_noise(n, r, 1.5, 0.1) * 3 / 1.5
        low = lowpass(colored_noise(n, r, 1.5, lo=40, hi=500), 400, circ=True) * (0.8 + 0.2 * np.sin(2 * np.pi * (2 / T) * t + c)) * 0.25
        bur = np.zeros(n)
        for _ in range(70):
            m = n_of(0.16)
            f0 = r.uniform(500, 1800)
            fs = f0 * (1 + 0.6 * np.linspace(0, 1, m))
            b = np.sin(2 * np.pi * np.cumsum(fs) / SR) * env_exp(m, 0.03, 0.004)
            place(bur, b, int(r.uniform(0, n)), r.uniform(0.008, 0.03), wrap=True)
        sparkle = highpass(colored_noise(n, r, -0.5), 6000, circ=True) * 0.012 * (0.5 + 0.5 * slow_noise(n, r, 4.0, 0.5))
        chans.append(0.25 * flow + low + bur + sparkle)
    return np.stack(chans, axis=1)


@recipe
def amb_forest(rng, v):
    """Leaf rustle (gust-modulated 1.5-7 kHz noise), a low breeze and a chorus of insects (AM'd high tones)."""
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    for c in range(2):
        r = _chan_rng("forest", c)
        gust = np.clip(0.5 + 0.5 * (0.6 * slow_noise(n, r, 0.3) * 3 / 1.5 + 0.4 * np.sin(2 * np.pi * (3 / T) * t + c)), 0.05, 1.0)
        leaves = bandpass(colored_noise(n, r, 0.0), 1500, 7000, circ=True) * (0.25 + 0.75 * gust ** 1.5) * 0.12
        breeze = lowpass(colored_noise(n, r, 1.5, lo=60, hi=900), 600, circ=True) * gust * 0.16
        ins = np.zeros(n)
        for k in range(9):
            f0 = dsp.snap_freq(r.uniform(3800, 6200), T)
            am = np.abs(np.sin(np.pi * dsp.snap_freq(r.uniform(28, 46), T) * t + r.uniform(0, 3))) ** 3
            window = np.clip(0.5 + 0.5 * np.sin(2 * np.pi * (int(r.integers(1, 5)) / T) * t + r.uniform(0, 6)), 0, 1) ** 2
            ins += sine(f0, n, r.random()) * am * window * 0.012
        chans.append(leaves + breeze + ins)
    return np.stack(chans, axis=1)


@recipe
def amb_battle_far(rng, v):
    """Far-off battle: a low rumble bed, sparse distant thumps, a faint crackle of small arms."""
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    thumps = [(r_, g_) for r_, g_ in zip(dsp.rng_for("battle", 99).uniform(0, 1, 9), dsp.rng_for("battle", 98).uniform(0.4, 1.0, 9))]
    for c in range(2):
        r = _chan_rng("battle", c)
        rumble = lowpass(colored_noise(n, r, 2.0, lo=25, hi=200), 160, circ=True) * (0.6 + 0.4 * slow_noise(n, r, 0.3, 0.03) * 3 / 1.5) * 0.5
        y = np.zeros(n)
        for pos, g in thumps:
            m = n_of(1.4)
            b = thump(m, 78, 32, 0.08, 0.35, drive=1.3) + lowpass(colored_noise(m, r, 0.0), 260, 4) * env_exp(m, 0.3)
            b = lowpass(b, 300)
            place(y, b, int((pos + 0.01 * c) * n), g * 0.5, wrap=True)
        crack = lowpass(highpass(crackle(n, r, 40 * (0.5 + 0.5 * np.sin(2 * np.pi * (2 / T) * t + 2 * c)) + 10), 1200), 3800) * 0.18
        hiss = lowpass(colored_noise(n, r, 1.0, lo=200, hi=6000), 3000, circ=True) * 0.02      # distant air / haze
        chans.append(rumble + y + crack + hiss)
    return np.stack(chans, axis=1)
