# Pacific Dominion (PD)

*The sea connects us.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Amphibious maneuver, naval reach and flexible coastal logistics.  
**Visual direction:** Ocean blue, coral orange and white; sealed hulls, folding flight surfaces and deck-mounted drones.

## Faction traits (passive modifiers, applied by the resolver)

- Collectors are amphibious and can cross navigable water at 70% of their land speed. They still collect only from designated deposits and unload at a Refinery.
- Ships gain movement speed +15%.
- Defensive structures have health -15%. Strengths: alternative routes and mobile staging. Weaknesses: vulnerable fixed positions and costly losses during landings.

## Rosters

### Pacific Dominion / Vanilla — Vanilla

*Amphibious maneuver, naval reach and flexible coastal logistics.*

- opening: Use Wake Skimmers and Tide Tanks to threaten routes that conventional armies cannot cover cheaply; build enough Storm AA to protect the landing area before investing in a fleet.

### Australia — Southern Reach Command

*Long-range expeditionary artillery backed by reconnaissance aircraft.*

- modifier: Land artillery weapon range +15%.
- modifier: Airfield construction time -15%.
- modifier: Land combat vehicle health -10%.
- modifier: Ship build time +15%.
- replaces **Breaker Howitzer** with **Outrider Howitzer**
- replaces **Petrel Fighter** with **Wedge Recon Fighter**
- removes **Leviathan Assault Carrier** (no replacement)
- loses vanilla-only power **Joint Landing**
- exclusive research: **Forward Fire Control** (T3, 1500 cr) — Outriders gain reload interval -10% while their target is within 6 cells of a friendly Wedge Recon Fighter.
- exclusive power: **Long Watch** (T2, 600 cr, 150 s cooldown) — Reveal a 7-cell-radius area for 18 seconds through a high-altitude sensor pass. It reveals terrain and ordinary units but does not detect camouflage.
- opening: Build a compact marine and Tide screen, then Wedge reconnaissance and Outrider batteries. Relocate as soon as the firing line is exposed.

### Indonesia — Archipelago Defense League

*Transport assaults, inexpensive marines and raids across several routes.*

- modifier: Combat infantry build time -15%.
- modifier: Transport health +20%, including Landing Transports.
- modifier: Tank cost +15%.
- replaces **Wake Skimmer** with **Kancil Landing Skimmer**
- replaces **Ranger Marine** with **Island Raider**
- removes **Tempest Carrier** (no replacement)
- loses vanilla-only power **Joint Landing**
- exclusive research: **Distributed Beachheads** (T2, 1000 cr) — Reef Technicians gain movement speed +15% and can repair a transport while riding in it, one Technician per transport.
- exclusive power: **Feint Landing** (T2, 500 cr, 120 s cooldown) — Create three harmless, non-blocking decoy transports for 25 seconds on scouted land or water. They cannot carry units and are identified by detectors.
- opening: Move Raiders in several Kancils, force defenders to commit to one approach, then land elsewhere. Use normal artillery for sustained land siege.

### Japan — Maritime Systems Authority

*Expensive precision systems, adaptable armor and advanced carriers.*

