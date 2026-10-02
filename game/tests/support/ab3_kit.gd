class_name Ab3Kit
extends RefCounted
## The AB3 composite scenario (zones, summons, powers, unit abilities on the REAL data) shared by the double-run tests and
## the cross-platform scenario (tests/scenarios/xplat_ab3.gd). Six players, two teams, real movement, combat and economy
## on a small lake map:
##   T1: P0 NAPC Mexico, P2 SAP, P4 AE Kongo     T2: P1 Han China, P3 PD Indonesia, P5 DEF Russia
## The script fires powers and superweapons through SimPowerFx and unit abilities through CMD_USE_ABILITY, then lets the
## armies fight so that Trident charges, smoke, cover, repair stations, marks, swarms, engines and the Lagos drone all
## interact with combat.

const A := preload("res://tests/support/ab2_kit.gd")
const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const TICKS: int = 1500
const CELL: int = 1024


static func c(cell: int) -> int:
	return cell * CELL + CELL / 2


static func build() -> SimWorld:
	var rows: PackedStringArray = A.MV.grid(72)
	A.MV.rect(rows, 46, 30, 62, 50, "~")
	var w: SimWorld = A.world({
		"rosters": ["roster.napc.mexico", "roster.han.china", "roster.sap.vanilla", "roster.pd.indonesia", "roster.ae.kongo", "roster.def.russia"],
		"teams": [1, 2, 1, 2, 1, 2], "rows": rows, "seed": 31, "rules": {"fog": true}, "invariants_every": 25,
	})
	# T1 west, T2 east, facing each other across x = 36
	A.structure(w, "structure.shared.generator", 0, 8, 8)
	for i: int in 4:
		A.spawn(w, "unit.napc.vanguard_rifle_squad", 0, 14 + i, 20)
	A.spawn(w, "unit.napc.guardian_tank", 0, 16, 24)
	A.spawn(w, "unit.napc.guardian_tank", 0, 18, 24)
	A.spawn(w, "unit.napc.paladin_howitzer", 0, 12, 26)
	A.spawn(w, "unit.sap.combat_pioneer", 2, 20, 30)
	A.spawn(w, "unit.sap.naga_amphibious_carrier", 2, 50, 34)
	A.spawn(w, "unit.sap.shield_rifle_squad", 2, 22, 30)
	A.spawn(w, "unit.ae.lagos_drone_guard", 4, 12, 34)
	A.spawn(w, "unit.ae.civic_rifle_team", 4, 14, 36)
	A.spawn(w, "unit.ae.civic_rifle_team", 4, 15, 36)
	A.spawn(w, "unit.ae.buffalo_tank", 4, 18, 38)
	A.spawn(w, "unit.han.link_operator", 1, 56, 12)
	A.spawn(w, "unit.han.nest_rocket_drone", 1, 58, 12)
	A.spawn(w, "unit.han.ox_tank", 1, 56, 20)
	A.spawn(w, "unit.han.ox_tank", 1, 58, 20)
	A.spawn(w, "unit.pd.island_raider", 3, 56, 26)
	A.spawn(w, "unit.pd.island_raider", 3, 57, 26)
	A.spawn(w, "unit.pd.tide_tank", 3, 58, 28)
	A.spawn(w, "unit.def.echo_team", 5, 56, 40)
	A.spawn(w, "unit.def.hammer_tank", 5, 58, 42)
	A.spawn(w, "unit.def.hammer_tank", 5, 60, 42)
	A.structure(w, "structure.shared.generator", 1, 64, 8)
	return w


static func _units(w: SimWorld, pid: int) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for e: SimEntity in w.units_of(pid):
		if (e.flags & SimFlags.F_GONE) == 0 and e.summon == null:
			out.append(e)
	return out


static func _use(w: SimWorld, e: SimEntity, kind: int, x: int = -1, y: int = -1) -> void:
	if e == null or e.abil == null:
		return
	var s: int = e.abil.slot_of_kind(kind)
	if s >= 0:
		w.submit_raw(e.owner, SimCmd.use_ability(PackedInt32Array([e.id]), s, 0, 0, x, y))


static func _power(w: SimWorld, id: String, pid: int, x: int, y: int, angle: int = 0, aux: int = 4242) -> void:
	SimPowerFx.apply(w, w.data.power_idx(id), pid, c(x), c(y), angle, aux)


static func _sw(w: SimWorld, id: String, pid: int, x: int, y: int, hx: int, hy: int, aux: int = 77) -> void:
	for i: int in w.data.superweapons.size():
		if w.data.superweapons[i].id == id:
			SimPowerFx.apply_superweapon(w, i, pid, c(x), c(y), 300, c(hx), c(hy), aux)


