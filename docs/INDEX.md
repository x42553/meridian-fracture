# Documentation index

A map of everything under `docs/` and the top level, how to navigate the very large design specs, and a plain statement of what has and has not been verified.

## 1. For players

| Document | Read it for |
|---|---|
| [../README.md](../README.md) | What the game is, features, requirements, installing a build, quick start, status |
| [USER_MANUAL.md](USER_MANUAL.md) | How to play: skirmish setup, economy, tech, units and counters, powers and superweapons, factions, maps, neutrals, AI behaviour and difficulty, the campaign and tutorial, replays and the observer view, the Field Manual and its 3D viewer, options, hotkeys |
| [CONTROLS.md](CONTROLS.md) | Every mouse action and key (generated from the real keymap; every key is connected and pressed by a regression test, a dagger would mark one that is not) |
| [FACTIONS.md](FACTIONS.md) | The setting, the 8 factions, 24 subfactions, rosters, powers and superweapons (generated from the design bible) |
| [units/README.md](units/README.md) and `units/<faction>.md` | Generated stats of every unit and structure (cost, build time, health, armor, speed, vision, DPS, range) |
| [LAN_GUIDE.md](LAN_GUIDE.md) | Hosting and joining, ports, firewalls, version mismatches, desync packages, stalls |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Open items, limits and what does not exist |
| [../CHANGELOG.md](../CHANGELOG.md) | Release notes |
| [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), [../LICENSE](../LICENSE) | Licences of everything shipped or used to build (the MIT license is a placeholder the owner may change) |

Screenshots used by the documents are in `img/` (1920x1080, captured from the real game; see DEVELOPMENT.md, "Screenshots for the documentation").

## 2. For contributors

| Document | Read it for |
|---|---|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Repository layout, `tools/gd`, launch flags, determinism rules, tests, validators and waivers, stability and stress scripts, adding units, factions and models, the mission system and **how to author a mission** (schema reference, Python DSL), replay tools, audio pipeline, export, packaging, release scripts, CI |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The technical constitution: modules, boundaries, the determinism contract |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | Release steps and the manual checks only a human can do |
| [RULES_DATA_NOTES.md](RULES_DATA_NOTES.md) | Extensions to the authored rules data files |
| [balance/FRAMEWORK.md](balance/FRAMEWORK.md), [balance/TAXONOMY.md](balance/TAXONOMY.md) | The balance method (fair-cost bands, archetypes) and the damage and armor taxonomy |
| `factions/*.md` | Per-faction design notes behind the data |
| `spikes/*.md` | Findings of the first technical spikes (audio, models, terrain, UI, effects): proven engine behaviour |
| `perf/` | Raw measurement logs (frame times by player count, quality, renderer; soak runs) |

### Project history

| Document | Contents |
|---|---|
| [STATE.md](STATE.md) | The orchestration log: what each wave built, token accounting, open items |
| [DEVIATIONS.md](DEVIATIONS.md) (3,000+ lines) | The finished-task reports: summary, deviations downstream code relies on, tests, known gaps, cross-module requests. Do not read it whole: `tools/spec dev <label prefix>` prints one report (labels such as `QA1 HARD1 BAL3 AIT MIS1 MIS2 MIS3 REP1 REP2 VQ2A VQ2B DOC1 DOC2 INT3`) |
| `shots/` | Working screenshots of the agents (about 830 MB). Not documentation; exclude or delete before publishing the repository |

## 3. The design specs (`docs/spec/`) and how to navigate them

The 15 specs are up to 500 KB each (3.4 MB together) and follow a 13-heading format (1 Purpose, 2 Files and classes, 3 Public API, 4 Data structures, 5 Rules and algorithms, 6 Commands and events, 7 Data schemas, 8 Determinism, 9 Performance, 10 Tests, 11 Work breakdown, 12 Risks, 13 Cross-module requests). **Never read one whole.** Use the navigator:

