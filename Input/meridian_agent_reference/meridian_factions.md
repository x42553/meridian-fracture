# Meridian Fracture - agent reference

Schema version: `1.0.0`. Design version: `0.1`. Status: **draft, not playtested**. This file is generated from `meridian_factions.json`; edit JSON first and regenerate this view.

## Agent contract

- Use stable IDs as keys; display names may change.
- Read the chosen roster under `rosters` and use its `resolved` lists. Do not re-add replaced units or the vanilla-only third power.
- Numeric parent and subfaction modifiers are encoded once in `modifiers`. Source prose restates those rules; never count it as an extra bonus.
- Treat `null` as unspecified. Do not invent costs, health, weapons or unit build times.
- Treat conditional abilities, research effects and support-power effects as normative prose that still needs implementation design.
- Apply explicit terrain/state conditions. A conditional target list does not make a modifier unconditional.
- Preserve established lore and balance values unless the user requests a design change.
- After editing, rebuild affected `resolved` records, run `validate_reference.py`, then run `render_markdown.py`.

## Setting
The year is 2086. The Meridian Network once linked regional power grids, freight routing, desalination controls and disaster forecasting. It did not create energy: it made a fragile, unequal world depend on coordinated delivery. During the Long Blackout of 2057, cascading technical failures and competing emergency shutdowns broke that coordination. No faction can prove whether the first failure was sabotage, negligence or an attempt to prevent something worse.

Over three decades, reconstruction commands hardened into eight rival blocs. Meridian's surviving regional control vaults can now reconnect major industrial corridors. Whoever governs those connections can restore livelihoods, ration access or shut rivals out. The war is fought for substations, ports, salvage fields, manufacturing cities and the right to decide who gets power first.

Each faction offers a credible public good and an institutional danger. None is a stand-in for the moral character of a present-day country, religion or population. National names identify fictional successor commands; their military doctrines come from reconstruction history. All names and technology below are proposals, not canon that the game must retain.

| Period | Event | Description |
| --- | --- | --- |
| 2039-2056 | Meridian construction | A patchwork of national projects becomes an interdependent energy and logistics system. |
| 2057 | The Long Blackout | Nine months of cascading regional failures trigger evacuations, rationing and emergency rule. |
| 2058-2074 | The reconstruction wars | Convoy services, local governments and surviving militaries form new political alliances. |
| 2075-2085 | The corridor settlement | Eight blocs negotiate temporary transit rights while rebuilding military industry. |
| 2086 | The failed restart | A disputed restart at Meridian Vault Nine cuts power to several neutral cities. Every bloc mobilizes; the responsible decision remains contested. |

## Roster index

| ID | Faction | Roster | Doctrine |
| --- | --- | --- | --- |
| roster.napc.vanilla | North American Peace Corps | North American Peace Corps / Vanilla | Durable combined arms; reliable frontline vehicles and recovery. |
| roster.napc.usa | North American Peace Corps | USA | Sustained air operations and precision strikes. |
| roster.napc.canada | North American Peace Corps | Canada | Amphibious armor and protected transport; useful on rivers and ordinary land. |
| roster.napc.mexico | North American Peace Corps | Mexico | Affordable assault infantry with strong urban pressure. |
| roster.nec.vanilla | New European Confederation | New European Confederation / Vanilla | Precision, sensor networks and deliberate positional warfare. |
| roster.nec.nordics | New European Confederation | Nordics | Reconnaissance, mobile missiles and coastal denial. |
| roster.nec.eurocorps | New European Confederation | Eurocorps | Expensive armored formations and siege breakthroughs. |
| roster.nec.alpine_brotherhood | New European Confederation | Alpine Brotherhood | Fortified infantry, compact artillery positions and repairable defenses. |
| roster.olm.vanilla | Order of the Levant and Mediterranean | Order of the Levant and Mediterranean / Vanilla | Mobile combined arms, concealment and abundant electrical power. |
| roster.olm.saudi_arabia | Order of the Levant and Mediterranean | Saudi Arabia | Energy weapons and power-efficient late-game positions. |
| roster.olm.algeria | Order of the Levant and Mediterranean | Algeria | Fast light vehicles, ambushes and harassment. |
| roster.olm.el_andalus | Order of the Levant and Mediterranean | El-Andalus | Port defense, durable escorts and infantry holding power. |
| roster.def.vanilla | Democratic Eurasian Federation | Democratic Eurasian Federation / Vanilla | Industrial volume, artillery saturation and replaceable armored forces. |
| roster.def.russia | Democratic Eurasian Federation | Russia | Slow armored assaults with active protection. |
| roster.def.kazakhstan | Democratic Eurasian Federation | Kazakhstan | Fast reconnaissance and mobile missile warfare. |
| roster.def.north_korea | Democratic Eurasian Federation | North Korea | Durable infantry, prepared positions and decoys. |
| roster.pd.vanilla | Pacific Dominion | Pacific Dominion / Vanilla | Amphibious maneuver, naval reach and flexible coastal logistics. |
| roster.pd.australia | Pacific Dominion | Australia | Long-range expeditionary artillery backed by reconnaissance aircraft. |
| roster.pd.indonesia | Pacific Dominion | Indonesia | Transport assaults, inexpensive marines and raids across several routes. |
| roster.pd.japan | Pacific Dominion | Japan | Expensive precision systems, adaptable armor and advanced carriers. |
| roster.han.vanilla | Han Empire | Han Empire / Vanilla | Affordable infantry, unmanned support and vulnerable command links. |
| roster.han.china | Han Empire | China | Heavy armor and stronger local command coverage. |
| roster.han.vietnam | Han Empire | Vietnam | Concealed infantry and amphibious rocket raids. |
| roster.han.cambodia | Han Empire | Cambodia | Drone sustain, field repair and economical support systems. |
| roster.ae.vanilla | African Empire | African Empire / Vanilla | Recovery, battlefield salvage and practical industrial endurance. |
| roster.ae.nigeria | African Empire | Nigeria | Fast mobilization, infantry presence and protective drone support. |
| roster.ae.kongo | African Empire | Kongo | Amphibious transport, durable infantry and concealed recovery teams. |
| roster.ae.south_africa | African Empire | South Africa | Long-range ground weapons and expensive precision vehicles. |
| roster.sap.vanilla | South Asian Protectorate | South Asian Protectorate / Vanilla | Protected advances, resilient defenses and battlefield engineering. |
| roster.sap.india | South Asian Protectorate | India | Heavy protected pushes supported by economical power infrastructure. |
| roster.sap.thailand | South Asian Protectorate | Thailand | Amphibious infantry assaults and mobile defense. |
| roster.sap.pakistan | South Asian Protectorate | Pakistan | Long-range missile artillery and concealed forward observation. |

## Shared rules

### rule.design.roster_selection | Roster selection

Choose one of 32 playable rosters before the match: 8 vanilla factions or one of their 24 subfactions. A subfaction inherits its parent faction's traits, structures, service units, two shared upgrades, two shared powers and superweapon. It replaces exactly two combat units, loses one additional combat unit, gains one exclusive upgrade, and replaces the vanilla-only third power with its own. You cannot mix subfaction packages.

### rule.design.economy | Economy

One spendable resource: credits, earned by Collectors delivering salvage from designated deposits to Refineries. Power is a separate capacity budget, not currency. No faction needs a second harvest resource. Suggested starting preset: one deployed HQ and 7,500 credits; medium game speed; no veterancy in the first balance prototype.

### rule.design.technology | Technology

T1 is the opening roster. Radar unlocks T2. Radar plus Laboratory unlock T3. A unit always needs its listed producer as well. No faction needs a Dock to unlock land or air technology; every roster is playable on a land-only map.

### rule.design.production | Production

Each Barracks, Factory, Airfield and Dock has one independent queue. Research uses one player-wide queue. Building construction uses one player-wide queue. Additional production structures add queues, not hidden speed bonuses. A replaced unit cannot also be built.

### rule.design.research | Research

Upgrades cost the listed credits and take 45 seconds at T2 or 75 seconds at T3. T2 research requires an intact Radar; T3 research requires Radar and Laboratory. Completed upgrades persist if those buildings are lost. Losing a tech prerequisite pauses dependent unfinished unit and research orders until rebuilt.

### rule.design.power_loss | Power loss

During a shortage, normal production and research progress at 50% speed; powered defenses and Relay bonuses stop. Powered Radar/Laboratory support powers cannot activate. Superweapon recharge pauses. Existing units and completed upgrades continue to work. SAP defense reserves are the stated exception, not a second resource.

### rule.design.scope_of_modifiers | Scope of modifiers

Combat-unit modifiers apply to the listed combat roster, including its support specialists, but not the four shared service units unless explicitly stated. Structure modifiers apply only to the named structure class. Transport bonuses include any unit explicitly tagged Transport. Units retain role tags when replaced unless the replacement explicitly changes role.

### rule.design.how_percentages_combine | How percentages combine

Apply three layers: base specification, then parent-faction modifiers, then subfaction modifiers, then research/temporary effects. Within a layer, changes to the same stat add; layers multiply. Example: parent vehicle health +10% and subfaction vehicle health -10% yield 1.10 x 0.90 = 0.99 of the base health. Bonuses with identical sources never stack.

### rule.design.caps_and_interpretation | Caps and interpretation

Final purchase cost and build time cannot fall below 60% of the base specification. Final reload interval cannot fall below 50%. Combined damage resistance cannot reduce incoming weapon damage by more than 50%, except a successful projectile interception which removes that projectile. Build time -20% means 0.80 times the duration; it is not the same as production progressing 20% faster.

### rule.design.prototype_boundary | Prototype boundary

The percentages, power prices and timings are initial tuning targets. The bible defines roles and prerequisites, not final weapon damage, armor tables, model counts, pathfinding or unit prices. Each unique unit needs its own base stat specification; replacing a unit does not imply identical stats.

### rule.combat.support_power_access | Support-power access

Each roster has exactly three support powers: two inherited powers and one vanilla-only or subfaction-specific power. T2 powers require a powered Radar; T3 powers require powered Radar and Laboratory. Powers cost credits per use, have separate cooldowns in seconds, and are ready when first unlocked. Rebuilding a prerequisite never resets a cooldown.

### rule.combat.targeting_and_warnings | Targeting and warnings

Reconnaissance powers may target any map location. Other support powers need current vision unless their text explicitly supplies reconnaissance. Superweapons may target previously explored terrain without current vision. Strategic warning zones are visible to affected players and cannot be hidden by fog or decoys.

### rule.combat.superweapon_control | Superweapon control

A strategic structure starts empty and charges only with enough power and intact Radar/Laboratory. One charge may be stored; no stockpiling. The full recharge starts at activation. Destruction or EMP shutdown of the launcher during its warning cancels the attack without refunding the charge; an ordinary power shortage after activation does not cancel it. Ordinary AA cannot intercept strategic attacks except the explicitly shootable Tempest drones.

### rule.combat.damage_and_area_notation | Damage and area notation

One cell means one ordinary terrain tile. A radius is measured from the marked center; all times are real-time seconds at normal speed. Damage-bearing area attacks can hurt friendlies. Aurora affects enemies only; summoned attackers select enemies only. Support buffs affect friendlies unless the text explicitly says otherwise.

### rule.combat.interception_and_strategic_packets | Interception and strategic packets

For Trident, each Atlas rod, Perun core/ring blast, Horizon impact, Tempest drone hit and Dragonfall engine shot is one impact packet. Eight charges reduce one packet by 50%. Fewer than eight cannot reduce it. Helios and Aurora bypass Trident as beam and EMP effects. All reductions still obey the overall 50% resistance cap.

### rule.combat.concealment_and_electronic_warfare | Concealment and electronic warfare

Camouflaged units are revealed within 5 cells of a detector unless a different radius is listed. Firing, taking damage or the specific ability's movement restriction also reveals them. Detector vehicles, every T2 escort and basic Watchtowers prevent concealment from becoming an uncounterable opening. EMP never changes ownership and never instantly kills an aircraft.

### rule.combat.suppression_cover_and_smoke | Suppression, cover and smoke

Suppression triggers after three designated suppressive hits within 2 seconds, reducing infantry movement by 25% for 3 seconds after the last hit. Fortress Guard fire and Watchtower fire are suppressive; other weapons are not unless later specified. Portable cover takes 4 seconds, lasts 45 seconds, allows one piece per builder and provides 20% bullet resistance unless stated otherwise. Marked civilian garrisons hold four infantry squads. Smoke uses the two-sided Dust Screen rule.

### rule.combat.transports_aircraft_and_repairs | Transports, aircraft and repairs

Combat transports normally carry two infantry squads and cannot shoot with their passengers' weapons. Okapi carries three squads and Leviathan four; Kancil, Beaver, Naga and other APCs carry two. Aircraft need powered Airfield pads to rearm; carriers replenish only their own drones. Heal and repair auras from the same source do not stack. Field repair stations cannot repair themselves.

### rule.combat.role_tags | Role tags

Light means APC/scout chassis plus Sandglass, Scorpion and Reed artillery. Tank means direct-fire armored land combat units, including siege tanks, Ifrit, Kiln and Gaj, but not Dragon/Long command walkers or Leviathan transports. Artillery means indirect ground launchers, not direct-fire siege tanks, ships or aircraft. Unmanned means Firefly, Nest/Reed, Swallow, Silkwing, Nightjar and carrier-launched drones; not crewed carriers or temporary superweapon units.

### rule.combat.submarines_and_wrecks | Submarines and wrecks

Boreal Missile Submarines camouflage underwater and surface for 8 seconds when firing. Detectors reveal them; only anti-submarine weapons can target them underwater, while strategic blast damage still applies. Enemy land combat-vehicle wrecks persist for 60 seconds unless destroyed or salvaged; only the African Empire can turn them into credits. No salvage from friendly fire, deliberate scuttling or summons.

## Mechanical conventions

```json
{
  "currency": "credits",
  "distance_unit": "terrain_cell",
  "duration_unit": "seconds_at_normal_speed",
  "tier_requirements": {
    "1": [],
    "2": [
      "structure.shared.radar"
    ],
    "3": [
      "structure.shared.radar",
      "structure.shared.laboratory"
    ]
  },
  "research_time_seconds_by_tier": {
    "2": 45,
    "3": 75
  },
  "starting_preset": {
    "structure_id": "structure.shared.headquarters",
    "credits": 7500,
    "veterancy_enabled": false
  },
  "modifier_order": [
    "base_specification",
    "parent_faction",
    "subfaction",
    "research_and_temporary_effects"
  ],
  "modifier_formula": "base_value * product_over_layers(1 + sum(applicable_delta_percent_in_layer) / 100)",
  "floors_as_fraction_of_base": {
    "cost_credits": 0.6,
    "build_time_seconds": 0.6,
    "reload_interval_seconds": 0.5
  },
  "maximum_combined_damage_resistance_fraction": 0.5,
  "interception_exception": "Successful ordinary projectile interception removes the projectile; strategic impact packets have the specified partial-reduction rules.",
  "prerequisite_semantics": "All IDs in requires_all_structure_ids must be present. Unit production also requires its producer, included in that list. Power activation adds operational/power conditions.",
  "power_shortage_production_and_research_rate_multiplier": 0.5,
  "service_units_excluded_from_combat_modifiers": true,
  "no_same_source_stacking": true
}
```

## Building registry

| ID / name | Credits | Power supply delta | Build seconds | Prerequisites / conditions | Function |
| --- | --- | --- | --- | --- | --- |
| structure.shared.headquarters / Headquarters | 0 | 0 | unspecified | ;  | Construction anchor; 8-cell build radius. A deployed starting HQ is free. |
| structure.shared.generator / Generator | 600 | 150 | 25 | structure.shared.headquarters;  | Provides power; construction 25 s. |
| structure.shared.refinery / Refinery | 1800 | -30 | 40 | structure.shared.generator;  | Includes one Collector on completion; 40 s. |
| structure.shared.barracks / Barracks | 500 | -10 | 20 | structure.shared.generator;  | Produces infantry and Engineers; 20 s. |
| structure.shared.factory / Factory | 2000 | -40 | 40 | structure.shared.refinery;  | Produces land vehicles and MCVs; 40 s. |
| structure.shared.dock / Dock | 1800 | -35 | 40 | structure.shared.refinery; Valid shoreline placement. | Produces ships and Landing Transports; 40 s. |
| structure.shared.radar / Radar | 1500 | -40 | 30 | structure.shared.factory;  | Unlocks T2, Airfield and first powers; 30 s. |
| structure.shared.airfield / Airfield | 1600 | -40 | 35 | structure.shared.radar;  | Produces and services aircraft; four pads; 35 s. |
| structure.shared.laboratory / Laboratory | 2500 | -60 | 50 | structure.shared.radar;  | Unlocks T3, advanced defenses and superweapon; 50 s. |
| structure.shared.watchtower / Watchtower | 450 | -5 | 15 | structure.shared.barracks;  | Anti-infantry; detector radius 4; 15 s. |
| structure.shared.anti_tank_turret / Anti-tank turret | 800 | -15 | 20 | structure.shared.factory;  | Direct-fire anti-vehicle defense; 20 s. |
| structure.shared.aa_battery / AA battery | 900 | -20 | 20 | structure.shared.radar;  | Anti-air defense; detector radius 5; 20 s. |
| structure.napc.atlas_kinetic_array / Atlas Kinetic Array | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Atlas Kinetic Array. |
| structure.napc.bulwark_cannon / Bulwark Cannon | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Long-range anti-vehicle cannon; slow traverse and poor infantry damage. |
| structure.nec.aurora_microwave_array / Aurora Microwave Array | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Aurora Microwave Array. |
| structure.nec.lance_rail_emplacement / Lance Rail Emplacement | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Very long-range single-target anti-armor defense; minimal splash and a long reload. |
| structure.nec.relay / Relay | 600 | -20 | unspecified | structure.shared.radar; Normal construction radius; does not extend it. | Requires Radar; consumes 20 power. Provides the 6-cell networked-fire zone. It must be placed in normal construction range and does not extend that range. |
| structure.olm.helios_reflector / Helios Reflector | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Helios Reflector. |
| structure.olm.sunwall_projector / Sunwall Projector | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Continuous thermal anti-vehicle beam; excellent against slow targets, poor against infantry swarms. |
| structure.def.perun_missile_complex / Perun Missile Complex | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Perun Missile Complex. |
| structure.def.citadel_mortar / Citadel Mortar | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Armored indirect-fire defense; minimum range makes it vulnerable to close attacks. |
| structure.pd.tempest_swarm_hub / Tempest Swarm Hub | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Tempest Swarm Hub. |
| structure.pd.sea_spear_battery / Sea Spear Battery | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Long-range missile defense targeting ground vehicles or ships, but not aircraft; vulnerable during reload. |
| structure.han.dragonfall_field_foundry / Dragonfall Field Foundry | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Dragonfall Field Foundry. |
| structure.han.dragon_tooth_launcher / Dragon Tooth Launcher | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Short salvos of guided anti-vehicle missiles; powerful burst, vulnerable between salvos. |
| structure.ae.horizon_mass_driver / Horizon Mass Driver | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Horizon Mass Driver. |
| structure.ae.forge_cannon / Forge Cannon | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Armored rapid-cycling anti-vehicle turret; shorter range than rail defenses. |
| structure.sap.trident_interception_array / Trident Interception Array | 5000 | -200 | 90 | structure.shared.radar, structure.shared.laboratory; Maximum one strategic structure per player. | Charges Trident Interception Array. |
| structure.sap.bastion_missile_tower / Bastion Missile Tower | 1800 | -40 | 35 | structure.shared.radar, structure.shared.laboratory;  | Durable anti-vehicle missile defense with strong burst damage and a long reload; no anti-air attack. |

