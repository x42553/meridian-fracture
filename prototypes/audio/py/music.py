"""music.py - algorithmic layered-stem music (numpy only, built on dsp.py).

A track = Flavour (tempo/scale/timbre hooks) + style ("combat" | "calm") + bar count.  arrange() renders four stems
(drums, bass, pads, lead) into equal-length stereo buffers.  Everything is rendered CIRCULARLY (note tails wrap to the
loop start, reverb/echo are circular convolutions), so the loop point is seamless by construction; stems share one
master gain so their sum is the reference mix and the game can crossfade layers freely.
"""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

import numpy as np

import dsp
from dsp import (SR, Array, bandpass, biquad, colored_noise, env_adsr, env_exp, fit, highpass, karplus_strong, lowpass,
                 n_of, place, saturate, saw, sine, square, sweep_filter, t_axis, fm, modal, reverb, echo, widen, pan)

SCALES: dict[str, tuple[int, ...]] = {
    "aeolian": (0, 2, 3, 5, 7, 8, 10), "phrygian": (0, 1, 3, 5, 7, 8, 10), "phrygian_dominant": (0, 1, 4, 5, 7, 8, 10),
    "harmonic_minor": (0, 2, 3, 5, 7, 8, 11), "dorian": (0, 2, 3, 5, 7, 9, 10), "mixolydian": (0, 2, 4, 5, 7, 9, 10),
    "lydian": (0, 2, 4, 6, 7, 9, 11), "pentatonic_minor": (0, 3, 5, 7, 10), "hirajoshi": (0, 2, 3, 7, 8), "major": (0, 2, 4, 5, 7, 9, 11),
}


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


@dataclass(frozen=True)
class Flavour:
    """Per-faction hooks.  Everything that makes two factions sound different lives here (no code forks)."""
    name: str
    bpm: float
    root: int            # MIDI tonic (bass register, e.g. 45 = A2)
    mode: str            # key of SCALES
    kit: str             # "electro" | "taiko" | "brush"
    bass: str            # "saw_sub" | "fm" | "pluck"
    pad: str             # "supersaw" | "glass" | "choir"
    lead: str            # "saw_lead" | "brass" | "pluck" | "bell" | "reed"
    swing: float = 0.0   # 0..0.33, delays odd 16ths
    seed: int = 1
    reverb: str = "hall"


FLAVOURS: dict[str, Flavour] = {
    "default": Flavour("default", 140.0, 45, "aeolian", "electro", "saw_sub", "supersaw", "saw_lead"),
    "calm": Flavour("calm", 84.0, 38, "dorian", "brush", "pluck", "glass", "bell", seed=7),
    "napc": Flavour("napc", 138.0, 45, "aeolian", "electro", "saw_sub", "supersaw", "brass", seed=11),
    "nec": Flavour("nec", 128.0, 38, "dorian", "electro", "fm", "glass", "pluck", seed=12),
    "olm": Flavour("olm", 126.0, 40, "phrygian_dominant", "taiko", "pluck", "choir", "pluck", swing=0.10, seed=13),
    "def": Flavour("def", 132.0, 36, "harmonic_minor", "taiko", "saw_sub", "choir", "brass", seed=14),
    "pd": Flavour("pd", 140.0, 43, "pentatonic_minor", "electro", "fm", "glass", "bell", seed=15),
    "han": Flavour("han", 120.0, 38, "hirajoshi", "taiko", "pluck", "choir", "pluck", seed=16),
    "ae": Flavour("ae", 126.0, 41, "dorian", "taiko", "pluck", "glass", "bell", swing=0.16, seed=17),
    "sap": Flavour("sap", 132.0, 42, "phrygian_dominant", "electro", "fm", "glass", "reed", swing=0.08, seed=18),
}


