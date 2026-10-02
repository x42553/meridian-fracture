# New European Confederation (NEC)

*No city stands alone.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Precision, sensor networks and deliberate positional warfare.  
**Visual direction:** Slate blue, white and amber; low profiles, angular turrets, fold-out sensor masts.

## Faction traits (passive modifiers, applied by the resolver)

- Networked fire: friendly combat infantry and land combat vehicles within 6 cells of a powered friendly Relay deal weapon damage +10%. Relay fields do not stack.
- All combat units cost +5%; service units are exempt.
- Strengths: precise fire, strong defensive positions and efficient local coordination. Weaknesses: costly units and dependence on vulnerable Relay coverage.

## Rosters

### New European Confederation / Vanilla — Vanilla

*Precision, sensor networks and deliberate positional warfare.*

- opening: Establish one contested position with Jagers and Leopards; add Radar, a Relay and Rapiers. Use artillery to make opponents enter the network rather than chasing blindly.

### Nordics — Northern Watch

*Reconnaissance, mobile missiles and coastal denial.*

- modifier: Scout and artillery sight +20%.
- modifier: Amphibious vehicle movement speed +15% on land and water.
- modifier: Tank health -10%.
- replaces **Surveyor APC** with **Fen Recon Carrier**
- replaces **Archer SPG** with **Fjord Missile Carrier**
- removes **Argent Rail Tank** (no replacement)
- loses vanilla-only power **Treaty Coordination**
- exclusive research: **Dispersed Links** (T2, 1000 cr) — Deployed Fen masts provide the Relay damage bonus in 4 cells using onboard power. Fields work during base power loss, do not stack with Relays and do not gain Relay radius upgrades.
- exclusive power: **Silent Watch** (T2, 600 cr, 150 s cooldown) — Friendly stationary ground units in a 6-cell-radius area camouflage for up to 15 seconds. Movement, firing or detection breaks concealment.
- opening: Use Fen carriers to reveal attack routes and screen mobile artillery with infantry and Rapiers.

### Eurocorps — Franco-German Armored Directorate

*Expensive armored formations and siege breakthroughs.*

- modifier: Tank health +15%.
- modifier: Tank cost +10%.
- modifier: All land combat vehicle build time +10%.
- replaces **Leopard Tank** with **Marte Heavy MBT**
- replaces **Argent Rail Tank** with **Charlemagne Siege Tank**
- removes **Aster EW Aircraft** (no replacement)
- loses vanilla-only power **Treaty Coordination**
- exclusive research: **Shared Fire Solutions** (T3, 1700 cr) — Marte and Charlemagne gain reload interval -10% inside a powered Relay field.
- exclusive power: **Armored Overwatch** (T2, 900 cr, 180 s cooldown) — For 15 seconds, stationary tanks in a selected 6-cell-radius zone gain weapon range +10%. Moving immediately removes the bonus.
- opening: Defend with infantry and Surveyors until Radar unlocks Marte; add Relays before building a costly siege group.

### Alpine Brotherhood — Pass and Tunnel Compact

*Fortified infantry, compact artillery positions and repairable defenses.*

