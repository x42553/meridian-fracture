# MERIDIAN FRACTURE — Architecture Anchor (v0.1)

> **Status:** anchor decisions. Every agent builds against this document. Domain specs in `docs/spec/*.md`
> refine it; where a domain spec and this anchor disagree, **this anchor wins** unless the reconciler has
> recorded an explicit amendment in `docs/AMENDMENTS.md`.
> The faction/unit/tech **design bible** (read-only, canonical) lives in `Input/meridian_agent_reference/`.

---

## 0. Product definition

**Meridian Fracture** is a real-time strategy game in the Command & Conquer tradition (base building,
credits economy, power grid, tech tiers, support powers, superweapons, fast tactical combat).

* Engine: **Godot 4.7.2 stable** (standard build, *not* .NET). Language: **GDScript only**, statically typed.
* Targets: **Windows 10+ (x86_64)**, **Linux (Debian 12+, x86_64)**, **macOS 12+ (universal)**. One code base, no platform forks.
* Modes: **Skirmish vs AI** and **LAN multiplayer (2–8 players, humans and AI mixed)**. Replays.
* Content: **8 factions × (1 vanilla + 3 subfactions) = 32 playable rosters**, all defined by the bible:
  156 unit defs, 29 structure defs, 40 research upgrades, 48 support powers, 8 superweapons,
  98 typed passive modifiers. (See `Input/meridian_agent_reference/README.md` for the reading rules — they are binding.)
* Quality bar ("AAA feel"): coherent art direction, readable silhouettes, punchy combat feedback (VFX/SFX/camera),
  polished C&C-style HUD, rock-solid netcode, 60 FPS on mid-range hardware, zero crashes in a 60-minute 8-player match.
  There is **no external art**: all art and audio is procedural (generated at build-time by Python tools into
  `game/assets/`, or generated at runtime by GDScript). Only permissively licensed (OFL/CC0/MIT) third-party fonts may be vendored, with license files.

## 1. Non-negotiable technical decisions

1. **Deterministic lockstep simulation.** All clients run the identical simulation; only *commands* cross the network.
   The simulation uses **integer arithmetic only** (see §4). Cross-platform (macOS arm64 ↔ Linux x86_64 ↔ Windows x86_64) bit-identical results are a hard requirement and are tested.
2. **The simulation is headless.** `game/src/sim/**`, `core/**`, `data/**`, `map/**` contain **no `Node`s** and no engine
   rendering/physics/audio dependencies (RefCounted/Resource only). The full game (AI vs AI included) must run under `godot --headless`.
3. **Presentation is a pure function of sim state + events.** `view/`, `ui/`, `audio/` read the sim, never mutate it.
   Mutation happens only through `SimCommand`s submitted to the command pipeline (which is also what the network carries).
4. **AI is host-side and issues ordinary commands** (same path as a human). AI code may use anything (it is *not* part of the deterministic core), but must read state only through the sim's public query API and act only via commands.
5. **All game content is data-driven** from the bible + balance layer (§7). No unit stat is hard-coded in systems.
6. **No third-party plugins/addons/GDExtensions.** Only what ships in the stock Godot 4.7.2 editor/export templates.
7. **Everything must work headless-first and be testable by scripts**: every module ships with tests runnable via `tools/gd test`.

## 2. Repository layout

