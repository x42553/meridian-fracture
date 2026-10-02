class_name SimMissionSystem
extends RefCounted
## Scripted-mission runtime (MIS1). One instance per SimWorld that was created with `config.mission_id != ""` (world.mission),
## compiled from the DefMission of GameData (data.ext["missions"]; JSON schema in DefMissionParser). NOT a pipeline stage: the
## kernel's stage 11 (SimCleanupSystem) calls `update(world)` at its very end, so every trigger sees the world after deaths,
## removals and list compaction of the tick. Its authoritative state is hashed through SimCleanupSystem.hash_state (part
## `sys.cleanup` of the checksum, DR-13); with no mission the part is unchanged.
##
## SEMANTICS
##  - Evaluation: when world.tick % 5 == 0, in this order: timers (expiry / repeat restart), area_left latches, then every ENABLED
##    trigger in ascending trigger id. A trigger fires when its `when` tree is true (edge / cooldown / once rules in
##    DefMissionParser), then runs its actions in order; actions take effect immediately, so later triggers of the same pass see
##    their results. Nothing is evaluated once the match ended (a win / lose action ends it at once).
##  - Start (begin(), called by SimWorld after the initial entities): areas are resolved against the generated map, mission
##    rules were already applied (apply_rules: victory 0 by default, start_mode forced to NONE), then per mission player in slot
##    order: credits, AI activity, start HQ / MCV and the extra start entities (units placed on free cells near the start cell
##    + offset, free structures), autostart timers, initial objective states (events for every non-hidden one).
##  - Scripted forces are normal entities owned by their player; orders are plain SimOrders issued through world.orders (never
##    through the AI module). An AI player with ai_active == 0 has every command rejected (blocks_commands), so a scripted AI
##    can be switched on later by change_ai.
##  - Result: win(p) ends the match with winner team = team of p and reason EndReason.MISSION_WIN; lose(p) eliminates p
##    (Elim.SCRIPT) and ends it with reason MISSION_LOSE (winner = the first non-eliminated player of another team, else none).
##    Both flow through world.end_match, i.e. the normal MATCH_END event, match_result(), end screen and replay trailer.
##  - UI events (SimEvent.MISSION_*, block 130-159) are output only. Determinism: ints only, ordered iteration, no RNG.

var def: DefMission = null
var data: GameData = null

# ---- hashed runtime state ----
var obj_state: PackedInt32Array = PackedInt32Array()
var trig_enabled: PackedInt32Array = PackedInt32Array()
var trig_fired: PackedInt32Array = PackedInt32Array()
var trig_last_tick: PackedInt32Array = PackedInt32Array()
var trig_last_val: PackedInt32Array = PackedInt32Array()
var timer_state: PackedInt32Array = PackedInt32Array()
var timer_end: PackedInt32Array = PackedInt32Array()
var timer_len: PackedInt32Array = PackedInt32Array()
var placed_id: PackedInt32Array = PackedInt32Array()  ## entity id of a placed structure, 0 = not spawned yet
var placed_owner0: PackedInt32Array = PackedInt32Array()  ## its first owner
var wave_spawned: PackedInt32Array = PackedInt32Array()
var wave_ids: Array[PackedInt32Array] = []
var latch: PackedInt32Array = PackedInt32Array()
var area_data: PackedInt32Array = PackedInt32Array()  ## resolved areas, AREA_STRIDE ints each
var ai_active: PackedInt32Array = PackedInt32Array()  ## per pid 0..7
var ai_aggr: PackedInt32Array = PackedInt32Array()
var result: int = SimMissionConst.RES_NONE
var result_pid: int = -1
var result_tick: int = 0
var passes: int = 0  ## evaluation passes run

const AREA_STRIDE: int = 8  ## shape, x0, y0, x1, y1, cx, cy, r2 (cells)


## null (+ Log.error) when the mission id is unknown to `game_data`.
static func create(game_data: GameData, mission_id: String) -> SimMissionSystem:
	var t: DefMissionTable = DefMissionTable.of(game_data)
	var m: DefMission = t.get_mission(mission_id) if t != null else null
	if m == null:
		Log.error("mission", "unknown mission '%s'" % mission_id)
		return null
	var s: SimMissionSystem = SimMissionSystem.new()
	s.def = m
	s.data = game_data
	s._alloc()
	return s


