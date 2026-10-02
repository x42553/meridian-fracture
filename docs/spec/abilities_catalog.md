# Meridian Fracture: Ability Catalog (appendix to abilities.md)

Status: generated from `Input/meridian_agent_reference/meridian_factions.json` by a script that asserts the row counts (156 units, 40 research, 48 support powers, 8 superweapons) and cross-checks unit tags against primitives (`detector` <=> DETECTOR, `transport` <=> TRANSPORT, `carrier` => CARRIER, `amphibious` => X:AMPHIB). Every primitive listed in section 1 is used by at least one row, so the primitive set is derived from the prose, not invented.

## 0. How to read this file

* **Primitives** are this domain's analysis vocabulary (derived from the prose, mapped to the data registry in the columns below). Unit-level primitives occupy an ability slot in `SimCompAbility`; effect primitives (research, powers, superweapons) are executed by data's `DefLayer3` (static parts), this domain's conditional and timed-effect engine, economy's power framework and `SimPowerFx`. The **Registry kind** columns map every row to `data_balance.md` 7.4 (ability kinds), 7.5 (effect ops), `economy.md` 5.18 (power kinds) and `data_balance.md` 4.1 (superweapon actions); the **Runtime owner** column of the primitive index is the recommended split (`abilities.md` 1.4 and 12.2).
* **Param syntax**: `key=value` pairs separated by `;`, nested groups in `(...)`. Units: `s` seconds, `c` cells, `%` percent, `t` ticks. The loader converts with the ARCHITECTURE section 3 rules (`ceili(seconds*20)`, `roundi(cells*1024)`). `|` inside a value separates alternatives (escaped as `\|` in the tables).
* A trailing `*` on a value means the prose is silent and the value is a **design default proposed by this spec** (balance layer may retune; it never overrides a bible number).
* **X:** column = behavior owned by another domain (weapon data, ammo/sortie, movement class, economy...). The ability system only provides the hooks named in `abilities.md`.
* Param names are descriptive; the registry names are those of `data_balance.md` 7.4 (for example `arm` = `delay_s`, `deploy` / `pack` = `deploy_s` / `pack_s`, `cap` = `capacity_squads_n`, `pax_fire` = `passengers_fire`; `off_when=` on an AURA row = the provider-activity rules of `abilities.md` 5.7.1: death always, `suppressed` = `combat.is_suppressed`).
* `CUSTOM(...)` = prose not expressible as a primitive; the description says what is implemented instead (all such cases are listed in section 6).
* `-` = no ability primitive: the role text is fully covered by stats/weapons in the balance layer.

## 1. Primitive index

| Primitive | Class | Rows using it | Runtime owner (recommended split) |
|---|---|---|---|
| DETECTOR | unit/structure ability (slot) | 44 | abilities |
| CLOAK | unit/structure ability (slot) | 8 | abilities |
| SUBMERGE | unit/structure ability (slot) | 1 | abilities (+combat want_surface) |
| MODE_SWITCH | unit/structure ability (slot) | 19 | abilities (+combat want/ext protocol) |
| FIRE_GATE | unit/structure ability (slot) | 3 | combat (weapon gating flag) |
| FACING_ARMOR | unit/structure ability (slot) | 4 | combat (static dir_rows / presist) |
| ACTIVE_PROTECTION | unit/structure ability (slot) | 4 | combat (point defence, PD_APS_*) |
| AURA | unit/structure ability (slot) | 18 | abilities (effects pushed to combat as leases) |
| TRANSPORT | unit/structure ability (slot) | 18 | abilities (SimTransport; combat ejects on death) |
| GARRISON | unit/structure ability (slot) | 1 | abilities (SimTransport; combat garrison_fire) |
| DISEMBARK_BUFF | unit/structure ability (slot) | 3 | abilities |
| SPAWN_ZONE | unit/structure ability (slot) | 7 | abilities (zones) |
| SUMMON_ATTACHED | unit/structure ability (slot) | 1 | abilities |
| CARRIER | unit/structure ability (slot) | 3 | combat (SimCarrierOps, drone defs from data) |
| REPAIR_ACTOR | unit/structure ability (slot) | 8 | abilities SimChannel (economy: credits, order approach) |
| SALVAGE | unit/structure ability (slot) | 3 | abilities SimChannel (combat: wreck record; economy: credits) |
| CAPTURE | unit/structure ability (slot) | 2 | abilities SimChannel (economy: neutral rules) |
| STAT_MOD | effect (research/trait/power/superweapon) | 18 | data DefLayer3 (unconditional); abilities (conditional, temporary) |
| PARAM_MOD | effect (research/trait/power/superweapon) | 20 | data DefLayer3 |
| GRANT_ABILITY | effect (research/trait/power/superweapon) | 6 | data DefLayer3 + abilities (instantiate) |
| STATUS_AREA | effect (research/trait/power/superweapon) | 20 | economy (framework) + abilities (apply_timed_effect) |
| STATUS_PLAYER | effect (research/trait/power/superweapon) | 6 | economy (framework) + abilities (SimPlayerFx windows) |
| REVEAL_ZONE | effect (research/trait/power/superweapon) | 7 | economy (framework) + abilities (vision reveal) |
| REPAIR_ZONE | effect (research/trait/power/superweapon) | 6 | economy (framework) + abilities (zones) |
| SMOKE_ZONE | effect (research/trait/power/superweapon) | 3 | economy (framework) + abilities (zones) |
| DECOY_GROUP | effect (research/trait/power/superweapon) | 3 | economy (framework) + abilities (zones, summons) |
| STRIKE_BARRAGE | effect (research/trait/power/superweapon) | 3 | economy (framework) + combat (spawn_remote shells) |
| MARK_TARGETS | effect (research/trait/power/superweapon) | 2 | economy (framework) + abilities (mark effect) + combat (fire log) |
| EMP_PULSE | effect (research/trait/power/superweapon) | 1 | economy (schedule) + combat (EMP warhead) |
| SWARM_SUMMON | effect (research/trait/power/superweapon) | 1 | economy (framework) + abilities (SimSummons) |
| ENGINE_DROP | effect (research/trait/power/superweapon) | 1 | economy (framework) + abilities (SimSummons) |
| DEBRIS_ZONE | effect (research/trait/power/superweapon) | 1 | abilities (zones) |
| INTERCEPT_ZONE | effect (research/trait/power/superweapon) | 1 | abilities (zones) + combat (hooks) |
| IMPACT_PACKETS | effect (research/trait/power/superweapon) | 4 | economy (schedule) + combat (strike projectiles) |

Total primitives: **34** (17 slot abilities + 17 effects).

## 2. Units (156)

### 2.1 Shared service units (4)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.shared.engineer` | service T1 | CAPTURE(target=neutral_tech;deny=enemy_production,superweapon;time=10s*); REPAIR_ACTOR(targets=land_vehicle,structure;rate=1%/s;cost=0.5%price/s;range=1c*;not_self=1); SALVAGE(time=8s;payout=20%;AE_roster_only=granted_by_trait) | capture, repair, salvage | X:ECON(cost=500) | No weapon. SALVAGE is granted only in AE rosters by faction trait (GRANT_ABILITY). |
| `unit.shared.collector` | service T1 | - | - | X:ECON(harvest);X:MOVE(PD roster override: amphibious, water speed 70% of land) | - |
| `unit.shared.mobile_construction_vehicle` | service T2 | - | - | X:PROD(deploys into HQ) | Deploy-to-structure is a production transform, not an ability slot. |
| `unit.shared.landing_transport` | service T1 | TRANSPORT(cap_slots=4;infantry=1slot;vehicle=2slots;vehicle_cls=non_amphibious_land;deny=transport,mcv;pax_fire=no) | transport | X:AMPHIB | - |

