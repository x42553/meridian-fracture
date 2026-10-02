class_name UiViewPortFixture
extends UiViewPort
## The scripted view adapter (ui.md 3.2.2 / task UI-04b): a procedural battlefield (`UiFixtureBattlefield`) drawn from any
## `UiSimPort` (fixture JSON or a real `SimWorld` through `UiSimPortWorld`), a small camera rig with the UI-driven camera
## API, sphere picking on `UiPickData` (`UiPicking`, fog-hidden and contained entities are never in the data) and a 2D
## overlay (`UiFixtureOverlay`) standing in for the selection / bars / lines / ghost the real view draws in 3D.
## Call `refresh()` after the sim changed (the real view does it in `frame`); picking reads the data of the last refresh.

const CELL_M: float = 3.0
const M_PER_UNIT: float = 3.0 / 1024.0
const UNIT_PER_M: float = 1024.0 / 3.0
const BAT_TO_RAD: float = TAU / 4096.0
const AIR_ALTITUDE_M: float = 7.0
const DEFAULT_PITCH: float = 55.0
const ZOOM_MIN: float = 14.0
const ZOOM_MAX: float = 150.0

# UI-pushed interaction state, read by `UiFixtureOverlay`
var selection_ids: PackedInt32Array = PackedInt32Array()
var hover_id: int = -1
var bar_mode: int = 2
var range_ring_ids: PackedInt32Array = PackedInt32Array()
var rally_ids: PackedInt32Array = PackedInt32Array()
var order_ids: PackedInt32Array = PackedInt32Array()
var ghost: Dictionary = {}  ## {struct_def, ax, ay, orient, result} while placing
var floaters: Array[Dictionary] = []  ## {text, x, y, color} recorded by `float_text` (tests)

# camera rig
var focus: Vector3 = Vector3.ZERO
var yaw_deg: float = 30.0
var pitch_deg: float = DEFAULT_PITCH
var distance: float = 62.0
var margins: Vector4 = Vector4.ZERO
var smoothing: bool = true

var root: UiFixtureBattlefield = null  ## add to a SubViewport / scene (`attach`)
var overlay: UiFixtureOverlay = null  ## add above the 3D view, below the HUD

var _sim: UiSimPort = null
var _pd: UiPickData = UiPickData.new()
var _snap: UiEntitySnapshot = UiEntitySnapshot.new()
var _row: UiEntityRow = UiEntityRow.new()
var _hp: PackedFloat32Array = PackedFloat32Array()
var _cam: Camera3D = null
var _icons: Dictionary = {}
var _mini: ImageTexture = null


## Builds the battlefield for `sim`'s map. `amp` = terrain amplitude (0 = flat, exact picking), `render` false skips every
## mesh (headless tests keep the camera, height function and picking).
func _init(p_sim: UiSimPort = null, amp: float = 0.0, render: bool = true) -> void:
	_sim = p_sim
	root = UiFixtureBattlefield.new()
	var cw: int = p_sim.map_w() if p_sim != null else 128
	var ch: int = p_sim.map_h() if p_sim != null else 128
	root.build(cw, ch, amp, render)
	_cam = root.camera
	overlay = UiFixtureOverlay.new()
	overlay.view = self
	focus = Vector3(float(cw) * CELL_M * 0.5, 0.0, float(ch) * CELL_M * 0.5)
	_place_camera()


## Adds the 3D root to `host` (a SubViewport / Node); the camera then projects with the host's viewport size.
func attach(host: Node) -> void:
	host.add_child(root)
	_place_camera()


## Frees the 3D root and the overlay (they are plain nodes outside any owner until attached).
func dispose() -> void:
	for n: Node in [root, overlay]:
		if is_instance_valid(n):
			if n.is_inside_tree():
				n.queue_free()
			else:
				n.free()


func sim() -> UiSimPort:
	return _sim


func pd() -> UiPickData:
	return _pd


