# The eight factions

> **Generated** from the bible mirror (`game/data/bible/meridian_factions.json`) by `python3 tools/py/gen_factions_doc.py`. Per-unit and per-structure numbers live in the generated [unit reference](units/README.md). The bible marks all values as a first design; the shipped numbers were tuned by AI self-play and have not been playtested by humans.

## Setting

The year is 2086. The Meridian Network once linked regional power grids, freight routing, desalination controls and disaster forecasting. It did not create energy: it made a fragile, unequal world depend on coordinated delivery. During the Long Blackout of 2057, cascading technical failures and competing emergency shutdowns broke that coordination. No faction can prove whether the first failure was sabotage, negligence or an attempt to prevent something worse.

Over three decades, reconstruction commands hardened into eight rival blocs. Meridian's surviving regional control vaults can now reconnect major industrial corridors. Whoever governs those connections can restore livelihoods, ration access or shut rivals out. The war is fought for substations, ports, salvage fields, manufacturing cities and the right to decide who gets power first.

| Period | Event |
|---|---|
| 2039-2056 | **Meridian construction**: A patchwork of national projects becomes an interdependent energy and logistics system. |
| 2057 | **The Long Blackout**: Nine months of cascading regional failures trigger evacuations, rationing and emergency rule. |
| 2058-2074 | **The reconstruction wars**: Convoy services, local governments and surviving militaries form new political alliances. |
| 2075-2085 | **The corridor settlement**: Eight blocs negotiate temporary transit rights while rebuilding military industry. |
| 2086 | **The failed restart**: A disputed restart at Meridian Vault Nine cuts power to several neutral cities. Every bloc mobilizes; the responsible decision remains contested. |

Each faction offers a credible public good and an institutional danger. National names identify fictional successor commands; their doctrines come from reconstruction history. Every faction has a **vanilla** roster and three **subfaction** rosters; a subfaction changes one thing about the parent (a modifier, one replaced unit, one exclusive research or power), so a roster is always one of 32 choices.

## North American Peace Corps (NAPC)

*"Hold the line. Bring them home."*

**Doctrine.** Durable combined arms; reliable frontline vehicles and recovery.

**Look.** Olive, cream and rescue orange; broad hulls, modular armor, visible crew cabins.

**Lore.** After the Long Blackout, North American evacuation commands became the only institutions able to keep continental supply routes open. Their emergency charter hardened into the North American Peace Corps, a military reconstruction alliance rather than the historical civilian organization. Its elected Assembly promises to reopen the Meridian Network under public supervision. Generals argue that the network must first be secured by force. Communities grateful for restored power increasingly question why temporary military administrations never leave.

**Traits.**

- Land combat vehicles: health +10%, purchase cost +10%.
- Factory service apron: friendly land combat vehicles within 5 cells recover 1% maximum health per second, up to 75%, after 6 seconds without dealing or taking damage. Multiple aprons do not stack.
- Strengths: dependable armor, repair efficiency, clear combined-arms roles. Weaknesses: expensive vehicle losses and limited concealment.

**Opening.** Rifle Squad and Pathfinder scout first; two Guardians secure the first expansion. Add Sentinel AA before committing to Paladins. Preserve damaged vehicles instead of trading them.

**Counterplay.** Raid collectors while the main army repairs, attack from several directions, and use cheaper anti-tank units to punish heavy-vehicle concentration.

**Superweapon: Atlas Kinetic Array** (recharge 480 s, warning 10 s). A surviving orbital magazine releases three guided kinetic penetrators at a selected point and two points 3 cells to either side. Each has a 2-cell damage radius. It is strongest against clustered heavy vehicles and key buildings; the gaps and long warning reward dispersal. *Counterplay:* Move valuable units between the impact circles, spread essential buildings, or destroy the control structure before the warning expires.

**Support powers.** UAV Sweep, Field Repair Drop (all rosters); Combined Arms Window (vanilla roster only).

