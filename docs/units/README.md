# Unit, structure and tech reference

> **Generated** by `python3 tools/py/gen_unit_reference.py` from the bible (`game/data/bible/meridian_factions.json`) and the balance sheets (`game/data/balance/`). Do not edit by hand — change the data and regenerate.

## How to read

- All numbers are **base values before roster modifiers**. At match start the resolver applies (1) faction passive modifiers, (2) subfaction modifiers, (3) research / temporary effects, with the bible's layering rule and floors/caps (cost and build time never below 60 % of base, reload never below 50 %, combined damage resistance never above 50 %).
- Units of measure: distances in **cells** (1 cell = 3 m in the 3D view), time in **seconds** at normal game speed, speed in **cells/second**, cost in **credits**, health in **hit points**.
- **DPS** = damage × hits per volley ÷ reload interval of the unit's best weapon; the damage-type × armor-class matrix (`docs/balance/TAXONOMY.md`) scales it against real targets. **Range** = longest weapon range.
- ★ marks unique subfaction units (they replace a vanilla unit in that roster only). Numbers the bible specifies (structure costs, service-unit costs, research/power costs, tiers, prerequisites) are never overridden; everything else is designed in `docs/balance/FRAMEWORK.md` and tuned later by AI-vs-AI simulation.
- Design status: the numbers were tuned by AI self-play (rounds BAL2 and BAL3: unit sheets inside the fair-cost band, and in a 1,140-match Hard round robin no roster outside 35-65 % wins) and have **not been playtested by humans**.

## Factions

- [North American Peace Corps (NAPC)](napc.md) — Durable combined arms; reliable frontline vehicles and recovery.
- [New European Confederation (NEC)](nec.md) — Precision, sensor networks and deliberate positional warfare.
- [Order of the Levant and Mediterranean (OLM)](olm.md) — Mobile combined arms, concealment and abundant electrical power.
- [Democratic Eurasian Federation (DEF)](def.md) — Industrial volume, artillery saturation and replaceable armored forces.
- [Pacific Dominion (PD)](pd.md) — Amphibious maneuver, naval reach and flexible coastal logistics.
- [Han Empire (HAN)](han.md) — Affordable infantry, unmanned support and vulnerable command links.
- [African Empire (AE)](ae.md) — Recovery, battlefield salvage and practical industrial endurance.
- [South Asian Protectorate (SAP)](sap.md) — Protected advances, resilient defenses and battlefield engineering.

## Shared structures (all factions)

| Structure | Cost | Build | Power | Health | Armor | Footprint | Prerequisites |
|---|---:|---:|---:|---:|---|---|---|
| Headquarters | 0 | — s | 0 | 6000 | fortress | 3×3 | — |
| Generator | 600 | 25 s | +150 | 1200 | building_light | 2×2 | headquarters |
| Refinery | 1800 | 40 s | -30 | 3600 | building_heavy | 3×3 | generator |
| Barracks | 500 | 20 s | -10 | 1000 | building_light | 2×2 | generator |
| Factory | 2000 | 40 s | -40 | 4500 | building_heavy | 3×3 | refinery |
| Dock | 1800 | 40 s | -35 | 3600 | building_heavy | 3×3 | refinery |
| Radar | 1500 | 30 s | -40 | 3000 | building_heavy | 2×2 | factory |
| Airfield | 1600 | 35 s | -40 | 3200 | building_heavy | 6×3 | radar |
| Laboratory | 2500 | 50 s | -60 | 5000 | building_heavy | 3×3 | radar |
| Watchtower | 450 | 15 s | -5 | 900 | building_light | 1×1 | barracks |
| Anti-tank turret | 800 | 20 s | -15 | 1500 | building_heavy | 1×1 | factory |
| AA battery | 900 | 20 s | -20 | 1500 | building_heavy | 2×2 | radar |

## Shared service units

| Unit | Cost | Build | HP | Speed | Notes |
|---|---:|---:|---:|---:|---|
| Engineer | 500 | 18 s | 260 | 1.5 | Captures neutral tech structures and repairs friendly land vehicles or structures. No weapon. Baseline repair rate 1% target maximum health/s, costing 0.5% of the target's paid price/s. Enemy production and superweapons are not capturable in this prototype. |
| Collector | 1400 | 30.5 s | 900 | 2 | One supplied by each completed Refinery; additional Collectors can be purchased. Harvest and unload rules are identical for all rosters unless explicitly changed. |
| Mobile Construction Vehicle | 3000 | 67 s | 2000 | 1.2 | Deploys into a Headquarters to establish another construction area. Slow, unarmed and expensive; no free deployment income. |
| Landing Transport | 900 | 25 s | 1400 | 2.6 | Unarmed amphibious service transport. Carries four infantry squads or two non-amphibious land vehicles, but never another transport or an MCV. Provides a water-crossing option to every roster. |

## All combat units (base values)

### North American Peace Corps

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

### New European Confederation

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

### Order of the Levant and Mediterranean

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

### Democratic Eurasian Federation

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

### Pacific Dominion

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

### Han Empire

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

### African Empire

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

### South Asian Protectorate

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

## Economy constants (from `global.json`)

```json
{
 "start_credits": 7500,
 "start_structure": "headquarters",
 "veterancy_enabled": false,
 "source_start": "bible",
 "collector": {
  "capacity_credits": 600,
  "harvest_pulse_ticks": 1,
  "harvest_credits_per_pulse": 1,
  "unload_pulse_ticks": 1,
  "unload_credits_per_pulse": 6,
  "unload_overhead_ticks": 40,
  "speed_cells_s": 2.0,
  "loaded_speed_pct": 100,
  "health": 900,
  "cost_credits": 1400,
  "build_time_s": 30.5,
  "refinery_unload_slots": 1,
  "deposit_search_radius_cells": 28,
  "source": "cost: bible; rest: ours"
 },
 "derived": {
  "harvest_credits_per_s": 20,
  "unload_credits_per_s": 120,
  "full_load_harvest_s": 30.0,
  "income_by_distance_cells": {
   "6": {
    "cycle_s": 43.0,
    "income_cr_per_min": 837
   },
   "8": {
    "cycle_s": 45.0,
    "income_cr_per_min": 800
   },
   "10": {
    "cycle_s": 47.0,
    "income_cr_per_min": 766
   },
   "12": {
    "cycle_s": 49.0,
    "income_cr_per_min": 735
   },
   "16": {
    "cycle_s": 53.0,
    "income_cr_per_min": 679
   },
   "20": {
    "cycle_s": 57.0,
    "income_cr_per_min": 632
   },
   "24": {
    "cycle_s": 61.0,
    "income_cr_per_min": 590
   },
   "32": {
    "cycle_s": 69.0,
    "income_cr_per_min": 522
   }
  },
  "reference_income_cr_per_min_per_collector": 766,
  "reference_distance_cells": 10,
  "collectors_per_refinery_recommended": 3,
  "refinery_unload_utilisation_at_3_collectors_pct": 32
 },
 "deposit": {
  "credits_per_cell": 600,
  "rich_credits_per_cell": 1200,
  "standard_field_cells": 24,
  "standard_field_credits": 14400,
  "rich_field_cells": 16,
  "rich_field_credits": 19200,
  "regrow": false,
  "start_fields_per_player": 2,
  "start_field_distance_cells": [
   8,
   16
  ],
  "expansion_fields_per_player_min": 2,
  "note": "Finite. A load of 600 empties exactly one cell
```