### 2.2 North American Peace Corps (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.napc.rifle_squad` | base T1 | - | - | - | - |
| `unit.napc.javelin_team` | base T1 | FIRE_GATE(mode=stationary) | flag UF_FIRE_STATIONARY | - | - |
| `unit.napc.combat_medic` | base T2 | AURA(class=MEDIC;fx=heal;r=4c*;rate=3%/s*;targets=friendly_infantry;not_self=1;same_source=max) | ? | - | Unarmed; heals infantry only, never vehicles. |
| `unit.napc.pathfinder_apc` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | - | - |
| `unit.napc.guardian_tank` | base T1 | - | - | - | - |
| `unit.napc.sentinel_aa` | base T2 | DETECTOR(r=5c) | detector | - | - |
| `unit.napc.paladin_howitzer` | base T2 | MODE_SWITCH(modes=mobile\|siege;deploy=3s;pack=3s*;fire_only_in=siege;immobile_in=siege) | deploy | - | - |
| `unit.napc.bastion_heavy_tank` | base T3 | - | - | - | - |
| `unit.napc.falcon_interceptor` | base T2 | - | - | X:AMMO(rearm) | - |
| `unit.napc.titan_gunship` | base T3 | - | - | X:MOVE(hover) | - |
| `unit.napc.riverwatch_patrol_boat` | base T1 | - | - | - | - |
| `unit.napc.aegis_frigate` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.napc.liberty_arsenal_ship` | base T3 | - | - | - | - |
| `unit.napc.raptor_multirole_fighter` | unique T2 | MODE_SWITCH(modes=AA_load\|AV_load;switch_at=airfield_pad;switch_time=rearm_time*;not_both=1) | mode_switch | X:AMMO | - |
| `unit.napc.condor_stealth_bomber` | unique T3 | CLOAK(arm=6s;quiet=no_attack,no_damage;while_moving=1;reveal=fire,damage) | camouflage | X:AMMO(bombs=1/sortie;slow_rearm) | Weak protection when detected = armor stat. |
| `unit.napc.beaver_amphibious_apc` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no;death_loss=20%*); DETECTOR(r=5c) | transport, detector | X:AMPHIB | Reinforced passenger protection = lower death_loss. |
| `unit.napc.narwhal_amphibious_tank` | unique T2 | - | - | X:AMPHIB | Water bonuses come from Canada modifiers and Sealed Compartments (conditional ON_WATER). |
| `unit.napc.vanguard_rifle_squad` | unique T1 | SPAWN_ZONE(zone=COVER;build=4s;pack=2s;life=45s;max_per_builder=1;resist=20%bullet;occupant=builder;requires=stationary) | portable_cover | - | - |
| `unit.napc.aguila_breach_team` | unique T2 | - | - | X:WEAPON(breach_charge vs structures;short grenade launcher) | Cannot heal (no MEDIC aura). |

### 2.3 New European Confederation (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.nec.jager_squad` | base T1 | - | - | X:ARMOR(area-vulnerable) | - |
| `unit.nec.spike_team` | base T1 | FIRE_GATE(mode=stationary) | flag UF_FIRE_STATIONARY | - | - |
| `unit.nec.sapper` | base T2 | SPAWN_ZONE(zone=COVER;build=4s;life=45s;max_per_builder=1;resist=20%bullet) | portable_cover | - | Cannot replace Engineer: no CAPTURE/REPAIR. |
| `unit.nec.surveyor_apc` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | - | - |
| `unit.nec.leopard_tank` | base T1 | - | - | - | - |
| `unit.nec.rapier_aa` | base T2 | DETECTOR(r=5c) | detector | - | - |
| `unit.nec.archer_spg` | base T2 | MODE_SWITCH(modes=mobile\|siege;deploy=4s*;pack=4s*;fire_only_in=siege;immobile_in=siege) | deploy | - | Prose: slow to deploy. |
| `unit.nec.argent_rail_tank` | base T3 | - | - | - | - |
| `unit.nec.kestrel_interceptor` | base T2 | - | - | X:AMMO(short_rearm) | - |
| `unit.nec.aster_ew_aircraft` | base T3 | AURA(class=JAM;fx=stat;stat=sight;delta=-25%;r=5c;targets=enemy_units;spare=weapon_range,detect_radius;same_source=max) | ? | - | - |
| `unit.nec.skerry_patrol_boat` | base T1 | - | - | - | - |
| `unit.nec.horizon_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.nec.concord_monitor` | base T3 | - | - | - | - |
| `unit.nec.fen_recon_carrier` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c;deployed_r=6c); MODE_SWITCH(modes=mobile\|mast;deploy=2s*;pack=2s*;immobile_in=mast;exposed_in=mast(no camouflage of any source)) | transport, detector, sensor_mast | X:AMPHIB | Field via Dispersed Links research (AURA class RELAY, granted). |
| `unit.nec.fjord_missile_carrier` | unique T2 | MODE_SWITCH(modes=mobile\|siege;deploy=1.5s*;pack=1.5s*;fire_only_in=siege;immobile_in=siege) | deploy | X:AMPHIB | Fast redeployment. |
| `unit.nec.marte_heavy_mbt` | unique T2 | FACING_ARMOR(front_arc=120deg*;front_resist=15%*;types=all) | directional_armor | X:MOVE(slow_accel) | - |
| `unit.nec.charlemagne_siege_tank` | unique T3 | MODE_SWITCH(modes=mobile\|siege;deploy=4s;pack=4s*;range=+25%;immobile_in=siege;no_hull_turn_in=siege) | deploy | - | - |
| `unit.nec.alpine_pioneer` | unique T2 | SPAWN_ZONE(zone=COVER;alias=shelter;build=4s*;life=45s;max_per_builder=1;resist=25%bullet); REPAIR_ACTOR(targets=friendly_defense_structure;rate=1%/s*;cost=0.5%price/s;range=1c*) | portable_cover, repair | - | - |
| `unit.nec.ibex_crawler_gun` | unique T2 | MODE_SWITCH(modes=mobile\|siege;deploy=2s;pack=2s*;fire_only_in=siege;immobile_in=siege); FACING_ARMOR(front_arc=120deg*;front_resist=25%*;rear_penalty=15%*;types=all) | deploy, directional_armor | - | - |

### 2.4 Order of the Levant and Mediterranean (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.olm.wayfarer_guard` | base T1 | - | - | - | - |
| `unit.olm.needle_team` | base T1 | - | - | - | - |
| `unit.olm.mirage_observer` | base T2 | DETECTOR(r=5c); CLOAK(arm=6s;quiet=stationary,no_attack,no_damage;reveal=move,fire,damage); AURA(class=spot_mirage;fx=tag;r=6c*;artillery_range_bonus=0) | detector, camouflage, spotter | - | Registry kind `spotter` (id 26): 'artillery spotter' has no numeric effect in the bible, so `artillery_range_bonus_pct` stays 0 (abilities.md section 12.1, item 1). |
| `unit.olm.caravan_apc` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | - | - |
| `unit.olm.sirocco_tank` | base T1 | - | - | - | - |
| `unit.olm.crescent_aa` | base T2 | DETECTOR(r=5c) | detector | - | - |
| `unit.olm.sandglass_mortar` | base T2 | MODE_SWITCH(modes=mobile\|siege;deploy=2s*;pack=2s*;fire_only_in=siege;immobile_in=siege) | deploy | - | - |
| `unit.olm.sunlance_beam_tank` | base T3 | - | - | X:WEAPON(thermal beam; damage over time on single target; cooling interval) | - |
| `unit.olm.shrike_interceptor` | base T2 | - | - | X:AMMO(limited_endurance) | - |
| `unit.olm.nightjar_strike_drone` | base T3 | - | - | X:AMMO(salvos=1/sortie) | - |
| `unit.olm.corsair_patrol_boat` | base T1 | - | - | - | - |
| `unit.olm.lantern_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.olm.beacon_missile_ship` | base T3 | - | - | - | - |
| `unit.olm.dawn_laser_aa` | unique T2 | DETECTOR(r=5c) | detector | X:WEAPON(continuous AA laser; thermal_beam tag assumed) | - |
| `unit.olm.ifrit_prism_tank` | unique T3 | MODE_SWITCH(modes=mobile\|prism;deploy=3s;pack=3s*;fire_only_in=prism;immobile_in=prism;needs_los=1;no_bounce=1) | deploy | X:WEAPON(anti-structure thermal beam) | - |
| `unit.olm.dune_rover` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c); CLOAK(arm=6s;quiet=no_attack;while_moving=1;reveal=fire,damage,detect;reveal_linger=6s on damage\|detect) | transport, detector, camouflage | - | - |
| `unit.olm.scorpion_rocket_buggy` | unique T2 | - | - | X:WEAPON(short salvo, long reload; no deploy) | - |
| `unit.olm.gate_guard` | unique T1 | FACING_ARMOR(front_arc=120deg*;front_resist=25%;types=bullet;blast_and_rear_excluded=1) | frontal_shield | X:MOVE(slower) | - |
| `unit.olm.strait_frigate` | unique T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater;short-range surface guns) | - |