class Grid:
    def __init__(self, bpm: float, bars: int, swing: float = 0.0):
        self.spb = SR * 60.0 / bpm
        self.bars = bars
        self.length = int(round(bars * 4 * self.spb))
        self.swing = swing

    def at(self, step16: float) -> int:
        s = step16 + (self.swing * 0.5 if int(step16) % 2 == 1 else 0.0)
        return int(round(s * self.spb / 4.0))

    def sec(self, steps16: float) -> float:
        return steps16 * self.spb / 4.0 / SR


def scale_note(f: Flavour, deg: int) -> int:
    sc = SCALES[f.mode]
    return f.root + sc[deg % len(sc)] + 12 * (deg // len(sc))


# ------------------------------------------------------------------------------------------------ voices
def _rng(*key) -> np.random.Generator:
    return dsp.rng_for("music:" + ":".join(str(k) for k in key))


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
        return modal([1700, 480, 3100], [0.012, 0.02, 0.008], [0.6, 0.8, 0.3], n, rng, 0.01) * 0.7
    raise ValueError(kind)


def riser(seconds: float, rng: np.random.Generator) -> Array:
    n = n_of(seconds)
    t = t_axis(n)
    x = colored_noise(n, rng, 0.3)
    x = sweep_filter(x, 400 * np.exp(np.log(11000 / 400) * (t / seconds) ** 1.5), "lp", 1.5, 2, 14)
    return x * (t / seconds) ** 2.0 * 0.5


@lru_cache(maxsize=None)
def bass_note(kind: str, midi: int, dur_ms: int) -> Array:
    f = hz(midi)
    n = n_of(dur_ms / 1000.0)
    rng = _rng("bass", kind, midi, dur_ms)
    env = env_adsr(n, 0.004, 0.10, 0.75, min(0.06, n / SR * 0.5))
    t = t_axis(n)
    if kind == "fm":
        x = fm(f, 1.0, 2.6 * np.exp(-t / 0.14) + 0.7, n) * 0.9 + 0.5 * sine(f, n)
    elif kind == "pluck":
        ks = karplus_strong(f * 2, n / SR, rng, 0.5 ** (1.0 / (f * 2 * 0.3)), 0.6)
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
    a = min(0.9, 0.35 * n / SR)
    r = min(1.0, 0.3 * n / SR)
    env = env_adsr(n, a, 0.4, 0.85, r)
    cut = np.interp(t, [0, a, n / SR - r, n / SR], [500, 2600, 2000, 900])
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
        ks = karplus_strong(f, max(n / SR, 0.5), rng, 0.5 ** (1.0 / (f * 0.42)), 0.9)
        x = fit(ks, n) * 1.3
        x = x * env_adsr(n, 0.001, 0.05, 1.0, min(0.12, n / SR * 0.4))
    elif kind == "bell":
        x = (fm(f, 3.5, 3.0 * np.exp(-t / 0.28) + 0.2, n) * env_exp(n, 0.55, 0.002) + 0.3 * sine(f * 2, n) * env_exp(n, 0.3, 0.002))
    elif kind == "brass":
        v = sum(saw(f * vib * 2.0 ** (c / 1200), n, rng.random()) for c in (-5, 0, 5)) / 3.0
        cut = np.interp(t, [0, 0.09, 0.4, n / SR], [500, 3400, 2000, 1500])
        x = sweep_filter(v, cut, "lp", 1.0, 2, 8) * env_adsr(n, 0.05, 0.12, 0.85, min(0.1, n / SR * 0.4))
    elif kind == "reed":
        v = square(f * vib, n, 0.32) * 0.55 + saw(f * vib, n) * 0.35
        x = biquad(biquad(v, "peak", 900, 2.0, 7.0), "peak", 2100, 2.0, 5.0)
        x = lowpass(x, 4200) * env_adsr(n, 0.02, 0.1, 0.8, min(0.09, n / SR * 0.4))
    else:  # saw_lead
        v = saw(f * vib, n, rng.random()) * 0.6 + square(f * vib * 1.004, n, 0.5) * 0.3
        cut = np.interp(t, [0, 0.03, 0.3, n / SR], [900, 4200, 1800, 1300])
        x = sweep_filter(v, cut, "lp", 1.2, 2, 8) * env_adsr(n, 0.008, 0.10, 0.8, min(0.08, n / SR * 0.4))
    return x * g


# ------------------------------------------------------------------------------------------------ arrangement
_RHYTHMS = [
    [(0, 3), (3, 1), (4, 2), (6, 2), (8, 3), (11, 1), (12, 4)],
    [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4)],
    [(0, 4), (4, 2), (6, 2), (8, 4), (12, 2), (14, 2)],
    [(0, 1), (1, 1), (2, 2), (4, 4), (8, 1), (9, 1), (10, 2), (12, 4)],
]


