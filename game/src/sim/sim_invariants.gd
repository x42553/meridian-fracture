class_name SimInvariants
extends RefCounted
## Structural invariant checker (sim_core 10.2, basic version): run at step boundaries by tests and by
## `opts.invariants_every`. Returns one message per violation ("INV-n ..."), empty = healthy. Checks INV-1, 2, 3,
## 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 17, and INV-4 / INV-16 (the map's structure grid agrees with the structure and
## neutral entities: every occupant is a live entity that holds its footprint, every footprint cell carries its id).


static func check(world: SimWorld) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var live: int = 0
	var last_id: int = 0
	var unit_n: int = 0
	var struct_n: int = 0
	var counts_units: PackedInt32Array = PackedInt32Array()
	var counts_structs: PackedInt32Array = PackedInt32Array()
	var counts_rebuild: PackedInt32Array = PackedInt32Array()
	counts_units.resize(world.players.size())
	counts_structs.resize(world.players.size())
	counts_rebuild.resize(world.players.size())
	var moved: Dictionary = {}
	for id: int in world._moved:
		moved[id] = true
	var max_x: int = world.map.w * SimConfig.CELL - 1
	var max_y: int = world.map.h * SimConfig.CELL - 1
	for e: SimEntity in world.entities:
		if e.id <= last_id:
			out.append("INV-1 entities not strictly ascending at id %d" % e.id)
		last_id = e.id
		if world.by_id[e.id] != e:
			out.append("INV-1 by_id[%d] is not the listed entity" % e.id)
		if e._gone:
			out.append("INV-11 gone entity %d is still listed" % e.id)
			continue
		live += 1
		if e.id >= world.next_id:
			out.append("INV-12 id %d >= next_id" % e.id)
		var gone: bool = (e.flags & SimFlags.F_GONE) != 0
		if (e.flags & SimFlags.F_DEAD) != 0:
			if e.hp != 0:
				out.append("INV-7 dead entity %d has hp %d" % [e.id, e.hp])
			if (e.flags & SimFlags.F_REMOVING) == 0 and (e.expire_tick == 0 or e.expire_tick < world.tick):
				out.append("INV-17 zombie: dead entity %d is neither queued nor scheduled" % e.id)
		elif e.hp_max > 0 and (e.hp < 1 or e.hp > e.hp_max):
			out.append("INV-7 entity %d hp %d outside 1..%d" % [e.id, e.hp, e.hp_max])
		if e.x < 0 or e.y < 0 or e.x > max_x or e.y > max_y:
			out.append("INV-8 entity %d outside the map" % e.id)
		var inside: bool = (e.flags & SimFlags.F_INSIDE) != 0
		if inside != (e.container_id >= 0):
			out.append("INV-13 entity %d: F_INSIDE and container_id disagree" % e.id)
		if inside == world.spatial.contains(e.id):
			out.append("INV-13/6 entity %d: inside=%s but in hash=%s" % [e.id, str(inside), str(world.spatial.contains(e.id))])
		if not inside and world.spatial.contains(e.id):
			if world.spatial.x_of(e.id) != e.x or world.spatial.y_of(e.id) != e.y or world.spatial.tag_of(e.id) != SimTag.of(e):
				out.append("INV-6 entity %d: hash position / tag stale" % e.id)
		if e.team != world.team_of(e.owner):
			out.append("INV-14 entity %d: cached team %d != %d" % [e.id, e.team, world.team_of(e.owner)])
		if e.kind != SimEntity.Kind.UNIT and not e.orders.is_empty():
			out.append("INV-9 non-unit %d has orders" % e.id)
		if e.orders.size() > SimConfig.MAX_ORDERS:
			out.append("INV-9 entity %d order queue too long" % e.id)
		for o: SimOrder in e.orders:
			if not world.orders.has_handler(o.type):
				out.append("INV-9 entity %d has an order type %d without a handler" % [e.id, o.type])
		if moved.has(e.id):
			if e.vx != e.x - e.prev_x or e.vy != e.y - e.prev_y:
				out.append("INV-15 mover %d: v != pos - prev" % e.id)
		elif e.prev_x != e.x or e.prev_y != e.y or e.vx != 0 or e.vy != 0:
			out.append("INV-15 entity %d did not move but prev/v differ" % e.id)
		if not gone and e.owner >= 0 and e.owner < world.players.size():
			if e.kind == SimEntity.Kind.UNIT:
				counts_units[e.owner] += e._cap
				if e._asset and world.defs.is_rebuilder(e.kind, e.def_idx):
					counts_rebuild[e.owner] += 1
			elif e.kind == SimEntity.Kind.STRUCTURE and e._asset:
				counts_structs[e.owner] += 1
		if e.kind == SimEntity.Kind.UNIT:
			unit_n += 1
		elif e.kind == SimEntity.Kind.STRUCTURE:
			struct_n += 1
	if live != world._live_count:
		out.append("INV-10 live_count %d != %d listed" % [world._live_count, live])
	if world.units.size() != unit_n or world.structures.size() != struct_n:
		out.append("INV-2 kind lists disagree with the entity list")
	for p: SimPlayer in world.players:
		if p.unit_count != counts_units[p.pid] or p.struct_count != counts_structs[p.pid] or p.rebuilders != counts_rebuild[p.pid]:
			out.append("INV-5 counters of player %d differ from a recount" % p.pid)
		var prev: int = 0
		for e: SimEntity in world.units_of(p.pid):
			if e.id <= prev or e.owner != p.pid:
				out.append("INV-3 units_of(%d) not ascending / wrong owner at %d" % [p.pid, e.id])
			prev = e.id
		prev = 0
		for e: SimEntity in world.structures_of(p.pid):
			if e.id <= prev or e.owner != p.pid:
				out.append("INV-3 structures_of(%d) not ascending / wrong owner at %d" % [p.pid, e.id])
			prev = e.id
	_check_occupancy(world, out)
	if not world._dead.is_empty() or not world._remove_q.is_empty() or not world._spawn_queue.is_empty():
		out.append("INV-11 transient queues are not empty at a step boundary")
	if world.abilities != null and world.abilities.has_method("invariants"):  # containers and aura registries (abilities AB2)
		for msg: String in world.abilities.invariants(world):
			out.append("INV-A " + msg)
	return out


