# African Empire (AE)

*What survives belongs to the future.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Recovery, battlefield salvage and practical industrial endurance.  
**Visual direction:** Ochre, charcoal and bright cyan; repairable panels, reinforced wheels and interchangeable weapon modules.

## Faction traits (passive modifiers, applied by the resolver)

- Service Engineers and Reclaimers may salvage destroyed enemy land combat vehicles: an 8-second uninterrupted action yields 20% of the unit's paid purchase cost. Each wreck pays once; allied, self-destroyed, decoy and temporary summoned units produce no income.
- Land-vehicle repairs cost 25% fewer credits per health restored.
- Land artillery weapon range -10%. Strengths: sustained ground campaigns and economic recovery after winning battles. Weaknesses: must hold the battlefield to salvage, and can be outranged.

## Rosters

### African Empire / Vanilla — Vanilla

*Recovery, battlefield salvage and practical industrial endurance.*

- opening: Use Buffalo tanks and infantry to win a local fight, secure the area, then bring salvage teams. Spend recovered credits on expansion before attempting an expensive siege push.

### Nigeria — Civic Logistics Directorate

*Fast mobilization, infantry presence and protective drone support.*

- modifier: Combat infantry cost -15%.
- modifier: Combat infantry build time -15%.
- modifier: Non-superweapon structure construction time -10%.
- modifier: Aircraft health -10%.
- replaces **Union Guard** with **Civic Rifle Team**
- replaces **Weaver AA** with **Lagos Drone Guard**
- removes **Kiln Assault Crawler** (no replacement)
- loses vanilla-only power **Recovery Priority**
- exclusive research: **Municipal Reserves** (T2, 1000 cr) — Civic Rifle Teams gain health +10% within 6 cells of a friendly Barracks or Refinery; fields do not stack.
- exclusive power: **Civil Defense Net** (T2, 600 cr, 150 s cooldown) — Friendly infantry in a 6-cell-radius area gain sight +25% and suppression immunity for 15 seconds.
- opening: Secure several points with Civic teams, support them with Lagos vehicles and Buffalo tanks, and use superior presence to protect collectors and wreck fields.

### Kongo — River Compact Guard

*Amphibious transport, durable infantry and concealed recovery teams.*

- modifier: Amphibious vehicle movement speed +20% on land and water.
- modifier: Combat infantry health +10%.
- modifier: Land artillery cost +20%.
- replaces **Mamba APC** with **Okapi Amphibious Carrier**
- replaces **Reclaimer** with **River Warden**
- removes **Sovereign Arsenal Ship** (no replacement)
- loses vanilla-only power **Recovery Priority**
- exclusive research: **Watershed Logistics** (T2, 1000 cr) — Okapi carriers repair carried infantry at 1% maximum health per second after 6 seconds out of combat; free healing does not repair the carrier.
- exclusive power: **Concealed Crossing** (T2, 600 cr, 150 s cooldown) — Lay a 16-cell-long, 4-cell-wide smoke corridor on land or water for 12 seconds. It follows the shared Dust Screen damage rule and protects either side.
- opening: Move Wardens and infantry in Okapis, attack vulnerable resource routes, and retreat damaged vehicles behind the infantry screen for repair.

### South Africa — Southern Arsenal Union

*Long-range ground weapons and expensive precision vehicles.*

