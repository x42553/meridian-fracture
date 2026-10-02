# MERIDIAN FRACTURE — Balance Framework (v1)

> **Domain:** balance framework, taxonomy and global tuning numbers.
> **Companions:** `docs/balance/TAXONOMY.md` (vocabulary, damage matrix, resistances, enums — frozen integer codes),
> `game/data/balance/global.json` (the numbers), `tools/py/balance_calc.py` (formulas, engagement model, validator, proposal generator).
> **Provenance of numbers:** every table below is produced by `python3 tools/py/balance_calc.py <command>` from `global.json`
> (`balance_calc.py report` regenerates all of them; `balance_calc.py validate` is the acceptance gate and currently prints `0 failure(s)`).
> If a table here and the JSON disagree, the JSON wins and this file is stale.
> **Status:** designed and *model-validated* (deterministic expected-value engagement model, 20 TPS). Real-engine confirmation is the job of the
> methodology in §5.17 / §10 / §11 (BAL-3). Section numbering follows the mandatory spec format.

---

## 1. Purpose & scope (what you own; what you explicitly do NOT own)

**Problem.** The bible fixes structure, service-unit, research, power and superweapon numbers, the layering/cap rules and all 98 typed modifiers, but leaves
**every combat statistic `null`** (health, armor, damage, range, speed, vision, radius, cost and build time of 152 combat units, all weapons, all defences).
Eight faction designers will fill those in concurrently. They must not diverge, so they need a shared physics: damage vocabulary, armor table, curves by tier and
role, budgets for defences/aircraft/ships/artillery/superweapons, an economy and pacing that make the bible's numbers meaningful, and a machine that says
"this unit is 12 % over-budget".

**I own**
1. The combat/movement vocabulary and frozen integer codes (`TAXONOMY.md`): 7 damage types, 11 armor classes, damage × armor matrix, size classes, movement classes, terrain kinds, weapon archetypes.
2. `game/data/balance/global.json`: matrix, size/movement tables, tier curves, 32 role archetypes with reference weapons, 27 weapon archetypes, structure HP/armor/footprint, defence weapons, economy, power, production rates, aircraft/naval/artillery/carrier rules, superweapon and support-power damage, pacing plans and windows, target bands, style tags, ability values, modifier-valuation and compensation tables, and the 156-row `unit_assignments` map (unit → archetype + tags + abilities).
3. Formulas: damage pipeline, integer resolution recipe for the bible's layer rule, fair-cost/power-index formula, build-time formula, TTK, sortie economics.
4. `tools/py/balance_calc.py` (proposal generator, integer resolver, engagement model, all validators) and the *specification* of the runtime classes `DefBalanceGlobal`, `DefWeaponArch`, `DefEconomyConsts`, `DefDamageMath`, `DefPercentMath` (implementation tasks in §11).
5. The validation methodology for real-engine balance passes (§5.17).

**I do NOT own**
* Final per-unit / per-structure numbers (8 faction designers; they start from `balance_calc.py proposals` and stay inside the tolerances of §5.4).
* The formal schema and loader of `game/data/balance/<faction>.json` and the modifier resolver (data_balance / data architects) — I supply the integer recipe (§5.1) and the constants.
* Any simulation system (combat, movement, economy, production, power, vision, zone, cleanup), the AI brain, netcode, UI, audio, maps.
* The bible. Bible-fixed numbers are asserted by `validate` and can never be edited here.

### 1.1 Where to find what (this file is long; the load-bearing parts are indexed here)

* **API and integer recipe:** §3 (GDScript signatures), §5.1 (bible layer rule as integers), §5.2 (the one damage formula). **Enums/matrix:** TAXONOMY.md.
* **Numbers for designers:** §5.3 (tier × role curves), §5.4 (fair-cost formula, tags, abilities, three worked examples), §4.4-4.6 (weapon/unit/ability templates), §7.4 (unit → archetype for all 156 units).
* **Budgets:** §5.5 cross-class, §5.6 TTK and equal-cost RPS, §5.7 structures/defences, §5.8 economy, §5.9 power, §5.10 pacing, §5.11 superweapons, §5.12 aircraft, §5.13 naval, §5.14 artillery vs vision, §5.15 passive-modifier compensation.
* **Process:** §5.17 real-engine methodology, §10 tests, §11 tasks (BAL-1…6). **What I need from others:** §13 (14 numbered requests; the critical ones: resolver uses `DefPercentMath`, combat uses `DefDamageMath.final_damage`, `SUPERWEAPON_FIRE` gets an `angle`, Refinery gets a Collector queue, map provides the §5.8 deposit layout).

### 1.2 What the bible fixes vs. what this framework designs

| Bible-fixed (asserted by `validate`; never overridden) | Designed here |
|---|---|
| Structure cost / build time / power: Generator 600/25 s/+150, Refinery 1800/40 s/−30, Barracks 500/20 s/−10, Factory 2000/40 s/−40, Dock 1800/40 s/−35, Radar 1500/30 s/−40, Airfield 1600/35 s/−40, Laboratory 2500/50 s/−60, Watchtower 450/15 s/−5, AT turret 800/20 s/−15, AA battery 900/20 s/−20, advanced defense 1800/35 s/−40, superweapon 5000/90 s/−200, Relay cost 600 | Structure HP, armor class, footprint, vision; Relay build time (15 s); HQ deploy time (3 s) |
| Service units: Engineer 500, Collector 1400, MCV 3000, Landing Transport 900 (carries 4 squads or 2 vehicles) | Their HP, speed, build times, collector capacity and harvest/unload rates |
| Start preset 7,500 credits + deployed HQ, no veterancy; build radius 8 cells; tier gates (Radar → T2, Radar + Laboratory → T3); research 45 s / 75 s | Every combat-unit stat and price, weapon numbers, ability parameters not quoted in prose |
| Superweapon recharge / warning / geometry / duration / charges (Atlas 480/10, Aurora 420/8, Helios 480/10, Perun 480/10, Tempest 480/10, Dragonfall 480/10, Horizon 480/10, Trident 360/6, 24 charges, 8 charges = −50 %) | Damage per impact packet, drone/engine stats, EMP damage, Helios DPS |
| Layering rule (add within a layer, multiply across layers) and floors/caps: cost ≥ 60 %, build time ≥ 60 %, reload ≥ 50 %, combined resistance ≤ 50 % | Integer recipe, rounding, damage pipeline, resistance stacking and matrix |
| Salvage 20 % of paid price / 8 s / wreck 60 s; Engineer repair 1 %/s for 0.5 % of price/s; suppression 3 hits / 2 s / −25 % / 3 s; detector radius 5 (Watchtower 4) | Economy rates, deposits, repair as credits-per-HP, sell refund (50 %), unit cap (150) |

### 1.3 One-screen cheat sheet (all values from `global.json`)

* **Anchor unit** `mbt_t1`: 850 credits, 27.5 s build, 900 HP, 140 `ap` per 1.2 s (117 DPS), range 7, speed 2.0 c/s, vision 9, radius 0.55. Everything else is scaled from it.
* **Infantry squad** `inf_line`: 250 / 9 s / 400 HP / 2×26 `bullet` per 1 s (52 DPS) / range 5.5. **AT team** `inf_at`: 350 / 12.5 s / 300 HP / one 270 `ap` missile per 4.5 s (60 DPS) / range 7.5.
* **Tier progression** (per-credit HP): tank 1.06 (T1) → 1.28 (T2) → 1.50 (T3); equal-cost T2 beats T1 by +0.28 remaining-cost share, T3 beats T1 by +0.28.
* **TTK anchors** (unopposed, matrix included): T1 tank vs T1 tank 7.7 s; AT team vs tank 15.0 s (discrete 14.4 s); rifle squad vs rifle squad 7.7 s; rifle vs tank 57.7 s.
* **Economy**: Collector 600-credit load, harvest 1 credit/tick, unload 6 credits/tick, 2.0 c/s → **766 credits/min at 10 cells** (735 at 12, 632 at 20). 3 collectors per refinery. Deposits: 600 credits/cell, standard field 24 cells = 14,400 credits, finite, no regrowth.
* **Power**: 1 Generator (+150) carries ~136 power of draw with the 10 % headroom rule; a full late base with a superweapon draws 795 → 6 generators (3,600 credits).
* **Pacing** (competent play, four scripted plans): first scout ≈ 2:07-2:22, first T1 tank ≈ 3:04 (army-first) - 4:11 (balanced), Radar ≈ 2:14-2:37, first mobile AA ≈ 5:39-6:33, Laboratory ≈ 4:31 (tech rush) - 9:21 (army-first), superweapon structure ≈ 6:59 - 11:20, **first superweapon shot ≈ 14:59 (tech rush) - 19:20 (balanced)**.
* **Damage pipeline**: `final = raw × bonus_bp/10000 × matrix% × (100 − min(50, Σres))% × falloff%`, one half-up rounding, minimum 1; EMP never takes health below 1.

---

## 2. Files & classes (path, class_name, one-line responsibility), respecting the module prefixes in ARCHITECTURE.md

| Path | class_name | Responsibility | Status |
|---|---|---|---|
| `docs/balance/FRAMEWORK.md` | – | This specification | written |
| `docs/balance/TAXONOMY.md` | – | Vocabulary, matrix, resistances, size/movement classes, weapon archetypes, frozen enums | written |
| `game/data/balance/global.json` | – | All framework numbers (single source of truth) | written, validated |
| `tools/py/balance_calc.py` | – | Proposal generator, integer resolver, engagement model, sanity tables, `validate` gate | written, `validate` = 0 failures |
| `game/src/data/def_balance_global.gd` | `DefBalanceGlobal` | Immutable typed view of `global.json`: converted int tables (matrix, group masks, terrain speeds, sizes), weapon archetype table, economy constants, data hash | task BAL-1 |
| `game/src/data/def_weapon_arch.gd` | `DefWeaponArch` | One weapon archetype in sim integers (units, ticks, layer mask) | BAL-1 |
| `game/src/data/def_economy_consts.gd` | `DefEconomyConsts` | Typed integer economy/power/production constants | BAL-1 |
| `game/src/data/def_damage_math.gd` | `DefDamageMath` | Pure static integer damage helpers (pipeline, splash falloff, beam ramp, non-lethal clamp) — the only place the damage formula lives | BAL-1 |
| `game/src/data/def_percent_math.gd` | `DefPercentMath` | Pure static integer helpers for the bible layer rule and unit conversions (half-up, ceil, basis points) used by the resolver | BAL-1 |
| `game/tests/test_balance_global.gd`, `game/tests/test_damage_math.gd`, `game/tests/test_percent_math.gd` | `TestBalanceGlobal`, … | Unit tests with the expected values listed in §10 | BAL-1 |
| `tools/py/balance_lint.py` | – | Roster-level linter for the faction balance files (fair-cost deviation, bands, T1-only survival, offsets, RPS on the faction's real units) | BAL-2 |
| `game/tests/balance/bal_harness.gd` (+ fixtures `game/tests/fixtures/balance/*.json`) | `BalHarness` | Headless real-sim measurement scripts for §5.17 (TTK matrix, equal-spend armies, first timings, snowball, superweapon metrics) | BAL-3 |
| `game/tests/test_economy_constants.gd` | `TestEconomyConstants` | Collector-cycle / payback conformance against `DefEconomyConsts` | BAL-4 |

Module rules: `DefBalanceGlobal` lives in `data/` (deps: core only), is constructed by `GameData` and reached by `sim` through `world.data.balance`
(never an autoload). `balance_calc.py` is offline tooling (floats allowed, DR-x does not apply) and is not shipped in the game.

---

## 3. Public API (exact GDScript signatures with types and semantics; call and tick order; who owns which memory)

### 3.1 `DefBalanceGlobal` (game/src/data/def_balance_global.gd)

```gdscript
class_name DefBalanceGlobal
extends RefCounted
## Immutable, integer-only view of game/data/balance/global.json. Built once by GameData; shared read-only by every SimWorld.

enum DamageType { BULLET = 0, AP = 1, HE = 2, THERMAL = 3, RAIL = 4, KINETIC = 5, EMP = 6 }
enum ArmorClass { INFANTRY = 0, LIGHT_VEHICLE = 1, MEDIUM_ARMOR = 2, HEAVY_ARMOR = 3, AIR_LIGHT = 4, AIR_HEAVY = 5,
                  SHIP_LIGHT = 6, SHIP_HEAVY = 7, BUILDING_LIGHT = 8, BUILDING_HEAVY = 9, FORTRESS = 10 }
enum Layer { GROUND = 0, AIR = 1, SURFACE_WATER = 2, UNDERWATER = 3 }
enum MoveClass { FOOT = 0, WHEELED = 1, TRACKED = 2, AMPHIBIOUS = 3, NAVAL = 4, SUBMERGED = 5, AIR_FIXED = 6, AIR_HOVER = 7, STATIC = 8 }
enum TerrainKind { ROAD = 0, OPEN = 1, ROUGH = 2, FOREST = 3, MARSH = 4, SHALLOW = 5, DEEP = 6, CLIFF = 7 }
enum FireMode { DIRECT = 0, INDIRECT = 1, MELEE = 2 }
enum Interceptable { NONE = 0, TRIDENT = 1, APS_TRIDENT = 2 }
enum SizeClass { INF = 0, LIGHT = 1, MEDIUM = 2, HEAVY = 3, HUGE = 4, AIR_MEDIUM = 5, AIR_LARGE = 6, SHIP_SMALL = 7, SHIP_MEDIUM = 8, SHIP_LARGE = 9 }

const DAMAGE_TYPE_COUNT: int = 7
const ARMOR_CLASS_COUNT: int = 11
const MOVE_CLASS_COUNT: int = 9
const TERRAIN_KIND_COUNT: int = 8
const WEAPON_ARCH_COUNT: int = 27
const GROUP_BULLET: int = 1
const GROUP_EXPLOSIVE: int = 2
const GROUP_BEAM: int = 4
const GROUP_THERMAL: int = 8
const GROUP_RAIL: int = 16
const GROUP_KINETIC: int = 32
const GROUP_EMP: int = 64

var version: int                       ## global.json "version"
var data_hash: int                     ## FNV-1a-32 over every converted table below (feeds the lobby data-version hash)
var matrix_pct: PackedInt32Array       ## DAMAGE_TYPE_COUNT * ARMOR_CLASS_COUNT entries, index = dtype * ARMOR_CLASS_COUNT + armor
var type_group_mask: PackedInt32Array  ## per damage type, OR of GROUP_* bits
var type_nonlethal: PackedByteArray    ## per damage type, 1 = never reduces health below 1
var armor_layer: PackedInt32Array      ## per armor class, Layer
var terrain_speed_pct: PackedInt32Array ## MOVE_CLASS_COUNT * TERRAIN_KIND_COUNT, index = move * TERRAIN_KIND_COUNT + terrain (0 = impassable)
var size_radius_units: PackedInt32Array ## per SizeClass, radius in sim units (cells * 1024, half-up)
var size_turn_per_tick: PackedInt32Array ## per SizeClass, binary angle units per tick (4096 per turn)
var size_accel_ticks: PackedInt32Array ## per SizeClass
var resist_cap_pct: int                ## 50 (bible)
var weapon_arch: Array[DefWeaponArch]  ## index = WeaponArch enum value (0..26)
var eco: DefEconomyConsts

## Parse and validate. Returns null (after push_error naming the offending key) if any table is malformed, any index is not dense,
## any matrix cell is outside 0..200, or any bible anchor is violated (start credits 7500, Generator 600/25 s/+150, Radar 1500/-40, service costs 500/1400/3000/900,
## resist cap 50, floors 60/60/50, build radius 8, superweapon 5000/90 s/-200). Never partially loads.
static func from_json_text(json_text: String) -> DefBalanceGlobal

## O(1) matrix lookup. Preconditions: 0 <= dtype < DAMAGE_TYPE_COUNT, 0 <= armor < ARMOR_CLASS_COUNT (asserted in debug builds).
func damage_pct(dtype: int, armor: int) -> int
func group_mask(dtype: int) -> int
func is_nonlethal(dtype: int) -> bool
func terrain_speed(move_class: int, terrain: int) -> int                     ## percent, 0 = impassable
func layer_of_armor(armor: int) -> int
func weapon_arch_def(arch: int) -> DefWeaponArch
## Load-time only (string ids appear in data files, never in the sim).
func damage_type_index(id: String) -> int                                    ## -1 if unknown
func armor_class_index(id: String) -> int
func move_class_index(id: String) -> int
func size_class_index(id: String) -> int
func weapon_arch_index(id: String) -> int
```

### 3.2 `DefWeaponArch` and `DefEconomyConsts`

```gdscript
class_name DefWeaponArch
extends RefCounted
var index: int; var damage_type: int; var fire_mode: int; var projectile_kind: int
var projectile_speed_upt: int          ## sim units per tick, 0 = hitscan
var homing: bool                       ## direct fire always hits a living target; false = lands on target position at fire time
var target_layer_mask: int             ## bit (1 << Layer)
var splash_units: int; var splash_edge_pct: int; var scatter_units: int; var min_range_units: int
var interceptable: int                 ## DefBalanceGlobal.Interceptable
var suppressive_default: bool
var turret_per_tick: int               ## binary angle units per tick
```

```gdscript
class_name DefEconomyConsts
extends RefCounted
var start_credits: int                 # 7500 (bible)
var collector_capacity: int            # 600
var harvest_pulse_ticks: int           # 1
var harvest_credits_per_pulse: int     # 1
var unload_pulse_ticks: int            # 1
var unload_credits_per_pulse: int      # 6
var unload_overhead_ticks: int         # 40
var collector_speed_upt: int           # 102 (2.0 c/s)
var refinery_unload_slots: int         # 1
var deposit_cell_credits: int          # 600
var deposit_rich_cell_credits: int     # 1200
var salvage_pct: int                   # 20 (bible)
var salvage_action_ticks: int          # 160 (8 s, bible)
var wreck_ticks: int                   # 1200 (60 s, bible)
var repair_pct_x100_per_s: int         # 100 (1 %/s, bible)
var repair_cost_pct_x100_per_s: int    # 50  (0.5 %/s of paid price, bible)
var sell_refund_pct: int               # 50
var unit_cap_default: int              # 150
var build_radius_units: int            # 8192 (8 cells, bible)
var generator_output: int              # 150 (bible)
var power_shortage_speed_pct: int      # 50 (bible)
var queue_length: int                  # 5
```

### 3.3 `DefDamageMath` and `DefPercentMath` (pure static, no state)

```gdscript
class_name DefDamageMath
extends RefCounted
const RESIST_CAP_PCT: int = 50

## Single-rounding pipeline. raw >= 0 per-hit weapon damage; bonus_bp = product of weapon-damage bonuses (10000 = none);
## matrix_pct = DefBalanceGlobal.damage_pct(); res_pct = SUM of applicable bible resistances (capped here); falloff_pct 0..100.
## Returns 0 if any factor is 0, else max(1, half_up(raw * bonus_bp * matrix * (100 - min(50, res)) * falloff / 10^10)); int64-safe (max ~6e15).
static func final_damage(raw: int, bonus_bp: int, matrix_pct: int, res_pct: int, falloff_pct: int) -> int
static func cap_resistance(sum_pct: int) -> int                       ## clamp to 0..50
## Splash falloff: 100 at edge_dist 0, linearly down to edge_pct at radius; 0 beyond. All args in sim units. Integer division truncates.
static func splash_falloff_pct(edge_dist_units: int, radius_units: int, edge_pct: int) -> int
## Health after a hit: non-lethal types clamp at 1.
static func health_after(hp: int, damage: int, nonlethal: bool) -> int
## Beam focus ramp as a bonus_bp factor: 10000 at focus 0, ramp_max_pct*100 at focus >= ramp_ticks.
static func ramp_bp(focus_ticks: int, ramp_ticks: int, ramp_max_pct: int) -> int
## Projectile flight time in ticks: ceil(distance_units / speed_upt), min 1; hitscan (speed 0) returns 0.
static func flight_ticks(distance_units: int, speed_upt: int) -> int
```

```gdscript
class_name DefPercentMath
extends RefCounted
static func half_up_div(a: int, b: int) -> int                          ## round(a/b), ties away from zero for positive b
static func ceil_div(a: int, b: int) -> int
## One layer step of the bible rule: acc' = half_up(acc * (10000 + layer_delta_sum_bp) / 10000). Start with acc = 10000.
static func layer_mul(acc_bp: int, layer_delta_sum_bp: int) -> int
static func apply_bp(value: int, bp: int) -> int                         ## half_up(value * bp / 10000)
static func apply_floor_bp(bp: int, floor_bp: int) -> int                ## max(bp, floor_bp): 6000 for cost/build time, 5000 for reload
static func seconds_to_ticks(milli_seconds: int, bp: int) -> int         ## ceil(ms * bp * TPS / (1000 * 10000))
static func cells_to_units(milli_cells: int, bp: int) -> int             ## half_up(mc * 1024 * bp / (1000 * 10000))
static func speed_to_upt(milli_cells_per_s: int, bp: int) -> int         ## half_up(mc_s * 1024 * bp / (1000 * TPS * 10000)), min 1
static func deg_s_to_binary_per_tick(deg_s_x100: int) -> int             ## half_up(deg_s * 4096 / 360 / TPS)
```

### 3.4 Call and tick order, ownership

1. **Boot (ASSUMPTION(data): `GameData` owns boot order and exposes `GameData.balance`):** `GameData.load()` → `DefBalanceGlobal.from_json_text(FileAccess.get_file_as_string("res://data/balance/global.json"))` **before** any faction balance file, because unit sheets refer to armor/size/movement classes by string id that the loader converts with `armor_class_index()` etc.
2. **Resolve:** the modifier resolver (data domain) uses `DefPercentMath` for every layered stat; results are stored in per-roster `DefUnit` int arrays.
3. **Tick (combat domain, pipeline step 8):** for each hit → `DefDamageMath.final_damage(...)` → `health_after(...)`. No other code implements the formula.
4. **Ownership:** `GameData` owns the `DefBalanceGlobal` instance; sims hold a reference and never mutate it (all tables are `PackedInt32Array` created once). `DefDamageMath`/`DefPercentMath` hold no memory.
5. **Python API** (`tools/py/balance_calc.py`, importable): `propose(arch_id, tier, tags, abilities, faction, target_cost, extra_offset_pct) -> dict`, `resolve_unit(unit_id, roster_id) -> dict`,
   `final_damage(raw, matrix_pct, res_pct, falloff_pct, bonus_bp) -> int`, `run_fight(a_units, b_units, start_dist, max_s) -> dict`, `ttk_unopposed(attacker, target) -> float`,
   `compensation_table(bible) -> dict`, `fair_cost_deviation(sheet) -> float`, and one `check_*` function per validator (returns `list[str]` of failures).

---

## 4. Data structures & fields (exact typed field lists; component layouts; enums with integer values)

### 4.1 Enumerations (frozen; full tables in TAXONOMY.md §11)

`DamageType` 0-6 (bullet, ap, he, thermal, rail, kinetic, emp) · `ArmorClass` 0-10 · `Layer` 0-3 (ground, air, surface_water, underwater) ·
`MoveClass` 0-8 · `TerrainKind` 0-7 · `FireMode` 0-2 · `WeaponArch` 0-26 · resist-group bit mask 1/2/4/8/16/32/64.

### 4.2 `global.json` top-level keys

| key | type | meaning |
|---|---|---|
| `version` | int | bump on any change |
| `notes`, `conventions` | [str], dict | units and rounding conventions (tps 20, cell 1024) |
| `damage_types` | [{id, index, groups[], nonlethal, label}] | 7 entries, dense indices |
| `resist_groups` | [str] | bit order 1,2,4,… |
| `armor_classes` | [{id, index, layer, label}] | 11 entries |
| `damage_matrix` | {type: {armor: int %}} | 7 × 11, integers 0..200 |
| `resistance_rules` | dict | cap 50, additive, formula string |
| `layers`, `fire_modes` | [str] | enums |
| `size_classes` | {id: {radius_cells, turn_deg_s, mass \| footprint}} | 10 unit classes + s1..s4 structure classes |
| `terrain_kinds` | [str] | column order of the terrain tables |
| `movement_classes` | {id: {index, layer, terrain_speed_pct{terrain: int}}} | 9 classes |
| `movement_defaults` | dict | accel ticks per size class, reverse speed, formation spacing |
| `vision_defaults_cells`, `detection` | dict | default vision by role, detector radii (bible) |
| `weapon_archetypes` | {id: {index, damage_type, fire_mode, projectile_kind, projectile_speed_cells_s, homing, targets[], splash_cells, splash_edge_pct, scatter_cells, range_cells_band, min_range_cells, reload_s_band, turret_deg_s, interceptable_by, suppressive_default, notes}} | 27 entries |
| `ability_templates` | {id: {fields[], defaults, source}} | 16 templates (§4.6) |
| `scaling` | dict | power-index and fair-cost formulas, tolerance bands |
| `production` | dict | credit rates per producer, queue length, floors, shortage speed |
| `structures` | {id: {cost_credits, build_time_s, health, armor_class, footprint[2], radius_cells, vision_cells, power_delta, …}} | 15 entries (incl. Relay, HQ) |
| `defenses` | {shared{}, advanced{}, budget{}} | weapons of the three shared defences and the eight advanced ones |
| `tier_curves` | {"T1"\|"T2"\|"T3": {role: {archetype, cost_credits, build_time_s, health, dps_vs_primary, range_cells, speed_cells_s, vision_cells, radius_cells}}} | derived mirror of `archetypes` (validated) |
| `archetypes` | {id: full reference unit} | 32 entries (§4.3) |
| `service_units` | {engineer, collector, mcv, landing_transport} | bible costs + our stats |
| `style_tags`, `ability_value_pct` | dict | tag multipliers; credit value of abilities (§5.4) |
| `faction_styles` | {faction: {summary, power_offset_pct}} | compensation output |
| `economy`, `power`, `aircraft`, `naval`, `artillery`, `carriers` | dict | §5.8, 5.9, 5.12, 5.13, 5.14 |
| `superweapons`, `support_power_damage` | dict | §5.11 |
| `veterancy` | {enabled:false} | bible |
| `unit_assignments` | {unit_id: {archetype, tags[], abilities[], tier?}} | 156 rows (service rows use `service.*`) |
| `targets` | dict | validation bands: `ttk_unopposed_s`, `rps_equal_cost`, `sortie`, `defenses`, `structure_kill`, `superweapon`, `economy`, `pacing` (incl. `plans`) |
| `modifier_compensation` | dict | factor 0.6, clamps, valuation tables, `recommended` per roster |

### 4.3 Reference unit entry (`archetypes.<id>`)

`family` (str) · `tier` (1-3) · `producer` (barracks/factory/airfield/dock) · `size_class` · `armor_class` · `movement_class` · `layer` ·
`cost_credits` (int) · `build_time_s` (float, multiple of 0.5) · `health` (int) · `speed_cells_s` · `vision_cells` · `radius_cells` ·
`primary_target_class` (armor id the DPS budget is measured against) · `power_exponents{hp,dps,range,speed,vision}` · `weapons[]` (instances, §4.4) ·
`dps_ref` (float, sustained DPS vs primary class; aircraft: sortie average) · `range_cells` (max weapon range) · optional `transport_capacity_squads`, `aura_radius_cells`,
aircraft `sortie_damage_raw`, `sortie_cycle_s`, `rearm_s_full`, `burst_dps_vs_primary`, carrier `drone_*`.

### 4.4 Weapon instance template (what a designer fills for every weapon)

```json
{
  "id": "weapon.napc.guardian_cannon",
  "archetype": "tank_cannon",
  "damage": 140,
  "hits_per_volley": 1,
  "reload_s": 1.2,
  "range_cells": 7.0,
  "min_range_cells": 0.0,
  "splash_cells": 0.5,
  "splash_edge_pct": 50,
  "scatter_cells": 0.0,
  "targets_override": null,
  "turret_deg_s": 90,
  "suppressive": false,
  "deploy_s": 0.0,
  "ammo_volleys": 0,
  "ramp_seconds": 0.0,
  "ramp_max_pct": 100
}
```

| field | type | rule |
|---|---|---|
| `archetype` | weapon archetype id | fixes damage type, fire mode, projectile, default splash/scatter, target set, interceptability; **cannot be overridden** |
| `damage` | int per hit | ≥ 25 (rocket 55 and beam ticks 33-50 accepted); before any modifier. After the matrix a non-strategic hit may not exceed 100 % of a T1 tank's 900 HP (no one-shot kills of a full-health T1 tank; documented exceptions: anti-structure bombs and salvos, e.g. Condor's 1,540 bomb) |
| `hits_per_volley` | int ≥ 1 | cosmetic multi-hit volley; DPS = damage × hits / reload_s |
| `reload_s` | seconds | inside the archetype's reload band; after modifiers ≥ 50 % of base; ≥ 0.25 s |
| `range_cells`, `min_range_cells` | cells | inside the archetype's range band (±10 % with tags); artillery ratio to own vision in §5.14 |
| `splash_cells`, `splash_edge_pct`, `scatter_cells` | | default from archetype; override only ±30 % |
| `targets_override` | [layer] \| null | e.g. `["air","ground"]` for dual-purpose flak; `["air"]` for the laser AA |
| `deploy_s` | seconds | artillery/siege deployment before first shot (bible values quoted in prose) |
| `ammo_volleys` | int | aircraft/limited-ammo units only; sortie economics in §5.12 |
| `ramp_seconds`, `ramp_max_pct` | | beams only: 100 → `ramp_max_pct` over `ramp_seconds` of uninterrupted focus on one target |

