# MERIDIAN FRACTURE — Combat Domain Specification

> **Domain:** Combat (weapons, projectiles, damage, targeting, suppression, death/wrecks, aircraft sorties, carrier drones, combat order handlers).
> **Status:** v0.1 proposal for reconciliation. `docs/ARCHITECTURE.md` wins on any conflict; the bible (`Input/meridian_agent_reference/meridian_factions.json`) is canonical for anything it specifies.
> **Notation.** *units* = sub-cell units (1024 per cell); *ticks* = 1/20 s; *bp* = basis points (10000 = 100 %); *bat* = binary angle (4096 per turn, 0 = east, +y = south); *Q8* = fixed-point with 8 fractional bits; `ASSUMPTION(domain)` = an interface I rely on but do not own (all collected in §13); `SEED` = a number I propose that the balance domain may retune.
> **Design stance.** Combat *pulls* nothing from other domains' internals. Other domains *push* buffs to combat as expiring **leases** (`SimCombatMods`), and combat *pushes* requests (deploy, surface, move, turn) to movement/abilities through the small APIs listed in §3.8. Damage is **resolved simultaneously**: shots and impacts enqueue damage during the tick; one flush applies it (§5.6), so update order between shooters never decides who dies first.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**Owned (this spec is the authority):**

* `SimCombatSystem` (pipeline step 8) and its cleanup hook (step 11): target acquisition, turret aim and slew, weapon fire (salvo/burst/reload/ammo/beams), projectile simulation, splash, the damage pipeline, EMP status, suppression, interception (point-defence, zone charges, strategic impact packets), death, wrecks, structure destruction, chain effects, garrison/cargo ejection, aircraft crash.
* `SimCompCombat` (all entities), `SimCompAir` (aircraft and airfields: sortie state machine, pads, rearm), `SimCompCarrier` (drone bays).
* The order handlers `ATTACK`, `ATTACK_MOVE` (targeting/engagement half), `GUARD`, `HOLD`, `FORCE_FIRE`, plus the *idle-engagement* behaviour (auto-acquire, chase leash, return-to-anchor) that stances imply; the combat commands (`CMD_ATTACK`, `CMD_ATTACK_MOVE`, `CMD_GUARD`, `CMD_HOLD`, `CMD_FORCE_FIRE`, `CMD_SET_STANCE`, `CMD_SCUTTLE`, `CMD_RETURN_TO_BASE`).
* Combat events (codes 200–229) and the read-only projectile snapshot the view mirrors.
* Combat data schemas: warheads, projectiles, weapons, mounts, per-entity combat loadouts (armor rows, directional armor, point-defence, death, air, carrier profiles) and the global combat constants file.
* The single write path for **hit points** (`heal`, `kill`, flush) — no other system writes `hp` directly.
* My resolution of the two bible selectors flagged `unresolved_target_domain` (`selector.thermal_beam_weapons`, `selector.ordinary_guided_missiles`) — see §7.7.

**Explicitly NOT owned (I consume, or request from the named domain):**

| Not mine | Owner | How I touch it |
|---|---|---|
| Damage-type / armor-class vocabulary, the type × armor matrix numbers, unit hit points, speeds, costs | balance_framework (`docs/balance/TAXONOMY.md`) / data | read via `GameData` (§3.8, §4.6) |
| Bible modifier resolution engine (layer product, floors/caps for cost/build/reload) | data (`GameData`) | I specify *which resolved fields I need* (§4.6, §7.7) |
| Pathfinding, steering, facing changes, air flight kinematics, takeoff/landing physics | movement | I call `SimMovement` primitives (§3.8) |
| Order queue, order state storage, dispatch | orders (OrderSystem) | it dispatches my order kinds to my handlers (§3.4, §6) |
| Ability primitives: deploy/pack timers, mode switches, camouflage, auras, command fields, repair, shields, smoke, summons, decoys, shelters, portable cover | abilities / zone | they push leases and inbox fields into `SimCompCombat`; I request states via `want_*` |
| Superweapon/support-power scheduling, warnings, charge, target selection | power / abilities | they call `spawn_remote` / `spawn_sweep` (§3.5) and push leases (§3.6) |
| Interception-zone lifetime and geometry (Trident) | zone system | I call `SimZoneSystem.intercept_*` during projectile update (§5.7) |
| Fog, detection, camouflage evaluation | vision | I call `can_see` / `is_known`; I publish `last_fire_tick`, `last_hit_tick` |
| Production queues, pad *structures'* build/placement, unit spawn, rally, unit cap, credit accounting, salvage *action* (8 s) | production / economy / orders | they call my hooks; I expose wreck eligibility and payout API (§3.3) |
| Power balance, SAP defence reserve | power | I read `is_powered` / `defense_online` |
| Rendering, audio, UI, AI decisions, networking | view / audio / ui / ai / net | events (§6), read API (§3.7) |

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

All sim files live under `game/src/sim/combat/` (subfolder of `sim/`; one class per file; ≤ 1500 lines each). Data classes live in `game/src/data/` because `data/` may not depend on `sim/`.

| Path | `class_name` | Responsibility |
|---|---|---|
| `sim/combat/sim_combat_consts.gd` | `SimCombatConsts` | Every enum, bit flag, event/command/order code and tuning constant default (§4.1). No logic. |
| `sim/combat/sim_comp_combat.gd` | `SimCompCombat` | Per-entity combat state: target, mounts, statuses, leases, wreck fields, "inbox" fields written by other domains (§4.3). |
| `sim/combat/sim_comp_air.gd` | `SimCompAir` | Aircraft sortie state **and** airfield pad table (role by `is_airfield`). |
| `sim/combat/sim_comp_carrier.gd` | `SimCompCarrier` | Drone bays, wing selection, replacement timers. |
| `sim/combat/sim_combat_system.gd` | `SimCombatSystem` | System facade: phase orchestration, lifecycle hooks, health API, fire-control API, read API, checksum. Owns scratch buffers. |
| `sim/combat/sim_combat_mods.gd` | `SimCombatMods` | Lease slots (buff/debuff/flags with expiry and same-source dedupe); aggregate cache. |
| `sim/combat/sim_damage.gd` | `SimDamage` | Damage pipeline (`compute`), damage queue, flush/apply, EMP + suppression status application, alerts, coalesced `EV_HIT`. |
| `sim/combat/sim_weapons.gd` | `SimWeapons` | Mount aim/slew, arcs, gating, salvo/burst/reload/ammo, hitscan resolution, beam state, muzzle geometry. |
| `sim/combat/sim_projectiles.gd` | `SimProjectiles` | Struct-of-arrays projectile pool; kinds bullet/missile/arc/bomb/strike/sweep; swept collision; detonation; splash; interception hooks; view snapshot. |
| `sim/combat/sim_targeting.gd` | `SimTargeting` | Filters, scoring, scan scheduling, stances, retarget, focus, retaliation, assist, overkill guard. |
| `sim/combat/sim_order_combat.gd` | `SimOrderCombat` | Combat command application; order handlers (`idle`, `attack`, `attack_move`, `guard`, `hold`, `force_fire`). |
| `sim/combat/sim_death.gd` | `SimDeath` | `kill`, death profiles, occupants/cargo, wrecks, salvage API, chain effects, aircraft crash, cleanup pass. |
| `sim/combat/sim_air_sortie.gd` | `SimAirSortie` | Sortie state machine, attack-run styles, pads, rearm, patrol, forced return, fuel. |
| `sim/combat/sim_carrier_ops.gd` | `SimCarrierOps` | Drone launch, recall, docking, replacement, wing switch. |
| `data/def_warhead.gd` | `DefWarhead` | Compiled warhead (damage, type, splash, flags, EMP). |
| `data/def_projectile.gd` | `DefProjectile` | Compiled projectile template (kind, speed, homing, arc, sweep). |
| `data/def_weapon.gd` | `DefWeapon` | Compiled weapon (projectile+warhead refs, filters, range, timing, ammo, accuracy, gating). |
| `data/def_mount.gd` | `DefMount` | Mount geometry and kind. |
| `data/def_combat.gd` | `DefCombat` | Per-entity-def combat block: mounts, priority, armor rows, directional armor, point defence, pads, refs to death/air/carrier profiles. |
| `data/def_death.gd` | `DefDeath` | Death profile. |
| `data/def_air.gd` | `DefAir` | Aircraft profile (style, fuel, rearm, attack-run geometry). |
| `data/def_carrier.gd` | `DefCarrier` | Carrier profile (bays, wings, timings). |
| `data/def_combat_compiler.gd` | `DefCombatCompiler` | JSON → int-only defs; unit conversion; validation; feeds the data hash. |
| `tests/test_combat_*.gd`, `tests/fixtures/combat_fixture.gd` | `TestCombat*`, `CombatFixture` | §10. |

Data files (all under `game/data/balance/`, §7): `combat_rules.json`, `combat_warheads.json`, `combat_projectiles.json`, `combat_weapons.json`, `combat_loadouts.json`.

---
## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

`SimWorld` owns one `combat: SimCombatSystem`; `world.projectiles` is an alias of `world.combat.projectiles`. No combat class stores a `SimWorld` reference (avoids RefCounted cycles); every entry point receives `world`. Integer division is written `@warning_ignore("integer_division")` and only on non-negative operands unless stated.

### 3.1 Call and tick order

```
Tick t (ARCHITECTURE §6 numbering)
 1 CommandSystem    SimOrderCombat.apply_command(world, cmd)            codes 40..47; validated at EXECUTION time; creates orders / sets stance
 5 OrderSystem      SimOrderCombat.step(world, e, ord) -> OS_*          for ORD_ATTACK..ORD_FORCE_FIRE (40..44)
                    SimOrderCombat.step_idle(world, e)                  for armed entities whose order queue is empty
 6 MovementSystem   reads SimCombatSystem.suppression_speed_bp(e); writes cc.ext_moving
 7 AbilitySystem    SimCombatMods.apply(...) leases; writes cc.ext_deployed / cc.ext_mode; reads cc.want_* and last_*_tick
 8 SimCombatSystem.update(world):
     P1 upkeep       status timers, lease-cache refresh, crash steps and crash impacts, orphan-drone timers
     P2 air/carrier  SimAirSortie.update per aircraft (id order; includes rearm progress at pads), SimCarrierOps.update per carrier
     P3 scans        budgeted target scans (round-robin cursor over armed entities)
     P4 weapons      per armed entity: validate target (urgent rescan if lost), aim/slew, gating, fire -> hitscan resolves, projectiles spawn, beams tick -> enqueue damage
     P5 projectiles  move, swept test, interception, detonate/splash -> enqueue damage; sweep beams tick
     P6 flush        apply queued damage in queue order; statuses; deaths (SimDeath.kill); coalesced events; retaliation resolution
 9 ZoneSystem       zone lifetimes (interception charges were consumed in P5 of this tick)
10 VisionSystem     reads last_fire_tick / last_hit_tick
11 CleanupSystem    SimCombatSystem.cleanup(world): expire wrecks, finish dying entities, hand removals to world
```
Any system may call `kill()` at any step; it is idempotent. Damage never bypasses the queue except `heal`.

**Hook matrix (who calls whom, at which step)**

| Domain (step) | Calls into combat | Combat calls into it | Data flowing |
|---|---|---|---|
| orders (1, 5) | `apply_command`, `step`, `step_idle`, `on_order_start`, `clear_target` | — | orders own the queue; combat handlers only read/write the `ord` scratch fields |
| production / economy / power (2-4) | `on_spawn` (via `SimWorld`), `SimAirSortie.on_aircraft_spawned`, `on_pads_changed`, `try_salvage`, `heal` (repairs), `is_functional`, `kill` (sell excluded) | `SimEconomy.try_spend`, `SimPower.is_powered`, `defense_online` | `paid_cost` set at completion; EMP-shut structures are non-functional |
| movement (6) | `suppression_speed_bp`, `is_alive` | `move_to`, `move_to_range`, `stop`, `turn_to`, `air_*` (issued at steps 5 and 8, executed next tick) | movement writes `cc.ext_moving`, `e.vx/vy`; EMP never blocks movement |
| abilities (7) | `SimCombatMods.apply/clear_key`, `lock_weapons`, `clear_suppression`, `heal`, `kill(CAUSE_EXPIRE)`, `spawn_remote/spawn_sweep` | — | abilities write `ext_deployed`, `ext_mode`; read `want_*`, `last_fire_tick`, `last_hit_tick`, `is_suppressed` |
| zone (9) | — | `intercept_ordinary`, `intercept_packet` during step 8 | charges are consumed in step 8; lifetimes expire in step 9 |
| vision (10, stride 2) | reads `last_fire_tick`, `last_hit_tick`, `is_alive` | `can_see`, `is_known`, `decoy_identified` (state from the previous vision update, at most 2 ticks old, identical on all clients) | dead entities leave vision at once |
| cleanup (11) | `cleanup(world)` | `SimWorld.remove_deferred` | wrecks expire, dying entities finish |

### 3.2 Lifecycle hooks (called by `SimWorld`)

```gdscript
class_name SimCombatSystem extends RefCounted

var projectiles: SimProjectiles        # public READ-ONLY for view/audio (fields in §4.4)
var armed_ids: PackedInt32Array        # ascending ids of entities with >=1 mount, or an air/carrier component
var wreck_ids: PackedInt32Array        # ascending ids of live KIND_WRECK entities (AE "Survey Network" reads this)
var scan_cursor: int = 0               # round-robin position in armed_ids (checksummed)
var status_ids: PackedInt32Array       # ascending ids with a live timer (EMP, weapon lock, suppression, dying)
var air_ids: PackedInt32Array          # ascending ids of aircraft/drones (not airfields)
var carrier_ids: PackedInt32Array      # ascending ids of carriers
var counters: PackedInt32Array         # deterministic perf counters: scans, shots, impacts, damage instances, live projectiles

func _init() -> void
func update(world: SimWorld) -> void                                   # pipeline step 8
func cleanup(world: SimWorld) -> void                                  # pipeline step 11; called by SimCleanupSystem
func on_spawn(world: SimWorld, e: SimEntity) -> void                   # allocate e.combat (always) / e.air / e.carrier; mounts full, ammo full, stance default; insert armed_ids
func on_remove(world: SimWorld, e: SimEntity) -> void                  # just before removal: unlink pads/bays/targets, drop from armed_ids/wreck_ids
func on_owner_changed(world: SimWorld, e: SimEntity, old_owner: int) -> void   # capture: clear target/orders link/leases, reset stance, retarget
func hash_into(cs: Checksum) -> void                                   # §8
func debug_string(world: SimWorld, e: SimEntity) -> String             # desync dumps / tests only
```

### 3.3 Health, death, wrecks (the only writers of `SimEntity.hp`)

```gdscript
# --- methods of SimCombatSystem ---
func heal(world: SimWorld, e: SimEntity, amount: int) -> int
    ## Adds up to `amount` hp (>0), never above hp_max, ignored if CF_DEAD. Returns hp actually restored. Emits nothing.

func rescale_hp(e: SimEntity, new_hp_max: int) -> void
    ## Called by data/research when hp_max changes (e.g. Circular Armor): hp = half_up(hp * new_hp_max / old_hp_max), min 1 if alive; sets e.hp_max.

func kill(world: SimWorld, e: SimEntity, cause: int, killer_id: int, killer_pid: int) -> void
    ## Idempotent. cause = CAUSE_*. killer_id/killer_pid = -1 when none. Full sequence in §5.11.

func scuttle(world: SimWorld, e: SimEntity) -> void              # kill(cause = CAUSE_SCUTTLE, -1, -1); no wreck, no salvage

func wreck_can_be_salvaged_by(world: SimWorld, wreck: SimEntity, salvager_pid: int) -> bool
    ## true iff WF_SALVAGEABLE and not consumed and team(salvager) != team(wreck.owner_pid) (bible: allied wrecks pay nothing).
    ## The faction trait (African Empire only) and the 8 s / 5 s action are the caller's (economy/orders) responsibility.

func try_salvage(world: SimWorld, wreck_id: int, salvager_pid: int, payout_pct: int) -> int
    ## Atomic: if eligible, marks the wreck consumed, schedules its removal (EV_WRECK_REMOVE reason 2) and returns
    ## payout = half_up(wreck.wreck_value * payout_pct / 100) (bible: 20). Returns -1 if not eligible.
```

### 3.4 Fire control and orders

```gdscript
# --- methods of SimCombatSystem ---
func set_stance(e: SimEntity, stance: int) -> void                      # ST_*; clears hold_pos only via SimOrderCombat.on_order_start
func set_target(world: SimWorld, e: SimEntity, target_id: int, src: int) -> bool   # TS_*; validates can_engage; false if refused
func set_ground_target(e: SimEntity, x: int, y: int) -> void            # force-fire point; TS_FORCE
func clear_target(e: SimEntity, keep_auto: bool = false) -> void        # drops beams and salvo remainder
func lock_weapons(e: SimEntity, until_tick: int) -> void                # max(existing, until); Aurora-class / Surge / Capacitor cooldown / repair lock
func clear_suppression(e: SimEntity) -> void                            # Coordinated Advance: "existing suppression is removed"
func can_attack(world: SimWorld, shooter: SimEntity, target: SimEntity, force: bool = false) -> bool   # UI cursor / command validation / AI

class_name SimOrderCombat extends RefCounted
const OS_RUNNING: int = 0
const OS_DONE: int = 1
const OS_FAILED: int = 2
static func apply_command(world: SimWorld, cmd: SimCommand) -> void
static func step(world: SimWorld, e: SimEntity, ord: SimOrder) -> int   # dispatch on ord.kind (ORD_ATTACK..ORD_FORCE_FIRE)
static func step_idle(world: SimWorld, e: SimEntity) -> void
static func on_order_start(world: SimWorld, e: SimEntity, kind: int) -> void   # clears hold_pos/ground target when a non-combat order begins
```

### 3.5 Spawning projectiles for powers, superweapons and chain effects (used by power/abilities/death)

```gdscript
class_name SimProjectiles extends RefCounted
func spawn_remote(world: SimWorld, owner_pid: int, owner_id: int, proj_idx: int, wh_idx: int,
        ox: int, oy: int, tx: int, ty: int, delay_ticks: int, dmg_bp: int, inst_flags: int) -> int
    ## Creates a projectile with no shooter entity. PK_STRIKE: detonates at (tx,ty) exactly delay_ticks from now (ox,oy only used for view + zone crossing).
    ## PK_ARC: launches after delay_ticks from (ox,oy) and flies to (tx,ty) (flight per §5.4). Returns serial, or -1 if the pool refused it
    ## (strategic/remote projectiles use the reserved slots and are refused only when reserve is exhausted). dmg_bp = attacker multiplier snapshot (10000 = none).
func spawn_sweep(world: SimWorld, owner_pid: int, owner_id: int, proj_idx: int, wh_idx: int,
        ax: int, ay: int, bx: int, by: int, delay_ticks: int, duration_ticks: int) -> int
    ## Helios-style swept line beam (§5.4.7). Returns serial or -1.
func live_count() -> int
```
Worked usage: Atlas = three `spawn_remote(..., PK_STRIKE strategic ...)` at the selected point and ±3 cells; Perun = two strikes at the same centre (core disc + ring annulus warheads); Horizon = three strikes centred 0/5/10 cells along the line with delays 0/90/180; Aurora = one strike with the EMP warhead; Counterbattery/Tremor/Counterlaunch = N `PK_ARC` shells from an off-map origin so Trident can see them cross its boundary.

**Aircraft and carrier entry points** (called by production, orders, abilities):
```gdscript
class_name SimAirSortie extends RefCounted
static func on_aircraft_spawned(world: SimWorld, e: SimEntity, airfield_id: int) -> void   # production: place on a free pad (AIR_PARKED, layer GROUND); airfield_id -1 = carrier drone
static func on_pads_changed(world: SimWorld, airfield: SimEntity) -> void                  # after Dispersed Runways or a pad-count change
static func assign_mission(world: SimWorld, e: SimEntity, mission: int, target_id: int, x: int, y: int, r: int) -> bool   # order handlers; false if no fuel or no usable ammo
static func update(world: SimWorld, e: SimEntity) -> void                                 # internal, P2
class_name SimCarrierOps extends RefCounted
static func request_wing(world: SimWorld, e: SimEntity, wing: int) -> void                # abilities (Shogun wing/mode switch)
static func update(world: SimWorld, e: SimEntity) -> void                                 # internal, P2
```

### 3.6 Leases — how abilities, zones and research-auras change combat numbers

```gdscript
class_name SimCombatMods extends RefCounted
static func apply(world: SimWorld, e: SimEntity, key: int, stat: int, bp: int, filter: int, ticks: int) -> void
    ## Creates/refreshes the lease identified by (key, stat) for `ticks` ticks. Same (key,stat) never stacks: an existing live lease keeps the
    ## larger |bp| and the later expiry. Different keys add within the "research/temporary" layer (§5.6). Full: evict earliest expiry; if the new lease
    ## expires before every slot, it is dropped. Aura owners re-apply every N (<=4) ticks with ticks = N + 2; no-op fast path when nothing changes.
static func clear_key(e: SimEntity, key: int) -> void
static func sum_bp(cc: SimCompCombat, stat: int, tick: int, dtype: int = -1, dc: int = 0) -> int   # additive delta; filter-matched when dtype >= 0
static func has_flag(cc: SimCompCombat, stat: int, tick: int) -> bool                            # STAT_FLAG_*
```
`filter` packing and stat ids: §4.1. Catalogue of every bible effect with its exact lease call: §5.14.

### 3.7 Read/query API (movement, abilities, vision, UI, AI, view)

```gdscript
# --- methods of SimCombatSystem ---
func is_alive(e: SimEntity) -> bool                                  # not CF_DEAD
func is_functional(world: SimWorld, e: SimEntity) -> bool            # alive, not EMP-shut (unless immune), powered if def.needs_power (defense_online for SAP reserve)
func weapons_online(world: SimWorld, e: SimEntity) -> bool           # is_functional AND tick >= wlock_until
func is_suppressed(e: SimEntity) -> bool                             # Han command-field providers, movement, UI
func suppression_speed_bp(e: SimEntity) -> int                       # 7500 while suppressed, else 10000 (movement multiplies its speed)
func ticks_since_combat(world: SimWorld, e: SimEntity) -> int        # tick - max(last_fire, last_hit, last_dealt); "out of combat 6 s" auras
func range_max_eff(world: SimWorld, e: SimEntity, mount: int = -1) -> int   # units; mount -1 = longest usable; UI range rings, AI, order handlers
func dp100(world: SimWorld, shooter: SimEntity, target: SimEntity) -> int   # expected damage per 100 ticks incl. matrix (AI/target scoring); no mods from other side
func range_min_of(world: SimWorld, e: SimEntity, mount: int = -1) -> int   # units; UI minimum-range ring
func ammo_of(e: SimEntity, mount: int) -> int                        # remaining salvos (-1 = infinite)
```
The view iterates `world.projectiles` arrays directly (§4.4); there is no per-owner projectile query.
`SimAirSortie` read helpers: `pads_free(world, airfield) -> int`, `pad_of(e) -> int`, `sortie_state(e) -> int`; `SimCarrierOps`: `drones_docked(e) -> int`, `drones_away(e) -> int`.

### 3.8 Consumed interfaces (every line is an ASSUMPTION on the domain named in its group header; the numbered asks are in §13)

