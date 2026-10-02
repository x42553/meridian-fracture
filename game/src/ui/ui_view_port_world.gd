class_name UiViewPortWorld
extends UiViewPort
## The production view adapter (ui.md 3.2.2 / 3.2.5): the ONLY UI file that names `View*` classes. Wraps a built `ViewWorld`
## (camera rig, picker, selection rings, health bars). The UI drives the camera: `auto_input` and the edge scroll of the rig
## are switched off here, so keyboard / edge / wheel / orbit follow the UI keymap, modals and focus rules.
## Members whose view subsystem has not landed yet (range rings, rally / order lines, placement ghost, float text, minimap
## texture, icon baking, showcase) keep the no-op defaults of `UiViewPort`; the UI degrades without them.

const CAMERA_SIGNAL_MS: int = 33  ## camera_changed is throttled to 30 Hz

var world: ViewWorld = null
## Interaction overlays and the icon service (created on first use, children of the ViewWorld): rally / order lines, range rings,
## the placement ghost with its build-radius ring, and the icon baker (build cards, portraits).
var lines: ViewLines = null
var range_rings: ViewRangeRings = null
var ghost: ViewPlacementGhost = null
var icons: ViewIconBake = null
var prewarm_report: Dictionary = {}  ## {count, ms} of the last prewarm(), filled when the queue ran empty

var _rig: ViewCamera = null
var _last_focus: Vector3 = Vector3.INF
var _last_yaw: float = -1.0e9
var _last_height: float = -1.0e9
var _last_emit_ms: int = -1000
var _cvd: bool = false
var _place_state: ViewPlacementState = ViewPlacementState.new()
var _place_def: int = -1
var _place_vd: ViewDef = null
var _place_range: Vector2 = Vector2.ZERO  ## metres (max, min) of the defense being placed
var _place_style: StringName = &""
var _def_cache: Dictionary = {}  ## def id -> ViewDef
var _menu_defs: ViewDefAdapter = null
var _prewarm_t0: int = 0
var _prewarm_count: int = 0


static var _menu_icons: UiViewPortWorld = null


static func release_statics() -> void:
	if _menu_icons != null:
		_menu_icons.icons = null
	_menu_icons = null
	ViewTurntable.release_shared()


## Icon-only adapter for screens without a running match (Field Manual, menus): no ViewWorld, the shared baker with its own
## recipe book and model builder. `request_icon` / `icon_ready` work as on a live adapter.
static func menu_icons() -> UiViewPortWorld:
	if _menu_icons == null:
		_menu_icons = UiViewPortWorld.new(null)
	return _menu_icons


func _init(p_world: ViewWorld = null) -> void:
	world = p_world
	if world == null:
		return
	_rig = world.camera
	if _rig != null:
		_rig.auto_input = false
		_rig.edge_scroll_enabled = false
		if not _rig.view_changed.is_connected(_on_rig_changed):
			_rig.view_changed.connect(_on_rig_changed)


func _on_rig_changed(_height: float, _pitch: float, _yaw: float) -> void:
	_emit_camera(true)


func _emit_camera(force: bool) -> void:
	var now: int = Time.get_ticks_msec()
	if not force and now - _last_emit_ms < CAMERA_SIGNAL_MS:
		return
	_last_emit_ms = now
	camera_changed.emit()


## Call once per rendered frame after `ViewWorld.frame`: emits `camera_changed` (<= 30 Hz) when the smoothed pose moved.
func poll_camera() -> void:
	if _rig == null:
		return
	var f: Vector3 = _rig.current_focus()
	var yaw: float = _rig.current_yaw_deg()
	var h: float = _rig.current_height()
	if f != _last_focus or not is_equal_approx(yaw, _last_yaw) or not is_equal_approx(h, _last_height):
		_last_focus = f
		_last_yaw = yaw
		_last_height = h
		_emit_camera(false)


# ---- camera -----------------------------------------------------------------------------------------------------------
func camera() -> Camera3D:
	return _rig.camera if _rig != null else null


func listener_pose() -> Dictionary:
	if _rig == null:
		return super.listener_pose()
	var c: Camera3D = _rig.camera
	var b: Basis = c.global_basis if c.is_inside_tree() else c.transform.basis
	return {"focus": _rig.current_focus(), "basis": b, "height": _rig.current_height()}


func set_camera_margins(left: float, top: float, right: float, bottom: float) -> void:
	if _rig != null:
		_rig.set_view_margins(Vector4(left, top, right, bottom))


