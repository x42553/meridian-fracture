# North American Peace Corps (NAPC)

*Hold the line. Bring them home.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Durable combined arms; reliable frontline vehicles and recovery.  
**Visual direction:** Olive, cream and rescue orange; broad hulls, modular armor, visible crew cabins.

## Faction traits (passive modifiers, applied by the resolver)

- Land combat vehicles: health +10%, purchase cost +10%.
- Factory service apron: friendly land combat vehicles within 5 cells recover 1% maximum health per second, up to 75%, after 6 seconds without dealing or taking damage. Multiple aprons do not stack.
- Strengths: dependable armor, repair efficiency, clear combined-arms roles. Weaknesses: expensive vehicle losses and limited concealment.

## Rosters

### North American Peace Corps / Vanilla — Vanilla

*Durable combined arms; reliable frontline vehicles and recovery.*

- opening: Rifle Squad and Pathfinder scout first; two Guardians secure the first expansion. Add Sentinel AA before committing to Paladins. Preserve damaged vehicles instead of trading them.

### USA — Air Mobility Command

*Sustained air operations and precision strikes.*

- modifier: Aircraft cost -15%.
- modifier: Aircraft rearm time -20%.
- modifier: Land combat vehicle build time +15%.
- replaces **Falcon Interceptor** with **Raptor Multirole Fighter**
- replaces **Titan Gunship** with **Condor Stealth Bomber**
- removes **Bastion Heavy Tank** (no replacement)
- loses vanilla-only power **Combined Arms Window**
- exclusive research: **Dispersed Runways** (T2, 1100 cr) — Airfields gain two extra service pads; service rate per pad is unchanged.
- exclusive power: **Rapid Turnaround** (T2, 700 cr, 150 s cooldown) — One powered Airfield rearms aircraft 50% faster for 20 seconds. Does not accelerate aircraft production.
- opening: Build a normal infantry and Guardian screen, then an early Airfield. Mix Raptor loadouts and attack exposed production with Condors.

### Canada — Northern Littoral Command

*Amphibious armor and protected transport; useful on rivers and ordinary land.*

- modifier: Amphibious combat units gain health +10% on all terrain.
- modifier: Ship build time -15%.
- modifier: Amphibious vehicle movement speed on water +20%.
- modifier: Land artillery reload interval +15%.
- replaces **Pathfinder APC** with **Beaver Amphibious APC**
- replaces **Guardian Tank** with **Narwhal Amphibious Tank**
- removes **Titan Gunship** (no replacement)
- loses vanilla-only power **Combined Arms Window**
- exclusive research: **Sealed Compartments** (T2, 1000 cr) — Beaver and Narwhal units take 15% less explosive damage while on water.
- exclusive power: **Floating Workshop** (T2, 800 cr, 180 s cooldown) — Deploy a visible repair pontoon on clear land or water. For 20 seconds it repairs friendly vehicles and ships within 5 cells at 1.5% maximum health per second.
- opening: Use infantry and Beavers until Radar unlocks Narwhals; attack across secondary routes while frigates protect the crossing.

### Mexico — Federal Vanguard

*Affordable assault infantry with strong urban pressure.*