```gdscript
# sim_core -------------------------------------------------------------------------------------------------------------
SimWorld: tick: int; rng: SimRng; data: GameData; map: MapData; combat: SimCombatSystem; players: Array[SimPlayer]
SimWorld.get_entity(id: int) -> SimEntity                      # null if never existed / removed; ids are never reused
SimWorld.spawn_unit(def_idx: int, owner: int, x: int, y: int, facing: int, flags: int) -> SimEntity
SimWorld.spawn_raw(kind: int, def_idx: int, owner: int, x: int, y: int, facing: int) -> SimEntity   # used for KIND_WRECK
SimWorld.remove_deferred(id: int, at_tick: int) -> void       # CleanupSystem removes at step 11 of tick >= at_tick
SimWorld.emit(type: int, x: int, y: int, a: int, b: int, c: int, d: int, e: int, f: int) -> void
SimWorld.rel(pid_a: int, pid_b: int) -> int                    # REL_SELF=0 REL_ALLY=1 REL_ENEMY=2 REL_NEUTRAL=3 (O(1) table); team_of(pid)
SimRng.next_int(n: int) -> int                                 # uniform [0, n), n >= 1
SpatialHash: query_circle(x: int, y: int, r: int, out: PackedInt32Array) -> int   # clears out, ids in deterministic order, returns count
SimEntity: id, def_idx, kind, owner, x, y, prev_x, prev_y, vx, vy, facing, layer, hp, hp_max, radius, container_id, paid_cost,
           expire_tick, flags, combat, air, carrier
Fp: atan2(y: int, x: int) -> int (bat 0..4095), dist(dx: int, dy: int) -> int, isqrt(n: int) -> int, sin(a: int) -> int / cos(a: int) -> int (Q16)
# movement -------------------------------------------------------------------------------------------------------------
SimMovement.move_to(world, e, x, y, flags) -> void ; move_to_range(world, e, tx, ty, range_units: int) -> void ; stop(world, e) -> void
SimMovement.turn_to(world, e, facing_bat: int) -> void ; is_moving(e) -> bool
SimMovement.air_fly_to(world, e, x, y) ; air_orbit(world, e, cx, cy, r) ; air_hover(world, e) ; air_face(world, e, bat) ; air_takeoff(world, e) ; air_land_at(world, e, x, y) ; air_at_goal(e) -> bool
# vision ---------------------------------------------------------------------------------------------------------------
SimVision.can_see(world, pid: int, target: SimEntity) -> bool      # fog + camouflage + detection, current
SimVision.is_known(world, pid: int, target: SimEntity) -> bool     # visible now, or a remembered structure ghost (attack orders on fogged structures)
SimVision.decoy_identified(world, pid: int, target: SimEntity) -> bool
# power / economy ------------------------------------------------------------------------------------------------------
SimPower.is_powered(world, e) -> bool ; SimPower.defense_online(world, pid) -> bool          # honours SAP 20/35 s reserve
SimEconomy.try_spend(world, pid: int, credits: int) -> bool                                  # carrier drone replacement
# zone system ----------------------------------------------------------------------------------------------------------
SimZoneSystem.intercept_ordinary(world, owner_team: int, x0: int, y0: int, x1: int, y1: int, sx: int, sy: int, proj_flags: int) -> int   # zone id that consumed one charge, or -1
SimZoneSystem.intercept_packet(world, owner_team: int, x: int, y: int) -> int                # reduction bp (0 or 5000); consumes 8 charges when it reduces
# data -----------------------------------------------------------------------------------------------------------------
GameData: warheads: Array[DefWarhead]; projectiles: Array[DefProjectile]; weapons: Array[DefWeapon]; defs (unit/structure) with .combat: DefCombat,
          .armor_class, .tags (bit mask), .radius, .layer, .needs_power, .garrison_fire
GameData.dmg_matrix_bp: PackedInt32Array                       # [dtype * n_armor + armor_class], bp
GameData.pmount(pid: int, def_idx: int, mount: int) -> PackedInt32Array   # resolved static mount stats, fields PM_* (§4.6)
GameData.presist(pid: int, def_idx: int) -> PackedInt32Array   # static resistance rows, stride 4 (§4.6)
```

### 3.9 Memory ownership

| Memory | Owner | Lifetime / rule |
|---|---|---|
| `SimCompCombat`, `SimCompAir`, `SimCompCarrier` | the entity; allocated in `on_spawn`, freed in `on_remove` | other domains write only the documented *inbox* and lease fields |
| `armed_ids`, `wreck_ids`, damage queue, projectile pool arrays, scratch buffers (`_cand`, `_victims`) | `SimCombatSystem` | scratch buffers are cleared on each use, never hold state across calls |
| `world.events` | `SimWorld` | combat only appends via `emit` |
| Def objects (`Def*`) | `GameData` | immutable after load; combat never mutates them |
| Resolved per-player tables | `GameData` | rebuilt on research completion; combat reads on every use (no caching across ticks) |

---
## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enumerations, bit flags and constants (`SimCombatConsts`; each is `const NAME: int = value`)

```
# --- layers / kinds (ASSUMPTION(sim_core); mirrored here, sim_core's numbers win) ---
LAYER_GROUND 0, LAYER_AIR 1, LAYER_SURFACE 2, LAYER_UNDERWATER 3
KIND_UNIT 0, KIND_STRUCTURE 1, KIND_WRECK 2                     # KIND_WRECK is requested from sim_core (§13-1)
REL_SELF 0, REL_ALLY 1, REL_ENEMY 2, REL_NEUTRAL 3

# --- target filter bits (DefWeapon.target_mask). Structures are KIND_STRUCTURE regardless of layer ---
TF_GROUND 1      # unit on LAYER_GROUND (infantry, vehicles, PARKED aircraft)
TF_AIR 2         # LAYER_AIR
TF_SURFACE 4     # LAYER_SURFACE (ships, amphibious vehicles currently on water, surfaced submarines)
TF_UNDERWATER 8  # LAYER_UNDERWATER (only anti-submarine weapons carry this bit)
TF_STRUCTURE 16
TF_WRECK 32      # never in a weapon mask; reachable only by force-fire (§5.10.6)

# --- damage types: FROZEN seed ids (ARCHITECTURE Appendix A); TAXONOMY.md may append ids >= 7, never renumber 0..6 ---
DT_BULLET 0, DT_EXPLOSIVE 1, DT_BEAM 2, DT_THERMAL 3, DT_RAIL 4, DT_KINETIC 5, DT_EMP 6
DT_MASK_ALL_WEAPON 0x7FBF      # every type bit (0..14) except DT_EMP; used by "weapon damage" reductions (Steel Advance, ...)
# THERMAL is its own id; the "beam family" resistance key covers {DT_BEAM, DT_THERMAL}: GameData.dt_cover_mask[key] (TAXONOMY)

# --- delivery of the primary hit, and damage-class bits carried by every damage INSTANCE ---
DELIV_DIRECT 0, DELIV_INDIRECT 1, DELIV_STRATEGIC 2
DC_DIRECT 1, DC_INDIRECT 2, DC_SPLASH 4, DC_STRATEGIC 8       # a splash victim of an artillery shell = DC_INDIRECT|DC_SPLASH
# --- resistance / lease filter packing (fits int32) ---
FILTER(types, req, forbid) = types | (req << 15) | (forbid << 19)          # types: bits 0..14; req, forbid: 4-bit DC masks
match(filter, dtype, dc) = ((filter & (1 << dtype)) != 0) and (((filter >> 15) & 15 & dc) == ((filter >> 15) & 15)) and (((filter >> 19) & 15 & dc) == 0)
FILTER_ALL_WEAPON = DT_MASK_ALL_WEAPON
FILTER_DIRECT_ONLY = DT_MASK_ALL_WEAPON | (DC_DIRECT << 15) | ((DC_SPLASH | DC_INDIRECT | DC_STRATEGIC) << 19)   # Dust Screen

# --- projectile kinds / flags ---
PK_HITSCAN 0, PK_BULLET 1, PK_MISSILE 2, PK_ARC 3, PK_BOMB 4, PK_STRIKE 5, PK_SWEEP 6, PK_BEAM 7   # PK_BEAM tags a continuous-beam weapon (no pool entry)
PF_GUIDED 1              # selector.ordinary_guided_missiles member (Pakistan +20 % flight speed)
PF_APS_INTERCEPTABLE 2   # Ural / Arjun / Bear / Gaj point defence may destroy it
PF_ZONE_INTERCEPTABLE 4  # Trident: "ordinary missile or artillery shell"
PF_BLOCKED_BY_HOSTILES 8 # bullet stops at the first hostile hit-circle on its path (optional; default off)
PF_AIRBURST_ON_EXPIRE 16 # detonate at end of life/flight in place (flak, AA missiles)
PF_STRATEGIC 32          # template belongs to a superweapon/summon (never modified by unit modifiers; excluded from Pakistan bonus)
PI_PACKET 1, PI_FORCED 2, PI_SUPPRESSIVE 4, PI_CHAIN 8, PI_REMOTE 16, PI_ENEMY_ONLY 32       # per-instance flags in the pool; PI_ENEMY_ONLY is set on every projectile fired by a CF_ENEMY_ONLY (summoned) shooter

# --- mounts, stances, target sources ---
MK_TURRET 0, MK_FIXED 1, MK_HULL 2
WC_ANTI_AIR 1, WC_ANTI_SUB 2, WC_ANTI_ARMOR 4, WC_ANTI_INF 8, WC_ARTILLERY 16, WC_ANTI_STRUCT 32     # DefWeapon.wclass
COND_ON_WATER 1                                                                                       # resistance row condition
AM_MOVE 0, AM_ENGAGE 1                                                                                # ORD_ATTACK_MOVE states
ST_AGGRESSIVE 0, ST_DEFENSIVE 1, ST_HOLD_FIRE 2, ST_GUARD 3
TS_NONE 0, TS_AUTO 1, TS_ORDER 2, TS_FORCE 3, TS_RETAL 4, TS_GUARD 5

# --- SimCompCombat.cflags ---
CF_DEAD 1, CF_DYING 2, CF_UNTARGETABLE 4 (inside container / docked), CF_SUMMONED 8, CF_DECOY 16, CF_INVULNERABLE 32,
CF_NO_WRECK 64, CF_SCUTTLED 128, CF_HAS_AA 256, CF_HAS_ASW 512, CF_SUPPRESSIBLE 1024 (infantry), CF_ENEMY_ONLY 2048 (summoned attackers)

# --- lease stats (SimCombatMods) ---
STAT_DMG_OUT 0      # attacker: +bp on weapon damage dealt (temporary layer)
STAT_RELOAD 1       # attacker: +bp on reload interval (negative = faster)
STAT_RANGE 2        # attacker: +bp on weapon range
STAT_TAKEN 3        # defender: +bp RESISTANCE (positive = less damage), filtered by (types, dc)
STAT_MARK 4         # defender: attacker-side bonus vs this entity; filter = team bit mask (bits 0..7) | 256 (ground weapons only)
STAT_EMP_RECOVER 5  # defender: +bp shortening of EMP durations
STAT_SUP_RECOVER 6  # defender: +bp faster suppression recovery
STAT_REARM_RATE 7   # airfield: +bp rearm speed
STAT_FLAG_EMP_IMMUNE 8, STAT_FLAG_SUP_IMMUNE 9             # boolean leases (bp ignored)

# --- damage instance flags ---
DF_NONLETHAL 1, DF_FORCED 2, DF_SUPPRESSIVE 4, DF_PACKET 8, DF_CHAIN 16, DF_CRASH 32

# --- death ---
DK_NONE 0, DK_VEHICLE 1, DK_INFANTRY 2, DK_CRASH 3, DK_AIR_EXPLODE 4, DK_SINK 5, DK_STRUCTURE 6, DK_DRONE 7, DK_SILENT 8
CAUSE_DAMAGE 0, CAUSE_SCUTTLE 1, CAUSE_EXPIRE 2, CAUSE_ORPHAN 3, CAUSE_CARGO 4, CAUSE_RESIGN 5
CARGO_DIE 0, CARGO_EJECT_HURT 1, CARGO_EJECT 2
EC_INFANTRY 1, EC_VEHICLE 2, EC_AIRCRAFT 4, EC_SHIP 8, EC_STRUCTURE 16                     # DefWarhead.emp_class_mask
WF_SALVAGEABLE 1, WF_CONSUMED 2

# --- air ---
AIR_PARKED 0, AIR_TAKEOFF 1, AIR_TRANSIT 2, AIR_ATTACK 3, AIR_PATROL 4, AIR_RETURN 5, AIR_LANDING 6, AIR_REARM 7, AIR_NO_BASE 8, AIR_DOCKED 9
AP_APPROACH 0, AP_RUN 1, AP_RELEASE 2, AP_EGRESS 3, AP_HOVER 4, AP_PURSUE 5
AS_HOVER 0, AS_MISSILE_RUN 1, AS_BOMB_RUN 2, AS_STRAFE 3, AS_DOGFIGHT 4, AS_NONE 5
MI_NONE 0, MI_ATTACK 1, MI_ATTACK_MOVE 2, MI_PATROL 3, MI_MOVE 4, MI_RETURN 5, MI_ESCORT 6
HOME_AIRFIELD 0, HOME_CARRIER 1
BAY_EMPTY 0, BAY_DOCKED 1, BAY_AWAY 2, BAY_REARM 3

# --- orders / commands (block reservations requested in §13-3) ---
ORD_ATTACK 40, ORD_ATTACK_MOVE 41, ORD_GUARD 42, ORD_HOLD 43, ORD_FORCE_FIRE 44
CMD_ATTACK 40, CMD_ATTACK_MOVE 41, CMD_GUARD 42, CMD_HOLD 43, CMD_FORCE_FIRE 44, CMD_SET_STANCE 45, CMD_SCUTTLE 46, CMD_RETURN_TO_BASE 47

# --- mount state layout inside SimCompCombat.mnt (stride MS = 10) ---
MS 10; M_CD 0, M_BURST 1, M_NEXT 2, M_AMMO 3, M_ANGLE 4, M_TARGET 5, M_AIM_SINCE 6, M_BEAM 7, M_SHOTS 8, M_DOT 9
MAX_MOUNTS 4, MAX_MODS 10, MODS_STRIDE 5
```

Tuning constants (defaults; overridable in `combat_rules.json` and part of the data hash; §7.1): `SCAN_INTERVAL_UNIT 6`, `SCAN_INTERVAL_STRUCT 8`, `SCAN_INTERVAL_AIR 4`, `RESCORE_INTERVAL 20`, `SCAN_BUDGET_BASE 24` (+4 per 64 armed entities), `SCAN_CAND_CAP 48`, `ACQ_MARGIN 1024`, `PRIO_TIER 4096`, `STICK_BONUS 2048`, `FOCUS_BONUS 1024`, `FOCUS_TTL 20`, `THREAT_BONUS 2048`, `WOUNDED_MAX 1024`, `RETAL_MARGIN 1024`, `OVERKILL_PENALTY 4096`, `HIDE_GIVEUP_AUTO 20`, `HIDE_GIVEUP_ORDER 200`, `ASSIST_RADIUS 8192`, `ASSIST_COOLDOWN 20`, `LEASH_AGGRESSIVE 8192`, `LEASH_DEFENSIVE 3072`, `LEASH_GUARD 6144`, `GUARD_RADIUS 10240`, `RETURN_SLACK 2048`, `APPROACH_BP 9000`, `SUP_HITS 3`, `SUP_WINDOW 40`, `SUP_TAIL 60`, `SUP_SPEED_BP 7500`, `TAKEN_MIN_BP 5000`, `TAKEN_MAX_BP 20000`, `CHIP_FLOOR_BP 500`, `WRECK_TICKS 1200`, `WRECK_HP_MIN 150`, `PROJ_POOL 4096`, `PROJ_STRATEGIC_RESERVE 256`, `PROJ_SOFT_CAP 3072`, `CHAIN_CAP 64`, `ALERT_COOLDOWN 200`, `ALERT_DIST 15360`, `AIM_TOL_DEFAULT 24`, `TURRET_IDLE_RETURN 60`, `ACC_MIN_BP 1000`, `ACC_V_REF 48`.

### 4.2 Compiled definitions (`data/`; all ints, immutable after load)

```gdscript
class_name DefWarhead extends RefCounted
var id: String; var idx: int
var damage: int             # base hp damage per instance (per dot tick for beams/sweeps)
var dtype: int              # DT_*
var delivery: int           # DELIV_*
var splash_r: int           # outer radius, units (0 = single victim)
var splash_inner: int       # full-damage radius, units (<= splash_r)
var splash_edge_bp: int     # fraction of full damage at splash_r (0..10000)
var splash_min_r: int       # annulus: victims with d_eff < splash_min_r take nothing (Perun ring); 0 = disc
var layer_mask: int         # victim layers affected: bit (1 << LAYER_*)
var friendly_fire: int      # 1 = splash may hurt owner/allies/neutrals; 0 = enemies only (Aurora)
var packet: int             # 1 = strategic impact packet (Trident 8-charge rule)
var suppressive: int        # 1 = counts toward suppression
var emp_unit_ticks: int     # weapons-off ticks for victims whose class is in emp_class_mask and are not structures
var emp_struct_ticks: int   # shutdown ticks for powered structures
var emp_class_mask: int     # EC_*
var nonlethal: int          # 1 = never reduces hp below 1 (forced 1 when dtype == DT_EMP)
var fx: int; var sfx: int   # presentation ids

class_name DefProjectile extends RefCounted
var id: String; var idx: int
var kind: int               # PK_*
var speed: int              # units/tick (bullet/missile flight; arc horizontal)
var life: int               # max ticks alive (bullet/missile)
var hit_radius: int         # added to target radius in swept tests; missile/flak proximity radius
var turn_rate: int          # bat/tick (missile)
var launch_delay: int       # ticks stationary pop-up (missile)
var homing_delay: int       # straight ticks after launch_delay before steering
var min_flight: int; var max_flight: int      # arc/bomb clamp, ticks
var arc_bp: int             # apex height as bp of distance: VIEW ONLY
var fall_ticks: int         # PK_BOMB fixed fall time
var spread: int             # bullet: max deviation each side, bat
var scatter_min: int; var scatter_max: int    # arc/bomb landing scatter radius (units) at distance 0 / at weapon range_max
var lead_bp: int            # fraction of target velocity used for lead (0..10000)
var flags: int              # PF_*
var spot_len: int; var sweep_width: int; var dot_interval: int   # PK_SWEEP
var fx: int; var trail: int

class_name DefWeapon extends RefCounted
var id: String; var idx: int
var projectile: int; var warhead: int
var target_mask: int                 # TF_*
var range_max: int; var range_min: int          # base spec, units (resolved value: GameData.pmount)
var reload: int                      # ticks of cooldown after the LAST shot of a salvo (base spec)
var burst: int; var burst_interval: int         # shots per salvo (>=1), ticks between shots
var aim_delay: int                   # ticks a mount must stay aimed before the first shot of a salvo
var ammo_max: int                    # salvos per magazine/sortie; 0 = infinite
var ammo_per_salvo: int
var acc_bp: int; var acc_falloff_bp: int; var acc_move_pen_bp: int; var acc_shooter_pen_bp: int   # PK_HITSCAN only
var fire_on_move: int                # 0: fires only while ext_moving == 0 and still_ticks >= settle_ticks
var settle_ticks: int
var req_deployed: int                # -1 any, 0 must be undeployed, 1 must be deployed
var req_mode: int                    # -1 any, else exact ext_mode
var req_layer: int                   # -1 any, else shooter layer must equal it (Boreal: LAYER_SURFACE)
var auto_min_eff_bp: int             # auto-acquire only if matrix >= this (explicit orders bypass)
var beam_max_ticks: int; var beam_ramp_start_bp: int; var beam_ramp_ticks: int; var beam_dot: int   # PK_BEAM
var wclass: int                      # WC_ANTI_AIR 1, WC_ANTI_SUB 2, WC_ANTI_ARMOR 4, WC_ANTI_INF 8, WC_ARTILLERY 16, WC_ANTI_STRUCT 32
var fx_muzzle: int; var sfx: int

class_name DefMount extends RefCounted
var weapon: int                      # DefWeapon idx
var kind: int                        # MK_*
var arc_center: int; var arc_half: int          # bat relative to hull; arc_half >= 2048 = 360 deg
var turn_rate: int                   # bat/tick; 0 for MK_FIXED
var aim_tol: int                     # bat
var off_fwd: int; var off_side: int  # muzzle offset (units) rotated by hull facing
var barrels: int                     # 1..4 (view alternation)
var independent: int                 # 1 = own target selection (AA, ASW, secondary guns)

class_name DefCombat extends RefCounted
var mounts: Array[DefMount]
var prio: int                        # threat priority 0..15
var stance_default: int; var am_mode: int       # am_mode 0 = stop to engage, 1 = skirmish
var auto_mode: int                   # 1 = request a mode switch when no weapon of the current mode can engage the target (Shinano, Protea, Shogun); 0 = manual / airfield-only (Raptor)
var acq_extra: int                   # extra auto-acquire range beyond weapon range (units); -1 = SCAN default
var resist_rows: PackedInt32Array    # stride 4: [filter, bp, layer, cond]   filter = FILTER(types, req, forbid) of §4.1; cond: COND_ON_WATER 1
var dir_rows: PackedInt32Array       # stride 5: [filter, arc_center, arc_half, bp, layer]  (bp < 0 = vulnerability)
var aps_count: int; var aps_cooldown: int; var aps_radius: int
var death: int; var air: int; var carrier: int  # profile indices, -1 none
var pad_count: int; var pad_offsets: PackedInt32Array
var garrison_fire: int; var needs_power: int

class_name DefDeath extends RefCounted
var kind: int; var warhead: int; var chain_delay: int
var dying_ticks: int; var visual_ticks: int
var crash_ticks: int; var crash_warhead: int
var wreck_hp_bp: int; var cargo_mode: int; var eject_hurt_bp: int

class_name DefAir extends RefCounted
var style: int; var fuel_ticks: int; var fuel_reserve: int; var rearm_ticks: int
var takeoff_ticks: int; var landing_ticks: int
var patrol_radius: int; var orbit_radius: int
var approach_dist: int; var egress_dist: int; var release_tol: int
var hover_bp: int; var strafe_min_sep: int; var strafe_max_ticks: int
var auto_resume: int; var retarget_radius: int

class_name DefCarrier extends RefCounted
var bays: int; var wing_defs: PackedInt32Array; var wing_weapon: PackedInt32Array
var launch_range: int; var tether: int; var dock_radius: int
var launch_interval: int; var launch_batch: int; var recall_delay: int
var replace_ticks: int; var replace_cost: int; var wing_switch_ticks: int; var orphan_ticks: int
```

### 4.3 Runtime components

