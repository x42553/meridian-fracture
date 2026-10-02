"""test_voice.py - voice pipeline self tests (plain asserts; seconds; `python qa/test_voice.py` or pytest).

  * the catalogue: 9 packs x (51 lines + 6 second takes) = 513 announcer jobs, unique ids, captions, 648 unit responses
  * numpy chains: resampling keeps pitch, the pitch shifter lowers 5 % at constant duration, the radio chain leaves nothing above
    the band, compressor reduces peaks, master hits the LUFS target under the true-peak ceiling
  * responses are deterministic, inside the length window and carry a squelch
  * the TTS cache key is stable; Piper refuses licence-forbidden voices; Kokoro (cached or live) returns speech when available
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import analyze  # noqa: E402
import dsp  # noqa: E402
from catalog import voice as cv  # noqa: E402
from voice import cache, chains, lines, responses, tts_kokoro, tts_piper, verify  # noqa: E402


def _peak_hz(x: np.ndarray, sr: int = dsp.SR) -> float:
    ps = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    return float(np.argmax(ps) * sr / len(x))


def test_catalogue() -> None:
    ls = lines.all_lines()
    ann, _ = lines.load()
    assert len(ls) == len(ann["packs"]) * (len(ann["lines"]) + sum(1 for v in ann["lines"].values() if v.get("variants", 1) == 2)) == 513
    assert len({v.asset_id for v in ls}) == 513
    assert all(v.caption.strip() and v.tts_text.strip() for v in ls)
    assert {v.pack for v in ls} == set(ann["packs"])
    assert all(a.startswith("vox/") for a in (v.asset_id for v in ls))
    assert next(v for v in ls if v.asset_id == "vox/napc/base_under_attack_2").tts_text.endswith("!")
    rs = responses.all_specs()
    assert len(rs) == 648 and len({s.asset_id for s in rs}) == 648
    bs = lines.all_barks()
    assert len(bs) == 624 and len({b.asset_id for b in bs}) == 624 and all(b.caption.strip() for b in bs)   # 8 factions x 6 classes x 13
    assert len(cv.all_asset_ids()) == 513 + 648 + 624


def test_resample_and_pitch_shift() -> None:
    sr = 24000
    x = np.sin(2 * np.pi * 1000 * np.arange(sr) / sr)
    y = chains.resample_fft(x, sr)
    assert len(y) == dsp.SR and abs(_peak_hz(y) - 1000) < 3
    z = chains.pitch_shift_keep_tempo(y, 0.95)
    assert len(z) == len(y) and abs(_peak_hz(z[2000:-2000]) - 950) < 12, _peak_hz(z[2000:-2000])


def test_chains_band_and_level() -> None:
    rng = dsp.rng_for("vt")
    n = dsp.SR
    x = dsp.colored_noise(n, rng, 1.0, 100, 12000) * dsp.env_exp(n, 0.4) * 0.3
    p = chains.profile("noisy_clipped", 60, 110, -38)
    y = chains.radio(x, p, "t")
    m = analyze.metrics(chains.master(y, -18.0, -1.5))
    assert m["band_gt6k_pct"] < 1.0 and abs(m["lufs_i"] + 18.0) < 0.5 and m["true_peak_db"] <= -1.5
    assert np.array_equal(y, chains.radio(x, p, "t")), "chains must be deterministic"
    o = chains.officer(x, chains.profile("clean_digital", 55, 90, -44), "o")
    assert len(o) > len(x)
    c = chains.compress(np.r_[np.zeros(100), np.ones(3000) * 0.9, np.zeros(100)], -20.0, 4.0, 2.0, 40.0)
    assert c[1500:3000].max() < 0.9 * 0.3 and c[100:110].max() > 0.5          # settled gain reduction; the attack lets the onset through
    assert abs(len(chains.computer(x)) - len(x)) == 0


def test_responses_deterministic_window_and_squelch() -> None:
    for s in (r for r in responses.all_specs() if r.faction in ("olm", "pd") and r.cls in ("heavy", "air", "structure") and r.n == 1):
        a, b = responses.render(s), responses.render(s)
        assert np.array_equal(a, b), s.asset_id
        assert 0.15 <= len(a) / dsp.SR <= 0.72, (s.asset_id, len(a) / dsp.SR)
        rel, flux = verify.squelch_metrics(chains.master(a, -20.0, -2.0))
        assert rel > -26 and flux > 0.15, (s.asset_id, rel, flux)


def test_cache_key_and_piper_licence() -> None:
    k1 = cache.key("kokoro", "m", "af_heart", 1.0, "en-us", "Unit lost.")
    assert k1 == cache.key("kokoro", "m", "af_heart", 1.0, "en-us", "Unit lost.") and k1 != cache.key("kokoro", "m", "af_heart", 1.0, "en-us", "Unit lost!")
    for bad in ("en_US-hfc_male-medium", "en_US-lessac-medium", "en_US-ryan-high"):
        try:
            tts_piper.synth("x", bad)
        except ValueError:
            continue
        raise AssertionError(bad)


def test_kokoro_speech_if_available() -> None:
    if not tts_kokoro.available():
        print("  (Kokoro not installed: skipped)")
        return
    x, sr = tts_kokoro.synth("Unit lost.", "am_michael", 1.0)
    assert sr == 24000 and 0.4 < len(x) / sr < 3.0 and np.abs(x).max() > 0.05
    cold, _ = tts_kokoro._engine().create("Unit lost.", voice="am_michael", speed=1.0, lang="en-us")     # bypasses the cache
    assert np.array_equal(x.astype(np.float32), np.asarray(cold, dtype=np.float32)), "Kokoro must be deterministic (cache = cold run)"


def test_scratch_builds_identical_and_incremental() -> None:
    import filecmp
    import subprocess
    import tempfile
    build = str(Path(__file__).resolve().parent.parent / "build_all.py")
    only = "resp/napc/infantry_select_1,resp/sap/naval_deny_2"
    with tempfile.TemporaryDirectory() as d:
        a, b = Path(d) / "a", Path(d) / "b"
        for out, jobs in ((a, 1), (b, 3)):
            p = subprocess.run([sys.executable, build, "responses", "--only", only, "--jobs", str(jobs), "--out", str(out)], capture_output=True, text=True)
            assert p.returncode == 0, p.stdout + p.stderr
        files = sorted(x.relative_to(a) for x in a.rglob("*") if x.is_file() and x.name != "provenance.json")
        assert len(files) >= 4
        for f in files:
            assert (b / f).exists() and filecmp.cmp(a / f, b / f, shallow=False), f"{f} differs"
        p = subprocess.run([sys.executable, build, "responses", "--only", only, "--out", str(a)], capture_output=True, text=True)
        assert "0 to render" in p.stdout, p.stdout


def _run_all() -> None:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    print("test_voice OK")


if __name__ == "__main__":
    _run_all()