```
Meridian/
  Input/                     READ-ONLY. The bible. Never edit.
  docs/                      ARCHITECTURE.md, AMENDMENTS.md, spec/*.md, balance/*.md, STATUS.md
  tools/
    gd                       THE wrapper for running Godot (import/run/test/shot/check/linux/docs). Always use it.
    godot/Godot.app          engine (macOS)          godot-linux-x86_64/  engine for Docker tests
    godot_docs/doc/classes/  exact-version class reference XML (grep it to verify any Godot API before using it!)
    py/                      Python tooling (asset generators, data compilers, linters). Stdlib + numpy + Pillow only.
  game/                      THE GODOT PROJECT (res:// == this directory)
    project.godot  export_presets.cfg
    src/
      core/   fixed-point math, RNG, checksum, spatial hash, int grids, logging     (no deps)
      data/   GameData, Def* classes, modifier resolver, validators                (deps: core)
      map/    MapData, terrain layers, map generator, pathing grids                (deps: core, data)
      sim/    SimWorld, entities, components, systems, commands, events            (deps: core, data, map)
      net/    lockstep session, lobby, LAN discovery, replay                       (deps: core, sim)
      ai/     skirmish AI brain(s)                                                 (deps: core, sim (read + commands))
      view/   3D presentation: camera, terrain/water/fog views, unit views, VFX    (deps: core, data, map, sim(read))
      ui/     2D UI: menus, lobby, HUD, sidebar, minimap, input controller         (deps: everything above)
      audio/  audio engine + event→sound mapping                                   (deps: core, data, sim events)
      app/    autoloads, boot, scene flow, settings, match setup                   (deps: everything)
    data/
      bible/      synced verbatim copy of Input/…/meridian_factions.json (by tools/py/sync_bible.py; never hand-edit)
      balance/    designed numbers the bible leaves null (stats, weapons, armor tables, ability params)
      recipes/    procedural model recipes (visual definitions)
      text/       UI strings, tips
    assets/       generated: audio/, fonts/, textures/, icons/ (each with a generator script in tools/py)
    tests/        test_*.gd, scenario fixtures, golden hashes
  prototypes/     throw-away spikes, each a self-contained mini Godot project
  builds/         exported binaries (git-ignored)
```

**Class naming / global classes.** Use `class_name` for every reusable class, with a **module prefix** so agents never collide:
`Fp`, `SimRng`, `Checksum`, `SpatialHash`, `IntGrid`, `Log` (core) · `Def*`, `GameData` (data) · `Map*` (map) · `Sim*` (sim) ·
`Net*` (net) · `Ai*` (ai) · `View*`, `Fx*` (view) · `Ui*` (ui) · `Snd*` (audio) · `App*` (app).
File name = snake_case of class name (`SimWorld` → `sim_world.gd`). One class per file. Files ≤ ~1500 lines — split by responsibility.

## 3. Coordinates, units and time (the sim's physical constants)

Defined once in `core/sim_config.gd` (`SimConfig`); never duplicate the numbers elsewhere.

| Quantity | Representation |
|---|---|
| Tick rate | **`SimConfig.TPS = 20`** ticks/second (50 ms). "Normal game speed" = real time. 1 network **turn = 2 ticks**. |
| Position | `int` sub-cell units. **`Fp.CELL = 1024`** units = 1 terrain cell. Entities store `x: int, y: int` (never `Vector2`/`Vector2i`). |
| Cell index | `cx = x >> 10` (only for non-negative coordinates; use `Fp.cell_of(v)`), grid index `cy * map.w + cx`. |
| Distance / range | integer units. Data in cells (may be fractional) is converted at load: `units = roundi(cells * 1024)`. Distance compares use squared ints or `Fp.dist()` (integer sqrt). |
| Angle | `int` **binary angle, 4096 per full turn** (0 = +x/east, increasing toward +y/south). `Fp.sin/cos` return Q16 (×65536) from a constant lookup table. |
| Speed | `int` units/tick. Data in cells/second → `roundi(cells_per_s * 1024 / TPS)`. |
| Time | `int` ticks. Data in seconds → `ceili(seconds * TPS)` computed with integer millisecond math at load. |
| Health / damage / credits / power | `int`. Health is stored in hit points (no fractions). |
| Percentages | `int` in **percent** or **basis points (1/100 %)**. Layered modifiers follow §7 exactly, with the *documented* rounding (half-up, floor at 1 where a stat must stay positive). |
| 1 cell in the 3D world | **3 world units (meters)**. Sim→view: `world_x = x * 3.0 / 1024.0`, `world_z = y * 3.0 / 1024.0`. Height is a *view-only* function of the map height layer; the sim is 2D (plus a per-entity `layer` for AIR/GROUND/NAVAL/UNDERWATER). |
| Map size | 96×96 … 256×256 cells (multiples of 8). |
| Players | up to **8** (`pid` 0–7) + `NEUTRAL = -1`. `team: int` per player. |

## 4. Determinism rules (violations are bugs; the linter greps for many of them)