```gdscript
class_name SimCompCombat extends RefCounted
# ---- identity ----
var n_mounts: int                       # from def; 0 for unarmed
var cflags: int                         # CF_*
# ---- stance / target  (writers: SimOrderCombat, SimTargeting, SimWeapons) ----
var stance: int; var hold_pos: int
var target_id: int = -1; var target_src: int = 0; var target_since: int
var seen_x: int; var seen_y: int; var seen_tick: int          # last position at which the target was visible
var ground_on: int; var ground_x: int; var ground_y: int      # force-fire ground point
var anchor_on: int; var anchor_x: int; var anchor_y: int      # leash / return anchor
var scan_next: int                      # tick at which this entity may next scan
var focus_mask: int; var focus_tick: int                      # teams that recently targeted THIS entity (bit per team 0..7)
var inflight_est: int                   # estimated damage in flight aimed at this entity (overkill guard)
var last_attacker_id: int = -1; var last_attacker_pid: int = -1; var last_assist_tick: int
var still_ticks: int                    # consecutive ticks with ext_moving == 0
var mnt: PackedInt32Array               # n_mounts * MS ints, layout §4.1
# ---- timestamps (READ by abilities / vision) ----
var last_fire_tick: int = -100000; var last_hit_tick: int = -100000; var last_dealt_tick: int = -100000
# ---- statuses ----
var emp_until: int; var wlock_until: int
var sup_left_q8: int; var sup_t0: int; var sup_t1: int; var sup_t2: int; var sup_i: int   # suppression countdown (Q8 ticks) + ring of last 3 hit ticks
# ---- leases ----
var mods: PackedInt32Array              # MAX_MODS * 5 ints [key, stat, bp, expire_tick, filter]; empty slot has stat = -1
var mods_dirty: int; var mods_next_expiry: int
var agg_dmg_bp: int; var agg_reload_bp: int; var agg_range_bp: int
# ---- point defence ----
var aps_next: PackedInt32Array          # per interceptor: tick when ready again
# ---- requests to abilities (written by combat; abilities read, act, and the state shows up in inbox) ----
var want_deploy: int = -1; var want_mode: int = -1; var want_surface: int = -1   # -1 none; deploy: 1 deploy / 0 pack; surface: 1 / 0
# ---- inbox (written by movement / abilities EVERY tick before step 8) ----
var ext_moving: int; var ext_deployed: int; var ext_mode: int
# ---- wreck (KIND_WRECK only) ----
var wreck_value: int; var wreck_expire: int; var wreck_flags: int; var wreck_owner_pid: int; var wreck_src_def: int
# ---- dying ----
var dying_until: int; var death_kind: int; var crash_vx: int; var crash_vy: int
# ---- per-tick scratch (NOT checksummed; reset lazily by tick stamp) ----
var taken_stamp: int; var taken_cache: PackedInt32Array   # keyed (dtype * 16 + dc-class) -> taken_bp for this tick
var hit_stamp: int; var hit_dmg: int; var hit_flags: int; var hit_atk: int; var hit_hp0: int

class_name SimCompAir extends RefCounted
var is_airfield: int
# aircraft
var state: int = 0; var sub: int = 0; var state_t0: int
var mission: int = 0; var m_target: int = -1; var m_x: int; var m_y: int; var m_r: int
var resume_mission: int; var resume_target: int = -1; var resume_x: int; var resume_y: int
var home_id: int = -1; var home_kind: int; var pad: int = -1
var fuel: int; var rearm_prog: int      # rearm_prog: bp accumulator, 10000 = one tick at base speed
var pass_count: int; var run_ux: int; var run_uy: int           # Q16 unit vector of the current run
var wx: int; var wy: int                                         # last waypoint handed to movement
var release_left: int; var next_logic: int; var orphan_deadline: int = -1; var forced_return: int
# airfield
var pad_occ: PackedInt32Array           # per pad: occupant id or -1 (a reservation counts as occupied)

class_name SimCompCarrier extends RefCounted
var wing: int; var wing_req: int = -1; var wing_switch_until: int
var bay_id: PackedInt32Array; var bay_state: PackedInt32Array; var bay_timer: PackedInt32Array   # per bay
var next_launch: int; var recall_at: int
```

### 4.4 Projectile pool (`SimProjectiles`, struct of arrays; capacity `PROJ_POOL`; **all fields public read-only for the view**)

Each field is a `PackedInt32Array` of length `PROJ_POOL`; slot `i` is live iff `alive[i] == 1`. A free-list (`free_stack`, LIFO) gives deterministic slot reuse. `serial` (monotonic, in the checksum) is the identity used by events.

| Field | Meaning |
|---|---|
| `alive`, `serial`, `kind`, `pdef`, `wh`, `wpn` | liveness, unique id, `PK_*`, `DefProjectile` idx, `DefWarhead` idx, `DefWeapon` idx or -1 |
| `owner_pid`, `owner_id`, `owner_team` | credit player, shooter entity (may be dead), cached team for friend/foe |
| `x`, `y`, `px`, `py` | current and previous-tick position (view interpolates `px,py -> x,y`) |
| `sx`, `sy`, `ex`, `ey` | start point, end/aim point (arc/bomb/strike end; sweep end B) |
| `vx`, `vy`, `heading`, `speed` | per-tick velocity, heading (bat), speed (units/tick, resolved at launch incl. Pakistan bonus) |
| `t0`, `t_end`, `flight` | launch tick (for delayed spawns: activation tick), expiry/detonation tick, flight or sweep duration |
| `target` | target entity id or -1 |
| `dmg_bp`, `dmg_tmp` | attacker snapshot taken at launch: `dmg_bp` = static layer product (`PM_DMG_BP` or garrison variant), `dmg_tmp` = signed sum of temporary lease deltas (bp); kept separate so the victim-side `STAT_MARK` bonus can add inside the same temporary layer (§5.6) |
| `flags` | `PI_*` |
| `est` | overkill-guard estimate added to `target.inflight_est`, removed exactly when the projectile ends |
| `aux0`, `aux1` | kind-specific: missile `turn state`/`launch_delay left`; bomb stick counter; sweep `dot interval`, `next dot tick` |

View snapshot contract: the view mirrors projectiles by `serial` using `EV_PROJ_SPAWN` / `EV_PROJ_END` and reads `x,y,px,py,heading,kind,pdef` each frame; for `PK_ARC`/`PK_BOMB`/`PK_STRIKE` it may instead animate from the spawn event alone (start, end, flight ticks are enough).

### 4.5 Damage queue (`SimDamage`, `PackedInt32Array`, stride 10, cleared each tick)

`[victim_id, dmg, dtype, dc, dflags, attacker_id, attacker_pid, ix, iy, aux]` — `dmg` is the **final** integer damage from the pipeline; `aux` = EMP ticks (already class-resolved, 0 if none); `ix,iy` = impact point (events, directional armor already applied at compute time).

### 4.6 Resolved per-player tables consumed from `GameData` (ASSUMPTION(data); the data domain computes them with the bible layer rule, I define the field semantics)

```
GameData.pmount(pid, def_idx, mount) -> PackedInt32Array   # PM_* fields
  PM_RANGE_MAX 0        units: base * prod_over_layers(1 + sum(range deltas in layer)); half-up
  PM_RANGE_MIN 1        units: unchanged by range modifiers
  PM_RELOAD 2           ticks: max( ceil(base * prod_over_layers(1 + sum(reload deltas))), ceil(base / 2) )   # bible floor 50 % of base
  PM_DMG_BP 3           bp: prod_over_layers(1 + sum(weapon_damage deltas in layer)) for layers parent, subfaction, research(static)
  PM_DMG_BP_GARRISON 4  bp: same, but with the conditional "garrisoned combat infantry" delta included (El Andalus +20 %)
  PM_PROJ_SPEED 5       units/tick: base * (1 + sum(projectile_flight_speed deltas)) for PF_GUIDED, non-PF_STRATEGIC projectiles; else base
  PM_AMMO_MAX 6         salvos
  PM_STRIDE 8
GameData.pdef(pid, def_idx) -> PackedInt32Array            # PD_* fields
  PD_REARM_TICKS 0      aircraft base rearm after rearm modifiers (USA -20 %, Integrated Flight Decks -15 %)
  PD_APS_COUNT 1, PD_APS_COOLDOWN 2   (Layered Protection: Ural 12 s -> 9 s, Bear +1; Integrated Protection: Arjun 15 s -> 10 s, Gaj +1)
  PD_EMP_RECOVER_BP 3   (Buried Command Lines: Radar + defensive structures 2500; Resilient Mesh: unmanned 2500)
  PD_REPLACE_TICKS 4    (carrier drone replacement; Integrated Flight Decks -15 %, Predictive Maintenance Shogun -20 %)
  PD_PAD_COUNT 5        (Airfield 4, Dispersed Runways +2)
GameData.presist(pid, def_idx) -> PackedInt32Array         # stride 4 rows [filter, bp, layer, cond]; layers 0 base (= DefCombat.resist_rows merged in), 1 parent, 2 sub, 3 research
```
Layer product rule and floors are exactly `rule.design.how_percentages_combine` and `mechanical_conventions`; combat does not re-derive them.

---
## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

Conventions: `mul(x, bp) = (x * bp + 5000) / 10000` for `x >= 0` (half-up); `ceil_div(a, b) = (a + b - 1) / b` for `a >= 0, b > 0`; `wrap(a) = a & 4095`; `wrap_signed(a) = ((a + 2048) & 4095) - 2048` (range -2048..2047); `d_eff(p, t) = max(0, Fp.dist(t.x - p.x, t.y - p.y) - t.radius)`; range tests use squares: `dx*dx + dy*dy <= (R + t.radius)^2` (max coordinate 262144 so squares stay < 2^40).

### 5.1 Phase contract inside `SimCombatSystem.update`

| Phase | Iterates | Work | Bounded by |
|---|---|---|---|
| P1 upkeep | `status_ids` (entities with a live timer: EMP, weapon lock, suppression, dying) | expire timers (emit `EV_SUPPRESS end`, `EV_WEAPON_LOCK online`), suppression countdown, aircraft crash motion and ground impact (spawns a strike), orphan-drone timers | number of timed entities |
| P2 air/carrier | `air_ids`, `carrier_ids` (ascending) | `SimAirSortie.update`, `SimCarrierOps.update`; takeoff, attack, landing and rearm states run every tick, transit/patrol/parked/no-base every 4th tick (staggered by id, elapsed ticks are applied to fuel) | number of aircraft/carriers |
| P3 scans | `armed_ids` from `scan_cursor`, wrapping | scan entities with `scan_next <= tick`, stop when the budget is spent; set `scan_cursor` to the next index | `SCAN_BUDGET` scans |
| P4 weapons | `armed_ids` ascending | per entity: validate target (`urgent` rescan if it died), aim/slew, gates, fire; beams tick | armed entities that have a target |
| P5 projectiles | pool slots `0..hi` | move, swept test, interception, detonation/splash, sweep dots | live projectiles |
| P6 flush | damage queue in enqueue order | apply, statuses, deaths, coalesced `EV_HIT`, alerts | queued instances |

An entity that is `CF_DEAD`, inside a non-firing container, unarmed, or an aircraft in `AIR_PARKED/AIR_REARM/AIR_DOCKED` is skipped in P3/P4 in O(1). Iterations snapshot `n0 = armed_ids.size()` at phase start so entities spawned mid-phase (drones) first act next tick.

### 5.2 Mount geometry, aiming and slew

```
bearing = Fp.atan2(ty - ey, tx - ex)                    # (0,0) -> e.facing
rel     = wrap_signed(bearing - e.facing - mount.arc_center)
in_arc  = mount.arc_half >= 2048  or  abs(rel) <= mount.arc_half
goal    = wrap(mount.arc_center + (rel if in_arc else sign(rel) * mount.arc_half))   # desired turret angle relative to hull
cur     = mnt[M_ANGLE]
if mount.turn_rate == 0: cur = mount.arc_center                                    # MK_FIXED / MK_HULL: pointing is the hull's job
else: cur = wrap(cur + clamp(wrap_signed(goal - cur), -turn_rate, +turn_rate))
aimed   = in_arc and abs(wrap_signed(goal - cur)) <= mount.aim_tol                  # MK_FIXED/HULL: aimed = in_arc
```
* **Slew time** = `ceil_div(|wrap_signed(goal - cur)|, turn_rate)` ticks. Example: Bulwark Cannon, `turn_rate 8`, target 90 deg away (1024 bat) -> 128 ticks (6.4 s) — "slow traverse". Colossus/Elephant/Bastion Cannon use `turn_rate` 6..10; ordinary tank turrets 34..51 (60..90 deg/s); Outrider has `MK_TURRET`, `arc_half 341` (+-30 deg) — "narrow firing arc".
* If `not in_arc` and the mount is the unit's only relevant mount, the order handler asks movement for `SimMovement.turn_to(e, wrap(bearing - arc_center))` (hull turning). Structures with `not in_arc` simply do not fire.
* `M_AIM_SINCE` = tick when `aimed` became continuously true (-1 otherwise). First shot of a salvo needs `tick - M_AIM_SINCE >= weapon.aim_delay`.
* Idle turrets (no target for `TURRET_IDLE_RETURN` ticks) slew back to `arc_center` at half rate; once there the mount is skipped.
* Muzzle point (events, projectile spawn only): `mx = e.x + ((off_fwd * cos(f) - off_side * sin(f)) >> 16)`, `my = e.y + ((off_fwd * sin(f) + off_side * cos(f)) >> 16)`, `f = wrap(e.facing + cur)` for turrets, `e.facing` otherwise (Q16 trig from `Fp`). Barrel index for view alternation = `mnt[M_SHOTS] % barrels`.

### 5.3 Firing gates, salvo, reload, ammo

Gates are evaluated in this order; the first failure decides the action (some raise a `want_*` request instead of silently waiting):

1. `weapons_online(e)` (alive, not EMP-shut, powered if `needs_power`, `tick >= wlock_until`). Garrisoned infantry additionally need `container.def.combat.garrison_fire == 1` and shoot from their container's position; transports never lend passengers' weapons.
2. Shooter state: `req_layer` (Boreal: not surfaced -> `want_surface = 1`); `req_deployed` (not deployed and target within `range_max_eff + 1024` -> `want_deploy = 1`); `req_mode` (if `DefCombat.auto_mode` and no weapon of the current mode can engage the target -> `want_mode = req_mode`).
3. Ammo: `weapon.ammo_max > 0` requires `mnt[M_AMMO] >= ammo_per_salvo`.
4. Movement: if `fire_on_move == 0` require `ext_moving == 0` and `still_ticks >= settle_ticks` (Javelin, Spike, Kavach: "must stop to fire"; `settle_ticks` 6).
5. Target validity and reach: `can_engage` (§5.10.1), `range_min <= d_eff <= range_max_eff`, where
   `range_max_eff = mul(PM_RANGE_MAX, 10000 + agg_range_bp)` (temporary layer adds; no cap in the bible).
6. Aim: `aimed` and `aim_delay` satisfied.
7. Timing: not mid-cooldown (`tick >= mnt[M_CD]`) or mid-salvo (`mnt[M_BURST] > 0 and tick >= mnt[M_NEXT]`).
8. Stance: `TS_AUTO/TS_RETAL/TS_GUARD` targets need `stance != ST_HOLD_FIRE`; `TS_ORDER/TS_FORCE` always pass.

**Salvo.** Starting a salvo (`M_BURST == 0`, gates pass): `M_AMMO -= ammo_per_salvo` (at start), `M_BURST = burst`, fire shot 0 immediately. Each subsequent shot when `tick >= M_NEXT` and gates still pass: fire, `M_BURST -= 1`, `M_NEXT = tick + burst_interval`. After the last shot: `M_CD = tick + reload_eff`. If gates fail for more than `2 * burst_interval + 2` consecutive ticks mid-salvo, the salvo aborts (`M_BURST = 0`, `M_CD = tick + reload_eff / 2`; ammo is not refunded). **`reload` is the cooldown after the last shot**, so DPS = `burst*dmg*20 / ((burst-1)*burst_interval + reload)`.

**Reload with modifiers** (bible floor 50 % of base; temporary effects add inside the research/temporary layer):
```
reload_eff = max( ceil_div(PM_RELOAD * max(0, 10000 + agg_reload_bp), 10000),  ceil_div(weapon.reload, 2) )
```
Worked: base 80, Canada artillery `+15 %` -> `PM_RELOAD = 92`; with a temporary `-10 %` -> `ceil(92*0.9) = 83`. Base 20, Japan `-10 %` (`PM_RELOAD 18`), temporary `-40 %` -> 11; temporary `-70 %` -> `ceil(5.4) = 6`, floored to `ceil(20/2) = 10`.

**Continuous beams** (`PK_BEAM` weapons: Sunlance, Ifrit deployed, Dawn Laser, Sunwall): mount state `M_BEAM` = start tick or -1, `M_DOT` = next damage tick.
```
off -> on: gates pass and tick >= M_CD:  M_BEAM = tick; M_DOT = tick + beam_dot; EV_BEAM_START
on, each tick: if any gate fails (target invalid/hidden/out of range/out of arc, locked, EMP, state lost) or tick - M_BEAM >= beam_max_ticks:
                   stop: M_BEAM = -1; M_CD = tick + reload_eff  (reload doubles as the cooling interval, so "cooling -10 %" research works); EV_BEAM_END(reason)
               elif tick >= M_DOT:
                   ramp = start + (10000 - start) * min(tick - M_BEAM, ramp_ticks) / ramp_ticks
                   base = max(1, mul(warhead.damage, ramp)); enqueue a DC_DIRECT instance on the target; last_fire_tick = tick; M_DOT += beam_dot
```
Beams never miss, are not interceptable and ignore Trident (they are not projectiles). Changing targets ends the beam (ramp restarts) — auto retargeting is suppressed while a beam is on unless the target became invalid.

### 5.4 Projectile kinds

Common launch data: `flags |= PI_ENEMY_ONLY` if the shooter has `CF_ENEMY_ONLY`; `dmg_bp = PM_DMG_BP` (or `PM_DMG_BP_GARRISON` when the shooter is inside a garrison), `dmg_tmp = SimCombatMods.sum_bp(cc, STAT_DMG_OUT)`, `speed = PM_PROJ_SPEED`, `owner_pid/owner_id/owner_team`, `est = mul(warhead.damage, matrix_bp)` added to `target.inflight_est`. All RNG draws happen here, in shooter-id then mount order.

**5.4.1 `PK_HITSCAN`** (rifles, MGs, rails, autocannons, drone guns): resolves at fire time; `EV_FIRE` carries the result.
```
p = acc_bp - acc_falloff_bp * min(d_eff, range_max_eff) / range_max_eff
    - acc_move_pen_bp * min(Fp.dist(t.vx, t.vy), ACC_V_REF) / ACC_V_REF            # moving target
    - (acc_shooter_pen_bp if ext_moving else 0)
    + min(2500, t.radius * 2500 / 1024)                                              # big targets are easier
p = 10000 if t.kind == KIND_STRUCTURE else clamp(p, ACC_MIN_BP, 10000)
hit = rng.next_int(10000) < p
```
Worked: rifle `acc 8000`, falloff 3000, range 5632, target radius 256 at distance 4096 (d_eff 3840) moving at 30 u/tick: `8000 - 2045 - 937 + 625 = 5643` -> 56.4 %. Hit: if the warhead is a packet (`packet == 1`, Tempest drone guns) ask `intercept_packet(owner_team, victim.x, victim.y)` first and pass the result as `pkt_bp`; then enqueue direct damage (and splash at the victim if the warhead has any). Miss: one more draw, impact displaced by `256 + d_eff/16` at a random bearing (visual + splash if any).

**5.4.2 `PK_BULLET`** (tank shells, autocannon slugs, unguided rockets): straight flight.
```
t1  = ceil_div(dist(muzzle, target), speed);  aim = target.pos + trunc(target.v * t1 * lead_bp / 10000)     # ground target: aim = point
h   = Fp.atan2(aim - muzzle) + (rng.next_int(2*spread + 1) - spread  if spread > 0)
vx  = (speed * cos(h)) >> 16 ; vy = (speed * sin(h)) >> 16 ;  flight = ceil_div(dist(muzzle, aim), speed)
t_end = t0 + min(life, flight + 2)
each tick: p1 = p0 + v ; swept test of segment p0->p1 against the TARGET circle (radius t.radius + hit_radius) (§5.4.8)
           hit -> detonate at the closest point; else at t_end: detonate in place if warhead.splash_r > 0 or PF_AIRBURST_ON_EXPIRE, else vanish
           (misses therefore land near the aim point and can still splash friendlies)
optional PF_BLOCKED_BY_HOSTILES: also test hostile hit-circles near the segment (spatial query at the segment midpoint, radius len/2 + 2560),
           earliest hit by parameter t, ties lowest id; off by default.
```
**5.4.3 `PK_MISSILE`** (guided): `launch_delay` ticks pop-up at the muzzle, then `homing_delay` ticks straight, then each tick
```
if target alive and valid: desired = Fp.atan2(t.pos - pos); heading += clamp(wrap_signed(desired - heading), -turn_rate, +turn_rate)
pos += (speed*cos(heading) >> 16, speed*sin(heading) >> 16); swept test vs target circle (t.radius + hit_radius = proximity fuse)
expiry (life): detonate in place iff PF_AIRBURST_ON_EXPIRE (AA missiles) else fizzle (EV_PROJ_END reason 0)
```
A missile whose target dies keeps its heading (no re-acquire). Speed is per-projectile (`PM_PROJ_SPEED`), which is how Pakistan's `+20 %` flight speed is honored.

**5.4.4 `PK_ARC`** (artillery shells, rocket barrages, missile artillery, naval bombardment, remote shells): integer flight time, no per-tick physics.
```
lead (2 iterations):  t = ceil_div(dist(muzzle, tpos), speed); aim = tpos + trunc(tv*t*lead_bp/10000); t = ceil_div(dist(muzzle, aim), speed); aim = tpos + trunc(tv*t*lead_bp/10000)
scatter radius sc = scatter_min + (scatter_max - scatter_min) * min(d, range_max) / range_max          # d = dist(muzzle, aim)
if sc > 0:  u = rng.next_int(65536); a = rng.next_int(4096); r = (sc * Fp.isqrt(u << 16)) >> 16 ; end = aim + ((r*cos(a)) >> 16, (r*sin(a)) >> 16)   # uniform in disc
flight = clamp(ceil_div(dist(muzzle, end), speed), min_flight, max_flight)
position at tick t0+k = start + trunc((end - start) * k / flight)  (k = 1..flight); detonates when k == flight
```
Worked: 12 cells (12288 u) at speed 512 u/tick (10 cells/s) -> 24 ticks (the seed howitzer shell, 768 u/tick, needs 24 ticks for its full 18-cell range); `scatter_min 128, scatter_max 1536, range_max 14336` -> `sc = 128 + 1408*12288/14336 = 1334`; `u = 32768` -> `Fp.isqrt(2^31) = 46340` -> `r = (1334*46340) >> 16 = 943`. `lead_bp 0` + big scatter = "inaccurate against moving targets" (Anvil); `lead_bp 10000` + tiny scatter = precision missiles. Moving targets escape because the aim point is fixed at launch ("moving units can escape").

**5.4.5 `PK_BOMB`**: as arc with `flight = fall_ticks`, `end = release_point + V*fall_ticks + scatter`, `V` = aircraft velocity at release. **5.4.6 `PK_STRIKE`**: no travel; detonates at `(ex,ey)` when `tick == t0 + flight`; used for superweapon impacts, Aurora, chain blasts, crash impacts.

**5.4.7 `PK_SWEEP`** (Helios): `spawn_sweep(A, B, delay, duration)`; the hot spot travels `A -> B` linearly.
```
unit vector u = ((B-A) << 16) / L,  L = Fp.dist(B-A);   spot centre C(k) = A + trunc((B-A)*k/duration), k = tick - t0
every dot_interval ticks: victims = entities within spot_len/2 + sweep_width/2 + 2560 of C (ascending id), layer/friend rules of the warhead
   along = ((v.x-C.x)*ux + (v.y-C.y)*uy) >> 16 ;  across = ((v.x-C.x)*(-uy) + (v.y-C.y)*ux) >> 16
   inside iff |along| <= spot_len/2 + v.radius  and  |across| <= sweep_width/2 + v.radius   -> enqueue DC_DIRECT damage (thermal, not a packet)
compile-time check: (L / duration) * dot_interval <= spot_len   (no gaps: no tunnelling between dots)
```
Helios seed: `L = 16384`, `duration 240`, `sweep_width 3072`, `spot_len 3072`, `dot_interval 5` (advance 341 u per dot). Units standing still take about `3072/68.3 = 45 ticks = 9 dots`; walking off the line ("leave the marked line") avoids it. Beam type is `DT_THERMAL`, so Saudi `+15 %` and Thermal Shrouds apply, Trident does not (`packet 0`, not `PF_ZONE_INTERCEPTABLE`).