The starting Headquarters is supplied. Other Headquarters deploy from an MCV; the deployment edge is separate from building prerequisites. Positive power supplies capacity, negative power consumes it.

## Shared service units

### unit.shared.engineer | Engineer

Requires `structure.shared.barracks`. Cost: 500 credits.

Captures neutral tech structures and repairs friendly land vehicles or structures. No weapon. Baseline repair rate 1% target maximum health/s, costing 0.5% of the target's paid price/s. Enemy production and superweapons are not capturable in this prototype.

### unit.shared.collector | Collector

Requires `structure.shared.refinery`. Cost: 1400 credits.

One supplied by each completed Refinery; additional Collectors can be purchased. Harvest and unload rules are identical for all rosters unless explicitly changed.

### unit.shared.mobile_construction_vehicle | Mobile Construction Vehicle

Requires `structure.shared.factory`, `structure.shared.radar`. Cost: 3000 credits.

Deploys into a Headquarters to establish another construction area. Slow, unarmed and expensive; no free deployment income.

### unit.shared.landing_transport | Landing Transport

Requires `structure.shared.dock`. Cost: 900 credits.

Unarmed amphibious service transport. Carries four infantry squads or two non-amphibious land vehicles, but never another transport or an MCV. Provides a water-crossing option to every roster.

## faction.napc | North American Peace Corps

*Hold the line. Bring them home.*

After the Long Blackout, North American evacuation commands became the only institutions able to keep continental supply routes open. Their emergency charter hardened into the North American Peace Corps, a military reconstruction alliance rather than the historical civilian organization. Its elected Assembly promises to reopen the Meridian Network under public supervision. Generals argue that the network must first be secured by force. Communities grateful for restored power increasingly question why temporary military administrations never leave.

**Doctrine:** Durable combined arms; reliable frontline vehicles and recovery.

**Visual direction:** Olive, cream and rescue orange; broad hulls, modular armor, visible crew cabins.

### Inherited traits
- Land combat vehicles: health +10%, purchase cost +10%.
- Factory service apron: friendly land combat vehicles within 5 cells recover 1% maximum health per second, up to 75%, after 6 seconds without dealing or taking damage. Multiple aprons do not stack.
- Strengths: dependable armor, repair efficiency, clear combined-arms roles. Weaknesses: expensive vehicle losses and limited concealment.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.napc.01 | parent_faction | health | +10 | selector.land_combat_vehicles | Land combat vehicles: health +10%, purchase cost +10%. |
| modifier.napc.02 | parent_faction | cost_credits | +10 | selector.land_combat_vehicles | Land combat vehicles: health +10%, purchase cost +10%. |

### roster.napc.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.napc.rifle_squad / Rifle Squad | 1 | structure.shared.barracks | General infantry; good against infantry, weak against armor. |
| unit.napc.javelin_team / Javelin Team | 1 | structure.shared.barracks | Stationary-firing anti-tank missiles; vulnerable while repositioning. |
| unit.napc.combat_medic / Combat Medic | 2 | structure.shared.barracks, structure.shared.radar | Unarmed infantry healer; cannot repair vehicles. |
| unit.napc.pathfinder_apc / Pathfinder APC | 1 | structure.shared.factory | Light transport, scout and detector; loses to tanks. |
| unit.napc.guardian_tank / Guardian Tank | 1 | structure.shared.factory | Conventional medium tank; main frontline unit. |
| unit.napc.sentinel_aa / Sentinel AA | 2 | structure.shared.factory, structure.shared.radar | Dedicated mobile anti-air and detector; poor ground weapon. |
| unit.napc.paladin_howitzer / Paladin Howitzer | 2 | structure.shared.factory, structure.shared.radar | Indirect siege artillery; must deploy for 3 seconds. |
| unit.napc.bastion_heavy_tank / Bastion Heavy Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Slow twin-gun breakthrough tank; easily outmaneuvered. |
| unit.napc.falcon_interceptor / Falcon Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Air-superiority fighter; no ground attack. |
| unit.napc.titan_gunship / Titan Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Armored hovering anti-vehicle aircraft; vulnerable to concentrated AA. |
| unit.napc.riverwatch_patrol_boat / Riverwatch Patrol Boat | 1 | structure.shared.dock | Cheap anti-infantry and light-surface patrol craft. |
| unit.napc.aegis_frigate / Aegis Frigate | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.napc.liberty_arsenal_ship / Liberty Arsenal Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Long-range land bombardment; depends on escorts. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.napc.bulwark_cannon`, `structure.napc.atlas_kinetic_array`.

### Inherited research

**research.napc.adaptive_plating | Adaptive Plating** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Land combat vehicles take 10% less explosive damage. Does not reduce beam, rail or bullet damage.

**research.napc.joint_tactical_links | Joint Tactical Links** - T3; 1600 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Sentinel AA and Aegis Frigates gain weapon range +10% while within 6 cells of a friendly Rifle Squad, Javelin Team or their replacements.

### Inherited support powers

**power.napc.uav_sweep | UAV Sweep** - T2; 500 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

A shootable reconnaissance UAV circles a 7-cell-radius area for 12 seconds, revealing terrain and detecting concealed units.

**power.napc.field_repair_drop | Field Repair Drop** - T3; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

A shootable cargo aircraft delivers a repair station. It repairs friendly land vehicles in 5 cells by 2% maximum health per second for 10 seconds; stations do not stack.

### Vanilla-only third power

**power.napc.combined_arms_window | Combined Arms Window** - T2; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 15 seconds, friendly infantry, land vehicles and aircraft in a selected 6-cell-radius zone deal 10% more weapon damage. Ships and structures receive no bonus.

### superweapon.napc.atlas_kinetic_array | Atlas Kinetic Array

Launcher: `structure.napc.atlas_kinetic_array`. Recharge: 480 seconds. Warning: 10 seconds. Starts empty; maximum one stored charge.

A surviving orbital magazine releases three guided kinetic penetrators at a selected point and two points 3 cells to either side. Each has a 2-cell damage radius. It is strongest against clustered heavy vehicles and key buildings; the gaps and long warning reward dispersal.

**Counterplay:** Move valuable units between the impact circles, spread essential buildings, or destroy the control structure before the warning expires.

**Vanilla opening:** Rifle Squad and Pathfinder scout first; two Guardians secure the first expansion. Add Sentinel AA before committing to Paladins. Preserve damaged vehicles instead of trading them.

**Fight this faction:** Raid collectors while the main army repairs, attack from several directions, and use cheaper anti-tank units to punish heavy-vehicle concentration.

### roster.napc.usa | USA - Air Mobility Command

Parent: `roster.napc.vanilla`.

The continental airlift service rebuilt scattered cities long before roads reopened. Its commanders believe control of the sky is the only humane way to shorten a war; critics see a doctrine that can leave occupied territory without enough troops to hold it.

**Doctrine:** Sustained air operations and precision strikes.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.napc.usa.01 | subfaction | cost_credits | -15 | selector.aircraft | Aircraft cost -15%. |
| modifier.napc.usa.02 | subfaction | rearm_time_seconds | -20 | selector.aircraft | Aircraft rearm time -20%. |
| modifier.napc.usa.03 | subfaction | build_time_seconds | +15 | selector.land_combat_vehicles | Land combat vehicle build time +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.napc.falcon_interceptor | unit.napc.raptor_multirole_fighter |
| unit.napc.titan_gunship | unit.napc.condor_stealth_bomber |

**Removed without replacement:** `unit.napc.bastion_heavy_tank`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.napc.raptor_multirole_fighter / Raptor Multirole Fighter | 2 | structure.shared.airfield, structure.shared.radar | Switches between anti-air and anti-vehicle missile loads at an Airfield. Cannot carry both; less effective in air combat than a dedicated Falcon. |
| unit.napc.condor_stealth_bomber / Condor Stealth Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Camouflages after 6 seconds without attacking. One heavy anti-structure bomb per sortie; slow rearm and weak protection when detected. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.napc.rifle_squad / Rifle Squad | 1 | structure.shared.barracks |
| unit.napc.javelin_team / Javelin Team | 1 | structure.shared.barracks |
| unit.napc.combat_medic / Combat Medic | 2 | structure.shared.barracks, structure.shared.radar |
| unit.napc.pathfinder_apc / Pathfinder APC | 1 | structure.shared.factory |
| unit.napc.guardian_tank / Guardian Tank | 1 | structure.shared.factory |
| unit.napc.sentinel_aa / Sentinel AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.paladin_howitzer / Paladin Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.raptor_multirole_fighter / Raptor Multirole Fighter | 2 | structure.shared.airfield, structure.shared.radar |
| unit.napc.condor_stealth_bomber / Condor Stealth Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.napc.riverwatch_patrol_boat / Riverwatch Patrol Boat | 1 | structure.shared.dock |
| unit.napc.aegis_frigate / Aegis Frigate | 2 | structure.shared.dock, structure.shared.radar |
| unit.napc.liberty_arsenal_ship / Liberty Arsenal Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.napc.adaptive_plating`, `research.napc.joint_tactical_links`.

**research.napc.dispersed_runways | Dispersed Runways** - T2; 1100 credits; 45 seconds; requires `structure.shared.radar`.

Airfields gain two extra service pads; service rate per pad is unchanged.

**Inherited support powers:** `power.napc.uav_sweep`, `power.napc.field_repair_drop`.

**power.napc.rapid_turnaround | Rapid Turnaround** - T2; 700 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

One powered Airfield rearms aircraft 50% faster for 20 seconds. Does not accelerate aircraft production.

**Unavailable vanilla-only power:** `power.napc.combined_arms_window`.

**Inherited superweapon:** `superweapon.napc.atlas_kinetic_array`. Atlas is unchanged. Use air reconnaissance to find high-value, tightly packed targets.

**Opening:** Build a normal infantry and Guardian screen, then an early Airfield. Mix Raptor loadouts and attack exposed production with Condors.

**Counterplay:** Layer AA with detectors, pressure Airfields, and advance during bomber rearm windows.

### roster.napc.canada | Canada - Northern Littoral Command

Parent: `roster.napc.vanilla`.

Northern ports and lake routes became the continent's winter lifelines. Littoral Command developed sealed vehicles and floating depots for routes that alternated between water, mud and broken pavement. It favors patient advances that keep evacuation routes open.

**Doctrine:** Amphibious armor and protected transport; useful on rivers and ordinary land.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.napc.canada.01 | subfaction | health | +10 | selector.amphibious_combat_units | Amphibious combat units gain health +10% on all terrain. |
| modifier.napc.canada.02 | subfaction | build_time_seconds | -15 | selector.ships | Ship build time -15%. |
| modifier.napc.canada.03 | subfaction | movement_speed | +20 | selector.amphibious_vehicles_on_water | Amphibious vehicle movement speed on water +20%. |
| modifier.napc.canada.04 | subfaction | reload_interval_seconds | +15 | selector.land_artillery | Land artillery reload interval +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.napc.pathfinder_apc | unit.napc.beaver_amphibious_apc |
| unit.napc.guardian_tank | unit.napc.narwhal_amphibious_tank |

**Removed without replacement:** `unit.napc.titan_gunship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.napc.beaver_amphibious_apc / Beaver Amphibious APC | 1 | structure.shared.factory | Detector and infantry transport that crosses water; reinforced passenger protection, but a weak weapon. |
| unit.napc.narwhal_amphibious_tank / Narwhal Amphibious Tank | 2 | structure.shared.factory, structure.shared.radar | Medium cannon tank that crosses water. Slower and less heavily armed than a Guardian; requires Radar. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.napc.rifle_squad / Rifle Squad | 1 | structure.shared.barracks |
| unit.napc.javelin_team / Javelin Team | 1 | structure.shared.barracks |
| unit.napc.combat_medic / Combat Medic | 2 | structure.shared.barracks, structure.shared.radar |
| unit.napc.beaver_amphibious_apc / Beaver Amphibious APC | 1 | structure.shared.factory |
| unit.napc.narwhal_amphibious_tank / Narwhal Amphibious Tank | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.sentinel_aa / Sentinel AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.paladin_howitzer / Paladin Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.bastion_heavy_tank / Bastion Heavy Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.napc.falcon_interceptor / Falcon Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.napc.riverwatch_patrol_boat / Riverwatch Patrol Boat | 1 | structure.shared.dock |
| unit.napc.aegis_frigate / Aegis Frigate | 2 | structure.shared.dock, structure.shared.radar |
| unit.napc.liberty_arsenal_ship / Liberty Arsenal Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.napc.adaptive_plating`, `research.napc.joint_tactical_links`.

**research.napc.sealed_compartments | Sealed Compartments** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Beaver and Narwhal units take 15% less explosive damage while on water.

**Inherited support powers:** `power.napc.uav_sweep`, `power.napc.field_repair_drop`.

**power.napc.floating_workshop | Floating Workshop** - T2; 800 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Deploy a visible repair pontoon on clear land or water. For 20 seconds it repairs friendly vehicles and ships within 5 cells at 1.5% maximum health per second.

**Unavailable vanilla-only power:** `power.napc.combined_arms_window`.

**Inherited superweapon:** `superweapon.napc.atlas_kinetic_array`. Atlas is unchanged. Amphibious scouts enable attacks behind a coastal defense line.

**Opening:** Use infantry and Beavers until Radar unlocks Narwhals; attack across secondary routes while frigates protect the crossing.

**Counterplay:** Pressure before Radar, cover exits from water, and use air attacks against the slower siege component.

### roster.napc.mexico | Mexico - Federal Vanguard

Parent: `roster.napc.vanilla`.

Mexican reconstruction brigades cleared rail junctions and defended dense resettlement districts. Their veterans formed the Federal Vanguard, demanding that the Corps protect inhabited places rather than merely draw secure borders around them. Their political leverage rests on citizen soldiers who expect to go home.

**Doctrine:** Affordable assault infantry with strong urban pressure.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.napc.mexico.01 | subfaction | cost_credits | -15 | selector.combat_infantry | Combat infantry cost -15%. |
| modifier.napc.mexico.02 | subfaction | build_time_seconds | -20 | selector.combat_infantry | Combat infantry build time -20%. |
| modifier.napc.mexico.03 | subfaction | cost_credits | +20 | selector.aircraft | Aircraft cost +20%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.napc.rifle_squad | unit.napc.vanguard_rifle_squad |
| unit.napc.combat_medic | unit.napc.aguila_breach_team |

**Removed without replacement:** `unit.napc.liberty_arsenal_ship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.napc.vanguard_rifle_squad / Vanguard Rifle Squad | 1 | structure.shared.barracks | May deploy portable cover in 4 seconds. Gains 20% bullet-damage resistance while stationary behind it; packing takes 2 seconds. |
| unit.napc.aguila_breach_team / Aguila Breach Team | 2 | structure.shared.barracks, structure.shared.radar | Armored assault infantry with anti-building charges and a short-range grenade launcher. Cannot heal; vulnerable in open ground. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.napc.vanguard_rifle_squad / Vanguard Rifle Squad | 1 | structure.shared.barracks |
| unit.napc.javelin_team / Javelin Team | 1 | structure.shared.barracks |
| unit.napc.aguila_breach_team / Aguila Breach Team | 2 | structure.shared.barracks, structure.shared.radar |
| unit.napc.pathfinder_apc / Pathfinder APC | 1 | structure.shared.factory |
| unit.napc.guardian_tank / Guardian Tank | 1 | structure.shared.factory |
| unit.napc.sentinel_aa / Sentinel AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.paladin_howitzer / Paladin Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.napc.bastion_heavy_tank / Bastion Heavy Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.napc.falcon_interceptor / Falcon Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.napc.titan_gunship / Titan Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.napc.riverwatch_patrol_boat / Riverwatch Patrol Boat | 1 | structure.shared.dock |
| unit.napc.aegis_frigate / Aegis Frigate | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.napc.adaptive_plating`, `research.napc.joint_tactical_links`.

**research.napc.section_logistics | Section Logistics** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Combat infantry recover 1% maximum health per second near a powered Barracks after 6 seconds out of combat.

**Inherited support powers:** `power.napc.uav_sweep`, `power.napc.field_repair_drop`.

**power.napc.coordinated_advance | Coordinated Advance** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Friendly infantry in a 6-cell-radius zone gain movement speed +25% and suppression immunity for 12 seconds. Existing suppression is removed.

**Unavailable vanilla-only power:** `power.napc.combined_arms_window`.

**Inherited superweapon:** `superweapon.napc.atlas_kinetic_array`. Atlas is unchanged. Use it to break fortified positions that infantry cannot safely approach.

**Opening:** Contest capture points with Vanguard squads; use Guardians and Javelins to protect Aguila teams approaching buildings.

**Counterplay:** Use conventional area damage, mobile machine-gun vehicles and repeated flanking moves; deny safe rally points.

## faction.nec | New European Confederation

*No city stands alone.*

The old continental institutions failed when member governments seized their own power reserves. City leagues, surviving national services and industrial cooperatives later negotiated a new confederation with narrow but enforceable obligations. Its armies defend a dense lattice of shared sensors and guaranteed supply routes. The Confederation wants Meridian governed by treaty and transparent technical standards, yet its smaller members fear that the engineers who define those standards will quietly become the new rulers.

**Doctrine:** Precision, sensor networks and deliberate positional warfare.

**Visual direction:** Slate blue, white and amber; low profiles, angular turrets, fold-out sensor masts.

### Inherited traits
- Networked fire: friendly combat infantry and land combat vehicles within 6 cells of a powered friendly Relay deal weapon damage +10%. Relay fields do not stack.
- All combat units cost +5%; service units are exempt.
- Strengths: precise fire, strong defensive positions and efficient local coordination. Weaknesses: costly units and dependence on vulnerable Relay coverage.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.nec.01 | parent_faction | cost_credits | +5 | selector.combat_units | All combat units cost +5%; service units are exempt. |

