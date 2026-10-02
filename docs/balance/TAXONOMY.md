# MERIDIAN FRACTURE — Balance Taxonomy (v1)

> **Authority.** This file is the final vocabulary authority for combat and movement (it supersedes ARCHITECTURE Appendix A, which seeded it).
> Every number here is mirrored in `game/data/balance/global.json` and enforced by `python3 tools/py/balance_calc.py validate`.
> Quantitative curves, budgets and formulas live in `docs/balance/FRAMEWORK.md`. Bible IDs and role tags are quoted from
> `Input/meridian_agent_reference/meridian_factions.json` and are never re-defined here.
> **Integer codes below are frozen**: they appear in replays, events and checksums. Append only; never renumber.

---

## 1. Design intent in one paragraph

Combat is a three-layer lookup: **weapon damage → (damage type × armor class) matrix → bible resistances (additive, capped at 50 %)**.
The matrix carries the rock-paper-scissors (RPS); resistances carry the bible's research/power/trait text; weapon archetypes carry
shape (range, reload, splash, scatter, projectile, ammo). A unit's *role archetype* (section 9) fixes which weapon archetypes and
armor class it uses, so one table answers "what is this unit good and bad against" for all 156 unit definitions.

---

## 2. Damage types (7)

| Idx | id | Resist groups (bit mask) | Weapons that use it | Non-lethal | Bible anchor |
|---:|---|---|---|:-:|---|
| 0 | `bullet` | `bullet` (1) | rifles, machine guns, autocannon, canister | no | "bullet" resistances: portable cover 20 %, shelter 25 %, Gate Guard front 25 % |
| 1 | `ap` | `explosive` (2) | tank cannons, AT/AA/air missiles, naval guns, torpedoes, missile artillery, drone missiles | no | "explosive" resistances: Adaptive Plating 10 %, Earthworks 20 %, Fieldworks 10 %, Sealed Compartments 15 % |
| 2 | `he` | `explosive` (2) | howitzer/mortar/rocket shells, bombs, flak, siege & demolition guns, grenades, cruise missiles | no | same group as `ap` |
| 3 | `thermal` | `beam` (4) + `thermal` (8) | Sunlance, Ifrit, Sunwall, Dawn laser AA, Helios | no | "thermal-beam" (Thermal Shrouds −10 %, Saudi +15 % damage); Adaptive Plating explicitly excludes "beam" |
| 4 | `rail` | `rail` (16) | Argent, Charlemagne, Rhino, Lance | no | Adaptive Plating excludes "rail" |
| 5 | `kinetic` | `kinetic` (32) | Atlas penetrators, Horizon mass driver (strategic only) | no | ARCH Appendix A "kinetic" |
| 6 | `emp` | `emp` (64) | Aurora (light damage + disable status) | **yes** | "normal EMP damage", "EMP never instantly kills an aircraft" |

**Why seven and not the six seeded in ARCH Appendix A.** The seed treated every shell, missile and rocket as one `explosive` type.
That cannot express three bible statements at once: *AT infantry do little damage to infantry* (Needle Team), *artillery and siege guns are the
anti-structure tool* (Elephant, Kiln, Paladin), and *rockets/missiles are what Adaptive Plating reduces*. The seed's `explosive` is therefore
split into two **warheads** (`ap`, `he`) that both belong to the single resist group `explosive`, so every bible sentence that says
"explosive damage" still applies to both. `beam` is not a separate type because every beam in the bible is thermal (Sunlance, Ifrit,
Sunwall, Dawn, Helios); `thermal` belongs to groups `beam` and `thermal`, so "beam" and "thermal-beam" rules both hit it. A plain `beam`
type is reserved for a future non-thermal beam and is deliberately not defined now (no dead rows).

**Group mask semantics.** A resistance source names one group; it applies to a hit iff `type.group_mask & source.group != 0`.
`Trident bypass` ("beams, bullets, EMP") is the same test on the projectile kind, not a damage-type rule (section 10).

**Rule for adding a type.** Add only when a bible sentence cannot be expressed by (type, group, weapon flag). Append the next index,
one matrix row of 11 integers, and bump `version` in global.json.

---