### 4.5 Unit sheet template (the balance-layer entry a designer fills; ASSUMPTION(data_balance): the final schema and file layout are owned by data_balance, only these fields and their meaning are fixed here)

```json
{
  "id": "unit.napc.guardian_tank",
  "archetype": "mbt_t1",
  "tier": 1,
  "size_class": "medium",
  "armor_class": "medium_armor",
  "movement_class": "tracked",
  "layer": "ground",
  "cost_credits": 850,
  "build_time_s": 27.5,
  "health": 900,
  "speed_cells_s": 2.0,
  "vision_cells": 9.0,
  "radius_cells": 0.55,
  "turn_deg_s": 150,
  "accel_ticks": 6,
  "deep_speed_pct": null,
  "dps_vs_primary": 116.7,
  "range_cells": 7.0,
  "weapons": ["weapon.napc.guardian_cannon"],
  "abilities": [],
  "tags": [],
  "notes": ""
}
```

Rules: `cost_credits`/`build_time_s` are **omitted (null) for the four service units** because the bible fixes cost (build time is ours: 18/30/67/25 s). Bible values are never overridden;
a unit that the bible gives no number keeps the computed proposal unless it passes the tolerance check of §5.4. `dps_vs_primary` and `range_cells` are derived helper fields for `balance_calc.py check`; aircraft sheets additionally carry `sortie_avg_dps_vs_primary` (sortie damage × matrix ÷ sortie cycle), which is the value the fair-cost check compares.

### 4.6 Ability parameter templates (`ability_templates`)

| template | fields | defaults / bible values |
|---|---|---|
| `deploy` | deploy_s, pack_s, mobile_in_mode, weapon_range_pct, locks_hull | deploy 3 s, pack 2 s; Paladin 3, Charlemagne 4 s +25 % range, Ifrit 3, Gaj 4 s +20 %, Saker 1, Ibex 2, Outrider 3, Fortress Guard 3, Shinano mode switch 3, Long Walker 3 (+2 cells command radius) |
| `camouflage` | delay_s, reveal_on, reveal_hold_s, while_moving | 6 s (bible); reveal on fire/damage/detected; Dune Rover hold 6 s and moves camouflaged |
| `heal_aura` | pct_max_health_per_s_x100, radius_cells, targets | 200 (2.0 %/s) in 4 cells, same source never stacks |
| `repair_target` | pct_max_health_per_s_x100, cost_pct_of_paid_price_per_s_x100, targets, one_at_a_time | 100 / 50 (Engineer, bible) |
| `command_field` | radius_cells, damage_pct, targets | 5 cells, +10 % damage to unmanned (bible) |
| `detector` | radius_cells | 5 (bible) |
| `interception` | cooldown_s, range_cells, targets | Ural 12 s, Arjun 15 s (bible), range 3 cells, ordinary missiles only |
| `smoke_launcher` | radius_cells, duration_s, cooldown_s | 4 / 6 / 40 (Naga, bible) |
| `decoy` | cooldown_s, lifetime_s, health | 40 / 30 / 1 (Echo Team, bible) |
| `cover` | build_s, lifetime_s, bullet_resist_pct, pieces_per_builder | 4 / 45 / 20 (bible); Alpine shelter 25 |
| `sensor` | radius_cells, duration_s, cooldown_s, detects_camouflage | Civic puck 4 / 20 / 30, no camouflage detection (bible); Fen mast radius 6 |
| `salvage` | time_s, payout_pct_of_paid_cost, wreck_lifetime_s | 8 / 20 / 60 (bible) |
| `transport` | capacity_squads, capacity_vehicles, load_s, unload_s | APC 2, Okapi 3, Leviathan 4, Landing Transport 4 squads or 2 vehicles (bible) |
| `emp` | weapon_disable_s, structure_shutdown_s, damage | 8 / 18 / 150 non-lethal (Aurora) |
| `jammer` | radius_cells, sight_pct | 5 cells, −25 % (Aster, bible) |
| `suppression` | hits_needed, window_s, slow_pct, slow_s | 3 / 2 / 25 / 3 (bible) |

### 4.7 JSON → simulation-integer conversion (DR-10: once, at load)

| key suffix | conversion | example |
|---|---|---|
| `_cells` | `units = half_up(cells × 1024)` | 7.0 → 7168 |
| `_cells_s` | `units/tick = half_up(cells_s × 1024 / 20)` | 2.0 → 102 (1.992 c/s) |
| `_s` | `ticks = ceil(round(s × 1000) × 20 / 1000)` | 27.5 → 550; 1.2 → 24 |
| `_pct` | int percent | 40 |
| `_bp` | int basis points | 11500 |
| `_deg_s` | `binary_angle/tick = half_up(deg_s × 4096 / 360 / 20)` | 150 → 85 |
| `credits`, `health`, `damage` | int, half-up | 850 |


---

## 5. Rules & algorithms (precise: formulas, rounding, tie-breaks, state machines, numbers; explain how each bible rule in your domain is honored)

### 5.1 Scale, units and the integer resolution recipe

* **World scale** (ARCH §3): 1 cell = 1024 units = 3 m; 20 ticks/s. A 128×128 map is 384 m across; crossing 128 cells takes a T1 tank 64 s (2.0 c/s), a rifle squad 85 s (1.5), a scout 40 s (3.2), a fighter 18 s (7.0), a capital ship 80 s (1.6).
* **Source data** are human units (cells, cells/s, seconds, percent) converted once at load (§4.7). Never round twice: resolve a stat in *milli-units* and convert last.
* **The bible layering rule as integers.** For one stat of one unit in one roster, take the matching modifiers (selector → unit tags; `conditions[]` become runtime checks; `unresolved_target_domain` is resolved by weapon properties — thermal-beam weapons = damage type `thermal`, ordinary guided missiles = projectile kind `missile` with `interceptable_by = aps_trident`).
  ```
  acc = 10000                                            # basis points
  for layer in (parent_faction, subfaction, research_and_temporary_effects):
      d = sum(delta_percent * 100 for matching modifiers of (stat, layer))     # deltas ADD inside a layer
      if d != 0: acc = half_up(acc * (10000 + d) / 10000)                      # layers MULTIPLY
  cost_acc, build_acc = max(acc, 6000)      reload_acc = max(acc, 5000)        # bible floors 60 % / 60 % / 50 %
  ```
* **Final conversions** (all half-up unless noted; `x_milli` = value × 1000 rounded):

| stat (bible name) | applies to | final integer |
|---|---|---|
| `cost_credits` | units, structures | `half_up(base × acc / 10000)` |
| `health` | units, structures | `max(1, half_up(base × acc / 10000))` |
| `build_time_seconds` | units, structures | `ceil(build_ms × acc × 20 / 10^7)` ticks, min 1 |
| `movement_speed` | units | `max(1, half_up(speed_milli × 1024 × acc / (1000 × 20 × 10^4)))` units/tick |
| `weapon_range_cells` | weapons | `half_up(range_milli × 1024 × acc / 10^7)` units |
| `sight_cells` | units | same as range |
| `reload_interval_seconds` | weapons | `max(ceil(base_ticks / 2), ceil(reload_ms × acc × 20 / 10^7))` ticks |
| `weapon_damage` | weapons | **not baked**: kept as `bonus_bp` and multiplied at hit time together with temporary buffs (Relay, Combined Arms Window, Central Priority…) |
| `rearm_time_seconds` | aircraft | `sortie_cycle = cycle − rearm_full + rearm_full × acc/10000` |
| `power_output` | Generators | `half_up(150 × acc / 10000)` (OLM +25 % → 188; Saudi 1.25 × 1.20 → 225) |
| `repair_credit_cost_per_health`, `repair_progress_rate`, `projectile_flight_speed` | repairs, structures, guided missiles | multiplier on the repair credit rate, repair speed, projectile `speed_upt` |

* **"No same-source stacking"** is enforced by the resolver keying modifiers by `(source_id, stat)`; identical sources add once.

### 5.2 Damage pipeline (the only formula)

```
final = max(1, half_up( raw × bonus_bp × matrix_pct × (100 − min(50, Σres_pct)) × falloff_pct  /  10^10 ))     # 0 if any factor is 0
```
* `raw` = weapon damage per hit (int). `bonus_bp` = product of weapon-damage bonuses in basis points (layer rule, so +10 % Relay and +15 % Central Priority in different layers give 11000 × 11500 / 10000 = 12650).
* `matrix_pct` = `damage_matrix[type][armor of target]` — armor, not resistance; the 50 % cap does not apply to it.
* `Σres_pct` = sum of all applicable resistance sources (TAXONOMY §5), each filtered by damage group, fire mode, arc, target state; capped at 50 (bible). Identical sources do not stack.
* `falloff_pct` = 100 for direct hits; for splash `100 − ((100 − edge_pct) × edge_dist) / radius` (integer division) with `edge_dist = max(0, centre_dist − target_radius)`; 0 if `edge_dist > radius`. Structures use their inscribed radius.
* **Direct fire** (`homing`): the projectile always hits a living target after `ceil(distance / speed)` ticks; if the target died in flight the shot is spent. **Ballistic** (`homing = false`): impact centre = target position **at fire time** + uniform disc of `scatter_cells` drawn from `SimRng` (fixed draw order per weapon); movers escape slow shells.
* **Beams** (`beam_thermal`): every `reload_ticks` (5) apply `final_damage(raw, ramp_bp(focus_ticks, ramp_ticks, ramp_max_pct), …)`; `focus_ticks` counts consecutive pulses on the same target and resets on retarget, loss of line of fire or deploy change. Helios is a moving-spot variant (§5.11).
* **Rail / hitscan** weapons resolve at fire tick (flight 0). **Non-lethal** (`emp`): `health_after = max(1, hp − dmg)`; status effects (weapon disable, shutdown) are separate durations.
* **Interception** removes the projectile before impact (Ural/Arjun: ordinary `missile` kinds only; Trident: `missile`, `rocket` and indirect `shell` kinds; never beams, bullets, rails, EMP, strategic packets). It is not a resistance and ignores the cap.
* **Suppression** (bible): three hits from `suppressive` weapons within 40 ticks → infantry speed × 75 % for 60 ticks after the last hit.

| worked case | inputs | result |
|---|---|---|
| Guardian shell vs Guardian | 140, `ap` vs medium 100 %, res 0 | 140 |
| … with Adaptive Plating | res 10 | 126 |
| Rifle hit vs tank under Steel Advance | 26 `bullet` vs medium 30 %, res 20 | 6 (26 × 0.30 × 0.80 = 6.24) |
| Rifle hit inside a Relay field vs infantry | 26 × 11000 bp, 100 % | 29 |
| Resistance cap | Adaptive 10 + Steel 20 + Protected 15 + Dust 30 = 75 → 50 on a 200-damage `ap` hit | 100 |
| Atlas rod, edge of circle on a Factory | 2400 `kinetic` vs building_heavy 130 %, falloff 50 % | 1560 |
| Atlas rod, centre, on a T3 tank / squad | 2400 vs heavy 130 % / infantry 40 % | 3120 (87 % of 3600 HP) / 960 (dead) |
| Minimum damage | 1 `bullet` vs fortress 6 % | 1 |
| Helios pulse (620 DPS → 31 per tick) | vs medium 100 % / vs squad 55 % | 31 / 17 |
| Sunwall pulse at full ramp | 33 × 19000 bp vs medium | 63 |
| Aurora pulse | 150 `emp` vs a 900-HP tank / a 100-HP drone | tank 750 left / drone 1 left |

