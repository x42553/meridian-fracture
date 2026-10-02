# MERIDIAN FRACTURE — Economy, Production, Construction, Research, Support Powers & Superweapons (Domain Spec v0.1)

> **Status:** domain spec for `docs/spec/economy.md`. Binding parent: `docs/ARCHITECTURE.md` (wins on conflict). Bible: `Input/meridian_agent_reference/meridian_factions.json` (never edited). Written concurrently with other domain specs; every assumption about another domain is tagged `ASSUMPTION(domain)` and every request is numbered in section 13.
> **Conventions used below:** `TPS = 20` (1 s = 20 ticks). `bp` = basis points (10000 = 1.0). "cells" are converted to sub-cell ints with `Fp.CELL = 1024` at load. `s_idx / u_idx / r_idx / p_idx / w_idx` are dense def indices for structures / units / research / support powers / superweapons (separate index spaces; `ASSUMPTION(data)`). All money, hp, power, progress are `int`. Integer division truncates toward zero (DR-5); every formula below is non-negative so `/` is floor.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

### 1.1 Owned by this domain

| Area | What is specified here |
|---|---|
| **Credits ledger** | `SimPlayerEcon.credits`, spend / refund / income API with reasons, per-player statistics, income-rate window for AI/HUD. |
| **Progressive payment** | Exact integer accounting of credits paid while structures, units and research progress; pause at 0 credits; 100 % refund of paid credits on cancel. |
| **Construction** | Single player-wide construction queue, completion states (building / ready-to-place / on-hold / paused), placement validation (build radius, footprints, terrain, aprons, shoreline for Dock, strategic max-one), build-up state, MCV deploy / HQ undeploy, sell, structure repair. |
| **Unit production** | One independent queue per Barracks / Factory / Airfield / Dock plus the Refinery Collector queue; queue length, rally points, exit search, primary building, unit cap, tech gating, prerequisite pause, 60 % cost/time floors *as consumed* (floors are computed by GameData; this domain consumes the resolved ints). |
| **Research** | One player-wide research queue, 45 s / 75 s durations, progressive payment, persistence after building loss, the *economy-side* research effects (knobs, section 5.8). |
| **Power grid** | Supply / demand, shortage state, 50 % rate rule, powered-defense/Relay/pad/power-activation/recharge gating flags, SAP defense reserve (20 s / 35 s, 60 s recharge), Saudi/OLM generator output (consumed from resolved defs), EMP `shutdown` reading. |
| **Harvesting** | Collector state machine (`HARVEST`, `RETURN_CARGO`), auto-harvest, refinery dock arbitration, flee behaviour, deposit table (sizes, depletion, regeneration), free Collector with each Refinery, PD amphibious-Collector data hook. |
| **Engineers & neutrals** | `CAPTURE`, `REPAIR`, `SALVAGE` order state machines; paid-repair primitive shared by every repairing unit and by structure wrench-repair; capture progress / contest rules; the neutral structure catalog (6 types) and their effects; African salvage. |
| **Support powers** | Unified framework for all 48 powers: slot model, targeting kinds, validation, payment, cooldowns, effect scheduler, effect-kind taxonomy (10 kinds) with an implementation recipe per kind, and the classification of all 48. |
| **Superweapons** | Charge / warning / execution state machine for all 8, launcher-loss / EMP cancel rules, warning-zone records visible to affected players, the exact execution timelines, impact-packet choke point (`emit_packet`) and interception hooks (Trident), AI-readable state. |
| **Economy-side data** | `economy.json`, `structure_rules.json`, `powers.json`, `superweapons.json`, `neutral_structures.json`, `repair_profiles.json`, `summons.json` (schemas + worked examples in section 7). |

### 1.2 Explicitly NOT owned (interfaces only)

| Not owned | Owner (`ASSUMPTION`) | What this domain needs from it |
|---|---|---|
| Entity core (`SimEntity`, spawn/remove, ids, spatial hash, owner change) | sim-core | hooks `on_entity_added/removed/died/owner_changed`, `spawn_unit`, `spawn_structure`, `remove_entity` (section 13). |
| Order framework (`OrderSystem`, `SimOrder`, order queues, move goals) | orders | handler registration; this domain supplies the *state machines* of 6 order types. |
| Pathfinding, steering, movement, collision, unit exit-cell search | movement | `request_move`, `find_free_cell_near`, `eject_units_from_rect`, scripted-mover skip flag. |
| Damage application, targeting, weapons, projectiles, armor, resistances, EMP status | combat | `apply_area_damage(...)`, packet flag semantics, resistance cap, `is_direct_fire`, `fire_log`. Strategic damage *originates* here but is *applied* by combat. |
| Timed stat effects, buffs, auras, camouflage, suppression, command fields, Relay field logic, heal auras, transports/garrison containers | abilities | `apply_timed_effect`, `effect def` compiler, `end_on` flags, structure `aura` primitive; this domain only *triggers* them and owns the knob values they read. |
| Zones (smoke, debris, repair fields, decoys, interception) | zones | `create/query/destroy` API; Trident zone owns charges. |
| Vision / detection / fog | vision | `add_reveal(...)`, `is_explored`, `is_visible`. |
| Def classes, modifier resolution, roster availability, def indices | data | resolved per-roster tables (`cost`, `build_ticks`, `power`, `rearm`, `repair_cost_bp`, `repair_rate_bp`, thermal modifier). |
| Unit/structure/weapon stat numbers (hp, damage, speed, unit costs, unit build times) | balance | this domain lists which bible nulls it *needs* (section 7.9) and supplies defaults for its own files. |
| Map generation (deposit seeds, neutral structure spawn seeds, terrain flags) | map | `MapData.deposits`, `MapData.neutral_spawns`, `is_buildable`, `water_body_size`. |
| Victory evaluation, wreck creation/expiry, deferred removal | cleanup (sim-core) | this domain supplies `SimEconomySystem.spawn_wreck(...)` and the rule that salvage freezes wreck expiry. |
| Sidebar, ghost rendering, cursors, sounds, VFX | ui / view / audio | this domain supplies query API + events. |
| AI decisions | ai | this domain supplies AI-friendly queries and reasons (`RSN_*`). |

### 1.3 Bible rules honored (index into section 5)

`rule.design.economy` (5.1, 5.9) · `rule.design.technology` (5.5) · `rule.design.production` (5.4) · `rule.design.research` (5.6) · `rule.design.power_loss` (5.7) · `rule.design.caps_and_interpretation` (5.2) · `rule.combat.support_power_access` (5.16) · `rule.combat.targeting_and_warnings` (5.16, 5.19) · `rule.combat.superweapon_control` (5.19) · `rule.combat.interception_and_strategic_packets` (5.20) · `rule.combat.transports_aircraft_and_repairs` (5.11, 5.13) · `rule.combat.submarines_and_wrecks` (5.12) · `mechanical_conventions.tier_requirements / starting_preset / floors` (5.2, 5.5).

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All paths under `game/`. One class per file, ≤ ~1500 lines each, `extends RefCounted` unless noted. No `Node` (DR-8). Systems expose `func update(world: SimWorld) -> void` and are constructed by `SimWorld`.

| Path | `class_name` | Responsibility |
|---|---|---|
| `src/sim/sim_econ_const.gd` | `SimEconConst` | Constants only: enums for states, reasons `RSN_*`, knobs `K_*`, command codes `CMD_*`, event codes `EVT_*`, order codes `ORD_*`, flags `EF_*`. No logic. |
| `src/sim/sim_player_econ.gd` | `SimPlayerEcon` | Per-player record (one per `pid`): credits, power state, reserve timers, queues (construction, research), rate table, knobs, power slots, counters, per-def structure counts, income window. |
| `src/sim/sim_comp_econ.gd` | `SimCompEcon` | Per-entity component: paid cost, structure lifecycle (`st`), repair accumulators, capture progress, HQ memory, collector cargo/FSM, engineer work state. |
| `src/sim/sim_comp_prod.gd` | `SimCompProd` | Per-producer component: unit queue arrays, head progress/paid/state, rally, primary flag, airfield pad table, rearm boost. |
| `src/sim/sim_comp_wreck.gd` | `SimCompWreck` | Wreck data: paid-cost basis, owner, killer, salvageable flag, expiry, current salvager. |
| `src/sim/sim_comp_temp.gd` | `SimCompTemp` | Temporary/summoned entity data: expiry, script kind, payload, source power/superweapon, brain. |
| `src/sim/sim_power_slot.gd` | `SimPowerSlot` | One of 4 per-player strategic slots (3 support powers + superweapon): cooldown / charge state. |
| `src/sim/sim_warning.gd` | `SimWarning` | Queryable warning-zone record (geometry, timing, `affected_mask`) for superweapons and warned powers. |
| `src/sim/sim_scheduled.gd` | `SimScheduled` | One entry of the strategic effect scheduler, ordered by `(tick, seq)`. |
| `src/sim/sim_placement_result.gd` | `SimPlacementResult` | Caller-owned, reusable ghost/validation result (reason, per-cell flags). |
| `src/sim/sim_production_system.gd` | `SimProductionSystem` | **Stage 2.** Construction queue, unit queues, research queue, prerequisite pause, rate table, rally & exit, structure completion, build-up → active transition, free-Collector spawn. Owns command handlers for the queue commands. |
| `src/sim/sim_placement.gd` | `SimPlacement` | Placement validation + ghost data (`validate` fills `SimPlacementResult`; `find_site` for the AI), build-radius test, footprint/apron/berth rules, MCV deploy-site test. Stateless (static-style methods taking `world`). |
| `src/sim/sim_structure_life.gd` | `SimStructureLife` | Structure lifecycle helper: activate, sell, undeploy HQ, wrench-repair loop, registration in power/prereq counters. Called by production/economy systems and hooks. |
| `src/sim/sim_economy_system.gd` | `SimEconomySystem` | **Stage 3 and public facade.** Credits ledger, income events and statistics, unit-cap counters, SimWorld hooks, sell/undeploy completion, neutral-structure effects, deposit regeneration tick, power balance. Owns command handlers for sell/repair/undeploy. Its dock / repair / capture / salvage API methods are one-line delegations to the two helpers below. |
| `src/sim/sim_economy_docks.gd` | `SimEconomyDocks` | Refinery dock protocol (FIFO queue, unload step, watchdog) and Collector-side helpers (`choose_field`, `choose_refinery`, danger marks). |
| `src/sim/sim_economy_work.gd` | `SimEconomyWork` | Paid-repair primitive, capture channel/evaluation, wreck creation and salvage claims. |
| `src/sim/sim_deposit_table.gd` | `SimDepositTable` | Deposits as parallel `PackedInt32Array`s: position, radius, stock, cap, regen timers, harvester counts; queries for nearest/best field. |
| `src/sim/sim_power_system.gd` | `SimPowerSystem` | **Stage 4.** Power balance → shortage state machine, SAP reserve, per-player derived flags (`defenses_online`, `powers_online`, `charge_online`), then calls `world.strategic.update(world)`. |
| `src/sim/sim_strategic_system.gd` | `SimStrategicSystem` | Support-power slots, superweapon slots, `CMD_USE_POWER` validation/payment, effect scheduler, warning records, packet choke point, AI-readable state. |
| `src/sim/sim_strategic_effects.gd` | `SimStrategicEffects` | Implementation recipes for the 10 support-power effect kinds (section 5.17). |
| `src/sim/sim_superweapons.gd` | `SimSuperweapons` | Timelines/executors for the 8 superweapons (section 5.21). |
| `src/sim/sim_impact_packet.gd` | `SimImpactPacket` | Reusable packet record (position, radius, damage, type, flags, source). |
| `src/sim/sim_summon_brain.gd` | `SimSummonBrain` | Autonomy driver (stride 20) for summoned units that have no player control: Dragonfall engines, Tempest drones, decoy lifetimes. |
| `src/sim/sim_order_harvest.gd` | `SimOrderHarvest` | Handler for `ORD_HARVEST` and `ORD_RETURN_CARGO` (Collector FSM, flee, dock protocol). |
| `src/sim/sim_order_capture.gd` | `SimOrderCapture` | Handler for `ORD_CAPTURE`. |
| `src/sim/sim_order_repair.gd` | `SimOrderRepair` | Handler for `ORD_REPAIR`. |
| `src/sim/sim_order_salvage.gd` | `SimOrderSalvage` | Handler for `ORD_SALVAGE`. |
| `src/sim/sim_order_deploy_mcv.gd` | `SimOrderDeployMcv` | Handler for `ORD_DEPLOY_MCV`. |
| `src/data/def_structure_rules.gd` | `DefStructureRules` | Typed loader for `structure_rules.json` (footprints, aprons, exits, berth, power class, pads, queue rules). *Specified here; hosted in the data module.* |
| `src/data/def_econ_rules.gd` | `DefEconRules` | Typed loader for `economy.json` (collector, deposits, sell, repair, salvage, capture, power constants, knob table). |
| `src/data/def_power_recipe.gd` | `DefPowerRecipe` | Typed loader for `powers.json` (48 recipes) and temp-effect defs. |
| `src/data/def_superweapon_rules.gd` | `DefSuperweaponRules` | Typed loader for `superweapons.json` (8 timelines, packet defs). |
| `src/data/def_neutral.gd` | `DefNeutral` | Typed loader for `neutral_structures.json`. |
| `src/data/def_repair_profile.gd` | `DefRepairProfile` | Typed loader for `repair_profiles.json`. |
| `src/data/def_summon.gd` | `DefSummon` | Typed loader for `summons.json` (temporary entity defs). |
| `data/balance/economy.json`, `structure_rules.json`, `powers.json`, `superweapons.json`, `neutral_structures.json`, `repair_profiles.json`, `summons.json` | — | Data files, schemas in section 7. |
| `tools/py/check_econ_data.py` | — | Validator: bible id references, tier/prerequisite consistency, tick conversions, all 48 powers present, all 8 superweapons present. |
| `tests/test_econ_*.gd`, `tests/test_prod_*.gd`, `tests/test_power_*.gd`, `tests/test_strategic_*.gd`, `tests/test_capture_salvage.gd` | — | Test files (section 10). |

**Conditional classes.** `SimStrategicEffects`, `SimSummonBrain`, the executor half of `SimSuperweapons`, `SimCompTemp`, the `repair_step` / capture / salvage half of `SimEconomyWork` and the knob table of 4.5 overlap with `SimPowerFx`, `SimSummons`, `SimChannel` and `SimPlayerFx` of the abilities spec (matrix 12.1, rows M3, M6, M11, M12). Their **behaviour** is normative here; whether the code lives in this domain or in the abilities domain is the reconciler's call, and the work breakdown (section 11) shrinks accordingly.

**Registration:** `SimWorld` owns `production`, `economy`, `power`, `strategic`, `placement`, `life` and the per-player array `world.econ_players: Array[SimPlayerEcon]` (indexed by `pid`, size = player count; neutral has no record). Stage order is the ARCHITECTURE order: `production.update` (2) → `economy.update` (3) → `power.update` (4, ends by calling `strategic.update`). `SimOrder*` handlers run inside stage 5 through the orders domain's registry.

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

Notation: `world: SimWorld`; `ent: SimEntity`; `pid: int` player index 0–7; `RSN_*` are validation reasons (0 = OK, section 4.1). Every mutating function is called **only from inside the tick pipeline** (commands, systems, order handlers, hooks). Read-only queries (`q_*`, `can_*`) never mutate and are safe for UI/AI at any time. `ASSUMPTION(sim-core)`: `SimEntity` exposes `id, kind, def_idx, owner, x, y, hp, max_hp, flags, layer, comp_econ, comp_prod, comp_wreck, comp_temp` and `SimWorld` exposes `tick, rng, data: GameData, map: MapData, events, get_entity(eid) -> SimEntity` (null when dead; the name used by the abilities and combat specs), `team_of(pid)`, `rel(a, b)`, plus the systems named in section 2.

### 3.1 Tick order, call order, memory ownership

```
Stage 1 CommandSystem   -> world.production.handle_command(world, cmd)   codes 120..131
                        -> world.economy.handle_command(world, cmd)      codes 132..139
                        -> world.strategic.handle_command(world, cmd)    codes 140..149
Stage 2 production.update   (uses power state & rate table computed on the PREVIOUS tick: 1-tick latency, deterministic)
Stage 3 economy.update      (structure sell/undeploy completion, wrench repair, capture evaluation, neutral effects,
                             deposit regen, power BALANCE recompute if dirty, income window)
Stage 4 power.update        (shortage state machine, SAP reserve, derived flags, rate-table dirty flag)
        -> strategic.update (scheduled effects, superweapon charge, warnings, summons, cooldown-ready events)
Stage 5 OrderSystem         -> SimOrderHarvest / Capture / Repair / Salvage / DeployMcv handlers call economy API synchronously
Stage 11 CleanupSystem      -> world.economy.spawn_wreck(...) ; honours SimCompWreck.salvage_by (expiry frozen while > 0)
```

| Memory | Owner | Lifetime / rule |
|---|---|---|
| `SimPlayerEcon` (one per pid) | `SimEconomySystem` (array `world.econ_players`) | created in `init_player`, lives for the match; all fields in the checksum (section 8). |
| `SimCompEcon`, `SimCompProd`, `SimCompWreck`, `SimCompTemp` | the entity that carries them | created by `SimWorld.spawn_*` when the def has the matching `has_econ / producer / wreck / temp` flag; freed with the entity. |
| `SimDepositTable` | `SimEconomySystem.deposits` | built once from `MapData.deposits` in `setup`; never resized. |
| Scheduled effects, warnings, power slots | `SimStrategicSystem` | `Array[SimScheduled]` sorted by `(tick, seq)`; `Array[SimWarning]`; `SimPowerSlot` ×4 per player. |
| `SimImpactPacket` | `SimStrategicSystem._pk_pool` | one pooled instance per call site; **never retained** by combat after `apply_area_damage` returns. |
| Scratch `PackedInt32Array`s | each system (`_scratch_*`) | reused every tick; no allocation in per-tick loops. |

### 3.2 `SimEconomySystem` (stage 3)

```gdscript
class_name SimEconomySystem extends RefCounted
var deposits: SimDepositTable
func setup(world: SimWorld, rules: DefEconRules) -> void                      # builds deposits from MapData
func init_player(world: SimWorld, pid: int, roster_idx: int, start_credits: int, handicap_pct: int = 100) -> void   # start credits scaled by handicap (net §5.3.6)
func update(world: SimWorld) -> void
func handle_command(world: SimWorld, cmd: SimCommand) -> int                  # SELL, REPAIR_TOGGLE, UNDEPLOY_HQ -> RSN_*

# --- ledger: the ONLY functions that change SimPlayerEcon.credits --------------------------------
func credits(pid: int) -> int
func can_afford(pid: int, amount: int) -> bool
func spend(world: SimWorld, pid: int, amount: int, reason: int) -> bool       # all-or-nothing; false if credits < amount
func earn(world: SimWorld, pid: int, amount: int, reason: int, ex: int = 0, ey: int = 0) -> void  # emits EVT_CREDITS_GAINED when ex/ey given

# --- unit cap -------------------------------------------------------------------------------------
func unit_cap_room(pid: int) -> int                                           # cap - live - reserved (may be <= 0)

# --- SimWorld hooks (called synchronously by sim-core; section 3.9) --------------------------------
func on_entity_added(world: SimWorld, ent: SimEntity) -> void
func on_entity_died(world: SimWorld, ent: SimEntity, killer_pid: int, cause: int) -> void   # cause: DEATH_* (combat)
func on_entity_removed(world: SimWorld, ent: SimEntity) -> void
func on_owner_changed(world: SimWorld, ent: SimEntity, old_pid: int, new_pid: int) -> void

# --- refinery dock protocol (called by SimOrderHarvest; deterministic FIFO) -------------------------
func dock_request(world: SimWorld, refinery_id: int, collector_id: int) -> int   # DOCK_WAIT | DOCK_GRANTED | DOCK_DENIED
func dock_unload_step(world: SimWorld, refinery_id: int, collector_id: int) -> int  # credits moved this tick (0 while timer runs)
func dock_release(world: SimWorld, refinery_id: int, collector_id: int) -> void
func dock_queue_len(refinery_id: int) -> int

# --- paid repair primitive (Engineer-class units, wrench, airfield pads) --------------------------
func repair_step(world: SimWorld, repairer: SimEntity, target: SimEntity, rc: int, src_bit: int) -> int  # hp restored this tick; 0 = paused
func repair_can_target(world: SimWorld, repairer: SimEntity, target: SimEntity, rc: int) -> int          # RSN_*
func repair_basis_cost(world: SimWorld, target: SimEntity) -> int             # paid_cost, or def.repair_basis if paid_cost == 0

# --- capture -----------------------------------------------------------------------------------------
func capture_can_target(world: SimWorld, engineer: SimEntity, target: SimEntity) -> int   # RSN_*
func capture_channel(world: SimWorld, engineer: SimEntity, target: SimEntity) -> void     # called every tick the engineer channels

# --- salvage (African Empire hooks) -------------------------------------------------------------------
func spawn_wreck(world: SimWorld, dead: SimEntity, killer_pid: int, cause_flags: int) -> int   # returns wreck entity id or 0
func salvage_can_target(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> int    # RSN_*
func salvage_duration_ticks(world: SimWorld, pid: int) -> int                              # min(base, research, power window)
func salvage_begin(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> bool         # claims wreck.salvage_by
func salvage_tick(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> int           # SALV_RUNNING | SALV_DONE | SALV_FAILED; pays on DONE
func salvage_cancel(world: SimWorld, salvager: SimEntity, wreck: SimEntity) -> void

# --- read-only queries (UI / AI) -----------------------------------------------------------------------
func q_income_per_minute(pid: int) -> int                                      # moving 60 s window (harvest+salvage+depot, not refunds)
func q_refineries(pid: int, out: PackedInt32Array) -> void                     # entity ids ascending
func q_collectors(pid: int, out: PackedInt32Array) -> void
func q_deposit_nearest(world: SimWorld, pid: int, x: int, y: int, min_stock: int) -> int   # deposit idx or -1; explored-only for pid
func q_wrecks_near(world: SimWorld, pid: int, x: int, y: int, r: int, out: PackedInt32Array) -> void   # salvageable-by-pid wrecks
func q_capturable_near(world: SimWorld, pid: int, x: int, y: int, r: int, out: PackedInt32Array) -> void
func q_stats(pid: int) -> SimPlayerEcon                                        # read-only view; callers must not mutate
func q_can_rebuild(pid: int) -> bool                                            # real_structure_count > 0 or mcv_count > 0 (ARCH §12 elimination test, for CleanupSystem)
```

### 3.3 `SimProductionSystem` (stage 2)

```gdscript
class_name SimProductionSystem extends RefCounted
func setup(world: SimWorld, rules: DefEconRules, srules: DefStructureRules) -> void
func update(world: SimWorld) -> void
func handle_command(world: SimWorld, cmd: SimCommand) -> int                  # QUEUE_*/CANCEL_*/HOLD_*/PLACE/SET_RALLY/SET_PRIMARY/RESEARCH

# --- validation (read-only; identical checks are re-run when the command executes) ------------------
func can_queue_structure(world: SimWorld, pid: int, s_idx: int) -> int        # RSN_*
func can_queue_unit(world: SimWorld, pid: int, producer_id: int, u_idx: int) -> int
func can_queue_research(world: SimWorld, pid: int, r_idx: int) -> int
func prereqs_met(world: SimWorld, pid: int, req: PackedInt32Array) -> bool    # req = s_idx list; uses SimPlayerEcon.struct_count
func has_active_hq(world: SimWorld, pid: int) -> bool

# --- catalog queries for the sidebar / AI --------------------------------------------------------------
func q_buildable_structures(world: SimWorld, pid: int, out: PackedInt32Array, include_locked: bool) -> void
func q_buildable_units(world: SimWorld, pid: int, producer_id: int, out: PackedInt32Array, include_locked: bool) -> void
func q_researchable(world: SimWorld, pid: int, out: PackedInt32Array, include_locked: bool) -> void
func q_find_producer(world: SimWorld, pid: int, prod_kind: int, u_idx: int) -> int   # primary first, else fewest queued items, ties lowest id; 0 = none
func q_item_progress_bp(world: SimWorld, pid: int, producer_id: int) -> int     # 0..10000 for head item (producer_id 0 = construction)
func q_rate_bp(pid: int, prod_kind: int) -> int                                 # effective progress rate (5000 under shortage)
func q_unit_cost(world: SimWorld, pid: int, u_idx: int) -> int                 # resolved price for tooltips / sidebar (post-modifier)
func q_unit_ticks(world: SimWorld, pid: int, u_idx: int) -> int                # resolved build ticks
func q_structure_cost(world: SimWorld, pid: int, s_idx: int) -> int
func q_structure_ticks(world: SimWorld, pid: int, s_idx: int) -> int

# --- internal-but-shared (used by SimStructureLife / strategic) ---------------------------------------
func refresh_rates(world: SimWorld, pid: int) -> void                           # recomputes SimPlayerEcon.rate_bp[] from power state + knobs
func spawn_from_producer(world: SimWorld, producer: SimEntity, u_idx: int, paid: int) -> int   # entity id or 0 if exit blocked
func on_structure_activated(world: SimWorld, ent: SimEntity) -> void            # free Collector for Refinery, airfield pads init
```

### 3.4 `SimPlacement` and `SimStructureLife`

```gdscript
class_name SimPlacement extends RefCounted
# Fills `out` (caller-owned, reused; no allocation) and returns out.reason (RSN_*, 0 = valid).
static func validate(world: SimWorld, pid: int, s_idx: int, cx: int, cy: int, rot: int, out: SimPlacementResult) -> int
static func validate_hq_site(world: SimWorld, pid: int, mcv: SimEntity, out: SimPlacementResult) -> int   # 3x3 centred on MCV cell; no radius test
static func footprint_center_x(world: SimWorld, s_idx: int, cx: int, rot: int) -> int   # sub-cell centre x = cx*1024 + w*512 (w after rotation); ints only (DR-1)
static func footprint_center_y(world: SimWorld, s_idx: int, cy: int, rot: int) -> int   # sub-cell centre y = cy*1024 + h*512
static func dist2_point_to_rect(px: int, py: int, rx0: int, ry0: int, rx1: int, ry1: int) -> int             # squared sub-cell distance, exact ints
static func find_site(world: SimWorld, pid: int, s_idx: int, near_x: int, near_y: int, max_ring: int, out_cell: Vector2i) -> bool   # AI helper; spiral order, first valid, <= 400 probes

class_name SimStructureLife extends RefCounted
func activate(world: SimWorld, ent: SimEntity) -> void            # BUILDUP -> ACTIVE: registers counters, power, pads, free Collector
func deactivate(world: SimWorld, ent: SimEntity, cause: int) -> void  # unregisters counters/power (sell start, death, capture loss)
func begin_sell(world: SimWorld, ent: SimEntity) -> int            # RSN_*
func begin_undeploy(world: SimWorld, ent: SimEntity) -> int        # HQ -> MCV
func deploy_mcv(world: SimWorld, mcv: SimEntity) -> int            # replaces MCV with HQ in BUILDUP; returns new HQ id or 0
func structure_online(world: SimWorld, ent: SimEntity) -> bool     # ACTIVE && not shutdown && (power rule of its power_class)
```

### 3.5 `SimPowerSystem` (stage 4) — grid, shortage, reserve

```gdscript
class_name SimPowerSystem extends RefCounted
func update(world: SimWorld) -> void                # shortage FSM + SAP reserve + derived flags, then world.strategic.update(world)
func supply(pid: int) -> int
func demand(pid: int) -> int
func is_shortage(pid: int) -> bool                  # demand > supply   (strict)
func powered(pid: int) -> bool                      # not shortage
func defenses_online(pid: int) -> bool              # powered OR SAP reserve_left > 0
func production_rate_bp(pid: int) -> int            # 10000 normal, 5000 shortage
func radar_online(world: SimWorld, pid: int) -> bool    # >=1 ACTIVE Radar, not shutdown, powered(pid)
func lab_online(world: SimWorld, pid: int) -> bool
func reserve_left_ticks(pid: int) -> int
func mark_dirty(pid: int) -> void                   # a structure changed state; economy recomputes balance next stage 3
```

### 3.6 `SimStrategicSystem` (stage 4b) — support powers + superweapons

```gdscript
class_name SimStrategicSystem extends RefCounted
func setup(world: SimWorld, prules: DefPowerRecipe, srules: DefSuperweaponRules) -> void
func init_player(world: SimWorld, pid: int, roster_idx: int) -> void            # builds the 4 SimPowerSlot (3 powers + superweapon)
func update(world: SimWorld) -> void
func handle_command(world: SimWorld, cmd: SimCommand) -> int                    # CMD_USE_POWER, CMD_LAUNCH_SUPERWEAPON (codes 140..141)

# --- validation & AI/UI state ---------------------------------------------------------------------------
func can_activate(world: SimWorld, pid: int, slot: int, tx: int, ty: int, angle: int, target_id: int) -> int   # RSN_*
func slot_info(pid: int, slot: int) -> SimPowerSlot                             # read-only; slot 0..2 powers, 3 superweapon
func cooldown_left_ticks(world: SimWorld, pid: int, slot: int) -> int           # support powers: ready_tick - tick; superweapon: recharge_ticks - charge
func warnings_affecting(pid: int, out: Array[SimWarning]) -> void              # incl. own; UI/AI filter (affected_mask bit pid)
func attacks_pending_against(pid: int, out: Array[SimWarning]) -> void         # subset: hostile warnings whose zone contains any entity of pid

# --- packet choke point: ALL strategic damage goes through here -------------------------------------------
func emit_packet(world: SimWorld, pk: SimImpactPacket) -> void                  # interception check -> world.combat.apply_area_damage(...)

# --- player-wide windows (Mobilization Order, Central Priority, Joint Landing, ...) ------------------------
func window_active(world: SimWorld, pid: int, window_id: int) -> bool
func knob(world: SimWorld, pid: int, k: int) -> int                              # effective knob value (base x temp), section 4.5

# --- hooks -------------------------------------------------------------------------------------------------
func on_structure_lost(world: SimWorld, ent: SimEntity, cause: int) -> void      # launcher died/sold/captured -> cancel WARNING attacks, clear slot
func on_unit_spawned(world: SimWorld, ent: SimEntity) -> void                    # re-apply active player-wide windows to new matching units
func on_shutdown_started(world: SimWorld, ent: SimEntity) -> void               # EMP hit a launcher -> cancel WARNING attacks
```

`emit_packet` contract: the caller fills a pooled `SimImpactPacket`; `emit_packet` (1) if `pk.flags & (PKT_INTERCEPTABLE | PKT_SHELL)` and not `(PKT_BEAM | PKT_EMP)`, asks `world.zones.intercept_packet(pk)` which may set `pk.pre_resist_bp += 5000` (strategic packet) or zero the damage (ordinary shell) and consume Trident charges (5.20); (2) calls `world.combat.apply_area_damage(pk)` (combat reads the packet fields immediately and must not retain the object); (3) emits `EVT_SW_IMPACT` for view (position, radius, type), except for per-hit Tempest/Dragonfall summon shots.

### 3.7 Order handlers (registered into the orders domain; state lives in `SimCompEcon`, never in the order)

`ASSUMPTION(orders)`: a handler class implements