def _snap(cand: int, chord: set[int], n_deg: int) -> int:
    return min(range(cand - 3, cand + 4), key=lambda d: (0 if d % n_deg in chord else 1, abs(d - cand)))


def gen_phrase(f: Flavour, rng: np.random.Generator, bar_roots: list[int], density: float, lo: int, hi: int) -> list[tuple[int, int, int, float]]:
    """Melody as (degree, start_step_in_phrase, length_steps, velocity) over len(bar_roots) bars; strong beats snap to chord tones."""
    nd = len(SCALES[f.mode])
    out: list[tuple[int, int, int, float]] = []
    prev = (lo + hi) // 2
    for b, cdeg in enumerate(bar_roots):
        chord = {cdeg % nd, (cdeg + 2) % nd, (cdeg + 4) % nd}
        rhythm = _RHYTHMS[int(rng.integers(len(_RHYTHMS)))]
        for st, ln in rhythm:
            if rng.random() > density and st != 0:
                continue
            cand = prev + int(rng.choice([-2, -1, -1, 0, 1, 1, 2, 3]))
            cand = min(max(cand, lo), hi)
            if st % 4 == 0:
                cand = min(max(_snap(cand, chord, nd), lo), hi)
            out.append((cand, b * 16 + st, ln, float(rng.uniform(0.75, 1.0)) * (1.0 if st % 4 == 0 else 0.85)))
            prev = cand
    if out:  # phrase ends on tonic / fifth
        d, s, ln, v = out[-1]
        end = min(range(d - 3, d + 4), key=lambda x: (0 if x % nd in (0, 4 % nd) else 1, abs(x - d)))
        out[-1] = (end, s, ln, v)
    return out


def _duck_curve(g: Grid, kick_steps: list[int], depth: float) -> Array:
    """Sidechain pump: multiplier curve dipping after every kick (circular)."""
    m = n_of(0.30)
    tpl = 1.0 - depth * np.exp(-t_axis(m) / 0.09) * np.clip(t_axis(m) / 0.004, 0, 1)
    d = np.ones(g.length)
    for s in kick_steps:
        p = g.at(s) % g.length
        k = min(m, g.length - p)
        d[p:p + k] = np.minimum(d[p:p + k], tpl[:k])
        if k < m:
            d[: m - k] = np.minimum(d[: m - k], tpl[k:])
    return d