- modifier: Combat infantry health +15%.
- modifier: Defensive structure cost -15%.
- modifier: Aircraft build time +20%.
- replaces **Sapper** with **Alpine Pioneer**
- replaces **Archer SPG** with **Ibex Crawler Gun**
- removes **Concord Monitor** (no replacement)
- loses vanilla-only power **Treaty Coordination**
- exclusive research: **Tunnel Workshops** (T2, 1000 cr) — Engineers and Alpine Pioneers repair defensive structures 25% faster; credit cost per health restored is unchanged.
- exclusive power: **Emergency Earthworks** (T2, 700 cr, 180 s cooldown) — Friendly infantry and defenses in a 5-cell-radius zone take 20% less explosive damage for 15 seconds. Does not protect vehicles.
- opening: Hold a narrow front with Pioneers, Ibex guns and Rapiers; expand behind the line rather than investing everything in one fortress.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Jager Squad | 1 | barracks | 240 | 8.5 s | 408 | infantry | 1.5 | 7 | 52 | 5.5 |
| Spike Team | 1 | barracks | 365 | 13 s | 318 | infantry | 1.4 | 7.5 | 64 | 9 |
| Sapper | 2 | barracks | 490 | 17.5 s | 452 | infantry | 1.4 | 8 | 36 | 4.5 |
| Surveyor APC | 1 | factory | 570 | 18.5 s | 560 | light_vehicle | 3.6 | 12 | 30 | 6 |
| Leopard Tank | 1 | factory | 850 | 27.5 s | 955 | medium_armor | 2 | 9 | 123 | 7 |
| Rapier AA | 2 | factory | 1125 | 33 s | 836 | medium_armor | 2.2 | 10 | 139 | 12 |
| Archer SPG | 2 | factory | 1300 | 38 s | 634 | light_vehicle | 1.5 | 8.5 | 61 | 15 |
| Argent Rail Tank | 3 | factory | 2400 | 63 s | 3450 | heavy_armor | 1.4 | 8.5 | 227 | 12 |
| Kestrel Interceptor | 2 | airfield | 1175 | 32.5 s | 731 | air_light | 7 | 11 | 104 | 8 |
| Aster EW Aircraft | 3 | airfield | 1800 | 50 s | 913 | air_heavy | 5 | 10 | — | — |
| Skerry Patrol Boat | 1 | dock | 615 | 17 s | 753 | ship_light | 4 | 11 | 56 | 6.5 |
| Horizon Escort | 2 | dock | 1700 | 47 s | 2300 | ship_heavy | 2.4 | 11 | 94 | 10 |
| Concord Monitor | 3 | dock | 2950 | 82 s | 3999 | ship_heavy | 1.6 | 10.5 | 126 | 20 |
| Fen Recon Carrier ★ | 1 | factory | 465 | 15 s | 594 | light_vehicle | 3.2 | 12 | 18 | 6 |
| Fjord Missile Carrier ★ | 2 | factory | 1525 | 45 s | 616 | light_vehicle | 1.7 | 8.5 | 66 | 17 |
| Marte Heavy MBT ★ | 2 | factory | 1400 | 37.7 s | 1985 | medium_armor | 1.8 | 9.5 | 173 | 7.5 |
| Charlemagne Siege Tank ★ | 3 | factory | 2525 | 61.2 s | 3560 | heavy_armor | 1.4 | 8.5 | 234 | 12 |
| Alpine Pioneer ★ | 2 | barracks | 520 | 18.5 s | 452 | infantry | 1.4 | 8 | 36 | 4.5 |
| Ibex Crawler Gun ★ | 2 | factory | 1375 | 40.5 s | 782 | light_vehicle | 1.5 | 8.5 | 60 | 12 |

## Baseline combat units

#### Jager Squad (`unit.nec.jager_squad`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 240 | 8.5 s | 408 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Accurate general infantry; vulnerable to area damage.

**Weapons:**
- `jager_squad` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

*Design note:* Accurate line infantry; area_vulnerable = takes extra damage from splash (armor/damage-matrix domain reads the tag; no ability kind exists).

#### Spike Team (`unit.nec.spike_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 365 | 13 s | 318 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Long-range guided anti-tank infantry; must stop to fire.

**Weapons:**
- `spike_team` (at_missile): 286×1 per 4.5 s = **64 dps**, range 9 cells

#### Sapper (`unit.nec.sapper`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 490 | 17.5 s | 452 | infantry | foot | 1.4 c/s | 8 | 0.4 | ground |

**Role (bible):** Combat engineer with a short-range weapon and temporary infantry cover; cannot replace the service Engineer.

**Weapons:**
- `sapper` (small_arms): 18×2 per 1 s = **36 dps**, range 4.5 cells

