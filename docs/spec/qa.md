# MERIDIAN FRACTURE - Quality Assurance, CI, Packaging & Release (`docs/spec/qa.md`)

> Domain architect: **QA / CI / packaging / release / documentation / licensing**. Binding parent: `docs/ARCHITECTURE.md` (wins on conflict; deviations are listed as amendment requests in section 13).
> **Companion specs (read on 2026-09-29; this spec references them and never duplicates their content):** `docs/spec/qa_tooling.md` (toolsmith handbook: `tools/gd`, `tests/runner.gd`, `TestCtx`, lint rules L000-L010, Docker runner, `tools/py/xplat_determinism.py`, `export.py`, `package_windows.py`, `package_linux.py`, `sync_bible.py`, `.github/workflows/build.yml`), `docs/spec/sim_core.md` (kernel and `src/core`: `SimWorld`, `SimTestKit`, `SimInvariants`, the MASTER command and event catalogs, `SimReplay`, golden `sim_core.json`; it landed while this spec was being finished and is reconciled here, including its requests R21/R22 to QA), `docs/spec/net.md` (owns net unit/virtual-time tests, `net_harness.gd`, replays), `docs/spec/ai.md` (owns the AI-vs-AI soak engine `ai_soak_main.gd`, its presets and AI quality thresholds), `docs/spec/data_balance.md` (owns the numeric conversion/rounding model, `DefValidator`, `validate_balance.py`, data goldens), `docs/spec/economy.md`, `combat.md`, `abilities.md` (own their rule/scenario tests). **Not yet published, so tagged ASSUMPTION(domain):** map, view, ui, audio, app. **Published specs that still disagree with each other** (command opcodes and event codes, checksum section names, `MatchConfig` rule keys; risk R30) are handled by addressing commands, events and checksum sections by *name* through one adapter.
> **Evidence base.** Every engine/environment claim marked *(verified)* was checked on 2026-09-29 either in `tools/godot_docs` or by running the real Godot 4.7.2 binary on: macOS arm64 (native), macOS x86_64 slice (Rosetta, `arch -x86_64`), Debian 12 x86_64 (Docker Desktop, Rosetta). **Windows could not be verified locally**; every Windows statement is tagged *(unverified-win)* and is closed by a CI/manual gate. Numbers marked *(measured)* come from those runs; numbers marked *(budget)* or *(estimate)* are targets to be ratcheted with measurements.
> Requests to other domains are numbered `[QA-XR-n]` in section 13. No emojis anywhere in project text.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**One paragraph.** The game is only "AAA" if it is provably deterministic, never crashes, feels fast, installs cleanly on three operating systems and can be handed to a stranger with documentation and correct licences. QA turns each of those promises into an *executable gate*: a script that exits non-zero, a golden file that changes only with a recorded reason, a numeric budget, or a checklist an agent must fill by looking at real screenshots. Because no human reviews individual commits and there is no VCS in the working tree (agents must not run `git`), gates and goldens are the only memory the project has.

### 1.1 What this domain owns
* **Test strategy**: the pyramid (unit, scenario, determinism incl. cross-OS/arch, AI soak, network 2-process with fault injection, replay goldens, data validation, visual regression, performance, fuzzing), CI tiers T0-T5, milestone gates M0-M6 and the per-phase Definition of Done (5.17).
* **Cross-cutting harness** under `game/tests/harness/` (`Qa*` classes and entry-point scripts: `match_runner.gd`, `replay_verify.gd`, `canary_dump.gd`, `simcore_dump.gd`, `perf_bench.gd`, `fuzz_runner.gd`, `data_audit.gd`, `export_smoke.gd`, `qa_entry.gd`, `license_dump.gd`, `controls_dump.gd`) and the **shared test-support layer** the domain specs asked for (`QaWorld`: build a world, tick, command, spawn; `QaGolden`; `QaAssert`) - economy #27, data #22, combat #37, abilities #13.
* **The single-match CLI** required by the assignment (`match_runner.gd`, 5.4.1) and the QA-level acceptance criteria that apply to *every* headless match (robustness, determinism, leaks, budgets: HC1-HC8).
* **Python QA tooling** in `tools/py/qa/` (CI orchestrator, soak orchestrator over the AI presets plus QA plans, cross-arch comparator, UDP impairment proxy, packager, release verifier, log scanner, licence inventory, tolerance oracle) and `tools/py/net_two_process.py` (net.md XR-18; QA takes it, task QA-12).
* **Release engineering** on top of tooling's packagers: the shared payload (docs, licences, credits, checksums), macOS packaging (`.app` zip + optional `.dmg`), deterministic archives, `.deb` quality bar (lintian, dependencies for Debian 12/13), `verify_release.py`, install/uninstall verification, unsigned-app instructions.
* **Documentation deliverables** (outlines and generators here; final text written in tasks QA-17/QA-18 once the game exists): `README.md`, `docs/USER_MANUAL.md`, `docs/CONTROLS.md`, `docs/FACTION_GUIDE.md` (generated), `docs/KNOWN_ISSUES.md`, `docs/RELEASE_NOTES_<ver>.md`, `LICENSES/`, `CREDITS.md`.
* **Legal hygiene**: third-party inventory, font (OFL) and engine (MIT + bundled components) licence texts, TTS/audio provenance rules, project-licence decision record.
* **Runtime quality requirements** for other modules: crash/log conventions, settings/save locations, accessibility checklist, cross-platform pitfalls checklist (5.12-5.15).
* **Bug triage process** for agents (5.16), including flaky-test quarantine, and the golden manifest covering *all* domains' goldens (5.3).

### 1.2 What this domain does NOT own
| Not owned | Owner | Interface |
|---|---|---|
| `tools/gd`, `tests/runner.gd`, `TestCtx`, `TestSuite`, `TestLogger`, `check_scripts.gd`, linter `tools/py/lint.py` (L000-L010), `tools/docker/Dockerfile`, `tools/py/export.py`, `package_windows.py`, `package_linux.py`, `xplat_determinism.py`, `sync_bible.py`, `fetch_engines.py`, `tools/setup`, `.github/workflows/build.yml`, `game/export_presets.cfg`, `game/project.godot` | tooling | consumed as they exist; QA extends rather than duplicates; changes requested in section 13 |
| Sim/net/ai/data/map/view/ui/audio/app implementation and their own unit/scenario tests | each module | QA specifies acceptance gates and needed hooks, never edits their code |
| **AI-vs-AI soak engine** (`AiSoakRunner`, `AiMatchMatrix`, `ai_soak_main.gd`, presets `pr/smoke/nightly/weekly/arena`, `AiMetrics`, `ai_soak_report.py`, AI regression thresholds ai.md 10.5, `ai_baseline.json`) | ai | QA runs the presets in its tiers, adds robustness criteria HC1-HC8 and cross-OS runs (5.4) |
| **Net process harness** (`net_harness.gd`, `NETTEST` lines, S1-S20, P1-P5, D1-D4 of net.md 10) | net | QA orchestrates it (`net_two_process.py`), adds real-UDP impairment and cross-OS cases (5.6) |
| **Data validation** (`DefValidator`, `validate_balance.py`, rule ids V-*, goldens `data_hash.json`, `convert_vectors.json`, `resolver_golden.json`, the bp rounding model) | data | QA gates on them and adds cross-cutting checks + an independent tolerance oracle (5.10) |
| Rule/scenario tests of economy, combat, abilities (`test_prod_*`, `test_abil_*`, ...) | those domains | QA lists the ones that gate milestones (5.17) |
| Sim kernel and `src/core` tests (`test_fp`, `test_sim_*`, `SimTestKit`, `SimInvariants`, fixture `sim_core_fixture.json`, golden `sim_core.json`) | sim_core | QA runs them on every leg (job D00, 5.2), implements the lint rules that tooling's L003 does not already cover (`SL-3` remainder and `SL-5..SL-10`, 5.14) and builds its harness on `SimTestKit`/`SimInvariants` instead of duplicating them |
| Balance **numbers** (`game/data/balance/*.json`, `docs/balance/*`) | balance | QA owns the empirical conformance harness (5.5.2) |
| UI theme, key bindings, HUD layout, credits/licences screens | ui / app | QA specifies audits, generators, checklists |
| Procedural art/audio generators | view / audio | QA specifies provenance and licence rules |
| Game design, lore, faction bible | `Input/` (read-only) | QA only checks conformance |

