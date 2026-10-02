class_name TutorialPlayer
extends RefCounted
## MIS3: a SCRIPTED PLAYER of the tutorial 'Field Training': does what each hint asks, with real commands (SimCmd through submit_raw), the moment the
## step's objective becomes active. Proves that every gate of the course can be passed by playing (no timeout is needed) and measures how long a
## quick player needs. Camera / selection / control-group steps are UI-only: the player just waits for their timer.
##   var p := TutorialPlayer.new(); each tick before world.step(): p.act(world)

var pid: int = 0
var step_log: Array = []  ## [tick, objective] when a step was first acted on
var _acted: Dictionary = {}
var _place_wait: int = 0
var _rally_set: bool = false


func act(w: SimWorld) -> void:
	if w.mission == null or w.match_state != SimWorld.MATCH_RUNNING:
		return
	if w.tick % 5 != 0:
		return
	var m: SimMissionSystem = w.mission
	for i: int in m.def.objectives.size():
		if m.obj_state[i] != SimMissionConst.OBJ_ACTIVE:
			continue
		var oid: String = m.def.objectives[i].id
		if not _acted.has(oid):
			_acted[oid] = true
			step_log.append([w.tick, oid])
		_do_step(w, oid)


func _area_xy(w: SimWorld, id: String) -> Vector2i:
	var c: int = w.mission.area_center_cell(w, w.mission.def.area_idx(id))
	return Vector2i((c % w.map.w) * 1024 + 512, (c / w.map.w) * 1024 + 512)


func _ids(w: SimWorld, tag_unit_id: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var idx: int = w.data.unit_idx(tag_unit_id)
	for e: SimEntity in w.units_of(pid):
		if (e.flags & SimFlags.F_GONE) == 0 and e.def_idx == idx:
			out.append(e.id)
	return out


func _structure(w: SimWorld, sid: String, ready_only: bool = true) -> SimEntity:
	var idx: int = w.data.structure_idx(sid)
	for s: SimEntity in w.structures_of(pid):
		if s.def_idx == idx and (s.flags & SimFlags.F_GONE) == 0 and (not ready_only or (s.flags & SimFlags.F_UNDER_CONSTRUCTION) == 0):
			return s
	return null


func _send(w: SimWorld, cmd: PackedInt32Array) -> void:
	w.submit_raw(pid, cmd)


## Starts / places one structure; returns true when it exists (or is queued).
func _build(w: SimWorld, sid: String, near: String) -> void:
	var idx: int = w.data.structure_idx(sid)
	if _structure(w, sid, false) != null:
		return
	var pe: SimPlayerEcon = w.players[pid].econ
	var st: PackedInt32Array = PackedInt32Array()
	w.production.construction_state(pid, st)
	if st[0] == 2:
		if w.tick < _place_wait or st[3] != idx:
			return
		var c: Vector2i = _area_xy(w, near)
		var site: PackedInt32Array = PackedInt32Array()
		if SimPlacement.find_site(w, pid, idx, c.x >> 10, c.y >> 10, 9, site):
			_send(w, SimCmd.build_place(idx, site[0], site[1], 0))
			_place_wait = w.tick + 20
		return
	if pe.cq_def.is_empty() and w.tick >= _place_wait:
		_send(w, SimCmd.build_start(idx, 1))
		_place_wait = w.tick + 10


func _train(w: SimWorld, producer_sid: String, unit_id: String, want_total: int) -> void:
	var prod: SimEntity = _structure(w, producer_sid)
	if prod == null or prod.prod == null:
		return
	var uidx: int = w.data.unit_idx(unit_id)
	var have: int = _ids(w, unit_id).size() + prod.prod.q_def.size()
	if have < want_total:
		_send(w, SimCmd.train(prod.id, uidx, 1))


func _do_step(w: SimWorld, oid: String) -> void:
	var tanks: PackedInt32Array = _ids(w, "unit.napc.guardian_tank")
	match oid:
		"s02":
			var c: Vector2i = _area_xy(w, "a_move1")
			if not tanks.is_empty() and not _acted.has("s02m"):
				_acted["s02m"] = true
				_send(w, SimCmd.move(tanks, c.x, c.y))
		"s03":
			var c2: Vector2i = _area_xy(w, "a_hostile1")
			if not tanks.is_empty() and not _acted.has("s03m"):
				_acted["s03m"] = true
				_send(w, SimCmd.attack_move(tanks, c2.x, c2.y))
		"s05":
			var pi: int = w.mission.def.placed.find("practice_target")
			var tid: int = w.mission.placed_id[pi] if pi >= 0 else 0
			if tid > 0 and not tanks.is_empty() and w.tick % 40 == 0:
				_send(w, SimCmd.force_fire(tanks, tid))
		"s06":
			_build(w, "structure.shared.generator", "a_gen")
		"s07":
			_build(w, "structure.shared.refinery", "a_ref")
		"s09":
			_build(w, "structure.shared.barracks", "a_base")
		"s10":
			_train(w, "structure.shared.barracks", "unit.napc.rifle_squad", 2)
		"s11":
			_build(w, "structure.shared.factory", "a_base")
		"s12":
			_train(w, "structure.shared.factory", "unit.napc.guardian_tank", 5)
		"s13":
			var fac: SimEntity = _structure(w, "structure.shared.factory")
			if fac != null:
				var rp: Vector2i = _area_xy(w, "a_rally")
				if not _rally_set:
					_rally_set = true
					_send(w, SimCmd.set_rally(PackedInt32Array([fac.id]), rp.x, rp.y))
				_train(w, "structure.shared.factory", "unit.napc.guardian_tank", tanks.size() + 1 if fac.prod.q_def.is_empty() else tanks.size() + fac.prod.q_def.size())
		"s15":
			_build(w, "structure.shared.anti_tank_turret", "a_def")
		"s16":
			_build(w, "structure.shared.radar", "a_radar")
		"s17":
			var rp2: Vector2i = _area_xy(w, "a_w_north")
			if w.tick % 100 == 0:
				_send(w, SimCmd.use_power(w.data.power_idx("power.napc.uav_sweep"), rp2.x, rp2.y))
		"s18", "s20":
			_defend(w, tanks)
		"s19":
			var pi2: int = w.mission.def.placed.find("old_tower")
			var oid2: int = w.mission.placed_id[pi2] if pi2 >= 0 else 0
			if oid2 > 0 and not _acted.has("s19s"):
				_acted["s19s"] = true
				_send(w, SimCmd.sell(PackedInt32Array([oid2])))
		"s21":
			_defend(w, tanks)


## Tanks attack-move to the nearest visible enemy (fog is off in the tutorial), else stay.
func _defend(w: SimWorld, tanks: PackedInt32Array) -> void:
	if tanks.is_empty() or w.tick % 40 != 0:
		return
	var best: SimEntity = null
	var best_d: int = 1 << 60
	var hq: SimEntity = _structure(w, "structure.shared.headquarters")
	if hq == null:
		return
	for p: SimPlayer in w.players:
		if p.pid == pid:
			continue
		for u: SimEntity in w.units_of(p.pid):
			if (u.flags & SimFlags.F_GONE) != 0:
				continue
			var d: int = absi(u.x - hq.x) + absi(u.y - hq.y)
			if d < best_d:
				best_d = d
				best = u
	if best != null and best_d < 40 * 1024:
		_send(w, SimCmd.attack_move(tanks, best.x, best.y))