**Shared research.** Adaptive Plating, Joint Tactical Links.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Durable combined arms; reliable frontline vehicles and recovery. | Baseline roster |
| Air Mobility Command | Sustained air operations and precision strikes. | Aircraft cost -15%; Aircraft rearm time -20%; Land combat vehicle build time +15%; Raptor Multirole Fighter replaces Falcon Interceptor; Condor Stealth Bomber replaces Titan Gunship; research Dispersed Runways; power Rapid Turnaround |
| Northern Littoral Command | Amphibious armor and protected transport; useful on rivers and ordinary land. | Amphibious combat units gain health +10% on all terrain; Ship build time -15%; Amphibious vehicle movement speed on water +20%; Land artillery reload interval +15%; Beaver Amphibious APC replaces Pathfinder APC; Narwhal Amphibious Tank replaces Guardian Tank; research Sealed Compartments; power Floating Workshop |
| Federal Vanguard | Affordable assault infantry with strong urban pressure. | Combat infantry cost -15%; Combat infantry build time -20%; Aircraft cost +20%; Vanguard Rifle Squad replaces Rifle Squad; Aguila Breach Team replaces Combat Medic; research Section Logistics; power Coordinated Advance |

Full stats: [NAPC unit reference](units/napc.md); bible digest: [factions/napc.md](factions/napc.md).

## New European Confederation (NEC)

*"No city stands alone."*

**Doctrine.** Precision, sensor networks and deliberate positional warfare.

**Look.** Slate blue, white and amber; low profiles, angular turrets, fold-out sensor masts.

**Lore.** The old continental institutions failed when member governments seized their own power reserves. City leagues, surviving national services and industrial cooperatives later negotiated a new confederation with narrow but enforceable obligations. Its armies defend a dense lattice of shared sensors and guaranteed supply routes. The Confederation wants Meridian governed by treaty and transparent technical standards, yet its smaller members fear that the engineers who define those standards will quietly become the new rulers.

**Traits.**

- Networked fire: friendly combat infantry and land combat vehicles within 6 cells of a powered friendly Relay deal weapon damage +10%. Relay fields do not stack.
- All combat units cost +5%; service units are exempt.
- Strengths: precise fire, strong defensive positions and efficient local coordination. Weaknesses: costly units and dependence on vulnerable Relay coverage.

**Opening.** Establish one contested position with Jagers and Leopards; add Radar, a Relay and Rapiers. Use artillery to make opponents enter the network rather than chasing blindly.

**Counterplay.** Attack the network edges, disable power, force repeated repositioning and use cheap units to absorb slow precision volleys.

**Superweapon: Aurora Microwave Array** (recharge 420 s, warning 8 s). A microwave burst affects an 8-cell-radius zone. Enemy vehicles and aircraft lose weapons for 8 seconds; powered enemy structures shut down for 18 seconds. Vehicles can still move, aircraft do not crash, and infantry remain operational. Direct damage is light. *Counterplay:* Disperse powered infrastructure, advance with infantry, and retreat disabled vehicles. Destroying Aurora during its warning cancels the pulse.

**Support powers.** Survey Drone, Counterbattery Mission (all rosters); Treaty Coordination (vanilla roster only).

**Shared research.** Sensor Fusion, Distributed Control.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Precision, sensor networks and deliberate positional warfare. | Baseline roster |
| Northern Watch | Reconnaissance, mobile missiles and coastal denial. | Scout and artillery sight +20%; Amphibious vehicle movement speed +15% on land and water; Tank health -10%; Fen Recon Carrier replaces Surveyor APC; Fjord Missile Carrier replaces Archer SPG; research Dispersed Links; power Silent Watch |
| Franco-German Armored Directorate | Expensive armored formations and siege breakthroughs. | Tank health +15%; Tank cost +10%; All land combat vehicle build time +10%; Marte Heavy MBT replaces Leopard Tank; Charlemagne Siege Tank replaces Argent Rail Tank; research Shared Fire Solutions; power Armored Overwatch |
| Pass and Tunnel Compact | Fortified infantry, compact artillery positions and repairable defenses. | Combat infantry health +15%; Defensive structure cost -15%; Aircraft build time +20%; Alpine Pioneer replaces Sapper; Ibex Crawler Gun replaces Archer SPG; research Tunnel Workshops; power Emergency Earthworks |

