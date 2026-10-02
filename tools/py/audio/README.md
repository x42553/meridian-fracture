# Meridian Fracture - audio generation toolchain

Every sound in `game/assets/audio/` is **synthesised by these scripts** (numpy only, seeded, deterministic) and encoded to
Ogg Vorbis with libvorbis (through the `soundfile` wheel). Nothing under `game/assets/audio/` is hand-made, nothing is
recorded, and nothing is downloaded. The one exception to "numpy only" is the announcer speech: offline text-to-speech
(Kokoro-82M, Apache-2.0) run at build time, see `NOTICE.txt` and the voice section below. Spec: `tools/spec show audio 7.8` (pipeline), `10.2` (QA), `9.3` (budget).

## Quick start

```
python3 tools/py/audio/bootstrap.py          # finds .cache/venv (or creates .cache/venv_audio); prints the exact commands
.cache/venv/bin/python tools/py/audio/build_all.py sfx --jobs 6      # whole SFX library, ~25 s cold, 0.2 s when up to date
.cache/venv/bin/python tools/py/audio/build_all.py check --jobs 6    # QA thresholds + budget + flavour gate
.cache/venv/bin/python tools/py/audio/build_all.py check --verify --sheets    # + deterministic re-render, spectrogram sheets
tools/gd import && tools/gd test audio_assets                        # Godot imports every OGG (headless load test)
```

`build_all.py` re-executes itself under the venv when the running interpreter has no working numpy (the system `python3`
numpy of the dev machine is a broken namespace stub). Windows: `.cache\venv\Scripts\python.exe`.

`--only` takes recipe names (`rifle_shot`), asset ids or prefixes (`sfx/weapon`, `ui/`) or globs (`sfx/impact/bullet_*`);
`--force` re-renders the selection; `--out DIR` builds into a scratch directory (manifest included).
Sheets land in `.cache/audio/sheets/*.png` (waveform strip + log-frequency spectrogram, title = duration, true peak, LUFS,
crest, loop seam) - **look at them** after touching a recipe.

## Music (AUD-T4) and voice (AUD-T5)

```
.cache/venv/bin/python tools/py/audio/build_all.py music --jobs 8        # 17 tracks x 4 stems + 25 stingers, ~1 min on 8 cores
.cache/venv/bin/python tools/py/audio/build_all.py voice --jobs 8        # 513 announcer lines (TTS cache: .cache/audio/tts), ~2 min cold
.cache/venv/bin/python tools/py/audio/build_all.py responses             # 648 unit-response bleeps, ~3 s
.cache/venv/bin/python tools/py/audio/build_all.py barks --jobs 8        # optional: 624 TTS unit barks (resp/<f>/voice/...), ~1 min
.cache/venv/bin/python tools/py/audio/build_all.py check --sheets        # includes music + voice QA; sheets in .cache/audio/sheets
python3 tools/py/audio/bootstrap.py --voice                              # verifies kokoro-onnx + onnxruntime (requirements-voice.txt)
```
`--only` accepts track ids (`napc.combat`), factions (`napc`), asset prefixes (`mus/stinger`, `vox/han`, `resp/def/voice`) and globs.