**5.4.8 Swept segment vs circle** (tunnelling protection; every moving projectile every tick):
```
sx = x1-x0 ; sy = y1-y0 ; len2 = sx*sx + sy*sy
tn = 0 if len2 == 0 else clamp((tx-x0)*sx + (ty-y0)*sy, 0, len2)
cx = x0 + (sx*tn)/len2 ; cy = y0 + (sy*tn)/len2                         # closest point on the segment (len2 > 0)
hit iff (tx-cx)^2 + (ty-cy)^2 <= (t.radius + hit_radius)^2 ; impact point = (cx,cy)
```
Test vector: bullet speed 2048 heading east from (0,0), target at (9216,0), radius 384, `hit_radius 64`: endpoints at 8192 and 10240 are each 1024 away (> 448) yet segment 5 (8192->10240) hits with closest point (9216,0). Splash-less projectiles faster than the target diameter are therefore never lost to tunnelling; the sweep test is mandatory for every `PK_BULLET/PK_MISSILE` step.

**5.4.9 Pool limit ("max live projectiles").** `PROJ_POOL 4096` slots. At `live >= PROJ_SOFT_CAP (3072)` new non-strategic `BULLET/MISSILE` shots without splash resolve instantly like hitscan with `p = 10000`. At `live >= PROJ_POOL - PROJ_STRATEGIC_RESERVE` every non-strategic spawn resolves instantly; `PI_REMOTE`/`PF_STRATEGIC` projectiles may use the reserve, and `spawn_remote` returns -1 only if that is exhausted too. The rule is count-based, hence identical on all clients.

### 5.5 Detonation, splash, falloff, friendly fire, layers