### 1.3 Decisions reconcilers must know (summary)
1. **Everything is a script that exits non-zero.** Agent-facing acceptance = `tools/gd test ...` (in-process) or a `tools/gd run res://tests/harness/<entry>.gd -- <args>` job (long-running, own process) that prints one machine-readable result line and returns a documented exit code (`QaCli.Exit`, 4.1).
2. **Test placement.** The runner discovers `res://tests/**/test_*.gd` recursively (skipping dirs named `fixtures` and `harness`); ids are `<relative path>::<method>`; tests may `await`, use `t.set_timeout(s)` and are abandoned after 30 s. The toolsmith documents `game/tests/<module>/test_<thing>.gd`; the domain specs plan flat `game/tests/test_<area>_<topic>.gd` (ai, data, economy, abilities) or `tests/net/`. All are accepted; each domain test must finish in <= 20 s and belongs to T0. **QA-owned slow kinds live in dedicated directories `determinism/ fuzz/ perf/ content/ visual/` and are excluded from T0** via a runner `--exclude` option [QA-XR-3] (fallback: `ci.py` builds `--file` lists from `gd test --list`). A test needing > 20 s is a job (`gd run`), not a `test_*.gd`. This amends ARCHITECTURE section 11 (flat wording, `run(t)` sketch; the runner supports both `test_*` methods and legacy `run`).
3. **Determinism is proven on six legs, not one** (4.5): macOS arm64, macOS x86_64 (Rosetta), Debian 12 amd64 and arm64 containers, the exported *release-template* build, and Windows through the hosted-CI matrix job already written in `.github/workflows/build.yml` (or a manual run: the workflow has never been pushed, so Windows is still *(unverified-win)*). The comparison engine is the toolsmith's `xplat_determinism.py` (`HASH tick=<n> <hex>` lines; verified by the toolsmith: identical 10-hash chains on macOS arm64, linux/amd64 and linux/arm64); QA supplies the scenarios and adds legs B and F.
4. **Official Godot export templates (debug and release) refuse path overrides** *(verified: `--path` aborts with "compiled without support for path overrides"; `--script`, `--main-pack` and `--check-only` are not even listed in the templates' `--help`)*. QA code can therefore run inside an exported build only through a `--qa=<job>` user-arg hook in the boot scene, present only in dedicated QA export presets that include `tests/harness/**`. Release presets exclude tests entirely.
5. **Zero tolerance for silent errors**: a run is green only if exit code is 0 **and** no engine error lines **and** no `ObjectDB instances leaked at exit` warning *(verified: exit code stays 0 and it is only a WARNING line, which `gd`'s error matcher ignores)*. QA requires strict-mode log scanning (5.1, QA-XR-1).
6. **Goldens are versioned data**: one `game/tests/golden/MANIFEST.json` covers every golden of every domain (data's `data_hash.json`, `convert_vectors.json`, `resolver_golden.json`, ai's baselines, net's fixtures index, QA chains); a revision counter and a mandatory reason accompany every change (5.3). The owning domain updates its own golden through `golden_manifest.py update --reason`.
7. **Budgets are calibrated, not absolute**: perf numbers are stated for the reference machine (RM = Apple M5 Max) and scaled by a measured calibration factor elsewhere (5.8).
8. **`user://` is shared between all processes of the same project on a machine** *(verified: concurrent agents already share `~/Library/Application Support/MeridianFracture/`, including `last_test_run.json` and `shader_cache/`)*. Parallel jobs and multi-process net tests must sandbox `HOME` (macOS/Linux) or `APPDATA` (Windows) per process (5.6, QA-XR-2).
9. **Long jobs never hold the live project lock.** `tools/gd` serialises imports with a shared/exclusive lock; a 3-hour soak launched through `gd run` on the live `game/` would hold a shared lock and make every other agent's import wait for it (the handbook's gotcha 13: a hung reader stalls every import behind it). `ci.py` and `soak.py` therefore copy `game/` into a frozen mirror `.cache/qa/<run_id>/game/` (excluding `.godot`), import once there and run every job with `GD_ROOT`/`GD_GAME_DIR` pointing at the mirror (documented env overrides). A run also tests one frozen tree while other agents keep editing. Short T0/T1 steps may use the live project.
10. **QA debug commands are extra modes of sim_core's `DEBUG` command** (opcode `0x0F`, gated by `SimMatchRules.allow_debug`, default 0, part of the `config_hash`; sim_core 6.1 defines mode 1 = grant credits and mode 2 = spawn). QA asks for modes 3..6 (kill, reveal, set-hp, charge) and a `TARGET` wire field ([QA-XR-17]); there is no QA-reserved opcode range. Desync injection is not a command (it would run on every peer): `QaCorrupt` mutates ONE peer's public sim state from the test harness (6.3).
11. **Soak division of labour** (5.4): the AI domain's harness is the *roster-matrix engine* (presets, `AiMetrics`, adjudication, report, AI thresholds); QA's `match_runner` is the single-match primitive for scenarios, content, cross-arch and perf; QA adds the robustness criteria HC1-HC8 to every soak, a 96-match **rotation** plan with proven coverage for cross-OS runs, endurance (3 x 60 min, 8 players) and the content-coverage gate.
12. **Content coverage is a gate**: all 156 units, 29 structures, 40 research, 48 support powers and 8 superweapons must be exercised without error by a roster-specific content bot (5.5) before M3 closes.
13. **Data model**: `data_balance.md` 5.2/5.5 (basis points, one rounding for layers 0-2, ceil-based floors, integer-ms durations) is normative. QA does not define a competing rounding table; it checks the exact-rational reading of the bible formula within a tolerance of one unit/tick (an independent oracle that catches formula and scope errors both PY and GDScript implementations could share).
14. **AI level names are Easy / Medium / Hard / Brutal** (ids 0..3, ai.md 7.1); the four AI styles are doctrine / aggressive / defensive / wildcard.
15. **Release packaging builds on tooling's `package_windows.py`/`package_linux.py`** (file names `meridian-fracture-<ver>-<os>-<arch>.<ext>`, `.deb` built in pure Python, reproducible tar timestamps); QA adds macOS packaging, the shared payload (docs, licences, credits, `SHA256SUMS.txt`), the `.deb` quality bar (lintian 0 unoverridden errors, DEP-5 `copyright`, changelog, dependency list verified on Debian 12 and 13) and `verify_release.py`. The macOS `.dmg` (`hdiutil`) is the only non-reproducible artefact.
16. **The project's own licence is undecided** (owner decision). Until recorded in `docs/AMENDMENTS.md`, README states there is no licence grant; M6 is blocked without it (risk R5).
17. **TTS**: shipped voice audio may only come from generators whose licence and provenance are recorded (`PROVENANCE.json`); macOS `say`/system voices and Piper voices without a permissive `MODEL_CARD` are prohibited; runtime OS TTS for accessibility is allowed (5.11).
18. **sim_core's requests to QA are accepted (its R21/R22).** The `test_sim_*` suites run in T0 on macOS and, at T2, in the Debian amd64 and arm64 containers (`gd linux test`); any `SCRIPT ERROR`/`ERROR:` line fails a run (already part of the definition of green, 5.1); job **D00** (`simcore_dump.gd`: `Fp` digests, golden codec batch, `config_hash`, S-CORE-1 chain, five chaos-fuzz games) runs on all legs and is compared with `golden/sim_core.json`; its lint rules L-1..L-10 (8.3 there) are enforced under the ids `SL-1..SL-10` - `SL-1`, `SL-2` and `SL-4` are already covered by tooling's L003 (QA only pins them with seeded fixtures), `SL-3` (remainder) and `SL-5..SL-10` are implemented in `tools/py/qa/check_sim_rules.py` (5.14). The sim kernel's own tests are not repeated by QA.

### 1.4 Evidence base (verified 2026-09-29)
| Fact | Value | Consequence |
|---|---|---|
| Engine | Godot 4.7.2 stable official; macOS binary is universal (`x86_64 arm64`), Rosetta installed | three native-ish legs on one Mac |
| Docker host | Docker Desktop, aarch64 VM, 18 cpus, 8.3 GB RAM; `--platform linux/amd64` runs the x86_64 engine via Rosetta (`VirtualApple @ 2.50GHz`) | Linux x86_64 leg is real x86_64 code |
| Calibration loop (3,000,000 iterations xorshift128, `QaCalibrate`) | arm64 native 294 ms; macOS x86_64/Rosetta 440 ms (x1.50); Debian amd64/Rosetta 767 ms (x2.61); identical results `acc=33451325123209 s3=2054281984` | RM factor 1.0; Rosetta legs are slow-CPU proxies |
| Process baselines | headless empty script: engine start 64 ms, 0.25 s wall, peak RSS 120 MB, static memory 23.5 MB; container start 1.3 s | fixed cost per process; batch scenarios per process |
| GDScript cost model (RM arm64 / Rosetta x86_64) | SoA int update (~20 statements) 128 / 402 ns; RefCounted-field update 229 / 540 ns; 9-cell neighbour scan (~7 hits) 1,451 / 3,615 ns; static call 83 / 174 ns; int dict lookup 54 / 94 ns | basis of 5.8 |
| Integer semantics (identical on all legs) | `-7/2=-3`, `-7%3=-1`, `>>` arithmetic on negatives at runtime (parser rejects constant negative shifts), shift count masked mod 64 (`1024>>64=1024`), 64-bit wrap, `x/0` = engine error + result 0 | canary 5.2; sim code uses only constant shift counts or `Fp.mul_q16` (lint `SL-7`) and `Fp.self_test()` re-checks these facts at boot (sim_core 8.4) |
| Rounding | `roundi(0.5)=1`, `roundi(-0.5)=-1`, `roundi(2.5)=3` (half away from zero); float trap: `ceili(6*(1-0.20)*20)` = 97 vs exact 96; 115 of 1,377 (base,pct) combos differ | integer-ms/bp conversion mandatory (data 5.2) |
| JSON | every number parses as float; `9007199254740993` becomes `...992.0`; `JSON.stringify` sorts keys by default | hashes as hex strings; canonical goldens |
| Formatting | `"%x" % -255 = "-ff"`; `String.num_uint64(-1,16)="ffffffffffffffff"`; `str(0.1+0.2)="0.3"`; `str(-0.0)="0.0"` | `QaChain.hex32/hex64` use masked `%08x` |
| Ordering | Dictionary keeps insertion order (erase+reinsert moves to end); `sort_custom` is unstable (ties scrambled but identical on all legs) | DR-6/DR-7; engine-upgrade canary |
| Errors | `OS.add_logger` captures `push_error`(type 0), `push_warning`(1), script errors incl. asserts and int divide-by-zero (2), each with a script backtrace; a script error aborts only the erroring function (an `int` function then returns 0); an error inside `_init`/`_initialize` leaves the SceneTree idling forever | runner watchdogs already implemented by tooling |
| Leaks | 1,000 RefCounted 2-cycles: `WARNING: 2002 ObjectDB instances were leaked at exit`, `OBJECT_COUNT` +2,000; orphan Node: 1 instance leaked | leak gates 5.8 |
| Exports | templates in `.cache/godot_export_templates.tpz` include windows/linux/macos (universal 170 MB release binary); templates abort on `--path` | QA export presets + `--qa` hook |
| Case sensitivity | editor on macOS resolves `res://mixedcase.gd` for `MixedCase.gd`; inside a `.pck` only the exact case resolves (`ResourceLoader.exists` false; `FileAccess.file_exists` is false for scripts even in exact case) | L001 + export resource manifest using `ResourceLoader.exists` |
| User dirs | `user://` = `~/Library/Application Support/MeridianFracture/` (mac), `$XDG_DATA_HOME` or `~/.local/share/MeridianFracture/` (Linux); `HOME` override redirects on mac; `XDG_DATA_HOME` override redirects on Linux and is ignored on mac | sandbox recipe 5.6 |
| Logging | `debug/file_logging/*` exists (defaults: off, `.pc` on, `max_log_files` 5, path `user://logs/godot.log`; `project.godot` currently sets both off); rotation at startup renames to `godot<YYYY-MM-DDTHH.MM.SS>.log` (mtime of the old file) and `max_log_files` counts the current file | 5.12 |
| Engine licence API | `Engine.get_license_text()` (1,149 chars, MIT), `get_license_info()` (19 licences), `get_copyright_info()` (102 components) | Licenses screen and `LICENSES/GODOT_THIRD_PARTY.txt` are generated, not hand-copied |
| Linux binary | hard deps only glibc (>= 2.28 symbols, ELF min kernel 5.15); everything else `dlopen`ed: libX11, Xcursor, Xext, Xi, Xinerama, Xrandr, Xrender, xkbcommon, wayland-client/cursor/egl, libdecor-0, EGL, GLESv2, vulkan, asound, pulse, udev, dbus-1, fontconfig, speechd | Debian 11 (kernel 5.10) is unsupported; `.deb` Depends 5.13 |
| Accessibility | `AccessibilityServer` (AccessKit) exists; CLI `--accessibility auto/always/disabled`; setting `accessibility/general/accessibility_support`; `Control.accessibility_name/description/live` | A-13 |
| Renderer defaults | Forward+; RD driver: macOS Metal, Windows Vulkan, Linux Vulkan; fallbacks `rendering_device/fallback_to_opengl3` etc. exist and are enabled in `project.godot` | X-21 |
| Sim command and event catalogs | sim_core MASTER catalog: 40 command opcodes (core `0x01-0x04` and `0x0F`; orders `0x10-0x25`; production and research `0x30-0x3A`; powers `0x50-0x51`), wire `u8` with varint fields; events `0x01-0x74` as 10-int records. economy.md, abilities.md, combat.md and net.md still carry their own numeric ranges (`CMD_*` 120..149, events 200..499, net command types 240..255) | QA addresses commands and events by **name** through `QaSimAdapter` and never hard-codes numbers (6.4); the disagreement is risk R30 |
| Existing cross-platform harness (toolsmith) | `xplat_determinism.py <scenario.gd>` runs native + Debian amd64 + Debian arm64 (`tools/godot-linux-arm64` now provisioned) and diffs `HASH tick=<n> <hex>` chains; identical 10-hash chains on macOS arm64, linux/amd64, linux/arm64; `--only-local --out F` + `--compare a b c` for CI; `--diverge=os/arch` self-test reports the first bad tick | QA reuses it (legs A, C, D, E) and adds B and F |
| Container renderers | Debian 12 lavapipe on aarch64 aborts for Forward+ and Mobile; `gd linux --arch arm64 shot` falls back to `gl_compatibility` by itself; amd64 renders all three | visual leg C is Forward+, leg D is compatibility only |
| File replacement | `DirAccess.rename` is remove-then-rename, not atomic (toolsmith gotcha 7) | settings/golden writes need a `.bak` recovery step (5.12) |
| Project lock | imports take an exclusive lock, everything else a shared lock; a long or hung reader stalls every import behind it (`gd ps` shows the pid) | long QA jobs run on a frozen mirror (decision 9) |
| Tooling exit codes | 0 ok, 1 failure, 2 usage/nothing matched, 3 engine `ERROR:` lines, 124 timeout/stall kill, 141 pipe closed | `QaCli.Exit` uses the same 2 and 3 |
| Existing packages | `package_windows.py` -> `meridian-fracture-<ver>-windows-x86_64.zip` (38.1 MB, includes console wrapper); `package_linux.py` -> `meridian-fracture-<ver>-linux-x86_64.tar.gz` (28.4 MB) and a pure-Python `meridian-fracture_<ver>_amd64.deb` (28.4 MB, `/opt/meridian-fracture`, `/usr/bin` symlink, `--test-deb` installs it in Debian 12); macOS: `ditto` zip of the ad-hoc-signed `.app` (171.8 MB) | QA adds payload, macOS script, lintian bar, verification |

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

QA classes use the prefix **`Qa`** (tests/tooling are exempt from linter L004's module prefixes; L009 still applies: file = snake_case of class). No file under `game/src/**` may mention `Qa*`, `TestCtx`, or `res://tests` (proposed rule L014). All harness classes live in `game/tests/harness/` (never scanned for tests). Files <= 1500 lines.

### 2.1 Harness classes (`game/tests/harness/`)
| File | `class_name` | Responsibility |
|---|---|---|
| `qa_cli.gd` | `QaCli` | Argument parser accepting `--k=v`, `--k v` and bare flags; job dispatch table; protocol-line emitter; `Exit` codes |
| `qa_log_guard.gd` | `QaLogGuard` | `Logger` subclass for entry points: counts errors/warnings, keeps first 20 samples, per-phase marks (same contract as `TestLogger`, plus warnings) |
| `qa_temp.gd` | `QaTemp` | Per-process scratch dir `user://qa_tmp/<pid>/`, auto-cleaned (tests never write elsewhere) |
| `qa_chain.gd` | `QaChain` | `.chain` file read/write/compare, first-divergence finder, `hex32/hex64` |
| `qa_golden.gd` | `QaGolden` | Golden text/JSON compare (LF-normalised), manifest verification, guarded update (all domains) |
| `qa_assert.gd` | `QaAssert` | Assertion helpers over `TestCtx`: `no_report_errors`, `chains_equal`, `snapshot_objects`, `no_object_leak` (3.2) |
| `qa_world.gd` | `QaWorld` | Test-support world builder over the real game data for domain unit/scenario tests: `make`, `tick`, `cmd`, `queue`, `spawn`, `grant`, `checksum`, `dispose` (economy #27, combat #37); the kernel's fixture-data kit is sim_core's `SimTestKit`, on which QaWorld builds and which it never duplicates |
| `qa_canary.gd` | `QaCanary` | Engine canary lines (10.2), data-hash lines |
| `qa_calibrate.gd` | `QaCalibrate` | Machine calibration loop, checksum, factor |
| `qa_metrics.gd` | `QaMetrics` | Tick timing histogram, per-system timing (fed by `QaTimedSystem`), memory/object sampling, leak deltas |
| `qa_timed_system.gd` | `QaTimedSystem` | Transparent `SimSystem` decorator that times `update` of stages 2-11; used only when the sim offers no profiling hook [QA-XR-16]; must not change the checksum |
| `qa_game_inv.gd` | `QaGameInv` | Game-level invariants G1-G7 (4.1) on top of sim_core's structural `SimInvariants.check` |
| `qa_corrupt.gd` | `QaCorrupt` | Desync injection into ONE peer by mutating public sim state (6.3); QA/debug builds only |
| `qa_sim_adapter.gd` | `QaSimAdapter` | The only file touching sim/data/map/ai/net APIs (rename shield): `SimWorld`, `SimMatchConfig`, `SimInvariants`, `SimCommand` builders by MASTER-catalog name, MASTER-catalog events, net's `NetSession` for the session driver |
| `qa_match_spec.gd` | `QaMatchSpec` | Match request value object; parse/validate; to net `MatchConfig` dictionary |
| `qa_match_result.gd` | `QaMatchResult` | Result value object, JSON schema v1 (shares field names with `AiMatchResult` where they overlap) |
| `qa_match.gd` | `QaMatch` | The headless match loop (5.4.2) |
| `qa_event_stats.gd` | `QaEventStats` | Folds normalised events into per-player stats, coverage sets, first-time milestones |
| `qa_stuck_detector.gd` | `QaStuckDetector` | Stuck-unit detection with the AI domain's definition (600 ticks, < 1 cell) |
| `qa_soak_plan.gd` | `QaSoakPlan` | Deterministic plans: 96-match rotation, endurance, content; writes `plan.json` for `ai_soak_main.gd --plan` |
| `qa_soak_judge.gd` | `QaSoakJudge` | Robustness criteria HC1-HC8 on any per-match result (QA or `AiMatchResult`), batch verdicts, Wilson intervals |
| `qa_content_bot.gd` | `QaContentBot` | Coverage-driven scripted player (builds/produces/researches/fires everything) |
| `qa_balance_probe.gd` | `QaBalanceProbe` | Sim-level TTK / equal-cost RPS / sortie / structure-kill probes from `balance/global.json targets` |
| `qa_fuzz_rng.gd` | `QaFuzzRng` | Independent xorshift128 test RNG (not `SimRng`) |
| `qa_fuzz_commands.gd` | `QaFuzzCommands` | Command fuzzer (shape-aware + byte-level) |
| `qa_fuzz_packets.gd` | `QaFuzzPackets` | Deep (T3) packet/datagram/replay-bytes fuzzer for `Net*` decoders and sessions (net's own suites cover T0/T1) |
| `qa_fuzz_files.gd` | `QaFuzzFiles` | Mutators for JSON/CFG/replay files (settings, data, replays) |
| `qa_data_audit.gd` | `QaDataAudit` | Cross-cutting data/asset audit + tolerance oracle; checks split across `qa_data_checks_gate.gd`, `_oracle.gd`, `_assets.gd` (`QaDataChecksGate`, ...) |
| `qa_perf.gd` | `QaPerf` | Perf scenario builders PS0-PS6/PV1-PV4, budget comparison, baseline ratchet |
| `qa_img_diff.gd` | `QaImgDiff` | PSNR/mean-abs/region diff (`Image.compute_image_metrics`), blankness/placeholder detectors, diff heatmap |
| `qa_contrast.gd` | `QaContrast` | WCAG contrast, CVD simulation, CIEDE2000 (float allowed: not sim) |
| `qa_a11y_audit.gd` | `QaA11yAudit` | Control-tree accessibility audit (names, focus order, states) |
| `qa_layout_audit.gd` | `QaLayoutAudit` | Overflow/clipping/overlap audit at resolutions x UI scales |
| `qa_visual_case.gd` | `QaVisualCase` | Data-driven visual case loader/builder (used by `visual_case.tscn`) |
| `qa_export_manifest.gd` | `QaExportManifest` | Enumerate resources, verify with `ResourceLoader.exists` in exported builds |
| `qa_replay_tools.gd` | `QaReplayTools` | Verify, diff, minimise (ddmin) `.mfreplay` files through `NetReplay*` |
| `qa_licenses.gd` | `QaLicenses` | Dumps `Engine.get_license_*` data as JSON for the licence generator |

### 2.2 Entry-point scripts (`extends SceneTree`, no `class_name`, in `game/tests/harness/`; run with `tools/gd run res://tests/harness/<name>.gd -- <args>`)
`match_runner.gd` (5.4.1), `replay_verify.gd`, `canary_dump.gd`, `simcore_dump.gd` (job D00, 5.2), `perf_bench.gd`, `fuzz_runner.gd`, `data_audit.gd`, `export_smoke.gd`, `license_dump.gd`, `controls_dump.gd`; plus `qa_entry.gd` (a `Node`, instantiated by `boot.gd` when `--qa=<job>` is present and the file exists; exported QA builds only) and the scene `game/tests/visual/visual_case.tscn` (+ `visual_case.gd`). Rule: an entry script contains **no logic** beyond `QaCli.dispatch(job, OS.get_cmdline_user_args())` and the pattern `_initialize()` -> `process_frame` one-shot watchdog -> `quit(code)` copied from `runner.gd` (an error inside `_initialize` otherwise hangs the process *(verified)*). Net process tests use net's `game/tests/net/net_harness.gd`; AI soaks use `game/tests/ai_soak_main.gd`; QA does not duplicate them.

### 2.3 Test placement (`game/tests/`)
* **Domain tests** (unit + scenario, T0, <= 20 s each): flat `test_<area>_<topic>.gd` (`<area>` = module/subsystem prefix such as `core`, `data`, `map`, `sim`, `prod`, `combat`, `abil`, `zone`, `vision`, `ai`, `net`, `view`, `ui`, `audio`, `app`) or `tests/<area>/test_*.gd` (net). Helper kits that are not tests (`def_test_kit.gd`, `ai/ai_mock_world_view.gd`, `tools/data_cli.gd`) must not start with `test_`.
* **QA-owned kinds** (dedicated directories): `determinism/` (D-scenarios, chains, replays), `fuzz/`, `perf/`, `content/`, `visual/` (self-skips when `DisplayServer.get_name() == "headless"`) - excluded from T0; `a11y/`, `qa/` (tests of the harness), `regress/` (one file per closed bug: `test_bug_<NNNN>_<slug>.gd`) - part of T0.
* **Support:** `fixtures/<area>/` (scenario definitions, command scripts, fuzz corpora; net's `fixtures/net/replays/`), `golden/` (all goldens + `MANIFEST.json` + `CHANGELOG.md`), `visual/{cases.json,checklist.json,golden/,review/}`, `perf/budgets.json`.
* **Rules:** seeds are explicit (never `randi`); tests build worlds only through `QaWorld` or the domain's kit and call `dispose()`; no wall-clock, no `user://` writes outside `QaTemp`; tests that provoke engine errors declare `t.expect_errors(n)` (the real runner fails any undeclared engine error).

### 2.4 Python tooling (`tools/py/qa/`, stdlib only; unit tests in `tools/py/tests/test_qa_*.py`)
| File | Purpose |
|---|---|
| `ci.py` | Tier runner T0-T5 on a frozen mirror for long steps, report writer (`builds/qa/<run_id>/summary.json/.md`), `status` matrix for gates; extends the jobs of `.github/workflows/build.yml` |
| `soak.py` | Runs `ai_soak_main.gd --preset=...` and QA plans (`rotation`, `endurance`, `content`) in parallel shards, applies HC criteria + logscan, aggregates coverage |
| `crossarch.py` | Thin driver over tooling's `xplat_determinism.py`: runs a scenario set on legs A, C, D (and B, F, E where available), adds legs B (Rosetta) and F (QA export), and on divergence re-runs both legs with `match_runner --sections-at=<tick>` and prints the differing `report_at` sections (5.2) |
| `udp_impair.py` | Seeded UDP impairment proxy (delay, jitter, loss, dup, reorder, bandwidth, blackout, corrupt) for real-ENet tests |
| `../net_two_process.py` | Orchestrator: spawns host + N clients of net's `net_harness.gd` with sandboxed `HOME`, optional proxy, external `kill -STOP/-9`, parses `NETTEST` lines |
| `release_payload.py` / `package_macos.py` / `verify_release.py` | Build the shared payload (docs, licences, credits, checksums); macOS zip/dmg; post-build verification of every package (tooling's `package_windows.py` / `package_linux.py` produce the Windows and Linux archives) |
| `logscan.py` | Scans captured output for forbidden patterns (5.1) |
| `golden_manifest.py` | `verify` / `update --reason` for `game/tests/golden/MANIFEST.json` |
| `licenses.py` | Builds `LICENSES/THIRD_PARTY.json/.md`, audits fonts/audio provenance |
| `ref_oracle.py` | Exact-rational tolerance oracle for the bible layering formula (5.10) |
| `api_coverage.py` | Static "public function referenced by a test" coverage |
| `bugs.py` | Bug index, status checks, owner routing, snapshot bisect (5.16) |
| `gen_controls_md.py`, `gen_faction_guide.py` | Generated documentation |
| `visual_report.py` | Contact sheets and review worklist from `cases.json` |
| `check_xplat.py` | QA-required static checks (proposed rules L011-L016) until tooling absorbs them |
| `check_sim_rules.py` | Sim-kernel lint rules `SL-3` (remainder) and `SL-5`..`SL-10` from sim_core 8.3 (its L-1..L-10); `SL-1`, `SL-2`, `SL-4` are already enforced by tooling's L003 and only pinned by fixtures (5.14) |

### 2.5 Data, golden and documentation files
`game/tests/golden/{MANIFEST.json,CHANGELOG.md,engine_canary.txt,perf_baseline.json,chains/*.chain,replays/*.mfreplay}` plus domain goldens registered in the manifest (`sim_core.json`, `data_hash.json`, `convert_vectors.json`, `resolver_golden.json`, `validator_allow.json`, `ai/baselines/ai_baseline.json`), `game/tests/fixtures/{scenarios/*.json,scripts/*.cmds.json,soak/plans/*.json,fuzz/corpus/*,fuzz/regress/*,content_waivers.json,balance_waivers.json}`, `game/tests/perf/budgets.json`, `game/tests/visual/{cases.json,checklist.json,golden/<platform>/*.png,review/*.json}`, `game/tests/quarantine.json`, `tools/py/qa/{tiers.json,impair_profiles.json,logscan_allow.txt}`, `docs/bugs/BUG-<NNNN>-<slug>.md`, `docs/bugs/OWNERS.md`, `LICENSES/*`, `CREDITS.md`, `README.md`, `docs/{USER_MANUAL,CONTROLS,FACTION_GUIDE,KNOWN_ISSUES,QA_MANUAL_TEST_PLAN}.md`, `game/data/text/credits.json`. Schemas in section 7.

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

Conventions: harness code runs *outside* the deterministic core, so floats, `Time.*` and `OS.*` are allowed here; anything that produces a **golden or a schedule** (`QaSoakPlan`, `QaChain`, `QaFuzzRng`, `QaCanary`) is integer-only and pure. Every public method is *total*: it returns an error code / `{}` / `null` and never raises an engine error (an engine error fails the surrounding test and, in entry scripts, the run).

### 3.1 `QaCli` (`qa_cli.gd`)
```gdscript
class_name QaCli extends RefCounted
enum Exit { OK = 0, FAILED = 1, USAGE = 2, ENGINE_ERRORS = 3, WALL_LIMIT = 4, DIVERGED = 5, UNSUPPORTED = 6 }
# 124 = killed by `gd` (timeout/stall) and 128+n = signal are produced OUTSIDE Godot. 2 and 3 deliberately equal tools/gd's EXIT_USAGE / EXIT_ENGINE_ERRORS.
static func parse(args: PackedStringArray) -> Dictionary          # {"_": Array[String] positionals, "key": String or true}; "--k=v", "--k v" (v = next token that does not start with "--"), bare "--flag"
static func get_int(a: Dictionary, key: String, default_value: int) -> int      # non-numeric => sets QaCli.usage_error and returns default_value
static func get_str(a: Dictionary, key: String, default_value: String) -> String
static func get_list(a: Dictionary, key: String) -> PackedStringArray            # comma separated, trimmed, empties dropped
static var usage_error: String                                   # "" when parsing was clean
static func dispatch(job: String, args: PackedStringArray) -> int  # jobs: match, replay_verify, canary, simcore, perf, fuzz, data_audit, export_smoke, license_dump, controls_dump; returns QaCli.Exit
static func emit(tag: String, payload: Dictionary) -> void       # ONE line: "<TAG> <json>" ; tags QA_START, QA_PROGRESS, QA_RESULT, QA_FAIL (machine-parsed by tools/py/qa/*); a match additionally prints `HASH tick=<n> <hex8>` lines (checksum every 20 ticks) so tooling's xplat_determinism.py can diff it unchanged
```
`QA_RESULT` is always the last stdout line of a job that ran to completion; a job without it is a crash by definition (`ci.py` and `soak.py` enforce this, closing the "exit code 0 with a broken runner" hole: a script error aborts only the erroring function, and an aborted `int` function returns 0 *(verified)*).

### 3.2 Match stack (`match_runner.gd` -> `QaMatch`)
```gdscript
class_name QaMatchSpec extends RefCounted                          # fields in section 4.2
static var last_error: String
static func from_args(a: Dictionary, roster_ids: PackedStringArray) -> QaMatchSpec   # null + last_error on bad input (unknown roster, size not multiple of 8, ...)
static func from_dict(d: Dictionary) -> QaMatchSpec
func to_dict() -> Dictionary
func validate(roster_ids: PackedStringArray) -> PackedStringArray  # human-readable problems, empty = ok
func to_match_config() -> Dictionary                               # canonical net MatchConfig (net.md 7.1: seed, map{family,size,seed,layout_players}, rules, players[]): ints/strings/bools only; the adapter applies NetMatchConfig.normalize()

class_name QaMatchResult extends RefCounted                        # JSON schema v1 in section 7.2
var d: Dictionary
func is_ok() -> bool                                               # d.ok
func exit_code() -> int                                            # QaCli.Exit
func to_json() -> String; static func from_json(s: String) -> QaMatchResult

class_name QaSimAdapter extends RefCounted                         # THE seam, one instance per world. Names from sim_core.md are published; the rest is ASSUMPTION(data|map|ai|net|app). Rename shield: if a domain renames an API only this file changes; `test_qa_adapter_contract` (T0) lists every unresolved symbol per domain.
enum Driver { DIRECT = 0, SESSION = 1 }
var world: RefCounted                                              # the SimWorld (sim_core 3.4); the harness reads it freely and mutates it only through commands, `QaCorrupt` (6.3) and direct spawns in non-replayed perf scenarios
var data: RefCounted                                               # GameData
var driver: int
static func load_game_data() -> RefCounted                         # GameData.load_default() (data)
static func roster_ids(data: RefCounted) -> PackedStringArray      # the 32 ids in BIBLE ORDER (faction order napc,nec,olm,def,pd,han,ae,sap; vanilla first, then the 3 subfactions in bible order); GameData tables are in sorted-id order (sim_core R1), so the adapter reorders through the bible faction lists
static func data_hash(data: RefCounted) -> int                     # GameData.data_hash (u32)
static func open(spec: QaMatchSpec, driver: int, opts: Dictionary = {}) -> QaSimAdapter   # SESSION: NetSession.local_from_config + NetClock.manual(), speed unpaced, fixed_input_delay_turns = spec.fixed_delay = the production launch path, world = session.world() (net.md 3.1). DIRECT: builds the world like net's world_builder (SimMatchConfig from the MatchConfig, MapGenerator.generate(cfg.map), SimWorld.new(cfg, data, map, {events: true, ...opts})). null + QaMatchSpec.last_error on failure
func make_ai(pid: int, level: int, style: int, seed_value: int) -> Callable   # AiFactory.make -> Callable(world, out) (ai.md 13.16, net.md 5.6); seed = mix32(match_seed ^ ((pid+1) * 0x9E3779B9))
func advance() -> int                                              # one lockstep TURN = 2 ticks (fewer while paused); returns the ticks executed. SESSION: clock.advance_us(TURN_US); session.poll(). DIRECT: emulates net's LOCAL pipeline (AI thinks at turn boundary E for target turn E + D when (E + pid) % period(level) == 0; scripted commands whose issue turn == E, executing at turn E + D; commands ordered by (pid, seq); world.apply_turn(cmds); world.step() x 2); test_qa_driver_equivalence proves both drivers give equal chains
func tick() -> int                                                 # world.tick (game ticks; differs from world.step_no only while paused)
func checksum_now() -> int                                         # world.checksum() (u32; ~1.8 ms at 1,200 units: never per tick)
func checksum_at(tick: int) -> int                                 # from world.checksum_log pairs [tick, checksum]; -1 if not a checkpoint
func checksum_parts(tick: int) -> Dictionary                       # world.report_at(tick).sections {"world","rng","players","entities","map","sys.<name>.<stage>": digest}; {} when older than the last 8 checkpoints
func drain_events() -> Array[Dictionary]                           # world.events.take() decoded (10-int records: type, tick, a..h) into the normalised form of 4.3; empties the buffer
func cmd(name: String, fields: Dictionary) -> RefCounted           # SimCommand by MASTER-catalog NAME (sim_core 6.1: "PRODUCE", "PLACE", "USE_POWER", ...) with named fields {ids, target, def, x, y, angle, count, mode, flags}; economy.md CMD_* aliases accepted; unknown name -> null + last_error
func submit(cmd: RefCounted) -> void                               # DIRECT: queued for the turn the emulated pipeline assigns; SESSION: session.submit path
func validate() -> PackedStringArray                               # SimInvariants.check(world) (INV-1..14, sim_core 10.2) + QaGameInv.check(self) (G1..G7, 4.1); empty = ok
func outcome() -> Dictionary                                       # {over: world.match_state == 1, winner_team, end_reason, end_tick, defeated: {pid: elim_tick}}
func player_info(pid: int) -> Dictionary                           # {credits, power_produced, power_consumed, unit_count, struct_count, st_*: the SimPlayer counters, can_build: [def ids] (economy q_* queries)}
func dump_state() -> String                                        # JSON.stringify(world.dump_state(), "  ", true): deterministic text for diffs
func close() -> void                                               # drops every reference (world, session, clock, AIs); MUST be called on every path; test_qa_world_frees proves the world is then freed (sim_core forbids reference cycles, its lint L-8; [QA-XR-15])

class_name QaMatch extends RefCounted
static func run(spec: QaMatchSpec, guard: QaLogGuard, progress: Callable = Callable()) -> QaMatchResult
# Owns the adapters (main and twin), AIs and metrics for its whole duration; closes them before returning on EVERY path; the result holds no reference into the world.

class_name QaMetrics extends RefCounted
func _init(max_ticks: int)                                         # preallocates PackedInt32Array(max_ticks + 1): no per-tick allocation
func record_tick(tick: int, usec: int) -> void
func record_system(stage_no: int, usec: int) -> void               # only when spec.profile_systems: fed by QaTimedSystem wrappers (or the sim's own hook [QA-XR-16])
func sample_memory(tick: int) -> void                              # OS.get_static_memory_usage(), Performance.OBJECT_COUNT / OBJECT_NODE_COUNT / OBJECT_ORPHAN_NODE_COUNT
func record_entities(tick: int, n: int) -> void                    # peak live entities for SC7
func summary(calib_factor: float) -> Dictionary                    # {mean,p50,p95,p99,max (us), by_system_mean, memory{...}, mean_norm_us}
func percentile(p: int) -> int                                     # nearest-rank, p in 1..100 (sorts a copy once)

class_name QaTimedSystem extends SimSystem                         # decorator installed on world.stages[stage_no - 1] for stages 2..11 (stage 1 is called directly by SimWorld.step, sim_core 5.3)
static func install(world: RefCounted, metrics: QaMetrics) -> void # idempotent
func _init(inner: SimSystem, metrics: QaMetrics)                   # copies stage_no, stride, stride_offset; system_name() forwards; forwards init_world, update (timed), on_spawn, on_dying, on_removed, on_owner_changed, on_player_eliminated, hash_state, dump_state

class_name QaEventStats extends RefCounted
func consume(events: Array[Dictionary]) -> void
func players() -> Array[Dictionary]; func coverage() -> Dictionary; func firsts() -> Dictionary

class_name QaStuckDetector extends RefCounted                      # ai.md definition: a unit with a move-class order and < 1 cell (1,024 u) displacement for 600 ticks (5.4.5)
func sample(tick: int, world: RefCounted) -> void                  # every 100 ticks; reads world.units (head order type, x, y, t_hit, F_BLOCKED) directly
func stuck_count() -> int; func movers_sampled() -> int; func stall_windows() -> int

class_name QaGameInv extends RefCounted                            # game-level invariants G1..G7 on top of SimInvariants (rules: HC4 in 5.4.4)
static func check(a: QaSimAdapter) -> PackedStringArray            # findings "G<n> pid=<p> <detail>"; a check whose data the current domains do not expose (production queue, power recount) is skipped and named by skipped(), never silently passed
static func skipped() -> PackedStringArray
```

**Test-support layer for domain tests (answers economy #27, combat #37, abilities #13, data #22):**
```gdscript
class_name QaWorld extends RefCounted                              # DIRECT driver over the REAL game data, no AI, no network; owns its adapter. Kernel tests with fixture defs use sim_core's SimTestKit; QaWorld is for domain tests that need real defs.
static func make(rosters: PackedStringArray, seed_value: int = 1, opts: Dictionary = {}) -> QaWorld
# opts: map_family:int = OPEN, map_size:int = 96, rules:Dictionary, ai_levels:Array[int] (per player, -1 = none), data:RefCounted (e.g. GameData.from_fixture(dict)), players:int, disable:PackedStringArray (SimWorld opts.disable, e.g. ["SimCombatSystem"]), test_mover:bool = false (registers sim_core's fixed-speed `TestMoveHandler` for `T_MOVE`/`T_PATROL` until the movement domain lands)
func tick(n: int = 1) -> void                                      # n x world.step(); events accumulate in `events`
func cmd(pid: int, name: String, fields: Dictionary = {}) -> int  # master-catalog name; validates and executes immediately through world.commands.execute (sim_core 3.5) and returns SimCommand.Err (0 = OK); advances no tick
func queue(pid: int, name: String, fields: Dictionary = {}) -> void   # world.submit: executes in stage 1 of the next step (use when ordering or timing is under test)
func spawn(pid: int, def_id: String, cell_x: int, cell_y: int, count: int = 1) -> PackedInt32Array   # direct world.spawn_unit / spawn_structure at the cell centre (reason SPAWN_SCRIPT) + flush; returns the new ids ascending. Not replayable: scripts that must survive replays use DEBUG mode 2 (6.2)
func grant(pid: int, credits: int) -> void                         # world.add_credits(pid, credits, CASH_SCRIPT)
func checksum() -> int; func chain(ticks: int) -> PackedInt64Array # [tick, checksum, input_chain] triples every 20 ticks
func events_of(kind: StringName) -> Array[Dictionary]; func entity_ids(pid: int) -> PackedInt32Array; func player(pid: int) -> Dictionary
var events: Array[Dictionary]
func dispose() -> void                                             # idempotent; tests call it in teardown()
class_name QaAssert extends RefCounted
static func no_report_errors(t: TestCtx, report: RefCounted) -> bool                    # DefLoadReport: fails and lists every error
static func chains_equal(t: TestCtx, a: PackedInt64Array, b: PackedInt64Array, label: String) -> bool   # names the first divergent tick
static func snapshot_objects() -> Dictionary                       # {objects, nodes, orphans, static_kb}
static func no_object_leak(t: TestCtx, before: Dictionary, after: Dictionary, tolerance: int = 50) -> bool
```
The fixed-speed movement stub that economy asked for is sim_core's `TestMoveHandler` (speed 300 units per tick, registered by `SimTestKit.make_world` unless `opts.no_test_handlers`, and by `QaWorld.make` with `test_mover: true`); once the movement domain lands, tests use its real handlers and QA adds no stub of its own.

### 3.3 Soak (`QaSoakPlan`, `QaSoakJudge`, `soak.py`)
```gdscript
class_name QaSoakPlan extends RefCounted
enum Tier { ROTATION = 0, ENDURANCE = 1, CONTENT = 2 }
static func build(tier: int, epoch: int, roster_ids: PackedStringArray) -> Array[Dictionary]   # each element = QaMatchSpec.to_dict(); pure, integer-only, identical on every platform
static func to_plan_file(specs: Array[Dictionary]) -> String     # JSON consumed by `ai_soak_main.gd --plan=<file>` [QA-XR-25] and `match_runner.gd --plan=<file>`
static func opponent(index: int, map_family: int) -> int           # rotation bijection (5.4.3)
static func params(tier: int) -> Dictionary                        # {max_ticks, ai_level, sizes, workers, wall_limit_s}
class_name QaSoakJudge extends RefCounted
static func judge_match(res: Dictionary, calib_factor: float) -> Dictionary    # {hard: Array[String] (HC1-HC8), soft: Array[String] (SC1-SC7), notes}; accepts QaMatchResult.d and AiMatchResult dictionaries via the field map of 5.4.4
static func judge_batch(results: Array) -> Dictionary   # {ok, per_roster{id:{n,score2,wins,draws,losses,timeouts,lo,hi}}, faction_pairs{}, coverage{}, failures[]}
static func wilson(score2: int, n: int) -> PackedFloat64Array      # [lo, hi] at z = 1.96; score2 = 2*wins + draws (integer); n = games
```

### 3.4 Determinism helpers
```gdscript
class_name QaChain extends RefCounted
static func hex32(v: int) -> String                                # "%08x" % (v & 0xFFFFFFFF)   (net checksums and chains are u32)
static func hex64(v: int) -> String                                # "%08x%08x" % [(v >> 32) & 0xFFFFFFFF, v & 0xFFFFFFFF]  (NEVER "%x": negative ints print as "-ff" (verified))
static func write(path: String, header: Dictionary, triples: PackedInt64Array) -> int         # Error; triples = [tick, checksum, input_chain, ...]
static func read(path: String) -> Dictionary                       # {header, triples} or {}
static func first_divergence(a: PackedInt64Array, b: PackedInt64Array) -> Dictionary  # {tick:int (-1 = identical), index:int, reason:"checksum"/"chain"/"length", a:PackedInt64Array, b:PackedInt64Array}
class_name QaGolden extends RefCounted
static func check_text(t: TestCtx, name: String, actual: String) -> bool     # vs res://tests/golden/<name>; CRLF->LF; on mismatch notes the first differing line
static func check_json(t: TestCtx, name: String, actual: Variant) -> bool    # canonical: JSON.stringify(v, "  ", true) + "\n"
static func verify_manifest(t: TestCtx) -> bool                              # sha256 of every golden == MANIFEST.json; MANIFEST.revision == last CHANGELOG revision
static func update(name: String, content: String, reason: String) -> int     # refuses unless env MERIDIAN_UPDATE_GOLDENS == reason (non-empty); appends CHANGELOG; rewrites MANIFEST
class_name QaCanary extends RefCounted
static func lines() -> PackedStringArray                           # the 28 engine canary lines (10.2), no "os" line
static func info_line() -> String                                  # "os <name> <arch> locale=<l>" informational, never compared
class_name QaCalibrate extends RefCounted
const ITERATIONS: int = 3000000; const EXPECT_ACC: int = 33451325123209; const EXPECT_S3: int = 2054281984; const REF_MS: int = 294
static func run() -> Dictionary                                    # {ms, acc, s3, ok (acc/s3 match), factor = max(1.0, ms / REF_MS)}
class_name QaReplayTools extends RefCounted
static func verify(path: String, builder: Callable, max_ticks: int = 0) -> Dictionary        # wraps NetReplayPlayer.verify_file
static func diff_checks(a: NetReplayData, b: NetReplayData) -> Dictionary                    # first differing CHECK record
static func minimise(path_in: String, path_out: String, predicate: Callable) -> Dictionary   # ddmin over TURNS records, then trailing ticks; predicate(bytes) -> bool "still fails"
class_name QaCorrupt extends RefCounted                            # desync injection into ONE peer without any sim hook: sim state is public GDScript state (6.3)
enum Section { WORLD = 0, RNG = 1, PLAYERS = 2, ENTITIES = 3 }     # the checksum sections reachable from outside; `map` and `sys.*` are covered by the owning domains' check_hash_coverage tests
static func apply(world: RefCounted, section: int, value: int) -> String   # WORLD: world.next_proj_id += value; RNG: draws `value` numbers from world.rng; PLAYERS: players[0].credits += value; ENTITIES: hp of the lowest-id live entity changed by `value` (never below 1). Returns a description, or "" and does nothing unless OS.has_feature("qa") or OS.is_debug_build()
```

### 3.5 Fuzzing
```gdscript
class_name QaFuzzRng extends RefCounted                            # xorshift128, 32-bit lanes; independent of SimRng
static func from_seed(seed_value: int) -> QaFuzzRng                # lanes: x = seed & M; four times x = (x * 1664525 + 1013904223) & M
func next_u32() -> int; func below(n: int) -> int; func range_i(lo: int, hi: int) -> int; func chance(pct: int) -> bool; func bytes(n: int) -> PackedByteArray
class_name QaFuzzCommands extends RefCounted
static func run(seed_value: int, iterations: int, opts: Dictionary) -> Dictionary   # {ok, iterations, rejected, accepted, crashes, invariant_failures, first_failure:{seed, iter, cmd}}
class_name QaFuzzPackets extends RefCounted
static func run(seed_value: int, iterations: int, targets: PackedStringArray) -> Dictionary   # targets: "turn_input","turn_bundle","handshake","ctrl","lobby","launch","discovery","replay"
class_name QaFuzzFiles extends RefCounted
static func mutate_json(rng: QaFuzzRng, text: String) -> String; static func mutate_cfg(rng: QaFuzzRng, text: String) -> String; static func mutate_bytes(rng: QaFuzzRng, b: PackedByteArray) -> PackedByteArray
```

### 3.6 Data audit, balance probes, content bot
```gdscript
class_name QaDataAudit extends RefCounted
static func run(strict: bool) -> Dictionary                        # {ok, checks_run, errors:[{id, where, msg}], warnings:[...], stats:{...}}; ids DA-01..DA-30 (5.10): the gate over data's own validators + QA cross-cutting checks + tolerance oracle
class_name QaBalanceProbe extends RefCounted
static func ttk_cases() -> Array[Dictionary]                       # from balance targets.ttk_unopposed_s: {attacker, target, min_s, max_s}
static func measure_ttk(c: Dictionary) -> Dictionary               # {ticks, seconds, ok}; 1 attacker vs 1 target on a flat open map, no regen, spawned by `QaWorld.spawn`
static func measure_rps(c: Dictionary) -> Dictionary               # {metric (-1..+1), ok}; 6000 credits per side, start distance 24 cells
class_name QaContentBot extends RefCounted
func _init(adapter: RefCounted, pid: int, roster_id: String, opts: Dictionary)
func step(tick: int) -> void                                       # every 10 ticks, <= 8 commands
func coverage() -> Dictionary; func blocked() -> Array[Dictionary]; func done() -> bool
```

### 3.7 Performance, visual, accessibility, export
```gdscript
class_name QaPerf extends RefCounted
static func run(scenario: String, ticks: int, warmup: int) -> Dictionary          # scenarios PS0-PS6 (sim), PV1-PV4 (rendered; needs a window)
static func compare(res: Dictionary, budgets: Dictionary, calib_factor: float) -> Dictionary   # {ok, breaches:[{metric, value, budget, ratio}]}
class_name QaImgDiff extends RefCounted
static func compare(a: Image, b: Image) -> Dictionary              # {size_ok, psnr, rmse, mean_abs, max_abs, diff_pct (percent 0..100), bbox}
static func blank_ratio(img: Image) -> float; static func placeholder_pct(img: Image) -> float; static func luma_stats(img: Image) -> Dictionary; static func heatmap(a: Image, b: Image) -> Image
class_name QaContrast extends RefCounted
static func luminance(c: Color) -> float; static func ratio(a: Color, b: Color) -> float
static func simulate(c: Color, kind: int) -> Color                 # kind: 0 protan, 1 deutan, 2 tritan (Machado 2009 matrices, severity 1.0)
static func delta_e2000(a: Color, b: Color) -> float                # sRGB inputs via CIELAB (D65)
static func delta_e2000_lab(l1: float, a1: float, b1: float, l2: float, a2: float, b2: float) -> float   # test entry (Sharma vectors)
static func min_pairwise_delta_e(cs: PackedColorArray, kind: int = -1) -> float
class_name QaA11yAudit extends RefCounted
static func audit(root: Control) -> Array[Dictionary]              # findings {id: "A-04", path: NodePath, msg}
class_name QaLayoutAudit extends RefCounted
static func audit_at(factory: Callable, sizes: Array[Vector2i], scales: PackedFloat32Array) -> Array[Dictionary]   # factory: (parent: Control) -> void
class_name QaExportManifest extends RefCounted
static func generate() -> PackedStringArray                        # editor: exact-case res:// resources that must ship
static func verify(manifest: PackedStringArray) -> Dictionary      # exported build: {missing, checked}; uses ResourceLoader.exists (FileAccess.file_exists is false for scripts in a pck (verified))
```

### 3.8 Command lines (Python; all exit 0 = pass)
```
python3 tools/py/qa/ci.py run <T0..T5|step-id> [--keep-going] [--jobs N]      python3 tools/py/qa/ci.py status [--gate M2]
python3 tools/py/qa/soak.py <pr|smoke|nightly|weekly|arena|rotation|endurance|content> [--epoch YYYYMMDD] [--jobs N] [--legs A,C]
python3 tools/py/qa/crossarch.py <scenario-ids|all> [--legs A,B,C,D,E,F] [--ticks-scale 0.5]      # wraps tools/py/xplat_determinism.py; prints first divergence per leg pair
python3 tools/py/qa/udp_impair.py --listen 127.0.0.1:PORT_PROXY --target 127.0.0.1:PORT_HOST --profile bad_wifi [--seed N]
python3 tools/py/net_two_process.py --case N0..N16 [--clients N] [--proxy <profile>] [--stop-at S] [--kill-at S] [--cross-os]
python3 tools/py/qa/release_payload.py --version 0.1.0 --out builds/release/0.1.0/payload      # docs, licences, credits, CONTROLS, RELEASE_NOTES
python3 tools/py/package_windows.py | package_linux.py [--payload <dir>]       # tooling's packagers; --payload requested [QA-XR-8]
python3 tools/py/qa/package_macos.py --version 0.1.0 [--dmg]                     # QA: ditto/zip of the ad-hoc-signed .app (+ optional dmg)
python3 tools/py/qa/verify_release.py builds/packages
python3 tools/py/qa/golden_manifest.py verify | update --reason "text" <files...>
python3 tools/py/qa/licenses.py build | audit      python3 tools/py/qa/bugs.py index | check | new "<title>" --sev S1 --module sim | bisect <cmd>
```

### 3.9 Call order and ownership summary
* **Entry script lifecycle**: `_initialize()` installs the `process_frame` one-shot watchdog, `OS.add_logger(QaLogGuard)`, `QaCli.dispatch()`, then `quit(exit)`; the guard is removed last. Any `QaLogGuard` error count > 0 forces `Exit.ENGINE_ERRORS` even if the job body returned OK.
* **Memory**: `QaMatch.run` owns world/AI/metrics; `QaMetrics` owns fixed `PackedInt32Array`s; results are plain `Dictionary` trees safe to keep after disposal; `QaTemp` owns its directory and removes it in `dispose()`; `QaWorld` owns its world until `dispose()`; test files own nothing outside `QaTemp` (tests never write to `res://` or arbitrary `user://` paths).
* **Threading**: none. Harness code is single-threaded and synchronous; parallelism is process-level (`soak.py`, `ci.py`).

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enumerations (integer values are file/protocol format; never renumber)
```gdscript
QaCli.Exit          { OK = 0, FAILED = 1, USAGE = 2, ENGINE_ERRORS = 3, WALL_LIMIT = 4, DIVERGED = 5, UNSUPPORTED = 6 }
QaSoakPlan.Tier     { ROTATION = 0, ENDURANCE = 1, CONTENT = 2 }
QaMatch.StopReason  { VICTORY = 0, TICK_CAP = 1, WALL_LIMIT = 2, ERROR = 3, DESYNC = 4 }
QaMatch.MapFamily   { OPEN = 0, URBAN = 1, COAST = 2 }                 # ASSUMPTION(map) - the three bible families; must equal the MatchConfig map family codes
QaMatch.AiLevel     { EASY = 0, MEDIUM = 1, HARD = 2, BRUTAL = 3 }     # ai.md 7.1; -1 = no AI (scripted/bot)
QaSev               { S0 = 0, S1 = 1, S2 = 2, S3 = 3 }                 # bug severity (5.16)
QaBugStatus         { NEW = 0, TRIAGED = 1, REPRODUCED = 2, FIXING = 3, FIXED = 4, VERIFIED = 5, CLOSED = 6, WONTFIX = 7 }
QaVerdict           { PASS = 0, FAIL = 1, NA = 2, WAIVED = 3 }          # visual / a11y checklist
QaLeg               { A_MAC_ARM64 = 0, B_MAC_X64 = 1, C_LINUX_AMD64 = 2, D_LINUX_ARM64 = 3, E_WINDOWS = 4, F_EXPORTED_RELEASE = 5 }
QaGameInv           { CREDITS_NEG = 1, UNIT_CAP = 2, QUEUE_LEN = 3, POWER_MISMATCH = 4, TECH_PREREQ = 5, ROSTER_LEGAL = 6, PLAYER_STATE = 7 }   # QA's game-level invariants G1..G7 (rules in 5.4.4 HC4); the structural ones (ids, lists, counters, spatial hash, hp, bounds, orders, teams) are sim_core's INV-1..INV-14
QaPerfId            { PS0 = 0, PS1 = 1, PS2 = 2, PS3 = 3, PS4 = 4, PS5 = 5, PS6 = 6, PV1 = 11, PV2 = 12, PV3 = 13, PV4 = 14 }
QaDbgMode           { GRANT = 1, SPAWN = 2, KILL = 3, REVEAL = 4, SET_HP = 5, CHARGE = 6 }   # modes of the replicated sim_core `DEBUG` command (opcode 0x0F): 1 and 2 exist in sim_core 6.1, 3..6 are requested [QA-XR-17]; layouts in 6.2
QaCorrupt.Section   { WORLD = 0, RNG = 1, PLAYERS = 2, ENTITIES = 3 }        # desync injection is a local harness helper, not a command (6.3)
```

### 4.2 `QaMatchSpec` fields
| Field | Type | Default | Meaning |
|---|---|---|---|
| `players` | `Array[Dictionary]` | required, 2..8 | `{roster: String, team: int, ai: int (AiLevel or -1), style: int = 0 (0 doctrine, 1 aggressive, 2 defensive, 3 wildcard), name: String, color: int = pid}` |
| `map_family` / `map_size` | `int` / `int` | `OPEN` / 0 | size 96..256 step 8; 0 = auto (2p 96, 3-4p 128, 5-6p 160, 7-8p 192) |
| `map_seed` / `sim_seed` | `int` / `int` | `--seed` / `--seed` | both derived from `--seed` unless `--map-seed` / `--sim-seed` given (u32) |
| `max_ticks` | `int` | 24000 | hard cap (20 game-minutes at 20 TPS) |
| `stop_on_victory` | `bool` | true | end when `outcome().over` |
| `rules` | `Dictionary` | `{}` | overrides of the `MatchConfig.rules` block, keyed as in net's `lobby_options.json rules_schema` (net.md 7.1/7.2): `start_credits` (7500), `unit_cap` (150), `superweapons` (true), `fog` (true), `shared_vision` (false), plus `allow_debug` (0; QA and dev builds only, [QA-XR-26]). sim_core's `SimMatchRules` spells some keys differently (`fog_mode`, ...): the adapter converts and `test_qa_adapter_contract` reports unmapped keys (risk R30) |
| `script_path` | `String` | "" | `*.cmds.json` scripted commands (7.4) |
| `bot` | `String` | "" | `"content"` = `QaContentBot` drives every player without an AI |
| `invariants_every` | `int` | 100 | `QaSimAdapter.validate()` cadence; 0 = only at end |
| `twin` | `bool` | false | second world built from the same config, fed the same inputs, checksums compared every 20 ticks |
| `record_replay` / `chain_out` / `chain_in` | `String` | "" | replay output path; chain output path; golden chain to compare against (exit `DIVERGED` on mismatch) |
| `wall_limit_s` | `int` | 3600 | abort with `WALL_LIMIT` |
| `profile_systems` | `bool` | false | per-system microsecond timing |
| `fixed_delay` | `int` | 1 | `NetSessionOptions.fixed_input_delay_turns`, so replays/goldens do not depend on adaptive delay |
| `driver` | `String` | `"session"` | `"session"` (production `NetSession` LOCAL, manual clock) or `"direct"` (`QaSimAdapter.advance()` emulating the LOCAL turn pipeline over `SimWorld.step()`; chain-equal to `session`) |

### 4.3 Normalised event dictionary (what `QaSimAdapter.drain_events` yields)
`{k: StringName, t: int (tick), pid: int, def: String (bible id, "" if none), a: int, b: int}`. The adapter decodes the 10-int records of sim_core's MASTER event catalog (6.2 there) into these kinds:
| `k` | Source event (code) | `a` / `b` |
|---|---|---|
| `spawned` | `SPAWNED 0x01` (id, def_idx, owner, x, y, facing, reason, parent) | a = entity id, b = `SPAWN_*` reason |
| `built` | `SPAWNED` of a STRUCTURE with reason `PLACED` (2) or `DEPLOYED` (3) | a = id |
| `produced` | `PRODUCTION_COMPLETE 0x26` (pid, def_idx, producer, spawned id) | a = spawned id |
| `died` | `DIED 0x03` (id, def_idx, owner, x, y, killer, killer_owner, reason) | a = killer owner (-1 none), b = `DIE_*` |
| `researched` | `RESEARCH_COMPLETE 0x2A` | a = research idx |
| `power_fired` | `POWER_USED 0x30` | a = power idx |
| `superweapon_fired` | `SW_LAUNCHED 0x35` | a = sw idx |
| `income` | `CASH 0x20` with reason HARVEST (1) or SALVAGE (2) and delta > 0 | a = credits |
| `captured` | `OWNER_CHANGED 0x04` with reason 0 | a = new owner |
| `rejected` | `CMD_REJECTED 0x61` (pid, op, Err, target-or-def) | a = op, b = `Err` |
| `blocked` | `QUEUE_BLOCKED 0x28` (reason 1 funds, 2 cap, 3 power, 4 prerequisite lost, 5 hold) | a = reason |
| `player_defeated` | `PLAYER_ELIMINATED 0x70` | a = `Elim` reason |
| `match_over` | `MATCH_END 0x71` | a = winner team, b = `EndReason` |
Spending is deliberately **not** an event kind: progressive payments are `silent` (sim_core 3.4.6). Totals come from the `SimPlayer` counters (`st_credits_earned/spent`, `st_units_built/lost/killed`, `st_structs_built/lost/killed`, `st_damage_dealt/taken`) read at each sample and at the end. Every event QA needs is in the published catalog [QA-XR-20]; economy.md (events 300..499), abilities.md (200..259) and combat.md (200..229) still use their own numeric ranges (risk R30): the adapter maps by name and `test_qa_adapter_contract` fails on an unmapped required kind.

### 4.4 Criteria identifiers (exact rules in 5.4.4)
Hard: `HC1` exit/result present, `HC2` zero engine errors and leaks, `HC3` no desync (twin/replay/repeat-check), `HC4` invariants clean, `HC5` tick-time guard, `HC6` memory guard, `HC7` outcome legal, `HC8` reproducibility. Soft (`SC1`-`SC5` owned by the AI report, ai.md 10.5; `SC6` and `SC7` are QA's): `SC1` economy started, `SC2` production progress, `SC3` stuck ratio, `SC4` decisive rate, `SC5` win-rate band, `SC6` content coverage, `SC7` entity headroom.

### 4.5 Leg definitions (how each is launched; all via `tools/gd` unless noted)
| Leg | Id | Command shape | Slowdown (measured) |
|---|---|---|---|
| A | mac arm64 native | `tools/gd run ...` (`xplat_determinism.py` target `native`) | 1.00 |
| B | mac x86_64 (Rosetta) | `GODOT_BIN=tools/py/qa/godot_x86_64.sh` wrapper (`exec arch -x86_64 <Godot> "$@"`; `tools/gd` honours `GODOT_BIN`) | 1.50 |
| C | Debian 12 amd64 container | `tools/gd linux --arch amd64 run ...` (target `amd64`) | 2.61, +1.3 s start |
| D | Debian 12 arm64 container | `tools/gd linux --arch arm64 run ...` (target `arm64`; `tools/godot-linux-arm64` is provisioned) | ~1.0 (native VM) |
| E | Windows x86_64 | the `windows-latest` job of `.github/workflows/build.yml` writes `chains/windows.hashes`; `xplat_determinism.py --compare` diffs it; never run yet | n/a |
| F | exported release-template build | `builds/<os>/... --headless -- --qa=match ...` (QA export preset) | ~1.0 |

### 4.6 Perf scenario definitions
| Id | Setup (spawned at tick 0 by direct `world.spawn_*` calls - perf runs are never replayed; seeds fixed) | Measures |
|---|---|---|
| PS0 | kernel floor: sim_core fixture data (`SimTestKit.make_world(8, seed, {disable: all domain systems})`), 8 players x 150 idle units (1,200) plus the 8 HQs, ticks 0..1200; variant b: 20 % of the units hold a `MOVE` order (test mover) | tick mean/p95/p99/max, checkpoint ticks reported separately (sim_core 9: idle step 0.54 ms, checkpoint 1.8 ms on RM) |
| PS1 | 2 players, 200 mobile combat units each (mixed roles from each side's vanilla roster) + 30 structures each, open 128x128, all units ordered `attack-move` toward each other, ticks 0..1200 | tick mean/p95/p99/max; per-system |
| PS2 | 8 players x 150 units + 40 structures (1,200 mobile + 320 structures), open 192x192, AI HARD from tick 0 | as PS1 + AI think time |
| PS3 | 2 players opening state (HQ + 7,500 credits, AI EASY), ticks 0..2400 | idle-ish baseline, build queue costs |
| PS4 | 200 units of one player ordered across a 192x192 urban map simultaneously (path request burst) | worst tick, path queue drain time |
| PS5 | 300 units moving over unexplored shroud on 256x256, fog on, 8 players | vision system cost |
| PS6 | PS1 + 3 support powers + 1 superweapon impact at tick 600 | spike behaviour |
| PV1 | PS1 rendered, 1920x1080, Medium preset, camera fixed at battle centre, 600 frames after 120 warm-up | frame time p50/p95/p99, draw calls, primitives, VRAM, CPU/GPU render time |
| PV2 | PV1 at 3840x2160 High | as PV1 |
| PV3 | PV1 at Low, `--rendering-method mobile` and `gl_compatibility` variants | fallback health |
| PV4 | Menu + lobby idle, 300 frames | UI cost |

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Test pyramid, CI tiers and the definition of "green"

| Layer | Directory / job | Proves | Tier | Target size at M6 |
|---|---|---|---|---|
| L1 Unit | domain `test_*` files | one class/function, edge values, integer exactness | T0 | >= 1,600 tests; >= 90 % of public functions referenced by a test (`api_coverage.py`) |
| L2 Scenario | domain `test_*` files (`QaWorld`) | build a `SimWorld`, issue commands, tick N, assert | T0 | >= 350 |
| L3 Determinism | `tests/determinism/`, `canary_dump`, `simcore_dump` (D00), `match_runner --chain-out`, net D1-D4, AI D1-D5 | same inputs -> same checksum chain across runs, processes, architectures, OSes, builds | T0 (canary), T1, T2 | D00-D07 x 6 legs + 40 tests |
| L4 Data | data's tests + validators, `data_audit` | bible + balance + resolution correctness | T0/T1 | data.md 5.12 rules + DA-01..DA-30 |
| L5 Net | net's `tests/net/` (virtual time) + real-ENet process matrix N0-N16 | lockstep, lobby, faults, desync detection | T0/T1 (virtual), T2/T3 (processes) | net.md S1-S20 + 17 process cases |
| L6 Fuzz | `tests/fuzz/`, `fuzz_runner` | validators/decoders/loaders never crash or corrupt state | T1 (2 k iterations), T3 (200 k) | 3 command + 9 packet/session + 4 file targets |
| L7 Soak | AI presets via `soak.py` + QA rotation/endurance | 32 rosters x 3 map families, AI vs AI, robust and plausible | T1 `pr`, T2 `smoke`, T3 `nightly`, T4 `weekly` | 6 / 28 / 1,488+ / 2,976 matches + 3 endurance |
| L8 Content | `tests/content/`, `QaContentBot` | every unit/structure/research/power/superweapon works | T3 | 32 roster runs |
| L9 Perf | `tests/perf/`, `perf_bench` | numeric budgets (5.8) | T1 (informational), T3 (gating) | PS0-PS6, PV1-PV4 |
| L10 Visual | `tests/visual/`, `gd shot` | rendered output is correct, agent-reviewed | T3 on a GPU host, gates | >= 60 cases at M5 |
| L11 A11y/layout | `tests/a11y/` | contrast, names, focus, overflow at resolutions x scales | T0/T1 | 5 resolutions x 3 scales |
| L12 Release | `release_payload.py`, `package_*.py`, `verify_release.py` | installable, licensed, checksummed | T5 | 4 packages |

**Definition of green (all must hold; `ci.py` enforces).** G1 process exit 0 as reported by `tools/gd` (which already maps "exit 0 but engine error lines" to 3 and kills stalls with 124). G2 the result sentinel is present (`== N files, ...` summary for `gd test`; `QA_RESULT` for QA jobs; `AISOAK_END`/`summary.jsonl` for AI presets; `NETTEST` lines for net). G3 `logscan.py` finds none of: `^(SCRIPT ERROR:|ERROR:|USER ERROR:|Parse Error:|CHECKER ABORTED|RUNNER ABORTED)`, `ObjectDB instances? (was|were) leaked at exit`, `resources? still in use at exit`, `Program crashed with signal`, `handle_crash` (allow-list `tools/py/qa/logscan_allow.txt`, each entry needs a reason; the container's `libfontconfig.so.1: cannot open shared object file` loader line is allowed only on images lacking the package). G4 `passed + failed + errors + skipped == count(--list)`, skips only for declared reasons (GPU absent), skip count printed. G5 `golden_manifest.py verify` passes. G6 the quarantine list is printed and has <= 5 entries, each with owner and expiry (5.16).

**Tiers** (`tools/py/qa/tiers.json` is the executable definition; example in 7.9). Worker counts assume the RM (18 cores):
| Tier | Who/when | Content | Wall budget (RM) |
|---|---|---|---|
| T0 | every agent, before finishing any task | `gd check` (lint L001-L010, plus the AI purity lint of ai.md 10.1 once tooling wires it in); `gd test --exclude=determinism/,fuzz/,perf/,content/,visual/` (all domain tests + `a11y/ qa/ regress/`; `ci.py` shards it 4 ways by file prefix); `validate_reference.py`; `validate_balance.py --strict`; `balance_calc.py validate`; `canary_dump --compare`; `golden_manifest verify`; `check_sim_rules.py` and `check_xplat.py` | <= 2 min at M0-M1, <= 6 min from M3 |
| T1 | before a module is declared done; hourly while agents work | T0 + `gd test determinism/ fuzz/ perf/ content/` (short variants) + AI preset `pr` (6 matches) + net process case N0 + replay goldens + `bugs.py check` | <= 15 min |
| T2 | before every milestone gate and after sim/net/data batches | T1 on legs B, C, D: canary, D00-D07 chains, AI D4 canary, `gd linux test` of T0 suites; AI preset `smoke` (28 pairs); net N0-N9 (real ENet, 2-3 processes); leg F (release-template QA export) vs leg A; from M5 the `.deb` build + lintian | <= 40 min |
| T3 | nightly | AI preset `nightly` (1,488 matches + ladders + FFAs, ~1.6 h on 8 shards per ai.md; ~0.8 h on 16) + QA `endurance` (3 x 60 game-min) + `content` (32) + `rotation` (96) inside the Debian container (leg C) + deep fuzz + perf gating + visual (GPU host) + net N10-N16 + leak and a11y suites | <= 3 h |
| T4 | weekly and at gates M4/M6 | AI preset `weekly` (2,976 pair-matches, ladders, `repeat-check`) + `arena`; balance conformance (5.5.2); win-rate report; content coverage matrix | <= 4 h |
| T5 | release candidate | T0-T4 green on a `gd snapshot`; packages; install tests; docs + licence audits; manual checklist R-01..R-24 | <= 8 h + manual |

**Execution environment.** T0 steps run on the live `game/` (short, shared lock). Everything longer (T1 soaks, T2-T5) runs on a **frozen mirror**: `ci.py` copies `game/` (without `.godot`) to `.cache/qa/<run_id>/game/`, imports once, and launches every job with `GD_ROOT=.cache/qa/<run_id>` and `GD_GAME_DIR=.cache/qa/<run_id>/game` (both documented env overrides of `tools/gd`). Reasons: a multi-hour reader on the live project would starve other agents' imports (decision 9), and the run then tests one consistent tree. The Docker legs already work this way (`gd linux` mirrors `game/` into `.cache/linux-<arch>/`). Each parallel job also gets its own sandboxed `HOME`/`XDG_DATA_HOME`/`APPDATA` (5.6, [QA-XR-2]) and its own `--results` file.

### 5.2 Determinism method

**D1 Engine canary.** `QaCanary.lines()` prints the 28 lines of 10.2 (integer division, modulo, shifts, wrap, rounding, ceil/float trap, float parsing/formatting, Dictionary order, unstable sort, hash, JSON typing, SHA-256, LE encoding). `canary_dump.gd --compare` diffs against `golden/engine_canary.txt`; the same file must match on **every** leg *(verified identical: macOS arm64, macOS x86_64/Rosetta, Debian 12 amd64/Rosetta; the `os` info line is excluded)*. An engine upgrade regenerates it with a CHANGELOG reason; any unexplained diff on one leg is S0. The calibration checksum (`acc=33451325123209`, `s3=2054281984`) is part of the same run, which also requires `Fp.self_test()` (sim_core 8.4: the arithmetic engine facts the kernel relies on) to return `[]` on every leg.

**D2 Double run.** Two `SimWorld`s from one config side by side in one process (DR-9) plus `NetSelfTest.run_double` (net.md 3.7): identical `checksum_at` at every multiple of 20 and identical `dump_state()` hash at the end. Any global mutable state in sim shows up here. For the kernel itself sim_core ships `SimTestKit.double_run/chain_of` and a codec-path equivalence test (its 10.4); QA does not repeat them.

**D3 Perturbation.** The same scenario must give the same chain after: (a) a warm-up match in the same process; (b) allocator/hash-state churn (insert/erase 10,000 random Dictionary keys, allocate/free 100,000 small objects) before world creation; (c) `--single-threaded-scene`; (d) `--time-scale 3 --fixed-fps 30` (sim must not read frame time); (e) from M2: windowed vs headless (`--gui`); (f) `LC_ALL=de_DE.UTF-8` and `LC_ALL=tr_TR.UTF-8` with `--language de|tr` (locale independence); (g) event-drain cadence: every tick vs every 100 ticks vs only at the end, and `opts.events = false` (the soak setting, sim_core 3.4.1) vs true (DR-12: events are output-only, and the number of RNG draws must not depend on them, sim_core 5.2).

**D4 Replay round trip.** Live run records a `.mfreplay`; `replay_verify.gd` (wraps `NetReplayPlayer.verify_file`) re-simulates it; the CHECK records must equal the live chain (`ok`, `first_mismatch_tick == -1`).

**D5 Goldens.** Chains `golden/chains/<id>.chain` (format 7.3) plus golden replays (`tests/golden/replays/*.mfreplay` and net's `fixtures/net/replays/`, net.md D3). Scenario catalogue (fixed configs in `fixtures/scenarios/*.json`; `--fixed-delay 1` so adaptive delay cannot change turn assignment):
| Id | Players | Map (family, size, seed) | Ticks | Purpose |
|---|---|---|---|---|
| D00 | sim_core golden job (`simcore_dump.gd`, no game data): `Fp` table, `mul_div` and `isqrt` digests, the golden 47-byte codec batch, `config_hash`, S-CORE-1 (200 steps; checkpoints at ticks 0/20/40/60/80/100, event digest) and five chaos-fuzz games (`SimTestKit.random_script`, seeds 11-15, 3,000 steps, 2-4 players) | sim_core fixture world | 200 / 3,000 | kernel arithmetic, RNG, codec, checksum and cleanup identical on every leg; needs no other domain, so it is the first cross-arch signal (M1) |
| D01 | napc.vanilla vs def.vanilla, AI MEDIUM | OPEN 96, 1 | 6,000 | economy + ground combat baseline |
| D02 | han.china vs olm.algeria, AI MEDIUM | URBAN 96, 2 | 6,000 | urban pathing, light vehicles |
| D03 | nec.nordics vs pd.japan, AI MEDIUM | COAST 128, 3 | 6,000 | naval + amphibious layers |
| D04 | napc.usa, sap.india, ae.kongo, def.russia FFA, AI MEDIUM | OPEN 128, 4 | 6,000 | 4-player ordering, air |
| D05 | scripted: all 39 non-system ops of the master command catalog (6.4) at least once, per roster feature (build, place, produce, cancel, research, move, attack, attack-move, guard, stop, deploy, capture, repair, sell, rally, load, unload, scatter, force-fire, powers, ...) | OPEN 96, 5 | 2,400 | command vocabulary; `allow_debug=1` (DEBUG modes 1 and 2 set the scene) |
| D06 | scripted: all 8 superweapons and 8 support powers with `start_credits=100000` (the maximum of net's `rules_schema`), superweapons on, `allow_debug=1` (mode 6 `CHARGE` skips the charge wait) | OPEN 128, 6 | 9,000 | strategic effects, zones |
| D07 | 8-player FFA, one roster per faction, AI HARD | OPEN 192, 7 | 12,000 | scale, ordering, endurance-lite |
D01-D07 are run by `match_runner --chain-out` and compared with `--chain-in`; a mismatch prints `first_divergence` (tick, checksum vs chain, then the differing section names of `report_at(tick).sections`, then a `dump_state` diff via net's `desync_diff.gd`). D00 is run by `simcore_dump.gd` and compared with `golden/sim_core.json` (digests) and across legs (fuzz chains). The AI domain's D4 canary (5 seeds x 3,000 ticks, command-log hash chain + checksum chain) is run by `crossarch.py` as scenarios `AI-D4-1..5` on the same legs.

**D6 Cross-arch / cross-OS.** The comparison engine is tooling's `xplat_determinism.py`: it runs one headless scenario on `native`, `amd64` and `arm64` targets in parallel (`gd`, `gd linux --arch amd64`, `gd linux --arch arm64`), parses `HASH tick=<n> <hex>` lines and reports the first diverging tick with every target's value; CI mode writes `--only-local --out F` per OS and `--compare a b c` diffs them. QA supplies the scenarios - `match_runner.gd` prints those lines for every checksum snapshot, so `xplat_determinism.py res://tests/harness/match_runner.gd -- --scenario=D01` works unchanged - and `crossarch.py` adds what the tool lacks: many scenarios per invocation, leg B (Rosetta), leg F (QA export), and on divergence re-runs both legs with `match_runner --sections-at=<tick>` (prints the `report_at` section digests and per-entity digests of that checkpoint) to name the differing section. Container legs pay 1.3 s start + x2.6 CPU (amd64) or ~x1 (arm64): D01-D07 on leg C = 7 x 6,000..12,000 ticks x 3 ms x 2.6 + 7 x 2 s = ~7 min *(estimate)*. Windows (leg E) is the `windows-latest` job of `.github/workflows/build.yml` producing `chains/windows.hashes`; QA extends its scenario list from the toolsmith's `xplat_int_math.gd` to D00-D03; the workflow has never been pushed, so until a hosted or manual run happens Windows determinism is *(unverified-win)* and the M2/M3/M6 gates require one green run each.

**D7 Release-vs-editor (leg F).** The QA export preset (release template, `tests/harness/**` included, custom feature `qa`) is launched as `MeridianFracture --headless -- --qa=match --scenario=D01 --chain-out=...` and its chain must equal leg A's. This catches release-only behaviour: `assert()` runs in editor/debug builds *(verified: a failed assertion aborts the function with a script error)* and is compiled out in release templates (documented engine behaviour; leg F would show any difference), so any side effect inside an `assert` desyncs release from debug (proposed lint L013).

**Failure diagnosis (S0 procedure).** (1) `first_divergence` -> tick T. (2) `report_at(T).sections` on both sides (kept for 8 checkpoints; sim_core 8.5): the first differing section names the domain - `world`/`rng` (draw-count or scheduling divergence), `players` (economy, production, power), `entities` (then the differing `entity_digests` pair names the entity id), `map`, or `sys.<name>.<stage>`. (3) With `opts.snapshot_keep = 3`, `SimTestKit.diff_snapshots(dump_state(T-20), dump_state(T))` lists the first differing fields. (4) `QaReplayTools.minimise` ddmin over the command records to the smallest log that still diverges. (5) File `BUG-NNNN` (S0) with legs, tick, section, minimised replay in `tests/fixtures/regress/`, add `tests/regress/test_bug_NNNN_<slug>.gd`. Development on the affected module stops (stop-the-line) until fixed or the divergence is proven environment-only.

### 5.3 Golden policy
* One `game/tests/golden/MANIFEST.json` lists path, sha256 and `revision` for **every** golden: QA (`engine_canary.txt`, `chains/*`, `replays/*`, `perf_baseline.json`, `visual/golden/**`), data (`data_hash.json`, `convert_vectors.json`, `resolver_golden.json`, `validator_allow.json`), ai (`ai/baselines/ai_baseline.json`), net (`fixtures/net/replays/*`), sim_core (`sim_core.json`). `CHANGELOG.md` has one line per revision: `rN | YYYY-MM-DD | agent | ids | reason | bug/task`.
* The owning domain updates its golden with `MERIDIAN_UPDATE_GOLDENS="<reason>" python3 tools/py/qa/golden_manifest.py update --reason "<same text>" <files>`; the tool bumps `revision`, appends CHANGELOG, recomputes hashes. `test_qa_golden_manifest` fails if any hash differs from the manifest or the last CHANGELOG revision != `MANIFEST.revision`. (Data's `V-HASH-01` refreshes its goldens with `data_cli.gd -- --update-goldens`; that path must call this tool, which also answers data's request for a golden helper with a mandatory reason instead of a bare flag.)
* A sim behaviour change that legitimately alters chains bumps `SimConfig.SIM_VERSION` [QA-XR-21], regenerates **all** chain/replay goldens in one revision, and lists the first-divergence summary per scenario in the CHANGELOG line. Replays from older `sim_version` are archived, not verified.
* Checksums are stored as **hex strings** (`QaChain.hex32`); numbers in JSON would round through float *(verified)*.

### 5.4 AI-vs-AI soak

#### 5.4.0 Division of labour with `ai.md` (no second matrix engine)
| Concern | Owner | Notes |
|---|---|---|
| Roster-matrix engine, presets `pr/smoke/nightly/weekly/arena`, `AiMatchMatrix`, match seeds `fnv1a("soak\|i\|j\|m")`, adjudication at cap, `AiMetrics`, `ai_soak_report.py`, AI thresholds (ai.md 10.5), `ai_baseline.json`, `repeat-check`, ladders | **ai** (task AI-11) | runs through net's LOCAL unpaced pipeline, i.e. the production path |
| Single-match CLI (`match_runner.gd`), result schema, twin/replay/chain outputs, invariants, memory/leak/timing guards, content bot, cross-arch chains, perf scenarios | **QA** | same pipeline (`--driver=session`) plus a faster `direct` driver |
| Robustness criteria HC1-HC8 applied to **every** soak (AI presets included) | QA specifies, ai implements the hooks | `AiSoakRunner` adds a `qa` block to `AiMatchResult` (QA-XR-25); `soak.py` applies `QaSoakJudge` + `logscan` |
| Plans QA adds on top: `rotation` (96, coverage-proven), `endurance`, `content` | QA | delivered to `ai_soak_main.gd` via `--plan=<file>` where AI measurements are wanted |
| Quality thresholds (first Radar/tank/AA/siege, idle ratios, ladders, cross-roster fairness, stuck <= 2 %) | ai.md 10.5 | QA adopts them verbatim as SC1-SC5; QA never re-states different numbers |
Why a rotation plan if `nightly` is a full round-robin: emulated legs (x2.6) and the Debian container cannot afford 1,488 matches; the rotation covers every roster twice per map family and all 28 faction pairs in 96 matches (proof below), so Linux-only and cross-OS robustness is tested nightly at 1/15 of the cost.

#### 5.4.1 Headless match-runner CLI (`match_runner.gd`)
```
tools/gd run --timeout 3600 res://tests/harness/match_runner.gd -- --rosterA=napc.canada --rosterB=han.china \
    --map=coast:128 --seed=20260929 --ticks=24000 --ai=hard --chain-out=builds/qa/x/m1.chain \
    --replay-out=builds/qa/x/m1.mfreplay --result=builds/qa/x/m1.json
```
Both `--key=value` and `--key value` are accepted. Roster names accept the full id (`roster.napc.canada`), `<faction>.<sub>` (`napc.canada`) or a bare faction code meaning its vanilla roster (`napc`). `gd run`'s default timeout is 300 s, so long callers **must** pass `--timeout`.
| Option | Default | Meaning |
|---|---|---|
| `--rosterA`, `--rosterB` | required unless `--players`/`--plan` | players 0 and 1 |
| `--players=a,b,c,...` | - | 2..8 rosters (overrides A/B); `--team=0,1,2,...` team per player (default: each its own team; 2p: 0,1) |
| `--map=<open/urban/coast/0/1/2>[:<size>]` | `open` | family and optional size (96..256, multiple of 8) |
| `--seed=<u32>` | 1 | master seed; `--map-seed`, `--sim-seed` override individually |
| `--ticks=<n>` | 24000 | cap; `--until=victory/ticks` (default victory) |
| `--ai=<easy/medium/hard/brutal/none>` | `medium` | for all players; `--ai0..--ai7` per player; `--style0..7` (0 doctrine, 1 aggressive, 2 defensive, 3 wildcard); `none` needs `--script` or `--bot` |
| `--rules=k=v,k=v` | - | e.g. `start_credits=100000,unit_cap=150,fog=1,superweapons=1,allow_debug=1` |
| `--script=<file>` / `--bot=content` | - | scripted commands (7.4) / content bot |
| `--plan=<file>` | - | run every spec of a plan file sequentially in this process (each result appended as a `QA_RESULT` line, process exit = worst code) |
| `--driver=session/direct` | `session` | `session` = production `NetSession` LOCAL with a manual clock; `direct` = `QaSimAdapter.advance()` emulating the LOCAL turn pipeline over `SimWorld.step()` (perf, fuzz, before net exists; chain-equal to `session` by `test_qa_driver_equivalence`) |
| `--fixed-delay=<turns>` | 1 | fixed input delay |
| `--twin` | off | second world compared each snapshot (criterion HC3) |
| `--invariants=<n>` | 100 | validate cadence |
| `--chain-out`, `--chain-in`, `--replay-out`, `--result` | - | outputs / golden comparison (mismatch exits 5) |
| `--wall-limit=<s>` | 3600 | abort with exit 4 |
| `--progress-secs=<s>` | 10 | `QA_PROGRESS` cadence (keeps `gd`'s stall watchdog fed) |
| `--profile` | off | per-system timing |
| `--hash-lines` | on with `--chain-out`/`--chain-in` | print `HASH tick=<n> <hex8>` per snapshot for `xplat_determinism.py` |
| `--sections-at=<tick>` | - | run to that checkpoint tick, print `SECTIONS {tick, final, sections{}, entity_digests[]}` and stop (used by `crossarch.py` to attribute a divergence; sim_core 8.5) |
| `--list-rosters` | - | prints the 32 ids in bible order and exits 0 |
Exit codes: `QaCli.Exit`. Output: `QA_START {spec}`, `QA_PROGRESS {tick, wall_s, entities, credits[]}` every 1,200 ticks or `--progress-secs`, final `QA_RESULT {QaMatchResult}` (7.2) as the **last** stdout line of each match.

#### 5.4.2 Match loop (`QaMatch.run`; identical for both drivers because `QaSimAdapter.advance()` hides the difference)
```
1  spec.validate -> data = load_game_data -> main = QaSimAdapter.open(spec, driver) (SESSION: manual NetClock at 0, auto_clear_events = false, fixed_input_delay_turns = spec.fixed_delay; DIRECT: world built like net's world_builder) -> QaTimedSystem.install when profiling -> twin = open(spec, driver) when spec.twin
2  loop while tick < max_ticks and not outcome.over:
3      scripted / bot / AI commands are produced by their owners: the AI = host-side NetAiRunner (SESSION) or its emulation (DIRECT), thinking when (E + pid) % period == 0; net's default period is 5 turns (ai.md 13.16 asks net for per-level periods [5,3,2,1]; the chain goldens depend on the adopted table and are regenerated if it changes)
4      t0 = usec; n = advance(); metrics.record_tick(tick, (usec - t0) / n) for the n ticks executed
5      events = drain_events -> QaEventStats.consume
6      every 20 ticks: chain.append(tick, checksum_at(tick), input_chain)
7      every invariants_every ticks: violations = validate(); the first violation stops the match (HC4)
8      every 100 ticks: QaStuckDetector.sample(world); metrics.sample_memory; metrics.record_entities(tick, world.entities.size())
9      twin: advance() the twin identically; compare checksum_at on every checkpoint (HC3)
10     wall > wall_limit -> stop WALL_LIMIT; QA_PROGRESS on cadence
11 result = assemble(...) (per-player counters straight from SimPlayer.st_*); close(main, twin) on every path; guard counts -> result.log
```
One `advance()` is one lockstep turn (2 ticks, independent of the speed setting because pacing belongs to the app): SESSION moves the manual clock by `TURN_MS` (100 ms), DIRECT calls `world.apply_turn(cmds); world.step(); world.step()`. There is no real-time pacing, so the runner is CPU-bound (target >= 20x real time for 2 players, 5.8).

#### 5.4.3 Plans and tiers
* **AI presets (ai.md 10.3, unchanged):** `pr` = 6 fixed 1v1 on 128x128 (cap 8 min, <= 3 min on 4 shards); `smoke` = 8 vanilla rosters round-robin, 28 pairs, open, Hard (cap 10 min, <= 3 min on 8 shards); `nightly` = all 32 rosters round-robin **496 pairs x 3 map families = 1,488 matches**, Hard vs Hard, sides alternate by `(i + j + m) % 2`, + difficulty ladders (Hard-Medium, Medium-Easy, Brutal-Hard: 40 games each) + 20 four-player and 4 eight-player FFAs (cap 25 min); `weekly` = nightly + swapped sides (2,976 pair-matches) + Brutal/Easy ladders + 5 % `repeat-check` + Linux-container canary (cap 30 min); `arena` = equal-spend armies.
* **Roster order** `R[0..31]` for QA plans: faction-major in bible order (`napc, nec, olm, def, pd, han, ae, sap`), each faction `[vanilla, sub1, sub2, sub3]` in bible order. `epoch` = `YYYYMMDD` int, `e6 = epoch % 1000000`.
* **ROTATION (96 matches, 2 players, cap 24,000 ticks = 20 game minutes, AI HARD, sizes 96/128/128 for OPEN/URBAN/COAST):** for map `m in {0,1,2}` and roster `i in 0..31`: `f = i / 4; s = i % 4; d = 1 + ((3*m + s) % 7); e = (m + 1) % 4; j = ((f + d) % 8) * 4 + ((s + e) % 4)`; match = `R[i]` vs `R[j]`; side swap when `((epoch + 7*i + 13*m) % 2) == 1`; `seed = e6 * 1000 + m * 100 + i`. *(Verified by script over the real 32 ids: per map `j` is a bijection so every roster appears exactly twice per map family (once each side); never the same faction (`d` in 1..7); all 56 ordered / 28 unordered faction pairs occur; 96 distinct roster pairs; 96 distinct seeds; no vanilla-vs-vanilla, which AI `smoke` covers.)* Examples: map0 i0 = `napc.vanilla` vs `nec.nordics`; map0 i1 = `napc.usa` vs `olm.algeria`; map1 i0 = `napc.vanilla` vs `pd.indonesia`; map2 i0 = `napc.vanilla` vs `sap.pakistan`; map2 i1 = `napc.usa` vs `nec.vanilla`.
* **ENDURANCE (3 matches, cap 72,000 = 60 game minutes, 8 players FFA, size 192, AI HARD, one per map family):** player `f` uses roster `4*f + ((e6 + f) % 4)`; `seed = e6*1000 + 900 + m`. Pass = zero errors + HC5/HC6 + SC3/SC7 bounds; this is the "zero crashes in a 60-minute 8-player match" requirement. It runs with `--invariants=20` (sim_core 10.5's continuous-soak cadence) and with events enabled, because the AI consumes them (sim_core's `events = false` soak setting is for command-only runs such as the fuzzers).
* **CONTENT (32 matches):** 5.5.1.
* Wall-time model: `wall_s = sum(ticks x mean_tick_ms x calib_factor) / 1000 / workers`. With the *(estimate)* 3 ms mean tick: ROTATION = 96 x 24,000 x 3 ms = 115 min serial = ~15 min on 8 workers (x2.6 on leg C = ~40 min); ENDURANCE = 72,000 x ~9 ms = 11 min each; AI `nightly` and `weekly` per ai.md (~1.6 h and ~3.2 h on 8 shards; *ai.md estimates*).

#### 5.4.4 Robustness criteria (per match; `QaSoakJudge.judge_match`; apply to QA runs **and** AI presets)
| Id | Criterion (hard = fails the run at every milestone from M1) | Source of the value |
|---|---|---|
| HC1 | process exit 0 and a complete result (`QA_RESULT.completed == true`; for AI presets `AISOAK_END` for every `AISOAK_BEGIN`) | stdout sentinel |
| HC2 | 0 engine errors, 0 leak lines, <= 10 warnings, `world.events.dropped == 0` (a drained-every-turn buffer never reaches its soft cap; sim_core 5.7) | `logscan` on the captured output, attributed per match by `AISOAK_BEGIN/END` |
| HC3 | no desync: `twin` match for every ENDURANCE match and for `index % 3 == e6 % 3` in ROTATION; replay re-verified (`replay_verify`) for the same subset; AI presets use their `repeat-check` (`cmd_log_hash` + `final_checksum` equal, ai.md D1) | twin / replay / repeat-check |
| HC4 | 0 invariant violations: sim_core's `SimInvariants.check` INV-1..INV-14 (ids ascending and never reused, kind and owner lists exact, `owned[]` and the counters equal a recount, spatial hash consistent, `1 <= hp <= max_hp`, positions inside the map, orders <= 32 with a handler, teams consistent) plus QA's `QaGameInv` G1..G7 (credits >= 0, unit cap respected, queue length <= 5, power balance equals recomputation, produced units satisfy tech prerequisites, roster legality, player enum fields in range) | `QaSimAdapter.validate()` every 100 ticks |
| HC5 | `max_tick_us / calib <= 100,000`; `p99_us / calib <= 12,000` (2 players) or `<= 32,000` (>= 5 players) | `qa.timing_us` |
| HC6 | `static_end - static_after_warmup(tick 2,000) <= 64 MB` (2 players) / `200 MB` (8 players); after `close()`: `OBJECT_COUNT <= baseline + 50` and orphan nodes unchanged | `qa.memory` |
| HC7 | legal outcome: winner team valid, or draw/adjudication flagged with `stop_reason == TICK_CAP`; defeat ticks monotone; no negative credits at any sample | outcome + samples |
| HC8 | reproducibility: for `index % 4 == 0` a fresh-process rerun with the same spec gives the same `final_checksum` | `soak.py` rerun |
| SC1-SC5 | AI quality: first Radar/tank/AA/siege/superweapon timings, idle ratios, income, stuck units <= 2 %, decisive rate, ladders (Hard beats Medium >= 85 %, Medium beats Easy >= 85 %, Brutal beats Hard >= 65 %), cross-roster fairness (fail outside 30-70 %; alarm band 35-65 %) | **ai.md 10.5, adopted verbatim** |
| SC6 | content coverage (5.5.1) | QA |
| SC7 | entity headroom: peak `world.entities.size()` (sampled every 100 ticks) <= 75 % of `SimConfig.MAX_ENTITIES` (8,192) and no spawn failure in the log (sim_core 3.4.5: `spawn_*` returns null and logs when `live >= MAX_ENTITIES`) | QA (`QaMetrics`) |
`AiMatchResult` lacks memory/invariant/timing fields, so `AiSoakRunner` must add a `qa` block with the same names QA uses: `qa: {engine_errors:int, max_tick_us, p99_tick_us, static_kb_warm, static_kb_end, objects_start, objects_end, orphans_end, peak_entities, invariant_violations:[String], twin_ok:bool}` [QA-XR-25]; `QaSoakJudge.normalise()` maps `QaMatchResult` fields (`timing_us.p99`, `memory.*`, `log.errors`, `invariants.violations`, `outcome.winner_team`) and `AiMatchResult` (`ticks`, `winner_team`, `adjudicated`, `qa.*`) onto one record.

#### 5.4.5 Stuck detection (`QaStuckDetector`, same definition as `AiMetrics.unit_stuck`)
Every 100 ticks the detector walks `world.units` (ascending id, skipping `F_GONE` and `F_INSIDE`). A unit whose head order is movement-class (`SimOrder` types `MOVE 16`, `PATROL 17`, `FOLLOW 18`, `ATTACK_MOVE 33`, `RETURN_BASE 36`, `HARVEST 48`, `RETURN_CASH 49`, `CAPTURE 50`, `REPAIR 51`, `SALVAGE 52`, `LOAD 64`, `GARRISON 66`, `DEPLOY_MCV 70`; sim_core 4.7) is *stuck* after 6 consecutive samples (600 ticks = 30 s) with displacement < 1,024 units (1 cell) and no `t_hit` inside the window; the movement mirror flag `F_BLOCKED` (bit 18, sim_core 4.3; maintained by movement, [QA-XR-18]) is recorded as the diagnostic reason. Collectors waiting in a refinery's dock queue are legitimate waiters and are excluded while a `HARVEST`/`RETURN_CASH` order holds the head and the unit is within 4 cells of a friendly refinery (ASSUMPTION(economy): the dock queue stays inside that radius). Threshold: stuck / units-with-move-orders <= 2 % (ai.md 10.5). A *stall window* is a 2,400-tick window in which a non-defeated player's credits, entity count and completed-structure count are all unchanged (ai.md watchdog `W1-W4` cover the AI side; QA's window also catches non-AI matches).

#### 5.4.6 Batch verdict and the M4 composition
`QaSoakJudge.judge_batch` computes `score2` (win 2, draw/timeout 1, loss 0) per roster and Wilson intervals at z = 1.96 (`p = score2 / 2n`). **M4 exit (weekly runs, n >= 93 games per roster):** (a) no roster outside 30-70 % (ai.md fail line) in either of two consecutive weekly runs with different epochs; (b) the ai.md alarm band 35-65 % holds for >= 30 of 32 rosters and the remaining ones are on the balance owner's waiver list; (c) each vanilla roster's Wilson interval intersects [0.45, 0.55]; (d) no ordered faction pair (n >= 48) outside [0.20, 0.80]; (e) timeouts <= 20 %; (f) all HC criteria 100 %. For n = 93 the interval test (c) is equivalent to an observed rate of about 35-65 %; it tightens as n grows. Requiring two consecutive runs halves false alarms (a truly balanced set has a ~12 % chance of one spurious roster alarm per run). AI-vs-AI rates are a proxy for human balance (risk R18; ai.md R8 agrees).

### 5.5 Content coverage and balance conformance

#### 5.5.1 Roster content bot (`QaContentBot`, plan CONTENT)
32 runs (one per roster), 2 players, COAST 128 with `start_near_water=1` (so Docks are placeable; the land tree is also exercised on OPEN because the bible requires that every roster is playable on a land-only map), rules `start_credits=100000` (the maximum of net's `rules_schema`, net.md 7.1) and `allow_debug=1`, so the bot tops credits up with `DEBUG` mode 1 whenever they fall below 20,000, cap 48,000 ticks, opponent = AI EASY of faction `(f+1) % 8`. Every 10 ticks the bot issues at most 8 commands: (1) if the construction queue is idle, the next structure in topological order of `requires_all_structure_ids` (Radar -> T2, Radar + Laboratory -> T3) placed on the first valid cell scanning rings 2..8 cells from the HQ (build radius 8); generators are inserted whenever power is short; (2) every idle producer queues the next not-yet-produced unit of its roster (queue length <= 5); (3) the research queue takes any available upgrade; (4) each support power is fired once when off cooldown at the target kind its text implies (reconnaissance: any cell; strike/area: enemy HQ; support: own army centroid); (5) the superweapon fires at the enemy HQ when charged; (6) produced units gather and attack-move at tick multiples of 1,200. Output: coverage sets and `blocked[{kind,id,reason}]`. **Gate:** for all 32 rosters `blocked` is empty except entries in `fixtures/content_waivers.json` with a reason, and the union over the 32 runs covers **156 units, 29 structures, 40 research, 48 powers, 8 superweapons** (`metadata.expected_counts`; 48 unique subfaction units, 4 service units). The three conditional modifiers (`modifier.napc.canada.03` vehicle on water, `modifier.olm.el_andalus.02` infantry in a marked civilian garrison, `modifier.ae.01` target receiving paid land-vehicle repairs) each have a two-way scenario test (data 5.5.5 names the runtime handling).

#### 5.5.2 Balance conformance (`QaBalanceProbe`; input `game/data/balance/global.json targets`, owner balance)
* **TTK:** for each of the 25 rows `[attacker_archetype, target_archetype, min_s, max_s]` of `ttk_unopposed_s` and each of the 8 vanilla rosters: spawn one attacker and one target (`QaWorld.spawn`, flat open map, full health, no regen), order attack, count ticks until death: pass if `min_s - 0.05 <= ticks/20 <= max_s + 0.05` (one tick of slack). Archetype -> unit via `unit_assignments`.
* **Equal-cost RPS:** for each of the 12 bands `[A, B, lo, hi]` in `rps_equal_cost.bands`: 6,000 credits of A vs 6,000 of B at 24 cells, metric = remaining cost share A minus B; median of 3 seeds must lie in `[lo, hi]`.
* **Sortie / defenses / structure-kill / superweapon-value / first power shortage (240 s):** same style with the ranges of the `sortie`, `defenses`, `structure_kill`, `superweapon`, `power_first_shortage_after_s` blocks.
* Gate M4: all rows pass or carry a balance-owner waiver in `fixtures/balance_waivers.json`; failures are filed as S2 bugs against balance/sim (which side is wrong is decided with `tools/py/balance_calc.py`, the analytic model).
* Rule/scenario tests of economy (`test_prod_*`, queues, power shortage), combat and abilities belong to those domains; 5.17 lists which of them gate milestones.

### 5.6 Network testing (complements net.md; QA owns the process-level real-socket matrix)

**Levels.** L1 (net-owned, in `gd test`): `NetTransportLoopback` + `NetTransportFault` with `NetClock.manual`, `NetSimAdapterFake`, S1-S20, presets `lan, wifi, bad_wifi, internet, awful, raw_chaos, local`. L2 (QA orchestrates net's harness): two or more **real Godot processes** with real ENet over 127.0.0.1, optionally through `udp_impair.py` (real datagram loss/reorder that the L1 decorator only models). L3 (QA, T3): cross-OS: host on macOS, client in the Debian container reaching `host.docker.internal:27615` *(raw UDP round trip verified: the container reached the host and got its reply; ENet through the Docker NAT is expected to work and is the point of the test)*.

**Process recipe (`net_two_process.py`, drives `game/tests/net/net_harness.gd`).** Per process a sandbox: `HOME=<builds/qa/run/proc_k>` (macOS/Linux; also `XDG_DATA_HOME=$HOME/.local/share` on Linux) or `APPDATA=<dir>` on Windows *(unverified-win)*, so `user://` (logs, replays, desync dumps, `last_test_run.json`) never collides *(verified for macOS `HOME` and Linux `XDG_DATA_HOME`)*; unique ports per process set (`--port`, outside 27614..27624 unless the case tests the defaults; net's socket tests use `28100 + pid % 300`); `--discovery` off except N16c (serialise it: the discovery port 27614 is fixed); each process is `tools/gd run res://tests/net/net_harness.gd -- --role=host|client --players=N --ai=K --sim=fake|real --turns=N --script=<file> --fault=<preset> --fixed-delay=2 --speed=0 --seed=S --out=<json> --countdown=0`; the orchestrator parses the `NETTEST role=... chain=0x... final=0x... checks=N desync=0 stalls=N delay=N bytes_out=N` lines, applies external signals (`kill -STOP/-CONT/-9`), and enforces the QA green rules (no engine errors, exit codes, `NETTEST` present). Before the real sim exists, `--sim=fake` (`NetSimAdapterFake`, golden values in net.md 10.2) runs the whole matrix.

**Matrix (N-cases; N0-N3 are net's P1-P5 verbatim, the rest are QA additions).**
| Id | Setup | Pass criteria |
|---|---|---|
| N0 | = net P1: host + 1 client, fake sim, 3,000 ticks, `--fixed-delay=2` | equal `chain/final/checks`, `desync=0`, exit 0, < 30 s |
| N1 | = net P2: host + 2 clients, `--fault=wifi` on all, 6,000 ticks | same; `stalls` small |
| N2 | = net P3: host + client + 2 AI, real sim, scripted | same |
| N3 | = net P5: `kill -STOP` a client 20 s, `auto_drop_ms = 8000` | host sees `DISCONNECTED` at ~6.5 s, auto-drops ~11.5 s, completes the match; the stopped client exits non-zero after `SIGCONT` |
| N4 | proxy `lan` pass-through | result byte-identical to N0 |
| N5 | proxy `wifi`: 10 ms +-8, 1 % real datagram loss | equal chains; total stall <= 2 s per 5 min |
| N6 | proxy `bad_wifi`: 30 ms +-25, 3 % loss | equal; adaptive delay ends in [3,5] turns |
| N7 | proxy `awful`: 150 ms +-60, 4 % loss | equal; delay reaches its cap 8; ticks >= 80 % of the ideal (net S5) |
| N8 | proxy `raw_chaos`: dup 3 %, reorder 10 % at datagram level | equal; ENet's own dedup/reorder handle it; `dup_in`/`ooo_in` reported |
| N9 | proxy `capped`: 64 kbit/s | equal; per-client average <= 8 kB/s |
| N10 | proxy `blackout3` (client->host 3 s at t = 10 s) | stall overlay <= 0.6 s, resumes, delay unchanged (quarantine), equal chains |
| N11 | proxy `blackout45` (both directions 45 s) | host prompt at 8 s; disconnect/auto-drop per rule; survivors finish with equal chains |
| N12 | proxy `corrupt1`: 1 % corrupted datagrams | no crash on either side (may disconnect); survivors never differ |
| N13 | `kill -9` client at t = 20 s | host detects <= 8 s, `player_status` changes, no crash, host continues |
| N14 | 8 processes (host + 7 clients, scripted, fault `wifi`) | equal chains on all 8 (T3) |
| N15 | cross-OS: macOS host + Debian-container client (`--cross-os`) | equal chains |
| N16 | (a) version/data mismatch: one process started with a modified data file -> `JOIN_REJECT(DATA_MISMATCH)` with the table/file diff lines (net S15); (b) forced desync: `--corrupt-at=400:1:12345` on ONE client (applies `QaCorrupt` section 1 = RNG: 12,345 extra draws) -> `desync_detected` on both within 2 s real time, `DesyncKind.SIM`, package files on both; (c) discovery with `set_targets_override(["127.0.0.1"])` -> entry visible <= 3 s, `compatible == true` (real broadcast on a LAN is manual R-14) | as stated |
**Universal pass criteria:** (1) surviving processes exit 0 and print `NETTEST`; no engine errors, no leak lines; (2) `final` and `chain` equal across survivors and **equal to the offline golden** of the same script and fixed delay (`match_runner --driver=direct` reference) unless the case kills/drops a player; (3) `stalls`/`delay` within the row; (4) memory/objects bounded; (5) N0 vs N4 vs N5 vs N6 give identical chains for identical scripts and fixed delay (network conditions must never change the simulation).

### 5.7 Fuzzing (commands, network packets, files)

**Principles.** Deterministic (seeded `QaFuzzRng`, test vectors in 10.1), fast (per-iteration guard 50 ms), self-minimising failures (`{target, seed, iter, input}` saved to `fixtures/fuzz/regress/` and replayed forever by `test_fuzz_regressions.gd`), and *oracle-based*: a fuzz case fails on any engine error (Logger), any invariant violation, any non-determinism, or any resource blow-up.
| Id | Target | Mutation strategies | Oracles |
|---|---|---|---|
| F-CMD-1 | `SimCommand` objects through `world.submit` / `SimCommandSystem.execute` (sim_core 3.5): all 40 opcodes plus every unknown op 0x00-0xFF | (a) random field values inside the ranges implied by `SimCommand.schema_of(op)`; (b) schema-aware: a valid command with one field replaced by boundary values {0, -1, 1, 2^31-1, 2^31, value +-1, map edge +-1 cell}, dead/enemy/foreign/never-allocated entity ids, out-of-map cells, invalid def indices, own-vs-other pid, pid 255, `ids` of size 0/1/256/257 (unsorted, duplicated); (c) valid/invalid interleavings across a pause; (d) 128 commands x 256 ids per turn (max load) | no engine error; `validate()` (INV-1..14 + G1..G7) empty after every tick; **rejection purity** (a command whose `execute` returns `Err != OK` leaves `world.checksum()` identical to a control world that never saw it - sim_core 5.5: "failing commands have no effect"); two worlds fed the same stream have equal chains; tick time <= 5x baseline |
| F-CMD-2 | wire: `SimCommandCodec.decode_batch` on random bytes (0..1,024) and on mutated valid batches | single-bit flips of the golden 47-byte batch and of random valid batches, truncation at every length, varint attacks (6 bytes, > 0x7FFFFFFF, overlong), zero id delta, `n = 129`, `count = 257`, op sweep 0..255, trailing bytes | returns false with `out` empty, or true with decode -> encode -> decode idempotent; never an engine error; <= 1 ms per batch |
| F-CMD-3 | privileged ops: `DEBUG` (0x0F) with `allow_debug = 0`, `PLAYER_DROP` (0x04) from `pid != 255`, `pid = 255` on any other op | random fields | all refused (`Err != OK`), checksum unchanged; only the host connection may inject `PLAYER_DROP` (net) |
| F-PKT-1..7 (net runs 20,000 random + 20,000 mutated buffers per decoder in `test_net_codec` at T0; QA runs 10x that in T3 and adds the session-level cases) | `NetCodec.decode_*` per message type; `NetLobbyCodec` (snapshot, action, chat, launch); `NetDiscovery` datagram parser; `NetMatchConfig.validate` (JSON) | random bytes 0..2,048; valid message + single-bit flips (every bit of small messages); truncation at every prefix length; random tail extension; varint attacks (overlong, 0xFFFFFFFF, 6 bytes); type-byte sweep 0..255 for every phase/direction; oversize (`> MAX_*`); deflate bomb (100 KB of zeros compressed -> 100 MB) | decoder returns `null`/`{}`, **never** calls `decode_*` out of range (engine error), never allocates from an unvalidated length, <= 1 ms per <= 64 KB packet, bomb rejected in <= 50 ms with < +10 MB memory |
| F-PKT-8 | `NetReplayData.from_bytes` / `NetReplayPlayer` | mutated replay bytes (header, records, trailer), truncation | `null` or `truncated == true`; no crash; verify reports mismatch cleanly |
| F-PKT-9 | session level: two honest clients + one hostile peer through `NetTransportLoopback` | garbage, replayed, out-of-window, oversize, wrong-phase messages | honest peers keep equal chains; hostile peer kicked at violation score >= 12 (net `VIOLATION_KICK_SCORE`); host phase machine unchanged |
| F-FILE-1..4 | `settings.cfg` (ConfigFile), `game/data/**/*.json`, replay files, `credits.json` | `QaFuzzFiles.mutate_json/cfg/bytes` | load returns a clear error/default; corrupt settings renamed `.bad-<utc>`; no crash |
Budgets: T1 = 2,000 iterations per target (<= 30 s total); T3 = 200,000 per target (<= 30 min total); regression corpus replay is part of T0 (`tests/regress`-style, < 5 s).

### 5.8 Performance

**Calibration.** `QaCalibrate.run()` executes the fixed 3,000,000-iteration xorshift128 loop (reference 294 ms on RM). `factor = max(1.0, ms / 294)`: slower machines get proportionally larger budgets, faster machines are *not* credited. It is run at start and end of every perf job; if the two differ by > 15 % (thermal/background load) the job repeats. Its checksum (`acc`, `s3`) doubles as an integer-determinism check.

**Cost model (measured, RM arm64 / Rosetta x86_64 slice)**: SoA update 128 / 402 ns per entity-tick (~20 typed statements, i.e. ~6 ns/statement in tight loops); object-field update 229 / 540 ns; 9-cell neighbour scan 1,451 / 3,615 ns; static call 83 / 174 ns; int dict lookup 54 / 94 ns. The domain specs budget with a more conservative 0.1-0.15 us per statement (economy: "<= 0.8 ms typical"; combat: "<= 5 ms typical, <= 12 ms at stress S"; abilities: vision 3.2 ms/tick at 1,680 entities/480 movers; ai: <= 1.5 ms per AI per tick; net: <= 1 ms average). Summed at the 400-entity battle that is ~9 ms on their model and ~3-4 ms at the measured 20-30 ns per realistic statement (mix of packed-array arithmetic, calls and dictionary lookups). QA therefore sets the gate at the measured model and requires **each domain to publish its own measured ns/statement** (abilities task AB-05 already plans a micro-benchmark) so the ratchet is argued with data at M2 (risk R1). *(estimate)* per-entity per-tick at PS1: movement update 0.13 + separation scan 1.45 + steering/path-follow 0.5 + target scan 2.0 (stride 4 -> 0.5) + weapon/aim 0.4 + projectiles/damage 0.4 + orders/economy amortised 0.3 = ~3.7 us -> 400 entities = 1.5 ms + vision 0.5 + production/economy/power 0.4 + checkpoint (sim_core 9 measures 1.8 ms at 1,200 units on RM, so ~0.6 ms at 400 entities on every 20th tick, ~0.03 ms amortised) + engine call overhead => **~3-3.5 ms**. The budget *requires* SoA/packed arrays, stride systems, incremental vision and capped path requests (DR-11); a naive object-per-component design lands at 8-12 ms and fails the gate.

**Budgets (RM units; multiply by `factor`; enforcement slack per milestone below)**
| Metric | Scenario | Mean | p95 | p99 | Max |
|---|---|---|---|---|---|
| Sim tick | PS0 kernel floor: 1,200 idle units, all domain stages stubbed (sim_core 9 measured 0.54 ms per idle step and 1.8 ms per checkpoint on RM) | 0.8 ms | 2.0 | 3.0 | 4.5 |
| Sim tick | PS1 400 mobile + 60 structures | 3.5 ms | 5.5 | 8.0 | 12 |
| Sim tick | PS2 1,200 mobile + 320 structures (8 players, AI HARD) | 11 ms | 16 | 22 | 35 |
| Sim tick | PS3 opening state, 2 players | 0.6 ms | 1.0 | 1.5 | 3 |
| Sim tick | PS4 200-unit path burst | 4.5 ms | 7 | 10 | 16 |
| Sim tick | PS5 300 movers over shroud 256x256 | 4.0 ms | 6 | 8 | 13 |
| Sim tick | PS6 PS1 + 3 powers + superweapon | 4.5 ms | 7 | 10 | 16 |
| AI (ai.md 10.5, adopted) | per AI per tick | avg <= 1.5 ms | - | <= 4.0 | think call <= 9 ms (`call_cap_wu`), never > 12 ms (net throttle) |
| Net (net.md 9, adopted) | 8 players | avg <= 1 ms | - | - | worst frame <= 8 ms |
| Throughput | `match_runner`, 2 players incl. AI | >= 20x real time (mean tick <= 2.5 ms) | | | |
| Frame time (rendered) | PV1 1080p Medium, RM | p50 4 ms | 8.3 | 12 | 25 |
| Frame time | PV2 4K High, RM | p50 8 ms | 16.6 | 22 | 40 |
| Render stats | PV1 | draw calls <= 1,800; primitives <= 3.5 M; VRAM <= 1.2 GB; CPU render <= 3 ms | | | |
| Floor hardware (manual, M5) | 1080p Low on a 2019 4-core x86 + integrated GPU | >= 60 FPS p95 (16.6 ms), draw calls <= 1,200 | | | |
| Memory (headless) | 2 players, 24 k ticks | RSS <= 250 MB, static <= 90 MB | | | |
| Memory (headless) | 8 players, 72 k ticks | RSS <= 420 MB, static <= 250 MB | | | |
| Memory (rendered) | 2 p / 20 min; 8 p / 60 min | RSS <= 1.3 GB; <= 2.2 GB; VRAM <= 1.5 GB High / 0.8 GB Low | | | |
| Leak drift | after tick 2,000 | static <= +0.5 MB/min; after 3 teardown cycles: objects <= baseline + 50, static <= baseline + 10 MB | | | |
| Load | cold start -> main menu interactive | <= 3.0 s (SSD) | | | |
| Load | data load (bible + balance + resolve 32 rosters) | <= 250 ms | | | |
| Load | map generation 96 / 128 / 192 / 256 | <= 0.3 / 0.6 / 1.5 / 2.5 s | | | |
| Load | "Start" -> first controllable frame, 2 p 128x128 / 8 p 192x192 | <= 5 s / <= 9 s | | | |
| Load | replay open (header + first frame) | <= 1 s | | | |
| Hitches | frames > 33 ms in the first 60 s of a match | <= 3 (shader baker enabled) | | | |
| Network (from `stats()`) | 8 players | client average <= 12 kB/s, peak <= 40 kB/s; host average <= 60 kB/s | | | |
**Ratchet.** `perf_baseline.json` stores accepted *normalised* results. Gate = `value <= min(budget x slack, baseline x 1.15)`; slack = 2.0 at M1, 1.5 at M2, 1.25 at M3, 1.0 from M4. The baseline improves automatically when a run is better by > 10 % on 3 consecutive runs and is never raised without a CHANGELOG reason. **Decision point (R1):** at M2, if PS1 mean exceeds 2.0x budget with the measured cost model, the architect chooses between restructuring hot loops, cheaper cadences for vision/AI, or raising the budget with a written argument.
**Protocol.** Warm-up 120 ticks/frames excluded; >= 1,200 ticks measured; median of 3 runs per statistic; per-system timing only in profiling runs (2 `Time.get_ticks_usec` per system per tick). Frame time uses `--disable-vsync` and **not** `--fixed-fps` (which disables real-time sync); GPU/CPU render time via `RenderingServer.viewport_set_measure_render_time` + `viewport_get_measured_render_time_cpu/gpu` and `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME / _PRIMITIVES_IN_FRAME / RENDER_VIDEO_MEM_USED` *(all verified in class docs)*. Rendered jobs run only when `DisplayServer.get_name() != "headless"`.
**Emulated legs as slow-CPU proxies.** Container leg C (x2.61) approximates a mid-range x86 desktop for CPU-bound sim work: PS1 mean on leg C must be <= 3.5 x 2.61 = 9.1 ms and p99 <= 20.9 ms (informational until M4, gating at M5). This is a proxy, not a substitute for the M5 floor-hardware run. Frame arithmetic: a 60 FPS frame is 16.7 ms and a tick lands every third frame, so on the floor machine a 9 ms tick plus ~6-8 ms of rendering just fits the tick frame and leaves two of three frames idle - hence the requirement for stride systems, SoA arrays and capped path requests. Cross-check with sim_core 9: PS0 on leg C (x2.61) predicts 1.6 ms mean and ~6.1 ms on checkpoint ticks, matching sim_core's own reference-PC estimate (about 2 ms average, 6.5 ms on checkpoint ticks), and PS1's 3.5 ms becomes 9.1 ms there, i.e. about the 8 ms sim share of a 60 FPS frame that sim_core budgets.
**Worst cases and mitigations.** Path burst (PS4) -> cap requests per tick (DR-11), spread over ticks, cache flow fields; vision (PS5) -> update only on cell change, stride 2 (abilities 9.2: moved-list, restamp budget 128/64); checkpoint tick (1.8 ms at 1,200 units) -> accepted as one slow tick per second; if profiling demands, `SimConfig.CHECKSUM_INTERVAL` 40 identically on every peer (sim_core 9: splitting a checkpoint across ticks is forbidden); superweapon (PS6) -> impact packets processed with a per-tick cap; activation spikes (economy: BUFF on 256 targets 2-4 ms) -> two-batch application; AI (PS2) -> governor 8 ms per boundary (net); GC-like spikes cannot occur (no GC) but `Array.append` growth can: preallocate.

### 5.9 Visual regression (screenshots + agent-reviewed checklist)

**Platform ids** (golden sets are per platform because GPU output differs): `macos-arm64-metal` (primary, committed), `linux-x64-lavapipe` (Debian amd64 container: Xvfb + Mesa Vulkan software rasteriser; renders Forward+, Mobile and Compatibility *(toolsmith-verified)*), `linux-arm64-gl` (arm64 container: Debian 12's lavapipe aborts on aarch64 for Forward+/Mobile, so `gd linux --arch arm64 shot` switches to `gl_compatibility` by itself - usable only for layout and HUD cases), `windows-x64-vulkan` (manual), plus per-GPU sets for M5 hardware runs (not committed).
**Generation.** `tools/gd shot res://tests/visual/visual_case.tscn builds/qa/<run>/visual/<platform>/<id>.png --size 1920x1080 --frames 60 -- --case=<id>` (tooling's `gd shot` forces `--fixed-fps 60 --disable-vsync` and an off-screen window). `visual_case.gd` reads `--case`, builds the deterministic scenario from `cases.json` (7.6): `SimWorld` from a fixture stepped N ticks with the DIRECT driver, camera pose, UI state, quality preset, UI scale, colour-blind mode, seeded VFX RNG and frozen animation clocks [QA-XR-28].
**Automatic checks (VA-1..VA-5, exit non-zero on failure, per image):** VA-1 not blank (`blank_ratio < 0.60` and luma stddev > 0.03); VA-2 no placeholder pixels (magenta #FF00FF +-8 or the engine missing-texture checker) `< 0.01 %`; VA-3 size equals request; VA-4 vs golden of the same platform id: PSNR >= 38 dB and `diff_pct <= 0.5 %` -> `unchanged`, else `changed` (requires review, not a failure); no golden -> `new`; VA-5 no engine errors while capturing.
**Agent review protocol.** `visual_report.py worklist` lists every `new`/`changed` case plus the `always` cases at gates. For each, the reviewing agent must (1) open the PNG with the image reader; for HUD cases also the generated 2x crops (`*_sidebar.png`, `*_minimap.png`, `*_topbar.png`); (2) write `review/<id>.json` (7.7) with one verdict per applicable checklist item; (3) obey the rubber-stamp guards enforced by `visual_report.py check`: every `fail`/`waived` has a note of >= 12 words naming the region; every `pass` of a `strict` item has an observation of >= 6 words; notes may not be identical across cases; reviewer role must differ from the author role of the changed module. Fails become bugs (routing: TERRAIN/FOG/UNIT/FX/STRUCT -> view (map for terrain data); HUD/MENU/TEXT -> ui; ICON -> the owner of the asset). On all-pass `visual_report.py approve <id>` stores the image downscaled to 960x540 lossless as the new golden (<= 60 goldens x <= 0.6 MB) and appends a CHANGELOG line.
**Checklist (`checklist.json`; `strict` = observation mandatory)**
| Id | Category | Statement |
|---|---|---|
| V-T01 | terrain | land, water, road, cliff and forest are distinguishable at default zoom; no chunk seams (strict) |
| V-T02 | terrain | no z-fighting, flicker or floating decals/shadows |
| V-U01 | unit | each unit class (infantry, light vehicle, tank, artillery, aircraft, ship) has a distinct silhouette at >= 24 px (strict) |
| V-U02 | unit | the 8 player colours are distinct on units, structures and minimap; no bleed into non-team parts (strict) |
| V-U03 | unit | health bars and selection rings are aligned with their unit and readable on light and dark ground |
| V-S01 | structure | footprint matches the placement grid (overhang <= 0.25 cell); construction state visible |
| V-S02 | structure | placement ghost valid/invalid is distinguishable without colour (pattern/icon) (strict) |
| V-F01 | fx | combat VFX are visible but do not hide units; particle density sane |
| V-F02 | fx | superweapon warning and impact are readable; no full-screen flash brighter/longer than the photosensitivity limit (A-10) (strict) |
| V-G01 | fog | shroud and fog edges smooth; hidden enemies not visible; explored-not-visible is distinct from visible |
| V-H01 | hud | sidebar, minimap, resource/power bar, selection panel do not overlap; margins >= 16 px at 1280x720 (strict) |
| V-H02 | hud | no clipped or overflowing text at 100 % and 150 % scale; effective font >= 14 px at 1080p (strict) |
| V-H03 | hud | every build icon present; no placeholder; consistent style |
| V-H04 | hud | tooltips fully on-screen and legible |
| V-M01 | menu | focus/hover/disabled states distinct; consistent spacing; no untranslated keys |
| V-X01 | text | body text contrast >= 4.5:1 on the actual background (automated value + agent confirmation on busy backgrounds) |
| V-A01 | a11y | under protanopia/deuteranopia/tritanopia simulation the team colours remain separable (pattern/shape cues present) |
| V-B01 | render | no black frames, tofu boxes, NaN-black squares, banding, shimmering shadows |
| V-R01 | render | quality preset visible difference Low < Medium < High without breaking layout |
| V-L01 | layout | ultrawide 21:9 and 16:10 keep HUD anchored, world not stretched |
| V-IP1 | ip | no real-world flags, emblems, logos or brand marks anywhere (all factions are fictional commands) (strict) |
| V-ID1 | ip | no bible/data IDs (`unit.napc...`) visible to the player |
**Domain-owned visual scenes** (net V1-V7 lobby/mismatch/stall/desync/replay/overlay/browser, abilities V1-V8, economy overlays 10.4, combat V-1..V-6, AI debug overlay) are registered in `cases.json` with an `owner` field and reviewed through the same pipeline; the owning domain supplies the scene and its deterministic fixture, QA supplies capture, auto-checks, review records and goldens.
**Case inventory at M5 (>= 60):** 3 map families x 2 zooms (6); each of 8 factions' base at T1 and T3 (16); 8 roster contact sheets; 5 combat scenes (infantry, armour, air, naval, artillery); 8 superweapons (warning + impact = 16 images counted as 8 cases); 2 fog cases; 6 HUD cases (720p/1080p/1440p x scale 100/150); main menu, skirmish setup, lobby, settings x3, victory, defeat; 3 colour-blind simulations; renderer fallbacks (`mobile`, `gl_compatibility`) for 2 cases.

### 5.10 Data validation gate

**What exists (owned by data, `data_balance.md`):** the Python validator `tools/py/validate_balance.py` (rule ids `V-SCH/REF/CMP/CNF/RNG/TIER/ROLE/MOD/ROS/EFF/ABL/DET/HASH-*`, exit 0 clean / 1 errors / 2 warnings with `--strict`), the in-engine `DefValidator` (FAST at release, FULL in debug/CI), `game/tests/tools/data_cli.gd` (`--validate`, `--hash`, `--dump <kind>`, `--update-goldens`), unit tests `test_data_*.gd`, and goldens `convert_vectors.json` (>= 300 cases, Python == GDScript), `resolver_golden.json` (V-MOD-12: resolved matches equal the bible's `modifier_applications` for all 32 rosters), `data_hash.json` (V-HASH-01). The numeric model is **normative there**: basis points, `half_up(base * (10000 + S1) * (10000 + S2) / 10^8)` with one rounding for layers 0-2 and a second for layer 3, ceil-based 60 %/50 % floors, `seconds_to_ticks = ceil_div(milli * 20, 1000)` from exact integer milli-units (the ceil-of-float trap `ceili(21.000000000000004) == 22` is data's own finding), resistance cap 5000 bp. Its worked examples (the 20 rows of its 5.6, bases from the balance framework, e.g. Guardian cost 850 -> 935, Narwhal health 907 -> 1097, Beaver health 602 -> 728, China Imperial Guard Tank health 1588 * 0.90 * 1.15 -> 1644, synthetic floor 250 -> 150) are its acceptance numbers. QA defines no competing rounding table.

**QA's data gate = five things.**
1. **Run them, strictly.** T0 executes `validate_balance.py --strict` and `data_cli.gd --validate` (level FULL), plus the `test_data_*` suites, and requires zero errors and zero unexpected warnings (`validator_allow.json` is the only allow-list; every entry has a reason). The real bible must report exactly the pinned numbers: **158 modifier applications, 570 effective (target, modifier) applications, exactly 2 no-ops** (data 5.5.4), 3 unresolved target domains, 3 conditional modifiers.
2. **Cross-leg hash parity.** `GameData.handshake()` (`hash`, `tables`) is printed by `data_cli.gd --hash` on legs A, B, C (and E/F later) and must equal `golden/data_hash.json` everywhere (V-HASH-01 on every leg, not just macOS). A per-table diff (`table units differs`) localises the culprit. This is the QA-owned half of data's request #22 ("`tools/gd linux` printing `GameData.handshake()`").
3. **Independent tolerance oracle (`ref_oracle.py`, DA-20).** Both data implementations (PY and GDScript) were written from one specification by one author, so a shared misreading of the *bible formula* would pass their parity vectors. The oracle re-derives, from the bible JSON and the balance JSON only and with `fractions.Fraction`, the value `base * prod over layers (1 + sum(delta_percent)/100)` in designer units for every (roster, def, stat), converts it to runtime units by exact rational arithmetic (cells x 1024, seconds x 20 with ceil, percent x 100), and requires `|GameData value - exact| <= 1` unit (`<= 1` tick for durations; `<= 1 mt` for reload), which accepts exactly `{floor, ceil}` of a non-integer exact value and exactly `{exact}` when the exact result is an integer, correct application of floors/caps, correct roster scope (which entities a modifier reaches, service-unit exclusion, replaced units) and the conditional stats (`speed_water`, garrison damage, paid-repair cost). The tolerance mirrors data's documented layer-3 second rounding (<= 1 unit); anything larger is a formula, scope or selector error. The oracle needs `data_cli.gd --dump units|structures|...` (data-owned) and nothing else from data.
4. **Cross-cutting checks the data rules do not cover** (`QaDataAudit`, ids below; DA-06..DA-09 and DA-11..DA-19 are deliberately unassigned, reserved for checks that data's own `V-*` rules do not yet cover).
5. **Content coverage** (5.5.1) and **balance conformance** (5.5.2) - behaviour, not just numbers.

| Id | QA cross-cutting check |
|---|---|
| DA-01 | registry counts equal `metadata.expected_counts`: 8 factions, 32 rosters (8 vanilla + 24 sub), 104 + 48 + 4 = 156 units, 29 structures, 98 modifiers, 40 research, 48 powers, 8 superweapons, 27 selectors (data V-CMP-01..03 also check; QA pins the numbers) |
| DA-02 | `game/data/bible/meridian_factions.json` sha256 == `Input/meridian_agent_reference/meridian_factions.json` (`sync_bible.py --check`; the mirror is never hand-edited; data V-CNF-07) |
| DA-03 | `validate_reference.py` (bible package validator) exits 0 |
| DA-04 | `validate_balance.py --strict` exits 0; `data_cli.gd --validate` (level FULL) clean |
| DA-05 | data goldens verify (`convert_vectors.json`, `resolver_golden.json`, `data_hash.json`) and are registered in `MANIFEST.json` |
| DA-10 | `data_hash` identical on legs A, B, C, E, F (item 2 above) |
| DA-20 | tolerance oracle: 0 violations for all 32 rosters x all defs x all stats |
| DA-21 | oracle sweep of the float trap: for every bible `*_seconds` value (0.5, 0.6, 6, 8, 10, 15, 20, 25, 30, 35, 40, 45, 50, 75, 90, 120, 150, 180, 210, 360, 420, 480) x integer percent -40..+40 (1,377 combos for the 17 build-time bases), GDScript ticks equal `ceil(exact x 20)` computed exactly; the naive float method differs in 115 of those 1,377 (e.g. 6 s at -20 % -> 96 not 97) and the test asserts both numbers |
| DA-22 | economy sanity: `balance/global.json economy.derived` recomputed from its constants (income at 12 cells = 582 credits/min per collector, start 7,500 credits, `standard_field_credits` = 14,400) |
| DA-23 | every unit/structure has a procedural recipe (`game/data/recipes`), an icon, name + description strings; every gameplay event has a sound mapping (`SndEventMap.missing()` empty) |
| DA-24 | all displayed strings exist in `game/data/text/*.json`; no bible/data id is visible to players; string length limits |
| DA-25 | JSON hygiene for non-balance JSON (`credits.json`, fixtures, `cases.json`): parses, no duplicate keys, no NaN/Infinity, integers <= 2^53, UTF-8 without BOM, LF, final newline (balance files are covered by V-SCH-02..04) |
| DA-26 | every font file has an OFL text in its directory (5.11) |
| DA-27 | every voice/music/sfx asset has a provenance entry with an allowed licence (5.11) |
| DA-28 | `credits.json` lists every component in `THIRD_PARTY.json` marked shipped |
| DA-29 | rosters resolvable and economically viable on OPEN, URBAN and COAST (no mandatory water; >= 2 exits per start; reachable deposits: `credits_per_player_reachable_min` 60,000) - runs the map generator for 24 seeds |
| DA-30 | `content_waivers.json` and `balance_waivers.json` reference existing ids and carry a reason; text files under `game/` and `docs/`: LF, no BOM, final newline (extend tooling's L010) |

### 5.11 Licensing, credits and TTS findings

**Inventory.** `LICENSES/THIRD_PARTY.json` (machine-readable, source of truth) renders `LICENSES/THIRD_PARTY.md`; fields per component: `name, version, spdx, licence_file, copyright, url, shipped (bool), modified (bool), used_for`. `licenses.py audit` fails if a shipped component lacks a licence file or a credits entry.
**Godot.** MIT/Expat with bundled third-party components. The exported binary contains the engine and its libraries, so the notices must ship: `LICENSES/GODOT_LICENSE.txt` = `Engine.get_license_text()` (1,149 chars, "Copyright (c) 2014-present Godot Engine contributors ... 2007-2014 Juan Linietsky, Ariel Manzur"), and `LICENSES/GODOT_THIRD_PARTY.txt` generated by `license_dump.gd` from `Engine.get_license_info()` (19 licence texts: Apache-2.0, BSD-2/3-clause, BSL-1.0, CC0-1.0, CC-BY-4.0, Expat, glslang, ...) and `Engine.get_copyright_info()` (102 components). The in-game Licenses screen reads the same APIs at runtime, so text always matches the shipped engine build. (Do not hand-copy.)
**Fonts (SIL OFL 1.1).** Rules: ship each family's OFL text with its copyright line next to the font files (`game/assets/fonts/<family>/OFL.txt`) and in `LICENSES/fonts/`; never modify or subset a font that declares a Reserved Font Name (if modification is ever needed, rename); never sell fonts alone; credit in `CREDITS.md`. *Current state (2026-09-29, `prototypes/ui/fonts`, read-only inspection):* Chakra Petch (Medium, SemiBold; no RFN declared), Exo 2 (variable), Orbitron (variable; RFN "Orbitron"), Rajdhani (Medium, SemiBold, Bold; no RFN declared), Saira Condensed (SemiBold), Share Tech Mono (RFN 'Share'). **Finding F-1: OFL text files exist for Chakra Petch, Orbitron, Rajdhani and Share Tech Mono, but none for Exo 2 and Saira Condensed; DA-26 fails until their `OFL.txt` (with the upstream copyright lines) are added.** Recommended accessibility addition: Atkinson Hyperlegible (OFL) as the dyslexia-friendly option (A-17).
**TTS / generated audio (findings dated 2026-09-29; verified from installed package metadata in `.cache/venv*` and from primary web pages; not legal advice).**
| Component | Licence | Verdict |
|---|---|---|
| Kokoro-82M weights + `voices-v1.0.bin` (`.cache/tts/kokoro-v1.0.int8.onnx`) | Apache-2.0 (model card; kokoro-onnx README "kokoro model: Apache 2.0"). Trained on "permissive/non-copyrighted audio: public domain, Apache/MIT-licensed, synthetic audio from closed commercial TTS" (model card) - residual upstream-terms risk low-medium | **Allowed** as generator for shipped voice lines, with provenance |
| kokoro-onnx 0.4.7, onnxruntime 1.30.0, soundfile 0.14.0, numpy, scipy | MIT / MIT / BSD-3 / BSD-3 / BSD-3 | allowed (build-time only, not shipped) |
| phonemizer-fork 3.3.1; espeak-ng (`libespeak-ng` via espeakng_loader 0.2.4) | GPL-3.0-or-later | **tool only**: the produced WAV is program *output* and is not covered by the GPL unless it contains program text (FSF GPL FAQ position); nothing GPL is shipped in the game; record "phonemizer: espeak-ng (GPL-3.0-or-later), tool only" in provenance |
| piper-tts 1.8.0 (`.cache/venv_piper`; upstream `OHF-Voice/piper1-gpl`) | GPL-3.0-or-later engine (bundles g2pW Apache-2.0 and espeak-ng data); upstream `VOICES.md`: "Piper is intended for personal use and text to speech research only ... Some voices may have restrictive licenses ... `MODEL_CARD`" | **Not allowed** for shipped audio unless one specific voice's `MODEL_CARD` grants commercial use (CC0/CC-BY) and its exact text is archived; default: do not use. No Piper voice model is present in the local `.cache/` (git-ignored) today |
| macOS `say`, `AVSpeechSynthesizer`, Personal Voice | Apple SLA; Apple developer forum thread on commercial use gives no permission and reports that `say` voices cannot be used commercially | **Prohibited** for shipped assets |
| Windows SAPI / OneCore voices | EULA not verified | **Prohibited** until verified |
| Runtime OS TTS through `DisplayServer.tts_speak` (API verified) | audio produced on the user's machine with the user's voices; nothing redistributed | **Allowed** for optional accessibility announcements (off by default) |
| Procedural voice-like sounds (formant/noise synthesis in numpy) | none | Allowed |
Constraint: ARCHITECTURE allows only stdlib + numpy + Pillow in `tools/py`; the ONNX/Kokoro stack is therefore outside the standard toolchain (kept in `.cache/venv*`), run manually by the audio owner, and only its outputs plus `PROVENANCE.json` are committed. `PROVENANCE.json` entry: `{file, sha256, generator, model, model_sha256, voice, text, language, licence_model, licence_tools, created_utc, tool_versions}`; DA-27 allow-list for `licence_model`: `Apache-2.0, MIT, CC0-1.0, CC-BY-4.0 (requires a credits line), procedural`.
**Project licence.** Not decided by the owner. Until `docs/AMENDMENTS.md` records a decision, the repository carries **no licence grant** (all rights reserved by default) and README must say exactly that. Options compatible with Godot MIT and OFL fonts: (A) MIT or Apache-2.0 for code + CC BY 4.0 for generated assets (recommended default for an openly built game; Apache-2.0 adds a patent grant); (B) proprietary EULA/freeware. Agent-generated assets may have limited copyright protection (jurisdiction dependent) - a counsel question outside QA. Blocker for M6 (R5).
**Trademark hygiene.** Shipped text never uses the trademark "Command & Conquer" (README says "inspired by classic base-building real-time strategy games"); no real flags/emblems/brands in art (V-IP1).
**Credits.** `game/data/text/credits.json` (7.8) drives the in-game Credits screen: Game (roles), Engine (Godot + link to Licenses), Fonts, Audio (generators, models, licences), Special thanks; the Licenses screen lists `THIRD_PARTY.json` plus the engine APIs above.

### 5.12 Logs, crash reports, settings and save locations

`user://` resolves per OS (custom dir name `MeridianFracture` is already set in `project.godot`):
| OS | `user://` |
|---|---|
| macOS | `~/Library/Application Support/MeridianFracture/` *(verified)* |
| Linux (Debian) | `$XDG_DATA_HOME/MeridianFracture/`, default `~/.local/share/MeridianFracture/` *(verified)* |
| Windows | `%APPDATA%\MeridianFracture\` *(unverified-win)* |
| Item | Path under `user://` |
|---|---|
| Settings | `settings.cfg` |
| Engine log (+ rotation) | `logs/godot.log`, `logs/godot<YYYY-MM-DDTHH.MM.SS>.log`; net's own `logs/net*.log` |
| Crash reports | `logs/crash/crash_<utc>.txt`, `crash_<utc>_unclean.txt` |
| Session sentinel | `.session` |
| Replays | `replays/autosave_1..3.mfreplay`, `replays/<name>.mfreplay`, `replays/_recording.mfreplay.tmp` |
| Desync packages | `desync/desync_<match8>_p<pid>_t<tick>.{json,state.txt,mfreplay,checks.csv}` (net.md 5.7; newest 10 packages kept) |
| Screenshots | `screenshots/<utc>.png` |
| Caches | `cache/` (data cache, safe to delete), `shader_cache/` and `vulkan/` (engine-created) |
| Test-only | `qa_tmp/`, `last_test_run.json` |
* **Enabling logs.** `project.godot` currently sets `file_logging/enable_file_logging=false` and `.pc=false` (correct for shared dev runs). Exports need `debug/file_logging/enable_file_logging.standalone=true` and `debug/file_logging/max_log_files=10` (counts the current file: 9 history + current; rotation renames the old file to `godot<mtime>.log` at startup *(verified)*) [QA-XR-6].
* **Format.** Engine lines untouched. Game lines go through core's `Log` (sim_core 3.2.7: `Log.t/d/i/w/e(tag, msg)`, levels TRACE..OFF, 256-line ring; it has no clock because `src/core` is clock-free) and the **app's sink**, which adds the line format `[E|W|I|D] <ms since start> [tag] message`, the rate limit of 20 lines/s/tag with a suppression counter and the file output [QA-XR-23]. INFO by default, DEBUG only in debug builds; the sim never logs per tick. Size guard: `godot.log` < 5 MB per hour of play (measured in the endurance run; violation = S2).
* **`AppLogger`** (`Logger` subclass, `OS.add_logger`): mirrors `_log_error` into `Log.ring` (last 256 lines) and an error counter; never prints inside `_log_error`; must tolerate an empty `script_backtraces` array (backtraces and `get_stack()` exist only in debug builds; tests always run with the editor binary, toolsmith gotcha 9).
* **Crash handling.** `debug/settings/crash_handler/message` = "Meridian Fracture crashed. A report was saved in the logs folder; please attach it when reporting." On start `AppCrashReporter` writes `.session` (`{pid, start_utc, version}`) and deletes it on clean quit; on `NOTIFICATION_CRASH` (constant 2012 on `Node`/`MainLoop`, verified) it best-effort writes `logs/crash/crash_<utc>.txt`; on the next start a leftover `.session` yields `crash_<utc>_unclean.txt` (tail of the previous `godot.log`) and a non-blocking toast "The game did not close properly last time" with *Open logs folder* and *Copy report*. Net's `NetReplay.recover_orphans()` handles the replay tmp file.
* **Report header** (all fields required, test `test_app_crash_report_fields`): game version + build id, Godot version, OS + version, arch, CPU name/cores, RAM, GPU adapter name/vendor/type/API version (`RenderingServer.get_video_adapter_*`), rendering method + driver, display server, screen size/scale/refresh, locale, `user://` path, uptime, phase (menu/lobby/match), match summary (rosters, map family/size/seed), sim tick + last checksum, net role. **Never** other peers' IP addresses or chat text.
* **Privacy.** No telemetry and no network traffic except LAN gameplay/discovery (proposed rule L012); crash reports are never uploaded.
* **Retention.** Autosave replays 3 (`replay_autosave_count`), desync packages newest 10 (net deletes the oldest on the 11th; <= 200 MB), crash reports newest 20, `logs/net*.log` rotated with the engine log policy, screenshots unlimited (UI shows folder size), warning at 1 GB total.
* **Settings robustness.** `[meta] version=N` + migration table; unknown keys preserved; a corrupt file is renamed `settings.cfg.bad-<utc>` and defaults are used with a toast. **Writes are crash-safe without relying on an atomic rename** (`DirAccess.rename` is remove-then-rename, not atomic *(toolsmith gotcha 7; concurrent writers of one `user://` file can lose the rename)*): (1) write `settings.cfg.tmp` completely and flush; (2) if `settings.cfg` exists, rename it to `settings.cfg.bak`; (3) rename `.tmp` to `settings.cfg`; (4) on load, if `settings.cfg` is missing or unparsable and `.bak` parses, load the `.bak` and restore it. The same protocol applies to `desync` reports and to golden updates. Test `test_app_settings_atomic_write` interrupts the sequence after each step (simulated by a fault-injecting file layer) and asserts that a valid file is always recoverable; on Windows the remove-then-rename behaviour additionally fails while another process holds the file open *(unverified-win)*. Window position is clamped to existing screens on load (X-13).
* **Saves.** There are no save games; replays are the persistence mechanism (net.md scope).
* **Sandbox rule for tests/agents:** nothing outside `QaTemp` and the sandboxed `HOME`; never delete files you did not create in a shared `user://`.

### 5.13 Release packaging (builds on tooling's packagers)

**Versioning.** SemVer `MAJOR.MINOR.PATCH[-rcN]` in `application/config/version` (read by `env.project_version()` in the packagers and by net as `game_version`), macOS `application/version` + `short_version`, Windows file/product version. `SimConfig.SIM_VERSION`, `NetProtocol.PROTO_VERSION` and the data hash are independent and appear in the lobby handshake, the crash header and `MERIDIAN_BOOT`. A release is a tagged commit (`vX.Y.Z[-rcN]`) + `builds/packages/` + `SHA256SUMS.txt` (`gd snapshot release-<ver>` still makes a source tarball outside git).
**Pipeline (tooling steps exist; QA steps are new).**
```
export.py export all                    (tooling)  release template, exclude_filter "tests/*"   -> builds/<platform>/
release_payload.py --version V          (QA)       docs, licences, credits, CONTROLS, RELEASE_NOTES -> builds/release/V/payload/
package_windows.py [--payload DIR]      (tooling)  -> builds/packages/meridian-fracture-V-windows-x86_64.zip
package_linux.py   [--payload DIR]      (tooling)  -> ...-linux-x86_64.tar.gz + meridian-fracture_V_amd64.deb
package_macos.py   [--dmg]              (QA)       -> meridian-fracture-V-macos-universal.zip (+ .dmg)
verify_release.py builds/packages       (QA)       SHA256SUMS.txt + structure/header/smoke/lintian/install checks
```
Sizes *(measured by tooling with the boot scene)*: Windows zip 38.1 MB (exe 109 MB + console wrapper + pck), Linux tar.gz 28.4 MB, `.deb` 28.4 MB, macOS `.app` 171.8 MB (zip ~65-75 MB *(estimate)*); budget <= 250 MB compressed per package once game data is added.
**Shared payload** (next to the binary, never inside the macOS bundle so its signature stays valid): `README.txt` (5-line quick start, requirements, unsigned-app instructions, LAN ports **UDP 27615-27624 game and 27614 discovery** - the current Windows README names only 27615), `CONTROLS.md`, `USER_MANUAL.md`, `CREDITS.md`, `RELEASE_NOTES.md`, `LICENSES/` (`MERIDIAN_LICENSE.txt` once decided, `GODOT_LICENSE.txt`, `GODOT_THIRD_PARTY.txt`, `fonts/OFL_*.txt`, `THIRD_PARTY.md`); `SHA256SUMS.txt` sits in the package directory.
**Reproducibility.** Tooling already fixes tar mtimes (`1_700_000_000`), uid/gid 0, gzip `mtime=0`; QA's test builds every package twice and requires identical sha256 (zip entries need fixed `date_time` and Unix modes in `external_attr`, [QA-XR-8]); the macOS `.dmg` (`hdiutil`) is exempt.

| Package | State today (tooling) | QA requirements (deltas) |
|---|---|---|
| **Windows zip** | `meridian-fracture-<ver>/` with `MeridianFracture.exe`, `.pck`, `.console.exe`, `README.txt` (CRLF) | + payload; console wrapper only in QA/debug builds (release GUI exe is enough; the wrapper helps support, so shipping it is allowed but must be documented); unsigned (`codesign/enable=false`): SmartScreen shows "Windows protected your PC" -> *More info* -> *Run anyway*; antivirus false positives mitigated by SHA-256 and by never self-extracting or writing beside the exe; first LAN host/join raises the Windows Defender Firewall dialog -> allow *Private networks*; requirements: Windows 10 64-bit or later, Vulkan 1.2 or D3D12 GPU (tooling's README), no VC++ redistributable *(unverified-win; closed by R-01/R-02)* |
| **Linux tar.gz** | ELF + `.pck` + `.desktop` + icon + `README.txt` | + payload + `INSTALL.txt` (dependency list below); embedded PCK optional (`binary_format/embed_pck=true`, [QA-XR-5]); never `strip` a binary with an embedded PCK |
| **Debian package** | pure-Python `ar`/tar writer; `/opt/meridian-fracture/` + `/usr/bin/meridian-fracture` symlink + `.desktop` + icon; `md5sums`; `postinst`; `--test-deb` installs it in Debian 12 and smoke-runs it | **Quality bar: `lintian` 0 errors after documented overrides.** Lintian findings on the current shape *(verified on an equivalent test package)*: `E: no-copyright-file` (must ship a DEP-5 `copyright` that lists Godot's MIT text and every bundled licence), `E: no-changelog changelog.Debian.gz`, `E: dir-or-file-in-opt` (overridable in `usr/share/lintian/overrides/meridian-fracture` if `/opt` stays), `W: no-manual-page`. **Recommended layout (verified lintian-clean with 1 archive-upload-only warning):** `/usr/games/meridian-fracture` (ELF, PCK embedded), `/usr/share/applications/*.desktop`, `/usr/share/icons/hicolor/256x256/apps/*.png`, `/usr/share/doc/meridian-fracture/{copyright,changelog.Debian.gz}`, `/usr/share/man/man6/meridian-fracture.6.gz`, `DEBIAN/{control,md5sums}`. Also: replace the "Command & Conquer style RTS" description (trademark, 5.11); use the verified `Depends`/`Recommends` below; `StartupWMClass` must equal the emitted WM_CLASS/app_id (X-09); tooling's control uses `Depends: ... libgl1, libvulkan1 ... libasound2 \| libpulse0`, which lacks `libegl1` and the Debian 13 alternative. Control file in 7.10 |
| **macOS zip** | CI runs `ditto -c -k --keepParent builds/macos/MeridianFracture.app builds/packages/meridian-fracture-macos-universal.zip` (no version in the name) | `package_macos.py` names it `meridian-fracture-<ver>-macos-universal.zip`, adds the docs folder next to the app; checks `lipo -archs` = `x86_64 arm64`, `codesign --verify --deep --strict` OK (ad-hoc, preset `codesign/codesign=1`; min macOS 12.0; bundle id `com.meridianfracture.game`; Mach-O name "Meridian Fracture" with a space), executable bits preserved; optional `.dmg`: `hdiutil create -volname "Meridian Fracture <ver>" -srcfolder <staging with app + Applications symlink + docs> -ov -format UDZO` |
**Debian dependencies (Debian 12 bookworm and 13 trixie, amd64; kernel >= 5.15 ELF note, glibc >= 2.28 symbols; Debian 11 is unsupported).** The engine has only glibc as a hard `NEEDED`; everything else is `dlopen`ed, so a missing library degrades a feature or crashes at window creation. Verified: a test package with the lists below installs on `debian:12` (12.15) and `debian:13` (13.7) containers with all names resolved.
```
Depends:    libc6 (>= 2.28), libx11-6, libxcursor1, libxext6, libxi6, libxinerama1, libxrandr2, libxrender1,
            libxkbcommon0, libfontconfig1, libegl1, libvulkan1, libasound2t64 | libasound2
Recommends: mesa-vulkan-drivers | nvidia-vulkan-icd, libgl1-mesa-dri, libpulse0, libudev1, libdbus-1-3,
            libwayland-client0, libwayland-cursor0, libwayland-egl1, libdecor-0-0
Suggests:   speech-dispatcher
```
Roles: `libvulkan1` + a Vulkan ICD = Forward+ (default); `libegl1` + `libgl1-mesa-dri` = OpenGL 3 fallback (project fallbacks enabled); `libasound2t64 | libasound2` (Debian 13 renamed the package in the 64-bit `time_t` transition; the alternative resolves on both) and `libpulse0` (PulseAudio and PipeWire-pulse) = audio; `libudev1` = hotplug; `libdbus-1-3` = screensaver inhibit; Wayland trio + `libdecor-0-0` = Wayland client and window decorations; `libspeechd2`/`speech-dispatcher` = optional TTS accessibility.
**macOS: opening an unsigned (ad-hoc) app.** Move it to `/Applications` first (Gatekeeper *App Translocation* runs quarantined apps from a randomised read-only path; the game only writes to `user://`, but LAN firewall prompts repeat). macOS 15 and later: double-click -> dialog says Apple could not verify it -> *System Settings > Privacy & Security* -> scroll to *Security* -> "Meridian Fracture was blocked" -> *Open Anyway* -> authenticate -> *Open*. macOS 12-14: Control-click the app -> *Open* -> *Open*. Any version, terminal: `xattr -dr com.apple.quarantine /Applications/MeridianFracture.app`. If macOS says the app "is damaged and can't be opened" it is the quarantine flag on an unnotarised app: run the same command. First LAN use: allow incoming network connections. Wording on macOS 26/27 must be re-verified at M6 (host runs macOS 27.0). Notarisation would need an Apple Developer ID and is out of scope.
**Verification (`verify_release.py`).** Per package: unpack to a temp dir; file list equals the expected manifest; no `tests/`, `tools/`, `docs/spec` or `res://tests/` strings inside the `.pck`; executable bits; header check (PE `MZ` + machine `0x8664`; ELF machine 62; Mach-O fat magic with x86_64 + arm64); `SHA256SUMS.txt` matches (two-space format, `shasum -a 256 -c` and `sha256sum -c` compatible); shared payload non-empty; version string identical in file names, `application/config/version` and the `--smoke` line (`MERIDIAN_BOOT ... version=<ver>` [QA-XR-14]); host-compatible package launches with `--headless --smoke` (exit 0) and prints `selftest=ok` (`Fp.self_test()`, the cheapest Windows-arithmetic proof available before leg E runs a full chain). **Install tests:** `.deb` in clean `debian:12` and `debian:13` containers (tooling's `--test-deb` on 12; QA adds 13 and `lintian`), tar.gz smoke in a container, zip smoke on the Windows runner, mac zip unpack + `codesign --verify` + smoke. Manual checklist R-01..R-24 (5.17) covers what containers cannot.

### 5.14 Cross-platform pitfalls checklist (`X-nn`; "L" = lint rule; "T" = test; "M" = manual)
| Id | Pitfall | Detection / rule |
|---|---|---|
| X-01 | **Case-exact paths.** Editor on macOS/Windows resolves wrong-case `res://` paths; an exported `.pck` does not (verified); Linux disk is case-sensitive | L001 (literal paths) + T `QaExportManifest.verify` in the QA export + T2 container run |
| X-02 | Path separators: only `/`; use `path_join`, `get_file`, `get_base_dir`; no `\`, no drive letters, no `OS.get_executable_path()`-relative writes | grep gate for backslash path separators inside `.gd` string literals; T `test_paths_no_backslash` |
| X-03 | Windows-reserved names (`con prn aux nul com0-9 lpt0-9`, with or without extension), trailing dot/space, case-insensitive duplicates, path < 150 | L002 (covers reserved 1-9 and length; add `com0/lpt0` and duplicate-lowercase check) |
| X-04 | **Locale**: engine number parsing/printing is locale-independent (verified: `"1,5".to_float()=1.0`, `%` formatting uses `.`); `TranslationServer.format_number/parse_number` are locale-dependent | proposed L011 (banned outside `src/ui`, `src/app`); T1 subset under `LC_ALL=de_DE.UTF-8` and `tr_TR.UTF-8` + `--language de`/`tr` (D3f); UI money format via `UiFormat` with fixed grouping |
| X-05 | Line endings: LF everywhere; Godot never translates CRLF | `.gitattributes` `* text=auto eol=lf`, `*.png *.ttf *.wav *.ogg binary` [QA-XR-9]; DA-30; goldens normalised on read |
| X-06 | **High-DPI**: `allow_hidpi=true` (default), `stretch/mode=canvas_items`, `aspect=expand` (current), macOS `display/high_res=true` (preset), Windows per-monitor, X11 has no automatic scale | UI scale setting Auto = `DisplayServer.screen_get_scale()` (fallback dpi/96); handle `NOTIFICATION_WM_DPI_CHANGE` (value 1009, verified); layout audit at 1x/1.25x/1.5x/2x; M on a Retina and a 4K monitor |
| X-07 | **Window focus**: on `NOTIFICATION_APPLICATION_FOCUS_OUT` (2017) / `WM_WINDOW_FOCUS_OUT` (1005) release edge-scroll, drag-select, held keys and mouse confinement; never pause a lockstep sim; `application/run/low_processor_mode` stays false; swallow the focus-in click; lower frame cap when unfocused but keep ticking | T `test_app_focus_release`; M R-13 |
| X-08 | **Firewall prompts** (LAN): Windows Defender dialog on first bind of the UDP game port 27615-27624 and discovery port 27614; macOS "accept incoming connections" (repeats when an ad-hoc signature changes); Debian usually none (`ufw allow 27614:27624/udp`); Wi-Fi AP client isolation blocks broadcast -> manual IP join; multi-NIC hosts (VPN, Docker bridges) can hijack limited broadcast | net's `announce_ok`/`browse_error` hints (UI text); manual guide in USER_MANUAL; M R-14/R-16 |
| X-09 | **Wayland vs X11 (Debian 12/13)**: `--display-driver x11/wayland` both exist *(verified from `--help`)*; project setting `display/display_server/driver.linuxbsd`. Wayland: no window positioning, no global cursor warp, fractional scaling, `MOUSE_MODE_CONFINED` depends on pointer-constraints, client-side decorations via libdecor | do not call `window_set_position`/`warp_mouse` as required behaviour; edge-scroll from cursor position vs window rect; `.desktop` `StartupWMClass` must match the emitted WM_CLASS/app_id; M R-05/R-06 run both sessions |
| X-10 | Keyboard layouts: bindings by `physical_keycode`; show labels with `DisplayServer.keyboard_get_label_from_physical` (verified) | T `test_ui_bindings_physical`; M R-18 |
| X-11 | Mouse/trackpad: macOS Ctrl+click = right click; no middle button on many laptops; gestures | every mouse-only action has an alternative binding; Magnify/Pan gestures mapped; M R-19 |
| X-12 | Fullscreen: default borderless windowed-fullscreen; exclusive fullscreen optional; macOS native Space | M R-11 |
| X-13 | Multi-monitor: clamp saved window rect to existing screens; refresh rate per screen; monitor unplugged | T `test_app_window_clamp`; M R-11 |
| X-14 | Save/config only in `user://` (table 5.12); never beside the exe; shader cache lives in `user://shader_cache` (Windows: Roaming AppData - keep < 200 MB, offer "clear caches") | L-rule no absolute paths; T |
| X-15 | Non-atomic replacement: `DirAccess.rename` is remove-then-rename (toolsmith gotcha 7); Windows cannot replace/delete open files | `.bak` write protocol (5.12); T `test_app_settings_atomic_write` on all legs; replay rotation while open |
| X-16 | Unicode: ASCII file names; UTF-8 text; player names may be CJK/Arabic/emoji -> font fallback (`SystemFont`), no crash, tofu tolerated; names sanitised before use in file names (net does) | F-PKT + T `test_ui_unicode_names`; M |
| X-17 | Time: replays and logs store UTC + ticks, never local time in sim/file names except formatted UTC | T |
| X-18 | Endianness/word size: all targets are little-endian 64-bit; codecs are explicit LE (`PackedByteArray.encode_*` is LE, verified) | T `test_codec_le_bytes` (canary line `enc_s64`) |
| X-19 | Integer/shift UB: shift counts masked mod 64 identically on x86_64/arm64 (verified) but C++ leaves them undefined; negative-constant shifts are parse errors; sim_core's `Fp` uses constant shift counts only | canary lines `shl`/`shr_neg`; `Fp` unit tests; lint `SL-7` (negative literal next to a shift; literal shift count >= 32) |
| X-20 | Threads: sim single-threaded; `WorkerThreadPool` results merged in deterministic order; `--single-threaded-scene` leg | D3c |
| X-21 | Renderer backends: Metal (mac), Vulkan (Win/Linux), fallbacks D3D12/OpenGL3; effects gated by capability queries (`RenderingServer.get_current_rendering_method()`), never OS name | shots with `--rendering-method mobile` and `gl_compatibility` (V3); M R-09 |
| X-22 | GPU/driver quirks (Intel iGPU, AMD, NVIDIA proprietary, Apple) | M R-09 matrix; known-issue list |
| X-23 | Audio: default mix 44100 Hz vs device 48 kHz (engine resamples); PulseAudio/PipeWire/ALSA; device hot-swap; no device must not crash (`--audio-driver Dummy`) | T runs whole suite headless with Dummy; M R-12 |
| X-24 | Sleep/hibernate/lid: wall-clock jumps must not cause tick bursts (`MAX_ELAPSED_US=250000`, `ACC_CAP_TICKS=4` in net) | net T with manual clock jump; M R-13 |
| X-25 | macOS App Nap / occlusion and Windows background throttling can starve a minimised client (others stall) | document "keep the window visible in LAN games"; measure in M R-13 |
| X-26 | Antivirus/SmartScreen/Gatekeeper on unsigned binaries | 5.13; SHA-256 published |
| X-27 | Read-only install dirs (`/usr/games`, Program Files, translocated app) | never write outside `user://`; T that `res://` writes are absent (grep `FileAccess.open("res://`) in `src/`) |
| X-28 | XDG: honour `XDG_DATA_HOME` (verified for `user://`); `XDG_CONFIG_HOME` for `OS.get_config_dir()` | sandbox recipe 5.6 |
| X-29 | Command line: user args after `--`; Windows quoting; official templates refuse `--path` (verified) and do not offer `--script`/`--main-pack` | QA hook `--qa=`; docs |
| X-30 | Interface selection for LAN discovery on multi-NIC machines; IPv6 | net `broadcast_candidates` unit tests; M R-14 |
| X-31 | Non-ASCII/space in install and user paths (for example a Windows user folder named `Zoë`) | CI job sets `APPDATA` to a Unicode path *(unverified-win)*; T on macOS with a Unicode `HOME` |
| X-32 | Exported build differs from editor: asserts compiled out of release templates, `res://` case, `FileAccess.file_exists` on scripts false, resource remaps | leg F, `QaExportManifest`, lint L013 |
| X-33 | Godot upgrade drift: `hash()`, `sort_custom` tie order and float formatting may change | canary golden per engine version; upgrade = new golden revision with reason |
| X-34 | Shared `user://` between concurrent processes on one machine | sandbox `HOME`/`APPDATA` per process (5.6); never delete files you did not create |
| X-35 | Project text files: no BOM, LF, `.uid` files present for every script after import | DA-30, proposed L015 |
| X-36 | Debian version support: kernel >= 5.15 per ELF note, so Debian 11 (5.10) is out; Debian 12/13 in | doc; `.deb` `Depends` |

**Sim-kernel lint rules (sim_core R22; ids `SL-n` so they never collide with tooling's `L001-L010`).** `tools/py/qa/check_sim_rules.py` runs in T0 after `gd check` over `game/src/core` and `game/src/sim` (SL-8..SL-10 also over the domain systems' folders). *Already enforced by tooling's L003 and only pinned here by seeded-violation fixtures* (`tools/py/tests/fixtures/lint/`): SL-1 (unqualified float builtins `sin( cos( atan2( sqrt( pow( exp( log( floor( ceil( round( roundi( floori( ceili(`; allow-list `sqrt` in `Fp.isqrt`, `roundi` in `Fp.milli`), SL-2 (`randi randf randomize RandomNumberGenerator shuffle( pick_random`), SL-4 (`float Vector2 Vector3 Transform Color` in sim/core state). *Implemented by QA:* **SL-3 remainder** (`await`, `call_deferred`, `Thread`, `Mutex`, `Timer`, `emit_signal`, `signal ` in sim/core; `Time.` and `OS.get_ticks` are L003's), **SL-5** (a class deriving `SimComponent`/`SimEntity`/`SimPlayer`/`SimOrder` without `hash_into`, or with a member `var` that its `hash_into` never mentions - regex level; the reflection test `check_hash_coverage` stays authoritative), **SL-6** (`Dictionary` members in sim state classes; allow-list: `SimWorld` diagnostics), **SL-7** (negative literal next to `>>`/`<<`, or `<<` with a literal count >= 32), **SL-8** (a member typed `SimWorld` in any `SimSystem`/`SimComponent` subclass: a RefCounted cycle), **SL-9** (`.sort_custom(` in sim code without a `# total order:` comment), **SL-10** (append, erase or sort on `world.entities|units|structures|wrecks|zones|deposits` or on the results of `units_of()/structures_of()` outside `SimWorld`). Each rule has a unit test and a violating/clean fixture pair; a line may be waived with `# lint-allow: SL-n reason` (tooling's convention). In addition `test_qa_hash_coverage_meta` requires that every `class_name ... extends SimComponent` and every `SimSystem` with private state has a test calling `SimTestKit.check_hash_coverage` (DR-13).

### 5.15 Accessibility checklist (`A-nn`; automated = T, manual = M)
| Id | Requirement | Check |
|---|---|---|
| A-01 | 8 player colours pairwise CIEDE2000 >= 20 (normal) and >= 12 under protanopia, deuteranopia, tritanopia simulation (Machado 2009, severity 1.0); a non-colour cue (pattern/shape/number) on minimap dots and unit base markers | T `QaContrast.min_pairwise_delta_e`; V-A01 |
| A-02 | Contrast >= 4.5:1 body text, >= 3:1 large text (>= 24 px, or >= 18.66 px bold) and UI graphics, for every `UiTheme` state (normal/hover/pressed/disabled/focus) | T over theme tokens [QA-XR-28] |
| A-03 | Effective text >= 14 px at 1080p/100 %; UI scale 75-200 %; no overflow (layout audit at 1280x720, 1366x768, 1920x1080, 2560x1440, 3840x2160 x scales 1.0/1.5/2.0) | T `QaLayoutAudit` |
| A-04 | Full keyboard navigation of all menus (Tab, Shift+Tab, arrows, Enter, Esc); visible focus ring; no keyboard trap | T `QaA11yAudit` focus-graph walk |
| A-05 | Every in-game action rebindable with conflict detection and reset; settings persisted | T |
| A-06 | Mouse-only and keyboard-only viability: every shortcut has a UI button; camera and selection cycling by keyboard | M |
| A-07 | No information by sound alone: announcements also as text log + screen-edge alert + minimap ping; captions option | T/M |
| A-08 | Separate volume sliders (master, music, SFX, voice, UI); mute-on-focus-loss toggle | T |
| A-09 | Reduce motion: camera shake off, camera smoothing off, slower edge scroll option | T |
| A-10 | Photosensitivity: no more than 3 flashes per second; superweapon/impact flashes limited in area x luminance; "Reduce flashing" option | automated on captured frames (luminance delta count) + V-F02 |
| A-11 | Game speed adjustable (50-200 %, net `SPEED_PCT`) and pause always allowed in skirmish | T |
| A-12 | No time-limited UI prompt shorter than 5 s that requires input (host stall prompt is host-only and non-blocking) | M |
| A-13 | Screen reader support for menus/lobby/settings via AccessKit: `accessibility_name` (+ description) on every interactive `Control`, live regions for lobby/chat/errors; `--accessibility auto` default; in-match RTS view is documented as not screen-reader operable | T `QaA11yAudit` (name non-empty, role sensible); M R-17 with VoiceOver/NVDA/Orca |
| A-14 | Optional announcer via `DisplayServer.tts_speak` (runtime OS voices), off by default | T |
| A-15 | High-contrast HUD: thicker selection rings, unit outlines, larger health bars | V-U03 |
| A-16 | Colour-blind presets recolour team palette and UI states | T + V-A01 |
| A-17 | Dyslexia-friendly font option (Atkinson Hyperlegible, OFL) and font-size setting; avoid long all-caps text | M |
| A-18 | Localisation-ready: strings externalised; pseudo-localisation (`TranslationServer.pseudolocalize`, verified to exist) with +40 % length shows no overflow | T `QaLayoutAudit` |
| A-19 | Alternatives to drag: select-all-on-screen, same-type double-click, control-group cycling | M |
| A-20 | Toggle vs hold: camera rotate and edge-scroll can be toggled | T |
| A-21 | Cursor size/contrast option, scales with DPI | M |
| A-22 | Assist: AI EASY level, auto-harvest (bible: collectors auto-harvest), placement hints | M |
| A-23 | Tooltips for every unit/structure/upgrade; glossary in the manual | T (DA-24) |
| A-24 | Documentation in plain Markdown, alt text on screenshots | M |

### 5.16 Bug triage process for agents
* **Severity.** S0 stop-the-line: desync/non-determinism, crash, data corruption, red tooling (T0 broken), release-blocking legal issue. S1: cannot complete a match/lobby, hangs, memory/perf regression > 1.5x budget, engine errors in normal play, unstable netcode. S2: wrong behaviour with a workaround, visual defect, balance outlier beyond the M4 band, accessibility failure. S3: polish, text, minor visual.
* **Report.** `docs/bugs/BUG-<NNNN>-<slug>.md` with front matter (7.11): id, title, severity, status, module (owner role), found_in (snapshot label, leg, tick, seed), repro (exact command), expected, actual, evidence (log excerpt, first-divergence, screenshot path), suspected cause, regression_test path, fix_snapshot, verified_by. `bugs.py new` allocates ids (max + 1, file-locked) and validates; `bugs.py index` regenerates `docs/bugs/INDEX.md`; `bugs.py check` (in T1) fails on malformed files, S0/S1 older than their SLA, `CLOSED` without an existing regression test (S0-S2), quarantine entries past expiry.
* **State machine.** NEW -> TRIAGED (severity + module set within the same session/day) -> REPRODUCED (a **failing test or command exists**; for non-deterministic issues a seed/replay) -> FIXING -> FIXED (test passes, `gd check` clean, T1 green) -> VERIFIED (independent agent re-runs repro on legs A and C; for visual bugs a new review record) -> CLOSED. WONTFIX needs owner + reason.
* **Routing** (`docs/bugs/OWNERS.md`): by path prefix of the top engine-error frame or the failing test directory: `src/core` core, `src/data` data, `src/map` map, `src/sim` sim, `src/net` net, `src/ai` ai, `src/view` view, `src/ui` ui, `src/audio` audio, `src/app` app, `game/data/balance` and `docs/balance` balance, `tools/gd`, `tools/py/gdlib`, `tests/runner.gd`, `tests/test_ctx.gd`, `tests/harness/test_*`, `tools/docker`, `tools/py/export.py` tooling, `tests/harness/qa_*`, `tools/py/qa` QA. Desync section -> module: `entities orders combat zones vision production economy players` sim, `rng` core, `map` map, data hash data.
* **Rules.** Reproduce first; no fix without a failing test (except doc/typo); regression test lives in `tests/regress/test_bug_<NNNN>_<slug>.gd` and must fail on the pre-fix code; never disable or delete a failing test without a bug id; goldens are not "fixed" by regeneration unless the divergence is understood and recorded (5.3); a fix that touches another module's file is a request, not an edit (working agreement 1).
* **Determinism bugs (S0)** follow 5.2 and stop new feature work in the affected module.
* **Flaky tests are S1.** Classification: `gd test --repeat 10 --filter <id>` [QA-XR-3] (or 10 sequential runs): any failure among identical runs = flaky. Quarantine only with `game/tests/quarantine.json` entry `{id, owner, bug, since, expires}` (expiry <= 7 days); quarantined tests still run and are printed in the summary as `QUARANTINED`; max 5 at any time; 0 at milestone gates. Never "retry until green".
* **Escalation.** Two failed fix attempts or an S0/S1 older than 24 h of work -> architect/reconciler with bisect data: restore consecutive `gd snapshot` archives into temp dirs and run the repro on each (`tools/py/qa/bugs.py bisect <repro-cmd>`), reporting the first bad snapshot.
* **Budgets at gates.** M2: 0 S0/S1, <= 10 S2. M3: 0/0, <= 8. M4: 0/0, <= 5. M5: 0/0, <= 3. M6: 0 S0/S1/S2 for 72 h, <= 10 S3 listed in KNOWN_ISSUES.
* **Agent report line** (added to the ARCHITECTURE 13.7 report): `bugs: opened BUG-0012(S2) ; closed BUG-0009(S1) ; quarantined none`.

### 5.17 Milestone gates and Definition of Done

**Universal phase DoD (every gate; on top of ARCHITECTURE Appendix B).** U1 `gd check` clean (0 parse errors, 0 lint violations, warnings <= recorded baseline). U2 tiers required by the gate are green on macOS; T2 legs where stated. U3 open bugs within the gate budget (5.16). U4 golden manifest verifies; every golden change has a CHANGELOG reason. U5 perf within the ratchet slack of that gate. U6 docs: the domain specs and `docs/STATUS.md` match the code; user docs for shipped features. U7 from M2: no `NOT IMPLEMENTED` stub reachable from a shipped flow (grep gate over `src/`), `TODO(module)` count reported. U8 log hygiene: zero engine errors and zero leak lines in T1. U9 a `gd snapshot <gate>` is taken and its label recorded in `docs/STATUS.md`. Task-level additions to Appendix B: new public API is referenced by a test; determinism-relevant code has a double-run test; perf-relevant code is covered by a P-scenario; cross-module needs are listed as requests.

| Gate | Objective exit criteria (all must hold) |
|---|---|
| **M0 Tooling** | (1) `tools/gd` check/test/run/shot/linux/snapshot/docs work, the concurrency proof passes and the runner's false-green protections are verified (tooling). (2) Engine canary golden committed and equal on legs A, B, C. (3) Kernel-math tests of sim_core (SC-01..SC-03: `test_fp`, `test_sim_rng`, `test_checksum`, `test_int_grid`, `test_spatial_hash`) pass on legs A and C with `Fp.self_test() == []` on A, B, C; QA's `test_qa_time_conversion` pins the integer-ms -> ticks rule (6 s at -20 % = 96 ticks, 10.1). (4) `ci.py run T0` completes in <= 2 min; `logscan.py` and `golden_manifest.py verify` are in T0; runner `--exclude` exists or the `ci.py` fallback works; `check_sim_rules.py` passes its seeded-violation fixtures. (5) `export.py export all` produces three outputs; host smoke prints `MERIDIAN_BOOT`; PE/ELF header checks pass for the cross-built outputs. (6) `validate_reference.py`, `balance_calc.py validate`, `validate_balance.py --strict` green; DA-01..DA-05. (7) domain specs reconciled (including risk R30), `docs/AMENDMENTS.md` exists. (8) QA harness core (`QaCli`, `QaLogGuard`, `QaTemp`, `QaChain`, `QaGolden`, `QaCanary`, `QaCalibrate`) and the `QaWorld`/`QaAssert` skeleton have tests. |
| **M1 Headless sim skirmish** | (1) `match_runner` completes D01 (napc.vanilla vs def.vanilla, 6,000 ticks) and a full napc.vanilla vs def.vanilla AI match to victory or the 24,000-tick cap, both with exit 0, zero errors, `--twin` equal and replay verify OK. (2) D00 (sim_core golden: S-CORE-1 + five fuzz games) equals `golden/sim_core.json` and is equal across legs A, B, C; chains D01-D03 are committed and equal on A, B, C. (3) Sim kernel (SC-01..SC-13) and systems 1-11 implemented for the 8 vanilla rosters' T1 units; all domains' unit tests >= 600 and scenario tests >= 150; API-reference coverage >= 70 %. (4) PS0 (kernel floor) within budget; PS1 and PS3 measured and <= 2.0x budget; throughput >= 10x real time. (5) AI preset `pr` 6/6 within the ai.md thresholds and HC1-HC8 (the `qa` block present). (6) F-CMD-1/2 clean at 2 k iterations and net's decoder fuzz green. (7) data gate green for the 8 vanilla rosters incl. oracle DA-20. (8) net L1 tests green; N0-N2 green (fake sim allowed). (9) three consecutive in-process matches return to the object/memory baseline (HC6 teardown). |
| **M2 Vertical slice (one faction)** | (1) Boot -> menu -> skirmish setup -> match vs AI -> result screen -> menu -> quit through the UI only, on macOS (Metal) and the Linux container (lavapipe); 10-shot script reviewed all-pass. (2) N0-N9 green; a real two-machine LAN match of 20 minutes without `desync_detected` (R-14). (3) >= 12 visual cases reviewed all-pass on macOS, HUD at 1280x720 and 1920x1080. (4) PS1 <= 1.5x budget; PV1 frame p95 <= 12.5 ms on RM; load times <= 1.5x budget; <= 5 hitches (> 33 ms) in the first minute. (5) D00-D05 equal on legs A, B, C, F; one green leg-E run. (6) logs written and rotated in an export; sentinel/crash-report/settings-recovery tests green. (7) QA export presets run `--qa=canary` and `--qa=match` equal to leg A. (8) AI preset `smoke` 28/28. (9) README draft and generated CONTROLS.md; `licenses.py build` runs (audit warnings allowed). (10) A-01..A-06 pass. (11) 0 S0/S1, <= 10 S2. |
| **M3 All factions data-complete** | (1) Data gate fully green (validators strict + oracle DA-20 for all 32 rosters, DA-01..DA-30); the 3 unresolved domains resolved (V-MOD-05) and the 3 conditional modifiers implemented. (2) CONTENT plan 32/32 rosters pass; union coverage 156 units, 29 structures, 40 research, 48 powers, 8 superweapons = 100 %; waivers documented. (3) AI preset `nightly` (1,488 + ladders + FFAs): HC 100 %, timeouts <= 35 %; QA `rotation` 96/96 in the Debian container. (4) the 3 conditional modifiers have two-way scenario tests. (5) every unique unit has recipe, icon, strings, sounds (DA-23). (6) PS1-PS6 <= 1.25x budget. (7) deep fuzz (200 k) clean for every target. (8) D00-D07 equal on legs A, B, C, F, E. |
| **M4 Balanced + AI** | (1) AI preset `weekly` in two consecutive runs with different epochs: HC1-HC8 100 %, batch composition 5.4.6 satisfied, stuck <= 2 %, timeouts <= 20 %. (2) balance conformance rows all pass or waived. (3) AI ladders at the ai.md 10.5 thresholds (Hard beats Medium >= 85 %, Medium beats Easy >= 85 %, Brutal beats Hard >= 65 %, start-slot bias <= 55/45). (4) faction identity timings (first scout/tank/AA/siege/superweapon, salvage share of income, warning-window damage escaped, Tempest AA losses, Dragonfall assembly survival, Trident charges spent - the bible `prototype_priorities`) reported in `docs/balance/` and inside the balance windows +-25 %. (5) ENDURANCE x3 green. (6) all budgets at 1.0x; PS2 p99 <= 22 ms; AI CPU within ai.md. (7) N0-N16 all pass incl. N14, N15. (8) 0 S0/S1, <= 5 S2. |
| **M5 Polish** | (1) >= 60 visual cases all-pass (waivers with reason), V-IP1/V-ID1 pass. (2) A-01..A-24 pass or waived; screen-reader smoke with VoiceOver, NVDA and Orca. (3) floor-hardware run: 1080p Low >= 60 FPS p95 in a PV1-class scene on a physical 2019-class machine (description recorded), < 1 % frames > 33 ms. (4) load budgets met, hitches <= 3. (5) 3 x 60-minute rendered 8-player matches (macOS + Linux GPU) with zero crashes/errors, memory within budget. (6) audio mix + captions; pseudo-localisation shows no overflow. (7) `NOT IMPLEMENTED` grep = 0 in shipped flows. (8) USER_MANUAL, generated FACTION_GUIDE, CONTROLS complete drafts. (9) both Wayland and X11 sessions verified on Debian 12 and 13. (10) 0 S0/S1, <= 3 S2. |
| **M6 Release candidate** | (1) T0-T4 green twice, 48 h apart, on the release snapshot. (2) all packages built reproducibly (double build identical hashes for zip, tar.gz, deb), `verify_release.py` green, lintian 0 errors, clean installs on Debian 12 and 13, Windows and macOS install tests done (R-01..R-04). (3) licence audit green (`licenses.py audit`, DA-26..28), project licence recorded, credits complete. (4) docs final, KNOWN_ISSUES lists all open S3. (5) 72 h freeze with 0 open S0/S1/S2, <= 10 S3. (6) manual checklist R-01..R-24 signed. (7) `SHA256SUMS.txt` produced, version stamped everywhere, `gd snapshot release-<ver>` recorded. |

Rule/scenario tests owned by other domains that gate M3 (QA verifies they exist and pass, never re-implements them): economy `test_prod_queue` (5 enqueues OK, 6th `QUEUE_FULL`; T2 unit at 30 % with Radar destroyed -> `PAUSED_PREREQ`, progress unchanged for 200 ticks), power-shortage speed 50 %, build radius 8, progressive payment; combat TTK/armor/interception/suppression tests; abilities detector 5 cells, transport capacities, superweapon geometry, zone semantics; data `test_data_*`; ai S1-S13; net S1-S20.

**Manual checklist (R-nn; each records machine, OS build, date, result).** R-01 Windows 10 clean VM: unzip, SmartScreen path, 10-minute match. R-02 Windows 11: same + firewall prompt when hosting. R-03 macOS latest, clean user: quarantined zip, Open Anyway path, `/Applications`, 10-minute match. R-04 macOS Intel slice under Rosetta: launch smoke. R-05 Debian 12 GNOME Wayland: `.deb` install, play, remove. R-06 Debian 12 X11 (Xorg) session. R-07 Debian 13: `.deb` install and play. R-08 tar.gz on Debian without root. R-09 GPU matrix (Intel iGPU, AMD, NVIDIA proprietary, Apple Silicon): launch + 10 minutes + V-B01. R-10 floor-hardware performance run. R-11 multi-monitor, DPI change, fullscreen toggles. R-12 audio device hot-swap and no-device start. R-13 sleep/wake and lid close during a LAN match. R-14 real LAN: mac + Windows, mac + Debian: discovery, join by IP, 20-minute match, pause, drop, replay. R-15 8-player LAN (VMs allowed) 20 minutes. R-16 firewall on/off behaviour and messages. R-17 screen-reader smoke. R-18 AZERTY/QWERTZ/Dvorak. R-19 trackpad-only macOS. R-20 uninstall keeps user data; documented "delete user data" path works. R-21 forced crash (QA build hotkey) writes a report; unclean-exit toast next start. R-22 corrupt settings recovery. R-23 pseudo-localisation pass. R-24 a fresh agent follows README/USER_MANUAL from scratch and lists gaps.

### 5.18 Documentation deliverables (outlines; generators marked G)
* **`README.md`**: (1) title, tagline, screenshot; (2) what it is (8 factions x vanilla + 3 subfactions = 32 rosters, skirmish vs AI, LAN 2-8 players, replays); (3) requirements (OS versions, CPU/GPU/RAM/disk, network); (4) download and install per OS incl. unsigned-app steps (5.13); (5) quick start; (6) LAN quick guide (ports UDP 27614 and 27615-27624, firewall); (7) documentation links; (8) build from source (Godot 4.7.2, `tools/gd`, export, tests); (9) project layout and pointer to `docs/ARCHITECTURE.md`; (10) contributing (working agreements, DoD, bug process); (11) licence statement per 5.11 (pending until decided) and credits pointer; (12) where logs live and how to report a bug; trademark disclaimer ("inspired by classic base-building RTS games").
* **`docs/USER_MANUAL.md`**: 0 quick start; 1 installing and first launch (per OS); 2 requirements; 3 main menu; 4 skirmish setup (roster choice, map family/size, players/teams, AI level, rules: start credits 7,500, unit cap 150, fog, superweapons, speed); 5 the battlefield (camera, selection, orders, HUD: sidebar tabs, minimap, credits/power, selection panel); 6 building a base (HQ, 8-cell build radius, placement, power and shortage, refineries and collectors, salvage, tech tiers, producers and queues of 5, research, rally, repair/sell); 7 combat (roles, damage types and armor, transports, air, naval, detection, suppression, smoke, EMP); 8 support powers and superweapons; 9 factions (G from data); 10 LAN multiplayer (host, join, discovery, manual IP, firewall, lobby, pause, stalls, dropping, desync dialog); 11 replays; 12 settings (video, audio, controls, gameplay, accessibility); 13 troubleshooting (logs and crash reports locations per OS, safe mode/renderer fallback, clearing caches, known issues); 14 glossary; 15 credits and licences.
* **`docs/CONTROLS.md` (G)**: `controls_dump.gd` writes `UiBindings` as JSON; `gen_controls_md.py` renders tables by context (Global, Camera, Selection, Orders, Production/Sidebar, Control groups, Chat/Net, Replay) with columns Action / Windows+Linux / macOS / Notes, plus a printable cheat-sheet. CI fails when the committed file differs from regeneration.
* **`docs/FACTION_GUIDE.md` (G)**: per faction: motto, identity, opening and counterplay (bible fields), vanilla roster table (unit, tier, cost, build time, role tags from resolved data), structures, research, powers, superweapon, and for each subfaction the delta (replacements, removed units, modifiers text).
* **`docs/KNOWN_ISSUES.md` (G from open bugs S2/S3 with workaround)**, **`docs/RELEASE_NOTES_<ver>.md`** (from golden/perf/bug CHANGELOGs), **`CREDITS.md` / `LICENSES/` (G by `licenses.py`)**, **`docs/QA_MANUAL_TEST_PLAN.md`** (R-01..R-24 with result tables).

### 5.19 How the bible rules in this domain are honoured
| Bible rule | QA mechanism (owner of the implementation in brackets) |
|---|---|
| `null` = unspecified, never zero/free/instant | data V-CMP-04 (required fields where the bible is null), V-CNF-01 (balance never overrides a non-null bible value), V-RNG-03; QA pins the outcome in T0 (DA-04) |
| Layering `base x prod(1 + sum/100)`, floors 60 % / 60 % / 50 %, resistance cap 50 %, no same-source stacking, build time -20 % = x0.80 | data 5.5 (bp model, `V-MOD-09`, floors via `DefStatMath.clamp_stat`) + QA tolerance oracle DA-20 and float-trap sweep DA-21 |
| Service units excluded from combat modifiers; modifier scope | data V-MOD-10, V-ROLE-05 (allowed set pinned by test) |
| Tier rules (Radar -> T2, Radar + Laboratory -> T3), producers required, land-only playability, no Dock needed for land/air tech | data V-TIER-01..04 + QA content bot (5.5.1) + invariant `TECH_PREREQ` |
| One queue per Barracks/Factory/Airfield/Dock, one research queue, one construction queue, queue length 5, replaced unit cannot also be built | invariant `QUEUE_LEN`; economy `test_prod_queue`; data V-ROS-03 |
| Research 45 s (T2) / 75 s (T3) = 900 / 1,500 ticks, losing a prerequisite pauses dependent orders, completed upgrades persist | data conversion (`ceil_div`), economy tests, content bot |
| Power shortage: production/research at 50 %, powered defenses stop, powered powers cannot activate, superweapon recharge pauses | economy/abilities tests, invariant `POWER_MISMATCH`, balance target `power_first_shortage_after_s = 240` |
| Start preset HQ + 7,500 credits, medium speed, no veterancy | `QaMatchSpec.rules` defaults; scenario test of the initial state of all 32 rosters |
| Exactly 3 powers per roster; T2/T3 powers need powered Radar/Laboratory; superweapon starts empty, one stored charge, recharge starts at activation | data V-ROS-04, content bot, D06 |
| Damage and area notation, friendly fire, interception (8 charges halve an impact packet), concealment (5-cell detection), suppression (3 hits in 2 s, -25 % for 3 s), transport capacities (2 squads; Okapi 3; Leviathan 4), submarine surfacing (8 s) | combat/abilities scenario tests (listed under the M3 gate); D06 exercises the strategic ones |
| Three unresolved target domains, three conditional modifiers | data V-MOD-05 / V-MOD-07 / V-MOD-08 + QA two-way scenario tests (5.5.1) |
| `prototype_priorities` (timings, salvage share, warning-window damage, Tempest losses, Dragonfall survival, Trident charges, disabled duplicate fields/repair stations/decoy income) | `AiMetrics` (ai.md) + `QaEventStats.firsts()`; M4 criterion 4; data V-ROS-08 (replacements do not keep both abilities) |
| Three map families, >= 2 exits, no mandatory water for baseline economy | DA-29 + rotation/nightly cover all three families |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

QA introduces no gameplay state. Its "commands" are (a) job command lines and their result protocol, (b) extra modes of the replicated **`DEBUG` sim command** used only by tests, (c) one **local** (non-replicated) helper, `QaCorrupt`, which needs no sim change, and (d) the sim commands and events it consumes.

### 6.1 Jobs, protocol lines and exit codes
| Job (`QaCli.dispatch`) | Entry script | Key args | Protocol lines (stdout, one per line, JSON payload) | Exit codes used |
|---|---|---|---|---|
| `match` | `match_runner.gd` | 5.4.1 | `QA_START`, `QA_PROGRESS`, `QA_RESULT` (7.2) | 0 OK, 1 criteria failed, 2 usage, 3 engine errors, 4 wall limit, 5 chain mismatch (`--chain-in`) |
| `replay_verify` | `replay_verify.gd` | `--replay=<path> [--chain-in=<path>] [--max-ticks=N] [--diff-against=<path>]` | `QA_RESULT {ok, ticks, compared, first_mismatch_tick, final_checksum}` | 0, 5 (mismatch), 2, 3 |
| `canary` | `canary_dump.gd` | `--compare` (default) / `--write=<path>` / `--calibrate` | `QA_RESULT {lines:28, ok, calib:{ms,factor,ok}}` | 0, 5 (diff vs golden), 3 |
| `simcore` | `simcore_dump.gd` | `--compare` (default) / `--write=<path>` | `QA_RESULT {lines, ok}`; `HASH tick=<n> <hex8>` lines for S-CORE-1 and for each of the five fuzz games (job D00, 5.2) | 0, 5 (diff vs `golden/sim_core.json`), 3 |
| `perf` | `perf_bench.gd` | `--scenario=PS0..PS6,PV1..PV4 --ticks=N --warmup=N --json=<path> --update-baseline` | `QA_RESULT {scenario, stats, breaches[]}` | 0, 1 (budget breach), 6 (PV* without a window) |
| `fuzz` | `fuzz_runner.gd` | `--target=commands/packets/files/all --seed=N --iters=N --json=<path>` | `QA_RESULT {ok, iterations, failures[]}` (failure objects contain a replayable input) | 0, 1 |
| `data_audit` | `data_audit.gd` | `--strict --json=<path>` | `QA_RESULT {ok, checks_run, errors[], warnings[]}` | 0, 1 |
| `export_smoke` | `export_smoke.gd` / `--qa=export_smoke` | `--manifest=<path>` | `QA_RESULT {checked, missing[]}` | 0, 1 |
| `license_dump` | `license_dump.gd` | `--out=<path>` | `QA_RESULT {licences, components}` | 0 |
| `controls_dump` | `controls_dump.gd` | `--out=<path>` | `QA_RESULT {actions}` | 0 |
`gd`'s own codes pass through unchanged: 124 = timeout/stall kill; 3 also results when Godot exits 0 but printed engine error lines. QA jobs therefore reserve 3 for "engine errors" and never reuse it. Other domains' entry points keep their own protocols and are only orchestrated by QA: `ai_soak_main.gd` (exit 0 pass / 1 regression / 2 harness error, `AISOAK_BEGIN/END`), `net_harness.gd` (`NETTEST` lines), `data_cli.gd` (`--validate`, `--hash`, `--dump`), `validate_balance.py` (0/1/2/3).

### 6.2 Debug modes of the replicated `DEBUG` command (sim_core opcode `0x0F`)
sim_core's MASTER catalog (6.1 there) defines `DEBUG` with wire fields `MODE, DEF, COUNT, X, Y`; it is refused unless `SimMatchRules.allow_debug = 1` (default 0; part of the rules stream mixed into `config_hash` and the `world` checksum section, so every peer must agree; net's lobby never sets it, net XR-10) and it lists modes 1 and 2. QA needs four more modes and one more field. All modes act for the *issuing* pid (`cmd.pid`), are recorded in replays like any command, and are refused (no state change, `Err != OK`) when `allow_debug = 0`.
| Mode | Name | Fields | Semantics |
|---|---|---|---|
| 1 | `GRANT` (sim_core) | COUNT | `add_credits(pid, COUNT, CASH_SCRIPT)`; negative allowed, credits clamped at 0 |
| 2 | `SPAWN` (sim_core; QA asks for exact placement) | DEF, COUNT, X, Y | spawn COUNT of DEF for the issuer; units on a deterministic square spiral of free cells around (X, Y) (ring by ring, row-major inside a ring); a structure def uses `spawn_structure` at that cell (COUNT must be 1); ignores cost, prerequisites and the unit cap; refused if the def cannot exist on that layer |
| 3 | `KILL` (requested) | TARGET | `kill(entity(TARGET), 0, DIE_SCRIPT)` through the normal death path (event, wreck rules) |
| 4 | `REVEAL` (requested) | COUNT | 1 = reveal the whole map to the issuer, 0 = restore normal vision (vision domain) |
| 5 | `SET_HP` (requested) | TARGET, COUNT | set health, clamped to `1..max_hp` |
| 6 | `CHARGE` (requested) | COUNT | bit0 = superweapon fully charged and READY, bit1 = all support-power cooldowns reset (`power_ready_at = 0`) |
The wire schema becomes `MODE, TARGET, DEF, COUNT, X, Y` (adds the `TARGET` field, code 1; `WIRE_VERSION` stays 1 while nothing has shipped) [QA-XR-17]. X/Y of `DEBUG` are exempt from the map-bounds check (sim_core 5.5) and the spawn mode clamps into the map.

### 6.3 Local (non-replicated) test helper `QaCorrupt` - no sim change needed
A replicated command executes identically on every peer, so it can never *cause* a desync; desync-detection tests must mutate ONE peer. Sim state is public GDScript state, so `QaCorrupt.apply(world, section, value)` does it from the harness without any hook in the sim: section 0 `world` (`world.next_proj_id += value`), 1 `rng` (draws `value` numbers from `world.rng`), 2 `players` (`players[0].credits += value`), 3 `entities` (`hp` of the lowest-id live entity changed by `value`, never below 1). The next checkpoint (<= 20 ticks later) then differs from the other peers in exactly that section of `report_at(tick).sections`, which is what the desync package must name. It is called only by net's `net_harness.gd --corrupt-at=<tick>:<section>:<value>` [QA-XR-26] and by QA tests, and refuses unless `OS.has_feature("qa")` or `OS.is_debug_build()`. Coverage of the `map` and `sys.*` sections is proven by the owning domains' `check_hash_coverage` tests (sim_core 8.3), whose existence `test_qa_hash_coverage_meta` verifies.

### 6.4 Sim commands and events QA consumes (by NAME; numbers are the owning domain's authority)
QA never hard-codes command numbers (`DEBUG 0x0F` is the only opcode named in this spec). `QaSimAdapter.cmd(name, fields)` builds a `SimCommand` from the MASTER-catalog name (sim_core 6.1) and named fields; economy.md's `CMD_*` names are accepted as aliases (`CMD_TRAIN` = `PRODUCE`, `CMD_BUILD_START` = `BUILD`, `CMD_BUILD_PLACE` = `PLACE`, `CMD_RESEARCH` = `RESEARCH`, `CMD_USE_POWER` = `USE_POWER`, `CMD_LAUNCH_SUPERWEAPON` = `LAUNCH_SW`, `CMD_SET_RALLY` = `SET_RALLY`, `CMD_SELL` = `SELL`, ...). The catalog has 40 opcodes: core `PAUSE UNPAUSE RESIGN PLAYER_DROP DEBUG`; orders `MOVE ATTACK_MOVE ATTACK FORCE_FIRE STOP GUARD SCATTER PATROL DEPLOY ABILITY LOAD UNLOAD GARRISON CAPTURE REPAIR SALVAGE HARVEST RETURN_CASH SET_STANCE RETURN_TO_BASE SCUTTLE SET_RALLY`; production `PRODUCE CANCEL_PRODUCE HOLD_QUEUE BUILD CANCEL_BUILD PLACE SELL TOGGLE_REPAIR RESEARCH CANCEL_RESEARCH DEPLOY_MCV`; powers `USE_POWER LAUNCH_SW`. Scenario D05 issues **all 39 non-system ops** (`PLAYER_DROP` is host-only and is covered by net cases N3, N11 and N13); `test_qa_d05_covers_catalog` compares the script with the op table of `SimCommand` so a newly added op cannot be forgotten.
Read-only economy queries used by the content bot (economy.md, published): `q_buildable_structures`, `q_buildable_units`, `q_researchable`, `q_find_producer`, `q_stats`, `q_income_per_minute`, `q_can_rebuild`, `has_active_hq`, `can_queue_structure/unit/research`, `SimPlacement.find_site` (spiral, first valid, <= 400 probes) and `SimPlacement.validate`; sim_core's own queries (`units_of`, `structures_of`, `players[pid].owned/powered/research_done`, `unit_cap_room`, `find_idle_units`) cover the rest.
Events (normalised in 4.3) are exclusively those of the sim_core MASTER catalog; QA needs no additional event and emits none. **Emitted by QA:** protocol lines only (6.1); nothing enters the sim except the `DEBUG` modes above, and only in test matches.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

All JSON: UTF-8, LF, 2-space indent, keys sorted (`JSON.stringify(v, "  ", true)`), final newline, no numbers above 2^53 (hashes are hex strings).

### 7.1 Scenario fixture `game/tests/fixtures/scenarios/D01.json`
```json
{
  "id": "D01", "version": 1,
  "description": "economy + ground combat baseline (ai 1 = Medium)",
  "players": [
    {"roster": "roster.napc.vanilla", "team": 0, "ai": 1, "style": 0},
    {"roster": "roster.def.vanilla",  "team": 1, "ai": 1, "style": 0}
  ],
  "map": {"family": 0, "size": 96, "seed": 1},
  "sim_seed": 1,
  "rules": {"start_credits": 7500, "unit_cap": 150, "fog": true, "superweapons": true},
  "fixed_delay": 1,
  "ticks": 6000,
  "script": "",
  "golden_chain": "chains/D01.chain"
}
```
### 7.2 `QaMatchResult` v1 (`--result`, and the `QA_RESULT` line)
```json
{
  "version": 1, "completed": true, "ok": true, "exit_code": 0, "stop_reason": "victory",
  "engine": "4.7.2-stable",
  "platform": {"os": "macOS", "arch": "arm64", "cpu": "Apple M5 Max", "leg": "A", "calib_ms": 294, "calib_factor": 1.0},
  "spec": {"players": [{"roster": "roster.napc.canada", "team": 0, "ai": 2}, {"roster": "roster.han.china", "team": 1, "ai": 2}],
           "map_family": 2, "map_size": 128, "map_seed": 20260929, "sim_seed": 20260929, "max_ticks": 24000},
  "sim_version": 1, "data_hash": "1a2b3c4d", "map_hash": "0badf00d",
  "ticks": 13842, "outcome": {"winner_team": 0, "defeated": {"1": 13842}},
  "final_checksum": "9f3a1c02", "final_chain": "5be07a11",
  "timing_us": {"mean": 2410, "p50": 2200, "p95": 3900, "p99": 5200, "max": 9100, "total_ms": 33360,
                "by_system_mean": {"command": 40, "production": 120, "economy": 90, "power": 30, "order": 260, "movement": 820,
                                   "ability": 110, "combat": 700, "zone": 40, "vision": 150, "cleanup": 50}},
  "memory": {"static_start_kb": 23537, "static_after_warmup_kb": 41200, "static_end_kb": 47100,
             "objects_start": 1481, "objects_end_after_close": 1490, "peak_entities": 1412, "orphans_start": 1, "orphans_end": 1},
  "log": {"errors": 0, "warnings": 2, "leaks": 0, "samples": []},
  "invariants": {"checked": 138, "violations": []},
  "twin": {"enabled": true, "ok": true, "compared": 692},
  "players": [
    {"pid": 0, "roster": "roster.napc.canada", "won": true, "units_built": 57, "units_lost": 31, "kills": 44,
     "structures_built": 18, "structures_lost": 4, "credits_earned": 41200, "credits_spent": 40100,
     "first_s": {"scout": 41.0, "tank": 118.5, "aa": 190.0, "siege": 611.0, "superweapon": -1.0}}
  ],
  "coverage": {"units": ["unit.napc.guardian_tank"], "structures": ["structure.shared.refinery"], "research": [], "powers": [], "superweapons": []},
  "stuck": {"flagged": 0, "movers_sampled": 5310, "stall_windows": 0},
  "replay": {"path": "builds/qa/2026-09-29/m0007.mfreplay", "sha256": "e3b0c442..."}
}
```
### 7.3 Chain file `game/tests/golden/chains/D01.chain` (text; one triple per checksum snapshot = every 20 ticks)
```
# meridian chain v1 scenario=D01 engine=4.7.2-stable sim_version=1 data_hash=1a2b3c4d
# columns: tick checksum input_chain   (checksum and input_chain are u32, lowercase hex, 8 digits)
0 4f1c2ab0 811c9dc5
20 9a03bb17 2c77d0e4
40 1e88a5c3 7d1f00b9
```
### 7.4 Scripted commands `game/tests/fixtures/scripts/*.cmds.json`
```json
{"version": 1, "commands": [
  {"turn": 0,  "pid": 0, "op": "DEBUG",   "mode": 1, "count": 100000},
  {"turn": 2,  "pid": 0, "op": "BUILD",   "def": "structure.shared.generator", "count": 1},
  {"turn": 40, "pid": 0, "op": "PLACE",   "def": "structure.shared.generator", "cell": [52, 47]},
  {"turn": 60, "pid": 0, "op": "PRODUCE", "target": {"def": "structure.shared.barracks", "nth": 0}, "def": "unit.napc.rifle_squad", "count": 1},
  {"turn": 90, "pid": 0, "op": "MOVE",    "ids": {"def": "unit.napc.rifle_squad", "n": 4}, "cell": [60, 50]}
]}
```
`op` is a MASTER-catalog name (6.4) and the other keys are the `SimCommand` fields (`ids, target, def, x, y, angle, count, mode, flags`). Bible ids in `def` are resolved to def indices by the adapter. `ids` and `target` take raw entity ids or a **selector** `{"def": <bible id>, "n": <count, default all>, "nth": <index>}` resolved when the command is issued against the issuer's live entities in ascending id order (ids are deterministic but cannot be known when a script is written). `cell: [cx, cy]` sets `x, y` to the cell centre `(c << 10) + 512`, except for `PLACE` where it is the footprint's top-left cell corner `c << 10` as the op requires; `pos: [x, y]` gives raw sub-cell units. `turn` is the issue turn (execution = turn + delay; net's harness injects when `exec_turn == cmd.turn - D - 1`); commands sort by (turn, pid, file order) exactly as net orders a bundle (pid ascending, then issue order). Net's own scripts (`game/tests/net/scripts/*.json`, net.md 7.6) use the same idea; `match_runner` accepts either format.
### 7.5 UDP impairment profiles `tools/py/qa/impair_profiles.json`
```json
{"profiles": {
  "lan":       {"latency_ms": 0.5, "jitter_ms": 0.3, "loss_pct": 0, "dup_pct": 0, "reorder_pct": 0, "bandwidth_kbps": 0},
  "wifi":      {"latency_ms": 10,  "jitter_ms": 8,   "loss_pct": 1, "dup_pct": 0, "reorder_pct": 0, "bandwidth_kbps": 0},
  "bad_wifi":  {"latency_ms": 30,  "jitter_ms": 25,  "loss_pct": 3, "dup_pct": 0, "reorder_pct": 0, "bandwidth_kbps": 0},
  "awful":     {"latency_ms": 150, "jitter_ms": 60,  "loss_pct": 4, "dup_pct": 0, "reorder_pct": 0, "bandwidth_kbps": 0},
  "raw_chaos": {"latency_ms": 20,  "jitter_ms": 15,  "loss_pct": 2, "dup_pct": 3, "reorder_pct": 10, "bandwidth_kbps": 0},
  "capped":    {"latency_ms": 20,  "jitter_ms": 5,   "loss_pct": 0, "dup_pct": 0, "reorder_pct": 0, "bandwidth_kbps": 64},
  "blackout3": {"latency_ms": 5,   "jitter_ms": 2,   "blackouts": [[10.0, 13.0]], "direction": "c2s"},
  "blackout45":{"latency_ms": 5,   "jitter_ms": 2,   "blackouts": [[10.0, 55.0]], "direction": "both"},
  "corrupt1":  {"latency_ms": 5,   "jitter_ms": 2,   "corrupt_pct": 1}
}, "seed_default": 1}
```
Names and numbers mirror net's `NetFaultProfile` presets so L1 (virtual time) and L2 (real UDP) results are comparable; the proxy applies each impairment per datagram and per direction with a seeded `random.Random`.
### 7.6 Visual cases `game/tests/visual/cases.json` and checklist item
```json
{"version": 1, "cases": [
  {"id": "VC-012", "title": "NAPC base at T3, coast map, 1080p Medium", "category": "structure",
   "scenario": "fixtures/scenarios/vc_napc_t3.json", "ticks": 4800,
   "camera": {"cell_x": 52, "cell_y": 47, "yaw": 30, "pitch": 55, "zoom": 1.0},
   "ui": {"scale": 1.0, "hud": true, "colour_mode": "normal"}, "quality": "medium", "size": "1920x1080",
   "renderer": "forward_plus", "always_review": false,
   "checks": ["V-S01", "V-U02", "V-H01", "V-B01", "V-IP1", "V-ID1"]}
]}
```
`checklist.json` item: `{"id": "V-S02", "category": "structure", "strict": true, "statement": "placement ghost valid/invalid is distinguishable without colour", "applies_to": ["structure", "hud"]}`.
### 7.7 Visual review record `game/tests/visual/review/VC-012.json`
```json
{"case_id": "VC-012", "platform": "macos-arm64-metal", "image": "builds/qa/2026-09-29/visual/macos-arm64-metal/VC-012.png",
 "reviewer": "agent:qa-visual", "author_of_change": "agent:view", "date": "2026-09-29", "auto": {"VA-1": "pass", "VA-2": "pass", "VA-4": "changed", "psnr": 36.2},
 "checks": [
   {"id": "V-S01", "verdict": "pass", "note": "Refinery and radar footprints sit inside their placement squares; scaffolding visible on the barracks under construction."},
   {"id": "V-U02", "verdict": "fail", "note": "Team colour 5 (teal) and 6 (green) tanks near the lower right are hard to tell apart; no pattern cue on the turret ring."}],
 "overall": "fail", "bugs": ["BUG-0042"]}
```
### 7.8 `game/data/text/credits.json`, `LICENSES/THIRD_PARTY.json`, audio `PROVENANCE.json`
```json
{"version": 1, "sections": [
  {"title": "Engine", "entries": [{"name": "Godot Engine 4.7.2", "license": "MIT", "link": "licenses:godot"}]},
  {"title": "Fonts",  "entries": [{"name": "Rajdhani", "author": "Indian Type Foundry", "license": "OFL-1.1", "link": "licenses:font/rajdhani"}]},
  {"title": "Audio",  "entries": [{"name": "Kokoro-82M (voice lines)", "license": "Apache-2.0", "link": "licenses:audio/kokoro"}]}]}
```
```json
{"components": [{"name": "Rajdhani", "version": "1.0", "spdx": "OFL-1.1", "licence_file": "LICENSES/fonts/OFL_rajdhani.txt",
  "copyright": "Copyright (c) 2014, Indian Type Foundry", "url": "https://fonts.google.com/specimen/Rajdhani", "shipped": true, "modified": false, "used_for": "UI font"}]}
```
```json
{"files": [{"file": "game/assets/audio/voice/napc/ack_01.ogg", "sha256": "…", "generator": "kokoro-onnx 0.4.7", "model": "kokoro-v1.0.int8.onnx",
  "model_sha256": "…", "voice": "am_michael", "text": "Acknowledged.", "language": "en-us", "licence_model": "Apache-2.0",
  "licence_tools": ["MIT", "GPL-3.0-or-later (phonemizer/espeak-ng, tool only)"], "created_utc": "2026-09-29T12:00:00Z", "tool_versions": {"onnxruntime": "1.30.0"}}]}
```
### 7.9 CI tier definition `tools/py/qa/tiers.json`
```json
{"version": 1, "mirror_for": ["T1", "T2", "T3", "T4", "T5"], "tiers": {
  "T0": {"budget_s": 120, "steps": [
    {"id": "check",   "cmd": ["tools/gd", "check"]},
    {"id": "tests",   "cmd": ["tools/gd", "test", "--exclude=determinism/,fuzz/,perf/,content/,visual/"], "shards": 4},
    {"id": "bible",   "cmd": ["python3", "Input/meridian_agent_reference/validate_reference.py"]},
    {"id": "balance", "cmd": ["python3", "tools/py/balance_calc.py", "validate"]},
    {"id": "data",    "cmd": ["python3", "tools/py/validate_balance.py", "--strict"]},
    {"id": "canary",  "cmd": ["tools/gd", "run", "res://tests/harness/canary_dump.gd", "--", "--compare"]},
    {"id": "goldens", "cmd": ["python3", "tools/py/qa/golden_manifest.py", "verify"]}]},
  "T1": {"needs": ["T0"], "budget_s": 900, "steps": ["determinism", "fuzz-smoke", "perf-smoke", "ai-preset-pr", "net-N0", "replay-goldens", "bugs-check"]}
}}
```
### 7.10 Debian `control`, `.desktop` (both verified: package built, installed on Debian 12.15 and 13.7, lintian 0 errors)
```
Package: meridian-fracture
Version: 0.1.0-1
Section: games
Priority: optional
Architecture: amd64
Maintainer: Meridian Fracture Team <noreply@example.invalid>
Installed-Size: <computed, KiB>
Depends: libc6 (>= 2.28), libx11-6, libxcursor1, libxext6, libxi6, libxinerama1, libxrandr2, libxrender1, libxkbcommon0, libfontconfig1, libegl1, libvulkan1, libasound2t64 | libasound2
Recommends: mesa-vulkan-drivers | nvidia-vulkan-icd, libgl1-mesa-dri, libpulse0, libudev1, libdbus-1-3, libwayland-client0, libwayland-cursor0, libwayland-egl1, libdecor-0-0
Suggests: speech-dispatcher
Homepage: <project url once decided>
Description: Real-time strategy game with eight factions and LAN multiplayer
 Eight factions with three sub-factions each, skirmish against AI and
 deterministic lockstep LAN multiplayer.
```
The synopsis deliberately avoids the trademark "Command & Conquer" (5.11).
```
[Desktop Entry]
Type=Application
Name=Meridian Fracture
Comment=Real-time strategy game with eight factions and LAN multiplayer
Exec=/usr/games/meridian-fracture
Icon=meridian-fracture
Terminal=false
Categories=Game;StrategyGame;
Keywords=rts;strategy;lan;multiplayer;
StartupWMClass=MeridianFracture
```
### 7.11 Bug file `docs/bugs/BUG-0042-team-colours-5-6-confusable.md`
```
---
id: BUG-0042
title: Team colours 5 and 6 are confusable in the fog-edge lighting
severity: S2
status: REPRODUCED
module: view
found_in: {snapshot: m2-gate, leg: A, case: VC-012}
repro: tools/gd shot res://tests/visual/visual_case.tscn out.png --size 1920x1080 -- --case=VC-012
expected: V-U02 passes (separable colours)
actual: teal and green tanks indistinguishable at default zoom
evidence: builds/qa/2026-09-29/visual/macos-arm64-metal/VC-012.png
regression_test: game/tests/a11y/test_team_colour_delta_e.gd
fix_snapshot:
verified_by:
---
Free text: analysis, suspected cause, workaround.
```
### 7.12 Perf budgets, baseline, golden manifest, quarantine
```text
// game/tests/perf/budgets.json
{"version": 1, "reference": {"machine": "Apple M5 Max", "calib_ms": 294}, "slack": {"M1": 2.0, "M2": 1.5, "M3": 1.25, "M4": 1.0},
 "scenarios": {"PS1": {"tick_us": {"mean": 3500, "p95": 5500, "p99": 8000, "max": 12000}}, "PS2": {"tick_us": {"mean": 11000, "p95": 16000, "p99": 22000, "max": 35000}}}}
// game/tests/golden/perf_baseline.json
{"revision": 3, "scenarios": {"PS1": {"tick_us_norm": {"mean": 2650, "p95": 3900, "p99": 5100, "max": 8200}, "measured": "2026-10-14", "engine": "4.7.2-stable"}}}
// game/tests/golden/MANIFEST.json
{"revision": 7, "files": {"engine_canary.txt": "sha256:...", "chains/D01.chain": "sha256:...", "data_hash.json": "sha256:...", "convert_vectors.json": "sha256:...", "ai/baselines/ai_baseline.json": "sha256:..."}}
// game/tests/quarantine.json
{"entries": [{"id": "test_net_scenarios.gd::test_s7_freeze_quarantine", "owner": "net", "bug": "BUG-0031", "since": "2026-10-02", "expires": "2026-10-09"}]}
```
(comments shown for orientation only; the real files are pure JSON).

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

**What enters the checksum: nothing from QA.** QA owns no sim state. Effects of the replicated `DEBUG` modes (6.2) live in ordinary sim state and are therefore covered by the sim's checksum; `rules.allow_debug` is part of the `SimMatchRules` stream that sim_core mixes into `config_hash` and into the `world` section (5.10 and 8.2 there), so a peer with a different value can neither join nor replay. Goldens, chains and results are *outputs* of the checksum, never inputs.
**QA code determinism.** Anything that produces a schedule or golden is integer-only and platform-independent: `QaSoakPlan` (verified by script), `QaFuzzRng` (xorshift128; vectors 10.1), `QaChain` (masked hex), `QaCalibrate` (checksum `33451325123209`/`2054281984`). Floats/`Time` are used only for reporting.
**How each rule is enforced by tests (QA is the enforcement layer for the DR list):**
| DR | Enforcement |
|---|---|
| DR-1 ints only | L003 bans floats/Vector2/3/Color in deterministic modules; `TestCtx.eq` is type-strict (int 1 != float 1.0); canary line `json_types` documents that JSON yields floats, so the loader must convert |
| DR-2 no engine RNG | L003; fuzz F-CMD with `randi` interposition test: a test scans `src/` for RNG identifiers (already in L003) |
| DR-3 no wall clock | L003; D3d (`--time-scale 3 --fixed-fps 30`) must not change chains |
| DR-4 no float builtins | L003; canary `roundi/ceili` facts; DA-21 exactness sweep; data V-DET-01 (float scan) |
| DR-5 C integer semantics | canary lines `div_trunc, mod_sign, shr_neg, shl, wrap, mul_wrap`; `Fp` unit tests; the canary documents: arithmetic shift on negatives at runtime, shift-count masking (undefined in C++ but identical on x86_64 and arm64), 64-bit wrap, `x/0` = error + 0 |
| DR-6 iteration order | canary `dict_order`; D3(a,b) perturbation; lint heuristic for `for k in dict` in sim (warning) |
| DR-7 total-order sorts | canary `sort_ties` proves ties are scrambled; lint `SL-9` (`sort_custom` needs a `# total order:` comment) plus a comparator heuristic (warning: no `.id` tie-break) |
| DR-8 no Node/await/threads in sim | L005 + lint `SL-3` (`await`, `Thread`, `Mutex`, `call_deferred`, `Timer`, signals in `src/sim`); D3c `--single-threaded-scene` |
| DR-9 no hidden globals | D2 double-run and warm-process perturbation D3a |
| DR-10 data converted once; data hash in handshake | data V-SCH-04/V-HASH-01, DA-10 (hash parity on all legs), N16a |
| DR-11 counts not time | PS4/PS5 worst-case bursts; fuzz max-load |
| DR-12 events output-only | D3g: draining events every tick vs every 100 ticks vs never (until the end) gives identical chains |
| DR-13 checksum covers all state | sim_core's reflection test `SimTestKit.check_hash_coverage` per component and `SL-5`; QA adds `test_qa_hash_coverage_meta` (every component and stateful system class has such a test), `test_checksum_sensitivity` (mutating one public field per section - world, rng, players, entities - changes `world.checksum()` and exactly that section's digest in `report_at`) and job D00; code review rule "new persistent field => hash_into + test + SIM_VERSION" |
| DR-14 AI/UI floats confined | L005/L003 boundaries; AI output enters only as int commands (fuzz oracle) |
| DR-15 interpolation view-only | visual tests run with frozen clocks; sim chain unaffected by camera/UI (D3e windowed vs headless) |
**Engine facts relied upon (all *(verified)* on macOS arm64, macOS x86_64/Rosetta, Debian 12 amd64):** listed in 1.4 and pinned by the 28 canary lines; any divergence on any leg, or after an engine upgrade, is investigated as S0 before anything else runs.
**Replay format dependency.** Golden replays embed `sim_version` and `data_hash`; a replay whose header mismatches is *archived*, never silently accepted (5.3).

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

**Product budgets** (sim ms/tick at 400 and 1,200 entities, frame time, memory, load time, network): section 5.8 is the normative table; this spec is the acceptance authority for them and adopts the AI (ai.md 10.5) and net (net.md 9) figures for their own components. Reasoning summary: at 400 entities the *(estimate)* cost is ~3.7 us/entity x 400 = 1.5 ms + vision 0.5 + production/economy/power 0.4 + engine call overhead => ~3-3.5 ms mean on RM (budget 3.5 ms mean / 8 ms p99). The sum of the domain specs' own estimates is higher (~9 ms) only because they price a statement at 0.1-0.15 us against a measured 20-30 ns; the ratchet (slack 2.0 -> 1.0 by M4) and the R1 decision point at M2 settle the disagreement with measurements, not opinions. On a 2.6x slower CPU (leg C proxy) the 3.5 ms tick becomes 9.1 ms, which plus ~6-8 ms of rendering just fits a 16.7 ms frame on the one frame in three that runs a tick - hence the hard requirement for stride systems, SoA arrays and capped path requests.
**Kernel floor.** sim_core 9 measured on RM: an idle 1,200-unit step with all domain stages stubbed costs 0.54 ms (+0.09 ms amortised checkpoint), a checkpoint 1.8 ms, the order dispatcher with 20 % active orders 0.35 ms, `query_radius` 6.9 us (r = 4 cells) and 15.4 us (r = 8) in dense clusters; its kernel total is about 2 ms average and 6.5 ms on checkpoint ticks on the reference PC (x2.5). PS0 (4.6, budget 0.8 / 2.0 / 3.0 / 4.5 ms) turns those numbers into a regression gate, so a kernel change cannot silently eat the domains' share of the tick.
**Harness overhead (must stay <= 3 % of the measured tick, twin mode excluded):**
| Harness activity | Cost (RM, estimate) | Cadence |
|---|---|---|
| `QaMetrics.record_tick` (array write) | < 0.001 ms | every tick |
| event drain + `QaEventStats.consume` | <= 0.05 ms (at PS1 event rates) | every tick |
| chain append | < 0.001 ms | every 20 ticks |
| `validate()` (INV-1..14 + G1..G7) | <= 2.0 ms at ~1,900 entities (the full table of a busy 8-player match) | every 100 ticks (0.02 ms/tick amortised) |
| `QaStuckDetector.sample` (walks `world.units`) | <= 0.4 ms | every 100 ticks |
| `sample_memory` (3 monitor reads) | < 0.02 ms | every 100 ticks |
| twin world | +100 % CPU | only in HC3 subsets |
Memory of the harness: timing array 4 B x (max_ticks + 1) = 288 KB for 72,000 ticks; chain 3 x int64 per 20 ticks = 86 KB for 72,000 ticks; result JSON <= 200 KB; a replay <= 3 MB per match-hour (net.md).
**CI wall-time budgets (RM, 8-16 workers):** T0 <= 2 min at M0-M1 (<= 6 min from M3, 4 shards), T1 <= 15 min, T2 <= 40 min, T3 <= 3 h, T4 <= 4 h, T5 <= 8 h + manual (5.1). T1-T5 run on a frozen mirror (decision 9): mirror creation = copy of `game/` without `.godot` (~ seconds) + one import (~2 s tiny project, ~30 s cold with many scripts). Process fixed costs to batch around: native start 0.25 s; container start 1.3 s + `docker run` ~0.5 s. Workers <= cores - 2 (16 on RM); per-worker memory ~120 MB baseline + 100-300 MB match, so 16 workers need < 8 GB.
**Worst cases and mitigations.** (1) Parallel jobs racing on `user://` -> per-process `HOME` sandbox (5.6). (2) Rosetta legs 2.6x slower -> scenario lengths sized per leg, `--ticks-scale` option in `crossarch.py`; detect QEMU (`/proc/cpuinfo` model "QEMU Virtual CPU") and warn when factor > 8. (3) Screenshot runs need a window (`gd shot` positions it off-screen) - serialised on GPU hosts, at most 1 per GPU. (4) Weekly matrix stalls on a hung match -> `--wall-limit`, `gd --timeout`, and `soak.py` re-queues once (a repeated hang is S1). (5) Disk: replays and results ~4 MB per match x 1,488 = 6 GB per nightly run (12 GB weekly) -> retention: keep failures and every 10th replay; results JSON always.

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

Files are under `game/tests/<kind>/`; ids are `<kind>/<file>::<method>`. "Leg" = 4.5. Expected values below were computed or measured on 2026-09-29 (macOS arm64; canary and calibration also on legs B and C).

### 10.1 Harness unit tests (`tests/qa/`, tier T0)
| Test | Expected values |
|---|---|
| `test_qa_fuzz_rng::test_vectors` | `from_seed(1)`: state `[0x3c88596c, 0x5e8885db, 0x8116017e, 0xb4733ac5]`, first five `next_u32()` = `3394131486, 3505566929, 3789439552, 3428247980, 1947248798`; `from_seed(12345)` -> `1872748884, 2291328150, 1634147168, 2341992395, 462566060`; `from_seed(0xDEADBEEF)` -> `213958346, 2975023483, 4092125211, 3529959500, 3680053796`; `below(n)` always `< n` over 10,000 draws for n in {1, 2, 3, 1000, 2^31 - 1}; same seed twice gives identical streams |
| `test_qa_chain::test_hex` | `hex32(-1)="ffffffff"`, `hex32(0x1234ABCD)="1234abcd"`, `hex32(0)="00000000"`; `hex64(-1)="ffffffffffffffff"`, `hex64(0x123456789ABCDEF0)="123456789abcdef0"`, `hex64(-9223372036854775807 - 1)="8000000000000000"`, `hex64(0)="0000000000000000"` (the naive `"%x" % -255` yields `"-ff"` - test documents it) |
| `test_qa_chain::test_roundtrip_and_divergence` | write/read 3 triples equal; identical chains -> `tick == -1`; chains equal except checksum at index 3 -> `tick == 60`, reason `"checksum"`; equal checksums but different input_chain -> reason `"chain"`; shorter chain -> reason `"length"` |
| `test_qa_calibrate::test_checksum` | `run()` returns `acc == 33451325123209`, `s3 == 2054281984`, `ok == true` on every leg; `ms > 0`; `factor >= 1.0`; `ms` is printed as a note (294 on A, 440 on B, 767 on C at the time of writing) and never asserted |
| `test_qa_time_conversion::test_exact_vs_float` | reference `ms_to_ticks(ms) = (ms * 20 + 999) / 1000`: `(1)=1, (50)=1, (51)=2, (45000)=900`; 6 s at -20 % -> `6000 * 80 / 100 = 4800` ms -> **96**, while `ceili(6.0 * (1.0 + (-20) / 100.0) * 20.0)` = **97** (test asserts both, documenting the trap); sweep 17 bases {6,8,10,15,20,25,30,35,40,45,50,75,90,120,150,180,210} x pct -40..+40: exactly **115** float disagreements out of **1,377** |
| `test_qa_canary::test_lines_match_golden` | 28 lines equal `golden/engine_canary.txt` (10.2) |
| `test_qa_canary::test_int_div_zero` | `expect_errors(1)`: `5 / z` with `z = 0` returns `0` and raises exactly one engine error ("Division by zero error in operator '/'") |
| `test_qa_cli::test_parse` | `["--a=1","--b","2","--flag","pos"]` -> `{a:"1", b:"2", flag:true, _:["pos"]}`; `--k` followed by another `--x` is a flag; `get_int` of `"x"` sets `usage_error`; `Exit` values `0..6` exactly as 4.1 |
| `test_qa_log_guard::test_counts` | `push_error` -> `errors == 1` (type 0); `push_warning` -> `warnings == 1`; runtime script error -> `errors` +1 with a backtrace sample; guard removal stops counting |
| `test_qa_temp::test_lifecycle` | directory created under `user://qa_tmp/<pid>/`; `dispose()` removes it; writing through `QaTemp.path()` works, outside paths refused |
| `test_qa_golden_manifest::test_verify` | tamper one byte of a fixture golden -> verify fails naming the file; revision mismatch with CHANGELOG fails; `update()` without the env reason returns an error |
| `test_qa_match_spec::test_parse` | `--rosterA=napc.canada` -> `roster.napc.canada`; `--rosterA=napc` -> `roster.napc.vanilla`; `--map=coast:128` -> family 2, size 128; `--map=open:100` -> error (not a multiple of 8); `--map=open:88` -> error (< 96); `--ai=none` without script/bot on 2 players -> error; 9 players -> error; unknown roster -> error listing near matches; auto size: 2p 96, 4p 128, 6p 160, 8p 192 |
| `test_qa_soak_plan::test_properties` | for `epoch = 20260929` over the real 32 ids: ROTATION has 96 matches; for each map the opponent function is a bijection; never the same faction; every roster appears exactly twice per map; 56 ordered / 28 unordered faction pairs covered; 96 distinct roster pairs; 96 distinct seeds; examples: map0 i0 `roster.napc.vanilla` vs `roster.nec.nordics`, seed `260929000`, swap true (`(20260929 + 0 + 0) % 2 == 1`); map1 i5 `roster.nec.nordics` vs `roster.ae.south_africa`, seed `260929105`, swap true; map2 i31 `roster.sap.pakistan` vs `roster.olm.algeria`, seed `260929231`, swap false (`20261172` is even); ENDURANCE has 3 matches of 8 players, rosters for `e6 = 260929`: `napc.usa, nec.eurocorps, olm.el_andalus, def.vanilla, pd.australia, han.vietnam, ae.south_africa, sap.vanilla`, seeds `260929900..902`; CONTENT has 32 matches, one per roster; `to_plan_file` output parses back to the same specs |
| `test_qa_soak_judge::test_wilson` | `wilson(93, 93)` (p = 0.5) = `[0.4004, 0.5996]`; `wilson(65, 93)` = `[0.2603, 0.4506]` (passes the M4 band: hi >= 0.45); `wilson(60, 93)` = `[0.2362, 0.4230]` (fails); `wilson(120, 93)` = `[0.5439, 0.7349]` (passes: lo <= 0.55); tolerance 0.0005 |
| `test_qa_soak_judge::test_hard_criteria` | synthetic results (both a `QaMatchResult` and an `AiMatchResult` carrying the `qa` block): `errors=1` -> HC2; `max_tick_us` above 100,000 x factor -> HC5; `static_end - warmup` 70 MB (2p) -> HC6; negative credits sample -> HC7; all good -> no hard failures; an `AiMatchResult` without a `qa` block -> a clear "missing qa block" failure |
| `test_qa_img_diff::test_metrics` | identical images: `diff_pct == 0`, `max_abs == 0`; one changed pixel of 100x100: `diff_pct == 0.01` (percent units, 0..100); solid colour: `blank_ratio == 1.0`; image with 1 % magenta (#FF00FF): `placeholder_pct` within 1.0 +- 0.01 |
| `test_qa_contrast::test_wcag` | `ratio(white, black) == 21.0`; `ratio(#767676, white) = 4.542` (>= 4.5 passes); `ratio(#777777, white) = 4.478` (fails) |
| `test_qa_contrast::test_delta_e` | CIEDE2000 Sharma vectors: `delta_e2000_lab(50, 2.6772, -79.7751, 50, 0, -82.7485) = 2.0425`; `(50, 3.1571, -77.2803, 50, 0, -82.7485) = 2.8615` (tolerance 0.0005) |
| `test_qa_contrast::test_cvd` | Machado severity 1.0, tolerance +-2 per channel: protanopia red (255,0,0) -> (109,95,0), green -> (255,229,0); deuteranopia red -> (163,144,0), green -> (239,214,58); tritanopia red -> (255,0,15), green -> (0,247,217) |
| `test_qa_replay_tools::test_ddmin` | synthetic predicate "fails iff records 13 and 77 are both present" over 100 records -> `minimise` returns exactly `[13, 77]` in <= 60 predicate calls |
| `test_qa_a11y_audit::test_findings` | a Control tree with an unnamed `Button` -> finding `A-13`; a focus trap (two Controls pointing at each other without an exit) -> `A-04`; a well-formed tree -> no findings |
| `test_qa_layout_audit::test_overflow` | a `Label` with 200 characters in a 120 px container without wrapping -> overflow finding at scale 1.0 and 2.0; wrapped label -> none |
| `test_qa_data_audit::test_oracle` (+ `tools/py/tests/test_qa_ref_oracle.py`) | the exact-rational oracle on rows of data's worked examples (its 5.6, current on 2026-09-29) as vectors, acceptance set `{exact}` for an integer and `{floor, ceil}` otherwise: Guardian cost 850 with +10 % -> exact 935 (accepts only 935; 934 and 936 rejected); Guardian health 907 with +10 % -> exact 997.7 (accepts 997 and 998, rejects 996 and 999; data's value is 998); Narwhal health 907 with +10 % x +10 % -> exact 1097.47 (accepts 1097 and 1098, rejects 1096 and 1099; data's value is 1097); Beaver health 602 x 1.21 -> exact 728.42 (accepts 728 and 729, rejects 727 and 730; data's value is 728); China Imperial Guard Tank health 1588 * 0.90 * 1.15 -> exact 1643.58 (accepts 1643 and 1644, rejects 1642 and 1645; data's value is 1644); floor case (Han Banner Infantry cost 250: layer 1 -15 %, then a hypothetical layer-3 -30 %) -> exactly 150 (149 is rejected: floors are exact, not tolerant); duration case 6 s at -20 % -> exactly 96 ticks (95 and 97 rejected); a modifier applied to a service unit -> scope violation; a hand-edited dump with one wrong stat is reported with roster, def and stat |
| `test_qa_adapter_contract::test_symbols` | every symbol `QaSimAdapter` uses exists: the sim_core ones are hard requirements from M1 (`SimWorld.step/apply_turn/submit/checksum/report_at/dump_state`, `SimTestKit`, `SimInvariants.check`, the `SimCommand` builders), the others are listed as missing per domain (drift alarm, T0); every MASTER-catalog name resolves through `cmd(name, fields)`, every economy `CMD_*` alias resolves to a catalog name, every required event kind of 4.3 has a decoder, every `rules` key QA uses maps to a `SimMatchRules` field (unmapped keys are listed; risk R30) |
| `test_qa_driver_equivalence::test_direct_vs_session` | D01 shortened to 1,200 ticks: the DIRECT and SESSION drivers of `QaSimAdapter` produce identical `[tick, checksum, input_chain]` chains and equal event digests |
| `test_qa_world_frees::test_no_cycle` | build a `QaWorld`, run 200 ticks, `close()`: a `weakref` to the `SimWorld` is dead and `Performance.OBJECT_COUNT` is back within +-20 of the start (the runtime twin of lint `SL-8`) |
| `test_qa_timed_system::test_transparent` | S-CORE-1 (sim_core 10.3, 200 steps) with and without `QaTimedSystem.install`: identical checkpoints `1821889010, 1296281870, 4010259252, 1438074068, 1511169403` at ticks 20..100; the decorator overrides every method of `SimSystem` (`get_method_list` difference empty) |
| `test_qa_game_inv::test_detects` | `SimTestKit` worlds mutated on purpose: negative credits -> G1; `unit_count` above `unit_cap` -> G2; a production queue of 6 -> G3 (skipped and reported when the queue is unreadable); a produced unit without its prerequisite -> G5; an unpermitted def for the roster -> G6; a clean world -> no finding |
| `test_qa_hash_coverage_meta::test_all_covered` | every `class_name ... extends SimComponent` in `src/sim/comp/` and every `SimSystem` with private state has a test file that calls `check_hash_coverage` on it (DR-13); the sim_core stubs pass trivially |
| `test_qa_d05_covers_catalog::test_ops` | the op names used by `fixtures/scripts/d05.cmds.json` plus `PLAYER_DROP` (net cases) cover all 40 entries of `SimCommand`'s op table; an unknown name fails |
| `tools/py/tests/test_qa_impair.py` | seed 1, profile `lan`: over 10,000 datagrams loss within 0 +- 0.5 %; profile `bad_wifi`: loss 3 % +- 0.5 %; identical sequences for identical seeds; blackout drops everything inside the window and nothing outside |
| `tools/py/tests/test_qa_logscan.py` | sample logs: clean -> pass; a line `WARNING: 2 ObjectDB instances were leaked at exit` -> fail; `SCRIPT ERROR:` -> fail; allow-listed loader line -> pass |
| `tools/py/tests/test_qa_package.py` | two builds with the same `SOURCE_DATE_EPOCH` -> identical sha256 (zip, tar.gz); tar entries uid/gid 0, sorted; zip modes preserve 0755; `SHA256SUMS.txt` verifies with both `shasum -a 256 -c` and `sha256sum -c`; `verify_release` fails when one byte of a payload file is altered |
| `tools/py/tests/test_qa_sim_rules.py` | for `SL-3` (remainder) and `SL-5..SL-10` a violating fixture is flagged with the rule id and line and its clean twin passes; `# lint-allow: SL-n reason` suppresses exactly one line and an allow without a reason is itself an error; the `SL-1`, `SL-2`, `SL-4` fixtures are flagged by tooling's `lint.py --rules L003` (pins the division of labour) |

### 10.2 Engine canary golden (`game/tests/golden/engine_canary.txt`; identical on legs A, B, C)
```
div_trunc -3 -3 3
mod_sign -1 1 -1
shr_neg -4 -1
shl 4611686018427387904 -9223372036854775808
wrap -9223372036854775808 9223372036854775807
mul_wrap 0
min_neg -9223372036854775808 -9223372036854775808
div_zero_guard 3
roundi 1 -1 2 3 -3
ceili_floori 3 -1 0
int_cast 2 -2 12 0
secs_to_ticks 6 900 21 7
cells_to_units 2560 717 7168
to_float 1.5 1.0 1000.0 0.5
str_float 0.3 1.0 100000000000000000000.0 0.0
fmt 3.14 12345   2.2 1234.57
dict_order zeta,alpha,beta,mid
hash_str 3488633211 2784076613
sort_ties 0,18,3,15,6,12,9,19,16,13,10,7,4,1,11,8,14,5,17,2
sort_ints [-1, 0, 3, 3, 5, 9]
sort_strs ["1", "10", "2", "A", "B", "_", "a", "b"]
case title_i TITLE_I i ß
json_types 3 3 3 9007199254740992.0 0.0
json_stringify {"a":[1,2.5,"x"],"b":1}
json_sorted {"a":2,"b":1}
sha256 b6c4ac412ac8822355239dd717c11ca5b07373e4db550d0423c1b6aeceef8493
enc_s64 feffffffffffffff -2 4294967294 -2
enc_u32 -1 4294967295
```
How each line is produced (each value joined by one space after the label; all operands that would be constant-folded are routed through helper functions `_shr/_shl/_add/_mul` because the GDScript parser rejects constant negative shifts and folds constants): `div_trunc` = `a=-7`: `a/2, 7/-2, -7/-2`; `mod_sign` = `a%3, 7%-3, -7%-3`; `shr_neg` = `_shr(a,1), _shr(-1,40)`; `shl` = `_shl(1,62), _shl(1,63)`; `wrap` = `_add(9223372036854775807,1), _add(-9223372036854775807,-2)`; `mul_wrap` = `_mul(4611686018427387904,4)`; `min_neg` = `m=_add(-9223372036854775807,-1)`, `m`, `absi(m)`; `div_zero_guard` = `clampi(5,0,3)`; `roundi` = `roundi` of `0.5,-0.5,1.5,2.5,-2.5`; `ceili_floori` = `ceili(2.0000001), floori(-0.1), ceili(-0.1)`; `int_cast` = `int(2.9), int(-2.9), int("12"), int("-0")`; `secs_to_ticks` = `ceili(0.3*20), ceili(45.0*20), ceili(1.05*20), ceili(0.35*20)`; `cells_to_units` = `roundi(2.5*1024), roundi(0.7*1024), roundi(7.0*1024)`; `to_float` = `"1.5"`, `"1,5"`, `"1e3"`, `".5"` `.to_float()`; `str_float` = `str(0.1+0.2), str(1.0), str(1e20), str(-0.0)`; `fmt` = `"%.2f"%3.14159, "%d"%12345, "%5.1f"%2.25, String.num(1234.5678,2)`; `dict_order` = insert `zeta, alpha, mid, beta`, overwrite `alpha`, erase `mid`, re-insert `mid`, keys joined by `,`; `hash_str` = `"unit.napc.guardian_tank".hash(), hash(12345)`; `sort_ties` = ids of `[i % 3, i]` for i in 0..19 sorted by `x[0] < y[0]`; `sort_ints` = `[5,3,-1,3,9,0].sort()`; `sort_strs` = `["b","B","a","A","_","1","10","2"].sort()`; `case` = `"TITLE_i".to_lower(), "title_i".to_upper(), "İ".to_lower(), "ß".to_upper()`; `json_types` = `typeof` of `a` (1), `b` (2.0), `c` (1e2) after `JSON.parse_string('{"a":1,"b":2.0,"c":1e2,"d":"x","big":9007199254740993,"neg":-0}')`, then `big`, `neg`; `json_stringify` = `JSON.stringify({"b":1,"a":[1,2.5,"x"]})`; `json_sorted` = `JSON.stringify({"b":1,"a":2}, "", true)`; `sha256` = SHA-256 of UTF-8 `meridian`; `enc_s64` = 8-byte buffer, `encode_s64(0,-2)`: hex, `decode_s64`, `decode_u32`, `decode_s32`; `enc_u32` = `encode_u32(0,0xFFFFFFFF)`: `decode_s32`, `decode_u32`. Informational, never compared: `os <name> <arch> locale=<l>`. `hash_str` and `sort_ties` are engine-version fingerprints: they change only with an engine upgrade (procedure X-33).

### 10.3 Determinism and scenario cases
| Test / job | Expected |
|---|---|
| `determinism/test_double_run` (D01 for 1,200 ticks, two worlds in one process, `NetSelfTest.run_double`) | `ok == true`, `first_mismatch_tick == -1`, `compared == 60` snapshots |
| `determinism/test_perturbation` (D01 600 ticks under perturbations a, b, g of D3) | chains equal to the unperturbed run |
| `determinism/test_replay_roundtrip` | live chain == `verify_file` chain; final checksum equal |
| `determinism/test_checksum_sensitivity` (D01 to tick 400, then one public field mutated per section on a copy) | `next_proj_id`, one extra `rng` draw, `players[0].credits += 1`, `hp` of the lowest live entity: each changes `world.checksum()`, and at the next checkpoint `report_at(tick).sections` differs from the control in exactly that section (`world`, `rng`, `players`, `entities`) and in no other; the control is unchanged |
| `determinism/test_simcore_golden` (D00 in process) | `Fp` digests, codec hex, `config_hash` and the S-CORE-1 chain equal `golden/sim_core.json`; the five fuzz chains equal a second run and the committed digests; a different seed differs (mirrors sim_core 10.4 through `simcore_dump.gd`) |
| `determinism/test_chain_goldens` (T1: D01-D03 shortened to 1,200 ticks; full lengths in `crossarch.py`) | equal to `golden/chains/*.chain` |
| `crossarch.py D00..D07,AI-D4-1..5 --legs A,B,C` (T2) | zero divergences; wall <= 10 min on RM (leg C ~7 min *(estimate)*) |
| leg F `--qa=match --scenario=D01 --chain-out` (T2) | equals leg A chain |
| N0 vs N4 vs N5 vs N6 (5.6) | equal `chain/final/checks` for equal scripts and fixed delay: network conditions never change the simulation |
| `scenario/sim/test_rule_*` (sim-owned; QA gate at M3, bible-defined numbers) | `start_preset`: all 32 rosters start with 1 HQ and 7,500 credits; `research_time`: T2 45 s = 900 ticks, T3 75 s = 1,500 ticks at full power and 1,800 / 3,000 ticks under shortage (50 %); `queue_length`: 5 accepted, 6th refused; cancel refunds spent credits; `tier_gates`: T2 def refused without Radar, T3 without Radar + Laboratory, losing Radar freezes dependent progress and resumes on rebuild; `replaced_unit`: `roster.napc.canada` refuses `unit.napc.guardian_tank` and accepts `unit.napc.narwhal_amphibious_tank`; `build_radius`: placement 9 cells from the HQ refused, 8 accepted; `superweapon_control`: starts empty, one stored charge, recharge starts at activation, pauses under shortage; `suppression`: 3 suppressive hits within 2 s -> movement -25 % for 3 s after the last hit; `detector`: camouflaged unit revealed within 5 cells; `transport`: Okapi 3 squads, Leviathan 4, others 2 |
| `scenario/sim/test_conditional_modifiers` (x3) | `modifier.napc.canada.03` applies only while the vehicle is on water; `modifier.olm.el_andalus.02` only for infantry in a marked civilian garrison; `modifier.ae.01` only while the target receives paid land-vehicle repairs; each toggles both ways |

### 10.4 Data cases (`data/`, `QaDataAudit`, data's own suites)
Pinned facts of the real bible that the gate asserts today *(verified against `meridian_factions.json`)*: 8 factions, 32 rosters (8 vanilla + 24 subfaction), 104 + 48 + 4 = 156 units, 29 structures, 98 modifiers (20 parent-faction + 78 subfaction), 40 research, 48 powers, 8 superweapons, 27 selectors; **158 modifier applications of which 3 carry `unresolved_target_domain`** (thermal-beam weapons of `modifier.olm.saudi_arabia.02`; carrier-launched drone pricing of `modifier.han.cambodia.01`; ordinary guided-missile flight speed of `modifier.sap.pakistan.02`) **and 6 carry `conditions` (3 distinct conditions**: `modifier.napc.canada.03` vehicle on water, `modifier.olm.el_andalus.02` infantry in a marked civilian garrison, `modifier.ae.01` target receiving paid land-vehicle repairs); 13 modifier stats (`health, cost_credits, rearm_time_seconds, build_time_seconds, movement_speed, reload_interval_seconds, sight_cells, power_output, weapon_damage, weapon_range_cells, repair_progress_rate, repair_credit_cost_per_health, projectile_flight_speed`); one operation `add_percent_within_layer`; distinct `*_seconds` values 0.5, 0.6, 6, 8, 10, 15, 20, 25, 30, 35, 40, 45, 50, 75, 90, 120, 150, 180, 210, 360, 420, 480. With data's stub bases the resolver reports 570 effective (target, modifier) applications and exactly 2 no-ops (data 5.5.4). DA-21 asserts the 115-of-1,377 float-trap count; DA-20 uses the worked examples of 10.1.

### 10.5 Fuzz, net-process, perf, visual, accessibility, release
* **Fuzz** (`fuzz/test_fuzz_smoke`): F-CMD-1 2,000 iterations seed 1 on D05's world, F-CMD-2 on 2,000 mutated batches of the golden 47-byte batch, F-CMD-3 on 200 privileged-op cases: `crashes == 0`, `invariant_failures == 0`, `accepted + rejected == 2000`; F-PKT at 2,000 iterations each (net's own suites already run 20,000 + 20,000 buffers per decoder); `test_fuzz_regressions` replays every file in `fixtures/fuzz/regress/` (starts empty; grows with findings).
* **Net process** (`tools/py/net_two_process.py` driving `net_harness.gd`): N0-N16 (5.6) with the tolerances in the table; orchestrator self-tests with a stub harness (parses `NETTEST`, detects a missing line, applies `kill -STOP/-9`); N4 (proxy pass-through) gives identical `chain/final/checks` to N0.
* **Perf** (`perf/test_perf_smoke`): PS0 for 400 ticks: `mean_us / factor <= 0.8 ms x slack`, checkpoint ticks reported separately; PS3 for 400 ticks: `mean_us / factor <= 0.6 ms x slack`; `QaPerf.compare` flags a synthetic 2x regression; baseline ratchet math (improve > 10 % x 3 runs lowers; raise refused without reason).
* **Visual** (`visual/test_visual_cases`, skips with `t.skip("needs a GPU")` when headless): each `cases.json` entry produces an image; VA-1..VA-5 pass; `visual_report.py check` rejects a review with a 5-word `fail` note, identical notes across cases, or reviewer == author role.
* **Accessibility** (`a11y/`): `test_team_colour_delta_e` (8 palette colours: min pairwise CIEDE2000 >= 20 normally, >= 12 under each CVD simulation), `test_theme_contrast` (all text/background token pairs >= 4.5:1, large text/graphics >= 3:1), `test_menus_a11y` (every interactive Control has a non-empty accessible name; focus order visits all; no trap), `test_layout_matrix` (1280x720, 1366x768, 1920x1080, 2560x1440, 3840x2160 x scale 1.0/1.5/2.0: zero overflow findings), `test_pseudoloc` (+40 % strings: zero overflow).
* **Release** (`tools/py/tests`): package determinism, `verify_release` tamper detection, deb `control` field validation (all `Depends` names present in a Debian 12 and 13 package list snapshot), lintian 0 errors (T2 from M5), `licenses.py audit` fails on the current `prototypes/ui/fonts` (Exo 2 and Saira Condensed lack `OFL` text: finding F-1) and passes after the texts are added; `golden_manifest.py` accepts an update of `data_hash.json` only with a reason.
* **Docs/legal:** `gen_controls_md.py` is idempotent (second run produces no diff); `gen_faction_guide.py` output contains all 32 rosters and 156 units; README contains no occurrence of the string "Command & Conquer"; `license_dump.gd` writes 19 licence texts and 102 component entries on the current engine.
* **Crash/log** (`tests/qa/test_app_*` written with app): 12 fake sessions -> exactly 10 log files; `.session` sentinel lifecycle; unclean-exit report created with all header fields; corrupt `settings.cfg` -> renamed `.bad-<utc>` + defaults; settings write atomicity (interrupt between temp write and rename leaves the old file intact).

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Sizes are estimated GDScript lines (Python noted separately). Every task ends with the ARCHITECTURE Appendix B DoD plus 5.17's task-level additions.

* **QA-01 Harness core (M0, ~1,000 GD + 300 py).** Files: `qa_cli.gd`, `qa_log_guard.gd`, `qa_temp.gd`, `qa_chain.gd`, `qa_golden.gd`, `qa_assert.gd`; `tools/py/qa/golden_manifest.py`, `logscan.py`, `logscan_allow.txt`; `game/tests/golden/MANIFEST.json` + `CHANGELOG.md` seeded with data's existing goldens. Deps: tooling runner (exists). Acceptance: `tests/qa/test_qa_cli, test_qa_log_guard, test_qa_temp, test_qa_chain, test_qa_golden_manifest`; `tools/py/tests/test_qa_logscan.py` (10.1).
* **QA-02 Canary and calibration (M0, ~450 GD).** Files: `qa_canary.gd`, `qa_calibrate.gd`, `canary_dump.gd`, `golden/engine_canary.txt` (10.2), `tests/qa/test_qa_canary.gd, test_qa_calibrate.gd, test_qa_time_conversion.gd`. Deps: QA-01. Acceptance: canary equal on legs A, B, C (script-verified today); calibration checksum equal on all legs; the time-conversion test shows 96 vs 97.
* **QA-03 CI orchestrator (M0, ~1,100 py).** Files: `tools/py/qa/ci.py`, `tiers.json`, frozen-mirror creation (`.cache/qa/<run_id>/`, `GD_ROOT`/`GD_GAME_DIR`), summary writer (`builds/qa/<run>/summary.json/.md`), `status` matrix for the M0-M6 gates (criteria as data), `--exclude` fallback via `gd test --list` + `--file`; proposed additions to tooling's `.github/workflows/build.yml` (jobs: QA scenarios D00-D03 chains on all three runners, `rotation` in the Debian container, net cases N0-N9, `verify_release`) delivered as a patch file for the toolsmith [QA-XR-8]. Deps: QA-01. Acceptance: `ci.py run T0` green in <= 2 min; a T1 step demonstrably runs from the mirror while a concurrent `gd import` on the live project is not blocked; `ci.py status --gate M0` lists each criterion as PASS/FAIL/UNKNOWN; unit tests with a fake `gd`.
* **QA-04 Match stack (M1, ~1,900 GD).** Files: `qa_sim_adapter.gd`, `qa_match_spec.gd`, `qa_match_result.gd`, `qa_match.gd`, `qa_metrics.gd`, `match_runner.gd`; `tests/qa/test_qa_match_spec, test_qa_adapter_contract, test_qa_match_smoke`. Deps: QA-01; sim_core (`SimWorld`, `SimMatchConfig`, `SimCommand`, MASTER event catalog, `SimInvariants`, `SimTestKit`; published), net (`NetSession.local_from_config`, `NetSimAdapterFake` for M0-M1), data (`GameData`), map (`MapGenerator`), ai (`AiFactory.make`). Acceptance: D01 (6,000 ticks) and a full match to victory or the 24,000-tick cap exit 0, `--twin` equal, replay verify OK; `--driver=direct` gives the same chain as `--driver=session` for the same spec (`test_qa_driver_equivalence`); `test_qa_world_frees`.
* **QA-05 Test-support and observers (M1, ~1,250 GD).** Files: `qa_world.gd`, `qa_event_stats.gd`, `qa_stuck_detector.gd`, `qa_game_inv.gd`, `qa_timed_system.gd`, `qa_corrupt.gd`; `tests/qa/test_qa_world, test_qa_event_stats, test_qa_stuck, test_qa_game_inv, test_qa_timed_system`. Deps: QA-04, sim_core (`SimTestKit`, `SimCommand` schema; published). Acceptance: a domain test (economy `test_prod_queue`) is re-expressed with `QaWorld.make/cmd/tick` in <= 20 lines; stuck detector flags a synthetic 600-tick immobile mover and ignores a 599-tick one; `QaTimedSystem` leaves the S-CORE-1 checkpoints unchanged (10.1).
* **QA-06 Determinism suite and cross-arch (M1, ~1,500 GD + 800 py).** Files: `replay_verify.gd`, `qa_replay_tools.gd`, `simcore_dump.gd` (D00), `tests/determinism/*` (incl. `test_checksum_sensitivity`, `test_simcore_golden`), `tests/qa/test_qa_hash_coverage_meta`, `fixtures/scenarios/D01..D07.json`, `golden/chains/*`, `tools/py/qa/crossarch.py` (thin driver over `xplat_determinism.py`), `tools/py/qa/godot_x86_64.sh`. Deps: QA-02, QA-04, sim_core SC-12 (`SimTestKit`, golden `sim_core.json`), tooling `gd linux` and `xplat_determinism.py`. Acceptance: 10.3; D00 and D01-D03 equal on A, B, C (M1), D00-D07 + `AI-D4-1..5` on A, B, C, F (M2), E at M2/M3.
* **QA-07 Soak orchestration (M1 -> M3, ~1,100 GD + 900 py).** Files: `qa_soak_plan.gd`, `qa_soak_judge.gd`, `tools/py/qa/soak.py`, `fixtures/soak/plans/`, tests. Deps: QA-04; ai `AiSoakRunner`/`ai_soak_main.gd` (AI-11) with `--plan` and the `qa` result block [QA-XR-25]. Acceptance: `test_qa_soak_plan`, `test_qa_soak_judge`; `soak.py pr` runs the AI preset and applies HC1-HC8 (M1); `soak.py rotation` 96/96 inside the Debian container (M3); `soak.py endurance` x3 (M4).
* **QA-08 Data gate (M1 -> M3, ~1,600 GD + 700 py).** Files: `qa_data_audit.gd`, `qa_data_checks_gate.gd`, `qa_data_checks_oracle.gd`, `qa_data_checks_assets.gd`, `data_audit.gd`, `tools/py/qa/ref_oracle.py`, `tests/data/test_qa_*`. Deps: QA-01; data (`data_cli.gd`, `validate_balance.py`, `GameData.handshake()`), balance (`global.json`). Acceptance: T0 runs the validators strictly and asserts the pinned counts (10.4); oracle vectors of 10.1; hash parity on legs A, B, C; DA-01..DA-30 at M3.
* **QA-09 Content bot and balance probes (M3 -> M4, ~2,200 GD).** Files: `qa_content_bot.gd`, `qa_balance_probe.gd`, `tests/content/*`, `fixtures/content_waivers.json`, `balance_waivers.json`. Deps: QA-04, economy `q_*` queries and `SimPlacement.find_site`, `QaWorld.spawn` and `DEBUG` modes (6.2), balance `targets`. Acceptance: CONTENT plan 32/32 with union coverage 156/29/40/48/8 (M3); TTK/RPS conformance rows (M4).
* **QA-10 Performance (M1 -> M2, ~1,200 GD).** Files: `qa_perf.gd`, `perf_bench.gd`, `tests/perf/*`, `tests/perf/budgets.json`, `golden/perf_baseline.json`. Deps: QA-02 (calibration), QA-04, QA-05 (`QaTimedSystem`), sim_core `SimTestKit` (PS0), optional `system_usec` [QA-XR-16]. Acceptance: PS0-PS6 measured and recorded (PS0 within its budget from the first run); PV1-PV4 on a GPU host; ratchet logic tests.
* **QA-11 Fuzzers (M1 -> M2, ~1,800 GD).** Files: `qa_fuzz_rng.gd`, `qa_fuzz_commands.gd`, `qa_fuzz_packets.gd`, `qa_fuzz_files.gd`, `fuzz_runner.gd`, `tests/fuzz/*`, `fixtures/fuzz/*`. Deps: QA-01, sim_core `SimCommand`/`SimCommandCodec` (published; [QA-XR-19] for op enumeration), net codecs. Acceptance: RNG vectors; 2,000-iteration smoke clean for F-CMD-1/2/3; deflate-bomb case rejected < 50 ms; regression replay test.
* **QA-12 Net process orchestrator (M2, ~1,300 py + 100 GD fixtures).** Files: `tools/py/net_two_process.py`, `tools/py/qa/udp_impair.py`, `impair_profiles.json`, `fixtures/scripts/net_*.cmds.json`, `tools/py/tests/test_qa_impair.py`, orchestrator self-tests with a stub harness. Deps: net `net_harness.gd` (NET-11) with the extra options [QA-XR-26], tooling sandbox [QA-XR-2]. Acceptance: N0-N3 = net P1-P5 (M1/M2), N4-N13 (M2/M4), N14-N16 (M4).
* **QA-13 Visual harness (M2 -> M5, ~1,300 GD + 600 py).** Files: `qa_visual_case.gd`, `qa_img_diff.gd`, `tests/visual/visual_case.tscn` + `.gd`, `cases.json`, `checklist.json`, `tools/py/qa/visual_report.py`, tests. Deps: view/ui injectable scenes [QA-XR-28], tooling `gd shot`, domain visual scenes. Acceptance: >= 12 cases (M2), >= 60 (M5); review guards; goldens registered in the manifest.
* **QA-14 Accessibility and layout audits (M2 -> M5, ~1,200 GD).** Files: `qa_contrast.gd`, `qa_a11y_audit.gd`, `qa_layout_audit.gd`, `tests/a11y/*`. Deps: ui (theme tokens, accessible names). Acceptance: 10.1 vectors; A-01..A-06 at M2, A-01..A-24 at M5.
* **QA-15 Export smoke, QA presets, `--qa` hook (M2, ~500 GD).** Files: `qa_export_manifest.gd`, `export_smoke.gd`, `qa_entry.gd`. Deps: tooling presets [QA-XR-5], app hook [QA-XR-11]. Acceptance: exported QA build runs `--qa=canary` (equal to golden) and `--qa=match --scenario=D01` (chain equal to leg A); a missing-resource fixture is detected.
* **QA-16 Release engineering (M2 prototype -> M6, ~1,600 py).** Files: `tools/py/qa/release_payload.py`, `package_macos.py`, `verify_release.py`, deb assets (`control` template, DEP-5 `copyright` generator, man page, changelog, lintian override), `tools/py/tests/test_qa_package.py`. Deps: tooling `export.py`, `package_windows.py`, `package_linux.py` (changes requested in [QA-XR-8]), docs (QA-18), licences (QA-17). Acceptance: 5.13 recipes; reproducible double build; lintian 0 unoverridden errors on the `.deb` (Debian 12 container with lintian); install tests on Debian 12 and 13; `SHA256SUMS.txt` verifies with both tools.
* **QA-17 Legal and credits (M2 seed -> M6, ~700 py + 150 GD).** Files: `tools/py/qa/licenses.py`, `qa_licenses.gd`, `license_dump.gd`, `LICENSES/THIRD_PARTY.json/.md`, `credits.json` schema, fonts/provenance audits (DA-26..28). Deps: ui (Licenses/Credits screens), audio (provenance). Acceptance: finding F-1 reproduced then closed; 19 licences + 102 components dumped; audit fails/passes as specified.
* **QA-18 Documentation (M2 draft -> M6, ~500 py, no GD).** Files: `README.md`, `docs/USER_MANUAL.md`, `docs/CONTROLS.md` (G), `docs/FACTION_GUIDE.md` (G), `docs/KNOWN_ISSUES.md` (G), `docs/QA_MANUAL_TEST_PLAN.md`, `controls_dump.gd`, `gen_controls_md.py`, `gen_faction_guide.py`. Deps: ui bindings, data, balance. Acceptance: 5.18 outlines complete; generators idempotent; README trademark check.
* **QA-19 Bug tooling and static checks (M0 -> M1, ~1,900 py).** Files: `tools/py/qa/bugs.py`, `api_coverage.py`, `check_xplat.py` (proposed rules L011-L016 until tooling absorbs them), `check_sim_rules.py` (`SL-3` remainder and `SL-5..SL-10`, 5.14), `tools/py/tests/fixtures/lint/*` (violating/clean pairs for SL-1..SL-10), `docs/bugs/OWNERS.md`, `INDEX.md` generator, `bugs.py bisect`. Deps: tooling lint conventions (`# lint-allow:` syntax). Acceptance: `bugs.py check` in T1; `check_xplat.py` and `check_sim_rules.py` flag each seeded violation and accept each clean fixture; `api_coverage.py` prints the percentage used by the M1 gate.
* **QA-20 Crash/log/settings conformance tests (M2, ~600 GD).** Files: `tests/qa/test_app_log_rotation.gd`, `test_app_crash_report_fields.gd`, `test_app_sentinel.gd`, `test_app_settings_recovery.gd`, `test_app_settings_atomic_write.gd`, `test_app_focus_release.gd`, `test_app_window_clamp.gd`. Deps: app implementation [QA-XR-12/13/14]. Acceptance: 10.5 crash/log row.
* **QA-21 Gate reporting and manual protocol (ongoing, ~400 py).** Files: gate definitions M0-M6 as data in `tiers.json`, a `docs/STATUS.md` section generator, `QA_MANUAL_TEST_PLAN.md` result tables. Deps: QA-03. Acceptance: `ci.py status --gate M2` lists all 11 criteria of 5.17 with evidence paths.

---

## 12. Risks, open questions and your recommended resolution for each

| Id | Risk / open question | Recommended resolution |
|---|---|---|
| R1 | GDScript cannot meet the tick budget (measured model gives ~3-3.5 ms at 400 entities; the domain specs' 0.1-0.15 us/statement model sums to ~9 ms; a naive object design 8-12 ms) | ratcheted slack (2.0 -> 1.0 by M4); every domain publishes measured ns/statement; PS1 measured at M1; decision at M2: restructure hot loops, cheaper vision/AI cadences, or a written budget increase (GDExtension is forbidden; TPS must not change) |
| R2 | Windows cannot be tested locally (all Windows facts *(unverified-win)*) | hosted CI job (T0/T1 + leg-E chains) or a borrowed Windows machine at M2, M3, M5, M6; template workflow in QA-03; never rely on Wine |
| R3 | Rosetta legs are 1.5-2.6x slower; Docker without Rosetta falls back to QEMU (10-20x) | detect via `/proc/cpuinfo`; `--ticks-scale`; compare chain prefixes if lengths differ; never gate on wall time of emulated legs |
| R4 | Unsigned/ad-hoc apps trigger Gatekeeper/SmartScreen friction | documented steps (5.13), SHA-256, README section; optional Apple Developer ID + notarisation and Windows Authenticode after release (needs owner accounts) |
| R5 | Project licence undecided | owner decision recorded in `docs/AMENDMENTS.md` by M4; recommended MIT or Apache-2.0 (code) + CC BY 4.0 (assets); until then README states no licence grant |
| R6 | Copyright status of agent-generated assets is jurisdiction dependent | counsel question outside QA; keep provenance and generator versions; avoid third-party model output with unclear terms |
| R7 | TTS licensing (Kokoro OK; Piper voices, Apple/Windows system voices not OK); model cards can change | pin `model_sha256`, archive licence text with the audio, re-verify at M5, allow-list in DA-27 |
| R8 | Real-socket net tests can flake | logic tested in virtual time (net L1); L2 asserts eventual properties with generous timeouts and unique ports; no retry-until-green; quarantine policy |
| R9 | Engine upgrade changes `hash()`, sort tie order, float printing, shader behaviour | canary golden per engine version; upgrade = new golden revision + full D-chain rerun on all legs before any other work |
| R10 | API drift between domains breaks the harness (map, app, ui, view and audio are unpublished; sim_core is published and is a hard requirement from M1) | single adapter seam + `test_qa_adapter_contract` in T0 listing missing symbols per domain; `NetSimAdapterFake` keeps the harness alive meanwhile |
| R11 | Shared `user://` between concurrent agents/processes (already observed) | sandbox `HOME`/`XDG_DATA_HOME`/`APPDATA` per process; `--results` per run; never delete files you did not create |
| R12 | Official templates refuse path overrides | `--qa=` hook in QA presets only; T2 leg F fails loudly if the hook is missing |
| R13 | `ObjectDB ... leaked at exit` is a WARNING with exit code 0 | logscan G3 in every tier; request strict mode [QA-XR-1] |
| R14 | Screenshot output differs across GPUs/drivers/OS | per-platform goldens, PSNR thresholds, agent review is the real gate; goldens stored downscaled |
| R15 | LLM reviewer inconsistency or rubber-stamping | deterministic auto-checks first; strict items need observations; author != reviewer; at M5 `strict` items get a second independent review, disagreement escalates to a human |
| R16 | Wayland/X11/compositor variance on Debian | test both sessions on Debian 12 and 13 at M5; no required behaviour that Wayland forbids (window positioning, cursor warp) |
| R17 | Accessibility (AccessKit) maturity per OS in 4.7.2 is unverified | smoke with VoiceOver, NVDA, Orca at M5; fallback: optional OS-TTS announcer (A-14); document limits honestly |
| R18 | AI-vs-AI win rates are a proxy for human balance (ai.md R8 agrees) | treat as guardrail; human playtests after M5; vary AI styles; keep bands wide (5.4.6) |
| R19 | No VCS in the tree (agents may not run git) | `gd snapshot` labels per gate/bug, golden MANIFEST + CHANGELOG, bug files; recommend the owner initialises git (prepared `.gitattributes`) |
| R20 | Docs drift from the game | generators + idempotency checks in CI; docs updated in the same task as the feature (DoD U6) |
| R21 | Hosted CI may not exist | local `ci.py` is authoritative; the workflow is a template |
| R22 | Disk growth (replays, screenshots, results) | retention rules (5.12), goldens downscaled, `builds/` is git-ignored |
| R23 | AI `weekly` (~3 h on 8 shards) and QA endurance are long | run overnight/weekend; incremental mode re-runs only pairs involving rosters whose data hash changed |
| R24 | No physical mid-range hardware for the M5 floor run | obtain a 2019-class PC (4-core x86, integrated GPU) or accept the leg-C proxy plus volunteer reports; M5 cannot close without one real run |
| R25 | Overlapping harnesses (AI soak vs `match_runner`) could diverge | division of labour 5.4.0; shared `qa` result block; both drive net's LOCAL pipeline; `test_qa_soak_judge` accepts both result shapes |
| R26 | Domain test layouts vary (flat files, subdirectories, own fixtures) | placement rules 2.3; runner `--exclude`; QA-owned slow kinds isolated in five directories; no domain is forced to move files |
| R27 | Resolved by the published sim_core: `SimWorld.checksum()`, `checksum_log`, `report_at(tick).sections`, `dump_state()`, `SimInvariants.check()`. Still open: map-hash accessors and whether net's reconciled adapter exposes the same names | `QaSimAdapter` reads sim_core directly (DIRECT driver); net's `NetSimAdapter` names (`checksum_part_names`, `submit_raw`, `checksum_parts_at`) differ (R30) and matter only to the SESSION driver |
| R28 | Open question: is `roster_ids` order "bible order" or sorted-id order for UI/soak? | QA plans use bible order via the adapter; GameData's dense indices stay in sorted-id order (data 5.3); the two never mix |
| R29 | Existing CI (`.github/workflows/build.yml`) and packagers were written before the QA spec; QA changes to them could collide with the toolsmith's ownership | QA never edits them: deltas are delivered as requests/patch files ([QA-XR-8]); QA-owned scripts live in `tools/py/qa/` and call the tooling scripts |
| R30 | The published specs disagree on the sim's external contract: command opcodes (sim_core MASTER `0x01..0x51` vs economy 120..149, abilities 100..119, combat 40..47, net 240..255), event codes (sim_core `0x01..0x74` vs economy 300..499, abilities 200..259, combat 200..229), checksum section names (sim_core `world, rng, players, entities, map, sys.<name>.<stage>` vs net's `entities, players, rng, map, production, economy, orders, combat, zones, vision`), command representation (`SimCommand` + varint codec vs net's `PackedInt32Array [type, ...]`), `MatchConfig` rule keys (net `fog`, `veterancy`, `vision_*` vs sim_core `fog_mode`, `start_mode`, ...; `allow_debug` exists only in sim_core) and the replay container (`SimReplay` "MFRP" vs `NetReplayData`) | QA depends on no number and no section list: everything goes through `QaSimAdapter` by name, and `test_qa_adapter_contract` reports every unresolved name, alias and key. [QA-XR-30] asks the reconcilers to make sim_core's catalogs and section names authoritative and to give net an adapter over `SimCommand`/`SimCommandCodec`, `report_at` and `SimReplay`. Until then the DIRECT driver works on sim_core alone and the SESSION driver waits for the reconciled net adapter |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**Tooling (owner of `docs/spec/qa_tooling.md`)**
1. `[QA-XR-1]` `gd run` / `gd test` strict mode (flag `--strict` or env `MERIDIAN_STRICT=1`, on in `ci.py`): treat `WARNING: N ObjectDB instance(s) were leaked at exit`, `ERROR: N resources still in use at exit`, `Program crashed with signal` as failures (exit 3). Reason: verified to be WARNING-level with exit code 0.
2. `[QA-XR-2]` Per-invocation `user://` sandbox: `gd <cmd> --sandbox <label|auto|off>` sets `HOME=<.cache/home/<label>>` and `XDG_DATA_HOME=$HOME/.local/share` (macOS/Linux; `APPDATA` on Windows), pre-creating the directories; default `auto` = one stable directory per agent session (keeps the shader cache warm). Document that concurrent processes otherwise share `user://` (observed: `last_test_run.json`, `logs/godot.log`, `shader_cache/` of several agents in one directory).
3. `[QA-XR-3]` Runner options: `--exclude=<csv>` (substrings of `<file>::<method>` to drop) and `gd test --repeat N` (run selected tests N times in fresh instances; report per-id pass counts) for flake classification.
4. `[QA-XR-4]` (the arm64 engine and `gd linux --arch arm64` now exist - thanks) optional `gd linux --distro 12|13` (image variant on `debian:13-slim`, with `libasound2t64`) for the Debian 13 install and rotation runs; the Debian 12 image already installs `libfontconfig1`, which silences the loader line.
5. `[QA-XR-5]` Export presets (`game/export_presets.cfg`): (a) release presets: `exclude_filter="tests/*, tools/*, docs/*"`, Linux `binary_format/embed_pck=true`, all three `shader_baker/enabled=true`, `debug/export_console_wrapper=0`, `application/version`/`short_version` = `application/config/version`; (b) new QA presets `QA Windows`, `QA Linux`, `QA macOS` on the release template with `exclude_filter=""`, `include_filter` covering `tests/harness/*, tests/golden/*, tests/fixtures/*` (non-resource files), `custom_features="qa"`, `debug/export_console_wrapper=2`; (c) keep macOS `codesign/codesign=1` (ad-hoc, verified by `export.py`).
6. `[QA-XR-6]` `game/project.godot`: `debug/file_logging/enable_file_logging.standalone=true`, `debug/file_logging/max_log_files=10`, `application/config/version="0.1.0"`, `debug/settings/crash_handler/message="Meridian Fracture crashed. A report was saved in the logs folder; please attach it when reporting."`, decision on `accessibility/general/accessibility_support`; keep `application/run/low_processor_mode=false`; neutralise the trademark in `config/description` ("Command & Conquer style" -> "classic base-building RTS style").
7. `[QA-XR-7]` Lint rules (tooling's list ends at L010 = CRLF; ids proposed here follow it, QA supplies `check_xplat.py` until absorbed): L010 extended to UTF-8 BOM and a missing final newline in `game/` and `docs/` text files; L011 `TranslationServer.format_number|parse_number` outside `src/ui`, `src/app`; L012 network/shell APIs (`HTTPRequest`, `HTTPClient`, `StreamPeerTCP`, `TCPServer`, `WebSocketPeer`, `OS.execute`, `OS.create_process`, `OS.create_instance`, `OS.shell_open`) outside `src/net`, `tests/`, `tools/` (no telemetry, no shelling out); L013 `assert(` whose argument contains an assignment or a call to a non-pure function (asserts are compiled out of release templates); L014 `res://tests`, `Qa*`, `TestCtx` referenced from `src/`; L015 `.gd` without sibling `.gd.uid` after import; L016 comparator lint (warning) for `sort_custom` in deterministic modules without an `.id` tie-break; extend L002 with `com0/lpt0` and case-insensitive duplicate names.
8. `[QA-XR-8]` (a) `xplat_determinism.py`: accept several scenarios per invocation and a `--targets` value `rosetta` (leg B via `GODOT_BIN=tools/py/qa/godot_x86_64.sh`), or let `crossarch.py` drive it as documented; (b) `package_windows.py` / `package_linux.py`: `--payload DIR` (copy the QA payload into the archive), zip entries with fixed `date_time` and Unix modes, `.deb` per the 5.13 quality bar (DEP-5 `copyright`, `changelog.Debian.gz`, man page, verified `Depends`, no trademark in the description, `/usr/games` layout or an `/opt` override), version in the macOS package name; (c) `.github/workflows/build.yml`: accept the job additions of QA-03 and extend the determinism scenario list beyond `xplat_int_math.gd`; (d) optional `gd ci` passthrough to `tools/py/qa/ci.py`; (e) data's `data_cli.gd -- --update-goldens` (data V-HASH-01) must route through `golden_manifest.py update --reason` so that every golden change carries a reason.
9. `[QA-XR-9]` Repository hygiene files at the root: `.gitattributes` (`* text=auto eol=lf`; `*.png *.ttf *.wav *.ogg *.pck *.icns binary`) and `.editorconfig` (LF, UTF-8, tabs for `.gd`, 2 spaces for JSON).
10. `[QA-XR-10]` Docker: an image target with `lintian` (and `dpkg-dev`, `fakeroot` already present) for the `.deb` gate.

**App**
11. `[QA-XR-11]` `boot.gd`: when user args contain `--qa=<job>` and `ResourceLoader.exists("res://tests/harness/qa_entry.gd")`, instantiate it as a child, pass the remaining user args, and quit with its exit code; without the file the flag is ignored. Also `--selfcheck` = `QaExportManifest.verify` when present. Rationale: templates refuse `--path` (verified) and do not offer `--script`.
12. `[QA-XR-12]` `AppLogger` (`Logger` via `OS.add_logger`), `AppCrashReporter` (`.session` sentinel, `NOTIFICATION_CRASH`, `crash_<utc>[_unclean].txt`), toast on unclean exit, retention rules and report header exactly as 5.12; the crash report reads `Log.ring`.
13. `[QA-XR-13]` `settings.cfg` sections/keys and defaults: `[meta] version`; `[video] window_mode, resolution, monitor, ui_scale, vsync, fps_cap, quality, renderer`; `[audio] master, music, sfx, voice, ui, mute_unfocused, captions`; `[access] colour_mode, reduce_motion, reduce_flash, ui_font, announcer_tts, high_contrast_hud, cursor_scale, edge_scroll_enabled, edge_scroll_speed`; `[controls] <action>=<events>`; `[net] player_name, port`; corrupt-file recovery and atomic writes; window position clamp; focus-loss input release.
14. `[QA-XR-14]` `AppInfo.version() -> String`, `build_id() -> String`, `platform_string() -> String`; extend the smoke line to `MERIDIAN_BOOT engine=... renderer=... os=... debug=... version=<x.y.z> build=<id> selftest=<ok|N>` where `selftest` is the outcome of `Fp.self_test()` (sim_core 8.4 and its request R20: the engine arithmetic facts the sim relies on; `ok` or the number of failed checks), so that every launched package, including the Windows zip on the hosted runner, proves the integer semantics without a full match (`export.py` parses by prefix; existing keys unchanged).

**Sim (and core)**
15. `[QA-XR-15]` (sim_core, confirmation) `SimInvariants.check(world) -> PackedStringArray` stays public, allocation-light and <= 2 ms at 1,900 entities (QA calls it every 100 ticks); a `SimWorld` is freed when the last external reference is dropped - no RefCounted cycles (its lint L-8) - which `test_qa_world_frees` proves. A cycle found there is an S1 bug against the offending domain; no `dispose()` is requested.
16. `[QA-XR-16]` (sim_core, optional) `opts.profile: bool` for `SimWorld` and `SimWorld.system_usec: PackedInt64Array` (index = stage_no - 1) filled only when enabled. Without it QA times stages 2-11 with the `QaTimedSystem` decorator.
17. `[QA-XR-17]` (sim_core) extend `DEBUG` (0x0F): wire schema `MODE, TARGET, DEF, COUNT, X, Y` (adds `TARGET`), modes 3 `KILL`, 4 `REVEAL`, 5 `SET_HP`, 6 `CHARGE`, and the precise spawn placement of mode 2 (6.2); all gated by `SimMatchRules.allow_debug`, always acting for the issuing pid; the AI, the UI and net's lobby never emit or enable them.
18. `[QA-XR-18]` (movement, via sim_core 4.3) maintain the mirror flag `F_BLOCKED` (the unit's path is blocked or it waits for a free cell) and clear it on progress, so that `QaStuckDetector` can name the reason. QA reads only `world.units` and `SimEntity.orders/x/y/t_hit/flags`, which are public and read-only by convention.
19. `[QA-XR-19]` (sim_core) `SimCommand.all_ops() -> PackedInt32Array` and `SimCommand.op_name(op: int) -> String` (the MASTER-catalog names QA scripts use) and, optionally, `SimCommand.field_range(op: int, field_code: int) -> Vector2i` for schema-aware fuzzing (QA falls back to boundary values without it). `schema_of`, `is_known`, `actor_kind`, `allowed_when_paused` and `system_only` (sim_core 3.5) are used as they are.
20. `[QA-XR-20]` (all sim domains) emit the events QA relies on exactly as the MASTER catalog lists them (`SPAWNED` with its reason, `PRODUCTION_COMPLETE`, `RESEARCH_COMPLETE`, `POWER_USED`, `SW_LAUNCHED`, `BUILD_READY`, `QUEUE_BLOCKED`, `HARVEST_DELIVERED`, `CASH`); the reconcilers map the economy (300..499), abilities (200..259) and combat (200..229) ranges onto that catalog (risk R30).
21. `[QA-XR-21]` (sim_core, confirmation) `SimConfig.SIM_VERSION` is bumped for every result-changing change and QA then regenerates all chain goldens in one revision (5.3); `game/tests/golden/sim_core.json` is registered in the golden manifest; `SimTestKit` takes the fixture path as a parameter, because tooling's L005 forbids `res://tests/` strings in `src/`, or moves to `tests/harness/` (QA's preference: it is test code and then never ships). The content bot uses economy's published queries; no further request.
22. `[QA-XR-22]` (data) `data_cli.gd --dump units|structures|research|powers|superweapons|rosters` emitting canonical JSON of the resolved defs for the oracle; `GameData.handshake()` printable by `data_cli.gd --hash` on every leg; confirm the exact strings `hash`/`tables`; publish the metric "decisions in `selector_resolutions`" so the oracle can map the 3 unresolved domains.
23. `[QA-XR-23]` (core/sim_core) `Log` gets an injectable sink, `Log.sink: Callable = Callable()` called with (level, tag, msg), so that the app can add timestamps, the rate limit and the file output of 5.12 while `src/core` stays clock-free; `Log.ring` (256 lines) stays and feeds crash reports; no other change.
24. `[QA-XR-24]` (map) `MapGenerator.generate(map_cfg: Dictionary) -> MapData` as a pure function of `config.map` (sim_core R8), `MapData.map_hash` (u32), family codes 0..2 = open, urban, coast (net.md 7.1), config flag `map.start_near_water: bool`, guarantee >= 2 exits per start and reachable deposits, `map_validator`; 24 seeds x 3 families must pass DA-29.
25. `[QA-XR-25]` (ai) `ai_soak_main.gd --plan=<file>` (list of match specs from `QaSoakPlan.to_plan_file`) and a `qa` block in `AiMatchResult`: `{engine_errors:int, max_tick_us, p99_tick_us, static_kb_warm, static_kb_end, objects_start, objects_end, orphans_end, peak_entities, invariant_violations:[String], twin_ok:bool}`; an invariant cadence option `--validate-every=100` (calls `SimInvariants.check`); the AI must never emit `DEBUG` (0x0F) or `PLAYER_DROP` (0x04); per-call cap 9 ms (already in ai.md); the QA CONTENT plan needs `AiFactory.make` with level EASY as the passive opponent.
26. `[QA-XR-26]` (net) extra `net_harness.gd` options: `--corrupt-at=<tick>:<section>:<value>` (applies `QaCorrupt.apply`, 6.3, on that peer only; QA builds/editor only), `--out` JSON containing the `NETTEST` fields, `--data-file-override=<path>` (start one process with a modified data file for the version-mismatch case); `NetSessionOptions.pacing_unlimited`/`speed_pct = 0` (already `--speed=0`); QA implements `tools/py/net_two_process.py` (net.md XR-18); the `NETTEST` line format stays stable; `lobby_options.json rules_schema` accepts `allow_debug` (0/1, default 0) only when the harness passes `--allow-debug` (never from the lobby UI) and the world builder passes it to `SimMatchRules.allow_debug`; net's `NetSimAdapterWorld` is implemented over sim_core's real API (`SimCommandCodec`, `report_at`, `checksum_log`, `SimReplay`; R30).
27. `[QA-XR-27]` (balance) keep the `targets` schema stable (`ttk_unopposed_s`, `rps_equal_cost`, `sortie`, `defenses`, `structure_kill`, `superweapon`, `power_first_shortage_after_s`), publish the `pacing` windows (FRAMEWORK 5.7), keep `unit_assignments` (archetype -> unit) readable, and own `fixtures/balance_waivers.json`.
28. `[QA-XR-28]` (view/ui) injectable roots: `ViewRoot.new(adapter, local_pid)`, `UiHud` (no autoload dependency); `ViewCamera.set_pose(cell_x, cell_y, yaw_deg, pitch_deg, zoom)`; frozen animation clock and seeded VFX RNG for screenshots; `UiTheme.colors() -> Dictionary` per state and `UiTheme.team_colors() -> PackedColorArray` (8); `UiBindings.dump() -> Dictionary`; accessible names on every interactive Control; UI scale through `Window.content_scale_factor`; Credits/Licenses screens fed by `credits.json`, `THIRD_PARTY.json` and `Engine.get_license_*`; domain visual scenes registered in `cases.json`.
29. `[QA-XR-29]` (audio) `game/assets/audio/PROVENANCE.json` (7.8) for every generated voice/sfx/music file, licence allow-list (5.11), captions for voice lines, `SndEventMap.missing() -> PackedStringArray` for DA-23.
30. `[QA-XR-30]` (reconcilers) amendments to `docs/ARCHITECTURE.md` via `docs/AMENDMENTS.md`: (1) section 11 test layout: recursive discovery, `test_*(t)` methods, `fixtures/`+`harness/` not scanned, QA slow kinds in `determinism/ fuzz/ perf/ content/ visual/`, runner `--exclude`; (2) `OS.create_process/create_instance` allowed under `tests/` and `tools/` only; (3) new directory `tools/py/qa/`; (4) sim_core's MASTER command and event catalogs and its checksum section names are the single authority: the numeric ranges of economy (120..149, events 300..499), abilities (100..119, 200..259), combat (40..47, 200..229) and net (240..255) are removed or mapped, and net's `NetSimAdapter` sits on `SimCommand`/`SimCommandCodec`, `report_at` and `SimReplay` (R30); (5) Debian package layout under `/usr/games` with embedded PCK; (6) `user://` sandbox rule for concurrent processes; (7) project licence decision record; (8) trademark wording ("classic base-building RTS"); (9) extended `MERIDIAN_BOOT` line; (10) Debian 11 unsupported (ELF kernel note 5.15); (11) official export templates refuse `--path` and do not offer `--script`, so QA code runs in exports only via the `--qa` hook; (12) one golden manifest for all domains; (13) sim_core's R21/R22 to QA are accepted as job D00 and lint ids `SL-1..SL-10` (5.14) and are recorded in the amendment log.
