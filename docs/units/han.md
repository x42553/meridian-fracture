# Han Empire (HAN)

*A common future requires a common plan.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Affordable infantry, unmanned support and vulnerable command links.  
**Visual direction:** Jade green, crimson and porcelain; compact modular hulls, sensor crowns and standardized drone racks.

## Faction traits (passive modifiers, applied by the resolver)

- Combat infantry cost -15% and build time -15%.
- Land combat vehicle health -10%.
- A Link Operator or Dragon Command Walker grants friendly unmanned combat units within 5 cells weapon damage +10%. Fields do not stack; destroying or suppressing the provider removes its field. Strengths: combined infantry/drone pressure; weaknesses: fragile vehicles and exposed control units.

## Rosters

### Han Empire / Vanilla — Vanilla

*Affordable infantry, unmanned support and vulnerable command links.*

- opening: Use cheap infantry to secure ground, add Ox tanks and Firefly AA, then support a Nest group with protected Link Operators.

### China — Imperial Standards Army

*Heavy armor and stronger local command coverage.*

- modifier: Land combat vehicle health +15%.
- modifier: Land combat vehicle cost +10%.
- modifier: Combat infantry build time +10%.
- replaces **Ox Tank** with **Imperial Guard Tank**
- replaces **Dragon Command Walker** with **Long Command Walker**
- removes **Silkwing Drone Bomber** (no replacement)
- loses vanilla-only power **Reserve Bandwidth**
- exclusive research: **Guard Integration** (T3, 1600 cr) — Imperial Guard Tanks count as eligible recipients of command-field damage bonuses, despite being crewed.
- exclusive power: **Central Priority** (T2, 800 cr, 180 s cooldown) — For 15 seconds, command fields provide weapon damage +20% instead of +10%; their radius is unchanged.
- opening: Use Banner and Lance infantry to survive until Radar, then combine Guard tanks with Fireflies, Nest drones and a command provider.

### Vietnam — Canopy Defense Command

*Concealed infantry and amphibious rocket raids.*

- modifier: Combat infantry movement speed +10%.
- modifier: Light land vehicle cost -10%.
- modifier: Tank cost +20%.
- replaces **Banner Infantry** with **Canopy Ranger**
- replaces **Nest Rocket Drone** with **Reed Rocket Skimmer**
- removes **Dragon Command Walker** (no replacement)
- loses vanilla-only power **Reserve Bandwidth**
- exclusive research: **Hidden Relays** (T2, 1000 cr) — Link Operators camouflage after 6 seconds stationary without attacking; their command field remains active while hidden.
- exclusive power: **Broken Contact** (T2, 650 cr, 150 s cooldown) — Ground combat units in a 6-cell-radius zone gain movement speed +20% for 10 seconds and leave a 6-second smoke screen at their initial position. Smoke follows the shared Dust Screen rule.
- opening: Threaten several approaches with Rangers; bring Link Operators and Reed skimmers to turn an ambush into a short, concentrated barrage.

### Cambodia — Mekong Reconstruction Authority

*Drone sustain, field repair and economical support systems.*