| Path | Role |
|---|---|
| `catalog/music.py` | `TrackSpec` / `StingerSpec`, loudness + stem-balance constants, `music_json()` (must equal the authored `music.json`) |
| `music/flavours.py` | scales, the 8 faction flavours + menu, 8 drum feels (16-step grids x 3 intensity tiers), drum / bass / pad / lead voices |
| `music/arrange.py` | flavour + style + bars -> 4 circular stems (sections, progressions, A / answer melody, sidechain pump, circular reverb / echo / limiter) |
| `music/stingers.py` | 2-bar risers, victory (major resolution), defeat, match start |
| `music/mixdown.py` | stem balance, ONE shared gain + circular true-peak limiter on the sum, encode loop (true peak of the decoded sum, loop seam), manifest entries |
| `music/verify.py` | tempo / scale / loop-continuity / loudness / seam checks on the shipped files, music.json agreement, palette distinctiveness, sheets |
| `catalog/voice.py`, `voice/lines.py` | expected voice assets (from `announcer.json`, `responses.json`, `factions.json`) and the QA numbers |
| `voice/tts_kokoro.py`, `tts_piper.py`, `cache.py` | Kokoro (shipped), Piper (fast iteration, CC0 voices only), text+voice+model hash cache |
| `voice/chains.py` | numpy computer / officer / radio chains (phase-vocoder pitch, robotisation, mu-law crush, compressor, squelch); ffmpeg is not needed |
| `voice/responses.py` | unit-response bleeps: squelch + faction motif (scale, timbre, interval habit, rhythm) + squelch, faction radio profile |
| `voice/build.py`, `voice/verify.py` | rendering / encoding / manifest entries, QA (spec 10.2 announcer + response rows), audition sheets |
| `NOTICE.txt`, `requirements-voice.txt` | TTS / tool licences, pins |

Music is rendered per TRACK (four stems share one master gain); a change in any `music/*.py` re-renders every track. Voice assets
are per file; the raw TTS output is cached by text + voice + speed + model hash, so only changed lines are re-synthesised.
Tests: `qa/test_music.py`, `qa/test_voice.py` (seconds each).

## Layout

| Path | Role |
|---|---|
| `dsp.py` | numpy-only synthesis kit: periodic noise colours, PolyBLEP oscillators, FM, modal, Karplus-Strong, envelopes, RBJ biquads by exact impulse response (FFT convolution, max error 1e-9 vs `scipy.lfilter`), time-varying filters, saturation, look-ahead limiter, echo, synthetic-IR reverb, M/S, LR4 `bass_mono`, `bass_exciter`, true peak, `rng_for(name, salt)` |
| `oggtools.py` | libvorbis encode + Ogg serial/CRC rewrite (byte-reproducible), sample-exact decode |
| `analyze.py` | BS.1770 K-weighted gated LUFS (matches ffmpeg ebur128 to <0.05 LU), true peak, attack / decay / spectral bands / stereo LF correlation / loop seam, distinctiveness features, spectrogram + contact sheets |
| `catalog/__init__.py` | `AssetSpec` (the single source of truth), id / file / bank rules |
| `catalog/{weapons,impacts,movement,structures,powers,superweapons,ui_alarms,ambience}.py` | what exists (specs only, no DSP) |
| `catalog/qa_thresholds.py` | QA class of every asset and the limits (spec 10.2) |
| `sfx/*.py` | recipes `fn(rng, variant, **params) -> ndarray`; `sfx/kit.py` shared blocks + faction flavour post-process |
| `render.py` | master chain for one asset (level, exciter, dither, encode, decode, verify) and `recipe_hash` |
| `manifest.py`, `provenance.py` | `audio_manifest.json`, `asset_index.json`, `provenance.json`, `NOTICE.txt` (sorted, byte-stable) |
| `qa/qa_assets.py`, `qa/sheets.py` | `check` implementation |
| `qa/test_dsp.py`, `qa/test_pipeline.py` | toolkit + pipeline self tests (plain asserts) |
| `make_fixtures.py` | 20 tiny OGGs (<200 KB) for the GDScript runtime tests -> `game/tests/fixtures/audio/` |

## Asset ids, files, banks

Ids are lower-case `[a-z0-9_]` paths relative to `res://assets/audio/`, no extension. `variants == 1` -> `<id>`; `n > 1` ->
group `<id>` = `<id>_1 .. <id>_n` (`asset_index.json` `groups`). Files: `channels="mono"` -> `<asset>.mono.ogg`,
`"stereo"` -> `<asset>.ogg`, `"both"` -> both (a 3D event loads the `.mono.ogg`; the index row has `"m": 1`).

