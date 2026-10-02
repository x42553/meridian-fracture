# Democratic Eurasian Federation (DEF)

*A thousand districts. One supply line.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Industrial volume, artillery saturation and replaceable armored forces.  
**Visual direction:** Oxide red, gray and pale yellow; slab armor, exposed running gear and standardized containers.

## Faction traits (passive modifiers, applied by the resolver)

- Land combat vehicles: cost -10%, build time -10%, movement speed -10%.
- No free units, permanent production multiplier or unlimited passive income; numerical superiority still needs collectors and factories.
- Strengths: replacement capacity, heavy artillery and sustained pressure. Weaknesses: slow reactions, supply exposure and cumbersome late-game formations.

## Rosters

### Democratic Eurasian Federation / Vanilla — Vanilla

*Industrial volume, artillery saturation and replaceable armored forces.*

- opening: Use cheap Hammers and infantry to contest two fronts, establish the economy behind them, then build a screened Anvil line rather than rushing one expensive capstone.

### Russia — Northern Arsenal Command

*Slow armored assaults with active protection.*

- modifier: Land combat vehicle health +15%.
- modifier: Land combat vehicle cost +10%.
- modifier: Land combat vehicle movement speed -10%.
- replaces **Hammer Tank** with **Ural Assault Tank**
- replaces **Colossus Siege Tank** with **Bear Siege Crawler**
- removes **Burya Bomber** (no replacement)
- loses vanilla-only power **Redundant Orders**
- exclusive research: **Layered Protection** (T3, 1500 cr) — Ural missile-interception cooldown falls from 12 to 9 seconds; Bear gains one such interceptor.
- exclusive power: **Steel Advance** (T2, 900 cr, 180 s cooldown) — Land vehicles in a 6-cell-radius zone take 20% less weapon damage for 12 seconds, but movement speed is reduced by a further 20% during the effect.
- opening: Screen with infantry and Mules until Radar; build a compact Ural spearhead supported by Porcupines and artillery.

### Kazakhstan — Steppe Transit Command

*Fast reconnaissance and mobile missile warfare.*

- modifier: Ground combat unit movement speed +20%.
- modifier: Refinery build cost -15%; collectors are not discounted.
- modifier: Land combat vehicle health -15%.
- replaces **Mule APC** with **Steppe Recon Carrier**
- replaces **Anvil Rocket Battery** with **Saker Missile Truck**
- removes **Colossus Siege Tank** (no replacement)
- loses vanilla-only power **Redundant Orders**
- exclusive research: **Mobile Dispatch** (T2, 900 cr) — Steppe Carriers and Saker trucks gain sight +15% and pack up without delay after firing.
- exclusive power: **Transit Priority** (T2, 600 cr, 150 s cooldown) — Friendly collectors and ground transports in a 7-cell-radius zone gain movement speed +35% for 15 seconds. Does not improve harvesting or unloading rate.
- opening: Scout aggressively, establish a second collection route and use Sakers to strike valuable units before withdrawing.

### North Korea — Fortress Reconstruction Bureau

*Durable infantry, prepared positions and decoys.*