func pan_screen(dir: Vector2, delta: float) -> void:
	if _rig != null:
		_rig.pan_screen(dir, delta)


func rotate_yaw(deg: float) -> void:
	if _rig != null:
		_rig.rotate_yaw(deg)


func tilt(deg: float) -> void:
	if _rig != null:
		_rig.tilt(deg)


func zoom_by(steps: float, cursor: Vector2) -> void:
	if _rig != null:
		_rig.zoom_by(steps, cursor)


func focus_on_sim(x: int, y: int, instant: bool = false) -> void:
	if _rig != null:
		_rig.focus_on_sim(x, y, instant)


func reset_camera_orientation() -> void:
	if _rig != null:
		_rig.reset_orientation()


## {focus_x, focus_z, yaw, zoom, pitch_bias} in metres / degrees / 0..1 / degrees (bookmarks).
func camera_state() -> Dictionary:
	if _rig == null:
		return {}
	var f: Vector3 = _rig.current_focus()
	var base: float = lerpf(_rig.pitch_near_deg, _rig.pitch_far_deg, ViewCamera.ease_zoom(_rig.current_zoom()))
	return {"focus_x": f.x, "focus_z": f.z, "yaw": _rig.current_yaw_deg(), "zoom": _rig.current_zoom(),
		"pitch_bias": _rig.current_pitch_deg() - base}


func set_camera_state(s: Dictionary, instant: bool = false) -> void:
	if _rig == null or s.is_empty():
		return
	var fx: float = float(s.get("focus_x", 0.0))
	var fz: float = float(s.get("focus_z", 0.0))
	var yaw: float = float(s.get("yaw", 0.0))
	var zoom: float = float(s.get("zoom", 0.4))
	var bias: float = float(s.get("pitch_bias", 0.0))
	if instant:
		_rig.snap_to(Vector2(fx, fz), yaw, zoom, bias)
		return
	# smooth jump: retarget the rig's smoothing goals (the rig eases toward them in `advance`)
	_rig.focus_on(Vector3(fx, 0.0, fz))
	_rig._yaw_t = deg_to_rad(yaw)
	_rig._zoom_t = clampf(zoom, 0.0, 1.0)
	_rig._bias_t = bias


func set_camera_smoothing(on: bool) -> void:
	if _rig == null:
		return
	# smooth constants are rates; a very large rate snaps within one frame (accessibility "reduce motion")
	_rig.pan_smooth = 11.0 if on else 1000.0
	_rig.zoom_smooth = 9.0 if on else 1000.0
	_rig.rot_smooth = 12.0 if on else 1000.0


func screen_to_ground(p: Vector2) -> Vector3:
	return _rig.screen_to_ground(p) if _rig != null else Vector3.INF


func frustum_ground_quad() -> PackedVector2Array:
	var out := PackedVector2Array()
	if _rig == null:
		return out
	var size: Vector2 = _viewport_size()
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]
	var mr: Rect2 = _rig.map_rect
	for c: Vector2 in corners:
		var g: Vector3 = _rig.screen_to_ground(c)
		if g == Vector3.INF:
			var ray: Array[Vector3] = _rig.screen_ray(c)
			var d: Vector3 = ray[1]
			if d.y < -0.0001:  # a corner ray that leaves the map: the sea-level plane keeps the quad's shape (clamped below)
				g = ray[0] + d * (-ray[0].y / d.y)
			else:
				var flat: Vector2 = Vector2(d.x, d.z)
				var reach: Vector2 = flat.normalized() * ViewCamera.FALLBACK_REACH_M if flat.length() > 0.0001 else Vector2.ZERO
				g = Vector3(ray[0].x + reach.x, 0.0, ray[0].z + reach.y)
		out.append(Vector2(clampf((g.x - mr.position.x) / mr.size.x, 0.0, 1.0), clampf((g.z - mr.position.y) / mr.size.y, 0.0, 1.0)))
	return out


func _viewport_size() -> Vector2:
	if _rig.view_size_override.x > 0.0 and _rig.view_size_override.y > 0.0:
		return _rig.view_size_override
	var c: Camera3D = _rig.camera
	if c != null and c.is_inside_tree():
		var s: Vector2 = c.get_viewport().get_visible_rect().size
		if s.x > 0.0 and s.y > 0.0:
			return s
	return Vector2(1920.0, 1080.0)


# ---- picking ----------------------------------------------------------------------------------------------------------
func pick(screen: Vector2, filter: int = PICK_ANY) -> int:
	return world.pick(screen, filter) if world != null and world.picker != null else -1


