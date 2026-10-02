class_name AppDevCamera
extends RefCounted
## Dev / test helper of the GUI test boot (`--focus=fight[,zoom=0.3]`): parks the match camera on the hottest fight so a screenshot
## shows muzzle flashes, tracers and explosions. Presentation only: it reads the sim and moves the camera.

const WINDOW_TICKS: int = 24


## The centroid (sub-cell units) of the units that fired within the last WINDOW_TICKS, or (-1, -1) when nobody fought.
static func fight_centre(w: SimWorld) -> Vector2i:
	var sx: int = 0
	var sy: int = 0
	var n: int = 0
	var first: SimEntity = null
	for e: SimEntity in w.entities:
		if e.combat != null and e.combat.last_fire_tick > 0 and w.tick - e.combat.last_fire_tick <= WINDOW_TICKS:
			if first == null:
				first = e
			# only the cluster around the first shooter, so two fights do not average into empty ground
			if absi(e.x - first.x) < 24 * 1024 and absi(e.y - first.y) < 24 * 1024:
				sx += e.x
				sy += e.y
				n += 1
	if n == 0:
		return Vector2i(-1, -1)
	return Vector2i(sx / n, sy / n)


## The centre of the densest crowd: the live unit / structure with the most others within RADIUS sub-cells (perf probes: the
## camera on the busiest spot shows the most entities a player would see at once). (-1, -1) while nothing lives.
static func crowd_centre(w: SimWorld, radius_cells: int = 30) -> Vector2i:
	var r: int = radius_cells * 1024
	var xs: PackedInt32Array = PackedInt32Array()
	var ys: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in w.entities:
		if (e.kind == SimEntity.Kind.UNIT or e.kind == SimEntity.Kind.STRUCTURE) and (e.flags & SimFlags.F_DEAD) == 0:
			xs.append(e.x)
			ys.append(e.y)
	var best: int = -1
	var best_n: int = 0
	for i: int in xs.size():
		var n: int = 0
		for j: int in xs.size():
			if absi(xs[j] - xs[i]) < r and absi(ys[j] - ys[i]) < r:
				n += 1
		if n > best_n:
			best_n = n
			best = i
	if best < 0:
		return Vector2i(-1, -1)
	return Vector2i(xs[best], ys[best])


## Centre of the first structure that is being built (BUILDUP scaffold), (-1, -1) when none.
static func build_centre(w: SimWorld) -> Vector2i:
	for e: SimEntity in w.entities:
		if e.kind == SimEntity.Kind.STRUCTURE and e.econ != null and e.econ.st == SimEconConst.ST_BUILDUP and e.owner == 0 and e.econ.st_until >= w.tick:
			return Vector2i(e.x, e.y)
	return Vector2i(-1, -1)


## Centre of the first refinery with a collector unloading at its dock, (-1, -1) when none.
static func dock_centre(w: SimWorld) -> Vector2i:
	for e: SimEntity in w.entities:
		if e.kind == SimEntity.Kind.STRUCTURE and e.econ != null and e.econ.dock_occupant > 0:
			return Vector2i(e.x, e.y)
	return Vector2i(-1, -1)


## Centre of the first live unit on the given movement layer (SimEntity.Layer), the one nearest the map centre first so a screenshot is not framed on a base edge; (-1, -1) when none.
static func layer_centre(w: SimWorld, layer: int) -> Vector2i:
	var best: SimEntity = null
	var best_d: int = 0x7FFFFFFF
	var mx: int = w.map.w * 512 if w.map != null else 0
	var my: int = w.map.h * 512 if w.map != null else 0
	for e: SimEntity in w.entities:
		if e.kind == SimEntity.Kind.UNIT and e.layer == layer and e.hp > 0:
			var d: int = absi(e.x - mx) / 1024 + absi(e.y - my) / 1024
			if d < best_d:
				best_d = d
				best = e
	return Vector2i(best.x, best.y) if best != null else Vector2i(-1, -1)


## Centre of the wreck that died last (a burning wreck), (-1, -1) when none.
static func wreck_centre(w: SimWorld) -> Vector2i:
	var best: SimEntity = null
	for e: SimEntity in w.entities:
		if e.kind == SimEntity.Kind.WRECK and (best == null or e.born > best.born):
			best = e
	return Vector2i(best.x, best.y) if best != null else Vector2i(-1, -1)


## Whether the moment `what` ("build", "wreck", "fight") has come in the match (the first construction of player 0, any wreck, any shot).
static func event_seen(w: SimWorld, what: String) -> bool:
	match what:
		"build":
			return build_centre(w).x >= 0
		"wreck":
			return wreck_centre(w).x >= 0
		"fight":
			return fight_centre(w).x >= 0
		"dock":
			return dock_centre(w).x >= 0
		"air":
			return layer_centre(w, SimEntity.Layer.AIR).x >= 0
		"naval":
			return layer_centre(w, SimEntity.Layer.SURFACE).x >= 0
	return false


## Target of the oldest running superweapon warning / strike (`--focus=sw`), (-1, -1) when none.
static func warning_centre(w: SimWorld) -> Vector2i:
	if w.strategic == null:
		return Vector2i(-1, -1)
	for wr: SimWarning in w.strategic.warnings:
		if wr.kind == SimEconConst.WK_SUPER:
			return Vector2i(wr.x, wr.y)
	return Vector2i(-1, -1)


## Moves the camera of `view` (a `UiViewPort`) to the hot spot of `what` ("fight", "build", "wreck"); true when there was one.
static func follow_fight(view: UiViewPort, w: SimWorld, zoom: float, what: String = "fight") -> bool:
	if view == null or w == null:
		return false
	var c: Vector2i = fight_centre(w)
	if what == "build":
		c = build_centre(w)
	elif what == "wreck":
		c = wreck_centre(w)
	elif what == "dock":
		c = dock_centre(w)
	elif what == "crowd":
		c = crowd_centre(w)
	elif what == "sw":
		c = warning_centre(w)
	elif what == "air":
		c = layer_centre(w, SimEntity.Layer.AIR)
	elif what == "naval":
		c = layer_centre(w, SimEntity.Layer.SURFACE)
	if c.x < 0:
		return false
	var s: Dictionary = view.camera_state()
	if s.is_empty():
		return false
	s["focus_x"] = float(c.x) / 1024.0 * ViewConsts.CELL_M
	s["focus_z"] = float(c.y) / 1024.0 * ViewConsts.CELL_M
	s["zoom"] = zoom
	view.set_camera_state(s, true)
	return true


## One line about the entity `event_seen` found (diagnostics of the proof runs).
static func describe(w: SimWorld, what: String) -> String:
	if what != "build":
		return ""
	for e: SimEntity in w.entities:
		if e.kind == SimEntity.Kind.STRUCTURE and e.econ != null and e.econ.st == SimEconConst.ST_BUILDUP and e.owner == 0:
			return "id=%d def=%s born=%d until=%d" % [e.id, w.data.structures[e.def_idx].id, e.born, e.econ.st_until]
	return ""