- modifier: Combat infantry cost -15%.
- modifier: Combat infantry build time -20%.
- modifier: Aircraft cost +20%.
- replaces **Rifle Squad** with **Vanguard Rifle Squad**
- replaces **Combat Medic** with **Aguila Breach Team**
- removes **Liberty Arsenal Ship** (no replacement)
- loses vanilla-only power **Combined Arms Window**
- exclusive research: **Section Logistics** (T2, 1000 cr) — Combat infantry recover 1% maximum health per second near a powered Barracks after 6 seconds out of combat.
- exclusive power: **Coordinated Advance** (T2, 600 cr, 150 s cooldown) — Friendly infantry in a 6-cell-radius zone gain movement speed +25% and suppression immunity for 12 seconds. Existing suppression is removed.
- opening: Contest capture points with Vanguard squads; use Guardians and Javelins to protect Aguila teams approaching buildings.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Rifle Squad | 1 | barracks | 250 | 9 s | 402 | infantry | 1.5 | 7 | 52 | 5.5 |
| Javelin Team | 1 | barracks | 350 | 12.5 s | 302 | infantry | 1.4 | 7.5 | 60 | 7.5 |
| Combat Medic | 2 | barracks | 485 | 17.5 s | 302 | infantry | 1.5 | 9 | — | — |
| Pathfinder APC | 1 | factory | 550 | 17.5 s | 545 | light_vehicle | 3.2 | 12 | 30 | 6 |
| Guardian Tank | 1 | factory | 850 | 27.5 s | 906 | medium_armor | 2 | 9 | 118 | 7 |
| Sentinel AA | 2 | factory | 1050 | 31 s | 839 | medium_armor | 2.2 | 10 | 135 | 10 |
| Paladin Howitzer | 2 | factory | 1375 | 40.5 s | 668 | light_vehicle | 1.5 | 8.5 | 59 | 15 |
| Bastion Heavy Tank | 3 | factory | 2375 | 62.5 s | 3700 | heavy_armor | 1.2 | 8.5 | 262 | 8.5 |
| Falcon Interceptor | 2 | airfield | 1100 | 30.5 s | 719 | air_light | 7 | 11 | 103 | 8 |
| Titan Gunship | 3 | airfield | 2250 | 62.5 s | 1773 | air_heavy | 4.5 | 10 | 124 | 6 |
| Riverwatch Patrol Boat | 1 | dock | 600 | 16.5 s | 733 | ship_light | 3.2 | 11 | 56 | 6.5 |
| Aegis Frigate | 2 | dock | 1700 | 47 s | 2260 | ship_heavy | 2.4 | 11 | 92 | 10 |
| Liberty Arsenal Ship | 3 | dock | 3400 | 94.5 s | 4625 | ship_heavy | 1.6 | 10.5 | 123 | 24 |
| Raptor Multirole Fighter ★ | 2 | airfield | 1050 | 29 s | 719 | air_light | 7 | 11 | 88 | 8 |
| Condor Stealth Bomber ★ | 3 | airfield | 1925 | 53.5 s | 1130 | air_heavy | 6 | 10 | 1319 | 1.5 |
| Beaver Amphibious APC ★ | 1 | factory | 485 | 15.5 s | 607 | light_vehicle | 3.2 | 12 | 19 | 6 |
| Narwhal Amphibious Tank ★ | 2 | factory | 860 | 28 s | 911 | medium_armor | 1.8 | 9 | 100 | 7 |
| Vanguard Rifle Squad ★ | 1 | barracks | 260 | 9.5 s | 419 | infantry | 1.5 | 7 | 52 | 5.5 |
| Aguila Breach Team ★ | 2 | barracks | 510 | 18 s | 545 | infantry | 1.4 | 8 | 36 | 2.8 |

## Baseline combat units

#### Rifle Squad (`unit.napc.rifle_squad`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 250 | 9 s | 402 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** General infantry; good against infantry, weak against armor.

**Weapons:**
- `rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

#### Javelin Team (`unit.napc.javelin_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 350 | 12.5 s | 302 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Stationary-firing anti-tank missiles; vulnerable while repositioning.

**Weapons:**
- `javelin_missile` (at_missile): 271×1 per 4.5 s = **60 dps**, range 7.5 cells

#### Combat Medic (`unit.napc.combat_medic`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 485 | 17.5 s | 302 | infantry | foot | 1.5 c/s | 9 | 0.4 | ground |

**Role (bible):** Unarmed infantry healer; cannot repair vehicles.

**Weapons:** none (support / unarmed).

**Abilities:** `heal_aura`
  - `heal_aura`: {"rate_pct_per_s": 3, "radius_cells": 4}

#### Pathfinder APC (`unit.napc.pathfinder_apc`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 550 | 17.5 s | 545 | light_vehicle | wheeled | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Light transport, scout and detector; loses to tanks.

**Weapons:**
- `pathfinder_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Guardian Tank (`unit.napc.guardian_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 850 | 27.5 s | 906 | medium_armor | tracked | 2 c/s | 9 | 0.6 | ground |

**Role (bible):** Conventional medium tank; main frontline unit.

**Weapons:**
- `guardian_cannon` (tank_cannon): 141×1 per 1.2 s = **118 dps**, range 7 cells

#### Sentinel AA (`unit.napc.sentinel_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 839 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Dedicated mobile anti-air and detector; poor ground weapon.

**Weapons:**
- `sentinel_aa_missile` (aa_missile): 101×2 per 1.5 s = **135 dps**, range 10 cells
- `sentinel_mg` (machine_gun): 25×1 per 1.2 s = **21 dps**, range 6 cells

#### Paladin Howitzer (`unit.napc.paladin_howitzer`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1375 | 40.5 s | 668 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Indirect siege artillery; must deploy for 3 seconds.

**Weapons:**
- `paladin_shell` (artillery_shell): 205×1 per 3.5 s = **59 dps**, range 15 cells, min 4; deploy 3 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3}

