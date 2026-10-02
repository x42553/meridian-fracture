"""arrange.py - Flavour + style + bar count -> four aligned circular stems (drums, bass, pads, lead).

Structure of a track: combat = three 8-bar sections (groove / fuller / climax, a fill at the end of each), calm = three 4-bar
sections (sparse / warmer / sparse, so the loop re-enters where it started).  Harmony is an 8-bar (combat) or 2-bar-per-chord
(calm) progression of scale degrees; the lead plays an A phrase and an answer phrase per 8 bars, thinned by section tier so
the melody stays recognisable.  Notes are placed with wrap-around and reverbs / echoes are circular convolutions, so the
loop point is seamless by construction; every stem is exactly `length_samples(bpm, bars)` long.
"""
from __future__ import annotations

import numpy as np

import dsp
from dsp import Array, colored_noise, echo, n_of, place, reverb, sweep_filter, t_axis, widen

from music.flavours import (FEELS, LEAD_RHYTHMS, SCALES, Flavour, bass_note, drum_hit, lead_note, length_samples,
                            pad_chord, scale_note)

CHORD_OFFS = {7: (0, 2, 4, 6), 5: (0, 2, 3, 4)}     # chord tones as scale-degree offsets (5-note scales give open 4th/5th voicings)
LIMIT_LOOKAHEAD_S = 0.012
LIMIT_SMOOTH_S = 0.020
ACC = {"X": 1.0, "x": 0.7, "o": 0.4}


class Grid:
    def __init__(self, bpm: float, bars: int, swing: float = 0.0):
        self.bpm = bpm
        self.spb = dsp.SR * 60.0 / bpm
        self.bars = bars
        self.length = length_samples(bpm, bars)
        self.swing = swing

    def at(self, step16: float) -> int:
        s = step16 + (self.swing * 0.5 if int(step16) % 2 == 1 else 0.0)
        return int(round(s * self.spb / 4.0))

    def sec(self, steps16: float) -> float:
        return steps16 * self.spb / 4.0 / dsp.SR


def riser(seconds: float, rng: np.random.Generator) -> Array:
    n = n_of(seconds)
    t = t_axis(n)
    x = colored_noise(n, rng, 0.3)
    x = sweep_filter(x, 400 * np.exp(np.log(11000 / 400) * (t / seconds) ** 1.5), "lp", 1.5, 2, 14)
    return x * (t / seconds) ** 2.0 * 0.5


def chord_tone(f: Flavour, cdeg: int, k: int) -> int:
    nd = len(SCALES[f.mode])
    return scale_note(f, cdeg + CHORD_OFFS[nd][k % 4] + (nd if k >= 4 else 0))


def _snap(cand: int, chord: set[int], n_deg: int) -> int:
    return min(range(cand - 3, cand + 4), key=lambda d: (0 if d % n_deg in chord else 1, abs(d - cand)))


def gen_phrase(f: Flavour, rng: np.random.Generator, bar_roots: list[int], density: float, lo: int, hi: int) -> list[tuple[int, int, int, float]]:
    """Melody as (degree, start_step, length_steps, velocity) over len(bar_roots) bars; strong beats snap to chord tones."""
    nd = len(SCALES[f.mode])
    offs = CHORD_OFFS[nd]
    out: list[tuple[int, int, int, float]] = []
    prev = (lo + hi) // 2
    rhythms = LEAD_RHYTHMS[f.lead_rhythm]
    for b, cdeg in enumerate(bar_roots):
        chord = {(cdeg + o) % nd for o in offs}
        rhythm = rhythms[int(rng.integers(len(rhythms)))]
        for st, ln in rhythm:
            keep = rng.random() <= density or st == 0          # draw always: the phrase stays identical for any density
            cand = prev + int(rng.choice([-2, -1, -1, 0, 1, 1, 2, 3]))
            cand = min(max(cand, lo), hi)
            if st % 4 == 0:
                cand = min(max(_snap(cand, chord, nd), lo), hi)
            vel = float(rng.uniform(0.75, 1.0)) * (1.0 if st % 4 == 0 else 0.85)
            prev = cand
            if keep:
                out.append((cand, b * 16 + st, ln, vel))
    if out:                                                    # phrase ends on tonic / fifth
        d, s, ln, v = out[-1]
        end = min(range(d - 3, d + 4), key=lambda x: (0 if x % nd in (0, offs[2] % nd) else 1, abs(x - d)))
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


