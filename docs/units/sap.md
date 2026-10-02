# South Asian Protectorate (SAP)

*No refuge left undefended.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Protected advances, resilient defenses and battlefield engineering.  
**Visual direction:** Sand, indigo and saffron; layered armor, deployable braces and prominent interception sensors.

## Faction traits (passive modifiers, applied by the resolver)

- Defensive structures gain health +15%.
- Power reserve: defenses keep operating for 20 seconds after a power shortage begins. Reserve recharges only after 60 continuous seconds of adequate power. EMP-disabled defenses remain disabled; superweapons never use this reserve.
- Land combat vehicles move 10% slower. Strengths: protected positions and measured advances. Weaknesses: slow map response and the temptation to overspend on fortifications.

## Rosters

### South Asian Protectorate / Vanilla — Vanilla

*Protected advances, resilient defenses and battlefield engineering.*

- opening: Establish an economical infantry and Bulwark screen, protect the first expansion with a small defense cluster, then move the army forward with artillery rather than staying in the starting base.

### India — Integrated Defense Command

*Heavy protected pushes supported by economical power infrastructure.*

- modifier: Land combat vehicle health +15%.
- modifier: Land combat vehicle build time +15%.
- modifier: Generator cost -10%.
- replaces **Bulwark Tank** with **Arjun Assault Tank**
- replaces **Elephant Siege Tank** with **Gaj Siege Platform**
- removes **Sarus Gunship** (no replacement)
- loses vanilla-only power **Protected Advance**
- exclusive research: **Integrated Protection** (T3, 1700 cr) — Arjun missile-interception cooldown falls from 15 to 10 seconds; Gaj gains one interceptor with the same cooldown.
- exclusive power: **Assault Coordination** (T2, 900 cr, 180 s cooldown) — Friendly tanks in a 6-cell-radius zone gain reload interval -15% and sight +15% for 12 seconds.
- opening: Defend with infantry until Radar, then push with Arjuns, Vajras and Gaj platforms in stages, keeping a modest power surplus.

### Thailand — River and Strait Command

*Amphibious infantry assaults and mobile defense.*

- modifier: Amphibious combat vehicle cost -15%.
- modifier: Combat infantry movement speed +10%.
- modifier: Defensive structure health -10%.
- modifier: Tank reload interval +10%.
- replaces **Jackal APC** with **Naga Amphibious Carrier**
- replaces **Shield Rifle Squad** with **River Marine**
- removes **Elephant Siege Tank** (no replacement)
- loses vanilla-only power **Protected Advance**
- exclusive research: **Rapid Ferry Drills** (T2, 900 cr) — Naga loading and unloading time -40%; does not change passenger attack speed.
- exclusive power: **Mobile Reserve** (T2, 650 cr, 150 s cooldown) — Friendly ground transports in a 7-cell-radius zone gain movement speed +30% for 15 seconds and may unload while moving at half speed.
- opening: Use Nagas to relocate infantry rapidly, keep Monsoon guns behind the landing area, and defend several approaches with a mobile reserve.

### Pakistan — Frontier Observation Command

*Long-range missile artillery and concealed forward observation.*