#### Bastion Heavy Tank (`unit.napc.bastion_heavy_tank`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2375 | 62.5 s | 3700 | heavy_armor | tracked | 1.2 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Slow twin-gun breakthrough tank; easily outmaneuvered.

**Weapons:**
- `bastion_twin_cannon` (tank_cannon): 164×2 per 1.2 s = **262 dps**, range 8.5 cells, splash 0.6

#### Falcon Interceptor (`unit.napc.falcon_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1100 | 30.5 s | 719 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Air-superiority fighter; no ground attack.

**Weapons:**
- `falcon_aam` (aa_missile): 103×1 per 1 s = **103 dps**, range 8 cells, 6 volleys/sortie

**Rearm (full):** 8 s

#### Titan Gunship (`unit.napc.titan_gunship`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2250 | 62.5 s | 1773 | air_heavy | air_hover | 4.5 c/s | 10 | 0.6 | air |

**Role (bible):** Armored hovering anti-vehicle aircraft; vulnerable to concentrated AA.

**Weapons:**
- `titan_missiles` (air_missile): 93×2 per 1.5 s = **124 dps**, range 6 cells, 7 volleys/sortie

**Rearm (full):** 12 s

#### Riverwatch Patrol Boat (`unit.napc.riverwatch_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 600 | 16.5 s | 733 | ship_light | naval | 3.2 c/s | 11 | 0.6 | surface_water |

**Role (bible):** Cheap anti-infantry and light-surface patrol craft.

**Weapons:**
- `riverwatch_mg` (machine_gun): 28×2 per 1 s = **56 dps**, range 6.5 cells

#### Aegis Frigate (`unit.napc.aegis_frigate`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2260 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `aegis_gun` (naval_gun): 185×1 per 2 s = **92 dps**, range 9 cells
- `aegis_aa_missile` (aa_missile): 61×2 per 1.5 s = **81 dps**, range 10 cells
- `aegis_torpedo` (torpedo): 257×1 per 6 s = **43 dps**, range 7 cells

#### Liberty Arsenal Ship (`unit.napc.liberty_arsenal_ship`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3400 | 94.5 s | 4625 | ship_heavy | naval | 1.6 c/s | 10.5 | 1.3 | surface_water |

**Role (bible):** Long-range land bombardment; depends on escorts.

**Weapons:**
- `liberty_bombard` (naval_bombard): 328×3 per 8 s = **123 dps**, range 24 cells, min 6

## Unique subfaction units

#### Raptor Multirole Fighter (`unit.napc.raptor_multirole_fighter`)

*unique subfaction unit — replaces **Falcon Interceptor** in USA* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 29 s | 719 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Switches between anti-air and anti-vehicle missile loads at an Airfield. Cannot carry both; less effective in air combat than a dedicated Falcon.

**Weapons:**
- `raptor_aam` (aa_missile): 88×1 per 1 s = **88 dps**, range 8 cells, 6 volleys/sortie; modes: 0
- `raptor_agm` (air_missile): 71×1 per 1.5 s = **47 dps**, range 6 cells, 4 volleys/sortie; modes: 1

**Abilities:** `multirole`

**Rearm (full):** 8 s

#### Condor Stealth Bomber (`unit.napc.condor_stealth_bomber`)

*unique subfaction unit — replaces **Titan Gunship** in USA* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1925 | 53.5 s | 1130 | air_heavy | air_fixed | 6 c/s | 10 | 0.7 | air |

**Role (bible):** Camouflages after 6 seconds without attacking. One heavy anti-structure bomb per sortie; slow rearm and weak protection when detected.

**Weapons:**
- `condor_bomb` (bomb): 1583×1 per 1.2 s = **1319 dps**, range 1.5 cells, 1 volleys/sortie

**Abilities:** `stealth`

**Rearm (full):** 28 s

#### Beaver Amphibious APC (`unit.napc.beaver_amphibious_apc`)

*unique subfaction unit — replaces **Pathfinder APC** in Canada* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 485 | 15.5 s | 607 | light_vehicle | amphibious | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Detector and infantry transport that crosses water; reinforced passenger protection, but a weak weapon.

**Weapons:**
- `beaver_mg` (machine_gun): 25×1 per 1.3 s = **19 dps**, range 6 cells

**Abilities:** `amphibious`, `ability.transport.squads2`
  - `ability.transport.squads2`: {"passenger_damage_reduction_pct": 20}

#### Narwhal Amphibious Tank (`unit.napc.narwhal_amphibious_tank`)

*unique subfaction unit — replaces **Guardian Tank** in Canada* · **T2** · built at **factory** · requires factory, radar · tags: amphibious, combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 860 | 28 s | 911 | medium_armor | amphibious | 1.8 c/s | 9 | 0.6 | ground |

