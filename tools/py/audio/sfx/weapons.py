"""weapons.py - weapon fire recipes: one per archetype family (audio spec 5.4 table) plus the faction-flavour wrapper.

Layering rule from the spike: transient (crack) + body + low thump/sub + tail (reverb/echo/debris), then saturation.
All weapon recipes are positional (3D) sounds: catalog entries master them to mono.  `k` scales pitch/size."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import (
    SR, colored_noise, crackle, env_exp, env_points, fm, highpass, lfo, lowpass, modal, n_of, place, saturate, sine, snap_freq, saw, sweep_filter, t_axis)
from sfx import RECIPES, recipe
from sfx.kit import apply_flavour, burst, echo_taps, finish, fsweep, thump, verb


# ------------------------------------------------------------------------------------------------- small arms
@recipe
def rifle_shot(rng, v):
    """Crack + supersonic snap + body + short thump, slap echo, field reverb (spike reference recipe)."""
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


@recipe
def mg_round(rng, v):
    """Belt-fed MG round: lower, chunkier than the rifle, with a bolt clack; the event layer repeats it."""
    n = n_of(0.9)
    k = 1.0 + 0.06 * (v - 1)
    crack = burst(n, rng, 0.0018, lo=1500 * k, hi=14000, attack=0.0002)
    snap = burst(n, rng, 0.005, lo=2600, hi=8000 * k)
    body = burst(n, rng, 0.026, lo=300, hi=2800 * k, exponent=0.5)
    low = thump(n, 165 * k, 68, 0.014, 0.040)
    clack = modal([1650, 2900], [0.012, 0.008], [0.35, 0.2], n, rng, 0.02) * env_exp(n, 1.0, 0.0004, 0.028)
    x = saturate(1.15 * crack + 0.7 * snap + 0.85 * body + 0.45 * low + 0.25 * clack, 1.9)
    x = highpass(x, 80)
    slap = echo_taps(x, [(0.085 + 0.01 * v, 0.16), (0.19, 0.07)], 2600)
    return finish(verb(x + slap, "field", 0.22), 0.9, 0.2)


@recipe
def autocannon_round(rng, v):
    """Single autocannon round: heavier crack, thumpy 60 Hz body, ejection clank."""
    n = n_of(1.1)
    k = 1.0 + 0.07 * (v - 1)
    crack = burst(n, rng, 0.0022, lo=1300 * k, hi=14000, attack=0.0002)
    snap = burst(n, rng, 0.006, lo=2600, hi=8000 * k)
    body = burst(n, rng, 0.035, lo=350, hi=3200 * k, exponent=0.3)
    low = thump(n, 190 * k, 62, 0.018, 0.05)
    clank = modal([1850, 3150], [0.014, 0.010], [0.5, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0004, 0.05)
    x = saturate(1.3 * crack + 0.9 * snap + 0.95 * body + 0.5 * low + 0.25 * clank, 1.8)
    x = highpass(x, 70)
    slap = echo_taps(x, [(0.12 + 0.012 * v, 0.2), (0.27, 0.1), (0.46, 0.05)], 2800)
    return finish(verb(x + slap, "outdoor", 0.30), 1.1, 0.25)


# ------------------------------------------------------------------------------------------------- cannons
@recipe
def tank_cannon(rng, v, k=1.0, length=3.0, room="canyon"):
    """Sub sweep + boom + crack + breech clank + rumble tail.  k > 1 lighter/higher, k < 1 heavier/lower."""
    n = n_of(length)
    vk = 1.0 + 0.05 * (v - 1)
    kk = k * vk
    sub = thump(n, 74 * kk, 31 * kk, 0.10 / kk, 0.22 / kk, drive=1.4)
    boom = lowpass(colored_noise(n, rng, 0.0), 420 * kk, 4) * env_exp(n, 0.16 / kk)
    mid = lowpass(colored_noise(n, rng, 0.3, lo=200), 1400 * kk, 4) * env_exp(n, 0.10 / kk) * 0.9
    crack = burst(n, rng, 0.004, lo=1800, hi=14000) * 1.2
    punch = burst(n, rng, 0.030, lo=650, hi=2500) * 1.2
    clank = modal([310 * kk, 780 * kk, 1490 * kk, 2350 * kk], [0.09, 0.07, 0.05, 0.03], [1, 0.7, 0.5, 0.3], n, rng, 0.01) \
        * env_exp(n, 1.0, 0.0005, 0.19 / kk)
    rumble = colored_noise(n, rng, 2.0, lo=25, hi=160) * env_exp(n, 0.60 / kk, 0.004)
    x = saturate(0.9 * sub + 1.0 * boom + mid + 0.8 * crack + 0.8 * punch + 0.30 * clank + 0.35 * rumble, 1.5)
    return finish(verb(x, room, 0.28), length, 0.5)


@recipe
def siege_gun(rng, v):
    """Long-barrel siege gun: massive sub, bright muzzle blast, whistle-away and rolling echoes."""
    n = n_of(3.8)
    t = t_axis(n)
    kk = 1.0 + 0.05 * (v - 1)
    sub = thump(n, 60 * kk, 24, 0.14, 0.42, drive=1.6)
    boom = lowpass(colored_noise(n, rng, 0.0), 300, 4) * env_exp(n, 0.28)
    blast = burst(n, rng, 0.018, lo=500, hi=8000) * 1.1
    crack = burst(n, rng, 0.003, lo=2400, hi=15000) * 0.9
    rumble = colored_noise(n, rng, 2.0, lo=22, hi=130) * env_exp(n, 1.0, 0.004)
    whistle = sweep_filter(colored_noise(n, rng, 0.5), 3800 * np.exp(-t / 0.7) + 500, "lp", 1.1, 2, 16)
    whistle *= env_points(n, [(0, 0), (0.1, 0.10, 1), (1.6, 0.0, -3)])
    x = saturate(1.0 * sub + 1.0 * boom + blast + crack + 0.55 * rumble + whistle, 1.5)
    tail = echo_taps(x, [(0.7, 0.24), (1.5, 0.13), (2.4, 0.07)], 700)
    return finish(verb(x + tail, "canyon", 0.30), 3.8, 0.6)


@recipe
def demolition_boom(rng, v):
    """Blunt, short, very low demolition cannon: thud + shattered-concrete crackle."""
    n = n_of(2.6)
    t = t_axis(n)
    kk = 1.0 + 0.06 * (v - 1)
    sub = thump(n, 55 * kk, 21, 0.09, 0.40, drive=1.8)
    body = lowpass(colored_noise(n, rng, 0.0), 260, 4) * env_exp(n, 0.22)
    slam = burst(n, rng, 0.020, lo=220, hi=3400) * 1.9
    crack = burst(n, rng, 0.003, lo=1500, hi=9000) * 1.0
    deb = highpass(lowpass(crackle(n, rng, 380 * np.exp(-t / 0.45) + 15), 6000), 1200) * 0.45 * env_exp(n, 0.9, 0.02, 0.05)
    x = saturate(0.85 * sub + 1.0 * body + slam + crack + deb, 1.6)
    return finish(verb(x, "hall", 0.26), 2.6, 0.45)


@recipe
def naval_gun(rng, v, k=1.0, length=3.2):
    """Ship's gun: a cannon blast over open water - long watery tail, a metallic turret ring."""
    n = n_of(length)
    kk = k * (1.0 + 0.05 * (v - 1))
    sub = thump(n, 68 * kk, 26 * kk, 0.11, 0.34, drive=1.5)
    boom = lowpass(colored_noise(n, rng, 0.0), 360 * kk, 4) * env_exp(n, 0.22)
    blast = burst(n, rng, 0.022, lo=300, hi=9000) * 1.5
    crack = burst(n, rng, 0.003, lo=2000, hi=15000) * 0.9
    ring = modal([420, 1130, 2100], [0.22, 0.14, 0.09], [0.45, 0.3, 0.18], n, rng, 0.01) * env_exp(n, 1.0, 0.0006, 0.06)
    hiss = highpass(colored_noise(n, rng, 0.5), 2500) * env_points(n, [(0, 0), (0.05, 0.16, 1), (1.6, 0.0, -2)])
    x = saturate(0.7 * sub + boom + blast + crack + 0.28 * ring + hiss + 0.4 * lowpass(colored_noise(n, rng, 2.0, lo=25, hi=140), 140) * env_exp(n, 0.8, 0.005), 1.5)
    tail = echo_taps(x, [(0.55, 0.20), (1.15, 0.11)], 1800)
    return finish(verb(x + tail, "water", 0.34), length, 0.6)