- modifier: Unmanned combat unit cost -15%.
- modifier: Repairs to friendly structures progress 25% faster; cost per health is unchanged.
- modifier: Tank build time +20%.
- replaces **Jade Carrier** with **Lotus Drone Tender**
- replaces **Link Operator** with **Mekong Field Engineer**
- removes **Emperor Drone Ship** (no replacement)
- loses vanilla-only power **Reserve Bandwidth**
- exclusive research: **Modular Servicing** (T3, 1500 cr) — Lotus Tenders repair 50% faster, but credit cost per health restored is unchanged.
- exclusive power: **Repair Swarm** (T2, 700 cr, 180 s cooldown) — Repair friendly unmanned land units and structures in a 5-cell-radius zone by 2% maximum health per second for 10 seconds. This paid power has no further repair charge.
- opening: Use infantry to shield Fireflies and Nest drones, keeping a few Lotus Tenders behind the line. Avoid trading support vehicles for a short-lived damage advantage.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Banner Infantry | 1 | barracks | 230 | 8 s | 337 | infantry | 1.5 | 7 | 52 | 5.5 |
| Lance Team | 1 | barracks | 350 | 12.5 s | 298 | infantry | 1.4 | 7.5 | 59 | 7.5 |
| Link Operator | 2 | barracks | 495 | 17.5 s | 298 | infantry | 1.5 | 9 | — | — |
| Jade Carrier | 1 | factory | 505 | 16.5 s | 439 | light_vehicle | 3.2 | 12 | 30 | 6 |
| Ox Tank | 1 | factory | 850 | 27.5 s | 893 | medium_armor | 2 | 9 | 116 | 7 |
| Firefly AA Drone | 2 | factory | 940 | 27.5 s | 675 | medium_armor | 2.2 | 10 | 132 | 10 |
| Nest Rocket Drone | 2 | factory | 1125 | 33 s | 506 | light_vehicle | 1.7 | 8.5 | 55 | 13 |
| Dragon Command Walker | 3 | factory | 2800 | 73.5 s | 2977 | heavy_armor | 1.3 | 9 | 132 | 8 |
| Swallow Interceptor | 2 | airfield | 1075 | 30 s | 695 | air_light | 7 | 11 | 99 | 8 |
| Silkwing Drone Bomber | 3 | airfield | 1700 | 46.5 s | 1092 | air_heavy | 6 | 10 | 579 | 1.5 |
| Canal Patrol Boat | 1 | dock | 600 | 16.5 s | 695 | ship_light | 3.2 | 11 | 56 | 6.5 |
| Jade Escort | 2 | dock | 1700 | 47 s | 2183 | ship_heavy | 2.4 | 11 | 80 | 10 |
| Emperor Drone Ship | 3 | dock | 3800 | 105.5 s | 4962 | ship_heavy | 1.5 | 11 | — | — |
| Imperial Guard Tank ★ | 2 | factory | 1250 | 37 s | 1588 | medium_armor | 1.8 | 9.5 | 158 | 7.5 |
| Long Command Walker ★ | 3 | factory | 2950 | 77.5 s | 2977 | heavy_armor | 1.3 | 9 | 132 | 8 |
| Canopy Ranger ★ | 1 | barracks | 265 | 9.5 s | 366 | infantry | 1.5 | 7 | 52 | 5.9 |
| Reed Rocket Skimmer ★ | 2 | factory | 855 | 25 s | 393 | light_vehicle | 2.6 | 9 | 43 | 10.5 |
| Lotus Drone Tender ★ | 1 | factory | 585 | 19 s | 484 | light_vehicle | 3.2 | 12 | 28 | 6 |
| Mekong Field Engineer ★ | 2 | barracks | 520 | 18.5 s | 279 | infantry | 1.5 | 9 | — | — |

## Baseline combat units

#### Banner Infantry (`unit.han.banner_infantry`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 230 | 8 s | 337 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Inexpensive general infantry; needs supporting weapons against armor.

**Weapons:**
- `banner_rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

#### Lance Team (`unit.han.lance_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 350 | 12.5 s | 298 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Anti-vehicle rocket infantry with a long reload.

**Weapons:**
- `lance_rocket` (at_missile): 348×1 per 5.8 s = **59 dps**, range 7.5 cells

#### Link Operator (`unit.han.link_operator`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, detector, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 495 | 17.5 s | 298 | infantry | foot | 1.5 c/s | 9 | 0.4 | ground |

**Role (bible):** Unarmed detector and provider of the 5-cell command field.

**Weapons:** none (support / unarmed).

**Abilities:** `command_field`

#### Jade Carrier (`unit.han.jade_carrier`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 505 | 16.5 s | 439 | light_vehicle | wheeled | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Light transport and detector; vulnerable to direct tank fire.

**Weapons:**
- `jade_carrier_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Ox Tank (`unit.han.ox_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 850 | 27.5 s | 893 | medium_armor | tracked | 2 c/s | 9 | 0.6 | ground |

**Role (bible):** Simple medium tank used to screen infantry formations.

**Weapons:**
- `ox_cannon` (tank_cannon): 139×1 per 1.2 s = **116 dps**, range 7 cells

#### Firefly AA Drone (`unit.han.firefly_aa_drone`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle, unmanned

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 940 | 27.5 s | 675 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Unmanned mobile anti-air and detector; no useful anti-tank attack.

**Weapons:**
- `firefly_aa` (aa_missile): 99×2 per 1.5 s = **132 dps**, range 10 cells

**Abilities:** `unmanned`

#### Nest Rocket Drone (`unit.han.nest_rocket_drone`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege, unmanned

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1125 | 33 s | 506 | light_vehicle | tracked | 1.7 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Unmanned indirect-fire launcher; fragile and dependent on spotting.

**Weapons:**
- `nest_rockets` (rocket_barrage): 55×6 per 6 s = **55 dps**, range 13 cells, min 3.5

**Abilities:** `unmanned`

