class_name AppStress
extends RefCounted
## Perf-probe helper (`--stress-units=N --stress-at=<tick>` of the test boot): drops N extra ground units per player around the player's first
## structure straight into the sim (outside the command stream: LOCAL perf runs only, never networked, never in a normal match) so a scripted
## 8-player match reaches 400+ entities within a minute instead of half an hour. The AI adopts the idle units like any other.


## Spawns up to `per_player` units for every player that owns a structure; returns the number actually spawned.
static func spawn(w: SimWorld, per_player: int) -> int:
	var made: int = 0
	var home: Dictionary = {}
	for e: SimEntity in w.entities:
		if e.kind == SimEntity.Kind.STRUCTURE and not home.has(e.owner):
			home[e.owner] = Vector2i(e.x / SimConfig.CELL, e.y / SimConfig.CELL)
	for pid: int in home.keys():
		var p: SimPlayer = w.players[pid]
		if p == null or p.roster == null:
			continue
		var defs: PackedInt32Array = PackedInt32Array()
		for idx: int in p.roster.producible_units:
			var d: DefUnit = w.data.units[idx]
			if d.home_layer == 0 and d.speed > 0 and d.weapons.size() > 0 and d.cost > 0:
				defs.append(idx)
		if defs.is_empty():
			continue
		var c: Vector2i = home[pid] as Vector2i
		var n: int = 0
		for ring: int in range(4, 40):
			for k: int in ring * 8:
				var a: float = TAU * float(k) / float(ring * 8)
				var cx: int = c.x + roundi(cos(a) * float(ring))
				var cy: int = c.y + roundi(sin(a) * float(ring))
				if not w.map.is_clear(cx, cy, 0):
					continue
				w.spawn_unit(defs[(n + made) % defs.size()], pid, cx * SimConfig.CELL + SimConfig.CELL / 2, cy * SimConfig.CELL + SimConfig.CELL / 2,
					0, 0, 0, 0, SimEvent.SPAWN_PRODUCED)
				n += 1
				if n >= per_player:
					break
			if n >= per_player:
				break
		made += n
	return made