### roster.nec.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.nec.jager_squad / Jager Squad | 1 | structure.shared.barracks | Accurate general infantry; vulnerable to area damage. |
| unit.nec.spike_team / Spike Team | 1 | structure.shared.barracks | Long-range guided anti-tank infantry; must stop to fire. |
| unit.nec.sapper / Sapper | 2 | structure.shared.barracks, structure.shared.radar | Combat engineer with a short-range weapon and temporary infantry cover; cannot replace the service Engineer. |
| unit.nec.surveyor_apc / Surveyor APC | 1 | structure.shared.factory | Fast scout, detector and light infantry transport. |
| unit.nec.leopard_tank / Leopard Tank | 1 | structure.shared.factory | Well-balanced medium tank; limited splash damage. |
| unit.nec.rapier_aa / Rapier AA | 2 | structure.shared.factory, structure.shared.radar | Long-range mobile anti-air and detector. |
| unit.nec.archer_spg / Archer SPG | 2 | structure.shared.factory, structure.shared.radar | Accurate indirect artillery; fragile and slow to deploy. |
| unit.nec.argent_rail_tank / Argent Rail Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Long-range armor killer; slow reload, weak against infantry. |
| unit.nec.kestrel_interceptor / Kestrel Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Dedicated fighter with a short rearm cycle. |
| unit.nec.aster_ew_aircraft / Aster EW Aircraft | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Unarmed jammer: enemies within 5 cells have sight -25%; no effect on weapon range or fixed detection radius. |
| unit.nec.skerry_patrol_boat / Skerry Patrol Boat | 1 | structure.shared.dock | Fast surface scout with a light autocannon. |
| unit.nec.horizon_escort / Horizon Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.nec.concord_monitor / Concord Monitor | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Precision coastal artillery ship; vulnerable to close attack. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.nec.lance_rail_emplacement`, `structure.nec.aurora_microwave_array`, `structure.nec.relay`.

### Inherited research

**research.nec.sensor_fusion | Sensor Fusion** - T2; 1100 credits; 45 seconds; requires `structure.shared.radar`.

Surveyor APC, Rapier AA and Horizon Escort detection radius +2 cells; replacements inherit it.

**research.nec.distributed_control | Distributed Control** - T3; 1700 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Relay radius increases from 6 to 8 cells. A Relay retains its damage-bonus field for 10 seconds after losing power, but not after destruction.

### Inherited support powers

**power.nec.survey_drone | Survey Drone** - T2; 450 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

A shootable drone reveals and detects within 6 cells of the target for 15 seconds.

**power.nec.counterbattery_mission | Counterbattery Mission** - T3; 1100 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

After 5 seconds of warning, six conventional precision shells strike a selected 4-cell-radius area over 4 seconds. Moderate siege damage; moving units can escape.

### Vanilla-only third power

**power.nec.treaty_coordination | Treaty Coordination** - T2; 800 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 20 seconds, powered Relays provide damage +15% instead of +10%. No additional benefit outside their fields.

### superweapon.nec.aurora_microwave_array | Aurora Microwave Array

Launcher: `structure.nec.aurora_microwave_array`. Recharge: 420 seconds. Warning: 8 seconds. Starts empty; maximum one stored charge.

A microwave burst affects an 8-cell-radius zone. Enemy vehicles and aircraft lose weapons for 8 seconds; powered enemy structures shut down for 18 seconds. Vehicles can still move, aircraft do not crash, and infantry remain operational. Direct damage is light.

**Counterplay:** Disperse powered infrastructure, advance with infantry, and retreat disabled vehicles. Destroying Aurora during its warning cancels the pulse.

**Vanilla opening:** Establish one contested position with Jagers and Leopards; add Radar, a Relay and Rapiers. Use artillery to make opponents enter the network rather than chasing blindly.

**Fight this faction:** Attack the network edges, disable power, force repeated repositioning and use cheap units to absorb slow precision volleys.

### roster.nec.nordics | Nordics - Northern Watch

Parent: `roster.nec.vanilla`.

Norway, Sweden, Denmark and Finland pooled maritime surveillance and dispersed defense commands after repeated failures of centralized dispatch. Northern Watch treats early warning as a public service and prefers to lose ground briefly rather than lose the soldiers needed to retake it.

**Doctrine:** Reconnaissance, mobile missiles and coastal denial.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.nec.nordics.01 | subfaction | sight_cells | +20 | selector.scouts_or_artillery | Scout and artillery sight +20%. |
| modifier.nec.nordics.02 | subfaction | movement_speed | +15 | selector.amphibious_vehicles | Amphibious vehicle movement speed +15% on land and water. |
| modifier.nec.nordics.03 | subfaction | health | -10 | selector.tanks | Tank health -10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.nec.surveyor_apc | unit.nec.fen_recon_carrier |
| unit.nec.archer_spg | unit.nec.fjord_missile_carrier |

**Removed without replacement:** `unit.nec.argent_rail_tank`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.nec.fen_recon_carrier / Fen Recon Carrier | 1 | structure.shared.factory | Amphibious detector and transport. Can deploy a 6-cell sensor mast, becoming immobile and visibly exposed. |
| unit.nec.fjord_missile_carrier / Fjord Missile Carrier | 2 | structure.shared.factory, structure.shared.radar | Amphibious precision missile artillery; fast redeployment, long reload and little splash. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.nec.jager_squad / Jager Squad | 1 | structure.shared.barracks |
| unit.nec.spike_team / Spike Team | 1 | structure.shared.barracks |
| unit.nec.sapper / Sapper | 2 | structure.shared.barracks, structure.shared.radar |
| unit.nec.fen_recon_carrier / Fen Recon Carrier | 1 | structure.shared.factory |
| unit.nec.leopard_tank / Leopard Tank | 1 | structure.shared.factory |
| unit.nec.rapier_aa / Rapier AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.fjord_missile_carrier / Fjord Missile Carrier | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.kestrel_interceptor / Kestrel Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.nec.aster_ew_aircraft / Aster EW Aircraft | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.nec.skerry_patrol_boat / Skerry Patrol Boat | 1 | structure.shared.dock |
| unit.nec.horizon_escort / Horizon Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.nec.concord_monitor / Concord Monitor | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.nec.sensor_fusion`, `research.nec.distributed_control`.

**research.nec.dispersed_links | Dispersed Links** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Deployed Fen masts provide the Relay damage bonus in 4 cells using onboard power. Fields work during base power loss, do not stack with Relays and do not gain Relay radius upgrades.

**Inherited support powers:** `power.nec.survey_drone`, `power.nec.counterbattery_mission`.

**power.nec.silent_watch | Silent Watch** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Friendly stationary ground units in a 6-cell-radius area camouflage for up to 15 seconds. Movement, firing or detection breaks concealment.

**Unavailable vanilla-only power:** `power.nec.treaty_coordination`.

**Inherited superweapon:** `superweapon.nec.aurora_microwave_array`. Aurora is unchanged. Exploit the shutdown to reposition missile carriers rather than attempting a heavy frontal breakthrough.

**Opening:** Use Fen carriers to reveal attack routes and screen mobile artillery with infantry and Rapiers.

**Counterplay:** Close distance under smoke or cover, bring detectors, and force fights where thin armor cannot disengage.

### roster.nec.eurocorps | Eurocorps - Franco-German Armored Directorate

Parent: `roster.nec.vanilla`.

France and Germany sponsor the largest shared manufacturing program in the Confederation. Eurocorps sees common equipment and professional command as the antidote to political fragmentation. Its critics see procurement policy turning into a claim to lead every coalition operation.

**Doctrine:** Expensive armored formations and siege breakthroughs.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.nec.eurocorps.01 | subfaction | health | +15 | selector.tanks | Tank health +15%. |
| modifier.nec.eurocorps.02 | subfaction | cost_credits | +10 | selector.tanks | Tank cost +10%. |
| modifier.nec.eurocorps.03 | subfaction | build_time_seconds | +10 | selector.land_combat_vehicles | All land combat vehicle build time +10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.nec.leopard_tank | unit.nec.marte_heavy_mbt |
| unit.nec.argent_rail_tank | unit.nec.charlemagne_siege_tank |

**Removed without replacement:** `unit.nec.aster_ew_aircraft`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.nec.marte_heavy_mbt / Marte Heavy MBT | 2 | structure.shared.factory, structure.shared.radar | Heavy medium-tank replacement with good frontal protection and slow acceleration. Requires Radar, delaying the first tank. |
| unit.nec.charlemagne_siege_tank / Charlemagne Siege Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Deploys in 4 seconds to gain weapon range +25%. Cannot turn its hull or move while deployed; weak against infantry. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.nec.jager_squad / Jager Squad | 1 | structure.shared.barracks |
| unit.nec.spike_team / Spike Team | 1 | structure.shared.barracks |
| unit.nec.sapper / Sapper | 2 | structure.shared.barracks, structure.shared.radar |
| unit.nec.surveyor_apc / Surveyor APC | 1 | structure.shared.factory |
| unit.nec.marte_heavy_mbt / Marte Heavy MBT | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.rapier_aa / Rapier AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.archer_spg / Archer SPG | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.charlemagne_siege_tank / Charlemagne Siege Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.nec.kestrel_interceptor / Kestrel Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.nec.skerry_patrol_boat / Skerry Patrol Boat | 1 | structure.shared.dock |
| unit.nec.horizon_escort / Horizon Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.nec.concord_monitor / Concord Monitor | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.nec.sensor_fusion`, `research.nec.distributed_control`.

**research.nec.shared_fire_solutions | Shared Fire Solutions** - T3; 1700 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Marte and Charlemagne gain reload interval -10% inside a powered Relay field.

**Inherited support powers:** `power.nec.survey_drone`, `power.nec.counterbattery_mission`.

**power.nec.armored_overwatch | Armored Overwatch** - T2; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 15 seconds, stationary tanks in a selected 6-cell-radius zone gain weapon range +10%. Moving immediately removes the bonus.

**Unavailable vanilla-only power:** `power.nec.treaty_coordination`.

**Inherited superweapon:** `superweapon.nec.aurora_microwave_array`. Aurora is unchanged. Time the shutdown with the slow advance and deployment of the siege line.

**Opening:** Defend with infantry and Surveyors until Radar unlocks Marte; add Relays before building a costly siege group.

**Counterplay:** Punish the delayed tank timing, flank deployed guns and force this expensive army to defend several places.

### roster.nec.alpine_brotherhood | Alpine Brotherhood - Pass and Tunnel Compact

Parent: `roster.nec.vanilla`.

Austria, Switzerland and Italy formed mutual rescue and engineering associations to keep mountain passes, reservoirs and tunnel networks usable. The Brotherhood grew from these civic oaths into a military compact. Its loyalties run first to protected communities, sometimes at the expense of confederal strategy.

**Doctrine:** Fortified infantry, compact artillery positions and repairable defenses.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.nec.alpine_brotherhood.01 | subfaction | health | +15 | selector.combat_infantry | Combat infantry health +15%. |
| modifier.nec.alpine_brotherhood.02 | subfaction | cost_credits | -15 | selector.defensive_structures | Defensive structure cost -15%. |
| modifier.nec.alpine_brotherhood.03 | subfaction | build_time_seconds | +20 | selector.aircraft | Aircraft build time +20%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.nec.sapper | unit.nec.alpine_pioneer |
| unit.nec.archer_spg | unit.nec.ibex_crawler_gun |

**Removed without replacement:** `unit.nec.concord_monitor`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.nec.alpine_pioneer / Alpine Pioneer | 2 | structure.shared.barracks, structure.shared.radar | Builds one temporary infantry shelter per squad and repairs friendly defenses. A shelter lasts 45 seconds and grants occupants 25% bullet-damage resistance. |
| unit.nec.ibex_crawler_gun / Ibex Crawler Gun | 2 | structure.shared.factory, structure.shared.radar | Compact tracked howitzer with a 2-second deployment and strong frontal protection. Less range than Archer, vulnerable from behind. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.nec.jager_squad / Jager Squad | 1 | structure.shared.barracks |
| unit.nec.spike_team / Spike Team | 1 | structure.shared.barracks |
| unit.nec.alpine_pioneer / Alpine Pioneer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.nec.surveyor_apc / Surveyor APC | 1 | structure.shared.factory |
| unit.nec.leopard_tank / Leopard Tank | 1 | structure.shared.factory |
| unit.nec.rapier_aa / Rapier AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.ibex_crawler_gun / Ibex Crawler Gun | 2 | structure.shared.factory, structure.shared.radar |
| unit.nec.argent_rail_tank / Argent Rail Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.nec.kestrel_interceptor / Kestrel Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.nec.aster_ew_aircraft / Aster EW Aircraft | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.nec.skerry_patrol_boat / Skerry Patrol Boat | 1 | structure.shared.dock |
| unit.nec.horizon_escort / Horizon Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.nec.sensor_fusion`, `research.nec.distributed_control`.

**research.nec.tunnel_workshops | Tunnel Workshops** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Engineers and Alpine Pioneers repair defensive structures 25% faster; credit cost per health restored is unchanged.

**Inherited support powers:** `power.nec.survey_drone`, `power.nec.counterbattery_mission`.

**power.nec.emergency_earthworks | Emergency Earthworks** - T2; 700 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Friendly infantry and defenses in a 5-cell-radius zone take 20% less explosive damage for 15 seconds. Does not protect vehicles.

**Unavailable vanilla-only power:** `power.nec.treaty_coordination`.

**Inherited superweapon:** `superweapon.nec.aurora_microwave_array`. Aurora is unchanged. Use the interruption to advance pioneers and establish the next defensive position.

**Opening:** Hold a narrow front with Pioneers, Ibex guns and Rapiers; expand behind the line rather than investing everything in one fortress.

**Counterplay:** Out-expand the compact army, use long-range siege and avoid feeding infantry into prepared cover.

## faction.olm | Order of the Levant and Mediterranean

*Keep the wells. Keep the word.*

Desalination operators, Levantine municipal councils and Mediterranean convoy leagues created an oath-bound order to defend water and energy infrastructure during the Blackout. Membership is civic and includes many faiths and secular communities. The Order now protects a chain of coastal enclaves rather than a continuous empire. It argues that no distant government should be able to shut off another city's water. Its solar directorates nevertheless want exclusive custody of the very Meridian controls that would make such coercion possible.

**Doctrine:** Mobile combined arms, concealment and abundant electrical power.

**Visual direction:** Ivory, copper and deep teal; heat shields, fabric screens and articulated wheels.

### Inherited traits
- Combat infantry and light land vehicles: movement speed +10%, health -10%.
- Generators produce +25% power; this creates no credits.
- Strengths: rapid repositioning, screening and energy-intensive systems. Weaknesses: fragile screens and poor prolonged frontal trades.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.olm.01 | parent_faction | movement_speed | +10 | selector.combat_infantry | Combat infantry and light land vehicles: movement speed +10%, health -10%. |
| modifier.olm.02 | parent_faction | movement_speed | +10 | selector.light_land_vehicles | Combat infantry and light land vehicles: movement speed +10%, health -10%. |
| modifier.olm.03 | parent_faction | health | -10 | selector.combat_infantry | Combat infantry and light land vehicles: movement speed +10%, health -10%. |
| modifier.olm.04 | parent_faction | health | -10 | selector.light_land_vehicles | Combat infantry and light land vehicles: movement speed +10%, health -10%. |
| modifier.olm.05 | parent_faction | power_output | +25 | selector.generators | Generators produce +25% power; this creates no credits. |

