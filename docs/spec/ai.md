# MERIDIAN FRACTURE — Skirmish AI Specification

> **Domain:** Skirmish AI (`game/src/ai/**`, `game/data/balance/ai/**`, AI tests/harness). **Binding parents:** `docs/ARCHITECTURE.md` v0.1 (constitution) and `Input/meridian_agent_reference/*` (bible).
> **Status:** spec v1.1 (2026-09-29). Written concurrently with the sim/data/map/net specs and **aligned with what was published at 14:04**: `net.md` §5.6 (the injected `ai_factory` / thinker contract, XR-13, handicap §5.3.6), `combat.md` §3.7/§6.1 (read helpers, `CMD_*` 40..47) and `data_balance.md` §3 (`DefRoster`, `DefQuery`, `DefPower`, `DefSuperweapon`, `DefNeutral`). Everything else I need from another domain is tagged `ASSUMPTION(domain)` inline and collected in section 13.
> **Conventions:** ticks = sim ticks (`SimConfig.TPS = 20`); `S` = 20 ticks; positions are sub-cell ints (`Fp.CELL = 1024`); `_c` suffix = whole cells; `Qn` = fixed point with n fractional bits (`Q8` = value × 256); `wu` = AI work unit (section 5.2). All bible numbers quoted here are copied from `meridian_factions.json`; AI-only numbers are *tuning* and live in `game/data/balance/ai/ai_tuning.json`, never in code.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**Purpose.** A host-side computer opponent — and mid-game stand-in for a dropped human — that plays **any of the 32 rosters** (8 vanilla + 24 subfactions) through the *same* `SimCommand` pipeline a human uses, at **four difficulty levels** (Easy, Medium, Hard, Brutal), with **doctrine-specific behavior** derived from the bible's `opening`/`counterplay`/`identity` text, an economy that respects the bible's single-queue construction and progressive payment, and full use of **all 48 support powers and 8 superweapons**. It plugs into the lockstep host through net's injected contract `ai_factory(pid, level, style, seed) -> Callable(world, out: Array)` (`net.md` §5.6, XR-13), must run headless, be reproducible per match seed, and cost ≤ 1.5 ms per AI per tick on average.

**I own**
* `game/src/ai/**` (all `Ai*` classes, section 2), `game/data/balance/ai/*.json` (doctrine, difficulty, roles, powers, tuning), the AI-vs-AI soak harness (`game/src/ai/harness/**`, `game/tests/ai_soak_main.gd`, `game/tests/ai/**`, `tools/py/ai_soak_report.py`), AI telemetry/debug-frame formats, AI intent codes, AI regression thresholds.
* `AiFactory` / `AiThinker` — the implementation of net's XR-13 contract (`level_names()`, `style_names()`, seeded private RNG, `(world, out)` thinker).
* The **read adapter** `AiWorldView` — the *only* AI class allowed to touch `SimWorld` — and the **write adapter** `AiCommandBuilder` — the *only* AI class allowed to encode commands (`PackedInt32Array [type, args...]`).

**I do NOT own (and must not edit)**
* Sim state, systems, command validation/execution, pathfinding, steering, target acquisition, abilities (`sim/`), the `SimCommand`/`SimEvent` definitions (I *request* fields, section 13), fog/vision rules.
* Lockstep/session/relay/replay (`net/`) — `NetAiRunner` decides *when* a thinker runs, sanitises its output (size 1..1024, type 0..255, ≤ 64 commands per think), stamps the execution turn and injects it; I only append `PackedInt32Array` commands to the `out` array I am given.
* Map generation and terrain data (`map/`); resolved unit/structure/power numbers and the balance layer (`data/`, `docs/balance`); modifier resolution.
* Any rendering of AI debug data (`view/`, `ui/`): I produce `AiDebugFrame` data only. Lobby widgets/labels (`ui/`, `app/`): I supply label strings in data.
* Match rules such as unit cap, start credits, the `MatchConfig` schema and per-slot `handicap_pct` semantics (net.md 5.3.6 / XR-9); I only supply the AI level/style enumerations, names and the lobby-default handicap for Brutal.

**Design tenets (binding for implementers)**