- modifier: Aircraft and ship reload intervals -10%; Airfield rearm time is unchanged.
- modifier: All combat unit cost +10%.
- modifier: Defensive structure health -10%.
- replaces **Tide Tank** with **Shinano Adaptive Tank**
- replaces **Tempest Carrier** with **Shogun Drone Carrier**
- removes **Breaker Howitzer** (no replacement)
- loses vanilla-only power **Joint Landing**
- exclusive research: **Predictive Maintenance** (T3, 1700 cr) — Shinano mode changes take 2 seconds; Shogun drone replacement time -20%.
- exclusive power: **Precision Window** (T2, 900 cr, 180 s cooldown) — Friendly aircraft and ships in a 6-cell-radius zone gain weapon damage +20% for 10 seconds, but receive no bonus to sight or survivability.
- opening: Use infantry and Skimmers until Radar unlocks Shinanos. On land, their siege mode replaces the lost howitzer; at sea, build one well-escorted Shogun.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Ranger Marine | 1 | barracks | 250 | 9 s | 450 | infantry | 1.5 | 7 | 52 | 5.5 |
| Harpoon Team | 1 | barracks | 350 | 12.5 s | 318 | infantry | 1.4 | 7.5 | 64 | 7.5 |
| Reef Technician | 2 | barracks | 475 | 17 s | 300 | infantry | 1.5 | 9 | — | — |
| Wake Skimmer | 1 | factory | 585 | 19 s | 552 | light_vehicle | 3.2 | 12 | 30 | 6 |
| Tide Tank | 1 | factory | 900 | 29 s | 955 | medium_armor | 2 | 9 | 123 | 7 |
| Storm AA | 2 | factory | 1050 | 31 s | 840 | medium_armor | 2.2 | 10 | 140 | 10 |
| Breaker Howitzer | 2 | factory | 1375 | 40.5 s | 670 | light_vehicle | 1.5 | 8.5 | 59 | 15 |
| Leviathan Assault Carrier | 3 | factory | 2900 | 76.5 s | 4121 | heavy_armor | 1.5 | 8.5 | 171 | 5.5 |
| Petrel Fighter | 2 | airfield | 1275 | 35.5 s | 721 | air_light | 7 | 11 | 103 | 8 |
| Osprey Strike Tiltrotor | 3 | airfield | 2100 | 58.5 s | 1545 | air_heavy | 4.5 | 10 | 124 | 6 |
| Reef Patrol Boat | 1 | dock | 615 | 17 s | 743 | ship_light | 4 | 11 | 56 | 6.5 |
| Trident Escort | 2 | dock | 1700 | 47 s | 2266 | ship_heavy | 2.4 | 11 | 92 | 10 |
| Tempest Carrier | 3 | dock | 3800 | 105.5 s | 5000 | ship_heavy | 1.5 | 11 | — | — |
| Outrider Howitzer ★ | 2 | factory | 1375 | 40.5 s | 710 | light_vehicle | 1.5 | 8.5 | 53 | 18 |
| Wedge Recon Fighter ★ | 2 | airfield | 1025 | 28.5 s | 753 | air_light | 7 | 13.8 | 91 | 8 |
| Kancil Landing Skimmer ★ | 1 | factory | 490 | 16 s | 552 | light_vehicle | 4 | 12 | 19 | 6 |
| Island Raider ★ | 1 | barracks | 250 | 9 s | 403 | infantry | 1.6 | 7 | 52 | 5.5 |
| Shinano Adaptive Tank ★ | 2 | factory | 1060 | 33 s | 1000 | medium_armor | 2 | 9 | 129 | 11 |
| Shogun Drone Carrier ★ | 3 | dock | 3950 | 109.5 s | 5451 | ship_heavy | 1.5 | 11 | — | — |

## Baseline combat units

#### Ranger Marine (`unit.pd.ranger_marine`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 250 | 9 s | 450 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** General infantry optimized for fighting after transport deployment.

**Weapons:**
- `ranger_rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

*Design note:* Bible: 'optimized after transport deployment' has no number (abilities_catalog section 6 CUSTOM flavor). Not encoded; the catalog's optional DISEMBARK_BUFF (+10% 4s) stays off.

#### Harpoon Team (`unit.pd.harpoon_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 350 | 12.5 s | 318 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Anti-vehicle missile infantry; may target surface ships, never aircraft.

**Weapons:**
- `harpoon_missile` (at_missile): 286×1 per 4.5 s = **64 dps**, range 7.5 cells

#### Reef Technician (`unit.pd.reef_technician`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 475 | 17 s | 300 | infantry | foot | 1.5 c/s | 9 | 0.4 | ground |

**Role (bible):** Unarmed specialist repairing nearby land vehicles or ships, one target at a time.

**Weapons:** none (support / unarmed).

**Abilities:** `repair_aura`
  - `repair_aura`: {"rate_pct_per_s": 1, "cost": "paid", "target_unit_tags": ["land_vehicle", "ship"], "radius_cells": 3, "one_target": true, "can_self": false}

