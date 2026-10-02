class_name AiOpLanding
extends AiOp
## Amphibious / transport assault (ai.md 5.10.2). Used when the target cannot be reached over land (`needs_water`), or by a
## TRANSPORT_ASSAULT roster when the amphibious route is at least 25 % shorter than the land route. Land maps never see it.
##  FORMING  (ASSEMBLE): transports and cargo gather at the assembly point (a shore cell near my base connected to the landing zone);
##  STAGING  (LOAD):     cargo `load`s into the transports by capacity (Landing Transport 4 squads or 2 vehicles, APCs 2, Okapi 3,
##                       Leviathan 4), 700 ticks at most;
##  ADVANCING (CROSS):   transports and swimmers `move` to the LZ (amphibious route), the naval op escorts (brain.landing_watch);
##  ENGAGING (UNLOAD):   `unload` at the LZ;
##  CLEANUP  (LAND):     the landed force becomes a normal AiOpAttack that starts in ADVANCING (no staging); the transports go home.
## LZ = passable land cell adjacent to water within 20 cells of the target, in the target's land region, minimizing the threat map
## in 12 cells, the defenders that cover it and the distance to the target.
## `consider` is called by the attack planner right before it creates a normal wave: 0 = not applicable, 1 = a landing op was
## launched, 2 = a landing is needed but cannot be prepared yet (docks / transports are requested and the wave is held).

const LOAD_TICKS: int = 700
const CROSS_TICKS: int = 1800
const UNLOAD_TICKS: int = 300
const ASSEMBLE_TICKS: int = 900
const LZ_RADIUS_C: int = 20
const MIN_CARGO: int = 3
const SHORTER_PCT: int = 75

var wave_tgt: Dictionary = {}
var wave_ratio: int = 256
var lz_x: int = 0
var lz_y: int = 0
var asm_x: int = 0
var asm_y: int = 0
var transports: PackedInt32Array = PackedInt32Array()
var cargo: PackedInt32Array = PackedInt32Array()
var swimmers: PackedInt32Array = PackedInt32Array()
var loaded_n: int = 0
var seen_mask: int = 0  ## bit per OpState the op has been in (statistics / tests)
var landed_n: int = 0
var mandatory: bool = false
var _plan: Dictionary = {}  ## transport eid -> PackedInt32Array cargo eids
var _last_cmd: int = AiTypes.NEVER
var _unloaded_cmd: bool = false