## 3. Armor classes (11)

| Idx | id | Layer | Members (examples) | HP scale |
|---:|---|---|---|---|
| 0 | `infantry` | ground | every infantry squad, Engineer | 260-546 |
| 1 | `light_vehicle` | ground | APC/scout chassis, Collector, Landing Transport, self-propelled artillery (Paladin, Archer, Anvil, Saker…), buggies, Reed | 480-1400 |
| 2 | `medium_armor` | ground | T1/T2 tanks, mobile AA, MCV (command walkers are `heavy_armor`) | 750-2100 |
| 3 | `heavy_armor` | ground | T3 tanks/siege tanks, crawlers, command walkers, Leviathan, Dragonfall engines/capsules | 3000-4400 |
| 4 | `air_light` | air | fighters, strike drones, UAVs, Tempest drones, carrier drones | 90-700 |
| 5 | `air_heavy` | air | gunships, bombers, EW aircraft, cargo aircraft | 900-1800 |
| 6 | `ship_light` | surface_water | patrol/river boats | 700 |
| 7 | `ship_heavy` | surface_water / underwater | escorts, monitors, arsenal ships, carriers, submarines | 2000-5000 |
| 8 | `building_light` | ground | Generator, Barracks, Watchtower, Relay | 900-1200 |
| 9 | `building_heavy` | ground | Refinery, Factory, Radar, Laboratory, Airfield, Dock, AT turret, AA battery, advanced defenses | 1500-5000 |
| 10 | `fortress` | ground | Headquarters, strategic (superweapon) structures | 6000-7000 |

Notes.
* **Not the bible role tag `light`.** The bible tag `light` (APC/scout chassis, Sandglass, Scorpion, Reed) is used by modifier selectors
  (`selector.light_land_vehicles`). Armor class `light_vehicle` is a stat-sheet property that also covers self-propelled howitzers (thin
  skinned, 650 HP). The two are independent; both are stored on the unit.
* **Bible "heavily armored aircraft".** Dawn Laser AA is "weaker against heavily armored aircraft": that is `air_heavy` (thermal 65 %
  vs `air_light` 95 %).
* **Decoys** (1 HP) use `infantry` for decoy tanks so any hit kills; they have no damage.
* **Garrisoned infantry** take no direct damage; the garrisoned civilian structure (`building_light`) does (see FRAMEWORK 5.16).

---

## 4. Damage matrix (integer percent)

Rows = damage type, columns = armor class of the **target**. `0` means "cannot damage" (rails and kinetic cannot damage aircraft; EMP cannot
damage infantry). Values above 100 are deliberate specialisations. The matrix is *armor*, not *resistance*: the 50 % cap does not apply to it.

| type \ armor | infantry | light_vehicle | medium_armor | heavy_armor | air_light | air_heavy | ship_light | ship_heavy | building_light | building_heavy | fortress |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| `bullet`  | 100 | 55 | 30 | 15 | 65 | 25 | 85 | 25 | 25 | 12 | 6 |
| `ap`      | 40 | 100 | 100 | 90 | 100 | 85 | 100 | 100 | 65 | 60 | 40 |
| `he`      | 100 | 85 | 65 | 50 | 60 | 45 | 85 | 60 | 110 | 100 | 70 |
| `thermal` | 55 | 100 | 100 | 90 | 95 | 65 | 100 | 90 | 100 | 100 | 80 |
| `rail`    | 20 | 100 | 115 | 125 | 0 | 0 | 100 | 110 | 60 | 65 | 55 |
| `kinetic` | 40 | 70 | 100 | 130 | 0 | 0 | 90 | 120 | 130 | 130 | 100 |
| `emp`     | 0 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |

### 4.1 Row reasons (why each weapon class is good or bad)

* **`bullet` — the anti-personnel row.** Full damage to squads (100), decent against thin-skinned vehicles (55) and unarmoured boats (85), and
  the only damage type ground infantry carry against light aircraft (65) — so massed rifles are a soft answer to drones, not to gunships (25).
  Falls off a cliff against armour (30/15) and structures (25/12/6): infantry cannot kill a base or a tank alone. This is the bible's
  "Rifle Squad: good against infantry, weak against armor".
