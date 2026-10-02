class_name SimZoneDecoys
extends RefCounted
## DECOY zones (abilities 5.11.3): the zone spawns `count` harmless look-alikes of the template's decoy kind (a roster unit
## matching the template's tag mask, or a structure def) at positions scattered by hash(aux, k) inside `scatter_u`; they
## are summons (SM_DECOY: no weapons, F_DECOY so identification works, hp = the template's hp) that live exactly as long as
## the zone and die with it.


static func _hash(a: int, b: int) -> int:
	return Checksum.mix(Checksum.mix(Checksum.FNV_OFFSET, a), b) & 0x7FFFFFFF


## Roster unit that best represents the tag mask: lowest tier, then highest cost, then lowest index. -1 = none.
static func unit_for(world: SimWorld, pid: int, mask: int) -> int:
	if pid < 0 or pid >= world.players.size() or mask == 0:
		return -1
	var units: Array[DefUnit] = world.players[pid].roster.units
	var best: int = -1
	for i: int in units.size():
		var u: DefUnit = units[i]
		if u == null or u.cost <= 0 or u.id.begins_with("summon.") or (u.tags & mask) != mask:
			continue
		if best < 0:
			best = i
			continue
		var b: DefUnit = units[best]
		if u.tier < b.tier or (u.tier == b.tier and u.cost > b.cost):
			best = i
	return best


static func spawn(world: SimWorld, z: SimZone, d: DefZone, count: int, scatter_u: int, aux: int) -> void:
	var struct_idx: int = int(d.params.get("structure_idx", -1))
	var mask: int = int(d.params.get("unit_decoy_mask", 0))
	var def_idx: int = -1
	if struct_idx < 0:
		def_idx = unit_for(world, z.owner_pid, mask)
		if def_idx < 0:
			return
	var life: int = maxi(z.t_end - world.tick, 1)
	var flags: int = SimZoneConsts.SM_TEMPORARY | SimZoneConsts.SM_DECOY | SimZoneConsts.SM_NO_SALVAGE | SimZoneConsts.SM_NO_CAPTURE \
		| SimZoneConsts.SM_NO_REPAIR | SimZoneConsts.SM_NO_HARVEST | SimZoneConsts.SM_NO_CMD_FIELD | SimZoneConsts.SM_NO_VISION_GRANT \
		| SimZoneConsts.SM_UNCONTROLLABLE | SimZoneConsts.SM_NO_WRECK
	var n: int = mini(maxi(count, 1), SimZoneConsts.MAX_MEMBERS)
	for k: int in n:
		var px: int = z.x
		var py: int = z.y
		if scatter_u > 0 and n > 1:
			var ang: int = _hash(aux, k * 2) & 4095
			var rr: int = ((_hash(aux, k * 2 + 1) & 0xFFFF) * scatter_u) >> 16
			px += Fp.mul_q16(rr, Fp.cos(ang))
			py += Fp.mul_q16(rr, Fp.sin(ang))
		var eid: int = -1
		if struct_idx >= 0:
			var kf: int = SimFlags.F_DECOY | SimFlags.F_TEMPORARY | SimFlags.F_SUMMONED | SimFlags.F_NO_FOOTPRINT | SimFlags.F_NO_UNIT_CAP \
				| SimFlags.F_NO_SALVAGE | SimFlags.F_NO_CAPTURE | SimFlags.F_NO_REPAIR | SimFlags.F_NO_COLLISION
			var s: SimEntity = world.spawn_structure(struct_idx, z.owner_pid, px, py, 0, kf, 0, maxi(z.src_eid, 0), SimEvent.SPAWN_SUMMONED)
			if s != null:
				SimSummons.adopt(world, s, z.src_eid, flags, life, SimZoneConsts.SD_STATIC, 0, 0, 0)
				eid = s.id
		else:
			eid = SimSummons.spawn(world, def_idx, z.owner_pid, px, py, z.src_eid, flags, life, SimZoneConsts.SD_STATIC, 0, 0, 0)
		if eid <= 0:
			continue
		var e: SimEntity = world.by_id[eid]
		if d.hp > 0:
			world.set_hp_max(e, d.hp)
			e.hp = d.hp
		e.summon.zone_id = z.id
		e.summon.src_kind = 3
		e.summon.src_idx = z.zone_idx
		z.members.append(eid)
	z.n_members = z.members.size()