- modifier: Land combat vehicle weapon range +10%.
- modifier: Land combat vehicle cost +15%.
- modifier: Combat infantry build time +15%.
- replaces **Buffalo Tank** with **Rhino Rail Tank**
- replaces **Forge Howitzer** with **Protea Gun Carrier**
- removes **Hammerhead Gunship** (no replacement)
- loses vanilla-only power **Recovery Priority**
- exclusive research: **Precision Machining** (T3, 1700 cr) — Rhino and Protea reload intervals -10%; applies in either Protea firing mode.
- exclusive power: **Counterbattery Solution** (T2, 900 cr, 180 s cooldown) — Reveal enemy artillery that fired during the preceding 8 seconds within a selected 9-cell area, then mark those units for 12 seconds. Friendly ground weapons deal +15% damage to marked targets.
- opening: Use infantry and Mambas until Radar, then establish overlapping Rhino and Protea firing lines. Keep enough AA to protect a ground-focused force.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Union Guard | 1 | barracks | 250 | 9 s | 428 | infantry | 1.5 | 7 | 52 | 5.5 |
| Pike Team | 1 | barracks | 330 | 12 s | 310 | infantry | 1.4 | 7.5 | 62 | 6 |
| Reclaimer | 2 | barracks | 545 | 19.5 s | 420 | infantry | 1.4 | 8 | 36 | 5 |
| Mamba APC | 1 | factory | 550 | 17.5 s | 520 | light_vehicle | 3.2 | 12 | 30 | 6 |
| Buffalo Tank | 1 | factory | 850 | 27.5 s | 931 | medium_armor | 2 | 9 | 121 | 7 |
| Weaver AA | 2 | factory | 1050 | 31 s | 857 | medium_armor | 2.2 | 10 | 133 | 10 |
| Forge Howitzer | 2 | factory | 1325 | 39 s | 773 | light_vehicle | 1.5 | 8.5 | 59 | 12 |
| Kiln Assault Crawler | 3 | factory | 2400 | 63 s | 3800 | heavy_armor | 1.2 | 8 | 250 | 4.5 |
| Sunbird Interceptor | 2 | airfield | 1100 | 30.5 s | 700 | air_light | 7 | 11 | 100 | 8 |
| Hammerhead Gunship | 3 | airfield | 2100 | 58.5 s | 1500 | air_heavy | 4.5 | 10 | 120 | 6 |
| Delta Patrol Boat | 1 | dock | 600 | 16.5 s | 700 | ship_light | 3.2 | 11 | 56 | 6.5 |
| Anchor Escort | 2 | dock | 1700 | 47 s | 2200 | ship_heavy | 2.4 | 11 | 90 | 10 |
| Sovereign Arsenal Ship | 3 | dock | 3150 | 87.5 s | 4500 | ship_heavy | 1.4 | 10.5 | 120 | 20 |
| Civic Rifle Team ★ | 1 | barracks | 260 | 9.5 s | 373 | infantry | 1.5 | 7 | 49 | 5.5 |
| Lagos Drone Guard ★ | 2 | factory | 1100 | 32.5 s | 743 | medium_armor | 2.2 | 10 | 125 | 10 |
| Okapi Amphibious Carrier ★ | 1 | factory | 560 | 18 s | 442 | light_vehicle | 3.2 | 12 | 30 | 6 |
| River Warden ★ | 2 | barracks | 570 | 20.5 s | 420 | infantry | 1.4 | 8 | 36 | 5 |
| Rhino Rail Tank ★ | 2 | factory | 1250 | 37 s | 1502 | medium_armor | 1.8 | 9.5 | 148 | 11 |
| Protea Gun Carrier ★ | 2 | factory | 1375 | 40.5 s | 619 | light_vehicle | 1.5 | 8.5 | 60 | 15 |

## Baseline combat units

#### Union Guard (`unit.ae.union_guard`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 250 | 9 s | 428 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Reliable general infantry protecting repair and salvage teams.

**Weapons:**
- `union_rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

#### Pike Team (`unit.ae.pike_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 330 | 12 s | 310 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Anti-tank infantry with a short-to-medium-range missile.

**Weapons:**
- `pike_missile` (at_missile): 279×1 per 4.5 s = **62 dps**, range 6 cells

#### Reclaimer (`unit.ae.reclaimer`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 545 | 19.5 s | 420 | infantry | foot | 1.4 c/s | 8 | 0.4 | ground |

**Role (bible):** Armed salvage specialist; repairs one land vehicle at normal Engineer rate and gains salvage access.

**Weapons:**
- `reclaimer_carbine` (small_arms): 36×1 per 1 s = **36 dps**, range 5 cells

**Abilities:** `repair_aura`, `salvage`
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_unit_tags": ["land_vehicle"], "radius_cells": 1, "one_target": true}
  - `salvage`: {"action_s": 8, "payout_pct": 20}

#### Mamba APC (`unit.ae.mamba_apc`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 550 | 17.5 s | 520 | light_vehicle | wheeled | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Wheeled light transport and detector; strong road mobility.

**Weapons:**
- `mamba_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Buffalo Tank (`unit.ae.buffalo_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 850 | 27.5 s | 931 | medium_armor | tracked | 2 c/s | 9 | 0.6 | ground |

**Role (bible):** Conventional medium tank designed for repair and reuse.

**Weapons:**
- `buffalo_cannon` (tank_cannon): 145×1 per 1.2 s = **121 dps**, range 7 cells

#### Weaver AA (`unit.ae.weaver_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 857 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Mobile anti-air and detector with poor anti-armor capability.

**Weapons:**
- `weaver_missile` (aa_missile): 100×2 per 1.5 s = **133 dps**, range 10 cells
- `weaver_mg` (machine_gun): 25×1 per 1 s = **25 dps**, range 6 cells

#### Forge Howitzer (`unit.ae.forge_howitzer`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1325 | 39 s | 773 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Durable indirect artillery with shorter range than most rivals.

**Weapons:**
- `forge_shell` (artillery_shell): 207×1 per 3.5 s = **59 dps**, range 12 cells, min 4; deploy 3 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 2}

