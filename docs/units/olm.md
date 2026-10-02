# Order of the Levant and Mediterranean (OLM)

*Keep the wells. Keep the word.*

> Generated from the bible + balance sheets by `tools/py/gen_unit_reference.py`. **Base values before roster modifiers** (cells, seconds, credits, hit points). DPS = damage × hits per volley ÷ reload.

**Doctrine:** Mobile combined arms, concealment and abundant electrical power.  
**Visual direction:** Ivory, copper and deep teal; heat shields, fabric screens and articulated wheels.

## Faction traits (passive modifiers, applied by the resolver)

- Combat infantry and light land vehicles: movement speed +10%, health -10%.
- Generators produce +25% power; this creates no credits.
- Strengths: rapid repositioning, screening and energy-intensive systems. Weaknesses: fragile screens and poor prolonged frontal trades.

## Rosters

### Order of the Levant and Mediterranean / Vanilla — Vanilla

*Mobile combined arms, concealment and abundant electrical power.*

- opening: Use Caravan and Sirocco groups to threaten several routes, screen retreats with Dust Screen, and bring Observers before attempting a siege.

### Saudi Arabia — Solar Directorate

*Energy weapons and power-efficient late-game positions.*

- modifier: Generator output +20% relative to the parent faction.
- modifier: Thermal-beam weapon damage +15%.
- modifier: Land combat vehicle movement speed -10%.
- replaces **Crescent AA** with **Dawn Laser AA**
- replaces **Sunlance Beam Tank** with **Ifrit Prism Tank**
- removes **Beacon Missile Ship** (no replacement)
- loses vanilla-only power **Open Corridor**
- exclusive research: **Thermal Reservoirs** (T3, 1500 cr) — Ifrit and Dawn units gain reload or cooling interval -10%; does not alter Helios.
- exclusive power: **Capacitor Discharge** (T2, 800 cr, 180 s cooldown) — Thermal-beam units and Sunwall defenses in a 6-cell-radius zone deal damage +20% for 10 seconds, then cannot fire for 4 seconds while cooling.
- opening: Build a conventional screen, then Dawn AA and Ifrits. Keep enough mobile Siroccos to prevent opponents bypassing the beam line.

### Algeria — Saharan Corridor Guard

*Fast light vehicles, ambushes and harassment.*

- modifier: Light land vehicle cost -15%.
- modifier: Light land vehicle build time -15%.
- modifier: Light land vehicle health -10%.
- modifier: Tank cost +15%.
- replaces **Caravan APC** with **Dune Rover**
- replaces **Sandglass Mortar** with **Scorpion Rocket Buggy**
- removes **Sunlance Beam Tank** (no replacement)
- loses vanilla-only power **Open Corridor**
- exclusive research: **Distributed Fuel Caches** (T2, 900 cr) — Dune Rovers and Scorpions gain movement speed +10% after 6 seconds out of combat; firing or taking damage ends it.
- exclusive power: **False Convoy** (T2, 500 cr, 120 s cooldown) — Create four visible decoy light vehicles for 25 seconds at a scouted clear location. They have 1 health, no damage, no collision and no capture ability; detectors identify them.
- opening: Raid collectors with Rovers and Needle passengers. Use Scorpions for repeated short attacks rather than prolonged firing lines.

### El-Andalus — Western Straits Compact

*Port defense, durable escorts and infantry holding power.*

- modifier: Ship health +15%.
- modifier: Garrisoned combat infantry weapon damage +20%.
- modifier: Aircraft cost +15%.
- replaces **Wayfarer Guard** with **Gate Guard**
- replaces **Lantern Escort** with **Strait Frigate**
- removes **Sunlance Beam Tank** (no replacement)
- loses vanilla-only power **Open Corridor**
- exclusive research: **Harbor Militia** (T2, 1000 cr) — Gate Guards gain damage +10% within 6 cells of a friendly Factory or Dock; no stacking between buildings.
- exclusive power: **Straits Crossfire** (T2, 800 cr, 180 s cooldown) — Friendly infantry and ships in a selected 6-cell-radius zone gain weapon range +10% and sight +20% for 15 seconds.
- opening: Secure buildings with Gate Guards, then combine Siroccos and Sandglass mortars. On water maps, add escort groups before expensive siege ships.

## All units at a glance (★ = unique subfaction unit)