### 2.5 Democratic Eurasian Federation (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.def.line_conscript` | base T1 | - | - | - | - |
| `unit.def.recoil_team` | base T1 | - | - | - | - |
| `unit.def.signal_officer` | base T2 | DETECTOR(r=5c); AURA(class=SUPPRESS_REC;fx=stat;stat=suppression_recovery;delta=+50%;r=5c;targets=friendly_infantry;same_source=max) | detector, ? | - | - |
| `unit.def.mule_apc` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | - | - |
| `unit.def.hammer_tank` | base T1 | - | - | X:SIGHT(modest) | - |
| `unit.def.porcupine_aa` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(flak vs air+light infantry) | - |
| `unit.def.anvil_rocket_battery` | base T2 | - | - | X:WEAPON(wide barrage; inaccurate vs moving) | - |
| `unit.def.colossus_siege_tank` | base T3 | - | - | - | - |
| `unit.def.kite_interceptor` | base T2 | - | - | - | - |
| `unit.def.burya_bomber` | base T3 | - | - | - | - |
| `unit.def.picket_boat` | base T1 | - | - | - | - |
| `unit.def.rampart_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.def.boreal_missile_submarine` | base T3 | SUBMERGE(stealth=submarine;surface_on_fire=1;hold_surface=8s;transition=1s*;underwater_target_only=asw;strategic_blast_hits=1) | submerge | - | - |
| `unit.def.ural_assault_tank` | unique T2 | ACTIVE_PROTECTION(intercept=missile;cooldown=12s;charges=1;not=shell,beam,strategic) | interceptor | - | - |
| `unit.def.bear_siege_crawler` | unique T3 | FACING_ARMOR(front_arc=120deg*;front_resist=30%*;rear_penalty=25%*;types=all) | directional_armor | X:SIGHT(poor);X:WEAPON(demolition cannon) | Gains ACTIVE_PROTECTION via Layered Protection (GRANT). |
| `unit.def.steppe_recon_carrier` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | X:SIGHT(extended) | - |
| `unit.def.saker_missile_truck` | unique T2 | MODE_SWITCH(modes=mobile\|siege;deploy=1s;pack=1s*;fire_only_in=siege;immobile_in=siege) | deploy | - | - |
| `unit.def.fortress_guard` | unique T1 | MODE_SWITCH(modes=mobile\|deployed;deploy=3s;pack=3s*;immobile_in=deployed;weapon_in_deployed=strong_suppressive) | deploy | X:WEAPON(suppressive) | Fortress Guard fire is suppressive per rule.combat.suppression_cover_and_smoke. |
| `unit.def.echo_team` | unique T2 | DETECTOR(r=5c); AURA(class=SUPPRESS_REC;fx=stat;stat=suppression_recovery;delta=+50%;r=5c;targets=friendly_infantry;same_source=max); SPAWN_ZONE(zone=DECOY;decoy_of=tank;count=1;life=30s;cooldown=40s;hp=1;non_blocking=1;max_active=1) | detector, ?, decoy_spawn | - | - |

### 2.6 Pacific Dominion (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.pd.ranger_marine` | base T1 | - | - | - | CUSTOM(flavor): 'optimized after transport deployment' has no number; recommended DISEMBARK_BUFF dmg +10% 4s (balance option, off by default). |
| `unit.pd.harpoon_team` | base T1 | - | - | X:WEAPON(layers=ground,surface; never air) | - |
| `unit.pd.reef_technician` | base T2 | REPAIR_ACTOR(targets=land_vehicle,ship;rate=1%/s*;cost=0.5%price/s;range=3c*;one_target=1;not_self=1;works_while_carried=research) | repair | - | - |
| `unit.pd.wake_skimmer` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | X:AMPHIB | - |
| `unit.pd.tide_tank` | base T1 | - | - | X:AMPHIB;X:MOVE(slow on water) | - |
| `unit.pd.storm_aa` | base T2 | DETECTOR(r=5c) | detector | X:MOVE(needs transport across water) | - |
| `unit.pd.breaker_howitzer` | base T2 | - | - | - | - |
| `unit.pd.leviathan_assault_carrier` | base T3 | TRANSPORT(cap=4;cls=infantry;pax_fire=no) | transport | X:AMPHIB;X:WEAPON(short siege cannon) | - |
| `unit.pd.petrel_fighter` | base T2 | - | - | - | - |
| `unit.pd.osprey_strike_tiltrotor` | base T3 | - | - | X:MOVE(hover when firing) | - |
| `unit.pd.reef_patrol_boat` | base T1 | - | - | - | - |
| `unit.pd.trident_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.pd.tempest_carrier` | base T3 | CARRIER(wings=strike;drone=surface_strike;hangar=6*;replace=20s*;replace_cost=0*;leash=12c*;recall=1;own_drones_only=1) | carrier | - | - |
| `unit.pd.outrider_howitzer` | unique T2 | MODE_SWITCH(modes=mobile\|siege;deploy=3s;pack=3s*;fire_only_in=siege;immobile_in=siege) | deploy | X:WEAPON(narrow firing arc) | - |
| `unit.pd.wedge_recon_fighter` | unique T2 | DETECTOR(r=5c); AURA(class=SPOT_WEDGE;fx=tag;r=6c;targets=friendly_artillery_targets) | detector, ? | X:SIGHT(extended) | SPOT_WEDGE only feeds Forward Fire Control (target-side condition). |
| `unit.pd.kancil_landing_skimmer` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no;unload_time=-50%); DETECTOR(r=5c) | transport, detector | X:AMPHIB | - |
| `unit.pd.island_raider` | unique T1 | DISEMBARK_BUFF(stat=weapon_damage;delta=+20%;dur=6s;refresh=none) | disembark_buff | - | - |
| `unit.pd.shinano_adaptive_tank` | unique T2 | MODE_SWITCH(modes=mobile_direct\|siege;switch=3s;fire_only_in_each=own_weapon;siege_immobile=1;siege_no_anti_infantry=1) | mode_switch | X:AMPHIB | - |
| `unit.pd.shogun_drone_carrier` | unique T3 | CARRIER(wings=strike\|interceptor;drone=surface_strike\|interceptor;one_wing_at_a_time=1;wing_switch=5s*;hangar=6*;replace=20s*;replace_cost=0*;leash=12c*;recall=1) | carrier | - | - |