# ---- refresh ----------------------------------------------------------------------------------------------------------
## Rebuilds the pick data and the stand-in instances from the sim's snapshot (call after ticks / moves).
func refresh() -> void:
	_sim.snapshot(_snap)
	_pd.clear()
	var n: int = _snap.count
	_hp.resize(n)
	var d: GameData = _sim.data()
	var viewer: int = _sim.viewer_pid()
	root.begin_frame()
	var slot: int = 0
	for i: int in n:
		var eid: int = _snap.ids[i]
		var fl: int = _snap.flags[i]
		var kind: int = _snap.kind_of(i)
		var owner: int = _snap.owners[i]
		var def: int = _snap.defs[i]
		var pos: Vector3 = sim_to_world(_snap.xs[i], _snap.ys[i])
		var pf: int = 0
		var shape: int = UiFixtureBattlefield.Shape.VEHICLE
		var radius: float = 1.1
		var h: float = 1.6
		var alt: float = 0.0
		var fw: int = 1
		var fh: int = 1
		match kind:
			UiEntityRow.K_STRUCTURE, UiEntityRow.K_NEUTRAL_STRUCTURE:
				pf |= UiPickData.F_STRUCTURE
				shape = UiFixtureBattlefield.Shape.STRUCTURE
				if d != null and kind == UiEntityRow.K_STRUCTURE and def >= 0 and def < d.structures.size():
					fw = d.structures[def].fp_w
					fh = d.structures[def].fp_h
				elif d != null and kind == UiEntityRow.K_NEUTRAL_STRUCTURE and def >= 0 and def < d.neutrals.size():
					fw = d.neutrals[def].fp_w
					fh = d.neutrals[def].fp_h
				radius = maxf(float(maxi(fw, fh)) * CELL_M * 0.42, 1.6)
				h = 2.4 + 0.55 * float(maxi(fw, fh))
			UiEntityRow.K_WRECK:
				pf |= UiPickData.F_WRECK
				shape = UiFixtureBattlefield.Shape.WRECK
				radius = 1.0
				h = 0.8
			_:
				if d != null and def >= 0 and def < d.units.size():
					var u: DefUnit = d.units[def]
					radius = maxf(float(u.radius) * M_PER_UNIT * 1.1, 0.55)
					if u.move_class == DefEnums.MoveClass.AIR_FIXED or u.move_class == DefEnums.MoveClass.AIR_HOVER:
						pf |= UiPickData.F_AIR
						shape = UiFixtureBattlefield.Shape.AIR
						alt = AIR_ALTITUDE_M
						radius = maxf(radius, 1.4)
						h = 1.4
					elif u.move_class == DefEnums.MoveClass.FOOT:
						shape = UiFixtureBattlefield.Shape.INFANTRY
						radius = maxf(radius, 0.7)
						h = 1.7
					elif u.move_class == DefEnums.MoveClass.NAVAL or u.move_class == DefEnums.MoveClass.SUBMERGED:
						shape = UiFixtureBattlefield.Shape.NAVAL
						radius = maxf(radius, 1.6)
						h = 1.6
					else:
						radius = clampf(radius, 1.0, 2.2)
		if (fl & UiEntityRow.F_GHOST) != 0:
			pf |= UiPickData.F_GHOST
		if owner < 0:
			pf |= UiPickData.F_NEUTRAL
		elif viewer >= 0 and owner == viewer:
			pf |= UiPickData.F_OWN
		elif viewer >= 0 and _sim.rel(viewer, owner) == UiSimPort.Rel.ALLY:
			pf |= UiPickData.F_ALLY
		var ctr: Vector3 = pos + Vector3(0.0, alt + h * 0.5, 0.0)
		_pd.add(eid, pos, ctr, radius, h + alt, pf)
		_hp[slot] = float(_snap.hp_pct[i]) / 100.0
		var yaw: float = 0.0
		if _sim.read(eid, _row):
			yaw = -float(_row.facing) * BAT_TO_RAD
		var col: Color = _entity_color(owner, viewer, (pf & UiPickData.F_GHOST) != 0)
		_draw_standin(shape, pos, yaw, radius, h, alt, fw, fh, col)
		slot += 1
	root.end_frame()
	overlay.queue_redraw()


func _entity_color(owner: int, _viewer: int, is_ghost: bool) -> Color:
	var c: Color = Color(0.62, 0.62, 0.60) if owner < 0 else team_color(_sim.color_of(owner))
	if is_ghost:
		return c.lerp(Color(0.3, 0.32, 0.36), 0.7)
	return c


