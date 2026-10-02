# Release checklist

Run from the repository root. `VERSION` is the only place a version is typed; everything else is stamped from it. Caveat that applies
to every release: **the Windows build has never been executed on a Windows host by the maintainers** (CI executes the exported `.exe`
on a Windows runner; a human must still run it once, see "Manual checks").

## 1. Version and changelog

```
python3 tools/py/version.py bump minor        # or patch | major | X.Y.Z ; stamps project.godot, export_presets.cfg, README badge + file names
$EDITOR CHANGELOG.md                          # add '## [X.Y.Z] - date' (move items out of [Unreleased])
python3 tools/py/version.py check             # must print 'version X.Y.Z consistent'
```

Commit the stamped files; tag the exact commit that passes sections 2 to 5 (`git tag -a vX.Y.Z -m "Meridian Fracture X.Y.Z"`; release candidates `vX.Y.Z-rcN`). Packages in `builds/` are not versioned: publish them as release assets next to the tag.

If the emblem or colours changed: `pip install pillow && python3 tools/py/gen_app_icon.py` (rewrites `game/assets/icons/`), then
`python3 tools/py/gen_app_icon.py --check`.

## 2. Tests (macOS or the dev host)

```
python3 -m unittest discover -s tools/py/tests                         # python tooling (needs: pip install pillow pyyaml for the icon / workflow tests)
tools/gd check --strict                                                # lint + compile, must be clean
tools/gd test -q --timeout 2700 --stall 0                              # FULL suite, ~7-13 min, nothing else heavy running
tools/gd linux --arch arm64 check --strict && tools/gd linux --arch arm64 test -q --stall 0 --timeout 2700
tools/gd linux --arch amd64 test -q --stall 0 --timeout 5400           # emulated on Apple silicon: slow
```

## 3. Determinism

```
for f in game/tests/scenarios/xplat_*.gd; do s=$(basename $f .gd)   # all 20 (sim, maps, AI, net, mission, replay ...)
  python3 tools/py/xplat_determinism.py res://tests/scenarios/$s.gd --targets native,amd64,arm64   # chains identical across OS / CPU
done
python3 tools/py/app_replay_proof.py          # replay proof
python3 tools/py/app_two_process.py           # LAN, two processes (add --linux --arch amd64 for the container; --binary <exported exe> for the exported app)
```

## 4. Export, packages, smoke

```
python3 tools/py/export.py install-templates --tpz <Godot_v4.7.2-stable_export_templates.tpz>     # once
python3 tools/py/export.py export all         # builds/{windows,linux,macos}; smoke runs on the host OS; pck ~99 MB identical on all OSes
python3 tools/py/pck_list.py builds/linux/MeridianFracture.pck --audit --project game
python3 tools/py/package_windows.py           # .zip (exe, console exe, pck, .ico, README)
python3 tools/py/package_linux.py --test-deb  # .tar.gz + .deb, installs the .deb in debian:12-slim and 13-slim containers
python3 tools/py/package_macos.py             # .dmg + .zip; verifies icon, version, ad-hoc signature, hdiutil verify/attach/detach
python3 tools/py/version.py check --packages  # every package name and the .deb control Version carry the release version
```

Exported-build smoke (the CI step does the same): `"builds/macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture" --headless -- --autostart=match --ticks=1200 --speed=0 --bots --fresh-settings --no-audio`
must end with `APPTEST_END reason=ticks tick=1200`; the `APPTEST tick=1200` line must be identical on every OS.

Windows icon limitation: without `rcedit` (or wine + rcedit) on the export host the `.exe` cannot get its icon and version resource embedded,
so `application/modify_resources=false` stays and the zip ships `MeridianFracture.ico` beside the exe. The window / taskbar icon at runtime
comes from the project icon (`application/config/icon`). To embed it: install rcedit, set `export/windows/rcedit` in the editor settings,
set `application/modify_resources=true`, re-export on that host.

## 4b. Exported-build proofs (QA2)