#### Kiln Assault Crawler (`unit.ae.kiln_assault_crawler`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2400 | 63 s | 3800 | heavy_armor | tracked | 1.2 c/s | 8 | 0.8 | ground |

**Role (bible):** Heavy demolition vehicle with a broad blast and short reach.

**Weapons:**
- `kiln_cannon` (demolition_cannon): 1000×1 per 4 s = **250 dps**, range 4.5 cells

#### Sunbird Interceptor (`unit.ae.sunbird_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1100 | 30.5 s | 700 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Dedicated fighter protecting advancing ground formations.

**Weapons:**
- `sunbird_missile` (aa_missile): 100×1 per 1 s = **100 dps**, range 8 cells, 6 volleys/sortie

**Rearm (full):** 8 s

#### Hammerhead Gunship (`unit.ae.hammerhead_gunship`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2100 | 58.5 s | 1500 | air_heavy | air_hover | 4.5 c/s | 10 | 0.6 | air |

**Role (bible):** Close-support anti-vehicle aircraft, vulnerable to prepared AA.

**Weapons:**
- `hammerhead_missile` (air_missile): 90×2 per 1.5 s = **120 dps**, range 6 cells, 7 volleys/sortie

**Rearm (full):** 12 s

#### Delta Patrol Boat (`unit.ae.delta_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 600 | 16.5 s | 700 | ship_light | naval | 3.2 c/s | 11 | 0.6 | surface_water |

**Role (bible):** River and coastal scout with a light cannon.

**Weapons:**
- `delta_gun` (machine_gun): 28×2 per 1 s = **56 dps**, range 6.5 cells

#### Anchor Escort (`unit.ae.anchor_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2200 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `anchor_gun` (naval_gun): 180×1 per 2 s = **90 dps**, range 9 cells
- `anchor_aa` (aa_missile): 60×2 per 1.5 s = **80 dps**, range 10 cells
- `anchor_torpedo` (torpedo): 250×1 per 6 s = **42 dps**, range 7 cells

#### Sovereign Arsenal Ship (`unit.ae.sovereign_arsenal_ship`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3150 | 87.5 s | 4500 | ship_heavy | naval | 1.4 c/s | 10.5 | 1.3 | surface_water |

**Role (bible):** Heavy naval artillery platform with limited mobility.

**Weapons:**
- `sovereign_bombard` (naval_bombard): 320×3 per 8 s = **120 dps**, range 20 cells, min 6

## Unique subfaction units

#### Civic Rifle Team (`unit.ae.civic_rifle_team`)

*unique subfaction unit — replaces **Union Guard** in Nigeria* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 260 | 9.5 s | 373 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Rifle infantry able to place one 20-second sensor puck every 30 seconds. Puck reveals a 4-cell area but does not detect camouflage and is destructible.

**Weapons:**
- `civic_rifle` (small_arms): 25×2 per 1 s = **49 dps**, range 5.5 cells

**Abilities:** `sensor`

#### Lagos Drone Guard (`unit.ae.lagos_drone_guard`)

*unique subfaction unit — replaces **Weaver AA** in Nigeria* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1100 | 32.5 s | 743 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Mobile anti-air and detector with one small repair drone. The drone repairs one nearby infantry unit at 1% maximum health per second and can be shot down.

**Weapons:**
- `lagos_missile` (aa_missile): 100×2 per 1.6 s = **125 dps**, range 10 cells
- `lagos_mg` (machine_gun): 25×1 per 1 s = **25 dps**, range 6 cells

**Abilities:** `drone_repair`
  - `drone_repair`: {"rate_pct_per_s": 1, "cost": "free", "target_unit_tags": ["infantry"], "radius_cells": 3, "one_target": true}

#### Okapi Amphibious Carrier (`unit.ae.okapi_amphibious_carrier`)

*unique subfaction unit — replaces **Mamba APC** in Kongo* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 560 | 18 s | 442 | light_vehicle | amphibious | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Amphibious light transport and detector; thin armor but strong passenger capacity.