#### Wake Skimmer (`unit.pd.wake_skimmer`)

*baseline* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 585 | 19 s | 552 | light_vehicle | amphibious | 3.2 c/s | 12 | 0.5 | ground |

**Role (bible):** Amphibious light transport and detector.

**Weapons:**
- `skimmer_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

**Abilities:** `amphibious`

#### Tide Tank (`unit.pd.tide_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 900 | 29 s | 955 | medium_armor | amphibious | 2 c/s | 9 | 0.6 | ground |

**Role (bible):** Amphibious medium tank; slow movement on water.

**Weapons:**
- `tide_cannon` (tank_cannon): 148×1 per 1.2 s = **123 dps**, range 7 cells

**Abilities:** `amphibious`

#### Storm AA (`unit.pd.storm_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 840 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Land-based anti-air and detector; requires a transport to cross water.

**Weapons:**
- `storm_aa_missile` (aa_missile): 105×2 per 1.5 s = **140 dps**, range 10 cells

#### Breaker Howitzer (`unit.pd.breaker_howitzer`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1375 | 40.5 s | 670 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Conventional land artillery with good sustained fire.

**Weapons:**
- `breaker_shell` (artillery_shell): 165×1 per 2.8 s = **59 dps**, range 15 cells, min 4; deploy 3 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 2}

#### Leviathan Assault Carrier (`unit.pd.leviathan_assault_carrier`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: amphibious, combat, ground, land_vehicle, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2900 | 76.5 s | 4121 | heavy_armor | amphibious | 1.5 c/s | 8.5 | 1 | ground |

**Role (bible):** Heavy amphibious vehicle with a short-range siege cannon and infantry capacity.

**Weapons:**
- `leviathan_siege_cannon` (demolition_cannon): 597×1 per 3.5 s = **171 dps**, range 5.5 cells

#### Petrel Fighter (`unit.pd.petrel_fighter`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1275 | 35.5 s | 721 | air_light | air_fixed | 7 c/s | 11 | 0.5 | air |

**Role (bible):** Dedicated interceptor with good patrol endurance.

**Weapons:**
- `petrel_aam` (aa_missile): 103×1 per 1 s = **103 dps**, range 8 cells, 8 volleys/sortie

**Rearm (full):** 8 s

#### Osprey Strike Tiltrotor (`unit.pd.osprey_strike_tiltrotor`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2100 | 58.5 s | 1545 | air_heavy | air_hover | 4.5 c/s | 10 | 0.6 | air |

**Role (bible):** Anti-vehicle attack aircraft that hovers when firing; vulnerable to focused AA.

**Weapons:**
- `osprey_missiles` (air_missile): 93×2 per 1.5 s = **124 dps**, range 6 cells, 7 volleys/sortie

**Rearm (full):** 12 s

#### Reef Patrol Boat (`unit.pd.reef_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 615 | 17 s | 743 | ship_light | naval | 4 c/s | 11 | 0.6 | surface_water |

**Role (bible):** Fast coastal scout and light-surface attacker.

**Weapons:**
- `patrol_mg` (machine_gun): 28×2 per 1 s = **56 dps**, range 6.5 cells

#### Trident Escort (`unit.pd.trident_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2266 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `escort_gun` (naval_gun): 185×1 per 2 s = **92 dps**, range 9 cells
- `escort_aam` (aa_missile): 62×2 per 1.5 s = **83 dps**, range 10 cells
- `escort_torpedo` (torpedo): 258×1 per 6 s = **43 dps**, range 7 cells

#### Tempest Carrier (`unit.pd.tempest_carrier`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: carrier, combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3800 | 105.5 s | 5000 | ship_heavy | naval | 1.5 c/s | 11 | 1.5 | surface_water |

**Role (bible):** Launches short-range strike drones against ground or surface targets; needs escort protection.

**Weapons:** none (support / unarmed).

## Unique subfaction units

#### Outrider Howitzer (`unit.pd.outrider_howitzer`)

*unique subfaction unit — replaces **Breaker Howitzer** in Australia* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1375 | 40.5 s | 710 | light_vehicle | tracked | 1.5 c/s | 8.5 | 0.6 | ground |