### 2.7 Han Empire (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.han.banner_infantry` | base T1 | - | - | - | - |
| `unit.han.lance_team` | base T1 | - | - | - | - |
| `unit.han.link_operator` | base T2 | DETECTOR(r=5c); AURA(class=COMMAND;fx=stat;stat=weapon_damage;delta=+10%;r=5c;targets=friendly_unmanned_combat;off_when=dead,suppressed;same_source=none_stack) | detector, ? | - | - |
| `unit.han.jade_carrier` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | - | - |
| `unit.han.ox_tank` | base T1 | - | - | - | - |
| `unit.han.firefly_aa_drone` | base T2 | DETECTOR(r=5c) | detector | TAG:unmanned | - |
| `unit.han.nest_rocket_drone` | base T2 | - | - | TAG:unmanned | - |
| `unit.han.dragon_command_walker` | base T3 | AURA(class=COMMAND;fx=stat;stat=weapon_damage;delta=+10%;r=5c;targets=friendly_unmanned_combat;off_when=dead,suppressed) | ? | X:HP(large target) | Crewed: not a command-field recipient. |
| `unit.han.swallow_interceptor` | base T2 | - | - | TAG:unmanned | - |
| `unit.han.silkwing_drone_bomber` | base T3 | - | - | TAG:unmanned;X:AMMO(slow_rearm) | - |
| `unit.han.canal_patrol_boat` | base T1 | - | - | - | - |
| `unit.han.jade_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.han.emperor_drone_ship` | base T3 | CARRIER(wings=strike;drone=unmanned_surface_strike;hangar=6*;replace=20s*;replace_cost=0*;leash=12c*;recall=1) | carrier | - | - |
| `unit.han.imperial_guard_tank` | unique T2 | - | - | - | Command-field recipient only after Guard Integration (PARAM_MOD). |
| `unit.han.long_command_walker` | unique T3 | AURA(class=COMMAND;fx=stat;stat=weapon_damage;delta=+10%;r=5c;targets=friendly_unmanned_combat;off_when=dead,suppressed); MODE_SWITCH(modes=mobile\|deployed;deploy=3s;pack=3s*;immobile_in=deployed;aura_r_add_in_deployed=+2c) | ?, deploy | - | - |
| `unit.han.canopy_ranger` | unique T1 | CLOAK(arm=6s;quiet=stationary,no_attack,no_damage;terrain=any;reveal=move,fire,damage) | camouflage | - | - |
| `unit.han.reed_rocket_skimmer` | unique T2 | - | - | TAG:unmanned;X:AMPHIB | - |
| `unit.han.lotus_drone_tender` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c); REPAIR_ACTOR(targets=friendly_unmanned_land;rate=1%/s;cost=0.5%price/s;range=3c*;one_target=1;not_self=1) | transport, detector, repair | - | - |
| `unit.han.mekong_field_engineer` | unique T2 | DETECTOR(r=5c); REPAIR_ACTOR(targets=friendly_structure;rate=1%/s*;cost=0.5%price/s;range=1c*); MODE_SWITCH(modes=mobile\|deployed;deploy=2s;pack=2s*;immobile_in=deployed;enables=AURA); AURA(class=COMMAND;fx=stat;stat=weapon_damage;delta=+10%;r=5c;targets=friendly_unmanned_combat;requires=deployed;off_when=dead,suppressed) | detector, repair, deploy, ? | - | Service Engineers remain available; unit is not a service unit. |

### 2.8 African Empire (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.ae.union_guard` | base T1 | - | - | - | - |
| `unit.ae.pike_team` | base T1 | - | - | - | - |
| `unit.ae.reclaimer` | base T2 | REPAIR_ACTOR(targets=land_vehicle;rate=1%/s;cost=0.5%price/s;range=1c*;one_target=1); SALVAGE(time=8s;payout=20%;target=enemy_land_combat_vehicle_wreck;pays_once=1) | repair, salvage | - | Armed salvage specialist. Rate = normal Engineer rate. |
| `unit.ae.mamba_apc` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | X:MOVE(road bonus) | - |
| `unit.ae.buffalo_tank` | base T1 | - | - | - | - |
| `unit.ae.weaver_aa` | base T2 | DETECTOR(r=5c) | detector | - | - |
| `unit.ae.forge_howitzer` | base T2 | - | - | - | - |
| `unit.ae.kiln_assault_crawler` | base T3 | - | - | - | - |
| `unit.ae.sunbird_interceptor` | base T2 | - | - | - | - |
| `unit.ae.hammerhead_gunship` | base T3 | - | - | - | - |
| `unit.ae.delta_patrol_boat` | base T1 | - | - | - | - |
| `unit.ae.anchor_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.ae.sovereign_arsenal_ship` | base T3 | - | - | - | - |
| `unit.ae.civic_rifle_team` | unique T1 | SPAWN_ZONE(zone=SENSOR_PUCK;life=20s;cooldown=30s;reveal_r=4c;detect=no;body_hp=destructible*;max_active=1) | sensor_puck | - | - |
| `unit.ae.lagos_drone_guard` | unique T2 | DETECTOR(r=5c); SUMMON_ATTACHED(def=repair_drone;count=1;fx=heal;targets=friendly_infantry;rate=1%/s;r=3c*;one_target=1;shootable=1;respawn=90s*) | detector, summon_orbit | - | - |
| `unit.ae.okapi_amphibious_carrier` | unique T1 | TRANSPORT(cap=3;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | X:AMPHIB | Thin armor: stat. |
| `unit.ae.river_warden` | unique T2 | CLOAK(arm=6s;quiet=stationary,no_attack,no_damage,no_action;reveal=move,fire,damage,repair,salvage); REPAIR_ACTOR(targets=land_vehicle;rate=1%/s;cost=0.5%price/s;range=1c*;one_target=1); SALVAGE(time=8s;payout=20%;target=enemy_land_combat_vehicle_wreck;pays_once=1) | camouflage, repair, salvage | - | - |
| `unit.ae.rhino_rail_tank` | unique T2 | - | - | - | - |
| `unit.ae.protea_gun_carrier` | unique T2 | MODE_SWITCH(modes=siege_shell\|canister;switch=3s;not_both=1;siege_immobile=1) | mode_switch | - | - |

### 2.9 South Asian Protectorate (19)

| Unit id | Class / tier | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|---|
| `unit.sap.shield_rifle_squad` | base T1 | - | - | - | CUSTOM(flavor): 'good staying power behind cover' has no number; realized as health stat only. |
| `unit.sap.kavach_team` | base T1 | FIRE_GATE(mode=no_fire_while_moving) | flag UF_FIRE_STATIONARY | - | - |
| `unit.sap.combat_pioneer` | base T2 | SPAWN_ZONE(zone=COVER;build=4s;life=45s;max_per_builder=1;resist=20%bullet); REPAIR_ACTOR(targets=friendly_defense_structure;rate=1%/s*;cost=0.5%price/s;range=1c*) | portable_cover, repair | - | Cannot capture structures (no CAPTURE). |
| `unit.sap.jackal_apc` | base T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c) | transport, detector | - | - |
| `unit.sap.bulwark_tank` | base T1 | - | - | - | - |
| `unit.sap.vajra_aa` | base T2 | DETECTOR(r=5c) | detector | - | - |
| `unit.sap.monsoon_howitzer` | base T2 | MODE_SWITCH(modes=mobile\|siege;deploy=3s;pack=3s*;fire_only_in=siege;immobile_in=siege) | deploy | - | - |
| `unit.sap.elephant_siege_tank` | base T3 | - | - | - | - |
| `unit.sap.garuda_interceptor` | base T2 | - | - | - | - |
| `unit.sap.sarus_gunship` | base T3 | - | - | - | - |
| `unit.sap.estuary_patrol_boat` | base T1 | - | - | - | - |
| `unit.sap.shield_escort` | base T2 | DETECTOR(r=5c) | detector | X:WEAPON(layers=air,underwater) | - |
| `unit.sap.citadel_monitor` | base T3 | - | - | - | - |
| `unit.sap.arjun_assault_tank` | unique T2 | ACTIVE_PROTECTION(intercept=missile;cooldown=15s;charges=1;not=shell,beam,strategic;range=short) | interceptor | - | - |
| `unit.sap.gaj_siege_platform` | unique T3 | MODE_SWITCH(modes=mobile\|siege;deploy=4s;pack=4s*;range=+20%;immobile_in=siege) | deploy | - | - |
| `unit.sap.naga_amphibious_carrier` | unique T1 | TRANSPORT(cap=2;cls=infantry;pax_fire=no); DETECTOR(r=5c); SPAWN_ZONE(zone=SMOKE;r=4c;life=6s;cooldown=40s;rule=dust_screen) | transport, detector, smoke_launcher | X:AMPHIB | - |
| `unit.sap.river_marine` | unique T1 | DISEMBARK_BUFF(stat=damage_taken;delta=-20%;dur=6s;refresh=none) | disembark_buff | - | - |
| `unit.sap.shaheen_missile_battery` | unique T2 | MODE_SWITCH(modes=mobile\|siege;deploy=3s;pack=3s*;fire_only_in=siege;immobile_in=siege) | deploy | - | - |
| `unit.sap.watchpost_recon_team` | unique T2 | DETECTOR(r=5c); CLOAK(arm=6s;quiet=stationary,no_attack,no_damage;reveal=move,fire,damage); AURA(class=SPOT_WATCHPOST;fx=tag;r=6c;targets=friendly_artillery_targets) | detector, camouflage, ? | - | Cannot build cover or repair defenses. SPOT_WATCHPOST only feeds Observer Network. |