| Unit | T | Producer | Cost | Build | HP | Armor | Speed | Vision | DPS | Range |
|---|:-:|---|---:|---:|---:|---|---:|---:|---:|---:|
| Wayfarer Guard | 1 | barracks | 250 | 9 s | 384 | infantry | 1.5 | 7 | 52 | 5.5 |
| Needle Team | 1 | barracks | 350 | 12.5 s | 294 | infantry | 1.4 | 7.5 | 59 | 7.5 |
| Mirage Observer | 2 | barracks | 525 | 19 s | 300 | infantry | 1.5 | 11.2 | — | — |
| Caravan APC | 1 | factory | 570 | 18.5 s | 499 | light_vehicle | 3.6 | 12 | 30 | 6 |
| Sirocco Tank | 1 | factory | 820 | 26.5 s | 750 | medium_armor | 2.5 | 9 | 114 | 7 |
| Crescent AA | 2 | factory | 1050 | 31 s | 784 | medium_armor | 2.2 | 10 | 131 | 10 |
| Sandglass Mortar | 2 | factory | 855 | 25 s | 470 | light_vehicle | 2.6 | 9 | 42 | 8.8 |
| Sunlance Beam Tank | 3 | factory | 2400 | 63 s | 3073 | heavy_armor | 1.4 | 8.5 | 200 | 9 |
| Shrike Interceptor | 2 | airfield | 915 | 25.5 s | 686 | air_light | 7.8 | 11 | 98 | 8 |
| Nightjar Strike Drone | 3 | airfield | 1450 | 40.5 s | 637 | air_light | 6.5 | 10 | 294 | 6 |
| Corsair Patrol Boat | 1 | dock | 615 | 17 s | 672 | ship_light | 4 | 11 | 56 | 6.5 |
| Lantern Escort | 2 | dock | 1700 | 47 s | 2156 | ship_heavy | 2.4 | 11 | 88 | 10 |
| Beacon Missile Ship | 3 | dock | 3400 | 94.5 s | 4410 | ship_heavy | 1.6 | 10.5 | 118 | 24 |
| Dawn Laser AA ★ | 2 | factory | 1050 | 31 s | 753 | medium_armor | 2.2 | 10 | 140 | 9 |
| Ifrit Prism Tank ★ | 3 | factory | 2700 | 71 s | 2981 | heavy_armor | 1.4 | 8.5 | 228 | 9 |
| Dune Rover ★ | 1 | factory | 625 | 20 s | 460 | light_vehicle | 4 | 12 | 30 | 6 |
| Scorpion Rocket Buggy ★ | 2 | factory | 830 | 24.5 s | 388 | light_vehicle | 2.6 | 9 | 41 | 11 |
| Gate Guard ★ | 1 | barracks | 260 | 9.5 s | 355 | infantry | 1.3 | 7 | 52 | 5.5 |
| Strait Frigate ★ | 2 | dock | 1800 | 50 s | 2091 | ship_heavy | 2.1 | 11 | 98 | 10 |

## Baseline combat units

#### Wayfarer Guard (`unit.olm.wayfarer_guard`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 250 | 9 s | 384 | infantry | foot | 1.5 c/s | 7 | 0.4 | ground |

**Role (bible):** Mobile general infantry with modest protection.

**Weapons:**
- `wayfarer_rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

#### Needle Team (`unit.olm.needle_team`)

*baseline* · **T1** · built at **barracks** · requires barracks · tags: anti_tank, combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 350 | 12.5 s | 294 | infantry | foot | 1.4 c/s | 7.5 | 0.4 | ground |

**Role (bible):** Anti-vehicle missile infantry; little anti-infantry damage.

**Weapons:**
- `needle_needle_missile` (at_missile): 265×1 per 4.5 s = **59 dps**, range 7.5 cells

#### Mirage Observer (`unit.olm.mirage_observer`)

*baseline* · **T2** · built at **barracks** · requires barracks, radar · tags: combat, detector, ground, infantry, specialist

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 525 | 19 s | 300 | infantry | foot | 1.5 c/s | 11.2 | 0.4 | ground |

**Role (bible):** Unarmed detector and artillery spotter; camouflages after 6 stationary seconds.

**Weapons:** none (support / unarmed).

**Abilities:** `camouflage`, `spotter`
  - `camouflage`: {"delay_s": 6, "needs_stationary": true, "needs_no_attack": true}
  - `spotter`: {"radius_cells": 6, "artillery_range_bonus_pct": 0}

#### Caravan APC (`unit.olm.caravan_apc`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 570 | 18.5 s | 499 | light_vehicle | wheeled | 3.6 c/s | 12 | 0.5 | ground |

**Role (bible):** Light transport, scout and detector; designed for rapid withdrawal.

**Weapons:**
- `caravan_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