**Role (bible):** Long-range mobile artillery with a narrow firing arc and 3-second deployment; weak at close range.

**Weapons:**
- `outrider_shell` (artillery_shell): 186×1 per 3.5 s = **53 dps**, range 18 cells, min 6; deploy 3 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 3}

*Design note:* Narrow firing arc (arc_deg 40) and 6-cell minimum range: weak at close range.

#### Wedge Recon Fighter (`unit.pd.wedge_recon_fighter`)

*unique subfaction unit — replaces **Petrel Fighter** in Australia* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat, detector

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1025 | 28.5 s | 753 | air_light | air_fixed | 7 c/s | 13.8 | 0.5 | air |

**Role (bible):** Detector-equipped fighter with extended sight; lower anti-air damage than Petrel.

**Weapons:**
- `wedge_aam` (aa_missile): 91×1 per 1 s = **91 dps**, range 8 cells, 6 volleys/sortie

**Rearm (full):** 8 s

*Design note:* SPOT_WEDGE aura (6 cells, friendly artillery targets) feeds Forward Fire Control only; carried as params.spot_wedge_radius_cells (no registry kind).

#### Kancil Landing Skimmer (`unit.pd.kancil_landing_skimmer`)

*unique subfaction unit — replaces **Wake Skimmer** in Indonesia* · **T1** · built at **factory** · requires factory · tags: amphibious, combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 490 | 16 s | 552 | light_vehicle | amphibious | 4 c/s | 12 | 0.5 | ground |

**Role (bible):** Fast amphibious light transport and detector. Passengers unload 50% faster; its weapon is weaker than Wake's.

**Weapons:**
- `kancil_mg` (machine_gun): 25×1 per 1.3 s = **19 dps**, range 6 cells

**Abilities:** `amphibious`, `ability.transport.squads2`
  - `ability.transport.squads2`: {"capacity_squads_n": 2, "unload_speed_pct": 150}

#### Island Raider (`unit.pd.island_raider`)

*unique subfaction unit — replaces **Ranger Marine** in Indonesia* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 250 | 9 s | 403 | infantry | foot | 1.6 c/s | 7 | 0.4 | ground |

**Role (bible):** Mobile rifle infantry gaining weapon damage +20% for 6 seconds after disembarking. The effect cannot be refreshed by immediate reboarding.

