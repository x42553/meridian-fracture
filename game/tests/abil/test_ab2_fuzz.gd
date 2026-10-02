extends RefCounted
## AB2 command fuzz: seeded random ability / cargo commands (valid, half valid and garbage) against a crowded world with
## every container / mode / aura unit type, SimInvariants every 25 ticks (a violation or engine error fails the test),
## a double run for determinism.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")

const UNITS_P0: Array = [
	"unit.napc.paladin_howitzer", "unit.napc.pathfinder_apc", "unit.napc.rifle_squad", "unit.napc.rifle_squad", "unit.napc.rifle_squad",
	"unit.napc.rifle_squad", "unit.napc.guardian_tank", "unit.napc.combat_medic", "unit.shared.landing_transport", "unit.shared.engineer",
	"unit.napc.beaver_amphibious_apc",
]
const UNITS_P1: Array = [
	"unit.nec.charlemagne_siege_tank", "unit.nec.fen_recon_carrier", "unit.nec.leopard_tank", "unit.nec.leopard_tank", "unit.nec.aster_ew_aircraft",
	"unit.nec.surveyor_apc", "unit.shared.landing_transport", "unit.pd.shinano_adaptive_tank", "unit.han.link_operator", "unit.han.nest_rocket_drone",
]

var _s: int = 1


func _rnd(n: int) -> int:
	_s = (_s * 1103515245 + 12345) & 0x7FFFFFFF
	return (_s >> 8) % n


func _build(seed_value: int) -> SimWorld:
	_s = seed_value
	var rows: PackedStringArray = A.MV.grid(64)
	A.MV.rect(rows, 40, 10, 58, 40, "~")
	var w: SimWorld = A.world({"rosters": ["roster.napc.canada", "roster.nec.nordics"], "rows": rows, "seed": seed_value, "invariants_every": 25})
	for i: int in UNITS_P0.size():
		A.spawn(w, UNITS_P0[i], 0, 8 + (i % 5) * 3, 8 + (i / 5) * 3 + (30 if UNITS_P0[i].contains("landing") else 0))
	for j: int in UNITS_P1.size():
		A.spawn(w, UNITS_P1[j], 1, 14 + (j % 5) * 3, 40 + (j / 5) * 3)
	A.structure(w, "structure.shared.generator", 0, 6, 6)
	A.structure(w, "structure.shared.factory", 0, 22, 12)
	A.structure(w, "structure.nec.relay", 1, 50, 50)
	A.structure(w, "structure.shared.generator", 1, 52, 52)
	A.neutral(w, "neutral.civilian_garrison", 30, 20)
	A.neutral(w, "neutral.field_hospital", 34, 24)
	return w


func _pick(w: SimWorld, pid: int) -> int:
	var own: Array[SimEntity] = w.units_of(pid)
	if own.is_empty() or _rnd(12) == 0:
		return 1 + _rnd(80)  # a possibly stale / foreign / nonexistent id
	return own[_rnd(own.size())].id


func _cmd(w: SimWorld) -> void:
	var pid: int = _rnd(2)
	var ids: PackedInt32Array = PackedInt32Array([_pick(w, pid), _pick(w, pid)])
	var slot: int = _rnd(9) - 2
	match _rnd(9):
		0:
			w.submit_raw(pid, SimCmd.build(SimCmd.DEPLOY, [slot], ids))
		1:
			w.submit_raw(pid, SimCmd.build(SimCmd.UNDEPLOY, [slot], ids))
		2:
			w.submit_raw(pid, SimCmd.build(SimCmd.SET_MODE, [slot, _rnd(4) - 1], ids))
		3:
			w.submit_raw(pid, SimCmd.build(SimCmd.USE_ABILITY, [slot, _rnd(3), _pick(w, _rnd(2)), -1, -1], ids))
		4:
			w.submit_raw(pid, SimCmd.build(SimCmd.SET_AUTOCAST, [slot, _rnd(2)], ids))
		5:
			w.submit_raw(pid, SimCmd.build(SimCmd.UNLOAD, [_rnd(2), _pick(w, pid), (2 + _rnd(60)) * 1024, (2 + _rnd(60)) * 1024], ids))
		6:
			w.submit_raw(pid, SimCmd.build(SimCmd.LOAD, [_pick(w, pid), _rnd(3)], ids))
		7:
			w.submit_raw(pid, SimCmd.build(SimCmd.MOVE, [(4 + _rnd(56)) * 1024, (4 + _rnd(56)) * 1024, _rnd(3), 0], ids))
		_:
			var g: int = 0
			for n: SimEntity in w.neutrals:
				g = n.id
				if _rnd(2) == 0:
					break
			w.submit_raw(pid, SimCmd.build(SimCmd.GARRISON, [g, _rnd(3)], ids))


func _run(seed_value: int, ticks: int) -> PackedInt64Array:
	var w: SimWorld = _build(seed_value)
	for s: int in ticks:
		if s % 5 == 0:
			_cmd(w)
			_cmd(w)
		w.step()
	var bad: PackedStringArray = w.abilities.debug_validate(w)
	if not bad.is_empty():
		push_error("fuzz: debug_validate: " + str(bad.slice(0, 3)))
	return PackedInt64Array([w.checksum(), w.events.digest(), w.abilities.timer_digest, A.count_events(w, K.EV_MODE_CHANGED), A.count_events(w, K.EV_LOADED), A.count_events(w, K.EV_UNLOADED)])


func test_fuzz_no_errors_and_deterministic(t: TestCtx) -> void:
	for seed_value: int in [3, 17, 91]:
		var a: PackedInt64Array = _run(seed_value, 1200)
		var b: PackedInt64Array = _run(seed_value, 1200)
		t.eq(a, b, "seed %d: identical double run" % seed_value)
		t.gt(a[3] + a[4] + a[5], 0, "seed %d: the fuzz reached the features (modes %d loads %d unloads %d)" % [seed_value, a[3], a[4], a[5]])