DR-1  Sim state is **ints only**. No `float`, `Vector2/3` (float), `Transform`, `Color` in anything that can influence sim state or the checksum.
      (`Vector2i` may be used only for cell coordinates and never via `.length()`, `.length_squared()`, `.distance_to()`, `.normalized()` — int32 overflow / float.)
DR-2  No engine randomness: never `randi/randf/randomize/RandomNumberGenerator/shuffle/pick_random`. Use `SimRng` (xorshift128, 32-bit masked, state in the checksum). Each `SimWorld` owns one RNG; systems draw in a fixed order.
DR-3  No wall-clock or frame time in the sim: never `delta`, `Time.*`, `OS.get_ticks_*`, `Engine.get_frames_drawn`.
DR-4  Only `Fp.sin/cos/atan2/isqrt` (tables/integer algorithms) — never `sin/cos/atan2/sqrt/pow/exp/log/floor/round` float builtins on sim values. (`Fp.isqrt` must be exact.)
DR-5  Integer division truncates toward zero and `%` keeps the dividend's sign (C semantics). Use `Fp.floor_div/floor_mod` where floor semantics are needed. Keep intermediate magnitudes < 2^62; never rely on overflow.
DR-6  **Iteration order must be deterministic**: iterate `Array`s in entity-id order; `Dictionary` may be used only with **int or String keys inserted in deterministic order** (Godot dictionaries preserve insertion order). Never key by object reference. Never iterate a `Dictionary` while its insertion order could depend on non-deterministic history — prefer arrays sorted by id.
DR-7  Sorting: `sort_custom` comparators must be **total orders** (tie-break by entity id). No reliance on sort stability.
DR-8  No `Node`, signals, `await`, `call_deferred`, timers, threads, or physics in the sim. Sim code is synchronous and single-threaded.
DR-9  No hidden global mutable state: all sim state lives in `SimWorld` (so two worlds can run side by side in a test and produce identical hashes).
DR-10 Floating data (JSON) is converted to ints **once at load** via `Fp` helpers (with `roundi`); the *converted* data hash is part of the lobby handshake.
DR-11 Pathfinding/steering/targeting use integer math and deterministic tie-breaks (lowest id / lowest cell index). Work per tick is bounded by **counts** (e.g. "≤ N path requests/tick"), never by elapsed time.
DR-12 Events emitted to presentation are output-only. The sim never reads events, view state, UI state, selection, camera, or settings.
DR-13 `SimWorld.checksum()` covers all gameplay-relevant state (entities in id order, players, RNG, map mutable layers, queues, cooldowns). Any new persistent sim field **must** be added to the checksum in the same change.
DR-14 The AI (host) and UI (client-local) may use floats, but anything they *decide* enters the sim only as a `SimCommand` of ints.
DR-15 Presentation interpolation (float) is allowed **only** in `view/` and must never feed back.

## 5. Module map & dependency rules

```
core ← data ← map ← sim ← { net, ai }          view/ui/audio read sim (+ data, map); app composes all
```
* No module may depend "upward" (e.g. `sim` never references `view`, `ui`, `net`, `ai`, `app`).
* `sim` reaches data through `GameData` (a plain object owned by the world, **not** an autoload singleton, so headless tests can construct worlds freely). `app/` provides autoload wrappers.
* Cross-module calls use the documented public API in the domain spec; no reaching into another module's private (`_`-prefixed) members.

## 6. Simulation tick pipeline (fixed order — every system runs every tick unless it declares a stride)

```
 1  CommandSystem       apply this tick's validated commands (ordered by player index, then submission sequence)
 2  ProductionSystem    construction queue, unit queues, research queue, rally, placement completion
 3  EconomySystem       credits, power balance, harvesting cycle, refinery unload, income events
 4  PowerSystem         (supports 3) shortage state; support-power cooldowns; superweapon charge / warning / execution
 5  OrderSystem         current-order state machines (move, attack-move, guard, capture, repair, load, …)
 6  MovementSystem      path following, steering, separation, collision, air/naval movement
 7  AbilitySystem       deploy/camouflage/cover/heal-auras/command-fields/EMP/shields/summons… (data-driven primitives)
 8  CombatSystem        target acquisition, turret aim, weapon fire, projectile update, damage, suppression, death
 9  ZoneSystem          area effects with lifetime (smoke, interception zones, debris slow, decoys, pucks, shelters)
10  VisionSystem        fog/shroud per player (stride 2), detection/reveal
11  CleanupSystem       deferred removals, wrecks, salvage windows, victory/defeat evaluation
12  SimWorld.tick++ ; every 20 ticks: checksum snapshot (for net desync + replay + tests)
```
Systems are plain classes `SimXxxSystem` with `func update(world: SimWorld) -> void` and are registered in that order by `SimWorld`.
Events (`SimEvent`, int-typed) are appended to `world.events` during the tick and drained by presentation after each tick batch.