**Weapons:**
- `raider_rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

**Abilities:** `ability.disembark_buff.default`
  - `ability.disembark_buff.default`: {"duration_s": 6, "damage_bonus_pct": 20, "refresh_on_reboard": false}

*Design note:* Mobile rifle infantry: +6% speed, -5% health versus Ranger Marine; buff numbers from the bible.

#### Shinano Adaptive Tank (`unit.pd.shinano_adaptive_tank`)

*unique subfaction unit — replaces **Tide Tank** in Japan* · **T2** · built at **factory** · requires factory, radar · tags: amphibious, combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1060 | 33 s | 1000 | medium_armor | amphibious | 2 c/s | 9 | 0.6 | ground |

**Role (bible):** Amphibious tank switching in 3 seconds between mobile direct fire and stationary long-range siege fire. Siege mode loses anti-infantry effectiveness.

**Weapons:**
- `shinano_cannon` (tank_cannon): 155×1 per 1.2 s = **129 dps**, range 7 cells, modes: 0
- `shinano_siege_rail` (rail_gun): 399×1 per 4.5 s = **89 dps**, range 11 cells, modes: 1

**Abilities:** `amphibious`, `ability.mode_switch.default`
  - `ability.mode_switch.default`: {"switch_s": 3, "modes": [{"id": "mobile_direct", "slots_n": [0]}, {"id": "siege", "slots_n": [1]}]}

*Design note:* Mode 0 mobile direct fire (tank cannon, full anti-infantry); mode 1 stationary siege (rail gun, 20% vs infantry armour, fires only while stationary).

#### Shogun Drone Carrier (`unit.pd.shogun_drone_carrier`)

*unique subfaction unit — replaces **Tempest Carrier** in Japan* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: carrier, combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3950 | 109.5 s | 5451 | ship_heavy | naval | 1.5 c/s | 11 | 1.5 | surface_water |

**Role (bible):** Advanced carrier switching between surface-strike drones and interceptor drones; only one wing type may operate at a time.

**Weapons:** none (support / unarmed).

**Abilities:** `multirole`
  - `multirole`: {"switch_s": 5, "switch_at_structure_id": "", "modes": [{"id": "strike", "slots_n": []}, {"id": "interceptor", "slots_n": []}]}
  - `ability.carrier.default`: {"wings": [{"id": "strike", "drone_id": "summon.pd.surface_strike_drone", "wing_size_n": 6}, {"id": "interceptor", "drone_id": "summon.pd.interceptor_drone", "wing_size_n": 6}], "replace_s": 14, "launch_range_cells": 14}

*Design note:* One wing type may operate at a time (mode_switch, 5 s wing change).

## Faction structures

- **Tempest Swarm Hub** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Tempest Swarm Hub.
- **Sea Spear Battery** — 1800 cr, 35 s, power -40; health 3400; 170×3 per 6 s, range 13. Long-range missile defense targeting ground vehicles or ships, but not aircraft; vulnerable during reload.

## Superweapon

**Tempest Swarm Hub** — recharge 480 s, warning 10 s.

Launches 24 autonomous strike drones toward a selected 6-cell-radius area. They attack ground and surface targets there for up to 20 seconds before their batteries expire. Drones are individually targetable by AA and their approach direction is visible. Maximum aggregate damage is high, but interception can sharply reduce it.

*Counterplay:* Concentrate overlapping AA near the marked zone, move mobile units out, or destroy the hub during the warning. Drones cannot capture, scout beyond their attack zone or be salvaged.

## Research

- **Expeditionary Maintenance** (T2, 1000 cr, 45 s): Reef Technicians repair 25% faster. Repair credit cost per health restored is unchanged.
- **Integrated Flight Decks** (T3, 1600 cr, 75 s): Airfield rearm time -15%; carrier drone replacement time -15%. Applies to carrier replacements.
- **Forward Fire Control** (T3, 1500 cr, 75 s, subfaction-exclusive): Outriders gain reload interval -10% while their target is within 6 cells of a friendly Wedge Recon Fighter.
- **Distributed Beachheads** (T2, 1000 cr, 45 s, subfaction-exclusive): Reef Technicians gain movement speed +15% and can repair a transport while riding in it, one Technician per transport.
- **Predictive Maintenance** (T3, 1700 cr, 75 s, subfaction-exclusive): Shinano mode changes take 2 seconds; Shogun drone replacement time -20%.

## Support powers

- **Maritime Patrol** (T2, 500 cr, cooldown 90 s): A shootable patrol aircraft reveals and detects a 20-cell-long, 6-cell-wide corridor for 12 seconds. Works over land and water.
- **Expeditionary Workshop** (T3, 900 cr, cooldown 180 s): A shootable aircraft drops a 20-second workshop on clear land or water, repairing friendly vehicles and ships in 5 cells at 1.5% maximum health per second.
- **Joint Landing** (T2, 700 cr, cooldown 180 s, not inherited): For 15 seconds, friendly ground units that disembark from transports take 20% less weapon damage for 6 seconds. Reboarding cannot refresh an existing protection effect.
- **Long Watch** (T2, 600 cr, cooldown 150 s, not inherited): Reveal a 7-cell-radius area for 18 seconds through a high-altitude sensor pass. It reveals terrain and ordinary units but does not detect camouflage.
- **Feint Landing** (T2, 500 cr, cooldown 120 s, not inherited): Create three harmless, non-blocking decoy transports for 25 seconds on scouted land or water. They cannot carry units and are identified by detectors.
- **Precision Window** (T2, 900 cr, cooldown 180 s, not inherited): Friendly aircraft and ships in a 6-cell-radius zone gain weapon damage +20% for 10 seconds, but receive no bonus to sight or survivability.