### 5.3 Tier and role curves (numeric, by tier and role)

| Tier | Role | Archetype | Cost | Build s | HP | DPS vs primary class | Range | Speed c/s | Vision | Radius |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| T1 | infantry_line | inf_line | 250 | 9.0 | 400 | 52 | 5.5 | 1.5 | 7.0 | 0.4 |
| T1 | infantry_at | inf_at | 350 | 12.5 | 300 | 60 | 7.5 | 1.4 | 7.5 | 0.4 |
| T1 | scout_apc | veh_scout | 550 | 17.5 | 520 | 30 | 6.0 | 3.2 | 12.0 | 0.45 |
| T1 | tank | mbt_t1 | 850 | 27.5 | 900 | 117 | 7.0 | 2.0 | 9.0 | 0.55 |
| T1 | patrol_boat | ship_patrol | 600 | 16.5 | 700 | 48 | 6.5 | 3.2 | 11.0 | 0.6 |
| T2 | infantry_specialist_unarmed | inf_support | 450 | 16.0 | 300 | 0 | 0.0 | 1.5 | 9.0 | 0.4 |
| T2 | infantry_specialist_armed | inf_combat_spec | 500 | 18.0 | 420 | 36 | 5.0 | 1.4 | 8.0 | 0.4 |
| T2 | artillery_light | arty_light | 900 | 26.5 | 480 | 43 | 11.0 | 2.6 | 9.0 | 0.5 |
| T2 | tank | mbt_t2 | 1250 | 37.0 | 1600 | 160 | 7.5 | 1.8 | 9.5 | 0.6 |
| T2 | anti_air_vehicle | veh_aa | 1050 | 31.0 | 800 | 133 | 10.0 | 2.2 | 10.0 | 0.55 |
| T2 | artillery_howitzer | arty_howitzer | 1300 | 38.0 | 650 | 57 | 15.0 | 1.5 | 8.5 | 0.6 |
| T2 | artillery_rocket | arty_rocket | 1250 | 37.0 | 600 | 55 | 13.0 | 1.7 | 8.5 | 0.6 |
| T2 | artillery_missile | arty_missile | 1450 | 42.5 | 600 | 65 | 17.0 | 1.7 | 8.5 | 0.6 |
| T2 | fighter | air_fighter | 1100 | 30.5 | 700 | 100 burst / 30 sortie | 8.0 | 7.0 | 11.0 | 0.5 |
| T2 | escort_ship | ship_escort | 1700 | 47.0 | 2200 | 90 | 10.0 | 2.4 | 11.0 | 1.0 |
| T2 | tank:rail | mbt_t2_rail | 1250 | 37 | 1500 | 161 | 11.0 | 1.8 | 9.5 | 0.6 |
| T2 | anti_air_vehicle:beam | veh_aa_beam | 1050 | 31 | 800 | 133 | 9.0 | 2.2 | 10.0 | 0.55 |
| T2 | anti_air_vehicle:flak | veh_aa_flak | 1050 | 31 | 800 | 62 | 8.0 | 2.2 | 10.0 | 0.55 |
| T3 | siege_tank:ap | siege_ap | 2400 | 63.0 | 3600 | 256 | 8.5 | 1.4 | 8.5 | 0.8 |
| T3 | siege_tank:he | siege_he | 2400 | 63.0 | 3600 | 233 | 8.5 | 1.4 | 8.5 | 0.8 |
| T3 | siege_tank:rail | siege_rail | 2400 | 63.0 | 3300 | 250 | 12.0 | 1.4 | 8.5 | 0.8 |
| T3 | siege_tank:beam | siege_beam | 2400 | 63.0 | 3200 | 200 | 9.0 | 1.4 | 8.5 | 0.8 |
| T3 | siege_tank:demo | siege_demo | 2400 | 63.0 | 3800 | 250 | 4.5 | 1.2 | 8.0 | 0.85 |
| T3 | command_walker | veh_command | 2800 | 73.5 | 3000 | 133 | 8.0 | 1.3 | 9.0 | 1.0 |
| T3 | assault_carrier | veh_assault_carrier | 2900 | 76.5 | 4000 | 167 | 5.5 | 1.5 | 8.5 | 1.0 |
| T3 | gunship | air_gunship | 2100 | 58.5 | 1500 | 120 burst / 37 sortie | 6.0 | 4.5 | 10.0 | 0.6 |
| T3 | bomber | air_bomber | 1900 | 53.0 | 1100 | 583 burst / 35 sortie | 1.5 | 6.0 | 10.0 | 0.7 |
| T3 | strike_drone | air_drone | 1500 | 41.5 | 650 | 300 burst / 21 sortie | 6.0 | 6.5 | 10.0 | 0.5 |
| T3 | ew_aircraft | air_ew | 1800 | 50.0 | 900 | 0 | 0.0 | 5.0 | 10.0 | 0.6 |
| T3 | siege_ship | ship_siege | 3200 | 89.0 | 4500 | 120 | 20.0 | 1.6 | 10.5 | 1.3 |
| T3 | carrier | ship_carrier | 3800 | 105.5 | 5000 | 216 | 0.0 | 1.5 | 11.0 | 1.5 |
| T3 | submarine | ship_sub | 2600 | 72.0 | 2000 | 62 | 22.0 | 1.8 | 9.0 | 0.9 |

*Reading guide.* Aircraft: `DPS` column shows burst DPS while firing and the sortie-average DPS (damage per sortie ÷ cycle) used by the fair-cost formula. `siege_tank:*` are the five T3 weapon variants; `tank:rail`, `anti_air_vehicle:*` are weapon swaps at T2.
Build time = cost ÷ producer rate (rates below, rounded to 0.5 s). **Default vision by role (cells):** rifle 7.0, AT team 7.5, specialists 9.0 (observers/spotters 12.0), scout/APC 12.0, T1 tank 9.0, T2 tank 9.5, T3 siege 8.5, mobile AA 10.0, artillery 8.5, fighter 11.0, ground-attack aircraft 10.0, patrol boat / escort 11.0, capital ship 10.5, Collector / MCV 8.0, structures 8.0 (Radar 14, HQ 11, AA battery 12, advanced defence 13); detection radius 5 (Watchtower 4, AA battery 5). `range / vision` ratios are in §5.5.

**Producer credit rates** (build time = cost / rate; a producer's maximum spend per minute):

| producer (tier) | credits per second | credits per minute |
| :--- | ---: | ---: |
| barracks | 28 | 1680 |
| factory_t1 | 31 | 1860 |
| factory_t2 | 34 | 2040 |
| factory_t3 | 38 | 2280 |
| airfield | 36 | 2160 |
| dock | 36 | 2160 |
| refinery | 46 | 2760 |
| construction | 48 | 2880 |

Build times of the bible-fixed structures imply 24-56 credits/s (Generator 24 … superweapon 56); new structure times must use 40 credits/s (Relay: 600 / 40 = 15 s).

**Tolerance bands** a designer's unit must respect (checked by `balance_calc.py check` and BAL-2): cost ±25 %, health ±30 %, speed ±35 %, vision ±30 %, radius ±20 %, DPS ±30 %, range ±25 % against the archetype reference *and* a fair-cost deviation within ±8 % (§5.4). Tags and abilities move the reference; a unit outside the band needs a `notes` line explaining the bible sentence it implements.

**Tier progression rule.** Cost per unit of power (PI/cost) is constant inside a family. Between tiers the family reference changes: T2 tanks give 1.28 HP/credit vs 1.06 (+0.28 remaining-cost share at equal cost), T3 give 1.50 (T3 beats T1 by +0.28 and T2 by +0.24). The extra HP per credit pays for the Radar (1,500) + Laboratory (2,500) tech tax and the slower production of expensive units.

### 5.4 Formula sheet: power index, fair cost, build time, styles

**Power index (PI) and fair cost.** For a unit of family `f` with reference `(HP0, DPS0, R0, S0, V0, cost0)` (the archetype):
```
PI     = (HP/HP0)^a_hp × (DPS/DPS0)^a_dps × (R/R0)^a_range × (S/S0)^a_speed × (V/V0)^a_vision
cost   = round_to_5_or_25( cost0 × PI × (1 + Σ ability_value_pct / 100) )          # < 1000: step 5, else step 25
build  = round_to_0.5( cost / rate[producer, tier] )
```
Exponents (`archetypes.*.power_exponents`): HP and DPS 0.5 (square-law: strength ∝ √(HP × DPS)); range/speed/vision by family:

| family | HP | DPS | range | speed | vision |
| :--- | ---: | ---: | ---: | ---: | ---: |
| infantry | 0.5 | 0.5 | 0.25 | 0.15 | 0.05 |
| support | 0.5 | 0.5 | 0.1 | 0.15 | 0.3 |
| scout | 0.5 | 0.5 | 0.2 | 0.35 | 0.25 |
| artillery | 0.5 | 0.5 | 0.45 | 0.1 | 0.1 |
| tank | 0.5 | 0.5 | 0.3 | 0.2 | 0.05 |
| aa | 0.5 | 0.5 | 0.4 | 0.15 | 0.1 |
| siege | 0.5 | 0.5 | 0.3 | 0.1 | 0.05 |
| aircraft | 0.5 | 0.5 | 0.25 | 0.15 | 0.08 |
| ship | 0.5 | 0.5 | 0.35 | 0.1 | 0.1 |

`DPS` is the sustained DPS against the archetype's **primary target class** (infantry for rifles, `medium_armor` for AT teams and tanks, `air_light` for AA, `building_heavy` for siege guns, sortie average for aircraft). A unit with no weapon that belongs to an armed archetype (`no_gun`) is priced at half of its offensive share.

**Trade rule** (tank family): +10 % HP costs +4.9 % price, or is offset by −9.1 % DPS, or by −21 % speed (exponent 0.20); +20 % range (exponent 0.30) costs +5.6 % price, or −5.3 % HP and −5.3 % DPS. The calculator solves the price so a designer only chooses the shape.

**Style tags** change stats only (multipliers in % of the archetype value; multiply when combined):

* **speed:** `fast` speed 125%; `quick` speed 112%; `slow` speed 88%; `very_slow` speed 70%
* **health:** `fragile` health 85%; `light_hull` health 92%; `sturdy` health 115%; `robust` health 125%; `armored` health 130%
* **weapon damage:** `weak_gun` damage 60%; `weaker_gun` damage 85%; `strong_gun` damage 115%; `no_gun` (unarmed)
* **range:** `long_range` range 120%; `short_range` range 80%; `very_short_range` range 55%
* **burst shape:** `alpha` damage 130%, reload 130%; `sustained` damage 80%, reload 80%
* **sight:** `poor_sight` vision 80%; `good_sight` vision 125%
* **scatter:** `precise` scatter 60%; `inaccurate` scatter 150%
* **radius:** `large` radius 125%; `compact` radius 88%
* **aircraft:** `endurance` ammo 130%; `limited_endurance` ammo 75%; `quick_rearm` rearm 70%; `slow_rearm` rearm 140%; `heavy_bomb` damage 220%, ammo 50%

**Ability values** add to the price (they are the credit cost of a capability; costs of abilities that are inherent to an archetype are already in its reference — e.g. `detector` for scouts and AA, command field for `veh_command`):

| ability | cost % | ability | cost % |
| :--- | ---: | :--- | ---: |
| amphibious | 6 | cover_builder | 4 |
| camouflage | 5 | shield_front | 5 |
| stealth | 6 | unmanned | -3 |
| deployable_mode | 5 | smoke | 3 |
| transport_3 | 4 | jammer | 4 |
| transport_4 | 8 | multirole | 4 |
| detector | 0 | dual_purpose | 6 |
| heal_aura | 8 | spotter | 4 |
| repair_aura | 6 | salvage | 3 |
| command_field | 10 | breach_charge | 4 |
| aps_interception | 7 | frontal_armor | 4 |
| decoy | 3 | drone_repair | 4 |
| sensor | 3 | suppressive_deploy | 4 |

**Faction style** = a summary string plus `power_offset_pct` (§5.15). Offsets scale HP and every weapon damage by √(1 + offset) so PI moves by `offset`; **price is unchanged** (that is what compensates a passive modifier). Passive bible modifiers are never pre-baked.

**Designer procedure** (8 steps): (1) look the unit up in `unit_assignments` (archetype, tags, abilities); (2) `balance_calc.py propose <archetype> --tags … --abilities … --faction <f>` or `proposals --styled --faction <f>`; (3) `--cost N` if the price is being chosen; (4) fill weapons from the archetype, staying inside its bands (§4.4); (5) add the ability parameters from §4.6; (6) apply the unique-unit offset for subfaction units (§5.15); (7) `balance_calc.py check sheet.json`; (8) run `balance_lint.py` on the whole roster and record deviations in `notes`.

**Worked examples (integer resolution, §5.1).**

1. *Guardian Tank (`mbt_t1`, neutral archetype), USA subfaction — vehicle with a same-layer add and a cross-layer stat.*

*Guardian Tank in `roster.napc.usa`* — applied: faction.napc: health +10% (parent_faction); faction.napc: cost_credits +10% (parent_faction); roster.napc.usa: build_time_seconds +15% (subfaction)

| stat | base | layered multiplier | final (sim integer) | rule |
| :--- | ---: | ---: | ---: | :--- |
| cost credits | 850 | 1.1000 | 935 | half-up(base x bp / 10000) |
| health | 900 | 1.1000 | 990 | half-up |
| build time | 27.5 s | 1.1500 | 633 ticks (31.65 s) | ceil(ms x bp x 20 / 1e7) |
| speed | 2.0 c/s | 1.0000 | 102 units/tick (1.992 c/s) | half-up(milli-c/s x 1024 x bp / (1000 x 20 x 1e4)) |
| vision | 9.0 cells | 1.0000 | 9216 units | half-up |
| weapon tank_cannon range | - | 1.0000 | 7168 units | half-up |
| weapon tank_cannon reload | - | 1.0000 | 24 ticks | ceil, floor 50 % of base |
| weapon tank_cannon damage bonus | 140 | 1.0000 | 140 per volley vs primary class | runtime bonus_bp |

2. *Ural Assault Tank (`mbt_t2`, tags `sturdy`, ability `aps_interception`: 1250 × √1.15 × 1.07 = 1,425), Russia — parent −10 % and subfaction +10 % cost multiply to 0.99, speeds multiply to 0.81, health +15 % is subfaction only.*

*Ural Assault Tank in `roster.def.russia`* — applied: faction.def: cost_credits -10% (parent_faction); faction.def: build_time_seconds -10% (parent_faction); faction.def: movement_speed -10% (parent_faction); roster.def.russia: health +15% (subfaction); roster.def.russia: cost_credits +10% (subfaction); roster.def.russia: movement_speed -10% (subfaction)

| stat | base | layered multiplier | final (sim integer) | rule |
| :--- | ---: | ---: | ---: | :--- |
| cost credits | 1425 | 0.9900 | 1411 | half-up(base x bp / 10000) |
| health | 1840 | 1.1500 | 2116 | half-up |
| build time | 42.0 s | 0.9000 | 756 ticks (37.80 s) | ceil(ms x bp x 20 / 1e7) |
| speed | 1.8 c/s | 0.8100 | 75 units/tick (1.465 c/s) | half-up(milli-c/s x 1024 x bp / (1000 x 20 x 1e4)) |
| vision | 9.5 cells | 1.0000 | 9728 units | half-up |
| weapon tank_cannon range | - | 1.0000 | 7680 units | half-up |
| weapon tank_cannon reload | - | 1.0000 | 25 ticks | ceil, floor 50 % of base |
| weapon tank_cannon damage bonus | 200 | 1.0000 | 200 per volley vs primary class | runtime bonus_bp |

3. *Condor Stealth Bomber (`air_bomber`, tags `heavy_bomb`, `slow_rearm`, ability `stealth`), USA — aircraft cost −15 %, rearm −20 % (sortie cycle 48 → 42.4 s).*

*Condor Stealth Bomber in `roster.napc.usa`* — applied: roster.napc.usa: cost_credits -15% (subfaction); roster.napc.usa: rearm_time_seconds -20% (subfaction)

| stat | base | layered multiplier | final (sim integer) | rule |
| :--- | ---: | ---: | ---: | :--- |
| cost credits | 1925 | 0.8500 | 1636 | half-up(base x bp / 10000) |
| health | 1100 | 1.0000 | 1100 | half-up |
| build time | 53.5 s | 1.0000 | 1070 ticks (53.50 s) | ceil(ms x bp x 20 / 1e7) |
| speed | 6.0 c/s | 1.0000 | 307 units/tick (5.996 c/s) | half-up(milli-c/s x 1024 x bp / (1000 x 20 x 1e4)) |
| vision | 10.0 cells | 1.0000 | 10240 units | half-up |
| weapon bomb range | - | 1.0000 | 1536 units | half-up |
| weapon bomb reload | - | 1.0000 | 24 ticks | ceil, floor 50 % of base |
| weapon bomb damage bonus | 1540 | 1.0000 | 1540 per volley vs primary class | runtime bonus_bp |
| rearm (full) | - | 0.8000 | 22.4 s -> sortie cycle 42.4 s | seconds |

*Fair-cost example (Sirocco, `mbt_t1` + tags `fast`, `fragile`):* PI = 0.85^0.5 × 1.25^0.20 = 0.922 × 1.046 = 0.964 → cost 850 × 0.964 = 819 → **820**, HP 765, speed 2.5 c/s, build 820 / 31 = 26.5 s. OLM's passive −10 % light-vehicle HP does not apply to tanks; the roster index of §5.15 covers the rest.

### 5.5 Cross-class budget rules (infantry vs vehicles vs aircraft vs ships vs artillery)

| archetype | T | cost | HP per credit | DPS per 100 cr | range / own vision | speed c/s | armor |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| inf_line | 1 | 250 | 1.60 | 20.8 | 0.79 | 1.5 | infantry |
| inf_at | 1 | 350 | 0.86 | 17.1 | 1.00 | 1.4 | infantry |
| inf_support | 2 | 450 | 0.67 | 0.0 | - | 1.5 | infantry |
| inf_combat_spec | 2 | 500 | 0.84 | 7.2 | 0.62 | 1.4 | infantry |
| veh_scout | 1 | 550 | 0.95 | 5.5 | 0.50 | 3.2 | light_vehicle |
| arty_light | 2 | 900 | 0.53 | 4.8 | 1.22 | 2.6 | light_vehicle |
| mbt_t1 | 1 | 850 | 1.06 | 13.7 | 0.78 | 2.0 | medium_armor |
| mbt_t2 | 2 | 1250 | 1.28 | 12.8 | 0.79 | 1.8 | medium_armor |
| veh_aa | 2 | 1050 | 0.76 | 12.7 | 1.00 | 2.2 | medium_armor |
| arty_howitzer | 2 | 1300 | 0.50 | 4.4 | 1.76 | 1.5 | light_vehicle |
| arty_rocket | 2 | 1250 | 0.48 | 4.4 | 1.53 | 1.7 | light_vehicle |
| arty_missile | 2 | 1450 | 0.41 | 4.5 | 2.00 | 1.7 | light_vehicle |
| siege_ap | 3 | 2400 | 1.50 | 10.7 | 1.00 | 1.4 | heavy_armor |
| siege_he | 3 | 2400 | 1.50 | 9.7 | 1.00 | 1.4 | heavy_armor |
| siege_rail | 3 | 2400 | 1.38 | 10.4 | 1.41 | 1.4 | heavy_armor |
| siege_beam | 3 | 2400 | 1.33 | 8.3 | 1.06 | 1.4 | heavy_armor |
| siege_demo | 3 | 2400 | 1.58 | 10.4 | 0.56 | 1.2 | heavy_armor |
| veh_command | 3 | 2800 | 1.07 | 4.8 | 0.89 | 1.3 | heavy_armor |
| veh_assault_carrier | 3 | 2900 | 1.38 | 5.7 | 0.65 | 1.5 | heavy_armor |
| air_fighter | 2 | 1100 | 0.64 | 2.7 | 0.73 | 7.0 | air_light |
| air_gunship | 3 | 2100 | 0.71 | 1.8 | 0.60 | 4.5 | air_heavy |
| air_bomber | 3 | 1900 | 0.58 | 1.8 | 0.15 | 6.0 | air_heavy |
| air_drone | 3 | 1500 | 0.43 | 1.4 | 0.60 | 6.5 | air_light |
| air_ew | 3 | 1800 | 0.50 | 0.0 | - | 5.0 | air_heavy |
| ship_patrol | 1 | 600 | 1.17 | 7.9 | 0.59 | 3.2 | ship_light |
| ship_escort | 2 | 1700 | 1.29 | 5.3 | 0.91 | 2.4 | ship_heavy |
| ship_siege | 3 | 3200 | 1.41 | 3.8 | 1.90 | 1.6 | ship_heavy |
| ship_carrier | 3 | 3800 | 1.32 | 5.7 | - | 1.5 | ship_heavy |
| ship_sub | 3 | 2600 | 0.77 | 2.4 | 2.44 | 1.8 | ship_heavy |
| mbt_t2_rail | 2 | 1250 | 1.20 | 12.9 | 1.16 | 1.8 | medium_armor |
| veh_aa_beam | 2 | 1050 | 0.76 | 12.7 | 0.90 | 2.2 | medium_armor |
| veh_aa_flak | 2 | 1050 | 0.76 | 5.9 | 0.80 | 2.2 | medium_armor |

1. **Infantry** carry the highest HP and DPS per credit (1.6 HP, 20.8 DPS per 100 credits for `inf_line`) because armour, the matrix and splash remove most of it: a squad deals 30 % to tanks and 25 % to gunships. Only AT teams (60 DPS `ap`, 0.86 HP/credit) and `he` specialists convert credits into anti-armor. Squads are one entity with one health pool (ARCH §12); they count 1 toward the unit cap.
2. **Vehicles** convert cost into HP more than DPS as they get bigger: HP/credit 1.06 → 1.28 → 1.50, DPS/100 credits 13.7 → 12.8 → 10.7. Speed is 2.0 (T1) → 1.4 (T3) c/s; big units are slower and larger (radius 0.55 → 0.8-1.0).
3. **Artillery** pays for range and splash with fragility: 0.41-0.53 HP/credit, single-target DPS/100 credits 4.4-4.5, range 1.5-2.0× own vision (needs spotters), minimum range 20-30 % of range, deploy 1-3 s. Its value is splash on clumps (§5.6) and outranging static defences.
4. **Aircraft** have 0.43-0.71 HP/credit and 1.4-2.7 sortie-average DPS per 100 credits — 5-10× lower than ground units — bought back by speed (4.5-7 c/s), reach and alpha strike; their value is the first sortie against an unescorted target (§5.12).
5. **Ships** are sturdy (1.17-1.41 HP/credit) and slow (1.5-3.2 c/s); only siege ships (range 20) and submarines (range 22) threaten land. Ships are a side theatre: no baseline economy needs water (bible).
6. **Static defences** convert cost into a *static power ratio* of 1.15-1.35 versus mobile units of the same cost (§5.7) and are the only class that draws power.
7. **Entity counts.** Typical 25-minute army 40-70 entities; infantry-heavy rosters (Han −15 % infantry cost) reach 100-120; the 150 cap (§5.8) bounds sim cost, not economy. Carrier drones, Tempest drones, Dragonfall engines, decoys and Collectors are exempt.

### 5.6 Time-to-kill targets and equal-cost matchups

**Definitions.** *Unopposed TTK* = target health ÷ attacker's best-weapon DPS against the target's armor class (matrix included, no resistance, all shots hit, target stationary). *Discrete duel* = full engagement model, both sides firing, from a shared start inside range. *Equal-cost group fight* = two armies bought with 6,000 credits each, starting 24 cells apart, fight to the death or 150 s; the metric is `remaining-cost share of A − remaining-cost share of B` (−1…+1; +0.45…+0.9 = hard counter, +0.15…+0.45 = soft counter, |x| < 0.15 = even).

| attacker | target | TTK s | band | status |
| :--- | :--- | ---: | ---: | :--- |
| mbt_t1 | mbt_t1 | 7.7 | 6-9 | ok |
| mbt_t2 | mbt_t2 | 10.0 | 8-12 | ok |
| siege_ap | siege_ap | 15.6 | 12-18 | ok |
| inf_at | mbt_t1 | 15.0 | 12-18 | ok |
| inf_line | inf_line | 7.7 | 6-9 | ok |
| inf_line | mbt_t1 | 57.7 | 40-70 | ok |
| mbt_t1 | inf_line | 8.6 | 8-12 | ok |
| mbt_t1 | veh_scout | 4.5 | 3.5-6 | ok |
| siege_ap | mbt_t1 | 3.5 | 3-5 | ok |
| mbt_t1 | siege_ap | 34.3 | 24-36 | ok |
| inf_at | inf_line | 16.7 | 14-22 | ok |
| inf_line | inf_at | 5.8 | 5-8 | ok |
| veh_aa | air_fighter | 5.2 | 4-7 | ok |
| veh_aa | air_gunship | 13.2 | 10-15 | ok |
| air_fighter | air_fighter | 7.0 | 5-8 | ok |
| air_fighter | air_gunship | 17.6 | 15-22 | ok |
| air_gunship | mbt_t1 | 7.5 | 6-9 | ok |
| arty_howitzer | mbt_t1 | 24.2 | 20-30 | ok |
| arty_howitzer | inf_line | 7.0 | 5-9 | ok |
| arty_missile | mbt_t1 | 13.9 | 11-17 | ok |
| siege_rail | mbt_t1 | 3.6 | 3-5 | ok |
| siege_he | Factory (4500) | 19.3 | 15-25 | ok |
| ship_patrol | ship_patrol | 14.7 | 12-20 | ok |
| ship_escort | ship_escort | 24.4 | 20-30 | ok |
| ship_siege | ship_escort | 30.6 | 27-40 | ok |
| mbt_t1 | Factory (4500) | 64.3 | 55-80 | ok |

The mirror duel `mbt_t1` vs `mbt_t1` (both firing) ends in 7.7 s and a draw; an AT team loses a 1-vs-1 to a tank (6.5 s, the tank kills the 300-HP squad first) but wins by numbers (three AT teams cost 1,050 and kill a tank in 5.3 s while it fires back). Discrete unopposed measurements (what the harness sees): tank vs tank 7.7 s, AT team vs tank 14.4 s (4 missiles at 0/4.5/9/13.5 s + flight), rifle squad vs tank 57.2 s.

| attacker \ target (s) | inf_line | veh_scout | mbt_t1 | mbt_t2 | siege_ap | arty_howitzer | air_fighter | air_gunship | Factory | HQ |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| inf_line | 7.7 | 18.2 | 57.7 | 102.6 | 461.5 | 22.7 | 20.7 | 115.4 | 721.2 | 1923.1 |
| inf_at | 16.7 | 8.7 | 15.0 | 26.7 | 66.7 | 10.8 | - | - | 125.0 | 250.0 |
| veh_scout | 13.3 | 31.5 | 100.0 | 177.8 | 800.0 | 39.4 | 35.9 | 200.0 | 1250.0 | 3333.3 |
| mbt_t1 | 8.6 | 4.5 | 7.7 | 13.7 | 34.3 | 5.6 | - | - | 64.3 | 128.6 |
| mbt_t2 | 6.2 | 3.2 | 5.6 | 10.0 | 25.0 | 4.1 | - | - | 46.9 | 93.8 |
| veh_aa | - | - | - | - | - | - | 5.2 | 13.2 | - | - |
| arty_howitzer | 7.0 | 10.7 | 24.2 | 43.1 | 126.0 | 13.4 | - | - | 78.8 | 150.0 |
| arty_missile | 15.5 | 8.0 | 13.9 | 24.8 | 61.9 | 10.1 | - | - | 116.1 | 232.1 |
| siege_ap | 3.9 | 2.0 | 3.5 | 6.2 | 15.6 | 2.5 | - | - | 29.3 | 58.6 |
| siege_he | 1.7 | 2.6 | 5.9 | 10.5 | 30.9 | 3.3 | - | - | 19.3 | 36.7 |
| siege_rail | 9.2 | 2.4 | 3.6 | 6.4 | 13.3 | 3.0 | - | - | 31.9 | 50.2 |
| air_gunship | 8.3 | 4.3 | 7.5 | 13.3 | 33.3 | 5.4 | - | - | 62.5 | 125.0 |
| air_fighter | - | - | - | - | - | - | 7.0 | 17.6 | - | - |

**Equal-cost group fights** (row beats column; positive = row wins):

| row beats col | inf_line | inf_at | veh_scout | mbt_t1 | mbt_t2 | arty_howitzer | arty_missile | siege_ap | siege_he |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| inf_line | +0.00 | +0.72 | +0.73 | -0.23 | -0.52 | -0.57 | +0.78 | -0.76 | -0.96 |
| inf_at | -0.72 | +0.00 | +0.86 | +0.45 | +0.34 | -0.15 | +0.55 | +0.32 | -0.56 |
| veh_scout | -0.73 | -0.86 | +0.00 | -0.92 | -0.94 | -0.45 | +0.03 | -0.97 | -0.96 |
| mbt_t1 | +0.23 | -0.45 | +0.92 | +0.00 | -0.28 | +0.69 | +0.60 | -0.28 | -0.17 |
| mbt_t2 | +0.52 | -0.34 | +0.94 | +0.28 | +0.00 | +0.75 | +0.76 | +0.24 | +0.21 |
| arty_howitzer | +0.57 | +0.15 | +0.45 | -0.69 | -0.75 | +0.00 | +0.73 | -0.81 | -0.85 |
| arty_missile | -0.78 | -0.55 | -0.03 | -0.60 | -0.76 | -0.73 | +0.00 | -0.79 | -0.79 |
| siege_ap | +0.76 | -0.32 | +0.97 | +0.28 | -0.24 | +0.81 | +0.79 | +0.00 | +0.41 |
| siege_he | +0.96 | +0.56 | +0.96 | +0.17 | -0.21 | +0.85 | +0.79 | -0.41 | +0.00 |

**Acceptance bands** (each is asserted by `balance_calc.py validate`; the real-engine harness must land within ±0.15 of the model value):

| A | B | share diff | band | status | why |
| :--- | :--- | ---: | ---: | :--- | :--- |
| inf_line | inf_at | +0.72 | +0.45..+0.95 | ok | rifles hard-counter AT infantry |
| inf_at | mbt_t1 | +0.45 | +0.40..+0.90 | ok | AT infantry hard-counters T1 tanks |
| inf_at | mbt_t2 | +0.34 | +0.20..+0.70 | ok | and (softer) T2 tanks |
| mbt_t1 | inf_line | +0.23 | +0.00..+0.40 | ok | tanks soft-counter rifles |
| inf_at | siege_ap | +0.32 | +0.15..+0.60 | ok | cheap AT punishes heavy armor |
| siege_ap | mbt_t1 | +0.28 | +0.10..+0.55 | ok | T3 beats T1 at equal cost (tier premium) |
| mbt_t2 | mbt_t1 | +0.28 | +0.10..+0.45 | ok | T2 beats T1 at equal cost |
| mbt_t1 | veh_scout | +0.92 | +0.60..+1.00 | ok | scouts lose to tanks |
| mbt_t1 | arty_howitzer | +0.69 | +0.40..+0.95 | ok | unescorted howitzers lose to a tank charge |
| arty_howitzer | inf_line | +0.57 | +0.30..+0.80 | ok | artillery beats infantry blobs |
| arty_howitzer | arty_howitzer | +0.00 | -0.05..+0.05 | ok | mirror |
| siege_he | inf_line | +0.96 | +0.60..+1.00 | ok | siege guns crush rifles |

*Model caveats:* no fog/vision limits, no terrain, no micro; artillery is shown unescorted (real armies escort it, so its columns are pessimistic), infantry cannot use cover or garrisons (pessimistic for infantry).

### 5.7 Structures and defences

**Structure table** (cost, build time, power are bible-fixed; HP, armor, footprint, vision are designed). HP follows `HP ≈ 2.0-2.25 × cost` for economy/production/tech, ~1.7-2.0 × for defences, 1.4 × for the superweapon and 2 × the MCV price for the HQ, so an army worth the building's cost razes it in ~20-35 s (validated: 8 T1 tanks, 6,800 credits, kill a 4,500-HP Factory in 8.0 s; an army worth exactly the Factory's 2,000 credits needs ~27 s).

