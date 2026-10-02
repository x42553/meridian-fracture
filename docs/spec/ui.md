# MERIDIAN FRACTURE — UI/UX, Input, Screens & App Shell (`docs/spec/ui.md`)

> **Domain architect:** UI/UX, input, screens, app shell. **Modules owned:** `game/src/ui/*` (class prefix `Ui*`) and `game/src/app/*` (prefix `App*`).
> **Binding parent:** `docs/ARCHITECTURE.md` (wins on conflict unless `docs/AMENDMENTS.md` says otherwise). Sibling specs read while writing this one: `sim_core.md` **v2.1** (file of 2026-09-29 16:57: the MASTER command catalog §6.1 — 45 ops with the `SimCmd` int-array builders —, the MASTER event registry §6.2 with the domain blocks movement 100-129, combat 200-229, abilities 230-259, economy 300-499, the command blocks unit orders 1-12 / combat 40-47 / abilities 100-105 / economy 120-141 / net 250, the `SimFogApi` ghost list and the `SimWorld` / `SimPlayer` / `SimEntity` read surface — **this spec follows v2.1**), `net.md` (session/lobby/replay API), `data_balance.md` (`GameData`, `DefRoster`, `DefBrowser`, `DefPlayerView`), `economy.md` (production/power/strategic queries, superweapon framework), `abilities.md` + `abilities_catalog.md` (ability commands, which units have user-activated abilities), `combat.md` (attack/stance semantics, `EV_ATTACK_ALERT`, `EV_DEATH`), `ai.md` (`AiWorldView`), `render.md` (the view: camera, picking, interaction overlays, minimap source, icons, quality keys), `audio.md` (the `Snd` facade: UI cues, unit responses, the event-driven announcer, captions, `SndSettings`), `qa.md` + `qa_tooling.md`, `terrain_movement.md` (map generator API: `MapGenParams`, `MapGenerator.validate_params`, `MapGenJob`, `MapData`; file of 17:13), `art_direction.md` (the visual bible, file of 16:28: `style.json` with the UI tokens, type scale, chrome recipes, faction skins, player colours, emblems and the icon rig, read through `ViewStyle`). `audio.md` and `render.md` were written against the *v1* sim_core catalog (hex event codes, records `[type, tick, a … h]`); section 6.2.1 carries a v1 → v2 alias column so the reconcilers can sweep them in one pass.
> **Engine:** Godot 4.7.2 stable, GDScript only, stock Control/Theme/CanvasItem (no addons).
> **Evidence base.** (a) The UI spike `prototypes/ui` (6,094 lines of typed GDScript, screenshots inspected: HUD x6 variants, menu x3, skirmish x3, LAN x2, Mobile and gl_compatibility variants). The spike's `REPORT.md` does **not exist on disk** at authoring time; its findings were taken from the task brief and re-checked against the spike source and screenshots. Numbers marked *(spike)* come from it. (b) Four new engine experiments run for this spec on the real 4.7.2 binary (E1-E4 below; scratch project, nothing written to `game/`). (c) Arithmetic done with stdlib Python: WCAG contrast ratios of the palette, a colour-vision-deficiency (CVD) simulation of the team palettes (Machado 2009 matrices) and CIEDE2000 distances in Lab (the metric of QA A-01; the implementation reproduces the Sharma-Wu-Dalal reference pairs), and an independent re-implementation of the `SimCmd` layouts for the golden command arrays. Numbers marked *(measured)* / *(computed)* come from (b)/(c).
> **Notation.** `ASSUMPTION(domain)` marks something this spec needs from another domain that is not written yet. They are all collected as numbered requests `[XR-n]` in section 13. "Logical px" = pixels after `Window.content_scale_factor` (the unit every layout number in this document uses). `sim units` = `Fp.CELL = 1024` per cell.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**One-paragraph architecture.** Meridian Fracture's front end is a set of code-built `Control` trees over one vector-drawn `Theme` (chamfered `StyleBox`es, procedural glyphs and emblems, three vendored OFL fonts, 3D-model portraits baked at runtime; **zero external art**). Four autoloads (`AppSettings`, `AppNet`, `AppState`, `AppScenes`) form the app shell; every screen is a `UiScreen` control created by `AppScenes` into a persistent layer stack. The UI reaches the rest of the game **only through four small port interfaces** — `UiSimPort` (read the simulation), `UiViewPort` (camera, picking, ghosts, minimap sources), `UiNetPort` (submit commands) and `UiAudioPort` — each with a production adapter and a fixture/null adapter, so the whole front end can be built, tested and screenshotted before sim, view or audio exist (the same trick `net` uses with `NetSimAdapterFake`). Player intent flows **mouse/keyboard → `UiInputController` (gestures) → `UiSelection` + `UiContextResolver` (what would this click do?) → `UiCommandBus` (builds int-array commands with the sim's own `SimCmd` builders through `UiCmdCodec`, gives instant feedback) → `UiNetPort` → `NetSession.submit_command`**; the simulation is never touched directly. Skirmish and LAN share **one** lobby screen and **one** start-match pipeline (`NetSession` in `Role.LOCAL` vs `HOST`/`CLIENT`, then `AppMatchJob` → loading screen → game screen).

### 1.1 What this module owns

* **App shell (`game/src/app/*`):** the four autoloads; boot flow and splash; CLI/user-arg parsing; scene/screen manager with transitions, modal stack and loading screen host; settings model, schema, persistence (`user://settings.cfg`) and application to the engine (display, audio buses, input map, render quality); logging (the `Log` sink and a `Logger` subclass feeding the core ring; the engine log file is the log), crash / fatal reporting and the `.session` sentinel; match-setup glue (`NetSessionOptions` builder, world-builder job, AI factory wiring, event fan-out); the headless "boot straight into a match" harness.
* **Design system (the code side of `art_direction.md` §5.12):** colour tokens (`UiPalette`, constants asserted equal to `style.ui.tokens`), `UiMetrics`, `UiSkin` x 8 factions + neutral built by `UiSkin.from_style`, the colour-vision-safe semantic set, fonts, `UiStyleBox` recipes driven by `style.ui.chrome`, the glyph library (55 glyphs) and the data-driven emblem interpreter `UiEmblem`, `UiTheme` with type variations, layout/scale math, motion rules, accessibility helpers, text/number formatting, procedural cursors (incl. the 8 edge-scroll cursors). **The values — tokens, type scale, skins, chrome numbers, player colours, emblem op lists, relation and health colours — belong to art's `style.json` and reach the UI only through `ViewStyle`; the UI owns the code that draws them.**
* **Widget kit:** icon buttons, build cards + clock-wipe sweeps, credit ticker, power bar, queue strip, ribbons, list rows, tab bars, option rows, key-bind capture button, dialogs/toasts/tooltips, vignette.
* **Screens:** splash, main menu (live 3D backdrop), lobby (skirmish / LAN host / LAN client — one class), LAN browser, loading, game (HUD), end-of-match, replay browser + replay viewer HUD, Field Manual, options, credits, fatal-error screen, and every modal dialog.
* **In-game HUD:** sidebar (radar/minimap, credits + power, tabs, build cards, queue strip), bottom panel (control-group badges, selection panel with portraits, command bar, ability bar), top strip, power/superweapon dock, alert ribbons, message/notification feed, chat, stall/pause/net/desync overlays, observer + replay controls, camera pad and Select menu (mouse-only viability), a small 2D world overlay (order markers, power / superweapon targeting previews, off-screen alert arrows) and the driving of the view's own world visuals (selection rings, health bars, rally / order lines, placement ghost, range rings).
* **Input and command translation:** gesture state machine, keymap (defaults, contexts, rebinding), cursor states, selection model and control groups, camera bookmarks, picking through the view's picker, contextual right-click resolution, armed command modes, placement and power-targeting flows, `UiCommandBus` and its codec, command feedback.
* **Persistent user data written by the UI/app** (locations per `qa.md` §5.12): `user://settings.cfg` (+ `.tmp`, `.bak`, `.bad-<utc>`), `user://.session`, `user://logs/crash/*`, `user://screenshots/*`; the app's log sink writes into the engine log `user://logs/godot.log`. (Replays and desync packages belong to `net`, icon and model caches to the view.)
* **Text and UI data files:** `game/data/text/*.json`, `game/data/ui/*.json` (schemas in section 7).

### 1.2 What this module does NOT own

| Not owned | Owner | Interface used by the UI |
|---|---|---|
| Simulation state, command validation/execution, command op codes and field layouts, event codes, fog/vision rules | sim | `UiSimPort` (reads), `UiCmdCodec` (the **only** UI file that names command ops; it calls the `SimCmd` builders of the `sim_core.md` v2.1 §6.1 catalog, mapping in 6.1), `UiEv` (event codes and field indices of the MASTER registry and the combat / abilities / economy blocks, 6.2) |
| Camera rig, terrain/unit rendering, ghosts, fog texture, model building (`ViewModelBuilder`), team-colour shader, VFX, selection *effects* | view | `UiViewPort` |
| Sound playback, buses, the event-driven announcer, unit-response voices, captions, the mapping of audio settings onto buses | audio | `UiAudioPort` over the `Snd` facade (`audio.md` §3.1: `ui(&"snd.ui.*")`, `unit_selected` / `unit_ordered` / `order_denied`, `announcement_started`, `SndSettings`); UI cue ids in 6.3.1 |
| Lockstep, lobby protocol, discovery, replay files, desync detection, `NetSession` | net | `NetSession` signals and methods exactly as in `net.md` §3; `UiNetPort` for commands |
| `GameData`, `DefRoster`, `DefBrowser`, `DefLayer3`, stat math | data | called directly (`GameData` is a plain object; the UI never reads JSON) |
| Map generation (`MapGenerator`, `MapGenParams`, `MapGenJob`), `MapData`, start positions, the minimap bake | map / view | `MapGenParams.from_config / min_size / recommended_size / slots_for`, `MapGenerator.validate_params`, `MapGenJob` (preview generation on its worker thread) and `MapData.start_cells / fair_slot_order` (`terrain_movement.md` §3.3, §3.7) through the UI's own `UiMapPreview` (5.14.5); the preview *image* is baked by the view (`UiViewPort.bake_map_preview`, `ViewMinimapSource.bake`, requests `[XR-31]`, `[XR-19]`); map names are the UI's `UiMapNames` |
| AI levels/styles and their display keys | ai | `AiFactory.level_names()` etc. (`ai.md` §3) |
| `project.godot`, export presets, `tools/gd`, test runner, lint | build / qa | requests `[XR-40]..[XR-44]` |
| Network transport specifics, firewall behaviour | net | UI text only (keys `net.help.*`, `net.err.*` of `net.md` §5.13) |
| Gamepad support | — | not required (menus stay keyboard-navigable) |
| Internet play, accounts, save/load games, mods | — | out of scope (see `net.md` §1.2) |

### 1.3 Decisions reconcilers must know

1. **Ports and adapters.** `UiSimPort`, `UiViewPort`, `UiNetPort`, `UiAudioPort` are the only seams. Everything else in `ui/` and `app/` is testable without a `SimWorld`, a 3D scene or a socket. Fixture adapters (`UiSimPortFixture`, `UiViewPortFixture`) live in `src/ui/` (not in `tests/`) because `--fixture` screenshot runs need them at runtime.
2. **`UiCommandBus` is the single path UI → sim**, and `ui_cmd_codec.gd` is the single file that names command ops and calls the sim's `SimCmd` builders (they return the `PackedInt32Array [op, fields…, ids…]` that `NetSession.submit_command` carries; the pid is stamped by net, never in the payload). **The UI adopts the `sim_core.md` v2.1 §6.1 MASTER catalog** (45 ops): decimal domain blocks (unit orders 1-12, combat 40-47, abilities 100-105, economy 120-141, `RESIGN` 250), queue mode `QM_APPEND` for Shift, `BUILD_PLACE` in whole cells with a rotation field, `USE_POWER` addressed by power index, `TRAIN` / `TRAIN_CANCEL` by producer id + queue index, per-queue holds (`BUILD_HOLD`, `QUEUE_HOLD`, `RESEARCH_HOLD`), and the ops v1 lacked (`SET_PRIMARY`, `UNDEPLOY_HQ`, `SET_AUTOCAST`, `HOLD`). The AI uses the same builders. If the reconcilers change the catalog, one file (plus `UiEv`) changes.
3. **Skirmish setup and LAN lobby are one screen** (`UiScreenLobby`) over `NetLobby`/`NetLobbyState`; skirmish is a `Role.LOCAL` session held in `Phase.LOBBY` (request `[XR-20]`: `NetSession.local_lobby(opts)`).
4. **`AppMatchJob` is a composite `NetWorldJob`**: sim world build → view build (which bakes the local roster's icons and prewarms materials), with the audio banks loading on threads alongside, all time-sliced or asynchronous, so `LOAD_DONE` means "ready to render and hear frame 1" and the loading screen shows one honest progress bar per player.
5. **Scaling rule (spike, verified at 0.75/1.0/1.5):** `display/window/stretch/mode = disabled` and `Window.content_scale_factor = clamp(window_px_height / 1080, 0.75, 2.0) * ui_scale`. `game/project.godot` currently says `canvas_items` + `expand`; change requested `[XR-40]`.
6. **Input plumbing rules are non-negotiable** (spike lab, 30 observed results): HUD root `MOUSE_FILTER_IGNORE`; STOP panels set `mouse_force_pass_scroll_events = false`; every HUD control `focus_mode = FOCUS_NONE`; gestures *start* in `_unhandled_input`, *continue* in `_input`, are polled in `_process` and cancelled on focus loss; keyboard actions are matched with `exact_match = true`.
7. **Key layout:** unit orders are plain letters (A G S X D H ...), sidebar build cards are **`Alt` + the 4x3 grid keys** (Q W E R / A S D F / Z X C V), camera is arrows + `Q`/`E`, groups are `1`-`0`. The spike's card hotkeys (plain `QWERASDFZXCV`) collided with orders and are dropped. Full table in 5.6.
8. **Platform modifier caveat (macOS):** Godot's macOS backend reports `Ctrl`+click as a *right* click (engine source behaviour, **not verifiable from this environment**, so treated as a known risk). Mouse-gesture modifiers therefore have per-OS defaults (5.5.6) and are rebindable.
9. **No sockets before the user asks.** The main menu never starts LAN discovery; the first LAN screen entry shows the one-time explainer (`net.md` §5.13) *before* `start_browse()`/`listen()`.
10. **The minimap is always available.** The bible is silent on radar-gated minimaps (Radar unlocks T2/powers, nothing more), so the minimap works from tick 0. Low power only tints the sweep.
11. **3D interaction visuals belong to the view** (`render.md` §3.7/§5.10): selection rings and brackets, health bars, status marks, rally and order lines, the placement ghost with per-cell colours and the build-radius ring, range rings, strategic-warning zones, remembered-structure ghosts and floating "+$" text are instanced quads / ribbons drawn by `ViewSelection`, `ViewHealthBars`, `ViewLines`, `ViewPlacementGhost`, `ViewRangeRings`, `ViewWarnings`, `ViewGhosts`, `ViewFloatText`; the UI drives them through `UiViewPort` (3.2.2) and never draws them. The UI keeps a small 2D `UiWorldOverlay` for what is screen-space by nature: order-issue markers, power / superweapon targeting previews, off-screen alert arrows, plus the selection rectangle. The spike's 2D overlay code becomes the fixture adapter's implementation of the same contract.
12. **Autoload safety (measured E1):** under `--script` test runners the autoload nodes exist during `_initialize` but their `_ready()` has **not** run yet, and a script that names an autoload identifier cannot be compiled before the autoloads are registered. Consequence: all app logic lives in `class_name` `RefCounted` classes (`AppSettingsStore`, `AppFlow`, `AppLogger`...); the four autoload scripts are thin, have **no `class_name`**, and initialise lazily in `_init`/first use — never in `_ready`.
13. **The UI never reads the bible/balance JSON.** All content strings and stats come from `GameData`/`DefBrowser`/`DefRoster` (`data_balance.md` §13-15). Display names are labels, never lookup keys (bible rule).
14. **Determinism:** nothing in `ui/`/`app/` enters the sim except integer command arrays built by `UiCommandBus` through `SimCmd` (DR-14). World-to-sim conversion is the single float→int step (5.8.2).
15. **The visual language is `art_direction.md`; colour-vision support is data-driven and verified numerically** (section 5.19). Every colour, type size, chrome number, faction skin, player colour and emblem comes from `style.json` through `ViewStyle` (art R-17..R-22); the UI keeps **two** colour modes, `normal` and `cvd` (art's single colour-vision-safe team set, designed for protan, deutan and tritan at once, plus a CVD-safe semantic set for OK / WARN / DANGER / POWER, which art does not define and this spec does). The UI's own CIEDE2000 + Machado 2009 evidence (5.19.3) shows that art's *default* team set misses QA A-01 under simulation (authored minimum 8.5 / 9.0 / 8.7 against ≥ 12) while its CVD set meets it (13.5 or better), and carries a replacement proposal for the default set (`[XR-49]`, risk R28).
16. **Announcer ownership (audio.md wins).** The audio module's `SndSimBridge` turns sim events into announcer lines, alarms and cues by itself (`audio.md` §6.2, §3.11: "the UI must **not** also announce `on_hold`, `canceled`, build-ready, etc."). The UI notifier therefore produces **visual** notices only (ribbons, log lines, minimap pings, edge arrows, jump targets) from the same event batch, and mirrors spoken lines as text through the `announcement_started` caption signal (`audio/captions`), skipping the lines a notice already covers (5.13.1). The UI plays only *UI-initiated* cues (`snd.ui.*`, 6.3.1) and the unit responses (`unit_selected` / `unit_ordered` / `order_denied`). Audio settings are `SndSettings`; the app persists them in `settings.cfg` and hands them to `Snd.apply_settings` (5.18.5).
17. **Def indices are per kind (sim_core v2 §4.1).** `SimEntity.def_idx` indexes `data.units` (UNIT, WRECK), `data.structures`, `data.zones` or `data.neutrals` according to `kind`, and commands carry the same per-kind indices (`TRAIN def` = unit index, `BUILD_START def` = structure index, `RESEARCH def` = research index) — the `GameData` table indices, so `UiSimPort.table_idx` / `sim_def` are identity seams. A bare number never says which table it indexes, hence every port method that takes a def also takes its kind (`def_flags(kind, def_idx)`, `ids_of_def(kind, def_idx, out)`).
18. **Sim events are consumed as delivered by the master catalog.** `AppEvents` drains `world.events.take()` once per rendered frame (`sim_core.md` §5.7) and hands the same read-only `PackedInt32Array` of 10-int records `[type, tick, x, y, a, b, c, d, e, f]` (positions in slots 2-3) to the view (`ViewWorld.frame(dt, alpha, records)`), audio (`Snd.on_events`) and UI; the UI never retains the array and never asks for a second copy. There is no `watch_mask` (v1 idea withdrawn by sim_core v2 §5.7 and v2.1 §6.4-F): fog filtering of events is the consumer's job (5.13.1).

### 1.4 Spike carry-over (what is adopted verbatim, with the spike's numbers)

| Pattern (spike class) | Adopted as | Spike evidence |
|---|---|---|
| `UiStyleBox` — scripted `StyleBox._draw` with `RenderingServer.canvas_item_add_polygon/polyline` (cut corners, vertical gradient, glow, accent brackets) plugged into `Theme` | `UiStyleBox` (same) + cached instances + optional 9-slice baking | Works for every Control incl. embedded popups; **91 µs per redraw** (500 redraws/frame = 45.8 ms, 4,401 draw calls) vs StyleBoxFlat 9.7 ms vs StyleBoxTexture 0.15 ms → never redraw styled panels per frame |
| `UiTheme.build(UiSkin)` faction tint (accent, accent2, dark tint) | `UiTheme.build(skin, a11y)` | 0.27 ms warm, 5-9 ms first call |
| Theme assigned on the first `Control` **below** a `CanvasLayer` (Window.theme does not inherit through `CanvasLayer`) | `UiLayerRoot` per layer | Pitfall 1 |
| `set_anchors_and_offsets_preset` (not `set_anchors_preset`) for code-built full-rect roots | rule in `UiLayerRoot` and `UiScreen` | Pitfall 2 |
| Custom-drawn widgets fetch styles by `get_theme_stylebox(state, &"Button")` | all widgets | — |
| `_make_custom_tooltip` returns a frameless body; Godot wraps it in the themed `TooltipPanel` | `UiTooltipBody` | verified |
| `UiCooldownSweep` canvas_item **shader** with a `progress` uniform; label child above the sweep | same | **0.11 ms for 100 sweeps** changing every frame vs TextureProgressBar 1.54 ms vs GDScript polygon 1.55 ms |
| `UiBuildCard` static text redrawn only on state change or once per displayed second | same | HUD idle 1.17 ms (Forward+) / 0.51 ms (Mobile), 683 draw calls; animated 1.27 ms; UI scale 1.5 → 0.77 ms |
| `UiIconBaker`: N `SubViewport`s in one frame, `UPDATE_ONCE`, ortho camera fitted to AABB, one `await frame_post_draw`, `fix_alpha_edges` | production icons come from the view's `ViewIconBake` (`render.md` §5.8.10 — same technique, its own spike `[M]`); the spike class stays as `UiViewPortFixture`'s baker and as the reference to lift | 34 icons 188x124 in 87 ms (2.6 ms/icon) warm; **cold pipeline cache 2.6-2.8 s** (Metal) |
| `UiMinimap`: `_draw` of terrain + fog textures + `draw_rect` dots + frustum polygon + rings + sweep at 30 Hz, mouse grab for drags | same | 0.23 ms per redraw for 439 dots |
| `UiWorldOverlay`: one `draw_multiline_colors` for all brackets, bars only for selected/damaged, cull off-screen | becomes the **fixture adapter's** implementation of the view overlay contract (`UiViewPort.set_selection` … `update_placement`); the production overlay is the view's instanced-quad design (`render.md` §5.10); the 2D `UiWorldOverlay` that ships keeps only order markers, targeting previews and edge alerts | 0.67 ms for 377 visible entities |
| `UiInputController`: start in `_unhandled_input`, continue in `_input`, poll in `_process`, cancel on focus loss | same (extended) | lab cases A-S |
| `UiPicking`: ray-vs-sphere and `unproject_position` box select without physics | fixture adapter only; production picking is the view's `ViewPicker` (same idea with oriented boxes: 60-90 µs per pick, 1.2 ms per `pick_box` at 400 entities) | 92 µs box (439 entities), 127 µs ray |
| Fonts: Rajdhani SemiBold/Bold (body), Orbitron variable (heads/numerals), Share Tech Mono (numbers) | `UiFonts` roles | judged at 12-18 px on `#0b1016`; the shipped minimum is 14 px |
| Responsive rules: minimap `clamp((h-420)*0.55, 180, 300)`, queue strip + footer hidden below 800 logical px, selection panel width `clamp(playfield-40, 600, 900)` | `UiLayout` size classes | 1280x720 @0.75 verified |

**Known spike defects fixed in this spec:** (1) `UiRibbon._draw` allocated a `UiStyleBox` every redraw (20 Hz per ribbon) → cached; (2) `UiInputController._finish` read `double_click` from the *release* event → double-click is now detected from the press timestamp/position (5.5.3); (3) card hotkeys collided with order hotkeys (decision 7); (4) `UiHotkeys.install()` erased `ui_focus_next/prev` globally, breaking menu Tab navigation → erased only while the GAME keymap context is active (5.6.3); (5) the demo cost/skirmish "crates" rule and demo data are harness-only and are not carried over.

### 1.5 Engine facts established for this spec

| # | Question | Result (Godot 4.7.2, macOS arm64, Metal Forward+) |
|---|---|---|
| E1 | Are autoloads usable from `--script` runners (the `tools/gd test` mode)? | Autoload nodes exist in `root` during `_initialize`, but `_ready()` runs **after** it (`ready_seen == false`). A script that names an autoload identifier fails to compile if loaded before registration (`Identifier not found`) but works when `load()`ed lazily inside `_initialize`. |
| E2 | Can a `Logger` subclass capture engine/script errors? | Yes. `OS.add_logger(logger)`. `_log_error(function, file, line, code, rationale, editor_notify, error_type, script_backtraces)` fires for `push_error` (`error_type 0`), `push_warning` (`1`), script runtime errors (`2`, `file`/`line` point at the script) and for errors raised on worker threads (called on that thread: `OS.get_thread_caller_id()` differed) → implementation needs a `Mutex`. For `push_error` the engine location is `core/variant/variant_utility.cpp`; the useful location is `script_backtraces[0].format()`. `_log_message(message, error)` mirrors `print`/`printerr`. |
| E3 | Cost of custom cursors? | Baking a 64x64 cursor through a `SubViewport` works (alpha preserved). `Input.set_custom_mouse_cursor(Image, shape, hotspot)` costs **0.36-0.56 ms** per *changed* image and 1.3 ms for an `ImageTexture`; re-setting the same texture 8 µs; `Input.set_default_cursor_shape()` between pre-registered shapes **1 µs**. → register each cursor once on its own shape slot at boot and switch by shape (5.7.3). |
| E4 | Action matching and key labels | `InputEvent.is_action_pressed(a, false, exact_match=false)` matches `Ctrl+1` against an action bound to plain `1`, and `Shift+S` against `S`; only `exact_match=true` separates them (all 4 group actions + orders need it). `OS.get_keycode_string(KEY_Q \| KEY_MASK_ALT)` → `"Option+Q"` on macOS (`"Alt+Q"` elsewhere) — platform-correct labels for free. `OS.find_keycode_from_string("Ctrl+Shift+1")` round-trips. `InputEventKey.is_command_or_control_pressed()` is `Cmd` on macOS (false for a Ctrl event). `ConfigFile.encode_to_text()/parse()` round-trips Dictionary, Array, `Color`, `PackedStringArray`. |
| — | Other API presence checked in `tools/godot_docs` | `Input.set_custom_mouse_cursor`, `set_default_cursor_shape`; `DisplayServer.keyboard_get_label_from_physical` (layout-aware labels), `window_set_vsync_mode`, `screen_get_scale`; `Viewport.scaling_3d_mode` (`BILINEAR, FSR, FSR2, METALFX_SPATIAL, METALFX_TEMPORAL, NEAREST`), `screen_space_aa` (`FXAA, SMAA`), `msaa_3d/2d`, `oversampling`; `RenderingServer.get_video_adapter_type`; `Control.accessibility_name/description/live`; `ProjectSettings accessibility/general/accessibility_support`; `Engine.get_license_text/get_license_info/get_copyright_info`; `OS.add_logger`, `OS.shell_open`; `Node.process_priority`; `WorkerThreadPool`; `SceneTree.change_scene_to_node`. |

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

Lint constraints that shape this list (`tools/py/lint.py`): `src/ui/**` classes must match `^Ui[A-Z0-9]\w*$`, `src/app/**` `^App[A-Z0-9]\w*$` (L004); file name = snake_case of `class_name` (L009); ≤ 1500 lines per file (L007); no `print`/`push_warning` outside `core/log.gd` — use `Log.*` (L006; the one `print` of `AppLogSink` carries a `lint-allow: L006` reason); autoload scripts carry **no** `class_name` (a `class_name` equal to the autoload name is a compile error). Paths are relative to `game/src/`. `~L` = planned lines.

### 2.1 `app/` — app shell

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `app/boot.gd`, `app/boot.tscn` | — (main scene script) | **Replaces the placeholder.** Keeps the `--smoke` contract (`MERIDIAN_BOOT engine=… renderer=… os=… debug=… version=<x.y.z> build=<id> selftest=<ok\|N>`, exit 0; `export.py` parses by prefix and the existing keys do not change), honours the QA hooks `--qa=<job>` (instantiates `res://tests/harness/qa_entry.gd` when it exists and quits with its exit code, `[QA-XR-11]`) and `--selfcheck`, then hands over to `AppBoot.run(self)` | 60 |
| `app/dev_shot.gd` | — (autoload `DevShot`) | **QA-owned, untouched.** `--shot=<png> --frames=<n>` viewport capture used by `tools/gd shot` | — |
| `app/app_boot.gd` | `AppBoot` | Boot state machine: parse args → init log sink and logger → load settings and the crash sentinel → load `GameData` → `ViewStyle.load_file()` (~2 ms, art §3) → theme/fonts → splash → first screen or autostart | 380 |
| `app/app_launch_args.gd` | `AppLaunchArgs` | Parsed `OS.get_cmdline_user_args()`: `--screen`, `--autostart`, `--config`, `--fixture`, `--ticks`, `--smoke`, `--fresh-settings` …; pure, unit-tested | 200 |
| `app/app_settings.gd` | — (autoload `AppSettings`) | Thin Node: owns one `AppSettingsStore`, debounced save (0.5 s), flush on quit/focus-out, `changed(id)` signal, calls `AppApply` | 140 |
| `app/app_settings_store.gd` | `AppSettingsStore` | Typed settings model: defaults, clamp/validate, load/save `user://settings.cfg`, migration, unknown-key preservation, in-memory mode for tests | 420 |
| `app/app_settings_schema.gd` | `AppSettingsSchema` | Table of every setting (id, type, default, range/choices, apply-hook, restart flag, capability guard); drives validation **and** the options UI | 380 |
| `app/app_apply.gd` | `AppApply` | Applies settings to the engine: window/vsync/fps, UI scale, cursor, low-processor mode, InputMap (via `UiKeymap`); hands the `[video]` / `[access]` `ConfigFile` to the view (`quality_config`, with the colour-mode name translation of 5.19.3) and a `SndSettings` built from `[audio]` / `[access]` to `Snd.apply_settings` (`AppAudio`) | 400 |
| `app/app_graphics.gd`, `app/app_relaunch.gd` | `AppGraphics`, `AppRelaunch` | Thin graphics glue: builds the `[video]` `ConfigFile` handed to the view, "Custom (based on …)" detection, capability guards per rendering method / driver, first-run `recommend()` pass-through to `ViewQuality` (the presets themselves are the view's, 4.7); `AppRelaunch`: the `video/renderer` choice needs a restart, done by `OS.create_process(OS.get_executable_path(), args + ["--rendering-method", name])` once, guarded against loops | 180 |
| `app/app_state.gd` | — (autoload `AppState`) | Thin Node: current `AppFlow` mode, `GameData` owner, profile, last match summary; binds `NetSession` phase signals to screen navigation | 260 |
| `app/app_flow.gd` | `AppFlow` | Pure screen-flow graph: modes, allowed edges, back-stack, params; unit-tested transition table (5.1) | 240 |
| `app/app_scenes.gd` | — (autoload `AppScenes`) | Layer stack (backdrop 3D host, screen, overlay, fade, debug), screen instantiate/enter/exit, fade transitions, modal stack host, loading-screen host, theme distribution | 420 |
| `app/app_screens.gd` | `AppScreens` | Registry `screen id → Callable() -> UiScreen`; id validation; fixture-screen overrides | 90 |
| `app/app_net.gd` | — (autoload `AppNet`, `process_priority = -100`) | Owns the `NetSession`; builds `NetSessionOptions`; calls `poll()` once per rendered frame before any view/ui `_process`, drains the events once, drives `view.frame(dt, alpha, records)` and then the `AppEvents` consumers; multiplayer power-mode toggles | 320 |
| `app/app_events.gd`, `app/app_audio.gd` | `AppEvents`, `AppAudio` | `AppEvents`: ordered consumer list for the drained event records (audio 10 → ui 20; the view is called first, explicitly, with the same array); one `world.events.take()` per rendered frame, the same read-only array to every consumer. `AppAudio`: the app-side bridge to the `Snd` autoload — `setup`, `set_mode`, `begin_match` / `load_progress` / `is_match_ready`, `attach_world`, the per-frame `set_camera` → `on_events` → `on_frame` feed, `end_match`, settings hand-off (`audio.md` §3.11) | 220 |
| `app/app_match.gd` | `AppMatch` | Match-setup glue: options builder inputs, `begin_build(config) -> NetWorldJob`, `make_ai_thinker`, skirmish/host/join/replay launch helpers, `MatchRules` defaults, headless helpers | 380 |
| `app/app_match_job.gd` | `AppMatchJob` | Composite `NetWorldJob`: (1) sim world (delegated), (2) `ViewWorld.build_async` (terrain, models, icons, prewarm), (3) audio banks (`Snd.begin_match`, threaded, polled through `load_progress()` / `is_match_ready()`); weighted progress; error propagation | 360 |
| `app/app_match_context.gd` | `AppMatchContext` | Everything about the running match the screens share: session, config, ports, local pid/roster/skin, event consumers, stats collector | 200 |
| `app/app_profile.gd` | `AppProfile` | Player name (sanitised OS user name default), last roster, favourites, lifetime counters | 120 |
| `app/app_logger.gd` | `AppLogger` | `Logger` subclass (mutex): mirrors engine errors into `Log.ring` (256 lines), per-location rate limiting, error-storm detector, toast callback; never prints inside `_log_error` | 220 |
| `app/app_crash_reporter.gd`, `app/app_log_sink.gd`, `app/app_file_layer.gd` | `AppCrashReporter`, `AppLogSink`, `AppFileLayer` | `.session` sentinel, `NOTIFICATION_CRASH` handler, `crash_<utc>[_unclean\|_fatal].txt`, report header, retention (20); the `Log.sink` formatter with the 20 lines/s/tag rate limit; injectable file layer for the crash-safe settings writer (5.20) | 340 |
| `app/app_crash.gd` | `AppCrash` | Fatal/crash report model: reason codes, text builder (`GameData.last_report.text()`, log tail, versions, GPU), clipboard/text export | 180 |
| `app/app_paths.gd` | `AppPaths` | All `user://` and `res://` path constants (one place; exact-case) and `ensure_user_dirs()` (creates `logs/`, `logs/crash/`, `cache/icons/`, `cache/models/`, `screenshots/` at boot — `render.md` request 32 asks the app for the cache folders) | 80 |
| `app/app_info.gd` | `AppInfo` | `version()`, `build_id()`, `platform_string()` and the extended `MERIDIAN_BOOT` smoke line (`[QA-XR-14]`) | 70 |
| `app/app_test_boot.gd` | `AppTestBoot` | Headless autostart harness: `--autostart=match\|replay`, scripted commands via `UiCommandBus`, `APPTEST …` result line, exit codes | 340 |

**Autoload responsibilities** (registered in this order after the QA-owned `DevShot`; scripts have no `class_name`, initialise lazily — measured E1):

| Autoload | Owns | Depends on | Must not |
|---|---|---|---|
| `AppSettings` | the `AppSettingsStore`, debounced persistence, `changed` / `graphics_quality_changed`, calls `AppApply` | `AppSettingsStore`, `AppApply` | touch scenes or sessions |
| `AppNet` | the current `NetSession`, the per-frame `poll()` (priority −100), event fan-out (`AppEvents`), `NetSessionOptions` construction | `AppSettings`, `AppMatch`, `AppState.data` | create widgets |
| `AppState` | `AppFlow` mode + push/pop stack, the loaded `GameData`, `AppProfile`, the `AppMatchContext`, session-signal → navigation wiring, clean quit | `AppFlow`, `AppNet`, `AppScenes` | know widget classes beyond screen ids |
| `AppScenes` | the layer stack (backdrop / screen / overlay / fade / debug), screen instantiate-enter-exit, fade transitions, dialog stack, theme distribution to every `UiLayerRoot`, loading-screen host | `AppScreens`, `UiThemeService` | game rules, networking |
| `DevShot` (QA) | `--shot` capture for `tools/gd shot` | — | — |

### 2.2 `ui/` — foundation and design system

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `ui/ui_palette.gd` | `UiPalette` | Colour-token constants (the 18 tokens of `style.ui.tokens`; asserted equal to the JSON by test U-1), the CVD-safe semantic set (5.19.3), `team(i)` → `ViewStyle.player_color(i, cvd)`. With `ui_skin.gd` the only UI files allowed to hold colour literals (lint L011, `art_direction.md` R-25) | 120 |
| `ui/ui_metrics.gd` | `UiMetrics` | Spacing scale, type scale, cuts, border widths, sidebar/card/panel dimensions, timings — every layout constant of section 4.6 | 140 |
| `ui/ui_skin.gd` | `UiSkin` | Faction skin (accent, accent2, tint) + derived gradient stops; `from_style(style, faction_code)` (`art_direction.md` R-17), `neutral()` | 90 |
| `ui/ui_skin_set.gd` | `UiSkinSet` | Holds the injected `ViewStyle`; one `UiSkin` per faction + neutral; colour-mode switch `normal` / `cvd`; contrast self-check; built-in fallback skins when `style.json` failed to load | 150 |
| `ui/ui_fonts.gd` | `UiFonts` | Font roles BODY / BODY_BOLD / HEAD / HEAD_LIGHT / NUM (`FontVariation` for Orbitron `wght`); optional dyslexia-friendly family (`access/ui_font`); every role carries a fallback chain ending in a `SystemFont` so CJK / Arabic / emoji player names render (tofu tolerated, never a crash, QA X-16) | 110 |
| `ui/ui_style_box.gd` | `UiStyleBox` | Scripted chamfered/gradient/glow `StyleBox` (spike), `variant()`, cached factories | 150 |
| `ui/ui_draw.gd` | `UiDraw` | Pure geometry helpers: chamfer points, rect sector/boundary, arc points, pixel snapping | 110 |
| `ui/ui_theme.gd` | `UiTheme` | `build(skin, a11y) -> Theme`: labels, panels, buttons (+focus ring for menus), inputs, bars, scrollbars, sliders, popups, tooltips; type variations of 4.6.3 | 420 |
| `ui/ui_theme_service.gd` | `UiThemeService` | Holds the current `Theme`; `rebuild(skin)`; assigns to every `UiLayerRoot`; emits `theme_changed` | 110 |
| `ui/ui_glyphs.gd` | `UiGlyphs` | Vector glyph library on the 24-px grid (`art_direction.md` §5.12.6): the spike's 29 + the 16 art requires (TANK, ARTILLERY, ANTI_AIR, SCOUT, TRANSPORT, ENGINEER, COLLECTOR, MCV, DRONE, SUBMARINE, CARRIER, SIEGE, COMMAND, CAMO, EMP_OFF, NO_POWER) + 10 UI-specific (FOLLOW, HOLD, PATROL, RETURN, UNLOAD, STANCE, RALLY, PING, SPEED, MUTE); `draw(ci, glyph, rect, col, w)`; `role_glyph(def)` (5.10.4); a lazily baked white atlas for the strategic-zoom markers | 640 |
| `ui/ui_emblem.gd`, `ui/ui_emblem_view.gd` | `UiEmblem`, `UiEmblemView` | `UiEmblem`: art's data-driven op interpreter with art's signatures (`draw_ops`, `draw_faction`, `draw_badge`, `draw_pips`; `art_direction.md` §3, §5.11) replacing the spike's hand-coded emblems; `UiEmblemView`: the fitting Control (size ladder ≥ 96 / 48-95 / 24-47 / 16-23 px, clear space 10 %) | 130 |
| `ui/ui_text.gd` | `UiText` | `t(key, args)` lookup over `data/text/*.json`, `{name}` interpolation, plural suffix, missing-key policy | 150 |
| `ui/ui_format.gd` | `UiFormat` | `credits(n)` "12,450", `mmss(s)`, `hms(s)`, `pct`, `hash8(h)` "9F3A-C21E", `bytes`, `hotkey(action)` | 140 |
| `ui/ui_layout.gd` | `UiLayout` | Scale factor and size-class maths (5.4), window-resize handling, safe minimums | 140 |
| `ui/ui_motion.gd` | `UiMotion` | Durations/easings honouring `reduce_motion`; tween helpers | 90 |
| `ui/ui_a11y.gd` | `UiA11y` | CVD simulation (Machado 2009), CIEDE2000 and contrast checks (the palette tests), the shared pip-shape drawing, `accessibility_name` helper | 240 |
| `ui/ui_cursors.gd` | `UiCursors` | Procedural cursor bake (SubViewport → Image) of the art set (default, move, attack, attack-move, guard, deploy, repair, sell, capture / interact, force-fire, invalid + the UI states) with relation tints, one-time registration on shape slots, `set_state()`; the 8 edge-scroll cursors swapped onto the arrow slot on demand (`set_scroll(dir)`) | 340 |
| `ui/ui_focus_policy.gd` | `UiFocusPolicy` | `apply_menu(root)` (focus ALL, tab order) / `apply_hud(root)` (focus NONE recursively) | 60 |

### 2.3 `ui/` — widgets and containers

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `ui/ui_screen.gd` | `UiScreen` | Base class of all screens: `enter(params)`, `exit()`, `back_requested`, default focus, keymap context, escape chain | 160 |
| `ui/ui_layer_root.gd` | `UiLayerRoot` | Full-rect `Control` under a `CanvasLayer`, carries the `theme`, `MOUSE_FILTER_IGNORE` | 40 |
| `ui/ui_dialog_stack.gd` | `UiDialogStack` | Modal stack: dims, blocks input controller, focus trap, Esc handling, one dialog visible at a time (queue) | 160 |
| `ui/ui_dialog.gd` | `UiDialog` | Dialog base (title, body, button row, result signal) | 140 |
| `ui/ui_toast.gd` | `UiToast` | Non-modal notices (info/warn/error) with optional action buttons (Open logs folder, Copy report, Watch recovered replay, Undo), auto-dismiss | 140 |
| `ui/ui_tooltip_body.gd` | `UiTooltipBody` | Frameless rich tooltip body factory (`_make_custom_tooltip`) for cards, orders, stats | 200 |
| `ui/ui_icon_button.gd` | `UiIconButton` | Glyph/icon button (toggle, badge, hotkey text, caption), HUD-safe (focus NONE) | 130 |
| `ui/ui_build_item.gd` | `UiBuildItem` | View-model of one card (state enum, cost, time, progress permille, queue, requirement text) | 70 |
| `ui/ui_build_card.gd` | `UiBuildCard` | Single custom-drawn build card (portrait, name, cost, hotkey, badges, states) | 300 |
| `ui/ui_cooldown_sweep.gd` | `UiCooldownSweep` | Clock-wipe overlay; SHADER back-end (default), polygon/TextureProgress kept for gl_compat fallback tests | 110 |
| `ui/ui_credit_ticker.gd` | `UiCreditTicker` | Count-up credits, flash, income line (fixed-width digit cells) | 90 |
| `ui/ui_power_bar.gd` | `UiPowerBar` | 32-segment power meter, LOW POWER alert pulse (1 Hz) | 90 |
| `ui/ui_queue_strip.gd` | `UiQueueStrip` | 5-slot production queue of the active producer, cancel/hold, producer switcher | 150 |
| `ui/ui_ribbon.gd` | `UiRibbon` | Alert ribbon (severity, countdown, charge, tag) | 130 |
| `ui/ui_group_bar.gd` | `UiGroupBar` | Control-group badges 1..0 | 90 |
| `ui/ui_list_row.gd` | `UiListRow` | One custom-drawn row of a data list (LAN games, replays, Field Manual lists) | 100 |
| `ui/ui_roster_strip.gd` | `UiRosterStrip` | Wrapped grid of unit portraits with tier pips and UNIQUE badges | 80 |
| `ui/ui_select_rect.gd` | `UiSelectRect` | Drag-select rectangle overlay | 40 |
| `ui/ui_tab_bar.gd` | `UiTabBar` | Segmented tab strip (glyph or text), badges | 130 |
| `ui/ui_choice_row.gd`, `ui/ui_slider_row.gd`, `ui/ui_toggle_row.gd` | `UiChoiceRow`, `UiSliderRow`, `UiToggleRow` | Options rows bound to a settings id (label, control, value text, reset-to-default, restart badge) | 300 |
| `ui/ui_keybind_button.gd` | `UiKeybindButton` | Key-capture button (listen mode, conflict signal, clear) | 160 |
| `ui/ui_panel_header.gd`, `ui/ui_progress_chip.gd` | `UiPanelHeader`, `UiProgressChip` | Small recurring composites | 120 |
| `ui/ui_vignette.gd` | `UiVignette` | One-quad canvas shader (vignette, letterbox, scrim, scanlines) | 60 |

### 2.4 `ui/` — ports and adapters (the only seams to sim / view / net / audio)

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `ui/ui_sim_port.gd` | `UiSimPort` | **Abstract read API of the simulation as the UI needs it** (3.2.1). Default bodies `push_error("NOT IMPLEMENTED")` | 300 |
| `ui/ui_sim_port_world.gd` | `UiSimPortWorld` | Adapter over `SimWorld`/`SimPlayer`/`SimEntity` and the production/power/strategic queries (mapping table 3.2.4; the only file to edit if sim renames); also wraps `GameData`/`DefPlayerView` reads | 700 |
| `ui/ui_sim_port_fixture.gd` | `UiSimPortFixture` | Deterministic scripted fake world (players, producers, queues, powers, entities, fog, events) loaded from `tests/fixtures/ui/*.json` | 600 |
| `ui/ui_entity_row.gd`, `ui/ui_entity_snapshot.gd` | `UiEntityRow`, `UiEntitySnapshot` | Reusable struct for one entity read / SoA bulk snapshot (ids, x, y, def, owner, flags, hp%) | 120 |
| `ui/ui_view_port.gd` | `UiViewPort` | **Abstract API to the view**: UI-driven camera, picking, the interaction visuals the view draws (selection, health bars, lines, placement ghost, range rings, float text), minimap sources, icons and models, quality / palette (3.2.2) | 200 |
| `ui/ui_view_port_world.gd` | `UiViewPortWorld` | Adapter over `ViewWorld` and its subsystems per table 3.2.5 (`render.md`); the only file that names `View*` classes | 350 |
| `ui/ui_view_port_fixture.gd` | `UiViewPortFixture` | Procedural battlefield (lifted from the spike's `DemoWorld`/`DemoModels`) for UI dev, screenshots, headless layout tests; implements the whole port incl. 2D stand-ins for rings / bars / lines / ghost (the spike's overlay code) and the spike's picking and icon baker | 1,300 |
| `ui/ui_pick_data.gd` | `UiPickData` | SoA of rendered entities (ids, pos, radius, height, flags) + `slot_of(id)` — **fixture adapter only** (production picking is `ViewPicker`) | 90 |
| `ui/ui_net_port.gd`, `ui_net_port_session.gd`, `ui_net_port_recorder.gd`, `ui_net_port_null.gd` | `UiNetPort`, `UiNetPortSession`, `UiNetPortRecorder`, `UiNetPortNull` | Command submission seam (takes the command int array): session-backed (`NetSession.submit_command(ints)`), recording (tests), refusing (observers/replays) | 200 |
| `ui/ui_audio_port.gd`, `ui_audio_port_snd.gd`, `ui_audio_port_null.gd`, `ui_audio_port_recorder.gd` | `UiAudioPort`, `UiAudioPortSnd`, `UiAudioPortNull`, `UiAudioPortRecorder` | UI-cue / unit-response / caption seam over the `Snd` facade (`snd.ui.*` ids in 6.3.1); null and recording adapters for tests | 220 |

### 2.5 `ui/` — input, selection, commands

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `ui/ui_input_controller.gd` | `UiInputController` | World gesture state machine (5.5), edge scroll, camera intents, armed modes, hover probe, focus-loss cancel | 700 |
| `ui/ui_actions.gd` | `UiActions` | `StringName` constants of every action + category/context metadata | 200 |
| `ui/ui_keymap.gd` | `UiKeymap` | Defaults (from `keymap_defaults.json`), contexts, conflict detection, rebinding, persistence, InputMap install/uninstall, labels | 520 |
| `ui/ui_selection.gd` | `UiSelection` | Selection model (ids, order, primary, mode), add/toggle/replace, prune on death, successor rule, signals | 320 |
| `ui/ui_selection_info.gd`, `ui/ui_unit_caps.gd` | `UiSelectionInfo`, `UiUnitCaps` | Aggregated capability bits of the selection; per-def capability cache built from `DefUnit` tags/abilities/weapons | 260 |
| `ui/ui_control_groups.gd`, `ui/ui_bookmarks.gd` | `UiControlGroups`, `UiBookmarks` | 10 groups (assign/add/recall/double-tap centre); 4 camera bookmarks | 220 |
| `ui/ui_selection_actions.gd` | `UiSelectionActions` | Keyboard / menu selection commands built on the ports: same type on screen or map, all military (map or screen), next idle unit, next collector, next producer, HQ, jump to alert — the single implementation behind the keys and the "Select" menu (A-06, A-19) | 200 |
| `ui/ui_picking.gd` | `UiPicking` | Pure picking maths on `UiPickData` (ray pick, box select) — used by `UiViewPortFixture` and unit-tested as the reference for the view's `ViewPicker` rules; `same_type_on_screen` lives in `UiSelectionActions` on top of `UiViewPort.entity_screen_rect` | 200 |
| `ui/ui_target.gd`, `ui/ui_order_intent.gd` | `UiTarget`, `UiOrderIntent` | What is under the cursor / what a click would do (fields in 4.3) | 120 |
| `ui/ui_context_resolver.gd` | `UiContextResolver` | The right-click / armed-click decision table (5.7) — pure, 100 % unit-tested | 480 |
| `ui/ui_modes.gd` | `UiModes` | Armed command modes (attack-move, move, guard, patrol, force-fire, sell, repair, rally, ping, waypoint latch) state + transitions | 170 |
| `ui/ui_command_bus.gd` | `UiCommandBus` | Only path UI → sim: dispatch intents, chunk id lists, throttle, optimistic feedback, rejection handling | 520 |
| `ui/ui_cmd_codec.gd` | `UiCmdCodec` | One static builder per UI action that calls the matching `SimCmd` builder (section 6.1) and returns the command int array; `describe()` for tests and logs; `verify_against_sim()`; the one file that names ops and fields | 300 |
| `ui/ui_ev.gd` | `UiEv` | Event codes and field indices (core registry + combat / abilities / economy blocks, 6.2.1) that the UI consumes; name ↔ code tables for `notices.json`; `verify_against_sim()` | 160 |
| `ui/ui_feedback.gd` | `UiFeedback` | Immediate ack: order markers, minimap pings, unit responses, brackets flash, denied cues | 200 |
| `ui/ui_placement.gd` | `UiPlacement` | Ready-to-place flow: footprint anchor, validity polling, ghost + build-radius requests, commit/cancel | 260 |
| `ui/ui_targeting.gd` | `UiTargeting` | Support-power / superweapon targeting (shape preview, vision validity, angle for line powers) | 260 |

### 2.6 `ui/` — HUD, presenters, notifications

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `ui/ui_hud.gd` | `UiHud` | HUD root: composes sidebar, bottom panel, top strip, dock, ribbons, feeds, overlay; size-class relayout | 320 |
| `ui/ui_sidebar.gd` | `UiSidebar` | Right sidebar: header, minimap, tool row, eco panel, tab bar, card grid, queue strip, footer | 450 |
| `ui/ui_bottom_panel.gd`, `ui/ui_selection_panel.gd`, `ui/ui_selection_view.gd` | `UiBottomPanel`, `UiSelectionPanel`, `UiSelectionView` | Group bar + portrait/tiles + command area | 480 |
| `ui/ui_command_bar.gd`, `ui/ui_ability_bar.gd` | `UiCommandBar`, `UiAbilityBar` | Static 4x2 order grid; dynamic ability slots (mode switch, cover, decoy, smoke, unload …) | 300 |
| `ui/ui_top_strip.gd` | `UiTopStrip` | Game time, kills/lost, score, speed, pause/net badges | 120 |
| `ui/ui_power_dock.gd` | `UiPowerDock` | 3 support-power buttons + superweapon with sweeps, countdowns, hotkeys F5–F8 | 220 |
| `ui/ui_ribbon_stack.gd` | `UiRibbonStack` | Ordered stack of `UiRibbon`s with slide in/out and caps | 140 |
| `ui/ui_camera_pad.gd`, `ui/ui_select_menu.gd` | `UiCameraPad`, `UiSelectMenu` | Mouse-only alternatives to camera keys and selection shortcuts (5.11.7) | 220 |
| `ui/ui_log_feed.gd`, `ui/ui_chat_overlay.gd` | `UiLogFeed`, `UiChatOverlay` | Fading message feed; chat input + history (plain text only) | 320 |
| `ui/ui_stall_overlay.gd`, `ui/ui_pause_banner.gd`, `ui/ui_net_overlay.gd` | `UiStallOverlay`, `UiPauseBanner`, `UiNetOverlay` | "Waiting for …", pause banner, F3 net/perf overlay | 280 |
| `ui/ui_observer_bar.gd`, `ui/ui_replay_bar.gd`, `ui/ui_scoreboard.gd` | `UiObserverBar`, `UiReplayBar`, `UiScoreboard` | Perspective switcher, replay transport (speed chips, seek bar with CHECK ticks), per-player stats table | 420 |
| `ui/ui_minimap.gd`, `ui/ui_minimap_feed.gd` | `UiMinimap`, `UiMinimapFeed` | Minimap widget; SoA feed (dots, ghosts, quad, pings, warnings) | 360 |
| `ui/ui_world_overlay.gd`, `ui/ui_order_markers.gd` | `UiWorldOverlay`, `UiOrderMarkers` | Small 2D screen-space layer: order-issue markers, power / superweapon targeting previews (projected ground polylines), off-screen alert arrows (A-07) and the **strategic-zoom class-glyph markers** (below 18 px per metre every visible unit also gets its role glyph in the owner colour, `art_direction.md` R-18, 5.12); everything else in the world is the view's | 340 |
| `ui/ui_hud_presenter.gd` | `UiHudPresenter` | The one place that pulls from `UiSimPort` and pushes to widgets (cadences in 5.10.1) | 700 |
| `ui/ui_build_model.gd`, `ui/ui_producer_picker.gd` | `UiBuildModel`, `UiProducerPicker` | Builds the 8 tabs of `UiBuildItem`s from roster + sim state; deterministic producer choice | 480 |
| `ui/ui_notifier.gd`, `ui/ui_notice_rules.gd` | `UiNotifier`, `UiNoticeRules` | Event → notice engine (dedupe, cooldown, severity, ping, jump target); rule table loaded from `notices.json` | 420 |
| `ui/ui_match_stats.gd`, `ui/ui_score.gd` | `UiMatchStats`, `UiScore` | Time-series sampler (10 s) for graphs; score formula (5.16.5) | 260 |

### 2.7 `ui/` — screens, dialogs, baking

| Path | `class_name` | Responsibility | ~L |
|---|---|---|---|
| `ui/ui_screen_splash.gd` | `UiScreenSplash` | Wordmark splash, progress text, skip | 120 |
| `ui/ui_screen_main_menu.gd` | `UiScreenMainMenu` | Menu stack, featured-faction card, status chips, 3D showcase control | 380 |
| `ui/ui_screen_lobby.gd` | `UiScreenLobby` | Lobby for LOCAL/HOST/CLIENT roles; composes the five panels below | 700 |
| `ui/ui_lobby_slot_row.gd`, `ui/ui_lobby_briefing.gd`, `ui/ui_lobby_map_panel.gd`, `ui/ui_lobby_rules_panel.gd`, `ui/ui_lobby_chat.gd` | `UiLobbySlotRow`, `UiLobbyBriefing`, `UiLobbyMapPanel`, `UiLobbyRulesPanel`, `UiLobbyChat` | Slot row (type/faction/sub/team/colour/start/ready/kick), faction+roster briefing, map preview + start markers, rules/net options, chat | 1,300 |
| `ui/ui_map_preview.gd`, `ui/ui_map_names.gd` | `UiMapPreview`, `UiMapNames` | Lobby map preview: `MapGenJob` (worker thread) → `MapData` → `UiViewPort.bake_map_preview`, tuple cache, start markers from `MapData.start_cells`, the fair-start helper (`fair_slot_order`); deterministic cosmetic map names from a syllable table | 240 |
| `ui/ui_screen_lan_browser.gd` | `UiScreenLanBrowser` | Discovery list, filters, details, direct IP, recent hosts, host button, explainer | 520 |
| `ui/ui_screen_loading.gd` | `UiScreenLoading` | Per-player progress, map card, tips, cancel | 260 |
| `ui/ui_screen_game.gd` | `UiScreenGame` | Assembles ports + HUD + input + presenter; owns the per-frame UI update order; observer/replay variants | 560 |
| `ui/ui_screen_end.gd` | `UiScreenEnd` | Result banner, per-player table, graphs, buttons | 420 |
| `ui/ui_screen_replays.gd` | `UiScreenReplays` | Replay list, filters, verify, save/rename/delete, watch | 460 |
| `ui/ui_screen_field_manual.gd`, `ui/ui_fm_model.gd`, `ui/ui_fm_tech_tree.gd`, `ui/ui_model_viewer.gd` | `UiScreenFieldManual`, `UiFmModel`, `UiFmTechTree`, `UiModelViewer` | In-game encyclopedia over `DefBrowser`; tech-tree graph; turntable 3D viewer | 1,500 |
| `ui/ui_screen_options.gd` + `ui/ui_options_page_graphics.gd`, `_audio.gd`, `_controls.gd`, `_interface.gd`, `_network.gd` | `UiScreenOptions`, `UiOptionsPageGraphics`, `UiOptionsPageAudio`, `UiOptionsPageControls`, `UiOptionsPageInterface`, `UiOptionsPageNetwork` | Schema-driven options pages, keybind table, apply/revert | 1,200 |
| `ui/ui_screen_credits.gd`, `ui/ui_screen_fatal.gd` | `UiScreenCredits`, `UiScreenFatal` | Scrolling credits + licences; fatal-error screen | 320 |
| `ui/ui_dlg_game_menu.gd`, `ui_dlg_confirm.gd`, `ui_dlg_message.gd`, `ui_dlg_text_input.gd`, `ui_dlg_host_game.gd`, `ui_dlg_join_rejected.gd`, `ui_dlg_firewall_help.gd`, `ui_dlg_stall_prompt.gd`, `ui_dlg_desync.gd`, `ui_dlg_key_conflict.gd`, `ui_dlg_save_replay.gd` | `UiDlg*` (11 classes) | Modal dialogs | 900 |
| `ui/ui_icon_baker.gd`, `ui/ui_icon_cache.gd`, `ui/ui_style_bakery.gd` | `UiIconBaker`, `UiIconCache`, `UiStyleBakery` | `UiIconBaker`: the spike's batched model → icon bake, used by the fixture adapter only; `UiIconCache`: handle map `key → Texture2D` over `UiViewPort.request_icon` / `icon_ready` (the view owns baking and its disk cache); optional 9-slice style baking | 380 |

### 2.8 Tests, fixtures, data, assets owned by this module

| Path | Purpose |
|---|---|
| `game/tests/ui/test_ui_*.gd` | Unit tests (10.2), scenario and determinism tests (10.4-10.5), `func test_*(t: TestCtx)`; the async labs (`test_ui_lab_*.gd`, 10.3) live beside them |
| `game/tests/ui/ui_harness.gd` | `SubViewport`-based input/layout harness (spike's input lab, automated) |
| `game/tests/fixtures/ui/*.json` | Fixture worlds and states for `UiSimPortFixture` / screens: `hud_mid_match`, `hud_low_power`, `hud_two_factories`, `hud_superweapon_warning`, `hud_observer`, `lobby_skirmish`, `lobby_lan`, `lobby_errors`, `lan_games`, `loading`, `end_victory`, `end_defeat`, `replays_list`, `replay_view` |
| `game/data/text/ui_en.json`, `tips_en.json`, `credits.json`, `map_names_en.json` | Strings, loading tips, credits (QA schema), map-name syllables (7.1-7.3) |
| `game/data/ui/keymap_defaults.json`, `cursors.json`, `notices.json`, `skirmish_presets.json` | UI data (7.6-7.10). Tokens, skins, player colours, emblems and the type scale are **not** UI data: they live in `game/data/recipes/style.json` (`art_direction.md` §7; what the UI reads is listed in 7.4). Graphics presets are the view's `quality.json` (7.9) |
| `game/assets/fonts/<family>/` (`rajdhani`, `orbitron`, `share_tech_mono`, optionally `atkinson_hyperlegible`) with each family's `OFL.txt` beside the font files | Vendored OFL fonts, copied from the spike (≈1.4 MB; Latin subsetting would need fontTools, which the tool policy excludes — accepted); licence texts also in `LICENSES/fonts/` (`qa.md` §5.11: never modify or subset a font that declares a Reserved Font Name — Orbitron and Share Tech Mono do) |

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

Conventions: `##` doc comments are part of the contract. All coordinates that cross a port are **sim units** (`int`, 1024 per cell) unless the name says `world`/`screen`/`norm` or is a **placement anchor** (`ax, ay`, `cx, cy`: whole cells). Anything named `*_permille` is `0..1000`. Every method that receives data derived from remote peers or files is total (returns a default / `false`, never raises an engine error). Signatures that mention `Sim*`/`Net*`/`Def*` types are the exact ones from the sibling specs; ports absorb any renaming.

### 3.0 Frame order, threading and memory ownership

```
per rendered frame (all on the main thread; the UI creates no threads except the optional PNG-cache WorkerThreadPool task)

 P0  input events (delivered by the engine at any point before _process):
       GUI Controls  →  _input()  →  _unhandled_input()   [UiInputController gestures; see 5.5.2]
 P1  AppNet._process          process_priority = -100
       ticks = session.poll()                                # net.md §3.0
       if the match context exists:
           records = ctx.sim.take_events()                   # ONE drain per rendered frame (sim_core.md §5.7)
           var alpha := session.tick_alpha()
           ctx.view.frame(delta, alpha, records)   # the view's single per-frame entry (render.md §3.0) [XR-13]: events → entities / FX, interpolation, fog, overlays; picking data is valid AFTER this
           AppEvents.dispatch(records, alpha, delta)         # consumers in ascending `order`: audio (10) = AppAudio.frame → Snd.set_camera, Snd.on_events, Snd.on_frame (audio.md §3.2); ui (20) = UiHudPresenter.on_events (notifier, selection prune, stats)
 P2  (the view has no _process of its own; nothing runs here)
 P3  UiScreenGame._process    process_priority = 0
       3a  UiInputController.tick(delta)      # polled camera keys, edge scroll, hover probe @30 Hz → cursor state
       3b  if ticks > 0: UiHudPresenter.on_ticks(ticks)        # state → view-models, 20 Hz
       3c  UiHudPresenter.on_frame(delta)                      # smoothing (credits, sweeps), overlay projection, minimap cadence
 P4  engine draws; widgets that changed called queue_redraw() in 3a-3c
```

| Thing | Owner | Lifetime / rule |
|---|---|---|
| `NetSession`, `SimWorld`, `GameData` | net / net / `AppState` | UI holds references only; drops them on `AppNet.session_changed(null)` |
| `UiSimPort`, `UiViewPort`, `UiNetPort`, `UiAudioPort` instances | `AppMatchContext` | created at `AppMatchJob` start, disposed in `AppMatchContext.dispose()` (nulls every reference) |
| `UiEntityRow`, `UiEntitySnapshot`, `PackedInt32Array` out-params | the caller | reused buffers; a port method never retains them; callers never keep them past the call unless stated |
| `UiSelection`, `UiControlGroups`, `UiBookmarks`, `UiCommandBus`, `UiHudPresenter` | `UiScreenGame` | one set per match; freed with the screen |
| `Theme` | `UiThemeService` | one live instance; screens read it through their `UiLayerRoot` |
| Baked icons | the view (`ViewIconBake`) | textures and LRU belong to the view; `UiIconCache` holds handles only |
| Widgets never hold a parent reference | — | children talk upward only through signals/`Callable`s injected at setup (no cycles) |

### 3.1 App layer

```gdscript
# ---- autoload scripts have NO class_name; initialise lazily (measured E1) ----------------------------------------------
# game/src/app/app_settings.gd   (autoload "AppSettings")
var store: AppSettingsStore
signal changed(id: StringName)                          # after the store changed and AppApply ran
signal graphics_quality_changed()                       # a video/* quality key changed; AppApply hands the [video] ConfigFile to the view (4.7.3) [XR-14]
func ensure_loaded() -> void                            # idempotent; called from _init and every accessor
func get_int(id: StringName) -> int
func get_bool(id: StringName) -> bool
func get_float(id: StringName) -> float
func get_str(id: StringName) -> String
func set_value(id: StringName, value: Variant) -> void # validate+clamp → store → schedule save (0.5 s debounce) → AppApply.on_changed
func apply_all() -> void                                # boot: display, audio, input, ui scale, quality
func flush() -> void                                    # save immediately (quit, focus-out, before launching a match)
func set_overrides(o: Dictionary) -> void               # CLI/test overrides; never persisted

class_name AppSettingsStore extends RefCounted          # pure; unit-tested without SceneTree
const FORMAT_VERSION: int = 1
signal changed(id: StringName)
var load_notes: PackedStringArray                       # e.g. "settings.cfg corrupt → moved to settings.cfg.bad-20260929T140311Z"
static func with_defaults() -> AppSettingsStore
func load_from(path: String, files: AppFileLayer = null) -> int   # Error; missing file = try .bak, else defaults; parse failure = file renamed *.bad-<utc>, .bak tried, else defaults
func save_to(path: String, files: AppFileLayer = null) -> int   # 5.20.1: write .tmp, rename the old file to .bak, rename .tmp into place (a valid file is recoverable after every step)
func get_value(id: StringName) -> Variant               # typed per schema; unknown id → null + Log.warn once
func set_value(id: StringName, value: Variant) -> bool  # coerce+clamp per AppSettingsSchema; false if id unknown or value unusable
func reset(id: StringName) -> void
func reset_all() -> void
func is_default(id: StringName) -> bool
func dirty() -> bool
func keys_section() -> Dictionary                       # action → PackedStringArray (packed key strings, 4.5.1)
func set_keys_section(d: Dictionary) -> void

class_name AppSettingsSchema extends RefCounted
enum T { BOOL = 0, INT = 1, FLOAT = 2, CHOICE = 3, STRING = 4, KEYS = 5 }
static func entries() -> Array[Dictionary]              # rows of 4.8.1: {id, type, default, min, max, step, choices, apply, restart, guard, label_key}
static func entry(id: StringName) -> Dictionary
static func guard_ok(guard: StringName) -> bool         # capability guard: &"forward_plus", &"not_compat", &"metalfx", &"fsr2", &"windowed_only" …

class_name AppApply extends RefCounted
static func on_changed(id: StringName, store: AppSettingsStore) -> void   # routes by schema `apply` hook: video / audio / input / ui / quality / net / misc
static func apply_video(store: AppSettingsStore) -> void
static func apply_audio(store: AppSettingsStore) -> void                  # builds a SndSettings from [audio] + [access] (SndSettings.load_from) and calls Snd.apply_settings through AppAudio; the app never touches AudioServer buses (5.18.5)
static func apply_ui_scale(window: Window, store: AppSettingsStore) -> void   # UiLayout.factor(...)
static func quality_config(store: AppSettingsStore) -> ConfigFile         # the [video] + [access] sections for ViewQuality.from_settings (4.7.3); `colour_mode` (`normal` / `deutan`) with `cvd_palette` and `high_contrast_hud` as separate booleans are written under the view's names (5.19.3)

class_name AppGraphics extends RefCounted
enum Preset { LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3, AUTO = 4 }            # = the view's [video] quality values
static func recommend() -> int                          # UiViewPort.quality_recommend() → ViewQuality.recommend (5.18.2)
static func overrides(store: AppSettingsStore) -> PackedStringArray   # quality keys present besides `quality` ("Custom (based on …)" when non-empty)
static func clear_overrides(store: AppSettingsStore) -> void          # choosing a preset in the dropdown

# ---- flow --------------------------------------------------------------------------------------------------------------
class_name AppFlow extends RefCounted
enum Mode { BOOT = 0, MAIN_MENU = 1, SKIRMISH_LOBBY = 2, LAN_BROWSER = 3, LAN_LOBBY = 4, LOADING = 5, IN_MATCH = 6,
            END_SCREEN = 7, REPLAYS = 8, REPLAY_PLAYBACK = 9, OPTIONS = 10, CREDITS = 11, FIELD_MANUAL = 12, FATAL = 13, QUIT = 14 }
var mode: int
var params: Dictionary
static func can_go(from: int, to: int) -> bool          # the edge table of 5.1.2
static func screen_id_of(mode: int) -> StringName
func go(to: int, p: Dictionary = {}) -> bool            # false + Log.warn if the edge is illegal
func push(to: int, p: Dictionary = {}) -> bool          # overlay (options / field manual over a match or a lobby)
func pop() -> int                                        # returns the mode returned to
func stack_depth() -> int

# game/src/app/app_state.gd      (autoload "AppState")
signal mode_changed(mode: int, previous: int)
var flow: AppFlow
var data: GameData                                      # loaded once at boot; null only in FATAL
var profile: AppProfile
var match_ctx: AppMatchContext                          # null outside LOADING/IN_MATCH/END_SCREEN/REPLAY_PLAYBACK
var audio: AppAudio                                     # the Snd bridge (created at boot; a no-op adapter under --no-audio or after a data error)
func go(mode: int, params: Dictionary = {}) -> void     # AppFlow.go + AppScenes.goto(screen id, params)
func bind_session(session: NetSession) -> void          # wires phase_changed / match_started / launch_aborted / kicked / match_ended / desync_detected / net_error
func quit_game() -> void                                # settings.flush(); AppCrashReporter.end_session(); get_tree().quit()

# game/src/app/app_scenes.gd     (autoload "AppScenes")
enum Layer { BACKDROP = 0, SCREEN = 1, OVERLAY = 2, FADE = 3, DEBUG = 4 }     # CanvasLayer indices 0 / 10 / 40 / 90 / 100
signal screen_changed(id: StringName)
var screen: UiScreen                                    # current top screen
var dialogs: UiDialogStack
func layer_root(layer: int) -> Control                  # UiLayerRoot (BACKDROP returns the Node3D host via backdrop_host())
func backdrop_host() -> Node3D
func goto(id: StringName, params: Dictionary = {}, fade: bool = true) -> void   # replace the screen (fade out 0.18 s → exit → free → enter → fade in 0.22 s)
func push(id: StringName, params: Dictionary = {}) -> void                       # overlay screen above a live one (input to the lower screen is blocked)
func pop() -> void
func set_backdrop(n: Node3D) -> void
func clear_backdrop() -> void
func toast(text: String, severity: int = 0, actions: Array[Dictionary] = []) -> void   # actions: [{label_key: StringName, call: Callable}] — e.g. the unclean-exit toast (Open logs folder, Copy report, Watch recovered replay) and the auto-quality toast (Undo); a toast with actions stays 10 s
func modal(dlg: UiDialog) -> void
func set_theme(t: Theme) -> void                        # assigns to every UiLayerRoot (Pitfall 1)

# game/src/app/app_net.gd        (autoload "AppNet", process_priority = -100, process_mode ALWAYS)
signal session_changed(session: NetSession)             # null when a session ended
var session: NetSession
var events: AppEvents
func make_options() -> NetSessionOptions                # settings [net] + GameData.roster_ids()/data_hash + AppMatch factories (net.md §3.1)
func start_local_lobby() -> NetSession                  # Role.LOCAL held in Phase.LOBBY (skirmish setup)        [XR-20]
func start_local_from_config(config: Dictionary) -> NetSession   # tests / --autostart
func host_lan(lobby_name: String, password: String = "") -> NetSession
func join_lan(address: String, port: int = 27615, password: String = "") -> NetSession
func end_session() -> void                              # leave()/shutdown(), dispose match context, session_changed(null)
func is_multiplayer() -> bool                           # role HOST or CLIENT
# _process(): if session != null: var t := session.poll(); if match_ctx != null and phase in PLAYING/PAUSED/ENDED: events.dispatch(match_ctx.sim.take_events(), session.tick_alpha(), delta)
#             OS.low_processor_usage_mode is forced false while is_multiplayer() (net.md R10)

# ---- match glue ----------------------------------------------------------------------------------------------------------
class_name AppMatch extends RefCounted
static func default_rules() -> Dictionary               # net.md §7.2 defaults: start_credits 7500, unit_cap 150, superweapons true, fog true, shared_vision false, veterancy false
static func begin_build(config: Dictionary, with_view: bool = true) -> NetWorldJob   # returns an AppMatchJob (opts.world_builder)   [XR-12]
static func make_ai_thinker(pid: int, level: int, style: int, seed: int) -> Callable # AiFactory.make(...)  (opts.ai_factory)
static func validate_map(family: int, size: int, layout_players: int) -> String      # MapGenerator.validate_params(family, size, layout_players): "" = ok — the callable net expects as opts.map_validator (net XR-12)
static func make_context(session: NetSession, observer: bool = false) -> AppMatchContext   # builds the four ports and registers the event consumers (audio 10, ui 20)
static func result_summary(ctx: AppMatchContext) -> Dictionary   # for UiScreenEnd (4.9)

class_name AppMatchJob extends NetWorldJob
func _init(config: Dictionary, with_view: bool = true) -> void
func step(budget_us: int) -> bool                        # phases: SIM 0-50 % → VIEW 50-90 % (icons and material prewarm are inside the view's build) → AUDIO 90-100 % (Snd.begin_match starts at the beginning of VIEW; the banks load on threads, the job waits for Snd.is_match_ready()); async parts poll state, nothing blocks
func progress_pct() -> int
func error() -> String
func take_adapter() -> NetSimAdapter
func phase_name() -> String                              # "Generating terrain" … (text key for the loading screen)

class_name AppMatchContext extends RefCounted
var session: NetSession
var config: Dictionary                                   # session.config()
var local_pid: int                                       # -1 = observer / replay
var is_observer: bool
var is_replay: bool
var data: GameData
var roster: DefRoster                                    # local player's roster (or the observed player's)
var skin: UiSkin
var sim: UiSimPort
var view: UiViewPort
var net: UiNetPort
var audio: UiAudioPort
var stats: UiMatchStats
func dispose() -> void

class_name AppEvents extends RefCounted
func add_consumer(name: StringName, order: int, cb: Callable) -> void    # cb(records: PackedInt32Array, alpha: float, dt: float) -> void; stride-10 records [type, tick, x, y, a … f] (UiEv, sim_core §4.9); read-only, valid only during the callback
func remove_consumer(name: StringName) -> void
func dispatch(records: PackedInt32Array, alpha: float, dt: float) -> void   # each consumer once per frame in ascending `order`; nothing to clear afterwards (take() already emptied the buffer)

class_name AppAudio extends RefCounted                  # the app-side bridge to the `Snd` autoload (audio.md §3.1 / §3.11); widgets never call `Snd` (they use UiAudioPort); no-op adapter when `--no-audio` or audio failed to set up
signal caption(line_id: StringName, text: String, priority: int)     # Snd.announcement_started, re-emitted; the notifier shows it when audio/captions is on (5.13.1)
func setup() -> bool                                     # Snd.setup(); false = a data error made audio unusable → the game continues silent, one toast
func set_mode(mode: int) -> void                         # Snd.set_mode(MODE_*) on AppState.mode_changed: MENU 1, LOBBY 2, LOADING 3, MATCH 4, POST_MATCH 5 (BOOT 0 until the first menu)
func begin_match(config: Dictionary, local_pid: int, observer: bool, replay: bool) -> void   # builds SndMatchConfig (data, local pid / team, player_factions by pid, local roster id, MapData family / biome, seed) → Snd.begin_match
func load_progress() -> float                            # Snd.load_progress(); is_match_ready() ends the AUDIO phase of AppMatchJob
func attach_world(world_root: Node3D) -> void            # after ViewWorld.build_async: Snd.attach_world (needs the game Camera3D current in that viewport)
func frame(session: NetSession, view: UiViewPort, records: PackedInt32Array, alpha: float, dt: float) -> void   # AppEvents consumer (order 10): Snd.set_camera(pose from UiViewPort.listener_pose()) → Snd.on_events(world, records, alpha) → Snd.on_frame(world, alpha, dt); `world` is read here, in app/, never in ui/
func end_match(result: int) -> void                      # Snd.end_match(SndMatchConfig.RESULT_*) + detach_world
func apply_settings(store: AppSettingsStore) -> void     # SndSettings.load_from(ConfigFile of [audio] + [access]) → Snd.apply_settings(s); audio must not write the file (single writer, 5.20.1)
func set_time_scale(x: float) -> void                    # replays: Snd.set_time_scale

class_name AppRelaunch extends RefCounted                # `video/renderer` (QA-XR-13) cannot change at runtime: restart with `--rendering-method`
static func supported() -> bool                          # not headless, not the editor, executable path exists
static func requested_method(store: AppSettingsStore) -> String   # "" (auto = project default), "forward_plus", "mobile", "gl_compatibility"
static func needed(store: AppSettingsStore, args: AppLaunchArgs) -> bool   # requested != RenderingServer.get_current_rendering_method() ∧ no `--rendering-method` already on the command line ∧ not `--renderer-relaunched`
static func relaunch(method: String, original_args: PackedStringArray) -> int   # OS.create_process(OS.get_executable_path(), original_args + ["--rendering-method", method, "--renderer-relaunched"]) then quit; the flag stops a loop if the method is unavailable (the second start logs the fallback and keeps the running method)

# ---- boot, logging, crash ---------------------------------------------------------------------------------------------
class_name AppLaunchArgs extends RefCounted
static func parse(args: PackedStringArray) -> AppLaunchArgs   # OS.get_cmdline_user_args()
var smoke: bool ; var selfcheck: bool ; var qa_job: String ; var screen: StringName ; var autostart: StringName ; var config_path: String ; var fixture: String
var ticks: int ; var quit_on_end: bool ; var fresh_settings: bool ; var no_audio: bool ; var speed_pct: int ; var faction: String
var extras: Dictionary                                   # unknown --key=value pairs (passed to screens, e.g. --preview=)

class_name AppBoot extends RefCounted
static func run(host: Node) -> void                      # coroutine; see 5.2 for the timeline

class_name AppInfo extends RefCounted                    # [QA-XR-14]
static func version() -> String                          # application/config/version, "0.1.0"
static func build_id() -> String                         # short build identifier ("dev" in the editor)
static func platform_string() -> String                  # "macOS 27.0 arm64", "Debian GNU/Linux 12 x86_64", "Windows 11 x86_64" (report headers, lobby build chip)
static func smoke_line(selftest: int) -> String          # "MERIDIAN_BOOT engine=… renderer=… os=… debug=… version=… build=… selftest=<ok|N>"; selftest = the number of failed Fp.self_test() checks

class_name AppLogSink extends RefCounted                 # installed as Log.sink at the first boot step [QA-XR-23]
func install() -> void
func emit(level: int, tag: StringName, msg: String) -> void   # "[E|W|I|D] <ms since start> [tag] message", 20 lines/s/tag with "(+N suppressed)", then print (lint-allow L006)

class_name AppLogger extends Logger
signal error_logged(entry: Dictionary)                   # {type, where, text, count, tick?}; emitted on the main thread (call_deferred)
func install() -> void                                    # OS.add_logger(self)
func uninstall() -> void
func tail(n: int = 60) -> PackedStringArray               # from Log.ring
func recent_errors() -> Array[Dictionary]
func storm() -> bool                                      # ≥ 50 errors in 5 s

class_name AppCrashReporter extends RefCounted           # [QA-XR-12]; the sentinel, the crash files and the toast
func start_session() -> Dictionary                        # writes user://.session; returns {} if the previous run ended cleanly, else that run's {pid, start_utc, version} (and has written crash_<utc>_unclean.txt)
func end_session() -> void                                # deletes .session (quit, WM_CLOSE_REQUEST)
func on_crash() -> void                                   # NOTIFICATION_CRASH (2012): best-effort logs/crash/crash_<utc>.txt
func report_header(phase: String) -> String               # the required fields of 5.20.3
func report_text(reason: int, detail: String) -> String   # header + reason + detail + Log.ring tail (fatal screen, Copy report)
func prune() -> void                                      # keep the newest 20 crash files

class_name AppCrash extends RefCounted
enum Reason { DATA_LOAD_FAILED = 0, WORLD_BUILD_FAILED = 1, ERROR_STORM = 2, NET_FATAL = 3, RENDERER = 4, DISK = 5, UNKNOWN = 15 }
static func show(reason: int, detail: String) -> void            # AppState.go(FATAL, {…}); also writes logs/crash/crash_<utc>_fatal.txt

class_name AppFileLayer extends RefCounted               # injectable file operations of the settings writer (tests interrupt the sequence)
func write_text(path: String, text: String) -> int
func rename(from: String, to: String) -> int
func remove(path: String) -> int
func exists(path: String) -> bool
func read_text(path: String) -> String

class_name AppTestBoot extends RefCounted
static func run(host: Node, args: AppLaunchArgs) -> void         # 5.2.3; prints APPTEST lines; exits 0 / 2 (data) / 3 (world) / 4 (desync) / 5 (timeout)
```

### 3.2 Ports

#### 3.2.1 `UiSimPort` — everything the UI reads from the simulation

`UiSimPortWorld` is the only class that touches `SimWorld`; the mapping of every member below onto `sim_core.md` fields and the production / power / strategic queries of `economy.md` §3.11 is table 3.2.4 (`ASSUMPTION(sim)`, `ASSUMPTION(production)`; requests `[XR-2]..[XR-4]`). Reads are as-of the end of the last executed tick and pure (no allocation per call except where an `out` buffer is passed).

```gdscript
class_name UiSimPort extends RefCounted
enum Rel { SELF = 0, ALLY = 1, ENEMY = 2, NEUTRAL = 3 }              # = SimWorld.Rel (sim_core.md §3.4.3)
enum Vis { SHROUD = 0, FOG = 1, VISIBLE = 2 }
enum Rule { OK = 0, UNKNOWN_OP = 1, BAD_PLAYER = 2, ELIMINATED = 3, MATCH_ENDED = 4, BAD_FIELD = 5, NO_ACTORS = 6, NO_TARGET = 7, WRONG_KIND = 8, NOT_AVAILABLE = 9, NO_PREREQ = 10, NO_CREDITS = 11,
            QUEUE_FULL = 12, BAD_SITE = 13, NO_VISION = 14, NOT_READY = 15, UNIT_CAP = 16, BLOCKED = 17, DISABLED = 18, NOT_ALLOWED = 19, BAD_ORDER = 20, INSIDE = 21 }
        # numerically = SimCommand.Err (sim_core.md §4.1): a check_* result and a CMD_REJECTED error share ONE text table `reject.<n>`; economy's RSN_* validation reasons (economy.md §4.1) are mapped onto these values by UiSimPortWorld (table 3.2.4) and travel as the `detail` of CMD_REJECTED
enum QueueState { RUNNING = 0, WAIT_FUNDS = 1, UNIT_CAP = 2, LOW_POWER = 3, PREREQ_LOST = 4, HELD = 5, EXIT_BLOCKED = 6, SHUTDOWN = 7 }   # the UI's view of economy's head-of-queue QS_*: RUNNING ← QS_ACTIVE / QS_EMPTY, HELD ← QS_HOLD, PREREQ_LOST ← QS_PAUSED_PREREQ, WAIT_FUNDS ← QS_PAUSED_FUNDS, UNIT_CAP ← QS_PAUSED_CAP, EXIT_BLOCKED ← QS_PAUSED_EXIT, SHUTDOWN ← QS_PAUSED_SHUTDOWN; LOW_POWER ← QS_ACTIVE while the player's power rate is below 100 % (economy PW_SHORTAGE)
enum PowerStatus { READY = 0, COOLDOWN = 1, LOCKED_PREREQ = 2, UNPOWERED = 3, NO_CREDITS = 4 }
enum SwStatus { NONE = 0, CHARGING = 1, READY = 2, WARNING = 3 }                                   # economy SW_NONE / SW_CHARGING / SW_READY plus WARNING (own strike inside its warning window: `pending_attack != 0`)
enum Construction { IDLE = 0, BUILDING = 1, READY_TO_PLACE = 2, PAUSED = 3 }
const DF_STRUCTURE: int = 1                          # def_flags() bits
const DF_COUNTS_FOR_CAP: int = 2                     # false for summons, decoys, drones: never announced as "unit lost"
const DF_MCV: int = 4
const DF_COLLECTOR: int = 8
const RF_FOG: int = 1
const RF_SUPERWEAPONS: int = 2
const RF_SHARED_VISION: int = 4
const RF_VETERANCY: int = 8

# ---- time / identity -----------------------------------------------------------------------------------------------------
func tick() -> int                                   # sim tick (20 per game second at 100 % speed)
func tick_alpha() -> float                           # 0..1 within the current tick (view-only float; session.tick_alpha())
func local_pid() -> int                              # -1 = observer/replay
func viewer_pid() -> int                             # whose fog/economy the HUD shows; == local_pid unless observing; -1 = omniscient observer
func set_viewer_pid(pid: int) -> void                # observers only
func player_count() -> int
func player_active(pid: int) -> bool                 # false when defeated/resigned
func team_of(pid: int) -> int                        # final team id (config.players[].team)
func color_of(pid: int) -> int                       # palette index 0..11
func name_of(pid: int) -> String
func roster_of(pid: int) -> DefRoster
func rel(a: int, b: int) -> int
func data() -> GameData
func def_flags(kind: int, def_idx: int) -> int       # DF_* bits from the GameData table selected by `kind` (structure tag; DefUnit.pop > 0 = counts for cap; MCV = DEPLOY_STRUCTURE ability; collector tag)
func table_idx(kind: int, def_idx: int) -> int       # identity in sim_core v2 (per-kind def indices = GameData table indices, decision 17); kept as the single seam if the reconcilers ever move to one dense space
func sim_def(kind: int, table_idx: int) -> int       # inverse of table_idx; identity in v2
func rule_flag(flag: int) -> bool
func map_w() -> int                                  # cells
func map_h() -> int
# ---- viewer economy ------------------------------------------------------------------------------------------------------
func credits() -> int
func harvested_total() -> int                        # monotonic (harvest + salvage); UI derives income/min
func power_supply() -> int                           # sum of positive power_supply_delta of powered structures
func power_demand() -> int                           # sum of negative deltas (as a positive number)
func unit_cap() -> int
func unit_count() -> int                             # non-structure entities (cap accounting)
func player_stats(pid: int, out: Dictionary) -> void # keys of 4.9.1 (units_built, units_lost, harvested, value_destroyed, …) from SimPlayer.st_*
# ---- entities ------------------------------------------------------------------------------------------------------------
func alive(eid: int) -> bool
func read(eid: int, out: UiEntityRow) -> bool        # false if gone; fields 4.4.1
func own_ids(kind_mask: int, out: PackedInt32Array) -> int     # viewer's entities, ascending id; kind_mask bits: 1 unit, 2 structure
func idle_units(out: PackedInt32Array) -> int                  # viewer's alive, on-map, selectable units with an empty order queue, ascending (SimWorld.find_idle_units)
func ids_of_def(kind: int, def_idx: int, out: PackedInt32Array) -> int    # viewer's alive entities of that (kind, def), ascending (SimWorld.find_by_def(kind, def_idx, pid, out))
func snapshot(out: UiEntitySnapshot) -> void         # SoA of everything the viewer may draw on the minimap: own + allied + currently visible enemies + remembered enemy structure ghosts (flag F_GHOST)
func visibility(cx: int, cy: int) -> int             # Vis for the viewer (omniscient viewer → VISIBLE)
func can_target(eid: int) -> bool                    # true for own / allied entities and for enemies passing world.fog.entity_visible for the viewer; false for remembered ghosts (they are approached with ATTACK_MOVE, 5.7.2)
func can_attack(shooter_eid: int, target_eid: int, force: bool) -> bool   # SimCombatSystem.can_attack (cursor + resolver)
func order_queue(eid: int, out: PackedInt32Array) -> int       # flattened [kind, x, y, target_id]*n for waypoint lines; returns n
func range_max(eid: int) -> int                      # effective maximum weapon range in sim units incl. research / deploy bonuses (combat's range_max_eff); 0 = unarmed — range rings
func detect_radius(eid: int) -> int                  # detector radius in sim units (5 cells, 6 for a deployed sensor mast); 0 = not a detector — detection ring
# ---- production / research (viewer) ---------------------------------------------------------------------------------------
func construction_state(out: PackedInt32Array) -> void         # out = [Construction, def_idx, progress_permille, ready_def_idx, eta_ticks, rate_pct, queue_state]   (queue_state = QueueState of the construction queue)
func construction_queue(out: PackedInt32Array) -> int          # structure defs queued BEHIND the head (bible: one player-wide construction queue); returns n
func producers(queue_kind: int, out: PackedInt32Array) -> int  # own completed producer structures of a DefEnums.QueueKind, ascending id
func queue_of(producer_eid: int, out: PackedInt32Array) -> int # queued unit defs in order (slot 0 = in production); returns length (≤ 5)
func queue_info(producer_eid: int, out: PackedInt32Array) -> void   # out = [progress_permille, eta_ticks, rate_pct, queue_state]   (QueueState of THIS producer's queue; precedence HELD > SHUTDOWN > PREREQ_LOST > EXIT_BLOCKED > UNIT_CAP > WAIT_FUNDS > LOW_POWER)
func research_state(out: PackedInt32Array) -> void             # out = [active_def or -1, progress_permille, eta_ticks, queue_state, queued_count, queued_def0, …]
func research_done(res_idx: int) -> bool
func check_build(struct_def: int) -> int                        # Rule (prereqs, construction queue not full, limit); credits are NOT checked (progressive payment)
func check_place(struct_def: int, ax: int, ay: int, orient: int = 0) -> int   # top-left footprint cell (ax, ay), orient 0-3 = 90° clockwise steps (0 unless the footprint is rotatable); Rule.OK or BAD_SITE (+ detail via place_reason)
func placement_result(struct_def: int, ax: int, ay: int, orient: int = 0) -> RefCounted   # SimPlacementResult (economy.md §3.4: reason + per-cell CF_* states) — opaque to the UI, forwarded to UiViewPort.update_placement for the ghost's per-cell colours
func footprint_rotatable(struct_def: int) -> bool               # DefStructureRules.Row.rotatable (economy §7.2: the Dock is the only rotatable footprint)
func place_reason() -> int                                      # last check_place failure: 1 outside radius, 2 blocked, 3 shoreline, 4 strategic limit, 5 shroud
func check_train(producer_eid: int, unit_def: int) -> int
func check_research(res_def: int) -> int
func build_radius_centers(out: PackedInt32Array) -> int         # [x0, y0, x1, y1, …] HQ centres (Relay does not extend, bible)
func sell_value(eid: int) -> int                                # credits refunded (sell_refund_bp × paid), 0 if not sellable
func repair_cost_per_second(eid: int) -> int
# ---- support powers / superweapon (viewer) ----------------------------------------------------------------------------------
func power_slot(power_def: int) -> int                          # 0..2 = index in the viewer's roster powers (orders the dock and the F5-F7 hotkeys; USE_POWER itself carries the power index); -1 if not in the roster
func power_status(power_def: int) -> int                        # PowerStatus
func power_ready_tick(power_def: int) -> int
func power_total_cooldown_ticks(power_def: int) -> int
func power_target_ok(power_def: int, x: int, y: int) -> bool    # DefPower.target_vision vs REAL vision
func sw_status() -> int                                         # SwStatus
func sw_def() -> int                                            # DefSuperweapon index of the viewer's roster
func sw_charge_permille() -> int
func sw_ready_tick() -> int
func sw_launcher_eid() -> int
func strategic_warnings(out: PackedInt32Array) -> int           # stride 12 [id, owner, kind (WK_*: 0 superweapon, 1 power, 2 scan), src_idx, x, y, x2, y2, radius, width, angle, exec_tick]*n — only the warnings whose `affected_mask` has the viewer's bit (bible: "visible to affected players and cannot be hidden by fog or decoys"; economy §5.16: the owner, the owner's team, or any player with an entity inside the zone + 3 cells); flattened by the adapter from SimStrategicSystem.warnings_affecting(pid, out); the viewer's own and allied strikes are always listed
# ---- map ------------------------------------------------------------------------------------------------------------------
func passable(cx: int, cy: int, move_class: int) -> bool         # MapData.passable(cx, cy, mc): LIVE nav weight of the class's small-hull profile (structures and the map border included; terrain is public knowledge, so no fog rule)
func deposit_at(cx: int, cy: int) -> int                       # resource cell under the pointer (v2.1: deposits are map cells, not entities). Fog-honouring: the current amount when the cell is visible, the static MapData.deposit_max (> 0) when merely explored, 0 otherwise — it never reveals depletion in the dark
# ---- events (called by AppEvents only) ---------------------------------------------------------------------------------
func take_events() -> PackedInt32Array                          # world.events.take(): stride-10 records [type, tick, x, y, a, b, c, d, e, f] (sim_core.md §4.9); the fixture returns the scripted events due since the last call
```

#### 3.2.2 `UiViewPort` — everything the UI needs from the 3D presentation

The production adapter `UiViewPortWorld` wraps the classes of `render.md` (`ViewWorld`, `ViewCamera`, `ViewPicker`, `ViewSelection`, `ViewHealthBars`, `ViewLines`, `ViewPlacementGhost`, `ViewRangeRings`, `ViewFloatText`, `ViewMinimapSource`, `ViewIconBake`, `ViewStyle`, `ViewQuality`); mapping table 3.2.5. **The view owns every 3D interaction visual** (selection rings and brackets, health bars, rally / order lines, placement ghost, range rings, strategic warning zones, remembered-structure ghosts, floating "+$" text — `render.md` §3.7/§5.10); the UI only *drives* them through this port. The UI drives the camera too: it sets `ViewCamera.auto_input = false` (render.md §3.3) and calls the rig's methods, so keyboard, edge scroll, wheel and orbit obey the UI's keymap, modals and focus rules.

```gdscript
class_name UiViewPort extends RefCounted
signal camera_changed()                                       # ViewCamera.view_changed or a focus move: refresh the minimap quad (≤ 30 Hz)
signal icon_ready(key: StringName)                            # ViewIconBake.icon_ready
signal quality_auto_changed(preset: int, reason: String)      # ViewQualityAuto.on_change → the UI shows a toast
const PICK_UNITS: int = 1                                     # = ViewPicker.PICK_* (render.md §3.7)
const PICK_STRUCTURES: int = 2
const PICK_WRECKS: int = 4
const PICK_OWN: int = 8
const PICK_ENEMY: int = 16
const PICK_NEUTRAL: int = 32
const PICK_AIR: int = 64
const PICK_GHOSTS: int = 128
const PICK_ANY: int = 0xFF
# ---- camera (UI-driven) ------------------------------------------------------------------------------------------------
func camera() -> Camera3D
func listener_pose() -> Dictionary                             # {focus: Vector3, basis: Basis, height: float} from ViewCamera.current_focus() / camera.global_basis / current_height() — what AppAudio hands to Snd.set_camera (audio.md §3.2)
func set_camera_margins(left: float, top: float, right: float, bottom: float) -> void   # ViewCamera.view_margin_px: HUD-occluded PHYSICAL pixels (logical × content_scale_factor); focus_on centres in the free area
func pan_screen(dir: Vector2, delta: float) -> void           # dir.y = -1 → toward the top of the screen
func rotate_yaw(deg: float) -> void
func tilt(deg: float) -> void
func zoom_by(steps: float, cursor: Vector2) -> void           # > 0 zooms in; drifts toward the cursor ground point
func focus_on_sim(x: int, y: int, instant: bool = false) -> void
func reset_camera_orientation() -> void
func camera_state() -> Dictionary                             # {focus_x, focus_z, yaw, zoom, pitch_bias} (bookmarks)
func set_camera_state(s: Dictionary, instant: bool = false) -> void   # ViewCamera.snap_to / focus_on
func set_camera_smoothing(on: bool) -> void                   # off under reduce_motion (A-09): pan/zoom/rotation smoothing constants → instant [XR-13]
func screen_to_ground(p: Vector2) -> Vector3                  # Vector3.INF on miss
func frustum_ground_quad() -> PackedVector2Array              # the 4 viewport corners as normalised map coordinates (4 × screen_to_ground, clamped) — the minimap camera polygon
# ---- picking (ViewPicker: hidden-by-fog, contained and camouflaged entities are never returned) ---------------------------
func pick(screen: Vector2, filter: int = PICK_ANY) -> int     # entity id or -1; ≈ 60-90 µs
func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int   # fills `out`; ≈ 1.2 ms per call for 400 entities → the UI calls it on release and at ≤ 15 Hz while dragging
func pick_ground(screen: Vector2) -> Vector3
func entity_screen_rect(eid: int) -> Rect2                    # projected pick volume in viewport px (tooltips, same-type-on-screen)
func entity_world_pos(eid: int) -> Vector3                    # interpolated
func world_to_sim(p: Vector3) -> Vector2i                     # the single float→int step (5.8.2)
func sim_to_world(x: int, y: int) -> Vector3                  # includes terrain height
# ---- interaction visuals owned by the view --------------------------------------------------------------------------------
func set_selection(ids: PackedInt32Array) -> void             # ViewSelection.set_selection (rings / brackets, model rim); called on every selection change
func set_hover(eid: int) -> void                              # -1 clears
func set_health_bar_mode(mode: int) -> void                   # ViewHealthBars.Mode: 0 never, 1 selected, 2 damaged (default), 3 always
func set_range_rings(ids: PackedInt32Array) -> void           # ViewRangeRings.show_for (≤ 12 rings); empty hides
func set_rally_sources(structure_ids: PackedInt32Array) -> void      # ViewLines: selected producers
func set_order_sources(unit_ids: PackedInt32Array) -> void           # ViewLines: selected units' queued orders (≤ 32 units × 8 waypoints)
func begin_placement(struct_def: int) -> bool                 # ViewPlacementGhost.show_structure + show_build_radius(true) + range ring for defenses
func update_placement(ax: int, ay: int, result: RefCounted, orient: int = 0) -> void   # snaps to the cell grid; `result` is the SimPlacementResult of UiSimPort.placement_result (per-cell colours)
func end_placement() -> void                                  # hide_ghost + build radius + ring
func float_text(text: String, sim_x: int, sim_y: int, color: Color) -> void   # ViewFloatText.popup — UI-originated texts only (the viewer's sell / refund "+$n" from CASH events); harvest / salvage income "+$" is the view's own
func set_float_font(font: Font) -> void                       # ViewFloatText.font
# ---- minimap sources (the widget itself is UiMinimap) -----------------------------------------------------------------------
func minimap_texture() -> Texture2D                           # ViewMinimapSource.texture: one texel per cell, baked once per map
func minimap_material() -> Material                           # ViewMinimapSource.make_material(true): terrain + this viewer's fog on a TextureRect; the fixture returns a plain material
# ---- icons, models, backdrops (ViewIconBake / ViewModelBuilder) ---------------------------------------------------------
func request_icon(def_id: String, roster_id: String, size: int) -> Texture2D   # cached texture or a flat placeholder; queues a bake (max 1 per frame); emits icon_ready(key). size: 0 ICON 128x96, 1 PORTRAIT 384x288, 2 CARD 188x124, 3 BANNER 304x152 (2 and 3 requested in [XR-19]; until then the UI crops 0/1 to the slot, "cover" mode)
func icon_key(def_id: String, roster_id: String, size: int) -> StringName
func make_model_node(def_id: String, roster_id: String, team_index: int) -> Node3D   # ViewModelBuilder.get_model + ViewMaterials: origin on the ground plane, for the Field Manual turntable
func prewarm() -> void                                        # bake one throw-away icon behind the splash: pays the 2.6-2.8 s cold Metal pipeline compile once
static func for_menus() -> UiViewPort                          # menu-mode adapter: recipe book, model builder, materials, icon baker, showcase, palette, quality — no ViewWorld / SimWorld required
func showcase(faction_code: String) -> Node3D                 # menu / lobby backdrop (terrain mood + hero model + dust); the UI orbits its camera [XR-19]
# ---- quality, palette, accessibility --------------------------------------------------------------------------------------
func apply_quality(cfg: ConfigFile) -> void                   # ViewQuality.from_settings(cfg, presets) → ViewWorld.apply_quality (live; terrain re-bake only when subdivision changed)
func quality_recommend() -> int                               # ViewQuality.recommend: first-run preset from the adapter type and renderer
func set_cvd_palette(on: bool) -> void                        # local rendering of the team-colour ids with the CVD-safe set (the ids are identical on every client, `art_direction.md` R-21): ViewStyle.player_color(id, cvd) / team_uniform; until the view adopts art R-1 the adapter maps it to ViewTeamColors.set_mode (5.19.3)
func team_color(index: int) -> Color                          # ViewStyle.player_color(index, cvd_active): the lobby swatch, the minimap blip and the 3D team colour are the same colour
func set_high_contrast(on: bool) -> void                      # thicker rings, unit outlines, larger health bars [XR-14]
func px_per_metre() -> float                                  # screen pixels per world metre at the camera focus (ViewCamera): below 18 = strategic zoom (class-glyph markers, `art_direction.md` R-18) [XR-19]
func project_points(sim_xy: PackedInt32Array, out: PackedVector2Array) -> void   # bulk sim units [x0, y0, x1, y1, …] → viewport px (terrain height included; off-screen points are returned as computed, the caller culls); ≈ 1 µs per point
func bake_map_preview(map: MapData) -> Texture2D              # lobby preview: ViewMinimapSource.bake(ViewTerrainSource.from_map(map), style.look_for_map(map.biome, map.family)) — 21-42 ms at 192², synchronous on the calling thread [XR-31]
```

`UiPickData` / `UiPicking` (4.4, 2.5) survive only as the **fixture adapter's** picking implementation (the spike's ray-vs-sphere and `unproject_position` box select, 92-127 µs); production picking is `ViewPicker`, whose tie rules are: smallest ray parameter, ties (< 0.01 m) prefer non-wreck over wreck, unit over structure, lower id.

#### 3.2.3 `UiNetPort`, `UiAudioPort`

```gdscript
class_name UiNetPort extends RefCounted
func submit(cmd: PackedInt32Array) -> bool                   # cmd = the int array built by UiCmdCodec / SimCmd ([op, fields…, ids…], no pid); NetSession.submit_command(cmd). false = refused (not playing / larger than 1024 ints / queue full / observer); never blocks
func can_submit() -> bool
func local_pid() -> int
func tick() -> int
func is_observer() -> bool
func pending_count() -> int                                   # commands queued locally, not yet sent (≤ 256)
func request_pause(want_paused: bool) -> int                  # NetProtocol.PauseError (0 = sent)
func surrender() -> bool                                      # NetSession.surrender() = submit_command([RESIGN, ResignReason.SURRENDER])
func send_chat(text: String, team_only: bool) -> void
func send_map_ping(cell_x: int, cell_y: int) -> void
# UiNetPortSession: forwards to NetSession (the pid is stamped by net from the connection; sim_core v2.1 §4.8 and net.md §5.5 carry the same PackedInt32Array, so no conversion layer exists).
# UiNetPortRecorder: appends every submitted array to `sent: Array[PackedInt32Array]` (tests compare UiCmdCodec.describe(cmd) strings and the raw ints).
# UiNetPortNull: can_submit() == false (observers, replays, main-menu showcase)

class_name UiAudioPort extends RefCounted                     # thin mirror of the `Snd` facade (audio.md §3.1); UI-INITIATED cues only — gameplay announcer lines, alarms and sim-event cues are event-driven inside audio (audio.md §3.11)
signal caption(line_id: StringName, text: String, priority: int)     # Snd.announcement_started (always emitted; shown when audio/captions is on)
enum Order { MOVE = 0, ATTACK = 1, GUARD = 2, DEPLOY = 3, CAPTURE = 4, REPAIR = 5, LOAD = 6, UNLOAD = 7, HARVEST = 8, STOP = 9, SCATTER = 10, SELL = 11 }   # = SndUnitResponse.Order
const CLICK := &"snd.ui.click"; const HOVER := &"snd.ui.hover"; const CONFIRM := &"snd.ui.confirm"; const BACK := &"snd.ui.back"; const TAB := &"snd.ui.tab"      # the cue ids of 6.3.1, all from audio.md §4.8
const TOGGLE_ON := &"snd.ui.toggle_on"; const TOGGLE_OFF := &"snd.ui.toggle_off"; const SLIDER_TICK := &"snd.ui.slider_tick"; const ERROR := &"snd.ui.error"
const QUEUE_ADD := &"snd.ui.queue_add"; const QUEUE_HOLD := &"snd.ui.queue_hold"; const PLACE_OK := &"snd.ui.place_ok"; const PLACE_FAIL := &"snd.ui.place_fail"
const SELL_MODE := &"snd.ui.sell_mode"; const REPAIR_MODE := &"snd.ui.repair_mode"; const WAYPOINT := &"snd.ui.waypoint"; const RALLY_SET := &"snd.ui.rally_set"
const GROUP_SET := &"snd.ui.group_set"; const GROUP_RECALL := &"snd.ui.group_recall"; const MINIMAP_CLICK := &"snd.ui.minimap_click"; const MINIMAP_PING := &"snd.ui.minimap_ping"
const ALERT := &"snd.ui.alert"; const NOTIFY := &"snd.ui.notify"; const CHAT := &"snd.ui.chat"; const MENU_TRANSITION := &"snd.ui.menu_transition"
const LOBBY_JOIN := &"snd.ui.lobby_join"; const LOBBY_LEAVE := &"snd.ui.lobby_leave"; const LOBBY_READY := &"snd.ui.lobby_ready"; const LOBBY_COUNTDOWN_TICK := &"snd.ui.lobby_countdown_tick"; const LOBBY_START := &"snd.ui.lobby_start"
func ui(id: StringName, gain_db: float = 0.0) -> void        # Snd.ui(&"snd.ui.*"): ids are the UiAudioPort constants of 6.3.1
func announce(line: StringName) -> bool                       # UI / lobby originated lines only (e.g. &"player_disconnected" from the lobby); NEVER for events the sim emits
func unit_selected(def_idx: int, is_structure: bool, count: int) -> void   # Snd.unit_selected — once per COMMITTED selection change (mouse release / key), def = primary (highest tier, ties lowest def index), per-kind def index
func unit_ordered(order: int, def_idx: int) -> void           # Snd.unit_ordered(Order, primary def)
func order_denied(def_idx: int, is_structure: bool = false) -> void   # Snd.order_denied — UI pre-check refusals only (the sim's ORDER_FAILED / CMD_REJECTED are voiced by audio itself)
func set_time_scale(x: float) -> void                         # replays (Snd.set_time_scale)
func captions_enabled() -> bool                               # Snd.settings().captions
# UiAudioPortSnd forwards to the `Snd` autoload; UiAudioPortNull ignores everything; UiAudioPortRecorder records `[name, args]` for tests. Session-level calls (setup, set_mode, begin_match, on_events, set_camera, end_match) are AppAudio's, not the port's.
```

#### 3.2.4 `UiSimPortWorld` mapping (what every read is backed by; rows tagged *production* / *power* / *combat* depend on those domains' read helpers, requests `[XR-2]..[XR-4]`)

| `UiSimPort` member | Backed by (`sim_core.md` v2 unless stated) | Note |
|---|---|---|
| `tick()`, `tick_alpha()` | `world.tick`; `session.tick_alpha()` | net pauses by not calling `step()` (sim_core §3.4.2: no sim-level pause), so `tick` freezes and every HUD countdown with it |
| `player_active/team_of/color_of/name_of/roster_of` | `world.players[pid]`: `is_player_active(pid)` (`eliminated == 0`), `team`, `color`, `name`, `roster_idx` → `GameData` roster | pids follow the config; vacant pids are pre-eliminated |
| `rel(a, b)` | `world.rel(a, b)` | `Rel` enum identical (SELF 0, ALLY 1, ENEMY 2, NEUTRAL 3) |
| `credits()`, `unit_cap()`, `unit_count()` | `players[v].credits`, `rules.unit_cap`, `players[v].unit_count` (cap weight) | |
| `power_supply/demand()` | `players[v].power_supply` / `power_demand` (kernel mirrors written by the power domain) | the bar and the `EVT_POWER_SHORTAGE` edge agree because both read the power domain's totals |
| `harvested_total()` | `players[v].st_credits_earned` | HARVEST + SALVAGE reasons only (sim_core §3.4.7) |
| `player_stats()` | `st_units_built/lost/killed`, `st_structs_built/lost/killed`, `st_credits_earned/spent`, `st_damage_dealt/taken`, `st_cmds`, `st_peak_units`, the count of researched entries (economy); four requested counters (4.9.1) | |
| `alive/read/own_ids/idle_units/ids_of_def` | `world.is_alive(id)`, `world.get_entity(id)`, `own_ids(v)` / `units_of(v)` / `structures_of(v)`, `find_idle_units(v, out)`, `find_by_def(kind, def_idx, v, out)` | `UiEntityRow` fill rules below |
| `snapshot()` | `world.entities_visible_to(v, out)` plus a `by_id` loop | fog-honouring by construction; observers loop `world.entities` |
| `visibility(cx, cy)`, `can_target` | `world.fog.cell_visible / cell_explored(v, cx, cy)`, `world.fog.entity_visible(v, e)` | remembered structure ghosts: `SimFogApi.ghosts(pid)` (records `{eid, def_idx, owner, x, y, facing, hp_pct, seen_tick}`), `ghost_version(pid)` as the change gate (the minimap feed rebuilds ghost dots only when it changes) and `decoy_identified(pid, e)` (`sim_core.md` §3.3.2; empty defaults until the vision domain overrides them) |
| `can_attack(shooter, target, force)` | `SimCombatSystem.can_attack(world, shooter, target, force)` (combat §3.4, "UI cursor / command validation") | `force` mirrors `ATTACK` flag bit0 |
| `range_max`, `detect_radius` | `SimCombatSystem.range_max_eff(world, e)` (combat §3.7); the detector radius from the def / `SimCompVision` (abilities §3.4) | range rings (the view draws them from ids) and the detection ring |
| `order_queue(eid)` | `SimEntity.orders` (`type`, `x`, `y`, `target_id`) | waypoint lines |
| `construction_*`, `producers`, `queue_of`, `queue_info`, `research_*` | *production*: `SimProductionSystem` / `SimPlayerEcon` / `SimCompProd` through the helpers of economy §3.3 and §3.11 (`construction_state`, `queue_of`, `q_item_progress_bp`, `q_rate_bp`, `research_active`, `research_done`, `q_buildable_*`) | progress permille = `q_item_progress_bp / 10`; ETA from the resolved ticks and the rate; `queue_state` from the head `QS_*` of the queue |
| `check_build/place/train/research` | *production*: `can_queue_structure`, `can_queue_unit`, `can_queue_research`, `SimPlacement.validate(world, pid, s_idx, cx, cy, rot, out)` (economy §3.3-3.4; they return `RSN_*`) | one table in `UiSimPortWorld` maps `RSN_*` to `Rule`: `NOT_AVAILABLE`, `LOCKED`, `FEATURE_OFF` → NOT_AVAILABLE; `PREREQ`, `NO_HQ` → NO_PREREQ; `QUEUE_FULL`; `NO_CREDITS`; `UNIT_CAP`; `OUT_OF_RADIUS`, `TERRAIN`, `STRUCTURE_BLOCK`, `UNIT_BLOCK`, `NEEDS_SHORE`, `DEPOSIT`, `DEBRIS`, `APRON`, `STRATEGIC_LIMIT` → BAD_SITE; `NO_VISION`, `NOT_EXPLORED` → NO_VISION; `COOLDOWN`, `NOT_READY`, `NOT_CHARGED` → NOT_READY; `NO_POWER` → BLOCKED; anything else NOT_ALLOWED. The `RSN_*` value is kept for tooltips and gives `place_reason()`: 1 `OUT_OF_RADIUS`, 2 the site-blocking reasons (`TERRAIN`, `STRUCTURE_BLOCK`, `UNIT_BLOCK`, `DEPOSIT`, `DEBRIS`, `APRON`), 3 `NEEDS_SHORE`, 4 `STRATEGIC_LIMIT`, 5 `NOT_EXPLORED`. The sim re-runs the same checks on execution and reports `err` + `detail` in CMD_REJECTED (`[XR-3]` asks economy to publish this table so both sides use one) |
| card cost / time / power | `players[v].view` = `DefPlayerView` and `SimProductionSystem.q_unit_cost / q_unit_ticks / q_structure_cost / q_structure_ticks` (post-modifier prices) | the UI never recomputes stats |
| `build_radius_centers` | viewer's ACTIVE HQ structures (`SimPlacement` 8-cell rule) | a Relay does not extend it (bible) |
| `sell_value`, `repair_cost_per_second` | `SimEntity.paid_cost` × the sell refund percentage (economy §5.3); `SimEconomySystem.repair_basis_cost` | |
| `power_slot/status/ready_tick/total_cooldown/target_ok` | *power*: `SimPlayerEcon` slots P0-P2 (`SimPowerSlot.def_idx`, `ready_tick`), `power_ready_tick(pid, p_idx)`, `power_target_ok(pid, p_idx, x, y)` (economy §3.11), prerequisites through the tech counters | the slot (0-2) orders the dock and the hotkeys; `USE_POWER` carries the power index |
| `sw_status/def/charge/ready_tick/launcher_eid` | *power*: slot 3 `SimPowerSlot` (`sw_state` SW_NONE / CHARGING / READY, `charge`, `recharge_ticks`, `launcher_id`, `pending_attack` → WARNING) via `sw_status(pid)`, `sw_ready_tick(pid)`, `sw_launcher_eid(pid)` | `SwStatus` numbers as in 4.1 |
| `strategic_warnings` | *power*: `SimStrategicSystem.warnings_affecting(pid, out)` (economy §3.6) flattened to stride 12 | the query, not the `EVT_WARNING` event, decides which zones and ribbons the viewer gets |
| `passable/map_w/map_h` | `world.map` (`MapData.passable`, `w`, `h`; `terrain_movement.md` §3.3) | |
| `deposit_at` | `world.map.deposit_at(idx)` / `deposit_max[idx]` gated by `world.cell_visible / cell_explored(v, cx, cy)` | the fog rule lives in the adapter |
| `take_events` | `world.events.take()` | one call per rendered frame |

`UiEntityRow` fill rules (`SimEntity` → row): `kind` ← UI classification of `SimEntity.kind` and `owner` (UNIT 0, STRUCTURE 1, WRECK 2, NEUTRAL_STRUCTURE 3 = a STRUCTURE with owner −1 or a NEUTRAL that is not a deposit, there is no deposit kind: deposits are map cells, read with `deposit_at`; ZONE is never listed); `def_idx` ← `SimEntity.def_idx` (per-kind index); `F_STRUCT` ← `kind == STRUCTURE`; `F_DEPLOYED` ← `SimFlags.F_DEPLOYED` (bit 24); `F_CAMO` ← `F_CLOAKED` (26); `F_EMP` ← `F_EMP_SHUT` (37) or `F_WEAPONS_OFF` (22); `F_UNPOWERED` ← structure ∧ ¬`F_POWERED` (28); `F_LOADED` ← `F_INSIDE` (2); `F_GARRISONED` ← `F_GARRISONED` (39); `F_DECOY` ← `F_DECOY` (6) ∧ identified by the viewer (`decoy_identified`, `render.md` request 10); `F_SUPPRESSED` ← `F_SUPPRESSED` (38); `F_REPAIRING` ← `F_REPAIR_ON` (29); `F_SELLING` ← `F_SELLING` (30); `F_CONSTRUCTING` ← `F_UNDER_CONSTRUCTION` (40); `F_GHOST` ← the vision ghost list; `container` ← `container_id`; `paid_cost` ← `paid_cost`; `stance` ← `e.combat.stance` (0 aggressive · 1 defensive · 2 hold fire · 3 guard; no combat component → −1); `order_kind` ← `orders[0].type` (T_MOVE 16, T_PATROL 17 and T_FOLLOW 18 → 1, T_ATTACK 40 and T_FORCE_FIRE 44 → 2, T_ATTACK_MOVE 41 → 3, T_GUARD 42 → 4, T_HOLD 43 → 5, T_HARVEST 30 and T_RETURN_CARGO 31 → 6, T_REPAIR 33 → 7, a structure with a non-empty queue → 8, any other order → 15, empty → 0); `mode`, `cargo`, `ammo`, `squad`, `rally_*`, `queue_len`, `is_primary` ← the ability (`e.abil`, `cc.ext_mode`), cargo (`e.cargo`), combat (`ammo_of`, squad members) and production (`e.prod`: rally, queue length, primary flag) components (null-checked typed access, sim_core §4.5 rule 7).

#### 3.2.5 `UiViewPortWorld` mapping (what every member is backed by, `render.md`)

| `UiViewPort` member | Backed by | Note |
|---|---|---|
| `camera`, `pan_screen`, `rotate_yaw`, `tilt`, `zoom_by`, `focus_on_sim`, `reset_camera_orientation` (= `ViewCamera.reset_orientation`), `screen_to_ground` | `ViewWorld.camera` (`ViewCamera`, §3.3) methods of the same names | `auto_input = false` at match start; `ensure_input_actions()` never called |
| `set_camera_margins`, `listener_pose` | `ViewCamera.view_margin_px = Vector4(left, top, right, bottom)`; `listener_pose` = `current_focus()`, `camera.global_basis`, `current_height()` | physical px = logical × `content_scale_factor`; the pose feeds `Snd.set_camera` (`AppAudio`) |
| `camera_state` / `set_camera_state` | `current_focus / current_yaw_deg / current_height / current_pitch_deg` and `snap_to / focus_on` | bookmarks store the dictionary |
| `camera_changed` | `ViewCamera.view_changed` plus focus moves | throttled to 30 Hz |
| `frustum_ground_quad` | four `screen_to_ground` rays through the viewport corners, converted by `(p − map_origin) / map_size` | ≈ 40 µs |
| `pick`, `pick_box`, `pick_ground`, `entity_screen_rect`, `entity_world_pos`, `world_to_sim`, `sim_to_world` | `ViewWorld` methods of the same names (§3.1); filters = `ViewPicker.PICK_*` | the only picker in production |
| `set_selection`, `set_hover` | `ViewWorld.selection` (`ViewSelection`) | also drives the model rim (`u_state.y`) |
| `set_health_bar_mode` | `ViewWorld.health_bars.set_mode` | default 2 (damaged) |
| `set_range_rings` | `ViewWorld.range_rings.show_for / hide_all` | ≤ 12 rings |
| `set_rally_sources`, `set_order_sources` | `ViewWorld.lines` (`ViewLines`) | rebuilt ≤ 10 Hz by the view |
| `begin_placement`, `update_placement`, `end_placement` | `ViewWorld.ghost.show_structure(s_idx, recipe_id, style_id, rot)`, `.update_cursor(world_pos, result)`, `.show_build_radius`, `.hide_ghost`; defenses add `range_rings.show_preview` | recipe = `DefStructure.pres_recipe`, style = `ViewRecipeBook.style_for_roster(roster_id)`, world position from `sim_to_world(ax·1024 + fp_w·512, …)` |
| `float_text`, `set_float_font` | `ViewWorld.float_text.popup(...)`, `.font` | pool of 24 |
| `minimap_texture`, `minimap_material` | `ViewWorld.minimap` (`ViewMinimapSource.texture`, `make_material(true)`) | |
| `request_icon`, `icon_key`, `icon_ready` | `ViewWorld.icons` (`ViewIconBake.request(recipe_id, style_id, size) / is_ready / icon_ready`); menus use a standalone `ViewIconBake` | recipe = `DefBase.pres_recipe` of the def, style = `ViewRecipeBook.style_for_roster(roster_id)`; key = content hash + size |
| `make_model_node` | `ViewModelBuilder.get_model(recipe, style, scale_bp)` + `ViewMaterials.unit_material(style, NODE, team_index)` in a `ViewModelRig` | Field Manual turntable |
| `prewarm`, `showcase` | `ViewIconBake.prewarm()`, `ViewShowcase.create(faction_code, seed)` (`[XR-19]`) | |
| `apply_quality`, `quality_recommend`, `quality_auto_changed` | `ViewQuality.from_settings(cfg, presets)`, `ViewWorld.apply_quality`, `ViewQuality.recommend`, `ViewQualityAuto.on_change` | |
| `set_cvd_palette`, `team_color`, `set_high_contrast` | `ViewStyle.player_color(id, cvd)` / `team_uniform` (art R-21; until render adopts art R-1: `ViewTeamColors.set_mode / color`); high contrast `[XR-14]` | |
| `px_per_metre`, `project_points` | `ViewCamera` scale at the focus (the quantity behind the view's `CameraTier` thresholds); `ViewWorld.sim_to_world` + `Camera3D.unproject_position` per point | `[XR-19]` |
| `bake_map_preview` | `ViewMinimapSource.bake(ViewTerrainSource.from_map(map), ViewStyle.look_for_map(map.biome, map.family))` (`render.md` §3.4) | `[XR-31]` |
| (not a port member) `frame(dt, alpha, records)` | `ViewWorld.frame` — called by `AppNet` (3.0), never by a widget | |

### 3.3 Input, selection, commands

```gdscript
class_name UiInputController extends Node
signal select_box(rect: Rect2, mode: int)                      # mode: 0 replace, 1 add
signal select_click(pos: Vector2, mode: int, double: bool)     # mode: 0 replace, 1 toggle
signal context_click(pos: Vector2, mods: int)                  # RMB press in the world; mods = UiKeymap.MOD_* bits
signal armed_click(pos: Vector2, mods: int)                    # LMB while a command mode is armed
signal camera_pan(dir: Vector2, delta: float)
signal camera_rotate(dir: float, delta: float)                 # keyboard Q/E: dir = ±1, the rig applies rotate_speed × delta
signal camera_tilt(deg: float)                                 # PageUp/PageDown: ±1° per repeat
signal camera_orbit(yaw_deg: float, tilt_deg: float)           # MMB drag (5.5.2): already in degrees → view.rotate_yaw / view.tilt
signal camera_zoom(steps: float, cursor: Vector2)
signal action(id: StringName)                                  # a keymap action fired (exact match), 5.6
signal hover_changed(pos: Vector2, over_ui: bool)              # 30 Hz while the pointer moves
var enabled: bool                                              # false while a modal is open (mouse + keys)
var enabled_keys: bool                                         # false while a LineEdit has focus (5.5.8)
var edge_scroll: bool
var select_rect: UiSelectRect
var armed: int                                                 # UiModes.Armed
func tick(delta: float) -> void                                # called by UiScreenGame (P3a)
func cancel_gesture() -> void
static func edge_direction(p: Vector2, view: Rect2, margin: float = 6.0) -> Vector2   # pure
static func drag_exceeded(press: Vector2, cur: Vector2, threshold: float = 6.0) -> bool

class_name UiKeymap extends RefCounted
enum Context { GLOBAL = 1, MENU = 2, GAME = 4, OBSERVER = 8, LOBBY = 16, TEXT_ENTRY = 32 }
const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2
const MOD_ALT: int = 4
const MOD_META: int = 8
signal bindings_changed()
static func instance() -> UiKeymap
func load_defaults() -> void                                   # data/ui/keymap_defaults.json
func load_from(store: AppSettingsStore) -> void
func save_to(store: AppSettingsStore) -> void
func bindings(action: StringName) -> PackedInt32Array          # ≤ 2 packed keys (4.5.1); empty = unbound
func label(action: StringName) -> String                       # first binding, platform label: "Alt+Q" / "Option+Q" / "F5"
func conflicts(packed: int, contexts: int, ignore: StringName = &"") -> PackedStringArray
func bind(action: StringName, slot: int, packed: int, on_conflict: int) -> bool   # on_conflict: 0 refuse, 1 swap, 2 replace
func unbind(action: StringName, slot: int) -> void
func reset(action: StringName) -> void
func reset_all() -> void
func install(context: int) -> void                             # (re)builds InputMap for GLOBAL|context; frees Tab when GAME
func uninstall(context: int) -> void                           # restores ui_focus_next/prev
func matches(event: InputEvent, action: StringName) -> bool    # exact_match = true wrapper
func mods_of(event: InputEventWithModifiers) -> int            # MOD_* bits with the per-OS gesture mapping of 5.5.6
static func pack(ev: InputEventKey) -> int                     # physical_keycode | modifier mask (Godot KEY_MASK_*)
static func unpack(packed: int) -> InputEventKey

class_name UiSelection extends RefCounted
enum Mode { NONE = 0, UNITS = 1, STRUCTURES = 2, FOREIGN = 3 }
const MAX_SELECT: int = 500                                     # = maximum unit cap (rules.unit_cap ≤ 500)
signal changed(mode: int)
var ids: PackedInt32Array                                       # selection order (first = oldest)
var primary: int                                                # -1 if empty
var mode: int
var active_def: int                                             # active subgroup (drives portrait + ability bar); per-kind def index (units in UNITS mode, structures in STRUCTURES mode); default = highest (tier, cost)
func cycle_subgroup(direction: int = 1) -> void                  # Ctrl+Tab
func clear() -> void
func replace(new_ids: PackedInt32Array, port: UiSimPort) -> void      # filters to one Mode (units | structures | one foreign), caps at MAX_SELECT
func add(new_ids: PackedInt32Array, port: UiSimPort) -> void
func toggle(eid: int, port: UiSimPort) -> void
func remove(eid: int) -> void
func has(eid: int) -> bool
func size() -> int
func sorted_ids() -> PackedInt32Array                           # ascending copy (cached until the next change) — what commands carry
func prune(port: UiSimPort) -> bool                             # drops dead / foreign-owned / contained ids; returns changed; re-picks primary
func on_removed(eid: int, reason: int, successor_eid: int) -> void   # REMOVED / EV_DEATH hook (5.11.2); reason = REM_* (3 DEPLOYED, 4 CONSUMED …); successor_eid = the SPAWNED entity of reason DEPLOYED that pairs with this removal (same owner, same batch, paired by emission order, or `parent == eid`), else -1

class_name UiControlGroups extends RefCounted
signal changed(index: int)
func assign(index: int, ids: PackedInt32Array) -> void          # Ctrl+n
func add_to(index: int, ids: PackedInt32Array) -> void          # Ctrl+Shift+n
func recall(index: int, port: UiSimPort) -> PackedInt32Array    # alive members only; drops dead ids permanently
func count(index: int, port: UiSimPort) -> int
func centroid_sim(index: int, port: UiSimPort) -> Vector2i
func register_press(index: int, now_ms: int) -> bool            # true if this is the second press within 350 ms (double-tap → centre camera)

class_name UiBookmarks extends RefCounted
func set_slot(i: int, state: Dictionary) -> void                # 0..3
func get_slot(i: int) -> Dictionary                             # empty if unset

class_name UiModes extends RefCounted                            # armed command modes (5.7.2)
enum Armed { NONE = 0, ATTACK_MOVE = 1, GUARD = 2, SELL = 3, REPAIR = 4, RALLY = 5, WAYPOINT = 6, FORCE_FIRE = 7, POWER = 8, SUPERWEAPON = 9,
             PLACE = 10, ABILITY = 11, PING = 12, MOVE = 13, PATROL = 14, FOLLOW = 15 }
signal changed(armed: int, previous: int)
var armed: int
var waypoint_latch: bool                                         # W: every resolved intent is queued
var sticky: bool                                                 # input/sticky_modes
var arg: int                                                     # ability slot / power idx for ABILITY / POWER
func arm(mode: int, arg: int = -1) -> void                       # also switches the cursor (UiCursors.set_state) and plays UiAudioPort.CONFIRM (snd.ui.confirm)
func disarm() -> void
func consume(shift_held: bool) -> void                           # after one issued order: disarm unless sticky or Shift
func is_click_mode() -> bool                                     # LMB issues instead of selecting

class_name UiPicking extends RefCounted                          # pure maths on UiPickData — the FIXTURE adapter's picker and the reference for ViewPicker's rules (production picking is UiViewPort.pick / pick_box)
static func ray_pick(camera: Camera3D, pd: UiPickData, screen: Vector2, filter: int = 0xFF) -> int          # eid or -1 (filter = UiViewPort.PICK_*)
static func box_select(camera: Camera3D, pd: UiPickData, rect: Rect2, filter: int) -> PackedInt32Array

class_name UiSelectionActions extends RefCounted                 # 4.5/5.5.4 keyboard and menu selection commands
func setup(sim: UiSimPort, view: UiViewPort, selection: UiSelection, notifier: UiNotifier) -> void
func same_type_on_screen(kind: int, def_idx: int) -> PackedInt32Array   # own alive non-contained entities of that (kind, def) whose entity_screen_rect intersects the playfield
func same_type_on_map(kind: int, def_idx: int) -> PackedInt32Array
func all_military(on_screen_only: bool) -> PackedInt32Array      # tag combat minus service, not structures
func next_idle(direction: int) -> int                            # UiSimPort.find idle armed unit; centres the camera; -1 if none
func next_collector() -> int
func next_producer() -> int
func hq() -> int

class_name UiContextResolver extends RefCounted
static func resolve(sel: UiSelectionInfo, tgt: UiTarget, mods: int, armed: int) -> UiOrderIntent   # pure, deterministic (5.7)
static func cursor_for(intent: UiOrderIntent) -> int            # UiCursors.State
static func make_target(port: UiSimPort, view: UiViewPort, screen: Vector2, viewer_pid: int) -> UiTarget   # the only impure part: view.pick(screen, PICK_ANY) + view.pick_ground + port.read (+ port.deposit_at on a ground hit: an explored cell with a deposit becomes Kind.DEPOSIT, eid −1, x / y = the cell centre) → UiTarget

class_name UiCommandBus extends RefCounted
signal issued(kind: int, cmd: PackedInt32Array)                 # after a successful submit (feedback, tests); cmd = the int array that was sent
signal refused(kind: int, reason: int)                          # local pre-validation or port refusal; reason = UiSimPort.Rule or REFUSE_* below
const REFUSE_NOT_ALLOWED: int = 100                             # observer / not playing
const REFUSE_RATE: int = 101                                    # per-turn budget exceeded
const REFUSE_EMPTY: int = 102                                   # no eligible units
func setup(net: UiNetPort, sim: UiSimPort, view: UiViewPort, audio: UiAudioPort, feedback: UiFeedback) -> void
func dispatch(intent: UiOrderIntent) -> int                      # the primary intent, then its `extra` intents in order; returns the number of commands submitted (0 = refused)
# typed helpers used by widgets and tests (each builds the array through UiCmdCodec, pre-validates per 5.8.4, then submits):
func train(producer_eid: int, unit_def: int, count: int) -> bool                     # TRAIN (count 1..5)
func train_cancel(producer_eid: int, queue_index: int) -> bool                       # TRAIN_CANCEL: removes that queue slot; the head refunds what it was paid (the sim)
func queue_hold(queue_kind: int, producer_ids: PackedInt32Array, hold: bool) -> bool # UiCmdCodec.Hold: PRODUCER → QUEUE_HOLD (ids = producers), CONSTRUCTION → BUILD_HOLD, RESEARCH → RESEARCH_HOLD
func build_start(struct_def: int, count: int = 1) -> bool                            # BUILD_START
func build_place(struct_def: int, cx: int, cy: int, rot: int = 0) -> bool           # BUILD_PLACE; (cx, cy) = the footprint's top-left CELL (whole cells, not sub-cell units), rot 0-3 = clockwise quarter turns
func build_cancel(queue_index: int) -> bool                                          # BUILD_CANCEL (0 = the head, also a READY item)
func research(res_def: int) -> bool                                                  # RESEARCH
func research_cancel(queue_index: int) -> bool
func set_primary(producer_eid: int) -> bool                                          # SET_PRIMARY: the star on the queue strip (replaces the old UI-only pin)
func use_power(power_def: int, x: int, y: int, angle: int, target_eid: int = 0) -> bool   # USE_POWER; the `def` field = the power index p_idx (the sim derives the slot)
func launch_superweapon(x: int, y: int, angle: int) -> bool                          # LAUNCH_SUPERWEAPON
func sell(struct_ids: PackedInt32Array) -> bool                                      # SELL
func set_struct_repair(struct_ids: PackedInt32Array, mode: int) -> bool              # SET_STRUCT_REPAIR: 0 off / 1 on / 2 toggle
func undeploy_hq(hq_ids: PackedInt32Array) -> bool                                   # UNDEPLOY_HQ (HQ → MCV)
func set_rally(producer_ids: PackedInt32Array, x: int, y: int, target_eid: int = 0, clear: bool = false) -> bool   # SET_RALLY
func stance(ids: PackedInt32Array, stance: int) -> bool                              # SET_STANCE: 0 aggressive / 1 defensive / 2 hold fire / 3 guard
func hold(ids: PackedInt32Array) -> bool                                             # HOLD (hold position is an ORDER, not a stance)
func simple(kind: int, ids: PackedInt32Array) -> bool                                # STOP / SCATTER / RETURN_CASH (RETURN_CARGO, nearest refinery) / SCUTTLE
func follow(ids: PackedInt32Array, target_eid: int, queued: bool = false) -> bool         # FOLLOW (v2.1 op 12): target = an own or allied unit, never a member of `ids`
func return_to_base(ids: PackedInt32Array, base_eid: int = 0, queued: bool = false) -> bool   # RETURN_TO_BASE with its target (v2.1): the clicked airfield / carrier, 0 = the nearest free pad or the carrier
func harvest(ids: PackedInt32Array, cell_x: int, cell_y: int, queued: bool = false) -> bool   # HARVEST target 0 at the deposit cell's centre (v2.1: the sim takes the deposit cell nearest to x, y)
func deploy_toggle(ids: PackedInt32Array) -> bool                                    # DEPLOY (def −1: the sim routes an MCV to T_DEPLOY_MCV) for units not deployed, UNDEPLOY(slot) for units with F_DEPLOYED, split by the row flag → ≤ 2 commands
func use_ability(ids: PackedInt32Array, slot: int, target_eid: int = 0, x: int = -1, y: int = -1) -> bool   # USE_ABILITY op 0 (start)
func cancel_ability(ids: PackedInt32Array, slot: int) -> bool                        # USE_ABILITY op 1
func set_mode(ids: PackedInt32Array, slot: int, mode: int) -> bool                   # SET_MODE with an explicit target mode index (the UI never sends −1 = cycle, so a mixed group ends in one mode)
func set_autocast(ids: PackedInt32Array, slot: int, on: bool) -> bool               # SET_AUTOCAST
func unload(carrier_ids: PackedInt32Array, all: bool = true, passenger_eid: int = 0) -> bool   # UNLOAD: one command per carrier, drop point = the carrier's own position (the exit-cell search starts there, abilities §5.10.2)
func begin_turn_budget(now_tick: int) -> void                    # resets the per-turn counter (40 commands / turn, 5.8.3)

class_name UiCmdCodec extends RefCounted                        # the ONLY file that names sim ops; every builder calls the SimCmd builder of the same name (sim_core.md §3.5) and returns the PackedInt32Array that net carries (6.1)
enum Queue { REPLACE = 0, APPEND = 1 }                          # = SimOrder.QM_*; QM_FRONT (2) is never produced by the UI
enum Hold { PRODUCER = 0, CONSTRUCTION = 1, RESEARCH = 2 }      # which hold op a queue kind maps to
const MAX_IDS: int = 512                                        # id-list cap of an M_IDS op (sim_core §4.8); MAX_SELECT = 500 fits, so one user action is one command
static func move(ids: PackedInt32Array, x: int, y: int, queued: bool, flags: int = 0) -> PackedInt32Array   # (attack_move and patrol take the same flags) … one static builder per UI action of 6.1 (same names as the bus helpers); each is SimCmd.<op>(ids, fields in wire order) with Shift → mode = QM_APPEND
static func split_ids(ids: PackedInt32Array, max_ids: int = 512) -> Array[PackedInt32Array]    # ascending chunks (defensive: MAX_SELECT keeps every user action in one chunk)
static func world_to_sim(wx: float, wz: float, map_w_cells: int, map_h_cells: int) -> Vector2i    # 5.8.2
static func describe(cmd: PackedInt32Array) -> String           # "MOVE ids=[3,7,12] x=15360 y=30720 mode=1 flags=0": SimCmd.name_of(op), then the op's fields in SimCmd.layout_of order and the ids (test goldens, logs)
static func verify_against_sim() -> PackedStringArray           # contract check: every op the UI builds is SimCmd.is_known and its layout arity equals the one assumed here; empty = OK

class_name UiEv extends RefCounted                               # the ONLY file that names event codes and field offsets (6.2.1); record = [type, tick, x, y, a, b, c, d, e, f]
const STRIDE: int = 10
const I_TYPE := 0; const I_TICK := 1; const I_X := 2; const I_Y := 3; const I_A := 4; const I_B := 5; const I_C := 6; const I_D := 7; const I_E := 8; const I_F := 9
const SPAWNED := 1; const REMOVED := 2; const OWNER_CHANGED := 3; const CASH := 4; const CMD_REJECTED := 5; const ORDER_FAILED := 6; const PLAYER_ELIMINATED := 7; const MATCH_END := 8   # core registry
const DEATH := 208; const EMP := 213; const ATTACK_ALERT := 214                                                  # combat block (EV_DEATH, EV_EMP, EV_ATTACK_ALERT)
const MODE_CHANGED := 235; const ABILITY_USED := 236; const ABILITY_READY := 237; const LOADED := 240; const UNLOADED := 241; const UNLOAD_BLOCKED := 242; const GARRISON_CHANGED := 243; const SCAN_WARNING := 250; const BUFF_APPLIED := 259   # abilities block
const PLACE_REJECTED := 301; const STRUCTURE_READY := 302; const UNIT_PRODUCED := 305; const QUEUE_STATE := 306; const RESEARCH_COMPLETE := 307; const INSUFFICIENT_FUNDS := 309; const UNIT_CAP_REACHED := 310   # economy block
const POWER_SHORTAGE := 311; const POWER_RESTORED := 312; const STRUCTURE_SOLD := 314; const HQ_DEPLOYED := 317; const HQ_UNDEPLOYED := 318; const POWER_UNLOCKED := 400; const POWER_READY := 401; const POWER_ACTIVATED := 402
const WARNING := 404; const SW_READY := 405; const SW_CANCELLED := 406; const SW_EXEC_START := 407; const SW_IMPACT := 408; const SW_DONE := 409
static func by_name(name: StringName) -> int                    # lower-case trigger name of notices.json → code, −1 unknown (&"attack_alert" → 214)
static func name_of(code: int) -> StringName
static func count(records: PackedInt32Array) -> int             # records.size() / STRIDE
static func field(records: PackedInt32Array, i: int, slot: int) -> int   # slot = I_*; no allocation
static func death_owner(e: int) -> int                          # ((e >> 8) & 0xFF) − 1 (EV_DEATH field e)
static func death_killer_pid(e: int) -> int                     # (e & 0xFF) − 1
static func death_flags(c: int) -> int                          # (c >> 8) & 0xFF (EV_DEATH field c: 1 wreck, 2 crash, 4 decoy, 8 summoned, 16 structure, 32 occupants, 64 unit, 128 aircraft)
static func verify_against_sim() -> PackedStringArray           # compares every code with the SimEvent / combat / abilities / economy constants once those classes exist; empty = OK

class_name UiFeedback extends RefCounted
func setup(overlay: UiOrderMarkers, minimap: UiMinimap, audio: UiAudioPort, notifier: UiNotifier) -> void
func order_issued(kind: int, sim_x: int, sim_y: int, ids: PackedInt32Array, def_idx: int) -> void   # marker + minimap ping + unit response (audio.unit_ordered(order, def_idx)) + bracket flash
func denied(reason: int, text_key: StringName) -> void          # cursor shake, audio.ui(ERROR) and audio.order_denied for UI pre-check refusals, toast/log line

class_name UiPlacement extends RefCounted
signal committed(struct_def: int, ax: int, ay: int, rot: int)
signal cancelled()
func begin(struct_def: int) -> bool                              # false if the item is not READY; calls view.begin_placement
func active() -> bool
func on_hover(screen: Vector2) -> void                           # ≤ 30 Hz: pick_ground → anchor → placement_result → view.update_placement
func rotate(steps: int = 1) -> void                              # 90° clockwise steps (BUILD_PLACE carries the rotation); no-op unless the footprint is rotatable
func on_click() -> bool                                          # commits when valid
func cancel() -> void
static func anchor(cell_x: int, cell_y: int, fp_w: int, fp_h: int) -> Vector2i    # (cx - fp_w / 2, cy - fp_h / 2), integer division

class_name UiTargeting extends RefCounted
signal committed(x: int, y: int, angle: int)
signal cancelled()
func begin_power(power_idx: int) -> bool
func begin_superweapon() -> bool
func on_hover(screen: Vector2) -> void                           # validity via power_target_ok; radius / line preview data for the overlay
func on_press(screen: Vector2) -> void                           # line/corridor powers: press sets the start, drag sets the angle, release commits
func cancel() -> void
```

### 3.4 HUD, presenter, notifications

```gdscript
class_name UiHud extends Control
signal build_requested(item: UiBuildItem, count: int)             # LMB (count 1) / Shift+LMB (count 5)
signal build_hold_requested(item: UiBuildItem)                    # RMB on a building/queued card
signal build_cancel_requested(item: UiBuildItem)                  # RMB on a held card
signal place_requested(item: UiBuildItem)                         # LMB on a READY structure card
signal power_pressed(power_idx: int)                              # LMB on a power/superweapon card or dock button
signal tab_changed(tab: int)
signal tool_pressed(id: StringName)                               # repair / sell / rally / waypoint / menu
signal command_pressed(id: StringName)                            # command bar buttons
signal ability_pressed(slot: int)
signal group_pressed(index: int, double: bool)
signal tile_pressed(index: int, mods: int)                        # selection tile: replace / remove / same-type-in-selection
signal camera_requested(norm: Vector2)                            # minimap LMB press/drag
signal minimap_order(norm: Vector2, mods: int)                    # minimap RMB (or armed LMB)
signal producer_cycled(direction: int)
const MODE_PLAYER: int = 0
const MODE_OBSERVER: int = 1
func setup(skin: UiSkin, data: GameData, roster: DefRoster, mode: int) -> void       # MODE_PLAYER / MODE_OBSERVER
func set_size_class(size_class: int) -> void
func sidebar() -> UiSidebar
func bottom() -> UiBottomPanel
func minimap() -> UiMinimap
func overlay() -> UiWorldOverlay
func ribbons() -> UiRibbonStack
func log_feed() -> UiLogFeed

class_name UiHudPresenter extends RefCounted
func setup(ctx: AppMatchContext, hud: UiHud, selection: UiSelection, groups: UiControlGroups, bus: UiCommandBus,
        placement: UiPlacement, targeting: UiTargeting, notifier: UiNotifier, icons: UiIconCache) -> void   # also connects ctx.audio.caption → notifier.on_caption
func on_events(records: PackedInt32Array) -> void                 # AppEvents consumer (order 20): notifier + selection prune/successor + stats
func on_ticks(ticks: int) -> void                                 # cadences of 5.10.1
func on_frame(delta: float) -> void
func refresh_all() -> void                                        # after tab switch / viewer change / theme change

class_name UiBuildModel extends RefCounted
func rebuild(port: UiSimPort, roster: DefRoster) -> void          # structure of the 8 tabs (static per roster)
func refresh(port: UiSimPort, viewer_selection_producers: PackedInt32Array) -> void   # states, progress, queue counts (≤ 2 Hz full, 20 Hz for progress)
func items(tab: int) -> Array[UiBuildItem]
func item_for(kind: int, def_idx: int) -> UiBuildItem

class_name UiProducerPicker extends RefCounted
static func pick(port: UiSimPort, queue_kind: int, unit_def: int, selected: PackedInt32Array) -> int   # producer eid or -1 (5.10.3)

class_name UiNotifier extends RefCounted
signal notice(n: UiNotice)                                        # ribbon + log + cue decisions already made (never a voice request)
func setup(rules: UiNoticeRules, port: UiSimPort, audio: UiAudioPort) -> void
func post(rule_id: StringName, args: Dictionary = {}, sim_x: int = -1, sim_y: int = -1) -> void
func on_event(ev: PackedInt32Array) -> void                       # one 10-int event record [type, tick, x, y, a … f] (UiEv codes); the rule table maps it to notices
func on_caption(line_id: StringName, text: String, priority: int) -> void   # Snd.announcement_started via UiAudioPort.caption: appended to the feed when audio/captions is on and no notice with that announcer_line was posted in the last 3 s (5.13.1)
func last_alert_position() -> Vector2i                            # for the jump-to-alert key
func cycle_alert() -> Vector2i                                    # repeated presses walk the last 5 alerts (≤ 30 s old)
func active_ribbons() -> Array[UiNotice]

class_name UiMinimap extends Control
signal camera_requested(norm: Vector2)
signal order_requested(norm: Vector2, mods: int)
signal ping_requested(norm: Vector2)                              # LMB while the PING mode is armed (`J`, 5.7.2)
func set_feed(f: UiMinimapFeed) -> void
func add_ping(norm: Vector2, col: Color, kind: int) -> void       # kind 0 order, 1 alert, 2 ally ping, 3 superweapon
func set_camera_quad(q: PackedVector2Array) -> void
func set_source(terrain: Texture2D, material: Material) -> void   # UiViewPort.minimap_texture / minimap_material: terrain + this viewer's fog drawn by a TextureRect child with the material; the widget draws dots, ghosts, camera quad, pings and the sweep above it
func norm_to_sim(norm: Vector2) -> Vector2i                       # round(norm × map cells × 1024)

class_name UiWorldOverlay extends Control                        # 2D, screen-space, above the 3D view (rings, bars, lines and the placement ghost are the view's)
func setup(view: UiViewPort, port: UiSimPort) -> void
func add_order_marker(kind: int, sim_x: int, sim_y: int) -> void   # 0.6 s feedback flash (5.8.7)
func set_targeting_preview(shape: int, sim_x: int, sim_y: int, radius_units: int, angle: int, length_units: int, valid: bool, friendly_fire: bool) -> void   # circle / capsule / line projected onto the ground as polylines; red hatch when own units are inside
func clear_targeting_preview() -> void
func add_edge_alert(sim_x: int, sim_y: int, kind: int) -> void    # arrow + glyph on the screen edge pointing at an off-screen alert for 4 s (A-07: alerts never rely on sound alone)
func set_strategic_markers(on: bool) -> void                      # `ui/strategic_markers` ∧ ¬UiHud.lite: role-glyph markers on every visible unit while UiViewPort.px_per_metre() < 18 (5.12); refreshed from one project_points call at 15 Hz, redrawn at 30 Hz
```

### 3.5 Screens, dialogs, design-system entry points

```gdscript
class_name UiScreen extends Control
signal back_requested()
signal navigate(target: StringName, params: Dictionary)
var screen_id: StringName
var keymap_context: int                                          # UiKeymap.Context to install while active
func enter(params: Dictionary) -> void                           # virtual; params documented per screen below
func exit() -> void                                              # virtual; release ports, tweens, sockets started by the screen
func default_focus() -> Control                                  # virtual; menus only
func on_escape() -> bool                                         # virtual; true = handled (closed a popup); false → back_requested
func can_leave() -> bool                                         # virtual; false → the screen shows its own confirm dialog

class_name UiDialogStack extends Node
signal top_changed(dlg: UiDialog)
func push(dlg: UiDialog) -> void
func close_top(result: int = 0) -> void
func is_open() -> bool
func has_modal_over_input() -> bool                              # true → UiInputController.enabled = false

class_name UiDialog extends PanelContainer
signal closed(result: int)                                       # result 0 = cancel/close, 1+ = button index
static func confirm(title_key: StringName, body_key: StringName, args: Dictionary = {}, yes_key: StringName = &"ui.yes", no_key: StringName = &"ui.no") -> UiDialog
static func message(title_key: StringName, body: String, ok_key: StringName = &"ui.ok") -> UiDialog

class_name UiThemeService extends RefCounted
static func current() -> Theme
static func rebuild(skin: UiSkin) -> Theme                       # UiTheme.build + AppScenes.set_theme
static func instance() -> UiThemeService
signal theme_changed(theme: Theme)                          # widgets connect once; custom-drawn ones queue_redraw()

class_name UiPalette extends RefCounted                            # the 18 tokens of style.ui.tokens as consts (BG_DEEP … BLACK_A, 4.6.4) + the CVD semantic set (7.5); test U-1 asserts them equal to the JSON
const CVD_OK := Color("#4DB8FF"); const CVD_WARN := Color("#F5E663"); const CVD_DANGER := Color("#E8590C"); const CVD_POWER := Color("#A8E6FF")
static func team(id: int) -> Color                                 # UiSkinSet.team_color(id): ViewStyle.player_color(id, cvd_active)
static func semantic(kind: StringName) -> Color                    # &"ok" &"warn" &"danger" &"power" for the active colour mode

class_name UiSkin extends RefCounted
var accent: Color; var accent2: Color; var tint: Color; var chrome: Dictionary   # chrome = ViewStyle.chrome() (5.19.1)
static func from_style(style: ViewStyle, faction_code: String) -> UiSkin        # art R-17; unknown code → neutral()
static func neutral() -> UiSkin                                    # #7fb0e6 / #ffd35c / #141c26

class_name UiSkinSet extends RefCounted
enum ColourMode { NORMAL = 0, CVD = 1 }
signal colour_mode_changed(mode: int)                              # UiThemeService.rebuild + palette consumers redraw
func setup(style: ViewStyle) -> void                               # null → built-in fallback skins (UiPalette constants + neutral skin for every faction)
func skin_for(faction_code: String) -> UiSkin                      # cached; the local player's faction in a match, the last roster's in menus
func set_colour_mode(mode: int) -> void
func colour_mode() -> int
func style() -> ViewStyle                                          # may be null (fallback mode)

class_name UiEmblem extends RefCounted                             # art_direction.md §3 — the signatures are art's; ops are style.emblems data (5.11)
const MIN_STROKE_PX: float = 1.5
static func draw_ops(ci: CanvasItem, ops: Array, rect: Rect2, c1: Color, c2: Color, bg: Color) -> void
static func draw_faction(ci: CanvasItem, style: ViewStyle, faction_code: String, rect: Rect2, sub_index: int = 0, sub_key: String = "") -> void   # chooses emblem + badge / pips by the size ladder
static func draw_badge(ci: CanvasItem, glyph_ops: Array, rect: Rect2, c1: Color, c2: Color, bg: Color) -> void   # lower-right disc, 40 % of the emblem size
static func draw_pips(ci: CanvasItem, sub_index: int, rect: Rect2, c1: Color) -> void                             # below 48 px: 1-3 pips

class_name UiGlyphs extends RefCounted
enum Glyph { STRUCTURES = 0, INFANTRY = 1, VEHICLES = 2, AIRCRAFT = 3, NAVAL = 4, DEFENSE = 5, POWERS = 6, ATTACK_MOVE = 7, GUARD = 8, STOP = 9, SCATTER = 10, DEPLOY = 11, SELL = 12, REPAIR = 13,
             WAYPOINT = 14, CREDIT = 15, BOLT = 16, WARNING = 17, CHEVRON_UP = 18, CHEVRON_DOWN = 19, CLOSE = 20, CHECK = 21, LOCK = 22, CLOCK = 23, GEAR = 24, PLUS = 25, MINUS = 26, RADAR = 27, MISSILE = 28,
             TANK = 29, ARTILLERY = 30, ANTI_AIR = 31, SCOUT = 32, TRANSPORT = 33, ENGINEER = 34, COLLECTOR = 35, MCV = 36, DRONE = 37, SUBMARINE = 38, CARRIER = 39, SIEGE = 40, COMMAND = 41, CAMO = 42, EMP_OFF = 43, NO_POWER = 44,
             FOLLOW = 45, HOLD = 46, PATROL = 47, RETURN = 48, UNLOAD = 49, STANCE = 50, RALLY = 51, PING = 52, SPEED = 53, MUTE = 54 }   # 0-28 = the spike's set, 29-44 = art's 16 (art_direction.md §5.12.6), 45+ = UI additions
static func draw(ci: CanvasItem, glyph: int, rect: Rect2, col: Color, width: float = 1.8) -> void   # 24-px grid, stroke 1.8 px (2.0 at ≥ 32 px), minimum size 16 px, second role col.darkened(0.55)
static func role_glyph(def_kind: int, def_idx: int) -> int                     # capability → layer → archetype role → class glyph (5.10.4)
static func atlas() -> Texture2D                                               # white 32-px cells baked once through a SubViewport (one frame)
static func atlas_rect(glyph: int) -> Rect2

class_name UiText extends RefCounted
static func load_all() -> void                                    # data/text/*.json (at boot)
static func t(key: StringName, args: Dictionary = {}) -> String   # "{name}" interpolation; missing key → "⟦key⟧" + Log.warn once
static func tn(key: StringName, count: int, args: Dictionary = {}) -> String   # "key#one" / "key#other"
static func has(key: StringName) -> bool

class_name UiFormat extends RefCounted
static func credits(n: int) -> String                             # 12450 → "12,450"
static func mmss(seconds: float) -> String                        # ceil; 26.0 → "0:26"
static func hms(seconds: int) -> String                           # 3725 → "1:02:05"
static func hash8(h: int) -> String                               # 0x9F3AC21E → "9F3A-C21E"
static func hotkey(action: StringName) -> String
static func pct(permille: int) -> String                          # 372 → "37%"

class_name UiLayout extends RefCounted
enum SizeClass { COMPACT = 0, REGULAR = 1, LARGE = 2 }
static func factor(window_px: Vector2i, ui_scale: float) -> float # 5.4.1
static func apply(window: Window, ui_scale: float) -> void
static func size_class(logical_h: float) -> int
static func minimap_size(logical_h: float) -> float               # clamp((h − 420) × 0.55, 180, 300)

class_name UiCursors extends RefCounted
enum State { DEFAULT = 0, TEXT = 1, HAND = 2, ATTACK = 3, MOVE = 4, SELECT = 5, DENIED = 6, ATTACK_MOVE = 7, FORCE_FIRE = 8, GUARD = 9,
             DEPLOY = 10, SELL = 11, REPAIR = 12, RALLY = 13, INSPECT = 14, BUSY = 15, INTERACT = 16, POWER = 17, SUPERWEAPON = 18, PLACE_OK = 19, PLACE_BAD = 20,
             SCROLL_N = 21, SCROLL_NE = 22, SCROLL_E = 23, SCROLL_SE = 24, SCROLL_S = 25, SCROLL_SW = 26, SCROLL_W = 27, SCROLL_NW = 28 }   # 21-28: edge-scroll arrows, shown on the ARROW slot only while the pointer is in the scroll band
static func register_all(ui_scale: float, mode: int) -> void      # bake + Input.set_custom_mouse_cursor once per shape slot (5.7.3)
static func set_state(state: int) -> void                         # Input.set_default_cursor_shape(slot_of(state)) — 1 µs; no-op if unchanged
static func slot_of(state: int) -> int                            # Input.CursorShape
static func set_scroll(dir: Vector2i) -> void                     # edge-scroll arrow for dir ∈ {−1,0,1}² (swaps the image into the ARROW slot, 0.36-0.56 ms, only when the direction changes); Vector2i.ZERO restores the default arrow

class_name UiIconCache extends RefCounted                          # handle map over the view's icon service; the view owns baking, its LRU and its disk cache (user://cache/icons/, render.md §5.8.10)
signal changed(key: StringName)                                    # an icon arrived: widgets showing the placeholder queue_redraw
func setup(view: UiViewPort) -> void                               # connects UiViewPort.icon_ready
func get_icon(def_id: String, roster_id: String, size: int) -> Texture2D   # cached handle or the view's flat placeholder; never blocks
func warm(defs: PackedStringArray, roster_id: String, size: int) -> void   # queue a roster's icons (lobby briefing, loading screen)
func pending() -> int

class_name UiIconBaker extends Node                                # the spike's batched baker: used ONLY by UiViewPortFixture (and as the reference implementation)
func bake(recipes: PackedStringArray, size: Vector2i, team: Color, rim: Color) -> void   # coroutine (await); one batch, one frame_post_draw
func get_icon(recipe: String, size: Vector2i, team: Color) -> ImageTexture
func prewarm() -> void                                             # renders a hidden lit 3D scene once (pipeline compile) — 2.6-2.8 s cold (spike)
```

**Screen parameters (`enter(params)`):**

| Screen id | Params |
|---|---|
| `&"splash"` | `{next: StringName}` |
| `&"main_menu"` | `{}` |
| `&"lobby"` | `{role: "local"\|"host"\|"client", back: StringName}` (session from `AppNet.session`) |
| `&"lan_browser"` | `{}` |
| `&"loading"` | `{kind: "match"\|"replay", title: String}` |
| `&"game"` | `{ctx: AppMatchContext}` (player, observer or replay) |
| `&"end"` | `{summary: Dictionary}` (4.9) |
| `&"replays"` | `{}` |
| `&"field_manual"` | `{roster_id: String = <local roster>, page: StringName = &"overview", focus_id: String = ""}` |
| `&"options"` | `{page: StringName = &"graphics"}` |
| `&"credits"` | `{}` |
| `&"fatal"` | `{reason: int, detail: String}` |

### 3.6 Field Manual model (pure; the screen only renders it)

```gdscript
class_name UiFmModel extends RefCounted
func build(data: GameData, roster: DefRoster) -> void            # calls DefBrowser.* cards once; caches (no per-frame calls)
func overview() -> Dictionary                                    # {faction_card, roster_card (delta), traits[], opening, counterplay}
func units() -> Array[Dictionary]                                # DefBrowser.unit_card rows, tier/cost order (DefRoster.producible_units)
func structures() -> Array[Dictionary]
func research() -> Array[Dictionary]
func powers() -> Array[Dictionary]                                # 3 powers + superweapon_card
func tech_tree() -> Dictionary                                   # DefBrowser.tech_tree
func compare(other: DefRoster) -> Dictionary                     # DefBrowser.compare_rosters
func search(text: String, limit: int = 20) -> Array[Dictionary]  # DefBrowser.search
func card_for(kind: int, def_idx: int) -> Dictionary
```

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enumerations (consolidated; integer values are stable — persisted settings and tests use them)

| Enum | Values |
|---|---|
| `AppFlow.Mode` | BOOT 0, MAIN_MENU 1, SKIRMISH_LOBBY 2, LAN_BROWSER 3, LAN_LOBBY 4, LOADING 5, IN_MATCH 6, END_SCREEN 7, REPLAYS 8, REPLAY_PLAYBACK 9, OPTIONS 10, CREDITS 11, FIELD_MANUAL 12, FATAL 13, QUIT 14 |
| `AppScenes.Layer` | BACKDROP 0 (3D host, no canvas), SCREEN 1, OVERLAY 2, FADE 3, DEBUG 4 — mapped to `CanvasLayer.layer` 0 / 10 / 40 / 90 / 100 |
| `UiBuildItem.Kind` | STRUCTURE 0, UNIT 1, RESEARCH 2, POWER 3, SUPERWEAPON 4 |
| `UiBuildItem.State` | AVAILABLE 0, BUILDING 1, QUEUED 2, READY 3, ON_HOLD 4, LOCKED 5, UNAFFORDABLE 6, COOLDOWN 7, **BLOCKED 8** (prerequisite lost / unpowered — bible `rule.design.research`), **PLACING 9** (placement mode active), **DONE 10** (research completed) |
| `UiSidebar.Tab` | STRUCTURES 0, DEFENSE 1, INFANTRY 2, VEHICLES 3, AIRCRAFT 4, NAVAL 5, RESEARCH 6, POWERS 7 |
| `UiSelection.Mode` | NONE 0, UNITS 1, STRUCTURES 2, FOREIGN 3 (inspect only, no commands) |
| `UiTarget.Kind` | NONE 0 (unknown / off-map), GROUND 1, ENEMY 2, OWN 3, ALLY 4, NEUTRAL 5, WRECK 6, DEPOSIT 7 |
| `UiTarget.EntityKind` | UNIT 0, STRUCTURE 1, WRECK 2, NEUTRAL_STRUCTURE 3 (a deposit target is `Kind.DEPOSIT` with `eid = −1`: it comes from the ground pick and `deposit_at`) |
| `UiOrderIntent.Kind` | NONE 0, MOVE 1, ATTACK 2, ATTACK_MOVE 3, GUARD 4, FORCE_FIRE 5, CAPTURE 6, REPAIR 7, LOAD 8, GARRISON 9, SALVAGE 10, HARVEST 11, RETURN_BASE 12, SET_RALLY 13, SELL 14, STRUCT_REPAIR 15, USE_POWER 16, LAUNCH_SUPERWEAPON 17, UNLOAD 18, DEPLOY 19, HOLD 20, STOP 21, SCATTER 22, PATROL 23, STANCE 24, RETURN_CASH 25, ABILITY 26, SCUTTLE 27, UNDEPLOY 28, FOLLOW 29, DENIED 99 |
| `UiModes.Armed` | NONE 0, ATTACK_MOVE 1, GUARD 2, SELL 3, REPAIR 4, RALLY 5, WAYPOINT 6 (latch: subsequent orders are queued), FORCE_FIRE 7, POWER 8, SUPERWEAPON 9, PLACE 10, ABILITY 11, PING 12, MOVE 13, PATROL 14, FOLLOW 15 |
| Stance (= combat's `SimCompCombat.stance`, `sim_core.md` R21 / `combat.md` §5.10.4) | AGGRESSIVE 0, DEFENSIVE 1, HOLD_FIRE 2, GUARD 3 (the stance button and `Z` cycle 0 → 1 → 2 → 3 → 0). **Hold position is the `HOLD` order** (`H`, `T_HOLD`), not a stance; the GUARD *order* (`G`, guard a unit or a point) and the GUARD *stance* (auto-acquire around the anchor) are different things |
| Queue mode (= `SimOrder.QM_*`) | REPLACE 0 (plain click), APPEND 1 (Shift or the `W` latch); FRONT 2 is never produced by the UI |
| `UiNotice.Severity` (= `UiRibbon.Severity`) | INFO 0, OK 1, WARN 2, DANGER 3 |
| `UiLayout.SizeClass` | COMPACT 0 (logical h < 800), REGULAR 1 (800–1299), LARGE 2 (≥ 1300) |
| `UiSkinSet.ColourMode` | NORMAL 0 (persisted as `"normal"`), CVD 1 (art's single colour-vision-safe team set and the CVD-safe semantic set, persisted as `"cvd"`; one set serves protan, deutan and tritan) |
| `UiA11y.Cvd` (simulation only) | NONE 0, DEUTERANOPIA 1, PROTANOPIA 2, TRITANOPIA 3 |
| `UiKeymap.Context` | GLOBAL 1, MENU 2, GAME 4, OBSERVER 8, LOBBY 16, TEXT_ENTRY 32 |
| `UiKeymap.MOD_*` (gesture modifiers) | SHIFT 1, CTRL 2, ALT 4, META 8 |
| `UiCursors.State` | see 3.5 (0-28) and the slot map in 5.7.3 |
| `UiHud` mode | PLAYER 0, OBSERVER 1 |
| Ping kinds (`UiMinimap.add_ping`) | ORDER 0, ALERT 1, ALLY 2, SUPERWEAPON 3 |
| Order-marker kinds (`UiOrderMarkers`) | MOVE 0, ATTACK 1, ATTACK_MOVE 2, GUARD 3, RALLY 4, REPAIR 5, CAPTURE 6, DENIED 7 |
| Unit-response orders (`UiAudioPort.Order` = `SndUnitResponse.Order`) | MOVE 0, ATTACK 1, GUARD 2, DEPLOY 3, CAPTURE 4, REPAIR 5, LOAD 6, UNLOAD 7, HARVEST 8, STOP 9, SCATTER 10, SELL 11 (mapping from intents in 5.8.7) |

### 4.2 View-models

```gdscript
class_name UiBuildItem extends RefCounted
enum Kind { STRUCTURE = 0, UNIT = 1, RESEARCH = 2, POWER = 3, SUPERWEAPON = 4 }
enum State { AVAILABLE = 0, BUILDING = 1, QUEUED = 2, READY = 3, ON_HOLD = 4, LOCKED = 5, UNAFFORDABLE = 6, COOLDOWN = 7, BLOCKED = 8, PLACING = 9, DONE = 10 }
var kind: int                     # Kind
var def_idx: int                  # UNIT / STRUCTURE: the per-kind def index (what TRAIN / BUILD_START / events carry; identity with the GameData table index, decision 17); RESEARCH / POWER / SUPERWEAPON: the GameData table index (POWER additionally has `slot`)
var id: String                    # canonical id ("unit.napc.guardian_tank"); labels only
var display_name: String          # DefBase.ui_name
var tier: int                     # 1-3 (0 for powers)
var cost: int                     # credits, resolved for the local roster (0 = free / n.a.)
var total_seconds: float          # build / research / cooldown / recharge time, resolved (display only)
var power_delta: int              # structures: + supply / − demand (bible fixed numbers)
var state: int                    # State
var progress_permille: int        # 0..1000 (BUILDING / ON_HOLD / COOLDOWN / charging)
var eta_ticks: int                # from the sim (already includes the 50 % low-power rate); −1 unknown
var rate_pct: int                 # 100 normal, 50 shortage
var queued: int                   # units waiting in the chosen producer (incl. the one in progress)
var pending: int                  # optimistic local increments not yet confirmed by the sim (cleared on confirm or after 1.5 s)
var blocked_reason: int           # UiSimPort.Rule when LOCKED / BLOCKED / UNAFFORDABLE
var queue_state: int              # UiSimPort.QueueState of the queue this item sits in (chips: "$" WAIT_FUNDS, "!" UNIT_CAP, bolt LOW_POWER); HELD → ON_HOLD, PREREQ_LOST → BLOCKED
var requires_text: String         # "Radar", "Radar + Laboratory" (UiText, from DefRoster.prereqs)
var hotkey_label: String          # "Alt+Q" (UiKeymap.label of card_{slot})
var slot: int                     # grid position within its tab (drives the hotkey)
var recipe: String                # DefBase.pres_recipe → icon key
var glyph: int                    # UiGlyphs.Glyph fallback while the icon is not baked
var role_glyph: int               # bottom-left role glyph of the card (UiGlyphs.role_glyph(def), 5.10.4); the top-right tier badge derives from `tier` (2 → one chevron, 3 → two)
var icon: Texture2D               # null until baked
var replaced_by_roster: bool      # true if this def is a subfaction unique (shows UNIQUE badge)
var producer_eid: int             # chosen producer for units (−1 for structures / research / powers)
func is_sweeping() -> bool        # BUILDING / ON_HOLD / COOLDOWN
func remaining_seconds() -> float # eta_ticks / 20, or total × (1 − p) / rate when unknown

class_name UiNotice extends RefCounted
var rule_id: StringName           # key in notices.json
var severity: int
var title: String
var subtitle: String
var glyph: int
var countdown_ticks: int          # −1 none; counts down against sim.tick() so pause freezes it
var charge_permille: int          # −1 none
var sim_x: int                    # jump / ping target, −1 none
var sim_y: int
var ribbon: bool                  # also shown as a ribbon (else log line only)
var created_tick: int
var ttl_ticks: int                # ribbons auto-hide (0 = until resolved by an explicit clear)

class_name UiMinimapFeed extends RefCounted
var dots_norm: PackedVector2Array # normalised map coordinates 0..1
var dots_color: PackedColorArray
var dots_size: PackedFloat32Array # logical px by class (art 5.12.6: infantry 2, vehicle 3, air 3, naval 3, structure 4, superweapon 8; the viewer's own +1)
var dots_class: PackedByteArray   # blip shape by class (art 5.12.6): 0 infantry dot, 1 vehicle square, 2 air diamond, 3 naval triangle, 4 structure outlined square, 5 superweapon pulsing star, 6 neutral capturable (hollow square in the NEUTRAL colour)
var dots_pip: PackedByteArray     # 255 = none; else the owner's pip shape (the view's 8-shape table, +8 = outlined) drawn instead of the outlined square on structure blips while the colour mode is cvd (the non-colour player cue of QA A-01 at minimap scale)
var ghost_norm: PackedVector2Array
var warn_norm: PackedVector2Array # strategic warning centres
var warn_radius_norm: PackedFloat32Array
```

### 4.3 Order-resolution structures

```gdscript
class_name UiTarget extends RefCounted
var kind: int                     # UiTarget.Kind
var entity_kind: int              # EntityKind (meaningful when kind ≥ ENEMY)
var eid: int                      # −1 for ground
var def_idx: int                  # −1 for ground
var owner: int
var layer: int                    # 0 ground, 1 air, 2 surface, 3 underwater (combat LAYER_*)
var x: int                        # sim units (entity position, or the ground point)
var y: int
var visible: bool                 # currently visible to the viewer
var ghost: bool                   # remembered structure
var hp_permille: int
var damaged: bool                 # hp < hp_max
var capturable: bool              # neutral tech structure not yet owned by the viewer's team
var garrisonable: bool            # neutral civilian garrison with a free slot for the viewer
var transport_free: int           # free squad slots (own/ally transports)
var transport_vehicle_free: int
var is_producer: bool
var is_refinery: bool
var is_airfield: bool
var is_carrier: bool
var salvageable: bool             # enemy land-vehicle wreck inside its 60 s window
var passable_mask: int            # move classes that can stand on this ground cell (bit per DefEnums.MoveClass); ground targets only

class_name UiSelectionInfo extends RefCounted
var mode: int                     # UiSelection.Mode
var count: int
var caps_any: int                 # OR of UiUnitCaps over the selection
var caps_all: int                 # AND of UiUnitCaps
var ids_by_cap: Dictionary        # cap bit (int) → PackedInt32Array of ids having it; built lazily per resolve() call site, not per frame
var primary_def: int
var has_foreign: bool
func ids_with(cap_mask: int, require_all: bool = true) -> PackedInt32Array   # ascending
func ids_without(cap_mask: int) -> PackedInt32Array

class_name UiOrderIntent extends RefCounted
var kind: int                     # UiOrderIntent.Kind
var ids: PackedInt32Array         # eligible units (ascending)
var target_eid: int               # −1 = point (sent as target 0)
var x: int                        # sim units
var y: int
var queued: bool                  # Shift or WAYPOINT latch → QM_APPEND on every op that has a queue mode
var force: bool                   # force modifier held (ATTACK on a non-enemy sets FLAGS bit0 "forced")
var move_flags: int               # MOVE / ATTACK_MOVE / PATROL flag bits (v2.1): b1 speed-match when `input/move_speed_match`, b2 reverse-ok when `input/move_reverse`; b0 no-formation is never set by the UI; filled by the bus from the settings, 0 by default
var arg: int                      # stance / ability slot / power index / structure-repair mode
var arg2: int                     # spare (UNLOAD: 0 all cargo / 1 one passenger); abilities use `arg` = slot and the bus helpers use_ability / set_mode / set_autocast directly
var extra: Array[UiOrderIntent]   # further intents produced by the SAME click for the other units of a mixed selection, in fixed rule order (5.7.2); the bus submits primary first, then extras
var cursor: int                   # UiCursors.State to show for this intent
var deny_reason: StringName       # UiText key when kind == DENIED ("order.deny.no_weapon" …)
var marker: int                   # order-marker kind for feedback (−1 none)
```

**Capability bits (`UiUnitCaps`, computed once per def from `DefUnit`/`DefStructure`; the cache is rebuilt when the roster changes):**

| Bit | Name | Derivation |
|---|---|---|
| 1<<0 | `CAP_ARMED` | ≥ 1 weapon slot (or a summoned/armed structure) |
| 1<<1 / 2 / 3 / 4 | `CAP_HIT_GROUND` / `HIT_AIR` / `HIT_WATER` / `HIT_SUB` | `attack_layer_mask` bits GROUND / AIR / SURFACE_WATER / UNDERWATER (structures count as ground) |
| 1<<5 | `CAP_MOBILE` | `speed > 0` and not a structure |
| 1<<6 / 7 | `CAP_AIR` / `CAP_NAVAL` | `move_class` AIR_* / NAVAL, SUBMERGED |
| 1<<8 / 9 | `CAP_INFANTRY` / `CAP_VEHICLE` | unit tags `infantry` / `land_vehicle` |
| 1<<10 | `CAP_ARTILLERY` | tag `artillery` (force-fire on ground) |
| 1<<11 | `CAP_COLLECTOR` | tag `collector` / ability HARVEST |
| 1<<12 | `CAP_CAPTURE` | ability CAPTURE (Engineer) |
| 1<<13 / 14 | `CAP_REPAIR_VEHICLE` / `CAP_REPAIR_STRUCT` | ability REPAIR params `targets` (`land_vehicle` / `structure` / `friendly_defense_structure`) |
| 1<<15 | `CAP_SALVAGE` | ability SALVAGE (AE rosters only) |
| 1<<16 / 17 | `CAP_TRANSPORT` / `CAP_PASSENGER` | ability TRANSPORT / infantry (or land vehicle for the Landing Transport class) |
| 1<<18 | `CAP_DEPLOY` | ability DEPLOY / MODE_SWITCH with an immobile mode / sensor_mast / MCV (all are sent `DEPLOY` with def −1 or `UNDEPLOY(slot)`; the sim routes an MCV to `T_DEPLOY_MCV`; `CAP_MCV` only selects the icon) |
| 1<<19 | `CAP_MCV` | tag `construction` |
| 1<<20 | `CAP_MODE_SWITCH` | ability MODE_SWITCH (ability bar button) |
| 1<<21 | `CAP_GARRISON` | infantry (neutral garrison rule) |
| 1<<22 | `CAP_DETECTOR` | tag `detector` (range-ring colour) |
| 1<<23 | `CAP_CARRIER_DRONE` | tag `unmanned` + `carrier` wing member |
| 1<<24 | `CAP_SERVICE` | `unit_class == SERVICE` (excluded from "select all military" and soft-excluded from attack orders) |
| 1<<25 / 26 / 27 | `CAP_STRUCTURE` / `CAP_PRODUCER` / `CAP_SELLABLE` | structure / `queue_kind != NONE` / `SF_SELLABLE` |
| 1<<28 | `CAP_HAS_ABILITY_BUTTONS` | any of MODE_SWITCH, SPAWN_ZONE family (kinds 11, 12, 13, 16), CARRIER (wing switch), SUBMERGE, TRANSPORT (unload) |

### 4.4 Port data structures

#### 4.4.1 `UiEntityRow` (one entity read; reused buffer)

```gdscript
class_name UiEntityRow extends RefCounted
const F_STRUCT: int = 1
const F_GHOST: int = 2            # remembered structure, not currently seen
const F_CAMO: int = 4
const F_DEPLOYED: int = 8
const F_EMP: int = 16
const F_UNPOWERED: int = 32
const F_CONSTRUCTING: int = 64
const F_GARRISONED: int = 128     # occupants inside (neutral garrison or own transport)
const F_LOADED: int = 256         # this entity is inside a container (not selectable)
const F_DECOY: int = 512          # decoy identified by the viewer
const F_SUPPRESSED: int = 1024
const F_REPAIRING: int = 2048     # structure repair toggle on
const F_SELLING: int = 4096       # being sold (sell button disabled, "Selling…" chip)
var id: int
var def_idx: int
var kind: int                     # UI classification (3.2.4): 0 unit, 1 structure, 2 wreck, 3 neutral structure (4 is reserved: deposits are map cells)
var owner: int                    # −1 neutral
var x: int                        # sim units, end of last tick
var y: int
var prev_x: int
var prev_y: int
var facing: int                   # binary angle 0..4095
var layer: int
var hp: int
var hp_max: int
var flags: int
var order_kind: int               # 0 idle, 1 moving, 2 attacking, 3 attack-moving, 4 guarding, 5 holding, 6 harvesting, 7 repairing, 8 producing, 15 other
var stance: int                   # combat stance 0 aggressive · 1 defensive · 2 hold fire · 3 guard (−1 = no combat component)
var mode: int                     # deploy / mode-switch / loadout index
var cargo: int                    # loaded squads
var cargo_cap: int
var ammo: int                     # −1 infinite
var vet: int                      # 0..3 (0 always unless rules.veterancy)
var squad: int                    # live squad members for infantry (1 otherwise)
var squad_max: int
var container: int                # −1 none
var paid_cost: int
var rally_x: int                  # producers; −1 unset
var rally_y: int
var rally_target: int
var queue_len: int                # producers
var is_primary: bool              # producers: the sim's primary building of its kind (SET_PRIMARY)
```

#### 4.4.2 `UiEntitySnapshot` (SoA; one bulk call per 10 Hz)

```gdscript
class_name UiEntitySnapshot extends RefCounted
var count: int
var ids: PackedInt32Array
var xs: PackedInt32Array          # sim units
var ys: PackedInt32Array
var defs: PackedInt32Array
var owners: PackedInt32Array
var flags: PackedInt32Array       # UiEntityRow.F_* (struct / ghost / camo …) | (kind << 16)
var hp_pct: PackedByteArray       # 0..100
func clear() -> void              # count = 0; arrays keep capacity
```

#### 4.4.3 `UiPickData` (the fixture adapter's picking data; production picking is `ViewPicker`)

```gdscript
class_name UiPickData extends RefCounted
var count: int
var ids: PackedInt32Array
var pos: PackedVector3Array                                   # rendered ground point under the entity (bar / bracket anchor base)
var center: PackedVector3Array                                # centre of the pick sphere (includes altitude for aircraft)
var radius: PackedFloat32Array                                # pick radius, world metres
var height: PackedFloat32Array                                # metres above `pos` where the 2D stand-in bar anchors
var flags: PackedInt32Array                                   # bit0 structure, bit1 ghost, bit2 air, bit3 wreck, bit4 neutral, bit5 own, bit6 ally
func slot_of(eid: int) -> int                                 # -1 when not rendered; O(1) (id → slot)
```

### 4.5 Keymap structures

#### 4.5.1 Packed key format and persistence

A binding is one `int`: `packed = physical_keycode | modifier_mask`, with Godot's own masks (`KEY_MASK_SHIFT` 1<<25 = 33,554,432, `KEY_MASK_ALT` 1<<26 = 67,108,864, `KEY_MASK_META` 1<<27 = 134,217,728, `KEY_MASK_CTRL` 1<<28 = 268,435,456; key code mask `0x7FFFFF`; verified in `@GlobalScope.xml`) — exactly `InputEventKey.get_physical_keycode_with_modifiers()` (measured: `Ctrl+Shift+1` = 301,989,937 = 268,435,456 + 33,554,432 + 49; `Alt+Q` = 67,108,945). Mouse-button bindings (only for `cam_orbit`) use `packed = -button_index` (negative). Persisted in `[keys]` as one line per action: `cmd_stop=PackedStringArray("k:83")` / `card_1=PackedStringArray("k:67108945")` (Alt+Q); a token is `k:<packed>` or `m:<button>`; unknown tokens are dropped, `PackedStringArray()` (empty) means *explicitly unbound*, a missing action key means *default*. Labels are produced at runtime by `OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(physical) | mods)` so AZERTY/QWERTZ users see their own letters while the *position* stays the same.

#### 4.5.2 Action registry (`UiActions`)

Each action: `id: StringName`, `category: StringName` (camera / selection / orders / tools / sidebar / powers / interface / observer), `contexts: int` (`UiKeymap.Context` mask), `label_key`, `repeat: bool` (fires on key echo — camera actions only), `default: PackedInt32Array`. The complete default table is in 5.6.1.

### 4.6 Layout and theme tokens

#### 4.6.1 Layout metrics (`UiMetrics`; logical px at `content_scale_factor` applied)

| Constant | Value | Notes |
|---|---|---|
| `DESIGN_H` | 1080 | reference height of the scale rule |
| `SIDEBAR_W` | 348 | inner width 320 after 14 px padding; 3 card columns |
| `SIDEBAR_PAD` | 14 x 12 | |
| `MINIMAP_MAX` / `MINIMAP_MIN` / `MINIMAP_PAD` | 300 / 180 / 5 | size = `clamp((logical_h − 420) × 0.55, 180, 300)` |
| `TOOL_H` | 32 | tool row: repair, sell, rally, waypoint, menu |
| `ECO_H` | 56 + 42 | credits ticker + power bar |
| `TAB_SIZE` / `TAB_GAP` | 38 / 2 | 8 tabs = 318 ≤ 320 |
| `CARD` / `CARD_ICON_H` | 98 x 104 / 62 | icon baked at 2x (188 x 124) |
| `GRID_COLS` / `GRID_GAP` / `GRID_SLOTS` | 3 / 6 / 12 | ghost slots fill to a multiple of 3, min 12 |
| `QUEUE_SLOT` / `QUEUE_H` / `FOOTER_H` | 56 x 44 / 66 / 16 | hidden when COMPACT |
| `BOTTOM_W_MIN` / `BOTTOM_W_MAX` / `BOTTOM_H` / `BOTTOM_MARGIN` | 600 / 900 / 160 / 10 | width `clamp(playfield_w − 40, 600, 900)` |
| `GROUP_BADGE` / `GROUP_GAP` | 60 x 30 / 4 | 10 badges = 636 px |
| `PORTRAIT` / `TILE` / `TILE_GAP` | 152 x 76 / 46 / 4 | tiles: `cols = floor((w − 152 − 12 + 4) / 50)`, overflow tile `+N` |
| `COMMAND_BTN` / `COMMAND_GAP` / `ABILITY_BTN` | 48 / 5 / 40 | 4 x 2 grid + one utility / ability row (≤ 4 fixed context buttons + ≤ 4 dynamic slots = 8 x 45 = 360 px) |
| `RIBBON` / `RIBBON_GAP` / `RIBBON_TOP` / `RIBBON_MAX` | 480 x 48 / 6 / 12 / 4 | centre of the playfield |
| `DOCK_BTN` / `DOCK_GAP` / `DOCK_POS` | 56 / 6 / (12, 44) | 4 buttons, under the top strip |
| `TOP_STRIP_POS` | (12, 12) | time, kills/lost, score |
| `LOG_MAX` / `LOG_BOTTOM` | 6 lines / 232 px above the bottom edge | chat + notifications share this feed |
| `BRACKET_MIN_HALF` / `BAR_W` / `BAR_H` | 10 / 24..90 / 4 | world overlay |
| `SCREEN_MARGIN` | 56 / 34 / 56 / 30 (l, t, r, b) | menus / lobby / browser |
| `MENU_BTN` / `MENU_POS` | 420 x 54 / (104, 470) | hero buttons, gap 10 |
| `LOBBY_ROW_H` / `LOBBY_COLS` | 48 / 76, 158, 232, 190, 118, 90 | player row: swatch+emblem, type, faction, subfaction, team, status |
| `DRAG_THRESHOLD` / `EDGE_MARGIN` | 6 / 6 | pointer gestures |
| `DOUBLE_CLICK_MS` / `DOUBLE_CLICK_PX` / `DOUBLE_TAP_MS` | 350 / 8 / 350 | |
| `HOVER_HZ` / `MINIMAP_HZ` / `FEED_HZ` | 30 / 30 / 10 | |
| `MIN_WINDOW` | 1024 x 576 | `Window.min_size` |

#### 4.6.2 Type scale (the values of `style.ui.type`, `art_direction.md` §5.12.3; the JSON wins)

| Token | Font role | Size (logical px) | Use |
|---|---|---|---|
| `caption` | NUM (Share Tech Mono) | 14 (the spike used 11-12; raised to meet QA A-03) | CAPS captions, tag chips, hotkey badges |
| `small` | BODY (Rajdhani SemiBold) | 14 | dim/secondary text (`DimLabel`) |
| `body` | BODY | 15 | default text (`FS_BODY`) |
| `sub` | BODY | 18 | sub-headings, selection-panel names |
| `list` | BODY_BOLD (Rajdhani Bold) | 15 | rows, option labels, button labels, names |
| `head` | HEAD (Orbitron wght 700, +1 px glyph spacing) | 14 (panel headers) / 17-22 (names) | `HeaderLabel`, dialog titles |
| `hero` | HEAD | 20 | menu hero buttons |
| `title` | HEAD | 40 | screen titles |
| `logo` | HEAD | 56 | main-menu wordmark |
| `numerals` | NUM | 34 (credits counter), 25 (countdown), 15 (costs, timers, hotkeys) | tickers |

Rules (spike font study, 12-18 px on `#0b1016`, plus `qa.md` A-03 / V-H02 and `art_direction.md` §5.12.3): **no text below 14 logical px at 100 % UI scale on a 1080p window** (the audit measures effective size there; a 75 % scale is a density choice the player makes knowingly; the art bible allows decorative micro-labels down to 11 px, the UI does not use them); headers are UPPERCASE with tracking, body text is sentence case, numbers are always NUM with thousands separators, text shadow (0, 1) black 60 %; Orbitron only for CAPS and numerals (lowercase is poor below 14 px) and CAPS strings stay short (labels ≤ 24 characters, never running text, A-17); Share Tech Mono is thin below 14; Rajdhani Medium is too thin below 16 (rejected). Cards, chips and badges are sized for 14 px text (the build-card hotkey badge and cost line are 14 px in a 98 x 104 card, names ellipsise at 12 characters and show the full name in the tooltip).

#### 4.6.3 Theme type variations (`Theme.set_type_variation`)

| Variation | Base | Purpose |
|---|---|---|
| `HeaderLabel` | Label | Orbitron 14, `skin.accent` |
| `DimLabel` | Label | Rajdhani 14, `TEXT_DIM` |
| `NumLabel` | Label | Share Tech Mono 15, `TEXT` |
| `TitleLabel` | Label | Orbitron 40 (`title`) |
| `CreditsLabel` | Label | Share Tech Mono 15, `CREDITS` |
| `OkLabel` / `WarnLabel` / `DangerLabel` | Label | semantic colours (colour-mode aware) |
| `InsetPanel` | PanelContainer | recessed dark panel (4 px cuts) |
| `SidebarPanel` | PanelContainer | 18 px bottom-left cut, bracket BL |
| `RibbonPanel` | PanelContainer | 12 px cut on all corners |
| `Button` / `PrimaryButton` / `HeroButton` / `DangerButton` | Button | normal / accent fill / 54 px menu button (Orbitron 20) / red confirm (surrender, delete) |
| `CommandButton`, `TabButton`, `GhostButton` | Button | command bar, tabs, borderless |
| `TooltipPanel` / `TooltipLabel` | (built-in types) | tooltip frame + label |
| Menu-only `focus` stylebox | all Buttons/LineEdit/OptionButton | 2 px `skin.accent` outline, no fill (HUD widgets keep `FOCUS_NONE`, so it never shows in-game) |

#### 4.6.4 Colour tokens (`UiPalette`; the 18 tokens of `style.ui.tokens`, `art_direction.md` §5.12.2 — constants in code, asserted equal to the JSON by test U-1)

| Token | Hex | Contrast on `BG_PANEL` (computed) | Use |
|---|---|---|---|
| `BG_DEEP` / `BG_PANEL` / `BG_RAISED` / `BG_CONTROL` / `BG_HOVER` | `#06080b` / `#0b1016` / `#121a23` / `#182230` / `#213145` | — | surfaces, dark → light |
| `TEXT` | `#e6eef6` | 16.30 : 1 (11.27 on `BG_HOVER`) | primary text |
| `TEXT_DIM` | `#95a8bb` | 7.82 : 1 (5.41 on `BG_HOVER`) | secondary |
| `TEXT_MUTE` | `#7a8ca0` (the spike's `#5d6f83` measured 3.70 : 1 and was renamed `TEXT_DISABLED`) | 5.53 : 1 (5.08 on `BG_RAISED`, 4.64 on `BG_CONTROL`; **3.83 on `BG_HOVER`: use `TEXT_DIM` there**) | tertiary text that must stay readable |
| `TEXT_DISABLED` | `#5d6f83` | 3.70 : 1 | disabled controls and decoration only, never essential information (WCAG-exempt) |
| `LINE_DIM` / `LINE` | `#212d3b` / `#35465a` | 1.37 : 1 / 1.98 : 1 | decorative dividers |
| `LINE_BRIGHT` | `#5f7a96` | 4.28 : 1 (3.60 on `BG_CONTROL`) | borders of interactive controls (≥ 3 : 1 non-text rule); the high-contrast HUD border |
| `CREDITS` / `OK` / `WARN` / `DANGER` / `POWER` | `#ffd35c` / `#5ce383` / `#ffb52a` / `#ff5555` / `#49d0ff` | 13.39 / 11.61 / 10.81 / 6.08 / 10.68 | semantic |
| `BLACK_A` | `#0000008c` | — | scrims and text shadows |
| Faction accents on `BG_PANEL` | napc `#f07f2c` 7.07, nec `#5b93e0` 6.09, olm `#2fc9bb` 9.27, def `#e0503a` 4.89, pd `#33a0ec` 6.71, han `#33c98a` 8.97, ae `#26d6e8` 10.79, sap `#f3a622` 9.35 | all ≥ 4.5 | headers, focus rings, fills |
| Dark text on an accent fill (`#10161d`) | — | 4.66 (def) … 10.28 (ae) | primary buttons |

Relation colours (`style.ui.relation`; used by UI widgets: minimap own-dot outline, pings, tooltips, cursor tints, and by the view for rings and bars, `art_direction.md` R-20): SELF `#5ce383` (= OK), ALLY `#49d0ff` (= POWER), ENEMY `#ff5555` (= DANGER), NEUTRAL `#ffd35c`; colour is never the only signal (self solid · ally solid + diamond pip · enemy four notches + cross pip · neutral dashed, art 5.12.5). Health colours (`style.ui.hp_ramp`): OK ≥ 66 %, WARN 33-66 %, DANGER < 33 % with segment ticks at 33 / 66 % — the selection-panel HP bar and the view's bars share the ramp (`FxStyle.hp_color`), replacing the 60 / 30 % of `render.md` §5.10 (art RK-24).

#### 4.6.5 Motion (`UiMotion`; every duration is 0 when `access/reduce_motion`; timings of `art_direction.md` §5.12.4)

| Effect | Duration | Easing |
|---|---|---|
| hover glow / state change | 0.09 s | `TRANS_CUBIC`, `EASE_OUT` |
| press | 0.06 s | linear |
| panel / ribbon slide | 0.18 s in, 0.25 s out (24 px) | `TRANS_CUBIC`, `EASE_OUT` / `EASE_IN` |
| screen fade out / in | 0.18 s / 0.22 s | `TRANS_QUART`, `EASE_OUT` |
| toast | in 0.15 s, hold 4 s, out 0.3 s | — |
| credit ticker | rolls to the new value in 0.3 s | `TRANS_CUBIC`, `EASE_OUT` (worked example 5.10.7) |
| pulses | card READY, ribbon DANGER, low power: 1 Hz alert pulse (border / fill) | nothing else animates faster than 2 Hz; ≤ 3 Hz in any case (photosensitivity) |

### 4.7 Graphics quality (contents owned by the view; persistence and options UI owned by the app)

#### 4.7.1 What is where

The preset tables (LOW / MEDIUM / HIGH / ULTRA), the renderer clamps (Mobile, Compatibility) and the auto-downgrade ladder are the view's (`render.md` §4.9, §5.12, §7.7 `quality.json`). The app **does not duplicate them**: it persists the player's choices under `[video]` using the view's key names, shows them on the Graphics page, and hands the resulting `ConfigFile` to `ViewQuality.from_settings(cfg, presets)` (through `UiViewPort.apply_quality`). A key that is absent means "the preset's value"; a key that is present overrides it, so the store's "write only non-default values" rule (5.20.1) and the view's rule are the same rule.

#### 4.7.2 The user-facing quality keys (`[video]`, exactly the names `ViewQuality.from_settings` reads)

| Key | Type | Values | Notes |
|---|---|---|---|
| `quality` | int | 0 low, 1 medium, 2 high, 3 ultra, 4 auto | the preset; default = `ViewQuality.recommend()` written at first run (discrete GPU → high, integrated → medium, software / other → low, Mobile and Compatibility capped at medium; Apple silicon is not name-matched, it reaches HIGH through auto-upgrade); 4 enables `ViewQualityAuto` (steps down after 2 bad 3-s windows, up after 10 good ones, never above the user's cap, toast on change). The name `quality` is the one of `render.md` §7.7 and `qa.md` `[QA-XR-13]` |
| `renderer` | string | `""` (project default), `forward_plus`, `mobile`, `gl_compatibility` | **needs a restart** (a renderer cannot change at run time): `AppRelaunch` restarts once with `--rendering-method`; the effective renderer is always `RenderingServer.get_current_rendering_method()`; the row is hidden when `AppRelaunch.supported()` is false (headless, editor) |
| `render_scale` | float | 0.5 … 1.0 step 0.05 | `Viewport.scaling_3d_scale`; independent of the UI scale |
| `scaling_mode` | string | `bilinear`, `fsr1`, `fsr2`, `metalfx_spatial`, `metalfx_temporal` | `fsr2` needs Forward+; MetalFX only when `RenderingServer.get_current_rendering_driver_name() == "metal"` (a driver check, never an OS-name check); FSR2 / MetalFX-temporal disable MSAA |
| `msaa` | int | 0 off, 1 2x, 2 4x, 3 8x | Compatibility caps at 4x |
| `fxaa` | bool | | Forward+ / Mobile only |
| `shadow_mode` | string | `blob`, `cascades2`, `cascades4` | |
| `ssao` | string | `off`, `low_half`, `medium_half`, `high_full` | Forward+ only |
| `ssil` | bool | | Forward+ only |
| `glow` | bool | | |
| `decor_density` | float | 0.0 … 1.0 | |
| `health_bars` | int | 0 never, 1 selected, 2 damaged, 3 always | forwarded to `ViewHealthBars.set_mode`; default 2 |
| `unit_outline` | int | 0 off, 1 thin, 2 bold | readability outline (`art_direction.md` R-16; QA A-15 wants it in the high-contrast HUD): default 1 (thin) on Medium and above, the view clamps it to 0 on Low; `access/high_contrast_hud` raises the effective level to at least 2 in the view |
| `unit_backend` | int | −1 auto, 0 nodes, 1 batch | advanced |
| `night_maps` | bool (the view reads 0 / 1) | | urban maps may render as night maps (`ViewBuildOptions.night_allowed`); default on |
| `wide_view` | bool | | camera `height_max` 110 m instead of 84 m |

The Graphics page shows a single **Preset** dropdown (Low, Medium, High, Ultra, Auto) plus the rows above under "Advanced"; changing any advanced row while a fixed preset is selected shows "Custom (based on High)" (the dropdown text; the stored preset stays 2). The auto ladder's target frame time is `video/fps_cap` when it is above 0, else the display refresh rate (`render.md` §7.7); there is no separate target row. `camera_wasd` of `render.md` is never written: `A`/`S`/`D` are order hotkeys, camera panning is the rebindable `cam_pan_*` (arrows by default, 5.6.1). A capability guard (5.18.4) disables rows the running renderer cannot honour and says why in the tooltip.

#### 4.7.3 Hand-off

`AppSettings.graphics_quality_changed()` is emitted after any `video/*` quality key changed; `AppApply` builds a `ConfigFile` containing the store's `[video]` section and calls `UiViewPort.apply_quality(cfg)`. In a match that is `ViewWorld.apply_quality` (live, terrain re-bake only when `terrain_subdiv` changed, ~200 ms threaded); in menus it is the `for_menus()` adapter (backdrop, icons). The `ViewQuality` object is created by the view; the app never stores it.

### 4.8 Settings

#### 4.8.1 Schema rows (`AppSettingsSchema.entries()`; the complete list — the options UI is generated from it)

Row shape: `{id, type, default, min, max, step, choices: Array[{value,label_key}], apply: StringName, restart: bool, guard: StringName}`. `apply` hook ∈ `video audio input ui quality net misc`. The id is `section/key`; sections and key names follow `qa.md` request `[QA-XR-13]` where it names them (`meta`, `video`, `audio`, `access`, `controls` = key bindings, `net`) and `render.md` §7.7 for the quality keys; everything else lives in `input`, `ui` and `game`.

| id | type | default | range / choices | apply | notes |
|---|---|---|---|---|---|
| `meta/version`, `meta/first_run` | INT / BOOL | 1, true | | misc | migration + first-run flag |
| `video/window_mode` | CHOICE | 0 | 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen | video | default windowed; borderless is the recommended fullscreen (QA X-12) |
| `video/resolution` | VECTOR2I | (1600, 900) | min (1024, 576) | video | windowed size, remembered |
| `video/window_pos`, `video/monitor` | VECTOR2I / INT | (−1, −1), −1 | | video | −1 = let the OS place; on load the rectangle is clamped to the existing screens (QA X-13) |
| `video/ui_scale` | INT | 100 | 75 … 200 step 5 | ui | text-size control (A-03); the effective factor is limited so the logical height stays ≥ 540 (5.4.1) |
| `video/vsync` | CHOICE | 1 | 0 off, 1 on, 2 adaptive, 3 mailbox (`DisplayServer.VSYNC_*`) | video | |
| `video/fps_cap` | CHOICE | 0 | 0 (unlimited), 30, 60, 90, 120, 144, 165, 240 | video | `Engine.max_fps` |
| `video/background_fps` | INT | 30 | 0 … 240 (0 = same) | video | applied on focus-out; the sim keeps ticking |
| `video/quality` … `video/wide_view` | | | the 15 quality keys of 4.7.2 | quality | `video/quality`, `render_scale`, `scaling_mode`, `msaa`, `fxaa`, `shadow_mode`, `ssao`, `ssil`, `glow`, `decor_density`, `health_bars`, `unit_outline`, `unit_backend`, `night_maps`, `wide_view` |
| `video/renderer` | CHOICE | `""` | `""` project default, `forward_plus`, `mobile`, `gl_compatibility` | video | restart required (`AppRelaunch`, 4.7.2); guard `renderer_switch` |
| `audio/master`, `audio/music`, `audio/sfx`, `audio/voice`, `audio/ui`, `audio/ambience` | INT | 100, 70, 90, 100, 80, 70 | 0 … 100 | audio | the `SndSettings` defaults (`audio.md` §4.5); slider → gain `(v/100)²`, 0 = mute — the curve, bus defaults and ramping are audio's |
| `audio/announcer` | CHOICE | 0 | 0 faction voice, 1 computer voice, 2 off | audio | `SndSettings.ANN_*` |
| `audio/unit_voices` | CHOICE | 0 | 0 radio bleeps, 1 voice barks, 2 mixed, 3 off | audio | `SndSettings.UV_*` |
| `audio/music_mode` | CHOICE | 0 | 0 dynamic, 1 calm only, 2 off | audio | `SndSettings.MUSIC_*` |
| `audio/dynamic_range` | CHOICE | 0 | 0 full, 1 night (compressed) | audio | `SndSettings.DR_*` |
| `audio/quality` | CHOICE | 1 | 0 low, 1 medium, 2 high | audio | `SndSettings.Q_*` (bank size / voice count trade-offs are audio's) |
| `audio/mute_unfocused` | BOOL | true | | audio | honoured by audio (its manager is an autoload node and sees the focus notifications) |
| `audio/output_device` | STRING | `"Default"` | `AudioServer.get_output_device_list()` | audio | applied by audio (`audio.md` R5) |
| `audio/captions` | BOOL | true | | ui | show the `announcement_started` caption of every spoken line that no notice already covers (QA name; A-07) |
| `access/colour_mode` | CHOICE | `normal` | `normal`, `cvd` | ui | team colours (`ViewStyle.player_color(id, cvd)`), the semantic OK / WARN / DANGER / POWER set and the structure-blip pip shapes (5.19.3); the string form is what `cases.json` uses. `cvd` is `art_direction.md`'s `cvd_palette` (R-22); the first-run page and the lobby hint offer it (5.2.2, 5.14.2) |
| `access/reduce_motion`, `access/reduce_flash` | BOOL | false, false | | ui | 5.19.4 |
| `access/high_contrast_hud` | BOOL | false | | ui | opaque panels, thick borders, and — through the view — thicker rings, unit outlines, larger health bars (A-15) |
| `access/ui_font` | CHOICE | 0 | 0 default (Rajdhani / Orbitron), 1 dyslexia-friendly (Atkinson Hyperlegible, OFL) | ui | A-17; hidden if the font files are not vendored |
| `access/announcer_tts` | BOOL | false | | audio | audio speaks the announcer caption with the OS voice instead of the recorded line (`SndAnnouncer.set_tts`, A-14, `audio.md` §5.9 step 8); off by default; hidden when `DisplayServer.tts_get_voices_for_language("en")` is empty (guard `tts`) |
| `access/cursor_scale` | CHOICE | 100 | 100 (32 px), 150 (48 px), 200 (64 px) | ui | source image size of the custom cursors, A-21 |
| `access/edge_scroll_enabled` | BOOL | true | | input | |
| `access/edge_scroll_speed` | INT | 100 | 25 … 200 (%) | input | |
| `input/confine_cursor` | CHOICE | 1 | 0 never, 1 fullscreen only, 2 always | input | `Input.mouse_mode = CONFINED` while in a match and focused |
| `input/key_scroll_speed`, `input/rotate_speed`, `input/zoom_speed` | INT | 100 | 25 … 200 (%) | input | |
| `input/invert_zoom`, `input/invert_orbit` | BOOL | false | | input | |
| `input/orbit_mode` | CHOICE | 0 | 0 hold MMB, 1 toggle (click to start, click to stop) | input | A-20 |
| `input/double_click_ms` | INT | 350 | 200 … 600 | input | |
| `input/drag_threshold` | INT | 6 | 3 … 16 | input | |
| `input/sidebar_hover_hotkeys` | BOOL | false | | input | letters act as card hotkeys while the pointer is over the sidebar |
| `input/group_double_tap_center` | BOOL | true | | input | |
| `input/sticky_modes` | BOOL | false | | input | armed modes stay armed after a click (as if Shift were held) |
| `input/move_speed_match` | BOOL | false | | input | `MOVE` / `ATTACK_MOVE` / `PATROL` flags b1: the group moves at its slowest member (`sim_core.md` §6.1 v2.1; off = the movement domain's default) |
| `input/move_reverse` | BOOL | false | | input | flags b2: vehicles may reverse on short moves |
| `input/esc_clears_selection` | BOOL | false | | input | Esc chain step 5 (5.5.7) |
| `input/pause_on_menu`, `input/pause_on_focus_loss` | BOOL | true, true | | input | **LOCAL role only** |
| `ui/sidebar_side` | CHOICE | 0 | 0 right, 1 left | ui | |
| `ui/minimap_sweep` | BOOL | true | | ui | |
| `ui/tooltips` | BOOL | true | | ui | |
| `ui/tooltip_delay_ms` | INT | 500 | 0 … 1500 | ui | `gui/timers/tooltip_delay_sec` |
| `ui/chat_fade_s`, `ui/chat_opacity` | INT | 8, 85 | 3 … 30, 20 … 100 | ui | |
| `ui/show_fps` | BOOL | false | | ui | |
| `ui/cursor_style` | CHOICE | 0 | 0 custom, 1 system | ui | |
| `ui/brackets` | BOOL | true | | ui | selection rings and brackets (`ViewSelection`); off = the UI never calls `set_selection` / `set_hover` |
| `ui/range_rings` | CHOICE | 0 | 0 single selection only, 1 all selected armed (≤ 12), 2 off | ui | placing a defense always shows its ring |
| `ui/camera_pad` | BOOL | true | | ui | 5.11.7 |
| `ui/strategic_markers` | BOOL | true | | ui | role-glyph markers on every visible unit below 18 px per metre (5.12); forced off by `UiHud.lite` |
| `game/language` | STRING | `"en"` | English only (row disabled) | misc | |
| `game/last_roster`, `game/last_skirmish`, `game/skirmish_preset` | STRING | `"roster.napc.vanilla"`, `""`, `""` | JSON of the last lobby state | misc | |
| `game/tips` | BOOL | true | | misc | |
| `net/player_name` | STRING | sanitised OS user name, else `"Commander"` | ≤ 24 chars | net | |
| `net/port` | INT | 27615 | 1024 … 65535 | net | |
| `net/last_address` | STRING | `""` | | net | |
| `net/recent_hosts` | LIST | `[]` | ≤ 8 `ip:port`, most recent first | net | |
| `net/discovery`, `net/allow_public_discovery` | BOOL | true, false | | net | |
| `net/min_input_delay` | INT | 2 | 1 … 4 | net | advanced; local sessions force 1 |
| `net/auto_drop_ms` | INT | 60000 | 0, 30000, 60000, 120000 | net | |
| `net/replay_autosave_count` | INT | 3 | 1 … 10 | net | |
| `net/record_chat`, `net/show_net_overlay`, `net/help_shown` | BOOL | true, false, false | | net | |
| `[controls]` | KEYS | `keymap_defaults.json` | 4.5.1 | input | dynamic section: `<action>=PackedStringArray(tokens)` (`qa.md` `[QA-XR-13]`) |

#### 4.8.2 File layout

```ini
; user://settings.cfg   (ConfigFile text; section = the part of the id before "/"; only non-default values are written)
[meta]
version=1
first_run=false

[video]
window_mode=0
resolution=Vector2i(1600, 900)
ui_scale=110
vsync=1
quality=2
render_scale=0.85

[audio]
master=100
music=70

[access]
colour_mode="cvd"

[net]
player_name="X42553"
recent_hosts=PackedStringArray("192.168.1.20:27615")

[game]
last_roster="roster.napc.canada"

[controls]
cmd_attack_move=PackedStringArray("k:65")
group_assign_1=PackedStringArray("k:268435505")
```

Unknown sections / keys are preserved verbatim on save (`_unknown`), invalid values fall back to the default and add a `load_notes` line (never an error dialog). The write protocol and recovery are in 5.20.1.

### 4.9 Match summary and stats

#### 4.9.1 Player stats (`UiSimPort.player_stats(pid, out)`; request `[XR-6]`)

All ints. Twelve come straight from counters `SimPlayer` already has (`sim_core.md` §4.6): `units_built` (`st_units_built`), `units_lost`, `units_killed`, `structures_built` (`st_structs_built`), `structures_lost`, `structures_destroyed` (`st_structs_killed`), `harvested` (`st_credits_earned`: harvest + salvage), `spent` (`st_credits_spent`), `damage_dealt`, `damage_taken`, `commands` (`st_cmds`: accepted commands; for APM), `peak_units` (`st_peak_units`); `research_done` is the number of set entries of `research_done[]`. **Four counters are requested** (hashed, DR-13): `st_value_killed` (Σ `paid` of enemy entities this player destroyed → `value_destroyed`), `st_value_lost` (Σ `paid` of own entities lost → `value_lost`), `st_powers_used`, `st_sw_launched`. Until they exist the adapter reports 0 for them and the end screen hides those rows and the military term of the score (5.16.5).

#### 4.9.2 Result summary (`AppMatch.result_summary(ctx)` → `UiScreenEnd`)

```
{ outcome: int (0 victory, 1 defeat, 2 draw, 3 observed), reason: int (net MatchEndReason), winner_team: int,
  duration_ticks: int, final_checksum: int, map_name: String, map_family: int, map_size: int, map_seed: int,
  players: [ {pid, name, roster_id, faction_code, team, color, status: int (net PlayerNetStatus), is_local: bool, is_ai: bool, ai_level: int,
              stats: Dictionary (4.9.1), score: int (UiScore), apm: int} … ],
  series: { pid: { "harvested": PackedInt32Array, "army": PackedInt32Array, "value_destroyed": PackedInt32Array } },   # one sample / 200 ticks
  replay_path: String, can_save_replay: bool, can_return_to_lobby: bool }
```

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Screen flow

#### 5.1.1 Diagram

```
                                  ┌───────────── OPTIONS (push/pop) ── FIELD_MANUAL (push/pop) ── CREDITS (push/pop) ─────────────┐
 BOOT ──► [splash] ──► MAIN_MENU ─┼─► SKIRMISH_LOBBY ─────────────┐                                                                │
   │                    │  ▲      ├─► LAN_BROWSER ─► LAN_LOBBY ───┼─► LOADING ─► IN_MATCH ─► END_SCREEN ─► MAIN_MENU              │
   │                    │  │      ├─► REPLAYS ──► LOADING ────────┘      │           │            ├─► SKIRMISH_LOBBY / LAN_LOBBY  │
   ▼                    │  │      └─► QUIT                       launch_aborted      │            └─► LOADING ─► REPLAY_PLAYBACK  │
 FATAL ◄── any (data load / world build / error storm)           back to lobby     Esc menu: resume · options · field manual ·     │
                                                                                     surrender · leave  (never leaves the match) ◄┘
```

#### 5.1.2 Edge table (`AppFlow.can_go`; anything not listed is illegal and logged)

| From | To | Trigger | Notes |
|---|---|---|---|
| BOOT | MAIN_MENU | boot finished | after splash minimum 1.2 s |
| BOOT | FATAL | `GameData.load_default() == null` | detail = `GameData.last_report.text()` |
| BOOT | LOADING | `--autostart=match\|replay` | skips splash minimum and menus |
| MAIN_MENU | SKIRMISH_LOBBY | button | `AppNet.start_local_lobby()` first; failure → message dialog |
| MAIN_MENU | LAN_BROWSER | button | first time: `UiDlgFirewallHelp` (explainer) must be acknowledged **before** the browser starts `start_browse()` (sets `net/help_shown`) |
| MAIN_MENU | REPLAYS / OPTIONS / CREDITS / FIELD_MANUAL | button | OPTIONS, CREDITS, FIELD_MANUAL are `push` (return with `pop`) |
| MAIN_MENU | QUIT | Quit button (no confirm: the main menu never holds a session or unsaved state) | `AppState.quit_game()`: flush settings, delete `.session`, `get_tree().quit()` |
| SKIRMISH_LOBBY | MAIN_MENU | Back / Esc | ends the LOCAL session; unsaved slot edits are persisted as "last skirmish" first |
| SKIRMISH_LOBBY | LOADING | Start | `lobby.host_start()` returned `OK` |
| SKIRMISH_LOBBY / LAN_LOBBY | FIELD_MANUAL / OPTIONS | push | lobby stays alive underneath |
| LAN_BROWSER | LAN_LOBBY | host created or join accepted | `AppNet.host_lan()` / `join_lan()` → phase `LOBBY` |
| LAN_BROWSER | MAIN_MENU | Back | stops discovery |
| LAN_LOBBY | LAN_BROWSER | Leave / `kicked` / host left / `join_rejected` | message dialog first |
| LAN_LOBBY | LOADING | phase `COUNTDOWN` → `LOADING` | countdown overlay in the lobby |
| LOADING | IN_MATCH | `match_started` | |
| LOADING | SKIRMISH_LOBBY / LAN_LOBBY | `launch_aborted(reason, detail)` | dialog with `net.err.*` text; lobby is unlocked again |
| LOADING | MAIN_MENU | Cancel | LOCAL: discard; host: cancels launch (`host_cancel_start`) ; client: `leave()` |
| IN_MATCH | END_SCREEN | `match_ended` (banner 2.5 s first) or LOCAL "Leave" | |
| IN_MATCH | MAIN_MENU | Esc menu → Leave (confirm; MP: counts as surrender-and-leave) | `AppNet.end_session()` |
| IN_MATCH | OPTIONS / FIELD_MANUAL | push | game keeps running (MP) or is paused (LOCAL, `input/pause_on_menu`) |
| IN_MATCH | FATAL | error storm during load-critical work, world corruption | desync uses a dialog, not FATAL |
| END_SCREEN | MAIN_MENU / SKIRMISH_LOBBY / LAN_LOBBY / REPLAY_PLAYBACK | buttons | `RETURN_TO_LOBBY` moves everybody to `LAN_LOBBY` |
| REPLAYS | REPLAY_PLAYBACK | Watch | through LOADING (same job) |
| REPLAY_PLAYBACK | REPLAYS / MAIN_MENU | Back | |
| any | FATAL | `AppCrash.show()` | |

#### 5.1.3 Per-screen lifecycle duties

| Screen | On enter | On exit |
|---|---|---|
| main menu | `UiKeymap.install(MENU)`, `Snd.set_mode(MODE_MENU)`, `AppScenes.set_backdrop(view.showcase(featured))`, featured faction rotates every 30 s (cross-fade 0.6 s) | free backdrop |
| lobby | `MODE_LOBBY`; roster icons baked lazily for the hovered slot; chat focus policy | stop timers; session stays |
| LAN browser | after explainer: `NetDiscovery.start_browse()`; refresh timer 1 s | `stop_browse()` (always) |
| loading | `MODE_LOADING`; tips rotate every 6 s; `Engine.max_fps = 0` during load (no cap) | restore cap |
| game | `UiKeymap.install(GAME or OBSERVER)`, `MODE_MATCH`, `Input.mouse_mode` per `input/confine_cursor`, `OS.low_processor_usage_mode = false` | uninstall keymap, mouse mode `VISIBLE`, drop ports |
| end | `MODE_POST_MATCH` (after `Snd.end_match(result)`) | — |
| options | remember previous values for **Revert**; live preview of every change | flush settings |

---

### 5.2 Boot, first run and headless boot

#### 5.2.1 Timeline (targets on the reference Mac; the splash must be on screen within 100 ms of process start)

| t (ms) | Step | Budget | Failure handling |
|---|---|---|---|
| 0 | `boot.gd`: `--smoke` check (print the extended `MERIDIAN_BOOT …` line, exit 0), `--qa=<job>` / `--selfcheck` hooks, else `AppBoot.run(self)` | 1 | — |
| 0-5 | `AppLaunchArgs.parse`; `AppPaths.ensure_user_dirs()`; `Log.sink = AppLogSink`; `AppLogger.install()`; `Fp.self_test()` (failures are logged and counted for the smoke line) | 5 | logging failure → continue, in-memory ring only |
| 5-25 | `AppSettings.ensure_loaded()` (file ≤ 4 KB); `AppCrashReporter.start_session()` (writes `.session`, detects an unclean previous run); `AppApply.apply_video/ui scale/audio` with the saved window rectangle clamped to existing screens; `UiLayout.apply(window)` | 20 | corrupt file → renamed `.bad-<utc>`, `.bak` tried, else defaults |
| 25-60 | `UiFonts` (4 files, 1.4 MB), `UiText.load_all`, `ViewStyle.load_file()` (~2 ms; `null` → a built-in fallback skin and one error toast in a release build, the fatal screen in a development build, `art_direction.md` §3) and `UiSkinSet.setup(style)`, `UiThemeService.rebuild(neutral)` (5-9 ms first build), `AppScenes` layers; **splash shown** | 35 | missing font → `Log.error`, engine default font (never fatal) |
| 60-330 | `GameData.load_default()` (150-250 ms, synchronous, splash text "Loading game data") | 270 | `null` → FATAL(DATA_LOAD_FAILED) |
| 330-380 | `NetReplay.recover_orphans()`; `UiKeymap.load_from(store)`+`install(MENU)`; `UiCursors.register_all` (27 cursor images: 17 base + 2 reticle variants + 8 scroll arrows, one bake batch ≈ 60 ms); `AppAudio.setup()` (`Snd.setup()`: audio JSON + bus layout, cost is audio's) and `apply_settings` | 70 | cursor bake failure → system cursors; audio data error → silent game + one toast |
| 380-600 (warm) / 380-3,300 (cold pipeline cache, measured 2.6-2.8 s in the spike) | `UiIconBaker.prewarm()`: hidden lit 3D scene with one model + shadow + particles so the pipeline cache is populated **behind the splash**; progress bar | 220 / 2,900 | skipped when `--no-prewarm` |
| ≥ 1,200 | unclean-exit toast if the `.session` sentinel was stale (5.20.3); first-run welcome (5.2.2); then `MAIN_MENU` | — | — |

Targets: warm boot to interactive menu ≤ 2.0 s; cold ≤ 5 s. The splash is skippable after 0.4 s but never before `GameData` finished.

#### 5.2.2 First run (`meta/first_run == true`)

One compact dialog: *Commander name* (default sanitised OS user name), *Graphics* (dropdown pre-set to `AppGraphics.recommend()` with the adapter name shown), *UI scale* (Auto = 100 %), *Colour-vision safe palette* (off; a checkbox with a one-line explanation and a live swatch preview, `access/colour_mode`). Confirming writes the settings and clears `first_run`. Nothing else is asked (no account, no telemetry).

#### 5.2.3 Headless / test boot (`AppTestBoot`)

`godot --headless --path game -- --autostart=match --config=<json> [--ticks=N] [--quit-on-end] [--speed=0] [--with-ui] [--script-cmds=<json>]`

| Arg | Meaning |
|---|---|
| `--smoke` | print the extended `MERIDIAN_BOOT` line (with `version`, `build`, `selftest` from `Fp.self_test()`) and exit 0 (contract with `tools/py/export.py`) |
| `--qa=<job>`, `--selfcheck` | QA hooks (`qa.md` `[QA-XR-11]`): run `res://tests/harness/qa_entry.gd` if present and quit with its exit code; `--selfcheck` = the export manifest verification; both are ignored when the file is absent |
| `--screen=<id>` | open that screen directly after boot (screenshots): `main_menu, lobby, lan_browser, loading, game, end, replays, field_manual, options, credits, fatal` |
| `--fixture=<name>` | back `game`/`lobby`/`end` with `UiSimPortFixture`/`UiViewPortFixture` data from `tests/fixtures/ui/<name>.json` (no sim needed) |
| `--faction=<code>`, `--roster=<id>`, `--ui-scale=<f>`, `--palette=<normal\|cvd>` | skin / roster / scale / colour-mode overrides (not persisted) |
| `--autostart=match` | build a `NetSession.local_from_config` from `--config` (or `default_rules()` + `--players=N --ai-level=L --map-seed=S`), run to the end or `--ticks` |
| `--autostart=replay --replay=<path>` | `NetReplayPlayer` headless verify/playback |
| `--speed=<pct>` | `0` = unpaced (net.md §5.5.9), else percent |
| `--with-ui` | also build the HUD, `UiHudPresenter`, `UiInputController` against the real ports (no rendering in `--headless`) and drive a scripted human through `UiCommandBus` |
| `--script-cmds=<json>` | `[{"tick": 40, "op": "train", "producer": "barracks#0", "def": "unit.napc.rifle_squad", "count": 2}, {"tick": 200, "op": "attack_move", "ids": "all_military", "x": 60, "y": 60}, …]` (`op` = a `UiCommandBus` helper name such as `train`, `build_start`, `build_place`, `sell`, `use_power`, or an order kind such as `move`, `attack_move`, `attack`, `stop`, which the harness wraps in a `UiOrderIntent` and sends through `dispatch()`; `"all_military"` = the `Ctrl+A` set of the local player) |
| `--fresh-settings`, `--no-audio`, `--no-prewarm` | test hygiene; `--fresh-settings` uses an in-memory `AppSettingsStore` and never writes `user://settings.cfg` |
| `--page=<id>`, `--popup=1`, `--preview=<a,b>` | screen-specific extras passed through `AppLaunchArgs.extras` (options page; open the first dropdown; HUD previews `place`, `power`, `drag`, `tooltip`, `lowpower`) |

Output (one line each, greppable): `APP_READY mode=<mode> data_hash=<%08X>`, `APPTEST tick=<n> chain=<%08X> checksum=<%08X> cmds=<n> ui_cmds=<n> refused=<n>`, `APPTEST_END reason=<victory\|defeat\|ticks\|timeout> tick=<n>`. Exit codes: 0 ok, 2 data load failed, 3 world build failed, 4 desync, 5 timeout (wall-clock cap `--timeout-s`, default 600).

---

### 5.3 The match-start pipeline (skirmish, LAN host, LAN client and replay are the same code)

| # | Actor | Step |
|---|---|---|
| 1 | `UiScreenLobby` | Start pressed → `session.lobby.host_start()`. A non-`OK` `NetLobby.StartError` is rendered inline (table 5.14.4) and the offending row/field is highlighted; nothing else happens. |
| 2 | `NetSession` | `Phase.COUNTDOWN` (LOCAL: `countdown_s = 0`; LAN: 3 s, `countdown_changed(n)` drives the lobby overlay and `snd.ui.lobby_countdown_tick`). Lobby is locked except `SET_READY(false)` (aborts). |
| 3 | `AppState` | On `phase_changed(LOADING)` → `go(LOADING, {kind:"match"})`. The host built `MatchConfig`; every peer calls `opts.world_builder(config)` = `AppMatch.begin_build(config, true)` → `AppMatchJob`. |
| 4 | `AppMatchJob.step(4 ms)` per `poll()` | Phases below. The engine main loop keeps servicing ENet because each `step` returns within 4 ms (net.md §5.4 step 3). |
| 5 | `UiScreenLoading` | Shows the map card (name, family, size, seed as 8 hex digits), the player list with emblem, colour, roster name and **per-player progress bars** from `load_progress(pids, percents)`; the local bar and label come from `job.progress_pct()` / `job.phase_name()`. Tips from `tips_en.json` every 6 s. Cancel button per 5.1.2. |
| 6 | net | `LOAD_DONE` → `WAIT_START` (local bar 100 %, label "Waiting for players") → `START` → `match_started`. |
| 7 | `AppState` | `AppMatch.make_context(session)` builds ports (`UiSimPortWorld`, `UiViewPortWorld`, `UiNetPortSession`, `UiAudioPortSnd`), `AppEvents` consumers are registered (audio 10 = `AppAudio.frame`, ui 20; the view is driven by `AppNet` right after `poll()`), `AppAudio.attach_world(view root)` runs, then `go(IN_MATCH, {ctx})`. The sim keeps no per-viewer event mask (`sim_core.md` §5.7): the fog rule is the consumers' (5.13.1). |
| 8 | `UiScreenGame.enter` | HUD built from `ctx.roster` and `ctx.skin`; theme rebuilt with the local faction skin; camera centred on the local start position; fade-in 0.22 s; audio plays the faction motto and `match_start` on entering `MODE_MATCH`; groups/bookmarks empty. |
| 9 | running | 3.0 frame order. |
| 10 | `match_ended(result)` | banner "VICTORY / DEFEAT / DRAW / MATCH ENDED" for 2.5 s over the frozen game → `go(END_SCREEN, {summary})`. The `NetSession` stays alive (replay saving, RETURN_TO_LOBBY) until the user leaves the end screen. |

**`AppNet.make_options()` → `NetSessionOptions` (net.md §3.1):**

| Option field | Source |
|---|---|
| `player_name` | `net/player_name` |
| `game_version` / `sim_version` / `data_hash` | `AppInfo.version()` / `SimConfig.SIM_VERSION` / `GameData.data_hash` |
| `roster_ids` | `GameData.roster_ids()` (exactly 32, ascending) |
| `color_count`, `ai_level_count`, `ai_style_count` | `ViewStyle.player_color_count(false)` = 12 (the wire ids 0-11 never depend on the local colour mode; `cvd` only hides swatches 8-11 locally) / `AiFactory.level_count()` / `AiFactory.style_count()` |
| `port`, `discovery_enabled`, `min_input_delay_turns` | `net/port`, `net/discovery`, `net/min_input_delay` |
| `record_replay`, `record_chat`, `replay_autosave_count` | true, `net/record_chat`, `net/replay_autosave_count` |
| `auto_clear_events` | **false** (`AppEvents` clears after the consumers ran) |
| `world_builder` / `ai_factory` / `map_validator` | `Callable(AppMatch, "begin_build")` / `"make_ai_thinker"` / `"validate_map"` |
| `password` | lobby dialog / join dialog (never persisted) |
| `allow_solo` | `false` (`--autostart` tests set it `true`) |

**`AppMatchJob` phases (weights are initial; UI-05 re-tunes them from measured timings so the bar advances roughly linearly in wall time):**

| Phase | Weight | Work | Async detail |
|---|---|---|---|
| SIM | 0-50 % | delegate to the sim/map builder job (`NetSimAdapterWorld` construction; the map itself is built by `MapGenJob.begin(map_cfg)` on its worker thread — `step(budget_us)` polls, `progress_pct()` 0-100, `result()` a finalized `MapData`, `terrain_movement.md` §3.7) | if the builder is not sliceable it runs in one call and net raises ENet timeouts to `TIMEOUTS_LOADING` (net.md R4) |
| VIEW | 50-90 % | `await ViewWorld.build_async(world, local_pid, opts)` (`render.md` §3.1: globals and materials 2 %, terrain 20 %, water + atmosphere 5 %, decor 10 %, minimap bake 3 %, models 30 %, FX 5 %, material prewarm 15 %, **icons of the local roster 10 %**), reported through `build_progress(fraction, stage)`; the job maps the fraction onto 50-90 % and shows the view's `stage` label | the view slices to ≤ 8 ms per frame and yields on `process_frame`; the job's `step(budget_us)` just polls its state, so `NetSession.poll()` keeps running |
| AUDIO | 90-100 % (runs concurrently) | `AppAudio.begin_match(config, local_pid, observer, replay)` at the start of the VIEW phase → `Snd.begin_match(SndMatchConfig)`; the banks (`core`, `fx_<faction>`, `vox_*`, `resp_*`, `mus_*`, `amb`) load with `ResourceLoader.load_threaded_request` (`audio.md` §5.13); the job reads `Snd.load_progress()` and waits for `Snd.is_match_ready()` | nothing blocks the main thread; a failed bank load is an `audio_warning`, never a load failure; skipped with `--no-audio` and under `--headless` |

Icons and shader/pipeline prewarm therefore live **inside** the view's build (the view bakes the local roster's icons and warms one hidden instance per style for 3 frames); the UI has no separate ICONS / PREWARM phase. `ViewBuildOptions` used by the job: `bake_icons = true`, `prewarm_scope = 1` (rosters present in the match), `screenshot_mode` only for `gd shot`.

Under `--headless` there is no renderer (`frame_post_draw` never fires, `qa_tooling.md` gotcha 8), so the job is created with `with_view = false`: the VIEW phase is skipped and any HUD built for a test shows glyph fallbacks instead of baked icons.

Budgets (from `render.md` §5.8.10 and `qa.md` §5.8): an icon bakes in ≈ 19 ms warm (two frame waits, one per frame), the first icon costs 2.7 s on a cold Metal shader cache, the local roster (≈ 35 defs) bakes in ≈ 0.7 s while the loading screen shows; "Start → first controllable frame" must stay ≤ 5 s (2 players, 128 x 128) and ≤ 9 s (8 players, 192 x 192).

---

### 5.4 Scale, layout and responsive rules

#### 5.4.1 The scale rule (verified in the spike at 0.75 / 1.0 / 1.5)

```
factor = clamp(window_pixel_height / 1080.0, 0.75, 2.0) * ui_scale          # ui_scale = settings video/ui_scale / 100  (0.75 … 2.0)
factor = minf(factor, window_pixel_height / 540.0)                            # the logical height never drops below 540 (the COMPACT layout's floor)
factor = clamp(factor, 0.5, 4.0)                                              # absolute guard
Window.content_scale_factor = factor         (project: display/window/stretch/mode = "disabled", window/dpi/allow_hidpi = true)
logical_size = window_pixel_size / factor
```
`Window.size` is in **pixels** even on Retina (`screen_get_scale() == 2.0` yet `--resolution 1920x1080` gave a 1920x1080-pixel window, spike), so no `screen_scale` term exists. Text is re-rasterised crisply by the font server.

| Window px | `video/ui_scale` | factor | logical size | Size class |
|---|---|---|---|---|
| 1920 x 1080 | 100 | 1.000 | 1920 x 1080 | REGULAR |
| 1600 x 900 | 100 | 0.833 | 1920 x 1080 | REGULAR |
| 1280 x 720 | 100 | 0.750 (0.667 clamped) | 1706.7 x 960 | REGULAR |
| 1366 x 768 | 100 | 0.750 | 1821.3 x 1024 | REGULAR |
| 1024 x 576 (minimum) | 100 | 0.750 | 1365.3 x 768 | COMPACT |
| 2560 x 1440 | 100 | 1.333 | 1920 x 1080 | REGULAR |
| 3440 x 1440 (ultrawide) | 100 | 1.333 | 2580 x 1080 | REGULAR |
| 3840 x 2160 | 100 | 2.000 | 1920 x 1080 | REGULAR |
| 3840 x 2160 | 125 | 2.500 | 1536 x 864 | REGULAR |
| 1920 x 1080 | 150 | 1.500 | 1280 x 720 | COMPACT |
| 1920 x 1080 | 200 | 2.000 | 960 x 540 (the floor) | COMPACT |
| 1280 x 720 | 200 | 1.333 (1.5 limited by the floor) | 960 x 540 | COMPACT |
| 3840 x 2160 | 200 | 4.000 | 960 x 540 | COMPACT |
| 5120 x 2880 | 100 | 2.000 (2.667 clamped) | 2560 x 1440 | LARGE |

`UiLayout.apply(window, ui_scale)` runs at boot, on `video/ui_scale` change, on `Window.size_changed` (debounced 100 ms so a live drag-resize does not re-layout every frame) and on `NOTIFICATION_WM_DPI_CHANGE`. It also sets `Window.min_size = 1024 x 576`. When the floor limits the factor the options page shows the effective value ("200 % requested, 178 % effective at this window size"). 3D rendering is independent (`scaling_3d_scale`), so a UI scale of 2.0 never lowers 3D resolution.

#### 5.4.2 Size classes and the rules they trigger

| Class | Logical height | Rules |
|---|---|---|
| COMPACT | < 800 | minimap `clamp((h − 420) × 0.55, 180, 300)` (h = 720 → 180); queue strip and sidebar footer hidden; log 4 lines; ribbons max 3; lobby briefing collapses to tabs; Field Manual shows list **or** detail (drill-down) |
| REGULAR | 800-1299 | spike layout (screenshots at 1920x1080) |
| LARGE | ≥ 1300 | log 10 lines; bottom panel max width 1000; Field Manual shows list + detail + 3D viewer side by side |

Other responsive rules: selection panel width `clamp(playfield_w − 40, 600, 900)` where `playfield_w = logical_w − 348`; menus and screens centre a content column of at most 1920 logical px on ultrawide windows (side gutters show the vignette); HUD panels stay anchored to window edges. With `ui/sidebar_side = 1` the sidebar anchors left and `play_area` mirrors (all offsets are computed from one `sidebar_left: bool`).

---

### 5.5 Input model

#### 5.5.1 Event routing (every row verified by the spike's input lab, cases A-S, unless marked *new*)

| Event | Handler | Rule |
|---|---|---|
| LMB press, pointer over the world | `UiInputController._unhandled_input` | starts a gesture; requires the HUD root `UiHud` to be `MOUSE_FILTER_IGNORE` (case A: STOP eats every world click, PASS leaks, IGNORE is the only correct value) |
| LMB press over a STOP panel / button | that `Control._gui_input` | the world never sees it; a Button still gets the release even if the pointer left it (case G, implicit grab) |
| Labels (default IGNORE) inside a STOP panel | fall through to the panel | (case C) never put a PASS panel over the HUD: it leaks clicks (case E) |
| Motion/release while a world gesture is active | `_input` (before the GUI) | `set_input_as_handled()`; otherwise motion over the STOP sidebar is swallowed and the selection rectangle freezes (case F/H) |
| Lost release (alt-tab, OS dialog) | `_process` polls `Input.is_mouse_button_pressed(LEFT)` | cancels the gesture unless `synthetic` (tests) |
| Window/app focus loss | `NOTIFICATION_WM_WINDOW_FOCUS_OUT`, `APPLICATION_FOCUS_OUT` | `cancel_gesture()`, edge scroll off, held keys and cursor confinement released, `background_fps` cap applied, the sim keeps ticking (case S; QA X-07); the click that regains focus is swallowed (an LMB press within 150 ms of `FOCUS_IN` starts no gesture) |
| RMB over the world | `_unhandled_input` → `context_click` | issues on **press**; RMB over the sidebar is consumed and never orders (case K) |
| Wheel over the sidebar | ScrollContainer; **all STOP HUD panels set `mouse_force_pass_scroll_events = false`** | otherwise the wheel zooms the camera through the panel (cases L/L2) |
| Arrow / Space / Enter with a focused Button | — | focus neighbours consume arrows and Space "presses" the button (cases N/N2/O) → **every HUD control is `FOCUS_NONE`** (case P); menus use focus deliberately (5.6.3) |
| Chat text entry | `LineEdit` focus owner | `UiInputController.enabled_keys = false` while `gui_get_focus_owner() is LineEdit` (also gates polled camera keys) |
| "Pointer over UI?" probe | `Viewport.gui_get_hovered_control() != null` | non-null over sidebar, null over the world when the root is IGNORE (lab "hover") |
| Key vs action | `UiKeymap.matches(event, action)` = `event.is_action_pressed(a, false, true)` | **exact match is mandatory**: measured E4 — plain `Ctrl+1` also matches the action bound to `1`, `Shift+S` matches `S`; the spike proved a hand-built key event needs `physical_keycode` to match actions bound by physical key |
| *new* Polled camera actions | `Input.is_action_pressed(a, true)` (exact) | `Q`/`E` rotation must be exact so `Alt+Q` (card 1) does not also rotate the camera |
| *new* Double click | own detector (5.5.3), not `InputEventMouseButton.double_click` | the flag is only reliably present on the press event and is absent on synthetic events; the spike read it from the release |

#### 5.5.2 World gesture state machine (`UiInputController`)

| State | Event | Guard | Next | Emits |
|---|---|---|---|---|
| IDLE | LMB down (unhandled) | `enabled` ∧ no modal | PRESS (store position, `mods`, time, hit eid) | — |
| PRESS | motion | `drag_exceeded(press, cur, thr)` (Euclidean ≥ `input/drag_threshold`, default 6 logical px) ∧ `armed == NONE` | BOX | `select_rect.show_rect` |
| PRESS | LMB up | `armed == NONE` | IDLE | `select_click(pos, mode, double)`; `mode` = toggle if Shift else replace |
| PRESS | LMB up | `armed != NONE` | IDLE | `armed_click(pos, mods)` |
| BOX | motion | — | BOX | update rectangle |
| BOX | LMB up | — | IDLE | `select_box(Rect2(press, cur).abs(), mode)`; `mode` = add if Shift else replace |
| PRESS/BOX | focus loss, modal opened, window resized, Esc, lost release | — | IDLE | hide rectangle, nothing emitted |
| IDLE | RMB down | `armed == NONE` | IDLE | `context_click(pos, mods)` |
| IDLE | RMB down | `armed != NONE` | IDLE | mode cancelled (no order) |
| IDLE | MMB down | — | ORBIT | — |
| ORBIT | motion | — | ORBIT | `camera_orbit(−rel.x × 0.22 × orbit_speed × inv, rel.y × 0.22 × orbit_speed × inv)` (degrees; `UiScreenGame` calls `view.rotate_yaw` / `view.tilt`) |
| ORBIT | MMB up / focus loss | — | IDLE | — |

Gestures *start* only in `_unhandled_input`, so a click on any STOP Control can never start a drag; once active, `_input` (which runs before the GUI) sees every event and consumes it.

#### 5.5.3 Click semantics, double click, box, hit priority

* **Single click on an own unit/structure:** replace selection with it (Shift: toggle membership). On empty ground: clear selection (Shift: keep). On an enemy/allied/neutral entity: replace with a `FOREIGN` inspect selection (info only). On a remembered structure ghost: same as enemy inspect.
* **Double click** (own detector): `now − last_press_time ≤ input/double_click_ms` ∧ `|pos − last_press_pos| ≤ 8` ∧ both presses hit the **same own unit** ⇒ `select_same_type_on_screen(kind, def_idx)`: every own, alive, non-contained, non-ghost entity of that (kind, def) (`ids_of_def(kind, def_idx)`) whose `entity_screen_rect` intersects the playfield rectangle (`viewport rect` minus the sidebar). Double click on a structure selects that structure only. `T` = same behaviour, `Ctrl+T` = whole map.
* **Box:** `view.pick_box(rect, PICK_UNITS | PICK_OWN, out)`; if the result is empty the same call runs with `PICK_STRUCTURES | PICK_OWN`. The view already excludes fog-hidden, contained (`F_INSIDE`) and ghost entities and accepts a unit when its mid point projects into the rectangle (structures: the centre). Over `MAX_SELECT = 500` candidates the UI keeps armed non-service units first (needs `UiUnitCaps`), then ascending id. `mode` add: union; the resulting selection is filtered to one `UiSelection.Mode` (units win over structures). While dragging, the call is repeated at ≤ 15 Hz only if the rectangle changed by ≥ 4 px (1.2 ms per call at 400 entities) and only feeds the rectangle's colour (valid / empty), not a per-entity preview.
* **Ray pick:** `view.pick(screen, PICK_ANY)` (`render.md` §5.11): ground hit `G` of the ray, candidates = units and wrecks within 4.5 cells of `G`, structures along a DDA walk of the structure grid toward the camera's ground foot, and all aircraft; oriented-box ray test per candidate; smallest ray parameter wins, ties (< 0.01 m) prefer non-wreck over wreck, unit over structure, lower id. Entities the view does not return (hidden by fog / camouflage / containers) can never be picked (5.9); remembered structures are returned only with `PICK_GHOSTS`, which the UI includes for hover and inspect.
* Cost (view, `render.md` §5.11): pick ≈ 60-90 µs, `pick_box` ≈ 1.2 ms at 400 entities (spike's UI-side picker for reference: 127 µs ray, 92 µs box). The hover probe runs at 30 Hz only while the pointer moves.

#### 5.5.4 Selection modifiers summary

| Input | Effect |
|---|---|
| click / drag | replace |
| Shift + click | toggle one |
| Shift + drag | add box |
| double click, `T` | same type on screen |
| `Ctrl+T` | same type on the whole map |
| `Ctrl+A` | all own combat units (not `CAP_SERVICE`, not structures) |
| selection tile click | replace with that unit; `Shift` remove it; `Ctrl`/`Cmd` (`is_command_or_control_pressed`) keep only its type |
| `Ctrl+Tab` | cycle the *active subgroup* (primary `def_idx`) inside a mixed selection — drives the ability bar and portrait |

#### 5.5.5 Camera, edge scroll, cursor confinement

The UI owns all camera input: at match start it sets `ViewCamera.auto_input = false` (`render.md` §3.3) and never calls `ViewCamera.ensure_input_actions()`, so the rebindable `UiKeymap` actions are the only ones in the `InputMap` and the view's own polling can never fight the UI's modal / focus / text-entry gating. The view's `camera/wasd_pan` option is replaced by rebinding `cam_pan_*`.

* **Keyboard pan:** `dir = (right − left, down − up)` from exact-polled `cam_pan_left/right/up/down` actions; `camera_pan(dir.limit_length(1), delta)` → `view.pan_screen`; the rig converts to metres (constant screen speed). Speed factor `input/key_scroll_speed / 100`.
* **Rotation/tilt/zoom:** `Q`/`E` → `camera_rotate(±1, delta)` → `view.rotate_yaw(±100° × rotate_speed × delta)`; `PageUp/PageDown` → tilt ±1° per repeat; wheel or `=`/`-` → `camera_zoom(±1 × zoom_speed × invert, cursor)` (zoom-to-cursor). **Trackpads (QA X-11):** `InputEventMagnifyGesture` → zoom (`factor − 1` scaled to steps), vertical `InputEventPanGesture` over the world → zoom like the wheel, horizontal pan ignored; every mouse-only camera action also has a key or a HUD button (the camera pad of 5.11.7).
* **Orbit:** MMB drag (`input/orbit_mode` 0 hold, 1 toggle — click once to start, click again to stop, A-20) → `camera_orbit(yaw°, tilt°)`; the camera pad has rotate / tilt buttons for laptops without a middle button.
* **HUD margins:** on every layout change `UiScreenGame` calls `view.set_camera_margins(0, 0, sidebar_w × factor, bottom_h × factor)` so `focus_on` (jump to alert, groups, bookmarks) centres in the free area.
* **Reduce motion (A-09):** `view.set_camera_smoothing(false)` (pan / zoom / rotation constants → instant), the view's own reduce rules for shake (×0.2 under `reduce_motion`, 0 under `reduce_flash`, `render.md` §5.12), and the edge-scroll speed slider stays available.
* **Edge scroll** (`edge_direction(p, view, margin = 6)` is pure and unit-tested): active iff `access/edge_scroll_enabled` ∧ `Window.has_focus()` ∧ state IDLE ∧ no modal ∧ pointer inside the window rectangle ∧ ≥ 0.5 s since the window regained focus. It is computed from the pointer *position*, not from the hovered control, so the extreme 6-px column works even over the sidebar; from the cursor position, never from warping the pointer (Wayland has no cursor warp, QA X-09). Toggle: action `toggle_edge_scroll` (A-20). Worked values on 1920x1080: `(2, 300)` → `(−1, 0)`; `(1919, 1079)` → `(1, 1)`; `(−40, 300)` (outside) → `(0, 0)`; `(960, 3)` → `(0, −1)`. While the band is active the pointer shows the matching scroll arrow (`UiCursors.set_scroll(dir)`, 5.7.3).
* **Confinement:** `Input.mouse_mode = MOUSE_MODE_CONFINED` iff in a match ∧ focused ∧ (`input/confine_cursor == 2` ∨ (`== 1` ∧ fullscreen)); back to `VISIBLE` on menu, focus loss or leaving the match.
* **Bookmarks:** `Ctrl+F9..F12` store `view.camera_state()`; `F9..F12` restore with `smooth = true`.
* **Jump to alert:** `Space` → `UiNotifier.cycle_alert()` → `view.focus_on_sim`; first press = newest alert, repeated presses within 3 s walk back through the last 5 alerts younger than 30 s.

#### 5.5.6 Gesture modifiers per OS (`UiKeymap.mods_of`)

| Role | Windows / Linux | macOS | Why |
|---|---|---|---|
| queue / add / toggle | Shift | Shift | universal |
| force-fire (attack anything, fire at ground/friendlies) | Ctrl | Option (`alt_pressed`) | Godot's macOS backend reports Ctrl+click as a right click *(unverifiable here — treated as a known risk, `R3`)* |
| control-group assign | Ctrl+n (**and** Cmd+n on macOS) | Ctrl+n, Cmd+n | keyboard-only; Mission Control's Ctrl+1..9 may be enabled by the user, so macOS gets a second default |
| everything else that would have used Alt+click (force-move, ping) | armed modes `M` and `J` | same | Alt+click/drag is grabbed by many Linux window managers, so the design has no Alt+mouse gesture at all |

All roles are rebindable in Options → Controls; `UiKeymap.mods_of` reads `event.shift_pressed`, `ctrl_pressed`, `alt_pressed`, `meta_pressed` and maps them through the table.

#### 5.5.7 Escape chain (`UiInputController` + `UiScreenGame`; first hit wins)

1. an open OptionButton popup or tooltip (the engine consumes it); 2. cancel placement / targeting / armed mode / ping mode; 3. close the chat input; 4. close the top modal dialog; 5. if `input/esc_clears_selection` and a selection exists: clear it; 6. toggle `UiDlgGameMenu`.

#### 5.5.8 Text-entry gating

While a `LineEdit` (chat, lobby name, seed entry, IP field) owns the focus: the input controller ignores keys and polled camera actions; `Enter` submits, `Esc` cancels; after submit the LineEdit calls `release_focus()` so gameplay keys work in the same frame. `UiKeymap.install(TEXT_ENTRY)` is not used: the gating is purely focus-based.

---

### 5.6 Keymap

#### 5.6.1 Default bindings (physical keys; contexts G = GAME, O = OBSERVER, M = MENU/LOBBY, * = all)

| Category | Action id | Default | macOS extra | Ctx | Notes |
|---|---|---|---|---|---|
| camera | `cam_pan_left/right/up/down` | Left / Right / Up / Down | | G O | repeat; the names match `render.md` §3.3 |
| camera | `cam_rotate_left` / `cam_rotate_right` | Q / E | | G O | exact-polled |
| camera | `cam_tilt_up` / `cam_tilt_down` | PageUp / PageDown | | G O | repeat |
| camera | `cam_zoom_in` / `cam_zoom_out` | `=` / `-` | | G O | wheel always works |
| camera | `cam_center_base` | Home | | G O | nearest own HQ |
| camera | `cam_center_selection` | `.` | | G | |
| camera | `cam_jump_alert` | Space | | G | |
| camera | `cam_reset` | Backspace | | G O | yaw/tilt/zoom to defaults |
| camera | `cam_bookmark_1..4` / `cam_bookmark_set_1..4` | F9..F12 / Ctrl+F9..F12 | | G O | |
| camera | `cam_orbit` (mouse) | MMB drag | | G O | hold or toggle (`input/orbit_mode`) |
| camera | `toggle_edge_scroll` | Ctrl+E | | G O | toggles `access/edge_scroll_enabled` for the session (A-20) |
| selection | `group_select_1..9,0` | 1..9, 0 | | G | double-tap centres |
| selection | `group_assign_n` | Ctrl+n | + Cmd+n | G | replace |
| selection | `group_add_n` | Ctrl+Shift+n | | G | add current selection to the group |
| selection | `group_append_n` | Shift+n | | G | add the group to the current selection |
| selection | `sel_all_military` / `sel_all_military_screen` | Ctrl+A / Ctrl+Shift+A | | G | whole map / visible playfield only (A-19) |
| selection | `sel_same_screen` / `sel_same_map` | T / Ctrl+T | | G | |
| selection | `sel_idle_next` / `sel_idle_prev` | N / Shift+N | | G | idle armed unit, centres camera |
| selection | `sel_collector_next` | C | | G | cycles collectors |
| selection | `sel_producer_next` | B | | G | cycles own production structures |
| selection | `sel_hq` | Ctrl+Home | | G | |
| selection | `sel_subgroup_next` | Ctrl+Tab | | G | |
| selection | `sel_group_next` | Ctrl+G | | G | selects the next non-empty control group (cycling, A-19) |
| orders | `cmd_attack_move` / `cmd_move` / `cmd_guard` / `cmd_patrol` | A / M / G / P | | G | armed modes (Shift chains further legs / waypoints) |
| orders | `cmd_stop` / `cmd_scatter` / `cmd_hold` | S / X / H | | G | immediate; `H` = the `HOLD` order (hold position: fires at targets in range, never moves) |
| orders | `cmd_follow` | Ctrl+F | Cmd+F | G | armed: click an own or allied unit → `FOLLOW` (5.7.2); the sim's suggested "follow modifier" right-click is not offered because the design has no Alt+mouse gesture (5.5.6) |
| orders | `cmd_deploy` | D | | G | `deploy` for units without `F_DEPLOYED` (an MCV too: the sim routes it to `T_DEPLOY_MCV`), `undeploy(slot)` for those with it; a mixed selection sends both |
| orders | `cmd_stance_cycle` | Z | | G | 0 → 1 → 2 → 3 → 0 (aggressive, defensive, hold fire, guard) |
| orders | `cmd_force_fire_mode` | Y | | G | armed |
| orders | `cmd_return` | V | | G | aircraft / drones → `return_to_base`; collectors → `return_cargo` (nearest refinery) |
| orders | `cmd_unload` | U | | G | transports |
| orders | `cmd_ability_1..4` | I / O / K / L | | G | dynamic ability bar slots |
| orders | `cmd_scuttle` | Ctrl+Delete | | G | `SCUTTLE`, always behind a confirm dialog ("Scuttle N units? They leave no wreck.") |
| orders | `cmd_ping` | J | | G O | armed: next click (world or minimap) pings the team |
| tools | `tool_repair` / `tool_sell` / `tool_rally` / `tool_waypoint` | R / Delete / F / W | | G | armed modes; W latches queueing |
| tools | `place_rotate` | Ctrl+R | | G | turns the placement ghost 90° clockwise while placing a rotatable structure (also `Shift`+wheel) |
| sidebar | `tab_next` / `tab_prev` | Tab / Shift+Tab | | G | |
| sidebar | `card_1..12` | Alt+Q W E R A S D F Z X C V | Option+… | G | grid order left→right, top→bottom |
| sidebar | `card_5x_1..12` | Alt+Shift+(same) | | G | queue ×5 |
| powers | `power_1..3` / `superweapon` | F5 / F6 / F7 / F8 | | G | |
| interface | `toggle_menu` | Esc | | * | 5.5.7 |
| interface | `pause_game` | Pause, Ctrl+P | | G | two bindings (many laptop keyboards have no Pause key); LOCAL: pause; MP: `request_pause` |
| interface | `chat_all` / `chat_team` | Enter / Shift+Enter | | G O | |
| interface | `open_field_manual` / `toggle_scoreboard` / `toggle_net_overlay` / `hide_ui` | F1 / F2 / F3 / F4 | | G O | |
| interface | `screenshot` | Print | | * | `user://screenshots/meridian_<unix>.png`, toast |
| interface | `toggle_fullscreen` | Alt+Enter | | * | |
| observer | `obs_player_1..8` / `obs_all` | 1..8 / 0 | | O | perspective |
| observer | `obs_next_player` / `obs_toggle_fog` | Tab / F | | O | |
| observer | `obs_pause` / `obs_speed_up` / `obs_speed_down` | Space / `]` / `[` | | O | replay only |

`UiKeymap` unit test: no two default bindings with the same packed key share a context bit (the table above is conflict-free by construction: e.g. `Space` is `cam_jump_alert` in G and `obs_pause` in O; `Tab` is `tab_next` in G and `obs_next_player` in O).

#### 5.6.2 Rebinding rules

* Capture (`UiKeybindButton`): first non-modifier `InputEventKey` press (not echo) wins; modifiers held at that moment are recorded; `Esc` cancels; a dedicated X clears (so `Delete` and `Backspace` stay bindable). Mouse buttons are accepted only by actions flagged `allow_mouse` (`cam_orbit`).
* **Refused combos:** modifier-only, `Esc` for anything except `toggle_menu`, OS-reserved (`Alt+F4`, `Cmd+Q`, `Cmd+H`, `Cmd+M`, `Cmd+Tab`, `Alt+Tab`, `Ctrl+Alt+Delete`) → inline message.
* **Conflict** (same packed key, overlapping context bits): dialog *"Q is already used by Rotate left"* with **Swap** (exchange the two bindings), **Replace** (unbind the other) or **Cancel**. Default bindings can always be restored per action (↺) or all at once.
* Each action holds ≤ 2 bindings; the second is optional.

#### 5.6.3 InputMap installation per context

`install(ctx)` builds every action bound in `GLOBAL | ctx` with `InputMap.add_action(name, 0.2)` and one `InputEventKey` per binding (`physical_keycode`, modifier flags), erasing stale ones first. Entering GAME/OBSERVER additionally erases the events of `ui_focus_next` and `ui_focus_prev` (frees Tab; spike case R) — `uninstall` re-adds `Tab` / `Shift+Tab`, so menu keyboard navigation and the lobby's LineEdits keep working. `ui_accept`, `ui_cancel` and the arrow `ui_*` actions are never touched.

#### 5.6.4 Labels

`UiKeymap.label(action)` = platform label of the first binding (`OS.get_keycode_string`, measured `"Option+Q"` on macOS, `"Alt+Q"` elsewhere) with the layout-aware letter (`DisplayServer.keyboard_get_keycode_from_physical`). Tooltips render `Name  [Alt+Q]`; build cards show only the grid letter in the hotkey badge when the tab has focus (`Q`), the full chord in the tooltip.

---

### 5.7 Contextual command resolution

#### 5.7.1 Inputs and outputs

`UiContextResolver.resolve(sel, tgt, mods, armed) -> UiOrderIntent` is a **pure function** (no engine calls) so it can be table-tested. It runs (a) at 30 Hz for cursor choice while the pointer is over the world, and (b) once on RMB press / armed click to produce the order. `make_target()` (the only impure part) fills `UiTarget` from `UiPickData` + `UiSimPort` (ownership relation via `rel(viewer, owner)`, capture/garrison/transport flags via `read()`).

#### 5.7.2 Algorithm (partition by rule)

```
resolve(sel, tgt, mods, armed):
  if sel.mode == NONE or sel.mode == FOREIGN:               return NONE            # cursor: SELECT/INSPECT/DEFAULT by tgt.kind
  if armed != NONE:                                         return resolve_armed(...)   # below
  if tgt.kind == NONE:                                      return DENIED("order.deny.off_map")
  unassigned = sel.ids (ascending)
  intents = []
  for rule in RULES (priority order, table below):
      if not rule.target_pred(tgt, mods): continue
      subset = [u for u in unassigned if rule.unit_pred(caps[u]) and rule.extra(u, tgt)]
      if subset is empty: continue
      intents.append(make_intent(rule, subset, tgt, mods));  unassigned -= subset
  if intents is empty:  return DENIED(reason_for(tgt, sel))                            # e.g. "order.deny.cannot_hit", "order.deny.no_weapon"
  primary = intents[0];  primary.extra = intents[1:]                                    # MOVE intents of rules 14-16 are ordinary intents in this list
  for it in intents: it.queued = mods.queue or waypoint_latch; it.force = mods.force   # every intent of the click shares the modifiers
  return primary
```
Every unit ends in **at most one** intent (first matching rule wins), so a mixed selection produces one command per rule with a non-empty subset; the bus submits them in rule order. The intent list order is deterministic.

**Rule table (priority order).** `caps` are `UiUnitCaps` bits (4.3). "hits(L)" = `CAP_HIT_GROUND/AIR/WATER/SUB` for target layer L (structures count as ground).

| # | Rule | Target predicate | Unit predicate | Intent (target) | Cursor |
|---|---|---|---|---|---|
| 1 | FORCE | `mods.force` ∧ kind ∈ {GROUND, WRECK, DEPOSIT, OWN, ALLY, NEUTRAL} (an ENEMY falls through to rule 11) | `CAP_ARMED` ∧ (`CAP_HIT_GROUND` for ground points, hits(`tgt.layer`) for entities) | ground / wreck / deposit: FORCE_FIRE(x, y); own / allied / neutral entity: ATTACK(eid) with the forced flag (FLAGS bit0) | FORCE_FIRE |
| 2 | CAPTURE | `tgt.capturable` | `CAP_CAPTURE` | CAPTURE(eid) | INTERACT |
| 3 | GARRISON | `tgt.garrisonable` ∧ kind ∈ {NEUTRAL, OWN, ALLY} | `CAP_GARRISON` ∧ ¬`CAP_SERVICE` | GARRISON(eid) | INTERACT |
| 4 | LOAD | kind ∈ {OWN, ALLY} ∧ `transport_free > 0` (or `transport_vehicle_free > 0` for vehicles) ∧ `tgt.eid ∉ selection` | `CAP_PASSENGER` ∧ ¬`CAP_TRANSPORT` | LOAD(eid) | INTERACT |
| 5 | REPAIR_UNIT | kind ∈ {OWN, ALLY} ∧ unit ∧ `damaged` ∧ land vehicle | `CAP_REPAIR_VEHICLE` | REPAIR(eid) | REPAIR |
| 6 | REPAIR_STRUCT | kind ∈ {OWN, ALLY} ∧ structure ∧ `damaged` | `CAP_REPAIR_STRUCT` | REPAIR(eid) | REPAIR |
| 7 | SALVAGE | `tgt.salvageable` | `CAP_SALVAGE` | SALVAGE(wreck) | INTERACT |
| 8 | HARVEST_DEPOSIT | kind == DEPOSIT (a ground pick on an explored cell with `deposit_at(cx, cy) > 0`, no entity picked) | `CAP_COLLECTOR` | HARVEST(0, x = cell centre, y = cell centre): the sim harvests the deposit cell nearest to (x, y) | INTERACT |
| 9 | RETURN_CASH | kind == OWN ∧ `is_refinery` | `CAP_COLLECTOR` | RETURN_CASH(refinery): deliver the load, the sim then resumes harvesting | INTERACT |
| 10 | RETURN_BASE | kind == OWN ∧ (`is_airfield` ∨ `is_carrier`) | `CAP_AIR` ∨ `CAP_CARRIER_DRONE` | RETURN_TO_BASE(target = the clicked airfield or carrier; `V` sends target 0 = nearest free pad) | INTERACT |
| 11 | ATTACK | kind == ENEMY | `CAP_ARMED` ∧ hits(`tgt.layer`) | currently visible: ATTACK(eid); remembered ghost (¬`visible`): ATTACK_MOVE(target position) for `CAP_MOBILE` units only, because the sim accepts ATTACK only on currently visible targets (`sim_core.md` §5.5) | ATTACK |
| 12 | CANNOT_HIT | kind == ENEMY | `CAP_ARMED` ∧ ¬hits(`tgt.layer`) | (consumes the unit; no order) | — |
| 13 | RALLY | any (ground point or own entity) | `CAP_STRUCTURE` ∧ `CAP_PRODUCER` | SET_RALLY(x, y, target) with mode 0 (set) | RALLY |
| 14 | MOVE_GROUND | kind == GROUND | `CAP_MOBILE` | MOVE(x, y) | MOVE |
| 15 | MOVE_TO_ENTITY | kind ∈ {OWN, ALLY, NEUTRAL, WRECK} or DEPOSIT (not consumed by 2-10), `tgt.eid` not in selection | `CAP_MOBILE` | MOVE(target position) — a walk to the spot, not a `FOLLOW` (that is the armed mode below) | MOVE |
| 16 | ENEMY_UNARMED_MOVE | kind == ENEMY | `CAP_MOBILE` ∧ ¬`CAP_ARMED` ∧ ¬(`CAP_COLLECTOR` ∨ `CAP_MCV` ∨ `CAP_CAPTURE` ∨ `CAP_TRANSPORT`) | MOVE(target position) | MOVE |

Notes: (a) rule 12 exists so armed anti-air units in a mixed group are silently excluded from a ground attack instead of being dragged to the target by rule 16; (b) collectors, MCVs, engineers and transports never follow an attack target (the "soft exclusion" that prevents an accidental `Ctrl+A` group order from marching harvesters into a fight); (c) if the *whole* selection is consumed by rule 12 or nothing matches, the result is `DENIED` with reason `order.deny.cannot_hit` / `order.deny.no_weapon` / `order.deny.no_valid_order`; PATROL, DEPLOY, stance, RETURN_CASH via `V`, UNLOAD, SCUTTLE and abilities are never produced by the RMB table (they are keys and buttons, 5.11); (d) `MOVE_GROUND` on a cell impassable for **every** selected move class (`UiTarget.passable_mask & selection_move_mask == 0`) yields `DENIED("order.deny.blocked")`; a mixed selection where at least one class can stand there orders MOVE and the sim paths the others to the nearest reachable cell; (e) shroud cells are legal move targets (units path into the unknown).

**Armed modes (`resolve_armed`):**

| Armed | LMB target | Result |
|---|---|---|
| ATTACK_MOVE | ENEMY | rule 11 (ATTACK) for armed units that can hit; everything else in rule 14/15 as MOVE |
| ATTACK_MOVE | otherwise | ATTACK_MOVE(x, y) for `CAP_ARMED ∧ CAP_MOBILE`; unarmed mobile units get MOVE; non-mobile excluded |
| MOVE | any | MOVE(target position) for `CAP_MOBILE`, even onto an enemy (walk past / into) |
| PATROL (`P`) | GROUND, or any entity (its position) | PATROL(x, y) for `CAP_MOBILE`; Shift appends further legs (`QM_APPEND`), the sim cycles them |
| FOLLOW (`Ctrl+F`, utility-row button) | OWN or ALLY **unit** not in the selection | FOLLOW(target = eid) for `CAP_MOBILE` units (escort distance is the movement domain's); Shift appends (`QM_APPEND`); any other target → DENIED(`order.deny.follow_target`). Cursor MOVE; marker: white bracket on the target |
| GUARD | OWN/ALLY entity | GUARD(target = eid) for armed mobile units (aircraft: per combat) |
| GUARD | GROUND | GUARD(target = 0, x, y) — guard that point |
| GUARD | ENEMY | DENIED(`order.deny.guard_enemy`) |
| FORCE_FIRE (`Y`) | any | rule 1 |
| SELL | OWN structure with `CAP_SELLABLE` | SELL(eid) — immediate, no confirm (the refund appears as floating text through `CASH` reason SELL) |
| REPAIR | OWN structure | `SET_STRUCT_REPAIR` with an explicit mode: 1 if the structure is not repairing (`F_REPAIRING` clear), else 0 |
| RALLY | GROUND or OWN entity | SET_RALLY (mode 0) for selected producers, else for the producers of the active tab's queue kind |
| WAYPOINT (latch) | — | not a click mode: every resolved intent gets `queued = true` until toggled off (`W`, `Esc`) |
| PING | GROUND / minimap | `net.send_map_ping(cx, cy)` (team) + local ping marker |
| POWER / SUPERWEAPON | — | `UiTargeting` (5.10.6) |
| PLACE | — | `UiPlacement` (5.10.5) |

Armed modes exit after one issued order unless Shift is held or `input/sticky_modes`; RMB / Esc cancels. Sell/repair/rally armed by the sidebar tool row behave identically to their keys.

#### 5.7.3 Cursor states and the shape-slot map

Engine facts (E3): switching between pre-registered shape slots costs **1 µs**; replacing a slot's image costs 0.4-1.3 ms. So all 17 base images are registered once at boot on their own `Input.CursorShape` slot and states switch via `Input.set_default_cursor_shape`. Two rarely used variants (power reticle, superweapon reticle) are swapped into the `CROSS` slot at targeting entry/exit. The eight **edge-scroll** arrows of `art_direction.md` §5.12.6 have no slot of their own: they are baked with the others (8 × 2.6 ms ≈ 21 ms once, kept as `Image`s) and, while the pointer rests in the scroll band, `UiCursors.set_scroll(dir)` swaps the matching one into the `ARROW` slot (0.36-0.56 ms, only when the direction changes); leaving the band restores the default arrow. Images follow the art rules: 32 px vector, 2 px white stroke with a 1 px dark outline, hover tint = the relation token (`ENEMY` red on ATTACK / FORCE_FIRE, `SELF` green on MOVE, `NEUTRAL` yellow on INTERACT, grey with a slash on DENIED); the art set's `capture` cursor is the INTERACT image.

| `UiCursors.State` | Slot | Image | Chosen when |
|---|---|---|---|
| DEFAULT | ARROW | arrow, accent edge | world with nothing special; placement valid |
| TEXT | IBEAM | I-beam | text fields (engine, per Control) |
| HAND | POINTING_HAND | hand | clickable HUD controls (engine, per Control) |
| ATTACK | CROSS | `ENEMY` red crosshair | intent ATTACK |
| BUSY | WAIT | spinner ring | loading/waiting |
| INTERACT | BUSY | chevron-into-box (`NEUTRAL` yellow) | CAPTURE, GARRISON, LOAD, SALVAGE, HARVEST, RETURN |
| DENIED | FORBIDDEN | ⊘ in `TEXT_DISABLED` grey | intent DENIED; placement invalid; power target invalid |
| SELECT | CAN_DROP | white corner brackets | hover own unit/structure with no order pending |
| ATTACK_MOVE | DRAG | orange crosshair + arrows | armed ATTACK_MOVE over ground |
| MOVE | MOVE | `SELF` green chevron ring | intent MOVE |
| FORCE_FIRE | VSIZE | red ground reticle | intent FORCE_FIRE |
| GUARD | HSIZE | shield | armed GUARD |
| DEPLOY | BDIAGSIZE | inward brackets | hover a deployable selected unit while `D` is armed (rare) |
| SELL | FDIAGSIZE | `$` (green valid / red invalid) | armed SELL |
| REPAIR | VSPLIT | wrench | armed REPAIR / intent REPAIR |
| RALLY | HSPLIT | flag | armed RALLY / rally intent |
| INSPECT | HELP | magnifier | hover enemy/neutral with no selection or foreign selection |
| POWER / SUPERWEAPON | CROSS (variant) | blue / red reticle | targeting a power / superweapon |
| PLACE_OK / PLACE_BAD | ARROW / FORBIDDEN | (same images as DEFAULT / DENIED; the ghost is the feedback) | placement |

Sizes: `access/cursor_scale` 100 / 150 / 200 → 32 / 48 / 64 px source images (baked at 1x; the same size on 1x and 2x displays — whether macOS treats them as points or pixels is **unverified** (`R4`), which is why the size is a setting). Hotspots are stored in `cursors.json` (7.7). Headless or `ui/cursor_style == 1`: no registration, system cursors.

#### 5.7.4 Worked examples

| # | Selection | Target | Result |
|---|---|---|---|
| E1 | 3 Guardian Tanks (armed, hit ground) + 1 Collector | visible enemy Rifle Squad | rule 11 → `ATTACK` for the 3 tanks; Collector excluded by 16 → 1 command; cursor ATTACK |
| E2 | Engineer + 2 Rifle Squads | neutral substation (`capturable`) | rule 2 `CAPTURE`(Engineer) + rule 15 `MOVE`(squads to the structure) → 2 commands; cursor INTERACT |
| E3 | Sentinel AA (hits AIR only) | enemy tank | rule 12 consumes it → `DENIED("order.deny.cannot_hit")`; cursor DENIED |
| E4 | Collector | the gold cells of a deposit field (explored, `deposit_at(48, 17) > 0`) | rule 8 `HARVEST(0, 49664, 17920)`; a salvage wreck is rule 7 `SALVAGE` |
| E5 | own Barracks (structure selection) | ground | rule 13 `SET_RALLY(x, y)`; the overlay draws a flag and a line |
| E6 | 5 tanks, `W` latch on | visible enemy structure | rule 11 `ATTACK` with `queued = true` → `mode = QM_APPEND` |
| E7 | Beaver APC (transport) + Rifle Squad | own transport with 2 free slots | squad: rule 4 `LOAD`; the APC itself: rule 15 `MOVE` to the target unless it is the target |
| E8 | 5 tanks + 1 Sentinel AA (hits AIR only) | remembered (ghost) enemy Radar, out of sight | rule 11 → one `ATTACK_MOVE` to the ghost's position for the 5 tanks (mobile, hit ground); the AA unit is consumed by rule 12; cursor ATTACK |
| E9 | 3 aircraft | own Airfield 640 | rule 10 `RETURN_TO_BASE(target 640)`; cursor INTERACT |
| E10 | 2 Rifle Squads | armed FOLLOW, own Collector 1203 | `FOLLOW(target 1203)` for both squads; an enemy tank → DENIED(`order.deny.follow_target`) |

---

### 5.8 Building commands: ids, coordinates, budget, validation, feedback

#### 5.8.1 Construction rules (ops and fields are in 6.1)

* Every command is an int array built by `UiCmdCodec` through the `SimCmd` builder of its op; the UI writes no op number outside `ui_cmd_codec.gd`, and the payload has no pid (net stamps it from the connection).
* Ids are **ascending and unique** (the builder sorts, so identical user actions give identical arrays) and belong to the viewer (checked against `UiSelection` after `prune`). The sim caps an id list at 512 (`BAD_FIELD` above it) and `MAX_SELECT` is 500, so one user action is **one** command per intent; `split_ids` exists only as a guard. Formation grouping, if the movement domain has one, is per command.
* **Queue mode.** Shift (or the `W` latch) sets `mode = QM_APPEND` on every op the catalog flags Q (MOVE, PATROL, LOAD, GARRISON, CAPTURE, REPAIR, SALVAGE, HARVEST, RETURN_CARGO, FOLLOW, ATTACK, ATTACK_MOVE, GUARD, RETURN_TO_BASE); the other ops (FORCE_FIRE, deploy, abilities, unload, production) have no queue mode and ignore Shift. Otherwise `QM_REPLACE`. `QM_FRONT` is never produced.
* One user action → ≤ 1 command per intent: `Shift`+card click is **one** `TRAIN` with `count = 5`, never five commands.
* **Movement flags (v2.1).** `MOVE`, `ATTACK_MOVE` and `PATROL` carry `flags`: b1 speed-match (the group moves at its slowest member) when `input/move_speed_match` is on, b2 reverse-allowed (short moves) when `input/move_reverse` is on; both default off (the movement domain's own defaults apply), b0 no-formation is never set by the UI. Golden rows in 6.1.
* **Forced attacks.** `ATTACK` carries FLAGS bit0 when the target is not an enemy (force modifier or `Y` mode on an own, allied or neutral entity); without it the sim rejects a friendly target.

#### 5.8.2 The single float → int step (world → sim units)

`UiViewPort.world_to_sim(p)` / `UiCmdCodec.world_to_sim`:

```
sim_x = clampi(roundi(world_x * 1024.0 / 3.0), 0, map_w_cells * 1024 - 1)        # ARCH §3: world = sim * 3 / 1024
sim_y = clampi(roundi(world_z * 1024.0 / 3.0), 0, map_h_cells * 1024 - 1)
cell  = sim >> 10                                                                  # Fp.cell_of
```
Worked: terrain hit `(45.0, 90.0)` m → `(15360, 30720)` (cell 15, 30, exactly on the corner); `(45.7, 90.1)` → `(15599, 30754)` (15598.93 and 30754.13 rounded); on a 128-cell map the largest legal value is 131,071 (the sim rejects `x ≥ map.w × 1024` with `BAD_FIELD`). Minimap: `norm_to_sim(n) = (roundi(n.x × map_w × 1024), roundi(n.y × map_h × 1024))`, clamped; a click at local (150, 150) in a 300-px widget (pad 5, map rect 290) → `n = (150−5)/290 = 0.5` → `x = 65,536` on a 128-cell map. The *sender's* integers are authoritative (net relays them), so two machines never have to agree on the float.

**Placement is expressed in cells, not points.** `BUILD_PLACE` takes **whole cells** (`sim_core.md` §6.1, flag C: `0 ≤ x < map.w`, `0 ≤ y < map.h`) and a rotation: anchor `(ax, ay)` = (30, 41) rotated once is sent as `x = 30`, `y = 41`, `mode = 1` (golden in 6.1). The ghost, the validity check and the command all use the same top-left anchor (5.10.5).

#### 5.8.3 Per-turn budget and coalescing

Net accepts ≤ 64 commands per player per 2-tick turn and queues ≤ 256 locally (`net.md` §4.1); the sim decodes every command on its own (≤ 1024 ints, ≤ 512 ids, `sim_core.md` §4.8). `UiCommandBus` keeps a counter reset when `net.tick() / 2` changes: ≤ 40 commands per turn (the bus is the only producer); excess → `refused(kind, REFUSE_RATE)` + `UiAudioPort.ERROR` (at most once per second). Two consecutive commands with identical int arrays inside the same turn are dropped as duplicates (key repeat, double clicks). `UiNetPort.submit == false` → `REFUSE_NOT_ALLOWED`.

#### 5.8.4 What the UI validates before sending (everything else is the sim's authority)

| Command | UI pre-check (via `UiSimPort`) | On failure |
|---|---|---|
| `build_start` | `check_build(def) == OK` | `refused(rule)`; card shakes; text from `reject.<rule>`; `UiAudioPort.ERROR` (audio voices the sim's own rejections, not these) |
| `train` | `check_train(producer, def) == OK` ∧ `unit_count + queued + count ≤ unit_cap` | idem; `UNIT_CAP` shows the unit-cap toast |
| `research` | `check_research == OK` | idem |
| `use_power` / `launch_superweapon` | `power_status == READY` (or `sw_status == READY`) ∧ `power_target_ok` | DENIED cursor + toast ("Needs vision" / "Unexplored") |
| `build_place` | `check_place == OK` (also polled while hovering) | ghost stays red; `UiAudioPort.PLACE_FAIL` on a refused click |
| Unit orders | ids alive and viewer-owned (`prune`); target visible or own / allied (a remembered ghost becomes ATTACK_MOVE, 5.7.2) | `DENIED("order.deny.not_visible")` |
| `sell`, `set_struct_repair` | `CAP_SELLABLE` / repairable | DENIED |
| `scuttle` | confirm dialog accepted | nothing sent |

Credits are **not** pre-checked for `build_start` / `train` beyond what `check_*` returns: payment is progressive (ARCH §12), so a click with 400 credits on a 2,000-credit Factory is legal; the card shows the cost in red when `credits < cost`.

#### 5.8.5 Optimistic feedback

The sim executes a command ≥ 1-2 turns later (input delay `D`: 200-300 ms on a LAN, 100-200 ms locally; `net.md` §5.5.1). So every click reacts at once: order marker, unit response, minimap ping and bracket flash (5.8.7), and cards increment `UiBuildItem.pending` (cleared when the next `refresh` shows the queue grew, or after 1.5 s). The UI never fakes credits, health or progress.

#### 5.8.6 Rejections

`CMD_REJECTED` (code 5: `pid, op, err, detail, target-or-def`; emitted for real players only and throttled by the sim to one per 10 ticks per player) → notice rule `cmd_rejected`: text `reject.<err>` (`SimCommand.Err` values, which `UiSimPort.Rule` mirrors; placement refinements from `detail`, e.g. the `RSN_*` reason of a `BAD_SITE`), at most one per second. **Audio voices the rejection itself** (`snd.ui.error` + `unable_to_comply`; `BAD_SITE` → `place_fail` + `cannot_deploy`; funds and unit-cap lines from their own events), so the UI plays nothing for a sim rejection. `EVT_QUEUE_STATE` (306) drives the card's blocked chip and needs no rejection text. The catalog carries no client tag, so the UI never correlates a rejection with a click; the toast names the rejected `op` ("Cannot place a structure there").

#### 5.8.7 Immediate feedback (`UiFeedback.order_issued`)

| Intent | Marker (world overlay, 2D, 0.6 s) | Minimap | Unit response (`UiAudioPort.unit_ordered`, 6.3.3) |
|---|---|---|---|
| MOVE / PATROL | three green chevrons converging on the point (patrol: blue) | ORDER ping only if the point is off-screen | MOVE |
| ATTACK / FORCE_FIRE | red bracket flash on the target (0.5 s) | — | ATTACK |
| ATTACK_MOVE | orange chevrons | ORDER ping if off-screen | ATTACK |
| GUARD | blue shield glyph | — | GUARD |
| RALLY | persistent flag while the producer stays selected | — | cue `RALLY_SET` |
| CAPTURE / LOAD / GARRISON / SALVAGE / HARVEST / REPAIR / RETURN_CASH / RETURN_BASE / FOLLOW | white bracket on the target (HARVEST: on the deposit cell) | — | CAPTURE / LOAD / LOAD / CAPTURE / HARVEST / REPAIR / HARVEST / MOVE / MOVE |
| DENIED | red ⊘ at the cursor, cursor shake 0.2 s | — | `order_denied` + cue `ERROR` |

Selected units also flash their brackets for 0.15 s (the view's ring pulse through `set_selection`). Unit responses use the primary unit's per-kind def index; audio applies its own gaps (250 ms global, 700 ms per class and type), so the UI adds no throttle.

---

### 5.9 Fog of war and targeting

* **Pickability = renderability.** `ViewPicker` returns only entities the view draws: own, allied (shared vision on or off — allies are always known), currently visible enemies / neutrals, and — with `PICK_GHOSTS` — remembered **structure ghosts**. An entity hidden by fog, shroud, camouflage or a container is never returned, so ray pick, box select and the context resolver cannot see it. Cloaked enemies revealed by a detector appear normally (the sim's `entity_visible` says so).
* **Ghosts** (remembered enemy structures) may be inspected and approached: the kernel's `ATTACK` requires a currently visible target (`sim_core.md` §5.5), so a click on a ghost issues `ATTACK_MOVE` to its position (rule 11, question Q12; `combat.md` §5.10.1 would accept known targets); their minimap dot is dimmed (α 0.5).
* **Ground** under fog: legal move/attack-move/rally target; `UiTarget.visible = false` only changes hover text. A **deposit** cell is a harvest target when it is explored and `deposit_at(cx, cy) > 0`; `deposit_at` returns the live amount only for visible cells and the static maximum otherwise, so depletion in the dark is never revealed.
* **Support powers** (`DefPower.target_vision`): `ANY` (reconnaissance) any cell incl. shroud; `CURRENT` needs `visibility == VISIBLE` at the cursor cell; superweapons `EXPLORED` need `visibility ≥ FOG`. The check is `UiSimPort.power_target_ok` (real vision); invalid → red preview, DENIED cursor, hint "Needs vision" / "Unexplored".
* **Minimap** shows own + allied dots always and enemy dots only if visible (`snapshot()` is fog-honouring); enemy structure ghosts dimmed.
* **Alerts** come from victim-owned events, never from enemy positions the viewer cannot see. **Strategic warnings** (superweapon impact zones) are visible to the *affected* players and are never hidden by fog or decoys (bible `rule.combat.targeting_and_warnings`); the UI draws exactly what `strategic_warnings()` lists for the viewer.
* **Observer** (`viewer_pid == −1`): omniscient — `visibility()` returns VISIBLE, `snapshot()` lists everything; a chosen player perspective restores that player's fog.
* **Shared vision** (`RF_SHARED_VISION`): the sim's per-team fog is used unchanged; the UI has no extra rule.

---

### 5.10 Sidebar, build cards, production and power UI

#### 5.10.1 Update cadences (`UiHudPresenter`; `T` = one 50-ms tick batch)

| Data | Source | Cadence |
|---|---|---|
| credits, power supply/demand, unit cap | `UiSimPort` | read every tick batch; `UiCreditTicker` animates per frame |
| construction / queue progress and ETA of cards on the visible tab + tab badges | `construction_state`, `queue_info` | every tick batch (20 Hz) — only widgets that changed call `queue_redraw` |
| availability of all cards (`check_build/train/research`, `power_status`) | `UiSimPort` | every 10 ticks (2 Hz) and immediately on the relevant events |
| power dock, superweapon charge | `UiSimPort` | every tick batch |
| minimap dots | `snapshot()` | every 2 ticks (10 Hz); redraw 30 Hz for pings/sweep |
| selection panel (HP, status) | `read(eid)` for the visible tiles + primary (≤ 40 reads) | every 2 ticks; portrait/tiles rebuilt only on selection change |
| notifications | events | every event batch |
| order markers, edge arrows, targeting preview | `UiViewPort.sim_to_world` + camera projection | every frame |
| hover / cursor | resolver | 30 Hz while the pointer moves |
| stats series | `player_stats` | every 200 ticks (10 s) |

#### 5.10.2 Tab content and order

| Tab | Content (from the local `DefRoster`) | Order |
|---|---|---|
| STRUCTURES | `producible_structures` without defense tags, incl. Relay (NEC) and the superweapon launcher | `(build_tier, cost, index)` as the roster provides |
| DEFENSE | structures with `defense` / `advanced_defense` tags | same |
| INFANTRY | `units_produced_by(barracks)` incl. Engineer | `(tier, cost, index)` |
| VEHICLES | factory units incl. Collector, MCV | same |
| AIRCRAFT | airfield units | same |
| NAVAL | dock units incl. Landing Transport | same |
| RESEARCH | `research_list` (2 vanilla, 3 subfaction) | list order |
| POWERS | superweapon card first, then the 3 powers | list order |

Cards of tiers/prerequisites not yet met are **shown locked** ("Needs Radar"), not hidden, so the tree teaches itself (bible `rule.design.technology`). A replaced unit is absent (bible: *a replaced unit cannot also be built*). Grid = 3 columns, min 12 slots (ghost slots), scrolls vertically; slot `i` gets the `card_{i+1}` hotkey label.

#### 5.10.3 Producer routing (units)

```
UiProducerPicker.pick(port, queue_kind, unit_def, selected) -> producer eid | -1
  cands = [p for p in port.producers(queue_kind) if port.check_train(p, unit_def) in {OK, UNIT_CAP}]      # ascending ids
  if cands.is_empty(): return -1
  chosen = [p for p in selected if p in cands]
  if not chosen.is_empty(): return chosen[0]                                       # the user selected a producer: it wins
  for p in cands: if port.read(p).is_primary: return p                             # the sim's primary building of its kind (SET_PRIMARY: the queue-strip star)
  return argmin over cands of (queue_len(p), tail_eta_ticks(p), p)                  # shortest queue, then soonest free, then lowest id
```
Deterministic on the sender; the *sim* receives an explicit producer id. `TRAIN` also accepts 0 = auto (primary first, else fewest queued, ties lowest id, `economy.md` §3.3 `q_find_producer`), but the UI always names the producer so that the card, the queue strip and the pre-check agree. The first producer of a kind becomes primary by itself (economy §5.4); the star on the queue strip moves the flag with `set_primary`. Structure construction has one player-wide queue and needs no routing.

#### 5.10.4 Card state derivation and interaction

| Item | Derivation (first match) |
|---|---|
| Structure | head of the construction queue & `Construction.BUILDING` → BUILDING (chips from `queue_state`: WAIT_FUNDS "$", LOW_POWER bolt); head & `PAUSED` → ON_HOLD when `queue_state == HELD`, BLOCKED when `PREREQ_LOST` or `SHUTDOWN`; `READY_TO_PLACE` & `ready_def == def` → READY (PLACING while `UiPlacement.active`); behind the head → QUEUED (badge = position); `check_build` = NO_PREREQ / NOT_AVAILABLE → LOCKED (`requires_text`; NOT_AVAILABLE for the single strategic structure = "Already built"); else AVAILABLE |
| Unit | no producer of its type exists → LOCKED("Needs Barracks"); `check_train` = NO_PREREQ → LOCKED; slot 0 of the chosen producer's queue is this def → BUILDING (ON_HOLD if `queue_state == HELD`, BLOCKED if `PREREQ_LOST`, `UNIT_CAP`, `EXIT_BLOCKED` or `SHUTDOWN`, with the reason as the tooltip's warning line); appears deeper in the queue → QUEUED; else AVAILABLE (red cost if `credits < cost`) |
| Research | `research_done` → DONE (dimmed, check glyph); active → BUILDING (ON_HOLD / BLOCKED from `queue_state` as above); in queue → QUEUED; `check_research` NO_PREREQ → LOCKED; else AVAILABLE |
| Power | `PowerStatus`: READY → AVAILABLE (pulse), COOLDOWN → COOLDOWN (sweep + countdown from `power_ready_tick − tick`), LOCKED_PREREQ → LOCKED, UNPOWERED → BLOCKED ("Radar offline: low power"), NO_CREDITS → UNAFFORDABLE |
| Superweapon | `SwStatus.NONE` → LOCKED("Build <launcher>"); CHARGING → COOLDOWN (sweep = charge permille; frozen + BLOCKED("No power") while `power_demand > power_supply`, bible: recharge pauses); READY → AVAILABLE (pulse); WARNING (own strike in flight) → ON_HOLD with label "LAUNCHING" |

**Card anatomy** (`art_direction.md` §5.12.6): the baked icon (128 x 96, drawn 2x for UI scale up to 2) over the plate gradient `#121A23 → #0B1016`; the **tier badge** top-right (T2 one chevron, T3 two chevrons, from `DefUnit.tier`; T1 none); the **role glyph** bottom-left (`UiGlyphs.role_glyph(def)`: by capability first — COLLECTOR, MCV, ENGINEER (capture), TRANSPORT, DRONE / CARRIER —, then by layer — SUBMARINE, NAVAL, AIRCRAFT —, then by the archetype's `role` column, and the class glyph INFANTRY / VEHICLES when nothing else applies; the archetype column is requested from art in `[XR-49]`); the hotkey badge and cost line (14 px NUM). Icons carry the faction accent as team colour (art), never the player colour.

**Hold is a queue attribute, not an item attribute** (`QUEUE_HOLD`, `BUILD_HOLD`, `RESEARCH_HOLD`, `sim_core.md` §6.1): there are exactly three holdable queues — one producer's unit queue, the player-wide construction queue and the research queue. Holding the Factory freezes everything in it; the card in progress shows ON_HOLD (steady amber sweep), queued cards keep their count badge.

| Input on a card | Effect |
|---|---|
| LMB, AVAILABLE unit | `train(pick(...), def, 1)`; **Shift+LMB** → count 5 (one `TRAIN`); cue `QUEUE_ADD` |
| LMB, BUILDING / QUEUED unit | +1 in the same producer |
| LMB, AVAILABLE structure | `build_start(def)` |
| LMB, READY structure | begin placement (5.10.5) |
| LMB, ON_HOLD | resume the queue (`queue_hold(kind, ids, false)`); cue `QUEUE_HOLD` |
| LMB, AVAILABLE(READY) power / superweapon | begin targeting (5.10.6), or fire immediately when `target_mode == NONE` |
| RMB (first match): `queued ≥ 2` of this def | cancel one — `train_cancel(producer, index)` with the index of the **last** queued instance of that def in `queue_of(producer)`, never the head while another instance waits (structures and research: `build_cancel(index)` / `research_cancel(index)`) |
| RMB, ON_HOLD | cancel the head — `train_cancel(producer, 0)` / `build_cancel(0)` / `research_cancel(0)`; the sim refunds what was paid (`cancel_refund_bp`); a queue that becomes empty clears its hold (request in `[XR-11]`); audio voices `canceled` from the resulting event |
| RMB, BUILDING | hold the queue (`queue_hold(kind, ids, true)`); cue `QUEUE_HOLD` |
| RMB, QUEUED (count 1, behind another def) | cancel that item by its queue index |
| LMB, LOCKED / BLOCKED | no command; toast with the requirement, deny cue, and the tab holding the missing prerequisite pulses for 1.5 s |
| hover 0.5 s | rich tooltip: name, tier, role line, resolved cost / time / power, key stats from `DefBrowser`, requirement in warning colour, hotkey chord |

`UNAFFORDABLE` (credits shown red) never blocks a click; only `check_*` failures do.

#### 5.10.5 Ready-to-place flow (`UiPlacement`; the ghost, its per-cell colours and the build-radius ring are drawn by the view)

1. Trigger: LMB on a READY structure card, its hotkey, or automatically when the item completes and `Structures` is the active tab (never steals the pointer). State `PLACING` on the card; `view.begin_placement(def)` shows the ghost model (`ViewPlacementGhost.show_structure`), the dashed 8-cell build-radius ring around every active HQ and, for defenses, a range preview (`ViewRangeRings.show_preview` with the largest weapon `range_u` of the structure card).
2. Pointer over the world (≤ 30 Hz, only when the anchor cell or orientation changes): `pick_ground` → cell `(cx, cy)`; **anchor** `(ax, ay) = (cx − fp_w / 2, cy − fp_h / 2)` for the oriented footprint size (integer division; this is the footprint's **top-left cell**, the cursor sits on the centre cell for odd footprints and on the lower-right centre cell for even ones; `BUILD_PLACE` sends `ax, ay` in whole cells, 5.8.2); `result = sim.placement_result(def, ax, ay, orient)`; `view.update_placement(ax, ay, result, orient)` (the view colours each footprint cell from `result.cells`: OK green, terrain / structure red, unit orange, deposit magenta, debris orange, apron yellow, shore cyan, and tints the model green or red by `result.reason == 0`).
3. **Rotation** only when `sim.footprint_rotatable(def)` (only the Dock: `DefStructureRules.Row.rotatable`, economy §7.2): `Ctrl+R` (`place_rotate`) or `Shift`+wheel turns the ghost by 90° clockwise (`orient` 0-3); the anchor is recomputed for the rotated width and height. `BUILD_PLACE` carries the rotation in its `mode` field (`economy.md` `CMD_BUILD_PLACE(s_idx, cx, cy, rot)`, `SimPlacement.validate(…, rot, out)`), so rotated placement is native.
4. Reason text under the cursor from `place_reason()` (a colour-independent cue: text plus the ghost's hatch pattern, QA V-S02): 1 "Outside build radius", 2 "Blocked", 3 "Needs shoreline", 4 "Only one strategic structure allowed", 5 "Unexplored". Cursor: DEFAULT if valid, DENIED otherwise.
5. LMB (valid) → `build_place(def, ax, ay, orient)`; cue `PLACE_OK`; card shows PLACING… until `construction_state` changes (timeout 1 s → READY again); `view.end_placement()`. Invalid click: cue `PLACE_FAIL`.
6. RMB / Esc / another card: cancel and `end_placement()`; the item stays READY. If the completed item is destroyed or cancelled meanwhile, the mode ends with a toast.

#### 5.10.6 Research, support powers, superweapon

* Research: one active + queue; LMB starts/queues (`RESEARCH`), RMB cancels (refund by sim). Times 45 s (T2) / 75 s (T3) are bible numbers shown from the resolved def. Completed upgrades persist even if the Radar is lost (bible); a lost prerequisite pauses unfinished orders → BLOCKED.
* Powers: `UiPowerDock` mirrors the POWERS tab (F5-F7 + F8) with sweeps and remaining seconds; the command carries the **power index** (`use_power(power_def, …)`: `def` = `p_idx` of the resolved roster power; the sim derives the slot and answers `NOT_AVAILABLE` for a power outside the roster's three), while the slot (0-2, `sim.power_slot`) only orders the dock and the `F5`-`F7` hotkeys. Powers that name one of the player's own structures or units (`target_mode` OWN_STRUCTURE / OWN_UNIT, e.g. one Airfield) highlight valid targets under the cursor and send `target = eid` with that entity's position as `(x, y)`. Targeting (`UiTargeting`): circle preview of the resolved radius, line/corridor powers preview length × width and take an **angle** (press = start, drag = direction, release = commit; binary angle = `posmod(roundi(atan2(dy, dx) × 4096 / TAU), 4096)` with `dx, dy` in sim axes — 0 = +x, increasing toward +y like `SimEntity.facing`; the sim rejects angles outside 0-4095 — computed by the UI as the single float→int step); Shift keeps the mode for another cast only if the power is off cooldown (it never is → no-op); RMB / Esc cancels. Own recon powers accept the whole map; damage-bearing powers draw a friendly-fire warning ring when own units are inside the preview.
* Superweapon: same targeting with the geometry from `DefSuperweapon` (Atlas: 3 circles r = 2 cells, ±3 cells; Aurora, Helios line, Perun disc+ring, Tempest area, Dragonfall, Horizon line, Trident interception zone — preview shapes come from the resolved def, `shape` enum in the fixture). After commit the launcher card shows WARNING and a ribbon "LAUNCHING" with the warning countdown; the bible's warning zones (visible to affected players) are drawn by the view (`ViewWarnings`); the UI adds the ribbon, the minimap ring and the edge arrow.

#### 5.10.7 Worked numbers

* **ETA label.** Radar: 30 s = 600 ticks. Progress 372 ‰ at normal power: `eta = ceil((1000 − 372) × 600 / 1000) = ceil(376.8) = 377 ticks` → `ceil(377 / 20) = 19 s` → **"0:19"**. Under shortage (`rate_pct = 50`): `ceil(376.8 × 100 / 50) = 754 ticks` → 37.7 s → **"0:38"**. The sim supplies `eta_ticks`; the formula is the fallback.
* **Credit ticker.** Target 12,450 from 11,020: the shown value is `roundi(lerp(from, to, ease_out_cubic(t / 0.3)))` for `t` in 0..0.3 s (`art_direction.md` §5.12.4: the ticker rolls in 300 ms) — 18 frames at 60 FPS, 1,430 credits: the first frame shows 11,020 + 1,430 × 0.157 = 11,245 (`ease_out_cubic(1/18) = 1 − (1 − 1/18)³ = 0.1567`); an event during a roll restarts from the value currently shown; `Δ = 30` rolls the same 0.3 s. Digits are drawn in fixed-width cells (widest digit of the font), commas half width, so the number never jitters.
* **Power bar.** capacity 300, usage 265: `scale_max = max(300, 265) × 1.1 = 330`; segment `i` starts at `lo = i × 330 / 32 = 10.3125 i`; used if `lo < 265 − 0.33` → segments 0-25 (26) lit, capacity marker at `300 / 330 = 90.9 %` of the bar. Usage 355: `scale_max = 390.5`, segments above capacity turn red and flash at 2.2 Hz, "LOW POWER" pulses, ribbon `low_power` appears.
* **Sweep.** progress 0.372 → shader `t = atan(p.x, −p.y) / TAU`, `dark = step(progress, t)`: the edge is at 134° clockwise from 12 o'clock; shaded = not yet finished.
* **Queue count pill.** `queued = 3` → pill "x3"; hidden when the state is AVAILABLE.

#### 5.10.8 Queue strip

Shows the chosen producer's queue: slot 0 with the clock wipe, slots 1-4 icons, header `FACTORY 2 // QUEUE` and `3 / 5`, a hold toggle (`queue_hold(PRODUCER, [producer], …)`) and a star (`set_primary(producer)`, filled when `is_primary`). `TRAIN_CANCEL` cancels by queue index, so: LMB on a slot → `train_cancel(producer, slot)` (slot 0 refunds what the head was paid); RMB on a slot → the same for every queued instance of that def in this producer, highest index first (one command each, ≤ 5 per click). Chevrons at the header (or `B`) cycle the shown producer. Hidden when COMPACT.

#### 5.10.9 Tooltips (`UiTooltipBody`, delay `ui/tooltip_delay_ms` = 500, max width 340, follows the pointer with a 16-px offset and stays inside the window)

| Widget | Content |
|---|---|
| Unit card | name (accent, Orbitron 15), `TIER n // ROLE TAG`, stat row **COST / TIME / POWER / HOTKEY** resolved for the local roster (a resolved value that differs from base shows the delta chip `+10 %` in good/bad colour; `(at floor)` on a bible floor), bible role text, main weapon line (damage type, range in cells, DPS from `DefBrowser`), requirement in warning colour, hint line "LMB build · RMB hold / cancel · Shift ×5" |
| Structure card | cost, build time, **power delta**, prerequisites, description, what it produces/unlocks, footprint and placement rule chips |
| Research card | cost, 45 s / 75 s, effect text, requirement, "Persists if the prerequisite is lost" |
| Power / superweapon | cost, cooldown or recharge + warning time, targeting rule ("any location", "needs current vision", "explored terrain"), effect and counterplay text |
| Command bar / tool row | action name `[Alt+…]` + one sentence |
| Selection tile | name, `hp / hp_max`, order, vet |
| Credits | "Credits — income +1,860 / min" |
| Power bar | "Power 265 / 300 — consumption above capacity halves production and research speed." |
| Group badge | "Group 3: 12 units — Ctrl+3 reassigns" |

#### 5.10.10 Top strip (`UiTopStrip`, top-left)

`mm:ss` game time from `sim.tick() / 20` (`h:mm:ss` past an hour), `KILLS n` / `LOST n` (`units_killed` / `units_lost`), optional `SCORE n` (`UiScore`, hidden in ranked-style rules-less skirmish by default — toggle in Interface), a speed badge when `speed_pct != 100` ("1.5×"), a pause glyph while paused, and in LAN a latency dot (green < 60 ms, yellow < 150 ms, red ≥ 150 ms from `session.stats().rtt_ms`). The strip is an `InsetPanel` and updates its text once per displayed second.

---

### 5.11 Selection model

#### 5.11.1 Rules

* Modes are exclusive: **UNITS** (own mobile entities, ≤ `MAX_SELECT` = 500), **STRUCTURES** (own structures; several allowed, commands limited to sell/repair/rally/stop-production), **FOREIGN** (exactly one non-own entity, read-only). Adding to a selection of another mode replaces it (units win over structures when both are boxed).
* **Primary** = first id of the *active subgroup*; the active subgroup is the `def_idx` with the highest `(tier, cost)` in the selection (ties: lowest def index) and changes with `Ctrl+Tab`. Portrait, name, role line and the ability bar follow the primary.
* `ids` keep selection order (oldest first); `sorted_ids()` (ascending, cached) is what commands carry, so identical user actions yield byte-identical command arrays.

#### 5.11.2 Survival of entity death and change

* Selection stores **ids only**. On every tick batch `prune(port)` (O(n)) removes ids that are dead, no longer owned by the viewer (captured: `OWNER_CHANGED`), or contained in a transport (`F_LOADED`, `LOADED` event); it re-picks the primary; if the selection becomes empty the panel shows NO SELECTION. Between batches `EV_DEATH` and `REMOVED` events remove the id immediately (no one-frame ghost).
* **Successor rule (exact, no distance heuristic):** deploying an MCV emits `REMOVED(reason DEPLOYED)` for the MCV and, in the same batch, `SPAWNED(reason DEPLOYED)` plus `EVT_HQ_DEPLOYED(pid, hq id)` for the Headquarters (`sim_core.md` §6.2, `economy.md` `deploy_mcv`; the reverse `UNDEPLOY_HQ` emits `EVT_HQ_UNDEPLOYED(pid, mcv id)`). When a selected id is removed with reason DEPLOYED its successor is the `SPAWNED(DEPLOYED)` entity of the same owner in the same batch whose `SimEntity.parent` equals the removed id (economy is asked to set it, `[XR-8]`); when `parent` is 0 the n-th `SPAWNED(DEPLOYED)` of that owner pairs with the n-th `REMOVED(DEPLOYED)` of that owner in emission order (one deployment emits both, so the pairing needs no distance). Any other removal just drops the id.
* Groups keep ids and drop dead ones lazily on recall (5.11.3); bookmarks and the alert list store positions only, never ids.

#### 5.11.3 Control groups

| Action | Effect |
|---|---|
| `n` | `select(recall(n))`; if every member is dead the slot is cleared and a soft "empty" tick plays; a second press within 350 ms (`register_press`) centres the camera on the centroid of the alive members (`input/group_double_tap_center`) |
| `Ctrl+n` | assign: group = current selection (a valid selection is single-mode, so groups are too) |
| `Ctrl+Shift+n` | add the current selection to the group |
| `Shift+n` | add the group to the current selection |
| badge click / double click (`UiGroupBar`) | same as `n` / double-tap |

Badges show the digit, the alive count and the dominant type glyph (structures: structure glyph); empty groups are dimmed.

#### 5.11.4 Selection panel content

| Selection | Portrait & header | Body |
|---|---|---|
| single unit | baked icon (152 x 76), name (Rajdhani Bold 18), role line (CAPS 14), HP bar `hp / hp_max` coloured OK / WARN / DANGER at ≥ 66 % / 33-66 % / < 33 % with tick marks at 33 and 66 % (`style.ui.hp_ramp`, the same ramp as the view's bars, `art_direction.md` §5.12.5), veterancy chevrons only if `RF_VETERANCY` | status chips (EMP, SUPPRESSED, CAMOUFLAGED, DEPLOYED), cargo `2 / 2`, ammo pips (aircraft), squad pips `squad / squad_max` (infantry, ≤ 5) |
| multi units | primary's portrait; header "SELECTED  n UNITS" | tile grid `TILE 46` (cols per 4.6.1) with HP bar, vet chevrons, squad pips; overflow tile "+N"; hover highlight; click semantics 5.5.4 |
| structure | portrait; name; HP; POWERED / OFFLINE chip | producers: queue summary "3 queued", rally flag, `Sell $N` (from `sell_value`), repair toggle; launcher: charge state; defenses: weapon range ring toggle |
| foreign | portrait; name; owner colour swatch + player name; HP | "Inspecting" chip; no command bar |
| none | "NO SELECTION" | command bar shows only sell/repair (armed-mode buttons) |

#### 5.11.5 Command bar enablement (4 x 2 grid)

| Button | Enabled when | Action |
|---|---|---|
| Attack-move `A` | `caps_any & CAP_ARMED` ∧ mobile | arm `ATTACK_MOVE` |
| Guard `G` | armed ∧ mobile | arm `GUARD` |
| Stop `S` | any mobile or producer | `simple(STOP)` |
| Scatter `X` | mobile | `simple(SCATTER)` |
| Deploy `D` | `caps_any & CAP_DEPLOY` | `deploy_toggle(ids)`: `DEPLOY` (def −1) for the units without `F_DEPLOYED` — an MCV included, the sim routes it — and `UNDEPLOY(slot)` for those with it; the icon shows the primary's `F_DEPLOYED` state |
| Sell `Delete` | `caps_any & CAP_SELLABLE` (structures) or always as tool | arm `SELL` |
| Repair `R` | always as tool (structures) | arm `REPAIR` |
| Stance `Z` | armed ∧ mobile | cycle 0 → 1 → 2 → 3 → 0 (`SET_STANCE`); icon shows the primary's stance, "MIXED" glyph when the selection disagrees |

The **utility row** under the grid holds fixed, context-dependent buttons, each shown only when it applies, followed by the dynamic ability slots of 5.11.6: Hold `H` (armed ∧ mobile → `hold(ids)`), Patrol `P` (mobile → arms PATROL), Follow `Ctrl+F` (mobile → arms FOLLOW; the click must land on an own or allied unit), Return `V` (`CAP_AIR` / `CAP_CARRIER_DRONE` → `return_to_base` with target 0; `CAP_COLLECTOR` → `return_cargo` to the nearest refinery), Unload `U` (transports with `cargo > 0`).

#### 5.11.6 Ability bar (dynamic, ≤ 4 slots after the utility row)

Derived from the **active subgroup**'s `DefUnit.abilities` (kinds) and applied to `ids_of_def(UNIT, active_def)`; the `slot` of a button is the ability's index in the unit def (`sim_core.md` §6.1: the `def` field of ops 100-104):

| Ability kind | Button | Command |
|---|---|---|
| MODE_SWITCH (all shipped switches have exactly two modes, `abilities_catalog.md`), and the Shogun's CARRIER wing | "Switch to {other mode}" with the template's label/icon (`mobile / siege`, `AA load / AV load`, `strike / interceptor` wing for CARRIER); the `deploy`-kind switches (siege) are also on `D` | `set_mode(ids, slot, other_mode_of_primary)` — an explicit index, so a mixed group converges on one mode |
| PORTABLE_COVER / DECOY_SPAWN / SENSOR_PUCK / SMOKE_LAUNCHER | ability icon with a cooldown sweep from `EV_ABILITY_USED` / `EV_ABILITY_READY` when exposed, else enabled; while BUILDING or ACTIVE the button offers Cancel | `use_ability(ids, slot, 0, x, y)` (start) / `cancel_ability(ids, slot)`; kinds that need a point arm `UiModes.Armed.ABILITY` first |
| SUBMERGE | no button — the state machine follows combat's `want_surface` (`abilities.md` §5.6.4); the selection panel shows a SUBMERGED / SURFACED chip from the row's `mode` | — |
| TRANSPORT | Unload (needs `cargo > 0`) | `unload(ids)`: one `UNLOAD` (all cargo) per carrier at its own position |
| CAPTURE / REPAIR / SALVAGE | context-only (right-click rules 2, 5-7), no button | — |

Hotkeys `I O K L` in slot order, `U` for Unload. **Auto-cast:** repair/heal actors default to auto-cast ON in the sim (`abilities.md` §5.6.3) and show a small "A" pip on the button; right-click on the button toggles it with `set_autocast(ids, slot, on)`, and the pip follows the entity's `AUTOCAST` bit (row `mode` block). Structures: a selected HQ shows **Pack HQ** (`undeploy_hq`, confirm dialog — it turns the base into an MCV).


#### 5.11.7 Camera pad and Select menu (mouse-only viability, QA A-06 / A-19)

Every shortcut of the game has a HUD control, so the game is playable with the mouse alone and with the keyboard alone:

* **Camera pad** (`UiCameraPad`, 6 icon buttons under the minimap frame, shown unless `ui/camera_pad` is off, also in COMPACT): rotate left / right (hold repeats), tilt up / down, zoom in / out, centre on base, jump to alert. It calls the same `UiViewPort` methods as the keys.
* **Select menu** (`UiSelectMenu`, the "SELECT" button at the end of the tool row, popup with the keymap labels beside each entry): all military (map), all military on screen, same type on screen, idle unit (next / previous), next collector, next producer, headquarters, control groups 1-0 (recall), camera bookmarks 1-4. Backed by `UiSelectionActions`.
* Keyboard-only paths: `Tab` cycles the sidebar tabs, cards have `Alt`+grid hotkeys, `N`/`C`/`B` cycle idle units / collectors / producers, groups on `1`-`0`, bookmarks on `F9`-`F12`, `Space` jumps to the newest alert.

---

### 5.12 Minimap

* **Geometry.** Widget side `S = UiLayout.minimap_size(logical_h)` (180-300); pad 5; map rect `m = (5, 5, S − 10, S − 10)`; non-square maps are letterboxed into `m` keeping the cell aspect. `norm = ((local − m.pos) / m.size).clamp(0, 1)`; `sim = round(norm × cells × 1024)` clamped (5.8.2). Draw order: inset panel → a `TextureRect` child holding `view.minimap_texture()` with `view.minimap_material()` (terrain and this viewer's fog in one shader pass: the view uploads the fog at ≤ 10 Hz and cross-fades it on the GPU) → 1/8 grid ticks (α 0.035) → ghosts (α 0.5) → dots → camera quad (fill α 0.06, polyline α 0.95, 1.5 px; corners clamped to −0.05..1.05) → strategic-warning circles → pings → radar sweep → "N".
* **Blips** (`art_direction.md` §5.12.6): colour = `UiPalette.team(color_of(owner))` (colour-mode aware), shape = **class** — infantry 2-px dot, vehicle 3-px square, air 3-px diamond, naval 3-px triangle, structure 4-px outlined square, superweapon pulsing 8-px star (feed fields `dots_class`, `dots_size`); the viewer's own blips are +1 px with a 1-px dark outline; neutral capturable structures are hollow squares in the NEUTRAL colour. In colour mode `cvd` structure blips (5 px) show the owner's pip shape (the view's table, 5.19.3) instead of the outlined square, and the hover tooltip over any blip names the owner (swatch, player number, name) in every mode: the non-colour player cue of QA A-01 at minimap scale. Enemy blips only for currently visible enemies (5.9).
* **Cadence.** Feed rebuilt every 2 ticks (10 Hz); the widget redraws at 30 Hz (`_accum ≥ 1/30`) only when the feed changed, a ping is alive or the sweep is on. Cost (spike): 0.23 ms per redraw for 439 dots.
* **Strategic-zoom class markers** (`UiWorldOverlay`, `art_direction.md` R-18; not part of the minimap widget). While `UiViewPort.px_per_metre() < 18` and `ui/strategic_markers` is on, every visible **unit** of `snapshot()` (structures and wrecks keep the view's brackets) that projects inside the viewport gets its role glyph (`UiGlyphs.role_glyph`, drawn from the lazily baked white atlas) at 20 px in its owner colour, tinted per draw call, with a 1-px `BG_DEEP` shadow. Positions come from one `UiViewPort.project_points` call at 15 Hz and are redrawn at 30 Hz from the cached points (dead reckoning is unnecessary at that zoom); culled to the viewport and capped at 400 markers (own first, then allies, then visible enemies). Budget 0.4 ms: 400 `draw_texture_rect_region` calls sharing one atlas texture batch into one draw command. Off in `UiHud.lite`; markers are `MOUSE_FILTER_IGNORE` (picking stays the view's).
* **Pings.** Expanding ring `radius = 4 + 22 k` px, alpha `1 − k`, `k = frac(age / 1 s)` (a 1 Hz ring, `art_direction.md` §5.12.6); ALERT in `WARN` for 3 s (three rings), ORDER white-green for 1 s, ALLY in the `ALLY` cyan for 3 s, SUPERWEAPON in `DANGER` red until impact.
* **Sweep.** Wedge of 6 slices at `1.1 rad/s`, accent α 0.16 fading; off with `reduce_motion` or `ui/minimap_sweep = false`; low power only desaturates it (decision 10).
* **Input.** LMB press → `camera_requested(norm)`, drag keeps emitting even outside the rect (implicit grab); double click centres without smoothing; RMB → `order_requested(norm, mods)` (resolved as a GROUND target: MOVE, or the armed mode's order); armed PING → `ping_requested`; wheel is consumed (no camera zoom through the widget).
* **Frustum quad.** `view.frustum_ground_quad()` (four `screen_to_ground` rays, ≈ 40 µs) at every `camera_changed` (max 30 Hz).

### 5.13 Notifications, alerts and the message feed

#### 5.13.1 Engine (`UiNotifier` + `UiNoticeRules`, table in `notices.json`, 7.6)

Each rule: `{id, trigger, filter, severity, title_key, sub_key, ribbon, log, glyph, announcer_line, cue, ping, jump, cooldown_s, dedupe, ttl_s}`. `post()`: (1) drop if the same `dedupe` key fired within `cooldown_s` (wall seconds; a sim pause does not pause cooldowns, so a paused game cannot spam); (2) add to the feed (`log`) and to the ribbon stack if flagged; (3) `cue`: a UI-only `snd.ui.*` id (`UiAudioPort.ALERT` / `NOTIFY` / `ERROR`, 6.3.1) for notices audio does not voice by itself — rows with an `announcer_line` play nothing here; (4) minimap ping, off-screen edge arrow and `last_alert` position; (5) publish `notice`. **The notifier never requests a voice line**: audio speaks the sim events itself (`audio.md` §6.2, decision 16). `announcer_line` names the line audio speaks for the same event and is used only to suppress the duplicate caption (below). Ribbons: ≤ 4 (COMPACT 3) ordered DANGER > WARN > OK > INFO then newest; a repeat of the same `rule_id` updates the ribbon in place (countdown / charge) instead of stacking; a ribbon click jumps to its position or activates it (own superweapon READY → targeting).

**Captions (A-07, `audio/captions`).** `UiAudioPort.caption(line_id, text, priority)` → `UiNotifier.on_caption`. When a notice whose `announcer_line == line_id` was posted within the last 3 s, the caption is dropped (the notice already shows richer text); otherwise, with `audio/captions` on, the caption text is appended to the feed as an INFO line (mission start, victory, defeat, ally defeated, player disconnected, game paused …). With captions off, spoken-only lines that no notice covers are not mirrored; every alert that matters still has a ribbon, a log line, a minimap ping and an edge arrow.

**Fog rule for events.** The sim emits its events identically on every peer and does not filter by viewer (`sim_core.md` §5.7), so the notifier filters: events about the viewer's own entities (and, for `attack_alert` and `warning`, the viewer's allies) always pass; events that originate from an enemy (`EVT_POWER_ACTIVATED`, `EV_BUFF_APPLIED`, `OWNER_CHANGED` of a neutral structure …) pass only when their position `(x, y)` is currently `VISIBLE` or the rule is flagged `global` (strategic warnings — which additionally need the `affected` check of the bible rule —, defeat, chat). Nothing else reveals a position the viewer could not see.

#### 5.13.2 Rule table

Event fields are the letters of 6.2.1 (`UiEv` names in lower case are the `trigger` values); `x, y` are the record's position slots. "Viewer" = `viewer_pid`; observers get no personal notices, only the global rows. The *announcer line* column is what **audio** says for the same event; the UI adds only the *cue* written as "cue …".

| Rule id | Trigger (event · filter) | Sev | Ribbon | Announcer line (audio) / UI cue | Ping · jump | Cooldown · ttl |
|---|---|---|---|---|---|---|
| `base_attack` | `attack_alert` · `a` = viewer ∧ class `d` = 1 (structure); structure name from `read(b)`, sector from `(x, y)` | WARN | "BASE UNDER ATTACK" / "{structure} // {sector}" | `base_under_attack` | ALERT · yes | 6 s · 8 s |
| `unit_attack` | `attack_alert` · `a` = viewer ∧ `d` ∈ {0, 3} | INFO | — (log) | `unit_under_attack` / `aircraft_under_attack` | ALERT · yes | 10 s |
| `collector_attack` | `attack_alert` · `a` = viewer ∧ `d` = 2 | WARN | — (log "Collector under attack at {sector}") | `collector_under_attack` | ALERT · yes | 10 s |
| `ally_attack` | `attack_alert` · `a` is an ally of the viewer ∧ `d` = 1 | INFO | — (log "{ally}: base under attack at {sector}") | `ally_under_attack` | ALLY ping · yes | 15 s |
| `unit_lost` | `death` · owner `((e >> 8) & 0xFF) − 1` = viewer ∧ flags `(c >> 8) & 0xFF` has 64 (unit) ∧ has neither 4 (decoy) nor 8 (summoned) ∧ `def_flags(UNIT, b)` has `DF_COUNTS_FOR_CAP` | INFO | — | `unit_lost` | — | 15 s; aggregated "3 units lost" per 3 s window |
| `hq_lost` | `death` · owner = viewer ∧ structure flag 16 ∧ def `b` = `roster_of(viewer).hq_idx` (`DefRoster.hq_idx`) | DANGER | "HEADQUARTERS DESTROYED" / "{sector}" (art §5.12.5: "base destroyed" is a DANGER banner) | `structure_lost` | ALERT · yes | 8 s · 10 s |
| `structure_lost` | `death` · owner = viewer ∧ flags `(c >> 8) & 0xFF` has 16 (structure) | WARN | — (log) | `structure_lost` | ALERT · yes | 4 s |
| `low_power` | `power_shortage` · `a` = viewer | WARN | "LOW POWER" / "Production and research at 50 %" (persistent until restored) | `low_power` (audio repeats it every 45 s) | — | edge-triggered |
| `power_restored` | `power_restored` · `a` = viewer | OK | ribbon cleared, log line | `power_restored` | — | edge |
| `construction_ready` | `structure_ready` · `a` = viewer | OK | — (log "Construction complete: {name}. Ready to place.") | `construction_complete` | — | 2 s; tab STRUCTURES pulses; `Structures` auto-focus if idle |
| `unit_ready` | `unit_produced` · `a` = viewer | INFO | — | `unit_ready` | — | 8 s per producer type |
| `research_done` | `research_complete` · `a` = viewer | OK | — (log) | `research_complete` | — | — |
| `tech_unlocked` | UI-derived (`state_tech_unlocked`): the set of AVAILABLE cards grew between two `UiBuildModel.refresh` calls | INFO | — (log "New: {name}") | `new_construction_options` (only if the sim event returns, 6.2.1) | — | 10 s; the tab holding the def pulses |
| `tech_lost` | UI-derived: a card left AVAILABLE for LOCKED / BLOCKED because a prerequisite structure died | WARN | — (log "{name} unavailable: {cause} lost") | cue `ALERT` | — | 10 s |
| `power_unlocked` | `power_unlocked` · `a` = viewer | INFO | — (log "New support power: {power}") | — | — | — |
| `power_ready_own` | `power_ready` · `a` = viewer, slot `b` | INFO | — (log "{power} ready"; the dock button glows) | `power_ready` / `power_<name>_ready` | — | — |
| `sw_ready_own` | `sw_ready` · `a` = viewer | OK | "{launcher} READY" (click = target) | `sw_ready` | — | edge |
| `sw_warning_enemy` | `warning` · owner `b` is an enemy of the viewer ∧ `c` = 0 (superweapon) ∧ the warning is listed by `strategic_warnings()` for the viewer (affected; exempt from the fog rule) | DANGER | "ENEMY SUPERWEAPON DETECTED" / "{weapon} // {player} // {sector}" + countdown `(exec_tick − tick) / 20` from the warning record | `sw_launch_detected` | SUPERWEAPON ring · yes | until the warning ends + 3 s |
| `sw_warning_ally` | `warning` · `c` = 0 ∧ owner is an ally | INFO | "ALLIED STRIKE INBOUND" + countdown | `sw_launched` | ring | until the warning ends |
| `sw_warning_own` | `warning` · `c` = 0 ∧ owner = viewer | INFO | "LAUNCHING" + countdown | `sw_launched` | ring | until the warning ends |
| `power_warning_enemy` | `warning` · `c` = 1 (power barrage) ∧ enemy ∧ listed | WARN | "INCOMING STRIKE" + countdown | `sw_incoming_strike` | ring · yes | until the warning ends |
| `scan_warning` | `warning` · `c` = 2 (scan) ∧ enemy ∧ listed, or `scan_warning` | WARN | "SCAN DETECTED" | `scan_detected` | ring | until the warning ends |
| `sw_inbound` | `sw_exec_start` · the warning is listed | – | the warning's ribbon switches to "INBOUND"; cleared by the first `sw_impact` / `sw_done` (or after 8 s) | — | — | — |
| `sw_cancelled` | `sw_cancelled` · the warning was listed (cause 1 launcher destroyed, 2 shut down, 3 sold; no refund, bible) | WARN | ribbon cleared, log "Launch cancelled" | `sw_cancelled` | — | — |
| `power_used_enemy` | `power_activated` · enemy pid ∧ position `VISIBLE` | INFO | — (log "{player} used {power}") | — | ping if known | 5 s |
| `buff_applied` | `buff_applied` · owner = viewer | INFO | — (log "{power}: {n} units") | — | — | 2 s |
| `cmd_rejected` | `cmd_rejected` · `a` = viewer, err `c` (or `place_rejected`) | INFO | — (log "{reason text}") | `unable_to_comply` / `cannot_deploy` (BAD_SITE) | — | 1 s |
| `order_failed` | `order_failed` · unit `a` owned by the viewer | INFO | — (log "{unit} cannot reach the target") | (the unit's deny response) | — | 3 s |
| `insufficient_funds` | `insufficient_funds` · `a` = viewer; `cmd_rejected` NO_CREDITS; UI refusal | WARN | — | `insufficient_funds` | — | 5 s |
| `unit_cap` | `unit_cap_reached` · `a` = viewer; `cmd_rejected` UNIT_CAP; UI refusal | INFO | — | `unit_cap_reached` | — | 5 s |
| `unload_blocked` | `unload_blocked` · carrier owned by the viewer | INFO | toast "No room to unload" | — | — | 3 s |
| `cannot_place` / `queue_full` | UI refusals | INFO | — | cue `ERROR` | — | 2 s |
| `structure_sold` | `structure_sold` · `a` = viewer | INFO | — (log "Sold {name}: +${refund}") | `structure_sold` | — | — |
| `player_defeated` | `player_eliminated` (global) | INFO (ally / local: WARN) | — (log) | `ally_defeated` / `enemy_defeated` | — | — |
| `player_left` | `player_status_changed` LEFT / DROPPED / DISCONNECTED / AI_TAKEOVER / RESIGNED | INFO | — (log) | `player_disconnected` | — | — |
| `captured` | `owner_changed` · reason 0 (capture) with the viewer as old or new owner | OK (gained) / WARN (lost) | — (log) | `building_captured` / `structure_captured` | ping · yes | — |
| `emp_hit` | `emp` · victim `a` owned by the viewer ∧ `e` = 0 | WARN | — (log "{name} disabled by EMP") | — (audio plays the EMP cue) | — | 10 s |
| `chat_msg` | `chat_received` | INFO (system WARN) | — (feed, sender colour) | cue `CHAT` | — | — |
| `ally_ping` | `map_ping` | INFO | — | cue `MINIMAP_PING` | ALLY · yes | 1 s |
| `net_error` | `net_error(code, text)` | WARN | toast | — | — | 5 s |
| `idle_collector` (UI-derived) | own collector `order_kind == 0` for > 200 ticks while deposits exist (tracked from `SPAWNED` / `REMOVED` and `read`) | INFO | — (log "Collector idle") | cue `NOTIFY` | — | 60 s |

**Ribbon anatomy** (`art_direction.md` §5.12.5, spike-verified): every ribbon has a glyph, a bold title and a dim subtitle and a 1 Hz border pulse while active (static under `access/reduce_motion`); DANGER = red banner with MISSILE (enemy superweapon, strike) or WARNING (headquarters lost, scan); WARN = amber with WARNING (base under attack); OK = green with BOLT for the own-superweapon READY ribbon, CHECK otherwise; INFO = the skin accent with the topic glyph (POWERS, GEAR, RADAR …).

Colours in the feed: sender/owner swatch from the team palette (`UiPalette.team`, with the player number beside it); severity tint for rule lines; text is rendered as **plain text** (chat and names never parsed as BBCode — `RichTextLabel.add_text`, `push_color`, never `append_text`, XR-16 of net.md).

#### 5.13.3 Feed behaviour

`UiLogFeed` (bottom-left, 6 lines / 4 COMPACT / 10 LARGE) shows notices, captions and chat together; each line fades after 8 s (chat: `ui/chat_fade_s`); opening chat (`Enter`) shows the last 50 lines with the input box; `audio/captions` mirrors the spoken lines that no notice covers (5.13.1).

---

### 5.14 Lobby and skirmish setup (`UiScreenLobby`)

#### 5.14.1 Composition

Three logical columns at ≥ 1600 logical px: **left** slot table (8 rows x `LOBBY_ROW_H` 48) above the faction briefing; **middle** map panel above rules panel; **right** (LAN roles only) chat, spectators, lobby name/password. Below 1600 the right column becomes a bottom drawer; skirmish (LOCAL) never shows it. Title bar: emblem of the focused slot's faction, "SKIRMISH" / "LAN LOBBY — {lobby name}", data-hash chip (`UiFormat.hash8`), latency chip for clients. Bottom bar: Back, Save preset (LOCAL), status line ("6 players · 2 open · data hash 9F3A-C21E"), and START (host/local) or READY toggle (client).

#### 5.14.2 Editable controls per role

| Control | LOCAL | HOST | CLIENT |
|---|---|---|---|
| Type: Human / AI Easy·Medium·Hard·Brutal / Open / Closed | slot 0 fixed Human; others free | slot 0 fixed (host); others free (`host_set_slot_kind`, `host_set_ai`); Brutal shows `ai.cheats.brutal` and defaults the handicap to 120 % | read-only |
| Faction + subfaction (5.14.3) | all rows | all rows (`host_set_slot_roster`) | own row (`set_roster`) |
| Team None / A-D | all | all | own |
| Colour swatch grid (12; 8 in colour mode `cvd`; conflict swaps; hex from `ViewStyle.player_color`, player number and pip shape on each swatch, plate-contrast hint under the row, 5.19.3) | all | all | own |
| Start position | all | all | own |
| Handicap chip 50-200 % | AI rows | all rows | read-only |
| Ready | — | host is always ready | own toggle |
| Kick / ban (host, remote humans) | — | X button | — |
| Name | own | own | own |
| Move to slot / spectate | — | — | buttons (`move_to_slot`, `become_spectator`) |

Row visuals (spike): colour bar, index, emblem (accent of the roster's faction; muted for Open/Closed), pickers (`OptionButton`s with `fit_to_longest_item = false`, `clip_text = true`), status text (READY green, NOT READY warn, OPEN/CLOSED muted, DISCONNECTED danger) and ping in ms.

#### 5.14.3 Roster picker → roster id or random token (net.md §5.3.4)

| Faction dropdown | Subfaction dropdown | Result |
|---|---|---|
| a faction `F` (8) | Vanilla | `roster.<f>.vanilla` |
| `F` | one of its 3 subfactions | `roster.<f>.<sub>` (ids from `GameData.roster_for(code, sub_key)`) |
| `F` | "Any (random of 4)" | `random.<f>` |
| Random | "Vanilla (any faction)" | `random.vanilla` |
| Random | "Subfaction (any faction)" | `random.subfaction` |
| Random | "Any" | `random` |

Rosters are atomic (bible `rule.design.roster_selection`): no per-unit picking, no mixed packages. Random tokens are resolved by the host at launch (`from_lobby`), the loading screen then shows the concrete roster.

#### 5.14.4 Start errors → UI (`NetLobby.StartError`)

| Code | Text key | Highlight |
|---|---|---|
| 1 `NO_PLAYERS` | `lobby.err.no_players` | slot table |
| 2 `NOT_ENOUGH_PLAYERS` | `lobby.err.not_enough` ("Add at least one opponent") | first Open slot |
| 3 `HUMAN_NOT_READY` | `lobby.err.not_ready` | rows with ready = false |
| 4 `HUMAN_DISCONNECTED` | `lobby.err.disconnected` | that row |
| 5 `BAD_ROSTER` | `lobby.err.bad_roster` | faction dropdown |
| 6 `COLOR_CONFLICT` | `lobby.err.color` | swatches |
| 7 `START_CONFLICT` | `lobby.err.start` | start markers |
| 8 `TOO_MANY_PLAYERS` | `lobby.err.too_many` | map layout dropdown |
| 9 `MAP_INVALID` | text from `MapGenerator.validate_params` | map panel |
| 10 `SINGLE_TEAM` | `lobby.err.single_team` | team column |
| 11 `ALREADY_LAUNCHING` | (ignored) | — |

The START button is always clickable (so the reason is discoverable); the error appears as a red line above it for 6 s and the highlight pulses twice.

#### 5.14.5 Map panel

Family (3: open land / urban routes / coast & river), size (96, 128, 160, 192, 224, 256), layout players (2/4/6/8; shrinking closes slots ≥ N as net does), seed as **8 hex digits** (editable `LineEdit`, validated `[0-9A-Fa-f]{1,8}` → u32; **Re-roll** uses the engine RNG — UI-side randomness is allowed, the chosen seed is what gets transmitted), name from `UiMapNames.name_for(family, seed)` (a deterministic syllable table in `data/text/map_names_en.json`; cosmetic, never transmitted), preview image from `UiMapPreview`: `MapGenJob.begin(map_cfg, null, true)` (`terrain_movement.md` §3.7: one worker thread running the pure `MapGenerator.generate` and the navigation preparation; the panel calls `step(0)` once per frame — a poll of < 50 µs — and reads `progress_pct()` for the spinner; ≈ 0.3 / 0.6 / 1.5 / 2.5 s for 96 / 128 / 192 / 256 cells, `qa.md` §5.8), the finished `MapData` goes through `UiViewPort.bake_map_preview` (the view's `ViewMinimapSource.bake`, 21-42 ms at 192², a one-frame hitch) and the texture is drawn at 280 px and cached by `(family, size, seed, layout_players)`; a spinner and the family emblem show meanwhile, and a change of seed while a job runs `cancel()`s it and drops the stale result. Numbered start markers in the occupant's colour from `map.start_cells` (`[cx0, cy0, cx1, cy1, …]` in start order = the start index net stores, HQ centre cells; click your own marker to `set_start`); the host's **Balance starts** button assigns the occupied slots to `map.fair_slot_order(n)` through `host_set_slot_start` (net's own `-1` random start does not know the geometry, `[XR-31]`); static line "≥ 2 exits per start area; no water needed for the economy". The generator's optional `params` (water %, clutter density, resources, neutral density, biome, start near water) are not offered: net reserves `map.params = {}`. Invalid combination → red text from `MapGenerator.validate_params(family, size, layout_players)` (size a multiple of 8 within 96-256 and at least `MapGenParams.min_size(slots)`: 96 / 112 / 128 / 160 / 192 for 2 / 3 / 4 / 6 / 8 slots). The size dropdown marks `MapGenParams.recommended_size(players)` (2 → 128, 3 → 144, 4 → 160, 5-6 → 192, 7-8 → 224) with a star; the sizes offered are net's `lobby_options.json` list, and sizes below `MapGenParams.min_size(layout_players)` are greyed out.

#### 5.14.6 Rules panel

| Control | Values (default in bold) |
|---|---|
| Starting credits | 2,500 · 5,000 · **7,500 (bible preset)** · 10,000 · 15,000 · 20,000 · 50,000 (`rules.start_credits`, 0-100,000) |
| Unit cap | 50 · 100 · **150** · 200 · 300 · 500 (`rules.unit_cap`, 20-500) |
| Game speed | Very slow 50 % · Slow 75 % · **Medium 100 %** · Fast 125 % · Faster 150 % · Turbo 200 % (`lobby_options.json`) |
| Superweapons / Fog of war / Shared ally vision | **on** / **on** / **off** |
| Veterancy | **off** (bible first prototype) |
| Host only (LAN): Pause policy, On disconnect, Auto-drop, Spectators, Password, Lobby name | net.md §7.2 defaults |

Clients see the same panel read-only. (The spike's demo "crates / salvage bonus" checkbox does not exist in the rules schema and is dropped.)

#### 5.14.7 Faction briefing panel

Source: the hovered slot, else the focused slot; all data via `DefBrowser.faction_card`/`roster_card` (never JSON). Tabs:

| Tab | Content |
|---|---|
| Overview | emblem, faction name (Orbitron, faction accent), motto, identity line, subfaction title + lore (first 3 lines), **modifier list** (the `modifiers` rows of `DefBrowser.roster_card`: `source_text`, stat, `delta_bp` and the `conditional` flag, rendered with ▲/▼ arrows classed by `UiFormat.delta_class(stat, delta_bp)`: negative cost/build-time/reload = good, positive health/damage/speed = good), traits, opening and counterplay tips |
| Units | `UiRosterStrip` of baked portraits for `producible_units` (13 baseline + 4 service, minus replaced + uniques) with tier pips and **UNIQUE** badges (`replaced_by_roster`), plus the roster delta list ("Pathfinder APC → Beaver Amphibious APC", "REMOVED Titan Gunship", "Unavailable power: Combined Arms Window") |
| Tech | structures in tier order with cost/power, the 3 research upgrades |
| Powers | 3 powers (cost, cooldown, requirement) + superweapon (recharge, warning) with their effect text |

Clicking a unit/structure/power opens the Field Manual at that entry (`push field_manual {roster_id, focus_id}`).

#### 5.14.8 Presets and persistence

`game/skirmish_preset` names one of `skirmish_presets.json` (1v1 vs Medium AI on a 96 open-land map; 2v2; 3-AI free-for-all on 128; 4v4 on 256 with Hard AIs); the last edited lobby state is serialised to `game/last_skirmish` (JSON of `NetLobbyState` fields) whenever the screen is left, and restored on entry (rosters validated against `GameData.roster_ids()`; unknown ids → Random). Saving a preset name stores the same JSON under `game/skirmish_preset`.

#### 5.14.9 Chat, ready, kick, spectators

Chat panel: `LineEdit` (max 200 bytes, `NetProtocol.sanitize_text` applied by net), history `RichTextLabel` fed with `add_text` (plain), sender colour = slot colour, system messages `[SYSTEM]` warn colour; `Enter` focuses the box. Team chat toggle `Shift+Enter`. Kick asks a confirm dialog with "ban for this session". Spectator list below the chat when `allow_spectators`.

---

### 5.15 LAN browser and joining (`UiScreenLanBrowser`)

* **Entry** shows `UiDlgFirewallHelp` once (setting `net/help_shown`) with the OS-specific text of `net.md` §5.13 (Windows "Private networks", macOS "Local Network" permission, Debian ufw command, ports UDP 27614-27624) chosen by `OS.get_name()` (cosmetic use only), **before** `NetDiscovery.start_browse()`. If `browse_error == "port_in_use"` the header shows `net.help.port_in_use` ("Use Join by IP").
* **List** (`UiListRow`, one canvas item per row): GAME, HOST, MAP (family + size), PLAYERS `humans/total`, RULES (`7.5k · 1.0x · SW`), PING, BUILD (`v0.1.0 OK` / `OLD` / `DATA`). Rows come from `NetDiscovery.entries()` (sorted by host name/address); entries expire after 4 s without an announce (net). **Incompatible games are listed dimmed with the failing layer** (`proto` / `sim` / `data` → `OLD` or `DATA` and a tooltip with both hashes via `UiFormat.hash8`), full games dimmed with "FULL", password games with a lock glyph. Filters: text, hide full, hide incompatible; sort by any column; REFRESH restarts the browse.
* **Detail card**: map preview when known, player slots (from a `LOBBY_SNAPSHOT` only after joining; before that only counts), compatibility banner, **JOIN GAME** (disabled with the reason text when incompatible or full).
* **Direct connect**: `LineEdit` IP/host + port (default 27615); validation: IPv4/IPv6 literal or host name ≤ 253 chars, port 1024-65535; **Recent hosts** dropdown (`net/recent_hosts`, ≤ 8); CONNECT → `AppNet.join_lan(address, port, password)`.
* **Join flow**: state CONNECTING (spinner + Cancel, 6 s `CONNECT_TIMEOUT`) → `join_rejected(reason, info)` → `UiDlgJoinRejected` with `NetProtocol.describe_reject` text (`net.err.proto|sim|data` naming the failing layer and both hashes; `net.err.full`, `in_progress`, `banned`, `host_busy`; `BAD_PASSWORD` re-opens a password prompt) → or LOBBY (client screen).
* **Host**: `UiDlgHostGame` (lobby name ≤ 24, optional password, port, "Advertise on LAN" = `net/discovery`) → `AppNet.host_lan`.
* **Silence hints** (no false alarms): after 8 s of an empty list show `net.help.no_games`; if `announce_ok` is false for 10 s in the host lobby show `net.help.announce_blocked`; never block the UI on the OS permission prompt.

---

### 5.16 In-match menus, overlays, observer/replay, end of match

#### 5.16.1 Game menu (`UiDlgGameMenu`, Esc)

Items: **Resume**, **Options** (push), **Field Manual** (push), **Surrender** (confirm: "Surrender the match? You become an observer of your own match." → `net.surrender()`; HUD switches to observer mode, banner "YOU HAVE SURRENDERED"), **Leave match** (confirm; LOCAL: abandons the match and returns to the main menu — the autosaved replay stays; LAN: `session.leave()`, which resigns via the host). The footer reads "The game continues while this menu is open." in LAN; in LOCAL with `input/pause_on_menu` the menu requests `request_pause(true)` when it opens (only if it was not already paused) and resumes on close.

#### 5.16.2 Pause, stall, desync

| Overlay | Trigger | Content |
|---|---|---|
| Pause banner (`UiPauseBanner`) | `pause_changed(true, by_pid)` | "PAUSED — {name} paused the game ({left} pauses left)" (`net.pause.by`), **Resume** if `request_pause(false) == OK` for the local player (pauser or host); LOCAL: "PAUSED — press {key} to resume" (`{key}` = `UiKeymap.label(&"pause_game")`, so "Pause" or "Ctrl+P" as bound) |
| Stall overlay (`UiStallOverlay`) | `stall_changed(waiting)` (net raises it after 400 ms) | `net.stall.waiting` "Waiting for {names}… {seconds} s"; per-reason subline (`DISCONNECTED` "connection lost", `SLOW_CPU` "{name}'s computer is running slowly"); "Waiting for the host…" when no `STALL_INFO` for 1.5 s; the sim view freezes, the UI stays live |
| Stall prompt (`UiDlgStallPrompt`, host only, **non-modal**: a docked panel under the top strip that never dims or blocks the game view or the input controller, QA A-12) | `stall_prompt(pids)` after 8 s | **Wait** / **Drop (player resigns)** / **Replace with AI** → `host_resolve_stall(pid, action)`; no answer keeps waiting (there is no forced choice and no countdown) |
| Desync (`UiDlgDesync`) | `desync_detected(report)` | `net.desync.title/body` with mm:ss and tick, **Show folder** (`OS.shell_open(globalize_path("user://desync"))` — the one sanctioned use of `shell_open`, no `OS.execute`), **Save replay**, **Leave**; the world stays readable, HUD frozen |
| Connection lost | `phase == DISCONNECTED` / `kicked` | message dialog, then LAN browser / main menu |
| Net overlay (`UiNetOverlay`, F3) | toggle | `session.stats()`: role, tick, turn, delay D, speed, RTT/jitter per pid, kbps in/out, load, stalls, last checksum tick; plus FPS and the UI cost counters |

#### 5.16.3 Observer and replay HUD

`UiHud.setup(mode = OBSERVER)` removes the sidebar build area (keeps minimap, credits of the *viewed* player, power) and shows `UiObserverBar` (perspective: **All players (fog off)** or one player; keys `1..8`, `0`, `Tab`), `UiScoreboard` (F2: player, emblem, team, credits, income/min, units, structures, kills, losses, score, APM) and, for replays, `UiReplayBar`: play/pause, speed chips ¼ · ½ · 1 · 2 · 4 · 8 · MAX (`NetReplayPlayer.SPEEDS`), a seek bar (`progress()`, drag → `seek_tick`, a spinner while `is_seeking()`), tick marks every 600 ticks (30 s), a filled portion up to `verified_through_tick()`, the badge "Verified through mm:ss", and on `verify_failed` a banner "Replay diverged at mm:ss — recorded on a different build?". `UiNetPortNull` refuses commands. A player who surrendered gets the same observer mode but keeps their own perspective as the default.

#### 5.16.4 End screen (`UiScreenEnd`)

Banner: **VICTORY** (OK) / **DEFEAT** (DANGER) / **DRAW** / **MATCH ENDED** (observer). Tabs: **Summary** (per-player table: colour bar, emblem, name, roster, team, result, score, time alive), **Military** (units built/lost/killed, structures built/lost/destroyed, damage dealt/taken, value destroyed), **Economy** (harvested, spent, income graph), **Graphs** (lines from `series`, one per player in the team colour with the player's pip shape at the line end in every mode (the second channel of 5.19.3), x = time, y = metric switchable). Buttons: **Play again** (LOCAL: back to the lobby with the same state; LAN host: `host_return_to_lobby`; LAN client: wait for `RETURN_TO_LOBBY`), **Watch replay** (autosave_1 through the replay pipeline), **Save replay** (`UiDlgSaveReplay`: name → `NetReplay.save_copy`), **Main menu**.

#### 5.16.5 Score (`UiScore`, integer, presentation only)

```
military   = value_destroyed / 10
economy    = harvested / 20
technology = 100 * research_done + 50 * powers_used + 250 * (1 if sw_launched > 0 else 0)
score      = military + economy + technology
apm        = commands * 60 / max(1, duration_ticks / 20)           # integer division
```
Worked: `value_destroyed = 42,000`, `harvested = 60,000`, `research_done = 3`, `powers_used = 4`, one superweapon → `4,200 + 3,000 + (300 + 200 + 250) = 7,950`; 1,800 commands in a 1,500 s match → `apm = 1800 × 60 / 1500 = 72`. The formula never feeds back into the sim.

#### 5.16.6 Replay browser (`UiScreenReplays`)

Rows come from `NetReplay.list_replays()` (metadata only: header + trailer): DATE (`mtime`, local), MAP (`UiMapNames.name_for` + family/size), PLAYERS (emblem + name, winning team starred), LENGTH (`duration_ticks / 20` as `mm:ss`), BUILD (`OK` when `versions.sim` and `data_hash` equal the local ones, else dimmed `OLD BUILD` — playback would refuse), SIZE. Special entries: `autosave_1..3` labelled **Last match** (newest first), `crash_*` labelled **Recovered (truncated)**. Default sort newest first; filters: text, hide autosaves, hide incompatible; empty state "No replays yet — every match is recorded automatically". Detail pane: rosters and colours, seed as 8 hex digits, rules chips, duration, `finalized` flag. Actions: **Watch** (double click; perspective chooser "All players / player N"), **Verify** (`NetReplayPlayer.verify_file` time-sliced with a progress bar, result badge `OK` or `DIVERGED at mm:ss`), **Save copy / Rename** (`NetReplay.save_copy`, name sanitised by net), **Delete** (confirm; `NetReplay.delete_replay`, only `*.mfreplay` inside the replay directory), **Open folder** (`OS.shell_open`). Metadata reads are progressive: the list appears immediately and rows fill in as files are read (≤ 150 ms for 200 files).

#### 5.16.7 Credits (`UiScreenCredits`)

Auto-scrolls at 40 logical px/s over the vignette backdrop, pauses while hovered, click / Esc leaves; `reduce_motion` shows static pages instead. A **Licenses** button (and every credits entry whose `link` starts with `licenses:`) opens the Licenses screen: the engine block from `Engine.get_license_text()`, `Engine.get_license_info()` and `Engine.get_copyright_info()` (always the shipped build's own text), then one entry per component of `LICENSES/THIRD_PARTY.json` (`name`, `version`, `spdx`, `copyright`, `url`, `used_for`, and the text of its `licence_file`, e.g. `LICENSES/fonts/OFL_rajdhani.txt`). `credits.json` follows the QA schema (7.3).

---

### 5.17 Field Manual (`UiScreenFieldManual`)

* **Entry points:** main menu; lobby briefing (click a unit/structure/power → `focus_id`); Esc menu and `F1` in a match (push, the match keeps running; LOCAL pauses if `pause_on_menu`). Default roster = the local roster (`game/last_roster` from menus); a roster picker (faction + subfaction dropdowns, all 32) at the top changes it. Data comes only from `UiFmModel` → `DefBrowser` (`data_balance.md` §3.10); the screen never touches JSON.
* **Layout (REGULAR/LARGE):** left navigation (roster picker; categories **Overview · Units · Structures · Research · Powers · Tech tree · Compare**; search box), middle list (`UiListRow`: icon, name, tier pips, cost), right detail card with the turntable viewer on top. COMPACT: drill-down (list → detail).
* **Detail card (unit):** header (name, class, tier, `role_text`), **cost / build time / health / speed / water speed / sight** as the card's resolved values with a delta marker when they differ from the card's `base.*` block (`▲ +10 %` good/bad by `UiFormat.delta_class`, tooltip `"Base 1,500 → 1,650: Land combat vehicles cost +10 % (NAPC parent, layer 1)"`), **(at floor)** when a value sits on a bible floor (cost / build time 60 %, reload 50 %), **\*** when the effect is conditional (tooltip lists the condition: "on water only", "in a civilian garrison", "paid repairs"); armor class, movement class, layers; producer and `requires` as clickable chips (open the structure card); "Replaces … / Replaced by …" (subfaction uniques get the UNIQUE badge); weapons table (name, damage, DPS from `DefBrowser`, range, min range, reload, burst, damage type, targets, splash, suppressive); abilities (kind + summary); modifiers list (source text, stat, delta, layer); strong-vs / weak-vs; counter suggestions (the card's `counters`).
* **Structures** show cost, build time, **power delta**, prerequisites, what they produce/unlock, footprint and placement flags (shoreline, "max one strategic", "does not extend build radius"). **Research** shows cost, 45/75 s, effect text, prerequisites. **Powers/superweapon** show cost, cooldown or recharge/warning, targeting rule ("any location" / "needs current vision" / "explored terrain"), effect and counterplay text (bible).
* **Compare:** two roster pickers; `DefBrowser.compare_rosters` → columns *Only in A*, *Only in B*, *Replaced*, *Modifier differences*, each row clickable.
* **Tech tree (`UiFmTechTree`):** nodes = structures (≤ 29) + producers' units grouped under them; layered DAG layout: `depth(n) = 1 + max(depth(requirement))` (HQ = 0), column `x = depth × 220`, rows ordered by the barycentre of predecessors then by index (one pass), node 180 x 44, straight or elbow edges; pan by drag, zoom by wheel; nodes owned in the current match are highlighted when opened in-game.
* **Live values:** in a match a toggle *Include completed research* re-reads stats through `DefLayer3.effective_unit_stat` (badge LIVE); off by default in menus.
* **Model viewer (`UiModelViewer`):** `SubViewport` + `view.make_model_node(def_id, roster_id, team_index)`; turntable 20°/s, drag rotates, wheel zooms, `UPDATE_WHEN_VISIBLE`; below the Low preset or when `reduce_motion` it shows the baked icon instead.
* **Search:** debounced 150 ms → `DefBrowser.search(text, 20)`; results grouped by kind; Enter opens the first.

---

### 5.18 Options

#### 5.18.1 Pages

| Page | Content |
|---|---|
| Graphics | info line (adapter name / type / API version, rendering method and driver — `RenderingServer.get_video_adapter_*`, `get_current_rendering_method/driver_name`); **Preset** dropdown (Low / Medium / High / Ultra / Auto; shows "Custom (based on High)" when overrides exist); window mode; resolution (windowed only); vsync; FPS cap; background FPS; *Advanced* foldout with the keys of 4.7.2 (render scale, scaling mode, MSAA, FXAA, shadows, SSAO, SSIL, glow, decor density, health bars, unit outline, unit backend, night maps, wide view); **Renderer** dropdown with an *Apply and restart* button (`AppRelaunch`). Rows the running renderer or driver cannot honour are disabled with a tooltip ("Forward+ only", "Metal only") — guarded by capability, never by OS name |
| Audio | Master / Music / SFX / Ambience / UI / Voice sliders (0-100); announcer (faction / computer / off); unit responses (bleeps / voices / mixed / off); music (dynamic / calm only / off); dynamic range (full / night); audio quality; mute when unfocused; output device; captions (spoken lines as text) — the rows are `SndSettings` fields (`audio.md` §4.5) |
| Controls | keybind table by category with filter box, per-action ↺ and "Reset all" (every in-game action is rebindable with conflict handling, A-05); camera (key scroll, rotate, zoom speed, invert zoom / orbit, orbit hold / toggle); pointer (double-click time, drag threshold); behaviour (cursor confinement, sticky modes, group double-tap, Esc clears selection, pause on menu, pause on focus loss, sidebar hover hotkeys); orders (movement speed match, vehicles reverse on short moves — `input/move_speed_match`, `input/move_reverse`) |
| Interface | UI scale (text size, 75-200 % with the effective value shown), tooltips + delay, sidebar side, minimap sweep, selection brackets, range rings, camera pad, strategic-zoom markers, chat fade / opacity, FPS counter, cursor style |
| Accessibility | colour mode (normal / colour-vision safe, with a live swatch preview of the 8 team colours in both sets), high-contrast HUD, reduce motion, reduce flashes, UI font (default / dyslexia-friendly), system announcer voice (text-to-speech toggle), cursor size, edge scroll on / off + speed |
| Network | player name, port, discovery on / off, minimum input delay, auto-drop, replay autosave count, record chat, net overlay, "Show the network help again" |
| Storage | sizes of logs, crash reports, replays, screenshots and caches (`DirAccess` walk, cached for 5 s) with *Open folder* buttons (`OS.shell_open`) and *Clear caches*; a warning line above 1 GB in total (`qa.md` §5.12) |
| Language | English only (dropdown shows one entry, disabled) |

#### 5.18.2 First-run and Auto quality

The first-run default is `UiViewPort.quality_recommend()` = `ViewQuality.recommend()` (`render.md` §5.12: adapter type and renderer, never the adapter name or the OS name), shown with the adapter name in the first-run dialog (5.2.2). Choosing **Auto** (`quality = 4`) lets `ViewQualityAuto` step the preset down after two bad 3-second windows and up after ten good ones (never above the player's cap, at most once per 30 s); each step reaches the UI as `quality_auto_changed(preset, reason)` and becomes a toast with an *Undo* button that pins the previous preset.

#### 5.18.3 Apply semantics

Every change applies **immediately** (live preview) and is persisted after 0.5 s. Window mode, resolution and vsync changes open a **15-second "Keep these settings?" countdown** (a wrong resolution must not lock a player out; QA A-12 asks for no prompt shorter than 5 s, this one is 15 s and answers itself by reverting); no answer reverts. A page has *Reset to defaults*; Back flushes. Choosing a preset removes every quality override from `[video]` and stores `quality`; touching an advanced row stores that one key, so the dropdown reads "Custom (based on …)". UI scale changes re-run `UiLayout.apply` and re-register the cursors (no theme rebuild).

#### 5.18.4 Capability guards (`AppSettingsSchema.guard_ok`)

| Guard | Predicate |
|---|---|
| `forward_plus` | `RenderingServer.get_current_rendering_method() == "forward_plus"` |
| `not_compat` | method != `"gl_compatibility"` |
| `fsr2` | `forward_plus` |
| `metalfx` | `RenderingServer.get_current_rendering_driver_name() == "metal"` ∧ method != compat (the view's rule, `render.md` §4.9; if the engine rejects the mode the setting falls back to bilinear and `Log.warn`s) |
| `windowed_only` | window mode == 0 |
| `tts` | `DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)` ∧ at least one voice for `"en"` (= `SndAnnouncer.tts_available()`) |
| `renderer_switch` | `AppRelaunch.supported()` |
| `font_dyslexia` | the dyslexia-friendly font files are vendored (`assets/fonts/atkinson_hyperlegible/`) |

#### 5.18.5 Audio mapping

The app never touches `AudioServer` buses. `AppApply.apply_audio` builds a `SndSettings` (`SndSettings.load_from(cfg)` over a `ConfigFile` made of the store's `[audio]` and `[access] announcer_tts` values, so the defaults and the names are audio's) and calls `Snd.apply_settings(s)` through `AppAudio`; audio ramps every change (`SndBusFader`), maps the slider with `(v/100)²` (v = 0 → mute; Music at 70 → 0.49 → −6.2 dB on top of the bus default, `audio.md` §4.5), selects the output device (falling back to `"Default"` when the saved device is gone), mutes on focus loss when `audio/mute_unfocused` is set, and owns the announcer / unit-response / music modes. `Snd.apply_settings` must not write `settings.cfg` (single writer, 5.20.1; request `[XR-35]`). The options sliders call `Snd.ui(&"snd.ui.slider_tick")` at most every 0.1 s while dragging so the player hears the effect of the bus being edited.

---

### 5.19 Design system, accessibility and widget performance rules

#### 5.19.1 Style recipes (`style.ui.chrome`; the values below are the shipped ones — `art_direction.md` §5.12.4 took them from the spike — skin `s`, tint blends are `Color.lerp`)

`UiSkinSet` reads `ViewStyle.chrome()` once and hands it to `UiTheme.build` (`skin.chrome`); a key the JSON lacks falls back to the value in this table, and test U-1 asserts that the two agree today. Bracket arms are **12 px** (art; the spike's default was 20 px — the JSON wins).

| Recipe | Fill top → bottom | Border | Cuts (TL, TR, BR, BL) | Other |
|---|---|---|---|---|
| Panel | `BG_RAISED.lerp(s.tint, 0.55)` α 0.94 → `BG_PANEL.lerp(s.tint, 0.25)` α 0.96 | `LINE`, 1 px | (10, 0, 10, 0) | accent brackets TL + BR (12 px, 2 px), padding 12/10/12/10, highlight α 0.06 |
| Sidebar | as Panel, α 0.97 | `LINE` | (0, 0, 0, 18) | bracket BL, padding 14/12/14/12 |
| Ribbon panel | as Panel, α 0.92 | `LINE` | (12, 12, 12, 12) | no brackets, padding 20/6 |
| Inset | `BG_DEEP.lerp(tint, 0.2)` → `BG_PANEL.lerp(tint, 0.1)` | `LINE_DIM` | (4, 0, 4, 0) | padding 8/6, no highlight |
| Button normal | `#1f2c3c` → `#141e2b` | `LINE` | (6, 0, 6, 0) | padding 14/6 |
| Button hover | `#2a3f57` → `#1a2a3c` | `s.accent` | same | glow `s.accent` α 0.22 |
| Button pressed | `#0d141c` → `#182638` | `s.accent` | same | no highlight |
| Button disabled | `#0f151c` → `#0c1218` | `LINE_DIM` | same | text `TEXT_DISABLED` |
| Primary (accent) | `accent.lightened(0.12)` → `accent.darkened(0.42)` | `accent.lightened(0.35)` | (8, 0, 8, 0) | hover +0.15 lightness and glow α 0.35; pressed top = old bottom, bottom = `accent.darkened(0.6)`; text `#10161d` (4.66 : 1 on the raw DEF accent, the worst skin, 10.28 on AE; art measures ≥ 5.4 : 1 on the lit half of the gradient) |
| Hero (menu) | Button colours, fill α 0.78 | | (12, 0, 12, 0) | Orbitron 20, padding 28/12 |
| Bars | background inset (cut 3); fill `accent.lightened(0.25)` → `accent.darkened(0.35)` | | | scrollbars: padding 3, track black 35 %, grabber `accent.darkened(0.35)` |
| Tooltip | Panel α 0.98 | | (8, 0, 8, 0) | bracket TL only, glow black α 0.5, padding 12/8 |
| Popup / dropdown | Panel α 0.98 | | (6, 0, 6, 0) | no brackets, padding 6; item hover fill `accent` α 0.28 → 0.14, border `accent` α 0.7 |
| Focus (menus only) | transparent | `s.accent`, 2 px | as the control | glow α 0.2 |

Everything sits on a 4-px grid; `access/reduce_motion` turns the pulses into static highlights (4.6.5). Under `access/high_contrast_hud` the normal-state borders become `LINE_BRIGHT` and the panel alphas 1.0 (5.19.4).

#### 5.19.2 Faction skins (`style.ui.skins`, `art_direction.md` §5.12.5; `UiSkin.from_style(style, code)`)

| Code | Bible visual direction | accent | accent2 | tint | contrast on `BG_PANEL` (accent / accent2, art) |
|---|---|---|---|---|---|
| napc | Olive, cream and rescue orange | `#f07f2c` | `#c9d27a` | `#2a2f16` | 7.1 / 11.8 |
| nec | Slate blue, white and amber | `#5b93e0` | `#ffb733` | `#14243d` | 6.1 / 11.0 |
| olm | Ivory, copper and deep teal | `#2fc9bb` | `#d9803f` | `#0f2b2c` | 9.3 / 6.5 |
| def | Oxide red, gray and pale yellow | `#e0503a` | `#f0dc8c` | `#341612` | 4.9 / 13.9 |
| pd | Ocean blue, coral orange and white | `#33a0ec` | `#ff7f5c` | `#0f2740` | 6.7 / 7.7 |
| han | Jade green, crimson and porcelain | `#33c98a` | `#e0424f` | `#0f2f22` | 9.0 / 4.6 |
| ae | Ochre, charcoal and bright cyan | `#26d6e8` | `#e0aa3c` | `#11292d` | 10.8 / 9.1 |
| sap | Sand, indigo and saffron | `#f3a622` | `#7a72e6` | `#2c2412` | 9.4 / 4.9 |
| neutral (splash, fatal; the UI's own) | — | `#7fb0e6` | `#ffd35c` | `#141c26` | — |

`accent` = borders on hover, tab underline, progress fill, headings and focus rings; `accent2` = badges and small ticks; `tint` = the dark colour mixed into the panel gradients. The skin is per **faction**: subfactions use their parent's skin and show their sub glyph in the header (`UiEmblem.draw_badge`, `sub_glyph_ops`). `accent2` drops to 4.2 (HAN) and 4.5 (SAP) on `BG_RAISED`: never for body text on raised panels. The similar accents (NEC / PD blue, OLM / AE cyan-teal, NAPC / SAP orange-amber) are separated by the tint, the emblem and the faction name in the header and never sit side by side in the HUD; in the lobby, emblems and names label them.

The theme in a match uses the **local** player's faction; menus use the last-used roster's faction; the lobby/briefing tints only the briefing widgets with the hovered faction (no theme rebuild on hover; local `Color` use). Observers and replays use the neutral skin.

#### 5.19.3 Team colours, colour modes and the numbers behind them (`UiSkinSet`, `UiA11y`)

**Source of truth.** The twelve player colours (`crimson 0 … white 11`, the lobby ids of `net.md`), the colour-vision-safe set and the seat order `assign_order` are `style.player_colors` (`art_direction.md` §5.4.1). The UI reads them only through `ViewStyle.player_color(id, cvd)`, `player_color_count(cvd)` (12 / 8), `default_color_for_slot(slot)` and `plate_contrast(faction, id, cvd)`; there is no UI copy (art R-21), so the lobby swatch, the minimap blip and the 3D team colour are the same colour. The colour **ids** are what travels over the network and into replays: `access/colour_mode` changes only the local rendering (swatches, blips, the view's team uniform) and which swatches the lobby offers (`cvd` has 8 colours; ids 8-11 have no variant — `player_color(id, true)` falls back to the default hex for them — and are not offered while `cvd` is active, though a peer may still have picked one).

**Modes.** `normal` and `cvd` (`UiSkinSet.ColourMode`). `cvd` selects art's single colour-vision-safe set — annealed under the Machado 2009 simulation of protan, deutan and tritan together (art §5.4.2: no per-type modes) — and the semantic set below. `UiViewPort.set_cvd_palette(on)` tells the view. The view's own vocabulary (`render.md` §3.8: `normal`, `protan`, `deutan`, `tritan`, `high_contrast`) predates art's set; `[XR-14]` replaces it with a boolean, and until then `AppApply.quality_config` writes `[access] colour_mode` as `normal` / `deutan` (the closest v1 name: one all-type set), `[access] cvd_palette` as a boolean for adopters of art R-1, and `[access] high_contrast_hud` as the separate boolean of QA-XR-13. The translation lives in one place, `AppApply.quality_config`.

**Evidence computed for this spec.** Metric = the one QA names for A-01 (`QaContrast.min_pairwise_delta_e`): sRGB → linear → Machado 2009 matrices (severity 1.0) → CIE Lab (D65) → **CIEDE2000** (the implementation reproduces the Sharma-Wu-Dalal reference pairs 2.0425 / 2.8615 / 4.3065 / 1.2644). Minimum pairwise ΔE2000 over ids 0-7:

| Set | normal | protan | deutan | tritan | source |
|---|---|---|---|---|---|
| art default (authored) | 22.6 | 8.5 | 9.0 | 8.7 | `art_direction.md` §5.4.1 |
| art CVD (authored) | 20.8 | 14.5 | 13.8 | 13.5 | `art_direction.md` §5.4.1 |
| UI proposal `P-default` | 26.1 | 17.8 | 17.8 | 17.8 | computed here (simulated annealing over CIE LCh, per-slot hue windows) |

`P-default` ids 0-7, in art's hue families (crimson, azure, emerald, amber, violet, cyan, orange, magenta): `AD0410 1E69C6 53AC7A DDF514 B892FD 65FDFA CD6D04 87386B`. Reading QA A-01 (≥ 20 normal and ≥ 12 under each simulation): art's **CVD** set passes; art's **default** set passes normal vision only. Two consistent resolutions, both in `[XR-49]` and risk R28: **(a) narrow A-01** to "the default set ≥ 20 normal; the CVD set ≥ 20 normal and ≥ 12 under each simulation" — no colour changes, art's plate-contrast tables stay valid, and the UI's job is to make the CVD set easy to find (first-run page, lobby hint, Options → Accessibility); **(b) adopt `P-default`** as the default set, which meets A-01 as written but changes the hues that art measured plates and lighting against. This spec recommends (a) and keeps (b) as a ready table swap. `test_ui_palettes` implements the check with a `mode` switch (`literal` | `narrow`) so that QA's decision is one constant.

**Second channels (never colour alone).** (1) Every colour index has a **pip shape** — the view's table `0 circle, 1 triangle, 2 square, 3 diamond, 4 cross, 5 hexagon, 6 star, 7 bar` (ids 8-15 repeat 0-7 with an outline, `art_direction.md` §5.4.2, `render.md` §5.12) — drawn by the view at the left end of its health bars and at the north point of its selection rings in **every** mode; the UI uses the same table on the lobby swatches, the scoreboard and graphs, and (mode `cvd`) the structure blips of the minimap. (2) The **player number 1-8** is shown next to every swatch, in the roster/observer strip and in the scoreboard. (3) Minimap blips are class-shaped (5.12). (4) The blip / entity hover tooltip names the owner. (5) Selection cues differ by relation (view).

**Lobby.** Swatch hex from `ViewStyle.player_color(id, cvd_active)`; the default colour of slot `n` is `default_color_for_slot(n)` (azure, crimson, emerald, amber, violet, cyan, orange, magenta — the two most distinct first), assigned by net's `NetLobby` (`[XR-49]`); `plate_contrast(faction, id, cvd) < 20` shows a one-line hint under the row ("low contrast on your faction — try {colour}", best free colour by ΔE) and the swatch keeps a small "!" chip; a swatch whose distance to a taken colour is below 12 in the active set gets the "similar" dot; Godot exposes no OS colour-vision flag, so the CVD set is offered by a fixed one-line hint under the swatch grid ("Colour-vision safe palette: Options → Accessibility") and on the first-run page (5.2.2).

**Semantic colours per mode** (A-16: the colour-vision mode recolours UI states too; art defines the `normal` tokens, this spec the `cvd` set):

| Mode | OK | WARN | DANGER | POWER | Min ΔE2000 of OK / WARN / DANGER (normal / deut / prot / trit) |
|---|---|---|---|---|---|
| `normal` (art tokens) | `#5ce383` | `#ffb52a` | `#ff5555` | `#49d0ff` | 38.3 / 11.4 / 10.7 / 20.6 — not relied upon: every semantic colour is paired with a glyph and a word (art §5.12.2) |
| `cvd` (`UiPalette.CVD_*`) | `#4DB8FF` | `#F5E663` | `#E8590C` | `#A8E6FF` | 44.9 / **21.9** / 32.0 / 33.3 |

Relation colours (SELF / ALLY / ENEMY / NEUTRAL) stay the view's and art's in both modes; their non-colour cues carry the meaning. Icons and text always accompany semantic colour (READY has a check glyph and the word, LOW POWER has the bolt glyph, DANGER ribbons have the hazard block, invalid placement has the ghost's hatch and a reason line). `UiTheme.colors() -> Dictionary` (token → `Color` per widget state) and `UiTheme.team_colors() -> PackedColorArray` (the colours of the active mode) expose the values to QA's audits (`[QA-XR-28]`).

#### 5.19.4 Accessibility rules (and how each item of QA's checklist `qa.md` §5.15 is met)

* **Contrast:** body text ≥ 4.5 : 1 on its panel (`TEXT` 16.3, `TEXT_DIM` 7.8, `TEXT_MUTE` 5.5 on `BG_PANEL`, 4.6 on `BG_CONTROL`; `TEXT_MUTE` is not used on `BG_HOVER`, 3.8); interactive control borders and UI graphics ≥ 3 : 1 (`LINE_BRIGHT` 4.28 on `BG_PANEL`; the normal button border `LINE` is decorative because the fill gradient and the label define the control); text on hover / pressed fills stays ≥ 9 : 1 (`TEXT` on `#2a3f57`); dark text on an accent fill ≥ 4.5 (4.66 minimum). **Disabled** text is `TEXT_DISABLED` 3.70 : 1: WCAG 1.4.3 exempts inactive components, so the audit checks it against the ≥ 3 : 1 graphics bound (question Q13 for QA). `test_ui_tokens` computes these ratios from `UiTheme.colors()` for every state (normal, hover, pressed, disabled, focus).
* **High contrast** (`access/high_contrast_hud`): panels α 1.0, no glow, borders `LINE_BRIGHT` 2 px, text `TEXT` only, `TEXT_MUTE` promoted to `TEXT_DIM`, custom cursors get a white outline; the world side (thicker rings, unit outlines — `video/unit_outline` is raised to at least bold —, larger health bars) is `UiViewPort.set_high_contrast` (`[XR-14]`).
* **Motion / flashes:** `access/reduce_motion` → all `UiMotion` durations 0, no sweep, no scanlines, no menu backdrop drift, static badges, camera smoothing off (`set_camera_smoothing(false)`), the view's shake at ×0.2; `access/reduce_flash` → pulses replaced by steady fills, the view's shake at 0, flash overlays off. No element pulses faster than 3 Hz in any mode (the alert pulse of READY cards, DANGER ribbons and low power is 1 Hz; nothing else animates faster than 2 Hz, art 5.12.4); the view limits impact flashes by area × luminance (its V-F02).
* **Keyboard:** every menu control is reachable with Tab / arrows / Enter / Esc (`UiFocusPolicy.apply_menu`), the focus ring is always visible, no keyboard trap (Esc always leaves); the HUD is mouse-first but every HUD action has a rebindable key (5.6.1) and every key has a HUD control (5.11.7).
* **Hit targets:** ≥ 32 logical px for everything clickable except badges (build cards 98 x 104, command buttons 48, tabs 38, menu buttons 54); icons and glyphs are never drawn below 16 px (art §5.12.7).
* **Screen readers (A-13):** `accessibility_name` / `accessibility_description` on every button, slider, list row and dialog (`UiA11y.name(control, key)`); `accessibility_live = polite` on the notification feed, the lobby chat and the loading status label; ProjectSettings `accessibility/general/accessibility_support` stays at its default (auto). The in-match RTS world view is documented as **not** screen-reader operable (menus, lobby, options, end screen, replays and the Field Manual are).
* **Text size:** the UI scale slider (75-200 %) is the text-size control (effective value shown when the 540-px logical floor limits it); no text below 14 logical px at 100 % (QA A-03, V-H02); the dyslexia-friendly font option (`access/ui_font`) swaps the BODY and BODY_BOLD roles for Atkinson Hyperlegible (OFL) with sizes unchanged, as `art_direction.md` §5.12.3 specifies (HEAD and NUM stay Orbitron / Share Tech Mono: short CAPS labels and numerals only); running text is sentence case.
* **Audio-only information:** every announcer line is mirrored as text in the feed when `audio/captions`, alerts also show a ribbon, a minimap ping and an off-screen edge arrow, and `access/announcer_tts` makes audio speak the announcer caption with the system voice (`DisplayServer.tts_speak`, off by default; the UI does not speak anything itself).

| QA item | Met by |
|---|---|
| A-01 team colours | 5.19.3: art's `cvd` set meets it, art's default set does not under simulation (R28, `[XR-49]`); pip shapes, player numbers, class-shaped blips with owner tooltips as the non-colour cues |
| A-02 contrast | this section, `test_ui_tokens` |
| A-03 text ≥ 14 px, scale 75-200 %, no overflow | 4.6.2, 5.4.1, `test_ui_lab_layout` (five window sizes × scales 1.0 / 1.5 / 2.0) |
| A-04 keyboard navigation | `UiFocusPolicy`, `test_ui_lab_menu_nav`, QA's focus-graph walk |
| A-05 rebinding | 5.6.2, options Controls page |
| A-06 mouse-only and keyboard-only | camera pad + Select menu (5.11.7), keys for every HUD action |
| A-07 no information by sound alone | 5.13 (ribbon, log, minimap ping, edge arrow, captions, TTS) |
| A-08 volume sliders, mute on focus loss | 5.18.5 |
| A-09 reduce motion | 5.5.5, 4.6.5, `access/reduce_motion` |
| A-10 photosensitivity | 1 Hz alert pulses (nothing faster than 2 Hz, art §5.12.4), `access/reduce_flash`, view limits |
| A-11 game speed, pause | lobby speed 50-200 %, LOCAL pause (5.16.2) |
| A-12 no timed prompt < 5 s | the 15 s settings revert answers itself; the host stall prompt is non-modal (5.16.2) |
| A-13 AccessKit | names / live regions above |
| A-14 optional TTS announcer | `access/announcer_tts` |
| A-15 high-contrast HUD | above, plus the view's rings / outlines / bars (`video/unit_outline`, `set_high_contrast`) |
| A-16 colour-blind presets recolour team palette and UI states | 5.19.3 (`cvd` recolours team colours, the semantic set and the structure blips) |
| A-17 dyslexia font, text size | `access/ui_font` (BODY roles), UI scale; CAPS only for headers and buttons |
| A-18 localisation-ready | `UiText`, `test_ui_lab_layout` runs the longest strings through `TranslationServer.pseudolocalize` (+40 %) |
| A-19 alternatives to drag | `sel_all_military_screen`, double-click / `T` same type, `sel_group_next` (5.6.1) |
| A-20 toggle vs hold | `input/orbit_mode`, `toggle_edge_scroll` |
| A-21 cursor size and contrast | `access/cursor_scale`, outline in high contrast |
| A-22 assist | AI level Easy, collectors auto-harvest (sim), placement reason text |
| A-23 tooltips for everything | 5.10.9 (a tooltip stays while hovered; toasts hold ≥ 4 s), Field Manual as glossary |

#### 5.19.5 Theme application and rebuild triggers

`UiThemeService.rebuild(skin)` runs on: entering a match (local faction skin), leaving it (last roster skin), colour mode, high-contrast toggle, font option. It calls `UiTheme.build` (0.27 ms warm, 5-9 ms first call), then assigns the theme to every `UiLayerRoot` (P1) and emits `theme_changed`; custom-drawn widgets connect once and `queue_redraw`. UI scale changes need no rebuild (fonts and vectors are resolution-independent) but re-register cursors. `default_font`/size are set on the theme (`FS_BODY = 15`), not through project settings.

#### 5.19.6 Widget performance rules (binding for UI-02/UI-08/UI-10)

1. Never `queue_redraw()` a styled panel every frame; animate only in leaf widgets that draw ≤ 20 primitives or in shader children (`UiCooldownSweep`).
2. Cache `UiStyleBox` instances per `(recipe, state, skin)` — no allocation inside `_draw` (fixes the spike's `UiRibbon`).
3. Custom-drawn rows (one canvas item per row) instead of one node per cell for any list ≥ 20 rows.
4. Per-frame text: one Control with `draw_string` (300 draws = 1.17 ms) instead of many `Label`s whose text changes every frame (300 Labels = 2.0 ms); redraw text once per displayed second.
5. `set_process(false)` whenever a widget is idle (ticker, power bar, ribbon without countdown).
6. Icons are baked at 2x (188 x 124 for a 94 x 62 slot) and drawn with `draw_texture_rect`, so UI scale up to 2 stays sharp.
7. `gl_compatibility` / `Low` preset sets `UiHud.lite`: no glow polylines, no scanlines/vignette, minimap 15 Hz, world overlay bars only for selected units (the spike measured 683 HUD draw calls and a CPU-bound GL-on-Metal path: 6.3 ms frame HUD-only).
8. Optional (UI-14): bake `UiStyleBox` to `StyleBoxTexture` 9-slice per (skin, recipe, state) — 0.15 ms vs 45.8 ms for 500 redraws; only if profiling shows style redraw ≥ 0.5 ms/frame in the 8-player scenario.

---

### 5.20 Settings persistence, logging, crash and recovery

File locations, retention and the report header follow `qa.md` §5.12 (QA owns the policy, this module implements it; `[QA-XR-12]`, `[QA-XR-13]`). `user://` resolves to `~/Library/Application Support/MeridianFracture/` on macOS, `$XDG_DATA_HOME/MeridianFracture/` (default `~/.local/share/MeridianFracture/`) on Linux and `%APPDATA%\MeridianFracture\` on Windows; the app never writes anywhere else and never beside the executable.

#### 5.20.1 `user://settings.cfg`

* **Load:** missing → try `settings.cfg.bak`, else defaults. Parse error → the file is renamed `settings.cfg.bad-<utc>`, then `.bak` is tried, else defaults; `load_notes` gets a line and a toast says "Settings were reset (the old file was kept as settings.cfg.bad-<utc>)". Values are coerced per schema (`clampi`/`clampf`/choice membership); invalid → default + note. `meta/version` greater than the build's → still loaded, unknown keys preserved read-only. Older → migration table (empty for v1). The saved window rectangle is **clamped to the screens that exist** (`DisplayServer.get_screen_count`, `screen_get_usable_rect`; QA X-13) and never restored to an unplugged monitor; window positioning is never *required* behaviour (Wayland cannot honour it, X-09).
* **Save (crash-safe without an atomic rename, `DirAccess.rename` is remove-then-rename):** (1) write `settings.cfg.tmp` completely and flush; (2) if `settings.cfg` exists, rename it to `settings.cfg.bak` (an older `.bak` is removed first); (3) rename `.tmp` to `settings.cfg`; (4) on load, a missing or unparsable `settings.cfg` with a parsable `.bak` loads the `.bak` and restores it. Only values that differ from the default are written (plus `meta/version`), in schema order, then unknown sections verbatim. The file layer is an injectable `AppFileLayer` so `test_app_settings_atomic_write` (QA) can interrupt the sequence after each step and assert that a valid file is always recoverable. Debounced 0.5 s after the last change; flushed on quit, on `NOTIFICATION_APPLICATION_FOCUS_OUT` and before a match starts. Failure (read-only profile, disk full) → in-memory operation, one toast, `Log.warn`.
* **Overrides** (`--ui-scale`, `--palette`, `--faction`) live in `AppSettings.set_overrides` and are never persisted. `--fresh-settings` = in-memory store; concurrent test processes use a per-process sandbox (`gd --sandbox`, `[QA-XR-2]`) so two writers never share one `user://settings.cfg`.

#### 5.20.2 Logging (`AppLogger` + the `Log` sink, E2)

* **One log, the engine's.** Exports enable `debug/file_logging/enable_file_logging.standalone=true` and `max_log_files=10` (`[QA-XR-6]`, request `[XR-40]`), so `user://logs/godot.log` (rotated by the engine to `godot<timestamp>.log`) holds engine and game lines in order; this module rotates nothing itself. Net writes its own `logs/net*.log`.
* **Game lines** go through core's `Log.debug/info/warn/error(tag, msg)` (`sim_core.md` §3.2.6; QA's older `Log.t/d/i/w/e` spelling is the same API); at the first boot step the app installs `Log.sink` (`[QA-XR-23]`): `AppLogSink` formats `[E|W|I|D] <ms since start> [tag] message`, applies the rate limit of 20 lines per second per tag with a "(+N suppressed)" counter and prints the line — the one place in `src/app` that calls `print`, marked `# lint-allow: L006 app log sink`. `Log.ring` (256 lines, core) keeps the recent lines for crash reports. INFO by default, DEBUG only in debug builds; nothing logs per tick.
* **`AppLogger`** (`Logger` subclass, `OS.add_logger` at the first boot step): `_log_error` / `_log_message` may run on any thread → every entry point takes a `Mutex`; it mirrors engine errors and warnings into `Log.ring` and an error counter, uses `script_backtraces[0].format()` as the location when the array is non-empty (release builds have no backtraces and it must tolerate an empty array), **never prints inside `_log_error`** (re-entry), ignores `_log_message` lines that carry the app's own prefix, and hands UI callbacks to the main thread with `call_deferred`.
* **Rate limiting of errors:** identical `(type, file, line, code)` entries are recorded the first time, then every 100th with `(×N)`. **Error storm:** ≥ 50 errors within 5 s sets `storm()`; the UI shows one toast ("Many errors are occurring — the log has details") and, in a match, a hint to leave and save; it is never fatal by itself. Script errors (type 2) toast at most once per 30 s per location (always in debug builds).
* **Budget:** `godot.log` stays under 5 MB per hour of play (QA endurance run; a violation is severity S2) — the sink's rate limit is what guarantees it. No telemetry, no network traffic except LAN discovery and play (proposed lint L012); crash reports are never uploaded.

#### 5.20.3 Session sentinel, crash reports and retention

* `user://.session` = `{"pid":4242,"start_utc":"2026-09-29T14:03:11Z","version":"0.1.0"}` is written after the settings load (skipped in test modes) and deleted by `AppState.quit_game()` and on `NOTIFICATION_WM_CLOSE_REQUEST`.
* **`AppCrashReporter`** handles `NOTIFICATION_CRASH` (2012) best-effort: it writes `user://logs/crash/crash_<utc>.txt` (report header + the `Log.ring` tail). At the next start a leftover `.session` with another pid yields `crash_<utc>_unclean.txt` (header of the recorded session plus the tail of the previous engine log, i.e. the newest `godot*.log` that is not the current one) and a **non-blocking toast** "The game did not close properly last time" with actions *Open logs folder* (`OS.shell_open`) and *Copy report* (`DisplayServer.clipboard_set`); if `NetReplay.recover_orphans()` renamed `_recording.mfreplay.tmp` to `crash_<unix>.mfreplay` the toast adds *Watch recovered replay* (playable though truncated). `project.godot` sets `debug/settings/crash_handler/message` to "Meridian Fracture crashed. A report was saved in the logs folder; please attach it when reporting."
* **Report header** (all fields required, test `test_app_crash_report_fields`): game version + build id, Godot version, OS + version, architecture, CPU name and cores, RAM, GPU adapter name / vendor / type / API version, rendering method and driver, display server, screen size / scale / refresh, locale, `user://` path, uptime, phase (menu / lobby / match), match summary (rosters, map family / size / seed), sim tick and last checksum, net role. **Never** other peers' IP addresses or chat text.
* **Retention:** crash reports newest 20, autosave replays 3 (`net/replay_autosave_count`), desync packages newest 10 (net), screenshots unlimited (the Storage page shows the size), a warning above 1 GB in total; screenshots go to `user://screenshots/<utc>.png`.

#### 5.20.4 Fatal screen (`UiScreenFatal`)

Reasons `AppCrash.Reason`: `DATA_LOAD_FAILED` (detail = `GameData.last_report.text()`), `WORLD_BUILD_FAILED` (detail from `job.error()`), `ERROR_STORM` during load-critical work, `NET_FATAL`, `RENDERER`, `DISK`. Layout: title, one plain-language sentence, monospace scroll box with the technical report (the header of 5.20.3, the reason and detail, settings digest, the last 60 `Log.ring` lines), buttons **Copy report** (`DisplayServer.clipboard_set`), **Open logs folder** (`OS.shell_open`), **Retry** (only for `WORLD_BUILD_FAILED` / `NET_FATAL`, returns to the menu), **Quit**. The screen uses the neutral skin and needs only fonts and the theme, so it works even when `GameData` failed; the same report is written to `logs/crash/` as `crash_<utc>_fatal.txt`.

---

### 5.21 How the bible rules in this domain are honoured

| Bible rule | UI/app behaviour |
|---|---|
| `roster_selection` — 32 atomic rosters, no mixing | one faction + one subfaction dropdown pair, tokens for random (5.14.3); briefing shows the delta vs vanilla; no per-unit picking |
| `economy` — credits only; power is a capacity budget; 7,500 preset; medium speed; no veterancy | credits ticker + separate power bar; rules panel defaults 7,500 / Medium 100 % / veterancy off; vet chevrons hidden unless `RF_VETERANCY` |
| `technology` — Radar → T2, Radar + Laboratory → T3, producer always required, land-only playable | locked cards show the missing prerequisite names (`requires_text`); no Dock hint on land tabs; Naval tab locked with "Needs Dock" only |
| `production` — independent queues per Barracks/Factory/Airfield/Dock; one player-wide research queue and one construction queue; replaced units cannot be built | producer routing (5.10.3) + queue strip per producer; separate construction/research states; replaced units absent from tabs and shown as "replaced by" in the Field Manual |
| `research` — 45 s (T2) / 75 s (T3); losing a prerequisite pauses dependent orders | card states BLOCKED (auto-pause) vs ON_HOLD (user); times from the resolved defs; completed upgrades stay (DONE) |
| `power_loss` — 50 % production/research, powered defenses and Relay bonuses stop, powered powers cannot activate, superweapon recharge pauses | LOW POWER ribbon + flashing bar; ETAs use `rate_pct`; structure panel shows OFFLINE; powers BLOCKED ("Radar offline: low power"); superweapon sweep freezes with "POWER" |
| `scope_of_modifiers` / `how_percentages_combine` / caps and floors | the UI never computes stats; it shows `DefBrowser` resolved values, base values on hover, floor markers "(at floor)" for the 60 % / 50 % rules, and cap notes |
| `support_power_access` — 3 powers per roster, ready when unlocked, cooldowns never reset by rebuilding prerequisites | POWERS tab/dock has exactly the roster's 3 + superweapon; cooldown state comes only from the sim |
| `targeting_and_warnings` — recon powers anywhere, others need current vision, superweapons explored terrain, warning zones visible to affected players and not hideable by fog or decoys | 5.9 targeting validity; strategic-warning overlay and ribbons for every affected player (the `strategic_warnings()` query decides, never fog) |
| `superweapon_control` — starts empty, one charge, launcher destroyed/EMP'd during warning cancels without refund | LOCKED → CHARGING → READY states; `sw_cancelled` notice; no stockpile UI |
| `damage_and_area_notation` — one cell = one tile; radius from the marked centre; friendly fire | ranges/radii in cells everywhere; friendly-fire ring on damage-bearing previews |
| `concealment` — detectors reveal within 5 cells | selected detectors draw a detection ring (`CAP_DETECTOR`); CAMOUFLAGED chip on units |
| `suppression` — 3 hits in 2 s slow infantry 25 % | SUPPRESSED chip + tile pip |
| `transports_aircraft_repairs` — capacities 2/3/4, aircraft need powered pads | cargo `n / cap` on transports; ammo/sortie state on aircraft cards; LOAD/UNLOAD in the resolver/ability bar |
| `submarines_and_wrecks` — subs targetable only by ASW when detected; only AE salvages wrecks | resolver rules 11/12 use layer hit caps; SALVAGE cursor only for `CAP_SALVAGE` |
| `role_tags` | `select all military` = tag `combat` minus `service`; caps derive from tags |
| `prototype_priorities` — three map families, ≥ 2 exits, no mandatory water | map panel families + static note; no roster–map coupling |
| Structure descriptions — HQ 8-cell build radius, Relay does not extend it, shoreline placement, max one strategic | placement rings from `build_radius_centers`, `place_reason` texts 3/4 |

---

### 5.22 Engine pitfalls checklist (binding; P1-P8 are the spike's, P9-P16 were measured for this spec, the rest are documented engine behaviour)

| # | Pitfall | Mitigation |
|---|---|---|
| P1 | `Window.theme` is not inherited by Controls below a `CanvasLayer` | assign `theme` on the first Control under each layer (`UiLayerRoot`) |
| P2 | `set_anchors_preset(FULL_RECT)` on a code-built Control under a `CanvasLayer` left size (0,0) | always `set_anchors_and_offsets_preset` |
| P3 | `TextServer.name_to_tag` is not static | `TextServerManager.get_primary_interface().name_to_tag("wght")` |
| P4 | `draw_multiline_colors` wants one colour per segment; `draw_polygon` has no AA parameter; `msaa_2d` warns on gl_compatibility | one colour per segment; AA border polyline; guard `msaa_2d` by renderer |
| P5 | `OptionButton.fit_to_longest_item` defaults true; bitmap theme icons blur when scaled | set false; vector or 2x icons |
| P6 | `--headless` root window is 64 x 64; `SubViewport` has no `get_viewport_rect()` | layout/input tests run inside a sized `SubViewport`; `get_visible_rect()` |
| P7 | class-reference XML descriptions are stripped | verify behaviour empirically; record in tests |
| P8 | Metal: `RENDER_TEXTURE_MEM_USED` underflows, GPU timers read 0, frames pinned to display Hz | measure CPU only; never trust GPU counters on Metal |
| P9 | (E1) autoload `_ready` has not run in `--script` runners; a script naming an autoload cannot compile before registration | pure `class_name` logic classes; lazy init in `_init`; runner-safe accessors |
| P10 | (E2) `Logger` callbacks arrive on any thread; `push_error` reports the engine location | `Mutex`; use `script_backtraces[0]` for the real location |
| P11 | (E3) replacing a cursor image costs 0.4-1.3 ms | register once per shape slot; switch with `set_default_cursor_shape` (1 µs) |
| P12 | (E4) loose action matching fires `Ctrl+1` for `1` and `Shift+S` for `S` | `exact_match = true` everywhere for keyboard actions, including polled ones |
| P13 | macOS reports Ctrl+click as right click (engine backend, unverified here) | per-OS gesture modifiers (5.5.6); no Alt gestures |
| P14 | `InputEventMouseButton.double_click` is set on presses only and absent on synthetic events | own double-click detector |
| P15 | key labels are platform strings ("Option") | `OS.get_keycode_string`; never hard-code "Alt" in UI text |
| P16 | `is_command_or_control_pressed()` is Cmd on macOS | use it only where "the platform command key" is meant (selection tile), never for gameplay chords |
| P17 | `ConfigFile.save` is not atomic; Windows cannot rename over an existing file | tmp + remove + rename |
| P18 | `Window.size` is in pixels; `content_scale_factor` scales UI only | 5.4.1; no `screen_scale` term |
| P19 | custom cursor size on HiDPI displays (points vs pixels) unknown | `access/cursor_scale` setting, system cursor fallback |
| P20 | Tab / arrows / Space are consumed by focused Controls and `ui_focus_next` | HUD `FOCUS_NONE`; `ui_focus_*` freed only in GAME context |
| P21 | a `LineEdit` keeps focus after Enter and swallows gameplay keys | `release_focus()` after submit/cancel |
| P22 | wheel over STOP panels leaks to the camera | `mouse_force_pass_scroll_events = false` |
| P23 | 300 Labels changing per frame cost 2.0 ms | one `draw_string` Control |
| P24 | `Tween`s made from nodes outside the tree do nothing | create tweens from in-tree nodes (`UiMotion` takes a node) |
| P25 | Forward+-only features (TAA, SSAO, volumetric fog) silently no-op elsewhere | capability guards (5.18.4) |
| P26 | scripted `StyleBox._draw` redrawn per frame is expensive (91 µs each) | 5.19.6 rule 1-2 |
| P27 | first 3D bake stalls 2.6-2.8 s on a cold Metal pipeline cache (1.5 s GL) | prewarm behind the splash/loading screen |
| P28 | Godot's `Ctrl+Tab` and `Tab` navigation inside `LineEdit`/popups | `sel_subgroup_next` only in GAME context |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

The UI **produces** sim commands (int arrays built by `UiCmdCodec` with the sim's `SimCmd` builders) and **consumes** sim events (10-int records decoded through `UiEv`) and `NetSession` signals. It defines no sim state. **Authority:** op codes, field layouts, queue modes, error codes and event codes are those of `sim_core.md` v2.1 (§6.1 commands and their `SimCmd` builders, §6.2 registry, §4.1 enums) and of the combat / abilities / economy blocks it adopts; this section is the UI's *usage* of them. Because v2 took the domain numbering as primary there is no alias column for commands; for events the last column of 6.2.1 gives the v1 name that `audio.md` and `render.md` still quote. If the reconcilers change the catalog, only `ui_cmd_codec.gd`, `ui_ev.gd` and the `UiSimPortWorld` adapter change (`[XR-1]`, `[XR-5]`).

### 6.1 Commands the UI produces (`UiCmdCodec`)

Conventions (`sim_core.md` §4.8, §5.5): a command is `[op, f_0 … f_(k−1), id_0 … id_(n−1)]`, all int32, with **no pid** (net stamps it from the connection); the id list exists only for ops flagged M_IDS (n ≤ 512, ascending, unique, > 0 — the `SimCmd` builder sorts and de-duplicates); `x, y` are sub-cell units for ops flagged P and whole cells for the one op flagged C (`BUILD_PLACE`); `mode` on unit orders is the queue mode (`QM_REPLACE 0`, `QM_APPEND 1` = Shift or the `W` latch, `QM_FRONT 2` never used by the UI); `target ≤ 0` means "none" (except `SET_RALLY`); fields an op does not carry are not sent and flag bits not listed must be 0. The kernel silently drops actors that are gone, inside a container or not the sender's and answers `NO_ACTORS` only if none remain, so a partly stale selection still works. **Never built by the UI:** `RESIGN` (surrender is `NetSession.surrender()`, departures are injected by the host) and `DEBUG` (a dev console outside this module, disabled in multiplayer).

| Code | `SimCmd` builder | Wire fields (then ids) | Produced by |
|---|---|---|---|
| 1 | `move` | `x, y, mode, flags` (flags: b1 speed-match / b2 reverse-ok from the two settings, else 0; b0 never) | rules 14-16, armed MOVE `M`, minimap RMB |
| 2 | `stop` | – | `S`, command bar |
| 3 | `scatter` | – | `X`, command bar |
| 4 | `patrol` | `x, y, mode, flags` (Shift chains legs; always cyclic; flags as `move`) | armed `P` |
| 5 | `load` | `target, mode` (ids = passengers, target = transport) | rule 4 |
| 6 | `garrison` | `target, mode` | rule 3 |
| 7 | `capture` | `target, mode` | rule 2 |
| 8 | `repair` | `target, mode` | rules 5-6 |
| 9 | `salvage` | `target, mode` (target = wreck) | rule 7 |
| 10 | `harvest` | `target, x, y, mode` (v2.1: the UI sends `target = 0` and the deposit cell's centre — the sim takes the deposit cell nearest to (x, y)) | rule 8 |
| 11 | `return_cargo` | `target, mode` (target = refinery, 0 = nearest) | rule 9, `V` on collectors |
| 12 | `follow` | `target, mode` (target = an own or allied unit) | armed `Ctrl+F` |
| 40 | `attack` | `target, mode, flags` (bit0 = forced: target is own / allied / neutral) | rules 11 and 1 |
| 41 | `attack_move` | `x, y, mode, flags` (flags as `move`) | armed `A`, rule 11 for a remembered ghost |
| 42 | `guard` | `target, x, y, mode` (target 0 = guard that point) | armed `G` |
| 43 | `hold` | – | `H`, command bar (hold position) |
| 44 | `force_fire` | `target, x, y, count` (target 0 = ground point; count 0 = until replaced; no queue mode) | rule 1 on ground / wreck / deposit, armed `Y` |
| 45 | `set_stance` | `mode` (0 aggressive · 1 defensive · 2 hold fire · 3 guard) | `Z` cycle, stance button |
| 46 | `scuttle` | – | `Ctrl+Delete` + confirm |
| 47 | `return_to_base` | `target, mode` (target = the clicked airfield / carrier id, 0 = nearest free pad or the carrier) | rule 10, `V` on aircraft / drones (target 0) |
| 100 | `deploy` | `def` (ability slot, −1 = the unit's deploy ability; an MCV becomes `T_DEPLOY_MCV`) | `D` on units that are not deployed |
| 101 | `undeploy` | `def` (slot) | `D` on units with `F_DEPLOYED` |
| 102 | `set_mode` | `def, mode` (slot, target mode index) | ability bar mode switches (explicit index, never −1 = cycle) |
| 103 | `use_ability` | `def, mode, target, x, y` (slot; mode 0 start · 1 cancel; x, y −1 = none) | ability bar (5.11.6) |
| 104 | `set_autocast` | `def, mode` (slot; 0 / 1) | ability button right-click / "A" pip |
| 105 | `unload` | `mode, target, x, y` (0 all · 1 one; target = passenger; drop point inside the map; ids = transports or garrison structures) | `U`, Unload button |
| 120 | `build_start` | `def, count` (structure index, 1..5) | structure card LMB |
| 121 | `build_cancel` | `mode` (queue index; 0 = head, also a READY item) | structure card RMB |
| 122 | `build_hold` | `mode` (1 hold · 0 resume) | card RMB on BUILDING; LMB on ON_HOLD |
| 123 | `build_place` | `def, x, y, mode` (structure index, top-left **cell** cx, cy, rotation 0-3) | placement click |
| 124 | `train` | `target, def, count` (producer id, unit index, 1..5) | unit card LMB / Shift+LMB |
| 125 | `train_cancel` | `target, mode` (producer id, queue index) | card RMB, queue strip |
| 126 | `queue_hold` | `mode` (1 hold · 0 resume); ids = producers | card RMB on a unit, queue-strip toggle |
| 127 | `set_rally` | `x, y, target, flags` (bit0 = clear); ids = producers | rule 13, armed RALLY, flag X |
| 128 | `set_primary` | `target` (producer id) | queue-strip star |
| 129 | `research` | `def` (research index) | research card LMB |
| 130 | `research_cancel` | `mode` (queue index) | research card RMB |
| 131 | `research_hold` | `mode` (1 / 0) | research card RMB on BUILDING |
| 132 | `sell` | – (ids = structures) | armed SELL |
| 133 | `set_struct_repair` | `mode` (0 off · 1 on · 2 toggle); ids = structures | armed REPAIR (explicit 0 / 1) |
| 134 | `undeploy_hq` | – (ids = HQs) | selection panel button "Pack HQ" |
| 140 | `use_power` | `def, x, y, angle, target` (**power index** `p_idx` of the roster's three — the sim derives the slot —; angle 0-4095; target = own structure / unit for those target modes, else 0) | power targeting (5.10.6) |
| 141 | `launch_superweapon` | `x, y, angle` | superweapon targeting |

**Gaps the UI works around** (requests in section 13): (1) `unload` needs a drop point inside the map, so the UI sends each carrier's own position (the exit-cell search starts there, `abilities.md` §5.10.2) and one command per carrier; (2) the kernel requires a *visible* target for `attack` (combat's executor may accept known targets, `combat.md` §5.10.6), so remembered ghosts get `attack_move` (Q12); (3) `force_fire` has no queue mode, so Shift+force-fire cannot queue; (4) `set_rally` on a deposit uses `−(deposit_idx+1)` (a deposit *field* id in v2.1, `sim_core.md` Q-7): the UI offers rally on ground and own entities only; (5) there is no per-command tag, so a `CMD_REJECTED` cannot be matched to the click that caused it (5.8.6). Closed by v2.1: `return_to_base` now carries its target, `harvest` addresses a deposit cell, `follow` exists, and the movement flags exist.

**Golden commands** (unit tests, 10.2; strings from `UiCmdCodec.describe`, arrays from the `SimCmd` builders — the layouts were re-implemented independently in Python, which reproduces the six vectors of `sim_core.md` §4.8 and yields the arrays below):

| Action | `describe()` | Int array |
|---|---|---|
| Shift+RMB move of {7, 3, 12} to world (45.0, 90.0) m | `MOVE ids=[3,7,12] x=15360 y=30720 mode=1 flags=0` | `[1, 15360, 30720, 1, 0, 3, 7, 12]` |
| RMB attack: unit {41} → enemy 907 | `ATTACK ids=[41] target=907 mode=0 flags=0` | `[40, 907, 0, 0, 41]` |
| Force modifier on own unit 1203 with {5, 6} | `ATTACK ids=[5,6] target=1203 mode=0 flags=1` | `[40, 1203, 0, 1, 5, 6]` |
| Force-fire {5, 6} at ground (20480, 20480) | `FORCE_FIRE ids=[5,6] target=0 x=20480 y=20480 count=0` | `[44, 0, 20480, 20480, 0, 5, 6]` |
| Shift+card: 5 units at producer 88, unit def 17 | `TRAIN target=88 def=17 count=5` | `[124, 88, 17, 5]` |
| RMB on the card: producer 88 queue [17, 17, 21] → cancel the last 17 (index 1) | `TRAIN_CANCEL target=88 mode=1` | `[125, 88, 1]` |
| Hold the Factory queue (producer 88) | `QUEUE_HOLD ids=[88] mode=1` | `[126, 1, 88]` |
| Hold the construction queue | `BUILD_HOLD mode=1` | `[122, 1]` |
| Place structure def 9 at top-left cell (30, 41), rotated once | `BUILD_PLACE def=9 x=30 y=41 mode=1` | `[123, 9, 30, 41, 1]` |
| Power def 1 at (65536, 40960), angle 90° = 1024 | `USE_POWER def=1 x=65536 y=40960 angle=1024 target=0` | `[140, 1, 65536, 40960, 1024, 0]` |
| Rally of producers {88, 90} to (10240, 12288) | `SET_RALLY ids=[88,90] x=10240 y=12288 target=0 flags=0` | `[127, 10240, 12288, 0, 0, 88, 90]` |
| Sell structures {31, 32} | `SELL ids=[31,32]` | `[132, 31, 32]` |
| Stance defensive for {2, 9} | `SET_STANCE ids=[2,9] mode=1` | `[45, 1, 2, 9]` |
| Guard the point (20480, 10240) with {4} | `GUARD ids=[4] target=0 x=20480 y=10240 mode=0` | `[42, 0, 20480, 10240, 0, 4]` |
| Shift patrol {4, 8} to (30720, 40960) | `PATROL ids=[4,8] x=30720 y=40960 mode=1 flags=0` | `[4, 30720, 40960, 1, 0, 4, 8]` |
| Armed attack-move {5, 6} to (20480, 10240) | `ATTACK_MOVE ids=[5,6] x=20480 y=10240 mode=0 flags=0` | `[41, 20480, 10240, 0, 0, 5, 6]` |
| Shift+RMB move {7, 3, 12} with `input/move_speed_match` on | `MOVE ids=[3,7,12] x=15360 y=30720 mode=1 flags=2` | `[1, 15360, 30720, 1, 2, 3, 7, 12]` |
| Armed Ctrl+F: {5, 6} follow own unit 1203 | `FOLLOW ids=[5,6] target=1203 mode=0` | `[12, 1203, 0, 5, 6]` |
| RMB on own airfield 640 with aircraft {21, 22} | `RETURN_TO_BASE ids=[21,22] target=640 mode=0` | `[47, 640, 0, 21, 22]` |
| `V` with aircraft {21, 22} (nearest pad) | `RETURN_TO_BASE ids=[21,22] target=0 mode=0` | `[47, 0, 0, 21, 22]` |
| Collector {9} RMB on the deposit cell (48, 17) | `HARVEST ids=[9] target=0 x=49664 y=17920 mode=0` | `[10, 0, 49664, 17920, 0, 9]` |
| Unload transport {70} standing at (66560, 30720), all cargo | `UNLOAD ids=[70] mode=0 target=0 x=66560 y=30720` | `[105, 0, 0, 66560, 30720, 70]` |
| Mode switch: slot 1 of unit {12} to mode 1 | `SET_MODE ids=[12] def=1 mode=1` | `[102, 1, 1, 12]` |
| Deploy MCV {6} | `DEPLOY ids=[6] def=-1` | `[100, -1, 6]` |
| Use ability slot 2 of unit {12} at (5000, 6000) | `USE_ABILITY ids=[12] def=2 mode=0 target=0 x=5000 y=6000` | `[103, 2, 0, 0, 5000, 6000, 12]` |
| Hold position {4} | `HOLD ids=[4]` | `[43, 4]` |
| STOP for 450 selected units | one command, 1 + 450 ints (`MAX_IDS` is 512; `split_ids` would only split above it) | – |

### 6.2 Events consumed

#### 6.2.1 Sim events (`AppEvents` consumer "ui", order 20; records `[type, tick, x, y, a, b, c, d, e, f]`, `x, y` in sub-cell units or (0, 0); `UiEv` holds the codes and the offsets)

The UI **degrades gracefully** when an event is missing: every fact below is also derivable from polled port state (construction edge, research edge, power edge, `sw_status` edge, prune diff), so a missing event costs only its notification, never correctness. Events are not filtered by the sim per viewer (`sim_core.md` §5.7); the notifier applies the fog rule of 5.13.1. Field letters follow each owner's table: core `sim_core.md` §6.2, combat `combat.md` §6.2, abilities `abilities.md` §6.2 (`p0..p3` → `a..d`), economy `economy.md` §6.2 (coordinates moved to `x, y`, the remaining fields keep their order — `[XR-5]` asks the reconcilers to confirm the compact layouts of 402 and 408).

| Code | Name | `x, y` | Fields the UI reads | UI consumer / effect | v1 name (`audio.md` / `render.md`) |
|---:|---|---|---|---|---|
| 1 | `SPAWNED` | position | `a` id · `b` kind · `c` def_idx · `d` owner · `e` facing · `f` reason (0 initial, 1 produced, 2 placed, 3 deployed, 4 summoned, 5 wreck, 6 script) | selection successor pairing, idle-collector tracker, `pending` clearing | `0x01` |
| 2 | `REMOVED` | position | `a` id · `b` kind · `c` def_idx · `d` owner · `e` reason (0 killed, 1 sold, 2 expired, 3 deployed, 4 consumed, 5 script) | `UiSelection.on_removed`, groups, collector tracker | `0x02` |
| 3 | `OWNER_CHANGED` | position | `a` id · `b` old owner · `c` new owner · `d` reason (0 capture, 1 script) | `captured`, selection prune, minimap recolour | `0x04` |
| 4 | `CASH` | source or (0, 0) | `a` pid · `b` delta · `c` new total · `d` reason (0 start, 1 harvest, 2 salvage, 3 refund, 4 sell, 5 spend, 6 script) · `e` source id | credit ticker retarget (also polled); the viewer's SELL / REFUND: `UiViewPort.float_text("+$n")` at x, y (income floaters are the view's) | `CASH 0x20` |
| 5 | `CMD_REJECTED` | – | `a` pid · `b` op · `c` err (`SimCommand.Err`) · `d` detail (economy `RSN_*`, abilities 1..10) · `e` target-or-def | `cmd_rejected` (text `reject.<err>`), card shake; audio voices it itself | `0x61` |
| 6 | `ORDER_FAILED` | unit | `a` unit id · `b` order type · `c` err · `d` detail | `order_failed` | `0x60` |
| 7 | `PLAYER_ELIMINATED` | – | `a` pid · `b` reason (`Elim`) · `c` team | `player_defeated`, scoreboard | `0x70` |
| 8 | `MATCH_END` | – | `a` winner team (−1 none) · `b` reason · `c` tick | end summary (`match_ended` navigates) | `0x71` |
| 208 | `EV_DEATH` | position | `a` id · `b` def_idx · `c` `death_kind \| cause<<4 \| flags<<8` (flags 1 wreck, 2 crash, 4 decoy, 8 summoned, 16 structure, 32 had occupants, 64 unit, 128 aircraft) · `d` killer id · `e` `(killer_pid+1) \| (owner+1)<<8` · `f` `facing \| layer<<12 \| visual_ticks<<16` | `unit_lost` / `structure_lost`, selection prune | `DIED 0x03` |
| 213 | `EV_EMP` | victim | `a` victim id · `b` duration ticks · `c` 0 weapons off / 1 shutdown · `d` attacker pid · `e` 1 = blocked | `emp_hit` | `STATE 0x05` (7, 8) |
| 214 | `EV_ATTACK_ALERT` | victim | `a` victim owner · `b` victim id · `c` attacker pid · `d` class (0 unit, 1 structure, 2 collector, 3 aircraft); the sim throttles it (200 ticks per player unless 15 cells from the last alert) | `base_attack`, `unit_attack`, `collector_attack`, `ally_attack` | `0x52 / 0x53 / 0x54` |
| 235 | `EV_MODE_CHANGED` | – | `a` eid · `b` slot · `c` new mode | ability button state (also polled from the row) | – |
| 236 / 237 | `EV_ABILITY_USED` / `EV_ABILITY_READY` | – | `a` eid · USED: `b` kind, `c` slot · READY: `b` slot | ability cooldown sweep start / end | `ABILITY 0x40` |
| 240 / 241 | `EV_LOADED` / `EV_UNLOADED` | exit (unloaded) | `a` passenger · `b` carrier | selection prune (`F_INSIDE`), cargo readout | `0x06 / 0x07` |
| 242 | `EV_UNLOAD_BLOCKED` | – | `a` carrier · `b` reason | toast "No room to unload" | – |
| 243 | `EV_GARRISON_CHANGED` | – | `a` building · `b` occupants · `c` claim team | selection panel garrison count | – |
| 250 | `EV_SCAN_WARNING` | scan centre | `b` power idx · `c` radius (cells) · `d` owner pid | `scan_warning` (deduplicated against `EVT_WARNING` kind SCAN by owner + tick) | – |
| 259 | `EV_BUFF_APPLIED` | centre | `b` power idx · `c` entity count · `d` owner pid | `buff_applied` (own casts) | – |
| 301 | `EVT_PLACE_REJECTED` | – | `a` pid · `b` structure idx · `c` `RSN_*` | `cmd_rejected` with BAD_SITE (deduplicated against a `CMD_REJECTED` of the same tick) | `CMD_REJECTED 0x61` (BAD_SITE) |
| 302 | `EVT_STRUCTURE_READY` | – | `a` pid · `b` structure idx | `construction_ready`, tab pulse, placement offer | `BUILD_READY 0x25` |
| 305 | `EVT_UNIT_PRODUCED` | – | `a` pid · `b` entity id · `c` unit idx · `d` producer id | `unit_ready`, producer flash | `PRODUCTION_COMPLETE 0x26` |
| 306 | `EVT_QUEUE_STATE` | – | `a` pid · `b` producer id (0 construction, −1 research) · `c` `QS_*` · `d` reason | blocked / held chips (also polled) | `QUEUE_BLOCKED 0x28` |
| 307 | `EVT_RESEARCH_COMPLETE` | – | `a` pid · `b` research idx | `research_done`, DONE state | `0x2A` |
| 309 | `EVT_INSUFFICIENT_FUNDS` | – | `a` pid · `b` producer id / 0 / −1 · `c` credits needed | `insufficient_funds` | `QUEUE_BLOCKED 0x28` (1) |
| 310 | `EVT_UNIT_CAP_REACHED` | – | `a` pid | `unit_cap` | `0x2F` |
| 311 / 312 | `EVT_POWER_SHORTAGE` / `EVT_POWER_RESTORED` | – | `a` pid · (311) `b` supply · `c` demand | `low_power` / `power_restored` | `POWER_LOW 0x22 / POWER_RESTORED 0x23` |
| 314 | `EVT_STRUCTURE_SOLD` | – | `a` pid · `b` entity id · `c` refund | log line "Sold …" | `CASH` (SELL) |
| 317 / 318 | `EVT_HQ_DEPLOYED` / `EVT_HQ_UNDEPLOYED` | – | `a` pid · `b` HQ id / MCV id | selection successor (5.11.2), log line | `SPAWNED` (DEPLOYED) |
| 400 / 401 | `EVT_POWER_UNLOCKED` / `EVT_POWER_READY` | – | `a` pid · `b` slot | `power_unlocked`, `power_ready_own`, dock glow | `POWER_READY 0x31` |
| 402 | `EVT_POWER_ACTIVATED` | target | `a` pid · `b` slot · `c` power idx | `power_used_enemy`; own dock cooldown start (also polled) | `POWER_USED 0x30` |
| 404 | `EVT_WARNING` | zone centre | `a` warning id · `b` owner pid · `c` `WK_*` (0 superweapon, 1 power, 2 scan) · `d` source def idx | ribbons and minimap rings from `strategic_warnings()`; the view draws the zone | `SW_WARNING 0x34` |
| 405 | `EVT_SW_READY` | – | `a` pid | `sw_ready_own` | `0x33` |
| 406 | `EVT_SW_CANCELLED` | – | `a` pid · `b` superweapon idx · `c` cause (1 destroyed, 2 shut down, 3 sold) · `d` warning id | `sw_cancelled`, zone removal | `0x36` |
| 407 | `EVT_SW_EXEC_START` | – | `a` pid · `b` superweapon idx · `c` warning id | ribbon phase "INBOUND" | `SW_LAUNCHED 0x35` |
| 408 | `EVT_SW_IMPACT` | impact | `a` kind (superweapon idx, or 100 + power idx for shells) | the first impact clears the ribbon | `0x37` |
| 409 | `EVT_SW_DONE` | – | `a` warning id | ribbon and minimap ring removed | – |

Not consumed (presentation belongs to view / audio / the AI): core 9 `NAV_CHANGED`, movement 100-129 (`EV_MOVE_FAILED 100 … EV_STUCK 108`; the UI's "cannot reach" notice is core `ORDER_FAILED` 6), combat 200-207, 209-212, 215-220, abilities 230-234, 238, 239, 244-249, 251-258, economy 303, 304, 313, 315, 316, 320-329, 403, 410. **Events that sim_core v2.1 no longer lists but audio, view or the UI would like** (`[XR-5]`): `TECH_UNLOCKED` / `TECH_LOST` (audio's `new_construction_options` line; the UI derives the notice from card availability edges instead), `BUILD_CANCELLED` (audio's `canceled` line), `BUILD_STARTED`, `SW_CHARGING`, the `STATE` family (deploy, cloak, selling, powered — the UI reads flags), `HARVEST_DELIVERED` (economy `EVT_CREDITS_GAINED` is folded into `CASH`; the view's "+$" floaters need a delivery event or `CASH` with reason 1 and the refinery position), `PAUSED` / `UNPAUSED` (net's `pause_changed` covers the UI).

#### 6.2.2 `NetSession` signals (net.md §6.3), consumed through `AppState.bind_session` and the screens

| Signal | Consumer / effect |
|---|---|
| `phase_changed(phase, prev)` | `AppState` navigation (5.1.2, 5.3) |
| `lobby_changed()` | `UiScreenLobby` re-render from `lobby.state` (read-only) |
| `chat_received(channel, from_pid, from_name, text)` | lobby chat, in-game feed (`from_pid == 255` = system) |
| `countdown_changed(s)` | lobby overlay, `snd.ui.lobby_countdown_tick` |
| `join_rejected(reason, info)` | `UiDlgJoinRejected` |
| `kicked(reason, detail)` | message dialog → LAN browser |
| `load_progress(pids, percents)` | `UiScreenLoading` bars |
| `launch_aborted(reason, detail)` | dialog → back to the lobby |
| `match_started()` | `AppMatch.make_context` → game screen |
| `stall_changed(waiting)` / `stall_prompt(pids)` | `UiStallOverlay` / `UiDlgStallPrompt` |
| `pause_changed(paused, by_pid)` | `UiPauseBanner`, audio duck |
| `player_status_changed(pid, status)` | scoreboard, `player_left` notice |
| `speed_changed(pct)` / `input_delay_changed(turns)` | top strip badge, net overlay |
| `match_ended(result)` | end banner → `UiScreenEnd` |
| `desync_detected(report)` | `UiDlgDesync` |
| `net_error(code, text)` | toast |
| `map_ping(from_pid, x, y)` | minimap ALLY ping |
| `NetDiscovery.entries_changed()` | browser list |
| `NetReplayPlayer.verify_failed` / `finished` | replay bar banner / end-of-replay dialog |

### 6.3 Emitted by the UI/app (for other domains)

#### 6.3.1 UI cues (`UiAudioPort.ui`; ids of the audio registry `events.json`, `audio.md` §4.8 — the UI invents none)

Only cues the UI itself initiates. Everything the sim causes is voiced by audio from the same event batch (`audio.md` §3.11), including `snd.ui.build_ready`, `queue_cancel`, `place_fail` after a sim rejection, `snd.ui.error` after a `CMD_REJECTED`, the alarms and every announcer line.

| Constant (`UiAudioPort.*`) | Id | The UI plays it when |
|---|---|---|
| `CLICK` | `snd.ui.click` | any enabled button, card, tab or list row is pressed |
| `HOVER` | `snd.ui.hover` | menu-button hover (menus only, ≤ 8 per second) |
| `CONFIRM` | `snd.ui.confirm` | dialog confirm, armed-mode entry, preset applied |
| `BACK` | `snd.ui.back` | Esc / Back / dialog cancel |
| `TAB` | `snd.ui.tab` | sidebar tab or options page switch |
| `TOGGLE_ON`, `TOGGLE_OFF` | `snd.ui.toggle_on`, `snd.ui.toggle_off` | checkboxes and toggles |
| `SLIDER_TICK` | `snd.ui.slider_tick` | slider steps (≤ 10 per second) |
| `ERROR` | `snd.ui.error` | a **UI pre-check** refusal (locked card, invalid target, empty selection, empty control group) — not for sim rejections |
| `QUEUE_ADD` | `snd.ui.queue_add` | optimistic click on a card that queues something (audio ignores `BUILD_STARTED`) |
| `QUEUE_HOLD` | `snd.ui.queue_hold` | hold toggle click (audio voices the resulting `on_hold`) |
| `PLACE_OK`, `PLACE_FAIL` | `snd.ui.place_ok`, `snd.ui.place_fail` | placement committed / click refused by the UI pre-check |
| `SELL_MODE`, `REPAIR_MODE` | `snd.ui.sell_mode`, `snd.ui.repair_mode` | the tool is armed |
| `WAYPOINT` | `snd.ui.waypoint` | `W` latch on / off |
| `RALLY_SET` | `snd.ui.rally_set` | a rally order is issued |
| `GROUP_SET`, `GROUP_RECALL` | `snd.ui.group_set`, `snd.ui.group_recall` | Ctrl+n / n |
| `MINIMAP_CLICK`, `MINIMAP_PING` | `snd.ui.minimap_click`, `snd.ui.minimap_ping` | minimap press / a ping is issued or an ally ping arrives |
| `ALERT`, `NOTIFY` | `snd.ui.alert`, `snd.ui.notify` | UI-only warnings (idle collector, edge alert without a spoken line) / info toasts |
| `CHAT` | `snd.ui.chat` | a chat message arrives |
| `LOBBY_JOIN`, `LOBBY_LEAVE`, `LOBBY_READY`, `LOBBY_COUNTDOWN_TICK`, `LOBBY_START` | `snd.ui.lobby_join` … `snd.ui.lobby_start` | the matching net lobby signal (`audio.md` §3.11 row `net`) |
| `MENU_TRANSITION` | `snd.ui.menu_transition` | screen fade |

#### 6.3.2 Announcer lines

The UI announces nothing that the sim causes. `UiAudioPort.announce(line)` exists for the few UI / lobby originated lines (`player_disconnected` when a lobby peer leaves before the match; the in-match case is audio's, from `PLAYER_ELIMINATED`). Spoken lines reach the UI as captions: `Snd.announcement_started(line_id, text, priority)` → `UiAudioPort.caption` → `UiNotifier.on_caption` (5.13.1).

#### 6.3.3 Unit responses (`UiAudioPort.unit_selected` / `unit_ordered` / `order_denied`)

`unit_selected(def_idx, is_structure, count)` once per committed selection change with the primary's per-kind def index; `unit_ordered(order, def_idx)` when an order is issued, with `UiAudioPort.Order` chosen from the intent: MOVE / PATROL / FOLLOW / RETURN_BASE → MOVE; ATTACK / ATTACK_MOVE / FORCE_FIRE → ATTACK; GUARD → GUARD; DEPLOY / UNDEPLOY → DEPLOY; CAPTURE → CAPTURE; REPAIR / STRUCT_REPAIR → REPAIR; LOAD / GARRISON → LOAD; UNLOAD → UNLOAD; HARVEST / RETURN_CASH → HARVEST; STOP → STOP; SCATTER → SCATTER; SELL → SELL. `order_denied(def_idx, is_structure)` for a UI pre-check refusal of a unit order; the sim's `ORDER_FAILED` is routed to the same response by audio itself. Audio applies its own gaps (250 ms global, 700 ms per class and type), so the UI adds no throttle.

#### 6.3.4 App/UI signals other modules may subscribe to

| Signal | Emitter | Subscriber / meaning |
|---|---|---|
| `AppSettings.graphics_quality_changed()` | app | `AppApply` hands the `[video]` ConfigFile to `UiViewPort.apply_quality` (4.7.3) |
| `AppSettings.changed(id)` | app | audio (through `AppAudio.apply_settings`), view (colour mode, unit outline, camera shake), any module reading a setting |
| `AppState.mode_changed(mode, previous)` | app | `AppAudio.set_mode` → `Snd.set_mode` (MENU 1, LOBBY 2, LOADING 3, MATCH 4, POST_MATCH 5) |
| `AppNet.session_changed(session)` | app | view / audio drop world references on `null` |
| `UiThemeService.theme_changed(theme)` | ui | custom-drawn widgets |
| `UiCommandBus.issued(kind, cmd: PackedInt32Array)` | ui | tests, replay-of-UI-actions tooling |

### 6.4 What other domains must add (summary; exact wording in section 13)

* **sim (sim-core + production + power + abilities):** the read surface of table 3.2.4 including production / power introspection (a public `RSN_*` → `Err` table, ETA that already includes the 50 % rate, `queue_state`); four extra `SimPlayer` counters (4.9.1); `parent` set on an HQ deployed from an MCV (and the reverse) so the selection successor rule is exact; the events v2 dropped (6.2.1); `UNLOAD` accepting the carrier's own cell; omniscient-viewer reads and the vision ghost list.
* **view:** the `UiViewPort` provider (camera driven by the UI, pick, ground pick, minimap sources, placement ghost, quality keys, `ViewStyle` injection, model builder, showcase scene, map-preview bake) and the small deltas of `[XR-13]`..`[XR-19]`, chiefly the CVD switch (`set_cvd_palette`), the `colour_mode` names and `px_per_metre` / `project_points`.
* **net:** `NetSession.local_lobby(opts)`, lobby (de)serialisation for presets, spectator join option, replay-player accessors.
* **data:** `DefBrowser` cards including the structured fields the ability bar and Field Manual need; faction display accessors; `DefPower.warns_opponents`.
* **map:** `MapGenJob` (cancel, `progress_pct`), `MapGenerator.validate_params`, `MapData.start_cells` / `fair_slot_order`, `MapData.passable` / `deposit_at` (as specified in `terrain_movement.md` §3.3, §3.7).
* **art_direction:** `ViewStyle.ui_data(section)` and `style.ui.tokens_cvd`, the archetype `role` column, the decision on QA A-01 versus the default team set, one spelling of the accessibility settings keys (`[XR-49]`).
* **audio:** `Snd.apply_settings` never writes the file; the `snd.ui.*` ids of 6.3.1 exist; `announcement_started` fires for every line; the focus/mute behaviour stays in audio.
* **build/qa:** project settings (stretch, HiDPI, version), export filters, screenshot tooling, test-runner conventions.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

All UI data is plain JSON read once at boot by `UiText`, `UiKeymap`, `UiCursors`, `UiNoticeRules`, `AppMatch`; the visual tokens come from art's `style.json` through `ViewStyle` (7.4). Loaders are total: a malformed file logs `Log.error` with `file:line`, falls back to built-in defaults where one exists (keymap, cursors; skins and palettes fall back to the constants of `UiPalette` / `UiSkin.neutral` when `style.json` failed to load) and only strings/notices degrade to `⟦key⟧`. Exact-case file names, LF endings, ints and strings only (no engine-specific types). All paths are under `game/`.

### 7.1 `data/text/ui_en.json` — every user-visible string

```json
{ "format": 1, "lang": "en",
  "strings": {
    "menu.skirmish": "SKIRMISH",
    "menu.lan": "LAN MULTIPLAYER",
    "ui.ok": "OK",
    "ui.yes": "YES",
    "lobby.err.not_enough": "Add at least one opponent.",
    "order.deny.cannot_hit": "None of the selected units can hit that target.",
    "order.deny.blocked": "Nothing selected can move there.",
    "reject.11": "Insufficient funds.",
    "reject.12": "This production queue is full.",
    "reject.13": "Cannot place a structure there.",
    "notice.base_attack.title": "BASE UNDER ATTACK",
    "notice.base_attack.sub": "{structure}  //  {sector}",
    "net.err.connect_timeout": "Could not reach {address}:{port} within 6 seconds. Check the address, that the host has opened a game, and that UDP {port} is allowed through the host's firewall.",
    "net.stall.waiting": "Waiting for {names}... {seconds} s",
    "options.video/vsync.label": "Vertical sync",
    "options.video/vsync.tip": "Synchronises frames with the display to prevent tearing."
  },
  "plurals": { "hud.units_lost#one": "{n} unit lost", "hud.units_lost#other": "{n} units lost" } }
```
Rules: keys are lowercase dotted (`options.<setting id>.label|tip` keeps the setting id verbatim); `{name}` placeholders; `#one`/`#other` plural suffixes (`UiText.tn`); the `net.*` keys are the ones of `net.md` §5.13 (net supplies English defaults in `NetProtocol.describe_*`, this file overrides them); a lint script (`test_ui_text_keys`) scans the sources for `UiText.t(&"…")` literals and fails on a missing key. Namespaces: `menu ui lobby lan loading hud order.deny reject notice options fm end net tip credits action faction roster preset`.

### 7.2 `data/text/tips_en.json`

```json
{ "format": 1, "tips": [
  { "id": "radar_t2", "text": "Radar unlocks Tier 2. Radar plus Laboratory unlock Tier 3." },
  { "id": "low_power", "text": "During a power shortage production and research run at half speed and powered defenses go offline. Build another Generator." },
  { "id": "collector", "text": "Each Refinery comes with one free Collector. Extra Collectors cost 1,400 credits." },
  { "id": "queues", "text": "Every Barracks, Factory, Airfield and Dock has its own queue. More producers add queues, not hidden speed." },
  { "id": "sw_warning", "text": "Superweapon strikes show a warning zone to every player they threaten. Spread your buildings and move units out of the circles." },
  { "id": "groups", "text": "Ctrl+1..0 assigns a control group. Press the number twice to centre the camera on it." }
] }
```
Loading shows one tip per 6 s (`game/tips`). ≈ 30 tips are planned, each taken from a bible rule so they stay true.

### 7.3 `data/text/credits.json` (schema owned by `qa.md` §7.8; the Credits and Licenses screens read it)

```json
{"version": 1, "sections": [
  {"title": "Game",   "entries": [{"name": "Meridian Fracture", "author": "A real-time strategy prototype", "link": ""}]},
  {"title": "Engine", "entries": [{"name": "Godot Engine 4.7.2", "license": "MIT", "link": "licenses:godot"}]},
  {"title": "Fonts",  "entries": [{"name": "Rajdhani", "author": "Indian Type Foundry", "license": "OFL-1.1", "link": "licenses:font/rajdhani"},
                                  {"name": "Orbitron", "license": "OFL-1.1", "link": "licenses:font/orbitron"}]},
  {"title": "Audio",  "entries": [{"name": "Kokoro-82M (voice lines)", "license": "Apache-2.0", "link": "licenses:audio/kokoro"}]}]}
```
Each entry: `name`, optional `author`, `license` (SPDX), `link` = `licenses:<id>` (opens the Licenses screen scrolled to that component of `LICENSES/THIRD_PARTY.json`) or empty. The Credits screen renders sections in order; QA owns the content (its `licenses.py audit` fails if a shipped component lacks a credits entry, `qa.md` §5.11), the UI owns the rendering. Names of individuals are not invented by this spec; the implementer takes them from the repository owner.

### 7.4 What the UI reads from `game/data/recipes/style.json` (owned by `art_direction.md` §7; read-only here)

The UI has **no data file of its own for colours, skins, type or emblems**. `App` loads `ViewStyle.load_file()` once at boot (`schema meridian.style/1`, ~2 ms; on failure `push_error("style.json: <path>: <reason>")` and `null`) and injects it into `UiSkinSet` and the view. Everything below is read through `ViewStyle`:

| `style.json` path | UI consumer | `ViewStyle` accessor |
|---|---|---|
| `ui.tokens` (18 tokens, 4.6.4) | `UiPalette` constants (asserted equal by test U-1), `UiTheme` | `ui_token(name)` |
| `ui.chrome` | `UiTheme.build` / `UiStyleBox` recipes (5.19.1) | `chrome()` |
| `ui.skins` (8 entries `{accent, accent2, tint}`) | `UiSkin.from_style` | `skin(code)` |
| `ui.type` (4.6.2), `ui.relation`, `ui.hp_ramp`, `ui.selection`, `ui.icon_rig` | `UiFonts`/`UiMetrics`, pings / tooltips / cursor tints, the selection-panel HP bar; the view reads the rest | `ui_data(section)` (**requested**, `[XR-49]`; `FxStyle.relation_color` / `hp_color` cover the two colour ramps today) |
| `player_colors.default`, `.cvd`, `.assign_order` | lobby swatches, blips, scoreboard, roster strip | `player_color(id, cvd)`, `player_color_count(cvd)`, `default_color_for_slot(slot)`, `plate_contrast(faction, id, cvd)` |
| `emblems.factions`, `emblems.subs` | `UiEmblem` (`draw_ops`, `draw_faction`, `draw_badge`, `draw_pips`) | `emblem_ops(code)`, `sub_glyph_ops(key)` |
| `faction_order` | faction index for skins and emblems | `faction_index(code)` |

Stability rules: the UI never caches a `Dictionary` returned by `ViewStyle` beyond the call that needs it (art: read-only, owned by `ViewStyle`); a missing key falls back to the constants of `UiPalette` / this spec's tables and logs one `Log.warn`.

### 7.5 Colour-vision variants that art does not define (constants in `ui_palette.gd`, proposed for `style.ui.tokens_cvd`)

| Constant | Value | Role |
|---|---|---|
| `CVD_OK` / `CVD_WARN` / `CVD_DANGER` / `CVD_POWER` | `#4DB8FF` / `#F5E663` / `#E8590C` / `#A8E6FF` | semantic states in colour mode `cvd` (min ΔE2000 of OK / WARN / DANGER: 44.9 normal, **21.9** deuteranopia, 32.0 protanopia, 33.3 tritanopia) |
| `P_DEFAULT_0_7` (documentation constant, not used at run time) | `AD0410 1E69C6 53AC7A DDF514 B892FD 65FDFA CD6D04 87386B` | the replacement proposal for the default team set (5.19.3), kept so that `test_ui_palettes` can print the comparison |

Test U-1b asserts the CIEDE2000 numbers of the semantic set with `UiA11y`; `[XR-49]` asks art to host the four constants as `style.ui.tokens_cvd` so that they are generated, not typed twice.

### 7.6 `data/ui/notices.json` — notifier rules (one row per rule of 5.13.2)

```json
{ "format": 1, "rules": [
  { "id": "base_attack", "trigger": "attack_alert", "filter": { "victim": "viewer", "class": 1 },
    "severity": "warn", "ribbon": true, "log": true, "glyph": "warning",
    "title_key": "notice.base_attack.title", "sub_key": "notice.base_attack.sub",
    "announcer_line": "base_under_attack", "cue": "",
    "ping": "alert", "jump": true, "cooldown_s": 6.0, "ttl_s": 8.0, "dedupe": "base_attack" },
  { "id": "sw_warning_enemy", "trigger": "warning", "filter": { "owner": "enemy", "kind": 0, "affected": true },
    "severity": "danger", "ribbon": true, "log": true, "glyph": "missile", "countdown": "exec_tick", "global": true,
    "title_key": "notice.sw_warning_enemy.title", "sub_key": "notice.sw_warning_enemy.sub",
    "announcer_line": "sw_launch_detected", "cue": "", "ping": "superweapon", "jump": true,
    "cooldown_s": 0.0, "ttl_s": 0.0, "dedupe": "warning:{id}" }
] }
```
`trigger` ∈ the lower-case event names of 6.2.1 (`attack_alert`, `death`, `warning`, `queue_state` … = `UiEv.by_name`), `net_*` (signals), `state_*` (edge of a polled value: `state_idle_collector`, `state_tech_unlocked`), `ui_*` (UI refusals). `filter` keys: `victim` / `owner` / `pid` (`viewer` / `enemy` / `ally`), `class` (attack-alert class 0-3), `kind` (`WK_*`), `structure` (bool), `counts_for_cap` (bool), `reason`, `err`, `affected` (bool: the warning must be listed by `strategic_warnings()` for the viewer). `announcer_line` is the audio line id spoken for the same event (used only to suppress the duplicate caption, 5.13.1); `cue` is a `UiAudioPort` constant name (`ALERT`, `NOTIFY`, `ERROR`, `CHAT`, `MINIMAP_PING`) for notices audio does not voice; `global: true` marks rows exempt from the fog rule of 5.13.1. Unknown trigger or filter keys are load errors. Top-level keys: `format`, `rules`.

### 7.7 `data/ui/cursors.json`

```json
{ "format": 1, "sizes": [32, 48, 64],
  "cursors": {
    "ATTACK":      { "slot": "CROSS",        "recipe": "crosshair",   "color": "danger",  "hotspot": [0.5, 0.5] },
    "MOVE":        { "slot": "MOVE",         "recipe": "chevron_ring", "color": "ok",     "hotspot": [0.5, 0.5] },
    "DENIED":      { "slot": "FORBIDDEN",    "recipe": "no_entry",    "color": "danger",  "hotspot": [0.5, 0.5] },
    "RALLY":       { "slot": "HSPLIT",       "recipe": "flag",        "color": "accent",  "hotspot": [0.24, 0.94] },
    "POWER":       { "slot": "CROSS",        "recipe": "reticle",     "color": "power",   "hotspot": [0.5, 0.5], "variant": true },
    "SUPERWEAPON": { "slot": "CROSS",        "recipe": "reticle_x2",  "color": "danger",  "hotspot": [0.5, 0.5], "variant": true },
    "SCROLL_N":    { "slot": "ARROW",        "recipe": "scroll_arrow", "color": "text",    "hotspot": [0.5, 0.12], "rotate_deg": 0,   "variant": true },
    "SCROLL_NE":   { "slot": "ARROW",        "recipe": "scroll_arrow", "color": "text",    "hotspot": [0.88, 0.12], "rotate_deg": 45,  "variant": true }
  } }
```
Recipes are `UiCursors` drawing functions (crosshair, chevron_ring, no_entry, flag, reticle, brackets, arrow, ibeam, hand, shield, wrench, dollar, magnifier, spinner, chevron_box, corner_brackets, crosshair_arrows, ground_reticle, scroll_arrow); colour tokens resolve through `UiPalette`/the current skin (`danger` = the `ENEMY` relation red, `ok` = `SELF` green, `text` = `TEXT`); every image gets art's 2-px white stroke with a 1-px dark outline (a white outer ring under `access/high_contrast_hud`); the eight `SCROLL_*` entries are one recipe rotated in 45° steps and are `variant`s swapped onto the `ARROW` slot while the pointer is in the edge-scroll band (5.7.3); hotspots are fractions of the image size so all three sizes share one table.

### 7.8 `data/ui/keymap_defaults.json`

```json
{ "format": 1, "actions": [
  { "id": "cmd_attack_move", "category": "orders", "contexts": ["game"], "keys": ["A"], "label_key": "action.cmd_attack_move" },
  { "id": "group_assign_1", "category": "selection", "contexts": ["game"], "keys": ["Ctrl+1"], "mac_keys": ["Ctrl+1", "Cmd+1"] },
  { "id": "cam_rotate_left", "category": "camera", "contexts": ["game", "observer"], "keys": ["Q"], "repeat": true },
  { "id": "card_1", "category": "sidebar", "contexts": ["game"], "keys": ["Alt+Q"] },
  { "id": "cam_orbit", "category": "camera", "contexts": ["game", "observer"], "mouse": [3], "allow_mouse": true }
] }
```
`keys` are US-layout chords parsed with `OS.find_keycode_from_string` and stored as *physical* keycodes (letters, digits and F-keys are identical on the US layout); `mac_keys` replaces `keys` on macOS; `mouse` lists mouse buttons (3 = middle). The full table is 5.6.1 (≈ 150 rows after expanding `1..0`, `1..12`).

### 7.9 Quality presets — there is no UI copy

The UI ships no graphics-preset file. Presets and renderer clamps are the view's `game/data/recipes/quality.json` (`render.md` §7.7, schema `meridian.quality/1`); the Options page needs only its key list (4.7.2) and the `ViewQuality` API. Worked example of what gets persisted for a player who picked High and lowered the render scale: `[video] quality=2` and `render_scale=0.85`, every other key absent (= the High preset). The first-run choice is `ViewQuality.recommend()`.

### 7.10 `data/ui/skirmish_presets.json`

```json
{ "format": 1, "presets": [
  { "id": "duel", "name_key": "preset.duel", "map": { "family": 0, "size": 96, "layout_players": 2 },
    "rules": { "start_credits": 7500, "unit_cap": 150, "superweapons": true, "fog_of_war": true, "shared_vision": false, "veterancy": false }, "speed_code": 2,
    "slots": [ { "kind": "human", "roster": "last" }, { "kind": "ai", "level": 1, "style": 0, "roster": "random", "team": 2 } ] },
  { "id": "ffa4", "name_key": "preset.ffa4", "map": { "family": 0, "size": 128, "layout_players": 4 }, "speed_code": 2,
    "slots": [ { "kind": "human", "roster": "last" }, { "kind": "ai", "level": 2, "roster": "random" }, { "kind": "ai", "level": 2, "roster": "random" }, { "kind": "ai", "level": 2, "roster": "random" } ] }
] }
```
The file ships four presets — `duel` (1v1 vs a Medium AI, 96 cells), `team2v2` (2v2, 128), `ffa4` (one human and three Hard AIs free-for-all, 128) and `war4v4` (4v4 with Hard AIs, 256); the example shows two of them, the other two follow the same shape. `roster: "last"` = `game/last_roster`; slot fields map 1:1 to `NetLobby` calls; presets contain no seed (a fresh seed is rolled when loaded).

### 7.11 Files written at runtime

| Path | Content | Writer |
|---|---|---|
| `user://settings.cfg` (+ `.tmp`, `.bak`, `.bad-<utc>`) | 4.8.2 | `AppSettingsStore` |
| `user://logs/godot.log` (+ engine rotation `godot<timestamp>.log`) | engine and game lines (game lines formatted by `AppLogSink`), < 5 MB per hour of play | the engine; the app installs the sink |
| `user://.session` | `{"pid","start_utc","version"}` | `AppCrashReporter` |
| `user://logs/crash/crash_<utc>.txt`, `crash_<utc>_unclean.txt`, `crash_<utc>_fatal.txt` | report header + `Log.ring` tail; newest 20 kept | `AppCrashReporter` |
| `user://cache/icons/<key>.png` | baked icons (key = content hash + size, `render.md` §5.8.10); a stale file is impossible | written by the view (`ViewIconBake`); the folder is created by `AppPaths.ensure_user_dirs()`; the options page offers "Clear caches" |
| `user://screenshots/<utc>.png` | `Print` key | `UiScreenGame` |
| replays / desync packages | — | `net` (not this module) |

### 7.12 Fixture worlds for `UiSimPortFixture` — `tests/fixtures/ui/<name>.json`

A fixture is a *scripted* stand-in for the sim (no `GameData` mutation): it lets HUD screenshots and layout tests run without `SimWorld`.

```json
{ "format": 1, "roster": "roster.napc.canada", "map": { "w": 128, "h": 128 }, "viewer": 0, "tick": 15200,
  "players": [ { "pid": 0, "name": "X42553", "team": 1, "color": 0, "roster": "roster.napc.canada", "credits": 12450, "harvested": 61000, "power_supply": 300, "power_demand": 265 },
               { "pid": 1, "name": "AI 2",  "team": 2, "color": 1, "roster": "roster.def.russia" } ],
  "construction": { "state": 1, "def": "structure.shared.radar", "progress_permille": 372, "eta_ticks": 377, "rate_pct": 100, "queue_state": 0, "queue": [] },
  "producers": [ { "id": 88, "def": "structure.shared.factory", "queue": ["unit.napc.narwhal_amphibious_tank", "unit.napc.narwhal_amphibious_tank"], "progress_permille": 620, "queue_state": 0 } ],
  "powers": { "power.napc.uav_sweep": { "status": 1, "ready_tick": 16400, "cooldown_ticks": 1800 } },
  "superweapon": { "status": 1, "charge_permille": 740, "ready_tick": 17000 },
  "entities": [ { "id": 1001, "def": "unit.napc.guardian_tank", "owner": 0, "x": 65536, "y": 61440, "hp": 800, "hp_max": 800, "order": 0, "selected": true },
                { "id": 2001, "def": "unit.def.hammer_tank", "owner": 1, "x": 90112, "y": 51200, "hp": 500, "hp_max": 700, "visible": true } ],
  "events": [ { "at_tick": 15210, "type": "EV_ATTACK_ALERT", "x": 70000, "y": 60000, "a": 0, "b": 1001, "c": 1, "d": 0 } ],
  "warnings": [ { "id": 3, "owner": 1, "kind": 0, "sw": "superweapon.def.perun_missile_complex", "x": 40960, "y": 30720, "radius": 9216, "angle": 0, "start_tick": 16900, "exec_tick": 17300 } ] }
```
Ids in fixtures are strings resolved through the real `GameData` (`GameData.for_test` or the shipped data), so the same fixture works with any balance data. `events` use the master record shape: `type` is a `UiEv` name and `x, y, a … f` are the position and payload ints of 6.2.1 (the example is `EV_ATTACK_ALERT`: victim owner 0 at (70000, 60000), victim entity 1001, attacker 1, class 0 = unit); `take_events()` returns the records whose `at_tick` has passed since the last call. The fixture player advances `tick` on `advance(ticks)` and re-derives progress/eta/cooldowns linearly, which is enough for animated screenshots.

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

`ui/` and `app/` are **outside the deterministic core** (ARCH §5: they may use floats, `Dictionary`, `Time`, engine RNG, signals, `await`). Their only influence on the simulation is the integer command arrays they hand to `NetSession.submit_command`, which net orders, relays, records and executes identically on every peer (net.md I1-I3). Nothing the UI owns is checksummed.

| Rule | Compliance in this domain |
|---|---|
| DR-1 ints only in sim input | `UiCmdCodec` builds command arrays from `int`s only (the `SimCmd` builders take and return ints, `sim_core.md` §3.5, §4.8); coordinates pass through the single `roundi` step of 5.8.2; no `float`, `Vector2` or `Color` value is ever written into a command. Angles use `roundi(atan2 × 4096 / TAU)` once, at the UI, and are transmitted as ints |
| DR-2 no engine randomness in the sim | The UI does use engine RNG (seed re-roll, tip choice, featured faction) — these are UI-side and only the *chosen* seed (a u32 in the lobby) crosses into the sim through `MatchConfig`, exactly as net.md §5.3.5 requires |
| DR-3 no wall clock in the sim | `Time.get_ticks_msec()` appears only in UI timers (double click, hold repeat, toasts, cooldown de-duplication). No timestamp, frame number or `delta` is put into a command. HUD countdowns use **sim ticks** (`sim.tick()`), so they freeze during a pause |
| DR-6/7 order | Commands carry ids in ascending order (`UiSelection.sorted_ids`), chunks are ascending, rule-produced intents are emitted in the fixed rule order; no command depends on `Dictionary` iteration order (the `ids_by_cap` dictionary is only used as a lookup keyed by ints and read through `ids_with()` which returns ascending arrays). Identical user actions therefore yield identical command arrays (golden tests 10.2) |
| DR-8 | Not applicable to `ui/`/`app/` (Nodes, signals and `await` are their job), but **no UI callback runs inside a sim tick**: `AppNet` polls first, events are dispatched after `poll()` returns, widgets update afterwards |
| DR-9 no hidden global state | Two sessions can coexist in tests: `UiSimPort`/`UiViewPort`/`UiNetPort` are per-match instances held by `AppMatchContext`; the only statics are stateless helpers and read-only caches (`UiFonts`, `UiText`, `UiKeymap.instance()` — settings, not sim state) |
| DR-10 data hash | The UI displays `GameData.data_hash` (`UiFormat.hash8`) and never converts data itself |
| DR-12 events are output-only | The UI reads events and polled state; it never writes into `world` — `UiSimPortWorld` exposes no mutator, and a lint proposal (`UL-1`, request `[XR-44]`; the ids `L010`-`L016` are taken by tooling and QA) greps `src/ui/**` and `src/app/**` for assignments on `world.`/`SimWorld` members |
| DR-13 checksum coverage | The UI adds **no** persistent sim state. `SimPlayer.stats` (4.9.1) is a sim request: whatever the sim stores there must be checksummed by the sim |
| DR-14 UI floats | allowed; anything the UI decides enters the sim only as ints (5.8) |
| DR-15 interpolation | `tick_alpha()` is used only by widgets for smoothing; it never feeds a command |

**Local settings can never desync a match.** Settings that reach the sim are lobby values transmitted by the host (`rules.*`, `handicap`) — not `settings.cfg` values. `net/min_input_delay` changes only the pacing floor (net), `controls/*`, `ui/*`, `video/*`, `audio/*` are presentation. `AppMatchJob` phases VIEW/ICONS/PREWARM are read-only with respect to the sim adapter (test D4 proves `checksum0` is identical with and without them).

**Cross-platform statement.** Screen-space picking uses float projection, so two machines may resolve the same physical click to different entity ids; that is irrelevant because the *sender's ids* are what travel. For headless tests the harness supplies ids directly (`--script-cmds`), which makes UI-script runs reproducible across macOS/Linux/Windows.

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

UI cost is per **rendered frame** (60 FPS target = 16.6 ms; the UI's budget is ≤ 2.0 ms average and ≤ 4 ms in the worst frame on the reference Apple M5 Max, ≤ 5 ms on a mid-range x86 laptop, i.e. ≤ 30 % of the frame) plus small per-tick batches at 20 Hz. All CPU figures below come from the spike unless marked *(estimate)*; GPU time could not be measured on Metal (P8), the GPU load is small by construction (≈ 700 draw calls, one full-screen vignette quad, no post-processing besides an optional glass blur that is **not** used).

### 9.1 Per-frame CPU (Forward+, 1080p, 8 players, 400 entities on screen, 100 cards, 40 selected)

| Component | Cost per frame (amortised) | Basis |
|---|---|---|
| HUD widget tree, idle | 1.17 ms | spike: 683 draw calls, Forward+ (Mobile 0.51 ms) |
| HUD with animated sweeps/tickers | +0.10 ms | spike 1.27 ms; shader sweeps 0.11 ms for 100 |
| UI-side world overlay (order markers, targeting preview, edge alerts; ≤ 12 primitives) + the per-frame `set_selection` / `set_hover` calls | < 0.03 ms | *(estimate)*; the rings, bars and lines themselves are the view's instanced quads (`render.md` §9: overlays ≤ 0.1 ms typical each, counted in the view's budget, not here; the spike's UI-drawn overlay cost 0.67 ms for 377 visible entities, the reason for moving it) |
| Minimap redraw (30 Hz) | 0.07 ms | spike 0.23 ms per redraw for 439 dots |
| `UiHudPresenter` tick batch (20 Hz; ≈ 30 port reads for credits/power/queues, 40 `check_*` at 2 Hz, selection panel at 10 Hz) | 0.10 ms | *(estimate)*: 0.4 ms per batch, 6 µs per read |
| Minimap feed (10 Hz, 1,000 entities through `snapshot()` into PackedArrays) | 0.05 ms | *(estimate)* 0.5 ms per build |
| Hover resolver (30 Hz while the pointer moves): `ViewPicker.pick` 60-90 µs + resolve 30 µs | 0.04 ms | `render.md` §5.11 |
| Notifier / events | < 0.02 ms | table lookups |
| Strategic-zoom class markers (only below 18 px per metre; 400 units): `project_points` 400 × ≈ 1 µs every 66 ms + 400 `draw_texture_rect_region` calls at 30 Hz | +0.3 ms amortised (0.5 ms in a rebuild frame) | *(estimate)*: GDScript ≈ 1 µs per call; one atlas texture, one batched draw command; skipped in `UiHud.lite` |
| **Typical total** | **≈ 1.5 ms** | spike measured HUD + 400 moving entities = 2.22 ms Forward+ / 1.25 ms Mobile, of which the UI-drawn overlay was 0.67 ms |
| **Worst case** (500 selected, tile overflow, 8 ribbons churning, options popup open, a `pick_box` every 66 ms while dragging = 1.2 ms / 4 frames, strategic markers on) | **≈ 2.6 ms** | tiles are one custom draw bounded by the visible tile slots (≤ 40); the view caps its selection buffer at 512 instances; the drag box costs 0.3 ms amortised |

`gl_compatibility` is CPU/draw-call bound on macOS GL-on-Metal (HUD-only idle frame 6.3 ms vs Forward+ 0.2-0.5 ms render CPU): the `UiHud.lite` mode (5.19.6 rule 7) removes glow polylines, scanlines and the vignette and halves the minimap rate; target ≤ 4 ms there.

### 9.2 Load and startup budget

| Phase | Budget | Notes |
|---|---|---|
| Process start → splash visible | ≤ 100 ms | fonts + theme first (5-9 ms first `UiTheme.build`) |
| `GameData.load_default()` | 150-250 ms | data spec §9; synchronous behind the splash |
| Cursor bake (27 images) | ≈ 60 ms | one SubViewport batch (17 base + 2 reticle variants + 8 scroll arrows) |
| Pipeline prewarm | 220 ms warm / 2.6-3.3 s cold | spike: first 3D bake stalls 2.6-2.8 s (Metal), 1.5 s (GL) |
| Menu → interactive | ≤ 2.0 s warm, ≤ 5 s cold | |
| Roster icons (≈ 35 defs, baked by the view inside its build, one per frame) | ≈ 0.7 s warm (≈ 19 ms per icon incl. two frame waits) | the view's disk cache (`user://cache/icons/`, key = content hash + size) makes launches 2+ nearly free |
| Lobby briefing roster strip (20 icons) | progressive: placeholders at once, one real icon per frame (≈ 0.4 s to fill warm, immediate on a cache hit) | requests carry a hover token so an abandoned roster's queue is dropped |
| Options screen build | ≤ 10 ms (≈ 80 schema rows) | built lazily per page |
| Lobby map preview | 0.3-2.5 s asynchronous (`MapGenJob` worker) + 21-42 ms on the main thread (`bake_map_preview`) | one-frame hitch when the texture arrives; cached per `(family, size, seed, layout_players)`; a seed change cancels the job |
| Field Manual open | ≤ 30 ms shell + one `unit_card` per visible list row (0.05 ms each, data spec §9); full roster build sliced over frames | |
| Replay list (200 files) | metadata only (header + trailer): ≤ 150 ms total, rows appear progressively | net.md §5.8 |

### 9.3 Memory

Icons are the view's textures (ICON 128 x 96 x 4 B = 48 KB, PORTRAIT 384 x 288 = 442 KB baked on demand, CARD 188 x 124 = 93 KB if requested): ≈ 1.7-3.3 MB per roster (≈ 35 defs); `UiIconCache` holds only handles, the view owns the LRU. Fonts: 1.4 MB on disk (four files) plus glyph atlases (≈ few MB). Theme + styles ≈ 1 MB. `UiPickData` for 1,000 entities ≈ 40 KB. `Log.ring` 256 lines ≈ 40 KB.

### 9.4 Worst cases and mitigations

| Case | Risk | Mitigation |
|---|---|---|
| 500 selected units | tile grid + brackets | tiles drawn in one Control (≤ 40 slots, overflow tile); brackets in one multiline call; bars only for the ≤ 96 nearest the camera; commands chunked by 256 ids |
| 200-row LAN list | node explosion | `UiListRow` custom-drawn rows (1 canvas item per row), scroll virtualisation above 400 rows |
| Card sweeps on 24 visible cards | GDScript per frame | shader back-end, `refresh()` only on state change |
| Theme rebuild on skin change | 5-9 ms hitch | done under the screen fade (0.18 s) |
| Chat / notification storm | label churn | cap feed lines, coalesce identical, `RichTextLabel` plain text, ≤ 6 lines visible |
| First bake stall (cold shader cache) | 2.6-2.8 s | prewarm behind splash/loading; never on first click |
| Field Manual tech tree (≤ 60 nodes) | draw | one custom-drawn Control, edges as polylines, cached on roster change |
| Minimap at 4K | fill rate | texture is map-resolution (≤ 256²), widget ≤ 300 logical px — independent of window size |
| Options popups in exclusive fullscreen | embedded windows | `gui_embed_subwindows` default keeps them inside the viewport |
| Allocation churn | GC pauses | no allocation in `_draw`, reused arrays/rows, `StringName` constants |

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

### 10.1 Conventions

* Files `game/tests/ui/test_ui_*.gd`, `extends RefCounted`, `func test_*(t: TestCtx)` (the runner's convention); any engine error fails a test (`t.expect_errors(n)` when a test provokes one). Pure logic (layout maths, keymap, selection, resolver, codec, settings, notifier, palettes) is tested **without a SceneTree** through `UiSimPortFixture`/`UiNetPortRecorder`.
* Tests that need input events or laid-out Controls are **labs**: ordinary coroutine tests (`game/tests/ui/test_ui_lab_*.gd`; the runner supports `await`, `qa_tooling.md` §2 — 30 s default timeout, `t.set_timeout(s)`) that build a sized `SubViewport` (P6), push events with `Viewport.push_input`, `await` `process_frame` and assert with `t.eq` / `t.check`; they also print `LAB | … | …` lines with `t.note` so a log reads like the spike's input lab. They run under `tools/gd test ui` and unchanged under `tools/gd linux test ui`; no renderer is needed for input and layout (icon baking and screenshots are the `gd shot` tests of 10.6, because `--headless` has no renderer: `frame_post_draw` never fires).
* Autoload-free: tests construct `AppSettingsStore`, `AppFlow`, `AppLogger` etc. directly (P9).

### 10.2 Unit tests

| File | Cases → expected |
|---|---|
| `test_ui_layout` | `factor((1920,1080),1.0)=1.0`; `(1280,720)=0.75` (0.667 clamped); `(1024,576)=0.75`; `(2560,1440)=1.3333`; `(3840,2160)=2.0`; `(3840,2160)×1.25=2.5`; `(1920,1080)×1.5=1.5`; `(5120,2880)=2.0`; logical sizes of 5.4.1; `minimap_size(960)=297`, `(1080)=300`, `(800)=209`, `(720)=180`, `(600)=180`; size classes: 799 → COMPACT, 800 → REGULAR, 1299 → REGULAR, 1300 → LARGE; bottom panel width `clamp(1358−40, 600, 900)=900`, `clamp(700−40,…)=660`, `clamp(500,…)=600` |
| `test_ui_format` | `credits(12450)="12,450"`, `credits(0)="0"`, `credits(999)="999"`, `credits(1000000)="1,000,000"`; `mmss(26.0)="0:26"`, `mmss(25.1)="0:26"` (ceil), `mmss(0)="0:00"`, `mmss(3599)="59:59"`; `hms(3725)="1:02:05"`; `hash8(0x9F3AC21E)="9F3A-C21E"`, `hash8(0x1)="0000-0001"`; `pct(372)="37%"`; `hotkey` returns the platform label |
| `test_ui_keymap` | defaults conflict-free (no shared packed key with an overlapping context bit); `pack(Ctrl+Shift+1)=301989937`, `pack(Alt+Q)=67108945`, `unpack∘pack` identity; exact matching: event `Ctrl+1` matches only `group_assign_1`; `Shift+S` matches no action while `S` matches `cmd_stop`; `Shift+1` matches `group_append_1` only; `Alt+Q` matches `card_1` and not `cam_rotate_left`; `Pause` and `Ctrl+P` both match `pause_game`; `P` matches `cmd_patrol` (not ping), `J` matches `cmd_ping`; `Delete` matches `tool_sell` while `Ctrl+Delete` matches only `cmd_scuttle`; labels (`Alt+Q` on non-mac); `bind` conflict returns the other action; forbidden combos refused (`Esc` for `cmd_stop`, `Alt+F4`); swap/replace resolution; persistence round trip through `AppSettingsStore` (`PackedStringArray("k:67108945")`); empty array = explicitly unbound; `install(GAME)` frees Tab and `uninstall` restores `Tab`/`Shift+Tab` on `ui_focus_next/prev`; macOS override adds `Cmd+1` to `group_assign_1` |
| `test_ui_settings` | every id of 4.8.1 present once with a default of its declared type; `set_value` clamps (`video/ui_scale=250 → 200`, `audio/master=-5 → 0`); unknown id → `false`; corrupt file → renamed `.bad-<utc>`, `.bak` tried, else defaults, `load_notes` non-empty; only non-default values written; unknown section preserved verbatim; `meta/version` newer than the build still loads; **crash-safe write** (`test_app_settings_atomic_write` with a fault-injecting `AppFileLayer`): the sequence `.tmp` written → old file renamed `.bak` → `.tmp` renamed is interrupted after each step and a valid file (`settings.cfg` or `.bak`) is always loadable and restored; the saved window rectangle is clamped to the screens that exist (`test_app_window_clamp`, fakes for 1 and 2 screens, an unplugged monitor); `AppGraphics.overrides` is empty for a preset-only file and lists the keys otherwise ("Custom (based on …)"); `AppGraphics.recommend` forwards `ViewQuality.recommend` |
| `test_ui_apply` | audio hand-off: the `SndSettings` built from a store has exactly the store's `[audio]` values (defaults master 100, music 70, sfx 90, voice 100, ui 80, ambience 70, announcer 0, unit_voices 0) and `Snd.apply_settings` is called once per change through a fake `AppAudio` (the app never touches `AudioServer`); `quality_config` contains exactly the `[video]` keys present in the store (absent = preset value) and writes `[access] colour_mode` under the view's names (`cvd` → `deutan`, plus `cvd_palette`) and `high_contrast_hud` as its own boolean; `scaling_mode = metalfx_spatial` falls back to `bilinear` when the `metalfx` guard fails; `video/health_bars` reaches `set_health_bar_mode`; `video/ui_scale = 200` at 1280x720 gives factor 1.333 (floor) and reports "178 % effective"; `AppRelaunch.needed` is false when the running method already equals `video/renderer` or `--renderer-relaunched` is present |
| `test_ui_flow` | legal/illegal edges of 5.1.2 (e.g. `MAIN_MENU→IN_MATCH` illegal, `LOADING→SKIRMISH_LOBBY` legal); `push/pop` depth and return mode; `go` while a stack exists clears it |
| `test_ui_launch_args` | `--screen=lobby --fixture=hud_mid_match --ui-scale=1.5 --smoke --qa=D01 --selfcheck`; unknown `--k=v` lands in `extras`; bare `--flag` = true |
| `test_ui_selection` | replace/add/toggle; units + structures → units win; foreign selection is single; cap 500 (501st refused); `sorted_ids` ascending and cached; `prune` drops dead/foreign-owned/contained ids and re-picks the primary; **successor rule**: MCV id 5 `REMOVED(DEPLOYED)` + `SPAWNED(id 9, DEPLOYED)` whose `parent` is 5 → selection `{9}`; with `parent` 0 the pairing by emission order (two MCVs of one owner deployed in one batch: 5 → 9 and 6 → 10 keep their order); `REMOVED(reason KILLED)` → `{}`; a `SPAWNED(DEPLOYED)` of another owner is ignored; primary = highest `(tier, cost)` def then lowest id; `sel_subgroup_next` cycles defs |
| `test_ui_groups` | assign/add/append semantics; recall skips dead ids and clears an all-dead group; `register_press` true at 349 ms, false at 351 ms; centroid of ids {(0,0),(2048,4096)} = (1024, 2048) |
| `test_ui_selection_actions` | over the fixture ports: `same_type_on_screen(kind, def_idx)` returns only entities of that (kind, def) whose `entity_screen_rect` intersects the playfield (an off-screen twin is excluded); `all_military(true)` drops structures, service units and off-screen units, `all_military(false)` keeps the latter; `next_idle` walks idle armed units in ascending id order and calls `focus_on_sim`; `sel_group_next` cycles the non-empty groups and skips empty ones; `hq()` picks the nearest own HQ |
| `test_ui_map_preview` | `UiMapPreview` caches by `(family, size, seed, layout_players)`; a seed change while a job runs drops the stale result; an invalid combination yields the `MapGenerator.validate_params` text and no job; the start markers equal `MapData.start_cells` and the Balance-starts button issues `host_set_slot_start(slot_i, fair_slot_order(n)[i])`; cancelling drops the stale result; `UiMapNames.name_for(0, 0x5A17C3E9)` is identical on repeated calls and differs from `name_for(0, 0x5A17C3EA)` |
| `test_ui_picking` | the fixture adapter's picker (`UiPicking`, the reference for `ViewPicker`'s rules): 5 synthetic entities: ray through a unit standing 1 m in front of a building picks the unit; ray behind a wall picks the nearer; tie (< 0.01 m) → non-wreck over wreck, unit over structure, then lowest id; an entity absent from `UiPickData` (fogged) is never picked; `PICK_GHOSTS` returns a remembered structure only when requested; box over 3 units + 1 structure with `PICK_UNITS \| PICK_OWN` returns 3 units; the same box with `PICK_STRUCTURES \| PICK_OWN` returns the structure; box behind the camera excluded. Contract test (runs against the fixture now and against `ViewWorld` when it lands): `UiViewPort.pick` never returns a fog-hidden or contained entity |
| `test_ui_edge_scroll` | 1920x1080 margin 6: `(2,300)→(−1,0)`, `(1919,1079)→(1,1)`, `(−40,300)→(0,0)`, `(960,3)→(0,−1)`, `(6,540)→(−1,0)`, `(7,540)→(0,0)`; `drag_exceeded(thr = 6)`: `(100,100)→(103,104)` distance 5.0 → false; `→(104,104)` 5.66 → false; `→(106,100)` 6.0 → true; `→(105,105)` 7.07 → true |
| `test_ui_context_resolver` | ≥ 60 rows: E1-E10 of 5.7.4; each of rules 1-16 with a positive and a negative case; armed modes (attack-move onto enemy → ATTACK, onto ground → ATTACK_MOVE, unarmed mobile → MOVE; patrol onto ground → PATROL, Shift keeps the mode; follow onto an own or allied unit → FOLLOW(target), onto an enemy / structure / ground / a selected unit → DENIED; guard onto own unit → GUARD(target), onto ground → GUARD(point), onto enemy → DENIED; sell on non-sellable → DENIED; repair sends explicit mode 1 or 0 from `F_REPAIRING`); ghost enemy structure → ATTACK_MOVE for mobile units only; modifiers (`force` on own unit → ATTACK with the forced flag, on ground → FORCE_FIRE; Shift → `queued`); soft exclusion of collectors/MCV/engineers/transports from enemy targets; deny reasons `cannot_hit`, `no_weapon`, `blocked`, `off_map`, `follow_target`; a deposit cell (explored, `deposit_at > 0`) → HARVEST for collectors only, unexplored or depleted cells → MOVE; an airfield click → `RETURN_TO_BASE` with the airfield id; cursor per intent; determinism (same inputs → identical intents, ids ascending); mixed selection produces `extra` intents in rule order |
| `test_ui_cmd_codec` | the golden commands of 6.1 (`describe()` strings and the exact int arrays; the same builders reproduce the six vectors of `sim_core.md` §4.8; the v2.1 rows: `FOLLOW` `[12, 1203, 0, 5, 6]`, `RETURN_TO_BASE` with and without a target, `HARVEST` at a cell centre, `PATROL` / `ATTACK_MOVE` with `flags`, `MOVE` with flag b1 = 2); `verify_against_sim()` returns `[]` (every op the UI builds is `SimCmd.is_known`, its `layout_of` arity equals the one assumed here); Shift sets `mode = 1` only on ops flagged Q and is ignored on the others; `split_ids(450 ids)` → one chunk, `split_ids(600 ids)` → 512/88; `build_place` x/y are whole cells and `mode` the rotation; `use_power` carries the power index; `world_to_sim(45.0, 90.0)=(15360, 30720)`, `(45.7, 90.1)=(15599, 30754)`, negative and > map clamp to `[0, 131071]` on 128 cells; `norm_to_sim(0.5, 0.5)` on 128 = `(65536, 65536)`; angle `roundi(atan2(1,0) × 4096 / TAU)=1024` |
| `test_ui_ev` | every `UiEv` code equals the registry (`SPAWNED 1`, `REMOVED 2`, `OWNER_CHANGED 3`, `CASH 4`, `CMD_REJECTED 5`, `ORDER_FAILED 6`, `PLAYER_ELIMINATED 7`, `MATCH_END 8`, `EV_DEATH 208`, `EV_EMP 213`, `EV_ATTACK_ALERT 214`, `EVT_STRUCTURE_READY 302`, `EVT_POWER_SHORTAGE 311`, `EVT_WARNING 404`, `EVT_SW_READY 405`) and, once the sim classes exist, the `SimEvent` / `SimCombatConsts` / `SimEconConst` constants by name (`verify_against_sim()`); `by_name(&"attack_alert") == 214`; a 10-int record `[type, tick, x, y, a…f]` decodes to the field names of 6.2.1 (e.g. an `EV_DEATH` with `e = (3+1) \| (0+1)<<8` yields killer pid 3, owner 0); unknown types are skipped without an error; every `notices.json` trigger resolves |
| `test_ui_command_bus` | via `UiNetPortRecorder` + `UiSimPortFixture`: every helper emits its golden array; `check_train = NO_PREREQ` → `refused`, nothing sent; 41st command in one turn refused (`REFUSE_RATE`); identical consecutive array in the same turn dropped; observer port refuses all (`REFUSE_NOT_ALLOWED`); `dispatch(intent with extra)` sends primary then extras in order; `queued` sets `mode = QM_APPEND` on ops flagged Q and is ignored on the others; `use_power` sends the power index (the slot only orders the dock); `train_cancel` sends the queue index of the last instance of the def; `unload` sends one command per carrier with its own position; `deploy_toggle` splits deployed / undeployed units; prune of dead ids before send |
| `test_ui_build_model` | for `roster.napc.canada` the VEHICLES tab contains Narwhal and not Guardian; INFANTRY lacks nothing replaced; Titan Gunship absent from AIRCRAFT; every state of the derivation table (5.10.4) produced from fixture data (BUILDING 372 ‰, QUEUED ×2, READY, ON_HOLD from `queue_state` HELD, BLOCKED from `PREREQ_LOST`, LOCKED with `requires_text`, COOLDOWN, DONE); a BUILDING card with `WAIT_FUNDS` keeps its state and shows the "$" chip; ETA under shortage `377 → 754` ticks; **producer picker**: queues (2, 0) → the empty one; equal queues → lowest id; selected producer wins over shorter queue; the primary (`is_primary`) wins over shorter queues; none → −1 |
| `test_ui_notifier` | cooldown suppresses a second `base_attack` within 6 s; `unit_lost` aggregation ("3 units lost"); ribbon merge keeps one ribbon per `rule_id`; `sw_warning_enemy` from an `EVT_WARNING` at tick 15200 whose `strategic_warnings()` record has `exec_tick = 17300` → countdown `(17300 − 15200) / 20 = 105 s` → "1:45" (`UiFormat.mmss`); an `EVT_WARNING` that `strategic_warnings()` does not list posts nothing (not affected); fog rule: an enemy `EVT_POWER_ACTIVATED` at a fogged position posts nothing and at a visible position posts `power_used_enemy`; an `EV_DEATH` of a summon (flag 8) or a decoy (flag 4) posts nothing; **captions**: `on_caption("base_under_attack", …)` within 3 s of a `base_attack` notice adds no line, `on_caption("match_start", …)` adds one INFO line when `audio/captions` is on and none when off; the notifier never calls `announce`; ribbon order DANGER > WARN > OK; `cycle_alert` walks the last 5 alerts younger than 30 s; text keys all resolve |
| `test_ui_tokens` (= art's test U-1 and QA's `test_theme_contrast`) / `test_ui_palettes` | tokens: every `UiPalette` constant equals `style.ui.tokens`, `UiSkin.from_style` equals `style.ui.skins`, `UiTheme.chrome` equals `style.ui.chrome`; contrast from `UiTheme.colors()`: `TEXT`/`BG_PANEL` = 16.30 ± 0.05, `TEXT_DIM` 7.82, `TEXT_MUTE` 5.53 (4.64 on `BG_CONTROL`), `LINE_BRIGHT` 4.28, `TEXT_DISABLED` 3.70, all eight skin accents ≥ 4.5 on `BG_PANEL` (def 4.89 is the minimum), dark text on an accent fill ≥ 4.5 (4.66 minimum); CVD simulation goldens (±1 per channel): `#FF0000` → deut `#A39000`, prot `#6D5F00`, trit `#FF000F`; `#00FF00` → `#EFD63A` / `#FFE500` / `#00F7D9`; `#0000FF` → `#003DFB` / `#0059FF` / `#006B96`; CIEDE2000 (checked against the Sharma-Wu-Dalal reference pairs 2.0425 / 2.8615 / 4.3065 / 1.2644): ΔE2000(`#FF0000`, `#00FF00`) = 86.6 normal, 19.4 deuteranopia, 42.4 protanopia, 75.7 tritanopia; palettes: art's authored minima reproduced within ± 0.5 (default 22.6 / 8.5 / 9.0 / 8.7, CVD 20.8 / 14.5 / 13.8 / 13.5), `P-default` 26.1 / 17.8 / 17.8 / 17.8, the A-01 verdict per set with the `literal` / `narrow` switch of 5.19.3 (art's default set fails `literal` under simulation: the recorded R28 deviation), the CVD semantic set ≥ 21.9 in every simulation; `UiEmblem` draws the 8 faction emblems and 24 sub badges at 16 / 24 / 32 / 48 / 96 px without error (ops inside the unit square, strokes clamped to 1.5 px, deterministic image hash) |
| `test_ui_text` | every `UiText.t(&"…")` literal in `src/ui`, `src/app` exists in `ui_en.json`; interpolation `{address}:{port}`; plural `#one/#other`; missing key returns `⟦key⟧` |
| `test_ui_score` | worked example: `4,200 + 3,000 + 750 = 7,950`; `apm = 72`; zero stats → 0; integer division only |
| `test_ui_logger` | `push_error` captured with the script frame as location; `push_warning` type 1; runtime error type 2; 100 errors from a worker thread all captured into `Log.ring` (256 lines); identical error ×250 logs 1, 100, 200 with counts; storm flag after 50 in 5 s; an empty `script_backtraces` (release build) does not fail; `_log_error` never prints (no re-entry); `AppLogSink` line format `[E] 1234 [net] text`, and the 21st line of one tag within a second is suppressed with a "(+N suppressed)" counter |
| `test_app_crash_report_fields` | `report_header` contains every required field of 5.20.3 (version + build id, engine, OS, arch, CPU, RAM, GPU name / vendor / type / API, rendering method + driver, display server, screen, locale, `user://` path, uptime, phase, match summary, sim tick + checksum, net role) and never an IP address or chat text (fixture with both present); `start_session` on a leftover `.session` writes `crash_<utc>_unclean.txt`; `prune` keeps 20 |
| `test_app_focus_release` | on `APPLICATION_FOCUS_OUT` an active box drag, edge scroll, held keys and the mouse confinement are released; the focus-in click is swallowed; the sim keeps ticking (no pause in a LAN session) |
| `test_ui_bindings_physical` | bindings are stored as physical keycodes; on a fake AZERTY layout the label of `cam_rotate_left` is the layout's letter while the InputMap event still matches the physical Q position; `UiKeymap.dump()` lists every action with contexts and labels (QA's `UiBindings.dump`) |
| `test_ui_unicode_names` | player names with CJK, Arabic and emoji render through the fallback chain without an engine error; sanitised names are ASCII in file names |
| `test_ui_icon_cache` | over `UiViewPortFixture`: `get_icon` returns the placeholder at once and the real texture after `icon_ready` (`changed` emitted once per key); a second request for the same key is a hit; `warm` never queues twice; `pending()` returns to 0 |
| `test_ui_cursors` | 17 states map to 17 distinct `Input.CursorShape` slots (+ 2 variants on CROSS); `set_state` unchanged → no call; sizes 32/48/64 hotspots scale; the 8 scroll arrows swap onto the ARROW slot only when the direction changes (`set_scroll` with the same direction → no call) and `set_scroll(Vector2i.ZERO)` restores the default arrow |
| `test_ui_options_schema` | every schema row of 4.8.1 appears on exactly one options page; a row whose capability guard fails is disabled with a tooltip (hidden only for `video/renderer` when `AppRelaunch.supported()` is false); Revert restores the values seen when the page opened; the 15 s "Keep these settings?" countdown answers itself with Revert |
| `test_ui_fixture_port` | `UiSimPortFixture` obeys the `UiSimPort` contract (used by all other tests): advancing ticks re-derives progress linearly, events fire at `at_tick` |

### 10.3 Labs (async tests, `SubViewport` 1920x1080 unless stated)

| Lab | Assertions |
|---|---|
| `test_ui_lab_input` | the spike's cases A-S as asserted facts: HUD root IGNORE lets world clicks reach `_unhandled_input`; STOP/PASS variants fail as documented; drag started in the world and released over the sidebar still emits one `select_box`; RMB over the sidebar emits no `context_click`; wheel over the sidebar emits no zoom (with `mouse_force_pass_scroll_events = false`); `FOCUS_NONE` buttons never consume arrows/Space; focus loss cancels the gesture; lost release cancels via `_process` polling (non-synthetic mode) |
| `test_ui_lab_input2` | **new**: `Alt+Q` does not rotate the camera (exact polling) and triggers `card_1`; `Ctrl+1` triggers only `group_assign_1`; own double-click detector fires at 349 ms/7 px and not at 351 ms or 9 px; a focused `LineEdit` suppresses camera keys and `Esc` closes it; opening a modal cancels an active drag; minimap drag keeps emitting outside the rect; card RMB emits `build_hold_requested`, second RMB `build_cancel_requested`; edge scroll off when the window is unfocused |
| `test_ui_lab_layout` | for window sizes {1024x576, 1280x720, 1366x768, 1920x1080, 2560x1440, 3840x2160} x `video/ui_scale` {1.0, 1.5, 2.0} (QA A-03 audit): sidebar width == 348 ± 0.5 logical; no HUD control extends beyond the viewport; selection panel inside the playfield and ≥ 600 wide; minimap side per formula; ribbons centred in the playfield; queue strip/footer hidden iff COMPACT; key labels (`Label.get_minimum_size()`) fit their rects for the longest English strings of `ui_en.json` (pseudo-loc test: every string through `TranslationServer.pseudolocalize`, +40 % length, still fits menu buttons via ellipsis, no overlap; QA A-18) |
| `test_ui_lab_widgets` | a BUILDING `UiBuildCard` issues ≤ 1 `queue_redraw()` per displayed second (counter hook); a READY card ≤ 60/s; `UiCreditTicker` stops `_process` when settled; `UiPowerBar` idles when usage ≤ capacity; `UiRibbon` allocates no `UiStyleBox` per redraw (object count stable over 200 frames) |
| `test_ui_lab_menu_nav` | Tab / Shift+Tab / arrows / Enter / Esc traverse the main menu, lobby, options and dialogs; the focus ring is visible (styled focus exists); Tab is free in GAME context and restored after |

### 10.4 Scenario tests

| ID | Setup | Expected |
|---|---|---|
| S1 | headless `--autostart=match --with-ui`, 2 AIs + scripted human via `UiCommandBus` (`train`, `build_start`, `build_place`, `attack_move`), 6,000 ticks, real sim | 0 engine errors; `refused == 0`; within 40 ticks of `train` the item state is BUILDING/QUEUED; the human's `sent` commands equal the commands decoded from the recorded replay |
| S2 | `UiScreenLobby` over a LOCAL lobby: set every `StartError` condition | each yields its text key and highlight target of 5.14.4; the seed field accepts `5A17C3E9` and rejects `XYZ` |
| S3 | `AppMatchJob` with a fake sim builder | progress is monotonic 0 → 100, phase names in order SIM, VIEW, ICONS, PREWARM, `error()` empty; a failing builder → `error()` set → `AppCrash` FATAL(WORLD_BUILD_FAILED) |
| S4 | `UiScreenEnd` from a summary dictionary (4.9.2) | banner text per outcome, per-player rows sorted by score, graphs draw one polyline per player |
| S5 | replay UI over `NetReplayPlayer` with a golden fixture replay | speed chips change `set_speed`; drag on the seek bar calls `seek_tick`; `verify_failed` shows the banner exactly once |
| S6 | settings persistence across two `gd run` processes | values written by process 1 are read by process 2; `--fresh-settings` leaves the file untouched |
| S7 | crash sentinel: start, `kill -9`, restart | `crash_<utc>_unclean.txt` exists with the header fields; the toast offers *Open logs folder* / *Copy report*; `recover_orphans()` produced `crash_<unix>.mfreplay` and the toast adds *Watch recovered replay*; a clean quit leaves no `.session` |
| S8 | LAN flow with `NetTransportLoopback` sessions (host + client objects in one process) | browser lists the announced game; join → lobby; client `set_ready` reflected on the host row; mismatching `data_hash` → the join dialog shows both hashes as `%08X`; host start → both reach `match_started` |

### 10.5 Determinism tests

* **D1** run the same scripted UI session (`--script-cmds`) twice: identical `UiNetPortRecorder.sent` commands (`describe()` strings) and identical final checksum/chain.
* **D2** the same script through a LOCAL session and through `NetReplayPlayer`: identical final checksum.
* **D3** the same match with HUD + presenter + input controller attached versus headless without them: identical checksum chain (proves the UI never mutates the sim).
* **D4** `AppMatchJob(with_view = true)` versus `(false)`: identical `adapter.checksum_now()` and `map_hash()`.

### 10.6 Visual tests (screenshots inspected with the image reader; `tools/gd shot res://src/app/boot.tscn out.png --size WxH --frames N -- --screen=<id> …`)

Every shot is read by an agent against the checklist below. The matrix: screens x {1280x720, 1920x1080, 3840x2160} x `video/ui_scale` {1.0, 1.5} x renderers {forward_plus, mobile, gl_compatibility} where marked; **minimum set (40 shots):**

| ID | Args | Check |
|---|---|---|
| V-menu-{fwd,mob,gl} | `--screen=main_menu --faction=napc` | backdrop lit, wordmark crisp, buttons aligned, featured card readable |
| V-menu-han | `--faction=han` | jade skin applied |
| V-splash | `--screen=splash` | wordmark, progress text |
| V-lobby-skirmish-{720,1080,4k} | `--screen=lobby --fixture=lobby_skirmish` | 8 rows, pickers, briefing with UNIQUE badges, map preview, rules, START |
| V-lobby-dropdown | `--popup=1` | popup themed, embedded |
| V-lobby-lan-host / -client | `--fixture=lobby_lan` | chat, ping, kick, ready, incompatible colour |
| V-lobby-errors | `--fixture=lobby_errors` | inline red error + highlight |
| V-lobby-colours | `--fixture=lobby_skirmish` (+ `--palette=cvd`) | swatch hex from `ViewStyle`, player numbers and pip shapes, plate-contrast hint under a low-contrast row, the CVD hint under the grid, 8 swatches in `cvd` |
| V-lan-browser | `--screen=lan_browser --fixture=lan_games` | compatible / OLD / DATA / full rows, detail card, direct connect |
| V-explainer | dialog | OS-specific firewall text |
| V-loading | `--screen=loading --fixture=loading` | per-player bars, tip, phase label |
| V-hud-mid-{720,1080,4k,ui150} x {fwd,mob,gl} | `--screen=game --fixture=hud_mid_match` | every card state visible (AVAILABLE, BUILDING, QUEUED, READY, ON_HOLD, LOCKED, UNAFFORDABLE, COOLDOWN, BLOCKED, DONE), tooltip, brackets, bars, ribbons, minimap, group bar |
| V-hud-lowpower | `--fixture=hud_low_power` | flashing bar, LOW POWER ribbon, ETA doubled, BLOCKED powers |
| V-hud-sw-warning | `--fixture=hud_superweapon_warning` | DANGER ribbon with countdown, warning zone, minimap ring |
| V-hud-placement | `--preview=place` | ghost, rings, reason text |
| V-hud-targeting | `--preview=power` | circle preview, cursor variant |
| V-hud-2factories | `--fixture=hud_two_factories` | producer switcher, queue strip |
| V-hud-observer | `--fixture=hud_observer` | perspective bar, scoreboard |
| V-hud-strategic | `--fixture=hud_mid_match --preview=zoomout` | class-glyph markers in owner colours below 18 px per metre, hidden when `ui/strategic_markers` is off, brackets untouched |
| V-hud-blips | `--fixture=hud_mid_match` (+ `--palette=cvd`) | class-shaped minimap blips (dot / square / diamond / triangle / outlined square / star), pip shapes on structure blips in `cvd` |
| V-cursors | `--preview=cursors` | the 17 base cursors, the 2 reticles and the 8 scroll arrows on a dark and a light background, 32 / 48 / 64 px |
| V-hud-sidebar-left | `ui/sidebar_side=1` | mirrored layout |
| V-end-victory / -defeat | `--screen=end --fixture=end_*` | banner, table, graph |
| V-replays / V-replay-view | `--screen=replays`, `--fixture=replay_view` | list states, transport bar |
| V-fm-{overview,unit,structure,power,tree,compare} | `--screen=field_manual` | resolved stats, delta markers, floors, tree layout |
| V-options-{graphics,audio,controls,interface,network} | `--screen=options --page=…` | rows aligned, disabled-by-renderer tooltip, keybind table |
| V-cb-cvd | `--palette=cvd` on lobby + HUD | swatches distinguishable, pip shapes and structure blips visible, semantic colours readable |
| V-highcontrast | `access/high_contrast_hud` | borders, opacity |
| V-dialogs | game menu, confirm, desync, stall prompt, unclean-exit toast, fatal | layout, buttons |

**Registration with QA.** Every row above is a case in QA's registry `game/tests/visual/cases.json` (`qa.md` §7.6) with `"owner": "ui"`: `scenario` = the UI fixture (`tests/fixtures/ui/<name>.json`), `ui` = `{scale, hud, colour_mode}`, `quality`, `size`, `renderer`, and `checks` drawn from the checklist ids the shot can decide (V-H01 overlap and margins ≥ 16 px at 1280x720, V-H02 clipped text and effective font ≥ 14 px at 1080p, V-H03 every build icon present, V-H04 tooltips fully on screen, V-M01 focus / hover / disabled states and no untranslated keys, V-X01 body contrast, V-A01 colour-blind separability with shape cues, V-S02 placement ghost distinguishable without colour, V-ID1 no data ids visible, V-IP1 no real-world marks). The UI supplies the scenes and deterministic fixtures; QA supplies capture (`gd shot ... --frames 60`), the automatic checks VA-1..VA-5, the review records and the goldens. Reviewers never review their own change.

Review checklist: no clipped or overlapping text; alignment on the 4-pt grid; contrast; icons crisp at scale 1.5 and 2.0; faction tint correct; nothing depends on colour alone; popup/tooltip visible; ribbons stack in the right order; no placeholder or debug text.

### 10.7 Performance tests

`game/tests/ui/ui_bench.gd` (`tools/gd run … -- --bench=hud`): builds the HUD over `UiViewPortFixture` with 400 entities, 100 cards and 40 selected; prints `PERF ui_frame_ms=… overlay_ms=… minimap_ms=… presenter_ms=… draw_calls=…`. Gates: typical ≤ 2.0 ms Forward+ / ≤ 4.0 gl_compat; regression > 25 % versus `game/tests/golden/ui_perf.json` fails.

### 10.8 Gates

`tools/gd check` clean for `src/ui`, `src/app`, `tests/ui`; `tools/gd test ui` < 30 s including the labs (each < 5 s); D1-D4 in CI; the visual set reviewed before a release candidate and after any change to `UiTheme`/widgets; `test_ui_text_keys` and `test_ui_palettes` are release gates.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Common Definition of Done (ARCHITECTURE Appendix B): `tools/gd check` clean; the listed tests and labs pass via `tools/gd test ui`; static typing everywhere; `##` docs on public API; no `print` (use `Log`); no `TODO` without `TODO(ui)`/`TODO(app)`; stubs `push_error("NOT IMPLEMENTED: …")`; screenshots inspected with the image reader and the checklist of 10.6. Line counts include tests. Paths as in section 2. **No task waits on sim, view or audio**: UI-04 delivers the fixtures first, and the production adapters are wired in UI-15 (or earlier as those domains land, guarded by the shared contract tests).

| ID | Task | Files owned | Depends on | Acceptance tests | ~Lines |
|---|---|---|---|---|---|
| **UI-01a** | Design system core: tokens asserted against `style.ui.tokens`, skins from `ViewStyle` + the CVD semantic set, fonts, `UiStyleBox`, `UiTheme` / service, layout / motion / a11y helpers | `ui_palette ui_metrics ui_skin ui_skin_set ui_fonts ui_style_box ui_draw ui_theme ui_theme_service ui_layout ui_motion ui_a11y ui_focus_policy`; vendored fonts + `OFL.txt` (`assets/fonts/*`); tests `layout tokens palettes` | core `Log`; art `style.json` + `ViewStyle` (a stub `ViewStyle.from_dict` with the 18 tokens until art lands) | contrast ratios of 4.6.4, CVD goldens and the palette verdicts (5.19.3), layout table (5.4.1), theme build ≤ 10 ms first / 0.3 ms warm, style sheet screenshot | 2,500 |
| **UI-01b** | Glyphs (55), emblems on art's op lists, text / number formatting, procedural cursors (17 base + 2 reticle + 8 scroll) | `ui_glyphs ui_emblem(+view) ui_text ui_format ui_cursors`; `data/text/ui_en.json` (seed), `data/ui/cursors.json`; tests `format text cursors` (the emblem checks live in `test_ui_palettes`) | UI-01a | emblem renders at 16 / 24 / 32 / 48 / 96 px for the 8 emblems and 24 badges, glyph sheet, cursor sheet V-cursors, `test_ui_text_keys` seed | 1,900 |
| **UI-02a** | Widget core: screen base, layer root, dialog stack + dialog, toast, tooltip body, icon button, tab bar, list row, panel header / chip, select rectangle, vignette | `ui_screen ui_layer_root ui_dialog_stack ui_dialog ui_toast ui_tooltip_body ui_icon_button ui_tab_bar ui_list_row ui_panel_header ui_progress_chip ui_select_rect ui_vignette` | UI-01a | `lab_widgets` (core part), `lab_menu_nav` (widget part), widget sheet screenshots at 1.0 / 1.5 scale in 3 renderers | 1,850 |
| **UI-02b** | HUD and option widgets: build item / card + clock sweep, credit ticker, power bar, queue strip, ribbon, group bar, roster strip, option rows, key-bind button | `ui_build_item ui_build_card ui_cooldown_sweep ui_credit_ticker ui_power_bar ui_queue_strip ui_ribbon ui_group_bar ui_roster_strip ui_choice_row ui_slider_row ui_toggle_row ui_keybind_button` | UI-01a, UI-01b, UI-02a | `lab_widgets` (HUD part), ≤ 1 redraw/s on a BUILDING card, ticker worked numbers (5.10.7), card anatomy screenshots (tier badge, role glyph) | 2,000 |
| **UI-03a** | Settings and persistence: launch args, settings store / schema / apply (crash-safe writer), graphics glue and renderer relaunch | `app_launch_args app_settings app_settings_store app_settings_schema app_apply app_graphics app_relaunch`; tests `settings apply launch_args` (incl. `test_app_settings_atomic_write`, `test_app_window_clamp`) | UI-01a (`UiLayout`); core `Log` | 10.2 rows for settings / apply / launch_args; interrupted-write recovery at every step; colour / quality key translation of 5.19.3 | 2,300 |
| **UI-03b** | Boot, flow, state, scenes: boot scene + `AppBoot` + extended `--smoke` + QA hooks, flow graph, state, scene layers / transitions / modal host, screen registry, profile, paths, info | `boot.gd boot.tscn app_boot app_flow app_state app_scenes app_screens app_profile app_paths app_info`; tests `flow boot focus_release` | UI-01a, UI-02a (screen base, layer root), UI-03a, UI-03c | boot timeline within 5.2.1 budgets, extended `--smoke` line, `test_app_focus_release`, crash-sentinel scenario S7 | 2,200 |
| **UI-03c** | Logging and crash: `AppLogSink`, `AppLogger`, `AppCrashReporter`, `AppCrash`, `AppFileLayer` | `app_logger app_log_sink app_crash_reporter app_file_layer app_crash`; tests `logger crash_reporter` (incl. `test_app_crash_report_fields`) | core `Log.sink` `[XR-39]` | worker-thread logger test (E2), report header fields, retention, rate limiter, error-storm flag | 1,100 |
| **UI-04a** | Sim, net and audio ports and their fixtures / recorders / null adapters, entity row / snapshot, `UiEv`, fixture JSON loader and fixture files | `ui_sim_port ui_sim_port_fixture ui_entity_row ui_entity_snapshot ui_net_port ui_net_port_session ui_net_port_recorder ui_net_port_null ui_audio_port ui_audio_port_snd ui_audio_port_null ui_audio_port_recorder ui_ev`; `tests/fixtures/ui/*.json`; `contract_ui_sim_port.gd` (shared contract test for fixture and world adapters) | sim SC-04 skeleton and SC-07 (`SimCmd`: `is_known`, `layout_of`, builders — `verify_against_sim` and `describe` need them; the recorder stores plain int arrays and needs nothing) | `test_ui_fixture_port`, `test_ui_ev`; contract test green on the fixture | 2,150 |
| **UI-04b** | View port and the fixture battlefield: interface, fixture adapter (procedural battlefield lifted from the spike's `DemoWorld` / `DemoModels`, 2D stand-ins for rings / bars / lines / ghost), pick data, reference picking | `ui_view_port ui_view_port_fixture ui_pick_data ui_picking` | UI-04a, UI-01a | fixture battlefield renders; picking reference cases (ray 127 µs, box 92 µs at 439 entities); overlay / picking alignment lab | 2,240 |
| **UI-05** | Match glue: `AppNet`, event fan-out, `AppAudio`, `AppMatch`, composite `AppMatchJob`, `AppMatchContext`, headless test boot | `app_net app_events app_audio app_match app_match_job app_match_context app_test_boot` | UI-03b, UI-04a; net NET-10 (real `NetSession`; loopback earlier), sim/map `[XR-12]` (fake builder until then), audio (the `Snd` facade; `AppAudio` degrades to a no-op adapter until it lands) | S3, S6, D4 (with a fake sim), `--autostart=match` prints `APP_READY` / `APPTEST` lines and exits 0 on the fake adapter | 2,300 |
| **UI-06a** | Menus, dialogs, loading: splash, main menu with the 3D showcase, loading screen + tips, credits, fatal screen, generic dialogs, first-run dialog | `ui_screen_splash ui_screen_main_menu ui_screen_loading ui_screen_credits ui_screen_fatal ui_dlg_message ui_dlg_confirm ui_dlg_text_input ui_dlg_key_conflict`; `data/text/credits.json`, `data/text/tips_en.json` | UI-01a, UI-01b, UI-02a, UI-03b; view `[XR-19]` showcase (fixture until then) | `lab_menu_nav`, V-menu-*, V-splash, V-loading, first-run flow | 1,850 |
| **UI-06b** | Options: schema-driven pages, keybind table, apply / revert | `ui_screen_options ui_options_page_*` (graphics, audio, controls, interface, network) | UI-02b, UI-03a, UI-09a (keymap) | V-options-*, "Keep these settings?" revert test, `test_ui_options_schema` (every row reachable, guards hide rows) | 1,600 |
| **UI-07a** | Lobby core (skirmish + LAN host / client): screen, slot rows, rules panel, chat | `ui_screen_lobby ui_lobby_slot_row ui_lobby_rules_panel ui_lobby_chat`; `data/ui/skirmish_presets.json` | UI-02a, UI-02b, UI-04a; net NET-5/6/7/10, `[XR-20]`; art `ViewStyle` swatches / hints `[XR-49]` | S2, S8, V-lobby-skirmish, V-lobby-lan-*, V-lobby-errors, V-lobby-colours; every `StartError` mapped | 1,900 |
| **UI-07b** | Lobby briefing and map panel, map preview, LAN browser and its dialogs | `ui_lobby_briefing ui_lobby_map_panel ui_map_preview ui_map_names ui_screen_lan_browser ui_dlg_host_game ui_dlg_join_rejected ui_dlg_firewall_help`; `data/text/map_names_en.json` | UI-07a, UI-14; data DATA-08; map `MapGenJob` `[XR-31]`; view `bake_map_preview` `[XR-19]` | V-lan-browser, V-explainer; roster tokens resolve; preview cancel / cache behaviour; Balance-starts button | 2,100 |
| **UI-08a** | Sidebar, build cards, production and power UI | `ui_hud ui_sidebar ui_build_model ui_producer_picker ui_top_strip ui_power_dock` | UI-02b, UI-04a | `test_ui_build_model`, V-hud-mid (all card states), V-hud-2factories, V-hud-lowpower | 2,040 |
| **UI-08b** | Placement, targeting and the presenter | `ui_placement ui_targeting ui_hud_presenter` | UI-08a, UI-09b, UI-09c | V-hud-placement, V-hud-targeting, presenter cadence test (5.10.1), rotation of the Dock | 1,620 |
| **UI-09a** | Input controller, keymap, actions, control groups, bookmarks | `ui_input_controller ui_actions ui_keymap ui_control_groups ui_bookmarks`; `data/ui/keymap_defaults.json` | UI-01a, UI-04a | `test_ui_keymap groups edge_scroll`, `lab_input`, `lab_input2` (spike cases A-S) | 2,340 |
| **UI-09b** | Selection model and modes: selection, capabilities, selection actions, targets / intents, armed modes | `ui_selection ui_selection_info ui_unit_caps ui_selection_actions ui_target ui_order_intent ui_modes` | UI-04a | `test_ui_selection` (survival of death, successor rule), `test_ui_selection_actions` | 1,470 |
| **UI-09c** | Contextual resolution and the command path: resolver, command bus, codec, feedback | `ui_context_resolver ui_command_bus ui_cmd_codec ui_feedback` | UI-04a, UI-09b; sim SC-07 (`SimCmd` builders incl. `follow`) | `test_ui_context_resolver` (≥ 60 rows), `test_ui_cmd_codec` (goldens of 6.1), `test_ui_command_bus` | 2,200 |
| **UI-10** | Bottom panel, minimap, small 2D overlay (incl. strategic-zoom markers), camera pad and Select menu | `ui_bottom_panel ui_selection_panel ui_selection_view ui_command_bar ui_ability_bar ui_minimap ui_minimap_feed ui_world_overlay ui_order_markers ui_camera_pad ui_select_menu` | UI-02, UI-04, UI-08a, UI-09; view `px_per_metre` / `project_points` `[XR-19]` | V-hud-* (selection, minimap, order markers, V-hud-strategic, V-hud-blips), `ui_bench` UI overlay ≤ 0.05 ms and strategic markers ≤ 0.5 ms | 2,350 |
| **UI-11** | Notifications, chat, net overlays and in-match dialogs | `ui_notifier ui_notice_rules ui_ribbon_stack ui_log_feed ui_chat_overlay ui_stall_overlay ui_pause_banner ui_net_overlay ui_dlg_game_menu ui_dlg_stall_prompt ui_dlg_desync ui_dlg_save_replay`; `data/ui/notices.json` | UI-08a, UI-05; net signals | `test_ui_notifier`, fog-rule and caption de-duplication cases, V-dialogs, V-hud-sw-warning, chat plain-text test (BBCode string renders literally) | 2,040 |
| **UI-12** | Field Manual | `ui_screen_field_manual ui_fm_model ui_fm_tech_tree ui_model_viewer` | UI-02, UI-14; data DATA-08 (`DefBrowser`); view `[XR-19]` | golden `UiFmModel` output vs `DefBrowser` cards; V-fm-*; search and compare behaviour | 2,000 |
| **UI-13** | End screen, replays, observer and scoreboard | `ui_screen_end ui_match_stats ui_score ui_screen_replays ui_replay_bar ui_observer_bar ui_scoreboard` | UI-10; net NET-8; sim `[XR-6]`, `[XR-7]` | S4, S5, `test_ui_score`, V-end-*, V-replays, V-hud-observer | 2,060 |
| **UI-14** | Icon service and style baking | `ui_icon_cache` (handles over the view's icon service), `ui_icon_baker` (fixture only), `ui_style_bakery` (optional 9-slice) | UI-01a, UI-04b; view `[XR-19]` (fixture baker until then) | `test_ui_icon_cache`; fixture baker ≤ 3 ms/icon warm at 188 x 124; `prewarm()` behind the splash; with the real view: placeholder → texture within 2 frames of `icon_ready` | 500 |
| **UI-15** | Integration and polish: game screen, production adapters, full visual suite, perf and accessibility passes, renderer matrix, manual OS checklist | `ui_screen_game ui_sim_port_world ui_view_port_world`; `ui_bench`; goldens | all UI tasks; sim, view, audio, net delivered | S1, D1-D3, full 10.6 matrix on 3 renderers, perf gates 10.7, manual checklist on a real Mac / Windows / Debian (R3, R4, LAN permission flows) | 2,260 |

**Order and parallelism.** UI-01a first → {UI-01b, UI-02a, UI-03a, UI-03c, UI-04a} in parallel → {UI-02b, UI-03b, UI-04b, UI-09a, UI-09b, UI-14} → {UI-05, UI-06a, UI-06b, UI-07a, UI-08a, UI-09c} → {UI-07b, UI-08b, UI-10, UI-11, UI-12, UI-13} → UI-15. Milestones: **M-UI0** (UI-01a..04b, UI-14) fixture-driven widgets, ports and fixtures; **M-UI1** (UI-05..UI-09c) menus, lobby, sidebar and input on fixtures + net loopback; **M-UI2** (UI-10..UI-13) complete UI on fixtures; **M-UI3** (UI-15) real sim / view / audio. Total ≈ 49,000 lines including tests and fixtures (the source files of section 2 add up to ≈ 36,600 lines; tests, labs and fixture code make up the rest; the spike's 6,094 lines contribute ≈ 3,500 lines of directly liftable `ui/` code). Every task is sized ≤ ~2,500 lines including its tests, the unit an implementing agent can finish and review in one pass.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / question | Recommended resolution |
|---|---|---|
| R1 | The sim-core kernel API is specified (`sim_core.md` v2) but the production / power / strategic read helpers and several events are still proposals in the economy / abilities specs (and v2 dropped a few v1 events); the UI is the largest consumer | ports + fixtures (decision 1); `UiSimPortWorld` (table 3.2.4) is the only file to change; a shared contract test (`contract_ui_sim_port.gd`) runs against fixture and world adapters; align names with `AiWorldView` so the reconcilers can publish one `SimReadApi`; missing events degrade to polled state (6.2.1) |
| R2 | `render.md`'s `ViewCamera` reads `Input` itself by default (`auto_input = true`, `cam_*` actions registered at runtime, wheel / MMB) — two owners of input | the UI sets `auto_input = false` and calls `pan_screen / rotate_yaw / tilt / zoom_by / focus_on_sim` (`[XR-13]`); the rebindable `UiKeymap` is the only owner of the `cam_*` actions; the view's `camera/wasd_pan` option becomes rebinding |
| R3 | macOS reports Ctrl+click as right click (engine source behaviour; cannot be verified in this environment) | per-OS gesture modifiers (force-fire = Option on macOS), no Alt gestures, all rebindable; **manual verification on a real Mac is an acceptance item of UI-15** |
| R4 | Custom cursor image size on HiDPI displays (points vs pixels) unknown | `access/cursor_scale` setting (32/48/64), system-cursor fallback, cursor sheet screenshot + manual check in UI-15 |
| R5 | The command and event vocabulary moved between sim_core v1 (hex master + alias column) and v2 (decimal domain blocks, events with `x, y` slots); `audio.md` and `render.md` still quote v1, and the domain specs use their own field letters | the UI follows v2; every op number lives in `UiCmdCodec` and every event code / offset in `UiEv`; `verify_against_sim()` checks both against `SimCmd.is_known` / `layout_of` and the event constants, so a reconciler decision costs one file each; column 6 of 6.2.1 is the v1 → v2 crosswalk for the sweep of the other specs |
| R6 | `Alt`+letter card hotkeys: ergonomics, OS conflicts (Alt+Tab, window managers) | rebindable; optional `input/sidebar_hover_hotkeys`; Alt+letter is not used by Windows/macOS/Linux shells except Alt+Tab/F4; monitor playtests |
| R7 | Accessibility coverage of custom-drawn widgets (AccessKit gets no semantic tree from `_draw`) | `accessibility_name/description` on every widget (cheap), text mirrors of audio, keyboard navigation in menus; real screen-reader testing is outside this environment — flag as best effort |
| R8 | Project `stretch/mode = canvas_items` + 1920x1080 base conflicts with the verified scale rule | `[XR-40]` sets `disabled`; until then the UI would double-scale — `UiLayout.apply` asserts the mode and logs an error if it is not `disabled` |
| R9 | First 3D bake/pipeline compile stalls 2.6-3.3 s (cold; `render.md`: first icon 2.7 s on a cold Metal cache) | `UiViewPort.prewarm()` behind the splash, the view's material prewarm inside `build_async` behind the loading screen; never bake on first click |
| R10 | gl_compatibility HUD is CPU-bound (683 draw calls) | `UiHud.lite`, minimap 15 Hz, fewer glows; measured in UI-15 on the compat renderer; the view's own overlays are instanced quads and budgeted in `render.md` §9 |
| R25 | The interaction visuals now depend on the view (selection rings, health bars, lines, ghost); if the view slips, the HUD has none | `UiViewPortFixture` implements the whole contract with the spike's 2D overlay, so the HUD, the tests and the screenshots never wait; `ui/brackets` and `video/health_bars` can switch the view's overlays off |
| R26 | `video/renderer` needs a restart: `OS.create_process` of the running executable may fail or loop (sandboxed macOS bundles, packaged Linux installs) | one relaunch guarded by `--renderer-relaunched`; a failed `create_process` (−1) keeps the running renderer and shows a message; manual check on the three OSes in UI-15 |
| R27 | The view's `colour_mode` vocabulary (`normal`, `protan`, `deutan`, `tritan`, `high_contrast`) predates art's single colour-vision-safe set and has one exclusive high-contrast slot; art R-1 changes the team-uniform path | `AppApply.quality_config` writes `normal` / `deutan` + `cvd_palette` + the separate `high_contrast_hud` boolean (5.19.3); `[XR-14]` asks the view for the `cvd` boolean pair |
| R28 | Art's *default* team set does not meet QA A-01 under colour-vision simulation (authored minima 8.5 / 9.0 / 8.7 against ≥ 12; art's rendered minima are lower still: 6.2-8.0 default, 9.9-12.6 CVD, after tone mapping) | recommended: narrow A-01 to "default ≥ 20 normal; CVD set ≥ 20 normal and ≥ 12 simulated" (no colour change); alternative: swap in `P-default` (26.1 / 17.8 / 17.8 / 17.8, 5.19.3). Either way the CVD set is prominent (first run, lobby hint) and the pip shapes, player numbers and owner tooltips are the second channel; `test_ui_palettes` carries a `literal` / `narrow` switch (`[XR-49]`) |
| R29 | The sibling specs were still changing while this one was written (`sim_core.md` v2.1 at 16:57, `terrain_movement.md` at 17:13, `art_direction.md` at 16:28); `audio.md` and `render.md` still speak sim_core v1 (hex events, `ViewTeamColors`, `MapImages`) | every dependency sits behind a port or a one-file adapter (`UiCmdCodec`, `UiEv`, `UiSimPortWorld`, `UiViewPortWorld`, `UiSkinSet`, `AppApply.quality_config`); `verify_against_sim()` and the shared contract test catch drift the day a sibling changes; the sweep items are collected in `[XR-5]`, `[XR-14]`, `[XR-34]`, `[XR-49]` |
| R11 | Colour-vision sets are validated by CIEDE2000 in simulated space only (Machado 2009, severity 1.0), on authored colours | acceptance numbers are tests; art review + real user feedback; the pip shapes add a second channel; art's authored-to-rendered drift (mean 5.4, max 8.8 ΔE00) is measured by art's screenshot boards, so the visual review (V-U02) must confirm the sets still read as team colours on terrain |
| R12 | LAN permission flows (macOS 15 Local Network, Windows Defender) cannot be exercised here | explainer before first socket, silence hints, manual checklist on real machines (net R1-R3) |
| R13 | The composite loading job weights may be off (the bar could stall at 55 % or 95 %) | UI-05 measures phase timings on the three OSes and re-tunes; the bar never goes backwards (`max(previous, computed)`) |
| R14 | `UiStyleBox` cost if applied to many redrawing panels | rules 5.19.6; optional 9-slice baking task (UI-14) with a 0.5 ms/frame trigger |
| R15 | Spike `REPORT.md` is missing on disk | this spec re-derives the findings from the spike code/screenshots; ask the spike owner to restore it under `prototypes/ui/REPORT.md` (documentation only) |
| R16 | Localisation is English-only but strings are externalised; text expansion, RTL and CJK fonts are untested | `test_ui_lab_layout` pseudo-localisation (×1.4 length) keeps layouts honest; fonts are Latin-only (Rajdhani has Indic glyphs, no CJK) — out of scope for v1 |
| R17 | Selection can hold at most `MAX_SELECT` entities; commands must stay under the 64-commands-per-turn limit | `MAX_SELECT = 500` (= maximum unit cap) fits one command (id cap 512, size cap 1024 ints), per-turn budget 40, duplicates dropped |
| R18 | The Windows/Linux window-manager or OS may steal focus when the LAN permission prompt appears | gestures/edge scroll cancel on any focus loss; nothing waits on the prompt |
| R19 | Error-storm handling could hide a real crash loop | the storm flag only toasts; every error still goes to the log; the `.session` sentinel detects real crashes |
| R20 | Replay verify UI on a different build shows "diverged" although the replay is fine for viewing | banner text says "recorded on a different build?" (net R14); the viewer keeps playing |
| R21 | `Logger` callbacks arrive on worker threads | mutex + deferred UI callbacks; unit test with a worker thread (E2) |
| R22 | Event vocabularies written before and after sim_core v2 disagree (audio maps v1 hex events; economy lost several v1 events) and audio owns the announcer | the UI consumes only v2 names, derives what it can from polled state, never announces (decision 16) and de-duplicates captions by `announcer_line`; the reconcilers sweep `audio.md` §6.2 with the alias column of 6.2.1 (`[XR-5]`, `[XR-34]`) |
| R23 | Announcer lines could play twice (UI notifier and audio's event→sound map) | resolved by ownership: audio speaks (audio.md §3.11), the UI shows notices and captions; the notifier has no voice call at all |
| R24 | The kernel's `ATTACK` needs a currently visible target (combat's executor may accept known targets, `combat.md` §5.10.6); remembered ghosts cannot be attacked directly under the kernel rule | rule 11 issues `ATTACK_MOVE` to the ghost for mobile units (question Q12) |
| Q1 | Sidebar (C&C classic) vs per-structure command cards? | **Sidebar** (bible/ARCH: "sidebar build tabs"); cards hotkeys via Alt+grid; sidebar side switchable |
| Q2 | Should `Esc` clear the selection? | No by default (menu first); `input/esc_clears_selection` |
| Q3 | Should the LOCAL game pause while menus are open? | Yes by default (`pause_on_menu`), never in multiplayer |
| Q4 | Minimap gated by Radar/power? | No (bible silent, decision 10); revisit only if the sim exposes `radar_online` |
| Q5 | Gamepad? | Not required; menus are keyboard navigable; a gamepad layer can reuse `UiKeymap` contexts later |
| Q6 | Named skirmish presets and save/load of lobby setups? | v1: last state + 4 shipped presets; named user presets are trivial to add (`game/skirmish_preset`) |
| Q7 | Tutorial / campaign UI | out of scope (bible is skirmish/LAN only) |
| Q8 | In-game surrender in a 1v1 LOCAL game ends the match immediately? | `T_RESIGN` defeats the local player; with only AIs left the sim ends the match → end screen (VICTORY for the last team) |
| Q9 | Should the AI difficulty labels show the Brutal cheat text? | Yes: `ai.cheats.brutal` next to the level name (AI spec §5.14.1) |
| Q10 | Are 8 sidebar tabs too many? | Tabs of a roster with nothing in them (e.g. NAVAL before a Dock) stay visible but dimmed with a tooltip; keeps hotkey positions stable |
| Q11 | Who speaks event-driven announcer lines, the UI notifier or the audio module's own event→sound map? | Audio (`audio.md` §3.11: "the UI must not also announce …"); the UI shows the ribbons, log lines, pings and arrows, plus the captions of lines no notice covers (5.13.1) |
| Q12 | May players attack a remembered (ghost) structure directly? | Not with `ATTACK` under the kernel rule (visibility required); the UI sends `ATTACK_MOVE` to the ghost position; if combat's executor accepts known targets (`combat.md` §5.10.6) only rule 11 changes |
| Q13 | Does A-02 apply to disabled text and to decorative borders? | Disabled text (`TEXT_DISABLED` 3.70 : 1) is treated as WCAG-exempt but held to ≥ 3 : 1; the normal-state button border `LINE` (1.98 : 1) is decorative because the label (≥ 4.5 : 1) and the fill identify the control, so `UiTheme.colors()` marks it `decorative`; hover / pressed / focus borders use the accent (≥ 4.9) and the high-contrast HUD uses `LINE_BRIGHT` (4.28). QA confirms the audit's rule; raising `TEXT_DISABLED` to 4.5 would make it indistinguishable from `TEXT_MUTE` |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**sim** (sim-core, production, economy/power, abilities, vision — the UI reads `sim_core.md` as the MASTER)

1. **XR-1 One command vocabulary.** Keep `sim_core.md` v2.1 §6.1 (45 ops) as the only vocabulary and `SimCmd` public: one lower-case static builder per catalog row (`ids` first, then the wire fields in catalog order, parameter names = the catalog's field names), `is_known`, `name_of`, `layout_of`, `meta_of`. The UI calls nothing else (the AI does the same), so `describe()` and `verify_against_sim()` need no other API.
2. **XR-2 Read surface for `UiSimPort`.** The members of table 3.2.4 as pure, O(1)/O(n) reads: player economy and identity (`SimPlayer`), per-entity rows with the fields of 4.4.1 through `get_entity` and the components (`e.combat.stance`, `e.cargo`, `e.abil` / `cc.ext_mode`, `e.prod` rally / queue length / primary flag), bulk snapshot through `entities_visible_to`, fog reads including `SimFogApi.ghosts / ghost_version / decoy_identified` (v2.1) and the map's per-cell `deposit_at` / `deposit_max`, `can_attack(shooter, target, force)`, and the `def_flags` sources (`DefUnit.pop`, the MCV ability, the collector tag). Def indices are per kind (decision 17), so no translation is needed. Ids are never reused.
3. **XR-3 Production/economy introspection.** `construction_state` (state, def, progress, ready def, ETA that already includes the 50 % low-power rate, rate %), the construction queue behind the head, `producers(queue_kind)`, `queue_of` with per-item progress, the head `QS_*` of every queue, `research_active` / `research_done` / the research queue, `q_unit_cost` / `q_unit_ticks` / `q_structure_cost` / `q_structure_ticks`, `build_radius_centers`, `sell_value`, `repair_cost_per_second`, and **one published `RSN_*` → `SimCommand.Err` table** (economy's `can_queue_*` and `SimPlacement.validate` return `RSN_*`, the executors answer `Err` + `detail`; 3.2.4 lists the mapping the UI assumes).
4. **XR-4 Powers/superweapon introspection.** Public `warnings_affecting(pid, out)` with the `SimWarning` fields the UI flattens (id, kind `WK_*`, source def, owner, x, y, x2, y2, radius, width, angle, `exec_tick`; the viewer's own and allied strikes always listed; bible: visible to affected players, never hidden by fog or decoys), `power_target_ok(pid, p_idx, x, y)` against real vision, the slot state (`SimPowerSlot`: def, `ready_tick`, `sw_state`, `charge`, `recharge_ticks`, `launcher_id`), and on the power def: `target_mode` including `OWN_STRUCTURE` / `OWN_UNIT` (economy `TK_*`) and `warns_opponents` (recon / scan powers).
5. **XR-5 Events.** (a) Publish one per-event field table for the blocks 200-229 (done in `combat.md` §6.2), 230-259 and 300-499, and confirm the compact layouts of economy 402 and 408 (coordinates moved to the record's `x, y`, remaining fields closed up). (b) The events v2 no longer lists but audio, view or UI use: `TECH_UNLOCKED` / `TECH_LOST` (audio's `new_construction_options`), `BUILD_CANCELLED` (audio's `canceled`), `BUILD_STARTED`, `SW_CHARGING`, the `STATE` changes (deploy, cloak, selling, powered — the UI reads flags), and a harvest-delivery event or `CASH` reason 1 with the refinery position for the view's "+$" floaters. (c) `EVT_WARNING` is emitted for the owner too (own "LAUNCHING" ribbon). (d) The consumer contract "one `take()` per rendered frame, the same array for every consumer" (`sim_core.md` §5.7) stays.
6. **XR-6 Four more `SimPlayer` counters.** `st_value_killed`, `st_value_lost` (Σ `paid` of killed / lost entities), `st_powers_used`, `st_sw_launched` (4.9.1), hashed per DR-13; everything else the end screen shows already exists as `st_*`.
7. **XR-7 Observer/replay perspective.** Vision, snapshot and economy reads accept a `viewer` pid; `−1` = omniscient; economy / stat reads of any pid allowed for observers (never for players).
8. **XR-8 Selection/ownership semantics.** `container_id` / `F_INSIDE`, `F_NO_SELECT`, `F_UNTARGETABLE` readable (they are); capture changes the owner in place (`OWNER_CHANGED`); wrecks and deposits are entities (kinds 2 and 4 / NEUTRAL); **`parent` is set on the Headquarters spawned by an MCV deployment (`SPAWN_DEPLOYED`) and on the MCV spawned by `UNDEPLOY_HQ`**, which makes the selection successor rule of 5.11.2 exact (the emission-order pairing is only the fallback).
9. **XR-9 Match rules and player display data readable:** `rules.{start_credits, unit_cap, superweapons, fog_mode, shared_vision}` and the veterancy switch, `map.w/h`, per-player name / team / colour / roster index (from `SimMatchConfig`).
10. **XR-10 Ability activation contract.** `def` of ops 100-104 = the ability's index in the unit def; `DEPLOY` / `UNDEPLOY` idempotent per unit state with `F_DEPLOYED` / `F_DEPLOYING` readable; `EV_ABILITY_READY` (or `ability_ready_tick(eid, slot)`) for cooldown sweeps; the per-slot auto-cast bit readable from the row; the deploy slot of a def through `DefBrowser` (needed for `undeploy(slot)`); optional: `UNLOAD` accepting `x = y = −1` for "at the carrier" (drop the P flag) so one command can serve several carriers.
11. **XR-11 Structure and queue operations.** `SELL` refund `sell_refund × paid_cost`; `SET_STRUCT_REPAIR` modes; `SET_RALLY` clear (flag bit0); `QUEUE_HOLD` / `BUILD_HOLD` / `RESEARCH_HOLD` hold is cleared when the queue becomes empty; automatic hold on prerequisite loss surfaces as `QS_PAUSED_PREREQ`; `TRAIN_CANCEL` / `BUILD_CANCEL` / `RESEARCH_CANCEL` by queue index refund what was paid (`cancel_refund_bp`); `SET_PRIMARY` moves the primary flag (readable on the row).
12. **XR-12 Sliceable world construction** usable by `AppMatchJob` (`begin(config)`, `step(budget_us) -> bool`, `progress_pct()`, `take_adapter()`), the sim/map counterpart of the slicing request in `net.md` R4.

**view** (`render.md` is the view spec; the UI adopts its classes and asks only for the deltas below)

13. **XR-13 UI-driven camera and one frame entry.** The UI sets `ViewCamera.auto_input = false` (exists, `render.md` §3.3) and uses `pan_screen / rotate_yaw / tilt / zoom_by / focus_on_sim / snap_to / reset_orientation / screen_to_ground`, `view_margin_px` and the `view_changed` signal. Requests: (a) `ViewWorld.frame(dt, alpha, records: PackedInt32Array)` takes the drained event array (sim_core `events.take()` empties the buffer, so the view's router must not read `sim.events` itself), and `AppNet` calls it right after `session.poll()`; (b) `ViewCamera.ensure_input_actions()` is not called when the UI drives the camera; (c) a smoothing switch (`set_smoothing(false)` or zeroed `pan_smooth / zoom_smooth / rot_smooth`) for reduce-motion (A-09); (d) `video/wide_view` maps to `height_max` 110 m.
14. **XR-14 Quality, palette, accessibility.** (a) `ViewQuality.from_settings(cfg, presets)` reads the `[video]` keys with the names of `render.md` §7.7 (4.7.2 uses them verbatim: `quality`, `render_scale`, `scaling_mode`, `msaa`, `fxaa`, `shadow_mode`, `ssao`, `ssil`, `glow`, `decor_density`, `health_bars`, `unit_outline`, `unit_backend`, `night_maps`, `wide_view`, `fps_cap`); `renderer` is the app's (`AppRelaunch`), `camera_wasd` is never written. (b) **Colour vocabulary:** `AppApply.quality_config` writes `[access] colour_mode` as `normal` / `deutan` (UI `cvd`, the closest v1 name for art's single all-type set), `cvd_palette` as a boolean for adopters of art R-1 and `high_contrast_hud` as a separate boolean (the QA-XR-13 name) — the view should read the two booleans so that the colour-vision set and the high-contrast look can be active together (its `high_contrast` mode slot is exclusive today). (c) **Palette data:** the view's team colours come from `ViewStyle.player_color(id, cvd)` / `team_uniform` (`art_direction.md` R-1, R-21) — one source, so the lobby swatch, the minimap blip and the 3D team colour agree; `render.md`'s hard-coded `ViewTeamColors` values and a UI-owned `palettes.json` are both dropped, and `UiTheme.team_colors()` wraps `ViewStyle.player_color`. (d) Pips: the view already draws a shape pip per player index in every mode (`render.md` §5.12; art §5.4.2); the UI uses the same `pip_shape` table on the lobby swatches, the scoreboard and (mode `cvd`) the minimap structure blips. (e) Optional: a `[video] camera_shake` percentage key if a shake-intensity slider is wanted (none is offered today: the view only has the two reduce rules). (f) A high-contrast switch for `ViewSelection` (ring stroke × 1.6), `ViewHealthBars` (height × 1.5 with a dark outline) and a unit-outline rim (A-15), and a hatch pattern on invalid placement cells (V-S02).
15. **XR-15 Picking.** `ViewWorld.pick / pick_box / pick_ground / entity_screen_rect / entity_world_pos` are the UI's only picker (table 3.2.5); requests: `PICK_GHOSTS` and `PICK_WRECKS` combinable with the owner filters for hover and inspect, and `pick_box` staying ≤ 1.2 ms at 400 entities (the UI calls it on release and at ≤ 15 Hz while dragging).
16. **XR-16 Coordinate contract.** `world_to_sim(p) = roundi(p × 1024 / 3)` clamped to the map and `sim_to_world` including terrain height, exactly as `render.md` §3.1 — the UI's single float→int step relies on them.
17. **XR-17 Minimap source.** `ViewMinimapSource.texture` (one texel per cell, baked once per map) and `make_material(true)` (terrain + this viewer's fog) are assigned by the UI to a `TextureRect`; `world_to_uv / uv_to_world` for pings; the view draws no dots, brackets or lines on it (the widget is `UiMinimap`).
18. **XR-18 Interaction visuals are the view's.** `ViewSelection.set_selection / set_hover`, `ViewHealthBars.set_mode`, `ViewLines.set_rally_sources / set_order_sources / set_preview`, `ViewPlacementGhost.show_structure / update_cursor / show_build_radius / hide_ghost` (fed with the sim's `SimPlacementResult`, including the rotation `rot`), `ViewRangeRings.show_for / show_preview / hide_all`, `ViewWarnings` (affected players, ignores fog and decoys), `ViewFloatText.popup` with the UI's font (`set_float_font`); `ViewHealthBars` mode values 0 never / 1 selected / 2 damaged / 3 always.
19. **XR-19 Models, icons, backdrops.** `ViewIconBake` gains two sizes beside ICON 128 x 96 and PORTRAIT 384 x 288 — `CARD` 188 x 124 (sidebar cards) and `BANNER` 304 x 152 (selection panel) — and `prewarm()`; `ViewRecipeBook`, `ViewModelBuilder`, `ViewMaterials` and `ViewIconBake` are constructible **without** a `ViewWorld` (menus, lobby briefing, Field Manual); `ViewModelBuilder.get_model` + `ViewMaterials.unit_material` give the turntable node; `ViewShowcase.create(faction_code, seed) -> Node3D` for menu / lobby backdrops (terrain mood, hero model, drifting dust; the UI orbits its camera). Also: (a) `ViewCamera.px_per_metre() -> float` and a bulk `project_points(sim_xy, out)` behind `UiViewPort` (strategic-zoom markers below 18 px per metre, `art_direction.md` R-18); (b) `ViewMinimapSource.bake(ViewTerrainSource.from_map(map), mood)` callable from the UI thread on a finished `MapData` for the lobby preview (`[XR-31]`); (c) `ViewStyle` constructed once by `App` and injected into the view (the UI does not load it twice).

**net**

20. **XR-20 `NetSession.local_lobby(opts) -> NetSession`:** `Role.LOCAL` held in `Phase.LOBBY` with `lobby.is_host() == true`; `lobby.host_start()` launches with `countdown_s = 0` through the normal pipeline (so skirmish and LAN host share `UiScreenLobby`).
21. **XR-21 Lobby (de)serialisation:** `NetLobbyState.to_dict()/from_dict()` (ints/strings only) and `NetLobby.apply_state(state)` that replays a saved state through the validated setters (skirmish "last game" and presets).
22. **XR-22 Spectator join:** `NetSessionOptions.join_as_spectator: bool`; `NetSession.player_statuses() -> PackedInt32Array` (per pid).
23. **XR-23 Replay playback for the HUD:** `NetReplayPlayer.adapter().world()` usable by `UiSimPortWorld`; `check_ticks() -> PackedInt32Array` (seek-bar marks), `end_tick()`, `events_in(turn_from, turn_to)` for chat/status replay; `verify_failed`/`finished` as documented.
24. **XR-24 Command carriage and back-pressure:** resolved by `sim_core.md` v2.1 §4.8 (the array net carries is the array `submit_raw` takes), so the UI calls `NetSession.submit_command(ints)`; still requested: `NetSession.pending_command_count() -> int` and that `submit_command` never blocks and returns `false` when > 256 are pending.
25. **XR-25 Text keys:** net supplies English defaults for `net.*` (already in `NetProtocol.describe_*`); UI overrides them through `UiText` — net must expose the key names it uses (`net.err.*`, `net.stall.*`, `net.pause.by`, `net.desync.*`, `net.help.*`).
26. **XR-26 Discovery details (optional v2):** add the map seed and the lobby name to the announce datagram so the browser can show the map name/preview before joining.

**data**

27. **XR-27 `DefBrowser` additions** on top of `data_balance.md` §3.10: a per-stat `floor_hit` flag (or `DefStatMath.floor_hit(stat, base, value)`), structured `abilities` entries `{kind, slot, modes: [names], cooldown_t}` (the card has `{kind, summary}`), `pres_recipe`, `queue_kind`, `unit_class`, tag masks, `condition_text` for conditional modifiers, structure prerequisites as `[{id, name}]`.
28. **XR-28 Display accessors.** Already published and used as-is: `DefFaction.code/ui_motto/ui_lore/ui_identity/ui_opening/ui_counterplay/ui_traits/sub_rosters`, `DefRoster.ui_title/ui_identity/ui_lore/ui_opening/ui_counterplay/power_slot`, `GameData.roster_ids()/roster_faction()/roster_for(code, sub_key)`. Still needed: the faction display name (`ui_name`) and the fixed sub-roster order (`DefFaction.sub_rosters` ascending) documented as normative.
29. **XR-29 Classification for the tabs.** Published: `DefRoster.units_produced_by`, `producible_units`, `producible_structures`, `research_list`, `power_list`. Needed: `DefStructure.queue_kind`, tag bits for defense / advanced defense / superweapon launcher / relay, the `SERVICE` unit class, and `DefPower.target_mode` (incl. `OWN_STRUCTURE`) and `warns_opponents`.
30. **XR-30 Test data.** UI fixtures run on the shipped data (`GameData.load_default()`); `GameData.load_from_sources` is enough for negative tests, no `for_test` is required.

**map**

31. **XR-31 Map inputs for the lobby.** The UI runs `MapGenJob.begin(map_cfg, null, true)` (worker thread; `step(budget_us)`, `progress_pct()`, `result()`, `cancel()`; `terrain_movement.md` §3.7) and reads `MapData.start_cells`, `fair_slot_order(players)`, `biome` and `family`. Requests: (a) `MapGenJob.cancel()` returns promptly (the lobby cancels on every seed change); (b) optional, if profiling shows the navigation preparation dominates: a `prepare_nav = false` switch for previews; (c) view: `ViewMinimapSource.bake(ViewTerrainSource.from_map(map), mood)` callable from the UI thread on a finished `MapData` (`UiViewPort.bake_map_preview`, `[XR-19]`); (d) net: resolve random starts (`start = −1`) with `map.fair_slot_order(n)` where a map exists, else leave it to the host's Balance-starts button. `MapGenParams.recommended_size(players)`, `min_size(slots)` and `slots_for(players)` are public helpers (they are). Map names are the UI's (`UiMapNames`), nothing requested.
32. **XR-32 Validation.** `MapGenerator.validate_params(family, size, layout_players) -> String` is the lobby validator (also `net.md` `[XR-12]`: `opts.map_validator`); `MapGenParams.from_config(cfg).validate()` covers the full dictionary; `AppMatch.validate_map(family, size, layout_players)` wraps the first.
33. **XR-33 Passability and deposits.** `MapData.passable(cx, cy, mc)` (LIVE, structures included), `deposit_at(i)`, `deposit_max` and `idx(cx, cy)` reachable through the sim read API (`UiSimPort.passable`, `deposit_at`) for the DENIED move cursor and the harvest cursor; `MapBuildRules.PR_*` (`PR_OUT_OF_BOUNDS 1 … PR_WATER_EXIT 6`) are folded into economy's `RSN_*` by `SimPlacement`, so `UiSimPort.place_reason()` (5.10.5) keeps reading economy's reasons.

**audio**

34. **XR-34 Audio contract (the UI side of `audio.md` §3.11).** Confirm: the UI calls only `Snd.ui(&"snd.ui.*")` with the ids of 6.3.1 (all exist in audio's grammar §4.8), `unit_selected` / `unit_ordered` / `order_denied`, `announce` for lobby lines, and reads `announcement_started` (emitted for every line, shown when `audio/captions`); **audio speaks every sim-caused line** (decision 16), the UI never does; `Snd.set_mode` values MENU 1 / LOBBY 2 / LOADING 3 / MATCH 4 / POST_MATCH 5; `Snd.set_time_scale` for replays. The reconcilers sweep `audio.md` §6.2 to the v2 event codes (alias column of 6.2.1).
35. **XR-35 Audio settings:** the `[audio]` names, defaults and ranges of `SndSettings` (`audio.md` §4.5) are adopted in 4.8.1; `Snd.apply_settings(s)` must not write `settings.cfg` (the app is the single writer, 5.20.1); the slider curve `(v/100)²`, bus defaults, output-device fallback and mute-on-unfocus stay in audio; `Snd.begin_match(SndMatchConfig)` / `load_progress()` / `is_match_ready()` run during loading and `AppMatchJob` waits for them.
36. **XR-36 Unit responses and captions:** `unit_selected(def_idx, is_structure, count)` takes the per-kind def index of the primary (highest tier, ties lowest def index); `unit_ordered(order, def_idx)` with `SndUnitResponse.Order`; `order_denied(def_idx, is_structure)`; audio's own gaps apply (250 ms global, 700 ms per class and type), the UI adds no throttle; `Snd.settings().captions` is the UI's `audio/captions`.

**ai**

37. **XR-37** `AiFactory.level_count()/level_names()/style_names()/level_handicap_pct(level)/level_cheat_key(level)/takeover_level()` and the text keys `ai.level.*`, `ai.style.*`, `ai.cheats.brutal` (ai.md §3).
38. **XR-38 (optional)** the `AiDebugFrame` schema of ai.md XR-18; the UI hosts it behind `Ctrl+F3`.

**core**

39. **XR-39 `Log` and `Fp`:** `Log.debug/info/warn/error(tag, msg)` (`sim_core.md` §3.2.6) with the injectable `Log.sink: Callable` called with `(level, tag, msg)`, `Log.level` / `Log.quiet` and the 256-line `Log.ring` (`qa.md` `[QA-XR-23]`, used by `AppLogSink`, `AppLogger` and the crash reports); `Fp.self_test() -> Array` of failed checks (boot and the smoke line, `sim_core.md` R24), `Fp.CELL`, `Fp.cell_of`, `SimConfig.TPS`.

**build / qa / tooling**

40. **XR-40 `project.godot`:** `display/window/stretch/mode="disabled"`, `display/window/dpi/allow_hidpi=true`, `application/config/version="0.1.0"`, `gui/theme/default_font_antialiasing=1`, `gui/theme/default_font_hinting=1`, `gui/theme/default_font_subpixel_positioning=1` (spike values), autoload block `AppSettings, AppNet, AppState, AppScenes` (in that order, after `DevShot`), `boot.tscn` stays the main scene, `debug/file_logging/enable_file_logging.standalone=true` and `max_log_files=10` (the engine log is the single log, `[QA-XR-6]`), `debug/settings/crash_handler/message` as in 5.20.3, `boot_splash` unchanged.
41. **XR-41 Export presets:** `include_filter="data/*.json,data/*/*.json,assets/fonts/*,assets/fonts/*/*,LICENSES/*,LICENSES/*/*"` (the Licenses screen reads `LICENSES/THIRD_PARTY.json` and the licence files at runtime; `qa.md` `[QA-XR-5]` owns the release presets); macOS `NSLocalNetworkUsageDescription` (net XR-15); high-DPI capable flags on macOS/Windows; window icon/app name.
42. **XR-42 `tools/gd shot`:** keep `--size`/`--rendering-method`/user-arg pass-through; DevShot and `AppBoot` must coexist (`AppBoot` never quits on `--shot`; `DevShot` captures after `--frames`); optional `tools/py/ui_shots.py` batch driver for the 40-shot matrix of 10.6 and a Pillow-based `img_diff.py` for perceptual regression.
43. **XR-43 Test runner:** the runner already supports `await`; request only a `t.frames(n)` helper (await n process frames) and that `tools/gd linux test ui` runs the labs in the Debian container (no display needed for input / layout labs).
44. **XR-44 Lint:** add rule `UL-1` (assignment / mutating call on `world.` / `SimWorld` members inside `src/ui`, `src/app`; same idea as the view's read-only guard); QA's proposed `L012` (no shell / network APIs outside `src/net`) must allow `OS.shell_open` on a `user://` folder in `src/app` and `src/ui` (Open logs folder, Open replay folder, desync package) with a `lint-allow: L012 open user:// folder` reason; keep `Time.*`, floats and `TranslationServer.format_number` legal in `ui/` and `app/`; `Log.*` for output (L006), plus the single `print` of `AppLogSink` under `lint-allow: L006`.
45. **XR-45 Fixture storage:** `game/tests/fixtures/ui/`, `game/tests/golden/ui_perf.json` and (optional) baseline screenshots are UI-owned test assets; CI must not garbage-collect them.
46. **XR-46 CI matrix:** run `tools/gd test ui` (labs included) on macOS, Debian container and Windows; run the visual set on all three rendering methods for release candidates.
47. **XR-47 QA registries and hooks** (`qa.md` `[QA-XR-11]`, `[QA-XR-28]`): register the UI visual matrix of 10.6 in `game/tests/visual/cases.json` (`owner: ui`); the UI supplies `UiTheme.colors()` / `team_colors()`, `UiKeymap.dump()` (QA's `UiBindings.dump`), an injectable `UiHud` (no autoload dependency), accessible names on every interactive Control, and the credits / licenses screens fed by `credits.json`, `LICENSES/THIRD_PARTY.json` and `Engine.get_license_*`; QA supplies the `--qa=<job>` harness entry, the per-process `user://` sandbox (`gd --sandbox`) and the audits (`QaLayoutAudit`, `QaA11yAudit`, `QaContrast`).

**architecture / reconciler**

48. **XR-48 Amendments to `docs/ARCHITECTURE.md`** (record in `docs/AMENDMENTS.md`): (a) autoloads = `DevShot, AppSettings, AppNet, AppState, AppScenes`; (b) `data/ui/` and `data/text/` are owned by `ui`, `assets/fonts/` by `ui`; (c) scale rule of 5.4.1 supersedes the `canvas_items` stretch in the project skeleton; (d) §12 "Selection & control model" refined by 5.5-5.7 (Alt+grid card hotkeys, group semantics, per-OS force modifier, minimap always available); (e) §11 names the "lab" test kind (async SubViewport tests that run under `gd test`) beside unit/scenario/determinism/visual; (f) `ui/` and `app/` may use floats, `Time` and engine RNG but must never mutate `SimWorld` (lint `UL-1`); (g) the engine log `user://logs/godot.log` is the single log, the app installs `Log.sink`, crash reports live in `user://logs/crash/` (`qa.md` §5.12); (h) graphics presets are the view's `quality.json`, the app only persists and exposes the `[video]` overrides; (i) the extended `MERIDIAN_BOOT` smoke line and the `--qa` / `--selfcheck` hooks; (j) minimum text size 14 px and UI scale 75-200 %; (k) `sim_core.md` v2.1 is the command / event vocabulary for view, audio, ui and qa (sweep `audio.md` §6.2 and the order-type numbers in `render.md` §5.10); (l) audio owns the event-driven announcer, the UI shows captions and notices; (m) `[video] quality` / `renderer` and the `[audio]` `SndSettings` names are the persisted keys.

**art_direction** (`art_direction.md` — the visual bible; the UI adopts its tokens, skins, player colours, emblems, glyph list and cursor set)

49. **XR-49 Visual-language integration.** (a) **`ViewStyle` accessors:** `ui_data(section: String) -> Dictionary` for `type`, `relation`, `hp_ramp`, `selection`, `icon_rig` and `tokens_cvd` (art lists only `ui_token`, `skin`, `chrome`); `style.ui.tokens_cvd` = the four colour-vision-safe semantic colours of 7.5 (`#4DB8FF #F5E663 #E8590C #A8E6FF`, computed here, minimum ΔE2000 21.9 under every simulation). (b) **A-01 versus the default team set (risk R28):** decide between narrowing QA A-01 (the UI's recommendation, no colour change) and adopting the UI proposal `P-default` (5.19.3); tell QA which. (c) **Archetype role column:** `style.archetypes.<id>.role` ∈ the glyph names (`TANK`, `ARTILLERY`, `ANTI_AIR`, `SCOUT`, `TRANSPORT`, `ENGINEER`, `COLLECTOR`, `MCV`, `DRONE`, `SUBMARINE`, `CARRIER`, `SIEGE`, `COMMAND`, else the class glyph), so that build cards and strategic-zoom markers do not guess from tags (5.10.4). (d) **Settings spelling:** art R-22 writes `[accessibility] cvd_palette dyslexia_font high_contrast reduce_motion` and `[video] time_of_day`; the settings-file owner (`qa.md` QA-XR-13) and `render.md` use `[access] colour_mode reduce_motion reduce_flash high_contrast_hud ui_font` and `[video] night_maps`. The UI keeps the latter and maps `cvd_palette` = `colour_mode == cvd`, `dyslexia_font` = `ui_font == 1`, `high_contrast` = `high_contrast_hud`, `time_of_day=auto` = `night_maps`; art and render adopt one spelling. (e) **net:** `NetLobby` assigns default colours in `ViewStyle.default_color_for_slot` order (`assign_order` 1, 0, 2, 3, 4, 5, 6, 7) and reads swatch hex from `style.player_colors`; ids stay 0-11 on the wire in both modes. (f) **view:** the `cvd` boolean and `high_contrast_hud` of XR-14, `ViewStyle` injected once, `FxStyle.hp_color` / `relation_color` shared with UI widgets, `video/unit_outline` (art R-16). (g) **Chrome:** the panel bracket arm is 12 px in `style.ui.chrome` while the spike used 20 px; the UI follows the JSON. (h) **UI scale range:** art §5.12.3 / §5.12.7 say 75-150 %, `qa.md` A-03 says 75-200 %; the UI offers 75-200 % (4.8.1) — art's range statement should follow QA.