- modifier: Land artillery weapon range +15%.
- modifier: Ordinary guided-missile flight speed +20%; excludes superweapons.
- modifier: Light land vehicle health -15%.
- replaces **Monsoon Howitzer** with **Shaheen Missile Battery**
- replaces **Combat Pioneer** with **Watchpost Recon Team**
- removes **Citadel Monitor** (no replacement)
- loses vanilla-only power **Protected Advance**
- exclusive research: **Observer Network** (T3, 1500 cr) — Shaheen batteries gain reload interval -10% when their target is within 6 cells of a Watchpost team.
- exclusive power: **Counterlaunch Plot** (T2, 800 cr, 180 s cooldown) — Mark enemy artillery that fired in the last 8 seconds inside a selected 8-cell-radius zone. After a 5-second warning, conventional shells hit the marked positions, not the units' new locations.
- opening: Scout with Jackals and Watchpost teams; protect Shaheens with Bulwarks and Vajras. Fire from unexpected angles rather than making one enormous gun line.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Shield Rifle Squad | 1 | barracks | 270 | 9.5 s | 460 | infantry | 1.5 | 7 | 52 | 5.5 |
| Kavach Team | 1 | barracks | 350 | 12.5 s | 300 | infantry | 1.4 | 7.5 | 60 | 7.5 |
| Combat Pioneer | 2 | barracks | 550 | 19.5 s | 420 | infantry | 1.4 | 8 | 36 | 5 |
| Jackal APC | 1 | factory | 590 | 19 s | 598 | light_vehicle | 3.2 | 12 | 30 | 6 |
| Bulwark Tank | 1 | factory | 830 | 27 s | 900 | medium_armor | 1.8 | 9 | 117 | 7 |
| Vajra AA | 2 | factory | 1050 | 31 s | 800 | medium_armor | 2.2 | 10 | 133 | 10 |
| Monsoon Howitzer | 2 | factory | 1375 | 40.5 s | 650 | light_vehicle | 1.5 | 8.5 | 57 | 15 |
| Elephant Siege Tank | 3 | factory | 2400 | 63 s | 3600 | heavy_armor | 1.4 | 8.5 | 233 | 8.5 |
| Garuda Interceptor | 2 | airfield | 1275 | 35.5 s | 700 | air_light | 7 | 11 | 100 | 8 |
| Sarus Gunship | 3 | airfield | 1975 | 55 s | 1500 | air_heavy | 4.5 | 10 | 120 | 4.8 |
| Estuary Patrol Boat | 1 | dock | 600 | 16.5 s | 700 | ship_light | 3.2 | 11 | 56 | 6.5 |
| Shield Escort | 2 | dock | 1700 | 47 s | 2200 | ship_heavy | 2.4 | 11 | 90 | 10 |
| Citadel Monitor | 3 | dock | 3400 | 94.5 s | 5175 | ship_heavy | 1.4 | 10.5 | 120 | 20 |
| Arjun Assault Tank ★ | 2 | factory | 1350 | 39.5 s | 1505 | medium_armor | 1.8 | 9.5 | 150 | 7.5 |
| Gaj Siege Platform ★ | 3 | factory | 2525 | 66.5 s | 3439 | heavy_armor | 1.4 | 8.5 | 223 | 8.5 |
| Naga Amphibious Carrier ★ | 1 | factory | 600 | 19.5 s | 504 | light_vehicle | 3.2 | 12 | 30 | 6 |
| River Marine ★ | 1 | barracks | 250 | 9 s | 365 | infantry | 1.5 | 7 | 56 | 5.5 |
| Shaheen Missile Battery ★ | 2 | factory | 1450 | 42.5 s | 609 | light_vehicle | 1.7 | 8.5 | 66 | 17 |
| Watchpost Recon Team ★ | 2 | barracks | 525 | 19 s | 309 | infantry | 1.5 | 11.2 | — | — |

## Baseline combat units

#### Shield Rifle Squad (`unit.sap.shield_rifle_squad`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 270 | 9.5 s | 460 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** General infantry with good staying power behind cover.

**Weapons:**
- `shield_rifle_squad` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

#### Kavach Team (`unit.sap.kavach_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 350 | 12.5 s | 300 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Anti-vehicle missile infantry; cannot fire on the move.

**Weapons:**
- `kavach_team` (at_missile): 270×1 per 4.5 s = **60 dps**, range 7.5 cells

#### Combat Pioneer (`unit.sap.combat_pioneer`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 550 | 19.5 s | 420 | infantry | foot | 1.4 c/s | 8 | 0.4 | ground |

**Role (bible):** Armed engineer building temporary cover and repairing defenses; cannot capture structures.

**Weapons:**
- `combat_pioneer` (small_arms): 36×1 per 1 s = **36 dps**, range 5 cells

**Abilities:** `cover_builder`, `repair_aura`
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_structure_tags": ["defense"], "radius_cells": 1}

#### Jackal APC (`unit.sap.jackal_apc`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 590 | 19 s | 598 | light_vehicle | wheeled | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Light transport and detector with modest armor.

**Weapons:**
- `jackal_apc` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Bulwark Tank (`unit.sap.bulwark_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 830 | 27 s | 900 | medium_armor | tracked | 1.8 c/s | 9 | 0.6 | ground |

**Role (bible):** Slow medium tank supporting infantry advances.

**Weapons:**
- `bulwark_tank` (tank_cannon): 140×1 per 1.2 s = **117 dps**, range 7 cells

#### Vajra AA (`unit.sap.vajra_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 800 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Dedicated mobile anti-air and detector.

**Weapons:**
- `vajra_aa` (aa_missile): 100×2 per 1.5 s = **133 dps**, range 10 cells

#### Monsoon Howitzer (`unit.sap.monsoon_howitzer`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1375 | 40.5 s | 650 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Steady indirect artillery with a 3-second deployment.

**Weapons:**
- `monsoon_howitzer` (artillery_shell): 200×1 per 3.5 s = **57 dps**, range 15 cells, min 4; deploy 3 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 3}