def arrange(f: Flavour, style: str, bars: int, out_rng_key: str = "") -> dict[str, Array]:
    """Render dry-to-wet stems (drums, bass, pads, lead) as (L,2) circular float arrays."""
    rng = dsp.rng_for(f"arr:{f.name}:{style}:{bars}:{out_rng_key}", f.seed)
    g = Grid(f.bpm, bars, f.swing)
    L = g.length
    nd = len(SCALES[f.mode])
    combat = style == "combat"
    # 8-bar harmonic cycle (scale-degree roots); calm uses 2-bar chords
    prog = [0, 0, 5, 6, 0, 0, 3, 4] if combat else [0, 0, 3, 3, 5, 5, 4, 4]
    sect = [0.55, 0.8, 1.0, 0.7] if combat else [0.4, 0.6, 0.8, 0.5]
    drums, bass, pads, lead = (np.zeros((L, 2)) for _ in range(4))
    kick_steps: list[int] = []
    for bar in range(bars):
        inten = sect[min(bar * len(sect) // bars, len(sect) - 1)]
        cdeg = prog[bar % 8]
        base = bar * 16
        last8 = bar % 8 == 7
        # ---- drums
        if combat:
            ks = [0, 4, 8, 12] if inten >= 0.75 else [0, 6, 8, 11]
            if f.kit == "taiko":
                ks = [0, 3, 8, 10] if inten < 0.9 else [0, 3, 6, 8, 10, 14]
            sn = [4, 12]
            hats = list(range(0, 16, 2)) if inten < 0.75 else list(range(16))
            if f.kit == "taiko":
                hats = [2, 6, 10, 14]
        else:
            ks = [0, 10] if inten < 0.7 else [0, 6, 10]
            sn = [12]
            hats = list(range(0, 16, 4)) if f.kit == "brush" else list(range(0, 16, 2))
        for s in ks:
            place(drums, drum_hit(f.kit, "kick", s % 2), g.at(base + s), 0.95 if s % 4 == 0 else 0.7, wrap=True)
            kick_steps.append(base + s)
        for s in sn:
            place(drums, drum_hit(f.kit, "snare", 0), g.at(base + s), 0.85 if combat else 0.5, wrap=True)
        if combat and inten >= 0.8 and rng.random() < 0.5:
            place(drums, drum_hit(f.kit, "snare", 0), g.at(base + 7 + (rng.random() < 0.5) * 8), 0.3, wrap=True)
        for s in hats:
            kind = "open" if (combat and s == 14 and bar % 2 == 1 and f.kit == "electro") else ("shaker" if f.kit == "brush" else "hat")
            acc = 1.0 if s % 4 == 2 else (0.72 if s % 4 == 0 else 0.5)
            place(drums, drum_hit(f.kit, kind, s % 3), g.at(base + s), acc * (0.8 if combat else 0.6), wrap=True)
        if last8 and combat:  # fill + riser into the next section
            for j, s in enumerate((12, 13, 14, 15)):
                place(drums, drum_hit(f.kit, "tom", j), g.at(base + s), 0.7, wrap=True)
            rs = riser(g.sec(16 * 2), dsp.rng_for(f"riser{bar}", f.seed))
            place(drums, dsp.to_stereo(rs) * 0.5, g.at(base - 16), 0.7, wrap=True)
        if not combat and bar % 4 == 3:
            place(drums, drum_hit(f.kit, "rim", 0), g.at(base + 14), 0.5, wrap=True)
        # ---- bass
        root_m = scale_note(f, cdeg) - 12
        if combat:
            pat = [(0, 2), (2, 2), (4, 2), (6, 1), (7, 1), (8, 2), (10, 2), (12, 2), (14, 2)] if inten >= 0.75 else [(0, 4), (4, 4), (8, 4), (12, 4)]
            for s, ln in pat:
                m = root_m + (12 if (s in (6, 14) and inten >= 0.75) else 0) + (scale_note(f, cdeg + 4) - scale_note(f, cdeg) if s == 10 else 0)
                place(bass, dsp.to_stereo(bass_note(f.bass, m, int(g.sec(ln) * 1000 * 0.95))), g.at(base + s), 0.9, wrap=True)
        else:
            if bar % 2 == 0:
                place(bass, dsp.to_stereo(bass_note(f.bass, root_m, int(g.sec(32) * 1000 * 0.98))), g.at(base), 0.9, wrap=True)
                place(bass, dsp.to_stereo(bass_note(f.bass, root_m + 12, int(g.sec(3) * 1000))), g.at(base + 24), 0.5, wrap=True)
        # ---- pads (one chord per bar in combat, per 2 bars in calm)
        if combat or bar % 2 == 0:
            span = 16 if combat else 32
            chord = tuple(scale_note(f, cdeg + o) + 12 for o in (0, 2, 4, 6 if inten > 0.75 else 7))
            ln_ms = int((g.sec(span) + 0.9) * 1000)
            place(pads, pad_chord(f.pad, chord, ln_ms), g.at(base), 0.8 if combat else 0.9, wrap=True)
    # ---- lead: 4-bar phrases (A, A', B, A'')
    ldeg_lo, ldeg_hi = nd + 1, nd * 2 + 3
    phr_len = 4
    for pi in range(bars // phr_len):
        inten = sect[min(pi * phr_len * len(sect) // bars, len(sect) - 1)]
        roots = [prog[(pi * phr_len + b) % 8] for b in range(phr_len)]
        if combat and inten < 0.6:
            continue
        pr = dsp.rng_for(f"phrase:{f.name}:{style}:{pi % 2 if pi % 4 != 2 else 2}", f.seed)
        notes = gen_phrase(f, pr, roots, 0.85 if combat else 0.55, ldeg_lo, ldeg_hi)
        for deg, st, ln, vel in notes:
            dur = int(g.sec(ln) * 1000 * (1.15 if f.lead in ("pluck", "bell") else 0.95)) + 40
            place(lead, dsp.to_stereo(lead_note(f.lead, scale_note(f, deg), dur, int(vel * 100))), g.at(pi * phr_len * 16 + st), 0.6 if combat else 0.7, wrap=True)
    # ---- mix processing per stem (all circular)
    duck = _duck_curve(g, kick_steps, 0.55 if combat else 0.3)
    pads *= duck[:, None]
    bass *= duck[:, None] ** 0.6
    small = SND_IR("plate")
    hall = SND_IR(f.reverb)
    drums = reverb(drums, small, 0.16, 1.0, circular=True)
    pads = reverb(pads, hall, 0.38, 1.0, circular=True)
    lead = echo(lead, g.sec(3), 0.5, 0.32, 3, circular=True)
    lead = reverb(lead, hall, 0.24, 1.0, circular=True)
    pads = widen(pads, 1.35)
    lead = widen(lead, 1.15)
    drums = dsp.limit(drums, -3.0, 0.003, 0.05)
    bass = dsp.bass_mono(bass, 160.0, circ=True)
    return {"drums": drums, "bass": bass, "pads": pads, "lead": lead}


@lru_cache(maxsize=None)
def SND_IR(preset: str) -> Array:
    presets = {"plate": dict(rt60=1.1, predelay=0.002, damping_hz=9500, size=0.4),
               "hall": dict(rt60=2.8, predelay=0.03, damping_hz=5200, size=1.6),
               "canyon": dict(rt60=3.4, predelay=0.045, damping_hz=2800, size=2.0, low_mult=1.3)}
    return dsp.make_ir(seed="mir_" + preset, **presets.get(preset, presets["hall"]))


STEM_LUFS = {  # per-style loudness targets for each stem BEFORE the shared master gain (relative balance of the layers)
    "combat": {"drums": -19.0, "bass": -21.0, "pads": -24.0, "lead": -22.0},
    "calm": {"drums": -28.0, "bass": -25.0, "pads": -22.0, "lead": -24.0},
}


def mixdown(stems: dict[str, Array], style: str = "combat", target_tp_db: float = -2.0) -> tuple[dict[str, Array], Array, float]:
    """Balance stems to STEM_LUFS[style], then apply ONE shared master gain so sum(stems) has true peak = target.
    Because the gain is shared, the stems still sum to the reference mix and can be crossfaded freely in the game."""
    import analyze  # local import: analysis helpers are build-time only
    tr = {k: v * dsp.db_to_lin(STEM_LUFS[style][k] - analyze.lufs_integrated(v)) for k, v in stems.items()}
    mix = sum(tr.values())
    gdb = target_tp_db - 20 * np.log10(dsp.true_peak(mix) + 1e-12)
    g = dsp.db_to_lin(gdb)
    return {k: v * g for k, v in tr.items()}, mix * g, float(gdb)
