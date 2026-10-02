# Meridian Fracture

![version](https://img.shields.io/badge/version-0.1.0-blue)

A real-time strategy game in the Command & Conquer tradition, built with **Godot 4.7.2** and GDScript. It is set in 2086, thirty years after the Long Blackout broke the Meridian Network, and eight rival blocs fight over the substations, ports and salvage fields that decide who gets power first.

Build a base, harvest credits, manage power, climb three tech tiers, command mixed armies on land, sea and air, and call in support powers and superweapons. Play a skirmish against the computer, work through the tutorial and eight campaign operations, play a LAN game with up to eight players, and watch any match again as a replay.

![Main menu](docs/img/main_menu.png)

## Features

- **8 factions, 32 rosters:** each faction has a vanilla roster and three subfactions that swap units and change rules. 156 unit definitions, 29 structures, 40 research upgrades, 48 support powers and 8 superweapons (with visible warning zones). See [docs/FACTIONS.md](docs/FACTIONS.md).
- **Classic base building:** one player-wide construction queue, placement inside the 8-cell build radius of your Headquarters, per-building production queues, progressive payment, power that slows production when short, Mobile Construction Vehicles for expansion, finite deposits that force you to expand.
- **Combat with depth:** seven damage types against eleven armor classes, fog of war, camouflage and detection, garrisons, transports, aircraft, ships and submarines, artillery, engineers, capture and salvage.
- **Campaign:** an interactive tutorial (Field Training) and eight faction operations with briefings, scripted objectives, mission timers and messages, four difficulties and saved progress.
- **Skirmish AI:** four difficulty levels (Easy, Medium, Hard, and Brutal, which cheats openly). The AI is economy-first, expands, attacks in planned waves, micro-manages, uses support powers and launches superweapons.
- **Replays and observing:** every match is recorded; the Replays screen lists, verifies, saves and plays them with a seek bar, speeds up to MAX, event jumps, a scoreboard and a per-player view.
- **LAN multiplayer:** deterministic lockstep for up to 8 players, discovery or direct address, desync diagnostics. Windows, macOS and Linux play together. See [docs/LAN_GUIDE.md](docs/LAN_GUIDE.md).
- **Procedural maps:** seeded and identical on every computer; open land, urban and coast-and-river families; 2 to 8 players; sizes from 96 to 256 cells.
- **Everything is generated:** models are procedural recipes compiled to meshes (with a 3D model viewer in the Field Manual), sound effects and music are synthesised, and the announcer voice is offline text-to-speech. No third-party art or audio ships.
- **Field Manual, options, accessibility:** in-game encyclopedia with tech tree and comparison, rebindable keys, colour-blind palette, UI scaling, reduced motion and captions.

| | |
|---|---|
| ![Early game](docs/img/early_game.png) | ![Battle](docs/img/big_battle.png) |
| Early game: base, build sidebar, fog of war | A staged ground battle with the effects on |
| ![Superweapon warning](docs/img/superweapon_warning.png) | ![Superweapon strike](docs/img/superweapon_strike.png) |
| The marked zone and countdown of a superweapon | The strike lands (showcase scenario) |
| ![Campaign](docs/img/campaign.png) | ![Mission](docs/img/mission_hud.png) |
| The campaign theatre map | A mission: objectives, message, timer |
| ![Field Manual](docs/img/field_manual.png) | ![Observer](docs/img/observer.png) |
| Field Manual with the 3D model viewer | Replay with the observer HUD |
| ![Skirmish lobby](docs/img/lobby.png) | ![End screen](docs/img/end_screen.png) |
| Skirmish lobby | End screen with statistics |

More: [mission briefing](docs/img/mission_briefing.png), [mission result](docs/img/mission_result.png), [tutorial](docs/img/tutorial.png), [replays screen](docs/img/replays.png), [options](docs/img/options.png), [LAN browser](docs/img/lan_browser.png), [LAN lobby](docs/img/lan_lobby.png), unit lineups of [NAPC](docs/img/lineup_napc.png), [Han](docs/img/lineup_han.png) and [Pacific Dominion](docs/img/lineup_pd.png).

## Status: what is verified and what is not

The game is feature complete. What was **verified by machines**: about 2,400 automated tests (macOS arm64 and Linux arm64 and amd64), identical simulation hashes on macOS and Linux for the cross-OS scenarios, two-process LAN games over loopback, 30-minute 8-player soaks, quit and boot stress runs, exported macOS and Linux builds that start and play a headless match from their data package, and a `.deb` that installs on Debian 12 and 13.

What was **never done**: the Windows executable was never run on a Windows computer (a CI runner is configured but has never run), nobody listened to the audio, no two real machines played a LAN game, and the balance comes from AI-versus-AI play only, not from human playtesting. Every listed keyboard shortcut is connected and pressed by a regression test in a live match; a few Options rows (sidebar side, selection brackets, zoomed-out markers, cursor confinement, sidebar hover hotkeys) still do nothing. The full list is in [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md); [docs/INDEX.md](docs/INDEX.md) maps all documentation and states the verification level of each area.

## System requirements

| | Minimum (target) | Notes |
|---|---|---|
| OS | Windows 10 or later (64-bit), macOS 12 or later (Intel or Apple silicon), Debian 12 or another 64-bit Linux | The Windows build has not been executed on Windows |
| CPU | 4 cores, 2019-class | The simulation runs at 20 ticks per second on one thread; large matches are CPU-bound |
| GPU | Vulkan 1.1 capable (Windows, Linux) or Metal (macOS); an integrated GPU should work on the Low preset | The Compatibility (OpenGL) renderer is available in Options > Graphics |
| Memory | 4 GB | |
| Disk | About 300 MB for the game | Executable plus a 100 MB data package (`.pck`); the macOS app is about 260 MB (universal) |
| Network | Any LAN for multiplayer | UDP ports 27614 to 27624 |

The performance target is 60 FPS at 1080p on the Low preset on that hardware. Measured: the 120 FPS cap held (p95 frame time 10.6 ms) with about 550 entities on an Apple M5 Max; **not** measured on physical low-end PCs or integrated GPUs.

## Run a build

Builds are produced by CI or by `python3 tools/py/export.py export all` (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)) and packaged into `builds/packages/`.