func _alloc() -> void:
	obj_state.resize(def.objectives.size())
	trig_enabled.resize(def.triggers.size())
	trig_fired.resize(def.triggers.size())
	trig_last_tick.resize(def.triggers.size())
	trig_last_tick.fill(-1)
	trig_last_val.resize(def.triggers.size())
	timer_state.resize(def.timers.size())
	timer_end.resize(def.timers.size())
	timer_len.resize(def.timers.size())
	placed_id.resize(def.placed.size())
	placed_owner0.resize(def.placed.size())
	placed_owner0.fill(-1)
	wave_spawned.resize(def.waves.size())
	wave_ids.clear()
	for _i: int in def.waves.size():
		wave_ids.append(PackedInt32Array())
	latch.resize(def.latches)
	area_data.resize(def.areas.size() * AREA_STRIDE)
	ai_active.resize(SimConfig.MAX_PLAYERS)
	ai_active.fill(1)
	ai_aggr.resize(SimConfig.MAX_PLAYERS)
	ai_aggr.fill(50)
	for i: int in def.triggers.size():
		trig_enabled[i] = 1 if def.triggers[i].enabled else 0
	for i: int in def.timers.size():
		timer_len[i] = def.timers[i].ticks


## The world's effective rules: the config's rules plus the mission overrides; start_mode is always NONE (begin() places the starts).
func apply_rules(base: SimMatchRules) -> SimMatchRules:
	var r: SimMatchRules = SimMatchRules.from_dict(base.to_dict())
	for k: Variant in def.rules.keys():
		r.set(str(k), int(def.rules[k]))
	r.start_mode = SimMatchRules.START_NONE
	return r


## Problems of `def` against a concrete config (SimMatchConfig.validate): every mission player must be a config player.
func config_problems(cfg: SimMatchConfig) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for p: DefMissionPlayer in def.players:
		var found: bool = false
		for s: SimPlayerSlot in cfg.players:
			found = found or s.pid == p.slot
		if not found:
			out.append("mission '%s' needs player slot %d" % [def.id, p.slot])
	return out


# ---------------------------------------------------------------------------------------------------- begin
func begin(world: SimWorld) -> void:
	_resolve_areas(world)
	for pl: DefMissionPlayer in def.players:
		if pl.slot >= world.players.size():
			continue
		var p: SimPlayer = world.players[pl.slot]
		if p.controller == SimPlayer.Controller.NONE:
			continue
		if pl.credits >= 0:
			p.credits = pl.credits * pl.handicap / 100
		ai_active[pl.slot] = 1 if (pl.human or pl.ai_active) else 0
		ai_aggr[pl.slot] = pl.ai_aggr
		SimMissionActions.start_entities(self, world, pl)
	for i: int in def.timers.size():
		if def.timers[i].autostart:
			start_timer(world, i, 0)
	for i: int in def.objectives.size():
		obj_state[i] = def.objectives[i].initial
		if obj_state[i] != SimMissionConst.OBJ_HIDDEN:
			world.emit(SimEvent.MISSION_OBJECTIVE, 0, 0, i, obj_state[i], def.objectives[i].kind, SimMissionConst.OBJ_HIDDEN)