### roster.olm.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.olm.wayfarer_guard / Wayfarer Guard | 1 | structure.shared.barracks | Mobile general infantry with modest protection. |
| unit.olm.needle_team / Needle Team | 1 | structure.shared.barracks | Anti-vehicle missile infantry; little anti-infantry damage. |
| unit.olm.mirage_observer / Mirage Observer | 2 | structure.shared.barracks, structure.shared.radar | Unarmed detector and artillery spotter; camouflages after 6 stationary seconds. |
| unit.olm.caravan_apc / Caravan APC | 1 | structure.shared.factory | Light transport, scout and detector; designed for rapid withdrawal. |
| unit.olm.sirocco_tank / Sirocco Tank | 1 | structure.shared.factory | Fast medium tank; less armor than conventional rivals. |
| unit.olm.crescent_aa / Crescent AA | 2 | structure.shared.factory, structure.shared.radar | Mobile anti-air missile system and detector. |
| unit.olm.sandglass_mortar / Sandglass Mortar | 2 | structure.shared.factory, structure.shared.radar | Light indirect artillery with a short deployment delay and limited range. |
| unit.olm.sunlance_beam_tank / Sunlance Beam Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Focused thermal beam damages a single target over time; vulnerable during sustained firing. |
| unit.olm.shrike_interceptor / Shrike Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Fast air-superiority fighter with limited endurance. |
| unit.olm.nightjar_strike_drone / Nightjar Strike Drone | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Unmanned precision attacker; one anti-vehicle missile salvo before rearm. |
| unit.olm.corsair_patrol_boat / Corsair Patrol Boat | 1 | structure.shared.dock | Fast coastal scout and anti-infantry gunboat. |
| unit.olm.lantern_escort / Lantern Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.olm.beacon_missile_ship / Beacon Missile Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Long-range missile siege ship; weak at close range. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.olm.sunwall_projector`, `structure.olm.helios_reflector`.

### Inherited research

**research.olm.thermal_shrouds | Thermal Shrouds** - T2; 900 credits; 45 seconds; requires `structure.shared.radar`.

Light land vehicles gain sight +10% and take 10% less thermal-beam damage.

**research.olm.optical_mesh | Optical Mesh** - T3; 1500 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Caravan APCs and their replacements camouflage after 6 seconds stationary without attacking. Moving or firing reveals them.

### Inherited support powers

**power.olm.dust_screen | Dust Screen** - T2; 400 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

A 6-cell-radius smoke zone lasts 12 seconds. All ground units inside, friendly or enemy, take 30% less direct-fire weapon damage; artillery and area blasts are unaffected.

**power.olm.mobile_workshop | Mobile Workshop** - T3; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

Place a visible, destructible repair drone station on clear ground. It repairs friendly vehicles in 5 cells at 2% maximum health per second for 15 seconds; no stacking.

### Vanilla-only third power

**power.olm.open_corridor | Open Corridor** - T2; 650 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Friendly land vehicles in a selected 6-cell-radius zone gain movement speed +25% for 12 seconds. Units must be in the zone when activated.

### superweapon.olm.helios_reflector | Helios Reflector

Launcher: `structure.olm.helios_reflector`. Recharge: 480 seconds. Warning: 10 seconds. Starts empty; maximum one stored charge.

A surviving orbital mirror focuses sunlight along a player-selected line 16 cells long and 3 cells wide. The beam traverses the line over 12 seconds, damaging ground units, ships and structures with strong thermal damage. It cannot track units after the line is committed.

**Counterplay:** Leave the marked line, attack along its flanks, and spread structures. Beam-resistant upgrades reduce its damage; smoke does not.

**Vanilla opening:** Use Caravan and Sirocco groups to threaten several routes, screen retreats with Dust Screen, and bring Observers before attempting a siege.

**Fight this faction:** Keep a mobile reserve, force close fights, detect concealed observers and attack the thin frontline before energy weapons can concentrate.

### roster.olm.saudi_arabia | Saudi Arabia - Solar Directorate

Parent: `roster.olm.vanilla`.

The Directorate operates vast solar farms, storage fields and desalination plants rebuilt after the Blackout. Its technocrats insist that dependable power requires unified command. Water councils accuse them of turning an emergency engineering mandate into a permanent monopoly.

**Doctrine:** Energy weapons and power-efficient late-game positions.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.olm.saudi_arabia.01 | subfaction | power_output | +20 | selector.generators | Generator output +20% relative to the parent faction. |
| modifier.olm.saudi_arabia.02 | subfaction | weapon_damage | +15 | selector.thermal_beam_weapons | Thermal-beam weapon damage +15%. |
| modifier.olm.saudi_arabia.03 | subfaction | movement_speed | -10 | selector.land_combat_vehicles | Land combat vehicle movement speed -10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.olm.crescent_aa | unit.olm.dawn_laser_aa |
| unit.olm.sunlance_beam_tank | unit.olm.ifrit_prism_tank |

**Removed without replacement:** `unit.olm.beacon_missile_ship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.olm.dawn_laser_aa / Dawn Laser AA | 2 | structure.shared.factory, structure.shared.radar | Detector with a continuous anti-air laser. Reliable against small drones, weaker against heavily armored aircraft; no ground attack. |
| unit.olm.ifrit_prism_tank / Ifrit Prism Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Deploys in 3 seconds to focus a stronger anti-structure beam. Must remain stationary and maintain line of sight; no bouncing beams. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.olm.wayfarer_guard / Wayfarer Guard | 1 | structure.shared.barracks |
| unit.olm.needle_team / Needle Team | 1 | structure.shared.barracks |
| unit.olm.mirage_observer / Mirage Observer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.olm.caravan_apc / Caravan APC | 1 | structure.shared.factory |
| unit.olm.sirocco_tank / Sirocco Tank | 1 | structure.shared.factory |
| unit.olm.dawn_laser_aa / Dawn Laser AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.olm.sandglass_mortar / Sandglass Mortar | 2 | structure.shared.factory, structure.shared.radar |
| unit.olm.ifrit_prism_tank / Ifrit Prism Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.olm.shrike_interceptor / Shrike Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.olm.nightjar_strike_drone / Nightjar Strike Drone | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.olm.corsair_patrol_boat / Corsair Patrol Boat | 1 | structure.shared.dock |
| unit.olm.lantern_escort / Lantern Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.olm.thermal_shrouds`, `research.olm.optical_mesh`.

**research.olm.thermal_reservoirs | Thermal Reservoirs** - T3; 1500 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Ifrit and Dawn units gain reload or cooling interval -10%; does not alter Helios.

**Inherited support powers:** `power.olm.dust_screen`, `power.olm.mobile_workshop`.

**power.olm.capacitor_discharge | Capacitor Discharge** - T2; 800 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Thermal-beam units and Sunwall defenses in a 6-cell-radius zone deal damage +20% for 10 seconds, then cannot fire for 4 seconds while cooling.

**Unavailable vanilla-only power:** `power.olm.open_corridor`.

**Inherited superweapon:** `superweapon.olm.helios_reflector`. Helios receives the thermal-beam damage modifier, but not unit-only cooling upgrades. Its warning and area are unchanged.

**Opening:** Build a conventional screen, then Dawn AA and Ifrits. Keep enough mobile Siroccos to prevent opponents bypassing the beam line.

**Counterplay:** Attack from multiple angles, use smoke against direct-fire units, and exploit the cooling period after Capacitor Discharge.

### roster.olm.algeria | Algeria - Saharan Corridor Guard

Parent: `roster.olm.vanilla`.

The Corridor Guard began as a federation of railway crews, oasis councils and convoy escorts linking coast and interior. Its commanders distrust static borders and defend movement itself as the basis of political independence. They support the Order while resisting solar-directorate control of transit routes.

**Doctrine:** Fast light vehicles, ambushes and harassment.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.olm.algeria.01 | subfaction | cost_credits | -15 | selector.light_land_vehicles | Light land vehicle cost -15%. |
| modifier.olm.algeria.02 | subfaction | build_time_seconds | -15 | selector.light_land_vehicles | Light land vehicle build time -15%. |
| modifier.olm.algeria.03 | subfaction | health | -10 | selector.light_land_vehicles | Light land vehicle health -10%. |
| modifier.olm.algeria.04 | subfaction | cost_credits | +15 | selector.tanks | Tank cost +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.olm.caravan_apc | unit.olm.dune_rover |
| unit.olm.sandglass_mortar | unit.olm.scorpion_rocket_buggy |

**Removed without replacement:** `unit.olm.sunlance_beam_tank`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.olm.dune_rover / Dune Rover | 1 | structure.shared.factory | Fast light transport and detector. Camouflages after 6 seconds without firing even while moving, but detection or taking damage reveals it for 6 seconds. |
| unit.olm.scorpion_rocket_buggy / Scorpion Rocket Buggy | 2 | structure.shared.factory, structure.shared.radar | Light artillery vehicle firing a short rocket salvo before a long reload; no deployment delay, fragile chassis. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.olm.wayfarer_guard / Wayfarer Guard | 1 | structure.shared.barracks |
| unit.olm.needle_team / Needle Team | 1 | structure.shared.barracks |
| unit.olm.mirage_observer / Mirage Observer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.olm.dune_rover / Dune Rover | 1 | structure.shared.factory |
| unit.olm.sirocco_tank / Sirocco Tank | 1 | structure.shared.factory |
| unit.olm.crescent_aa / Crescent AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.olm.scorpion_rocket_buggy / Scorpion Rocket Buggy | 2 | structure.shared.factory, structure.shared.radar |
| unit.olm.shrike_interceptor / Shrike Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.olm.nightjar_strike_drone / Nightjar Strike Drone | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.olm.corsair_patrol_boat / Corsair Patrol Boat | 1 | structure.shared.dock |
| unit.olm.lantern_escort / Lantern Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.olm.beacon_missile_ship / Beacon Missile Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.olm.thermal_shrouds`, `research.olm.optical_mesh`.

**research.olm.distributed_fuel_caches | Distributed Fuel Caches** - T2; 900 credits; 45 seconds; requires `structure.shared.radar`.

Dune Rovers and Scorpions gain movement speed +10% after 6 seconds out of combat; firing or taking damage ends it.

**Inherited support powers:** `power.olm.dust_screen`, `power.olm.mobile_workshop`.

**power.olm.false_convoy | False Convoy** - T2; 500 credits per use; 120 seconds cooldown; requires powered `structure.shared.radar`.

Create four visible decoy light vehicles for 25 seconds at a scouted clear location. They have 1 health, no damage, no collision and no capture ability; detectors identify them.

**Unavailable vanilla-only power:** `power.olm.open_corridor`.

**Inherited superweapon:** `superweapon.olm.helios_reflector`. Helios is unchanged. It supplies the heavy base-breaking pressure missing from the light-vehicle roster.

**Opening:** Raid collectors with Rovers and Needle passengers. Use Scorpions for repeated short attacks rather than prolonged firing lines.

**Counterplay:** Escort harvesters with detectors, hold mobile AA nearby and use fast splash-damage units to deny escape routes.

### roster.olm.el_andalus | El-Andalus - Western Straits Compact

Parent: `roster.olm.vanilla`.

El-Andalus is a future Spanish coastal compact whose name deliberately invokes a layered regional past, rather than a religious conquest or a claim over present-day Spain. Port municipalities joined the Order after eastern power links failed. Its assemblies demand open shipping and local autonomy, often challenging the Order's more centralized directorates.

**Doctrine:** Port defense, durable escorts and infantry holding power.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.olm.el_andalus.01 | subfaction | health | +15 | selector.ships | Ship health +15%. |
| modifier.olm.el_andalus.02 | subfaction | weapon_damage | +20 | selector.garrisoned_combat_infantry | Garrisoned combat infantry weapon damage +20%. |
| modifier.olm.el_andalus.03 | subfaction | cost_credits | +15 | selector.aircraft | Aircraft cost +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.olm.wayfarer_guard | unit.olm.gate_guard |
| unit.olm.lantern_escort | unit.olm.strait_frigate |

**Removed without replacement:** `unit.olm.sunlance_beam_tank`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.olm.gate_guard / Gate Guard | 1 | structure.shared.barracks | Shield-equipped infantry taking 25% less frontal bullet damage. Slower than Wayfarers; shields do not stop blasts or attacks from behind. |
| unit.olm.strait_frigate / Strait Frigate | 2 | structure.shared.dock, structure.shared.radar | Detector and anti-air/anti-submarine escort with stronger short-range surface guns, at the cost of slower movement. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.olm.gate_guard / Gate Guard | 1 | structure.shared.barracks |
| unit.olm.needle_team / Needle Team | 1 | structure.shared.barracks |
| unit.olm.mirage_observer / Mirage Observer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.olm.caravan_apc / Caravan APC | 1 | structure.shared.factory |
| unit.olm.sirocco_tank / Sirocco Tank | 1 | structure.shared.factory |
| unit.olm.crescent_aa / Crescent AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.olm.sandglass_mortar / Sandglass Mortar | 2 | structure.shared.factory, structure.shared.radar |
| unit.olm.shrike_interceptor / Shrike Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.olm.nightjar_strike_drone / Nightjar Strike Drone | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.olm.corsair_patrol_boat / Corsair Patrol Boat | 1 | structure.shared.dock |
| unit.olm.strait_frigate / Strait Frigate | 2 | structure.shared.dock, structure.shared.radar |
| unit.olm.beacon_missile_ship / Beacon Missile Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.olm.thermal_shrouds`, `research.olm.optical_mesh`.

**research.olm.harbor_militia | Harbor Militia** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Gate Guards gain damage +10% within 6 cells of a friendly Factory or Dock; no stacking between buildings.

**Inherited support powers:** `power.olm.dust_screen`, `power.olm.mobile_workshop`.

**power.olm.straits_crossfire | Straits Crossfire** - T2; 800 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Friendly infantry and ships in a selected 6-cell-radius zone gain weapon range +10% and sight +20% for 15 seconds.

**Unavailable vanilla-only power:** `power.olm.open_corridor`.

**Inherited superweapon:** `superweapon.olm.helios_reflector`. Helios is unchanged. Use its fixed line to force enemies away from a defended crossing or coastal approach.

**Opening:** Secure buildings with Gate Guards, then combine Siroccos and Sandglass mortars. On water maps, add escort groups before expensive siege ships.

**Counterplay:** Attack outside garrison coverage, use indirect fire and overwhelm the compact army before it can protect several approaches.

## faction.def | Democratic Eurasian Federation

*A thousand districts. One supply line.*

The Federation emerged from emergency congresses linking surviving Russian regions, Kazakh transport authorities and the northern Korean industrial state. Its charter distributes representation among territorial and workplace assemblies, but wartime production quotas give the central supply ministry enormous power. Some districts defend the federation as their only protection from abandonment; others call its elections ceremonial. It wants Meridian reopened as a shared industrial backbone and is willing to occupy reluctant junction cities to make the plan function.

**Doctrine:** Industrial volume, artillery saturation and replaceable armored forces.

**Visual direction:** Oxide red, gray and pale yellow; slab armor, exposed running gear and standardized containers.

### Inherited traits
- Land combat vehicles: cost -10%, build time -10%, movement speed -10%.
- No free units, permanent production multiplier or unlimited passive income; numerical superiority still needs collectors and factories.
- Strengths: replacement capacity, heavy artillery and sustained pressure. Weaknesses: slow reactions, supply exposure and cumbersome late-game formations.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.def.01 | parent_faction | cost_credits | -10 | selector.land_combat_vehicles | Land combat vehicles: cost -10%, build time -10%, movement speed -10%. |
| modifier.def.02 | parent_faction | build_time_seconds | -10 | selector.land_combat_vehicles | Land combat vehicles: cost -10%, build time -10%, movement speed -10%. |
| modifier.def.03 | parent_faction | movement_speed | -10 | selector.land_combat_vehicles | Land combat vehicles: cost -10%, build time -10%, movement speed -10%. |

### roster.def.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.def.line_conscript / Line Conscript | 1 | structure.shared.barracks | Inexpensive rifle infantry; poor at independent assaults. |
| unit.def.recoil_team / Recoil Team | 1 | structure.shared.barracks | Unguided anti-vehicle weapon with useful close-range damage. |
| unit.def.signal_officer / Signal Officer | 2 | structure.shared.barracks, structure.shared.radar | Detector; nearby infantry recover from suppression 50% faster within 5 cells. |
| unit.def.mule_apc / Mule APC | 1 | structure.shared.factory | Light transport and detector; robust but slow. |
| unit.def.hammer_tank / Hammer Tank | 1 | structure.shared.factory | Mass-produced medium tank with modest sight. |
| unit.def.porcupine_aa / Porcupine AA | 2 | structure.shared.factory, structure.shared.radar | Dual-purpose flak against aircraft and light infantry; also a detector. |
| unit.def.anvil_rocket_battery / Anvil Rocket Battery | 2 | structure.shared.factory, structure.shared.radar | Wide-area indirect barrage; inaccurate against isolated moving targets. |
| unit.def.colossus_siege_tank / Colossus Siege Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Slow heavy assault gun with strong area damage and poor traverse. |
| unit.def.kite_interceptor / Kite Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Simple air-superiority fighter; limited ground utility. |
| unit.def.burya_bomber / Burya Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Conventional area-bombing aircraft; visible and vulnerable on approach. |
| unit.def.picket_boat / Picket Boat | 1 | structure.shared.dock | Cheap patrol craft with a heavy machine gun. |
| unit.def.rampart_escort / Rampart Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.def.boreal_missile_submarine / Boreal Missile Submarine | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Concealed missile submarine; surfaces for 8 seconds to bombard the coast, exposing itself to ordinary weapons. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.def.citadel_mortar`, `structure.def.perun_missile_complex`.

### Inherited research

**research.def.standardized_parts | Standardized Parts** - T2; 900 credits; 45 seconds; requires `structure.shared.radar`.

Engineer repairs to land vehicles cost 15% fewer credits per health restored; applies anywhere, not only near a Factory.

**research.def.coordinated_barrages | Coordinated Barrages** - T3; 1600 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Anvil batteries, Colossus tanks and their replacements gain reload interval -10% when stationary for at least 4 seconds. Moving resets the bonus.

### Inherited support powers

**power.def.mobilization_order | Mobilization Order** - T2; 700 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 20 seconds, Barracks and Factory production progresses 25% faster. Costs remain unchanged; benefit applies only while this power is active.

**power.def.tremor_barrage | Tremor Barrage** - T3; 1300 credits per use; 210 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

After a 6-second warning, four waves of conventional shells strike a 5-cell-radius area over 8 seconds. High area pressure, limited precision.

### Vanilla-only third power

**power.def.redundant_orders | Redundant Orders** - T2; 650 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Friendly vehicles in a 6-cell-radius zone ignore weapon-disabling EMP effects for 10 seconds. Does not protect buildings or prevent damage.

### superweapon.def.perun_missile_complex | Perun Missile Complex

Launcher: `structure.def.perun_missile_complex`. Recharge: 480 seconds. Warning: 10 seconds. Starts empty; maximum one stored charge.

One conventional bunker-buster missile detonates in a 3-cell-radius core, followed by a lower-damage fragmentation ring out to 7 cells. The core threatens heavy structures; the ring punishes tightly packed support units. It leaves no permanent contamination.

**Counterplay:** Move away from the central marker, separate production buildings and intercept the attack by destroying the launch complex during its warning. Normal AA cannot stop the strategic missile.

**Vanilla opening:** Use cheap Hammers and infantry to contest two fronts, establish the economy behind them, then build a screened Anvil line rather than rushing one expensive capstone.

**Fight this faction:** Attack collectors, force artillery to redeploy, strike several fronts and avoid engaging the entire production stream head-on.

### roster.def.russia | Russia - Northern Arsenal Command

Parent: `roster.def.vanilla`.

The northern arsenal regions rebuilt around armored factories and winterized transport hubs. Their delegates promise that industrial self-sufficiency will prevent another collapse. The army's demand for predictable supply repeatedly clashes with local assemblies over how much civilian recovery can be postponed.

**Doctrine:** Slow armored assaults with active protection.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.def.russia.01 | subfaction | health | +15 | selector.land_combat_vehicles | Land combat vehicle health +15%. |
| modifier.def.russia.02 | subfaction | cost_credits | +10 | selector.land_combat_vehicles | Land combat vehicle cost +10%. |
| modifier.def.russia.03 | subfaction | movement_speed | -10 | selector.land_combat_vehicles | Land combat vehicle movement speed -10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.def.hammer_tank | unit.def.ural_assault_tank |
| unit.def.colossus_siege_tank | unit.def.bear_siege_crawler |

**Removed without replacement:** `unit.def.burya_bomber`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.def.ural_assault_tank / Ural Assault Tank | 2 | structure.shared.factory, structure.shared.radar | Heavy tank intercepting one incoming ordinary missile every 12 seconds. Cannot intercept shells, beams or superweapons; requires Radar. |
| unit.def.bear_siege_crawler / Bear Siege Crawler | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Very slow assault platform with frontal armor and a heavy demolition cannon. Poor vision and weak rear protection. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.def.line_conscript / Line Conscript | 1 | structure.shared.barracks |
| unit.def.recoil_team / Recoil Team | 1 | structure.shared.barracks |
| unit.def.signal_officer / Signal Officer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.def.mule_apc / Mule APC | 1 | structure.shared.factory |
| unit.def.ural_assault_tank / Ural Assault Tank | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.porcupine_aa / Porcupine AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.anvil_rocket_battery / Anvil Rocket Battery | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.bear_siege_crawler / Bear Siege Crawler | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.def.kite_interceptor / Kite Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.def.picket_boat / Picket Boat | 1 | structure.shared.dock |
| unit.def.rampart_escort / Rampart Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.def.boreal_missile_submarine / Boreal Missile Submarine | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.def.standardized_parts`, `research.def.coordinated_barrages`.

**research.def.layered_protection | Layered Protection** - T3; 1500 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Ural missile-interception cooldown falls from 12 to 9 seconds; Bear gains one such interceptor.

**Inherited support powers:** `power.def.mobilization_order`, `power.def.tremor_barrage`.

**power.def.steel_advance | Steel Advance** - T2; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Land vehicles in a 6-cell-radius zone take 20% less weapon damage for 12 seconds, but movement speed is reduced by a further 20% during the effect.

**Unavailable vanilla-only power:** `power.def.redundant_orders`.

**Inherited superweapon:** `superweapon.def.perun_missile_complex`. Perun is unchanged. Use it to remove a strongpoint before committing slow armor.

**Opening:** Screen with infantry and Mules until Radar; build a compact Ural spearhead supported by Porcupines and artillery.

**Counterplay:** Raid around the spearhead, use guns or beams that bypass missile interception, and strike weak rear armor.

### roster.def.kazakhstan | Kazakhstan - Steppe Transit Command

Parent: `roster.def.vanilla`.

Railway cities and open-country logistics authorities formed Transit Command to keep east-west movement from becoming a hostage of any one capital. Its troops favor dispersed depots and short engagements. Within the Federation, it is the loudest voice against concentrating every reserve in a few enormous arsenals.

**Doctrine:** Fast reconnaissance and mobile missile warfare.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.def.kazakhstan.01 | subfaction | movement_speed | +20 | selector.ground_combat_units | Ground combat unit movement speed +20%. |
| modifier.def.kazakhstan.02 | subfaction | cost_credits | -15 | selector.refineries | Refinery build cost -15%; collectors are not discounted. |
| modifier.def.kazakhstan.03 | subfaction | health | -15 | selector.land_combat_vehicles | Land combat vehicle health -15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.def.mule_apc | unit.def.steppe_recon_carrier |
| unit.def.anvil_rocket_battery | unit.def.saker_missile_truck |

**Removed without replacement:** `unit.def.colossus_siege_tank`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.def.steppe_recon_carrier / Steppe Recon Carrier | 1 | structure.shared.factory | Fast light transport and detector with extended sight, but poor armor. |
| unit.def.saker_missile_truck / Saker Missile Truck | 2 | structure.shared.factory, structure.shared.radar | Precision anti-vehicle and anti-structure missile artillery; deploys in 1 second, with little splash. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.def.line_conscript / Line Conscript | 1 | structure.shared.barracks |
| unit.def.recoil_team / Recoil Team | 1 | structure.shared.barracks |
| unit.def.signal_officer / Signal Officer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.def.steppe_recon_carrier / Steppe Recon Carrier | 1 | structure.shared.factory |
| unit.def.hammer_tank / Hammer Tank | 1 | structure.shared.factory |
| unit.def.porcupine_aa / Porcupine AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.saker_missile_truck / Saker Missile Truck | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.kite_interceptor / Kite Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.def.burya_bomber / Burya Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.def.picket_boat / Picket Boat | 1 | structure.shared.dock |
| unit.def.rampart_escort / Rampart Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.def.boreal_missile_submarine / Boreal Missile Submarine | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.def.standardized_parts`, `research.def.coordinated_barrages`.