#### Elephant Siege Tank (`unit.sap.elephant_siege_tank`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2400 | 63 s | 3600 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Heavy assault gun with strong anti-structure damage and slow traverse.

**Weapons:**
- `elephant_siege_tank` (siege_gun): 700×1 per 3 s = **233 dps**, range 8.5 cells

#### Garuda Interceptor (`unit.sap.garuda_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1275 | 35.5 s | 700 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Dedicated defensive fighter with good endurance.

**Weapons:**
- `garuda_interceptor` (aa_missile): 100×1 per 1 s = **100 dps**, range 8 cells, 8 volleys/sortie

**Rearm (full):** 8 s

#### Sarus Gunship (`unit.sap.sarus_gunship`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1975 | 55 s | 1500 | air_heavy | air_hover | 4.5 c/s | 10 | 0.6 | air |

**Role (bible):** Close-support anti-vehicle aircraft with a short effective range.

**Weapons:**
- `sarus_gunship` (air_missile): 90×2 per 1.5 s = **120 dps**, range 4.8 cells, 7 volleys/sortie

**Rearm (full):** 12 s

#### Estuary Patrol Boat (`unit.sap.estuary_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 600 | 16.5 s | 700 | ship_light | naval | 3.2 c/s | 11 | 0.6 | surface_water |

**Role (bible):** River and coastal scout with a light cannon.

**Weapons:**
- `estuary_patrol_boat` (machine_gun): 28×2 per 1 s = **56 dps**, range 6.5 cells

#### Shield Escort (`unit.sap.shield_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2200 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `shield_escort_gun` (naval_gun): 180×1 per 2 s = **90 dps**, range 9 cells
- `shield_escort_aa` (aa_missile): 60×2 per 1.5 s = **80 dps**, range 10 cells
- `shield_escort_torpedo` (torpedo): 250×1 per 6 s = **42 dps**, range 7 cells

#### Citadel Monitor (`unit.sap.citadel_monitor`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3400 | 94.5 s | 5175 | ship_heavy | naval | 1.4 c/s | 10.5 | 1.3 | surface_water |

**Role (bible):** Armored coastal artillery ship, slow and vulnerable without escorts.

**Weapons:**
- `citadel_monitor` (naval_bombard): 320×3 per 8 s = **120 dps**, range 20 cells, min 6

## Unique subfaction units

#### Arjun Assault Tank (`unit.sap.arjun_assault_tank`)

*unique subfaction unit — replaces **Bulwark Tank** in India* · **T2** · built at **factory** · requires factory, radar · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1350 | 39.5 s | 1505 | medium_armor | tracked | 1.8 c/s | 9.5 | 0.6 | ground |

**Role (bible):** Armored medium tank mounting a short-range active-protection system. It intercepts one ordinary missile every 15 seconds; requires Radar.

**Weapons:**
- `arjun_assault_tank` (tank_cannon): 188×1 per 1.2 s = **150 dps**, range 7.5 cells

**Abilities:** `aps_interception`
  - `aps_interception`: {"cooldown_s": 15}

#### Gaj Siege Platform (`unit.sap.gaj_siege_platform`)

*unique subfaction unit — replaces **Elephant Siege Tank** in India* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2525 | 66.5 s | 3439 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Heavy siege vehicle that deploys in 4 seconds for weapon range +20% and cannot move while deployed.

**Weapons:**
- `gaj_siege_platform` (siege_gun): 669×1 per 3 s = **223 dps**, range 8.5 cells

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 4, "pack_s": 4, "range_bonus_pct": 20}

#### Naga Amphibious Carrier (`unit.sap.naga_amphibious_carrier`)

*unique subfaction unit — replaces **Jackal APC** in Thailand* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 600 | 19.5 s | 504 | light_vehicle | amphibious | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Amphibious light transport and detector with a smoke launcher: one 4-cell-radius, 6-second shared-rule smoke screen every 40 seconds.

**Weapons:**
- `naga_amphibious_carrier` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

**Abilities:** `amphibious`, `smoke`

#### River Marine (`unit.sap.river_marine`)

*unique subfaction unit — replaces **Shield Rifle Squad** in Thailand* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 250 | 9 s | 365 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Rifle infantry taking 20% less weapon damage for 6 seconds after disembarking. Immediate reboarding cannot refresh the effect.

**Weapons:**
- `river_marine` (small_arms): 28×2 per 1 s = **56 dps**, range 5.5 cells

