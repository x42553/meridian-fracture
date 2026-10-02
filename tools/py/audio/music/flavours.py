"""flavours.py - everything that makes one faction's music differ from another's (no code forks).

  SCALES / FLAVOURS   tempo, tonic, mode, kit, bass / pad / lead timbre, swing, progressions, drum feel (audio spec 5.15)
  FEELS               16-step drum + bass grids per feel, three intensity tiers each
  drum_hit / bass_note / pad_chord / lead_note   the instrument voices (cached, deterministic)

Pattern grid characters: X accent, x normal, o ghost, . rest; bass grids: digits are intervals ('0' root, '1' octave up,
'5' fifth, '4' fourth, '7' seventh), '-' holds the previous note.
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

import numpy as np

import dsp
from dsp import (Array, bandpass, biquad, colored_noise, env_adsr, env_exp, fit, highpass, karplus_strong, lowpass, modal,
                 n_of, saturate, saw, sine, square, sweep_filter, t_axis, fm)

SCALES: dict[str, tuple[int, ...]] = {
    "aeolian": (0, 2, 3, 5, 7, 8, 10), "phrygian": (0, 1, 3, 5, 7, 8, 10), "phrygian_dominant": (0, 1, 4, 5, 7, 8, 10),
    "harmonic_minor": (0, 2, 3, 5, 7, 8, 11), "dorian": (0, 2, 3, 5, 7, 9, 10), "mixolydian": (0, 2, 4, 5, 7, 9, 10),
    "lydian": (0, 2, 4, 6, 7, 9, 11), "pentatonic_minor": (0, 3, 5, 7, 10), "hirajoshi": (0, 2, 3, 7, 8), "major": (0, 2, 4, 5, 7, 9, 11),
}
BARS = {"combat": 24, "calm": 12}
BAR_BEATS = 4
CALM_RATIO = 0.6


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


@dataclass(frozen=True)
class Flavour:
    name: str
    bpm: float           # combat tempo; calm = round(0.6 * bpm)
    root: int            # MIDI tonic (bass register, 45 = A2)
    mode: str            # key of SCALES
    kit: str             # "electro" | "taiko" | "brush"
    bass: str            # "saw_sub" | "fm" | "pluck"
    pad: str             # "supersaw" | "glass" | "choir"
    lead: str            # "saw_lead" | "brass" | "pluck" | "bell" | "reed"
    swing: float = 0.0   # 0..0.33, delays odd 16ths
    seed: int = 1
    reverb: str = "hall"
    feel: str = "four_floor"
    prog_combat: tuple[int, ...] = (0, 0, 5, 6, 0, 0, 3, 4)   # chord root degree per bar of an 8-bar cycle
    prog_calm: tuple[int, ...] = (0, 5, 3, 6, 5, 4)           # one chord per 2 bars (12 bars)
    lead_rhythm: str = "flow"

    def tempo(self, style: str) -> float:
        return float(self.bpm if style == "combat" else round(self.bpm * CALM_RATIO))


FLAVOURS: dict[str, Flavour] = {
    "napc": Flavour("napc", 138.0, 45, "aeolian", "electro", "saw_sub", "supersaw", "brass", seed=11, feel="four_floor",
                    prog_combat=(0, 0, 5, 6, 0, 0, 3, 4), prog_calm=(0, 5, 3, 6, 5, 4), lead_rhythm="anthem"),
    "nec": Flavour("nec", 128.0, 38, "dorian", "electro", "fm", "glass", "pluck", seed=12, feel="broken",
                   prog_combat=(0, 3, 0, 6, 0, 3, 4, 6), prog_calm=(0, 3, 6, 3, 0, 4), lead_rhythm="precise"),
    "olm": Flavour("olm", 126.0, 40, "phrygian_dominant", "taiko", "pluck", "choir", "pluck", swing=0.10, seed=13, feel="taiko_roll",
                   prog_combat=(0, 1, 0, 0, 5, 1, 0, 3), prog_calm=(0, 1, 0, 5, 1, 0), lead_rhythm="ornate"),
    "def": Flavour("def", 132.0, 36, "harmonic_minor", "taiko", "saw_sub", "choir", "brass", seed=14, feel="march",
                   prog_combat=(0, 0, 5, 4, 0, 0, 3, 4), prog_calm=(0, 5, 3, 4, 0, 4), lead_rhythm="anthem"),
    "pd": Flavour("pd", 140.0, 43, "pentatonic_minor", "electro", "fm", "glass", "bell", seed=15, feel="half_drive",
                  prog_combat=(0, 2, 3, 4, 0, 2, 4, 3), prog_calm=(0, 3, 2, 4, 0, 3), lead_rhythm="flow"),
    "han": Flavour("han", 120.0, 38, "hirajoshi", "taiko", "pluck", "choir", "pluck", seed=16, feel="sparse_pulse",
                   prog_combat=(0, 0, 2, 1, 0, 0, 3, 2), prog_calm=(0, 2, 3, 2, 0, 1), lead_rhythm="staccato"),
    "ae": Flavour("ae", 126.0, 41, "dorian", "taiko", "pluck", "glass", "bell", swing=0.16, seed=17, feel="polyrhythm",
                  prog_combat=(0, 6, 3, 4, 0, 6, 3, 5), prog_calm=(0, 3, 6, 4, 0, 3), lead_rhythm="staccato"),
    "sap": Flavour("sap", 132.0, 42, "phrygian_dominant", "electro", "fm", "glass", "reed", swing=0.08, seed=18, feel="tabla",
                   prog_combat=(0, 0, 1, 0, 5, 5, 1, 0), prog_calm=(0, 1, 5, 1, 0, 3), lead_rhythm="ornate"),
    # the global menu theme: generic hero flavour (24 bars @ 100 BPM)
    "menu": Flavour("menu", 100.0, 40, "aeolian", "taiko", "saw_sub", "supersaw", "brass", seed=21, feel="half_drive",
                    prog_combat=(0, 5, 2, 6, 0, 5, 3, 4), prog_calm=(0, 5, 3, 4, 0, 4), lead_rhythm="anthem"),
}
FACTION_ORDER = ("napc", "nec", "olm", "def", "pd", "han", "ae", "sap")


def length_samples(bpm: float, bars: int, bar_beats: int = BAR_BEATS) -> int:
    """Identical to validate_audio V-AUD-21: round(bars * bar_beats * 60 / bpm * 44100)."""
    return round(bars * bar_beats * 60.0 / bpm * 44100)


# ------------------------------------------------------------------------------------------------ drum feels
FEELS: dict[str, dict] = {
    "four_floor": dict(   # napc: punchy, heroic four-on-the-floor
        kick=("X...x...X...x...", "X...X...X...X...", "X..xX...X..xX.x."),
        snare=("........X.......", "....X.......X...", "....X.......X..o"),
        hat=("..x...x...x...x.", "x.x.x.x.x.x.x.x.", "xoxoxoxoxoxoxoxo"),
        open=("", "..............X.", "......X.......X."), perc=("", "", "....o..o....o..."), perc_kind="rim",
        bass=("0-0-0-0-0-0-0-5-", "0-0-1-0-0-0-1-5-", "0-1-0-1-0-1-0-5-"),
        calm_perc=("", "..............o.")),
    "broken": dict(       # nec: dry, crisp, syncopated
        kick=("X..x......x...x.", "X..x..X...x.X...", "X..x..X..xx.X..x"),
        snare=("........X.......", "....X.......X...", "....X..o....X..o"),
        hat=("x.x.x.x.x.x.x.x.", "xox.xox.xox.xox.", "xxoxxxoxxxoxxxox"),
        open=("", "", "...........X...."), perc=("", "..o...o...o...o.", "o..o..o..o..o..o"), perc_kind="clave",
        bass=("0---0-.0---0-.5-", "0-.0-.0-5-.0-.1-", "0.0.1.0.5.0.1.0.5"[:16]),
        calm_perc=("", "......o.....o...")),
    "taiko_roll": dict(   # olm: drum-circle rolls, swung, no hats
        kick=("X..x....X.x.....", "X..x..x.X.x.x...", "X.xx..x.X.xxx.x."),
        snare=("", "............X...", "....o...X..o..X."),
        hat=("", "", ""), open=("", "", ""),
        perc=("..o...o...o...o.", "o.o.o.o.o.o.o.o.", "xoxoxoxoxoxoxoxo"), perc_kind="shaker",
        bass=("0-----0-----5---", "0---0---0-5-0---", "0-0-0---0-5-1-0-"),
        calm_perc=("..o...o.......", "o...o...o...o...")),
    "march": dict(        # def: heavy marching pulse
        kick=("X.......X.......", "X.......X..x....", "X..x....X..x..x."),
        snare=("", "..o...o...o...o.", "..x...x...x...xx"),
        hat=("", "....x.......x...", "..x...x...x...x."), open=("", "", ""),
        perc=("", "X.......X.......", "X..o....X..o...."), perc_kind="tom",
        bass=("0---------------", "0-0-0---0-0-0---", "0-0-5-0-0-0-4-5-"),
        calm_perc=("X...............", "X.......o.......")),
    "half_drive": dict(   # pd: half-time backbeat, airy 8th hats
        kick=("X.......x.......", "X.....o.x..x....", "X.....x.x..xx..."),
        snare=("", "........X.......", "........X......x"),
        hat=("x.x.x.x.x.x.x.x.", "xox.xox.xox.xox.", "xoxoxoxoxoxoxoxo"), open=("", "", "..............X."),
        perc=("", "", "o..o..o..o..o.o."), perc_kind="rim",
        bass=("0-------0-------", "0---0-5-0---0-7-", "0-0-0-5-0-0-1-7-"),
        calm_perc=("", "..o...o...o...o.")),
    "sparse_pulse": dict( # han: high, sharp, electronic sparse pulse
        kick=("X..x......x.....", "X..x......x..x..", "X..x..x...x..x.."),
        snare=("", "........X.......", "....o...X...o..."),
        hat=("x.x.x.x.x.x.x.x.", "xxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxx"), open=("", "", ""),
        perc=("..o...o...o...o.", "..x...x...x..x..", "..x..x..x..x..x."), perc_kind="rim",
        bass=("0-----0-------5-", "0---0---0-----5-", "0-0---0-5-0---5-"),
        calm_perc=("..o.........o...", "..o...o...o...o.")),
    "polyrhythm": dict(   # ae: 3-against-4 clank / kalimba clave
        kick=("X.....X.....X...", "X.....X..x..X...", "X..x..X..x..X.x."),
        snare=("", "", "........X......."),
        hat=("", "x.x.x.x.x.x.x.x.", "x.x.x.x.x.x.x.x."), open=("", "", ""),
        perc=("x..x..x..x..x..x", "x..x..x..x..x..x", "x.xx.xx.xx.xx.xx"), perc_kind="clave",
        bass=("0-----5-----0---", "0-----5---0-0-5-", "0-0---5-0-0-5-1-"),
        calm_perc=("x..x..x..x..x...", "x..x..x..x..x..x")),
    "tabla": dict(        # sap: tabla-like tuned hits over a steady pulse
        kick=("X....x..X...x...", "X....x..X..xx...", "X..x.x..X..xx.x."),
        snare=("", "", "........X......."),
        hat=("", "..x...x...x...x.", "x.x.x.x.x.x.x.x."), open=("", "", ""),
        perc=("..o..o..o..o..o.", "..x.o.x...x.o.x.", "..x.ox..x.x.ox.x"), perc_kind="tabla",
        bass=("0---0---0---5---", "0-0-0---0-5-0---", "0-0-1-0-0-5-5-1-"),
        calm_perc=("..o.....o.......", "..o..o..o..o....")),
}
for _f in FEELS.values():           # patterns are exactly 16 steps
    for _k in ("kick", "snare", "hat", "open", "perc"):
        _f[_k] = tuple((s + "." * 16)[:16] for s in _f[_k])
    _f["bass"] = tuple((s + "." * 16)[:16] for s in _f["bass"])
    _f["calm_perc"] = tuple((s + "." * 16)[:16] for s in _f["calm_perc"])

LEAD_RHYTHMS: dict[str, list[list[tuple[int, int]]]] = {
    "flow": [[(0, 3), (3, 1), (4, 2), (6, 2), (8, 3), (11, 1), (12, 4)], [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4)],
             [(0, 4), (4, 2), (6, 2), (8, 4), (12, 2), (14, 2)], [(0, 1), (1, 1), (2, 2), (4, 4), (8, 1), (9, 1), (10, 2), (12, 4)]],
    "anthem": [[(0, 6), (6, 2), (8, 4), (12, 4)], [(0, 4), (4, 4), (8, 6), (14, 2)], [(0, 3), (3, 1), (4, 4), (8, 4), (12, 4)],
               [(0, 8), (8, 2), (10, 2), (12, 4)]],
    "precise": [[(0, 2), (2, 2), (4, 2), (7, 1), (8, 2), (10, 2), (12, 4)], [(0, 1), (3, 1), (6, 2), (8, 1), (11, 1), (12, 4)],
                [(0, 2), (3, 2), (6, 2), (8, 2), (11, 1), (13, 3)]],
    "ornate": [[(0, 2), (2, 1), (3, 1), (4, 3), (7, 1), (8, 2), (10, 1), (11, 1), (12, 4)], [(0, 3), (3, 1), (4, 1), (5, 1), (6, 2), (8, 4), (12, 4)],
               [(0, 1), (1, 1), (2, 2), (5, 3), (8, 2), (10, 2), (12, 4)]],
    "staccato": [[(0, 1), (2, 1), (3, 1), (6, 2), (8, 1), (10, 1), (11, 1), (14, 2)], [(0, 2), (3, 1), (4, 1), (7, 1), (8, 2), (11, 1), (12, 2), (14, 2)],
                 [(0, 1), (1, 1), (4, 2), (6, 1), (8, 1), (9, 1), (12, 3)]],
}


# ------------------------------------------------------------------------------------------------ voices
def _rng(*key) -> np.random.Generator:
    return dsp.rng_for("music:" + ":".join(str(k) for k in key))


def _ramp(n: int, ms: float = 0.4) -> Array:
    """Onset ramp for modal hits (their random start phase would otherwise begin with a step)."""
    return np.clip(np.arange(n) / max(1.0, ms * 0.001 * dsp.SR), 0.0, 1.0)


@lru_cache(maxsize=None)
def drum_hit(kit: str, kind: str, v: int = 0) -> Array:
    rng = _rng(kit, kind, v)
    if kind == "kick":
        n = n_of(0.5)
        if kit == "taiko":
            b = sine(52 + (98 - 52) * np.exp(-t_axis(n) / 0.05), n) * env_exp(n, 0.30, 0.002)
            b += 0.5 * bandpass(colored_noise(n, rng), 180, 900) * env_exp(n, 0.045)
            return saturate(b, 1.6)
        b = sine(47 + (150 - 47) * np.exp(-t_axis(n) / 0.030), n) * env_exp(n, 0.19, 0.001)
        b += 0.25 * colored_noise(n, rng, 0.0, 1800, 9000) * env_exp(n, 0.002, 0.0002)
        return saturate(b, 2.2 if kit == "electro" else 1.3) * (1.0 if kit == "electro" else 0.6)
    if kind == "snare":
        n = n_of(0.4)
        if kit == "taiko":
            return saturate(0.8 * bandpass(colored_noise(n, rng), 400, 2600) * env_exp(n, 0.07) + 0.6 * sine(205, n) * env_exp(n, 0.10), 1.4)
        tone = sine(180 + 70 * np.exp(-t_axis(n) / 0.02), n) * env_exp(n, 0.09) * 0.6
        noise = colored_noise(n, rng, 0.0, 1500, 10500) * env_exp(n, 0.13 if kit == "electro" else 0.07)
        return saturate(tone + noise + 0.4 * colored_noise(n, rng, 0.0, 3000, 12000) * env_exp(n, 0.003), 1.5) * (0.9 if kit == "electro" else 0.45)
    if kind in ("hat", "open"):
        n = n_of(0.5 if kind == "open" else 0.16)
        x = sum(square(f * (1.0 + 0.01 * v), n) for f in (205.3, 304.4, 369.6, 522.7, 800.0, 540.0)) / 6.0
        x = highpass(x, 7000, 4)
        return x * env_exp(n, 0.20 if kind == "open" else 0.028, 0.0006) * (0.6 if kit == "electro" else 0.35)
    if kind == "shaker":
        n = n_of(0.2)
        return colored_noise(n, rng, 0.0, 5000, 14000) * env_exp(n, 0.045, 0.012) * 0.4
    if kind == "tom":
        n = n_of(0.6)
        f0 = (70, 92, 118)[v % 3]
        return saturate(sine(f0 + f0 * 0.5 * np.exp(-t_axis(n) / 0.06), n) * env_exp(n, 0.32, 0.002) + 0.3 * bandpass(colored_noise(n, rng), 150, 700) * env_exp(n, 0.05), 1.5)
    if kind == "rim":
        n = n_of(0.12)
        return modal([1700, 480, 3100], [0.012, 0.02, 0.008], [0.6, 0.8, 0.3], n, rng, 0.01) * _ramp(n) * 0.7
    if kind == "clave":      # tuned wood block, three pitches
        n = n_of(0.16)
        f0 = (1250.0, 1560.0, 1010.0)[v % 3]
        return modal([f0, f0 * 2.31, f0 * 3.7], [0.028, 0.014, 0.008], [0.9, 0.35, 0.15], n, rng, 0.004) * _ramp(n) * 0.75
    if kind == "tabla":      # v even = bayan (low, pitch glide up), odd = dayan (tonal ring)
        if v % 2 == 0:
            n = n_of(0.34)
            return saturate(sine(96 + 44 * (1 - np.exp(-t_axis(n) / 0.09)), n) * env_exp(n, 0.16, 0.002) + 0.12 * colored_noise(n, rng, 0.0, 300, 1500) * env_exp(n, 0.02), 1.4) * 0.9
        n = n_of(0.30)
        f0 = 395.0 + 36.0 * (v // 2 % 3)
        return modal([f0, f0 * 2.0, f0 * 3.02], [0.14, 0.09, 0.05], [0.9, 0.5, 0.3], n, rng, 0.002) * env_exp(n, 1.0, 0.0008) * _ramp(n) * 0.8
    raise ValueError(kind)


@lru_cache(maxsize=None)
def bass_note(kind: str, midi: int, dur_ms: int) -> Array:
    f = hz(midi)
    n = n_of(dur_ms / 1000.0)
    rng = _rng("bass", kind, midi, dur_ms)
    env = env_adsr(n, 0.004, 0.10, 0.75, min(0.06, n / dsp.SR * 0.5))
    t = t_axis(n)
    if kind == "fm":
        x = fm(f, 1.0, 2.6 * np.exp(-t / 0.14) + 0.7, n) * 0.9 + 0.5 * sine(f, n)
    elif kind == "pluck":
        ks = karplus_strong(f * 2, n / dsp.SR, rng, 0.5 ** (1.0 / (f * 2 * 0.3)), 0.6)
        x = 0.9 * lowpass(fit(ks, n), 900) + 0.9 * sine(f, n) * np.exp(-t / 0.5)
    else:  # saw_sub
        x = lowpass(saw(f, n) * 0.55, 700 + 6 * f, 2, 1.3) + 0.95 * sine(f, n)
    return saturate(x * env, 1.6)


@lru_cache(maxsize=None)
def pad_chord(kind: str, midis: tuple[int, ...], dur_ms: int) -> Array:
    n = n_of(dur_ms / 1000.0)
    rng = _rng("pad", kind, midis, dur_ms)
    t = t_axis(n)
    L, R = np.zeros(n), np.zeros(n)
    for vi, m in enumerate(midis):
        f = hz(m)
        if kind == "glass":
            for j in range(3):
                fj = f * 2.0 ** (((j - 1) * 5) / 1200)
                v = fm(fj, 2.0, 1.1 + 0.6 * np.sin(2 * np.pi * (0.13 + 0.05 * j) * t + vi), n) * 0.5
                pn = (-0.7, 0.0, 0.7)[j]
                L += v * np.cos((pn + 1) * np.pi / 4) * 0.7
                R += v * np.sin((pn + 1) * np.pi / 4) * 0.7
        else:
            vib = 1.0 + (0.004 * np.sin(2 * np.pi * 5.1 * t) if kind == "choir" else 0.0)
            for j, cents in enumerate((-12, -6, 0, 6, 12)):
                v = saw(f * vib * 2.0 ** (cents / 1200), n, rng.random())
                pn = -0.8 + 1.6 * j / 4
                L += v * np.cos((pn + 1) * np.pi / 4) * 0.35
                R += v * np.sin((pn + 1) * np.pi / 4) * 0.35
    st = np.stack([L, R], axis=1)
    a = min(0.9, 0.35 * n / dsp.SR)
    r = min(1.0, 0.3 * n / dsp.SR)
    env = env_adsr(n, a, 0.4, 0.85, r)
    cut = np.interp(t, [0, a, n / dsp.SR - r, n / dsp.SR], [500, 2600, 2000, 900])
    st = sweep_filter(st, cut, "lp", 0.9, 2, 10)
    if kind == "choir":
        st = biquad(biquad(st, "peak", 700, 2.5, 6.0), "peak", 1150, 3.0, 5.0)
    return st * env[:, None]


@lru_cache(maxsize=None)
def lead_note(kind: str, midi: int, dur_ms: int, vel: int) -> Array:
    f = hz(midi)
    n = n_of(dur_ms / 1000.0)
    rng = _rng("lead", kind, midi, dur_ms)
    t = t_axis(n)
    g = vel / 100.0
    vib = 1.0 + 0.006 * np.clip((t - 0.12) / 0.25, 0, 1) * np.sin(2 * np.pi * 5.4 * t)
    if kind == "pluck":
        ks = karplus_strong(f, max(n / dsp.SR, 0.5), rng, 0.5 ** (1.0 / (f * 0.42)), 0.9)
        x = fit(ks, n) * 1.3
        x = x * env_adsr(n, 0.001, 0.05, 1.0, min(0.12, n / dsp.SR * 0.4))
    elif kind == "bell":
        x = (fm(f, 3.5, 3.0 * np.exp(-t / 0.28) + 0.2, n) * env_exp(n, 0.55, 0.002) + 0.3 * sine(f * 2, n) * env_exp(n, 0.3, 0.002))
    elif kind == "brass":
        v = sum(saw(f * vib * 2.0 ** (c / 1200), n, rng.random()) for c in (-5, 0, 5)) / 3.0
        cut = np.interp(t, [0, 0.09, 0.4, n / dsp.SR], [500, 3400, 2000, 1500])
        x = sweep_filter(v, cut, "lp", 1.0, 2, 8) * env_adsr(n, 0.05, 0.12, 0.85, min(0.1, n / dsp.SR * 0.4))
    elif kind == "reed":
        v = square(f * vib, n, 0.32) * 0.55 + saw(f * vib, n) * 0.35
        x = biquad(biquad(v, "peak", 900, 2.0, 7.0), "peak", 2100, 2.0, 5.0)
        x = lowpass(x, 4200) * env_adsr(n, 0.02, 0.1, 0.8, min(0.09, n / dsp.SR * 0.4))
    else:  # saw_lead
        v = saw(f * vib, n, rng.random()) * 0.6 + square(f * vib * 1.004, n, 0.5) * 0.3
        cut = np.interp(t, [0, 0.03, 0.3, n / dsp.SR], [900, 4200, 1800, 1300])
        x = sweep_filter(v, cut, "lp", 1.2, 2, 8) * env_adsr(n, 0.008, 0.10, 0.8, min(0.08, n / dsp.SR * 0.4))
    return x * g


def scale_note(f: Flavour, deg: int) -> int:
    sc = SCALES[f.mode]
    return f.root + sc[deg % len(sc)] + 12 * (deg // len(sc))