| structure | cost | build s | HP | armor | footprint | vision | power | HP/credit |
| :--- | ---: | ---: | ---: | :--- | :--- | ---: | ---: | ---: |
| headquarters | 0 | n/a | 6000 | fortress | 3x3 | 11.0 | 0 | - |
| generator | 600 | 25 | 1200 | building_light | 2x2 | 6.0 | 150 | 2.00 |
| refinery | 1800 | 40 | 3600 | building_heavy | 3x3 | 8.0 | -30 | 2.00 |
| barracks | 500 | 20 | 1000 | building_light | 2x2 | 7.0 | -10 | 2.00 |
| factory | 2000 | 40 | 4500 | building_heavy | 3x3 | 8.0 | -40 | 2.25 |
| dock | 1800 | 40 | 3600 | building_heavy | 3x3 | 10.0 | -35 | 2.00 |
| radar | 1500 | 30 | 3000 | building_heavy | 2x2 | 14.0 | -40 | 2.00 |
| airfield | 1600 | 35 | 3200 | building_heavy | 4x3 | 8.0 | -40 | 2.00 |
| laboratory | 2500 | 50 | 5000 | building_heavy | 3x3 | 8.0 | -60 | 2.00 |
| watchtower | 450 | 15 | 900 | building_light | 1x1 | 8.0 | -5 | 2.00 |
| anti_tank_turret | 800 | 20 | 1500 | building_heavy | 2x2 | 9.0 | -15 | 1.88 |
| aa_battery | 900 | 20 | 1500 | building_heavy | 2x2 | 12.0 | -20 | 1.67 |
| advanced_defense | 1800 | 35 | 3400 | building_heavy | 2x2 | 13.0 | -40 | 1.89 |
| superweapon | 5000 | 90 | 7000 | fortress | 4x4 | 10.0 | -200 | 1.40 |
| relay | 600 | 15 | 900 | building_light | 1x1 | 8.0 | -20 | 1.50 |

**Shared defences**

| defense | cost | HP | weapon | dmg x hits | reload s | range | raw DPS | power |
| :--- | ---: | ---: | :--- | ---: | ---: | ---: | ---: | ---: |
| watchtower | 450 | 900 | machine_gun | 30x2 | 1.0 | 7.0 | 60 | -5 |
| anti_tank_turret | 800 | 1500 | tank_cannon | 135x1 | 1.3 | 8.0 | 104 | -15 |
| aa_battery | 900 | 1500 | aa_missile | 100x2 | 1.5 | 11.0 | 133 | -20 |

* `watchtower` fire is **suppressive** (bible) and hits air at the bullet matrix (65/25). `aa_battery` mirrors the mobile AA weapon (133 DPS, range 11) with 1,500 HP. `anti_tank_turret` mirrors the T1 tank (104 vs 117 DPS, range 8 vs 7) with 1.67× the HP.
* **Defence design rules:** (1) static power ratio (√(HP × DPS) / cost relative to a same-cost mobile group of the same role) between 1.15 and 1.35; (2) every defence has exactly one exploitable weakness quoted from the bible; (3) power draw −5 … −40 and shutdown during power loss (SAP reserve exception); (4) HP modifiers of the bible (SAP +15 %, PD −15 %, Japan/Thailand −10 %) apply to the values below.

**Advanced defences** (1,800 credits, 35 s, −40 power; HP before faction modifiers; one per faction):

| advanced defense | fac | HP | weapon | dmg x hits | reload s | range | raw DPS | burst | sustained vs medium | shape |
| :--- | :--- | ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| bulwark_cannon | napc | 3400 | tank_cannon | 700x1 | 4.0 | 12.0 | 175 | 700 | 175 | slow traverse; poor vs infantry by matrix |
| lance_rail | nec | 3400 | rail_gun | 700x1 | 5.0 | 14.0 | 140 | 700 | 161 | single target; very long range; long reload |
| sunwall_projector | olm | 3300 | beam_thermal | 33x1 | 0.25 | 10.0 | 132 | 33 | 132 -> 251 (ramp) | beam ramps 130 -> 250 DPS on one target |
| citadel_mortar | def | 4000 | artillery_shell | 340x1 | 3.0 | 16.0 | 113 | 340 | 113 | armored; min range 5 |
| sea_spear_battery | pd | 3400 | at_missile | 170x3 | 6.0 | 13.0 | 85 | 510 | 85 | 3-missile salvo; no air |
| dragon_tooth_launcher | han | 3400 | at_missile | 150x4 | 7.5 | 11.0 | 80 | 600 | 80 | 4-missile burst; vulnerable between salvos |
| forge_cannon | ae | 3600 | tank_cannon | 110x1 | 0.7 | 9.5 | 157 | 110 | 157 | rapid cycling; shorter range than rail |
| bastion_missile_tower | sap | 3600 | at_missile | 550x2 | 9.0 | 12.0 | 122 | 1100 | 122 | 2 x 550 burst then long reload; no AA |

*Break-even budgets:* the smallest attacking army that wins, expressed as a multiple of the defence's price (T1 tanks vs the shared pair, T2 tanks vs each advanced defence, linear interpolation between integer armies):

| defense | attacker | attackers needed | attacker cost / defense cost |
| :--- | :--- | ---: | ---: |
| anti_tank_turret + watchtower (1250) | mbt_t1 | 2 | 1.24 |
| 2 x (turret + tower) (2500) | mbt_t1 | 5 | 1.42 |
| bulwark_cannon (1800) | mbt_t2 | 3 | 1.67 |
| lance_rail (1800) | mbt_t2 | 3 | 1.93 |
| sunwall_projector (1800) | mbt_t2 | 3 | 1.61 |
| citadel_mortar (1800) | mbt_t2 | 2 | 1.03 |
| sea_spear_battery (1800) | mbt_t2 | 2 | 1.06 |
| dragon_tooth_launcher (1800) | mbt_t2 | 2 | 1.08 |
| forge_cannon (1800) | mbt_t2 | 3 | 1.57 |
| bastion_missile_tower (1800) | mbt_t2 | 3 | 1.45 |
| turret + tower (1250) | 2 x arty_howitzer (2600) | - | howitzers alive 2/2 in 26s |

Reading: rails/cannons/beams (Lance 1.93, Bulwark 1.67, Sunwall 1.61, Forge 1.57, Bastion 1.45) punish approaching vehicles; mortar/missile designs (Citadel 1.03, Sea Spear 1.06, Dragon Tooth 1.08) are strong against sieges and clumps but weak against a charge (minimum range, reload windows) — exactly the bible's descriptions. The mean of the eight is 1.43 (band 1.30-1.65). **Artillery outranges every defence** (howitzer 15 vs AT turret 8; missile artillery 17 vs Lance 14; naval bombard 20): two howitzers destroy turret + watchtower without loss.

**Structure kill times** (4,500-HP Factory):

| attackers | cost | seconds to kill a 4500-HP Factory |
| :--- | ---: | ---: |
| 4 x mbt_t1 | 3400 | 16.2 |
| 8 x mbt_t1 | 6800 | 8.0 |
| 12 x mbt_t1 | 10200 | 5.6 |
| 6 x mbt_t2 | 7500 | 8.1 |
| 4 x siege_he | 9600 | 3.9 |
| 4 x arty_howitzer | 5200 | 22.6 |
| 4 x arty_missile | 5800 | 29.8 |
| 12 x inf_line | 3000 | 60.2 |
| 2 x air_bomber | 3800 | 46.6 |

### 5.8 Economy constants

**Collector cycle** (all integers at load: capacity 600, harvest 1 credit/tick = 20 credits/s → 600 ticks to fill, unload 6 credits/tick → 100 ticks, 40 ticks docking overhead, speed 102 units/tick):
`cycle_s = 30 + 5 + 2 + 2 × distance_cells / 2.0 = 37 + distance_cells`