## 2b. Structures (29) and neutral map objects (2)

Not part of the 156 unit rows. Structures carry abilities only through the rows below or through GRANT_ABILITY effects.

| Structure id | Primitives and parameters | Registry kind (data 7.4) | External (X:) | Note |
|---|---|---|---|---|
| `structure.shared.headquarters` | - | - | X:PROD(build radius 8c) | - |
| `structure.shared.generator` | - | - | X:POWER(+150; OLM +25% typed) | - |
| `structure.shared.refinery` | - | - | X:ECON | Provider of aura class BARRACKS_REFINERY when Municipal Reserves is researched (AE Nigeria). |
| `structure.shared.barracks` | - | - | X:PROD | Provider of BARRACKS_REFINERY (Municipal Reserves) and grant target of BARRACKS_REGEN (Section Logistics). |
| `structure.shared.factory` | AURA(class=APRON;fx=heal;rate=1%/s;cap=75%maxhp;r=5c;targets=friendly_land_combat_vehicle;recipient_cond=OUT_OF_COMBAT(6s);same_source=max;roster=NAPC_trait) | ? | X:PROD | APRON exists only in NAPC rosters (faction trait). Provider of FACTORY_DOCK when Harbor Militia is researched. |
| `structure.shared.dock` | - | - | X:PROD;X:MAP(shoreline) | Provider of FACTORY_DOCK when Harbor Militia is researched. |
| `structure.shared.radar` | - | - | X:POWER(gates T2 powers) | Target of Buried Command Lines (EMP recovery -25%). |
| `structure.shared.airfield` | - | - | X:AIR(pads=4;rearm) | Dispersed Runways: pads +2. Rapid Turnaround: rearm +50% rate on one airfield. |
| `structure.shared.laboratory` | - | - | X:POWER(gates T3 powers) | - |
| `structure.shared.watchtower` | DETECTOR(r=4c) | detector | X:WEAPON(anti-infantry, suppressive) | Detector radius 4 (bible), not the default 5. |
| `structure.shared.anti_tank_turret` | - | - | X:WEAPON | - |
| `structure.shared.aa_battery` | DETECTOR(r=5c) | detector | X:WEAPON(anti-air) | - |
| `structure.nec.relay` | AURA(class=RELAY;fx=stat;stat=weapon_damage;delta=+10%;r=6c;targets=friendly_combat_infantry,friendly_land_combat_vehicle;requires=powered;power_grace=0s;same_source=none_stack) | ? | X:POWER(-20) | Treaty Coordination raises delta to +15%; Distributed Control raises r to 8c and grace to 10s. |
| `structure.napc.atlas_kinetic_array` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.napc.bulwark_cannon` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.nec.aurora_microwave_array` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.nec.lance_rail_emplacement` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.olm.helios_reflector` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.olm.sunwall_projector` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.def.perun_missile_complex` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.def.citadel_mortar` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.pd.tempest_swarm_hub` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.pd.sea_spear_battery` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.han.dragonfall_field_foundry` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.han.dragon_tooth_launcher` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.ae.horizon_mass_driver` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.ae.forge_cannon` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `structure.sap.trident_interception_array` | - | - | X:POWER(strategic launcher) | EMP shutdown or destruction during warning cancels the attack (no refund); never uses the SAP defense reserve; excluded from Emergency Fortification. |
| `structure.sap.bastion_missile_tower` | - | - | X:WEAPON(advanced defense) | Tag `defense`: subject to SAP power reserve, Buried Command Lines, Layered Fieldworks provider, Emergency Fortification. |
| `neutral.civilian_garrison` | GARRISON(cap_squads=4;cls=infantry;pax_fire=1;targetable_occupants=0;eject_on_destroy=1;eject_hp_loss=35%*;claim=first_occupant_team) | (neutral container) | X:MAP(marked neutral building; hp 800*) | Marked civilian garrison. El-Andalus: garrisoned combat infantry weapon_damage +20% (typed modifier, condition GARRISONED). |
| `neutral.tech_structure` | CAPTURE(target;by=engineer;owner_change=1;time=10s*) | capture | X:MAP(captureable substations) | Only Engineers capture; enemy production and superweapon structures are never capturable. |

## 3. Research (40)

| Research id | T | Effect primitives and parameters | Effect ops (data 7.5) | Note |
|---|---|---|---|---|
| `research.napc.adaptive_plating` | 2 | STAT_MOD(stat=dmg_taken;delta=-10%;types=explosive;sel=land_combat_vehicles;not=beam,rail,bullet) | resist_mod | - |
| `research.napc.joint_tactical_links` | 3 | STAT_MOD(stat=weapon_range;delta=+10%;sel=sentinel_aa,aegis_frigate;cond=IN_AURA(JTL);aura_providers=rifle_squad,javelin_team+replacements;aura_r=6c) | stat_mod | - |
| `research.napc.dispersed_runways` | 2 | PARAM_MOD(struct=airfield;pads=+2;service_rate_per_pad=unchanged) | param_mod | - |
| `research.napc.sealed_compartments` | 2 | STAT_MOD(stat=dmg_taken;delta=-15%;types=explosive;sel=beaver,narwhal;cond=ON_WATER) | resist_mod | - |
| `research.napc.section_logistics` | 2 | GRANT_ABILITY(to=structure.shared.barracks;AURA(class=BARRACKS_REGEN;fx=heal;rate=1%/s;r=6c*;targets=combat_infantry;requires=powered;recipient_cond=OUT_OF_COMBAT(6s))) | grant_ability | - |
| `research.nec.sensor_fusion` | 2 | STAT_MOD(stat=detect_radius;delta=+2c(add_cells);sel=surveyor_apc,rapier_aa,horizon_escort+replacements) | stat_mod | - |
| `research.nec.distributed_control` | 3 | PARAM_MOD(ability=AURA(class=RELAY);r=6c->8c;power_grace=10s;grace_not_after_destruction=1) | param_mod | - |
| `research.nec.dispersed_links` | 2 | GRANT_ABILITY(to=fen_recon_carrier;AURA(class=RELAY;fx=stat;stat=weapon_damage;delta=+10%;r=4c;requires=deployed;power=onboard;no_stack_with_relay=1;no_radius_upgrades=1)) | grant_ability | - |
| `research.nec.shared_fire_solutions` | 3 | STAT_MOD(stat=reload_interval;delta=-10%;sel=marte,charlemagne;cond=IN_AURA(RELAY,powered)) | stat_mod | - |
| `research.nec.tunnel_workshops` | 2 | PARAM_MOD(ability=REPAIR_ACTOR;rate=+25%;sel=engineer,alpine_pioneer;targets=defense_structure;cost_per_health=unchanged) | param_mod | - |
| `research.olm.thermal_shrouds` | 2 | STAT_MOD(stat=sight;delta=+10%;sel=light_land_vehicles); STAT_MOD(stat=dmg_taken;delta=-10%;types=thermal_beam;sel=light_land_vehicles) | resist_mod | - |
| `research.olm.optical_mesh` | 3 | GRANT_ABILITY(to=caravan_apc+replacements;CLOAK(arm=6s;quiet=stationary,no_attack,no_damage;reveal=move,fire)) | grant_ability | Dune Rover keeps its own (superset) CLOAK; both slots OR together. |
| `research.olm.thermal_reservoirs` | 3 | STAT_MOD(stat=reload_interval;delta=-10%;sel=ifrit,dawn;not=helios) | stat_mod | - |
| `research.olm.distributed_fuel_caches` | 2 | STAT_MOD(stat=move_speed;delta=+10%;sel=dune_rover,scorpion;cond=OUT_OF_COMBAT(6s);ends_on=fire,damage) | stat_mod | - |
| `research.olm.harbor_militia` | 2 | STAT_MOD(stat=weapon_damage;delta=+10%;sel=gate_guard;cond=IN_AURA(FACTORY_DOCK);aura_providers=factory,dock;aura_r=6c;no_stack_between_buildings=1) | stat_mod | - |
| `research.def.standardized_parts` | 2 | PARAM_MOD(ability=REPAIR_ACTOR;cost_per_health=-15%;sel=engineer;targets=land_vehicle;applies_anywhere=1) | param_mod | - |
| `research.def.coordinated_barrages` | 3 | STAT_MOD(stat=reload_interval;delta=-10%;sel=anvil,colossus+replacements;cond=STATIONARY(4s);reset_on=move) | stat_mod | - |
| `research.def.layered_protection` | 3 | PARAM_MOD(ability=ACTIVE_PROTECTION;cooldown=12s->9s;sel=ural); GRANT_ABILITY(to=bear;ACTIVE_PROTECTION(intercept=missile;cooldown=9s*;charges=1)) | param_mod, grant_ability | - |
| `research.def.mobile_dispatch` | 2 | STAT_MOD(stat=sight;delta=+15%;sel=steppe_recon_carrier,saker); PARAM_MOD(ability=MODE_SWITCH;pack=0s;sel=saker;after=firing) | stat_mod, param_mod | - |
| `research.def.buried_command_lines` | 2 | PARAM_MOD(status=EMP_POWER_OFF;duration=-25%;sel=radar,defense_structures;initial_shutdown_not_prevented=1) | param_mod | - |
| `research.pd.expeditionary_maintenance` | 2 | PARAM_MOD(ability=REPAIR_ACTOR;rate=+25%;sel=reef_technician;cost_per_health=unchanged) | param_mod | - |
| `research.pd.integrated_flight_decks` | 3 | PARAM_MOD(struct=airfield;rearm_time=-15%); PARAM_MOD(ability=CARRIER;replace_time=-15%;sel=all_carriers) | param_mod | - |
| `research.pd.forward_fire_control` | 3 | STAT_MOD(stat=reload_interval;delta=-10%;sel=outrider;cond=TARGET_IN_AURA(SPOT_WEDGE);aura_r=6c) | stat_mod | - |
| `research.pd.distributed_beachheads` | 2 | STAT_MOD(stat=move_speed;delta=+15%;sel=reef_technician); PARAM_MOD(ability=REPAIR_ACTOR;works_while_carried=1;one_per_transport=1) | stat_mod, param_mod | - |
| `research.pd.predictive_maintenance` | 3 | PARAM_MOD(ability=MODE_SWITCH;switch=3s->2s;sel=shinano); PARAM_MOD(ability=CARRIER;replace_time=-20%;sel=shogun) | param_mod | - |
| `research.han.resilient_mesh` | 2 | PARAM_MOD(status=EMP_WEAPONS_OFF;duration=-25%;sel=unmanned_combat_units;normal_emp_damage=1) | param_mod | - |
| `research.han.distributed_cognition` | 3 | PARAM_MOD(ability=AURA(class=COMMAND);r=5c->7c;no_stack=1) | param_mod | - |
| `research.han.guard_integration` | 3 | PARAM_MOD(ability=AURA(class=COMMAND);recipients=+imperial_guard_tank) | param_mod | - |
| `research.han.hidden_relays` | 2 | GRANT_ABILITY(to=link_operator;CLOAK(arm=6s;quiet=stationary,no_attack,no_damage;reveal=move,fire,damage;aura_stays_active=1)) | grant_ability | - |
| `research.han.modular_servicing` | 3 | PARAM_MOD(ability=REPAIR_ACTOR;rate=+50%;sel=lotus_drone_tender;cost_per_health=unchanged) | param_mod | - |
| `research.ae.recovery_winches` | 2 | PARAM_MOD(ability=SALVAGE;time=8s->5s;payout=unchanged) | param_mod | - |
| `research.ae.circular_armor` | 3 | STAT_MOD(stat=health_max;delta=+10%;sel=land_combat_vehicles;salvage_basis_unchanged=1) | stat_mod | - |
| `research.ae.municipal_reserves` | 2 | STAT_MOD(stat=health_max;delta=+10%;sel=civic_rifle_team;cond=IN_AURA(BARRACKS_REFINERY);aura_providers=barracks,refinery;aura_r=6c) | stat_mod | - |
| `research.ae.watershed_logistics` | 2 | PARAM_MOD(ability=TRANSPORT;cargo_regen=1%/s;after=OUT_OF_COMBAT(6s);sel=okapi;carrier_not_repaired=1) | param_mod | - |
| `research.ae.precision_machining` | 3 | STAT_MOD(stat=reload_interval;delta=-10%;sel=rhino,protea;both_protea_modes=1) | stat_mod | - |
| `research.sap.layered_fieldworks` | 2 | STAT_MOD(stat=dmg_taken;delta=-10%;types=explosive;sel=combat_infantry;cond=IN_AURA(DEFENSE);aura_providers=friendly_defense_structures;aura_r=4c;overlap_no_stack=1) | resist_mod | - |
| `research.sap.reserve_capacitors` | 3 | PARAM_MOD(player=POWER_RESERVE;reserve=20s->35s;recharge_after=60s_continuous_adequate_power) | param_mod | - |
| `research.sap.integrated_protection` | 3 | PARAM_MOD(ability=ACTIVE_PROTECTION;cooldown=15s->10s;sel=arjun); GRANT_ABILITY(to=gaj;ACTIVE_PROTECTION(intercept=missile;cooldown=10s;charges=1)) | param_mod, grant_ability | - |
| `research.sap.rapid_ferry_drills` | 2 | PARAM_MOD(ability=TRANSPORT;load_time=-40%;unload_time=-40%;sel=naga;passenger_attack_speed_unchanged=1) | param_mod | - |
| `research.sap.observer_network` | 3 | STAT_MOD(stat=reload_interval;delta=-10%;sel=shaheen;cond=TARGET_IN_AURA(SPOT_WATCHPOST);aura_r=6c) | stat_mod | - |

## 4. Support powers (48)

| Power id | T | Cost / cooldown | Effect primitives and parameters | EK (economy 5.18) | Note |
|---|---|---|---|---|---|
| `power.napc.uav_sweep` | 2 | 500 cr / 90 s | REVEAL_ZONE(shape=circle;r=7c;dur=12s;detect=1;body=UAV;shootable=1;target=any_location) | RECON_SUMMON | - |
| `power.napc.field_repair_drop` | 3 | 900 cr / 180 s | REPAIR_ZONE(r=5c;rate=2%/s;dur=10s;targets=friendly_land_vehicle;no_stack=1;not_self=1;delivery=shootable_cargo_aircraft(approach=5s*);fizzles_if_shot=1) | REPAIR | - |
| `power.napc.combined_arms_window` | 2 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=15s;stat=weapon_damage;delta=+10%;targets=friendly_infantry,land_vehicle,aircraft;not=ship,structure) | BUFF | - |
| `power.napc.rapid_turnaround` | 2 | 700 cr / 150 s | STATUS_AREA(area=single_target;target=powered_airfield;dur=20s;stat=rearm_rate;delta=+50%;production_unchanged=1) | STRUCT_BUFF | - |
| `power.napc.floating_workshop` | 2 | 800 cr / 180 s | REPAIR_ZONE(r=5c;rate=1.5%/s;dur=20s;targets=friendly_vehicle,ship;placement=clear_land_or_water;body=pontoon(visible;destructible*)) | REPAIR | - |
| `power.napc.coordinated_advance` | 2 | 600 cr / 150 s | STATUS_AREA(r=6c;dur=12s;stat=move_speed;delta=+25%;targets=friendly_infantry;grant=suppression_immunity;remove_existing_suppression=1) | BUFF | - |
| `power.nec.survey_drone` | 2 | 450 cr / 90 s | REVEAL_ZONE(shape=circle;r=6c;dur=15s;detect=1;body=drone;shootable=1;target=any_location) | RECON_SUMMON | - |
| `power.nec.counterbattery_mission` | 3 | 1100 cr / 180 s | STRIKE_BARRAGE(warn=5s;shells=6;span=4s;r=4c;dmg=conventional_precision;exec=combat) | BOMBARD | - |
| `power.nec.treaty_coordination` | 2 | 800 cr / 180 s | STATUS_PLAYER(dur=20s;param=RELAY.damage;value=10%->15%;only_inside_fields=1) | WINDOW | - |
| `power.nec.silent_watch` | 2 | 600 cr / 150 s | STATUS_AREA(r=6c;dur=15s;grant=CAMO;targets=friendly_stationary_ground;break_on=move,fire,detect) | BUFF | - |
| `power.nec.armored_overwatch` | 2 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=15s;stat=weapon_range;delta=+10%;targets=friendly_stationary_tanks;remove_on=move) | BUFF | - |
| `power.nec.emergency_earthworks` | 2 | 700 cr / 180 s | STATUS_AREA(r=5c;dur=15s;stat=dmg_taken;delta=-20%;types=explosive;targets=friendly_infantry,defense_structure;not=vehicle) | BUFF | - |
| `power.olm.dust_screen` | 2 | 400 cr / 90 s | SMOKE_ZONE(shape=circle;r=6c;dur=12s;dmg_taken=-30%;scope=direct_fire;targets=all_ground_units_two_sided;unaffected=artillery,area_blast) | SMOKE | - |
| `power.olm.mobile_workshop` | 3 | 900 cr / 180 s | REPAIR_ZONE(r=5c;rate=2%/s;dur=15s;targets=friendly_vehicle;placement=clear_ground;body=repair_drone_station(visible;destructible);no_stack=1) | REPAIR | - |
| `power.olm.open_corridor` | 2 | 650 cr / 150 s | STATUS_AREA(r=6c;dur=12s;stat=move_speed;delta=+25%;targets=friendly_land_vehicle;membership=snapshot_at_activation) | BUFF | - |
| `power.olm.capacitor_discharge` | 2 | 800 cr / 180 s | STATUS_AREA(r=6c;dur=10s;stat=weapon_damage;delta=+20%;targets=thermal_beam_units,sunwall;then=WEAPONS_OFF(4s;cooling)) | BUFF+penalty | - |
| `power.olm.false_convoy` | 2 | 500 cr / 120 s | DECOY_GROUP(count=4;decoy_of=light_land_vehicle;dur=25s;hp=1;no_damage=1;no_collision=1;no_capture=1;placement=scouted_clear;identified_by=detectors) | DECOY | - |
| `power.olm.straits_crossfire` | 2 | 800 cr / 180 s | STATUS_AREA(r=6c;dur=15s;stat=weapon_range;delta=+10%;stat2=sight;delta2=+20%;targets=friendly_infantry,ship) | BUFF | - |
| `power.def.mobilization_order` | 2 | 700 cr / 180 s | STATUS_PLAYER(dur=20s;param=PRODUCTION_RATE;value=+25%;queues=barracks,factory;cost_unchanged=1) | WINDOW | A progress-rate effect: not a build-time modifier, so the 60% build-time floor does not apply. |
| `power.def.tremor_barrage` | 3 | 1300 cr / 210 s | STRIKE_BARRAGE(warn=6s;waves=4;span=8s;r=5c;dmg=conventional;exec=combat) | BOMBARD | - |
| `power.def.redundant_orders` | 2 | 650 cr / 180 s | STATUS_AREA(r=6c;dur=10s;grant=EMP_WEAPONS_IMMUNE;targets=friendly_vehicle;not=structure;remove_existing_emp_weapons_off=1*) | BUFF | - |
| `power.def.steel_advance` | 2 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=12s;stat=dmg_taken;delta=-20%;stat2=move_speed;delta2=-20%;targets=land_vehicle) | BUFF | - |
| `power.def.transit_priority` | 2 | 600 cr / 150 s | STATUS_AREA(r=7c;dur=15s;stat=move_speed;delta=+35%;targets=friendly_collector,ground_transport;harvest_unload_rate_unchanged=1) | BUFF | - |
| `power.def.false_front` | 2 | 500 cr / 150 s | DECOY_GROUP(decoys=radar:1,tank:3;dur=30s;zone_r=6c;placement=scouted;harmless=1;non_blocking=1;identified_by=detectors) | DECOY | - |
| `power.pd.maritime_patrol` | 2 | 500 cr / 90 s | REVEAL_ZONE(shape=corridor;len=20c;wid=6c;dur=12s;detect=1;terrain=land_and_water;body=patrol_aircraft;shootable=1;target=any_location) | RECON_SUMMON | - |
| `power.pd.expeditionary_workshop` | 3 | 900 cr / 180 s | REPAIR_ZONE(r=5c;rate=1.5%/s;dur=20s;targets=friendly_vehicle,ship;placement=clear_land_or_water;delivery=shootable_aircraft(approach=5s*);fizzles_if_shot=1) | REPAIR | - |
| `power.pd.joint_landing` | 2 | 700 cr / 180 s | STATUS_PLAYER(window=15s;on=unload_event;apply=DISEMBARK_BUFF(stat=damage_taken;delta=-20%;dur=6s;refresh=none);targets=friendly_ground_units) | WINDOW | - |
| `power.pd.long_watch` | 2 | 600 cr / 150 s | REVEAL_ZONE(shape=circle;r=7c;dur=18s;detect=0;body=none(high_altitude);target=any_location*) | REVEAL_ZONE | - |
| `power.pd.feint_landing` | 2 | 500 cr / 120 s | DECOY_GROUP(count=3;decoy_of=transport;dur=25s;no_cargo=1;placement=scouted_land_or_water;identified_by=detectors) | DECOY | - |
| `power.pd.precision_window` | 2 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=10s;stat=weapon_damage;delta=+20%;targets=friendly_aircraft,ship;no_sight_or_survivability_bonus=1) | BUFF | - |
| `power.han.wideband_scan` | 2 | 400 cr / 90 s | REVEAL_ZONE(shape=circle;r=7c;dur=6s;detect=1;warn=2s(visible_to_enemies);target=any_location*) | REVEAL_ZONE | - |
| `power.han.software_surge` | 3 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=12s;stat=reload_interval;delta=-25%;targets=friendly_unmanned_combat;not=superweapon_summon;then=WEAPONS_OFF(3s)) | BUFF+penalty | - |
| `power.han.reserve_bandwidth` | 2 | 650 cr / 150 s | STATUS_PLAYER(dur=20s;param=COMMAND.radius;value=+3c;damage_stays=+10%;fields_do_not_stack=1) | WINDOW | - |
| `power.han.central_priority` | 2 | 800 cr / 180 s | STATUS_PLAYER(dur=15s;param=COMMAND.damage;value=+10%->+20%;radius_unchanged=1) | WINDOW | - |
| `power.han.broken_contact` | 2 | 650 cr / 150 s | STATUS_AREA(r=6c;dur=10s;stat=move_speed;delta=+20%;targets=friendly_ground_combat); SMOKE_ZONE(at=initial_position_of_each_unit_snapshot;dur=6s;rule=dust_screen) | BUFF+SMOKE | - |
| `power.han.repair_swarm` | 2 | 700 cr / 180 s | REPAIR_ZONE(r=5c;rate=2%/s;dur=10s;targets=friendly_unmanned_land,structure;no_repair_charge=1) | REPAIR | - |
| `power.ae.survey_network` | 2 | 400 cr / 90 s | REVEAL_ZONE(shape=circle;r=7c;dur=12s;detect=0;highlight=salvageable_wrecks;target=any_location*) | REVEAL_ZONE | - |
| `power.ae.field_refurbishment` | 3 | 1000 cr / 180 s | REPAIR_ZONE(r=6c;rate=3%/s;dur=10s;targets=friendly_land_vehicle;lock_weapons_while_repaired=1;stop_repair_on_move=per_unit) | REPAIR (snapshot) | - |
| `power.ae.recovery_priority` | 2 | 600 cr / 150 s | STATUS_PLAYER(dur=20s;sel=engineer,reclaimer(+river_warden);stat=move_speed;delta=+25%;param=SALVAGE.time;value=3s;payout_unchanged=1) | WINDOW | - |
| `power.ae.civil_defense_net` | 2 | 600 cr / 150 s | STATUS_AREA(r=6c;dur=15s;stat=sight;delta=+25%;grant=suppression_immunity;targets=friendly_infantry) | BUFF | - |
| `power.ae.concealed_crossing` | 2 | 600 cr / 150 s | SMOKE_ZONE(shape=corridor;len=16c;wid=4c;dur=12s;terrain=land_or_water;rule=dust_screen;protects_either_side=1) | SMOKE | - |
| `power.ae.counterbattery_solution` | 2 | 900 cr / 180 s | MARK_TARGETS(r=9c;lookback=8s;reveal=1;mark=12s;effect=friendly_ground_weapons_dmg+15%_vs_marked) | MARK | - |
| `power.sap.recon_balloon` | 2 | 450 cr / 90 s | REVEAL_ZONE(shape=circle;r=6c;dur=20s;detect=1;body=tethered_observation_drone;shootable=1;placement=clear_location) | RECON_SUMMON | - |
| `power.sap.emergency_fortification` | 3 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=15s;stat=dmg_taken;delta=-25%;targets=friendly_defense_structure,production_structure;not=superweapon_structure;emp_not_prevented=1) | BUFF | - |
| `power.sap.protected_advance` | 2 | 750 cr / 180 s | STATUS_AREA(r=6c;dur=12s;stat=dmg_taken;delta=-15%;targets=friendly_infantry,land_vehicle;no_move_bonus=1) | BUFF | - |
| `power.sap.assault_coordination` | 2 | 900 cr / 180 s | STATUS_AREA(r=6c;dur=12s;stat=reload_interval;delta=-15%;stat2=sight;delta2=+15%;targets=friendly_tanks) | BUFF | - |
| `power.sap.mobile_reserve` | 2 | 650 cr / 150 s | STATUS_AREA(r=7c;dur=15s;stat=move_speed;delta=+30%;grant=UNLOAD_WHILE_MOVING(speed=50%);targets=friendly_ground_transport) | BUFF | - |
| `power.sap.counterlaunch_plot` | 2 | 800 cr / 180 s | MARK_TARGETS(r=8c;lookback=8s;record=positions_at_fire_time); STRIKE_BARRAGE(warn=5s;at=marked_positions_not_current;dmg=conventional;exec=combat) | BOMBARD+MARK | - |

## 5. Superweapons (8)

| Superweapon id | Recharge / warning | Effect primitives and parameters | SwAction (data 4.1) | Note |
|---|---|---|---|---|
| `superweapon.napc.atlas_kinetic_array` | 480 s / 10 s | IMPACT_PACKETS(rods=3;centers=target,+-3c_lateral;r=2c_each;dmg=kinetic;warn=10s;recharge=480s;packets=3) | KINETIC_VOLLEY | Owner: power/combat. Ability domain: Trident hand-off only. |
| `superweapon.nec.aurora_microwave_array` | 420 s / 8 s | EMP_PULSE(r=8c;warn=8s;enemies_only=1;vehicles+aircraft=WEAPONS_OFF(8s);powered_structures=SHUTDOWN(18s);vehicles_still_move=1;aircraft_do_not_crash=1;infantry_unaffected=1;light_direct_damage=1;bypasses=trident) | EMP_BURST | - |
| `superweapon.olm.helios_reflector` | 480 s / 10 s | IMPACT_PACKETS(shape=line;len=16c;wid=3c;sweep=12s;dmg=thermal_beam;targets=ground,ship,structure;no_tracking=1;bypasses=trident,smoke) | BEAM_SWEEP | Owner: power/combat. |
| `superweapon.def.perun_missile_complex` | 480 s / 10 s | IMPACT_PACKETS(core_r=3c;ring_r=7c;packets=2(core,ring);dmg=conventional;warn=10s;no_contamination=1) | BUNKER_BUSTER | Owner: power/combat. |
| `superweapon.pd.tempest_swarm_hub` | 480 s / 10 s | SWARM_SUMMON(drones=24;area_r=6c;attack_window=20s;targets=ground,surface;aa_targetable=1;approach_visible=1;each_hit=packet;flags=no_capture,no_scout,no_salvage,no_cost_mods,no_unit_cap;enemies_only=1) | DRONE_SWARM | - |
| `superweapon.han.dragonfall_field_foundry` | 480 s / 10 s | ENGINE_DROP(capsules=3;area_r=5c;assemble=5s;attackable_during_assembly=1;engine_life=60s;flags=no_capture,no_repair,no_harvest,no_command_field,no_salvage,no_cost_mods;role=slow_anti_structure;each_shot=packet) | ENGINE_DROP | - |
| `superweapon.ae.horizon_mass_driver` | 480 s / 10 s | IMPACT_PACKETS(circles=3;r=3c;line=10c;span=9s;hits=ground,ship,structure); DEBRIS_ZONE(land_vehicle_speed=-35%;dur=20s;blocks_new_construction=1;never_blocks_movement=1;land_only=1) | RAIL_STRIKE | Impact owner: power/combat; debris owner: ability domain. |
| `superweapon.sap.trident_interception_array` | 360 s / 6 s | INTERCEPT_ZONE(r=6c;dur=25s;charges=24;ordinary_missile_or_shell_crossing=destroy(1 charge);strategic_packet=-50% for 8 charges (never cancel; <8 charges cannot reduce);bypass=beam,bullet,emp,units_entering,fired_from_inside;fixed;visible;warn=6s;recharge=360s) | INTERCEPT_ZONE | - |

## 6. CUSTOM and flavor-only rows

| Unit id | Resolution |
|---|---|
| `unit.pd.ranger_marine` | CUSTOM(flavor): 'optimized after transport deployment' has no number; recommended DISEMBARK_BUFF dmg +10% 4s (balance option, off by default). |
| `unit.sap.shield_rifle_squad` | CUSTOM(flavor): 'good staying power behind cover' has no number; realized as health stat only. |

## 7. Verification summary

* structure rows: 29 (+2 neutral objects), asserted equal to the bible structure id set.
* unit rows: 156; research rows: 40; power rows: 48; superweapon rows: 8 (asserted equal to the bible counts and id sets).
* units with at least one slot primitive: 89; without: 67.
* detectors: 42 units; transports: 18 units; carriers: 3.
* maximum distinct slot primitives on one unit: 4 (the fixed slot count MAX_SLOTS=6 leaves headroom for GRANT_ABILITY).