Full stats: [NEC unit reference](units/nec.md); bible digest: [factions/nec.md](factions/nec.md).

## Order of the Levant and Mediterranean (OLM)

*"Keep the wells. Keep the word."*

**Doctrine.** Mobile combined arms, concealment and abundant electrical power.

**Look.** Ivory, copper and deep teal; heat shields, fabric screens and articulated wheels.

**Lore.** Desalination operators, Levantine municipal councils and Mediterranean convoy leagues created an oath-bound order to defend water and energy infrastructure during the Blackout. Membership is civic and includes many faiths and secular communities. The Order now protects a chain of coastal enclaves rather than a continuous empire. It argues that no distant government should be able to shut off another city's water. Its solar directorates nevertheless want exclusive custody of the very Meridian controls that would make such coercion possible.

**Traits.**

- Combat infantry and light land vehicles: movement speed +10%, health -10%.
- Generators produce +25% power; this creates no credits.
- Strengths: rapid repositioning, screening and energy-intensive systems. Weaknesses: fragile screens and poor prolonged frontal trades.

**Opening.** Use Caravan and Sirocco groups to threaten several routes, screen retreats with Dust Screen, and bring Observers before attempting a siege.

**Counterplay.** Keep a mobile reserve, force close fights, detect concealed observers and attack the thin frontline before energy weapons can concentrate.

**Superweapon: Helios Reflector** (recharge 480 s, warning 10 s). A surviving orbital mirror focuses sunlight along a player-selected line 16 cells long and 3 cells wide. The beam traverses the line over 12 seconds, damaging ground units, ships and structures with strong thermal damage. It cannot track units after the line is committed. *Counterplay:* Leave the marked line, attack along its flanks, and spread structures. Beam-resistant upgrades reduce its damage; smoke does not.

**Support powers.** Dust Screen, Mobile Workshop (all rosters); Open Corridor (vanilla roster only).

**Shared research.** Thermal Shrouds, Optical Mesh.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Mobile combined arms, concealment and abundant electrical power. | Baseline roster |
| Solar Directorate | Energy weapons and power-efficient late-game positions. | Generator output +20% relative to the parent faction; Thermal-beam weapon damage +15%; Land combat vehicle movement speed -10%; Dawn Laser AA replaces Crescent AA; Ifrit Prism Tank replaces Sunlance Beam Tank; research Thermal Reservoirs; power Capacitor Discharge |
| Saharan Corridor Guard | Fast light vehicles, ambushes and harassment. | Light land vehicle cost -15%; Light land vehicle build time -15%; Light land vehicle health -10%; Tank cost +15%; Dune Rover replaces Caravan APC; Scorpion Rocket Buggy replaces Sandglass Mortar; research Distributed Fuel Caches; power False Convoy |
| Western Straits Compact | Port defense, durable escorts and infantry holding power. | Ship health +15%; Garrisoned combat infantry weapon damage +20%; Aircraft cost +15%; Gate Guard replaces Wayfarer Guard; Strait Frigate replaces Lantern Escort; research Harbor Militia; power Straits Crossfire |

Full stats: [OLM unit reference](units/olm.md); bible digest: [factions/olm.md](factions/olm.md).

## Democratic Eurasian Federation (DEF)

*"A thousand districts. One supply line."*

**Doctrine.** Industrial volume, artillery saturation and replaceable armored forces.

**Look.** Oxide red, gray and pale yellow; slab armor, exposed running gear and standardized containers.

**Lore.** The Federation emerged from emergency congresses linking surviving Russian regions, Kazakh transport authorities and the northern Korean industrial state. Its charter distributes representation among territorial and workplace assemblies, but wartime production quotas give the central supply ministry enormous power. Some districts defend the federation as their only protection from abandonment; others call its elections ceremonial. It wants Meridian reopened as a shared industrial backbone and is willing to occupy reluctant junction cities to make the plan function.

