class_name SimStateHash
extends RefCounted
## The 16 part digests + per-entity digests + final checksum of sim_core 8.2. Every authoritative int of the world
## enters exactly one part; derived state (lists, spatial hash, events, rings, the pending queue) does not.


static func compute(world: SimWorld) -> Dictionary:
	var parts: PackedInt32Array = PackedInt32Array()
	var buf: PackedInt32Array = PackedInt32Array()
	buf.append(world.tick)
	buf.append(world.next_id)
	buf.append(world.next_proj_id)
	buf.append(world.match_state)
	buf.append(world.winner_team)
	buf.append(world.end_reason)
	buf.append(world.end_tick)
	buf.append(world._live_count)
	buf.append(world._config_hash)
	buf.append(world.data.data_hash())
	buf.append(world.map.map_hash())
	world.rules.hash_into(buf)
	parts.append(Checksum.digest32(buf))
	buf.resize(0)
	world.rng.hash_into(buf)
	parts.append(Checksum.digest32(buf))
	buf.resize(0)
	for p: SimPlayer in world.players:
		p.hash_into(buf)
	parts.append(Checksum.digest32(buf))
	var ed: PackedInt32Array = PackedInt32Array()  # per-entity digests, also returned for desync forensics
	for e: SimEntity in world.entities:
		buf.resize(0)
		e.hash_into(buf)
		ed.append(e.id)
		ed.append(Checksum.digest32(buf))
	parts.append(Checksum.digest32(ed))
	buf.resize(0)
	buf.append(world.map.checksum_dynamic())
	parts.append(Checksum.digest32(buf))
	for s: SimSystem in world.stages:
		buf.resize(0)
		s.hash_state(world, buf)
		parts.append(Checksum.digest32(buf))
	var h: int = Checksum.mix(Checksum.FNV_OFFSET, SimConfig.SIM_VERSION)
	for v: int in parts:
		h = Checksum.mix(h, v)
	return {"final": Checksum.finalize(h), "parts": parts, "entity_digests": ed}