# ------------------------------------------------------------------------------------------------ limiter
def _maxfilt_circ(a: np.ndarray, w: int) -> np.ndarray:
    """Centered circular running maximum over [i-w, i+w] (doubling: log2(2w+1) passes)."""
    size, length = 2 * w + 1, 1
    r = a.copy()
    while length < size:
        step = min(length, size - length)
        r = np.maximum(r, np.roll(r, -step))
        length += step
    return np.roll(r, w)


def _smooth_circ(a: np.ndarray, k: int) -> np.ndarray:
    ker = np.hanning(k + 2)[1:-1]
    ker /= ker.sum()
    h = np.zeros(len(a))
    h[:k] = ker
    h = np.roll(h, -(k // 2))
    return np.fft.irfft(np.fft.rfft(a) * np.fft.rfft(h), len(a))


def true_peak_env(mix: np.ndarray, oversample: int = 4) -> np.ndarray:
    """Per-sample inter-sample-peak envelope of a CIRCULAR stereo signal: exact FFT (zero-padded) oversampling, max over the
    oversampled points around each sample and over both channels."""
    n = len(mix)
    out = np.zeros(n)
    for c in range(mix.shape[1]):
        spec = np.fft.rfft(mix[:, c])
        up = np.zeros(n * oversample // 2 + 1, dtype=complex)
        up[: len(spec)] = spec
        up[len(spec) - 1] = 0.0                                          # drop the Nyquist bin (avoids a phantom real-only component)
        y = np.abs(np.fft.irfft(up * oversample, n * oversample)).reshape(n, oversample)
        out = np.maximum(out, y.max(axis=1))
    return out


def limiter_gr_db(mix: np.ndarray, ceiling_db: float, true_peak: bool = False) -> np.ndarray:
    """Gain reduction (dB, >= 0) that keeps the (true) peak of `mix` under the ceiling; circular, smooth, one curve for all stems."""
    c = dsp.db_to_lin(ceiling_db)
    pk = true_peak_env(mix) if true_peak else np.max(np.abs(mix), axis=1)
    gr = np.maximum(0.0, 20.0 * np.log10(np.maximum(pk, 1e-9) / c))
    if not gr.any():
        return gr
    gm = _maxfilt_circ(gr, int(LIMIT_LOOKAHEAD_S * dsp.SR))
    return np.maximum(_smooth_circ(gm, int(LIMIT_SMOOTH_S * dsp.SR) | 1), 0.0)


def _events(lane: str) -> list[tuple[int, float]]:
    return [(i, ACC[c]) for i, c in enumerate(lane) if c in ACC]


def _bass_events(lane: str) -> list[tuple[int, int, str]]:
    """[(step, length_steps, interval_code)]: a digit starts a note, '-' holds it, '.' ends it."""
    ev: list[tuple[int, int, str]] = []
    for i, c in enumerate(lane):
        if c.isdigit():
            ev.append((i, 1, c))
        elif c == "-" and ev and ev[-1][0] + ev[-1][1] == i:
            s, ln, code = ev[-1]
            ev[-1] = (s, ln + 1, code)
    return ev


def _tier(style: str, bar: int, bars: int) -> int:
    if style == "combat":
        return min(bar * 3 // bars, 2)
    return (0, 1, 0)[min(bar * 3 // bars, 2)]


def arrange(f: Flavour, style: str, bars: int) -> dict[str, Array]:
    """Render dry-to-wet stems (drums, bass, pads, lead) as (L,2) circular float arrays."""
    combat = style == "combat"
    bpm = f.tempo(style) if f.name != "menu" else f.bpm
    rng = dsp.rng_for(f"arr:{f.name}:{style}:{bars}", f.seed)
    g = Grid(bpm, bars, f.swing)
    L = g.length
    nd = len(SCALES[f.mode])
    feel = FEELS[f.feel]
    kit = f.kit if (combat or f.kit != "electro") else "brush"
    drums, bass, pads, lead = (np.zeros((L, 2)) for _ in range(4))
    kick_steps: list[int] = []
    perc_kind = feel["perc_kind"]
    for bar in range(bars):
        tier = _tier(style, bar, bars)
        cdeg = f.prog_combat[bar % 8] if combat else f.prog_calm[bar // 2]
        base = bar * 16
        section_end = combat and bar % 8 == 7
        # ---- drums
        if combat:
            lanes = {k: feel[k][tier] for k in ("kick", "snare", "hat", "open", "perc")}
        else:
            lanes = {"kick": ("X...............", "X.......x.......")[min(tier, 1)],
                     "snare": ("", "............o...")[min(tier, 1)] + "." * 16,
                     "hat": ("..............o.", "x...x...x...x...")[min(tier, 1)],
                     "open": "." * 16, "perc": feel["calm_perc"][min(tier, 1)]}
        gain = {"kick": 0.95, "snare": 0.85 if combat else 0.45, "hat": 0.8 if combat else 0.55, "open": 0.75, "perc": 0.8 if combat else 0.6}
        for s, a in _events(lanes["kick"]):
            place(drums, drum_hit(kit, "kick", s % 2), g.at(base + s), gain["kick"] * a * (1 - 0.06 * rng.random()), wrap=True)
            kick_steps.append(base + s)
        for s, a in _events(lanes["snare"]):
            place(drums, drum_hit(kit, "snare", 0), g.at(base + s), gain["snare"] * a, wrap=True)
        hat_kind = "shaker" if (kit == "brush" or (f.kit == "taiko" and not combat)) else "hat"
        for s, a in _events(lanes["hat"]):
            acc = 1.0 if s % 4 == 2 else (0.75 if s % 4 == 0 else 0.55)
            place(drums, drum_hit(kit, hat_kind, s % 3), g.at(base + s), gain["hat"] * a * acc, wrap=True)
        for s, a in _events(lanes["open"]):
            place(drums, drum_hit(kit, "open", 0), g.at(base + s), gain["open"] * a, wrap=True)
        for s, a in _events(lanes["perc"]):
            v = (s // 2) % 6 if perc_kind == "tabla" else s % 3
            k = perc_kind if combat or perc_kind in ("tom", "clave", "shaker", "tabla") else "rim"
            place(drums, drum_hit(kit if k in ("shaker", "tom") else "electro", k, v), g.at(base + s), gain["perc"] * a, wrap=True)
        if section_end:                                          # fill + riser into the next section
            for j, s in enumerate((12, 13, 14, 15)):
                place(drums, drum_hit(kit, "tom", j), g.at(base + s), 0.7, wrap=True)
            rs = riser(g.sec(16 * 2), dsp.rng_for(f"riser{bar}", f.seed))
            rs = dsp.fade(rs, 0.0, 0.03)                        # cut before the next section: keeps the loop seam of the last one clean
            place(drums, dsp.to_stereo(rs) * 0.5, g.at(base - 16), 0.7, wrap=True)
        # ---- bass
        root_m = scale_note(f, cdeg) - 12
        if combat:
            for s, ln, code in _bass_events(feel["bass"][tier]):
                m = {"0": root_m, "1": root_m + 12, "5": chord_tone(f, cdeg, 2) - 12, "4": scale_note(f, cdeg + (3 if nd == 7 else 1)) - 12,
                     "7": chord_tone(f, cdeg, 3) - 12}.get(code, root_m)
                ln = min(ln, 16 - s)
                place(bass, dsp.to_stereo(bass_note(f.bass, m, int(g.sec(ln) * 1000 * 0.95))), g.at(base + s), 0.9 if s % 4 == 0 else 0.75, wrap=True)
        elif bar % 2 == 0:
            place(bass, dsp.to_stereo(bass_note(f.bass, root_m, int(g.sec(32) * 1000 * 0.98))), g.at(base), 0.9, wrap=True)
            place(bass, dsp.to_stereo(bass_note(f.bass, root_m + 12, int(g.sec(3) * 1000))), g.at(base + 24), 0.5, wrap=True)
        # ---- pads (one chord per bar in combat, per 2 bars in calm)
        if combat or bar % 2 == 0:
            span = 16 if combat else 32
            chord = tuple(chord_tone(f, cdeg, o) + 12 for o in (0, 1, 2)) + ((chord_tone(f, cdeg, 3) + 12) if tier == 2 else (chord_tone(f, cdeg, 0) + 24),)
            ln_ms = int((g.sec(span) + 0.9) * 1000)
            place(pads, pad_chord(f.pad, chord, ln_ms), g.at(base), 0.8 if combat else 0.9, wrap=True)
    # ---- lead: per 8-bar (combat) / 4-bar (calm) period an A phrase then an answer; identical phrases every period
    lo, hi = 2 * nd - 2, 3 * nd - 1
    plen = 4
    prog = list(f.prog_combat) if combat else [c for c in f.prog_calm for _ in range(2)]
    phr_a = gen_phrase(f, dsp.rng_for(f"phrase:{f.name}:{style}:A", f.seed), [prog[b % len(prog)] for b in range(plen)],
                       0.9 if combat else 0.6, lo, hi)
    phr_b_tail = gen_phrase(f, dsp.rng_for(f"phrase:{f.name}:{style}:B", f.seed), [prog[(plen + b) % len(prog)] for b in range(plen)],
                            0.9 if combat else 0.6, lo, hi)
    phr_b = [n for n in phr_a if n[1] < 32] + [n for n in phr_b_tail if n[1] >= 32]   # answer = A's first two bars + new tail
    dens_by_tier = (0.55, 0.8, 1.0) if combat else (0.6, 0.85, 0.6)
    for pi in range(bars // plen):
        tier = _tier(style, pi * plen, bars)
        phrase = (phr_a if pi % 2 == 0 else phr_b) if combat else (phr_a, phr_b, phr_a)[pi % 3]
        drng = dsp.rng_for(f"thin:{f.name}:{style}:{pi}", f.seed)
        for deg, st, ln, vel in phrase:
            if st != 0 and drng.random() > dens_by_tier[tier]:
                continue
            dur = int(g.sec(ln) * 1000 * (1.15 if f.lead in ("pluck", "bell") else 0.95)) + 40
            place(lead, dsp.to_stereo(lead_note(f.lead, scale_note(f, deg), dur, int(vel * 100))), g.at(pi * plen * 16 + st), 0.6 if combat else 0.7, wrap=True)
    # ---- per-stem processing (all circular)
    duck = _duck_curve(g, kick_steps, 0.55 if combat else 0.3)
    pads *= duck[:, None]
    bass *= duck[:, None] ** 0.6
    plate = _ir("plate")
    hall = _ir(f.reverb)
    drums = reverb(drums, plate, 0.16, 1.0, circular=True)
    pads = reverb(pads, hall, 0.38, 1.0, circular=True)
    lead = echo(lead, g.sec(3), 0.5, 0.32, 3, circular=True)
    lead = reverb(lead, hall, 0.24, 1.0, circular=True)
    pads = widen(pads, 1.35)
    lead = widen(lead, 1.15)
    drums = drums * dsp.db_to_lin(-limiter_gr_db(drums, -3.0))[:, None]        # circular limiter (dsp.limit is not seam-safe)
    bass = dsp.bass_mono(bass, 160.0, circ=True)
    assert all(len(s) == L for s in (drums, bass, pads, lead)), "stems must be exactly length_samples long"
    return {"drums": drums, "bass": bass, "pads": pads, "lead": lead}


_IR_CACHE: dict[str, Array] = {}


def _ir(preset: str) -> Array:
    if preset not in _IR_CACHE:
        presets = {"plate": dict(rt60=1.1, predelay=0.002, damping_hz=9500, size=0.4),
                   "hall": dict(rt60=2.8, predelay=0.03, damping_hz=5200, size=1.6),
                   "canyon": dict(rt60=3.4, predelay=0.045, damping_hz=2800, size=2.0, low_mult=1.3)}
        _IR_CACHE[preset] = dsp.make_ir(seed="mir_" + preset, **presets.get(preset, presets["hall"]))
    return _IR_CACHE[preset]


def ir(preset: str) -> Array:
    return _ir(preset)
