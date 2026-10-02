class_name SimCleanupSystem
extends SimSystem
## Stage 11 (sim_core 5.4 / 5.9): defeat cascade, every stage's cleanup hook, expiry, the deaths / removals rounds
## (id-ordered batches, tether chains), list compaction, elimination by assets and the victory rule. It works on
## the world's kernel-private queues (`_dead*`, `_remove_q`), which only the kernel touches.

const MAX_ROUNDS: int = 16


func _init() -> void:
	stage_no = 11


func update(world: SimWorld) -> void:
	_defeat_cascade(world)
	for s: SimSystem in world.stages:
		s.cleanup(world)
	_expire_due(world)
	var guard: int = 0
	while guard < MAX_ROUNDS and (world._dead_done < world._dead.size() or world._remove_done < world._remove_q.size()):
		_process_deaths(world)
		_process_removals(world)
		guard += 1
	if world._dead_done == world._dead.size() and world._remove_done == world._remove_q.size():
		_reset_queues(world)
	world._flush_spawns()
	world._compact_lists()
	_evaluate_players(world)
	_evaluate_victory(world)
	if world.mission != null:
		world.mission.update(world)  # MIS1: triggers see the settled world; win / lose go through world.end_match


## Mission state (MIS1) is part of `sys.cleanup`; nothing is appended without a mission, so skirmish checksums are unchanged.
func hash_state(world: SimWorld, buf: PackedInt32Array) -> void:
	if world.mission != null:
		world.mission.hash_into(buf)


## Each eliminated (non-vacant) player loses up to DEFEAT_KILLS_PER_TICK living entities per tick: units first,
## then structures, ascending id (Cause.RESIGN).
func _defeat_cascade(world: SimWorld) -> void:
	for p: SimPlayer in world.players:
		if p.eliminated == 0 or p.controller == SimPlayer.Controller.NONE:
			continue
		var budget: int = SimConfig.DEFEAT_KILLS_PER_TICK
		for list: Array[SimEntity] in [world.units_of(p.pid), world.structures_of(p.pid)]:
			for e: SimEntity in list:
				if budget <= 0:
					break
				if (e.flags & SimFlags.F_GONE) != 0:
					continue
				world.kill(e, SimWorld.Cause.RESIGN, 0, -1)
				budget -= 1


## Entities whose expire_tick came due (id order): lingering corpses go, F_EXPIRE_KILLS die, the rest vanish.
func _expire_due(world: SimWorld) -> void:
	for e: SimEntity in world.entities:
		if e.expire_tick == 0 or world.tick < e.expire_tick or e._gone or (e.flags & SimFlags.F_REMOVING) != 0:
			continue
		if (e.flags & SimFlags.F_DEAD) != 0:
			world._queue_removal(e, SimEvent.REM_KILLED)
		elif (e.flags & SimFlags.F_EXPIRE_KILLS) != 0:
			world.kill(e, SimWorld.Cause.EXPIRE, 0, -1)
		else:
			world.remove_entity(e.id, SimEvent.REM_EXPIRED)


## Deaths batch: the unprocessed tail of _dead, ascending entity id.
func _process_deaths(world: SimWorld) -> void:
	var from: int = world._dead_done
	var to: int = world._dead.size()
	if to <= from:
		return
	_sort_dead_tail(world, from, to)
	world._dead_done = to
	for i: int in range(from, to):
		var e: SimEntity = world._dead[i]
		var cause: int = world._dead_cause[i]
		var killer_id: int = world._dead_killer[i]
		var killer_pid: int = world._dead_killer_pid[i]
		for s: SimSystem in world.stages:
			s.on_dying(world, e, cause, killer_id, killer_pid)
		_credit_stats(world, e, killer_pid)
		if e.expire_tick != 0 and e.expire_tick > world.tick:
			continue  # lingering corpse: a hook armed remove_deferred()
		if (e.flags & SimFlags.F_REMOVING) == 0:
			world._queue_removal(e, SimEvent.REM_KILLED)


