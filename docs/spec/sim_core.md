# Simulation Core — Domain Specification (`sim_core`)

> **Domain architect:** Simulation core. **Binding parent:** `docs/ARCHITECTURE.md` (anchor; wins on conflict). **Status:** design v2.1 — reconciled with the concurrently published `combat`, `economy`, `abilities`, `data_balance`, `net`, `ai`, `qa_tooling`, `terrain_movement` (map and movement), `qa`, `audio` and `render` specs; implementation-ready.
> **Evidence base.** Every algorithm, byte layout and number below was proven with a throw-away executable reference prototype (≈ 3.7 kLOC of kernel + 0.3 kLOC generated tables + 2.3 kLOC of tests and benches, GDScript, scratch project, **not** part of the repo) run on Godot 4.7.2 **macOS arm64 and Linux x86_64 (Debian container, amd64)**: the whole suite (23 scripts, 248 assertions, 364 output lines: Fp/RNG/checksum/hash vectors, command catalog round trips, order semantics, lifecycle, API, config, part attribution, the map contract, world lifetime, the S-CORE-1 scenario chain, command-log replay, five 3,000-step chaos-fuzz games with structural invariants INV-1…INV-17) produced **byte-identical output on both platforms**, and the repo's `tools/py/xplat_determinism.py` reports identical hash chains on **macOS arm64, linux/amd64 and linux/arm64**, and the arithmetic/RNG/trig digests were cross-checked against independent Python implementations. The kernel sources of the prototype also pass the repo's own gate **`tools/gd check src --strict` (lint L001–L010, 0 script errors, 0 GDScript warnings)** when laid out as `game/src/{core,sim,data,map}` in a throw-away project (`GD_ROOT`/`GD_GAME_DIR` override), so the code excerpts below are lint-clean as written. Golden values in §10 come from that prototype.
> **What changed from v1 (reconciliation).** The other domain architects published while this spec was being written and converged on one vocabulary for the kernel. v2 **adopts it wherever it is technically sound** (entity fields, world services, event shape, decimal code blocks, `submit_raw`, net's adapter API, data's per-kind def indices and `DefPlayerView`) and documents every remaining divergence with a decision in §6.4. Removed from v1: sim-level pause (net owns pause at the lockstep barrier), `SimReplay` file format (net owns `NetReplay`), kernel-side wreck creation and status timers (combat owns them), the kernel's own per-player stat tables (`DefStats`; data's `DefPlayerView` replaces them).
> **What changed in v2.1.** The specs published while v2.0 was being finished — `terrain_movement` (map **and** movement), `qa`, `audio`, `render` — are reconciled in §6.4-F. The consequential decisions: **the map owns structure occupancy** and the kernel calls `MapData.occupy / vacate` (so `struct_grid` and `IntGrid` are gone, the `map` checksum part is `map.checksum_dynamic()`, `struct_at()` reads it); world creation reads the map's real `spawns` / `neutrals` records (neutral buildings are STRUCTUREs of owner −1, deposits are map cells); `spawn_structure` takes a `facing` (rotatable footprints); `SPAWNED` is the first event of every entity and the new core event `NAV_CHANGED` follows occupancy changes; block 100–129 is movement's; command `FOLLOW`, movement flags on `MOVE / ATTACK_MOVE / PATROL`, `RETURN_TO_BASE.target`, `DEBUG` modes 3–6 (`SimSystem.on_debug`); `SimFogApi.ghosts / ghost_version / decoy_identified` and world wrappers `cell_visible / entity_visible / are_allied`; a `test_sim_free` proof that a world has no RefCounted cycles; and translation tables for the consumers that were written against v1's names.
> Tags used below: `ASSUMPTION(domain)` = something I rely on another architect to provide (also listed in §13); `[verified]` = observed on the real 4.7.2 binary.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

### 1.1 What this domain is
The **deterministic kernel** every other simulation domain plugs into: the integer math and RNG the sim may use, the world container and its tick pipeline, the entity/player data model and the *rules for extending it*, the command pipeline (framework, int-array wire form, validation, master catalog), the event stream, the order-queue dispatcher, entity lifecycle (spawn, kill, removal, capture, temporary units), match rules, victory/defeat, the checksum contract and the test kit. If a domain needs a new persistent field, command, event or order, the *slot* for it is defined here.

### 1.2 Owned (design authority)
`game/src/core/*` (`SimConfig`, `Fp`(+`FpTables`), `SimRng`, `Checksum`, `SpatialHash`, `Log`) · `SimWorld` (+`SimStateHash`, `SimPipeline`, `SimInvariants`, `SimDefs`) · `SimEntity`, `SimFlags`, `SimTag`, the **component-slot policy** · `SimPlayer` · `SimSystem`/`SimComponent`/`SimFogApi` base types · `SimCmd` (**MASTER command catalog**, wire layouts, int-array builders), `SimCommand`, `SimCommandCodec`, `SimCommandSystem` · `SimEvent`, `SimEventBuffer` and the **MASTER event registry** (core events + code blocks; each domain owns the event tables inside its block) · `SimOrder`, `SimOrderHandler`, `SimOrderSystem` (dispatcher + queue semantics; handlers are supplied by other domains) · `SimCleanupSystem` (deferred removal, expiry, elimination, defeat cascade, victory) · `SimMatchConfig`/`SimMatchRules`/`SimPlayerSlot` (the sim's reader of net's `MatchConfig`) · `SimCommandLog` (in-memory record for tests/tools) · `SimTestKit` · the world **query API** · the **checksum contract** · tick-pipeline registration (ARCHITECTURE §6).

### 1.3 Explicitly NOT owned (interfaces only)

| Not mine | Owner | Interface I rely on / provide |
|---|---|---|
| `GameData`, `Def*`, `DefRoster`, `DefPlayerView`, `DefLayer3`, data hash, modifier math | data | the **only** data reads of the kernel are the ones in `SimDefs` (§3.3.5, list in §7.2); `ASSUMPTION(data)` §13 |
| `MapData`, `MapFootprint`, terrain / nav / pathing grids, **structure occupancy** (`occupy` / `vacate` / `occupant_at`), deposits, patches, generator, `map_hash()` / `checksum_dynamic()` | map | `ASSUMPTION(map)` §7.2b, §13 R7; `world.map` is a private `clone_fresh()`; the kernel **calls** `occupy` / `vacate` for STRUCTURE / NEUTRAL entities and keeps no map state of its own |
| Path following, steering, collision, air/naval movement | movement | order handlers `T_MOVE…`, `SimCompMove`; I supply `world.set_pos/set_layer/set_inside` and the `prev_*/v*` bookkeeping |
| Target acquisition, weapons, projectiles, damage, armour, suppression, EMP, hp writes, stance, status timers, **death/wreck handling** | combat | `SimCompCombat/Air/Carrier`, `world.kill()` + `on_dying`, `set_hp_max`, `alloc_proj_id`; event block 200–229; commands 40–47 |
| Construction/unit/research queues, placement, rally, sell, credits *policy*, harvesting, repair/salvage/capture actions, power balance, support powers, superweapons | economy (incl. production/power/strategic) | `SimCompEcon/Prod`, `SimPlayerEcon`; executors 120–141; event block 300–499; credits only through `add_credits/try_spend` |
| Deploy/camouflage/auras/EMP-immunity/shields/summons, zones, vision, cargo/garrison | abilities (abilities, zones, vision, transports) | `SimCompAbility/Stats/Vision/Cargo/Summon`, `SimPlayerFx/Vision`; executors 100–105; event block 230–259; `SimFogApi` |
| Lockstep session, lobby, transport, LAN, **pause**, speed, **replay file IO**, `MatchConfig` schema | net | `submit_raw`, `step`, `checksum_at/parts_at`, `dump_state`, `is_match_over`… (§3.4.8); `T_RESIGN = 250` |
| AI, view, UI, audio, app, `tools/gd`, test runner | respective | read-only query API + `SimCmd` builders + `events.take()` |
| Chat | net/ui | **not a sim command** |