**Abilities:** `ability.disembark_buff.default`
  - `ability.disembark_buff.default`: {"duration_s": 6, "damage_taken_reduction_pct": 20, "refresh_on_reboard": false}

#### Shaheen Missile Battery (`unit.sap.shaheen_missile_battery`)

*unique subfaction unit — replaces **Monsoon Howitzer** in Pakistan* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1450 | 42.5 s | 609 | light_vehicle | tracked | 1.7 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Precision missile artillery requiring 3 seconds to deploy; long reach, small blast radius and vulnerable during reload.

**Weapons:**
- `shaheen_missile_battery` (missile_artillery): 426×1 per 6.5 s = **66 dps**, range 17 cells, min 4; deploy 3 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 3}

#### Watchpost Recon Team (`unit.sap.watchpost_recon_team`)

*unique subfaction unit — replaces **Combat Pioneer** in Pakistan* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, detector, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 525 | 19 s | 309 | infantry | foot | 1.5 c/s | 11.2 | 0.4 | ground |

**Role (bible):** Detector and artillery observer that camouflages after 6 stationary seconds. Cannot build cover or repair defenses.

**Weapons:** none (support / unarmed).

**Abilities:** `camouflage`, `spotter`
  - `spotter`: {"radius_cells": 6}

## Faction structures

- **Trident Interception Array** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Trident Interception Array.
- **Bastion Missile Tower** — 1800 cr, 35 s, power -40; health 3600; 550×2 per 9 s, range 12. Durable anti-vehicle missile defense with strong burst damage and a long reload; no anti-air attack.

## Superweapon

**Trident Interception Array** — recharge 360 s, warning 6 s.

Protects a selected 6-cell-radius zone for 25 seconds with 24 interception charges. Each incoming hostile ordinary missile or artillery shell crossing the boundary consumes one charge and is destroyed. A superweapon impact packet consumes 8 charges to reduce its damage by 50%, never to cancel it. Beams, bullets, EMP, units entering the zone and weapons fired from inside it bypass interception. The zone is fixed and clearly visible.

*Counterplay:* Exhaust charges with cheap projectiles, attack with beams or infantry, enter the zone, or wait 25 seconds. Protection can support an offensive push; it is not a permanent base shield.

## Research

- **Layered Fieldworks** (T2, 1000 cr, 45 s): Combat infantry within 4 cells of a friendly defensive structure take 10% less explosive damage; overlapping structures do not stack.
- **Reserve Capacitors** (T3, 1600 cr, 75 s): Defense power reserve increases from 20 to 35 seconds. Recharge still requires 60 continuous seconds of adequate power.
- **Integrated Protection** (T3, 1700 cr, 75 s, subfaction-exclusive): Arjun missile-interception cooldown falls from 15 to 10 seconds; Gaj gains one interceptor with the same cooldown.
- **Rapid Ferry Drills** (T2, 900 cr, 45 s, subfaction-exclusive): Naga loading and unloading time -40%; does not change passenger attack speed.
- **Observer Network** (T3, 1500 cr, 75 s, subfaction-exclusive): Shaheen batteries gain reload interval -10% when their target is within 6 cells of a Watchpost team.

## Support powers

- **Recon Balloon** (T2, 450 cr, cooldown 90 s): Deploy a shootable tethered observation drone at a clear location for 20 seconds. It reveals terrain and detects within 6 cells.
- **Emergency Fortification** (T3, 900 cr, cooldown 180 s): Friendly defenses and production buildings in a 6-cell-radius zone take 25% less weapon damage for 15 seconds. Does not protect the superweapon structure or prevent EMP.
- **Protected Advance** (T2, 750 cr, cooldown 180 s, not inherited): For 12 seconds, infantry and land vehicles in a selected 6-cell-radius zone take 15% less weapon damage. Units receive no movement bonus.
- **Assault Coordination** (T2, 900 cr, cooldown 180 s, not inherited): Friendly tanks in a 6-cell-radius zone gain reload interval -15% and sight +15% for 12 seconds.
- **Mobile Reserve** (T2, 650 cr, cooldown 150 s, not inherited): Friendly ground transports in a 7-cell-radius zone gain movement speed +30% for 15 seconds and may unload while moving at half speed.
- **Counterlaunch Plot** (T2, 800 cr, cooldown 180 s, not inherited): Mark enemy artillery that fired in the last 8 seconds inside a selected 8-cell-radius zone. After a 5-second warning, conventional shells hit the marked positions, not the units' new locations.