# -------------------------------------------------------------------------------------------------- planner entry
static func consider(ctx: AiContext, b: AiBrain, budget: AiBudget, force: PackedInt32Array, tgt: Dictionary, ratio_q8: int) -> int:
	if ctx.tick < b.landing_block_until or not budget.spend(10):
		return 0
	var route: AiRouteGraph = ctx.kb.route
	var hx: int = ctx.kb.sites.home_x
	var hy: int = ctx.kb.sites.home_y
	var tx: int = int(tgt["x"])
	var ty: int = int(tgt["y"])
	var need_water: bool = not route.connected(hx, hy, tx, ty, AiTypes.MoveClass.TRACKED)
	var assault: bool = ctx.pers.has_flag(AiTypes.doctrine_bit("TRANSPORT_ASSAULT")) or ctx.pers.attack_style == AiTypes.Style.LANDING
	if not need_water and not assault:
		return 0
	if not need_water:
		# a water route must beat the land route by 25 %
		var land: PackedInt32Array = PackedInt32Array()
		var wet: PackedInt32Array = PackedInt32Array()
		var nl: int = route.route(hx, hy, tx, ty, AiTypes.MoveClass.TRACKED, route.threat_weight_q8, land)
		var nw: int = route.route(hx, hy, tx, ty, AiTypes.MoveClass.AMPHIBIOUS, route.threat_weight_q8, wet)
		budget.spend(30)
		if nl == 0 or nw == 0 or route.route_cells(wet) * 100 > route.route_cells(land) * SHORTER_PCT:
			b.landing_block_until = ctx.tick + 1200
			return 0
	# the force: cargo (does not swim), swimmers (amphibious combat units), transports in the force
	var t: AiEntityTable = ctx.kb.own
	var cargo_l: PackedInt32Array = PackedInt32Array()
	var swim_l: PackedInt32Array = PackedInt32Array()
	var trans_l: PackedInt32Array = PackedInt32Array()
	for eid: int in force:
		var r: int = t.row(eid)
		if r < 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p == null or AiForce.is_air(ctx, t.def[r]) or AiForce.is_sea(ctx, t.def[r]):
			continue
		if (t.role_mask[r] & (1 << AiTypes.R_AMPH_TRANSPORT)) != 0 and p.transport_cap > 0:
			trans_l.append(eid)
		elif (p.tag_mask & DefEnums.UT_AMPHIBIOUS) != 0 or p.move_class == AiTypes.MoveClass.AMPHIBIOUS:
			swim_l.append(eid)
		else:
			cargo_l.append(eid)
	for r2: int in t.count:
		if t.kind[r2] == AiTypes.KIND_UNIT and (t.role_mask[r2] & (1 << AiTypes.R_LANDING_TRANSPORT)) != 0 and t.squad[r2] < 0 \
				and (t.flags[r2] & AiTypes.EF_LOADED) == 0:
			trans_l.append(t.eid[r2])
	if need_water and cargo_l.is_empty() and trans_l.is_empty() and not swim_l.is_empty():
		return 0  # everybody swims: a normal wave takes the amphibious route (AiOpAttack.route_class)
	if trans_l.is_empty() or cargo_l.size() < MIN_CARGO:
		if need_water:
			_request_transports(ctx, b)
			return 2
		b.landing_block_until = ctx.tick + 900
		return 0
	var lz: PackedInt32Array = find_lz(ctx, tx, ty, budget)
	if lz.is_empty():
		b.landing_block_until = ctx.tick + 900
		return 2 if need_water else 0
	var op: AiOpLanding = AiOpLanding.new()
	op.mandatory = need_water
	op.wave_tgt = tgt
	op.wave_ratio = ratio_q8
	op.tx = tx
	op.ty = ty
	op.lz_x = lz[0]
	op.lz_y = lz[1]
	op.transports = trans_l
	op.cargo = cargo_l
	op.swimmers = swim_l
	if b.add_op(ctx, op):
		b.bump("landing_ops")
		ctx.telemetry.emit(AiTypes.Tele.LANDING_LAUNCHED, cargo_l.size(), trans_l.size(), ctx.tick)
		return 1
	b.landing_block_until = ctx.tick + 600
	return 0


## A landing is needed but the roster cannot swim: a Dock and Landing Transports are wanted.
static func _request_transports(ctx: AiContext, b: AiBrain) -> void:
	var eco: AiEconomy = b.eco()
	var dock: int = ctx.res.structure_of_kind(AiTypes.StructKind.DOCK)
	if dock >= 0 and eco.struct_own[dock] + eco.struct_q[dock] == 0:
		var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, dock, -1, 1, AiEconomy.P_TECH, AiTypes.WantOrigin.ARMY)
		w.deadline = ctx.tick + 1200
		b.add_want(w)
	var ld: int = ctx.res.first(AiTypes.R_LANDING_TRANSPORT)
	if ld >= 0 and eco.role_have(AiTypes.R_LANDING_TRANSPORT) < 2:
		var w2: AiWant = AiWant.make(AiTypes.WantKind.UNIT_ROLE, ld, AiTypes.R_LANDING_TRANSPORT, 2, AiEconomy.P_ARMY, AiTypes.WantOrigin.ARMY)
		w2.deadline = ctx.tick + 1200
		b.add_want(w2)
	b.bump("landing_requests")