### 1.4 Headline decisions (details in the sections named)
1. **One entity table for UNIT / STRUCTURE / WRECK / ZONE / NEUTRAL; projectiles are *not* entities** — they live in a combat-owned pooled SoA store and use `world.alloc_proj_id()`. `def_idx` indexes the def table selected by `kind` (data's per-kind indices) (§4.1, §4.12).
2. **One clock.** `world.tick` = completed ticks; there is no sim-level pause and no second counter. Net pauses by not calling `step()` (§5.3).
3. **`SimWorld.step()` is the only entry point that advances the sim.** Commands arrive as `PackedInt32Array [op, fields…, ids…]` through `submit_raw(pid, ints)` and are decoded, validated and executed inside stage 1 (§3.5, §5.5).
4. **Stage-stable iteration.** Entity lists are never appended to or compacted while any system's `update()` runs; new entities become visible at the next stage boundary; dead ones stay (flagged `F_DEAD`) until `SimCleanupSystem` compacts (§5.4).
5. **Domain extension = 11 typed nullable component slots on entities, 3 on players, plus the `hash_into(buf)` contract**, enforced by a reflection test (`SimTestKit.check_hash_coverage`) so DR-13 cannot silently rot (§4.5, §8.3).
6. **Checksum = 16 named parts** (`world, rng, players, entities, map`, one per pipeline stage) built from per-entity MD5-folded digests, every 20 ticks in ≈1.75 ms for 1,700 entities; `checksum_at/parts_at/dump_state` give net everything it needs to localise a desync (§8).
7. **Kernel maintains motion bookkeeping:** `prev_x/prev_y` (position at the start of the tick), `vx/vy` (this tick's displacement) and `moved_prev2()` are written by `set_pos` and reset lazily, so combat (lead), the view (interpolation) and vision (incremental updates) share one source (§5.4).
8. **Orders:** handlers are stateless strategy objects (`can_issue / on_begin / on_update / on_end / on_target_lost / on_idle`), the dispatcher owns queue semantics; `on_begin`+`on_update` run in the same pass; any system can veto an order through `order_gate` (§5.6).
9. **Data coupling in one file** (`SimDefs`): a data-side rename costs one file; the kernel never touches a `Def*` anywhere else (§3.3.5).
10. **Determinism of removal:** deaths and removals are processed in ascending entity-id batches; hooks run in stage order; a hook may keep a corpse alive with `remove_deferred` (§5.4).
11. **The map owns occupancy, the kernel guarantees it is maintained:** `spawn_entity` occupies the footprint of a STRUCTURE / NEUTRAL entity (`MapData.occupy`) and removal vacates it (`MapData.vacate`), so no domain can forget either; the `map` checksum part is `map.checksum_dynamic()`; `SPAWNED` is always the first event of an entity, `NAV_CHANGED` follows it (§5.4, §8.2).

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All paths under `game/`. Files ≤ 1500 lines (`SimWorld` is ≈ 990); one class per file; snake_case file = class name (lint L009).

### 2.1 `src/core/` (no dependencies)

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/core/sim_config.gd` | `SimConfig` | Single home of physical/engine constants (TPS, CELL, caps, versions, throttle gaps). |
| `src/core/fp.gd` | `Fp` | Static integer math: floor/ceil division, exact `isqrt`, `dist`, rounding `mul_div`, layered-modifier math, Q16 trig, integer `atan2`, angle helpers, load-time float→int converters, `self_test()`. |
| `src/core/fp_tables.gd` | `FpTables` | **GENERATED** (by `tools/py/gen_fp_tables.py`): two `const … : PackedInt32Array = [ … ]` literals — `SIN_Q16` (4096 entries) and `ATAN_Q8` (1025 entries). Never hand-edit. |
| `src/core/sim_rng.gd` | `SimRng` | xorshift128, splitmix32 seeding, `next_int/range_i/chance_*/shuffle`, state (de)serialisation. |
| `src/core/checksum.gd` | `Checksum` | FNV-1a 32-bit primitives, overflow-safe 64-bit folding, MD5-based `digest32` fast path for packed arrays, finalizer. |
| `src/core/spatial_hash.gd` | `SpatialHash` | 4-cell bucket grid over entity ids; tag-filtered, allocation-free circle/rect queries returning ascending ids; `cell_bucket`. |
| `src/core/log.gd` | `Log` | `debug/info/warn/error(tag, msg)`, injectable sink, 256-line ring (never influences the sim). The only file allowed to `print` (L006). |

### 2.2 `src/sim/` — kernel (mine)

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/sim/sim_world.gd` | `SimWorld` | The deterministic world: construction from data/config/map, `step()`, spawn/kill/remove/change-owner, lists, queries, credits ledger, checkpoints, dumps. |
| `src/sim/sim_state_hash.gd` | `SimStateHash` | Builds the 16 part digests + per-entity digests + final checksum (§8.2). |
| `src/sim/sim_pipeline.gd` | `SimPipeline` | Fixed 11-stage table; instantiates domain systems by global class name (or takes test overrides). |
| `src/sim/sim_invariants.gd` | `SimInvariants` | Structural invariant checker (INV-1…INV-17, §10.2) used by tests, soak and `opts.invariants_every`. |
| `src/sim/sim_defs.gd` | `SimDefs` | **The** adapter to the data domain: every def field the kernel reads (§7.2). |
| `src/sim/sim_entity.gd` | `SimEntity` | Entity record (§4.2) + `hash_into` + `HASH_EXEMPT`. |
| `src/sim/sim_flags.gd` | `SimFlags` | 64-bit `flags` bit allocation shared by all domains (§4.3). |
| `src/sim/sim_tag.gd` | `SimTag` | Spatial-hash tag bit layout + builders for `need`/`avoid` masks (§4.10). |
| `src/sim/sim_component.gd` | `SimComponent` | Base of all domain components (`hash_into`, reflective `dump`). |
| `src/sim/sim_system.gd` | `SimSystem` | Base of all pipeline stages (hooks §3.3.3). |
| `src/sim/sim_fog_api.gd` | `SimFogApi` | Narrow visibility interface (default: everything visible); vision domain replaces `world.fog`. |
| `src/sim/sim_player.gd` | `SimPlayer` | Player record (§4.6). |
| `src/sim/sim_order.gd` | `SimOrder` | Order record + order-type/status/queue-mode/flag/end-reason constants (§4.7). |
| `src/sim/sim_order_handler.gd` | `SimOrderHandler` | Base class of order handlers. |
| `src/sim/sim_order_system.gd` | `SimOrderSystem` | Stage 5: handler registry, queue semantics, gate, dispatcher, idle hooks. |
| `src/sim/sim_cmd.gd` | `SimCmd` | **MASTER command catalog**: opcodes, wire layouts, metadata, static int-array builders (§6.1). |
| `src/sim/sim_command.gd` | `SimCommand` | Decoded command record + `Err` codes + `to_ints/from_ints`. |
| `src/sim/sim_command_codec.gd` | `SimCommandCodec` | `decode(c)` / `encode(c)` between the int array and the record; malformed-input rejection. |
| `src/sim/sim_command_system.gd` | `SimCommandSystem` | Stage 1: canonical ordering, decode, validation, executor registry, built-in executors (orders, stop, scatter, scuttle, resign, debug). |
| `src/sim/sim_event.gd` | `SimEvent` | Event record layout, core event codes, block map, reason enums (§6.2). |
| `src/sim/sim_event_buffer.gd` | `SimEventBuffer` | Append-only fixed-stride int buffer, throttles, soft cap, `take()`. |
| `src/sim/sim_cleanup_system.gd` | `SimCleanupSystem` | Stage 11: defeat cascade, cleanup hooks, expiry, deaths, removals, elimination, victory. |
| `src/sim/sim_match_config.gd` | `SimMatchConfig` | Sim view of net's `MatchConfig` (seed, map dict, rules, players): `from_dict`, hash, validation. |
| `src/sim/sim_match_rules.gd` | `SimMatchRules` | Match rules (13 int fields). |
| `src/sim/sim_player_slot.gd` | `SimPlayerSlot` | One `players[]` entry (pid, kind, roster id, team, colour, start, handicap, AI level/style/flags). |
| `src/sim/sim_command_log.gd` | `SimCommandLog` | In-memory command record + replay driver for tests/tools (`submit`, `finish`, `play`, flat int form). |

### 2.3 `src/sim/comp/` — component slot files (**stubs created by task SC-04, bodies owned by the named domain**)

| Path | `class_name` | Owner (writes the fields) | Entity/player slot |
|---|---|---|---|
| `comp/sim_comp_move.gd` | `SimCompMove` | movement | `e.move` |
| `comp/sim_comp_combat.gd` | `SimCompCombat` | combat | `e.combat` |
| `comp/sim_comp_air.gd` | `SimCompAir` | combat | `e.air` |
| `comp/sim_comp_carrier.gd` | `SimCompCarrier` | combat | `e.carrier` |
| `comp/sim_comp_econ.gd` | `SimCompEcon` | economy | `e.econ` |
| `comp/sim_comp_prod.gd` | `SimCompProd` | economy (production) | `e.prod` |
| `comp/sim_comp_ability.gd` | `SimCompAbility` | abilities | `e.abil` |
| `comp/sim_comp_stats.gd` | `SimCompStats` | abilities | `e.stats` |
| `comp/sim_comp_vision.gd` | `SimCompVision` | abilities (vision) | `e.vis` |
| `comp/sim_comp_cargo.gd` | `SimCompCargo` | abilities (transports) | `e.cargo` |
| `comp/sim_comp_summon.gd` | `SimCompSummon` | abilities (summons) | `e.summon` |
| `comp/sim_player_econ.gd` | `SimPlayerEcon` | economy | `p.econ` |
| `comp/sim_player_fx.gd` | `SimPlayerFx` | abilities | `p.fx` |
| `comp/sim_player_vision.gd` | `SimPlayerVision` | abilities (vision) | `p.vis` |

### 2.4 Domain systems that plug into the pipeline (names fixed here, stub files created by SC-04 so typed `SimWorld` members parse from day 1)
`SimProductionSystem`(2) `SimEconomySystem`(3) `SimPowerSystem`(4) `SimMovementSystem`(6) `SimAbilitySystem`(7) `SimCombatSystem`(8) `SimZoneSystem`(9) `SimVisionSystem`(10, `stride = 2`) — each stub `extends SimSystem`, sets its own `stage_no` in `_init`, and is **overwritten by the owning domain** (keep `class_name`, `stage_no` and the hooks). `SimStrategicSystem` (economy's stage-4b helper, called by `SimPowerSystem`) is a `RefCounted` stub with the same rule. `SimPipeline` finds all of them through `ProjectSettings.get_global_class_list()` **by class name**, so any folder works; `opts.systems` replaces a stage with a test double.

### 2.5 Tools & tests (created by the tasks in §11)
`tools/py/gen_fp_tables.py` (table generator + verifier) · tests (QA convention `func test_*(t: TestCtx)`, one script per line): `game/tests/core/test_fp.gd`, `test_sim_rng.gd`, `test_checksum.gd`, `test_spatial_hash.gd`, `test_log.gd` · `game/tests/sim/test_sim_world.gd`, `test_sim_lifecycle.gd`, `test_sim_api.gd`, `test_sim_commands.gd`, `test_sim_orders.gd`, `test_sim_events.gd`, `test_sim_config.gd`, `test_sim_map.gd`, `test_sim_free.gd`, `test_sim_command_log.gd`, `test_sim_scenario.gd` (S-CORE-1), `test_sim_determinism.gd`, `test_sim_fuzz.gd`, `test_sim_contract.gd` · test support (never discovered as tests) `game/tests/support/sim_test_kit.gd` (`SimTestKit`), `test_move_handler.gd`, `test_combat_system.gd` · fixtures `game/tests/fixtures/sim_core_fixture.json`, goldens `game/tests/golden/sim_core.json` · cross-platform scenario `game/tests/scenarios/xplat_sim_core.gd` (prints `HASH tick=N hex` lines for `tools/py/xplat_determinism.py`).

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

### 3.1 Conventions that apply to every signature below
* **Ints only** in sim state (DR-1). `bool` is allowed for *parameters and returns*, never as a persistent sim field (use `int` 0/1).
* **Memory ownership.** The world owns every entity/player/component object. Accessors that return `Array[...]` (`units_of`, `entities`, …) return the **live internal array — read-only, stage-stable** (never append/erase/sort it; never keep it across a `step()`). Query functions **fill a caller-owned `PackedInt32Array`** (`resize(0)` first) and return the count. `own_ids`, `moved_prev2` return a **borrowed** array (valid until the next call / list change). `events.take()` transfers ownership of the accumulated `PackedInt32Array` to the caller.
* **Packed arrays are reference types in 4.7.2 `[verified]`**: `var a := b` aliases. Use `.duplicate()` whenever a value crosses an ownership boundary.
* **Systems never store `SimWorld`** (it would form a `RefCounted` cycle and leak). Every hook receives `world` as its first argument.
* **Failure model.** No exceptions. Spawn functions return `null` on failure (entity cap, bad `def_idx`, bad/eliminated owner, match ended); command validation returns a `SimCommand.Err`; queries return `0`/`null`/empty. Callers **must** null-check spawns.
* **Order of iteration** is always ascending entity id unless a doc says otherwise.
* **Underscore members are kernel-internal** (`_dead`, `_remove_q`, `_counted`, …; the few that sibling kernel classes touch carry `@warning_ignore("unused_private_class_variable")`). Domain code must not read or write them (ARCH §5).
* **Names follow the concurrently published domain specs** (`get_entity`, `remove_entity`, `change_owner`, `rel`, `hp_max`, `paid_cost`, `expire_tick`, `container_id`, `query_circle`, `next_int`, `SimComp*`, …); §6.4 lists every remaining difference and its resolution.
* Parameters prefixed `_` in base classes are intentionally unused (silences the linter). Typed `for` loops (`for e: SimEntity in …`) are required over untyped arrays (warning `untyped_declaration` is an error under `--strict`).

### 3.2 `core/` API

#### 3.2.1 `SimConfig` (constants; the only place these numbers live)

| Constant | Value | Meaning / provenance |
|---|---|---|
| `SIM_VERSION` | 1 | bump on *any* change that alters simulation results; mixed into every checksum |
| `TPS`, `TICK_MS`, `TURN_TICKS` | 20, 50, 2 | ARCH §3 (net XR-8) |
| `CHECKSUM_PERIOD` | 20 | ticks between checkpoints (ARCH §6.12; net XR-8) |
| `SNAPSHOT_KEEP` | 64 | checkpoints whose part digests stay available via `checksum_parts_at` (net XR-4: ≥ 64) |
| `CELL`, `CELL_SHIFT` | 1024, 10 | literals equal to `Fp.CELL`/`Fp.CELL_SHIFT` (`core/` files do not reference each other; a test asserts equality) |
| `MAX_PLAYERS`, `NEUTRAL`, `NEUTRAL_SLOT` | 8, −1, 8 | `slot_of(owner)` maps −1→8 |
| `MIN_MAP_CELLS`, `MAX_MAP_CELLS` | 96, 256 | ARCH §3 |
| `DEFAULT_UNIT_CAP`, `DEFAULT_START_CREDITS` | 150, 7500 | ARCH §12; bible `starting_preset` |
| `MAX_ENTITIES` | 8192 | live entities hard cap (8×150 units + structures + wrecks/zones ≈ 2,400 typical) |
| `MAX_ORDERS` | 32 | order-queue length |
| `MAX_CMD_INTS`, `MAX_CMD_IDS` | 1024, 512 | ints per command (net XR-2 envelope 1..1024); ids per command |
| `NEVER` | −1 000 000 | "long ago" sentinel for domain timestamps |
| `EVENT_STRIDE`, `EVENT_SOFT_CAP_INTS` | 10, 1 310 720 | event record width; drop threshold (131 072 events) |
| `SPATIAL_SHIFT` | 12 | bucket = 4 cells |
| `DEFEAT_KILLS_PER_TICK` | 6 | defeat cascade rate |
| `REJECT_GAP` | 10 | `CMD_REJECTED` throttle (ticks per player) |

`static func slot_of(owner: int) -> int` (owner −1 → 8).

#### 3.2.2 `Fp` — fixed-point / integer math (static only)
```gdscript
const CELL := 1024; const CELL_SHIFT := 10
const TURN := 4096; const ANGLE_MASK := 4095; const ANGLE_HALF := 2048; const ANGLE_QUARTER := 1024     # TURN = angle units per full turn (data CMR-1)
const Q16 := 65536; const ISQRT_MAX := 4611686018427387903      # 2^62 - 1
enum Round { TRUNC = 0, FLOOR = 1, CEIL = 2, HALF_UP = 3, HALF_AWAY = 4 }

static func cell_of(v: int) -> int                       # v >> 10 (floor for negatives; hot loops inline it)
static func cell_center(c: int) -> int                   # (c << 10) + 512
static func floor_div(a: int, b: int) -> int             # floor(a/b), b != 0
static func floor_mod(a: int, b: int) -> int             # result has the sign of b, 0 <= r < |b| for b > 0
static func ceil_div(a: int, b: int) -> int              # ceil(a/b)
static func isqrt(n: int) -> int                         # EXACT floor(sqrt(n)), n clamped to [0, ISQRT_MAX]
static func dist2(dx: int, dy: int) -> int               # dx*dx + dy*dy   (|dx|,|dy| < 2^30)
static func dist(dx: int, dy: int) -> int               # isqrt(dist2) -- floor Euclidean distance
static func mul_div(a: int, b: int, c: int, mode: int = Round.HALF_UP) -> int   # a*b/c, c != 0, |a*b| < 2^62
static func pct(v: int, p: int) -> int                   # v*p/100 half-up (fast path for v,p >= 0)
static func apply_pct(base: int, delta_pct: int) -> int  # base*(100+delta)/100 half-up
static func apply_layers(base: int, layers_bp: PackedInt32Array, min_pct_of_base: int = 0, max_pct_of_base: int = 0) -> int
static func clamp(v: int, lo: int, hi: int) -> int       # (name is fixed by ARCH; shadows the builtin -- add @warning_ignore("shadowed_global_identifier") if the checker complains)
static func lerp_i(a: int, b: int, num: int, den: int) -> int   # a + (b-a)*num/den, half-up
static func approach(v: int, target: int, step: int) -> int      # move v toward target by <= step
static func mul_q16(a: int, q: int) -> int               # (a*q + 32768) >> 16  (round half up, arithmetic shift)
static func sin(a: int) -> int                           # Q16, a any int (masked to 0..4095)
static func cos(a: int) -> int                           # sin(a + 1024)
static func atan2(dy: int, dx: int) -> int               # angle 0..4095; atan2(0,0) = 0
static func angle_between(x0: int, y0: int, x1: int, y1: int) -> int
static func angle_norm(a: int) -> int                    # a & 4095  (= combat's wrap_angle)
static func angle_diff(from_a: int, to_a: int) -> int    # shortest signed difference in [-2048, 2047]
static func turn_toward(cur: int, target: int, max_step: int) -> int   # rotate <= max_step toward target
static func rot_x(ox: int, oy: int, a: int) -> int       # rotate offset (ox,oy) by angle a (Q16 table), x component
static func rot_y(ox: int, oy: int, a: int) -> int
static func step_x(angle: int, d: int) -> int            # mul_q16(d, cos(angle)) -- displacement of a step of length d
static func step_y(angle: int, d: int) -> int            # mul_q16(d, sin(angle))
# ---- load-time only (the ONLY place a float touches a sim number; DR-10; lint-allow'ed) ----
static func milli(f: float) -> int                       # roundi(f * 1000.0): the single float->int rounding step
static func cells_to_units(milli_cells: int) -> int      # (mc*1024 + 500) / 1000
static func seconds_to_ticks(milli_seconds: int) -> int  # ceil(ms * 20 / 1000)
static func cps_to_units_per_tick(milli_cps: int) -> int # (mcps*1024 + 10000) / 20000
static func self_test() -> PackedStringArray             # [] = OK; guards engine facts (§8.4); call at boot and in tests
const TABLE_DIGEST_SIN := 2046802713; const TABLE_DIGEST_ATAN := 1306073121
```
**Trap `[verified]`:** inside `fp.gd` an *unqualified* `sin(x)`/`cos(x)`/`atan2(y,x)` resolves to the **float builtin**, not the static method. All internal uses read the table directly (`FpTables.SIN_Q16[...]`) or are written `Fp.sin(...)`. `self_test()` exists because the prototype hit exactly this bug. The repo lint (L003) flags unqualified `sin( cos( atan2( sqrt( … )` in `core/` and `sim/`; the two legitimate float uses carry `# lint-allow: L003 <reason>` (the `sqrt` seed in `isqrt`, `milli`).

#### 3.2.3 `SimRng`
```gdscript
var s0: int; var s1: int; var s2: int; var s3: int          # 4 x uint32 lanes (in the checksum)
func _init(seed_value: int = 1)
func reseed(seed_value: int) -> void       # any int64 (negative allowed); never leaves all-zero state
func next_u32() -> int                     # 0 .. 2^32-1
func next_int(n: int) -> int               # [0, n), 1 <= n <= 2^30; (next_u32() * n) >> 32   (combat/economy name; was `below`)
func range_i(lo: int, hi: int) -> int      # INCLUSIVE both ends (economy/AI name; was `range_int`)
func chance_pct(p: int) -> bool            # next_int(100) < p
func chance_bp(p: int) -> bool             # next_int(10000) < p
func shuffle(a: Array) -> void             # Fisher-Yates, i = n-1 .. 1, j = next_int(i+1)
func hash_into(buf: PackedInt32Array) -> void      # appends s0..s3
func get_state() -> PackedInt32Array / func set_state(st: PackedInt32Array) -> void    # 4 lanes (int32-wrapped; set_state masks & 0xFFFFFFFF)
static func mul32(a: int, c: int) -> int   # (a*c) mod 2^32 for a,c < 2^32 without int64 overflow
```
Exactly **one** RNG exists per world (`world.rng`), draws happen in fixed system order (DR-2). The only kernel draw is `SCATTER` (one `range_i(-3072,3072)` for x then one for y per actor, ascending id). Presentation code, AI and lobby use their own non-sim RNGs.

#### 3.2.4 `Checksum`
```gdscript
const FNV_OFFSET := 0x811C9DC5; const FNV_PRIME := 0x01000193; const EMPTY_DIGEST := 0xD98C1DD4
var h: int                                   # accumulator instance state
func reset() -> void
func add(v: int) -> void                     # FNV-1a over the 4 LE bytes of (v & 0xFFFFFFFF)
func add64(v: int) -> void                   # overflow-safe: low 32 bits then bits 32..63
func add_packed(a: PackedInt32Array) -> void # mix(size), then mix(digest32(a))
func value() -> int                          # finalize(h) -- murmur3 fmix32, 0..2^32-1
static func mix(hv: int, v: int) -> int      # one FNV-1a word step, returns new state
static func mix64(hv: int, v: int) -> int
static func fnv_bytes(b: PackedByteArray, hv: int = FNV_OFFSET) -> int      # classic byte-wise FNV-1a (fnv("foobar") = 0xBF9CF968, fnv("a") = 0xE40C292C)
static func fnv_string(s: String, hv: int = FNV_OFFSET) -> int              # over UTF-8 bytes
static func finalize(hv: int) -> int
static func digest32(a: PackedInt32Array) -> int       # FAST PATH: MD5(a.to_byte_array() little-endian), first 4 digest bytes as LE u32; empty array -> EMPTY_DIGEST
static func digest32_bytes(a: PackedByteArray) -> int  # same for bytes
```
`digest32` uses a `HashingContext` (a `RefCounted`, allowed; MD5 is specified so it is platform independent). **`HashingContext.update()` errors on empty input `[verified]` — hence the explicit `EMPTY_DIGEST` (= first 4 bytes of MD5("") as LE u32).** The FNV-1a parameters equal data's `DefHash` (offset 2166136261, prime 16777619, byte-wise) — one algorithm across the code base (data CMR-2); the data hash enters the checksum through the `world` part (§8.2), so no separate "seed" entry point is needed.

#### 3.2.5 `SpatialHash`
```gdscript
const SHIFT := 12                                            # 4096 units = 4 cells per bucket
func _init(map_w_cells: int, map_h_cells: int)
func insert(id: int, x: int, y: int, tag: int) -> void       # id >= 1; positions clamped into the map
func remove(id: int) -> void;  func contains(id: int) -> bool
func move(id: int, x: int, y: int) -> void                   # updates coords; re-buckets only when the bucket changes
func set_tag(id: int, tag: int) -> void;  func tag_of(id: int) -> int
func x_of(id: int) -> int;  func y_of(id: int) -> int
func query_circle(x: int, y: int, r: int, out: PackedInt32Array, need: int = 0, avoid: int = 0) -> int     # (was `query_radius`)
func query_rect(x0: int, y0: int, x1: int, y1: int, out: PackedInt32Array, need: int = 0, avoid: int = 0) -> int
func cell_bucket(cx: int, cy: int, out: PackedInt32Array) -> int     # ids stored in the bucket that contains cell (cx, cy), ascending
```
A candidate passes iff `(tag & need) == need and (tag & avoid) == 0`; the circle test is `dx²+dy² <= r²` on **entity centres**; `out` is cleared, filled and **sorted ascending** (native `PackedInt32Array.sort()`, a total order on ints); returns `out.size()`. Entities inside a container are not in the hash (`SimWorld.set_inside` removes them), dead entities carry no `ALIVE` bit. Add the maximum entity radius (structures: ≤ 3 cells) to `r` when edge distance matters. Cargo code must use `SimWorld.set_inside`, not `insert/remove` directly.

#### 3.2.6 `Log`
```gdscript
enum Level { DEBUG, INFO, WARN, ERROR, OFF }
static var level: int = Level.INFO;  static var quiet: bool = false;  static var sink: Callable;  static var ring: PackedStringArray    # last 256 lines
static func debug(tag: String, msg: String) -> void      # also info / warn / error ; error -> push_error, warn -> push_warning, others -> print, unless `sink` is valid
```
`sink` (`func(level: int, tag: String, msg: String)`) is the injectable output (net XR-19, tests capture with it). `Log` is the only code allowed to call `print`/`push_*` (lint L006). It has no influence on the sim.

### 3.3 Base types every domain extends

#### 3.3.1 `SimSystem`
```gdscript
class_name SimSystem extends RefCounted
var stage_no: int; var stride: int = 1; var stride_offset: int = 0     # stage runs when stride == 1 or (world.tick + stride_offset) % stride == 0
func system_name() -> String                                # default = SimPipeline.STAGE_NAMES[stage_no - 1] ("commands","production","economy","power","orders","movement","abilities","combat","zones","vision","cleanup")
func init_world(world: SimWorld) -> void                    # once, after ALL systems are constructed and players exist, BEFORE initial entities: create player components, register executors/handlers, replace world.fog
func update(world: SimWorld) -> void                        # the stage body
func on_spawn(world: SimWorld, e: SimEntity) -> void        # synchronously inside spawn_entity: fields set, e in by_id / spatial hash / counters and (STRUCTURE / NEUTRAL) already occupying its map footprint, SPAWNED already emitted, NOT yet in the lists; allocate your component here
func on_dying(world: SimWorld, e: SimEntity, cause: int, killer_id: int, killer_pid: int) -> void   # stage 11, once per kill(), ascending id, BEFORE removal: wreck creation, cargo ejection, claims, EV_DEATH; may call world.kill() on others (processed in the same cleanup) and world.remove_deferred() to keep the corpse
func on_remove(world: SimWorld, e: SimEntity, reason: int) -> void   # just before the entity leaves the world (dead or silently removed): drop every reference to it; last chance to read it
func on_owner_changed(world: SimWorld, e: SimEntity, old_owner: int) -> void
func on_player_eliminated(world: SimWorld, pid: int) -> void          # clear queues, cancel superweapon, ...
func order_gate(world: SimWorld, e: SimEntity, o: SimOrder) -> int   # veto a new order (SimCommand.Err; default OK): "uncontrollable while packing", EMP, ...
func cleanup(world: SimWorld) -> void                       # start of stage 11 after the defeat cascade: expire wrecks, finish dying entities, hand removals to the world
func hash_state(world: SimWorld, buf: PackedInt32Array) -> void       # append ALL authoritative system-private ints (§8); fixed order
func on_debug(world: SimWorld, pid: int, mode: int, target: int, def_idx: int, count: int, x: int, y: int) -> int   # DEBUG command modes >= 4 (needs rules.allow_debug): return -1 = "not my mode", else a SimCommand.Err (0 = done); offered to the stages in order until one answers (vision: 4 reveal, combat: 5 set hp, economy: 6 charge)
```
Rules for hook implementers: (1) `on_spawn` may touch **only its own component** (never assume another domain's component exists yet); (2) hooks are invoked in stage order 1→11 for every system; (3) a hook must never spawn an entity of the kind currently being removed in the same call chain without a terminating condition (cleanup runs ≤ 16 rounds per tick; leftovers continue next tick); (4) **kill hooks run at stage 11, not at the `kill()` call** — between the call and stage 11 the entity is `F_DEAD`, `hp == 0`, invisible to spatial queries and no longer counted, so systems that run in between must simply skip it.

#### 3.3.2 `SimComponent` and `SimFogApi`
```gdscript
class_name SimComponent extends RefCounted
const HASH_EXEMPT: PackedStringArray = []        # subclasses may shadow: names of DERIVED fields that are intentionally not hashed
func hash_into(buf: PackedInt32Array) -> void    # append every authoritative field, fixed order, ints only (append 64-bit values as two ints)
func dump() -> Dictionary                        # reflective default

class_name SimFogApi extends RefCounted           # vision domain replaces world.fog in its init_world()
func cell_visible(pid: int, cx: int, cy: int) -> bool          # currently visible to pid's team (shared vision included)
func cell_explored(pid: int, cx: int, cy: int) -> bool
func entity_visible(pid: int, e: SimEntity) -> bool             # fog AND camouflage/detection
func entity_revealed(pid: int, e: SimEntity) -> bool            # camouflage/detection only (fog ignored): omniscient AI reads
func fog_bytes(pid: int) -> PackedByteArray                     # w*h bytes: 0 shroud, 1 fog(explored), 2 visible -- for the view (vision domain adds it)
func fog_version(pid: int) -> int                               # increments when fog_bytes changed (texture upload gate)
func ghosts(pid: int) -> Array                                  # remembered structures of pid: records {eid, def_idx, owner, x, y, facing, hp_pct, seen_tick} (vision domain's type); default []
func ghost_version(pid: int) -> int                             # increments on any change of ghosts(pid) (view upload gate); default 0
func decoy_identified(pid: int, e: SimEntity) -> bool           # pid has identified e as a decoy (detector contact); default false
```
All defaults are "everything visible / nothing known" so a world without the vision domain still runs. Consumers call the world wrappers `world.cell_visible / cell_explored / entity_visible` (§3.4.4), not the stage object.

#### 3.3.3 Component slots (policy in §4.5)
`SimEntity` slots: `move, combat, air, carrier, econ, prod, abil, stats, vis, cargo, summon`. `SimPlayer` slots: `econ, fx, vis`. One class per slot (§2.3); the owning domain defines its fields, nests sub-objects freely (`SimCompCombat` may own its wreck block, mount state, …) and hashes them in its `hash_into`.

#### 3.3.4 Named systems on the world
`world.commands, production, economy, power, orders, movement, abilities, combat, zones, vision, cleanup` are typed members (class names of §2.4) assigned by `SimPipeline` in stage order; `world.strategic` (economy's helper) is assigned by economy in `init_world`. Domains call each other through these members (`world.combat.heal(world, e, n)`), never through globals.

#### 3.3.5 `SimDefs` — the only data adapter
```gdscript
class_name SimDefs extends RefCounted                     # world.defs, built from world.data (a GameData) at construction
const DEF_KIND: PackedInt32Array = [0, 1, 0, 7, 8]        # SimEntity.Kind -> DefEnums.Kind (UNIT 0, STRUCTURE 1, WRECK->UNIT, ZONE 7, NEUTRAL 8)
func has_def(kind: int, def_idx: int) -> bool
func hp_max(view: DefPlayerView, kind: int, def_idx: int) -> int     # owner's current max hp (static layers + permanent research: view.resolved_stats(...)[HEALTH]); view == null -> base value (neutral)
func radius(kind: int, def_idx: int) -> int
func home_layer(kind: int, def_idx: int) -> int                       # SimEntity.Layer at spawn
func cap_weight(kind: int, def_idx: int) -> int                       # DefUnit.pop for UNIT (0 = exempt), 0 otherwise
func flags_init(kind: int, def_idx: int) -> int                       # UF_* -> F_* (non-blocking, no repair/capture/salvage); ZONE: untargetable + no select
func is_rebuilder(kind: int, def_idx: int) -> bool                    # unit def carries AbilityKind.DEPLOY_STRUCTURE (23) = MCV: keeps its owner alive
```
Footprints are **not** a data matter for the kernel: the def → footprint table belongs to the map (`map.footprint_of(kind, def_idx)`, §3.4.5), which also keeps `src/data` free of `Map*` identifiers (lint L005: `core <- data <- map <- sim`). All reads are pure and allocation-free after construction (the `_rebuilder` byte table is built once). §7.2 lists the exact `Def*` members behind each method.

---

### 3.4 `SimWorld`

#### 3.4.1 Construction
```gdscript
func _init(game_data: GameData, cfg: SimMatchConfig, map_data: MapData, opts: Dictionary = {})
static func create(game_data: GameData, cfg: SimMatchConfig, map_data: MapData, opts: Dictionary = {}) -> SimWorld   # the validating factory for real matches (net's world_builder, app, tools): null + Log.error for every problem — cfg.validate(...) messages, or spawns / neutrals that are not whole records of their strides
```
`opts` keys (all optional): `events: bool = true` (event buffer on) · `disable: PackedStringArray` (class names of domain stages replaced by a plain `SimSystem` stub, e.g. `["SimCombatSystem"]`; the matching typed member, `world.combat`, is then `null`) · `systems: Array` (`SimSystem` instances whose `stage_no` replaces that stage — test doubles that must subclass the stub class of the stage so the typed member accepts them) · `snapshot_keep: int = 0` (keep the last N `dump_state()` texts at checkpoints for desync forensics) · `invariants_every: int = 0` (run `SimInvariants.check` every N ticks and `Log.error` each violation) · `checkpoint_interval: int = 20` (debug only: every peer of a real match uses `SimConfig.CHECKSUM_PERIOD`).
Construction order (fixed, deterministic): copy inputs → `defs = SimDefs.new(data)` → `map = map_data.clone_fresh()` → `rng = SimRng.new(cfg.seed_value)` → `spatial` → players (array sized `max pid + 1`; **pid = the config's pid**; a pid without an entry becomes a *vacant* player: `controller = NONE`, `eliminated = 1`; active players get `roster = data.rosters[data.roster_idx(slot.roster)]`, `view = DefPlayerView.new(data, roster)`, `credits = start_credits × handicap / 100` truncated) → relation table → `SimPipeline.create(opts.disable, opts.systems)` → typed members → `for s in stages: s.init_world(self)` → initial entities → flush → checkpoint at tick 0 (`checksum_log = [0, checksum]`).

**Initial entities** (`SPAWN_INITIAL`, flag `F_INITIAL`), in this order: (1) if `rules.neutral_structures`: for each record of `map.neutrals` (stride `MapData.NEUTRAL_STRIDE = 8`: `[kind, cell (top-left), w, h, variant, flags, orbit, reserved]`) with `map.neutral_def_for_kind(kind) >= 0`, a STRUCTURE of owner −1 whose footprint centre is `((cell mod map.w)·1024 + w·512, (cell div map.w)·1024 + h·512)` (`cell` is a cell **index** `cy·w + cx`; kinds mapped to −1, i.e. the scenery blockers, are static map data and spawn nothing); (2) for each active player in ascending pid the start entity of `rules.start_mode` — an HQ STRUCTURE, or an MCV UNIT facing `map.spawns[rec + 2]` — centred on the spawn cell `map.spawns[rec + 1]` (a cell index; centre = `(cell mod map.w, cell div map.w)·1024 + 512`), where `rec = slot·MapData.SPAWN_STRIDE` and `slot = players[].start` (a spawn **slot** index; the lobby chooses slots, `map.fair_slot_order(n)` gives the fair ones). The spawn cell is the centre cell of the start footprint (a 3×3 HQ covers the cell and its 8 neighbours).

#### 3.4.2 Stepping and command intake
```gdscript
func submit_raw(pid: int, ints: PackedInt32Array) -> void   # queue [op, fields…, ids…] for the NEXT step(); pid is stamped by the caller (net: from the connection). Never fails: malformed input is rejected inside stage 1 (counted in st_rejected)
func submit(cmd: SimCommand) -> void                        # = submit_raw(cmd.pid, cmd.to_ints())
func step() -> void                                         # THE only way time advances. See §5.3.
func run(n: int) -> void                                    # n x step()
func take_pending() -> Array[SimCommand]                    # internal (SimCommandSystem)
```
(The charge's `tick()` is named `step()`: a GDScript class cannot have a member `tick` **and** a method `tick`, and ARCH §6.12 fixes the field name `tick`.) `step()` decodes and executes the queued commands (stage 1) and, while the match is running, stages 2–11, then increments `tick`. **One `step()` = one 50 ms simulation tick.** Net's turn is `for each command: submit_raw(pid, ints)` in canonical order, then `step(); step()` (`TURN_TICKS = 2`; the commands execute in the first step). After `MATCH_ENDED`, `step()` only drops pending commands.

#### 3.4.3 State fields (read-only for everyone except the owning domain)
```gdscript
var config: SimMatchConfig; var rules: SimMatchRules; var data: GameData; var defs: SimDefs; var map: MapData     # map = private clone
var tick: int                                            # completed ticks (0 right after construction)
var rng: SimRng
var players: Array[SimPlayer]; var humans_total: int     # index = pid (vacant pids included)
var by_id: Array[SimEntity]                              # sparse, index = entity id; null = free/removed
var entities: Array[SimEntity]                           # ALL live entities ascending id (includes F_DEAD until removal)
var units: Array[SimEntity]; var structures: Array[SimEntity]; var wrecks: Array[SimEntity]; var zone_ents: Array[SimEntity]; var neutrals: Array[SimEntity]
var next_id: int; var next_proj_id: int
var spatial: SpatialHash                                 # (`hash` would shadow a builtin: lint warning)
var stages: Array[SimSystem]; var commands: SimCommandSystem; var orders: SimOrderSystem; var cleanup: SimCleanupSystem     # + the domain members of §3.3.4
var fog: SimFogApi; var events: SimEventBuffer
var match_state: int; var winner_team: int; var end_reason: int; var end_tick: int   # MATCH_RUNNING = 0 / MATCH_ENDED = 1
var checksum_log: PackedInt64Array                       # pairs [tick, checksum(u32, >= 0)] every 20 ticks incl. tick 0
var report_ring: Array[Dictionary]; var last_report: Dictionary    # last SNAPSHOT_KEEP (64) checkpoint reports {tick, final, parts, entity_digests}
var snapshot_ring: Array[String]                         # dump_state() texts if opts.snapshot_keep > 0
```
Enums: `EndReason { ELIMINATION = 0, NO_HUMANS = 1, DRAW = 2 }`, `Rel { SELF = 0, ALLY = 1, ENEMY = 2, NEUTRAL = 3 }`, **`Cause { DAMAGE = 0, SCUTTLE = 1, EXPIRE = 2, ORPHAN = 3, CARGO = 4, RESIGN = 5, SCRIPT = 6 }`** (why an entity died; numbering = combat's `CAUSE_*`, 5 = its owner was eliminated). Constant `CHECKSUM_PART_NAMES` (§8.2).

#### 3.4.4 Queries (complexity in brackets; `n` = list length)
```gdscript
func get_entity(id: int) -> SimEntity                    # [O(1)] null if never allocated / already removed (dead-but-not-removed entities ARE returned)
func is_alive(id: int) -> bool                           # [O(1)] exists and not F_DEAD|F_REMOVING
func units_of(owner: int) -> Array[SimEntity]            # [O(1) to fetch] owner -1 = neutral. live internal list, ascending id
func structures_of(owner: int) -> Array[SimEntity]
func own_ids(pid: int) -> PackedInt32Array               # [cached per tick/list change] ascending ids of the live units + structures of pid (borrowed)
func team_of(owner: int) -> int                          # [O(1)] -1 for neutral / invalid
func rel(a: int, b: int) -> int                          # [O(1)] Rel.* between two OWNERS (pids or -1); vacant pids are NEUTRAL to everyone
func are_enemies(a: int, b: int) -> bool
func are_allied(a: int, b: int) -> bool                  # SELF or ALLY (false for neutral and vacant pids)
func struct_at(cx: int, cy: int) -> int                  # id of the STRUCTURE / NEUTRAL entity occupying the cell (map.occupant_at), 0 = free or outside the map
func cell_visible(pid: int, cx: int, cy: int) -> bool;  func cell_explored(pid: int, cx: int, cy: int) -> bool;  func entity_visible(pid: int, e: SimEntity) -> bool   # forward to world.fog (view, audio, AI read the world, never the stage object)
func non_enemy_mask(pid: int) -> int                     # `avoid` mask leaving only enemies of pid: own + allied + neutral owner bits
func query_circle(x: int, y: int, r: int, out: PackedInt32Array, need: int = SimTag.ALIVE, avoid: int = 0) -> int   # [~5 us r=4 cells, ~11 us r=8 cells]
func query_rect(x0: int, y0: int, x1: int, y1: int, out: PackedInt32Array, need: int = SimTag.ALIVE, avoid: int = 0) -> int
func nearest(x: int, y: int, r: int, need: int = SimTag.ALIVE, avoid: int = 0, exclude_id: int = 0) -> int   # id or 0; ties -> lowest id
func enemies_in_circle(viewer: int, x: int, y: int, r: int, out: PackedInt32Array, ignore_fog: bool = false) -> int   # alive enemy UNITs+STRUCTUREs; fog via fog.entity_visible, or with ignore_fog only camouflage via fog.entity_revealed
func visible_enemy_ids(viewer: int, out: PackedInt32Array) -> int        # [O(entities)] all enemy units + structures passing fog.entity_visible
func find_idle_units(pid: int, out: PackedInt32Array) -> int   # [O(units of pid)] alive, on map, selectable, empty order queue
func find_by_def(kind: int, def_idx: int, pid: int, out: PackedInt32Array) -> int   # [O(units or structures of pid)] alive entities of that (kind, def), ascending id
func entities_visible_to(pid: int, out: PackedInt32Array) -> int          # [O(entities)] own + allied + enemy entities passing fog.entity_visible
func moved_prev2() -> PackedInt32Array                   # ids whose position changed during this tick so far or the previous one (ascending, borrowed)
func alloc_proj_id() -> int                              # separate id space for combat's pooled projectiles
```
`need`/`avoid` are `SimTag` masks (§4.10). Enemy ground units of player P: `need = SimTag.ALIVE | SimTag.kind_bit(UNIT) | SimTag.layer_bit(GROUND)`, `avoid = world.non_enemy_mask(P)`. Everything else the AI/UI need is a loop over `units_of/structures_of/own_ids` (≤ 150 units per player); there is deliberately **no** string-keyed or def-keyed index — tech prerequisites and power state are economy's counters, not the kernel's.

#### 3.4.5 Spawn, kill, removal, ownership (all deterministic; safe to call from any system)
```gdscript
func spawn_entity(kind: int, def_idx: int, owner: int, x: int, y: int, facing: int = 0, flags: int = 0, parent: int = 0, paid_cost: int = 0, reason: int = SimEvent.SPAWN_SCRIPT) -> SimEntity   # THE spawn path (combat's `spawn_raw`, economy's `spawn_entity`)
func spawn_unit(def_idx: int, owner: int, x: int, y: int, facing: int = 0, flags: int = 0, paid_cost: int = 0, parent: int = 0, reason: int = SimEvent.SPAWN_SCRIPT) -> SimEntity
func spawn_structure(def_idx: int, owner: int, x: int, y: int, facing: int = 0, flags: int = 0, paid_cost: int = 0, parent: int = 0, reason: int = SimEvent.SPAWN_PLACED) -> SimEntity   # x,y = footprint CENTRE (sub-cell units); facing = 1024 x orientation (0..3 quarter turns clockwise) for rotatable footprints; same positional layout as spawn_unit
func spawn_zone(def_idx: int, owner: int, x: int, y: int, life_ticks: int, parent: int = 0, flags: int = 0) -> SimEntity      # life_ticks > 0 sets expire_tick = tick + life_ticks
func spawn_wreck(from: SimEntity, salvageable: bool, hp: int = 1, life_ticks: int = 0) -> SimEntity   # kind WRECK, dead unit's def / original owner / paid_cost; called from a combat on_dying hook
func kill(e: SimEntity, cause: int, killer_id: int = 0, killer_pid: int = -1) -> void   # SimWorld.Cause; F_DEAD, hp = 0, off the spatial queries, no longer counted; hooks + removal happen in stage 11 of THIS tick (no-op if already gone / match ended)
func remove_entity(id: int, reason: int) -> bool         # REM_* ; silent removal (sold, deployed, consumed wreck, expiry); no on_dying, no wreck; false if unknown / already leaving
func remove_deferred(id: int, at_tick: int) -> void      # removal at stage 11 of the first tick >= at_tick; on a DEAD entity it keeps the corpse (crash sequence) until then
func change_owner(id: int, new_owner: int, reason: int = 0) -> bool   # capture: re-lists, re-counts, hp_max from the new owner's view (hp keeps its ratio), clears orders, on_owner_changed + OWNER_CHANGED; false for invalid / eliminated owner or same owner
func eliminate(pid: int, reason: int) -> void           # SimPlayer.Elim.*; the defeat cascade is executed by cleanup
func end_match(winner_team: int, reason: int) -> void
```
`spawn_entity` semantics: returns `null` if the match ended, `live >= MAX_ENTITIES`, `defs.has_def(kind, def_idx)` fails, `owner` is not −1 or a valid pid, or `owner` is an **eliminated** player (wrecks excepted). Otherwise it assigns `id = next_id++`; `team`, `radius`, `layer = defs.home_layer`, `flags = defs.flags_init | flags` (+`F_NO_UNIT_CAP` for every non-UNIT and for units whose `cap_weight` is 0), `hp = hp_max = defs.hp_max(owner's view)`, `container_id = −1`, `prev = pos`, `born = tick`; registers in `by_id`, the spatial hash and the owner's counters **immediately**; parks it for the lists (visible in lists after the current stage); marks `parent.F_HAS_CHILDREN`; emits `SPAWNED` (**always the first event of the entity**); for STRUCTURE / NEUTRAL entities without `F_NO_FOOTPRINT` occupies the map footprint (`map.occupy`, §5.4 "Footprints") and emits `NAV_CHANGED`; then calls `on_spawn` on every stage (hooks and validation see the occupied cells). Counting: `_count_in` adds the unit's cap weight to `unit_count`, `1` to `struct_count` / `rebuilders` **unless** the entity is `F_TEMPORARY | F_DECOY | F_SUMMONED` (temporary assets never keep a player alive), and to `st_*_built` unless the reason is `SPAWN_INITIAL` / `SPAWN_WRECK`. Counters drop at `kill()` / `remove_entity()` time, not at final removal.

#### 3.4.6 Motion, containers, hit points (the only writers of `x/y`, `layer`, `container_id`, `hp_max`)
```gdscript
func set_pos(e: SimEntity, x: int, y: int, teleport: bool = false) -> void   # clamps into the map, updates the spatial hash unless F_INSIDE, maintains prev_x/prev_y/vx/vy and moved_prev2 (below); teleport = true snaps (prev = pos, v = 0)
func set_layer(e: SimEntity, layer: int) -> void                              # keeps the hash tag in sync
func set_inside(e: SimEntity, container_id: int, inside: bool) -> void       # loaded/garrisoned: F_INSIDE + container_id (≥ 0), removed from / re-inserted into the hash; leaving sets container_id = -1
func set_hp_max(e: SimEntity, new_max: int) -> void                          # new hp_max; hp keeps its fraction (half-up, never below 1 while alive)  (= combat's rescale_hp core)
```
**Motion bookkeeping (kernel-maintained, hashed):** the first `set_pos` of a tick stamps the entity as a *mover* (`_pos_tick = tick`, appended to `_moved`) and records `prev_x/prev_y` = position at the start of the tick; every call sets `vx/vy = pos − prev` (displacement this tick, accumulating over several calls). At the start of the next `step()` the previous tick's movers get `prev = pos, v = 0`. Consequences: for every entity that did not move during the last tick `prev == pos ∧ v == 0` (INV-15); after a step the view interpolates `prev → pos` with no per-tick capture pass; combat's lead calculation reads `t.vx/vy` directly. `moved_prev2()` = movers of this tick ∪ movers of the previous tick.

#### 3.4.7 Credits ledger (the only writers of `SimPlayer.credits`; domains must use these, never edit `credits` directly)
```gdscript
# reasons live in SimEvent: CASH_START 0, CASH_HARVEST 1, CASH_SALVAGE 2, CASH_REFUND 3, CASH_SELL 4, CASH_SPEND 5, CASH_SCRIPT 6
func add_credits(pid: int, amount: int, reason: int, x: int = 0, y: int = 0, source_id: int = 0, silent: bool = false) -> int   # returns the credits actually added (economy's `earn`)
func try_spend(pid: int, amount: int, reason: int = SimEvent.CASH_SPEND, source_id: int = 0, silent: bool = false) -> bool     # false (no change) if credits < amount (economy's `spend`)
func unit_cap_room(pid: int) -> int                     # rules.unit_cap - unit_count, >= 0
```
`silent = true` suppresses the `CASH` event (progressive per-tick payments). **Handicap** (net XR-9): `HARVEST` / `SALVAGE` income of a player with `handicap != 100` is scaled by `handicap / 100` with an exact remainder carry (`t = amount × handicap + income_frac; credited = t / 100; income_frac = t % 100`; hashed) — five 1-credit pulses at 120 % pay exactly 6; other reasons and all costs are never scaled. Statistics: `st_credits_earned += credited` for HARVEST/SALVAGE with `credited > 0`; `st_credits_spent += −credited` for negative amounts and `−= credited` for `REFUND` (net spend).

#### 3.4.8 Checksum, net adapter surface and diagnostics
```gdscript
func checksum() -> int                              # compute NOW (≈1.75 ms @ 1,700 entities); the periodic values are in checksum_log
func checksum_at(t: int) -> int                     # u32 recorded at the end of tick t (t % CHECKSUM_PERIOD == 0), -1 if that tick never happened   (net XR-4)
func report_at(t: int) -> Dictionary                # {} or {tick, final, parts: PackedInt32Array (16), entity_digests: PackedInt32Array [id, digest32, ...]} for a retained checkpoint (SNAPSHOT_KEEP = 64); QA's "sections" = zip(CHECKSUM_PART_NAMES, parts)
func checksum_parts_at(t: int) -> PackedInt32Array  # the 16 part digests of that snapshot (same length/order on every peer; int32-wrapped: mask & 0xFFFFFFFF), empty if older than SNAPSHOT_KEEP
func checksum_part_names() -> PackedStringArray     # = CHECKSUM_PART_NAMES
func map_hash() -> int                              # map.map_hash() (lobby / replay handshake value of the map)
func is_match_over() -> bool
func match_result() -> Dictionary                   # {winner_team: int (-1 none), reason: int (EndReason)}
func is_player_active(pid: int) -> bool             # false when eliminated / vacant
func clear_events() -> void
func dump_state() -> String                         # deterministic text: header, RNG, one line per player / entity / system with EVERY checksummed int
func dump_entity(e: SimEntity) -> Dictionary        # reflective, field names -> values (debug UI, tests)
```
This is exactly the surface net's `NetSimAdapterWorld` forwards to (`current_tick → tick`, `submit_command → submit_raw`, `step`, `checksum_at`, `checksum_parts_at`, `checksum_part_names`, `checksum_now → checksum`, `map_hash`, `is_match_over`, `match_result`, `is_player_active`, `dump_state`, `clear_events`); net keeps all pacing, pause, replay-file and desync-report logic.

### 3.5 Commands

```gdscript
class_name SimCmd extends RefCounted     # MASTER catalog (§6.1): opcode constants, layouts, metadata, static int-array builders
const MOVE := 1; const STOP := 2; … const RESIGN := 250                      # one const per catalog row
const FT_TARGET … FT_ANGLE                                                   # storage slot a wire field decodes into (8 slots)
const M_IDS, M_UNITS, M_STRUCTS, M_ANY, M_POS, M_QUEUE, M_ANGLE, M_CELL      # per-op metadata bits (§6.1)
static func is_known(op: int) -> bool;  static func name_of(op: int) -> String
static func layout_of(op: int) -> PackedInt32Array;  static func meta_of(op: int) -> int
static func build(op: int, values: Array, ids: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array   # [op, values…, sorted-unique ids…]
static func all_ops() -> PackedInt32Array                      # every op of the catalog, ascending (schema-aware fuzzing, docs)
static func move(ids: PackedInt32Array, x: int, y: int, mode: int = 0, flags: int = 0) -> PackedInt32Array   # …one static builder per catalog row, `ids` first, wire order after; UI, AI and tests use ONLY these
```
```gdscript
class_name SimCommand extends RefCounted          # the DECODED record; the canonical transport form is the int array
enum Err { OK = 0, UNKNOWN_OP, BAD_PLAYER, ELIMINATED, MATCH_ENDED, BAD_FIELD, NO_ACTORS, NO_TARGET, WRONG_KIND, NOT_AVAILABLE, NO_PREREQ, NO_CREDITS, QUEUE_FULL, BAD_SITE, NO_VISION, NOT_READY, UNIT_CAP, BLOCKED, DISABLED, NOT_ALLOWED, BAD_ORDER, INSIDE }
var op: int; var pid: int; var ids: PackedInt32Array          # ids: ascending, unique, > 0
var target: int; var x: int; var y: int; var def: int; var count: int; var mode: int; var flags: int; var angle: int    # the 8 field slots; a field the op's layout does not carry is 0
var detail: int                                               # an executor may set a domain-specific reason next to the Err it returns (economy RSN_*, abilities reasons); surfaces in CMD_REJECTED.d
var raw: PackedInt32Array; var actors: Array[SimEntity]      # RUNTIME: the submitted ints; actors filled by SimCommandSystem after ownership/existence filtering (executors iterate this)
func to_ints() -> PackedInt32Array;  static func from_ints(pid: int, ints: PackedInt32Array) -> SimCommand    # null if malformed
```
```gdscript
class_name SimCommandCodec extends RefCounted
static func decode(c: SimCommand) -> int          # decodes c.raw into c's fields; Err.OK or BAD_FIELD / UNKNOWN_OP; normalises ids (sort, dedup); never throws
static func encode(c: SimCommand) -> PackedInt32Array     # [op, fields in layout order, ids]
```
```gdscript
class_name SimCommandSystem extends SimSystem      # stage 1; world.commands
func register_executor(op: int, c: Callable) -> void          # c: func(world: SimWorld, cmd: SimCommand) -> int   (SimCommand.Err.OK or a reason). One executor per op; a later registration replaces the earlier one (that is how a domain overrides a built-in)
func execute(world: SimWorld, c: SimCommand) -> int           # validation + dispatch (also used by tests)
```
Built-in executors: the order ops (`MOVE, FOLLOW, PATROL, LOAD, GARRISON, CAPTURE, REPAIR, SALVAGE, HARVEST, RETURN_CARGO, ATTACK, ATTACK_MOVE, GUARD, HOLD, FORCE_FIRE, RETURN_TO_BASE`) turn each actor into a `SimOrder` and call `world.orders.issue` — domains only register **order handlers** (§3.6); `STOP`, `SCATTER`, `SCUTTLE`, `RESIGN`, `DEBUG` are complete in the kernel. Every other op (`SET_STANCE`, abilities 100–105, economy 120–141) needs an executor from the owning domain; without one the op returns `Err.NOT_AVAILABLE`.

### 3.6 Orders
```gdscript
class_name SimOrder extends RefCounted           # fields §4.7
static func make(t: int, target: int = 0, px: int = 0, py: int = 0, a: int = 0, a2: int = 0, f: int = 0) -> SimOrder
```
```gdscript
class_name SimOrderHandler extends RefCounted          # stateless; ONE instance per order type
var requires_target: bool = false                       # if true and order.target_id != 0 no longer resolves to an alive entity -> on_target_lost() instead of on_update()
func can_issue(world: SimWorld, e: SimEntity, o: SimOrder) -> int   # SimCommand.Err.OK to accept (pure validation, no side effects)
func on_begin(world: SimWorld, e: SimEntity, o: SimOrder) -> int    # first time it becomes the head (phase 0 -> 1); returns RUNNING / DONE / FAILED
func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int   # every tick while head; RUNNING / DONE / FAILED. Before returning FAILED set o.fail = a SimCommand.Err
func on_end(world: SimWorld, e: SimEntity, o: SimOrder, reason: int) -> void   # exactly once for every order whose on_begin ran, when it leaves the queue: SimOrder.END_DONE / FAILED / CANCELLED (stop) / REPLACED / DIED (unit removed). Release reservations here
func on_target_lost(world: SimWorld, e: SimEntity, o: SimOrder) -> int          # default FAILED
func on_idle(world: SimWorld, e: SimEntity) -> void                             # only for handlers registered with register_idle
```
```gdscript
class_name SimOrderSystem extends SimSystem        # stage 5; world.orders
func register_handler(type: int, h: SimOrderHandler) -> void         # one per type; a duplicate is logged (Log.error) and ignored (first wins)
func replace_handler(type: int, h: SimOrderHandler) -> void          # deliberate override (tests)
func register_idle(h: SimOrderHandler) -> void                       # called (registration order) for units with an empty queue until one enqueues an order
func has_handler(type: int) -> bool
func issue(world: SimWorld, e: SimEntity, o: SimOrder, mode: int) -> int     # mode = SimOrder.QM_*; every system's order_gate, then handler.can_issue; QUEUE_FULL at MAX_ORDERS; REPLACE ends begun orders with END_REPLACED
func issue_internal(world: SimWorld, e: SimEntity, type: int, target_id: int = 0, x: int = 0, y: int = 0, mode: int = SimOrder.QM_REPLACE, arg: int = 0) -> int   # domain-created orders (auto-harvest, retaliation): same validation, flag OF_AUTO
func clear(world: SimWorld, e: SimEntity, reason: int = SimOrder.END_CANCELLED) -> void   # on_end(reason) for every begun order, empty the queue
```
Built-in handler: `T_WAIT` (`arg` = ticks). Stage 5 iterates **units only**; structures have no queue (structure behaviour is component-driven).

### 3.7 Events
```gdscript
class_name SimEventBuffer extends RefCounted             # world.events
var data: PackedInt32Array; var enabled: bool = true; var dropped: int
func emit(type: int, x: int = 0, y: int = 0, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> void   # appends [type, tick, x, y, a..f]
func emit_throttled(type: int, pid: int, gap: int, x: int = 0, y: int = 0, a: int = 0, … f: int = 0) -> void   # at most once per `gap` ticks per (type, pid); type < 512
func take() -> PackedInt32Array          # O(1): returns the accumulated records, buffer restarts empty
func count() -> int;  func clear() -> void;  func digest() -> int      # digest32 of the whole buffer (event-determinism tests)
```
`SimWorld.emit(type, x, y, a..f)` is a shortcut for `events.emit`. Positions are sub-cell units, `(0, 0)` when an event has no place. `enabled = false` for headless soak. Records are int32; checksums stored in events would wrap negative — the kernel stores none (net reads `checksum_at`).

### 3.8 Config, rules, command log
```gdscript
class_name SimMatchRules extends RefCounted
# lobby schema (net.md 7.1 `rules`):  start_credits 7500 · unit_cap 150 · superweapons 1 · fog 1 · shared_vision 0 · veterancy 0 · vision_stride 2 · vision_budget 128
# kernel / dev only (never sent by the lobby):  start_mode 0 · neutral_structures 1 · victory 1 · end_when_no_humans 1 · allow_debug 0
const START_HQ := 0; START_MCV := 1; START_NONE := 2
func to_dict() -> Dictionary;  static func from_dict(d: Dictionary) -> SimMatchRules;  func hash_into(buf: PackedInt32Array) -> void      # bools folded to 0/1; unknown keys ignored
class_name SimPlayerSlot extends RefCounted
const HUMAN := 0; AI := 1
var pid: int; kind: int; name: String; roster: String; team: int; color: int; start: int; handicap: int = 100; ai_level: int; ai_style: int; ai_flags: int
func to_dict() -> Dictionary; static func from_dict(d: Dictionary) -> SimPlayerSlot
class_name SimMatchConfig extends RefCounted            # the sim's reader of net's MatchConfig; ignores format, match_id, created_unix, versions, net
var seed_value: int; var map: Dictionary; var rules: SimMatchRules; var players: Array[SimPlayerSlot]     # sorted by pid
static func from_dict(d: Dictionary) -> SimMatchConfig;  func to_dict() -> Dictionary;  func max_pid() -> int
static func is_int_only(v: Variant) -> bool             # no floats anywhere (net normalises before the sim sees the dictionary)
func config_hash() -> int                               # §5.10
func validate(data: GameData, start_count: int) -> PackedStringArray     # [] = valid (rules in §5.10); start_count = map.spawns.size() / MapData.SPAWN_STRIDE (SimWorld.create computes it)
```
```gdscript
class_name SimCommandLog extends RefCounted             # tests/tools only; the replay FILE belongs to net (NetReplay)
var ticks: PackedInt32Array; var pids: PackedInt32Array; var cmds: Array[PackedInt32Array]; var checkpoints: PackedInt64Array
func record(tick: int, pid: int, ints: PackedInt32Array) -> void
func submit(world: SimWorld, pid: int, ints: PackedInt32Array) -> void      # records under world.tick AND submits
func finish(world: SimWorld) -> void                                         # copies world.checksum_log
func to_ints() -> PackedInt32Array;  static func from_ints(a: PackedInt32Array) -> SimCommandLog     # [n, (tick, pid, len, ints…)×n]
func play(world: SimWorld, n_ticks: int) -> Dictionary                       # {ok, mismatch_tick, final}; `world` must be freshly built from the same inputs
```

### 3.9 Test kit
```gdscript
class_name SimTestKit extends RefCounted                 # game/tests/support/sim_test_kit.gd (tests may reference src/, never the reverse -- lint L005)
const MCV := 0; RIFLE := 1; TANK := 2; DRONE := 3        # unit def indices of the fixture (per-kind index spaces)
const HQ := 0; BARRACKS := 1; DOCK := 2; GARRISON_S := 3; SMOKE := 0; DEPOSIT := 0; GARRISON := 1
static func make_data(fixture_path: String = "res://tests/fixtures/sim_core_fixture.json") -> GameData   # ASSUMPTION(data): GameData.for_test(fixture dict) builds the §7.1 fixture; data_hash pinned to 0x1234ABCD; the path is a parameter so nothing under src/ names res://tests (lint L005)
static func make_map(neutral_records := PackedInt32Array()) -> MapData   # ASSUMPTION(map): MapData.for_test(96, 96, 8 spawn cells, neutral records, map_hash 0x5678EF01) + the fixture's footprint table (set_footprint) and neutral kind -> def table (set_neutral_def)
static func make_config(players: int = 2, seed_value: int = 424242) -> SimMatchConfig
static func make_world(players: int = 2, seed_value: int = 424242, opts: Dictionary = {}) -> SimWorld   # adds TestCombatSystem unless opts.systems is given; wires TestMoveHandler for T_MOVE / T_PATROL
static func wire(w: SimWorld) -> SimWorld
static func produce(w: SimWorld, def_idx: int, pid: int, x: int, y: int, paid: int = 0) -> SimEntity   # spawn_unit as production would (reason PRODUCED)
static func s_core_1(w: SimWorld, steps: int = 200) -> PackedInt32Array      # the golden scenario of §10.3; returns [tick, checksum, …] per checkpoint
static func random_step(w: SimWorld, tr: SimRng) -> void; static func run_random(seed_value: int, players: int, steps: int, check_every: int, victory_off: bool = true) -> PackedInt64Array   # chaos fuzz
static func check_hash_coverage(cls: GDScript, exempt: PackedStringArray) -> PackedStringArray   # DR-13 reflection guard (problems; [] = OK)
static func diff_dumps(a: String, b: String, max_lines: int = 20) -> PackedStringArray;  static func double_run(steps: int = 200) -> bool
static func fold_ints(v: Variant) -> Variant              # test stand-in for net's NetMatchConfig.normalize (JSON floats -> ints)
```
`TestMoveHandler` (speed 300: per tick `if dist² ≤ 300²` snap to target and finish, else `facing = atan2(dy,dx)`, `set_pos(e, x + step_x, y + step_y)`) and `TestCombatSystem` (stage 8; `on_dying` leaves a wreck for tank kills by an enemy's damage; records `dying_log`; `order_gate` vetoes orders for `F_DEPLOYING` units) are test-only stand-ins for the movement and combat domains. `SimInvariants.check(world) -> PackedStringArray` is the structural checker (list in §10.2).

### 3.10 Call and tick order (normative)
```
construction:   SimWorld.new → players → SimPipeline.create → init_world (stage 1..11) → initial spawns (on_spawn hooks) → flush → checkpoint(tick 0)
per step():     [ended? drop pending, return] ; events.set_tick(tick) ; reset last tick's movers (prev = pos, v = 0)
                stage 1  SimCommandSystem  (sort → decode → validate → execute)         → _flush_spawns()
                stage 2..11 (skipping stride-gated stages) each followed by _flush_spawns()
                tick++ ; [invariants_every] ; if tick % 20 == 0: checkpoint (16 parts + entity digests + checksum_log)
net frame:      for each turn: submit_raw(pid, ints) per command in (pid, issue) order ; step() ; step()
app frame:      steps as demanded by net ; then  batch = world.events.take() ; view/audio/ui/ai consume batch   (view: interpolate e.prev_x → e.x)
```
Events of tick *t* carry `tick = t` (the tick being simulated). A frame that runs *k* steps yields one batch with non-decreasing `tick`.

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enumerations (integer values are part of the contract: hashed, serialised or used as array indices)

| Enum | Values |
|---|---|
| `SimEntity.Kind` | `UNIT=0, STRUCTURE=1, WRECK=2, ZONE=3, NEUTRAL=4` (5 = reserved, **never** used: projectiles are not entities). `def_idx` indexes `data.units` (UNIT, WRECK = the dead unit's def), `data.structures` (STRUCTURE), `data.zones` (ZONE), `data.neutrals` (NEUTRAL); `SimDefs.DEF_KIND` maps to data's `DefEnums.Kind` (0, 1, 0, 7, 8) |
| `SimEntity.Layer` | `GROUND=0, AIR=1, SURFACE=2` (surface water), `UNDERWATER=3` (= data `Layer`, combat `LAYER_*`) |
| `SimPlayer.Controller` | `HUMAN=0, AI=1, NONE=2` (vacant pid) |
| `SimPlayer.Elim` | `NONE=0, NO_ASSETS=1, RESIGN=2, DISCONNECT=3, KICKED=4, TIMEOUT=5, DESYNC=6, SCRIPT=7` — a `RESIGN` command with `mode m ∈ 0..4` (net `ResignReason`: surrender, disconnect, kicked, timeout, +4 desync drop) gives `2 + m` |
| `SimWorld.Rel` | `SELF=0, ALLY=1, ENEMY=2, NEUTRAL=3` |
| `SimWorld.EndReason` | `ELIMINATION=0, NO_HUMANS=1, DRAW=2` |
| `SimWorld.Cause` | `DAMAGE=0, SCUTTLE=1, EXPIRE=2, ORPHAN=3` (tethered parent lost) `, CARGO=4` (container died) `, RESIGN=5` (owner eliminated) `, SCRIPT=6` |
| `SimPlayerSlot` kind | `HUMAN=0, AI=1` |
| `SimMatchRules` start mode | `START_HQ=0` (deployed HQ), `START_MCV=1`, `START_NONE=2` |
| `SimOrder` status | `RUNNING=0, DONE=1, FAILED=2` |
| `SimOrder` queue mode | `QM_REPLACE=0, QM_APPEND=1, QM_FRONT=2` |
| `SimOrder` flags | `OF_FORCED=1, OF_CYCLIC=2, OF_AUTO=4, OF_NO_FORMATION=8, OF_SPEED_MATCH=16, OF_REVERSE_OK=32` |
| `SimOrder` end reason | `END_DONE=0, END_FAILED=1, END_CANCELLED=2, END_REPLACED=3, END_DIED=4` |
| `SimCommand.Err` | `OK=0, UNKNOWN_OP=1, BAD_PLAYER=2, ELIMINATED=3, MATCH_ENDED=4, BAD_FIELD=5, NO_ACTORS=6, NO_TARGET=7, WRONG_KIND=8, NOT_AVAILABLE=9, NO_PREREQ=10, NO_CREDITS=11, QUEUE_FULL=12, BAD_SITE=13, NO_VISION=14, NOT_READY=15, UNIT_CAP=16, BLOCKED=17, DISABLED=18, NOT_ALLOWED=19, BAD_ORDER=20, INSIDE=21` (domain-specific reasons such as economy's `RSN_*` travel in `cmd.detail`) |
| Cash reasons (`SimEvent`) | `CASH_START=0, HARVEST=1, SALVAGE=2, REFUND=3, SELL=4, SPEND=5, SCRIPT=6` |
| Spawn reasons (`SPAWNED.f`) | `SPAWN_INITIAL=0, PRODUCED=1, PLACED=2, DEPLOYED=3, SUMMONED=4, WRECK=5, SCRIPT=6` |
| Remove reasons (`REMOVED.e`) | `REM_KILLED=0, SOLD=1, EXPIRED=2, DEPLOYED=3, CONSUMED=4, SCRIPT=5` |

### 4.2 `SimEntity` — exact field list
`hash` column: **H** = appended to the entity stream in this order (§8.2); **d** = derived/private, deliberately excluded (declared in `SimEntity.HASH_EXEMPT`).

| # | Field | Type | Default | Written by | Meaning | hash |
|---|---|---|---|---|---|---|
| 1 | `id` | int | 0 | core (spawn) | unique, ≥ 1, monotonic, **never reused** | H |
| 2 | `kind` | int | 0 | core | `Kind` | H |
| 3 | `def_idx` | int | −1 | core | index into the def table selected by `kind` (§4.1) | H |
| 4 | `owner` | int | −1 | core (spawn, `change_owner`) | pid 0–7 or −1 neutral | H |
| 5 | `parent` | int | 0 | core (spawn arg) | creator id: summoner, carrier of a drone, … (0 none; **not** set on wrecks) | H |
| 6 | `container_id` | int | −1 | `set_inside` | container id while `F_INSIDE`, else −1 | H |
| 7,8 | `x`,`y` | int | 0 | `set_pos` (movement) | sub-cell units (1024 = 1 cell), entity centre; structures: footprint centre | H |
| 9,10 | `prev_x`,`prev_y` | int | = x,y | `set_pos` / spawn | position at the **start** of the current (or last moved) tick | H |
| 11,12 | `vx`,`vy` | int | 0 | `set_pos` | displacement during the current (or last completed moved) tick | H |
| 13 | `facing` | int | 0 | movement/combat | 0..4095 (0 = +x, increasing toward +y) | H |
| 14 | `layer` | int | `home_layer` | `set_layer` | `Layer` | H |
| 15 | `hp` | int | `hp_max` | **combat** (damage, heal, `set_hp_max`), spawn | current hit points; `F_DEAD ⇒ hp == 0`, otherwise `1 ≤ hp ≤ hp_max` when `hp_max > 0` (`hp_max == 0` = indestructible zone/deposit) | H |
| 16 | `hp_max` | int | `defs.hp_max(view)` | spawn, `set_hp_max`, `change_owner` | maximum hit points of the owner's resolved def | H |
| 17 | `paid_cost` | int | 0 | spawner (production) | credits **actually paid** (post-modifier). Basis for sell refund, Engineer repair cost, AE salvage. Wreck: the dead unit's value | H |
| 18 | `flags` | int (64-bit) | `flags_init` | shared (§4.3) | bit set, hashed as two words | H |
| 19 | `born` | int | tick | core | `world.tick` at spawn | H |
| 20 | `expire_tick` | int | 0 | spawner/domain, `remove_deferred`; **cleared by `kill()`** | absolute tick at which cleanup removes it; 0 = never. Domains may extend it (wreck being salvaged) | H |
| 21 | `orders` | `Array[SimOrder]` | `[]` | order system | queue, head = current. **Units only** | H (size + each order, §4.7) |
| 22 | `move, combat, air, carrier, econ, prod, abil, stats, vis, cargo, summon` | component refs | null | owning domain | typed nullable slots (§4.5) | H (11-bit mask + each present comp in this order) |
| – | `team` | int | −1 | core | cache of `world.team_of(owner)` | d |
| – | `radius` | int | `defs.radius` | core | collision / selection radius (units); wreck: the dead unit's | d |
| – | `_cap`, `_asset`, `_counted` | int/bool | 0/false | core | cap weight counted for the owner; counts toward struct/rebuilder counters; currently counted | d |
| – | `_pos_tick`, `_listed`, `_gone` | int/bool | −1/false | core | mover stamp; list membership; finalised | d |

Kind-specific conventions (no extra fields):

| Kind | `owner` | `def_idx` table | `hp/hp_max` | other |
|---|---|---|---|---|
| UNIT | pid (neutral allowed for scripted units) | `units` | resolved unit health | may have orders; counts toward the cap by `pop` unless `F_NO_UNIT_CAP` |
| STRUCTURE | pid or −1 (−1 = a neutral building: the map's `neutrals` records are STRUCTURE defs, Q-7) | `structures` | resolved structure health | position = footprint **centre**; created only when construction is **complete and placed** (queues live in `SimPlayerEcon`/`SimCompProd`); occupies its footprint in the map at spawn (`MapData.occupy`), vacates it at removal; `facing` = 1024 × orientation for rotatable footprints |
| WRECK | **original owner** (needed for the "enemy of the salvager" test) | `units` (the dead unit's def) | chosen by the creator (`spawn_wreck(hp)`) | `paid_cost` = dead unit's; `expire_tick` = tick + wreck life; flags `F_TEMPORARY \| F_UNTARGETABLE \| F_NO_SELECT \| F_NO_UNIT_CAP` (+`F_NO_SALVAGE` if ineligible). Combat owns the wreck's salvage state in `SimCompCombat` |
| ZONE | creator pid | `zones` | `DefZone.hp` (0 = indestructible) | `expire_tick` = lifetime; geometry in the zone system's records (abilities keep zone *records*; the kind exists for entity-backed zones such as pucks) |
| NEUTRAL | −1 (or a capturer) | `neutrals` | `DefNeutral.health` | data's `DefNeutral` objects that are not structures (props, markers); occupies only if the map registers a footprint for the def (`map.footprint_of(NEUTRAL, idx)`); the map's own neutral buildings are STRUCTURE entities, and resource deposits are **map cells**, not entities (Q-7) |

### 4.3 `flags` bit allocation (shared by ALL domains — a bit is **written only by its owner**, read by anyone)
`flags` is a GDScript `int` (64 bit); the entity stream hashes `flags & 0xFFFFFFFF` and `flags >> 32` as two words.

| Bit | Constant | Writer | Meaning |
|---|---|---|---|
| 0 | `F_DEAD` | core (`kill`) | hp reached 0; awaiting cleanup (or lingering). Systems skip such entities |
| 1 | `F_REMOVING` | core | removal queued (`F_GONE = F_DEAD\|F_REMOVING`) |
| 2 | `F_INSIDE` | `set_inside` | inside a container: not on the map, not in the spatial hash, no orders/targeting |
| 3 | `F_TEMPORARY` | spawner | has a lifetime (`expire_tick`) — never counts toward struct/rebuilder counters |
| 4 | `F_SUMMONED` | spawner (ability/power/superweapon) | created by a power/ability: no salvage, no refund |
| 5 | `F_NO_UNIT_CAP` | core (spawn only) | excluded from the unit cap (= combat/abilities `F_NO_UNIT_CAP`, abilities `SM_NO_UNIT_CAP`) |
| 6 | `F_DECOY` | ability/economy | harmless decoy (detectors identify it); no wreck income; never counts as an asset |
| 7 | `F_NO_COLLISION` | movement/ability | never blocks movement (= data `UF_NON_BLOCKING`) |
| 8 | `F_INVULNERABLE` | data/ability | takes no damage |
| 9 | `F_UNTARGETABLE` | data | never auto-acquired (force-fire policy is combat's) |
| 10 | `F_NO_SELECT` | data | not selectable by players |
| 11 | `F_TETHERED` | spawner | dies (`Cause.ORPHAN`) when `parent` is removed |
| 12 | `F_HAS_CHILDREN` | core | some entity names this one as `parent` (cleanup fast path) |
| 13 | `F_NO_SALVAGE` | core / data | wreck is not salvageable (friendly fire, scuttle, summon, decoy); data `UF_NO_SALVAGE` |
| 14 | `F_INITIAL` | core | placed by the map / start state |
| 15 | `F_EXPIRE_KILLS` | spawner | on expiry die (`Cause.EXPIRE`, with `on_dying`) instead of silent removal |
| 16–19 | `F_MOVING, F_AIRBORNE, F_BLOCKED, F_ON_WATER` | movement | movement state mirrors |
| 20–22 | `F_FIRING, F_ENGAGED, F_WEAPONS_OFF` | combat | fired this tick; in combat window; weapons unavailable (23 reserved) |
| 24–27 | `F_DEPLOYED, F_DEPLOYING, F_CLOAKED, F_ABILITY_ACTIVE` | ability | deployed/transitioning/camouflaged/active ability |
| 28–30 | `F_POWERED, F_REPAIR_ON, F_SELLING` | power / economy / production | structure has power; auto-repair on; being sold (31 reserved) |
| 32 | `F_NO_CAPTURE` | data / spawner | capture-immune (`UF_NO_CAPTURE`) |
| 33 | `F_NO_REPAIR` | data / spawner | cannot be repaired (`UF_NO_REPAIR`) |
| 34 | `F_NO_VISION_GRANT` | spawner | never reveals fog for its owner (decoys, summons) |
| 35 | `F_NO_FOOTPRINT` | spawner | structure-like entity that does not occupy a map footprint (False Front, temporary decoys). Set **at spawn** through the `flags` argument |
| 36 | `F_SCRIPTED_MOVE` | spawner | `SimMovementSystem` skips it (moved by its own driver) |
| 37–40 | `F_EMP_SHUT, F_SUPPRESSED, F_GARRISONED, F_UNDER_CONSTRUCTION` | combat / combat / cargo / economy | state mirrors for view, AI and audio |

Bits 41–47 are free (amendment required), 48–63 reserved. New bits require an amendment to this table.

### 4.4 Time-stamp convention
All timers are **absolute ticks**; `active(t) := world.tick < t`; to clear assign `0`; to apply `t = maxi(t, world.tick + duration)` unless the effect text says it cannot be refreshed. "N seconds without dealing or taking damage" rules use the domain's `last_fire_tick` / `last_hit_tick`. The kernel has **no** status timers on `SimEntity`: EMP, suppression, disabled/shutdown and last-hit/last-fire live in `SimCompCombat` (combat is their owner; abilities read them there), camouflage state in `SimCompAbility`/`SimCompStats`. `SimConfig.NEVER` (−1 000 000) is the "long ago" value for such timestamps.

### 4.5 Component slot policy
1. `SimEntity` has **exactly eleven** typed, nullable slots: `move, combat, air, carrier, econ, prod, abil, stats, vis, cargo, summon` (classes `SimComp*`, §2.3). `SimPlayer` has three: `econ, fx, vis` (`SimPlayerEcon/Fx/Vision`). **One class per slot; the owning domain defines its fields and may nest sub-objects.** Anything a *second* domain must read goes through a documented accessor on the component or a field on `SimEntity`/`SimPlayer`/`flags`.
2. Files are created as empty stubs (`extends SimComponent`, no fields) by task SC-04 so every module parses from day 1; the owner overwrites the file (keeps `class_name`).
3. **Creation.** Only the owner's `on_spawn` creates its component, decided from the def (`if def.has_weapons: e.combat = SimCompCombat.new()`). Components are never swapped for a different class; they may be freed by setting the slot to `null` only in the owner's `on_remove` / `on_dying`.
4. **Contents.** Ints and packed int arrays only (no `Dictionary`, `Node`, `float`, object refs; reference other entities by **id**; 64-bit values as two ints). No back-reference to the entity or world.
5. **`hash_into(buf)` is mandatory and complete**: append every authoritative field in a fixed order; derived caches are listed in a `const HASH_EXEMPT: PackedStringArray`. A test per component calls `SimTestKit.check_hash_coverage(SimCompX, SimCompX.HASH_EXEMPT)` (reflection: mutates each script variable and asserts the digest changes).
6. **Adding a field** (DR-13): add the `var` → append it at the **end** of `hash_into` → extend the domain's test → if behaviour changes, bump `SimConfig.SIM_VERSION` → regenerate `game/tests/golden/sim_core.json` in the same change.
7. **Cross-domain reads** of another domain's component are allowed only through null-checked typed access (`if e.combat != null`), never in `on_spawn`.
8. Mapping of the slot names the domain specs used: economy `comp_econ → econ`, `comp_prod → prod`; `comp_temp` disappears (`expire_tick` + `F_TEMPORARY` are kernel fields); `comp_wreck` disappears (wreck/salvage state is combat's `SimCompCombat` block; salvage claims are channel state, §6.4); combat's `SimCompCombat/Air/Carrier` and abilities' `SimCompAbility/Stats/Vision/Cargo/Summon` keep their names.

### 4.6 `SimPlayer` — exact field list

| Field | Type | Default | Written by | Meaning |
|---|---|---|---|---|
| `pid` `team` `roster_idx` `faction_idx` `color` `controller` `ai_level` `ai_style` `ai_flags` `handicap` | int | – | constructor | identity/config; `team` = the config's final team id (1..4 or 8+pid; up to 15); `handicap` percent 50..200 |
| `name` | String | "" | constructor | label only — **never hashed** |
| `roster` | `DefRoster` | – | constructor | data reference (immutable) — not hashed |
| `view` | `DefPlayerView` | – | constructor; production calls `view.apply_research(idx)` | data's per-player facade (resolved stats, owns `DefLayer3`); **`view.checksum()` is hashed** |
| `eliminated` `elim_tick` `elim_reason` | int | 0 | `eliminate()` | lifecycle; vacant pids start `eliminated = 1` |
| `credits` | int | `start_credits × handicap / 100` | `add_credits/try_spend` only | spendable credits |
| `income_frac` | int | 0 | `add_credits` | handicap remainder carry (0..99) |
| `power_supply` `power_demand` | int | 0 | power system | mirrored capacity budget for HUD / AI reads (`bible rule.design.power_loss`); the detailed grid state is economy's |
| `unit_count` `struct_count` `rebuilders` | int | 0 | core | cap weight of live capped units; live non-temporary structures; live non-temporary MCV-class units — **the elimination source of truth** |
| `st_units_built` `st_units_lost` `st_units_killed` `st_structs_built` `st_structs_lost` `st_structs_killed` | int | 0 | core | end-screen counters (built counted at spawn unless `SPAWN_INITIAL` / `SPAWN_WRECK`) |
| `st_credits_earned` `st_credits_spent` | int | 0 | `add_credits` | see §3.4.7 (`st_credits_earned` = AI's `credits_earned_total`) |
| `st_damage_dealt` `st_damage_taken` | int | 0 | combat | hit points applied |
| `st_cmds` `st_rejected` `st_peak_units` | int | 0 | core | accepted commands; rejected commands (AI's `rejected_command_count`); max `unit_count` |
| `econ` `fx` `vis` | component refs | null | owning domain | player-level extension slots (§4.5) |

Tech prerequisites (owned counts per def), powered counts, research-done flags, support-power / superweapon state and the production/research queues are **not** kernel fields: they live in `SimPlayerEcon` (economy) with hashes in the `economy` part. `alive` is `eliminated == 0` (`world.is_player_active(pid)`).

### 4.7 `SimOrder`

| Field | Meaning |
|---|---|
| `type` | order type (table below) |
| `target_id` | entity id (0 = none) |
| `x`,`y` | destination / target point (sub-cell units) |
| `arg`,`arg2` | type-specific (combat's `count` = `arg`) |
| `flags` | `OF_*` |
| `phase` | 0 = `PH_NEW` (not begun); ≥ 1 handler-defined (combat's `state`). The dispatcher sets 1 before `on_begin()` |
| `t0`,`p0`,`p1` | handler scratch (tick started, path cursor, retry counter…; combat's `tx,ty`); all hashed |
| `fail` | a `SimCommand.Err` the handler sets before returning FAILED; copied into `ORDER_FAILED.c`; **not hashed** (the order is dropped at once) |

| Code | `T_*` | Args | Handler owner |
|---|---|---|---|
| 0 / 1 | `NONE` (invalid) / `WAIT` | `arg` = ticks | core |
| 16 | `MOVE` | x,y; `OF_NO_FORMATION`, `OF_SPEED_MATCH`, `OF_REVERSE_OK` | movement |
| 17 | `PATROL` | x,y; always `OF_CYCLIC` (re-appended on DONE); the same movement flags as `MOVE` | movement |
| 18,19,20 | `FOLLOW`, `FACE`, `LAND` | target (`FOLLOW` is issued by command 12) / `arg` = angle / x,y or pad | movement |
| 30 | `HARVEST` | target 0 + x,y = a deposit cell (map model; a positive target = a DEPOSIT entity only if Q-7 keeps that model) | economy |
| 31 | `RETURN_CARGO` | target refinery (0 = nearest) | economy |
| 32 / 33 / 34 | `CAPTURE` / `REPAIR` / `SALVAGE` | target | economy (service units) |
| 35 | `DEPLOY_MCV` | optional cell (x,y) | economy |
| 40 | `ATTACK` | target; `OF_FORCED` = attack own/allied/neutral | combat |
| 41 | `ATTACK_MOVE` | x,y | combat |
| 42 | `GUARD` | target (guard that unit) or x,y (guard that spot) | combat |
| 43 | `HOLD` | – (hold position) | combat |
| 44 | `FORCE_FIRE` | target or x,y (ground); `arg` = count | combat |
| 45 | `RETURN_BASE` | – (aircraft: land at a pad / rearm) | combat / movement |
| 50 / 51 / 52 | `LOAD` / `UNLOAD` / `GARRISON` | target transport / x,y + `arg` flags / target building | abilities (transports) |
| 53 / 54 | `DEPLOY` / `UNDEPLOY` | `arg` = ability slot | abilities |
| 55 / 56 | `USE_ABILITY` / `SET_MODE` | `arg` slot, `arg2` op or mode, target, x,y | abilities |

Ranges: 0–15 core · 16–29 movement · 30–39 economy · 40–49 combat · 50–63 transport/abilities (= the numbers economy and combat asked for); `TYPE_COUNT = 64`; extending needs an amendment.

### 4.8 Command wire contract (net's view: `PackedInt32Array`)
A command is `[op, f_0 … f_(k−1), id_0 … id_(n−1)]`, all int32: `op ∈ 0..255`, `1 ≤ size ≤ 1024` (net XR-2), **no pid, sequence number or timestamp inside** — the pid is stamped by net from the connection and passed to `submit_raw`; the order of execution inside a turn is ascending pid, then the issue order (`_ord`). `k` and the meaning of each field come from the op's row in the catalog (§6.1); a field slot is one of `target, x, y, def, count, mode, flags, angle` (`FT_*`). The id list exists only for ops flagged `M_IDS` (`n ≤ 512`); the decoder sorts and de-duplicates it and rejects ids ≤ 0. Any deviation (unknown op, fewer than `k` fields, trailing ints on an id-less op, too many ids, size out of range) is `Err.BAD_FIELD` / `UNKNOWN_OP`, counted in `st_rejected`, never an engine error.

**Golden vectors** (`SimCmd` builders → ints; verified on both platforms):

| Builder call | Ints |
|---|---|
| `move(ids={40,12,16,15}, x=5000, y=7168)` (ids canonicalised) | `[1, 5000, 7168, 0, 0, 12, 15, 16, 40]` |
| `attack(ids={301,305}, target=777, mode=1)` | `[40, 777, 1, 0, 301, 305]` |
| `train(producer=55, unit_def=17, count=3)` | `[124, 55, 17, 3]` |
| `build_place(struct_def=9, cx=12, cy=20, rot=0)` | `[123, 9, 12, 20, 0]` |
| `use_power(power_def=1, x=90000, y=131072, angle=1024)` | `[140, 1, 90000, 131072, 1024, 0]` (decodes fine; rejected `BAD_FIELD` on a 96-cell map: y out of range) |
| `resign(reason=0)` | `[250, 0]` |

Costs (M5 Max): `SimCmd.move` 0.5 µs · `decode` 2.8 µs · one `orders.issue` (with the 11-stage gate) 2.6 µs · a 3-actor MOVE command end to end ≈ 26 µs.

### 4.9 Event record
`[type, tick, x, y, a, b, c, d, e, f]` — 10 × int32; `x,y` sub-cell position or `(0,0)`. Layouts per type in §6.2 (core) and in each domain's spec (its block).

### 4.10 Spatial-hash tag (one-hot fields so `need`/`avoid` express set logic)

| Bits | Field | Value |
|---|---|---|
| 0–4 | kind | `1 << kind` (`ALL_KINDS = 31`) |
| 5 | `ALIVE` | set unless `F_GONE` |
| 6–9 | layer | `1 << (6 + layer)` |
| 10–18 | owner slot | `1 << (10 + slot_of(owner))`; neutral = bit 18 (`NEUTRAL_OWNER`) |

Builders: `SimTag.of(e)`, `kind_bit(k)`, `layer_bit(l)`, `owner_bit(o)`; masks `ALL_KINDS`, `ALL_LAYERS`, `ALL_OWNERS`, `NEUTRAL_OWNER`. There are **no team bits**: teams are arbitrary ids up to 15, so the world precomputes per-owner ally masks and `world.non_enemy_mask(pid)` (own + allied owner bits + neutral) is the `avoid` mask of "enemies only". The world refreshes tags on kill / removal / `change_owner` / `set_layer`.
*Example:* alive enemy ground units of player 0: `need = ALIVE | kind_bit(UNIT) | layer_bit(GROUND)`, `avoid = world.non_enemy_mask(0)`.

### 4.11 `SimMatchRules` / `SimPlayerSlot` / `SimMatchConfig`
* **Rules** (all int, defaults; the first eight are net's `rules_schema` keys, ranges as validated by net): `start_credits 7500` (0..100000) · `unit_cap 150` (20..500) · `superweapons 1` · `fog 1` · `shared_vision 0` · `veterancy 0` (bible: off) · `vision_stride 2` (1..4) · `vision_budget 128` (16..512) — the last two are performance knobs that must be identical on all peers. Kernel/dev only: `start_mode 0` · `neutral_structures 1` · `victory 1` (0 = sandbox: no elimination-by-assets, no match end) · `end_when_no_humans 1` · `allow_debug 0`. **Not sim rules:** game speed (`net.speed_pct`), pause policy, input delay, disconnect policy — net owns them and keeps them out of `rules` so the sim cannot read them by accident.
* **Slot** (`players[]` entry): `pid` 0..7, `kind` (human / ai), `name` (label), `roster` (String id, e.g. `roster.napc.canada`), `team` (final id 1..4 or 8+pid), `color` 0..11 (view only), `start` (spawn **slot** index = record `start` of `map.spawns`, unique per player; the lobby picks slots, `map.fair_slot_order(n)` gives the fair ones), `handicap` 50..200, `ai_level/ai_style/ai_flags` (`ai = {level, style, flags}`; `flags` bit0 = fog cheat, read by the AI runner, not the sim). Pids need not be contiguous: missing pids become vacant players.
* **Config**: `seed` (u32), `map` (opaque Dictionary interpreted by the map domain: family/size/seed/layout_players/params — **ints, strings, arrays only**), `rules`, `players`. `from_dict` accepts exactly net.md §7.1 and ignores `format, match_id, created_unix, versions, net`.

### 4.12 Ids and counters
* `id`: `next_id` starts at 1, +1 per entity ever spawned (all kinds). Never reused, so a stale id can never alias a new entity (this is why commands/orders/events may safely carry ids). `by_id` grows by doubling (16 B per slot; ~3 MB at 200 k ids).
* `proj_id`: `next_proj_id` (separate counter) for combat's pooled projectiles; appears only in events and combat state.
* **Decisions:** PROJECTILE is not an entity kind (1,000+ short-lived objects would bloat the id space, the hash and every "for e in entities" loop; combat owns a pooled SoA store). Wrecks/summons/decoys/drones are ordinary entities distinguished by flags + `expire_tick` + `parent`. Neutral buildings are STRUCTURE entities with owner −1 (the map's `neutrals` records, resolved by `map.neutral_def_for_kind`); resource deposits are **map cells** in `MapData` (`deposit`, `harvest`, hashed by `checksum_dynamic()`), not entities; `Kind.NEUTRAL` stays available for `DefNeutral` objects (§12 Q-7).

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 `Fp` — semantics, rounding and algorithms

**Integer semantics of the engine `[verified on macOS arm64 and Linux x86_64]`** (the reason `Fp` exists):

| Expression | Result | Consequence |
|---|---|---|
| `-7 / 2`, `7 / -2` | −3, −3 | `/` truncates toward zero |
| `-7 % 3`, `7 % -3` | −1, 1 | `%` keeps the dividend's sign |
| `posmod(-7,3)`, `posmod(7,-3)` | 2, −2 | floor-style modulus exists as a builtin |
| `Fp.floor_div(-7,2)`, `floor_mod(-7,3)`, `ceil_div(-7,2)` | −4, 2, −3 | use these when flooring is meant |
| `(-1025) >> 10` (typed vars) | −2 | runtime `>>` is an **arithmetic** shift; *constant* negative shift operands are a **parse error** ("Only positive operands are supported"). Never write a negative literal next to `>>`/`<<`; `Fp.self_test()` asserts the runtime behaviour at boot |
| `1 << 63`, `1 << 64` | INT64_MIN, 1 | shift count is taken mod 64; never shift by ≥ 63 |
| `0xFFFFFFFF * 0xFFFFFFFF` | wraps | never rely on overflow; keep magnitudes < 2^62; 32-bit products use `SimRng.mul32` |

**`mul_div(a,b,c,mode)`** — `n = a*b` (|n| < 2^62), sign-normalise so `c > 0`, `q = n / c` (truncated), `r = n - q*c` (sign of `n`, `|r| < c`):

| mode | result |
|---|---|
| `TRUNC` | `q` |
| `FLOOR` | `q - 1` if `r < 0` else `q` |
| `CEIL` | `q + 1` if `r > 0` else `q` |
| `HALF_UP` (round half toward +∞; default) | if `r < 0`: `q -= 1; r += c`; then `q + 1` if `2r ≥ c` else `q` |
| `HALF_AWAY` (round half away from zero) | if `r ≥ 0`: `q + (2r ≥ c)`; else `q - (−2r ≥ c)` |

Verified table (`a*b/c` → trunc, floor, ceil, half_up, half_away): `7/2 → 3,3,4,4,4` · `−7/2 → −3,−4,−3,−3,−4` · `5/2 → 2,2,3,3,3` · `−5/2 → −2,−3,−2,−2,−3` · `10/3 → 3,3,4,3,3` · `−10/3 → −3,−4,−3,−3,−3` · `11/3 → 3,3,4,4,4` · `−11/3 → −3,−4,−3,−4,−4`. Cross-checked (together with `floor_div/floor_mod/ceil_div/pct`) against a Python `Fraction` oracle on 60,000 random triples × 5 modes (digest `1403213809`, identical on both platforms).

**`isqrt(n)`** (exact, `n` clamped to `[0, 2^62−1]`):
```gdscript
var r: int = int(sqrt(float(n)))  # lint-allow: L003 float seed only; the two integer loops below make the result exact
while r * r > n: r -= 1
while (r + 1) * (r + 1) <= n: r += 1
return r                                    # unique r with r² ≤ n < (r+1)²  -> independent of any float behaviour
```
`(r+1)² ≤ 2^62` cannot overflow. This is the **only** float use in `core/` besides `milli()` (both carry a `# lint-allow: L003 <reason>` comment for the repo lint). Verified against `math.isqrt` (digest `853641712`), incl. `isqrt(2^62−1) = 2147483647`. Domain contract: **do not pass n ≥ 2^62** (an earlier prototype without the clamp looped forever on `n ≈ 2^63`). `dist(dx,dy)` = `isqrt(dx*dx+dy*dy)` (floor); prefer `dist2` comparisons: `dist2(dx,dy) <= r*r`.

**Angles.** `Fp.TURN = 4096` per turn, 0 = +x (east), increasing toward +y (south = 1024, west = 2048, north = 3072). `angle_diff(a,b) = ((b - a + 2048) & 4095) - 2048` ∈ [−2048, 2047] (e.g. `angle_diff(10, 4090) = −16`). `turn_toward(cur, tgt, m)` rotates by at most `m` (e.g. `turn_toward(0, 4000, 30) = 4066`, `turn_toward(4090, 20, 30) = 20`).

**Tables.** `SIN_Q16[a] = round_half_up(sin(a·2π/4096)·65536)` for `a = 0..4095`; `cos(a) = SIN_Q16[(a+1024) & 4095]`; `ATAN_Q8[i] = round_half_up(atan(i/1024)·(4096/2π)·256)` for `i = 0..1024` (`ATAN_Q8[1024] = 131072` = 45°·256).
Generation (`tools/py/gen_fp_tables.py`, run **once by a human/agent, output committed**): Python `decimal`, `prec = 60`, π hard-coded to 60 digits, `sin` by Taylor series to 10⁻⁵⁵, `atan` by 6 argument halvings + Taylor; compute the first quadrant `0..1024` and mirror: `S[2048−a] = S[a]`, `S[2048+a] = −S[a]`, `S[4096−a] = −S[a]`, `S[1024] = 65536`. The tool **fails** unless: symmetries hold, `max |S[a] − libm_sin·65536| < 0.5`, `max |A[i] − libm_atan·k| < 0.5`, `A[0]=0`, `A[1024]=131072`, and it prints the two digests that must equal `Fp.TABLE_DIGEST_SIN = 2046802713`, `Fp.TABLE_DIGEST_ATAN = 1306073121` (`Checksum.digest32` of the arrays). Emitted file: `const SIN_Q16: PackedInt32Array = [ … ]` and `const ATAN_Q8: PackedInt32Array = [ … ]` (16 numbers per line) — an array literal assigned to a typed `const` packed array is legal `[verified]` while `PackedInt32Array([...])` in a `const` is **not** ("isn't a constant expression"), and direct const access costs ≈17 ns. Samples: `SIN_Q16[1]=101, [2]=201, [256]=25080, [512]=46341, [1024]=65536, [3072]=−65536, [4095]=−101`; `ATAN_Q8[1]=163, [256]=40884, [512]=77376, [1023]=130990`.

**`atan2(dy,dx)`** (octant reduction + linear interpolation, verified):
```gdscript
static func _atan_ratio(mn: int, mx: int) -> int:        # 0 <= mn <= mx, mx > 0 -> 0..512 (45° = 512 units)
    var t: int = (mn << 16) / mx                          # Q16 ratio, 0..65536
    if t >= 65536: return 512
    var i: int = t >> 6; var f: int = t & 63              # 1024 segments, 6 fractional bits
    var a0: int = FpTables.ATAN_Q8[i]
    return (a0 + (((FpTables.ATAN_Q8[i + 1] - a0) * f) >> 6) + 128) >> 8
static func atan2(dy: int, dx: int) -> int:
    if dx == 0 and dy == 0: return 0
    var ax := absi(dx); var ay := absi(dy)
    var a: int = _atan_ratio(ay, ax) if ay <= ax else 1024 - _atan_ratio(ax, ay)   # angle within the first quadrant
    if dx >= 0: return a if dy >= 0 else (4096 - a) & 4095
    return (2048 - a) if dy >= 0 else (2048 + a)
```
Examples: `atan2(0,1)=0`, `atan2(1,0)=1024`, `atan2(0,−1)=2048`, `atan2(−1,0)=3072`, `atan2(1,1)=512`, `atan2(−1,1)=3584`, `atan2(1,−1)=1536`, `atan2(−1,−1)=2560`, `atan2(1000,1)=1023`. Accuracy over 20,000 random vectors (|dx|,|dy| < 2^18): max error vs exact = **0.508 units**, 99.73 % equal to the correctly rounded value, the rest off by one. An independent Python implementation of exactly this algorithm reproduces the GDScript digest `3886527727` for 50,000 vectors of `atan2/rot_x/rot_y`.

**Worked movement example** (used by S-CORE-1): from (21504, 22528) to (30720, 30720): `dx=9216, dy=8192`; `dist = 12330`; `atan2 = 474`; `sin(474)=43562`, `cos(474)=48962`; at speed 300 units/tick `step_x = mul_q16(300, 48962) = 224`, `step_y = mul_q16(300, 43562) = 199`; the unit arrives on the 42nd step (⌈12330/300⌉ = 42; `begin()+tick()` share the first pass).

**`apply_layers(base, layers_bp, min_pct, max_pct)`** implements the bible formula `final = base × Π(1 + Σdelta_in_layer/100)` with **one sequential, scaled, half-up rounding per layer** (deterministic, overflow-free for base ≤ 10⁶ and ≤ 4 layers of |Σ| ≤ 200 %):
```gdscript
var acc: int = base * 10000
for bp in layers_bp: acc = mul_div(acc, 10000 + bp, 10000, HALF_UP)      # bp = SUM of the layer's deltas in basis points (percent × 100)
var res: int = floor_div(acc + 5000, 10000)
if min_pct > 0: res = maxi(res, mul_div(base, min_pct, 100, CEIL))       # "cost and build time ≥ 60 % of base"
if max_pct > 0: res = mini(res, mul_div(base, max_pct, 100, FLOOR))
```
Worked: bible example "parent vehicle health +10 %, subfaction −10 %" → `apply_layers(1000, [1000, −1000]) = 990` (= 0.99×). `apply_layers(1000,[1000,500]) = 1155`. Floors: `apply_layers(1500,[−2000,−2500,−1500]) = 765`; with `min_pct = 60` → `900`. **Ownership.** The data resolver owns the stat arithmetic (`DefStatMath`, data 3.4; it folds layers 0–2 in one rounding and layer 3 in a second, which can differ from `apply_layers` by ≤ 1 unit — K-11). `apply_layers` is the kernel's reference implementation of the ARCH §7.3 formula for tests, AI / UI estimates and anything outside the resolver; the two must never both define the value of a *game* stat. Callers sum deltas *within* a layer, apply the layers base → parent → subfaction → research/temporary, apply the floors/caps of `mechanical_conventions` (cost/build-time ≥ 60 %, reload ≥ 50 %; resistance cap 50 % is applied by combat on the *summed* resistance), and never apply a same-source bonus twice.

**Load-time converters (DR-10).** Data JSON floats become ints exactly once: `m = Fp.milli(f)` (`roundi(f * 1000.0)` — a single IEEE multiplication, identical everywhere; `milli(0.1) = 100`, `milli(2.675) = 2675`), then integer math only: `cells_to_units(2500) = 2560` (2.5 cells), `seconds_to_ticks(1500) = 30` (1.5 s → ceil), `cps_to_units_per_tick(3000) = 154` (3 cells/s = 153.6 units/tick → half-up). The converted tables are what `data_hash` covers (data's `DefNumParse` implements the same single-rounding step for its own JSON; `Fp.milli` is the kernel-side twin and the only float entry of `core/`).


### 5.2 `SimRng`
```gdscript
seed(s):  lo = s & 0xFFFFFFFF ; hi = (s >> 32) & 0xFFFFFFFF ; st = (lo ^ mul32(hi, 0x9E3779B1)) & M
          repeat 4×: st = (st + 0x9E3779B9) & M ; lane_k = smix(st)            # smix = murmur3 fmix32: z=mul32(z^(z>>16),0x85EBCA6B); z=mul32(z^(z>>13),0xC2B2AE35); z^(z>>16)
          if all lanes == 0: s0 = 1
next_u32: t = s0 ^ ((s0 << 11) & M) ; s0=s1 ; s1=s2 ; s2=s3 ; s3 = (s3 ^ (s3 >> 19)) ^ (t ^ (t >> 8)) ; return s3
next_int(n): (next_u32() * n) >> 32       # Lemire multiply-shift, product < 2^62 for n <= 2^30 ; bias < n/2^32, irrelevant for gameplay
```
Vectors (first 5 `next_u32` of a fresh generator; cross-checked with Python): seed 0 → `2407135599, 70998536, 3162094942, 2962270859, 4032991095` · seed 1 → `3898016280, 503430273, 2109199260, 1781707058, 975518126` · seed 12345 → `1165108165, 1674106077, 2795167292, 40330380, 3604939534` · seed 4294967296 → `3443646874, 3280564437, 988752536, 1060094022, 4255169288` · seed 1234567890123456789 → `1222558724, 1588512357, 1375524028, 485886740, 2729841258`. `SimRng.new(42)`: `next_int(100)×8 = 82, 87, 94, 90, 96, 0, 16, 46`, then `range_i(−5,5)×8 = 0, −4, −2, −3, 1, −3, −3, 0` (`range_i(lo,hi) = lo + next_int(hi−lo+1)`).
**Draw discipline:** the number of draws must be a pure function of sim state — never conditional on view/UI state, on `events.enabled` (tested), on selection, or on wall time; draws inside stage code happen in entity-id order. The AI, the lobby and net use their own generators (`AiRng`, `lobby_rand`), never `world.rng`.

### 5.3 The step (time model)
```gdscript
func step() -> void:                                                         # SimWorld -- verified reference
	if match_state != MATCH_RUNNING:
		_pending.clear()                                                     # frozen: the final state is stable for the end screen
		return
	events.set_tick(tick)
	_begin_tick_moves()                                                      # last tick's movers: prev = pos, v = 0
	commands.update(self)                                                    # stage 1: sort, decode, validate, execute
	_flush_spawns()
	for i in range(1, stages.size()):                                        # stages 2..11
		var s: SimSystem = stages[i]
		if s.stride > 1 and (tick + s.stride_offset) % s.stride != 0:
			continue
		s.update(self)
		_flush_spawns()
	tick += 1
	if _inv_every > 0 and tick % _inv_every == 0:
		for msg in SimInvariants.check(self):
			Log.error("invariant", "tick %d: %s" % [tick, msg])
	if tick % _ckpt_interval == 0:
		_record_checkpoint()
```
* `tick` = ticks of *game time* (all cooldowns, `expire_tick`, `born`, domain timers use it). **There is no second counter and no sim-level pause**: net implements pause at the lockstep barrier (`CK_PAUSE`/`RESUME`, budgets in net.md 5.5.8) by *not calling `step()`*; a paused game therefore has no sim-visible trace, and replays do not record pauses. The v1 design (`step_no`, `PAUSE/UNPAUSE` commands, `pauses_used`) is withdrawn.
* Net's turn = `TURN_TICKS = 2` steps: net submits the commands of all players for the turn (`submit_raw(pid, ints)`, ascending pid, issue order inside a pid), then calls `step(); step()`. All commands of a turn therefore execute in the turn's first step; the second step has none. `speed_pct` only changes how fast net calls `step()`.
* **Canonical command order.** Stage 1 sorts the pending list by `(pid, submission index)` — a total order — so the result is independent of how the caller interleaved players; two peers that submit the same per-pid sequences execute identically.
* **Match end** (`match_state = ENDED`) freezes the world: later `step()` calls only clear the pending list; mutation APIs (`spawn_*`, `kill`, `remove_entity`, `change_owner`) become no-ops and return `null` / `false`.

### 5.4 Entity lifecycle
**Stage-stable lists (guarantee G-1).** Inside `SimSystem.update()` no list (`entities/units/structures/wrecks/zone_ents/neutrals`, per-owner lists) is appended to or compacted. `spawn_entity` registers the entity in `by_id`, the spatial hash, the player counters and (STRUCTURE / NEUTRAL) the map footprint immediately (so validation sees it) and parks it in `_spawn_queue`; `_flush_spawns()` appends the queue (ids ascending, all greater than existing ids) after every stage. `kill()`/`remove_entity()` only set flags and queue work. Dead entities stay listed (with `F_DEAD`/`F_REMOVING`, tag `ALIVE` cleared) until cleanup ends. Consequently `for i in range(n)` over a list captured at the start of a system's update is always safe, and newly spawned entities are first processed by the **next** stage (or next tick for earlier stages). Systems must skip `F_GONE` entities.

```gdscript
func kill(e: SimEntity, cause: int, killer_id: int = 0, killer_pid: int = -1) -> void:     # SimWorld
	if (e.flags & SimFlags.F_GONE) != 0 or match_state != MATCH_RUNNING:
		return
	e.flags |= SimFlags.F_DEAD
	e.hp = 0
	e.expire_tick = 0       # a hook may re-arm it with remove_deferred() to keep a corpse around
	spatial.set_tag(e.id, SimTag.of(e))
	_count_out(e)
	_dead.append(e)
	_dead_cause.append(cause)
	_dead_killer.append(killer_id)
	_dead_killer_pid.append(killer_pid)
```
`kill` is idempotent and legal at any stage; combat's `SimCombatSystem.kill(...)` is a thin wrapper around it. `remove_entity(id, reason)` sets `F_REMOVING`, refreshes the tag, drops the counters and queues the removal — no `on_dying`, no wreck.

**`SimCleanupSystem.update` (stage 11) — exact order:**
1. `_defeat_cascade`: for each eliminated (non-vacant) player, kill up to `DEFEAT_KILLS_PER_TICK = 6` living entities — units first, then structures, ascending id — with `Cause.RESIGN`.
2. **Every stage's `cleanup(world)` hook**, in stage order (combat: expire wrecks, finish dying entities; abilities: end zones …). Hooks use `kill`, `remove_entity`, `remove_deferred`.
3. `_expire_due`: for each entity in id order with `expire_tick != 0 and tick >= expire_tick`, not gone and not already removing: a **lingering corpse** (`F_DEAD`) is queued for removal (`REM_KILLED`); `F_EXPIRE_KILLS` → `kill(Cause.EXPIRE)`; otherwise `remove_entity(REM_EXPIRED)`.
4. **Rounds** (≤ 16 while the queues are non-empty):
   * **Deaths batch** = the unprocessed tail of `_dead`, sorted by entity id (`_sort_tail`, a packed-int64 key sort). For each entity: `on_dying(world, e, cause, killer_id, killer_pid)` on every stage in stage order (`killer_pid` defaults to the killer entity's owner, else −1); kernel statistics (`st_units_lost/structs_lost` for the owner, `st_*_killed` for a killer of a different owner); then, unless a hook re-armed `expire_tick` into the future (**lingering corpse**), queue the removal (`REM_KILLED`). Kills requested by the hooks are *not* processed in this batch — they form the next round's batch.
   * **Removals batch** = the unprocessed tail of `_remove_q`, sorted by id: `finalize_removal` = `on_remove` on every stage, remove from the spatial hash, vacate the map footprint (`map.vacate`, `NAV_CHANGED` with `d = 0`), clear the order queue (`on_end(END_DIED)` for begun orders), emit `REMOVED`, `by_id[id] = null`, mark gone, and if `F_HAS_CHILDREN`, `kill(Cause.ORPHAN)` every `F_TETHERED` entity whose `parent == id` (next round).
   When both queues are drained they are reset (only then: an earlier version cleared them after the first removal batch and left orphaned children as never-removed zombies — INV-17 now guards it).
5. `_flush_spawns()` (wrecks made by hooks) then `_compact_lists()` (one O(n) pass per list, order preserved).
6. `_evaluate_players`: unless `rules.victory == 0`, any non-eliminated player with `struct_count == 0 and rebuilders == 0` → `eliminate(NO_ASSETS)`.
7. `_evaluate_victory` (§5.9).
After stage 11 both queues are empty (INV-11) unless a pathological chain needed more than 16 rounds (the rest continues next tick).

```gdscript
func update(world: SimWorld) -> void:                                       # SimCleanupSystem -- verified reference
	_defeat_cascade(world)
	for s in world.stages:
		s.cleanup(world)
	_expire_due(world)
	var guard: int = 0
	while guard < 16 and (world._dead_done < world._dead.size() or world._remove_done < world._remove_q.size()):
		_process_deaths(world)
		_process_removals(world)
		guard += 1
	if world._dead_done == world._dead.size() and world._remove_done == world._remove_q.size():
		_reset_queues(world)
	world._flush_spawns()
	world._compact_lists()
	_evaluate_players(world)
	_evaluate_victory(world)
```
**Lingering corpses.** A hook that wants a dead entity to stay (an aircraft crash sequence) calls `world.remove_deferred(e.id, world.tick + n)` from `on_dying`; the entity keeps `F_DEAD`, `hp == 0`, its `x/y` (combat may still move it with `set_pos`), stays in every list and in the hash **without** the `ALIVE` bit, is not counted, and is removed at stage 11 of the first tick `>= at_tick`. INV-17 rejects a dead entity that is neither queued nor scheduled.

**Motion bookkeeping** (`set_pos` / `_begin_tick_moves`, verified reference):
```gdscript
func set_pos(e: SimEntity, x: int, y: int, teleport: bool = false) -> void:
	if x < 0:
		x = 0
	elif x > _max_x:
		x = _max_x
	if y < 0:
		y = 0
	elif y > _max_y:
		y = _max_y
	if teleport:
		e.prev_x = x
		e.prev_y = y
		e.vx = 0
		e.vy = 0
	else:
		if e._pos_tick != tick:                        # first move of this tick: remember where the tick started
			e._pos_tick = tick
			_moved.append(e.id)
			_moved_ver += 1
			e.prev_x = e.x
			e.prev_y = e.y
		e.vx = x - e.prev_x                           # displacement since the start of the tick (several calls accumulate)
		e.vy = y - e.prev_y
	e.x = x
	e.y = y
	if (e.flags & SimFlags.F_INSIDE) == 0:
		spatial.move(e.id, x, y)

func _begin_tick_moves() -> void:                      # first thing in step()
	_moved_ver += 1
	var t: PackedInt32Array = _moved_prev
	_moved_prev = _moved
	_moved = t
	_moved.resize(0)
	for id in _moved_prev:                             # last tick's movers: forget the motion
		var e: SimEntity = by_id[id]
		if e != null:
			e.prev_x = e.x
			e.prev_y = e.y
			e.vx = 0
			e.vy = 0
			e._pos_tick = -1
```
Cost: 0.64 µs per first-touch `set_pos` including the next-tick reset (0.33 µs for a plain hash move) — about +0.4 ms per tick if all 1,200 units move (M5 Max). Between two steps a caller may `set_pos` (setup code, tests): those calls are stamped with the upcoming tick and are reset at the start of that step, i.e. they behave like a move that happened "during the previous tick".

**Ownership transfer (capture).** `change_owner(id, new, reason)`: `_count_out`; remove from the old owner's list; set `owner/team`; `set_hp_max(defs.hp_max(new owner's view))` (hp keeps its ratio, min 1); `_count_in(built=false)` (transfers never add to `st_*_built`); insert into the new owner's list at the id-sorted position; refresh tag; clear the unit's orders (`END_CANCELLED`); `on_owner_changed` on every stage; emit `OWNER_CHANGED`. Neutral → player transfers start counting (struct/rebuilder/cap) at that moment. The bible restricts capture to neutral tech structures — that policy check belongs to the `T_CAPTURE` handler, not to the mechanism.

**Containers.** `set_inside(e, container, true)` sets `F_INSIDE`, `container_id`, removes `e` from the spatial hash (queries and vision no longer see it; orders are not dispatched). The cargo domain must handle carrier death in `on_dying` (kill or eject passengers) — passengers keep counting toward `unit_count` until they die. `kill()` of a passenger is legal.

**Temporary units & zones.** Spawner sets `e.expire_tick = tick + N` (or uses `spawn_zone(life_ticks)`), flags `F_TEMPORARY|F_SUMMONED` (+`F_EXPIRE_KILLS` for drones/engines that should explode, `F_TETHERED` for carrier drones bound to `parent`, `F_NO_FOOTPRINT` for structure-like decoys). Such entities never count as assets (`struct_count`/`rebuilders`), never leave salvageable wrecks unless the wreck creator says so, and disappear without ceremony unless flagged.

**Unit cap.** `SimPlayer.unit_count` = Σ `DefUnit.pop` of live units without `F_NO_UNIT_CAP` (pop 0 = exempt: Collector, MCV, drones). Production must check `world.unit_cap_room(pid)` before *starting* a unit and again before spawning; the kernel never refuses a `spawn_unit` for cap reasons (scripted/summoned spawns bypass it by flag).

**Footprints and occupancy (the map owns them; the kernel keeps them in sync).** For STRUCTURE / NEUTRAL entities `(x, y)` is the footprint centre. `spawn_entity` (unless `F_NO_FOOTPRINT`) asks the map for the def's footprint (`fp = map.footprint_of(kind, def_idx)`; null = nothing to occupy), takes the orientation `orient = (facing >> 10) & 3` for `fp.rotatable` footprints (else 0; `SPAWNED.e` carries the facing so the view rotates the same way), the rotated size `fp.size_oriented(orient)` (packed `w << 8 | h`) and the top-left cell `((x − w·512) >> 10, (y − h·512) >> 10)`, calls `map.occupy(id, fp, cx, cy, orient)` and emits `NAV_CHANGED` (a 3×3 HQ at the centre of cell (20,20) covers cells 19..21; a 2×2 barracks centred on the cell corner (60·1024, 60·1024) covers 59..60; a rotatable 3×2 dock at `facing = 1024` covers 2 wide × 3 tall — all `[verified]` in `test_sim_map`/`test_sim_api`). Removal (`finalize_removal`, after the `on_remove` hooks) calls `map.vacate(id)` and emits `NAV_CHANGED` (`d = 0`). **Placement legality is production's job** (`MapBuildRules.check == PR_OK` before it spawns, terrain_movement.md 3.6): the kernel does not re-check, so a scripted or test spawn at an arbitrary site passes `F_NO_FOOTPRINT` or relies on a tolerant map (the prototype's stub is; the real `occupy` asserts in debug builds). `change_owner`, `set_pos` and layer changes never touch occupancy; a dead structure keeps its cells until its removal (a `remove_deferred` corpse keeps them through the whole collapse sequence). The occupancy state itself lives in the map and is hashed by `map.checksum_dynamic()` (the `map` part, §8.2); the kernel's only own bit is the derived `SimEntity._occ` (hash-exempt). INV-16: every `map.occ` cell holds the id of a live occupying entity.

**Hit points.** `hp`/`hp_max` are written only by combat (damage, heal, `set_hp_max` when research changes a max) and by spawn / `change_owner`; `set_hp_max` verified: `100/100` with max 110 → `110/110`; `55/110` with max 130 → `65/130` (ratio kept, half-up, min 1).

### 5.5 Command pipeline
1. **Intake.** `submit_raw(pid, ints)` appends a `SimCommand{pid, raw, _ord = counter}` to `_pending` — nothing is decoded and no sim state changes outside `step()`.
2. **Canonical order.** At stage 1 the list is sorted by `(pid, _ord)` (`SimCommandSystem._cmp`, a total order).
3. **Decode** (`SimCommandCodec.decode`): size `1..1024` · op known (`UNKNOWN_OP`) · at least `k` fields · ids only for `M_IDS` ops, `n ≤ 512`, each `> 0`, then sorted and de-duplicated (`BAD_FIELD`).
4. **Validation** (`execute`), first failure wins; failing commands have **no effect**:
   1. issuer: `0 ≤ pid < players.size()` and not vacant (`BAD_PLAYER`) · 2. `RESIGN` is legal in **any** state (idempotent) and skips the remaining checks · 3. not eliminated (`ELIMINATED`) · 4. `MATCH_ENDED` · 5. fields (`BAD_FIELD`), by metadata bit: `M_POS` → `0 ≤ x < map.w·1024`, `0 ≤ y < map.h·1024`; `M_CELL` → `0 ≤ x < map.w`, `0 ≤ y < map.h`; `M_QUEUE` → `mode ∈ 0..2`; `M_ANGLE` → `0 ≤ angle < 4096` · 6. actors (ops with `M_IDS`): resolve each id → keep if it exists, is not `F_GONE|F_INSIDE`, `owner == pid`, and the kind matches (`M_UNITS` units, `M_STRUCTS` structures, `M_ANY` both); silently drop the rest; `NO_ACTORS` if none remain (so a partially stale selection still works) · 7. executor: `_executors[op]`; none → `NOT_AVAILABLE`.
   Domain executors add semantic checks (availability in the roster, prerequisites, funds, site, visibility, cooldown) and return `Err.*` (+ `cmd.detail`). Visibility rules (bible `rule.combat.targeting_and_warnings`): `ATTACK/CAPTURE/SALVAGE/LOAD…` targets must satisfy `world.fog.entity_visible(pid, target)` or be owned/allied; `USE_POWER` needs current vision of the target cell unless the power is a reconnaissance power; `LAUNCH_SUPERWEAPON` needs `cell_explored`.
5. **Rejection feedback.** A failed command counts `st_rejected` and emits `CMD_REJECTED(pid, op, err, detail, target-or-def)` throttled to one per 10 ticks per player (only for real players); the UI turns it into a sound/toast. An accepted command increments `st_cmds`. The AI does not receive rejections; it verifies effects by state, and can read `st_rejected` for its telemetry.
6. **Built-in executors.**
   * *Order ops* (`MOVE, FOLLOW, PATROL, LOAD, GARRISON, CAPTURE, REPAIR, SALVAGE, HARVEST, RETURN_CARGO, ATTACK, ATTACK_MOVE, GUARD, HOLD, FORCE_FIRE, RETURN_TO_BASE`): for each actor (ascending id) build a **fresh** `SimOrder` (`type` from the op; `target_id/x/y` copied; `OF_FORCED` for `ATTACK` flag bit0; for `MOVE`, `ATTACK_MOVE` and `PATROL` the command flags map bit0 → `OF_NO_FORMATION`, bit1 → `OF_SPEED_MATCH`, bit2 → `OF_REVERSE_OK`; `OF_CYCLIC` for `PATROL`; `FORCE_FIRE` `arg = count`) and call `orders.issue(world, e, o, cmd.mode)`; result OK if ≥ 1 actor accepted else the last error. A domain (combat for 40–47) may register its own executor instead and create richer orders.
   * `STOP`: `orders.clear(END_CANCELLED)` per actor. `SCATTER`: per actor in ascending id, `nx = clamp(x + rng.range_i(−3072, 3072))`, then `ny` likewise (two draws each), issue `T_MOVE` with `QM_REPLACE` (3 cells max radius; deterministic because draw order = id order). `SCUTTLE`: `kill(e, Cause.SCUTTLE, 0, cmd.pid)` (no wreck by convention: combat's hook makes wrecks only for `Cause.DAMAGE`).
   * `RESIGN` (`mode` = net's `ResignReason`, clamped 0..4): `eliminate(pid, Elim.RESIGN + mode)`; idempotent. The host injects it *on behalf of* a dropped / kicked / timed-out human (it is the first command of that pid's group), so no separate "drop" command exists.
   * `DEBUG` (needs `rules.allow_debug`, which the lobby never sets; wire `mode, target, def, count, x, y`): `mode 1` = `add_credits(pid, count, CASH_SCRIPT)`, `mode 2` = spawn `count` units of `def` at (x,y), `mode 3` = `kill(target, Cause.SCRIPT)` (`NO_TARGET` if it is gone); every other mode is offered to the stages' `on_debug` hook in stage order (vision 4 = reveal, combat 5 = set hp of `target` to `count`, economy 6 = charge powers) and is `BAD_FIELD` if no stage answers.
7. **Wire safety.** Decoding is total: malformed input is a counted rejection, never an engine error; `cmd.pid` is whatever the caller passed (net stamps it from the connection, never from the payload).

### 5.6 Orders
* **Queue.** `orders[0]` is current. `issue(..., QM_REPLACE)` ends every begun order (`on_end(END_REPLACED)`), clears, appends; `QM_APPEND` appends (fails `QUEUE_FULL` at 32); `QM_FRONT` inserts at index 0 — the interrupted order keeps its `phase` and resumes when the inserted one finishes (retaliation, fleeing). Before the handler's `can_issue`, every stage's `order_gate` may veto the order (`DISABLED`, …).
* **Dispatcher** (per stage-5 update; units in id order; skips `F_GONE|F_INSIDE`) — verified reference:
  ```gdscript
  func update(world: SimWorld) -> void:                       # SimOrderSystem
      var list: Array[SimEntity] = world.units
      var n: int = list.size()
      for i in n:
          var e: SimEntity = list[i]
          if (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
              continue
          var q: Array[SimOrder] = e.orders
          if q.is_empty():
              for h in _idle:                                  # registration order
                  h.on_idle(world, e)
                  if not q.is_empty():
                      break
              continue
          var o: SimOrder = q[0]
          var h2: SimOrderHandler = _handlers[o.type]
          if h2 == null:
              q.pop_front()
              continue
          var st: int
          if h2.requires_target and o.target_id != 0 and not world.is_alive(o.target_id):
              st = h2.on_target_lost(world, e, o)              # default FAILED
          elif o.phase == SimOrder.PH_NEW:
              o.phase = 1
              st = h2.on_begin(world, e, o)
              if st == SimOrder.RUNNING:
                  st = h2.on_update(world, e, o)               # zero-latency start
          else:
              st = h2.on_update(world, e, o)
          if st != SimOrder.RUNNING:
              var idx: int = q.find(o)                         # a handler may have pushed a child in front
              if idx >= 0:
                  q.remove_at(idx)
              if o.phase != SimOrder.PH_NEW:
                  h2.on_end(world, e, o, SimOrder.END_FAILED if st == SimOrder.FAILED else SimOrder.END_DONE)
              if st == SimOrder.FAILED:
                  world.events.emit(SimEvent.ORDER_FAILED, e.x, e.y, e.id, o.type, o.fail, 0)
              elif (o.flags & SimOrder.OF_CYCLIC) != 0 and q.size() < SimConfig.MAX_ORDERS:
                  o.phase = SimOrder.PH_NEW
                  q.append(o)                                  # patrol loops
  ```
  At most **one handler call per unit per tick** (plus the begin→update fusion), so a handler that pushes a child order in front runs the child next tick.
* A handler may `issue(..., QM_FRONT)` sub-orders (attack-move → attack), mutate its own order's `phase/t0/p0/p1`, and talk to executor systems only through components (e.g. movement's `SimCompMove` goal), never by calling their internals.
* `FAILED` drops **only that order**; the rest of the queue continues (C&C behaviour). `DONE` likewise. `on_end` is called for every order that began, whatever the reason it left (done, failed, stop, replaced, the unit died or was removed, ownership changed → `END_CANCELLED`).
* Handlers must be **stateless and deterministic**; all state lives in the order or in components (both hashed). Domain specs map onto this interface as: economy `on_begin/on_update/on_end` (same names), combat `step → on_update`, `step_idle → on_idle`, `on_order_start → on_begin`, `clear_target → on_end`, `apply_command → an executor` (§6.4).

### 5.7 Events
* One flat `PackedInt32Array`, records of 10 ints `[type, tick, x, y, a, b, c, d, e, f]`. `emit` is O(1) amortised (`resize(n+10)` + 10 stores, 0.2 µs). If the buffer would exceed `EVENT_SOFT_CAP_INTS` the event is dropped and `dropped++` (never affects the sim). `enabled = false` makes every emit a no-op (soak tests); toggling it never changes the checksum chain (tested).
* **Determinism of emission.** Events are output-only (DR-12) but their *emission sequence* is deterministic and is itself tested (`events.digest()` identical across runs/platforms) so presentation replays are reproducible.
* **Throttles** (`emit_throttled`, per `(type, pid)`, event types < 512): the kernel throttles `CMD_REJECTED` (10 ticks); the domains throttle their own alerts (combat: `ATTACK_ALERT` per its spec; economy: insufficient funds 100 ticks, unit cap 200 ticks) with the same helper. Never throttled: lifecycle, elimination and match events.
* **Draining.** The app calls `events.take()` once per rendered frame (after running 0..k steps) and hands the same array, read-only, to view, audio and UI. Nobody may retain the array across frames for mutation; each consumer keeps its own cursor if it needs history. The host-side AI does not consume events (it derives what it needs from state, ai.md 6.2).
* **Per-viewer filtering** is a presentation concern: every event carries `x,y`, so `view/audio` filter positional events by the local fog (`world.fog.cell_visible`); events that must never be filtered (superweapon warnings) say so in their owner's table. The kernel has no `watch_mask` (v1 idea withdrawn; vision emits its own per-group events, abilities 231–233).

### 5.8 Spatial hash
* Bucket = 4×4 cells (`SHIFT = 12`) → 24×24 buckets on a 96² map, 64×64 on 256². One bucket = one `PackedInt32Array` of ids; per-id parallel arrays hold `x`, `y`, `tag`, `bucket` (grown by doubling; ~16 B/id).
* Exactly one bucket per entity (centre). `insert`/`remove`/`move` are O(bucket size) (swap-remove; bucket order is irrelevant because results are sorted). `move` re-buckets only when the bucket index changes (≈ every 4 cells of travel).
* `query_circle`: buckets covering `[x−r, x+r]²`, per candidate `(tag & need) == need and (tag & avoid) == 0` then exact `dx²+dy² ≤ r²`; finally `out.sort()`. Measured on a dense cluster (800 of 1,200 entities inside 30×30 cells): **6.9 µs at r = 4 cells, 15.4 µs at r = 8 cells** (≈ 40 ns per candidate); on 1,688 entities spread over the map: 4.9 / 11 µs. Sorting a packed int array is native and a total order → deterministic id order.
* Why 4 cells: ~2× over-scan at r = 8 with 25 buckets; 2-cell buckets scan 81 buckets for the same area (bucket overhead dominates).

```gdscript
func query_circle(x: int, y: int, r: int, out: PackedInt32Array, need: int = 0, avoid: int = 0) -> int:
	out.resize(0)
	var r2: int = r * r
	var x0: int = x - r
	var y0: int = y - r
	var bx0: int = 0 if x0 < 0 else x0 >> SHIFT              # never shift a negative value
	var by0: int = 0 if y0 < 0 else y0 >> SHIFT
	var bx1: int = (x + r) >> SHIFT
	var by1: int = (y + r) >> SHIFT
	if bx1 >= bw:
		bx1 = bw - 1
	if by1 >= bh:
		by1 = bh - 1
	for by in range(by0, by1 + 1):
		var row: int = by * bw
		for bx in range(bx0, bx1 + 1):
			var ids: PackedInt32Array = _buckets[row + bx]
			for k in ids.size():
				var id: int = ids[k]
				var t: int = _tag[id]
				if (t & need) != need or (t & avoid) != 0:
					continue
				var dx: int = _px[id] - x
				var dy: int = _py[id] - y
				if dx * dx + dy * dy <= r2:
					out.append(id)
	out.sort()                                                # native, total order -> ascending ids
	return out.size()
```
Verified against brute force: 300 circle + 300 rect queries over 1,200 entities with random tag filters — 0 mismatches.

### 5.9 Victory and defeat
* **Elimination.** A player is eliminated when `struct_count == 0 and rebuilders == 0` — owns no structure and no MCV-class unit (ARCH §12). Both counters count only **assets**: STRUCTURE / UNIT entities that are not `F_TEMPORARY | F_DECOY | F_SUMMONED`, so a decoy radar or a summon never keeps a player alive (economy's `q_can_rebuild`); a captured neutral building counts from the moment of capture. The rule is evaluated in stage 11 after removals, so a player whose last structure died this tick is eliminated this tick. Other causes: `RESIGN` command (immediate; reason = net's `ResignReason` via `Elim.RESIGN + mode`: surrender / disconnect / kicked / timeout / desync drop). `victory == 0` disables the automatic rule only.
* **Defeat cascade.** Every tick, at most 6 of the eliminated player's remaining entities die (`Cause.RESIGN`): units by ascending id, then structures. Verified timeline for 20 units after `RESIGN` (HQ dead in the same cleanup): units left after each step = `14, 8, 2, 0, 0`. Their production, research, power and superweapon state are dropped by `on_player_eliminated`.
* **Team victory.** After removals, the set of teams with ≥ 1 non-eliminated player is computed (team ids up to 15, as a bit set). `≤ 1` team ⇒ `end_match(winner = that team or −1, ELIMINATION or DRAW)`. Else if `rules.end_when_no_humans` and the match started with ≥ 1 human and no non-eliminated human remains ⇒ `end_match(−1, NO_HUMANS)`. Allies win together; a lone survivor ends the game at once. Vacant pids are pre-eliminated and never participate.
* **Match end** freezes the world (§5.3), emits `MATCH_END(winner_team, reason, tick)` and records `end_tick = tick` (the tick being simulated when the last elimination was processed).

### 5.10 Config, validation and hashing
* **`from_dict`** reads exactly net.md 7.1: `seed`, `map`, `rules{…}`, `players[]{pid, kind, name, roster, team, color, start, handicap, ai{level, style, flags}}` (bool rules folded to 0/1, unknown keys ignored, `peer` ignored); `players` are sorted by pid. Scalars are read with `int()`; the `map` dictionary must already be int-only (net's `NetMatchConfig.normalize` guarantees it; `validate` re-checks with `is_int_only` — the sim contains no float handling, lint L003).
* **`config_hash()`** (also mixed into every checksum through the `world` part): `h = FNV_OFFSET; h = mix64(h, seed); h = mix(h, digest32(rules stream)); for every player in pid order: mix(pid), mix(kind), h = fnv_string(roster, h), mix(team), mix(color), mix(start), mix(handicap), mix(ai_level), mix(ai_style), mix(ai_flags); h = fnv_string(JSON.stringify(map, "", true), h); return finalize(h)`. Names are excluded. Fixture values: 2-player fixture config `856134193`; the net.md 7.1 worked example (with fixture rosters) `3200203660`. (Net computes its own `config_hash` over the exact transmitted JSON bytes for the lobby handshake; this one detects a sim-relevant difference after normalisation.)
* **`validate(data, start_count)`** (deterministic): `seed` u32 · `map` int-only · 1..8 players · per player: pid unique in 0..7, roster exists, `team 1..15`, `color 0..11` unique, `start` unique and `< start_count`, `handicap 50..200` · rules ranges (§4.11). Example bad config → `["seed must be a u32", "pid 0: handicap out of range", "pid 1: unknown roster 'roster.nope'", "pid 1: team out of range", "pid 1: colour invalid or duplicated", "rules.unit_cap out of range"]`. `SimWorld.create(data, cfg, map, opts)` runs it and returns `null` (after `Log.error` per problem) instead of constructing; net's `world_builder` and the app must use `create`.
* **Replays.** The replay *file* (`*.mfreplay`: header + canonical config JSON + `TURNS`/`CHECK`/`PARTS`/`END` records) is net.md 4.8 / `NetReplay`. The kernel's obligations are (a) `submit_raw` + `step` are the only inputs, (b) `checksum_at`/`checksum_parts_at` for verification, (c) the config JSON is the `MatchConfig` net stores. `SimCommandLog` is the in-memory equivalent for tests: 5 records over 130 ticks = 41 ints; `play()` on a fresh world reproduces every checkpoint and the final checksum, and tampering with one command is reported at the first divergent checkpoint (tick 20 in the test). Replays always start at tick 0 (no mid-game snapshot restore in v1).

### 5.11 How each bible / design rule in this domain is honoured

| Rule (source) | Honoured by |
|---|---|
| Start preset: deployed HQ + 7,500 credits, veterancy off (`mechanical_conventions.starting_preset`) | `SimMatchRules.start_credits/start_mode`, constructor spawns the HQ (`SPAWN_INITIAL`); veterancy reserved = 0 |
| Unit cap 150 non-structure entities/player (ARCH §12), Collector / MCV exempt (data `pop 0`) | `unit_cap`, `SimPlayer.unit_count` (Σ pop), `F_NO_UNIT_CAP`, `unit_cap_room()` |
| Wrecks: enemy land-vehicle wrecks persist 60 s unless destroyed/salvaged; no salvage from friendly fire, deliberate scuttling, summons (`rule.combat.submarines_and_wrecks`) | mechanism only: `spawn_wreck`, `expire_tick`, `F_NO_SALVAGE`, `SCUTTLE` → `Cause.SCUTTLE`; the *policy* (which deaths leave a wreck, eligibility, life 1200 ticks from `DefEconomy.wreck_life_t`) is combat's `on_dying` hook |
| AE: "each wreck pays once; 20 % of paid cost; allied/self-destroyed/decoy/summoned pay nothing" | wreck keeps `paid_cost` + original `owner`; the salvage channel `remove_entity(wreck, REM_CONSUMED)` after paying; eligibility flag decided at creation |
| Engineer repair cost 0.5 % of *paid price*/s | `SimEntity.paid_cost` |
| Research persists if buildings are lost; losing a prerequisite only pauses dependent orders (`rule.design.research`) | economy's counters vs `DefPlayerView`/`DefLayer3` (research state is data's, hashed via `view.checksum()`) |
| Power is a capacity budget; shortage halves production/research, stops powered defenses, pauses SW recharge (`rule.design.power_loss`) | `power_supply/power_demand` mirrors, `F_POWERED`; logic in economy |
| Support powers: three per roster, ready when first unlocked, cooldown never reset by rebuilding (`rule.combat.support_power_access`) | economy's `SimPlayerEcon` (hashed in the `economy` part); commands carry the power index (`USE_POWER`) |
| Superweapon: starts empty, one stored charge, launcher destroyed during warning cancels without refund (`rule.combat.superweapon_control`) | economy's state + its `on_remove(launcher)` hook; events in its block (`SW_*`); warning zones broadcast to all players (not fog-gated) |
| Powers need current vision unless reconnaissance; superweapons may target explored terrain (`rule.combat.targeting_and_warnings`) | executors use `SimFogApi.cell_visible/cell_explored` |
| One production queue per Barracks/Factory/Airfield/Dock, one player-wide research queue and one construction queue (`rule.design.production`) | `SimCompProd` (per structure) vs `SimPlayerEcon` (player-wide) slots |
| Victory: eliminated when no structures and no MCV; teams win together (ARCH §12) | §5.9 |
| Summoned attackers / Aurora select enemies only; support buffs affect friendlies (`damage_and_area_notation`) | relation table `Rel`, `F_SUMMONED`, `world.non_enemy_mask` |
| Income multipliers for AI handicap (net XR-9): start credits and harvest / salvage income only, never costs or stats | `add_credits` handicap scaling (§3.4.7) |
| Chat is not a sim command (charge) | no opcode |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

### 6.1 MASTER command catalog (opcode = `ints[0]`, decimal blocks; fields listed in **wire order**, the id list (`+ ids`) always last)
Blocks: **1–39 core / movement / unit orders** (this domain) · **40–47 combat** (combat.md 6.1) · **99 debug** · **100–119 abilities** (abilities.md 6.1) · **120–149 economy** (production 120–131, economy 132–139, strategic 140–149; economy.md 6.1) · **240–255 net / system** (net.md 6.1; only `RESIGN = 250`). Everything else is unassigned; adding an op needs an amendment to this table. The AI, the UI command bus and tests build commands **only** with the `SimCmd.<name>` builders (they return the `PackedInt32Array` net carries); a domain never hand-packs ints.

Metadata (checked by the kernel before any executor runs): **U** actors must be UNITs · **S** actors must be STRUCTUREs · **A** either (`M_ANY`) · **P** `x,y` are sub-cell coordinates inside the map · **C** `x,y` are cell coordinates inside the map · **Q** `mode` is a queue mode (`QM_REPLACE 0 / APPEND 1 / FRONT 2`; Shift-click = append) · **G** `angle` in 0..4095. `target` ≤ 0 means "none" in every op **except** `SET_RALLY` (there a negative value encodes `−(deposit_idx+1)`); ids are entity ids; `def` is a def / slot / power / research index in the table the op names.

| Code | `SimCmd` name | Wire fields (then `+ ids`) | Meta | Executor | Producer (UI / AI) and semantics |
|---|---|---|---|---|---|
| 1 | `MOVE` | `x, y, mode, flags` | U P Q | built-in → `T_MOVE` | right-click ground; `flags` b0 = no formation · b1 = speed match (the group moves at its slowest member) · b2 = reverse allowed (short moves) |
| 2 | `STOP` | – | U | built-in | `S`; cancels the whole queue (`END_CANCELLED`) |
| 3 | `SCATTER` | – | U | built-in (2 `range_i` draws per actor) | `X` |
| 4 | `PATROL` | `x, y, mode, flags` | U P Q | built-in → `T_PATROL` (always cyclic) | `P` + clicks; Shift chains waypoints; `flags` as `MOVE` |
| 5 | `LOAD` | `target, mode` (ids = passengers, target = transport) | U Q | built-in → `T_LOAD` (abilities' `SimTransport`) | right-click a friendly transport |
| 6 | `GARRISON` | `target, mode` | U Q | built-in → `T_GARRISON` | right-click a garrisonable building |
| 7 | `CAPTURE` | `target, mode` | U Q | built-in → `T_CAPTURE` (economy) | right-click a neutral tech structure with an Engineer |
| 8 | `REPAIR` | `target, mode` | U Q | built-in → `T_REPAIR` (economy) | right-click a damaged friendly vehicle / structure with a repairer |
| 9 | `SALVAGE` | `target, mode` (target = wreck) | U Q | built-in → `T_SALVAGE` (economy) | right-click a wreck with an AE salvager |
| 10 | `HARVEST` | `target, x, y, mode` (0 = the deposit cell nearest to x,y — the map's per-cell model; a positive target names a DEPOSIT entity only if the reconcilers keep that model, Q-7) | U P Q | built-in → `T_HARVEST` (economy) | right-click a deposit with a Collector |
| 11 | `RETURN_CARGO` | `target, mode` (target = refinery, 0 = nearest) | U Q | built-in → `T_RETURN_CARGO` (economy) | `R` / right-click a refinery |
| 12 | `FOLLOW` | `target, mode` (target = a friendly or allied unit) | U Q | built-in → `T_FOLLOW` (movement) | right-click a friendly unit with the follow modifier: keep at escort distance (terrain_movement.md `CMD_FOLLOW`) |
| 40 | `ATTACK` | `target, mode, flags` | U Q | built-in → `T_ATTACK`; combat may override | right-click an enemy; `flags` bit0 = forced (attack own / allied / neutral, Ctrl+right-click) |
| 41 | `ATTACK_MOVE` | `x, y, mode, flags` | U P Q | built-in → `T_ATTACK_MOVE` | `A` + click; `flags` as `MOVE` |
| 42 | `GUARD` | `target, x, y, mode` (target 0 = guard the point) | U P Q | built-in → `T_GUARD` | `G` + click a friendly unit or ground |
| 43 | `HOLD` | – | U | built-in → `T_HOLD` | `H`: hold position |
| 44 | `FORCE_FIRE` | `target, x, y, count` (target 0 = ground point) | U P | built-in → `T_FORCE_FIRE` (`arg = count`) | Ctrl + click |
| 45 | `SET_STANCE` | `mode` (combat `ST_*`: 0 aggressive · 1 defensive · 2 hold fire · 3 guard) | U | **combat** (`cc.stance`) | stance buttons; no built-in executor |
| 46 | `SCUTTLE` | – | U | built-in (`kill(Cause.SCUTTLE)`) | Ctrl+Delete (confirm); no wreck |
| 47 | `RETURN_TO_BASE` | `target, mode` (target = airfield or carrier id, 0 = nearest) | U Q | built-in → `T_RETURN_BASE` | Return button (aircraft / drones rearm) |
| 99 | `DEBUG` | `mode, target, def, count, x, y` | – | built-in; needs `rules.allow_debug` | dev console / QA / soak: 1 = grant `count` credits · 2 = spawn `count` units of `def` at (x,y) · 3 = kill `target` (`Cause.SCRIPT`) · ≥ 4 = the stages' `on_debug` hook (4 reveal = vision, 5 set hp of `target` to `count` = combat, 6 charge powers = economy); never sent by the lobby, the AI or the UI |
| 100 | `DEPLOY` | `def` (ability slot, −1 = the unit's deploy ability; MCV → `T_DEPLOY_MCV`) | A | **abilities** | `D` |
| 101 | `UNDEPLOY` | `def` (slot) | A | abilities | pack / undeploy |
| 102 | `SET_MODE` | `def, mode` (slot; mode idx, −1 = cycle) | A | abilities | loadout / wing / siege-mobile switch |
| 103 | `USE_ABILITY` | `def, mode, target, x, y` (slot; op 0 start · 1 cancel) | A | abilities | ability button (cover, decoy, puck, smoke, repair, salvage, capture) |
| 104 | `SET_AUTOCAST` | `def, mode` (slot; 0 / 1) | A | abilities | auto-cast toggle |
| 105 | `UNLOAD` | `mode, target, x, y` (0 all · 1 one; target = passenger; ids = transports **or garrison structures**) | A P | abilities (`SimTransport.begin_unload`) | `U` / Unload button |
| 120 | `BUILD_START` | `def, count` (structure idx, 1..5) | – | production | sidebar structure icon |
| 121 | `BUILD_CANCEL` | `mode` (queue index, 0 = head incl. a READY item) | – | production | right-click the icon |
| 122 | `BUILD_HOLD` | `mode` (1 hold · 0 resume) | – | production | hold button |
| 123 | `BUILD_PLACE` | `def, x, y, mode` (structure idx, **cell** cx, cy, rotation 0..3) | C | production (placement) | click with the placement ghost |
| 124 | `TRAIN` | `target, def, count` (producer id, 0 = auto; unit idx; 1..5) | – | production | sidebar unit icon (left = 1, Shift = 5) |
| 125 | `TRAIN_CANCEL` | `target, mode` (producer id, queue index) | – | production | right-click the icon |
| 126 | `QUEUE_HOLD` | `mode` (1 hold · 0 resume) (ids = producers) | S | production | hold button |
| 127 | `SET_RALLY` | `x, y, target, flags` (target = entity, or `−(deposit_idx+1)` = harvest that deposit; `flags` bit0 = clear) (ids = producers) | S | production | rally-point mode click |
| 128 | `SET_PRIMARY` | `target` (producer id) | – | production | primary-building button |
| 129 | `RESEARCH` | `def` (research idx) | – | production | research icon |
| 130 | `RESEARCH_CANCEL` | `mode` (queue index) | – | production | right-click the icon |
| 131 | `RESEARCH_HOLD` | `mode` (1 / 0) | – | production | hold button |
| 132 | `SELL` | – | S | economy | sell-mode click |
| 133 | `SET_STRUCT_REPAIR` | `mode` (0 off · 1 on · 2 toggle) | S | economy | repair-mode click |
| 134 | `UNDEPLOY_HQ` | – | S | economy | HQ → MCV |
| 140 | `USE_POWER` | `def, x, y, angle, target` (power idx of the roster's three; centre + direction for LINE targets; target = own structure / unit for those target modes) | P G | economy (strategic) | power button + targeting click |
| 141 | `LAUNCH_SUPERWEAPON` | `x, y, angle` | P G | economy (strategic) | SW button + targeting click (drag sets the angle) |
| 250 | `RESIGN` | `mode` (0 surrender · 1 disconnect · 2 kicked · 3 timeout · 4 desync drop) | – | built-in (idempotent, legal in any state) | menu → Resign; **host-injected** for departed players (net.md 6.1) |

45 ops. **Field bit conventions:** `MOVE` / `ATTACK_MOVE` / `PATROL` `flags` b0 no-formation · b1 speed-match · b2 reverse-ok (→ `OF_NO_FORMATION`, `OF_SPEED_MATCH`, `OF_REVERSE_OK`) · `ATTACK` `flags` b0 forced · `SET_RALLY` `flags` b0 clear. All other flag bits must be 0 (executors reject with `BAD_FIELD` if a domain later assigns them).
**Error feedback:** `SimCommand.Err` (§4.1) plus `cmd.detail` (the domain's own reason: economy `RSN_*`, abilities 1..10). The UI maps `CMD_REJECTED` to sounds/toasts (`NO_CREDITS` "Insufficient funds", `NO_PREREQ`, `BAD_SITE`, `NOT_READY` "Power not ready", `UNIT_CAP`).
**Not commands:** chat, pings, selection, control groups, camera, hotkey remaps, game speed, pause / resume, observer joins (net or presentation).

### 6.2 MASTER event registry
Record `[type, tick, x, y, a, b, c, d, e, f]` (§4.9). **Blocks:** 1–99 core (below) · **100–129 movement** (terrain_movement.md 6.3, renumbered from its proposed 0x40–0x48: `EV_MOVE_FAILED 100 … EV_STUCK 108`, table in §6.4-F1) · **130–159 scripted missions** (MIS1, `SimMissionSystem`: `MISSION_OBJECTIVE 130 … MISSION_REVEAL 140`, layouts in `src/sim/sim_event.gd`) · 160–199 unassigned · **200–229 combat** (combat.md 6.2: `EV_FIRE 200 … EV_WEAPON_LOCK 220`) · **230–259 abilities** (abilities.md 6.2: `EV_CLOAK_CHANGED 230 … EV_BUFF_APPLIED 259`) · **300–499 economy / production / power** (economy.md 6.2: `EVT_STRUCTURE_READY 302 … EVT_SW_DONE 409`) · 500–999 presentation-local ids that are never emitted by the sim. Each domain owns the layout of its block (field meanings are in its own spec); the kernel provides the buffer, the `x,y` slot and the throttle helper.

Core events (emitted by the kernel; `x,y` = position, `(0,0)` if none):

| Code | Name | a · b · c · d · e · f | Consumers / notes |
|---|---|---|---|
| 1 | `SPAWNED` | id · kind · def_idx · owner · facing · reason (`SPAWN_*`) | **always the first event of its entity**; view creates the node (mesh by kind + def, structure rotation from `facing`), minimap, audio "unit ready" (reason PRODUCED) |
| 2 | `REMOVED` | id · kind · def_idx · owner · reason (`REM_*`) | view destroys the node (a corpse may outlive it: combat's `EV_DEATH` carries `visual_ticks`), UI drops it from selection |
| 3 | `OWNER_CHANGED` | id · old_owner · new_owner · reason (0 capture, 1 script) | recolour, audio "captured", minimap |
| 4 | `CASH` | pid · delta · new_total · reason (`CASH_*`) · source_id | credits ticker, floating "+$" at `x,y` (economy's `EVT_CREDITS_GAINED` is this event); not emitted for `silent` spends |
| 5 | `CMD_REJECTED` | pid · op · err (`Err`) · detail · target-or-def | error sound/toast; throttled 10 ticks per player; replaces economy 300 and abilities 253 |
| 6 | `ORDER_FAILED` | unit id · order type · err (`o.fail`) · detail | "cannot reach" audio (UI throttles); replaces economy 319 |
| 7 | `PLAYER_ELIMINATED` | pid · reason (`Elim`) · team | announcer, scoreboard |
| 8 | `MATCH_END` | winner_team (−1 none) · reason (`EndReason`) · tick | end screen |
| 9 | `NAV_CHANGED` | changed cell bbox packed `cx0<<24 \| cy0<<16 \| cx1<<8 \| cy1` (bytes; mask `& 0xFFFFFFFF` after int32 storage) · `map.nav_version` · structure id · 1 occupied / 0 vacated; `x,y` = structure centre | AI (invalidate site / route caches), view (path debug); emitted whenever the kernel calls `map.occupy` / `map.vacate` (terrain_movement.md `EV_NAV_CHANGED`, which asked its caller to emit it) |

No `DIED` event: the death record is combat's `EV_DEATH` (208) — it knows the death kind, cause, killer and visual timing; the kernel's lifecycle events are `SPAWNED`/`NAV_CHANGED`/`REMOVED`. There is no `PAUSED`, `CHECKPOINT` or `MATCH`-level pause event (net owns pause and reads `checksum_at`).

**Ordering guarantees** (normative; render.md request 1): events appear in emission order, which inside a tick is stage order (commands, production, economy, power, orders, movement, abilities, combat, zones, vision, cleanup). `SPAWNED` is the first event of every entity — it precedes `NAV_CHANGED` and everything a domain's `on_spawn` hook emits. Removal emits `NAV_CHANGED` (`d = 0`) and then `REMOVED`, the kernel's last event for that entity; combat's `on_dying` hook runs before the removal batch, so its `EV_DEATH` precedes `REMOVED`. One `events.take()` per rendered frame is handed read-only to view, audio, UI and the host AI.

### 6.3 What other domains must add / register (checklist)

| Domain | Must do |
|---|---|
| movement | `SimMovementSystem` (stage 6, overwrites the stub); handlers `T_MOVE, T_PATROL` (+`T_FOLLOW/FACE/LAND`); `SimCompMove`; positions only via `set_pos` (per tick, once per mover — it maintains `prev/v`), layers via `set_layer`; set `F_MOVING/F_AIRBORNE/F_BLOCKED/F_ON_WATER`; skip `F_SCRIPTED_MOVE` and `F_GONE` entities; read `abilities.speed_units(e)` / `is_immobile(e)`; events 100–129; keep a private ascending list of your movers (append in `on_spawn`, compact in your `cleanup(world)` hook — there is no `world.movers`); the order flags `OF_NO_FORMATION / OF_SPEED_MATCH / OF_REVERSE_OK` arrive on `MOVE` / `ATTACK_MOVE` / `PATROL` orders; **do not call `map.occupy` / `vacate`** — the kernel does (§5.4); `map.nav.prepare(...)` for the rosters in `init_world` |
| combat | `SimCombatSystem` (8); executor for `SET_STANCE` (and optionally 40–47); handlers `T_ATTACK, T_ATTACK_MOVE, T_FORCE_FIRE, T_GUARD, T_HOLD, T_RETURN_BASE` + an idle hook (auto-acquire); `SimCompCombat/Air/Carrier`; projectile pool with `alloc_proj_id()`; **`on_dying` = the death path** (wreck via `spawn_wreck`, `EV_DEATH`, cargo ejection, crash via `remove_deferred`); hp only through its own writers and `set_hp_max`; `kill()` wrapper around `world.kill`; own the status timers (`last_hit_tick`, `last_fire_tick`, EMP, suppression); events 200–229 |
| production / economy / power / strategic | `SimProductionSystem` (2), `SimEconomySystem` (3), `SimPowerSystem` (4) (+ `SimStrategicSystem` helper called by power); executors `120–134, 140, 141`; handlers `T_HARVEST, T_RETURN_CARGO, T_CAPTURE, T_REPAIR, T_SALVAGE, T_DEPLOY_MCV` + idle auto-harvest; `SimCompEcon`, `SimCompProd`, `SimPlayerEcon` (queues, tech counters, power grid, powers, superweapon — all hashed via `hash_state` / `hash_into`); credits **only** through `add_credits/try_spend`; `p.view.apply_research(idx)` at research completion (players in ascending pid); `spawn_*(paid_cost = credits paid)`; `power_supply/power_demand` mirrors; capture via `change_owner`; consume wrecks via `remove_entity(REM_CONSUMED)`; events 300–499 |
| abilities / zones / vision / transports | `SimAbilitySystem` (7), `SimZoneSystem` (9), `SimVisionSystem` (10, `stride = 2`); executors `100–105`; `SimCompAbility/Stats/Vision/Cargo/Summon`, `SimPlayerFx/Vision`; `order_gate` for uncontrollable states; replace `world.fog` in `init_world`; zones / summons via `spawn_zone` / `spawn_unit(… F_SUMMONED …)` + `expire_tick`; `set_inside` for cargo; `on_dying(carrier)` kills / ejects passengers; read `moved_prev2()`; events 230–259 |
| net | `submit_raw(pid, ints)` per command in `(pid, issue)` order then `step()` ×2; `checksum_at/parts_at/part_names/dump_state/is_match_over/match_result/is_player_active/map_hash/clear_events`; `SimWorld.create(...)` in `world_builder`; injects `RESIGN` (250) for departed players; owns pause, speed, replay file, desync reports |
| production (placement) | `MapBuildRules.check == PR_OK` → `SimDockMove.units_in_footprint / evict` → `world.spawn_structure(def, pid, cx·1024 + w·512, cy·1024 + h·512, facing = 1024·orient, …)` with `w, h` the rotated footprint size — the kernel occupies; pass `F_NO_FOOTPRINT` only for structure-likes that must not block |
| view / ui / audio / ai | consume `events.take()`; query API only; commands via `SimCmd` builders through net; never mutate sim objects; view interpolates `prev → pos` |
| data | `GameData` API of §7.2 (only what `SimDefs` reads), `GameData.for_test`, `DefRoster.hq_idx/mcv_idx`, `data_hash()` |
| map | `MapData` API of §7.2b (`w, h, spawns, neutrals, clone_fresh(), map_hash(), checksum_dynamic(), occupy / vacate / occupant_at, footprint_of, neutral_def_for_kind`); `MapBuildRules.check` stays production's precondition |

### 6.4 Reconciliation crosswalk with the concurrently published specs
**Principle.** Kernel-owned vocabulary follows the majority of the domain specs; state a domain must be able to trust (credits, elimination counters, ids, hashing) stays in the kernel; state a domain owns (queues, tech, powers, wrecks, status timers, stance) is *not* mirrored in the kernel. "Adopted" = the kernel now uses the other spec's name; "Kernel" = the domain spec should adapt; "Merged" = two domain specs overlap and the recommendation says which survives.

**A. Entity & world vocabulary**

| Topic | Domain spec says | This spec | Resolution |
|---|---|---|---|
| Entity fields | `hp_max`, `paid_cost`, `expire_tick`, `container_id` (−1), `radius`, `prev_x/prev_y`, `vx/vy` (combat, abilities, ai, economy 3.8) | identical | **Adopted** (economy's `max_hp` → `hp_max`) |
| Component slots | `comp_econ, comp_prod, comp_wreck, comp_temp` (economy) · `combat, air, carrier` · `abil, stats, vis, cargo, summon` | `econ, prod` · `combat, air, carrier` · `abil, stats, vis, cargo, summon` | `comp_temp` → kernel fields `expire_tick` + `F_TEMPORARY`; `comp_wreck` → block inside `SimCompCombat` (combat creates wrecks); class names `SimComp*` (§2.3) |
| World services | `get_entity`, `spawn_entity(def, pid, x, y) -> int`, `spawn_unit`, `spawn_raw`, `remove_entity(eid, cause)`, `remove_deferred`, `change_owner(eid, pid)`, `set_layer(eid, layer)`, `rel`, `team_of`, `emit` | `get_entity`, `spawn_entity(kind, def, owner, x, y, …) -> SimEntity`, `spawn_unit`, `remove_entity(id, reason) -> bool`, `remove_deferred`, `change_owner(id, pid, reason) -> bool`, `set_layer(e, layer)`, `rel`, `team_of`, `emit` | **Adopted** except: `spawn_entity` takes the `kind` (def indices are per kind) and returns the entity (`.id`); `spawn_raw` = `spawn_entity`; `set_layer` takes the entity (hot path; `get_entity(id)` first) |
| `kill` | combat `SimCombatSystem.kill(world, e, cause, killer_id, killer_pid)`; economy `kill_entity(ent, killer_pid, cause)` | `world.kill(e, cause, killer_id, killer_pid)` + `on_dying` hooks at stage 11 | **Merged**: one kill path; combat's `kill` is a wrapper; economy's `on_entity_died` = `on_dying`; hooks run at stage 11 (not at the call), between call and stage 11 the entity is dead and skipped |
| Death causes | combat `CAUSE_DAMAGE 0, SCUTTLE 1, EXPIRE 2, ORPHAN 3, CARGO 4, RESIGN 5`; economy `DEATH_SELF_DESTRUCT/SCUTTLE/FRIENDLY_FIRE/EXPIRE` | `SimWorld.Cause` = combat's numbers + `SCRIPT 6` | **Adopted**; `SELF_DESTRUCT` = `SCUTTLE`; friendly fire is derivable in the hook from `killer_pid` vs `e.owner` |
| Hooks | combat `on_spawn/on_remove/on_owner_changed/cleanup/hash_into(cs)`; economy `on_entity_added/died/removed/owner_changed`; abilities `on_spawn/on_remove(e, cause)/on_owner_changed/fold_checksum` | `on_spawn, on_dying, on_remove, on_owner_changed, on_player_eliminated, cleanup, hash_state(world, buf)` | **Adopted** combat's names; `hash_into(cs)` / `fold_checksum` / `checksum_into` → `hash_state(world, buf)` (append ints instead of `cs.add(v)`: one native MD5 per system — 0.34 µs vs 3.6 µs per-int FNV for a 30-int stream, ≈10×); `on_remove` order = ascending id per batch (abilities' request) |
| Named systems | `world.combat/abilities/zones/vision/production/economy/power/strategic/movement/orders` | typed members (§3.3.4) | **Adopted**; stubs make them parse from day 1 |
| Spatial hash | `SpatialHash.query_circle`, `cell_bucket`, `insert/remove(eid)` for cargo | `query_circle`, `cell_bucket`; cargo uses `set_inside` | **Adopted**; `insert/remove` stay internal so tags cannot go stale |
| RNG | `SimRng.next_int(n)` (combat) · `range_i(lo, hi)` (economy) | both | **Adopted** (v1 `below` / `range_int` renamed) |
| Math / log | `Fp.TURN`, `wrap_angle`, `angle_diff`, `mul_q16` (combat, data) · `Log.debug/info/warn/error(tag, msg)` + sink (net, data, ai) | `Fp.TURN`, `angle_norm` (= wrap_angle), `angle_diff`, `mul_q16` · `Log.*` + `sink` | **Adopted** |
| Motion | `prev_x/prev_y` "position at the end of the previous tick", `vx/vy` "this tick's displacement, written by movement" (combat) · `world.moved_prev2` (abilities) | kernel writes all of it in `set_pos` | **Kernel**: movement must use `set_pos` (once per tick per unit is optimal) and does not write `vx/vy` itself |
| Flags | `EF_TEMPORARY/DECOY/NO_SALVAGE/NO_CAPTURE/NO_REPAIR/NO_VISION_GRANT`, `F_NO_COLLISION`, `F_NO_UNIT_CAP`, `F_SCRIPTED_MOVE`, `F_NO_FOOTPRINT` (economy, abilities) · `CF_*` (combat cflags) · `UF_*` (data) | 64-bit `flags` with those bits (§4.3); `CF_*` stay in `SimCompCombat.cflags`; `UF_*` map through `SimDefs.flags_init` | **Adopted** |
| Structure occupancy | `world.struct_grid: IntGrid` stamped by economy (economy 13-6); map `occ` + `occupy / vacate` called by production / cleanup (terrain_movement.md 3.11) | one source of truth: the map's `occ`; the kernel calls `occupy` in `spawn_entity` and `vacate` in `finalize_removal`; `world.struct_at(cx, cy)` reads it; `struct_grid` and `IntGrid` are deleted | **Kernel calls, map owns** (never forgotten, id-ordered); economy / production validate placement with `MapBuildRules.check` |
| Neutral objects | economy: neutral buildings are extra `structures` defs; data: `neutrals: Array[DefNeutral]` incl. deposits; map: `neutrals` records `NK_*` whose concrete defs are STRUCTURE ids, deposits are per-cell map data | neutral buildings = STRUCTURE with owner −1 (`map.neutral_def_for_kind`); deposits are not entities; `Kind.NEUTRAL` stays for `DefNeutral` objects | **Q-7 resolved** (§12) |
| Def data | economy `world.data.res(pid)`, abilities `players[pid].layer3`, combat `pdef/presist/pmount`, ai `unit_def(def, pid)` | `SimPlayer.view: DefPlayerView` (data 3.13) | **Adopted** (data's resolution); the kernel reads only via `SimDefs` (§7.2) |
| `SimPlayerEcon` location | `world.econ_players[pid]` (economy) | `world.players[pid].econ` | economy keeps the class; `econ_players` becomes an accessor |
| Credits | `SimPlayerEcon.credits`, `spend/earn/try_spend/add` on `SimEconomySystem` | `SimPlayer.credits`, `world.add_credits/try_spend` | **Kernel**: economy's four functions delegate; `earn(…, ex, ey)` → `add_credits(…, x, y)` (emits `CASH` with a position) |
| Player fields the AI reads | `credits, power_supply, power_demand, unit_count, roster, team, alive, handicap, credits_earned_total` | all present (`alive` = `eliminated == 0`; `credits_earned_total` = `st_credits_earned`) | **Adopted** |
| Tech / power / research per player | `SimPlayerEcon` counters; v1 kernel `owned[]/powered[]/research_done[]` | removed from the kernel | **Economy** owns them (hashed in its part) |
| Stance, `t_hit/t_fire/t_disabled/…` | combat `cc.stance`, `last_hit_tick`, `last_fire_tick`, `emp_until` | removed from `SimEntity` | **Combat** owns them |
| Rules | `salvage_enabled` (combat 13-10) | not a lobby rule | combat computes it in `init_world` from the players' rosters (data trait) |

**B. Commands, orders**

| Topic | Domain spec says | This spec | Resolution |
|---|---|---|---|
| Wire form | `PackedInt32Array [type, args…]`, `SimCmd.*` static encoders, `SimCommand{type, pid, ids, args}` (net, economy, ai) | `[op, fields…, ids…]`, `SimCmd` builders, `SimCommand` with 8 named field slots | **Adopted**; the *layout* is the catalog row (economy: "only the logical field order is normative"). abilities' `x, y, a, b, c, flags` map onto `x, y, def, mode, target, flags` per row |
| Blocks | combat 40–47 · abilities 100–119 · economy 120–149 (v1 economy 100–199 overlap resolved by its own revision) · net 240–255 · movement (terrain_movement.md) commands folded into 1–12 / 41 / 47 / 105 (§6.4-F1) | same | **Adopted** |
| Names | combat `CMD_ATTACK…`, economy `CMD_BUILD_START/TRAIN/…`, ai intents | `SimCmd.ATTACK`, `BUILD_START`, `TRAIN`, … | prefix `CMD_` dropped; AI intent `RETURN_TO_BASE 28` = `RETURN_TO_BASE`, `PACK 18` = `UNDEPLOY`, `STRUCT_REPAIR 9` = `SET_STRUCT_REPAIR`, `LAUNCH_SW 30` = `LAUNCH_SUPERWEAPON`, `CAPTURE…HARVEST 24–27` = ops 7–10, `LOAD/GARRISON 21/23` = 5/6, `UNLOAD 22` = 105, `USE_ABILITY 20` = 103 (`ability_idx` = slot), `SET_MODE 19` = 102 |
| `-1` for "none" | combat / AI pass `target_id = -1` for ground / point | `target ≤ 0` = none | **Adopted** in decoder semantics (except `SET_RALLY`) |
| Removed v1 ops | `PAUSE`, `UNPAUSE`, `PLAYER_DROP`, `DEPLOY_MCV`, `PRODUCE/CANCEL_PRODUCE/HOLD_QUEUE/BUILD/CANCEL_BUILD/PLACE/RESEARCH…` | – | pause → net; drop → host-injected `RESIGN`; MCV deploy → `DEPLOY` (abilities → `T_DEPLOY_MCV`); production ops → economy's 120–131 |
| `T_RESIGN` | net `T_RESIGN = 250` `[250, reason]` | `RESIGN = 250` | **Adopted**; `NetProtocol.T_RESIGN` = `SimCmd.RESIGN` |
| Order numbers | economy `ORD_HARVEST 30 … ORD_DEPLOY_MCV 35` · combat `ORD_ATTACK 40 … ORD_FORCE_FIRE 44` | §4.7 | **Adopted**; movement 16–29, transports / abilities 50–63 |
| Handler interface | economy `on_begin/on_update/on_end(reason)` · combat `step/step_idle/on_order_start/clear_target/apply_command` | `can_issue/on_begin/on_update/on_end/on_target_lost/on_idle` + executors + `order_gate` | **Adopted** economy's names; combat maps `step → on_update`, `step_idle → on_idle`, `apply_command → executor`, `on_order_start → on_begin` of the next order, `clear_target → on_end` |
| `SimOrder` fields | economy `type, target_id`; combat `kind, target_id, count, state, tx, ty` | `type, target_id, x, y, arg, arg2, flags, phase, t0, p0, p1, fail` | **Kernel**: `count → arg`, `state → phase`, `tx,ty → p0,p1` |
| Order helpers | economy `orders.issue_internal(ent, type, target_id, x, y)`; abilities `orders.attack(eid, target)/stop(eid)` | `issue_internal(world, e, type, target_id, x, y, mode, arg)`, `clear(world, e, reason)` | **Adopted** with an explicit `world`; `attack(eid, t)` = `issue_internal(T_ATTACK, t)` |
| `DF_UNCONTROLLABLE` orders reject | abilities 13-9 | `SimSystem.order_gate` | **Kernel** mechanism, abilities supplies the predicate |

**C. Events**

| Topic | Domain spec says | This spec | Resolution |
|---|---|---|---|
| Shape | `SimEvent{type, tick, x, y, a..f}` (combat, economy 6, abilities `p0..p3, x, y`) | `[type, tick, x, y, a..f]` | **Adopted**; abilities' `p0..p3` → `a..d`; economy's `c=x, d=y` fields move to `x,y` |
| Blocks | combat 200–229 · abilities 230–259 · economy 300–499 | same | **Adopted**; core 1–99 |
| Duplicates folded into core | abilities `EV_CMD_REJECTED 253`, economy `EVT_CMD_REJECTED 300`, `EVT_ORDER_FAILED 319`, `EVT_CREDITS_GAINED 308` | core `CMD_REJECTED 5`, `ORDER_FAILED 6`, `CASH 4` | domain `RSN_*` / reason codes travel in `d` |
| Overlaps between domains for the reconciler | `EV_SALVAGE_DONE 251` (abilities) vs `EVT_SALVAGE_PAID 328`; `EV_CAPTURE_DONE 252` vs `EVT_STRUCTURE_CAPTURED 326`; `EV_ATTACK_ALERT 214` (combat) vs `EVT_COLLECTOR_ATTACKED 320`; `EV_SUMMONED 248`/`EVT_SUMMON_EXPIRED 410`/`EV_SUMMON_EXPIRED 249`; `EV_DEATH 208` vs `EVT_STRUCTURE_SOLD 314` | – | not kernel decisions; suggested survivors: combat's alert, one salvage / capture event from the channel owner, combat's `EV_DEATH` |
| Fog-gated delivery | abilities per-group `EV_VIS_CHANGED` with client mask | kernel has no mask | vision emits per group; view / audio filter by `x,y` and the local fog |

**D. Net, data, replay**

| Topic | Domain spec says | This spec | Resolution |
|---|---|---|---|
| Adapter surface | `submit_raw`, `step`, `checksum_at`, `checksum_parts_at`, `CHECKSUM_PART_NAMES`, `dump_state() -> String`, `is_match_over`, `match_result`, `is_player_active`, `map_hash`, `clear_events` (net 3.3) | all present (`CHECKSUM_PART_NAMES` is a `SimWorld` constant; the 16 names are fixed by the pipeline table) | **Adopted** |
| Pause | net-level (`CK_PAUSE`, budgets, not recorded) | none in the sim | **Adopted**; v1 `PAUSE/UNPAUSE`, `step_no`, `pauses_used`, `paused_*` deleted |
| Replay | net.md 4.8 `*.mfreplay`, `NetReplay` | `SimCommandLog` (tests) only | **Adopted**; v1 `SimReplay` deleted |
| MatchConfig | net.md 7.1 schema of record, `MatchConfig.from_dict`, `SimWorld.create(cfg)` | `SimMatchConfig.from_dict`, `SimWorld.create(data, cfg, map, opts)` | **Adopted**; class prefix `Sim*` (lint L004); pids may be non-contiguous |
| Handicap | net XR-9: start credits + income scaled, stored, checksummed | `SimPlayer.handicap`, `income_frac`, §3.4.7 | **Adopted** |
| `SimWorld._init(data, cfg)` | data CMR-4 | `_init(data, cfg, map, opts)` | map is a third argument (the map module builds it first) |
| `Checksum.seed(with)` | data CMR-2 | data hash enters through the `world` part | no separate entry point; FNV params equal `DefHash` |
| Unit tests | `func test_*(t: TestCtx)` (qa) vs `func run(t)` (ARCH §11) | `test_*` | **Adopted** (net XR-20e) |
| Sim lints | qa L001–L010 | + SL-5…SL-10 (§8.3; QA's numbering) | implemented by QA |

**E. Not adopted, with reasons.** (1) *Immediate kill hooks* (economy 3.9 "kill path sets the dead flag, then economy.on_entity_died"): hooks run at stage 11 so that all deaths of a tick are processed in one deterministic, id-ordered pass with consistent lists; nothing in the other specs needs them earlier because every system already skips dead entities. (2) *`SimEvent` objects / one `SimCommand` object per network command*: one object per event / per command per tick; the int forms need no allocation and are what net records and hashes. (3) *`Dictionary`-based `args` for commands*: layouts are static rows of one table, validated once. (4) *A kernel-owned wreck policy* (v1) and *`comp_wreck`*: combat owns the death path; the kernel offers `spawn_wreck`, `expire_tick`, `remove_deferred`. (5) *Per-domain stat tables in the kernel* (v1 `DefStats`): data's `DefPlayerView` is the single source.

**F. Specs published while v2.0 was being finished: `terrain_movement` (map **and** movement), `qa`, `audio`, `render`.** They were written against the v1 kernel spec (terrain_movement against its `ASSUMPTION(sim_core)` proposals). Each row is a decision: **Adopted** = the kernel changed in v2.1 (prototype and tests updated); **Consumer adapts** = the other spec should be edited by its owner or the reconcilers. Names not listed here were already identical.

**F1. terrain_movement (map + movement)**

| Topic | terrain_movement says | This spec | Resolution |
|---|---|---|---|
| Layering of footprints | TM 13-9 (asked of data): `GameData.footprint(idx) -> MapFootprint`, `GameData.terrain: MapTerrain` | `src/data` may not mention `Map*` identifiers (lint **L005**, `core <- data <- map <- sim`; the first prototype variant failed exactly there) | **Map owns the def → footprint table**: `MapData.footprint_of(kind, def_idx)`; `GameData` keeps only the footprint id string. Same for `terrain`. Reconcilers amend TM 13-9 |
| Map handles the kernel uses | `clone_fresh()`, `map_hash()`, `checksum_dynamic()`, `spawns` (stride 6), `neutrals` (stride 8), `occupy / vacate / occupant_at`, `nav_version` | exactly those (§3.4.1, §7.2b) | **Adopted**; v2.0's guesses (`clone_for_world`, `content_hash`, `hash_state`, `start_cells`, `initial_entities`) are gone |
| Who calls `occupy` / `vacate` | production before its spawn; cleanup on destruction (TM 3.11, 13-15) | the kernel: `spawn_entity` and `finalize_removal` (§5.4 "Footprints") | **Kernel** (one place, never forgotten, id-ordered); production calls `MapBuildRules.check`, `SimDockMove.units_in_footprint / evict`, then `spawn_structure(…, facing = 1024·orient)`; `F_NO_FOOTPRINT` opts out. TM's `EV_NAV_CHANGED` = core event **9** |
| `struct_grid` (economy 13-6) | kernel-stamped grid | removed; `world.struct_at(cx, cy)` = `map.occupant_at` | **Adopted** (economy's overlap test = `MapBuildRules.check`) |
| Checksum | `SimMovementSystem.checksum(cs)` folds `map.checksum_dynamic()` first; `Checksum.add_int / add_ints / add_bytes / fnv1a_bytes` (13-12) | the `map` part *is* `map.checksum_dynamic()` (§8.2); every system appends ints in `hash_state(world, buf)` | movement does **not** repeat the map hash; domains do not need a `Checksum` accumulator (its `add / add64 / add_packed / value()` and static `fnv_bytes` exist for tools and tests): appending ints to `buf` costs one MD5 per system, ≈ 10× cheaper than per-int FNV |
| `world.movers` | ascending list of entities with a `SimCompMove` | not provided | movement keeps a private list: append in `on_spawn` (ids ascend), compact in its `cleanup(world)` hook (runs before the kernel compaction) |
| `world.entity(id)` | v1 name | `get_entity(id)` (combat, economy, abilities use it) | consumer adapts |
| `world.set_order(e, kind, x, y, target, flags, aux, append)` | 13-2 | `world.orders.issue_internal(world, e, type, target_id, x, y, mode, arg)`; `aux = group_id` → `arg`; `append` → `mode = QM_APPEND`; flags → `OF_*` | semantics adopted; the formation slot is passed as `x, y` |
| Order handler API | static `SimMoveOrders.begin / update / end` with `OS_*`, `OE_*` | `SimOrderHandler.on_begin / on_update / on_end(reason)`; `OS_RUNNING / DONE / FAILED` = `SimOrder.RUNNING / DONE / FAILED`; `OE_DONE / CANCELLED / REPLACED / DEAD` = `END_DONE / CANCELLED / REPLACED / DIED` (+ `END_FAILED`) | a thin handler object per order type over the static functions |
| `SimOrder.kind`, `SimWorld.setup` | TM 13-2, 3.12 | `SimOrder.type`; `SimWorld.create(data, cfg, map, opts)` (validating) / `SimWorld.new` builds the world: map clone, `init_world` of every stage, initial entities | consumer adapts |
| Order numbers | `ORD_MOVE 1 … ORD_RETURN_BASE 8` | `T_MOVE 16 · T_PATROL 17 · T_FOLLOW 18`; `T_ATTACK_MOVE 41`, `T_RETURN_BASE 45` (combat); `T_LOAD 50 · T_UNLOAD 51 · T_GARRISON 52` (= `ORD_ENTER` / `ORD_UNLOAD`); `SCATTER` issues `T_MOVE` | **Adopted** (renumbered, names and semantics are TM's) |
| Commands | `CMD_MOVE … CMD_RETURN_BASE` at 0x40–0x48 | `MOVE 1 · STOP 2 · SCATTER 3 · PATROL 4 · LOAD 5 / GARRISON 6 (= ENTER) · ATTACK_MOVE 41 · RETURN_TO_BASE 47 · UNLOAD 105 (abilities)` and **new `FOLLOW 12`**; TM `F_QUEUE` = `mode = QM_APPEND`; `F_NO_SLOT / F_SPEED_MATCH / F_REVERSE` = `flags` b0 / b1 / b2 of `MOVE`, `ATTACK_MOVE`, `PATROL`; `CMD_RETURN_BASE.target` = `RETURN_TO_BASE.target` (0 = nearest); `CMD_UNLOAD x = y = −1, F_ALL` → abilities' `UNLOAD mode 0 = all` | **Adopted**; TM's 0x40–0x4F block is not used |
| Events | `EV_MOVE_FAILED 0x40 … EV_NAV_CHANGED 0x49`; `world.emit(kind, a, b, c, x, y)` | block **100–129 = movement**: `EV_MOVE_FAILED 100 · EV_MEDIUM_CHANGED 101 · EV_AIR_TAKEOFF 102 · EV_AIR_LANDED 103 · EV_BOARDED 104 · EV_UNBOARDED 105 · EV_DOCKED 106 · EV_UNDOCKED 107 · EV_STUCK 108` (payloads as TM 6.3, `x, y` in the header); `EV_NAV_CHANGED` = core 9; call shape `emit(type, x, y, a, b, c…)` | **Adopted**. Overlaps for the reconcilers: 104 / 105 ≈ abilities 240 / 241, 102 / 103 ≈ combat 215 |
| Cargo API | `world.cargo_can_load / add / remove / list / count`, boarding time modifiers (13-4) | cargo belongs to abilities (`SimCompCargo`, `SimTransport`); the kernel provides `set_inside`, `container_id`, `F_INSIDE`, `on_dying` | consumer adapts: call abilities' functions; there is no `world.cargo_*` |
| `world.are_allied(a, b)`, `players[pid].is_ai` | 13-7 | `are_allied` added (§3.4.4); `is_ai` = `players[pid].controller == SimPlayer.Controller.AI` | **Adopted** / consumer adapts |
| Spatial hash | expose `head / next / cell_shift`; `world.unit_hash` rebuilt after movement | one `SpatialHash`, updated incrementally by `set_pos` (always current), queries `query_circle / rect / cell_bucket` | movement keeps private separation grids (TM R11 allows it) |
| Entity slots | `move`, `pads`, `dock` | `move` (plus `air`, `carrier`, …); `SimCompPads` / `SimCompDock` nest inside `SimCompMove` or the structure's `prod` slot — the owners' choice (§4.5 rule 1) | policy |
| Neutral kinds `NK_*` | concrete `DefStructure` ids named in `map_gen.json` | `map.neutral_def_for_kind(nk)` → STRUCTURE def index or −1 (`NK_SCENERY`, no entity); spawned at world creation with owner −1 | **Adopted** |
| Deposits | per-cell `MapData.deposit`, `harvest`, `nearest_deposit`, `fields` | not entities; `HARVEST target = 0` + a cell `x, y` of the field; `SET_RALLY target = −(field id)` | economy adapts (render R24 lists the three deposit models); the kernel is neutral |
| Start positions | `spawns[k]` (slot = image index), `fair_slot_order(n)` | `players[].start` = slot index; the spawn cell is the centre cell of the 3×3 start footprint (`ASSUMPTION(map)`, TM V9 must hold for that anchor) | **Adopted**; lobby / net choose slots |
| Facing | `entity.facing` binary angle 0..4095, 0 = +x toward +y | identical (§4.2) | same |
| `Fp` | `sin / cos / atan2 / isqrt / dist / floor_div / floor_mod / cell_of` (13-11) | all present with those names and conventions | same |

**F2. qa and qa_tooling (the `QaSimAdapter` symbols)**

| QA symbol / request | This spec |
|---|---|
| `world.apply_turn(cmds)`, `step_no`, pause | net's turn loop is `for c in cmds: submit_raw(pid, ints)` then `step()` ×2; there is no sim pause and no second counter — `tick` is the only clock |
| `report_at(tick).sections` (dictionary) | `report_at(t).parts` (16 ints) zipped with `CHECKSUM_PART_NAMES` (`world, rng, players, entities, map, sys.commands … sys.cleanup`; no `<name>.<stage>` double suffix) |
| `checksum_log` pairs, `checksum_at`, `dump_state` | identical |
| lists `world.zones`, `world.deposits` (lint SL-10) | `zone_ents`, `neutrals`; there is no deposits list |
| `SimCommand.schema_of / is_known / allowed_when_paused / system_only / all_ops / op_name / field_range` | `SimCmd.layout_of / is_known / meta_of / name_of / all_ops` (added); no pause, so no `allowed_when_paused`; `system_only` = ops the lobby never emits (`DEBUG` needs `allow_debug`; `RESIGN` is host-injected for departed players); `field_range` is not provided (QA falls back to boundary values) |
| `SimReplay` "MFRP" | net's `NetReplay`; `SimCommandLog` for tests |
| `SimConfig.CHECKSUM_INTERVAL`, `SimTestKit.diff_snapshots(a, b)`, `SimTestKit.random_script(...)` | `SimConfig.CHECKSUM_PERIOD` (20); `SimTestKit.diff_dumps(a, b)` (snapshots are `dump_state()` texts); no `random_script` — QA composes scripts from `random_step`, `s_core_1` and the public API |
| `QaCorrupt` targets `next_proj_id`, rng draws, `players[0].credits`, entity `hp` | all public fields, one per checksum part; `test_sim_determinism` proves each moves exactly its part |
| `QaTimedSystem` decorating `world.stages[stage_no − 1]` | supported for stages 2–11 through `opts.systems`; stage 1 is called directly by `step()` |
| QA-XR-15 `SimInvariants.check` ≤ 2 ms at 1,900 entities; no RefCounted cycles | **measured 4.1 ms** at 1,888 entities on a 96×96 map (M5 Max; 0.5 ms of it the O(cells) occupancy scan) — not met, accepted: QA calls it every 100 ticks (0.04 ms per tick amortised). **No cycles**: `test_sim_free` (a world with two armies, a wreck and a resign is freed when its last reference drops; a negative control that stores the world inside a system does leak) |
| QA-XR-16 `opts.profile`, `system_usec` | **declined**: sim code has no clock (DR-3, lint L003); `QaTimedSystem` through `opts.systems` is the supported way |
| QA-XR-17 `DEBUG` `MODE, TARGET, DEF, COUNT, X, Y` and modes 3–6 | **Adopted** (§6.1 row 99): the kernel does 1–3; ≥ 4 go to `SimSystem.on_debug` of the owning stage |
| QA-XR-19 catalog helpers | `all_ops()` and `name_of()`; `field_range` not provided |
| QA-XR-21 `SIM_VERSION`, goldens, `SimTestKit` path | `SimConfig.SIM_VERSION = 1`, bumped for every result-changing change; goldens in `game/tests/golden/sim_core.json`; `SimTestKit` lives in `game/tests/support/` and takes the fixture path as a parameter (no `res://tests` string in `src/`, lint L005) |
| QA-XR-23 `Log.sink` | present |
| R30: catalogs disagree | **resolved in one place**: §6.1 / §6.2 are the only registry, and their numbers are the domains' blocks, so nothing of the domain specs has to be "removed or mapped"; only v1's ad-hoc master codes disappear (translation table F3); net's adapter surface is §3.4.8 |
| `MatchConfig` keys `fog_mode`, `start_mode`, `allow_debug` | rules of §4.11: net's eight lobby keys (`fog` 0/1 replaces v1's `fog_mode`) plus the kernel-only `start_mode`, `neutral_structures`, `victory`, `end_when_no_humans`, `allow_debug` |

**F3. render and audio: read surface and event translation**

| v1 name used by render / audio | This spec |
|---|---|
| `sim.entity(id)` | `get_entity(id)` |
| `SimEntity.max_hp / holder / expires` | `hp_max / container_id / expire_tick` |
| `SimEntity.t_hit, t_fire, t_disabled, t_shutdown, t_suppressed` | combat's `SimCompCombat` (`last_hit_tick`, `last_fire_tick`, EMP and suppression timers); the view reads `e.combat` |
| `sim.paused`, `rules.speed_pct` | net session state, not sim state |
| `sim.query_radius(x, y, r, out, need, avoid)` | `query_circle(...)`, same arguments |
| `sim.relation(a, b)`, `sim.team_of(pid)` | `rel(a, b)` (`SELF / ALLY / ENEMY / NEUTRAL`), `team_of(owner)` |
| `sim.entity_visible(pid, e)`, `sim.cell_visible(pid, cx, cy)` | present as world wrappers over `world.fog` (+ `cell_explored`) |
| `fog.fog_bytes / fog_version / ghosts / ghost_version / decoy_identified` | all in `SimFogApi` (vision overrides; defaults are empty / 0 / false) |
| `sim.projectiles` (combat.md 2 calls `world.projectiles` an alias of `world.combat.projectiles`) | read `world.combat.projectiles` (combat.md 4.4); **declined as a kernel member**: an alias would tie the kernel to combat's `SimProjectiles` type; the kernel only allocates serial ids (`alloc_proj_id`) |
| `players[pid].sw_state / sw_x / sw_y / sw_angle / sw_warn_until`, `power_state` | economy's `SimPlayerEcon` (`players[pid].econ`); `power_supply` / `power_demand` mirrors are kernel fields (`LOW` ⇔ supply < demand) |
| `rules.fog_mode`, `rules.wrecks` | `rules.fog`; wrecks are combat's |
| `world.events.watch_mask` | withdrawn: no fog-gated delivery in the kernel; audio filters by `x, y` with `world.cell_visible` |
| `view.capture_prev` hook | not needed: `prev_x / prev_y / vx / vy` are kernel state (§3.4.6) |
| structure orientation (render request 2) | `spawn_structure(…, facing = 1024·orient)`; `SPAWNED.e` carries it |
| `SPAWNED` first, `DIED` before `REMOVED` (render request 1) | `SPAWNED` first (guaranteed); no `DIED`: combat's `EV_DEATH` (208), then `REMOVED` |
| `SimEvent` constants by name (audio 13-4) | `SimEvent.<NAME>` for the core codes, each domain's own class for its block |

Translation of v1's master event codes (still spelled by render, audio and qa) to the events that exist now:

| v1 code | v2.1 event(s) |
|---|---|
| 0x01 `SPAWNED` · 0x02 `REMOVED` · 0x04 `OWNER_CHANGED` | core 1 · 2 · 3 (`x, y` moved to the header; payload `a..f` as §6.2) |
| 0x03 `DIED` | combat 208 `EV_DEATH` (+ 219 `EV_CRASH`, 209 `EV_WRECK_ADD`); silent summon expiry: economy 410 / abilities 249 |
| 0x05 `STATE` | combat 212 `EV_SUPPRESS`, 213 `EV_EMP`, 215 `EV_AIR_STATE`, 220 `EV_WEAPON_LOCK`; abilities 234 / 235 `EV_MODE_STARTED / CHANGED` (deploy, pack, mode switch), 230 `EV_CLOAK_CHANGED`; economy 304 `STRUCTURE_ACTIVE`, 315 `STRUCTURE_SELLING`, 316 `REPAIR_STATE`, 317 / 318 `HQ_DEPLOYED / UNDEPLOYED`; powered = flag `F_POWERED` + 311 / 312 |
| 0x06 / 0x07 `LOADED` / `UNLOADED` | abilities 240 / 241 (movement 104 / 105 overlap) |
| 0x10 `DAMAGE` · 0x11 `WEAPON_FIRED` | combat 204 `EV_HIT` (coalesced per victim per tick) · 200 `EV_FIRE` (owner: read it from the shooter) |
| 0x12 / 0x13 `PROJECTILE_LAUNCHED / IMPACT` · 0x14 `EXPLOSION` | combat 201 `EV_PROJ_SPAWN` / 202 `EV_PROJ_END` + 203 `EV_IMPACT` · warheads: 203; superweapon shells: economy 408 |
| 0x15 `BEAM` · 0x16 `INTERCEPT` · 0x17 `HEAL` | combat 205 / 206 · 211 · abilities 254 `EV_REPAIR_PULSE` |
| 0x19 `SALVAGE` | economy 327 / 328, abilities 251 |
| 0x20 `CASH` · 0x21 `HARVEST_DELIVERED` | core 4 `CASH` (reason `HARVEST`; `source_id` = the delivering collector or its refinery — economy's choice) |
| 0x22 / 0x23 `POWER_LOW / RESTORED` | economy 311 / 312 |
| 0x24 `BUILD_STARTED` · 0x27 `BUILD_CANCELLED` · 0x28 `QUEUE_BLOCKED` · 0x29 `RESEARCH_STARTED` | economy 306 `EVT_QUEUE_STATE` (+ 309 `INSUFFICIENT_FUNDS`, 310 `UNIT_CAP_REACHED`) |
| 0x25 `BUILD_READY` · 0x26 `PRODUCTION_COMPLETE` · 0x2A `RESEARCH_COMPLETE` · 0x2F `UNIT_CAP_REACHED` | economy 302 · 305 · 307 · 310 |
| 0x2B / 0x2C `TECH_UNLOCKED / LOST` · 0x2D `BUILD_PROGRESS` | none: poll `SimPlayerEcon` (tech counters, queue progress) |
| 0x30 `POWER_USED` · 0x31 `POWER_READY` | economy 402 · 401 (+ 400 `POWER_UNLOCKED`) |
| 0x32 `SW_CHARGING` · 0x33 `SW_READY` | poll · economy 405 |
| 0x34 `SW_WARNING` (never fog-gated) | economy 404 `EVT_WARNING` (+ abilities 250 `EV_SCAN_WARNING`) |
| 0x35 / 0x36 / 0x37 `SW_LAUNCHED / CANCELLED / IMPACT` | economy 407 / 406 / 408 |
| 0x40 `ABILITY` · 0x42 `REVEAL_AREA` | abilities 236 `ABILITY_USED`, 237 `ABILITY_READY`, 238 / 239 `FX_APPLIED / REMOVED`, 259 `BUFF_APPLIED` · none |
| 0x50 / 0x51 `REVEALED / HIDDEN` | abilities 231 `EV_VIS_CHANGED` (per vision group) |
| 0x52 / 0x53 / 0x54 `*_UNDER_ATTACK` | combat 214 `EV_ATTACK_ALERT` (class in `d`: unit / structure / collector / aircraft), economy 320 `COLLECTOR_ATTACKED` |
| 0x60 `ORDER_FAILED` · 0x61 `CMD_REJECTED` · 0x70 `PLAYER_ELIMINATED` · 0x71 `MATCH_END` | core 6 · 5 · 7 · 8 |
| 0x72 / 0x73 `PAUSED / UNPAUSED` · 0x74 `CHECKPOINT` | none in the sim: net's session state · `checksum_at(t)` |

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

### 7.1 Sim test fixture — `game/tests/fixtures/sim_core_fixture.json` (consumed by `SimTestKit`)
Purpose: tiny, stable defs so core tests never depend on the bible or balance layer. `ASSUMPTION(data)`: `GameData.for_test(d: Dictionary) -> GameData` (also requested by combat and abilities) builds real `DefUnit / DefStructure / DefZone / DefNeutral / DefRoster` from it; **per-kind def indices are assigned in sorted-id order**, and the `fx.<k>N_` prefixes make sorted order = listed order. `ASSUMPTION(map)`: `MapData.for_test(w, h, spawn_cells, neutral_records, map_hash)` plus `set_footprint(kind, def_idx, fp)` and `set_neutral_def(nk, def_idx)` (the footprint table and the neutral-kind table are the map's data, `footprints.json` / `map_gen.json`).
```json
{
  "version": 1,
  "data_hash": 305441741,
  "units": [
    { "id": "fx.u0_mcv",   "health": 400, "cost": 3000, "pop": 0, "radius": 256, "abilities": ["deploy_structure"] },
    { "id": "fx.u1_rifle", "health": 100, "cost": 200,  "pop": 1, "radius": 256 },
    { "id": "fx.u2_tank",  "health": 300, "cost": 800,  "pop": 1, "radius": 256 },
    { "id": "fx.u3_drone", "health": 1,   "cost": 0,    "pop": 0, "radius": 256 }
  ],
  "structures": [
    { "id": "fx.s0_hq",       "health": 1000, "cost": 0,   "radius": 1536 },
    { "id": "fx.s1_barracks", "health": 500,  "cost": 500, "radius": 1024 },
    { "id": "fx.s2_dock",     "health": 800,  "cost": 900, "radius": 1536 },
    { "id": "fx.s3_garrison", "health": 400,  "cost": 0,   "radius": 1024 }
  ],
  "zones":    [ { "id": "fx.z0_smoke", "hp": 0, "radius": 3072 } ],
  "neutrals": [ { "id": "fx.n0_deposit", "health": 0 }, { "id": "fx.n1_garrison", "health": 400 } ],
  "rosters": [ "roster.fx.a", "roster.fx.b", "roster.fx.c", "roster.fx.d", "roster.fx.e", "roster.fx.f", "roster.fx.g", "roster.fx.h" ],
  "roster_hq": "fx.s0_hq", "roster_mcv": "fx.u0_mcv",
  "map": { "w": 96, "h": 96, "map_hash": 1450766081,
           "spawn_cells": [[20,20],[70,70],[20,70],[70,20],[45,10],[45,80],[10,45],[80,45]],
           "footprints": [ { "kind": "structure", "def": "fx.s0_hq",       "w": 3, "h": 3 },
                           { "kind": "structure", "def": "fx.s1_barracks", "w": 2, "h": 2 },
                           { "kind": "structure", "def": "fx.s2_dock",     "w": 3, "h": 2, "rotatable": true },
                           { "kind": "structure", "def": "fx.s3_garrison", "w": 2, "h": 2 },
                           { "kind": "neutral",   "def": "fx.n1_garrison", "w": 2, "h": 2 } ],
           "neutral_kinds": { "garrison": "fx.s3_garrison" } }
}
```
`data_hash` = 0x1234ABCD and the map `map_hash` = 0x5678EF01 are **pinned** (not recomputed) so the S-CORE-1 golden does not depend on the data/map hashers. Fixture rosters have no research, powers or superweapon; every roster starts with `hq_idx = 0, mcv_idx = 0`; `spawn_cells` name the spawn cell = the centre cell of the start footprint (HQ spawned at `cell·1024 + 512`); the dock is the only rotatable footprint; the tests that need neutral records pass them to `make_map(neutral_records)`. The research stub of the prototype (`DefPlayerView.apply_research(i)` = +10 % × (i+1) health) stands for `DefPlayerView`'s real behaviour in `test_sim_api`.

### 7.2 Data fields the kernel reads — the complete list behind `SimDefs`
`ASSUMPTION(data)`; everything else in a `Def*` is invisible to the kernel. Paths are data_balance.md 3–4.

| `SimDefs` method | Data member | Notes |
|---|---|---|
| construction | `GameData.units: Array[DefUnit]`, `.structures`, `.zones`, `.neutrals`, `.rosters: Array[DefRoster]`, `.roster_idx(id: String) -> int`, `.data_hash() -> int` | per-kind dense indices (sorted-id order) |
| `hp_max(view, kind, def)` | `DefPlayerView.resolved_stats(DefEnums.Kind, def_idx)[DefEnums.Stat.HEALTH]` (= 2) for a player; base `DefUnit.health / DefStructure.health / DefZone.hp / DefNeutral.health` for neutral owners | "static + permanent research" value (data 3.13) |
| `radius` | `DefUnit.radius`, `DefStructure.radius`, `DefZone.radius`, `DefNeutral.radius` | units |
| `home_layer` | `DefUnit.home_layer` (`DefEnums.Layer`, same numbering as `SimEntity.Layer`) | non-units: GROUND |
| `cap_weight` | `DefUnit.pop` | 0 = exempt |
| `flags_init` | `DefUnit.flags`: `UF_NON_BLOCKING` (128) → `F_NO_COLLISION`, `UF_NO_REPAIR` (16), `UF_NO_CAPTURE` (32), `UF_NO_SALVAGE` (64) | zones: `F_UNTARGETABLE \| F_NO_SELECT` |
| `is_rebuilder` | `DefUnit.ability_mask` bit `AbilityKind.DEPLOY_STRUCTURE` (23) | built once into a byte table |
| players | `DefRoster.hq_idx`, `DefRoster.mcv_idx` (**requested**, not in data 3.6 today; fallback: first `structures` def with `SF_NO_BUILD` and its `deploy_unit`), `DefPlayerView.new(data, roster)`, `.checksum()` | start entities; per-player view |

Nothing else is read: the kernel never touches weapons, abilities, costs, tiers, prerequisites, powers, research or **footprints** (the map's, §7.2b).

### 7.2b Map members the kernel reads or calls — `ASSUMPTION(map)`, terrain_movement.md 3.3 / 3.6 / 4.1

| Member | Use in the kernel |
|---|---|
| `w`, `h` | world bounds (`_max_x = w·1024 − 1`), spatial hash size, `M_POS` / `M_CELL` command bounds |
| `spawns: PackedInt32Array` (stride `SPAWN_STRIDE = 6`: `[slot, cell, facing, orbit, team_hint, reserved]`) | start positions: record `players[].start`; `facing` for an MCV start; `spawns.size() / 6` = slot count for `SimMatchConfig.validate` |
| `neutrals: PackedInt32Array` (stride `NEUTRAL_STRIDE = 8`: `[kind, cell index (top-left), w, h, variant, flags, orbit, reserved]`; cell index = `cy·w + cx`) | initial neutral STRUCTUREs (kernel skips kinds whose def is −1) |
| `neutral_def_for_kind(nk) -> int` | **requested**: STRUCTURE def index of a neutral kind, −1 for scenery (TM 13-9's request to data, moved to the map; it resolves `map_gen.json` ids through `GameData`'s structure id → index lookup) |
| `footprint_of(kind, def_idx) -> MapFootprint` | **requested**: the def's footprint or null. The kernel reads only `.rotatable` and `.size_oriented(orient)` (packed `w << 8 \| h` after rotation) |
| `clone_fresh() -> MapData` | called once in `SimWorld._init`; static arrays shared, dynamic layers fresh — two worlds side by side stay independent |
| `map_hash() -> int` | `SimWorld.map_hash()`, `world` checksum part, lobby handshake |
| `checksum_dynamic() -> int` | the whole `map` checksum part (deposits, occupancy, patches, `nav_version`) |
| `occupy(sid, fp, cx, cy, orient) -> int` / `vacate(sid) -> int` | footprint lifecycle (packed changed bbox returned → `NAV_CHANGED.a`) |
| `occupant_at(cell_index) -> int`, `idx(cx, cy)`, `in_bounds(cx, cy)`, `occ` (read-only array), `nav_version` | `struct_at`, INV-16, `NAV_CHANGED.b`, `dump_state` |

`MapBuildRules.check`, `MapFootprint` rotation helpers, nav, deposits, patches and the generator are never called by the kernel.

### 7.3 Match configuration JSON (net.md 7.1; the sim reads the marked keys)
```json
{"map":{"family":0,"layout_players":4,"params":{},"seed":20240517,"size":128},
 "players":[{"color":1,"handicap":100,"kind":"human","name":"X42553","peer":1,"pid":0,"roster":"roster.fx.a","start":0,"team":1},
            {"color":4,"handicap":100,"kind":"human","name":"Mia","peer":2,"pid":1,"roster":"roster.fx.b","start":1,"team":1},
            {"ai":{"flags":0,"level":2,"style":0},"color":0,"handicap":120,"kind":"ai","name":"AI 3","peer":0,"pid":5,"roster":"roster.fx.c","start":2,"team":10}],
 "rules":{"fog":true,"shared_vision":false,"start_credits":7500,"superweapons":true,"unit_cap":150,"veterancy":false,"vision_budget":128,"vision_stride":2},
 "seed":3141592653}
```
(plus `format`, `match_id`, `created_unix`, `versions{…}`, `net{…}` — ignored by the sim). Keys are emitted sorted by net (`JSON.stringify(cfg, "", true)`). The example (non-contiguous pids 0, 1, 5; a 120 % AI) is a test: it validates against the fixture, builds a 6-player world with vacant pids 2–4 (pre-eliminated), start credits `[7500, 7500, –, –, –, 9000]`, three HQs; `config_hash = 3200203660`.

### 7.4 Replay
The `*.mfreplay` file and its JSON header are net.md 4.8 / 7.4 (they embed the canonical `MatchConfig` JSON above). The kernel adds no file format; `SimCommandLog.to_ints()` is the flat form used by tests: `[n, (tick, pid, len, ints…) × n]`.

### 7.5 Golden file — `game/tests/golden/sim_core.json`
```json
{ "sim_version": 1,
  "fp":   { "sin_digest": 2046802713, "atan_digest": 1306073121, "muldiv_digest": 1403213809, "isqrt_digest": 853641712, "trig_digest": 3886527727 },
  "commands": { "move": [1,5000,7168,0,0,12,15,16,40], "attack": [40,777,1,0,301,305], "train": [124,55,17,3], "place": [123,9,12,20,0], "use_power": [140,1,90000,131072,1024,0], "resign": [250,0] },
  "config_hash": { "fixture_2p": 856134193, "net_example": 3200203660 },
  "s_core_1": { "checksum_tick0": 4077726312,
                "chain": { "20": 2467641772, "40": 1177079746, "60": 828122293, "80": 3138515439, "100": 2720863688 },
                "final_checksum": 4082083667, "events_digest": 3987817499, "events": 26, "end_tick": 100, "winner_team": 1,
                "parts_tick100": { "world": 3428337259, "rng": 2740417745, "players": 2789405313, "entities": 1983726783, "map": 533770084, "sys.combat": 3722655248, "other stages": 3649838548 } },
  "xplat_sim_core": { "0": "1ee03a26", "20": "aa8ab36d", "40": "101c1796", "600": "c9c9f1fb", "1180": "4524bc6a", "1200": "2e2cfc5c" } }
```
Regenerated by `SimTestKit` only with a `SIM_VERSION` bump or an intentional hash-layout change; CI compares it on macOS **and** the Debian containers (amd64 and arm64). `xplat_sim_core` is the `HASH tick=N hex` chain printed by `game/tests/scenarios/xplat_sim_core.gd` (3-player chaos game, `--ticks=1200`, 61 lines) for `tools/py/xplat_determinism.py`.

### 7.6 Generated table file — `game/src/core/fp_tables.gd`
Emitted by `tools/py/gen_fp_tables.py` (§5.1). Header comment `## GENERATED … DO NOT EDIT`; two `const … : PackedInt32Array = [ … ]`. The tool also prints the digests to paste into `Fp.TABLE_DIGEST_*`.

### 7.7 Project settings the kernel requires (owner: app/tooling)
`project.godot` `[debug]`: `gdscript/warnings/integer_division=0` (the sim deliberately uses truncating `/`; **already set** by the toolsmith), `untyped_declaration=1` (all kernel code is typed), `unsafe_*=0`. If the checker reports `shadowed_global_identifier` for `Fp.sin/cos/atan2/clamp` (names fixed by ARCH), silence per function with `@warning_ignore("shadowed_global_identifier")` (the prototype's `Fp` needed none).

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

### 8.1 DR-1 … DR-15 compliance

| Rule | How the kernel complies / where it is enforced |
|---|---|
| DR-1 ints only | Every sim field is `int` / packed int array. The floats in `core/` are the `isqrt` estimate (corrected to exactness) and `Fp.milli(f: float)` (load-time), both `lint-allow`ed; `SimMatchConfig` contains no float handling (`is_int_only` rejects). `bool` never persists. `String`s (`name`, roster ids) are labels excluded from the checksum. Lint L003 |
| DR-2 no engine RNG | One `SimRng` per world; the only kernel draw is `SCATTER`; L003 |
| DR-3 no time | Only `world.tick`; `Log` uses no clock; L003 (`delta`, `Time.*`) |
| DR-4 only `Fp` trig/isqrt | tables + integer algorithms; unqualified `sin(` etc. flagged (L003); `self_test()` |
| DR-5 division semantics | `Fp.floor_div/floor_mod/ceil_div`; `mul32` for 32-bit products; no shift of negative **constants**; magnitudes < 2^62 documented per function |
| DR-6 iteration order | lists ascending id; `by_id` array; relation table array; parts are appended in a fixed order; no Dictionary in entity/player/component state (SL-6) |
| DR-7 total orders | `SimCommandSystem._cmp` = `(pid, _ord)`; cleanup batches sort a packed int64 key `(id << 16) \| index`; spatial results are sorted ints; no other `sort_custom` in the kernel (SL-9) |
| DR-8 no Node/async | `HashingContext` (RefCounted) is the only engine object used besides `PackedByteArray`/`JSON`; single-threaded synchronous code |
| DR-9 no hidden global state | statics are immutable tables (`FpTables`, `SimCmd` layout table) or diagnostics (`Log.ring`, `Checksum._hc` scratch reset per call). Checksum scratch buffer and query buffers are **instance** fields of `SimWorld` |
| DR-10 float data once | `Fp.milli` + integer converters (data has its own `DefNumParse`, same rounding); converted tables hashed by `data_hash` |
| DR-11 bounded work | orders ≤ 32, ids ≤ 512, ints ≤ 1024, cleanup rounds ≤ 16, defeat cascade ≤ 6/tick, events soft cap; no elapsed-time loops |
| DR-12 events output-only | nothing in the kernel reads events; emission sequence is itself tested; enabling / disabling events never changes the chain |
| DR-13 checksum coverage | §8.2 + reflection test + lint SL-5 |
| DR-14 host AI / UI floats | commands carry ints only; `SimCommand` fields are ints and validated |
| DR-15 interpolation view-only | the kernel stores `prev_*` (needed by combat and cheaper than a view-side copy pass) but nothing in the sim reads a *rendered* value; floats appear only in `view/` |

### 8.2 The checksum contract (exactly what is covered)
`SimStateHash.compute(world)` builds **16 parts**, each a `digest32` (MD5 → first 4 bytes LE) of an int stream, in this fixed order (`SimWorld.CHECKSUM_PART_NAMES`); the final checksum mixes them:
```
final = finalize( fold( mix(FNV_OFFSET, SIM_VERSION), part_0 … part_15 ) )     # mix = FNV-1a word step over 4 LE bytes; finalize = murmur3 fmix32  ->  total = f(parts)
```

| # | Part | Stream (in order) |
|---|---|---|
| 0 | `world` | `tick, next_id, next_proj_id, match_state, winner_team, end_reason, end_tick, live_count, config_hash, data_hash, map_hash`, then the 13 rules ints in `SimMatchRules.FIELDS` order (`start_credits, unit_cap, superweapons, fog, shared_vision, veterancy, vision_stride, vision_budget, start_mode, neutral_structures, victory, end_when_no_humans, allow_debug`) |
| 1 | `rng` | `s0, s1, s2, s3` |
| 2 | `players` | for each player in pid order: `pid, team, roster_idx, faction_idx, color, controller, ai_level, ai_style, ai_flags, handicap, eliminated, elim_tick, elim_reason, credits, income_frac, power_supply, power_demand, unit_count, struct_count, rebuilders, st_units_built, st_units_lost, st_units_killed, st_structs_built, st_structs_lost, st_structs_killed, st_credits_earned, st_credits_spent, st_damage_dealt, st_damage_taken, st_cmds, st_rejected, st_peak_units, view.checksum() (0 if none), comp_mask(econ=1, fx=2, vis=4), then each present player component's `hash_into` |
| 3 | `entities` | `digest32` over the pairs `[id, digest32(entity stream)]` for every listed entity in ascending id. **Entity stream**: `id, kind, def_idx, owner, parent, container_id, x, y, prev_x, prev_y, vx, vy, facing, layer, hp, hp_max, paid_cost, flags & 0xFFFFFFFF, flags >> 32, born, expire_tick, orders.size(), per order [type, target_id, x, y, arg, arg2, flags, phase, t0, p0, p1], comp_mask(bit0 move … bit10 summon), each present component's hash_into in slot order` |
| 4 | `map` | the single int `map.checksum_dynamic()` — the map's **mutable** layers only (deposits, structure occupancy, patches, `nav_version`; static terrain is covered by `map_hash` in the `world` part) |
| 5–15 | `sys.commands … sys.cleanup` | for stages 1..11 in order: that system's `hash_state(world, buf)` — every authoritative int the system keeps outside components (path-request queues, projectile pool, zone tables, production timers, the economy's tech / power / queue state …). Stubs contribute `EMPTY_DIGEST` |

```gdscript
static func compute(world: SimWorld) -> Dictionary:               # SimStateHash -- verified reference
	var parts: PackedInt32Array = PackedInt32Array()
	var buf: PackedInt32Array = world._hbuf                       # instance scratch, resize(0) before each use
	buf.resize(0)
	buf.append(world.tick)
	buf.append(world.next_id)
	buf.append(world.next_proj_id)
	buf.append(world.match_state)
	buf.append(world.winner_team)
	buf.append(world.end_reason)
	buf.append(world.end_tick)
	buf.append(world._live_count)
	buf.append(world._config_hash)
	buf.append(world.data.data_hash())
	buf.append(world.map.map_hash())
	world.rules.hash_into(buf)
	parts.append(Checksum.digest32(buf))
	buf.resize(0)
	world.rng.hash_into(buf)
	parts.append(Checksum.digest32(buf))
	buf.resize(0)
	for p in world.players:
		p.hash_into(buf)
	parts.append(Checksum.digest32(buf))
	var ed: PackedInt32Array = PackedInt32Array()                 # per-entity digests, also returned for desync forensics
	for e in world.entities:
		buf.resize(0)
		e.hash_into(buf)
		ed.append(e.id)
		ed.append(Checksum.digest32(buf))
	parts.append(Checksum.digest32(ed))
	buf.resize(0)
	buf.append(world.map.checksum_dynamic())
	parts.append(Checksum.digest32(buf))
	for s in world.stages:
		buf.resize(0)
		s.hash_state(world, buf)
		parts.append(Checksum.digest32(buf))
	var h: int = Checksum.mix(Checksum.FNV_OFFSET, SimConfig.SIM_VERSION)
	for v in parts:
		h = Checksum.mix(h, v)
	return {"final": Checksum.finalize(h), "parts": parts, "entity_digests": ed}
```

**Authoritative vs derived.** Everything that cannot be recomputed from other hashed state is hashed. Deliberately **not** hashed (derived or diagnostic): `SimEntity.team/radius/_*`, `SimPlayer.name/roster/view` (the view is covered by `view.checksum()` + owner), `by_id`, the lists, the spatial hash and its tags (verified by INV-6), the pending command queue (empty at every checkpoint), `events`, `checksum_log`, report/snapshot rings, `Log`. A domain's caches (occupancy grids rebuilt each tick, path caches, visibility scratch) are exempt **only if** every consumer treats them as a pure function of hashed state; a cache whose *content history* affects decisions (a persistent flow field reused across ticks) **is** state and must be hashed. There is no save/restore of mid-game state in v1, so history-dependent caches are safe as long as every peer runs the same sequence.

**Checkpoints.** At tick 0 and every 20th tick (`SimConfig.CHECKSUM_PERIOD`, overridable via `opts.checkpoint_interval` for debugging; net forces 20): compute all parts + per-entity digests (≈ 1.75 ms @ 1,700 entities), append `[tick, final]` to `checksum_log` (Int64 pairs, values 0..2^32−1), push a report `{tick, final, parts, entity_digests}` into `report_ring` (last 64), optionally a `dump_state()` text into `snapshot_ring`.

### 8.3 Adding a field (DR-13 procedure) and the enforcement net
1. Add the `var` to the class. 2. Append it at the end of that class's `hash_into` (or add it to `HASH_EXEMPT` with a `## derived:` comment). 3. The class's coverage test (`SimTestKit.check_hash_coverage(cls, exempt)`) must stay green — it instantiates the class, perturbs each int/String script variable and requires the digest of `hash_into` to change exactly for the non-exempt ones; a mismatch in either direction is a violation (verified: only the documented derived fields are exempt in `SimEntity` and `SimPlayer`). 4. If behaviour changes, bump `SimConfig.SIM_VERSION`. 5. Regenerate `game/tests/golden/sim_core.json` in the same change.
*Existing lint* (`tools/py/lint.py`, qa_tooling §3) already covers the DR text rules for `src/{core,sim,map,data}`: **L003** (float type/literals/builtins, `randi…`, `Time.*`, `delta`, unqualified `sin/cos/atan2/sqrt/pow/floor/round…`, `.normalized() .distance_to() .length_squared()`), **L005** (module dependency direction), **L006** (`print` only in `core/log.gd`), **L007** (≤ 1500 lines), **L008** (typed vars), **L009** (file name = snake_case of class), **L004** (class prefix per directory). *Additional sim lints* (implemented by QA in `tools/py/qa/check_sim_rules.py`, qa.md 5.14, whose numbering is used here — its SL-1 … SL-4 are the L003 text rules): **SL-5** every `class_name` deriving `SimComponent`/`SimEntity`/`SimPlayer`/`SimOrder` defines `hash_into` (the reflection test remains authoritative) · **SL-6** no `Dictionary`/`Node`/`float` typed member in those classes · **SL-7** negative literal next to `>>`/`<<`, or `<<` with a count ≥ 32 · **SL-8** a member typed `SimWorld` in any `SimSystem`/`SimComponent` subclass (RefCounted cycle) · **SL-9** `.sort_custom(` in sim code without a `# total order:` comment · **SL-10** appending to / erasing from / sorting `world.entities|units|structures|wrecks|zone_ents|neutrals|units_of()|structures_of()` outside `SimWorld` and `SimCleanupSystem`.

### 8.4 Engine facts the kernel relies on (all `[verified]` on 4.7.2, macOS arm64, Linux x86_64 **and** Linux arm64) — `Fp.self_test()` re-checks the arithmetic ones at boot
1. Packed arrays are **reference types** (aliasing on assignment/argument passing); `PackedInt32Array.append(v)` **wraps modulo 2^32 silently**.
2. `HashingContext.update()` on empty input returns an error → use `EMPTY_DIGEST`.
3. `JSON.parse_string` returns **floats for all numbers** (ints > 2^53 lose precision; `stringify` prints `96.0`); `JSON.stringify(x, "", true)` sorts keys — net normalises before the sim sees a dictionary.
4. Runtime `>>`/`<<` on typed negative ints is arithmetic/normal; a **constant** negative shift operand is a parse error; shift counts wrap mod 64; int64 multiplication wraps.
5. `const X: PackedInt32Array = [ … ]` is legal (fast const access ≈ 17 ns); `const X = PackedInt32Array([ … ])` is not. Cross-class `static var` reads cost ≈ 5× a const read.
6. A static method named like a builtin (`sin`, `cos`, `atan2`, `clamp`) is **not** chosen by an unqualified call inside its own class.
7. `Object.get_property_list()` exposes script variables with `usage & PROPERTY_USAGE_SCRIPT_VARIABLE` (4096) → reflection-based coverage/dump work; `Object.set(name, v)` works.
8. `ProjectSettings.get_global_class_list()` works in headless script mode (used by `SimPipeline`).
9. `for x in array` iterates the *live* array (elements appended during the loop are visited) → guarantee G-1 and lint SL-10.
10. `Dictionary` preserves insertion order (also after `erase`); `Array.find(obj)` compares identity; `PackedInt32Array.sort()` and `PackedInt64Array.sort()` are native and total.
11. The integer-division warning must be disabled project-wide (§7.7).
12. Under `--strict` (the repo's CI) an untyped `for` iterator over an untyped `Array`/`Dictionary` is an error → write `for e: SimEntity in …`; a private (`_x`) class variable read only by *other* classes triggers `unused_private_class_variable` → annotate with `@warning_ignore("unused_private_class_variable")` (or `@warning_ignore_start/restore` around a block); a member named `hash` triggers `shadowed_global_identifier` → the world calls it `spatial`.
13. `static var _ready: bool = _build()` runs `_build()` once when the class is first used, after the earlier static vars are initialised (how `SimCmd` builds its layout table).
14. `Callable.is_valid()` is false for a default-constructed `Callable()` (unregistered command executors, unset `Log.sink`).

### 8.5 Desync diagnostics (what actually happens; net.md 5.7 owns the protocol)
1. Every 20 ticks net takes `(checksum_at(T), input_chain)`; on a mismatch it classifies input-chain vs sim divergence and exchanges `checksum_parts_at(T)` — the first differing **part name** (`checksum_part_names()`) names the domain: `world`/`rng` (draw-count or scheduling divergence), `players`, `entities` (any entity), `map`, or `sys.<stage>` (`sys.economy`, `sys.combat`, …).
2. For `entities` two peers can exchange `report_at(T)["entity_digests"]` (`[id, digest]` pairs, ≈ 10 KB for 1,200 entities) and diff by id: the first differing id (or an id present on one side only) is the culprit. Reports are kept for `SNAPSHOT_KEEP = 64` checkpoints (64 s).
3. Every peer writes `dump_state()` to `user://desync/…state.txt`: one line per player / entity / system carrying **every checksummed int** (`E<id> id kind def owner parent container x y prev_x prev_y vx vy facing layer hp hp_max paid flags_lo flags_hi born expire orders… comp_mask …`); `SimTestKit.diff_dumps(a, b)` prints the first differing lines (tested: a tampered command shows up as two `E3` lines with different `x/y/facing`). `opts.snapshot_keep = N` retains the last N dumps in memory.
4. Offline: net re-simulates two replays to the tick and diffs `dump_state()`; since replays feed `submit_raw` + `step` only, the kernel adds nothing.

### 8.6 Cross-platform status
The reference prototype suite (23 scripts, 248 assertions, 364 output lines covering Fp/RNG/log/checksum/hash/commands/orders/events/config/part attribution/S-CORE-1/lifecycle/API/map contract/world lifetime/command-log/fuzz) is **byte-identical** on Godot 4.7.2 macOS arm64 and Linux x86_64 (Docker `debian:12-slim`, `--platform linux/amd64`, `tools/godot-linux-x86_64`); the repo's `tools/py/xplat_determinism.py` reports **IDENTICAL hash chains on macOS arm64, linux/amd64 and linux/arm64** (61 hashes of the 3-player chaos scenario `xplat_sim_core.gd`). Windows x86_64 could not be executed in the authoring environment; it shares the same integer semantics (MSVC arithmetic shift, wrapping imul) and is covered by `Fp.self_test()` plus the golden file in release testing (risk K-4).

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

**Measured on the authoring machine (Apple M5 Max, Godot 4.7.2, headless, machine load ≈ 3 from other agents; best of 5 runs).** Multiply by ≈ 2.5 for a mid-range x86 laptop (reference PC) — the budget below uses the multiplied numbers. World for the kernel rows: 8 players, 1,200 units + 488 structures (1,688 entities), all domain stages stubbed.

| Operation | M5 Max | Reference PC (≈×2.5) |
|---|---|---|
| GDScript static call overhead | 70–90 ns | ~0.2 µs |
| `Fp.sin` / `atan2` / `dist` / `mul_div` / `isqrt` / `step_x` | 0.08 / 0.35 / 0.23 / 0.18 / 0.14 / 0.18 µs | 0.2 / 0.9 / 0.6 / 0.45 / 0.35 / 0.45 |
| typed-array index / int-key `Dictionary.get` | 48 / 108 ns | 0.12 / 0.27 µs |
| `SimEntity` field access (10 fields in a loop body) | 0.33 µs | 0.8 µs |
| `spawn_unit` end to end (entity, hash, counters, 11 hooks, event) | 6.5 µs | 16 µs |
| `SimOrder.make` / `orders.issue` (REPLACE, 11-stage `order_gate` loop) | 0.7 / 2.8 µs | 1.8 / 7 µs |
| `SpatialHash.move` alone / `world.set_pos` first touch of a tick (incl. next-tick reset) / repeated in one tick | 0.33 / 0.64 / 0.46 µs | 0.8 / 1.6 / 1.2 µs |
| `query_circle` r = 4 / 8 cells: uniform map / dense cluster | 5.0 / 11.3 µs · 6.9 / 15.4 µs | 12 / 28 µs · 17 / 38 µs |
| `events.emit` | 0.2 µs | 0.5 µs |
| `SimCmd.move` (3 ids) / `decode` / whole 3-actor MOVE command (build → submit → decode → execute → 3 orders) | 0.5 / 2.9 µs / ≈ 24 µs | 1.2 / 7 / 60 µs |
| dispatcher: 240 active orders on a no-op handler (delta over idle) | +45 µs (0.19 µs per active order) | +110 µs |
| checkpoint (16 parts, 1,688 entities) | 1.7 ms | 4.3 ms (every 20th tick → 0.22 ms amortised) |
| structure spawn + removal incl. occupancy (measured with the prototype's stub map: 4.5 µs of the total are `occupy` + `vacate`; the kernel's own share — footprint lookup, cell maths, one call — is an estimated ≈ 1 µs; the real nav update is the map domain's budget) | 8.9 µs | 22 µs |
| `SimInvariants.check` (1,888 entities, 96×96 map; debug / QA cadence only) | 4.1 ms | 10 ms |
| idle full `step()`, all stub stages (incl. 0.09 ms amortised checkpoint) | 0.29 ms | 0.72 ms |
| 60 kills + hooks + removals + compaction (per death ≈ 13 µs) | 0.8 ms | 2 ms |
| 1,200-unit *all moving* step with the test mover (atan2 + 2×step + set_pos each) | 2.2 ms | 5.5 ms (domain cost, not kernel) |
| `digest32` of a 30-int stream vs the same with per-int `Checksum.mix` | 0.34 µs vs 3.6 µs | – |

**Kernel cost model per tick at 8 players × 150 units (~1,900 entities), reference PC:** idle skeleton ≈ 0.5 ms (expiry scan 1,900 × 0.12 µs ≈ 0.25 ms is the largest part; compaction now runs only on ticks with removals) · stage 1: ≈ 60 µs per 3-actor command (a select-all of 150 actors ≈ 1.2 ms once) · stage 5 dispatcher ≈ 0.5 µs per active order + handler work (domains) · `set_pos` bookkeeping ≈ 1.6 µs per mover (all 1,200 units moving ≈ 1.9 ms; typically half) · events ≈ 0.3 ms at 300 events/tick · checkpoint amortised 0.23 ms. **Kernel total ≈ 1.5–2.5 ms average, + 4.5 ms on checkpoint ticks** out of an 8 ms sim budget (a 60 FPS frame that also renders). Domains therefore have ≈ 5 ms average; combat/movement must self-limit (stride/stagger).

**Worst cases and mitigations**

| Case | Cost | Mitigation |
|---|---|---|
| Checkpoint spike (4.5 ms) landing on a heavy tick | one slow frame per second | acceptable; if profiling demands, raise the global constant `CHECKSUM_PERIOD` to 40 (same on every peer; **never** vary it per machine or per load) — splitting one checkpoint across ticks is not allowed because state changes between ticks |
| `select-all + MOVE` (150–512 ids) | ~1.2 ms once | ids capped at 512; orders allocated only at command time |
| Mass death (nuke, 60 units) | 60 × (hooks + wreck spawn ≈ 17 µs + removal) ≈ 2 ms | wreck creation is the dominant cost and is combat's policy (only land combat vehicles); wrecks capped by `MAX_ENTITIES` |
| Defeat of a 150-unit player | 25 ticks × 6 deaths | rate-limited by design |
| Query storms (combat acquisition) | 12–40 µs each on the reference PC | **contract for combat:** ≤ ~100 radius queries/tick (stagger acquisition by `id & 3`, cache the current target), prefer `nearest()` with small radii; use tag filters to skip friendlies |
| Event flood (1,000+ events/tick) | 0.5 ms | fixed 40-byte records, soft cap, `enabled = false` in headless soak |
| Expiry scan grows with the entity count | 0.12 µs per entity per tick | if ever needed: index the `F_TEMPORARY` entities (ascending) instead of scanning all — a private change |
| Entity table growth (long match) | `by_id` doubles; 200 k ids = 3.2 MB | ids never reused but wrecks/zones are the only high-churn kinds |
| Memory | entity ≈ 1 KB → 2,000 entities ≈ 2 MB; hash arrays 16 B/id; event buffer ≤ 5 MB (soft cap) | – |

**Data-structure decisions (8 × 150 entities).** Arrays not dictionaries for anything indexed by id/pid (`by_id`, relation table, ally masks) — 2.2× faster than `Dictionary.get`; per-kind and per-owner ascending lists maintained incrementally (append at flush, one compaction pass per cleanup that removed something) so no system ever sorts or filters the global list; **no entity pooling** (spawns are rare relative to ticks; pooling would create stale-reference hazards for the view) — projectiles, the only high-churn objects, are pooled by combat; packed arrays for bulk state; strides for expensive stages (`VisionSystem` stride 2, combat acquisition staggered); hot loops inline `>> 10`, `x*x+y*y` and cache statics in locals (a cross-class `static var` read is ~5× a local); avoid `Callable.call` in per-entity loops (≈65 ns) — handlers are called through array-indexed objects; state digests use one native MD5 per stream (10× cheaper than per-int FNV).

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

All tests are `game/tests/{core,sim}/test_*.gd` (`extends RefCounted`, `func test_*(t: TestCtx) -> void`, one fresh instance per test), run by `tools/gd test <filter>`, macOS **and** `tools/gd linux`. `t.eq` is type-strict (int ≠ float). A run that prints any `SCRIPT ERROR`/`ERROR:` line fails (the runner turns engine errors into test errors). The expected values below were produced by the prototype scripts named in brackets (`t_*.gd`) and are identical on both platforms.

### 10.1 Unit tests

| Test file [prototype] | Cases |
|---|---|
| `test_fp.gd` [`t_selftest`, `t_tables`, `t_fp_ref`, `t_move`] | `self_test() == []` · table digests `2046802713` / `1306073121` · sin/cos: `sin(0)=0, sin(1)=101, sin(256)=25080, sin(512)=46341, sin(1024)=65536, sin(2048)=0, sin(3072)=−65536, sin(−1)=−101, cos(0)=65536, cos(2048)=−65536`; symmetry `S[a]=S[2048−a]=−S[a+2048]` for all a (0 violations); `sin²+cos²` within 2·65536 of 65536² · `atan2` samples §5.1 (8 octant vectors) + accuracy ≤ 1 unit vs float `atan2` on 20,000 random vectors · `isqrt`: `k²−1,k²,k²+1` for k ∈ {0,1,2,3,46340,46341,65535,65536,1000003,2147483646,2147483647} exact; `isqrt(2^62−1)=2147483647`; `isqrt(−5)=0`; 100,000 random values vs binary-search reference (digest `853641712`) · `dist(3000,4000)=5000, dist(1,1)=1, dist(−5,12)=13` · `mul_div` table of §5.1 for all modes + `Fraction`-style oracle on 60,000 random triples (digest `1403213809`) · `floor_div(−7,2)=−4, floor_mod(−7,3)=2, ceil_div(−7,2)=−3, floor_div(7,−2)=−4, ceil_div(7,2)=4` · `pct(7,50)=4, pct(−7,50)=−3` · `apply_layers(1000,[1000,−1000])=990; (1000,[1000,500])=1155; (1500,[−2000,−2500,−1500])=765; …,min 60 → 900` · `angle_diff(10,4090)=−16, (4090,10)=16, (0,2048)=−2048, (2048,0)=−2048` · `turn_toward(0,100,30)=30, (0,4000,30)=4066, (4090,20,30)=20, (10,15,30)=15` · `mul_q16(−3,32768)=−1, (3,32768)=2, (1000,46341)=707` · `step_x(474,300)=224, step_y(474,300)=199` (a unit walking (21504,22528)→(30720,30720) at 300/tick arrives after 42 steps facing 474) · trig digest `3886527727` (atan2/rot_x/rot_y, 50,000 vectors) · converters: `milli(0.1)=100, milli(2.675)=2675, cells_to_units(2500)=2560, seconds_to_ticks(1500)=30, cps_to_units_per_tick(3000)=154` · `Fp.TURN == 4096`, `SimConfig.CELL == Fp.CELL` |
| `test_sim_rng.gd` [`t_rng`] | first 4 `next_u32`: seed 0 → `2407135599, 70998536, 3162094942, 2962270859` · seed 1 → `3898016280, 503430273, 2109199260, 1781707058` · seed 12345 → `1165108165, 1674106077, 2795167292, 40330380` · seed 4294967296 → `3443646874, 3280564437, 988752536, 1060094022` · seed 1234567890123456789 → `1222558724, 1588512357, 1375524028, 485886740` · `SimRng.new(42)`: `next_int(100)×8 = [82,87,94,90,96,0,16,46]` then `range_i(−5,5)×8 = [0,−4,−2,−3,1,−3,−3,0]` · `next_int(n) < n` (n ∈ {1,2,3,100,2^30}) · 1,000,000 draws of `next_int(10)` within ±2 % per bucket (worst deviation 577) · `get_state/set_state` resumes the same sequence · `reseed(−1)` valid, ≠ `reseed(1)` · `shuffle` of 8 elements (seed 3) = `[1,3,4,7,5,2,8,6]` |
| `test_checksum.gd` [`t_ck`] | `fnv_bytes("foobar") = 0xBF9CF968`, `("a") = 0xE40C292C`, `("") = 0x811C9DC5` · `mix64` equals `mix(lo) ∘ mix(hi)` for −2 and 5·10⁹ · accumulator `add(1); add(−1); add64(−2); add64(5000000000)` → raw `0x29A072D1`, `value() = 0xE1C8E810` · `digest32([1,2,3,−4,100000]) = 3675704907 = 0xDB16CE4B` · `digest32([]) = EMPTY_DIGEST = 0xD98C1DD4` (= 3649838548) · `add_packed([1,2,3,−4,100000])` from a fresh accumulator → raw `0xE08A87EE` |
| `test_sim_map.gd` [`t_map`] | **world setup from the map**: `map.neutrals` records → one neutral STRUCTURE per mapped kind (scenery and unmapped kinds spawn nothing), centre = top-left cell + size/2, 2×2 occupied, not counted for anyone, `F_INITIAL`; players' HQs on their spawn cells; `rules.neutral_structures = 0` spawns none; `START_MCV` puts a unit there · **event order**: `SPAWNED` then `NAV_CHANGED` per structure (`a` = packed bbox, `b` = `nav_version`, `c` = id, `d` = 1), `NAV_CHANGED(d = 0)` before `REMOVED` · **lifecycle**: occupied at spawn (before any hook), a dead structure keeps its cells until stage 11, a `remove_deferred` corpse until its deadline · **rotation**: `facing / 1024 & 3` swaps the sides of a rotatable 3×2 (orient 0: 3×2, 1: 2×3, 3149 → orient 3), a non-rotatable footprint ignores it, `SPAWNED.e` carries the facing · `F_NO_FOOTPRINT`: no occupancy, no event · `change_owner` keeps cells · units never occupy · **isolation**: two worlds from one template share nothing dynamic (`clone_fresh`), the `map` part reacts to occupancy · `SimWorld.create` refuses a start slot beyond `map.spawns` and spawn / neutral lists that are not whole records |
| `test_sim_free.gd` [`t_free`] | a world (3 players, S-CORE-1 for 60 steps: wreck, resign, orders, events) is freed when its last reference is dropped; replacing `world.fog` changes nothing; a negative control (a system that stores the world) does leak, proving the test can fail |
| `test_spatial_hash.gd` [`t_hash`, `t_nearest`] | 300 circle + 300 rect queries over 1,200 entities (800 clustered) with random `need`/`avoid` — 0 mismatches vs brute force (8,653 circle hits), results ascending · edge positions `x = 0`, `x = map_max`, out-of-map insert clamped · `remove` twice, `move` across buckets, `insert` of id ≥ capacity grows the arrays · `cell_bucket` ascending · `nearest` tie-break: entities at distance 300 with ids 4 and 5 → 4; nothing in a tiny radius → 0 |
| `test_log.gd` [`t_logging`] | `sink` receives `(level, tag, msg)` for lines at or above `level`; the ring records every line (even below the threshold) and keeps the last 256; `quiet` suppresses the sink; a default `Callable()` is not valid (restore `Log.level/quiet/sink` at the end of the test) |
| `test_sim_world.gd` + `test_sim_api.gd` [`t_api`, `t_opts`] | construction: 2 HQs (ids 1, 2), credits 7,500, `checksum_log == [0, 4077726312]` · **credits**: start `7500 × 120 / 100 = 9000` for a 120 % player; `add_credits(+500 HARVEST)` → 8,000 and `st_credits_earned 500`; five 1-credit HARVEST pulses at 120 % pay exactly 6 (`income_frac` back to 0); REFUND/SELL never scaled; `try_spend(1000)` ok, `try_spend(999999)` leaves credits intact, refund lowers `st_credits_spent`; `CASH` event carries `x,y` · **cap**: `unit_cap_room = 148` with 2 rifles, a pop-0 drone is free · **containers**: `set_inside` excludes from queries, `container_id = 999`, INV-13; leaving restores −1 · idle finder, moving unit not idle · **filters**: `query_circle(…, avoid = non_enemy_mask(0))` finds only player 1's rifle; `rel`, `team_of`; `enemies_in_circle` (ascending, default fog), a hide-all fog empties it, `ignore_fog` uses `entity_revealed`; `visible_enemy_ids` · **hp**: research +10 % → `set_hp_max(110)`: `100/100 → 110/110`; `55/110`, +20 % more → `65/130` · **change_owner**: neutral barracks not counted; after capture `struct_count 2`, lists moved, `team` cached, `hp_max` = the new owner's view value (650), second call returns false · **footprints** (through `map.occupy / vacate`, read with `struct_at`): HQ 3×3 occupies cells 19..21² with id 1 and nothing at (22,20)/(18,20); a 2×2 barracks at (60·1024,60·1024) occupies 59..60²; removal vacates them; outside the map is 0 · **fog wrappers**: `entity_visible` forwards to a replaced fog, the default fog is all-visible with no ghosts / decoys / bytes; `are_allied` · **motion**: idle `prev == pos, v == 0`; first `set_pos` of a tick: `prev = start, v = displacement`; second call accumulates; in `moved_prev2()` this and the next tick, not the one after; teleport snaps; INV-15 · `own_ids` ascending/complete, `find_by_def`, `entities_visible_to` · **checksum API**: `checksum_at(last) == log`, `checksum_at(t+1) == −1`, `checksum_at(0) == log[1]`, parts count 16 = names count, `report_at(t)` carries parts + `2n` entity digests, `checksum()` at a checkpoint tick equals `checksum_at` · `dump_state()` has one `E` line per entity; `snapshot_keep = 2` keeps 2 dumps; `take()` empties; `events:false` leaves the buffer empty and never changes the chain; `checkpoint_interval:1` gives 6 checkpoints in 5 steps; `invariants_every:1` logs nothing for a healthy world and reports `INV-7` for a corrupted one (through `Log.error`); `disable` leaves `world.combat == null` and the world runs; `systems` replaces a stage |
| `test_sim_lifecycle.gd` [`t_lifecycle`] | cascade: 20 rifles of a resigned player die `14, 8, 2, 0, 0` per step · kill is immediate (`F_DEAD`, hp 0, invisible to queries) but the entity stays until stage 11; wreck via the combat stand-in: `hp 50/50`, owner = original, `paid_cost 800`, kind WRECK, def TANK, kill stats credited (`st_units_killed`, `st_units_lost`); the wreck is still there 2 steps before its `expire_tick` (= spawn tick + 1200) and gone 2 steps after it; friendly-fire wreck has `F_NO_SALVAGE`; `SCUTTLE` leaves none · pop-0 drone does not count toward the cap; `F_HAS_CHILDREN` set · **tether chain** g1 → (g2, g4) → g3 dies in one tick in generations, ascending id inside a generation (`on_dying` order `[g1, g2, g4, g3]`, causes SCRIPT then ORPHAN) · **deaths run in ascending id order** whatever the kill order (kills 3,1,4,2 → hooks 1,2,3,4) · lingering corpse via `remove_deferred(+5)`: not counted, present for 4 ticks with INV clean, removed at the deadline · `remove_entity` true once then false; deferred removal of a live entity fires as `REM_EXPIRED`; `F_EXPIRE_KILLS` summon dies through `on_dying` · match end: last opponent resigns → `is_match_over`, `match_result().winner_team == 1`, tick frozen afterwards, `spawn` returns null · reflection coverage: every non-exempt `SimEntity`/`SimPlayer` int field is hashed and every exempt one is not |
| `test_sim_commands.gd` [`t_cmd`] | the six golden int arrays of §4.8 and their `from_ints → to_ints` round trip · **every** catalog op (45) builds → decodes → re-encodes identically, ids `{9,3,9,5}` → `{3,5,9}` · rejects: empty, op 0, op 200, negative op, short fields, trailing ints on an id-less op, id ≤ 0, 1025 ints, 513 ids · in a world: foreign ids → `NO_ACTORS`, x = map width → `BAD_FIELD`, queue mode 3 → `BAD_FIELD`, unknown op, `DEBUG` without `allow_debug` → `NOT_ALLOWED`, `SET_STANCE` without executor → `NOT_AVAILABLE`, pid 9 ignored; 1 accepted / 6 rejected counted in `st_cmds/st_rejected` · canonical order: player 1's command submitted before player 0's, append order kept · `RESIGN` mode 2 → `Elim.KICKED`; second `RESIGN` idempotent, other commands of the eliminated player rejected · `DEBUG` with the flag: +500 credits, 2 tanks spawned · **v2.1**: `all_ops()` = the 45 ops ascending; `FOLLOW` issues `T_FOLLOW` with its target; `MOVE` flags b0 + b1 + b2 (= 7) → `OF_NO_FORMATION`, `OF_SPEED_MATCH` and `OF_REVERSE_OK` together, the same bits on `ATTACK_MOVE` and `PATROL` (which keeps `OF_CYCLIC`); `RETURN_TO_BASE` carries its airfield id as the order target; `DEBUG` mode 3 kills the target (`NO_TARGET` if gone), mode 5 reaches the combat test double's `on_debug`, unclaimed mode 6 is `BAD_FIELD` |
| `test_sim_orders.gd` [`t_orders`] | `on_begin` and `on_update` run in the same pass (`["b3","u3.1"]`); completion calls `on_end(DONE)` once · duplicate `register_handler` logged and ignored (first wins) · `QM_REPLACE`: `on_end(REPLACED)` for begun orders only · `QM_FRONT`: front order runs, interrupted order resumes at its phase (`b4 u4.1 b1 u1.1 e1/0 u4.2`) · `QUEUE_FULL` at 32 · `OF_CYCLIC` re-queues with phase reset · `FAILED` drops only that order, `on_end(FAILED)`, `ORDER_FAILED` carries `o.fail` (`BLOCKED`) · `on_target_lost` when the target is removed, then `on_end(FAILED)` · `STOP` → `END_CANCELLED (2)`; unit removal → `END_DIED (4)` · idle hooks in registration order, stop after one enqueues (`["first","second"]`, `OF_AUTO`) · `order_gate` veto: `issue` returns `DISABLED`, a vetoed `MOVE` command is rejected and counted |
| `test_sim_events.gd` [`t_events`] | record layout `[type, tick, x, y, a..f]`, defaults 0 · `emit_throttled` (once per gap per (type,pid); other pid unaffected) · soft cap: 131,072 kept, the 131,073rd counted in `dropped` · `take()` hands over and empties · `enabled=false` no-op · `digest()` of an empty buffer = `EMPTY_DIGEST` |
| `test_sim_config.gd` [`t_cfg`] | valid config → `[]`; the bad config of §5.10 → the 6 exact messages · net.md 7.1 example (non-contiguous pids 0,1,5) validates, builds a 6-player world (vacant 2–4 pre-eliminated, credits `[7500, 9000]`, 3 HQs), `rel` matrix, `config_hash = 3200203660`; `to_dict → from_dict` keeps the hash; renaming a player keeps it, changing a handicap changes it · a float in `map` → `validate` reports it · `SimWorld.create` returns null (and logs) for an invalid config |
| `test_sim_command_log.gd` [`t_log`] | 5 records over 130 ticks → 41 flat ints, round trip · `play()` on a fresh world reproduces the 3 checkpoints and the final checksum (`446186505`) and the `dump_state()` text · tampering with the first command → `mismatch_tick 20`; `diff_dumps` shows two `E3` lines differing in `x/y/facing` · `double_run()` identical |
| `test_sim_determinism.gd` [`t_attrib`, `t_world`] | **part attribution**: one mutation per part (`next_proj_id`, one RNG draw, credits, one entity hp, the map occupancy (`checksum_dynamic`), system-private state) changes exactly that part; flags bit 34 (high word) and `prev_x` are hashed; undoing restores the checksum · **sensitivity**: one differing command field / one hp point / another seed changes the chain · double run: identical chains, events digest, final checksum and `dump_state()` |

### 10.2 Structural invariants (`SimInvariants.check`, run after every step in scenario tests, every 7 steps in fuzz, and by `opts.invariants_every`)
INV-1 `entities` strictly ascending, `by_id[id]` identity · INV-2 kind lists = entities filtered by kind, ascending · INV-3 per-owner lists exact and ascending · INV-4 `_counted` ⇔ owner valid ∧ kind UNIT/STRUCTURE ∧ not `F_GONE` · INV-5 `unit_count/struct_count/rebuilders` equal recounts · INV-6 every non-inside entity is in the spatial hash with matching `x,y,tag`; inside entities are not · INV-7 `F_DEAD ⇒ hp == 0`, otherwise `1 ≤ hp ≤ hp_max` when `hp_max > 0` · INV-8 positions inside the map · INV-9 only units have orders; queue ≤ 32; every order type has a handler · INV-10 `_live_count` = live entities · INV-11 no gone entity listed; transient queues empty at every step boundary · INV-12 all ids < `next_id` · INV-13 `F_INSIDE ⇔ container_id ≥ 0`, inside ⇒ not in hash · INV-14 `e.team == team_of(e.owner)` · INV-15 motion: a mover has `v == pos − prev`; every other entity has `prev == pos ∧ v == 0` · INV-16 every `map.occ` cell ≥ 0 holds the id of a live occupying entity (`_occ`), and every occupying entity has a footprint · INV-17 no zombie: a dead entity that is not queued for removal must have a future `expire_tick` (this caught a real defect of the first cleanup design: children killed during the removal batch were never removed).

### 10.3 Golden scenario S-CORE-1 (`SimTestKit.s_core_1`) [`t_world`, `t_golden`]
Fixture §7.1, 2 players (pid 0 HUMAN team 1 `roster.fx.a`, pid 1 AI team 2 `roster.fx.b`), seed 424242, default rules, `TestCombatSystem` at stage 8, `TestMoveHandler` (speed 300; per tick: if `dist² ≤ 300²` snap to target and finish, else `facing = atan2(dy,dx)`, `set_pos(e, x + step_x, y + step_y)`) registered for `T_MOVE` and `T_PATROL`.
Setup (after construction, HQ ids 1 and 2): `spawn_unit(…, SPAWN_PRODUCED)`: P0 rifles ids 3–7 at `(21·1024 + i·700, 22·1024)` paid 200; P0 tanks ids 8–9 at `(24·1024, 20·1024 + i·1500)` paid 800; P1 rifles ids 10–12 at `(69·1024 + i·700, 68·1024)` paid 200; P1 tank id 13 at `(66·1024, 70·1024)` paid 800.
Script (`s` = loop index, commands submitted before `step()` #`s+1`; 200 steps):

| s | action |
|---|---|
| 2 | P0 `MOVE` ids 3–9 → (30·1024, 30·1024), `QM_REPLACE` |
| 5 | P1 `MOVE` id 13 → (50·1024, 50·1024); then `MOVE` id 13 → (60·1024, 40·1024) with `QM_APPEND` |
| 8 | P0 `SCATTER` ids 3, 4 |
| 30 | P0 `SCUTTLE` id 8 (a tank) |
| 40 | P1 `SCUTTLE` id 9 (P0's tank) → rejected `NO_ACTORS` |
| 60 | direct API: `world.kill(entity 13, Cause.DAMAGE, killer_id 3, killer_pid 0)` (enemy kill → the stand-in leaves an eligible wreck) |
| 100 | P1 `RESIGN` |

**Expected** (identical on macOS arm64 and Linux x86_64): `checksum_log[0..1] = [0, 4077726312]`; checkpoint checksums (u32) at ticks 20/40/60/80/100 = `2467641772, 1177079746, 828122293, 3138515439, 2720863688`; `events.digest() = 3987817499` (26 events); at the tick-100 checkpoint the 16 part digests are `world 3428337259 · rng 2740417745 · players 2789405313 · entities 1983726783 · map 533770084 · sys.combat 3722655248 · the other ten stages 3649838548 (EMPTY_DIGEST)`; final state `match_state = ENDED, winner_team = 1, end_reason = ELIMINATION, end_tick = 100, tick = 101`, final checksum `4082083667`; **8 entities** remain: HQ id 1 at (20992, 20992) · rifles 5, 6, 7 and tank 9 at (30720, 30720) with empty queues · rifle 3 at (21442, 22306) and rifle 4 at (24082, 26578) (scattered) · **wreck id 14** (kind WRECK, owner 1, def TANK, `hp 50`, `paid_cost 800`, `expire_tick 1260`, flags `F_TEMPORARY \| F_UNTARGETABLE \| F_NO_SELECT \| F_NO_UNIT_CAP`) at (57299, 58810) — P1's units and HQ were destroyed by the defeat cascade in the resign step and tank 8 by the scuttle (no wreck); event census (26 records): `SPAWNED 14 · NAV_CHANGED 3 (two HQs occupied at creation, P1's HQ vacated by the cascade) · REMOVED 6 · CMD_REJECTED 1 · PLAYER_ELIMINATED 1 · MATCH_END 1`; counters P0 `built 7 lost 1 killed 1 cmds 3 peak 7`, P1 `built 4 lost 4 killed 0 cmds 3 rejected 1`; RNG state after `[1164917686, 1157485396, −1740605161, −188843546]` (int32-wrapped lanes); double run identical; seed 999 differs.

### 10.4 Determinism tests
* **Double run** (`double_run`): same factory/script twice ⇒ identical chains, event digests and `dump_state()` texts.
* **Command-path equivalence**: the scenario submits everything through `submit_raw` (the only path); the decoded record is never mutated by executors except `actors`/`detail`.
* **Replay**: record S-CORE-1-like scripts with `SimCommandLog.submit`, `play()` on a fresh world ⇒ `ok`; net's own `NetSelfTest.run_double` repeats this against `NetReplayPlayer`.
* **Cross-platform**: the prototype suite and 5 fuzz games run byte-identically on macOS and in the Debian container; `xplat_sim_core.gd` runs under `tools/py/xplat_determinism.py` on macOS arm64, linux/amd64 and linux/arm64 (61 identical hashes).
* **Sensitivity / attribution**: §10.1 `test_sim_determinism`.

### 10.5 Fuzz / soak [`t_fuzz`]
`SimTestKit.random_step` mixes valid and junk commands (random ops, fields, ids, 0–8 random ints) with direct API actions (spawn / kill / remove / change_owner / set_pos incl. teleport / set_inside / set_layer / remove_deferred / add_credits / set_hp_max / tethered spawns / resign / zones), 1–3 actions per step, drawn from a private `SimRng`. Prototype results, seeds 11–15 (2–4 players, 3,000 steps, invariants every 7 steps): `1133726238 / 771214686 / 667777034 / 3193510834 / 2030472703` (final checksums; ticks 3000, 3000, 3000, 3, 21 — seeds 14 and 15 run with victory on and end early), **0 invariant violations**, reruns identical, macOS == Linux. Continuous soak (QA): AI-vs-AI headless 8-player 60-minute match with `invariants_every = 20`, `events = false`.

### 10.6 Visual test (developer aid, SC-12; not built in the prototype)
`game/tests/visual/sim_core_inspector.tscn` (+ `gd shot`): draws, from a `SimWorld` only, the map cells, spatial-hash bucket grid, entities as owner-coloured dots sized by kind, ids as labels, wrecks as crosses, the `map.occ` footprints, `prev → pos` motion vectors, the current order target lines, and the tail of the event log; screenshots at S-CORE-1 ticks 0, 40, 100 must show: two clusters converging, a wreck cross at tick 60+, P1's units gone after the tick-100 resign. The agent inspects the PNGs with the image reader.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Sizes are GDScript lines excluding generated tables; the reference prototype implemented the whole kernel in ≈ 3,700 hand-written lines (`SimWorld` 990, `SimCmd` 272, `Fp` 214, command system 178, cleanup 177, `SpatialHash` 164) plus 332 generated table lines and ≈ 2,300 lines of tests and benches, so every task is far below the cap. Paths are relative to `game/` unless prefixed `tools/`. **The prototype is a throw-away reference, not a code drop:** implementers re-create the files from this spec, and the acceptance column is what the prototype's scripts asserted.

| Task | Title | Files owned (create) | ≈ Lines | Depends on | Acceptance (must pass on macOS **and** `gd linux`, plus `tools/gd check` clean incl. `--strict`) |
|---|---|---|---|---|---|
| **SC-01** | Fixed-point library + table generator | `src/core/fp.gd`, `src/core/fp_tables.gd` (generated), `tools/py/gen_fp_tables.py` (+ `--verify` mode with independent Python `mul_div/isqrt/atan2/rot` oracles), `tests/core/test_fp.gd` | 215 + 340 gen + 220 py + 300 test | SC-02 (`Checksum.digest32` for the table digests) | §10.1 `test_fp`; tool prints digests `2046802713 / 1306073121`; verify mode reproduces `1403213809 / 853641712 / 3886527727`; `Fp.self_test() == []`; L003 clean with the two `lint-allow`s |
| **SC-02** | Config, RNG, checksum, log | `src/core/sim_config.gd`, `sim_rng.gd`, `checksum.gd`, `log.gd`, `tests/core/test_sim_rng.gd`, `test_checksum.gd`, `test_log.gd` | 220 + 200 test | – | RNG/FNV/MD5/log vectors of §10.1; `SimConfig.CELL == Fp.CELL` |
| **SC-03** | Spatial hash | `src/core/spatial_hash.gd`, `tests/core/test_spatial_hash.gd`, `tests/bench/bench_sim_core.gd` | 165 + 150 | – | brute-force equivalence (0 mismatches over 300 + 300 queries), edge cases, bench within 2× of §9 |
| **SC-04** | Kernel model types + skeletons | `src/sim/sim_flags.gd`, `sim_tag.gd`, `sim_component.gd`, `sim_system.gd`, `sim_fog_api.gd`, `sim_order.gd`, `sim_entity.gd`, `sim_player.gd`, `sim_defs.gd`, the 14 component stubs in `src/sim/comp/`, the 8 system stubs + `SimStrategicSystem` (§2.4), and a **skeleton** `sim_world.gd` (all typed members + method signatures, bodies `push_error("NOT IMPLEMENTED …")`) so every module parses from day 1 | 600 | SC-02 | `gd check` clean; `check_hash_coverage(SimEntity)` / `(SimPlayer)` report only the documented exempt fields; component stubs instantiate; `SimDefs` against a stub `GameData` |
| **SC-05** | Match config | `src/sim/sim_match_rules.gd`, `sim_player_slot.gd`, `sim_match_config.gd`, `tests/sim/test_sim_config.gd` | 200 + 120 | SC-02 | validation messages of §5.10, net.md 7.1 example builds, `config_hash` goldens `856134193 / 3200203660` |
| **SC-06** | World, pipeline, state hash | `src/sim/sim_world.gd` (replaces the skeleton), `sim_pipeline.gd`, `sim_state_hash.gd`, `tests/sim/test_sim_world.gd`, `test_sim_api.gd`, `test_sim_determinism.gd` | 970 + 150 + 300 | SC-02..05, SC-07..10 (same agent, one change) | `test_sim_world/api/determinism/map`; INV-1..17 clean; S-CORE-1 checkpoints (with SC-12 fixtures); the map contract of §7.2b against the map stub (`MapData.for_test` + footprint table), later against the real `MapData` |
| **SC-07** | Command framework | `src/sim/sim_cmd.gd`, `sim_command.gd`, `sim_command_codec.gd`, `sim_command_system.gd`, `tests/sim/test_sim_commands.gd` | 260 + 40 + 75 + 165 + 250 | SC-04 | the six golden int arrays; all 45 ops round-trip (incl. `FOLLOW`, the movement flag bits, `RETURN_TO_BASE.target`, `DEBUG` modes); validation matrix; canonical ordering; `SCATTER` draw count (2 per actor) |
| **SC-08** | Events | `src/sim/sim_event.gd`, `sim_event_buffer.gd`, `tests/sim/test_sim_events.gd` | 110 + 90 | SC-02 | §10.1 `test_sim_events` |
| **SC-09** | Order system | `src/sim/sim_order_handler.gd`, `sim_order_system.gd`, `tests/sim/test_sim_orders.gd` | 140 + 260 | SC-04, SC-07 | begin+update fusion, queue modes, cyclic, failure, `on_end` reasons, idle hooks, `order_gate` |
| **SC-10** | Cleanup, lifecycle, victory | `src/sim/sim_cleanup_system.gd`, `tests/sim/test_sim_lifecycle.gd` | 180 + 300 | SC-04, SC-06 | cascade timeline `14, 8, 2, 0, 0`, tether chains, id-ordered batches, lingering corpses, victory cases |
| **SC-11** | Command log + cross-platform scenario | `src/sim/sim_command_log.gd`, `tests/sim/test_sim_command_log.gd`, `tests/scenarios/xplat_sim_core.gd` | 65 + 80 + 40 | SC-05, SC-06, SC-07 | flat round trip, `play()` reproduces checkpoints, tamper detection; `tools/py/xplat_determinism.py` identical on 3 platforms |
| **SC-12** | Test kit, invariants, goldens, fuzz, inspector | `tests/support/sim_test_kit.gd`, `test_move_handler.gd`, `test_combat_system.gd`, `src/sim/sim_invariants.gd`, `tests/fixtures/sim_core_fixture.json`, `tests/golden/sim_core.json`, `tests/sim/test_sim_scenario.gd`, `test_sim_fuzz.gd`, `test_sim_map.gd`, `test_sim_free.gd`, `tests/visual/sim_core_inspector.tscn` + script | 350 + 130 + 200 + 450 | SC-06..SC-11; `ASSUMPTION(data)` R1 (`for_test`), `ASSUMPTION(map)` R7 | S-CORE-1 goldens of §10.3 & §7.5; 5 fuzz games invariant-clean; attribution + sensitivity tests; inspector screenshots reviewed |
| **SC-13** | Contract gate | `tests/sim/test_sim_contract.gd` (+ the lint rules SL-5..SL-10 that QA implements, R25) | 300 | all domain systems landed (soft) | full real pipeline builds; every stage extends `SimSystem`; every component passes `check_hash_coverage`; every op of §6.1 has an executor or order handler (warning until all domains land, error at integration freeze); no domain reaches into `_`-members |

**Waves.** W1: SC-02 → (SC-01 ∥ SC-03 ∥ SC-05 ∥ SC-08). W2: SC-04 (publishes the skeleton, unblocking every domain). W3: SC-07 ∥ SC-09. W4: SC-06 + SC-10 + SC-11 (one agent, one change, because they are mutually referential in GDScript). W5: SC-12. W6: SC-13 as domains land. Domain architects can start coding against the SC-04 skeleton at W2 and get the fixture world at W5.

**Doubles for foreign classes.** SC-06 / SC-12 compile against `GameData`, `DefPlayerView`, `MapData` and `MapFootprint` (members: §7.2, §7.2b). If the data and map domains have not landed their skeletons by W4, the agent works with private throw-away doubles that have exactly those members (the prototype's `stubs/` are that: ≈ 90 lines for `GameData` + `Def*`, ≈ 130 for `MapData` + `MapFootprint`) and deletes them when the real classes arrive — a duplicate `class_name` is a parse error, so doubles are never committed under the real names.

---

## 12. Risks, open questions and your recommended resolution for each

| ID | Risk / question | Recommended resolution |
|---|---|---|
| K-1 | **GDScript throughput** at 8 × 150 units + AI in a 60 FPS frame | Budgets in §9 (kernel ≈ 1.5–2.5 ms avg / +4.5 ms checkpoint tick on the reference PC). Gate every wave with `bench_sim_core.gd` (1,200 units moving). Mitigation ladder: stride/stagger (combat acquisition `id & 3`, vision 2) → `CHECKSUM_PERIOD` 40 (a global constant, identical on all peers) → index the `F_TEMPORARY` entities for the expiry scan → SoA hot fields (breaking change, only if profiling demands) |
| K-2 | Domains bypass the contract (state outside hashed slots, `Dictionary` in components, storing `SimWorld`, mutating shared lists, writing `x/y` directly) | Lints SL-5/6/8/10, per-component reflection coverage test, `test_sim_contract`, INV-6/15 catch stale hash / motion state, checklist in §4.5 and §6.3; reconcilers reject specs that add persistent state without a `hash_into` |
| K-3 | Parallel development: circular `class_name` files and missing domain classes | SC-04 ships the skeleton `SimWorld`, 14 component stubs and 8 system stubs; typed members parse from day 1; tests use `opts.disable` / `opts.systems` |
| K-4 | **Windows not executed** in the authoring environment | `Fp.self_test()` at boot logs the arithmetic facts; release testing compares the golden file and `xplat_sim_core.gd` on a Windows machine; identical integer semantics expected (arithmetic `>>`, wrapping `imul`, LE `to_byte_array`) |
| K-5 | Fixed 11 entity component slots may not fit a domain | Amendment process (one line + one hash word); escape hatch: domain-private arrays keyed by entity id inside its system, hashed in id order via `hash_state` (allowed) |
| K-6 | Single global RNG couples all draw sites (a new draw shifts later ones; goldens change, determinism does not) | Each domain lists its draw sites in its spec; bump `SIM_VERSION` + regenerate goldens; if coupling hurts, add `SimRng.fork(tag)` streams (array hashed in order) — deferred |
| K-7 | Shared per-player def state leaking research between two players of one roster | `DefPlayerView` is per player (data 3.13); test: research for P0 does not change P1's `hp_max` (in `test_sim_api`: `set_hp_max` follows only the owner's view) |
| K-8 | Wreck entities (≤ ~200 alive) cost spawn time and list length | Policy is combat's (land combat vehicles only); 60 s life; cap `MAX_ENTITIES` |
| K-9 | 32-bit checksum collisions (≈ 2⁻³² per check, ≈ 10⁻⁶ per hour) | Accepted; 16 independent part digests improve localisation, not detection; net additionally compares its input chain |
| K-10 | **No mid-game join / save / load** | Not in v1: replays always start at tick 0. If needed later: add `restore()` to components and a `SimWorld.load_dump()` (the text dump already enumerates all checksummed state) |
| K-11 | `apply_layers` rounding (half-up per layer) differs from a single final rounding by ±1 in rare cases | It is the *only* implementation in `Fp`; data's `DefStatMath` must call it or provably match it (data §5.5 uses a two-stage fold: **reconcile**: data's rounding wins for resolved stats, `Fp.apply_layers` remains for AI / UI estimates) |
| K-12 | Names `Fp.sin/cos/atan2/clamp` shadow builtins (ARCH-fixed) | never call them unqualified inside `Fp`; the prototype passed `--strict` without `shadowed_global_identifier` warnings; `spatial` instead of `hash` for the world field |
| K-13 | Spectators, time limits, alliances changing mid-game | Out of scope v1; `end_match`, `RESIGN` reasons, extra `SimPlayerSlot` fields can model them without touching the pipeline |
| K-14 | Event flood or missing consumer in headless runs | `events.enabled = false`, soft cap with `dropped` counter |
| K-15 | Domain caches (path/flow fields, vision) not covered by the checksum | §8.2 rule: history-dependent caches are state and must be hashed; `hash_state` per system; part attribution shows which system diverged |
| K-16 | **Hooks at stage 11 instead of at the `kill()` call** surprise domain authors (economy's `on_entity_died` timing) | documented in §3.3.1 rule 4 and §6.4-E; every system skips `F_GONE`; nothing observable between call and stage 11 except the flags; if a domain proves it needs an immediate reaction it can register an `on_kill_request` extension (amendment) rather than mutating inside `kill()` |
| K-17 | `set_pos` bookkeeping cost (+0.3 µs per mover) | measured §9 (≈ +0.4 ms/tick at 1,200 movers on M5 Max); paid once instead of a per-frame O(N) capture in the view and a private velocity in combat |
| K-18 | Domain specs still use their own names in code samples | the crosswalk §6.4 is normative; the reconciler should sweep the domain specs once; `NetSimAdapterWorld` and `AiWorldView` are the intended single-file shims |
| K-19 | **Kernel-driven occupancy**: `spawn_entity` calls `map.occupy`, whose real precondition is `MapBuildRules.check == PR_OK` (debug assert) | production checks first (its stated flow); scripted, test and fuzz spawns pass `F_NO_FOOTPRINT` or use a tolerant map; INV-16 catches a stale cell; if the reconcilers prefer production to call `occupy` itself, production passes `F_NO_FOOTPRINT` and must also `vacate` — a two-line change in `_occupy` / `finalize_removal` |
| K-20 | **Consumers written against v1's master event catalog** (render, audio, qa: `DIED`, `STATE`, `WEAPON_FIRED`, 8-field records with the position in `a..h`) | translation table §6.4-F3; the events that carry more information than v1 had (`EV_DEATH` kind and visual ticks, `EV_HIT` coalescing) are the producers' design; the reconcilers must either move the consumers to the domain blocks (recommended: symbolic constants per owning class plus a start-up `_validate_codes()`, which render already has) or add a translation layer in the consumers — the kernel needs no change either way |
| K-21 | `SimInvariants.check` costs 4.1 ms at 1,888 entities (QA asked ≤ 2 ms) | accepted: debug / QA cadence only (every 100 ticks = 0.04 ms per tick); the O(cells) occupancy scan is 0.5 ms of it; a `level` parameter can skip the per-entity spatial verification if QA ever needs a cheaper mode |
| K-22 | **Layering conflict** between terrain_movement 13-9 (`GameData.footprint`, `GameData.terrain`) and lint L005 (`core <- data <- map <- sim`) | footprints and terrain are reached through the map (`MapData.footprint_of`, `MapData.tt`), `GameData` keeps only ids / raw dictionaries; the reconcilers amend TM 13-9 and data's `footprint_id` handling |
| Q-1 | Are projectiles entities? | **No** (§4.12) |
| Q-2 | Where do transports/cargo live? | abilities (`SimCompCargo`, `SimTransport`); the kernel provides `set_inside`, `F_INSIDE`, `container_id` and the `on_dying` hook |
| Q-3 | Where do superweapon / support-power cooldowns and the SAP reserve live? | economy's `SimPlayerEcon` (hashed in the `economy` part); the kernel mirrors only `power_supply/power_demand` for HUD / AI |
| Q-4 | NEC Relay fields, HAN command fields | Not kernel concepts: abilities / economy via components, leases and `hash_state` |
| Q-5 | Orders for structures? | No — structures are component-driven; player actions on structures are commands with executors |
| Q-6 | Pause | **Net** (barrier-level; not in replays). Single player: the app stops calling `step()` |
| Q-7 | **Neutral buildings and deposits: `Kind.NEUTRAL` + `data.neutrals` (data), extra `structures` defs with owner −1 (economy, map), DEPOSIT entities (v1), economy's disc table, or map cells?** | **Resolved for the kernel (v2.1)**: neutral buildings are **STRUCTURE** entities of owner −1 — the map's `neutrals` records name `NK_*` kinds whose concrete defs are structure ids (terrain_movement.md 4.3 / 7.4), and they must behave as structures after capture (footprint, sell, repair, victory asset); `map.neutral_def_for_kind` resolves them. **Deposits are not entities**: the map keeps per-cell amounts and fields (`deposit`, `harvest`, `nearest_deposit`, hashed by `checksum_dynamic()`); `HARVEST target = 0` + a cell and `SET_RALLY target = −(field id)` cover the commands. `Kind.NEUTRAL` remains for `DefNeutral` objects that are not structures. Left to the reconcilers: economy's `SimDepositTable` (discs) vs the map's cells (render R24) — the kernel is neutral |
| Q-8 | Who creates wrecks (combat `EV_WRECK_ADD`, economy `spawn_wreck`, abilities' `SimChannel`)? | **Combat**, in its `on_dying` hook via `world.spawn_wreck(e, salvageable, hp, life)`; economy / abilities only consume them (`remove_entity(REM_CONSUMED)`) and extend `expire_tick` while a salvage channel is active |
| Q-9 | Immediate `hp` writers besides combat (repair, heal auras, Engineer) | all through `SimCombatSystem.heal` (combat.md 3.3) so the death / clamp rules live in one place |

### Amendments proposed to `docs/ARCHITECTURE.md` (for the reconcilers; record in `docs/AMENDMENTS.md`)

| # | Section | Proposed text |
|---|---|---|
| A-1 | §6 | Systems extend `SimSystem` (hooks `init_world/update/on_spawn/on_dying/on_remove/on_owner_changed/on_player_eliminated/order_gate/cleanup/hash_state`); the pipeline finds them by class name and exposes them as typed `SimWorld` members (`combat`, `economy`, …) |
| A-2 | §3, §6.12 | `SimWorld.tick` counts game ticks (used by all timers); `SimWorld.step()` is the single driver; commands enter as `submit_raw(pid, PackedInt32Array [op, …])`; **there is no sim-level pause** (net pauses by not stepping) |
| A-3 | §2 | Component files live in `src/sim/comp/` (`SimComp*`, `SimPlayer*`); kernel files in `src/sim/`; a domain may use sub-folders for its systems; tests live in `tests/{core,sim,…}/test_*.gd` |
| A-4 | §4 DR-5 | Add: "runtime `>>`/`<<` on typed negative ints is arithmetic; never write a negative constant next to a shift; 32-bit products use `SimRng.mul32`" |
| A-5 | §7 | Def indices are dense **per kind** (`units`, `structures`, `zones`, `neutrals`); the kernel reads data only through `SimDefs`; per-player resolved values come from `DefPlayerView` |
| A-6 | §8 | Events are flat int32 records of stride 10 `[type, tick, x, y, a..f]` drained with `take()`; code blocks: core 1–99, combat 200–229, abilities 230–259, economy 300–499; presentation must not retain the array |
| A-7 | §10, §11 | `debug/gdscript/warnings/integer_division=0` (set); tests use `func test_*(t: TestCtx)` (net XR-20e) |
| A-8 | §13 | Add to working agreements: "packed arrays alias — `.duplicate()` across ownership boundaries"; "systems never store `SimWorld`"; "typed `for` iterators and `@warning_ignore` on friend-private members under `--strict`" |
| A-9 | §6 | Stage 11 order: defeat cascade → every system's `cleanup(world)` → expiry → id-sorted rounds of {`on_dying` batch, removal batch} → compaction → elimination → victory; kill hooks run there, not at the `kill()` call |
| A-10 | §12 | Elimination counts **assets** only: structures / MCV-class units that are not temporary, decoy or summoned; team ids are arbitrary (1..15) |
| A-11 | §9 | Replay files are net's (`NetReplay`); the sim defines no replay format |
| A-12 | §5, §8 | Structure occupancy is the map's (`MapData.occupy / vacate / occupant_at`, `occ` hashed by `checksum_dynamic()`); the kernel calls it from `spawn_entity` / removal; there is no kernel `struct_grid`; the `map` checksum part is `map.checksum_dynamic()` |
| A-13 | §5 | `src/data` may not mention `Map*` types (lint L005): footprints and terrain are reached through `MapData` (`footprint_of`, `tt`), never through `GameData` |
| A-14 | §8 | Event blocks: core 1–99 (adds `NAV_CHANGED 9`), **movement 100–129**, combat 200–229, abilities 230–259, economy 300–499; `SPAWNED` is the first event of an entity |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**Data domain (`GameData`, `Def*`)**
1. **R1 `GameData` (read-only after construction):** `units: Array[DefUnit]`, `structures: Array[DefStructure]`, `zones: Array[DefZone]`, `neutrals: Array[DefNeutral]`, `rosters: Array[DefRoster]` (dense per-kind indices in sorted-id order, data 5.3) · `roster_idx(id: String) -> int` (−1 unknown) · `data_hash() -> int` (u32) · **`static GameData.for_test(d: Dictionary) -> GameData`** building the §7.1 fixture (also asked by combat and abilities) with pinned `data_hash`.
2. **R2 `DefRoster.hq_idx: int` and `DefRoster.mcv_idx: int`** (structure index of the roster's HQ; unit index of its MCV = the HQ's `deploy_unit`) — the kernel spawns the start entities from them. Fallback if data prefers: the kernel scans `structures` for `SF_NO_BUILD`.
3. **R3 `DefPlayerView`:** `_init(data, roster)`, `resolved_stats(kind: DefEnums.Kind, def_idx) -> PackedInt32Array` with `[DefEnums.Stat.HEALTH]` = current max hp, `apply_research(idx)`, `checksum() -> int`. The kernel hashes `checksum()` per player; production calls `apply_research` (players in ascending pid).
4. **R4 fields read** (§7.2): `DefUnit.health, pop, radius, home_layer, flags (UF_NON_BLOCKING 128, UF_NO_REPAIR 16, UF_NO_CAPTURE 32, UF_NO_SALVAGE 64), ability_mask`; `DefStructure.health, radius`; `DefZone.hp, radius`; `DefNeutral.health, radius` (footprints are the map's, R7). `AbilityKind.DEPLOY_STRUCTURE = 23` must be set on every MCV-class unit def (elimination rule).
5. **R5 Q-7** (neutral buildings are structure defs of owner −1, deposits are map cells) is resolved in §12; data appends the neutral structure defs (`neutral.garrison_house`, …) to `structures` and keeps the ids that `map_gen.json` names.
6. **R6** JSON floats converted once (`DefNumParse` / `Fp.milli`); resolved stats via data's `DefStatMath`; reconcile with `Fp.apply_layers` rounding (K-11); FNV parameters equal `Checksum` (already so).

**Map domain (`MapData`)**
7. **R7 `MapData` (terrain_movement.md 3.3 as published, plus two small requests):** `w, h` · `spawns` (stride `SPAWN_STRIDE = 6`) and `neutrals` (stride `NEUTRAL_STRIDE = 8`) as published · `clone_fresh()` · `map_hash()` · `checksum_dynamic()` (O(1), covers every mutable layer) · `occupy(sid, fp, cx, cy, orient) -> int` and `vacate(sid) -> int` (packed changed bbox) · `occupant_at(i)`, `idx`, `in_bounds`, read-only `occ` and `nav_version` · **requested additions:** `footprint_of(kind: int, def_idx: int) -> MapFootprint` (null = occupies nothing; this replaces TM 13-9's `GameData.footprint`, which lint L005 forbids) and `neutral_def_for_kind(nk: int) -> int` (STRUCTURE def index, −1 = scenery) · `static for_test(w, h, spawn_cells, neutral_records, map_hash)` with `set_footprint(kind, def_idx, fp)` / `set_neutral_def(nk, def_idx)` for the fixture. Semantics relied on: the spawn cell is the centre cell of the 3×3 start footprint (TM V9 must hold for that anchor); `occupy` assumes a legal site — production checks `MapBuildRules.check` first (K-19).
8. **R8** Map generation is a pure function of `config.map` (ints / strings / arrays only; the kernel passes no RNG); start indices ordered so adjacent indices are adjacent positions (net XR-12).
9. **R9** Buildability / pathing / occupancy queries stay in the map domain; the kernel exposes positions, `set_pos`, `struct_at(cx, cy)` and calls `occupy` / `vacate` (R7); `MapBuildRules.check` is production's precondition.

**Net domain**
10. **R10** Build worlds with `SimWorld.create(data, cfg, map, opts)` (returns null on an invalid config); per turn `submit_raw(pid, ints)` for every command in ascending pid then issue order, then `step()` **twice**; `pid` comes from the connection, never the payload.
11. **R11** Departed / kicked / timed-out / desync-dropped players: the host injects `RESIGN` (250) with `mode` = `ResignReason` (0 surrender, 1 disconnect, 2 kicked, 3 timeout, 4 desync) as the first command of that pid's group, in the same turn on all peers.
12. **R12** Keep pause, speed, input delay, replay file, lobby and desync reports in net; use `checksum_at`, `checksum_parts_at` (64 retained), `checksum_part_names`, `dump_state`, optionally `report_at(t)["entity_digests"]` for deeper localisation; `NetSimAdapterWorld` is the single shim.
13. **R13** The `map` dictionary handed to `SimMatchConfig.from_dict` must be int-only (`NetMatchConfig.normalize` already guarantees it); the lobby handshake carries `SimConfig.SIM_VERSION`, `TURN_TICKS`, `CHECKSUM_PERIOD`, `data_hash`, `map_hash`.
14. **R14** Debug commands are unavailable in multiplayer (`rules.allow_debug` is never set by the lobby); net's `rules` whitelist must contain exactly the eight lobby keys of §4.11.

**Simulation domains**
15. **R15 movement:** `SimMovementSystem` (stage 6), handlers `T_MOVE, T_PATROL` (+`T_FOLLOW/FACE/LAND`), `SimCompMove`; move only with `world.set_pos(e, x, y)` (once per unit per tick is optimal; use `teleport = true` for placement); do **not** write `vx/vy/prev_*`; set `F_MOVING/F_AIRBORNE/F_BLOCKED/F_ON_WATER`; skip `F_GONE` / `F_SCRIPTED_MOVE`; read the order flags `OF_NO_FORMATION / OF_SPEED_MATCH / OF_REVERSE_OK` of `MOVE`, `ATTACK_MOVE`, `PATROL`; implement `T_FOLLOW` (command `FOLLOW 12`); keep a private mover list (`on_spawn` append, `cleanup(world)` compact); events 100–129; do **not** call `map.occupy / vacate` and do not fold `map.checksum_dynamic()` into your `hash_state`; call `map.nav.prepare(…)` from `init_world`.
16. **R16 combat:** `SimCombatSystem` (8): executor for `SET_STANCE` (45) (and optionally 40–47 for richer orders), handlers `T_ATTACK, T_ATTACK_MOVE, T_FORCE_FIRE, T_GUARD, T_HOLD, T_RETURN_BASE` + idle hook, `SimCompCombat/Air/Carrier`; **the death path in `on_dying`** (wreck via `spawn_wreck`, `EV_DEATH`, cargo ejection, crash sequences via `remove_deferred`); `kill()` wrapper; hp writes only through combat + `set_hp_max`; `on_debug` mode 5 (set hp of `target`); status timers and stance in `SimCompCombat`; pooled projectiles with `alloc_proj_id()`; `st_damage_*`; events 200–229; ≤ ~100 radius queries per tick.
17. **R17 economy / production / power:** `SimProductionSystem` (2), `SimEconomySystem` (3), `SimPowerSystem` (4) (+ `SimStrategicSystem`), executors 120–134, 140, 141, handlers `T_HARVEST … T_DEPLOY_MCV` + auto-harvest idle hook, `SimCompEcon/Prod`, `SimPlayerEcon` (player-wide queues, tech counters via hooks, power grid, powers, superweapon), credits only through `add_credits/try_spend` (delegate `spend/earn/try_spend/add`), `power_supply/power_demand` mirror, `spawn_*(paid_cost = credits paid)`, `unit_cap_room`, `change_owner` for capture, `remove_entity(REM_CONSUMED)` for wrecks, hooks `on_dying / on_remove / on_owner_changed`, `hash_state` for all private ints; events 300–499; the `EVT_CMD_REJECTED / ORDER_FAILED / CREDITS_GAINED` events are the core `CMD_REJECTED / ORDER_FAILED / CASH`.
18. **R18 abilities / zones / vision / transports:** `SimAbilitySystem` (7), `SimZoneSystem` (9), `SimVisionSystem` (10, stride 2), executors 100–105, `SimCompAbility/Stats/Vision/Cargo/Summon`, `SimPlayerFx/Vision`, `order_gate` for uncontrollable states, replace `world.fog` (`cell_visible/cell_explored/entity_visible/entity_revealed`, plus `ghosts / ghost_version / decoy_identified / fog_bytes / fog_version` for the view), `on_debug` mode 4 (reveal), `set_inside` for cargo, `on_dying(carrier)`, zones / summons via `spawn_zone` / `spawn_unit(… F_SUMMONED …)` + `expire_tick`, read `moved_prev2()`; events 230–259.
19. **R19 all domains:** unique behaviour per stage; `hash_state` for every private int kept outside components; components ints-only with complete `hash_into` and a `check_hash_coverage` test; never store `SimWorld`; never write another domain's `flags` bits; list every RNG draw site in your spec; never touch `_`-prefixed members of kernel classes; iterate entity lists with typed loops and skip `F_GONE`.

**View / UI / Audio / AI**
20. **R20 view:** interpolate `prev_x/prev_y → x/y` after each step (no capture pass); `world.events.take()` once per frame; read fog only via `world.fog`; never keep `Array` references from `units_of()` across steps; create nodes on `SPAWNED`, destroy on `REMOVED` (a corpse may outlive it: combat `EV_DEATH.visual_ticks`).
21. **R21 UI:** build commands with the `SimCmd` builders (Shift ⇒ `QM_APPEND`), submit through the net path; map `CMD_REJECTED` (`err`, `detail`) to feedback (§6.1); combat stance numbering `0 aggressive · 1 defensive · 2 hold fire · 3 guard`.
22. **R22 audio:** consume the event blocks; positional cues filtered with `world.fog.cell_visible(local_pid, cx, cy)` except events documented as global (superweapon warnings).
23. **R23 AI:** read only via `SimWorld` queries (`get_entity`, `own_ids`, `units_of`, `structures_of`, `query_circle`, `enemies_in_circle`, `visible_enemy_ids`, `players[pid]` incl. `st_credits_earned`, `st_rejected`), act only via `SimCmd` builders; may use floats internally; `-1` "no target" is accepted by the decoder.

**App / QA / tooling**
24. **R24 app:** `Fp.self_test()` at boot (log errors); wire `Log.sink` to a file under `user://logs/`; `project.godot` `integer_division=0` (present).
25. **R25 QA / toolsmith:** run `tests/{core,sim}` on macOS and `tools/gd linux` (amd64 + arm64); add `game/tests/scenarios/xplat_sim_core.gd` to the `xplat_determinism` CI job; lints **SL-5 … SL-10** of §8.3 (QA's `check_sim_rules.py`); treat any `SCRIPT ERROR`/`ERROR:` output as failure; keep `gd check --strict` at 0 warnings for `src/core` and `src/sim`.

**Reconcilers**
26. **R26** Apply amendments A-1 … A-14 (§12) to `docs/AMENDMENTS.md`; Q-7 is resolved (§12); sweep the domain specs for the names of the crosswalk (§6.4) — in particular economy 3.9 / 13-4 (hook timing), abilities 13-3 (`spawn_entity`, `set_layer` signature), combat 13-4 (`emit`), ai 13-3 (encoders = `SimCmd`), net 6.1 (`T_RESIGN` alias); fold the duplicate events listed in §6.4-C.

**Specs published late (reconciled in §6.4-F)**
27. **R27 map + data (terrain_movement 13-9, lint L005):** `MapData.footprint_of` and `neutral_def_for_kind` instead of `GameData.footprint` / `GameData.terrain`; production and movement stop calling `occupy` / `vacate` themselves (the kernel does), keep `MapBuildRules.check` as the pre-spawn gate and drop `world.movers` / `world.cargo_*` / `world.set_order` / `world.unit_hash` from their assumptions (§6.4-F1 gives each replacement).
28. **R28 view, audio, QA:** replace the v1 names by the ones in §6.4-F2 / F3 (`get_entity`, `hp_max`, `container_id`, `expire_tick`, `query_circle`, `report_at(t).parts`, no pause, no `apply_turn`) and move the consumers from v1's master event codes to the blocks of the owning domains (translation table in F3); `SimEvent` holds the core codes only, every other class exposes its own `EV_*` / `EVT_*` constants.
29. **R29 QA:** accept the declined/adapted items of §6.4-F2 (`opts.profile` declined, `SimInvariants.check` 4.1 ms, `field_range` not provided), run `test_sim_map` / `test_sim_free` in T0, and make `QaSimAdapter` resolve `report_at(t).parts` with `checksum_part_names()`.