* **`ap` — the anti-armour row.** 100 against every vehicle and hull (90 against heavy armour so T3 tanks are sturdier than raw HP suggests),
  but only 40 against squads (Needle/Javelin "little anti-infantry damage") and 60-65 against buildings (tanks can raze a base only by
  numbers). AA and air-to-ground missiles use `ap`; the 85 against `air_heavy` is the armoured-aircraft discount.
* **`he` — the area / anti-structure row.** 100 against squads, 110 against light structures and 100 against heavy ones (artillery is the bible's
  answer to defences and buildings), but only 65/50 against medium/heavy armour: howitzers hurt tanks a little, infantry blobs a lot.
  Flak (`he` airburst) uses the 60/45 air columns.
* **`thermal` — the sustained single-target row.** Almost flat 100 against vehicles and structures (a beam does not care what it burns), but
  only 55 against squads ("poor against infantry swarms") and 65 against armoured aircraft. The "excellent against slow targets" clause is
  **not** in the matrix: it is the weapon's *ramp* (`beam_thermal`: focus time on one target raises damage to 150-190 %); slow or stationary
  targets stay in the beam long enough to reach the ramp.
* **`rail` — the anti-heavy row.** 115-125 against medium/heavy armour and 110 against capital ships, weak against squads (20) and
  structures (60-65), cannot hit aircraft. Long range, no splash: "Argent Rail Tank: long-range armor killer, weak against infantry".