**Traits.**

- Land combat vehicles: cost -10%, build time -10%, movement speed -10%.
- No free units, permanent production multiplier or unlimited passive income; numerical superiority still needs collectors and factories.
- Strengths: replacement capacity, heavy artillery and sustained pressure. Weaknesses: slow reactions, supply exposure and cumbersome late-game formations.

**Opening.** Use cheap Hammers and infantry to contest two fronts, establish the economy behind them, then build a screened Anvil line rather than rushing one expensive capstone.

**Counterplay.** Attack collectors, force artillery to redeploy, strike several fronts and avoid engaging the entire production stream head-on.

**Superweapon: Perun Missile Complex** (recharge 480 s, warning 10 s). One conventional bunker-buster missile detonates in a 3-cell-radius core, followed by a lower-damage fragmentation ring out to 7 cells. The core threatens heavy structures; the ring punishes tightly packed support units. It leaves no permanent contamination. *Counterplay:* Move away from the central marker, separate production buildings and intercept the attack by destroying the launch complex during its warning. Normal AA cannot stop the strategic missile.

**Support powers.** Mobilization Order, Tremor Barrage (all rosters); Redundant Orders (vanilla roster only).

**Shared research.** Standardized Parts, Coordinated Barrages.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Industrial volume, artillery saturation and replaceable armored forces. | Baseline roster |
| Northern Arsenal Command | Slow armored assaults with active protection. | Land combat vehicle health +15%; Land combat vehicle cost +10%; Land combat vehicle movement speed -10%; Ural Assault Tank replaces Hammer Tank; Bear Siege Crawler replaces Colossus Siege Tank; research Layered Protection; power Steel Advance |
| Steppe Transit Command | Fast reconnaissance and mobile missile warfare. | Ground combat unit movement speed +20%; Refinery build cost -15%; collectors are not discounted; Land combat vehicle health -15%; Steppe Recon Carrier replaces Mule APC; Saker Missile Truck replaces Anvil Rocket Battery; research Mobile Dispatch; power Transit Priority |
| Fortress Reconstruction Bureau | Durable infantry, prepared positions and decoys. | Combat infantry health +20%; Combat infantry build time -15%; Defensive structure cost -10%; Aircraft cost +25%; Fortress Guard replaces Line Conscript; Echo Team replaces Signal Officer; research Buried Command Lines; power False Front |

Full stats: [DEF unit reference](units/def.md); bible digest: [factions/def.md](factions/def.md).

## Pacific Dominion (PD)

*"The sea connects us."*

**Doctrine.** Amphibious maneuver, naval reach and flexible coastal logistics.

**Look.** Ocean blue, coral orange and white; sealed hulls, folding flight surfaces and deck-mounted drones.

**Lore.** Australia, Indonesian maritime leagues and Japanese industrial authorities kept each other alive through a chain of protected shipping routes. Their emergency maritime command became the Pacific Dominion: a treaty government whose authority is strongest at sea and contested on land. Its admirals want Meridian reopened without allowing a continental power to dictate access to ports. Smaller islands increasingly ask whether the Dominion's promise of open passage includes the right to refuse its bases.

**Traits.**

- Collectors are amphibious and can cross navigable water at 70% of their land speed. They still collect only from designated deposits and unload at a Refinery.
- Ships gain movement speed +15%.
- Defensive structures have health -15%. Strengths: alternative routes and mobile staging. Weaknesses: vulnerable fixed positions and costly losses during landings.

**Opening.** Use Wake Skimmers and Tide Tanks to threaten routes that conventional armies cannot cover cheaply; build enough Storm AA to protect the landing area before investing in a fleet.

**Counterplay.** Guard landing exits, attack weak static defenses and keep aircraft ready to strike isolated amphibious columns.

