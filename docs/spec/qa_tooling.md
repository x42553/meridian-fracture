# QA & Tooling Manual (agent handbook)

Owner: toolsmith. Every command below was executed on macOS arm64 (Apple M5 Max) with Godot 4.7.2; timings are what I measured.
Paths are relative to the repo root; `res://` = `game/`.

## 0. Rules of the road
1. **Never start the Godot binary on `game/` yourself.** Use `tools/gd`: it serialises the shared `game/.godot/` cache (an import
   rewrites `global_script_class_cache.cfg`, which every `class_name` lookup reads) with a fair reader/writer lock.
2. Before you report done: `tools/gd check <your dirs>` clean, `tools/gd test <your filter>` green; quote both results.
3. Verify every engine API with `tools/gd docs` (the class reference in `tools/godot_docs` is signatures-only, no prose).
4. Look at your pixels: `tools/gd shot`, then open the PNG with the image reader.
5. Godot writes `<script>.gd.uid` next to every script on import; keep them (stable references across renames).
6. Env overrides: `GODOT_BIN` (engine binary; CI), `GD_ROOT` / `GD_GAME_DIR` (run against a throw-away project), `GD_TRACE_FILE`.

Exit codes: `0` ok, `1` failure (tests, lint/script errors, import), `2` usage / nothing matched / config, `3` Godot exited 0 but printed
engine `ERROR:` lines (`run`, `shot`), `124` hard timeout or stall-kill, `141` output pipe closed. `-v` prints the exact Godot command line.