**Abilities:** `cover_builder`
  - `cover_builder`: {"build_s": 4, "lifetime_s": 45, "resist_pct": 20, "pieces_per_builder_n": 1}

#### Surveyor APC (`unit.nec.surveyor_apc`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 570 | 18.5 s | 560 | light_vehicle | wheeled | 3.6 c/s | 12 | 0.5 | ground |

**Role (bible):** Fast scout, detector and light infantry transport.

**Weapons:**
- `surveyor_apc` (machine_gun): 15×2 per 1 s = **30 dps**, range 6 cells

#### Leopard Tank (`unit.nec.leopard_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 850 | 27.5 s | 955 | medium_armor | tracked | 2 c/s | 9 | 0.6 | ground |

**Role (bible):** Well-balanced medium tank; limited splash damage.

**Weapons:**
- `leopard_tank` (tank_cannon): 148×1 per 1.2 s = **123 dps**, range 7 cells

#### Rapier AA (`unit.nec.rapier_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1125 | 33 s | 836 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Long-range mobile anti-air and detector.

**Weapons:**
- `rapier_aa` (aa_missile): 104×2 per 1.5 s = **139 dps**, range 12 cells

#### Archer SPG (`unit.nec.archer_spg`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1300 | 38 s | 634 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Accurate indirect artillery; fragile and slow to deploy.

**Weapons:**
- `archer_spg` (artillery_shell): 212×1 per 3.5 s = **61 dps**, range 15 cells, min 4; deploy 4 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 4, "pack_s": 4, "immobile": true, "deployed_slots_n": [0]}

#### Argent Rail Tank (`unit.nec.argent_rail_tank`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2400 | 63 s | 3450 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Long-range armor killer; slow reload, weak against infantry.

**Weapons:**
- `argent_rail_tank` (rail_gun): 794×1 per 3.5 s = **227 dps**, range 12 cells

#### Kestrel Interceptor (`unit.nec.kestrel_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1175 | 32.5 s | 731 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Dedicated fighter with a short rearm cycle.

**Weapons:**
- `kestrel_interceptor` (aa_missile): 104×1 per 1 s = **104 dps**, range 8 cells, 6 volleys/sortie

**Rearm (full):** 5.6 s

#### Aster EW Aircraft (`unit.nec.aster_ew_aircraft`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, electronic_warfare

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1800 | 50 s | 913 | air_heavy | air_fixed | 5 c/s | 10 | 0.6 | air |

**Role (bible):** Unarmed jammer: enemies within 5 cells have sight -25%; no effect on weapon range or fixed detection radius.

**Weapons:** none (support / unarmed).

#### Skerry Patrol Boat (`unit.nec.skerry_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 615 | 17 s | 753 | ship_light | naval | 4 c/s | 11 | 0.6 | surface_water |

**Role (bible):** Fast surface scout with a light autocannon.

**Weapons:**
- `skerry_patrol_boat` (autocannon): 31×1 per 0.6 s = **56 dps**, range 6.5 cells

#### Horizon Escort (`unit.nec.horizon_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2300 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `horizon_escort_naval_gun` (naval_gun): 189×1 per 2 s = **94 dps**, range 9 cells
- `horizon_escort_aa_missile` (aa_missile): 63×2 per 1.5 s = **84 dps**, range 10 cells
- `horizon_escort_torpedo` (torpedo): 262×1 per 6 s = **44 dps**, range 7 cells

#### Concord Monitor (`unit.nec.concord_monitor`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2950 | 82 s | 3999 | ship_heavy | naval | 1.6 c/s | 10.5 | 1.3 | surface_water |

**Role (bible):** Precision coastal artillery ship; vulnerable to close attack.

**Weapons:**
- `concord_monitor` (naval_bombard): 335×3 per 8 s = **126 dps**, range 20 cells, min 6

## Unique subfaction units

#### Fen Recon Carrier (`unit.nec.fen_recon_carrier`)