* **`kinetic` — strategic penetrator.** Reserved for Atlas and Horizon packets. 130 against heavy armour and buildings ("strongest against
  clustered heavy vehicles and key buildings"), 100 against fortresses, small against squads (40) because the penetrator wastes energy on soft
  targets (squads die anyway from the 2400 base damage).
* **`emp` — status weapon.** Applies its damage to everything except squads (0) and is **non-lethal**: it can never reduce health below 1,
  so "EMP never instantly kills an aircraft" holds for every class. The disable/shutdown durations are status parameters, not damage.

### 4.2 Column reasons (why each class exists)

| Column | Purpose in the RPS |
|---|---|
| `infantry` | The only class where bullets and `he` shine. Countered by artillery, siege guns and `he` splash; counter to AT teams (rifles beat AT by +0.72 in the equal-cost model). |
| `light_vehicle` | Scouts, APCs and artillery. Bullets still hurt (55), so rifles/MGs can raid artillery and Collectors; tanks delete them. |
| `medium_armor` | The standard tank. Bullets 30, `he` 65: it survives infantry fire and mild shelling; AT teams and `ap`/`rail` are the counters. |
| `heavy_armor` | T3 vehicles. Bullets 15 and `he` 50 make them nearly immune to infantry and artillery; only `ap` (90), `rail` (125), `kinetic` (130) and numbers kill them. Cheap AT teams still win by cost (+0.23 in the model). |
| `air_light` / `air_heavy` | Fighters/drones die to any AA and even rifles; gunships/bombers shrug off bullets (25) and need real AA. Rail and kinetic cannot touch either. |
| `ship_light` / `ship_heavy` | Boats fear bullets (85) but capital ships ignore them (25); torpedoes/naval guns (`ap` 100) and rails (110) sink them. |
| `building_light` / `building_heavy` | Soft targets for `he` (110/100) and `thermal` (100), armoured against bullets (25/12) and `ap` (65/60). |
| `fortress` | HQ and strategic structures: 70 % `he`, 40 % `ap`, 6 % bullets. A base breaker needs siege weapons or bombers; a 10-second warning cannot be beaten by ten tanks. |

### 4.3 Resulting RPS graph (equal-cost model, 6000 credits per side; see FRAMEWORK 5.6)

```
rifles  >> AT teams  >> tanks (T1/T2)  >  rifles          (hard, hard, soft)
AT teams >  T3 heavies   (cheap AT punishes concentration; he-siege variants beat AT by splash)
T2 tanks > T1 tanks;  T3 heavies > T1 tanks;  tanks >> unescorted artillery >> rifles blobs
AA vehicles >> fighters/drones/gunships (per cost); air >> any ground group without AA
```

---

## 5. Resistances and damage modifiers (bible text → pipeline)

**Pipeline (one rounding, half-up, minimum 1):**
`final = raw × bonus_bp/10000 × matrix_pct/100 × (100 − min(50, Σ res_pct))/100 × falloff_pct/100`

`bonus_bp` is the product of all *weapon damage* bonuses (Relay +10 %, Combined Arms Window +10 %, Saudi +15 % thermal, Island Raider +20 %…).
`Σ res_pct` is the **sum of every applicable resistance source**, capped at 50 (bible rule.design.caps_and_interpretation). Interception
(projectile removal by Ural/Arjun) is not a resistance and is exempt from the cap.

| Bible source | Effect | Encoding in a `ResistSource` (group, scope, pct) |
|---|---|---|
| Adaptive Plating (research) | land combat vehicles −10 % explosive; not beam/rail/bullet | group `explosive`, scope land combat vehicles, 10 |
| Thermal Shrouds | light land vehicles −10 % thermal-beam | group `thermal`, scope tag `light`, 10 |
| Sealed Compartments | Beaver/Narwhal −15 % explosive **while on water** | group `explosive`, condition `on_water`, 15 |
| Layered Fieldworks | combat infantry within 4 cells of a friendly defence −10 % explosive (no stacking between defences) | group `explosive`, aura 4 cells, 10 |
| Emergency Earthworks (power) | infantry and defences −20 % explosive for 15 s; not vehicles | group `explosive`, timed, 20 |
| Portable cover / Vanguard | +20 % bullet resistance while stationary behind cover | group `bullet`, state `behind_cover`, 20 |
| Alpine shelter | 25 % bullet resistance to occupants | group `bullet`, 25 |
| Gate Guard shield | 25 % less **frontal** bullet damage; not blasts or rear | group `bullet`, arc `front`, 25 |
| Dust Screen (power) | 30 % less **direct-fire** weapon damage inside the smoke, friend and foe; artillery/blasts unaffected | fire mode `direct` (all types), zone, 30 |
| Steel Advance (power) | land vehicles −20 % weapon damage for 12 s | all types, timed, 20 |
| Protected Advance (power) | infantry and land vehicles −15 % for 12 s | all types, timed, 15 |
| Emergency Fortification (power) | defences and production buildings −25 % for 15 s; not superweapon, not EMP | all types except `emp`, timed, 25 |
| Joint Landing / River Marine | −20 % weapon damage for 6 s after disembarking (no refresh by reboarding) | all types, timed, 20 |
| Trident strategic reduction | a superweapon packet with ≥ 8 charges spent: −50 %, still capped with the rest | all, packet flag, 50 |
| Suppression | movement −25 % for 3 s after 3 suppressive hits in 2 s | status, not damage |

*Stacking.* Sources of different names add; identical sources never stack (bible). Example: Adaptive Plating (10) + Steel Advance (20)
+ Protected Advance (15) = 45 → 45 % less explosive damage; adding Dust Screen (30) would reach 75 and is clipped to 50.

---

## 6. Size classes

| id | Radius (cells) | Turn °/s | Used by |
|---|--:|--:|---|
| `inf` | 0.40 | 720 | all squads |
| `light` | 0.45 | 240 | APC/scout, light artillery |
| `medium` | 0.55 | 150 | tanks, AA, howitzers |
| `heavy` | 0.80 | 90 | T3 tanks |
| `huge` | 1.00 | 60 | command walkers, Leviathan |
| `air_medium` | 0.50 | 180 | fighters, drones |
| `air_large` | 0.65 | 120 | gunships, bombers |
| `ship_small` | 0.60 | 120 | patrol boats, landing craft |
| `ship_medium` | 1.00 | 80 | escorts, submarines |
| `ship_large` | 1.40 | 45 | monitors, arsenal ships, carriers |
| `s1`..`s4` (structures) | 0.5 / 1.0 / 1.5 / 2.0 | – | footprints 1×1, 2×2, 3×3, 4×4 (Airfield 4×3 uses radius 1.75) |

Radius is the collision and splash-edge radius (`edge_dist = max(0, centre_dist − target_radius)`). Structure radius is the inscribed circle.
Ships with radius ≥ 0.9 cell are deep-water only; the map generator must provide ≥ 3 / 4 / 6-cell channels for small / medium / large hulls.

---

## 7. Layers and target sets

Entity layers (ARCH §Appendix A): `ground` (0), `air` (1), `surface_water` (2), `underwater` (3). A weapon lists the layers it may hit.
* **Who can hit air:** `small_arms`, `machine_gun`, `autocannon` (bullet matrix 65/25), `aa_missile`, `flak`, `beam_thermal` variants flagged AA,
  the escort AA missile. **Cannot:** tank cannons, siege guns, AT missiles (Harpoon/Sea Spear "never aircraft"), all artillery, rails, torpedoes.
* **Who can hit underwater:** only `torpedo` and `depth_charge` (bible: "only anti-submarine weapons can target them underwater, while
  strategic blast damage still applies" — strategic packets ignore the layer test).
* **Ships vs land:** naval guns and bombardment list `ground` and `surface_water`; submarines' cruise missiles hit `ground` only.

---

## 8. Movement classes and terrain

Terrain kinds (fixed order, index = column): `road` 0, `open` 1, `rough` 2, `forest` 3, `marsh` 4, `shallow` 5, `deep` 6, `cliff` 7.
The map module must map every concrete terrain tile to one of these kinds (ASSUMPTION(map)). Table values are percent of base speed; 0 = impassable.

| Movement class | Idx | Layer | road | open | rough | forest | marsh | shallow | deep | cliff |
|---|--:|---|--:|--:|--:|--:|--:|--:|--:|--:|
| `foot` | 0 | ground | 110 | 100 | 80 | 70 | 60 | 70 | 0 | 0 |
| `wheeled` | 1 | ground | 130 | 100 | 55 | 0 | 35 | 50 | 0 | 0 |
| `tracked` | 2 | ground | 105 | 100 | 80 | 55 | 55 | 65 | 0 | 0 |
| `amphibious` | 3 | ground | 105 | 100 | 75 | 50 | 80 | 90 | **70** | 0 |
| `naval` | 4 | surface_water | 0 | 0 | 0 | 0 | 0 | 80 | 100 | 0 |
| `submerged` | 5 | underwater | 0 | 0 | 0 | 0 | 0 | 0 | 100 | 0 |
| `air_fixed` | 6 | air | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |
| `air_hover` | 7 | air | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |
| `static` | 8 | ground | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

* `wheeled` "strong road mobility" (Mamba) = 130 on road, and forest is impassable. `amphibious` deep-water default 70 % matches the bible's
  PD Collector rule (70 % of land speed); Tide Tank ("slow movement on water") sets a per-unit `deep_speed_pct` override of 60.
  Bible water-speed bonuses (Canada +20 % on water, Nordics/Kongo +15/20 %) are modifiers on top of this table.
* Debris from Horizon: land vehicles −35 % for 20 s is a zone effect multiplying the table value.
* Shallow water is crossable by ground units at reduced speed (fords); only deep water needs an amphibious unit or a Landing Transport.

---

## 9. Role archetypes (32) and bible role tags

An archetype = tier + producer + armor class + movement class + size class + weapon archetypes + reference numbers (FRAMEWORK 5.4). The
mapping from the 152 combat units to archetypes is in `global.json → unit_assignments` (listing in FRAMEWORK 7.4).

| Archetype | T | Producer | Bible role tags it carries | Armor | Move | Size | Weapon archetypes |
|---|--:|---|---|---|---|---|---|
| `inf_line` | 1 | Barracks | combat, ground, infantry | infantry | foot | inf | small_arms |
| `inf_at` | 1 | Barracks | anti_tank, infantry | infantry | foot | inf | at_missile |
| `inf_support` | 2 | Barracks | specialist, (detector), infantry — unarmed | infantry | foot | inf | – |
| `inf_combat_spec` | 2 | Barracks | specialist, infantry — armed | infantry | foot | inf | small_arms (+ grenade_launcher / breach_charge) |
| `veh_scout` | 1 | Factory | light, scout, detector, transport | light_vehicle | wheeled | light | machine_gun |
| `arty_light` | 2 | Factory | light, artillery, siege | light_vehicle | wheeled | light | mortar / rocket_barrage |
| `mbt_t1` | 1 | Factory | tank | medium_armor | tracked | medium | tank_cannon |
| `mbt_t2`, `mbt_t2_rail` | 2 | Factory | tank | medium_armor | tracked | medium | tank_cannon / rail_gun |
| `veh_aa`, `veh_aa_beam`, `veh_aa_flak` | 2 | Factory | anti_air, detector | medium_armor | tracked | medium | aa_missile / beam_thermal / flak |
| `arty_howitzer`, `arty_rocket`, `arty_missile` | 2 | Factory | artillery, siege | light_vehicle | tracked | medium | artillery_shell / rocket_barrage / missile_artillery |
| `siege_ap`, `siege_he`, `siege_rail`, `siege_beam`, `siege_demo` | 3 | Factory | tank, siege | heavy_armor | tracked | heavy | tank_cannon / siege_gun / rail_gun / beam_thermal / demolition_cannon |
| `veh_command` | 3 | Factory | command | heavy_armor | tracked | huge | tank_cannon |
| `veh_assault_carrier` | 3 | Factory | transport, amphibious | heavy_armor | amphibious | huge | siege_gun |
| `air_fighter` | 2 | Airfield | aircraft, anti_air | air_light | air_fixed | air_medium | aa_missile |
| `air_gunship` | 3 | Airfield | aircraft, ground_attack | air_heavy | air_hover | air_large | air_missile |
| `air_bomber` | 3 | Airfield | aircraft, ground_attack | air_heavy | air_fixed | air_large | bomb |
| `air_drone` | 3 | Airfield | aircraft, ground_attack, unmanned | air_light | air_hover | air_medium | air_missile |
| `air_ew` | 3 | Airfield | aircraft, electronic_warfare | air_heavy | air_fixed | air_large | – |
| `ship_patrol` | 1 | Dock | ship, scout | ship_light | naval | ship_small | machine_gun |
| `ship_escort` | 2 | Dock | ship, anti_air, anti_submarine, detector | ship_heavy | naval | ship_medium | naval_gun + aa_missile + torpedo |
| `ship_siege` | 3 | Dock | ship, siege | ship_heavy | naval | ship_large | naval_bombard |
| `ship_carrier` | 3 | Dock | ship, carrier, siege | ship_heavy | naval | ship_large | drone_missile (on the drones) |
| `ship_sub` | 3 | Dock | ship, submarine, siege | ship_heavy | submerged | ship_medium | torpedo + cruise_missile |

**Reverse map: bible role tag → archetype(s)** (`rule.combat.role_tags`; the bible's tag stays on the unit, the archetype supplies numbers):

| bible tag | archetype(s) carrying it |
|---|---|
| `light` | `veh_scout`, `arty_light` (APC/scout chassis, Sandglass, Scorpion, Reed) |
| `tank` | `mbt_t1`, `mbt_t2`, `mbt_t2_rail`, all `siege_*` (siege tanks are tanks; `veh_command` and `veh_assault_carrier` are not) |
| `artillery` | land: `arty_light`, `arty_howitzer`, `arty_rocket`, `arty_missile` (not ships, aircraft or direct-fire siege tanks) |
| `siege` | `siege_*`, `arty_*`, `ship_siege`, `ship_carrier`, `ship_sub` |
| `unmanned` | ability `unmanned` on `veh_aa` (Firefly), `arty_rocket`/`arty_light` (Nest, Reed), `air_fighter` (Swallow), `air_bomber` (Silkwing), `air_drone` (Nightjar), carrier drones |
| `scout`, `detector` | `veh_scout`, `ship_patrol` (scout); `veh_scout`, `veh_aa*`, `ship_escort`, observer/officer `inf_support` (detector, radius 5) |
| `transport` | `veh_scout` (2 squads; Okapi 3), `veh_assault_carrier` (4), Landing Transport |
| `specialist` | `inf_support`, `inf_combat_spec` |
| `amphibious` | ability `amphibious` (movement class `amphibious`), `veh_assault_carrier`, Landing Transport |
| `anti_air` | `veh_aa*`, `air_fighter`, `ship_escort` |
| `anti_tank` | `inf_at` |
| `anti_submarine` | `ship_escort` |
| `ground_attack` | `air_gunship`, `air_bomber`, `air_drone` |
| `carrier`, `command`, `electronic_warfare`, `submarine` | `ship_carrier`; `veh_command`; `air_ew`; `ship_sub` |
| `repair`, `capture`, `collector`, `construction`, `service` | service units only (Engineer, Collector, MCV, Landing Transport) |

Service units (bible-fixed cost) use dedicated rows in `service_units`: Engineer (infantry, 260 HP), Collector (light_vehicle, 900 HP, capacity 600),
MCV (medium_armor, 2000 HP), Landing Transport (light_vehicle, 1400 HP). Units keep their bible tags when a variant replaces them
(rule.design.scope_of_modifiers); replacement changes stats only through `tags`/`abilities` in `unit_assignments`.

---

## 10. Weapon archetypes (27)

Every weapon in every unit and defence is an instance of one of these; the instance only overrides numbers, never the damage type,
fire mode or target set. `fire_mode` drives the bible's Dust Screen rule (direct-fire only). `interceptable_by` drives Ural/Arjun APS
(`aps_trident`: ordinary guided missiles, 12/15 s cooldown) and Trident charges (`trident`: artillery shells and rockets; `aps_trident`
also counts missiles). Beams, bullets, rails and EMP are never interceptable (bible).

| # | archetype | dmg type | fire | projectile | speed c/s | targets | splash | scatter | range cells | reload s | interceptable by |
|--:|:--|:--|:--|:--|--:|:--|--:|--:|--:|--:|:--|
| 0 | small_arms | bullet | direct | bullet | 40 | ground/sea/air | - | - | 5-6 | 0.8-1.2 | none |
| 1 | machine_gun | bullet | direct | bullet | 40 | ground/sea/air | - | - | 5.5-7 | 0.8-1.2 | none |
| 2 | autocannon | bullet | direct | bullet | 30 | ground/sea/air | - | - | 6-8 | 0.4-0.8 | none |
| 3 | tank_cannon | ap | direct | shell | 16 | ground/sea | 0.5 | - | 6.5-9 | 1-1.6 | none |
| 4 | siege_gun | he | direct | shell | 14 | ground/sea | 1.2 | 0.5 | 7.5-9.5 | 2.4-3.6 | none |
| 5 | demolition_cannon | he | direct | shell | 12 | ground/sea | 2.5 | 0.4 | 3.5-5 | 3.5-4.5 | none |
| 6 | at_missile | ap | direct | missile | 10 | ground/sea | - | - | 6-9 | 4-6.5 | aps_trident |
| 7 | aa_missile | ap | direct | missile | 14 | air | - | - | 8-11 | 1-2 | aps_trident |
| 8 | flak | he | direct | shell | 20 | air | 1.6 | - | 7-9 | 0.8-1.2 | none |
| 9 | artillery_shell | he | indirect | shell | 9 | ground | 1.6 | 0.9 | 12-17 | 3-4.2 | trident |
| 10 | rocket_barrage | he | indirect | rocket | 10 | ground | 1.3 | 1.8 | 11-14 | 5-8 | trident |
| 11 | mortar | he | indirect | shell | 9 | ground | 1.4 | 1.0 | 9-12 | 2.5-3.5 | trident |
| 12 | missile_artillery | ap | indirect | missile | 12 | ground/sea | 0.7 | 0.35 | 15-19 | 5.5-8 | aps_trident |
| 13 | beam_thermal | thermal | direct | beam | hitscan | ground/sea | - | - | 8-10.5 | 0.25 | none |
| 14 | rail_gun | rail | direct | rail | hitscan | ground/sea | - | - | 10-14.5 | 3.5-6 | none |
| 15 | torpedo | ap | direct | torpedo | 8 | sea/sub | - | - | 6-9 | 6-10 | none |
| 16 | depth_charge | he | indirect | bomb | 6 | sub | 2.5 | 0.5 | 3-5.5 | 4-6 | none |
| 17 | bomb | he | indirect | bomb | 8 | ground | 2.2 | 0.7 | 0-1.5 | 0.8-1.6 | none |
| 18 | air_missile | ap | direct | missile | 14 | ground/sea | - | - | 5-7 | 1.2-2 | aps_trident |
| 19 | emp_pulse | emp | direct | field | hitscan | ground/air/sea | - | - | - | - | none |
| 20 | canister | bullet | direct | pellets | 30 | ground | 1.2 | - | 3-4 | 1.5-2.5 | none |
| 21 | grenade_launcher | he | direct | grenade | 12 | ground | 1.2 | 0.3 | 2.5-4 | 1.2-2 | none |
| 22 | breach_charge | he | melee | charge | hitscan | ground | - | - | 0-1.2 | 6-10 | none |
| 23 | naval_gun | ap | direct | shell | 14 | ground/sea | 0.9 | - | 8-10.5 | 1.6-2.6 | none |
| 24 | naval_bombard | he | indirect | shell | 10 | ground/sea | 2.0 | 1.2 | 18-24 | 6-10 | trident |
| 25 | cruise_missile | he | indirect | missile | 12 | ground | 1.5 | 0.4 | 20-26 | 9-14 | aps_trident |
| 26 | drone_missile | ap | direct | missile | 14 | ground/sea | - | - | 3.5-6 | 1.5-2.5 | aps_trident |

`targets_override` on an instance may narrow or swap the archetype's target set only for the documented cases: laser AA (`["air"]`), dual-purpose flak (`["air","ground"]`), and units the bible restricts (Harpoon Team and Sea Spear "never aircraft", Bastion tower "no anti-air").

Behaviour flags every weapon instance carries: `homing` (direct fire always hits a living target; ballistic weapons land on the target's
position **at fire time**, so movers dodge slow shells), `scatter_cells` (uniform disc, drawn from `SimRng`), `suppressive` (bible: only Fortress
Guard and Watchtower fire), `min_range_cells`, `ammo_volleys` (aircraft/limited ammo), `ramp_seconds`/`ramp_max_pct` (beams), `deploy_s`.
Design rule for granularity: **≥ 25 damage per hit** (rocket 55 and beam ticks 33-50 accepted) so that a 10 % modifier is not
quantised away; use `hits_per_volley` for cosmetic multi-shot volleys.

---

## 11. Enumerations with frozen integer values

```
DamageType    BULLET 0, AP 1, HE 2, THERMAL 3, RAIL 4, KINETIC 5, EMP 6
ResistGroup   BULLET 1, EXPLOSIVE 2, BEAM 4, THERMAL 8, RAIL 16, KINETIC 32, EMP 64          (bit mask)
ArmorClass    INFANTRY 0, LIGHT_VEHICLE 1, MEDIUM_ARMOR 2, HEAVY_ARMOR 3, AIR_LIGHT 4, AIR_HEAVY 5, SHIP_LIGHT 6,
              SHIP_HEAVY 7, BUILDING_LIGHT 8, BUILDING_HEAVY 9, FORTRESS 10
Layer         GROUND 0, AIR 1, SURFACE_WATER 2, UNDERWATER 3
MoveClass     FOOT 0, WHEELED 1, TRACKED 2, AMPHIBIOUS 3, NAVAL 4, SUBMERGED 5, AIR_FIXED 6, AIR_HOVER 7, STATIC 8
TerrainKind   ROAD 0, OPEN 1, ROUGH 2, FOREST 3, MARSH 4, SHALLOW 5, DEEP 6, CLIFF 7
FireMode      DIRECT 0, INDIRECT 1, MELEE 2
Interceptable NONE 0, TRIDENT 1, APS_TRIDENT 2
WeaponArch    small_arms 0 … drone_missile 26   (table in section 10; index = order)
```

---

## 12. Change control

1. A new value or type is proposed by editing `global.json` **and** this file in the same change; `balance_calc.py validate` must pass.
2. Bible-fixed numbers (structure costs/build times/power, service-unit costs, research/power costs, superweapon timings and geometry,
   caps and floors) are asserted by `validate`; they cannot be changed here.
3. Faction designers may not add damage types, armor classes or weapon archetypes; they request them from the framework owner.