## Removals batch: the unprocessed tail of _remove_q, ascending entity id.
func _process_removals(world: SimWorld) -> void:
	var from: int = world._remove_done
	var to: int = world._remove_q.size()
	if to <= from:
		return
	var keys: PackedInt64Array = PackedInt64Array()
	for i: int in range(from, to):
		keys.append((world._remove_q[i].id << 16) | (i - from))
	keys.sort()
	var batch: Array[SimEntity] = []
	var reasons: PackedInt32Array = PackedInt32Array()
	for k: int in keys:
		batch.append(world._remove_q[from + (k & 0xFFFF)])
		reasons.append(world._remove_reason[from + (k & 0xFFFF)])
	world._remove_done = to
	for i: int in batch.size():
		world._finalize_removal(batch[i], reasons[i])


## Sorts the tail [from, to) of the parallel _dead arrays by entity id (packed int64 key, total order).
func _sort_dead_tail(world: SimWorld, from: int, to: int) -> void:
	var keys: PackedInt64Array = PackedInt64Array()
	for i: int in range(from, to):
		keys.append((world._dead[i].id << 16) | (i - from))
	keys.sort()
	var ents: Array[SimEntity] = []
	var cause: PackedInt32Array = PackedInt32Array()
	var kid: PackedInt32Array = PackedInt32Array()
	var kpid: PackedInt32Array = PackedInt32Array()
	for k: int in keys:
		var src: int = from + (k & 0xFFFF)
		ents.append(world._dead[src])
		cause.append(world._dead_cause[src])
		kid.append(world._dead_killer[src])
		kpid.append(world._dead_killer_pid[src])
	for j: int in ents.size():
		world._dead[from + j] = ents[j]
		world._dead_cause[from + j] = cause[j]
		world._dead_killer[from + j] = kid[j]
		world._dead_killer_pid[from + j] = kpid[j]


## Kernel statistics: losses of the owner, kills of a killer of another owner.
func _credit_stats(world: SimWorld, e: SimEntity, killer_pid: int) -> void:
	var is_unit: bool = e.kind == SimEntity.Kind.UNIT
	if not is_unit and e.kind != SimEntity.Kind.STRUCTURE:
		return
	if e.owner >= 0 and e.owner < world.players.size():
		var p: SimPlayer = world.players[e.owner]
		if is_unit:
			p.st_units_lost += 1
		else:
			p.st_structs_lost += 1
	if killer_pid >= 0 and killer_pid < world.players.size() and killer_pid != e.owner:
		var k: SimPlayer = world.players[killer_pid]
		if is_unit:
			k.st_units_killed += 1
		else:
			k.st_structs_killed += 1


func _reset_queues(world: SimWorld) -> void:
	world._dead.clear()
	world._dead_cause.resize(0)
	world._dead_killer.resize(0)
	world._dead_killer_pid.resize(0)
	world._dead_done = 0
	world._remove_q.clear()
	world._remove_reason.resize(0)
	world._remove_done = 0


## Elimination by assets: no structure and no MCV-class unit (victory 0 = sandbox: rule off).
func _evaluate_players(world: SimWorld) -> void:
	if world.rules.victory == 0:
		return
	for p: SimPlayer in world.players:
		if p.controller == SimPlayer.Controller.NONE or p.eliminated != 0:
			continue
		if p.struct_count == 0 and p.rebuilders == 0:
			world.eliminate(p.pid, SimPlayer.Elim.NO_ASSETS)


## Team victory (sim_core 5.9): one team (or none) left -> ELIMINATION / DRAW; no human left -> NO_HUMANS.
func _evaluate_victory(world: SimWorld) -> void:
	if world.rules.victory == 0 or world._participants < 2 or world.match_state != SimWorld.MATCH_RUNNING:
		return
	var teams: int = 0
	var humans_left: int = 0
	for p: SimPlayer in world.players:
		if p.controller == SimPlayer.Controller.NONE or p.eliminated != 0:
			continue
		teams |= 1 << p.team
		if p.controller == SimPlayer.Controller.HUMAN:
			humans_left += 1
	var count: int = 0
	var last: int = -1
	for t: int in 16:
		if (teams >> t) & 1 != 0:
			count += 1
			last = t
	if count <= 1:
		world.end_match(last if count == 1 else -1, SimWorld.EndReason.ELIMINATION if count == 1 else SimWorld.EndReason.DRAW)
	elif world.rules.end_when_no_humans != 0 and world.humans_total > 0 and humans_left == 0:
		world.end_match(-1, SimWorld.EndReason.NO_HUMANS)
