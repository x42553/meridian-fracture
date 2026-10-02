"""sfx.py - procedural sound-effect recipes (numpy only, built on dsp.py).

Every recipe is  fn(rng, variant) -> ndarray  (mono (n,) or stereo (n,2)) registered with @sound(...).
Loops (loop=True) are built from circular noise, whole-cycle-snapped oscillators and wrap-around placement, so
their seam is mathematically continuous; one-shots get a short fade-out.  Recipes follow the classic
layering rules: transient (crack) + body + low thump/sub + tail (reverb/echo/debris), then saturation.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from functools import lru_cache
from typing import Callable

import numpy as np

import dsp
from dsp import (SR, Array, biquad, bandpass, colored_noise, crackle, decorrelate, echo, env_exp, env_points,
                 fade, fit, highpass, lfo, lowpass, make_ir, modal, n_of, pan, phase_cycles, place, reverb, saturate,
                 saw, sine, slow_noise, snap_freq, square, sweep_filter, t_axis, to_mono, to_stereo, widen, fm)


@dataclass
class Sound:
    name: str
    category: str
    fn: Callable[[np.random.Generator, int], Array]
    channels: str = "mono"          # "mono" (3D-positional use) or "stereo" (2D / hero / beds)
    loop: bool = False
    peak_db: float = -1.5
    variants: int = 1
    tags: tuple[str, ...] = ()
    notes: str = ""
    lufs: float | None = None       # optional loudness target (peak_db stays a hard ceiling)


SOUNDS: dict[str, Sound] = {}


def sound(name: str, category: str, channels: str = "mono", loop: bool = False, peak_db: float = -1.5,
          variants: int = 1, tags: tuple[str, ...] = (), notes: str = ""):
    def deco(fn):
        SOUNDS[name] = Sound(name, category, fn, channels, loop, peak_db, variants, tags, notes)
        return fn
    return deco


# ------------------------------------------------------------------------------------------------ helpers
_PRESETS = {
    "room": dict(rt60=0.45, predelay=0.004, damping_hz=7000, size=0.5),
    "small": dict(rt60=0.75, predelay=0.006, damping_hz=6000, size=0.7),
    "field": dict(rt60=0.55, predelay=0.012, damping_hz=3800, size=0.9, low_mult=0.7),
    "outdoor": dict(rt60=1.0, predelay=0.020, damping_hz=3600, size=1.2, low_mult=0.8),
    "hangar": dict(rt60=1.6, predelay=0.010, damping_hz=8000, size=1.0),
    "hall": dict(rt60=2.6, predelay=0.028, damping_hz=5200, size=1.6),
    "canyon": dict(rt60=3.4, predelay=0.045, damping_hz=2800, size=2.0, low_mult=1.3),
    "plate": dict(rt60=1.8, predelay=0.002, damping_hz=9500, size=0.4),
}


@lru_cache(maxsize=None)
def _ir(preset: str) -> Array:
    return make_ir(seed="ir_" + preset, **_PRESETS[preset])


def verb(x: Array, preset: str, wet: float = 0.3, dry: float = 1.0, circular: bool = False) -> Array:
    return reverb(x, _ir(preset), wet=wet, dry=dry, circular=circular)


def fsweep(n: int, f0: float, f1: float, tc: float) -> Array:
    """Exponential pitch glide f0 -> f1 with time constant tc (kick/boom/zap staple)."""
    return f1 + (f0 - f1) * np.exp(-t_axis(n) / tc)


def burst(n: int, rng: np.random.Generator, tau: float, lo: float | None = None, hi: float | None = None,
          exponent: float = 0.0, delay: float = 0.0, attack: float = 0.0004) -> Array:
    return colored_noise(n, rng, exponent, lo, hi, 0.35) * env_exp(n, tau, attack, delay)


def thump(n: int, f0: float, f1: float, tc: float, tau: float, delay: float = 0.0, drive: float = 0.0) -> Array:
    y = sine(fsweep(n, f0, f1, tc), n) * env_exp(n, tau, 0.0015, delay)
    return saturate(y, drive) if drive else y


def finish(x: Array, seconds: float, fade_out: float = 0.05) -> Array:
    return fade(fit(x, n_of(seconds)), 0.0, fade_out)


def mono(x: Array) -> Array:
    return to_mono(x)


# ------------------------------------------------------------------------------------------------ weapons
@sound("rifle_shot", "weapons", variants=3, tags=("small_arms",), notes="crack + supersonic snap + body + short thump, slap echo, field reverb")
def rifle_shot(rng, v):
    n = n_of(1.3)
    k = 1.0 + 0.08 * (v - 1)
    crack = burst(n, rng, 0.0016, lo=1800 * k, hi=16000, attack=0.0002)
    snap = burst(n, rng, 0.006, lo=2500, hi=7000 * k)
    body = burst(n, rng, 0.020, lo=350, hi=3000 * k, exponent=0.5)
    low = thump(n, 200 * k, 85, 0.012, 0.030)
    x = saturate(1.1 * crack + 0.9 * snap + 0.7 * body + 0.5 * low, 1.8)
    x = highpass(x, 90)
    slap = np.roll(lowpass(x, 3000), n_of(0.105 + 0.014 * v)) * 0.20
    slap[: n_of(0.105)] = 0
    return finish(verb(x + slap, "field", 0.24), 1.3, 0.25)


@sound("autocannon_burst", "weapons", tags=("autocannon",), notes="9 rounds @ ~11.5 Hz with jitter")
def autocannon_burst(rng, v):
    n = n_of(1.9)
    dry = np.zeros(n)
    for i in range(9):
        m = n_of(0.30)
        r = rng_round = None
        crack = burst(m, rng, 0.0018, lo=1200, hi=13000)
        body = burst(m, rng, 0.040, lo=350, hi=2600, exponent=0.5)
        low = thump(m, 190, 62, 0.018, 0.045)
        clack = modal([1850, 3150], [0.014, 0.010], [0.5, 0.3], m, rng, 0.01)
        shot = saturate(crack + 0.9 * body + 0.8 * low + 0.15 * clack, 1.8)
        place(dry, shot, n_of(0.02 + i * 0.087 + rng.uniform(-0.004, 0.004)), 10 ** (rng.uniform(-1.6, 0.5) / 20))
    return finish(verb(dry, "outdoor", 0.32), 1.9, 0.25)


@sound("tank_cannon", "weapons", channels="stereo", tags=("tank",), notes="sub sweep + boom + crack + breech clank + rumble tail")
def tank_cannon(rng, v):
    n = n_of(3.0)
    sub = thump(n, 74, 31, 0.10, 0.22, drive=1.4)
    boom = lowpass(colored_noise(n, rng, 0.0), 420, 4) * env_exp(n, 0.16)
    mid = lowpass(colored_noise(n, rng, 0.3, lo=200), 1400, 4) * env_exp(n, 0.10) * 0.9
    crack = burst(n, rng, 0.004, lo=1800, hi=14000) * 1.2
    punch = burst(n, rng, 0.030, lo=650, hi=2500) * 1.2
    clank = modal([310, 780, 1490, 2350], [0.09, 0.07, 0.05, 0.03], [1, 0.7, 0.5, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0005, 0.19)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=160) * env_exp(n, 0.60, 0.004) * 1.0
    x = saturate(0.9 * sub + 1.0 * boom + mid + 0.8 * crack + 0.8 * punch + 0.30 * clank + 0.35 * rumble, 1.5)
    return finish(verb(x, "canyon", 0.28), 3.0, 0.5)


@sound("howitzer_thump", "weapons", channels="stereo", tags=("artillery",), notes="pressure thump, whistle-away, distant rolling echoes")
def howitzer_thump(rng, v):
    n = n_of(4.0)
    sub = thump(n, 58, 19, 0.16, 0.55, drive=1.6)
    press = lowpass(colored_noise(n, rng, 0.0), 95, 4) * env_exp(n, 0.35) * 1.4
    blast = burst(n, rng, 0.02, lo=700, hi=6000) * 0.75 + lowpass(colored_noise(n, rng, 0.3, lo=150), 1000, 4) * env_exp(n, 0.10) * 0.8
    whistle = sweep_filter(colored_noise(n, rng, 0.5), 4200 * np.exp(-t_axis(n) / 1.3) + 600, "lp", 1.2, 2, 16)
    whistle *= env_points(n, [(0, 0), (0.12, 0.16, 1), (2.6, 0.0, -3)])
    x = saturate(sub + press + blast + whistle, 1.4)
    tail = np.zeros(n)
    for d, g in ((0.85, 0.30), (1.7, 0.16), (2.6, 0.08)):
        place(tail, lowpass(x, 500, 2) * g, n_of(d))
    return finish(verb(x + tail, "canyon", 0.34), 4.0, 0.6)


@sound("missile_launch", "weapons", channels="stereo", tags=("missile",), notes="ignition pop, rising motor roar, recede")
def missile_launch(rng, v):
    n = n_of(3.8)
    t = t_axis(n)
    motor = colored_noise(n, rng, 1.0, lo=120, hi=9000)
    cut = np.where(t < 0.55, 250 + 3200 * (t / 0.55) ** 1.5, 3450 * np.exp(-np.maximum(t - 1.5, 0) / 1.4) + 500)
    motor = sweep_filter(motor, cut, "lp", 0.9, 2, 20)
    amp = env_points(n, [(0, 0), (0.15, 0.85, 1.5), (1.5, 1.0), (3.6, 0.0, -2.5)])
    rumble = colored_noise(n, rng, 2.0, lo=40, hi=220) * amp * 0.9
    fizz = crackle(n, rng, 900 * amp + 30) * 0.7
    fizz = highpass(fizz, 2200) * amp
    pop = burst(n, rng, 0.03, lo=400, hi=4500) * 0.7
    x = motor * amp * 0.9 + rumble + fizz * 0.7 + pop
    x = saturate(x, 1.3)
    st = pan(x, np.linspace(-0.5, 0.6, n))
    st = widen(st + 0.35 * decorrelate(x, "ml"), 1.3)
    return finish(verb(st, "outdoor", 0.2), 3.8, 0.4)


@sound("rocket_whoosh", "weapons", channels="stereo", tags=("rocket", "flyby"), notes="doppler-style pass with band sweep")
def rocket_whoosh(rng, v):
    n = n_of(1.5)
    t = t_axis(n)
    c = 0.58
    bell = np.exp(-((t - c) / 0.24) ** 2)
    noise = colored_noise(n, rng, 0.7, lo=200, hi=12000)
    cut = 700 + 3800 * bell
    x = sweep_filter(noise, cut, "lp", 1.4, 2, 20) * (0.08 + bell)
    f = 1500 * (1.12 - 0.24 / (1 + np.exp(-(t - c) * 10)))
    x += 0.08 * sine(f, n) * bell
    st = pan(x, np.clip((t - c) * 1.9, -0.95, 0.95))
    return finish(verb(st, "room", 0.12), 1.5, 0.25)


# ------------------------------------------------------------------------------------------------ explosions
@sound("explosion_small", "explosions", channels="stereo", variants=2, tags=("explosion",), notes="blast sweep + thump + debris crackle")
def explosion_small(rng, v):
    n = n_of(2.4)
    t = t_axis(n)
    blast = sweep_filter(colored_noise(n, rng, 0.0), 9000 * np.exp(-t / 0.22) + 300, "lp", 0.8, 2, 20) * env_exp(n, 0.12)
    low = thump(n, 135, 44, 0.05, 0.16, drive=1.6) + 0.7 * lowpass(colored_noise(n, rng, 0.0), 220, 4) * env_exp(n, 0.25)
    dens = 500 * np.exp(-t / 0.5) + 20
    deb = highpass(lowpass(crackle(n, rng, dens), 6500), 1400) * 0.5 * env_exp(n, 0.9, 0.05, 0.05)
    x = saturate(blast + low + deb, 1.5)
    return finish(widen(verb(x, "hall", 0.3), 1.2), 2.4, 0.4)


@sound("explosion_large", "explosions", channels="stereo", tags=("explosion", "large"), notes="crack, fireball roar, sub boom, secondary pop, debris rain, long rumble")
def explosion_large(rng, v):
    n = n_of(5.0)
    t = t_axis(n)
    crack = burst(n, rng, 0.006, lo=1200, hi=15000) * 0.9
    roar = sweep_filter(colored_noise(n, rng, 0.6, lo=90, hi=8000), 6500 * np.exp(-t / 0.55) + 260, "lp", 0.8, 2, 20)
    roar *= env_points(n, [(0, 0), (0.004, 1), (0.5, 0.8, -2), (2.4, 0.0, -3)])
    sub = thump(n, 62, 20, 0.30, 0.95, drive=1.8)
    body = lowpass(colored_noise(n, rng, 0.0), 300, 4) * env_exp(n, 0.45)
    pop = thump(n, 95, 38, 0.08, 0.25, delay=0.34, drive=1.5) * 0.55 + burst(n, rng, 0.05, lo=200, hi=2200, delay=0.34) * 0.35
    dens = 700 * np.exp(-t / 1.2) + 12
    deb = highpass(lowpass(crackle(n, rng, dens), 7000), 900) * 0.45 * env_exp(n, 2.0, 0.05, 0.15)
    rumble = colored_noise(n, rng, 2.0, lo=22, hi=140) * env_exp(n, 1.7, 0.02) * 1.3
    x = saturate(crack + 1.0 * roar + 1.15 * sub + 0.9 * body + pop + deb + 0.7 * rumble, 1.5)
    return finish(widen(verb(x, "canyon", 0.30), 1.35), 5.0, 0.8)


@sound("building_collapse", "explosions", channels="stereo", tags=("collapse", "structure"), notes="rumble swell, groans, cracks, random debris crashes, dust hiss, settle")
def building_collapse(rng, v):
    n = n_of(7.0)
    t = t_axis(n)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=180) * env_points(n, [(0, 0), (0.6, 1.0, 1.5), (3.4, 0.85), (6.6, 0.0, -2)]) * 1.2
    groan = lowpass(saw(fsweep(n, 95, 48, 1.4), n), 320, 4) * env_points(n, [(0, 0), (0.3, 0.35), (2.2, 0.2), (3.0, 0, -2)])
    x = rumble + groan
    for _ in range(9):  # sharp structural cracks
        at = rng.uniform(0.05, 1.8)
        m = n_of(0.25)
        cr = burst(m, rng, 0.006, lo=700, hi=9000) + modal(rng.uniform(300, 1800, 3), [0.05, 0.04, 0.03], [0.7, 0.5, 0.3], m, rng) * env_exp(m, 0.05)
        place(x, cr * rng.uniform(0.5, 1.0), n_of(at))
    for _ in range(55):  # debris crashes, density falls over time
        at = rng.uniform(0.6, 5.6) ** 1.0
        if rng.random() > np.exp(-(at - 0.6) / 3.0):
            continue
        m = n_of(0.35)
        fc = rng.uniform(300, 3800)
        cr = bandpass(colored_noise(m, rng, 0.0), fc * 0.7, fc * 1.5) * env_exp(m, rng.uniform(0.03, 0.16), 0.001)
        cr += 0.4 * modal([fc, fc * 2.3], [0.06, 0.04], [0.5, 0.3], m, rng, 0.02) * env_exp(m, 0.1)
        place(x, cr * rng.uniform(0.3, 1.0) * 0.5, n_of(at))
    dust = highpass(colored_noise(n, rng, 1.0), 1800) * env_points(n, [(0, 0), (1.0, 0.12, 1), (4.0, 0.08), (6.8, 0.0, -1)])
    x += dust
    x += thump(n, 80, 35, 0.05, 0.3, delay=3.4, drive=1.4) * 0.6 + burst(n, rng, 0.08, lo=150, hi=1800, delay=3.4) * 0.4
    x = saturate(x, 1.3)
    return finish(widen(verb(x, "hall", 0.24), 1.3), 7.0, 0.7)


# ------------------------------------------------------------------------------------------------ energy weapons
@sound("beam_hum_loop", "energy", channels="stereo", loop=True, peak_db=-6.0, tags=("beam", "loop"), notes="periodic saws+sub+shimmer, snapped to whole cycles")
def beam_hum_loop(rng, v):
    T = 4.0
    n = n_of(T)
    t = t_axis(n)
    f0 = snap_freq(110, T)
    detune = 1.0 + 0.004 * lfo(2 / T, n)
    x = 0.55 * saw(f0 * detune, n) + 0.40 * saw(f0 * 1.5 * (1 + 0.003 * lfo(3 / T, n, 0.3)), n) + 0.5 * sine(f0 / 2, n)
    x = lowpass(x, 2200, 4, circ=True)
    shimmer = colored_noise(n, rng, 0.0, lo=2200, hi=5200) * (0.5 + 0.5 * lfo(snap_freq(7, T), n)) * 0.18
    buzz = highpass(saw(snap_freq(120, T), n), 900, circ=True) * 0.05
    core = x + shimmer + buzz
    st = np.stack([core, np.roll(core, n_of(0.011))], axis=1)
    return widen(st, 1.3)


@sound("beam_discharge", "energy", channels="stereo", tags=("beam",), notes="charge whine, zap burst, descending FM, crackle, thump")
def beam_discharge(rng, v):
    n = n_of(1.8)
    t = t_axis(n)
    tc = 0.6
    fch = 200 + 2200 * np.clip(t / tc, 0, 1) ** 2
    charge = (saw(fch, n) * 0.5 + sine(fch * 2, n) * 0.2) * env_points(n, [(0, 0), (tc, 1, 2.5), (tc + 0.02, 0)])
    charge = lowpass(charge, 5000)
    zap = burst(n, rng, 0.06, lo=900, hi=9000, delay=tc)
    fmf = 4500 * np.exp(-np.maximum(t - tc, 0) / 0.14) + 380
    sweep = fm(fmf, 1.41, 5 * np.exp(-np.maximum(t - tc, 0) / 0.2), n) * env_exp(n, 0.28, 0.001, tc) * 0.7
    cr = highpass(crackle(n, rng, 900 * np.exp(-np.maximum(t - tc, 0) / 0.3) * (t > tc)), 1800) * 0.7
    low = thump(n, 110, 48, 0.04, 0.17, delay=tc, drive=1.5)
    x = saturate(charge * 0.8 + zap + sweep + cr + low, 1.5)
    return finish(widen(verb(x, "hangar", 0.22), 1.3), 1.8, 0.3)


@sound("rail_crack", "energy", channels="stereo", tags=("rail",), notes="supersonic crack + FM zing + ring + whump")
def rail_crack(rng, v):
    n = n_of(2.4)
    t = t_axis(n)
    crack = burst(n, rng, 0.0012, lo=3200, hi=16000, attack=0.0002) * 1.3
    zing = fm(1800 + 3400 * np.exp(-t / 0.07), 1.41, 6 * np.exp(-t / 0.07), n) * env_exp(n, 0.09, 0.0008) * 0.5
    ring = modal([2200, 3700, 5900, 8300], [0.42, 0.3, 0.2, 0.15], [0.25, 0.2, 0.15, 0.1], n, rng, 0.004) * env_exp(n, 2.0, 0.0006)
    whump = thump(n, 100, 44, 0.03, 0.13, drive=1.4) * 0.9
    x = saturate(crack + zing + ring + whump, 1.4)
    slap = np.zeros(n)
    for d, g in ((0.13, 0.28), (0.29, 0.16), (0.52, 0.09)):
        place(slap, highpass(lowpass(x, 5000 * (1 - 0.3 * d)), 1500) * g, n_of(d))
    return finish(widen(verb(x + slap, "hangar", 0.3), 1.25), 2.4, 0.4)


@sound("emp_zap", "energy", channels="stereo", tags=("emp",), notes="thoom + arc crackle + S&H FM sparks + falling power-down whine")
def emp_zap(rng, v):
    n = n_of(2.2)
    t = t_axis(n)
    pulse = thump(n, 92, 34, 0.08, 0.32, drive=1.6)
    dens = 1400 * np.exp(-t / 0.45) + 60
    arcs = highpass(crackle(n, rng, dens, 1.2), 2500) * 1.1
    hold = int(0.03 * SR)
    sh = np.repeat(rng.uniform(1200, 6500, n // hold + 2), hold)[:n]
    sparks = fm(sh, 2.13, 8.0, n) * env_exp(n, 0.55, 0.002) * (0.4 + 0.6 * (np.abs(arcs) > 0.02)) * 0.28
    down = sine(1900 * np.exp(-t / 0.35) + 90, n) * env_exp(n, 0.5, 0.004) * 0.3
    ring = sine(220 * t + 40 * np.sin(2 * np.pi * 11 * t), n) * env_exp(n, 0.3) * 0.2
    x = saturate(pulse + arcs + sparks + down + ring, 1.4)
    return finish(widen(verb(x, "plate", 0.22), 1.4), 2.2, 0.4)


# ------------------------------------------------------------------------------------------------ air
@sound("jet_flyby", "air", channels="stereo", tags=("aircraft", "flyby"), notes="physical pass model: doppler on whine, cutoff/amp/pan from geometry")
def jet_flyby(rng, v):
    T = 7.0
    n = n_of(T)
    t = t_axis(n)
    t0, d0, vel, c = 3.2, 55.0, 240.0, 343.0
    xp = vel * (t - t0)
    r = np.sqrt(d0 ** 2 + xp ** 2)
    vr = vel * xp / r                       # radial velocity (m/s, + = receding)
    dopp = 1.0 / (1.0 + vr / c)
    near = (d0 / r)
    amp = near ** 0.85
    jet = colored_noise(n, rng, 0.9, lo=110, hi=11000)
    jet = sweep_filter(jet, 800 + 3800 * near ** 0.7, "lp", 0.9, 2, 20) * amp
    roar = colored_noise(n, rng, 2.0, lo=60, hi=520) * near ** 1.2 * 1.3
    f0 = 1180.0 * dopp
    whine = (sine(f0, n) + 0.5 * sine(2 * f0, n) + 0.22 * sine(3.02 * f0, n)) * amp ** 0.8
    whine = lowpass(whine, 6000)
    fizz = highpass(colored_noise(n, rng, 0.0), 4500) * near ** 1.6 * 0.30
    x = 0.8 * jet + 0.55 * roar + 0.10 * whine + fizz
    x = saturate(x, 1.2)
    st = pan(x, np.clip(xp / (r + 1e-9), -1, 1) * 0.92)
    return finish(verb(st, "outdoor", 0.14), T, 0.5)


@sound("heli_rotor_loop", "air", channels="stereo", loop=True, peak_db=-6.0, tags=("aircraft", "loop"), notes="88 blade slaps in 4 s (22 Hz), 4-blade gain pattern, turbine whine, tail rotor")
def heli_rotor_loop(rng, v):
    T = 4.0
    n = n_of(T)
    bp = 22.0
    m = n_of(0.09)
    slap = burst(m, rng, 0.0045, lo=900, hi=3800)
    th = thump(m, 120, 55, 0.008, 0.028)
    blade = 0.8 * slap + 1.0 * th
    dry = np.zeros(n)
    pattern = [1.0, 0.78, 0.92, 0.84]
    for i in range(int(bp * T)):
        place(dry, blade, int(i / bp * SR + rng.normal(0, 8)), pattern[i % 4] * (1 + 0.05 * rng.normal()), wrap=True)
    t = t_axis(n)
    rot = bp / 4
    am = 1.0 + 0.22 * np.sin(2 * np.pi * rot * t)
    whine = (sine(snap_freq(1450, T), n) + 0.4 * sine(snap_freq(2900, T), n)) * (1 + 0.1 * lfo(2 / T, n)) * 0.05
    tail = highpass(saw(snap_freq(118, T), n), 400, circ=True) * 0.07 * (0.6 + 0.4 * lfo(bp * 3 / 4 * 1.0, n))
    air = lowpass(colored_noise(n, rng, 1.0), 900, circ=True) * 0.22
    core = dry * am * 0.85 + whine + tail + air
    st = np.stack([core, np.roll(core, n_of(0.006))], axis=1)
    return widen(st, 1.25)


# ------------------------------------------------------------------------------------------------ vehicles / movement
@sound("engine_tracked_loop", "vehicles", loop=True, peak_db=-6.0, tags=("engine", "loop"), notes="27 Hz firing pulses through body resonances + track clatter + rumble")
def engine_tracked_loop(rng, v):
    T = 3.0
    n = n_of(T)
    m = n_of(0.06)
    pulse = thump(m, 96, 44, 0.006, 0.010)
    x = np.zeros(n)
    for i in range(int(27 * T)):
        place(x, pulse, int(i / 27 * SR + rng.normal(0, 14)), 1 + 0.12 * rng.normal(), wrap=True)
    x = biquad(lowpass(x, 300, 4, circ=True), "peak", 95, 2.0, 9.0, True)
    x = biquad(x, "peak", 190, 2.0, 5.0, True)
    cl = np.zeros(n)
    mm = n_of(0.05)
    link = 0.6 * burst(mm, rng, 0.003, lo=700, hi=5000) + modal([900, 1650, 2500], [0.010, 0.007, 0.005], [0.6, 0.4, 0.25], mm, rng, 0.02)
    for i in range(32):
        place(cl, link, int(i / 32 * n + rng.normal(0, 55)), rng.uniform(0.6, 1.0), wrap=True)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=110) * 0.5
    y = (1.0 * x + 0.3 * cl + rumble) * (1 + 0.08 * lfo(1 / T, n))
    return saturate(y, 1.2)


@sound("engine_wheeled_loop", "vehicles", loop=True, peak_db=-6.0, tags=("engine", "loop"), notes="uneven 4-pulse firing group @44 Hz, intake + tire noise, transmission whine")
def engine_wheeled_loop(rng, v):
    T = 2.5
    n = n_of(T)
    m = n_of(0.04)
    pulse = (sine(fsweep(m, 150, 75, 0.008), m) + 0.35 * sine(fsweep(m, 300, 150, 0.008), m)) * env_exp(m, 0.011, 0.0006)
    x = np.zeros(n)
    pat = [1.0, 0.7, 0.92, 0.62]
    for i in range(int(44 * T)):
        place(x, pulse, int(i / 44 * SR + rng.normal(0, 10)), pat[i % 4] * (1 + 0.06 * rng.normal()), wrap=True)
    x = lowpass(x, 950, 4, circ=True)
    intake = bandpass(colored_noise(n, rng, 1.0), 300, 1300, circ=True) * (0.6 + 0.4 * lfo(2 / T, n)) * 0.20
    tire = bandpass(colored_noise(n, rng, 0.5), 900, 3800, circ=True) * 0.10
    whine = sine(snap_freq(780, T), n) * 0.03
    return saturate(x + intake + tire + whine, 1.3)


@sound("engine_boat_loop", "vehicles", loop=True, peak_db=-6.0, tags=("engine", "loop"), notes="irregular burble @12.5 Hz, water hiss, gurgle, prop whine")
def engine_boat_loop(rng, v):
    T = 3.2
    n = n_of(T)
    m = n_of(0.08)
    pulse = sine(fsweep(m, 130, 62, 0.012), m) * env_exp(m, 0.022, 0.001)
    x = np.zeros(n)
    for i in range(int(12.5 * T)):
        place(x, pulse, int(i / 12.5 * SR + rng.normal(0, 90)), 0.6 + 0.6 * rng.random(), wrap=True)
    x = lowpass(x, 320, 4, circ=True)
    hiss = bandpass(colored_noise(n, rng, 1.0), 700, 5200, circ=True) * (0.7 + 0.3 * lfo(2 / T, n)) * 0.26
    gur = sine(170 + 55 * slow_noise(n, rng, 8.0, 1.0), n) * 0.06
    prop = sine(snap_freq(640, T), n) * 0.03
    return saturate(x * 1.1 + hiss + gur + prop, 1.2)


@sound("footsteps_loop", "vehicles", loop=True, peak_db=-6.0, tags=("infantry", "loop"), notes="8 steps in 4 s, per-step variation, gear jingle")
def footsteps_loop(rng, v):
    T = 4.0
    n = n_of(T)
    x = np.zeros(n)
    for i in range(8):
        m = n_of(0.30)
        f = 1.0 + 0.25 * (i % 2)
        st = burst(m, rng, 0.030, lo=150, hi=1400 * f, exponent=0.5) + 0.8 * thump(m, 105 * f, 62, 0.012, 0.05)
        st += 0.30 * highpass(crackle(m, rng, 900 * np.exp(-t_axis(m) / 0.05)), 1800) + \
            0.05 * modal([3200, 5100], [0.05, 0.03], [1, 0.6], m, rng, 0.02)
        place(x, saturate(st, 1.3), int(i * 0.5 * SR + rng.normal(0, 260)), 10 ** (rng.uniform(-2.0, 0.0) / 20), wrap=True)
    return x


# ------------------------------------------------------------------------------------------------ UI
@sound("ui_click", "ui", peak_db=-4.0, tags=("ui",), notes="2 ms click + 1.8 kHz tick")
def ui_click(rng, v):
    n = n_of(0.16)
    x = burst(n, rng, 0.0012, lo=2500, hi=14000) * 0.5 + sine(1800, n) * env_exp(n, 0.007, 0.0004) * 0.8 + sine(420, n) * env_exp(n, 0.012, 0.0004) * 0.4
    return finish(saturate(x, 1.2), 0.16, 0.03)


@sound("ui_hover", "ui", peak_db=-9.0, tags=("ui",), notes="soft 2.6 kHz blip")
def ui_hover(rng, v):
    n = n_of(0.14)
    x = (sine(2600, n) + 0.22 * sine(5200, n)) * env_exp(n, 0.03, 0.005)
    return finish(x, 0.14, 0.04)


@sound("ui_error", "ui", peak_db=-5.0, tags=("ui",), notes="two low buzz pulses, falling pitch")
def ui_error(rng, v):
    n = n_of(0.42)
    x = np.zeros(n)
    for i, f in enumerate((150, 128)):
        m = n_of(0.11)
        b = lowpass(square(f, m) * 0.7 + saw(f * 1.005, m) * 0.5, 1100) * env_points(m, [(0, 0), (0.008, 1, 1), (0.09, 0.8), (0.11, 0, -3)])
        place(x, b, n_of(0.02 + i * 0.15))
    return finish(saturate(x, 1.4), 0.42, 0.05)


@sound("ui_confirm", "ui", channels="stereo", peak_db=-5.0, tags=("ui",), notes="rising FM-bell dyad E5->B5")
def ui_confirm(rng, v):
    n = n_of(0.9)
    x = np.zeros(n)
    for f, at, g in ((659.3, 0.0, 0.8), (987.8, 0.085, 1.0)):
        m = n - n_of(at)
        nt = fm(f, 3.5, 2.2 * np.exp(-t_axis(m) / 0.12), m) * env_exp(m, 0.20, 0.002)
        place(x, nt, n_of(at), g)
    return finish(widen(verb(x, "plate", 0.16), 1.3), 0.9, 0.2)


# ------------------------------------------------------------------------------------------------ base / structures
@sound("construction_hammer", "structures", tags=("construction",), notes="4 metal strikes with modal ring")
def construction_hammer(rng, v):
    n = n_of(2.4)
    x = np.zeros(n)
    for at in (0.0, 0.43, 0.85, 1.32):
        m = n_of(0.6)
        k = rng.uniform(0.96, 1.05)
        hit = burst(m, rng, 0.004, lo=700, hi=9000) * 0.9 + thump(m, 190 * k, 100, 0.01, 0.03) * 0.8
        hit += modal([1180 * k, 2760 * k, 4400 * k], [0.12, 0.07, 0.05], [0.5, 0.35, 0.2], m, rng, 0.01) * env_exp(m, 1.0, 0.0006)
        place(x, saturate(hit, 1.4), n_of(at + rng.uniform(0, 0.02)), rng.uniform(0.75, 1.0))
    return finish(mono(verb(x, "hangar", 0.18)), 2.4, 0.3)


@sound("construction_servo", "structures", channels="stereo", tags=("construction",), notes="motor whine up/down with gear noise and clunk")
def construction_servo(rng, v):
    n = n_of(1.7)
    t = t_axis(n)
    f = np.interp(t, [0, 0.5, 0.85, 1.45], [300, 980, 960, 420]) * (1 + 0.012 * np.sin(2 * np.pi * 9 * t))
    amp = env_points(n, [(0, 0), (0.05, 1, 1), (1.3, 0.9), (1.5, 0, -3)])
    m = lowpass(saw(f, n) * 0.5 + sine(f, n) * 0.6 + 0.25 * sine(2 * f, n), 4500) * amp
    gear = bandpass(colored_noise(n, rng, 0.0), 900, 3200) * amp * 0.16
    clunk = thump(n, 120, 60, 0.02, 0.06, delay=0.0) * 0.6 + thump(n, 130, 55, 0.02, 0.07, delay=1.5) * 0.7
    click = burst(n, rng, 0.004, lo=800, hi=6000, delay=1.5) * 0.4
    x = saturate(m * 0.55 + gear + clunk + click, 1.3)
    return finish(widen(verb(x, "room", 0.14), 1.2), 1.7, 0.2)


@sound("power_down", "structures", channels="stereo", tags=("power",), notes="frequency-collapsing hum, closing lowpass, falling whine, relay clunk")
def power_down(rng, v):
    n = n_of(2.6)
    t = t_axis(n)
    fh = 100 * np.exp(-t / 1.1) + 26
    hum = (saw(fh, n) * 0.5 + sine(fh / 2, n) * 0.6)
    hum = sweep_filter(hum, 3000 * np.exp(-t / 0.7) + 120, "lp", 0.9, 2, 20) * env_points(n, [(0, 0), (0.02, 1, 1), (1.6, 0.35, -2), (2.2, 0.0, -2)])
    whine = sine(1600 * np.exp(-t / 0.5) + 70, n) * env_exp(n, 0.5, 0.01) * 0.28
    relay = modal([310, 830, 1700], [0.06, 0.05, 0.03], [0.9, 0.5, 0.25], n, rng, 0.01) * env_exp(n, 1.0, 0.0006, 2.05) + thump(n, 110, 55, 0.02, 0.05, delay=2.05) * 0.8
    x = saturate(hum + whine + relay, 1.3)
    return finish(widen(verb(x, "hangar", 0.18), 1.2), 2.6, 0.3)


@sound("power_up", "structures", channels="stereo", tags=("power",), notes="capacitor-charge sweep, opening filter, relay slam, stable 100 Hz hum")
def power_up(rng, v):
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
    x = saturate(0.7 * charge + relay + spark + 0.8 * hold, 1.3)
    return finish(widen(verb(x, "hangar", 0.18), 1.2), 3.0, 0.3)


@sound("radar_ping", "structures", channels="stereo", peak_db=-4.0, tags=("radar",), notes="1.18 kHz sonar ping, echo taps, shimmer")
def radar_ping(rng, v):
    n = n_of(2.4)
    t = t_axis(n)
    f = 1180 * (1 + 0.003 * np.sin(2 * np.pi * 6 * t))
    ping = (sine(f, n) + 0.15 * sine(2 * f, n)) * env_exp(n, 0.32, 0.008)
    x = ping.copy()
    for d, g in ((0.42, 0.45), (0.9, 0.22)):
        place(x, lowpass(ping, 2500) * g, n_of(d))
    return finish(widen(verb(x, "plate", 0.25), 1.3), 2.4, 0.4)


@sound("cash_tick", "structures", peak_db=-6.0, tags=("economy",), notes="metallic coin tick")
def cash_tick(rng, v):
    n = n_of(0.30)
    x = modal([2450, 4020, 6100], [0.05, 0.035, 0.02], [1.0, 0.6, 0.3], n, rng, 0.004) + burst(n, rng, 0.0015, lo=3000, hi=12000) * 0.5
    return finish(x, 0.30, 0.06)


# ------------------------------------------------------------------------------------------------ alarms
@sound("sw_siren_loop", "alarms", channels="stereo", loop=True, peak_db=-4.0, tags=("superweapon", "loop"), notes="2 wail cycles / 4 s, detuned pair, circular echo+reverb, 2 Hz pulse")
def sw_siren_loop(rng, v):
    T = 4.0
    n = n_of(T)
    t = t_axis(n)
    lf = 520 * np.exp(np.log(880 / 520) * (0.5 - 0.5 * np.cos(2 * np.pi * 2 / T * t)))
    lf2 = lf * 1.004
    x = saw(lf, n) * 0.5 + saw(lf2, n) * 0.4 + sine(lf, n) * 0.4
    x = lowpass(x, 3400, 4, circ=True) * (0.85 + 0.15 * lfo(4 / T, n))
    x += sine(snap_freq(55, T), n) * 0.08 * (0.5 + 0.5 * lfo(8 / T, n))
    x = saturate(x, 1.5)
    st = np.stack([x, np.roll(x, n_of(0.009))], axis=1)
    st = echo(st, 0.25, 0.5, 0.35, 3, circular=True)
    return verb(st, "hangar", 0.20, circular=True)


@sound("countdown_beep", "alarms", peak_db=-5.0, tags=("superweapon",), notes="short 880 Hz beep")
def countdown_beep(rng, v):
    n = n_of(0.40)
    x = lowpass(square(880, n) * 0.6 + sine(880, n), 5000) * env_points(n, [(0, 0), (0.004, 1, 1), (0.09, 0.9), (0.12, 0, -3)])
    return finish(mono(verb(saturate(x, 1.3), "room", 0.12)), 0.40, 0.05)


@sound("countdown_final", "alarms", channels="stereo", peak_db=-4.0, tags=("superweapon",), notes="long 1.32 kHz launch tone")
def countdown_final(rng, v):
    n = n_of(1.2)
    x = lowpass(square(1320, n) * 0.5 + sine(1320, n) + 0.3 * sine(2640, n), 6000) * env_points(n, [(0, 0), (0.004, 1, 1), (0.6, 0.9), (0.95, 0, -3)])
    return finish(widen(verb(saturate(x, 1.3), "hangar", 0.2), 1.2), 1.2, 0.2)


# ------------------------------------------------------------------------------------------------ ambience beds
@sound("amb_wind_loop", "ambience", channels="stereo", loop=True, peak_db=-9.0, tags=("ambience", "loop"), notes="gust-modulated pink noise (integer-cycle gusts + circular random drift), whistle band")
def amb_wind_loop(rng, v):
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    for c in range(2):
        r = dsp.rng_for("wind", c)
        base = colored_noise(n, r, 1.0, lo=50, hi=9000)
        g = 0.5 + 0.5 * (0.55 * slow_noise(n, r, 0.25) * 3 / 1.5 + 0.35 * np.sin(2 * np.pi * (2 / T) * t + c) + 0.2 * np.sin(2 * np.pi * (5 / T) * t + 2 * c))
        g = np.clip(g, 0.0, 1.0)
        f = sweep_filter(base, 320 + 2700 * g ** 1.6, "lp", 0.8, 2, 16, circ=True) * (0.22 + 0.78 * g ** 1.3)
        wh = colored_noise(n, r, 0.0, lo=950, hi=1500) * g ** 4 * 0.18
        chans.append(f + wh)
    return np.stack(chans, axis=1)


@sound("amb_city_hum_loop", "ambience", channels="stereo", loop=True, peak_db=-12.0, tags=("ambience", "loop"), notes="60 Hz mains + harmonics, HVAC, distant traffic, sparse tonal blips")
def amb_city_hum_loop(rng, v):
    T = 20.0
    n = n_of(T)
    t = t_axis(n)
    hum = sum(a * sine(60.0 * k, n, 0.1 * k) for k, a in ((1, 0.5), (2, 0.35), (3, 0.18), (4, 0.10), (6, 0.05))) * (1 + 0.05 * lfo(3 / T, n))
    chans = []
    for c in range(2):
        r = dsp.rng_for("city", c)
        hvac = lowpass(colored_noise(n, r, 1.0, lo=60, hi=3000), 700, circ=True) * (0.7 + 0.3 * np.sin(2 * np.pi * (3 / T) * t + c)) * 0.32
        traffic = colored_noise(n, r, 2.0, lo=30, hi=160) * (0.55 + 0.45 * slow_noise(n, r, 0.2, 0.03) * 3 / 1.5) * 0.6
        fizz = colored_noise(n, r, -1.0, lo=4000, hi=12000) * 0.006
        blips = np.zeros(n)
        for _ in range(5):
            m = n_of(0.25)
            f0 = rng.choice([1320.0, 1760.0, 990.0])
            place(blips, sine(f0, m) * env_exp(m, 0.06, 0.004) * 0.02, int(rng.uniform(0, n)), 1.0, wrap=True)
        chans.append(0.6 * hum + hvac + traffic + fizz + blips)
    return np.stack(chans, axis=1)


@sound("amb_coast_waves_loop", "ambience", channels="stereo", loop=True, peak_db=-9.0, tags=("ambience", "loop"), notes="3 breaking waves per channel (swell/crest/foam/backwash), 24 s")
def amb_coast_waves_loop(rng, v):
    T = 24.0
    n = n_of(T)
    t = t_axis(n)
    chans = []
    for c in range(2):
        r = dsp.rng_for("coast", c)
        bed = lowpass(colored_noise(n, r, 1.0, lo=60, hi=6000), 900, circ=True) * 0.05
        wave = np.zeros(n)
        for i in range(3):
            centre = (i + 0.5 + 0.08 * c + r.uniform(-0.06, 0.06)) * T / 3
            dt = ((t - centre + T / 2) % T) - T / 2               # circular time offset
            swell = np.exp(-((dt + 0.6) / 1.8) ** 2) * (dt < 0.6) + np.exp(-((dt + 0.6) / 4.5) ** 2) * (dt >= 0.6)
            cutoff = 250 + 3600 * np.exp(-((dt) / 1.5) ** 2)
            body = colored_noise(n, r, 1.0, lo=60, hi=9000)
            body = sweep_filter(body, cutoff, "lp", 0.8, 2, 16, circ=True) * swell
            fenv = np.clip((dt + 1.2) / 1.2, 0, 1) ** 2 * np.exp(-np.maximum(dt, 0) / 1.8)   # smooth build-up, no step
            foam = highpass(colored_noise(n, r, 0.0), 3200, circ=True) * fenv * 0.25
            wave += (body * (0.8 + 0.4 * r.random()) + foam)
        chans.append(bed + wave)
    return np.stack(chans, axis=1)


# loudness targets (LUFS, K-weighted, gated; peak_db above stays a hard ceiling).  Transient one-shots are left
# peak-normalised because crest factors of 15-20 dB make LUFS targets meaningless for them.
_LUFS = {"engine_tracked_loop": -22, "engine_wheeled_loop": -22, "engine_boat_loop": -22, "heli_rotor_loop": -20,
         "beam_hum_loop": -20, "footsteps_loop": -24, "amb_wind_loop": -26, "amb_city_hum_loop": -30, "amb_coast_waves_loop": -26,
         "sw_siren_loop": -16, "countdown_beep": -16, "countdown_final": -14, "ui_click": -22, "ui_hover": -28, "ui_error": -18,
         "ui_confirm": -18, "radar_ping": -20, "cash_tick": -24, "construction_servo": -18, "power_down": -16, "power_up": -15,
         "missile_launch": -17, "rocket_whoosh": -18, "autocannon_burst": -16, "beam_discharge": -16, "jet_flyby": -17}

# psychoacoustic bass amount per asset (build-time master chain; recipes stay physically motivated)
EXCITER = {"tank_cannon": 0.75, "howitzer_thump": 0.9, "explosion_small": 0.7, "explosion_large": 0.7, "building_collapse": 0.6,
           "rail_crack": 0.3, "emp_zap": 0.6, "power_down": 0.4, "missile_launch": 0.3, "beam_hum_loop": 0.25, "sw_siren_loop": 0.0}
for _k, _v in _LUFS.items():
    SOUNDS[_k].lufs = _v