**research.def.mobile_dispatch | Mobile Dispatch** - T2; 900 credits; 45 seconds; requires `structure.shared.radar`.

Steppe Carriers and Saker trucks gain sight +15% and pack up without delay after firing.

**Inherited support powers:** `power.def.mobilization_order`, `power.def.tremor_barrage`.

**power.def.transit_priority | Transit Priority** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Friendly collectors and ground transports in a 7-cell-radius zone gain movement speed +35% for 15 seconds. Does not improve harvesting or unloading rate.

**Unavailable vanilla-only power:** `power.def.redundant_orders`.

**Inherited superweapon:** `superweapon.def.perun_missile_complex`. Perun is unchanged. Recon carriers provide targeting for the heavy strike absent from the regular mobile roster.

**Opening:** Scout aggressively, establish a second collection route and use Sakers to strike valuable units before withdrawing.

**Counterplay:** Use fast attackers and aircraft, deny retreat routes and punish the thin armor whenever it stops to fire.

### roster.def.north_korea | North Korea - Fortress Reconstruction Bureau

Parent: `roster.def.vanilla`.

Following the Blackout, competing military and industrial councils reorganized the northern Korean state around hardened local districts. The Bureau joined the Federation for fuel and machine tools while retaining strict internal controls. Its engineers excel at redundancy and deception; its civilians bear the cost of reconstruction plans written as permanent mobilization.

**Doctrine:** Durable infantry, prepared positions and decoys.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.def.north_korea.01 | subfaction | health | +20 | selector.combat_infantry | Combat infantry health +20%. |
| modifier.def.north_korea.02 | subfaction | build_time_seconds | -15 | selector.combat_infantry | Combat infantry build time -15%. |
| modifier.def.north_korea.03 | subfaction | cost_credits | -10 | selector.defensive_structures | Defensive structure cost -10%. |
| modifier.def.north_korea.04 | subfaction | cost_credits | +25 | selector.aircraft | Aircraft cost +25%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.def.line_conscript | unit.def.fortress_guard |
| unit.def.signal_officer | unit.def.echo_team |

**Removed without replacement:** `unit.def.boreal_missile_submarine`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.def.fortress_guard / Fortress Guard | 1 | structure.shared.barracks | Rifle squad that deploys in 3 seconds for stronger suppressive fire; cannot move while deployed. |
| unit.def.echo_team / Echo Team | 2 | structure.shared.barracks, structure.shared.radar | Detector and suppression-recovery support. Can place one non-blocking decoy tank per team every 40 seconds; decoy lasts 30 seconds and has 1 health. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.def.fortress_guard / Fortress Guard | 1 | structure.shared.barracks |
| unit.def.recoil_team / Recoil Team | 1 | structure.shared.barracks |
| unit.def.echo_team / Echo Team | 2 | structure.shared.barracks, structure.shared.radar |
| unit.def.mule_apc / Mule APC | 1 | structure.shared.factory |
| unit.def.hammer_tank / Hammer Tank | 1 | structure.shared.factory |
| unit.def.porcupine_aa / Porcupine AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.anvil_rocket_battery / Anvil Rocket Battery | 2 | structure.shared.factory, structure.shared.radar |
| unit.def.colossus_siege_tank / Colossus Siege Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.def.kite_interceptor / Kite Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.def.burya_bomber / Burya Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.def.picket_boat / Picket Boat | 1 | structure.shared.dock |
| unit.def.rampart_escort / Rampart Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.def.standardized_parts`, `research.def.coordinated_barrages`.

**research.def.buried_command_lines | Buried Command Lines** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Radar and defensive structures recover from EMP shutdown 25% sooner; does not prevent initial shutdown.

**Inherited support powers:** `power.def.mobilization_order`, `power.def.tremor_barrage`.

**power.def.false_front | False Front** - T2; 500 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Place a 30-second decoy Radar and three decoy tanks in a scouted 6-cell zone. All are harmless, non-blocking and revealed by detectors.

**Unavailable vanilla-only power:** `power.def.redundant_orders`.

**Inherited superweapon:** `superweapon.def.perun_missile_complex`. Perun is unchanged. Decoys conceal preparations; they never hide or falsify the real superweapon countdown.

**Opening:** Build overlapping infantry positions and a modest Hammer reserve, using decoys to make the location of the real artillery line uncertain.

**Counterplay:** Verify targets with detectors, attack the economy outside fortified districts and use sustained siege rather than chasing decoys.

## faction.pd | Pacific Dominion

*The sea connects us.*

Australia, Indonesian maritime leagues and Japanese industrial authorities kept each other alive through a chain of protected shipping routes. Their emergency maritime command became the Pacific Dominion: a treaty government whose authority is strongest at sea and contested on land. Its admirals want Meridian reopened without allowing a continental power to dictate access to ports. Smaller islands increasingly ask whether the Dominion's promise of open passage includes the right to refuse its bases.

**Doctrine:** Amphibious maneuver, naval reach and flexible coastal logistics.

**Visual direction:** Ocean blue, coral orange and white; sealed hulls, folding flight surfaces and deck-mounted drones.

### Inherited traits
- Collectors are amphibious and can cross navigable water at 70% of their land speed. They still collect only from designated deposits and unload at a Refinery.
- Ships gain movement speed +15%.
- Defensive structures have health -15%. Strengths: alternative routes and mobile staging. Weaknesses: vulnerable fixed positions and costly losses during landings.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.pd.01 | parent_faction | movement_speed | +15 | selector.ships | Ships gain movement speed +15%. |
| modifier.pd.02 | parent_faction | health | -15 | selector.defensive_structures | Defensive structures have health -15%. Strengths: alternative routes and mobile staging. Weaknesses: vulnerable fixed positions and costly losses during landings. |

### roster.pd.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.pd.ranger_marine / Ranger Marine | 1 | structure.shared.barracks | General infantry optimized for fighting after transport deployment. |
| unit.pd.harpoon_team / Harpoon Team | 1 | structure.shared.barracks | Anti-vehicle missile infantry; may target surface ships, never aircraft. |
| unit.pd.reef_technician / Reef Technician | 2 | structure.shared.barracks, structure.shared.radar | Unarmed specialist repairing nearby land vehicles or ships, one target at a time. |
| unit.pd.wake_skimmer / Wake Skimmer | 1 | structure.shared.factory | Amphibious light transport and detector. |
| unit.pd.tide_tank / Tide Tank | 1 | structure.shared.factory | Amphibious medium tank; slow movement on water. |
| unit.pd.storm_aa / Storm AA | 2 | structure.shared.factory, structure.shared.radar | Land-based anti-air and detector; requires a transport to cross water. |
| unit.pd.breaker_howitzer / Breaker Howitzer | 2 | structure.shared.factory, structure.shared.radar | Conventional land artillery with good sustained fire. |
| unit.pd.leviathan_assault_carrier / Leviathan Assault Carrier | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Heavy amphibious vehicle with a short-range siege cannon and infantry capacity. |
| unit.pd.petrel_fighter / Petrel Fighter | 2 | structure.shared.airfield, structure.shared.radar | Dedicated interceptor with good patrol endurance. |
| unit.pd.osprey_strike_tiltrotor / Osprey Strike Tiltrotor | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Anti-vehicle attack aircraft that hovers when firing; vulnerable to focused AA. |
| unit.pd.reef_patrol_boat / Reef Patrol Boat | 1 | structure.shared.dock | Fast coastal scout and light-surface attacker. |
| unit.pd.trident_escort / Trident Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.pd.tempest_carrier / Tempest Carrier | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Launches short-range strike drones against ground or surface targets; needs escort protection. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.pd.sea_spear_battery`, `structure.pd.tempest_swarm_hub`.

### Inherited research

**research.pd.expeditionary_maintenance | Expeditionary Maintenance** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Reef Technicians repair 25% faster. Repair credit cost per health restored is unchanged.

**research.pd.integrated_flight_decks | Integrated Flight Decks** - T3; 1600 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Airfield rearm time -15%; carrier drone replacement time -15%. Applies to carrier replacements.

### Inherited support powers

**power.pd.maritime_patrol | Maritime Patrol** - T2; 500 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

A shootable patrol aircraft reveals and detects a 20-cell-long, 6-cell-wide corridor for 12 seconds. Works over land and water.

**power.pd.expeditionary_workshop | Expeditionary Workshop** - T3; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

A shootable aircraft drops a 20-second workshop on clear land or water, repairing friendly vehicles and ships in 5 cells at 1.5% maximum health per second.

### Vanilla-only third power

**power.pd.joint_landing | Joint Landing** - T2; 700 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 15 seconds, friendly ground units that disembark from transports take 20% less weapon damage for 6 seconds. Reboarding cannot refresh an existing protection effect.

### superweapon.pd.tempest_swarm_hub | Tempest Swarm Hub

Launcher: `structure.pd.tempest_swarm_hub`. Recharge: 480 seconds. Warning: 10 seconds. Starts empty; maximum one stored charge.

Launches 24 autonomous strike drones toward a selected 6-cell-radius area. They attack ground and surface targets there for up to 20 seconds before their batteries expire. Drones are individually targetable by AA and their approach direction is visible. Maximum aggregate damage is high, but interception can sharply reduce it.

**Counterplay:** Concentrate overlapping AA near the marked zone, move mobile units out, or destroy the hub during the warning. Drones cannot capture, scout beyond their attack zone or be salvaged.

**Vanilla opening:** Use Wake Skimmers and Tide Tanks to threaten routes that conventional armies cannot cover cheaply; build enough Storm AA to protect the landing area before investing in a fleet.

**Fight this faction:** Guard landing exits, attack weak static defenses and keep aircraft ready to strike isolated amphibious columns.

**Roster-specific service overrides:**

```json
{
  "unit.shared.collector": {
    "add_tags": [
      "amphibious"
    ],
    "water_speed_fraction_of_land_speed": 0.7,
    "source_text": "Collectors are amphibious and can cross navigable water at 70% of their land speed. They still collect only from designated deposits and unload at a Refinery."
  }
}
```

### roster.pd.australia | Australia - Southern Reach Command

Parent: `roster.pd.vanilla`.

Remote settlements and long supply lines taught Southern Reach to value information and range over dense occupation. It supports the Dominion as a safeguard for trade, but resists proposals to turn every maritime dispute into a permanent continental deployment.

**Doctrine:** Long-range expeditionary artillery backed by reconnaissance aircraft.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.pd.australia.01 | subfaction | weapon_range_cells | +15 | selector.land_artillery | Land artillery weapon range +15%. |
| modifier.pd.australia.02 | subfaction | build_time_seconds | -15 | selector.airfields | Airfield construction time -15%. |
| modifier.pd.australia.03 | subfaction | health | -10 | selector.land_combat_vehicles | Land combat vehicle health -10%. |
| modifier.pd.australia.04 | subfaction | build_time_seconds | +15 | selector.ships | Ship build time +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.pd.breaker_howitzer | unit.pd.outrider_howitzer |
| unit.pd.petrel_fighter | unit.pd.wedge_recon_fighter |

**Removed without replacement:** `unit.pd.leviathan_assault_carrier`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.pd.outrider_howitzer / Outrider Howitzer | 2 | structure.shared.factory, structure.shared.radar | Long-range mobile artillery with a narrow firing arc and 3-second deployment; weak at close range. |
| unit.pd.wedge_recon_fighter / Wedge Recon Fighter | 2 | structure.shared.airfield, structure.shared.radar | Detector-equipped fighter with extended sight; lower anti-air damage than Petrel. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.pd.ranger_marine / Ranger Marine | 1 | structure.shared.barracks |
| unit.pd.harpoon_team / Harpoon Team | 1 | structure.shared.barracks |
| unit.pd.reef_technician / Reef Technician | 2 | structure.shared.barracks, structure.shared.radar |
| unit.pd.wake_skimmer / Wake Skimmer | 1 | structure.shared.factory |
| unit.pd.tide_tank / Tide Tank | 1 | structure.shared.factory |
| unit.pd.storm_aa / Storm AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.pd.outrider_howitzer / Outrider Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.pd.wedge_recon_fighter / Wedge Recon Fighter | 2 | structure.shared.airfield, structure.shared.radar |
| unit.pd.osprey_strike_tiltrotor / Osprey Strike Tiltrotor | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.pd.reef_patrol_boat / Reef Patrol Boat | 1 | structure.shared.dock |
| unit.pd.trident_escort / Trident Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.pd.tempest_carrier / Tempest Carrier | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.pd.expeditionary_maintenance`, `research.pd.integrated_flight_decks`.

**research.pd.forward_fire_control | Forward Fire Control** - T3; 1500 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Outriders gain reload interval -10% while their target is within 6 cells of a friendly Wedge Recon Fighter.

**Inherited support powers:** `power.pd.maritime_patrol`, `power.pd.expeditionary_workshop`.

**power.pd.long_watch | Long Watch** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Reveal a 7-cell-radius area for 18 seconds through a high-altitude sensor pass. It reveals terrain and ordinary units but does not detect camouflage.

**Unavailable vanilla-only power:** `power.pd.joint_landing`.

**Inherited superweapon:** `superweapon.pd.tempest_swarm_hub`. Tempest Swarm is unchanged. Use it to force a defended enemy position to split attention between the air and artillery.

**Opening:** Build a compact marine and Tide screen, then Wedge reconnaissance and Outrider batteries. Relocate as soon as the firing line is exposed.

**Counterplay:** Rush the artillery, contest reconnaissance aircraft and use raids to stretch a small expeditionary screen.

### roster.pd.indonesia | Indonesia - Archipelago Defense League

Parent: `roster.pd.vanilla`.

Island governments joined their patrol fleets and rescue services to keep local routes open when distant command centers failed. The League supplies much of the Dominion's landing infantry and insists that maritime security must answer to the communities living beside the ports.

**Doctrine:** Transport assaults, inexpensive marines and raids across several routes.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.pd.indonesia.01 | subfaction | build_time_seconds | -15 | selector.combat_infantry | Combat infantry build time -15%. |
| modifier.pd.indonesia.02 | subfaction | health | +20 | selector.all_transports | Transport health +20%, including Landing Transports. |
| modifier.pd.indonesia.03 | subfaction | cost_credits | +15 | selector.tanks | Tank cost +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.pd.wake_skimmer | unit.pd.kancil_landing_skimmer |
| unit.pd.ranger_marine | unit.pd.island_raider |

**Removed without replacement:** `unit.pd.tempest_carrier`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.pd.kancil_landing_skimmer / Kancil Landing Skimmer | 1 | structure.shared.factory | Fast amphibious light transport and detector. Passengers unload 50% faster; its weapon is weaker than Wake's. |
| unit.pd.island_raider / Island Raider | 1 | structure.shared.barracks | Mobile rifle infantry gaining weapon damage +20% for 6 seconds after disembarking. The effect cannot be refreshed by immediate reboarding. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.pd.island_raider / Island Raider | 1 | structure.shared.barracks |
| unit.pd.harpoon_team / Harpoon Team | 1 | structure.shared.barracks |
| unit.pd.reef_technician / Reef Technician | 2 | structure.shared.barracks, structure.shared.radar |
| unit.pd.kancil_landing_skimmer / Kancil Landing Skimmer | 1 | structure.shared.factory |
| unit.pd.tide_tank / Tide Tank | 1 | structure.shared.factory |
| unit.pd.storm_aa / Storm AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.pd.breaker_howitzer / Breaker Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.pd.leviathan_assault_carrier / Leviathan Assault Carrier | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.pd.petrel_fighter / Petrel Fighter | 2 | structure.shared.airfield, structure.shared.radar |
| unit.pd.osprey_strike_tiltrotor / Osprey Strike Tiltrotor | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.pd.reef_patrol_boat / Reef Patrol Boat | 1 | structure.shared.dock |
| unit.pd.trident_escort / Trident Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.pd.expeditionary_maintenance`, `research.pd.integrated_flight_decks`.

**research.pd.distributed_beachheads | Distributed Beachheads** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Reef Technicians gain movement speed +15% and can repair a transport while riding in it, one Technician per transport.

**Inherited support powers:** `power.pd.maritime_patrol`, `power.pd.expeditionary_workshop`.

**power.pd.feint_landing | Feint Landing** - T2; 500 credits per use; 120 seconds cooldown; requires powered `structure.shared.radar`.

Create three harmless, non-blocking decoy transports for 25 seconds on scouted land or water. They cannot carry units and are identified by detectors.

**Unavailable vanilla-only power:** `power.pd.joint_landing`.

**Inherited superweapon:** `superweapon.pd.tempest_swarm_hub`. The Tempest Swarm Hub remains available despite losing the Tempest Carrier; they are separate technologies.

**Opening:** Move Raiders in several Kancils, force defenders to commit to one approach, then land elsewhere. Use normal artillery for sustained land siege.

**Counterplay:** Scout the real transports, use area damage at unloading points and force Raiders to fight after their arrival bonus expires.

### roster.pd.japan | Japan - Maritime Systems Authority

Parent: `roster.pd.vanilla`.

Industrial cities and shipyard administrations rebuilt Japan's defense around automation because skilled crews were scarce after the Blackout. The Authority treats precise, limited operations as a way to preserve lives. Its reliance on remote systems has widened the political distance between those authorizing force and those living under it.

**Doctrine:** Expensive precision systems, adaptable armor and advanced carriers.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.pd.japan.01 | subfaction | reload_interval_seconds | -10 | selector.aircraft_or_ships | Aircraft and ship reload intervals -10%; Airfield rearm time is unchanged. |
| modifier.pd.japan.02 | subfaction | cost_credits | +10 | selector.combat_units | All combat unit cost +10%. |
| modifier.pd.japan.03 | subfaction | health | -10 | selector.defensive_structures | Defensive structure health -10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.pd.tide_tank | unit.pd.shinano_adaptive_tank |
| unit.pd.tempest_carrier | unit.pd.shogun_drone_carrier |