func _draw_standin(shape: int, pos: Vector3, yaw: float, radius: float, h: float, alt: float, fw: int, fh: int, col: Color) -> void:
	var dark: Color = col.darkened(0.45)
	var light: Color = col.lightened(0.15)
	var up: Vector3 = Vector3(0.0, alt, 0.0)
	match shape:
		UiFixtureBattlefield.Shape.STRUCTURE:
			var w: float = float(fw) * CELL_M - 0.5
			var l: float = float(fh) * CELL_M - 0.5
			root.push_box(pos + Vector3(0.0, h * 0.3, 0.0), Vector3(w, h * 0.6, l), 0.0, Color(0.30, 0.31, 0.33).lerp(col, 0.12))
			root.push_box(pos + Vector3(0.0, h * 0.6 + h * 0.14, 0.0), Vector3(w * 0.62, h * 0.28, l * 0.62), 0.0, col)
			root.push_box(pos + Vector3(w * 0.22, h * 0.6 + h * 0.36, -l * 0.15), Vector3(w * 0.16, h * 0.16, l * 0.16), 0.0, light)
			root.push_shadow(pos, Vector2(w + 2.5, l + 2.5))
		UiFixtureBattlefield.Shape.INFANTRY:
			root.push_capsule(pos, 0.34, 1.35, col)
			root.push_capsule(pos + Vector3(0.55, 0.0, 0.4), 0.3, 1.25, light)
			root.push_capsule(pos + Vector3(-0.5, 0.0, 0.5), 0.3, 1.25, dark.lightened(0.3))
			root.push_shadow(pos, Vector2(1.8, 1.8))
		UiFixtureBattlefield.Shape.AIR:
			root.push_box(pos + up, Vector3(radius * 1.7, 0.35, radius * 0.55), yaw, col)
			root.push_box(pos + up + Vector3(0.0, 0.05, 0.0), Vector3(radius * 0.6, 0.14, radius * 2.3), yaw, dark)
			root.push_shadow(pos + Vector3(0.0, -alt + 0.0, 0.0), Vector2(radius * 2.4, radius * 2.4))
		UiFixtureBattlefield.Shape.WRECK:
			root.push_box(pos + Vector3(0.0, 0.3, 0.0), Vector3(radius * 1.8, 0.6, radius * 1.1), yaw, Color(0.14, 0.13, 0.12))
		UiFixtureBattlefield.Shape.NAVAL:
			root.push_box(pos + Vector3(0.0, 0.5, 0.0), Vector3(radius * 3.0, 1.0, radius * 1.0), yaw, dark.lerp(Color(0.4, 0.42, 0.45), 0.5))
			root.push_box(pos + Vector3(0.0, 1.3, 0.0), Vector3(radius * 1.0, 0.7, radius * 0.8), yaw, col)
		_:
			var fwd: Vector3 = Vector3(cos(-yaw), 0.0, -sin(-yaw))
			root.push_box(pos + Vector3(0.0, 0.5, 0.0), Vector3(radius * 1.9, 0.75, radius * 1.25), yaw, Color(0.20, 0.23, 0.21).lerp(col, 0.2))
			root.push_box(pos + Vector3(0.0, 1.05, 0.0), Vector3(radius * 1.0, 0.42, radius * 0.9), yaw, col.darkened(0.08))
			root.push_box(pos + Vector3(0.0, 1.1, 0.0) + fwd * radius * 0.85, Vector3(radius * 1.1, 0.13, 0.13), yaw, Color(0.12, 0.13, 0.14))
			root.push_shadow(pos, Vector2(radius * 2.9, radius * 2.9))


# ---- camera ----------------------------------------------------------------------------------------------------------
func camera() -> Camera3D:
	return _cam


func _place_camera() -> void:
	var el: float = deg_to_rad(pitch_deg)
	var yaw: float = deg_to_rad(yaw_deg)
	var off: Vector3 = Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el)) * distance
	var eye: Vector3 = focus + off
	_cam.transform = Transform3D(Basis.looking_at(-off, Vector3.UP), eye)


func _moved() -> void:
	_place_camera()
	camera_changed.emit()
	if overlay != null:
		overlay.queue_redraw()


func listener_pose() -> Dictionary:
	return {"focus": focus, "basis": _cam.transform.basis, "height": _cam.transform.origin.y}


func set_camera_margins(left: float, top: float, right: float, bottom: float) -> void:
	margins = Vector4(left, top, right, bottom)


func pan_screen(dir: Vector2, delta: float) -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var f: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var r: Vector2 = Vector2(-f.y, f.x)
	var move: Vector2 = (r * dir.x - f * dir.y) * distance * 0.9 * delta
	_set_focus(focus + Vector3(move.x, 0.0, move.y))


func _set_focus(p: Vector3) -> void:
	focus = Vector3(clampf(p.x, 0.0, root.map_w_m), 0.0, clampf(p.z, 0.0, root.map_h_m))
	focus.y = root.height_at(focus.x, focus.z)
	_moved()


func rotate_yaw(deg: float) -> void:
	yaw_deg = fposmod(yaw_deg + deg, 360.0)
	_moved()


func tilt(deg: float) -> void:
	pitch_deg = clampf(pitch_deg + deg, 30.0, 80.0)
	_moved()


