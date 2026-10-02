# Known issues and limits

State of v0.1.0, compiled from the orchestration log ([STATE.md](STATE.md)), the per-task reports ([DEVIATIONS.md](DEVIATIONS.md), `tools/spec dev <label>`) and from running every documented command and key during the final documentation pass (task DOC2). Items are ordered by how likely a player or a maintainer is to hit them. "Found by DOC2" means it was newly discovered while verifying the documentation.

## 1. Never verified (needs a human or hardware the project did not have)

| What | Status |
|---|---|
| **Windows executable** | Built by the exporter and run by CI on a real Windows runner since 2026-10-02: the exported console exe passes its smoke test, plays a headless bot match, the tutorial and an operation, records and replays a match, and ends the same match on the same hash chain as the Linux and macOS builds; the whole test suite passes on that runner too. **Not yet run by a person on a real Windows PC**: window, input, audio device, the missing embedded icon (it needs `rcedit`; the `.ico` ships beside the exe), SmartScreen and firewall prompts (documented, not observed). Tracked in #1 and #8. |
| **Audio by ear** | 492 sound effects, 17 music tracks with stems, stingers and 513 announcer lines are synthesised and wired. They were checked by measurement (loudness, budgets, voice counts, no errors on the dummy audio driver) and never listened to by a person: mix, ducking depth, music transitions and the voice quality are unjudged. |
| **LAN between two real computers** | Proven with two real game processes on one machine over loopback (macOS and Linux amd64; arm64 in-process), including fault injection and forced desync. Not tested over Wi-Fi, a VPN, between physical machines or with Windows. |
| **Balance with humans** | Numbers were tuned by AI-versus-AI play only (BAL2, BAL3, AIT). Whether the factions are fun and fair for people is unknown; the AI round robin measures economy and army survival more than unit strength. |
| **Low-end hardware** | Measured on an Apple M5 Max and in Linux containers. The 60 FPS at 1080p target for a 2019 4-core with an integrated GPU is a target, not a measurement. A cheaper rendering path for Mobile/Compatibility (batched instances) is not built. |
| **macOS Gatekeeper, notarization** | The app is ad-hoc signed, not notarized (needs a paid Apple Developer account). First launch needs right click > Open. A real DMG install on a clean Mac was not done. |
| **Debian real device** | The `.deb` installs and starts in Debian 12 and 13 containers; no real desktop session (menu entry, icon) was checked. |
| **CI** | Enabled on 2026-10-02 (the repository is public, so GitHub-hosted runners are free). The first runs found eight problems in the workflow and its tools (#25 to #32, fixed; #30, a check that can never fail, is still open). Run 37008439730 is green: Python tool tests, the 12 test shards on Linux, Windows and macOS runners, hash chains compared across the three, exports and packages for all three, the `.deb` install in Debian 12 and 13, and the full suite in Debian 12 containers (amd64 and arm64). A nightly soak runs at 03:17 UTC on `main`; a push cancels the run in progress for the same branch. |
| **License** | The MIT license is a placeholder; the owner may change it. |

## 2. Input: the keyboard shortcuts (connected by HOT1; was: listed but not connected)

DOC2 found that about 45 of the 159 registered keymap actions had no handler in the game screen (the powers `F5` to `F8`, build-card keys, tabs, `Space`, `M`, `Y`, `J`, `T`, abilities, scuttle, chat, `F4`, `Print`, `Alt+Enter`, the camera pad, ...). They are connected now: every default key of every action is pressed as a real key event in a live match by the regression test `tests/ui/test_hot1_keys.gd` (player match, the golden replay's observer HUD and a scripted mission), and the test fails for any new action that has neither a probe nor a reasoned exemption. [CONTROLS.md](CONTROLS.md) is regenerated from the code and has no dagger left. What is still true:

- **`F2` (scoreboard)** works only for observers and in replays (it would show the opponents' economy in a normal match); `cmd_ping` and `hide_ui` also work for observers.
- **`Print` and `Alt+Enter`** work inside a match only (Options > Graphics has the same fullscreen setting for the menus). `Print` writes a PNG to `user://screenshots/`; headless runs have no frame and say so.
- **Chat** (`Enter`, `Shift+Enter`) works in LAN matches (the net layer's in-match channel, recorded in replays when "chat recording" is on). A single-player match and a replay have nobody to talk to, so the key says that. The UI half is tested; no two real machines exchanged a chat line.
- **`I O K L`**: no shipped unit has more than one ability-bar ability, so `O K L` find no button; `I` works (a test fails when data adds a unit with two, so the probe gets extended).
- **Pings** are relayed to teammates only (host rules); alone you see your own marker and the sound.
- Options rows that still do nothing (found while connecting the keys): **Sidebar side**, **Selection brackets**, **Zoomed-out markers**, **Cursor confinement** and **Sidebar hover hotkeys**. (The camera pad, minimap sweep, sticky modes, move speed match, reverse, group double-tap centring, Esc clears selection and pause on focus loss are connected now.)
- **Veterancy**: the rule exists in the simulation and in saved setups, but it has no effect, so the lobby no longer offers the switch.

## 3. Features that do not exist

- **Spectating a running LAN match** and late-join catch-up: spectators can sit in the lobby and are removed at launch. Watch the replay afterwards.
- **Co-op and multi-human missions**: missions are single-player (one human slot); no LAN missions.
- In-match chat outside LAN matches, a rally-point or build-queue UI beyond what the sidebar shows.
- **Veterancy** (no switch in the lobby), more maps and biomes beyond the three generated families.
- Mission engine: no `hide_area`, no power or knob overrides, no superweapon lock.
- AI: siege operations still destroy almost nothing (artillery rosters are under-measured), no second parallel attack wave, no SELL intent (an AI with an empty bank and no Collectors cannot recover), no spotters.

## 4. Balance and AI (measured, not felt)

- After BAL3 no roster is outside 35 to 65 % in the 1,140-match Hard AI round robin (sd 6.4). Residual low: Australia 39, Nordics 39, Alpine 39, ae.vanilla 41, han.vanilla 41; high: India 65, Nigeria 61, SAP vanilla 59, PD vanilla 58 (n = 54 to 96 per roster, error about +/- 8). Eurocorps and Australia are fixed only through AI dials; a human playing them may find them weak (cost and build-time modifiers cannot be compensated by numbers).
- The first superweapon strike in AI matches comes after about minute 20 (Laboratory prerequisite plus a 7 to 8 minute first recharge); the 16-minute test cap ends before superweapons fire, so their balance was not measured. Structures, defenses and superweapon numbers were not retuned.
- The AI is army-light before minute five (about three units at 4:30); a determined early rush can beat it.
- Missions: no human playtest. A scripted bot wins 47 of 48 harness runs and an idle player never wins, but the plain skirmish bot (`--bots=human`) loses `op_napc`, `op_nec` and `op_olm` at Medium, as expected; only Medium was benchmarked (Easy and Hard shift AI levels without measurement); op_han (seed 31337) and op_olm have thin margins; a Hard AI alone cannot finish the objective-driven operations.
- Mission difficulty shifts AI levels only; credits and objectives are not scaled.

## 5. Presentation and UI

- The Esc menu says "Surrender" in missions (it ends the mission as a defeat); the result screen has a large empty lower area at 1080p; the observer sidebar leaves empty space under the player list; replays and observers wear the neutral HUD skin; message plates time out in real time even while paused; a Field Manual link from a briefing opens the roster but may not scroll to every entry type; the lobby model viewer uses the faction accent instead of the slot colour.
- Replay: no world keyframes (a backward seek re-simulates from tick 0, a few seconds for a three-minute match); the event list holds only recorded status and chat events plus eliminations seen while watching; replays recorded with different balance data warn that they may diverge, and the test fixtures in `game/tests/fixtures/net/replays` must be regenerated after any intended data change that alters play.
- Visual polish not reviewed or not captured live: beams (Helios sweep, thermal), EMP and burning wrecks in a full match (covered by FX contact sheets and tests); the Trident and microwave domes can read milky at close range; per-subfaction unique-unit sheets exist but were not all reviewed at 720p.
- Unconfirmed engine-level crashes: a SIGABRT with an extreme far camera (not reproduced in 59 real-renderer runs) and an early `caller thread can't call propagate_notification` message (2 of 20 boots in one early batch, then none in more than 330 boots; the thread guard now names the thread if it returns).
- Under the real renderer the engine prints leak lines at exit (`RIDs of type Texture were leaked`, `resources still in use at exit`); they are expected noise with `--allow-errors` and do not affect the exit code of the game. A bare `SceneTree.quit()` with suspended coroutines still prints them; it no longer hangs or crashes.

## 6. Engineering

- **Version control:** the history starts at the v0.1.0 release candidate (tag `v0.1.0-rc1`, branch `main`; remote `origin` is the public GitHub repository `x42553/meridian-fracture` (public since 2026-10-02); commits carry the machine's global git identity). `docs/shots/` (about 835 MB of working screenshots, not documentation) is git-ignored; delete it if you need the disk space; `docs/img/` (about 25 MB) is the curated set that is versioned. Packages (`builds/`), the engines in `tools/` and the import cache `game/.godot/` are git-ignored too (`tools/setup` re-creates the engines and the cache on a fresh clone).
- Hotkeys: `tests/ui/test_hot1_keys.gd` presses every default key in a live match and checks an effect (section 2); most other screens' unit tests still cover pure models.
- Data hash: `terrain.json` and `map_gen.json` are now covered through the manifest and the join reject names the differing file, but the launch-time check reports only "game data mismatch" with hash numbers, and `MapTerrain` and `MapGenTables` still read those two files from disk themselves.
- The Python tests need Pillow and PyYAML installed (`pip install pillow pyyaml`) for the icon and workflow checks; `tools/py/gen_app_icon.py` needs Pillow.
- **Godot 4.7.2 engine bug (mitigated, not eliminated):** the GDScript VM caches an untyped operator's evaluator on its first execution without synchronisation, so a burst of worker threads starting the same never-run function can crash with SIGSEGV. Before QA2 about 1 % of real-renderer match starts of the exported build crashed this way (`ViewRecipeInterpreter._num`); the first model builds now run on the main thread (`ViewModelBuilder.WARM_MAX`) and terrain group tasks run item 0 alone first: 0 crashes in 1,000 boots afterwards (one crash in the 600 boots before the warm set was widened to 24 archetypes). A rare, never-executed code path run by two workers in the same instant could still hit it. `python3 tools/py/gdscript_race_probe.py` reproduces the bug in isolation; retest on every Godot upgrade (see `docs/spec/qa_tooling.md` section 8).
- Quitting within about 200 ms of a headless match start (test flags only) can print `resources still in use at exit` engine lines (exit code 0, no hang or crash; seen in 1 of 60 randomised exported-build quit runs).
- Release engineering gaps: Windows icon embedding and signing, macOS notarization (accounts and tools the project does not have).
- Everything else the orchestration log lists as "Remaining" (human playtest, listening, Windows run, two-machine LAN game, Debian real device, GPU path, notarization, first CI run, license choice, coop missions, spectators, siege and veterancy) is contained in sections 1 to 4 above.