func _resolve_areas(world: SimWorld) -> void:
	var w: int = world.map.w
	var h: int = world.map.h
	for i: int in def.areas.size():
		var a: DefMissionArea = def.areas[i]
		var x: int = a.x
		var y: int = a.y
		if a.anchor == DefMissionArea.Anchor.MAP:
			x = a.x * (w - 1) / 1000
			y = a.y * (h - 1) / 1000
		elif a.anchor == DefMissionArea.Anchor.START:
			var sc: int = start_cell(world, a.anchor_pid)
			x = (sc % w) + a.x if sc >= 0 else a.x
			y = (sc / w) + a.y if sc >= 0 else a.y
		var o: int = i * AREA_STRIDE
		if a.shape == DefMissionArea.Shape.CIRCLE:
			var cx: int = clampi(x, 0, w - 1)
			var cy: int = clampi(y, 0, h - 1)
			area_data[o] = 0
			area_data[o + 1] = maxi(cx - a.r, 0)
			area_data[o + 2] = maxi(cy - a.r, 0)
			area_data[o + 3] = mini(cx + a.r, w - 1)
			area_data[o + 4] = mini(cy + a.r, h - 1)
			area_data[o + 5] = cx
			area_data[o + 6] = cy
			area_data[o + 7] = a.r * a.r
		else:
			var x0: int = clampi(x, 0, w - 1)
			var y0: int = clampi(y, 0, h - 1)
			var x1: int = clampi(x + a.w - 1, x0, w - 1)
			var y1: int = clampi(y + a.h - 1, y0, h - 1)
			area_data[o] = 1
			area_data[o + 1] = x0
			area_data[o + 2] = y0
			area_data[o + 3] = x1
			area_data[o + 4] = y1
			area_data[o + 5] = (x0 + x1) / 2
			area_data[o + 6] = (y0 + y1) / 2
			area_data[o + 7] = 0


## Spawn cell index (map cell) of the player's start slot, -1 when unknown.
static func start_cell(world: SimWorld, pid: int) -> int:
	for s: SimPlayerSlot in world.config.players:
		if s.pid == pid:
			var rec: int = s.start * MapData.SPAWN_STRIDE
			if rec >= 0 and rec + 1 < world.map.spawns.size():
				return world.map.spawns[rec + 1]
	return -1


# ---------------------------------------------------------------------------------------------------- areas
## Resolved centre cell index of area `a`.
func area_center_cell(world: SimWorld, a: int) -> int:
	var o: int = a * AREA_STRIDE
	return area_data[o + 6] * world.map.w + area_data[o + 5]


func in_area(a: int, cx: int, cy: int) -> bool:
	var o: int = a * AREA_STRIDE
	if cx < area_data[o + 1] or cx > area_data[o + 3] or cy < area_data[o + 2] or cy > area_data[o + 4]:
		return false
	if area_data[o] == 1:
		return true
	var dx: int = cx - area_data[o + 5]
	var dy: int = cy - area_data[o + 6]
	return dx * dx + dy * dy <= area_data[o + 7]


## Bounding radius of an area in sub-cell units (used for the reveal disc).
func area_radius_units(a: int) -> int:
	var o: int = a * AREA_STRIDE
	var rx: int = (area_data[o + 3] - area_data[o + 1]) / 2 + 1
	var ry: int = (area_data[o + 4] - area_data[o + 2]) / 2 + 1
	return maxi(rx, ry) * SimConfig.CELL