#### Dragon Command Walker (`unit.han.dragon_command_walker`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, command, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2800 | 73.5 s | 2977 | heavy_armor | tracked | 1.3 c/s | 9 | 1 | ground |

**Role (bible):** Crewed heavy support vehicle with a cannon and 5-cell command field; expensive, large target.

**Weapons:**
- `walker_cannon` (tank_cannon): 198×1 per 1.5 s = **132 dps**, range 8 cells

#### Swallow Interceptor (`unit.han.swallow_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat, unmanned

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1075 | 30 s | 695 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Unmanned air-superiority fighter; cannot attack ground targets.

**Weapons:**
- `swallow_aam` (aa_missile): 99×1 per 1 s = **99 dps**, range 8 cells, 6 volleys/sortie

**Abilities:** `unmanned`

**Rearm (full):** 8 s

#### Silkwing Drone Bomber (`unit.han.silkwing_drone_bomber`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack, unmanned

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 46.5 s | 1092 | air_heavy | air_fixed | 6 c/s | 10 | 0.7 | air |

**Role (bible):** Unmanned precision bomber with a slow rearm cycle.

**Weapons:**
- `silkwing_bomb` (bomb): 695×1 per 1.2 s = **579 dps**, range 1.5 cells, 2 volleys/sortie

**Abilities:** `unmanned`

**Rearm (full):** 28 s

#### Canal Patrol Boat (`unit.han.canal_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 600 | 16.5 s | 695 | ship_light | naval | 3.2 c/s | 11 | 0.6 | surface_water |

**Role (bible):** Cheap coastal scout and infantry support craft.

**Weapons:**
- `patrol_mg` (machine_gun): 28×2 per 1 s = **56 dps**, range 6.5 cells

#### Jade Escort (`unit.han.jade_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2183 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `escort_aa` (aa_missile): 60×2 per 1.5 s = **80 dps**, range 10 cells
- `escort_torpedo` (torpedo): 248×1 per 6 s = **41 dps**, range 7 cells

#### Emperor Drone Ship (`unit.han.emperor_drone_ship`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: carrier, combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3800 | 105.5 s | 4962 | ship_heavy | naval | 1.5 c/s | 11 | 1.5 | surface_water |

**Role (bible):** Crewed carrier launching unmanned surface-strike drones; weak at close range.

**Weapons:** none (support / unarmed).

## Unique subfaction units

#### Imperial Guard Tank (`unit.han.imperial_guard_tank`)

*unique subfaction unit — replaces **Ox Tank** in China* · **T2** · built at **factory** · requires factory, radar · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1250 | 37 s | 1588 | medium_armor | tracked | 1.8 c/s | 9.5 | 0.6 | ground |

**Role (bible):** Better-armored medium tank with an accurate anti-vehicle gun; requires Radar and remains weak against infantry masses.

**Weapons:**
- `guard_cannon` (tank_cannon): 198×1 per 1.2 s = **158 dps**, range 7.5 cells

#### Long Command Walker (`unit.han.long_command_walker`)

*unique subfaction unit — replaces **Dragon Command Walker** in China* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, command, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2950 | 77.5 s | 2977 | heavy_armor | tracked | 1.3 c/s | 9 | 1 | ground |

**Role (bible):** Heavy crewed command platform. Deploying in 3 seconds extends its command radius by 2 cells but prevents movement.

**Weapons:**
- `walker_cannon` (tank_cannon): 198×1 per 1.5 s = **132 dps**, range 8 cells

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 2, "command_radius_bonus_cells": 2}

#### Canopy Ranger (`unit.han.canopy_ranger`)

*unique subfaction unit — replaces **Banner Infantry** in Vietnam* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 265 | 9.5 s | 366 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Rifle infantry camouflaging after 6 seconds stationary without firing on any terrain. Moving, attacking or taking damage reveals it.

**Weapons:**
- `ranger_rifle` (small_arms): 52×1 per 1 s = **52 dps**, range 5.9 cells

**Abilities:** `camouflage`

#### Reed Rocket Skimmer (`unit.han.reed_rocket_skimmer`)

*unique subfaction unit — replaces **Nest Rocket Drone** in Vietnam* · **T2** · built at **factory** · requires factory, radar · tags: amphibious, artillery, combat, ground, land_vehicle, light, siege, unmanned

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 855 | 25 s | 393 | light_vehicle | amphibious | 2.6 c/s | 9 | 0.5 | ground |

**Role (bible):** Unmanned amphibious light artillery firing short rocket bursts; less range and health than Nest.