**Windows.** Unzip `meridian-fracture-0.1.0-windows-x86_64.zip` and run `MeridianFracture.exe` (keep the `.pck` file beside it). `MeridianFracture.console.exe` shows a console with the log. The build is unsigned: on the SmartScreen prompt choose More info, Run anyway. Allow the game on private networks when Windows asks about the firewall. This build has never been run on Windows by the maintainers.

**macOS.** Open `meridian-fracture-0.1.0-macos-universal.dmg` and drag Meridian Fracture onto Applications (or unzip `meridian-fracture-0.1.0-macos-universal.zip`). The app is only ad-hoc signed, not notarized: on first launch right click it, choose Open, then Open again; if macOS still refuses, run `xattr -dr com.apple.quarantine /Applications/MeridianFracture.app`. Allow local network access when asked. Details: [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).

**Debian, Ubuntu and derivatives.**

```
sudo apt install ./meridian-fracture_0.1.0_amd64.deb     # installs to /opt/meridian-fracture, adds a menu entry
meridian-fracture
```

or unpack `meridian-fracture-0.1.0-linux-x86_64.tar.gz` and run `./MeridianFracture.x86_64` in the extracted folder.

## Run from source

Clone the repository, then:

```
tools/setup                                                    # engines, bible mirror, first import
tools/godot/Godot.app/Contents/MacOS/Godot --path game         # macOS
tools/godot-linux-x86_64/Godot_v4.7.2-stable_linux.x86_64 --path game   # Linux
```

On Windows install Godot 4.7.2 from godotengine.org and open the `game` folder or run `godot --path game`. Python 3.10 or later is used for the tooling (`tools/`).

## Quick start

1. **Campaign > Field Training** is a guided tutorial; or **Skirmish** on the main menu: choose your faction, add an AI opponent (Medium is a fair start), press **Start**.
2. You begin with a Headquarters and 7,500 credits. Build a **Generator**, then a **Refinery** (it comes with a free Collector) and a **Barracks** from the tabs on the right. When a card says READY, click it and place the structure near your Headquarters.
3. Queue infantry and vehicles. Select units by dragging a box, right click to move or attack, `A` then click to attack-move, hold `Ctrl` and right click to force fire.
4. Get a **Radar** for tier 2 and a **Laboratory** for tier 3, watch your power bar, and grow the economy with more Collectors and a second Headquarters: deposits are finite and do not regrow.
5. Press `F1` for the Field Manual, `Esc` for the game menu, `Ctrl+O` for the mission objectives, and click the power icons in the top-left dock to use powers.

Read the [user manual](docs/USER_MANUAL.md) for the economy, tech tiers, unit roles and counters, support powers and superweapons, the campaign, replays and the AI. All keys and mouse actions are in [docs/CONTROLS.md](docs/CONTROLS.md).

## Documentation

| Document | Contents |
|---|---|
| [docs/INDEX.md](docs/INDEX.md) | Map of all documents, how to navigate the huge design specs, what is verified and what is not |
| [docs/USER_MANUAL.md](docs/USER_MANUAL.md) | How to play, including campaign, replays, AI behaviour |
| [docs/CONTROLS.md](docs/CONTROLS.md) | Mouse and keyboard reference (generated from the real keymap) |
| [docs/LAN_GUIDE.md](docs/LAN_GUIDE.md) | Hosting and joining, ports, firewalls, troubleshooting |
| [docs/FACTIONS.md](docs/FACTIONS.md) | The eight factions and 24 subfactions |
| [docs/units/README.md](docs/units/README.md) | Generated stats of every unit and structure |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Repository layout, tools, tests, determinism, adding content and missions, replay tools, stress scripts, validators, export, CI |
| [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) | Open items and limitations |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The technical constitution |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | Release steps and the checks only a human can do |
| [docs/STATE.md](docs/STATE.md) | Orchestration log and build history |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |
| [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) | Licences of everything else in or behind the game |

## License

The game's code and data are released under the **MIT License** (see [LICENSE](LICENSE)); this is a placeholder default and the project owner may change it. Third-party components (Godot, fonts, the speech model used at build time) are covered by [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The setting, factions and names are fictional; the national names identify fictional successor commands and do not describe real countries or populations.
