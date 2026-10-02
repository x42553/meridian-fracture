"""test_music.py - music generator self tests (plain asserts; a few seconds; `python qa/test_music.py` or pytest).

  * the catalog agrees with game/data/audio/music.json (bpm, bars, length_samples, mode, root, stingers)
  * every flavour renders four stems of EXACTLY length_samples, finite, deterministic (two renders identical)
  * circular limiter: keeps the true peak of a peaky loop under the ceiling and is seamless (gain at both ends equal)
  * tempo estimator, scale-share and loop-continuity helpers on synthetic signals
  * risers are exactly 2 bars; stingers finite and faded
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import analyze  # noqa: E402
import dsp  # noqa: E402
import manifest as mf  # noqa: E402
from catalog import music as cm  # noqa: E402
from music import arrange, flavours, stingers, verify  # noqa: E402


def test_catalog_matches_authored_music_json() -> None:
    assert verify.check_data(mf.ROOT / "game" / "data" / "audio") == []
    assert len(cm.tracks()) == 17 and len(cm.stingers()) == 25 and len(cm.all_asset_ids()) == 17 * 4 + 25


def test_calm_tempo_is_about_060_of_combat() -> None:
    for f in cm.FACTIONS:
        fv = flavours.FLAVOURS[f]
        assert abs(fv.tempo("calm") / fv.tempo("combat") - 0.6) < 0.01, f


def test_stems_exact_length_finite_deterministic() -> None:
    for name in ("napc", "han", "sap"):                  # different kits, feels, timbres
        f = flavours.FLAVOURS[name]
        a = arrange.arrange(f, "combat", 8)
        b = arrange.arrange(f, "combat", 8)
        want = flavours.length_samples(f.tempo("combat"), 8)
        for k in ("drums", "bass", "pads", "lead"):
            assert len(a[k]) == want and a[k].shape[1] == 2
            assert np.all(np.isfinite(a[k])) and np.array_equal(a[k], b[k]), (name, k)
    calm = arrange.arrange(flavours.FLAVOURS["olm"], "calm", 4)
    assert len(calm["lead"]) == flavours.length_samples(flavours.FLAVOURS["olm"].tempo("calm"), 4)


def test_circular_limiter_holds_true_peak_and_is_seamless() -> None:
    rng = dsp.rng_for("limtest")
    n = dsp.SR * 3
    x = 0.4 * np.stack([dsp.sine(220, n), dsp.sine(331, n)], axis=1)
    for k in (5000, 60000, n - 300):                        # hot spots, one right before the seam
        x[k:k + 40] += rng.uniform(0.6, 1.0, (40, 2))
    ceil = -2.0
    gr = arrange.limiter_gr_db(x, ceil, true_peak=True)
    y = x * dsp.db_to_lin(-gr)[:, None]
    assert analyze.true_peak_db(y) <= ceil + 0.35, analyze.true_peak_db(y)
    assert gr.min() >= 0 and abs(gr[0] - gr[-1]) < 0.5      # smooth across the wrap
    assert arrange.true_peak_env(x).max() >= np.abs(x).max() - 1e-9


def test_tempo_estimator_and_helpers() -> None:
    bpm = 100.0
    n = dsp.SR * 16
    clicks = np.zeros(n)
    step = int(round(dsp.SR * 60 / bpm / 2))               # 8th notes
    for i in range(0, n - 2000, step):
        clicks[i:i + 1500] += dsp.colored_noise(1500, dsp.rng_for(f"c{i}"), 0.0, 2000, 9000) * dsp.env_exp(1500, 0.01) * (1.0 if (i // step) % 2 == 0 else 0.5)
    est = verify.estimate_bpm(clicks)
    assert verify.tempo_ok(est, bpm), est
    assert verify.tempo_ok(50.0, 100.0) and verify.tempo_ok(200.0, 100.0) and not verify.tempo_ok(133.0, 100.0)
    notes = sum(dsp.sine(flavours.hz(m), dsp.SR * 4) for m in (45, 48, 52, 57))      # A minor triad + octave
    assert verify.in_scale_pct(notes, 45, "aeolian") > 95
    assert verify.in_scale_pct(notes, 46, "aeolian") < 60
    loop = dsp.colored_noise(dsp.SR * 3, dsp.rng_for("lc"), 1.0)
    assert verify.loop_continuity(loop) < 2.0


def test_stingers_render() -> None:
    by = {s.id: s for s in cm.stingers()}
    for f in ("napc", "pd"):
        r = stingers.render(by[f"mus/stinger/{f}_riser"])
        assert len(r) == by[f"mus/stinger/{f}_riser"].length_samples and r.shape[1] == 2
        assert np.all(np.isfinite(r)) and abs(r[-1]).max() < 0.02
    m = stingers.render(by["mus/stinger/match_start"])
    assert len(m) == round(2.5 * 44100) and abs(m[-1]).max() < 1e-3


def test_scratch_builds_identical_and_incremental() -> None:
    import filecmp
    import subprocess
    import tempfile
    build = str(Path(__file__).resolve().parent.parent / "build_all.py")
    only = "mus/stinger/napc_riser,mus/stinger/match_start"
    with tempfile.TemporaryDirectory() as d:
        a, b = Path(d) / "a", Path(d) / "b"
        for out, jobs in ((a, 1), (b, 2)):
            p = subprocess.run([sys.executable, build, "music", "--only", only, "--jobs", str(jobs), "--out", str(out)], capture_output=True, text=True)
            assert p.returncode == 0, p.stdout + p.stderr
        files = sorted(x.relative_to(a) for x in a.rglob("*") if x.is_file() and x.name != "provenance.json")
        assert len(files) >= 4
        for f in files:
            assert (b / f).exists() and filecmp.cmp(a / f, b / f, shallow=False), f"{f} differs between --jobs 1 and 2"
        p = subprocess.run([sys.executable, build, "music", "--only", only, "--out", str(a)], capture_output=True, text=True)
        assert "0 job(s) to render" in p.stdout, p.stdout


def _run_all() -> None:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    print("test_music OK")


if __name__ == "__main__":
    _run_all()