**Weapons:**
- `okapi_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

**Abilities:** `amphibious`, `transport_3`

#### River Warden (`unit.ae.river_warden`)

*unique subfaction unit — replaces **Reclaimer** in Kongo* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 570 | 20.5 s | 420 | infantry | foot | 1.4 c/s | 8 | 0.4 | ground |

**Role (bible):** Armed repair and salvage infantry. Camouflages after 6 seconds stationary; repairing, salvaging or firing reveals it.

**Weapons:**
- `warden_carbine` (small_arms): 36×1 per 1 s = **36 dps**, range 5 cells

**Abilities:** `camouflage`, `repair_aura`, `salvage`
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_unit_tags": ["land_vehicle"], "radius_cells": 1, "one_target": true}
  - `salvage`: {"action_s": 8, "payout_pct": 20}
  - `camouflage`: {"delay_s": 6, "needs_stationary": true, "needs_no_attack": true, "reveal_on_fire": true, "keeps_abilities_active": false}

#### Rhino Rail Tank (`unit.ae.rhino_rail_tank`)

*unique subfaction unit — replaces **Buffalo Tank** in South Africa* · **T2** · built at **factory** · requires factory, radar · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1250 | 37 s | 1502 | medium_armor | tracked | 1.8 c/s | 9.5 | 0.6 | ground |

**Role (bible):** Accurate anti-armor rail tank with little splash; requires Radar and cannot efficiently clear infantry alone.

**Weapons:**
- `rhino_rail` (rail_gun): 741×1 per 5 s = **148 dps**, range 11 cells

#### Protea Gun Carrier (`unit.ae.protea_gun_carrier`)

*unique subfaction unit — replaces **Forge Howitzer** in South Africa* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1375 | 40.5 s | 619 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Switches in 3 seconds between indirect siege shells and short-range defensive canister fire; cannot use both simultaneously.

**Weapons:**
- `protea_shell` (artillery_shell): 210×1 per 3.5 s = **60 dps**, range 15 cells, min 4; modes: 0
- `protea_canister` (canister): 30×4 per 2 s = **60 dps**, range 3.5 cells, modes: 1

**Abilities:** `ability.mode_switch.default`
  - `ability.mode_switch.default`: {"switch_s": 3, "modes": [{"id": "siege_shell", "slots_n": [0]}, {"id": "canister", "slots_n": [1]}]}

## Faction structures

- **Horizon Mass Driver** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Horizon Mass Driver.
- **Forge Cannon** — 1800 cr, 35 s, power -40; health 3600; 110×1 per 0.7 s, range 9.5. Armored rapid-cycling anti-vehicle turret; shorter range than rail defenses.

## Superweapon

**Horizon Mass Driver** — recharge 480 s, warning 10 s.

A rail-assisted strategic battery strikes three overlapping circles, each 3 cells in radius, along a 10-cell line over 9 seconds. Impacts damage ground units, ships and structures. On land, pulverized debris slows all land vehicles by 35% for 20 seconds and prevents new construction there; it never blocks movement or permanently changes the map.

*Counterplay:* Leave the marked line before the first impact, avoid routing reinforcements through the debris, and attack from the sides. Existing buildings remain usable if they survive.

## Research

- **Recovery Winches** (T2, 900 cr, 45 s): Salvage actions take 5 rather than 8 seconds. Wreck value is unchanged.
- **Circular Armor** (T3, 1600 cr, 75 s): Land combat vehicles gain health +10%. Does not create salvage from friendly losses or increase a wreck's paid-cost basis.
- **Municipal Reserves** (T2, 1000 cr, 45 s, subfaction-exclusive): Civic Rifle Teams gain health +10% within 6 cells of a friendly Barracks or Refinery; fields do not stack.
- **Watershed Logistics** (T2, 1000 cr, 45 s, subfaction-exclusive): Okapi carriers repair carried infantry at 1% maximum health per second after 6 seconds out of combat; free healing does not repair the carrier.
- **Precision Machining** (T3, 1700 cr, 75 s, subfaction-exclusive): Rhino and Protea reload intervals -10%; applies in either Protea firing mode.

## Support powers

- **Survey Network** (T2, 400 cr, cooldown 90 s): Reveal a 7-cell-radius area for 12 seconds and highlight salvageable wrecks there. Reveals ordinary units but does not detect camouflage.
- **Field Refurbishment** (T3, 1000 cr, cooldown 180 s): Repair friendly land vehicles in a 6-cell-radius zone by 3% maximum health per second for 10 seconds. They cannot fire while receiving repairs; moving ends repair on that unit.
- **Recovery Priority** (T2, 600 cr, cooldown 150 s, not inherited): For 20 seconds, Engineers and Reclaimers gain movement speed +25% and salvage in 3 seconds. Salvage payout is unchanged.
- **Civil Defense Net** (T2, 600 cr, cooldown 150 s, not inherited): Friendly infantry in a 6-cell-radius area gain sight +25% and suppression immunity for 15 seconds.
- **Concealed Crossing** (T2, 600 cr, cooldown 150 s, not inherited): Lay a 16-cell-long, 4-cell-wide smoke corridor on land or water for 12 seconds. It follows the shared Dust Screen damage rule and protects either side.
- **Counterbattery Solution** (T2, 900 cr, cooldown 180 s, not inherited): Reveal enemy artillery that fired during the preceding 8 seconds within a selected 9-cell area, then mark those units for 12 seconds. Friendly ground weapons deal +15% damage to marked targets.
