# Development guide

Meridian Fracture is a **Godot 4.7.2, GDScript-only** project. The game is a deterministic-lockstep RTS: the simulation is integer-only and identical on Windows, macOS and Linux. This file is the map for contributors. Deeper material: [INDEX.md](INDEX.md) (all documents and how to navigate the specs), [ARCHITECTURE.md](ARCHITECTURE.md) (the constitution), [STATE.md](STATE.md) (build log), [DEVIATIONS.md](DEVIATIONS.md) (per-task reports), `docs/spec/*` (domain specs, huge), `docs/spikes/*` (proven engine behaviour), [RULES_DATA_NOTES.md](RULES_DATA_NOTES.md), [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Every command in this file was run on macOS arm64 (and the `tools/gd linux` ones in the Debian container) when the file was written; commands that need hardware or accounts the maintainers do not have are marked.

## Repository layout

```
Input/                 the design bible (read-only source of truth; never edit)
game/                  the Godot project (res://)
  project.godot, export_presets.cfg
  src/                 core sim map data net ai view ui audio app  (class_name prefix per directory)
  data/                bible/ (mirror of Input/), balance/ (rules data, AI profiles), missions/ (campaign and tutorial scripts),
                       recipes/ (3D model recipes), ui/ (keymap, presets, cursors), audio/ (event/mix/music data), text/, net/
  assets/              fonts/ (OFL), audio/ (generated OGGs), shaders/, icons/
  tests/               unit tests by domain + scenarios, golden, integration, visual (screenshot labs), support (harnesses)
docs/                  this documentation, specs, balance framework, generated unit reference, screenshots (img/)
tools/                 gd (Godot wrapper), spec (spec navigator), setup, py/ (validators, generators, packaging, stress), docker/
.github/workflows/     build.yml (CI)
builds/                exported builds, packages and QA output (generated)
prototypes/            throw-away spikes (not part of the game)
```

Source modules and their prefixes: `src/core` (fixed-point math, RNG, checksum, logging), `src/sim` (`Sim*`: the world, ECS-style components, systems, orders, combat, economy, abilities, zones, the mission system), `src/map` (`Map*`: generator, navigation), `src/data` (`Def*`, `GameData`: the single content pipeline), `src/net` (`Net*`: lockstep, lobby, discovery, desync, replays), `src/ai` (`Ai*`), `src/view` (`View*`, `Fx*`: 3D presentation), `src/ui` (`Ui*`), `src/audio` (`Snd*`), `src/app` (`App*`: boot, screens, settings, match, campaign and replay glue). Rules: file name equals snake_case of the `class_name`; lowercase snake_case file names; exact-case `res://` paths (Linux is case-sensitive); static typing everywhere; files up to 1,500 lines; no debug `print` (use `Log`).

## Getting started

```
tools/setup                  # fresh checkout: engines (sha512 verified), bible mirror, first import (idempotent)
tools/setup --templates      # also install the export templates (about 2 GB)
tools/setup --docker         # also build the Debian container images (needs Docker)
```

Run the game from source:

```
tools/godot/Godot.app/Contents/MacOS/Godot --path game        # macOS; Linux: tools/godot-linux-x86_64/Godot_v4.7.2-stable_linux.x86_64 --path game
```

Always go through the wrappers for everything else: `tools/gd` serialises access to the shared `game/.godot` import cache (never run the Godot binary on `game/` by hand while another command runs). The manual for the tooling is `docs/spec/qa_tooling.md` (sections 4 and 5: cross-platform, export, packaging, CI).

### tools/gd

| Command | Purpose |
|---|---|
| `tools/gd import` | Import resources and refresh the `class_name` cache (auto-runs when needed) |
| `tools/gd check [--strict] [paths]` | Lint (project rules L001...) plus compile every script; `--strict` promotes warnings to errors. Must be clean before finishing any task |
| `tools/gd test [filter...] [-q] [--list] [--file F] [--timeout S] [--stall S]` | Headless tests. Filters are case-insensitive substrings of `<path>::<method>` |
| `tools/gd run <res://x.gd or .tscn> [--gui] [-- args]` | Run a script or scene, headless by default; the path must be inside `game/` |
| `tools/gd shot <scene> out.png [--size WxH] [--frames N] [--allow-errors] [-- args]` | Real-renderer screenshot after N rendered frames |
| `tools/gd docs <Class> [member]` | Godot 4.7.2 class reference lookup (this engine is newer than most training data) |
| `tools/gd linux [--arch amd64\|arm64] <cmd>` | Run any gd command in the Debian 12 container |
| `tools/gd ps` | Who holds the project lock |
| `tools/gd snapshot` | tar.zst of the source tree into `.backups/` |

Examples: `tools/gd check --strict`, `tools/gd test net_ -q`, `tools/gd linux test net_protocol -q`.

Full suite: `tools/gd test -q --timeout 2700 --stall 0` (2,428 tests at the time of writing, about 7 to 13 minutes; nothing else heavy running).

### Launch flags

The app reads everything after `--` (`OS.get_cmdline_user_args()`); `AppLaunchArgs` parses it, unknown `--key=value` pairs are passed to the screens. Test and tool modes (`--smoke`, `--autostart`, `--shot`, `--fresh-settings`, `--screen`) never touch the real settings, campaign progress or `.session` file.

| Flag | Meaning |
|---|---|
| `--smoke` | Boot, self-test, print `MERIDIAN_BOOT engine=... version=... selftest=ok`, quit (used by the export smoke tests) |
| `--fresh-settings`, `--no-audio`, `--ui-scale=N`, `--palette=normal\|cvd`, `--quality=`, `--window=WxH`, `--renderer-relaunched` | Test-friendly settings overrides |
| `--screen=<id>` | Open a screen directly: `main_menu`, `lobby` (`--lan-host[=port]` for the LAN host lobby), `lan_browser`, `options` (`--page=graphics\|audio\|controls\|interface\|network\|storage`), `field_manual` (`--page=overview\|units\|structures\|research\|powers\|tree\|compare --roster_id=roster.napc.vanilla --focus_id=unit.napc.bastion_heavy_tank`), `campaign` (`--select=<mission id>`), `mission_briefing` (`--mission=<id>`), `replays` (`--dir=<folder>`), `credits`, `splash`. `--no_help` skips the first-run LAN explainer |
| `--campaign-progress=id[:seconds[:difficulty]],...`, `--campaign-unlock` | Pre-mark missions as won / open every mission (screenshots, tests) |
| `--autostart=match` | A local match through the real session path: `--players=N --humans=H --rosters=a,b --map-seed=S --map-size=N --family=0\|1\|2 --ai-level=L --ai-levels=1,2 --fog=0\|1 --ticks=N --speed=<pct>` (`0` = unpaced) `--bots[=all\|human]` (scripted test bot instead of the human / AI slots) `--with-ui` (real loading and match screens) `--pause-at=N --surrender-at=N --quit-on-end --timeout-s=S` |
| `--autostart=mission=<id>` | A campaign or tutorial mission (`--difficulty=0..3`, default 1 = Medium; the same match flags apply; prints `APPTEST_MISSION` and `APPTEST_MISSION_END`) |
| `--autostart=replay=<file.mfreplay>` | Play a recording through the real replay path: `--with-ui --seek-to=N --seek-demo --perspective=N --scoreboard --follow --select=PID --menu --cam-zoom=Z --allow-mismatch --ck-lines` |
| `--autostart=lan-host` / `lan-join=<address>` | Two headless processes play a LAN game through the real lobby ([LAN_GUIDE.md](LAN_GUIDE.md), `tools/py/app_two_process.py`) |
| `--record-replays --replay-dir=<folder>` | Record the match into a chosen folder (headless proofs, screenshots) |
| `--ck-lines` | Print `APPTEST_CK tick= chain= checksum=` every 200 ticks (match and replay) |
| `--scenario=showcase` | Late-game debug scenario for screenshots, LOCAL runs only: rich credits, instant tech base, charged and launched superweapon (`--credits --sw-at --sw-pids --sw-target --sw-angle`), `--army=N`, `--battle=ground\|air\|naval --battle-n=N --battle-at=T` |
| `--keys="F5@80;movehq:5,0@85;clickhq:5,0@110"` | Scripted real key presses and mouse moves / clicks at sim ticks (`AppTestKeys`: `F5@T`, `Ctrl+1@T`, `move:X,Y@T`, `click:X,Y@T`, `movehq:DX,DY@T` / `clickhq:DX,DY@T` relative to the HQ in cells); with `--cap` it captures what a key does in a live match (`APPKEYS` lines) |
| `--screen=lobby --lan-host --lan-address=192.0.2.10:27615` | The LAN host lobby with a neutral address shown (screenshots must not carry a private address) |
| `--cap=T1,T2 --cap-out=<prefix> [--cap-keep]` | Window PNGs at those sim ticks (`<prefix>_<tick>.png`), then end (unless `--cap-keep`) |
| `--cam-zoom=Z --cam-pitch=D --cam-yaw=D --focus=fight\|build\|wreck\|dock\|air\|naval\|crowd\|sw --ui-tab=N --minimap-click=x,y` | Camera and HUD framing for screenshots |
| `--quit-at-phase=<phase> --quit-after-ms=N --quit-mode=tree\|close\|state\|raw` | Used by `tools/py/quit_stress.py` |

Example screenshot of a live match (not paused, with effects) and of a staged battle:

```
tools/gd shot res://src/app/boot.tscn out.png --size 1920x1080 --frames 6000 --allow-errors -- \
  --autostart=match --with-ui --bots=human --speed=0 --players=2 --humans=1 --map-seed=5 --fresh-settings --cam-zoom=0.45 \
  --cap=2400 --cap-out=/tmp/early

tools/gd shot res://src/app/boot.tscn out.png --size 1920x1080 --frames 9000 --allow-errors -- \
  --autostart=match --with-ui --players=2 --humans=1 --fog=0 --fresh-settings --scenario=showcase --battle=ground --battle-n=40 \
  --army=20 --sw-at=0 --focus=fight --cap=250 --cap-out=/tmp/battle
```

(`--frames` counts rendered frames; the sim is real time unless `--speed=0`; raise `--timeout` for long runs.)

### tools/spec

The specs are 150 to 500 KB each; never read one whole.

```
tools/spec sizes                       # sections and sizes
tools/spec list economy                # table of contents of one spec
tools/spec show economy 5.3 5.7        # print sections
tools/spec grep ui "drag|Shift"        # search
tools/spec dev BAL3                    # the finished-task report whose label starts with this prefix (DEVIATIONS.md)
```

## Determinism rules (short form)

The simulation (`src/core|sim|map|data`) must produce bit-identical state on every OS. The linter (`L003` and friends) enforces most of it:

1. Integers only: no `float`, `Vector2/3`, `randf`, `Time`, `delta`, `sin/sqrt/pow`, no `Node`, signals or `await` in sim code. Use `Fp` helpers and `SimRng` (xorshift128, state in the checksum).
2. Iteration order is deterministic: arrays in entity-id order; dictionaries only with int or String keys inserted in deterministic order; sort comparators are total orders (tie-break by id).
3. Every new persistent sim field must be added to `SimWorld.checksum()` in the same change.
4. Presentation (`view|ui|audio`) reads the sim and never mutates it. UI, AI, missions' UI side and network act **only through `SimCommand`s** made of ints. The AI may use floats internally.
5. Data is converted to ints once at load; the converted data hash is part of the lobby handshake and of replays, so any balance, AI or mission edit changes the hash (both LAN peers must match; recorded replays warn about a changed build). `terrain.json` and `map_gen.json` are covered through the manifest too; the handshake names the differing file.

A `# lint-allow: RULE reason` comment is allowed only where a spec permits.

### Cross-OS check

`python3 tools/py/xplat_determinism.py res://tests/scenarios/<scenario>.gd [--targets native,amd64,arm64]` runs a scenario on macOS, linux-amd64 and linux-arm64 (containers) and compares the hash chains. `--only-local` runs the local OS only. CI compares macOS, Linux and Windows chains. Example: `python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_int_math.gd --only-local`. The release gate uses `xplat_int_math xplat_match xplat_match_navair xplat_ab2 xplat_ai_brain xplat_net_local`; more (`xplat_mission`, `xplat_net_replay`, `xplat_ai_econ`, `xplat_soak`, ...) are in `game/tests/scenarios/xplat_*.gd`.

Two-process LAN proof: `python3 tools/py/app_two_process.py` (through the real menus) and `python3 tools/py/net_two_process.py` (netcode level, with fault injection). **Both use two processes on one machine over loopback; no real two-computer game has been played.**

## Tests

`game/tests/` holds one directory per domain (`core sim map econ combat abil ai net view ui audio unit`), plus `scenarios` (scripted matches used for goldens and cross-OS chains), `golden` (recorded hashes: when a change legitimately alters simulation state, regenerate them and record why), `fixtures` (including two recorded replays), `integration` (soak and stress), `bench`, `harness`, `support` (SimMatchKit, SimBot, MissionRun) and `visual` (screenshot labs; look at the output with your own eyes). A test file is a script with `test_*` methods; see `game/tests/unit/` for the pattern and `docs/spec/qa.md`.

Python tests for the tooling: `python3 -m unittest discover -s tools/py/tests` (195 tests, all green; Pillow and PyYAML are needed for the icon and workflow tests). Replay fixtures with recorded real AI play must be regenerated after any intended data change that alters AI or unit behaviour (header of `game/tests/net/make_replay_fixture.gd` says how).

## Data and validators

One content pipeline, owned by the data module: everything the sim knows comes from `game/data/bible` (mirror of the bible), `game/data/balance` (units, structures, powers, research, zones, traits, neutrals, global rules, `ai/` profiles, terrain and map generator parameters) and `game/data/missions`, all listed in `balance/manifest.json`. Loaders are `src/data/def_*`.

| Validator | What it checks |
|---|---|
| `python3 tools/py/sync_bible.py --check` | The bible mirror equals `Input/` (hash manifest). Never edit `game/data/bible/` by hand |
| `python3 tools/py/validate_balance.py [--strict] [-v] [--no-waivers]` | Balance files: schemas, cross references, bible numbers and floors, manifest coverage. `--strict` exits 0 on the shipped data: four accepted warnings are documented **waivers** in `tools/py/balance_lib/waivers.json` (a stale waiver is itself a warning; `--no-waivers` ignores the file); CI runs it |
| `python3 tools/py/check_rules_data.py` | Research, powers, zones, traits, neutrals against the bible prose numbers |
| `python3 tools/py/validate_recipes.py [--strict]` | 3D model recipes (rules V-RCP-01 to 12) |
| `python3 tools/py/gen_recipe_index.py --check`, `gen_recipe_stubs.py --check` | Recipe index, footprints and stubs are current |
| `python3 tools/py/validate_missions.py [--strict] [files]`, `--schema` | Mission files against the schema, the manifest and the bible; `--schema` prints the exact schema (below) |
| `python3 tools/py/version.py check [--packages]` | `VERSION` equals project, export presets, README badge and file names, CHANGELOG |
| `tools/py/audio/build_all.py check` | Audio assets against loudness and budget thresholds (needs the audio venv) |
| `tools/gd check --strict` | Lint and compile for the whole project |

### Stability tools

| Tool | What it proves |
|---|---|
| `python3 tools/py/quit_stress.py [--iterations 60] [--headless \| --both] [--seed N --jobs N --timeout S]` | The app exits by itself wherever it is asked to quit (splash, menu, lobby, LAN browser / lobby, options, credits, Field Manual, replays, loading map / world / view / models, match, end screen, replay playback) with the quit modes `tree`, `close` (window close request), `state` (menu Quit) and `raw` (a bare `SceneTree.quit()`). A raw quit during world loading may exit with code 3; the tool counts that as shutdown noise, not as a failure. Driven by `--quit-at-phase=<phase> --quit-after-ms=<n> --quit-mode=<mode>` |
| `python3 tools/py/boot_stress.py [--iterations 100]` | Real-renderer boots of an autostart match (random family / size / players / seed, audio on every 4th run): no crash, no `caller thread can't call` error, no engine ERROR line at exit |
| `python3 tools/py/far_zoom_probe.py --mode exit` | The original quit-during-load repro (green) |
| `python3 tools/py/soak_run.py [--game-min 30 --players 8 --out soak]` | Long AI-versus-AI soak (zero engine errors, identical digests); nightly in CI |
| `python3 tools/py/perf_run.py [--matrix ...]` | Frame-time and entity-count measurements with the real renderer |

Rules the quit work established: every owner of a thread or task cancels and joins it itself (`MapGenJob`, `ViewModelBuilder.cancel()`, `ViewWorld` abort, `ViewIconBake.flush`); a coroutine that awaits frames must also stop once `AppShutdown.quitting` is set (`AppState.quit_game`, a window close and the quit hook call `AppShutdown.begin_quit`, then `prepare_quit` exits the screens before the match context is disposed). `Log` is thread-safe (`Log.ring_push` / `Log.ring_tail`); never call Node API from a worker thread.

### Generated documentation (rerun after data changes)

```
python3 tools/py/gen_unit_reference.py     # docs/units/*.md   from the bible and the balance sheets
python3 tools/py/gen_factions_doc.py       # docs/FACTIONS.md  from the bible mirror
python3 tools/py/gen_controls_doc.py       # docs/CONTROLS.md  from keymap_defaults.json AND a scan of the game code
```

`gen_controls_doc.py` marks every keymap action that no code handles with a dagger, by scanning `UiScreenGame._on_action`, `UiObserverController.handle_action` and the input controller. When a missing hotkey gets connected, rerun it and the dagger disappears; update the prose in `docs/USER_MANUAL.md` section 14 and [KNOWN_ISSUES.md](KNOWN_ISSUES.md) by hand.

### Adding a unit

1. The bible (in `Input/`, then `python3 tools/py/sync_bible.py`) defines the unit id, tier, producer, prerequisites, tags and text. The balance side is authored in `game/data/balance/units_<code>.json`: `units` entry (archetype, cost, build time, health, speed, vision, weapon instances, abilities) plus `weapons`; archetypes and taxonomy in `global.json` and [balance/FRAMEWORK.md](balance/FRAMEWORK.md). `python3 tools/py/balance_calc.py propose <archetype> --tier N` suggests fair starting stats.
2. Give it a look: `python3 tools/py/gen_recipe_stubs.py` writes a stub recipe from `game/data/recipes/assignments.json`; replace it with a hand-authored `game/data/recipes/<unit id>.json` (remove `meta.stub`), using archetypes from `recipes/archetypes/` and the faction style in `recipes/styles/<code>.json`. Preview with a lineup sheet: `tools/gd shot res://tests/visual/napc_sheet.tscn out.png --size 1920x1080 -- --ids=unit.napc.guardian_tank,unit.napc.rifle_squad --style=napc --roster=roster.napc --cols=5 --cell=17 --cam=88 --yaw=0 --pitch=52` (works for every faction with `--style=<code>`; `tests/visual/archetype_sheet.tscn` for archetypes).
3. Regenerate: `python3 tools/py/gen_recipe_index.py`, then run the validators above and `python3 tools/py/gen_unit_reference.py`.
4. Tests: `tools/gd test def_ balance recipes -q` for data, and the domain tests.

Balance changes: `tools/py/bal2_*.py` and `bal3_*.py` are the AI-self-play balance rounds (round robins on private project copies, `bal3_changes.py` re-applies the accepted changes from the pre-round sheets: a later re-run would undo hand edits). `tools/py/ai_soak_report.py` and `ait_report.py` aggregate soak results. The measured conclusion of BAL3 is that AI dials (`game/data/balance/ai/ai_personality.json`, `ai_faction_*.json`) move the AI round robin more than unit numbers inside the fair-cost band.

### Adding a faction or subfaction

A faction is a bible entry (`factions`, `rosters`, `units`, `research`, `support_powers`, `superweapons`) plus: `units_<code>.json` (and the file in `manifest.json`), entries in `faction_traits.json`, `power_actions.json`, `research_effects.json`, `zone_templates.json` for its mechanics, an AI file `ai/ai_faction_<code>.json`, a `recipes/styles/<code>.json` style, and audio profiles in `game/data/audio/factions.json`. A subfaction is a roster with modifiers, replaced units and one exclusive research or power; no new files are needed unless it introduces units (its livery and emblem come from the style). Field Manual, lobby and AI pick rosters up from `GameData`.

### Adding a balance sheet

Add the file under `game/data/balance/`, list it in `manifest.json`, describe its schema under `game/data/balance/schema/`, register a loader in `src/data` (`DefLoaderBalance` or `DefLoaderRules`) and a validator rule in `validate_balance.py`. Extensions to the authored rules files are documented in [RULES_DATA_NOTES.md](RULES_DATA_NOTES.md). Changing any file changes the data hash: goldens, replay fixtures and LAN peers must be rebuilt together.

### Adding a model recipe

Recipes are JSON programs (parts, sockets, expressions, macros) that the view compiles into one mesh per model: `game/data/recipes/`. Read `tools/spec show render 5.8` for the grammar. Validate with `validate_recipes.py`; the mesh budget test (`tools/gd test view_structure_archetypes`) guards triangle counts.

## The mission system

Missions are data: `game/data/missions/<id>.json`, run by `SimMissionSystem` inside the simulation (so they are deterministic, replayable and covered by the data hash), presented by the UI layer (`UiMissionHud`, `UiObjectivesPanel`, briefing and result screens, `UiCampaignModel`) and started by `AppMission` (difficulty shifts the AI levels: Easy -1, Medium 0, Hard +1, Brutal +2) with progress in `AppCampaign` (`user://campaign.cfg`). The engine offers 15 condition kinds (plus the `all` / `any` / `not` combinators) and 21 actions; the exact schema, always current, is printed by

```
python3 tools/py/validate_missions.py --schema
```

### How to author a mission

1. Pick an `id` (`[a-z][a-z0-9_]*`, the file name is `<id>.json`), a `group` (`tutorial`, `operation`, `demo` or your own; the campaign map puts operations on a ring, `tutorial` in the hub and other groups along the bottom) and an `order`.
2. Describe the `map` (`family`, `size`, `seed`, optional generator `params`), the `rules` (credits, fog, `victory` 0 means the script decides), the `players` (exactly one `human`, rosters, teams, start mode, optional free units and structures, AI level and style; an AI can start switched off and be activated by a `change_ai` action) and the `areas` (circles or rectangles anchored to the absolute map, to the map in permille, or to a start position, so the mission does not depend on the generated terrain).
3. Add `objectives` (primary, secondary, hidden), `messages` (with an optional announcer line from `data/audio/announcer.json`), `timers`, and `triggers`: every 5th tick each enabled trigger's `when` condition is evaluated and, if true, its `then` actions run (spawn units or structures, set objectives, show messages, start timers, grant or lock powers, reveal areas, change the AI, transfer or destroy things, `win` / `lose`).
4. Probe the map: `tools/gd run res://tests/scenarios/mis3_map_probe.gd -- family=0 size=128 seed=10 players=4 scan=12` prints validator results for a range of candidate seeds (add `ascii=2` for a picture, or `mission=<id>` for a shipped mission). Look at the layout with `tools/gd run res://tests/scenarios/mis3_dump.gd -- mission=<id> ticks=N` (every area centre and every player's entities after N ticks).
5. Play it with the harness: `tools/gd run res://tests/scenarios/mis3_run.gd -- mission=<id> driver=bot|ai|idle|tutorial [trace=60 tracedef=unit.x tracepos=1 full=1]` prints the outcome, time, objective states and the trigger firing times as `MIS3_RESULT {...}`. `bot` is MissionBot (SimBot macro play steered by the per-mission goals in `tests/support/mission_goals.gd`), `ai` the Hard AI alone, `idle` nobody, `tutorial` the scripted tutorial player. A good mission is won by the bot and never by `idle`.
6. Validate and test: `python3 tools/py/validate_missions.py --strict`, `python3 tools/py/mis3_bench.py <ids> --driver bot --seeds 777,1234` (one process per mission and seed; the acceptance table), `tools/gd test mis3` (structure, map quality, the tutorial played with commands, bot completes and idle does not win; the last two are slow).
7. Look at it: `tools/gd shot res://src/app/boot.tscn out.png --size 1920x1080 --frames 600 --allow-errors -- --autostart=mission=<id> --with-ui --fresh-settings --no-audio --speed=0 --cap=600 --cap-out=/tmp/m`, or play it with `--autostart=mission=<id> --campaign-unlock`.

The nine shipped missions (`tut_field_training` and `op_napc`, `op_nec`, `op_olm`, `op_def`, `op_pd`, `op_han`, `op_ae`, `op_sap`) were written with the small Python DSL in `tools/py/mis3/` (`lib.py` plus one module per mission). `python3 tools/py/gen_missions.py [id ...]` regenerates the JSON files and the manifest list; run in a scratch copy it reproduces the shipped files byte for byte. After a hand edit of a generated JSON file, port the change into the module or stop using the generator for that mission. `demo_ambush.json` is hand written (the generator never touches `demo_*` files). New missions must be listed in `manifest.json` (the generator does that for its files) and add a result to the campaign UI automatically (group `operation` joins the ring).

## Replays

Every match is recorded by `NetSession` into a temporary file and finalised as `autosave_1.mfreplay` in `user://replays` (older ones rotate up to `net/replay_autosave_count`, default 3; a crash keeps its recording). A `.mfreplay` holds the match configuration, the data hash and the command stream with periodic checksums, so playback is a re-simulation (`NetReplayPlayer`, `AppReplay`, `AppReplaySession`) and every recorded CHECK is compared (a mismatch is shown as divergence). Backward seeks rebuild the world from tick 0.

| Tool | Purpose |
|---|---|
| `python3 tools/py/app_replay_proof.py [--ticks 6000 --players 4 --seed 7 --linux]` | Records a headless match through the real app, plays it back through the real replay path and compares the `APPTEST_CK` lines, the player statistics, a seek demo and the end state (`APP_REPLAY_PROOF RESULT=OK`) |
| `tools/gd run res://src/app/boot.tscn -- --autostart=replay=<file> --ck-lines [--with-ui ...]` | Play one recording (flags above) |
| `tools/gd run res://tests/net/make_replay_fixture.gd` | Regenerate the golden fixture `tests/fixtures/net/replays/xplat_2p_ai.mfreplay`; the second fixture is recorded by the game itself (command in the script header) |
| `python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_net_replay.gd` | The fixture verifies identically on every OS |
| Replays screen > VERIFY | Time-sliced headless re-simulation of the selected recording |

## Audio pipeline

All audio is synthesised by `tools/py/audio` (numpy, seeded); speech is generated offline with Kokoro-82M (Apache-2.0). See `tools/py/audio/README.md` for the quick start (`bootstrap.py`, `build_all.py sfx|music|voice|check`). The result is committed under `game/assets/audio` with `provenance.json` and `NOTICE.txt`. Nothing under `game/assets/audio` is hand made or downloaded. **No human has listened to it**; the checks are measurements (loudness, budgets, clipping).

## Screenshots for the documentation

`docs/img/*.png` are 1920x1080 captures of the real game. Recreating them (examples with the flags above; replace paths): menus and screens with `--screen=<id>` (main menu, lobby, options `--page=interface`, Field Manual with `--focus_id=unit.napc.bastion_heavy_tank`, campaign with `--campaign-progress=tut_field_training:480:1,op_napc:900:1`, briefing `--mission=op_napc`, replays `--dir=<folder with a recording>`, `lan_browser`, `lobby --lan-host --no_help`); live frames with `--autostart=match --with-ui --cap=...`; the observer HUD with `--autostart=replay=<file> --with-ui --seek-to=7600 --follow --cam-zoom=0.35`; the mission HUD with `--autostart=mission=op_olm --with-ui --bots=human --speed=0 --cap=3000 --cap-keep`; the superweapon with `--scenario=showcase --sw-at=60 --focus=sw --cap=200,276`; the unit lineups with `napc_sheet.tscn` (see "Adding a unit"). Set `USER=Commander` (or any name) in the environment so the profile name on the screens is not your login. The files live in the repository, so keep them reasonably small.

## Export, packaging and release

Presets are in `game/export_presets.cfg` (Windows Desktop, Linux, macOS); output goes to `builds/<platform>/`. Full checklist: [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

```
python3 tools/py/version.py check|bump <major|minor|patch|X.Y.Z>   # VERSION is the single source; stamps project, presets, README badge and file names
python3 tools/py/gen_app_icon.py [--check]                           # app icon set (needs Pillow)
python3 tools/py/export.py install-templates --tpz <file>            # once
python3 tools/py/export.py export windows|linux|macos|all            # export and smoke-run on the host OS
python3 tools/py/export.py smoke macos                               # run the exported binary with --smoke
python3 tools/py/export.py report                                    # sizes of everything under builds/
python3 tools/py/pck_list.py builds/linux/MeridianFracture.pck --audit --project game
python3 tools/py/package_linux.py [--test-deb]                       # tar.gz and Debian .deb (pure Python; --test-deb installs it in Debian 12 and 13 containers)
python3 tools/py/package_windows.py                                  # zip with the .exe, console exe, .pck and .ico
python3 tools/py/package_macos.py                                    # .dmg and .zip (ad-hoc signed, not notarized)
```

The `.pck` is about 100 MB and byte-identical across OSes. The macOS app is ad-hoc signed (the CI job zips it with `ditto -c -k --keepParent`). **The Windows binary has not been executed on a Windows host by the maintainers**; CI is configured to run the smoke test on a Windows runner but has never run on GitHub.

## Continuous integration

`.github/workflows/build.yml`: a `tools` job (Python tests, version and icon consistency, bible mirror, strict balance validator), per platform (Linux, Windows, macOS) a `test` job (import, strict check, the suite in shards, headless quit stress, a screenshot smoke), determinism hash chains per runner and a final comparison, exports with the templates, smoke runs of the exports, packaging (including the DMG on the macOS runner), a Debian 12 container job for linux/amd64, and a nightly soak. The workflow exists and is checked for sanity by a Python test; it has **not yet been executed on GitHub**.

## Working agreements

Own only the files your task assigns; verify with `tools/gd check --strict` and the relevant `tools/gd test` filter; quote real results; verify Godot APIs with `tools/gd docs`; never run git in the shared tree (snapshots go to `.backups/`); never touch `Input/`. Balance numbers come from AI-versus-AI soaks; any change to data needs the validators, regenerated unit docs and a look at the replay fixtures.
