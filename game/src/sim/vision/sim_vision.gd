class_name SimVision
extends RefCounted
## Static query facade over world.vision (abilities 3.4): the names combat, economy and the AI call.
## Team masks have one bit per team id (bit t = team t, 0..15).


static func can_see(world: SimWorld, pid: int, target: SimEntity) -> bool:
	return world.fog.entity_visible(pid, target)


## Visible now, or a remembered structure ghost.
static func is_known(world: SimWorld, pid: int, target: SimEntity) -> bool:
	if world.fog.entity_visible(pid, target):
		return true
	var vs: SimVisionSystem = world.vision
	return vs != null and target.kind == SimEntity.Kind.STRUCTURE and vs.has_ghost(vs.group_of(pid), target.id)


static func decoy_identified(world: SimWorld, pid: int, target: SimEntity) -> bool:
	return world.fog.decoy_identified(pid, target)


static func is_identified(world: SimWorld, pid: int, ent_id: int) -> bool:
	var e: SimEntity = world.get_entity(ent_id)
	return e != null and world.fog.decoy_identified(pid, e)


static func is_explored(world: SimWorld, pid: int, cx: int, cy: int) -> bool:
	return world.fog.cell_explored(pid, cx, cy)


static func is_visible(world: SimWorld, pid: int, cx: int, cy: int) -> bool:
	return world.fog.cell_visible(pid, cx, cy)


## Temporary reveal for every group whose team bit is set in team_mask. shape SHAPE_DISC (x, y, radius) or
## SHAPE_CAPSULE (segment (x, y)-(x2, y2), half-width radius). Returns the handle, -1 when the table is full.
static func add_reveal(world: SimWorld, team_mask: int, shape: int, x: int, y: int, x2: int, y2: int, radius: int, until_tick: int, detect: bool, bind_ent: int) -> int:
	var vs: SimVisionSystem = world.vision
	if vs == null:
		return -1
	var gmask: int = 0
	for g: int in vs.ngroups:
		if vs.group_team[g] >= 0 and ((team_mask >> vs.group_team[g]) & 1) != 0:
			gmask |= 1 << g
	return vs.add_temp_mask(gmask, shape, x, y, x2, y2, radius, detect, until_tick, bind_ent)


static func remove_reveal(world: SimWorld, handle: int) -> void:
	if world.vision != null:
		world.vision.remove_temp_source(handle)


## Force-reveals a (camouflaged) entity until `until_tick` (Counterbattery Solution); the team mask is not per-team.
static func add_reveal_entity(world: SimWorld, _team_mask: int, ent_id: int, until_tick: int) -> void:
	var e: SimEntity = world.get_entity(ent_id)
	if e != null and world.vision != null:
		world.vision.force_reveal(world, e, until_tick)