```
python3 tools/py/export_qa.py --binary "builds/macos/MeridianFracture.app/Contents/MacOS/Meridian Fracture" --label macos-app --missions all --editor-compare
python3 tools/py/export_qa.py --docker amd64 --label linux-amd64 --missions all ; python3 tools/py/export_qa.py --docker arm64 --label linux-arm64 --missions all
python3 tools/py/export_qa.py --compare builds/qa/macos-app.json builds/qa/linux-amd64.json builds/qa/linux-arm64.json   # IDENTICAL
python3 tools/py/win_static_check.py          # Windows: static only, the .exe is never executed here
python3 tools/py/quit_stress.py --binary "<exported exe>" --iterations 60 --jobs 2 ; python3 tools/py/boot_stress.py --binary "<exported exe>" --iterations 60
python3 tools/py/export_perf.py --binary "<exported exe>" startup|menu_rss|perf --players 4 --size 192 --game-min 30 --speed 200   # keep the machine idle: a covered window or other load doubles the frame times
python3 tools/py/release_manifest.py          # builds/RELEASE_MANIFEST.json (sizes + sha256 + QA results); --check after any rebuild
```

## 5. Stress

```
python3 tools/py/quit_stress.py --headless --iterations 20 --seed 1 --timeout 90 --jobs 2
python3 tools/py/boot_stress.py
python3 tools/py/soak_run.py --game-min 30 --players 8 --out soak      # nightly in CI; optional locally
```

## 6. macOS Gatekeeper (what testers see)

The app is **ad-hoc signed, not notarized**. Downloaded copies are quarantined; first launch: right click the app, Open, Open again; or
`xattr -dr com.apple.quarantine /Applications/MeridianFracture.app`. Notarization needs a paid Apple Developer account, a
"Developer ID Application" certificate, signing with `--options runtime --timestamp` plus entitlements, `xcrun notarytool submit <dmg> --wait`
and `xcrun stapler staple`; it has not been attempted. Windows SmartScreen: More info, Run anyway (unsigned).

## 7. CI

GitHub Actions are disabled on `x42553/meridian-fracture` until a first CI run is wanted (private repositories pay for macOS and Windows runner minutes; the nightly soak runs 30 minutes): enable them first with `gh api -X PUT repos/x42553/meridian-fracture/actions/permissions -F enabled=true` or Settings > Actions > General. Then push; `.github/workflows/build.yml` runs the version check, icon check, all suites, determinism diff, exports, packages (incl. the DMG on the
macOS runner) and uploads `meridian-fracture-<version>-<platform>` artifacts. Download them for step 8.

## 8. Manual checks only a human can do

- [ ] Windows: run `MeridianFracture.exe` from the zip on a real Windows 10/11 PC (window icon, menu, a skirmish, quit; SmartScreen and firewall prompts as documented).
- [ ] Real two-machine LAN game (different OSes if possible), 10+ minutes, no desync; discovery and direct address.
- [ ] Listen to the audio: music, effects, announcer, volume sliders, mute.
- [ ] Playtest a full skirmish, the tutorial and at least one campaign operation start to finish.
- [ ] macOS: open the `.dmg`, drag to Applications, first launch via right click Open; Dock / Finder show the emblem icon.
- [ ] Linux: `sudo apt install ./meridian-fracture_X.Y.Z_amd64.deb`, menu entry shows the icon, game starts.
- [ ] Main menu footer and `--smoke` line show `vX.Y.Z`.


## 9. Results of the final QA pass (task QA2, version 0.1.0, macOS arm64 host M5 Max, Debian 12 containers)

Everything below ran on the final source; artifacts, sizes and sha256 are in `builds/RELEASE_MANIFEST.json`, raw logs in `builds/qa/logs2/`.
**The Windows `.exe` was NOT executed (no Windows host): static checks only.** Nobody listened to the audio; no real two-machine LAN game was played.