*unique subfaction unit — replaces **Surveyor APC** in Nordics* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 465 | 15 s | 594 | light_vehicle | amphibious | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Amphibious detector and transport. Can deploy a 6-cell sensor mast, becoming immobile and visibly exposed.

**Weapons:**
- `fen_recon_carrier` (machine_gun): 9×2 per 1 s = **18 dps**, range 6 cells

**Abilities:** `amphibious`, `ability.sensor_mast.default`
  - `ability.sensor_mast.default`: {"deploy_s": 2, "reveal_radius_cells": 6, "immobile": true}

*Design note:* Deployed mast is visibly exposed (no camouflage); Dispersed Links research grants the 4-cell relay field later.

#### Fjord Missile Carrier (`unit.nec.fjord_missile_carrier`)

*unique subfaction unit — replaces **Archer SPG** in Nordics* · **T2** · built at **factory** · requires factory, radar · tags: amphibious, artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1525 | 45 s | 616 | light_vehicle | amphibious | 1.7 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Amphibious precision missile artillery; fast redeployment, long reload and little splash.

**Weapons:**
- `fjord_missile_carrier` (missile_artillery): 465×1 per 7 s = **66 dps**, range 17 cells, min 4; splash 0.5; deploy 1.5 s

**Abilities:** `amphibious`, `deployable_mode`
  - `deployable_mode`: {"deploy_s": 1.5, "pack_s": 1.5, "immobile": true, "deployed_slots_n": [0]}

#### Marte Heavy MBT (`unit.nec.marte_heavy_mbt`)

*unique subfaction unit — replaces **Leopard Tank** in Eurocorps* · **T2** · built at **factory** · requires factory, radar · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1400 | 37.7 s | 1985 | medium_armor | tracked | 1.8 c/s | 9.5 | 0.6 | ground |

**Role (bible):** Heavy medium-tank replacement with good frontal protection and slow acceleration. Requires Radar, delaying the first tank.

**Weapons:**
- `marte_heavy_mbt` (tank_cannon): 216×1 per 1.2 s = **173 dps**, range 7.5 cells

**Abilities:** `frontal_armor`
  - `frontal_armor`: {"front_arc_deg": 120, "front_reduction_pct": 15}

#### Charlemagne Siege Tank (`unit.nec.charlemagne_siege_tank`)

*unique subfaction unit — replaces **Argent Rail Tank** in Eurocorps* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2525 | 61.2 s | 3560 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Deploys in 4 seconds to gain weapon range +25%. Cannot turn its hull or move while deployed; weak against infantry.

**Weapons:**
- `charlemagne_siege_tank` (rail_gun): 820×1 per 3.5 s = **234 dps**, range 12 cells, deploy 4 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 4, "pack_s": 4, "immobile": true, "turn_locked": true, "range_bonus_pct": 25, "deployed_slots_n": [0]}

#### Alpine Pioneer (`unit.nec.alpine_pioneer`)

*unique subfaction unit — replaces **Sapper** in Alpine Brotherhood* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 520 | 18.5 s | 452 | infantry | foot | 1.4 c/s | 8 | 0.4 | ground |

**Role (bible):** Builds one temporary infantry shelter per squad and repairs friendly defenses. A shelter lasts 45 seconds and grants occupants 25% bullet-damage resistance.

**Weapons:**
- `alpine_pioneer` (small_arms): 20×2 per 1.1 s = **36 dps**, range 4.5 cells

**Abilities:** `cover_builder`, `repair_aura`
  - `cover_builder`: {"build_s": 4, "lifetime_s": 45, "resist_pct": 25, "pieces_per_builder_n": 1}
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_structure_tags": ["defense"], "radius_cells": 1, "one_target": true}

*Design note:* One shelter per squad; repair applies to friendly defensive structures only (cost 0.5% price per s = economy repair_cost_bp).

#### Ibex Crawler Gun (`unit.nec.ibex_crawler_gun`)