func zoom_by(steps: float, cursor: Vector2) -> void:
	var before: Vector3 = screen_to_ground(cursor) if _cam.is_inside_tree() else Vector3.INF
	distance = clampf(distance * pow(0.88, steps), ZOOM_MIN, ZOOM_MAX)
	_place_camera()
	if before != Vector3.INF:
		var after: Vector3 = screen_to_ground(cursor)
		if after != Vector3.INF:
			var shift: Vector3 = before - after
			focus = Vector3(clampf(focus.x + shift.x, 0.0, root.map_w_m), focus.y, clampf(focus.z + shift.z, 0.0, root.map_h_m))
	_moved()


func focus_on_sim(x: int, y: int, _instant: bool = false) -> void:
	_set_focus(sim_to_world(x, y))


func reset_camera_orientation() -> void:
	yaw_deg = 30.0
	pitch_deg = DEFAULT_PITCH
	distance = 62.0
	_moved()


func camera_state() -> Dictionary:
	return {"focus_x": focus.x, "focus_z": focus.z, "yaw": yaw_deg, "zoom": distance, "pitch_bias": pitch_deg - DEFAULT_PITCH}


func set_camera_state(s: Dictionary, _instant: bool = false) -> void:
	yaw_deg = float(s.get("yaw", yaw_deg))
	distance = clampf(float(s.get("zoom", distance)), ZOOM_MIN, ZOOM_MAX)
	pitch_deg = clampf(DEFAULT_PITCH + float(s.get("pitch_bias", 0.0)), 30.0, 80.0)
	_set_focus(Vector3(float(s.get("focus_x", focus.x)), 0.0, float(s.get("focus_z", focus.z))))


func set_camera_smoothing(on: bool) -> void:
	smoothing = on


func screen_to_ground(p: Vector2) -> Vector3:
	if not _cam.is_inside_tree():
		return Vector3.INF
	return _ground_hit(_cam.project_ray_origin(p), _cam.project_ray_normal(p))


func _ground_hit(o: Vector3, d: Vector3) -> Vector3:
	if d.y >= -0.0001:
		return Vector3.INF
	var t: float = -o.y / d.y
	var g: Vector3 = o + d * t
	if root.amp > 0.0:
		for _i: int in 4:  # fixed-point refinement against the height field
			var h: float = root.height_at(g.x, g.z)
			g = o + d * ((h - o.y) / d.y)
	if g.x < 0.0 or g.z < 0.0 or g.x > root.map_w_m or g.z > root.map_h_m:
		return Vector3.INF
	g.y = root.height_at(g.x, g.z)
	return g


func frustum_ground_quad() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if not _cam.is_inside_tree():
		return out
	var vs: Vector2 = _cam.get_viewport().get_visible_rect().size
	for c: Vector2 in [Vector2(0.0, 0.0), Vector2(vs.x, 0.0), Vector2(vs.x, vs.y), Vector2(0.0, vs.y)]:
		var g: Vector3 = screen_to_ground(c)
		if g == Vector3.INF:  # a corner above the horizon: fall back to a far point along the ray
			var o: Vector3 = _cam.project_ray_origin(c)
			var dv: Vector3 = _cam.project_ray_normal(c)
			g = o + Vector3(dv.x, 0.0, dv.z).normalized() * root.map_w_m
		out.append(Vector2(clampf(g.x / root.map_w_m, 0.0, 1.0), clampf(g.z / root.map_h_m, 0.0, 1.0)))
	return out


# ---- picking ---------------------------------------------------------------------------------------------------------
func pick(screen: Vector2, filter: int = PICK_ANY) -> int:
	return UiPicking.ray_pick(_cam, _pd, screen, filter)


func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int:
	out.clear()
	out.append_array(UiPicking.box_select(_cam, _pd, rect, filter))
	return out.size()


func pick_ground(screen: Vector2) -> Vector3:
	return screen_to_ground(screen)


func entity_screen_rect(eid: int) -> Rect2:
	var i: int = _pd.slot_of(eid)
	if i < 0 or not _cam.is_inside_tree():
		return Rect2()
	var c: Vector3 = _pd.center[i]
	if _cam.is_position_behind(c):
		return Rect2()
	var depth: float = -(_cam.global_transform.affine_inverse() * c).z
	var vs: Vector2 = _cam.get_viewport().get_visible_rect().size
	var px: float = _pd.radius[i] * (vs.y * 0.5) / (tan(deg_to_rad(_cam.fov) * 0.5) * maxf(depth, 0.1))
	var p: Vector2 = _cam.unproject_position(c)
	return Rect2(p - Vector2(px, px), Vector2(px, px) * 2.0)


func entity_world_pos(eid: int) -> Vector3:
	var i: int = _pd.slot_of(eid)
	return _pd.pos[i] if i >= 0 else Vector3.ZERO