- modifier: Combat infantry health +20%.
- modifier: Combat infantry build time -15%.
- modifier: Defensive structure cost -10%.
- modifier: Aircraft cost +25%.
- replaces **Line Conscript** with **Fortress Guard**
- replaces **Signal Officer** with **Echo Team**
- removes **Boreal Missile Submarine** (no replacement)
- loses vanilla-only power **Redundant Orders**
- exclusive research: **Buried Command Lines** (T2, 1000 cr) — Radar and defensive structures recover from EMP shutdown 25% sooner; does not prevent initial shutdown.
- exclusive power: **False Front** (T2, 500 cr, 150 s cooldown) — Place a 30-second decoy Radar and three decoy tanks in a scouted 6-cell zone. All are harmless, non-blocking and revealed by detectors.
- opening: Build overlapping infantry positions and a modest Hammer reserve, using decoys to make the location of the real artillery line uncertain.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Line Conscript | 1 | barracks | 230 | 8 s | 320 | infantry | 1.5 | 7 | 50 | 5.5 |
| Recoil Team | 1 | barracks | 355 | 12.5 s | 288 | infantry | 1.4 | 7.5 | 66 | 6 |
| Signal Officer | 2 | barracks | 470 | 17 s | 294 | infantry | 1.5 | 9 | — | — |
| Mule APC | 1 | factory | 590 | 19 s | 612 | light_vehicle | 2.8 | 12 | 30 | 6 |
| Hammer Tank | 1 | factory | 840 | 27 s | 864 | medium_armor | 2 | 7.2 | 112 | 7 |
| Porcupine AA | 2 | factory | 1050 | 31 s | 753 | medium_armor | 2.2 | 10 | 102 | 8 |
| Anvil Rocket Battery | 2 | factory | 1250 | 37 s | 565 | light_vehicle | 1.7 | 8.5 | 54 | 13 |
| Colossus Siege Tank | 3 | factory | 2400 | 63 s | 3456 | heavy_armor | 1.4 | 8.5 | 224 | 8.5 |
| Kite Interceptor | 2 | airfield | 1025 | 28.5 s | 672 | air_light | 7 | 11 | 81 | 8 |
| Burya Bomber | 3 | airfield | 1900 | 53 s | 1056 | air_heavy | 6 | 10 | 560 | 1.5 |
| Picket Boat | 1 | dock | 645 | 18 s | 659 | ship_light | 3.2 | 11 | 64 | 6.5 |
| Rampart Escort | 2 | dock | 1700 | 47 s | 2071 | ship_heavy | 2.4 | 11 | 88 | 10 |
| Boreal Missile Submarine | 3 | dock | 2600 | 72 s | 1921 | ship_heavy | 1.8 | 9 | 60 | 22 |
| Ural Assault Tank ★ | 2 | factory | 1425 | 42 s | 1722 | medium_armor | 1.8 | 9.5 | 150 | 7.5 |
| Bear Siege Crawler ★ | 3 | factory | 2425 | 64 s | 3593 | heavy_armor | 1.1 | 6.4 | 236 | 4.5 |
| Steppe Recon Carrier ★ | 1 | factory | 580 | 18.5 s | 380 | light_vehicle | 4 | 15 | 30 | 6 |
| Saker Missile Truck ★ | 2 | factory | 1450 | 42.5 s | 539 | light_vehicle | 1.7 | 8.5 | 58 | 17 |
| Fortress Guard ★ | 1 | barracks | 260 | 9.5 s | 353 | infantry | 1.5 | 7 | 56 | 6 |
| Echo Team ★ | 2 | barracks | 480 | 17 s | 276 | infantry | 1.5 | 9 | — | — |

## Baseline combat units

#### Line Conscript (`unit.def.line_conscript`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 230 | 8 s | 320 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Inexpensive rifle infantry; poor at independent assaults.

**Weapons:**
- `conscript_rifle` (small_arms): 25×2 per 1 s = **50 dps**, range 5.5 cells

#### Recoil Team (`unit.def.recoil_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 355 | 12.5 s | 288 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Unguided anti-vehicle weapon with useful close-range damage.

**Weapons:**
- `recoil_rocket` (at_missile): 298×1 per 4.5 s = **66 dps**, range 6 cells

#### Signal Officer (`unit.def.signal_officer`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, detector, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 470 | 17 s | 294 | infantry | foot | 1.5 c/s | 9 | 0.4 | ground |

**Role (bible):** Detector; nearby infantry recover from suppression 50% faster within 5 cells.

**Weapons:** none (support / unarmed).

**Abilities:** `ability.suppression_support.default`
  - `ability.suppression_support.default`: {"recovery_bonus_pct": 50, "radius_cells": 5}

#### Mule APC (`unit.def.mule_apc`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 590 | 19 s | 612 | light_vehicle | wheeled | 2.8 c/s | 12 | 0.5 | ground |

**Role (bible):** Light transport and detector; robust but slow.

**Weapons:**
- `mule_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Hammer Tank (`unit.def.hammer_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 840 | 27 s | 864 | medium_armor | tracked | 2 c/s | 7.2 | 0.6 | ground |

**Role (bible):** Mass-produced medium tank with modest sight.

**Weapons:**
- `hammer_gun` (tank_cannon): 134×1 per 1.2 s = **112 dps**, range 7 cells

#### Porcupine AA (`unit.def.porcupine_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 753 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Dual-purpose flak against aircraft and light infantry; also a detector.

**Weapons:**
- `porcupine_flak` (flak): 51×2 per 1 s = **102 dps**, range 8 cells

#### Anvil Rocket Battery (`unit.def.anvil_rocket_battery`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1250 | 37 s | 565 | light_vehicle | tracked | 1.7 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Wide-area indirect barrage; inaccurate against isolated moving targets.

**Weapons:**
- `anvil_barrage` (rocket_barrage): 54×6 per 6 s = **54 dps**, range 13 cells, min 3.5; splash 1.5

#### Colossus Siege Tank (`unit.def.colossus_siege_tank`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2400 | 63 s | 3456 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Slow heavy assault gun with strong area damage and poor traverse.