## 7. Data layering (bible → balance → runtime)

1. **Bible** (`Input/…/meridian_factions.json`, mirrored to `game/data/bible/`): IDs, lore, tiers, prerequisites, roles/abilities prose, *typed passive modifiers*, research, powers, superweapons, roster deltas. **Canonical for anything it specifies. `null` means unspecified (never zero/free/instant).**
2. **Balance layer** (`game/data/balance/*.json`): the numbers the bible leaves null: health, armor class, speed, vision, radius, movement class, cost/build time (where null), weapons (damage, damage type, range, reload, projectile), ability parameters extracted from the prose, structure footprints, building HP, research/power effect parameters. Every entry references bible IDs. **Bible values are never overridden by the balance layer**; conflicts are flagged, not silently resolved.
3. **Resolution** (runtime, `GameData`): for a roster (`roster.napc.canada`), compute final per-player defs using the bible's layering rule:
   `final = base × Π over layers (1 + Σ deltas_in_layer/100)` with layers *base → parent faction → subfaction → research/temporary*, then apply the floors/caps in `mechanical_conventions` (cost & build time ≥ 60 % of base, reload ≥ 50 % of base, combined resistance ≤ 50 %). Conditional modifiers (`conditions[]`) become runtime checks; `unresolved_target_domain` entries must be resolved by the data architect and documented.
4. **IDs**: strings in data (`unit.napc.guardian_tank`); the sim uses **dense int def indices** assigned by `GameData` in sorted-ID order (deterministic). Display names are labels only.
5. Data version hash = FNV-1a over the canonical converted int tables; it is exchanged in the lobby and any mismatch blocks the match.

## 8. Presentation contract

* `SimWorld` exposes read-only queries (`entities`, `players`, `map`, `fog_of_player(pid)`, `events`) and `submit(cmd: SimCommand)`.
* `view/` keeps a `ViewWorld` that mirrors entities to scene nodes by id: create on `SPAWNED`, destroy on `REMOVED`; each frame interpolate `prev→curr` sim state with `alpha = time_since_tick / tick_interval` (floats allowed here only).
* All models are **procedural** (recipes in `game/data/recipes/` interpreted by a `ViewModelBuilder`); team color via shader `instance uniform`; parts flagged for animation (wheels, tracks, turrets, rotors, radars, infantry limbs) are animated in shader or by cheap node transforms. Target: a full-screen battle of ~400 entities at 60 FPS on integrated-class GPUs at the *Low* preset.
* Fog of war is a per-player texture produced by the sim's vision layer and applied by a terrain/unit overlay shader; hidden enemy units are not rendered.
* UI is code-built `Control` trees over a single `UiTheme`; UI never touches sim internals except through `SimWorld` query API and `SimCommand` submission (via `UiCommandBus`).

## 9. Networking summary (details: `docs/spec/net.md`)

* Star topology: host = authority for *ordering* only (relay + AI runner). Godot `ENetMultiplayerPeer` (reliable ordered). LAN discovery via UDP broadcast (`PacketPeerUDP`) + manual IP join. Default port 27615 (UDP).
* Turn-based lockstep: commands issued at turn *T* execute at *T + input_delay* (default 2 turns = 4 ticks = 200 ms); a client advances only when every human's turn packet is present; empty turns are heartbeats.
* Desync detection: checksum every 20 ticks exchanged; mismatch → both sides dump state to `user://desync/` and show a dialog. Version/data-hash/map-hash handshake in lobby.
* Replays = `MatchConfig` + ordered command log + periodic checksums (same file used by determinism tests).