func radius_of(eid: int) -> float:
	var i: int = _pd.slot_of(eid)
	return _pd.radius[i] if i >= 0 else 1.0


func hp_frac_of_slot(i: int) -> float:
	return _hp[i] if i < _hp.size() else 1.0


func ground_height(x: float, z: float) -> float:
	return root.height_at(x, z)


func world_to_sim(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * UNIT_PER_M), roundi(p.z * UNIT_PER_M))


func sim_to_world(x: int, y: int) -> Vector3:
	var wx: float = float(x) * M_PER_UNIT
	var wz: float = float(y) * M_PER_UNIT
	return Vector3(wx, root.height_at(wx, wz), wz)


func px_per_metre() -> float:
	var vh: float = _cam.get_viewport().get_visible_rect().size.y if _cam.is_inside_tree() else 1080.0
	return vh / (2.0 * tan(deg_to_rad(_cam.fov) * 0.5) * distance)


func project_points(sim_xy: PackedInt32Array, out: PackedVector2Array) -> void:
	out.clear()
	if not _cam.is_inside_tree():
		return
	for i: int in sim_xy.size() / 2:
		out.append(_cam.unproject_position(sim_to_world(sim_xy[i * 2], sim_xy[i * 2 + 1])))


# ---- interaction visuals (2D stand-ins) -------------------------------------------------------------------------------
func set_selection(ids: PackedInt32Array) -> void:
	selection_ids = ids.duplicate()
	overlay.queue_redraw()


func set_hover(eid: int) -> void:
	if eid != hover_id:
		hover_id = eid
		overlay.queue_redraw()


func set_health_bar_mode(mode: int) -> void:
	bar_mode = clampi(mode, 0, 3)
	overlay.queue_redraw()


func set_range_rings(ids: PackedInt32Array) -> void:
	range_ring_ids = ids.slice(0, 12)
	overlay.queue_redraw()


func set_rally_sources(structure_ids: PackedInt32Array) -> void:
	rally_ids = structure_ids.duplicate()
	overlay.queue_redraw()


func set_order_sources(unit_ids: PackedInt32Array) -> void:
	order_ids = unit_ids.slice(0, 32)
	overlay.queue_redraw()


func begin_placement(struct_def: int) -> bool:
	ghost = {"struct_def": struct_def, "ax": 0, "ay": 0, "orient": 0, "result": null}
	return true


func update_placement(ax: int, ay: int, result: RefCounted, orient: int = 0) -> void:
	if ghost.is_empty():
		return
	ghost["ax"] = ax
	ghost["ay"] = ay
	ghost["orient"] = orient
	ghost["result"] = result
	overlay.queue_redraw()


func end_placement() -> void:
	ghost = {}
	overlay.queue_redraw()


func float_text(text: String, sim_x: int, sim_y: int, color: Color) -> void:
	floaters.append({"text": text, "x": sim_x, "y": sim_y, "color": color})
	if floaters.size() > 64:
		floaters.pop_front()


# ---- minimap, icons, palette -----------------------------------------------------------------------------------------
## One texel per cell shaded from the fixture terrain (baked once).
func minimap_texture() -> Texture2D:
	if _mini == null:
		var w: int = _sim.map_w()
		var h: int = _sim.map_h()
		var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
		for cy: int in h:
			for cx: int in w:
				var hh: float = root.height_at((float(cx) + 0.5) * CELL_M, (float(cy) + 0.5) * CELL_M)
				var t: float = clampf(0.5 + hh / maxf(root.amp * 2.0, 1.0), 0.0, 1.0)
				img.set_pixel(cx, cy, Color(0.16, 0.24, 0.12).lerp(Color(0.42, 0.38, 0.22), t))
		_mini = ImageTexture.create_from_image(img)
	return _mini


func minimap_material() -> Material:
	return CanvasItemMaterial.new()


## A flat placeholder texture per (def, roster, size), coloured by a hash of the id.
func request_icon(def_id: String, roster_id: String, size: int) -> Texture2D:
	var key: StringName = icon_key(def_id, roster_id, size)
	if not _icons.has(key):
		var px: Vector2i = [Vector2i(128, 96), Vector2i(384, 288), Vector2i(188, 124), Vector2i(304, 152)][clampi(size, 0, 3)]
		var hue: float = float(hash(def_id) % 360) / 360.0
		var img: Image = Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
		img.fill(Color.from_hsv(hue, 0.35, 0.42))
		_icons[key] = ImageTexture.create_from_image(img)
	return _icons[key] as Texture2D


func team_color(index: int) -> Color:
	return UiPalette.team(index)


func quality_recommend() -> int:
	return 1