**Weapons:**
- `colossus_gun` (siege_gun): 672×1 per 3 s = **224 dps**, range 8.5 cells, splash 1.5

#### Kite Interceptor (`unit.def.kite_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1025 | 28.5 s | 672 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Simple air-superiority fighter; limited ground utility.

**Weapons:**
- `kite_aam` (aa_missile): 81×1 per 1 s = **81 dps**, range 8 cells, 6 volleys/sortie

**Rearm (full):** 8 s

#### Burya Bomber (`unit.def.burya_bomber`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1900 | 53 s | 1056 | air_heavy | air_fixed | 6 c/s | 10 | 0.7 | air |

**Role (bible):** Conventional area-bombing aircraft; visible and vulnerable on approach.

**Weapons:**
- `burya_bomb` (bomb): 672×1 per 1.2 s = **560 dps**, range 1.5 cells, 2 volleys/sortie

**Rearm (full):** 20 s

#### Picket Boat (`unit.def.picket_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 645 | 18 s | 659 | ship_light | naval | 3.2 c/s | 11 | 0.6 | surface_water |

**Role (bible):** Cheap patrol craft with a heavy machine gun.

**Weapons:**
- `picket_hmg` (machine_gun): 32×2 per 1 s = **64 dps**, range 6.5 cells

#### Rampart Escort (`unit.def.rampart_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2071 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `rampart_gun` (naval_gun): 176×1 per 2 s = **88 dps**, range 9 cells
- `rampart_flak_missile` (aa_missile): 59×2 per 1.5 s = **79 dps**, range 10 cells
- `rampart_torpedo` (torpedo): 245×1 per 6 s = **41 dps**, range 7 cells

#### Boreal Missile Submarine (`unit.def.boreal_missile_submarine`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: combat, ship, siege, submarine

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2600 | 72 s | 1921 | ship_heavy | submerged | 1.8 c/s | 9 | 0.9 | underwater |

**Role (bible):** Concealed missile submarine; surfaces for 8 seconds to bombard the coast, exposing itself to ordinary weapons.

**Weapons:**
- `boreal_torpedo` (torpedo): 480×1 per 8 s = **60 dps**, range 8 cells
- `boreal_cruise` (cruise_missile): 576×1 per 12 s = **48 dps**, range 22 cells

## Unique subfaction units

#### Ural Assault Tank (`unit.def.ural_assault_tank`)

*unique subfaction unit — replaces **Hammer Tank** in Russia* · **T2** · built at **factory** · requires factory, radar · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1425 | 42 s | 1722 | medium_armor | tracked | 1.8 c/s | 9.5 | 0.6 | ground |

**Role (bible):** Heavy tank intercepting one incoming ordinary missile every 12 seconds. Cannot intercept shells, beams or superweapons; requires Radar.

**Weapons:**
- `ural_cannon` (tank_cannon): 187×1 per 1.2 s = **150 dps**, range 7.5 cells

**Abilities:** `aps_interception`
  - `aps_interception`: {"cooldown_s": 12}

#### Bear Siege Crawler (`unit.def.bear_siege_crawler`)

*unique subfaction unit — replaces **Colossus Siege Tank** in Russia* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2425 | 64 s | 3593 | heavy_armor | tracked | 1.1 c/s | 6.4 | 0.8 | ground |

**Role (bible):** Very slow assault platform with frontal armor and a heavy demolition cannon. Poor vision and weak rear protection.

**Weapons:**
- `bear_demolition` (demolition_cannon): 946×1 per 4 s = **236 dps**, range 4.5 cells

**Abilities:** `frontal_armor`
  - `frontal_armor`: {"front_arc_deg": 120, "front_reduction_pct": 30, "rear_increase_pct": 25}

#### Steppe Recon Carrier (`unit.def.steppe_recon_carrier`)

*unique subfaction unit — replaces **Mule APC** in Kazakhstan* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 580 | 18.5 s | 380 | light_vehicle | wheeled | 4 c/s | 15 | 0.5 | ground |

**Role (bible):** Fast light transport and detector with extended sight, but poor armor.

