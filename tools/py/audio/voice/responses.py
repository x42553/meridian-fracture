"""responses.py - unit acknowledgement clips: `[squelch open][2-3 note faction motif][squelch close]` baked into one mono OGG
(audio spec 5.10, 7.6, 7.8b).  648 bleeps = 8 factions x (6 classes x (3 select + 3 move + 3 attack + 2 deny + 2 special) + 3 structure).

  * classes (responses.json): infantry high and short, vehicle mid, heavy low and long, air fast trill, naval sonar ping,
    support soft two-note, structure click.  The motif length comes from `classes.<c>.len_ms`, variant n of N spans the range.
  * contours: select = ascending pair, move = repeated note + rise, attack = falling triplet, deny = low two-note buzz,
    special = arpeggio.  Degrees are scale degrees of the faction's mode (music.flavours) mapped through the faction's interval
    habit (napc thirds, nec fourths, def fifths ...), so the palettes differ in scale, interval, timbre and rhythm.
  * timbres (spec 5.15): napc brass call-and-response, nec glass pings, olm oud-like plucks with microtonal bends, def low brass
    marching pulses, pd sonar / marimba bell, han koto plucks (hirajoshi), ae kalimba polyrhythm, sap reed + tabla hits.
  * radio: the faction's profile from factions.json (squelch open / close ms, hiss, style) through chains.radio_fx.
"""
from __future__ import annotations

import json
from dataclasses import dataclass

import numpy as np

import dsp
from dsp import Array, SR, n_of, t_axis
from music.flavours import drum_hit, hz, scale_note
from voice import chains
from voice.lines import DATA

CLASSES = ("infantry", "vehicle", "heavy", "air", "naval", "support")
CONTOUR = {"select": [0, 2], "move": [0, 0, 2], "attack": [4, 2, 0], "deny": [0, -1], "special": [0, 2, 4]}
BASE_OFFSET = {"infantry": 48, "vehicle": 36, "heavy": 24, "air": 43, "naval": 36, "support": 36, "structure": 40}
# faction interval habit: contour degree 2 -> a, 4 -> b (scale degrees); timbre; rhythm feel
PALETTE: dict[str, dict] = {
    "napc": dict(third=2, fifth=4, timbre="brass", feel="call"),
    "nec": dict(third=3, fifth=6, timbre="glass", feel="even"),
    "olm": dict(third=1, fifth=4, timbre="oud", feel="swing"),
    "def": dict(third=4, fifth=4, timbre="lowbrass", feel="march"),
    "pd": dict(third=2, fifth=3, timbre="marimba", feel="even"),
    "han": dict(third=1, fifth=3, timbre="koto", feel="even"),
    "ae": dict(third=2, fifth=4, timbre="kalimba", feel="poly"),
    "sap": dict(third=1, fifth=4, timbre="reed", feel="tabla"),
}


@dataclass(frozen=True)
class RespSpec:
    faction: str
    cls: str
    typ: str
    n: int
    n_total: int

    @property
    def asset_id(self) -> str:
        return f"resp/{self.faction}/{self.cls}_{self.typ}_{self.n}"


def all_specs() -> list[RespSpec]:
    r = json.loads((DATA / "responses.json").read_text(encoding="utf-8"))
    fac = json.loads((DATA / "factions.json").read_text(encoding="utf-8"))["factions"]
    out: list[RespSpec] = []
    for f in fac:
        for cls in r["classes"]:
            types = r["structure_types"] if cls == "structure" else r["types"]
            for t, cnt in types.items():
                out += [RespSpec(f, cls, t, n, int(cnt)) for n in range(1, int(cnt) + 1)]
    return sorted(out, key=lambda s: s.asset_id)


# ------------------------------------------------------------------------------------------------ tones
def _env(n: int, a: float, tau: float) -> Array:
    return dsp.env_exp(n, tau, a)