**Removed without replacement:** `unit.pd.breaker_howitzer`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.pd.shinano_adaptive_tank / Shinano Adaptive Tank | 2 | structure.shared.factory, structure.shared.radar | Amphibious tank switching in 3 seconds between mobile direct fire and stationary long-range siege fire. Siege mode loses anti-infantry effectiveness. |
| unit.pd.shogun_drone_carrier / Shogun Drone Carrier | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Advanced carrier switching between surface-strike drones and interceptor drones; only one wing type may operate at a time. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.pd.ranger_marine / Ranger Marine | 1 | structure.shared.barracks |
| unit.pd.harpoon_team / Harpoon Team | 1 | structure.shared.barracks |
| unit.pd.reef_technician / Reef Technician | 2 | structure.shared.barracks, structure.shared.radar |
| unit.pd.wake_skimmer / Wake Skimmer | 1 | structure.shared.factory |
| unit.pd.shinano_adaptive_tank / Shinano Adaptive Tank | 2 | structure.shared.factory, structure.shared.radar |
| unit.pd.storm_aa / Storm AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.pd.leviathan_assault_carrier / Leviathan Assault Carrier | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.pd.petrel_fighter / Petrel Fighter | 2 | structure.shared.airfield, structure.shared.radar |
| unit.pd.osprey_strike_tiltrotor / Osprey Strike Tiltrotor | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.pd.reef_patrol_boat / Reef Patrol Boat | 1 | structure.shared.dock |
| unit.pd.trident_escort / Trident Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.pd.shogun_drone_carrier / Shogun Drone Carrier | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.pd.expeditionary_maintenance`, `research.pd.integrated_flight_decks`.

**research.pd.predictive_maintenance | Predictive Maintenance** - T3; 1700 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Shinano mode changes take 2 seconds; Shogun drone replacement time -20%.

**Inherited support powers:** `power.pd.maritime_patrol`, `power.pd.expeditionary_workshop`.

**power.pd.precision_window | Precision Window** - T2; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Friendly aircraft and ships in a 6-cell-radius zone gain weapon damage +20% for 10 seconds, but receive no bonus to sight or survivability.

**Unavailable vanilla-only power:** `power.pd.joint_landing`.

**Inherited superweapon:** `superweapon.pd.tempest_swarm_hub`. Tempest Swarm is unchanged; combat-unit cost and reload modifiers do not apply to temporary superweapon drones.

**Opening:** Use infantry and Skimmers until Radar unlocks Shinanos. On land, their siege mode replaces the lost howitzer; at sea, build one well-escorted Shogun.

**Counterplay:** Exploit the delayed tank timing, force expensive units to split and attack while carriers change wing types.

## faction.han | Han Empire

*A common future requires a common plan.*

A post-Blackout restoration movement recast the surviving Chinese central government as the Han Empire, claiming an old dynastic name for a new administrative order. In this setting the title is political, not a claim that its citizens share one ethnicity. Vietnamese and Cambodian successor governments joined through unequal security and infrastructure treaties, retaining their own armed commands. The imperial court promises to end scarcity by coordinating Meridian centrally; its provincial partners disagree sharply over who gets to write the plan.

**Doctrine:** Affordable infantry, unmanned support and vulnerable command links.

**Visual direction:** Jade green, crimson and porcelain; compact modular hulls, sensor crowns and standardized drone racks.

### Inherited traits
- Combat infantry cost -15% and build time -15%.
- Land combat vehicle health -10%.
- A Link Operator or Dragon Command Walker grants friendly unmanned combat units within 5 cells weapon damage +10%. Fields do not stack; destroying or suppressing the provider removes its field. Strengths: combined infantry/drone pressure; weaknesses: fragile vehicles and exposed control units.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.han.01 | parent_faction | cost_credits | -15 | selector.combat_infantry | Combat infantry cost -15% and build time -15%. |
| modifier.han.02 | parent_faction | build_time_seconds | -15 | selector.combat_infantry | Combat infantry cost -15% and build time -15%. |
| modifier.han.03 | parent_faction | health | -10 | selector.land_combat_vehicles | Land combat vehicle health -10%. |

### roster.han.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.han.banner_infantry / Banner Infantry | 1 | structure.shared.barracks | Inexpensive general infantry; needs supporting weapons against armor. |
| unit.han.lance_team / Lance Team | 1 | structure.shared.barracks | Anti-vehicle rocket infantry with a long reload. |
| unit.han.link_operator / Link Operator | 2 | structure.shared.barracks, structure.shared.radar | Unarmed detector and provider of the 5-cell command field. |
| unit.han.jade_carrier / Jade Carrier | 1 | structure.shared.factory | Light transport and detector; vulnerable to direct tank fire. |
| unit.han.ox_tank / Ox Tank | 1 | structure.shared.factory | Simple medium tank used to screen infantry formations. |
| unit.han.firefly_aa_drone / Firefly AA Drone | 2 | structure.shared.factory, structure.shared.radar | Unmanned mobile anti-air and detector; no useful anti-tank attack. |
| unit.han.nest_rocket_drone / Nest Rocket Drone | 2 | structure.shared.factory, structure.shared.radar | Unmanned indirect-fire launcher; fragile and dependent on spotting. |
| unit.han.dragon_command_walker / Dragon Command Walker | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Crewed heavy support vehicle with a cannon and 5-cell command field; expensive, large target. |
| unit.han.swallow_interceptor / Swallow Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Unmanned air-superiority fighter; cannot attack ground targets. |
| unit.han.silkwing_drone_bomber / Silkwing Drone Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Unmanned precision bomber with a slow rearm cycle. |
| unit.han.canal_patrol_boat / Canal Patrol Boat | 1 | structure.shared.dock | Cheap coastal scout and infantry support craft. |
| unit.han.jade_escort / Jade Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.han.emperor_drone_ship / Emperor Drone Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Crewed carrier launching unmanned surface-strike drones; weak at close range. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.han.dragon_tooth_launcher`, `structure.han.dragonfall_field_foundry`.

### Inherited research

**research.han.resilient_mesh | Resilient Mesh** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Unmanned combat units recover from EMP weapon shutdown 25% sooner; they still take normal EMP damage.

**research.han.distributed_cognition | Distributed Cognition** - T3; 1700 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Command-field radius increases from 5 to 7 cells. Bonuses still do not stack and no unit is useful only inside a field.

### Inherited support powers

**power.han.wideband_scan | Wideband Scan** - T2; 400 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

Reveal and detect a 7-cell-radius area for 6 seconds. A visible scan warning gives opponents 2 seconds before detection begins.

**power.han.software_surge | Software Surge** - T3; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

Friendly unmanned combat units in a 6-cell-radius zone gain reload interval -25% for 12 seconds, then lose weapons for 3 seconds. Excludes superweapon summons.

### Vanilla-only third power

**power.han.reserve_bandwidth | Reserve Bandwidth** - T2; 650 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

For 20 seconds, all surviving command-field providers gain radius +3 cells. Damage bonus stays at +10% and overlapping fields still do not stack.

### superweapon.han.dragonfall_field_foundry | Dragonfall Field Foundry

Launcher: `structure.han.dragonfall_field_foundry`. Recharge: 480 seconds. Warning: 10 seconds. Starts empty; maximum one stored charge.

Three assembly capsules land within a marked 5-cell-radius area, then take 5 seconds to unfold into autonomous siege engines. They can be attacked during assembly. For 60 seconds after assembly they operate as slow anti-structure ground units, then their limited-energy cores expire. They cannot capture, repair, harvest, receive command-field buffs or generate salvage.

**Counterplay:** Attack capsules before assembly, surround the slow engines with anti-tank units, or retreat and wait out their 60-second lifetime. Destroying the Foundry during warning cancels deployment.

**Vanilla opening:** Use cheap infantry to secure ground, add Ox tanks and Firefly AA, then support a Nest group with protected Link Operators.

**Fight this faction:** Use area damage against infantry, prioritize command providers, force vehicle trades and do not allow several drone systems to fire behind an intact screen.

### roster.han.china | China - Imperial Standards Army

Parent: `roster.han.vanilla`.

The central Standards Army presents uniform equipment and reliable public works as proof of the restoration's legitimacy. Its armored commands protect the routes that bind imperial provinces together. Their officers are divided between rebuilding a useful state and enforcing the court's demand for obedience.

**Doctrine:** Heavy armor and stronger local command coverage.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.han.china.01 | subfaction | health | +15 | selector.land_combat_vehicles | Land combat vehicle health +15%. |
| modifier.han.china.02 | subfaction | cost_credits | +10 | selector.land_combat_vehicles | Land combat vehicle cost +10%. |
| modifier.han.china.03 | subfaction | build_time_seconds | +10 | selector.combat_infantry | Combat infantry build time +10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.han.ox_tank | unit.han.imperial_guard_tank |
| unit.han.dragon_command_walker | unit.han.long_command_walker |

**Removed without replacement:** `unit.han.silkwing_drone_bomber`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.han.imperial_guard_tank / Imperial Guard Tank | 2 | structure.shared.factory, structure.shared.radar | Better-armored medium tank with an accurate anti-vehicle gun; requires Radar and remains weak against infantry masses. |
| unit.han.long_command_walker / Long Command Walker | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Heavy crewed command platform. Deploying in 3 seconds extends its command radius by 2 cells but prevents movement. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.han.banner_infantry / Banner Infantry | 1 | structure.shared.barracks |
| unit.han.lance_team / Lance Team | 1 | structure.shared.barracks |
| unit.han.link_operator / Link Operator | 2 | structure.shared.barracks, structure.shared.radar |
| unit.han.jade_carrier / Jade Carrier | 1 | structure.shared.factory |
| unit.han.imperial_guard_tank / Imperial Guard Tank | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.firefly_aa_drone / Firefly AA Drone | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.nest_rocket_drone / Nest Rocket Drone | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.long_command_walker / Long Command Walker | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.han.swallow_interceptor / Swallow Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.han.canal_patrol_boat / Canal Patrol Boat | 1 | structure.shared.dock |
| unit.han.jade_escort / Jade Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.han.emperor_drone_ship / Emperor Drone Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.han.resilient_mesh`, `research.han.distributed_cognition`.

**research.han.guard_integration | Guard Integration** - T3; 1600 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Imperial Guard Tanks count as eligible recipients of command-field damage bonuses, despite being crewed.

**Inherited support powers:** `power.han.wideband_scan`, `power.han.software_surge`.

**power.han.central_priority | Central Priority** - T2; 800 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 15 seconds, command fields provide weapon damage +20% instead of +10%; their radius is unchanged.

**Unavailable vanilla-only power:** `power.han.reserve_bandwidth`.

**Inherited superweapon:** `superweapon.han.dragonfall_field_foundry`. Dragonfall is unchanged. Temporary siege engines cannot benefit from Central Priority or Guard Integration.

**Opening:** Use Banner and Lance infantry to survive until Radar, then combine Guard tanks with Fireflies, Nest drones and a command provider.

**Counterplay:** Attack before the first Guard tanks arrive, remove providers and use terrain to prevent the army concentrating its expensive core.

### roster.han.vietnam | Vietnam - Canopy Defense Command

Parent: `roster.han.vanilla`.

Vietnamese defense councils entered the imperial treaty system to secure reconstruction supplies while preserving operational autonomy. Canopy Command regards dispersed defense as insurance against both foreign invasion and imperial overreach. Its soldiers train for ambushes in any terrain, not only forests.

**Doctrine:** Concealed infantry and amphibious rocket raids.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.han.vietnam.01 | subfaction | movement_speed | +10 | selector.combat_infantry | Combat infantry movement speed +10%. |
| modifier.han.vietnam.02 | subfaction | cost_credits | -10 | selector.light_land_vehicles | Light land vehicle cost -10%. |
| modifier.han.vietnam.03 | subfaction | cost_credits | +20 | selector.tanks | Tank cost +20%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.han.banner_infantry | unit.han.canopy_ranger |
| unit.han.nest_rocket_drone | unit.han.reed_rocket_skimmer |

**Removed without replacement:** `unit.han.dragon_command_walker`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.han.canopy_ranger / Canopy Ranger | 1 | structure.shared.barracks | Rifle infantry camouflaging after 6 seconds stationary without firing on any terrain. Moving, attacking or taking damage reveals it. |
| unit.han.reed_rocket_skimmer / Reed Rocket Skimmer | 2 | structure.shared.factory, structure.shared.radar | Unmanned amphibious light artillery firing short rocket bursts; less range and health than Nest. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.han.canopy_ranger / Canopy Ranger | 1 | structure.shared.barracks |
| unit.han.lance_team / Lance Team | 1 | structure.shared.barracks |
| unit.han.link_operator / Link Operator | 2 | structure.shared.barracks, structure.shared.radar |
| unit.han.jade_carrier / Jade Carrier | 1 | structure.shared.factory |
| unit.han.ox_tank / Ox Tank | 1 | structure.shared.factory |
| unit.han.firefly_aa_drone / Firefly AA Drone | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.reed_rocket_skimmer / Reed Rocket Skimmer | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.swallow_interceptor / Swallow Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.han.silkwing_drone_bomber / Silkwing Drone Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.han.canal_patrol_boat / Canal Patrol Boat | 1 | structure.shared.dock |
| unit.han.jade_escort / Jade Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.han.emperor_drone_ship / Emperor Drone Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.han.resilient_mesh`, `research.han.distributed_cognition`.

**research.han.hidden_relays | Hidden Relays** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Link Operators camouflage after 6 seconds stationary without attacking; their command field remains active while hidden.

**Inherited support powers:** `power.han.wideband_scan`, `power.han.software_surge`.

**power.han.broken_contact | Broken Contact** - T2; 650 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Ground combat units in a 6-cell-radius zone gain movement speed +20% for 10 seconds and leave a 6-second smoke screen at their initial position. Smoke follows the shared Dust Screen rule.

**Unavailable vanilla-only power:** `power.han.reserve_bandwidth`.

**Inherited superweapon:** `superweapon.han.dragonfall_field_foundry`. Dragonfall remains available despite losing the Dragon Command Walker; it is an independent strategic structure.

**Opening:** Threaten several approaches with Rangers; bring Link Operators and Reed skimmers to turn an ambush into a short, concentrated barrage.

**Counterplay:** Use detectors and persistent scouting, keep units spread against rockets and pressure the faction when it cannot safely reset concealment.

### roster.han.cambodia | Cambodia - Mekong Reconstruction Authority

Parent: `roster.han.vanilla`.

The Authority grew from river engineers, agricultural cooperatives and urban repair teams. It accepted imperial backing to rebuild transport and irrigation, then developed its own field robotics to reduce dependence on imported crews. Its leadership balances material gains against the fear that every new connection also tightens political control.

**Doctrine:** Drone sustain, field repair and economical support systems.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.han.cambodia.01 | subfaction | cost_credits | -15 | selector.unmanned_combat_units | Unmanned combat unit cost -15%. |
| modifier.han.cambodia.02 | subfaction | repair_progress_rate | +25 | selector.structures | Repairs to friendly structures progress 25% faster; cost per health is unchanged. |
| modifier.han.cambodia.03 | subfaction | build_time_seconds | +20 | selector.tanks | Tank build time +20%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.han.jade_carrier | unit.han.lotus_drone_tender |
| unit.han.link_operator | unit.han.mekong_field_engineer |

**Removed without replacement:** `unit.han.emperor_drone_ship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.han.lotus_drone_tender / Lotus Drone Tender | 1 | structure.shared.factory | Light transport and detector. Repairs one nearby friendly unmanned land unit at 1% maximum health per second, paying normal repair cost; cannot repair itself. |
| unit.han.mekong_field_engineer / Mekong Field Engineer | 2 | structure.shared.barracks, structure.shared.radar | Unarmed detector, structure repairer and command provider. Its command field requires a 2-second stationary deployment; service Engineers remain available. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.han.banner_infantry / Banner Infantry | 1 | structure.shared.barracks |
| unit.han.lance_team / Lance Team | 1 | structure.shared.barracks |
| unit.han.mekong_field_engineer / Mekong Field Engineer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.han.lotus_drone_tender / Lotus Drone Tender | 1 | structure.shared.factory |
| unit.han.ox_tank / Ox Tank | 1 | structure.shared.factory |
| unit.han.firefly_aa_drone / Firefly AA Drone | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.nest_rocket_drone / Nest Rocket Drone | 2 | structure.shared.factory, structure.shared.radar |
| unit.han.dragon_command_walker / Dragon Command Walker | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.han.swallow_interceptor / Swallow Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.han.silkwing_drone_bomber / Silkwing Drone Bomber | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.han.canal_patrol_boat / Canal Patrol Boat | 1 | structure.shared.dock |
| unit.han.jade_escort / Jade Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.han.resilient_mesh`, `research.han.distributed_cognition`.

**research.han.modular_servicing | Modular Servicing** - T3; 1500 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Lotus Tenders repair 50% faster, but credit cost per health restored is unchanged.

**Inherited support powers:** `power.han.wideband_scan`, `power.han.software_surge`.

**power.han.repair_swarm | Repair Swarm** - T2; 700 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Repair friendly unmanned land units and structures in a 5-cell-radius zone by 2% maximum health per second for 10 seconds. This paid power has no further repair charge.

**Unavailable vanilla-only power:** `power.han.reserve_bandwidth`.

**Inherited superweapon:** `superweapon.han.dragonfall_field_foundry`. Dragonfall is unchanged. Its temporary engines cannot be repaired by Lotus Tenders, Engineers or Repair Swarm.

**Opening:** Use infantry to shield Fireflies and Nest drones, keeping a few Lotus Tenders behind the line. Avoid trading support vehicles for a short-lived damage advantage.

**Counterplay:** Focus one target at a time, kill Tenders and deployed engineers, and prevent the army withdrawing to repair.

## faction.ae | African Empire

*What survives belongs to the future.*

Nigerian commercial and civic alliances, a Kongo basin compact and southern industrial states built a reconstruction federation around power corridors and mutual investment. Its elected High Steward adopted the title Emperor after mediating a succession of near-civil wars, turning a temporary compromise into a disputed constitutional institution. This Empire claims no automatic authority over all Africa. It wants to own the machinery of recovery rather than purchase access from outsiders, but debates over corridor revenues and the Steward's emergency powers threaten its cohesion.

**Doctrine:** Recovery, battlefield salvage and practical industrial endurance.

**Visual direction:** Ochre, charcoal and bright cyan; repairable panels, reinforced wheels and interchangeable weapon modules.

### Inherited traits
- Service Engineers and Reclaimers may salvage destroyed enemy land combat vehicles: an 8-second uninterrupted action yields 20% of the unit's paid purchase cost. Each wreck pays once; allied, self-destroyed, decoy and temporary summoned units produce no income.
- Land-vehicle repairs cost 25% fewer credits per health restored.
- Land artillery weapon range -10%. Strengths: sustained ground campaigns and economic recovery after winning battles. Weaknesses: must hold the battlefield to salvage, and can be outranged.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.ae.01 | parent_faction | repair_credit_cost_per_health | -25 | selector.land_vehicle_repairs | Land-vehicle repairs cost 25% fewer credits per health restored. |
| modifier.ae.02 | parent_faction | weapon_range_cells | -10 | selector.land_artillery | Land artillery weapon range -10%. Strengths: sustained ground campaigns and economic recovery after winning battles. Weaknesses: must hold the battlefield to salvage, and can be outranged. |

