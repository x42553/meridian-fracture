# Project state

_Maintained by the assistant that orchestrated the build. Last updated 2026-10-02 (v0.1.0 release candidate). Detailed per-task reports: `docs/DEVIATIONS.md` (`tools/spec dev <label>`); open problems: `docs/KNOWN_ISSUES.md`; release steps: `docs/RELEASE_CHECKLIST.md`; documentation map: `docs/INDEX.md`._

## Status

**Meridian Fracture v0.1.0 — release candidate.** A complete real-time strategy game in Godot 4.7.2 (GDScript only): 8 factions x 4 rosters (32 playable rosters) from the design bible in `Input/`, deterministic lockstep simulation, skirmish AI (4 difficulty levels), LAN multiplayer, replays with an observer mode, a tutorial plus 8 faction operations, procedural art and audio.

| Area | State |
|---|---|
| Rules | 156 units, 29 structures, 40 research upgrades, 48 support powers, 8 superweapons, abilities/zones/summons/engineers, fog and stealth — all data-driven (`game/data/`), all implemented |
| Simulation | integer-only deterministic; macOS arm64 = Linux amd64 = Linux arm64 on 20 hash-chain scenarios |
| AI | economy, expansion, production/composition, scouting, attack/defend/harass/hunt, siege, micro, naval/air/amphibious, powers and superweapons, dispersal; Medium-vs-Medium ends by elimination ~32 % of the time, Hard beats Easy 30/32 by elimination |
| Network | NetSession (LOCAL/HOST/CLIENT), lobby, UDP discovery, lockstep, desync detection; two-process ENet proofs identical on macOS and Linux |
| Presentation | procedural models per faction/subfaction, terrain/water/atmosphere/moods, FX (191 effects), HUD, menus, Field Manual with 3D viewer, options, campaign UI, replays/observer UI |
| Audio | 492 SFX, 17 music tracks x 4 stems, 25 stingers, 513 announcer lines (Kokoro TTS, Apache-2.0), unit responses; runtime wired |
| Tests | 2,448 tests green on macOS arm64, Linux arm64 and Linux amd64; `tools/gd check --strict` clean; ~153k lines of game code, ~87k lines of tests, ~32k lines of Python tooling; a fresh `git clone` (only the engine linked in) passes the same suite and `check --strict` (2,448/2,448, 691 s, macOS arm64) and the 195 Python tool tests |
| Packages | macOS universal `.dmg` + `.zip`, Linux `.tar.gz` + amd64 `.deb`, Windows `.zip` (`builds/packages/`, checksums in `builds/RELEASE_MANIFEST.json`; `builds/` is not versioned) |
| Version control | git, branch `main`, history starts at this release candidate (tag `v0.1.0-rc1`); no remote, nothing pushed; `docs/shots/` (835 MB working screenshots), `builds/`, `.backups/`, engines and the import cache are git-ignored |
| Performance | exported macOS build: 1.65 s to menu, 2.6 s to a running match; frame time p95 10.7 ms at 1080p, 4 players, 192x192 (M5 Max); RSS ~710 MB in a match |

## Not verified (needs a human or other hardware)

- The **Windows executable has never been run** (static checks only; the exe has no embedded icon/version resource — needs rcedit/wine).
- **Audio was never listened to**; it was measured (loudness, true peak, spectrograms, loop seams) only.
- **No real two-machine LAN game** was played (all multi-process proofs ran on one machine; in-match chat/pings untested on two real machines).
- **No human playtest**: balance was tuned by AI self-play (Hard vs Hard round robins; every roster inside 35-65 %); feel and fun are unknown.
- macOS builds are ad-hoc signed, **not notarized**; the GitHub CI workflow has **never run**.
- A rare Godot 4.7.2 GDScript operator-cache race (about 1 crash per 400-600 exported real-renderer match starts before the mitigation, 0 in 1000 boots after) is mitigated, not removed — retest on every engine upgrade and report upstream.