def tone(kind: str, midi: float, dur_s: float, rng: np.random.Generator, buzz: bool = False) -> Array:
    """One note.  All timbres have a <= 15 ms attack so a 60-100 ms note still reads as a note."""
    n = n_of(dur_s)
    f = hz(midi)
    t = t_axis(n)
    if buzz:                                                   # DENY: low raspy buzz with amplitude flutter
        x = dsp.saw(f, n) * 0.6 + dsp.square(f * 1.01, n, 0.35) * 0.4
        x = dsp.lowpass(x, 1400.0, 2) * (0.75 + 0.25 * np.sin(2 * np.pi * 85 * t))
        return x * dsp.env_adsr(n, 0.006, 0.03, 0.85, min(0.03, dur_s * 0.3))
    if kind == "brass":
        v = sum(dsp.saw(f * 2.0 ** (c / 1200), n, rng.random()) for c in (-6, 0, 6)) / 3.0
        cut = np.interp(t, [0, 0.03, dur_s * 0.6, dur_s], [700, 3400, 2400, 1500])
        return dsp.sweep_filter(v, cut, "lp", 1.0, 2, 8) * dsp.env_adsr(n, 0.012, 0.05, 0.85, min(0.04, dur_s * 0.35))
    if kind == "lowbrass":
        v = dsp.saw(f, n) * 0.55 + dsp.square(f * 0.998, n, 0.45) * 0.45
        v = dsp.lowpass(v, 1300.0, 2) * (0.82 + 0.18 * np.sin(2 * np.pi * 55 * t))
        return dsp.saturate(v, 1.6) * dsp.env_adsr(n, 0.014, 0.05, 0.85, min(0.04, dur_s * 0.35))
    if kind == "glass":
        x = dsp.fm(f, 2.0, 1.6 * np.exp(-t / 0.05) + 0.25, n) * _env(n, 0.0015, 0.18)
        return x + 0.25 * dsp.sine(f * 3.0, n) * _env(n, 0.001, 0.05)
    if kind == "oud":                                          # plucked, glides up from ~35 cents flat (microtonal bend)
        cents = -35.0 * np.exp(-t / 0.035) + 8.0 * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.15, 0, 1)
        x = dsp.additive(f * 2.0 ** (cents / 1200.0), [1.0, 0.65, 0.42, 0.27, 0.16, 0.09], n) * _env(n, 0.001, 0.16)
        return dsp.lowpass(x, 3200.0, 2)
    if kind == "marimba":
        return dsp.modal([f, f * 3.93, f * 9.2], [0.16, 0.04, 0.015], [1.0, 0.45, 0.15], n, rng, 0.002) * dsp.env_exp(n, 1.0, 0.001)
    if kind == "koto":
        x = dsp.fit(dsp.karplus_strong(f, max(dur_s, 0.12), rng, 0.5 ** (1.0 / (f * 0.30)), 1.0), n) * 1.3
        return x * dsp.env_adsr(n, 0.0008, 0.03, 1.0, min(0.05, dur_s * 0.3))
    if kind == "kalimba":
        return dsp.modal([f, f * 5.4, f * 12.1], [0.22, 0.035, 0.012], [1.0, 0.5, 0.2], n, rng, 0.003) * dsp.env_exp(n, 1.0, 0.0008)
    if kind == "reed":
        v = dsp.square(f, n, 0.32) * 0.55 + dsp.saw(f, n) * 0.35
        v = dsp.biquad(dsp.biquad(v, "peak", 1100.0, 2.0, 7.0), "peak", 2400.0, 2.0, 5.0)
        return dsp.lowpass(v, 4200.0) * dsp.env_adsr(n, 0.014, 0.05, 0.8, min(0.04, dur_s * 0.35))
    raise ValueError(kind)


def _ping(midi: float, dur_s: float) -> Array:
    """Sonar ping: a pure tone with a slow decay and a soft echo."""
    n = n_of(dur_s)
    x = dsp.sine(hz(midi), n) * _env(n, 0.004, 0.11)
    d = n_of(0.085)
    y = x.copy()
    y[d:] += 0.35 * x[: n - d]
    return y