| # | Tenet | Consequence |
|---|---|---|
| T1 | Same rules as a human | Reads via `AiWorldView`, acts via ordinary commands (raw int arrays through net's injection path), APM-capped, fog-honoring (except Brutal, labelled). Never mutates sim state (a lint test greps `world.` assignments). |
| T2 | Fair by default | Static terrain, start positions and deposit sites are treated as public (lobby map preview); *dynamic* entity info obeys fog. Only **Brutal** cheats: fog-piercing reads and a `handicap_pct = 120` economy bonus (starting credits and harvest/salvage income, net §5.3.6). Camouflage/detection is never cheated. |
| T3 | Data-driven distinctness | One doctrine JSON per faction (8) with four roster overlays each; roles are resolved from bible tags per roster, so the seven "tank moved to T2" rosters and every replaced unit work with no code branch. |
| T4 | Count-budgeted | All time-slicing is by **work units**, never by wall-clock: identical behavior at any simulation speed (headless 30x or real time). |
| T5 | Reproducible | Personality/aggression randomness comes from `AiRng` seeded with the `mix32`-derived per-slot seed net passes to the factory; same seed and same sim ⇒ same command stream. |
| T6 | Robust | Watchdog, command blacklist, safe mode; missing data disables a role, never crashes. |
| T7 | Observable | Telemetry event codes, decision trace ring, overlay frames, soak harness with regression thresholds. |
| T8 | Balance-agnostic | Consumes *resolved* per-player defs; no unit number is hard-coded; all thresholds are tuning data. |

**Scale the AI must cover (from the bible):** 32 rosters, 156 unit defs (104 baseline combat, 48 unique, 4 service), 29 structures, 40 research upgrades (3 per roster), 48 support powers (3 per roster), 8 superweapons (1 per faction), 98 typed modifiers (consumed only through resolved defs).

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All paths under `game/src/ai/` unless stated. One class per file, `Ai*` prefix, every file ≤ ~1500 lines, static typing, `##` docs.

### 2.1 Infrastructure

| Path | class_name | Responsibility |
|---|---|---|
| `ai_types.gd` | `AiTypes` | All enums and constants (section 4). No logic. |
| `ai_factory.gd` | `AiFactory` | Per-match instance built by `app/`: `make(pid, level, style, seed) -> Callable` (net's `ai_factory`), owns `AiSharedData` and the thinker registry, level/style names, Brutal handicap, global CPU governor. |
| `ai_thinker.gd` | `AiThinker` | The `(world, out)` callable for one AI slot: catch-up clock (`dt`), call budget, bootstrap on first think (also used for takeover of a dropped human). |
| `ai_controller.gd` | `AiController` | One AI player's state: owns `AiWorldView`, `AiKnowledge`, `AiBrain`, `AiCommandBuilder`, `AiRng`, `AiScheduler`; `step()` per think. |
| `ai_config.gd` | `AiConfig` | Construction parameters for one AI (pid, difficulty, roster, seed, overrides). |
| `ai_context.gd` | `AiContext` | Per-controller bundle handed to every module (`view, kb, cmd, cfg, diff, pers, rng, shared, brain, tick`). |
| `ai_world_view.gd` | `AiWorldView` | **Sole reader of `SimWorld`.** Fog mode, per-tick caches, batch queries. Subclassable (`AiMockWorldView` in tests). |
| `ai_command_builder.gd` | `AiCommandBuilder` | **Sole encoder of commands** (`PackedInt32Array [type, args...]`). Intent API, APM token bucket, priority classes, per-unit order dedup, chunking, no-effect back-off, stats. |
| `ai_rng.gd` | `AiRng` | Deterministic xorshift32 PRNG + FNV-1a string hash + `mix32` seed helper (independent of `SimRng` and of `net/`). |
| `ai_budget.gd` | `AiBudget` | Work-unit accounting (`left`, `spend`, debt carry). |
| `ai_scheduler.gd` | `AiScheduler` | Fixed slot table: module cadences, phase offsets, quotas, starvation guard. |
| `ai_job.gd` | `AiJob` | Base class for resumable, budgeted jobs (placement search, A*, SW target search). |
| `ai_perf.gd` | `AiPerf` | Diagnostic-only wall-clock sampling (`Time.get_ticks_usec`); output never read by decisions. |
| `ai_telemetry.gd` | `AiTelemetry` | Telemetry event codes + emit helper (harness/log consumer). |
| `ai_debug.gd` | `AiDebug` | Decision trace ring buffer (int reason codes), `AiDebugFrame` builder. |
| `ai_debug_frame.gd` | `AiDebugFrame` | Plain data for overlay rendering (circles/lines/text/heat/panel). |

### 2.2 Data, profiles, evaluation

| Path | class_name | Responsibility |
|---|---|---|
| `ai_data_store.gd` | `AiDataStore` | Loads/merges all JSON in `game/data/balance/ai/` (base + roster overlay patches), exposes typed accessors, computes `ai_data_hash`. |
| `ai_data_validator.gd` | `AiDataValidator` | Static validation of AI JSON vs `GameData` for all 32 rosters (unresolved roles/ids, tier-unreachable steps, missing powers). Used by tests and at load. |
| `ai_shared_data.gd` | `AiSharedData` | Per-match immutable derived data shared by all controllers: coarse route graph, map traits, per-roster role tables and unit profiles. |
| `ai_role_resolver.gd` | `AiRoleResolver` | Bible tags + `ai_roles.json` ⇒ per-roster `role → def indices`, role bitmasks, unit handler masks. |
| `ai_unit_profile.gd` | `AiUnitProfile` | Derived combat profile of a resolved def (hp, dps per armor class, range, speed, value, power). |
| `ai_tech_graph.gd` | `AiTechGraph` | Prerequisite DAG of structures; `missing(def)`, `reachable_tier(role)`. |
| `ai_cond.gd` | `AiCond` | Compiled condition DSL evaluator used by build scripts, targets, research gates. |
| `ai_personality.gd` | `AiPersonality` | Resolved personality vector for one AI (base + overlay + seeded jitter). |
| `ai_difficulty_profile.gd` | `AiDifficultyProfile` | One difficulty row (cadence, APM, cheats, handicaps). |
| `ai_strength.gd` | `AiStrength` | Lanchester-style group strength ratio using `AiUnitProfile`; noise per difficulty. |
| `ai_strength_group.gd` | `AiStrengthGroup` | Aggregated hp/dps-by-armor-class summary of a set of units/structures (input to `AiStrength`). |
| `ai_cluster.gd` | `AiCluster` | Grid-hash clustering and oriented-shape candidate scoring (powers, superweapons, harass targets). |

### 2.3 Knowledge base (blackboard)

| Path | class_name | Responsibility |
|---|---|---|
| `ai_knowledge.gd` | `AiKnowledge` | Blackboard root: owns all tables below; economy stats; primary-enemy selection. |
| `ai_entity_table.gd` | `AiEntityTable` | Struct-of-arrays rows for own entities and for recently seen enemy units. |
| `ai_ghost_table.gd` | `AiGhostTable` | Remembered enemy/neutral structures (last-known state, confidence). |
| `ai_threat_map.gd` | `AiThreatMap` | 8-cell-block threat/influence grid with lazy decay. |
| `ai_enemy_profile.gd` | `AiEnemyProfile` | Per-enemy observed composition shares + roster priors (drives counter-tech). |
| `ai_resource_sites.gd` | `AiResourceSites` | Salvage-deposit fields: reachability, claim state, saturation, expansion sites. |
| `ai_route_graph.gd` | `AiRouteGraph` | 8×8-cell coarse graph per move class; threat-aware A*; choke and disjoint-route detection. |
| `ai_avoid_zones.gd` | `AiAvoidZones` | Time-limited hazard/no-fire/no-build zones (SW impacts, debris, interception zones). |
| `ai_event_ingest.gd` | `AiEventIngest` | Derives AI-internal event records by **diffing per-think snapshots** (the thinker receives no event feed), applies the human-reaction delay, updates the KB. |

### 2.4 Brain and modules

| Path | class_name | Responsibility |
|---|---|---|
| `ai_brain.gd` | `AiBrain` | Owns module instances, the op list, the want list; strategy state (phase/posture). |
| `ai_strategy.gd` | `AiStrategy` | Phase and posture selection, primary-enemy choice, op creation utility scoring. |
| `ai_economy.gd` | `AiEconomy` | Income EMA, collectors, refineries, power upkeep, want allocation with burn-rate gating, spend priorities. |
| `ai_build_planner.gd` | `AiBuildPlanner` | Executes opener script + target tables + dynamic wants for the single construction queue; issues `BUILD_START`/`BUILD_PLACE`. |
| `ai_placer.gd` | `AiPlacer` | Budgeted placement search job with dispersal, threat and role preferences. |
| `ai_tech.gd` | `AiTech` | Tier goals, research queue choice, counter-tech switching, prerequisite rebuild. |
| `ai_production.gd` | `AiProduction` | Per-producer queue refill by composition deficit; rally points; hold/unhold. |
| `ai_composition.gd` | `AiComposition` | Target role shares from doctrine × phase × counter multipliers. |
| `ai_squad.gd` | `AiSquad` | One tactical group (data + helpers). |
| `ai_squad_manager.gd` | `AiSquadManager` | Unit→squad assignment, claim/steal arbitration, centroid/value upkeep. |
| `ai_scout.gd` | `AiScout` | Scout selection, visit lists, explored-grid tracking, camouflage alerts. |
| `ai_defense.gd` | `AiDefense` | Alarms, defend-op spawning, collector protection, static-defense investment wants. |
| `ai_attack_planner.gd` | `AiAttackPlanner` | Target clustering/scoring, wave sizing, launch gating, multi-prong split. |
| `ai_micro.gd` | `AiMicro` | Focus fire, kiting, hold-position for stationary-fire units, per-unit retreat trigger. |
| `ai_repair.gd` | `AiRepair` | Repair points (apron/engineer/tender/power), retreat return logic, structure repair toggles. |
| `ai_unit_handlers.gd` | `AiUnitHandlers` | Special-unit behaviors (deploy/pack, mode switch, loadout, camouflage hold, command-field escort, healer follow, decoys, pucks, masts). |
| `ai_powers.gd` | `AiPowers` | Support-power evaluation loop, reserve/eagerness policy, per-power dispatch. |
| `ai_power_arch.gd` | `AiPowerArch` | Archetype evaluators (`REVEAL`, `STRIKE`, `BUFF`, `REPAIR`, `SMOKE`, `DECOY`, `MARK`, ...). |
| `ai_superweapon.gd` | `AiSuperweapon` | Superweapon build policy, target search job, combo timing, launch. |
| `ai_dispersal.gd` | `AiDispersal` | Reactions to enemy superweapon warnings and hazard zones. |
| `ai_watchdog.gd` | `AiWatchdog` | Stall/loop/error detection, op timeouts, safe mode. |

### 2.5 Operations (`ops/`)

| Path | class_name | Responsibility |
|---|---|---|
| `ops/ai_op.gd` | `AiOp` | Abstract operation (state machine base, squad claims, timeout). |
| `ops/ai_op_attack.gd` | `AiOpAttack` | Wave attack FSM (form → stage → advance → engage → siege → retreat/cleanup). |
| `ops/ai_op_defend.gd` | `AiOpDefend` | Reactive defense at a threatened site. |
| `ops/ai_op_harass.gd` | `AiOpHarass` | Small fast raid group vs collectors/outposts with hit-and-run. |
| `ops/ai_op_expand.gd` | `AiOpExpand` | MCV expansion (build MCV → escort → deploy → refinery/defense cluster) and in-radius refinery expansion. |
| `ops/ai_op_capture.gd` | `AiOpCapture` | Engineer capture of neutral structures; civilian garrison occupation. |
| `ops/ai_op_salvage.gd` | `AiOpSalvage` | African Empire wreck salvage teams. |
| `ops/ai_op_landing.gd` | `AiOpLanding` | Transport/amphibious assault across water (load → cross → unload → land op). |
| `ops/ai_op_naval.gd` | `AiOpNaval` | Fleet patrol/strike/escort. |
| `ops/ai_op_air.gd` | `AiOpAir` | Aircraft sortie cycle (patrol, strike, rearm) and CAS attachment. |
| `ops/ai_op_hunt.gd` | `AiOpHunt` | End-game sweep for remaining enemy structures. |

### 2.6 Harness (`harness/`), data, tests, tools

| Path | class_name | Responsibility |
|---|---|---|
| `harness/ai_soak_runner.gd` | `AiSoakRunner` | Runs matches headless through net's `LOCAL` unpaced pipeline with `AiFactory` (production cadence, sanitisation, latency), shards, repeat-checks; writes results. |
| `harness/ai_match_spec.gd` | `AiMatchSpec` | One match definition (rosters, difficulty, map family/seed, caps). |
| `harness/ai_match_matrix.gd` | `AiMatchMatrix` | Generates preset match lists (pr/smoke/nightly/weekly/arena); derives match seeds. |
| `harness/ai_metrics.gd` | `AiMetrics` | Observer collecting per-match metrics (section 10). |
| `harness/ai_match_result.gd` | `AiMatchResult` | Serializable result record. |
| `game/tests/ai_soak_main.gd` | (script, `extends SceneTree`) | CLI entry: `tools/gd run game/tests/ai_soak_main.gd -- --preset=nightly ...`. |
| `game/tests/ai/ai_mock_world_view.gd` | `AiMockWorldView` | Scriptable `AiWorldView` subclass for unit tests. |
| `game/tests/test_ai_*.gd` | (test classes) | Unit/scenario/determinism tests (section 10). |
| `game/tests/ai/scenarios/*.json`, `game/tests/ai/baselines/ai_baseline.json` | — | Harness scenarios and accepted-metric baselines. |
| `tools/py/ai_soak_report.py` | — | Aggregates result files → `report.md` + verdict vs baseline (stdlib only). |
| `game/data/balance/ai/ai_tuning.json`, `ai_difficulty.json`, `ai_roles.json`, `ai_composition.json`, `ai_powers.json`, `ai_faction_{napc,nec,olm,def,pd,han,ae,sap}.json` | — | Data (section 7). |

Dependency rule: `ai/` depends downward only (`core`, `data`, `map`, `sim`); it never imports `net/` (net injects the factory). `AiWorldView` is the only file that *reads* `SimWorld` (`AiThinker`/`AiController` merely pass the `RefCounted` reference through); `AiCommandBuilder` is the only file that knows command layouts. `game/src/ai/harness/**` is the one exception: it may use `net/` (the `LOCAL` unpaced `NetSession`, `NetSelfTest`) because it *is* a test driver.

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

Signature blocks below omit bodies; a `class_name` line starts a new file. Everything is statically typed; ids are `int`; positions are sub-cell ints unless suffixed `_c`.

### 3.1 Call and tick order (host only)

```
NET (host), inside NetLockstep.on_boundary(E, target)     # E = turn about to begin (tick 2E), target = E + D (input delay D, default 2 turns)
  for pid in ai_pids ascending:
      skip unless (E + pid) % think_period_turns == 0 and sim.is_player_active(pid)      # net.md 5.6; phase-staggered by pid
      cmds = []; thinker.call(sim.world(), cmds)          # == AiThinker.think(world, cmds); reads the state of tick 2E, BEFORE this turn's commands run
      net sanitises (each command size 1..1024, type 0..255; keep <= 64 commands and <= 6144 bytes) and injects `cmds` into the bundle of turn `target` (group id = pid)

AiThinker.think(world, out):
  dt = world.tick - last_think_tick                       # first call: bootstrap_from_world(), dt = 1
  0. view.begin_think(world, dt)                          # bind the SimWorld, invalidate per-think caches (no per-entity work)
  1. AiEventIngest.derive()                               # diff snapshots -> AI-internal event records; human-reaction delay queue (5.3.2)
  2. budget.reset(min(avg_wu * dt, call_cap_wu), call_cap_wu); cmd.begin_think(dt)
  3. scheduler.run(world.tick, dt, budget)                # fixed module order, section 5.2
  4. cmd.flush(out)                                       # appends <= AI_MAX_CMDS_PER_THINK (64) PackedInt32Array commands, class-ordered, token limited
```

* The thinker **never** runs on clients and is **not needed** for replay playback: its commands travel in the turn bundles, are recorded like human ones, and every peer executes them identically (net.md 5.6). AI takeover of a dropped human calls `NetAiRunner.add_ai(pid, TAKEOVER_AI_LEVEL, 0)` → the same factory → the first `think` runs `bootstrap_from_world()`.
* **Cadence.** Net calls each thinker every `think_period_turns` turns (default 5 = 10 ticks). The AI is written for **any** period ≥ 1 turn: a call advances the AI's clock by `dt` ticks, runs every module slot that became due in `(last_tick, tick]` **once**, and scales the call budget with `dt`. Effects that need a finer cadence than the call period degrade gracefully: `micro`/kiting are enabled only when `dt ≤ 4` (5.9.1), `reaction_delay` is rounded up to the next call. **Request 13.16:** per-level periods `[5, 3, 2, 1]` turns (Easy…Brutal) instead of one constant.
* **Execution lag.** A command appended at the boundary of turn E executes at turn E + D, i.e. tick `2E + 2D` (default 4 ticks later). `AI_EXEC_LAG = 6` is the default estimate; `AiCommandBuilder.exec_lag_est` adapts it (EMA of the observed emit→effect delay, clamped 4..20). Every module is idempotent across the window: after issuing, it waits `exec_lag_est + 2` ticks for an observable effect before re-issuing (5.15).
* **No event feed.** `thinker.call` receives only `world`; `world.events` is drained by presentation and is *not* a source. All AI-internal events are derived from state (5.3.2). `NetAiRunner` stops calling defeated players (`is_player_active`), and `AiFactory.release(pid)` frees the thinker.

### 3.2 Factory, thinker, config, controller

```gdscript
class_name AiFactory
extends RefCounted
## One instance per match, built by app/ (AppMatch.make_ai_thinker, XR-14). Handed to net as `opts.ai_factory = factory.make`.
func _init(store: AiDataStore, telemetry: Callable = Callable()) -> void      # telemetry: func(pid: int, code: int, a: int, b: int, tick: int) -> void
func make(pid: int, level: int, style: int, seed: int) -> Callable            # net's ai_factory: returns (world: RefCounted, out: Array) -> void bound to a new AiThinker
func thinker(pid: int) -> AiThinker                                           # null if none (tests, harness, debug overlays)
func release(pid: int) -> void
func state_hash() -> int                                                      # FNV-1a over thinker state hashes, ascending pid
func debug_frame(pid: int) -> AiDebugFrame                                    # null unless the thinker's debug_level >= 2
static func level_count() -> int                                              # 4  (NetSessionOptions.ai_level_count)
static func style_count() -> int                                              # 4  (NetSessionOptions.ai_style_count)
static func level_names() -> PackedStringArray                                # text keys: ai.level.easy|medium|hard|brutal
static func style_names() -> PackedStringArray                                # text keys: ai.style.doctrine|aggressive|defensive|wildcard
static func level_handicap_pct(level: int) -> int                             # lobby default handicap for that level: 100, 100, 100, 120 (Brutal)
static func level_cheat_key(level: int) -> String                             # "" or "ai.cheats.brutal" (label shown next to the level name)
static func takeover_level() -> int                                           # 1 (Medium); equals NetProtocol.TAKEOVER_AI_LEVEL
```

```gdscript
class_name AiThinker
extends RefCounted
func _init(cfg: AiConfig, factory: AiFactory) -> void
func think(world: RefCounted, out: Array) -> void          # the Callable handed to net: appends PackedInt32Array commands (<= 64)
func state_hash() -> int
func debug_snapshot() -> Dictionary
func last_think_us() -> int                                # AiPerf sample (diagnostic only)
```

```gdscript
class_name AiConfig
extends RefCounted
var pid: int = 0
var level: int = AiTypes.Difficulty.MEDIUM          # 0..3
var style: int = 0                                  # 0..3 (5.14.4)
var seed: int = 0                                   # 32-bit, already mixed by net: mix32(match_seed ^ ((pid+1) * 0x9E3779B9))
var debug_level: int = 0                            # 0 off, 1 trace ring, 2 trace + overlay frames
var perf: bool = false                              # enable AiPerf sampling (diagnostic only)
var personality_override: Dictionary = {}           # tests: field -> int
var tuning_override: Dictionary = {}                # harness param sweeps: "dotted.path" -> Variant
```
(The roster is not passed by the factory: the thinker reads `world.players[pid].roster` at its first think.)

```gdscript
class_name AiController
extends RefCounted
var cfg: AiConfig
var ctx: AiContext                    # view, kb, cmd, cfg, diff, pers, rng, shared, brain
func _init(cfg: AiConfig, shared: AiSharedData, store: AiDataStore, telemetry: Callable) -> void
func step(world: RefCounted, dt: int, out: Array) -> void
func bootstrap_from_world() -> void     # derive phase/posture/wants/squads from current state; skips opener steps whose effects already exist
func state_hash() -> int                # AiRng state + script pointer + op/want/squad ids and states + KB counts
func debug_snapshot() -> Dictionary     # human-readable dump for logs/tests
```

### 3.3 `AiWorldView` — the only reader of `SimWorld`

Semantics: all reads are *as-of the tick of the think* (state at tick 2E). It wraps the sim's published read surface — `world.get_entity(id) -> SimEntity` (ids never reused), `world.players[pid]`, `world.data: GameData`, `world.map: MapData`, `world.rel(a, b)`, `SpatialHash.query_circle`, `SimVision.can_see/is_known/decoy_identified`, `SimCombatSystem.ticks_since_combat/dp100/range_max_eff/ammo_of`, `SimAirSortie.pads_free/sortie_state` (combat.md 3.7/3.8) — plus the additions requested in section 13. `SimEntity` exposes `id, def_idx, kind, owner, x, y, prev_x, prev_y, vx, vy, facing, layer, hp, hp_max, radius, container_id, paid_cost, expire_tick, flags, combat, air, carrier`; the view reads those fields directly (member access is cheap) and offers **`read_row`** so the KB fetches an entity in one call. `omniscient == true` only for Brutal: enemy population reads (`visible_enemy_ids`, `enemies_in_circle`) ignore fog **but still honor camouflage/detection**; `cell_visible`, `targetable_now`, `power_target_ok` always use **real** vision because the sim validates commands against real vision. Enemy hidden data (queues, credits, power state) is never readable.

```gdscript
class_name AiWorldView
extends RefCounted
var omniscient: bool = false
func begin_think(world: RefCounted, dt: int) -> void
func tick() -> int
func me() -> int
# --- players / rules
func player_count() -> int
func player_alive(p: int) -> bool
func team_of(p: int) -> int
func is_enemy(p: int) -> bool                     # world.rel(me, p) == REL_ENEMY and alive
func roster_of(p: int) -> int                     # dense roster index (public: shown in lobby)
func credits() -> int
func income_total() -> int                        # cumulative harvest + salvage credits earned (monotonic stat; the AI derives income deltas)
func power_supply() -> int
func power_demand() -> int
func unit_cap() -> int
func unit_count() -> int                          # non-structure entities of me (cap accounting)
func rule_flag(flag: int) -> bool                 # AiTypes.RF_FOG / RF_SUPERWEAPONS / RF_SHARED_VISION
# --- definitions (DefRoster of the player: modifiers + research already applied)
func roster(of_player: int = -1) -> DefRoster
func unit_def(def_idx: int, of_player: int = -1) -> DefUnit
func structure_def(def_idx: int, of_player: int = -1) -> DefStructure
func power_def(power_idx: int) -> DefPower
func research_def(res_idx: int) -> DefResearch
func neutral_def(def_idx: int) -> DefNeutral
# --- own entities (ids ascending; the returned array is borrowed: never write, never keep across thinks)
func own_ids() -> PackedInt32Array
func alive(eid: int) -> bool
func read_row(eid: int, out: PackedInt32Array) -> bool     # out = [def, owner, kind, x, y, vx, vy, hp, hp_max, flags, order_kind, ticks_since_combat, layer, paid_cost, container]; false if gone
func e_def(eid: int) -> int
func e_owner(eid: int) -> int
func e_x(eid: int) -> int
func e_y(eid: int) -> int
func e_hp(eid: int) -> int
func e_hp_max(eid: int) -> int
func e_flags(eid: int) -> int                     # AiTypes.EF_* bits (mapped from SimEntity.flags / components)
func e_order(eid: int) -> int                     # AiTypes.OrderKind
func e_ticks_since_combat(eid: int) -> int        # SimCombatSystem.ticks_since_combat (NAPC apron rule "6 s out of combat", retreat logic)
func e_last_hit(eid: int) -> int                  # tick or -1
func e_last_fire(eid: int) -> int                 # tick or -1 (also valid for visible enemy artillery)
func e_cargo(eid: int) -> int                     # loaded infantry squads
func e_ammo(eid: int) -> int                      # SimCombatSystem.ammo_of; -1 infinite/n.a.
func e_mode(eid: int) -> int                      # deploy/mode/loadout index
# --- enemies (fog-honoring unless omniscient); results appended ascending by id; return count
func visible_enemy_ids(out: PackedInt32Array) -> int          # enemy units AND structures (not allies, not neutral); ascending eid
func enemies_in_circle(x: int, y: int, r: int, out: PackedInt32Array) -> int   # same population, within r sub-cell units of (x, y)
func targetable_now(eid: int) -> bool             # SimVision.can_see(world, me, e)
func cell_visible(cx: int, cy: int) -> bool       # REAL vision, never cheated
func cell_explored(cx: int, cy: int) -> bool
# --- rule validators (mirror CommandSystem validation; used to avoid rejected commands)
func can_build(struct_def: int) -> int            # AiTypes.Rule.*
func can_place(struct_def: int, cx: int, cy: int) -> bool
func can_train(producer_eid: int, unit_def: int) -> int
func can_research(res_def: int) -> int
func power_status(power_def: int) -> int          # AiTypes.PowerStatus.*
func power_ready_tick(power_def: int) -> int
func power_target_ok(power_def: int, x: int, y: int) -> bool   # DefPower.target_vision (ANY / VISIBLE / EXPLORED) against REAL vision
func sw_status() -> int                           # AiTypes.SwStatus (NONE, CHARGING, READY, WARNING)
func sw_ready_tick() -> int
func sw_launcher_eid() -> int
func strategic_warnings(out: PackedInt32Array) -> int          # active warnings, visible to all: [owner, sw_idx, x, y, angle, start_tick, impact_tick] * n
# --- production / construction state
func construction_state(out: PackedInt32Array) -> void   # out = [state, def, progress_pct, ready_def]  state: 0 idle,1 building,2 ready_to_place,3 paused
func queue_of(producer_eid: int, out: PackedInt32Array) -> int   # queued unit defs in order; returns length
func queue_progress_pct(producer_eid: int) -> int
func research_active() -> int                     # def idx or -1
func research_done(res_def: int) -> bool
func pads_free(airfield_eid: int) -> int          # SimAirSortie.pads_free
# --- public map info (treated as public knowledge, T2)
func map_w() -> int
func map_h() -> int
func passable(cx: int, cy: int, move_class: int) -> bool
func region(cx: int, cy: int, move_class: int) -> int      # connected component id, -1 blocked
func is_water(cx: int, cy: int) -> bool
func map_family() -> int                          # AiTypes.MapFamily (OPEN=0, URBAN=1, COAST=2)
func start_positions() -> PackedInt32Array        # [cx0, cy0, cx1, cy1, ...] indexed by start index (players.start)
func deposit_ids(out: PackedInt32Array) -> int    # neutral entities of kind `deposit` (DefNeutral.neutral_kind)
func deposit_x(id: int) -> int
func deposit_y(id: int) -> int
func deposit_left(id: int) -> int                 # remaining credits (regenerating fields report their current stock)
func neutral_ids(out: PackedInt32Array) -> int    # neutral capturable/garrisonable structures (all kinds except deposit)
func wrecks_in_circle(x: int, y: int, r: int, out: PackedInt32Array) -> int     # KIND_WRECK entities
func wreck_info(id: int, out: PackedInt32Array) -> void    # [x, y, paid_cost, expire_tick, def, original_owner]
```

### 3.4 `AiCommandBuilder` — the only encoder of commands

Commands are raw int arrays `PackedInt32Array [type, args...]` (net.md 5.5 / XR-2): `type` in 0..255, size 1..1024, **no pid, sequence number or tag inside** (the host stamps the pid). The builder delegates layout to the sim's command encoders (`ASSUMPTION(sim_core)`: `SimCmd` static constructors returning `PackedInt32Array`, the same arrays `UiCommandBus` submits; the combat block 40..47 is fixed by combat.md 6.1: `CMD_ATTACK 40, ATTACK_MOVE 41, GUARD 42, HOLD 43, FORCE_FIRE 44, SET_STANCE 45, SCUTTLE 46, RETURN_TO_BASE 47`), so a layout change costs exactly one file.

Every method returns `true` if the intent was **queued for emission this think** (`false`: throttled by APM/back-off/blacklist/duplicate). `prio_class`: `0` emergency (dispersal, power/refinery rebuild, SW launch), `1` economy/production, `2` operations, `3` micro. `flush(out)` drains classes in ascending order, at most `AI_MAX_CMDS_PER_THINK = 64` commands, and never a command larger than 1024 ints (unit lists are chunked to ≤ 48 ids). The APM limiter is an integer token bucket in Q8: refill `apm_cap × 256 × dt / 1200` per think (Hard 180, dt 10 ⇒ 384), capacity `cmd_burst × 256`, cost `256` per emitted command (a chunked group order costs 1 per chunk); 30 % of the capacity is reserved for classes 0–1, so emergencies and economy are never starved by micro.

```gdscript
class_name AiCommandBuilder
extends RefCounted
var exec_lag_est: int = AiTypes.AI_EXEC_LAG
func _init(pid: int, diff: AiDifficultyProfile, telemetry: Callable) -> void
func begin_think(dt: int) -> void
func flush(out: Array) -> int                      # appends PackedInt32Array commands; returns the count
func stats() -> Dictionary                         # {intent_code: count, "throttled": n, "no_effect": n}
func note_no_effect(intent: int, key: int, tick: int) -> void   # from effect verification (5.15): back-off, then blacklist
# economy (class 1)
func build_start(struct_def: int, prio_class: int = 1) -> bool
func build_place(struct_def: int, cx: int, cy: int) -> bool
func build_cancel() -> bool
func train(producer_eid: int, unit_def: int, count: int = 1, prio_class: int = 1) -> bool
func train_cancel(producer_eid: int, slot: int) -> bool
func queue_hold(producer_eid: int, hold: bool) -> bool
func research(res_def: int) -> bool
func set_rally(producer_eid: int, x: int, y: int) -> bool
func set_structure_repair(struct_eid: int, on: bool) -> bool
# unit orders (class 2 unless stated; unit lists are chunked to <= 48 ids per command; one order per unit per think, last intent wins)
func move(units: PackedInt32Array, x: int, y: int, queued: bool = false, prio_class: int = 2) -> bool
func attack_move(units: PackedInt32Array, x: int, y: int, queued: bool = false, prio_class: int = 2) -> bool     # CMD_ATTACK_MOVE 41
func attack(units: PackedInt32Array, target_eid: int, queued: bool = false, prio_class: int = 2) -> bool          # CMD_ATTACK 40
func force_fire(units: PackedInt32Array, x: int, y: int, count: int = 0) -> bool                                  # CMD_FORCE_FIRE 44 (target -1 = ground)
func guard(units: PackedInt32Array, target_eid: int, x: int = 0, y: int = 0) -> bool                              # CMD_GUARD 42; target_eid < 0 => guard point
func hold(units: PackedInt32Array, prio_class: int = 2) -> bool                                                   # CMD_HOLD 43 (hold position)
func set_stance(units: PackedInt32Array, stance: int) -> bool                                                     # CMD_SET_STANCE 45 (0..3; hold-fire ambushes)
func stop(units: PackedInt32Array, prio_class: int = 2) -> bool
func scatter(units: PackedInt32Array, prio_class: int = 0) -> bool
func deploy(units: PackedInt32Array) -> bool                       # also deploys an MCV / masts / siege units
func pack(units: PackedInt32Array) -> bool                         # undeploy
func set_mode(units: PackedInt32Array, mode_idx: int) -> bool      # loadout / wing / siege-mobile mode
func use_ability(units: PackedInt32Array, ability_idx: int, x: int, y: int, target_eid: int = -1) -> bool
func load_units(units: PackedInt32Array, transport_eid: int) -> bool
func unload(transport_eid: int, x: int, y: int) -> bool
func garrison(units: PackedInt32Array, building_eid: int) -> bool
func capture(units: PackedInt32Array, target_eid: int) -> bool
func repair(units: PackedInt32Array, target_eid: int) -> bool      # Engineers/Technicians/Tenders/Reclaimers
func salvage(units: PackedInt32Array, wreck_id: int) -> bool
func harvest(units: PackedInt32Array, deposit_id: int) -> bool
func return_to_base(units: PackedInt32Array) -> bool               # CMD_RETURN_TO_BASE 47 (aircraft / drones re-arm)
# powers (class 0)
func use_power(power_def: int, x: int, y: int, angle: int = 0, x2: int = 0, y2: int = 0) -> bool
func launch_superweapon(x: int, y: int, angle: int = 0) -> bool
```

### 3.5 Module, op, job and utility signatures

```gdscript
# Module convention (duck-typed; every AiXxx module in 2.4 implements these):
func setup(ctx: AiContext) -> void
func step(ctx: AiContext, budget: AiBudget) -> void     # must call budget.spend(n) per loop iteration and return when it yields false
func state_hash() -> int

class_name AiOp
extends RefCounted
var id: int = 0
var type: int = AiTypes.OpType.NONE
var state: int = AiTypes.OpState.NEW
var priority: int = 50
var created_tick: int = 0
var next_update_tick: int = 0
var timeout_tick: int = 0
var squads: PackedInt32Array = PackedInt32Array()
var tx: int = 0                     # target position (sub-cell)
var ty: int = 0
var target_ghost: int = -1          # AiGhostTable row or -1
var committed_value: int = 0        # credit value of units claimed at start
func start(ctx: AiContext) -> bool                       # claims units; false => discard op
func update(ctx: AiContext, budget: AiBudget) -> void    # advance FSM, emit intents
func abort(ctx: AiContext, reason: int) -> void          # release squads to RESERVE
func state_hash() -> int

class_name AiJob
extends RefCounted
var done: bool = false
func step(budget: AiBudget) -> void                      # resumable; sets done when finished
func result() -> Variant                                 # valid once done (e.g. PackedInt32Array [cx, cy], route waypoints, [x, y, angle, score])

class_name AiBudget
extends RefCounted
var left: int = 0
var debt: int = 0                                        # overspend (diff bursts), repaid at <= half of the next call budgets
func reset(call_budget: int, call_cap: int) -> void      # call_budget = min(avg_wu * dt, call_cap_wu) (5.2)
func spend(n: int = 1) -> bool                           # true while left > 0
func exhausted() -> bool

class_name AiRng
extends RefCounted
static func hash_str(s: String) -> int                   # FNV-1a 32-bit over UTF-8 bytes
func seed_from(seed: int) -> void                       # state = seed & 0xFFFFFFFF (net already mixed it); 0 => 0x9E3779B9
static func mix32(x: int) -> int                         # murmur3 fmix32 (identical to NetProtocol.mix32): x^=x>>16; x*=0x85EBCA6B; x^=x>>13; x*=0xC2B2AE35; x^=x>>16 (32-bit masked)
static func thinker_seed(match_seed: int, pid: int) -> int   # mix32((match_seed ^ ((pid + 1) * 0x9E3779B9)) & 0xFFFFFFFF) — what net passes to ai_factory; used by the harness and tests
func next_u32() -> int                                   # xorshift32: s^=s<<13; s^=s>>17; s^=s<<5 (all masked to 32 bits)
func range_i(lo: int, hi: int) -> int                    # inclusive, lo + next_u32() % (hi-lo+1)
func chance(pct: int) -> bool                            # range_i(0, 99) < pct
func pick_weighted(weights: PackedInt32Array) -> int     # index; sum==0 => 0
func state() -> int

class_name AiCond
extends RefCounted
static func compile(node: Variant, errors: PackedStringArray) -> AiCond   # node: Dictionary (vocabulary in 5.5.2)
func eval(ctx: AiContext) -> bool

class_name AiStrength
extends RefCounted
# Returns Q8 ratio (attacker strength / defender strength). See 5.3.4.
static func ratio_q8(att: AiStrengthGroup, def: AiStrengthGroup) -> int

class_name AiStrengthGroup
extends RefCounted
var hp: int = 0
var dps_x100_by_class: PackedInt32Array = PackedInt32Array()
var hp_by_class: PackedInt32Array = PackedInt32Array()
var avg_range: int = 0
var value: int = 0

class_name AiCluster
extends RefCounted
func value_grid(ctx: AiContext, enemy_mask: int, out: PackedInt32Array) -> void          # 3-cell blocks
func best_circle(ctx: AiContext, r: int, mode: int, k: int, out: PackedInt32Array) -> void   # out = [x, y, score] * k
func score_shape(ctx: AiContext, shape: Array, x: int, y: int, angle: int, mode: int) -> int
```

### 3.5b Intra-AI interfaces (how modules talk; all ids ints, arrays borrowed unless noted)

```gdscript
class_name AiContext
extends RefCounted
var view: AiWorldView
var kb: AiKnowledge
var cmd: AiCommandBuilder
var cfg: AiConfig
var diff: AiDifficultyProfile
var pers: AiPersonality
var rng: AiRng
var shared: AiSharedData
var brain: AiBrain
var tick: int = 0
var dt: int = 1                            # ticks since the previous think (>= 1)

class_name AiBrain                         # owns the want list, op list, phase/posture
var wants: Array[AiWant]                   # sorted by (prio, created, id); mutated only via the methods below
var ops: Array[AiOp]                       # ascending id
var phase: int                             # AiTypes.Phase
var posture: int                           # AiTypes.Posture
func add_want(w: AiWant) -> int            # returns id; de-duplicates on (kind, def, role, origin, site) and refreshes prio/deadline
func drop_want(id: int) -> void
func add_op(op: AiOp) -> bool              # assigns id, calls op.start(); false => discarded
func op_by_id(id: int) -> AiOp             # null if finished
func overflow() -> bool                    # unit cap >= 85 % or credits > 4000 for 1200 ticks

class_name AiSquadManager
func create(kind: int, op_id: int) -> AiSquad
func claim(role_mask: int, count: int, near_x: int, near_y: int, max_dist: int, prio: int, squad: AiSquad) -> int   # returns units added (5.8.3)
func release(squad_id: int, to_reserve: bool = true) -> void
func squad(id: int) -> AiSquad             # null if gone
func squad_of(eid: int) -> int             # -1 if unassigned
func refresh(budget: AiBudget) -> void     # centroid / value / speed_min upkeep (cursor)

class_name AiKnowledge                     # read API used by every module
func threat_at(x: int, y: int) -> int
func threat_circle(x: int, y: int, r: int) -> int
func enemies_near(x: int, y: int, r: int, out: PackedInt32Array) -> int          # rows of enemy_units (ascending eid)
func ghosts_near(x: int, y: int, r: int, kind_mask: int, out: PackedInt32Array) -> int   # ghost rows
func est_enemy_army_value(pid: int) -> int
func primary_enemy() -> int
func camo_alert(out: PackedInt32Array) -> bool     # fills [x, y, tick] of the latest camouflage alert; false if none

class_name AiRouteGraph
func route(fx: int, fy: int, tx: int, ty: int, move_class: int, threat_weight_q8: int, out: PackedInt32Array) -> int   # waypoints [x0, y0, x1, y1, ...]; returns count (0 = unreachable); resumable via AiJob wrapper
func disjoint_route(fx: int, fy: int, tx: int, ty: int, move_class: int, avoid: PackedInt32Array, out: PackedInt32Array) -> int
func chokes_on(route: PackedInt32Array, out: PackedInt32Array) -> int

class_name AiPlacer
func request(struct_def: int, site_kind: int, hint_x: int, hint_y: int) -> AiJob        # job.result() -> PackedInt32Array [cx, cy] or empty
func blacklist(cx: int, cy: int, until_tick: int) -> void

class_name AiPowerArch
static func evaluate(power_def: int, params: AiPowerParams, ctx: AiContext, out: PackedInt32Array) -> int   # returns benefit (credits-equivalent); out = [x, y, angle, x2, y2]
```

### 3.6 Harness API

```gdscript
class_name AiSoakRunner
extends RefCounted
## Drives net's LOCAL pipeline unpaced (speed_pct = 0, max_ticks_per_poll 64..512, auto_clear_events = true) with an AiFactory,
## so the AI runs with the production cadence, sanitisation and input delay. Metrics are read from session.world() each tick batch.
func run_match(spec: AiMatchSpec) -> AiMatchResult                    # one headless match; never throws
func run_preset(preset: String, shard_i: int, shard_n: int, out_dir: String) -> int   # exit code 0 pass, 1 regression, 2 harness error
func repeat_check(spec: AiMatchSpec) -> bool                          # run twice (NetSelfTest.run_double with the factory), compare cmd_log_hash + final checksum + AiFactory.state_hash

class_name AiMatchSpec
extends RefCounted
var rosters: PackedStringArray = PackedStringArray()
var difficulties: PackedInt32Array = PackedInt32Array()
var teams: PackedInt32Array = PackedInt32Array()
var map_family: int = 0
var map_size: int = 128
var map_seed: int = 0
var match_seed: int = 0
var cap_ticks: int = 30000
var start_credits: int = 7500
var superweapons: bool = true
```

### 3.7 Ownership of memory

* `AiFactory` owns the `AiThinker` registry and `AiSharedData` (built lazily from the first thinker's world; immutable afterwards; thinkers hold read-only references). The factory is a per-match object owned by `app/` (no global state).
* `AiThinker` owns one `AiController`, which owns `AiKnowledge`, `AiBrain` (modules, ops, wants), `AiCommandBuilder`, `AiRng`, `AiScheduler`, `AiPerf`, `AiDebug`.
* `AiWorldView` holds a borrowed `SimWorld` reference for the duration of one think (no ownership, no mutation). Packed arrays returned by it are borrowed for the current call chain.
* Commands are `PackedInt32Array`s created by `AiCommandBuilder` and appended to the caller's `out` array; ownership transfers to net on return; the AI keeps no reference.
* Entity ids are used as opaque keys; combat.md 3.8 guarantees `SimWorld.get_entity(id)` returns null for removed entities and **ids are never reused**, so a stale id in a squad/op is detected by `alive(eid) == false`.

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enums and constants (`AiTypes`)

```gdscript
enum Difficulty { EASY = 0, MEDIUM = 1, HARD = 2, BRUTAL = 3 }
enum Phase { OPENING = 0, BUILDUP = 1, MIDGAME = 2, LATE = 3, DESPERATE = 4 }
enum Posture { TURTLE = 0, BALANCED = 1, AGGRESSIVE = 2, ALL_IN = 3 }
enum Style { PUSH = 0, PRONG = 1, RAID = 2, CREEP = 3, LANDING = 4, AIR = 5, FORTRESS = 6 }
enum Expand { EARLY = 0, DEFENDED = 1, LATE = 2, MINIMAL = 3 }
enum OpType { NONE = 0, ATTACK = 1, DEFEND = 2, HARASS = 3, EXPAND = 4, CAPTURE = 5, SALVAGE = 6, LANDING = 7, NAVAL = 8, AIR = 9, HUNT = 10 }
enum OpState { NEW = 0, FORMING = 1, STAGING = 2, ADVANCING = 3, ENGAGING = 4, SIEGING = 5, RETREATING = 6, CLEANUP = 7, DONE = 8, FAILED = 9 }
enum SquadKind { RESERVE = 0, MAIN = 1, FLANK = 2, DEFENSE = 3, HARASS = 4, SCOUT = 5, AIR_STRIKE = 6, AIR_PATROL = 7, TRANSPORT = 8, NAVAL = 9, ENGINEER = 10, CAPTURE = 11, SALVAGE = 12, EXPANSION = 13, REPAIR = 14 }
enum WantKind { STRUCT = 0, UNIT_ROLE = 1, UNIT_DEF = 2, RESEARCH = 3 }
enum WantOrigin { EMERGENCY = 0, OPENER = 1, TARGET = 2, POWER_GRID = 3, ECONOMY = 4, TECH = 5, COUNTER = 6, DEFENSE = 7, EXPANSION = 8, SUPERWEAPON = 9, ARMY = 10 }
enum WantState { OPEN = 0, ISSUED = 1, DONE = 2, DROPPED = 3 }
enum StructKind { HQ = 0, GENERATOR = 1, REFINERY = 2, BARRACKS = 3, FACTORY = 4, DOCK = 5, RADAR = 6, AIRFIELD = 7, LAB = 8, WATCHTOWER = 9, AT_TURRET = 10, AA_BATTERY = 11, ADV_DEFENSE = 12, SUPERWEAPON = 13, RELAY = 14, OTHER = 15 }
enum Cat { AIR = 0, ARMOR = 1, INFANTRY = 2, ARTILLERY = 3, NAVAL = 4, SUB = 5, CAMO = 6, STATIC_DEF = 7, LIGHT = 8, TRANSPORT = 9, COUNT = 10 }
enum OrderKind { IDLE = 0, MOVE = 1, ATTACK_MOVE = 2, ATTACK = 3, GUARD = 4, DEPLOYING = 5, DEPLOYED = 6, PACKING = 7, LOADING = 8, UNLOADING = 9, HARVEST = 10, REPAIR = 11, CAPTURE = 12, SALVAGE = 13, RETURNING = 14, OTHER = 15 }
enum Rule { OK = 0, NEED_PREREQ = 1, NO_CREDITS = 2, QUEUE_FULL = 3, LIMIT = 4, POWER = 5, UNIT_CAP = 6, NOT_PLACEABLE = 7, BUSY = 8, LOCKED = 9, OTHER = 15 }
enum PowerStatus { READY = 0, COOLDOWN = 1, LOCKED_PREREQ = 2, UNPOWERED = 3, NO_CREDITS = 4 }
enum SwStatus { NONE = 0, CHARGING = 1, READY = 2, WARNING = 3 }
enum TargetRule { ANY = 0, VISIBLE = 1, EXPLORED = 2, OWN_AREA = 3 }       # AI-side mapping of DefPower.target_vision / target_mode (data_balance.md 4)
enum MapFamily { OPEN = 0, URBAN = 1, COAST = 2 }
enum MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2, AMPHIBIOUS = 3, NAVAL = 4, SUBMERGED = 5, AIR = 6 }    # ASSUMPTION(data): mirrors DefEnums.MoveClass / docs/balance/TAXONOMY.md; the AI reads the data enum, this is only a local alias
enum PowerArch { REVEAL = 0, REVEAL_CORRIDOR = 1, STRIKE = 2, BUFF = 3, BUFF_MOVE = 4, PRODUCTION = 5, REPAIR_ZONE = 6, SMOKE = 7, DECOY = 8, MARK = 9, GUARD_STRUCT = 10, CAMO_HOLD = 11, TRANSPORT_BUFF = 12, ECON_BOOST = 13, FIELD_BOOST = 14, ANTI_EMP = 15, SW_MULTI_CIRCLE = 16, SW_DISC_RING = 17, SW_LINE = 18, SW_AREA_DRONES = 19, SW_DROP = 20, SW_SHIELD = 21, SW_DISABLE_ZONE = 22 }
enum Err { NONE = 0, CMD_LOOP = 1, NO_EFFECT = 2, ROLE_MISSING = 3, DATA_MISSING = 4, BUDGET_DEBT = 5, EXCEPTION_BURST = 6, OP_TIMEOUT = 7, STALL_ECON = 8, STALL_QUEUE = 9, STALL_ARMY = 10, STALL_POWER = 11 }
enum Intent { NONE = 0, BUILD_START = 1, BUILD_PLACE = 2, BUILD_CANCEL = 3, TRAIN = 4, TRAIN_CANCEL = 5, QUEUE_HOLD = 6, RESEARCH = 7, SET_RALLY = 8, STRUCT_REPAIR = 9, MOVE = 10, ATTACK_MOVE = 11, ATTACK = 12, FORCE_FIRE = 13, GUARD = 14, STOP = 15, SCATTER = 16, DEPLOY = 17, PACK = 18, SET_MODE = 19, USE_ABILITY = 20, LOAD = 21, UNLOAD = 22, GARRISON = 23, CAPTURE = 24, REPAIR = 25, SALVAGE = 26, HARVEST = 27, RETURN_TO_BASE = 28, USE_POWER = 29, LAUNCH_SW = 30, HOLD = 31, SET_STANCE = 32 }   # section 6.1 (AI-internal codes; wire types are the sim's)
enum Tele { FIRST_SCOUT_SENT = 1, FIRST_BARRACKS = 2, FIRST_FACTORY = 3, FIRST_RADAR = 4, FIRST_LAB = 5, FIRST_TANK = 6, FIRST_AA = 7, FIRST_SIEGE = 8, FIRST_AIRCRAFT = 9, FIRST_NAVAL = 10, SW_STRUCT_DONE = 11, SW_LAUNCHED = 12, POWER_USED = 13, ATTACK_LAUNCHED = 14, ATTACK_CONTACT = 15, ATTACK_ABORTED = 16, EXPANSION_DEPLOYED = 17, DEFEND_STARTED = 18, STALL = 19, CMD_REJECTED = 20, AI_ERROR = 21, TECH_SWITCH = 22, RETREAT_ORDERED = 23, DISPERSAL = 24, SALVAGE_DONE = 25, LANDING_LAUNCHED = 26, PHASE_CHANGE = 27, POSTURE_CHANGE = 28, OPENER_DONE = 29, SAFE_MODE = 30 }   # section 6.3
enum Why { NONE = 0, WANT_ISSUED = 1, BURN_GATED = 2, NO_FUNDS = 3, PREREQ_MISSING = 4, LAUNCH_GATE_RATIO = 5, LAUNCH_GATE_TIME = 6, ABORT_RATIO = 7, RETREAT_HP = 8, POWER_BENEFIT_LOW = 9, POWER_GATE = 10, SW_HOLD = 11, SW_FIRE = 12, BLACKLISTED = 13, REJECTED = 14, THROTTLED = 15 }   # decision-trace reason codes (append-only)
const AI_EXEC_LAG: int = 6
const RF_FOG: int = 1
const RF_SUPERWEAPONS: int = 2
const RF_SHARED_VISION: int = 4
# entity flag bits returned by AiWorldView.e_flags (ASSUMPTION(sim) provides equivalents)
const EF_CAMO: int = 1
const EF_DEPLOYED: int = 2
const EF_EMP: int = 4
const EF_UNPOWERED: int = 8
const EF_UNDER_CONSTRUCTION: int = 16
const EF_GARRISONED: int = 32
const EF_LOADED: int = 64
const EF_DECOY: int = 128        # known decoy (revealed by a detector); AI treats as zero threat
const EF_MOVING: int = 256
const EF_SUPPRESSED: int = 512
const EF_REPAIRING: int = 1024
const EF_HELD: int = 2048
```

**Role bit indices** (`AiUnitProfile.role_mask` is a 64-bit int; a def may carry several roles; rules in 5.5.1):
`0 INFANTRY_BASIC, 1 INFANTRY_AT, 2 INFANTRY_SUPPORT, 3 SCOUT_LIGHT, 4 TANK_MAIN, 5 AA_MOBILE, 6 ARTILLERY, 7 HEAVY, 8 COMMAND_WALKER, 9 FIGHTER, 10 BOMBER, 11 EW_AIR, 12 BOAT_LIGHT, 13 ESCORT_SHIP, 14 SIEGE_SHIP, 15 CARRIER, 16 SUBMARINE, 17 AMPH_TRANSPORT, 18 ENGINEER, 19 COLLECTOR, 20 MCV, 21 LANDING_TRANSPORT, 22 DETECTOR, 23 HEALER, 24 REPAIRER, 25 COMMAND_PROVIDER, 26 SPOTTER, 27 SALVAGER, 28 AMPHIBIOUS, 29 UNMANNED, 30 KITER, 31 STATIONARY_FIRE, 32 COMBAT, 33 STRUCTURE`.

**Unit-handler bit indices** (`handler_mask`; behaviors in 5.9.5): `0 DEPLOY_SIEGE, 1 MODE_SWITCH, 2 LOADOUT, 3 CAMO_HOLD, 4 ESCORT_PROVIDER, 5 HEALER_FOLLOW, 6 REPAIR_FOLLOW, 7 SPOTTER_LINK, 8 AP_INTERCEPT, 9 TRANSPORT_SHUTTLE, 10 SMOKE_ON_RETREAT, 11 DECOY_PLACE, 12 PUCK_PLACE, 13 COVER_DEPLOY, 14 BREACH_ASSAULT, 15 SALVAGE, 16 CARRIER_ESCORT, 17 EW_ESCORT, 18 MAST_DEPLOY, 19 WING_SWITCH, 20 SHOOT_SCOOT, 21 SUB_BOMBARD, 22 LANDING_BONUS, 23 GARRISON_PREF`.

**Doctrine flag bits** (`AiPersonality.flags`; assigned per roster in 5.14): `0 PRESERVE_VEHICLES, 1 APRON_RETREAT, 2 AIR_LOADOUT, 3 AMPHIBIOUS_ROUTES, 4 RELAY_NETWORK, 5 SENSOR_MAST, 6 SIEGE_DEPLOY, 7 SHELTER_COVER, 8 POWER_RICH, 9 SMOKE_RETREAT, 10 COLLECTOR_RAID, 11 DECOYS, 12 COMMAND_FIELD, 13 SALVAGE, 14 GARRISON, 15 CAPTURE_POINTS, 16 DEFENSE_CLUSTER, 17 INTERCEPTOR_ESCORT, 18 OBSERVER_LINK, 19 MODE_SWITCH, 20 CAMO_AMBUSH, 21 TRANSPORT_ASSAULT, 22 REPAIR_TENDERS, 23 TWO_FRONT, 24 SHOOT_SCOOT, 25 STAGED_PUSH`.

### 4.2 Knowledge tables

**`AiEntityTable`** (struct-of-arrays; `count` rows dense; removal = swap-with-last; `row_of: Dictionary[int, int]` maps eid → row; iteration for tie-breaks is always by ascending `eid`, never by row)

| Field | Type | Meaning |
|---|---|---|
| `count` | `int` | live rows |
| `eid`, `def`, `owner` | `PackedInt32Array` | ids |
| `x`, `y` | `PackedInt32Array` | sub-cell position (refreshed ≤ 10 ticks stale) |
| `hp`, `hp_max` | `PackedInt32Array` | hit points |
| `flags` | `PackedInt32Array` | `EF_*` |
| `order` | `PackedInt32Array` | `OrderKind` |
| `last_dmg` | `PackedInt32Array` | last tick damaged (own rows) |
| `squad` | `PackedInt32Array` | `AiSquad.id` or `-1` (own rows) |
| `paid` | `PackedInt32Array` | `SimEntity.paid_cost` (credits actually paid; army value = `paid × hp/hp_max`; wreck payout basis) |
| `role_mask` | `PackedInt64Array` | cached from `AiUnitProfile` |
| `last_seen`, `last_moved` | `PackedInt32Array` | enemy rows: tick last seen / tick position last changed by ≥ 1 cell |

**`AiGhostTable`** (persistent enemy/neutral structures; ≤ 768 rows; row fields as arrays): `eid, def, owner, x, y, last_seen, hp_pct (0..100), flags, conf (0..100), kind (StructKind), value (credits)`. `conf` = 100 when seen this tick, `-1 per 20 ticks` until 30; ghosts are deleted when their cell is visible and the entity is absent/dead, or when an `ENEMY_GONE` record confirms destruction (5.3.2). Seed rows: for each enemy start position a **presumed HQ** ghost with `conf = 30` (start preset guarantees a deployed HQ).

**`AiThreatMap`**: `bw`, `bh` (block = 8 cells, `block_shift = 13`), `threat: PackedInt32Array` (Σ enemy `AiUnitProfile.power` seen in the last sweep), `stamp: PackedInt32Array` (tick of last write). Read value `v(tick) = threat × max(0, 600 − (tick − stamp)) / 600` (integer, linear decay over 600 ticks).

**`AiEnemyProfile`** (one per enemy pid, 8 slots): `seen_value: PackedInt32Array[Cat.COUNT]` (decayed ×7/8 every 200 ticks), `share_q8: PackedInt32Array[Cat.COUNT]` (blend of observation and prior, 5.5.5), `first_seen_tick: PackedInt32Array[Cat.COUNT]` (−1 unseen), `observed_value: int` (total, for prior fade), `air_peak: int`, `arty_fired_recent: int`, `camo_seen: bool`, `sub_seen: bool`, `sw_known_tick: int` (−1 none).

**`AiResourceSites`** rows: `id (deposit id), x, y, left, region_land, region_amph, claimed_refinery_eid (−1), collectors_assigned, path_len_c (from nearest own HQ, −1 unreachable), threat_q8, kind (0 main, 1 near-expansion, 2 far, 3 enemy-side)`.

**`AiAvoidZones`** rows: `shape (0 circle, 1 rect-oriented), x, y, r_or_len, half_width, angle, expire_tick, kind (0 hazard, 1 no_fire_artillery, 2 no_build, 3 slow_debris, 4 friendly_shield)`.

**`AiEconomyStats`**: `income_ema_q8` (credits per second, Q8), `income_per_min`, `gained_window` (credits in current 20-tick window), `spent_total`, `spent_class: PackedInt32Array[11]` (indexed by `WantOrigin`), `power_spent_5min`, `collectors_alive`, `collectors_waiting`, `collectors_idle`, `refineries`, `generators`, `burn_q8` (Σ active line burn), `last_income_tick`, `salvage_income`, `bonus_income`.

### 4.3 Squads, wants, ops, personality, difficulty

**`AiSquad`**: `id: int`, `kind: int (SquadKind)`, `op_id: int (−1)`, `units: PackedInt32Array (ascending eid)`, `cx: int`, `cy: int`, `radius: int`, `value: int`, `hp_frac_q8: int`, `speed_min: int`, `stage_x: int`, `stage_y: int`, `last_cmd_tick: int`, `role_counts: PackedInt32Array[34]`.

**`AiWant`**: `id: int`, `kind: int (WantKind)`, `def: int` (struct/unit/research def or −1), `role: int` (role bit index for `UNIT_ROLE`, else −1), `count: int` (absolute target for structures/roles: "have ≥ count"), `prio: int (0..100, lower first)`, `origin: int`, `created: int`, `deadline: int (0 none)`, `site_x: int`, `site_y: int` (−1 none), `issued_tick: int`, `state: int`, `fail_count: int`, `block_until: int`.

**`AiPersonality`** (all `int`): `aggression, tech, economy` (0..100), `defense_pct` (0..40), `harass_pct, air, naval, siege, infantry` (0..100), `dispersion` (1..6 cells), `micro` (0..100), `style, style_alt` (`Style`), `expand` (`Expand`), `flags` (doctrine bits), `retreat_hp_pct, return_hp_pct` (1..99), `sw_priority` (0..100), `first_attack_jitter_pct` (−15..+25), `wave_interval_jitter_pct` (−20..+20).

**`AiDifficultyProfile`** (`ai_difficulty.json`, 7.1): `id, label, label_cheats, think_period_ticks, micro_period_ticks, apm_cap, cmd_burst, reaction_delay_ticks, idle_tolerance_ticks, queue_depth, place_latency_ticks, opt_step_keep_pct, info_omniscient (bool), scout_level, expansions_max, collector_k_x10, tech_delay_x100, first_attack_min_s, wave_interval_s, launch_ratio_x100, est_noise_pct, micro_retreat, micro_focus, micro_kite, dodge_pct, powers_level, sw_min_time_s, unit_cap_pct, wu_per_tick, call_cap_wu, jitter_pct, handicap_pct, prongs_max, harass_ops_max, enemy_prior (0 off, 1 air-only, 2 full), eager_pct` (power benefit strictness). `handicap_pct` is only the lobby *default* for the AI slot (100; Brutal 120) — the sim's `players[].handicap` is authoritative.

**`AiUnitProfile`**: `def: int`, `cost: int`, `build_ticks: int`, `hp: int`, `speed: int` (units/tick; `DefUnit.speed`, `speed_water` kept in `speed_water`), `sight: int`, `range: int`, `min_range: int`, `dps_x100: PackedInt32Array` (per armor class: `DefQuery.unit_dps_x100(data, roster, unit_idx, armor)` — Σ weapon slots × damage matrix, damage per second × 100; `0` = cannot hurt), `hits_mask: int` (layer bits GROUND=1, AIR=2, SURFACE=4, UNDERWATER=8), `armor_class: int`, `layer: int`, `move_class: int`, `tag_mask: int`, `role_mask: int (64-bit)`, `handler_mask: int`, `transport_cap: int`, `deploy_ticks: int`, `mode_count: int`, `splash_r: int`, `value: int` (= `cost`), `power: int` (= `Fp.isqrt(hp × dps_avg_x100 / 100)`).

**`AiPowerParams`** (from `ai_powers.json`): `arch: int`, `sel_mask: int` (tag mask of eligible units), `eff_q8: int`, `dur_ticks: int`, `r_units: int` (0 ⇒ take from `DefPower`), `min_ratio_x100: int`, `min_gap_ticks: int`, `gate: PackedStringArray`, `util_value: int`, `purpose: int`, `emergency: bool` (bypasses the power-spend cap: Redundant Orders, Emergency Fortification, Trident counter-cast), `extras: Dictionary`.

**`AiDebugFrame`**: `pid: int`, `tick: int`, `circles: PackedInt32Array` (stride 5: `x, y, r, argb, label_idx`), `lines: PackedInt32Array` (stride 5: `x0, y0, x1, y1, argb`), `labels: PackedStringArray`, `heat_w: int`, `heat_h: int`, `heat: PackedInt32Array` (threat blocks, 0..255), `panel: PackedStringArray` (`"key: value"` lines).

**`AiMatchResult`** (JSON-serializable): `spec_hash, ai_data_hash, engine_version, ticks, winner_team, adjudicated: bool, score: Array[int], per_player: Array[Dictionary]` where each has `pid, roster_id, difficulty, telemetry_first: {code: tick}`, `income_curve: PackedInt32Array` (credits gained per 60 s window), `idle: {construction, production, research, army}` (Q8 ratios), `stalls: {code: count}`, `errors: {code: count}`, `cmds: {intent: count}`, `rejected: int`, `ai_us_avg: int`, `ai_us_p99: int`, `cmd_log_hash: int`, `final_checksum: int`.

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Layered goal architecture

```
                 +--------------------------- AiKnowledge (blackboard) ---------------------------+
                 | own/enemy entity tables · ghosts · threat map · enemy profile · resource sites   |
                 | route graph · avoid zones · economy stats · attack history · primary enemy       |
                 +-------------^------------------------^---------------------------^-------------+
 STRATEGY  (AiStrategy, every 40 ticks)   ──►  OPERATIONS (AiOp*, each on its own cadence)  ──►  TASKS (AiWant + module jobs)  ──►  INTENTS (AiCommandBuilder)  ──►  SimCommand
 phase · posture · primary enemy · utility        attack · defend · harass · expand · capture ·      structure/unit/research wants,        move/attack/train/build/...      via sink
 scoring of candidate operations                  salvage · landing · naval · air · hunt             placement, rally, micro, powers
```

* **Strategy** chooses phase (`OPENING/BUILDUP/MIDGAME/LATE/DESPERATE`), posture (`TURTLE/BALANCED/AGGRESSIVE/ALL_IN`) and *which* operation to start by utility scoring (5.7). It never issues unit orders.
* **Operations** are finite-state machines that own **squads** (claimed through `AiSquadManager`) and emit unit intents at their cadence (Hard: every 10 ticks; micro 4).
* **Tasks** are the economy pipeline: `AiWant`s (what to build/train/research and why) allocated by `AiEconomy`, executed by `AiBuildPlanner`/`AiProduction`/`AiTech`; plus resumable `AiJob`s (placement, routing, superweapon search).
* **Doctrine data** (5.5, 5.14) parameterizes all three layers: opener script and target tables feed wants; composition weights feed production; personality feeds strategy and ops.
* **Module order in a tick** is fixed (5.2). Modules communicate only through `AiKnowledge`, the want list, the op list and squads — never by calling each other's internals.

### 5.2 Scheduling and count-based time slicing (the 1.5 ms budget)

**Work unit (wu).** One wu ≈ 3 µs on an M-class core ≈ one loop iteration over an entity/ghost/cell/candidate with ≤ 8 simple statements, or ≤ 2 `AiWorldView` accessor calls. Charges: entity/ghost/cell visit = 1; accessor group = 1 per 2 calls; `can_place`/`can_train`/`can_build` validation = 5; sort of n items = `n`; A* node expansion = 2. Modules call `budget.spend(n)` **before** doing the work and stop when it returns `false`. No decision depends on wall-clock (T4).

**Budget.** `wu_per_tick` (avg): Easy 220 · Medium 350 · Hard 500 · Brutal 600. A think that advances the clock by `dt` ticks receives `call_budget = min(avg × dt, call_cap_wu)` with `call_cap_wu` ≤ 3000 (≈ 9 ms: below net's 12 ms "throttle twice" threshold, so the runner never doubles the period). `AiFactory` is the global governor: it divides a match-wide 2400 wu/tick among live thinkers, so per-AI `avg = min(profile, 2400 / n_ai)` (8 AIs ⇒ 300). The average per tick is therefore `≤ avg × 3 µs` (Hard 1.5 ms) regardless of the call period; the cap only bounds the tail. Integer semantics (no carry between thinks — `dt` already scales the budget):

```
reset(call_budget, call_cap):  pay = min(debt, call_budget / 2);  debt -= pay;  left = min(call_cap, call_budget - pay)
spend(n):                      left -= n;  if left < 0: debt += -left; left = 0;  return left > 0
```
(Diff/event bursts may overspend: the overshoot becomes `debt`, repaid at ≤ half of the next call budgets, so the *average* holds.)

**Slot table** (fixed; evaluated in this order in every think; a slot is *due* when at least one multiple of its period — offset by `slot.phase` — lies in `(last_tick, tick]`, and a due slot runs **once** per think with quota `quota × min(4, ceil(dt / period))`; net already staggers thinkers by pid so no pid offset is needed; `think` = `think_period_ticks` (Easy 30, Medium 20, Hard 10, Brutal 6); `think2 = max(5, think/2)`; `micro` = `micro_period_ticks`, 0 disables; the effective cadence of a slot is `max(period, call interval)`):

| # | Slot (module) | Period | Base phase | Quota (wu) | Notes |
|---|---|---|---|---|---|
| 0 | Ingest: change detection (5.3.2), own-table rolling refresh, enemy sweep | 1 | 0 | 120 | own units re-read at least every 10 ticks, own structures every 40 (rolling cursor); the sweep slows (cursor) when the quota is hit |
| 1 | KB upkeep: ghost validation, profile decay, resource sites, explored grid | 5 | 1 | 40 | cursor-based |
| 2 | Watchdog | 100 | 7 | 20 | 5.15 |
| 3 | Dispersal (SW warnings, hazard zones) | 2 | 0 | 40 | class-0 commands |
| 4 | Economy (income EMA, collectors, want allocation) | think | 2 | 50 | |
| 5 | BuildPlanner (+ `AiPlacer` job steps while a placement job is open) | think | 4 | 80 (+40 per elapsed tick, ≤ 160) | |
| 6 | Tech (tier goals, research, counter-tech) | 40 | 6 | 30 | |
| 7 | Production (queue refill, rally) | think2 | 3 | 60 | |
| 8 | Strategy (phase/posture/op utility) | 40 | 8 | 60 | |
| 9 | Defense (alarms, defend ops, defense wants) | 10 | 5 | 40 | |
| 10 | AttackPlanner (target scoring, wave launch) | think × 4 | 9 | 60 | |
| 11 | Ops (updates every op whose `next_update_tick <= tick`, ascending id) | 1 | 0 | 80 | |
| 12 | Powers + Superweapon (+ SW target job steps while open) | 10 | 7 | 60 (+40 per elapsed tick, ≤ 160) | |
| 13 | Micro (focus/kite/hold/retreat triggers; ≤ 24 units/tick) | micro | 1 | 60 | |
| 14 | Repair, Engineers, Scout | 20 | 11 | 40 | |

**Starvation guard.** A due slot skipped for lack of budget is marked `late`; late slots run first in the next think; after 3 consecutive skips the slot's `quota` is pre-reserved at the start of the think. Every module keeps a `_cursor` so partial passes resume where they stopped; a full pass must complete within `2 × period` for correctness-critical modules (Ingest, Economy, Production, Dispersal) — the watchdog flags `Err.BUDGET_DEBT` if a module's pass takes > 4 periods.

### 5.3 Information and knowledge

#### 5.3.1 Fog policy (T2)
* **Public (all difficulties):** terrain passability/regions/water, start positions (`start_positions()`), deposit sites, neutral-structure placements, opponents' rosters (lobby-visible), rules (unit cap, superweapons on/off).
* **Fogged:** all enemy entities, enemy queues/credits/power (never readable), enemy powers in flight outside my vision. Enemy *structures* are remembered as ghosts (5.3.2).
* **Brutal (`info_omniscient = true`):** `visible_enemy_ids` / `enemies_in_circle` ignore fog, **not** camouflage/detection (an undetected camouflaged unit stays invisible). Before every `attack(units, eid)` the AI requires `targetable_now(eid)` (real vision); otherwise it uses `attack_move` to the position. Power targets always use `power_target_ok` (real vision or `TargetRule` exemption).
* Reading an enemy's hp/position/def when visible is allowed (a human sees health bars); reading enemy production, credits, cooldowns or upgrades is not.

#### 5.3.2 Change detection (no event feed) and reaction delay
`thinker.call` receives only the world (3.1) and `world.events` is drained by presentation, so `AiEventIngest` **derives every AI-internal event from state**, using the tables it keeps anyway. Each record is an int tuple; "alert" records pass through the human-reaction queue, "state" records do not.

| Record (fields) | Derived from | Class |
|---|---|---|
| `OWN_SPAWNED` / `OWN_LOST` (`eid, def, x, y, paid`) | ordered merge of `own_ids()` against the own table (both ascending) | state |
| `OWN_DAMAGED` (`eid, dhp, since_combat`) | `hp` drop between two refreshes; `e_last_hit` | alert |
| `UNSEEN_HIT` (`x, y`) | an own entity lost hp **and** no visible enemy within `max_range + 2 cells` of it | alert |
| `ENEMY_SEEN` / `ENEMY_GONE` (`eid, def, x, y`) | diff of consecutive `visible_enemy_ids()` sweeps; *gone* = absent while its last cell is currently visible ⇒ presumed dead (units) or destroyed (ghost removed) | alert |
| `ENEMY_ARTY_FIRED` (`eid, x, y`) | a visible enemy with the ARTILLERY role whose `e_last_fire` is within 160 ticks | alert |
| `WRECK_SEEN` (`id, x, y, paid, expire`) | `wrecks_in_circle` scans around the army and salvagers (AE only) | alert |
| `SW_WARNING` (`owner, sw, x, y, angle, start, impact`) | `strategic_warnings(out)` (global, never fogged) | alert |
| `POWER_STATE`, `INCOME`, `RESEARCH_DONE`, `CONSTRUCTION_READY`, `PRODUCTION_DONE` | direct polls: `power_supply/demand`, `income_total()` deltas, `research_done`, `construction_state`, queue lengths | state |
| `PLAYER_DEFEATED` | `player_alive(p)` flips | state |

1. **Reaction delay.** Alert records get `ready_tick = tick + reaction_delay_ticks` (Easy 60, Medium 30, Hard 12, Brutal 4), rounded up to the next think — this *is* the human-reaction model, including for superweapon warnings. State records are applied immediately (the AI polls them anyway; its economy latency is `place_latency_ticks` / `idle_tolerance_ticks`, not `reaction_delay`).
2. **Own table refresh (rolling cursor):** per think `ceil(units × dt / 10)` unit rows and `ceil(structures × dt / 40)` structure rows via `read_row` (3 wu/row), so every unit is re-read at least every 10 ticks whatever the call period.
3. **Enemy sweep:** once per think `visible_enemy_ids(buf)` (the sim caches it per tick), processed in slices: units → `enemy_units` row (`last_seen`, `last_moved` from `vx, vy`/position change), structures → ghost `upsert`, threat map `add_sighting(x, y, power)`, profile `seen_value[cat] += paid`. Unit rows unseen for 100 ticks are dropped.
4. **Ghost validation** (slot 1): a ghost whose cell is currently visible (`cell_visible`) while its entity is not in the visible set ⇒ delete; `conf` decays 1 per 20 ticks to a floor of 30; `hp_pct` is frozen at the last sighting. (The sim keeps its own remembered-structure ghosts for attack orders, `SimVision.is_known`; the AI keeps a separate table because it needs to enumerate them.)
5. **Unseen-attacker alerts:** ≥ 3 `UNSEEN_HIT` within 200 ticks inside a 6-cell radius raise `camo_alert(x, y)` (drives detectors and recon powers, 5.5.5, 5.12).

#### 5.3.3 Threat map
Blocks of 8 cells (`x >> 13`). Each *sweep* (one full pass over the visible enemy list) accumulates `frame[block] += profile.power` for armed enemies (structures with weapons count at their `power`); at sweep end `stored = max(decayed_stored, frame)`, `stamp = tick`. `threat_at(x, y, t) = stored × max(0, 600 − (t − stamp)) / 600`. Queries: `threat_circle(x, y, r)` sums blocks overlapped (≤ 9 for r ≤ 12 cells). Defensive structures are also written from ghosts at `conf/100` weight so unseen-but-known defenses keep the map warm. Consumers: routing cost, staging point choice, expansion site choice, harass safety, placement.

#### 5.3.4 Strength estimation (`AiStrength`)
Group summary: `hp = Σ hp_i` (current), `hp_by_class[c]`, `dps_x100_by_class[c] = Σ dps_x100_i[c]`, `avg_range` (dps-weighted), `value`.

```
share_c(D)  = hp_by_class_D[c] * 256 / hp_D                         # Q8, defender's armor mix
dpsA     = Σ_c share_c(D) * dps_x100_A[c] >> 8                    # A's effective damage/s vs D's mix (layers it cannot hit contribute 0)
dpsD     = Σ_c share_c(A) * dps_x100_D[c] >> 8                    # symmetric
f_range     = clamp(256 + 8 * (range_A_c - range_D_c), 205, 320)   # ~3 % per cell of range advantage
dpsA     = dpsA * f_range >> 8 ;  dpsD = dpsD * (256 + 256*home_adv_pct/100) >> 8   # defender home advantage (tuning 10 %)
arty screen : if artillery dps share of A > 40 % and non-artillery hp share of A < 30 % : dpsA = dpsA * 205 >> 8
R_q8        = hp_A * dpsA * 256 / max(1, hp_D * dpsD)          # Lanchester-square ratio; defender dps == 0 -> 16*256
R_q8        = R_q8 * (256 + noise_q8) >> 8                           # noise_q8 in [-n, +n], n = est_noise_pct*256/100, drawn once per (target, 200-tick epoch) as hash(epoch, target_row) so it does not flicker
```
Magnitudes: `hp ≤ 2×10^5`, `dps_x100 ≤ 2×10^6` ⇒ product `≤ 4×10^11 × 256 ≈ 10^14 < 2^62` (DR-5 safe). All `dps` terms share the same ×100 scale, so ratios are scale-free (the worked example below uses plain dps).
**Defender group** for a target = ghost/visible units within 16 cells of the target + defensive structures within their own range of the target + `assumed_reserve`: if the target's info is stale (> 60 s) add `unseen_reserve_pct` (35 %) of seen value + `assumed_base_value(t) = a0 + a1 * t_min` (tuning: 1500 + 900/min) when nothing was ever scouted.
**Worked example** (illustrative numbers, `ASSUMPTION(balance)`): A = 10 tanks (hp 800, dps 45 each): `hp_A = 8000`, `dps_A = 450`. D = 6 tanks (hp 900, dps 50) + 2 AT turrets (hp 1000, dps 60): `hp_D = 7400`, `dps_D = 420`. Same armor class, ranges equal, no noise: `R_q8 = 8000*450*256/(7400*420) = 296` (1.156 < launch 332 = `130*256/100`) ⇒ **hold**. With 14 tanks: `hp_A = 11200`, `dps_A = 630` ⇒ `R_q8 = 581` (2.27) ⇒ **launch**. (Unit test vector in 10.1.)

#### 5.3.5 Unit profiles (`AiUnitProfile`) — built once per (roster, def) from the roster's resolved `DefUnit`
Read from `DefRoster.unit(idx)` (data_balance.md 3.6/4): `cost, build_ticks, health, speed, speed_water, sight, max_range, min_range, attack_layer_mask, armor_class, move_class, layer_mask, tier, pop, tags, ability_mask, detect_radius, cloak_delay_t, transport_squads`. **`dps_x100[c] = DefQuery.unit_dps_x100(data, roster, idx, c)`** for every armor class `c` (Σ weapon slots × the damage matrix, damage per second ×100; slots active only in another mode are folded into `dps_x100_alt` for units with `deploy`/`mode_switch`, and the profile switches between them with `EF_DEPLOYED`/`e_mode`); splash weapons count ×1.3 vs the infantry class when `splash_radius ≥ 1 cell`. `power = isqrt(hp × dps_avg_x100 / 100)` with `dps_avg` = mean of `dps_x100[c]` over the classes the unit can hit (`0` classes excluded). A unit with no weapon slot has `dps = 0` and counts as non-combat for strength (validator raises `Err.DATA_MISSING` only if a *combat*-tagged unit has none). **Value** = `cost` for defs and `SimEntity.paid_cost × hp/hp_max` for live own units (the wreck payout basis). `kiter` (range ≥ 1.4 × the median enemy `max_range` and `speed ≥ tank speed`) is computed; `stationary_fire` comes from `ai_roles.json → unit_roles.STATIONARY_FIRE` or a weapon-slot flag (`ASSUMPTION(data)`); AI role bits come from `DefTags`/`DefQuery.units_with` (5.5.1).

#### 5.3.6 Primary enemy (FFA/teams)
Every 40 ticks (hysteresis 3600 ticks unless the current primary is eliminated or another scores > current + 25):
`S(e) = (40·prox + 30·weak + 20·host + 10·swt) / 100` (all terms 0..100, integer math) with `prox = 100·256 / (256 + d_c)` where `d_c` = `Fp.dist(my_HQ, e_last_known_HQ) / Fp.CELL` in cells (0 cells ⇒ 100, 100 cells ⇒ 72, 256 cells ⇒ 50), `weak = 100 − 100·est_strength(e) / max_e est_strength` (`est_strength` = `AiStrength` value of e's known army + ghosts), `host = 100` if `e` attacked me in the last 300 s decaying linearly to 0, `swt = 100` if `e` has a known superweapon structure. Ties: lowest pid. Allies (same team) are never targets; the AI answers visible ally entities losing hp (allied vision: `OWN_DAMAGED`-style diffs of allied rows) with a DEFEND op if its own reserve ratio ≥ 1.0 and the site is ≤ 40 cells away (Medium+).

### 5.4 Economy

#### 5.4.1 Model and spending priorities
Bible facts driving the design: **one player-wide construction queue** (structures build strictly sequentially, times fixed: Generator 25 s, Refinery 40 s, Barracks 20 s, Factory 40 s, Radar 30 s, Airfield 35 s, Laboratory 50 s, Dock 40 s, Watchtower 15 s, AT turret 20 s, AA battery 20 s, advanced defense 35 s, superweapon 90 s); **progressive payment** (cost deducted while building; a line pauses at 0 credits); one queue per producer; one research queue; production and research run at 50 % under a power shortage.

*Consequence:* the dominant early-game inefficiency is an idle construction queue or a completed structure waiting for placement; the second is starving parallel lines. The economy therefore reasons in **credits/second burn** and never starts a line the income cannot feed.

`AiWant` origins map to priorities (lower = first): EMERGENCY 0 · OPENER 10 · POWER_GRID 15 · ECONOMY 20 · COUNTER 25 · TECH 30 · ARMY 40 · EXPANSION 50 · DEFENSE 55 (25 while `under_attack` in the last 60 s) · SUPERWEAPON 80. Wants sort by `(prio, created, id)`.

**Allocation (slot 4, every `think` ticks):**
```
income_per_s   = income_ema_q8 >> 8                          # EMA: ema_q8 += ((gained_window << 8) - ema_q8) >> 3 every 20 ticks
burn_cap       = income_per_s + credits / tuning.econ.burn_horizon_s (30)
avail          = credits - reserve                            # reserve = 300 (0 during OPENING)
for w in wants (sorted, state OPEN, now >= w.block_until):
    line_burn = cost(w) * 20 / max(1, build_ticks(w))         # credits per second while the line runs
    if w.prio > 15 and burn_total + line_burn > burn_cap: continue        # lower-priority smaller lines may still fit
    need = min(cost(w), line_burn * 8)                        # 8 s of funding required to start (progressive payment)
    if avail < need: continue
    issue(w); burn_total += line_burn; avail -= need
```
* **Army floor:** after OPENING, if `spent_class[ARMY] / spent_total < 0.45` (Easy 0.35) over the last 300 s and `credits ≥ 800`, ARMY wants get temporary `prio = max(26, prio − 20)`.
* **Hold logic:** if `credits < 100` and `burn_total > income_per_s`, the lowest-priority (prio ≥ 40) *unit/research* lines are `queue_hold(true)`; released when `credits ≥ 400`. Structure lines (single queue) are never held.
* **Construction slot:** STRUCT wants additionally need the single construction slot to be free (nothing building, nothing waiting for placement); at most one STRUCT want is issued per pass, the highest-priority eligible one. **Placement pre-computation:** the `AiPlacer` job for the structure in progress starts at ≥ 80 % progress, so the cell is ready when `CONSTRUCTION_READY` fires and the only delay left is `place_latency_ticks` (+ `AI_EXEC_LAG` per command). Per structure the overhead is therefore ≈ `place_latency + 2·AI_EXEC_LAG` (Hard 22 ticks ⇒ the 5-structure spine costs ≈ 110 ticks on top of 3100).
* **Refund/cancel** is never used except by the watchdog to break a proven deadlock (5.15).

#### 5.4.2 Power upkeep
`margin = supply − demand`. Before starting any structure with `power_delta = d` (negative consumes): require `margin − Σ pending_delta − |d| ≥ margin_min` (Easy 0, Medium 10, Hard 20, Brutal 20; `+200` when the superweapon is pending). Otherwise a **Generator** want is inserted at `POWER_GRID (15)` with `site_hint` back-side. Shortage (`supply < demand`) ⇒ EMERGENCY Generator (prio 0), and all non-emergency structure wants pause until margin ≥ 0. Because production/research run at 50 %, powered defenses stop, powers cannot activate and superweapon recharge pauses, **power loss counts as a stall metric** (10.3). `POWER_RICH` rosters (OLM +25 % generator output, Saudi +20 % more) read the *resolved* generator output, so their generator count falls out of the same formula. SAP's 20 s defense reserve is never counted as supply.
Sequence example (bible numbers): Refinery −30, Barracks −10, Factory −40, Radar −40 = −120 ≤ 150 (one Generator). Adding Laboratory −60 and Airfield −40 = −220 > 150 ⇒ second Generator before the Laboratory (`margin_min` 20 ⇒ Generator #2 queued when `150 − 120 − 60 < 20`). Superweapon −200 ⇒ total demand ≈ 420+ ⇒ three Generators (450) before the launcher.

#### 5.4.3 Collectors and refineries
Facts: each Refinery includes **one free Collector** (Collector alone costs 1400; Refinery 1800 ⇒ marginal building cost 400); more Collectors can be bought at a Refinery.
* `collector_target = min(ceil(refineries × collector_k_x10 / 10), Σ claimed_field_slots)` with `collector_k_x10` = 10/15/20/22 (Easy→Brutal) and `slots_per_field` default 3 (`ai_tuning.econ.collector_slots_per_field`; refined at runtime from `AiResourceSites` observations).
* **Prefer Refinery over Collector** when `collectors_waiting / collectors_alive ≥ 40 %` (queueing at the unload point) or when `refineries × 2 < collectors_alive`: a Refinery adds unload capacity *and* a free Collector.
* Buy a Collector (ECONOMY prio 20) when `collectors_alive + queued < target` and `credits ≥ 1400 + reserve`. If `collectors_alive == 0` and income 0 ⇒ EMERGENCY (prio 0) Collector, then Refinery if no Refinery.
* **Protection:** Collectors with `hp_pct < 60` or an armed enemy within 10 cells `move` to the nearest safe Refinery and hold 200 ticks, then `harvest` again; `AiDefense` raises a DEFEND op at the field when ≥ 2 collectors flee. PD collectors are amphibious (70 % speed on water): their reachable field set uses `MoveClass.AMPHIBIOUS`.
* **Idle collectors** (`collectors_idle`): re-`harvest` the nearest field with `left > 0`; if none reachable ⇒ expansion score +20.

#### 5.4.4 Expansion (MCV and in-radius)
Bible facts: buildings must be within the 8-cell build radius of a friendly HQ (a Relay does not extend it); an MCV (3000, T2: Factory + Radar) deploys into an HQ; there is no free deployment income.
* **In-radius expansion** (`expand` step `refinery_site`): place a Refinery at the placeable cell within radius minimizing `path_len_c(cell → nearest unclaimed field)` (must be ≤ 25 cells and same region); escort = `escort_role × escort_n` (NAPC: 2 Guardians).
* **MCV expansion** (`AiOpExpand`) launches when all hold: Radar built; `credits ≥ 4000`; `expansions_active < expansions_max` (Easy 0, Medium 1, Hard 2, Brutal 3); `expand_score ≥ 55`; style timing (`EARLY t ≥ 240 s`, `DEFENDED t ≥ 330 s` and defense cluster affordable, `LATE t ≥ 540 s`, `MINIMAL` never). 
```
expand_score = 30 + (100 - main_field_left_pct)/2 [or +15 after 360 s if unknown]   # main_field_left_pct = 100 * deposit_left / DefNeutral.reward.credits (nominal field size) + economy/4 + (waiting_ratio >= 40% ? 15 : 0)
               - threat_q8(site)/16 - (under_attack_recent ? 30 : 0)
```
* **Site** = unclaimed field `f` with `path_len_c ≤ 70`, in my half (`d(my_start, f) ≤ 1.1 × min_e d(e_start, f)`), `threat_q8` low, in my collectors' move-class region; HQ cell = placeable HQ cell within 4–6 cells of the field centre maximizing distance from the nearest enemy start. Sequence: train MCV (ECONOMY/EXPANSION want) → claim escort (`tank_main × 2`, or `infantry_basic × 3` if no tank) → `move` → `deploy` at site → wants: Refinery (prio 20) + Generator if margin low + (DEFENDED) one AT turret and one Watchtower (prio 55) → op DONE when Refinery completes. Failure (MCV lost, timeout 3600 ticks) ⇒ op FAILED, `block_until = tick + 3600` for that site.

#### 5.4.5 Defense investment
Static defenses are bought to reach a *share of total spend*: `defense_share = clamp(personality.defense_pct, 0, 40) × phase_mult` (`OPENING 0.6, BUILDUP 1.0, MIDGAME 1.0, LATE 0.8`); a defense want is created (prio 55, or 25 if attacked in the last 60 s) whenever `spent_class[DEFENSE] / spent_total < defense_share` **and** a site with unmet coverage need exists.
* **Types:** Watchtower (450, barracks; anti-infantry; detector radius 4) at refineries/outposts vs raids; AT turret (800, factory) toward tank approaches; **AA battery (900, Radar; detector radius 5)** when the air trigger fires (5.5.5): 1 per production cluster + 1 per refinery hub, max 4; **advanced defense** (roster-specific 1800, Radar+Lab) only when `defense_pct ≥ 25` or the base was attacked ≥ 2 times; SW-launcher guard: 1 AA battery + 1 AT turret within 6 cells once the launcher is placed.
* **Advanced defenses (Radar + Laboratory, 1800 each; one per faction)** are placed per their bible weakness: Bulwark Cannon (NAPC, slow traverse, poor vs infantry) and Lance Rail Emplacement (NEC, very long range, long reload) behind a Watchtower/infantry screen; Sunwall Projector (OLM, excellent vs slow targets, poor vs infantry swarms) beside the approach the enemy's slow armor uses; Citadel Mortar (DEF, minimum range) never alone at the perimeter — pair with a Watchtower and AT turret; Sea Spear Battery (PD) and Bastion Missile Tower (SAP) have **no anti-air** and always get an AA battery within 6 cells; Dragon Tooth Launcher (HAN, burst then vulnerable) in overlapping pairs; Forge Cannon (AE, short range) at chokes and beside production.
* **Sites** (`AiPlacer`): ring 5–8 cells from an HQ facing the top-2 approach headings from the route graph (plus chokes on the primary route for URBAN maps), near each Refinery, and around expansion HQs. `DEFENSE_CLUSTER` rosters (SAP, North Korea, Alpine) place clusters of 3 with 2-cell spacing; others place singles with 3-cell spacing.
* **Anti-overinvestment guard** (bible weakness of SAP/Alpine/NK): defense spend is capped at `0.40 × total_spent`, and no defense want is issued while `army_value < 0.5 × est_enemy_army` unless the base is under attack.

#### 5.4.6 Repair spending, unit cap
Structure repair: `set_structure_repair(on)` when `hp_pct < 60` and no armed enemy within 10 cells, or a defense under attack with `credits ≥ 800`; off at 95 %. Unit-vehicle repair spending in 5.9.2. Unit cap: production refill stops at `unit_cap × unit_cap_pct/100 − 6` (reserve for Engineers/Collector/MCV); at ≥ 85 % of that the AI sets `overflow = true` (forces a wave, 5.8.1) and stops queuing units whose value/cost < the army median.

### 5.5 Build orders, roles and tech (data-driven per roster)

#### 5.5.1 Roles resolved from bible tags (`AiRoleResolver`, rules in `ai_roles.json`)
A role is a *bit* on a def; each roster's `role → Array[def_idx]` is resolved from `DefRoster.producible_units` (already ascending by `(tier, cost, index)`, replaced units excluded — so a replaced unit can never be built: bible "A replaced unit cannot also be built") using `DefTags.unit_mask(names)` and `DefQuery.units_with(roster, all_mask, none_mask)`; "lowest tier" picks are simply the first element. Rules (`all` = must have all tags, `none` = must have none):

| Role | Rule | Roster examples |
|---|---|---|
| INFANTRY_BASIC | `all[infantry, combat]`, `none[anti_tank, specialist, detector]` | Rifle Squad, Vanguard, Fortress Guard, Canopy Ranger |
| INFANTRY_AT | `all[infantry, anti_tank]` | Javelin, Spike, Needle, Recoil, Harpoon, Lance, Pike, Kavach |
| INFANTRY_SUPPORT | `all[infantry, specialist]` | Medic, Sapper, Mirage, Signal Officer, Reef Tech, Link Operator, Reclaimer, Pioneer |
| SCOUT_LIGHT | `all[scout, land_vehicle, combat]`, tier ≤ 1 preferred | Pathfinder, Surveyor, Caravan, Mule, Wake, Jade, Mamba, Jackal (+ unique replacements) |
| TANK_MAIN | `all[tank, land_vehicle]`, `none[siege]`, pick lowest tier | Guardian … or **T2** Narwhal, Marte, Ural, Imperial Guard, Shinano, Arjun, Rhino |
| AA_MOBILE | `all[anti_air, land_vehicle]` | Sentinel, Rapier, Crescent, Porcupine, Storm, Firefly, Weaver, Vajra, Dawn, Lagos |
| ARTILLERY | `all[artillery, land_vehicle]`, lowest tier | Paladin, Archer, Sandglass, Anvil, Breaker, Nest, Forge, Monsoon + unique |
| HEAVY | `all[tank, siege]` (T3) | Bastion, Argent, Sunlance, Colossus, Kiln, Elephant + Charlemagne, Ifrit, Bear, Gaj |
| COMMAND_WALKER | `all[command, land_vehicle]` | Dragon, Long |
| FIGHTER / BOMBER / EW_AIR | `all[aircraft, anti_air]` / `all[aircraft, ground_attack]` / `all[aircraft, electronic_warfare]` | Falcon…; Titan, Nightjar, Burya, Silkwing, Hammerhead, Sarus, Osprey, Condor |
| BOAT_LIGHT / ESCORT_SHIP | `all[ship, scout]` / `all[ship, anti_air, anti_submarine]` | patrol boats / Aegis, Horizon, Lantern… |
| SIEGE_SHIP / CARRIER / SUBMARINE | `all[ship, siege]`, `none[submarine, carrier]` / `carrier` / `submarine` | Liberty, Concord, Beacon / Tempest, Emperor, Shogun / Boreal |
| AMPH_TRANSPORT | `all[amphibious, transport]` | Beaver, Fen, Wake, Kancil, Okapi, Naga, Leviathan |
| ENGINEER, COLLECTOR, MCV, LANDING_TRANSPORT | ids `unit.shared.*` | — |
| DETECTOR, AMPHIBIOUS, UNMANNED, COMBAT | tag `detector`, `amphibious`, `unmanned`, `combat` | — |
| HEALER, REPAIRER, COMMAND_PROVIDER, SPOTTER, SALVAGER, STATIONARY_FIRE | explicit `unit_roles` lists in `ai_roles.json` (5.9.5) | Medic; Reef Tech, Lotus, Pioneer; Link Operator, Dragon, Long, Mekong; Mirage, Watchpost, Wedge; Reclaimer, Warden; Javelin/Spike/Kavach |
| KITER | computed by `AiUnitProfile` (5.3.5); an optional `unit_roles.KITER` list overrides | long-range mobile shooters (rail, missile, artillery that can move-fire) |

Missing role for a roster ⇒ `Err.ROLE_MISSING` at load (validator) and the role is excluded from composition (never a crash). `AiTechGraph.reachable_tier(role)` reports the tier at which a role first becomes producible; **the seven rosters whose tank moved to T2 (Canada, Eurocorps, Russia, China, Japan, India, South Africa) report `TANK_MAIN = tier 2`** and their opener scripts must not train `tank_main` before Radar (validator rule V3, 7.7). Those rosters hold the line with `infantry_basic`, `infantry_at`, `scout_light` until Radar, exactly as the bible openers say.

#### 5.5.2 Build-order script DSL (executed by `AiBuildPlanner`)
Each faction file holds `opener` (ordered steps), `targets` (time-gated maintain-count table), `composition`, `research`, `doctrine`, and `rosters` overlays (7.3). **Step fields:** `id` (unique in the merged script), `op` ∈ {`build`, `train`, `research`, `expand`, `scout`, `power`, `set`}, op arguments, `when` (AiCond, default true), `skip_if` (AiCond, default false), `opt` (bool), `parallel` (bool), `prio` (int override), `timeout_s` (default 240).

* `build`: `struct` ∈ {`generator, refinery, barracks, factory, radar, laboratory, airfield, dock, watchtower, at_turret, aa_battery, adv_defense, superweapon, relay`}; `adv_defense`/`superweapon` resolve to the roster faction's def. Optional `site`: `back|front|field|choke|relay_zone`.
* `train`: `role` (or `def` id), `n` = *absolute* "alive + queued ≥ n" (self-healing after losses), optional `from` producer struct.
* `research`: `research` (research id); `expand`: `kind` ∈ {`refinery_site`, `mcv`} + `escort_role`, `escort_n`; `scout`: `target` ∈ {`enemy_start`, `expansions`}; `power`: `power` (power id, cast at first legal moment); `set`: `flag` (doctrine toggle).
* **Pointer semantics.** *Non-parallel* steps run strictly in order: the pointer sits on the first non-parallel step that is not `DONE/SKIPPED`. If its `skip_if` holds it becomes `SKIPPED` (permanently) and the pointer advances; if its `when` does not hold yet it **waits** — blocking later non-parallel steps — until `when` holds or its `timeout_s` elapses (then it is `SKIPPED` and reported); otherwise it executes and blocks until complete. *Parallel* steps (`parallel: true`) are background wants evaluated on every pass regardless of the pointer: they activate as soon as `when` holds (and `skip_if` does not), never block anything, and complete like any other step. **Conditional or optional work that must never stall the spine (Docks, expansions, AA, research) is therefore written `parallel: true`.** Completion: `build` ⇒ one more completed structure of that kind than at activation (or `n` absolute if given); `train` ⇒ alive + queued ≥ n; `research` ⇒ done; `expand` ⇒ op DONE; `scout` ⇒ visited or timeout; `power` ⇒ cast issued. A step that exceeds `timeout_s` (default 240; spine `build` steps 600) is force-completed and reported via `telemetry(STALL, step_id)`.
* **Difficulty:** steps with `opt: true` are dropped with probability `100 − opt_step_keep_pct` %, drawn once per step id at controller init (stable).
* **Targets table** (mid-game): entries `{id, from_s, struct, n, when?}`; every economy tick an entry with `from_s × tech_delay_x100/100 ≤ now` and `have < n` becomes a want (origin TARGET, prio 30, or 20 for refinery).
* **Overlay patch semantics** (deterministic, applied in listed order to a *deep copy* of the faction base): `opener_patch` / `targets_patch`: `{"remove": [ids], "replace": {id: step}, "insert_after": {id: [steps]}, "insert_before": {id: [steps]}, "append": [steps]}`; `composition_patch`: `{phase: {role: weight or null}}`; `personality`: `{field: int}` overrides; `flags_add/flags_remove`; `style`: replaces list; `research_patch`, `power_policy`: merge by id. Every id named in `remove/replace/insert_*` must exist (validator rule V1).

**Condition vocabulary (`AiCond`):** `t_ge_s`, `t_lt_s`, `have {struct|role|def, n}`, `have_lt {…}`, `queued {role|def, n}`, `credits_ge`, `credits_lt`, `income_ge` (credits/min), `power_margin_ge`, `power_margin_lt`, `tier_ge` (1–3, by *completed* structures), `researched` (id), `enemy_seen` (cat within 180 s), `enemy_share_ge {cat, pct}`, `army_value_ge`, `army_units_ge`, `phase_ge`, `posture_is`, `map_trait {name: water|urban|open, ge_pct}`, `roster_has_role`, `flag`, `under_attack`, `dock_placeable`, and combinators `all`, `any`, `not`. Unknown keys are a load error, never silently ignored.

#### 5.5.3 Tech graph and tier goals
`AiTechGraph` nodes are the 29 structures (`DefStructure.requires`/`requires_mask`; readiness via `DefRoster.prereqs_met(requires_mask, owned_mask)`; `DefQuery.tech_path` is the nothing-owned variant used by tests) with edges from `requires_all_structure_ids` (Barracks←Generator, Refinery←Generator, Factory←Refinery, Radar←Factory, Airfield←Radar, Laboratory←Radar, Dock←Refinery(+shoreline), Watchtower←Barracks, AT turret←Factory, AA battery←Radar, advanced defense & superweapon←Radar+Laboratory, Relay←Radar). `missing(def)` returns the ordered list of structures still to build (DFS, dependency order; those already under construction are excluded). A want for a unit/structure with unmet prerequisites is expanded into prerequisite wants at the same priority ("tech pull").
* **Tier goals:** Radar is always wanted (T2 units, Airfield, powers, AA battery); Laboratory (T3 units, advanced defense, superweapon) is wanted from `lab_from_s = 420 × tech_delay_x100/100 × (150 − personality.tech)/100` seconds (tech 50 ⇒ 420 s Hard; tech 65 ⇒ 357 s; tech 30 ⇒ 504 s), or earlier when a role with weight ≥ 15 % needs T3.
* **Losing a prerequisite** pauses dependent unfinished production/research and disables powers: the missing structure becomes an EMERGENCY want (prio 0) until rebuilt; completed research persists and is never re-bought.
* **Docks are never a prerequisite for land/air tech** (bible); Dock wants require `dock_placeable` and a purpose (naval doctrine, water map, or `needs_water`).

#### 5.5.4 Research policy (all 40 upgrades)
One player-wide queue; T2 research 45 s (needs intact Radar), T3 75 s (Radar + Laboratory); costs from the bible. `AiTech` (slot 6) buys the highest-priority *eligible* research when `credits ≥ cost + reserve`, no P0–P2 want is blocked, and nothing is researching. Gate = `when` (`ai_faction_*.json → research[]`); default gate if omitted: "≥ 6 units of the affected role alive".

| Research (cost) | Gate (AI) | Prio |
|---|---|---|
| napc.adaptive_plating (1000) | `have tank_main ≥ 4` and (enemy artillery share ≥ 15 % or explosive share of damage taken ≥ 30 %) | 30 |
| napc.joint_tactical_links (1600) | `have aa_mobile+escort_ship ≥ 2` and infantry ≥ 6 | 60 |
| napc.dispersed_runways (1100, USA) | airfields ≥ 1 and aircraft ≥ 0.75 × pads | 30 |
| napc.sealed_compartments (1000, Canada) | amphibious vehicles ≥ 4 and (map water ≥ 10 % or enemy explosive share ≥ 15 %) | 40 |
| napc.section_logistics (1000, Mexico) | infantry ≥ 12 | 40 |
| nec.sensor_fusion (1100) | detectors ≥ 3 and (camo or air seen) | 45 |
| nec.distributed_control (1700) | relays ≥ 2 (`RELAY_NETWORK`) | 35 |
| nec.dispersed_links (1000, Nordics) | Fen carriers ≥ 2 | 40 |
| nec.shared_fire_solutions (1700, Eurocorps) | Marte+Charlemagne ≥ 6 and relays ≥ 1 | 35 |
| nec.tunnel_workshops (1000, Alpine) | pioneers+engineers ≥ 2 and defenses ≥ 4 | 40 |
| olm.thermal_shrouds (900) | light vehicles ≥ 6 | 55 |
| olm.optical_mesh (1500) | Caravan-class ≥ 3 and `CAMO_AMBUSH` | 60 |
| olm.thermal_reservoirs (1500, Saudi) | Ifrit+Dawn ≥ 4 | 30 |
| olm.distributed_fuel_caches (900, Algeria) | Rover+Scorpion ≥ 6 | 35 |
| olm.harbor_militia (1000, El-Andalus) | Gate Guards ≥ 8 and (Factory or Dock exists) | 40 |
| def.standardized_parts (900) | engineers ≥ 2 and land vehicles ≥ 8 | 45 |
| def.coordinated_barrages (1600) | Anvil/Colossus-class ≥ 4 | 35 |
| def.layered_protection (1500, Russia) | Ural ≥ 4 | 35 |
| def.mobile_dispatch (900, Kazakhstan) | Saker+Steppe ≥ 4 | 35 |
| def.buried_command_lines (1000, N. Korea) | enemy EMP source seen or defenses ≥ 6 | 60 |
| pd.expeditionary_maintenance (1000) | technicians ≥ 2 | 45 |
| pd.integrated_flight_decks (1600) | (airfields ≥ 1 and aircraft ≥ 6) or carriers ≥ 1 | 35 |
| pd.forward_fire_control (1500, Australia) | Outrider ≥ 4 and Wedge ≥ 1 | 30 |
| pd.distributed_beachheads (1000, Indonesia) | technicians ≥ 1 and Kancil ≥ 3 | 40 |
| pd.predictive_maintenance (1700, Japan) | Shinano ≥ 4 or Shogun ≥ 1 | 35 |
| han.resilient_mesh (1000) | unmanned ≥ 8 and enemy EMP seen | 60 |
| han.distributed_cognition (1700) | providers ≥ 1 and unmanned ≥ 8 | 35 |
| han.guard_integration (1600, China) | Imperial Guard ≥ 4 and providers ≥ 1 | 30 |
| han.hidden_relays (1000, Vietnam) | Link Operators ≥ 1 and `CAMO_AMBUSH` | 45 |
| han.modular_servicing (1500, Cambodia) | Lotus Tenders ≥ 2 | 40 |
| ae.recovery_winches (900) | salvagers ≥ 2 | 25 |
| ae.circular_armor (1600) | land vehicles ≥ 8 | 35 |
| ae.municipal_reserves (1000, Nigeria) | Civic Rifle Teams ≥ 8 | 40 |
| ae.watershed_logistics (1000, Kongo) | Okapi ≥ 3 | 45 |
| ae.precision_machining (1700, S. Africa) | Rhino+Protea ≥ 6 | 30 |
| sap.layered_fieldworks (1000) | infantry ≥ 8 and defenses ≥ 3 | 40 |
| sap.reserve_capacitors (1600) | defenses ≥ 6 and (power shortage seen or generators attacked) | 55 |
| sap.integrated_protection (1700, India) | Arjun ≥ 4 | 30 |
| sap.rapid_ferry_drills (900, Thailand) | Naga ≥ 3 | 40 |
| sap.observer_network (1500, Pakistan) | Shaheen ≥ 4 and Watchpost ≥ 1 | 30 |

#### 5.5.5 Counter-tech switching (`AiTech` + `AiComposition`)
`AiEnemyProfile.share_q8[cat]` = share of *seen enemy army value* (decayed ×7/8 every 200 ticks) blended with the **roster prior** (`as_enemy_prior` block of the enemy's faction file; enabled Hard/Brutal fully, Medium air-only, Easy off): `w_prior = max(0, 256 − observed_value × 256 / 6000)`, `share = (obs × (256 − w_prior) + prior × w_prior) >> 8`. A trigger stays active for 300 s after its condition clears (hysteresis). Multipliers apply to composition weights (Q8 in `ai_composition.json → counters`); structure responses become COUNTER wants (prio 25).

| Trigger (Hard thresholds) | Composition response | Structure / other response |
|---|---|---|
| **Air**: `share_air ≥ 15 %` or ≥ 3 aircraft seen within 60 s (`≥ 30 %`: stronger) | AA_MOBILE ×2.0 (×3.0), FIGHTER ×1.6 (×2.2), BOMBER ×0.7 (×0.6) | Radar priority ↑ (AA units are T2); AA battery: 1 per production cluster + 1 per refinery hub, max 4; keep ≥ 2 AA in each MAIN squad |
| **Heavy armor**: `share_armor ≥ 35 %` (tanks + siege tanks + heavy) | INFANTRY_AT ×1.8, BOMBER ×1.3, HEAVY ×1.3, TANK_MAIN ×0.9 | AT turret near approaches; research anti-armor gate opens |
| **Infantry mass**: `share_infantry ≥ 45 %` | INFANTRY_BASIC ×1.4, ARTILLERY ×1.3, INFANTRY_AT ×0.5 | Watchtower at refineries/entrances (anti-infantry, detector 4); avoid clumping |
| **Artillery/siege**: `share_artillery ≥ 20 %` or ≥ 3 artillery fired recently | harass/fast units (KITER, SCOUT_LIGHT, BOMBER) ×1.5; FIGHTER ×1.3 | raid ops target artillery lines; counter-battery powers armed; spread army (no cluster > 12 cells²) |
| **Naval**: `share_naval ≥ 25 %` and I have water exposure | BOMBER ×1.4, ESCORT_SHIP ×1.5 (if naval), INFANTRY_AT ×1.2 | coastal AT turret / advanced defense near shore |
| **Submarine**: any `submarine` tag seen or ≥ 2 unexplained ship losses | ESCORT_SHIP (anti-submarine) ×2.0 | detectors on the fleet |
| **Camouflage**: any camouflaged unit seen or `camo_alert` | DETECTOR-role units ≥ 10 % of army and ≥ 1 per MAIN/FLANK squad | Watchtower/AA battery at key sites (they detect); UAV/scan-type powers (`REVEAL` with detection) fire at the alert cell |
| **Static-defense heavy**: `share_static ≥ 30 %` of known enemy base value | ARTILLERY ×1.6, HEAVY ×1.3, SIEGE_SHIP ×1.3 | superweapon priority ↑ (+20 `sw_priority`) |
| **Light/raid** (`share_light ≥ 40 %`) | AA_MOBILE ×1.2, ARTILLERY (splash) ×1.2, INFANTRY_BASIC ×1.2 | escorts for Collectors, Watchtower at refineries |
| **Landings** (≥ 2 enemy transports seen near coast) | INFANTRY_AT ×1.2 | coast defenses on beaches near my base |

### 5.6 Production and composition

#### 5.6.1 Target shares (`AiComposition`)
`w[r] = base[phase][r] × group_mult(r) × Π counters(r)`; `base` from the roster's merged `composition` (integer weights per phase: `opening, buildup, midgame, late`). `group_mult`: FIGHTER/BOMBER × `air/50`; BOAT/ESCORT/SIEGE_SHIP/CARRIER/SUBMARINE × `naval/50 × water_factor` (`water_factor = clamp(water_ratio/0.15, 0, 1)` and 0 if no placeable Dock); ARTILLERY/HEAVY × `siege/50`; INFANTRY_* × `infantry/50`. Roles with no def in the roster are dropped. Roles whose def is not yet producible keep their weight and raise **tech pull** (5.5.3) when their share ≥ 15 %; *effective* shares are normalized only over currently producible roles: `share_q8[r] = w[r] × 256 / Σ w`.

#### 5.6.2 Queue refill (`AiProduction`, slot 7)
```
value_now[r] = Σ cost × hp_frac over alive units with role r  +  cost of queued items of role r
V            = Σ_r value_now[r]
deficit[r]   = share_q8[r] * max(V, V_floor) / 256 - value_now[r]        # V_floor = 1500 in OPENING, 4000 later
producer p refills when queue_len(p) < queue_depth (1/2/3/3) and (queue_len > 0 or empty for >= idle_tolerance ticks)
r* = argmax deficit[r] among roles producible at p; tie -> lowest role bit index; def* = first def of r* for the roster
p choice for def*: producers of that structure kind with the shortest total queue time, tie -> lowest eid
skip when unit_count >= unit_cap * unit_cap_pct/100 - 6, or a role-specific cap:  aircraft <= pads*3/2, carriers <= 1 per 6 escorts
```
Queue length is 5 max (ARCHITECTURE §12); the AI never fills beyond its `queue_depth`. Rally: on first sight of a producer and every time the staging point moves > 8 cells, `set_rally(producer, stage)`; AA units rally to `stage_aa` (production centroid), artillery to `stage − 3 cells`, docks to the nearest water cell in front of the dock, aircraft none.

#### 5.6.3 Staging point
`stage` = the first route-graph waypoint beyond 10–12 cells from the primary HQ toward the primary enemy, snapped to the nearest passable cell with ≥ 2 passable neighbors and `threat = 0`. Overrides: `RELAY_NETWORK` ⇒ inside a Relay field (radius − 1); `DEFENSE_CLUSTER` ⇒ inside the defense cluster; `RAID` ⇒ toward the nearest exit to the harass target; naval ⇒ dock front. Recomputed every 600 ticks or when the primary enemy changes.

### 5.7 Strategy (`AiStrategy`, slot 8, every 40 ticks)

* **Phase:** `OPENING` until the opener has no active/pending non-optional steps or `t ≥ 300 s` (Easy 420 s); `BUILDUP` until `tier ≥ 2` and `army_units ≥ 10` or `t ≥ 600 s`; `MIDGAME` until `tier == 3` or `t ≥ 1080 s`; `LATE` afterwards; `DESPERATE` when I have no production structure and no MCV, or `income == 0` for ≥ 120 s with credits < 300 (then: deploy any MCV at the safest cell, all-in attack if `army_value > 0`, else hunt-and-hide).
* **Posture:** `ratio_q8 = my_army_value × 256 / max(1, est_enemy_army_value(primary))`; `agg = aggression + clamp((ratio_q8 − 256)/4, −30, +30) + (overflow ? 25 : 0) − (under_attack_severe ? 40 : 0)`; `TURTLE < 25`, `BALANCED < 60`, `AGGRESSIVE < 85`, else `ALL_IN` (only permitted when `ratio_q8 ≥ 512` or `DESPERATE`). Hysteresis: a posture change needs 2 consecutive evaluations.
* **Op selection:** each candidate op type has a utility in 0..100 and a launch threshold; at most one new non-DEFEND op per strategy tick (DEFEND is created immediately by `AiDefense`):
  `ATTACK` = 5.8.1 gate; `HARASS` = `harass_pct + (exposed enemy collectors known ? 30 : 0)` ≥ 40 and count < `harass_ops_max`; `EXPAND` = `expand_score` ≥ 55; `CAPTURE` = neutral capturable within 45 path-cells and a free Engineer; `LANDING` = `needs_water` or (`TRANSPORT_ASSAULT`/`AMPHIBIOUS_ROUTES` flag ∧ transports ≥ 2 ∧ ratio ≥ launch); `NAVAL` = naval share plan met (≥ 3 ships); `AIR` = aircraft ≥ 3 idle and target with acceptable AA threat; `HUNT` = enemy alive ∧ known enemy structures == 0 ∧ `t > 900 s`.
* **Attack history adaptation:** each finished wave stores `(ratio_at_launch, value_lost/value_sent, target_value_destroyed)`. If `value_lost/value_sent > 0.7` and destroyed < 40 % of the target cluster ⇒ `aggression −= 5` (floor 10) and `min_wave_units += 2`; on success (destroyed ≥ 70 % with losses < 40 %) ⇒ `aggression += 3` (cap `base + 15`). Reset never; bounded, so behavior stays within the personality.

### 5.8 Army operations

#### 5.8.1 Attack planning (`AiAttackPlanner`, slot 10)
**Available force F** = COMBAT units in RESERVE squads (excluding COLLECTOR, ENGINEER, MCV, LANDING_TRANSPORT, HEALER/SPOTTER/PROVIDER — these attach to squads later), minus the defense reserve `reserve_frac` (TURTLE 50 %, BALANCED 25 %, AGGRESSIVE 10 %, ALL_IN 0 % of value, kept nearest to the HQ).
**Launch gate** (all): `t ≥ first_attack_min_s × (100 + first_attack_jitter_pct)/100` (once) and afterwards `t − last_wave_end ≥ wave_interval_s × (100 + wave_interval_jitter_pct)/100`; `posture ≥ BALANCED` (TURTLE launches only on `overflow`); `units(F) ≥ min_wave_units = clamp(6 + t_min/2, 6, 24)` (Easy × 0.7); `R_est_q8 ≥ launch_ratio_q8` (`launch_ratio_x100 × 256/100`: 332 for 1.30; Brutal 307); no DEFEND op with priority ≥ 90 active. `overflow = unit_count ≥ 0.85 × cap or credits > 4000 for 1200 ticks`. Easy ignores the ratio after 900 s (it attacks eventually).
**Target selection:** enemy structures/units are clustered (`AiCluster`, ghost within 12 cells of the highest-weight structure). Base weights (× modifiers), per class:

| Target class | Weight | Modifiers |
|---|---|---|
| Superweapon structure | 100 (charging/ready) / 70 | scouted only |
| Generator | 60 | × 1.5 if enemy has ≤ 2 generators (power collapse = 50 % production, defenses off) |
| Refinery | 55 | + 15 for `COLLECTOR_RAID`; × 1.2 if the enemy's only one |
| Radar | 55 | × 1.3 if enemy uses T2+ units |
| Laboratory, Factory, Relay | 50 | Relay only if the enemy is `RELAY_NETWORK` |
| Headquarters | 45 | × 2 if it is the enemy's last known HQ or a presumed one |
| Airfield | 40 | × 1.5 if I face air |
| Dock, Barracks | 30 | — |
| MCV (unit) | 60 | — |
| Collector (unit) | 45 each (max 3) | harass primary |
| Defensive structure | 10 | only when it blocks a cluster (≤ 10 cells) |
```
cluster_weight = Σ w_i ;  def_pen_q8 = min(768, D_est_q8 * 256 / max(1, F_q8)) ;
score = cluster_weight * 65536 / ((256 + path_len_c) * (256 + def_pen_q8))      # = weight x 256/(256+path) x 256/(256+pen); e.g. w 100, path 44 cells, D/F 0.5 (pen 128) -> 56
style bias: RAID +30 % on refinery/collector targets; AIR +20 % on production; CREEP: prefer clusters reachable while keeping ≥ 1 staging point within artillery range.
```
Tie-break: higher score, then lower ghost row, then lower cluster x, y. Then compute `R_est` vs `defenders(target)` (5.3.4).
**Style shaping:** `PUSH` one MAIN squad; `PRONG` MAIN (65 % of value) + FLANK (35 %) on a **second target reachable by a route disjoint from the main route** (`AiRouteGraph.disjoint_route`), FLANK departs so its ETA is main ETA − 10 s (draws defenders); `RAID` waves are HARASS ops (5.8.5) and the MAIN army waits for `overflow`; `CREEP` = ADVANCING in 12-cell leapfrog steps with artillery `DEPLOY` halts (5.9.3); `LANDING` ⇒ `AiOpLanding` when `needs_water` else amphibious-route prong; `AIR` ⇒ `AiOpAir` strikes first, ground follows once AA threat at target < 30 % of strike hp; `FORTRESS` ⇒ attacks only after winning a defense (`R ≥ 1.5`) or on `overflow`. `prongs = min(prongs_max, distinct_routes, style_prongs)`.

#### 5.8.2 Attack op state machine (`AiOpAttack`)
| State | Entry | Actions (each update, Hard: 10 ticks) | Exit |
|---|---|---|---|
| FORMING | launch gate passed; squads claimed | `move` all to `stage`; slow units (min speed) first | ≥ 80 % of units within 6 cells of centroid, or 900 ticks ⇒ ADVANCING |
| ADVANCING | route waypoints `W[0..k]` from `AiRouteGraph.route(threat-aware)`, spacing 12 cells | `attack_move` group to `W[i]`; artillery trails 4 cells; regroup at each waypoint until ≥ 70 % within 8 cells of the lead or 200 ticks; re-plan if route threat rises > 2× | armed enemy visible within 14 cells of centroid ⇒ ENGAGING; arrival ⇒ ENGAGING |
| ENGAGING | contact | `attack_move` at target; focus fire (5.9.1); every 20 ticks recompute local `R_now` vs enemies/defenses within 16 cells | `R_now < abort_ratio` (0.70) or squad value < 40 % of initial ⇒ RETREATING; defenses dominate and artillery present ⇒ SIEGING; target cluster destroyed ⇒ CLEANUP |
| SIEGING | artillery/heavy in range of defenses | `deploy` at 0.95 × range; escorts hold 3–5 cells ahead; re-evaluate every 40 ticks | defenses within siege range destroyed ⇒ ADVANCING (next waypoint/target); enemy sortie beats escorts ⇒ ENGAGING |
| RETREATING | abort | `move` to `repair point` (5.9.2) / stage; pack deployed units | arrival ⇒ DONE (units to RESERVE, `last_wave_end = now`) |
| CLEANUP | target cluster gone | hold ≤ 600 ticks for salvage (AE, 5.11) else ≤ 200; select next cluster (re-run 5.8.1 target score) | new target ⇒ ADVANCING; none ⇒ DONE |
`timeout_tick = created + 12000` (10 min). Abort also if HQ/production is under attack with `T_est` large (the DEFEND op steals squads, 5.8.4).

#### 5.8.3 Squad arbitration (`AiSquadManager`)
Ops call `claim(role_mask, count, near_x, near_y, max_dist, prio)`: candidates = own units with `squad == −1` or in RESERVE, then units of ops with strictly lower `priority` (steal only if the victim op keeps ≥ 60 % of value, or the thief is DEFEND for HQ/production/SW). Selection: nearest (`Fp.dist`), tie by lowest eid. Op priorities: SW response 95 (dispersal, transient) · DEFEND base 90 · DEFEND outpost 70 · ATTACK MAIN 60 · LANDING 60 · ATTACK FLANK 55 · AIR 55 · EXPAND 50 · SALVAGE 50 · HARASS 45 · NAVAL 40 · CAPTURE 40 · HUNT 35.

#### 5.8.4 Defense (`AiDefense`, slot 9)
Sites = each HQ, each Refinery cluster, the superweapon launcher, Radar/Laboratory, expansion HQs. Every 10 ticks: `T_est(site)` = strength of visible armed enemies within 16 cells (unarmed scouts excluded unless ≥ 3). If `T_est > 0` create/refresh `AiOpDefend(site)` requiring `F_def` with `R ≥ 1.3` (defensive structures within range add to my side); claim from RESERVE first, then lower-priority ops within 30 cells. Air threat ⇒ claim AA_MOBILE and FIGHTER first. Collectors near the site flee (5.4.3). If the site is HQ/production/SW and `R_avail < 1.0` after claims, ATTACK ops are recalled (RETREATING to site). DEFEND ends when no armed enemy within 20 cells for 200 ticks; units return to stage. Enemy `SW_WARNING` bypasses this path (5.13.3).

#### 5.8.5 Harass (`AiOpHarass`)
Squad 3–5 fast units (SCOUT_LIGHT, KITER, amphibious transports with INFANTRY_AT passengers for Algeria/Kongo, BOMBER excluded). Targets in order: enemy Collectors (seen in the last 60 s), outlying Refineries, Generators. Safety: abort target if `threat_circle(target, 10 cells) > 0.7 × squad power`. Cycle: approach along the lowest-threat route (avoid `AiThreatMap` peaks and known detector radii for camouflage units), engage ≤ 160 ticks, retreat 15 cells if squad hp < 70 % or enemy response `R < 0.8`, re-enter after 400 ticks. Kill credit counts for adaptation (5.7). Max ops: Easy 0, Medium 1, Hard 2, Brutal 3.

#### 5.8.6 Scouting and hunting (`AiScout`, `AiOpHunt`)
* `scout_level` 0 (Easy): one scout at 300 s to the nearest enemy start; 1 (Medium): first scout from the Barracks/Factory at ≈ 90 s to the nearest enemy start, then expansion sites every 240 s; 2 (Hard): two scouts cycling enemy starts, mid-map deposit fields and unexplored 8-cell blocks (by `cell_explored` sampling 64 blocks per pass), fighters/recon powers when available; 3 (Brutal): omniscient, scouting only for detection alerts.
* Scout safety: `move` (never attack-move); retreat when an armed enemy is within 10 cells; per-target timeout 1800 ticks; skip targets `cell_visible` already.
* **Hunt:** when no enemy structure ghosts remain but the enemy is alive, `AiOpHunt` sweeps unexplored/stale blocks with fast units and aircraft in descending order of `(stale age, distance to enemy start)`, `attack_move` on discovery — this guarantees matches terminate (harness `stalemate` metric, 10.3).

### 5.9 Micro, retreat/repair, special units

#### 5.9.1 Focus fire and kiting (`AiMicro`, Medium+ focus, Hard+ kite)
* Runs every `micro_period_ticks` (effective cadence `max(micro_period, think interval dt)`) for ≤ 24 units per tick of elapsed time (cursor over squads in ENGAGING/SIEGING/DEFEND). **Kiting and per-unit dodging are enabled only when the think interval `dt ≤ 4` ticks** (net period ≤ 2 turns; execution lag ≥ 4 ticks makes finer micro moot); with a coarser cadence the AI keeps focus fire, retreat and hold-position but does not kite.
* **Focus:** for each squad pick `focus` = argmax over visible enemies within `1.2 × squad_avg_range`: `prio = base(class) + (100 − hp_pct)/4 − dist_c`. Bases: command provider 90 · healer 85 · detector (if I field camouflage) 80 · artillery (if within my reach) 75 · anti-tank units (if my squad is ≥ 50 % armor) 70 · AA (if my air is present) 70 · tank 60 · infantry 50 · Collector 45 · defense structure blocking 40 · scout 20 · decoy (`EF_DECOY`) 0. Units already firing at a target with `hp_pct < 25 %` keep it. Emit one `attack(units_subset, eid)` per subset (≤ 4 subsets/squad) when the current order differs.
* **Kite** (units with role KITER, `personality.micro > 0`, ≤ 8 kiters per micro tick): if the nearest enemy that can hit it is within `0.7 × own_range` and `own_speed ≥ enemy_speed`: `move` to `0.9 × own_range` away along the vector from that enemy; re-engage next micro tick. **Stationary-fire units** (Javelin/Spike/Kavach-type "must stop to fire") are *never* kited: they hold behind the front rank at ≥ 4 cells, and `stop` when armor closes within 1.2 × range.
* **Focus of infantry vs suppression:** squads with ≥ 2 `EF_SUPPRESSED` while advancing on a suppressor (Watchtower/Fortress Guard) try `Coordinated Advance`/`Civil Defense Net` (5.12) else route around within 4 cells.

#### 5.9.2 Retreat and repair (`AiRepair`)
* **Per-unit retreat** when `hp_pct < retreat_hp_pct` (default 35; infantry 20; personality `retreat_hp_pct`: NAPC 50 [`PRESERVE_VEHICLES`], AE 40, others 35) and the unit is not expendable (infantry squads with `value < 150` retreat only below 20 %). **Squad retreat** when squad value < 40 % of initial or `R_now < 0.70`.
* **Repair point** by roster mode: `APRON_RETREAT` (NAPC family): within 5 cells of an own Factory (service apron heals 1 %/s up to 75 % after 6 s without combat; `return_hp_pct = 75`); `REPAIR_TENDERS` (Cambodia, PD): beside a Lotus Tender / Reef Technician; default: beside a Factory with Engineers; power-based: the drop location of Field Repair Drop / Workshops / Field Refurbishment (5.12). Units return to the op when `hp_pct ≥ return_hp_pct` (85 default).
* **Engineers:** keep `engineers = clamp(ceil(land_vehicles / 10), 1, 4)` (AE: `salvage_team` counts too); at the repair point each idle Engineer `repair`s the most damaged vehicle whose `value × (1 − hp_frac) ≥ 100` while `credits ≥ 300` (repair costs 0.5 % of paid price per second at 1 %/s; AE pays 25 % less, Cambodia structure repairs +25 % faster).
* **Structures:** 5.4.6.

#### 5.9.3 Deploy / pack / mode rules (`AiUnitHandlers`)
* **Deployables** (`DEPLOY_SIEGE`: artillery, Charlemagne 4 s +25 % range, Ifrit 3 s, Gaj 4 s +20 %, Outrider 3 s, Shaheen 3 s, Ibex 2 s, Monsoon/Paladin 3 s): `deploy` when a target/structure is within `0.95 × (deployed) range`, no armed enemy within 8 cells (or `min_range`), and the op is SIEGING/CREEP-halted or the unit is defending; `pack` when the target is dead and the next is out of range, or enemies come within 60 % of `min_range`/6 cells without escorts. **Leapfrog:** with `STAGED_PUSH`/`CREEP`, at least 50 % of deployables stay deployed while the rest move.
* **Mode switch** (`MODE_SWITCH`): Shinano: siege mode when a structure target is in siege range and no enemy armor within 10 cells, else mobile; Protea: shells when no enemy within 12 cells, canister when enemies ≤ 8 cells; minimum dwell 120 ticks (no oscillation). **Loadout** (Raptor at Airfield): AA when enemy air share ≥ 15 % or air seen in 60 s, else AV. **Wing switch** (Shogun): interceptor wing if enemy air share ≥ 20 %, else strike wing; re-evaluated every 400 ticks.
* Deployed/stationary units are excluded from focus/kite orders while `EF_DEPLOYED`.

#### 5.9.4 Command-field providers (HAN: `COMMAND_FIELD`)
Field-eligible = `UNMANNED` combat units (+ Imperial Guard tanks if `Guard Integration` researched). Field radius 5 (7 with Distributed Cognition; +3 Reserve Bandwidth; +2 Long Walker deployed). Provider placement each micro pass: `coverage = Σ value(eligible within radius) / Σ value(eligible)`; if `< 60 %` move the provider to the value-weighted centroid then 3 cells *behind* it (away from the nearest enemy); keep `providers ≥ ceil(eligible/8)`; assign 2 escorts (GUARD); provider `hp_pct < 50` ⇒ retreat (destroying/suppressing a provider removes the field; bible counterplay). Fields do not stack ⇒ never stack two providers on the same units: spread providers ≥ 2 × radius apart when ≥ 2.

#### 5.9.5 Special-unit handler table
Handler bits are **seeded from `DefUnit.ability_mask`** (abilities_catalog.md 1): `MODE_SWITCH` → `MODE_SWITCH`/`DEPLOY_SIEGE`, `CLOAK` → `CAMO_HOLD`, `ACTIVE_PROTECTION` → `AP_INTERCEPT`, `TRANSPORT` → `TRANSPORT_SHUTTLE`, `DISEMBARK_BUFF` → `LANDING_BONUS`, `CARRIER` → `CARRIER_ESCORT`, `REPAIR_ACTOR` → `REPAIRER`, `SALVAGE` → `SALVAGE`, `AURA` (command field) → `ESCORT_PROVIDER`, `SPAWN_ZONE` → `COVER_DEPLOY` / `DECOY_PLACE` / `SMOKE_ON_RETREAT` by its params — and completed by `ai_roles.json → unit_handlers` where the primitive does not disambiguate the behavior.

**Baseline units with behavior beyond "attack-move":**

| Unit(s) | Handler | AI rule |
|---|---|---|
| Combat Medic (NAPC) | HEALER_FOLLOW | `guard` the largest infantry squad, stay ≤ 3 cells, retreat with wounded |
| Sapper (NEC), Combat Pioneer (SAP) | COVER_DEPLOY + REPAIRER | deploy portable cover (4 s, 20 % bullet resistance, 45 s) when holding ≥ 6 s near enemies within 1.3 × range; Pioneer repairs defenses < 70 % |
| Mirage Observer (OLM) | SPOTTER_LINK, CAMO_HOLD | park stationary ≤ 8 cells from artillery toward the target; camouflage after 6 s; retreat if a detector is within 6 |
| Signal Officer (DEF) | detector support | stays with infantry mass (suppression recovery aura 5 cells) |
| Reef Technician (PD) | REPAIR_FOLLOW | repairs nearest damaged vehicle/ship of its squad, behind the line |
| Link Operator (HAN), Dragon Walker | ESCORT_PROVIDER | 5.9.4 |
| Reclaimer (AE) | SALVAGE | 5.11; repairs a vehicle at engineer rate when idle |
| Aster EW (NEC) | EW_ESCORT | `guard` MAIN centroid; built only when weight > 0 (low) |
| Boreal Missile Submarine (DEF) | SUB_BOMBARD | move within range of a coastal target, fire (surfaces 8 s), withdraw; requires ≥ 2 escorts |
| Leviathan (PD) | TRANSPORT_SHUTTLE | carries 4 squads amphibiously; landing spearhead with its siege cannon |
| Tempest Carrier / Emperor Drone Ship | CARRIER_ESCORT | fleet centerpiece; only built with ≥ 2 escorts; keep escorts ≤ 8 cells |
| Watchtower/AA battery (structures) | detector | camouflage-detection anchors (radius 4 / 5): raids by camouflage units avoid them |

**Unique subfaction units (all 48):**

| Roster / unit | Handler | AI rule |
|---|---|---|
| USA Raptor | LOADOUT | 5.9.3 loadout rule; one loadout per sortie |
| USA Condor | CAMO_HOLD | flights ≥ 3 vs high-value ghost (SW/Lab/Factory) with no detector within 5 cells of the approach; one bomb per sortie, slow rearm |
| Canada Beaver | TRANSPORT_SHUTTLE | detector + 2-squad carrier for secondary/water routes |
| Canada Narwhal | route class AMPH | prefer secondary/water routes; avoid long water legs under fire |
| Mexico Vanguard | COVER_DEPLOY | deploy cover (4 s) when holding near enemies; pack (2 s) to advance |
| Mexico Aguila | BREACH_ASSAULT | escorted (Guardian/Javelin); targets structures (production, blocking defenses); never in open ground alone |
| Nordics Fen | MAST_DEPLOY, TRANSPORT_SHUTTLE | deploy 6-cell mast at the forward stage/expansion; pack if armed enemy ≤ 12 cells |
| Nordics Fjord | SHOOT_SCOOT | after each salvo relocate ≥ 6 cells (fast redeploy); infantry/Rapier screen |
| Eurocorps Marte | TANK_MAIN (T2) | production gated behind Radar; hold until ≥ 3 before ADVANCING |
| Eurocorps Charlemagne | DEPLOY_SIEGE | 4 s, +25 % range, immobile; deploy at 0.9 × deployed range; never with enemies ≤ 8 cells |
| Alpine Pioneer | COVER_DEPLOY, REPAIRER | one shelter per squad (45 s, 25 % bullet resistance); repairs defenses |
| Alpine Ibex | DEPLOY_SIEGE | 2 s; face target, cover rear |
| Saudi Dawn | AA_MOBILE | AA sizing counts × 0.7 vs armored bombers |
| Saudi Ifrit | DEPLOY_SIEGE | 3 s; needs stationary + line of sight; deploy at beam range with clear line, escorted |
| Algeria Dune Rover | CAMO_HOLD | camouflages after 6 s without firing even moving; raids; retreat to re-camouflage when revealed (6 s) |
| Algeria Scorpion | SHOOT_SCOOT | short salvo, long reload: fire, retreat 8 cells, return; harass |
| El-Andalus Gate Guard | GARRISON_PREF | prefer neutral civilian garrisons (+20 % damage); face enemy (25 % frontal shield) |
| El-Andalus Strait Frigate | escort | strong short-range guns, slower; escort role |
| Russia Ural | AP_INTERCEPT | front rank vs missile-heavy enemies, spaced ≥ 3 cells (one interception / 12 s) |
| Russia Bear | heavy | very slow, poor sight/rear: spotters + escort; last in queue |
| Kazakhstan Steppe Carrier | SCOUT | extended sight; detector; scout first |
| Kazakhstan Saker | SHOOT_SCOOT, DEPLOY_SIEGE | 1 s deploy; snipe high-value units (focus table) then withdraw beyond enemy range |
| N. Korea Fortress Guard | COVER_DEPLOY | deploy 3 s (immobile, stronger suppression) only at DEFENSE points (chokes, beside defenses, around Radar/Lab); never in ATTACK ops except SIEGING holds |
| N. Korea Echo Team | DECOY_PLACE | one decoy tank per team every 40 s (30 s) at the base edge facing the approach; detector |
| Australia Outrider | DEPLOY_SIEGE | 3 s, narrow arc: pre-face; relocate when enemies ≤ 1.2 × min_range or counter-battery |
| Australia Wedge | SPOTTER_LINK | detector fighter patrols 8 cells ahead of the artillery; ≥ 1 per 4 Outriders |
| Indonesia Kancil | TRANSPORT_SHUTTLE | −50 % unload time; unload ≤ 3 cells from LZ |
| Indonesia Island Raider | LANDING_BONUS | +20 % damage 6 s after disembark: unload adjacent to target (≤ 5 cells); never reboard |
| Japan Shinano | MODE_SWITCH | 5.9.3; replaces the missing howitzer on land |
| Japan Shogun | WING_SWITCH, CARRIER_ESCORT | 5.9.3; one well-escorted carrier |
| China Imperial Guard | TANK_MAIN (T2) | field-eligible only after Guard Integration |
| China Long Walker | ESCORT_PROVIDER | deploy (3 s, radius +2, immobile) on SIEGING/CREEP halts; pack to move |
| Vietnam Canopy Ranger | CAMO_HOLD | ambush along enemy route ≥ 8 cells from their base; fire at 0.8 × range; hold still when detectors are visible |
| Vietnam Reed | SHOOT_SCOOT | amphibious unmanned artillery, short bursts; field-eligible |
| Cambodia Lotus Tender | REPAIR_FOLLOW | repairs one unmanned unit at 1 %/s, 3 cells behind; ≥ 1 per 6 unmanned; never repairs itself |
| Cambodia Mekong Engineer | ESCORT_PROVIDER, REPAIRER | 2 s deploy for field; repairs structures; detector |
| Nigeria Civic Rifle Team | PUCK_PLACE | sensor puck every 30 s (20 s) on the forward arc or in an unexplored cell; does not detect camouflage |
| Nigeria Lagos Drone Guard | AA_MOBILE | stay ≤ 4 cells from infantry (repair drone 1 %/s) |
| Kongo Okapi | TRANSPORT_SHUTTLE | 3 squads; raids on resource routes; damaged vehicles retreat behind infantry (bible opening) |
| Kongo River Warden | SALVAGE, CAMO_HOLD | salvage team member; camouflaged after 6 s stationary |
| S. Africa Rhino | TANK_MAIN (T2) | long-range AT, second rank ≥ 4 cells behind, paired with infantry (weak vs infantry) |
| S. Africa Protea | MODE_SWITCH | 5.9.3 (min dwell 120 ticks) |
| India Arjun | AP_INTERCEPT | like Ural (15 s) |
| India Gaj | DEPLOY_SIEGE | 4 s, +20 % range, staged pushes |
| Thailand Naga | TRANSPORT_SHUTTLE, SMOKE_ON_RETREAT | smoke (4 cells, 6 s, 40 s cooldown) when carrying and taking direct fire, or retreating |
| Thailand River Marine | LANDING_BONUS | −20 % damage 6 s after disembark: unload under fire near LZ; never reboard |
| Pakistan Shaheen | DEPLOY_SIEGE, SHOOT_SCOOT | 3 s deploy; vulnerable during reload; 2–3 batteries per group from different bearings |
| Pakistan Watchpost | SPOTTER_LINK, CAMO_HOLD | forward observer ≥ 1 per 3 batteries; retreat if detected |

### 5.10 Transport, naval, amphibious and air

#### 5.10.1 Water policy (avoid mandatory water; use amphibious when the map requires)
* At init, `AiSharedData` computes `needs_water(e) = region(my_start, TRACKED) != region(e_start, TRACKED)` for each enemy start and `water_ratio` (water cells / cells). **Baseline economy never uses water** (bible). Docks are built only when `dock_placeable` **and** one of: naval doctrine (`naval ≥ 30` with `water_factor > 0`), `needs_water(primary)`, or `TRANSPORT_ASSAULT` with a water route shorter than the land route by ≥ 25 %.
* **Route class choice** for an op = the class minimizing ETA over the *slowest* member: `ETA = Σ len_class / speed_class` (water legs for amphibious ground units use their water speed; PD collectors/ships get the bible speed modifiers through resolved defs). `AMPHIBIOUS_ROUTES` rosters (PD, Canada, Kongo, Thailand, Nordics, Vietnam's Reed) weigh water cells at 1.0 (others 1.6) to prefer secondary routes.
* If `needs_water(primary)` and the roster lacks amphibious combat units: composition shifts to AIR/NAVAL + LANDING TRANSPORT (900, Dock): `AiOpLanding` only.

#### 5.10.2 Landing / crossing (`AiOpLanding`)
`ASSEMBLE` (cargo squads + transports at the Dock/shore; Landing Transport carries 4 squads or 2 non-amphibious vehicles, never an MCV/transport; APCs carry 2, Okapi 3, Leviathan 4) → `LOAD` (`load_units`) → `CROSS` (`move` along a water/amphibious route with escort ships; `Concealed Crossing`/Naga smoke/Mobile Reserve/Joint Landing per 5.12) → `UNLOAD` (`unload` at the LZ; `LANDING_BONUS` units are placed adjacent to the target) → `LAND` (a new ATTACK op adopts the disembarked squads; transports `RETURN`). **LZ** = passable land cell adjacent to water within 20 cells of the target minimizing `threat_circle(cell, 12 cells) + defense_coverage` and reachable by the cargo's move class; `PRONG`/Indonesia picks a *decoy* LZ ≥ 25 cells away for a feint (with Feint Landing when available) and lands at the other.

#### 5.10.3 Naval (`AiOpNaval`)
Fleet = ESCORT_SHIP ≥ 2 (anti-air + anti-submarine) + BOAT_LIGHT ≥ 1, plus SIEGE_SHIP/CARRIER/SUBMARINE at T3 only when escorts ≥ 2. Tasks: hold a water choke on the route between bases, kill enemy ships within 30 cells of my coast, bombard coastal ghosts within siege range, escort landings. Launch/abort by `AiStrength` on naval groups (launch 1.3, abort 0.7). Subs: only `SUB_BOMBARD` (5.9.5).

#### 5.10.4 Aircraft sorties (`AiOpAir`)
* Capacity: `pads = 4 × airfields (+2 per airfield with Dispersed Runways)`; `max_aircraft = pads × 3/2`; the AI only rearms at *powered* Airfields (an unpowered Airfield ⇒ POWER_GRID want).
* Squad states per aircraft group: `PARKED → LAUNCH (≥ min_sortie = max(3, 60 % of the group) ready, target chosen, route acceptable) → ATTACK → RETURNING (ammo 0, `return_to_pad`) → REARM → PARKED`.
* **Bomber/gunship target scoring:** `air_score = value(target cluster) × 256 / (256 + aa_pen_q8)` where `aa_pen_q8 = Σ aa_dps_in(target ± 8 cells) × exposure_s × 256 / bomber_hp_pool` (`exposure_s` = 8); launch only if `aa_pen_q8 ≤ 128` (50 %) or the target is an SW/production/tech ghost with `air_score ≥ 2 × cost_of_flight`. Camouflage bombers (Condor) additionally require no detector coverage on the approach (KB detector radii: Watchtower 4, AA battery 5, detector units 5).
* **Fighters:** `AIR_PATROL` over the MAIN squad or base; when enemy aircraft appear within 20 cells of my assets `attack` them; carriers replenish only their own drones (bible); fighters otherwise `guard`.
* **CAS attachment:** hovering gunships (Titan, Hammerhead, Sarus, Osprey) attach to an ATTACK op in ENGAGING and `attack_move` to the target once the AA threat there is below 30 % of their hp.
* `Rapid Turnaround` (USA) and `Precision Window` (Japan) are triggered from here (5.12).

### 5.11 Engineers: capture, garrison, salvage

* **Neutral capture** (`AiOpCapture`): candidates from `neutral_ids` with `capturable` flag (enemy production and superweapons are *not* capturable, bible). Value = data `capture_bonus` (substation power, vision, credits; `ASSUMPTION(map)`); go if within 45 path-cells of my base/army, `threat = 0`, unowned, and `value_credits ≥ 300` (0.6 × the 500-credit Engineer, so a lost Engineer is repaid within one capture). Team: 1 Engineer + 2 escorts; timeout 2400 ticks; re-check ownership each 40 ticks. Mexico/Nigeria (`CAPTURE_POINTS`) raise the priority to 55 and send the first Engineer at 120 s.
* **Garrison** (`GARRISON`/`GARRISON_PREF`): civilian garrison buildings hold 4 infantry squads; El-Andalus stations 2–4 Gate Guards in garrisons within 14 cells of its structures or on the approach route (+20 % weapon damage while garrisoned); others garrison only in `DEFEND` ops on URBAN maps.
* **Salvage (AE only, `SALVAGE`)** (`AiOpSalvage`): reacts to `WRECK_SEEN` records of **enemy land combat vehicles** (never friendly, self-destroyed, decoy or summoned: no income). Salvager = Engineer, Reclaimer or River Warden. Payout = 20 % of the wreck's `paid_cost`; action = 8 s uninterrupted (5 s with Recovery Winches, 3 s under Recovery Priority); wreck persists 60 s. Assign the nearest free salvager if `ETA + action + 100 ticks ≤ expire_tick − now`, `threat(wreck ± 10 cells) == 0` after the fight, and `payout ≥ 150`; batch wrecks by proximity. AE keeps `salvage_team = clamp(2 + army_value/8000, 2, 6)` salvagers (Engineers 500 credits / Reclaimers) and the ATTACK op's CLEANUP state holds the battlefield ≤ 600 ticks while wrecks remain (doctrine: "must hold the battlefield to salvage").

### 5.12 Support powers (`AiPowers` + `AiPowerArch`; all 48)

Bible facts honored: exactly **three powers per roster** (two inherited + one vanilla-only or subfaction-specific); T2 powers need a **powered** Radar, T3 need powered Radar + Laboratory; powers cost credits *per use*, have separate cooldowns, and are **ready when first unlocked**; rebuilding a prerequisite never resets a cooldown; reconnaissance powers may target any map location, other powers need *current vision* unless their text supplies reconnaissance (decoys need *scouted* terrain); a power on cooldown or without power/prerequisites is simply not `READY` (`power_status`).

#### 5.12.1 Decision loop (slot 12, every 10 ticks)
```
for p in roster.power_list (3):
    if view.power_status(p) != READY or params.min_level > diff.powers_level: continue           # Easy=1 (REVEAL, REPAIR_ZONE only), Medium=2, Hard=3, Brutal=4 (adds combos)
    if tick - last_cast[p] < params.min_gap_ticks: continue                                         # anti-spam, e.g. 3000 ticks for recon
    if power_spent_5min + cost > power_spend_cap_pct(15%) * income_5min and not params.emergency: continue
    (benefit, x, y, angle) = AiPowerArch.evaluate(p, params, ctx)                                   # archetype evaluator, credits-equivalent
    need = cost * params.min_ratio_x100 / 100 * diff.eager_pct / 100                                # eager_pct: Easy 150, Medium 125, Hard 100, Brutal 85
    if credits >= excess_cash_credits (2500): need = need * 60 / 100                                # idle cash makes the AI trigger-happy
    if benefit >= need and credits - reserve_low >= cost and view.power_target_ok(p, x, y): use_power(p, x, y, angle)
```
**Traceability to the ability primitives** (abilities_catalog.md 1): REVEAL ↔ `REVEAL_ZONE`; REPAIR_ZONE ↔ `REPAIR_ZONE`; SMOKE ↔ `SMOKE_ZONE`; DECOY ↔ `DECOY_GROUP`; STRIKE ↔ `STRIKE_BARRAGE`; MARK ↔ `MARK_TARGETS`; ANTI_EMP/BUFF/GUARD_STRUCT/CAMO_HOLD/TRANSPORT_BUFF/ECON_BOOST/FIELD_BOOST/PRODUCTION ↔ `STATUS_AREA` / `PARAM_MOD` / `STATUS_PLAYER`; SW_MULTI_CIRCLE/SW_DISC_RING/SW_LINE ↔ `IMPACT_PACKETS` (+ `DEBRIS_ZONE` for Horizon); SW_AREA_DRONES ↔ `SWARM_SUMMON`; SW_DROP ↔ `ENGINE_DROP`; SW_SHIELD ↔ `INTERCEPT_ZONE`; SW_DISABLE_ZONE ↔ `EMP_PULSE`. An archetype is chosen per power in `ai_powers.json` and validated (V4) against the power's `actions[].op`.

Benefit is measured in **credits-equivalent** so one threshold family fits all 48 powers. Definitions: `V(S) = Σ cost_e × hp_e/hp_max_e` (own units at paid cost); *engaged* = damaged within 100 ticks, or ATTACK/ATTACK_MOVE order with an enemy within 12 cells; `fight_ref = 400 ticks`; `q8` fractions.

| Archetype | Benefit formula | Centre / target | Common gates |
|---|---|---|---|
| **REVEAL** | `info(c) × cost / 60`, `info = 100` stale/unscouted enemy base cluster (age > 180 s, or never scouted and t > 240 s) `+ 60` inside a `camo_alert` (power detects) `+ 40` unexplored expansion site within 30 cells `+ 50` SPOT_ARTY (artillery idle, known target cluster in artillery range, no vision) `+ 30` WRECKS (paid value ≥ 1500 near salvagers) | candidate with max `info`; corridor powers orient along the primary route | `min_gap` 3000 ticks (Hard 2000); never twice on the same cell within 6000 ticks |
| **REVEAL_CORRIDOR** | as REVEAL over a 20 × 6 corridor | centred on the primary route midpoint, angle = route bearing | same |
| **STRIKE** (warned shells) | `Σ w_stat × v × min(256, dmg_q8) >> 8 − 2·V(own in circle)`; `w_stat = 256` structures and units unmoved for ≥ 40 ticks (idle/deployed/stationary fire), `64` otherwise; `dmg_q8` from power damage / target hp (default 150) | best of top-6 `AiCluster.best_circle` | all counted targets currently visible (`VISIBLE` rule); warning ⇒ never count fleeing units |
| **BUFF** | `V(engaged eligible in circle) × eff_q8 >> 8 × min(256, dur × 256 / fight_ref) >> 8` | V-weighted centroid of the engaged group | `engaged eligible ≥ engaged_min` (default 6); cast at ENGAGING start or during DEFEND |
| **BUFF_MOVE** | fixed `util_value` when the gate holds | centroid of the moving group (units must be inside at cast) | raid/prong ADVANCING with path ≥ 25 cells, or RETREATING with pursuers |
| **PRODUCTION** | `Σ_active_lines (cost·20/build_ticks) × eff × dur_s` (credits/s of the boosted lines) | n/a (global) | credits ≥ 1500, no power shortage, ≥ 3 active lines |
| **REPAIR_ZONE** | `Σ v_e × min(eff_total_q8, missing_q8) >> 8` (`eff_total = rate × dur`: 20 % → 51, 30 % → 77) | repair point (centroid of damaged eligible units within 12 cells of it) | no armed enemy within 12 cells; ≥ 3 eligible with missing ≥ 15 %; no other repair zone active within 10 cells (no stacking); afterwards `AiRepair` sends damaged eligible units to the centre |
| **SMOKE** (two-sided) | `V(own ground units receiving direct fire) × 77 >> 8 × dur/fight_ref × (256 − arty_share_q8)/256` | centred on the group to protect | `enemy_direct_fire_value_in_circle ≤ 0.3 × own_value_in_circle`; use for RETREATING, crossings, approach through direct-fire defenses |
| **DECOY** | fixed `util_value` (600) | scouted clear cell (`EXPLORED`) ≥ 25 cells from the real op path, inside enemy sight if possible | tied to a real op launching the same tick, or enemy scouts observing (NK) |
| **MARK** | strike-like on marked positions (`Counterlaunch`) or `0.15 × V(own engaged in range) × 12/20` (`Solution`) | centre of the enemy artillery that fired ≤ 8 s ago | ≥ 2 enemy artillery fired recently, own force able to reach |
| **GUARD_STRUCT** | `V(defenses+production in circle) × eff_q8 >> 8 × dur/fight_ref` (× explosive share for Earthworks) | centroid of attacked defenses | base under attack: armed enemy value ≥ 6 units within 14 cells |
| **CAMO_HOLD / ANTI_EMP / TRANSPORT_BUFF / ECON_BOOST / FIELD_BOOST** | fixed `util_value` or the BUFF-form on the affected set (see rows) | see rows | see rows |

#### 5.12.2 Per-power heuristics (all 48; ticks = seconds × 20)
`eff` values are Q8 fractions (0.10 ≈ 26). Radius/duration/cost/cooldown come from the resolved `DefPower` (bible values listed for reference).

| # | Power (cost / cd) | Arch, params | Trigger and target rule |
|---|---|---|---|
| 1 | NAPC UAV Sweep (500/90) | REVEAL r7 12 s, detects | stalest enemy base cluster; `camo_alert` cell; min gap 3000 |
| 2 | NAPC Field Repair Drop (900/180, T3) | REPAIR_ZONE r5, 2 %/s × 10 s ⇒ 20 % (51), land vehicles | at the repair point; benefit ≥ 1.2 × cost (e.g. 6 tanks worth 1000 missing ≥ 20 %: `6000·51/256 = 1195 ≥ 1080` ⇒ cast; 5 tanks: 996 ⇒ hold) |
| 3 | NAPC Combined Arms Window (900/180, vanilla) | BUFF r6 +10 % (26) × 15 s; inf + land vehicles + aircraft, not ships/structures | at ENGAGING start with ≥ 8 eligible engaged (V ≥ ~14 000 to pay off) or during a base defense |
| 4 | NAPC Rapid Turnaround (700/150, USA) | PRODUCTION rearm +50 % × 20 s | ≥ 4 aircraft REARMING at one powered Airfield and a target waiting |
| 5 | NAPC Floating Workshop (800/180, Canada) | REPAIR_ZONE r5, 1.5 %/s × 20 s ⇒ 30 % (77), vehicles **and ships**, land or water | at the repair point; water tile beside the fleet when ≥ 3 ships damaged |
| 6 | NAPC Coordinated Advance (600/150, Mexico) | BUFF_MOVE r6, inf +25 % speed + suppression immunity 12 s, `util 900` | ≥ 8 infantry squads ADVANCING on a target with suppressive defenders (Watchtower/Fortress Guard) within 14 cells of the route, or ≥ 2 suppressed squads; centre on the infantry centroid |
| 7 | NEC Survey Drone (450/90) | REVEAL r6 15 s, detects | as #1 |
| 8 | NEC Counterbattery Mission (1100/180, T3) | STRIKE r4, 6 shells / 4 s, warning 5 s | stationary enemy artillery, deployed siege, defenses or production clusters (visible); centre by `best_circle` |
| 9 | NEC Treaty Coordination (800/180, vanilla) | BUFF-relay `eff = 12` (extra +5 % over 1.10) × 20 s | ≥ 1 powered Relay and engaged eligible V inside a Relay field; cast at fight start (base defense/staging) |
| 10 | NEC Silent Watch (600/150, Nordics) | CAMO_HOLD r6, `util 800`, ≤ 15 s | own stationary group ≥ 6 units, enemy force ETA ≤ 240 ticks with **0 detectors** among visible enemies; group then holds fire until enemy ≤ 0.6 × range |
| 11 | NEC Armored Overwatch (900/180, Eurocorps) | BUFF r6 +10 % range ⇒ `eff 20` × 15 s, stationary tanks | ≥ 5 stationary/deployed tanks and an enemy within 1.3 × range |
| 12 | NEC Emergency Earthworks (700/180, Alpine) | GUARD_STRUCT r5, −20 % explosive (`eff 51 × explosive_share`) × 15 s, infantry + defenses | explosive share of damage taken in the last 200 ticks ≥ 40 % |
| 13 | OLM Dust Screen (400/90) | SMOKE r6 12 s, 30 % less direct fire, ground units both sides | RETREATING squads, crossings, assaults into direct-fire defenses; gate enemy direct-fire value inside ≤ 0.3 × own |
| 14 | OLM Mobile Workshop (900/180, T3) | REPAIR_ZONE r5, 2 %/s × 15 s ⇒ 30 % (77), visible destructible station | as #2 (station must survive: place ≥ 12 cells behind the front) |
| 15 | OLM Open Corridor (650/150, vanilla) | BUFF_MOVE r6, land vehicles +25 % speed 12 s, `util 700` | ≥ 5 vehicles starting ADVANCING on a ≥ 25-cell path (flank/raid), or RETREATING under pursuit; vehicles must be inside at cast |
| 16 | OLM Capacitor Discharge (800/180, Saudi) | BUFF finisher r6 +20 % (51) × 10 s then no fire 4 s | ≥ 4 thermal-beam units engaged **and** `enemy_hp_in_range ≤ 1.2 × my_beam_dps × 10 s` **and** enemy remaining dps after 4 s ≤ 25 % of my group hp; never opens a fight |
| 17 | OLM False Convoy (500/120, Algeria) | DECOY 4 light-vehicle decoys 25 s, `util 600` | when a raid/main op launches: place on a scouted clear cell ≥ 25 cells from the real path on a lane the enemy watches; once per 2400 ticks |
| 18 | OLM Straits Crossfire (800/180, El-Andalus) | BUFF r6 range +10 % / sight +20 % ⇒ `eff 20` × 15 s, infantry + ships | garrison line under attack (≥ 8 infantry engaged) or fleet engaged (≥ 3 ships) |
| 19 | DEF Mobilization Order (700/180) | PRODUCTION +25 % Barracks/Factory × 20 s | ≥ 3 active lines, credits ≥ 1500, no power shortage (benefit `rate × 0.25 × 20`) |
| 20 | DEF Tremor Barrage (1300/210, T3) | STRIKE r5, 4 waves / 8 s, warning 6 s, precision × 0.6 | stationary artillery lines, staged armies, defended positions before an assault; visible only |
| 21 | DEF Redundant Orders (650/180, vanilla) | ANTI_EMP r6, vehicles ignore weapon-disabling EMP 10 s, `util 900` | enemy **Aurora warning** zone containing ≥ 6 own vehicles that cannot leave in time: cast at zone centre at `impact − 30 ticks`; else never |
| 22 | DEF Steel Advance (900/180, Russia) | BUFF r6 −20 % damage taken (`eff 51 × 0.75` for the −20 % speed) × 12 s, land vehicles | ≥ 6 vehicles about to ENGAGE defenders or defending; never when pursuing/kiting/artillery-heavy |
| 23 | DEF Transit Priority (600/150, Kazakhstan) | ECON_BOOST r7 +35 % speed 15 s, `util 700` | ≥ 2 loaded transports ADVANCING with ≥ 20 cells left, or ≥ 2 Collectors fleeing under attack |
| 24 | DEF False Front (500/150, N. Korea) | DECOY decoy Radar + 3 tanks 30 s, `util 600` | enemy scout/aircraft observing within 20 cells of my base, or enemy superweapon known READY: place on the approach ≥ 12 cells from real Radar/Lab/SW; gap 4800 |
| 25 | PD Maritime Patrol (500/90) | REVEAL_CORRIDOR 20 × 6, 12 s, detects | along my route/coast lane; unexplored water lanes; #1 triggers |
| 26 | PD Expeditionary Workshop (900/180, T3) | REPAIR_ZONE r5, 1.5 %/s × 20 s ⇒ 30 %, vehicles + ships, land or water | as #5 |
| 27 | PD Joint Landing (700/180, vanilla) | TRANSPORT_BUFF 15 s, −20 % damage for 6 s after disembark; benefit `V(cargo) × 51 >> 8 × 6/20` | landing op transports ≤ 4 cells from unloading with armed enemy within 14 cells of the LZ |
| 28 | PD Long Watch (600/150, Australia) | REVEAL r7 18 s, no detection, SPOT_ARTY | artillery idle with a known target cluster in range but no vision: centre on the cluster |
| 29 | PD Feint Landing (500/120, Indonesia) | DECOY 3 decoy transports 25 s, `util 600` | same tick a real LANDING op departs; decoy on scouted land/water ≥ 25 cells from the real LZ on a lane the enemy sees |
| 30 | PD Precision Window (900/180, Japan) | BUFF r6 +20 % (51) × 10 s, aircraft + ships | ≥ 4 aircraft/ships engaged in the circle |
| 31 | HAN Wideband Scan (400/90) | REVEAL r7 6 s, detects; enemy gets a 2 s visible warning | detection: `camo_alert` or pre-sweep of a choke/ambush site before passing; scouting: only when the base is unscouted; gap 1800 |
| 32 | HAN Software Surge (900/180, T3) | BUFF finisher r6, unmanned reload −25 % ⇒ `eff 85` × 12 s, then no fire 3 s | ≥ 6 unmanned combat units engaged **and** finisher condition (as #16, 3 s silence) or base defense with enemy dps after 3 s ≤ 30 % |
| 33 | HAN Reserve Bandwidth (650/150, vanilla) | FIELD_BOOST providers +3 radius × 20 s: benefit `V(eligible in (r, r+3]) × 26 >> 8` | ≥ 4 engaged unmanned units outside r but inside r + 3 of a provider |
| 34 | HAN Central Priority (800/180, China) | FIELD_BOOST fields +20 % instead of +10 % ⇒ `eff 26` extra × 15 s | providers alive, ≥ 4 field-eligible engaged; benefit `V(in field) × 26 >> 8 × 15/20` |
| 35 | HAN Broken Contact (650/150, Vietnam) | BUFF_MOVE + SMOKE r6, ground combat +20 % speed 10 s + 6 s smoke at start position, `util 700` | disengaging (RETREATING with pursuers) or closing an ambush (CAMO_AMBUSH group committing); smoke gate as #13 |
| 36 | HAN Repair Swarm (700/180, Cambodia) | REPAIR_ZONE r5, 2 %/s × 10 s ⇒ 20 %, unmanned land units + structures; no repair charge | after a raid on the base (damaged structures) or at the army repair point; count structures too |
| 37 | AE Survey Network (400/90) | REVEAL r7 12 s, highlights wrecks, no detection | post-battle wreck cluster (paid value ≥ 1500) with salvagers ≤ 25 cells, or unscouted base |
| 38 | AE Field Refurbishment (1000/180, T3) | REPAIR_ZONE r6, 3 %/s × 10 s ⇒ 30 % (77), land vehicles; targets cannot fire while repaired, moving ends repair | repair point only, no enemy ≤ 14 cells; ≥ 5 vehicles missing ≥ 30 % |
| 39 | AE Recovery Priority (600/150, vanilla) | ECON_BOOST, Engineers/Reclaimers +25 % speed, salvage 3 s × 20 s; `util = 0.5 × pending payout` | ≥ 3 wrecks pending with payout ≥ 900 within 25 cells of ≥ 2 salvagers, area secure |
| 40 | AE Civil Defense Net (600/150, Nigeria) | BUFF r6 sight +25 % + suppression immunity ⇒ `eff 20`, 15 s, infantry | ≥ 8 infantry squads engaged/advancing and (≥ 2 suppressed or suppressive defenders near) |
| 41 | AE Concealed Crossing (600/150, Kongo) | SMOKE corridor 16 × 4, 12 s, land or water | landing/crossing op within 6 cells of the corridor start, enemy direct fire from outside the corridor; angle along the route |
| 42 | AE Counterbattery Solution (900/180, S. Africa) | MARK r9: mark artillery that fired ≤ 8 s ago; my ground weapons +15 % vs marked for 12 s | ≥ 2 marked artillery, own ground force within 14 cells; benefit `0.15 × V(engaged) × 12/20` |
| 43 | SAP Recon Balloon (450/90) | REVEAL r6 20 s, detects, shootable, deployed at a clear cell | expansion approach / forward stage / `camo_alert`; gap 2400 |
| 44 | SAP Emergency Fortification (900/180, T3) | GUARD_STRUCT r6, −25 % damage 15 s (`eff 64`), defenses + production, not the superweapon, not EMP | base under attack (armed enemy value ≥ 6 units within 14 cells) and ≥ 4 defenses/production in the circle |
| 45 | SAP Protected Advance (750/180, vanilla) | BUFF r6 −15 % damage taken (`eff 38`) × 12 s, infantry + land vehicles | ENGAGING start or defending; V engaged ≥ threshold |
| 46 | SAP Assault Coordination (900/180, India) | BUFF r6 tanks reload −15 % ⇒ `eff 45`, sight +15 %, 12 s | ≥ 5 tanks engaged |
| 47 | SAP Mobile Reserve (650/150, Thailand) | TRANSPORT_BUFF r7 +30 % speed, unload while moving at half speed, 15 s, `util 700` | ≥ 2 loaded transports ≤ 20 cells from the LZ, or reactive redeploy of the mobile reserve |
| 48 | SAP Counterlaunch Plot (800/180, Pakistan) | MARK-STRIKE r8: after a 5 s warning shells hit the *marked positions* | ≥ 1 stationary enemy artillery cluster with `V ≥ 1500` that fired ≤ 8 s ago; benefit uses `w_stat` (units that moved away don't count) |

**Guardrails.** Never cast two REPAIR_ZONE powers within 10 cells (heal/repair auras from the same source do not stack; repair stations cannot repair themselves). Never cast a **damage-bearing** power (STRIKE/MARK-STRIKE) whose circle contains ≥ 20 % of the benefit in own value (friendly fire). SMOKE only when the two-sided rule is favorable. Reconnaissance powers ignore `power_target_ok` vision limits (`TargetRule.ANY`); everything else obeys real vision (Brutal's fog cheat gives no exemption).

### 5.13 Superweapons (`AiSuperweapon`, `AiDispersal`)

Bible facts honored: max **one** strategic structure per player; 5000 credits, 90 s build, `−200` power, needs Radar + Laboratory; charges only with enough power and intact Radar/Laboratory; **one stored charge, no stockpiling; full recharge starts at activation**; destruction or EMP of the launcher during the warning cancels the attack without refund; a power shortage *after* activation does not cancel it; strategic warning zones are visible to affected players and cannot be hidden; ordinary AA cannot intercept (except Tempest drones); superweapons may target *explored* terrain without current vision.

#### 5.13.1 Build policy
Start the launcher (prio 80) only when **all**: superweapons enabled and `can_build == OK`; `t ≥ sw_min_time_s × (150 − sw_priority)/100 ± 10 %(rng)` (`sw_min_time_s`: Easy 1800, Medium 960, Hard 660, Brutal 540); `credits ≥ 2500` and `income_per_s × 240 ≥ 2500`; `supply − demand ≥ 200 + margin_min` (otherwise Generators are queued first at prio 15: three Generators for a typical late base); no EMERGENCY/OPENER/ECONOMY wants pending; not `under_attack` in the last 60 s; `army_value ≥ 0.6 × est_enemy_army`. Since the single construction queue is blocked for 90 s, cheap urgent wants (power, defenses) are queued **before** it. Placement: back side, at least `dispersion + 2` cells from Radar/Laboratory/Generators if space allows, then guard wants (1 AA battery + 1 AT turret within 6 cells, prio 55). The AI protects Radar, Laboratory, Generators and the launcher (DEFEND priority 90 sites) because charging depends on them.

#### 5.13.2 Use policy and targeting job
On `READY`, `AiSuperweapon` starts a resumable **target job** (≤ 40 wu/tick, completes in ≤ 8 ticks typical):
1. **Candidates** — `AiCluster.value_grid` over ghosts + visible enemy units into 3-cell blocks; top-K blocks (K = 10) by local 3 × 3 sum, plus every single high-value ghost (superweapon, Laboratory, Radar, HQ) and, for line/multi-circle weapons, 16 orientations (`angle = k × 256` binary units).
2. **Scoring** — per weapon (table below); **geometry is read from the resolved `DefSuperweapon`** (`packets[i].offset_x/offset_y/radius/damage/delay_t` in the local frame with +x along the committed orientation, plus `radius`, `duration_t`, `warning_t`, `action_kind`; `DefPower.length/width` for line/corridor powers), so `ai_powers.json` carries only weights and the bible values in the table are for orientation; scores use `w_stat` (structures and unmoved units 1.0; mobile units `mobile_w`), enemy value `v`, and **own-value penalty** `pen_own` × `V(own in shape)`; sim queries (`enemies_in_circle`, fog-honoring) refresh unit positions inside the top-3 candidates before the final pick; ghosts supply unseen structures ("previously explored terrain").
3. **Decision** — fire when `score ≥ sw_min_score` (`0.8 × 5000` = 4000; Brutal 3000; Easy 6000) or the hold expired and `score ≥ 0.4 × 5000`; `hold_max`: Easy 5400 ticks, Medium 1800, Hard 900, Brutal 400 (recharge starts at activation, so holding wastes time). **Combo timing**: if an ATTACK/LANDING op will be within ~60 s of the target region, `fire_at = op.arrival_tick − warning_ticks − 20` (Aurora, Dragonfall, Perun, Atlas, Horizon, Helios to soften defenses); Brutal also uses combos, Hard only for Aurora/Dragonfall.
4. Never target allied territory; never fire if `pen_own × own_value_in_shape > 0.5 × enemy_gain`.

| Superweapon (bible geometry) | Shape and candidate generation | Score (credits-equivalent) | Extras |
|---|---|---|---|
| **Atlas Kinetic Array** — 3 penetrators at the point and ±3 cells, each r 2, 10 s warning | `SW_MULTI_CIRCLE`: circles from `packets` (bible: 3 × r 2 at offsets 0/−3/+3 cells along `angle`); 16 angles; centres at cluster blocks | `Σ w × v × min(1, dmg/hp)`; heavy-vehicle clusters and key buildings; `mobile_w = 0.25`; `pen_own = 1.5` | e.g. 3 Factories in a row 3 cells apart (value 2000 each): centre on the middle one, `angle 0` ⇒ `3 × 2000 = 6000`; centre on an end ⇒ 4000 |
| **Aurora Microwave Array** — r 8 zone; enemy vehicles/aircraft lose weapons 8 s; powered enemy structures off 18 s; infantry unaffected; light damage; enemies only | `SW_DISABLE_ZONE`: circle r 8 | `0.5 × V(enemy vehicles+aircraft) + 0.8 × V(powered defenses) + 0.3 × V(powered production/power/tech)`; no own penalty (enemies only) | **Combo-first**: hold up to 60 s for an assault whose slowest unit can reach the zone within 8 s + 4 s of the warning (`fire_at`), or defensive use when an enemy armored group is inside/near my base; `mobile_w 1.0` for vehicles (they are disabled, not killed) |
| **Helios Reflector** — 16 × 3 line swept over 12 s, strong thermal damage to ground, ships, structures; cannot track after commit | `SW_LINE`: rectangle 16 × 3, 16 angles over the full circle (the sweep direction is part of the angle), centres at cluster blocks and along base rows | `Σ_structures 1.0·v + Σ_stationary units 0.8·v + Σ_mobile 0.15·v`; `pen_own = 2`; beam-resistant upgrades reduce damage | El-Andalus-style denial: if an enemy wave's route crosses a known choke, `+ 0.3 × wave value` (force them away from a defended crossing) |
| **Perun Missile Complex** — core r 3 (heavy), fragmentation ring to r 7 (lower damage) | `SW_DISC_RING`: core r 3 + ring 3–7 | `1.0 × V(core) + 0.35 × V(ring)`; `pen_own = 2`; +50 % if the target is an enemy superweapon launcher that is charging (counter-SW), +30 % on Laboratory/Radar/HQ | normal AA cannot stop it (bible); only destroying the launcher during the warning cancels it |
| **Tempest Swarm Hub** — 24 drones on a r 6 area for up to 20 s; ground and surface targets; AA can shoot drones | `SW_AREA_DRONES`: circle r 6 | `(0.6 Σ structures + 1.0 Σ stationary units + 0.4 Σ mobile) × (256 − aa_red_q8)/256`; `aa_red = min(230, AA_dps(target ± 14 cells) × 20 s × 256 / (24 × drone_hp × 0.5))` | prefers soft targets with weak AA (artillery lines, collectors, infantry masses) |
| **Dragonfall Field Foundry** — 3 capsules within a marked r 5 area; 5 s assembly; 60 s of slow anti-structure engines; attackable during assembly | `SW_DROP`: circle r 5 | `0.6 × Σ structure value within 10 cells of the point − AT_dps_pen`; `AT_dps_pen = min(v, enemy anti-ground dps within 10 cells × 60 s × 0.5)`; prefers HQ/production/tech away from defenses | **Combo**: own wave within 30 s to exploit the breach; never on stacks of AT turrets |
| **Horizon Mass Driver** — 3 overlapping r 3 circles along a 10-cell line over 9 s; debris slows land vehicles 35 % for 20 s and blocks new construction | `SW_LINE` with 3 circles at 0/5/10 cells: 16 angles | `Σ_circles (structures 1.0, stationary 0.8, mobile 0.3)·v + block_bonus (1500 if an enemy MCV/expansion site is inside) + 0.2 × wave value on a crossing route`; `pen_own = 1.5` | Kongo note: debris also slows *my* vehicles: register own `slow_debris` avoid zone for 29 s |
| **Trident Interception Array** (SAP) — protects a r 6 zone 25 s with 24 charges: destroys each hostile ordinary missile/shell crossing; a superweapon packet consumes 8 charges for −50 %; beams, bullets, EMP, entering units and fire from inside bypass | `SW_SHIELD`: circle r 6 (defensive) | **Counter-SW**: on an enemy warning whose footprint holds ≥ 5000 of my structure value, cast over the footprint centre within 4 s of the warning (6 s < enemy 10 s); benefit `0.5 × V(protected) × packets_covered/packets`. **Offensive cover**: ENGAGING/SIEGING vs a target where missile/shell damage share ≥ 40 %, over the assault group. **Defensive**: base attacked by artillery-heavy enemy with my defenders inside | never a permanent shield (25 s); zone is fixed and visible to the enemy; bait is possible but not planned |

#### 5.13.3 Reactions to enemy superweapon warnings (`AiDispersal`, class-0 commands, slot 3)
On the (delayed, 5.3.2) `SW_WARNING(owner, sw, x, y, angle, impact_tick)` record (from `strategic_warnings`): add an `AiAvoidZones` row with the bible geometry, then for each own **mobile** entity in the danger footprint (+2-cell margin) whose squad is *eligible* (`squad.id % 100 < dodge_pct`; Easy 0 %, Medium 50 %, Hard/Brutal 100 %): find the nearest passable, threat-free cell outside the footprint reachable in `time_left − max(20, dt + exec_lag_est)` ticks (ring scan, ties by lowest cell index), `move` with per-unit ring offsets (spread ≥ 2 cells), interrupting ops (priority 95). Units that cannot escape still move toward the nearest edge.

| Incoming | Footprint (bible) | Response |
|---|---|---|
| Atlas | 3 circles r 2 at 0/±3 cells along `angle` | leave to > 3 cells from every rod centre; vehicles first; spread |
| Perun | core r 3, ring to r 7 | leave to > 8 cells (support units in the ring first) |
| Helios | 16 × 3 line, 12 s sweep | leave the rectangle perpendicular to the axis to > 3.5 cells from it (sweep time is generous); structures can't move |
| Aurora | r 8 (weapons off 8 s vehicles/aircraft; powered structures off 18 s; infantry unaffected) | vehicles/aircraft leave r 9 if reachable in time else `Redundant Orders` (DEF, at `impact − 30`); **infantry/AT hold and, at `impact + 20`, attack into the zone** (disabled vehicles) — Hard/Brutal only |
| Tempest | r 6, 24 drones, 20 s | mobile ground units leave to > 7 cells; AA_MOBILE + FIGHTER take a ring at 7–10 cells and `attack` drones as they appear (only drones are AA-targetable); if AA < 3, fighters `attack_move` the zone |
| Dragonfall | r 5 capsules, 5 s assembly, 60 s life | pre-position ≥ 6 AT/TANK units at 8–10 cells; when capsules appear `attack` them with all AT units (kill before assembly ends); afterwards mobile units kite the slow engines, AT surrounds; other units avoid r + 4 for 65 s |
| Horizon | 10-cell line, 3 circles r 3, 9 s; debris 20 s | leave to > 4 cells from the line; register `slow_debris` + `no_build` zones for 29 s: excluded from route waypoints, staging and placement; reinforcements re-routed |
| Trident (enemy) | r 6, 25 s, 24 charges | register a `no_fire_artillery` zone (25 s): artillery/missile squads retarget outside it or wait; prefer beams, direct fire, infantry or aircraft; superweapon packets are only halved, not cancelled |

**Launcher snipe (Brutal only):** if the enemy launcher's ghost is known, an air group has `ETA + time_to_kill ≤ warning_left − 40 ticks` and AA threat is low, dispatch a bomber flight to destroy it during the warning (bible counterplay); otherwise skip.

### 5.14 Difficulty profiles and per-roster personalities

#### 5.14.1 Difficulty levels (`ai_difficulty.json`; the **only** cheats are Brutal's, and they are labelled)

| Parameter | Easy | Medium | Hard | Brutal |
|---|---|---|---|---|
| Target skill | loses to a competent human in ~10–12 min | matches an average player | strong, fair | expert-level (with cheats) |
| `think_period_ticks` (strategic cadence) | 30 | 20 | 10 | 6 |
| `micro_period_ticks` | 0 (off) | 10 | 4 | 2 |
| `apm_cap` commands/min (group order = 1) / `cmd_burst` tokens | 40 / 4 | 90 / 8 | 180 / 16 | 320 / 28 |
| `reaction_delay_ticks` (events incl. SW warnings) | 60 | 30 | 12 | 4 |
| `idle_tolerance_ticks` (empty producer noticed after) | 200 | 80 | 20 | 4 |
| `queue_depth` per producer | 1 | 2 | 3 | 3 |
| `place_latency_ticks` (completed structure → placement) | 100 | 40 | 10 | 2 |
| `opt_step_keep_pct` (optional opener steps kept) | 50 | 80 | 100 | 100 |
| Information | fair | fair | fair | **omniscient** (fog only; camouflage honored) |
| `scout_level` | 0 | 1 | 2 | 3 |
| `expansions_max` (MCV) | 0 | 1 | 2 | 3 |
| `collector_k_x10` | 10 | 15 | 20 | 22 |
| `tech_delay_x100` | 160 | 125 | 100 | 85 |
| `first_attack_min_s` / `wave_interval_s` | 900 / 300 | 600 / 180 | 420 / 120 | 330 / 90 |
| `launch_ratio_x100` / `est_noise_pct` | 130 / 40 | 130 / 25 | 130 / 10 | 120 / 4 |
| Micro | retreat only for < 20 % | retreat + focus | + kite | + kite + stationary-fire hold |
| `dodge_pct` (SW dispersal eligibility) | 0 | 50 | 100 | 100 |
| `powers_level` / `eager_pct` | 1 / 150 | 2 / 125 | 3 / 100 | 4 / 85 |
| `sw_min_time_s` | 1800 | 960 | 660 | 540 |
| `unit_cap_pct` (of rules cap) | 60 | 85 | 100 | 100 |
| `wu_per_tick` / `call_cap_wu` (max budget of one think) | 220 / 1500 | 350 / 2400 | 500 / 3000 | 600 / 3000 |
| `jitter_pct` (personality) | 30 | 25 | 15 | 10 |
| `prongs_max` / `harass_ops_max` | 1 / 0 | 2 / 1 | 3 / 2 | 4 / 3 |
| `enemy_prior` | off | air only | full | full |
| **`handicap_pct`** (lobby default; economy bonus) | 100 | 100 | 100 | **120 (+20 % starting credits and harvest/salvage income)** |
| `label_cheats` (lobby text key `ai.cheats.brutal`) | "" | "" | "" | "Cheats: +20 % credits and income, sees through fog" |

* **Resource bonus is Brutal-only and uses net's existing per-slot `handicap_pct`** (net.md 5.3.6 / XR-9: 50..200 step 5; scales that player's **starting credits and harvest/salvage income** by `pct/100` in the sim, integer truncating; never unit cost, build time, health, damage or reload, so the bible floors/caps are untouched). The AI itself applies nothing: `AiFactory.level_handicap_pct(level)` returns 120 for Brutal and 100 otherwise, and the lobby uses it as the **default** `handicap_pct` when the host selects a level (still editable by the host), showing `ai.cheats.brutal` next to the level name whenever the AI slot's level is Brutal or its handicap exceeds 100. Takeover of a dropped human (`TAKEOVER_AI_LEVEL = 1`, Medium) keeps that slot's existing handicap.
* **Handicaps** for weaker levels are behavioral only (latency, depth, opener fidelity, no expansions, imprecise estimates, slower tech, `unit_cap_pct`); no stat penalties.

#### 5.14.2 Personality vectors and doctrine flags for all 32 rosters
Columns: aggression, tech, economy (0–100); defense share %, harass %; air, naval, siege, infantry weights (0–100); primary/alternate attack style (`P`ush, `PR`ong, `R`aid, `C`reep, `L`anding, `A`ir, `F`ortress); expansion style (`E`arly, `D`efended, `L`ate, `M`inimal); doctrine flags (bit names in 4.1). Values are the *base* before seeded jitter (5.14.3); rationale is the bible `identity/opening/counterplay` text.

| Roster | Agg | Tech | Eco | Def% | Har% | Air | Nav | Siege | Inf | Style | Exp | Flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| napc.vanilla | 50 | 50 | 55 | 15 | 10 | 15 | 10 | 40 | 40 | P/PR | E | PRESERVE_VEHICLES, APRON_RETREAT, SIEGE_DEPLOY |
| napc.usa | 55 | 60 | 50 | 10 | 10 | 65 | 5 | 20 | 35 | A/P | E | PRESERVE_VEHICLES, APRON_RETREAT, AIR_LOADOUT |
| napc.canada | 45 | 45 | 55 | 15 | 15 | 10 | 45 | 30 | 45 | L/PR | D | PRESERVE_VEHICLES, APRON_RETREAT, AMPHIBIOUS_ROUTES, TRANSPORT_ASSAULT, SIEGE_DEPLOY |
| napc.mexico | 65 | 35 | 50 | 10 | 15 | 5 | 5 | 20 | 75 | PR/P | E | PRESERVE_VEHICLES, APRON_RETREAT, SHELTER_COVER, CAPTURE_POINTS |
| nec.vanilla | 35 | 60 | 60 | 25 | 5 | 15 | 10 | 55 | 40 | C/F | D | RELAY_NETWORK, SIEGE_DEPLOY, STAGED_PUSH |
| nec.nordics | 45 | 55 | 55 | 20 | 25 | 10 | 25 | 50 | 40 | C/R | D | RELAY_NETWORK, SENSOR_MAST, AMPHIBIOUS_ROUTES, OBSERVER_LINK, SHOOT_SCOOT, SIEGE_DEPLOY |
| nec.eurocorps | 30 | 65 | 60 | 25 | 0 | 0 | 10 | 60 | 35 | C/P | D | RELAY_NETWORK, SIEGE_DEPLOY, STAGED_PUSH |
| nec.alpine_brotherhood | 25 | 45 | 60 | 35 | 0 | 5 | 0 | 50 | 60 | F/C | D | RELAY_NETWORK, SHELTER_COVER, DEFENSE_CLUSTER, SIEGE_DEPLOY |
| olm.vanilla | 55 | 50 | 55 | 10 | 35 | 15 | 15 | 25 | 40 | PR/R | E | POWER_RICH, SMOKE_RETREAT, CAMO_AMBUSH |
| olm.saudi_arabia | 40 | 60 | 55 | 20 | 10 | 10 | 5 | 35 | 35 | C/P | D | POWER_RICH, SIEGE_DEPLOY, STAGED_PUSH |
| olm.algeria | 75 | 30 | 50 | 5 | 80 | 10 | 5 | 30 | 35 | R/PR | E | POWER_RICH, COLLECTOR_RAID, DECOYS, CAMO_AMBUSH, SHOOT_SCOOT, SMOKE_RETREAT |
| olm.el_andalus | 35 | 45 | 55 | 30 | 10 | 5 | 40 | 40 | 60 | C/F | D | POWER_RICH, GARRISON, DEFENSE_CLUSTER, SIEGE_DEPLOY |
| def.vanilla | 55 | 45 | 65 | 15 | 10 | 15 | 10 | 60 | 40 | PR/P | E | TWO_FRONT, SIEGE_DEPLOY |
| def.russia | 40 | 60 | 60 | 15 | 0 | 5 | 10 | 55 | 30 | P/C | D | INTERCEPTOR_ESCORT, SIEGE_DEPLOY, STAGED_PUSH |
| def.kazakhstan | 60 | 45 | 70 | 10 | 45 | 15 | 10 | 45 | 35 | R/C | E | COLLECTOR_RAID, SHOOT_SCOOT, SIEGE_DEPLOY |
| def.north_korea | 25 | 40 | 55 | 40 | 0 | 0 | 5 | 45 | 75 | F/C | D | DEFENSE_CLUSTER, SHELTER_COVER, DECOYS, SIEGE_DEPLOY |
| pd.vanilla | 50 | 50 | 60 | 5 | 30 | 20 | 45 | 40 | 45 | L/PR | E | AMPHIBIOUS_ROUTES, TRANSPORT_ASSAULT, REPAIR_TENDERS, SIEGE_DEPLOY |
| pd.australia | 35 | 60 | 55 | 10 | 5 | 40 | 20 | 70 | 30 | C/A | D | AMPHIBIOUS_ROUTES, OBSERVER_LINK, REPAIR_TENDERS, SIEGE_DEPLOY, STAGED_PUSH |
| pd.indonesia | 65 | 35 | 55 | 5 | 40 | 5 | 30 | 30 | 70 | L/R | E | AMPHIBIOUS_ROUTES, TRANSPORT_ASSAULT, DECOYS, COLLECTOR_RAID, REPAIR_TENDERS |
| pd.japan | 45 | 65 | 55 | 10 | 10 | 40 | 40 | 40 | 30 | P/A | D | AMPHIBIOUS_ROUTES, MODE_SWITCH, REPAIR_TENDERS |
| han.vanilla | 60 | 45 | 55 | 10 | 15 | 15 | 10 | 40 | 65 | PR/P | E | COMMAND_FIELD |
| han.china | 45 | 60 | 55 | 15 | 0 | 5 | 10 | 35 | 45 | P/C | D | COMMAND_FIELD, SIEGE_DEPLOY |
| han.vietnam | 60 | 40 | 50 | 10 | 45 | 10 | 20 | 40 | 70 | R/PR | E | COMMAND_FIELD, CAMO_AMBUSH, AMPHIBIOUS_ROUTES, SHOOT_SCOOT |
| han.cambodia | 40 | 50 | 60 | 15 | 5 | 15 | 5 | 45 | 55 | C/P | D | COMMAND_FIELD, REPAIR_TENDERS, SHOOT_SCOOT |
| ae.vanilla | 50 | 45 | 70 | 15 | 10 | 15 | 10 | 40 | 45 | P/PR | E | SALVAGE, PRESERVE_VEHICLES (retreat 40), SIEGE_DEPLOY |
| ae.nigeria | 55 | 40 | 60 | 15 | 15 | 10 | 10 | 25 | 70 | PR/P | E | SALVAGE, CAPTURE_POINTS |
| ae.kongo | 55 | 40 | 60 | 10 | 40 | 10 | 30 | 20 | 60 | L/R | E | SALVAGE, AMPHIBIOUS_ROUTES, TRANSPORT_ASSAULT, SMOKE_RETREAT, CAMO_AMBUSH, COLLECTOR_RAID |
| ae.south_africa | 35 | 60 | 60 | 15 | 5 | 20 | 5 | 60 | 40 | C/P | D | SALVAGE, MODE_SWITCH, SIEGE_DEPLOY, STAGED_PUSH |
| sap.vanilla | 35 | 50 | 60 | 30 | 5 | 10 | 10 | 55 | 55 | C/F | D | DEFENSE_CLUSTER, SIEGE_DEPLOY, STAGED_PUSH |
| sap.india | 40 | 60 | 55 | 20 | 0 | 10 | 10 | 50 | 35 | C/P | D | DEFENSE_CLUSTER, INTERCEPTOR_ESCORT, SIEGE_DEPLOY, STAGED_PUSH |
| sap.thailand | 50 | 40 | 55 | 20 | 25 | 10 | 25 | 40 | 65 | L/C | D | DEFENSE_CLUSTER, AMPHIBIOUS_ROUTES, TRANSPORT_ASSAULT, SMOKE_RETREAT |
| sap.pakistan | 40 | 55 | 55 | 20 | 15 | 10 | 5 | 65 | 45 | C/R | D | DEFENSE_CLUSTER, OBSERVER_LINK, CAMO_AMBUSH, SHOOT_SCOOT, SIEGE_DEPLOY, STAGED_PUSH |

Retreat thresholds: `retreat_hp_pct/return_hp_pct` = NAPC family 50/75 (apron heals to 75 %), AE 40/85, all others 35/85. `dispersion` (min cells between key structures, i.e. Radar/Laboratory/Generators/production/launcher): 3 default; 4 for Japan, Australia, Nordics (precision rosters that fear Atlas/Perun/Aurora); 2 for `DEFENSE_CLUSTER` rosters (they cluster on purpose and rely on defenses); `sw_priority`: 60 default, 80 for Saudi, Pakistan, DEF vanilla; 40 for Algeria, Kazakhstan (raid-first).

**Opening recipes** (guidance for the JSON authors, `AI-10`; shorthand: `G` Generator, `Rf` Refinery, `Rx` Barracks, `F` Factory, `Rd` Radar, `L` Laboratory, `A` Airfield, `D` Dock, `W` Watchtower, `AT` AT turret, `Rl` Relay, `X` advanced defense; `t:role×n` = train until n; `‖` = parallel; every recipe starts with the spine **`G, Rf, Rx, F, Rd`** = 155 s of sequential build time and 6,400 credits of the 7,500 start). Roles are the 5.5.1 roles; T2 roles come after `Rd`.

| Roster | Steps after / around the spine |
|---|---|
| napc.vanilla | `G Rf Rx ‖ t:inf×2 ‖ t:scout×1 · F · t:tank×2 (escort 1st expansion) · Rd · G · in-radius Rf2 · t:aa×2 · t:art×2 · R:adaptive_plating · L` (bible: Rifle + Pathfinder, two Guardians, AA before Paladins) |
| napc.usa | `… F Rd · A · t:tank×2 · t:ftr×2 · t:aa×1 · L · t:bmb×2 · R:dispersed_runways · A2`; no Bastion (removed) |
| napc.canada | `… F ‖ t:inf×3 ‖ t:scout(Beaver)×2 · Rd · t:tank(Narwhal)×2 · [D + t:esc×1 if naval/water] · R:sealed_compartments` (no T1 tank: infantry + Beavers until Radar) |
| napc.mexico | `G Rf Rx Rx · F · t:inf×6 · t:at×2 · t:scout×1 · Rd · t:support(Aguila)×2 · capture ops from 120 s · R:section_logistics` |
| nec.vanilla | `… F ‖ t:inf×2 t:at×1 t:scout×1 · t:tank×2 · Rd · Rl · t:aa×2 · t:art×2 · R:sensor_fusion · L · Rl2 · R:distributed_control` |
| nec.nordics | `… F ‖ t:inf×2 t:scout(Fen)×2 · t:tank×2 · Rd · t:aa×2 · t:art(Fjord)×3 · deploy Fen mast at stage · R:dispersed_links` |
| nec.eurocorps | `… F ‖ t:inf×4 t:at×2 t:scout×1 · Rd · Rl · t:tank(Marte)×2 · G · t:aa×2 · L · t:heavy(Charlemagne)×2 · R:shared_fire_solutions` |
| nec.alpine | `… F ‖ t:inf×4 t:at×2 · W×2 · Rd · Rl · t:support(Pioneer)×2 · t:art(Ibex)×2 · AT×1 · t:aa×2 · Rf2 · X · R:tunnel_workshops` |
| olm.vanilla | `… F ‖ t:scout(Caravan)×2 t:tank×2 t:inf×2 · Rd · t:aa×1 · t:support(Mirage)×2 · t:art×2 · L` (generators only by the margin rule; each yields +25 % power) |
| olm.saudi | `… F ‖ t:inf×2 · t:tank×2 · Rd · t:aa(Dawn)×2 · L · t:heavy(Ifrit)×2 · R:thermal_reservoirs · Sunwall/beam cluster with extra G when margin < 60` (each Generator yields +50 % over base) |
| olm.algeria | `… F ‖ t:scout(Rover)×3 (+ t:at×3 as passengers) · t:tank×1 · Rd · t:art(Scorpion)×3 · harass op ASAP · t:aa×1 · R:distributed_fuel_caches` |
| olm.el_andalus | `… F ‖ t:inf(Gate)×4 (garrison) · t:tank×2 · Rd · t:art×2 · [D + t:esc if water] · t:aa×2 · R:harbor_militia · W` |
| def.vanilla | `G Rf Rx F F2 · t:tank×3 t:inf×4 (two fronts) · Rd · t:aa×2 · t:art×3 · Mobilization Order · L · R:standardized_parts` |
| def.russia | `… F ‖ t:inf×4 t:at×2 t:scout×1 · Rd · t:tank(Ural)×3 · t:aa×2 · t:art×2 · L · t:heavy(Bear)×2 · R:layered_protection` |
| def.kazakhstan | `G Rf Rf2 (−15 % refinery) Rx F · t:scout(Steppe)×3 · t:tank×2 · Rd · t:art(Saker)×3 · t:aa×2 · R:mobile_dispatch` |
| def.north_korea | `… F ‖ t:inf(Fortress)×6 · W×2 · t:tank×2 · Rd · t:support(Echo)×1 · AT×2 · t:art×2 · t:aa×2 · X · R:buried_command_lines` |
| pd.vanilla | `… F ‖ t:scout(Wake)×2 t:tank(Tide)×2 t:inf×2 · Rd · t:aa(Storm)×3 (before any fleet) · t:art×2 · D · t:esc×1 · L` |
| pd.australia | `… F ‖ t:inf×3 t:tank×2 · Rd · A · t:ftr(Wedge)×2 · t:art(Outrider)×3 · t:aa×2 · L · R:forward_fire_control` |
| pd.indonesia | `… F ‖ t:inf(Raider)×6 · t:scout(Kancil)×3 · t:tank×1 · Rd · t:art×2 · t:aa×2 · landing op with feint · R:distributed_beachheads` |
| pd.japan | `… F ‖ t:inf×3 t:scout×2 · Rd · t:tank(Shinano)×3 · t:aa×2 · L · [D + one escorted Shogun if water] · R:predictive_maintenance` |
| han.vanilla | `G Rf Rx Rx F · t:inf×6 t:at×2 · t:tank(Ox)×2 · Rd · t:aa(Firefly)×2 · t:support(Link)×1 · t:art(Nest)×3 · L · t:cmd(Dragon)×1` |
| han.china | `… F ‖ t:inf×4 t:at×2 · Rd · t:tank(Imperial Guard)×3 · t:aa×2 · t:support(Link)×1 · t:art×3 · L · t:cmd(Long)×1 · R:guard_integration` |
| han.vietnam | `… F ‖ t:inf(Ranger)×6 (ambush) · t:scout×2 · t:tank×1 · Rd · t:support(Link)×1 · t:art(Reed)×3 · t:aa×2 · R:hidden_relays` |
| han.cambodia | `… F ‖ t:inf×4 · t:tank×2 · Rd · t:scout(Lotus)×1 · t:aa×2 · t:art×3 · t:support(Mekong)×1 · L · R:modular_servicing` |
| ae.vanilla | `… F ‖ t:inf×3 t:tank×3 t:eng×2 (salvage team) · Rd · t:support(Reclaimer)×2 · t:aa×2 · t:art×2 · MCV expansion funded by salvage · R:recovery_winches · L` |
| ae.nigeria | `G Rf Rx Rx F · t:inf(Civic)×6 · t:tank×2 · Rd · t:aa(Lagos)×2 · t:art×2 · capture points · R:municipal_reserves` |
| ae.kongo | `… F ‖ t:inf×4 t:scout(Okapi)×2 · Rd · t:support(Warden)×2 · t:tank×2 · t:aa×2 · raid op on resource routes · R:watershed_logistics` |
| ae.south_africa | `… F ‖ t:inf×4 t:at×2 t:scout×1 · Rd · t:tank(Rhino)×3 · t:art(Protea)×3 · t:aa×3 · L · R:precision_machining` |
| sap.vanilla | `… F ‖ t:inf×4 t:at×1 · t:tank×2 · Rd · W · t:aa×2 · t:art×2 · defense cluster at the expansion · Rf2 · L · R:layered_fieldworks` |
| sap.india | `… F ‖ t:inf×4 · Rd · t:tank(Arjun)×3 · t:aa×2 · t:art×2 · L · t:heavy(Gaj)×2 · surplus G · R:integrated_protection` |
| sap.thailand | `… F ‖ t:inf(River Marine)×6 · t:scout(Naga)×3 · t:tank×2 · Rd · t:art×2 · t:aa×2 · mobile reserve · R:rapid_ferry_drills` |
| sap.pakistan | `… F ‖ t:inf×3 t:scout×2 · t:tank×2 · Rd · t:support(Watchpost)×2 · t:art(Shaheen)×3 · t:aa×2 · L · R:observer_network` |

#### 5.14.3 Seeded randomness (reproducible AI-vs-AI)
Net hands the factory a 32-bit `seed = mix32(match_seed ^ ((pid + 1) × 0x9E3779B9))` (net.md 5.6; never the sim RNG). `AiRng.seed_from(seed)` sets the xorshift32 state to `seed` (0 ⇒ `0x9E3779B9`). Draw order at controller init is **fixed**: (0) if `style == wildcard`, one `pick_weighted([40, 30, 30])` (doctrine / aggressive / defensive) and one uniform attack-style pick (5.14.4); (1) personality jitter per numeric field in `AiPersonality` declaration order: `p' = clamp(p × (100 + r)/100, 0, 100)`, `r = range_i(−J, +J)`, `J = jitter_pct`; (2) attack style: `pick_weighted([70, 30])` between primary and alternate; (3) `first_attack_jitter_pct = range_i(−15, 25)`, `wave_interval_jitter_pct = range_i(−20, 20)`; (4) one draw per `opt` step id in merged script order (`chance(100 − keep)` ⇒ dropped); (5) `sw` timing jitter `range_i(−10, 10)`. Afterwards the RNG is used only for tie-breaks that would otherwise favor a fixed corner (scout target order among equals, waypoint side). Estimate noise uses `hash(epoch, target_row)` (not a draw) so it is stable within a 200-tick epoch.
Test vectors: `mix32(1) = 0x514E28B7`; `seed_from(0x514E28B7)` ⇒ first six `next_u32()` = `524866043, 2877414208, 2380002740, 2664205378, 3890067424, 1964142960`, and a fresh RNG's first six `range_i(−15, 25)` = `18, −1, −2, 25, −4, 20`; `seed_from(0)` ⇒ state `0x9E3779B9`, first two = `1359758873, 3761132862`; `thinker_seed(12345, 1) = 0x8739D20C` with first three outputs `309959344, 81710791, 2110671044`.

#### 5.14.4 Styles (`style` argument of `ai_factory`; `AiFactory.style_count() = 4`)
Applied after the roster overlay and before the seeded jitter, on top of the difficulty level (4 levels × 4 styles × 32 rosters); the lobby shows the style next to the level.

| Style | Key | Effect |
|---|---|---|
| 0 Doctrine | `ai.style.doctrine` | none: the roster personality of 5.14.2 as tabulated |
| 1 Aggressive | `ai.style.aggressive` | `aggression +20`, `harass_pct +10`, `defense_pct −5` (≥ 0), `first_attack_min_s × 0.80`, `wave_interval_s × 0.80`, posture thresholds −10 |
| 2 Defensive | `ai.style.defensive` | `aggression −20`, `defense_pct +8` (≤ 40), `first_attack_min_s × 1.30`, `wave_interval_s × 1.20`, `expand` EARLY→DEFENDED, FORTRESS/CREEP style weights ×2 |
| 3 Wildcard | `ai.style.wildcard` | seeded pick of Doctrine/Aggressive/Defensive (40/30/30) **and** a uniformly drawn attack style among {PUSH, PRONG, RAID, CREEP, LANDING} (LANDING only if the map has water) |

Takeover of a dropped human always uses `(level 1, style 0)` (net `TAKEOVER_AI_LEVEL`).

### 5.15 Watchdog, stall handling, error containment (`AiWatchdog`, slot 2; codes W1–W8, scenario tests are S1–S13)

| Code | Detector | Reaction |
|---|---|---|
| W1 `Err.STALL_ECON` | income 0 for ≥ 1200 ticks and (no Collector or no Refinery) and credits < 1400 | EMERGENCY wants (Collector, then Refinery); ≥ 2400 ticks ⇒ phase `DESPERATE` |
| W2 `Err.STALL_QUEUE` | a production/construction line with 0 progress for ≥ 600 ticks while credits ≥ 100 and power ok | log, check prerequisites/power, cancel and re-issue once (refund), then blacklist the def for 1200 ticks |
| W3 `Err.CMD_LOOP` | same `(intent, key)` emitted ≥ 5 times in 200 ticks with no observable effect | blacklist the key 1200 ticks; `Err.CMD_LOOP` telemetry |
| W4 `Err.STALL_ARMY` | army value ≥ 30 % of estimated enemy and no op launched for 6000 ticks with posture ≥ BALANCED | force one AGGRESSIVE launch; lower `launch_ratio` by 10 % steps to a floor of 1.0 |
| W5 `Err.OP_TIMEOUT` | op past `timeout_tick`, or centroid moved < 2 cells with no combat for 600 ticks | abort op, release squads |
| W6 `Err.BUDGET_DEBT` | a module pass takes > 4 periods | log; double the period of optional modules (Micro, Scout) for 400 ticks |
| W7 `Err.EXCEPTION_BURST` | ≥ 5 AI error reports (`AiDebug.err()` wrapper around `push_error`) or invalid-id reads in 100 ticks | **Safe mode** for 1200 ticks: only Ingest, Economy, BuildPlanner, Production, Defense (basic) run |
| W8 `Err.STALL_POWER` | shortage ≥ 600 ticks | EMERGENCY Generator; pause non-emergency structures |

**Effect verification** (avoids AI_EXEC_LAG double-issue): `build_start` ⇒ `construction_state` leaves idle; `build_place` ⇒ a new structure id of that def appears in `own_ids()`; `train` ⇒ queue length +1; `research` ⇒ `research_active == def`; unit orders ⇒ `e_order`/position change; `use_power` ⇒ `power_status != READY`; wait `exec_lag_est + 2` ticks (3.1), retry ≤ 2 with back-off 20/60 ticks, then blacklist the parameter combination (e.g. the placement cell for 1200 ticks) and log `Err.NO_EFFECT` / telemetry 20. There is no rejection feedback channel (commands carry no tag and the sim skips illegal ones silently), so this state-based verification **is** the rejection handling; `can_*` validators keep the miss rate low, and the harness measures it via the sim's optional rejected-command counter (13.3).

### 5.16 How each bible rule in this domain is honored

| Bible rule | Where honored |
|---|---|
| Roster selection; replaced unit cannot also be built; unique units need their own stats | Roles resolved only from the roster's `producible_units` (5.5.1); AI never reads vanilla units of a subfaction; profiles per (roster, def) (5.3.5) |
| Economy: single currency, Collectors → Refineries, Refinery includes a Collector | 5.4.3 collector/refinery logic; Refinery-before-Collector preference |
| Technology: T1 open, Radar → T2, Radar + Laboratory → T3, producer always required; Dock never gates land/air tech; every roster playable land-only | `AiTechGraph` (5.5.3); Dock wants need a purpose and `dock_placeable`; `needs_water` handled by transports, never by requiring Docks for land/air |
| Production: one queue per Barracks/Factory/Airfield/Dock; one research queue; one construction queue | 5.4.1 (burn-rate gating, sequential build model), 5.6.2 per-producer queues |
| Research: 45/75 s, needs intact Radar (T2) / Radar + Laboratory (T3), losing prerequisites pauses orders, completed upgrades persist | 5.5.3–5.5.4; EMERGENCY rebuild of the paused prerequisite; research never re-bought |
| Power loss: production/research 50 %, powered defenses stop, powers cannot activate, superweapon recharge pauses; SAP reserve is not supply | 5.4.2 margin rules, EMERGENCY generator, power-shortage metric; reserve ignored in supply math |
| Support-power access: 3 powers, T2 needs powered Radar, T3 powered Radar + Laboratory, cost per use, cooldowns, ready at unlock, no reset on rebuild, recon anywhere / others need vision | 5.12 loop uses `power_status` and `power_target_ok` (real vision even for Brutal); `TargetRule` per power |
| Superweapon control: one per player, empty at start, single stored charge, recharge from activation, launcher loss cancels, shortage after activation doesn't cancel, AA can't intercept | 5.13: build policy, no-hold-beyond-need, guard wants, protection of Radar/Laboratory/Generators |
| Targeting and warnings: warning zones visible, decoys cannot hide countdowns | Dispersal reacts to visible zones (5.13.3); False Front / Feint / Convoy are used only as bait/feints, never assumed to hide SW |
| Damage and area notation: area attacks hurt friendlies; Aurora enemies only; buffs friendly | STRIKE friendly-fire penalty; Aurora `pen_own = 0`; BUFF eligibility by selector |
| Interception (Trident): packet −50 % with 8 charges, cap 50 %, Helios/Aurora bypass | 5.13.2 Trident rows; zone treated as `no_fire_artillery` for enemy AI; prefers beams/infantry/EMP vs Trident zones |
| Concealment and EW: camouflaged units revealed within 5 cells of a detector; firing/damage reveals | detector coverage in KB (Watchtower 4, AA battery 5, detector units 5); camouflage raids avoid it; `camo_alert` ⇒ detectors/recon (5.5.5) |
| Suppression, cover, smoke: 3 hits/2 s ⇒ −25 % speed 3 s; cover 4 s/45 s/20 %; Dust Screen two-sided | 5.9.1 suppression handling; COVER_DEPLOY handlers; SMOKE two-sided gate |
| Transports, aircraft, repairs: capacities; pads must be powered; carriers replenish own drones; heal/repair no stacking; stations can't repair themselves | 5.10.2 capacities, 5.10.4 pad/power logic, 5.12 no-stacking guardrail |
| Role tags | 5.5.1 uses the bible tags verbatim; special cases via explicit lists |
| Submarines and wrecks: only anti-submarine weapons hit submerged; wrecks persist 60 s and only the African Empire salvages; no salvage from friendly fire/scuttling/summons | ESCORT_SHIP for subs (5.5.5); salvage ops AE-only with the exclusion list (5.11) |
| Numbers the bible fixes (structure costs/times, Engineer 500, Collector 1400, MCV 3000, Landing Transport 900, build radius 8, start 7,500 + HQ) | quoted from the bible in 5.4–5.5; never overridden; wants use resolved defs |
| Floors/caps (cost/build time ≥ 60 %, reload ≥ 50 %, resistance ≤ 50 %) | applied by `GameData`; the AI reads only resolved values |
| Prototype priorities (first scout/tank/AA/siege/superweapon timings; salvage share; SW damage escaped; Tempest losses to AA; Dragonfall assembly survival; Trident charges) | harness metrics (section 10.3) |

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

The AI owns **no sim command and no sim event**. It owns (a) the **intent codes** it emits, (b) the **derived event records** it builds from state (because the thinker receives no event feed), and (c) the **telemetry codes** it publishes to the harness/log. Wire layouts are the sim's: a command is `PackedInt32Array [type, args...]` (net.md 5.5: type 0..255, size 1..1024, no pid/tag inside; the host stamps the pid). `AiCommandBuilder` is the only file that knows layouts, so a rename costs one file.

### 6.1 Intent codes (AI → command)
Unit-list commands carry a variable-length `ids` list (chunked to ≤ 48 per command) and, where noted, a `queue` flag. Codes 40..47 are fixed by combat.md 6.1; the rest are requested from sim_core (`ASSUMPTION(sim_core)`) and the AI-side `Intent` code is independent of the wire `type`.

| AI code | Intent | Wire command | Fields |
|---|---|---|---|
| 1 | BUILD_START | sim_core `BUILD_START` | `struct_def` |
| 2 | BUILD_PLACE | sim_core `BUILD_PLACE` | `struct_def, cx, cy` |
| 3 | BUILD_CANCEL | sim_core `BUILD_CANCEL` | — (watchdog deadlock breaker only) |
| 4 | TRAIN | sim_core `TRAIN` | `producer_eid, unit_def, count` |
| 5 | TRAIN_CANCEL | sim_core `TRAIN_CANCEL` | `producer_eid, slot` |
| 6 | QUEUE_HOLD | sim_core `QUEUE_HOLD` | `producer_eid, hold` |
| 7 | RESEARCH | sim_core `RESEARCH` | `res_def` |
| 8 | SET_RALLY | sim_core `SET_RALLY` | `producer_eid, x, y` |
| 9 | STRUCT_REPAIR | sim_core `SET_STRUCT_REPAIR` | `eid, on` |
| 10 | MOVE | sim_core `MOVE` | `ids, x, y, queue` |
| 11 | ATTACK_MOVE | **`CMD_ATTACK_MOVE` 41** | `ids, x, y, queue` |
| 12 | ATTACK | **`CMD_ATTACK` 40** | `ids, target_id, queue` (only if `targetable_now`; wrecks are force-fire only) |
| 13 | FORCE_FIRE | **`CMD_FORCE_FIRE` 44** | `ids, target_id (−1 = ground), x, y, count` |
| 14 | GUARD | **`CMD_GUARD` 42** | `ids, target_id (−1 = point), x, y` (aircraft: air patrol) |
| 15 | STOP | sim_core `CMD_STOP` | `ids` |
| 16 | SCATTER | sim_core `SCATTER` | `ids` |
| 17 | DEPLOY | abilities `CMD_DEPLOY` | `ids` (siege units, MCV, masts, Long Walker, Fortress Guard) |
| 18 | PACK | abilities `CMD_UNDEPLOY` | `ids` |
| 19 | SET_MODE | abilities `CMD_SET_MODE` | `ids, mode_idx` (Shinano, Protea, Raptor loadout, Shogun wing) |
| 20 | USE_ABILITY | abilities `USE_ABILITY` | `ids, ability_idx, x, y, target_id` (cover, shelter, puck, decoy, smoke launcher) |
| 21 | LOAD | sim_core `LOAD` | `ids, transport_id` |
| 22 | UNLOAD | sim_core `UNLOAD` | `transport_id, x, y` |
| 23 | GARRISON | sim_core `GARRISON` | `ids, building_id` |
| 24 | CAPTURE | sim_core `CAPTURE` | `ids, target_id` |
| 25 | REPAIR | sim_core `REPAIR` | `ids, target_id` |
| 26 | SALVAGE | sim_core `SALVAGE` | `ids, wreck_id` |
| 27 | HARVEST | sim_core `HARVEST` | `ids, deposit_id` |
| 28 | RETURN_TO_BASE | **`CMD_RETURN_TO_BASE` 47** | `ids` (aircraft / drones re-arm) |
| 29 | USE_POWER | sim_core `USE_POWER` | `power_def, x, y, angle, x2, y2` (`angle` = binary angle 0–4095 for corridor/line effects; `x2, y2` only for two-point powers) |
| 30 | LAUNCH_SW | sim_core `LAUNCH_SUPERWEAPON` | `x, y, angle` |
| 31 | HOLD | **`CMD_HOLD` 43** | `ids` (hold position: stationary-fire units, ambush groups) |
| 32 | SET_STANCE | **`CMD_SET_STANCE` 45** | `ids, stance (0..3)` (hold-fire until the ambush range) |

Deploying an MCV uses `DEPLOY`. Priority classes (0 emergency … 3 micro) and the APM bucket are AI-side only and never enter a command. Commands are validated by every peer's `CommandSystem` at the *execution* tick; a stale or illegal command is skipped deterministically (never an engine error), so the AI verifies effects by state (5.15) instead of receiving rejections.

### 6.2 Derived event records (state → `AiEventIngest`)
Because `thinker.call(world, out)` receives no events (and `world.events` belongs to presentation), the AI derives everything it needs; the record set and sources are in the table of 5.3.2 (`OWN_SPAWNED/LOST, OWN_DAMAGED, UNSEEN_HIT, ENEMY_SEEN/GONE, ENEMY_ARTY_FIRED, WRECK_SEEN, SW_WARNING, POWER_STATE, INCOME, RESEARCH_DONE, CONSTRUCTION_READY, PRODUCTION_DONE, PLAYER_DEFEATED`). Alert-class records pass through the reaction-delay queue; state-class records do not. **State reads this requires from the sim** (section 13): `strategic_warnings`, `income_total`, `e_last_fire` of visible enemy artillery, `wrecks_in_circle`, `construction_state`, `queue_of`, `research_done`, `player_alive`. If sim later exposes a persistent event ring (`events_since(cursor)`), `AiEventIngest` will consume it as an optimisation, never as a requirement.

The **harness** (an observer, not the AI) additionally reads raw sim events from `session.world().events` each tick batch (`auto_clear_events = true` lets the session clear them afterwards) for metrics that need causes: `INCOME.source` (salvage share), `ENTITY_REMOVED.killer_class` (Tempest drones lost to AA), `SW_END` stats (Trident charges, Dragonfall survivors).

### 6.3 Telemetry emitted (AI → harness/log; `func(pid, code, a, b, tick)`)
`1 FIRST_SCOUT_SENT (a=def)` · `2 FIRST_BARRACKS` · `3 FIRST_FACTORY` · `4 FIRST_RADAR` · `5 FIRST_LAB` · `6 FIRST_TANK (a=def)` · `7 FIRST_AA (a=def)` · `8 FIRST_SIEGE (a=def; artillery or HEAVY)` · `9 FIRST_AIRCRAFT` · `10 FIRST_NAVAL` · `11 SW_STRUCT_DONE` · `12 SW_LAUNCHED (a=x_c, b=y_c)` · `13 POWER_USED (a=power idx, b=benefit)` · `14 ATTACK_LAUNCHED (a=R_q8, b=value)` · `15 ATTACK_CONTACT` · `16 ATTACK_ABORTED (a=reason)` · `17 EXPANSION_DEPLOYED` · `18 DEFEND_STARTED (a=T_est)` · `19 STALL (a=Err code, b=detail)` · `20 CMD_REJECTED (a=intent, b=reason)` · `21 AI_ERROR (a=Err code)` · `22 TECH_SWITCH (a=Cat trigger)` · `23 RETREAT_ORDERED (a=units)` · `24 DISPERSAL (a=sw idx, b=units moved)` · `25 SALVAGE_DONE (a=credits)` · `26 LANDING_LAUNCHED` · `27 PHASE_CHANGE (a=phase)` · `28 POSTURE_CHANGE (a=posture)` · `29 OPENER_DONE` · `30 SAFE_MODE`. "First" events fire once per player; the harness records the tick. (`CMD_REJECTED` fires when effect verification gives up on an intent, 5.15.)

### 6.4 What other domains must add
Flagged in full in section 13: the read surface behind `AiWorldView` (3.3) — chiefly `strategic_warnings`, `income_total`, cell visibility/exploration, construction/queue introspection, neutral/deposit/wreck reads —, sim_core command encoders for the intents above, the per-level think period and unpaced headless driver in net, and the `DefPower`/`DefSuperweapon` fields listed in 13.10.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

All files live in `game/data/balance/ai/`, UTF-8, LF, `"schema": 1`. `AiDataStore.load_dir()` loads them in this fixed order and computes `ai_data_hash = FNV-1a32` over the concatenated bytes: `ai_tuning.json, ai_difficulty.json, ai_roles.json, ai_composition.json, ai_powers.json, ai_faction_ae.json, ai_faction_def.json, ai_faction_han.json, ai_faction_napc.json, ai_faction_nec.json, ai_faction_olm.json, ai_faction_pd.json, ai_faction_sap.json`. Unknown keys are load errors. All ids are the bible's stable ids (`AiDataStore` resolves them to dense def indices through `GameData` at load); roles/handlers/flags are upper-case names from section 4; `as_enemy_prior` keys are the lower-case `Cat` names (`static` = `STATIC_DEF`).

### 7.1 `ai_difficulty.json` — one profile per difficulty (Hard and Brutal shown; Easy/Medium per table 5.14.1)
```json
{
  "schema": 1,
  "profiles": {
    "hard": {
      "id": 2, "label": "Hard", "label_cheats": "",
      "think_period_ticks": 10, "micro_period_ticks": 4, "apm_cap": 180, "cmd_burst": 16,
      "reaction_delay_ticks": 12, "idle_tolerance_ticks": 20, "queue_depth": 3, "place_latency_ticks": 10,
      "opt_step_keep_pct": 100, "info_omniscient": false, "scout_level": 2, "expansions_max": 2,
      "collector_k_x10": 20, "tech_delay_x100": 100, "first_attack_min_s": 420, "wave_interval_s": 120,
      "launch_ratio_x100": 130, "est_noise_pct": 10, "micro_retreat": true, "micro_focus": true, "micro_kite": true,
      "dodge_pct": 100, "powers_level": 3, "eager_pct": 100, "sw_min_time_s": 660, "unit_cap_pct": 100,
      "wu_per_tick": 500, "call_cap_wu": 3000, "jitter_pct": 15, "handicap_pct": 100,
      "prongs_max": 3, "harass_ops_max": 2, "enemy_prior": 2
    },
    "brutal": {
      "id": 3, "label": "Brutal", "label_cheats": "ai.cheats.brutal",
      "think_period_ticks": 6, "micro_period_ticks": 2, "apm_cap": 320, "cmd_burst": 28,
      "reaction_delay_ticks": 4, "idle_tolerance_ticks": 4, "queue_depth": 3, "place_latency_ticks": 2,
      "opt_step_keep_pct": 100, "info_omniscient": true, "scout_level": 3, "expansions_max": 3,
      "collector_k_x10": 22, "tech_delay_x100": 85, "first_attack_min_s": 330, "wave_interval_s": 90,
      "launch_ratio_x100": 120, "est_noise_pct": 4, "micro_retreat": true, "micro_focus": true, "micro_kite": true,
      "dodge_pct": 100, "powers_level": 4, "eager_pct": 85, "sw_min_time_s": 540, "unit_cap_pct": 100,
      "wu_per_tick": 600, "call_cap_wu": 3000, "jitter_pct": 10, "handicap_pct": 120,
      "prongs_max": 4, "harass_ops_max": 3, "enemy_prior": 2
    }
  }
}
```

### 7.2 `ai_roles.json` — role rules, explicit role lists, unit handlers
```json
{
  "schema": 1,
  "roles": {
    "INFANTRY_BASIC": {"all": ["infantry", "combat"], "none": ["anti_tank", "specialist", "detector"]},
    "INFANTRY_AT": {"all": ["infantry", "anti_tank"]},
    "SCOUT_LIGHT": {"all": ["scout", "land_vehicle", "combat"], "tier_max": 1},
    "TANK_MAIN": {"all": ["tank", "land_vehicle"], "none": ["siege"], "pick": "lowest_tier"},
    "HEAVY": {"all": ["tank", "siege"]},
    "AA_MOBILE": {"all": ["anti_air", "land_vehicle"]},
    "ARTILLERY": {"all": ["artillery", "land_vehicle"], "pick": "lowest_tier"},
    "FIGHTER": {"all": ["aircraft", "anti_air"]},
    "BOMBER": {"all": ["aircraft", "ground_attack"]},
    "ESCORT_SHIP": {"all": ["ship", "anti_air", "anti_submarine"]}
  },
  "unit_roles": {
    "HEALER": ["unit.napc.combat_medic"],
    "COMMAND_PROVIDER": ["unit.han.link_operator", "unit.han.dragon_command_walker", "unit.han.long_command_walker", "unit.han.mekong_field_engineer"],
    "STATIONARY_FIRE": ["unit.napc.javelin_team", "unit.nec.spike_team", "unit.sap.kavach_team"],
    "SALVAGER": ["unit.shared.engineer", "unit.ae.reclaimer", "unit.ae.river_warden"]
  },
  "unit_handlers": {
    "unit.han.link_operator": ["ESCORT_PROVIDER"],
    "unit.pd.shinano_adaptive_tank": ["MODE_SWITCH"],
    "unit.sap.shaheen_missile_battery": ["DEPLOY_SIEGE", "SHOOT_SCOOT"]
  }
}
```
(The full file lists every role in 5.5.1 and every handler row of 5.9.5.)

### 7.3 Faction doctrine file `ai_faction_<code>.json` — schema
Top level: `faction` (id), `as_enemy_prior` (percent per `Cat` name, used by opponents' `AiEnemyProfile`), `base` (see below), `rosters` (exactly the faction's four roster ids; each value is an overlay object, `{}` for vanilla).
`base` and every overlay may contain: `personality` (int overrides), `style` (list of `{style, w}`), `expand` (`EARLY|DEFENDED|LATE|MINIMAL`), `flags` (base) / `flags_add` / `flags_remove`, `opener` (base) / `opener_patch`, `targets` / `targets_patch`, `composition` / `composition_patch`, `research` / `research_patch`, `power_policy`. Patch semantics: 5.5.2.

**Worked example — `ai_faction_napc.json` (base + USA, Canada, Mexico overlays):**
```json
{
  "schema": 1,
  "faction": "faction.napc",
  "as_enemy_prior": {"air": 12, "armor": 40, "infantry": 22, "artillery": 12, "naval": 8, "sub": 0, "camo": 0, "static": 6, "light": 10, "transport": 8},
  "base": {
    "personality": {"aggression": 50, "tech": 50, "economy": 55, "defense_pct": 15, "harass_pct": 10, "air": 15, "naval": 10, "siege": 40, "infantry": 40, "dispersion": 3, "micro": 60, "sw_priority": 60, "retreat_hp_pct": 50, "return_hp_pct": 75},
    "style": [{"style": "PUSH", "w": 70}, {"style": "PRONG", "w": 30}],
    "expand": "EARLY",
    "flags": ["PRESERVE_VEHICLES", "APRON_RETREAT", "SIEGE_DEPLOY"],
    "opener": [
      {"id": "gen1", "op": "build", "struct": "generator"},
      {"id": "ref1", "op": "build", "struct": "refinery"},
      {"id": "rax1", "op": "build", "struct": "barracks"},
      {"id": "inf1", "op": "train", "role": "INFANTRY_BASIC", "n": 2, "parallel": true, "when": {"have": {"struct": "barracks", "n": 1}}},
      {"id": "fac1", "op": "build", "struct": "factory"},
      {"id": "scout1", "op": "train", "role": "SCOUT_LIGHT", "n": 1, "parallel": true, "when": {"have": {"struct": "factory", "n": 1}}},
      {"id": "tank1", "op": "train", "role": "TANK_MAIN", "n": 2, "parallel": true, "when": {"have": {"struct": "factory", "n": 1}}},
      {"id": "rad1", "op": "build", "struct": "radar"},
      {"id": "gen2", "op": "build", "struct": "generator", "parallel": true, "when": {"power_margin_lt": 40}},
      {"id": "exp1", "op": "expand", "kind": "refinery_site", "escort_role": "TANK_MAIN", "escort_n": 2, "opt": true, "parallel": true, "when": {"have": {"role": "TANK_MAIN", "n": 2}}},
      {"id": "aa1", "op": "train", "role": "AA_MOBILE", "n": 2, "parallel": true, "when": {"tier_ge": 2}},
      {"id": "art1", "op": "train", "role": "ARTILLERY", "n": 2, "parallel": true, "when": {"have": {"role": "AA_MOBILE", "n": 2}}},
      {"id": "res1", "op": "research", "research": "research.napc.adaptive_plating", "opt": true, "parallel": true, "when": {"tier_ge": 2}}
    ],
    "targets": [
      {"id": "t_ref2", "from_s": 180, "struct": "refinery", "n": 2},
      {"id": "t_rax2", "from_s": 240, "struct": "barracks", "n": 2},
      {"id": "t_fac2", "from_s": 300, "struct": "factory", "n": 2},
      {"id": "t_lab", "from_s": 420, "struct": "laboratory", "n": 1},
      {"id": "t_air", "from_s": 480, "struct": "airfield", "n": 1, "when": {"enemy_seen": "air"}},
      {"id": "t_ref3", "from_s": 600, "struct": "refinery", "n": 3}
    ],
    "composition": {
      "opening": {"INFANTRY_BASIC": 40, "INFANTRY_AT": 20, "SCOUT_LIGHT": 10, "TANK_MAIN": 30},
      "buildup": {"INFANTRY_BASIC": 25, "INFANTRY_AT": 15, "TANK_MAIN": 35, "AA_MOBILE": 10, "ARTILLERY": 10, "HEALER": 5},
      "midgame": {"INFANTRY_BASIC": 15, "INFANTRY_AT": 12, "TANK_MAIN": 30, "AA_MOBILE": 8, "ARTILLERY": 15, "HEAVY": 12, "FIGHTER": 4, "HEALER": 4},
      "late": {"INFANTRY_BASIC": 10, "INFANTRY_AT": 10, "TANK_MAIN": 25, "AA_MOBILE": 8, "ARTILLERY": 15, "HEAVY": 20, "FIGHTER": 6, "BOMBER": 6}
    },
    "research": [
      {"id": "research.napc.adaptive_plating", "prio": 30, "when": {"all": [{"have": {"role": "TANK_MAIN", "n": 4}}, {"any": [{"enemy_share_ge": {"cat": "artillery", "pct": 15}}, {"army_units_ge": 12}]}]}},
      {"id": "research.napc.joint_tactical_links", "prio": 60, "when": {"all": [{"have": {"role": "AA_MOBILE", "n": 2}}, {"have": {"role": "INFANTRY_BASIC", "n": 6}}]}}
    ],
    "power_policy": {"power.napc.combined_arms_window": {"engaged_min": 8}}
  },
  "rosters": {
    "roster.napc.vanilla": {},
    "roster.napc.usa": {
      "personality": {"aggression": 55, "tech": 60, "economy": 50, "defense_pct": 10, "air": 65, "naval": 5, "siege": 20, "infantry": 35},
      "style": [{"style": "AIR", "w": 80}, {"style": "PUSH", "w": 20}],
      "flags_add": ["AIR_LOADOUT"],
      "opener_patch": {
        "insert_after": {
          "rad1": [{"id": "af1", "op": "build", "struct": "airfield"}],
          "aa1": [{"id": "ftr1", "op": "train", "role": "FIGHTER", "n": 2, "parallel": true, "when": {"have": {"struct": "airfield", "n": 1}}}]
        }
      },
      "targets_patch": {"replace": {"t_air": {"id": "t_air", "from_s": 300, "struct": "airfield", "n": 2}}},
      "composition_patch": {
        "midgame": {"FIGHTER": 22, "BOMBER": 12, "HEAVY": null, "ARTILLERY": 6},
        "late": {"FIGHTER": 25, "BOMBER": 22, "HEAVY": null, "ARTILLERY": 6}
      },
      "research_patch": {"append": [{"id": "research.napc.dispersed_runways", "prio": 30, "when": {"have": {"struct": "airfield", "n": 1}}}]}
    },
    "roster.napc.canada": {
      "personality": {"aggression": 45, "tech": 45, "naval": 45, "siege": 30, "infantry": 45},
      "style": [{"style": "LANDING", "w": 60}, {"style": "PRONG", "w": 40}],
      "expand": "DEFENDED",
      "flags_add": ["AMPHIBIOUS_ROUTES", "TRANSPORT_ASSAULT"],
      "opener_patch": {
        "replace": {
          "inf1": {"id": "inf1", "op": "train", "role": "INFANTRY_BASIC", "n": 3, "parallel": true, "when": {"have": {"struct": "barracks", "n": 1}}},
          "tank1": {"id": "tank1", "op": "train", "role": "TANK_MAIN", "n": 2, "parallel": true, "when": {"tier_ge": 2}}
        },
        "insert_after": {
          "scout1": [{"id": "scout2", "op": "train", "role": "SCOUT_LIGHT", "n": 2, "parallel": true, "when": {"have": {"struct": "factory", "n": 1}}}],
          "rad1": [{"id": "dock1", "op": "build", "struct": "dock", "opt": true, "parallel": true, "when": {"all": [{"dock_placeable": true}, {"any": [{"map_trait": {"name": "water", "ge_pct": 10}}, {"flag": "TRANSPORT_ASSAULT"}]}]}}]
        }
      },
      "research_patch": {"append": [{"id": "research.napc.sealed_compartments", "prio": 40, "when": {"have": {"role": "AMPHIBIOUS", "n": 4}}}]}
    },
    "roster.napc.mexico": {
      "personality": {"aggression": 65, "tech": 35, "defense_pct": 10, "air": 5, "siege": 20, "infantry": 75},
      "style": [{"style": "PRONG", "w": 70}, {"style": "PUSH", "w": 30}],
      "flags_add": ["SHELTER_COVER", "CAPTURE_POINTS"],
      "opener_patch": {
        "insert_after": {"rax1": [{"id": "rax2", "op": "build", "struct": "barracks"}]},
        "replace": {"inf1": {"id": "inf1", "op": "train", "role": "INFANTRY_BASIC", "n": 6, "parallel": true, "when": {"have": {"struct": "barracks", "n": 1}}}},
        "append": [{"id": "sup1", "op": "train", "role": "INFANTRY_SUPPORT", "n": 2, "parallel": true, "when": {"tier_ge": 2}}]
      },
      "research_patch": {"append": [{"id": "research.napc.section_logistics", "prio": 40, "when": {"have": {"role": "INFANTRY_BASIC", "n": 12}}}]}
    }
  }
}
```
Notes: Canada's `tank1` is gated on `tier_ge: 2` because its `TANK_MAIN` (Narwhal) is a T2 unit (validator V3); the bible opener "infantry and Beavers until Radar unlocks Narwhals" falls out of `inf1` + `scout1/scout2`; `dock1` is `parallel` so a land-locked map never stalls the spine. USA has no `HEAVY` (Bastion removed) so its weight is deleted; `AiRoleResolver` would drop it anyway.

### 7.4 `ai_composition.json` — global counter table (5.5.5)
Multipliers are Q8 (512 = ×2.0); `structs` produce COUNTER wants (prio 25).
```json
{
  "schema": 1,
  "hysteresis_ticks": 6000,
  "counters": {
    "air": {
      "trigger": {"share_ge": 15, "or_seen": 3, "within_ticks": 1200},
      "mult": {"AA_MOBILE": 512, "FIGHTER": 410, "BOMBER": 179},
      "strong": {"share_ge": 30, "mult": {"AA_MOBILE": 768, "FIGHTER": 563, "BOMBER": 154}},
      "structs": [{"struct": "aa_battery", "per": "production_cluster", "max": 4}]
    },
    "armor": {
      "trigger": {"share_ge": 35},
      "mult": {"INFANTRY_AT": 461, "BOMBER": 333, "HEAVY": 333, "TANK_MAIN": 230},
      "structs": [{"struct": "at_turret", "per": "approach", "max": 3}]
    },
    "infantry": {"trigger": {"share_ge": 45}, "mult": {"INFANTRY_BASIC": 358, "ARTILLERY": 333, "INFANTRY_AT": 128}, "structs": [{"struct": "watchtower", "per": "refinery", "max": 3}]},
    "artillery": {"trigger": {"share_ge": 20, "or_seen": 3}, "mult": {"SCOUT_LIGHT": 384, "BOMBER": 384, "FIGHTER": 333}, "structs": []},
    "sub": {"trigger": {"seen": true}, "mult": {"ESCORT_SHIP": 512}, "structs": []},
    "camo": {"trigger": {"seen": true}, "min_detector_pct": 10, "structs": [{"struct": "watchtower", "per": "key_site", "max": 4}]},
    "static": {"trigger": {"share_ge": 30}, "mult": {"ARTILLERY": 410, "HEAVY": 333, "SIEGE_SHIP": 333}, "sw_priority_add": 20, "structs": []}
  }
}
```

### 7.5 `ai_powers.json` — per-power / per-superweapon AI parameters (all 48 + 8 entries; three shown)
Keys are bible ids; radius, duration, cost, cooldown, warning, packet offsets and line length/width come from the resolved `DefPower`/`DefSuperweapon` (`ai_powers.json` never duplicates them). `arch` ∈ `PowerArch` names; `min_level` gates by `powers_level`; `emergency` (bool) bypasses the power-spend cap; `gate` is a list of named predicates implemented in `AiPowerArch` (a fixed vocabulary: `no_enemy_within_12`, `min_eligible_3`, `missing_ge_15pct`, `with_op_launch`, `scouted_cell_25_from_path`, `stationary_only`, `base_under_attack`, `finisher`, `two_sided_ok`, `zero_detectors_visible`, `aurora_warning_covers_6_vehicles`, ...).
```json
{
  "schema": 1,
  "powers": {
    "power.napc.field_repair_drop": {
      "arch": "REPAIR_ZONE", "min_level": 1, "sel": ["land_vehicle"], "eff_total_q8": 51,
      "min_ratio_x100": 120, "min_gap_ticks": 600,
      "gate": ["no_enemy_within_12", "min_eligible_3", "missing_ge_15pct"], "after": "gather_damaged"
    },
    "power.napc.uav_sweep": {
      "arch": "REVEAL", "min_level": 1, "purpose": ["SCOUT", "DETECT"], "min_ratio_x100": 100, "min_gap_ticks": 3000
    },
    "power.olm.false_convoy": {
      "arch": "DECOY", "min_level": 2, "util_value": 600, "min_ratio_x100": 100, "min_gap_ticks": 2400,
      "gate": ["with_op_launch", "scouted_cell_25_from_path"]
    },
    "superweapon.napc.atlas_kinetic_array": {
      "arch": "SW_MULTI_CIRCLE", "angles": 16,
      "mobile_w_q8": 64, "pen_own_q8": 384, "prefer": ["superweapon", "laboratory", "factory", "headquarters"], "combo": false
    }
  }
}
```

### 7.6 `ai_tuning.json` — global constants (no code changes needed to retune)
```json
{
  "schema": 1,
  "strength": {"launch_ratio_x100": 130, "abort_ratio_x100": 70, "home_adv_pct": 10, "unseen_reserve_pct": 35, "assumed_base_a0": 1500, "assumed_base_a1_per_min": 900, "range_q8_per_cell": 8, "unit_stale_ticks": 100, "target_stale_ticks": 1200},
  "threat": {"block_shift": 13, "decay_ticks": 600, "defense_radius_c": 16},
  "econ": {"reserve_credits": 300, "burn_horizon_s": 30, "margin_min": {"easy": 0, "medium": 10, "hard": 20, "brutal": 20}, "collector_slots_per_field": 3, "army_min_share_pct": 45, "power_spend_cap_pct": 15, "excess_cash_credits": 2500, "excess_cash_discount_pct": 40},
  "army": {"stage_gather_pct": 80, "stage_timeout_ticks": 900, "waypoint_spacing_c": 12, "regroup_pct": 70, "regroup_timeout_ticks": 200, "min_wave_units_base": 6, "min_wave_units_cap": 24, "reserve_frac_pct": {"turtle": 50, "balanced": 25, "aggressive": 10, "all_in": 0}},
  "retreat": {"default_hp_pct": 35, "infantry_hp_pct": 20, "return_hp_pct": 85},
  "sw": {"min_score": 4000, "hold_max_ticks": {"easy": 5400, "medium": 1800, "hard": 900, "brutal": 400}, "candidates_k": 10, "angles": 16},
  "map_mods": {"open": {"prongs_add": 1, "defense_pct_add": -3}, "urban": {"infantry_add": 10, "prongs_add": -1, "garrison": 1}, "coast": {"naval_add": 10, "amph_route_bias": 1}}
}
```

### 7.7 Validation rules (`AiDataValidator`, run at load, by `tools/gd check`, and in `test_ai_data`)
V1 every id named by a patch (`remove/replace/insert_*`, `power_policy`, `research_patch`) exists; V2 for **each of the 32 rosters** every `struct`, `role`, `def`, `research` and `power` reference in the merged script resolves to a def the roster owns (a role resolving to zero defs is an error only if a non-`opt` step or a weight ≥ 10 uses it); V3 a `train` step whose role's minimum tier is *T* must be gated (by its own `when` or by an earlier blocking step) on structures that make tier *T* reachable — e.g. `TANK_MAIN` for Canada/Eurocorps/Russia/China/Japan/India/South Africa requires `tier_ge: 2`; V4 all 48 support powers and 8 superweapons have an entry with a valid `arch` and `min_level`; V5 every research id of every roster has a `when` gate (or falls back to the default gate with a warning); V6 personality fields within ranges (4.3); V7 style weights sum > 0; V8 flag/handler/role names valid; V9 no unknown `AiCond` keys; V10 difficulty rows complete, **only Brutal** may set `info_omniscient` or `handicap_pct ≠ 100`; V11 patches do not create duplicate step ids; V12 `as_enemy_prior` sums to ≤ 100 per category group. Any error blocks loading (AI falls back to a built-in minimal doctrine and raises `Err.DATA_MISSING`).

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

* **The AI is outside the deterministic core** (ARCHITECTURE §1.4, DR-14; net.md I3): nothing in `game/src/ai/**` enters `SimWorld.checksum()`. Its influence on the sim is *exclusively* the ordinary commands it appends to `out`, which net injects into the turn bundles, records and replays like human ones; AI mistakes can therefore never desync clients (all peers reject an illegal command identically), and replay playback never needs the AI.
* **Sim-side fields I depend on that must be in the checksum** (already required by net.md XR-9): the per-player `handicap` (Brutal's 120) is stored in player state and checksummed by the sim; the `MatchConfig` (which records each AI slot's level/style) is hashed into the lobby handshake and replay header. Nothing else from the AI needs to enter the checksum.
* **Reproducible AI (harness contract).** Same `(AiMatchSpec, match_seed, engine build, ai_data_hash, game data hash)` ⇒ same command stream, same `cmd_log_hash`, same `AiFactory.state_hash()` at ticks 1000/5000/10000, same final `SimWorld.checksum()` (verified by `NetSelfTest.run_double` in AI mode, net.md 5.6). Guaranteed by:
  1. **RNG** — only `AiRng`, seeded with the `mix32`-derived seed net passes to the factory (5.14.3); never `randi/randf/randomize/shuffle/pick_random`, never `SimRng` (would mutate sim state).
  2. **No wall-clock in decisions** — `Time.*`/`OS.get_ticks_*` appear only in `AiPerf` and `harness/`; output of `AiPerf` is written to metrics and never read by a module (lint-enforced, 10.1). Work is budgeted by **counts** (wu), so a slower machine produces the same commands later in wall time, never different commands (DR-11 spirit).
  3. **Ordering** — every iteration that can affect a decision walks arrays in ascending entity id (or ascending row/cell index); `Dictionary` is used only with `int`/`String` keys inserted in deterministic order and never iterated when order matters; `sort_custom` comparators are total orders (tie-break by eid, then row, then cell index) — DR-6/DR-7.
  4. **Arithmetic** — decision math is `int`; where floats appear (never required) only `+ − × ÷` and comparisons are allowed; **no** `sin/cos/atan2/sqrt/pow/exp/log/floor/round` on decision values — use `Fp.sin/cos/atan2/isqrt/dist` (DR-4). Products are bounded `< 2^62` (DR-5). This makes AI decisions bit-identical across macOS arm64 / Linux x86_64 / Windows, which the canary test (10.4) exercises even though netplay does not require it (the AI runs on the host only).
  5. **Derived-event timing** — alert records are queued with `ready_tick = tick + reaction_delay` and dispatched in `(ready_tick, derivation order)`; derivation order is fixed (ascending eid merges, 5.3.2). The think *cadence* is decided by net (`(E + pid) % period`) and is identical across runs of the same match, so `dt` per think is reproducible.
  6. **Read purity** — every `AiWorldView` accessor is a pure read; the AI never calls a sim method with side effects (lint: no assignment to `world.*`, no calls outside the documented read API).
* **Replays / saves.** AI commands are in the recorded turn bundles; playback runs without any thinker. AI internal state is not saved; mid-match attach (`bootstrap_from_world`) reconstructs from sim state, so a "load game" resumes AI play without persisted AI memory (knowledge is re-learned: ghosts start from presumed HQs).
* **`AiController.state_hash()`** = FNV-1a32 over, in this order: `AiRng.state`, `phase`, `posture`, `primary_enemy`, script pointer + per-step state bytes, `wants` (id, state), `ops` (id, type, state, squad count), `squads` (id, kind, unit count), KB counts (own rows, enemy rows, ghosts), last 64 emitted `(intent, key)` pairs. It is compared by `repeat_check` and logged into `AiMatchResult`.

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

**Target:** ≤ 1.5 ms average per AI per tick on an M-class CPU (≈ 500 wu at ~3 µs/wu, Hard). Calibrated by `AiPerf` in the harness (`ai_us_avg`), with the wu→µs factor re-measured each release; the budget mechanism (5.2) guarantees the *cap*, the module design keeps the *typical* cost far below it.

**Per-think view.** Net calls a thinker every `P` turns (`dt = 2P` ticks); a think costs `dt ×` the per-tick figures below (budget `min(avg × dt, call_cap_wu)`). Hard at `P = 2` (`dt = 4`): typical mid-fight ≈ 740 wu ≈ 2.2 ms per think (within net's "≤ 3 ms typical"), cap 3000 wu ≈ 9 ms. Hard at net's default `P = 5` (`dt = 10`): ≈ 1850 wu ≈ 5.5 ms mid-fight, still under net's 12 ms throttle because `call_cap_wu` bounds the tail — but micro/dodge then act at 0.5 s granularity, hence request 13.16 (per-level periods `[5, 3, 2, 1]`).

Assumptions for the estimate: 150 own units + 50 structures, 120 visible enemies, 200 ghosts, ≤ 20 wants, ≤ 6 ops, ≤ 12 squads, Hard cadence.

| Module | Cadence | Quota (wu/run) | Typical wu/tick (mid-fight) | Peaceful wu/tick |
|---|---|---|---|---|
| Ingest (change detection + own refresh 15 rows/tick × 3 + enemy sweep 24 rows/tick × 2.5) | 1 | 120 | ~115 | ~55 |
| KB upkeep (ghost validation, profile decay) | 5 | 40 | 8 | 4 |
| Watchdog | 100 | 20 | 0.2 | 0.2 |
| Dispersal | 2 | 40 | 2 | 1 |
| Economy | 10 | 50 | 3 | 3 |
| BuildPlanner (+ placement job ~15 ticks per placement) | 10 | 80 (+40) | 4 (+2) | 4 |
| Tech | 40 | 30 | 0.8 | 0.8 |
| Production | 5 | 60 | 6 | 6 |
| Strategy | 40 | 60 | 1.5 | 1.5 |
| Defense | 10 | 40 | 2 | 1 |
| AttackPlanner | 40 | 60 | 1 | 1 |
| Ops (≤ 6 ops × ~40 wu / 10 ticks) | 1 | 80 | 24 | 6 |
| Powers (+ SW job when ready) | 10 | 60 (+40) | 3 | 2 |
| Micro (≤ 24 units/tick) | 4 | 60 | 10 | 0 |
| Repair + Engineers + Scout | 20 | 40 | 2 | 2 |
| **Total** | | | **≈ 185 wu ≈ 0.55 ms** | **≈ 90 wu ≈ 0.27 ms** |

* **Steady-state ceiling** if every quota were exhausted: `Σ quota/period ≈ 290 wu/tick + jobs 80 ≈ 370 wu` (< 500 avg cap) — the avg budget is therefore never the binding constraint in steady state.
* **Spike bound.** A think never exceeds `call_cap_wu` (Hard 3000 wu ≈ 9 ms; `dt` = 2 ticks (period 1) ⇒ `min(1000, 3000)` = 1000 wu ≈ 3 ms, i.e. net's "≤ 3 ms each"); overshoot from diff bursts becomes `debt` (5.2). Net staggers thinkers by pid, so at most `ceil(n_ai / period)` thinkers run per boundary.
* **8 AIs (8-player LAN, all AI):** typical `8 × 0.55 = 4.4 ms` per tick averaged (9 % of the 50 ms tick); governor-capped worst case `2400 wu ≈ 7.2 ms` per tick. Per boundary frame net runs `ceil(8 / P)` thinkers (P = 5 ⇒ 2, P = 2 ⇒ 4, P = 1 ⇒ 8); with the recommended per-level periods a mixed lobby stays below ≈ 9 ms on the busiest boundary. The sim's own per-tick cost is budgeted by its domain; the AI never runs on clients.
* **Memory** per AI < 1 MB: entity tables (≤ 512 rows × 13 arrays × 4 B ≈ 27 KB), ghosts (768 × 11 × 4 ≈ 34 KB), threat map (1024 blocks × 2 × 4 B = 8 KB), squads/ops/wants (< 20 KB), trace ring (256 × 16 B); shared (immutable): route graph per move class (1024 nodes × 6 classes ≈ 50 KB), unit profiles (8 rosters × 185 defs × ~120 B ≈ 180 KB), role tables.

**Worst cases and mitigations**

| Worst case | Cost driver | Mitigation |
|---|---|---|
| Mass deaths (Perun/Helios hits 100 units) | 100 `OWN_LOST`/`ENEMY_GONE` records derived in one think | 1 wu each; overshoot ⇒ debt repaid over the next thinks; `reaction_delay` spreads dispatch |
| SW target search on 500 ghosts | 10 candidates × 16 angles × ~20 ghosts ≈ 3200 point tests | resumable job (40 wu/tick ⇒ ~10 ticks); only when READY, once per 6–8 min |
| Placement search (200 cells × `can_place` at 5 wu) | 1000 wu | lattice step 2 first (50 cells = 250 wu), refine top-4; job at 40 wu/tick |
| A* on a 256×256 map | 1024 nodes × 2 wu ≈ 2000 wu | job; cached routes valid 600 ticks unless threat changes > 2× |
| 8 AIs × large armies | Ingest linear in visible entities | rolling cursors (never all rows in one tick), per-tick caps (24 micro units, 24 enemy rows) |
| Command bursts | APM cap + token bucket | `flush()` drains ≤ tokens; class-0/1 reserved 30 % |
| GDScript call overhead on `AiWorldView` | ~6 field reads per entity row | one `read_row` per entity (member access on the borrowed `SimEntity`), batch lists (`own_ids`, `visible_enemy_ids`), rows cached ≤ 10 ticks |
| Debug/trace overhead | string building | trace stores int codes only; strings materialized on demand when `debug_level ≥ 1` |

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

All tests are `game/tests/test_ai_*.gd` (`RefCounted`, `func run(t: TestCtx) -> void`), runnable with `tools/gd test ai`. Unit tests use `AiMockWorldView` (scriptable `AiWorldView` subclass) and never need a full `SimWorld`; scenario tests build a real headless `SimWorld` via the harness bootstrap.

### 10.1 Unit tests

| Test file | Cases and expected values |
|---|---|
| `test_ai_rng` | `mix32(1) == 0x514E28B7`, `mix32(0xDEADBEEF) == 0x0DE5C6A9` (net vectors); `seed_from(0x514E28B7)` ⇒ six `next_u32()` = `524866043, 2877414208, 2380002740, 2664205378, 3890067424, 1964142960`; fresh RNG six `range_i(−15, 25)` = `18, −1, −2, 25, −4, 20`; `seed_from(0)` ⇒ `state() == 0x9E3779B9`, first two = `1359758873, 3761132862`; `thinker_seed(12345, 1) == 0x8739D20C` with first three = `309959344, 81710791, 2110671044`; `hash_str("") == 0x811C9DC5`, `hash_str("a") == 0xE40C292C`. |
| `test_ai_budget` | `reset(500, 1000)`; `spend(600)` ⇒ `left 0`, `debt 100`, returns false; next `reset(500, 1000)` ⇒ `pay = min(100, 250) = 100`, `left = 400`; no carry: leaving 300 unspent then `reset(500, 1000)` ⇒ `left = 500`; `reset(5000, 3000)` ⇒ `left = 3000`. |
| `test_ai_scheduler` | slot periods per difficulty; due-slot arithmetic for `dt` ∈ {1, 2, 4, 10, 50} (a slot runs once per think, quota × min(4, ceil(dt/period))); starvation guard: a slot skipped 3× gets its quota reserved; 10 000 ticks of synthetic thinks at each `dt` ⇒ mean `wu/tick ≤ wu_per_tick`, every think `≤ call_cap_wu`. |
| `test_ai_command_builder` | one order per unit per think (last wins); chunking: 100 units ⇒ 3 commands (48/48/4), each `PackedInt32Array` size ≤ 1024 with `type ≤ 255`; APM Hard (dt 10): refill `180×256×10/1200 = 384` Q8 tokens, capacity `16×256`, 100 class-2 intents in one think ⇒ ≤ 16 emitted **and** the 30 % reserve keeps class 0–1 usable (a `use_power` still emits); `flush` never appends more than 64 commands; `note_no_effect` blacklists the key for 1200 ticks; combat intents encode to types 40..47 exactly as combat.md 6.1 (ATTACK 40, ATTACK_MOVE 41, GUARD 42, HOLD 43, FORCE_FIRE 44, SET_STANCE 45, RETURN_TO_BASE 47). |
| `test_ai_cond` | compile/eval each vocabulary key on a mock; unknown key ⇒ error string; `all/any/not` truth table; `have_lt`; `tier_ge` from completed structures only. |
| `test_ai_roles` (all 32 rosters) | essentials present: `INFANTRY_BASIC, INFANTRY_AT, SCOUT_LIGHT, TANK_MAIN, AA_MOBILE, FIGHTER`; **`TANK_MAIN` tier == 2 exactly for** canada, eurocorps, russia, china, japan, india, south_africa (others 1); `ARTILLERY` absent **only** for `roster.pd.japan` (its Shinano covers siege); `HEALER` present only for NAPC rosters except Mexico (Aguila replaces the Medic); `HEAVY` absent for usa, nordics, algeria, el_andalus, kazakhstan, all PD, all HAN, nigeria, thailand; a replaced def (e.g. `unit.napc.guardian_tank` in Canada) never appears in any role list. |
| `test_ai_tech_graph` | `missing(radar)` from empty = `[generator, refinery, factory, radar]`; `missing(laboratory)` after those = `[laboratory]`; `missing(superweapon)` from empty = `[generator, refinery, factory, radar, laboratory, superweapon]`; `missing(dock)` = `[generator, refinery, dock]`; `missing(watchtower)` = `[generator, barracks, watchtower]`. |
| `test_ai_strength` | vectors of 5.3.4: 10 tanks vs 6 tanks + 2 turrets ⇒ `R_q8 == 296` (< 332 hold); 14 tanks ⇒ `581` (launch); defender dps 0 ⇒ `4096` (16×256); artillery-screen penalty applies when artillery dps share 50 % and non-artillery hp share 20 % (`dpsA × 205 >> 8`); noise stable within a 200-tick epoch. |
| `test_ai_economy` | allocation vector: `credits 200, income 5/s`, wants `[research 1000cr/45s prio 30, tank 900cr/400t prio 40]` ⇒ `burn_cap = 5 + 200/30 = 11` ⇒ nothing issued; `credits 1200` ⇒ `burn_cap = 45`: research (burn 22, need `min(1000, 176)`) issues, tank (22 + 45 > 45) skipped; opener want (prio 10) is exempt from burn gating; hold logic: `credits 50, burn 60 > income 5` ⇒ prio ≥ 40 unit lines held. Power: Hard `margin_min 20`, `supply 150, demand 120`, want Laboratory (−60) ⇒ Generator inserted (`150 − 120 − 60 = −30 < 20`). Collector target: 2 refineries, Hard k=2.0 ⇒ 4 (capped by field slots 2 × 3). |
| `test_ai_placer` | synthetic 64×64 open map, HQ (20, 20), enemy to the east: Generator lands on the west/back half; two placed Generators ≥ `dispersion` (3) apart; defense sites face the top approach heading; same inputs ⇒ same cell (deterministic tie-break `cy`, `cx`); blacklisted cell never chosen for 1200 ticks. |
| `test_ai_composition` | Hard, midgame weights + air trigger (share 20 %): `AA_MOBILE` weight ×2.0, `FIGHTER` ×1.6, `BOMBER` ×0.7; hysteresis: trigger stays 6000 ticks after the condition clears; roles without defs dropped (USA loses `HEAVY`); T3 role with share ≥ 15 % raises a Laboratory tech-pull want. |
| `test_ai_production` | deficit pick: shares `{TANK 50, AA 25, ART 25}` and value_now `{TANK 3000, AA 0, ART 500}` ⇒ next role `AA_MOBILE`; tie-break lowest role bit; queue depth respected (Easy 1, Hard 3); empty-queue idle tolerance (Easy waits 200 ticks); aircraft cap `pads×3/2` (1 Airfield ⇒ 6). |
| `test_ai_threat` | write 500 power at tick 0; at tick 300 read ≈ 250; at 600 ⇒ 0; sweep commit keeps `max(decayed, frame)`. |
| `test_ai_route_graph` | two-corridor map ⇒ `disjoint_route` returns two routes with no shared node; a threat spike on corridor A shifts `route()` to B; unreachable ⇒ empty; `needs_water` true for an island fixture. |
| `test_ai_cluster` | three Factories 3 cells apart: `best_circle(r=2 cells)` centre on the middle one; Atlas `score_shape` (circle offsets 0/±3, angle 0) = `3 × 2000 = 6000` vs `4000` off-centre; Helios rectangle on a row of 4 structures; Perun core/ring weights (1.0/0.35). |
| `test_ai_powers` (table-driven from `ai_powers.json`) | for **each of the 48 powers** one positive and one negative mock scenario (96 assertions), e.g. Field Repair Drop: 6 tanks (value 1000, missing 40 %, eff 51) ⇒ `1195 ≥ need 1080` ⇒ cast at the centroid; 5 tanks ⇒ `996` ⇒ hold; enemy within 12 cells ⇒ hold; Dust Screen: enemy direct-fire value inside 40 % of own ⇒ hold; Redundant Orders never fires without an Aurora warning; Recovery Priority needs ≥ 3 wrecks. |
| `test_ai_superweapons` | per-weapon targeting on synthetic ghost sets (8 weapons): Atlas as above; Aurora prefers the vehicle blob + powered defenses and holds up to `hold_max` for a combo; Helios picks the longest structure row; Perun +50 % on a charging enemy launcher; Tempest score falls with AA density (`aa_red`); Dragonfall penalized by AT turrets; Horizon `block_bonus` on an enemy MCV; Trident counter-cast when a warning footprint holds ≥ 5000 own structure value. |
| `test_ai_dispersal` | per weapon footprint (5.13.3): units inside get `move` orders after `reaction_delay`; Easy none, Medium `squad.id % 100 < 50`, Hard all; destination outside footprint + margin, ring-spread ≥ 2 cells, reachable within `time_left − 20` for speed 3 cells/s. |
| `test_ai_handlers` | each of the 48 unique units + baseline specials triggers its documented rule on the mock (e.g. Raptor loadout flips AA↔AV with the air share; Protea min dwell 120; Charlemagne never deploys with an enemy ≤ 8 cells; Link Operator moves when coverage < 60 %). |
| `test_ai_data` | `AiDataValidator` over the real `game/data/balance/ai/` for all 32 rosters ⇒ 0 errors; negative fixtures: unknown `AiCond` key, missing role, `train tank_main` without `tier_ge` on a T2-tank roster (V3), duplicate step id, Easy row with `handicap_pct 120` (V10). |
| `test_ai_purity_lint` | greps `game/src/ai/**` (excluding `ai_perf.gd`, `harness/`): forbidden `randi(`, `randf(`, `randomize(`, `shuffle(`, `pick_random(`, `Time.`, `OS.get_ticks`, `sin(`, `cos(`, `sqrt(`, `pow(`, assignments matching `world\.\w+(\.\w+)*\s*(=|\+=|-=)`, `SimRng`, `world.events`, any command-layout knowledge outside `ai_command_builder.gd` (no numeric command type literals elsewhere), any `SimWorld`/`SimEntity`/`SimVision`/`SimCombatSystem` mention outside `ai_world_view.gd` and the pass-through in `ai_thinker.gd`/`ai_controller.gd`, any `import` of `net/` outside `harness/`. |
| `test_ai_thinker` (contract with net.md 5.6) | `AiFactory.make(pid, level, style, seed)` returns a `Callable` accepting `(world, out)`; `out` receives only `PackedInt32Array`s with `1 ≤ size ≤ 1024`, `type ∈ 0..255`, ≤ 64 per call and ≤ 6144 encoded bytes; two consecutive thinks with `dt = 0` (same tick) do nothing harmful; first think bootstraps; `level_names()` / `style_names()` sizes equal `level_count()` / `style_count()`; `level_handicap_pct` = `[100, 100, 100, 120]`; `takeover_level() == 1`; a defeated player is never asked (net) and `release(pid)` frees the thinker. |

### 10.2 Scenario tests (real headless `SimWorld`, scripted opponent or dummy)

| ID | Setup | Expected |
|---|---|---|
| S1 opener timing | Hard AI vs passive dummy, start preset (HQ + 7,500) | Generator placed ≤ tick 560; Radar completed ≤ **3400** ticks (spine = 155 s = 3100 ticks + placement latencies); Medium ≤ 4300; Easy ≤ 5500; Hard construction-idle-with-wants ≤ 40 ticks in the first 3400; run for all 32 rosters (T2-tank rosters must not train a tank before Radar) |
| S2 power upkeep | destroy a Generator at tick 3000 | replacement Generator queued ≤ 60 ticks (prio 0); shortage never lasts > 200 ticks; total shortage < 5 % over 12 000 ticks |
| S3 counter-tech | inject 3 visible enemy fighters at tick T (Hard) | AA want issued ≤ `reaction_delay + 2·think = 32` ticks; ≥ 3 AA units (or 2 + 1 AA battery) within 1800 ticks given credits ≥ 4000; Easy reacts ≥ 60 ticks later |
| S4 retreat/repair | 6 tanks at 30 % hp in combat | `move` to repair point ≤ 30 ticks (Hard); NAPC rosters use the Factory apron (≤ 5 cells of a Factory); return at ≥ 75 % (NAPC) / 85 % |
| S5 attack cadence | 20-unit army vs weak base | first launch within `first_attack_min_s` ± jitter (420 s ± 15…25 %); abort (`RETREATING`) when enemy reinforcements push `R_now` < 0.70; attack-history adaptation lowers `aggression` by 5 after a loss |
| S6 SW dispersal | scripted `SW_WARNING` for each of 8 weapons | Hard: every mobile unit in the footprint has a `move` ≤ `12 + 4` ticks after the warning and ends outside at impact if speed ≥ 2 cells/s; Easy: no reaction; Medium: half the squads; Aurora: infantry hold and counter-attack at `impact + 20`; Dragonfall: AT units target capsules; Tempest: AA takes the ring |
| S7 powers end-to-end | mid-game fight fixture per faction | at least one support power cast per faction within 3 min of an engaged fight; no power cast twice inside `min_gap`; repair-zone powers never overlap within 10 cells |
| S8 SW lifecycle | Hard, income fixture | launcher started ≥ `sw_min_time_s × (150 − sw_priority)/100` (±10 %) after Radar+Lab, only with power margin ≥ 200 + 20; fired within `hold_max` ticks of READY; recharge restarts at activation (no hoarding) |
| S9 water | island map (no land route) | `needs_water` true; roster with amphibious APCs crosses directly; others build Dock + Landing Transports (900) and land ≥ 4 squads at a safe LZ within 12 min; Docks never built on a land-connected map for non-naval rosters |
| S10 salvage (AE) | enemy tank dies next to an AE army | salvager assigned ≤ 40 ticks; payout = 20 % of paid cost after the 8 s action (5 s with Winches); non-AE rosters ignore wrecks; friendly wreck never salvaged |
| S11 safe mode | mock feeds invalid ids | ≥ 5 errors/100 ticks ⇒ `Err.EXCEPTION_BURST`, safe mode 1200 ticks, economy continues, telemetry 30 |
| S12 takeover | `NetAiRunner.add_ai(pid, 1, 0)` on a world with 20 units / 10 structures for that pid (first think = `bootstrap_from_world`) | no duplicate opener steps; units claimed into squads ≤ 40 ticks; economy wants generated from state |
| S13 difficulty ladder (mini-soak) | Hard vs Medium and Medium vs Easy, mirror NAPC vanilla, 10 games each, both sides | Hard wins ≥ 8/10, Medium wins ≥ 8/10 |

### 10.3 AI-vs-AI headless soak harness

**Entry:** `tools/gd run game/tests/ai_soak_main.gd -- --preset=<pr|smoke|nightly|weekly|arena> [--shard=i/n] [--out=user://ai_soak/<run>] [--rosters=a,b] [--maps=open,urban,coast] [--difficulty=hard] [--players=2|4|8] [--cap-min=25] [--repeat-check=K] [--trace=<pid>] [--tune key=value ...] [--budget-minutes=N]`. `AiSoakRunner` builds net's `MatchConfig` dictionary (rules: start 7,500 credits, fog on, unit cap 150, superweapons on; AI slots `{level, style}` with `handicap` = `AiFactory.level_handicap_pct(level)`), creates a `NetSession` in `LOCAL` role with `speed_pct = 0` (unpaced), `max_ticks_per_poll = 256`, `auto_clear_events = true` and `ai_factory = AiFactory.make`, and polls it in a tight loop (no rendering, no sleeping). The AI therefore runs with the **production** think cadence, input delay and command sanitisation; metrics are read from `session.world()` after each poll. It writes one `AiMatchResult` JSON per match plus `summary.jsonl`. The process prints `AISOAK_BEGIN <idx>` / `AISOAK_END <idx>` so stderr `ERROR:` lines are attributed per match by `ai_soak_report.py`. Exit codes: 0 pass, 1 regression, 2 harness error.

**Presets**

| Preset | Content | Cap | Purpose / runtime target |
|---|---|---|---|
| `pr` | 6 fixed 1v1 on 128² maps: NAPC vanilla mirror; NEC vs OLM; DEF vs PD (coast); HAN vs AE; SAP vs NAPC Canada (water); Hard vs Medium | 8 min | PR gate: 0 errors, timing sanity, `repeat-check` on 2 matches; ≤ 3 min on 4 shards |
| `smoke` | 8 vanilla rosters round-robin (28 pairs), open map, Hard | 10 min | quick regression; ≤ 3 min on 8 shards |
| `nightly` | all **32 rosters round-robin: 496 pairs × 3 map families = 1488 matches**, Hard vs Hard, sides alternate by `(i + j + m) % 2`, seed = `fnv1a("soak|i|j|m")`; + difficulty ladders (Hard-Medium, Medium-Easy, Brutal-Hard: 40 games each); + 20 four-player FFAs (Latin-square rosters) + 4 eight-player FFAs | 25 min | balance signal + AI health; ≈ 13 CPU-h ⇒ ≈ 1.6 h on 8 shards at ~30 s/match |
| `weekly` | nightly + swapped sides (2976 pair-matches) + Brutal/Easy ladders + 5 % `repeat-check` + Linux-container canary | 30 min | deep coverage |
| `arena` | equal-spend armies pre-spawned (bible prototype priority "test equal-spend armies"), ordered roster pairs × 3 maps, AI attack/defend only, then with reinforcements and repairs | until dead or 5 min | unit balance under AI control |

**Per-player metrics** (`AiMetrics`, sampled every 20 ticks from the sim public read API + telemetry; observer only): `first_*` ticks (scout, barracks, factory, radar, lab, **tank, mobile AA, siege**, aircraft, naval, **superweapon structure, first superweapon launch**, first power, first attack, first contact); `income_curve` (credits per 60 s window from `INCOME` events); `army_value_curve`; `salvage_income_share` (AE); **idle metrics** (Q8 ratios): `idle_construction` (ticks with the construction queue idle while an eligible want existed, window 60–900 s), `idle_production` (producer ticks with an empty queue while `credits ≥ cheapest producible`), `idle_research`, `idle_army` (≥ 70 % of army IDLE at rally with posture ≥ BALANCED and no op), `placement_wait_ticks` (mean ready→placed), `credit_float_avg` (300–900 s); `power_short_ratio`; strategic-weapon stats from the bible's prototype priorities: `sw_damage_escaped` (value of mobile units inside the footprint at warning vs at impact), `tempest_drone_aa_losses`, `dragonfall_assembly_survival`, `trident_charges_spent`; `cmds{intent}`, `rejected`, `apm_avg`; `stalls{W1..W8}`; `errors{}`; `unit_stuck` (units with a move order and < 1 cell displacement for 600 ticks / units with move orders); `ai_us_avg/p99/max` (`AiPerf`); hashes.
**Match outcome:** `WIN/LOSS` by elimination; at cap, adjudication `score = 0.5·structures_value + 0.3·army_value + 0.2·5·income_last_min`; winner if ratio ≥ 1.25 else `DRAW`; flags `stalemate` (no damage events for 3600 ticks while both alive).
**Report** (`tools/py/ai_soak_report.py`, stdlib only): `report.md` + `metrics.json` with verdict vs `game/tests/ai/baselines/ai_baseline.json`; sections: verdict table; 32×32 win-rate matrix with 95 % Wilson intervals (n = 93 games per roster per nightly ⇒ ±10 pp); per-roster win % (by map family and start slot); timing distributions (median/p10/p90 of every `first_*`); income at 5/10/15 min; idle ratios; stalls/errors; AI CPU; determinism results; top-10 anomalies each with a one-line repro (`--spec <file>`).

### 10.4 Determinism tests
* **D1** `repeat_check` = `NetSelfTest.run_double(config, world_builder, script, 6000, factory.make)` with `--ai --twice`: 5 fixed seeds × 2 AIs × 6000 ticks, run twice ⇒ identical `AiFactory.state_hash()` at 1000/5000/6000, identical recorded command bundles (`cmd_log_hash`) and final `SimWorld.checksum()`, and local run == replay playback (no AI).
* **D2** wall-clock independence: same seeds with an injected busy-wait in `AiPerf` hooks and with different `--fixed-fps` ⇒ identical hashes (proves count-based slicing).
* **D3** seed sensitivity: match seeds 1–8, same roster ⇒ ≥ 6 distinct personality vectors and ≥ 6 distinct first-attack ticks; same seed ⇒ identical.
* **D4** cross-platform canary: macOS arm64 vs Linux container (`tools/gd linux`), 5 seeds × 3000 ticks ⇒ identical command-log hash chain and `SimWorld.checksum` chain (AI int math). Failure is a CI red on nightly (not a netplay blocker; AI is host-only).
* **D5** replay parity: record an AI-vs-AI match through the LOCAL pipeline, verify with `NetReplayPlayer` (no thinker) ⇒ identical checksum chain (net.md 5.10).

### 10.5 Regression thresholds (Hard unless stated; `nightly`; a breach fails the run, `warn` only annotates)

| Metric | Threshold |
|---|---|
| Script/runtime errors (`ERROR:` lines, `Err.EXCEPTION_BURST`) | **0** in all matches |
| Rejected / emitted commands | ≤ 3 % per AI (Easy ≤ 5 %); fail > 6 % |
| AI CPU | per tick: avg ≤ **1.5 ms**, p99 ≤ 4.0 ms; per think: typical ≤ 3 ms at `P ≤ 2`, max ≤ 9 ms (`call_cap_wu`), never > 12 ms (net's throttle) (`ai_us_*`) |
| First Radar (contested 1v1 soak; S1's unopposed limit is 3400 ticks) | Hard ≤ 3:10 (3800 ticks); Medium ≤ 4:00; Easy ≤ 5:30 |
| First tank | T1-tank rosters Hard ≤ 3:45; T2-tank rosters ≤ 5:00 |
| First mobile AA | ≤ 45 s after the first enemy aircraft sighting, and ≤ 7:00 overall |
| First siege unit | Hard ≤ 8:30 |
| Superweapon structure done | Hard ≤ 15:00 in matches ≥ 16 min; Brutal ≤ 12:00; first launch ≤ 120 s after READY |
| First attack launch | Hard 5:30–9:00; Easy never before 10:00 |
| Idle ratios (60–900 s) | construction ≤ 0.10 (fail > 0.20); production ≤ 0.12 (Medium ≤ 0.25); research ≤ 0.15; mean placement wait ≤ 20 ticks; credit float 300–900 s ≤ 2500 |
| Power shortage share | ≤ 5 % of time |
| Watchdog stalls W1–W4 | 0 per match (warn ≤ 0.02 average); stalemate ≤ 3 % of 1v1 matches |
| Income | at 10:00 ≥ 85 % of the scripted reference build's income; no 60 s window with income < 50 % of the previous 5-min mean while Collectors live |
| Difficulty ladder (mirror, 40 games, both sides) | Hard beats Medium ≥ 85 %; Medium beats Easy ≥ 85 %; Brutal beats Hard ≥ 65 %; Hard vs Hard start-slot bias ≤ 55/45 |
| Cross-roster fairness (Hard vs Hard, aggregated) | every roster 30–70 % (**fail**); 35–65 % is the balance-alarm band reported to the balance domain (AI competence confounds it) |
| Superweapon dodge | ≥ 80 % of mobile value escaped per warning (Hard) |
| Stuck units | ≤ 2 % |
| Determinism | D1–D3 100 %; D4/D5 100 % on nightly/weekly |

### 10.6 Debug overlays and logging (for tuning)
* **Log** via `Log` (core), categories `ai.<pid>.{econ,build,prod,ops,pow,sw,kb,watch}`, default WARN; `--ai-log=<cats>`.
* **Trace ring** (256 entries, `AiDebug`): `(tick, module, reason_code, a, b)` int records; `debug_snapshot()["trace"]`; harness `--trace=<pid>` writes JSONL; reason codes in `AiTypes.Why` (e.g. `WHY_WANT_ISSUED, WHY_BURN_GATED, WHY_LAUNCH_GATE_RATIO, WHY_ABORT_RATIO, WHY_POWER_BENEFIT_LOW`).
* **Overlay frame layers** (`AiDebugFrame`, built only at `debug_level ≥ 2`, ≤ every 10 ticks): L1 threat heat; L2 ghosts (by kind, opacity = `conf`); L3 squads/ops (circle + state label); L4 routes/waypoints; L5 placement candidates and dispersion radii; L6 superweapon/power scoring (top-K circles with scores); L7 economy panel (income, burn, reserve, top-8 wants); L8 command feed (last 30 intents). Rendering and hotkeys belong to view/ui (13.18).
* **Dump on stall:** the harness writes `debug_snapshot()` JSON (wants, ops, squads, KB summary, trace) when any watchdog code fires.

### 10.7 Tuning workflow
Nightly report ⇒ outliers ⇒ `--tune personality.aggression=+10` / `--tune strength.launch_ratio_x100=140` sweeps (applied through `AiConfig.tuning_override`, never code edits) ⇒ edit `game/data/balance/ai/*.json` ⇒ `smoke` ⇒ if accepted, regenerate `ai_baseline.json` (reviewed like code).

**Visual test** (view/ui domain): `tools/gd shot` of a scene with an `AiDebugFrame` fixture; expected: colored threat cells, labelled squad circles, SW top-K circles readable, no overdraw of the HUD.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

| ID | Title | Files owned | Depends on | Est. lines | Acceptance tests |
|---|---|---|---|---|---|
| **AI-01** | Foundation | `ai_types, ai_factory, ai_thinker, ai_controller, ai_config, ai_context, ai_world_view, ai_command_builder, ai_rng, ai_budget, ai_scheduler, ai_job, ai_perf, ai_telemetry, ai_debug, ai_debug_frame`, `tests/ai/ai_mock_world_view.gd` | SIM read surface + command encoders (13.1–13.7) or stubs; net XR-13 contract; CORE `Log`, `Fp` | 2200 | `test_ai_rng, test_ai_budget, test_ai_scheduler, test_ai_command_builder, test_ai_thinker, test_ai_purity_lint` |
| **AI-02** | Knowledge base | `ai_knowledge, ai_entity_table, ai_ghost_table, ai_threat_map, ai_enemy_profile, ai_resource_sites, ai_route_graph, ai_avoid_zones, ai_event_ingest, ai_cluster` | AI-01; MAP passability/regions (13.14–13.15); SIM state reads (13.5) | 2400 | `test_ai_threat, test_ai_route_graph, test_ai_cluster`, event-ingest fixtures |
| **AI-03** | Data plumbing and evaluation | `ai_data_store, ai_data_validator, ai_shared_data, ai_role_resolver, ai_unit_profile, ai_tech_graph, ai_cond, ai_personality, ai_difficulty_profile, ai_strength, ai_strength_group` | AI-01; DATA resolved-def API (13.10–13.12) | 2300 | `test_ai_data (with AI-10), test_ai_roles, test_ai_tech_graph, test_ai_cond, test_ai_strength` |
| **AI-04** | Economy and build orders | `ai_economy, ai_build_planner, ai_placer, ai_tech, ai_watchdog` | AI-01–03 | 2500 | `test_ai_economy, test_ai_placer`, S1, S2, S11 |
| **AI-05** | Production, composition, squads | `ai_production, ai_composition, ai_squad, ai_squad_manager` | AI-03, AI-04 | 1800 | `test_ai_composition, test_ai_production`, S3 |
| **AI-06** | Strategy and ground operations | `ai_brain, ai_strategy, ai_defense, ai_attack_planner, ai_scout, ops/ai_op, ops/ai_op_attack, ops/ai_op_defend, ops/ai_op_harass, ops/ai_op_hunt` | AI-02, AI-05 | 2500 | S5, `test_ai_strategy, test_ai_attack_planner` |
| **AI-07** | Micro, repair, special units, engineers | `ai_micro, ai_repair, ai_unit_handlers, ops/ai_op_capture, ops/ai_op_salvage` | AI-05, AI-06 | 2400 | `test_ai_handlers, test_ai_micro`, S4, S10 |
| **AI-08** | Amphibious, naval, air, expansion | `ops/ai_op_landing, ops/ai_op_naval, ops/ai_op_air, ops/ai_op_expand` | AI-06; MAP regions | 2300 | S9, `test_ai_landing, test_ai_air, test_ai_expand` |
| **AI-09** | Powers and superweapons | `ai_powers, ai_power_arch, ai_superweapon, ai_dispersal` | AI-02, AI-03, AI-06; SIM power/SW state (13.2, 13.8) | 2500 | `test_ai_powers, test_ai_superweapons, test_ai_dispersal`, S6, S7, S8 |
| **AI-10** | Difficulty, personalities and doctrine data authoring | `game/data/balance/ai/*.json` (8 faction files with 32 roster overlays, difficulty, roles incl. 48 unique units, composition, powers with 56 entries, tuning) ≈ 2500 JSON lines | AI-03 (schema + validator), DATA final ids, BALANCE numbers | 2500 | `test_ai_data` 0 errors for 32 rosters; S1 passes for all 32 |
| **AI-11** | Harness and tooling | `harness/*`, `game/tests/ai_soak_main.gd`, `tools/py/ai_soak_report.py`, scenario JSON, baselines, overlay builder | AI-01; NET `LOCAL` unpaced session + `NetSelfTest` (13.16); MAP generator (13.14); QA `tools/gd` | 2200 | `pr` preset green; D1–D3; report renders |
| **AI-12** | Integration and tuning | glue owned by app/net/ui (13.16–13.18) + AI tuning passes, baselines | all; NET/APP/UI | ~600 + tuning | LAN game 1 human + 3 AI 30 min; 8-AI 60-min match zero errors within CPU budget; `nightly` green; ladder thresholds met |

**Parallelism.** AI-01, AI-03 and AI-10 (schema first) start immediately against the mock world; AI-02 follows AI-01; AI-04/05 after AI-03; AI-06/07/08/09 run in parallel after AI-05/AI-02 land; AI-11 can begin once AI-01 exists (it needs a completed sim to run matches). The critical path is AI-01 → AI-03 → AI-04 → AI-05 → AI-06 → AI-12.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / open question | Recommended resolution |
|---|---|---|
| R1 | The sim_core read/command API is still unpublished (combat.md and net.md fix only part of it) | `AiWorldView`/`AiCommandBuilder`/`AiEventIngest` isolate the mismatch to three files; reconcilers freeze "Sim Read API v1" from 13.1–13.9; until then `AiMockWorldView` unblocks AI-01…AI-09 |
| R2 | Balance numbers (dps, hp, costs) arrive late or change | The AI consumes only *resolved* defs; profiles are rebuilt at match start; if weapons are missing a unit falls back to `power = isqrt(cost × 16)` so the AI still plays; validator flags `Err.DATA_MISSING`; thresholds live in `ai_tuning.json` |
| R3 | Economy details unknown (deposit size, finite vs regenerating, harvest rate) | The AI measures income and Collector wait states at runtime and reads `deposit_left` (current stock; regeneration shows up as stock growth, `economy.deposit_regen_mcpt`); `collector_slots_per_field` is tuning. AI supports finite and regenerating fields |
| R4 | Map connectivity data (regions per move class, water, shoreline) is required for amphibious/landing logic | Request 13.14–13.15; fallback: rate-limited `path_exists` probes (≤ 1/tick) to derive `needs_water`; without either, the AI plays land-only and never builds Docks (still legal: every roster is playable land-only) |
| R5 | 8 AIs on one host plus the sim may exceed the tick budget | Global governor 2400 wu/tick, rolling cursors, per-tick caps; measure `ai_us_avg` from the first integration (wu→µs factor); if ≥ 5 µs/wu, cut quotas 30 % (config only) |
| R6 | Brutal's fog cheat may feel unfair or hide behind "AI difficulty" | Only Brutal; label in lobby; recommend a separate lobby toggle `ai_fog_cheat` (default on for Brutal) so players can keep only the income bonus |
| R7 | Humans can exploit predictable AI (turtle, cheese, base walls) | Personality jitter, alternate styles, attack-history adaptation, `overflow` forced waves, `HUNT`; add scripted human-proxy opponents (rush, turtle, air, mass-infantry) as harness preset `proxy` (post-v1); accept residual exploitability |
| R8 | AI-vs-AI results ≠ human-facing quality | Treat soak as regression/health tool; require periodic human playtests; proxy bots (R7); AI competence confounds roster win rates — report them as *alarms* to balance, not verdicts |
| R9 | Decoys (False Convoy/Front/Feint) can fool the AI; bible says detectors reveal them | AI treats `EF_DECOY` as zero threat once flagged; before that it reacts like a human would. Sim must set the flag per viewer on detection |
| R10 | Data authoring load: 32 rosters × openers/compositions/research/powers | Base + overlay design keeps hand-written volume to ≈ 8 base scripts + 24 short overlays; `AiDataValidator` catches unresolved references; recipes in 5.14.2 give the exact intent per roster |
| R11 | Sim may not support an `angle` parameter for line/multi-circle superweapons or corridor powers | Set `angles = 1` in `ai_powers.json`; API keeps `angle` (ignored); targeting loses orientation optimization only |
| R12 | Execution lag (6 ticks) blunts kiting/dodging | Micro predicts positions: `pos + v × AI_EXEC_LAG` with `v` from the last two table samples; kite only when `own_speed × lag < 0.3 × own_range`; dispersal uses `time_left − 20` margin |
| R13 | Entity-id reuse would break squad/op bookkeeping | Request monotonic ids (13.1); AI treats `alive(eid) == false` as removal and re-verifies `def` before use |
| R14 | Easy budget (220 wu) starves modules | Quotas sum to 290 wu; starvation guard reserves quota after 3 skips; W6 doubles optional periods; `test_ai_scheduler` covers Easy |
| R15 | AI-vs-AI stalemates (two FORTRESS/TURTLE AIs) | Stall breakers W4/W5, `overflow`, `HUNT`; harness `stalemate` metric ≤ 3 %; adjudication by score; minimum adjudication age 20 min |
| R16 | Fair-mode leak: terrain/deposits/start slots are public | Deliberate (T2): matches the lobby map preview; documented so the reconciler can veto (then `AiRouteGraph` treats unexplored blocks as cost ×1.5) |
| R17 | Net's default think period (5 turns = 0.5 s) is coarser than Hard/Brutal micro and dodge cadences | Per-level periods `[5, 3, 2, 1]` requested (13.16); the AI degrades gracefully (kite/dodge only when `dt` allows, catch-up scheduling, `call_cap_wu` bounds the tail) |
| R18 | No event feed: diff-based detection cannot see causes (damage type, killer, attacker identity) | Causes are estimated from the visible enemy mix; the few causal statistics the harness needs come from raw sim events read by the observer, never by the AI (6.2) |
| Q1 | Brutal's bonus also raises starting credits (net's `handicap_pct` semantics) | Accepted and labelled ("+20 % credits and income"); if a pure income bonus is preferred, net/sim must split the handicap into two fields — no AI change |
| Q2 | Should the AI ever resign? | Optional `RESIGN` command (sim): Easy/Medium after 2400 ticks in `DESPERATE` with no production; default off |
| Q3 | Team play | AIs never attack allies and answer ally-damage events (Medium+); shared plans/targets are v2 |
| Q4 | Neutral-structure capture benefits | Map/sim to expose `capture_bonus` value in credits-equivalent per neutral def; AI ignores neutrals with value < 300 |
| Q5 | Minimum superweapon reaction window | Kept at bible values (6–10 s warnings); Easy's 3 s reaction delay is intentional |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

Items marked **(published)** already exist in another domain's spec at the time of writing and are listed so reconciliation is explicit; the rest are new asks.

**SIM (`sim/`, incl. sim_core, vision, power, economy)**
1. **Read surface behind `AiWorldView`.** *(published)* `SimWorld.get_entity(id) -> SimEntity` (null when removed; ids never reused), `SimEntity` fields `id, def_idx, kind, owner, x, y, prev_x, prev_y, vx, vy, facing, layer, hp, hp_max, radius, container_id, paid_cost, expire_tick, flags, combat, air, carrier`, `SimWorld.rel(a, b)`, `SpatialHash.query_circle(x, y, r, out)`, `SimVision.can_see/is_known/decoy_identified`, `SimCombatSystem.ticks_since_combat/dp100/range_max_eff/ammo_of/is_suppressed`, `SimAirSortie.pads_free/sortie_state`, `SimCarrierOps.drones_docked` (combat.md 3.7/3.8). **New:** `SimWorld.own_ids(pid) -> PackedInt32Array` (ascending, cached per tick, borrowed); `visible_enemy_ids(viewer, out)` (enemy units *and* structures, ascending, cached per tick); `enemies_in_circle(viewer, x, y, r, out, ignore_fog: bool = false)` (camouflage/detection always honored); `SimVision.cell_visible(world, pid, cx, cy)` and `cell_explored(...)`; `SimPlayer` fields `credits, power_supply, power_demand, unit_count, roster, team, alive, handicap` and a monotonic stat `credits_earned_total` (harvest + salvage); entity flag bits for camouflaged / deployed / EMP-shut / unpowered / under construction / garrisoned / loaded / decoy-identified-for-viewer / suppressed.
2. **Rule validators** through the same code path as `CommandSystem`, returning reason codes: `check_build(pid, def)`, `check_place(pid, def, cx, cy)`, `check_train(pid, producer_eid, def)`, `check_research(pid, def)`, `power_status(pid, power_idx)` (`READY/COOLDOWN/LOCKED_PREREQ/UNPOWERED/NO_CREDITS`), `power_ready_tick`, `power_target_ok(pid, power_idx, x, y)` (implements `DefPower.target_vision` against **real** vision), `sw_status/sw_ready_tick/sw_launcher_eid`.
3. **Command encoders** for the intents of 6.1 as static functions returning `PackedInt32Array [type, args...]` (the same arrays `UiCommandBus` submits — `SimCmd.*`), with variable-length `ids` lists, a `queue` flag on move/attack-move/attack, and an `angle` (+ optional second point) on `USE_POWER` / `LAUNCH_SUPERWEAPON`. *(published)* combat block 40..47 (`CMD_ATTACK, ATTACK_MOVE, GUARD, HOLD, FORCE_FIRE, SET_STANCE, SCUTTLE, RETURN_TO_BASE`). Optional: `SimWorld.rejected_command_count(pid)` (deterministic counter) so the harness can measure the rejected/emitted ratio.
4. **No rejection channel is needed**: commands carry no tag (net.md 5.5) and illegal ones are skipped deterministically, so the AI verifies effects by state (5.15). Please keep validators (2) in lock-step with `CommandSystem` so `can_*` never says yes to something the executor refuses.
5. **State reads that replace an event feed** (the thinker receives only `world`): `strategic_warnings(out)` — active superweapon warnings visible to every player: `[owner, sw_idx, x, y, angle, start_tick, impact_tick]*`; `e_last_fire` of *visible enemy* artillery (public: a human sees them fire); `construction_state`, `queue_of`, `queue_progress_pct`, `research_active/done`; wrecks as `KIND_WRECK` entities (`paid_cost`, `expire_tick`, former owner). Optionally a persistent event ring `events_since(cursor, out)`; the AI treats it as an optimisation only.
6. **Deterministic, pure and cheap reads:** no side effects, no per-call allocation on the hot accessors, no cache that mutates checksummed state.
7. **Deposits and neutrals as entities** *(published in data_balance.md 4: `DefNeutral`, `neutral_kind` ∈ garrison / substation / observation post / salvage depot / deposit, `reward{credits, power_n, reveal_radius, income}`, `capturable`, `capture_t`, `garrison_squads`)*: sim exposes the neutral entities and `deposit_left` (current stock; regeneration via `economy.deposit_regen_mcpt`).
8. **Power/superweapon state** (step 4 of the tick pipeline): per-player `power_status`, cooldown-ready ticks, superweapon `CHARGING/READY/WARNING`, launcher eid; strategic warnings (5).
9. **Player handicap** *(published net.md 5.3.6 / XR-9)*: economy-only, stored in player state and checksummed — Brutal's bonus rides on it; no new field is requested.

**DATA (`data/`)**
10. **Fields the AI reads** *(published data_balance.md 3–4)*: `DefRoster.units / structures / producible_units / producible_structures / research_list / power_list / superweapon_def / units_produced_by / prereqs_met / selector_units`; `DefUnit` (`cost, build_ticks, health, armor_class, move_class, layer_mask, speed, speed_water, sight, tier, pop, tags, ability_mask, detect_radius, cloak_delay_t, max_range, min_range, attack_layer_mask, transport_squads, weapons[DefWeaponSlot]`); `DefStructure` (`cost, build_ticks, power, health, fp_w/fp_h, build_radius, detect_radius, requires, requires_mask, superweapon`); `DefPower` (`cost, cooldown_t, tier, target_mode, target_vision, radius, length, width, warning_t, actions`); `DefSuperweapon` (`packets[offset_x, offset_y, radius, damage, delay_t], radius, duration_t, recharge_t, warning_t, action_kind`); `DefResearch`, `DefNeutral`; `DefQuery.unit_dps_x100/dps_x100/counters_of/tech_path/cheapest_*`; `GameData.dmg_matrix_bp`. **New asks:** a weapon-slot or unit flag `stationary_fire` (Javelin/Spike/Kavach "must stop to fire"); stable ability indices per unit for `USE_ABILITY` (cover, shelter, puck, decoy, smoke launcher); `DefPower.is_recon` (or `target_vision == ANY` documented as recon); an optional `pres_ai_role` hint per unit *(published as a hint)*.
11. **Enumerations shared with the AI:** `MoveClass`, `UnitClass`, layer bits, armor-class order, damage types (`docs/balance/TAXONOMY.md`); the AI's local `AiTypes.MoveClass` is only an alias.
12. **No separate AI roster tables are requested** — roles are computed from `DefTags`/`DefQuery.units_with` (5.5.1).
13. `tools/gd check` invokes `AiDataValidator` (V1–V12) on `game/data/balance/ai/` and fails on errors.

**MAP (`map/`)**
14. `MapData`: `w, h`, `passable(cx, cy, move_class)`, `region(cx, cy, move_class)` (connected components), `is_water`, `family()` (`OPEN/URBAN/COAST`), start positions in the map's start-index order (adjacent indices adjacent on the map, XR-12), deposit/neutral placements; deterministic per seed; generator entrypoint `MapGen.create(family, size, seed)` for the harness.
15. Guarantees the AI relies on (bible/architecture): ≥ 2 exits per start area, baseline economy on land, symmetric slots (2/4/6/8) so start-slot bias can be measured; a test fixture with an island start to exercise `needs_water`.

**NET / APP**
16. **Net (`NetAiRunner`, `NetProtocol`, `NetSessionOptions`).** *(published)* `ai_factory(pid, level, style, seed) -> Callable(world, out)`, `seed = mix32(match_seed ^ ((pid+1) × 0x9E3779B9))`, `AI_MAX_CMDS_PER_THINK = 64`, sanitisation, `TAKEOVER_AI_LEVEL = 1`, unpaced `LOCAL` sessions with `max_ticks_per_poll`, `NetSelfTest.run_double(..., ai_factory)`. **New asks:** (a) **per-level think periods** `AI_THINK_PERIOD_TURNS_BY_LEVEL = [5, 3, 2, 1]` (Easy…Brutal) instead of the single constant 5; (b) keep net's throttle ("> 12 ms twice ⇒ double the period") unchanged — the AI bounds every think to `call_cap_wu` ≈ 9 ms, so it never trips it; (c) `ai_level_count = 4`, `ai_style_count = 4`, names from `AiFactory.level_names()/style_names()`; (d) the lobby uses `AiFactory.level_handicap_pct(level)` as the default `handicap_pct` of an AI slot and shows `ai.cheats.brutal` (text key) for Brutal; (e) a per-poll hook (`on_turn_begin` already exists) usable by the soak harness to sample metrics without touching the sim.
17. **App.** `AppMatch.make_ai_thinker` (XR-14) builds one `AiFactory(AiDataStore.load_dir())` per match and passes `factory.make` as `ai_factory`; the text keys `ai.level.*`, `ai.style.*`, `ai.cheats.brutal` are added to `data/text`.

**VIEW / UI**
18. Render `AiDebugFrame` (circles, lines, labels, heat, panel) behind a debug key; optional AI status panel (phase/posture/income/top wants); lobby AI-slot widgets for level/style with the cheat label.

**QA / tooling**
19. `tools/gd run` forwards `--` arguments and returns the script's exit code; `tools/gd linux` available for the D4 canary; AI purity lint (10.1) wired into `tools/gd check`; CI jobs for `pr` (per PR), `smoke` (per merge), `nightly`/`weekly`; storage for `ai_baseline.json`; test runner timeout override for long AI tests.

**CORE**
20. `Log` category/level API (`Log.warn(cat, msg)`), `Fp.dist/isqrt/sin/cos/atan2`, `Fp.CELL`, `SimConfig.TPS`. (`AiRng` carries its own FNV-1a and `mix32`, so the AI has no dependency on `NetProtocol`.)

**BALANCE**
21. Final unit/structure/power numbers (`docs/balance`), including deploy times, min ranges and ability parameters (cover, shelter, puck, decoy, smoke launcher), so `AiUnitProfile` and `AiUnitHandlers` read them instead of hard-coding.