## 10. Cross-platform rules

* **Exact-case paths everywhere** (`preload("res://src/sim/sim_world.gd")` must match the filename byte-for-byte; Linux is case-sensitive, macOS/Windows usually aren't). All file names: lowercase snake_case ASCII, no spaces, none of the Windows-reserved names (`con prn aux nul com1… lpt1…`), path length < 150.
* Persistent user data only in `user://` (settings `user://settings.cfg`, replays `user://replays/`, cache `user://cache/`). Never write to `res://` at runtime, never use absolute paths, never shell out.
* No platform-specific APIs; `OS.get_name()` only for cosmetic tweaks (e.g. window mode defaults). No `OS.execute`.
* Rendering target: **Forward+** (default). The game must also *start and be playable* under `--rendering-method mobile` / `gl_compatibility` with automatic effect downgrades (guarded by capability checks, never by OS name).
* Text files use LF line endings. Binary/generated assets are committed as produced by the tools (re-generatable).

## 11. Tooling & testing contract (details: `docs/spec/qa.md`)

* **`tools/gd` is mandatory** for running Godot (it serialises the shared `.godot/` import cache with a file lock; parallel agents *will* otherwise corrupt it). Commands: `gd import`, `gd check` (parse every script + lint), `gd test [filter]`, `gd run <script|scene> [-- args]`, `gd shot <scene> <out.png> [opts]` (real renderer screenshot), `gd docs <Class>`, `gd linux <…>` (Debian container run), `gd snapshot`.
* Tests: `game/tests/test_*.gd`, each a `RefCounted` with `func run(t: TestCtx) -> void`, assertions via `t.check(...)`. The runner prints a summary and exits non-zero on failure.
* Required test kinds: unit tests per module; **scenario tests** (build a `SimWorld`, issue commands, tick N times, assert); **determinism tests** (same scenario twice, and across macOS↔Linux-container: identical checksum chain); **AI-vs-AI soak** (headless N-minute matches, no errors, plausible outcomes); **visual tests** (screenshots inspected by an agent with the image reader); **net loopback test** (two headless processes).
* `tools/gd check` must be clean (0 parse errors, 0 lint violations) at the end of every agent task.

## 12. Game-design decisions that bind all domains

* **Match start:** each player begins with a deployed HQ + 7,500 credits (bible preset); rules configurable in `MatchRules` (start credits, speed, unit cap default 150 non-structure entities/player, superweapons on/off, fog on/off, shared vision for allies).
* **Economy:** single currency (credits). Collectors auto-harvest **salvage deposits** and unload at Refineries (a Refinery includes one free Collector). Power is a capacity budget (§ bible `rule.design.power_loss`). No secondary resource.
* **Construction:** one player-wide construction queue; buildings must be placed within the **8-cell build radius of a friendly HQ** (Relay doesn't extend it). Cost is deducted progressively while building (pauses at 0 credits) — *decision:* progressive payment like C&C: RA2. Completed structures wait to be placed (placement ghost with validity coloring). MCV deploys into an HQ.
* **Production:** each Barracks/Factory/Airfield/Dock has one independent queue (queue length 5, rally point, hold/cancel with refund of spent credits). One player-wide research queue.
* **Tech:** T1 open; Radar → T2; Radar + Laboratory → T3; producers required per bible; losing a prerequisite pauses dependent orders (`rule.design.research`).
* **Infantry are squads** (one entity, one health pool; the view shows several soldiers who fall as health drops). Transports load squads (capacity per bible).
* **Fog of war:** shroud (unexplored) + fog (explored, not visible). Detection/camouflage per bible rules.
* **Victory:** a player is eliminated when they own no structures and no MCV/HQ-capable unit (i.e., can't rebuild). A team wins when all opposing players are eliminated (or all enemy humans/AI resign/disconnect).
* **Maps:** procedural, seeded, deterministic across platforms. Three families (open land, constrained urban routes, mixed coast/river); ≥ 2 exits per start area; **baseline economy never requires water**; symmetric fair layouts for 2/4/6/8 players; neutral structures (garrisonable civilian buildings, captureable substations, etc.).
* **Selection & control model:** C&C-style (box select, control groups, attack-move, guard, stop, scatter, deploy, force-fire, waypoints, rally points, sell/repair modes, sidebar build tabs). Camera: RTS orbit (pan/zoom/rotate).

## 13. Working agreements for agents (binding)

1. **File ownership:** you may create/edit only the paths your task assigns you. If you need a change elsewhere, do **not** edit it; list it under `CROSS_MODULE_REQUESTS` in your final report with the exact API/field needed.
2. **Verify before claiming.** Run `tools/gd check` and the relevant `tools/gd test …` and quote the result. Verify every Godot API against `tools/godot_docs/doc/classes/<Class>.xml` (Godot 4.7.2 postdates most training data). If you screenshot, *look* at the image.
3. **No placeholders that pretend to work.** Stubs must `push_error("NOT IMPLEMENTED: …")` or `assert(false)` so integration surfaces them; every TODO carries an owner tag `TODO(module)`.
4. Static typing everywhere (`var x: int = 0`, typed arrays `Array[int]`, `PackedInt32Array` for bulk data, typed function signatures). No untyped `var x = …` except with obvious `:=` inference of a typed expression.
5. Public API documented with `##` doc comments; keep comments dense and *why*-oriented. No dead code, no commented-out blocks, no debug `print` (use `Log`).
6. Performance-aware GDScript: avoid per-tick allocations in hot loops (reuse arrays), no `Dictionary` lookups where an array index works, cache `self.x` in locals inside loops, use `PackedInt32Array` for grids.
7. Final report (what you return): ≤ 25 lines — files created (paths), public API summary, test commands + results, known issues, `CROSS_MODULE_REQUESTS`. Do **not** paste code in the report.

---

## Appendix A — Vocabulary seeds mined from the bible (starting point; `docs/balance/TAXONOMY.md` is the final authority)

* **Damage types referenced by the bible:** `bullet`, `explosive` (shells, missiles, rockets, bombs, fragmentation, blast), `beam` (with the `thermal` sub-type: "thermal-beam", Helios, Sunwall; also microwave/laser), `rail`, `kinetic` (strategic penetrators / mass driver), `emp` (disable; "normal EMP damage" exists). Research and traits give type-specific resistances (e.g. "10% less explosive damage; does not reduce beam, rail or bullet").
* **Movement/pathing classes to support:** foot (infantry squads), wheeled, tracked, amphibious (ground+water), naval (surface ship), submerged (submarine), air (fixed-wing / hover / drone), plus static (structures).
* **Entity layers (sim):** `GROUND`, `AIR`, `SURFACE_WATER`, `UNDERWATER`. Weapons declare which layers they can hit.
* **Bible role tags (binding meaning, from `rule.combat.role_tags`):** light, tank, artillery, unmanned, siege, scout, detector, transport, specialist, amphibious, anti_air, anti_tank, anti_submarine, ground_attack, carrier, command, electronic_warfare, submarine, repair, capture, collector, construction, service.
* **Bible selector IDs** (`selectors` registry: 27 entries such as `selector.land_combat_vehicles`, `selector.combat_infantry`, `selector.aircraft`, `selector.ships`, `selector.land_artillery`, `selector.amphibious_vehicles_on_water`) are the only way modifiers pick targets; the data layer resolves them to def-index sets at load.
* **Numbers the bible does fix** (do not redesign): shared structure costs/build times/power deltas, Engineer 500, Collector 1400, MCV 3000, Landing Transport 900, tier requirements, research time 45 s (T2) / 75 s (T3), research/power costs and cooldowns, superweapon recharge/warning/geometry, start preset (HQ + 7,500 credits), build radius 8 cells, floors/caps (60 % cost/build-time floor, 50 % reload floor, 50 % resistance cap).

## Appendix B — Definition of Done (any task)

1. Code/data/doc files exist at the paths promised; `tools/gd check` is clean.
2. Tests exist for the new behaviour and pass via `tools/gd test <filter>`; determinism-relevant code has a double-run hash test.
3. No `TODO` without `TODO(module)`; no debug prints; no placeholder that silently succeeds.
4. Final report follows §13.7 and lists `CROSS_MODULE_REQUESTS`.