def motif(spec: RespSpec, flav, pal: dict, lens: tuple[float, float], rng: np.random.Generator) -> Array:
    """The dry 2-3 note motif of one clip (mono)."""
    cls, typ = spec.cls, spec.typ
    if cls == "structure":                                       # select-only click: wood tick + short tone
        tick = dsp.bandpass(dsp.colored_noise(n_of(0.02), rng), 1500, 6000) * dsp.env_exp(n_of(0.02), 0.004, 0.0004)
        x = np.zeros(n_of(0.11))
        x[: len(tick)] += 0.8 * tick
        x += 0.7 * dsp.fit(tone(pal["timbre"] if pal["timbre"] not in ("lowbrass",) else "glass", scale_note(flav, 0) + 24 + 3 * (spec.n - 1), 0.1, rng), len(x))
        return x
    degs = list(CONTOUR[typ])
    third, fifth = pal["third"], pal["fifth"]
    degs = [{0: 0, 2: third, 4: fifth, -1: -1}.get(d, d) for d in degs]
    if typ == "attack":
        degs = [fifth + third, fifth, 0] if pal["timbre"] in ("glass", "marimba") else [fifth, third, 0]
    shift = (0, 1, -1)[(spec.n - 1) % 3] if typ not in ("deny",) else 0            # variants transpose within the scale
    total = lens[0] + (lens[1] - lens[0]) * ((spec.n - 1) / max(spec.n_total - 1, 1))
    if typ == "attack":
        total *= 0.85
    buzz = typ == "deny"
    k = len(degs)
    feel = pal["feel"]
    if cls == "air" and not buzz:                                # fast trill: alternate two degrees every ~36 ms
        step = 0.036
        cnt = max(int(total / step), 4)
        degs = [degs[0] if i % 2 == 0 else degs[min(1, k - 1)] for i in range(cnt)]
        starts = [i * step for i in range(cnt)]
        durs = [step * 1.1] * cnt
    else:
        if feel == "poly":                                        # 3 against 2: uneven onsets
            starts = [0.0, total * 0.40, total * 0.70, total * 0.86][:k]
        elif feel == "swing":
            starts = [i * total / k + (0.05 * total if i % 2 else 0.0) for i in range(k)]
        elif feel == "march" and k == 2:
            degs, k = [degs[0], degs[0], degs[1]], 3
            starts = [0.0, total * 0.30, total * 0.62]
        elif feel == "call":                                      # call and response: short call, longer answer
            starts = [0.0, total * 0.38, total * 0.66][:k] if k == 3 else [0.0, total * 0.42]
        else:
            starts = [i * total / k for i in range(k)]
        durs = [max((starts[i + 1] if i + 1 < k else total) - starts[i], 0.05) * 1.25 for i in range(k)]
        durs[-1] = max(durs[-1], 0.09)
    out = np.zeros(n_of(max(s + d for s, d in zip(starts, durs)) + 0.04))
    for i, (d, s, dur) in enumerate(zip(degs, starts, durs)):
        deg = d + shift + (1 if (feel == "swing" and i == len(degs) - 1 and typ == "select") else 0)
        midi = flav.root + BASE_OFFSET[cls] + (scale_note(flav, deg) - flav.root) - (12 if buzz else 0)
        vel = 1.0 if i == 0 else 0.85
        if cls == "naval" and not buzz:
            ping = _ping(midi, dur + 0.22)
            x = ping * 0.8 + 0.35 * dsp.fit(tone(pal["timbre"], midi, dur + 0.05, rng), len(ping))
        elif cls == "support" and not buzz:
            x = 0.42 * tone("glass" if pal["timbre"] not in ("marimba",) else "marimba", midi, dur, rng) + 0.4 * dsp.sine(hz(midi), n_of(dur)) * _env(n_of(dur), 0.01, 0.16)
        else:
            x = tone(pal["timbre"], midi, dur, rng, buzz)
        a = n_of(s)
        m = min(len(x), len(out) - a)
        out[a:a + m] += vel * x[:m]
    if pal["timbre"] == "reed" and typ in ("select", "attack", "special") and not buzz:     # tabla-like hit under the first note
        h = drum_hit("electro", "tabla", (spec.n * 2 + (1 if typ == "attack" else 0)) % 6)
        m = min(len(h), len(out))
        out[:m] += 0.55 * h[:m]
    return out


def render(spec: RespSpec) -> Array:
    """Dry-to-radio mono clip, un-mastered."""
    from music.flavours import FLAVOURS as FL
    fac = json.loads((DATA / "factions.json").read_text(encoding="utf-8"))["factions"][spec.faction]
    resp = json.loads((DATA / "responses.json").read_text(encoding="utf-8"))
    lens_ms = resp["classes"][spec.cls]["len_ms"]
    lens = (lens_ms[0] / 1000.0, lens_ms[1] / 1000.0)
    flav = FL[spec.faction]
    rng = dsp.rng_for(spec.asset_id, 7)
    x = motif(spec, flav, PALETTE[spec.faction], lens, rng)
    x = x / max(float(np.max(np.abs(x))), 1e-9)
    r = fac["radio"]
    p = chains.profile(r["style"], r["squelch_open_ms"], r["squelch_close_ms"], r["hiss_db"])
    cap = n_of(lens[1] + 0.03)                                    # keeps heavy clips under 0.7 s with both squelches
    if len(x) > cap:
        x = dsp.fade(x[:cap], 0.0, 0.03)
    return chains.radio_fx(x, p, spec.asset_id, full=True)


def features(x: Array) -> np.ndarray:
    """Palette descriptors of one decoded clip for the distinctiveness gate: log centroid, dominant pitch class energy (12), decay."""
    m = dsp.to_mono(x)
    nfft = 4096
    seg = m[: nfft] if len(m) >= nfft else np.pad(m, (0, nfft - len(m)))
    ps = np.abs(np.fft.rfft(seg * np.hanning(nfft))) ** 2
    f = np.fft.rfftfreq(nfft, 1 / SR)
    sel = (f > 300) & (f < 3400)
    cen = float((ps[sel] * f[sel]).sum() / (ps[sel].sum() + 1e-12))
    pc = np.round(12 * np.log2(np.maximum(f[sel], 1) / 440.0) + 69).astype(int) % 12
    ch = np.bincount(pc, weights=ps[sel], minlength=12)
    ch = ch / (ch.sum() + 1e-12)
    dur = float(len(m) / SR)
    return np.concatenate([[np.log(cen), np.log(dur)], ch * 3.0])