#### Sirocco Tank (`unit.olm.sirocco_tank`)

*baseline* · **T1** · built at **factory** · requires factory · tags: combat, ground, land_vehicle, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 820 | 26.5 s | 750 | medium_armor | tracked | 2.5 c/s | 9 | 0.6 | ground |

**Role (bible):** Fast medium tank; less armor than conventional rivals.

**Weapons:**
- `sirocco_cannon` (tank_cannon): 137×1 per 1.2 s = **114 dps**, range 7 cells

#### Crescent AA (`unit.olm.crescent_aa`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 784 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Mobile anti-air missile system and detector.

**Weapons:**
- `crescent_aa_missile` (aa_missile): 98×2 per 1.5 s = **131 dps**, range 10 cells

#### Sandglass Mortar (`unit.olm.sandglass_mortar`)

*baseline* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, light, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 855 | 25 s | 470 | light_vehicle | wheeled | 2.6 c/s | 9 | 0.5 | ground |

**Role (bible):** Light indirect artillery with a short deployment delay and limited range.

**Weapons:**
- `sandglass_mortar` (mortar): 127×1 per 3 s = **42 dps**, range 8.8 cells, min 3; deploy 2 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 2, "pack_s": 2}

#### Sunlance Beam Tank (`unit.olm.sunlance_beam_tank`)

*baseline* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2400 | 63 s | 3073 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Focused thermal beam damages a single target over time; vulnerable during sustained firing.

**Weapons:**
- `sunlance_sunlance_beam` (beam_thermal): 50×1 per 0.2 s = **200 dps**, range 9 cells, ramps +150% over 5 s

#### Shrike Interceptor (`unit.olm.shrike_interceptor`)

*baseline* · **T2** · built at **airfield** · requires airfield, radar · tags: aircraft, anti_air, combat

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 915 | 25.5 s | 686 | air_light | air_fixed | 7.8 c/s | 11 | 0.5 | air |

**Role (bible):** Fast air-superiority fighter with limited endurance.

**Weapons:**
- `shrike_aam` (aa_missile): 98×1 per 1 s = **98 dps**, range 8 cells, 4 volleys/sortie

**Rearm (full):** 8 s

#### Nightjar Strike Drone (`unit.olm.nightjar_strike_drone`)

*baseline* · **T3** · built at **airfield** · requires airfield, radar, laboratory · tags: aircraft, combat, ground_attack, unmanned

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1450 | 40.5 s | 637 | air_light | air_hover | 6.5 c/s | 10 | 0.5 | air |

**Role (bible):** Unmanned precision attacker; one anti-vehicle missile salvo before rearm.

**Weapons:**
- `nightjar_salvo_missile` (air_missile): 147×4 per 2 s = **294 dps**, range 6 cells, 1 volleys/sortie

**Abilities:** `unmanned`

**Rearm (full):** 14 s

#### Corsair Patrol Boat (`unit.olm.corsair_patrol_boat`)

*baseline* · **T1** · built at **dock** · requires dock · tags: combat, scout, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 615 | 17 s | 672 | ship_light | naval | 4 c/s | 11 | 0.6 | surface_water |

**Role (bible):** Fast coastal scout and anti-infantry gunboat.

**Weapons:**
- `corsair_gunboat_mg` (machine_gun): 28×2 per 1 s = **56 dps**, range 6.5 cells

#### Lantern Escort (`unit.olm.lantern_escort`)

*baseline* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1700 | 47 s | 2156 | ship_heavy | naval | 2.4 c/s | 11 | 1 | surface_water |

**Role (bible):** Anti-air, anti-submarine escort and detector.

**Weapons:**
- `lantern_gun` (naval_gun): 176×1 per 2 s = **88 dps**, range 9 cells
- `lantern_aa_missile` (aa_missile): 59×2 per 1.5 s = **79 dps**, range 10 cells
- `lantern_torpedo` (torpedo): 245×1 per 6 s = **41 dps**, range 7 cells