**Weapons:**
- `steppe_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Saker Missile Truck (`unit.def.saker_missile_truck`)

*unique subfaction unit — replaces **Anvil Rocket Battery** in Kazakhstan* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1450 | 42.5 s | 539 | light_vehicle | tracked | 1.7 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Precision anti-vehicle and anti-structure missile artillery; deploys in 1 second, with little splash.

**Weapons:**
- `saker_missile` (missile_artillery): 378×1 per 6.5 s = **58 dps**, range 17 cells, min 4; splash 0.5; deploy 1 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 1, "pack_s": 1, "deployed_slots_n": [0]}

#### Fortress Guard (`unit.def.fortress_guard`)

*unique subfaction unit — replaces **Line Conscript** in North Korea* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 260 | 9.5 s | 353 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Rifle squad that deploys in 3 seconds for stronger suppressive fire; cannot move while deployed.

**Weapons:**
- `fortress_rifle` (small_arms): 25×2 per 1.1 s = **48 dps**, range 5.5 cells
- `fortress_suppressor` (small_arms): 25×2 per 0.9 s = **56 dps**, range 6 cells, suppressive

**Abilities:** `suppressive_deploy`
  - `suppressive_deploy`: {"deploy_s": 3, "pack_s": 3, "deployed_slots_n": [1]}

#### Echo Team (`unit.def.echo_team`)

*unique subfaction unit — replaces **Signal Officer** in North Korea* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, detector, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 480 | 17 s | 276 | infantry | foot | 1.5 c/s | 9 | 0.4 | ground |

**Role (bible):** Detector and suppression-recovery support. Can place one non-blocking decoy tank per team every 40 seconds; decoy lasts 30 seconds and has 1 health.

**Weapons:** none (support / unarmed).

**Abilities:** `ability.suppression_support.default`, `decoy`
  - `ability.suppression_support.default`: {"recovery_bonus_pct": 50, "radius_cells": 5}
  - `decoy`: {"cooldown_s": 40}

## Faction structures

- **Perun Missile Complex** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Perun Missile Complex.
- **Citadel Mortar** — 1800 cr, 35 s, power -40; health 4000; 340×1 per 3 s, range 16. Armored indirect-fire defense; minimum range makes it vulnerable to close attacks.

## Superweapon

**Perun Missile Complex** — recharge 480 s, warning 10 s.

One conventional bunker-buster missile detonates in a 3-cell-radius core, followed by a lower-damage fragmentation ring out to 7 cells. The core threatens heavy structures; the ring punishes tightly packed support units. It leaves no permanent contamination.

*Counterplay:* Move away from the central marker, separate production buildings and intercept the attack by destroying the launch complex during its warning. Normal AA cannot stop the strategic missile.

## Research

- **Standardized Parts** (T2, 900 cr, 45 s): Engineer repairs to land vehicles cost 15% fewer credits per health restored; applies anywhere, not only near a Factory.
- **Coordinated Barrages** (T3, 1600 cr, 75 s): Anvil batteries, Colossus tanks and their replacements gain reload interval -10% when stationary for at least 4 seconds. Moving resets the bonus.
- **Layered Protection** (T3, 1500 cr, 75 s, subfaction-exclusive): Ural missile-interception cooldown falls from 12 to 9 seconds; Bear gains one such interceptor.
- **Mobile Dispatch** (T2, 900 cr, 45 s, subfaction-exclusive): Steppe Carriers and Saker trucks gain sight +15% and pack up without delay after firing.
- **Buried Command Lines** (T2, 1000 cr, 45 s, subfaction-exclusive): Radar and defensive structures recover from EMP shutdown 25% sooner; does not prevent initial shutdown.

## Support powers

- **Mobilization Order** (T2, 700 cr, cooldown 180 s): For 20 seconds, Barracks and Factory production progresses 25% faster. Costs remain unchanged; benefit applies only while this power is active.
- **Tremor Barrage** (T3, 1300 cr, cooldown 210 s): After a 6-second warning, four waves of conventional shells strike a 5-cell-radius area over 8 seconds. High area pressure, limited precision.
- **Redundant Orders** (T2, 650 cr, cooldown 180 s, not inherited): Friendly vehicles in a 6-cell-radius zone ignore weapon-disabling EMP effects for 10 seconds. Does not protect buildings or prevent damage.
- **Steel Advance** (T2, 900 cr, cooldown 180 s, not inherited): Land vehicles in a 6-cell-radius zone take 20% less weapon damage for 12 seconds, but movement speed is reduced by a further 20% during the effect.
- **Transit Priority** (T2, 600 cr, cooldown 150 s, not inherited): Friendly collectors and ground transports in a 7-cell-radius zone gain movement speed +35% for 15 seconds. Does not improve harvesting or unloading rate.
- **False Front** (T2, 500 cr, cooldown 150 s, not inherited): Place a 30-second decoy Radar and three decoy tanks in a scouted 6-cell zone. All are harmless, non-blocking and revealed by detectors.