static func script(w: SimWorld, s: int) -> void:
	match s:
		0:
			for pid: int in [0, 2, 4]:  # everybody marches east, the other team west
				for e: SimEntity in _units(w, pid):
					if e.abil == null or e.abil.slot_of_kind(K.AK_SMOKE_LAUNCHER) < 0:
						w.submit_raw(pid, SimCmd.attack_move(PackedInt32Array([e.id]), c(50), c(30)))
			for pid2: int in [1, 3, 5]:
				for e2: SimEntity in _units(w, pid2):
					w.submit_raw(pid2, SimCmd.attack_move(PackedInt32Array([e2.id]), c(22), c(28)))
		10:
			for e3: SimEntity in _units(w, 2):
				_use(w, e3, K.AK_PORTABLE_COVER)
			for e4: SimEntity in _units(w, 4):
				_use(w, e4, K.AK_SENSOR_PUCK, c(16), c(36))
		20:
			_power(w, "power.napc.combined_arms_window", 0, 16, 22)
			_sw(w, "superweapon.sap.trident_interception_array", 2, 24, 28, 20, 20)
		40:
			_power(w, "power.napc.field_repair_drop", 0, 17, 24)
			for e5: SimEntity in _units(w, 5):
				_use(w, e5, K.AK_DECOY_SPAWN, e5.x + 3 * CELL, e5.y)
		60:
			_power(w, "power.napc.uav_sweep", 0, 40, 30, 1024)
			for e6: SimEntity in _units(w, 2):
				_use(w, e6, K.AK_SMOKE_LAUNCHER, c(48), c(34))
		90:
			_power(w, "power.han.broken_contact", 1, 57, 20)
			_power(w, "power.han.central_priority", 1, 0, 0)
		120:
			_sw(w, "superweapon.pd.tempest_swarm_hub", 3, 20, 26, 60, 26)
			_power(w, "power.pd.long_watch", 3, 30, 30)
		150:
			_power(w, "power.def.false_front", 5, 55, 40, 0, 99)
			_power(w, "power.ae.field_refurbishment", 4, 17, 38)
		200:
			_sw(w, "superweapon.han.dragonfall_field_foundry", 1, 20, 28, 60, 12, 1234)
			_power(w, "power.pd.joint_landing", 3, 0, 0)
		260:
			_power(w, "power.sap.counterlaunch_plot", 2, 56, 24)
			_power(w, "power.ae.counterbattery_solution", 4, 56, 24)
		300:
			_sw(w, "superweapon.ae.horizon_mass_driver", 4, 56, 24, 12, 12)
			_power(w, "power.olm.dust_screen", 4, 36, 30)
		400:
			_power(w, "power.def.tremor_barrage", 5, 16, 24, 0, 5)
			_power(w, "power.pd.expeditionary_workshop", 3, 57, 27)
		520:
			_sw(w, "superweapon.nec.aurora_microwave_array", 0, 56, 20, 8, 8)
			_power(w, "power.napc.floating_workshop", 0, 52, 40)
		700:
			_power(w, "power.ae.recovery_priority", 4, 0, 0)
			_power(w, "power.def.mobilization_order", 5, 0, 0)
			for e7: SimEntity in _units(w, 2):
				_use(w, e7, K.AK_PORTABLE_COVER)
		800:
			for e8: SimEntity in _units(w, 4):
				if e8.abil != null and e8.abil.slot_of_kind(K.AK_SUMMON_ORBIT) >= 0:
					var drone: SimEntity = w.get_entity(e8.abil.slots[e8.abil.slot_of_kind(K.AK_SUMMON_ORBIT) * K.SLOT_STRIDE + K.SL_AUX0])
					if drone != null:
						w.kill(drone, SimWorld.Cause.SCRIPT)  # shot down: respawn after 1800 ticks
		900:
			_sw(w, "superweapon.sap.trident_interception_array", 5, 40, 30, 60, 8)
			_power(w, "power.nec.treaty_coordination", 1, 0, 0)
		1000:
			_sw(w, "superweapon.napc.atlas_kinetic_array", 0, 58, 20, 10, 10)
			_sw(w, "superweapon.olm.helios_reflector", 1, 20, 28, 60, 10)


static func digest(w: SimWorld) -> PackedInt64Array:
	return PackedInt64Array([w.checksum(), w.events.digest(), Checksum.fnv_string(w.dump_state()), w.abilities.timer_digest])


## Chain of checksums (every checkpoint) of a full run.
static func run_chain(peek: bool = false) -> PackedInt64Array:
	var w: SimWorld = build()
	for s: int in TICKS:
		script(w, s)
		w.step()
		if peek and s % 11 == 0:
			w.checksum()
			w.abilities.debug_validate(w)
			w.zones.debug_validate(w)
	var out: PackedInt64Array = PackedInt64Array()
	out.append_array(w.checksum_log)
	out.append_array(digest(w))
	return out


## Coverage numbers of a finished run: how much of each feature actually happened.
static func coverage(w: SimWorld) -> Dictionary:
	var counts: Dictionary = {}
	var d: PackedInt32Array = w.events.data
	for i: int in d.size() / SimEvent.STRIDE:
		var t: int = d[i * SimEvent.STRIDE + SimEvent.I_TYPE]
		counts[t] = int(counts.get(t, 0)) + 1
	return counts