*unique subfaction unit — replaces **Archer SPG** in Alpine Brotherhood* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1375 | 40.5 s | 782 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Compact tracked howitzer with a 2-second deployment and strong frontal protection. Less range than Archer, vulnerable from behind.

**Weapons:**
- `ibex_crawler_gun` (artillery_shell): 192×1 per 3.2 s = **60 dps**, range 12 cells, min 4; deploy 2 s

**Abilities:** `frontal_armor`, `deployable_mode`
  - `deployable_mode`: {"deploy_s": 2, "pack_s": 2, "immobile": true, "deployed_slots_n": [0]}
  - `frontal_armor`: {"front_arc_deg": 120, "front_reduction_pct": 25, "rear_increase_pct": 15}

## Faction structures

- **Aurora Microwave Array** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Aurora Microwave Array.
- **Lance Rail Emplacement** — 1800 cr, 35 s, power -40; health 3400; 700×1 per 5 s, range 14. Very long-range single-target anti-armor defense; minimal splash and a long reload.
- **Relay** — 600 cr, — s, power -20; health 3400; 700×1 per 5 s, range 14. Requires Radar; consumes 20 power. Provides the 6-cell networked-fire zone. It must be placed in normal construction range and does not extend that range.

## Superweapon

**Aurora Microwave Array** — recharge 420 s, warning 8 s.

A microwave burst affects an 8-cell-radius zone. Enemy vehicles and aircraft lose weapons for 8 seconds; powered enemy structures shut down for 18 seconds. Vehicles can still move, aircraft do not crash, and infantry remain operational. Direct damage is light.

*Counterplay:* Disperse powered infrastructure, advance with infantry, and retreat disabled vehicles. Destroying Aurora during its warning cancels the pulse.

## Research

- **Sensor Fusion** (T2, 1100 cr, 45 s): Surveyor APC, Rapier AA and Horizon Escort detection radius +2 cells; replacements inherit it.
- **Distributed Control** (T3, 1700 cr, 75 s): Relay radius increases from 6 to 8 cells. A Relay retains its damage-bonus field for 10 seconds after losing power, but not after destruction.
- **Dispersed Links** (T2, 1000 cr, 45 s, subfaction-exclusive): Deployed Fen masts provide the Relay damage bonus in 4 cells using onboard power. Fields work during base power loss, do not stack with Relays and do not gain Relay radius upgrades.
- **Shared Fire Solutions** (T3, 1700 cr, 75 s, subfaction-exclusive): Marte and Charlemagne gain reload interval -10% inside a powered Relay field.
- **Tunnel Workshops** (T2, 1000 cr, 45 s, subfaction-exclusive): Engineers and Alpine Pioneers repair defensive structures 25% faster; credit cost per health restored is unchanged.

## Support powers

- **Survey Drone** (T2, 450 cr, cooldown 90 s): A shootable drone reveals and detects within 6 cells of the target for 15 seconds.
- **Counterbattery Mission** (T3, 1100 cr, cooldown 180 s): After 5 seconds of warning, six conventional precision shells strike a selected 4-cell-radius area over 4 seconds. Moderate siege damage; moving units can escape.
- **Treaty Coordination** (T2, 800 cr, cooldown 180 s, not inherited): For 20 seconds, powered Relays provide damage +15% instead of +10%. No additional benefit outside their fields.
- **Silent Watch** (T2, 600 cr, cooldown 150 s, not inherited): Friendly stationary ground units in a 6-cell-radius area camouflage for up to 15 seconds. Movement, firing or detection breaks concealment.
- **Armored Overwatch** (T2, 900 cr, cooldown 180 s, not inherited): For 15 seconds, stationary tanks in a selected 6-cell-radius zone gain weapon range +10%. Moving immediately removes the bonus.
- **Emergency Earthworks** (T2, 700 cr, cooldown 180 s, not inherited): Friendly infantry and defenses in a 5-cell-radius zone take 20% less explosive damage for 15 seconds. Does not protect vehicles.