## 1. Commands
| Command | Does | Measured |
|---|---|---|
| `tools/gd import [--if-stale]` | `godot --headless --import`, exclusive lock, refreshes class cache | 1.5-2 s (tiny project) |
| `tools/gd check [paths] [--fast] [--strict] [--warnings] [--lint-only] [--json F]` | lint + compile every script + warnings | 0.3-0.7 s (+~2 s when an import is due) |
| `tools/gd test [filter...] [-q] [--file F] [--list] [--trace] [--fail-fast]` | headless test run | 0.6 s for 16 tests (incl. a 0.5 s timeout demo) |
| `tools/gd run <res://x.gd\|x.tscn> [--gui] [-- args]` | run a script/scene, headless by default | 0.2 s |
| `tools/gd shot <scene> <out.png> [--frames N] [--size WxH] [--rendering-method M]` | real-renderer screenshot | 0.7 s |
| `tools/gd docs <Class> [member]` / `--find text` / `--list` | API lookup | instant |
| `tools/gd linux [--arch amd64\|arm64] <any command>` | same command in a Debian 12 container | 3-14 s warm |
| `tools/gd ps` | who holds / waits for the project lock (a waiting `gd` also prints this) | instant |
| `tools/gd snapshot [label]` / `--list` | tar.zst of the source tree into `.backups/` | 4 s (400 MB, other agents' prototypes) |
| `tools/setup [--templates] [--docker]` | fresh-checkout bootstrap: engines (sha512), bible mirror, first import | 3 s when up to date |

**Auto-import.** `check/test/run/shot` first compare a snapshot of what the import cache depends on with the one stored by the last import
(`.cache/import_state.json`): scripts that declare `class_name` (path + header lines `class_name/extends/@tool/@icon/@abstract`), scenes,
resources, shaders, images, audio, fonts, models, `project.godot` (mtime+size). **Editing a script body, or adding a script without
`class_name`, does not trigger an import**; sidecar `.uid/.import` are ignored. Anything else => the command releases its shared lock, imports
under the exclusive lock, re-checks, continues (`gd: importing (new: src/sim/sim_world.gd) ...`, ~2 s). A new `class_name` therefore just works.
Proof (`python3 tools/py/concurrency_test.py`): 6x `gd test` + 2x `gd import` from a cold cache in three arrival orders, no deadlock,
peak 6 concurrent readers, no exclusive interval overlapped any other lock interval, class cache valid, identical test summaries.
`game/.godot` is unchanged (mtime+size of every file) after test/run/shot/check (verified).

### check
```
$ tools/gd check
[lint] 23 files, 0 violation(s), 4 suppressed by lint-allow
[scripts] 0 error(s)
[warnings] 0 GDScript warning(s) in 0 file(s)
RESULT: OK (0 script error(s), 0 lint violation(s), 0 warning(s)) in 0.7s
$ tools/gd check src/sim tests/unit/test_sample_ctx.gd     # scope: res://, game/ or game-relative paths
```
Errors print as `game/src/x.gd:12: error: Parse Error: ...` (also type errors, unknown identifiers, duplicate class_name). Godot itself
prints no warnings in headless runs, so the checker runs a second process with every WARN promoted to error and reports the difference:
`game/x.gd:5: warning[unused_variable]: ...` (the bracket is the name for `@warning_ignore("...")`). Warnings only fail with `--strict`
(CI does). `--fast` skips that second process. `tests/fixtures/` and dot-dirs are not scanned unless passed explicitly.
Proven on deliberately broken temp scripts (syntax error `func g(`, `var x: int = "abc"`, undefined identifier): each reported with
file:line and exit 1; deleted afterwards (also automated in `tools/py/tests/test_gd_cli.py`).

### test
```
$ tools/gd test sample_ctx -q
== 4 files, 4 tests in 0.01 s: 4 passed, 0 failed, 0 errors, 0 skipped (23 checks)
$ tools/gd test --file tests/fixtures/fixture_failing.gd      # exit 1, prints file:line for every failed assertion
$ tools/gd test --list | head -3 ; tools/gd test --json out.json
```
Filter = case-insensitive substrings of `<path under tests/>::<method>`, comma/space separated, OR-ed. No match => exit 2 (never a silent pass).
Machine-readable report: `user://last_test_run.json` (macOS: `~/Library/Application Support/MeridianFracture/`), last writer wins;
`--json FILE` gives you a private copy. Godot exits 0 after script errors, so the runner installs a `Logger`: any engine error raised
during a test (null call, `push_error`, parse error of the test file) turns that test into ERROR with file:line.

### run / shot
```
$ tools/gd run tests/fixtures/run_args_demo.gd -- --foo=1 bar --exit=7    # prints ARGS=--foo=1,bar,--exit=7 ; exit 7
$ tools/gd run res://src/app/boot.tscn -- --smoke                          # MERIDIAN_BOOT engine=4.7.2-stable ...
$ tools/gd shot res://src/app/boot.tscn /tmp/boot.png --frames 5 --size 800x450     # prints the absolute path
$ tools/gd shot res://tests/scenarios/shot_demo.tscn /tmp/demo.png --size 640x360 -- --label=hello   # 3D demo, user arg
```
Args after a bare `--` reach the script via `OS.get_cmdline_user_args()`. `.gd` targets must `extends SceneTree`; `--timeout S` (run 300, shot 90),
`--stall S` (see gotchas). `shot` uses the project renderer (Forward+/Metal here; `--rendering-method mobile|gl_compatibility` also verified),
`--fixed-fps 60` so N frames = N/60 s of game time, an off-screen window (`--visible` to disable), 960x540 by default, and the `DevShot`
autoload (`game/src/app/dev_shot.gd`, inert unless `--shot=`, and in release builds) captures the root viewport after N frames. Look at the
result with the image reader (Read on the .png). Your scene can take its own options: `gd shot res://x.tscn o.png -- --map-seed=7`.

### docs
```
$ tools/gd docs Node2D position        ->  Node2D.position: Vector2 = Vector2(0, 0)
$ tools/gd docs roundi                 ->  @GlobalScope.int roundi(x: float)
$ tools/gd docs Logger                 # full class: properties, methods, signals, enums, inheritance chain
$ tools/gd docs --find frame_post      # substring search over all class and member names
```
Typos get suggestions (`Nod` -> Node, Node3D, Node2D). Covers core, scene, modules (enet, gdscript, regex...) and platform classes.

## 2. Writing tests
`game/tests/<module>/test_<thing>.gd`, `extends RefCounted`. Every `func test_*(t: TestCtx) -> void` is one test; a **fresh instance per test**
(no state leaks); optional `setup(t)` / `teardown(t)` around each. The ARCHITECTURE `func run(t: TestCtx)` form still works for files without `test_*`.
```gdscript
extends RefCounted
func test_integer_math_is_exact(t: TestCtx) -> void:      # from tests/unit/test_sample_basic.gd
	t.eq(7 / 2, 3, "integer division truncates toward zero")
	t.eq(-7 % 3, -1, "% keeps the dividend's sign")
```
`TestCtx`: `check(cond,msg)` `check_false` `eq(actual,expected)` (**type-strict**: int 1 != float 1.0, String == StringName) `ne` `near(a,b,eps)`
`lt/le/gt/ge` `is_null/not_null` `fail(msg)` `note(msg)` `skip(reason)` `expect_errors(n)` `set_timeout(s)`. All return bool and never abort.
* Engine errors fail the test unless declared with `t.expect_errors(n)` (exactly n).
* Tests may `await` (`await (Engine.get_main_loop() as SceneTree).process_frame`); a test that never resumes is abandoned after
  30 s (`tools/gd test -- --test-timeout=60`, or `t.set_timeout(s)` inside the test) and reported ERROR. An endless synchronous loop cannot be interrupted: gd kills the run at its timeout.
* Fixtures / non-test helpers live in `tests/fixtures/` (never discovered; `--file` runs them). Scenario scripts for `gd run` in `tests/scenarios/`.
* Shipped samples: `unit/test_sample_basic.gd`, `test_sample_ctx.gd`, `test_runner_detects_failure.gd` (drives `fixtures/fixture_failing.gd`
  through a real `TestSuite`: failures are detected, attributed to file:line, counted, and give exit code 1; empty selection gives 2).
  End-to-end (`tools/py/tests/test_gd_cli.py`): the failing fixture makes `gd test` exit 1.
* Determinism tests: build two `SimWorld`s side by side, feed both the same commands, compare `checksum()` every 20 ticks; cross-platform via section 4.

## 3. Lint (`tools/py/lint.py`, run by `gd check`; `--summary`, `--rules L003,L005`, `--list-allows`, `--json`)
| Id | Rule (scope) |
|---|---|
| L001 | every literal `res://` path in `.gd/.tscn/.tres/.cfg/.json/project.godot/.gdshader` exists with **exact case**; `%s`/`*` placeholders check the directory part |
| L002 | under `game/`: lowercase snake_case ASCII, no spaces, no Windows-reserved names (`con prn aux nul com1-9 lpt1-9`), path < 150; `README.md`, `LICENSE*`, `OFL.txt` allowed |
| L003 | `src/{core,sim,map,data}`: `randi randf randomize RandomNumberGenerator shuffle pick_random` (+`*_range`), `Time.*`, `OS.get_ticks*`, `Engine.get_*frames*`, float literals/`float`/`Vector2-4`/`Color`/`Transform*`/`PI TAU INF NAN`/`delta`/`sin cos tan atan atan2 sqrt pow exp log floor ceil round fmod` (+ `lerp floori roundi ...`), `.normalized() .distance_to() .length_squared()`. `Fp.sin(...)` (method call) is fine. `src/data` may use floats only in `*_loader.gd` / `*_parse.gd` |
| L004 | `class_name` prefix per dir: data `Def*`/`GameData`, map `Map*`, sim `Sim*`, net `Net*`, ai `Ai*`, view `View*`/`Fx*`, ui `Ui*`, audio `Snd*`, app `App*`; core free-form; names globally unique |
| L005 | dependency direction (core none; data no map/sim/view/...; map no sim/...; sim no view/ui/net/ai/audio/app; net, ai no view/ui/audio/app), by identifier prefix and by `res://src/<module>/` strings; `src/` never references `res://tests/` (excluded from exports). `SimRng`/`SimConfig` may live in core |
| L006 | `print printerr prints print_rich push_warning ...` in `src/` except `core/log.gd` (tests exempt; `push_error` allowed); `TODO` without `TODO(module)` |
| L007 | `.gd` file > 1500 lines |
| L008 | `var x = ...` / bare `var x` without type or `:=` in `src/{sim,core,map,data,net,ai}` |
| L009 | file name must be snake_case of its `class_name` (`SimWorld` -> `sim_world.gd`) |
| L010 | CRLF line endings in game text files (ARCHITECTURE section 10: LF only) |
| L000 | malformed `lint-allow` (unknown id or **no reason**; an invalid allow suppresses nothing) |

Escape hatch: `x = sqrt(n)  # lint-allow: L003 exact isqrt seed` (same line), or a comment-only line above it (applies to the next line),
or `# lint-allow-file: L003 reason` (whole file). In `.tscn/.tres/.cfg` use `;`. Audit with `python3 tools/py/lint.py --list-allows`.
GDScript warning levels are in `project.godot` `[debug]`: `integer_division` IGNORE (integer math is deliberate), `untyped_declaration` WARN,
`missing_await` WARN, `unused_signal`/`return_value_discarded`/`unsafe_*`/`inferred_declaration` IGNORE, everything else Godot's default
(`tests/fixtures` and `addons` excluded via `directory_rules`).

## 4. Cross-platform
* `tools/gd linux [--arch amd64|arm64] <cmd>`: image `meridian-linux-runner:<arch>` (Debian 12 slim, built from `tools/docker/Dockerfile`
  on first use: amd64 3m50s under emulation, arm64 4-5 min), Linux Godot mounted from `tools/godot-linux-<arch>`, mirror of `game/` in
  `.cache/linux-<arch>/` with its **own** `.godot`. Same `tools/gd` inside. Runs are serialised per arch. Only ever creates
  `meridian-*` containers/images (`--rm`; the public `debian:12-slim` base gets pulled). `--rebuild` rebuilds the image; `gd linux --reset` deletes the mirror. Output files: only `shot`'s out path is copied back.
  Measured: amd64 (emulated) cold import 30 s, warm `test` 4-14 s, `check` 2.8 s, `shot` 12-16 s (xvfb + Vulkan lavapipe);
  arm64 (native) warm `test` 2.5-5 s. **arm64 screenshots**: Debian 12's Mesa/LLVM 15 lavapipe aborts on aarch64 (`LLVM ERROR: Cannot select ... fs_variant_partial`)
  for Forward+ and Mobile, so `gd linux --arch arm64 shot` switches to `--rendering-method gl_compatibility` by itself (verified; amd64 renders all three).
* `python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_int_math.gd [-- --diverge=os|arch]`: scenario prints `HASH tick=N hex`;
  native + amd64 + arm64 containers run in parallel and are diffed. Result: **identical 10-hash chains on macOS arm64, linux/amd64, linux/arm64**;
  9 s warm, 39 s cold (import inside the containers; images already built). `--diverge=os` / `arch` inject a platform-dependent value at tick 60 and the tool reports
  `DIVERGENCE at tick 60 (last tick where all targets agreed: 40)` with each target's value, exit 1. CI mode: `--only-local --out F`, then `--compare a b c`.

## 5. Bible mirror, export, packaging, CI
* `python3 tools/py/sync_bible.py` copies `Input/meridian_agent_reference/meridian_factions.json` + schema **byte for byte** to
  `game/data/bible/` with `manifest.json` (sha256) and a "generated, do not edit" README; it refuses to overwrite hand-edited files
  (`--force` discards them); `--check` fails on edits or on a stale mirror (CI runs it).
* Export templates are installed in `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` (35 files, 2.07 GB, `version.txt`
  = `4.7.2.stable`): `python3 tools/py/export.py install-templates`. `python3 tools/py/fetch_engines.py --verify-only ...` re-checks
  all downloads against the official SHA512-SUMS.
* `python3 tools/py/export.py export windows|linux|macos|all` -> `builds/<platform>/` (holds the exclusive gd lock; `builds/export_report.json`).
  Measured (boot scene + data files): Windows `MeridianFracture.exe` 109,268,480 B + `MeridianFracture.console.exe` 188,928 B (stdout for logs/smoke; the release .exe is GUI-subsystem) + `.pck` ~0.8 MB (no rcedit/wine: `application/modify_resources=false`);
  Linux `MeridianFracture.x86_64` 73,519,416 B + `.pck`; macOS universal (x86_64+arm64) ad-hoc-signed `.app` 171.8 MB (`codesign --verify` OK,
  no notarisation). The exported macOS binary (`Contents/MacOS/Meridian Fracture`, note the space) was run with `--smoke` headless and windowed:
  `MERIDIAN_BOOT engine=4.7.2-stable renderer=forward_plus os=macOS debug=0`. The Windows exe cannot be run here (CI does).
  `*.json/*.csv/*.txt` data ships in the `.pck` via `include_filter`; `tests/*` is excluded.
* `python3 tools/py/package_windows.py` -> `.zip` (38.1 MB, includes the console wrapper). `python3 tools/py/package_linux.py [--test-deb]` -> `.tar.gz` (28.4 MB) and a `.deb`
  built in pure Python (28.4 MB): installs to `/opt/meridian-fracture`, `/usr/bin/meridian-fracture`, `.desktop` + 256px icon; `--test-deb` did
  `apt-get install` in Debian 12 (Depends resolved), ran `--headless --smoke` from `/opt` and via the symlink, `dpkg -r` (16-22 s).
* `.github/workflows/build.yml` (never pushed; YAML validated): `core.autocrlf false` first, matrix ubuntu/windows/macos = official Godot 4.7.2 + sha512, unit tests, bible check,
  `gd check --strict`, `gd test`, hash chain artifact, export + smoke, package, upload; a Debian-container job; a `determinism` job diffing the
  three runners' chains.
* Python tests: `python3 -m unittest discover -s tools/py/tests -v` (65 tests, 25-70 s: lint rules, locks, tracking, sync_bible, .deb structure, end-to-end gd against the engine).

## 6. Gotchas discovered
1. **Godot exits 0 after script errors** (parse errors, runtime errors). `gd run/shot` count `ERROR:`/`SCRIPT ERROR:` lines and force exit 3.
2. **A runtime error inside `_initialize()`/`_ready()` aborts that function before `quit()`; Godot then idles forever.** gd kills the process
   `--stall` seconds (run 20, test 60) after an error line with no further output (exit 124); runner.gd/check_scripts.gd also self-abort on the first frame.
3. `x as int >= 0` parses as `x as (int >= 0)`: `as` binds looser than comparisons. Parenthesise.
4. `ProjectSettings.set_setting` on warning levels only takes effect after `ProjectSettings.settings_changed.emit()` (GDScript caches them).
5. Locals named `root` (in a `SceneTree` script) or `fmod`/`round` shadow base-class members / builtins and warn.
6. macOS/Windows file systems are case-insensitive: only L001 (exact-case check) catches `res://src/Sim/x.gd` before Linux does.
7. `DirAccess.rename` is remove-then-rename, not atomic; concurrent writers of the same `user://` file can lose the rename (runner cleans up).
8. `--headless` has no renderer (`frame_post_draw` never fires): screenshots need a window (macOS) or xvfb (Linux, automatic in the container); DevShot exits 2 with `SHOT_FAIL` instead of hanging.
9. `get_stack()` and `Logger` backtraces exist only in debug builds; tests always run with the editor binary. `DevShot` is inert in release exports.
10. Parallel agents each get their own `--results` file from `gd test`; `user://last_test_run.json` is shared and last-writer-wins.
11. The Godot class XML has empty `<description>` tags in this checkout; `gd docs` is a signature/enum/signal/constant reference (and regenerates it with
    `godot --doctool` into `.cache/godot_docs` when `tools/godot_docs` is missing, e.g. on CI).
12. `project.godot` is shared: add autoloads / `[input]` actions by hand-editing only those sections, then `tools/gd check`.
13. A hung reader (endless loop in a test, no output) holds the shared lock until its hard timeout (test 600 s) and stalls every import behind it:
    `tools/gd ps` shows the pid; kill that process. Inside `src/core/fp.gd` call your own `sin()` as `Fp.sin()` (bare `sin(` is the float builtin, L003).

## 7. QA1 additions (exports of the full game, packages, performance, soak)
* `python3 tools/py/export.py export all`, then `python3 tools/py/export_proof.py`: static pck checks (`tools/py/pck_list.py FILE.pck --audit --project game`: no tests/tools/prototypes/docs/Input entries,
  every shippable project file present, the three pcks byte-identical), the exported macOS binary `--headless --smoke` + a 1200-tick headless autostart match, the exported Linux binary the same inside the
  Debian 12 amd64 container; the final chain/checksum must be identical on both. The Windows build is only checked statically (exe + pck sizes, pck identical to the Linux pck); CI executes it on a Windows runner.
  The exported scripts are TOKENIZED (`script_export_mode=2`): lint rule L011 forbids invisible characters (a U+FEFF string literal was silently emptied and cut the first byte off every JSON file in the pck).
  Exported GUI screenshot without a display: `Meridian\ Fracture --write-movie out.png --fixed-fps 30 --quit-after 240 -- --fresh-settings --no-audio`.
* `python3 tools/py/package_windows.py`, `python3 tools/py/package_linux.py --test-deb`: the .deb is installed in clean `debian:12-slim` and `debian:13-slim` containers (minimal install: Depends only), runs
  `--headless --smoke` + a headless match, then the Recommends stack + xvfb shows the real window (Vulkan / lavapipe). The engine dlopen()s everything except libc6: Depends = X11 + libvulkan1|libgl1 + libasound2|libpulse0 + udev + fontconfig + xkbcommon.
* Performance: `python3 tools/py/perf_run.py --players 8 --size 192 --quality high --game-min 5` (`--matrix` = 4p/8p x High/Low) runs a scripted GUI match through the app path with a real renderer
  (`--with-ui --bots=all --speed=200 --vsync=0`, dummy audio driver) and prints avg / p50 / p95 / p99 / worst frame ms, hitches, draw calls, entities, memory (AppPerfProbe, `--perf-log=<file>`).
  Game flags added for tools: `--quality=low|medium|high|ultra`, `--vsync=0|1`, `--window=WxH`, `--render-scale=F`, `--perf-log=F`, `--perf-every-ticks=N`.
* Soak: `python3 tools/py/soak_run.py --game-min 30 --players 8` (headless, real AI in all slots, FX/audio off then on with the dummy drivers): 0 engine errors, memory growth since the 25 % mark < 25 % / 150 MB,
  sim ms/tick avg + worst (NetLockstep.stats() `step_cost_total_us` / `step_cost_max_us` / `steps_timed`).
* Linux suites: run `tools/gd linux --arch amd64|arm64 test -q --stall 0 --timeout 2700` with nothing else heavy on the machine; `--stall 0` because the default 60 s silence-after-an-error watchdog
  kills a slow emulated run. amd64 is emulated (~1 core): ~40-60 min; arm64 native: ~8 min.
* .deb dependencies (Debian 12 bookworm / 13 trixie, verified by `package_linux.py --test-deb`): `Depends: libc6, libx11-6, libxcursor1, libxinerama1, libxext6, libxrandr2, libxrender1, libxi6,
  libxkbcommon0, libudev1, libfontconfig1, libvulkan1 | libgl1, libasound2 | libpulse0` (`libasound2` is provided by `libasound2t64` on trixie); `Recommends: mesa-vulkan-drivers | nvidia-vulkan-icd,
  libgl1-mesa-dri, libpulse0, libwayland-client0, libwayland-cursor0, libwayland-egl1, libdecor-0-0, libdbus-1-3`. The engine binary only links libc/libm/libdl/libpthread/librt; every other library
  is dlopen()ed, so a missing one degrades (no sound, no Wayland) instead of failing to start. Software rendering: `mesa-vulkan-drivers` (lavapipe) works (verified under xvfb).
* More test-boot flags (perf / QA only): `--stress-units=N --stress-at=T` (AppStress: N extra ground units per player dropped into the sim at tick T, LOCAL runs only: 8 players x 60 = 550 entities),
  `--focus=crowd` (camera on the densest spot), `--credits=N --unit-cap=N` (rules), `--perf-warmup=T`. `tests/bench/bench_sim_stages.gd` (per-system ms/tick at 540 entities; `phases=1` splits combat) and
  `tests/bench/bench_state_hash.gd` (checkpoint cost) are the sim profilers. `ViewModelBuilder.stat_sync_builds` counts models built synchronously mid-match (must stay 0 after the loading screen).
* Findings that shaped the code (QA1): the exported tokenized scripts lose invisible string literals (lint L011); the Compatibility renderer caps instance uniforms (rigs use plain uniforms there);
  `DefLayer3.checksum()` is cached (state checkpoint 9.3 -> 3.1 ms at 530 entities); every roster structure / summon / projectile model is prewarmed behind the loading screen;
  AI scenarios must `AiSoakKit.dispose(m)` (ctx.brain cycle); timing assertions in tests multiply their budget by `TestCtx.perf_factor()` (emulated amd64 is ~2.6x slower).

## 8. QA2 additions (final QA on the EXPORTED builds)
* `python3 tools/py/export_qa.py --binary "<exported exe>" --label macos-app --missions all [--editor-compare]` / `--docker amd64|arm64 --label linux-amd64`: headless proofs on the shipped
  binary + pck (smoke with the VERSION, bare `--bots` match, 4-player all-AI match, tutorial + operations, record then replay with identical `APPTEST_CK` lines); writes `builds/qa/<label>.json`;
  `--compare a.json b.json ...` requires identical checksum fingerprints across targets. `--docker arm64` runs the same `.pck` with the stock `linux_release.arm64` template (no arm64 preset is shipped).
  **The exported build has no `tests/` folder, so the SimBot test class does not exist there**: `--bots=all|human` only prints a warning (AI slots run the real AI, the human slot is idle), so the
  checksum chains differ from an editor run that used SimBot; with all-AI slots and no `--bots` the editor and the exported build print the identical chain (`--editor-compare` checks it).
  Operations need a real player: with an idle human they END with `lose` (the tutorial is time-gated and wins).
* `tools/py/quit_stress.py --binary PATH` and `tools/py/boot_stress.py --binary PATH` stress the exported app (engine ERROR lines scanned by the driver). Scenario `end_screen` is paced (`--speed=100`):
  an unpaced `--with-ui` run can finish the match before the game screen binds the session and then never reaches the end screen (test-only race, found by QA2).
* `tools/py/export_perf.py --binary PATH startup|perf|menu_rss`: start-up times (engine clock from AppQuitHook + wall), RSS sampled from `ps`, frame time from AppPerfProbe on the exported build.
* `tools/py/release_manifest.py`: `builds/RELEASE_MANIFEST.json` (size + sha256 of every package / binary / pck, merged builds/qa/*.json); `--check` re-hashes.
* GUI screenshots of the exported app: main menu `--write-movie /abs/path/menu.png --fixed-fps 30 --quit-after 150 -- --fresh-settings --no-audio` (frames `menu00000149.png`; give an ABSOLUTE path),
  live match `-- --autostart=match --with-ui --humans=1 --players=4 --speed=0 --cap=1800 --cap-out=/abs/prefix --quit-on-end` (without `--quit-on-end` a `--with-ui` run stays open).

* **Godot 4.7.2 engine bug: GDScript operator-cache race (found by QA2 with `boot_stress.py --binary` on the exported app: ~1 % of real-renderer match boots died with SIGSEGV in a WorkerThread inside
  `ViewRecipeInterpreter._num`; the crash handler's `caller thread can't call propagate_notification()` line that HARD1 chased is its side effect: `handle_crash` notifies the main loop from the crashing thread).**
  The VM stores the evaluator of an untyped operator (`match typeof(v)` patterns, Variant operands) in the function's bytecode on its FIRST execution and publishes it unsynchronised (type pair, then pointer);
  a second thread running the same fresh site reads a null / torn pointer and calls it. `python3 tools/py/gdscript_race_probe.py` reproduces it in isolation (fresh scripts, 8 threads: the cold run crashes
  every time, `--warm` never). Mitigation in the game: `ViewModelBuilder.WARM_MAX` (the first request of each of up to 24 distinct archetypes is built on the main thread before any worker starts; +0.15-0.3 s
  on the loading screen) and item 0 of every terrain `add_group_task` runs alone first. Rule for new code: do not start a burst of WorkerThreadPool tasks on a function that has never run; run it once on the calling thread first.
  Residual risk is a first execution of a rare site by two workers at once (not zero); retest after every engine upgrade and report upstream.

## 9. HOT1 additions (hotkeys connected, key-probe regression)

- `tools/gd test hot1 -q` (about 8 s): `tests/ui/test_hot1_keys.gd` builds a real LOCAL match (real `NetSession`, `UiSimPortWorld`, command bus, presenter, input controller) behind a `UiScreenGame` in a 1920x1080 harness and pushes an `InputEventKey` for **every default binding of every action in `data/ui/keymap_defaults.json`** (~150 bindings in the player match, the observer actions on the golden replay, `toggle_objectives` in the tutorial). Each probe asserts an observable effect: a command seen by a spy net port (which still forwards to the session), an armed mode, a camera move, a selection, a dialog, a message, a file. `test_every_action_is_probed_or_exempt` fails when an action has neither a probe nor an `EXEMPT` entry (with the reason and the test that covers it): a new keymap action cannot ship unconnected.
- `tests/ui/test_hot1_texts.gd` checks every key the shipped texts name (tutorial, missions, loading tips) against the default keymap and against the probe table.
- `tests/ui/test_hot1_settings.gd`: the Options rows that reach the game screen.
- GUI proof of a key in a live match: `tools/gd shot res://src/app/boot.tscn out.png --size 1920x1080 --frames 1800 --allow-errors -- --autostart=match --with-ui --players=2 --humans=1 --map-seed=5 --fresh-settings --scenario=showcase --sw-at=0 --keys="F5@70;movehq:5,0@75;clickhq:5,0@110;F8@150;movehq:8,2@155" --cap=95,135,175 --cap-out=/tmp/live` (images of the run: `docs/shots/hot1/`).
- Pillow is not installed on the maintainer's machine; to edit an image use Godot (`Image`) from a `tools/gd run` script, or recapture it (`--lan-address` keeps the private address out of the lobby shot).