| deposit-refinery distance (cells) | cycle s | credits/min per collector |
| :--- | ---: | ---: |
| 6 | 43.0 | 837 |
| 8 | 45.0 | 800 |
| 10 | 47.0 | 766 |
| 12 | 49.0 | 735 |
| 16 | 53.0 | 679 |
| 20 | 57.0 | 632 |
| 24 | 61.0 | 590 |
| 32 | 69.0 | 522 |

| quantity | value |
| :--- | :--- |
| Collector purchase payback | 1.8 min |
| Refinery + free collector payback | 2.4 min |
| Expansion total (MCV+refinery+2 collectors+gen+turret+tower) | 9450 cr -> 2298 cr/min, payback 4.1 min |
| Standard field (24 cells x 600) | 14400 cr, 6.3 min for 3 collectors |
| Full repair of any land vehicle | 50 % of paid price, 100 s |
| Salvage of a 850-credit tank wreck | 170 cr for 8 s |

* **Income per collector: 766 credits/min at the 10-cell reference distance** (837 at 6, 632 at 20, 522 at 32). One unload slot per refinery; at 3 collectors the slot is busy 32 % of the time, so 3 collectors per refinery scale almost linearly; beyond 3 the timeline model credits 60 % per extra collector (the AI and the tests use 3).
* **Payback:** Collector (1,400) 1.8 min; Refinery + its free Collector (1,800) 2.4 min; a full expansion needs an MCV (3,000) because buildings must sit inside an HQ's 8-cell radius (bible): MCV + Refinery + 2 Collectors + Generator + AT turret + Watchtower = **9,450 credits → +2,298 credits/min, payback 4.1 min**.
* **Deposits:** cells hold 600 credits (rich 1,200); a standard field is 24 cells = 14,400 credits, a rich field 16 cells = 19,200; a load of 600 empties exactly one cell; finite, no regrowth. Three collectors drain a standard field in 6.3 min, which forces the first expansion at ~10-12 min. Map budget per player: 75,000 (min) – 110,000 (target) reachable credits: 2 standard start fields (28.8k) + a natural expansion of 1 standard + 1 rich (33.6k) + 2 more standard fields (28.8k) + a share of 2 contested rich centre fields (38.4k). Finite deposits, not the clock, end matches at 20-35 min.
* **Opening arithmetic** (serial construction queue, bible costs/times): Generator 0:25 (600) → Refinery 1:05 (1,800) → Barracks 1:25 (500) → Factory 2:05 (2,000) → Radar 2:35 (1,500) = 6,400 credits; the remaining 1,100 + the first collector's income pay for one scout + one tank by ~3:00. A tech opening (skip Barracks) reaches Radar at 2:15.
* **Salvage (African Empire):** 20 % of paid price, 8 s uninterrupted, wreck 60 s (bible). A 850-credit tank wreck pays 170. Track salvage as a share of total income: target ≤ 10 %, alert at 15 % (§5.17 snowball check); the lever is the payout percentage, never unit stats (bible priority 5).
* **Repair:** Engineer repairs 1 %/s of maximum HP for 0.5 %/s of paid price → a full repair from 0 % costs 50 % of the price and takes 100 s; cost per hit point = 0.5 × price / max HP (a 1,000-HP, 850-credit tank costs 0.425 credits/HP). AE −25 % applies to land-vehicle repairs only.
* **Sell refund** 50 % of paid price; **build radius** 8 cells (bible); **unit cap** 150 non-structure entities (Collectors, MCVs, summons, decoys, carrier drones exempt); **queue length** 5 with cancel refunding spent credits; **power shortage** slows production and research to 50 %.
* **Production throughput:** a Barracks absorbs 1,680 credits/min, a T1 Factory 1,860, a T2/T3 Factory 2,040/2,280, an Airfield or Dock 2,160; one Refinery with 3 Collectors earns 2,298/min, so one Refinery feeds ~1.2 Factories. Additional producers add queues, not speed (bible).


### 5.9 Power balance per structure set

Bible: Generator +150; consumers Refinery −30, Barracks −10, Factory −40, Dock −35, Radar −40, Airfield −40, Laboratory −60, Watchtower −5, AT turret −15, AA battery −20, advanced defence −40, superweapon −200, Relay −20. Rule: **generators = ceil(draw × 1.10 / (150 × output multiplier))**; the 10 % headroom keeps a single lost Generator from stopping production.

| set | structures | draw | generators | supply | generator cost |
| :--- | :--- | ---: | ---: | ---: | ---: |
| opening | refinery, barracks, factory | 80 | 1 | 150 | 600 |
| plus_radar | refinery, barracks, factory, radar | 120 | 1 | 150 | 600 |
| tech_base | refinery, barracks, factory, radar, airfield, laboratory | 220 | 2 | 300 | 1200 |
| mid_base | refinery x2, barracks x2, factory x2, radar, airfield, laboratory, at_turret x2, aa_battery x2 | 370 | 3 | 450 | 1800 |
| late_base | refinery x3, barracks x2, factory x3, dock, radar, airfield x2, laboratory, defenses x6, superweapon | 795 | 6 | 900 | 3600 |

* A base at the *plus_radar* stage is exactly one Generator (120 of 150); the *tech_base* needs the second Generator **before** the Laboratory (−60 pushes 160 → 220). The superweapon alone draws 200 = 1.33 Generators (800 credits, 16 % of its price) and must not be added to a base at < 10 % headroom (charging pauses in a shortage, bible).
* Shortage (supply < draw): production and research at **50 %** speed (bible), powered defences and Relay bonuses stop (SAP reserve 20 s, 35 s with Reserve Capacitors, recharges after 60 s of adequate power), superweapon recharge pauses, existing units and completed upgrades work. Losing 1 of 2 Generators at *tech_base* (300 → 150 against 220) halves the whole economy of production: this is the intended raid target (Generator 1,200 HP, `building_light`).
* Modifiers: OLM Generators 150 × 1.25 = 187.5 → **188**; Saudi 1.25 × 1.20 = 1.50 → **225**; SAP India Generator cost −10 % → 540. The bible's power numbers are never rebalanced.

### 5.10 Pacing targets

Windows are measured from match start with the bible start (deployed HQ, 7,500 credits, medium speed, no veterancy). *Physical lower bound* = the pure production chain with unlimited credits (Generator 25 + Refinery 40 + Factory 40 + Radar 30 s …). *Fastest plan* = at least one of the four scripted plans must reach the milestone by this time; *balanced plan* = the stated time for the plan that keeps building army while teching.

| milestone | physical lower bound | fastest credible plan must reach it by | balanced plan must reach it by |
| :--- | ---: | ---: | ---: |
| first infantry squad | 1:30 | 1:45 | 2:20 |
| first scout (T1 APC) | 2:00 | 2:30 | 3:00 |
| first T1 tank | 2:15 | 3:35 | 5:30 |
| Radar complete (T2 gate) | 2:10 | 2:45 | 4:00 |
| first mobile AA | 2:45 | 5:50 | 7:00 |
| first siege (artillery) | 2:55 | 9:00 | 9:20 |
| Laboratory complete (T3 gate) | 3:05 | 5:00 | 9:00 |
| first T3 heavy tank | 4:10 | 12:20 | 12:40 |
| first fighter | 3:50 | 7:20 | 8:00 |
| Airfield complete | 3:20 | 4:20 | 12:40 |
| superweapon structure complete | 4:35 | 7:10 | 11:40 |
| first superweapon shot (structure + 480 s recharge) | 12:35 | 18:10 | 20:40 |

Timeline produced by the four scripted plans in `targets.pacing.plans` (serial construction queue, every queue pulls credits at once and pauses at 0 credits, collectors start earning 8-12 s after completion; `balance_calc.py pacing`):

| milestone | army_rush | balanced | tech_rush | air_rush |
| :--- | ---: | ---: | ---: | ---: |
| first infantry squad | 1:33 | 1:33 | - | - |
| first scout (T1 APC) | 2:22 | 2:22 | 4:32 | 2:07 |
| first T1 tank | 3:04 | 4:11 | 5:43 | 7:05 |
| Radar complete (T2) | 5:55 | 2:37 | 2:23 | 2:14 |
| first mobile AA | 8:12 | 6:33 | 7:30 | 5:39 |
| first siege (artillery) | 9:18 | 8:32 | - | - |
| Laboratory complete (T3) | 9:21 | 8:22 | 4:31 | 6:58 |
| first T3 heavy tank | 12:33 | 11:43 | - | - |
| first fighter (T2 air) | - | - | - | 7:05 |
| Airfield complete | - | 12:08 | - | 4:04 |
| superweapon structure complete | 12:06 | 11:20 | 6:59 | 9:37 |
| first superweapon shot (structure + 480 s recharge) | 20:06 | 19:20 | 14:59 | 17:37 |

