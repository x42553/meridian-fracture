class_name UiViewPort
extends RefCounted
## Everything the UI needs from the 3D presentation (ui.md 3.2.2). Abstract: the production adapter wraps `ViewWorld`,
## `ViewCamera`, `ViewPicker` ...; `UiViewPortFixture` is the scripted one (procedural battlefield, sphere picking).
## The UI DRIVES the view (camera, selection rings, placement ghost); the view owns every 3D interaction visual.
## Essentials `push_error("NOT IMPLEMENTED")`; purely visual hooks default to no-ops so adapters implement them lazily.

signal camera_changed()  ## camera moved: refresh the minimap quad (<= 30 Hz)
signal icon_ready(key: StringName)
signal quality_auto_changed(preset: int, reason: String)

const PICK_UNITS: int = 1  ## = ViewPicker.PICK_*
const PICK_STRUCTURES: int = 2
const PICK_WRECKS: int = 4
const PICK_OWN: int = 8  ## own + allied
const PICK_ENEMY: int = 16
const PICK_NEUTRAL: int = 32
const PICK_AIR: int = 64  ## aircraft are only returned when this bit is set
const PICK_GHOSTS: int = 128  ## remembered structures
const PICK_ANY: int = 0xFF

const ICON_SIZE_ICON: int = 0
const ICON_SIZE_PORTRAIT: int = 1
const ICON_SIZE_CARD: int = 2
const ICON_SIZE_BANNER: int = 3


func _ni(fn: String) -> void:
	push_error("NOT IMPLEMENTED: UiViewPort.%s" % fn)


# ---- camera (UI-driven) ---------------------------------------------------------------------------------------------
func camera() -> Camera3D:
	_ni("camera")
	return null


## {focus: Vector3, basis: Basis, height: float}: what AppAudio hands to Snd.set_camera.
func listener_pose() -> Dictionary:
	return {"focus": Vector3.ZERO, "basis": Basis.IDENTITY, "height": 0.0}


## HUD-occluded PHYSICAL pixels: `focus_on` centres in the free area.
func set_camera_margins(_left: float, _top: float, _right: float, _bottom: float) -> void:
	pass


## dir.y = -1 -> toward the top of the screen.
func pan_screen(_dir: Vector2, _delta: float) -> void:
	_ni("pan_screen")


func rotate_yaw(_deg: float) -> void:
	_ni("rotate_yaw")


func tilt(_deg: float) -> void:
	_ni("tilt")


## > 0 zooms in; drifts toward the cursor ground point.
func zoom_by(_steps: float, _cursor: Vector2) -> void:
	_ni("zoom_by")


func focus_on_sim(_x: int, _y: int, _instant: bool = false) -> void:
	_ni("focus_on_sim")


func reset_camera_orientation() -> void:
	pass


## {focus_x, focus_z, yaw, zoom, pitch_bias} (bookmarks).
func camera_state() -> Dictionary:
	_ni("camera_state")
	return {}


func set_camera_state(_s: Dictionary, _instant: bool = false) -> void:
	_ni("set_camera_state")


func set_camera_smoothing(_on: bool) -> void:
	pass


## Vector3.INF on miss.
func screen_to_ground(_p: Vector2) -> Vector3:
	_ni("screen_to_ground")
	return Vector3.INF


## The 4 viewport corners as normalised map coordinates (the minimap camera polygon).
func frustum_ground_quad() -> PackedVector2Array:
	return PackedVector2Array()


# ---- picking (hidden-by-fog, contained and camouflaged entities are never returned) -----------------------------------
## Entity id or -1.
func pick(_screen: Vector2, _filter: int = PICK_ANY) -> int:
	_ni("pick")
	return -1


## Fills `out` (ascending); returns the count.
func pick_box(_rect: Rect2, _filter: int, _out: PackedInt32Array) -> int:
	_ni("pick_box")
	return 0


func pick_ground(_screen: Vector2) -> Vector3:
	_ni("pick_ground")
	return Vector3.INF


## Projected pick volume in viewport px; an empty Rect2 when not rendered.
func entity_screen_rect(_eid: int) -> Rect2:
	_ni("entity_screen_rect")
	return Rect2()


func entity_world_pos(_eid: int) -> Vector3:
	_ni("entity_world_pos")
	return Vector3.ZERO


## The single float -> int step (5.8.2).
func world_to_sim(_p: Vector3) -> Vector2i:
	_ni("world_to_sim")
	return Vector2i.ZERO


func sim_to_world(_x: int, _y: int) -> Vector3:
	_ni("sim_to_world")
	return Vector3.ZERO


# ---- interaction visuals owned by the view --------------------------------------------------------------------------
func set_selection(_ids: PackedInt32Array) -> void:
	pass


## -1 clears.
func set_hover(_eid: int) -> void:
	pass


## 0 never, 1 selected, 2 damaged (default), 3 always.
func set_health_bar_mode(_mode: int) -> void:
	pass


func set_range_rings(_ids: PackedInt32Array) -> void:
	pass


func set_rally_sources(_structure_ids: PackedInt32Array) -> void:
	pass


func set_order_sources(_unit_ids: PackedInt32Array) -> void:
	pass


func begin_placement(_struct_def: int) -> bool:
	return false


## `result` = the SimPlacementResult of UiSimPort.placement_result.
func update_placement(_ax: int, _ay: int, _result: RefCounted, _orient: int = 0) -> void:
	pass


func end_placement() -> void:
	pass


func float_text(_text: String, _sim_x: int, _sim_y: int, _color: Color) -> void:
	pass


func set_float_font(_font: Font) -> void:
	pass


# ---- minimap sources ------------------------------------------------------------------------------------------------
func minimap_texture() -> Texture2D:
	return null


func minimap_material() -> Material:
	return null


# ---- icons, models, backdrops ---------------------------------------------------------------------------------------
## Cached texture or a flat placeholder; size = ICON_SIZE_*.
func request_icon(_def_id: String, _roster_id: String, _size: int) -> Texture2D:
	return null


func icon_key(def_id: String, roster_id: String, size: int) -> StringName:
	return StringName("%s|%s|%d" % [def_id, roster_id, size])


func make_model_node(_def_id: String, _roster_id: String, _team_index: int) -> Node3D:
	return null


func prewarm() -> void:
	pass


## Menu-mode adapter: no ViewWorld / SimWorld required (the fixture adapter until the real one lands).
static func for_menus() -> UiViewPort:
	return UiViewPortFixture.new()


func showcase(_faction_code: String) -> Node3D:
	return null


# ---- quality, palette, accessibility --------------------------------------------------------------------------------
func apply_quality(_cfg: ConfigFile) -> void:
	pass


func quality_recommend() -> int:
	return 1


func set_cvd_palette(_on: bool) -> void:
	pass


func team_color(index: int) -> Color:
	return UiPalette.team(index)


func set_high_contrast(_on: bool) -> void:
	pass


## Screen pixels per world metre at the camera focus: below 18 = strategic zoom.
func px_per_metre() -> float:
	return 30.0


## Bulk sim units [x0, y0, x1, y1, ...] -> viewport px (terrain height included; off-screen points returned as computed).
func project_points(_sim_xy: PackedInt32Array, out: PackedVector2Array) -> void:
	out.clear()


func bake_map_preview(_map: MapData) -> Texture2D:
	return null
