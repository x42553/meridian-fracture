# MERIDIAN FRACTURE — Audio Engine & Audio Asset Pipeline (domain spec)

> **Owner:** audio architect. **Status:** v1.0 for the reconcilers. **Binding inputs:** `docs/ARCHITECTURE.md` (wins on conflict), `docs/balance/TAXONOMY.md` (vocabulary), `docs/spec/sim_core.md` (the **MASTER event catalog** `SimEvent` — 10-int records `[type, tick, a..h]`, entity/fog/relation queries, `SimFlags`; this spec consumes exactly that catalogue), `docs/spec/qa_tooling.md` and `docs/spec/qa.md` (test layout, lint, licence/provenance and settings-key gates), `docs/spec/terrain_movement.md` (`MapData`: family, biome, terrain ids), `docs/spec/render.md` (the view camera getters), the sibling specs `combat.md`, `economy.md`, `abilities.md` (whose *proposed* codes 200–229 / 300–410 / 23x, like movement's 0x40–0x49, are superseded by the master catalog; §6.4 maps them), `data_balance.md` (presentation-id rules) and the audio spike `prototypes/audio/`.
>
> **Evidence tags used in this document.** `[spike]` measured in the audio spike (numbers quoted from the spike summary handed to this task; `prototypes/audio/REPORT.md` was **not on disk** when this spec was written, so every spike claim was cross-checked against the spike's code, `data/audio_events.json`, manifests and metrics JSON in that folder). `[probe]` measured for *this* spec on Godot 4.7.2 / macOS arm64 / `--audio-driver Dummy` (nine results P1–P9 from six throw-away scripts, in §5.14). `[docs]` verified in `tools/godot_docs` class XML. `[design]` a decision made here. `[tune]` a provisional number that must be tuned by ear. `ASSUMPTION(domain)` an interface owned by another architect (collected in §13).
>
> **Honesty note.** Nothing in this project has been *listened to*. Quality is enforced by objective proxies (LUFS, true peak, envelope, spectrum, loop seams, distinctiveness metrics) and by a mandatory human review gate (§10.6) with a purpose-built audition tool (`SndGallery`). The design maximises what can be verified by script and isolates everything that needs ears into data (`[tune]` numbers in JSON, never in code).

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**Purpose.** Give MERIDIAN FRACTURE a complete, AAA-style, **zero-external-asset** soundscape: every sound is synthesised from code at build time by `tools/py/audio/` (numpy DSP + libvorbis encode, deterministic seeds, hash manifest), shipped as Ogg Vorbis under `game/assets/audio/`, and played by a small, allocation-free runtime (`game/src/audio/`, prefix `Snd*`) that turns the deterministic simulation's output-only `SimEvent`s plus a few UI/camera calls into a mix that is loud where the action is, clear where the player must react, and never interferes with the simulation (DR-12). The spike (`prototypes/audio`, verdict GO) proved the toolchain: 38 SFX recipes, two loopable 4-stem tracks and 52 announcer lines = 116 OGG / 13 MB in ~30 s of build plus TTS, bit-reproducible on one machine, imported by Godot 4.7.2 as `AudioStreamOggVorbis` with sample-exact loops.

**This spec owns**

| Area | Deliverable |
|---|---|
| Runtime | everything under `game/src/audio/**` (classes `Snd*`), the `Snd` autoload facade, bus layout + ducking + limiter, event map + voice pool, sim→sound bridge, listener/camera coupling, entity loops, combat-intensity meter, dynamic music, announcer, unit acknowledgements, ambience, superweapon countdown, settings, debug monitor + `SndGallery` |
| Data | `game/data/audio/*.json` — schemas, validators, and the **initial content** (events, profiles, mix, music, announcer, responses, factions) |
| Assets | `game/assets/audio/**` (generated, committed): the OGGs, `audio_manifest.json`, `asset_index.json`, `PROVENANCE.json`, `NOTICE.txt` |
| Tooling | `tools/py/audio/**`: DSP toolkit, SFX/music/voice/response generators, catalog, build driver, QA, validators, venv bootstrap |
| Contract to other domains | the **sound-id grammar** (`snd.*`) that `data_balance.md` presentation ids must use, the derived defaults (so balance authors normally write *no* sound ids at all), the audio call points UI/view/net/app must make, and the few extra fields audio needs from sim domains (§6.4, §13) |
| Tests | `game/tests/audio/test_snd_*.gd`, `game/tests/scenarios/snd_*.gd`, `tools/py/audio/qa/*` |

**This spec does NOT own** (and never edits): sim events and their codes (sim_core owns the master catalog; audio *mirrors* the consumed subset in one file, §6.1); vision/fog rules; the camera controller (the app forwards the view camera's pose to `Snd.set_camera` every frame); the audio-settings *widgets* and the sidebar/selection code that calls `Snd.unit_selected/unit_ordered` (ui); lobby/net UI sounds beyond the `Snd.ui(...)` calls; `GameData` and the balance layer (audio only *reads* them); map generation (audio reads `MapData.family`, `biome` and the `terrain` ids); localisation of announcer text; voice chat (out of scope: LAN game without VoIP); recorded/sampled assets (none are used — the "no external art" rule of ARCHITECTURE §0 applies to audio); hand-composed music (all music is procedural, with per-faction flavours).

**Non-goals for v1** (listed so nobody assumes them): occlusion/LOS filtering, HRTF/surround output (stereo only; `AudioServer.get_speaker_mode()` is read but 5.1/7.1 is not authored), reverb zones per map, bullet whiz-by, per-roster (24 subfaction) music tracks. All are designed so they can be added without schema changes (§12).

**Design pillars** (these drive every later decision)
1. **Presentation-only, read-only.** Audio never mutates the sim, never uses `SimRng`, never appears in a checksum or in the data hash (§8).
2. **Data over code.** Every number a sound designer would tune by ear (levels, ranges, priorities, thresholds, fades, ducking) lives in `game/data/audio/*.json`, validated at load; code contains mechanisms only.
3. **Budgeted.** Fixed voice pools (48 positional + 16 flat), per-frame start caps, per-event and per-group limits, priority stealing with a reserve for important sounds (§5.2). The main-thread cost is bounded by counts, never by what the sim does.
4. **Readable battlefield.** Enemy vs own vs ally sounds are distinguishable by *faction flavour* (per-faction weapon timbre variants, radio bleeps, announcer voice, music), by priority (a huge explosion is never dropped for 40 rifle shots) and by fog rules (no positional leak from unseen cells, §5.5).
5. **Verified engine behaviour only.** Every non-obvious Godot behaviour the design leans on is either from the spike, from a probe in §5.14, or from the class docs. Three spike rules are binding: positional SFX are **mono** files; a **current `Camera3D`** must exist in the viewport that holds the `AudioStreamPlayer3D`s; every volume change is **ramped at ≥ 60 Hz** (bus/`AudioStreamSynchronized` steps click 21–23×).

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

The names in the task charge map as follows: *SndManager* = `SndManager`; *SndEventMap* = `SndEventMap` + `SndDataStore`; *SndMusic* = `SndMusicLibrary` + `SndMusicDirector`; *SndVoice* = `SndAnnouncer` + `SndUnitResponse` (speech) and `SndVoicePool` (all pooled SFX voices, pooling/limiting). All runtime classes live in `game/src/audio/` (lint L004: prefix `Snd`; L009: file = snake_case of class; L005: nothing outside `audio/` may mention `Snd*` except the `app/`, `view/`, `ui/` and `net/` call sites listed in §3.11). No file exceeds ~600 lines.

### 2.1 Runtime (GDScript)

| File | `class_name` | Extends | Responsibility |
|---|---|---|---|
| `snd_manager.gd` | `SndManager` | `Node` | Facade + owner of every subsystem; registered as autoload `Snd`; the only class other modules call (§3.1). |
| `snd_config.gd` | `SndConfig` | `RefCounted` | Constants (`const`) that are *mechanism* limits (pool sizes, handle layout, unit conversions). Tunables come from `mix.json`. |
| `snd_data_store.gd` | `SndDataStore` | `RefCounted` | Loads + validates all `game/data/audio/*.json`, owns the parsed typed defs, computes `data_version` (FNV-1a, diagnostic only). |
| `snd_bus.gd` | `SndBus` | `RefCounted` (static) | Builds/repairs the bus layout, effects and sidechains (idempotent); bus name/index constants. |
| `snd_bus_fader.gd` | `SndBusFader` | `RefCounted` | Ramps bus volumes/mutes/effect toggles per frame (never a single step). |
| `snd_settings.gd` | `SndSettings` | `RefCounted` | The user-facing audio options; load/save the `[audio]` section of `user://settings.cfg`; slider→dB mapping. |
| `snd_event_def.gd` | `SndEventDef` | `RefCounted` | One resolved event (variants, randomisation, spatial, limits, fog policy) + bookkeeping owned by the pool. |
| `snd_event_map.gd` | `SndEventMap` | `RefCounted` | Parses/validates `events.json`; `get_def`, `resolve(kind, tags)`, profile lookup, flavour selection. |
| `snd_profile_def.gd` | `SndProfileDef` | `RefCounted` | Resolved `snd.profile.*` (voice class, entity loops, death/spawn overrides). |
| `snd_asset_index.gd` | `SndAssetIndex` | `RefCounted` | `res://assets/audio` path resolution from `asset_index.json`, mono/stereo choice, **bank** loading (threaded), stream cache. |
| `snd_voice_pool.gd` | `SndVoicePool` | `Node` | The fixed pools of `AudioStreamPlayer3D`/`AudioStreamPlayer`; culling, limits, priority stealing, fades, handles (§5.2). |
| `snd_listener.gd` | `SndListener` | `Node3D` | Owns the `AudioListener3D`; couples to the RTS camera (focus point, yaw, zoom scale → *audio space*). |
| `snd_scheduler.gd` | `SndScheduler` | `RefCounted` | Tiny time-ordered queue for delayed sounds (shell whistle, propagation delay, staggered impacts). |
| `snd_event_codes.gd` | `SndEventCodes` | `RefCounted` | **Mirror** of the sim event/reason/flag codes audio consumes (one file to fix if a code moves); test asserts equality with the sim's constants. |
| `snd_units.gd` | `SndUnits` | `RefCounted` (static) | Sim units → metres/world position, size-class thresholds, armor → material table, the frozen 27-row `WeaponArch` table (`ARCH_TABLE`: name, damage type, flight class). |
| `snd_sound_bank.gd` | `SndSoundBank` | `RefCounted` | Bakes `GameData` + roster + audio data into flat arrays (weapon→event, warhead→size/kind, unit/structure→profile, power/superweapon→cue). Built per match, < 5 ms. |
| `snd_sim_bridge.gd` | `SndSimBridge` | `RefCounted` | Drains a batch of `SimEvent`s → audibility (fog/ownership/distance) → candidate list → ranked starts; owns throttles and the announcer/music triggers derived from events (§6.2). |
| `snd_loop_manager.gd` | `SndLoopManager` | `RefCounted` | Entity-bound loops (engines, rotors, beams, structure hums, projectile flight) selected by audibility; fades; per-frame position/pitch updates. |
| `snd_combat_meter.gd` | `SndCombatMeter` | `RefCounted` | Leaky-integrator "heat" → intensity 0..1 and calm/combat state requests for the music. |
| `snd_music_library.gd` | `SndMusicLibrary` | `RefCounted` | Builds per-faction `AudioStreamInteractive` (clips = `AudioStreamSynchronized` stem stacks) from `music.json`; async bank load. |
| `snd_music_director.gd` | `SndMusicDirector` | `Node` | Music state machine, safe transitions (one at a time), stem intensity smoothing, stingers, menu/lobby/match contexts. |
| `snd_announcer.gd` | `SndAnnouncer` | `Node` | EVA-style single-voice queue: priority, pre-emption, cooldowns, expiry, packs, `announcement_started` signal. |
| `snd_unit_response.gd` | `SndUnitResponse` | `RefCounted` | Selection/order acknowledgements: faction × voice class × response type; anti-spam; synth/voice/mixed modes. |
| `snd_ambience.gd` | `SndAmbience` | `Node` | Biome beds + terrain-weighted layers + far-battle bed; crossfades with per-frame ramps. |
| `snd_countdown.gd` | `SndCountdown` | `RefCounted` | Superweapon/power warning timeline: siren loop, 1 Hz beeps, final tone, charge-hum pitch. |
| `snd_stats.gd` | `SndStats` | `RefCounted` | Counters (played/culled/stolen/dropped per reason), registered as `Performance` custom monitors. |
| `debug/snd_monitor_panel.gd` | `SndMonitorPanel` | `Control` | Dev overlay: spectrum, bus peaks, pool occupancy, event log (ported from the spike's `audio_monitor.gd`). |
| `debug/snd_gallery.gd` (+ `.tscn`) | `SndGallery` | `Control` | Audition tool for humans: every event/profile/line/response/track/state with distance and faction controls, rating export (§10.6). |
| `debug/snd_test_rig.gd` | `SndTestRig` | `Node3D` | Builds a `Camera3D` + `Snd` stack inside a test scene tree; `AudioEffectCapture` helpers for integration tests. |

### 2.2 Data (`game/data/audio/`)

| File | Schema id | Content |
|---|---|---|
| `manifest.json` | `meridian.audio.manifest/1` | Sorted list of the files below + format version (mirrors `balance/manifest.json`). |
| `mix.json` | `meridian.audio.mix/1` | Buses, ducking, pool sizes, camera/zoom mapping, loudness references, fog policy defaults, throttles. |
| `events.json` | `meridian.audio.events/2` | Groups, **events** (`snd.*`), **profiles** (`snd.profile.*`), power/superweapon cue tables, `sim_map` patterns. **The registry V-REF-02 checks presentation ids against.** |
| `music.json` | `meridian.audio.music/1` | Combat-meter parameters, stem windows, tracks, per-faction sets, transitions, stingers, contexts. |
| `announcer.json` | `meridian.audio.announcer/1` | Line catalogue (text, category, priority, cooldown, variants), packs, categories. |
| `responses.json` | `meridian.audio.responses/1` | Unit-response taxonomy: classes, types, variants, barks (text for the optional voice layer), gaps. |
| `factions.json` | `meridian.audio.factions/1` | Per-faction sonic identity: music set, announcer pack, response pack, weapon flavour, radio style; optional per-roster overrides. |
| (assets) `game/assets/audio/audio_manifest.json` | `meridian.audio.assets/1` | Generated, tooling-only (excluded from exports): every asset with hash, loudness, duration, channels, loop flag, recipe hash. |
| (assets) `game/assets/audio/asset_index.json` | `meridian.audio.index/1` | Generated, **shipped**: slim runtime index `id → {file, bank, channels, loop, samples}` + group sizes (≈ 190 KB for ≈ 1 720 entries); read by `SndAssetIndex`. |
| (assets) `game/assets/audio/PROVENANCE.json` | qa.md 7.8 | Generated, committed, repository hygiene only (excluded from exports): one licence/provenance record per OGG (§7.8); audited by QA gate DA-27 and V-AUD-26. |
| (assets) `game/assets/audio/NOTICE.txt` | – | Generated, **shipped**: third-party notices for the credits screen (§7.8). |

### 2.3 Tools (`tools/py/audio/`) — Python 3.10+, numpy + soundfile + Pillow (build only)

| File | Responsibility |
|---|---|
| `bootstrap.py` | Verifies (and only if needed extends) the repo-local `.cache/venv` against the pins `numpy`, `soundfile`, `Pillow` (`--voice` adds `kokoro-onnx`, `onnxruntime`; falls back to a new `.cache/venv_audio`, never deletes a venv); refuses the broken system numpy the spike hit. |
| `build_all.py` | CLI driver: `sfx`, `music`, `voice`, `responses`, `events` (scaffold), `check`, `all`; `--only`, `--jobs`, `--verify`, `--sheets`, `--budget`. Incremental by recipe hash. |
| `dsp.py`, `oggtools.py`, `analyze.py` | The spike toolkit, promoted (§7.8). |
| `manifest.py`, `provenance.py` | Write `audio_manifest.json`, the runtime `asset_index.json`, `PROVENANCE.json` (qa.md schema) and `NOTICE.txt` from the catalog and the render results (sorted, byte-stable, `created_utc` preserved for unchanged recipes). |
| `catalog/*.py` | Declarative asset specs (`AssetSpec`) per family — the single source of truth for what is generated. |
| `sfx/*.py` | Recipes (`fn(rng, variant, **params) -> ndarray`) split by family: weapons, projectiles, impacts, explosions, structures, powers, superweapons, ui, alarms, movement, ambience. |
| `music/*.py` | `flavours.py`, `arrange.py`, `stingers.py`, `mixdown.py`, `verify.py` (tempo/scale/loop checks). |
| `voice/*.py` | `lines.py` (mirror of `announcer.json`), `tts_kokoro.py`, `tts_piper.py`, `chains.py` (numpy radio/computer/officer chains), `responses.py` (bleep motif synthesis + optional barks), cache. |
| `qa/qa_assets.py`, `qa/qa_capture.py`, `qa/sheets.py` | Objective QA (§10.2), engine-capture analysis, spectrogram contact sheets. |
| `validate_audio.py` | **stdlib-only** validator of `game/data/audio/*.json` against assets, `game/data/balance/*` and the bible (rules V-AUD-01…28, §7.9). |

### 2.4 Tests (owned by audio)

Discovered by `tools/gd test` (qa_tooling §2: `game/tests/<module>/test_<thing>.gd`, `extends RefCounted`, `func test_*(t: TestCtx)`): `game/tests/audio/test_snd_event_map.gd`, `test_snd_voice_pool.gd`, `test_snd_bus.gd`, `test_snd_bridge.gd`, `test_snd_announcer.gd`, `test_snd_music.gd`, `test_snd_meter.gd`, `test_snd_response.gd`, `test_snd_loops.gd`, `test_snd_settings.gd`, `test_snd_event_codes.gd`, `test_snd_coverage.gd`, `test_snd_determinism.gd`, `test_snd_match_flow.gd` and the engine-capture file `test_snd_capture.gd` (methods `test_slow_*`, skipped unless `SND_SLOW=1`); Python: `tools/py/audio/qa/test_*.py`. Scenario scripts for `tools/gd run` live in `game/tests/scenarios/snd_*.gd`.

### 2.5 Additions to the file table (adapters and small typed containers)

| File | `class_name` | Responsibility |
|---|---|---|
| `snd_world_reader.gd` | `SndWorldReader` | **The only file that touches `SimWorld`** (entities, fog, relations, players, spatial queries; sim_core §3.4). One place to fix if a sim_core signature changes. |
| `snd_match_config.gd` | `SndMatchConfig` | Typed input of `begin_match` (viewer, factions, map family and biome, seed, `GameData`). |
| `snd_mix_config.gd` | `SndMixConfig` | Typed view of `mix.json` (pool sizes, camera mapping, thresholds). |

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

Conventions: `##` doc lines are normative semantics. All positions in the public API are **Godot world metres** (`Vector3`, x east, z south, y up) unless a parameter says `sub-cell`. Conversion from sim units is `SndUnits.to_world(x, y, h)` = `(x*3/1024, h, y*3/1024)` (ARCHITECTURE §3). `now_ms` everywhere comes from one injectable clock (`SndConfig.clock: Callable`, default `Time.get_ticks_msec`) so tests are deterministic; the OS text-to-speech calls of the announcer are injectable the same way (`SndConfig.tts_voices / tts_speak / tts_stop / tts_speaking`: Callables defaulting to `DisplayServer.tts_get_voices_for_language("en")`, `tts_speak`, `tts_stop`, `tts_is_speaking`).

### 3.1 `SndManager` (autoload `Snd`) — the facade every other module uses

```gdscript
class_name SndManager extends Node

signal announcement_started(line_id: StringName, text: String, priority: int)   ## caption of the line that just started; UI shows it when SndSettings.captions (A-07: no information by sound alone)
signal announcement_finished(line_id: StringName)
signal music_state_changed(state: int, track_id: StringName)                    ## SndMusicDirector.State
signal audio_warning(code: int, message: String)                                ## non-fatal (missing bank, dummy driver, no camera); also goes to Log.warn("snd", ...)

const MODE_BOOT: int = 0
const MODE_MENU: int = 1
const MODE_LOBBY: int = 2
const MODE_LOADING: int = 3
const MODE_MATCH: int = 4
const MODE_POST_MATCH: int = 5

## One-time init from app boot. Loads + validates game/data/audio/*.json, builds buses (SndBus.setup), creates the 2D pool,
## announcer, music director shell and settings. Returns false only when a *data* error makes audio unusable (audio then stays silent, game continues).
func setup(data_dir: String = "res://data/audio") -> bool
func shutdown() -> void                                   ## stop everything, free nodes; idempotent

## Called by the app (or the view's builder) once the battlefield exists AND the game `Camera3D` is current in the same viewport as `world_root`
## (spike rule 2; e.g. the `ViewWorld` node after `build_async`). Creates the 3D pool + listener under `world_root`.
func attach_world(world_root: Node3D) -> bool             ## false + audio_warning if the viewport has no current Camera3D (retried every 1 s)
func detach_world() -> void

func set_mode(mode: int) -> void                          ## MODE_*; drives music context (menu/lobby/none), ambience on/off, mode-specific ducking
## Match lifecycle. begin_match builds SndSoundBank, requests the needed banks (threaded), starts CALM music + ambience once loaded.
func begin_match(cfg: SndMatchConfig) -> void
func load_progress() -> float                             ## 0..1 bank loading; poll from the loading screen
func is_match_ready() -> bool
func end_match(result: int) -> void                       ## SndMatchConfig.RESULT_* → stinger + announcer line, fades music/ambience/loops

## --- per-frame feeds (see 3.2 for order) ---------------------------------------------------------------
## `batch` = `world.events.take()` of this frame (sim_core §3.7): a flat `PackedInt32Array` of 10-int records
## `[type, tick, a, b, c, d, e, f, g, h]` (`SimEvent` catalogue). The app takes it ONCE and hands the same array, read-only, to view, ui, audio and ai;
## audio never retains it. `alpha` = view interpolation factor (0..1), unused by events (loops smooth themselves).
func on_events(world: SimWorld, batch: PackedInt32Array, alpha: float) -> void
func on_frame(world: SimWorld, alpha: float, dt: float) -> void
## Camera pose, pushed by the app every frame after the view's own frame update (3.2), from the view camera's public getters:
## focus = ground point under the screen centre (`ViewCamera.current_focus()`); basis = orientation of the game camera (`ViewCamera.camera.global_basis`, or the basis of
## `listener_transform()`); only its yaw about +Y is used, extracted convention-free as atan2(basis.z.x, basis.z.z), the previous yaw is kept if the camera looks straight down;
## height = camera height above the focus in metres (`ViewCamera.current_height()`; 34-84 m, wide view 110 m) - it drives the zoom scale of 5.3.
func set_camera(focus: Vector3, basis: Basis, height: float) -> void
func set_time_scale(scale: float) -> void                 ## replay/fast-forward: > 2.0 suppresses positional one-shots except priority ≥ 80, never changes pitch
func set_world_paused(paused: bool) -> void              ## pauses pool voices (stream_paused), enables the "muffle" low-pass on Master, keeps UI/music alive

## --- calls from UI / net / view -------------------------------------------------------------------------
func ui(event_id: StringName, gain_db: float = 0.0) -> int              ## flat (non-positional) cue on Ui bus; returns handle (0 = culled)
func announce(line: StringName, priority: int = -1) -> bool             ## -1 = catalogue priority; false if culled/cooling down
func unit_selected(def_idx: int, is_structure: bool, selection_count: int) -> void   ## call once per *committed* selection change (mouse release), not per frame
func unit_ordered(order: int, def_idx: int) -> void                     ## SndUnitResponse.Order; def_idx = DefUnit index of the primary selected unit
func order_denied(def_idx: int, is_structure: bool = false) -> void     ## "cannot" response (the sim's ORDER_FAILED event is routed here by the bridge too)
func play_at(event_id: StringName, world_pos: Vector3, flavour: StringName = &"", gain_db: float = 0.0) -> int   ## generic positional cue (view-only effects)
func stop_handle(handle: int, fade_ms: int = -1) -> void                ## -1 = event's fade_out_ms

func apply_settings(s: SndSettings) -> void                             ## ramped (SndBusFader); persists via SndSettings.save()
func settings() -> SndSettings
func music() -> SndMusicDirector
func pool() -> SndVoicePool
func announcer() -> SndAnnouncer
func stats() -> SndStats
func debug_snapshot() -> Dictionary                                     ## {voices_3d, voices_2d, bus_peaks, music_state, intensity, heat, stems_db[], queue, counters{}}
```

### 3.2 Call and tick order (per rendered frame)

```
App._process(delta):
  1  for each step needed (0..k, lockstep may catch up):  view.capture_prev(world); net.apply_turn(...) / world.step()      # sim_core §3.10
  2  var batch: PackedInt32Array = world.events.take()   # O(1); the buffer restarts empty. ONE take per frame, shared by all consumers
  3  view.frame(delta, alpha)                            # render.md 3.0: camera smoothing, event router, interpolation
     Snd.set_camera(cam.current_focus(), cam.camera.global_basis, cam.current_height())   # app glue, one line; audio has no dependency on any View* class
  4  Snd.on_events(world, batch, alpha)                  # a) newest ≤ 512 records b) classify+filter  c) rank  d) start ≤ MAX_STARTS_PER_FRAME  e) route to announcer / meter / countdown
  5  Snd.on_frame(world, alpha, delta)                   # listener smoothing → scheduler → loops (smoothed positions every frame, scan @4 Hz) → meter → music → announcer → ambience → countdown → pool fades/reaping → bus fader
UI callbacks (unit_selected / ui / announce ...) may be called at any time from the main thread; they never touch the sim.
```
Inside `on_events`, work is bounded by counts: at most `SndConfig.MAX_EVENTS_SCANNED = 512` records are classified per call (the *newest* 512 when a catch-up batch is larger; announcer-class records — economy, alerts, strategic, match — are routed in a first pass over the whole batch and never dropped, the cosmetic combat records are taken from the tail, §6.2), and at most `mix.pool.max_starts_per_frame = 24` sounds are started.

### 3.3 Data layer

```gdscript
class_name SndDataStore extends RefCounted
func load_all(dir: String) -> bool                       ## parse + validate every file; errors[] holds "file: path: message"; unknown keys are errors
var errors: PackedStringArray
var mix: SndMixConfig
var data_version: int                                    ## FNV-1a32 over canonical JSON bytes (diagnostic only, NOT exchanged in the lobby)

class_name SndAssetIndex extends RefCounted
func setup(index_path: String = "res://assets/audio/asset_index.json") -> bool        ## slim runtime index (7.8); full audio_manifest.json is tooling-only and not shipped
func resolve_path(id: String, want_mono: bool) -> String                             ## "res://assets/audio/<id>.mono.ogg" if want_mono and it exists in the index, else "<id>.ogg"
func bank_of(id: String) -> StringName
func group_members(group: String) -> PackedStringArray                               ## "<group>_1" … "<group>_N" (N from the index)
func request_banks(banks: PackedStringArray) -> void                                 ## ResourceLoader.load_threaded_request for every file of the banks
func load_progress() -> float                                                        ## 0..1 over the requested banks
func banks_ready() -> bool
func get_stream(id: String, want_mono: bool) -> AudioStream                          ## cached; null + one warning if absent; never mutated by callers (duplicate() before setting loop/bpm)
func release_banks(banks: PackedStringArray) -> void

class_name SndEventMap extends RefCounted
func build(store: SndDataStore, index: SndAssetIndex) -> bool          ## resolves stream ids → AudioStream for the *loaded* banks; missing = error
var errors: PackedStringArray
func has_event(id: StringName) -> bool
func get_def(id: StringName) -> SndEventDef                            ## null if unknown
func event_ids() -> Array[StringName]                                  ## sorted
func get_profile(id: StringName) -> SndProfileDef                      ## null if unknown
func profile_ids() -> Array[StringName]
func group_limit(group: StringName) -> int
func resolve(kind: StringName, tags: Dictionary) -> StringName         ## sim_map pattern → existing id, else the rule's fallback, else &""
func ensure_flavours(flavours: PackedStringArray) -> void              ## make sure streams of those flavours are loaded (sync); called by begin_match
func missing(data: GameData = null) -> PackedStringArray               ## QA gate DA-23: "kind:id" strings, EMPTY = complete. (a) consumed SimEvent types without a route; (b) ids named by sim_map / power_cues / sw_cues / announcer lines / responses that are absent from events.json, announcer.json, responses.json; (c) with `data`: bakes a temporary SndSoundBank and appends its `unresolved` list (weapon whose fire chain 5.4.1 ends in an absent id, entity def with no profile, DefPower / DefSuperweapon with no cue set)

class_name SndEventDef extends RefCounted   # fields in 4.3
func pick_stream(rng: RandomNumberGenerator, flavour: StringName) -> AudioStream   ## weighted, never repeats the previous pick of the same flavour when > 1 variant
```

### 3.4 `SndVoicePool` — the only place that owns `AudioStreamPlayer*` for one-shot/looped SFX

```gdscript
class_name SndVoicePool extends Node

const INVALID: int = 0                                    ## handle 0 = culled/dropped; handle = (generation << 7) | slot_index (4.2)

func setup(map: SndEventMap, cfg: SndMixConfig, seed_value: int, clock: Callable) -> void   ## creates the 2D pool immediately
func attach_3d(container: Node3D, voices_3d: int) -> void ## creates the 3D pool under `container`; container must live in the viewport with the current Camera3D
func detach_3d() -> void
## Audio space: p' = focus + (p - focus) * inv_scale, inv_scale = 1 / zoom_scale (5.3). Set once per frame by SndListener.
func set_listener(focus: Vector3, inv_scale: float) -> void
func to_audio_space(world_pos: Vector3) -> Vector3
## Level estimate (dB) the voice would have at the listener: def.volume_db + gain + attenuation_db(def, d_eff). Used for culling/stealing.
func estimate_db(def: SndEventDef, world_pos: Vector3, gain_db: float) -> float
## Start by id (event lookup) or by def (already resolved). `pitch_mul` multiplies the def's pitch (engine RPM, propagation, faction offset).
func play(event_id: StringName, world_pos: Vector3 = Vector3.ZERO, flavour: StringName = &"", gain_db: float = 0.0) -> int
func play_def(def: SndEventDef, world_pos: Vector3, flavour: StringName, gain_db: float, pitch_mul: float = 1.0, owner_tag: int = 0) -> int
func stop(handle: int, fade_ms: int = -1) -> void        ## fades then releases (loops: def.fade_out_ms); one-shots: engine stop() (probe: click-free)
func stop_all(fade_ms: int = 100) -> void
func is_active(handle: int) -> bool                      ## O(1): slot = handle & 127, generation check
func set_position(handle: int, world_pos: Vector3) -> void   ## converts to audio space; 3D voices only
func set_gain_db(handle: int, gain_db: float) -> void    ## ramped inside the pool (never a step > 6 dB per frame)
func set_pitch(handle: int, pitch_scale: float) -> void
func set_paused(paused: bool) -> void
func set_gate_priority(min_priority: int) -> void        ## replay fast-forward: plays only events with priority ≥ min (0 = off)
func active_count() -> int                               ## voices that are busy and not fading out
func active_3d() -> int
func active_2d() -> int
func snapshot_3d() -> Array[Dictionary]                  ## [{busy, priority, est_db, event}] for the monitor
static func model_db(def: SndEventDef, distance_m: float) -> float       ## pure attenuation model, clamped at +3 dB (max_db)
static func attenuation_db(def: SndEventDef, distance_m: float) -> float  ## model + linear fade window to max_distance (spike formula, verified ±0.8 dB)
var stats: SndStats
```

### 3.5 `SndListener`

```gdscript
class_name SndListener extends Node3D
func setup(parent: Node3D, pool: SndVoicePool, mix: SndMixConfig) -> bool      ## creates AudioListener3D, make_current(); verifies get_viewport().get_camera_3d() != null
func set_camera(focus: Vector3, basis: Basis, height: float, dt: float) -> void  ## smooths focus (tau = mix.camera.focus_smooth_s), yaw = atan2(basis.z.x, basis.z.z) → Basis(UP, yaw), zoom_scale → pool.set_listener
var focus: Vector3                                   ## smoothed ground focus (world)
var zoom_scale: float                                ## clamp(height / ref_height_m, zoom_scale_min, zoom_scale_max)
func hearing_radius_m() -> float                     ## mix.hearing.max_scan_m * zoom_scale
```

### 3.6 Sim adapters and bridge

```gdscript
class_name SndWorldReader extends RefCounted     # the ONLY audio file that touches SimWorld (sim_core §3.4); every call below is a thin wrapper
func bind(world: SimWorld, viewer_pid: int, omniscient: bool) -> void   ## omniscient = observer/replay: every cell visible, nothing hidden
func tick() -> int                                                ## world.tick
func viewer_pid() -> int
func viewer_team() -> int                                         ## world.team_of(viewer)
func cell_visible(cx: int, cy: int) -> bool                       ## world.cell_visible(viewer, cx, cy); omniscient → true
func relation_of(owner: int) -> int                               ## world.relation(viewer, owner): 0 SELF, 1 ALLY, 2 ENEMY, 3 NEUTRAL (owner −1 → NEUTRAL)
func entity(id: int) -> SimEntity                                 ## world.entity(id); null when gone (dead-but-not-removed entities ARE returned)
func entity_visible(e: SimEntity) -> bool                         ## world.entity_visible(viewer, e) (camouflage-aware); own/allied → true
func query_radius(x: int, y: int, r: int, out: PackedInt32Array) -> int   ## world.query_radius(x, y, r, out, SimTag.ALIVE); ascending ids
func team_within(x: int, y: int, r: int) -> bool                  ## true iff an alive entity of the viewer's team lies within r sub-cells (warning "affected" test)
func map_size() -> Vector2i                                       ## Vector2i(world.map.w, world.map.h) in cells; (0, 0) when there is no map
func terrain_id(cx: int, cy: int) -> int                          ## MapData.terrain_at(idx): MapTerrain id 0..14; GRASS (4) when out of bounds
func terrain_bytes() -> PackedByteArray                           ## MapData.terrain (row-major w×h, shared copy-on-write, never written): one scan builds the ambience grid
func player(pid: int) -> SimPlayer                                ## world.players[pid]: power_state, sw_state, sw_charge, sw_def, power_def[]

class_name SndSoundBank extends RefCounted
func bake(data: GameData, map: SndEventMap, mix: SndMixConfig) -> void       ## < 5 ms; walks data.def_ids / data.def_kinds (single entity-def space, sim_core R1), the weapon table through data.weapon_count() / weapon_id(i) / weapon_arch(i) / def_weapons(def_idx) (§13-6), data.powers, data.superweapons
# --- per weapon_def_idx (the index carried by WEAPON_FIRED / DAMAGE / PROJECTILE_* / BEAM) ---
var weapon_arch: PackedByteArray           ## TAXONOMY WeaponArch 0..26 (frozen ints); 255 = unknown → snd.weapon.small_arms
var weapon_fire: Array[SndEventDef]        ## fire event (null = silent)
var weapon_flavour: PackedStringArray      ## faction code parsed from the weapon id ("weapon.napc.x" → "napc"); "" (shared/unknown) → the shooter owner's faction
var weapon_beam: PackedByteArray           ## 1 = continuous beam weapon (archetype beam_thermal; its fire event carries link_loop / link_end)
var weapon_proj: PackedByteArray           ## flight class from the archetype (SndUnits.ARCH_TABLE, 5.4.2): 0 none/hitscan, 1 bullet-like, 2 missile, 3 arc, 4 bomb, 5 torpedo
var weapon_kind: PackedByteArray           ## warhead kind from the archetype's frozen damage type: 0 bullet, 1 explosive, 2 energy, 3 rail, 4 kinetic, 5 emp
var dtype_kind: PackedByteArray            ## damage_type int (DAMAGE/EXPLOSION events) → warhead kind, via DefDamageTable.damage_ids names
# --- per entity def idx (single dense space; index = SimEntity.def_idx) ---
var def_kind: PackedByteArray              ## SimEntity.Kind
var def_profile: Array[SndProfileDef]      ## never null: derived by archetype/kind, else generic (5.4.7)
var def_armor: PackedByteArray             ## ArmorClass (255 = none)
var def_layer: PackedByteArray             ## home Layer
var def_area: PackedByteArray              ## structure footprint area class s1..s4 → 0..3
var def_death_chain: PackedByteArray       ## 1 if the def has a chain-explosion warhead on death (the explosion then arrives as its own EXPLOSION event)
var def_speed: PackedInt32Array            ## units/tick (loop pitch normalisation)
var def_tags: PackedInt32Array             ## SndSoundBank.TAG_COLLECTOR 1, TAG_LAUNCHER 2, TAG_DEFENSE 4, TAG_RADAR 8, TAG_LAB 16, TAG_HQ 32
# --- powers, superweapons (DefPower / DefSuperweapon idx) ---
var power_cue: Array[Dictionary]           ## {&"activate": def, &"loop": def, &"end": def} (absent phase = no sound)
var power_ready_line: PackedStringArray    ## announcer line id ("" = generic power_ready)
var power_warning_ticks: PackedInt32Array  ## DefPower.warning_t (> 0: hostile activation raises a warning to those inside its radius)
var power_radius: PackedInt32Array         ## DefPower.radius (sub-cells)
var sw_cue: Array[Dictionary]              ## {&"charge"|&"launch"|&"loop"|&"impact"|&"end": def} (absent phase = no sound)
var sw_name: PackedStringArray             ## "atlas" … "trident"
var sw_length: PackedInt32Array            ## line length in sub-cells (Helios path voice): `DefSuperweapon.params.length_cells` × 1024 when the data layer publishes it, else `mix.strategic.helios_length_cells` (bible: 16 cells)
var sw_duration_ticks: PackedInt32Array    ## DefSuperweapon.duration_t (loop lengths: Aurora, Helios, Tempest, Dragonfall, Trident)
var coverage: Dictionary                   ## {units_derived, units_explicit, units_generic, weapons_fallback, ...} for the coverage test
var unresolved: PackedStringArray          ## "weapon:<id>", "def:<id>", "power:<id>", "sw:<id>" entries that ended on a fallback that does not exist (SndEventMap.missing)

class_name SndSimBridge extends RefCounted
func setup(reader: SndWorldReader, bank: SndSoundBank, pool: SndVoicePool, loops: SndLoopManager, meter: SndCombatMeter,
		announcer: SndAnnouncer, countdown: SndCountdown, scheduler: SndScheduler, listener: SndListener, mix: SndMixConfig, seed_value: int) -> void
func process(batch: PackedInt32Array, alpha: float, now_ms: int) -> void      ## the whole of 3.2 step 4; count = batch.size() / 10
var decision_log: PackedStringArray        ## enabled in tests: "event_id@x,z gain flavour handle?" per start (determinism test)
```

### 3.7 Loops, meter, music

```gdscript
class_name SndLoopManager extends RefCounted
func setup(reader: SndWorldReader, bank: SndSoundBank, pool: SndVoicePool, mix: SndMixConfig) -> void
func update(dt: float, now_ms: int) -> void                    ## every frame: chase the latest sim positions (tau 60 ms), pitch, fades; every mix.loops.scan_period_s: re-select
func start_beam(shooter_id: int, weapon_idx: int, start_def: SndEventDef, flavour: StringName) -> void
func stop_beam(shooter_id: int, weapon_idx: int) -> void
func add_path_voice(def: SndEventDef, from: Vector3, to: Vector3, start_ms: int, duration_ms: int, flavour: StringName, gain_db: float) -> void
func clear() -> void
func active_loops() -> int

class_name SndCombatMeter extends RefCounted
func configure(meter_cfg: Dictionary) -> void                  ## music.json "meter" block
func add(weight: float, dist_m: float, own: bool) -> void       ## already class-weighted by the bridge (5.7)
func update(dt: float) -> void
var heat: float; var intensity: float; var far_heat: float      ## intensity 0..1 (attack/release smoothed), far_heat = own-side action beyond hearing radius
func wants_combat(now_ms: int) -> bool                           ## hysteresis with holds (5.7)

class_name SndMusicLibrary extends RefCounted
func setup(store: SndDataStore, index: SndAssetIndex) -> void
func request_set(faction: StringName) -> void                    ## threaded bank load for the faction's tracks
func set_ready(faction: StringName) -> bool
func build_interactive(faction: StringName) -> SndMusicLibrary.Built   ## {stream: AudioStreamInteractive, sync: Dictionary[StringName(clip)->AudioStreamSynchronized], clip_index: Dictionary}

class_name SndMusicDirector extends Node
enum State { NONE = 0, MENU = 1, CALM = 2, COMBAT = 3, STINGER = 4 }
func setup(lib: SndMusicLibrary, store: SndDataStore) -> void
func enter_menu() -> void                                        ## menu theme, intensity from music.json contexts
func enter_match(faction: StringName) -> void                    ## CALM at intensity 0.2
func request_state(state: int, urgent: bool = false) -> void     ## CALM/COMBAT only; ignored while a transition is pending or within min_switch_interval (5.8)
func set_intensity(v: float) -> void                             ## 0..1 within the active clip; smoothed, ramped per frame
func play_stinger(stinger_id: StringName, fade_music_ms: int = 1200) -> void
func stop(fade_ms: int = 1500) -> void
func current_state() -> int
func is_transition_pending() -> bool
func stem_levels_db() -> PackedFloat32Array                      ## [drums, bass, pads, lead] for monitor/tests
func update(dt: float, now_ms: int) -> void
```

### 3.8 Announcer and unit responses

```gdscript
class_name SndAnnouncer extends Node
func setup(store: SndDataStore, index: SndAssetIndex, clock: Callable, seed_value: int) -> void
func set_pack(pack: StringName) -> void                          ## &"computer" or a faction code; missing line in pack → &"computer" pack; missing everywhere → false
func set_mode(mode: int) -> void                                 ## SndSettings.ANN_FACTION / ANN_COMPUTER / ANN_OFF
func set_tts(enabled: bool) -> void                              ## SndSettings.announcer_tts (5.9 step 8); stays false + one audio_warning when the OS offers no English voice
func tts_available() -> bool                                     ## not DisplayServer.tts_get_voices_for_language("en").is_empty()
func say(line: StringName, priority: int = -1, args: Dictionary = {}) -> bool   ## true = played or queued
func is_speaking() -> bool
func queue_size() -> int
func clear_queue() -> void
func update(dt: float, now_ms: int) -> void
signal started(line_id: StringName, text: String, priority: int)     ## text = the caption from announcer.json (UI shows it when SndSettings.captions)
signal finished(line_id: StringName)

class_name SndUnitResponse extends RefCounted
enum Order { MOVE = 0, ATTACK = 1, GUARD = 2, DEPLOY = 3, CAPTURE = 4, REPAIR = 5, LOAD = 6, UNLOAD = 7, HARVEST = 8, STOP = 9, SCATTER = 10, SELL = 11 }
enum RType { SELECT = 0, MOVE = 1, ATTACK = 2, DENY = 3, SPECIAL = 4 }
func setup(store: SndDataStore, index: SndAssetIndex, host: Node, clock: Callable, seed_value: int) -> void   ## creates 2 dedicated AudioStreamPlayers on bus Voice under `host` (outside the pool: never stolen)
func set_faction(faction: StringName) -> void
func set_mode(mode: int) -> void                                 ## SndSettings.UV_SYNTH / UV_VOICE / UV_MIXED / UV_OFF
func on_selected(voice_class: int, is_structure: bool, count: int, now_ms: int) -> void
func on_order(order: int, voice_class: int, now_ms: int) -> void
func on_denied(voice_class: int, now_ms: int) -> void
```

### 3.9 Ambience, countdown, scheduler, bus, settings

```gdscript
class_name SndAmbience extends Node
func setup(store: SndDataStore, index: SndAssetIndex, reader: SndWorldReader) -> void
func set_environment(family: int, biome: int) -> void            ## MapData.family (0 open, 1 urban, 2 coast/river) and MapData.biome (0 temperate, 1 desert, 2 arctic, 3 tropical); builds the 8×8-cell summary grid from reader.terrain_bytes()
func update(dt: float, focus: Vector3, zoom_scale: float, far_heat: float) -> void   ## 2 Hz terrain histogram, per-frame layer gain ramps
func stop(fade_ms: int) -> void

class_name SndCountdown extends RefCounted
func on_warning(owner_pid: int, sw_idx: int, x: int, y: int, exec_tick: int, extent: int, launcher_id: int, hostile: bool) -> void   ## from SW_WARNING; exec_tick = event tick + warning_ticks
func on_power_warning(power_idx: int, x: int, y: int, exec_tick: int, radius: int, hostile: bool) -> void   ## hostile POWER_USED with DefPower.warning_t > 0 (barrage, scan)
func on_cancelled(owner_pid: int, sw_idx: int) -> void           ## SW_CANCELLED / SW_LAUNCHED ends the warning
func update(sim_tick_f: float, dt: float) -> void                ## sim_tick_f = world.tick + alpha; re-tests "affected" every 0.5 s; TPS from SimConfig.TPS
func set_charge(fraction: float, shortage: bool) -> void         ## own superweapon charge-hum pitch (polled 2 Hz by the manager from SimPlayer.sw_charge)

class_name SndScheduler extends RefCounted
func push(due_ms: int, def: SndEventDef, world_pos: Vector3, flavour: StringName, gain_db: float, tag: int) -> bool   ## false when full (64)
func pop_due(now_ms: int, out_idx: PackedInt32Array) -> int
func cancel_tag(tag: int) -> void

class_name SndBus extends RefCounted
const MASTER: StringName = &"Master"; const MUSIC: StringName = &"Music"; const SFX: StringName = &"Sfx"; const AMBIENCE: StringName = &"Ambience"
const UI: StringName = &"Ui"; const VOICE: StringName = &"Voice"; const ANNOUNCER: StringName = &"Announcer"; const SFX_HEAVY: StringName = &"SfxHeavy"
static func setup(mix: SndMixConfig) -> bool                     ## idempotent: adds missing buses in the order of 4.1, (re)configures effects; never removes foreign buses
static func bus_index(name: StringName) -> int
static func verify() -> PackedStringArray                        ## returns violations (index order, sends, sidechain names) — used by test_snd_bus

class_name SndBusFader extends RefCounted
func set_target_db(bus: StringName, db: float, ramp_ms: int = 100) -> void
func set_effect_enabled(bus: StringName, effect_id: StringName, enabled: bool, ramp_ms: int = 100) -> void   ## enable ramps a wet/gain proxy, then flips the flag
func update(dt: float) -> void

class_name SndSettings extends RefCounted   # fields in 4.5
func load_from(cfg: ConfigFile) -> void
func save_to(cfg: ConfigFile) -> void
static func slider_to_linear(v: int) -> float                    ## (v/100)^2, 0 → exactly 0.0 (mute)
```

### 3.10 Ownership of memory and lifetimes

| Object | Owner | Lifetime / rule |
|---|---|---|
| `SndManager` and every `Snd*` Node | `SndManager` (child nodes) except 3D voices | created in `setup`; freed in `shutdown` |
| 3D `AudioStreamPlayer3D` ×N, `AudioListener3D` | container `Node3D` under the view's world root (created by `attach_world`) | freed by `detach_world` / world root free |
| `AudioStream` resources | `SndAssetIndex` cache (ref-counted) by bank | a bank is dropped when no `begin_match` references it; **never mutate a cached stream** — loops/BPM are set on `duplicate()`s (spike) |
| `SimEvent`, `SimEntity`, `GameData`, `SimWorld` | sim/app | **borrowed** for the duration of the call; audio stores only ints/ids (entity ids, def indices) |
| Parsed JSON dictionaries | `SndDataStore` | converted to typed defs at load; raw dictionaries dropped |
| Per-frame scratch (`PackedInt32Array`, candidate arrays) | `SndSimBridge` / `SndLoopManager` | allocated once, reused (no per-event allocation on the hot path) |

### 3.11 Calls other modules must make (the whole audio surface of the game)

| Caller | Call | When |
|---|---|---|
| `app` | `Snd.setup()`; register autoload `Snd="*res://src/audio/snd_manager.gd"`; `set_mode(MODE_*)`; `begin_match(cfg)` / `is_match_ready()`; `attach_world(world_root)` after `view.build_async`; per frame after `view.frame`: `set_camera(...)`, then `on_events(world, batch, alpha)` + `on_frame` with the one `batch = world.events.take()` of that frame; `end_match(result)`; `apply_settings` | boot / scene flow / main loop |
| `view` | keep the game `Camera3D` current in the viewport that will host the audio 3D root; publish `current_focus()` / `camera.global_basis` / `current_height()` (already in render.md 3.3); optional `play_at` for view-only effects. No call into `Snd` is required (the app forwards the pose) | world build |
| `ui` | `ui(&"snd.ui.*")` for widgets; `unit_selected/unit_ordered/order_denied`; audio options panel via `SndSettings`; subscribe to `announcement_started` for toasts. All gameplay announcements (build ready, cancelled, on hold, funds, alerts, …) are **event-driven** (6.2): the UI never announces them | input/UI handlers |
| `net` / lobby | `ui(&"snd.ui.lobby_join"/"lobby_leave"/"lobby_ready"/"lobby_countdown_tick"/"lobby_start"/"chat")`; `announce(&"player_disconnected")`; `set_time_scale(x)` for replays | lobby events, replay controls |

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Bus layout (built by `SndBus.setup`; the reference index order below is enforced by `SndBus.verify`)

Every send goes to a **lower** index (the engine's natural mix direction) and the two hidden ducking-key buses sit at the top. `[probe]` verified this exact layout (key bus `Announcer` at index 6 ducking `Music` at index 1, `Announcer` sending into `Voice`); the reversed order (key bus at a lower index than the listener) ducked identically in steady state (−4.6 dB), so the order is a convention that avoids any sidechain latency question, not a functional requirement.

| idx | Bus | Send | Default dB | Effects in order (`id`: parameters) | Purpose |
|---:|---|---|---:|---|---|
| 0 | `Master` | — | 0 | `night` `AudioEffectCompressor` **disabled** (thr −24 dB, ratio 3, attack 20 000 µs, release 250 ms, gain +4 dB) · `muffle` `AudioEffectLowPassFilter` **disabled** (1200 Hz) · `limiter` `AudioEffectHardLimiter` (ceiling **−1.0 dB**, pre-gain 0, release 0.1) | safety limiter, "night mode", pause muffle |
| 1 | `Music` | Master | −6 | `duck_ann` `AudioEffectCompressor` sidechain=`Announcer`, thr **−18 dB**, ratio **3**, attack 12 000 µs, release 450 ms · `duck_heavy` sidechain=`SfxHeavy`, thr −12 dB, ratio 2, attack 8 000 µs, release 350 ms `[tune]` | music, ducked by announcer and by huge booms |
| 2 | `Sfx` | Master | −2 | — | all gameplay one-shots and loops |
| 3 | `Ambience` | Master | −8 | `duck_heavy` sidechain=`SfxHeavy`, thr −16 dB, ratio 2.5, attack 8 000 µs, release 400 ms `[tune]` | beds |
| 4 | `Ui` | Master | −2 | — | menu clicks, alert pings, lobby cues |
| 5 | `Voice` | Master | 0 | — | announcer (through child bus `Announcer`) and unit acknowledgements (bleeps/barks); user slider "Voice" |
| 6 | `Announcer` | Voice | 0 | — | **hidden**: announcer lines play here; it is the ducking key |
| 7 | `SfxHeavy` | Sfx | 0 | — | **hidden**: events with `"bus": "SfxHeavy"` (explosion large/huge, collapse, superweapon impacts, artillery/railguns ≥ priority 60) are the second ducking key |

Rationale for the two hidden buses: unit acknowledgements (frequent, short) must **not** pump the music, so only the announcer keys `duck_ann`; unit responses live on `Voice` directly (not on `Announcer`). Spike measurement `[spike]` on the un-hidden layout: real announcer lines (−18 LUFS) gave −17.0 dB (thr −24 dB, 4:1), **−8.8 dB (thr −18 dB, 3:1, chosen)**, −2.6 dB (thr −14 dB, 2.5:1). `[probe]` on the hidden-key layout with a speech-level tone (−14.3 dBFS): −4.6 dB and full recovery (−0.5 dB) within 2.5 s; with a loud continuous tone −15.8 dB — i.e. the depth is content-dependent, the *mechanism* works, and the acceptance is measured with real lines (§10.3, target −6…−10 dB).

### 4.2 Voice-pool structures

`handle: int = (generation << 7) | slot_index`, `slot_index ∈ [0,127]` (3D region 0..87, 2D region 88..127), `generation ∈ [1, 2²⁴−1]` wrapping past 0. `INVALID = 0`. `is_active(h)` = `slots[h & 127].handle == h and slots[h & 127].busy`. No dictionary lookup; no allocation.

```gdscript
class SndVoicePool.Slot extends RefCounted
var p3: AudioStreamPlayer3D          # null in the 2D region
var p2: AudioStreamPlayer            # null in the 3D region
var def: SndEventDef                 # event currently playing (null when free)
var handle: int                      # 0 when free
var busy: bool
var fading: bool                     # ramping to silence; counts as free for limits, first choice as steal victim
var start_ms: int
var est_db: float                    # level estimate at start (def.volume_db + gain + attenuation), for stealing
var gain_db: float                   # caller gain (set_gain_db)
var vol_db: float                    # applied player volume_db (jitter + gain + fog/muffle)
var ramp_from_db: float; var ramp_to_db: float; var ramp_t_ms: int; var ramp_dur_ms: int; var ramp_stop_at_end: bool
var owner_tag: int                   # loop manager / scheduler tag (entity id or path id), 0 = none
var world_pos: Vector3               # last requested world position
```

Pool counters (mechanism constants in `SndConfig`, sizes from `mix.pool`): 3D budget `voices_3d` = 24 / 40 / **48** (quality Low/Medium/High), 2D budget **16**; `reserve_high_slots = 6`, `reserve_high_priority = 70`, `max_starts_per_frame = 24`, `steal_margin = 1.0`, `age_penalty_per_s = 1.0`, `cull_below_db = −42`.

### 4.3 `SndEventDef` (resolved event)

```gdscript
class_name SndEventDef extends RefCounted
enum Spatial { UI = 0, GLOBAL = 1, WORLD_3D = 2 }
enum Steal { NONE = 0, OLDEST = 1, QUIETEST = 2 }
enum Fog { HIDDEN = 0, MUFFLED = 1, AUDIBLE = 2 }

var id: StringName;            var index: int          # index = position in the sorted id list (dense)
var category: StringName                                # "weapon","impact","explosion","death","loop","struct","eco","power","strategic","alarm","ui","ambience"
var bus: StringName;           var bus_index: int       # cached AudioServer index (SndBus.bus_index)
var priority: int                                       # 0..100 (scale in 5.2)
var streams: Array[AudioStream];       var weights: PackedFloat32Array       # default variants (mono files when spatial == WORLD_3D)
var flavour_streams: Dictionary;       var flavour_weights: Dictionary       # StringName flavour -> Array[AudioStream] / PackedFloat32Array
var volume_db: float;          var volume_jitter_db: float                   # jitter uniform ±
var pitch: float;              var pitch_jitter_semitones: float             # pitch_scale = pitch * 2^(U(−j, +j)/12)
var spatial: int                                          # Spatial
var unit_size_m: float;        var max_distance_m: float                     # metres in *audio space* (5.3)
var attenuation: int                                      # AudioStreamPlayer3D.AttenuationModel
var lowpass_hz: float;         var panning_strength: float                   # attenuation_filter_cutoff_hz (20500 = off), per-node panning
var doppler: bool                                         # DOPPLER_TRACKING_IDLE_STEP for aircraft loops
var propagation: bool                                     # apply speed-of-sound delay (5.4)
var fog: int                                              # Fog policy for events from unseen cells (5.5)
var fog_gain_db: float;        var fog_lowpass_hz: float                     # used when fog == MUFFLED
var group: StringName;         var max_instances: int;  var min_interval_ms: int;  var steal: int
var loop: bool;                var fade_in_ms: int;     var fade_out_ms: int
var cull_below_db: float
var link_loop: StringName;     var link_end: StringName   # beam: start → loop → end event ids
var tags: PackedStringArray
# --- bookkeeping owned by SndVoicePool ---
var active_count: int;         var last_play_ms: int;    var _last_variant: Dictionary   # flavour -> last picked index
```

### 4.4 Other typed containers

```gdscript
class_name SndProfileDef extends RefCounted
var id: StringName;            var parent: StringName            # single inheritance, resolved at load
var voice_class: int                                             # SndUnitResponse voice class (4.6)
var loops: Array[Dictionary]                                     # [{event: StringName, when: int (LoopWhen), gain_db: float, pitch_speed: bool}]
var die: StringName;           var spawn: StringName;  var select_fx: StringName   # optional event overrides ("" = derive)
var scalars: Dictionary                                          # future per-profile tuning

class_name SndMatchConfig extends RefCounted
const RESULT_NONE: int = 0; const RESULT_VICTORY: int = 1; const RESULT_DEFEAT: int = 2; const RESULT_DRAW: int = 3; const RESULT_ABORT: int = 4
var data: GameData;            var local_pid: int;     var local_team: int
var observer: bool;            var replay: bool                  # observer/replay: omniscient hearing, no announcer/responses
var player_factions: PackedStringArray                           # index = pid → lower-case faction code ("napc"), "" = empty slot
var local_roster_id: String                                      # "roster.napc.canada"
var family: int                                                  # MapData.family: 0 open, 1 urban, 2 coast/river (terrain_movement 3.3)
var biome: int                                                   # MapData.biome: 0 temperate, 1 desert, 2 arctic, 3 tropical
var match_seed: int                                              # MatchConfig seed → audio RNG seed (presentation only)

class_name SndMixConfig extends RefCounted   # parsed mix.json; fields = the JSON keys of 7.2 (typed)

class_name SndSettings extends RefCounted
const ANN_FACTION: int = 0; const ANN_COMPUTER: int = 1; const ANN_OFF: int = 2
const UV_SYNTH: int = 0; const UV_VOICE: int = 1; const UV_MIXED: int = 2; const UV_OFF: int = 3
const MUSIC_DYNAMIC: int = 0; const MUSIC_CALM_ONLY: int = 1; const MUSIC_OFF: int = 2
const DR_FULL: int = 0; const DR_NIGHT: int = 1
const Q_LOW: int = 0; const Q_MEDIUM: int = 1; const Q_HIGH: int = 2
var master: int = 100; var music: int = 70; var sfx: int = 90; var voice: int = 100; var ui: int = 80; var ambience: int = 70    # 0..100
var announcer_mode: int = ANN_FACTION;   var unit_voice_mode: int = UV_SYNTH;   var music_mode: int = MUSIC_DYNAMIC
var dynamic_range: int = DR_FULL;        var quality: int = Q_MEDIUM;           var mute_unfocused: bool = true
var captions: bool = true;               var output_device: String = "Default"
var announcer_tts: bool = false                                  # accessibility: OS text-to-speech announcer (A-14), stored under [access]
```
`[audio]` keys in `user://settings.cfg`: `master, music, sfx, voice, ui, ambience` (ints), `announcer, unit_voices, music_mode, dynamic_range, quality` (ints), `mute_unfocused, captions` (bool), `output_device` (String); `[access]`: `announcer_tts` (bool, default false). The names `master, music, sfx, voice, ui, mute_unfocused, captions` and `[access] announcer_tts` are the ones qa.md fixes (QA-XR-13); the others are audio's additions, and `voice` is the slider of the `Voice` bus (announcer + unit responses). Unknown/missing keys keep defaults. `captions` only decides whether the UI shows the caption of `announcement_started`; the signal is always emitted. Slider → linear = `(v/100)²` (v = 0 → mute), bus dB = `mix_default_db + linear_to_db(linear)`; e.g. Music 70 → 0.49 → −6.2 dB → −12.2 dB net.

### 4.5 Bridge / loop / scheduler / announcer / meter / music state

```gdscript
# SndSimBridge candidate table (preallocated, capacity 512; parallel arrays, no per-event objects; the input batch is read in place, stride 10)
var _c_def: Array[SndEventDef];  var _c_pos: PackedVector3Array;  var _c_score: PackedFloat32Array
var _c_gain: PackedFloat32Array; var _c_src: PackedInt32Array      # source entity id (per-source throttle)
var _c_flav: Array[StringName];  var _c_delay_ms: PackedInt32Array # > 0 → goes to SndScheduler instead of the pool
var _last_fire_ms: PackedInt32Array                                # size 1024, index = entity id & 1023 (per-source 40 ms throttle)
var _route: PackedByteArray                                        # size 128: SimEvent type (0x00–0x7F) → route id (SndSimBridge.R_*); 0 = ignore
var _boom_key: PackedInt32Array; var _boom_tick: PackedInt32Array  # 64-entry ring: dedupe of PROJECTILE_IMPACT vs EXPLOSION at the same spot/tick

# SndLoopManager
var _ent_id: PackedInt32Array;   var _ent_handle: PackedInt32Array;  var _ent_event: Array[SndEventDef]   # active entity loops (≤ mix.loops.budget)
var _ent_prev: PackedVector3Array; var _ent_cur: PackedVector3Array;  var _ent_speed: PackedFloat32Array;  var _ent_pitch: PackedFloat32Array
var _path_*: parallel arrays (from, to, start_ms, dur_ms, handle, def) capacity 24
var _beam: Dictionary                                              # key = entity_id * 8 + mount → handle (≤ 32)

# SndScheduler: capacity 64, sorted by due_ms; item = {due_ms, def, pos, flavour, gain_db, tag}
# SndAnnouncer
class SndAnnouncer.Item extends RefCounted:  var line: StringName; var priority: int; var enq_ms: int; var expire_ms: int; var args: Dictionary
var _queue: Array[Item]  (cap 4);  var _current: Item;  var _last_said: Dictionary   # line → ms;  var _cat_last: Dictionary   # category → ms
# SndCombatMeter
var heat: float; var intensity: float; var far_heat: float; var _above_since_ms: int; var _below_since_ms: int; var _combat_since_ms: int
# SndMusicDirector
var _state: int; var _pending: int; var _pending_since_ms: int; var _last_switch_ms: int; var _intensity_target: float; var _stem_cur: PackedFloat32Array; var _stem_tgt: PackedFloat32Array
var _built: SndMusicLibrary.Built; var _player: AudioStreamPlayer; var _stinger_player: AudioStreamPlayer; var _clip_of_state: Dictionary
```

### 4.6 Enumerations (integer values are frozen once shipped; they appear in tests and saved settings)

| Enum | Values |
|---|---|
| `SndSimBridge.R_*` routes (each groups `SimEvent` types; the handler switches on the type inside the route) | `IGNORE 0, LIFECYCLE 1 (SPAWNED, REMOVED, OWNER_CHANGED), DIED 2, STATE 3, CARGO 4 (LOADED, UNLOADED), DAMAGE 5, FIRED 6, PROJECTILE 7 (LAUNCHED, IMPACT), EXPLOSION 8, BEAM 9, INTERCEPT 10, ECONOMY 11 (CASH, HARVEST_DELIVERED, SALVAGE), POWER_GRID 12 (POWER_LOW/RESTORED), PRODUCTION 13 (BUILD_*, PRODUCTION_COMPLETE, RESEARCH_*, TECH_*, QUEUE_BLOCKED, UNIT_CAP_REACHED), SUPPORT_POWER 14 (POWER_USED, POWER_READY), SUPERWEAPON 15 (SW_*), ALERT 16 (BASE/UNIT/HARVESTER_UNDER_ATTACK), ORDER_FEEDBACK 17 (ORDER_FAILED, CMD_REJECTED), MATCH 18 (PLAYER_ELIMINATED, MATCH_END, PAUSED, UNPAUSED)` |
| `LoopWhen` | `ALWAYS 0, MOVING 1, AIRBORNE 2, STRUCTURE_ACTIVE 3, CHARGING 4` |
| `VoiceClass` | `INFANTRY 0, VEHICLE 1, HEAVY 2, AIR 3, NAVAL 4, SUPPORT 5, STRUCTURE 6` |
| `SndMusicDirector.State` | `NONE 0, MENU 1, CALM 2, COMBAT 3, STINGER 4` |
| Material (`SndUnits.MAT_*`) | `DIRT 0, CONCRETE 1, METAL 2, FLESH 3, WOOD 4, WATER 5` |
| Size (`SndUnits.SIZE_*`) | `TINY 0, SMALL 1, MEDIUM 2, LARGE 3, HUGE 4` |
| Warhead kind | `BULLET 0, EXPLOSIVE 1, ENERGY 2, RAIL 3, KINETIC 4, EMP 5` |
| Announcer priority bands | `ROUTINE 0–49, NOTICE 50–69, WARNING 70–89, ALERT 90–100` |
| Event priority bands (5.2) | `AMBIENCE 0–9, LOOPS 10–24, SMALL_ARMS 25–39, MEDIUM 40–59, HEAVY 60–69, BIG_BOOM 70–89, ALARM/ANNOUNCE/UI 90–100` |
| Sim enums consumed (frozen in the sibling specs) | `SimEntity.Kind UNIT 0, STRUCTURE 1, WRECK 2, ZONE 3, DEPOSIT 4` · `SimEntity.Layer GROUND 0, AIR 1, SURFACE 2, UNDERWATER 3` · `SimWorld.Rel SELF 0, ALLY 1, ENEMY 2, NEUTRAL 3` · `SimPlayer.PowerState OK 0, LOW 1` · `SimPlayer.SwState NONE 0, CHARGING 1, READY 2, WARNING 3` · spawn/remove/die reasons and `ST_*` states (sim_core §4.1, §6.2) · `DamageType BULLET 0, AP 1, HE 2, THERMAL 3, RAIL 4, KINETIC 5, EMP 6` · `ArmorClass INFANTRY 0 … FORTRESS 10` · `MoveClass FOOT 0 … STATIC 8` · `MapTerrain` ids `deep_water 0, shallow 1, ford 2, beach 3, grass 4, dirt 5, sand 6, rock 7, forest 8, road 9, pavement 10, rubble 11, urban_block 12, cliff 13, mountain 14` (terrain_movement 4.2) · `MapData.family open 0, urban 1, coast 2` · `MapData.biome temperate 0, desert 1, arctic 2, tropical 3` |

### 4.7 `SndConfig` mechanism constants (code) vs `mix.json` tunables (data)

| Constant (code) | Value | Why fixed in code |
|---|---:|---|
| `M_PER_CELL` / `UNITS_PER_CELL` / `M_PER_UNIT` | 3.0 / 1024 / 3/1024 | ARCHITECTURE §3 |
| `MAX_SLOTS`, `SLOT_BITS` | 128, 7 | handle layout |
| `POOL_3D_MAX`, `POOL_2D_MAX` | 88, 40 | array sizes |
| `MAX_EVENTS_SCANNED`, `MAX_CANDIDATES` | 512, 512 | array sizes |
| `SOURCE_THROTTLE_SLOTS` | 1024 | hashed per-source throttle |
| `MAX_GAIN_DB` | +3.0 | Godot `AudioStreamPlayer3D.max_db` default `[docs]` |
| `SILENT_DB` | −80.0 | ramp floor |
| `RAMP_MAX_STEP_DB_PER_FRAME` | 6.0 | volume changes are always ramped (spike rule 3) |
| `SndUnits.BUILDUP_SECONDS` | 1.5 | length of the structure build-up = economy `buildup_ticks` 30 at 20 TPS (economy.json; the view animates `st_until − st_t0` of the same state); the `online_*` one-shots put their "online" accent at this time (V-AUD-27 compares it with the catalogue's copy and with `economy.json`) |

Everything else (levels, ranges, priorities, thresholds, fades, cooldowns, weights) is data. `mix.json` keys are listed in §7.2.

### 4.8 The `snd.*` id grammar (contract with data/balance/view/ui)

Ids are lower-case `snake_case` segments joined by `.`; the audio registry `events.json` holds exactly these. **Balance authors write no sound ids for the normal case**: the derivation rules in 5.4 map every unit, structure, weapon, warhead, power and superweapon to ids below automatically from data the balance layer already has (role archetype, weapon archetype, footprint, faction code). An explicit `pres_snd_profile` is only for deliberate overrides of a unit or structure and must name an id from this table (V-REF-02); weapons carry no presentation fields, so a per-weapon override lives in audio's own `events.json` (`sim_map.weapon_override`).

| Family | Ids (initial content; ≈ 220 events + 77 profiles) |
|---|---|
| Weapon fire | `snd.weapon.<archetype>` for the 27 archetypes of TAXONOMY §10 (`small_arms … drone_missile`), **except** `tank_cannon` → `snd.weapon.tank_cannon_light\|_medium\|_heavy`; beams: `snd.weapon.beam_thermal` (start) + `.loop` + `.end`; reserved `snd.weapon.unique.<name>` (empty in v1) |
| Projectile flight | `snd.proj.missile`, `.torpedo`, `.shell_whistle`, `.bomb_whistle` |
| Impacts | `snd.impact.bullet.<dirt\|concrete\|metal\|flesh\|wood\|water>`, `snd.impact.energy.<small\|large>`, `snd.impact.rail`, `.kinetic`, `.emp` |
| Explosions / deaths | `snd.explosion.<small\|medium\|large\|huge>`, `snd.explosion.water.<small\|medium\|large>`, `snd.collapse.<s1\|s2\|s3\|s4>`, `snd.death.<infantry\|decoy\|ship\|sub\|drone>`, `snd.intercept.<aps\|zone>`, `snd.emp.hit` |
| Movement loops | `snd.loop.step.foot`, `snd.loop.engine.<wheeled\|tracked\|tracked_heavy\|amphibious\|boat_small\|boat_large\|sub>`, `snd.loop.air.<jet\|rotor\|drone>`, `snd.air.<takeoff\|landing\|crash_fall>` |
| Structures / economy | `snd.struct.online.<hq\|generator\|refinery\|barracks\|factory\|dock\|radar\|airfield\|laboratory\|watchtower\|turret\|aa_battery\|relay\|superweapon\|adv_defense>`, `snd.struct.sell`, `.repair` (loop), `.power_down`, `.power_up`, `.defense_offline`, `.unit_out.<infantry\|vehicle\|aircraft\|ship>`, `.captured`, `.salvage` (loop), `.hq_deploy`, `.hum.<generator\|radar\|lab\|airfield\|refinery>` (loops), `snd.eco.cash`, `snd.eco.cash_big` |
| Support powers | `snd.power.<recon\|repair\|buff\|shield\|cloak\|smoke\|barrage\|generic>.<activate\|loop\|end>`, `snd.power.barrage.warning`, `.impact` |
| Superweapons | `snd.sw.<atlas\|aurora\|helios\|perun\|tempest\|dragonfall\|horizon\|trident>.<charge\|launch\|loop\|impact\|end>` (each name uses the phases it needs) |
| Alarms | `snd.alarm.sw_siren` (loop), `.countdown_tick`, `.countdown_final`, `.base_attack`, `.incoming`, `.low_power` |
| UI | `snd.ui.<click\|hover\|confirm\|error\|back\|tab\|toggle_on\|toggle_off\|slider_tick\|queue_add\|queue_cancel\|queue_hold\|build_ready\|place_ok\|place_fail\|sell_mode\|repair_mode\|group_set\|group_recall\|waypoint\|rally_set\|minimap_ping\|minimap_click\|alert\|chat\|lobby_join\|lobby_leave\|lobby_ready\|lobby_countdown_tick\|lobby_start\|menu_transition\|notify>` |
| Ambience | `snd.amb.<wind_open\|city_hum\|coast_waves\|river_flow\|forest\|battle_far>` |
| Profiles (77) | `snd.profile.<archetype>` (the 32 role archetypes of TAXONOMY §9), `snd.profile.svc_<engineer\|collector\|mcv\|landing_transport>`, `snd.profile.<summon_drone\|summon_capsule\|decoy>`, `snd.profile.struct.<hq\|generator\|refinery\|barracks\|factory\|dock\|radar\|airfield\|laboratory\|watchtower\|turret\|aa_battery\|relay>` (13) + `snd.profile.struct.sw_<faction>` (8) + `snd.profile.struct.adv_<faction>` (8) — one per structure def (29), `snd.profile.generic.<foot\|wheeled\|tracked\|amphibious\|naval\|submerged\|air_fixed\|air_hover\|static>` (9, last-resort fallbacks) |
| Not in `events.json` | announcer line ids (`announcer.json`, plain `snake_case`, e.g. `base_under_attack`), music track/stinger ids (`music.json`, e.g. `napc.combat`, `stinger.napc.victory`), unit-response ids (`responses.json`) |

Flavour keys (the `flavours` object of an event; also announcer packs and response packs) are the 8 lower-case faction codes `napc nec olm def pd han ae sap`, plus `computer` for the announcer. An unknown flavour falls back to the event's default `streams`.

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Mixing rules, ducking and loudness targets

**Mixing rules (binding)**
1. **One limiter only**: `Master` `AudioEffectHardLimiter` (ceiling −1.0 dB). No per-bus limiters (they pump against each other).
2. **Balance lives in the assets and in `SndEventDef.volume_db`**, not in bus faders. Bus faders (§4.1 defaults) exist for the user sliders, ducking and pause; the defaults are set once so that sliders at their defaults reproduce the reference mixes below.
3. **Ducking**: announcer → Music (`duck_ann`, target −6…−10 dB, spike-chosen thr −18 dB / 3:1 / 12 ms / 450 ms); huge booms → Music (−2…−5 dB) and Ambience (−3…−6 dB) through `SfxHeavy` `[tune]`. Unit responses never duck anything.
4. **Every volume change is ramped** (spike rule 3: `AudioStreamSynchronized` step 23.4×, `set_bus_volume_db` 20.8×, `AudioStreamPlayer.volume_db` 9.3× a sine's natural step; a 15-step 60 fps ramp 0.91×). Implementations: `SndBusFader` (bus), `SndMusicDirector` (stem volumes: only when |Δ| ≥ 0.05 dB, tau 0.8 s), pool ramps (`Slot.ramp_*`, ≤ 6 dB/frame), `SndAmbience` (1.5 s in / 2.5 s out).
5. **Stereo LF is mono** (LR4 crossover 140 Hz in the build chain `[spike]`: LF L/R correlation ≥ 0.93), so mono downmix on laptop speakers/phones does not cancel booms.
6. **Bass is made audible on small speakers** by a psychoacoustic exciter in the build chain (200 Hz–2 kHz power share: tank 2.2→7.0 %, howitzer 1.1→4.8 %, explosion_small 2.5→7.3 % `[spike]`), not by boosting sub-bass.
7. **Event `volume_db` ∈ [−24, +3]**; `validate_audio.py` rejects others (V-AUD-17).
8. **Focus and pause**: `NOTIFICATION_APPLICATION_FOCUS_OUT` (`[docs]`) with `mute_unfocused` ramps `Master` to −∞ in 200 ms (`FOCUS_IN` restores it); `set_world_paused(true)` sets `stream_paused` on pool voices and ramps the `muffle` low-pass (1200 Hz) on `Master`; music, UI and announcer keep running (`SndManager.process_mode = PROCESS_MODE_ALWAYS`).

**Asset loudness targets** (K-weighted, gated BS.1770/EBU R128; the build's numpy meter agrees with ffmpeg `ebur128` within 0.2 LU `[spike]`; sounds shorter than 1 s are zero-padded to 1 s before gating)

| Class | Target (LUFS-I) | True-peak ceiling | Notes |
|---|---|---|---|
| Transient one-shots (weapons, impacts, explosions) | peak-normalised; LUFS informational (−24…−15) | ≤ −1.4 dBTP (build target −1.5) | crest 15–20 dB makes LUFS meaningless; `[spike]` all SFX ≤ −1.4 dBTP |
| Loops (engines, rotors, hums) | −20…−24 (per family, `LUFS` table in the catalog) | ≤ −4 dBTP (build peak −6) | `[spike]` targets: tracked/wheeled/boat −22, heli −20, beam hum −20, footsteps −24 |
| Alarms / countdown | −16…−14 | ≤ −4 dBTP | `[spike]` siren −16, countdown_final −14 |
| UI | −28…−18 | ≤ −4 dBTP | hover −28, click −22, confirm/error −18 |
| Ambience beds | −26…−30 | ≤ −9 dBTP | wind −26, coast −26, city −30 `[spike]` |
| Announcer lines | **−18.0 ± 1.5** | ≤ −1.5 dBTP | `[spike]` measured −18.0…−19.8 |
| Unit responses (bleep + squelch / bark) | −20 ± 2 | ≤ −2.0 dBTP | quieter than the announcer by design |
| Music mix (sum of stems) | combat **−14.4**, calm **−16.1** (±1) | −2.0 dBTP | `[spike]`; stems carry the per-style balance (`STEM_LUFS`) + ONE shared master gain, so the stem sum equals the reference mix |

**Reference in-game mixes** (measured on `Master` by `AudioEffectCapture`, K-weighted; scripted scenarios in §10.3): **A** base building, calm music + ambience + UI/cash ticks: −26 ± 2 LUFS-S. **B** heavy battle (scripted 400-entity event flood, 60 s): −17 ± 2 LUFS-S, max true peak ≤ −1.0 dBTP, limiter gain reduction < 3 dB for 95 % of blocks, max momentary ≤ −10 LUFS-M. **C** superweapon impact: momentary ≤ −8 LUFS-M with Music ducked ≥ 2 dB. **D** announcer over B: `Music` ducked 6–10 dB, `Sfx` not ducked.

### 5.2 Event → voice: priority, variation, limits, throttling, stealing

**Priority scale (0–100)** — one scale for pool stealing, gating and announcer pre-emption: ambience 0–9 · loops 10–24 · small arms 25–39 (rifle 28, MG 30, autocannon 38) · medium 40–59 (cannons 52–58, missiles 46, flak 40) · heavy 60–69 (siege 62–66, artillery 66, rail 62, EMP 62) · big booms 70–89 (explosion_large 80, huge 85, collapse s3/s4 88–90) · alarms/announcer/UI 90–100 (siren 97, UI 95). A newcomer of a higher band can always displace a lower band's voice; within a band, the nearer/louder one wins (score below).

**`play_def` pipeline** (any failure returns `INVALID`, increments one counter in `SndStats`):

| # | Gate | Rule | Counter |
|---|---|---|---|
| 1 | replay gate | `def.priority < gate_priority` → drop | `cull_gate` |
| 2 | rate | `def.min_interval_ms > 0 and now − def.last_play_ms < min_interval_ms` → drop | `cull_interval` |
| 3 | distance | WORLD_3D only: `d_eff = ‖audio_pos − listener‖` (3D distance, includes height); `max_distance_m > 0 and d_eff > max_distance_m` → drop | `cull_distance` |
| 4 | audibility | `est = def.volume_db + gain_db + attenuation_db(def, d_eff)`; `est < def.cull_below_db` (default −42; data range [−80, −10]) → drop | `cull_level` |
| 5 | event instances | `def.active_count ≥ def.max_instances`: victim = same-event voice chosen by `def.steal` (OLDEST → smallest `start_ms`; QUIETEST → lowest score; NONE → drop) | `cull_limit` / `stolen` |
| 6 | group instances | `group_count[def.group] ≥ group_limit`: same, within the group | `cull_limit` / `stolen` |
| 7 | free slot | a free slot in the region exists **and** (`free_count > reserve_high_slots` **or** `def.priority ≥ reserve_high_priority`) → use it. `fading` voices count as free | — |
| 8 | pool full | victim = lowest **score** voice (fading first); steal iff `new_score > victim_score + steal_margin` | `stolen` / `dropped` |

`attenuation_db(def, d) = model_db + 20·log10(max(1 − d/max_distance_m, 0))` (window omitted when `max_distance_m = 0`); `model_db` = INVERSE: `−20·log10(d/U)`, INVERSE_SQUARE: `−40·log10(d/U)`, LOGARITHMIC: `−20·ln(d/U)`, DISABLED: 0; result clamped to `MAX_GAIN_DB = +3` (Godot `max_db`), `d` clamped ≥ 1e-4·U. `[spike]` verified against the engine within ~0.8 dB; **`max_distance` is a linear fade window, not a cutoff** (−6 dB at half, −20 dB at 90 %), so data uses `max_distance_m ≈ 2–3×` the audible range.

`score(voice) = priority + 0.5·est_db − age_s·age_penalty_per_s` (`age_penalty_per_s = 1.0`, `steal_margin = 1.0`). Ties: lower `slot_index` loses (deterministic).

*Worked example* (pool of 48 3D voices full of low-priority voices; a typical victim is a rifle shot, priority 28, est −20 dB, age 0.4 s → score 17.6): heavy cannon (62, est −8 → 58) steals; a near rifle (28, est −12 → 22 > 18.6) steals a far one; a far rifle (28, est −30 → 13) is `dropped`. With 6 free slots left a rifle is treated as "full" (step 7) while `explosion_huge` (85) still takes a free slot — this is the **reserve** that keeps big booms from being starved by small arms.

**Variation and randomisation** (per start, own `RandomNumberGenerator`, seeded from `SndMatchConfig.match_seed ^ 0x53E1D` — never `SimRng`):
- variant: weighted pick over `flavour_streams[flavour]` else `streams`, excluding the previous pick of that flavour when > 1 variant (spike);
- `vol_db = def.volume_db + gain_db + U(−volume_jitter_db, +volume_jitter_db)`; `pitch_scale = def.pitch · pitch_mul · 2^(U(−pj, +pj)/12)`;
- **3D node configuration**: `unit_size = unit_size_m`, `max_distance = max_distance_m`, `attenuation_model`, `attenuation_filter_cutoff_hz = lowpass_hz` (9–12 kHz for weapons; `[spike]` the 5 kHz default costs ≈30 % extra CPU and audibly dulls close shots; 20 500 disables it), `panning_strength`, `doppler_tracking`, `bus`. Project setting `audio/general/3d_panning_strength = 0.5` (the value under which the spike measured 6 dB L/R at node strength 1.0).
- **Loops** always start at position 0 with `volume_db = −60` ramped to target over `fade_in_ms` (default 120): `[probe]` a 3D player started at a random phase clicked 6.1× the natural step. De-phasing many instances of one loop is done by per-instance `pitch` (±0.4 % from a hash of the entity id) and by picking among variants, never by random seeking.
- **Stop**: `stop()` on `AudioStreamPlayer` and `AudioStreamPlayer3D` is click-free in the engine (`[probe]` 1.0× at 8 random phases, both types), so stolen voices are reused immediately; loops still fade 200 ms first so they do not audibly "cut".

**Throttling layers** (cheapest first): event `min_interval_ms` → per-source (entity id) 40 ms (`_last_fire_ms[e & 1023]`) → per-event/group limits → per-frame start cap (`max_starts_per_frame = 24`, ranked by `priority + 0.5·est_db`, the rest dropped with `cull_frame`) → meter/announcer/response gaps.

### 5.3 Listener at the RTS camera, audio space and the positional budget

`[spike]` binding rules: a **current `Camera3D`** must exist in the viewport that contains the players (`AudioListener3D` alone was silent); with a camera present the `AudioListener3D` overrides its transform (listener 110 m away gave exactly −20.8 dB). Therefore `SndListener` sits on the **ground focus point** (screen centre projected on terrain, +2 m), basis = camera yaw about +Y, so attenuation and panning are relative to the *battlefield the player is looking at*, not to the camera's altitude, and "screen-left" is the left ear.

- **Zoom scale** `s = clamp(height / ref_height_m, zoom_scale_min, zoom_scale_max)` = `clamp(height / 55, 0.6, 2.0)` (`mix.camera`), with `height` = the view camera's height above the focus (render.md `ViewCamera`: 34 m closest, 84 m farthest, 110 m with the "wide view" setting) → `s` = 0.62 … 1.53 (2.0 wide view); `s = 1` at 55 m, roughly the default zoom.
- **Audio space**: sources are mapped `p' = focus + (p − focus)/s` on x,z (height preserved). Zooming out pulls the whole battle closer, zooming in pushes it away; pan direction is preserved; no per-node `unit_size` edits are needed and moving loops pick the change up automatically.
- *Worked example*: tank cannon (U 45 m, max 320 m) 90 m from the focus. Default zoom (s = 1): `−20·log10(90/45) = −6.0 dB`, window `1 − 90/320 = 0.72 → −2.9 dB` → **−8.9 dB**. Zoomed out to s = 2.0: d_eff = 45 m → 0 dB, window 0.86 → −1.3 dB → **−1.3 dB** (+7.6 dB: more of the battle is "in the room"). The same shot at s = 0.62 (closest zoom, 34 m) is d_eff = 145.2 m → −10.17 − 5.25 = −15.4 dB; at the farthest standard zoom (84 m, s = 1.53) d_eff = 58.9 m → −2.3 − 1.8 = −4.1 dB.
- **Heights**: ground sources at `source_height_ground_m = 1.5`, aircraft at 22 m (jet directly overhead: d = 22 m). Sim is 2D; height is presentation-only.
- **Hearing radius** for pre-culling in the bridge: `max_scan_m · s` (750 m·s), then per-event `max_distance_m`.
- **Budget vs listener** (typical heavy fight at default zoom, 3D pool 48): small arms ≤ 10 (group cap) · heavy weapons ≤ 8 · explosions/impacts ≤ 6+8 · entity loops ≤ 16 · structure/one-shots ≈ 6 → **≈ 40–48**, i.e. the pool is designed to be *full but not starved* in the worst case; steals prefer far/quiet/low-priority voices. Quality presets scale the 3D pool 24/40/48 and `loops.budget` 8/12/16.

### 5.4 Sim event → sound resolution

All events are `SimEvent` records `[type, tick, a, b, c, d, e, f, g, h]` (sim_core §6.2); field letters below are that layout. **Coordinates**: sub-cell `(x, y)` → `SndUnits.to_world(x, y, h)` = `Vector3(x·3/1024, h, y·3/1024)` (`h` = `source_height_ground_m`, or `source_height_air_m` for AIR-layer sources); cell for fog/terrain = `x >> 10, y >> 10` (non-negative coordinates). Events without a position use the position of the entity they name (`reader.entity(id)`; when the entity is already gone the event is dropped unless it carries its own x/y). Combat/economy/abilities proposed differently-numbered events (`EV_FIRE`, `EV_IMPACT`, `EV_HIT`, `EVT_*`, …); §6.4 lists the master-catalogue equivalent of each and audio consumes only the master catalogue (§6.2).

**5.4.1 Weapon fire** — `WEAPON_FIRED` 0x11: `a` shooter · `b` weapon_def_idx · `c` target (0 = ground) · `d,e` target x/y · `f` muzzle_idx · `g,h` muzzle x/y. The master record has no result/burst/owner fields, so: the **owner** comes from `entity(a).owner` (a shooter already removed → treated as ENEMY for the fog rule), the **flavour** from the weapon id (`bank.weapon_flavour[b]`, e.g. `weapon.han.…` → `han`; shared weapons → the owner's faction), and hitscan weapons get their impact sound from `DAMAGE` (5.4.3). Beam weapons (`bank.weapon_beam[b]`) are handled by `BEAM`. Resolution chain of the fire event (first hit wins, computed once per weapon def in `SndSoundBank.bake`; weapon instances carry no presentation fields, data_balance 7.15, so the only input is the weapon id and its archetype):
1. `sim_map.weapon_override[<weapon id>]` — an optional per-weapon override kept in **audio's own** `events.json` (empty in v1), naming an event id;
2. `sim_map.weapon_fire` = `snd.weapon.{archetype}` where `{archetype}` is `SndUnits.ARCH_TABLE[weapon_arch].name`, the weapon's TAXONOMY §10 archetype (`WeaponArch` ints are frozen, TAXONOMY §11); for `tank_cannon` the suffix comes from the owning unit's profile `weapon_variant` (`light` for `mbt_t1`, `medium` for `mbt_t2`/`veh_command`, `heavy` for `siege_ap` and the anti-tank turret; default `medium`). The bake walks the entity defs in index order; the first owner of a weapon defines its variant, and a weapon shared by different profiles takes the heaviest;
3. `snd.weapon.small_arms` (unknown archetype index, e.g. an archetype added after this spec; `coverage.weapons_fallback` counts them and V-AUD-15 is the build-time guard).

| Archetype | Event id | Pr | U / max (m) | Limit (group / inst / min ms) | Var | Flav. | Recipe family |
|---|---|--:|---|---|--:|:-:|---|
| small_arms | `snd.weapon.small_arms` | 28 | 22 / 170 | small_arms / 6 / 35 | 3 | yes | `rifle_shot` (spike: crack + supersonic snap + body + thump, slap echo) |
| machine_gun | `snd.weapon.machine_gun` | 30 | 22 / 170 | small_arms / 5 / 45 | 3 | yes | `mg_round` |
| autocannon | `snd.weapon.autocannon` | 38 | 28 / 200 | small_arms / 4 / 60 | 3 | yes | `autocannon_round` (single round of the spike burst) |
| tank_cannon | `snd.weapon.tank_cannon_light` / `_medium` / `_heavy` | 52 / 58 / 64 | 34/260 · 40/300 · 50/340 | heavy / 4·4·3 / 90·90·120 | 2 | medium, heavy | `tank_cannon` (k = 1.15 / 1.0 / 0.8) |
| siege_gun | `snd.weapon.siege_gun` | 62 | 55 / 380 | heavy / 3 / 150 | 2 | yes | `siege_gun` |
| demolition_cannon | `snd.weapon.demolition_cannon` | 66 | 55 / 380 | heavy / 2 / 250 | 2 | | `demolition_boom` |
| at_missile | `snd.weapon.at_missile` | 46 | 34 / 260 | heavy / 4 / 100 | 2 | yes | `missile_launch` (spike) |
| aa_missile | `snd.weapon.aa_missile` | 46 | 34 / 260 | heavy / 4 / 80 | 2 | | `missile_launch_light` |
| flak | `snd.weapon.flak` | 40 | 30 / 220 | small_arms / 4 / 60 | 3 | | `flak_pop` |
| artillery_shell | `snd.weapon.artillery_shell` | 66 | 70 / 450 | heavy / 3 / 200 | 2 | yes | `howitzer_thump` (spike) |
| rocket_barrage | `snd.weapon.rocket_barrage` | 54 | 45 / 320 | heavy / 4 / 60 | 2 | | `rocket_whoosh` (spike, mono) |
| mortar | `snd.weapon.mortar` | 50 | 34 / 260 | heavy / 3 / 150 | 2 | | `mortar_thunk` |
| missile_artillery | `snd.weapon.missile_artillery` | 62 | 60 / 420 | heavy / 3 / 200 | 2 | | `missile_launch_heavy` |
| beam_thermal | `snd.weapon.beam_thermal` (+`.loop`, `.end`) | 52 | 40 / 300 | loops / 6 | 1 | yes | `beam_discharge` + `beam_hum_loop` (spike) |
| rail_gun | `snd.weapon.rail_gun` | 62 | 60 / 420 | heavy / 3 / 250 | 2 | yes | `rail_crack` (spike) |
| torpedo | `snd.weapon.torpedo` | 48 | 34 / 260 | heavy / 3 / 300 | 2 | | `torpedo_launch` |
| depth_charge | `snd.weapon.depth_charge` | 52 | 34 / 260 | heavy / 3 / 300 | 2 | | `depth_charge_drop` |
| bomb | `snd.weapon.bomb` | 50 | 34 / 260 | heavy / 4 / 100 | 2 | | `bomb_release` |
| air_missile | `snd.weapon.air_missile` | 46 | 34 / 260 | heavy / 4 / 90 | 2 | | `missile_launch_light` |
| emp_pulse | `snd.weapon.emp_pulse` | 62 | 45 / 350 | heavy / 3 / 250 | 1 | | `emp_zap` (spike) |
| canister | `snd.weapon.canister` | 46 | 30 / 220 | heavy / 4 / 100 | 2 | | `canister_blast` |
| grenade_launcher | `snd.weapon.grenade_launcher` | 40 | 24 / 180 | small_arms / 4 / 100 | 2 | | `grenade_thump` |
| breach_charge | `snd.weapon.breach_charge` | 56 | 26 / 190 | heavy / 3 / 300 | 1 | | `breach_bang` |
| naval_gun | `snd.weapon.naval_gun` | 58 | 55 / 380 | heavy / 3 / 200 | 2 | | `naval_gun` |
| naval_bombard | `snd.weapon.naval_bombard` | 68 | 70 / 460 | heavy / 3 / 300 | 2 | | `naval_bombard` |
| cruise_missile | `snd.weapon.cruise_missile` | 62 | 60 / 420 | heavy / 3 / 300 | 2 | | `missile_launch_heavy` |
| drone_missile | `snd.weapon.drone_missile` | 42 | 30 / 220 | small_arms / 4 / 80 | 2 | | `missile_launch_light` |

Groups (`max_voices`): `small_arms` 10 · `heavy` 8 · `explosions` 6 · `impacts` 8 · `loops` 16 · `struct` 6 · `power` 4 · `strategic` 4 · `ui` 6. Events with priority ≥ 60 use `bus: SfxHeavy` only for the boom classes (explosion large/huge, collapse, superweapon impacts, artillery/naval bombard/rail fire) so the second ducking key fires on real "thumps" only. Fog policy defaults: small arms/medium HIDDEN; artillery/naval_bombard/rail/cruise/explosion_large+ MUFFLED; superweapon/alarm AUDIBLE. `propagation: true` for artillery_shell, naval_bombard, explosion large/huge, collapse s3/s4 and superweapon impacts.

**Faction weapon flavour** (`flavours` object; 10 families × 8 factions × 2 variants = 160 mono files): the axes are pitch, brightness, tail wetness, saturation and a signature layer (table 5.15). It makes *who is shooting* audible; the objective distinctiveness gate is in §10.2.

**5.4.2 Projectile flight** — `PROJECTILE_LAUNCHED` 0x12: `a` proj_id · `b` weapon_def_idx · `c` shooter · `d,e` x0/y0 · `f,g` x1/y1 · `h` flight_ticks. The flight class comes from the archetype (`bank.weapon_proj[b]` = `SndUnits.ARCH_TABLE[arch].flight`: 0 none/hitscan, 1 bullet-like, 2 missile, 3 arc, 4 bomb, 5 torpedo; no projectile registry is needed because TAXONOMY §10 fixes the projectile kind and damage type per archetype):
```
WeaponArch  name(dtype → flight)
 0 small_arms(bullet→1)      1 machine_gun(bullet→1)      2 autocannon(bullet→1)        3 tank_cannon(ap→3)
 4 siege_gun(he→3)           5 demolition_cannon(he→3)    6 at_missile(ap→2)            7 aa_missile(ap→2)
 8 flak(he→3)                9 artillery_shell(he→3)     10 rocket_barrage(he→3)       11 mortar(he→3)
12 missile_artillery(ap→2)  13 beam_thermal(thermal→0)   14 rail_gun(rail→0)           15 torpedo(ap→5)
16 depth_charge(he→0)       17 bomb(he→4)                18 air_missile(ap→2)          19 emp_pulse(emp→0)
20 canister(bullet→1)       21 grenade_launcher(he→1)    22 breach_charge(he→0)        23 naval_gun(ap→3)
24 naval_bombard(he→3)      25 cruise_missile(he→2)      26 drone_missile(ap→2)
```
(`depth_charge` is class 0 because its drop is covered by the fire sound; `SndUnits.ARCH_TABLE` mirrors this list and `test_snd_coverage::arch_table` compares names and damage types with `DefWeaponArch` when the data layer provides it.)
- MISSILE (2) and TORPEDO (5): path voice `snd.proj.missile` / `snd.proj.torpedo` from (x0,y0) to (x1,y1) linearly over `h·50 ms` (`SndLoopManager.add_path_voice`, keyed by proj_id); `PROJECTILE_IMPACT` (same `a`) stops it (fade 60 ms).
- ARC (3) with `h ≥ 24` (≥ 1.2 s): schedule `snd.proj.shell_whistle` at (x1,y1) at `due = now + (h − 20)·50 ms` (the whistle lands 1.0 s before impact); only if the *impact* cell passes the fog rule of 5.5 (own/allied owner or visible cell).
- BOMB (4): `snd.proj.bomb_whistle` at (x1,y1) at `due = now + max(h·50 − 800, 0) ms`.
- Bullet-like (1) and none/hitscan (0): no flight sound. (`rocket_barrage` is class 3: its fire sound already contains the whoosh, and the whistle only plays when the flight lasts ≥ 24 ticks, i.e. at long range.)

**5.4.3 Impacts, explosions and hits.** Size from a radius in sub-cells: `0 → TINY`, `≤ 819 → SMALL`, `≤ 1536 → MEDIUM`, `≤ 2560 → LARGE`, else `HUGE` (0.8 / 1.5 / 2.5 cells). Warhead **kind** is resolved from the damage-type *name* (`DefDamageTable.damage_ids`: bullet → BULLET; ap, he → EXPLOSIVE; thermal, beam → ENERGY; rail; kinetic; emp), so renumbering never breaks audio.
- `PROJECTILE_IMPACT` 0x13: `a` proj_id · `b` weapon_def_idx · `c,d` x/y · `e` target (0) · `f` result (1 entity · 2 ground · 3 water · 4 intercepted · 5 expired) · `g` splash_radius · `h` owner. `f = 4`: stop the flight voice only (`INTERCEPT` plays the sound). Otherwise kind = `bank.weapon_kind[b]`, size from `g`:

| Warhead kind | Sound |
|---|---|
| EXPLOSIVE | `snd.explosion.<size>` (TINY → small); water result (`f = 3` or the target cell's `mix.terrain.material` is WATER) → `snd.explosion.water.<small\|medium\|large>` (HUGE stays `snd.explosion.huge`) |
| BULLET | `f ∈ {2,3,5}` only: `snd.impact.bullet.<material of terrain>` (entity hits are covered by `DAMAGE`) |
| ENERGY | `snd.impact.energy.<small if size ≤ MEDIUM else large>` |
| RAIL / KINETIC / EMP | `snd.impact.rail` / `snd.impact.kinetic` / `snd.impact.emp` |

- `EXPLOSION` 0x14: `a,b` x/y · `c` radius_units · `d` fx_kind · `e` owner · `f` source_id · `g` damage_type. Same table, kind from `bank.dtype_kind[g]`, size from `c`; the source for splash and chain explosions, strikes, crash impacts and superweapon blasts. **Dedupe**: the master catalogue lists both a `PROJECTILE_IMPACT` and an `EXPLOSION` for explosive impacts, so the bridge keeps a 64-entry ring of `(tick, x >> 9, y >> 9)` keys of explosions it has already voiced in this batch and skips the second event of the same key (whichever arrives first plays; both carry the radius).
- `DAMAGE` 0x10: `a` target · `b` attacker · `c` hp_lost · `d` damage_type · `e` weapon_def_idx · `f` flags (1 kill blow · 2 suppressive · 4 splash · 8 crush) · `g,h` x/y. Voiced only when `f & 4 == 0` (splash is covered by the explosion) and the kind is **BULLET** (`snd.impact.bullet.<material of the target's armor class>`, throttle 60 ms per target) or **ENERGY** (`snd.impact.energy.small`, 150 ms per target); a target already removed falls back to METAL. Material tables — `ArmorClass → material`: INFANTRY → FLESH; LIGHT_VEHICLE, MEDIUM_ARMOR, HEAVY_ARMOR, AIR_LIGHT, AIR_HEAVY, SHIP_LIGHT, SHIP_HEAVY → METAL; BUILDING_LIGHT, BUILDING_HEAVY, FORTRESS → CONCRETE. `MapTerrain id → material` (`mix.terrain.material`, 15 entries): deep_water, shallow, ford → WATER; beach, grass, dirt, sand → DIRT; forest → WOOD; rock, road, pavement, rubble, urban_block, cliff, mountain → CONCRETE.
- These sounds use the `impacts` group (8 voices, priority 24–36, `min_interval_ms` 60). Hitscan misses have no event in the master catalogue and are therefore silent in v1 (a bullet whiz-by is a listed non-goal).

**5.4.4 Deaths and collapses** — `DIED` 0x03: `a` id · `b` def_idx · `c` owner · `d,e` x/y · `f` killer_id · `g` killer_owner · `h` reason (`DIE_COMBAT 0, SCUTTLE 1, EXPIRED 2, DEFEAT 3, PARENT_LOST 4, SCRIPT 5`). Everything else comes from the baked def tables (`def_kind`, `def_armor`, `def_layer`, `def_area`, `def_death_chain`):

| Condition | Sound |
|---|---|
| def kind ZONE / DEPOSIT / WRECK | none |
| `h ∈ {EXPIRED, PARENT_LOST}` (timed-out summons, decoys, drones) | `snd.death.decoy`; AIR_LIGHT drones `snd.death.drone` |
| UNIT, armor INFANTRY | `snd.death.infantry` (6 variants, prio 22, group `impacts`) |
| UNIT, layer AIR | `snd.air.crash_fall` (2.5 s falling whine) at the position; the ground impact arrives as its own `EXPLOSION`. AIR_LIGHT drones/missiles: `snd.death.drone` instead |
| UNIT, layer SURFACE (ship armors) | `snd.death.ship`; layer UNDERWATER → `snd.death.sub` |
| UNIT, other vehicles | if `def_death_chain[b]` the explosion arrives as an `EXPLOSION` and this event stays silent (no double boom); otherwise `snd.explosion.<small\|medium\|large>` by armor (LIGHT → small, MEDIUM → medium, HEAVY → large) |
| STRUCTURE | `snd.collapse.<s1\|s2\|s3\|s4>` by footprint area (`≤ 1`, `≤ 4`, `≤ 9`, else) — priority 88–90 for s3/s4 on `SfxHeavy`; always plays (rubble); the chain explosion is a separate `EXPLOSION` |

Announcer/meter side effects: owner `c` == viewer → unit: line `unit_lost`(50); structure: `structure_lost`(80); Collector (`TAG_COLLECTOR`): `collector_lost`(82); superweapon launcher (`TAG_LAUNCHER`): `superweapon_destroyed`(90). Meter: death weights (5.7).

**5.4.5 Beams and other state-driven cues.**
- `BEAM` 0x15: `a` shooter · `b` weapon_def_idx · `c` target · `d` 1 start / 0 stop · `e,f` target x/y. Start: play the weapon's start event at the shooter and `start_beam(a, b, def, flavour)` binds `link_loop` to the entity (fade-in 150 ms); stop: fade-out 200 ms + `link_end` one-shot. Beams are keyed by `(shooter, weapon)` because the master record has no mount index. The Helios sweep has no event of its own: `SW_LAUNCHED` starts the `snd.sw.helios.loop` path voice along the committed line (5.12).
- `INTERCEPT` 0x16: `a` interceptor_id · `b` proj_id · `c,d` x/y · `e` charges/cooldown: `snd.intercept.zone` if `entity(a).kind == ZONE` (Trident dome) else `snd.intercept.aps`, at (c,d).
- `STATE` 0x05: `a` id · `b` state · `c` value · `d` duration · `e,f` x/y (the entity's owner via `entity(a)`). Value convention `ASSUMPTION(sim_core)`: `1` = state entered, `0` = state left (for POWERED: `1` powered, `0` unpowered):

| state (`ST_*`) | Sound |
|---|---|
| 7 EMP | `snd.emp.hit` at (e,f) if audible |
| 8 SHUTDOWN (`c = 1`) | own structure → `snd.struct.defense_offline` + line `systems_disabled`(75) |
| 13 POWERED (`c = 0`, power lost) | own structure with `TAG_DEFENSE` → `snd.struct.defense_offline` (2 s/entity) and, once per shortage (30 s), line `defenses_offline`(72) |
| 5 CLOAKED / 6 DECLOAKED | `snd.power.cloak.activate` / `.end` at −8 dB, visible units only |
| 10 LANDED / 11 TAKEOFF | `snd.air.landing` / `snd.air.takeoff` (own or visible) |
| 12 SELLING | `snd.struct.sell` at (e,f) |
| 15 REPAIRING | `c = 1` → `snd.struct.repair` loop bound to the entity; `c = 0` → stop |
| 1 DEPLOYING / 2 DEPLOYED | `TAG_HQ` → `snd.struct.hq_deploy`; otherwise none (v1) |
| others (suppressed, packed, mode-switch…) | ignored |

- `LOADED` / `UNLOADED` 0x06/0x07: `a` passenger · `b` carrier · `c,d` x/y → `snd.struct.unit_out.infantry` at the carrier (UNLOADED full level, LOADED −4 dB), visible only.

**5.4.6 Construction, production, economy, powers.**
- `SPAWNED` 0x01: `a` id · `b` def_idx · `c` owner · `d,e` x/y · `f` facing · `g` reason (`SPAWN_INITIAL 0, PRODUCED 1, PLACED 2, DEPLOYED 3, SUMMONED 4, WRECK 5, SCRIPT 6`) · `h` parent. A STRUCTURE with reason PLACED → `snd.struct.online.<kind>` at (d,e), a 2.0–3.0 s one-shot whose build-up section spans the view's build-up animation (`SndUnits.BUILDUP_SECONDS = 1.5`, the sim's 30-tick `BUILDUP` state) and ends on the "online" accent followed by a tail of at most 1.5 s; reason DEPLOYED with `TAG_HQ` → `snd.struct.hq_deploy`. Units are voiced by `PRODUCTION_COMPLETE`, never by `SPAWNED`. Kind of structure from `bank.def_profile[b].id` (`snd.profile.struct.<kind>`; launchers `online.superweapon`, advanced defences `online.adv_defense`).
- `PRODUCTION_COMPLETE` 0x26: `a` pid · `b` def_idx · `c` producer_id · `d` spawned_id: own → line `unit_ready`(45); `snd.struct.unit_out.<infantry|vehicle|aircraft|ship>` at the producer (class from `def_armor`/`def_layer` of `b`), 250 ms per producer, for any visible producer.
- `HARVEST_DELIVERED` 0x21: `a` collector · `b` refinery · `c` amount · `d` pid: `d` == viewer → `snd.eco.cash` at the refinery (pitch `1 + min(c, 1000)/1000·0.12`; `snd.eco.cash_big` above 500), 120 ms throttle. `CASH` 0x20 (`a` pid · `b` delta · `c` total · `d` reason · `e` source): only reasons SELL/REFUND with `b > 0` for the viewer → `snd.eco.cash_big` (flat) and, for SELL, line `structure_sold`(30); harvest and salvage payouts are voiced by their own events, so `CASH` with those reasons is ignored (no double tick).
- `SALVAGE` 0x19: `a` salvager · `b` wreck · `c` credits · `d` phase (0 start, 1 done, 2 aborted) · `e,f` x/y: own salvager — 0 → `snd.struct.salvage` loop bound at (e,f); 1 → stop + `snd.eco.cash`; 2 → stop.
- `POWER_LOW` 0x22 / `POWER_RESTORED` 0x23 (`a` pid): own → `snd.struct.power_down` / `snd.struct.power_up` + lines `low_power`(75) / `power_restored`(65).
- `OWNER_CHANGED` 0x04 (`a` id · `b` old · `c` new · `d,e` x/y · `f` reason 0 capture): `c` == viewer → line `building_captured`(60) + `snd.struct.captured`; `b` == viewer → line `structure_captured`(88) + `snd.alarm.base_attack`.
- `POWER_USED` 0x30: `a` pid · `b` power_idx · `c,d` x/y · `e` angle · `f` duration_ticks: cue set `bank.power_cue[b]` — `activate` at (c,d) (own/ally always, enemy if the cell is visible), `loop` for exactly `f` ticks when the class has one (scheduled stop), `end` at expiry; own also `snd.ui.confirm`. **Power classes** (48 powers → 7 classes): recon (8: UAV Sweep, Survey Drone, Maritime Patrol, Long Watch, Wideband Scan, Survey Network, Recon Balloon, Counterbattery Solution) · repair (6: Field Repair Drop, Floating Workshop, Mobile Workshop, Expeditionary Workshop, Repair Swarm, Field Refurbishment) · buff (18) · shield (6: Emergency Earthworks, Redundant Orders, Steel Advance, Joint Landing, Emergency Fortification, Protected Advance) · cloak (4: Silent Watch, False Convoy, False Front, Feint Landing) · smoke (3: Dust Screen, Broken Contact, Concealed Crossing) · barrage (3: Counterbattery Mission, Tremor Barrage, Counterlaunch Plot). Warned powers (`power_warning_ticks[b] > 0`) raise the alert of 5.12.
- `POWER_READY` 0x31 (`a` pid · `b` slot · `c` power_idx): own → the faction's `power_<name>_ready` line (`bank.power_ready_line[c]`) or the generic `power_ready`(68).
- Superweapons: `SW_*` events, table 5.12.

**5.4.7 Profiles (units and structures) — derived, not authored.** `bank.def_profile[def_idx]` (single entity-def space, `data.def_ids[def_idx]`) = the def's `pres_snd_profile` if non-empty and present in `events.json.profiles`, else `snd.profile.<archetype>` (archetype from `DefUnit.archetype` = the 32 role archetypes of the def's `unit_assignments` row, §13-7; service units `svc_engineer|collector|mcv|landing_transport`; summons/drones/decoys `summon_drone|summon_capsule|decoy`), else `snd.profile.generic.<move class name>`. Structures: id `structure.shared.<x>` → `snd.profile.struct.<x>` (`anti_tank_turret` → `turret`); bible tag `superweapon` → `struct.sw_<faction>`; `advanced_defense` → `struct.adv_<faction>`; `structure.nec.relay` → `struct.relay`. Coverage is therefore 100 % by construction; `validate_audio.py` prints the explicit-vs-derived-vs-generic counts and fails when a *generic* profile is used for a unit whose archetype has a specific profile (V-AUD-14).

Profile → default loops (all `LoopWhen.MOVING` unless stated; `pitch_speed` = engine RPM follows speed): FOOT `snd.loop.step.foot` · WHEELED `engine.wheeled` · TRACKED `engine.tracked` (`tracked_heavy` for heavy_armor) · AMPHIBIOUS `engine.amphibious` · NAVAL `engine.boat_small` (ship_small/medium) / `boat_large` (ship_large) · SUBMERGED `engine.sub` · AIR_FIXED `air.jet` (AIRBORNE, doppler on) · AIR_HOVER `air.rotor` (gunship) / `air.drone` (drones) · STATIC none; structures: generator/radar/laboratory/airfield/refinery hum loops (`STRUCTURE_ACTIVE`), superweapon launcher `snd.sw.<name>.charge` (`CHARGING`).

### 5.5 Audibility: fog, ownership, hearing radius

For every positional event with an owner `o` and cell `(cx, cy)`:

```
if reader.omniscient:                       audible, unmodified
elif relation_of(o) in {SELF, ALLY}:       audible                      # own and allied sounds are never fogged
elif reader.cell_visible(cx, cy):           audible                      # includes camouflaged units that fire (firing reveals them, bible)
else: match def.fog:
        HIDDEN:  drop (cull_fog)
        MUFFLED: only if d_ground ≤ mix.hearing.loud_fog_radius_m (300 m): play with gain += fog_gain_db (−9), lowpass = min(def.lowpass, fog_lowpass_hz 1200)
        AUDIBLE: play unmodified
```
Entity loops additionally require `reader.entity_visible(e)` (camouflage-aware, `F_CLOAKED`) — an unidentified decoy (`F_DECOY`) plays its mimicked class's loop ("decoys look real until identified", bible) as long as it is visible, and disappears from the mix when the vision domain stops reporting it visible. **Owner sources**: `WEAPON_FIRED` → `entity(a).owner`; `PROJECTILE_IMPACT` → `h`; `EXPLOSION` → `e`; `DIED`/`SPAWNED` → `c`; `STATE`/`BEAM`/`INTERCEPT` → the named entity's owner; `POWER_USED`/`SW_*` → `a`. An owner that cannot be resolved (entity already removed, id 0) is treated as ENEMY: fog decides (conservative), flavour falls back to the weapon's own faction.

### 5.6 Entity loops (engines, rotors, hums, beams)

Every `mix.loops.scan_period_s = 0.25` s (spread so only 1/4 of the scan runs per frame at 60 fps): (1) `reader.query_radius(focus_units, R, ids)` with `R = loops.radius_m·s / M_PER_UNIT` (90 m·s); (2) for at most 160 ids: `e = entity(id)`; skip entities with `F_DEAD | F_REMOVING | F_INSIDE`; take `bank.def_profile[e.def_idx].loops`; test `when` on the **flags mirrored by the sim** (`SimFlags`, sim_core §4.3): MOVING → `F_MOVING`; AIRBORNE → `F_AIRBORNE`; STRUCTURE_ACTIVE → `F_POWERED` set, `world.tick ≥ e.t_shutdown`, not `F_SELLING`; CHARGING → own launcher while `players[viewer].sw_state == CHARGING`; (3) visibility per 5.5; (4) `score = def.priority + 0.5·est_db(def, pos)`, `+ hysteresis_db/2 (3 dB → 1.5)` for already-active loops; sort by `(score desc, entity id asc)`; (5) keep the top `budget` (16); stop the rest with `fade_out_ms` (200), start new ones with `fade_in_ms` (120). **Motion**: the master `SimEntity` has no previous position, so every active loop chases the latest sim position `T = to_world(e.x, e.y, h)` with exponential smoothing `pos += (T − pos)·(1 − exp(−dt/0.06))` (60 ms time constant, equivalent to the view's one-tick interpolation lag and immune to catch-up batches); the smoothed speed `|Δpos|/dt` feeds `pitch = base·lerp(0.85, 1.15, min(1, speed/vmax))` for `pitch_speed` loops (`vmax = bank.def_speed[def]·20·3/1024` m/s), smoothed with tau 0.3 s. Per-instance de-phasing pitch: `1 + ((id·37) mod 21 − 10)·0.004`.

### 5.7 Combat meter (feeds the music, not the sound effects)

`heat ← heat·exp(−dt/τ) + Σ w` with τ = 6 s; `intensity_raw = 1 − exp(−heat/H_ref)`, `H_ref = 25`; `intensity` rises with tau 0.6 s and falls with tau 4 s. Weights per audible or own-side event (`music.json.meter.weights`, `[tune]`): weapon fire by the fire event's priority band (< 40 small 0.3 · 40–54 medium 0.6 · 55–64 heavy 1.0 · ≥ 65 artillery 1.2) and 0.5 per beam start; explosion 0.3 + 0.25·size (from `EXPLOSION` / explosive `PROJECTILE_IMPACT`); `DIED` unit own 4 / enemy 2, structure 8; `SW_WARNING`/`SW_IMPACT` 30; `BASE_UNDER_ATTACK` of the viewer +20 (also `urgent`). Each is multiplied by `clamp(1 − d/R, 0.15, 1)`, `R = 80 m·s`; own/allied events beyond `R` add `0.25·w` to `far_heat` (drives `snd.amb.battle_far`). State requests (`wants_combat`): **COMBAT** when `intensity ≥ 0.40` for ≥ 1.0 s, or on an urgent alert; **CALM** when `intensity < 0.15` for ≥ 18 s **and** ≥ 25 s since COMBAT began. *Worked example*: 10 rifle squads (0.3 × 10/s × 0.6) + 2 impacts/s (0.55 × 0.6) ≈ 2.5 heat/s → steady heat 15, raw 0.45; the 0.40 threshold is crossed after 11.5 s (`15·(1 − e^(−t/6)) = 12.8`), so COMBAT is requested ≈ 12.5–13.5 s into such a skirmish; a 40-unit fight with artillery (≈ 20 heat/s → steady 120, raw 0.99) crosses in < 1 s; a lone scout duel at 1 shot/s → 0.09 (stays CALM).

### 5.8 Dynamic music

**Content** (`music.json`): per faction `calm` (12 bars, tempo ≈ 0.6 × combat) and `combat` (24 bars) tracks of 4 aligned stems `drums, bass, pads, lead`, a 2-bar `riser` stinger, `victory`/`defeat` stingers; global `menu` theme (4 stems). All stems of a track have identical length = `bars·bar_beats·60/bpm` rounded once to whole samples; every stem is rendered *circularly* so loops are seamless by construction (`[spike]` engine-decoder seam jump/p99 ≤ 0.99, mixer seam 0.52×, engine gain −0.002 dB vs offline sum).

**Engine structure** `[probe P1–P6]`: per faction one `AudioStreamInteractive` (one `AudioStreamPlayer` on `Music`), clips = `AudioStreamSynchronized` stem stacks whose children are **duplicated** `AudioStreamOggVorbis` with `loop = true`, `bpm`, `beat_count`, `bar_beats` (P2: nested `AudioStreamSynchronized` clips honoured `NEXT_BAR` when their children carried identical `bpm` metadata, which every track guarantees):

| clip | content | transitions |
|---:|---|---|
| 0 `calm` | Sync[calm stems] | 0→1: `NEXT_BAR`, `TO START`, `FADE_CROSS` 2 beats, **filler = clip 2**; 0→3: `NEXT_BEAT`, `START`, `FADE_CROSS` 1 beat |
| 1 `combat` | Sync[combat stems] | 1→0 and 3→0: `NEXT_BAR`, `START`, `FADE_CROSS` 4 beats |
| 2 `riser` | 2-bar riser (non-loop) | filler only |
| 3 `combat_hot` | alias of clip 1's Sync resource | entry without riser for urgent alerts |

State mapping: clip 0 → CALM; clips 1, 3 → COMBAT; clip 2 is transient. Fallback: a switch with no defined transition is executed **immediately** with a ~0.3 s cross-fade (P5), so a data omission degrades gracefully instead of failing.

**Safe-switching rules (derived from measured hazards)**
1. **One transition in flight.** After `switch_to_clip_by_name` the director sets `_pending`; it is cleared when `get_current_clip_index()` maps to the target state **and** the fade time has elapsed. While pending, `request_state` is ignored. *Why*: P3 — asking to go back to the current clip while a switch is pending produced a 0.2 s **dropout**; P4 — switching during a running cross-fade left the incoming clip stuck ≈ −10 dB until the next bar.
2. `min_switch_interval_s = 8` after completion; requests are level-triggered (the meter's `wants_combat` is re-evaluated each frame, so a lost request is simply re-issued).
3. **Urgent** (own base-attack alert, superweapon warning affecting the viewer) while CALM and idle → clip 3 (`NEXT_BEAT`, no riser; worst wait one beat ≈ 0.43 s at 140 BPM). Non-urgent entry waits ≤ 1 bar (≈ 2.9 s at 83 BPM) plus the 2-bar riser (≈ 3.5 s) — total ≤ ~6.5 s, which is musical, not laggy, because the calm→combat cue is already a rising build.
4. There is no `bar_position()` (the spike's API): `AudioStreamPlayer.get_playback_position()` returns 0.0 for interactive streams (P6). Beat-synced UI is not a v1 feature.

**Stems vs intensity** (`[tune]`, equal-power `gain = sin(t·π/2)`, `t = clamp(inverse_lerp(lo, hi, intensity))`, converted with `linear_to_db(max(g, 1e-4))`): calm — pads [0, 0.20], bass [0.10, 0.35], drums [0.30, 0.60], lead [0.55, 0.90]; combat — pads [0, 0.15], bass [0.15, 0.40], drums [0.35, 0.65], lead [0.65, 0.95] (the spike's combat windows). `calm_intensity = clamp(0.2 + 1.5·meter.intensity, 0, 0.75)`; in COMBAT `intensity = max(meter.intensity, 0.55)` for the first 10 s after entry (drums present immediately). Per frame `cur += (tgt − cur)·(1 − exp(−dt/0.8))`; `set_sync_stream_volume` only when the dB value moved ≥ 0.05 dB `[spike]` (updates therefore occur at frame rate while moving, i.e. ≥ 60 Hz-ramped).

**Contexts and stingers.** MENU/LOBBY: single-clip interactive (`menu` theme) at intensity 0.6 / 0.35; `enter_match` cross-fades the menu player out (1.5 s ramp) while the faction stream fades in. `end_match(VICTORY|DEFEAT)`: ramp the music player to −∞ over 1.2 s, play `stinger.<faction>.victory|defeat` on its own player (bus Music), then MENU context at intensity 0.35; the announcer line starts 1.5 s into the stinger. `music_mode = CALM_ONLY` never requests COMBAT (stems still follow intensity); `OFF` mutes the Music bus through `SndBusFader`.

### 5.9 Announcer (EVA-style queue)

`say(line, priority, args)`:
1. Resolve pack: `ANN_OFF` → false; `ANN_COMPUTER` → pack `computer`; else the local faction pack (lower-case code). Stream = `vox/<pack>/<line>[_<n>]`; missing in the pack → `computer` pack; missing everywhere → false (and a debug warning once).
2. `prio = priority ≥ 0 ? priority : line.priority`.
3. **Cooldowns**: `now − last_said[line] < line.cooldown_ms` → false (default 6000 ms; per-line values in §7.5); category gap `now − cat_last[cat] < categories[cat].gap_ms` → false unless `prio ≥ 90`.
4. If a line is speaking: `prio ≥ current.priority + 20` (`preempt_margin`) → 40 ms fade-out of the current line, then play the new one immediately; otherwise enqueue.
5. **Queue** (max 4): sorted by priority desc, then arrival; an identical line already queued is refreshed (`priority = max`, `enq_ms = now`), not duplicated; overflow drops the lowest-priority item (if that is the newcomer → return false). An item expires `line.expire_ms` after enqueue (default 8000, alerts 4000, economy 8000) and is dropped silently when it reaches the front.
6. After a line ends, wait `gap_ms = 250` before the next; `Voice`/`Announcer` bus 0 dB; music duck is automatic (sidechain, §4.1).
7. Signals `started/finished`; `text` from `announcer.json` is the caption for UI toasts (accessibility, A-07); every line has one (V-AUD-28).
8. **TTS mode** (accessibility A-14; `SndSettings.announcer_tts`, default off, effective only while `DisplayServer.tts_get_voices_for_language("en")` is non-empty). The pre-rendered voice file is not played; the caption is spoken by the operating system's own voice: `DisplayServer.tts_speak(text, voice_id, volume = settings.voice, pitch = 1.0, rate = 1.1, utterance_id = line index, interrupt = false)` (a pre-empting line calls `tts_stop()` first); the short EVA notify chime (`snd.ui.notify`) still plays on the `Announcer` bus so the category cue stays audible; OS speech does not pass through the Godot buses, so the music is ducked by −6 dB through `SndBusFader` for the duration of the utterance. Queue, cooldown and priority rules are unchanged; the line ends when `tts_is_speaking()` turns false (polled at 10 Hz; hard cap `max(1.2 s, 0.075 s · characters)`). Nothing produced by OS voices is stored or shipped (qa.md 5.11: runtime OS TTS is allowed for accessibility).

*Worked example (fake clock; durations `construction_complete` 1.3 s, `base_under_attack` 1.6 s, `unit_ready` 0.9 s)*: t=0 `construction_complete`(60) plays → t=300 `unit_ready`(45) queued → t=500 `base_under_attack`(92 ≥ 60+20) pre-empts: the current line is cut with a 40 ms fade, the alert starts at 540 ms (12 s cooldown starts) and ends at 2140 → +250 ms gap → `unit_ready` starts at 2390 → t=2500 a second `base_under_attack` is dropped (cooldown) → t=2600 `low_power`(75 ≥ 45+20) pre-empts the running `unit_ready`.

**Repeat while a condition persists**: `low_power` re-announces every 45 s while `SimPlayer.power_state == LOW` (bridge polls 1 Hz; the 45 s line cooldown does the throttling). Match start plays the faction's **motto** line (`match_start_<code>`: the bible mottos, e.g. "Hold the line. Bring them home.") followed by `match_start` ("Battle control online.").

### 5.10 Unit acknowledgements ("bleeps + radio squelch", optional voice)

**Response classes** (`SndProfileDef.voice_class`): INFANTRY (inf_line, inf_at, inf_combat_spec) · VEHICLE (veh_scout, arty_*, mbt_*, veh_aa*) · HEAVY (siege_*, veh_command, veh_assault_carrier) · AIR (air_*) · NAVAL (ship_*) · SUPPORT (inf_support = engineer/specialists, collector, MCV, landing transport) · STRUCTURE (select only). **Types**: SELECT, MOVE, ATTACK, DENY, SPECIAL (order map: MOVE→MOVE; ATTACK, GUARD→ATTACK; DEPLOY, CAPTURE, REPAIR, LOAD, UNLOAD, HARVEST, SCATTER, SELL→SPECIAL; STOP→none).

**Assets** (baseline scope = synthesised, per faction × class × type): SELECT ×3, MOVE ×3, ATTACK ×3, DENY ×2, SPECIAL ×2 = 13 clips × 6 classes + 3 structure-select clips = **81 per faction, 648 total** (~3 MB). Each clip is `[squelch-open click 40–70 ms][faction motif 0.15–0.45 s][squelch-close tail 60–120 ms]` baked into one mono OGG. The motif is a faction-specific timbre/scale/contour (5.15) transposed per class register (INFANTRY high & short, VEHICLE mid, HEAVY low & long, AIR fast trill, NAVAL sonar-ping, SUPPORT soft two-note). Optional Phase-B voice layer: TTS barks per faction × class × type (texts in `responses.json`, ~648 more clips ≈ 4.5 MB) processed by the faction's radio chain.

**Play rules**: global gap 250 ms (`RESP_MIN_GAP_MS`); same class+type gap 700 ms; variant order = shuffled bag per (class, type) so no immediate repeat and never the same as the last two; if the same type is requested ≥ 4 times within 3 s only every second request plays (fatigue guard). Modes: SYNTH → bleep; VOICE → bark (falls back to bleep when absent); MIXED → bark with probability `voice_mix_pct` (60) for SELECT/ATTACK, bleep for MOVE/SPECIAL/DENY. Two dedicated `AudioStreamPlayer`s on `Voice` (round-robin) — outside the pool so they cannot be stolen, and not a ducking key. `ORDER_FAILED` (own unit; `a` = unit id) plays the DENY response of that unit's voice class (`bank.def_profile[entity(a).def_idx].voice_class`); `CMD_REJECTED` (own) plays `snd.ui.error` and the line `unable_to_comply` (`Err.BAD_SITE` → `snd.ui.place_fail` + `cannot_deploy`).

### 5.11 Ambience per biome

Six looped stereo beds on `Ambience` (`amb/wind_open`, `city_hum`, `coast_waves`, `river_flow`, `forest`, `battle_far`; 16–24 s). Evaluated at 2 Hz from a terrain histogram over `24 m·s` around the focus (coarse 8×8-cell summary grid built at map load by `SndAmbience` from `MapData.terrain`): `f_water` (deep_water and shallow with weight 1, ford with weight 0.5), `f_forest` (forest). Every level is continuous in its input (no on/off cliffs): with `A(x, x_full) = 20·log10(clamp(x / x_full, 0, 1))` (amplitude proportional to the fraction, −6 dB per halving, −∞ at 0) the target dB per bed is `wind_open` = family offset (open 0 / urban −9 / coast −3, by `MapData.family`) plus the biome offset below; `city_hum` = 0 on the urban family, else off; `coast_waves` = `max(A(f_water, 0.25), −9 if the family is coast else −∞)`; `river_flow` = `A(f_water, 0.15) − 3` (off on the coast family, where the waves bed covers it); `forest` = `A(f_forest, 0.33) − 3` plus the biome offset; `battle_far` = `A(far_heat, 40) − 6`. The full-scale fractions and trims are data (`mix.ambience`). Detail beds (forest, river) lose a further 6 dB per unit of zoom scale above 1 (3 dB per +0.5). *Worked example*: open temperate map, no water, no forest → only `wind_open` (0 dB) runs; 10 % forest → `forest` = A(0.10, 0.33) − 3 = −13.4 dB; 5 % water → `coast_waves` −14.0 dB and `river_flow` −12.5 dB; 25 % water → `coast_waves` 0 dB; `far_heat` 4 → `battle_far` −26 dB. **Biome flavour** (`MapData.biome`, data `mix.ambience.biome[]`, `[tune]`, no extra assets in v1): temperate `wind +0 dB, pitch ×1.00, forest +0 dB`; desert `+2 dB, ×1.06 (drier, thinner), forest −8 dB`; arctic `+3 dB, ×0.92 (lower howl), forest −4 dB`; tropical `−3 dB, ×1.00, forest +4 dB` — the pitch is the 2D player's `pitch_scale` of the `wind_open` bed and the offsets are added to its target and to the `forest` bed's target. A bed is *started* (fade-in 1.5 s, random start offset — click-free on 2D players `[probe]`) only when its target is above −40 dB and *stopped* (fade-out 2.5 s) after 3 s below −46 dB, so muted beds never cost decode time (stereo OGG ≈ 0.5 % core each `[spike]`).

### 5.12 Warnings, countdown sirens, superweapons

The master catalogue broadcasts `SW_WARNING` to **all** players and never fog-gates it (sim_core §6.2, bible "strategic warning zones … cannot be hidden by fog or decoys"), while the bible makes the *zone* visible to **affected** players. Resolution [design]: **the announcement is global, the siren is for the affected.** "Affected" = the viewer's team owns an alive entity within `extent_units + 3 cells` (3 072 sub-cells) of the target point — the same rule economy uses for `affected_mask` — evaluated at the event and re-tested every 0.5 s by `SndCountdown` (the siren fades out for a player whose last unit left the zone and fades in for one who entered it).

`SW_WARNING` 0x34: `a` owner_pid · `b` sw_idx · `c,d` target x/y · `e` angle · `f` warning_ticks · `g` launcher_id · `h` extent_units. `exec_tick = event.tick + f`.

| Case | Everyone | Affected viewer only |
|---|---|---|
| owner ENEMY/NEUTRAL | line `sw_launch_detected` (97) | siren loop `snd.alarm.sw_siren` (fade-in 300 ms) until `exec_tick` or `SW_CANCELLED`; `snd.alarm.countdown_tick` at every whole second of the last 5 s (pitch ×1.00, 1.06, 1.12, 1.19, 1.26); `snd.alarm.countdown_final` at T−0 |
| owner SELF/ALLY | line `sw_launched` (80) | — (a friendly launch has no siren) |
| hostile `POWER_USED` with `DefPower.warning_t > 0` (barrage: Counterbattery Mission, Tremor Barrage, Counterlaunch Plot; scan: Wideband Scan) | — | line `sw_incoming_strike` (93) — for the scan `scan_detected` (70) — plus `snd.alarm.incoming` (3 klaxon bursts) and a tick each second of the last 3 s of `warning_t`; "affected" uses `power_radius[b] + 3 072` around (c,d) |

Timeline for Atlas (`f` = 200 ticks = 10 s): T−10 line + siren; T−5…T−1 ticks; T−0 final tone; siren stops at `exec_tick`. Aurora `f` = 160 (8 s), Trident `f` = 120 (6 s: siren 6 s, ticks at T−5…T−1). `SW_CANCELLED` 0x36 (`a` owner · `b` sw_idx · `c` reason 1 launcher destroyed / 2 EMP shutdown): siren fades 300 ms; line `sw_cancelled` ("Launch aborted.", 85) to the owner's team and the affected. `SW_LAUNCHED` 0x35 (`a` owner · `b` sw_idx · `c,d` x/y · `e` angle): `snd.sw.<name>.launch` — missile-type launchers (Perun, Tempest, Horizon) positional at the launcher (`entity(g)` remembered from the warning, `SfxHeavy`, AUDIBLE), orbital/beam/capsule types flat; Helios additionally starts the `loop` path voice along the committed line (`c,d` = centre of the line, `e` = angle, `bank.sw_length` and `bank.sw_duration_ticks` (`DefSuperweapon.duration_t`): 16 cells over 12 s); Aurora/Tempest/Dragonfall/Trident start their `loop` for `sw_duration_ticks`. `SW_IMPACT` 0x37 (`a` owner · `b` sw_idx · `c,d` x/y · `e` radius · `f` packet_index): `snd.sw.<name>.impact` at (c,d) on `SfxHeavy`, propagation on, AUDIBLE, one voice per packet.

Own launcher charging: `SW_CHARGING` 0x32 (`a` pid · `b` sw_idx · `c` launcher_id): own → line `sw_charging`(70) and the `snd.sw.<name>.charge` hum bound to the launcher (quiet); an enemy launcher whose `entity_visible` holds → line `enemy_sw_charging`(88). The manager polls `reader.player(viewer)` at 2 Hz → `SndCountdown.set_charge(sw_charge / recharge_ticks, power_state == LOW)`: hum pitch `0.8 + 0.4·fraction`; under a power shortage the pitch freezes and the hum drops 6 dB ("superweapon recharge pauses", bible). `SW_READY` 0x33 → stop the hum, line `sw_ready`(90).

| Superweapon | Warn | `charge` | `launch` | during | `impact` / `end` |
|---|---:|---|---|---|---|
| Atlas Kinetic Array | 10 s | – | orbital rumble + rising whistle (flat) | three staggered whistles | `impact` ×3: kinetic thump + shock crack (huge) |
| Aurora Microwave Array | 8 s | rising microwave whine | discharge thoom (flat) | 8 s EMP crackle field (`loop`) | `impact` pulse; `end` |
| Helios Reflector | 10 s | mirror glint tone | beam ignition (flat) | 12 s moving beam (path `loop`) | `end` crackle fade |
| Perun Missile Complex | 10 s | – | missile launch roar (positional) | flight tail | `impact` bunker-buster thud + ring frag crackle |
| Tempest Swarm Hub | 10 s | – | 24-drone release whoosh (positional) | 20 s swarm buzz (`loop`) | `end` descending battery zings |
| Dragonfall Field Foundry | 10 s | – | capsule re-entry (flat) | landing thuds ×3, 5 s unfold servo (`loop`) | `end` power-down |
| Horizon Mass Driver | 10 s | rail-assist charge | rail crack barrage (positional) | – | `impact` ×3 over 9 s + debris hiss |
| Trident Interception Array | 6 s | – | dome hum-up (flat) | 25 s dome hum (`loop`) + `snd.intercept.zone` snaps | `end` dome collapse |

### 5.13 Formats, streaming and loading

**Ogg Vorbis everywhere** (libvorbis through `soundfile`; `compression_level` 0.38 SFX/loops (≈ q6), 0.55 ambience, 0.50 voice/responses (≈ q5), 0.45 music stems; `bass` stems mono). WAV/QOA is **not shipped**: `[spike]` SFX WAV masters 25 MB vs OGG 3.2 MB (7.9×); runtime cost delta is small (real-time 64 simultaneous looping 3D voices: mono OGG 10–15 % of one core, QOA 6.9 %, PCM 4.6 %; the pool never exceeds 48 and the mix runs on the audio thread). Escape hatch: an `AssetSpec.format = "wav"` for ≤ 50 files < 60 KB if profiling ever shows decode hot spots (loader handles `AudioStreamWAV` transparently). Godot keeps Ogg **resident and compressed** and decodes incrementally on the audio thread (there is no disk streaming), so "streaming vs preloaded" = *bank loading policy*: banks `core` (weapons, impacts, explosions, structures, powers, superweapons, UI, alarms, loops), `fx_<faction>` (for every faction in the match), `vox_computer` + `vox_<local>`, `resp_<local>`, `mus_<local>` + `mus_common`, `amb` are requested with `ResourceLoader.load_threaded_request` during the loading screen and released at `end_match`. `[spike]` `load()` of 116 OGG = 69–256 ms; `[probe]` cold import of 600 small OGG (7.6 MB) = 4.7 s wall. Sample rate 44 100 Hz = `audio/driver/mix_rate` (no resampling in Godot).

### 5.14 Engine facts this design depends on (all verified)

| ID | Fact | Evidence | Consequence |
|---|---|---|---|
| S1 | Positional SFX must be **mono** files; stereo streams are not spatialised (L-only file stays in the left ear: L −17.9 / R −46.1 dBFS at hard right) | spike | 3D events reference mono assets; build emits mono for `spatial=3d`; V-AUD-03 |
| S2 | A current `Camera3D` must exist in the listener viewport; `AudioListener3D` then overrides its transform | spike | `attach_world` check + retry; listener at ground focus |
| S3 | Volume steps click (Synchronized 23.4×, bus 20.8×, player 9.3×); 60 fps ramp 0.91× | spike | ramp everything |
| S4 | Attenuation curves ≈ theory (±0.8 dB), clamp +3 dB; `max_distance` is a linear fade window; default 5 kHz distance LPF costs ~30 % CPU | spike | data model in 5.2; `lowpass_hz` 9–12 kHz |
| S5 | `AudioEffectCapture` works under `--audio-driver Dummy` (real-time paced); `AudioStreamSynchronized` loops sample-exact; never mutate cached resources (`duplicate()` first) | spike | headless integration tests; loop metadata set at runtime |
| S6 | Pool cost: 20 000 randomised `play()` calls 0.58–0.64 s (29–32 µs/call), invariants held; 64 looping moving 3D voices = 10–15 % of one core; position updates 37 µs/frame for 64 | spike | budgets in §9 |
| P1 | `AudioStreamInteractive` with plain OGG clips (bpm 120): switch requested at 0.84 s → new clip audible from **2.00 s** (bar line), 1-beat cross-fade begins at the bar | probe | NEXT_BAR works |
| P2 | Same with `AudioStreamSynchronized` clips (all children carry the same `bpm` metadata); `set_sync_stream_volume` works live before/after the switch (0.102 → 0.299 ramp observed) | probe | stems inside interactive clips |
| P3 | Reversing a pending switch → **0.2 s dropout** | probe | rule 1/2 in 5.8 |
| P4 | Switch during a cross-fade → incoming clip stays ≈ −10 dB (0.098 vs 0.302) until the next bar | probe | rule 1 |
| P5 | No transition defined → immediate ~0.3 s cross-fade; `CLIP_ANY` transitions work | probe | graceful fallback |
| P6 | Filler clip: calm continues to the bar, riser plays 4 s, combat enters at 6.00 s; `get_playback_position()` = 0.0 on interactive players | probe | riser as filler; no `bar_position()` |
| P7 | A **hidden child bus** (`Announcer`→`Voice`, index 6) keys a sidechain compressor on `Music` (index 1): −4.6 dB at −14.3 dBFS tone, recovery −0.5 dB in 2.5 s; `SfxHeavy`→`Sfx` likewise (−15.8 dB for a loud 100 Hz tone); identical depth with the key bus at a lower index | probe | two ducking keys |
| P8 | `stop()` (2D and 3D) and 2D `play(offset)` are click-free (1.0× at 8 random phases); **3D `play(offset)` at a random phase clicked 6.1×** | probe | loops start at 0 with ramp; stolen voices reused immediately |
| P9 | Cold import of 600 small OGG: 4.7 s wall (191 % CPU) | probe | ~1 800-file tree ≈ 15–20 s |

### 5.15 Faction sonic identity (drives generators, `factions.json`, and the objective distinctiveness gate)

| Faction | Identity → sound | Music (bpm / root / mode / kit / bass / pad / lead / swing) | Weapon flavour (pitch st, brightness ×, tail ×, drive ×, signature layer) | Response motif & radio | Announcer voice (placeholder, ear selection required) |
|---|---|---|---|---|---|
| `napc` | durable combined arms: punchy, mid-heavy, heroic | 138 / A2 / aeolian / electro / saw_sub / supersaw / brass / 0 | 0, 1.00, 1.0, 1.0, "boom-clack" breech | brass 2-note call-and-response; clean digital radio | `am_michael` |
| `nec` | precision, sensors: dry, crisp, short tails | 128 / D2 / dorian / electro / fm / glass / pluck / 0 | +1.0, 1.25, 0.6, 0.8, sensor "tick" | rising fourths, glass pings; crisp wide radio | `bf_emma` |
| `olm` | mobile, concealed, electrical: warm, open, energy hum | 126 / E2 / phrygian dominant / taiko / pluck / choir / pluck / 0.10 | −0.5, 0.90, 1.5, 0.9, low energy hum under beams | oud-like plucks with microtonal bends; warm analog radio + static | `am_fenrir` |
| `def` | industrial volume, artillery: heavy, low, long tails | 132 / C2 / harmonic minor / taiko / saw_sub / choir / brass / 0 | −2.0, 0.75, 1.3, 1.4, low-brass growl | low brass fifths, marching pulses; noisy clipped radio | `bm_george` |
| `pd` | amphibious, naval: airy, watery, sonar | 140 / G2 / pentatonic minor / electro / fm / glass / bell / 0 | +0.5, 1.10, 1.2, 0.8, water-slap tail | sonar pings, marimba-bell; smooth digital radio | `af_bella` |
| `han` | cheap infantry, drones: sharp, high, electronic | 120 / D2 / hirajoshi / taiko / pluck / choir / pluck / 0 | +2.0, 1.40, 0.7, 1.0, drone buzz layer | koto-like pentatonic plucks; packet-chirp radio | `af_nicole` |
| `ae` | recovery, salvage: metallic, clanky, rhythmic | 126 / F2 / dorian / taiko / pluck / glass / bell / 0.16 | −0.5, 1.00, 0.9, 1.2, metal clank layer | kalimba polyrhythm; crackly HF radio | `am_puck` |
| `sap` | protected advances, interception: resonant, layered | 132 / F#2 / phrygian dominant / electro / fm / glass / reed / 0.08 | −1.0, 0.95, 1.1, 1.1, shield-hum resonance | reed + tabla-like hits; wobbly radio | `bf_isabella` |

(Music columns are the spike's tested `Flavour` presets `[spike]`: tempo estimator 7/8 within 1.6 %, 80–90 % of pitched energy in-scale; voice mapping is the spike's placeholder.) The 24 subfactions share their parent's pack in v1; `factions.json` supports a per-roster override for music set, announcer pack, response pack and weapon flavour, so a subfaction can diverge later with data only.

### 5.16 Bible and design rules honoured

| Rule (source) | Audio mechanism |
|---|---|
| "Strategic warning zones are visible to affected players and cannot be hidden by fog or decoys" (`rule.combat.targeting_and_warnings`) | `SW_WARNING` is broadcast and never fog-gated (sim_core); the siren/ticks are gated by the geometric "affected" test (5.12), policy AUDIBLE, decoys ignored; the announcement is global |
| Superweapon launcher destroyed/EMP-shut during the warning cancels the attack (`rule.combat.superweapon_control`) | `SW_CANCELLED` stops the siren, line `sw_cancelled` |
| Charging needs power; shortage pauses recharge; one stored charge | charge-hum pitch follows `charge/recharge_ticks`; frozen + −6 dB under shortage; `sw_ready` once |
| Power shortage stops powered defences (`rule.design.power_loss`) | `POWER_LOW` → `power_down` + `low_power` (repeats every 45 s); `STATE` POWERED = 0 on a defence → `defense_offline`; `POWER_RESTORED` → `power_up` |
| Camouflage revealed by firing/damage; decoys look real until identified (`concealment…`) | fog rule uses vision (`cell_visible`, `entity_visible`); a firing camouflaged unit is audible (its cell is visible), unidentified decoys play the mimicked loop, identified ones are silenced |
| EMP never changes ownership / never instantly kills aircraft | `STATE` EMP/SHUTDOWN produce `snd.emp.hit` + shutdown cues only; no death sound for EMP |
| Ordinary AA cannot intercept strategic attacks except Tempest drones; Trident consumes charges | `INTERCEPT` maps to `intercept.zone` (dome entity) or `intercept.aps`; the Tempest drones are ordinary summoned units (their `snd.loop.air.drone` loops are budgeted like any aircraft) and `sw.tempest.loop` adds the distant swarm mass |
| Aircraft need powered Airfield pads to rearm; carriers replenish drones | no dedicated events in the master catalogue: drone launch/dock and rearm cues are `STATE`/`SPAWNED`-derived only if the ability/combat domains add them (non-goal in v1) |
| Fog: hidden enemy units are not rendered (ARCHITECTURE §8) | hidden enemy positional audio dropped (except MUFFLED loud events within 300 m) |
| Unit cap / queues / progressive payment (ARCHITECTURE §12) | `insufficient_funds` (8 s), `unit_cap_reached` (15 s), `on_hold`, `canceled` lines and cash ticks |
| Faction identity, mottos, subfaction inheritance (bible) | per-faction packs; motto lines at match start; subfactions inherit the parent's packs, overridable per roster |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

### 6.1 Commands

Audio **consumes no `SimCommand` and issues none** (DR-12, ARCHITECTURE §3.3). It is a pure reader of the sim's event batch, of a few read-only `SimWorld` queries through `SndWorldReader`, and of direct calls from UI/view/app/net (§3.11). The event codes below are owned by **sim_core's MASTER event catalogue** (`SimEvent`, sim_core §6.2); `SndEventCodes` mirrors exactly the subset audio uses, and `test_snd_event_codes` asserts equality with the `SimEvent` constants by name.

### 6.2 Events consumed (`SndSimBridge` routes)

Record `[type, tick, a, b, c, d, e, f, g, h]` (10 × int32, unspecified fields 0; positions in sub-cells; `own` ⇔ the field names the viewer's pid or an entity of the viewer). Every positional start goes through `SndVoicePool.play_def` (5.2) after the audibility rule of 5.5; "meter" = adds weight to `SndCombatMeter` (5.7); "line" = `SndAnnouncer.say`.

| Code | Name | Fields used | Condition → action |
|---:|---|---|---|
| 0x01 | `SPAWNED` | a id · b def · c owner · d,e x,y · g reason | STRUCTURE + `PLACED` → `snd.struct.online.<kind>`; `DEPLOYED` HQ → `snd.struct.hq_deploy` (5.4.6) |
| 0x02 | `REMOVED` | — | ignored (sales are voiced by `STATE` SELLING and `CASH`) |
| 0x03 | `DIED` | a id · b def · c owner · d,e x,y · h reason | death/collapse table (5.4.4); own losses → lines `unit_lost`(50), `structure_lost`(80), `collector_lost`(82), `superweapon_destroyed`(90); meter |
| 0x04 | `OWNER_CHANGED` | a id · b old · c new · d,e x,y | new == viewer → `building_captured`(60) + `snd.struct.captured`; old == viewer → `structure_captured`(88) + `snd.alarm.base_attack` |
| 0x05 | `STATE` | a id · b state · c value · e,f x,y | state table (5.4.5): EMP, SHUTDOWN, POWERED, CLOAK, LAND/TAKEOFF, SELLING, REPAIRING, HQ deploy |
| 0x06, 0x07 | `LOADED`, `UNLOADED` | c,d x,y | `snd.struct.unit_out.infantry` (UNLOADED full, LOADED −4 dB), visible |
| 0x10 | `DAMAGE` | a target · d dtype · f flags · g,h x,y | bullet / thermal, non-splash → material impact (5.4.3) |
| 0x11 | `WEAPON_FIRED` | a shooter · b weapon · g,h x,y | fire sound + flavour (5.4.1); per-source 40 ms; meter |
| 0x12 | `PROJECTILE_LAUNCHED` | a proj · b weapon · d–g x0,y0,x1,y1 · h flight | missile path voice / shell & bomb whistle (5.4.2) |
| 0x13 | `PROJECTILE_IMPACT` | a proj · b weapon · c,d x,y · f result · g radius · h owner | explosion/impact table (5.4.3); stops the flight voice; meter |
| 0x14 | `EXPLOSION` | a,b x,y · c radius · e owner · g dtype | explosion/impact table, deduped against 0x13 (5.4.3); meter |
| 0x15 | `BEAM` | a shooter · b weapon · d start/stop | beam start event + bound loop / fade + end tail (5.4.5); meter |
| 0x16 | `INTERCEPT` | a interceptor · c,d x,y | `snd.intercept.zone` if the interceptor is a ZONE entity else `snd.intercept.aps` |
| 0x17 | `HEAL` | — | ignored in v1 |
| 0x19 | `SALVAGE` | a salvager · c credits · d phase · e,f x,y | own: loop while phase 0, `snd.eco.cash` at phase 1 |
| 0x20 | `CASH` | a pid · b delta · d reason | own SELL/REFUND (delta > 0) → `snd.eco.cash_big` (+ line `structure_sold`(30) for SELL); other reasons ignored |
| 0x21 | `HARVEST_DELIVERED` | b refinery · c amount · d pid | own → `snd.eco.cash` at the refinery (pitch by amount), 120 ms |
| 0x22, 0x23 | `POWER_LOW`, `POWER_RESTORED` | a pid | own → `snd.struct.power_down` + `low_power`(75) / `snd.struct.power_up` + `power_restored`(65); `low_power` repeats every 45 s while `SimPlayer.power_state == LOW` (bridge polls 1 Hz) |
| 0x24 | `BUILD_STARTED` | — | ignored (UI feedback belongs to the widget) |
| 0x25 | `BUILD_READY` | a pid | own → `construction_complete`(60) + `snd.ui.build_ready` |
| 0x26 | `PRODUCTION_COMPLETE` | a pid · b def · c producer | own → `unit_ready`(45); `snd.struct.unit_out.<class>` at the producer (visible), 250 ms/producer |
| 0x27 | `BUILD_CANCELLED` | a pid | own → `canceled`(40) + `snd.ui.queue_cancel` |
| 0x28 | `QUEUE_BLOCKED` | a pid · c reason | own: 1 funds → `insufficient_funds`(70) + `snd.ui.error`; 2 unit cap → `unit_cap_reached`(60); 5 hold → `on_hold`(40); 3, 4 ignored |
| 0x29, 0x2A | `RESEARCH_STARTED`, `RESEARCH_COMPLETE` | a pid | 0x2A own → `research_complete`(55) + `snd.ui.build_ready` |
| 0x2B | `TECH_UNLOCKED` | a pid | own → `new_construction_options`(40) |
| 0x2C, 0x2D | `TECH_LOST`, `BUILD_PROGRESS` | — | ignored |
| 0x2F | `UNIT_CAP_REACHED` | a pid | own → `unit_cap_reached`(60) (line cooldown dedupes with 0x28) |
| 0x30 | `POWER_USED` | a pid · b power · c,d x,y · f duration | power cue set (5.4.6); hostile + `warning_t > 0` → alert (5.12) |
| 0x31 | `POWER_READY` | a pid · c power_idx | own → `power_<name>_ready` (bank) or `power_ready`(68) |
| 0x32, 0x33 | `SW_CHARGING`, `SW_READY` | a pid · b sw · c launcher | own charging → `sw_charging`(70) + charge hum; visible enemy launcher → `enemy_sw_charging`(88); own ready → `sw_ready`(90), hum off |
| 0x34 | `SW_WARNING` | a owner · b sw · c,d x,y · f ticks · g launcher · h extent | siren/ticks/lines (5.12) — **never fog-gated** |
| 0x35 | `SW_LAUNCHED` | a owner · b sw · c,d x,y · e angle | `snd.sw.<name>.launch` + effect loops; siren off (5.12) |
| 0x36 | `SW_CANCELLED` | a owner · b sw | siren off, `sw_cancelled`(85) |
| 0x37 | `SW_IMPACT` | a owner · b sw · c,d x,y | `snd.sw.<name>.impact`; meter |
| 0x40, 0x42 | `ABILITY`, `REVEAL_AREA` | — | ignored in v1 (powers are voiced by `POWER_USED`) |
| 0x50, 0x51 | `REVEALED`, `HIDDEN` | — | ignored unless `mix.hearing.contact_ping` is enabled (default off) |
| 0x52 | `BASE_UNDER_ATTACK` | a victim_pid | viewer → `base_under_attack`(92) + `snd.alarm.base_attack` (Ui) + music `urgent` + meter; allied victim → `ally_under_attack`(70) if off-screen. Sim already throttles (160 ticks) |
| 0x53 | `UNIT_UNDER_ATTACK` | a victim_pid · b,c x,y · e target | viewer, victim off-screen (> 45 m·s from the focus) → `unit_under_attack`(60), or `aircraft_under_attack`(60) when `entity(e).layer == AIR` |
| 0x54 | `HARVESTER_UNDER_ATTACK` | a victim_pid | viewer → `collector_under_attack`(85) |
| 0x60 | `ORDER_FAILED` | a unit | own unit → deny response of its voice class (5.10) |
| 0x61 | `CMD_REJECTED` | a pid · c Err | own → `snd.ui.error` + `unable_to_comply`(55); `Err.BAD_SITE` → `snd.ui.place_fail` + `cannot_deploy`(60); `NO_CREDITS`, `UNIT_CAP`, `PAUSED` are voiced elsewhere / silent |
| 0x70 | `PLAYER_ELIMINATED` | a pid · b reason · c team | viewer → `end_match` flow; ally → `ally_defeated`(80); enemy → `enemy_defeated`(80); reason `DROP` (3) → `player_disconnected`(70) |
| 0x71 | `MATCH_END` | a winner_team | `end_match(VICTORY \| DEFEAT \| DRAW)` (fallback trigger if the app did not call it) |
| 0x72, 0x73 | `PAUSED`, `UNPAUSED` | — | lines `game_paused` / `game_resumed`(50) |
| 0x74 | `CHECKPOINT` | — | ignored |

Ignored on purpose: 0x02, 0x17, 0x24, 0x2C, 0x2D, 0x40, 0x42, 0x50, 0x51, 0x74. Unknown types map to `R_IGNORE` (never an error: forward compatible). The order of records inside a batch is emission order; the bridge processes announcer/alert/strategic/match records in a first pass over the whole batch (never dropped; repeated cues collapse through the line cooldowns) and the combat records (0x10–0x16) from the newest 512 (§3.2).

### 6.3 Events emitted (presentation only)

GDScript signals of `SndManager` (`announcement_started/finished`, `music_state_changed`, `audio_warning`); `Performance` custom monitors `snd/voices_3d`, `snd/voices_2d`, `snd/starts`, `snd/culls`, `snd/loops`, `snd/heat`, `snd/queue`, `snd/music_state` (registered with `Performance.add_custom_monitor` `[docs]`). **No sim events, no commands, nothing that reaches the checksum.**

### 6.4 Where the sibling specs' proposed events went (for the reconcilers; audio depends only on the master column)

| Proposed in | Proposed event | Master equivalent |
|---|---|---|
| combat | `EV_FIRE` 200 | `WEAPON_FIRED` 0x11 (no result/burst/owner: audio derives owner from the entity, flavour from the weapon id, hitscan hits from `DAMAGE`) |
| combat | `EV_PROJ_SPAWN` 201 / `EV_PROJ_END` 202 | `PROJECTILE_LAUNCHED` 0x12 / `PROJECTILE_IMPACT` 0x13 (results 4 intercepted, 5 expired) |
| combat | `EV_IMPACT` 203 | `PROJECTILE_IMPACT` 0x13 and `EXPLOSION` 0x14 |
| combat | `EV_HIT` 204 | `DAMAGE` 0x10 |
| combat | `EV_BEAM_START/END` 205/206, `EV_SWEEP` 207 | `BEAM` 0x15; the Helios sweep is described by `SW_LAUNCHED` + data |
| combat | `EV_DEATH` 208, `EV_CRASH` 219 | `DIED` 0x03 (+ `EXPLOSION` for chain/crash blasts) |
| combat | `EV_INTERCEPT` 211 | `INTERCEPT` 0x16 (zone vs APS by the interceptor entity's kind) |
| combat | `EV_SUPPRESS/EMP/WEAPON_LOCK` 212/213/220, `EV_AIR_STATE` 215 | `STATE` 0x05 (`ST_SUPPRESSED 9, ST_EMP 7, ST_SHUTDOWN 8, ST_POWERED 13, ST_LANDED 10, ST_TAKEOFF 11`) |
| combat | `EV_ATTACK_ALERT` 214 | `BASE_/UNIT_/HARVESTER_UNDER_ATTACK` 0x52–0x54 |
| combat | `EV_REARM/EV_DRONE` 216/217, `EV_EJECT` 218 | no master event (rearm and drone cues dropped in v1); eject → `UNLOADED` 0x07 |
| economy | `EVT_STRUCTURE_READY` 302, `_PLACED/_ACTIVE` 303/304 | `BUILD_READY` 0x25, `SPAWNED` (PLACED) 0x01 |
| economy | `EVT_UNIT_PRODUCED` 305, `_RESEARCH_COMPLETE` 307 | `PRODUCTION_COMPLETE` 0x26, `RESEARCH_COMPLETE` 0x2A |
| economy | `EVT_CREDITS_GAINED` 308, `_SALVAGE_*` 327/328 | `HARVEST_DELIVERED` 0x21 / `CASH` 0x20, `SALVAGE` 0x19 |
| economy | `EVT_INSUFFICIENT_FUNDS` 309, `_UNIT_CAP_REACHED` 310 | `QUEUE_BLOCKED` 0x28 (1, 2), `UNIT_CAP_REACHED` 0x2F |
| economy | `EVT_POWER_SHORTAGE/RESTORED` 311/312 | `POWER_LOW/RESTORED` 0x22/0x23 |
| economy | `EVT_STRUCTURE_SOLD/SELLING` 314/315, `_REPAIR_STATE` 316, `_HQ_DEPLOYED` 317 | `CASH` (SELL) + `STATE` SELLING/REPAIRING/DEPLOYED |
| economy | `EVT_ORDER_FAILED` 319, `EVT_CMD_REJECTED` 300, `EVT_PLACE_REJECTED` 301 | `ORDER_FAILED` 0x60, `CMD_REJECTED` 0x61 (`Err.BAD_SITE`) |
| economy | `EVT_COLLECTOR_ATTACKED` 320, `EVT_STRUCTURE_CAPTURED` 326 | `HARVESTER_UNDER_ATTACK` 0x54, `OWNER_CHANGED` 0x04 |
| economy | `EVT_POWER_ACTIVATED` 402, `_POWER_READY` 401, `_POWER_UNLOCKED` 400 | `POWER_USED` 0x30, `POWER_READY` 0x31 (first ready = unlocked) |
| economy | `EVT_WARNING` 404, `EVT_SW_READY/CANCELLED/EXEC_START/IMPACT` 405–408 | `SW_WARNING` 0x34, `SW_READY` 0x33, `SW_CANCELLED` 0x36, `SW_LAUNCHED` 0x35, `SW_IMPACT` 0x37 |
| economy | `EVT_POWER_EFFECT_END` 403, `EVT_SW_DONE` 409, `EVT_SUMMON_EXPIRED` 410, `EVT_CAPTURE_PROGRESS` 324, `EVT_NO_REFINERY` 321 | none (durations come from `POWER_USED.f` and `DefSuperweapon.duration_t`; expiry is `DIED` reason EXPIRED; capture-progress and no-refinery cues are dropped in v1) |
| abilities | `EV_VIS_CHANGED`, `EV_GHOST_*` (23x) | `REVEALED/HIDDEN` 0x50/0x51 (optional contact ping) |
| movement (terrain_movement 6.3) | `EV_MOVE_FAILED` 0x40 | `ORDER_FAILED` 0x60 (own unit → deny response) |
| movement | `EV_AIR_TAKEOFF` 0x42 / `EV_AIR_LANDED` 0x43 | `STATE` 0x05 `ST_TAKEOFF 11` / `ST_LANDED 10` (`snd.air.takeoff` / `snd.air.landing`) |
| movement | `EV_BOARDED` 0x44 / `EV_UNBOARDED` 0x45 | `LOADED` 0x06 / `UNLOADED` 0x07 |
| movement | `EV_MEDIUM_CHANGED` 0x41, `EV_DOCKED/UNDOCKED` 0x46/0x47, `EV_STUCK` 0x48, `EV_NAV_CHANGED` 0x49 | none (amphibious splash and wake cues, collector dock cues: dropped in v1; the payout is voiced by `HARVEST_DELIVERED`; stuck/nav are AI/debug) |

Movement proposed numbers 0x40–0x49 that collide with the master codes 0x40 `ABILITY` / 0x42 `REVEAL_AREA` are harmless to audio: both are in the ignored set, and the unassigned ones map to `R_IGNORE`.

Additions requested from other domains are numbered in §13 (chiefly the owner of a fired weapon, the power domain's `SW_LAUNCHED` timing, and the `GameData` accessors).

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

All files: UTF-8, LF, 2-space indent, strict JSON (no comments, no trailing commas), `"schema"` first, keys starting with `_` are documentation and ignored, **entries sorted by id**, unknown keys are load errors (typos surface at load time, `[spike]` t_events). Audio data is **presentation data**: it lives in `game/data/audio/`, is excluded from the lobby data hash (DR-10 applies only to `balance/` and `bible/`), and must be included by the export filter `data/*/*.json` (data_balance §13-20: `include_filter="data/*.json,data/*/*.json"`).

### 7.1 `manifest.json`
```json
{ "schema": "meridian.audio.manifest/1", "format": 1,
  "files": ["announcer.json", "events.json", "factions.json", "mix.json", "music.json", "responses.json"] }
```

### 7.2 `mix.json` — buses, pools, camera, hearing, loops
`engine.*` mirrors the `[audio]` values of `game/project.godot` (they are start-up settings and cannot be changed at runtime); `validate_audio.py` fails when they differ (V-AUD-25). Everything else is applied at runtime by `SndBus`, `SndVoicePool`, `SndListener`, `SndLoopManager` and `SndSimBridge`.
```json
{
  "schema": "meridian.audio.mix/1",
  "engine": { "mix_rate": 44100, "output_latency_ms": 30 },
  "buses": [
    { "name": "Master", "send": "", "volume_db": 0.0, "effects": [
      { "id": "night", "type": "compressor", "enabled": false, "threshold_db": -24.0, "ratio": 3.0, "attack_us": 20000.0, "release_ms": 250.0, "gain_db": 4.0 },
      { "id": "muffle", "type": "lowpass", "enabled": false, "cutoff_hz": 1200.0 },
      { "id": "limiter", "type": "hard_limiter", "enabled": true, "ceiling_db": -1.0, "pre_gain_db": 0.0, "release": 0.1 } ] },
    { "name": "Music", "send": "Master", "volume_db": -6.0, "effects": [
      { "id": "duck_ann", "type": "compressor", "enabled": true, "sidechain": "Announcer", "threshold_db": -18.0, "ratio": 3.0, "attack_us": 12000.0, "release_ms": 450.0, "gain_db": 0.0 },
      { "id": "duck_heavy", "type": "compressor", "enabled": true, "sidechain": "SfxHeavy", "threshold_db": -12.0, "ratio": 2.0, "attack_us": 8000.0, "release_ms": 350.0, "gain_db": 0.0 } ] },
    { "name": "Sfx", "send": "Master", "volume_db": -2.0, "effects": [] },
    { "name": "Ambience", "send": "Master", "volume_db": -8.0, "effects": [
      { "id": "duck_heavy", "type": "compressor", "enabled": true, "sidechain": "SfxHeavy", "threshold_db": -16.0, "ratio": 2.5, "attack_us": 8000.0, "release_ms": 400.0, "gain_db": 0.0 } ] },
    { "name": "Ui", "send": "Master", "volume_db": -2.0, "effects": [] },
    { "name": "Voice", "send": "Master", "volume_db": 0.0, "effects": [] },
    { "name": "Announcer", "send": "Voice", "volume_db": 0.0, "effects": [] },
    { "name": "SfxHeavy", "send": "Sfx", "volume_db": 0.0, "effects": [] }
  ],
  "pool": { "voices_3d": { "low": 24, "medium": 40, "high": 48 }, "voices_2d": 16, "reserve_high_slots": 6, "reserve_high_priority": 70,
            "max_starts_per_frame": 24, "steal_margin": 1.0, "age_penalty_per_s": 1.0, "cull_below_db": -42.0 },
  "camera": { "ref_height_m": 55.0, "zoom_scale_min": 0.6, "zoom_scale_max": 2.0, "listener_height_m": 2.0,
              "source_height_ground_m": 1.5, "source_height_air_m": 22.0, "focus_smooth_s": 0.08 },
  "hearing": { "max_scan_m": 750.0, "loud_fog_radius_m": 300.0, "fog_muffled_gain_db": -9.0, "fog_muffled_lowpass_hz": 1200.0, "offscreen_alert_m": 45.0 },
  "loops": { "budget": { "low": 8, "medium": 12, "high": 16 }, "scan_period_s": 0.25, "radius_m": 90.0, "hysteresis_db": 3.0,
             "fade_in_ms": 120, "fade_out_ms": 200, "pitch_speed_lo": 0.85, "pitch_speed_hi": 1.15, "max_candidates": 160 },
  "propagation": { "speed_mps": 900.0, "max_delay_ms": 400 },
  "size_thresholds_units": { "small": 819, "medium": 1536, "large": 2560 },
  "replay": { "gate_priority_above_2x": 80 },
  "strategic": { "helios_length_cells": 16.0 },
  "terrain": { "material": ["water", "water", "water", "dirt", "dirt", "dirt", "dirt", "concrete", "wood", "concrete", "concrete", "concrete", "concrete", "concrete", "concrete"],
               "_ids": "MapTerrain 0..14: deep_water shallow ford beach grass dirt sand rock forest road pavement rubble urban_block cliff mountain" },
  "ambience": { "scan_period_s": 0.5, "radius_m": 24.0, "grid_cells": 8, "water_weight": [1.0, 1.0, 0.5], "forest_id": 8,
                "family_wind_db": [0.0, -9.0, -3.0], "coast_floor_db": -9.0,
                "full": { "coast": 0.25, "river": 0.15, "forest": 0.33, "far_heat": 40.0 }, "trim_db": { "river": -3.0, "forest": -3.0, "battle_far": -6.0 },
                "start_db": -40.0, "stop_db": -46.0, "stop_after_s": 3.0, "fade_in_s": 1.5, "fade_out_s": 2.5, "detail_zoom_db_per_unit": -6.0,
                "biome": [ { "name": "temperate", "wind_db": 0.0, "wind_pitch": 1.00, "forest_db": 0.0 },
                           { "name": "desert",    "wind_db": 2.0, "wind_pitch": 1.06, "forest_db": -8.0 },
                           { "name": "arctic",    "wind_db": 3.0, "wind_pitch": 0.92, "forest_db": -4.0 },
                           { "name": "tropical",  "wind_db": -3.0, "wind_pitch": 1.00, "forest_db": 4.0 } ] }
}
```

### 7.3 `events.json` — events, profiles, cue tables, `sim_map` (this is the V-REF-02 registry)
Top-level keys: `schema`, `groups`, `events`, `profiles`, `power_cues`, `sw_cues`, `sim_map`. **Registry contract**: the set of valid presentation ids is `keys(events) ∪ keys(profiles)`. Event keys (all optional except `variants`): `category`, `bus`, `priority`, `variants[]`, `flavours{code: variants[]}`, `volume_db`, `volume_jitter_db`, `pitch`, `pitch_jitter_semitones`, `spatial{mode ui|global|3d, unit_size_m, max_distance_m, attenuation inverse|inverse_square|logarithmic|none, lowpass_hz, panning_strength, doppler, propagation, fog hidden|muffled|audible, fog_gain_db, fog_lowpass_hz}`, `limit{group, max_instances, min_interval_ms, steal none|oldest|quietest}`, `loop`, `fade_in_ms`, `fade_out_ms`, `cull_below_db`, `link{loop, end}`, `tags`, `notes`. A variant is `{"stream": "<asset id>", "weight": 1.0}` or `{"group": "<asset group>"}` (expands to `<group>_1…N` from the asset manifest). Asset ids are relative to `res://assets/audio/`, no extension; for `mode: "3d"` the loader takes `<id>.mono.ogg` when present else `<id>.ogg`.

```json
{
  "schema": "meridian.audio.events/2",
  "groups": { "heavy": { "max_voices": 8 }, "loops": { "max_voices": 16 }, "small_arms": { "max_voices": 10 } },
  "events": {
    "snd.loop.engine.tracked": {
      "category": "loop", "bus": "Sfx", "priority": 15, "loop": true, "fade_in_ms": 120, "fade_out_ms": 200,
      "variants": [ { "stream": "sfx/loop/engine_tracked", "weight": 1.0 } ],
      "volume_db": 0.0, "pitch_jitter_semitones": 0.0,
      "spatial": { "mode": "3d", "unit_size_m": 18.0, "max_distance_m": 120.0, "attenuation": "inverse", "lowpass_hz": 6000.0, "panning_strength": 1.0, "fog": "hidden" },
      "limit": { "group": "loops", "max_instances": 12, "min_interval_ms": 0, "steal": "oldest" }
    },
    "snd.ui.click": {
      "category": "ui", "bus": "Ui", "priority": 95,
      "variants": [ { "stream": "ui/click", "weight": 1.0 } ],
      "pitch_jitter_semitones": 0.2, "spatial": { "mode": "ui" },
      "limit": { "max_instances": 4, "min_interval_ms": 30, "steal": "oldest" }
    },
    "snd.weapon.small_arms": {
      "category": "weapon", "bus": "Sfx", "priority": 28,
      "variants": [ { "group": "sfx/weapon/small_arms" } ],
      "flavours": {
        "napc": [ { "group": "sfx/weapon_fx/napc/small_arms" } ],
        "han": [ { "group": "sfx/weapon_fx/han/small_arms" } ]
      },
      "volume_db": -3.0, "volume_jitter_db": 1.5, "pitch": 1.0, "pitch_jitter_semitones": 0.8, "cull_below_db": -42.0,
      "spatial": { "mode": "3d", "unit_size_m": 22.0, "max_distance_m": 170.0, "attenuation": "inverse", "lowpass_hz": 9000.0, "panning_strength": 1.0, "fog": "hidden" },
      "limit": { "group": "small_arms", "max_instances": 6, "min_interval_ms": 35, "steal": "oldest" }
    },
    "snd.weapon.tank_cannon_medium": {
      "category": "weapon", "bus": "Sfx", "priority": 58,
      "variants": [ { "group": "sfx/weapon/tank_cannon_medium" } ],
      "volume_db": 0.0, "volume_jitter_db": 1.0, "pitch_jitter_semitones": 0.6,
      "spatial": { "mode": "3d", "unit_size_m": 40.0, "max_distance_m": 300.0, "attenuation": "inverse", "lowpass_hz": 12000.0, "fog": "hidden" },
      "limit": { "group": "heavy", "max_instances": 4, "min_interval_ms": 90, "steal": "oldest" }
    }
  },
  "profiles": {
    "snd.profile.mbt_t1": {
      "voice_class": "vehicle", "weapon_variant": { "tank_cannon": "light" },
      "loops": [ { "event": "snd.loop.engine.tracked", "when": "moving", "gain_db": 0.0, "pitch_speed": true } ]
    },
    "snd.profile.mbt_t2": { "parent": "snd.profile.mbt_t1", "weapon_variant": { "tank_cannon": "medium" } }
  },
  "power_cues": { "power.napc.uav_sweep": "recon", "power.olm.dust_screen": "smoke", "power.def.tremor_barrage": "barrage" },
  "sw_cues": { "superweapon.napc.atlas_kinetic_array": "atlas", "superweapon.olm.helios_reflector": "helios" },
  "sim_map": {
    "weapon_fire": { "pattern": "snd.weapon.{archetype}", "fallback": "snd.weapon.small_arms" },
    "explosion": { "pattern": "snd.explosion.{size}", "fallback": "snd.explosion.small" },
    "impact_bullet": { "pattern": "snd.impact.bullet.{material}", "fallback": "snd.impact.bullet.dirt" },
    "collapse": { "pattern": "snd.collapse.{area}", "fallback": "snd.collapse.s1" },
    "profile": { "pattern": "snd.profile.{archetype}", "fallback": "snd.profile.generic.tracked" }
  }
}
```
Profile keys: `parent`, `voice_class`, `weapon_variant{weapon archetype → suffix}`, `loops[]`, `die`, `spawn`, `select_fx`, `scalars`. Schema rules: `variants` non-empty (after expansion); `weight > 0`; `profiles[*].loops[*].when ∈ always|moving|airborne|structure_active|charging`; `profiles[*].voice_class ∈ infantry|vehicle|heavy|air|naval|support|structure`; `power_cues` values ∈ `recon|repair|buff|shield|cloak|smoke|barrage|generic`; `sw_cues` values ∈ the 8 superweapon names; `flavours` keys ⊆ `napc nec olm def pd han ae sap`; profile `parent` chains must be acyclic (depth ≤ 4). Migration from the spike's v1 file: `unit_size`→`unit_size_m`, `max_distance`→`max_distance_m`, `lowpass_hz`/`panning_strength` moved inside `spatial` (already), `@pack` overrides → `flavours`, `sim_map` patterns keep their meaning; ids gain the `snd.` prefix.

### 7.4 `music.json`
```json
{
  "schema": "meridian.audio.music/1",
  "meter": { "tau_s": 6.0, "h_ref": 25.0, "attack_s": 0.6, "release_s": 4.0, "radius_m": 80.0, "min_dist_weight": 0.15, "far_weight": 0.25,
             "combat_on": 0.40, "combat_on_hold_s": 1.0, "combat_off": 0.15, "combat_off_hold_s": 18.0, "min_combat_s": 25.0,
             "weights": { "fire_small": 0.3, "fire_medium": 0.6, "fire_heavy": 1.0, "fire_artillery": 1.2, "beam_start": 0.5, "impact_base": 0.3, "impact_per_size": 0.25,
                          "death_unit_own": 4.0, "death_unit_enemy": 2.0, "death_structure": 8.0, "strategic": 30.0, "alert_own": 20.0 } },
  "director": { "smoothing_s": 0.8, "min_switch_interval_s": 8.0, "calm_base": 0.2, "calm_gain": 1.5, "calm_max": 0.75, "combat_floor": 0.55, "combat_floor_s": 10.0 },
  "stem_windows": {
    "calm":   { "pads": [0.0, 0.20], "bass": [0.10, 0.35], "drums": [0.30, 0.60], "lead": [0.55, 0.90] },
    "combat": { "pads": [0.0, 0.15], "bass": [0.15, 0.40], "drums": [0.35, 0.65], "lead": [0.65, 0.95] }
  },
  "transitions": {
    "calm>combat":     { "from": "next_bar",  "to": "start", "fade": "cross", "fade_beats": 2.0, "filler": "riser" },
    "calm>combat_hot": { "from": "next_beat", "to": "start", "fade": "cross", "fade_beats": 1.0 },
    "combat>calm":     { "from": "next_bar",  "to": "start", "fade": "cross", "fade_beats": 4.0 }
  },
  "tracks": {
    "napc.combat": { "folder": "mus/napc/combat", "bpm": 138.0, "bars": 24, "bar_beats": 4, "beat_count": 96, "length_samples": 1840696,
                     "stems": ["drums", "bass", "pads", "lead"], "mono_stems": ["bass"], "mode": "aeolian", "root_midi": 45 },
    "napc.calm":   { "folder": "mus/napc/calm", "bpm": 83.0, "bars": 12, "bar_beats": 4, "beat_count": 48, "length_samples": 1530217,
                     "stems": ["drums", "bass", "pads", "lead"], "mono_stems": ["bass"], "mode": "aeolian", "root_midi": 45 }
  },
  "stingers": {
    "stinger.napc.riser":   { "stream": "mus/stinger/napc_riser", "bpm": 138.0, "bars": 2 },
    "stinger.napc.victory": { "stream": "mus/stinger/napc_victory" },
    "stinger.napc.defeat":  { "stream": "mus/stinger/napc_defeat" }
  },
  "sets": { "napc": { "calm": "napc.calm", "combat": "napc.combat", "riser": "stinger.napc.riser", "victory": "stinger.napc.victory", "defeat": "stinger.napc.defeat" } },
  "roster_sets": {},
  "contexts": { "menu": { "track": "menu.theme", "intensity": 0.6 }, "lobby": { "track": "menu.theme", "intensity": 0.35 } }
}
```
`length_samples = round(bars·bar_beats·60/bpm·44100)` (1 840 696 = 24 bars @ 138 BPM = 41.7 s; 1 530 217 = 12 bars @ 83 BPM = 34.7 s; the spike's 32 bars @ 140 BPM = 2 419 200) and **all stems of a track must have exactly this length** (V-AUD-21). `beat_count = bars·bar_beats`. The real file holds all 16 faction tracks plus `menu.theme` (`mus/menu`, 24 bars @ 100 BPM = 2 540 160 samples = 57.6 s), all 8 `sets`, and 25 stingers (8 × riser/victory/defeat + `match_start`); `roster_sets` maps a roster id to a set key (empty in v1).

### 7.5 `announcer.json`
```json
{
  "schema": "meridian.audio.announcer/1",
  "defaults": { "cooldown_ms": 6000, "expire_ms": 8000, "priority": 50, "gap_ms": 250, "preempt_margin": 20, "max_queue": 4 },
  "categories": { "alert": { "gap_ms": 2500 }, "prod": { "gap_ms": 1500 }, "eco": { "gap_ms": 2000 }, "sw": { "gap_ms": 800 }, "match": { "gap_ms": 500 } },
  "packs": {
    "computer": { "label": "Computer", "engine": "kokoro", "voice": "af_heart", "chain": "computer" },
    "napc": { "label": "Peace Corps", "engine": "kokoro", "voice": "am_michael", "chain": "officer", "motto": "Hold the line. Bring them home." }
  },
  "lines": {
    "base_under_attack": { "text": "Base under attack.", "category": "alert", "priority": 92, "cooldown_ms": 12000, "expire_ms": 4000, "variants": 2 },
    "construction_complete": { "text": "Construction complete.", "category": "prod", "priority": 60, "cooldown_ms": 3000, "variants": 2 },
    "low_power": { "text": "Low power.", "category": "eco", "priority": 75, "cooldown_ms": 45000, "variants": 2 }
  }
}
```
Line catalogue (43 common lines; asset `vox/<pack>/<line>[_<n>]`; `(priority, cooldown)`; the trigger of each is in 6.2): **prod/eco**: `construction_complete`(60, 3 s), `unit_ready`(45, 5 s), `new_construction_options`(40, 20 s), `research_complete`(55, 3 s), `insufficient_funds`(70, 8 s), `unit_cap_reached`(60, 15 s), `low_power`(75, 45 s), `power_restored`(65, 10 s), `defenses_offline`(72, 30 s), `on_hold`(40, 2 s), `canceled`(40, 2 s), `structure_sold`(30, 1.5 s), `cannot_deploy`(60, 3 s), `unable_to_comply`(55, 2.5 s), `power_ready`(68, 4 s) · **alerts/losses**: `base_under_attack`(92, 12 s), `collector_under_attack`(85, 12 s), `unit_under_attack`(60, 15 s), `aircraft_under_attack`(60, 15 s), `ally_under_attack`(70, 15 s), `unit_lost`(50, 8 s), `structure_lost`(80, 5 s), `collector_lost`(82, 10 s), `structure_captured`(88, 6 s), `building_captured`(60, 4 s), `systems_disabled`(75, 15 s), `superweapon_destroyed`(90, 10 s) · **strategic**: `sw_charging`(70, 30 s), `sw_ready`(90, 10 s), `sw_launched`(80, 10 s), `sw_cancelled`(85, 10 s), `enemy_sw_charging`(88, 60 s), `sw_launch_detected`(97, 3 s), `sw_incoming_strike`(93, 6 s), `scan_detected`(70, 20 s) · **match**: `match_start`(90), `victory`(100), `defeat`(100), `ally_defeated`(80, 3 s), `enemy_defeated`(80, 3 s), `player_disconnected`(70, 3 s), `game_paused`(50, 1 s), `game_resumed`(50, 1 s). Lines with `variants: 2`: `construction_complete, unit_ready, insufficient_funds, unit_lost, base_under_attack, low_power`. Each faction pack additionally has `match_start_<code>` (its bible motto) and its six `power_<name>_ready` lines (e.g. "UAV sweep ready."). Totals: computer pack 43 + 6 second takes = 49 files; each faction pack 49 + 1 motto + 6 named power lines = 56 files → **497 announcer files** (≈ 7.2 MB at 14.5 KB/line `[spike]`).

### 7.6 `responses.json`
```json
{
  "schema": "meridian.audio.responses/1",
  "gaps": { "global_ms": 250, "same_ms": 700, "fatigue_count": 4, "fatigue_window_s": 3.0 },
  "default_mode": "synth", "voice_mix_pct": 60,
  "classes": { "infantry": { "register": "high", "len_ms": [150, 260] }, "vehicle": { "register": "mid", "len_ms": [200, 340] },
               "heavy": { "register": "low", "len_ms": [280, 450] }, "air": { "register": "trill", "len_ms": [160, 300] },
               "naval": { "register": "ping", "len_ms": [250, 420] }, "support": { "register": "soft", "len_ms": [180, 320] },
               "structure": { "register": "click", "len_ms": [80, 160] } },
  "types": { "select": 3, "move": 3, "attack": 3, "deny": 2, "special": 2 },
  "structure_types": { "select": 3 },
  "barks": { "infantry": { "select": ["Yes, sir.", "Ready.", "Standing by."], "move": ["Moving out.", "On my way.", "Roger."],
                            "attack": ["Engaging.", "Open fire.", "Attacking."], "deny": ["Negative.", "Can't do that."], "special": ["Affirmative.", "On it."] } }
}
```
Clip ids: `resp/<faction>/<class>_<type>_<n>` (bleep) and `resp/<faction>/voice/<class>_<type>_<n>` (bark, Phase B). Counts: 6 classes × (3+3+3+2+2 = 13) + 3 structure = 81 per faction × 8 = 648 bleeps.

### 7.7 `factions.json`
```json
{
  "schema": "meridian.audio.factions/1",
  "factions": {
    "napc": { "music_set": "napc", "announcer_pack": "napc", "response_pack": "napc", "weapon_flavour": "napc",
              "flavour": { "pitch_st": 0.0, "bright": 1.0, "tail": 1.0, "drive": 1.0, "layer": "breech_clack" },
              "radio": { "style": "clean_digital", "squelch_open_ms": 55, "squelch_close_ms": 90, "hiss_db": -44.0 } },
    "han":  { "music_set": "han", "announcer_pack": "han", "response_pack": "han", "weapon_flavour": "han",
              "flavour": { "pitch_st": 2.0, "bright": 1.4, "tail": 0.7, "drive": 1.0, "layer": "drone_buzz" },
              "radio": { "style": "packet_chirp", "squelch_open_ms": 40, "squelch_close_ms": 60, "hiss_db": -50.0 } }
  },
  "roster_overrides": { "roster.han.cambodia": { "response_pack": "han" } }
}
```
All 8 faction entries are required; `roster_overrides` keys must be roster ids of the bible (checked against `GameData`).

### 7.8 Generation pipeline (`tools/py/audio/`)

**Regenerate**
```
python3 tools/py/audio/bootstrap.py [--voice]                     # reuses the repo-local .cache/venv when it satisfies the pins (numpy, soundfile, Pillow; + kokoro-onnx/onnxruntime for --voice), else creates .cache/venv_audio; never deletes a venv; ffmpeg only for voice until chains.py is numpy-only
.cache/venv/bin/python tools/py/audio/build_all.py sfx music responses --jobs 4        # ≈ 4 min (spike: 38 recipes 20 s, 4 s/track, scaled to ≈ 470 SFX + 16 tracks + 648 bleeps)
.cache/venv/bin/python tools/py/audio/build_all.py voice --engine kokoro               # ≈ 15–20 min at RTF 1.55; text+voice hash cache → only changed lines re-synthesised
.cache/venv/bin/python tools/py/audio/build_all.py events                              # scaffold: adds missing event/profile stubs from the catalog, never overwrites hand-edited fields
.cache/venv/bin/python tools/py/audio/build_all.py check [--verify] [--sheets]         # QA + budget + validators; --verify re-renders to a temp dir and compares hashes
tools/gd import && tools/gd test snd
```
Windows uses `.cache\venv\Scripts\python.exe`; `bootstrap.py` prints the exact command. The system `python3` numpy was broken on the dev machine (namespace stub, no `__version__`) — bootstrap always builds its own venv and asserts `numpy.__version__`.

**Asset id and path scheme** (all lower-case `[a-z0-9_]`, ≤ 100 chars, no Windows-reserved names; lint L002): `game/assets/audio/<family>/<...>/<name>[_<n>][.mono].ogg`: `sfx/weapon/<archetype>_<n>`, `sfx/weapon_fx/<faction>/<archetype>_<n>`, `sfx/proj/…`, `sfx/impact/<material>_<size?>_<n>`, `sfx/explosion/<size>_<n>`, `sfx/death/…`, `sfx/loop/<name>`, `sfx/struct/…`, `sfx/power/<class>_<phase>`, `sfx/sw/<name>_<phase>`, `ui/<name>`, `alarm/<name>`, `amb/<bed>`, `mus/<faction>/<state>/<stem>`, `mus/menu/<stem>`, `mus/stinger/<name>`, `vox/<pack>/<line>[_<n>]`, `resp/<faction>/…`. **Bank** = first path segment(s): `sfx|ui|alarm` → `core`, `sfx/weapon_fx/<f>` → `fx_<f>`, `amb` → `amb`, `mus/<f>/…` and `mus/stinger/<f>_…` → `mus_<f>`, `mus/menu/…` and `mus/stinger/match_start` → `mus_common`, `vox/<p>` → `vox_<p>`, `resp/<f>` → `resp_<f>`.

**`AssetSpec`** (catalog; the single source of truth for what exists)
```python
@dataclass(frozen=True)
class AssetSpec:
    id: str                    # "sfx/weapon/small_arms"  (variants → small_arms_1..n)
    recipe: str                # "rifle_shot"  (function in tools/py/audio/sfx/*.py)
    variants: int = 1
    channels: str = "mono"     # "mono" | "stereo" | "both" (both → <id>.ogg stereo + <id>.mono.ogg)
    loop: bool = False
    peak_db: float = -1.5      # true-peak ceiling; loops -6
    lufs: float | None = None  # loudness target (loops, beds, alarms, ui); None = peak-normalise
    exciter: float = 0.0       # psychoacoustic bass amount (spike EXCITER table)
    quality: str = "sfx"       # oggtools preset: sfx 0.38 | ambience 0.55 | voice 0.50 | music 0.45
    params: dict = field(default_factory=dict)   # recipe parameters, incl. faction flavour axes {pitch_st, bright, tail, drive, layer}
    salt: int = 0              # extra RNG salt (bump to re-roll one asset)
    tags: tuple[str, ...] = ()
```
**Recipe contract**: `fn(rng: np.random.Generator, variant: int, **params) -> ndarray` (mono `(n,)` or stereo `(n,2)`, float64); pure (no globals, no I/O, no clock); looping recipes use circular noise / whole-cycle-snapped oscillators / wrap-around placement so the seam is continuous by construction. **Master chain per asset** (spike `render()`): stereo/mono per spec → DC removal (one-shots) → bass exciter → LR4 mono-below-140 Hz (stereo) → peak/LUFS normalisation (`min(lufs_gain, peak ceiling)`) → 16-bit TPDF dither (seeded) → libvorbis (`oggtools.encode_vorbis`, serial rewritten to `0x4D455249` with recomputed page CRCs) → mono twin for `both`.

**Seeds**: `rng_for(name, salt) = default_rng([crc32(name), salt & 0xFFFFFFFF])` with `name = f"{id}#{variant}"`; adding an asset never perturbs another. Music: `rng_for(f"arr:{flavour}:{style}:{bars}:{key}", flavour.seed)`. Dither: `rng_for(name, 5)`.

**Manifest** `game/assets/audio/audio_manifest.json` (generated, committed, sorted):
```json
{
  "schema": "meridian.audio.assets/1",
  "generator": { "dsp_version": 3, "python": "3.14.0", "numpy": "2.5.3", "soundfile": "0.14.0", "platform": "darwin-arm64", "tts": { "kokoro_onnx": "0.4.7", "model": "kokoro-v1.0.int8" } },
  "totals": { "files": 1720, "bytes": 69000000 },
  "assets": {
    "sfx/weapon/small_arms_1": { "file": "sfx/weapon/small_arms_1.mono.ogg", "bank": "core", "category": "weapon", "channels": 1, "loop": false,
      "duration_samples": 57330, "bytes": 16934, "sha256": "7adc3e2ee467976b…", "pcm_sha256": "3f1c…", "recipe_hash": "a91d…",
      "lufs_i": -21.0, "true_peak_db": -1.5, "seam_score": null, "flavour": null }
  }
}
```
(the elided hex is only in this document; the real file holds full 64-char hashes.) `recipe_hash = sha256(recipe source + json(params) + DSP_VERSION + MASTER_CHAIN_VERSION)`; an asset is re-rendered only when its `recipe_hash` changes or its file is missing. **Cross-platform note**: numpy FFT/`libvorbis` results are bit-identical between two runs on one machine (`[spike]` 38/38 WAV and 56/56 OGG identical) but may differ in the last ulp across platforms or library versions, so `check --verify` compares bytes only when `generator.platform` and library versions match the manifest, else it compares metrics (LUFS ±0.3 LU, true peak ±0.3 dB, duration exactly, loop seam ≤ threshold). The committed OGGs are the runtime truth; CI never depends on regeneration.


**Provenance** `game/assets/audio/PROVENANCE.json` (generated by `build_all.py` from the manifest, committed, sorted by `file`; the schema is fixed by qa.md 7.8 and the QA gate DA-27 audits it; V-AUD-26 is the producer-side check). One entry per shipped OGG:
```json
{ "files": [
  { "file": "game/assets/audio/sfx/weapon/small_arms_1.mono.ogg", "sha256": "7adc3e2ee467976b…", "generator": "meridian-audio-dsp 3",
    "model": null, "model_sha256": null, "voice": null, "text": null, "language": null,
    "licence_model": "procedural", "licence_tools": ["BSD-3-Clause (numpy, soundfile)", "LGPL-2.1 (libsndfile, build-time only)", "BSD-3-Clause (libvorbis, build-time only)"],
    "created_utc": "2026-09-29T12:00:00Z", "tool_versions": { "python": "3.14.7", "numpy": "2.5.3", "soundfile": "0.14.0", "libsndfile": "1.2.2" } },
  { "file": "game/assets/audio/vox/napc/base_under_attack_1.ogg", "sha256": "…", "generator": "kokoro-onnx 0.4.7", "model": "kokoro-v1.0.int8.onnx",
    "model_sha256": "…", "voice": "am_michael", "text": "Base under attack.", "language": "en-us", "licence_model": "Apache-2.0",
    "licence_tools": ["MIT", "GPL-3.0-or-later (phonemizer/espeak-ng, tool only)"], "created_utc": "2026-09-29T12:00:00Z", "tool_versions": { "onnxruntime": "1.30.0" } } ] }
```
`created_utc` is copied from the previous file while the asset's `recipe_hash` is unchanged and stamped only when an asset is (re)rendered, so regenerating an unchanged recipe leaves the file byte-identical; for voice lines `text`/`voice`/`model_sha256` are the inputs of the text+voice hash cache. `licence_model` is restricted to `Apache-2.0, MIT, CC0-1.0, CC-BY-4.0 (needs a credits line), procedural`. The file is repository hygiene only: it is excluded from the export and nothing reads it at runtime. Kokoro assets: the model file is `.cache/tts/kokoro-v1.0.int8.onnx` with `voices-v1.0.bin` (already present, git-ignored), the interpreter is the repo-local `.cache/venv` (Python 3.14.7, numpy 2.5.3, soundfile 0.14.0 on libsndfile 1.2.2, kokoro-onnx 0.4.7, onnxruntime 1.30.0 — what `bootstrap.py` reproduces and asserts).

**Runtime index** `game/assets/audio/asset_index.json` (generated with the manifest, shipped; the full manifest with hashes is not):
```json
{ "schema": "meridian.audio.index/1",
  "assets": { "sfx/weapon/small_arms_1": { "f": "sfx/weapon/small_arms_1.mono.ogg", "b": "core", "c": 1, "l": 0, "n": 57330 } },
  "groups": { "sfx/weapon/small_arms": 3 } }
```
(`f` file, `b` bank, `c` channels, `l` loop 0/1, `n` duration in samples; `groups` = number of `_1…_N` variants.)

**Licences and notices** (`game/assets/audio/NOTICE.txt`, generated): Kokoro-82M weights and voices **Apache-2.0** `[spike]` (ship OK, credit); `kokoro-onnx` MIT; `onnxruntime` MIT; `soundfile` BSD-3, `libsndfile` LGPL-2.1 and `libvorbis` BSD (build-time only, not shipped); `espeak-ng`/`phonemizer-fork` (Kokoro G2P) and `piper-tts 1.8.0` are **GPL-3.0+ — build-time only**, never linked or shipped, generated audio is not a derivative; Piper voices: `en_US-joe` CC0 and `en_GB-cori` public domain are usable, `sam` Apache-2.0, `libritts_r`/`alba` need attribution, `hfc_male`/`ryan` (CC BY-NC-SA) and `lessac` (Blizzard-2013) are **forbidden**; macOS `say`: SLA clause F allows System Voices only for personal non-commercial use — **must not ship**, never written under `game/assets/`.


### 7.8b Recipe briefs (what AUD-T2/T3/T4/T5 must synthesise; techniques are the spike's `dsp.py` toolkit)

Layering rule from the spike: **transient (crack) + body + low thump/sub + tail (reverb/echo/debris), then saturation**, mono-summed below 140 Hz, bass exciter for small speakers. `v` = variants. Durations are targets checked by §10.2.

| Family | Recipes → ids | Brief |
|---|---|---|
| Bullet impacts | `bullet_dirt, _concrete, _metal, _flesh, _wood, _water` (v2, 0.2–0.5 s) | dirt: noise 300–3 kHz + 90 Hz thud + grain crackle; concrete: 2–8 kHz crack + stone-chip modal (1.2–4 kHz, tau 20–60 ms); metal: ping modal (1.6/2.9/4.7 kHz, tau 0.05–0.18 s) + tick; flesh: soft 150–900 Hz thud + cloth rustle (no gore); wood: knock modal (280/610/1 100 Hz) + splinters; water: FM plip sweep + hiss |
| Energy / special impacts | `energy_small` 0.35 s, `energy_large` 0.9 s, `rail_hit` 0.8 s, `kinetic_hit` 1.5 s, `emp_hit` 1.2 s | FM zap + sizzle; supersonic crack + modal ring; deep sub thump + crack; thoom + arc crackle + falling whine |
| Explosions | `explosion_small/medium/large/huge` (2.4 / 3.2 / 5 / 7 s, v3), `explosion_water_small/medium/large` | the spike's `explosion_small/large` recipes generalised by a size parameter `k` (sweep-filtered blast, sub thump, secondary pop, debris rain, rumble); huge adds a 28 Hz boom and delayed secondaries; water variants replace the fireball with splash burst + collapsing column (low-passed) |
| Collapses, deaths | `collapse_s1…s4` (3–9 s), `infantry_fall` (v6, 0.5 s), `decoy_pop`, `ship_sink` (5 s), `sub_implode` (3 s), `drone_pop` | spike `building_collapse` scaled by footprint; soft body thud + gear rattle; small pop; groan + bubbling; sub thump + creak |
| Interception | `aps_pop` 0.4 s, `zone_snap` 0.5 s | sharp clang + whoosh; electrical snap |
| Movement loops (seamless, circular) | `engine_wheeled, engine_tracked, engine_tracked_heavy, engine_amphibious, engine_boat_small, engine_boat_large, engine_sub, step_foot, air_jet, air_rotor, air_drone` | spike loops (`engine_*`, `footsteps_loop`, `heli_rotor_loop`); heavy = lower firing rate + more clatter; amphibious = tracked + water hiss layer; jet = filtered noise + turbine whine (whole-cycle snapped); drone = 24-blade buzz |
| Air one-shots | `takeoff, landing` (3 s), `crash_fall` (2.5 s) | spool-up/down with pitch glide; falling whine + sputter |
| Structures | `online_<15 kinds>` (2.0–3.0 s: 1.5 s build-up, accent at `BUILDUP_SECONDS` = 1.5 s, tail ≤ 1.5 s), `sell`, `repair` (loop), `power_down/up` (spike), `defense_offline`, `unit_out_*` (4), `captured`, `salvage` (loop), `hq_deploy`, `hum_*` (5 loops) | the `online_*` one-shots start with alternating hammer/servo build-up sounds (spike `construction_hammer/servo`) and end on the "online" accent: generator spool, refinery clank-chug, barracks door slam, factory heavy doors, dock horn, radar spin-up, airfield beacon beeps, laboratory hum-up, watchtower/turret/AA servo, relay antenna deploy, HQ fanfare (metal + bell), superweapon deep engine start; sell = crank down + coin; repair = ratchet + rising motor; hums = tonal beds locked to whole cycles |
| Economy | `cash` (spike `cash_tick`), `cash_big` | modal coin tick; three-coin flourish |
| Powers | `power_<recon, repair, buff, shield, cloak, smoke, barrage, generic>_<activate, loop, end>` (activate 1.5–2.5 s, loop 4 s, end 1 s), `barrage_warning`, `barrage_impact` | recon: radar sweep + sonar pings; repair: ratchet + rising motor; buff: rising fifth chord + shimmer (pitched to the faction mode in `params`); shield: metallic clunk + low tone; cloak: phasing shimmer; smoke: canister pops + hiss; barrage: klaxon + incoming whistles + thumps |
| Superweapons | 8 × (`charge`, `launch`, `loop`, `impact`, `end` as needed) | per 5.12 table: kinetic thumps, microwave whine/EMP field, mirror glint + beam loop, bunker-buster thud, drone swarm buzz, capsule re-entry + landing thuds + unfold servo, rail barrage + debris hiss, dome hum + collapse |
| Alarms | `sw_siren` (spike loop), `countdown_tick` (spike beep), `countdown_final`, `base_attack` (two-tone ping 0.6 s), `incoming` (3 klaxon bursts 1.5 s), `low_power` (pulse tone) | spike alarm recipes + two new short cues |
| UI | 32 ids of 4.8 (0.05–1 s) | spike `ui_click/hover/error/confirm` as bases; `build_ready` rising arpeggio, `place_ok/fail`, `notify`, `alert` (attention tone), lobby cues, menu transition sweep; all peak ≤ −3 dBTP |
| Ambience beds (stereo loops 16–24 s) | `wind_open, city_hum, coast_waves` (spike), `river_flow, forest, battle_far` | river = band-passed noise + burble modal; forest = leaf rustle + insects; battle_far = distant rumble + crackle at low level |
| Music | 8 × `combat` (24 bars) + 8 × `calm` (12 bars, tempo ≈ 0.6 × combat), `menu.theme` (24 bars @ 100 BPM, generic hero flavour, 4 stems), 2-bar `riser` per faction, `victory`/`defeat` (≈ 6 s) per faction, `match_start` (2.5 s) | spike `music.py` with the 8 faction `Flavour`s of 5.15; risers = noise sweep + tom roll + reversed swell landing on the downbeat; victory = major-leaning resolution in the faction mode with brass/choir, defeat = low descending phrase; all rendered circularly (loops) or with natural tails (stingers) |
| Unit responses | `resp_<faction>_<class>_<type>_<n>` (648) | `[squelch open 40–70 ms][2–3 note motif in the faction scale and timbre, register by class][squelch close 60–120 ms]`; contours: select = ascending pair, move = repeated note + rise, attack = falling triplet, deny = low two-note buzz, special = arpeggio; radio chain per faction (band-pass, bit-crush amount, saturation, hiss floor) from `factions.json.radio` |
| Announcer / barks | `vox/<pack>/<line>` (497) and optional barks | Kokoro TTS → trim → `computer` chain (default pack; pitch −5 %, magnitude-only robotisation 45 %, 14/29 ms echo, presence EQ, compression) or `officer` chain (light radio + compression) or `radio` chain (telephone band, 9-bit crush, tanh clip, squelch, noise bed, band-limited last) → −18 LUFS → mono Vorbis 0.50 `[spike]` |

### 7.9 Validation rules (`validate_audio.py`, also run by `SndEventMap.build` in debug; V-AUD-nn, 28 rules)

| ID | Sev | Rule |
|---|---|---|
| 01 | E | unknown key at any level of any audio file; wrong `schema` |
| 02 | E | `stream`/`group` id not in `audio_manifest.json` or file missing |
| 03 | E | a `mode: "3d"` event resolves to a non-mono file (S1) |
| 04 | E | event `loop` differs from the asset's manifest `loop` |
| 05 | E | `priority` outside 0–100 |
| 06 | E | `limit.group` not declared in `groups` |
| 07 | E | profile references a missing event; `parent` missing/cyclic (depth > 4) |
| 08 | E | `sim_map` pattern with no resolvable id *and* no valid fallback |
| 09 | E | duplicate id (case-insensitive) |
| 10 | E | `flavours` key not a faction code |
| 11 | E | unknown bus name, or bus missing from `mix.json` |
| 12 | E | `power_cues`/`sw_cues` value outside the allowed classes; a bible power/superweapon id absent |
| 13 | E | a balance `pres_snd_profile` id, or a `sim_map.weapon_override` value, not in `keys(events) ∪ keys(profiles)` (the first half is data_balance V-REF-02) |
| 14 | E | a unit/structure resolves to a `generic` profile although its archetype has a specific one |
| 15 | E | a weapon archetype (TAXONOMY §10) has no `snd.weapon.*` event |
| 16 | W | `unit_size_m ≤ 0` (E) or `max_distance_m < 3·unit_size_m` (W) |
| 17 | E | `volume_db` outside [−24, +3] or `cull_below_db` outside [−80, −10] |
| 18 | W | event category vs asset loudness class mismatch (e.g. a UI asset used by a weapon) |
| 19 | E | announcer line without `computer`-pack file, or a faction pack missing any line file |
| 20 | E | announcer `variants` > files present |
| 21 | E | music track: stem missing, stem lengths differ from `length_samples`, `beat_count ≠ bars·bar_beats`, `mono_stems` not mono |
| 22 | E | `sets`/`transitions` reference a missing track/stinger/filler |
| 23 | E | response class×type×variant clip missing for any faction |
| 24 | E/W | asset budget cap exceeded (E: > 2 500 files or > 110 MB or a bank > 45 MB) / orphan asset not referenced by any data (W) |
| 25 | E | `mix.engine.mix_rate` / `output_latency_ms` differ from `game/project.godot` `audio/driver/*` |
| 26 | E | `game/assets/audio/PROVENANCE.json` (QA schema, 7.8) lacks an entry for any OGG of `asset_index.json`, has an entry without file, a wrong `sha256`, or a `licence_model` outside `Apache-2.0, MIT, CC0-1.0, CC-BY-4.0, procedural` (QA gate DA-27 re-checks it) |
| 27 | W | `catalog/structures.py:BUILDUP_S × 20` differs from `SndUnits.BUILDUP_SECONDS × 20` or from `buildup_ticks` in `game/data/balance/economy.json` (when present) |
| 28 | E | an announcer line without a non-empty caption `text` (captions are an accessibility requirement, A-07 / QA-XR-29) |

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

Audio lives entirely in the presentation layer (`audio/` is not in the deterministic module list of lint L003), so it may use floats, wall-clock and an engine RNG — **provided nothing flows back into the sim**.

| Rule | Audio compliance |
|---|---|
| DR-1 ints only in sim | N/A to audio. Audio reads ints from events/entities and converts to floats locally; it never writes to any sim object. |
| DR-2 no engine randomness in sim | Audio never touches `SimRng`. Its own `RandomNumberGenerator` instances (pool, announcer, responses) are seeded from `SndMatchConfig.match_seed ^ constant`, so a replay/test with the same seed and inputs makes the same variant/jitter choices. |
| DR-3 no wall clock in sim | Audio uses `Time.get_ticks_msec()` (throttles, cooldowns, ramps) through the injectable clock; not in the sim, not hashed. |
| DR-8/9 no Nodes/globals in sim | Audio is Node-based and outside `sim/`; it holds only borrowed references for the duration of a call and stores ints (entity ids, def indices). Two `SimWorld`s can run side by side with one `Snd` attached to at most one of them. |
| DR-10 data hash | `game/data/audio/**` and `game/assets/audio/**` are **not** part of `data_hash` and not exchanged in the lobby: two clients with different audio files still simulate identically. `SndDataStore.data_version` (FNV-1a over canonical JSON) is logged for bug reports only. |
| DR-12 events output-only | Audio only reads the batch the app obtained from `world.events.take()`; the sim never reads audio state, camera, settings or selection. |
| DR-13 checksum | **Nothing from audio enters `SimWorld.checksum()`** — there is no audio field to add. Adding one would be a bug. |
| DR-15 smoothing floats | Loop/path voices chase sim positions with float exponential smoothing; presentation only, never fed back. |

**Guarantees and how they are tested (§10.4).** (1) *Non-interference*: a headless AI-vs-AI scenario produces the identical checksum chain with the bridge attached and detached. (2) *Layering*: lint L005 already forbids `sim/core/data/map/net/ai` from mentioning `Snd*`; `test_snd_no_sim_dependency` additionally greps `game/src/audio` for `SimRng`, `world.rng`, and any assignment to a `world.` field. (3) *Reproducible decisions*: for an identical event batch sequence (sim_core makes `events.digest()` reproducible across runs and platforms), camera path, injected clock and seed, `SndSimBridge.decision_log` is byte-identical between runs (regression test for the bridge; the audible result additionally depends on the engine mixer). (4) *Local-only differences are expected*: different clients hear different fog-filtered sounds and may run different quality presets; none of it is synchronised. (5) *Catch-up*: when lockstep runs many ticks in one frame, dropping old cosmetic events is a local presentation decision.

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

### 9.1 Main-thread cost per rendered frame (60 fps, 16.6 ms budget; Apple M-class numbers, ×2 assumed for mid-range x86)

| Component | Typical | Worst (capped) | Reasoning |
|---|---:|---:|---|
| `SndSimBridge.process` reject path | 0.3 ms | 1.0 ms | ≈ 120 records/frame in a heavy fight (`WEAPON_FIRED`/`DAMAGE`/`PROJECTILE_*` at ≈ 20 ticks/s ÷ 60 fps) × ~3 µs (packed-int reads, route lookup, cell test, integer distance); hard bound `MAX_EVENTS_SCANNED = 512` → 1.5 ms |
| accepted starts (`play_def`) | 0.15 ms | 1.0 ms | ≈ 4 starts/frame typical × 30–40 µs `[spike]` (29–32 µs/call incl. node reconfiguration); cap 24/frame = 0.96 ms |
| `SndVoicePool._process` (ramps, reaping) | 0.02 ms | 0.05 ms | iterates busy slots only (≤ 48) |
| `SndLoopManager` positions | 0.05 ms | 0.10 ms | ≤ 16 loops × ~3 µs (`[spike]` 37 µs for 64 transform updates) |
| `SndLoopManager` scan (4 Hz) | 0.12 ms (amortised) | 0.6 ms in the scan frame | 160 candidates × ~3 µs, spread over 4 frames |
| music director + meter + announcer + ambience + countdown | 0.03 ms | 0.1 ms | O(4 stems), O(queue ≤ 4), 2 Hz terrain histogram |
| **Total** | **≈ 0.5 ms** | **≈ 3 ms hard bound** | governor keeps the worst case bounded (below) |

**Governor** (`SndSimBridge`): if `process()` took > 2.0 ms in ≥ 3 of the last 10 frames → level 1 (`max_starts` 12, scan 256 events, skip priority < 30); after another 10 bad frames → level 2 (`max_starts` 6, scan 128, skip priority < 45); back to level 0 after 60 frames under 1 ms. Announcer/alert/warning events are always processed first and are never skipped. Level and counters are visible in `SndStats`.

### 9.2 Audio-thread / process CPU (mixing runs on the engine's audio thread, not the main thread)

`[spike]` (Apple M5 Max, Dummy driver, one core = 100 %): mono OGG 3D voice 0.16–0.24 %/voice with the default 5 kHz distance filter, 0.17 % without; 64 simultaneous looping moving voices 10–15 %; stereo OGG 0.46–0.72 %/voice offline; 16/128/256 voices = 4/21/41 %. Design load: 48 3D voices ≈ 8–11 % + music 4 stems ≈ 2–3 % (+ up to 8 during a 4 s cross-fade) + ≤ 4 ambience beds (wind + one water bed + forest + far battle) ≈ 2 % + announcer/responses/UI ≈ 1 % → **≈ 13–17 % of one core (assume ≤ 35 % on a mid-range x86 core)**. Per-voice cost is why beds are started only when audible (5.11), why loops are budgeted (16), and why weapon low-pass cutoffs are 9–12 kHz.

### 9.3 Disk, download and resident-memory budget

Formats: Ogg Vorbis only (5.13). Loudness/peaks per §5.1. Baseline content (files / MB at the stated quality; sizes extrapolated from the spike's measured KB/s and per-file sizes):

| Category | Files | Avg | Total |
|---|---:|---:|---:|
| Weapon fire (27 archetypes, base variants) | 66 | 18 KB | 1.2 MB |
| Weapon faction flavours (10 families × 8 × 2) | 160 | 15 KB | 2.4 MB |
| Projectile flight / whistles | 8 | 20 KB | 0.16 MB |
| Impacts, explosions, deaths, collapses, intercept, EMP | 60 | 37 KB | 2.2 MB |
| Movement loops (engines, steps, air) + air one-shots | 20 | 40 KB | 0.8 MB |
| Structures, economy, hums | 55 | 26 KB | 1.4 MB |
| Support powers (7 classes + generic) | 26 | 25 KB | 0.65 MB |
| Superweapons (8 × ~5 assets) | 40 | 35 KB | 1.4 MB |
| Alarms + UI | 40 | 9 KB | 0.35 MB |
| Ambience beds (stereo, 16–24 s) | 6 | 350 KB | 2.1 MB |
| **SFX subtotal** | **≈ 481** | | **≈ 12.7 MB** |
| Music stems: 8 × combat (24 bars, ≈ 44 s) + 8 × calm (12 bars, ≈ 37 s) + menu; 4 stems each, bass mono, quality 0.45 | 68 | | ≈ 8 × 2.9 + 8 × 2.1 + 3.5 = **43.5 MB** |
| Stingers (8 × riser/victory/defeat + match-start) | 25 | 90 KB | 2.3 MB |
| Announcer (computer 49 + 8 × 56 files) | 497 | 14.5 KB | 7.2 MB |
| Unit-response bleeps (8 × 81) | 648 | 4.5 KB | 2.9 MB |
| **Baseline total** | **≈ 1 720** | | **≈ 69 MB** |
| Phase B optional barks (648) | +648 | 7 KB | +4.5 MB |
| **Hard caps** (V-AUD-24) | 2 500 files | | **110 MB total, 45 MB per bank** |

Text artefacts on top (repository only except the first): `asset_index.json` ≈ 0.19 MB (shipped), `audio_manifest.json` ≈ 0.7 MB and `PROVENANCE.json` ≈ 0.6 MB (not shipped). Levers if the cap is approached: music quality 0.45 → 0.55 (−15 %), combat 24 → 20 bars, calm 12 → 10 bars, drop flavour variants of the 4 least-heard families, announcer variants 2 → 1. Resident compressed set of one match (banks `core` ≈ 8.2 MB, `fx_*` for 8 factions ≈ 2.4 MB, `vox_computer` 0.75 + `vox_<local>` 0.86, `resp_<local>` 0.36, `mus_<local>` ≈ 5.3, `mus_common` ≈ 3.6, `amb` 2.1) ≈ **24 MB**, plus ~4 MB decoder state for ≤ 64 playing streams; GDScript-side state < 1 MB. **Loading**: banks via `ResourceLoader.load_threaded_request` while the loading screen runs (`[spike]` 116 files in 69–256 ms; a match's ≈ 700 files < 1 s); cold import of the full tree ≈ 15–20 s once (`[probe]` 600 files = 4.7 s).

### 9.4 Build cost (not runtime)
`[spike]`: 38 SFX recipes = 17–20 s idle (58–62 s under contention), music 3–4 s render per track, Kokoro int8 RTF 1.55 (52 lines = 105 s), Piper RTF 0.03. Scaled baseline: ≈ 470 SFX ≈ 4 min single-threaded (≈ 1.5 min with `--jobs 4`; assets are independent), 17 music tracks ≈ 1.5 min, 648 bleeps ≈ 1 min, voice ≈ 15–20 min at RTF 1.55 (cached by text+voice hash; Piper iteration mode 30 s). A no-op rebuild (all recipe hashes unchanged) takes seconds.

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

Runner facts (qa_tooling §2): `tools/gd test snd` runs `game/tests/audio/test_snd_*.gd` headless under the Dummy audio driver; tests are `func test_*(t: TestCtx)` on `RefCounted` classes, may `await` (default per-test limit 30 s, raise with `t.set_timeout`), and any engine error fails the test unless declared with `t.expect_errors(n)`; nodes are added under `(Engine.get_main_loop() as SceneTree).root` after `await process_frame`. The long engine-capture tests are the `test_slow_*` methods of `test_snd_capture.gd` (≈ 25 s total): they skip themselves unless the environment variable `SND_SLOW=1` is set, so a plain `tools/gd test` stays fast. A fake clock (`SndConfig.clock`) makes every time-dependent rule deterministic.

### 10.1 Unit tests (fast, no audio device needed)

| Test | Case → expected |
|---|---|
| `test_snd_event_map::real_data_loads` | `events.json` parses with 0 errors; `event_ids().size() ≥ 200`, `profile_ids().size() ≥ 77`; every `keys(events) ∪ keys(profiles)` is unique |
| `…::validation_catches_typos` | file with `"prioritee"` and a missing stream → ≥ 2 errors, `build()` returns false (spike behaviour); wrong `schema` → error |
| `…::flavours` | `pick_stream(rng, &"napc")` draws only from napc variants; unknown flavour → default list; 1 000 draws over ≥ 2 variants never repeat the previous pick |
| `…::sim_map` | `resolve(&"weapon_fire", {archetype: "nonexistent"}) == &"snd.weapon.small_arms"`; `resolve(&"explosion", {size: "huge"}) == &"snd.explosion.huge"` |
| `test_snd_voice_pool::attenuation` | def U = 22 m, max 170 m: `model_db(22) = 0`; `model_db(88) = −12.04 ± 0.05`; `model_db(5) = +3.0` (clamp); `attenuation_db(85) = −17.76 ± 0.05` (−11.74 model, −6.02 window) |
| `…::fuzz` | 20 000 random `play()` calls (seed 99, positions ±300 m): `active_count ≤ budget`, `def.active_count ≤ max_instances`, group counts ≤ limit at every step, 0 script errors, < 1.5 s |
| `…::reserve` | fill 42 slots with a fixture event (priority 28, no group, `max_instances` 100) so 6 remain: the next priority-28 start is not admitted by a *free* slot (it may only steal a quieter/older voice); `snd.explosion.huge` (85) is admitted to a free slot |
| `…::handles` | after a slot is reused `is_active(old_handle) == false`; new handle differs in generation; `INVALID == 0` never returned for a started voice |
| `…::intervals` | fake clock: two plays 20 ms apart with `min_interval_ms = 35` → 1 start, `cull_interval == 1`; 40 ms apart → 2 starts |
| `…::loop_ramp` | loop start has `ramp_from_db = −60`, reaches `vol_db` after `fade_in_ms ± 1 frame`; loops never call `play(offset ≠ 0)` on 3D players |
| `…::audio_space` | zoom scale 2.0 about focus (0,0,0): world (60,1.5,0) → (30,1.5,0); scale 0.7: (70,·,0) → (100,·,0); direction unchanged |
| `test_snd_bridge::units` | event x = 1024, y = 2048 → world (3.0, 1.5, 6.0); (x >> 10, y >> 10) = (1, 2) |
| `…::fog` | enemy `WEAPON_FIRED` in an invisible cell → `cull_fog == 1`, no start; visible cell → start; own/ally in invisible cell → start; MUFFLED event within 300 m → start with −9 dB; beyond → drop; omniscient → all start |
| `…::per_source` | two `WEAPON_FIRED` from entity 7 within 40 ms → 1 start; from entities 7 and 8 → 2 |
| `…::rank_cap` | 100 candidate events in one `process()` → exactly 24 starts, equal to the 24 highest `priority + 0.5·est_db` (ties by lower event index) |
| `…::routes` | every code in `SndEventCodes` has a route; an unknown type (0x7E) → ignored without error or warning |
| `…::dedupe` | a `PROJECTILE_IMPACT` and an `EXPLOSION` with the same tick and (x >> 9, y >> 9) in one batch → exactly one explosion voice (either order); different cells → two |
| `…::owner_fallback` | `WEAPON_FIRED` whose shooter id no longer resolves → treated as ENEMY (fog decides) and flavoured from the weapon id (`weapon.han.x` → `han`); a shared weapon falls back to the default variants |
| `…::state_table` | `STATE` values: EMP → `snd.emp.hit`; SHUTDOWN of an own structure → `snd.struct.defense_offline` + line `systems_disabled`; POWERED 0 of an own defence → `defense_offline` + `defenses_offline` once per 30 s; SELLING → `snd.struct.sell`; REPAIRING 1/0 → loop start/stop |
| `…::damage_filter` | `DAMAGE` with splash flag → silent; bullet vs INFANTRY → FLESH, vs MEDIUM_ARMOR → METAL, vs BUILDING_HEAVY → CONCRETE; two events on one target within 60 ms → 1 voice; removed target → METAL |
| `…::warning` | `SW_WARNING` (hostile, `f` = 200 ticks) with an own unit inside `extent + 3 cells` → siren handle valid, `sw_launch_detected` queued, ticks scheduled at T−5…T−1, final tone at T−0; no own unit inside → line only; the unit leaves the zone → siren fades within 0.5 s + 300 ms; `SW_CANCELLED` → siren fading, `sw_cancelled` queued; Trident (`f` = 120) → siren 6 s; own/allied owner → `sw_launched`, no siren; hostile `POWER_USED` with `warning_t > 0` → `sw_incoming_strike` for the affected only |
| `…::catch_up` | a batch of 2 000 records (ages 0–40 ticks) → at most 512 combat records classified (the newest), every announcer/alert/strategic/match record still processed; `process()` < 6 ms on CI (soft) |
| `…::impact_tables` | splash radius 0/819/1536/2560/3000 units → TINY/SMALL/MEDIUM/LARGE/HUGE (0.8 cell = 819 → SMALL, 820 → MEDIUM); ArmorClass → material table exhaustive; `mix.terrain.material` has exactly 15 entries (`MapTerrain` ids 0–14), each a valid material |
| `test_snd_announcer::queue` | the worked example of 5.9 with a fake clock: `construction_complete` → pre-empted by `base_under_attack` (starts 540 ms) → `unit_ready` starts at 2390 ms; the second `base_under_attack` at 2.5 s is dropped (12 s cooldown); `low_power` (75) at 2.6 s pre-empts the playing `unit_ready` (45); the queue never exceeds 4; an item older than `expire_ms` is skipped |
| `…::packs` | line missing in `napc` pack falls back to `computer`; missing everywhere → false and one warning; `ANN_OFF` → false |
| `test_snd_music::state_machine` | with a stubbed interactive playback: request while pending ignored; two requests within 8 s → 1 switch; urgent while CALM → clip 3; completion detected when `get_current_clip_index()` maps to the target and the fade elapsed; a request to the *current* state while pending is never forwarded (P3 guard) |
| `…::stems` | combat intensity 0.5: drums t = 0.5 → −3.01 dB, bass t = 1 → 0 dB, pads 0 dB, lead t = 0 → −80 dB floor; `set_sync_stream_volume` is called only when abs(Δ) ≥ 0.05 dB |
| `test_snd_meter::thresholds` | constant input 2.5 heat/s: `intensity_raw` at 10 s = 0.386 (< 0.40) and at 20 s = 0.439; `wants_combat` turns true between 12 s and 14 s (crossing at 11.5 s + 0.6 s smoothing + 1 s hold); input 0 for 18 s with `min_combat_s` satisfied → CALM; input 20/s → raw 0.99 within 1 s |
| `test_snd_loops::ambience_targets` | fake summary grid, open temperate map: no water/forest → only `wind_open` (0 dB) started; f_forest 0.10 → `forest` −13.4 ± 0.1 dB started; f_water 0.05 → `coast_waves` −14.0, `river_flow` −12.5; f_water 0.25 → `coast_waves` 0.0; coast family with f_water 0 → `coast_waves` −9.0 and no `river_flow`; urban → `city_hum` 0, `wind_open` −9; desert → `wind_open` +2 dB with pitch ×1.06; `far_heat` 4 → `battle_far` −26; a bed whose target stays below −46 dB for 3 s is stopped and not decoded |
| `test_snd_response::rules` | two SELECT within 200 ms → 1 play; same class+type at 500 ms → dropped, at 800 ms → plays; 100 draws never repeat immediately or within the last 2; 4 identical requests within 3 s → every second plays; `UV_VOICE` without a bark falls back to the bleep |
| `test_snd_settings` | slider 100 → 1.0 (0 dB), 50 → 0.25 (−12.04 dB), 0 → mute; `[audio]` + `[access]` round trip with the qa.md key names (`mute_unfocused`, `captions`, `announcer_tts`); unknown keys ignored |
| `test_snd_announcer::tts` | fake `DisplayServer` shim (`SndConfig.tts_speak/stop/is_speaking` callables): with `announcer_tts` on the voice file is not played, `tts_speak` receives the caption and `Music` is faded −6 dB and back; with no voices available the setting stays off and one `audio_warning` is emitted |
| `test_snd_bus` | `SndBus.setup` twice yields the same layout; `verify()` empty; index(`Announcer`) > index(`Music`), index(`SfxHeavy`) > index(`Music`); sidechain names and thresholds match `mix.json`; limiter last on Master with ceiling −1.0 |
| `test_snd_coverage::real_data` | with real `GameData`: `SndEventMap.missing(data)` is empty (QA gate DA-23); every entity def (unit, structure, summon) has a profile, every weapon a fire event; generic profiles used = 0; explicit-vs-derived counts printed; every weapon archetype has an event; every power id ∈ `power_cues`, every superweapon id ∈ `sw_cues` |
| `test_snd_coverage::arch_table` | `SndUnits.ARCH_TABLE` has 27 rows in TAXONOMY §10 order; with the data layer present every name equals `DefWeaponArch.id` without the `warch.` prefix and every damage type name equals `DefDamageTable.damage_ids[DefWeaponArch.dtype]`; every row has a `snd.weapon.*` event (`tank_cannon` → its three variants) |
| `test_snd_event_codes::match_sim` | each mirrored constant equals the `SimEvent` constant of the same name (names the sim has not defined yet are reported, a mismatch fails) |
| `test_snd_determinism::source_is_read_only` | no `SimRng`, `world.rng`, or `world.<field> =` in `game/src/audio/**` |

### 10.2 Asset QA (`qa_assets.py`, run by `build_all.py check`; thresholds are per category and stored in `catalog/qa_thresholds.py`)

Every decoded asset: sample rate 44 100, declared channel count (3D-event assets **mono**), length delta OGG vs source = 0 samples, no NaN, |DC| < 0.005, first/last sample of one-shots |x₀| ≤ 0.02 and |x_end| ≤ 0.003 (fade), no clipped samples.

| Class | Length | True peak | Loudness | Other |
|---|---|---|---|---|
| small arms / MG / autocannon | 0.4–1.6 s | ≤ −1.4 dBTP | informational | attack (10→90 % of envelope) ≤ 6 ms; centroid ≥ 700 Hz; 200 Hz–2 kHz power share ≥ 15 % (spike rifle: 1018 Hz, t40 293 ms after fix) |
| cannons, missiles, artillery, rail, EMP | 1.0–4.5 s | ≤ −1.4 | informational | attack ≤ 10 ms; 200 Hz–2 kHz share ≥ 4 % (bass-exciter check: spike tank 7.0 %, howitzer 4.8 %) |
| explosions, collapses | 1.5–8 s | ≤ −1.4 | informational | attack ≤ 12 ms; 200 Hz–2 kHz share ≥ 5 %; LF (< 140 Hz) L/R correlation ≥ 0.93 if stereo |
| loops | 2–24 s | ≤ −4 dBTP | within ±1 LU of the catalog target | source `seam_score` ≤ 4.0 and decoded ≤ 4.0; decoded length delta 0 |
| ui / alarms | 0.05–4 s | ≤ −3 dBTP | within the class window (§5.1) | — |
| announcer lines | 0.3–6 s | ≤ −1.5 dBTP | −18.0 ± 1.5 LUFS-I | mono; codec SNR ≥ 18 dB; > 6 kHz share ≤ 8 % (computer/officer) or ≤ 1 % (radio chain) |
| unit responses | 0.15–0.7 s | ≤ −2.0 dBTP | −20 ± 2 | mono; squelch present (spectral flux in first 70 ms) |
| music stems / tracks | = `length_samples` | mix ≤ −2.0 dBTP | combat −14.4 ± 1, calm −16.1 ± 1 (sum of stems) | source seam ≤ 4.0, decoded seam ≤ 4.0, spectral loop continuity ≤ 3.0; tempo estimate within 2 % (or exactly half/double, `[spike]` estimator ambiguity); ≥ 75 % of pitched energy inside the scale (spike 80–90 %); per-stem `STEM_LUFS` balance ±1.5 LU |
| ambience beds | 16–24 s | ≤ −9 dBTP | target ±1 LU | seam ≤ 4.0; no rectangular block in the spectrogram (visual sheet check) |

**Distinctiveness gate.** For every weapon family with flavours: feature vector = [log centroid, log t20, log t40, 4 band shares, crest] per variant; pairwise normalised Euclidean distance over the 8 factions; the closest pair is recorded in the manifest on the first accepted build and a later build must not reduce it by > 20 %. Same for the 8 music mixes (tempo, centroid, mode-histogram distance) and the 8 response palettes. This is the objective proxy for "you can hear who is shooting"; the ABX test in 10.6 is the real one.

**Reproducibility gate** (`build_all.py check --verify`): re-render to a temp dir; same platform + library versions → all `pcm_sha256` and `sha256` equal; otherwise metrics within tolerance (§7.8).

### 10.3 Engine-capture integration tests (`test_snd_capture.gd`, methods `test_slow_*`, Dummy driver, `AudioEffectCapture` on `Master`, real-time paced)

| Test | Expected |
|---|---|
| `test_slow_attenuation` | a looping mono tone event (U = 22) at 22, 44, 88 m: level steps −6.0 ± 1.0 dB per doubling, each within ±1.5 dB of `attenuation_db` (spike: ≤ 0.8 dB) |
| `test_slow_pan` | source at +x with listener yaw 0: R − L ≥ 5 dB at node strength 1.0 (project 0.5; spike 6 dB); yaw π/2 flips the side |
| `test_slow_focus_and_zoom` | moving the focus 50 m toward the source raises the level by the model difference ± 1.5 dB; camera height 110 m (s = 2.0) raises a 90 m source by 7.6 ± 1.5 dB vs height 55 m |
| `test_slow_duck_announcer` | Music tone + real `vox/computer/base_under_attack` line: steady-state Music drop **−6…−10 dB**, recovery within 1 dB by 2.5 s after the line ends; unit-response playback causes < 0.5 dB drop |
| `test_slow_duck_heavy` | `snd.explosion.huge` on `SfxHeavy`: Music drop −2…−5 dB, Ambience −3…−6 dB `[tune]` |
| `test_slow_loop_seams` | each music stem and each `loop` SFX crossing its loop point through the real mixer: step at the seam ≤ 2.5× the p99 step (spike: 0.52×) |
| `test_slow_interactive` | stem-tone streams (bpm 120): switch requested at 0.84 s → new tone audible from 2.00 ± 0.06 s; minimum envelope during the transition ≥ 50 % of steady (no dropout); per-stem volume ramp visible after the switch; **canary**: reversing a pending switch still produces the dropout of P3 (test records the result; if the engine fixes it the test reports "engine improved" and the guard stays) |
| `test_slow_click_guard` | 3D loop start with ramp: max sample step ≤ 1.5× natural at 8 random phases; `stop()` ≤ 1.5× |
| `test_slow_master_limiter` | 128 simultaneous `snd.explosion.huge` (pool-capped): capture true peak ≤ −0.9 dBFS |
| `test_slow_no_camera` | `attach_world` on a viewport without a current camera → false + `audio_warning`; after `make_current` → true and the tone is audible |
| `test_slow_reference_mixes` | scripted scenarios A–D of 5.1 measured with the numpy meter in `qa_capture.py` against the stated windows (nightly, not per commit) |

### 10.4 Scenario and determinism tests
- `test_snd_determinism::non_interference`: a 3-minute headless AI-vs-AI match (fixed seed) run twice, **with** a `SndTestRig` (bridge + real pool + Dummy driver) fed by `world.events.take()` every frame and **without** audio: identical `checksum_log` chains (every 20 ticks) — audio cannot change the sim; the two audio runs also produce equal `decision_log` hashes with the fake clock.
- `test_snd_determinism::catch_up`: 300 steps advanced before one `take()` → bridge stays within the 3 ms hard bound (governor level ≤ 1), announcer events intact.
- `test_snd_match_flow::full_flow`: `begin_match` → loading progress reaches 1.0 → CALM music → scripted `BASE_UNDER_ATTACK` → COMBAT within one bar + riser → `MATCH_END` → `end_match(VICTORY)` → stinger + line; no `Log.error`, no orphan nodes after `shutdown`.
- `test_snd_match_flow::headless_boot`: `Snd.setup()` with the Dummy driver and no camera returns true, logs one `audio_warning`, never crashes; export smoke flag `--check-audio` emits `MERIDIAN_AUDIO events=<n> banks=<n> errors=0` through `Log.info("audio", …)` (L006: no direct `print`).
- Debian: `tools/gd linux test snd` (container has no audio device → Godot falls back to Dummy).

### 10.5 Visual tests
`tools/gd shot res://src/audio/debug/snd_monitor.tscn out.png --frames 285` (the spike's monitor scene, ported): image must show non-empty spectrum, master peak history, ≥ 10 lit voice cells, four stem bars, bus peaks — inspected with the image reader. `SndGallery` screenshot at 1280×720 for layout. Spectrogram contact sheets (`--sheets`) are inspected for every new asset family (e.g. no hard-edged block in an ambience bed, no HF leakage in radio voices).

### 10.6 Human review gate (mandatory before audio is called done)
Tool: `SndGallery` (lists every event/profile/announcer line/response/track/state; controls: distance slider, faction flavour, zoom scale, music intensity/state buttons, A/B compare with the spike-era build, rating buttons writing `user://audio_review.csv`). Protocol: two reviewers rate each family 1–5 on punch, clarity, distinctiveness, fatigue and mix fit (any family < 3 → redesign ticket); **faction ABX**: identify the shooting faction from 20 random weapon samples (target ≥ 50 % vs 12.5 % chance); **intelligibility**: 20 random announcer lines transcribed by both reviewers (target 100 %, pronunciation list updated for misses); loop-point listen at three positions per track; ducking feel in scenario B/D; unit-response fatigue after 10 minutes of orders. Results go to `docs/audio/REVIEW.md` (written by AUD-G9).

### 10.7 CI wiring
Per commit: `python3 tools/py/audio/validate_audio.py --strict`, `tools/gd check`, `tools/gd test snd` (unit + scenarios; QA's tier T0 already runs every `game/tests/**/test_*.gd`, and `tools/py/qa/tiers.json` decides where the validator sits — audio asks for it next to the balance validators). Nightly: `SND_SLOW=1 tools/gd test snd_capture`, `build_all.py check --verify`, `tools/gd linux test snd`, reference mixes. Release: full review gate and manifest freeze (`audio_vN` tag).

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Two independent tracks after this spec: **T** (Python: assets + data + validators) and **G** (GDScript runtime). The G track develops against tiny synthetic fixture assets (`game/tests/fixtures/audio/`, generated by `tools/py/audio/make_fixtures.py`, < 200 KB) and a hand-written mini `events.json`, so it never waits for the full libraries.

| ID | Task | Files owned | Est. lines | Depends on | Acceptance |
|---|---|---|---:|---|---|
| **AUD-T1** | Toolkit + pipeline core | `tools/py/audio/{bootstrap,build_all,dsp,oggtools,analyze,manifest,provenance,make_fixtures}.py`, `catalog/{__init__,qa_thresholds}.py`, `README.md`, `requirements*.txt`, `qa/test_dsp.py` | ~2 000 py | — | `bootstrap` verifies/creates the venv on macOS + Linux; `manifest.py` + `provenance.py` write `audio_manifest.json`, `asset_index.json` and `PROVENANCE.json` (one entry per OGG, sorted, byte-stable on re-run); `build_all.py sfx --only rifle_shot` reproduces the spike metrics (±0.2 LU); two runs byte-identical; biquad vs scipy ≤ 1e-6; `check --verify` green; incremental no-op rebuild < 5 s |
| **AUD-T2** | SFX library A: weapons (27 archetypes, 10 flavour families × 8), projectiles, impacts, explosions, deaths, collapses | `catalog/{weapons,impacts}.py`, `sfx/{weapons,projectiles,impacts,explosions}.py` | ~2 500 py | T1 | all `snd.weapon.*`, `snd.proj.*`, `snd.impact.*`, `snd.explosion.*`, `snd.collapse.*`, `snd.death.*` assets exist; §10.2 thresholds + distinctiveness gate pass; sheets inspected |
| **AUD-T3** | SFX library B: structures, economy, powers, superweapons, alarms, UI, loops, ambience beds | `catalog/{structures,powers,superweapons,ui_alarms,movement,ambience}.py`, `sfx/{structures,powers,superweapons,ui,alarms,movement,ambience}.py` | ~2 500 py | T1 | all remaining ids of §4.8; loop seams ≤ 4; LUFS targets; 8 superweapon sequences exist |
| **AUD-T4** | Music generator | `music/{flavours,arrange,stingers,mixdown,verify}.py`, `catalog/music.py` | ~1 600 py | T1 | 8 × (calm, combat) + menu + 25 stingers; §10.2 music row; total ≤ 46 MB; spectrogram/flavour sheets |
| **AUD-T5** | Voice pipeline + responses | `voice/{lines,tts_kokoro,tts_piper,chains,responses,cache}.py`, `catalog/voice.py`, `tools/py/audio/requirements-voice.txt` | ~2 200 py | T1; Kokoro model in `.cache/tts` | 497 announcer files + 648 bleeps meet §10.2; numpy `chains.py` replaces ffmpeg (or ffmpeg ≥ 6 documented); pronunciation list; audition sheet for voice choice; NOTICE.txt |
| **AUD-T6** | Data authoring + validators | `validate_audio.py`, `build_all.py events` scaffolder, `game/data/audio/{manifest,mix,events,music,announcer,responses,factions}.json` | ~1 500 py + ~6 000 JSON lines | T2–T5 ids (can start from the catalog) | V-AUD-01…28 pass `--strict`; events ≥ 220, profiles ≥ 77; coverage counters printed |
| **AUD-G1** | Runtime data core | `snd_config, snd_data_store, snd_mix_config, snd_bus, snd_bus_fader, snd_event_def, snd_event_map, snd_profile_def, snd_asset_index, snd_stats` + `test_snd_event_map, test_snd_bus` | ~1 700 GD | fixtures; `Log` (core) | `test_snd_event_map::*`, `test_snd_bus`; loads real `events.json` (when T6 lands); `--check-audio` output |
| **AUD-G2** | Voice pool, listener, scheduler | `snd_voice_pool, snd_listener, snd_scheduler, snd_units` + `test_snd_voice_pool` | ~1 300 GD | G1 | all `test_snd_voice_pool::*`; `test_slow_attenuation/pan/focus_and_zoom/click_guard/no_camera` |
| **AUD-G3** | Sim bridge | `snd_world_reader, snd_event_codes, snd_sound_bank, snd_sim_bridge, snd_match_config` + `test_snd_bridge, test_snd_coverage, test_snd_event_codes` | ~2 200 GD | G1, G2; sim_core `SimEvent` records (a real `SimWorld` through `SimTestKit`, or hand-built batches) | `test_snd_bridge::*`, coverage with real `GameData` (`SndEventMap.missing(data)` empty), governor levels |
| **AUD-G4** | Loops, meter, countdown, ambience | `snd_loop_manager, snd_combat_meter, snd_countdown, snd_ambience` + `test_snd_loops, test_snd_meter` | ~1 500 GD | G2, G3 | 5.6/5.7/5.11/5.12 behaviours; meter and ambience numbers of 10.1 |
| **AUD-G5** | Music runtime | `snd_music_library, snd_music_director` + `test_snd_music` | ~1 000 GD | G1; T4 (or fixture stems) | state machine + stems tests; `test_slow_interactive`, `test_slow_loop_seams` |
| **AUD-G6** | Announcer + unit responses | `snd_announcer, snd_unit_response` + `test_snd_announcer, test_snd_response` | ~900 GD | G1; T5 (or fixtures) | queue/pack/response rules, TTS mode (`test_snd_announcer::tts`); `test_slow_duck_announcer` |
| **AUD-G7** | Manager, settings, wiring | `snd_manager, snd_settings` + `test_snd_settings, test_snd_match_flow` | ~700 GD | G1–G6; app/view/ui call points (§3.11) | end-to-end match flow; settings round trip |
| **AUD-G8** | Debug and QA tooling | `debug/{snd_monitor_panel, snd_gallery, snd_test_rig}` (+ `.tscn`), `tools/py/audio/qa/{qa_capture,sheets}.py`, `test_snd_capture, test_snd_determinism` | ~1 400 GD + ~500 py | G7 | monitor screenshot; gallery usable; determinism scenario green; reference-mix scripts |
| **AUD-G9** | Integration and tuning | data-only edits to `game/data/audio/*.json` (+ `docs/audio/REVIEW.md`) | ~0 code | everything; ears | reference mixes A–D within windows; review gate §10.6 passed; Windows/Debian device check (R5) |

**Milestones.** *M1 vertical slice* (one faction, hearable skirmish): T1, T2 (small_arms, tank_cannon_medium, explosion small/medium/large, bullet impacts), T4 (`napc` only), T5 (computer pack, 12 lines), T6 subset, G1, G2, G3, G6, G7. *M2 content complete*: T2–T5 complete, G4, G5, G8. *M3 quality gate*: G9 (mix, review, device checks). Tasks within a track are sequential by the dependency column; T and G tracks run in parallel.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / question | Recommended resolution |
|---|---|---|
| R1 | **Nothing has been listened to** (`[spike]` caveat): the objective proxies can pass while the sound is mediocre | Mandatory human gate (10.6) with `SndGallery`; keep all `[tune]` values in JSON; ship the QA thresholds as regression protection only; schedule the review before M3, not after |
| R2 | Announcer quality and pronunciation ("Perun", "Helios", "Superweapon" unverified); voice-per-faction mapping is a placeholder | Pronunciation table with phoneme overrides in `voice/lines.py`; audition sheet (3 candidate Kokoro voices per faction × 3 lines) for ear selection; Piper CC0 voices as a 30 s iteration mode; keep the `computer` pack as the safe default |
| R3 | Licences (Kokoro Apache-2.0 fine; GPL tools are build-time only; `say` forbidden) | Allow-list of voices/engines in `voice/lines.py`, CI grep that no file under `game/assets/audio` came from `say`/non-allowed voices (manifest records engine+voice), NOTICE.txt shown in credits (ui) |
| R4 | ≈ 70 MB of committed binary; every regeneration rewrites history | Hard caps (V-AUD-24), incremental builds, regenerate music/voice rarely, tag `audio_vN`; ask the reconcilers whether Git LFS is acceptable (not an audio decision) |
| R5 | Linux/Windows audio drivers were **not measured** (PulseAudio/ALSA, WASAPI shared mode at 48 kHz, device change) | `output_latency_ms` in data (default 30); QA checklist on real Debian 12 (PulseAudio and ALSA) and Windows 10/11: crackle at 30 ms, first-sound latency, unplug/replug, 48 kHz devices; `SndSettings.output_device`; fall back to Dummy without crashing |
| R6 | Low-end CPUs / few cores: 48 voices + music + sim | Quality presets (3D 24/40/48, loops 8/12/16), governor, no muted decoding (beds started on demand), weapon LPF 9–12 kHz; measure on the lowest supported machine in G9 |
| R7 | `AudioStreamInteractive` hazards (P3 dropout, P4 stuck fade) or a regression in a later Godot | Rules of 5.8; canary test `test_slow_interactive`; `SndMusicDirector` keeps a private backend interface so a two-player manual cross-fade can replace the interactive stream without API change |
| R8 | 3D start click (P8) | Loops start at 0 with a ramp; assets start at silence; test `test_slow_click_guard` |
| R9 | Sibling specs still disagree on event codes and layouts (combat 200–229, economy 300–410, abilities 23x vs the sim_core master catalogue) and on a few `GameData` accessors | Audio consumes **only** the master catalogue (6.2, mapping in 6.4); two adapter files (`SndWorldReader`, `SndEventCodes`) plus `SndSoundBank.bake` absorb any change; `test_snd_event_codes::match_sim` fails loudly at the seam |
| R10 | Numpy/libvorbis results differ across platforms → different bytes | Committed OGGs are the truth; `--verify` compares metrics off-platform; never regenerate on CI to ship |
| R11 | Event floods / lockstep catch-up | Caps (512 scan, 24 starts), age-based dropping, governor, adaptive levels |
| R12 | Audio leaking hidden enemy information | Fog policies (5.5), MUFFLED only for loud events within 300 m, decoy/camouflage-aware loops; `…::fog` test |
| R13 | Replay fast-forward / observer | `set_time_scale` gate (priority ≥ 80 above 2×), omniscient reader, announcer/responses off for observers |
| R14 | Music repetition (24-bar combat ≈ 44 s per faction) | Intensity layering + hot/cold entries now; Phase 2 in data terms: A/B lead and drum variants alternated each loop pass (`stems` entries may become objects with `variants`), 3 subfaction lead stems per faction; needs no API change |
| R15 | Import/edit-time cost of ~1 800 files | ≈ 15–20 s cold import (`[probe]`); `tools/gd import` is already serialised by a lock |
| R16 | ARCHITECTURE says tools/py = stdlib + numpy + Pillow; the encoder needs `soundfile` (libvorbis) | Request amendment (§13-18): `tools/py/audio` build-time dependency, venv bootstrap; alternatives fail (`[spike]` Homebrew ffmpeg has no libvorbis; its native encoder is stereo-only, ignores bitrate, pads samples) |
| R17 | No audio device (CI, servers) | Godot falls back to Dummy; `setup()` must succeed and warn once; sound systems cost ≈ 0 (pool reduced to 25 % when `DisplayServer` is not headless and the driver is Dummy) |
| R18 | The view camera's real ranges may change (render.md: height 34-84 m, wide view 110 m; pitch 46-61°) | `mix.camera` values are data (`ref_height_m`, `zoom_scale_min/max`); `Snd.set_camera(focus, basis, height)` is the only coupling; yaw is extracted from the basis, so no angle-sign convention is shared |
| R19 | `WEAPON_FIRED` carries no owner and no hitscan result; the shooter may be removed before audio runs | Flavour comes from the weapon id, owner from the entity (ENEMY when gone, fog decides); request packing `owner+1` into `f` (§13-1); hitscan hits are voiced from `DAMAGE`, misses stay silent in v1 |
| R20 | `PROJECTILE_IMPACT` and `EXPLOSION` may both be emitted for one impact (double boom) | Bridge dedupe ring keyed by (tick, x>>9, y>>9); `test_snd_bridge::dedupe`; ask sim_core/combat to state which one is authoritative for explosive impacts (§13-2) |
| R21 | `SW_LAUNCHED` timing (activation vs end of warning) is not stated in the master catalogue | Siren is bounded by `exec_tick = SW_WARNING.tick + warning_ticks` and `SW_CANCELLED`, so either timing works; launch cue is played at `SW_LAUNCHED` whenever it arrives |
| R22 | The master catalogue has no events for rearm, drone launch/dock, capture progress, crash phases, amphibious medium changes or collector docking | Those cues are dropped in v1 (assets not built); they can be added as `STATE`/`ABILITY` sub-cases without schema changes when the owning domains emit them |
| R23 | The table behind `weapon_def_idx` is defined differently by combat.md (`DefWeapon`, `DefProjectile`) and data_balance.md ("there is no `DefWeapon`": `DefWeaponSlot` + `DefWeaponArch`); nothing yet says which index the events carry or how to read a weapon's id and archetype | `SndSoundBank.bake` is the only reader and needs just `weapon_id(i)` and `weapon_arch(i)` (§13-6); until they exist every weapon would fall back to `snd.weapon.small_arms`, so `test_snd_coverage` fails loudly. Fallback if the accessors never arrive: derive the archetype from the shooter's role archetype (TAXONOMY §9 lists the weapon archetypes per role; right for single-weapon units, approximate for multi-weapon ones) |
| Q1 | Should the 24 subfactions have their own announcer/music? | No in v1 (shared parent packs); per-roster overrides already in `factions.json` |
| Q2 | Voice barks in v1? | Phase B, default `UV_SYNTH`; assets and code path are ready, voices need ear selection first |
| Q3 | Are enemy support-power activations audible? | Only when the activation cell is visible (`hidden` policy); the *warning* cues are global/affected-only per the bible |
| Q4 | Enable `SfxHeavy` ducking at launch? | Yes, with the mild values of 4.1; verify by ear (target Music −2…−5 dB) and drop to `enabled: false` in `mix.json` if it pumps |
| Q5 | Announcer in replays/observer mode? | Off; hearing is omniscient, responses off |
| Q6 | Who shows third-party credits? | Audio generates `NOTICE.txt`; ui shows it in the credits screen |
| Q7 | Mono-audio / spatial-off accessibility switch? | Later (a Master `AudioEffectPanner` bypass); not a v1 requirement |
| Q8 | Future occlusion, whiz-by, doppler, per-map reverb? | Data hooks exist (`doppler`, `propagation`, `fog`); implement after the M3 review if the ears ask for it |
| Q9 | Dedicated ambience beds per biome (desert dust, arctic howl, jungle insects)? | Not in v1: `MapData.biome` only offsets the `wind_open` bed (gain, pitch) and the `forest` bed through `mix.ambience.biome[]`; three extra beds (≈ 1 MB) are a data-only addition after the M3 review |

---


## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

Most of what audio needs is already in **sim_core's master catalogue and query API** (events with owners and positions, `entity/relation/cell_visible/entity_visible/query_radius`, `SimFlags`, `SimPlayer` power/superweapon state, `GameData.def_ids/def_kinds`); the list below is only what is *missing* or must be *confirmed*.

**sim_core**
1. `WEAPON_FIRED` (0x11): pack the shooter's owner into the record so fog and flavour survive a shooter that is removed before audio runs — `f = muzzle_idx | ((owner + 1) << 8)` (0 = none). Audio falls back to the entity lookup and the weapon id without it.
2. Confirm the explosive-impact convention: either `PROJECTILE_IMPACT` (0x13) **or** `EXPLOSION` (0x14) is authoritative for a splash impact, or both are emitted with the same radius (audio dedupes by tick and cell either way, R20). Confirm `SW_WARNING` is emitted at activation and `SW_LAUNCHED` at the end of the warning (R21), and that `PROJECTILE_IMPACT.result = 4` (intercepted) is emitted for intercepted projectiles.
3. Reserve/keep the master codes of 6.2 stable; register the reconciled versions of the sibling proposals per 6.4 (combat 200–229, economy 300–410, abilities 23x are not emitted).
4. `SimEvent` constants must exist by the names used in 6.2 (`SimEvent.WEAPON_FIRED`, `DAMAGE`, `DIED`, `STATE`, `ST_EMP`…, `SPAWN_*`, `REM_*`, `DIE_*`, `SimFlags.F_MOVING` …) so `test_snd_event_codes::match_sim` can compare by name.

**combat**
5. `DefDamageTable.damage_ids` must contain the TAXONOMY names `bullet, ap, he, thermal, rail, kinetic, emp` (combat §4.1 still lists `DT_EXPLOSIVE`/`DT_BEAM`; audio resolves kinds by name, so only the names matter).
6. Reconcile combat's `DefWeapon` (combat.md) with data's `DefWeaponSlot` / `DefWeaponArch` (data_balance §4: "there is no `DefWeapon`") and give `GameData` four neutral accessors over the table that `weapon_def_idx` of the events indexes: `weapon_count() -> int`, `weapon_id(i) -> String` (e.g. `weapon.napc.guardian_cannon`, faction segment included), `weapon_arch(i) -> int` (TAXONOMY `WeaponArch`, frozen), `def_weapons(def_idx) -> PackedInt32Array` (a unit's or structure's weapon indices, used to give each `tank_cannon` its light/medium/heavy voice); plus `GameData.death_has_chain(def_idx) -> bool` (combat `DefDeath.warhead >= 0`). Audio derives damage type, projectile class and warhead kind from the archetype (5.4.2) and reads splash radii from the events, so no projectile or warhead registry is needed.

**data**
7. Role archetype access: `DefUnit` has no archetype field in data_balance §4.2, yet 5.4.7 needs it. Add `DefUnit.archetype: String` (the bare id of the unit sheet's `archetype`, e.g. `mbt_t2`, `service.collector`, which `V-ABL-05` already guarantees equals `unit_assignments`) — or, equivalently, compile `pres_snd_profile = "snd.profile." + archetype` at load when a sheet gives none. Audio accepts either and derives when the field is empty or names an unknown profile (32 archetypes; service units `svc_engineer|collector|mcv|landing_transport`; summons/drones/decoys `summon_drone|summon_capsule|decoy`). Fields audio reads and asks to keep stable: `DefBase.id/kind/tags`, `DefUnit.speed/armor_class/home_layer/weapons`, `DefStructure.fp_w/fp_h/armor_class/superweapon`, `DefFaction.code`, `DefPower.id/warning_t/radius`, `DefSuperweapon.id/duration_t/recharge_t/warning_t/params` (`params.length_cells` for the Helios line, optional).
8. `V-REF-02` reads the registry as `keys(events) ∪ keys(profiles)` of `game/data/audio/events.json` (not a flat id list) and accepts the `snd.` grammar of 4.8; `game/data/audio/**` is excluded from `data_hash` and included by the export `include_filter` (`data/*/*.json`).

**vision**
9. `SimFogApi.cell_visible(pid, cx, cy)` and `entity_visible(pid, e)` must be O(1) and camouflage-aware (`world.cell_visible/entity_visible` wrappers of sim_core §3.4.4). Optional: `decoy_identified(pid, e)` so identified decoys stop playing the mimicked engine loop.

**map**
10. Nothing new: audio reads exactly what terrain_movement.md 3.3 publishes — `MapData.family` (0 open, 1 urban, 2 coast/river), `MapData.biome` (0 temperate, 1 desert, 2 arctic, 3 tropical), `MapData.w/h`, `MapData.terrain` (`PackedByteArray`, the 15 `MapTerrain` ids, row-major, read-only), via `world.map`. Please keep the 15 ids and their order stable (audio maps them by position in `mix.terrain.material`; a new terrain type needs a new entry and fails `…::impact_tables` until added). Note for the reconcilers: render.md 13-9 lists `biome` as 0 temperate, 1 arid, 2 arctic, 3 urban, a different enumeration from terrain_movement.md; audio follows the map generator (the owner of the field) and stores only the integer.

**view**
11. Keep the game `Camera3D` (`ViewCamera.camera`) current in the viewport that contains the node handed to `Snd.attach_world(world_root)` (the `ViewWorld` node, or a node inside the `SubViewport` when the world lives in one); keep `ViewCamera.current_focus()`, `camera.global_basis` (or `listener_transform().basis`) and `current_height()` published as in render.md 3.3 — the app forwards them to `Snd.set_camera(focus, basis, height)` each frame, so the audio side has no dependency on any `View*` class and no shared angle-sign convention (`listener_transform()` alone is not enough: it lacks the height and its origin is not specified). Never create `AudioStreamPlayer3D`s directly. The structure build-up animation stays driven by the sim's `BUILDUP` state (`st_until − st_t0` = 30 ticks): the `online_*` one-shots are authored to that 1.5 s. Audio does not use the view's interpolation (`capture_prev`) or its projectile mirrors.

**ui**
12. Call `Snd.ui(&"snd.ui.*")` for widget feedback; `Snd.unit_selected(def_idx, is_structure, count)` on committed selection changes (primary = highest tier, ties lowest def index); `Snd.unit_ordered(order, def_idx)` / `Snd.order_denied(...)`; build the audio options panel from `SndSettings`; subscribe to `announcement_started` for the caption toast (shown when `Snd.settings().captions`; the text log, screen-edge alert and minimap ping of A-07 are ui's and come from the sim events, not from audio); show `NOTICE.txt` in credits. Gameplay announcements are event-driven — the UI must **not** also announce `on_hold`, `canceled`, build-ready, etc.

**app**
13. Register `[autoload] Snd="*res://src/audio/snd_manager.gd"`; `Snd.attach_world(world_root)` once the view has built the world; per frame, after `view.frame(delta, alpha)`: `Snd.set_camera(cam.current_focus(), cam.camera.global_basis, cam.current_height())`, then with the frame's single `var batch := world.events.take()` (or a non-destructive read; audio only reads the array it is handed) `Snd.on_events(world, batch, alpha)` and `Snd.on_frame(...)` (3.2); `begin_match(SndMatchConfig)` during loading with `load_progress()`/`is_match_ready()` polling; `end_match(result)`; `set_mode` on scene changes; persist `[audio]` settings; set `world.events.watch_mask` only if `mix.hearing.contact_ping` is enabled; CLI flag `--check-audio` that makes `Snd` emit `MERIDIAN_AUDIO events=<n> banks=<n> errors=<n>` through `Log.info` (export smoke test, same idea as `--check-data`).
14. `project.godot`: `audio/driver/mix_rate=44100`, `audio/driver/output_latency=30`, `audio/general/3d_panning_strength=0.5`; leave `audio/general/default_playback_type` at its default (stream); do not add a `default_bus_layout.tres` (the layout is built in code). Export: `include_filter` must cover `assets/audio/asset_index.json`; `assets/audio/audio_manifest.json` and `assets/audio/PROVENANCE.json` may be excluded (`NOTICE.txt` stays: the credits screen shows it).

**net**
15. Lobby/chat/join/leave/ready/countdown sounds via `Snd.ui(...)`; replay speed via `Snd.set_time_scale(x)`; the sim's `PLAYER_ELIMINATED(reason DROP)` already yields `player_disconnected`.

**core**
16. `Log.debug/info/warn/error(tag: String, msg: String)`; constants `SimConfig.TPS`, `Fp.CELL` (audio duplicates them in `SndConfig` and asserts equality in a test).

**qa_tooling / architecture (AMENDMENTS)**
17. `tools/gd test` must pass the environment through to the Godot process (`SND_SLOW=1` enables the capture tests); add `tools/gd audio-check` (runs `validate_audio.py --strict` and `build_all.py check`).
18. **Amend ARCHITECTURE §2 `tools/py`**: `tools/py/audio/` may depend on `soundfile` (BSD-3, bundles libsndfile + libvorbis) at build time, inside the repo-local `.cache/venv` that already exists (qa.md 5.11 lists soundfile 0.14.0, numpy and kokoro-onnx as allowed build-time components; `bootstrap.py` reuses it and never deletes it); `kokoro-onnx`/`onnxruntime` only for voice regeneration; committed OGG assets are canonical and nothing in that stack is shipped.
19. **Record audio rules in `docs/AMENDMENTS.md`**: (a) a current `Camera3D` must exist in the viewport of the `AudioStreamPlayer3D`s; (b) positional SFX assets are mono; (c) bus layout with hidden ducking-key buses `Announcer` and `SfxHeavy`; (d) every volume change is ramped at ≥ 60 Hz; (e) `max_distance` is a fade window, not a cutoff; (f) audio data lives in `game/data/audio` and is presentation-only; (g) `Snd` autoload.

**balance**
20. Do not author per-unit sound ids: rely on the derivation of 5.4.7. A new role archetype or weapon archetype requires a matching `snd.profile.<archetype>` / `snd.weapon.<archetype>` (validator V-AUD-14/15 fails otherwise). Unique subfaction units use their archetype's profile unless a distinct sound is deliberately requested from audio.

**qa**
21. `[QA-XR-29]` accepted as specified in qa.md: `game/assets/audio/PROVENANCE.json` in the 7.8 schema for every OGG (7.8 of this spec), the licence allow-list of 5.11 (V-AUD-26), captions for every announcer line (V-AUD-28), and `SndEventMap.missing(data: GameData = null) -> PackedStringArray` as the DA-23 hook. Audio's unit tests run headless under `--audio-driver Dummy` (X-23) and live in `game/tests/audio/` (recursive discovery, QA-XR-30 (1)); the `SND_SLOW=1` capture tests (≈ 25 s) belong in a nightly tier, not in T0.
22. The `settings.cfg` key names of QA-XR-13 are adopted (`[audio] master, music, sfx, voice, ui, mute_unfocused, captions`; `[access] announcer_tts`); audio adds `ambience, announcer, unit_voices, music_mode, dynamic_range, quality, output_device` under `[audio]`. Manual checklist items R-12 (device hot-swap, no-device start) and X-23 (44.1 kHz mix vs 48 kHz device) are the verification of R5 and need a human on real Windows and Debian machines.