## How to run, test, build

- Play from source: `tools/godot/Godot.app/Contents/MacOS/Godot --path game` (after `tools/setup` on a fresh checkout to fetch the engines).
- Always use the wrapper: `tools/gd check --strict`, `tools/gd test <filter> -q` (full suite: `tools/gd test -q --timeout 2700 --stall 0`, 7-13 min), `tools/gd run`, `tools/gd shot <scene> out.png`, `tools/gd linux --arch amd64|arm64 <cmd>`, `tools/gd snapshot`.
- Specs are huge: `tools/spec list|show|grep|sizes|dev`.
- Headless/screenshot flags for a live match: `--autostart=match|mission=<id>|replay=FILE|lan-host|lan-join=IP --with-ui --bots[=all|human] --players=N --rosters=a,b --map-seed=S --map-size=N --family=F --ticks=N --speed=0 --pause-at=N --scenario=showcase` (see `docs/DEVELOPMENT.md`).
- Release: `docs/RELEASE_CHECKLIST.md` (exports, packages, QA scripts, version stamping with `tools/py/version.py`).

## How it was built (waves)

1. Foundation: tooling, 5 R&D spikes, 14 design specs (reconcile/review stages were dropped after a usage-limit failure; implementation followed the specs and tests found the seams).
2. Wave 1-2: kernel, data layer, map/pathing, 8 faction balance sheets, movement, map generator, combat, economy.
3. Wave 3-4: view layer, abilities/vision, UI/app shell, sim integration + 32-roster soak, netcode, AI.
4. Wave 5-7: faction visuals, abilities/zones/summons/engineers/powers/superweapons, app integration, FX, audio, icons/placement UX, structure states, AI extensions.
5. Wave 8-9: wiring, balance pass, visual polish, cross-platform QA, data-hash coverage, AI quality, replays/observer.
6. Wave 10-11: stability hardening, rebalance, mission system + campaign + tutorial, release engineering, final QA on exported builds, hotkey completion.

## Open items (details in `docs/KNOWN_ISSUES.md`)

1. Human-only checks above (Windows run, listening review, two-machine LAN game, playtest, Debian real device).
2. Weaker-GPU path: no MultiMesh batch backend for the Mobile/Compatibility renderers (node backend only); no integrated-GPU measurements.
3. Release polish: macOS notarization (Apple Developer account), Windows icon/version embedding and code signing, first real CI run, placeholder .deb maintainer/homepage, license choice (MIT placeholder).
4. Gameplay extensions: multi-human/coop missions, LAN spectators (lobby-only today), more maps/biomes, veterancy (bible: none in the first prototype), AI second attack wave and siege kills, Field Manual counter suggestions.
5. Small known issues: map generator leaves ~10 % of coast water cells above water level (the view compensates); sample player/host names in specs/tests use a first name as placeholder data.

## Lessons for whoever continues (human or assistant)

- **Budget:** the first design phase ran every agent at maximum effort and produced 150-500 KB specs; it consumed a weekly allowance. Use `effort: high|medium`, scoped briefs with explicit section lists (`tools/spec show <spec> <section>`), small tool outputs and terse reports. Implementation waves of 4-15 agents then cost 0.7-8.8M tokens each.
- **Workflows are resumable**; keep prompts unchanged for cache hits and write them RESUME-SAFE. After an interruption (usage limit, login expiry) probe with a trivial agent call and resume.
- **Agents must return valid JSON reports** (one 9 KB report failed to parse; the work was recovered from the transcript).
- **Never swap shared data files temporarily** (a balance agent once did and polluted other agents' test runs).
- Harness quirks: subagents cannot write report-style `.md` files with the Write tool (use Bash heredocs for deliverable docs); the shared `game/.godot` import cache is serialised by `tools/gd` (never run the engine binary on `game/` directly).
- Binding decisions live in `CLAUDE.md` (one content pipeline owned by the data module; `sim_core.md` is the reconciled kernel master).