**Superweapon: Tempest Swarm Hub** (recharge 480 s, warning 10 s). Launches 24 autonomous strike drones toward a selected 6-cell-radius area. They attack ground and surface targets there for up to 20 seconds before their batteries expire. Drones are individually targetable by AA and their approach direction is visible. Maximum aggregate damage is high, but interception can sharply reduce it. *Counterplay:* Concentrate overlapping AA near the marked zone, move mobile units out, or destroy the hub during the warning. Drones cannot capture, scout beyond their attack zone or be salvaged.

**Support powers.** Maritime Patrol, Expeditionary Workshop (all rosters); Joint Landing (vanilla roster only).

**Shared research.** Expeditionary Maintenance, Integrated Flight Decks.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Amphibious maneuver, naval reach and flexible coastal logistics. | Baseline roster |
| Southern Reach Command | Long-range expeditionary artillery backed by reconnaissance aircraft. | Land artillery weapon range +15%; Airfield construction time -15%; Land combat vehicle health -10%; Ship build time +15%; Outrider Howitzer replaces Breaker Howitzer; Wedge Recon Fighter replaces Petrel Fighter; research Forward Fire Control; power Long Watch |
| Archipelago Defense League | Transport assaults, inexpensive marines and raids across several routes. | Combat infantry build time -15%; Transport health +20%, including Landing Transports; Tank cost +15%; Kancil Landing Skimmer replaces Wake Skimmer; Island Raider replaces Ranger Marine; research Distributed Beachheads; power Feint Landing |
| Maritime Systems Authority | Expensive precision systems, adaptable armor and advanced carriers. | Aircraft and ship reload intervals -10%; Airfield rearm time is unchanged; All combat unit cost +10%; Defensive structure health -10%; Shinano Adaptive Tank replaces Tide Tank; Shogun Drone Carrier replaces Tempest Carrier; research Predictive Maintenance; power Precision Window |

Full stats: [PD unit reference](units/pd.md); bible digest: [factions/pd.md](factions/pd.md).

## Han Empire (HAN)

*"A common future requires a common plan."*

**Doctrine.** Affordable infantry, unmanned support and vulnerable command links.

**Look.** Jade green, crimson and porcelain; compact modular hulls, sensor crowns and standardized drone racks.

**Lore.** A post-Blackout restoration movement recast the surviving Chinese central government as the Han Empire, claiming an old dynastic name for a new administrative order. In this setting the title is political, not a claim that its citizens share one ethnicity. Vietnamese and Cambodian successor governments joined through unequal security and infrastructure treaties, retaining their own armed commands. The imperial court promises to end scarcity by coordinating Meridian centrally; its provincial partners disagree sharply over who gets to write the plan.

**Traits.**

- Combat infantry cost -15% and build time -15%.
- Land combat vehicle health -10%.
- A Link Operator or Dragon Command Walker grants friendly unmanned combat units within 5 cells weapon damage +10%. Fields do not stack; destroying or suppressing the provider removes its field. Strengths: combined infantry/drone pressure; weaknesses: fragile vehicles and exposed control units.

**Opening.** Use cheap infantry to secure ground, add Ox tanks and Firefly AA, then support a Nest group with protected Link Operators.

**Counterplay.** Use area damage against infantry, prioritize command providers, force vehicle trades and do not allow several drone systems to fire behind an intact screen.

**Superweapon: Dragonfall Field Foundry** (recharge 480 s, warning 10 s). Three assembly capsules land within a marked 5-cell-radius area, then take 5 seconds to unfold into autonomous siege engines. They can be attacked during assembly. For 60 seconds after assembly they operate as slow anti-structure ground units, then their limited-energy cores expire. They cannot capture, repair, harvest, receive command-field buffs or generate salvage. *Counterplay:* Attack capsules before assembly, surround the slow engines with anti-tank units, or retreat and wait out their 60-second lifetime. Destroying the Foundry during warning cancels deployment.

**Support powers.** Wideband Scan, Software Surge (all rosters); Reserve Bandwidth (vanilla roster only).