**Weapons:**
- `reed_rockets` (rocket_barrage): 48×4 per 4.5 s = **43 dps**, range 10.5 cells, min 3

**Abilities:** `amphibious`, `unmanned`

#### Lotus Drone Tender (`unit.han.lotus_drone_tender`)

*unique subfaction unit — replaces **Jade Carrier** in Cambodia* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 585 | 19 s | 484 | light_vehicle | wheeled | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Light transport and detector. Repairs one nearby friendly unmanned land unit at 1% maximum health per second, paying normal repair cost; cannot repair itself.

**Weapons:**
- `lotus_tender_mg` (machine_gun): 28×1 per 1 s = **28 dps**, range 6 cells

**Abilities:** `repair_aura`
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_unit_tags": ["unmanned", "land_vehicle"], "radius_cells": 3, "one_target": true, "can_self": false}

#### Mekong Field Engineer (`unit.han.mekong_field_engineer`)

*unique subfaction unit — replaces **Link Operator** in Cambodia* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, detector, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 520 | 18.5 s | 279 | infantry | foot | 1.5 c/s | 9 | 0.4 | ground |

**Role (bible):** Unarmed detector, structure repairer and command provider. Its command field requires a 2-second stationary deployment; service Engineers remain available.

**Weapons:** none (support / unarmed).

**Abilities:** `command_field`, `repair_aura`
  - `command_field`: {"deploy_s": 2}
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_structure_tags": ["structure"], "radius_cells": 1}

## Faction structures

- **Dragonfall Field Foundry** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Dragonfall Field Foundry.
- **Dragon Tooth Launcher** — 1800 cr, 35 s, power -40; health 3400; 150×4 per 7.5 s, range 11. Short salvos of guided anti-vehicle missiles; powerful burst, vulnerable between salvos.

## Superweapon

**Dragonfall Field Foundry** — recharge 480 s, warning 10 s.

Three assembly capsules land within a marked 5-cell-radius area, then take 5 seconds to unfold into autonomous siege engines. They can be attacked during assembly. For 60 seconds after assembly they operate as slow anti-structure ground units, then their limited-energy cores expire. They cannot capture, repair, harvest, receive command-field buffs or generate salvage.

*Counterplay:* Attack capsules before assembly, surround the slow engines with anti-tank units, or retreat and wait out their 60-second lifetime. Destroying the Foundry during warning cancels deployment.

## Research

- **Resilient Mesh** (T2, 1000 cr, 45 s): Unmanned combat units recover from EMP weapon shutdown 25% sooner; they still take normal EMP damage.
- **Distributed Cognition** (T3, 1700 cr, 75 s): Command-field radius increases from 5 to 7 cells. Bonuses still do not stack and no unit is useful only inside a field.
- **Guard Integration** (T3, 1600 cr, 75 s, subfaction-exclusive): Imperial Guard Tanks count as eligible recipients of command-field damage bonuses, despite being crewed.
- **Hidden Relays** (T2, 1000 cr, 45 s, subfaction-exclusive): Link Operators camouflage after 6 seconds stationary without attacking; their command field remains active while hidden.
- **Modular Servicing** (T3, 1500 cr, 75 s, subfaction-exclusive): Lotus Tenders repair 50% faster, but credit cost per health restored is unchanged.

## Support powers

- **Wideband Scan** (T2, 400 cr, cooldown 90 s): Reveal and detect a 7-cell-radius area for 6 seconds. A visible scan warning gives opponents 2 seconds before detection begins.
- **Software Surge** (T3, 900 cr, cooldown 180 s): Friendly unmanned combat units in a 6-cell-radius zone gain reload interval -25% for 12 seconds, then lose weapons for 3 seconds. Excludes superweapon summons.
- **Reserve Bandwidth** (T2, 650 cr, cooldown 150 s, not inherited): For 20 seconds, all surviving command-field providers gain radius +3 cells. Damage bonus stays at +10% and overlapping fields still do not stack.
- **Central Priority** (T2, 800 cr, cooldown 180 s, not inherited): For 15 seconds, command fields provide weapon damage +20% instead of +10%; their radius is unchanged.
- **Broken Contact** (T2, 650 cr, cooldown 150 s, not inherited): Ground combat units in a 6-cell-radius zone gain movement speed +20% for 10 seconds and leave a 6-second smoke screen at their initial position. Smoke follows the shared Dust Screen rule.
- **Repair Swarm** (T2, 700 cr, cooldown 180 s, not inherited): Repair friendly unmanned land units and structures in a 5-cell-radius zone by 2% maximum health per second for 10 seconds. This paid power has no further repair charge.
