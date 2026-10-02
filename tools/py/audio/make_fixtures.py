#!/usr/bin/env python3
"""make_fixtures.py - tiny synthetic OGG fixtures (< 200 KB) for the GDScript audio track (game/tests/fixtures/audio/).

The runtime tasks (AUD-G1..G8) develop against these instead of the full library: same file naming, same
`asset_index.json` schema, same sample rate, but a handful of 0.1-2 s assets.  The set covers every code path the runtime
needs: mono + stereo, variant groups, one-shots, seamless loops, a 4-stem music loop with a known BPM (120 BPM, 2 bars =
4 s -> 8 beats), a voice line and a bed.  Deterministic; re-running leaves the bytes unchanged.

  .cache/venv/bin/python tools/py/audio/make_fixtures.py
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

import catalog  # noqa: E402
import dsp  # noqa: E402
import manifest as mf  # noqa: E402
import oggtools  # noqa: E402

OUT = mf.ROOT / "game" / "tests" / "fixtures" / "audio"
BPM, BARS = 120, 2


def _crack(rng, n_s: float, f: float) -> np.ndarray:
    n = dsp.n_of(n_s)
    body = dsp.colored_noise(n, rng, 0.5, lo=f, hi=f * 6) * dsp.env_exp(n, n_s * 0.15, 0.0005)
    low = dsp.sine(120 * np.exp(-dsp.t_axis(n) / 0.02) + 60, n) * dsp.env_exp(n, n_s * 0.2, 0.001)
    return dsp.fade(dsp.saturate(body + 0.6 * low, 1.5) * 0.7, 0.0, n_s * 0.3)


def _tone(f: float, n_s: float, tau: float) -> np.ndarray:
    n = dsp.n_of(n_s)
    return dsp.fade(dsp.sine(f, n) * dsp.env_exp(n, tau, 0.004) * 0.6, 0.0, 0.02)


def _loop_tone(f: float, n_s: float, am_hz: float, rng) -> np.ndarray:
    n = dsp.n_of(n_s)
    f = dsp.snap_freq(f, n_s)
    am = 1.0 + 0.3 * np.sin(dsp.TAU * dsp.snap_freq(am_hz, n_s) * dsp.t_axis(n))
    return (dsp.sine(f, n) * 0.35 + dsp.colored_noise(n, rng, 1.0, lo=80, hi=1500) * 0.08) * am


def _stem(kind: str, rng) -> np.ndarray:
    """One 4 s stem (2 bars at 120 BPM), circular: notes placed on the beat grid with wrap-around."""
    n = dsp.n_of(BARS * 4 * 60.0 / BPM)
    beat = 60.0 / BPM
    y = np.zeros((n, 2))
    if kind == "drums":
        for i in range(BARS * 4):
            k = _crack(rng, 0.18, 300) if i % 2 else dsp.sine(110 * np.exp(-dsp.t_axis(dsp.n_of(0.2)) / 0.03) + 45, dsp.n_of(0.2)) * dsp.env_exp(dsp.n_of(0.2), 0.08, 0.001)
            dsp.place(y, dsp.to_stereo(k), dsp.n_of(i * beat), 0.6, wrap=True)
    elif kind == "bass":
        for i, f in enumerate((55.0, 55.0, 65.4, 49.0) * BARS):
            dsp.place(y, dsp.to_stereo(dsp.sine(f, dsp.n_of(beat * 2)) * dsp.env_exp(dsp.n_of(beat * 2), 0.5, 0.005) * 0.5), dsp.n_of(i * beat), 1.0, wrap=True)
    elif kind == "pads":
        for f, ph in ((220.0, 0.0), (277.2, 0.3), (329.6, 0.7)):
            s = dsp.sine(dsp.snap_freq(f, BARS * 4 * beat), n, ph) * 0.12
            y += dsp.to_stereo(s * (1 + 0.2 * np.sin(dsp.TAU * dsp.t_axis(n) / (BARS * 4 * beat))))
    else:  # lead
        for i, f in enumerate((659.3, 587.3, 523.3, 587.3, 659.3, 659.3, 659.3, 0.0)):
            if f:
                dsp.place(y, dsp.to_stereo(_tone(f, beat * 0.9, 0.2) * 0.5), dsp.n_of(i * beat), 1.0, wrap=True)
    return y


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    entries: dict[str, dict] = {}

    def emit(asset_id: str, x: np.ndarray, loop: bool, quality: float = 0.9) -> None:
        mono = x.ndim == 1
        rel = asset_id + (".mono.ogg" if mono else ".ogg")
        q = dsp.quantize16(x * (0.85 / max(dsp.peak(x), 1e-6)), asset_id)
        oggtools.encode_vorbis(dsp.dequantize16(q), OUT / rel, quality)
        dec = oggtools.decode(OUT / rel)
        entries[asset_id] = {"file": rel, "bank": catalog.bank_of(asset_id), "channels": 1 if mono else 2, "loop": loop,
                             "duration_samples": int(len(dec)), "bytes": (OUT / rel).stat().st_size, "sha256": "", "category": catalog.category_of(asset_id)}

    for v in (1, 2, 3):
        emit(f"sfx/weapon/small_arms_{v}", _crack(dsp.rng_for("fx-sa", v), 0.35, 1500 + 200 * v), False)
    for v in (1, 2):
        emit(f"sfx/weapon/tank_cannon_medium_{v}", _crack(dsp.rng_for("fx-tc", v), 0.9, 300), False)
        emit(f"sfx/explosion/small_{v}", _crack(dsp.rng_for("fx-ex", v), 1.0, 200), False)
        emit(f"sfx/impact/bullet_dirt_{v}", _crack(dsp.rng_for("fx-bd", v), 0.25, 800), False)
    emit("sfx/loop/engine_tracked", _loop_tone(90, 1.0, 3, dsp.rng_for("fx-et")), True)
    emit("ui/click", _tone(1800, 0.08, 0.02), False)
    emit("ui/hover", _tone(2600, 0.08, 0.02) * 0.5, False)
    emit("ui/confirm", np.stack([_tone(659.3, 0.3, 0.1), _tone(987.8, 0.3, 0.12)], axis=1), False)
    emit("alarm/sw_siren", np.stack([_loop_tone(700, 2.0, 2, dsp.rng_for("fx-sr")), _loop_tone(705, 2.0, 2, dsp.rng_for("fx-sr"))], axis=1), True)
    emit("vox/computer/base_under_attack", dsp.fade(dsp.saw(160 + 40 * np.sin(dsp.TAU * 3 * dsp.t_axis(dsp.n_of(0.7))), dsp.n_of(0.7)) * 0.25, 0.02, 0.05), False)
    emit("amb/wind_open", np.stack([_loop_tone(200, 3.0, 1, dsp.rng_for("fx-w", c)) for c in (0, 1)], axis=1), True)
    for stem in ("drums", "bass", "pads", "lead"):
        emit(f"mus/fixture/combat/{stem}", _stem(stem, dsp.rng_for("fx-mus", 1)), True, 0.9)
    keep = {OUT / e["file"] for e in entries.values()}
    for old in OUT.rglob("*.ogg"):                     # drop fixtures that left the set (Godot sidecars are kept for the rest)
        if old not in keep:
            old.unlink()
            Path(str(old) + ".import").unlink(missing_ok=True)
    idx = mf.build_index(entries)
    idx["music"] = {"mus/fixture/combat": {"bpm": BPM, "beat_count": BARS * 4, "bar_beats": 4, "stems": ["drums", "bass", "pads", "lead"],
                                            "length_samples": entries["mus/fixture/combat/drums"]["duration_samples"]}}
    mf.write_if_changed(OUT / "asset_index.json", mf.dumps(idx, compact=True))
    total = sum(p.stat().st_size for p in OUT.rglob("*.ogg"))
    print(f"{len(entries)} fixture assets, {total / 1000:.1f} KB in {OUT.relative_to(mf.ROOT)}")
    assert total < 200_000, "fixtures must stay below 200 KB"


if __name__ == "__main__":
    build()