```gdscript
func on_begin(world: SimWorld, ent: SimEntity, order: SimOrder) -> void
func on_update(world: SimWorld, ent: SimEntity, order: SimOrder) -> int      # SimOrder.RUNNING | DONE | FAILED
func on_end(world: SimWorld, ent: SimEntity, order: SimOrder, reason: int) -> void   # END_DONE | END_CANCELLED | END_REPLACED | END_DIED
```

and reaches movement through `world.movement.request_move(ent, x, y, flags) -> bool`, `world.movement.stop(ent)`, `world.movement.path_failed(ent) -> bool`, `world.movement.at_goal(ent) -> bool`. If the orders domain's names differ, only the thin adapter changes; the FSMs in section 5 are normative.

| Order | Class | Target | Owner-visible completion |
|---|---|---|---|
| `ORD_HARVEST` | `SimOrderHarvest` | deposit idx (`order.target_id = -1` = auto) | never DONE while auto; DONE when manual deposit is depleted and auto takes over |
| `ORD_RETURN_CARGO` | `SimOrderHarvest` | refinery id (0 = nearest) | DONE after unload, then auto-harvest resumes |
| `ORD_CAPTURE` | `SimOrderCapture` | structure id | DONE on ownership change; FAILED on invalid/garrisoned/friendly |
| `ORD_REPAIR` | `SimOrderRepair` | vehicle or structure id | DONE at full hp; FAILED if target lost |
| `ORD_SALVAGE` | `SimOrderSalvage` | wreck id | DONE on payout; FAILED if wreck expires/claimed |
| `ORD_DEPLOY_MCV` | `SimOrderDeployMcv` | optional cell (`order.x/y`) | DONE when HQ entity created |

### 3.8 Data access assumed from `GameData` (`ASSUMPTION(data)`; requests in section 13)

```gdscript
world.data.roster_of(pid) -> int                                  # roster idx (fixed at match start)
world.data.unit(u_idx) -> DefUnit ; world.data.structure(s_idx) -> DefStructure       # base defs
world.data.res(pid) -> ResolvedRoster                             # per-player resolved tables (research layer applied), all PackedInt32Array:
  .unit_cost[u_idx]  .unit_ticks[u_idx]  .unit_available[u_idx](0/1)  .unit_cap_cost[u_idx]
  .struct_cost[s_idx] .struct_ticks[s_idx] .struct_available[s_idx](0/1) .struct_power[s_idx]   # signed: +supply / -demand
  .unit_rearm_ticks[u_idx] .repair_cost_bp[def_key] .repair_rate_bp[def_key]  .thermal_damage_bp   # def_key = kind-tagged def index
  .research_available[r_idx](0/1)   .power_of_slot[slot] (p_idx)   .super_idx (w_idx)
world.data.research(r_idx) -> DefResearch                         # tier, cost, ticks, req list, econ knob assignments (from economy.json)
world.data.power(p_idx) -> DefPowerRecipe.Row ; world.data.super(w_idx) -> DefSuperweaponRules.Row
```

### 3.9 Hooks required from `SimWorld` (sim-core), all synchronous and in this order for a new/dead entity

1. `spawn_entity(def_idx, pid, x, y)` (or `spawn_unit` / `spawn_raw`, whatever sim-core names its spawn path) → **first** sim-core bookkeeping, then `economy.on_entity_added`, then `strategic.on_unit_spawned` (units only).
2. The kill path (`SimCombatSystem.kill(e, cause)` / `kill_entity(ent, killer_pid, cause)`, stage 8) → sets the dead flag, then `economy.on_entity_died` (unregisters structure counters/power, cancels capture/sell/repair/salvage claims, decrements unit count, releases dock slots), `strategic.on_structure_lost` (structures only), then queues the deferred removal for stage 11 (which calls `spawn_wreck` **before** freeing the entity).
3. `remove_entity(eid, cause)` → `economy.on_entity_removed` (idempotent; used for silent removal of summons, sold structures, deployed MCVs).
4. `change_owner(eid, new_pid)` → `economy.on_owner_changed` (moves counters and power between players; resets queues of a captured producer; see 5.13).

### 3.10 Who calls what (dependency direction)

`SimProductionSystem → SimEconomySystem.spend/earn/unit_cap_room`, `SimPlacement`, `SimStructureLife`, `GameData`. `SimEconomySystem → SimStructureLife`, `SimPowerSystem.mark_dirty`. `SimPowerSystem → SimStrategicSystem.update`. `SimStrategicSystem → SimEconomySystem.spend`, `SimProductionSystem.refresh_rates`, combat/zones/abilities/vision APIs listed in section 13. `SimOrder*` → `SimEconomySystem` only. **No** economy-domain class reaches into another domain's private members (ARCH §5).


### 3.11 Aliases and read helpers expected by the concurrently published specs

Cheap wrappers so that the abilities, combat, data and AI specs compile against this domain unchanged. All are pure delegations; the reconciler may rename either side.

```gdscript
# --- SimEconomySystem (abilities #12, combat 3.8) ---
func try_spend(pid: int, credits: int) -> bool                      # = spend(world, pid, credits, CR_OTHER); world reference is held by the system
func add(pid: int, credits: int) -> void                            # = earn(world, pid, credits, CR_OTHER)
func income_total(pid: int) -> int                                  # monotonic: stat_harvested + stat_salvaged + stat_depot (AI income deltas)
func power_supply(pid: int) -> int                                  # = world.power.supply(pid)
func power_demand(pid: int) -> int
# --- SimPowerSystem (abilities #10, combat 3.8: "SimPower.is_powered / defense_online") ---
func is_powered(eid: int) -> bool                                   # structure-level: ACTIVE and (power_class rule); = SimStructureLife.structure_online
func defense_online(pid: int) -> bool                               # = defenses_online(pid) (honours the SAP reserve)
# --- SimProductionSystem / SimStrategicSystem read helpers (AI knowledge layer) ---
func construction_state(pid: int, out: PackedInt32Array) -> void    # out = [state 0 idle/1 building/2 ready/3 paused, s_idx, progress_pct, ready_s_idx]
func queue_of(producer_id: int, out: PackedInt32Array) -> int       # queued u_idx in order; returns length
func queue_progress_pct(producer_id: int) -> int
func research_active(pid: int) -> int                               # r_idx or -1
func research_done(pid: int, r_idx: int) -> bool                    # SimPlayerEcon.researched
func power_ready_tick(pid: int, p_idx: int) -> int                  # slot.ready_tick
func power_target_ok(pid: int, p_idx: int, x: int, y: int) -> bool  # target/vision/terrain part of can_activate only
func sw_status(pid: int) -> int                                     # 0 none, 1 charging, 2 ready, 3 warning pending (own attack)
func sw_ready_tick(pid: int) -> int                                 # tick + (recharge_ticks - charge) while charge_ok, else -1
func sw_launcher_eid(pid: int) -> int
func strategic_warnings(pid: int, out: PackedInt32Array) -> int     # [owner, w_idx_or_p_idx, x, y, angle, start_tick, exec_tick] * n for warnings whose affected_mask has bit pid
```

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enums (all in `SimEconConst`; integer values are normative and enter the checksum indirectly)

