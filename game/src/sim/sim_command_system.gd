class_name SimCommandSystem
extends SimSystem
## Stage 1 (sim_core 3.5 / 5.5): canonical ordering, decode, validation, executor registry and the built-in
## executors (order ops, STOP, SCATTER, SCUTTLE, RESIGN, DEBUG). Every other op needs an executor registered by
## its owning domain (`register_executor`); without one it returns Err.NOT_AVAILABLE.

var _executors: Array[Callable] = []  ## by op 0..255; an invalid Callable = the built-in (or none)


func _init() -> void:
	stage_no = 1
	_executors.resize(256)


## One executor per op; a later registration replaces the earlier one (that is how a domain overrides a
## built-in). `c`: func(world: SimWorld, cmd: SimCommand) -> int (SimCommand.Err.OK or a reason).
func register_executor(op: int, c: Callable) -> void:
	if op < 0 or op > 255:
		Log.error("commands", "register_executor: op %d out of range" % op)
		return
	_executors[op] = c


## Stage 1 body: sort by (pid, submission index), decode, validate, execute; counts and reports rejections.
func update(world: SimWorld) -> void:
	var pending: Array[SimCommand] = world.take_pending()
	var n: int = pending.size()
	if n == 0:
		return
	var order: Array[SimCommand] = pending
	if n > 1:
		# total order: key = (pid, _ord) with _ord unique, so equal keys cannot occur
		var keys: PackedInt64Array = PackedInt64Array()
		keys.resize(n)
		for i: int in n:
			keys[i] = ((clampi(pending[i].pid, -1, 1 << 20) + 1) << 32) | i
		keys.sort()
		order = []
		for i: int in n:
			order.append(pending[keys[i] & 0xFFFFFFFF])
	for c: SimCommand in order:
		var err: int = SimCommandCodec.decode(c)
		if err == SimCommand.Err.OK:
			err = execute(world, c)
		var real: bool = c.pid >= 0 and c.pid < world.players.size() and world.players[c.pid].controller != SimPlayer.Controller.NONE
		if not real:
			continue
		var p: SimPlayer = world.players[c.pid]
		if err == SimCommand.Err.OK:
			p.st_cmds += 1
		else:
			p.st_rejected += 1
			var tgt: int = c.target if c.target != 0 else c.def
			world.events.emit_throttled(SimEvent.CMD_REJECTED, c.pid, SimConfig.REJECT_GAP, 0, 0, c.pid, c.op, err, c.detail, tgt)


## Validation + dispatch (also used by tests). `c` must be decoded (SimCommand.from_ints does that).
func execute(world: SimWorld, c: SimCommand) -> int:
	var op: int = c.op
	if c.pid < 0 or c.pid >= world.players.size() or world.players[c.pid].controller == SimPlayer.Controller.NONE:
		return SimCommand.Err.BAD_PLAYER
	var meta: int = SimCmd.meta_of(op)
	if op != SimCmd.RESIGN:
		if world.players[c.pid].eliminated != 0:
			return SimCommand.Err.ELIMINATED
		if world.match_state != SimWorld.MATCH_RUNNING:
			return SimCommand.Err.MATCH_ENDED
		if world.mission != null and world.mission.blocks_commands(world, c.pid):
			return SimCommand.Err.NOT_ALLOWED  # a scripted AI that the mission has not switched on yet
		if (meta & SimCmd.M_POS) != 0 and (c.x < 0 or c.x >= world.map.w * SimConfig.CELL or c.y < 0 or c.y >= world.map.h * SimConfig.CELL):
			return SimCommand.Err.BAD_FIELD
		if (meta & SimCmd.M_CELL) != 0 and (c.x < 0 or c.x >= world.map.w or c.y < 0 or c.y >= world.map.h):
			return SimCommand.Err.BAD_FIELD
		if (meta & SimCmd.M_QUEUE) != 0 and (c.mode < 0 or c.mode > 2):
			return SimCommand.Err.BAD_FIELD
		if (meta & SimCmd.M_ANGLE) != 0 and (c.angle < 0 or c.angle >= Fp.TURN):
			return SimCommand.Err.BAD_FIELD
		if (meta & SimCmd.M_IDS) != 0:
			_resolve_actors(world, c, meta)
			if c.actors.is_empty():
				return SimCommand.Err.NO_ACTORS
	var ex: Callable = _executors[op] if op >= 0 and op < 256 else Callable()
	if ex.is_valid():
		return ex.call(world, c)
	return _builtin(world, c)