#### Beacon Missile Ship (`unit.olm.beacon_missile_ship`)

*baseline* · **T3** · built at **dock** · requires dock, radar, laboratory · tags: combat, ship, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 3400 | 94.5 s | 4410 | ship_heavy | naval | 1.6 c/s | 10.5 | 1.3 | surface_water |

**Role (bible):** Long-range missile siege ship; weak at close range.

**Weapons:**
- `beacon_bombard` (naval_bombard): 314×3 per 8 s = **118 dps**, range 24 cells, min 6

## Unique subfaction units

#### Dawn Laser AA (`unit.olm.dawn_laser_aa`)

*unique subfaction unit — replaces **Crescent AA** in Saudi Arabia* · **T2** · built at **factory** · requires factory, radar · tags: anti_air, combat, detector, ground, land_vehicle

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1050 | 31 s | 753 | medium_armor | tracked | 2.2 c/s | 10 | 0.6 | ground |

**Role (bible):** Detector with a continuous anti-air laser. Reliable against small drones, weaker against heavily armored aircraft; no ground attack.

**Weapons:**
- `dawn_dawn_laser` (beam_thermal): 35×1 per 0.2 s = **140 dps**, range 9 cells

#### Ifrit Prism Tank (`unit.olm.ifrit_prism_tank`)

*unique subfaction unit — replaces **Sunlance Beam Tank** in Saudi Arabia* · **T3** · built at **factory** · requires factory, radar, laboratory · tags: combat, ground, land_vehicle, siege, tank

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 2700 | 71 s | 2981 | heavy_armor | tracked | 1.4 c/s | 8.5 | 0.8 | ground |

**Role (bible):** Deploys in 3 seconds to focus a stronger anti-structure beam. Must remain stationary and maintain line of sight; no bouncing beams.

**Weapons:**
- `ifrit_prism_beam` (beam_thermal): 57×1 per 0.2 s = **228 dps**, range 9 cells, deploy 3 s; ramps +150% over 5 s

**Abilities:** `deployable_mode`
  - `deployable_mode`: {"deploy_s": 3, "pack_s": 3, "immobile": true}

#### Dune Rover (`unit.olm.dune_rover`)

*unique subfaction unit — replaces **Caravan APC** in Algeria* · **T1** · built at **factory** · requires factory · tags: combat, detector, ground, land_vehicle, light, scout, transport

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 625 | 20 s | 460 | light_vehicle | wheeled | 4 c/s | 12 | 0.5 | ground |

**Role (bible):** Fast light transport and detector. Camouflages after 6 seconds without firing even while moving, but detection or taking damage reveals it for 6 seconds.

**Weapons:**
- `dune_mg` (machine_gun): 30×1 per 1 s = **30 dps**, range 6 cells

**Abilities:** `camouflage`
  - `camouflage`: {"delay_s": 6, "needs_stationary": false, "moving_ok": true, "needs_no_attack": true, "reveal_on_fire": true, "reveal_on_damage": true, "reveal_s": 6}

#### Scorpion Rocket Buggy (`unit.olm.scorpion_rocket_buggy`)

*unique subfaction unit — replaces **Sandglass Mortar** in Algeria* · **T2** · built at **factory** · requires factory, radar · tags: artillery, combat, ground, land_vehicle, light, siege

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 830 | 24.5 s | 388 | light_vehicle | wheeled | 2.6 c/s | 9 | 0.5 | ground |

**Role (bible):** Light artillery vehicle firing a short rocket salvo before a long reload; no deployment delay, fragile chassis.

**Weapons:**
- `scorpion_rocket_salvo` (rocket_barrage): 67×4 per 6.5 s = **41 dps**, range 11 cells, min 3.5

#### Gate Guard (`unit.olm.gate_guard`)

*unique subfaction unit — replaces **Wayfarer Guard** in El-Andalus* · **T1** · built at **barracks** · requires barracks · tags: combat, ground, infantry

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 260 | 9.5 s | 355 | infantry | foot | 1.3 c/s | 7 | 0.4 | ground |

**Role (bible):** Shield-equipped infantry taking 25% less frontal bullet damage. Slower than Wayfarers; shields do not stop blasts or attacks from behind.

**Weapons:**
- `gate_shield_rifle` (small_arms): 26×2 per 1 s = **52 dps**, range 5.5 cells