## Landing zone for a target at (tx, ty): [x, y] in sub-cells or empty.
static func find_lz(ctx: AiContext, tx: int, ty: int, budget: AiBudget) -> PackedInt32Array:
	var v: AiWorldView = ctx.view
	var tc: PackedInt32Array = AiOpKit.snap(ctx, tx, ty, AiTypes.MoveClass.TRACKED, 6)
	var tcx: int = tc[0] >> Fp.CELL_SHIFT
	var tcy: int = tc[1] >> Fp.CELL_SHIFT
	var treg: int = v.region(tcx, tcy, AiTypes.MoveClass.TRACKED)
	var keys: PackedInt64Array = PackedInt64Array()
	var cells: PackedInt32Array = PackedInt32Array()
	budget.spend(20)
	for oy: int in range(-LZ_RADIUS_C, LZ_RADIUS_C + 1, 2):
		for ox: int in range(-LZ_RADIUS_C, LZ_RADIUS_C + 1, 2):
			var cx: int = tcx + ox
			var cy: int = tcy + oy
			if cx < 2 or cy < 2 or cx >= v.map_w() - 2 or cy >= v.map_h() - 2:
				continue
			if not v.passable(cx, cy, AiTypes.MoveClass.TRACKED) or v.region(cx, cy, AiTypes.MoveClass.TRACKED) != treg:
				continue
			if not (v.is_water(cx + 2, cy) or v.is_water(cx - 2, cy) or v.is_water(cx, cy + 2) or v.is_water(cx, cy - 2)):
				continue
			var x: int = cx * Fp.CELL + Fp.CELL / 2
			var y: int = cy * Fp.CELL + Fp.CELL / 2
			var s: int = ctx.kb.threat_circle(x, y, 12 * Fp.CELL) / 16 + 4 * AiForce.cells(x, y, tx, ty)
			keys.append((mini(s, 0x3FFFFFF) << 24) | cells.size() / 2)
			cells.append(x)
			cells.append(y)
	if keys.is_empty():
		return PackedInt32Array()
	keys.sort()
	# the best twelve are checked against the defenders that cover them
	var best: int = -1
	var best_s: int = 1 << 60
	for k: int in mini(12, keys.size()):
		var idx: int = int(keys[k] & 0xFFFFFF)
		var x2: int = cells[2 * idx]
		var y2: int = cells[2 * idx + 1]
		var dg: AiStrengthGroup = AiForce.enemy_group(ctx, x2, y2, 12 * Fp.CELL, 200)
		var s2: int = int(keys[k] >> 24) * 16 + dg.value / 4
		if s2 < best_s:
			best_s = s2
			best = idx
	budget.spend(12)
	return PackedInt32Array([cells[2 * best], cells[2 * best + 1]])


# ---------------------------------------------------------------------------------------------------------- op
func start(ctx: AiContext) -> bool:
	type = AiTypes.OpType.LANDING
	priority = 60
	var b: AiBrain = ctx.brain as AiBrain
	var sm: AiSquadManager = b.squads()
	var sq: AiSquad = sm.create(AiTypes.SquadKind.TRANSPORT, id)
	sq.prio = priority
	squads.append(sq.id)
	var all: PackedInt32Array = PackedInt32Array()
	all.append_array(transports)
	all.append_array(cargo)
	all.append_array(swimmers)
	if b.assign_units(ctx, sq, all) == 0:
		return false
	var t: AiEntityTable = ctx.kb.own
	# capacity: cargo beyond what the transports can carry stays behind
	var cap: int = 0
	for eid: int in transports:
		cap += _cap_of(ctx, t.def[t.row(eid)])
	if cargo.size() > cap:
		var extra: PackedInt32Array = cargo.slice(cap)
		cargo = cargo.slice(0, cap)
		b.assign_units(ctx, sm.reserve, extra)
	committed_value = 0
	for eid2: int in sq.units:
		committed_value += t.paid[t.row(eid2)]
	_assembly(ctx)
	period = 20
	timeout_tick = ctx.tick + 6000
	set_state(ctx, AiTypes.OpState.FORMING)
	return true


static func _cap_of(ctx: AiContext, def: int) -> int:
	var p: AiUnitProfile = ctx.unit_profile(def)
	return maxi(p.transport_cap, 1) if p != null else 2


## The assembly point: a shore cell near my base (or my Dock) that is connected to the LZ by an amphibious route.
func _assembly(ctx: AiContext) -> void:
	var v: AiWorldView = ctx.view
	var ax: int = ctx.kb.sites.home_x
	var ay: int = ctx.kb.sites.home_y
	var dock: int = ctx.res.structure_of_kind(AiTypes.StructKind.DOCK)
	var t: AiEntityTable = ctx.kb.own
	if dock >= 0:
		for r: int in t.count:
			if t.kind[r] == AiTypes.KIND_STRUCTURE and t.def[r] == dock:
				ax = t.x[r]
				ay = t.y[r]
				break
	elif not transports.is_empty():
		var tr: int = t.row(transports[0])
		if tr >= 0:
			ax = t.x[tr]
			ay = t.y[tr]
	var acx: int = ax >> Fp.CELL_SHIFT
	var acy: int = ay >> Fp.CELL_SHIFT
	var best: int = 1 << 30
	asm_x = ax
	asm_y = ay
	for ring: int in 26:
		for oy: int in range(-ring, ring + 1, 2):
			for ox: int in range(-ring, ring + 1, 2):
				if maxi(absi(ox), absi(oy)) != ring:
					continue
				var cx: int = acx + ox
				var cy: int = acy + oy
				if not v.passable(cx, cy, AiTypes.MoveClass.TRACKED):
					continue
				if not (v.is_water(cx + 2, cy) or v.is_water(cx - 2, cy) or v.is_water(cx, cy + 2) or v.is_water(cx, cy - 2)):
					continue
				var x: int = cx * Fp.CELL + Fp.CELL / 2
				var y: int = cy * Fp.CELL + Fp.CELL / 2
				if ring < best and ctx.kb.route.connected(x, y, lz_x, lz_y, AiTypes.MoveClass.AMPHIBIOUS):
					best = ring
					asm_x = x
					asm_y = y
		if best < 1 << 30:
			return