## Existing, not gone / inside, owned by the issuer and of the right kind; the rest is silently dropped.
func _resolve_actors(world: SimWorld, c: SimCommand, meta: int) -> void:
	c.actors = []
	for id: int in c.ids:
		var e: SimEntity = world.get_entity(id)
		# FIX (abilities AB2): the claiming team may evacuate a civilian garrison (a neutral) with UNLOAD
		var claimed: bool = c.op == SimCmd.UNLOAD and e != null and e.kind == SimEntity.Kind.NEUTRAL and e.cargo != null \
			and e.cargo.claim_team >= 0 and e.cargo.claim_team == world.team_of(c.pid)
		if e == null or (e.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or (e.owner != c.pid and not claimed):
			continue
		if (meta & SimCmd.M_UNITS) != 0 and e.kind != SimEntity.Kind.UNIT:
			continue
		if (meta & SimCmd.M_STRUCTS) != 0 and e.kind != SimEntity.Kind.STRUCTURE:
			continue
		if (meta & SimCmd.M_ANY) != 0 and e.kind != SimEntity.Kind.UNIT and e.kind != SimEntity.Kind.STRUCTURE and not claimed:
			continue
		c.actors.append(e)


# ---- built-in executors ----
func _builtin(world: SimWorld, c: SimCommand) -> int:
	match c.op:
		SimCmd.MOVE:
			return _order(world, c, SimOrder.T_MOVE, _move_flags(c.flags))
		SimCmd.FOLLOW:
			return _order(world, c, SimOrder.T_FOLLOW, 0)
		SimCmd.PATROL:
			return _order(world, c, SimOrder.T_PATROL, SimOrder.OF_CYCLIC | _move_flags(c.flags))
		SimCmd.LOAD:
			return _order(world, c, SimOrder.T_LOAD, 0)
		SimCmd.GARRISON:
			return _order(world, c, SimOrder.T_GARRISON, 0)
		SimCmd.CAPTURE:
			return _order(world, c, SimOrder.T_CAPTURE, 0)
		SimCmd.REPAIR:
			return _order(world, c, SimOrder.T_REPAIR, 0)
		SimCmd.SALVAGE:
			return _order(world, c, SimOrder.T_SALVAGE, 0)
		SimCmd.HARVEST:
			return _order(world, c, SimOrder.T_HARVEST, 0)
		SimCmd.RETURN_CARGO:
			return _order(world, c, SimOrder.T_RETURN_CARGO, 0)
		SimCmd.ATTACK:
			if (c.flags & ~1) != 0:
				return SimCommand.Err.BAD_FIELD
			return _order(world, c, SimOrder.T_ATTACK, SimOrder.OF_FORCED if (c.flags & 1) != 0 else 0)
		SimCmd.ATTACK_MOVE:
			return _order(world, c, SimOrder.T_ATTACK_MOVE, _move_flags(c.flags))
		SimCmd.GUARD:
			return _order(world, c, SimOrder.T_GUARD, 0)
		SimCmd.HOLD:
			return _order(world, c, SimOrder.T_HOLD, 0)
		SimCmd.FORCE_FIRE:
			return _order(world, c, SimOrder.T_FORCE_FIRE, 0)
		SimCmd.RETURN_TO_BASE:
			return _order(world, c, SimOrder.T_RETURN_BASE, 0)
		SimCmd.STOP:
			for e: SimEntity in c.actors:
				world.orders.clear(world, e, SimOrder.END_CANCELLED)
			return SimCommand.Err.OK
		SimCmd.SCATTER:
			return _scatter(world, c)
		SimCmd.SCUTTLE:
			for e: SimEntity in c.actors:
				world.kill(e, SimWorld.Cause.SCUTTLE, 0, c.pid)
			return SimCommand.Err.OK
		SimCmd.RESIGN:
			world.eliminate(c.pid, SimPlayer.Elim.RESIGN + clampi(c.mode, 0, 4))
			return SimCommand.Err.OK
		SimCmd.DEBUG:
			return _debug(world, c)
	return SimCommand.Err.NOT_AVAILABLE


## MOVE / ATTACK_MOVE / PATROL command flags: b0 -> no formation, b1 -> speed match, b2 -> reverse ok.
static func _move_flags(f: int) -> int:
	var o: int = 0
	if (f & 1) != 0:
		o |= SimOrder.OF_NO_FORMATION
	if (f & 2) != 0:
		o |= SimOrder.OF_SPEED_MATCH
	if (f & 4) != 0:
		o |= SimOrder.OF_REVERSE_OK
	return o


## A fresh SimOrder per actor (ascending id); OK if at least one actor accepted, else the last error.
func _order(world: SimWorld, c: SimCommand, type: int, oflags: int) -> int:
	if type == SimOrder.T_MOVE or type == SimOrder.T_ATTACK_MOVE or type == SimOrder.T_PATROL:
		if (c.flags & ~7) != 0:
			return SimCommand.Err.BAD_FIELD
	var arg: int = c.count if type == SimOrder.T_FORCE_FIRE else 0
	var ok: bool = false
	var last: int = SimCommand.Err.NO_ACTORS
	for e: SimEntity in c.actors:
		var o: SimOrder = SimOrder.make(type, c.target, c.x, c.y, arg, 0, oflags)
		var err: int = world.orders.issue(world, e, o, c.mode)
		if err == SimCommand.Err.OK:
			ok = true
		else:
			last = err
	return SimCommand.Err.OK if ok else last


## 3 cells max radius; two rng draws per actor (x then y) in ascending id order, whatever the outcome.
func _scatter(world: SimWorld, c: SimCommand) -> int:
	var maxx: int = world.map.w * SimConfig.CELL - 1
	var maxy: int = world.map.h * SimConfig.CELL - 1
	var ok: bool = false
	var last: int = SimCommand.Err.NO_ACTORS
	for e: SimEntity in c.actors:
		var nx: int = clampi(e.x + world.rng.range_i(-3072, 3072), 0, maxx)
		var ny: int = clampi(e.y + world.rng.range_i(-3072, 3072), 0, maxy)
		var o: SimOrder = SimOrder.make(SimOrder.T_MOVE, 0, nx, ny)
		var err: int = world.orders.issue(world, e, o, SimOrder.QM_REPLACE)
		if err == SimCommand.Err.OK:
			ok = true
		else:
			last = err
	return SimCommand.Err.OK if ok else last


## DEBUG: 1 = credits, 2 = spawn `count` units of `def` at (x, y), 3 = kill `target`, >= 4 = the stages' on_debug.
func _debug(world: SimWorld, c: SimCommand) -> int:
	if world.rules.allow_debug == 0:
		return SimCommand.Err.NOT_ALLOWED
	match c.mode:
		1:
			world.add_credits(c.pid, c.count, SimEvent.CASH_SCRIPT)
			return SimCommand.Err.OK
		2:
			if c.count < 1 or c.count > 64 or not world.defs.has_def(SimEntity.Kind.UNIT, c.def):
				return SimCommand.Err.BAD_FIELD
			for _i: int in c.count:
				world.spawn_unit(c.def, c.pid, c.x, c.y, 0, 0, 0, 0, SimEvent.SPAWN_SCRIPT)
			return SimCommand.Err.OK
		3:
			var t: SimEntity = world.get_entity(c.target)
			if t == null or (t.flags & SimFlags.F_GONE) != 0:
				return SimCommand.Err.NO_TARGET
			world.kill(t, SimWorld.Cause.SCRIPT, 0, c.pid)
			return SimCommand.Err.OK
	if c.mode >= 4:
		for s: SimSystem in world.stages:
			var r: int = s.on_debug(world, c.pid, c.mode, c.target, c.def, c.count, c.x, c.y)
			if r != -1:
				return r
	return SimCommand.Err.BAD_FIELD