* **First scout ≈ 2:07-2:22, first tank ≈ 3:04 (army-first) … 4:11 (balanced) … 5:43 (tech rush)**, Radar ≈ 2:14-2:37 for every non-army plan (5:55 when the plan delays it), first mobile AA ≈ 5:39 (air-aware plan) … 8:12, first siege (howitzer) ≈ 8:32-9:18, Laboratory 4:31 (tech rush) … 9:21, first T3 tank ≈ 11:43-12:33, **superweapon structure 6:59 (tech rush) … 11:20 (balanced), first shot 14:59 … 19:20** (structure + 480 s recharge; Aurora 420 s and Trident 360 s shift that by −60 / −120 s). A 20-35-minute match therefore sees 1-3 shots per superweapon owner, matching the bible's "decision" design.
* **What 7,500 credits buys at t = 0**: the five-building chain to Radar costs 6,400 and finishes at 2:35 (serial queue), leaving ≈ 1,100 + first-collector income for one scout and one tank. The player therefore chooses between more collectors (each 1,400 pays back in 1.8 min), an early army and Radar; nothing is free.
* **Seven rosters have no T1 tank** (bible priority 3): Canada (Narwhal), Eurocorps (Marte), Russia (Ural), China (Imperial Guard), Japan (Shinano), South Africa (Rhino), India (Arjun). Their first tank needs Radar (earliest 2:15) + build 37-42 s ≈ **3:00 earliest, ≈ 4:30 realistic**. Survival requirement (tested by BAL-2/BAL-3): a T1-only roster (infantry, AT team, APC, one boat, AT turret, Watchtower) must hold a 3-tank + 2-rifle push (3,050 credits) at 3:30 with ≤ 2,800 credits (0.92 × the attacker's spend) of its own T1 units and defences: 4 AT + 3 rifles + scout (2,700) or 3 AT + 2 rifles + AT turret + Watchtower (2,800) — model result: attackers 0 alive, defenders 2 alive; 3 AT + 2 rifles + turret (2,350) or 2 AT + 2 rifles + turret + tower (2,450) lose. Compensation for the delayed tank is the T2 tank's premium (+0.28 vs T1 at equal cost) and, for Narwhal/Shinano, amphibious reach.
* **First-timing measurement points** (for BAL-3): first scout = first completed unit with tag `scout`; first tank = first completed `tank` (T1 or the roster's T2 replacement); first mobile AA = first `anti_air` ground vehicle; first siege = first `artillery` or `siege` vehicle; first superweapon = tick of the first `SUPERWEAPON_FIRED` event.

### 5.11 Superweapons and support powers

Bible-fixed timings and geometry (asserted): 

| superweapon | recharge s | warning s | source |
| :--- | ---: | ---: | :--- |
| atlas | 480 | 10 | bible |
| aurora | 420 | 8 | bible |
| helios | 480 | 10 | bible |
| perun | 480 | 10 | bible |
| tempest | 480 | 10 | bible |
| dragonfall | 480 | 10 | bible |
| horizon | 480 | 10 | bible |
| trident | 360 | 6 | bible |

All superweapon structures: 5,000 credits, 90 s, −200 power, `fortress` armor, **7,000 HP** (designed: killing it inside the 6-10 s warning needs ≈ 700 effective DPS against `fortress` armor — about 15 T1 tanks, 5 he-siege tanks at 163 DPS each, or 7 heavy bombs of 1,078 — an army already at the gates, never a raid). Recharge starts at activation, one stored charge, starts empty, pauses in a power shortage, cancelled by destruction or EMP of the launcher during warning (bible).

**Damage per impact packet** (each rod, core, ring, drone hit, engine shot is one Trident packet). Cells show final damage at the packet centre (Helios: total over the sweep), % of a reference HP (squad 400, light vehicle 520, medium tank 900, T3 tank 3,600, light building 1,000, heavy building 4,500, fortress 7,000):

| packet | raw | radius | edge | infantry (400) | light_vehicle (520) | medium_armor (900) | heavy_armor (3600) | building_light (1000) | building_heavy (4500) | fortress (7000) |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Atlas rod x3 | 2400 kinetic | 2 | 50% | 960 (240%) | 1680 (323%) | 2400 (267%) | 3120 (87%) | 3120 (312%) | 3120 (69%) | 2400 (34%) |
| Perun core | 5200 he | 3 | 50% | 5200 (1300%) | 4420 (850%) | 3380 (376%) | 2600 (72%) | 5720 (572%) | 5200 (116%) | 3640 (52%) |
| Perun fragmentation ring | 400 he | 7 | 30% | 400 (100%) | 340 (65%) | 260 (29%) | 200 (6%) | 440 (44%) | 400 (9%) | 280 (4%) |
| Horizon impact x3 | 1300 kinetic | 3 | 50% | 520 (130%) | 910 (175%) | 1300 (144%) | 1690 (47%) | 1690 (169%) | 1690 (38%) | 1300 (19%) |
| Helios sweep | 620 DPS thermal | 1.5 (half-width) | - | 972 (243%) | 1814 (349%) | 1906 (212%) | 1925 (53%) | 2325 (233%) | 2790 (62%) | 2604 (37%) |
| Aurora pulse | 150 emp (non-lethal) | 8 | 100% | 0 | 150 | 150 | 150 | 150 | 150 | 150 |

* **Atlas** — 3 kinetic rods, 2,400 each, radius 2, ±3 cells along the axis (default east-west; the fire command carries an angle). Centre hit: 87 % of a T3 tank, 69 % of a Factory, 34 % of a fortress. Three overlapping rods centred on one 3×3 building deliver 3,120 + 2 × 1,950 = 7,020 → kills a Factory (4,500) with one shot; against `fortress` armor 2,400 + 2 × 1,500 = 5,400 leaves the HQ (6,000) at 10 % and 6,000 leaves the superweapon structure (7,000) at 14 %, so fortresses need two shots ("key buildings only with several hits"). Best-aim results: 12 T1 tanks fully killed, 6 heavies 94 % of value with 4 killed.
* **Aurora** — 8 cells, EMP 150 (non-lethal), enemy vehicles and aircraft lose weapons 8 s, powered enemy structures shut down 18 s, squads unaffected; bypasses Trident; enemies only (bible). Its value is disruption: a disabled 12-tank army loses 8 s × 1,400 DPS ≈ 11,000 damage of output.
* **Helios** — thermal spot 3 cells wide moving 16 cells in 12 s (1.333 c/s), 620 DPS. Dwell = `2 × (1.5 + radius) / 1.333` s: squad 2.9 s, medium tank 3.1 s, T3 tank 3.5 s, 3×3 building 4.5 s → 1,906 damage to a medium tank (dead), 1,925 to a T3 tank (53 %), 2,790 to a Factory (62 %). Units that leave the strip before the spot reaches them take nothing (it cannot track); Thermal Shrouds −10 % applies. Implementation: each tick the spot centre is `start + dir × (tick × 16 × 1024 / 240)`; targets whose edge distance ≤ 1.5 cells take `final_damage(31, …)` (620/20 per tick).
* **Perun** — core 5,200 `he` radius 3 (falloff to 50 %), ring 400 `he` radius 7 (falloff to 30 %). Centre: 116 % of a Factory, 72 % of a T3 tank, 52 % of a fortress; ring: kills squads, 65 % of light vehicles, 29 % of a medium tank, 9 % of a Factory — "punishes tightly packed support units", leaves buildings mostly intact.
* **Horizon** — three 1,300 `kinetic` impacts, radius 3, centres −5/0/+5 along the axis at t = 0 / 4.5 / 9 s (dodge-able: the marked line is visible), debris slows land vehicles to 65 % for 20 s and blocks new construction in the strip. A unit still inside all three circles takes ≤ 3 hits.
* **Tempest** — 24 drones (90 HP `air_light`, 8 c/s, `drone_missile` 60 per 2 s, range 4.5), attack window 20 s; maximum aggregate 14,400 raw damage. Shootable by ordinary AA; each drone hit is a packet. Sim results (8 T1 tanks, static, 20 s): 0 AA 100 % destroyed; 2 AA 69 %; 4 AA 32 %; 6 AA 18 %. An unescorted static army dies; a defended zone loses ~⅓.
* **Dragonfall** — 3 capsules (1,500 HP `heavy_armor`, killable during the 5 s unfold) → 3 engines (3,200 HP `heavy_armor`, 1.0 c/s, `siege_gun` 420 `he` per 3.5 s, splash 0.7, scatter 1.2, range 8, 60 s life). Sim: an undefended base (Factory, Refinery, Barracks, 2 Generators) is razed in 36 s with all 3 engines alive; against 8 T1 tanks the engines die in 12 s after destroying 34 % of the tanks' value, against 4 tanks + 4 AT teams in 17 s (40 % lost); AT teams alone lose 73 % (they need tanks to soak the engines' 9,600 HP). The engines' splash 0.7 / scatter 1.2 make them poor against small targets and excellent against 3×3 buildings — the bible's "surround the slow engines with anti-tank units".
* **Trident** — no damage. 24 charges, 25 s, radius 6; an ordinary missile, rocket or artillery shell crossing the boundary consumes 1 charge; a strategic packet consumes 8 and is reduced by 50 % (never cancelled; still capped with other resistances); beams, bullets, EMP, units inside, shots from inside bypass. Packets per activation: Atlas 3 (= all 24 charges), Perun 2, Horizon 3, Tempest one per drone hit, Dragonfall one per engine shot.

| superweapon (best aim) | tight base (12 bldgs, 1-cell gaps) credit value (kills) | dispersed base (4-cell gaps) credit value (kills) | 12 T1 tanks blob credit value (kills) | 6 T3 heavies blob credit value (kills) | 20 rifle squads blob credit value (kills) |
| :--- | ---: | ---: | ---: | ---: | ---: |
| atlas | 4500 (2) | 3100 (2) | 10200 (12) | 13604 (4) | 5000 (20) |
| perun | 3465 (2) | 2522 (1) | 10200 (12) | 9504 (0) | 4924 (19) |
| helios | 2300 (4) | 1233 (2) | 8500 (10) | 7010 (0) | 4000 (16) |
| horizon | 2300 (4) | 1345 (2) | 10200 (12) | 8378 (0) | 4881 (14) |

| Tempest 24 drones, 20 s | ground value destroyed | drones alive |
| :--- | ---: | ---: |
| Tempest vs 8 tanks + 0 AA | 100% | 24 |
| Tempest vs 8 tanks + 1 AA | 100% | 14 |
| Tempest vs 8 tanks + 2 AA | 69% | 0 |
| Tempest vs 8 tanks + 4 AA | 32% | 0 |
| Tempest vs 8 tanks + 6 AA | 18% | 0 |

| Dragonfall 3 engines | defender value destroyed | engines alive | duration |
| :--- | ---: | ---: | ---: |
| Dragonfall vs 8 tanks | 34% | 0 | 12s |
| Dragonfall vs 4 tanks + 4 AT infantry | 40% | 0 | 17s |
| Dragonfall vs 2 AT turrets + 6 tanks | 27% | 0 | 17s |
| Dragonfall vs undefended base (Factory, Refinery, Barracks, 2 Generators) | 100% | 3 | 36s |

**Budget rule.** Best-aim value of a superweapon on a tight 12-building base must fall in 2,000-8,000 credits with ≥ 2 kills, and it must devastate an *unmoving* 12-tank blob (≥ 75 % of 10,200 credits); the answer is the 6-10 s warning, so **damage escaped** is the balance lever, not raw damage. Measurement definition for the harness: `escaped = 1 − Σ(credit value × damage fraction) / potential`, potential computed on the zone at warning start; design targets: no reaction ≤ 10 %; reaction after 5 s of a 10 s warning 40-70 %; structures ≥ 90 % unavoidable.

**Support powers with damage** (bible: warning, area, duration; shell numbers are ours):

| support power | delivery | shell | raw total | warning s |
| :--- | :--- | :--- | ---: | ---: |
| Counterbattery Mission (NEC) | 6 shells over 4 s in r=4 | 320 he, splash 1.6 | 1920 | 5 |
| Tremor Barrage (DEF) | 4 waves x 6 shells over 8 s in r=5 | 260 he, splash 1.8 | 6240 | 6 |
| Counterlaunch Plot (SAP) | 3 shells per marked position (max 6), 0.6 s apart, zone r=8 | 260 he, splash 1.6 | 780 per mark | 5 |

Shells land at `SimRng` points inside the zone (Counterbattery/Tremor) or on the recorded positions (Counterlaunch). Damage-bearing area attacks hurt friendlies (bible). Repair/heal powers use the bible percentages directly.

### 5.12 Aircraft sortie economics

| aircraft | cost | HP | speed | weapon | dmg x hits | volleys/sortie | sortie raw dmg | rearm s | cycle s | sortie-avg DPS |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| air_fighter | 1100 | 700 | 7.0 | aa_missile | 100x1 | 6 | 600 | 8 | 20 | 30.0 |
| air_gunship | 2100 | 1500 | 4.5 | air_missile | 90x2 | 7 | 1260 | 12 | 34 | 37.1 |
| air_bomber | 1900 | 1100 | 6.0 | bomb | 700x1 | 2 | 1400 | 20 | 40 | 35.0 |
| air_drone | 1500 | 650 | 6.5 | air_missile | 150x1 | 4 | 600 | 14 | 28 | 21.4 |

* **Sortie state machine** (per aircraft): `IDLE_ON_PAD → LAUNCH → INGRESS → ATTACK (ammo_volleys > 0) → EGRESS (3 s exposed, fixed) → RETURN → REARM (pad, powered) → IDLE`. Hover units (gunship, strike drone) stop in `ATTACK`; fixed-wing units make a pass (bomber releases at range 1.5). Aircraft with 0 ammo leave; they do not fight until fully rearmed. No unlimited-ammo aircraft exist except unarmed jammers.
* **Rearm throughput.** One Airfield has 4 pads (+2 with USA's Dispersed Runways); each pad rearms one aircraft per `rearm_s_full` (fighter 8 s, gunship 12 s, drone 14 s, bomber 20 s; Condor 28 s). Aircraft sustainable per Airfield = `pads × sortie_cycle / rearm` = fighters 10, gunships 11, bombers 8, drones 8 (15/17/12/12 with 6 pads). Without a powered pad no rearm happens (bible).
* **Value targets (first sortie, 22 s window, vs 6,000 credits of T1 tanks):** unprotected gunships destroy 0.57 of their cost per sortie, bombers 1.05 (one pass, wide splash), strike drones 0.38; with AA equal to 15 % of the ground spend the aircraft lose 15-21 % of their value per sortie, with 30 % AA 31-51 % — the AA share that neutralises air is ~30 %, a nuisance level ~15 %:

| air group | AA share | AA | tanks | ground value destroyed | air value lost | destroyed/air cost | air loss share | alive |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| air_gunship x2 | 0% | 0 | 7 | 2380 | 0 | 0.57 | 0.00 | 2/2 |
| air_gunship x2 | 15% | 1 | 6 | 2410 | 714 | 0.57 | 0.17 | 2/2 |
| air_gunship x2 | 30% | 2 | 5 | 2440 | 2142 | 0.58 | 0.51 | 2/2 |
| air_gunship x2 | 45% | 3 | 3 | 2809 | 4200 | 0.67 | 1.00 | 0/2 |
| air_bomber x2 | 0% | 0 | 7 | 3981 | 0 | 1.05 | 0.00 | 2/2 |
| air_bomber x2 | 15% | 1 | 6 | 2587 | 587 | 0.68 | 0.15 | 2/2 |
| air_bomber x2 | 30% | 2 | 5 | 2100 | 1175 | 0.55 | 0.31 | 2/2 |
| air_bomber x2 | 45% | 3 | 3 | 3150 | 1762 | 0.83 | 0.46 | 2/2 |
| air_drone x3 | 0% | 0 | 7 | 1700 | 0 | 0.38 | 0.00 | 3/3 |
| air_drone x3 | 15% | 1 | 6 | 1758 | 923 | 0.39 | 0.21 | 3/3 |
| air_drone x3 | 30% | 2 | 5 | 2034 | 1500 | 0.45 | 0.33 | 2/3 |
| air_drone x3 | 45% | 3 | 3 | 2034 | 2423 | 0.45 | 0.54 | 2/3 |

* **Carriers.** A carrier owns 6 drones (150 HP `air_light`, 6 c/s, leash 14 cells, `drone_missile` 60 × 2 per 2 s); a lost drone is replaced in 14 s for 120 credits (bible leaves this unresolved; PD Integrated Flight Decks −15 %, Predictive Maintenance −20 % scale the time). Drones are not counted in the unit cap and are exempt from cost modifiers of "combat units" except `unmanned` ones (Han Emperor).
* Unarmed aircraft (Aster) jam sight −25 % in 5 cells; EMP never kills aircraft; aircraft cannot capture or hold ground.

### 5.13 Naval scale

| ship | cost | build s | HP | HP vs T1 tank | speed c/s | range cells | vision | radius |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ship_patrol | 600 | 16.5 | 700 | 0.8x | 3.2 | 6.5 | 11.0 | 0.6 |
| ship_escort | 1700 | 47.0 | 2200 | 2.4x | 2.4 | 10.0 | 11.0 | 1.0 |
| ship_siege | 3200 | 89.0 | 4500 | 5.0x | 1.6 | 20.0 | 10.5 | 1.3 |
| ship_carrier | 3800 | 105.5 | 5000 | 5.6x | 1.5 | - | 11.0 | 1.5 |
| ship_sub | 2600 | 72.0 | 2000 | 2.2x | 1.8 | 22.0 | 9.0 | 0.9 |

* HP relative to the T1 tank: patrol 0.8×, escort 2.4×, siege 5.0×, carrier 5.6×, submarine 2.2×. Speed 3.2 / 2.4 / 1.6 / 1.5 / 1.8 c/s (PD ships +15 %). Ranges: patrol 6.5, escort gun 9 / AA 10 / torpedo 7, siege bombard 20 (min 6), submarine torpedo 8 / cruise missile 22 (must surface 8 s).
* TTK anchors: patrol vs patrol 14-15 s, escort vs escort 24.8 s, siege ship vs escort 33 s (unopposed 30.6 s). Naval bombard outranges howitzers (15) by 5 cells; coastal defences (range ≤ 14) cannot answer it — aircraft, submarines and own ships do.
* **Map contract (ASSUMPTION(map)):** navigable channels ≥ 3 / 4 / 6 cells wide for small / medium / large hulls; ships with radius ≥ 0.9 are deep-water only; baseline economy never requires water (bible); the Landing Transport (900) carries 4 squads or 2 non-amphibious vehicles across deep water at 2.6 c/s.

### 5.14 Artillery ranges relative to vision

| archetype | range | own vision | range / vision | min range | deploy s | scatter | splash | blind band (range - vision) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arty_light | 11.0 | 9.0 | 1.22 | 3.0 | 0 | 1.0 | 1.4 | 2.0 |
| arty_howitzer | 15.0 | 8.5 | 1.76 | 4.0 | 3.0 | 0.9 | 1.6 | 6.5 |
| arty_rocket | 13.0 | 8.5 | 1.53 | 3.5 | 2.0 | 1.8 | 1.3 | 4.5 |
| arty_missile | 17.0 | 8.5 | 2.00 | 4.0 | 2.0 | 0.35 | 0.7 | 8.5 |
| ship_siege | 20.0 | 10.5 | 1.90 | 6.0 | 0 | 1.2 | 2.0 | 9.5 |
| ship_sub | 22.0 | 9.0 | 2.44 | 0 | 0 | 0.4 | 1.5 | 13.0 |

* Rule: **field artillery range / own vision ∈ [1.5, 2.1]**, light artillery [1.1, 1.4], naval bombardment [1.9, 2.4]. A howitzer sees 8.5 cells and shoots 15: it fires only at targets any friendly unit currently sees (bible: non-recon powers need vision; artillery uses the owner's shared sight). Spotter vision: scouts 12, observers 11-14 (Mirage/Watchpost with `good_sight`), Wedge fighter 13.8, UAV/drone powers 6-7-cell reveals, Nordics scouts and artillery +20 %.
* A spotter 6.5+ cells ahead of a howitzer covers its whole range; an unspotted howitzer is blind for `range − vision` = 6.5 cells. Minimum range 20-30 % of range (Citadel 5 of 16); deploy 1-3 s; shells land on the **fire-time position** of the target, so units moving faster than ~1 cell per flight (9 c/s shell, 1.7 s at 15 cells) dodge them.
* Counter-battery (bible: NEC Counterbattery, SAP Counterlaunch, AE Counterbattery Solution) works on artillery that fired in the last 8 s.

### 5.15 How faction passive modifiers enter the base numbers

**Policy.** (1) *Base numbers are neutral*: designers use the archetype curve with tags/abilities, never a pre-discount for a passive bible modifier — the resolver applies those (double counting is the main way factions drift). (2) The bible passives are nevertheless **not value-neutral** (DEF's −10 % cost/time on vehicles, NEC's +5 % cost on everything, Han's −15 % infantry cost …). `balance_calc.py modifiers` values every roster's package on a reference army and recommends a **60 % compensation** through base stats (never through cost or build time, which the bible shows to players): a faction-wide `power_offset_pct` (HP and damage of every combat unit by √(1 + offset)) and, for subfactions, an extra offset on the two unique units. (3) Residual asymmetry (max ±4.9 %) is intentional identity.

**Valuation** (`modifier_compensation.valuation`): reference army = the roster's units in 13 role slots weighted infantry-line 0.10, AT 0.08, specialists 0.04, scout 0.04, tank 0.25, AA 0.07, artillery 0.10, siege 0.10, fighter 0.05, air attack 0.08, patrol 0.02, escort 0.04, capital 0.04 (renormalised over the slots present). Per unit: `E = PI'/PI ÷ cost'/cost × (1 + 0.3 × (1/build' − 1))` with PI' from the modified HP, damage (÷ reload), range, speed and sight at the family exponents; aircraft rearm exponent 0.4, projectile speed 0.05; conditional modifiers weighted (on water 0.25, garrisoned 0.15, paid repairs 0.04); structure modifiers weighted by spend share (defences 0.08, generators 0.05, refineries 0.04, airfields 0.03). Index = Σ slot weight × (E − 1).

| roster | units % | structures % | economy % | raw index % | faction offset % | unique-unit offset % | residual % | removed unit |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| napc.vanilla | -2.6 | +0.0 | +0.0 | -2.6 | +1.5 | +0.0 | -1.1 | - |
| napc.usa | -0.1 | +0.0 | +0.0 | -0.1 | +1.5 | +0.0 | +1.4 | Bastion Heavy Tank |
| napc.canada | -1.1 | +0.0 | +0.0 | -1.1 | +1.5 | +0.0 | +0.4 | Titan Gunship |
| napc.mexico | +1.1 | +0.0 | +0.0 | +1.1 | +1.5 | +0.0 | +2.6 | Liberty Arsenal Ship |
| nec.vanilla | -4.8 | +0.0 | +0.0 | -4.8 | +3.0 | +0.0 | -1.8 | - |
| nec.nordics | -5.3 | +0.0 | +0.0 | -5.3 | +3.0 | +0.0 | -2.3 | Argent Rail Tank |
| nec.eurocorps | -7.2 | +0.0 | +0.0 | -7.2 | +3.0 | +6.5 | -1.8 | Aster EW Aircraft |
| nec.alpine_brotherhood | -3.8 | +1.4 | +0.0 | -2.4 | +3.0 | +0.0 | +0.6 | Concord Monitor |
| olm.vanilla | -1.3 | +1.0 | +0.0 | -0.3 | +0.0 | +0.0 | -0.3 | - |
| olm.saudi_arabia | -1.1 | +1.8 | +0.0 | +0.7 | +0.0 | +0.0 | +0.7 | Beacon Missile Ship |
| olm.algeria | -2.4 | +1.0 | +0.0 | -1.4 | +0.0 | +0.0 | -1.4 | Sunlance Beam Tank |
| olm.el_andalus | -2.2 | +1.0 | +0.0 | -1.2 | +0.0 | +0.0 | -1.2 | Sunlance Beam Tank |
| def.vanilla | +7.1 | +0.0 | +0.0 | +7.1 | -4.0 | +0.0 | +3.1 | - |
| def.russia | +4.8 | +0.0 | +0.0 | +4.8 | -4.0 | +0.0 | +0.8 | Burya Bomber |
| def.kazakhstan | +4.4 | +0.7 | +0.0 | +5.1 | -4.0 | +0.0 | +1.1 | Colossus Siege Tank |
| def.north_korea | +8.2 | +0.9 | +0.0 | +9.1 | -4.0 | -12.0 | +3.3 | Boreal Missile Submarine |
| pd.vanilla | +0.1 | -0.6 | +0.0 | -0.5 | +0.0 | +0.0 | -0.5 | - |
| pd.australia | -2.2 | -0.4 | +0.0 | -2.6 | +0.0 | +0.0 | -2.6 | Leviathan Assault Carrier |
| pd.indonesia | -0.7 | -0.6 | +0.0 | -1.3 | +0.0 | +0.0 | -1.3 | Tempest Carrier |
| pd.japan | -7.7 | -1.0 | +0.0 | -8.7 | +0.0 | +12.0 | -4.9 | Breaker Howitzer |
| han.vanilla | +2.4 | +0.0 | +0.0 | +2.4 | -1.5 | +0.0 | +0.9 | - |
| han.china | +0.2 | +0.0 | +0.0 | +0.2 | -1.5 | +0.0 | -1.3 | Silkwing Drone Bomber |
| han.vietnam | +0.9 | +0.0 | +0.0 | +0.9 | -1.5 | +0.0 | -0.6 | Dragon Command Walker |
| han.cambodia | +6.5 | +0.4 | +0.0 | +7.0 | -1.5 | -12.0 | +4.5 | Emperor Drone Ship |
| ae.vanilla | -0.5 | +0.0 | +0.8 | +0.3 | +0.0 | +0.0 | +0.3 | - |
| ae.nigeria | +4.5 | +1.0 | +0.8 | +6.3 | +0.0 | -12.0 | +4.1 | Kiln Assault Crawler |
| ae.kongo | -0.7 | +0.0 | +0.8 | +0.1 | +0.0 | +0.0 | +0.1 | Sovereign Arsenal Ship |
| ae.south_africa | -7.5 | +0.0 | +0.8 | -6.7 | +0.0 | +11.0 | -2.6 | Hammerhead Gunship |
| sap.vanilla | -1.0 | +0.6 | +0.0 | -0.4 | +0.0 | +0.0 | -0.4 | - |
| sap.india | +0.7 | +1.2 | +0.0 | +1.9 | +0.0 | +0.0 | +1.9 | Sarus Gunship |
| sap.thailand | -1.1 | +0.2 | +0.0 | -0.9 | +0.0 | +0.0 | -0.9 | Elephant Siege Tank |
| sap.pakistan | -0.3 | +0.6 | +0.0 | +0.3 | +0.0 | +0.0 | +0.3 | Citadel Monitor |

`raw index` = value of the bible package; `faction offset` = −0.6 × raw (vanilla roster, |raw| < 1.5 → 0, clamp ±4 %); `unique-unit offset` = −0.6 × (raw + faction offset) ÷ (weight of the two replaced slots), skipped below |3 %|, clamp ±12 %; `residual` = what remains. Apply with `propose --faction <f> --styled` / `proposals --styled` (offsets scale stats, not price).

The recommended offsets are the `faction offset` and `unique-unit offset` columns above; they are stored in `modifier_compensation.recommended` (re-derived by `balance_calc.py modifiers --emit`; `validate` fails when they are stale).

**Extremes after resolution** (sanity: no stat leaves 0.80-1.25× of base except through the bible's own numbers; floors 60/60/50 % are never hit):

| extreme over all 32 rosters x their combat units | unit | value |
| :--- | :--- | :--- |
| slowest ground unit | def.russia bear_siege_crawler | 0.86 c/s (base 1.06) |
| fastest ground unit | olm.algeria dune_rover | 4.39 c/s (base 4.0) |
| cost multiplier range | napc.usa raptor_multirole_fighter .. def.north_korea kite_interceptor | 0.8500 .. 1.2500 |
| build-time multiplier range | napc.mexico vanguard_rifle_squad .. nec.alpine_brotherhood kestrel_interceptor | 0.8000 .. 1.2000 |
| health multiplier range | olm.algeria dune_rover .. napc.canada beaver_amphibious_apc | 0.8100 .. 1.2100 |
| speed multiplier range | def.russia mule_apc .. def.kazakhstan line_conscript | 0.8100 .. 1.2000 |

### 5.16 How each bible rule in this domain is honored

| Bible rule | Honored by |
|---|---|
| `null` = unspecified, never zero/free/instant | every null cost/time/HP/damage is replaced by a designed value; `validate` asserts all bible-fixed numbers unchanged |
| Layer rule: add within layer, multiply across | §5.1 integer recipe, half-up per layer; worked examples in §5.4 |
| Floors 60 % cost / 60 % build time / 50 % reload | `max(acc, 6000/6000/5000)` before conversion; extremes table shows none reached |
| Combined resistance ≤ 50 %, interception exempt | `DefDamageMath.cap_resistance`; interception is projectile removal |
| No same-source stacking | resolver keys by `(source, stat)`; resistance sources named |
| Service units excluded from combat modifiers | `unit_assignments` service rows; selectors require the `combat` tag; compensation ignores them |
| Roles retained on replacement; replacement stats independent | `unit_assignments` per unit; unique units priced by the fair-cost formula (no copy of the replaced unit) |
| Tiers: T1 open, Radar → T2, Radar + Lab → T3; research 45/75 s | pacing windows and T1-only survival test; no framework change |
| Power shortage 50 % production/research; defences off; recharge pauses | `production.power_shortage_speed_pct`, §5.9 |
| Damage areas hurt friendlies; Aurora and summons pick enemies only | packets hit every entity in radius regardless of owner; Aurora/Tempest/Dragonfall flagged enemy-only |
| Strategic warning cannot be hidden; superweapons may target explored terrain; one charge; start empty; destruction/EMP in warning cancels | constants in `superweapons.common` and §5.11; combat/power domains own the state machine |
| Ordinary AA cannot intercept strategic attacks except Tempest drones | strategic packets `interceptable_by = none`; Tempest drones are `air_light` entities with 90 HP |
| Trident: 8 charges = −50 % per packet, cap applies, Helios/Aurora bypass | `superweapons.trident`, `*_packets` counts, group test on projectile kind |
| Suppression 3 hits/2 s/−25 %/3 s, only Fortress Guard and Watchtower fire | `ability_templates.suppression`, `suppressive_default=false`, Watchtower flagged |
| Portable cover 4 s/45 s/20 % bullet; shelters 25 % | `ability_templates.cover` + resistance sources (TAXONOMY §5) |
| Concealment: detector radius 5 (Watchtower 4, AA battery 5); firing/damage reveals | `detection` block, `camouflage` template |
| Transports carry 2 squads (Okapi 3, Leviathan 4, Landing Transport 4 or 2 vehicles) | `transport_capacity_squads`, `transport` template |
| Aircraft rearm only on powered Airfield pads; carriers replenish only own drones | §5.12 |
| EMP never changes ownership or kills aircraft | `emp` non-lethal type, Aurora template |
| Submarine: only anti-submarine weapons target it underwater; strategic blast still applies | layer sets (§ TAXONOMY 7); strategic packets skip the layer test |
| Wrecks last 60 s, only African salvage, none from friendly fire/summons | `economy.salvage`; unit cap and salvage exemptions |
| Engineer repair 1 %/s for 0.5 % of price/s | `economy.repair` (cost per HP = 0.5 × price / max HP) |
| Unmanned = Firefly, Nest/Reed, Swallow, Silkwing, Nightjar, carrier drones | ability `unmanned` (−3 % price), selector scope |
| One strategic structure per player; superweapon buildable only with Radar + Laboratory | structure block; pacing model |

### 5.17 Validation methodology for real-engine balance passes (from the bible's prototype priorities)

Every experiment runs headless through `BalHarness` (BAL-3) with fixed seeds, on a flat 96×96 map unless stated, and writes CSV + a markdown summary. Model values come from `balance_calc.py`; the harness must land within the stated tolerance or the *global.json constants* (never the bible) are retuned.

1. **TTK matrix (micro).** For each pair in `targets.ttk_unopposed_s` (26 rows): attacker vs stationary unarmed target of the target archetype at standard range; 20 repetitions with different `SimRng` seeds (only scatter varies). Pass: mean within ±12 % of the band centre and inside the band.
2. **Equal-spend armies (priority 4).** For every pair in `targets.rps_equal_cost.bands` plus 16 mixed compositions (60 % main body + 20 % AT + 10 % AA + 10 % scouts; infantry mass; artillery + screen; air + AA): buy 6,000 and 15,000 credits, place 24 cells apart with ±3-cell seeded jitter, 30 seeds. Metric: remaining-cost-share difference. Pass: mean inside the band and within ±0.15 of the model; standard deviation < 0.25 (otherwise the fight is chaotic and needs a design review).
3. **Reinforcements, repairs, travel (priority 4).** After fight 1, each side receives its next production wave from a producer 60 cells behind the front. `T_ready = queue ticks + build ticks + travel ticks`; `tempo_ratio = T_ready(A) / T_ready(B)` for mirrored spends. Pass: 0.8-1.25 for ordinary rosters, 0.7-1.3 for mobility rosters (OLM, Kazakhstan). Repairs: NAPC apron regains 24 % HP per 30 s of calm (1 %/s after 6 s), Engineer repair costs 50 % of price for 100 %.
4. **First timings (priority 3).** Run the four plans of `targets.pacing.plans` with scripted commands in an enemy-free sandbox; record the milestone ticks of §5.10. Pass: every milestone inside `windows_s` ±10 %. Repeat per roster; for the seven no-T1-tank rosters also run the T1-only survival fixture (3 tanks + 2 rifles at 3:30 vs their T1 set ≤ 2,800 credits): the defender must win.
5. **Snowball / salvage (priority 5).** 20 seeded AI-vs-AI games AE vs each other faction on 3 map families; log salvage credits ÷ total income at minutes 10/15/20. Pass: ≤ 10 % at minute 15; **alert at 15 %** → reduce `economy.salvage.payout_pct_of_paid_cost` (20 → 15 → 12), never weaken every unit; also `P(AE wins | AE wins the first big battle) ≤ 70 %`.
6. **Superweapon decision metrics (priority 6).** Scripted defender reacts after 0 / 3 / 6 / 10 s. Measure `escaped` (§5.11), Tempest drones killed vs AA in zone (≥ 70 % with 4 AA, ≤ 10 % with 0), Dragonfall assembly survival (defender with ≥ 8 tanks in range kills all capsules before the 5 s unfold; with ≤ 4 at least one engine assembles), Trident charges spent (median ≥ 20/24 against ≥ 6 artillery pieces over 25 s; exactly 24 for an Atlas), Helios dodge (units that leave the strip before the spot arrives take < 10 %). Every strategic weapon must show at least one branch where the defender's choice changes the outcome by ≥ 30 %.
7. **Passive-modifier audit.** Recompute `balance_calc.py modifiers` after every stat change; the harness round-robin below must not contradict the index by more than 3 points.
8. **Round robin.** 32 × 32 AI matches, 3 map families × 4 seeds; target win rate 42-58 % per roster (AI bias caveat: compare mirrored pairs). Correction order when a roster is outside the band in two consecutive runs: (1) its unique-unit base numbers (±5 %), (2) its `power_offset_pct` (±2 %), (3) economy constants that are *ours* (salvage payout, deposit size), (4) never the bible's typed modifiers.
9. **Statistics.** Report mean ± 95 % CI (1.96 σ/√n); a result is "confirmed" only with n ≥ 20 (armies) or n ≥ 10 (superweapon scenarios).
10. **Mapping to the bible's eight prototype priorities.** (1) first harness runs use the 8 vanilla rosters only and check that each owns, by T2, an anti-infantry unit (rifle), an AT answer (AT team), a detector (scout/APC), a mobile AA and a siege route (artillery or siege tank) — `unit_assignments` guarantees the archetypes, the harness confirms the timings; (2) equal-spend and first-timing runs repeat on the three map families (open land, constrained urban routes, mixed coast/river) with ≥ 2 exits per start and no mandatory water; (3) experiment 4; (4) experiments 2-3; (5) experiment 5; (6) experiment 6; (7) duplicate command fields, repair stations and decoy income stay disabled — enforced by the identical-source rule of §5.1 and by `economy.salvage` excluding decoys and summons; (8) every price, HP and reload in `global.json` is a *proposal* until BAL-3 has confirmed it; the framework is frozen (version bumped) only after two consecutive clean calibration runs.


---

## 6. Commands consumed / events emitted (names, integer codes, field meanings). You are the authority for those in your domain; flag what other domains must add

**Commands consumed: none. Events emitted: none.** (Event and command names below are ASSUMPTION(sim) proposals; the integer codes and field meanings are authoritative.) This domain is data plus pure functions; nothing in it ticks. What it *does* fix are the integer codes that other domains' commands and events must carry, and it flags three additions.

| item | owner of the message | codes/fields defined here (authoritative) |
|---|---|---|
| `EV_DAMAGE` payload | combat | `dtype` = `DamageType` 0-6, `armor` = `ArmorClass` 0-10, `amount` = final int from `DefDamageMath.final_damage`, `flags` bit mask: 1 `KILL`, 2 `RESIST_CAPPED` (Σres hit 50), 4 `NONLETHAL_CLAMP`, 8 `STRATEGIC`, 16 `SPLASH`, 32 `SUPPRESSIVE` (presentation picks hit effects from `dtype × armor`; damage numbers, resist-cap icons) |
| `EV_INTERCEPT` payload | combat | `by`: 0 APS (Ural/Arjun), 1 Trident; `charges_left` for Trident |
| `SUPERWEAPON_FIRE` command | command/power | fields `{x:int, y:int (sim units), angle:int 0..4095}`. `angle` is the axis of the 3-rod line (Atlas), the beam line (Helios) and the impact line (Horizon); default 0 (east); other superweapons ignore it. **The bible names a "player-selected line" for Helios/Horizon and "two points 3 cells to either side" for Atlas without an orientation; this request closes the gap.** |
| `sw_kind` | power | ATLAS 0, AURORA 1, HELIOS 2, PERUN 3, TEMPEST 4, DRAGONFALL 5, HORIZON 6, TRIDENT 7 (bible faction order); carried by `EV_SW_WARNING`, `EV_SW_PACKET{sw_kind, packet_index, x, y}`, `EV_SW_FIRED` |
| `EV_SALVAGE` | economy | `{x, y, amount}` for the income-share telemetry of §5.17 (snowball check) |

Flags to other domains (also in §13): the combat domain must emit the fields above; the command pipeline must add `angle`; production must give the Refinery a Collector queue.

---

## 7. Data files & schemas you need (paths, JSON shapes, one worked example entry each)

### 7.1 `game/data/balance/global.json` (this domain, written)

Top-level shape: §4.2. Worked entries (verbatim from the file; `movement_classes`, `economy.collector` and `superweapons.*` follow the tables of §5.8, §5.11 and TAXONOMY §8):

*Damage matrix row (`damage_matrix.ap`):*

```json
{
  "infantry": 40,
  "light_vehicle": 100,
  "medium_armor": 100,
  "heavy_armor": 90,
  "air_light": 100,
  "air_heavy": 85,
  "ship_light": 100,
  "ship_heavy": 100,
  "building_light": 65,
  "building_heavy": 60,
  "fortress": 40
}
```

*Reference unit (`archetypes.mbt_t1`):*

```json
{
  "family": "tank",
  "tier": 1,
  "producer": "factory",
  "size_class": "medium",
  "armor_class": "medium_armor",
  "movement_class": "tracked",
  "layer": "ground",
  "cost_credits": 850,
  "build_time_s": 27.5,
  "health": 900,
  "speed_cells_s": 2.0,
  "vision_cells": 9.0,
  "radius_cells": 0.55,
  "primary_target_class": "medium_armor",
  "power_exponents": {
    "hp": 0.5,
    "dps": 0.5,
    "range": 0.3,
    "speed": 0.2,
    "vision": 0.05
  },
  "weapons": [
    {
      "archetype": "tank_cannon",
      "damage": 140,
      "hits_per_volley": 1,
      "reload_s": 1.2,
      "range_cells": 7.0
    }
  ],
  "notes": "T1 medium tank: anchor of the whole framework.",
  "dps_ref": 116.7,
  "range_cells": 7.0
}
```

*Weapon archetype (`weapon_archetypes.tank_cannon`):*

```json
{
  "index": 3,
  "damage_type": "ap",
  "fire_mode": "direct",
  "projectile_kind": "shell",
  "projectile_speed_cells_s": 16,
  "homing": true,
  "targets": [
    "ground",
    "surface_water"
  ],
  "splash_cells": 0.5,
  "splash_edge_pct": 50,
  "scatter_cells": 0.0,
  "range_cells_band": [
    6.5,
    9.0
  ],
  "min_range_cells": 0.0,
  "reload_s_band": [
    1.0,
    1.6
  ],
  "turret_deg_s": 90,
  "interceptable_by": "none",
  "suppressive_default": false,
  "notes": "Standard direct-fire anti-armor gun. Homing (always hits a live target); 50% splash edge."
}
```

*Unit assignment with tags (`unit_assignments["unit.olm.sirocco_tank"]`; abilities and tier overrides appear in the listing of §7.4):*

```json
{
  "archetype": "mbt_t1",
  "tags": [
    "fast",
    "fragile"
  ],
  "abilities": []
}
```

### 7.2 Command-line contract of `tools/py/balance_calc.py` (importable; stdlib only)

```
python3 tools/py/balance_calc.py validate                     # gate: 11 checks, exit 1 on any failure (currently 0 failures)
python3 tools/py/balance_calc.py report                       # all tables of this document
python3 tools/py/balance_calc.py propose mbt_t1 --tags fast,fragile          # -> 820 credits, 765 HP, 2.5 c/s, build 26.5 s
python3 tools/py/balance_calc.py propose mbt_t1 --cost 700                    # HP and damage scaled linearly to a chosen price
python3 tools/py/balance_calc.py proposals --styled --faction def --csv       # every DEF unit with offsets applied
python3 tools/py/balance_calc.py resolve unit.def.ural_assault_tank roster.def.russia   # bible layering -> sim integers
python3 tools/py/balance_calc.py check sheet.json             # lint a designer sheet (list of unit sheets, §4.5)
python3 tools/py/balance_calc.py duel inf_at mbt_t1           # discrete 1v1
python3 tools/py/balance_calc.py modifiers [--emit]           # roster index + recommended offsets (JSON block for global.json)
```

Example output of `check` on a mis-priced sheet (`cost 600, health 1400, dps 150` for `mbt_t1`): `fair-cost deviation -50.1 % (limit +-8 %); cost_credits -29 % vs archetype (limit +-25 %); health +56 % vs archetype (limit +-30 %)`.

### 7.3 Files this domain needs from others (shape only; owners write them)

* `game/data/balance/<faction>.json` (8 files, faction designers; schema by data_balance): per unit the sheet of §4.5, per weapon the instance of §4.4, per structure `{id, health, armor_class, footprint, vision_cells, weapons[]}`, per research/power the ability parameters of §4.6. Every entry references bible ids and an `archetype`; lint-clean against `unit_assignments`.
* `game/data/bible/meridian_factions.json` (synced copy; read by `balance_calc.py` from `Input/` directly).

### 7.4 Unit → archetype assignments (`unit_assignments`, 156 rows; `[tags, +abilities, Tn = tier override]`)

The four service units use dedicated `service.*` rows with the bible's fixed costs (Engineer 500, Collector 1400, MCV 3000, Landing Transport 900).

* **ae**: anchor_escort=ship_escort; buffalo_tank=mbt_t1; civic_rifle_team=inf_line[+sensor]; delta_patrol_boat=ship_patrol; forge_howitzer=arty_howitzer[sturdy,short_range,+deployable_mode]; hammerhead_gunship=air_gunship; kiln_assault_crawler=siege_demo; lagos_drone_guard=veh_aa[+drone_repair]; mamba_apc=veh_scout; okapi_amphibious_carrier=veh_scout[fragile,+amphibious,+transport_3]; pike_team=inf_at[short_range]; protea_gun_carrier=arty_howitzer[+deployable_mode]; reclaimer=inf_combat_spec[+repair_aura,+salvage]; rhino_rail_tank=mbt_t2_rail; river_warden=inf_combat_spec[+camouflage,+repair_aura,+salvage]; sovereign_arsenal_ship=ship_siege[slow]; sunbird_interceptor=air_fighter; union_guard=inf_line; weaver_aa=veh_aa
* **def**: anvil_rocket_battery=arty_rocket[inaccurate]; bear_siege_crawler=siege_demo[slow,poor_sight,+frontal_armor]; boreal_missile_submarine=ship_sub; burya_bomber=air_bomber; colossus_siege_tank=siege_he; echo_team=inf_support[no_gun,+decoy,+spotter]; fortress_guard=inf_line[+suppressive_deploy]; hammer_tank=mbt_t1[poor_sight]; kite_interceptor=air_fighter[weaker_gun]; line_conscript=inf_line[fragile]; mule_apc=veh_scout[robust,slow]; picket_boat=ship_patrol[strong_gun]; porcupine_aa=veh_aa_flak; rampart_escort=ship_escort; recoil_team=inf_at[short_range,strong_gun]; saker_missile_truck=arty_missile[precise]; signal_officer=inf_support[no_gun,+spotter]; steppe_recon_carrier=veh_scout[fast,good_sight,fragile]; ural_assault_tank=mbt_t2[sturdy,+aps_interception]
* **han**: banner_infantry=inf_line[fragile]; canal_patrol_boat=ship_patrol; canopy_ranger=inf_line[+camouflage]; dragon_command_walker=veh_command; emperor_drone_ship=ship_carrier; firefly_aa_drone=veh_aa[fragile,+unmanned]; imperial_guard_tank=mbt_t2[precise]; jade_carrier=veh_scout[fragile]; jade_escort=ship_escort; lance_team=inf_at[alpha]; link_operator=inf_support[no_gun,+command_field]; long_command_walker=veh_command[+deployable_mode]; lotus_drone_tender=veh_scout[+repair_aura]; mekong_field_engineer=inf_support[no_gun,+command_field,+repair_aura]; nest_rocket_drone=arty_rocket[fragile,+unmanned]; ox_tank=mbt_t1; reed_rocket_skimmer=arty_light[fragile,alpha,+amphibious,+unmanned]; silkwing_drone_bomber=air_bomber[precise,slow_rearm,+unmanned]; swallow_interceptor=air_fighter[+unmanned]
* **napc**: aegis_frigate=ship_escort; aguila_breach_team=inf_combat_spec[armored,very_short_range,+breach_charge]; bastion_heavy_tank=siege_ap[slow]; beaver_amphibious_apc=veh_scout[weak_gun,sturdy,+amphibious]; combat_medic=inf_support[no_gun,+heal_aura]; condor_stealth_bomber=air_bomber[heavy_bomb,slow_rearm,+stealth]; falcon_interceptor=air_fighter; guardian_tank=mbt_t1; javelin_team=inf_at; liberty_arsenal_ship=ship_siege[long_range]; narwhal_amphibious_tank=mbt_t1[slow,weaker_gun,+amphibious,T2]; paladin_howitzer=arty_howitzer[+deployable_mode]; pathfinder_apc=veh_scout; raptor_multirole_fighter=air_fighter[weaker_gun,+multirole]; rifle_squad=inf_line; riverwatch_patrol_boat=ship_patrol; sentinel_aa=veh_aa; titan_gunship=air_gunship[sturdy]; vanguard_rifle_squad=inf_line[+cover_builder]
* **nec**: alpine_pioneer=inf_combat_spec[short_range,+cover_builder,+repair_aura]; archer_spg=arty_howitzer[precise,light_hull,+deployable_mode]; argent_rail_tank=siege_rail; aster_ew_aircraft=air_ew; charlemagne_siege_tank=siege_rail[+deployable_mode]; concord_monitor=ship_siege[precise,fragile]; fen_recon_carrier=veh_scout[weak_gun,+amphibious,+sensor]; fjord_missile_carrier=arty_missile[precise,+amphibious]; horizon_escort=ship_escort; ibex_crawler_gun=arty_howitzer[sturdy,short_range,+frontal_armor,+deployable_mode]; jager_squad=inf_line[light_hull]; kestrel_interceptor=air_fighter[quick_rearm]; leopard_tank=mbt_t1; marte_heavy_mbt=mbt_t2[sturdy,+frontal_armor]; rapier_aa=veh_aa[long_range]; sapper=inf_combat_spec[short_range,+cover_builder]; skerry_patrol_boat=ship_patrol[fast]; spike_team=inf_at[long_range]; surveyor_apc=veh_scout[quick]
* **olm**: beacon_missile_ship=ship_siege[long_range]; caravan_apc=veh_scout[quick]; corsair_patrol_boat=ship_patrol[fast]; crescent_aa=veh_aa; dawn_laser_aa=veh_aa_beam; dune_rover=veh_scout[fast,+camouflage]; gate_guard=inf_line[slow,+shield_front]; ifrit_prism_tank=siege_beam[strong_gun,+deployable_mode]; lantern_escort=ship_escort; mirage_observer=inf_support[no_gun,good_sight,+camouflage,+spotter]; needle_team=inf_at; nightjar_strike_drone=air_drone[+unmanned]; sandglass_mortar=arty_light[short_range]; scorpion_rocket_buggy=arty_light[fragile,alpha]; shrike_interceptor=air_fighter[quick,limited_endurance]; sirocco_tank=mbt_t1[fast,fragile]; strait_frigate=ship_escort[slow,strong_gun]; sunlance_beam_tank=siege_beam; wayfarer_guard=inf_line
* **pd**: breaker_howitzer=arty_howitzer[sustained,+deployable_mode]; harpoon_team=inf_at; island_raider=inf_line; kancil_landing_skimmer=veh_scout[fast,weak_gun,+amphibious]; leviathan_assault_carrier=veh_assault_carrier; osprey_strike_tiltrotor=air_gunship; outrider_howitzer=arty_howitzer[long_range,weaker_gun,+deployable_mode]; petrel_fighter=air_fighter[endurance]; ranger_marine=inf_line; reef_patrol_boat=ship_patrol[fast]; reef_technician=inf_support[no_gun,+repair_aura]; shinano_adaptive_tank=mbt_t1[+amphibious,+deployable_mode,T2]; shogun_drone_carrier=ship_carrier[+multirole]; storm_aa=veh_aa; tempest_carrier=ship_carrier; tide_tank=mbt_t1[+amphibious]; trident_escort=ship_escort; wake_skimmer=veh_scout[+amphibious]; wedge_recon_fighter=air_fighter[weaker_gun,good_sight]
* **sap**: arjun_assault_tank=mbt_t2[+aps_interception]; bulwark_tank=mbt_t1[slow]; citadel_monitor=ship_siege[slow,sturdy]; combat_pioneer=inf_combat_spec[+cover_builder,+repair_aura]; elephant_siege_tank=siege_he; estuary_patrol_boat=ship_patrol; gaj_siege_platform=siege_he[+deployable_mode]; garuda_interceptor=air_fighter[endurance]; jackal_apc=veh_scout[sturdy]; kavach_team=inf_at; monsoon_howitzer=arty_howitzer[+deployable_mode]; naga_amphibious_carrier=veh_scout[+amphibious,+smoke]; river_marine=inf_line; sarus_gunship=air_gunship[short_range]; shaheen_missile_battery=arty_missile[precise]; shield_escort=ship_escort; shield_rifle_squad=inf_line[sturdy]; vajra_aa=veh_aa; watchpost_recon_team=inf_support[no_gun,good_sight,+camouflage,+spotter]
* **shared**: collector=service.collector; engineer=service.engineer; landing_transport=service.landing_transport; mobile_construction_vehicle=service.mcv

---

## 8. Determinism notes (DR-x compliance; what enters the checksum)

* **DR-1/DR-10 — ints only.** `global.json` is human-friendly (floats for cells, seconds, cells/s). `DefBalanceGlobal.from_json_text` converts every value to an int **once** with the half-up/ceil recipes of §4.7 and never keeps a float; sim code only sees `PackedInt32Array` tables and `int` fields. The converted tables feed `data_hash` (FNV-1a-32 in fixed table order: matrix, group masks, nonlethal flags, armor layers, terrain speeds, size radii/turn/accel, resist cap, weapon-arch records, economy record) which joins the lobby data-version hash; a mismatch blocks the match.
* **DR-2 randomness.** The framework draws none. Weapon `scatter_cells` is consumed by the combat domain with `SimRng`: exactly two draws (dx, dy) per scattering shot, in ascending shooter entity id, before splash victims are enumerated; rejection sampling is bounded to 2 retries then clamps to the disc edge.
* **DR-3/DR-4.** No time, no float builtins. `DefDamageMath` uses only `int` operations; the numerator of `final_damage` is at most `10^4 × 6·10^4 × 200 × 100 × 100 = 1.2·10^15` (< 2^62). All divisions have non-negative operands (asserted), so truncation equals floor and the half-up form `(2n + d) / (2d)` is identical on every platform.
* **DR-6/DR-7.** Tables are arrays indexed by frozen enums (`index` fields in the JSON, not insertion order); the only dictionaries are load-time id→index maps, iterated in sorted-key order. No sorting is needed at runtime.
* **DR-9.** No global mutable state; `DefBalanceGlobal` is immutable after `from_json_text` and shared by reference between worlds.
* **Checksum.** This module contributes **only** the data hash (constants). It creates no world state. Rules defined here whose runtime state other domains must add to `SimWorld.checksum()` (DR-13): per-weapon `focus_ticks` (beam ramp), `ammo_volleys_left` and sortie state, `deploy` state/timer, timed-resistance sources (`expires_tick`), Collector load/cycle state, deposit cell credits, wreck timers, superweapon charge/warning timers and packet schedules, Trident `charges_left`, decoy/puck timers.
* **Python tooling** (`balance_calc.py`) is offline; it uses floats and iterates dictionaries in insertion order but produces identical output run-to-run (no randomness, no time); it is never linked into the game.

---

## 9. Performance budget (per-tick cost estimate with reasoning; worst cases; mitigations)

* **Hot path = one pipeline evaluation per hit** ≈ 6 integer multiplies, 1 division, 1 array read (`matrix_pct[dtype * 11 + armor]`). In GDScript ≈ 1.5-2.5 µs including the call.
* **Worst case (8 players × 150 entities, ≈ 800 armed):** average reload 26 ticks → ≈ 31 volleys/tick; splash weapons (≈ 35 % of volleys) average 3 victims → ≈ 55 evaluations/tick ≈ 0.12 ms; beam pulses (≤ 30 beam units, every 5th tick) ≈ 6/tick; superweapon frames (Tempest 24 drones, ≈ 12 hits/s) negligible. Budget: **≤ 0.25 ms/tick (0.5 % of the 50 ms tick)**; an entire Horizon/Perun packet touches ≤ 60 entities once → ≤ 0.15 ms in the frame it lands.
* **Memory:** matrix 77 ints, terrain 72, sizes 30, weapon archetypes 27 objects × 12 fields, economy 25 ints — < 8 KB; `global.json` parse ≈ 120 KB once at boot (< 30 ms).
* **Mitigations:** no allocation in `DefDamageMath` (static, ints only); the combat domain should pre-fetch `matrix_pct` row offsets (`dtype * 11`) per weapon at spawn; resistance sums are recomputed only when a resistance source starts/expires, not per hit.
* **Tooling cost (offline):** `balance_calc.py validate` ≈ 3 s, `report` ≈ 3.3 s on a laptop (pure Python engagement model, ≤ 60 units per side).

---

## 10. Test plan (unit / scenario / determinism / visual; concrete cases with expected values)

**Unit — `TestBalanceGlobal`** (loads `res://data/balance/global.json`):
* `damage_pct(AP, INFANTRY) == 40`, `(AP, HEAVY_ARMOR) == 90`, `(RAIL, AIR_LIGHT) == 0`, `(KINETIC, BUILDING_HEAVY) == 130`, `(BULLET, FORTRESS) == 6`, `(EMP, INFANTRY) == 0`; all 77 cells equal the JSON.
* `group_mask(AP) == GROUP_EXPLOSIVE`, `group_mask(THERMAL) == GROUP_BEAM | GROUP_THERMAL`, `is_nonlethal(EMP)`, not others.
* `terrain_speed(TRACKED, FOREST) == 55`, `(WHEELED, FOREST) == 0`, `(WHEELED, ROAD) == 130`, `(AMPHIBIOUS, DEEP) == 70`, `(NAVAL, ROAD) == 0`, `(AIR_FIXED, CLIFF) == 100`.
* `size_radius_units[MEDIUM] == 563`, `[INF] == 410`, `[SHIP_LARGE] == 1434`; `size_turn_per_tick[MEDIUM] == 85`.
* `weapon_arch_def(TANK_CANNON).projectile_speed_upt == 819`, `.splash_units == 512`, `.interceptable == NONE`; `weapon_arch_def(AT_MISSILE).interceptable == APS_TRIDENT`; `WEAPON_ARCH_COUNT == 27`.
* `eco.collector_capacity == 600`, `eco.collector_speed_upt == 102`, `eco.start_credits == 7500`, `eco.build_radius_units == 8192`, `eco.salvage_action_ticks == 160`, `eco.wreck_ticks == 1200`.
* Malformed inputs return `null`: matrix cell 201, missing armor key, duplicate index, `start_credits` 7400 (bible), Radar power −41.
* `data_hash` identical on two loads and (golden, recorded once) on macOS and Linux.

**Unit — `TestDamageMath`:** `final_damage(140, 10000, 100, 0, 100) == 140`; `(140, 10000, 100, 10, 100) == 126`; `(26, 10000, 30, 20, 100) == 6`; `(26, 11000, 100, 0, 100) == 29`; `(200, 10000, 100, 75, 100) == 100` (cap); `(1, 10000, 6, 0, 100) == 1`; `(2400, 10000, 130, 0, 50) == 1560`; `(x, y, 0, …) == 0`; `(26, 12650, 100, 0, 100) == 33` (Relay +10 % then +15 % in another layer); `splash_falloff_pct(0, 2048, 50) == 100`, `(512, 1024, 50) == 75`, `(1024, 1024, 50) == 50`, `(1025, 1024, 50) == 0`; `health_after(100, 150, true) == 1`, `(100, 150, false) == -50`; `ramp_bp(0, 100, 190) == 10000`, `(50, 100, 190) == 14500`, `(200, 100, 190) == 19000`; `flight_ticks(7168, 819) == 9`, `(x, 0) == 0`.

**Unit — `TestPercentMath`:** `layer_mul(10000, 1000) == 11000`; `layer_mul(11000, -1000) == 9900` (1.10 × 0.90 = 0.99, bible example); `apply_bp(850, 11000) == 935`; `seconds_to_ticks(27500, 10000) == 550`, `(27500, 11500) == 633`; `speed_to_upt(2000, 10000) == 102`, `(1800, 8100) == 75`; `cells_to_units(7000, 10000) == 7168`; `apply_floor_bp(5000, 6000) == 6000`; `deg_s_to_binary_per_tick(15000) == 85`.

**Golden resolver cases (`balance_calc.py resolve`, replicated by the data-domain resolver test):** Guardian@USA → 935 credits, 990 HP, 633 ticks, 102 upt; Ural@Russia → 1411 credits, 2116 HP, 756 ticks, 75 upt, reload 25 ticks; Condor@USA → 1636 credits, 1070 ticks, cycle 42.4 s; Dawn Laser AA@Saudi → damage bonus 11500 bp.

**Scenario tests (sim required):**
1. *Collector cycle:* Refinery + Collector, deposit 10 cells away, fixed path: one delivery every 941 ticks ±2 %; income over 5 min = 766 × 5 ± 3 %.
2. *Opening timeline:* commands Generator, Refinery, Factory, Radar (tech opening) with unlimited credits: Radar completes at tick 2,700 ± 20 (135 s); with 7,500 credits and Barracks in the chain, Radar at 3,100 ± 40 (155 s).
3. *Matrix in the world:* Guardian vs Guardian mirror kills in 154 ± 8 ticks (7.7 s); AT team vs stationary tank 288 ± 14 ticks (14.4 s: 4 missiles at 0/4.5/9/13.5 s + flight); rifle squad vs tank 1,144 ± 40 ticks (57.2 s).
4. *Resistance cap:* tank under Adaptive Plating + Steel Advance + Protected Advance + Dust Screen takes ≥ 50 % of a plain tank's damage from a direct `ap` hit.
5. *Superweapon packets:* Atlas centred on a 3×3 Factory kills it; on the HQ leaves 10 %; Perun core centred on a Factory kills it; Aurora leaves every target ≥ 1 HP; Helios at the reference line deals 1,906 ± 30 to a stationary medium tank.
6. *Sortie:* 2 gunships on 7 T1 tanks, no AA, 22 s: destroyed value 2,380 ± 300.

**Determinism:** same scenario twice ⇒ identical checksum chain; macOS ↔ Linux container identical `data_hash` and identical results of scenarios 1-6.
**Visual:** none in this domain; the UI domain's tooltip test must show "vs armor" percentages read from `damage_pct`.
**Python gate:** `python3 tools/py/balance_calc.py validate` must exit 0 (CI companion of `tools/gd check`); a golden diff of `balance_calc.py report` is committed with every framework change.

---

## 11. Work breakdown: agent-sized implementation tasks (each <= ~2500 lines of GDScript) with task id, files owned, dependencies on other tasks/domains, acceptance tests

| Task | Files owned | Depends on | Est. size | Acceptance |
|---|---|---|---|---|
| **BAL-1** Runtime constants & math | `game/src/data/def_balance_global.gd`, `def_weapon_arch.gd`, `def_economy_consts.gd`, `def_damage_math.gd`, `def_percent_math.gd`, `game/tests/test_balance_global.gd`, `test_damage_math.gd`, `test_percent_math.gd` | core (`Fp` helpers optional), data `GameData` wiring, `tools/gd` | ≈ 1,100 lines | All §10 unit cases pass; `tools/gd check` clean; malformed-input cases return null with named errors; two loads give the same `data_hash`; load < 30 ms |
| **BAL-2** Roster linter | `tools/py/balance_lint.py` (+ `tools/py/tests/test_balance_lint.py`) | data_balance faction file schema (ASSUMPTION), `balance_calc.py` | ≈ 700 lines Python | Passes for the output of `proposals --styled` on all 32 rosters; flags: fair-cost deviation > 8 %, stat outside tolerance band, bible-fixed number changed, missing assignment, weapon outside archetype bands, unarmed unit with weapons, roster residual index > 6 %, T1-only survival failure (uses the roster's real units in the engagement model) |
| **BAL-3** Real-engine harness | `game/tests/balance/bal_harness.gd`, `bal_scenarios.gd`, `game/tests/fixtures/balance/*.json`, `tools/py/balance_compare.py` (CSV vs model) | sim (combat, economy, production, power, vision), ai (scripted plans via `targets.pacing.plans`), BAL-1 | ≈ 1,800 lines | Reproduces §5.17 experiments 1-6 for the reference archetypes built from `global.json` within the stated tolerances; deterministic (two runs identical); writes CSV + markdown summary; runs headless in < 10 min |
| **BAL-4** Economy conformance | `game/tests/test_economy_constants.gd` | sim economy, BAL-1 | ≈ 350 lines | Scenario tests 1-2 of §10 pass |
| **BAL-5** Faction designer pass (8 parallel tasks, one per faction) | `game/data/balance/<faction>.json` | this framework, data_balance schema, BAL-2 | per faction | `balance_lint.py` clean; roster indices in ±6 %; each unit inside bands; notes explain every out-of-band choice |
| **BAL-6** Calibration loop | edits to `global.json` only (framework owner) | BAL-3 results | small | After every harness run, `validate` = 0, `report` diff reviewed, `version` bumped |

Sequence: BAL-1 ∥ BAL-2 → BAL-5 (needs BAL-2 and data_balance) → BAL-3 (needs sim/ai) → BAL-4 → BAL-6 repeated.

---

## 12. Risks, open questions and your recommended resolution for each

1. **The model is an expected-value 2-D abstraction.** Real fights have terrain, fog, turret traverse and micro. *Resolution:* the harness (BAL-3) is authoritative; only `global.json` constants are retuned (never the bible); bands are ±0.15 wide by design.
2. **Additive vs multiplicative resistance stacking is not spelled out by the bible** (only "cannot exceed 50 %" and "changes to the same stat add"). *Resolution:* additive with cap 50 (documented in TAXONOMY §5); switch would be a one-line change in `DefDamageMath.cap_resistance` callers.
3. **Bible passive packages are not value-neutral** (index −8.7 % … +9.1 %). *Resolution:* 60 % compensation through base stats, never cost/time (§5.15); if the round-robin disagrees, retune the factor in `modifier_compensation.factor`.
4. **Seven rosters have no T1 tank.** *Resolution:* T2 premium + amphibious; T1-only survival fixture is an acceptance test of every roster (§5.10).
5. **Damage granularity.** Small hits quantise modifiers. *Resolution:* ≥ 25 damage per hit rule; volleys cosmetic.
6. **Carrier drone price/replacement are unresolved in the bible** (`selector.unmanned_combat_units.unresolved_target_domain`). *Resolution:* 120 credits and 14 s per replacement drone; drones exempt from combat-unit modifiers except `unmanned` ones; flagged for the data architect.
7. **Superweapon orientation** is unspecified for Atlas/Helios/Horizon. *Resolution:* `angle` field on the fire command (§6); default east.
8. **Deposits/expansions depend on the map generator.** *Resolution:* per-player reachable credits 75,000-110,000 with the layout in §5.8; the map spec must provide two standard fields within 8-16 cells of each start.
9. **Refinery-produced Collectors** (bible producer = Refinery) need a queue that ARCH's queue list omits. *Resolution:* request to production (§13-4).
10. **Artillery vs fog.** The model assumes spotters; if spotting proves too laborious, raise `own_vision` of artillery by ≤ 10 % rather than range.
11. **Air is decisive against AA-free armies by construction** (first-sortie value 0.57-1.05). *Resolution:* AA share 15 % = nuisance, 30 % = neutralising (bands asserted); if AI turtles produce too little AA, raise AA attention in AI, not aircraft HP.
12. **Salvage snowball** (bible priority 5). *Resolution:* payout lever 20 → 15 → 12 %, alert 15 % of income; never nerf unit stats.
13. **Bible ambiguity: Okapi (3 squads) and Leviathan (4 squads) vs "combat transports normally carry two".** Implemented as written; flagged only.
14. **Armor class `light_vehicle` ≠ bible tag `light`** (self-propelled howitzers are thin-skinned but not "light"). *Resolution:* both stored; selectors use tags, the matrix uses armor class (documented in TAXONOMY §3).
15. **Unit cap 150 with infantry-rich Han/Mexico/Nigeria/NK** can bind at ~25 min. *Resolution:* accepted (bible: 150 entities); revisit with a population-weight option only if the harness shows the cap deciding games.

16. **Assumptions about other domains (tagged).** ASSUMPTION(data): GameData boots `DefBalanceGlobal` first and hashes it. ASSUMPTION(data_balance): faction sheets carry `archetype`, follow §4.4/§4.5 and keep `unit_assignments` beside them. ASSUMPTION(map): every tile maps to one `TerrainKind`, deposits follow §5.8, channels follow §5.13. ASSUMPTION(combat): target scoring, event fields and the strategic-packet rules of §13-3. ASSUMPTION(production): the Refinery gets a Collector queue. ASSUMPTION(ai): opening scripts may be read from `targets.pacing.plans`. ASSUMPTION(power): `SUPERWEAPON_FIRE` carries `angle`. If any of these is rejected by its owner, the affected constant in `global.json` (not the bible) is adapted.

---

## 13. CROSS_MODULE_REQUESTS (numbered; the exact API/field/event/command you need from other domains)

1. **data (GameData):** construct `DefBalanceGlobal.from_json_text()` first; expose it as `GameData.balance`; add `DefBalanceGlobal.data_hash` to the lobby data-version hash; fail loading if the bible-fixed numbers in `global.json` disagree with `game/data/bible/`.
2. **data_balance / resolver:** implement the bible layering exactly as §5.1 using `DefPercentMath` (per-layer half-up, floors 6000/6000/5000, final ceil/half-up conversions); keep `weapon_damage` as `bonus_bp` (do not bake); resolve `selector.thermal_beam_weapons` (damage type `thermal`) and `selector.ordinary_guided_missiles` (projectile kind `missile`, `interceptable_by = aps_trident`); honor `targets_override` on weapon instances; keep `unit_assignments` beside the faction files for the linter.
3. **combat:** use `DefDamageMath.final_damage` for every hit; carry `fire_mode`, `interceptable`, `suppressive`, `homing`, `scatter`, `ramp`, `deploy_s`, `ammo_volleys` from the weapon instance; target selection score `(matrix_pct/10 bucket desc, distance asc, entity id asc)` among legal targets so AT teams do not waste missiles on squads; direct fire always hits a living target, ballistic fire lands on the fire-time position (§5.2); implement the beam ramp, the EGRESS exposure of 60 ticks, non-lethal clamp, Helios moving-spot rule (§5.11), Trident charges, APS; emit `EV_DAMAGE` with the fields of §6; **strategic packets skip the layer test** (hit submarines) and are never interceptable except by Trident.
4. **production:** give the Refinery a production queue for Collectors (bible `producer_structure_id = refinery`); queue length 5, cancel refunds spent credits; power shortage multiplies production **and** research speed by 50 %; MCV and Collector build times from `service_units`; enforce `unit_cap` with the exemptions of `economy.unit_cap.exempt`.
5. **economy:** implement the integer collector cycle of §5.8 (harvest pulse, unload pulse, overhead, single unload slot, nearest non-empty cell with lowest-index tie-break); finite deposits; salvage 20 %/8 s/60 s AE only; repair cost `0.5 × price / max HP` credits per HP; sell refund 50 %; emit `EV_SALVAGE`.
6. **power:** shortage rule (50 % speed, defences and Relay off, SAP reserve exception, superweapon recharge pause); `SUPERWEAPON_FIRE {x, y, angle}` plus `sw_kind`; superweapon structure HP 7,000 `fortress`; charging only with power and intact Radar + Laboratory.
7. **movement:** consume `terrain_speed_pct`, `size_classes.turn_deg_s`, `movement_defaults.accel_ticks`, `deep_speed_pct` per-unit override, deep-water restriction for radius ≥ 0.9 hulls; Horizon debris multiplier 65 % for land vehicles.
8. **map:** map every terrain tile to a `TerrainKind`; provide two standard deposit fields (24 cells × 600) within 8-16 cells of each start, a natural expansion (1 standard + 1 rich), further fields and contested rich centre fields per §5.8; navigable channels ≥ 3/4/6 cells; ≥ 2 exits per start; baseline economy never on water.
9. **vision:** default vision by role from `vision_defaults_cells`; detector radius 5 (Watchtower 4, AA battery 5); artillery may fire at anything any friendly unit currently sees.
10. **ai:** use `targets.pacing.plans` as opening scripts and `economy.derived.collectors_per_refinery_recommended = 3`; keep AA spend around the 15-30 % thresholds when enemy air exists; keep power headroom ≥ 10 %.
11. **qa:** add `python3 tools/py/balance_calc.py validate` to the CI/gate next to `tools/gd check`; store the golden `report` diff; schedule BAL-3 nightly.
12. **ui:** tooltips read `DefBalanceGlobal.damage_pct` to show effective damage per armor class; sidebar cost/time shows the resolved integers (never base).
13. **command pipeline:** add `angle:int` (0..4095) to the superweapon fire command and validate `sw_kind` against the player's roster.
14. **view/audio:** hit effects keyed by `(dtype, armor)`; non-lethal EMP uses a distinct effect; strategic packets flagged `STRATEGIC`.