func release(ctx: AiContext) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b != null:
		for sid: int in squads:
			var sq: AiSquad = b.squads().squad(sid)
			if sq != null:
				AiOpKit.detach_support(ctx, sq)
	super.release(ctx)


func update(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	measure(ctx, budget)
	var t: AiEntityTable = ctx.kb.own
	var live_t: PackedInt32Array = _alive(t, transports)
	var live_c: PackedInt32Array = _alive(t, cargo)
	if live_t.is_empty() and state != AiTypes.OpState.CLEANUP:
		abort(ctx, AiTypes.Err.NO_EFFECT)
		return
	if live_c.is_empty() and swimmers.is_empty() and state != AiTypes.OpState.CLEANUP:
		abort(ctx, AiTypes.Err.NO_EFFECT)
		return
	transports = live_t
	cargo = live_c
	seen_mask |= 1 << state
	swimmers = _alive(t, swimmers)
	if state >= AiTypes.OpState.ADVANCING and state <= AiTypes.OpState.ENGAGING:
		b.landing_watch = PackedInt32Array([lz_x, lz_y, ctx.tick])
	match state:
		AiTypes.OpState.FORMING:
			_assemble(ctx)
		AiTypes.OpState.STAGING:
			_load(ctx)
		AiTypes.OpState.ADVANCING:
			_cross(ctx)
		AiTypes.OpState.ENGAGING:
			_unload(ctx)
		AiTypes.OpState.CLEANUP:
			_land(ctx, b)


func _alive(t: AiEntityTable, list: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for eid: int in list:
		if t.row(eid) >= 0:
			out.append(eid)
	return out


func _assemble(ctx: AiContext) -> void:
	var t: AiEntityTable = ctx.kb.own
	if ctx.tick - _last_cmd >= 100:
		_last_cmd = ctx.tick
		ctx.cmd.move(transports, asm_x, asm_y)
		ctx.cmd.move(cargo, asm_x, asm_y)
	var near: int = 0
	for eid: int in cargo:
		var r: int = t.row(eid)
		if AiForce.dist(t.x[r], t.y[r], asm_x, asm_y) <= 8 * Fp.CELL:
			near += 1
	var tn: int = 0
	for eid2: int in transports:
		var r2: int = t.row(eid2)
		if AiForce.dist(t.x[r2], t.y[r2], asm_x, asm_y) <= 8 * Fp.CELL:
			tn += 1
	var elapsed: int = ctx.tick - state_since
	if (near * 100 >= 80 * cargo.size() and tn == transports.size()) or elapsed >= ASSEMBLE_TICKS:
		_make_plan(ctx)
		set_state(ctx, AiTypes.OpState.STAGING)
		_last_cmd = AiTypes.NEVER


## Cargo to transports by capacity (an infantry squad takes one slot, a vehicle two).
func _make_plan(ctx: AiContext) -> void:
	_plan.clear()
	var t: AiEntityTable = ctx.kb.own
	var free: Dictionary = {}
	for tid: int in transports:
		free[tid] = _cap_of(ctx, t.def[t.row(tid)])
		_plan[tid] = PackedInt32Array()
	var order: PackedInt32Array = cargo.duplicate()
	order.sort()
	for eid: int in order:
		var r: int = t.row(eid)
		var need: int = 1 if ctx.unit_profile(t.def[r]).category == AiTypes.Cat.INFANTRY else 2
		for tid2: int in transports:
			if int(free[tid2]) >= need:
				free[tid2] = int(free[tid2]) - need
				var lst: PackedInt32Array = _plan[tid2]
				lst.append(eid)
				_plan[tid2] = lst
				break


func _load(ctx: AiContext) -> void:
	var t: AiEntityTable = ctx.kb.own
	if ctx.tick - _last_cmd >= 120:
		_last_cmd = ctx.tick
		for tid: int in _plan:
			var list: PackedInt32Array = _plan[tid]
			var todo: PackedInt32Array = PackedInt32Array()
			for eid: int in list:
				var r: int = t.row(eid)
				if r >= 0 and (t.flags[r] & AiTypes.EF_LOADED) == 0:
					todo.append(eid)
			if not todo.is_empty() and t.row(tid) >= 0:
				ctx.cmd.load_units(todo, tid)
	loaded_n = 0
	for eid2: int in cargo:
		var r2: int = t.row(eid2)
		if r2 >= 0 and (t.flags[r2] & AiTypes.EF_LOADED) != 0:
			loaded_n += 1
	var elapsed: int = ctx.tick - state_since
	if loaded_n >= cargo.size() or elapsed >= LOAD_TICKS:
		if loaded_n == 0:
			abort(ctx, AiTypes.Err.NO_EFFECT)
			return
		# what did not board stays behind
		var left: PackedInt32Array = PackedInt32Array()
		var keep: PackedInt32Array = PackedInt32Array()
		for eid3: int in cargo:
			var r3: int = t.row(eid3)
			if (t.flags[r3] & AiTypes.EF_LOADED) != 0:
				keep.append(eid3)
			else:
				left.append(eid3)
		cargo = keep
		if not left.is_empty():
			var bb: AiBrain = ctx.brain as AiBrain
			bb.assign_units(ctx, bb.squads().reserve, left)
		set_state(ctx, AiTypes.OpState.ADVANCING)
		_last_cmd = AiTypes.NEVER


func _cross(ctx: AiContext) -> void:
	var t: AiEntityTable = ctx.kb.own
	if ctx.tick - _last_cmd >= 100:
		_last_cmd = ctx.tick
		ctx.cmd.move(transports, lz_x, lz_y)
		if not swimmers.is_empty():
			ctx.cmd.move(swimmers, lz_x, lz_y)
	var arrived: int = 0
	for eid: int in transports:
		var r: int = t.row(eid)
		var d: int = AiForce.dist(t.x[r], t.y[r], lz_x, lz_y)
		if d <= 5 * Fp.CELL or (t.order[r] == AiTypes.OrderKind.IDLE and d <= 10 * Fp.CELL):
			arrived += 1
	if arrived * 2 >= transports.size() or ctx.tick - state_since >= CROSS_TICKS:
		set_state(ctx, AiTypes.OpState.ENGAGING)
		_unloaded_cmd = false
		_last_cmd = AiTypes.NEVER


func _unload(ctx: AiContext) -> void:
	var t: AiEntityTable = ctx.kb.own
	if not _unloaded_cmd or ctx.tick - _last_cmd >= 100:
		_unloaded_cmd = true
		_last_cmd = ctx.tick
		for tid: int in transports:
			ctx.cmd.unload(tid, lz_x, lz_y)
	var still: int = 0
	for eid: int in cargo:
		var r: int = t.row(eid)
		if r >= 0 and (t.flags[r] & AiTypes.EF_LOADED) != 0:
			still += 1
	if still == 0 or ctx.tick - state_since >= UNLOAD_TICKS:
		landed_n = cargo.size() - still
		set_state(ctx, AiTypes.OpState.CLEANUP)


func _land(ctx: AiContext, b: AiBrain) -> void:
	var t: AiEntityTable = ctx.kb.own
	var force: PackedInt32Array = PackedInt32Array()
	for eid: int in cargo:
		var r: int = t.row(eid)
		if r >= 0 and (t.flags[r] & AiTypes.EF_LOADED) == 0:
			force.append(eid)
	force.append_array(swimmers)
	if not force.is_empty():
		var wave: AiOpAttack = AiOpAttack.new()
		wave.setup_wave(AiTypes.SquadKind.MAIN, force, wave_tgt, wave_ratio)
		wave.start_state = AiTypes.OpState.ADVANCING
		if b.add_op(ctx, wave):
			b.bump("landing_landed", force.size())
			ctx.telemetry.emit(AiTypes.Tele.LANDING_DONE, force.size(), transports.size(), ctx.tick)
	# the transports go home (they are detached from the squad by release)
	if not transports.is_empty():
		ctx.cmd.move(transports, asm_x, asm_y)
	release(ctx)
	state = AiTypes.OpState.DONE


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([super.state_hash(), transports.size(), cargo.size(), loaded_n, landed_n, lz_x, lz_y]))