| Group | Values |
|---|---|
| **`RSN_*`** validation reasons | `OK=0, NOT_OWNER=1, NOT_AVAILABLE=2, PREREQ=3, QUEUE_FULL=4, NO_CREDITS=5, UNIT_CAP=6, STRATEGIC_LIMIT=7, NOT_READY=8, BAD_TARGET=9, OUT_OF_RADIUS=10, TERRAIN=11, STRUCTURE_BLOCK=12, UNIT_BLOCK=13, NEEDS_SHORE=14, DEPOSIT=15, DEBRIS=16, APRON=17, NO_POWER=18, COOLDOWN=19, NO_VISION=20, NOT_EXPLORED=21, WRONG_KIND=22, BUSY=23, NO_HQ=24, GARRISONED=25, FRIENDLY=26, LOCKED=27, FEATURE_OFF=28, NO_LAUNCHER=29, NOT_CHARGED=30, EXPIRING=31, DECOY=32, INVALID_INDEX=33, HOLD=34` |
| **`ST_*`** structure state (`SimCompEcon.st`) | `BUILDUP=0` (placed, inert, 30 ticks), `ACTIVE=1`, `SELLING=2`, `UNDEPLOYING=3` |
| **`PC_*`** power class (per structure def, `structure_rules.json`) | `NONE=0` (HQ, Generator, neutrals), `ECON=1` (Refinery), `PRODUCER=2` (Barracks, Factory, Dock, Airfield), `SENSOR=3` (Radar, Laboratory), `DEFENSE=4` (all defenses incl. advanced), `RELAY=5`, `STRATEGIC=6` (superweapon launchers) |
| **`PROD_*`** producer / rate index | `NONE=0, BARRACKS=1, FACTORY=2, AIRFIELD=3, DOCK=4, REFINERY=5, CONSTRUCTION=6, RESEARCH=7` (`SimPlayerEcon.rate_bp` has 8 entries) |
| **`QS_*`** head-of-queue state | `EMPTY=0, ACTIVE=1, HOLD=2, PAUSED_PREREQ=3, PAUSED_FUNDS=4, PAUSED_CAP=5, PAUSED_EXIT=6, PAUSED_SHUTDOWN=7, READY=8` (READY only for the construction queue) |
| **`CR_*`** ledger reasons | `START=0, CONSTRUCTION=1, PRODUCTION=2, RESEARCH=3, POWER_USE=4, REPAIR=5, HARVEST=6, SALVAGE=7, SELL=8, REFUND=9, DEPOT=10, OTHER=11` |
| **`DOCK_*`** | `DENIED=0, WAIT=1, GRANTED=2` |
| **`SALV_*`** | `FAILED=0, RUNNING=1, DONE=2` |
| **`H_*`** Collector FSM | `IDLE=0, SEEK=1, TO_FIELD=2, HARVEST=3, TO_REFINERY=4, WAIT_DOCK=5, DOCK_IN=6, UNLOAD=7, DOCK_OUT=8, FLEE=9, BLOCKED=10` |
| **`W_*`** engineer work kind | `NONE=0, CAPTURE=1, REPAIR=2, SALVAGE=3` |
| **`RC_*`** repairer category | `ENGINEER=0` (Engineer, Reclaimer, River Warden), `TECHNICIAN=1` (Reef Technician), `TENDER=2` (Lotus Drone Tender), `PIONEER=3` (Combat/Alpine Pioneer, defenses only), `FIELD_ENGINEER=4` (Mekong Field Engineer, structures only), `WRENCH=5` (structure self-repair), `PAD=6` (Airfield pad) |
| **`RS_*`** repair source bits | `UNIT=1, WRENCH=2, PAD=4` |
| **`EF_*`** entity econ flags (`SimCompEcon.flags`) | `TEMPORARY=1, DECOY=2, NO_REPAIR=4, NO_CAPTURE=8, NO_SALVAGE=16, FREE=32, CAPPED=64, SUMMON=128, NO_VISION_GRANT=256, SELL_LOCKED=512` |
| **`PF_*`** player flags | `CAN_SALVAGE=1, SAP_RESERVE=2, AMPHIBIOUS_COLLECTORS=4, ELIMINATED=8, SUPERWEAPONS_OFF=16` |
| **`PW_*`** power state | `NORMAL=0, SHORTAGE=1` |
| **`SLOT_*`** | `P0=0, P1=1, P2=2, SW=3` (P0..P2 in the roster's `support_power_ids` order) |
| **`SW_*`** superweapon slot state | `NONE=0` (no ACTIVE launcher), `CHARGING=1`, `READY=2` |
| **`AT_*`** attack phase | `WARNING=0, EXEC=1, DONE=2, CANCELLED=3` |
| **`WK_*`** warning kind | `SUPER=0, POWER=1, SCAN=2` |
| **`TK_*`** target kind | `NONE=0, POINT=1, AREA=2, LINE=3, OWN_STRUCTURE=4, OWN_UNIT=5` (POINT and AREA are identical for the sim; AREA tells the UI to draw a radius) |
| **`VR_*`** vision requirement | `NONE=0` (reconnaissance), `EXPLORED=1` (superweapons, "scouted"), `CURRENT=2` |
| **`EK_*`** support-power effect kind | `REVEAL_ZONE=1, RECON_SUMMON=2, BUFF=3, WINDOW=4, STRUCT_BUFF=5, REPAIR=6, SMOKE=7, DECOY=8, BOMBARD=9, MARK=10` |
| **`SK_*`** scheduled-effect kind | `PACKET=1, SPAWN_ZONE=2, END_ZONE=3, APPLY_FX=4, SPAWN_SUMMON=5, ASSEMBLE=6, EXPIRE_ENTITY=7, WINDOW_END=8, WARNING_END=9, BEAM_PULSE=10, REVEAL_START=11, REVEAL_END=12, DROP_PAYLOAD=13, MARK_STRIKE=14` |
| **`PKT_*`** packet flags | `INTERCEPTABLE=1` (superweapon impact packet: Trident 8-charge / -50 % rule), `BEAM=2` (bypasses Trident), `EMP=4` (bypasses Trident), `ENEMY_ONLY=8`, `STRATEGIC=16`, `IGNORE_SMOKE=32`, `SHELL=64` (ordinary artillery shell / missile: a hostile Trident zone destroys it for 1 charge) |
| **`TS_*`** temp-entity script (`SimCompTemp.script`) | `NONE=0, HOVER=1, FLY_TO_HOVER=2, FLY_TO_DROP=3, ORBIT=4, CAPSULE=5, ENGINE=6, DECOY=7, STATION=8` |
| **`BR_*`** summon brain | `NONE=0, ASSAULT_STRUCTURES=1, SWARM_ZONE=2` |
| **`WF_*`** wreck flags | `SALVAGEABLE=1, PAID_BASIS_LOCKED=2` |
| **`ORD_*`** (proposed codes; orders domain owns the master enum) | `HARVEST=30, RETURN_CARGO=31, CAPTURE=32, REPAIR=33, SALVAGE=34, DEPLOY_MCV=35` |
| **`CMD_*`** / **`EVT_*`** | section 6 |

### 4.2 Player record

```gdscript
class_name SimPlayerEcon extends RefCounted
var pid: int; var roster_idx: int; var flags: int                       # PF_*
# ledger ----------------------------------------------------------------------------------------------
var credits: int
var stat_harvested: int; var stat_salvaged: int; var stat_depot: int
var stat_spent_construction: int; var stat_spent_units: int; var stat_spent_research: int
var stat_spent_powers: int;       var stat_spent_repair: int
var stat_refunded: int;           var stat_sold: int
var income_bp: int                       # handicap * 100 (10000 = none); scales HARVEST / SALVAGE / DEPOT credits only (net §5.3.6, XR-9)
var income_acc: int                      # remainder accumulator for the income scaling, unit 1/10000 credit
var income_ring: PackedInt32Array       # 12 buckets x 100 ticks; earn() with reason HARVEST/SALVAGE/DEPOT adds to bucket
var income_ring_idx: int                 # bucket currently filled; rotates when tick // 100 changes
# unit cap ----------------------------------------------------------------------------------------------
var unit_cap: int                        # MatchRules.unit_cap (default 150)
var unit_count: int                      # live entities with EF_CAPPED
var cap_reserved: int                    # sum of unit_cap_cost of unit-queue heads currently progressing
# counters (ACTIVE, non-EF_TEMPORARY structures only; index = s_idx) --------------------------------------------
var struct_count: PackedInt32Array
var active_hq_count: int
var real_structure_count: int            # structures in ST_BUILDUP/ACTIVE/SELLING/UNDEPLOYING that are not EF_TEMPORARY (victory: "owns any structure")
var mcv_count: int                       # live MCV units ("HQ-capable unit")
var strategic_owned: int                 # BUILDUP + ACTIVE strategic launchers (queued / READY ones are counted by scanning cq_def); max 1 in total
# power ------------------------------------------------------------------------------------------------------
var power_supply: int; var power_demand: int; var power_state: int      # PW_*
var power_dirty: bool
var shortage_since: int                  # tick the current shortage began, -1 if none
var reserve_left: int; var reserve_max: int; var adequate_streak: int   # SAP defense reserve (ticks)
var defenses_online: bool; var powers_online: bool                      # derived in stage 4 every tick (powers_online = !shortage)
# player-wide queues (head at index 0) ------------------------------------------------------------------------
var cq_def: PackedInt32Array; var cq_cost: PackedInt32Array; var cq_ticks: PackedInt32Array   # construction: s_idx, locked cost, locked ticks
var cq_progress: int; var cq_paid: int; var cq_state: int; var cq_hold: bool                   # head only; progress in bp-ticks (complete at cq_ticks[0] * 10000)
var rq_def: PackedInt32Array; var rq_cost: PackedInt32Array; var rq_ticks: PackedInt32Array   # research: r_idx
var rq_progress: int; var rq_paid: int; var rq_state: int; var rq_hold: bool
var researched: PackedByteArray          # index r_idx, 0/1
# rates & knobs ------------------------------------------------------------------------------------------------
var rate_bp: PackedInt32Array            # size 8 (PROD_*); 10000 = 1.0; recomputed when rates_dirty
var rates_dirty: bool
var knob_base: PackedInt32Array; var knob_temp: PackedInt32Array; var knob_until: PackedInt32Array   # size K_COUNT
# strategic ---------------------------------------------------------------------------------------------------
var slots: Array[SimPowerSlot]           # 4 entries (SLOT_P0..SLOT_SW)
# cached id lists (ascending entity id; maintained by on_entity_added/died) ---------------------------------------
var refinery_ids: PackedInt32Array
var producer_ids: Array[PackedInt32Array]   # index PROD_*; only ACTIVE producers
var producer_flat: PackedInt32Array      # all ACTIVE producer ids ascending (iteration order for payment)
var field_danger: PackedInt32Array   # per deposit idx: tick until which this player's collectors avoid the field (flee marks it)
var rr_offset: int                       # round-robin start for payment fairness
func checksum_into(ck: Checksum) -> void
```

### 4.3 Entity components

```gdscript
class_name SimCompEcon extends RefCounted
var flags: int = 0                       # EF_*
var paid_cost: int = 0                   # credits actually paid (post-modifier). Basis for salvage, sell, repair.
# --- structure lifecycle (structures only) ---
var st: int = ST_ACTIVE
var st_until: int = 0                    # tick when BUILDUP / SELLING / UNDEPLOYING ends
var power_class: int = PC_NONE           # cached from DefStructureRules
var power_delta: int = 0                 # resolved delta registered with the owner while ACTIVE (+supply / -demand); 0 if unregistered
var registered: bool = false             # true while counted in struct_count / power / producer lists
var mcv_paid_cost: int = 0               # HQ only: paid cost of the MCV it came from (restored on undeploy)
var shutdown_until: int = 0              # EMP shutdown end tick. ASSUMPTION(abilities): owned & written by AbilitySystem; read here
var repair_on: bool = false              # wrench mode
var repair_acc_hp: int = 0               # hp*bp accumulator, unit: hp*bp per (10000*TPS)
var repair_acc_cost: int = 0             # credit*bp*hp accumulator, unit: per (10000*max_hp)
var repair_src_mask: int = 0             # RS_* sources active THIS tick (cleared in stage 3)
var unit_repairer_id: int = 0            # entity id holding the single unit-repair slot on this target (0 = free)
var unit_repairer_tick: int = 0          # last tick the holder refreshed the claim (stale after 10 ticks)
# --- capture (capturable structures) ---
var cap_pid: int = -1                    # player whose progress is stored
var cap_progress: int = 0                # ticks 0..cap_need
var cap_last_tick: int = 0               # last tick with >=1 channeler
var cap_chan: PackedInt32Array           # size 8: channelers per pid THIS tick (cleared after evaluation)
var depot_next_tick: int = 0             # neutral Salvage Depot income timer
# --- collector unit ---
var cargo: int = 0
var h_state: int = H_IDLE
var h_mode: int = 0                      # 0 = auto, 1 = manual field
var h_field: int = -1                    # deposit idx currently assigned (harvester count held on this deposit), -1 none
var h_last_field: int = -1
var h_refinery: int = 0                  # entity id of chosen / docked refinery
var h_timer: int = 0                     # generic countdown / interval accumulator (ticks)
var h_bad_until: int = 0                 # do not retry a failed field/path before this tick
var h_bad_field: int = -1
var h_flee_until: int = 0
var h_last_hp: int = 0
var h_scan_tick: int = 0
var h_unload_total: int = 0              # credits unloaded in the current dock session (for EVT_CREDITS_GAINED)
# --- refinery dock (Refinery structures only) ---
var dock_occupant: int = 0               # collector entity id currently docked (0 none)
var dock_queue: PackedInt32Array         # waiting collector ids, FIFO
var dock_timer: int = 0                  # unload interval accumulator
var dock_since: int = 0                  # tick the occupant was granted (watchdog)
# --- engineer-class units ---
var w_kind: int = W_NONE
var w_target: int = 0                    # entity id
var w_progress: int = 0                  # capture channeling ticks are stored on the STRUCTURE; here: salvage ticks
func checksum_into(ck: Checksum) -> void
```

```gdscript
class_name SimCompProd extends RefCounted
var kind: int                            # PROD_* of this structure
var q_def: PackedInt32Array              # u_idx, head at [0]; length <= queue_len (5)
var q_cost: PackedInt32Array             # locked at enqueue
var q_ticks: PackedInt32Array            # locked at enqueue (resolved build ticks)
var head_progress: int = 0               # bp-ticks: += rate_bp each tick; complete at q_ticks[0] * 10000
var head_paid: int = 0
var head_state: int = QS_EMPTY
var head_cap_reserved: bool = false
var hold: bool = false                   # player hold (applies to whole queue)
var exit_retry_tick: int = 0
var is_primary: bool = false
var rally_on: bool = false; var rally_x: int = 0; var rally_y: int = 0; var rally_target: int = 0   # target = entity id, or -(deposit idx + 1) = harvest that deposit
var pad_ent: PackedInt32Array            # Airfield only: occupant aircraft id per pad (0 = free); size = pads_base + K_PAD_EXTRA
var rearm_boost_until: int = 0; var rearm_boost_bp: int = 10000   # Rapid Turnaround (per airfield)
func checksum_into(ck: Checksum) -> void
```

```gdscript
class_name SimCompWreck extends RefCounted
var paid_cost: int; var owner_pid: int; var killer_pid: int; var src_u_idx: int
var flags: int                           # WF_*
var expire_tick: int                     # spawn tick + 1200 (60 s); FROZEN while salvage_by != 0
var salvage_by: int = 0                  # entity id of claiming salvager
var salvage_end_tick: int = 0            # tick the current claim completes (used by the "would expire first" check)
func checksum_into(ck: Checksum) -> void

class_name SimCompTemp extends RefCounted
var expire_tick: int                     # hard lifetime; SimStrategicSystem removes silently (no wreck, no salvage, no credits)
var script: int                          # TS_*
var src_kind: int                        # 0 = support power, 1 = superweapon
var src_idx: int; var src_pid: int; var attack_id: int
var brain: int                           # BR_*
var zx: int; var zy: int; var zr: int    # leash zone (Tempest) / home zone
var state: int; var state_until: int     # script-private (capsule: assemble end tick)
var bound_zone: int                      # zone id destroyed when this entity dies (repair drone station), 0 none
func checksum_into(ck: Checksum) -> void
```

### 4.4 Strategic records

```gdscript
class_name SimPowerSlot extends RefCounted
var kind: int                            # 0 = support power, 1 = superweapon
var def_idx: int = -1                    # p_idx / w_idx (-1: roster has none, e.g. superweapons off)
var ready_tick: int = 0                  # support power: absolute tick when cooldown ends; 0 = ready since unlock
var uses: int = 0
var launcher_id: int = 0                 # superweapon: entity id of the ACTIVE launcher (0 none)
var sw_state: int = SW_NONE
var charge: int = 0                      # ticks accumulated toward recharge_ticks
var recharge_ticks: int = 0
var last_activation_tick: int = -1
var pending_attack: int = 0              # SimWarning id, 0 none
var announced: bool = false              # EVT_POWER_UNLOCKED already sent
func checksum_into(ck: Checksum) -> void

class_name SimWarning extends RefCounted
var id: int; var kind: int               # WK_*
var src_idx: int; var owner: int; var launcher_id: int
var x: int; var y: int; var x2: int; var y2: int     # centre / line ends in sub-cells
var radius: int; var width: int; var angle: int      # sub-cells; angle = 4096-per-turn binary angle
var start_tick: int; var exec_tick: int; var end_tick: int
var phase: int                           # AT_*
var affected_mask: int                   # bit p = player p should see the zone; recomputed every 10 ticks during WARNING
var refresh_tick: int
var payload_ids: PackedInt32Array        # marked units (counterlaunch), captured at activation
func checksum_into(ck: Checksum) -> void

class_name SimScheduled extends RefCounted
var tick: int; var seq: int; var kind: int          # SK_*
var owner: int; var src_idx: int; var attack_id: int
var x: int; var y: int; var r: int; var a: int; var b: int; var c: int; var d: int   # kind-specific ints
var ids: PackedInt32Array
func checksum_into(ck: Checksum) -> void

class_name SimImpactPacket extends RefCounted
var x: int; var y: int; var radius: int           # sub-cells; centre of blast (outer radius)
var radius_min: int                               # sub-cells; 0 = full disc, > 0 = annulus (Perun ring: 3 cells)
var damage: int                                   # at centre, before falloff/armor/resist
var dmg_type: int; var dmg_sub: int               # ASSUMPTION(combat) SimDamage.T_* / SUB_THERMAL
var falloff_edge_bp: int                          # damage fraction at the radius edge (0 = linear to zero, 10000 = flat)
var struct_mult_bp: int                           # multiplier vs structures (10000 neutral)
var team_mask: int                                # bit t = team t is hurt (computed by emit site; ENEMY_ONLY handled by caller)
var layer_mask: int                               # SimEntity layer bits hit
var pre_resist_bp: int                            # extra resistance contributed before the 50 % cap (Trident: 5000)
var flags: int                                    # PKT_*
var src_x: int; var src_y: int                    # firing position in sub-cells; -1,-1 = off-map (bombardments, orbital); used for Trident "fired from inside bypasses"
var src_pid: int; var src_kind: int; var src_idx: int; var attack_id: int
```

### 4.5 Knob table (`SimPlayerEcon.knob_*`; effective value read through `SimStrategicSystem.knob`)

`effective(k) = combine(knob_base[k], knob_temp[k] if knob_until[k] > tick else neutral)`. Roster/research writes `knob_base`; powers write `knob_temp` + `knob_until` (absolute tick). Combine modes: **MUL** (`base * temp / 10000`, temp neutral 10000), **ADD** (`base + temp`, neutral 0), **OVR** (temp replaces base while active), **MIN** (`min(base, temp)`).

| id | `K_*` | mode | default (base) | writers |
|---|---|---|---|---|
| 0 | `SAP_RESERVE_TICKS` | – | 400 if roster faction = SAP else 0 | `research.sap.reserve_capacitors` → 700 |
| 1 | `PAD_EXTRA` | – | 0 | `research.napc.dispersed_runways` → 2 |
| 2 | `REARM_RATE_BP` | MUL | 10000 | `research.pd.integrated_flight_decks` → 11765 (= 10000/0.85) |
| 3 | `SALVAGE_TICKS` | MIN | 160 | `research.ae.recovery_winches` → 100; power `ae.recovery_priority` temp 60 |
| 4 | `REPAIR_RATE_TECH_BP` | – | 10000 | `research.pd.expeditionary_maintenance` → 12500 |
| 5 | `REPAIR_RATE_TENDER_BP` | – | 10000 | `research.han.modular_servicing` → 15000 |
| 6 | `REPAIR_RATE_DEF_BP` | – | 10000 | `research.nec.tunnel_workshops` → 12500 (Engineer + Pioneer vs `defense`-tagged structures) |
| 7 | `REPAIR_COST_ENG_VEH_BP` | – | 10000 | `research.def.standardized_parts` → 8500 |
| 8 | `EMP_RECOVERY_STRUCT_BP` | – | 10000 | `research.def.buried_command_lines` → 7500 (duration multiplier for Radar + defenses) |
| 9 | `EMP_RECOVERY_UNMANNED_BP` | – | 10000 | `research.han.resilient_mesh` → 7500 |
| 10 | `RELAY_RADIUS_CELLS` | – | 6 | `research.nec.distributed_control` → 8 |
| 11 | `RELAY_HOLD_TICKS` | – | 0 | `research.nec.distributed_control` → 200 |
| 12 | `RELAY_DAMAGE_BP` | OVR | 1000 | power `nec.treaty_coordination` temp 1500 |
| 13 | `CMD_RADIUS_CELLS` | ADD | 5 | `research.han.distributed_cognition` base 7; power `han.reserve_bandwidth` temp +3 |
| 14 | `CMD_DAMAGE_BP` | OVR | 1000 | power `han.central_priority` temp 2000 |
| 15 | `PROD_RATE_BARRACKS_BP` | MUL | 10000 | power `def.mobilization_order` temp 12500 |
| 16 | `PROD_RATE_FACTORY_BP` | MUL | 10000 | power `def.mobilization_order` temp 12500 |
| 17 | `JOINT_LANDING` | OVR | 0 | power `pd.joint_landing` temp 1 |
| 18 | `RECOVERY_PRIORITY` | OVR | 0 | power `ae.recovery_priority` temp 1 |
| 19 | `K_COUNT` | | | |

Knobs 10–14, 17 are *consumed* by other domains (abilities, transports) through `SimStrategicSystem.knob(...)`; this domain owns their storage, research writers and window timers (`ASSUMPTION(abilities)`: they read, never write).

### 4.6 Deposit table, placement result, rule rows

```gdscript
class_name SimDepositTable extends RefCounted
var count: int
var x: PackedInt32Array; var y: PackedInt32Array; var radius: PackedInt32Array   # sub-cells (field radius)
var klass: PackedInt32Array            # 0 starter, 1 expansion, 2 rich
var stock: PackedInt32Array; var cap: PackedInt32Array
var regen_amount: PackedInt32Array; var regen_period: PackedInt32Array; var regen_delay: PackedInt32Array   # ticks
var last_harvest_tick: PackedInt32Array; var next_regen_tick: PackedInt32Array
var harvesters: PackedInt32Array       # collectors currently assigned (h_field == idx)
var deposit_mask: PackedByteArray      # map-sized, 1 = cell centre inside any field disc (placement rule 5); derived once at setup, not hashed
func checksum_into(ck: Checksum) -> void

class_name SimPlacementResult extends RefCounted   # caller-owned, reused
var reason: int; var ox: int; var oy: int; var w: int; var h: int      # origin cell + rotated footprint size
var in_radius: bool; var apron_ok: bool; var berth_ok: bool
var cells: PackedByteArray             # w*h entries: CF_OK=0, CF_TERRAIN=1, CF_STRUCTURE=2, CF_UNIT=3, CF_DEPOSIT=4, CF_DEBRIS=5, CF_APRON=6, CF_SHORE=7
```

**System-private persistent state (also hashed).** `SimEconomySystem`: `_wreck_ids: PackedInt32Array` (FIFO of live wrecks for the 128 cap), `_sell_ids`, `_repair_ids`, `_capture_ids` (ascending id lists of structures needing per-tick service), `_power_recheck_tick`. `SimStrategicSystem`: `_sched: Array[SimScheduled]`, `_seq: int`, `_warnings: Array[SimWarning]`, `_next_warning_id: int`, `_next_attack_id: int`. `SimProductionSystem`: none (all state is in `SimPlayerEcon` / `SimCompProd`).

`DefStructureRules.Row` (from `structure_rules.json`, one per `s_idx`, section 7.2): `fw, fh` footprint cells; `rotatable`; `power_class`; `queue_kind` (`PROD_*` or 0); `exit_dx, exit_dy` (exit cell relative to origin, rotation-aware for Dock); `apron` (list of relative cells); `dock_dx, dock_dy` (Refinery collector dock cell); `berth` rect (Dock, relative, must be water); `pads_base`, `pad_dx/dy[]` (Airfield); `sell_refund_bp` override; `repair_basis_cost` (used when `paid_cost == 0`); `max_per_player` (strategic = 1, else 0 = unlimited); `strategic` flag; `build_radius_cells` (HQ only = 8); `sight_cells` is *not* here (balance/structures).

---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Credits and progressive payment (`rule.design.economy`, ARCH §12)

* **Handicap.** `income_bp = handicap_pct * 100` (net.md 5.3.6: 50..200 %, economic only). `earn()` with reason `HARVEST`, `SALVAGE` or `DEPOT` credits `amount * income_bp` through the remainder accumulator (`acc += amount * income_bp; credited = acc / 10000; acc %= 10000`), so 10 credits at 120 % pay 12 and at 125 % alternate 12, 13; starting credits are scaled once in `init_player`. Nothing else (cost, build time, refunds, repair, power, cooldowns) is affected, so the bible floors stay intact.
* **Single currency.** `SimPlayerEcon.credits: int >= 0`. Only `spend()` / `earn()` mutate it. `spend` is all-or-nothing. Start credits come from `MatchRules.start_credits` (bible preset 7,500) through `init_player`; the starting HQ is spawned already `ST_ACTIVE` with `paid_cost = 0` and `EF_FREE`.
* **Progress unit = bp-ticks.** An item with locked `cost` and locked `ticks` completes when `progress >= total`, `total = ticks * 10000`. Each tick a progressing item adds `rate_bp` (10000 = normal speed) to `progress`, so speed changes are exact integers and never lose remainders.
* **Payment.** After computing `new_progress = min(progress + rate_bp, total)`:

```
target_paid = cost * new_progress / total            # integer floor; == cost when new_progress == total
delta       = target_paid - paid
if delta > credits:  state = PAUSED_FUNDS ; progress unchanged ; return      # "pauses at 0 credits"
credits -= delta ; paid += delta ; progress = new_progress                  # ledger reason CR_CONSTRUCTION/PRODUCTION/RESEARCH
```

  Magnitudes: `cost <= 5000`, `total <= 1800*10000 = 1.8e7` -> product `<= 9e10 << 2^62` (DR-5).
* **Worked example (Factory: cost 2000, 40 s = 800 ticks, total = 8,000,000).** Normal rate 10000: `target_paid` rises 2.5 per tick, so the item pays 2,3,2,3... credits per tick (50 credits/s on average: 2000 over 800 ticks); after 400 ticks `paid = 1000`; cancel refunds exactly 1000. Under shortage (`rate_bp = 5000`) it takes 1600 ticks and pays 1.25/tick; with shortage + Mobilization Order (Barracks/Factory only) `rate_bp = 5000 * 12500 / 10000 = 6250`. If credits are 1 when `delta = 2`, the item sits in `PAUSED_FUNDS` (no progress, no payment) until income arrives; payment resumes at the same progress point.
* **Refund on cancel / producer sold:** `paid` is credited back in full immediately (`CR_REFUND`), never anything else. A destroyed producer or lost construction context forfeits the paid amount of its head item (no refund) — except construction items, which are player-owned and keep their state.
* **Fairness when credits are scarce.** Each tick, per player, the heads are visited in the order `[construction, research, producer_flat...]` rotated by `(tick + pid) % n`, so no queue is permanently starved. All visits use the same `credits` variable, so two queues can never spend the same credit.
* **`paid_cost` on the produced entity** equals the locked `cost` (post-modifier price actually paid). It is the only basis for sell refund, repair cost and salvage payout. Free entities (`EF_FREE`: starting HQ, the Refinery's free Collector, neutral structures at capture) have `paid_cost = 0` and fall back to `repair_basis_cost` from `structure_rules.json` / `economy.json` for repairs only.

### 5.2 Resolved cost, time, floors (consumed, not computed here)

`GameData.resolve` produces `ResolvedRoster.unit_cost/unit_ticks/struct_cost/struct_ticks/struct_power` using the bible layering `final = base * Π_layers(1 + Σ delta_in_layer/100)` (base -> parent faction -> subfaction -> research/temporary), rounding **half-up once at the end** and applying floors `cost >= ceil(0.6*base)`, `build_ms >= ceil(0.6*base_ms)`. **This domain expects and tests exactly these results** (test 10.1-L):

| Case | Computation | Result |
|---|---|---|
| Kazakhstan Refinery cost (`modifier.def.kazakhstan.02`, -15 %) | 1800 * 0.85 | **1530** (floor 1080) |
| Alpine Brotherhood Watchtower cost (-15 %) | 450 * 0.85 = 382.5 | **383** |
| Alpine Brotherhood Lance Rail Emplacement (advanced defense, -15 %) | 1800 * 0.85 | **1530** |
| North Korea defensive structure cost (-10 %) | 800 (AT turret) * 0.90 | **720** |
| India Generator cost (-10 %) | 600 * 0.90 | **540** |
| Nigeria non-superweapon structure build time (-10 %) | Barracks 20 s -> 18.0 s | **360 ticks**; Factory 40 s -> 720 ticks; Superweapon (excluded) 90 s -> **1800** |
| Australia Airfield build time (-15 %) | 35 s -> 29.750 s -> ceil(29.75*20) | **595 ticks** |
| OLM Generator output (`modifier.olm.05`, +25 %) | 150 * 1.25 = 187.5 | **188** (half-up) |
| Saudi Arabia Generator output (+25 % parent x +20 % subfaction, layers multiply) | 150 * 1.25 * 1.20 | **225** exactly |
| Layer example (DEF parent -10 % x Russia +10 % vehicle cost) | 1000 * 0.90 * 1.10 | **990** (not 1000) |
| Durations from seconds | `ticks = ceil(seconds*20)` with integer ms math | 45 s = 900, 75 s = 1500, 8 s = 160 |

Bible nulls this domain needs filled by the balance layer (section 7.9): Relay build time (recommended **20 s**), MCV / Engineer / Collector / Landing Transport build times (recommended **45 / 12 / 30 / 25 s**), and every combat-unit cost/time.

### 5.3 Construction queue, placement and structure lifecycle

**Queue (`SimPlayerEcon.cq_*`).** Player-wide, FIFO, length 5, one item progresses at a time (the head). Cost/ticks are locked at enqueue. Enqueue never spends credits.

`structure.shared.headquarters` is never queueable (it only comes from the start preset or MCV deployment; its bible build time is null) and neutral defs are never queueable (`NOT_AVAILABLE`). `can_queue_structure` checks, in order: active HQ exists (`NO_HQ`) -> `struct_available[s_idx]` (`NOT_AVAILABLE`) -> prerequisites (`PREREQ`, evaluated on `struct_count`) -> superweapons enabled (`FEATURE_OFF`) -> strategic limit (`STRATEGIC_LIMIT`: `strategic_owned + queued_strategic + 1 <= 1`) -> queue room (`QUEUE_FULL`). Enqueue with `count > 1` is all-or-nothing.

**Head states** (`cq_state`): `ACTIVE` (progressing) -> `READY` (complete, waiting for placement; the queue is blocked until placed or cancelled, C&C style) ; `HOLD` (player hold: no progress, no payment); automatic pauses `PAUSED_FUNDS`, `PAUSED_PREREQ` (no active HQ, or a prerequisite structure lost). Completed-but-unplaced items are unaffected by later prerequisite loss (they are finished), but the placement command re-validates everything (except tier prerequisites) at placement time. Cancelling a `READY` item refunds `cq_paid` (= full cost).

**Placement command** `CMD_BUILD_PLACE(s_idx, cx, cy, rot)`: requires `cq_state == READY and cq_def[0] == s_idx` (`NOT_READY`), then `SimPlacement.validate` (below). On success: friendly ground units inside the footprint are pushed out (`world.movement.eject_units_from_rect`), the structure entity is spawned in `ST_BUILDUP` with `paid_cost = cq_paid`, the queue head is popped, `cq_progress = cq_paid = 0`. Rejections leave the queue untouched and emit `EVT_PLACE_REJECTED(reason)`.

**Build radius (decision).** Measured **from the centre of each friendly ACTIVE HQ to the nearest point of the candidate footprint rectangle**, Euclidean, in exact sub-cell ints: valid iff `min over ACTIVE HQ of dist2_point_to_rect(hq_cx, hq_cy, rect) <= (8*1024)^2 = 67,108,864`. Rationale: the bible measures radii "from the marked centre" (`rule.combat.damage_and_area_notation`) and a structure occupying part of the ring is allowed. Worked example: 3x3 HQ with origin cell (10,10) has centre (11.5, 11.5) cells; a 2x2 Barracks at origin (19,11) has nearest x = 19.0 -> distance 7.5 cells -> valid; at (20,11) -> 8.5 -> `OUT_OF_RADIUS`. Relay, neutral structures, allied HQs and MCVs never extend the radius (`structure.nec.relay` condition honored by construction: it uses the same test).

**`SimPlacement.validate` order** (first failing reason is returned; **all** failing cells are marked in `cells[]` for ghost colouring):

1. Footprint (rotated size `w x h`) inside map with a 1-cell margin -> `TERRAIN`.
2. Radius (above) -> `OUT_OF_RADIUS` (skipped by `validate_hq_site`).
3. Terrain: every cell `MapData.is_buildable` (land, slope ok, no static obstacle) -> `TERRAIN`.
4. Structure overlap: `world.struct_grid` (cell -> structure id) non-zero, or neutral structure -> `STRUCTURE_BLOCK`.
5. Deposit fields: `deposit_mask[cell] == 1` (precomputed: cell centre within any deposit radius) -> `DEPOSIT` (protects the economy and forbids wall-abuse on fields).
6. Debris: `world.zones.blocks_construction(cx, cy)` (Horizon debris) -> `DEBRIS`.
7. Units: any **ground** entity centre in the footprint that is enemy/neutral or immobile blocks -> `UNIT_BLOCK`; friendly mobile ground units do not (they are ejected at placement). Air units never block. `ASSUMPTION(movement)`: `eject_units_from_rect`; without it fall back to "any ground unit blocks".
8. Apron: (a) the new structure's own apron cells must be passable terrain and free of structure footprints; (b) the new footprint must not overlap the apron cells of any existing structure (checked against structures found by a spatial query on the footprint expanded by 3 cells) -> `APRON`.
9. Shore (Dock only): footprint cells land, and every cell of the rotated `berth` rectangle is water with `MapData.water_body_size >= 30` cells (no puddle docks) -> `NEEDS_SHORE`. `rot` is honored only for `rotatable` defs (Dock).
10. Strategic: `max_per_player` re-check -> `STRATEGIC_LIMIT`.

**Special-case placement rules (summary).** *Dock:* shoreline rule 9 with a rotatable berth. *Relay:* no exception at all: prerequisite Radar, ordinary 8-cell build radius, and it never extends the radius (bible: "does not extend that range"). *Refinery / Barracks / Factory / Airfield:* their aprons must stay clear so units exit and Collectors dock. *Strategic launcher:* at most one per player (queued + owned). *Defenses:* no extra rule beyond prerequisites and the radius. *HQ via MCV:* rules 1, 3–9 only. Neutral structures are placed by the map generator, never by players.

**Default footprints (cells, `structure_rules.json`).** HQ 3x3 · Generator 2x2 · Refinery 3x3 (dock cell south, apron 3x2) · Barracks 2x2 (apron 2x2) · Factory 3x3 (apron 3x2) · Dock 3x3 + 3x2 water berth · Radar 2x2 · Airfield 6x3 (6 pad cells in the middle row, 4 usable + `K_PAD_EXTRA`, apron 6x1) · Laboratory 3x3 · Watchtower 1x1 · Anti-tank turret 1x1 · AA battery 2x2 · advanced defenses 2x2 · Relay 1x1 · superweapon launchers 4x4. Structure centre in sub-cells: `x = cx*1024 + w*512`, `y = cy*1024 + h*512`.

**Lifecycle (`SimCompEcon.st`).**

| From | To | Trigger | Effects |
|---|---|---|---|
| (spawn by placement) | `BUILDUP` | `CMD_BUILD_PLACE` | Inert 30 ticks (`buildup_ticks`): not in `struct_count`, no power, no production, but occupies its footprint, has full hp and is targetable. |
| `BUILDUP` | `ACTIVE` | `tick >= st_until` (stage 2) | `SimStructureLife.activate`: register `struct_count[s_idx]++`, `active_hq_count`, power `power_delta`, `refinery_ids`, `producer_ids/flat`, `strategic_owned`, pads (`pad_ent.resize`), first producer of a kind becomes primary, Refinery spawns its free Collector, `power_dirty`. |
| `ACTIVE` | `SELLING` | `CMD_SELL` | Unregistered immediately (power and prerequisites drop now); queue heads refunded; 40 ticks (`sell_ticks`); cannot be cancelled; if killed during the sale, no refund. |
| `SELLING` | removed | `tick >= st_until` (stage 3) | credit `paid_cost * sell_refund_bp / 10000` (`sell_refund_bp = 5000`, flat regardless of hp) with `CR_SELL`; `remove_entity`. HQ (`paid_cost = 0`) refunds 0: "no free deployment income". |
| `ACTIVE` (HQ) | `UNDEPLOYING` | `CMD_UNDEPLOY_HQ` | Unregistered; 40 ticks; then HQ removed and an MCV spawned at the HQ exit with `paid_cost = mcv_paid_cost`, ignoring unit cap. |
| any | destroyed | `on_entity_died` | Unregistered; head items forfeited; `strategic.on_structure_lost`. |

Sell is refused (`LOCKED`) while the structure is a launcher with a `WARNING` attack, while `BUILDUP`, or when `EF_SELL_LOCKED`.

**MCV / HQ.** `ORD_DEPLOY_MCV` (order `x/y` optional: move there first). Site test `validate_hq_site`: 3x3 centred on the MCV's cell, rules 1 and 3–9 (no radius, no prerequisite). On success: MCV removed silently, HQ spawned in `BUILDUP` with `mcv_paid_cost = mcv.paid_cost`, `paid_cost = 0`, `EF_FREE`. The MCV counts as a capped unit while alive. Failure: `EVT_ORDER_FAILED(reason)` and the order ends; the AI uses `SimPlacement.find_site` around a desired point. Undeploy-then-redeploy restores the same MCV value, so there is no income loop. **All construction requires >= 1 ACTIVE HQ** (`NO_HQ` / queue pause), which is the bible's "construction anchor".

**Structure repair (wrench mode).** `CMD_SET_STRUCT_REPAIR` sets `repair_on`. While `repair_on`, `st == ACTIVE`, `hp < max_hp`: every tick `SimEconomySystem.repair_step(null, ent, RC_WRENCH, RS_WRENCH)` (see 5.11): rate 1 %/s of max hp, cost 0.5 % of paid price per 1 % hp (the Engineer baseline), pause when credits are insufficient, auto-off at full hp. Not blocked by combat.

### 5.4 Unit production (`rule.design.production`, ARCH §12)

**Queues.** Every ACTIVE producer structure has a `SimCompProd` queue of length 5 (`kind` = Barracks, Factory, Airfield, Dock, and Refinery whose only buildable is the Collector, because the bible names the Refinery as the Collector's `producer_structure_id`). Additional producers add queues, never hidden speed bonuses.

**`can_queue_unit(pid, producer_id, u_idx)`** in order: producer exists, owner match, `ST_ACTIVE` (`WRONG_KIND`/`LOCKED`); `unit.producer_kind == prod.kind` (`WRONG_KIND`); `unit_available[u_idx]` (`NOT_AVAILABLE`: a replaced unit cannot also be built); prerequisites = the unit's `requires_all_structure_ids` (already contains the producer, T2 adds Radar, T3 adds Radar + Laboratory) on `struct_count` (`PREREQ`); room in queue (`QUEUE_FULL`). `producer_id = 0` resolves via `q_find_producer` (primary building first, else fewest queued items, ties lowest id). Queueing on an EMP-shut-down producer is allowed (it just pauses).

**Head update (per queue, per tick)** — state precedence, first match wins:

```
hold                                   -> QS_HOLD
producer shutdown_until > tick         -> QS_PAUSED_SHUTDOWN
!prereqs_met(unit.req)                 -> QS_PAUSED_PREREQ          # "losing a prerequisite pauses dependent orders"
not head_cap_reserved and cap_cost>0 and unit_cap_room < cap_cost
                                       -> QS_PAUSED_CAP             # reservation happens when the head first advances
else advance (5.1) with rate_bp[prod.kind]  -> QS_ACTIVE or QS_PAUSED_FUNDS
if progress >= total: spawn_from_producer -> success: pop head ; blocked exit -> QS_PAUSED_EXIT (retry every 10 ticks)
```

**Unit cap.** `unit_cap_room = unit_cap - unit_count - cap_reserved`. `unit_count` counts live `EF_CAPPED` entities (non-structure, non-`EF_TEMPORARY`; each counts `unit_cap_cost`, default 1, from `DefUnit`). The free Collector and MCVs produced by undeploying an HQ bypass the check. Summons, decoys, carrier drones, Tempest drones, Dragonfall engines and power stations are never capped.

**Exit & rally.** Spawn cell = structure `exit` cell (rotation-aware). If a ground unit occupies it, `world.movement.find_free_cell_near(cell, layer, 4) -> int` picks the nearest free cell (ties: lowest cell index); none -> `QS_PAUSED_EXIT`. Airfield: spawn on the lowest free pad (`pad_ent[i] == 0`), else at the exit. Dock / Landing Transport: spawn in the free berth water cell nearest the exit. After spawn, if `rally_on`: issue an internal `ORDER_MOVE` to the rally point (Collectors ignore plain rally and auto-harvest; `rally_target < 0` encodes "harvest deposit `-rally_target-1`"; aircraft ignore rally). Rally cell validity is the movement domain's problem; an unreachable rally simply leaves the unit at the exit.

**Primary building.** The first producer of each kind becomes primary; `CMD_SET_PRIMARY` moves the flag (exactly one per kind per player).

**Special producers.** *Refinery:* Collector queue only (rate `rate_bp[REFINERY]`), plus a free Collector on activation. *Factory:* MCV (T2: Factory + Radar). *Dock:* Landing Transport (T1) and ships. *Airfield:* aircraft plus pad servicing API (5.14). *Harbor Terminal (neutral):* Dock queue restricted to units whose prerequisite list is `{dock}` (T1 only).

### 5.5 Tech gating and prerequisite loss (`rule.design.technology`, `mechanical_conventions.tier_requirements`)

* `prereqs_met(req)` is `for s in req: struct_count[s] > 0`. `struct_count` counts only `ST_ACTIVE`, non-temporary, non-decoy structures owned by the player (BUILDUP, SELLING and dead structures do not count; EMP shutdown and power shortage do **not** remove a prerequisite — the bible's "powered" flags are activation conditions, not tech dependencies).
* T1 = producer only; T2 adds `structure.shared.radar`; T3 adds Radar + `structure.shared.laboratory`. The lists come straight from the bible `requires_all_structure_ids`; a build-time validator (`check_econ_data.py`) asserts `tier 2 => radar in list`, `tier 3 => radar and laboratory in list` for every unit, research and power.
* Losing a prerequisite pauses, in place, every dependent **unfinished** unit head (`PAUSED_PREREQ`) and research head; progress and paid credits are kept; they resume automatically when the structure is rebuilt. Queued (non-head) items are re-checked when they become head. Completed upgrades and already-produced units persist. Dependent **construction** items behave identically. A `READY` structure can still be placed.
* Headquarters deployment from an MCV is not a prerequisite edge (README rule): `structure.shared.headquarters` appears in `Generator.requires` and is satisfied by any ACTIVE HQ, whether original or deployed.

### 5.6 Research (`rule.design.research`)

* One player-wide queue, length 3 (each roster has only 2 (vanilla) or 3 (subfaction) upgrades). `can_queue_research`: `research_available[r]` (roster), not yet researched, not already queued, prerequisites met now (T2: Radar; T3: Radar + Laboratory), room.
* Cost = bible `cost_credits`; ticks = `research_time_seconds * 20` = **900** (T2) / **1500** (T3). Same progressive-payment loop as 5.1 with `rate_bp[RESEARCH]`; paused (`PAUSED_PREREQ`) while Radar / Laboratory are missing; `HOLD` by player; 50 % speed under shortage (shortage rate).
* On completion: `researched[r] = 1` (never cleared, so upgrades persist through building loss); `apply_research_knobs` writes the economy knobs listed in `economy.json.research_knobs` (5.8); `world.data.apply_research(pid, r_idx)` refreshes the resolved tables (research layer); `world.abilities.on_research_complete(pid, r_idx)` lets the ability domain react; `EVT_RESEARCH_COMPLETE(pid, r_idx)`.
* Cancel refunds `rq_paid` in full. Research needs no specific building beyond the prerequisites, and there is no separate "research building" (bible: player-wide queue).

### 5.7 Power grid, shortage and the SAP reserve (`rule.design.power_loss`)

**Balance.** For player `p`: `supply = Σ max(0, power_delta)` and `demand = Σ max(0, -power_delta)` over that player's `ST_ACTIVE`, non-temporary structures; `power_delta` is `ResolvedRoster.struct_power[s_idx]` frozen at activation (Generator +150, OLM +188, Saudi +225; Refinery -30, Barracks -10, Factory -40, Dock -35, Radar -40, Airfield -40, Laboratory -60, Watchtower -5, Anti-tank turret -15, AA battery -20, advanced defense -40, Relay -20, superweapon launcher **-200**, HQ 0). A captured Grid Substation registers its +100 through the same path. `BUILDUP` and `SELLING` structures are not counted; EMP-shut-down structures **still consume**. The balance is recomputed in stage 3 whenever `power_dirty` (set by activate / deactivate / sell / death / owner change) and unconditionally every 100 ticks (debug builds assert equality with the incremental value).

**Shortage.** `power_state = SHORTAGE` iff `demand > supply` (strict; exactly balanced is normal). Evaluated in stage 4 right after the stage-3 balance, so stage 2 sees the change one tick later (deterministic 1-tick latency); `power_state` changes only inside stage 4, hence it is stable for stages 5–11 of the same tick (abilities and combat may poll it freely). Transition events: `EVT_POWER_SHORTAGE(pid, supply, demand)` and `EVT_POWER_RESTORED(pid)`; `rates_dirty = true` on every transition. Worked example: HQ + Generator + Refinery + Barracks + Factory + Radar = 150 supply vs 30+10+40+40 = 120 demand (normal); adding a Laboratory (+60) gives 180 > 150 -> shortage until a second Generator (+150) is active (300 vs 180).

**What shortage does (each bible clause -> mechanism):**

| Bible clause | Mechanism |
|---|---|
| "normal production and research progress at 50 % speed" | `refresh_rates`: `rate_bp[k] = 10000 * 5000/10000` for **every** PROD_* index (unit queues, construction, research). Multiplies with temporary rate windows. |
| "powered defenses ... stop" | `defenses_online(pid)` false -> Combat treats `PC_DEFENSE` structures as unable to acquire/fire and their detector radius (Watchtower 4, AA battery 5) is inactive; sight is unaffected. |
| "Relay bonuses stop" | `structure_online()` false for `PC_RELAY`; abilities honour `K_RELAY_HOLD_TICKS` (Distributed Control: retains the field 10 s = 200 ticks after power loss, not after destruction). |
| "Powered Radar/Laboratory support powers cannot activate" | `radar_online` / `lab_online` require `powered(pid)`; `CMD_USE_POWER` rejects with `NO_POWER`. Already-running effects continue. |
| "Superweapon recharge pauses" | charge increments only while `powered(pid)` (5.19). Warnings and executions already started continue. |
| "Existing units and completed upgrades continue to work" | No effect on units or `researched`. |
| "Aircraft need powered Airfield pads to rearm" | `pads_online(airfield)` = ACTIVE ∧ ¬shutdown ∧ `powered(pid)`; the air domain must not rearm/repair on offline pads. |
| Harvesting / unloading | Unaffected by shortage (Refinery is `PC_ECON`); stops only under EMP shutdown. |

**Power classes and `structure_online(ent)`.** `st == ACTIVE ∧ shutdown_until <= tick ∧` (`NONE`,`ECON`,`PRODUCER`: true; `SENSOR`,`RELAY`,`STRATEGIC`: `powered(pid)`; `DEFENSE`: `defenses_online(pid)`). Producers stay "online" under shortage because the bible slows them instead of stopping them.

**SAP defense reserve** (`PF_SAP_RESERVE`; bible trait "defenses keep operating for 20 seconds after a power shortage begins; reserve recharges only after 60 continuous seconds of adequate power; EMP-disabled defenses remain disabled; superweapons never use this reserve"). Per tick in stage 4:

```
reserve_max = knob(K_SAP_RESERVE_TICKS)                  # 400 (20 s); 700 (35 s) after Reserve Capacitors
if power_state == SHORTAGE:
    adequate_streak = 0
    if reserve_left > 0: reserve_left -= 1               # drains ONLY while short
    defenses_online = reserve_left > 0                   # EVT_SAP_RESERVE_EMPTY when it hits 0
else:
    defenses_online = true
    adequate_streak = min(adequate_streak + 1, 1200)
    if adequate_streak >= 1200: reserve_left = reserve_max        # full recharge after 60 s continuous adequacy
```

Non-SAP players: `defenses_online = powered`. Reserve does not affect production, Relay, powers or superweapons, and never overrides `shutdown_until`. When `research.sap.reserve_capacitors` completes: if `reserve_left == old_max` then `reserve_left = 700`, else unchanged (the extra capacity fills through the normal 60 s recharge rule). **Worked timeline:** shortage 1000–1500 -> reserve empty at tick 1400, defenses offline 1400–1500; power back at 1500 -> streak reaches 1200 at tick 2700 -> `reserve_left = 400`. Variant: shortage 1000–1200 only -> `reserve_left = 200`; a second shortage at 1800 (before the refill at 2400) drains the remaining 200 by tick 2000.

**OLM generators (+25 %)** are not special-cased: they arrive as a larger `struct_power` for the Generator def (188), Saudi 225. **Generator loss** immediately calls `mark_dirty`.

### 5.8 Economy-side research effects (knobs)

`economy.json.research_knobs` maps research ids to knob writes; `apply_research_knobs(pid, r_idx)` runs once at completion (idempotent by `researched`). The 12 research upgrades whose effect lives in this domain:

| Research | Knob write | Consumer |
|---|---|---|
| `research.napc.dispersed_runways` | `K_PAD_EXTRA = 2` (Airfield `pad_ent` resized on all owned and future Airfields; rate per pad unchanged) | pad API (5.14) |
| `research.pd.integrated_flight_decks` | `K_REARM_RATE_BP = 11765` (rearm time x 0.85) | pad API; **carrier drone replacement time -15 %** is combat/air (queries `has_research`) |
| `research.ae.recovery_winches` | `K_SALVAGE_TICKS = 100` (5 s instead of 8 s; wreck value unchanged) | 5.12 |
| `research.sap.reserve_capacitors` | `K_SAP_RESERVE_TICKS = 700` | 5.7 |
| `research.def.standardized_parts` | `K_REPAIR_COST_ENG_VEH_BP = 8500` | 5.11 |
| `research.nec.tunnel_workshops` | `K_REPAIR_RATE_DEF_BP = 12500` (Engineer + Pioneer repairing `defense`-tagged structures; cost per hp unchanged) | 5.11 |
| `research.pd.expeditionary_maintenance` | `K_REPAIR_RATE_TECH_BP = 12500` | 5.11 |
| `research.han.modular_servicing` | `K_REPAIR_RATE_TENDER_BP = 15000` | 5.11 |
| `research.def.buried_command_lines` | `K_EMP_RECOVERY_STRUCT_BP = 7500` (shutdown duration x 0.75 for Radar and `defense` structures; does not prevent the shutdown) | abilities (EMP) |
| `research.han.resilient_mesh` | `K_EMP_RECOVERY_UNMANNED_BP = 7500` | abilities (EMP) |
| `research.nec.distributed_control` | `K_RELAY_RADIUS_CELLS = 8`, `K_RELAY_HOLD_TICKS = 200` | abilities (Relay) |
| `research.han.distributed_cognition` | `K_CMD_RADIUS_CELLS` base = 7 | abilities (command field) |

The other 28 research upgrades are pure combat/ability/movement effects; their owners react to `world.abilities.on_research_complete(pid, r_idx)` and to `has_research(pid, r_idx)` (`SimPlayerEcon.researched`), and the data domain's resolved tables carry stat effects (e.g. Adaptive Plating resistances, Circular Armor +10 % health with a *paid-cost basis unchanged*, satisfied automatically because `paid_cost` is separate from `max_hp`).

### 5.9 Harvesting, refineries and deposits (`rule.design.economy`, `unit.shared.collector`)

**Deposits.** Fields, not cells: each `SimDepositTable` entry is a disc (centre, radius, class). Data classes (defaults in `economy.json`): **starter** cap 8,000, radius 3 cells, regen 40 credits per 200 ticks, max 4 harvesters; **expansion** cap 12,000, radius 3, regen 60/200, max 5; **rich** cap 20,000, radius 4, regen 100/200, max 6; all regen after 1200 idle ticks; all start at `stock = cap`. Map placement (`MapData.deposits`): 2 starter fields within 14–22 cells of each start, 1–2 expansion fields per player-share on the outer ring, 1–2 rich fields in contested centres; none on water; every start is >= 2 exits from fields (ARCH §12).

*Depletion & regeneration (decision):* fields are finite but never permanently dead. Each 20-tick stride, for each `i` with `stock[i] < cap[i]`: if `tick - last_harvest_tick[i] >= regen_delay[i]` and `tick >= next_regen_tick[i]`, then `stock += regen_amount` (clamped) and `next_regen_tick = tick + regen_period`. Idle-only regrowth means camping a field never yields free income; the per-field maximum is 240/min (starter), 360 (expansion), 600 (rich), i.e. at most about one Collector's worth. `EVT_DEPOSIT_DEPLETED(idx)` when stock reaches 0, `EVT_DEPOSIT_REGROWN(idx)` when a depleted field regains >= 10 % of cap.

**Collector constants** (`economy.json.collector`, identical for all rosters per the bible): cargo cap **500**; harvest **5 credits / 4 ticks** (25 credits/s, 20 s to fill); unload **10 credits / 4 ticks** (50 credits/s, 10 s to empty); dock-in 12 ticks, dock-out 8 ticks. All integer chunks, no fractional cash.

**FSM (`SimOrderHarvest.on_update`, one call per Collector per tick, state in `SimCompEcon.h_*`):**

| State | Behaviour and transitions |
|---|---|
| `IDLE` | No order: the orders domain auto-issues `ORD_HARVEST(auto)` for idle Collectors. Immediately `SEEK`. |
| `SEEK` | A Collector may search only when `(id + tick) % 20 == 0` (staggered, i.e. at most once per 20 ticks) and at most **6 searches per tick globally** (a Collector that misses its slot retries at its next slot). If `cargo >= 0.9*cap` -> `TO_REFINERY`. Else `choose_field`; none -> stay `SEEK` (retry after 60 ticks; if `cargo > 0` -> `TO_REFINERY`). Found -> `deposits.harvesters[f]++`, `h_field = f`, `request_move` to the field point nearest the Collector, `TO_FIELD`. |
| `TO_FIELD` | `path_failed` -> `h_bad_field = f`, `h_bad_until = tick + 600`, release field, `SEEK`. Inside the field disc (`dist2 <= (radius - 512)^2`) -> stop, `h_timer = 0`, `HARVEST`. |
| `HARVEST` | Field empty -> release; `cargo>0 ? TO_REFINERY : SEEK`. Every 4 ticks: `take = min(5, stock, cap - cargo)`; `stock -= take; cargo += take; last_harvest_tick = tick`. `cargo == cap` -> release field, `TO_REFINERY`. Threat test each 10 ticks (below). |
| `TO_REFINERY` | Pick refinery (below) unless `h_refinery` is still valid; `request_move` to the refinery approach cell. At approach: `dock_request` -> `GRANTED` = `DOCK_IN`, `WAIT` = `WAIT_DOCK`, `DENIED` = re-pick. No refinery -> `IDLE` with cargo, `EVT_NO_REFINERY(pid)` once per 600 ticks. |
| `WAIT_DOCK` | Re-request every tick (FIFO position kept). If waiting > 400 ticks and another refinery's queue is >= 2 shorter -> re-pick. |
| `DOCK_IN` | Move into the dock cell, 12 ticks -> `UNLOAD`. |
| `UNLOAD` | Each tick `dock_unload_step`; on `cargo == 0`: `EVT_CREDITS_GAINED(pid, h_unload_total, refinery x, y)`, `dock_release`, `DOCK_OUT` (8 ticks) then `SEEK` (prefers `h_last_field`). |
| `FLEE` | See below; ends by `SEEK` (or `TO_REFINERY` when carrying cargo). |

**`choose_field`:** candidates are deposits with `stock > 0`, explored by the owner, `harvesters[i] < max_harvesters(klass)`, not `h_bad_field` before `h_bad_until`, and `field_danger[i] <= tick`. Score `= Fp.dist(collector, centre) + 4096 * harvesters[i] - (i == h_last_field ? 2048 : 0)`; minimum wins, ties lowest index. **`choose_refinery`:** ACTIVE, non-shutdown refineries; score `= Fp.dist(collector, dock cell) + 3072 * (dock_queue_len + (dock_occupant != 0 ? 1 : 0))`; ties lowest entity id.

**Flee (AI- and human-friendly).** Scan every 10 ticks (`h_scan_tick`) and immediately on damage (`hp < h_last_hp`): a hostile **armed** non-air entity visible to the owner within 6 cells, or damage taken -> `FLEE`: release the field, `field_danger[f] = tick + 400` (other Collectors of that player avoid it for 20 s), `h_flee_until = tick + 200`, retreat to the nearest friendly Refinery whose 8-cell surroundings are hostile-free (keeping cargo; unload if reached), else to the nearest friendly structure. After `h_flee_until` with no hostile in 8 cells -> `SEEK`. Emits `EVT_COLLECTOR_ATTACKED(pid, id)` (rate-limited to once per 100 ticks per Collector). Any new player order cancels the FSM; cargo stays on the unit.

**AI-friendliness.** The FSM is self-healing (re-seeks after failed paths, empty fields, lost refineries, flee) so an AI only has to build Refineries/Collectors, defend fields, and may override with `ORD_HARVEST(deposit)` / `ORD_RETURN_CARGO`; it reads `q_deposit_nearest`, `q_collectors`, `q_refineries`, `q_income_per_minute` and per-Collector `h_state`.

**`ORD_RETURN_CARGO`** starts the FSM at `TO_REFINERY` with the given refinery (0 = choose), then auto-harvest resumes. **`ORD_HARVEST(deposit)`** sets `h_mode = 1` (manual) and `h_field`; on depletion it falls back to auto.

**Refinery dock protocol (`SimEconomySystem`).** One dock cell per Refinery. `dock_request`: `DENIED` if the refinery is not ACTIVE or shut down; `GRANTED` if occupant is the caller or (occupant free and (queue empty or caller is queue head)); otherwise append to `dock_queue` (FIFO, no duplicates) and return `WAIT`. `dock_unload_step` accumulates `dock_timer`; every 4 ticks moves `min(10, cargo)` credits with `earn(CR_HARVEST)`. A watchdog in stage 3 clears an occupant that is dead or has held the dock > 400 ticks, and purges dead ids from queues. Refinery destroyed/sold while docked: occupant released with cargo intact (`H_DOCK_OUT` -> `TO_REFINERY`).

**Free Collector.** On `activate` of a Refinery, `spawn_from_producer` creates one Collector at the exit with `paid_cost = 0`, `EF_FREE`, bypassing the unit cap and any queue; it starts `ORD_HARVEST(auto)`. Purchased Collectors (1,400 credits, from the Refinery queue) count against the cap.

**Numbers (design check).** 12 cells one way at 2.4 cells/s = 5 s each way; cycle = 20 s harvest + 5 + 1 (dock-in 12 ticks = 0.6 s, out 0.4 s -> 1.0 s) + 10 s unload + 5 = **41 s** for 500 credits = **12.2 credits/s = ~730/min per Collector**. Payback: Refinery (1,800 incl. one Collector) about 2.5 min; extra Collector (1,400) about 1.9 min. Starting 7,500 credits fund Generator 600 + Refinery 1,800 + Barracks 500 + Factory 2,000 = 4,900 with 2,600 for first units.

**PD Collectors (trait).** `pd.*` rosters mark the Collector `amphibious` with water speed 70 % via the balance `unit_overrides` (`PF_AMPHIBIOUS_COLLECTORS` is informational); this domain needs nothing else: pathing to a deposit across navigable water is the movement domain's job, harvest rules are unchanged.

### 5.10 Engineer-class units and repair categories

All paid repair goes through one primitive (5.11); the bible's baseline is **1 % of the target's maximum health per second, costing 0.5 % of the target's paid price per second** (so a full 0 -> 100 % repair takes 100 s and costs 50 % of the paid price). `repair_profiles.json` (section 7.6) binds unit ids to categories:

| Unit(s) | `RC_*` | Legal targets (all must be friendly, ACTIVE, not `EF_NO_REPAIR`) | Range | Notes |
|---|---|---|---|---|
| `unit.shared.engineer` | `ENGINEER` | land vehicles (`land_vehicle` tag, incl. Collector, MCV, Landing Transport) and any structure | 1.5 cells from target edge | Also captures (5.13) and, for AE, salvages (5.12). No weapon. |
| `unit.ae.reclaimer`, `unit.ae.river_warden` | `ENGINEER` | land vehicles only ("repairs one land vehicle at normal Engineer rate") | 1.5 | Armed; salvage access. |
| `unit.pd.reef_technician` | `TECHNICIAN` | land vehicles or ships, one target at a time | 2.0 | `research.pd.distributed_beachheads` (repair a transport while riding it) is handled by the transport domain calling `repair_step`. |
| `unit.han.lotus_drone_tender` | `TENDER` | friendly **unmanned land units**, never itself; not Dragonfall engines | 2.0 | "paying normal repair cost". |
| `unit.sap.combat_pioneer`, `unit.nec.alpine_pioneer` | `PIONEER` | friendly structures tagged `defense` | 1.5 | Cannot capture (Combat Pioneer), cannot repair vehicles. |
| `unit.han.mekong_field_engineer` | `FIELD_ENGINEER` | friendly structures | 1.5 | Cambodia's +25 % structure repair speed comes from `repair_rate_bp` on the target def. |
| structures (wrench) | `WRENCH` | itself | – | 5.3. |
| Airfield pads | `PAD` | aircraft docked on an online pad | – | ASSUMPTION: 3 %/s (`rate_bp = 300`), same cost rule; bible only says pads "service" aircraft. |

Combat Medic, Lagos drone-guard drone, Factory apron, Field Hospital, Field Repair Drop, Mobile Workshop, Floating Workshop, Expeditionary Workshop, Repair Swarm and Field Refurbishment are **free healing/repair effects owned by the abilities/zones domains or by the REPAIR power kind (5.17)**; they never call `repair_step` and never spend credits.

### 5.11 The paid repair primitive (`SimEconomySystem.repair_step`)

Inputs: `repairer` (null for wrench), `target`, category `rc`, source bit `src_bit`. State on the target's `SimCompEcon`: `repair_acc_hp`, `repair_acc_cost`, `repair_src_mask`, `unit_repairer_id/tick`.

```
if target.hp >= target.max_hp:                      return 0
rate_bp = profile[rc].rate_bp                                         # 100 = 1 %/s of max hp ; 300 for PAD
rate_bp = (rate_bp * res.repair_rate_bp[target_key] + 5000) / 10000   # modifier repair_progress_rate (Cambodia structures 12500); half-up to int bp
rate_bp = (rate_bp * category_knob(rc, target) + 5000) / 10000        # K_REPAIR_RATE_TECH/TENDER; K_REPAIR_RATE_DEF for ENGINEER|PIONEER vs `defense` structures
cost_bp = profile[rc].cost_bp                                         # 5000 = 0.5 % of price per 1 % hp
cost_bp = (cost_bp * res.repair_cost_bp[target_key] + 5000) / 10000  # modifier repair_credit_cost_per_health (AE land vehicles 7500)
if rc == ENGINEER and target is land vehicle: cost_bp = (cost_bp * knob(K_REPAIR_COST_ENG_VEH_BP) + 5000) / 10000   # Standardized Parts 8500
acc  = repair_acc_hp + target.max_hp * rate_bp                        # unit: hp*bp ; one hp = 10000*TPS = 200000 units
h    = min(acc / 200000, target.max_hp - target.hp) ; acc_rem = acc % 200000
if h == 0:  repair_acc_hp = acc_rem ; repair_src_mask |= src_bit ; return 0
cacc = repair_acc_cost + repair_basis_cost(target) * cost_bp * h      # unit: credit*bp*hp ; one credit = 10000*max_hp units
whole = cacc / (10000 * target.max_hp) ; cacc_rem = cacc % (10000 * target.max_hp)
if whole > credits(payer):  return 0                                   # pause at 0 credits: no healing without payment, accumulators untouched
spend(payer, whole, CR_REPAIR) ; repair_acc_cost = cacc_rem ; repair_acc_hp = acc_rem
target.hp += h ; repair_src_mask |= src_bit ; return h
```

The payer is the repairer's owner (wrench: the structure's owner). Intermediate maxima: `rate_bp <= 100*15000*15000/1e8 = 225`, `max_hp*rate_bp <= 1.4e6`; `cacc <= 5000*5000*6000 = 1.5e11` (DR-5 safe). **Rounding:** the bp products round half-up to an int (every bible-derived factor 7500/8500/12500/15000 gives an exact result, so the worked examples are exact); the hp and credit accumulators carry remainders exactly, so no credit or hp is ever created or destroyed by rounding.

* **Claim / stacking.** Different source bits stack additively on the same target (a wrench plus one unit). Within `RS_UNIT` only one repairer holds the target (`unit_repairer_id`); a second unit gets `BUSY` unless the claim is stale (`tick - unit_repairer_tick > 10`). The claim is refreshed every tick by the holder. "Field repair stations cannot repair themselves" and "Dragonfall engines cannot be repaired" are enforced by `EF_NO_REPAIR` on those entities.
* **Worked example.** Guardian Tank, `paid_cost = 1100`, `max_hp = 800` (illustrative). Engineer: `acc` gains `800*100 = 80,000` per tick -> 1 hp every 2.5 ticks = 8 hp/s (= 1 %/s). Cost per hp = `1100*5000/(10000*800)` = 0.6875 credits -> 5.5 credits/s; 0 -> 800 hp = 100 s = **550 credits** (50 % of price). AE: `cost_bp = 3750` -> 412.5 credits total (carry keeps it exact). DEF with Standardized Parts: `4250` -> 467.5. Tunnel Workshops on an Alpine-priced (1,530 credits) Lance Rail Emplacement (`max_hp` 2000): rate 1.25 %/s -> 25 hp/s, cost per hp unchanged at `1530*5000/(10000*2000)` = 0.3825 credits.
* **`repair_basis_cost`** = `paid_cost`, or `structure_rules.repair_basis_cost` / `economy.json.repair.basis_default` when `paid_cost == 0` (HQ basis 3,000 = one MCV; neutral structures 600; the free Collector 1,400) so free assets cannot be repaired for free.

### 5.12 Salvage and wrecks (African Empire; `faction.ae` trait, `rule.combat.submarines_and_wrecks`)

**Wreck creation** (`spawn_wreck`, called by CleanupSystem before freeing a dead entity). A wreck is created iff all hold: `dead.kind == UNIT` with tags `combat` ∧ `land_vehicle` (service vehicles excluded, aircraft/ships/infantry excluded); `dead.flags` has none of `EF_TEMPORARY | EF_DECOY | EF_SUMMON | EF_NO_SALVAGE`; `cause_flags` has none of `DEATH_SELF_DESTRUCT | DEATH_SCUTTLE | DEATH_FRIENDLY_FIRE`; `killer_pid >= 0` and `team(killer) != team(owner)`; the death cell is land; `paid_cost > 0`. The wreck is an entity (`kind WRECK`, `hp` from `summons.json.wreck`, non-blocking, not auto-targeted) carrying `SimCompWreck{paid_cost, owner_pid, killer_pid, flags = WF_SALVAGEABLE, expire_tick = tick + 1200}`. Wrecks exist for every faction (60 s persistence, destroyable by force-fire/splash), but only players with `PF_CAN_SALVAGE` can earn from them.

**Who may salvage.** `PF_CAN_SALVAGE` (roster faction ∈ `economy.json.salvage.enabled_factions` = `[faction.ae]`) and the unit id ∈ `salvage.salvager_units` = `[unit.shared.engineer, unit.ae.reclaimer, unit.ae.river_warden]`. Non-AE Engineers cannot salvage.

**`salvage_can_target`**: player flag (`WRONG_KIND`) -> wreck flag `SALVAGEABLE` (`BAD_TARGET`; pays once) -> `team(salvager) != team(wreck.owner_pid)` (`FRIENDLY`; a wreck of an enemy killed by a third party is fair game) -> `salvage_by == 0` or stale (`BUSY`) -> `expire_tick - tick >= duration` (`EXPIRING`).

**Action.** `SimOrderSalvage`: move within 1.5 cells -> `salvage_begin` (claim, `w_progress = 0`) -> per tick `salvage_tick` (+1) -> at `w_progress >= duration`: `payout = paid_cost * salvage.payout_bp / 10000` (= 20 %, floor), `earn(CR_SALVAGE)`, wreck removed, `EVT_SALVAGE_PAID`. **Uninterrupted** means: any order change, movement, death, or claim loss resets progress to 0 and frees the claim; taking damage does not interrupt. Wreck expiry is frozen while claimed (Cleanup checks `salvage_by != 0`). `duration = effective K_SALVAGE_TICKS` (MIN mode): 160 ticks base, 100 with Recovery Winches, 60 while Recovery Priority is active. Payout never changes with research (bible: "Wreck value is unchanged").

**Worked example.** NAPC Guardian wreck with `paid_cost = 1100` -> payout **220**; duration 160 / 100 / 60 ticks in the three states above. `prototype_priorities` tells the balance team to monitor salvage as a share of income; the payout percentage is one number (`salvage.payout_bp`) precisely so it can be reduced first.

### 5.13 Capture and the neutral structure catalog (`unit.shared.engineer`)

**Rules.** Only structures with `capturable = true` (the neutral catalog below) can be captured, whoever currently owns them; every faction production structure and superweapon is not capturable ("Enemy production and superweapons are not capturable in this prototype"). Only units with the bible tag `capture` (the service Engineer) capture; Combat Pioneer, Sapper, Aguila and others cannot. Preconditions (`capture_can_target`): target `capturable` (`WRONG_KIND`), not owned by the Engineer's team (`FRIENDLY`), no hostile garrison (`GARRISONED`), not `EF_NO_CAPTURE`.

**Channel and progress.** `SimOrderCapture` moves the Engineer to within 1.5 cells of the footprint edge, stops, and each tick calls `capture_channel` (increments `cap_chan[pid]`). Stage 3 evaluates every capturable structure that has channelers or stored progress:

```
attack_teams = { team(pid) : cap_chan[pid] > 0 and team(pid) != team(owner) }
if attack_teams is empty:
    if cap_progress > 0 and tick - cap_last_tick >= 100:  cap_progress = max(0, cap_progress - 2) ;  if 0: cap_pid = -1
elif |attack_teams| >= 2:  contested -> no change ; EVT_CAPTURE_CONTESTED (once per 40 ticks)
else:
    T = the team ; n = min(Σ cap_chan[pid] for pid in T, 3)                # at most 3 Engineers contribute
    if cap_pid != -1 and team(cap_pid) != T:  cap_progress = max(0, cap_progress - n) ; if 0: cap_pid = lowest pid of T with channel
    else:  cap_pid = (cap_pid == -1 ? lowest pid of T with channel : cap_pid) ; cap_progress += n ; cap_last_tick = tick
    if cap_progress >= cap_need:  new_owner = pid of T with most channelers (ties lowest) ; world.change_owner(ent.id, new_owner) ; reset ; EVT_STRUCTURE_CAPTURED
clear cap_chan
```

Engineers are **not consumed**. Capturing takes time: `cap_need` in ticks (table). Worked example (Grid Substation, `cap_need = 240`): 1 Engineer 240 ticks (12 s); 2 -> 120; 3 -> 80; 4 -> 80. If Engineer A of team 1 stores 150 and dies, an enemy Engineer needs 150 ticks to burn the progress down and 240 more to take it. `EVT_CAPTURE_PROGRESS` is emitted every 20 ticks with progress in bp. Ownership change moves power/income/aura registration through `on_owner_changed`; a captured Harbor Terminal's queue is cleared and refunded to the previous owner.

**Neutral catalog** (`neutral_structures.json`; ids `neutral.*` are new, non-bible; neutral owner = `-1`; neutral-owned structures are never auto-targeted and cannot be sold; once owned they are normal targets):

| id | Name | HP | Footprint | `cap_need` | Effect while owned by a player | Map role / placement guidance |
|---|---|---|---|---|---|---|
| `neutral.substation` | Grid Substation | 1200 | 2x2 | 240 (12 s) | **+100 power** (registered like a Generator delta; not multiplied by OLM) | 1 per 2 players on the ring between bases; lets a raid starve an enemy's power |
| `neutral.salvage_depot` | Salvage Depot | 1600 | 3x3 | 400 (20 s) | **+50 credits every 200 ticks** (300/min, about 0.4 Collector), paid by stage 3 to the owner, `EVT_CREDITS_GAINED` | 1 per map centre; symmetrical; contested |
| `neutral.field_hospital` | Field Hospital | 1000 | 2x3 | 300 (15 s) | Free heal aura: friendly **infantry** within 5 cells recover 2 %/s (abilities aura primitive; same-source rule, no stacking with a Medic aura: the highest applies) | forward healing on approach routes |
| `neutral.observation_tower` | Observation Tower | 800 | 1x1 | 300 (15 s) | Sight 14 cells (ordinary structure sight; no detection) | high ground/junctions; fog denial |
| `neutral.civilian_garrison` | Civilian Block | 2000 | 3x3 | not capturable | **Marked civilian garrison**: holds 4 infantry squads; occupants fire out (El-Andalus garrison +20 % applies) | urban map family, 4–8 per map; container mechanics belong to the transports/garrison domain |
| `neutral.harbor_terminal` | Harbor Terminal | 2200 | 3x3 (shore) | 500 (25 s) | Owner gets a forward **Dock queue** restricted to units whose prerequisites are only `{dock}` (patrol boat, Landing Transport); counts as `structure.shared.dock` for those prerequisites only; no other tech | coastal/river maps, 1 per water body >= 40 cells; gives land-locked rosters a water option, supporting the bible's "Landing Transport gives every roster a water-crossing option" |

Map guidance (for the map domain): every neutral sits at least 18 cells from any start; placements are mirrored/rotated for fairness; per 2 players: 1 substation, 1 field hospital, 1 observation tower, 0.5 depot; open-land maps favour substations/depots, urban maps garrison blocks/hospitals, coast/river maps harbor terminals. Incentive check: a captured substation (+100) is worth about 0.67 Generator (400 credits); a depot (300/min) pays a 3-Engineer squad (1,500) back in about 5 min.

**Order state machines (Capture, Repair, Salvage, Deploy MCV).** State lives in `SimCompEcon` (`w_kind`, `w_target`, `w_progress`), never in the order object, so replacing an order cannot leak claims (`on_end` always releases them). Movement is re-requested at most every 10 ticks and only if the target moved more than 2 cells from the last goal.

| Order | State | Behaviour | Exit |
|---|---|---|---|
| `ORD_CAPTURE` | `APPROACH` | `capture_can_target` else `FAILED(reason)`; `request_move` to the nearest free cell within `reach_cells` (1.5) of the footprint edge; `path_failed` -> `FAILED(BAD_TARGET)` | in reach -> `CHANNEL` |
| | `CHANNEL` | stop; every tick `capture_channel`; pushed beyond reach + 1 cell -> `APPROACH` | target owner is now on the Engineer's team -> `DONE`; target destroyed -> `FAILED(BAD_TARGET)` |
| `ORD_REPAIR` | `APPROACH` | `repair_can_target` else `FAILED`; move within the profile range (chase moving vehicles) | in range -> `CLAIM` |
| | `CLAIM` | take `unit_repairer_id` if free, stale or mine; otherwise wait up to 100 ticks then `FAILED(BUSY)` | claimed -> `REPAIRING` |
| | `REPAIRING` | refresh claim; out of range + 1 cell -> `APPROACH`; `h = repair_step(...)`; a paused step (no credits) keeps the state and emits a rate-limited `EVT_INSUFFICIENT_FUNDS` | `hp == max_hp` -> `DONE` (claim released); target dead/sold -> `FAILED` |
| `ORD_SALVAGE` | `APPROACH` | `salvage_can_target`; move within 1.5 cells | in reach -> `WORK` |
| | `WORK` | `salvage_begin` once, then `salvage_tick` each tick; any movement, order change, death or lost claim -> `salvage_cancel` (progress 0) | `SALV_DONE` -> `DONE`; `SALV_FAILED` -> `FAILED` |
| `ORD_DEPLOY_MCV` | `MOVE` (only if the order has a cell) | `request_move` to the cell centre; done within 0.5 cell | -> `CHECK` |
| | `CHECK` / `DEPLOY` | `SimPlacement.validate_hq_site` else `EVT_ORDER_FAILED(reason)` + `FAILED`; then `SimStructureLife.deploy_mcv` | HQ created -> `DONE` |

### 5.14 Airfield pads (interface to the air domain)

`SimCompProd.pad_ent` has `pads_base (4) + effective K_PAD_EXTRA` entries (2 more with Dispersed Runways; service rate per pad unchanged). API on `SimProductionSystem`:

```gdscript
func airfield_pad_acquire(world: SimWorld, airfield_id: int, aircraft_id: int) -> int   # lowest free pad or -1; idempotent for the same aircraft
func airfield_pad_release(world: SimWorld, airfield_id: int, aircraft_id: int) -> void
func airfield_pad_cell(world: SimWorld, airfield_id: int, pad: int) -> int              # map cell index of the pad
func airfield_service_rate_bp(world: SimWorld, airfield_id: int) -> int                  # 0 unless pads_online; else effective K_REARM_RATE_BP * (boost active ? boost_bp : 10000) / 10000
```

The air domain owns rearm progress (using `ResolvedRoster.unit_rearm_ticks[u_idx]`: USA -20 %, Japan unchanged) and multiplies its per-tick progress by `airfield_service_rate_bp / 10000`; pad repair calls `repair_step(RC_PAD)`. Rapid Turnaround sets `rearm_boost_bp = 15000`, `rearm_boost_until = tick + 400` on one Airfield ("50 % faster", not "-50 % time"; it does not touch production). A destroyed Airfield releases its pads: parked aircraft become homeless and the air domain must reassign them.

### 5.15 Roster traits that touch this domain (index)

| Trait (bible) | Where handled |
|---|---|
| Cost / build-time / power-output / rearm / repair modifiers (`cost_credits`, `build_time_seconds`, `power_output`, `rearm_time_seconds`, `repair_progress_rate`, `repair_credit_cost_per_health`) | `GameData` resolves; this domain consumes `ResolvedRoster` tables (5.2, 5.11, 5.14). |
| NAPC Factory service apron | abilities aura on the Factory def (free, non-stacking); not a repair-step. |
| NEC Relay (600 cr, -20 power, 6-cell field, normal build radius) | ordinary structure, `PC_RELAY`; field logic in abilities; build time **20 s** proposed (bible null). |
| OLM +25 % generator output, Saudi +20 % relative | resolved `struct_power`. |
| DEF "no free units, permanent production multiplier or unlimited passive income" | Only temporary `K_PROD_RATE_*` windows exist (Mobilization Order); test 10.1-N asserts no permanent multiplier and no passive income for DEF. |
| PD amphibious Collectors at 70 % water speed | balance `unit_overrides` on `unit.shared.collector` for `faction.pd` rosters (5.9). |
| AE salvage; land-vehicle repair -25 % | 5.12, 5.11. |
| SAP defense reserve, defense health +15 % | 5.7; health is a resolved stat. |
| Cambodia structure repair +25 % | `repair_rate_bp` on structure defs. |

### 5.16 Support-power framework (`rule.combat.support_power_access`, `rule.combat.targeting_and_warnings`)

**Slots.** At `init_player`, `slots[0..2]` are the roster's three support powers in the bible's `resolved.support_power_ids` order (two inherited + one vanilla-only/subfaction), `slots[3]` is the superweapon (`-1` if `MatchRules.superweapons` is off). A power is **unlocked** as soon as its prerequisites exist; it is **ready when first unlocked** because `ready_tick` starts at 0 (there is no opening cooldown). `EVT_POWER_UNLOCKED(pid, slot)` fires once when `can_activate` first passes its prerequisite/power checks (`announced` flag).

**Validation `can_activate` (first failure wins):**

1. slot/def valid, player not eliminated (`INVALID_INDEX`);
2. `tick >= ready_tick` (`COOLDOWN`); **cooldowns run in absolute ticks and are never reset or paused by losing/rebuilding a prerequisite or by power shortage** (bible: "Rebuilding a prerequisite never resets a cooldown");
3. prerequisites: every structure in the bible `requires_all_structure_ids` present (`PREREQ`) — T2: Radar; T3: Radar + Laboratory;
4. **powered** prerequisites (`requires_powered_prerequisites = true` for all 48): `radar_online` (and `lab_online` for T3): ACTIVE, not EMP-shut-down, and `powered(pid)` — otherwise `NO_POWER`;
5. `credits >= cost` (`NO_CREDITS`); cost is paid at activation, non-refundable, `CR_POWER_USE`;
6. target by `TK_*`: `NONE` nothing; `POINT/AREA/LINE`: inside the map (`TERRAIN`), vision rule `VR_*` (`NONE` = reconnaissance: any map location; `EXPLORED` = "scouted": `vision.is_explored`, `NOT_EXPLORED`; `CURRENT` = `vision.is_visible`, `NO_VISION`), and the recipe's terrain rule (`clear_land`, `clear_ground`, `land_or_water`: static passability only, never revealing hidden units); `OWN_STRUCTURE`: entity owned, ACTIVE, def in the recipe's list, `structure_online` (`BAD_TARGET`/`WRONG_KIND`); `OWN_UNIT`: owned and tag-matching (no current power uses it; kept for extension).

**Activation** (`handle_command`, codes 140–141, re-runs the validation, then): `spend(cost)` -> `slot.ready_tick = tick + cooldown_ticks` (cooldown starts now) -> `uses++` -> `EVT_POWER_ACTIVATED(pid, slot, def_idx, x, y, angle)` -> `SimStrategicEffects.start(...)` dispatches on `EK_*`. `EVT_POWER_READY(pid, slot)` when the cooldown expires (polled each tick over 8×3 slots).

**Effect scheduler.** `_sched: Array[SimScheduled]` sorted by `(tick, seq)` (binary insertion after equal ticks; `seq` is a monotonic counter, so ordering is total). Stage 4 pops while `front.tick <= now` and runs `SimStrategicEffects.run(rec)` / `SimSuperweapons.run(rec)`. All randomness (shell scatter, decoy positions, capsule landing spots) is drawn **at activation** from `world.rng` in a fixed loop order and stored in the records, so execution never touches the RNG (stable under replays). Hard cap 256 pending records (asserted).

**Warning zones.** Any effect that specifies a delay before hostile effect (`superweapons`, Counterbattery Mission, Tremor Barrage, Counterlaunch Plot, Wideband Scan's scan warning) creates a `SimWarning` in `world.strategic` (queryable state, not just an event). It is **visible to affected players and cannot be hidden by fog or decoys**: `affected_mask` = bit of every player that (a) is the owner, (b) is on the owner's team, or (c) owns at least one entity inside the zone expanded by 3 cells, recomputed every 10 ticks during `WARNING`. The view draws zone geometry for local players whose bit is set, regardless of fog; audio may play a global "strategic launch detected" for all players from `EVT_WARNING` (no position needed). Decoy entities never affect it.

**Reconnaissance rule.** Powers whose kind is `REVEAL_ZONE`, `RECON_SUMMON`, plus the two artillery fire-log powers (`ae.counterbattery_solution`, `sap.counterlaunch_plot`) use `VR_NONE` (any map location); the two counter-battery powers are treated as reconnaissance because their own text says they reveal/mark fired-from positions (ASSUMPTION flagged in section 12). Decoy powers ("scouted") use `VR_EXPLORED`. Everything else uses `VR_CURRENT`.

### 5.17 Implementation recipe per effect kind (`SimStrategicEffects`)

**Naming note.** The primitive names below are *logical operations*; the names actually published by the abilities/combat/data specs are mapped in the reconciliation matrix 12.1 (rows M3–M11), and the reconciler may collapse `SimStrategicEffects` into `SimPowerFx.apply` without changing any recipe. Common primitives (all `ASSUMPTION` on other domains; requests in section 13): `world.spatial.query_circle(x, y, r, out: PackedInt32Array)` (ascending entity id), `world.abilities.apply_timed_effect(id, fx_idx, dur_ticks, src_pid, src_key)`, `world.zones.create(...)`, `world.vision.add_reveal(...)`, `world.spawn_summon(def_id, owner, x, y, flags) -> int`, `world.combat.fire_log_query(...)`, `emit_packet`. `src_key = p_idx` makes "identical sources never stack": the ability domain must refresh instead of stack when the same `src_key` is applied to the same target.

**EK_BUFF (19 powers)** — snapshot buff. `ids = query_circle(x, y, r)`; for each id (cap 256): skip unless same team as the caster ("support buffs affect friendlies unless the text says otherwise"), alive, and matching the recipe `select` (a `PackedByteArray` over def indices compiled by GameData from tag lists: `entity_kinds/all_tags/any_tags/exclude_tags`, plus flags `not_moving`, `no_summon`); `apply_timed_effect(id, fx, dur, pid, p_idx)`. Recipes with a second phase (Capacitor Discharge, Software Surge) store the id list in a `SK_APPLY_FX` record at `tick + dur` that applies the penalty effect to those ids still alive. Effects that end on an event (`end_on = MOVE | FIRE | DETECTED`; Silent Watch, Armored Overwatch, Field Refurbishment) end permanently for that unit. **Snapshot vs zone (decision):** all 19 use *snapshot at activation* (effect follows the unit, entering units do not gain it); this is stated explicitly by Open Corridor ("must be in the zone when activated") and is the cheapest, most predictable reading of the others; `row.mode = "zone"` is reserved for a future zone-aura variant.

**EK_WINDOW (6)** — no target. Writes `knob_temp/knob_until` for the knob list of the recipe (5.18 table: Mobilization -> both PROD_RATE knobs and `rates_dirty`; Treaty -> `RELAY_DAMAGE_BP`; Reserve Bandwidth -> `CMD_RADIUS_CELLS` (ADD +3); Central Priority -> `CMD_DAMAGE_BP`; Joint Landing -> `JOINT_LANDING`; Recovery Priority -> `SALVAGE_TICKS` (MIN 60) + `RECOVERY_PRIORITY`) and schedules `SK_WINDOW_END` (clears `knob_until`, `rates_dirty`). Recovery Priority also applies the +25 % movement effect to every living Engineer/Reclaimer/River Warden and, through `on_unit_spawned`, to matching units created during the window.

**EK_STRUCT_BUFF (1)** — Rapid Turnaround: target must be an owned ACTIVE online Airfield; sets `rearm_boost_bp = 15000`, `rearm_boost_until = tick + 400`. It never touches the production queue (bible: "does not accelerate aircraft production").

**EK_REVEAL_ZONE (3)** — `handle = world.vision.add_reveal(team_mask, SHAPE_DISC, x, y, 0, 0, r, until_tick, detect, 0)`; the vision domain expires it. Wideband Scan first creates a `WK_SCAN` `SimWarning` (visible to affected players) and schedules `SK_REVEAL_START` at `+40`; Survey Network additionally emits `EVT_WRECKS_HIGHLIGHTED(pid, x, y, r, until)`. Long Watch and Survey Network do not detect camouflage (`detect = false`).

**EK_RECON_SUMMON (4)** — spawn a shootable air/hover summon (`summons.json`). UAV / Survey Drone: spawned 16 cells behind the target on the ray from the owner's nearest ACTIVE HQ (map centre if none), flies straight to the target (`TS_FLY_TO_HOVER`), then hovers (orbit radius 1 cell); its own sight/detector radius (7 / 6 cells) provides the reveal, `expire_tick = arrive_tick + duration`; shot down -> reveal ends. Recon Balloon: spawned in place (`TS_HOVER`), 400 ticks. Maritime Patrol: aircraft flies the 20-cell line start -> end (`TS_FLY_TO_HOVER` then orbit at the end) and a capsule reveal (length 20, width 6, `detect = true`) is bound to the aircraft (`bind_ent`): destroyed aircraft = reveal removed.

**EK_REPAIR (6)** — free repair, no credit spend. *Zone variants* (Floating Workshop pontoon, Mobile Workshop drone station, Field Repair Drop, Expeditionary Workshop, Repair Swarm): `zid = world.zones.create(ZONE_REPAIR, pid, x, y, r, until_tick, rate_bp_per_s, target_class, GROUP_REPAIR_STATION, bind_ent)`. The zone heals each valid friendly target by `max_hp * rate / (10000*TPS)` per tick with exact carry; **stations never stack and never heal themselves**: per target per tick only the station with the highest rate applies (ties lowest zone id). The Mobile Workshop is a destructible entity (`summon.repair_station`, zone bound to it: entity dead = zone ends); the Field Repair Drop and Expeditionary Workshop spawn a shootable cargo aircraft (`TS_FLY_TO_DROP`) and schedule `SK_DROP_PAYLOAD` on arrival — if the aircraft is dead by then, no zone; the pontoon is an indestructible marker. Repair Swarm targets friendly *unmanned land units and structures* (never `EF_NO_REPAIR` engines). *Snapshot variant* (Field Refurbishment): BUFF-style timed effect `heal_bp_per_s = 300` for 200 ticks with `no_fire` and `end_on = MOVE` on friendly land vehicles in the zone.

**EK_SMOKE (2 + Broken Contact)** — `world.zones.create(ZONE_SMOKE, ...)` with shape `DISC` (Dust Screen r6, 240 ticks) or `CAPSULE(x1,y1,x2,y2,half_width)` (Concealed Crossing: 16 x 4 cells -> segment length 12, half-width 2, so total length 16, 240 ticks), `params.direct_fire_reduction_bp = 3000`. Two-sided: all ground units inside, friendly or enemy, take 30 % less **direct-fire** weapon damage; artillery, area blasts and strategic packets ignore it (`PKT_IGNORE_SMOKE`; Helios "smoke does not" reduce). Broken Contact creates up to 8 disc zones r3 for 120 ticks at the units' *initial positions*, de-duplicated by 3x3-cell buckets in ascending bucket-index order.

**EK_DECOY (3)** — `for i in range(N)`: draw `angle = rng.range_i(0, 4095)` and `dist = rng.range_i(0, r_scatter)` (`ASSUMPTION(sim-core)`: `SimRng.range_i(lo, hi)` inclusive, ints only) (up to 6 tries to find a legal cell for the decoy def's layer/terrain), spawn `summon.decoy_*` with `EF_DECOY | EF_TEMPORARY | EF_NO_SALVAGE | EF_NO_CAPTURE | EF_NO_REPAIR`, 1 hp, no weapons, no collision, `expire_tick = tick + dur`, visual = the roster's model for that role (`summons.json.decoy_models`). Decoys never enter `struct_count`, power sums, unit cap, victory checks or salvage; detectors within their radius mark them identified (visual/AI-visible via `vision.is_identified`). The False Front decoy Radar is a structure-like temp entity without a footprint stamp (non-blocking).

**EK_BOMBARD (3)** — creates a `SimWarning` (kind `POWER`) and schedules `SK_PACKET` records at absolute impact ticks with pre-drawn positions; each packet is a `PKT_SHELL` (ordinary artillery shell: a hostile Trident zone destroys it for 1 charge) with `src` off-map. Details per power in 5.18. Counterlaunch Plot additionally selects up to 8 enemy artillery via `fire_log_query` at activation and freezes their positions.

**EK_MARK (1)** — Counterbattery Solution: `fire_log_query(enemy teams, x, y, r=9 cells, since = tick-160)` -> up to 16 live artillery ids; `vision.add_reveal_entity(team_mask, id, tick+240)` and `apply_timed_effect(id, fx.marked, 240, pid, p_idx)` where `fx.marked` = "takes +1500 bp damage from ground weapons of the marking team".

### 5.18 Classification of all 48 support powers

Ticks = seconds x 20. `Cost`/`CD` from the bible. Vision: `any` = `VR_NONE`, `scouted` = `VR_EXPLORED`, blank = `VR_CURRENT`. Radii in cells. `fx.*` are temp-effect ids compiled from `powers.json`. "sel" is the selector; "friendly" means same team as the caster.

| # | Power id | T | Cost | CD | EK | Target / vision | Parameters and timeline |
|---|---|---|---|---|---|---|---|
| 1 | `power.napc.uav_sweep` | 2 | 500 | 1800 | RECON_SUMMON | POINT any | UAV (`summon.uav`) sight+detect r7; 240 ticks after arrival |
| 2 | `power.napc.field_repair_drop` | 3 | 900 | 3600 | REPAIR | POINT | cargo aircraft delivers zone: r5, 200 bp/s, 200 ticks, friendly `land_vehicle` |
| 3 | `power.napc.combined_arms_window` | 2 | 900 | 3600 | BUFF | AREA r6 | sel friendly combat infantry / land vehicles / aircraft (no ships, structures); `weapon_damage +1000`; 300 ticks |
| 4 | `power.napc.rapid_turnaround` | 2 | 700 | 3000 | STRUCT_BUFF | OWN_STRUCTURE (Airfield) | rearm boost 15000 bp for 400 ticks |
| 5 | `power.napc.floating_workshop` | 2 | 800 | 3600 | REPAIR | POINT, land or water | pontoon zone r5, 150 bp/s, 400 ticks, friendly land vehicles and ships |
| 6 | `power.napc.coordinated_advance` | 2 | 600 | 3000 | BUFF | AREA r6 | sel friendly infantry; `movement +2500`, `suppression_immune`, clear existing suppression; 240 ticks |
| 7 | `power.nec.survey_drone` | 2 | 450 | 1800 | RECON_SUMMON | POINT any | drone reveal+detect r6; 300 ticks |
| 8 | `power.nec.counterbattery_mission` | 3 | 1100 | 3600 | BOMBARD | AREA r4 | warning 100; 6 shells at warning_end + {0,16,32,48,64,80}; shell 260 dmg, r1.5, edge 3000 bp, struct x1.5 |
| 9 | `power.nec.treaty_coordination` | 2 | 800 | 3600 | WINDOW | none | `RELAY_DAMAGE_BP` temp 1500 for 400 ticks |
| 10 | `power.nec.silent_watch` | 2 | 600 | 3000 | BUFF | AREA r6 | sel friendly ground units not moving; `camouflage` up to 300 ticks; `end_on MOVE\|FIRE\|DETECTED` |
| 11 | `power.nec.armored_overwatch` | 2 | 900 | 3600 | BUFF | AREA r6 | sel friendly tanks not moving; `weapon_range +1000`; 300 ticks; `end_on MOVE` |
| 12 | `power.nec.emergency_earthworks` | 2 | 700 | 3600 | BUFF | AREA r5 | sel friendly infantry + `defense` structures (not vehicles); explosive resistance +2000; 300 ticks |
| 13 | `power.olm.dust_screen` | 2 | 400 | 1800 | SMOKE | AREA r6 | disc r6, 240 ticks, direct-fire reduction 3000 bp, two-sided |
| 14 | `power.olm.mobile_workshop` | 3 | 900 | 3600 | REPAIR | POINT clear ground | destructible station (hp 400) + zone r5, 200 bp/s, 300 ticks, friendly land vehicles |
| 15 | `power.olm.open_corridor` | 2 | 650 | 3000 | BUFF | AREA r6 | sel friendly land vehicles; `movement +2500`; 240 ticks (snapshot) |
| 16 | `power.olm.capacitor_discharge` | 2 | 800 | 3600 | BUFF+penalty | AREA r6 | sel friendly units with thermal-beam weapons + Sunwall Projectors; `weapon_damage +2000` 200 ticks, then `weapons_disabled` 80 ticks |
| 17 | `power.olm.false_convoy` | 2 | 500 | 2400 | DECOY | POINT scouted, clear land | 4 decoy light vehicles, scatter r3, 500 ticks |
| 18 | `power.olm.straits_crossfire` | 2 | 800 | 3600 | BUFF | AREA r6 | sel friendly infantry + ships; `weapon_range +1000`, `sight +2000`; 300 ticks |
| 19 | `power.def.mobilization_order` | 2 | 700 | 3600 | WINDOW | none | Barracks + Factory `PROD_RATE` temp 12500 for 400 ticks; costs unchanged |
| 20 | `power.def.tremor_barrage` | 3 | 1300 | 4200 | BOMBARD | AREA r5 | warning 120; 4 waves at warning_end + {0,53,107,160}; 5 shells per wave in r5; shell 180, r1.5, edge 3000, struct x1.2 |
| 21 | `power.def.redundant_orders` | 2 | 650 | 3600 | BUFF | AREA r6 | sel friendly land vehicles; `emp_immune` (weapon-disabling EMP; not damage); 200 ticks |
| 22 | `power.def.steel_advance` | 2 | 900 | 3600 | BUFF | AREA r6 | sel friendly land vehicles; damage taken -2000 bp (still under the 50 % cap) and `movement -2000`; 240 ticks |
| 23 | `power.def.transit_priority` | 2 | 600 | 3000 | BUFF | AREA r7 | sel friendly Collectors + ground transports; `movement +3500`; 300 ticks; no harvest/unload change |
| 24 | `power.def.false_front` | 2 | 500 | 3000 | DECOY | AREA r6 scouted | 1 decoy Radar + 3 decoy tanks, 600 ticks, non-blocking |
| 25 | `power.pd.maritime_patrol` | 2 | 500 | 1800 | RECON_SUMMON | LINE any (20 x 6) | patrol aircraft flies line; capsule reveal+detect 240 ticks bound to it; land and water |
| 26 | `power.pd.expeditionary_workshop` | 3 | 900 | 3600 | REPAIR | POINT, land or water | aircraft delivers zone r5, 150 bp/s, 400 ticks, land vehicles + ships |
| 27 | `power.pd.joint_landing` | 2 | 700 | 3600 | WINDOW | none | `JOINT_LANDING` temp 1 for 300 ticks; transports domain applies `fx.pd.landing` (-2000 damage taken, 120 ticks) to units disembarking; per-unit anti-refresh |
| 28 | `power.pd.long_watch` | 2 | 600 | 3000 | REVEAL_ZONE | AREA r7 any | 360 ticks, terrain + ordinary units, no camouflage detection |
| 29 | `power.pd.feint_landing` | 2 | 500 | 2400 | DECOY | POINT scouted, land or water | 3 decoy transports (cannot carry), 500 ticks |
| 30 | `power.pd.precision_window` | 2 | 900 | 3600 | BUFF | AREA r6 | sel friendly combat aircraft + ships; `weapon_damage +2000`; 200 ticks; no sight/survivability change |
| 31 | `power.han.wideband_scan` | 2 | 400 | 1800 | REVEAL_ZONE | AREA r7 any | `WK_SCAN` warning 40 ticks, then reveal+detect 120 ticks |
| 32 | `power.han.software_surge` | 3 | 900 | 3600 | BUFF+penalty | AREA r6 | sel friendly unmanned combat units (not summons); `reload_interval -2500` 240 ticks, then `weapons_disabled` 60 ticks |
| 33 | `power.han.reserve_bandwidth` | 2 | 650 | 3000 | WINDOW | none | `CMD_RADIUS_CELLS` temp +3 for 400 ticks; damage bonus unchanged |
| 34 | `power.han.central_priority` | 2 | 800 | 3600 | WINDOW | none | `CMD_DAMAGE_BP` temp 2000 for 300 ticks |
| 35 | `power.han.broken_contact` | 2 | 650 | 3000 | BUFF+SMOKE | AREA r6 | sel friendly ground combat units; `movement +2000` 200 ticks; up to 8 smoke discs r3, 120 ticks, at initial positions |
| 36 | `power.han.repair_swarm` | 2 | 700 | 3600 | REPAIR | AREA r5 | free zone 200 bp/s, 200 ticks, friendly unmanned land units + structures; no credits |
| 37 | `power.ae.survey_network` | 2 | 400 | 1800 | REVEAL_ZONE | AREA r7 any | 240 ticks, no camouflage detection; highlights salvageable wrecks |
| 38 | `power.ae.field_refurbishment` | 3 | 1000 | 3600 | REPAIR (snapshot) | AREA r6 | sel friendly land vehicles; `heal 300 bp/s`, `no_fire`, `end_on MOVE`; 200 ticks |
| 39 | `power.ae.recovery_priority` | 2 | 600 | 3000 | WINDOW | none | `SALVAGE_TICKS` temp 60 + `movement +2500` on Engineers/Reclaimers/Wardens; 400 ticks; payout unchanged |
| 40 | `power.ae.civil_defense_net` | 2 | 600 | 3000 | BUFF | AREA r6 | sel friendly infantry; `sight +2500`, `suppression_immune`; 300 ticks |
| 41 | `power.ae.concealed_crossing` | 2 | 600 | 3000 | SMOKE | LINE (16 x 4), land or water | capsule smoke zone 240 ticks, two-sided, protects either side |
| 42 | `power.ae.counterbattery_solution` | 2 | 900 | 3600 | MARK | AREA r9 any (fire-log) | enemy artillery that fired in the last 160 ticks: reveal 240 ticks + `fx.marked` (+1500 bp damage taken from friendly ground weapons) 240 ticks |
| 43 | `power.sap.recon_balloon` | 2 | 450 | 1800 | RECON_SUMMON | POINT any, clear terrain | balloon hp 150, sight+detect r6, 400 ticks |
| 44 | `power.sap.emergency_fortification` | 3 | 900 | 3600 | BUFF | AREA r6 | sel friendly `defense` structures + Barracks/Factory/Airfield/Dock (not `superweapon`); damage taken -2500; 300 ticks; EMP not prevented |
| 45 | `power.sap.protected_advance` | 2 | 750 | 3600 | BUFF | AREA r6 | sel friendly infantry + land vehicles; damage taken -1500; 240 ticks; no speed bonus |
| 46 | `power.sap.assault_coordination` | 2 | 900 | 3600 | BUFF | AREA r6 | sel friendly tanks; `reload_interval -1500`, `sight +1500`; 240 ticks |
| 47 | `power.sap.mobile_reserve` | 2 | 650 | 3000 | BUFF | AREA r7 | sel friendly ground transports; `movement +3000`, `unload_while_moving` (half speed); 300 ticks |
| 48 | `power.sap.counterlaunch_plot` | 2 | 800 | 3600 | BOMBARD+MARK | AREA r8 any (fire-log) | mark <= 8 enemy artillery that fired in the last 160 ticks (positions frozen); warning 100; one shell per mark at warning_end; 300 dmg, r1.5 |

Counts by kind: REVEAL_ZONE 3, RECON_SUMMON 4, BUFF 19 (incl. two penalty-phase and Broken Contact), WINDOW 6, STRUCT_BUFF 1, REPAIR 6, SMOKE 2, DECOY 3, BOMBARD 3, MARK 1 = **48**. Number of powers per roster is always 3 (asserted at `init_player`).

### 5.19 Superweapon framework (`rule.combat.superweapon_control`)

**Slot state machine** (`SimPowerSlot`, slot 3, per player; `T` = activation tick):

| State | Enter | Per tick (stage 4b) | Exit |
|---|---|---|---|
| `SW_NONE` | no ACTIVE launcher | nothing | launcher becomes ACTIVE -> `CHARGING`, `charge = 0`, `launcher_id = id` ("starts empty") |
| `SW_CHARGING` | launcher ACTIVE, or immediately after an activation | if `charge_ok(pid)`: `charge += 1`, where `charge_ok = powered(pid) ∧ radar_present ∧ lab_present ∧ launcher ACTIVE ∧ launcher.shutdown_until <= tick` | `charge >= recharge_ticks` -> `READY`, `EVT_SW_READY` |
| `SW_READY` | fully charged | nothing (one stored charge, no stockpiling; `charge` stays at max) | activation -> `CHARGING` with `charge = 0`; launcher lost -> `NONE` (charge lost) |

`radar_present` / `lab_present` mean an ACTIVE, non-temporary Radar / Laboratory exists ("intact"; EMP or shortage of *those* buildings does not stop charging, only the player-level `powered` does — the bible pairs "enough power" with "intact Radar/Laboratory"). Recharge ticks: 480 s = **9600** (Atlas, Helios, Perun, Tempest, Dragonfall, Horizon), Aurora 420 s = **8400**, Trident 360 s = **7200**. **Shortage pauses charging** (`powered` false) and only charging. Cost: **no credits** to fire (the 5,000-credit launcher is the price); launcher draws **-200 power** continuously once ACTIVE.

**Activation** (`CMD_LAUNCH_SUPERWEAPON`, slot 3) validates in order: `FEATURE_OFF`, `NO_LAUNCHER` (slot NONE), `NOT_CHARGED` (state != READY), launcher ACTIVE and not shut down (`NO_POWER`), Radar/Laboratory present (`PREREQ`), target inside the map and **explored** (`NOT_EXPLORED`; superweapons need no current vision), recipe geometry legal (line length/angle for LINE targets). Note: activation is allowed during a shortage (only recharge pauses) and while another of the same player's attacks is still executing. On success, **the full recharge starts now**: `sw_state = CHARGING`, `charge = 0`, `last_activation_tick = T`. A `SimWarning{kind=SUPER}` is created with `exec_tick = T + warning_ticks` (200 / 160 Aurora / 120 Trident) and `EVT_WARNING` is emitted; `slot.pending_attack = warning.id`.

**Cancellation.** While `phase == WARNING`, if the launcher is destroyed (`on_structure_lost`), sold (blocked by `LOCKED`, but handled anyway), captured (impossible: not capturable), or starts an EMP shutdown (`on_shutdown_started`, also re-checked every tick), the attack becomes `CANCELLED` and **no charge is refunded** (the slot stays in `CHARGING` from the activation, or `NONE` if the launcher is gone). `EVT_SW_CANCELLED(pid, w_idx, cause)` with `cause` `1 destroyed / 2 shutdown / 3 sold`. After `exec_tick` (phase `EXEC`) launcher loss or shortage no longer cancels ("a surviving orbital magazine"; "an ordinary power shortage after activation does not cancel it"). Rebuilding a launcher starts a fresh empty charge. `Maximum one strategic structure per player` is enforced at enqueue and placement (5.3).

**Warning visibility.** See 5.16: `SimWarning.affected_mask`; the zone (circle, line capsule, or Atlas rod circles) is drawn for those players regardless of fog. Trident's zone stays visible to everyone after activation. Decoys cannot hide it and cannot falsify the countdown (bible `superweapon_note`).

### 5.20 Impact packets and interception hooks (`rule.combat.interception_and_strategic_packets`)

**Naming note.** The combat spec already provides `SimProjectiles.spawn_remote` / `spawn_sweep` (strikes with a delay, sweeps, off-map arcs) and performs the Trident packet reduction itself at detonation (matrix rows M5, M7); the *behaviour* below is normative and `emit_packet` is the logical choke point, which the reconciler may implement as those calls (recommended).

`SimStrategicSystem.emit_packet(world, pk)` is the **only** way strategic damage enters combat:

1. If `pk.flags & (PKT_INTERCEPTABLE | PKT_SHELL)` and not `(PKT_BEAM | PKT_EMP)`: `world.zones.intercept_packet(pk)`. It scans interception zones in ascending zone id, first match wins, only zones **hostile** to `pk.src_pid`'s team that contain `(pk.x, pk.y)` and do **not** contain the source (`src_x/src_y`; off-map counts as outside — "weapons fired from inside it bypass", "units entering the zone bypass"): `PKT_SHELL` with `charges >= 1` -> `charges -= 1`, `pk.damage = 0` (destroyed); `PKT_INTERCEPTABLE` with `charges >= 8` -> `charges -= 8`, `pk.pre_resist_bp += 5000`; fewer than 8 charges cannot reduce a strategic packet, and a packet is never cancelled. A zone with 0 charges is removed.
2. If `pk.damage > 0`: `world.combat.apply_area_damage(pk)`. Expected combat behaviour (`ASSUMPTION(combat)`, requested in section 13): entities whose team bit is set in `team_mask` and whose layer bit is set in `layer_mask` within `radius` (structures: distance to the nearest point of the footprint); `frac_bp = 10000 - (10000 - falloff_edge_bp) * d / radius`; `dmg = damage * frac_bp / 10000`; structures also `* struct_mult_bp / 10000`; then `resist = min(5000, target_resist(dmg_type) + pre_resist_bp)` and `dmg = dmg * (10000 - resist) / 10000` — so Trident's 50 % and a target's own resistances **share the single 50 % cap** ("all reductions still obey the overall 50 % resistance cap"). Smoke never applies (`PKT_IGNORE_SMOKE`).
3. `EVT_SW_IMPACT(kind, x, y, radius)` for VFX/audio (suppressed for per-hit Tempest packets).

**Who cannot intercept.** Strategic packets and support-power shells are instantaneous packets, not projectile entities: ordinary AA, Ural / Arjun active protection and every other unit-based interceptor cannot target them (bible: "Ordinary AA cannot intercept strategic attacks except the explicitly shootable Tempest drones"; Ural "cannot intercept shells, beams or superweapons"). Only a Trident zone interacts with packets, and the Tempest drones are ordinary shootable air entities.

Which bible items are packets: each Atlas rod, Perun core and ring, Horizon impact, Tempest drone hit and Dragonfall engine shot (`PKT_INTERCEPTABLE`); Helios pulses (`PKT_BEAM`) and the Aurora burst (`PKT_EMP`) bypass Trident; support-power bombardment shells are `PKT_SHELL`. **Worked examples:** Atlas (3 rods) into a fresh Trident (24 charges): all three rods lose 50 % of their damage and the zone is emptied; Perun (2 packets) leaves 8 charges, which then absorb one more strategic packet or 8 ordinary shells; a Tremor Barrage (20 shells) into a fresh Trident is stopped by 20 charges and leaves 4 (no strategic packet reducible afterwards).

### 5.21 Execution timelines of the eight superweapons

`T` = activation tick, `X = T + warning_ticks` (execution start). Geometry in cells; sub-cells = cells * 1024. Damage values are **initial tuning targets** in `superweapons.json` (balance may change them; the shapes, radii, counts and timings below are bible-fixed). All positions are fixed at activation.

| # | Superweapon (launcher) | Recharge / warning | Target | Execution |
|---|---|---|---|---|
| 1 | **Atlas Kinetic Array** (`superweapon.napc.atlas_kinetic_array`; launcher `structure.napc.atlas_kinetic_array`) | 9600 / 200 | LINE, length 6 (default angle 0 = east): points at line offsets **0, -3, +3** cells | Rod packets at `X`, `X+4`, `X+8` (centre, then -3, then +3). Each: `kinetic`, 1400 at centre, radius **2.0**, linear falloff to 0 at the edge, structures x1.5, `INTERCEPTABLE`. With 3-cell spacing and 2-cell radius adjacent circles overlap by 1 cell (see risk R4): the lens between two rods takes both rods at 25 % + 25 %, i.e. about 50 % of one full hit, which is the "gap" the counterplay text refers to. |
| 2 | **Aurora Microwave Array** (`superweapon.nec.aurora_microwave_array`; launcher `structure.nec.aurora_microwave_array`) | 8400 / 160 | AREA r8 | One burst at `X`: `EMP` packet 80 flat, `ENEMY_ONLY` (allies and owner untouched). Effects on enemy entities in the disc: land vehicles, ships and aircraft `fx.aurora.weapons_off` 160 ticks (no crash, movement kept); enemy structures with `power_class != NONE` shut down 360 ticks (Radar/defense duration x `K_EMP_RECOVERY_STRUCT_BP`, unmanned units' x `K_EMP_RECOVERY_UNMANNED_BP`, both applied by abilities); infantry unaffected (ASSUMPTION: ships count as "vehicles", as in the combat and abilities specs; the bible text only names vehicles and aircraft). A shut-down enemy launcher cancels its own warning (5.19). Bypasses Trident. |
| 3 | **Helios Reflector** (`superweapon.olm.helios_reflector`; launcher `structure.olm.helios_reflector`) | 9600 / 200 | LINE, length 16, width 3 | 60 self-rescheduling pulses at `X + 4k`, `k = 0..59`; pulse `k` is a disc of radius **1.5** centred at `start + dir * 16 * (2k+1)/120` cells; each 140 thermal-beam damage (x `thermal_damage_bp`/10000: Saudi +15 % -> 161), flat, layers ground + surface water + structures (not aircraft), all teams (friendly fire on), `BEAM` (bypasses Trident, ignores smoke). A unit on the centreline is inside a pulse disc for about 2.25 s (about 11 pulses, about 1,540 raw damage); it cannot track after commit. |
| 4 | **Perun Missile Complex** (`superweapon.def.perun_missile_complex`; launcher `structure.def.perun_missile_complex`) | 9600 / 200 | AREA (point; UI shows r7) | `X`: core packet `explosive` 2200, radius **3**, edge 4000 bp, structures x2.0. `X+6`: ring packet 500 over the **annulus between 3 and 7 cells** (the core disc is excluded, as in combat's `wh.perun_ring`), edge 2000 bp, x1.0. Both `INTERCEPTABLE`. No lingering zone. |
| 5 | **Tempest Swarm Hub** (`superweapon.pd.tempest_swarm_hub`; launcher `structure.pd.tempest_swarm_hub`) | 9600 / 200 | AREA r6; warning also carries the approach line launcher -> zone (`x2,y2` = launcher) | At `X`: 24 `summon.tempest_drone` spawn around the launcher (angle `i*4096/24`, radius 1 cell), each ordered to a spread point in the zone; `expire_tick = X + flight + 400` (flight = `ceil(dist/speed)`; **20 s of attack time after arrival**). Brain `SWARM_ZONE`: enemies only, ground + surface targets only, leash radius 8; drone: air layer, hp 60, speed 9 cells/s, weapon 70 dmg, radius 0.75, reload 24 ticks, range 2 cells; **each hit is one `INTERCEPTABLE` packet** with `src` = drone. Flags `EF_TEMPORARY`, `SUMMON`, `NO_SALVAGE`, `NO_VISION_GRANT`, `NO_CAPTURE`. Shootable by AA; no wreck. Maximum raw aggregate about 24 x 16.7 shots x 70 = 28,000. |
| 6 | **Dragonfall Field Foundry** (`superweapon.han.dragonfall_field_foundry`; launcher `structure.han.dragonfall_field_foundry`) | 9600 / 200 | AREA r5 | At `X`: 3 `summon.dragonfall_capsule` land at pre-drawn points (min separation 2 cells, land, up to 8 tries each; fallback fixed offsets); capsule: hp 400, immobile, attackable. At `X+100` (5 s): each surviving capsule is replaced by `summon.dragonfall_engine` (hp 2500, speed 1.0 cells/s, cannon 320 dmg, radius 1.2, reload 40 ticks, range 6 cells, structures x2.0, `INTERCEPTABLE` shots), `expire_tick = X+100+1200` (60 s), then it is removed silently. Brain `ASSAULT_STRUCTURES`: every 20 ticks target the nearest enemy non-temporary structure (ties lowest id), enemies only. Flags: `NO_REPAIR`, `NO_CAPTURE`, `NO_SALVAGE`, `SUMMON`, `TEMPORARY`, `NO_HARVEST`, `NO_COMMAND_BUFF`. Foundry destroyed during the warning: nothing lands. |
| 7 | **Horizon Mass Driver** (`superweapon.ae.horizon_mass_driver`; launcher `structure.ae.horizon_mass_driver`) | 9600 / 200 | LINE, length 10 | Centres at line offsets -5, 0, +5 (start -> end). Impacts at `X`, `X+90`, `X+180` (9 s). Each: `kinetic` 1100, radius **3**, edge 3000 bp, structures x1.3, `INTERCEPTABLE`, ground + water + structures. If the impact cell is land: `ZONE_DEBRIS` r3 for 400 ticks from that impact: all land vehicles (friend and foe) -35 % speed, `blocks_construction` (also blocks MCV deploy); never blocks movement, never edits the map. |
| 8 | **Trident Interception Array** (`superweapon.sap.trident_interception_array`; launcher `structure.sap.trident_interception_array`) | 7200 / 120 | AREA r6 | At `X`: `ZONE_INTERCEPT` r6 for 500 ticks with 24 charges, `per_packet = 8`, `reduction_bp = 5000`; ends early at 0 charges. Bypassed by beams, bullets, EMP, units entering, and weapons fired from inside; ordinary hostile missiles/shells crossing the boundary cost 1 charge and are destroyed. The zone is visible to all players. |

`SimSuperweapons.danger_fraction_bp(w: SimWarning, x: int, y: int, t: int) -> int` returns a 0–10000 estimate of the fraction of one full hit that a unit standing at `(x, y)` would receive if it stayed until tick `t` (AI dodge helper; uses the geometry/timings above and no RNG).

### 5.22 AI-readable state and queries

The AI (host-side, floats allowed) reads only: `SimStrategicSystem.slot_info(pid, slot)` (power id, `ready_tick`, `cooldown_left_ticks`, superweapon `sw_state`, `charge`/`recharge_ticks` -> charge percent, `launcher_id`), `warnings_affecting(pid)` / `attacks_pending_against(pid)` (geometry, `exec_tick`, `end_tick`, owner, kind, `affected_mask`), `can_activate(...)` (reason codes), `SimPlayerEcon` public fields (credits, power supply/demand/state, reserve, queues), `SimEconomySystem` queries (income per minute, refineries, collectors, deposit stock/explored, wrecks, capturables), `SimProductionSystem` catalog queries and `SimPlacement.find_site`. It acts only through commands (`CMD_*`) and ordinary orders (`ORD_HARVEST`, `ORD_CAPTURE`, ...). Every rejection reason is an enumerated `RSN_*`, so the AI can react without parsing strings.

---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

`ASSUMPTION(sim-core)`: the sim receives commands as `PackedInt32Array [type, args...]` (net.md 5.5) parsed into a `SimCommand` view with `type`, `pid` (stamped by the host), `ids: PackedInt32Array` for unit/structure-list commands and `args: PackedInt32Array`; events are `SimEvent{type, x, y, a..f}` ints (**request: six payload ints plus x,y**; coordinate pairs listed inside the field lists below (`c=x, d=y`, etc.) may be carried in `SimEvent.x/.y` instead; the order of the remaining fields is unchanged). This domain's blocks: commands **120–149** and events **300–499** (see 6.1 for the codes already taken by the other published specs). Every command is re-validated on execution (the network delivers commands from untrusted peers): `cmd.pid` must equal the authenticated sender, all `ids` must be owned live entities of `cmd.pid`, all indices in range. A rejected command changes nothing and emits `EVT_CMD_REJECTED`.

### 6.1 Commands

Codes **120–149** are this domain's block (core 1–99, combat 40–47, abilities 100–119 and net 240–255 are taken by the concurrently published specs). The wire form is the sim-core / net convention `PackedInt32Array [type, args...]` (net.md 5.5: `type` 0..255, no pid inside; the host stamps it); a leading `ids` list is encoded by the sim-core unit-list convention. **Only the logical field order below is normative**; `SimCmd` (sim-core) owns the byte layout. Command names follow the AI spec's intent names (`BUILD_START`, `TRAIN`, ...), which the AI, UI and net layers already use.

| Code | Name | Handler | `ids` | args (in order) | Semantics |
|---|---|---|---|---|---|
| 120 | `CMD_BUILD_START` | production | – | `s_idx`, `count` 1–5 | Append `count` copies to the construction queue (all-or-nothing). |
| 121 | `CMD_BUILD_CANCEL` | production | – | `queue_index` (0 = head, also a READY item) | Remove; refund `cq_paid` if head. |
| 122 | `CMD_BUILD_HOLD` | production | – | `hold` 1 / 0 | Player hold / resume of the head item. |
| 123 | `CMD_BUILD_PLACE` | production | – | `s_idx`, `cx`, `cy`, `rot` 0–3 | Place the READY head (5.3). |
| 124 | `CMD_TRAIN` | production | – | `producer_id` (0 = auto), `u_idx`, `count` 1–5 | Enqueue units at a producer. |
| 125 | `CMD_TRAIN_CANCEL` | production | – | `producer_id`, `queue_index` | Cancel one item; the head refunds `head_paid`. |
| 126 | `CMD_QUEUE_HOLD` | production | producer ids | `hold` 1 / 0 | Hold / resume whole unit queues. |
| 127 | `CMD_SET_RALLY` | production | producer ids | `x` (sub-cells), `y`, `target` (entity id, or `-(deposit_idx+1)` = harvest that deposit), `flags` (1 = clear) | Rally point. |
| 128 | `CMD_SET_PRIMARY` | production | – | `producer_id` | Primary building for its kind. |
| 129 | `CMD_RESEARCH` | production | – | `r_idx` | Enqueue research. |
| 130 | `CMD_RESEARCH_CANCEL` | production | – | `queue_index` | Refund `rq_paid` if head. |
| 131 | `CMD_RESEARCH_HOLD` | production | – | `hold` 1 / 0 | Hold / resume. |
| 132 | `CMD_SELL` | economy | structure ids | – | Begin sale (5.3). |
| 133 | `CMD_SET_STRUCT_REPAIR` | economy | structure ids | `mode` 0 off / 1 on / 2 toggle | Wrench mode. |
| 134 | `CMD_UNDEPLOY_HQ` | economy | HQ ids | – | HQ -> MCV. |
| 140 | `CMD_USE_POWER` | strategic | – | `p_idx`, `x`, `y`, `angle` (0–4095), `target_id` (OWN_STRUCTURE / OWN_UNIT targets, else 0) | Fire a support power. `p_idx` must be one of the roster's three powers (`NOT_AVAILABLE` otherwise); the slot is derived from it. LINE targets use `(x, y)` = centre and `angle` = direction of travel. |
| 141 | `CMD_LAUNCH_SUPERWEAPON` | strategic | – | `x`, `y`, `angle` | Fire the player's superweapon (slot 3). |

Unit orders owned by this domain are issued through the orders domain's generic order command with these order codes (`ORD_*`, proposed): `HARVEST=30` (`target` = deposit idx or -1 auto), `RETURN_CARGO=31` (`target` = refinery id or 0), `CAPTURE=32` (structure id), `REPAIR=33` (entity id), `SALVAGE=34` (wreck id), `DEPLOY_MCV=35` (optional cell). Order validation calls `capture_can_target`, `repair_can_target`, `salvage_can_target` and `SimPlacement.validate_hq_site`, so the sidebar/cursor and the AI receive the same `RSN_*` codes.

### 6.2 Events (output-only; codes are proposed, the reconciler owns the master table)

| Code | Name | Fields | Meaning / consumers |
|---|---|---|---|
| 300 | `EVT_CMD_REJECTED` | a=pid, b=cmd type, c=`RSN_*` | UI error voice/text. |
| 301 | `EVT_PLACE_REJECTED` | a=pid, b=`s_idx`, c=`RSN_*` | "Cannot deploy here". |
| 302 | `EVT_STRUCTURE_READY` | a=pid, b=`s_idx` | "Construction complete" (ready to place). |
| 303 | `EVT_STRUCTURE_PLACED` | a=pid, b=entity id, c=`s_idx` | Start build-up animation. |
| 304 | `EVT_STRUCTURE_ACTIVE` | a=pid, b=entity id, c=`s_idx` | Build-up finished. |
| 305 | `EVT_UNIT_PRODUCED` | a=pid, b=entity id, c=`u_idx`, d=producer id | "Unit ready". |
| 306 | `EVT_QUEUE_STATE` | a=pid, b=producer id (0 = construction, -1 = research), c=`QS_*`, d=reason | On change only; sidebar overlays. |
| 307 | `EVT_RESEARCH_COMPLETE` | a=pid, b=`r_idx` | "Upgrade complete". |
| 308 | `EVT_CREDITS_GAINED` | a=pid, b=amount, c=x, d=y | Floating "+$" text at refinery / wreck / depot. |
| 309 | `EVT_INSUFFICIENT_FUNDS` | a=pid, b=producer id/0/-1, c=needed | "Insufficient funds"; at most once per 100 ticks per queue. |
| 310 | `EVT_UNIT_CAP_REACHED` | a=pid | At most once per 200 ticks. |
| 311 | `EVT_POWER_SHORTAGE` | a=pid, b=supply, c=demand | "Low power". |
| 312 | `EVT_POWER_RESTORED` | a=pid | "Power restored". |
| 313 | `EVT_SAP_RESERVE_EMPTY` | a=pid | Defense reserve exhausted. |
| 314 | `EVT_STRUCTURE_SOLD` | a=pid, b=entity id, c=refund | Sale completed. |
| 315 | `EVT_STRUCTURE_SELLING` | a=pid, b=entity id, c=end tick | Sale animation. |
| 316 | `EVT_REPAIR_STATE` | a=pid, b=entity id, c=0/1 | Wrench icon. |
| 317 | `EVT_HQ_DEPLOYED` | a=pid, b=HQ id | |
| 318 | `EVT_HQ_UNDEPLOYED` | a=pid, b=MCV id | |
| 319 | `EVT_ORDER_FAILED` | a=pid, b=entity id, c=order type, d=`RSN_*` | Unit voice/text ("Cannot capture"). |
| 320 | `EVT_COLLECTOR_ATTACKED` | a=pid, b=entity id | Minimap ping + "Harvester under attack". |
| 321 | `EVT_NO_REFINERY` | a=pid | Hint. |
| 322 | `EVT_DEPOSIT_DEPLETED` | a=deposit idx | Visual state change of the field. |
| 323 | `EVT_DEPOSIT_REGROWN` | a=deposit idx | |
| 324 | `EVT_CAPTURE_PROGRESS` | a=leading pid, b=entity id, c=progress bp | Every 20 ticks while > 0. |
| 325 | `EVT_CAPTURE_CONTESTED` | a=entity id | |
| 326 | `EVT_STRUCTURE_CAPTURED` | a=new pid, b=entity id, c=old pid (-1 neutral) | "Structure captured". |
| 327 | `EVT_SALVAGE_STARTED` | a=pid, b=salvager id, c=wreck id, d=end tick | Salvage progress bar. |
| 328 | `EVT_SALVAGE_PAID` | a=pid, b=amount, c=x, d=y | Floating "+$". |
| 329 | `EVT_WRECKS_HIGHLIGHTED` | a=pid, b=x, c=y, d=radius (sub-cells), e=until tick | Survey Network overlay (UI-only). |
| 400 | `EVT_POWER_UNLOCKED` | a=pid, b=slot | "New support power available". |
| 401 | `EVT_POWER_READY` | a=pid, b=slot | Cooldown finished. |
| 402 | `EVT_POWER_ACTIVATED` | a=pid, b=slot, c=def idx (`p_idx` or `w_idx`), d=x, e=y, f=angle | Announcer; VFX anchor. |
| 403 | `EVT_POWER_EFFECT_END` | a=pid, b=`p_idx` | HUD timer end. |
| 404 | `EVT_WARNING` | a=warning id, b=owner pid, c=`WK_*`, d=src def idx, e=x, f=y | Zone geometry is read from `SimWarning` (queryable); event triggers the alarm cue and the zone VFX. |
| 405 | `EVT_SW_READY` | a=pid | "Superweapon ready". |
| 406 | `EVT_SW_CANCELLED` | a=pid, b=`w_idx`, c=cause (1 destroyed, 2 shutdown, 3 sold), d=warning id | |
| 407 | `EVT_SW_EXEC_START` | a=pid, b=`w_idx`, c=warning id | Warning ended; effects begin. |
| 408 | `EVT_SW_IMPACT` | a=kind (`w_idx`, or 100+`p_idx` for shells), b=x, c=y, d=radius, e=damage type | VFX/audio/camera shake. |
| 409 | `EVT_SW_DONE` | a=warning id | |
| 410 | `EVT_SUMMON_EXPIRED` | a=entity id, b=x, c=y | Fade-out VFX for silently removed summons. |

Events never carry hidden information beyond what the receiving player may see, except warnings, which are by design visible to `affected_mask` players; the view filters by `SimWarning.affected_mask` and `SimEntity` visibility (DR-12).

### 6.3 What other domains must add (see section 13 for exact signatures)

`SimCmd` encoders/decoders for codes 120–141 (layouts of 6.1); `SimEvent` with six payload ints; master `ORD_*` enum entries 30–35 and handler registration; `DEATH_*` cause flags (`SELF_DESTRUCT`, `SCUTTLE`, `FRIENDLY_FIRE`) on `kill_entity`; entity flags (`F_DEAD`, `F_TEMPORARY` mirror, no-footprint, no-collision, scripted-mover); `MatchRules.unit_cap/start_credits/superweapons`; `MapData.deposits/neutral_spawns/water_body_size/is_buildable/is_passable`; `world.struct_grid`; `SimWorld.set_owner`; abilities timed-effect API; zones API (repair, smoke, debris, intercept, `blocks_construction`); vision `add_reveal/is_explored/is_visible/is_identified`; combat `apply_area_damage(pk)`, `fire_log_query`, direct-fire flag, packet-emitting summon weapons; movement `find_free_cell_near/eject_units_from_rect/request_move`; the ZoneSystem/AbilitySystem/VisionSystem must skip entities flagged `EF_TEMPORARY` where victory or prerequisites are concerned.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

All under `game/data/balance/`. **Bible values are never duplicated or overridden here**: costs, cooldowns, tiers, prerequisites, recharge/warning seconds and research times are read from the mirrored bible (`game/data/bible/`); these files hold only what the bible leaves out. Every duration is written in **seconds** (float ok) and converted once at load with integer millisecond math (`ticks = ceil(sec*1000*TPS/1000)`), every distance in **cells** (converted `roundi(cells*1024)`), every percentage as **basis points** (DR-10). The converted int tables enter the data-version hash. Keys are bible ids (strings) so the sorted-id def index assignment (ARCH §7.4) applies unchanged.

### 7.1 `economy.json` — global economy constants and economy-side research knobs

```json
{
  "schema": 1,
  "collector": {
    "unit_id": "unit.shared.collector",
    "cargo_cap": 500,
    "harvest_chunk": 5,
    "harvest_interval_ticks": 4,
    "unload_chunk": 10,
    "unload_interval_ticks": 4,
    "dock_in_ticks": 12,
    "dock_out_ticks": 8,
    "search_stride_ticks": 20,
    "max_searches_per_tick": 6,
    "full_threshold_bp": 9000,
    "path_fail_retry_ticks": 600,
    "wait_dock_switch_ticks": 400,
    "flee": {
      "scan_stride_ticks": 10,
      "scan_radius_cells": 6,
      "clear_radius_cells": 8,
      "flee_ticks": 200,
      "danger_mark_ticks": 400,
      "alert_gap_ticks": 100
    }
  },
  "deposits": {
    "initial_fill_bp": 10000,
    "classes": [
      { "id": "starter",   "cap": 8000,  "radius_cells": 3, "max_harvesters": 4, "regen_amount": 40,  "regen_period_s": 10, "regen_delay_s": 60 },
      { "id": "expansion", "cap": 12000, "radius_cells": 3, "max_harvesters": 5, "regen_amount": 60,  "regen_period_s": 10, "regen_delay_s": 60 },
      { "id": "rich",      "cap": 20000, "radius_cells": 4, "max_harvesters": 6, "regen_amount": 100, "regen_period_s": 10, "regen_delay_s": 60 }
    ]
  },
  "production": {
    "queue_len": 5,
    "construction_queue_len": 5,
    "research_queue_len": 3,
    "exit_search_radius_cells": 4,
    "exit_retry_ticks": 10,
    "buildup_ticks": 30,
    "hq_deploy_ticks": 40,
    "hq_undeploy_ticks": 40,
    "unit_cap_default": 150,
    "placement_margin_cells": 1,
    "min_water_body_cells": 30
  },
  "sell": { "refund_bp": 5000, "sell_ticks": 40 },
  "repair": {
    "baseline_rate_bp": 100,
    "baseline_cost_bp": 5000,
    "pad_rate_bp": 300,
    "claim_stale_ticks": 10,
    "basis_default": { "structure": 600, "hq": 3000, "collector": 1400 }
  },
  "salvage": {
    "enabled_factions": ["faction.ae"],
    "salvager_units": ["unit.shared.engineer", "unit.ae.reclaimer", "unit.ae.river_warden"],
    "time_s": 8,
    "payout_bp": 2000,
    "wreck_life_s": 60
  },
  "capture": { "max_effective_engineers": 3, "decay_delay_ticks": 100, "decay_rate": 2, "reach_cells": 1.5 },
  "power": {
    "shortage_rate_bp": 5000,
    "balance_recheck_ticks": 100,
    "sap": { "faction_id": "faction.sap", "reserve_s": 20, "reserve_research_s": 35, "recharge_s": 60 }
  },
  "strategic": {
    "scheduler_cap": 256,
    "affected_margin_cells": 3,
    "affected_refresh_ticks": 10,
    "max_buff_targets": 256,
    "summon_spawn_back_cells": 16
  },
  "research_knobs": {
    "research.napc.dispersed_runways":       [ { "knob": "PAD_EXTRA", "op": "set", "value": 2 } ],
    "research.pd.integrated_flight_decks":   [ { "knob": "REARM_RATE_BP", "op": "set", "value": 11765 } ],
    "research.ae.recovery_winches":          [ { "knob": "SALVAGE_TICKS", "op": "set_seconds", "seconds": 5 } ],
    "research.sap.reserve_capacitors":       [ { "knob": "SAP_RESERVE_TICKS", "op": "set_seconds", "seconds": 35 } ],
    "research.def.standardized_parts":       [ { "knob": "REPAIR_COST_ENG_VEH_BP", "op": "set", "value": 8500 } ],
    "research.nec.tunnel_workshops":         [ { "knob": "REPAIR_RATE_DEF_BP", "op": "set", "value": 12500 } ],
    "research.pd.expeditionary_maintenance": [ { "knob": "REPAIR_RATE_TECH_BP", "op": "set", "value": 12500 } ],
    "research.han.modular_servicing":        [ { "knob": "REPAIR_RATE_TENDER_BP", "op": "set", "value": 15000 } ],
    "research.def.buried_command_lines":     [ { "knob": "EMP_RECOVERY_STRUCT_BP", "op": "set", "value": 7500 } ],
    "research.han.resilient_mesh":           [ { "knob": "EMP_RECOVERY_UNMANNED_BP", "op": "set", "value": 7500 } ],
    "research.nec.distributed_control":      [ { "knob": "RELAY_RADIUS_CELLS", "op": "set", "value": 8 }, { "knob": "RELAY_HOLD_TICKS", "op": "set_seconds", "seconds": 10 } ],
    "research.han.distributed_cognition":    [ { "knob": "CMD_RADIUS_CELLS", "op": "set", "value": 7 } ]
  }
}
```

Loader rules: `regen_period_s`/`regen_delay_s` -> ticks; `reach_cells` -> sub-cells; `op: set_seconds` -> ticks; unknown knob names are load errors. `basis_default` is used only when `paid_cost == 0`.

### 7.2 `structure_rules.json` — footprints, aprons, exits, power classes, producer kinds (29 entries)

Keys are the 29 bible structure ids. Schema per entry: `footprint [w,h]` cells; `rotatable`; `power_class` (`NONE|ECON|PRODUCER|SENSOR|DEFENSE|RELAY|STRATEGIC`); `queue` (`BARRACKS|FACTORY|AIRFIELD|DOCK|REFINERY|NONE`); `exit [dx,dy]` spawn cell relative to the origin (rotation-aware); `apron [[dx,dy],...]` cells that must stay free of structures; `dock [dx,dy]` (Refinery collector dock cell); `berth [dx,dy,w,h]` water rectangle (Dock); `pads {base:int, cells:[[dx,dy],...]}` (Airfield); `max_per_player` (strategic = 1); `build_radius_cells` (HQ); `repair_basis_cost`; `sell_locked`.

| Structure | Footprint | Power class | Queue | Notes |
|---|---|---|---|---|
| `structure.shared.headquarters` | 3x3 | NONE | – | `build_radius_cells` 8; exit (1,3) for undeployed MCV; `repair_basis_cost` 3000 |
| `structure.shared.generator` | 2x2 | NONE | – | |
| `structure.shared.refinery` | 3x3 | ECON | REFINERY | dock (1,3); exit (2,3); apron 3x2 south |
| `structure.shared.barracks` | 2x2 | PRODUCER | BARRACKS | exit (0,2); apron 2x2 south |
| `structure.shared.factory` | 3x3 | PRODUCER | FACTORY | exit (1,3); apron 3x2 south |
| `structure.shared.dock` | 3x3 (+3x2 berth) | PRODUCER | DOCK | rotatable; berth `[0,3,3,2]` at rot 0 |
| `structure.shared.radar` | 2x2 | SENSOR | – | |
| `structure.shared.airfield` | 6x3 | PRODUCER | AIRFIELD | pads base 4 (+`K_PAD_EXTRA`), pad cells in row y=1; apron row y=3 |
| `structure.shared.laboratory` | 3x3 | SENSOR | – | |
| `structure.shared.watchtower` | 1x1 | DEFENSE | – | |
| `structure.shared.anti_tank_turret` | 1x1 | DEFENSE | – | |
| `structure.shared.aa_battery` | 2x2 | DEFENSE | – | |
| `structure.napc.bulwark_cannon`, `structure.nec.lance_rail_emplacement`, `structure.olm.sunwall_projector`, `structure.def.citadel_mortar`, `structure.pd.sea_spear_battery`, `structure.han.dragon_tooth_launcher`, `structure.ae.forge_cannon`, `structure.sap.bastion_missile_tower` | 2x2 | DEFENSE | – | advanced defenses |
| `structure.nec.relay` | 1x1 | RELAY | – | 6-cell field radius from `K_RELAY_RADIUS_CELLS`; build time **20 s** (bible null) |
| `structure.napc.atlas_kinetic_array`, `structure.nec.aurora_microwave_array`, `structure.olm.helios_reflector`, `structure.def.perun_missile_complex`, `structure.pd.tempest_swarm_hub`, `structure.han.dragonfall_field_foundry`, `structure.ae.horizon_mass_driver`, `structure.sap.trident_interception_array` | 4x4 | STRATEGIC | – | `max_per_player` 1; `sell_locked` while a warning is pending |

```json
{
  "schema": 1,
  "structures": {
    "structure.shared.barracks": {
      "footprint": [2, 2], "rotatable": false, "power_class": "PRODUCER", "queue": "BARRACKS",
      "exit": [0, 2], "apron": [[0, 2], [1, 2], [0, 3], [1, 3]], "repair_basis_cost": 500
    },
    "structure.shared.dock": {
      "footprint": [3, 3], "rotatable": true, "power_class": "PRODUCER", "queue": "DOCK",
      "exit": [1, 3], "apron": [], "berth": [0, 3, 3, 2], "repair_basis_cost": 1800
    },
    "structure.shared.airfield": {
      "footprint": [6, 3], "rotatable": false, "power_class": "PRODUCER", "queue": "AIRFIELD",
      "exit": [2, 3], "apron": [[0, 3], [1, 3], [2, 3], [3, 3], [4, 3], [5, 3]],
      "pads": { "base": 4, "cells": [[0, 1], [1, 1], [2, 1], [3, 1], [4, 1], [5, 1]] }, "repair_basis_cost": 1600
    },
    "structure.napc.atlas_kinetic_array": {
      "footprint": [4, 4], "rotatable": false, "power_class": "STRATEGIC", "queue": "NONE",
      "max_per_player": 1, "sell_locked_during_warning": true, "repair_basis_cost": 5000
    }
  }
}
```

### 7.3 `powers.json` — effect recipes for the 48 support powers

Schema: `effects` = compiled by GameData into `temp_effects[]` (dense indices) for the abilities domain: `mods` (`stat` in `movement_speed|weapon_damage|reload_interval|weapon_range|sight|damage_taken|resist_explosive|dmg_taken_from_team`; `op` = `add_pct` with `bp`), `flags` (`suppression_immune|emp_immune|camouflage|weapons_disabled|unload_while_moving|no_fire|clear_suppression`), `heal_bp_per_s`, `end_on` (`MOVE|FIRE|DETECTED`), `stack_group` (defaults to the power id). `powers` = one entry per bible power id: `kind`, `target`, `vision`, `terrain`, `radius_cells` or `length_cells`+`width_cells`, `duration_s`, `warning_s`, `select`, `apply`, `knobs`, and kind-specific blocks. Cost, cooldown, tier, prerequisites come from the bible.

```json
{
  "schema": 1,
  "effects": {
    "fx.napc.combined_arms": { "mods": [ { "stat": "weapon_damage", "op": "add_pct", "bp": 1000 } ] },
    "fx.olm.capacitor_boost": { "mods": [ { "stat": "weapon_damage", "op": "add_pct", "bp": 2000 } ] },
    "fx.olm.capacitor_cooldown": { "flags": ["weapons_disabled"] },
    "fx.ae.marked": { "mods": [ { "stat": "dmg_taken_from_team", "op": "add_pct", "bp": 1500 } ] }
  },
  "powers": {
    "power.napc.uav_sweep": {
      "kind": "RECON_SUMMON", "target": "POINT", "vision": "NONE", "terrain": "any",
      "radius_cells": 7, "duration_s": 12,
      "summon": { "def": "summon.uav", "spawn_back_cells": 16, "speed_cells_s": 12, "orbit_cells": 1, "detect": true }
    },
    "power.napc.combined_arms_window": {
      "kind": "BUFF", "target": "AREA", "vision": "CURRENT", "terrain": "any",
      "radius_cells": 6, "duration_s": 15,
      "select": { "entity_kinds": ["unit"], "all_tags": ["combat"], "any_tags": ["infantry", "land_vehicle", "aircraft"], "exclude_tags": ["ship"], "team": "friendly" },
      "apply": [ { "fx": "fx.napc.combined_arms", "dur_s": 15 } ]
    },
    "power.olm.capacitor_discharge": {
      "kind": "BUFF", "target": "AREA", "vision": "CURRENT", "terrain": "any",
      "radius_cells": 6, "duration_s": 10,
      "select": { "entity_kinds": ["unit", "structure"], "weapon_subtype": "thermal", "team": "friendly" },
      "apply": [ { "fx": "fx.olm.capacitor_boost", "dur_s": 10 }, { "fx": "fx.olm.capacitor_cooldown", "delay_s": 10, "dur_s": 4 } ]
    },
    "power.def.mobilization_order": {
      "kind": "WINDOW", "target": "NONE", "vision": "NONE", "duration_s": 20,
      "knobs": [ { "knob": "PROD_RATE_BARRACKS_BP", "mode": "set", "value": 12500 }, { "knob": "PROD_RATE_FACTORY_BP", "mode": "set", "value": 12500 } ]
    },
    "power.def.tremor_barrage": {
      "kind": "BOMBARD", "target": "AREA", "vision": "CURRENT", "terrain": "any",
      "radius_cells": 5, "warning_s": 6,
      "shells": { "waves_offsets_ticks": [0, 53, 107, 160], "per_wave": 5, "damage": 180, "radius_cells": 1.5, "edge_bp": 3000, "struct_mult_bp": 12000, "dmg_type": "explosive" }
    },
    "power.olm.dust_screen": {
      "kind": "SMOKE", "target": "AREA", "vision": "CURRENT", "terrain": "any",
      "duration_s": 12,
      "zone": { "shape": "DISC", "radius_cells": 6, "direct_fire_reduction_bp": 3000 }
    },
    "power.napc.field_repair_drop": {
      "kind": "REPAIR", "target": "POINT", "vision": "CURRENT", "terrain": "clear_ground",
      "delivery": { "summon": "summon.cargo_aircraft", "spawn_back_cells": 16, "speed_cells_s": 10 },
      "zone": { "radius_cells": 5, "rate_bp_per_s": 200, "duration_s": 10, "targets": ["land_vehicle"], "group": "repair_station" }
    },
    "power.olm.false_convoy": {
      "kind": "DECOY", "target": "POINT", "vision": "EXPLORED", "terrain": "clear_land",
      "duration_s": 25,
      "decoys": [ { "def": "summon.decoy_light_vehicle", "count": 4, "scatter_cells": 3 } ]
    },
    "power.ae.counterbattery_solution": {
      "kind": "MARK", "target": "AREA", "vision": "NONE", "terrain": "any",
      "radius_cells": 9,
      "mark": { "since_s": 8, "reveal_s": 12, "fx": "fx.ae.marked", "dur_s": 12, "max_targets": 16 }
    }
  }
}
```

The remaining 39 entries follow the table in 5.18 literally (kind, target, vision, radius/length/width, duration, effects); the validator `check_econ_data.py` fails the build if any of the 48 ids is missing, if a bible cost/cooldown/tier key appears in this file, or if `kind` disagrees with the classification counts (3/4/19/6/1/6/2/3/3/1).

### 7.4 `superweapons.json` — geometry, packets and zones for the 8 superweapons

Bible fields (`recharge_seconds`, `warning_seconds`, `launcher_structure_id`, `requires_all_structure_ids`, `maximum_stored_charges`, `starts_charged`) are read from the bible mirror. This file supplies packet defs and the shapes of section 5.21. Entries for Aurora, Perun, Tempest and Dragonfall follow the same shape (`burst`, `core`+`ring`, `swarm`, `capsules`) with the values in the 5.21 table.

```json
{
  "schema": 1,
  "superweapons": {
    "superweapon.napc.atlas_kinetic_array": {
      "target": "LINE", "length_cells": 6, "default_angle": 0,
      "rods": { "offsets_cells": [0, -3, 3], "at_ticks": [0, 4, 8], "damage": 1400, "dmg_type": "kinetic",
                "radius_cells": 2.0, "edge_bp": 0, "struct_mult_bp": 15000, "layers": ["ground", "water", "structure"] }
    },
    "superweapon.olm.helios_reflector": {
      "target": "LINE", "length_cells": 16, "width_cells": 3,
      "beam": { "duration_s": 12, "pulse_interval_ticks": 4, "radius_cells": 1.5, "damage": 140,
                "dmg_type": "beam", "dmg_sub": "thermal", "uses_thermal_modifier": true, "layers": ["ground", "water", "structure"] }
    },
    "superweapon.ae.horizon_mass_driver": {
      "target": "LINE", "length_cells": 10,
      "impacts": { "offsets_cells": [-5, 0, 5], "at_ticks": [0, 90, 180], "damage": 1100, "dmg_type": "kinetic",
                   "radius_cells": 3, "edge_bp": 3000, "struct_mult_bp": 13000, "layers": ["ground", "water", "structure"] },
      "debris": { "radius_cells": 3, "duration_s": 20, "land_vehicle_speed_bp": 6500, "blocks_construction": true }
    },
    "superweapon.sap.trident_interception_array": {
      "target": "AREA",
      "zone": { "radius_cells": 6, "duration_s": 25, "charges": 24, "per_packet": 8, "reduction_bp": 5000, "shell_cost": 1 }
    }
  }
}
```

### 7.5 `neutral_structures.json` — the six neutral tech structures

```json
{
  "schema": 1,
  "neutrals": {
    "neutral.substation": {
      "name": "Grid Substation", "hp": 1200, "footprint": [2, 2], "capturable": true, "capture_s": 12,
      "repair_basis_cost": 600, "sight_cells": 6,
      "effects": [ { "kind": "POWER", "amount": 100 } ]
    },
    "neutral.salvage_depot": {
      "name": "Salvage Depot", "hp": 1600, "footprint": [3, 3], "capturable": true, "capture_s": 20,
      "repair_basis_cost": 600, "sight_cells": 6,
      "effects": [ { "kind": "INCOME", "amount": 50, "interval_s": 10 } ]
    },
    "neutral.field_hospital": {
      "name": "Field Hospital", "hp": 1000, "footprint": [2, 3], "capturable": true, "capture_s": 15,
      "repair_basis_cost": 600, "sight_cells": 6,
      "effects": [ { "kind": "HEAL_AURA", "radius_cells": 5, "rate_bp_per_s": 200, "targets": ["infantry"] } ]
    },
    "neutral.observation_tower": {
      "name": "Observation Tower", "hp": 800, "footprint": [1, 1], "capturable": true, "capture_s": 15,
      "repair_basis_cost": 600, "sight_cells": 14, "effects": []
    },
    "neutral.civilian_garrison": {
      "name": "Civilian Block", "hp": 2000, "footprint": [3, 3], "capturable": false,
      "repair_basis_cost": 600, "sight_cells": 5,
      "effects": [ { "kind": "GARRISON", "squads": 4 } ]
    },
    "neutral.harbor_terminal": {
      "name": "Harbor Terminal", "hp": 2200, "footprint": [3, 3], "capturable": true, "capture_s": 25,
      "repair_basis_cost": 600, "sight_cells": 6, "needs_shore": true, "berth": [0, 3, 3, 2],
      "effects": [ { "kind": "FORWARD_QUEUE", "queue": "DOCK", "tier_cap": 1, "counts_as": "structure.shared.dock" } ]
    }
  }
}
```

### 7.6 `repair_profiles.json` — repairer categories and the units bound to them

```json
{
  "schema": 1,
  "categories": {
    "ENGINEER":       { "rate_bp": 100, "cost_bp": 5000, "targets": ["land_vehicle", "structure"], "range_cells": 1.5, "self": false },
    "TECHNICIAN":     { "rate_bp": 100, "cost_bp": 5000, "targets": ["land_vehicle", "ship"], "range_cells": 2.0, "self": false },
    "TENDER":         { "rate_bp": 100, "cost_bp": 5000, "targets": ["unmanned_land"], "range_cells": 2.0, "self": false },
    "PIONEER":        { "rate_bp": 100, "cost_bp": 5000, "targets": ["defense_structure"], "range_cells": 1.5, "self": false },
    "FIELD_ENGINEER": { "rate_bp": 100, "cost_bp": 5000, "targets": ["structure"], "range_cells": 1.5, "self": false },
    "WRENCH":         { "rate_bp": 100, "cost_bp": 5000, "targets": ["structure"], "range_cells": 0, "self": true },
    "PAD":            { "rate_bp": 300, "cost_bp": 5000, "targets": ["aircraft"], "range_cells": 0, "self": false }
  },
  "units": {
    "unit.shared.engineer":            { "category": "ENGINEER" },
    "unit.ae.reclaimer":               { "category": "ENGINEER", "targets": ["land_vehicle"] },
    "unit.ae.river_warden":            { "category": "ENGINEER", "targets": ["land_vehicle"] },
    "unit.pd.reef_technician":         { "category": "TECHNICIAN" },
    "unit.han.lotus_drone_tender":     { "category": "TENDER" },
    "unit.sap.combat_pioneer":         { "category": "PIONEER" },
    "unit.nec.alpine_pioneer":         { "category": "PIONEER" },
    "unit.han.mekong_field_engineer":  { "category": "FIELD_ENGINEER" }
  }
}
```

### 7.7 `summons.json` — temporary entity defs owned by this domain (stats are initial tuning targets; the balance domain may retune, the flags are normative)

```json
{
  "schema": 1,
  "summons": {
    "summon.uav": {
      "layer": "air", "hp": 120, "armor": "air_light", "speed_cells_s": 12, "sight_cells": 7, "detector_cells": 7,
      "script": "FLY_TO_HOVER", "shootable": true,
      "flags": ["TEMPORARY", "SUMMON", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR"]
    },
    "summon.cargo_aircraft": {
      "layer": "air", "hp": 300, "armor": "air_medium", "speed_cells_s": 10, "sight_cells": 4, "detector_cells": 0,
      "script": "FLY_TO_DROP", "shootable": true,
      "flags": ["TEMPORARY", "SUMMON", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR"]
    },
    "summon.tempest_drone": {
      "layer": "air", "hp": 60, "armor": "air_light", "speed_cells_s": 9, "sight_cells": 2, "detector_cells": 0,
      "script": "NONE", "brain": "SWARM_ZONE", "shootable": true,
      "weapon": { "damage": 70, "dmg_type": "explosive", "radius_cells": 0.75, "reload_ticks": 24, "range_cells": 2,
                  "packet": true, "targets": ["ground", "water"], "struct_mult_bp": 10000 },
      "flags": ["TEMPORARY", "SUMMON", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR", "NO_VISION_GRANT"]
    },
    "summon.dragonfall_capsule": {
      "layer": "ground", "hp": 400, "armor": "heavy", "speed_cells_s": 0, "sight_cells": 3, "detector_cells": 0,
      "script": "CAPSULE", "assemble_s": 5,
      "flags": ["TEMPORARY", "SUMMON", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR", "NO_VISION_GRANT"]
    },
    "summon.dragonfall_engine": {
      "layer": "ground", "hp": 2500, "armor": "heavy", "speed_cells_s": 1.0, "sight_cells": 6, "detector_cells": 0,
      "script": "ENGINE", "brain": "ASSAULT_STRUCTURES", "lifetime_s": 60,
      "weapon": { "damage": 320, "dmg_type": "explosive", "radius_cells": 1.2, "reload_ticks": 40, "range_cells": 6,
                  "packet": true, "targets": ["structure", "ground"], "struct_mult_bp": 20000 },
      "flags": ["TEMPORARY", "SUMMON", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR", "NO_HARVEST", "NO_COMMAND_BUFF"]
    },
    "summon.repair_station": {
      "layer": "ground", "hp": 400, "armor": "medium", "speed_cells_s": 0, "sight_cells": 4, "detector_cells": 0,
      "script": "STATION", "flags": ["TEMPORARY", "SUMMON", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR"]
    },
    "summon.decoy_light_vehicle": {
      "layer": "ground", "hp": 1, "armor": "none", "speed_cells_s": 0, "sight_cells": 0, "detector_cells": 0,
      "script": "DECOY", "model_role": "light_vehicle", "no_collision": true,
      "flags": ["TEMPORARY", "DECOY", "NO_SALVAGE", "NO_CAPTURE", "NO_REPAIR", "NO_VISION_GRANT"]
    }
  },
  "wreck": { "hp": 200, "armor": "wreck", "auto_target": false, "life_s": 60 }
}
```

### 7.8 Loading, hashing and validation

* `DefEconRules`, `DefStructureRules`, `DefPowerRecipe`, `DefSuperweaponRules`, `DefNeutral`, `DefRepairProfile`, `DefSummon` load the seven files after the bible mirror; ids are resolved to dense def indices; every conversion (seconds, cells, bp) uses integer arithmetic (`ceil`/`roundi` once, DR-10); the converted int tables are folded into the data-version hash (FNV-1a) that gates the lobby.
* `tools/py/check_econ_data.py` (stdlib only) asserts: all bible ids referenced exist; 48/8/29 entries present; `structure_rules` keys = the 29 structure ids; no bible-owned key (`cost_credits`, `cooldown_seconds`, `tier`, `recharge_seconds`, `warning_seconds`, `research_time_seconds`) in any file; every unit with tier 2 lists `structure.shared.radar` and tier 3 lists Radar + Laboratory; every research/power tier matches `mechanical_conventions.tier_requirements`; per-kind counts of `powers.json` = 3/4/19/6/1/6/2/3/3/1; every roster resolves exactly 3 support powers and 1 superweapon; every knob name exists; every `summon.*` referenced exists; JSON parses; no duplicate keys.

### 7.9 Bible nulls this domain needs the balance layer to fill

| Null | Needed by | Recommendation |
|---|---|---|
| `structure.nec.relay.build_time_seconds` | construction queue | **20 s** (comparable to Barracks) |
| `unit.shared.engineer` build time | Barracks queue | **12 s** |
| `unit.shared.collector` build time | Refinery queue | **30 s** |
| `unit.shared.mobile_construction_vehicle` build time | Factory queue | **45 s** |
| `unit.shared.landing_transport` build time | Dock queue | **25 s** |
| Every combat unit `cost_credits` / `build_time_seconds` (104 baseline + 48 unique) | all unit queues | Balance layer. Economy-compatible guidance (the loop pays ~730 credits/min per Collector): T1 infantry 150–300 credits / 8–12 s; light vehicles 600–900 / 15–20 s; tanks 900–1,400 / 20–28 s; T2 AA and artillery 1,000–1,600 / 22–30 s; T3 siege tanks and gunships 1,800–2,600 / 35–45 s; aircraft 1,200–2,400; ships 700–2,600. Rule of thumb: build seconds is about credits / 50. |
| `DefUnit.cap_cost` | unit cap | default 1; MCV/Collector 1; drones spawned by carriers 0 |
| Structure `hp`, sight, weapons; unit `hp`, speed, weapons | combat/vision | balance layer (this domain adds `summons.json` and `neutral_structures.json` hp for its own entities) |

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

| Rule | How this domain complies |
|---|---|
| DR-1 ints only | Every quantity (credits, hp, progress in bp-ticks, rates in bp, power, repair accumulators, capture ticks, cooldown ticks) is `int`. No `float`, no `Vector2/3`; `Vector2i` appears only as *cell* output of `find_site` (AI helper). Data floats (seconds, cells) are converted once at load. |
| DR-2 no engine randomness | Randomness exists only at **power/superweapon activation** (shell scatter, decoy positions, capsule landing points), drawn from `world.rng` inside `handle_command` in a fixed loop order and stored in `SimScheduled`/`SimWarning` payloads. Draw counts are bounded and deterministic per recipe: decoy = 2 draws per try, `tries <= 6`; shell = 2 draws (angle, radius) plus at most 4 rejection retries; capsule = 2 draws per try, `tries <= 8`. Nothing draws per tick. |
| DR-3 no wall-clock | Only `world.tick`. All timers are absolute ticks or countdowns. |
| DR-4 float builtins | Distances via `Fp.dist` (exact integer sqrt), directions via `Fp.sin/cos/atan2` tables (Helios pulse centres, Tempest spawn ring, spawn-behind direction). |
| DR-5 division | All divisions have non-negative operands (asserted in debug); worst magnitudes: payment `cost*progress <= 9e10`, repair `cacc <= 1.5e11`, `dist2 <= (256*1024)^2 = 6.9e10`. |
| DR-6 iteration order | Entities/producers/refineries/collectors iterate as ascending-id `PackedInt32Array`s (`producer_flat`, `refinery_ids`); players iterate `pid` 0..7; deposits by index; `cap_chan` by pid 0..7; scheduler by `(tick, seq)`. **No `Dictionary` is iterated at runtime** (dictionaries appear only in load-time id maps). |
| DR-7 sorting | `_sched` uses binary insertion with a total key `(tick, seq)`; deposit/refinery choice breaks ties by lowest index/id; `sort_custom` is not used in the tick path. |
| DR-8 no Node/await | All classes `RefCounted`; no signals, timers, threads. |
| DR-9 no global state | All state hangs off `SimWorld` (`econ_players`, systems, comps). `SimPlacement` static methods are pure; no `static var`. Two worlds in one process produce identical hashes. |
| DR-10 data | Seven JSON files converted with integer math; converted tables are part of the data-version hash. |
| DR-11 bounded work | Field searches <= 6 per tick; buff targets <= 256; scheduler <= 256 records; wreck/decay loops O(structures); `find_site` <= 400 probes (AI thread, host only, never in the tick). |
| DR-12 events output-only | The sim never reads `world.events`. Warning zones are **state** (`SimWarning`), not events, so late joiners/replays see them. |
| DR-13 checksum | See below. |
| DR-14 AI/UI floats | AI/UI read queries and submit `CMD_*` ints. |

**Checksum contents** (all folded by `checksum_into(ck)` with `Checksum.add_int`; bools as 0/1; packed arrays as `length` then elements; fields in the order of section 4; call order: players by pid -> `SimDepositTable` -> strategic globals (`seq`, `next_warning_id`, `_sched` records in order, `warnings` in order) -> entity components in entity-id order by the sim-core entity walk):

* `SimPlayerEcon`: every field of 4.2 including derived caches (`struct_count`, `refinery_ids`, `producer_ids`, `producer_flat`, rate table, knob arrays, income ring, `field_danger`, `rr_offset`, both queues with progress/paid/state/hold, `researched`, reserve fields, all 4 `SimPowerSlot`s).
* `SimCompEcon`, `SimCompProd`, `SimCompWreck`, `SimCompTemp` for every entity that carries them (accumulators `repair_acc_*`, `cap_*`, dock queue, collector FSM, pad table, rearm boost).
* `SimDepositTable` arrays and the system-private lists of 4.6.
* Interaction with other domains' state that this domain mutates (owner changes, hp changes from repair, entities spawned/removed) is covered by their checksums.
* **Checksum parts for desync diagnosis** (net.md `part_names` = `["entities","players","rng","map","production","economy","orders","combat","zones","vision"]`): the `production` part folds `SimPlayerEcon` queue/rate/counter/researched fields, every `SimCompProd`, `producer_ids`, `producer_flat` and `struct_count`; the `economy` part folds credits, statistics, income fields (`income_bp`, `income_acc`), power and reserve fields, knobs, `SimCompEcon`, `SimCompWreck`, `SimDepositTable`, the four `SimPowerSlot`s, the scheduler, the warnings and `SimCompTemp`. Handicap (`income_bp`) is stored and checksummed (net XR-9).

**Engine APIs relied on** (verified against `tools/godot_docs/doc/classes` for Godot 4.7.2): `PackedInt32Array` and `PackedByteArray` (`resize`, `fill`, `push_back`, `remove_at`, `insert`, `find`, `has`, `append_array`, `size`, `is_empty`, `duplicate`; `PackedInt32Array.bsearch`), typed `Array[T]` including `Array[PackedInt32Array]`, `Array.insert/remove_at`, `RefCounted`. Nothing else from the engine is touched by this domain's sim code.

Cross-platform: no floating point and no platform-dependent iteration exists in this domain, so macOS arm64 / Linux x86_64 / Windows x86_64 must match bit-for-bit; golden hashes of scenarios S1 and S6 (section 10) are committed and re-run in the Debian container.

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

Assumptions: 20 TPS (50 ms), 8 players, ~1,200 entities, GDScript at roughly 1 µs per 10–15 simple statements. Target for this domain: **<= 0.8 ms typical, <= 2.5 ms worst case** per tick (5 % of the tick), excluding one-shot activation spikes.

| Component | Typical | Worst | Reasoning / mitigation |
|---|---|---|---|
| `SimProductionSystem.update` | 0.15 ms | 0.8 ms | Queue visits: 8 players x (construction + research + ~6 producers) = 64 visits, ~30 statements each; empty queues exit in 3 statements; worst 8 x 25 producers = 200 visits. Rate table recomputed only on change (`rates_dirty`). No allocation (parallel packed arrays). |
| `SimEconomySystem.update` | 0.1 ms | 0.6 ms | Sell/undeploy completion: only structures in those states (kept in a small id list). Wrench repair: only `repair_on` structures (<= 100 worst, ~60 statements each). Capture: only structures with channelers/progress. Deposit regen every 20th tick over <= 64 fields. Power balance only when `power_dirty`, plus a 100-tick recheck over <= 60 structures per player. |
| Order handlers (stage 5 share) | 0.3 ms | 0.8 ms | <= 96 Collectors x ~30 statements; field searches capped at 6/tick x <= 64 fields x ~15 statements (~0.25 ms worst); flee scans every 10 ticks (spatial hash query, radius 6 cells) staggered by `(id + tick) % 10`. |
| `SimPowerSystem.update` | 0.01 ms | 0.02 ms | 8 players x few compares. |
| `SimStrategicSystem.update` | 0.03 ms | 0.4 ms | 32 slot compares; scheduler pop O(1) per record; warnings' `affected_mask` refresh every 10 ticks (<= 4 warnings x one spatial query); Helios 1 pulse/4 ticks; Tempest/Dragonfall brains stride 20 (<= 27 units). |
| **Activation spikes (one-shot)** | – | 2–4 ms | BUFF on 256 targets: one `query_circle` + ~150 statements per target. Mitigation: hard cap 256 (nearest by id order); if > 128 targets, apply in two batches on consecutive ticks with durations measured from the actual application tick. Tempest spawn: 24 entities (~0.5 ms). |
| `SimPlacement.validate` (UI ghost, per frame, not in tick) | – | 30 µs | <= 24 cells x grid lookups + 1 spatial query + apron check over <= 12 nearby structures. |
| `SimPlacement.find_site` (AI, host only) | – | 8 ms | <= 400 probes x 20 µs; AI throttles to one call per think step and may spread across frames. |

Memory: `SimCompEcon` ~ 200 B, `SimCompProd` ~ 250 B (queues are 5-element packed arrays), per-player record ~ 2 KB; total < 400 KB. Allocation policy: components are created at spawn; scratch arrays and the pooled `SimImpactPacket` are reused; `SimScheduled`/`SimWarning` objects are allocated only at activation (bounded by the 256 cap) and freed when done; events go to the sim-core event ring.

---

## 10. Test plan (unit / scenario / determinism / visual)

All tests are `game/tests/test_*.gd` with `func run(t: TestCtx)`, run via `tools/gd test <filter>`; numbers below are the expected assertions. Tick counts assume `TPS = 20`.

### 10.1 Unit tests

| ID | File | Cases and expected values |
|---|---|---|
| **10.1-A** ledger | `test_econ_ledger.gd` | Handicap 120: a 10-credit unload credits 12; handicap 125: four 10-credit unloads credit 12, 13, 12, 13; refunds and sells ignore the handicap. `spend(600)` from 500 -> false, credits unchanged; `earn` updates income ring only for HARVEST/SALVAGE/DEPOT; refunds do not count as income; `q_income_per_minute` after 12 buckets. |
| **10.1-B** payment | `test_prod_payment.gd` | Factory cost 2000, 40 s: paid after tick 1/2/3 = 2/5/7; after 400 ticks = 1000; completes exactly at tick 800 with `paid == 2000`; cancel at tick 400 refunds 1000. Shortage (`rate_bp` 5000): completes at 1600. Shortage + Mobilization (6250): completes at 1280 (= 8,000,000 / 6250). Credits 0: progress frozen, state `PAUSED_FUNDS`; +1000 credits: resumes at the same progress. Two queues, 3 credits available: no double spend (credits never negative). |
| **10.1-C** queues | `test_prod_queue.gd` | 5 enqueues OK, 6th `QUEUE_FULL`; hold/resume keeps `paid`; T2 unit at 30 % with Radar destroyed -> `PAUSED_PREREQ`, `progress`/`paid` unchanged for 200 ticks, rebuild Radar -> resumes; unit cap 3 with 3 live units -> head `PAUSED_CAP` and no `cap_reserved`; exit cell blocked and no free cell within 4 -> `PAUSED_EXIT`, retry every 10 ticks; replaced unit -> `NOT_AVAILABLE`; `producer_id = 0` picks primary, ties lowest id; Collector only at Refinery. |
| **10.1-D** placement | `test_placement.gd` | HQ 3x3 origin (10,10): Barracks 2x2 origin (19,11) valid (7.5 cells); origin (20,11) `OUT_OF_RADIUS`; a footprint whose nearest point is exactly 8.0 cells is valid (`d2 == 67,108,864`); overlap with structure `STRUCTURE_BLOCK`; deposit cell `DEPOSIT`; Horizon debris `DEBRIS`; enemy unit in footprint `UNIT_BLOCK`, friendly unit ejected; Refinery apron overlapped by another structure `APRON`; Dock with land berth `NEEDS_SHORE`, puddle (< 30 cells) `NEEDS_SHORE`, valid shoreline OK at rotations 0–3; second strategic structure `STRATEGIC_LIMIT` at enqueue and at placement; Relay outside 8 cells -> invalid; two HQs: valid if within 8 of either; `validate_hq_site` ignores radius. |
| **10.1-E** power | `test_power_grid.gd` | HQ+Generator+Refinery+Barracks+Factory+Radar: supply 150, demand 120, normal; +Laboratory: demand 180 -> `SHORTAGE` (strict; equal is normal); OLM Generator = 188; Saudi = 225; captured Substation +100; sell/destroy updates on the same stage-3 pass; EMP-shut-down structure still counts as demand. SAP reserve: shortage 1000–1500 -> `defenses_online` false from tick 1400, streak, refill at tick 2700 (`reserve_left` 400); shortage 1000–1200 -> left 200, refill at 2400; second shortage at 1800 -> 0 at 2000; Reserve Capacitors: max 700, full reserve becomes 700; non-SAP: defenses offline at once; superweapon charge pauses and never uses reserve. |
| **10.1-F** repair | `test_repair_step.gd` | Guardian `paid 1100`, `max_hp 800`, Engineer: 8 hp/s, 0->full in 2000 ticks, spent exactly **550**; AE (`cost_bp` 3750): **412** spent (carry 0.5 remains); DEF Standardized Parts: **467**; credits 0 -> hp does not increase and accumulators unchanged; wrench 1 %/s and Engineer stack (two sources) but two Engineers do not (`BUSY`); Cambodia structure rate 12500 -> 1.25 %/s with cost per hp unchanged; Tunnel Workshops on a defense structure only; `EF_NO_REPAIR` -> `DECOY`; Lotus never repairs itself. |
| **10.1-G** harvest | `test_harvest_cycle.gd` | Stub movement (fixed speed 2.4 cells/s), field 12 cells from refinery: cycle 41 s +/- 1 s, +500 credits per cycle, deposit stock -500; with two equidistant fields the second Collector picks the field with fewer harvesters (penalty 4 cells per harvester); depleted field -> regrows +40 at `last_harvest + 1200 + 200`; refinery destroyed while unloading -> cargo intact; dock FIFO order deterministic for 3 Collectors; `field_danger` after flee steers others away for 400 ticks; `h_bad_field` expires after 600 ticks. |
| **10.1-H** capture | `test_capture.gd` | Substation `cap_need` 240: 1 Engineer captured at exactly 240 ticks; 2 -> 120; 3 -> 80; 4 -> 80; contested by two teams -> no change; idle 100 ticks then decays 2/tick; enemy Engineer burns down stored 150 progress in 150 ticks; Engineers not consumed; Combat Pioneer / Sapper cannot capture; faction structures `WRONG_KIND`; captured substation moves +100 power between players. |
| **10.1-I** salvage | `test_salvage.gd` | Wreck creation matrix: enemy-killed tank yes; friendly fire, scuttle, self-destruct, summon, decoy, aircraft, ship, infantry, Collector, water cell -> no wreck. AE Engineer on `paid 1100` wreck: duration 160 ticks, payout **220**, wreck removed, pays once; interrupt at tick 100 resets; Winches -> 100; Recovery Priority -> 60 (MIN); non-AE Engineer `WRONG_KIND`; wreck of an ally `FRIENDLY`; expiry frozen while claimed; `EXPIRING` if life < duration. |
| **10.1-J** powers | `test_strategic_powers.gd` | Ready when first unlocked (`ready_tick 0`); cooldown absolute: destroy and rebuild Radar -> cooldown unchanged; shortage -> `NO_POWER` but cooldown keeps running; credits charged once, insufficient -> `NO_CREDITS` and no cooldown; vision rules (recon any, decoys explored, others current); each of the 10 kinds runs its recipe (BUFF applies to exactly the expected ids; WINDOW restores knobs at expiry; SMOKE zone args; DECOY count/flags; BOMBARD schedule ticks; MARK targets). |
| **10.1-K** superweapons | `test_superweapons.gd` | Charge reaches READY after exactly 9600 ticks (Aurora 8400, Trident 7200); shortage of 600 ticks delays by 600; READY does not overcharge; activation at `T`: `charge = 0`, warning `T+200`; launcher destroyed at `T+100` -> cancelled, no refund; EMP shutdown at `T+100` -> cancelled; shortage during warning does not cancel; launcher lost after `T+200` does not cancel; Atlas packets at `T+200/204/208` with radius 2.0 and centres -3/0/+3; Trident 24 charges vs Atlas: all 3 rods `pre_resist_bp 5000`, charges 0; Perun leaves 8; ordinary shell costs 1; fewer than 8 charges -> no reduction; Trident + 40 % explosive resistance -> total reduction capped at 50 %; Helios pulses 60 at `X+4k` with head positions `(2k+1)*16/120`; Horizon impacts at `X, X+90, X+180` and debris blocks placement for 400 ticks; Dragonfall engines appear `X+100`, vanish `X+1300`; Tempest spawns 24, expire at arrival + 400. |
| **10.1-L** resolved tables | `test_econ_resolved.gd` | Section 5.2 table: 1530, 383, 1530, 720, 540, 360/720/1800 ticks, 595, 188, 225, 990. |
| **10.1-N** no DEF snowball | `test_def_traits.gd` | DEF roster has no permanent `PROD_RATE` change, no passive income; only Mobilization Order changes rates for 400 ticks. |
| **10.1-P** data | `test_econ_data.py` (via `check_econ_data.py`) | Section 7.8 assertions. |

### 10.2 Scenario tests (build a `SimWorld`, issue commands, tick N)

* **S1 opening**: 7,500 credits, one ACTIVE HQ; at tick 0 queue Generator (600, 25 s), Refinery (1,800, 40 s), Barracks (500, 20 s), Factory (2,000, 40 s); the harness places each item on the tick after its `EVT_STRUCTURE_READY`. Expected (tolerance +/- 5 ticks): Generator READY 500, ACTIVE 531; Refinery waits for the Generator prerequisite, READY 1331, ACTIVE 1362, free Collector spawns at 1362 and starts harvesting; Barracks READY 1732, ACTIVE 1763; Factory (prerequisite Refinery) READY 2533. Invariants: credits never negative; at tick 3,000 `credits == 7500 - 4900 + stat_harvested`; `struct_count` equals the recount.
* **S2 brownout**: add Laboratory -> shortage; production runs at half speed (a 400-tick Barracks item takes 800); Watchtower stops firing; SAP variant keeps firing for 400 ticks; add Generator -> restored; superweapon charge counter frozen during shortage.
* **S3 raid**: enemy tanks approach a harvesting Collector -> flee within 10 ticks, `EVT_COLLECTOR_ATTACKED`, field marked dangerous, cargo preserved, unload at a safe Refinery.
* **S4 salvage economy**: AE vs NAPC skirmish; log `stat_salvaged / total income` for the balance team (target < 15 % of AE income in even fights).
* **S5 expansion**: MCV -> second HQ -> build radius from both; undeploy -> MCV cost restored; sell refunds 50 %.
* **S6 superweapon duel**: Aurora fired at an enemy Atlas launcher during its warning -> Atlas cancelled; Trident vs Atlas; Horizon debris blocks an MCV deploy.
* **S7 AI soak**: 10-minute AI-vs-AI matches on three map families: no negative credits, no queue stuck in a `PAUSED_*` state for > 5 minutes unless prerequisites are genuinely missing, every roster uses at least one support power, at least one superweapon executes.
* **S8 windows**: Mobilization Order raises Barracks/Factory rate to 12500 for exactly 400 ticks then restores; Treaty/Central/Reserve Bandwidth knobs restored; Joint Landing window.

### 10.3 Determinism tests

* **D1** double run of S1 + S6: identical checksum chain every 20 ticks.
* **D2** replay: record commands of S6, replay in a fresh world, identical final checksum.
* **D3** cross-platform: committed golden checksums for S1/S6/S8, verified on macOS and in the Debian container (`gd linux test determinism`).
* **D4** property fuzz for accumulators (seeded `SimRng`): random rates, hp and credits; assert `sum(hp restored) * cost_per_hp` equals credits spent within < 1 credit and no credit is created or lost.
* **D5** queue fuzz: random legal/illegal commands for 20,000 ticks; invariants after each tick: `credits >= 0`; `paid <= cost`; `cap_reserved` equals recount; `struct_count` equals recount of ACTIVE non-temporary structures; `power_supply/demand` equal recount; every dock occupant alive.

### 10.4 Visual tests (`tools/gd shot`, inspected with the image reader)

* Placement ghost showing green, red-terrain, red-radius, red-apron and shore cells for a Dock (screenshots for the 5 `CF_*` classes).
* Warning overlays for Atlas (3 circles), Helios (line capsule), Horizon (3 circles + debris afterwards), Perun (core + ring), Aurora, Trident (visible to all after activation), each seen from an "affected" and an "unaffected" player's camera.
* Power bar in shortage, SAP reserve indicator, capture progress ring, deposit stock states (full / half / depleted / regrowing), Collector unloading effect, wrench icon, salvage progress bar, sidebar queue states (`READY`, `HOLD`, `PAUSED_*`).

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Dependency notation: `E#` = task in this spec; `[sim-core]`, `[data]`, `[map]`, `[orders]`, `[movement]`, `[combat]`, `[abilities]`, `[zones]`, `[vision]`, `[balance]`, `[qa]` = other domains. Where a dependency is not yet delivered, the caller uses a stub that calls `push_error("NOT IMPLEMENTED: ...")` (ARCH §13.3), never a silent success.

| Task | Files owned | Depends on | Est. lines | Acceptance |
|---|---|---|---|---|
| **E0 Constants & records** | `sim_econ_const.gd`, `sim_player_econ.gd`, `sim_comp_econ.gd`, `sim_comp_prod.gd`, `sim_comp_wreck.gd`, `sim_comp_temp.gd`, `sim_power_slot.gd`, `sim_warning.gd`, `sim_scheduled.gd`, `sim_impact_packet.gd`, `sim_placement_result.gd` | [sim-core] `Checksum`, entity component slots | 700 | Construct every class; defaults match section 4; `checksum_into` is order-stable (D1 micro-test); `gd check` clean. |
| **E1 Data loaders, JSON, validator** | `def_econ_rules.gd`, `def_structure_rules.gd`, `def_power_recipe.gd`, `def_superweapon_rules.gd`, `def_neutral.gd`, `def_repair_profile.gd`, `def_summon.gd`, the seven `game/data/balance/*.json` (29 structures, 48 powers, 8 superweapons, 6 neutrals, repair profiles, summons, economy), `tools/py/check_econ_data.py` | E0, [data] id/index assignment and hash, [balance] nulls (7.9) | 1,700 GDScript + JSON | 10.1-P, 10.1-L, all counts in 7.8; converted tables identical on macOS and Linux. |
| **E2 Economy core & power** | `sim_economy_system.gd` (ledger, hooks, player init, unit cap, income ring, sell/undeploy completion, neutral income/power, stats), `sim_power_system.gd` (balance, shortage FSM, SAP reserve, derived flags) | E0, E1, [sim-core] hooks | 1,600 | 10.1-A, 10.1-E, 10.1-N; S2 (power part). |
| **E3 Production** | `sim_production_system.gd` (construction/unit/research queues, rate table, prerequisite pause, cap reservation, exit and rally, pads API, research knob application, `handle_command` 120–131) | E0–E2, E4, [movement] `find_free_cell_near`, [sim-core] spawn API | 2,300 | 10.1-B, 10.1-C; S1, S8 (rate part). |
| **E4 Placement & structure lifecycle** | `sim_placement.gd`, `sim_structure_life.gd` (activate, deactivate, sell, undeploy, MCV deploy, wrench loop) | E0, E2, [map] `is_buildable/water_body_size`, [sim-core] `struct_grid`, [zones] `blocks_construction`, [movement] `eject_units_from_rect` | 1,500 | 10.1-D; S5; visual ghost tests 10.4. |
| **E5 Harvesting** | `sim_deposit_table.gd`, `sim_order_harvest.gd`, `sim_economy_docks.gd` (the delegating one-liners in `sim_economy_system.gd` are written by E2 against the signatures of 3.2) | E0, E2, [orders] handler API, [movement] move/stop, [map] `deposits`, [vision] `is_explored` | 1,800 | 10.1-G; S3; S7 income bands. |
| **E6 Engineer orders & neutrals** | `sim_order_capture.gd`, `sim_order_repair.gd`, `sim_order_salvage.gd`, `sim_order_deploy_mcv.gd`, `sim_economy_work.gd` (repair primitive, capture evaluation, wreck and salvage API); neutral effect registration hooks called from E2's `on_owner_changed` | E0, E2, E4, [orders], [movement], [sim-core] cleanup hook, [abilities] aura primitive (Field Hospital) | 2,000 | 10.1-F, 10.1-H, 10.1-I; S4, S5. |
| **E7 Strategic framework & support-power recipes** | `sim_strategic_system.gd`, `sim_strategic_effects.gd` (10 kinds, scheduler, windows, warnings, `emit_packet`, `handle_command` 140–141) | E0–E3, E1 (`powers.json`), [abilities] `apply_timed_effect`, [zones] `create`, [vision] `add_reveal`, [combat] `apply_area_damage`, `fire_log_query` | 2,500 | 10.1-J; S8; visual tests for warnings. |
| **E8 Superweapons & summons** | `sim_superweapons.gd` (8 timelines, `danger_fraction_bp`), `sim_summon_brain.gd` (Dragonfall / Tempest autonomy, expiry) | E7, [combat] summon weapons and packet emission, [zones] intercept and debris, [orders] `ORDER_ATTACK`, [movement] air units | 1,800 | 10.1-K; S6. |
| **E9 Tests, scenarios, goldens** | all files in section 10, golden hash files, `gd shot` scenes | E0–E8, [qa] `TestCtx` and movement stub | 2,500 | Sections 10.1–10.4 green in `tools/gd test`; determinism D1–D5 on macOS + Debian container. |

**Critical path:** E0 -> E1 -> E2 -> {E3, E4} -> {E5, E6} -> E7 -> E8; E9 starts with E2 and grows with each task. E5 and E6 own separate helper files (`sim_economy_docks.gd`, `sim_economy_work.gd`) so that no two agents edit the same file; `SimEconomySystem` keeps the stable public signatures of 3.2 and delegates.

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / open question | Recommended resolution |
|---|---|---|
| R1 | Order-handler / movement API names differ in the orders and movement specs. | The FSMs in 5.9–5.13 are normative; adapters are thin. E5/E6 agents adopt the reconciled master names; no logic change. |
| R2 | `SimCommand` has fewer than five int fields, or `SimEvent` fewer than six. | Ask sim-core for `a..e` and `a..f`; fallback: pack (e.g. `d = angle + (slot << 16)`), documented per command; codes and semantics unchanged. |
| R3 | The bible does not say how the 8-cell build radius is measured. | Chosen: HQ centre to nearest point of the footprint rectangle (5.3). One constant (`build_radius_cells`) plus test 10.1-D; if design prefers edge-to-edge, change `dist2_point_to_rect` input to the HQ rectangle. |
| R4 | Atlas geometry: 3-cell rod spacing with 2-cell radii overlaps by 1 cell, but the counterplay text speaks of "gaps between impact circles". | Keep the bible numbers; linear falloff to zero makes the overlap lens a valley of about 50 % of one rod, which is the practical gap. Flag to design; a later change to radius 1.5 or spacing 4 is a data-only edit. |
| R5 | Trident vs Tempest: drones already inside the zone fire "from inside" and bypass interception, so Trident mostly helps against drones that shoot from outside. | Follow the bible text literally (units entering and weapons fired from inside bypass); document in the tooltip; tune drone leash so they hit from the zone edge in the common case; revisit after S6. |
| R6 | Counterbattery Solution and Counterlaunch Plot are treated as reconnaissance (any location). | Accept; they only expose positions of artillery that just fired. If playtests dislike it, set `vision` to `CURRENT` in `powers.json` (data-only). |
| R7 | Snapshot vs zone semantics of area buffs are underspecified for most of the 19 BUFF powers. | Snapshot everywhere (explicit only for Open Corridor); `mode: "zone"` reserved; unit tests pin the behaviour. |
| R8 | African salvage may snowball. | `salvage.payout_bp` is the single knob; `stat_salvaged` telemetry; S4 target < 15 % of AE income; max 128 live wrecks per match (oldest expire first, deterministic by id) to bound cost. |
| R9 | Economy pacing values (chunk sizes, cap 500, field sizes, regen) are untested. | All in `economy.json`; S1/S7 report income per minute per Collector (design band 600–800) and field lifetimes (a starter field lasts about 16 Collector-cycles = about 11 minutes for one Collector); adjust data only. |
| R10 | Round-robin payment shares scarce credits among all active queues, which can surprise players who want a strict priority. | Document in tooltips; an alternative strict-priority mode is a one-line change of `rr_offset` handling; default kept for fairness (no queue starves). |
| R11 | Single construction queue blocks while a READY structure waits for placement. | Intentional C&C behaviour; UI shows a persistent "READY" blinking icon and event `EVT_STRUCTURE_READY`; AI places immediately. Optional future rule: auto-place when only one legal site exists (not planned). |
| R12 | Friendly-unit ejection at placement needs `eject_units_from_rect` from movement. | Fallback (documented) treats any ground unit as blocking; flag in the movement spec request. |
| R13 | `EF_TEMPORARY` entities (drones, engines, decoys, stations) could be counted by victory, AI threat maps, unit cap or minimap. | Flag semantics are normative (section 4.1); requests 5 and 8 make sim-core/AI respect them; test S7 asserts elimination ignores temporaries. |
| R14 | EMP shutdown state ownership (`shutdown_until`) belongs to abilities. | This domain only reads it; matrix row M10 recommends replacing the field by `abilities.is_operational(e)` / `combat.is_functional`; request 18 covers either form. |
| R15 | Neutral civilian garrison mechanics (capacity 4, fire-from-inside, eviction) have no owner. | Assign to the transports/container domain (request 22); this spec only supplies the def and placement. |
| R16 | Airfield pad repair (3 %/s paid) and pad-offline rearm rule are assumptions (bible: pads "service"/"rearm"). | Keep; both are data (`repair_profiles.json.PAD`, `powered` check) and easy to relax. |
| R17 | Sell refund 50 %, buildup 30 ticks, neutral income 300/min and other design constants are not in the bible. | Recorded in `economy.json`; balance may retune; none is referenced elsewhere as a literal. |
| R18 | Team/alliance semantics for "friendly"/"enemy" tests, shared vision and allied repair payer. | Use `world.rel(a, b)` everywhere (`same team` = `rel != REL_ENEMY`, `REL_NEUTRAL` for pid -1); allied repair is paid by the repairer; allied structures can be repaired by Engineers but never captured. |
| R19 | Superweapons off (`MatchRules`): slot 3 disabled, launcher not buildable. | `FEATURE_OFF`; `init_player` sets `def_idx = -1`; tested. |
| R20 | 256-target cap on area buffs could silently drop targets in giant battles. | Deterministic order (ascending id) and an `EVT`-free log line in debug; two-batch application above 128; raise the cap in data if needed. |
| R21 | Cost/time floors (60 %) are enforced in `GameData`, not here. | Test 10.1-L guards the behaviour from this side; any deviation is reported to the data domain. |
| R22 | Lotus Drone Tender vs Field Repair/Repair Swarm vs paid repair: the bible forbids stacking of repair stations, not of Engineer + station. | Different sources stack (unit + station + wrench); stations never stack with each other; documented and tested. |
| R23 | ARCH stage 7 lists "summons" and stage 9 lists "decoys" among AbilitySystem / ZoneSystem primitives, which overlaps this domain's temporary entities (`SimCompTemp`, `summons.json`) and repair fields. | This spec supplies defs, flags and expiry in `SimStrategicSystem`; if abilities/zones own a generic timed-summon / decoy / heal-field primitive, `spawn_summon`, expiry and `ZONE_REPAIR` are delegated to it and only the flags (`EF_*`), defs and recipes stay here. The reconciler decides; no recipe logic changes. |


### 12.1 Reconciliation matrix against the concurrently published specs (`abilities.md`, `combat.md`, `data_balance.md`, `ai.md`, `net.md`)

Written after reading those specs on 2026-09-29. `M#` rows are the overlaps or naming differences that the reconcilers must settle; "Recommended" is this domain's opinionated proposal. Where a row says *adopt*, this spec's later sections keep the behaviour and only the primitive name changes.

| # | Topic | This spec | Published spec(s) | Recommended resolution |
|---|---|---|---|---|
| M1 | Command codes and wire form | Block **120–149** (6.1), wire `[type, args...]`, AI-aligned names (`BUILD_START`, `TRAIN`, `USE_POWER`, `LAUNCH_SUPERWEAPON`, ...) | core 1–99, combat 40–47, abilities 100–119, net reserves 240–255; AI expects the same intent names from sim-core | Adopt as is. Events: mine 300–499; combat 200–229 and abilities 200–259 overlap each other (their reconciliation item). |
| M2 | Sim-core API names | `entity`, `spawn_*`, `set_owner` in early drafts | abilities and combat both use `get_entity(eid)`, `spawn_entity(def_idx, pid, x, y)`, `remove_entity(eid, cause)`, `change_owner(eid, pid)`, `SimEntity.paid_cost / expire_tick`, `rel()` | Adopt their names (already applied in 3.9 and section 13). |
| M3 | Who executes the 48 powers | Recipes per kind (5.17) + `SimStrategicEffects` | abilities §5.13: `SimPowerFx.validate/apply(world, power_idx, pid, x, y, angle, aux)`; data §4.2 `DefPower.actions` | **PowerSystem = framework** (slots, prerequisites + power, credits, cooldown, warnings, superweapon charge and timeline, calling `validate` then charge then `apply`); **`SimPowerFx` = effect execution.** 5.17/5.18 stay the normative behaviour table; `SimStrategicEffects` shrinks to glue or disappears; `powers.json` (7.3) is superseded by data's `powers.json` (same content, `DefPowerAction` encoding). |
| M4 | Warning zones | `SimWarning` records with `affected_mask` (5.16) | abilities: `zones.spawn_warning(kind, pid, x, y, angle, a, b, ticks)` as zones; AI: `strategic_warnings` "visible to all" (the alias in 3.11 filters by `affected_mask` instead, so the AI sees what a human sees) | Keep `SimWarning` as the sim-state attack record (timeline, mask, payload ids) and mirror it with `zones.spawn_warning` for rendering (`zone_id` stored in the record). The bible restricts the zone to affected players; the audio alert is global. |
| M5 | Strategic damage delivery and Trident packet rule | `emit_packet` + `SimImpactPacket` + `zones.intercept_packet(pk)` (5.20) | combat §3.5/§5.7: `SimProjectiles.spawn_remote/spawn_sweep`, warheads `wh.*` (Perun core 1400 / ring 350, Aurora 40, Helios 60 per dot every 5 ticks), combat calls `zones.intercept_packet(owner_team, x, y)`; abilities: `zones.packet_reduction_bp(shooter_team, x, y)` | **Adopt combat's projectile primitives**: Atlas/Perun/Horizon = `PK_STRIKE` with delays; Helios = `spawn_sweep`; bombardments = `PK_ARC` from off-map; Aurora = strike with EMP warhead. Drop `SimImpactPacket`/`emit_packet`. Damage numbers in 5.21/7.4 become defaults for the combat warhead defs (combat's values win); geometry, counts and delays stay here. |
| M6 | Summons | `SimCompTemp`, `summons.json`, `SimSummonBrain` (5.21, 7.7) | abilities: `SimSummons.spawn(world, def_idx, pid, x, y, parent_eid, flags, life_ticks, driver, ax, ay, ar)`, `SM_*` flags, drivers; data: `summon.*` defs; combat: `CF_SUMMONED`, `CF_ENEMY_ONLY`, `CF_DECOY` | **Adopt abilities' `SimSummons` + drivers** for Tempest, Dragonfall, UAV and decoys; `summons.json` numbers become balance proposals; flags stay normative. |
| M7 | Zones API | `zones.create(kind, ...)`, `blocks_construction`, `intercept_packet` | abilities §3.6: `spawn_zone(def_idx, pid, x, y, angle, param, owner_eid)`, `end_zone`, `active_zones`, `construction_blocked(cx, cy)`, `smoke_factor_bp`, `intercept_mask_at`, `try_intercept`, `packet_reduction_bp`; data `zones.json` | Adopt their API and `zone.*` templates (`zone.repair_station`, `zone.smoke_dust_screen`, `zone.horizon_debris`, `zone.trident_interception`, decoy zones). |
| M8 | Vision | `vision.add_reveal(...)`, `is_explored(pid, ...)` | `add_temp_source(group, shape, x, y, a, b, angle, detect, until_tick, owner_eid)`, `is_cell_explored(group, cx, cy)`, `is_point_visible`, `group_of(pid)`, `decoy_identified` | Adopt. |
| M9 | Timed effects | `apply_timed_effect(id, fx, dur, src_pid, src_key)`, `powers.json.effects` | `SimStatus.apply(world, e, status_idx, source_key, duration_ticks, magnitude_bp)`, `DefEffect`, `SimCombatMods.apply` leases (combat §3.6) | Adopt `SimStatus` via `SimPowerFx`; `src_key` semantics identical (same source refreshes, never stacks). |
| M10 | EMP shutdown / operational state | `SimCompEcon.shutdown_until`, `on_shutdown_started` | abilities `is_operational(e)`, combat `is_functional(world, e)`; abilities polls launcher operational during a warning | Adopt the functions; drop the field; during a warning the strategic system polls `is_operational(launcher)` (equivalent to the hook). |
| M11 | Player windows and research parameters | knob table (4.5), `research_knobs` (7.1) | abilities `SimPlayerFx` (windows, `class_mag`, `production_rate_bp(pid, kind)`, `struct_param(SP_AIRFIELD_PADS / SP_AIRFIELD_REARM_BP)`), data `research_effects.json` + `DefLayer3` (`param_mod`) | Keep only economy-owned parameters here (repair, salvage, reserve, pads) and read them from `DefLayer3`; knobs 10–18 are the **parameter names** the other domains own: `PAD_EXTRA` = `service_pads.pads_n`, `REPAIR_RATE_*` = `repair.rate_pct_per_s`, `SALVAGE_TICKS` = `salvage.action_s`, `SAP_RESERVE_TICKS` = `defense_power_reserve.reserve_s`, `EMP_RECOVERY_*` = `emp_recovery_pct`, `RELAY_*` = `relay_field.*`, `CMD_*` = `command_field.*`, `PROD_RATE_*` = `production_rate_bp`. Production multiplies queue progress by `abilities.production_rate_bp` (Mobilization Order) in addition to the shortage factor. |
| M12 | Repair, salvage and capture execution | order handlers + `repair_step`, `capture_channel`, `salvage_*` (5.10–5.13) | abilities §5.6.7 `SimChannel` (REPAIR_ACTOR, SALVAGE, CAPTURE) with orders doing the approach and `world.economy.try_spend/add`; combat creates wrecks (`KIND_WRECK`) and the catalog expects `wreck_paid_cost`, flags | Numerics are identical (1 %/s, 0.5 % of price per second, 160/100/60 ticks, 20 %). **Recommended: one implementation, `SimChannel`**; this spec's order handlers shrink to approach logic and `SimChannel.begin`, the economy keeps `try_spend/add`, capture progress rules (5.13) and the neutral effects; 10.1-F/H/I remain the shared test vectors. Wreck creation predicate of 5.12 is what combat's cleanup must apply. |
| M13 | SAP defense reserve | FSM in `SimPowerSystem` (5.7) | abilities `SimPlayerFx.reserve_state()`; combat `SimPower.defense_online(world, pid)`; data `defense_power_reserve` player ability | Implement **once, in `SimPowerSystem`** (needs the stage-4 shortage flag and feeds combat at stage 8); abilities' `reserve_state` becomes a read-through; durations 20/35/60 s come from `DefLayer3`. |
| M14 | Deposit representation | `SimDepositTable` arrays (4.6) | data `neutral.salvage_field` (kind `deposit`, entity, `reward.credits`), AI `deposit_ids/deposit_left` over neutral entities | Entity-backed deposits (pid -1) with stock/harvester fields in `SimCompEcon`; `SimDepositTable` stays as the ascending-id index for O(1) queries (rebuilt at setup). |
| M15 | Neutral catalog | six types incl. Field Hospital, Harbor Terminal, periodic depot income (5.13) | data `neutrals.json`: garrison, `power_substation`, `observation_post`, `salvage_depot` (one-time credits), `salvage_field`; `reward` has `income_crps` | Union: keep data's ids/kinds, add `neutral.field_hospital` and `neutral.harbor_terminal`, and give the depot periodic income (`reward.income_crps`); the brief asks for map-control incentives over time. |
| M16 | Economy constants | Collector cap 500, 25 / 50 credits per second, fields 8k / 12k / 20k with idle regrowth (7.1) | data `DefEconomy` proposals: cap 700, 100 / 200 credits per second, field 12,000, regen 0 | Adopt data's field names and units; use this spec's values: with the data proposals one Collector earns about 2,000 credits/min at 12 cells and repays itself in about 40 s, which trivialises the economy (see 5.9 pacing check). |
| M17 | Structure data | `structure_rules.json` (footprint, apron, exit, berth, dock, pads, power class, repair basis) | data `structures.json` (`footprint {w,h,mask}`, `exit`, `queue`, `flags`, `place_mask`, `build_radius_cells`, `max_per_player`) | Fold the extra keys (`apron`, `berth`, `dock`, `pads`, `power_class`, `repair_basis_cost`, `sell_locked_during_warning`) into data's `structures.json`; footprints and queue kinds as data defines them (`infantry/vehicle/aircraft/naval/collector` = Barracks/Factory/Airfield/Dock/Refinery). |
| M18 | Airfield pads | `SimCompProd.pad_ent`, `airfield_pad_*` API (5.14) | combat `SimAirSortie.on_aircraft_spawned(world, e, airfield_id)`, `pads_free`, `on_pads_changed`; abilities `struct_param` | Combat's `SimAirSortie` owns pad occupancy; pad count from `struct_param(SP_AIRFIELD_PADS)`, service/rearm rate from `SP_AIRFIELD_REARM_BP`; drop the pad table, keep the power gate (`pads_online`). |
| M19 | Production hooks | rate table, `apply_research_knobs` (5.4, 5.8) | abilities #11: `SimEffects.on_roster_init`, `on_research_completed`, `abilities.production_rate_bp`, `is_operational(structure)`, `SM_NO_UNIT_CAP`; data `DefLayer3.apply_research` | Production calls those hooks at match start and at research completion; unit cap excludes `EF_TEMPORARY` = `SM_NO_UNIT_CAP`. |
| M20 | Flags and cap accounting | `EF_*` flags, `cap_cost` | data `pop_n`, `UF_*`; combat `CF_*` | One shared flag vocabulary in `DefEnums`; the semantics of `EF_TEMPORARY / DECOY / NO_SALVAGE / NO_CAPTURE / NO_REPAIR` are normative. |
| M21 | AI query names | 3.11 aliases | ai.md §3.3 (`can_build`, `can_place`, `can_train`, `power_status`, `sw_status`, `strategic_warnings`, `construction_state`, `queue_of`, `income_total`, ...) | Aliases provided in 3.11. |
| M22 | Line anchor for LINE targets | `(x, y)` = centre, `angle` = direction of travel; Horizon offsets -5 / 0 / +5 | combat text: Horizon "centred 0/5/10 cells along the line"; abilities: -5 / 0 / +5 around the centre; data: offsets in the committed frame | Centre anchor (UI rotates around the cursor); combat's worked example should read -5 / 0 / +5. |
| M23 | Aurora ownership | EMP burst in 5.21 | abilities `EMP_PULSE`, combat `wh.aurora_pulse` strike with `emp` block | One packet in combat carries damage and EMP durations; abilities apply statuses through the warhead's `emp` block; power only schedules the strike. |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**sim-core**

1. `SimCommand` view over the wire array `[type, args...]` with `ids` and `args: PackedInt32Array` (decoders for the layouts of 6.1); reserve command codes **120–149** and event codes **300–499** for this domain; `CommandSystem` routes 120–131 -> `world.production.handle_command(world, cmd) -> int`, 132–139 -> `world.economy.handle_command`, 140–149 -> `world.strategic.handle_command`; a non-zero return is a `RSN_*` and produces `EVT_CMD_REJECTED`.
2. `SimEvent{type, a, b, c, d, e, f: int}` (six ints).
3. `SimWorld` owns `production: SimProductionSystem`, `economy: SimEconomySystem`, `power: SimPowerSystem`, `strategic: SimStrategicSystem`, `placement`/`life` helpers and `econ_players: Array[SimPlayerEcon]` (indexed by pid); `SimWorld.setup_match` calls `economy.setup/init_player`, `strategic.setup/init_player`, `production.setup`; stage 4 calls `power.update`, which calls `strategic.update`.
4. Hooks (synchronous, in the order of 3.9): `economy.on_entity_added(world, ent)`, `economy.on_entity_died(world, ent, killer_pid, cause)`, `economy.on_entity_removed(world, ent)`, `economy.on_owner_changed(world, ent, old_pid, new_pid)`, `strategic.on_unit_spawned(world, ent)`, `strategic.on_structure_lost(world, ent, cause)`, `strategic.on_shutdown_started(world, ent)`, invoked from the sim-core paths `spawn_entity`, the combat kill path, `remove_entity(eid, cause)` (silent removal) and `change_owner(eid, pid)`; cause bits `DEATH_SELF_DESTRUCT`, `DEATH_SCUTTLE`, `DEATH_FRIENDLY_FIRE`, `DEATH_EXPIRE`.
5. `SimEntity` fields: `comp_econ: SimCompEcon`, `comp_prod`, `comp_wreck`, `comp_temp`; kinds `UNIT`, `STRUCTURE`, `WRECK`; flags `F_DEAD`, `F_SCRIPTED_MOVE` (MovementSystem skips), `F_NO_COLLISION`, `F_NO_FOOTPRINT`; helpers `world.team_of(pid) -> int`, `world.rel(a, b) -> int` (`same_team` = `rel != REL_ENEMY`), `world.get_entity(eid) -> SimEntity`. `SimEntity.paid_cost` and `SimEntity.expire_tick` (already assumed by the combat spec) are the storage of `SimCompEcon.paid_cost` and `SimCompTemp.expire_tick`: exactly one copy must exist, whichever the reconciler picks.
6. `world.struct_grid: IntGrid` (cell -> structure entity id, stamped at spawn/remove); `world.spawn_entity(def_idx, pid, x, y) -> int` for structures, units and summons (this domain sets `st`, `st_until`, `paid_cost`, footprint stamping via the struct grid and component fields right after the spawn returns; footprint origin = top-left cell); the summon path is `SimSummons.spawn(...)` of the abilities spec (see R23).
7. `MatchRules` fields read by this domain: `start_credits`, `unit_cap`, `superweapons: bool`, and per player `handicap` (percent, 50..200; net.md 5.3.6) passed to `economy.init_player`.
8. CleanupSystem: call `world.economy.spawn_wreck(world, dead, killer_pid, cause)` for every dead unit before freeing it; do not expire a wreck whose `comp_wreck.salvage_by != 0`; evaluate elimination with `world.economy.q_can_rebuild(pid)` (ignores `EF_TEMPORARY` / `EF_DECOY` entities); do not double-remove entities whose `SimCompTemp.expire_tick` this domain manages.
9. Checksum: entity walk in id order must call `comp_*.checksum_into(ck)`; per-player and strategic records folded as in section 8.

**data / balance**

10. `GameData.res(pid) -> ResolvedRoster` with the arrays listed in 3.8 (`unit_cost, unit_ticks, unit_available, unit_cap_cost, struct_cost, struct_ticks, struct_available, struct_power, unit_rearm_ticks, repair_cost_bp, repair_rate_bp, research_available, power_of_slot, super_idx, thermal_damage_bp`), recomputed by `GameData.apply_research(pid, r_idx)`; rounding and floors exactly as in 5.2.
11. Host the seven `Def*` loaders (section 2) and include their converted tables in the data-version hash; register the six neutral ids of `neutral_structures.json` as additional structure defs (`s_idx` after the 29 bible structures, sorted-id order) so `SimWorld.setup_match` can spawn `MapData.neutral_spawns` through `spawn_structure(-1, ...)`; compile `powers.json.effects` into `temp_effects[]` (dense indices) and `select` blocks into per-def `PackedByteArray` masks (including the `weapon_subtype: thermal` and `not_moving`/`no_summon` flags).
12. Balance layer fills the nulls of 7.9 (Relay 20 s, Engineer 12 s, Collector 30 s, MCV 45 s, Landing Transport 25 s, all combat unit costs and build times) and applies `unit_overrides` for PD amphibious Collectors (70 % water speed); balance must not define structure footprints (owned by `structure_rules.json`).

**map**

13. `MapData.deposits: Array[{cx, cy, klass}]` (class ids 0/1/2, symmetric per 2/4/6/8 players, none on water); `MapData.neutral_spawns: Array[{type, cx, cy}]` for the six neutral ids; queries `is_buildable(cx, cy)`, `is_passable_ground(cx, cy)`, `is_water(cx, cy)`, `water_body_size(cx, cy) -> int` (cells in the connected water body); placement guidance in 5.13.

**orders / movement**

14. Handler registration for `ORD_HARVEST=30, ORD_RETURN_CARGO=31, ORD_CAPTURE=32, ORD_REPAIR=33, ORD_SALVAGE=34, ORD_DEPLOY_MCV=35` with the `on_begin/on_update/on_end` interface (3.7); `world.orders.issue_internal(ent, type, target_id, x, y)`; idle Collectors auto-issue `ORD_HARVEST(auto)`; player orders replace, never corrupt, `SimCompEcon` state.
15. `world.movement.request_move(ent, x, y, flags) -> bool`, `stop(ent)`, `path_failed(ent) -> bool`, `at_goal(ent) -> bool`, `find_free_cell_near(cell, layer, max_radius) -> int`, `eject_units_from_rect(x0, y0, x1, y1, team) -> void` (deterministic nearest-free-cell order), amphibious Collector movement class.

**combat**

16. `world.combat.apply_area_damage(pk: SimImpactPacket)` with the semantics of 5.20 (team/layer masks, linear falloff, structure multiplier, single 50 % resistance cap including `pre_resist_bp`, smoke ignore flag); `fire_log_query(team_mask, x, y, radius, since_tick, out_ids)`; weapon flag `direct_fire`; tag `thermal` on beam weapons; ordinary summon weapons (Tempest, Dragonfall) call `world.strategic.emit_packet` instead of applying damage directly; point-defense interception (Ural, Arjun, AA) must never target `SimImpactPacket`s; neutral-owned structures and wrecks are never auto-targeted; defense structures fire and detect only if `world.power.defenses_online(pid)` and `structure_online`.

**abilities**

17. `world.abilities.apply_timed_effect(target_id, fx_idx, dur_ticks, src_pid, src_key)` (same `src_key` on the same target refreshes, never stacks; supports `mods`, `flags`, `end_on = MOVE|FIRE|DETECTED`, `heal_bp_per_s`, `dmg_taken_from_team`; no effect chaining is needed because this domain's scheduler applies penalty phases), `world.abilities.on_research_complete(pid, r_idx)`, and reads of knobs 10–14 and 17 through `world.strategic.knob(world, pid, k)` (never writes).
18. EMP/shutdown: entity field `SimCompEcon.shutdown_until` written by abilities, `world.abilities.set_shutdown(id, dur_ticks)` applying `K_EMP_RECOVERY_*` multipliers, and a call to `world.strategic.on_shutdown_started(world, ent)` when a launcher is shut down.
19. Structure auras from data (`aura` blocks): Factory service apron (NAPC), Relay field (NEC), command fields (Han), neutral Field Hospital (`HEAL_AURA` in `neutral_structures.json`); auras honour `structure_online` and `EF_TEMPORARY` rules.

**zones / vision**

20. `world.zones.create(kind, owner, shape, x, y, x2, y2, radius, until_tick, params, bind_ent) -> int` for `ZONE_REPAIR` (rate, target class, group `repair_station` with highest-rate-wins, no self-repair), `ZONE_SMOKE` (disc or capsule, `direct_fire_reduction_bp`), `ZONE_DEBRIS` (land-vehicle speed bp, `no_build`), `ZONE_INTERCEPT` (charges, per-packet cost); `zones.destroy(id)`; `zones.intercept_packet(pk)` (5.20); `zones.blocks_construction(cx, cy) -> bool`; zone bound to an entity ends when it dies.
21. `world.vision.add_reveal(team_mask, shape, x, y, x2, y2, radius, until_tick, detect, bind_ent) -> int`, `remove_reveal(handle)`, `add_reveal_entity(team_mask, id, until_tick)`, `is_explored(pid, cx, cy)`, `is_visible(pid, cx, cy)`, `is_identified(pid, ent_id) -> bool` (decoys identified by detectors); entities flagged `EF_NO_VISION_GRANT` never reveal fog for their owner.

**transports / garrison, air, AI, UI, view, audio, net, QA**

22. Container domain: civilian garrison capacity 4 squads for `neutral.civilian_garrison` (occupants fire out, eviction on destruction); `K_JOINT_LANDING` window -> apply `fx.pd.landing` (damage taken -2000 bp, 120 ticks) to units on disembark with a per-unit anti-refresh timer; `unload_while_moving` effect flag (Mobile Reserve).
23. Air domain: use `airfield_pad_acquire/release/cell/service_rate_bp` (5.14); rearm/repair only when `airfield_service_rate_bp > 0`; reassign aircraft when an Airfield dies.
24. AI: use the query API of 5.22 and section 3 (`can_*`, `q_*`, `find_site`, `slot_info`, `warnings_affecting`, `danger_fraction_bp`); AI must respect `RSN_*`.
25. UI/view/audio: consume the events of section 6.2; ghost from `SimPlacementResult`; warnings from `SimWarning` filtered by `affected_mask`; sidebar states from `QS_*`; never mutate sim state.
26. Net: commands 120–141 are validated again in the sim; data-version hash includes the seven balance files; no floats cross the wire.
27. QA: `TestCtx` helpers `make_world(roster_a, roster_b, seed)`, `tick(n)`, `cmd(...)`, a movement stub with fixed speed, golden-hash file conventions, `gd shot` scenes for the overlays in 10.4.