`detonate(slot, x, y, direct_id)`:
1. **Packet reduction.** If `warhead.packet == 1` (or `PI_PACKET`): `pkt_bp = zones.intercept_packet(owner_team, x, y)` (0 or 5000); emit `EV_INTERCEPT kind 2` when non-zero.
2. **Victim set.** If `splash_r == 0`: only `direct_id`. Else `SpatialHash.query_circle(x, y, splash_r + 2560)` sorted ascending, plus `direct_id` (always included, treated as `d_eff = 0`). Reject: dead, `CF_UNTARGETABLE` (cargo, docked), victim layer bit not in `layer_mask`, and — if `friendly_fire == 0` or `PI_ENEMY_ONLY` — anyone who is not `REL_ENEMY` to the owner.
   **Bible default: `friendly_fire = 1` for every warhead with splash** ("damage-bearing area attacks can hurt friendlies", including the shooter's own side, allies, neutral structures and wrecks); **Aurora sets 0**; non-splash direct hits only ever touch the intended target. **Summoned attackers** (Tempest drones, Dragonfall engines; `CF_ENEMY_ONLY`) both *select* enemies only (§5.10.1) and, via `PI_ENEMY_ONLY`, deal splash to enemies only (§12-24).
3. **Falloff** with `d = d_eff(center, v)`; skip if `d > splash_r` or `d < splash_min_r`:
   `f = 10000` if `d <= splash_inner`; `edge_bp` if `d >= splash_r`; else `10000 - (10000 - edge_bp) * (d - splash_inner) / (splash_r - splash_inner)`.
   Worked: `inner 512, outer 2048, edge 2500`, victim `d = 1280` -> `f = 10000 - 7500*768/1536 = 6250`; a 110-damage shell deals `69` to a tank at that distance (matrix 100 %).
4. Per victim: `dmg = SimDamage.compute(...)` with `dc` = `DC_DIRECT`, `DC_INDIRECT` or `DC_STRATEGIC` according to the warhead's `delivery` (+`DC_SPLASH` for every victim other than the direct hit), `pkt_bp` from step 1, `from_bat = atan2(center - v)` (projectile heading + 2048 for the direct victim), enqueue; EMP/suppression side effects ride on the instance (`aux`, `DF_SUPPRESSIVE`).
5. `EV_IMPACT`; `target.inflight_est -= est`; free the slot.

### 5.6 The damage pipeline (`SimDamage.compute`, ordered; all arithmetic in Q8 = value * 256, half-up after each multiply)

```gdscript
static func compute(world: SimWorld, v: SimEntity, wh: DefWarhead, base: int, dc: int, static_bp: int, tmp_bp: int,
        atk_team: int, atk_ground: int, falloff_bp: int, from_bat: int, pkt_bp: int) -> int
```
| # | Step | Formula | Notes |
|---|---|---|---|
| 1 | Base damage | `x = base << 8` | `base = warhead.damage` (beams: ramped) |
| 2 | Type x armor | `m = dmg_matrix[wh.dtype][v.armor_class]`; `if m == 0: return 0`; `x = mul(x, m)` | matrix is base effectiveness, **not** a "resistance": it is not subject to the 50 % cap |
| 3 | Attacker modifiers | `x = mul(x, static_bp)`; `x = mul(x, clamp(10000 + tmp_bp + mark_bp, 0, 40000))` | `static_bp` = product of bible layers parent x subfaction (x static research) resolved by `GameData`; `tmp_bp` = additive sum of temporary/aura leases (research/temporary layer); `mark_bp` = victim's `STAT_MARK` leases matching `atk_team` (and `atk_ground`, true when the shooter is on `LAYER_GROUND`: ground units and structures, not aircraft or ships) — **added inside the same temporary layer**. Veterancy is off in the prototype |
| 4 | Splash falloff | `x = mul(x, falloff_bp)` | 10000 for direct hits |
| 5 | Defender resistances | `taken = taken_bp(v, wh.dtype, dc, from_bat, pkt_bp)`; `x = mul(x, taken)` | below |
| 6 | Cap | `taken >= TAKEN_MIN_BP (5000)`; `taken <= TAKEN_MAX_BP (20000)` | "combined resistance <= 50 % **except interception, which removes the projectile before this point**" |
| 7 | Rounding | `dmg = (x + 128) >> 8`; if `dmg < 1 and m >= CHIP_FLOOR_BP and x > 0: dmg = 1` | half-up; chip floor only when the matrix is at least 5 %, so rifles never grind heavy armor; `m < 500` may round to 0 |
| 8 | Apply (flush) | `hp -= dmg` after the non-lethal clamp | §5.6.2 |

**5.6.1 `taken_bp`** — layered exactly like every other bible stat: sums *add within a layer*, layer factors *multiply*.
```
L[0..3] = 0                    # 0 unit base / abilities of the unit, 1 parent faction, 2 subfaction, 3 research + temporary
L[3] += pkt_bp                                                       # Trident packet reduction is a temporary-layer resistance
for row in presist(v.owner, v.def_idx):        if match(row.filter, dtype, dc) and (row.cond & COND_ON_WATER == 0 or v.layer == LAYER_SURFACE): L[row.layer] += row.bp     # stride 4
for d in def.combat.dir_rows:                  if match(d.filter, dtype, dc) and abs(wrap_signed(wrap_signed(from_bat - v.facing) - d.arc_center)) <= d.arc_half: L[d.layer] += d.bp     # stride 5
for slot in v.combat.mods:                     if slot.stat == STAT_TAKEN and slot.expire > tick and match(slot.filter, dtype, dc): L[3] += slot.bp
taken = 10000 ; for k in 0..3: taken = mul(taken, clamp(10000 - L[k], 0, TAKEN_MAX_BP))
taken = clamp(taken, TAKEN_MIN_BP, TAKEN_MAX_BP)
```
Negative `bp` (rear armor, "weak rear protection") is a vulnerability: it raises `taken` above 10000 and is never capped by the 50 % rule. A per-victim per-tick cache keyed `(dtype*16 + dc)` is used when the victim has no directional rows and `pkt_bp == 0`.

**Directional armor.** `from_bat` is the bearing from the victim *toward the attack origin*: hitscan/beam = shooter position, bullet/missile = `heading + 2048`, splash = blast centre. Gate Guard: one row `filter = FILTER(1<<DT_BULLET, req DC_DIRECT, forbid DC_SPLASH|DC_INDIRECT|DC_STRATEGIC), arc_center 0, arc_half 683 (+-60 deg), bp 2500, layer 0` -> 25 % less **frontal bullet** damage, no effect on blasts or from behind. Ibex: front row `+2000`, rear row (`arc_center 2048, arc_half 1024`) `-1500`.

**Worked examples** (the reference vectors of §10 reproduce each):
* A — Sunlance-style thermal tick: base 12, matrix vs light vehicle 12000, Saudi `static_bp 11500`, Capacitor Discharge `tmp +2000`, victim Thermal Shrouds `+1000` and Steel Advance `+2000` (both layer 3 -> `L3 = 3000`, `taken 7000`): `12 -> 14.4 -> 16.56 -> 19.87 -> 13.9 -> 14`.
* B — Perun core packet on a heavy structure: base 1400, matrix 100 %, Trident `pkt 5000` + Emergency Fortification `2500` -> `L3 = 7500 -> 0.25` -> **capped to 0.50** -> `700` (without Trident: `taken 7500 -> 1050`).
* C — layers multiply: 5 bullet damage vs a frontal hit on a Gate Guard (25 %, layer 0) under Protected Advance (15 %, layer 3): `5 * 0.75 * 0.85 = 3.19 -> 3`.
* D — 60 explosive, attacker Relay `+10 %` plus Combined Arms Window `+10 %` (different keys add: `tmp +2000`), victim Adaptive Plating `10 %` + Steel Advance `20 %` (`L3 3000`): `60 * 1.2 * 0.7 = 50.4 -> 50`.

**5.6.2 Flush** (`SimDamage.flush`, P6). For each instance in queue order:
1. Skip if victim missing, `CF_DEAD`, or `CF_INVULNERABLE`.
2. `DF_NONLETHAL` (EMP, or warhead `nonlethal`): `dmg = min(dmg, v.hp - 1)`.
3. `v.hp -= dmg`; `cc.last_hit_tick = tick`; `last_attacker_*`; attacker (if alive) `last_dealt_tick = tick`; team focus bits; player stats.
4. `aux > 0` -> `apply_emp` (§5.8). `DF_SUPPRESSIVE` and victim `CF_SUPPRESSIVE` -> `suppress_hit` (§5.9).
5. Alert (`EV_ATTACK_ALERT`) if the victim belongs to a player, is not a decoy/wreck, and (`tick - alert_tick[pid] >= ALERT_COOLDOWN` or the distance to the last alert location `>= ALERT_DIST`).
6. Accumulate coalesced hit data (`hit_dmg += dmg`, flags OR); first touch appends the victim to the tick's `touched` list.
7. If `v.hp <= 0`: `SimDeath.kill(world, v, CAUSE_DAMAGE, attacker_id, attacker_pid)`. Later instances against the same victim are skipped (overkill).
8. Retaliation hook `SimTargeting.on_damaged(world, v, attacker_id)` (once per victim per tick, after the loop).
After the loop: emit one `EV_HIT` per touched victim, then clear the queue.

### 5.7 Interception

* **Point defence (Ural, Arjun; Bear/Gaj after research).** Each tick, for a live projectile with `PF_APS_INTERCEPTABLE` whose target `t` has `PD_APS_COUNT > 0`, `rel(owner_pid, t.owner) == REL_ENEMY` and `dist(proj, t)^2 <= (aps_radius + t.radius)^2`: take the lowest interceptor index `i` with `aps_next[i] <= tick`; if one exists the projectile is removed (`EV_PROJ_END reason 1`, `EV_INTERCEPT kind 0`) and `aps_next[i] = tick + PD_APS_COOLDOWN` (Ural 240 ticks -> 180 after Layered Protection; Arjun 300 -> 200). Only one projectile per interceptor per cooldown, so a second missile arriving during cooldown lands. Shells, bullets, beams and strategic packets never carry the flag ("cannot intercept shells, beams or superweapons"). `aps_next` is resized lazily to `PD_APS_COUNT`.
* **Trident ordinary charges.** After moving a projectile with `PF_ZONE_INTERCEPTABLE` (ordinary `PK_ARC/PK_MISSILE`, `PI_PACKET` off): `zid = SimZoneSystem.intercept_ordinary(owner_team, x0, y0, x1, y1, sx, sy, flags)`. The zone system enforces: hostile team only; **launch point (sx,sy) inside the zone bypasses**; crossing means the segment `(x0,y0)->(x1,y1)` intersects the zone circle while `(x0,y0)` is outside it (use the swept test of §5.4.8 with the zone radius; an endpoint-only test can miss grazing chords); consumes one charge; returns its id. Combat then removes the projectile (`reason 2`, `EV_INTERCEPT kind 1`, charges left in `d`). Bullets, beams, hitscan, EMP strikes, Helios sweeps and units entering the zone are never asked.
* **Strategic impact packets.** Every detonation with `packet == 1` calls `intercept_packet(owner_team, center)`; the zone system reduces only if the impact centre lies in a hostile zone with **>= 8 charges left** and then consumes 8 and returns `5000`. That value enters `L[3]` (§5.6.1), so the *overall 50 % cap still binds*. Fewer than 8 charges: no effect; a packet is never cancelled. Packets are: each Atlas rod, Perun core and Perun ring, each Horizon impact, each Tempest drone hit (drone weapon warhead `packet 1`), each Dragonfall engine shot. Helios (beam) and Aurora (EMP) carry `packet 0` and are never asked. Worked charge ledger for a 24-charge zone: 5 ordinary shells -> 19 left; packets 1 and 2 -> reduced (3 left); packet 3 -> full damage.

### 5.8 EMP

An EMP-carrying warhead (`emp_unit_ticks`/`emp_struct_ticks` > 0; `dtype DT_EMP` forces `nonlethal`) contributes its **normal damage through the pipeline** ("they still take normal EMP damage": Resilient Mesh only shortens the shutdown) and, per victim, an EMP status:
```
class = EC_STRUCTURE if kind == STRUCTURE else EC_AIRCRAFT if layer == AIR else EC_SHIP if ship-tag else EC_INFANTRY if infantry-tag else EC_VEHICLE
if (wh.emp_class_mask & class) == 0: nothing (Aurora: infantry unaffected)
base = emp_struct_ticks if structure (and def.emp_susceptible) else emp_unit_ticks
if has_flag(v, STAT_FLAG_EMP_IMMUNE): EV_EMP(blocked) ; return               # Redundant Orders "ignore weapon-disabling EMP"
rec = clamp(PD_EMP_RECOVER_BP + sum_bp(v, STAT_EMP_RECOVER), 0, 5000)         # Buried Command Lines 25 %, Resilient Mesh 25 %
dur = ceil_div(base * (10000 - rec), 10000) ; cc.emp_until = max(cc.emp_until, tick + dur)      # re-hits refresh, never stack
```
Aurora seed: `emp_unit_ticks 160` (8 s, vehicles/ships/aircraft), `emp_struct_ticks 360` (18 s), `friendly_fire 0`, `nonlethal 1`, light damage (`damage 40`, EMP row). Effects of `emp_until > tick`: units — `weapons_online` false (they still move; aircraft keep flying and **never crash from EMP**; `hp` never drops below 1 from EMP damage); structures — `is_functional` false, consumed by production/power/vision/zone/power domains (`SimCombatSystem.is_functional`): shutdown of production, research, Relay/command fields, pads, defences (SAP reserve cannot help) and superweapon launchers (a launcher EMP'd during its warning cancels the attack — the power domain polls `is_functional`). EMP never changes ownership (no code path does).

### 5.9 Suppression

`suppress_hit(v, tick)` runs for each applied instance with `DF_SUPPRESSIVE` on a `CF_SUPPRESSIVE` (infantry) victim without `STAT_FLAG_SUP_IMMUNE`:
```
if sup_left_q8 > 0:                       sup_left_q8 = SUP_TAIL * 256                     # already suppressed: each hit restarts the 3 s tail
else: ring[sup_i] = tick ; sup_i = (sup_i + 1) % 3 ; oldest = ring[sup_i]
      if tick - oldest <= SUP_WINDOW:      sup_left_q8 = SUP_TAIL * 256 ; EV_SUPPRESS(begin)     # 3 hits within 2 s (40 ticks)
each tick (P1): sup_left_q8 -= 256 * (10000 + sum_bp(STAT_SUP_RECOVER)) / 10000 ; at <= 0: 0 and EV_SUPPRESS(end)
```
Ring entries start at -100000. `SUP_HITS 3`, `SUP_WINDOW 40`, `SUP_TAIL 60`. Effects: `suppression_speed_bp(e) = 7500` while `sup_left_q8 > 0` (movement multiplies infantry speed); `is_suppressed` disables Han command fields (abilities). Worked: hits at ticks 0, 15, 30 -> begins at 30 (`30 - 0 <= 40`), ends at 90; hits at 0, 30, 60 never trigger (`60 - 0 > 40`). Signal Officer/Echo Team aura (`STAT_SUP_RECOVER +5000`): decrement 384/tick -> the 3 s tail lasts 2 s ("recover 50 % faster" = rate x1.5). `clear_suppression` (Coordinated Advance) zeroes `sup_left_q8` and the ring. Only weapons whose warhead has `suppressive = 1` count (all Fortress Guard fire — the deployed mode is "stronger" through its higher fire rate — and the Watchtower gun; "other weapons are not unless later specified"). Splash victims of a suppressive warhead count as one hit each.

---
### 5.10 Target acquisition, stances, orders

**5.10.1 Filters.** `filter_bit(t)`: `KIND_STRUCTURE -> TF_STRUCTURE`, `KIND_WRECK -> TF_WRECK`, else by layer (`GROUND->TF_GROUND`, `AIR->TF_AIR`, `SURFACE->TF_SURFACE`, `UNDERWATER->TF_UNDERWATER`). Parked aircraft are `LAYER_GROUND` (ground weapons hit them, AA does not); amphibious vehicles on water are `LAYER_SURFACE`.
```
can_engage(shooter, mount, t, force):
  t alive, t != shooter, not CF_UNTARGETABLE and t.container_id < 0 (cargo, garrison occupants, docked drones); bit = filter_bit(t)
  class_ok = (weapon.target_mask & bit) != 0   or (force and bit == TF_WRECK and mask has TF_GROUND or TF_STRUCTURE)
  relation_ok = force ? true : rel(shooter.owner, t.owner) == REL_ENEMY      # neutrals only by force-fire; CMD_ATTACK on a neutral is refused
  if shooter.CF_ENEMY_ONLY: relation_ok = (rel == REL_ENEMY)                    # summoned attackers select enemies only, even under force
  auto (force == false): t.CF_DECOY identified by shooter's player (SimVision.decoy_identified) -> false ; KIND_WRECK -> false
```
Visibility is required to *acquire* (`SimVision.can_see(shooter.owner, t)`); an explicit order additionally accepts `SimVision.is_known` (remembered structure) at issue time.

**5.10.2 Scan scheduling.** Per entity `scan_next`; initial `tick + (id % interval)` (staggering). Interval: structures `SCAN_INTERVAL_STRUCT 8`, aircraft `4`, others `6`. Unit with a `TS_AUTO` target rescans every `RESCORE_INTERVAL 20`. Budget per tick `SCAN_BUDGET_BASE + 4*(armed/64)` normal scans (round-robin from `scan_cursor`) plus 16 *urgent* scans (an entity whose target just died/became invalid rescans inside P4). Overflow entities stay due and are reached next tick by the rotation, so nobody starves. Each scan visits at most `SCAN_CAND_CAP 48` candidates that survive the cheap prefilter (alive, relation, layer-mask union of the mounts, flags, visibility, `d_eff <= R_acq`), in `SpatialHash` order (deterministic).

**5.10.3 Score** (integer; highest wins; ties -> lowest entity id):
```
score = prio*PRIO_TIER (+2*PRIO_TIER if shooter is LAYER_AIR and t has CF_HAS_AA)
      + clamp((m_best - 10000) * 2048 / 10000, -4096, 4096)          # m_best = best matrix bp among mounts that can hit t
      + THREAT_BONUS  if t is currently targeting a unit of the shooter's team (t.combat.target_id owner is SELF/ALLY)
      + FOCUS_BONUS   if (t.focus_mask >> team) & 1 and tick - t.focus_tick <= FOCUS_TTL
      + WOUNDED_MAX * (10000 - t.hp*10000/t.hp_max) / 10000
      - d_eff * 1024 / max(1, R_acq)
      + STICK_BONUS   if t.id == cc.target_id
      - OVERKILL_PENALTY if auto target and t.hp - t.inflight_est <= 0
```
Acceptance also needs `m_best >= weapon.auto_min_eff_bp` (default 1500 = 15 %): weapons never auto-acquire targets they barely hurt; explicit orders bypass this. On acquiring, the shooter ORs `1 << team` into `t.focus_mask` and stamps `focus_tick`. **Default `prio` table (SEED; overridable per def):** decoy 1, civilian 1, wreck 0, passive structure 3, service unit 3-4, unarmed support 4, transport/APC 6, infantry 6, anti-tank infantry 7, light vehicle 7, tank 8, artillery/siege 9, AA vehicle 8, aircraft 8-10 (bomber 10), drone 6, patrol boat 6, escort 8, siege ship/carrier 9, submarine 8, defence structure 10, advanced defence 11, superweapon structure 5.

**5.10.4 Stances** (`R_acq` measured from the shooter, or from the guard anchor for `ST_GUARD`):

| Stance | Auto-acquire | Chase | Leash from anchor | Return |
|---|---|---|---|---|
| `ST_AGGRESSIVE` (units default) | yes, `R_acq = range_max_eff + 2048` | yes, unless `hold_pos` | `LEASH_AGGRESSIVE 8192` | yes |
| `ST_DEFENSIVE` | only targets within `range_max_eff`; retaliates | only vs attackers, `LEASH_DEFENSIVE 3072` | 3072 | yes |
| `ST_HOLD_FIRE` | never | never | — | — |
| `ST_GUARD` | `R_acq = max(range_max_eff + 2048, GUARD_RADIUS 10240)` around the anchor | yes | `LEASH_GUARD 6144` | yes |
Structures are always `ST_AGGRESSIVE` without chase. `hold_pos = 1` sets the leash to 0 for every stance. The anchor is the position where the unit last became idle (or the guard point/guarded unit).

**5.10.5 Retarget, focus, retaliation, assist.** (a) Target invalid (dead, hidden longer than `HIDE_GIVEUP_AUTO 20` ticks for auto / `HIDE_GIVEUP_ORDER 200` for orders, out of leash, no longer engageable) -> `clear_target` and immediate urgent rescan. (b) Auto targets are re-scored every 20 ticks; the switch happens only if another candidate beats the current *including* `STICK_BONUS`. (c) `TS_ORDER`/`TS_FORCE` are never replaced by auto logic. (d) Retaliation (`SimTargeting.on_damaged`, after flush): if the victim is armed, stance != `ST_HOLD_FIRE`, has no target or a `TS_AUTO/TS_GUARD/TS_RETAL` target scoring at least `RETAL_MARGIN 1024` below the attacker, and the attacker is visible and engageable -> `set_target(attacker, TS_RETAL)`. (e) Assist: at most once per victim per `ASSIST_COOLDOWN 20` ticks, up to 12 idle friendly armed entities (ascending id) within `ASSIST_RADIUS 8192` with stance != `ST_HOLD_FIRE` get `TS_RETAL` on the attacker if engageable. (f) Explicit focus fire: several units with `CMD_ATTACK` on one target simply share it; automatic focus emerges from `FOCUS_BONUS`, `WOUNDED_MAX` and the overkill guard.

**5.10.6 Order handlers** (all return `OS_*`; `ord` fields used: `kind, target_id, x, y, count, state, t0, tx, ty`):
* **`step_idle`** (no order): if `ST_HOLD_FIRE` return. If `cc.target_id` valid (`TS_AUTO/TS_RETAL`): if the best mount cannot yet reach and `hold_pos == 0` and the target is within `leash + range` of the anchor -> chase (`move_to_range(want_dist)`, throttled: at most every 10 ticks or when the target moved > 2048); if in range -> `SimMovement.stop` once. No target: if the unit is > `RETURN_SLACK 2048` from its anchor, `hold_pos == 0` and not moving -> `move_to(anchor)`.
* **`ORD_ATTACK`**: target missing/dead -> `OS_DONE`; not engageable by any mount (e.g. a submarine dived) -> `OS_FAILED`. Set `target_src = TS_ORDER`. Visible -> refresh `seen_*`; invisible for more than 200 ticks -> `OS_DONE`, otherwise chase `seen_*`. Choose the best mount (largest `range_max_eff` among mounts that can hit); `want_dist = max(mul(range, APPROACH_BP 9000), range_min + 1024)`. Gates that need a state (deploy/surface/mode) -> set `want_*`, stop, wait. `d_eff > range` -> chase; `d_eff < range_min` and the unit can move -> back off to `range_min + 1024`; else `stop` and, if no relevant mount has the target in arc, `turn_to(bearing - arc_center)`. Firing itself is P4.
* **`ORD_ATTACK_MOVE`** (`state`: `AM_MOVE 0`, `AM_ENGAGE 1`): `AM_MOVE` issues `move_to(dest)`, scans as `ST_AGGRESSIVE` (respecting `ST_HOLD_FIRE`) with `R_acq = range + 2048`. On a target: if `DefCombat.am_mode == 1` (aircraft, raiders) or every mount that can hit it has `fire_on_move == 1`, keep moving and let P4 fire; else stop, remember the origin point, `AM_ENGAGE`. `AM_ENGAGE` behaves like idle chase with leash 8192 from the origin; after 10 ticks without a target re-issue `move_to(dest)` and return to `AM_MOVE`. Arrival within 1024 of `dest` with no target -> `OS_DONE`.
* **`ORD_GUARD`** (target entity or point; aircraft: patrol): anchor = guarded entity position (follow when farther than 4096 and idle) or the point. Engage anything that qualifies within `GUARD_RADIUS` of the anchor or that recently damaged the guarded unit (`last_attacker_id` is a candidate with `THREAT_BONUS`); chase leash 6144; return to anchor when idle. Guarded entity dead -> `OS_DONE`.
* **`ORD_HOLD`**: `stop`, `hold_pos = 1`, fire at targets within `range_max_eff`, never move; runs until replaced; `on_order_start` clears `hold_pos` for any other order.
* **`ORD_FORCE_FIRE`**: target entity (any relation, `TS_FORCE`, visibility not required) or ground point (`ground_on = 1`). Move into range unless `hold_pos` or a structure (structures out of range -> `OS_FAILED`). Direct-fire weapons shoot at the point (splash hurts friendlies), artillery bombards. `ord.count > 0` decrements per salvo started and ends the order at 0; `count == 0` fires until replaced or the entity target dies (`OS_DONE`).
* **Commands** (`apply_command`, executed at their tick): `CMD_ATTACK` requires ownership, alive, armed, target exists, `rel == REL_ENEMY`, `SimVision.is_known`, and at least one mount able to engage (units failing the last check are skipped); `CMD_SET_STANCE` sets `stance`; `CMD_SCUTTLE` calls `scuttle`; `CMD_RETURN_TO_BASE` sets `MI_RETURN` for aircraft/drones. `queue` semantics are `SimOrder`'s.

**5.10.7 Domain rules.** AA weapons carry `TF_AIR` (dual-purpose flak also `TF_GROUND`; fighters have no ground bit — "no ground attack"); ground weapons never carry `TF_AIR`; anti-submarine weapons carry `TF_UNDERWATER` and no ordinary weapon does, so submerged, detected submarines are targetable only by ASW mounts; **strategic and depth-charge warheads include `LAYER_UNDERWATER` in `layer_mask`, so "strategic blast damage still applies"**. Boreal: its missile weapon has `req_layer = LAYER_SURFACE`; with a valid target it sets `want_surface = 1` (abilities surface it, camouflage ends, layer becomes `LAYER_SURFACE` for the 8 s window) and it becomes targetable by every `TF_SURFACE` weapon while surfaced. Harpoon Team / Sea Spear: `TF_GROUND, TF_SURFACE, TF_STRUCTURE`, never `TF_AIR`. Defensive structures: stance aggressive, no chase, `needs_power = 1` -> silent when `SimPower.defense_online(pid)` is false (SAP reserve honoured there) or EMP-shut; Watchtower/AA battery/Bastion Missile Tower per their descriptions. Independent mounts (`DefMount.independent`, e.g. Aegis: AA, ASW, gun) hold their own target in `M_TARGET`, scanned with only their weapon's filter and range.

### 5.11 Health, death, wrecks, chain effects

**`kill(e, cause, killer_id, killer_pid)`** — ordered, idempotent:
1. Return if `CF_DEAD`. A `KIND_WRECK` is only removed (`EV_WRECK_REMOVE reason 1`, `remove_deferred`) — no chain, no wreck, no occupants. `hp = 0`; `cflags |= CF_DEAD` (functionally gone for targeting, vision, power, production, victory, pathing; every system skips `CF_DEAD`); if `dying_ticks > 1` also `CF_DYING`.
2. Release links: clear target/beams/salvo; aircraft -> free pad (`pad_occ`), free carrier bay slot (`BAY_EMPTY`, start replacement); carrier -> every away drone gets `orphan_deadline = tick + orphan_ticks`; airfield -> parked aircraft keep `home_id = -1`; garrison/transport -> step 3.
3. **Occupants** (`DefDeath.cargo_mode`): `CARGO_DIE` — each passenger is killed (`CAUSE_CARGO`, same killer, no wreck); `CARGO_EJECT_HURT` — `SimTransport.eject_all`, then each passenger takes `mul(hp_max, eject_hurt_bp)` non-lethal (min hp 1); `CARGO_EJECT` — unharmed. Defaults: land transports/APCs/Landing Transport `CARGO_DIE` ("transports dying with cargo"); Beaver/Naga/Okapi-class "reinforced passenger protection" `CARGO_EJECT_HURT 3000`; civilian garrison buildings `CARGO_EJECT_HURT 2500`.
4. **Wreck** if all hold: `wreck_hp_bp > 0`, tags `land_vehicle` and `combat`, `cause == CAUSE_DAMAGE`, `killer_pid >= 0 and rel(killer_pid, e.owner) == REL_ENEMY` (friendly fire, scuttle, chain with no enemy credit produce none), none of `CF_SUMMONED/CF_DECOY/CF_SCUTTLED/CF_NO_WRECK`, `e.paid_cost > 0`, and `world.rules.salvage_enabled` (some player has the salvage trait). Spawn `KIND_WRECK` (`SimWorld.spawn_raw`): `def_idx = e.def_idx`, `owner = e.owner`, `hp = hp_max = max(WRECK_HP_MIN, mul(e.hp_max, wreck_hp_bp))`, `wreck_expire = tick + WRECK_TICKS (1200 = 60 s)`, `wreck_flags = WF_SALVAGEABLE`, `wreck_value = e.paid_cost` (**paid purchase cost, unaffected by later health research**), `wreck_owner_pid`, `EV_WRECK_ADD`. A wreck is never auto-targeted, is hit by splash of every warhead (all relations), can be force-fired (`KIND_WRECK`, `TF_WRECK`), dies at 0 hp (`EV_WRECK_REMOVE reason 1`), and vanishes in `cleanup()` at `wreck_expire` (reason 0). Salvage (economy's 8 s action) calls `try_salvage`; "each wreck pays once" = `WF_CONSUMED`.
5. **Chain effect**: `DefDeath.warhead >= 0` -> `spawn_remote(owner_pid = killer_pid >= 0 ? killer_pid : e.owner, ..., PK_STRIKE, delay = chain_delay, PI_CHAIN)` at the corpse position. Friendly fire applies (structure explosions hurt neighbours, including the killer's own units). At most `CHAIN_CAP 64` chain spawns per tick; the rest are deferred to the next tick in id order. Chains resolve in P5/P6 of the same or next tick, never recursively inside `kill`.
6. **Aircraft** (`DK_CRASH`): `dying_until = tick + crash_ticks`, `crash_v = (e.vx, e.vy)`; P1 moves it `pos += crash_v; crash_v = crash_v * 15 / 16` (truncating) while the view spins it down; at `dying_until` a `crash_warhead` strike at its position (friendly fire; kills things under it); hover/unmoving aircraft drop straight. EMP never triggers this (§5.8). Drones/missiles use `DK_AIR_EXPLODE` (no crash).
7. **Structures** (`DK_STRUCTURE`): footprint freed by `CleanupSystem` at removal; power, tech prerequisites and production react through `CF_DEAD` on the next tick; chain blast per profile (refinery/generator/superweapon = large), superweapon launcher destroyed during warning is polled by power.
8. `EV_DEATH`; player stats (`losses`, killer `kills`); `SimWorld.remove_deferred(e.id, tick + max(1, dying_ticks))`.

**`cleanup(world)`** (step 11): remove expired wrecks (`remove_deferred` + `EV_WRECK_REMOVE`), drop consumed wrecks, compact `armed_ids`/`status_ids`/`wreck_ids` for removed entities.

### 5.12 Aircraft: sorties, pads, rearm

Aircraft and airfield state live in `SimCompAir`. Missions arrive from order handlers (`SimAirSortie.assign_mission`); the machine below runs in P2. Movement executes the flight primitives; layer flips are mine (`e.layer` is `LAYER_GROUND` while `PARKED/REARM/TAKEOFF-start/LANDING-end`, `LAYER_AIR` otherwise).

| State | Entry | Behaviour | Exit |
|---|---|---|---|
| `AIR_PARKED` | landed, ammo full or no mission | idle on pad; does not scramble on its own (§12-8) | mission assigned and `fuel > 0` and some weapon has ammo -> `TAKEOFF` |
| `AIR_TAKEOFF` | | `air_takeoff`; pad released at start; `takeoff_ticks`; at the end `layer = LAYER_AIR` | -> `TRANSIT` |
| `AIR_TRANSIT` | | `air_fly_to(dest)`; dest = approach point / patrol centre / move point; fuel burns | arrive -> `ATTACK` or `PATROL` |
| `AIR_ATTACK` | | style-specific `sub` machine below; auto-picks the next target within `retarget_radius` after a kill | ammo empty (no offensive weapon has ammo) or target gone with none nearby -> `RETURN` |
| `AIR_PATROL` | | `air_orbit(centre, orbit_radius)`; scans for `TF_AIR`/mask targets within `patrol_radius` (stance permitting); engages then resumes | fuel low / ammo empty -> `RETURN` (remembers `resume_*`) |
| `AIR_RETURN` | | pick pad: home airfield if alive, else nearest own airfield; deterministic tie-break: smaller squared distance, then lower airfield id, then lower pad index; reserve pad; `air_fly_to(pad)`; if none free, orbit the airfield (`fuel` keeps burning) and retry every 10 ticks (lowest aircraft id wins a freed pad) | within landing distance -> `LANDING`; no airfield exists -> `AIR_NO_BASE` |
| `AIR_LANDING` | | `air_land_at(pad)`, `landing_ticks`, at touchdown `layer = LAYER_GROUND` | -> `REARM` (or `PARKED` if full) |
| `AIR_REARM` | | each tick, if the airfield `is_functional` (powered, not EMP-shut): `rearm_prog += 10000 + sum_bp(airfield, STAT_REARM_RATE)`; every `rearm_ticks*10000/total_ammo_units` progress restores one ammo unit (slot order); fuel refilled on touchdown | all ammo restored -> `PARKED`; with `auto_resume` and a stored mission -> `TAKEOFF` |
| `AIR_NO_BASE` | no airfield | orbit current position at zero fuel cost, keep ammo/attack ability | a pad appears -> `RETURN` |
| `AIR_DOCKED` | drone inside carrier | `container_id = carrier id` (untargetable, not in the spatial hash), position mirrors carrier | launch -> `TAKEOFF` (instant) |

* **Order mapping.** `ORD_ATTACK` -> `MI_ATTACK` (order ends `OS_DONE` when the target is dead and no `resume` is stored, or the aircraft lands with no mission); `ORD_ATTACK_MOVE` -> `MI_ATTACK_MOVE`; `ORD_GUARD` -> `MI_PATROL` (runs until replaced); `ORD_FORCE_FIRE` on a ground point -> `MI_ATTACK` on the point (bombers, gunships); `ORD_HOLD` and `CMD_RETURN_TO_BASE` -> `MI_RETURN`; a plain move order -> `MI_MOVE`. `assign_mission` refuses (returns false, order `OS_FAILED`) when `fuel == 0` or no usable ammo remains.
* **Fuel.** `fuel` decrements per airborne tick (stride-4 states subtract the elapsed ticks); forced return when `fuel <= fuel_reserve + dist(pos, pad)/speed` (integer estimate). No pad -> no fuel penalty (recommended resolution of the bible's silence; §12-7).
* **Rearm time.** Base `PD_REARM_TICKS` (USA `-20 %` and Integrated Flight Decks `-15 %` are in it; Japan's reload bonus is not) `x` airfield rate. Full rearm from empty takes exactly `rearm_ticks` at rate 10000. Worked: `rearm 240`, 6 units -> one unit per 40 ticks; with **Rapid Turnaround** (`+5000`) units at ticks 27, 54, 80, 107, 134, 160. Aircraft *cannot rearm without a powered, functional pad*; carriers replenish only their own drones (§5.13); pad count is `PD_PAD_COUNT` (Dispersed Runways +2), resized by `SimAirSortie.on_pads_changed`.
* **Attack styles** (`DefAir.style`; all fire through the normal P4 weapon logic once geometry allows):
  * `AS_HOVER` (Titan, Osprey, Hammerhead, Sarus): `hover_dist = mul(range_max_eff, hover_bp)`; hover point `H = T + unit(P - T) * hover_dist`; `air_fly_to(H)`, then `air_hover` + `air_face(bearing)`; re-position (throttled 10 ticks) if the target drifts out of range. Vulnerable while hovering by design.
  * `AS_MISSILE_RUN` (Nightjar): `air_fly_to(T)`; fire when `d_eff <= 0.95*range` and heading error `<= arc_half`; then egress to `T + unit(heading)*egress_dist`, re-approach if ammo and target remain, else `RETURN` ("one salvo before rearm": `ammo_max 1`).
  * `AS_BOMB_RUN` (Burya, Condor, Silkwing): run direction `u = unit(T - P)` fixed at run start; waypoint `W = T + u*egress_dist`. Each tick: `Q = P + V*fall_ticks`; `along = ((T.x-Q.x)*ux + (T.y-Q.y)*uy) >> 16`; stick length `S = (burst-1)*|V|*burst_interval`; **release the salvo when `along <= S/2 + |V|/2`** (error <= half a tick of flight; the stick is centred on `T`); bombs are `PK_BOMB` with `end = release_pos + V*fall_ticks + scatter`. Worked: `V = 614 u/tick`, `fall 16` -> lead point 9824 u ahead; 6 bombs at interval 3 -> stick 9210 u long. After the last bomb -> `EGRESS` to `W`, repeat if ammo and target remain, else `RETURN`. Condor: `ammo_max 1`, one heavy bomb, `camouflage` handled by abilities (its `last_fire_tick` reveals it).
  * `AS_STRAFE`: approach, fire in the cone until `d < strafe_min_sep` or `strafe_max_ticks`, break away, re-approach.
  * `AS_DOGFIGHT` (fighters vs aircraft): `air_fly_to(T + T.v*8)`; fire missiles/guns when in cone and range; break away deterministically when `d < 2048` (`break = P + unit(facing + sign*512)*6144`, `sign = +1 if ((id ^ (tick/40)) & 1) == 0 else -1`).
* **Air-superiority patrol** = `ORD_GUARD` on aircraft: orbit + engage air targets; returns for rearm at `fuel_reserve`/empty and resumes automatically (`auto_resume`).
* **EMP on aircraft**: weapons offline, flight continues (§5.8). **Parked aircraft** are ground targets; a destroyed airfield leaves parked aircraft alive but homeless.

### 5.13 Carriers and drones

`SimCompCarrier` has `bays` slots. Bay states: `BAY_EMPTY` (replacement pending), `BAY_DOCKED` (ready), `BAY_AWAY`, `BAY_REARM`.
* **Launch.** Carrier functional, wing weapon (`DefCarrier.wing_weapon[wing]`, used only for target filter and `launch_range`) has a valid target (normal acquisition) -> every `launch_interval` ticks launch up to `launch_batch` docked drones: `container_id = -1`, position = carrier + bay offset, `AIR_TAKEOFF` (instant), mission `MI_ATTACK(target)` with `home_kind = HOME_CARRIER`. Drones are ordinary aircraft entities (`unmanned`, individually targetable, excluded from the unit cap by spawn flag) that auto-pick new targets within `tether` of the carrier.
* **Recall.** No valid target for `recall_delay` ticks, target beyond `tether`, `ST_HOLD_FIRE`, wing switch requested, or drone ammo empty -> `MI_RETURN` to the carrier's *current* position; docking when within `dock_radius` (1536): `BAY_REARM`, rearm takes the drone's `rearm_ticks` (Integrated Flight Decks); **only the carrier's own drones dock/rearm here**; then `BAY_DOCKED`.
* **Replacement.** A lost drone empties its bay: try `SimEconomy.try_spend(pid, replace_cost)` (retry every 20 ticks; cost is balance-designed because the bible leaves it null); on success wait `PD_REPLACE_TICKS` (Integrated Flight Decks `-15 %`, Predictive Maintenance `-20 %` for Shogun), then spawn the drone docked. Replacement only ever produces the current wing's drone type.
* **Wing switch (Shogun).** `request_wing(w)` sets `wing_req`; all away drones recall; when every drone is docked, for `wing_switch_ticks` the bays retool (no credits), then `wing = wing_req`. "Only one wing type operates at a time." Interceptor wing uses `AS_DOGFIGHT` around the carrier (`MI_ESCORT`).
* **Carrier death**: away drones die `orphan_ticks` (60) later (`CAUSE_ORPHAN`, no wreck); docked drones die with it.

### 5.14 Lease catalogue — how each bible effect reaches combat (owner of the call = abilities/zone unless "static")

Keys `FXK_*` are allocated by abilities; equal keys never stack, different keys add inside the temporary layer. `T` = ticks of duration.

| Bible effect | Stat, bp, filter | Applied to |
|---|---|---|
| NEC Relay networked fire (+10 %; Treaty Coordination +15 %; Dispersed Links Fen mast) | `DMG_OUT +1000/+1500`, key `RELAY` | own combat infantry + land combat vehicles in 6 cells (8 with Distributed Control) of a powered Relay |
| Han command field (+10 %; Central Priority +20 %) | `DMG_OUT +1000/+2000`, key `CMDFIELD` | own unmanned combat units in 5 (7) cells of an un-suppressed provider; provider `is_suppressed` removes it |
| Combined Arms Window | `DMG_OUT +1000` | infantry, land vehicles, aircraft (not ships, structures), 15 s |
| Capacitor Discharge | `DMG_OUT +2000`, then `lock_weapons(+80)` | thermal-beam units + Sunwall, 10 s |
| Precision Window | `DMG_OUT +2000` | aircraft + ships, 10 s |
| Harbor Militia / Island Raider | `DMG_OUT +1000` / `+2000` | Gate Guards near Factory/Dock / 6 s after disembarking |
| Counterbattery Solution | `MARK +1500`, filter = marking team bit + `256` (ground weapons only), 12 s | marked enemy artillery |
| Shared Fire Solutions; Coordinated Barrages; Forward Fire Control; Observer Network | `RELOAD -1000` | Marte/Charlemagne in Relay field; Anvil/Colossus stationary 4 s; Outrider near Wedge; Shaheen near Watchpost |
| Assault Coordination; Software Surge | `RELOAD -1500`; `RELOAD -2500` then `lock_weapons(+60)` | tanks 12 s; unmanned units 12 s (not superweapon summons) |
| Armored Overwatch; Straits Crossfire; Joint Tactical Links; Charlemagne/Gaj deploy | `RANGE +1000` (stationary tanks); `+1000` infantry + ships; `+1000` Sentinel/Aegis near infantry; `+2500` / `+2000` while `ext_deployed` | as named |
| Adaptive Plating; Sealed Compartments; Thermal Shrouds | **static** rows (layer 3): `EXPLOSIVE 1000`; `EXPLOSIVE 1500` with `COND_ON_WATER`; `THERMAL 1000` | land combat vehicles; Beaver + Narwhal; light land vehicles |
| Layered Fieldworks; Emergency Earthworks | lease `TAKEN EXPLOSIVE 1000` / `2000` | infantry within 4 cells of a friendly defence / infantry + defences in zone, 15 s |
| Dust Screen (also Broken Contact, Concealed Crossing, Naga smoke) | `TAKEN 3000`, `FILTER_DIRECT_ONLY` | all ground units in the smoke, friend and foe, per tick lease |
| Steel Advance; Protected Advance; Emergency Fortification | `TAKEN 2000` / `1500` / `2500`, `FILTER_ALL_WEAPON` | land vehicles / infantry + land vehicles / defences + production buildings (not the superweapon structure), 12/12/15 s |
| Joint Landing; River Marine | `TAKEN 2000`, `FILTER_ALL_WEAPON`, 120 ticks | 6 s after disembarking (no refresh on immediate reboard) |
| Portable cover; Vanguard cover; shelter | `TAKEN BULLET 2000`; `2000`; `2500` | occupant infantry, while cover/shelter lives (45 s) and (Vanguard) stationary |
| Gate Guard shield; Marte/Ibex/Bear armor | **static** `dir_rows` | see §5.6.1 |
| Signal Officer / Echo Team | `SUP_RECOVER +5000` | infantry within 5 cells |
| Coordinated Advance; Civil Defense Net | `FLAG_SUP_IMMUNE` + `clear_suppression` | infantry in zone |
| Redundant Orders | `FLAG_EMP_IMMUNE` | vehicles in zone, 10 s |
| Buried Command Lines; Resilient Mesh | **static** `PD_EMP_RECOVER_BP 2500` | Radar + defensive structures; unmanned units |
| Rapid Turnaround | `REARM_RATE +5000` on one powered Airfield, 20 s | pads |
| Field Refurbishment | `lock_weapons(now+2)` each tick while repairing | vehicles being repaired |
| Saudi thermal +15 %, El Andalus garrison +20 %, Pakistan missile speed +20 %, artillery range, reload, ship/aircraft reload, USA rearm | **static** `PM_*` / `PD_*` | resolved by `GameData`, never leases |

### 5.15 Bible rule -> mechanism matrix

| Bible rule | Honoured by |
|---|---|
| Damage-bearing area attacks hurt friendlies; Aurora enemies only; summoned attackers select enemies only | `friendly_fire = 1` default for splash; Aurora warhead `0`; `CF_ENEMY_ONLY` in `can_engage` and `PI_ENEMY_ONLY` on their projectiles (§5.5, §5.10.1) |
| Combined resistance <= 50 %, interception removes the projectile | `TAKEN_MIN_BP`; APS/zone removal happens before the pipeline (§5.6, §5.7) |
| Trident: ordinary missile/shell destroyed for 1 charge; packet reduced 50 % for 8 charges, never cancelled; Helios/Aurora/beams/bullets/EMP bypass | §5.7 |
| Suppression: 3 suppressive hits in 2 s -> -25 % infantry speed for 3 s after the last; only Fortress Guard and Watchtower fire suppressive | §5.9 (`suppressive` warhead flag) |
| Portable cover 20 % bullet; shelter 25 %; Gate Guard 25 % frontal bullet, not blasts/behind; Dust Screen 30 % direct-fire only | leases/static rows with filters (§5.6.1, §5.14) |
| Camouflage revealed by firing or taking damage | `last_fire_tick`, `last_hit_tick` published |
| EMP never changes ownership / instantly kills aircraft; recover-sooner research; Redundant Orders | §5.8 |
| Submarines: only ASW targets underwater; strategic blast still applies; Boreal surfaces to fire | §5.10.7 |
| Wrecks: enemy land combat vehicles, 60 s, destroyable, salvage 20 % of paid cost once; none from friendly fire, scuttling, summons, decoys | §5.11 step 4 |
| Aircraft need powered Airfield pads to rearm; carriers replenish only their own drones; Rapid Turnaround; Dispersed Runways | §5.12, §5.13 |
| Transports do not fire passengers' weapons; civilian garrisons hold squads that fire (+20 % El Andalus) | `garrison_fire`, `PM_DMG_BP_GARRISON` (§5.3 gate 1) |
| Reload floor 50 % of base; range/flight-speed/damage layers | `PM_*` resolution + `reload_eff` (§4.6, §5.3) |
| Power shortage stops powered defences (SAP reserve) | `is_functional` (§3.7) |
| Fog/detection gate targeting; decoys look real until identified | `SimVision.can_see`, `decoy_identified` (§5.10.1) |
| No veterancy in the prototype | pipeline has no veterancy term |

---
## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

### 6.1 Commands consumed (block 40..47 requested from sim_core; all validated at *execution* tick inside `SimOrderCombat.apply_command`; invalid entries are skipped deterministically, never an error)

| Code | Name | Payload (ints / `PackedInt32Array`) | Validation | Result |
|---|---|---|---|---|
| 40 | `CMD_ATTACK` | `ids`, `target_id`, `queue` | ids owned by the issuing player, alive, armed; target exists, is not a `KIND_WRECK` (wrecks are force-fire only), `REL_ENEMY`, `SimVision.is_known`; >= 1 mount can engage | `ORD_ATTACK` |
| 41 | `CMD_ATTACK_MOVE` | `ids`, `x`, `y`, `queue` | in map bounds | `ORD_ATTACK_MOVE` |
| 42 | `CMD_GUARD` | `ids`, `target_id` (-1 = point), `x`, `y` | target is SELF/ALLY; or point in bounds | `ORD_GUARD` (aircraft: air patrol) |
| 43 | `CMD_HOLD` | `ids` | — | `ORD_HOLD` |
| 44 | `CMD_FORCE_FIRE` | `ids`, `target_id` (-1 = ground), `x`, `y`, `count` | ground point in bounds, or any existing entity | `ORD_FORCE_FIRE` |
| 45 | `CMD_SET_STANCE` | `ids`, `stance` | `0..3` | `cc.stance` |
| 46 | `CMD_SCUTTLE` | `ids` | own units (structures use *sell*) | `scuttle()` — no wreck, no salvage |
| 47 | `CMD_RETURN_TO_BASE` | `ids` | aircraft or drones | `MI_RETURN` |

Consumed but owned elsewhere: `CMD_STOP` (calls `clear_target` and `on_order_start`), `CMD_DEPLOY/UNDEPLOY/SET_MODE` (abilities). **Flag:** sim_core must reserve the 40..47 block and the `ORD_*` 40..44 block, and route them to `SimOrderCombat`.

### 6.2 Events emitted (block 200..229 requested; 221..229 spare). Container: `SimEvent{type, tick, x, y, a, b, c, d, e, f}` (ASSUMPTION(sim_core); positions in sub-cell units). Output-only (DR-12).

| Code | Name | x,y | a | b | c | d | e | f |
|---|---|---|---|---|---|---|---|---|
| 200 | `EV_FIRE` | muzzle | shooter id | weapon idx | `mount \| barrel<<4 \| projkind<<8 \| result<<12 \| burst_i<<16`; result 0 projectile, 1 hitscan hit, 2 hitscan miss, 3 beam | target id / -1 | aim or impact x | aim or impact y |
| 201 | `EV_PROJ_SPAWN` | start | serial | projectile idx | `owner_pid \| kind<<4 \| flight_ticks<<16` | target id / -1 | end x | end y |
| 202 | `EV_PROJ_END` | last pos | serial | reason 0 expired, 1 APS, 2 zone, 3 instant fallback, 4 sweep done | interceptor entity/zone id / -1 | | | |
| 203 | `EV_IMPACT` | centre | warhead idx | serial / -1 | `hit_kind \| reduced<<4 \| miss<<5`; hit_kind 0 ground, 1 unit, 2 structure, 3 air, 4 surface, 5 underwater, 6 wreck | splash radius (units) | total damage dealt | `owner_pid \| victims<<4` |
| 204 | `EV_HIT` (coalesced per victim per tick) | victim | victim id | damage this tick | last attacker id | `dtype \| dc<<8 \| flags<<16`; flags 1 killed, 2 suppression started, 4 resist cap reached, 8 directional armor applied, 16 packet reduced, 32 EMP | hp after | hp_max |
| 205 | `EV_BEAM_START` | muzzle | shooter | weapon idx | mount | target id | beam_max_ticks | |
| 206 | `EV_BEAM_END` | | shooter | reason 0 lost, 1 overheat, 2 disabled, 3 target dead, 4 order change, 5 out of range | mount | | | |
| 207 | `EV_SWEEP` | A | serial | warhead idx | `duration \| delay<<16` | width (units) | B x | B y |
| 208 | `EV_DEATH` | position | entity id | def idx | `death_kind \| cause<<4 \| flags<<8`; flags 1 wreck entity created, 2 crash, 4 decoy, 8 summoned, 16 structure, 32 had occupants, 64 unit, 128 aircraft | killer entity id / -1 | `(killer_pid+1) \| (owner+1)<<8` | `facing \| layer<<12 \| visual_ticks<<16` |
| 209 | `EV_WRECK_ADD` | position | wreck id | source def idx | expiry tick | former owner pid | flags | value (credits) |
| 210 | `EV_WRECK_REMOVE` | | wreck id | reason 0 expired, 1 destroyed, 2 salvaged, 3 cleanup | | | | |
| 211 | `EV_INTERCEPT` | position | projectile serial / -1 (packet) | interceptor entity id (APS) or zone id | kind 0 APS kill, 1 zone kill, 2 packet reduced | charges left (zone) / ready tick (APS) | projectile owner pid | interceptor owner pid |
| 212 | `EV_SUPPRESS` | victim | victim id | 1 begin / 0 end | | | | |
| 213 | `EV_EMP` | victim | victim id | duration ticks | 0 weapons off, 1 shutdown | attacker pid | 1 = blocked by immunity | |
| 214 | `EV_ATTACK_ALERT` | victim | victim owner pid | victim id | attacker pid | class 0 unit, 1 structure, 2 collector, 3 aircraft | | |
| 215 | `EV_AIR_STATE` | | aircraft id | new state | pad idx / -1 | home id | substate | |
| 216 | `EV_REARM` | | aircraft id | 0 begin, 1 ammo unit restored, 2 complete | ammo units now | airfield id | | |
| 217 | `EV_DRONE` | | carrier id | drone id | 0 launch, 1 dock, 2 lost, 3 replace start, 4 replace done, 5 wing switched | bay idx | | |
| 218 | `EV_EJECT` | position | container id | passenger id | 0 garrison collapse, 1 transport death | | | |
| 219 | `EV_CRASH` | position | aircraft id | 0 start, 1 ground impact | ticks left | | | |
| 220 | `EV_WEAPON_LOCK` | | entity id | 1 offline / 0 online | 0 EMP, 1 `lock_weapons`, 2 power | | | |

Splash-less hitscan hits emit no `EV_IMPACT`: the view derives spark/decal from `EV_FIRE` (`result` 1/2, `(e,f)`) and `EV_HIT`. `EV_ATTACK_ALERT` is rate-limited (`ALERT_COOLDOWN 200` ticks per player unless `ALERT_DIST 15360` from the last alert). Cosmetic `EV_FIRE` may be capped at 128 per tick by a count-based, hence deterministic, rule (infantry burst events are dropped last-in first); no other event is ever dropped.

### 6.3 What the view/audio needs — recipes

| Presentation | Events / reads |
|---|---|
| Muzzle flash, recoil, fire sound | `EV_FIRE` (`b` -> `DefWeapon.fx_muzzle/sfx`; `c` mount/barrel picks the model anchor) |
| Hitscan tracer / miss spark | `EV_FIRE` with `result` 1/2 and `(e,f)` = impact; streak colour from the warhead `dtype` |
| Projectile mesh, trail | `EV_PROJ_SPAWN` then per-frame mirror of `world.projectiles` (`x,y,px,py,heading`); arcs/strikes may be animated from `start,end,flight` alone; remove on `EV_PROJ_END` or `EV_IMPACT` |
| Explosion, decal, camera shake | `EV_IMPACT` (`a` -> `DefWarhead.fx`; `d` = radius; `e` = damage for shake amplitude) |
| Hit flash, smoke stages, squad members falling | `EV_HIT` (`e/f` = hp fraction) |
| Kill, wreck, corpse, crash | `EV_DEATH` (`c` death kind), `EV_WRECK_ADD/REMOVE`, `EV_CRASH` |
| Turret orientation | read `e.combat.mnt[m*MS + M_ANGLE]` each frame (interpolated with `prev`) |
| Continuous beams | `EV_BEAM_START/END`, while on: `mnt[m*MS+M_BEAM] >= 0` and the mount's target (`M_TARGET` or `cc.target_id`) |
| Helios sweep | `EV_SWEEP`: hot spot = A + (B-A)*(t - t_event - delay)/duration |
| Suppression icon, EMP sparks, weapons-offline icon | `EV_SUPPRESS`, `EV_EMP`, `EV_WEAPON_LOCK` |
| "Base under attack" voice / minimap ping | `EV_ATTACK_ALERT` |
| Interception flash | `EV_INTERCEPT` |
| Aircraft gear/rotors/hover pose, rearm progress bar | `EV_AIR_STATE`, `EV_REARM`, `e.air.state` |

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

All under `game/data/balance/`; numbers in **human units** (cells, seconds, degrees, percent); `DefCombatCompiler` converts once at load (DR-10) and the converted ints enter the data hash. Ids are strings; every unit/structure key is a bible id.

### 7.1 Conversion rules (integer-exact; `*_m` = value rounded to milli-units first: `m = roundi(v*1000)`)

| Field | Formula |
|---|---|
| `*_cells` -> units | `(m*1024 + 500) / 1000` |
| `*_s` -> ticks | `(m*20 + 999) / 1000` (ceil) |
| `speed_cps` -> units/tick | `(m*1024 + 10000) / 20000` |
| `turn_dps` -> bat/tick | `(m*4096 + 3600000) / 7200000` |
| `*_deg` -> bat | `(m*4096 + 180000) / 360000` (`arc_deg` halved first) |
| `*_pct` -> bp | `pct*100` |

### 7.2 `combat_rules.json` — global constants (defaults in §4.1)

```json
{ "schema": "meridian.combat_rules/1",
  "consts": { "scan_interval_unit_ticks": 6, "scan_interval_struct_ticks": 8, "scan_interval_air_ticks": 4, "rescore_ticks": 20,
              "scan_budget_base": 24, "scan_cand_cap": 48, "suppression_hits": 3, "suppression_window_s": 2.0, "suppression_tail_s": 3.0,
              "suppression_speed_pct": 75, "resist_cap_pct": 50, "chip_floor_pct": 5, "wreck_s": 60, "wreck_hp_min": 150,
              "proj_pool": 4096, "proj_strategic_reserve": 256, "aim_tol_deg": 2.0, "approach_pct": 90 },
  "death_strike_projectile": "proj.strike_instant",
  "default_prio": { "decoy": 1, "civilian": 1, "wreck": 0, "structure": 3, "service": 3, "infantry": 6, "tank": 8, "artillery": 9, "defense": 10 } }
```

### 7.3 `combat_warheads.json`

```json
{ "schema": "meridian.combat_warheads/1", "warheads": {
  "wh.shell_medium":  { "damage": 60, "type": "explosive", "delivery": "direct",
                        "splash": { "outer_cells": 1.0, "inner_cells": 0.3, "edge_pct": 30 },
                        "layers": ["ground", "surface"], "friendly_fire": true, "fx": "expl_medium" },
  "wh.perun_core":    { "damage": 1400, "type": "explosive", "delivery": "strategic", "packet": true,
                        "splash": { "outer_cells": 3.0, "inner_cells": 1.5, "edge_pct": 50 },
                        "layers": ["ground", "surface", "underwater"], "friendly_fire": true, "fx": "expl_strategic_large" },
  "wh.perun_ring":    { "damage": 350, "type": "explosive", "delivery": "strategic", "packet": true,
                        "splash": { "min_cells": 3.0, "inner_cells": 3.0, "outer_cells": 7.0, "edge_pct": 30 },
                        "layers": ["ground", "surface", "underwater"], "friendly_fire": true, "fx": "expl_fragment_ring" },
  "wh.aurora_pulse":  { "damage": 40, "type": "emp", "delivery": "strategic", "packet": false,
                        "splash": { "outer_cells": 8.0, "inner_cells": 8.0, "edge_pct": 100 },
                        "layers": ["ground", "surface", "air"], "friendly_fire": false,
                        "emp": { "unit_s": 8, "structure_s": 18, "classes": ["vehicle", "ship", "aircraft", "structure"] }, "fx": "emp_pulse" },
  "wh.helios_beam":   { "damage": 60, "type": "thermal", "delivery": "strategic", "packet": false,
                        "layers": ["ground", "surface"], "friendly_fire": true, "fx": "beam_thermal_hit" },
  "wh.hmg_suppress":  { "damage": 6, "type": "bullet", "delivery": "direct", "suppressive": true, "layers": ["ground", "surface"], "fx": "hit_bullet" } } }
```

### 7.4 `combat_projectiles.json`

```json
{ "schema": "meridian.combat_projectiles/1", "projectiles": {
  "proj.hitscan":        { "kind": "hitscan" },
  "proj.beam":           { "kind": "beam" },
  "proj.shell_fast":     { "kind": "bullet",  "speed_cps": 40, "life_s": 1.2, "hit_radius_cells": 0.06, "spread_deg": 0.5, "lead_pct": 100, "flags": [] },
  "proj.at_missile":     { "kind": "missile", "speed_cps": 14, "life_s": 2.5, "hit_radius_cells": 0.15, "turn_dps": 140,
                           "launch_delay_s": 0.15, "homing_delay_s": 0.25, "flags": ["guided", "aps", "zone"] },
  "proj.howitzer_shell": { "kind": "arc", "speed_cps": 15, "min_flight_s": 0.5, "max_flight_s": 4.0, "arc_pct": 40,
                           "scatter_min_cells": 0.1, "scatter_max_cells": 1.5, "lead_pct": 50, "flags": ["zone"] },
  "proj.bomb_heavy":     { "kind": "bomb", "fall_s": 0.8, "scatter_max_cells": 0.4, "flags": [] },
  "proj.atlas_rod":      { "kind": "strike", "flags": ["strategic"] },
  "proj.strike_instant": { "kind": "strike", "flags": [] },
  "proj.helios_sweep":   { "kind": "sweep", "spot_len_cells": 3.0, "width_cells": 3.0, "dot_interval_s": 0.25, "flags": ["strategic"] } } }
```

### 7.5 `combat_weapons.json` (with archetype inheritance: `extends` shallow-merges the parent, child wins)

```json
{ "schema": "meridian.combat_weapons/1", "weapons": {
  "weapon.tank_cannon_medium": { "projectile": "proj.shell_fast", "warhead": "wh.shell_medium", "targets": ["ground", "surface", "structure"],
      "range_cells": 8.0, "min_range_cells": 0, "reload_s": 1.5, "burst": 1, "burst_interval_s": 0, "aim_delay_s": 0.15,
      "fire_on_move": true, "auto_min_eff_pct": 15, "class": ["anti_armor"], "fx_muzzle": "muzzle_cannon", "sfx": "cannon_medium" },
  "weapon.inf_rifle": { "projectile": "proj.hitscan", "warhead": "wh.rifle_bullet", "targets": ["ground", "surface", "structure"],
      "range_cells": 5.5, "reload_s": 0.75, "burst": 3, "burst_interval_s": 0.15, "aim_delay_s": 0.1, "fire_on_move": true,
      "accuracy": { "base_pct": 80, "falloff_pct": 30, "moving_target_pct": 15, "moving_shooter_pct": 25 }, "class": ["anti_infantry"] },
  "weapon.javelin": { "extends": "weapon.at_missile_inf", "range_cells": 7.5, "reload_s": 3.5, "fire_on_move": false, "settle_s": 0.3 },
  "weapon.sunlance_beam": { "projectile": "proj.beam", "warhead": "wh.sunlance_dot", "targets": ["ground", "surface", "structure"],
      "range_cells": 9.0, "reload_s": 3.0, "beam": { "max_s": 6.0, "ramp_start_pct": 40, "ramp_s": 3.0, "dot_s": 0.2 }, "class": ["anti_armor"] },
  "weapon.nightjar_salvo": { "extends": "weapon.strike_missiles", "ammo": { "salvos": 1 }, "burst": 4, "burst_interval_s": 0.15 },
  "weapon.paladin_howitzer": { "projectile": "proj.howitzer_shell", "warhead": "wh.howitzer_155", "targets": ["ground", "surface", "structure"],
      "range_cells": 18.0, "min_range_cells": 5.0, "reload_s": 4.0, "requires": { "deployed": true }, "class": ["artillery"] },
  "weapon.boreal_missile": { "projectile": "proj.sub_missile", "warhead": "wh.sub_missile", "targets": ["ground", "surface", "structure"],
      "range_cells": 20.0, "min_range_cells": 4.0, "reload_s": 5.0, "requires": { "layer": "surface" }, "class": ["artillery"] } } }
```

Entries referenced above but omitted for brevity (defined in the same files): parents `weapon.at_missile_inf`, `weapon.strike_missiles`; warheads `wh.rifle_bullet`, `wh.sunlance_dot`, `wh.howitzer_155`, `wh.sub_missile`, `wh.death_vehicle`, `wh.crash_impact`; projectiles `proj.sub_missile`.

### 7.6 `combat_loadouts.json` — per-entity combat blocks and profiles

```json
{ "schema": "meridian.combat_loadouts/1",
  "units": {
    "unit.napc.guardian_tank": { "prio": 8, "stance": "aggressive", "am_mode": "stop", "death": "death.vehicle_medium",
        "mounts": [ { "weapon": "weapon.tank_cannon_medium", "kind": "turret", "arc_deg": 360, "turn_dps": 90, "offset_cells": [0.5, 0.0], "barrels": 1 } ] },
    "unit.olm.gate_guard": { "prio": 6, "death": "death.infantry",
        "mounts": [ { "weapon": "weapon.inf_rifle", "kind": "fixed", "arc_deg": 360 } ],
        "dir_armor": [ { "types": ["bullet"], "direct_only": true, "center_deg": 0, "half_deg": 60, "resist_pct": 25, "layer": "base" } ] },
    "unit.def.ural_assault_tank": { "prio": 8, "death": "death.vehicle_heavy", "aps": { "count": 1, "cooldown_s": 12, "radius_cells": 3.0 },
        "mounts": [ { "weapon": "weapon.tank_cannon_heavy", "kind": "turret", "arc_deg": 360, "turn_dps": 60, "offset_cells": [0.6, 0.0] } ] },
    "unit.olm.nightjar_strike_drone": { "prio": 9, "death": "death.aircraft_drone", "air": "air.missile_drone",
        "mounts": [ { "weapon": "weapon.nightjar_salvo", "kind": "fixed", "arc_deg": 20, "offset_cells": [0.6, 0.0] } ] },
    "unit.pd.tempest_carrier": { "prio": 9, "death": "death.ship_large", "carrier": "carrier.tempest", "mounts": [] } },
  "structures": {
    "structure.shared.aa_battery": { "prio": 10, "needs_power": true, "death": "death.structure_medium",
        "mounts": [ { "weapon": "weapon.aa_missile_battery", "kind": "turret", "arc_deg": 360, "turn_dps": 120, "offset_cells": [0, 0] } ] },
    "structure.shared.airfield": { "prio": 3, "death": "death.structure_large", "pad_count": 4,
        "pads_cells": [[-1.5, -1.0], [1.5, -1.0], [-1.5, 1.0], [1.5, 1.0]] } },
  "death_profiles": {
    "death.vehicle_medium": { "kind": "vehicle", "chain": { "warhead": "wh.death_vehicle", "delay_s": 0.1 }, "dying_s": 0.05, "wreck_hp_pct": 20, "cargo": "die" },
    "death.aircraft_fighter": { "kind": "crash", "crash_s": 1.5, "crash_warhead": "wh.crash_impact", "dying_s": 1.5, "visual_s": 2.0 },
    "death.infantry": { "kind": "infantry", "dying_s": 0.05, "visual_s": 2.0, "wreck_hp_pct": 0 } },
  "air_profiles": {
    "air.missile_drone": { "style": "missile_run", "fuel_s": 90, "fuel_reserve_s": 12, "rearm_s": 15, "takeoff_s": 1.0, "landing_s": 1.5,
        "approach_cells": 10, "egress_cells": 8, "auto_resume": true, "retarget_cells": 8 } },
  "carrier_profiles": {
    "carrier.tempest": { "bays": 4, "wings": [ { "unit": "unit.pd.tempest_strike_drone", "weapon": "weapon.tempest_launch_filter" } ],
        "launch_range_cells": 12, "tether_cells": 14, "dock_cells": 1.5, "launch_interval_s": 1.0, "launch_batch": 2, "recall_delay_s": 3,
        "replace_s": 25, "replace_cost": 120, "wing_switch_s": 5, "orphan_s": 3 } } }
```
Omitted but referenced: `death.vehicle_heavy`, `death.aircraft_drone`, `death.ship_large`, `death.structure_medium`, `death.structure_large`, `weapon.tank_cannon_heavy`, `weapon.aa_missile_battery`, `weapon.tempest_launch_filter`. `dir_armor` rows compile as: `types` names -> type bit mask; `direct_only: true` -> `req DC_DIRECT, forbid DC_SPLASH|DC_INDIRECT|DC_STRATEGIC`; `layer` base/parent/sub/research -> 0..3; `resist_pct` -> `bp` (negative = vulnerability). `pads_cells` -> `pad_offsets`. (`unit.pd.tempest_strike_drone` is a *combat-domain-requested* def: the bible defines no carrier drone units; data must add drone defs, unmanned/aircraft-tagged, `no_cap`. See §13-19.)

### 7.7 Resolution of bible selectors and modifier stats (for the data architect)

* `selector.thermal_beam_weapons` (`unresolved_target_domain`) := every weapon whose warhead `dtype == DT_THERMAL`, plus the Helios sweep warhead (`superweapon.olm.helios_reflector`). Members: Sunlance, Ifrit prism, Sunwall, Helios. **Not** members: Dawn Laser (`DT_BEAM`), Aurora (EMP). Saudi `+15 %` -> `PM_DMG_BP` of those mounts and the Helios warhead's snapshot; Thermal Shrouds `-10 % thermal` -> a `DT_THERMAL` resistance row.
* `selector.ordinary_guided_missiles` := projectile defs with `PF_GUIDED` and without `PF_STRATEGIC` (guided missiles **including** precision missile artillery flagged `guided` — Saker, Shaheen, Fjord — because they are guided missiles). Pakistan `+20 %` -> `PM_PROJ_SPEED` (arc missiles: shorter flight).
* Bible stat -> field: `weapon_range_cells -> PM_RANGE_MAX` (layers multiply; `PM_RANGE_MIN` untouched); `reload_interval_seconds -> PM_RELOAD` (floor 50 % of base); `weapon_damage -> PM_DMG_BP` (+`_GARRISON` for the conditional El Andalus delta); `projectile_flight_speed -> PM_PROJ_SPEED`; `rearm_time_seconds -> PD_REARM_TICKS`; research resistances -> `presist` rows (layer 3); carrier/APS/EMP/pad research -> `PD_*`. `selector.unmanned_combat_units` note: carrier-launched drones are unmanned, but their replacement cost/time are data in `carrier_profiles` (bible: unspecified).

### 7.8 Seed archetype catalogue (SEED; illustrative HP scale: infantry 200, light vehicle 450, medium tank 850, heavy 1600; retuned by balance). `dps = burst*dmg*20 / ((burst-1)*bi + reload)` at 100 % matrix.

| Archetype (units) | Kind / type | Dmg | Burst x interval | Reload (ticks) | Range (min) cells | dps |
|---|---|---|---|---|---|---|
| inf_rifle (all general infantry) | hitscan bullet | 5 | 3 x 3 | 15 | 5.5 | 14.3 |
| inf_hmg (Fortress Guard deployed mode, Watchtower; suppressive) | hitscan bullet | 6 | 4 x 2 | 10 | 6.5 | 30.0 |
| inf_at_guided (Javelin 7.5 / Spike 9.5 / Needle / Lance long reload / Pike / Harpoon / Kavach) | missile explosive | 95-105 | 1 | 70-90 | 7.5-9.5 | 23-27 |
| inf_at_unguided (Recoil) | bullet-rocket explosive, splash 0.8 | 80 | 1 | 60 | 5.0 | 26.7 |
| apc_mg (APC/scout, weaker on amphibious variants) | hitscan bullet | 4 | 3 x 2 | 14 | 5.0 | 13.3 |
| tank_cannon_med (all T1/T2 tanks) | bullet explosive, splash 1.0 | 60 | 1 | 30 | 8.0 | 40.0 |
| tank_cannon_twin (Bastion) | bullet explosive | 70 | 2 x 4 | 44 | 9.0 | 58.3 |
| rail_cannon / rail_siege (Rhino, Imperial Guard / Argent, Charlemagne) | hitscan rail | 130 / 260 | 1 | 60 / 110 | 11 / 14 | 43 / 47 |
| howitzer_155 (Paladin, Archer, Breaker, Forge, Monsoon, Ibex) | arc explosive, splash 2.0 | 110 | 1 | 80 | 18 (5) | 27.5 |
| mortar_light (Sandglass) / rocket_barrage (Anvil, inaccurate) | arc explosive | 60 / 24 | 1 / 8 x 3 | 60 / 150 | 11 (3) / 15 (4) | 20 / 22.5 |
| missile_artillery (Saker, Shaheen, Fjord: precise, splash 0.8) | arc guided explosive | 190 | 1 | 130 | 16 (5) | 29.2 |
| aa_missile (Sentinel, Rapier, Crescent, Storm, Weaver, Vajra) / flak_dual (Porcupine) | missile / airburst bullet | 45 / 7 | 2 x 4 / 4 x 2 | 30 / 10 | 12 / 9 | 52.9 / 35 |
| fighter_aam / gunship_rockets | missile / bullet-rocket | 70 / 42 | 1 / 4 x 3 | 20 / 50 | 14 / 8 | 70 / 56.9 |
| bomber_area (Burya) / bomber_heavy (Condor) / bomber_precise (Silkwing) / strike_missiles (Nightjar) | bomb / bomb / bomb / missile | 140 / 850 / 300 / 100 | 6 x 3 / 1 / 2 x 6 / 4 x 3 | ammo 2 / 1 / 1 / 1 salvos | 0 / 0 / 0 / 10 | per sortie 1680 / 850 / 600 / 400 |
| ship_gun_light / ship_asw_depth_charge / ship_siege_missile / sub_missile | bullet / bomb (underwater) / arc guided / arc guided | 9 / 150 / 240 / 260 | 3 x 3 / 1 / 1 / 1 | 12 / 60 / 110 / 100 | 7 / 7 / 22 (6) / 20 (4) | 30 / 50 / 43.6 / 52 |
| at_turret, bulwark_cannon, lance_rail, forge_cannon (structures) | bullet / bullet / hitscan rail / bullet | 65 / 220 / 520 / 40 | 1 | 30 / 70 / 150 / 12 | 9 / 14 / 18 / 10 | 43 / 63 / 69 / 67 |
| citadel_mortar, dragon_tooth, bastion_missile_tower, sea_spear | arc / missile burst / missile burst / missile | 130 / 90 / 200 / 180 | 1 / 3 x 4 / 2 x 6 / 1 | 90 / 120 / 160 / 140 | 17 (6) / 12 / 13 / 16 | 29 / 42 / 48 / 26 |
| sunlance / sunwall / ifrit (deployed) / dawn laser (beams) | beam thermal / thermal / thermal / laser | 8 / 16 / 18 / 6 per dot | dot 4 / 4 / 4 / 2 ticks | cooling 60 / 80 / 60 / 40 | 9 / 12 / 11 / 10 | 40 / 80 / 90 / 60 at full ramp |
| tempest_drone (summon), dragonfall_engine (summon) | hitscan bullet packet / arc packet | 14 / 260 | 3 x 3 / 1 | 20 / 60 | 4 / 9 | 32 / 87 |

### 7.9 Special-case units -> mechanism (so authors and implementers agree)

| Bible unit / structure | Mechanism |
|---|---|
| Javelin, Spike, Kavach, Harpoon, Needle | `fire_on_move 0`, `settle_s 0.3`; Harpoon mask `ground+surface+structure` |
| Paladin, Archer, Breaker, Monsoon, Ibex, Shaheen, Saker, Sandglass | `requires deployed` (deploy time in the ability def: 3/4/3/3/2/3/1/1.5 s); `range_min` |
| Charlemagne, Gaj | optional deploy: `RANGE +2500 / +2000` lease while `ext_deployed` (abilities) |
| Ifrit | two mounts: mobile weak beam (`requires deployed: false`) and deployed heavy anti-structure beam (`requires deployed`) |
| Fortress Guard | bible rule: *all* its fire is suppressive; undeployed mount = rifle with a suppressive warhead, deployed mount (`requires deployed`) = `wh.hmg_suppress` at a higher fire rate |
| Shinano, Protea, Shogun | `requires mode`, `DefCombat.auto_mode = 1`; Raptor `auto_mode 0` (loads changed at an Airfield) |
| Sunlance, Dawn, Sunwall | continuous beams (§5.3); Sunlance and Ifrit `fire_on_move 0` ("vulnerable during sustained firing", "must remain stationary") |
| Ural, Arjun, Bear, Gaj | `aps` block; research changes count/cooldown through `PD_*` |
| Gate Guard, Marte, Ibex, Bear | `dir_armor` rows; Vanguard/shelter/cover are leases |
| Kiln | short range 5, broad splash 2.5, high structure matrix; Colossus/Elephant/Bulwark: `turn_rate` 6..10 |
| Titan, Osprey, Hammerhead, Sarus | `AS_HOVER`; Nightjar `AS_MISSILE_RUN`; Burya, Condor, Silkwing `AS_BOMB_RUN`; fighters `AS_DOGFIGHT`; Aster: no mounts |
| Boreal | `requires layer surface`; `want_surface` |
| Tempest, Shogun, Emperor | `carrier_profiles`; drones are aircraft defs |
| Leviathan | siege cannon + `garrison_fire 0` (passengers never fire) |
| Unarmed per bible | Combat Medic, Mirage Observer, Reef Technician, Link Operator, Mekong Field Engineer, Aster, Engineer, Collector, MCV, Landing Transport: `mounts: []`. All other `combat`-tagged units get at least a sidearm (Signal Officer, Echo Team, Watchpost, Alpine Pioneer, Lotus Tender: weak); balance to confirm |
| Aurora, Atlas, Perun, Horizon, Helios, Tempest drones, Dragonfall engines | warheads in §7.3; `PK_STRIKE`/`PK_SWEEP`/summon weapons with `packet` per §5.7 |

### 7.10 Compiler validation (load fails with a message naming the id)

Every referenced id exists; every mount weapon exists; `burst >= 1`; `range_min < range_max`; `splash_inner <= splash_r`; `splash_min_r < splash_r`; `edge_pct <= 100`; packet warheads have `delivery strategic`; `dtype emp` has `nonlethal`; `PK_ARC` has `speed > 0` and `min_flight <= max_flight`; `PK_SWEEP` obeys `(L/duration)*dot <= spot_len`; hitscan/beam weapons have no `speed`; `ammo_max > 0` for every `air_profile` mount; `req_layer` only on submarines; every `combat`-tagged unit has a loadout entry or is in the explicit unarmed list; all damage types/armor classes exist in TAXONOMY; resistance rows `bp <= 5000` and vulnerability rows `bp >= -5000`; converted values fit int32; carrier `wings` reference aircraft-layer defs.

---
## 8. Determinism notes (DR-x compliance; what enters the checksum)

| Rule | Compliance |
|---|---|
| DR-1 ints only | All sim fields are `int`/packed int arrays. Percentages are bp; damage is Q8 inside `compute` only. JSON floats exist only in `DefCombatCompiler` (§7.1, exact integer formulas). |
| DR-2 RNG | Only `world.rng.next_int`. **Draw sites, in order of occurrence:** P4 per shooter in ascending id then mount index: hitscan hit roll (1 draw; +1 on miss), bullet spread (1 draw iff `spread > 0`), arc scatter (2 draws iff scatter radius > 0). `spawn_remote` scatter draws happen inside the caller's (power system's) deterministic call. No draws in scoring, orders, upkeep, air, carriers, splash or flush. |
| DR-3 time | Only `world.tick`. No `delta`, no wall clock. |
| DR-4 trig | `Fp.atan2/sin/cos/isqrt/dist` only. |
| DR-5 division | `mul()` and `ceil_div` are used on non-negative operands only. Signed divisions (lead `trunc(v*t*lead/10000)`, arc interpolation `(end-start)*k/flight`, `crash_v*15/16`, scoring `(m-10000)*2048/10000`) rely on GDScript truncation toward zero and are annotated `@warning_ignore("integer_division")`. `>> 16` on signed values (muzzle offsets, Q16 products) is an arithmetic shift on every target platform; prefer `Fp.mul_q16` if core provides it. Every divisor is a constant or guarded `> 0`. |
| DR-6 iteration order | `armed_ids`, `status_ids`, `air_ids`, `wreck_ids`: ascending id arrays. Pool slots: ascending index; free slots reused LIFO. Spatial results are consumed with explicit `id` tie-breaks or sorted ascending (`PackedInt32Array.sort()`). Lease slots: fixed index order. No `Dictionary` in combat state. |
| DR-7 sorting | No `sort_custom`; maxima are found by loops with the tie-break `score > best or (score == best and id < best_id)`. |
| DR-8 no engine | No nodes, signals, await, timers. |
| DR-9 no global state | Scratch buffers live on `SimCombatSystem`; helper classes are stateless statics. Two worlds side by side share nothing. |
| DR-10 data | Compiled ints of all five combat JSON files enter the data hash; lobby mismatch blocks the match. |
| DR-11 bounded work | `SCAN_BUDGET`, `SCAN_CAND_CAP`, urgent budget 16, assist cap 12, `CHAIN_CAP 64`, `MAX_MODS 10`, `PROJ_POOL 4096`; none depend on time or platform. |
| DR-12 events | Output-only. Combat never reads `world.events`. The view reads `world.projectiles` and `mnt[]` but never writes. |
| DR-13 checksum | see below. |
| DR-14 AI/UI | AI and UI use the read API (§3.7) and submit commands (§6.1) only. |
| DR-15 interpolation | `px,py` and turret `M_ANGLE` interpolation is view-side. |

**Checksum contents** (`SimCombatSystem.hash_into(cs)`, called after entity states, entities in ascending id): for every entity `SimCompCombat`: `cflags, stance, hold_pos, target_id, target_src, target_since, seen_x/y/tick, ground_on/x/y, anchor_on/x/y, scan_next, focus_mask, focus_tick, inflight_est, last_attacker_id/pid, last_assist_tick, still_ticks, mnt[] (all n_mounts*MS ints), last_fire/hit/dealt_tick, emp_until, wlock_until, sup_left_q8, sup_t0..t2, sup_i, mods[] (all slots), aps_next[], want_deploy/mode/surface, ext_moving/deployed/mode, wreck_*, dying_until, death_kind, crash_vx/vy`; `SimCompAir` and `SimCompCarrier`: every field and array. Globals: `scan_cursor`; projectile pool: `next_serial`, `live`, free-stack contents in order, and every field of every live slot; pending chain queue; assertion that the damage queue is empty at hash time. `hp/hp_max` belong to the entity hash (sim_core). **Not hashed (derived or output-only):** `agg_*`, `mods_dirty`, `mods_next_expiry` (recomputed lazily and identically), `taken_cache`, `hit_*` coalescing scratch, `alert_tick`/alert location (event throttle), player stats, `_cand`/`_victims` scratch, and the derived id arrays `armed_ids`, `status_ids`, `air_ids`, `carrier_ids`, `wreck_ids` (D-4 asserts they equal a recomputation from entity state). Any new persistent combat field must be added to `hash_into` in the same change (DR-13).

Numeric safety: stored values fit int32 (coordinates <= 2.7e5, ticks < 2^31); intermediate products run in 64-bit GDScript ints (largest: `Q8 damage 1.3e6 * 40000 = 5e10`; `sx*tn <= 2048*4.2e6 = 8.6e9`; squares <= 2^40).

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

Cost model: one typed-GDScript statement ~ 0.1 us on a 2019 laptop (to be measured by CB-12; all counts below are statements). Reference scenarios: **typical** = 500 armed, 200 engaged, 150 live projectiles, 40 damage instances/tick; **stress S** = 8 players, ~1,150 units + ~300 structures, 900 armed, 450 engaged, 400 projectiles, 120 instances/tick.

| Phase | Reasoning | Typical | Stress S |
|---|---|---|---|
| P1 upkeep | ~100 timed entities x 12 | 0.5k | 1.5k |
| P2 air/carrier | 60 aircraft x ~70 (attack states every tick, others every 4th) | 1.5k | 5k |
| P3 scans | 24-40 scans x (query + ~25 prefiltered candidates x ~25 + scoring of ~8 x 40); rescoring every 20 ticks and urgent scans included | 14k | 36k |
| P4 weapons | idle armed x 4 + engaged x ~55 (validate, distance, aim, gates, salvo) | 13k | 28k |
| P5 projectiles | live x ~35 (move, swept test) + detonations x ~600 (query + ~8 victims x compute ~90) | 6k | 19k |
| P6 flush | instances x ~120 + coalesced events | 5k | 16k |
| **Total** | | **~40k = ~4 ms** | **~105k = ~10 ms** |

Budget: combat <= 12 ms/tick at stress S on the reference machine (of the 50 ms tick; the whole sim must stay < 35 ms), <= 5 ms typical.

**Worst cases and mitigations.** (1) *Mass artillery volley* — 240 shells landing within 3 ticks ~ 190k statements over 3 ticks (~6 ms/tick spike). Mitigation: burst intervals and flight-time variance spread impacts; per-victim per-tick `taken` cache (first hit ~90 statements, repeats ~35); splash candidate query capped by `splash_r + 2560`. (2) *Focus fire on one target* — the pipeline cache and `EV_HIT` coalescing cap the per-victim cost. (3) *Dense crowd scans* — prefilter before scoring, `SCAN_CAND_CAP`, stagger by `id % interval`, rescoring only every 20 ticks, budgeted rotation. (4) *Trident/APS checks* — only when a zone is active (`zones.active_intercept_count > 0`) or the projectile's target has `PD_APS_COUNT > 0`. (5) *Lease traffic* — aura owners refresh every <= 4 ticks with lease `N + 2` and a no-op fast path; an entity's aggregate is recomputed only when `mods_dirty` or `tick >= mods_next_expiry`. (6) *Air* — non-attack states run every 4th tick staggered by id. (7) *Projectile explosion* — hard pool cap 4096 with instant-resolution fallback (§5.4.9).

**Allocation discipline.** No per-shot or per-hit allocations: projectiles are SoA slots, damage instances are packed ints, scratch arrays are reused, events are appended to the world's event buffer (request: packed ring, §13-4). No `Dictionary`, no closures, no `Array.append` of objects in hot paths. **Memory:** pool 4096 x ~36 ints ~ 590 KB; components ~1,500 x ~90 ints ~ 540 KB. **Instrumentation:** `world.combat.counters` (scans, shots, impacts, live projectiles, instances) are deterministic counts asserted in regression tests; wall time is measured only by the external perf harness (DR-3).

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

Fixtures (`tests/fixtures/combat_fixture.gd`): `CombatFixture.make_world(seed, n_players)` builds a 64x64 world from an injected mini data set (`GameData.for_test`): 7 damage types, armor classes {infantry, light, medium, heavy, aircraft, ship, structure}, a **fixture matrix** (values set per test, not balance), hand-written warheads/weapons/loadouts, a mock `SimMovement`, mock `SimVision` (everything visible unless a test hides it), fake `SimZoneSystem`, `SimPower`, `SimEconomy`, `SimTransport`. Each test file is a `RefCounted` with `run(t: TestCtx)`.

**Unit tests** (expected values come from the executable reference vectors at the end of this section, `tools/py/combat_refvec.py`):

| ID | Case | Expected |
|---|---|---|
| U-PIPE-1..4 | Examples A, B, C, D of §5.6 | 14; 700 (1050 without Trident); 3; 50 |
| U-PIPE-5 | chip floor: base 5, matrix 500 / 400 / 0 | 1 / 0 / 0 (immune, no status) |
| U-PIPE-6 | rear vulnerability `-2000` on base 100, matrix 100 % | 120 (not capped) |
| U-PIPE-7 | resist sum 8000 in layer 3 | `taken 5000` (cap), damage halves |
| U-PIPE-8 | falloff: inner 512, outer 2048, edge 2500, `d_eff` 1280, base 110 | `f = 6250`, damage 69 |
| U-PIPE-9 | Counterbattery mark `+1500` plus Relay `+1000`: base 100, matrix 100 % | 125 (same layer, additive); with `atk_ground = 0` -> 110 |
| U-GEOM-1 | wrap_signed(2048), (4095), (-1), (0) | -2048, -1, -1, 0 |
| U-GEOM-2 | slew: `turn_rate 8`, error 1024, `aim_tol 24` | `cur == goal` at tick 128 (not 127); `aimed` from tick 125 |
| U-GEOM-3 | swept bullet vector of §5.4.8 | hit on tick 5 at (9216, 0) |
| U-GEOM-4 | arc: 12288 u at 512 u/tick, clamps 10..80; scatter 128..1536 over range 14336 | flight 24; scatter radius 1334; `u = 32768` -> r 943 |
| U-REL-1 | reload: base 80, Canada +15 %; + temp -10 %; base 20, Japan, temp -40 % / -70 % | 92; 83; 11; 10 |
| U-SUP-1..4 | hits at 0,15,30; 0,30,60; 0,10,20 with `SUP_RECOVER +5000`; immune lease | begins 30 ends 90; never; begins 20 ends 60; never |
| U-EMP-1..5 | Aurora on tank / aircraft / structure / infantry; recover 2500; immune | tank weapons off 160 ticks, hp >= 1; aircraft off 160 and still airborne, not dying; structure `is_functional` false 360 ticks; infantry unaffected; unmanned 120 ticks; immune -> `EV_EMP` blocked |
| U-INT-1 | Ural (count 1, cooldown 240): missile A reaches the interception radius at tick t, B at t+10, an artillery shell at t+20, missile C at t+240 | A removed (ready again at t+240), B hits, shell hits, C removed |
| U-INT-2 | 24-charge zone: 5 shells, 3 packets; a shell launched from inside; a bullet | shells destroyed (19 left); packets 1,2 halved (3 left), 3 full; inside-launch and bullet bypass |
| U-TGT-1 | scoring: tank (prio 8) vs infantry (6) for an AT weapon (matrix 200 % vs tank) | tank; tie on equal score -> lowest id |
| U-TGT-2 | stickiness / overkill: current target hp 10 with 15 in flight | switches to next; `HOLD_FIRE` never auto-fires but fires on `ORD_ATTACK` |
| U-TGT-3 | filters: AA mount vs parked aircraft; ground gun vs air; ASW vs dived sub; strategic warhead vs submerged | not engaged; not engaged; engaged only by ASW; damaged |
| U-TGT-4 | retaliation and assist (8-cell radius, cooldown 20) | attacked idle unit targets attacker; 3 idle allies join; second event within 20 ticks does not re-assist |
| U-DEATH-1 | wreck matrix: enemy kill of land combat vehicle (paid 900); friendly kill; scuttle; summoned; decoy; aircraft; salvage enabled off | wreck value 900 / none / none / none / none / none / none |
| U-DEATH-2 | wreck lifecycle | expires at `t+1200`; splash destroys it (`EV_WRECK_REMOVE 1`); `try_salvage(pct 20)` pays 180 once, second call -1; allied salvager -1 |
| U-DEATH-3 | occupants: transport (die), Beaver-class (hurt 3000, min 1 hp), garrison (hurt 2500) | as specified, `EV_EJECT` count |
| U-DEATH-4 | aircraft crash: crash_ticks 30, velocity (600,0) | moves with 15/16 decay, impact strike at tick +30, friendlies underneath hurt |
| U-AIR-1 | sortie: PARKED -> TAKEOFF -> TRANSIT -> ATTACK -> RETURN -> LANDING -> REARM -> PARKED with a powered pad | `rearm 240` ticks exactly; unpowered/EMP airfield: no progress |
| U-AIR-2 | Rapid Turnaround `+5000` | ammo units at 27,54,80,107,134,160 |
| U-AIR-3 | bomb run: V 614, fall 16, 6 bombs interval 3 | release when `along <= S/2 + |V|/2` (S 9210); impact stick centred within 307 u |
| U-AIR-4 | fuel: forced return at reserve; no airfield | RETURN; `AIR_NO_BASE`, no fuel penalty |
| U-CAR-1 | Tempest: launch batch 2 / 20 ticks, recall on target loss, dock rearm, loss -> replacement stalls at 0 credits, completes 25 s after paid | as specified; carrier death -> drones die 60 ticks later |
| U-ORD-1..5 | attack chase/turn/fire (mock movement); attack-move engage-and-resume; guard leash 6144 + return; hold no chase; force-fire ground with friendly in splash | as §5.10.6 |


**Reference vectors** (executable oracle for U-PIPE, U-GEOM-4, U-REL-1; the implementation task copies this to `tools/py/combat_refvec.py`):

```python
import math
def mul(x, bp): return (x * bp + 5000) // 10000
def ceil_div(a, b): return (a + b - 1) // b
def pipeline(base, m, static_bp, tmp_bp, mark_bp, falloff_bp, L, pkt=0):
    """L = resistance sums (bp) of layers 0..3; pkt (Trident packet) joins layer 3."""
    if m == 0: return 0
    x = mul(mul(mul(mul(base << 8, m), static_bp), max(0, min(40000, 10000 + tmp_bp + mark_bp))), falloff_bp)
    L = list(L); L[3] += pkt
    taken = 10000
    for k in range(4): taken = mul(taken, max(0, min(20000, 10000 - L[k])))
    taken = max(5000, min(20000, taken))
    x = mul(x, taken); d = (x + 128) >> 8
    return 1 if d < 1 and m >= 500 and x > 0 else d
def falloff(d, inner, outer, edge):
    return 10000 if d <= inner else edge if d >= outer else 10000 - (10000 - edge) * (d - inner) // (outer - inner)
def reload_eff(pm_reload, base, agg_bp): return max(ceil_div(pm_reload * max(0, 10000 + agg_bp), 10000), ceil_div(base, 2))

assert pipeline(12, 12000, 11500, 2000, 0, 10000, [0, 0, 0, 3000]) == 14                 # U-PIPE-1
assert pipeline(1400, 10000, 10000, 0, 0, 10000, [0, 0, 0, 2500], pkt=5000) == 700       # U-PIPE-2
assert pipeline(1400, 10000, 10000, 0, 0, 10000, [0, 0, 0, 2500]) == 1050
assert pipeline(5, 10000, 10000, 0, 0, 10000, [2500, 0, 0, 1500]) == 3                   # U-PIPE-3
assert pipeline(60, 10000, 10000, 2000, 0, 10000, [0, 0, 0, 3000]) == 50                 # U-PIPE-4
assert [pipeline(5, m, 10000, 0, 0, 10000, [0] * 4) for m in (500, 400, 0)] == [1, 0, 0] # U-PIPE-5
assert pipeline(100, 10000, 10000, 0, 0, 10000, [-2000, 0, 0, 0]) == 120                 # U-PIPE-6
assert pipeline(100, 10000, 10000, 0, 0, 10000, [0, 0, 0, 8000]) == 50                   # U-PIPE-7
assert falloff(1280, 512, 2048, 2500) == 6250
assert pipeline(110, 10000, 10000, 0, 0, falloff(1280, 512, 2048, 2500), [0] * 4) == 69  # U-PIPE-8
assert pipeline(100, 10000, 10000, 1000, 1500, 10000, [0] * 4) == 125                    # U-PIPE-9
assert pipeline(100, 10000, 10000, 1000, 0, 10000, [0] * 4) == 110
assert ceil_div(12288, 512) == 24                                                         # U-GEOM-4
sc = 128 + (1536 - 128) * 12288 // 14336
assert sc == 1334 and (sc * math.isqrt(32768 << 16)) >> 16 == 943
assert [reload_eff(92, 80, 0), reload_eff(92, 80, -1000), reload_eff(18, 20, -4000), reload_eff(18, 20, -7000)] == [92, 83, 11, 10]  # U-REL-1
print("all reference vectors pass")
```

**Scenario tests** (headless `SimWorld`, hitscan and projectile data from §7): S-1 *Guardian mirror*: 880 hp vs 60-damage shells, reload 30: 15 hits are needed; first shot tick `t0`, the 15th shot at `t0 + 14*30`, death at that tick plus flight (+- 3 ticks); with identical stats and start ticks both tanks die in the **same tick** (simultaneous resolution, §5.6.2). S-2 *Howitzer vs stationary/moving*: stationary target takes full damage from every shell that lands within `splash_inner`; a target moving 120 u/tick against `lead_bp 0` with flight 24 ticks is missed by `120*24 = 2880 u > splash_r 2048` (no damage), while `lead_bp 10000` hits it. S-3 *AA vs bomber pass*: 500-hp `AS_BOMB_RUN` bomber at 12 cells/s against 1, 2, 4, 8 Sentinels (`aa_missile`, range 12): damage taken is monotonic in the AA count, identical across double runs; with 8 the bomber dies before its release point (first salvo 8x2x45 = 720), with 1 it releases and the stick lands. S-4 *Ural column*: 3 Javelin volleys, only the first per 240 ticks is intercepted. S-5 *Trident push*: shells vs zone, then beams. S-6 *Helios*: 16-cell line, stationary unit takes ~9 dots, unit walking off takes <= 2. S-7 *Aurora*: EMP disables 8 vehicles for 160 ticks, aircraft keep flying, infantry unaffected, allies also unaffected (`friendly_fire 0`). S-8 *Stress S* build (8 players AI-free scripted armies) for perf and determinism.

**Determinism tests.** D-1 run S-8 twice in one process (two worlds side by side): identical checksum every 20 ticks for 3,000 ticks. D-2 macOS vs Linux container golden chain of S-1..S-8 (`tools/gd linux`). D-3 seeded random command fuzz (10 seeds x 3,000 ticks, combat-heavy composition, all orders and stances) — no error, identical double runs. D-4 checksum sensitivity: mutate each `hash_into` field in turn and confirm the hash changes (guards DR-13).

**Visual tests** (`gd shot`, images inspected with the image reader): V-1 muzzle flashes and tracers for rifle/tank/autocannon (verify `EV_FIRE` fields); V-2 artillery arcs, impacts and falloff ring; V-3 continuous beam and Helios sweep; V-4 homing missiles, APS intercept flash, Trident boundary flash; V-5 death set at ticks +0/+10/+30 (vehicle wreck, infantry, aircraft crash, structure chain blast); V-6 debug overlay `tests/visual/combat_event_probe.gd` that draws every event with its fields to prove the contract of §6.

**Performance test.** P-1 stress scenario S-8 with counters asserted (deterministic) and wall time reported per phase; fails softly above 12 ms mean on the reference machine.

---
## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

Suggested order: CB-00 -> CB-01 -> CB-02 -> {CB-03, CB-05} -> CB-04 -> CB-06 -> CB-07 -> CB-08 -> CB-09 -> CB-12; data authoring CB-10/CB-11 starts after CB-00 in parallel. Every task ends with `tools/gd check` clean and its tests green; tasks that touch determinism add a double-run hash test.

| Id | Task | Files owned | Depends on | LOC | Acceptance |
|---|---|---|---|---|---|
| CB-00 | Constants, compiled defs, compiler, validator, JSON schema + minimal sample data (>= 12 entries covering every profile kind) | `sim/combat/sim_combat_consts.gd`, `data/def_warhead.gd`, `def_projectile.gd`, `def_weapon.gd`, `def_mount.gd`, `def_combat.gd`, `def_death.gd`, `def_air.gd`, `def_carrier.gd`, `def_combat_compiler.gd`, the five `combat_*.json`, `tests/test_combat_data.gd` | data domain (`GameData` registry), balance TAXONOMY ids | ~2,200 | §7.1 conversion vectors, §7.10 negative cases, data-hash stability across two loads |
| CB-01 | Components, system skeleton, lease slots, lifecycle hooks, read API, checksum | `sim_comp_combat.gd`, `sim_comp_air.gd`, `sim_comp_carrier.gd`, `sim_combat_system.gd`, `sim_combat_mods.gd`, `tests/test_combat_mods.gd` | CB-00; sim_core entity/world API | ~1,300 | lease dedupe/eviction/expiry vectors; spawn/remove/owner-change; D-4 checksum sensitivity for owned fields |
| CB-02 | Damage pipeline, queue, flush, EMP, suppression, alerts, coalesced hits | `sim_damage.gd`, `tests/test_combat_pipeline.gd`, `test_combat_status.gd` | CB-01 | ~1,300 | U-PIPE-1..9, U-SUP, U-EMP |
| CB-03 | Mount aim/slew, gates, salvo/reload/ammo, hitscan, beams, muzzle geometry | `sim_weapons.gd`, `tests/test_combat_weapons.gd` | CB-01, CB-02 | ~1,500 | U-GEOM-1,2, U-REL-1, beam ramp/cooling vectors, S-1 with hitscan |
| CB-04 | Projectile pool and kinds, swept test, detonation/splash, interception hooks, pool cap, view snapshot | `sim_projectiles.gd`, `tests/test_combat_projectiles.gd` | CB-02, CB-03; zone-system interface (fake in tests) | ~1,800 | U-GEOM-3,4, U-PIPE-8, U-INT-1,2, S-2, S-4, S-5, S-6, pool-cap fallback |
| CB-05 | Targeting: filters, scoring, scan scheduling, stances, retarget, retaliation, assist, overkill guard | `sim_targeting.gd`, `tests/test_combat_targeting.gd` | CB-01, CB-03; vision interface (mock) | ~1,400 | U-TGT-1..4; budget/starvation test (scan rotation reaches every entity within `ceil(n/budget)` ticks) |
| CB-06 | Combat commands and order handlers, idle engagement | `sim_order_combat.gd`, `tests/test_combat_orders.gd` | CB-05; orders `SimOrder`; movement API (mock) | ~1,300 | U-ORD-1..5, command validation cases |
| CB-07 | Death: kill sequence, occupants, wrecks/salvage API, chain effects, crash, cleanup pass | `sim_death.gd`, `tests/test_combat_death.gd` | CB-02, CB-04; transport interface (mock) | ~1,300 | U-DEATH-1..4, chain cap, S-7 |
| CB-08 | Aircraft sortie machine, pads, rearm, patrol, attack styles | `sim_air_sortie.gd`, `tests/test_combat_air.gd` | CB-03, CB-04, CB-07; movement air API (mock); power API | ~2,000 | U-AIR-1..4, S-3 |
| CB-09 | Carrier ops: launch, recall, dock, replace, wing switch, orphan | `sim_carrier_ops.gd`, `tests/test_combat_carrier.gd` | CB-08; economy API (mock) | ~1,000 | U-CAR-1 |
| CB-10 | Combat data authoring A: NAPC, NEC, OLM, DEF rosters (all 4 x 13 baseline + unique units), shared structures, advanced defences, superweapon warheads, summons | `combat_weapons.json`, `combat_loadouts.json`, `combat_warheads.json`, `combat_projectiles.json` (sections for these factions; merge-friendly key namespaces) | CB-00; balance HP/cost tables | data | validator passes; every `combat`-tagged unit has a loadout or is on the unarmed list; DPS lint report within +-25 % of the balance curve; special-case table §7.9 honoured |
| CB-11 | Combat data authoring B: PD, HAN, AE, SAP rosters | same files, other key namespaces | CB-00, CB-10 conventions | data | same as CB-10 |
| CB-12 | Integration tests: scenarios S-1..S-8, determinism D-1..D-4, perf harness P-1, visual scenes V-1..V-6 and event probe | `tests/test_combat_scenarios.gd`, `test_combat_determinism.gd`, `test_combat_perf.gd`, `tests/fixtures/combat_fixture.gd`, `tests/visual/combat_*.gd` | CB-01..CB-09 | ~1,800 | all listed tests green on macOS and in the Linux container; screenshots reviewed |

---

## 12. Risks, open questions and your recommended resolution for each

| # | Risk / open question | Recommended resolution |
|---|---|---|
| 1 | TAXONOMY may renumber damage types / armor classes | Freeze ids 0..6 as in §4.1 (Appendix A seeds), append only; TAXONOMY supplies `dt_cover_mask` (beam family covers thermal). Combat compiles against names and asserts ids at load |
| 2 | Where `hp` lives | `SimEntity.hp/hp_max`, written only by `SimCombatSystem` (`heal`, `kill`, flush, `rescale_hp`); if sim_core splits it into a component, only these four call sites change |
| 3 | Abilities may already own a buff/effect store | Keep their store, but it must *project* into `SimCombatMods` leases every <= 4 ticks; combat reads no other buff store |
| 4 | "Combined resistance <= 50 %" vs the armor matrix | Interpreted as bible modifiers only; the type x armor matrix is base effectiveness (otherwise armor classes could not exist). Balance to confirm; the alternative is to clamp matrix rows at 50 %, which erases armor identity |
| 5 | Resistance stacking rule | Sum inside a layer, multiply across layers (the bible's own rule), then cap at 50 %. Simpler "sum everything" differs by < 3 points in every bible case |
| 6 | Does Aurora affect ships? Bible says "vehicles and aircraft" | Ships count as vehicles (`EC_SHIP` in the Aurora mask); one-line change if design says otherwise |
| 7 | Aircraft with no airfield / fuel exhaustion (bible silent) | No fuel penalty: `AIR_NO_BASE` orbits at zero fuel cost with remaining ammo; alternative (crash at 0 fuel) makes airfield loss snowball |
| 8 | Should fighters scramble automatically? | No in v1 (parked aircraft never self-launch; AI issues patrol/attack orders). Add `auto_scramble` later without schema change |
| 9 | Pads repair aircraft? Bible: pads *rearm* only | No repair (do not invent); add `pad_repair_bp_per_s` (default 0) if design wants it |
| 10 | Carrier drone replacement cost/time (`selector.unmanned_combat_units` note: unspecified; README: null is not free) | Balance-designed `replace_cost`/`replace_s` in `carrier_profiles` (seed 120 credits, 25 s); Cambodia's unmanned cost bonus applies only if data says so |
| 11 | Cargo fate when a transport dies | `CARGO_DIE` default; Beaver/Naga/Okapi "reinforced passenger protection" -> `EJECT_HURT 3000`; garrisons `EJECT_HURT 2500`; design to confirm |
| 12 | Wreck entities cost entities/events | Created only when some player has the salvage trait (`world.rules.salvage_enabled`); other factions' wrecks are cosmetic in the view (EV_DEATH flag) |
| 13 | Direct fire has no body-blocking | `PF_BLOCKED_BY_HOSTILES` implemented but off; enable per projectile after playtest |
| 14 | Sim is 2D: no terrain line-of-fire | Accepted; cliffs/buildings do not block shots. If needed the map domain can expose `blocks_fire(x0,y0,x1,y1)` and P4 gains one check |
| 15 | Event allocation/volume | Request a packed-int event ring (stride 10) in sim_core; coalesced `EV_HIT`; capped cosmetic `EV_FIRE` |
| 16 | GDScript throughput | Budgets in §9; escalation ladder: lower `SCAN_BUDGET_BASE`, raise `RESCORE_INTERVAL`, add a coarse per-team enemy-presence grid to skip empty scans, resolve infantry bursts as one aggregated roll per squad |
| 17 | OrderSystem interface is another domain's | Propose a dispatch table `kind -> SimOrderCombat.step`; if orders prefers owning the state machines, `sim_order_combat.gd` moves there unchanged |
| 18 | Helios semantics: moving hot spot vs whole line at once | Moving 3-cell spot over 12 s (bible: "traverses the line over 12 seconds", "leave the marked line"); parameters live in data |
| 19 | Packet reduction evaluated at impact centre, not per victim | Chosen for O(1) and determinism; a victim outside the zone but inside a centre-inside blast is also reduced (rare, favours the defender) |
| 20 | Do rockets (Recoil, Anvil) count as "ordinary missiles" for APS/Trident? | Data flags decide: guided missiles and missile artillery `aps`+`zone`; unguided rockets `zone` only; shells `zone`; bullets none |
| 21 | Several `combat` specialists have no stated weapon | Sidearm default (weak) except the explicit unarmed list (§7.9); balance to confirm |
| 22 | Selector resolutions `thermal_beam_weapons`, `ordinary_guided_missiles` | Resolved in §7.7; data architect to record them in its own spec |
| 23 | Armor class differs by state (deployed, garrisoned) | Not modelled; use directional rows and leases instead. Revisit if balance needs state-dependent armor |
| 24 | Do summoned attackers' *splash* hurt friendlies? Bible: "summoned attackers select enemies only"; assignment brief: "summons enemy-only" | Enemy-only damage (`PI_ENEMY_ONLY`), as it is the safer reading and avoids self-harm from temporary units; strategic impacts of the launching superweapons still follow the friendly-fire default. One-line change if design disagrees |
| 25 | ARCHITECTURE §6 lists EMP among AbilitySystem primitives | Boundary decision: the EMP *status* (`emp_until`, class table, recovery, immunity check) lives in combat because EMP arrives as warhead damage from the superweapon strike; abilities only push `STAT_FLAG_EMP_IMMUNE` / `STAT_EMP_RECOVER` leases and never keep a second EMP timer. Reconciler to record in `AMENDMENTS.md` |

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

**sim_core**
1. `SimEntity.kind` must include `KIND_WRECK = 2`; spatial hash, vision, unit cap, victory and selection treat it as neither unit nor structure. Provide `SimWorld.spawn_raw(kind, def_idx, owner, x, y, facing) -> SimEntity`.
2. `SimEntity` fields (ints): `id` (never reused), `def_idx`, `kind`, `owner`, `x, y, prev_x, prev_y` (prev = position at end of the previous tick), `vx, vy` (this tick's displacement, written by movement), `facing`, `layer` (combat/air may write it), `hp, hp_max` (combat is the only writer), `radius`, `container_id` (-1 none; entities with `container_id >= 0` are not in the spatial hash and are untargetable), `paid_cost`, `expire_tick`, `flags`, and component slots `combat`, `air`, `carrier`. `SimWorld.get_entity(id)`, `remove_deferred(id, at_tick)`, `spawn_unit(def_idx, owner, x, y, facing, flags)` with a `F_NO_UNIT_CAP` flag (drones, summons).
3. Reserve command codes 40..47 and order kinds 40..44 (§4.1, §6.1) and route them to `SimOrderCombat.apply_command` / `SimOrderCombat.step`.
4. Reserve event codes 200..229 and provide `SimWorld.emit(type, x, y, a, b, c, d, e, f)` with the `SimEvent{type, tick, x, y, a..f}` shape; strongly recommended: back it by a packed `PackedInt32Array` ring (stride 10) to avoid one object per event.
5. `SimWorld.rel(pid_a, pid_b) -> int` (`REL_SELF/ALLY/ENEMY/NEUTRAL`, O(1) table) and `team_of(pid)`.
6. `SimRng.next_int(n) -> int` uniform in `[0, n)`.
7. `SpatialHash.query_circle(x, y, r, out) -> int` with deterministic order, excluding contained/docked entities.
8. `Fp`: `atan2(y, x)`, `dist(dx, dy)`, `isqrt`, `sin`, `cos` (Q16); recommended `mul_q16`, `wrap_angle`, `angle_diff`.
9. Pipeline wiring: `SimCombatSystem.update` at step 8; `SimCleanupSystem` calls `combat.cleanup(world)` at step 11; `SimWorld.checksum` calls `combat.hash_into(cs)` after entities; `spawn/remove/owner-change` paths call `on_spawn/on_remove/on_owner_changed`.
10. `world.rules.salvage_enabled: bool` (true iff any player's roster has the salvage trait).
11. Per-player stats (`kills`, `losses`, `damage_dealt`, `damage_taken`) written by combat; a `rescale_hp` call from research/data when `hp_max` changes.
12. Cargo owner (transport/orders): `SimTransport.cargo_of(container) -> PackedInt32Array` and `SimTransport.eject_all(world, container) -> void` (placement around the wreck/footprint).
13. Every system that iterates entities must skip `SimCombatSystem.is_alive(e) == false` (power, production, vision, pathing, victory, selection).

**data**
14. `GameData` loads `combat_*.json` through `DefCombatCompiler` and exposes typed arrays `warheads`, `projectiles`, `weapons`, and `DefCombat` on every unit/structure def; the compiled ints join the data hash.
15. `GameData.dmg_matrix_bp` (`[dtype * n_armor + armor_class]`), each def's `armor_class`, and `dt_cover_mask` (beam family covers thermal).
16. Resolved tables `pmount`, `pdef`, `presist` (§4.6), rebuilt at research completion, using the layer rule and floors of the bible; record the selector resolutions of §7.7.
17. Def fields: `tags` bit mask of the bible role tags, `radius`, `layer`, `needs_power`, `emp_susceptible` (structures), `garrison_fire`, default `prio`.
18. Airfield def: `pad_count`, `pad_offsets`; `PD_PAD_COUNT` research bonus (Dispersed Runways).
19. **Carrier drone unit defs** (the bible has none): unmanned, aircraft-tagged, `F_NO_UNIT_CAP`, one per carrier wing (Tempest strike, Shogun strike, Shogun interceptor, Emperor strike), plus the wing filter weapons used by `carrier_profiles`.

**balance_framework**
20. TAXONOMY: freeze damage-type ids 0..6 (§4.1), name the armor classes, publish the matrix, `dt_cover_mask`, and an EMP row that keeps EMP damage light.
21. Numbers for every def (hp, speed, radius, vision, cost, build time) and retuning of the §7.8 seed archetypes to the DPS-per-cost curve; confirm the unarmed list of §7.9 and open items §12-4, 6, 9, 10, 11, 21.
22. Aircraft/carrier numbers: `fuel_s`, `rearm_s`, `takeoff/landing`, carrier `replace_s/replace_cost`, wing-switch time.

**movement**
23. Air primitives with these semantics: `air_fly_to`, `air_orbit`, `air_hover`, `air_face`, `air_takeoff`, `air_land_at`, `air_at_goal`; hover aircraft must be able to yaw in place.
24. Ground primitives `move_to`, `move_to_range(tx, ty, range)`, `stop`, `turn_to(facing)`; write `cc.ext_moving` and `e.vx/vy` every tick before step 8; multiply infantry speed by `SimCombatSystem.suppression_speed_bp(e)`; skip `CF_DEAD` entities (combat moves crashing aircraft itself); deployed/packing units pack automatically on a move order.

**orders**
25. Dispatch `ORD_ATTACK..ORD_FORCE_FIRE` to `SimOrderCombat.step`, call `step_idle` for armed entities with an empty queue, call `on_order_start` when any non-combat order begins, and define `SimOrder{kind, target_id, x, y, count, state, t0, tx, ty}`; `CMD_STOP` calls `clear_target`.

**abilities / zone / power**
26. Push leases with `SimCombatMods.apply` exactly per the catalogue of §5.14 (stat, bp, filter, duration); allocate `FXK_*` keys; refresh auras every <= 4 ticks with lease `N + 2`. Do not keep a second EMP timer: the EMP status is combat's (§12-25).
27. Write `cc.ext_deployed` / `cc.ext_mode` each tick before step 8; honour `cc.want_deploy`, `cc.want_mode`, `cc.want_surface` (and the Boreal 8 s surfaced window); read `last_fire_tick`, `last_hit_tick` for camouflage; read `is_suppressed` for command fields.
28. Zone system: implement `intercept_ordinary` and `intercept_packet` with the semantics of §5.7 (hostile only, launch-inside bypass, swept crossing, 1 charge per ordinary projectile, 8 charges per packet for `5000`).
29. Power/abilities: spawn strategic impacts with `SimProjectiles.spawn_remote` / `spawn_sweep` (`PI_REMOTE`), poll `SimCombatSystem.is_functional(launcher)` during warnings, mark summons `CF_SUMMONED` (and `CF_ENEMY_ONLY` for autonomous attackers), expire them with `kill(CAUSE_EXPIRE)`, spawn decoys with `CF_DECOY` and 1 hp.
30. `SimPower.is_powered(world, e)` and `defense_online(world, pid)` (SAP reserve).

**economy / production**
31. `SimEconomy.try_spend(pid, credits) -> bool`; set `SimEntity.paid_cost` at unit completion; the 8 s / 5 s salvage action calls `try_salvage(wreck_id, pid, 20)` on completion.
32. Production: call `SimAirSortie.on_aircraft_spawned(world, e, airfield_id)` after spawning aircraft; call `on_pads_changed` after pad research; treat `is_functional == false` (EMP) structures as shut down.

**vision**
33. `can_see(world, pid, e)`, `is_known(world, pid, e)`, `decoy_identified(world, pid, e)`; O(1); remove dead entities from vision immediately.

**view / audio / ui / ai / qa**
34. View/audio: implement the recipes of §6.3, mirror projectiles from `world.projectiles`, read `mnt[...M_ANGLE]`, keep dying corpses `visual_ticks` after `REMOVED`, own the `fx/sfx` id tables referenced by warheads/weapons/projectiles.
35. UI: use `can_attack` for cursors, `range_max_eff` for range rings, stance buttons -> `CMD_SET_STANCE`, `EV_ATTACK_ALERT` for alerts, `ammo_of`/`sortie_state` for aircraft cards.
36. AI: read-only queries `can_attack`, `dp100`, `range_max_eff`, `ticks_since_combat`; act only through the commands of §6.1.
37. QA: `TestCtx`, `GameData.for_test(dict)`, `tools/gd test combat`, `tools/gd linux` for golden chains, screenshot tooling for V-1..V-6.