**Shared research.** Resilient Mesh, Distributed Cognition.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Affordable infantry, unmanned support and vulnerable command links. | Baseline roster |
| Imperial Standards Army | Heavy armor and stronger local command coverage. | Land combat vehicle health +15%; Land combat vehicle cost +10%; Combat infantry build time +10%; Imperial Guard Tank replaces Ox Tank; Long Command Walker replaces Dragon Command Walker; research Guard Integration; power Central Priority |
| Canopy Defense Command | Concealed infantry and amphibious rocket raids. | Combat infantry movement speed +10%; Light land vehicle cost -10%; Tank cost +20%; Canopy Ranger replaces Banner Infantry; Reed Rocket Skimmer replaces Nest Rocket Drone; research Hidden Relays; power Broken Contact |
| Mekong Reconstruction Authority | Drone sustain, field repair and economical support systems. | Unmanned combat unit cost -15%; Repairs to friendly structures progress 25% faster; cost per health is unchanged; Tank build time +20%; Lotus Drone Tender replaces Jade Carrier; Mekong Field Engineer replaces Link Operator; research Modular Servicing; power Repair Swarm |

Full stats: [HAN unit reference](units/han.md); bible digest: [factions/han.md](factions/han.md).

## African Empire (AE)

*"What survives belongs to the future."*

**Doctrine.** Recovery, battlefield salvage and practical industrial endurance.

**Look.** Ochre, charcoal and bright cyan; repairable panels, reinforced wheels and interchangeable weapon modules.

**Lore.** Nigerian commercial and civic alliances, a Kongo basin compact and southern industrial states built a reconstruction federation around power corridors and mutual investment. Its elected High Steward adopted the title Emperor after mediating a succession of near-civil wars, turning a temporary compromise into a disputed constitutional institution. This Empire claims no automatic authority over all Africa. It wants to own the machinery of recovery rather than purchase access from outsiders, but debates over corridor revenues and the Steward's emergency powers threaten its cohesion.

**Traits.**

- Service Engineers and Reclaimers may salvage destroyed enemy land combat vehicles: an 8-second uninterrupted action yields 20% of the unit's paid purchase cost. Each wreck pays once; allied, self-destroyed, decoy and temporary summoned units produce no income.
- Land-vehicle repairs cost 25% fewer credits per health restored.
- Land artillery weapon range -10%. Strengths: sustained ground campaigns and economic recovery after winning battles. Weaknesses: must hold the battlefield to salvage, and can be outranged.

**Opening.** Use Buffalo tanks and infantry to win a local fight, secure the area, then bring salvage teams. Spend recovered credits on expansion before attempting an expensive siege push.

**Counterplay.** Disengage before losing vehicles, deny wreck fields with artillery and use air attacks to bypass the repaired frontline.

**Superweapon: Horizon Mass Driver** (recharge 480 s, warning 10 s). A rail-assisted strategic battery strikes three overlapping circles, each 3 cells in radius, along a 10-cell line over 9 seconds. Impacts damage ground units, ships and structures. On land, pulverized debris slows all land vehicles by 35% for 20 seconds and prevents new construction there; it never blocks movement or permanently changes the map. *Counterplay:* Leave the marked line before the first impact, avoid routing reinforcements through the debris, and attack from the sides. Existing buildings remain usable if they survive.

**Support powers.** Survey Network, Field Refurbishment (all rosters); Recovery Priority (vanilla roster only).

**Shared research.** Recovery Winches, Circular Armor.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Recovery, battlefield salvage and practical industrial endurance. | Baseline roster |
| Civic Logistics Directorate | Fast mobilization, infantry presence and protective drone support. | Combat infantry cost -15%; Combat infantry build time -15%; Non-superweapon structure construction time -10%; Aircraft health -10%; Civic Rifle Team replaces Union Guard; Lagos Drone Guard replaces Weaver AA; research Municipal Reserves; power Civil Defense Net |
| River Compact Guard | Amphibious transport, durable infantry and concealed recovery teams. | Amphibious vehicle movement speed +20% on land and water; Combat infantry health +10%; Land artillery cost +20%; Okapi Amphibious Carrier replaces Mamba APC; River Warden replaces Reclaimer; research Watershed Logistics; power Concealed Crossing |
| Southern Arsenal Union | Long-range ground weapons and expensive precision vehicles. | Land combat vehicle weapon range +10%; Land combat vehicle cost +15%; Combat infantry build time +15%; Rhino Rail Tank replaces Buffalo Tank; Protea Gun Carrier replaces Forge Howitzer; research Precision Machining; power Counterbattery Solution |