func pick_box(rect: Rect2, filter: int, out: PackedInt32Array) -> int:
	out.clear()
	if world == null or world.picker == null:
		return 0
	return world.pick_box(rect, filter, out)


func pick_ground(screen: Vector2) -> Vector3:
	return world.pick_ground(screen) if world != null else Vector3.INF


func entity_screen_rect(eid: int) -> Rect2:
	return world.entity_screen_rect(eid) if world != null else Rect2()


func entity_world_pos(eid: int) -> Vector3:
	if world == null:
		return Vector3.ZERO
	var p: Vector3 = world.entity_world_pos(eid)
	return Vector3.ZERO if p == Vector3.INF else p


func world_to_sim(p: Vector3) -> Vector2i:
	return world.world_to_sim(p) if world != null else Vector2i.ZERO


func sim_to_world(x: int, y: int) -> Vector3:
	return world.sim_to_world(x, y) if world != null else Vector3.ZERO


# ---- interaction visuals ----------------------------------------------------------------------------------------------
func set_selection(ids: PackedInt32Array) -> void:
	if world != null and world.selection != null:
		world.selection.set_selection(ids)


func set_hover(eid: int) -> void:
	if world == null:
		return
	if world.selection != null:
		world.selection.set_hover(eid)
	if world.health_bars != null:
		world.health_bars.set_hover(eid)


func set_health_bar_mode(mode: int) -> void:
	if world != null and world.health_bars != null:
		world.health_bars.set_mode(mode)


# ---- interaction overlays (lines, range rings, placement ghost) ---------------------------------------------------------------
func _ensure_overlays() -> bool:
	if world == null or world.sim == null:
		return false
	if lines != null:
		return true
	lines = ViewLines.new()
	lines.name = "Lines"
	world.add_child(lines)
	lines.setup(world)
	range_rings = ViewRangeRings.new()
	range_rings.name = "RangeRings"
	world.add_child(range_rings)
	range_rings.setup(world)
	ghost = ViewPlacementGhost.new()
	ghost.name = "PlacementGhost"
	world.add_child(ghost)
	ghost.setup(world)
	return true


func set_range_rings(ids: PackedInt32Array) -> void:
	if _ensure_overlays():
		range_rings.show_for(ids)


func set_rally_sources(structure_ids: PackedInt32Array) -> void:
	if _ensure_overlays():
		lines.set_rally_sources(structure_ids)


func set_order_sources(unit_ids: PackedInt32Array) -> void:
	if _ensure_overlays():
		lines.set_order_sources(unit_ids)


## Starts the ghost of structure def `struct_def` (roster index space of the sim) and shows the build-radius ring.
func begin_placement(struct_def: int) -> bool:
	if not _ensure_overlays() or struct_def < 0:
		return false
	var vd: ViewDef = world.defs.def_for(SimEntity.Kind.STRUCTURE, struct_def)
	if vd.placeholder:
		return false
	_place_def = struct_def
	_place_vd = vd
	_place_style = world.book.style_for_def(vd.id, _local_roster_id())
	var recipe: StringName = vd.recipe_id
	ghost.show_structure(struct_def, recipe, _place_style, 0)
	ghost.show_build_radius(true)
	_place_range = _defense_range_m(struct_def) if vd.is_defense else Vector2.ZERO
	return true


## `result` = the SimPlacementResult of UiSimPort.placement_result (cell codes, reason, radius flag).
func update_placement(ax: int, ay: int, result: RefCounted, orient: int = 0) -> void:
	if ghost == null or _place_def < 0:
		return
	var reason_text: String = ""
	if result is SimPlacementResult:
		var res: SimPlacementResult = result as SimPlacementResult
		_place_state.fill_from_placement(res, _place_def, orient)
		var code: int = UiSimPortWorld.place_reason_of(res.reason)
		if code > 0 and code < UiPlacement.REASON_TEXT.size():
			reason_text = UiPlacement.REASON_TEXT[code]
	else:
		_place_state.def_idx = _place_def
		_place_state.origin_cx = ax
		_place_state.origin_cy = ay
		_place_state.rot = orient
		_place_state.w = 0
		_place_state.h = 0
		_place_state.cells = PackedByteArray()
		_place_state.valid = false
		_place_state.in_radius = true
	var centre: Vector3 = Vector3((float(ax) + 0.5) * ViewConsts.CELL_M, 0.0, (float(ay) + 0.5) * ViewConsts.CELL_M)
	ghost.update_cursor(centre, _place_state, reason_text)
	if _place_range.x > 0.0:
		var c2: Vector3 = Vector3((float(_place_state.origin_cx) + float(_place_state.w) * 0.5) * ViewConsts.CELL_M, 0.0,
			(float(_place_state.origin_cy) + float(_place_state.h) * 0.5) * ViewConsts.CELL_M)
		range_rings.show_preview(c2, _place_range.x, _place_range.y)