```
tools/spec sizes                          # every spec with the size of each numbered section
tools/spec list ui                        # table of contents of one spec (line ranges)
tools/spec show economy 5.3 5.7           # print sections 5.3 to 5.7 of the economy spec
tools/spec grep ui "drag|Shift"           # regex search across one spec (or all)
tools/spec dev BAL3                       # a task report from DEVIATIONS.md
```

`docs/spec/INDEX.md` is the generated line-range index. Which spec answers what:

| Spec | Topic |
|---|---|
| `sim_core` | The deterministic kernel: world, entities, ticks, commands, checksums (the master) |
| `terrain_movement` | Map generation, terrain, pathfinding, movement |
| `combat`, `abilities`, `abilities_catalog` | Weapons, damage, armor; abilities, stealth, vision, zones, transports, summons |
| `economy` | Credits, power, production, research, powers, superweapons, capture |
| `ai` | The skirmish AI |
| `net` | Lockstep, lobby (spectators can sit there, not watch a running match), discovery, desync, replays, in-match chat and pings |
| `render` (and `art_direction`) | The view layer, models and recipes, effects, camera |
| `ui` | Screens, HUD, input, options, Field Manual, campaign and replay UI |
| `audio` | Sound design and runtime |
| `data_balance` | Data files, schemas, balance targets |
| `qa`, `qa_tooling` | Test strategy; the tooling manual (sections 4 and 5 cover cross-platform, export, packaging and CI) |

The specs describe the *design*; where the code deviates, the deviation is recorded in DEVIATIONS.md and the code and the tests win.

## 4. What is verified and what is not

| Area | Verified by | Not verified |
|---|---|---|
| Simulation, rules, AI, missions, replays | About 2,400 automated tests on macOS arm64 and Linux arm64 and amd64; golden hashes; six cross-OS determinism scenarios identical on macOS and both Linux CPUs; soaks of 96 matches over all 32 rosters and 8 players for 30 minutes with zero errors; replay proof; mission harness (bot wins 47 of 48 runs, idle never) | **Windows** (never run); cross-OS Windows hashes exist only as a CI step that never ran |
| Balance | AI round robins (BAL2, BAL3, AIT): 100 unit sheets in the fair-cost band, 1,140 Hard matches with every roster between 35 and 65 % | **Human playtest** (none); superweapon balance; whether the game is fun |
| Rendering, UI, screens | Real-renderer screenshots of every screen and many live frames (all images in `docs/img`), UI unit tests, 720p and 1080p reviews, 100 real-renderer boots and 68 + 30 quit-stress runs without hang or crash, 120 FPS cap at about 550 entities (p95 10.6 ms) on an Apple M5 Max | Integrated or low-end GPUs; Windows; a few Options rows that do nothing (see KNOWN_ISSUES section 2) |
| Audio | Generated and measured (loudness, budgets, no errors on the dummy driver) | **Never listened to by a human** |
| LAN | Two real game processes over loopback, with fault injection and forced desync, identical checksums on macOS and Linux amd64 | **No game between two real machines**, no Windows peer |
| Builds and packages | Exports for Windows, Linux and macOS (the `.pck` is byte-identical on all OSes); exported macOS and Linux builds play a headless match; `.deb` installs in Debian 12 and 13 containers; DMG verify and attach | The Windows exe was never executed; macOS notarization and signing certificates; Windows icon embedding; a real Debian desktop |
| CI | A workflow file, sanity-tested offline | Never executed on GitHub |
| Documentation | Every command in README, DEVELOPMENT, LAN_GUIDE and this index was executed by the author on macOS (the `tools/gd linux` ones in a container); every key in CONTROLS.md was checked in the code and the main ones pressed in a running match; every screenshot was looked at | The Windows and macOS install steps are taken from the packaging scripts, not performed on a clean machine |

Everywhere this documentation talks about Windows it means: the build is produced and the code is portable, but the executable has never been run.
