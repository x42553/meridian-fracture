"""stingers.py - the one-shot music cues (audio spec 5.8 / 7.8b): riser, victory, defeat, match start.

  riser        exactly 2 bars at the faction's combat tempo: filtered noise sweep + accelerating tom roll + a reversed pad swell
               that peaks on the last beat and is cut 25 ms before the downbeat of the combat clip that follows it
  victory      ~6.5 s: rising fanfare in the faction's mode and lead timbre, resolving on a MAJOR chord (raised third) with
               pad / brass, kick + noise swell, long hall tail
  defeat       ~6.5 s: slow descending phrase in the low register, minor chord, sub drone, low drum, dark tail
  match_start  2.5 s: short rising sting (generic hero flavour) landing on a power chord

Non-loop, natural tails, faded to silence.  Levels are set by mixdown (loudness target, true-peak ceiling).
"""
from __future__ import annotations

import numpy as np

import dsp
from dsp import Array, colored_noise, lowpass, n_of, place, reverb, sine, sweep_filter, t_axis, widen

from catalog.music import StingerSpec
from music import arrange
from music.flavours import (FLAVOURS, SCALES, bass_note, drum_hit, hz, lead_note, pad_chord, scale_note)


def _swell(seconds: float, rng: np.random.Generator, lo: float = 300.0, hi: float = 12000.0, power: float = 1.6) -> Array:
    n = n_of(seconds)
    t = t_axis(n) / seconds
    x = colored_noise(n, rng, 0.2)
    x = sweep_filter(x, lo * np.exp(np.log(hi / lo) * t ** power), "lp", 1.6, 2, 14)
    return x * t ** 2.2


def _stereo_noise(seconds: float, seed: str, **kw) -> Array:
    return np.stack([_swell(seconds, dsp.rng_for(seed, 1), **kw), _swell(seconds, dsp.rng_for(seed, 2), **kw)], axis=1)


def riser(spec: StingerSpec) -> Array:
    f = FLAVOURS[spec.flavour]
    n = spec.length_samples
    sec = n / dsp.SR
    x = np.zeros((n, 2))
    beat = 60.0 / spec.bpm
    x += _stereo_noise(sec, f"riser:{f.name}") * 0.55
    # tom roll: 8ths for the first bar, 16ths, then 32nds on the last beat (accelerando), velocity climbing
    hits: list[float] = []
    t = 0.0
    while t < sec - 0.04:
        prog = t / sec
        step = beat / (2 if prog < 0.5 else (4 if prog < 0.875 else 8))
        hits.append(t)
        t += step
    for i, th in enumerate(hits):
        v = 0.25 + 0.75 * (th / sec) ** 1.4
        place(x, drum_hit(f.kit if f.kit != "brush" else "taiko", "tom", i), n_of(th), v * 0.8)
    # reversed pad swell on the tonic chord, peaking at the end
    root = f.root + 12
    chord = tuple(scale_note(f, d) + 12 for d in (0, 2 if len(SCALES[f.mode]) == 7 else 3, 4 if len(SCALES[f.mode]) == 7 else 4))
    swell = pad_chord(f.pad, chord, int((sec + 0.2) * 1000))[:n] * ((t_axis(n) / sec) ** 1.8)[:, None]
    place(x, swell, 0, 0.7)
    # rising sine glide (octave-and-a-half) for pitch direction
    gl = sine(np.geomspace(hz(root), hz(root) * 2.83, n), n) * (t_axis(n) / sec) ** 2.0
    x += 0.14 * np.stack([gl, gl], axis=1)
    x = widen(x, 1.25)
    x = reverb(x, arrange.ir("plate"), 0.12, 1.0, circular=False, tail=False)
    return dsp.fade(x, 0.01, 0.025)


def _fanfare_notes(f, victory: bool) -> list[tuple[int, float, float]]:
    """[(midi, start_s, dur_s)] of the melody.  Victory climbs the mode and resolves on the tonic; defeat falls from the
    fifth in the low register."""
    nd = len(SCALES[f.mode])
    third, fifth = (2, 4) if nd == 7 else (2, 3)
    beat = 60.0 / max(f.bpm, 90.0)
    if victory:
        degs = [0, third, fifth, nd, fifth, nd + third, nd * 2]
        starts = [0.0, 1.0, 2.0, 3.0, 3.5, 4.0, 5.0]      # in beats
        durs = [1.0, 1.0, 1.0, 0.5, 0.5, 1.0, 5.0]
        return [(scale_note(f, d) + 12, s * beat * 1.05, d_ * beat * 1.05) for d, s, d_ in zip(degs, starts, durs)]
    degs = [fifth, third, 1 if nd == 7 else 1, 0, -1 if nd == 7 else -1, -nd]
    starts = [0.0, 1.6, 3.0, 4.2, 5.4, 6.4]
    durs = [1.6, 1.4, 1.2, 1.2, 1.0, 4.0]
    slow = 60.0 / 70.0
    return [(scale_note(f, d) - 0, s * slow * 0.72, d_ * slow * 0.9) for d, s, d_ in zip(degs, starts, durs)]