func end_placement() -> void:
	_place_def = -1
	_place_vd = null
	_place_range = Vector2.ZERO
	if ghost != null:
		ghost.hide_ghost()
	if range_rings != null:
		range_rings.show_preview(Vector3.ZERO, 0.0)


func _local_roster_id() -> String:
	if world == null or world.sim == null:
		return ""
	var pid: int = world.local_pid
	if pid < 0 or pid >= world.sim.players.size():
		return ""
	return world.defs.roster_id(world.sim.players[pid].roster_idx)


## (max, min) weapon range in metres of a defense structure of the local roster (before research); zero for an unarmed one.
func _defense_range_m(struct_def: int) -> Vector2:
	var pid: int = world.local_pid
	if pid < 0 or pid >= world.sim.players.size():
		return Vector2.ZERO
	var roster: DefRoster = world.sim.players[pid].roster
	var sd: DefStructure = roster.structure(struct_def) if roster != null else null
	if sd == null:
		return Vector2.ZERO
	var rmax: int = 0
	var rmin: int = 0
	for ws: DefWeaponSlot in sd.weapons:
		rmax = maxi(rmax, ws.range)
		if ws.min_range > 0 and (rmin == 0 or ws.min_range < rmin):
			rmin = ws.min_range
	return Vector2(float(rmax), float(rmin)) * ViewConsts.M_PER_UNIT


# ---- icons and portraits ------------------------------------------------------------------------------------------------------
func _ensure_icons() -> ViewIconBake:
	if icons != null and is_instance_valid(icons):
		return icons
	if world != null and world.sim != null:
		icons = ViewIconBake.new()
		icons.name = "IconBake"
		icons.setup(world.book, world.models, world.materials, world.quality)
		world.add_child(icons)
	else:
		icons = ViewIconBake.shared()
	if not icons.icon_ready.is_connected(_on_icon_ready):
		icons.icon_ready.connect(_on_icon_ready)
		icons.idle.connect(_on_icons_idle)
	return icons


## True when icons are baked from a live ViewWorld (the presenter then asks for them; a fixture view keeps the glyphs).
func icons_available() -> bool:
	return world != null and world.sim != null


func _on_icon_ready(tag: StringName) -> void:
	icon_ready.emit(tag)


func _on_icons_idle() -> void:
	if _prewarm_t0 > 0:
		prewarm_report = {"count": _prewarm_count, "ms": float(Time.get_ticks_usec() - _prewarm_t0) / 1000.0}
		_prewarm_t0 = 0


## Baked icon of a def (canonical id "unit.napc.guardian") in the style of `roster_id`; null until it is ready (then
## `icon_ready(icon_key(...))` fires). Sizes: `ICON_SIZE_ICON` 128x96, `PORTRAIT` 384x288, `CARD` 188x124, `BANNER` 304x152.
func request_icon(def_id: String, roster_id: String, size: int) -> Texture2D:
	var vd: ViewDef = _def_of(def_id)
	if vd == null:
		return null
	var sz: int = clampi(size, 0, 3)
	return _ensure_icons().request_def(icon_key(def_id, roster_id, sz), vd, roster_id, sz)


## A turntable (`ViewTurntable`, the Field Manual / lobby model viewer) showing `def_id` in the style of `roster_id`; null when there is no
## renderer or no model. `team` alpha 0 = the faction accent.
func create_turntable(def_id: String, roster_id: String, team: Color = Color(0.0, 0.0, 0.0, 0.0)) -> Control:
	var tt: ViewTurntable = ViewTurntable.new()
	if not show_in_turntable(tt, def_id, roster_id, team):
		tt.free()
		return null
	return tt


## Points an existing turntable at another def; false when there is nothing to draw (the previous model stays).
func show_in_turntable(tt: Control, def_id: String, roster_id: String, team: Color = Color(0.0, 0.0, 0.0, 0.0)) -> bool:
	var vd: ViewDef = _def_of(def_id)
	var t: ViewTurntable = tt as ViewTurntable
	return vd != null and t != null and t.show_def(vd, roster_id, team)