### roster.ae.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.ae.union_guard / Union Guard | 1 | structure.shared.barracks | Reliable general infantry protecting repair and salvage teams. |
| unit.ae.pike_team / Pike Team | 1 | structure.shared.barracks | Anti-tank infantry with a short-to-medium-range missile. |
| unit.ae.reclaimer / Reclaimer | 2 | structure.shared.barracks, structure.shared.radar | Armed salvage specialist; repairs one land vehicle at normal Engineer rate and gains salvage access. |
| unit.ae.mamba_apc / Mamba APC | 1 | structure.shared.factory | Wheeled light transport and detector; strong road mobility. |
| unit.ae.buffalo_tank / Buffalo Tank | 1 | structure.shared.factory | Conventional medium tank designed for repair and reuse. |
| unit.ae.weaver_aa / Weaver AA | 2 | structure.shared.factory, structure.shared.radar | Mobile anti-air and detector with poor anti-armor capability. |
| unit.ae.forge_howitzer / Forge Howitzer | 2 | structure.shared.factory, structure.shared.radar | Durable indirect artillery with shorter range than most rivals. |
| unit.ae.kiln_assault_crawler / Kiln Assault Crawler | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Heavy demolition vehicle with a broad blast and short reach. |
| unit.ae.sunbird_interceptor / Sunbird Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Dedicated fighter protecting advancing ground formations. |
| unit.ae.hammerhead_gunship / Hammerhead Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Close-support anti-vehicle aircraft, vulnerable to prepared AA. |
| unit.ae.delta_patrol_boat / Delta Patrol Boat | 1 | structure.shared.dock | River and coastal scout with a light cannon. |
| unit.ae.anchor_escort / Anchor Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.ae.sovereign_arsenal_ship / Sovereign Arsenal Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Heavy naval artillery platform with limited mobility. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.ae.forge_cannon`, `structure.ae.horizon_mass_driver`.

### Inherited research

**research.ae.recovery_winches | Recovery Winches** - T2; 900 credits; 45 seconds; requires `structure.shared.radar`.

Salvage actions take 5 rather than 8 seconds. Wreck value is unchanged.

**research.ae.circular_armor | Circular Armor** - T3; 1600 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Land combat vehicles gain health +10%. Does not create salvage from friendly losses or increase a wreck's paid-cost basis.

### Inherited support powers

**power.ae.survey_network | Survey Network** - T2; 400 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

Reveal a 7-cell-radius area for 12 seconds and highlight salvageable wrecks there. Reveals ordinary units but does not detect camouflage.

**power.ae.field_refurbishment | Field Refurbishment** - T3; 1000 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

Repair friendly land vehicles in a 6-cell-radius zone by 3% maximum health per second for 10 seconds. They cannot fire while receiving repairs; moving ends repair on that unit.

### Vanilla-only third power

**power.ae.recovery_priority | Recovery Priority** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

For 20 seconds, Engineers and Reclaimers gain movement speed +25% and salvage in 3 seconds. Salvage payout is unchanged.

### superweapon.ae.horizon_mass_driver | Horizon Mass Driver

Launcher: `structure.ae.horizon_mass_driver`. Recharge: 480 seconds. Warning: 10 seconds. Starts empty; maximum one stored charge.

A rail-assisted strategic battery strikes three overlapping circles, each 3 cells in radius, along a 10-cell line over 9 seconds. Impacts damage ground units, ships and structures. On land, pulverized debris slows all land vehicles by 35% for 20 seconds and prevents new construction there; it never blocks movement or permanently changes the map.

**Counterplay:** Leave the marked line before the first impact, avoid routing reinforcements through the debris, and attack from the sides. Existing buildings remain usable if they survive.

**Vanilla opening:** Use Buffalo tanks and infantry to win a local fight, secure the area, then bring salvage teams. Spend recovered credits on expansion before attempting an expensive siege push.

**Fight this faction:** Disengage before losing vehicles, deny wreck fields with artillery and use air attacks to bypass the repaired frontline.

### roster.ae.nigeria | Nigeria - Civic Logistics Directorate

Parent: `roster.ae.vanilla`.

Metropolitan councils, inland trade unions and communications firms formed the Directorate to prevent recovery funds disappearing into regional patronage. Its army combines rapidly organized infantry with field communications and drone support. Political rivals accuse it of mistaking the interests of its largest cities for those of the whole Empire.

**Doctrine:** Fast mobilization, infantry presence and protective drone support.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.ae.nigeria.01 | subfaction | cost_credits | -15 | selector.combat_infantry | Combat infantry cost -15%. |
| modifier.ae.nigeria.02 | subfaction | build_time_seconds | -15 | selector.combat_infantry | Combat infantry build time -15%. |
| modifier.ae.nigeria.03 | subfaction | build_time_seconds | -10 | selector.non_superweapon_structures | Non-superweapon structure construction time -10%. |
| modifier.ae.nigeria.04 | subfaction | health | -10 | selector.aircraft | Aircraft health -10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.ae.union_guard | unit.ae.civic_rifle_team |
| unit.ae.weaver_aa | unit.ae.lagos_drone_guard |

**Removed without replacement:** `unit.ae.kiln_assault_crawler`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.ae.civic_rifle_team / Civic Rifle Team | 1 | structure.shared.barracks | Rifle infantry able to place one 20-second sensor puck every 30 seconds. Puck reveals a 4-cell area but does not detect camouflage and is destructible. |
| unit.ae.lagos_drone_guard / Lagos Drone Guard | 2 | structure.shared.factory, structure.shared.radar | Mobile anti-air and detector with one small repair drone. The drone repairs one nearby infantry unit at 1% maximum health per second and can be shot down. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.ae.civic_rifle_team / Civic Rifle Team | 1 | structure.shared.barracks |
| unit.ae.pike_team / Pike Team | 1 | structure.shared.barracks |
| unit.ae.reclaimer / Reclaimer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.ae.mamba_apc / Mamba APC | 1 | structure.shared.factory |
| unit.ae.buffalo_tank / Buffalo Tank | 1 | structure.shared.factory |
| unit.ae.lagos_drone_guard / Lagos Drone Guard | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.forge_howitzer / Forge Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.sunbird_interceptor / Sunbird Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.ae.hammerhead_gunship / Hammerhead Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.ae.delta_patrol_boat / Delta Patrol Boat | 1 | structure.shared.dock |
| unit.ae.anchor_escort / Anchor Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.ae.sovereign_arsenal_ship / Sovereign Arsenal Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.ae.recovery_winches`, `research.ae.circular_armor`.

**research.ae.municipal_reserves | Municipal Reserves** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Civic Rifle Teams gain health +10% within 6 cells of a friendly Barracks or Refinery; fields do not stack.

**Inherited support powers:** `power.ae.survey_network`, `power.ae.field_refurbishment`.

**power.ae.civil_defense_net | Civil Defense Net** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Friendly infantry in a 6-cell-radius area gain sight +25% and suppression immunity for 15 seconds.

**Unavailable vanilla-only power:** `power.ae.recovery_priority`.

**Inherited superweapon:** `superweapon.ae.horizon_mass_driver`. Horizon is unchanged; the structure construction bonus does not shorten its build time or recharge.

**Opening:** Secure several points with Civic teams, support them with Lagos vehicles and Buffalo tanks, and use superior presence to protect collectors and wreck fields.

**Counterplay:** Use mobile area damage, destroy exposed support drones and force infantry to leave the infrastructure that strengthens them.

### roster.ae.kongo | Kongo - River Compact Guard

Parent: `roster.ae.vanilla`.

Kongo here names a fictional multi-state Congo Basin compact, not a claim that today's countries have merged. River councils and conservation authorities built its institutions around navigable routes, reservoirs and protected catchments. The Guard supports imperial industry but resists extraction that destroys the infrastructure and communities it is meant to serve.

**Doctrine:** Amphibious transport, durable infantry and concealed recovery teams.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.ae.kongo.01 | subfaction | movement_speed | +20 | selector.amphibious_vehicles | Amphibious vehicle movement speed +20% on land and water. |
| modifier.ae.kongo.02 | subfaction | health | +10 | selector.combat_infantry | Combat infantry health +10%. |
| modifier.ae.kongo.03 | subfaction | cost_credits | +20 | selector.land_artillery | Land artillery cost +20%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.ae.mamba_apc | unit.ae.okapi_amphibious_carrier |
| unit.ae.reclaimer | unit.ae.river_warden |

**Removed without replacement:** `unit.ae.sovereign_arsenal_ship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.ae.okapi_amphibious_carrier / Okapi Amphibious Carrier | 1 | structure.shared.factory | Amphibious light transport and detector; thin armor but strong passenger capacity. |
| unit.ae.river_warden / River Warden | 2 | structure.shared.barracks, structure.shared.radar | Armed repair and salvage infantry. Camouflages after 6 seconds stationary; repairing, salvaging or firing reveals it. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.ae.union_guard / Union Guard | 1 | structure.shared.barracks |
| unit.ae.pike_team / Pike Team | 1 | structure.shared.barracks |
| unit.ae.river_warden / River Warden | 2 | structure.shared.barracks, structure.shared.radar |
| unit.ae.okapi_amphibious_carrier / Okapi Amphibious Carrier | 1 | structure.shared.factory |
| unit.ae.buffalo_tank / Buffalo Tank | 1 | structure.shared.factory |
| unit.ae.weaver_aa / Weaver AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.forge_howitzer / Forge Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.kiln_assault_crawler / Kiln Assault Crawler | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.ae.sunbird_interceptor / Sunbird Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.ae.hammerhead_gunship / Hammerhead Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.ae.delta_patrol_boat / Delta Patrol Boat | 1 | structure.shared.dock |
| unit.ae.anchor_escort / Anchor Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.ae.recovery_winches`, `research.ae.circular_armor`.

**research.ae.watershed_logistics | Watershed Logistics** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Okapi carriers repair carried infantry at 1% maximum health per second after 6 seconds out of combat; free healing does not repair the carrier.

**Inherited support powers:** `power.ae.survey_network`, `power.ae.field_refurbishment`.

**power.ae.concealed_crossing | Concealed Crossing** - T2; 600 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Lay a 16-cell-long, 4-cell-wide smoke corridor on land or water for 12 seconds. It follows the shared Dust Screen damage rule and protects either side.

**Unavailable vanilla-only power:** `power.ae.recovery_priority`.

**Inherited superweapon:** `superweapon.ae.horizon_mass_driver`. Horizon is unchanged. Its slowing debris can protect a retreat, but also slows friendly vehicles.

**Opening:** Move Wardens and infantry in Okapis, attack vulnerable resource routes, and retreat damaged vehicles behind the infantry screen for repair.

**Counterplay:** Watch alternative crossings, reveal Wardens with detectors and use long-range artillery to deny safe recovery positions.

### roster.ae.south_africa | South Africa - Southern Arsenal Union

Parent: `roster.ae.vanilla`.

The Union links manufacturing cities, research institutions and organized labor under a common reconstruction charter. It supplies much of the Empire's precision machinery and insists that technical independence must include domestic control of design and production. Its influence grows with every weapon sold to its partners.

**Doctrine:** Long-range ground weapons and expensive precision vehicles.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.ae.south_africa.01 | subfaction | weapon_range_cells | +10 | selector.land_combat_vehicles | Land combat vehicle weapon range +10%. |
| modifier.ae.south_africa.02 | subfaction | cost_credits | +15 | selector.land_combat_vehicles | Land combat vehicle cost +15%. |
| modifier.ae.south_africa.03 | subfaction | build_time_seconds | +15 | selector.combat_infantry | Combat infantry build time +15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.ae.buffalo_tank | unit.ae.rhino_rail_tank |
| unit.ae.forge_howitzer | unit.ae.protea_gun_carrier |

**Removed without replacement:** `unit.ae.hammerhead_gunship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.ae.rhino_rail_tank / Rhino Rail Tank | 2 | structure.shared.factory, structure.shared.radar | Accurate anti-armor rail tank with little splash; requires Radar and cannot efficiently clear infantry alone. |
| unit.ae.protea_gun_carrier / Protea Gun Carrier | 2 | structure.shared.factory, structure.shared.radar | Switches in 3 seconds between indirect siege shells and short-range defensive canister fire; cannot use both simultaneously. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.ae.union_guard / Union Guard | 1 | structure.shared.barracks |
| unit.ae.pike_team / Pike Team | 1 | structure.shared.barracks |
| unit.ae.reclaimer / Reclaimer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.ae.mamba_apc / Mamba APC | 1 | structure.shared.factory |
| unit.ae.rhino_rail_tank / Rhino Rail Tank | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.weaver_aa / Weaver AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.protea_gun_carrier / Protea Gun Carrier | 2 | structure.shared.factory, structure.shared.radar |
| unit.ae.kiln_assault_crawler / Kiln Assault Crawler | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.ae.sunbird_interceptor / Sunbird Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.ae.delta_patrol_boat / Delta Patrol Boat | 1 | structure.shared.dock |
| unit.ae.anchor_escort / Anchor Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.ae.sovereign_arsenal_ship / Sovereign Arsenal Ship | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.ae.recovery_winches`, `research.ae.circular_armor`.

**research.ae.precision_machining | Precision Machining** - T3; 1700 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Rhino and Protea reload intervals -10%; applies in either Protea firing mode.

**Inherited support powers:** `power.ae.survey_network`, `power.ae.field_refurbishment`.

**power.ae.counterbattery_solution | Counterbattery Solution** - T2; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Reveal enemy artillery that fired during the preceding 8 seconds within a selected 9-cell area, then mark those units for 12 seconds. Friendly ground weapons deal +15% damage to marked targets.

**Unavailable vanilla-only power:** `power.ae.recovery_priority`.

**Inherited superweapon:** `superweapon.ae.horizon_mass_driver`. Horizon is unchanged. Unit-range upgrades never increase the strategic weapon's map reach.

**Opening:** Use infantry and Mambas until Radar, then establish overlapping Rhino and Protea firing lines. Keep enough AA to protect a ground-focused force.

**Counterplay:** Pressure before Radar, use infantry swarms and flanking attacks, and force expensive guns to keep changing firing modes.

## faction.sap | South Asian Protectorate

*No refuge left undefended.*

After successive grid failures and displacement crises, Indian, Pakistani and Thai successor authorities negotiated a mutual-protection compact for power, food and evacuation routes. Thailand belongs through maritime and infrastructure treaties, not through a claim that it is geographically South Asian. The Protectorate was meant to expire when civilian systems recovered. Its military council now argues that only permanent joint guardianship can prevent another catastrophe, while reformers demand the return of emergency powers to local governments.

**Doctrine:** Protected advances, resilient defenses and battlefield engineering.

**Visual direction:** Sand, indigo and saffron; layered armor, deployable braces and prominent interception sensors.

### Inherited traits
- Defensive structures gain health +15%.
- Power reserve: defenses keep operating for 20 seconds after a power shortage begins. Reserve recharges only after 60 continuous seconds of adequate power. EMP-disabled defenses remain disabled; superweapons never use this reserve.
- Land combat vehicles move 10% slower. Strengths: protected positions and measured advances. Weaknesses: slow map response and the temptation to overspend on fortifications.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.sap.01 | parent_faction | health | +15 | selector.defensive_structures | Defensive structures gain health +15%. |
| modifier.sap.02 | parent_faction | movement_speed | -10 | selector.land_combat_vehicles | Land combat vehicles move 10% slower. Strengths: protected positions and measured advances. Weaknesses: slow map response and the temptation to overspend on fortifications. |

### roster.sap.vanilla | Vanilla technology tree

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.sap.shield_rifle_squad / Shield Rifle Squad | 1 | structure.shared.barracks | General infantry with good staying power behind cover. |
| unit.sap.kavach_team / Kavach Team | 1 | structure.shared.barracks | Anti-vehicle missile infantry; cannot fire on the move. |
| unit.sap.combat_pioneer / Combat Pioneer | 2 | structure.shared.barracks, structure.shared.radar | Armed engineer building temporary cover and repairing defenses; cannot capture structures. |
| unit.sap.jackal_apc / Jackal APC | 1 | structure.shared.factory | Light transport and detector with modest armor. |
| unit.sap.bulwark_tank / Bulwark Tank | 1 | structure.shared.factory | Slow medium tank supporting infantry advances. |
| unit.sap.vajra_aa / Vajra AA | 2 | structure.shared.factory, structure.shared.radar | Dedicated mobile anti-air and detector. |
| unit.sap.monsoon_howitzer / Monsoon Howitzer | 2 | structure.shared.factory, structure.shared.radar | Steady indirect artillery with a 3-second deployment. |
| unit.sap.elephant_siege_tank / Elephant Siege Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Heavy assault gun with strong anti-structure damage and slow traverse. |
| unit.sap.garuda_interceptor / Garuda Interceptor | 2 | structure.shared.airfield, structure.shared.radar | Dedicated defensive fighter with good endurance. |
| unit.sap.sarus_gunship / Sarus Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory | Close-support anti-vehicle aircraft with a short effective range. |
| unit.sap.estuary_patrol_boat / Estuary Patrol Boat | 1 | structure.shared.dock | River and coastal scout with a light cannon. |
| unit.sap.shield_escort / Shield Escort | 2 | structure.shared.dock, structure.shared.radar | Anti-air, anti-submarine escort and detector. |
| unit.sap.citadel_monitor / Citadel Monitor | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory | Armored coastal artillery ship, slow and vulnerable without escorts. |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`.

**Buildings:** `structure.shared.headquarters`, `structure.shared.generator`, `structure.shared.refinery`, `structure.shared.barracks`, `structure.shared.factory`, `structure.shared.dock`, `structure.shared.radar`, `structure.shared.airfield`, `structure.shared.laboratory`, `structure.shared.watchtower`, `structure.shared.anti_tank_turret`, `structure.shared.aa_battery`, `structure.sap.bastion_missile_tower`, `structure.sap.trident_interception_array`.

### Inherited research

**research.sap.layered_fieldworks | Layered Fieldworks** - T2; 1000 credits; 45 seconds; requires `structure.shared.radar`.

Combat infantry within 4 cells of a friendly defensive structure take 10% less explosive damage; overlapping structures do not stack.

**research.sap.reserve_capacitors | Reserve Capacitors** - T3; 1600 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Defense power reserve increases from 20 to 35 seconds. Recharge still requires 60 continuous seconds of adequate power.

### Inherited support powers

**power.sap.recon_balloon | Recon Balloon** - T2; 450 credits per use; 90 seconds cooldown; requires powered `structure.shared.radar`.

Deploy a shootable tethered observation drone at a clear location for 20 seconds. It reveals terrain and detects within 6 cells.

**power.sap.emergency_fortification | Emergency Fortification** - T3; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`, `structure.shared.laboratory`.