**Role (bible):** Medium cannon tank that crosses water. Slower and less heavily armed than a Guardian; requires Radar.

**Weapons:**
- `narwhal_cannon` (tank_cannon): 120×1 per 1.2 s = **100 dps**, range 7 cells

**Abilities:** `amphibious`

#### Vanguard Rifle Squad (`unit.napc.vanguard_rifle_squad`)

*unique subfaction unit — replaces **Rifle Squad** in Mexico* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 260 | 9.5 s | 419 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** May deploy portable cover in 4 seconds. Gains 20% bullet-damage resistance while stationary behind it; packing takes 2 seconds.

**Weapons:**
- `rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

**Abilities:** `cover_builder`
  - `cover_builder`: {"build_s": 4, "pack_s": 2, "lifetime_s": 45, "resist_pct": 20}

#### Aguila Breach Team (`unit.napc.aguila_breach_team`)

*unique subfaction unit — replaces **Combat Medic** in Mexico* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 510 | 18 s | 545 | infantry | foot | 1.4 c/s | 8 | 0.4 | ground |

**Role (bible):** Armored assault infantry with anti-building charges and a short-range grenade launcher. Cannot heal; vulnerable in open ground.

**Weapons:**
- `aguila_grenade` (grenade_launcher): 58×1 per 1.6 s = **36 dps**, range 2.8 cells
- `aguila_breach_charge` (breach_charge): 290×1 per 8 s = **36 dps**, range 1 cells

**Abilities:** `breach_charge`

## Faction structures

- **Atlas Kinetic Array** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Atlas Kinetic Array.
- **Bulwark Cannon** — 1800 cr, 35 s, power -40; health 3400; 700×1 per 4 s, range 12. Long-range anti-vehicle cannon; slow traverse and poor infantry damage.

## Superweapon

**Atlas Kinetic Array** — recharge 480 s, warning 10 s.

A surviving orbital magazine releases three guided kinetic penetrators at a selected point and two points 3 cells to either side. Each has a 2-cell damage radius. It is strongest against clustered heavy vehicles and key buildings; the gaps and long warning reward dispersal.

*Counterplay:* Move valuable units between the impact circles, spread essential buildings, or destroy the control structure before the warning expires.

## Research

- **Adaptive Plating** (T2, 1000 cr, 45 s): Land combat vehicles take 10% less explosive damage. Does not reduce beam, rail or bullet damage.
- **Joint Tactical Links** (T3, 1600 cr, 75 s): Sentinel AA and Aegis Frigates gain weapon range +10% while within 6 cells of a friendly Rifle Squad, Javelin Team or their replacements.
- **Dispersed Runways** (T2, 1100 cr, 45 s, subfaction-exclusive): Airfields gain two extra service pads; service rate per pad is unchanged.
- **Sealed Compartments** (T2, 1000 cr, 45 s, subfaction-exclusive): Beaver and Narwhal units take 15% less explosive damage while on water.
- **Section Logistics** (T2, 1000 cr, 45 s, subfaction-exclusive): Combat infantry recover 1% maximum health per second near a powered Barracks after 6 seconds out of combat.

## Support powers

- **UAV Sweep** (T2, 500 cr, cooldown 90 s): A shootable reconnaissance UAV circles a 7-cell-radius area for 12 seconds, revealing terrain and detecting concealed units.
- **Field Repair Drop** (T3, 900 cr, cooldown 180 s): A shootable cargo aircraft delivers a repair station. It repairs friendly land vehicles in 5 cells by 2% maximum health per second for 10 seconds; stations do not stack.
- **Combined Arms Window** (T2, 900 cr, cooldown 180 s, not inherited): For 15 seconds, friendly infantry, land vehicles and aircraft in a selected 6-cell-radius zone deal 10% more weapon damage. Ships and structures receive no bonus.
- **Rapid Turnaround** (T2, 700 cr, cooldown 150 s, not inherited): One powered Airfield rearms aircraft 50% faster for 20 seconds. Does not accelerate aircraft production.
- **Floating Workshop** (T2, 800 cr, cooldown 180 s, not inherited): Deploy a visible repair pontoon on clear land or water. For 20 seconds it repairs friendly vehicles and ships within 5 cells at 1.5% maximum health per second.
- **Coordinated Advance** (T2, 600 cr, cooldown 150 s, not inherited): Friendly infantry in a 6-cell-radius zone gain movement speed +25% and suppression immunity for 12 seconds. Existing suppression is removed.
