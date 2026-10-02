"""test_dsp.py - toolkit self tests (plain asserts; runs under pytest or `python qa/test_dsp.py`).

  * biquad (FFT impulse-response form) vs scipy.signal.lfilter when scipy is installed, else vs a direct-form-I loop
  * determinism of rng_for, periodicity of circular noise, loop-safe reverb/echo/filters
  * LUFS meter vs ffmpeg ebur128 (skipped without ffmpeg), true peak of an inter-sample peak, Ogg CRC/serial rewrite,
    OGG encode -> decode is sample exact and byte-reproducible
"""
from __future__ import annotations

import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import analyze  # noqa: E402
import dsp  # noqa: E402
import oggtools  # noqa: E402


def _direct_form(b, a, x):
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x):
        yi = b[0] * xi + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def test_biquad_matches_reference():
    x = dsp.rng_for("selftest").standard_normal(20000)
    try:
        from scipy.signal import lfilter
        ref = lambda b, a, sig: lfilter(b, a, sig)  # noqa: E731
        which = "scipy"
    except ImportError:
        ref, which = _direct_form, "direct form"
    worst = 0.0
    for kind, fc, q, g in (("lp", 1000, 0.707, 0), ("hp", 60, 0.707, 0), ("bp", 3000, 8.0, 0), ("lowshelf", 200, 0.7, 6),
                           ("highshelf", 4000, 0.7, -5), ("peak", 800, 2.0, 9), ("notch", 1500, 4.0, 0), ("lp", 50, 12.0, 0)):
        b, a = dsp._rbj(kind, fc, q, g)
        err = float(np.max(np.abs(dsp.biquad(x, kind, fc, q, g) - ref(b, a, x))))
        worst = max(worst, err)
        assert err < 1e-6, (kind, fc, q, err)
    print(f"  biquad vs {which}: max error {worst:.2e}")


def test_rng_is_deterministic_and_independent():
    a = dsp.rng_for("x#1").random(4)
    assert np.array_equal(a, dsp.rng_for("x#1").random(4))
    assert not np.array_equal(a, dsp.rng_for("x#2").random(4))
    assert not np.array_equal(a, dsp.rng_for("x#1", 1).random(4))


def test_circular_material_is_seamless():
    n = 44100
    rng = dsp.rng_for("loop")
    noise = dsp.colored_noise(n, rng, 1.0, lo=80, hi=8000)
    assert dsp.seam_score(noise) < 6.0
    y = dsp.lowpass(noise, 900, 4, circ=True)
    assert dsp.seam_score(y) < 6.0
    # a circular filter of a periodic signal is periodic: the shifted spectrum magnitude is unchanged
    ys = np.roll(dsp.lowpass(np.roll(noise, 1234), 900, 4, circ=True), -1234)
    assert float(np.max(np.abs(ys - y))) < 1e-9


def test_true_peak_sees_intersample_peaks():
    n = 4096
    t = np.arange(n) / dsp.SR
    s = np.sin(2 * np.pi * 11025 * t + np.pi / 4)          # fs/4 sine sampled off-peak: sample peak 0.707, true peak 1.0
    assert abs(float(np.max(np.abs(s))) - 0.7071) < 1e-3
    assert abs(dsp.true_peak(s) - 1.0) < 0.02


def test_meter_matches_ffmpeg():
    if shutil.which("ffmpeg") is None:
        print("  (ffmpeg missing: skipped)")
        return
    rng = dsp.rng_for("lufs")
    x = np.stack([dsp.colored_noise(dsp.SR * 4, rng, 1.0) * 0.08, dsp.colored_noise(dsp.SR * 4, rng, 0.5) * 0.06], axis=1)
    with tempfile.TemporaryDirectory() as d:
        p = str(Path(d) / "t.wav")
        dsp.write_wav(p, x)
        ref = analyze.ffmpeg_ebur128(p)["lufs_i"]
    ours = analyze.lufs_integrated(x)
    assert abs(ours - ref) < 0.15, (ours, ref)
    print(f"  LUFS ours {ours:.2f} vs ffmpeg {ref:.1f}")


def test_ogg_roundtrip_is_exact_and_reproducible():
    x = np.clip(dsp.colored_noise(30000, dsp.rng_for("ogg"), 1.0) * 0.2, -1, 1)
    with tempfile.TemporaryDirectory() as d:
        a, b = Path(d) / "a.ogg", Path(d) / "b.ogg"
        oggtools.encode_vorbis(x, a, 0.4)
        oggtools.encode_vorbis(x, b, 0.4)
        assert a.read_bytes() == b.read_bytes()                     # serial/CRC rewrite makes libsndfile output stable
        assert len(oggtools.decode(a)) == len(x)                     # sample-exact length
        assert a.read_bytes()[14:18] == oggtools.SERIAL.to_bytes(4, "little")


def _run_all() -> None:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    print("test_dsp OK")


if __name__ == "__main__":
    _run_all()