## INV-4 / INV-16: `map.occ` versus the entities that hold a footprint (`_occ`).
static func _check_occupancy(world: SimWorld, out: PackedStringArray) -> void:
	var occ: PackedInt32Array = world.map.occ
	var per_id: Dictionary = {}
	for i: int in occ.size():
		var id: int = occ[i]
		if id <= 0:
			continue
		var e: SimEntity = world.get_entity(id)
		if e == null or not e._occ or (e.kind != SimEntity.Kind.STRUCTURE and e.kind != SimEntity.Kind.NEUTRAL):
			out.append("INV-16 cell %d is occupied by %d, which holds no footprint" % [i, id])
			continue
		per_id[id] = int(per_id.get(id, 0)) + 1
	var cells: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in world.entities:
		if not e._occ:
			continue
		var fp: MapFootprint = world.map.footprint_of(e.kind, e.def_idx)
		if fp == null:
			out.append("INV-4 entity %d is flagged as occupying but has no footprint" % e.id)
			continue
		var orient: int = (e.facing >> 10) & 3 if fp.rotatable else 0
		var sz: int = fp.size_oriented(orient)
		var cx: int = (e.x - (sz >> 8) * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
		var cy: int = (e.y - (sz & 255) * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
		var n: int = fp.cells_at(orient, cx, cy, cells, world.map.w, world.map.h)
		if n != int(per_id.get(e.id, 0)):
			out.append("INV-4 entity %d holds %d footprint cells on the map, expected %d" % [e.id, int(per_id.get(e.id, 0)), n])