func _def_of(def_id: String) -> ViewDef:
	var hit: ViewDef = _def_cache.get(def_id) as ViewDef
	if hit != null:
		return hit
	var live: bool = world != null and world.sim != null
	var data: GameData = world.sim.data if live else GameData.load_default()
	var defs: ViewDefAdapter = world.defs if live else _defs_for_menu(data)
	var kind: int = SimEntity.Kind.UNIT
	var idx: int = -1
	match def_id.get_slice(".", 0):
		"structure":
			kind = SimEntity.Kind.STRUCTURE
			idx = data.structure_idx(def_id)
		"neutral":
			kind = SimEntity.Kind.NEUTRAL
			idx = data.neutral_idx(def_id)
		_:
			idx = data.unit_idx(def_id)
	if idx < 0:
		return null
	var vd: ViewDef = defs.def_for(kind, idx)
	_def_cache[def_id] = vd
	return vd


func _defs_for_menu(data: GameData) -> ViewDefAdapter:
	if _menu_defs == null:
		_menu_defs = ViewDefAdapter.new()
		_menu_defs.setup(data)
	return _menu_defs


## Queues the CARD icons of every structure and unit the local roster can produce (build cards, queue strip, selection tiles).
## `prewarm_report` holds the count and the wall time once the queue ran empty.
func prewarm() -> void:
	if world == null or world.sim == null or world.local_pid < 0 or world.local_pid >= world.sim.players.size():
		return
	var roster: DefRoster = world.sim.players[world.local_pid].roster
	if roster == null:
		return
	var b: ViewIconBake = _ensure_icons()
	var rid: String = roster.id
	var reqs: Array = []
	var idx_s: PackedInt32Array = roster.producible_structures.duplicate()
	if roster.hq_idx >= 0:
		idx_s.append(roster.hq_idx)
	for si: int in idx_s:
		reqs.append(_prewarm_entry(SimEntity.Kind.STRUCTURE, si, rid, b))
	var idx_u: PackedInt32Array = roster.producible_units.duplicate()
	if roster.mcv_idx >= 0:
		idx_u.append(roster.mcv_idx)
	for ui: int in idx_u:
		reqs.append(_prewarm_entry(SimEntity.Kind.UNIT, ui, rid, b))
	_prewarm_t0 = Time.get_ticks_usec()
	_prewarm_count = reqs.size()
	prewarm_report = {}
	b.prewarm(reqs)
	if b.is_idle():
		_on_icons_idle()


func _prewarm_entry(kind: int, idx: int, rid: String, b: ViewIconBake) -> Dictionary:
	var vd: ViewDef = world.defs.def_for(kind, idx)
	return {"tag": icon_key(vd.id, rid, UiViewPort.ICON_SIZE_CARD), "recipe": vd.recipe_id, "style": b.recipe_book().style_for_def(vd.id, rid),
		"scale_bp": vd.scale_bp, "size": ViewIconBake.S_CARD}


# ---- palette, camera scale --------------------------------------------------------------------------------------------
func set_cvd_palette(on: bool) -> void:
	_cvd = on
	ViewTeamColors.set_mode(ViewTeamColors.MODE_DEUTAN if on else ViewTeamColors.MODE_NORMAL)


func set_high_contrast(on: bool) -> void:
	ViewTeamColors.set_mode(ViewTeamColors.MODE_HIGH_CONTRAST if on else (ViewTeamColors.MODE_DEUTAN if _cvd else ViewTeamColors.MODE_NORMAL))


func team_color(index: int) -> Color:
	return ViewTeamColors.color(index)


## Screen pixels per world metre at the camera focus (vertical fov, KEEP_HEIGHT).
func px_per_metre() -> float:
	if _rig == null or _rig.camera == null:
		return 30.0
	var dist: float = _rig.current_height() / maxf(sin(deg_to_rad(_rig.current_pitch_deg())), 0.05)
	return _viewport_size().y / (2.0 * dist * tan(deg_to_rad(_rig.camera.fov) * 0.5))


func project_points(sim_xy: PackedInt32Array, out: PackedVector2Array) -> void:
	out.clear()
	if world == null or _rig == null:
		return
	var n: int = sim_xy.size() / 2
	out.resize(n)
	for i: int in n:
		out[i] = _rig.world_to_screen(world.sim_to_world(sim_xy[i * 2], sim_xy[i * 2 + 1]))