**Abilities:** `shield_front`
  - `shield_front`: {"arc_deg": 120, "reduction_pct": 25, "resist_groups": ["bullet"]}

#### Strait Frigate (`unit.olm.strait_frigate`)

*unique subfaction unit — replaces **Lantern Escort** in El-Andalus* · **T2** · built at **dock** · requires dock, radar · tags: anti_air, anti_submarine, combat, detector, ship

| Cost | Build | Health | Armor | Move class | Speed | Vision | Radius | Layer |
|---:|---:|---:|---|---|---:|---:|---:|---|
| 1800 | 50 s | 2091 | ship_heavy | naval | 2.1 c/s | 11 | 1 | surface_water |

**Role (bible):** Detector and anti-air/anti-submarine escort with stronger short-range surface guns, at the cost of slower movement.

**Weapons:**
- `strait_gun` (naval_gun): 197×1 per 2 s = **98 dps**, range 8.5 cells
- `strait_aa_missile` (aa_missile): 66×2 per 1.5 s = **88 dps**, range 10 cells
- `strait_torpedo` (torpedo): 274×1 per 6 s = **46 dps**, range 7 cells

## Faction structures

- **Helios Reflector** — 5000 cr, 90 s, power -200; health 7000, power -200. Charges Helios Reflector.
- **Sunwall Projector** — 1800 cr, 35 s, power -40; health 3300; 33×1 per 0.2 s, range 10. Continuous thermal anti-vehicle beam; excellent against slow targets, poor against infantry swarms.

## Superweapon

**Helios Reflector** — recharge 480 s, warning 10 s.

A surviving orbital mirror focuses sunlight along a player-selected line 16 cells long and 3 cells wide. The beam traverses the line over 12 seconds, damaging ground units, ships and structures with strong thermal damage. It cannot track units after the line is committed.

*Counterplay:* Leave the marked line, attack along its flanks, and spread structures. Beam-resistant upgrades reduce its damage; smoke does not.

## Research

- **Thermal Shrouds** (T2, 900 cr, 45 s): Light land vehicles gain sight +10% and take 10% less thermal-beam damage.
- **Optical Mesh** (T3, 1500 cr, 75 s): Caravan APCs and their replacements camouflage after 6 seconds stationary without attacking. Moving or firing reveals them.
- **Thermal Reservoirs** (T3, 1500 cr, 75 s, subfaction-exclusive): Ifrit and Dawn units gain reload or cooling interval -10%; does not alter Helios.
- **Distributed Fuel Caches** (T2, 900 cr, 45 s, subfaction-exclusive): Dune Rovers and Scorpions gain movement speed +10% after 6 seconds out of combat; firing or taking damage ends it.
- **Harbor Militia** (T2, 1000 cr, 45 s, subfaction-exclusive): Gate Guards gain damage +10% within 6 cells of a friendly Factory or Dock; no stacking between buildings.

## Support powers

- **Dust Screen** (T2, 400 cr, cooldown 90 s): A 6-cell-radius smoke zone lasts 12 seconds. All ground units inside, friendly or enemy, take 30% less direct-fire weapon damage; artillery and area blasts are unaffected.
- **Mobile Workshop** (T3, 900 cr, cooldown 180 s): Place a visible, destructible repair drone station on clear ground. It repairs friendly vehicles in 5 cells at 2% maximum health per second for 15 seconds; no stacking.
- **Open Corridor** (T2, 650 cr, cooldown 150 s, not inherited): Friendly land vehicles in a selected 6-cell-radius zone gain movement speed +25% for 12 seconds. Units must be in the zone when activated.
- **Capacitor Discharge** (T2, 800 cr, cooldown 180 s, not inherited): Thermal-beam units and Sunwall defenses in a 6-cell-radius zone deal damage +20% for 10 seconds, then cannot fire for 4 seconds while cooling.
- **False Convoy** (T2, 500 cr, cooldown 120 s, not inherited): Create four visible decoy light vehicles for 25 seconds at a scouted clear location. They have 1 health, no damage, no collision and no capture ability; detectors identify them.
- **Straits Crossfire** (T2, 800 cr, cooldown 180 s, not inherited): Friendly infantry and ships in a selected 6-cell-radius zone gain weapon range +10% and sight +20% for 15 seconds.