| What | Where | Result |
|---|---|---|
| `tools/gd check --strict` | macOS, Linux arm64 | 0 errors, 0 lint violations, 0 warnings |
| Full suite (2448 tests) | macOS arm64 / Linux arm64 / Linux amd64 (emulated) | 2448/2448 on each (12 min / 11.6 min / 21 min) |
| `python3 -m unittest discover -s tools/py/tests` | macOS (venv with pillow + pyyaml) | 195 OK, 0 skipped (system python: 2 skipped without Pillow/PyYAML) |
| validate_balance --strict, validate_recipes --strict, check_rules_data, validate_missions --strict, validate_audio --strict | macOS | all clean |
| xplat determinism, all 20 `tests/scenarios/xplat_*.gd` (incl. mission, net_replay, soak, ai) | macOS vs Linux amd64 vs Linux arm64 | identical hash chains in all 20 |
| app_two_process (LAN, 2 processes, 3000 ticks) | editor macOS, Linux amd64, Linux arm64, EXPORTED macOS app | OK, host and client identical |
| app_replay_proof | macOS, Linux container | OK |
| Exported macOS .app, the app inside the .dmg, exported Linux amd64 (container) and the same pck on the arm64 template: smoke, 2p `--bots` match, 4p all-AI match, tutorial (WIN) + 8 operations (load from the pck, end `lose` with the idle human), record + replay | 4 targets | 14/14 steps each; fingerprints IDENTICAL across the 4 (editor-equal on macOS) |
| `.deb` install, run, remove | clean debian:12-slim and debian:13-slim | OK |
| Windows static check (`win_static_check.py`) | PE32+ x86-64 GUI + console exe, external pck, engine-default version resource (no rcedit), pck sha256 identical to Linux/macOS, zip members; CI Windows job runs `--smoke`, a 1200-tick headless match and export_qa on the console exe | OK, **not executed** |
| pck | all three exports | 100.46 MB (99.8 MB payload), sha256 13e4a2a2...783ad2 byte-identical; 7 files absent on purpose (`assets/icons/set/*`, `.gdignore`) |
| quit_stress on the exported app | GPU 60 runs / headless 60 runs | 0 hangs, 0 crashes (8 + 8 tolerated shutdown-leak lines in `raw` quit mode; 1 headless `tree` run printed leak lines, exit code 0) |
| boot_stress on the exported app | 60 boots + 1000 boots (4 parallel) | 0 crashes, 0 hangs (see the engine bug below) |
| GUI screenshots of the exported app | `builds/qa/shots/final/main_menu.png`, `live_match.png` | reviewed: menu with `v0.1.0` footer, live 4-player match HUD |
| Cold start (engine clock / wall, first launch of 5) | main menu / match 96x96 / match 192x192 | 1.65 s / 2.58 s / 2.78 s (medians 1.61 / 2.70 / 2.77 s) |
| Resident memory | menu / 4p 192 match at 1 min / after 30 game-min | 607 MB / 710 MB / 730 MB (no growth trend) |
| Frame time, 1080p, 4 players, 192x192, High, vsync off, real Metal | 5 game-min at 1x / 30 game-min at 2x | p95 10.7 ms (avg 3.7) / p95 10.96 ms, p99 16.8 ms, worst 26 ms, 0 hitches > 33 ms, 0 engine errors |

Real bug found and fixed in this pass: **Godot 4.7.2 GDScript operator-cache race** (about 1 % of real-renderer match starts of the exported build crashed with SIGSEGV in a
WorkerThread; HARD1's unexplained "caller thread can't call propagate_notification" line is the crash handler's side effect). Mitigation: `ViewModelBuilder.WARM_MAX`
(first request of each of 24 distinct archetypes is built on the main thread before workers run, +0.15 to 0.3 s loading), terrain group tasks run item 0 alone first, regression test
`tests/view/test_view_model_warm.gd`, isolated reproducer `tools/py/gdscript_race_probe.py` (cold: crashes every run, warm: never). After the fix: 0 crashes in 1,000 boots (before: 4 in about 390).

Remaining risks: Windows exe never run (and no embedded icon / version resource); audio never heard; no real LAN between two machines; the engine race is mitigated, not removed
(rare never-run code paths started by two workers at once); macOS build is ad-hoc signed, not notarized; frame-time numbers are valid only on an idle machine (two runs taken while the
window was partly covered / the machine busy showed p95 33 ms and 98 ms: do not use them); `quit` within 200 ms of a headless match start can print engine leak lines (exit code 0).