def _hero(spec: StingerSpec, victory: bool) -> Array:
    f = FLAVOURS[spec.flavour]
    n = n_of(spec.seconds)
    x = np.zeros((n, 2))
    nd = len(SCALES[f.mode])
    beat = 60.0 / max(f.bpm, 90.0)
    hall = arrange.ir("canyon" if not victory else "hall")
    if victory:
        mel = np.zeros((n, 2))
        for m, s, d in _fanfare_notes(f, True):
            dur_ms = int(d * 1000) + 60
            place(mel, dsp.to_stereo(lead_note(f.lead, m, dur_ms, 100)), n_of(s), 0.8)
            place(mel, dsp.to_stereo(lead_note("brass", m - 12, dur_ms, 80)), n_of(s), 0.35)     # brass doubling an octave below
        x += widen(reverb(mel, hall, 0.28, 1.0, circular=False, tail=False), 1.2)
        # final chord: MAJOR triad on the tonic (raised third) + octave, held for the last ~3 s
        t_chord = 5.0 * beat * 1.05
        tri = (f.root + 12, f.root + 12 + 4, f.root + 12 + 7, f.root + 24)
        place(x, pad_chord("choir" if f.pad != "glass" else "supersaw", tri, int((spec.seconds - t_chord + 0.4) * 1000)), n_of(t_chord), 0.8)
        place(x, pad_chord(f.pad, tuple(m + 12 for m in tri[:3]), int((spec.seconds - t_chord + 0.4) * 1000)), n_of(t_chord), 0.5)
        for j, tb in enumerate((0.0, 3.0 * beat * 1.05, t_chord)):
            place(x, dsp.to_stereo(drum_hit(f.kit if f.kit != "brush" else "taiko", "kick", j % 2)), n_of(tb), 1.0 if j == 2 else 0.7)
            place(x, dsp.to_stereo(bass_note(f.bass, f.root, 1600 if j == 2 else 600)), n_of(tb), 0.9)
        sw = _stereo_noise(t_chord, f"victory:{f.name}", lo=500.0, hi=14000.0)
        place(x, sw, 0, 0.3)
        place(x, dsp.to_stereo(drum_hit("electro", "open", 0)), n_of(t_chord), 0.5)
    else:
        mel = np.zeros((n, 2))
        for m, s, d in _fanfare_notes(f, False):
            dur_ms = int(d * 1000) + 100
            place(mel, dsp.to_stereo(lowpass(lead_note("brass" if f.lead != "bell" else "pluck", m, dur_ms, 90), 2400, 2)), n_of(s), 0.7)
            place(mel, dsp.to_stereo(bass_note("saw_sub", m - 12, dur_ms)), n_of(s), 0.55)
        x += widen(reverb(mel, hall, 0.34, 1.0, circular=False, tail=False), 1.1)
        third = 3 if nd == 7 or f.mode in ("hirajoshi", "pentatonic_minor") else 4
        chord = (f.root + 12, f.root + 12 + third, f.root + 12 + 7, f.root + 24 + third)
        t_chord = 4.2
        place(x, lowpass(pad_chord("choir", chord, int((spec.seconds - t_chord + 0.6) * 1000)), 1600, 2), n_of(t_chord), 0.9)
        drone = sine(hz(f.root - 12), n) * np.clip(t_axis(n) / 0.8, 0, 1) * np.exp(-t_axis(n) / 5.5)
        x += 0.5 * np.stack([drone, drone], axis=1)
        place(x, dsp.to_stereo(drum_hit("taiko", "kick", 1)), 0, 0.9)
        place(x, dsp.to_stereo(drum_hit("taiko", "tom", 0)), n_of(t_chord - 0.02), 0.9)
        place(x, dsp.to_stereo(drum_hit("taiko", "tom", 0)), n_of(t_chord + 0.9), 0.55)
    return dsp.fade(x, 0.004, 1.0 if victory else 1.6)


def match_start(spec: StingerSpec) -> Array:
    f = FLAVOURS["menu"]
    n = n_of(spec.seconds)
    x = np.zeros((n, 2))
    sw = _stereo_noise(1.05, "match_start", lo=400.0, hi=12000.0)
    place(x, sw, 0, 0.5)
    for j, th in enumerate((0.0, 0.25, 0.5, 0.7, 0.85, 0.95)):
        place(x, dsp.to_stereo(drum_hit("taiko", "tom", j)), n_of(th), 0.4 + 0.1 * j)
    t_hit = 1.05
    chord = (f.root + 12, f.root + 12 + 7, f.root + 24, f.root + 24 + 7)
    place(x, pad_chord("supersaw", chord, int((spec.seconds - t_hit + 0.4) * 1000)), n_of(t_hit), 0.8)
    place(x, dsp.to_stereo(lead_note("brass", f.root + 24, 1400, 100)), n_of(t_hit), 0.7)
    place(x, dsp.to_stereo(drum_hit("taiko", "kick", 0)), n_of(t_hit), 1.0)
    place(x, dsp.to_stereo(bass_note("saw_sub", f.root, 1200)), n_of(t_hit), 0.9)
    x = reverb(x, arrange.ir("hall"), 0.22, 1.0, circular=False, tail=False)
    return dsp.fade(x, 0.004, 0.8)


def render(spec: StingerSpec) -> Array:
    if spec.kind == "riser":
        return riser(spec)
    if spec.kind == "victory":
        return _hero(spec, True)
    if spec.kind == "defeat":
        return _hero(spec, False)
    if spec.kind == "match_start":
        return match_start(spec)
    raise ValueError(spec.kind)