@recipe
def naval_bombard(rng, v):
    """Heavy bombardment gun: a half-second sub swell, colossal blast, rolling multi-tap echo over the sea."""
    return naval_gun(rng, v, k=0.78, length=4.2)


# ------------------------------------------------------------------------------------------------- indirect fire
@recipe
def howitzer_thump(rng, v):
    """Pressure thump, whistle-away, distant rolling echoes (spike reference recipe)."""
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


@recipe
def mortar_thunk(rng, v):
    """Hollow tube 'thunk': the round dropped down the barrel, a soft pop and a quiet whistle-away."""
    n = n_of(1.7)
    t = t_axis(n)
    kk = 1.0 + 0.07 * (v - 1)
    tube = modal([210 * kk, 470 * kk, 920 * kk], [0.05, 0.04, 0.03], [1.0, 0.55, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0006)
    thud = thump(n, 120 * kk, 48, 0.02, 0.10, drive=1.3)
    pop = burst(n, rng, 0.012, lo=300, hi=4500) * 1.2
    clink = modal([1900, 3300], [0.01, 0.007], [0.4, 0.2], n, rng, 0.02) * env_exp(n, 1.0, 0.0003, 0.0)
    whistle = sweep_filter(colored_noise(n, rng, 0.4, lo=400), 2600 * np.exp(-t / 0.5) + 700, "lp", 1.5, 2, 12)
    whistle *= env_points(n, [(0, 0), (0.1, 0.10, 1), (1.1, 0.0, -3)])
    x = saturate(0.8 * tube + 1.1 * thud + pop + 0.2 * clink + whistle, 1.5)
    return finish(verb(x, "outdoor", 0.30), 1.7, 0.3)


@recipe
def rocket_volley(rng, v):
    """Rocket barrage: four staggered ignitions with hissing whooshes streaking away (positional, mono)."""
    n = n_of(2.6)
    x = np.zeros(n)
    for i in range(4):
        at = 0.02 + i * 0.16 + rng.uniform(-0.02, 0.02)
        m = n - n_of(at)
        t = t_axis(m)
        ign = burst(m, rng, 0.03, lo=300, hi=6000) * 0.9 + thump(m, 150, 60, 0.03, 0.10) * 0.6
        motor = sweep_filter(colored_noise(m, rng, 0.8, lo=200, hi=10000), 500 + 3800 * np.exp(-((t - 0.25) / 0.45) ** 2), "lp", 1.2, 2, 14)
        motor *= env_points(m, [(0, 0), (0.05, 1, 1.5), (0.5, 0.7), (1.9, 0.0, -2.5)])
        fizz = highpass(crackle(m, rng, 700 * env_exp(m, 0.8) + 20), 2500) * 0.35 * env_exp(m, 0.9)
        place(x, saturate(ign + 0.75 * motor + fizz, 1.3), n_of(at), rng.uniform(0.7, 1.0))
    return finish(verb(x, "outdoor", 0.22), 2.6, 0.4)


# ------------------------------------------------------------------------------------------------- missiles
@recipe
def missile_launch(rng, v, size="mid", pitch_st=0.0):
    """Ignition pop, rising motor roar that recedes.  size: light | mid | heavy (scales length, pitch and rumble)."""
    L, cut0, rum = {"light": (1.8, 1.35, 0.55), "mid": (2.5, 1.0, 0.9), "heavy": (3.4, 0.72, 1.2)}[size]
    n = n_of(L)
    t = t_axis(n)
    motor = colored_noise(n, rng, 1.0, lo=120 * cut0, hi=9000)
    cut = np.where(t < 0.55, 250 + 3200 * (t / 0.55) ** 1.5, 3450 * np.exp(-np.maximum(t - 1.5, 0) / 1.4) + 500) * cut0
    motor = sweep_filter(motor, cut, "lp", 0.9, 2, 20)
    amp = env_points(n, [(0, 0), (0.10, 0.9, 1.5), (0.28, 1.0), (L * 0.55, 0.42, -1.5), (L - 0.05, 0.0, -2.5)])   # launch, then the round recedes
    rumble = colored_noise(n, rng, 2.0, lo=40, hi=220 * cut0) * amp * rum
    fizz = highpass(crackle(n, rng, 900 * amp + 30), 2200) * amp * 0.5
    pop = burst(n, rng, 0.03, lo=400, hi=4500) * 0.7 + thump(n, 130 * cut0, 55, 0.03, 0.10) * 0.5
    x = saturate(motor * amp * 0.9 + rumble + fizz + pop, 1.3)
    x = dsp.pitch(x, pitch_st) if pitch_st else x
    return finish(verb(x, "outdoor", 0.2), L, 0.4)


@recipe
def flak_pop(rng, v):
    """Flak burst: sharp airburst crack, metallic fragment scatter."""
    n = n_of(1.3)
    t = t_axis(n)
    kk = 1.0 + 0.06 * (v - 1)
    crack = burst(n, rng, 0.003, lo=1400 * kk, hi=14000) * 1.1
    thud = thump(n, 150 * kk, 62, 0.02, 0.10, drive=1.4)
    puff = burst(n, rng, 0.05, lo=250, hi=2600) * 0.8
    frag = highpass(crackle(n, rng, 900 * np.exp(-t / 0.18) + 20, 1.2), 2600) * 0.6
    ring = modal([2100 * kk, 3600 * kk, 5200 * kk], [0.05, 0.035, 0.02], [0.3, 0.2, 0.12], n, rng, 0.02) * env_exp(n, 1.0, 0.0005, 0.005)
    x = saturate(crack + thud + puff + frag + ring, 1.5)
    return finish(verb(x, "outdoor", 0.28), 1.3, 0.25)


# ------------------------------------------------------------------------------------------------- energy / special
@recipe
def beam_discharge(rng, v):
    """Beam start: quick rising whine, zap burst, descending FM, crackle, thump."""
    n = n_of(1.8)
    t = t_axis(n)
    tc = 0.015                      # fire feedback must be immediate: the zap starts at once
    fch = 300 + 2600 * np.clip(t / tc, 0, 1) ** 2
    charge = (saw(fch, n) * 0.5 + sine(fch * 2, n) * 0.2) * env_points(n, [(0, 0), (tc, 1, 2.5), (tc + 0.02, 0)])
    charge = lowpass(charge, 5000)
    zap = burst(n, rng, 0.06, lo=900, hi=9000, delay=tc)
    fmf = 4500 * np.exp(-np.maximum(t - tc, 0) / 0.14) + 380
    sweep = fm(fmf, 1.41, 5 * np.exp(-np.maximum(t - tc, 0) / 0.2), n) * env_exp(n, 0.28, 0.001, tc) * 0.7
    cr = highpass(crackle(n, rng, 900 * np.exp(-np.maximum(t - tc, 0) / 0.3) * (t > tc)), 1800) * 0.7
    low = thump(n, 110, 48, 0.04, 0.17, delay=tc, drive=1.5)
    x = saturate(charge * 0.8 + zap + sweep + cr + low, 1.5)
    return finish(verb(x, "hangar", 0.22), 1.8, 0.3)


@recipe
def beam_hum_loop(rng, v):
    """Beam sustain: periodic saws + sub + shimmer, snapped to whole cycles (seamless)."""
    T = 4.0
    n = n_of(T)
    f0 = snap_freq(110, T)
    detune = 1.0 + 0.004 * lfo(2 / T, n)
    x = 0.55 * saw(f0 * detune, n) + 0.40 * saw(f0 * 1.5 * (1 + 0.003 * lfo(3 / T, n, 0.3)), n) + 0.5 * sine(f0 / 2, n)
    x = lowpass(x, 2200, 4, circ=True)
    shimmer = colored_noise(n, rng, 0.0, lo=2200, hi=5200) * (0.5 + 0.5 * lfo(snap_freq(7, T), n)) * 0.18
    buzz = highpass(saw(snap_freq(120, T), n), 900, circ=True) * 0.05
    return x + shimmer + buzz


@recipe
def beam_end(rng, v):
    """Beam cut-off: falling whine, sputter, small thump."""
    n = n_of(1.1)
    t = t_axis(n)
    whine = (saw(1800 * np.exp(-t / 0.10) + 160, n) * 0.5 + sine(900 * np.exp(-t / 0.10) + 80, n)) * env_exp(n, 0.16, 0.001)
    spit = highpass(crackle(n, rng, 700 * np.exp(-t / 0.15) + 10), 2000) * 0.7
    low = thump(n, 100, 46, 0.03, 0.12, drive=1.4)
    x = saturate(lowpass(whine, 4500) * 0.8 + spit + low, 1.4)
    return finish(verb(x, "hangar", 0.18), 1.1, 0.25)


@recipe
def rail_crack(rng, v):
    """Supersonic crack + FM zing + ring + whump, with slapping echoes."""
    n = n_of(2.4)
    t = t_axis(n)
    kk = 1.0 + 0.05 * (v - 1)
    crack = burst(n, rng, 0.0012, lo=3200, hi=16000, attack=0.0002) * 1.3
    zing = fm((1800 + 3400 * np.exp(-t / 0.07)) * kk, 1.41, 6 * np.exp(-t / 0.07), n) * env_exp(n, 0.09, 0.0008) * 0.5
    ring = modal([2200, 3700, 5900, 8300], [0.42, 0.3, 0.2, 0.15], [0.25, 0.2, 0.15, 0.1], n, rng, 0.004) * env_exp(n, 2.0, 0.0006)
    whump = thump(n, 100 * kk, 44, 0.03, 0.13, drive=1.4) * 0.9
    body = burst(n, rng, 0.035, lo=250, hi=2600) * 0.9
    x = saturate(crack + zing + ring + whump + body, 1.4)
    slap = np.zeros(n)
    for d, g in ((0.13, 0.28), (0.29, 0.16), (0.52, 0.09)):
        place(slap, highpass(lowpass(x, 5000 * (1 - 0.3 * d)), 1500) * g, n_of(d))
    return finish(verb(x + slap, "hangar", 0.3), 2.4, 0.4)


@recipe
def emp_zap(rng, v):
    """Thoom + arc crackle + sample-and-hold FM sparks + falling power-down whine."""
    n = n_of(2.2)
    t = t_axis(n)
    pulse = thump(n, 92, 34, 0.08, 0.32, drive=1.6)
    arcs = highpass(crackle(n, rng, 1400 * np.exp(-t / 0.45) + 60, 1.2), 2500) * 1.1
    hold = int(0.03 * SR)
    sh = np.repeat(rng.uniform(1200, 6500, n // hold + 2), hold)[:n]
    sparks = fm(sh, 2.13, 8.0, n) * env_exp(n, 0.55, 0.002) * (0.4 + 0.6 * (np.abs(arcs) > 0.02)) * 0.28
    down = sine(1900 * np.exp(-t / 0.35) + 90, n) * env_exp(n, 0.5, 0.004) * 0.3
    ring = sine(220 * t + 40 * np.sin(2 * np.pi * 11 * t), n) * env_exp(n, 0.3) * 0.2
    x = saturate(pulse + arcs + sparks + down + ring, 1.4)
    return finish(verb(x, "plate", 0.22), 2.2, 0.4)


# ------------------------------------------------------------------------------------------------- naval / air-dropped
@recipe
def torpedo_launch(rng, v):
    """Compressed-air launch: a pressurised 'whump', splash, then the screw cavitating away underwater."""
    n = n_of(3.0)
    t = t_axis(n)
    kk = 1.0 + 0.06 * (v - 1)
    whump = thump(n, 95 * kk, 38, 0.05, 0.22, drive=1.4)
    air = burst(n, rng, 0.09, lo=200, hi=3500) * 0.9
    splash = burst(n, rng, 0.14, lo=500, hi=7000, delay=0.10) * 0.6
    screw = sweep_filter(colored_noise(n, rng, 0.8, lo=100, hi=4000), 700 + 900 * np.exp(-t / 1.4), "lp", 0.9, 2, 12)
    screw *= env_points(n, [(0, 0), (0.25, 0.0), (0.5, 0.42, 1.5), (2.0, 0.28), (2.9, 0.0, -2)])
    whirr = sine(snap_freq(260, 3.0) * (1 + 0.03 * np.sin(2 * np.pi * 9 * t)), n) * env_points(n, [(0, 0), (0.4, 0.0), (0.8, 0.10, 1), (2.6, 0.06), (2.95, 0)])
    bub = highpass(crackle(n, rng, 260 * env_exp(n, 1.2) + 10), 700) * 0.4 * env_exp(n, 1.3, 0.01, 0.1)
    x = saturate(whump + air + splash + screw + whirr + bub, 1.4)
    return finish(verb(x, "water", 0.24), 3.0, 0.5)


@recipe
def depth_charge_drop(rng, v):
    """Rack release clunk, the barrel's plop into the sea and a fizzing descent."""
    n = n_of(2.0)
    t = t_axis(n)
    clunk = modal([260, 640, 1500], [0.07, 0.05, 0.03], [1.0, 0.6, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0005) + thump(n, 130, 60, 0.02, 0.06) * 0.8
    plop_at = 0.34
    plop = fm(fsweep(n, 700, 160, 0.06), 1.5, 2.5 * np.exp(-np.maximum(t - plop_at, 0) / 0.05), n) * env_exp(n, 0.10, 0.002, plop_at)
    splash = burst(n, rng, 0.12, lo=350, hi=6500, delay=plop_at) * 0.9
    col = lowpass(colored_noise(n, rng, 1.0), 700) * env_points(n, [(0, 0), (plop_at, 0), (plop_at + 0.1, 0.5, 1), (1.5, 0.15), (1.95, 0, -2)])
    bub = highpass(crackle(n, rng, 380 * env_exp(n, 0.9, 0.0, plop_at) + 5), 600) * 0.4
    x = saturate(clunk + plop * 0.7 + splash + col + bub, 1.3)
    return finish(verb(x, "water", 0.2), 2.0, 0.35)


@recipe
def bomb_release(rng, v):
    """Bomb shackles clunk open and the fins whoosh away (the falling whistle is a separate projectile sound)."""
    n = n_of(1.8)
    t = t_axis(n)
    clunk = modal([190, 520, 1250, 2200], [0.08, 0.06, 0.04, 0.02], [1.0, 0.65, 0.35, 0.2], n, rng, 0.012) * env_exp(n, 1.0, 0.0004)
    thud = thump(n, 115, 55, 0.02, 0.09, drive=1.3)
    latch = burst(n, rng, 0.006, lo=900, hi=7000, delay=0.0) * 1.0
    whoosh = sweep_filter(colored_noise(n, rng, 0.6, lo=250, hi=7000), 600 + 2600 * np.exp(-((t - 0.45) / 0.35) ** 2), "lp", 1.0, 2, 14)
    whoosh *= env_points(n, [(0, 0), (0.1, 0.0), (0.4, 0.55, 1.5), (1.4, 0.0, -2)])
    x = saturate(clunk + thud + latch + whoosh, 1.35)
    return finish(verb(x, "hangar", 0.2), 1.8, 0.3)


# ------------------------------------------------------------------------------------------------- infantry heavy
@recipe
def canister_blast(rng, v):
    """Canister shot: a wide muzzle blast that spits a spray of pellets (a rattle of tiny ticks)."""
    n = n_of(1.5)
    t = t_axis(n)
    kk = 1.0 + 0.06 * (v - 1)
    blast = burst(n, rng, 0.012, lo=200, hi=6000) * 1.2
    crack = burst(n, rng, 0.003, lo=1500 * kk, hi=14000) * 0.9
    thud = thump(n, 130 * kk, 55, 0.02, 0.10, drive=1.5)
    pellets = np.zeros(n)
    for _ in range(46):
        at = 0.01 + abs(rng.normal(0, 0.09))
        m = n_of(0.03)
        p = burst(m, rng, 0.002, lo=2500, hi=11000) + modal([rng.uniform(2200, 5200)], [0.006], [0.4], m, rng)
        place(pellets, p * rng.uniform(0.15, 0.5), n_of(at))
    x = saturate(blast + crack + thud + pellets, 1.6)
    return finish(verb(x, "field", 0.26), 1.5, 0.3)


@recipe
def grenade_thump(rng, v):
    """Grenade launcher: hollow 'thoonk' with a spring twang and a distant pop."""
    n = n_of(1.3)
    t = t_axis(n)
    kk = 1.0 + 0.07 * (v - 1)
    thoonk = fm(fsweep(n, 260 * kk, 95, 0.03), 1.0, 1.4 * np.exp(-t / 0.03), n) * env_exp(n, 0.10, 0.0006)
    tube = modal([310, 660, 1250], [0.06, 0.045, 0.03], [0.8, 0.5, 0.3], n, rng, 0.01) * env_exp(n, 1.0, 0.0005)
    pop = burst(n, rng, 0.02, lo=300, hi=5000) * 0.9
    body = thump(n, 120 * kk, 50, 0.02, 0.09, drive=1.4)
    x = saturate(0.9 * thoonk + 0.5 * tube + pop + body, 1.5)
    return finish(verb(x, "outdoor", 0.28), 1.3, 0.25)


@recipe
def breach_bang(rng, v):
    """Breaching charge: one dense, short, flat bang with a splintering tail (no reverb wash)."""
    n = n_of(1.4)
    t = t_axis(n)
    kk = 1.0 + 0.05 * (v - 1)
    bang = burst(n, rng, 0.016, lo=200, hi=9000) * 1.8
    crack = burst(n, rng, 0.002, lo=2200, hi=15000) * 1.0
    thud = thump(n, 120 * kk, 44, 0.03, 0.22, drive=1.8)
    splint = highpass(crackle(n, rng, 500 * np.exp(-t / 0.22) + 10), 1500) * 0.6 * env_exp(n, 0.5, 0.005, 0.03)
    x = saturate(1.2 * bang + crack + 0.7 * thud + splint, 1.7)
    return finish(verb(x, "small", 0.16), 1.4, 0.3)


# ------------------------------------------------------------------------------------------------- flavours
@recipe
def weapon_flavour(rng, v, base="rifle_shot", base_params=None, fx=None):
    """Faction flavour of a base weapon recipe (audio spec 5.15): base recipe, then pitch/brightness/tail/drive/layer."""
    x = RECIPES[base](rng, v, **(base_params or {}))
    y = apply_flavour(dsp.to_mono(x), rng, fx)
    return y
