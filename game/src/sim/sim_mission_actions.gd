class_name SimMissionActions
extends RefCounted
## Action executor of the mission system. Every effect goes through the kernel's public API (spawn / kill / change_owner /
## eliminate / end_match / add_credits, world.orders.issue); scripted forces get ordinary SimOrders, never AI commands. Ints only.


static func run(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	match a.op:
		DefMissionAction.Op.SET_OBJECTIVE:
			s.set_objective(w, a.ref, a.value)
		DefMissionAction.Op.SHOW_MESSAGE:
			var ann: int = a.value if a.value >= 0 else s.def.messages[a.ref].announcer_idx
			w.emit(SimEvent.MISSION_MESSAGE, 0, 0, a.ref, ann, 0)
		DefMissionAction.Op.TIMER_START:
			s.start_timer(w, a.ref, a.value)
		DefMissionAction.Op.TIMER_STOP:
			s.stop_timer(w, a.ref)
		DefMissionAction.Op.SPAWN_UNITS:
			spawn_units(s, w, a)
		DefMissionAction.Op.SPAWN_STRUCTURE:
			_spawn_structure(s, w, a)
		DefMissionAction.Op.GIVE_CREDITS:
			_give_credits(w, a)
		DefMissionAction.Op.GRANT_POWER, DefMissionAction.Op.LOCK_POWER:
			_power_lock(w, a)
		DefMissionAction.Op.REVEAL_AREA:
			_reveal(s, w, a)
		DefMissionAction.Op.CHANGE_AI:
			_change_ai(s, w, a)
		DefMissionAction.Op.TRANSFER:
			for e: SimEntity in _targets(s, w, a):
				w.change_owner(e.id, a.to_pid, SimEvent.OWNER_SCRIPT)
		DefMissionAction.Op.DESTROY:
			for e: SimEntity in _targets(s, w, a):
				w.kill(e, SimWorld.Cause.SCRIPT, 0, -1)
		DefMissionAction.Op.ORDER_UNITS:
			_order_units(s, w, a)
		DefMissionAction.Op.ELIMINATE:
			w.eliminate(a.owner_val, SimPlayer.Elim.SCRIPT)
		DefMissionAction.Op.TRIGGER_ENABLE:
			s.trig_enabled[a.ref] = 1
			s.trig_last_val[a.ref] = 0
		DefMissionAction.Op.TRIGGER_DISABLE:
			s.trig_enabled[a.ref] = 0
		DefMissionAction.Op.WIN:
			s.finish(w, a.owner_val, true)
		DefMissionAction.Op.LOSE:
			s.finish(w, a.owner_val, false)
		DefMissionAction.Op.CAMERA_HINT:
			_camera(s, w, a)
		DefMissionAction.Op.MUSIC_STATE:
			w.emit(SimEvent.MISSION_MUSIC, 0, 0, a.value)


# ---------------------------------------------------------------------------------------------------- start
## A mission player's start: HQ / MCV on its start cell, then the extra entities relative to that cell (SPAWN_INITIAL, F_INITIAL).
static func start_entities(s: SimMissionSystem, w: SimWorld, pl: DefMissionPlayer) -> void:
	var cell: int = SimMissionSystem.start_cell(w, pl.slot)
	if cell < 0:
		Log.error("mission", "player %d: start slot %d has no spawn on this map" % [pl.slot, pl.start_slot])
		return
	var p: SimPlayer = w.players[pl.slot]
	var cx: int = cell % w.map.w
	var cy: int = cell / w.map.w
	var x: int = cx * SimConfig.CELL + SimConfig.CELL / 2
	var y: int = cy * SimConfig.CELL + SimConfig.CELL / 2
	if pl.start_mode == 0:
		if p.roster.hq_idx >= 0:
			w.spawn_entity(SimEntity.Kind.STRUCTURE, p.roster.hq_idx, pl.slot, x, y, 0, SimFlags.F_INITIAL, 0, 0, SimEvent.SPAWN_INITIAL)
		else:
			Log.error("mission", "player %d: roster has no HQ" % pl.slot)
	elif pl.start_mode == 1:
		if p.roster.mcv_idx >= 0:
			w.spawn_entity(SimEntity.Kind.UNIT, p.roster.mcv_idx, pl.slot, x, y, 0, SimFlags.F_INITIAL, 0, 0, SimEvent.SPAWN_INITIAL)
		else:
			Log.error("mission", "player %d: roster has no MCV" % pl.slot)
	for i: int in pl.start_kinds.size():
		var tx: int = clampi(cx + pl.start_dx[i], 0, w.map.w - 1)
		var ty: int = clampi(cy + pl.start_dy[i], 0, w.map.h - 1)
		if pl.start_kinds[i] == 0:
			for _n: int in pl.start_count[i]:
				_place_unit(w, pl.slot, pl.start_def_idx[i], ty * w.map.w + tx, 0, SimEvent.SPAWN_INITIAL, SimFlags.F_INITIAL)
		else:
			var e: SimEntity = _place_structure(w, pl.slot, pl.start_def_idx[i], tx, ty, 0, SimFlags.F_INITIAL, SimEvent.SPAWN_INITIAL)
			if e != null and pl.start_placed[i] >= 0:
				s.placed_id[pl.start_placed[i]] = e.id
				s.placed_owner0[pl.start_placed[i]] = pl.slot


# ---------------------------------------------------------------------------------------------------- spawning
## One unit on the free cell nearest to `cell` (map cell index); null when none (nothing spawned).
static func _place_unit(w: SimWorld, owner: int, def_idx: int, cell: int, facing: int, reason: int, flags: int) -> SimEntity:
	var layer: int = w.defs.home_layer(SimEntity.Kind.UNIT, def_idx)
	var at: int = SimMovement.find_free_cell_near(w, cell, layer, SimMissionConst.SPAWN_SEARCH_RADIUS)
	if at < 0:
		Log.warn("mission", "no free cell near %d for unit def %d" % [cell, def_idx])
		return null
	var x: int = (at % w.map.w) * SimConfig.CELL + SimConfig.CELL / 2
	var y: int = (at / w.map.w) * SimConfig.CELL + SimConfig.CELL / 2
	return w.spawn_unit(def_idx, owner, x, y, facing, flags, 0, 0, reason)


static func spawn_units(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	if a.owner_val >= 0 and (a.owner_val >= w.players.size() or w.players[a.owner_val].eliminated != 0):
		return
	var center: int = s.area_center_cell(w, a.area)
	var made: Array[SimEntity] = []
	for _i: int in a.count:
		var e: SimEntity = _place_unit(w, a.owner_val, a.def_idx, center, a.value, SimEvent.SPAWN_SCRIPT, 0)
		if e != null:
			made.append(e)
	_issue_all(s, w, made, a)
	if a.wave >= 0:
		var ids: PackedInt32Array = s.wave_ids[a.wave]
		for e: SimEntity in made:
			ids.append(e.id)
		s.wave_ids[a.wave] = ids
		s.wave_spawned[a.wave] = 1
		w.emit(SimEvent.MISSION_WAVE, 0, 0, a.wave, 0, made.size())


static func _spawn_structure(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	if a.owner_val >= 0 and (a.owner_val >= w.players.size() or w.players[a.owner_val].eliminated != 0):
		return
	var cx: int = a.cell_x
	var cy: int = a.cell_y
	if a.area >= 0:
		var c: int = s.area_center_cell(w, a.area)
		cx = c % w.map.w
		cy = c / w.map.w
	var owner: int = -1 if a.owner_mode == DefMissionCond.OWN_NEUTRAL else a.owner_val
	var e: SimEntity = _place_structure(w, owner, a.def_idx, cx, cy, a.value, SimFlags.F_INITIAL, SimEvent.SPAWN_SCRIPT)
	if e != null and a.placed >= 0:
		s.placed_id[a.placed] = e.id
		s.placed_owner0[a.placed] = owner


## Free, active structure with its footprint origin at / near cell (cx, cy); null when no buildable site within the search radius.
static func _place_structure(w: SimWorld, owner: int, def_idx: int, cx: int, cy: int, rot: int, flags: int, reason: int) -> SimEntity:
	var fp: MapFootprint = w.map.footprint_of(SimEntity.Kind.STRUCTURE, def_idx)
	if fp == null:
		var d: DefStructure = w.data.structures[def_idx]
		fp = MapFootprint.new(d.fp_w, d.fp_h, d.fp_mask, false)
	var orient: int = rot & 3 if fp.rotatable else 0
	var cells: PackedInt32Array = PackedInt32Array()
	for r: int in range(0, SimMissionConst.STRUCT_SEARCH_RADIUS + 1):
		var k: int = 0
		while true:
			var rc: int = SimExitMove.ring_cell(r, k)
			if rc < 0:
				break
			k += 1
			var ox: int = cx + (rc & 0xFFFF) - 32768
			var oy: int = cy + (rc >> 16) - 32768
			if fp.cells_at(orient, ox, oy, cells, w.map.w, w.map.h) < 0:
				continue
			var ok: bool = true
			for ci: int in cells:
				if not w.map.is_buildable(ci % w.map.w, ci / w.map.w) or w.map.occupant_at(ci) >= 0:
					ok = false
					break
			if not ok:
				continue
			var sz: int = fp.size_oriented(orient)
			var x: int = ox * SimConfig.CELL + (sz >> 8) * (SimConfig.CELL / 2)
			var y: int = oy * SimConfig.CELL + (sz & 255) * (SimConfig.CELL / 2)
			return w.spawn_structure(def_idx, owner, x, y, orient << 10 if fp.rotatable else 0, flags, 0, 0, reason)
	Log.warn("mission", "no buildable site near cell (%d, %d) for structure def %d" % [cx, cy, def_idx])
	return null


# ---------------------------------------------------------------------------------------------------- orders
## Order of `a` (spawn_units / order_units) for every unit: targets are spread over the cells around the order area centre.
static func _issue_all(s: SimMissionSystem, w: SimWorld, units: Array[SimEntity], a: DefMissionAction) -> void:
	if a.order == DefMissionAction.ORD_NONE:
		return
	var type: int = SimOrder.T_HOLD
	match a.order:
		DefMissionAction.ORD_MOVE:
			type = SimOrder.T_MOVE
		DefMissionAction.ORD_ATTACK_MOVE:
			type = SimOrder.T_ATTACK_MOVE
		DefMissionAction.ORD_GUARD:
			type = SimOrder.T_GUARD
	var center: int = s.area_center_cell(w, a.order_area) if a.order_area >= 0 else -1
	var cursor: int = 0
	for e: SimEntity in units:
		var x: int = e.x
		var y: int = e.y
		if center >= 0:
			var found: PackedInt32Array = _spread_cell(w, center, e.layer, cursor)
			cursor = found[2]
			x = found[0] * SimConfig.CELL + SimConfig.CELL / 2
			y = found[1] * SimConfig.CELL + SimConfig.CELL / 2
		w.orders.issue(w, e, SimOrder.make(type, 0, x, y), SimOrder.QM_REPLACE)


## [cell x, cell y, next cursor]: the next clear cell of the ring walk around `center` for `layer` (the centre itself when none).
static func _spread_cell(w: SimWorld, center: int, layer: int, cursor: int) -> PackedInt32Array:
	var cx: int = center % w.map.w
	var cy: int = center / w.map.w
	var idx: int = cursor
	while idx < cursor + 289:  # rings 0..8
		var r: int = 0
		var left: int = idx
		while left >= (1 if r == 0 else 8 * r):
			left -= 1 if r == 0 else 8 * r
			r += 1
		var rc: int = SimExitMove.ring_cell(r, left)
		idx += 1
		var x: int = cx + (rc & 0xFFFF) - 32768
		var y: int = cy + (rc >> 16) - 32768
		if rc >= 0 and w.map.is_clear(x, y, layer):
			return PackedInt32Array([x, y, idx])
	return PackedInt32Array([cx, cy, idx])


static func _order_units(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	_issue_all(s, w, s.collect(w, a.owner_mode, a.owner_val, DefMissionCond.OF_UNIT, a.def_idx, a.tag_mask, a.area), a)


# ---------------------------------------------------------------------------------------------------- other effects
static func _targets(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> Array[SimEntity]:
	if a.placed >= 0:
		var out: Array[SimEntity] = []
		var e: SimEntity = w.get_entity(s.placed_id[a.placed])
		if e != null and (e.flags & SimFlags.F_GONE) == 0:
			out.append(e)
		return out
	return s.collect(w, a.owner_mode, a.owner_val, a.of_kind, a.def_idx, a.tag_mask, a.area)


static func _give_credits(w: SimWorld, a: DefMissionAction) -> void:
	var pid: int = a.owner_val
	if a.value > 0:
		w.add_credits(pid, a.value, SimEvent.CASH_SCRIPT)
	else:
		w.try_spend(pid, mini(-a.value, w.players[pid].credits), SimEvent.CASH_SCRIPT)


static func _power_lock(w: SimWorld, a: DefMissionAction) -> void:
	var pe: SimPlayerEcon = w.players[a.owner_val].econ
	if pe == null:
		return
	var lock: bool = a.op == DefMissionAction.Op.LOCK_POWER
	pe.slots[a.value].ready_tick = SimMissionConst.POWER_LOCK_TICK if lock else 0
	w.emit(SimEvent.MISSION_POWER, 0, 0, a.owner_val, a.value, 1 if lock else 0)


static func _reveal(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	if w.vision == null:
		return
	var o: int = a.area * SimMissionSystem.AREA_STRIDE
	var x: int = s.area_data[o + 5] * SimConfig.CELL + SimConfig.CELL / 2
	var y: int = s.area_data[o + 6] * SimConfig.CELL + SimConfig.CELL / 2
	for pid: int in s.pids_of(w, a.owner_mode, a.owner_val):
		if pid < 0:
			continue
		w.vision.add_temp_source(w.vision.group_of(pid), SimMatchSetup.SHAPE_DISC, x, y, 0, 0, s.area_radius_units(a.area), false, w.tick + a.value, 0)
		w.emit(SimEvent.MISSION_REVEAL, x, y, pid, a.area, a.value)


static func _change_ai(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	var pid: int = a.owner_val
	var p: SimPlayer = w.players[pid]
	if a.ai_active >= 0:
		s.ai_active[pid] = a.ai_active
	if a.ai_level >= 0:
		p.ai_level = a.ai_level
	if a.ai_style >= 0:
		p.ai_style = a.ai_style
	if a.ai_aggr >= 0:
		s.ai_aggr[pid] = a.ai_aggr
	w.emit(SimEvent.MISSION_AI, 0, 0, pid, s.ai_active[pid], p.ai_level, s.ai_aggr[pid])


static func _camera(s: SimMissionSystem, w: SimWorld, a: DefMissionAction) -> void:
	var cx: int = a.cell_x
	var cy: int = a.cell_y
	if a.area >= 0:
		cx = s.area_data[a.area * SimMissionSystem.AREA_STRIDE + 5]
		cy = s.area_data[a.area * SimMissionSystem.AREA_STRIDE + 6]
	w.emit(SimEvent.MISSION_CAMERA, cx * SimConfig.CELL + SimConfig.CELL / 2, cy * SimConfig.CELL + SimConfig.CELL / 2, a.area, a.value)
