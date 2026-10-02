# Changelog

All notable changes to Meridian Fracture are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/). The single source of the version is the `VERSION` file
(`python3 tools/py/version.py check` fails on drift).

## [Unreleased]

## [0.1.0] - 2026-10-02

First release. The Windows build has not been executed on a Windows host by the maintainers (CI runs it on a Windows runner); the
balance is a first pass that no human has playtested; macOS builds are ad-hoc signed, not notarized.

### Added
- **Factions:** 8 factions x 4 rosters (a vanilla roster and three subfactions that swap units and change rules), 156 unit definitions
  and 29 structures across land, sea and air.
- **Economy, tech and powers:** harvesting and credits, power that slows production when short, one player-wide construction queue,
  Mobile Construction Vehicles, three tech tiers, 40 research upgrades, 48 support powers and 8 superweapons with visible warning zones.
- **Combat:** seven damage types against eleven armor classes, fog of war, camouflage and detection, garrisons, transports, artillery,
  engineers, capture and salvage.
- **Skirmish AI:** four difficulty levels (Easy, Medium, Hard, Brutal); expansion, micro, support powers and superweapon use.
- **LAN multiplayer:** deterministic lockstep for up to 8 players, discovery or direct address, desync diagnostics, in-match chat
  (everybody or team) and team map pings; spectators can sit in the lobby but cannot watch a running match (watch the replay afterwards);
  Windows, macOS and Linux build identical simulation hashes (cross-OS determinism chains are checked in CI).
- **Replays:** record and play back any match, bit-exact.
- **Campaign:** interactive tutorial plus 8 operations with briefings, objectives and a campaign map.
- **Procedural everything:** seeded maps (open land, urban, coast-and-river; 2 to 8 players; 96 to 256 cells), models compiled from
  recipes, synthesised sound effects and music, offline text-to-speech announcer. No third-party art or audio ships.
- **UI and accessibility:** Field Manual (encyclopedia, tech tree, comparison), rebindable keys (all 159 registered actions are connected:
  powers `F5` to `F8`, build cards, tabs, abilities, ping, scuttle, screenshot, fullscreen, hide interface; a regression test presses
  every key in a live match), the on-screen camera pad, colour-blind palette, UI scaling, reduced motion, captions.
- **Release engineering:** app icon (shield and star emblem, procedurally rendered), `.icns` / `.ico` / PNG set, `VERSION` stamping with a
  drift check, macOS `.dmg` + `.zip`, Windows `.zip`, Linux `.tar.gz` + `.deb`, CI that runs every step the developer runs locally.
- **Tools:** `tools/gd` (import, check, test, shot, linux container runs), export / package scripts, determinism and soak harnesses,
  quit and boot stress scripts, balance validator and calculators, bible mirror sync.

### Known limitations
- A Godot 4.7.2 engine race (GDScript operator cache published without synchronisation) could crash a match start about once in a hundred on the exported build; the loading code now runs the first model builds on the main thread (0 crashes in 1,000 test boots afterwards), but the engine bug itself remains until Godot is upgraded.
- **The Windows build was never executed.** There was no Windows host: the Windows export builds and the CI workflow is configured, but
  neither the exe nor the zip has been run on a Windows computer. macOS and Linux (Debian 12/13) were run; nobody has listened to the
  audio, and no two real machines have played a LAN game (two processes on one machine have).
- No veterancy system (the lobby offers no switch), no in-match chat outside LAN matches, no spectating of a running match.
- Windows executable: the exe icon cannot be embedded on a host without rcedit or wine (`application/modify_resources=false`); the
  `.ico` ships next to the exe. The window icon at runtime comes from the project icon.
- No code signing certificate, no notarization (see `docs/RELEASE_CHECKLIST.md`).

[Unreleased]: https://example.invalid/meridian-fracture/compare/v0.1.0...HEAD
[0.1.0]: https://example.invalid/meridian-fracture/releases/tag/v0.1.0