Friendly defenses and production buildings in a 6-cell-radius zone take 25% less weapon damage for 15 seconds. Does not protect the superweapon structure or prevent EMP.

### Vanilla-only third power

**power.sap.protected_advance | Protected Advance** - T2; 750 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

For 12 seconds, infantry and land vehicles in a selected 6-cell-radius zone take 15% less weapon damage. Units receive no movement bonus.

### superweapon.sap.trident_interception_array | Trident Interception Array

Launcher: `structure.sap.trident_interception_array`. Recharge: 360 seconds. Warning: 6 seconds. Starts empty; maximum one stored charge.

Protects a selected 6-cell-radius zone for 25 seconds with 24 interception charges. Each incoming hostile ordinary missile or artillery shell crossing the boundary consumes one charge and is destroyed. A superweapon impact packet consumes 8 charges to reduce its damage by 50%, never to cancel it. Beams, bullets, EMP, units entering the zone and weapons fired from inside it bypass interception. The zone is fixed and clearly visible.

**Counterplay:** Exhaust charges with cheap projectiles, attack with beams or infantry, enter the zone, or wait 25 seconds. Protection can support an offensive push; it is not a permanent base shield.

**Vanilla opening:** Establish an economical infantry and Bulwark screen, protect the first expansion with a small defense cluster, then move the army forward with artillery rather than staying in the starting base.

**Fight this faction:** Expand around the slow army, bait the interception zone away from the real target, use attacks from inside its boundary and punish excessive static defense spending.

### roster.sap.india | India - Integrated Defense Command

Parent: `roster.sap.vanilla`.

The largest Protectorate member rebuilt joint logistics across a patchwork of surviving state institutions. Integrated Defense Command wants military compatibility to make mutual protection credible. Its size also makes neighboring partners wary that integration could become another word for dependence.

**Doctrine:** Heavy protected pushes supported by economical power infrastructure.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.sap.india.01 | subfaction | health | +15 | selector.land_combat_vehicles | Land combat vehicle health +15%. |
| modifier.sap.india.02 | subfaction | build_time_seconds | +15 | selector.land_combat_vehicles | Land combat vehicle build time +15%. |
| modifier.sap.india.03 | subfaction | cost_credits | -10 | selector.generators | Generator cost -10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.sap.bulwark_tank | unit.sap.arjun_assault_tank |
| unit.sap.elephant_siege_tank | unit.sap.gaj_siege_platform |

**Removed without replacement:** `unit.sap.sarus_gunship`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.sap.arjun_assault_tank / Arjun Assault Tank | 2 | structure.shared.factory, structure.shared.radar | Armored medium tank mounting a short-range active-protection system. It intercepts one ordinary missile every 15 seconds; requires Radar. |
| unit.sap.gaj_siege_platform / Gaj Siege Platform | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory | Heavy siege vehicle that deploys in 4 seconds for weapon range +20% and cannot move while deployed. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.sap.shield_rifle_squad / Shield Rifle Squad | 1 | structure.shared.barracks |
| unit.sap.kavach_team / Kavach Team | 1 | structure.shared.barracks |
| unit.sap.combat_pioneer / Combat Pioneer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.sap.jackal_apc / Jackal APC | 1 | structure.shared.factory |
| unit.sap.arjun_assault_tank / Arjun Assault Tank | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.vajra_aa / Vajra AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.monsoon_howitzer / Monsoon Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.gaj_siege_platform / Gaj Siege Platform | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.sap.garuda_interceptor / Garuda Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.sap.estuary_patrol_boat / Estuary Patrol Boat | 1 | structure.shared.dock |
| unit.sap.shield_escort / Shield Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.sap.citadel_monitor / Citadel Monitor | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.sap.layered_fieldworks`, `research.sap.reserve_capacitors`.

**research.sap.integrated_protection | Integrated Protection** - T3; 1700 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Arjun missile-interception cooldown falls from 15 to 10 seconds; Gaj gains one interceptor with the same cooldown.

**Inherited support powers:** `power.sap.recon_balloon`, `power.sap.emergency_fortification`.

**power.sap.assault_coordination | Assault Coordination** - T2; 900 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Friendly tanks in a 6-cell-radius zone gain reload interval -15% and sight +15% for 12 seconds.

**Unavailable vanilla-only power:** `power.sap.protected_advance`.

**Inherited superweapon:** `superweapon.sap.trident_interception_array`. Trident is unchanged. Use it over the destination of an armored advance rather than always over the starting base.

**Opening:** Defend with infantry until Radar, then push with Arjuns, Vajras and Gaj platforms in stages, keeping a modest power surplus.

**Counterplay:** Exploit slow production, use non-missile anti-tank weapons and force repeated Gaj redeployment.

### roster.sap.thailand | Thailand - River and Strait Command

Parent: `roster.sap.vanilla`.

Thai river authorities and maritime services joined the Protectorate to secure both inland food routes and access to the wider ocean. Their commanders favor flexible defense and evacuation over static prestige projects. They often mediate between the compact's continental powers while resisting demands to commit everything to their border disputes.

**Doctrine:** Amphibious infantry assaults and mobile defense.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.sap.thailand.01 | subfaction | cost_credits | -15 | selector.amphibious_combat_vehicles | Amphibious combat vehicle cost -15%. |
| modifier.sap.thailand.02 | subfaction | movement_speed | +10 | selector.combat_infantry | Combat infantry movement speed +10%. |
| modifier.sap.thailand.03 | subfaction | health | -10 | selector.defensive_structures | Defensive structure health -10%. |
| modifier.sap.thailand.04 | subfaction | reload_interval_seconds | +10 | selector.tanks | Tank reload interval +10%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.sap.jackal_apc | unit.sap.naga_amphibious_carrier |
| unit.sap.shield_rifle_squad | unit.sap.river_marine |

**Removed without replacement:** `unit.sap.elephant_siege_tank`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.sap.naga_amphibious_carrier / Naga Amphibious Carrier | 1 | structure.shared.factory | Amphibious light transport and detector with a smoke launcher: one 4-cell-radius, 6-second shared-rule smoke screen every 40 seconds. |
| unit.sap.river_marine / River Marine | 1 | structure.shared.barracks | Rifle infantry taking 20% less weapon damage for 6 seconds after disembarking. Immediate reboarding cannot refresh the effect. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.sap.river_marine / River Marine | 1 | structure.shared.barracks |
| unit.sap.kavach_team / Kavach Team | 1 | structure.shared.barracks |
| unit.sap.combat_pioneer / Combat Pioneer | 2 | structure.shared.barracks, structure.shared.radar |
| unit.sap.naga_amphibious_carrier / Naga Amphibious Carrier | 1 | structure.shared.factory |
| unit.sap.bulwark_tank / Bulwark Tank | 1 | structure.shared.factory |
| unit.sap.vajra_aa / Vajra AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.monsoon_howitzer / Monsoon Howitzer | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.garuda_interceptor / Garuda Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.sap.sarus_gunship / Sarus Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.sap.estuary_patrol_boat / Estuary Patrol Boat | 1 | structure.shared.dock |
| unit.sap.shield_escort / Shield Escort | 2 | structure.shared.dock, structure.shared.radar |
| unit.sap.citadel_monitor / Citadel Monitor | 3 | structure.shared.dock, structure.shared.radar, structure.shared.laboratory |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.sap.layered_fieldworks`, `research.sap.reserve_capacitors`.

**research.sap.rapid_ferry_drills | Rapid Ferry Drills** - T2; 900 credits; 45 seconds; requires `structure.shared.radar`.

Naga loading and unloading time -40%; does not change passenger attack speed.

**Inherited support powers:** `power.sap.recon_balloon`, `power.sap.emergency_fortification`.

**power.sap.mobile_reserve | Mobile Reserve** - T2; 650 credits per use; 150 seconds cooldown; requires powered `structure.shared.radar`.

Friendly ground transports in a 7-cell-radius zone gain movement speed +30% for 15 seconds and may unload while moving at half speed.

**Unavailable vanilla-only power:** `power.sap.protected_advance`.

**Inherited superweapon:** `superweapon.sap.trident_interception_array`. Trident is unchanged. The zone can cover either end of a crossing, but not both if they lie outside its radius.

**Opening:** Use Nagas to relocate infantry rapidly, keep Monsoon guns behind the landing area, and defend several approaches with a mobile reserve.

**Counterplay:** Attack after disembarkation protection expires, control crossing exits and use heavy armor against the lighter assault groups.

### roster.sap.pakistan | Pakistan - Frontier Observation Command

Parent: `roster.sap.vanilla`.

Frontier Observation Command arose from early-warning services and reconstruction troops protecting long, exposed corridors. It supports mutual protection but demands safeguards against domination by larger partners. Its doctrine emphasizes finding an attack early and disrupting it before a costly close battle begins.

**Doctrine:** Long-range missile artillery and concealed forward observation.

| Modifier ID | Layer | Stat | Delta percent | Selector | Conditions / source |
| --- | --- | --- | --- | --- | --- |
| modifier.sap.pakistan.01 | subfaction | weapon_range_cells | +15 | selector.land_artillery | Land artillery weapon range +15%. |
| modifier.sap.pakistan.02 | subfaction | projectile_flight_speed | +20 | selector.ordinary_guided_missiles | Ordinary guided-missile flight speed +20%; excludes superweapons. |
| modifier.sap.pakistan.03 | subfaction | health | -15 | selector.light_land_vehicles | Light land vehicle health -15%. |

#### Exact roster changes

| Replaced ID | Unique replacement ID |
| --- | --- |
| unit.sap.monsoon_howitzer | unit.sap.shaheen_missile_battery |
| unit.sap.combat_pioneer | unit.sap.watchpost_recon_team |

**Removed without replacement:** `unit.sap.citadel_monitor`.

#### Unique unit definitions

| Unit ID / name | Tier | Requires all structures | Role / abilities |
| --- | --- | --- | --- |
| unit.sap.shaheen_missile_battery / Shaheen Missile Battery | 2 | structure.shared.factory, structure.shared.radar | Precision missile artillery requiring 3 seconds to deploy; long reach, small blast radius and vulnerable during reload. |
| unit.sap.watchpost_recon_team / Watchpost Recon Team | 2 | structure.shared.barracks, structure.shared.radar | Detector and artillery observer that camouflages after 6 stationary seconds. Cannot build cover or repair defenses. |

#### Complete resolved combat tree

| Unit ID / name | Tier | Requires all structures |
| --- | --- | --- |
| unit.sap.shield_rifle_squad / Shield Rifle Squad | 1 | structure.shared.barracks |
| unit.sap.kavach_team / Kavach Team | 1 | structure.shared.barracks |
| unit.sap.watchpost_recon_team / Watchpost Recon Team | 2 | structure.shared.barracks, structure.shared.radar |
| unit.sap.jackal_apc / Jackal APC | 1 | structure.shared.factory |
| unit.sap.bulwark_tank / Bulwark Tank | 1 | structure.shared.factory |
| unit.sap.vajra_aa / Vajra AA | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.shaheen_missile_battery / Shaheen Missile Battery | 2 | structure.shared.factory, structure.shared.radar |
| unit.sap.elephant_siege_tank / Elephant Siege Tank | 3 | structure.shared.factory, structure.shared.radar, structure.shared.laboratory |
| unit.sap.garuda_interceptor / Garuda Interceptor | 2 | structure.shared.airfield, structure.shared.radar |
| unit.sap.sarus_gunship / Sarus Gunship | 3 | structure.shared.airfield, structure.shared.radar, structure.shared.laboratory |
| unit.sap.estuary_patrol_boat / Estuary Patrol Boat | 1 | structure.shared.dock |
| unit.sap.shield_escort / Shield Escort | 2 | structure.shared.dock, structure.shared.radar |

**Service units:** `unit.shared.engineer`, `unit.shared.collector`, `unit.shared.mobile_construction_vehicle`, `unit.shared.landing_transport`. All parent structures remain.

**Inherited research:** `research.sap.layered_fieldworks`, `research.sap.reserve_capacitors`.

**research.sap.observer_network | Observer Network** - T3; 1500 credits; 75 seconds; requires `structure.shared.radar`, `structure.shared.laboratory`.

Shaheen batteries gain reload interval -10% when their target is within 6 cells of a Watchpost team.

**Inherited support powers:** `power.sap.recon_balloon`, `power.sap.emergency_fortification`.

**power.sap.counterlaunch_plot | Counterlaunch Plot** - T2; 800 credits per use; 180 seconds cooldown; requires powered `structure.shared.radar`.

Mark enemy artillery that fired in the last 8 seconds inside a selected 8-cell-radius zone. After a 5-second warning, conventional shells hit the marked positions, not the units' new locations.

**Unavailable vanilla-only power:** `power.sap.protected_advance`.

**Inherited superweapon:** `superweapon.sap.trident_interception_array`. Trident is unchanged. Protect a missile battery during a decisive salvo, then relocate before the zone expires.

**Opening:** Scout with Jackals and Watchpost teams; protect Shaheens with Bulwarks and Vajras. Fire from unexpected angles rather than making one enormous gun line.

**Counterplay:** Hunt observers with detectors, use aircraft and fast vehicles, and move immediately after firing to evade Counterlaunch Plot.

## Modifier selector registry

Selectors are unions across entity kinds, with all-tag, any-tag and exclusion filters. Explicit ID lists further restrict selection. The JSON contains resolved eligible target IDs for each roster. Conditions still apply at runtime. Weapon/projectile domains without final specifications remain explicitly unresolved.

| Selector ID | Entity kinds | All tags | Any tags | Excluded tags | Explicit IDs | Conditions / unresolved domains |
| --- | --- | --- | --- | --- | --- | --- |
| selector.combat_units | unit | combat |  |  |  |   |
| selector.combat_infantry | unit | combat, infantry |  |  |  |   |
| selector.land_combat_vehicles | unit | combat, land_vehicle |  |  |  |   |
| selector.light_land_vehicles | unit | combat, land_vehicle, light |  |  |  |   |
| selector.aircraft | unit | combat, aircraft |  |  |  |   |
| selector.ships | unit | combat, ship |  |  |  |   |
| selector.tanks | unit | combat, tank |  |  |  |   |
| selector.land_artillery | unit | combat, land_vehicle, artillery |  |  |  |   |
| selector.ground_combat_units | unit | combat, ground |  |  |  |   |
| selector.amphibious_combat_units | unit | combat, amphibious |  |  |  |   |
| selector.amphibious_combat_vehicles | unit | combat, amphibious, land_vehicle |  |  |  |   |
| selector.amphibious_vehicles | unit | combat, amphibious, land_vehicle |  |  |  |   |
| selector.amphibious_vehicles_on_water | unit | combat, amphibious, land_vehicle |  |  |  | The vehicle is on water.  |
| selector.scouts_or_artillery | unit | combat | scout, artillery |  |  |   |
| selector.all_transports | unit | transport |  |  |  |   |
| selector.aircraft_or_ships | unit | combat | aircraft, ship |  |  |   |
| selector.unmanned_combat_units | unit | combat, unmanned |  |  |  |  Carrier-launched drones are also unmanned, but their pricing/replacement costs are unspecified. |
| selector.garrisoned_combat_infantry | unit | combat, infantry |  |  |  | The infantry unit occupies a marked civilian garrison.  |
| selector.defensive_structures | structure | defense |  |  |  |   |
| selector.generators | structure |  |  |  | structure.shared.generator |   |
| selector.refineries | structure |  |  |  | structure.shared.refinery |   |
| selector.airfields | structure |  |  |  | structure.shared.airfield |   |
| selector.structures | structure |  |  |  |  |   |
| selector.non_superweapon_structures | structure |  |  | superweapon |  |   |
| selector.land_vehicle_repairs | unit | land_vehicle |  |  |  | The target is receiving paid land-vehicle repairs.  |
| selector.thermal_beam_weapons | weapon |  |  |  |  |  Thermal-beam weapons and defenses; exact weapon registry is not yet specified. Also applies to superweapon.olm.helios_reflector |
| selector.ordinary_guided_missiles | projectile |  |  | superweapon |  |  Ordinary guided-missile projectile templates; exact weapon registry is not yet specified. |

## Campaign fault lines

### conflict.north_america_europe | North America / Europe

Both support international reconstruction, but disagree over military occupation versus binding civilian oversight. A shared relief operation can become a confrontation over who commands it.

### conflict.europe_order | Europe / Order

They need each other's ports and power exchanges. The conflict is whether water access can be guaranteed by treaty when solar plants remain under exclusive control.

### conflict.order_african_empire | Order / African Empire

Shared coastal trade encourages cooperation; rival corridor tariffs and control of desalination machinery create a practical, non-religious source of conflict.

### conflict.eurasia_han_empire | Eurasia / Han Empire

Both seek coordinated industrial recovery, but each wants authority over the continental scheduling system. Border depots and railway junctions become bargaining chips.

### conflict.pacific_han_empire | Pacific / Han Empire

Shipping access and the political independence of treaty ports are the central dispute. Capturing a port is easy compared with persuading its residents to accept the winner.

### conflict.pacific_protectorate | Pacific / Protectorate

They can cooperate over evacuation routes yet clash over who inspects maritime cargo and where foreign bases may operate.

### conflict.african_empire_protectorate | African Empire / Protectorate

They share an interest in independent reconstruction technology but compete over industrial contracts and access to eastern shipping corridors.

### conflict.every_bloc_its_own_members | Every bloc / its own members

Each campaign should include one mission where following central orders damages the faction's stated purpose. Subfactions disagree over methods, resources and authority rather than existing only as cosmetic national teams.

## Prototype priorities

1. Prototype the eight vanilla rosters before adding all 24 variants. Give each faction a playable early anti-infantry unit, anti-tank answer, detector, mobile AA and siege route before tuning special mechanics.

2. Use three map families: open land, constrained urban routes, and mixed coast/river. Include at least two exits from each starting area; avoid mandatory water for baseline economic access.

3. Measure first scout, first tank, first mobile AA, first siege and first superweapon timings. A variant that moves its tank from T1 to T2 must survive with its actual T1 roster, not an assumed inherited tank.

4. Test equal-spend armies, then repeat with reinforcements, repairs and travel time. A nominally equal fight can still favor a faction that reaches the next battle earlier.

5. Track salvage credits as a share of total income. If African wins create an excessive snowball, reduce salvage payout before weakening every unit.

6. Measure damage escaped during superweapon warnings, Tempest losses to AA, Dragonfall assembly survival and Trident charges spent. All strategic weapons should create decisions for the defender.

7. Keep duplicate command fields, repair stations and decoy income disabled. Never let a replacement inherit both its old unit's special ability and its new ability unless explicitly stated.

8. Only after these tests, assign final unit costs, health, damage, armor classes, reloads and speed. The present document is a complete faction/technology proposal, not a verified competitive balance patch.

## Deliberately unspecified

- Most combat-unit costs and build times

- Final health, damage, armor, range and speed values

- Weapon and projectile specifications

- Complete executable definitions of conditional abilities

- Terrain and pathfinding implementation

- Final borders, protagonists and campaign scripts
