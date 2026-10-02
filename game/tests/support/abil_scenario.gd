class_name AbilScenario
extends RefCounted
## The composite abilities scenario (abilities 10.3 D1 / D4): 4 players with camouflage, detector, submarine and
## turret defs walk a seeded random walk on the 96x96 test map while timed effects, conditional effects, reveals, a
## capture and a kill happen at scripted ticks. Everything the script does is a pure function of (tick, entity id).

const CELL: int = 1024
const K := preload("res://src/sim/abilities/sim_ability_consts.gd")


static func build(fog: bool = true) -> SimWorld:
	var d: GameData = AbilKit.data()
	AbilKit.set_sight(d, DefTestKit.U_ENGINEER, 8192)
	var list: Array[DefEffect] = [
		AbilKit.fx_stat(DefEnums.Stat.SPEED, 2500, 1),
		AbilKit.fx_stat(DefEnums.Stat.SIGHT, -2500, 2),
		AbilKit.fx_stat(DefEnums.Stat.SIGHT, 2000, 3),
		AbilKit.fx_op(DefEnums.EffectOp.CAMOUFLAGE, 0, {"end_on": ["move", "fire", "detected"]}),
		AbilKit.fx_op(DefEnums.EffectOp.HEAL, 0, {"rate_bps": 100, "cost": "free"}),
		AbilKit.fx_op(DefEnums.EffectOp.RESIST_MOD, 3000),
	]
	list[5].fire_mode_mask = 1
	AbilKit.add_zone_effects(d, list)
	var cond: DefEffect = AbilKit.fx_stat(DefEnums.Stat.SPEED, 1000)
	cond.cond_codes = PackedInt32Array([DefEnums.Cond.OUT_OF_COMBAT])
	cond.cond_params = [{"for_t": 60}]
	AbilKit.add_research_effects(d, [cond])
	var w: SimWorld = AbilKit.world({"players": 4, "seed": 99, "rules": {"fog": fog}}, d)
	for pid: int in 4:
		AbilKit.bind_cond(w, pid, DefTestKit.U_TANK, cond)
	var rows: Array = [
		[DefTestKit.U_RIFLEMAN, 6], [DefTestKit.U_TANK, 2], [DefTestKit.U_COLLECTOR, 1],
		[DefTestKit.U_ENGINEER, 2], [DefTestKit.U_TANK2, 1],
	]
	for pid2: int in 4:
		var bx: int = 16 + (pid2 % 2) * 60
		var by: int = 16 + (pid2 / 2) * 60
		var n: int = 0
		for r: Array in rows:
			for k: int in int(r[1]):
				AbilKit.spawn(w, r[0], pid2, bx + (n % 5) * 3, by + (n / 5) * 3)
				n += 1
		AbilKit.spawn_struct(w, DefTestKit.S_TURRET, pid2, bx + 8, by + 12)
	return w


static func _mix(a: int, b: int) -> int:
	var v: int = (a * 2654435761 + b * 40503 + 12345) & 0x7FFFFFFF
	v ^= v >> 13
	v = (v * 1274126177) & 0x7FFFFFFF
	return v ^ (v >> 16)


## Scripted step before step number s + 1 (w.tick == s).
static func script(w: SimWorld, s: int) -> void:
	var units: Array[SimEntity] = w.units
	for e: SimEntity in units:
		if (e.flags & SimFlags.F_GONE) != 0 or e.combat == null:
			continue
		var h: int = _mix(e.id, s / 9)
		var moving: bool = (h & 3) != 0 and e.kind == SimEntity.Kind.UNIT
		e.combat.ext_moving = 1 if moving else 0
		if moving and (s + e.id) % 2 == 0:
			var ang: int = (_mix(e.id, s / 40) & 3)
			var dx: int = [180, -180, 0, 0][ang]
			var dy: int = [0, 0, 180, -180][ang]
			w.set_pos(e, clampi(e.x + dx, 3 * CELL, 92 * CELL), clampi(e.y + dy, 3 * CELL, 92 * CELL))
	var fxt: SimEffectTable = w.abilities.fx_table
	if s % 100 == 20:
		for i: int in units.size():
			var e2: SimEntity = units[i]
			if (e2.flags & SimFlags.F_GONE) == 0 and _mix(e2.id, s) % 5 == 0:
				var k: int = _mix(e2.id, s + 1) % 6
				w.abilities.apply_timed_effect(e2.id, fxt.zone_effect(0, k), 60 + _mix(e2.id, s + 2) % 200, e2.owner, 500 + k)
	if s == 150 and w.vision != null:
		SimVision.add_reveal(w, 0xFF, K.SHAPE_DISC, 40 * CELL, 40 * CELL, 0, 0, 5120, 300, true, 0)
		SimVision.add_reveal(w, 0xFF, K.SHAPE_CAPSULE, 20 * CELL, 70 * CELL, 32 * CELL, 70 * CELL, 2048, 450, false, 0)
	if s == 400 and w.structures.size() > 1:
		w.change_owner(w.structures[0].id, 1)
	if s == 700 and w.structures.size() > 2:
		w.kill(w.structures[2], SimWorld.Cause.SCRIPT)
	if s == 500 and units.size() > 10:
		w.abilities.on_owner_changed(w, units[3], units[3].owner)