Full stats: [AE unit reference](units/ae.md); bible digest: [factions/ae.md](factions/ae.md).

## South Asian Protectorate (SAP)

*"No refuge left undefended."*

**Doctrine.** Protected advances, resilient defenses and battlefield engineering.

**Look.** Sand, indigo and saffron; layered armor, deployable braces and prominent interception sensors.

**Lore.** After successive grid failures and displacement crises, Indian, Pakistani and Thai successor authorities negotiated a mutual-protection compact for power, food and evacuation routes. Thailand belongs through maritime and infrastructure treaties, not through a claim that it is geographically South Asian. The Protectorate was meant to expire when civilian systems recovered. Its military council now argues that only permanent joint guardianship can prevent another catastrophe, while reformers demand the return of emergency powers to local governments.

**Traits.**

- Defensive structures gain health +15%.
- Power reserve: defenses keep operating for 20 seconds after a power shortage begins. Reserve recharges only after 60 continuous seconds of adequate power. EMP-disabled defenses remain disabled; superweapons never use this reserve.
- Land combat vehicles move 10% slower. Strengths: protected positions and measured advances. Weaknesses: slow map response and the temptation to overspend on fortifications.

**Opening.** Establish an economical infantry and Bulwark screen, protect the first expansion with a small defense cluster, then move the army forward with artillery rather than staying in the starting base.

**Counterplay.** Expand around the slow army, bait the interception zone away from the real target, use attacks from inside its boundary and punish excessive static defense spending.

**Superweapon: Trident Interception Array** (recharge 360 s, warning 6 s). Protects a selected 6-cell-radius zone for 25 seconds with 24 interception charges. Each incoming hostile ordinary missile or artillery shell crossing the boundary consumes one charge and is destroyed. A superweapon impact packet consumes 8 charges to reduce its damage by 50%, never to cancel it. Beams, bullets, EMP, units entering the zone and weapons fired from inside it bypass interception. The zone is fixed and clearly visible. *Counterplay:* Exhaust charges with cheap projectiles, attack with beams or infantry, enter the zone, or wait 25 seconds. Protection can support an offensive push; it is not a permanent base shield.

**Support powers.** Recon Balloon, Emergency Fortification (all rosters); Protected Advance (vanilla roster only).

**Shared research.** Layered Fieldworks, Reserve Capacitors.

**Rosters.**

| Roster | Identity | Change |
|---|---|---|
| Vanilla | Protected advances, resilient defenses and battlefield engineering. | Baseline roster |
| Integrated Defense Command | Heavy protected pushes supported by economical power infrastructure. | Land combat vehicle health +15%; Land combat vehicle build time +15%; Generator cost -10%; Arjun Assault Tank replaces Bulwark Tank; Gaj Siege Platform replaces Elephant Siege Tank; research Integrated Protection; power Assault Coordination |
| River and Strait Command | Amphibious infantry assaults and mobile defense. | Amphibious combat vehicle cost -15%; Combat infantry movement speed +10%; Defensive structure health -10%; Tank reload interval +10%; Naga Amphibious Carrier replaces Jackal APC; River Marine replaces Shield Rifle Squad; research Rapid Ferry Drills; power Mobile Reserve |
| Frontier Observation Command | Long-range missile artillery and concealed forward observation. | Land artillery weapon range +15%; Ordinary guided-missile flight speed +20%; excludes superweapons; Light land vehicle health -15%; Shaheen Missile Battery replaces Monsoon Howitzer; Watchpost Recon Team replaces Combat Pioneer; research Observer Network; power Counterlaunch Plot |

Full stats: [SAP unit reference](units/sap.md); bible digest: [factions/sap.md](factions/sap.md).