Event id -> asset group: `snd.<a>.<b>.<c>` -> `sfx/<a>/<b>_<c>` (weapon, proj, impact, explosion, death, collapse, loop, air,
struct, eco, power, sw, intercept); `snd.ui.x` -> `ui/x`; `snd.alarm.x` -> `alarm/x`; `snd.amb.x` -> `amb/x`. Examples:
`snd.weapon.tank_cannon_medium` -> `sfx/weapon/tank_cannon_medium`; `snd.impact.bullet.dirt` -> `sfx/impact/bullet_dirt`;
`snd.explosion.water.small` -> `sfx/explosion/water_small`; `snd.sw.atlas.impact` -> `sfx/sw/atlas_impact`;
`snd.power.buff.loop` -> `sfx/power/buff_loop`; `snd.weapon.beam_thermal.loop` -> `sfx/weapon/beam_thermal_loop`.
Faction weapon flavours: `sfx/weapon_fx/<faction>/<archetype>` (10 families x 8 factions x 2 variants).
Banks: `core` (sfx / ui / alarm), `fx_<faction>`, `amb`; music / voice banks belong to AUD-T4 / T5.

## Writing a recipe

```python
from sfx import recipe
from sfx.kit import burst, thump, finish, verb            # helpers; changing kit.py re-renders everything

@recipe
def my_shot(rng, v, k=1.0):                                # pure: no globals, no I/O, no clock, draw only from rng
    n = n_of(1.2)
    x = burst(n, rng, 0.002, lo=1500, hi=14000) + 0.6 * thump(n, 180 * k, 70, 0.012, 0.04)
    return finish(verb(x, "field", 0.25), 1.2, 0.2)       # mono (n,) or stereo (n,2), float64, any level
```
then `add(AssetSpec("sfx/weapon/my_shot", "my_shot", variants=2, params={"k": 1.1}, exciter=0.3))` in a catalog module.
Levels are the master chain's job: `peak_db` is the true-peak ceiling (loops -6), `lufs` a loudness target that is also
capped by the ceiling (so on a one-shot it acts as a cap), `exciter` the psychoacoustic bass amount. The RNG is
`rng_for(f"{id}#{variant}", salt)`, so adding or renaming an asset never perturbs another. Loops must be circular:
frequency-domain noise, `snap_freq` oscillators, `place(..., wrap=True)`, `circ=True` filters / reverb / echo.

## Determinism and incremental builds

`recipe_hash = sha256(recipe source + sfx/kit.py + json(spec) + DSP_VERSION + MASTER_CHAIN_VERSION)`; an asset is re-rendered
only when its hash changed or its file is missing. Two clean builds (any `--jobs`) give identical OGG / manifest / index bytes;
`provenance.json` `created_utc` is kept while an OGG's bytes are unchanged (set `SOURCE_DATE_EPOCH` for reproducible fresh
stamps). Bump `dsp.DSP_VERSION` / `render.MASTER_CHAIN_VERSION` when a change alters existing outputs. Across platforms /
library versions bytes may differ in the last ulp: `check --verify` then compares metrics (LUFS +-0.3, true peak +-0.3 dB,
exact duration) instead of hashes.

## QA classes (`catalog/qa_thresholds.py`)

Measured on the **decoded** OGGs: sample rate, channels, length delta 0, no NaN, |DC| < 0.005, first / last sample of one-shots,
no clipping, per-class length / true peak / attack (10-90 % rise to the median level of the first 40 ms, >150 Hz) / centroid /
200 Hz-2 kHz share / LF correlation / loop seam (source and decoded) / loudness window, plus the size budget (110 MB total,
2500 files, 45 MB per bank) and the faction-flavour distinctiveness gate (closest pair of the 8 factions per family must not
shrink by more than 20 % against the baseline stored in the manifest under `qa.distinct`). Values marked `[tune]` in
`qa_thresholds.py` are not literal spec numbers.