# ---------------------------------------------------------------------------------------------------- queries
## Pids selected by an owner selector (DefMissionCond.OWN_*), ascending; -1 = neutral. Vacant pids are never selected.
func pids_of(world: SimWorld, mode: int, val: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	match mode:
		DefMissionCond.OWN_PID:
			if val >= 0 and val < world.players.size() and world.players[val].controller != SimPlayer.Controller.NONE:
				out.append(val)
		DefMissionCond.OWN_NEUTRAL:
			out.append(-1)
		_:
			var ref_team: int = world.team_of(val) if (mode == DefMissionCond.OWN_ENEMIES_OF or mode == DefMissionCond.OWN_ALLIES_OF) else -1
			for p: SimPlayer in world.players:
				if p.controller == SimPlayer.Controller.NONE:
					continue
				var take: bool = false
				match mode:
					DefMissionCond.OWN_ALL:
						take = true
					DefMissionCond.OWN_TEAM:
						take = p.team == val
					DefMissionCond.OWN_ENEMIES_OF:
						take = p.team != ref_team
					DefMissionCond.OWN_ALLIES_OF:
						take = p.team == ref_team and p.pid != val
				if take:
					out.append(p.pid)
	return out


## Does entity `e` pass the filter (kind is already right)?
func matches(e: SimEntity, def_idx: int, tag_mask: int, area: int) -> bool:
	if (e.flags & SimFlags.F_GONE) != 0:
		return false
	if def_idx >= 0 and e.def_idx != def_idx:
		return false
	if tag_mask != 0:
		var tags: int = data.units[e.def_idx].tags if e.kind == SimEntity.Kind.UNIT else data.structures[e.def_idx].tags
		if (tags & tag_mask) != tag_mask:
			return false
	if area >= 0:
		if (e.flags & SimFlags.F_INSIDE) != 0 or not in_area(area, e.x >> SimConfig.CELL_SHIFT, e.y >> SimConfig.CELL_SHIFT):
			return false
	return true


## Live entities (ids ascending per pid, pids ascending) of the selected owners passing the filter.
func collect(world: SimWorld, mode: int, val: int, of_kind: int, def_idx: int, tag_mask: int, area: int) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for pid: int in pids_of(world, mode, val):
		if of_kind == DefMissionCond.OF_UNIT or of_kind == DefMissionCond.OF_ANY:
			for e: SimEntity in world.units_of(pid):
				if matches(e, def_idx, tag_mask, area):
					out.append(e)
		if of_kind == DefMissionCond.OF_STRUCTURE or of_kind == DefMissionCond.OF_ANY:
			for e: SimEntity in world.structures_of(pid):
				if matches(e, def_idx, tag_mask, area):
					out.append(e)
	return out


func count(world: SimWorld, mode: int, val: int, of_kind: int, def_idx: int, tag_mask: int, area: int) -> int:
	var n: int = 0
	for pid: int in pids_of(world, mode, val):
		if of_kind == DefMissionCond.OF_UNIT or of_kind == DefMissionCond.OF_ANY:
			for e: SimEntity in world.units_of(pid):
				if matches(e, def_idx, tag_mask, area):
					n += 1
		if of_kind == DefMissionCond.OF_STRUCTURE or of_kind == DefMissionCond.OF_ANY:
			for e: SimEntity in world.structures_of(pid):
				if matches(e, def_idx, tag_mask, area):
					n += 1
	return n


## true when commands of `pid` must be rejected: an AI whose mission switch is off.
func blocks_commands(world: SimWorld, pid: int) -> bool:
	return pid >= 0 and pid < ai_active.size() and ai_active[pid] == 0 and pid < world.players.size() \
		and world.players[pid].controller == SimPlayer.Controller.AI


# ---------------------------------------------------------------------------------------------------- update
func update(world: SimWorld) -> void:
	if world.match_state != SimWorld.MATCH_RUNNING or world.tick % SimMissionConst.EVAL_PERIOD != 0:
		return
	passes += 1
	_tick_timers(world)
	_update_latches(world)
	for i: int in def.triggers.size():
		if world.match_state != SimWorld.MATCH_RUNNING:
			return
		_run_trigger(world, i)


func _tick_timers(world: SimWorld) -> void:
	for i: int in def.timers.size():
		if timer_state[i] == SimMissionConst.TM_EXPIRED and def.timers[i].repeat:
			timer_state[i] = SimMissionConst.TM_RUNNING
			while timer_end[i] <= world.tick:
				timer_end[i] += maxi(timer_len[i], 1)
		if timer_state[i] == SimMissionConst.TM_RUNNING and world.tick >= timer_end[i]:
			timer_state[i] = SimMissionConst.TM_EXPIRED
			world.emit(SimEvent.MISSION_TIMER, 0, 0, i, 2, timer_len[i])


func _update_latches(world: SimWorld) -> void:
	if latch.is_empty():
		return
	for t: DefMissionTrigger in def.triggers:
		_latch_walk(world, t.when)


func _latch_walk(world: SimWorld, c: DefMissionCond) -> void:
	if c == null:
		return
	if c.op == DefMissionCond.Op.AREA_LEFT:
		if latch[c.ref] == 0 and count(world, c.owner_mode, c.owner_val, DefMissionCond.OF_UNIT, c.def_idx, c.tag_mask, c.area) > 0:
			latch[c.ref] = 1
		return
	for ch: DefMissionCond in c.children:
		_latch_walk(world, ch)


func _run_trigger(world: SimWorld, ti: int) -> void:
	if trig_enabled[ti] == 0:
		return
	var t: DefMissionTrigger = def.triggers[ti]
	var v: bool = SimMissionConds.eval(self, world, t.when)
	var fire: bool = v
	if t.edge:
		fire = v and trig_last_val[ti] == 0
		trig_last_val[ti] = 1 if v else 0
	if fire and t.cooldown > 0 and trig_last_tick[ti] >= 0 and world.tick - trig_last_tick[ti] < t.cooldown:
		fire = false
	if not fire:
		return
	trig_fired[ti] += 1
	trig_last_tick[ti] = world.tick
	if t.once:
		trig_enabled[ti] = 0
	world.emit(SimEvent.MISSION_TRIGGER, 0, 0, ti, trig_fired[ti])
	for a: DefMissionAction in t.then:
		if world.match_state != SimWorld.MATCH_RUNNING:
			return
		SimMissionActions.run(self, world, a)


# ---------------------------------------------------------------------------------------------------- state changes
func set_objective(world: SimWorld, idx: int, state: int) -> void:
	if idx < 0 or idx >= obj_state.size() or obj_state[idx] == state:
		return
	var prev: int = obj_state[idx]
	obj_state[idx] = state
	world.emit(SimEvent.MISSION_OBJECTIVE, 0, 0, idx, state, def.objectives[idx].kind, prev)


## ticks_override > 0 replaces the duration (and is kept for restarts).
func start_timer(world: SimWorld, idx: int, ticks_override: int) -> void:
	if idx < 0 or idx >= timer_state.size():
		return
	if ticks_override > 0:
		timer_len[idx] = ticks_override
	timer_state[idx] = SimMissionConst.TM_RUNNING
	timer_end[idx] = world.tick + timer_len[idx]
	world.emit(SimEvent.MISSION_TIMER, 0, 0, idx, 0, timer_len[idx])


func stop_timer(world: SimWorld, idx: int) -> void:
	if idx < 0 or idx >= timer_state.size() or timer_state[idx] != SimMissionConst.TM_RUNNING:
		return
	timer_state[idx] = SimMissionConst.TM_STOPPED
	world.emit(SimEvent.MISSION_TIMER, 0, 0, idx, 1, timer_len[idx])


## The mission's end: win(pid) / lose(pid). Idempotent.
func finish(world: SimWorld, pid: int, won: bool) -> void:
	if result != SimMissionConst.RES_NONE or world.match_state != SimWorld.MATCH_RUNNING:
		return
	result = SimMissionConst.RES_WIN if won else SimMissionConst.RES_LOSE
	result_pid = pid
	result_tick = world.tick
	var team: int = world.team_of(pid)
	world.emit(SimEvent.MISSION_RESULT, 0, 0, pid, result, team)
	if won:
		world.end_match(team, SimWorld.EndReason.MISSION_WIN)
		return
	world.eliminate(pid, SimPlayer.Elim.SCRIPT)
	var winner: int = -1
	for p: SimPlayer in world.players:
		if p.controller != SimPlayer.Controller.NONE and p.eliminated == 0 and p.team != team:
			winner = p.team
			break
	world.end_match(winner, SimWorld.EndReason.MISSION_LOSE)


# ---------------------------------------------------------------------------------------------------- hash
## Appends every authoritative int (fixed order). Part of `sys.cleanup`.
func hash_into(buf: PackedInt32Array) -> void:
	buf.append(0x4D495331)  # "MIS1": a mission is present
	buf.append(passes)
	buf.append(result)
	buf.append(result_pid)
	buf.append(result_tick)
	for arr: PackedInt32Array in [obj_state, trig_enabled, trig_fired, trig_last_tick, trig_last_val, timer_state, timer_end, timer_len,
			placed_id, placed_owner0, wave_spawned, latch, area_data, ai_active, ai_aggr]:
		buf.append(arr.size())
		buf.append_array(arr)
	for ids: PackedInt32Array in wave_ids:
		buf.append(ids.size())
		buf.append_array(ids)
