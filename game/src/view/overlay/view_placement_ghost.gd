class_name ViewPlacementGhost
extends Node3D
## Structure placement feedback (render spec 5.10): the structure model in the GHOST material (tinted green / red by
## `state.valid`) snapped to the cell grid at the footprint centre, a ground-following grid that colours every footprint cell
## from `ViewPlacementState.cells` (CF_OK green, blocked red, unit orange, deposit magenta, apron yellow, shore cyan, keep-out
## hatch), a bright footprint outline, a faint gap-1 halo, the reason text above the footprint, and the dashed build-radius ring
## (8 cells = 24 m) around every completed friendly HQ. Only rotatable footprints (the Dock) rotate. Presentation only.

const BUILD_RADIUS_M: float = 24.0
const GRID_LIFT_M: float = 0.10
const RING_LIFT_M: float = 0.16
const HQ_REFRESH_S: float = 0.5
const COL_OK: Color = Color(0.30, 1.0, 0.40)
const COL_BAD: Color = Color(1.0, 0.30, 0.25)
const COL_RADIUS: Color = Color(0.62, 1.0, 0.72, 0.85)
const GRID_SHADER: String = "res://assets/shaders/ghost_grid.gdshader"

var build_radius_m: float = BUILD_RADIUS_M
var active: bool = false
var def_idx: int = -1
var footprint_origin: Vector2i = Vector2i.ZERO
var footprint_size: Vector2i = Vector2i.ZERO
var reason_text: String = ""
var last_codes: PackedByteArray = PackedByteArray()  ## the w x h CF_* codes last uploaded to the grid texture (tests)

var _v: ViewWorld = null
var _rig: MeshInstance3D = null
var _grid: MeshInstance3D = null
var _grid_mesh: ArrayMesh = ArrayMesh.new()
var _grid_mat: ShaderMaterial = null
var _grid_x: MeshInstance3D = null  ## same mesh without depth test and fainter: the cells hidden behind an existing structure
var _grid_x_mat: ShaderMaterial = null
var _codes: ImageTexture = null
var _label: Label3D = null
var _ring: ViewRibbon = null
var _mats: Dictionary = {}  # "style|valid" -> ShaderMaterial
var _style: StringName = &""
var _model: ViewModel = null
var _rot: int = 0
var _fw: int = 1  ## unrotated footprint of the shown def
var _fh: int = 1
var _rotatable: bool = false
var _sig: int = 0
var _radius_on: bool = false
var _hq_sig: int = -1
var _hq_timer: float = 0.0
var _ground: Callable = Callable()
var _valid: bool = false


func setup(v: ViewWorld) -> void:
	_v = v
	_ground = Callable(v, "ground_at")
	_rig = MeshInstance3D.new()
	_rig.name = "GhostRig"
	_rig.visible = false
	_rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rig)
	_grid_mat = ShaderMaterial.new()
	_grid_mat.shader = load(GRID_SHADER) as Shader
	_grid_mat.render_priority = ViewLayers.PRIO_GRID
	_grid = MeshInstance3D.new()
	_grid.name = "GhostGrid"
	_grid.mesh = _grid_mesh
	_grid.material_override = _grid_mat
	_grid.layers = ViewLayers.MASK_OVERLAYS
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid.visible = false
	_grid.extra_cull_margin = 16384.0
	add_child(_grid)
	var xsh: Shader = Shader.new()
	xsh.code = (load(GRID_SHADER) as Shader).code.replace("depth_draw_never,", "depth_draw_never, depth_test_disabled,")
	_grid_x_mat = ShaderMaterial.new()
	_grid_x_mat.shader = xsh
	_grid_x_mat.render_priority = ViewLayers.PRIO_GRID + 1
	_grid_x_mat.set_shader_parameter(&"alpha_scale", 0.4)
	_grid_x = MeshInstance3D.new()
	_grid_x.name = "GhostGridXray"
	_grid_x.mesh = _grid_mesh
	_grid_x.material_override = _grid_x_mat
	_grid_x.layers = ViewLayers.MASK_OVERLAYS
	_grid_x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_x.visible = false
	_grid_x.extra_cull_margin = 16384.0
	add_child(_grid_x)
	_label = Label3D.new()
	_label.name = "Reason"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.font_size = 32
	_label.pixel_size = 0.00045
	_label.outline_size = 10
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_label.modulate = Color(1.0, 0.86, 0.8)
	_label.render_priority = 20
	_label.visible = false
	add_child(_label)
	_ring = ViewRibbon.new()
	_ring.setup(self, 4.0, ViewLayers.PRIO_LINES)
	_ring.material.set_shader_parameter(&"outline_px", 1.5)
	if v.terrain != null:
		_ring.set_bounds(Rect2(Vector2.ZERO, v.terrain.world_size()))


## Starts a placement of `struct_def` (the model of `recipe_id` in `style_id`). The footprint size comes from the def record.
func show_structure(p_def_idx: int, recipe_id: StringName, style_id: StringName, rot: int) -> void:
	def_idx = p_def_idx
	_style = style_id
	_rot = rot & 3
	var vd: ViewDef = _v.defs.def_for(SimEntity.Kind.STRUCTURE, p_def_idx)
	_fw = maxi(vd.fp_w, 1)
	_fh = maxi(vd.fp_h, 1)
	_rotatable = vd.rotatable
	_model = _v.models.get_model(recipe_id, style_id, vd.scale_bp)
	if _model.info.footprint != Vector2i.ZERO and vd.fp_w <= 1 and vd.fp_h <= 1:
		_fw = _model.info.footprint.x
		_fh = _model.info.footprint.y
	_rig.mesh = _model.mesh
	active = true
	_sig = 0
	_rig.visible = false  # shown by the first update_cursor
	_grid.visible = false
	_grid_x.visible = false
	_label.visible = false


## Moves the ghost to the state's footprint (`world_pos` is only used while the state has no footprint yet) and recolours it.
func update_cursor(world_pos: Vector3, state: ViewPlacementState, reason: String = "") -> void:
	if not active or _model == null:
		return
	var w: int = state.w
	var h: int = state.h
	var ox: int = state.origin_cx
	var oy: int = state.origin_cy
	if w <= 0 or h <= 0:
		w = _fh if (state.rot & 1) == 1 else _fw
		h = _fw if (state.rot & 1) == 1 else _fh
		ox = int(floorf(world_pos.x / ViewConsts.CELL_M)) - w / 2
		oy = int(floorf(world_pos.z / ViewConsts.CELL_M)) - h / 2
	_valid = state.valid
	reason_text = reason
	footprint_origin = Vector2i(ox, oy)
	footprint_size = Vector2i(w, h)
	var sig: int = hash([ox, oy, w, h, state.rot, state.valid, state.in_radius, state.cells, reason])
	if sig == _sig:
		return
	_sig = sig
	_place_rig(ox, oy, w, h, state.rot)
	_rebuild_grid(ox, oy, w, h, state)
	_update_label(ox, oy, w, h, reason)


func hide_ghost() -> void:
	active = false
	def_idx = -1
	if _rig != null:
		_rig.visible = false
		_grid.visible = false
		_grid_x.visible = false
		_label.visible = false
	show_build_radius(false)


## Dashed 8-cell circle around every completed, friendly HQ (allied HQs and MCVs do not extend the build area).
func show_build_radius(on: bool) -> void:
	_radius_on = on
	_hq_sig = -1
	_hq_timer = 0.0
	if not on and _ring != null:
		_ring.begin()
		_ring.commit()


func is_radius_shown() -> bool:
	return _radius_on


func _process(delta: float) -> void:
	update(delta)


func update(dt: float) -> void:
	if _v == null or not _radius_on:
		return
	_hq_timer -= dt
	if _hq_timer > 0.0:
		return
	_hq_timer = HQ_REFRESH_S
	_refresh_radius()


## World XZ of every completed friendly HQ.
func hq_centres() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if _v == null:
		return out
	for ve: ViewEntity in _v.entities():
		if ve.kind != SimEntity.Kind.STRUCTURE or ve.owner != _v.local_pid or ve.sim_gone or ve.dead or not ve.vdef.is_hq:
			continue
		if ve is ViewStructure and (ve as ViewStructure).phase != ViewConsts.PH_ACTIVE:
			continue
		if (ve.sim_flags & SimFlags.F_UNDER_CONSTRUCTION) != 0:
			continue
		out.append(Vector2(ve.wx, ve.wz))
	return out


func _refresh_radius() -> void:
	var cs: PackedVector2Array = hq_centres()
	var sig: int = hash(cs) + int(build_radius_m * 10.0)
	if sig == _hq_sig:
		return
	_hq_sig = sig
	_ring.begin()
	for c: Vector2 in cs:
		var seg: int = clampi(int(build_radius_m * 3.0), 48, 160)
		var pts: PackedVector3Array = ViewRibbon.circle_points(c.x, c.y, build_radius_m, seg, _ground, RING_LIFT_M)
		_ring.add_polyline(pts, COL_RADIUS, ViewRibbon.STYLE_BUILD, 1.0, true)
	_ring.commit()


func ring_vertex_count() -> int:
	return _ring.vertex_count if _ring != null else 0


func _place_rig(ox: int, oy: int, w: int, h: int, rot: int) -> void:
	var cx: float = (float(ox) + float(w) * 0.5) * ViewConsts.CELL_M
	var cz: float = (float(oy) + float(h) * 0.5) * ViewConsts.CELL_M
	var hx: float = float(w) * ViewConsts.CELL_M * 0.5
	var hz: float = float(h) * ViewConsts.CELL_M * 0.5
	var g: float = _v.ground_at(cx, cz) + _v.ground_at(cx - hx, cz - hz) + _v.ground_at(cx + hx, cz - hz) \
		+ _v.ground_at(cx - hx, cz + hz) + _v.ground_at(cx + hx, cz + hz)
	var y: float = g / 5.0 + ViewConsts.GROUND_LIFT_M
	var r: int = rot & 3 if _rotatable else 0
	var yaw: float = -float(r) * PI * 0.5
	var b: Basis = Basis(Vector3.UP, yaw)
	if _model.placeholder:
		var box: Vector3 = _model.info.rest_aabb.size
		b = b.scaled_local(Vector3((float(_fw) * ViewConsts.CELL_M - 0.5) / maxf(box.x, 0.1), 2.4, (float(_fh) * ViewConsts.CELL_M - 0.5) / maxf(box.z, 0.1)))
	_rig.transform = Transform3D(b, Vector3(cx, y, cz))
	_rig.material_override = _material(_valid)
	_rig.visible = true


func _material(valid: bool) -> ShaderMaterial:
	var key: String = "%s|%d" % [_style, 1 if valid else 0]
	var m: ShaderMaterial = _mats.get(key) as ShaderMaterial
	if m == null:
		m = _v.materials.unit_material(_style, ViewMaterials.Variant.GHOST).duplicate() as ShaderMaterial
		m.set_shader_parameter(&"ghost_tint", COL_OK if valid else COL_BAD)
		m.set_shader_parameter(&"ghost_alpha", 0.55)
		m.render_priority = ViewLayers.PRIO_GHOST
		_mats[key] = m
	return m


func _rebuild_grid(ox: int, oy: int, w: int, h: int, state: ViewPlacementState) -> void:
	# codes texture (w x h, R8)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(w * h)
	for i: int in w * h:
		var code: int
		if not state.in_radius:
			code = ViewPlacementState.CF_TERRAIN
		elif state.cells.is_empty():
			code = ViewPlacementState.CF_OK if state.valid else ViewPlacementState.CF_TERRAIN
		else:
			code = state.cells[i] if i < state.cells.size() else ViewPlacementState.CF_OK
		bytes[i] = code
	last_codes = bytes
	var img: Image = Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes)
	if _codes == null or _codes.get_width() != w or _codes.get_height() != h:
		_codes = ImageTexture.create_from_image(img)
	else:
		_codes.update(img)
	_grid_mat.set_shader_parameter(&"codes", _codes)
	_grid_mat.set_shader_parameter(&"fp_size", Vector2(float(w), float(h)))
	_grid_mat.set_shader_parameter(&"verdict", 0.0 if state.valid else 1.0)
	_grid_x_mat.set_shader_parameter(&"codes", _codes)
	_grid_x_mat.set_shader_parameter(&"fp_size", Vector2(float(w), float(h)))
	_grid_x_mat.set_shader_parameter(&"verdict", 0.0 if state.valid else 1.0)
	# ground-following mesh over cells -1 .. w (footprint + halo)
	var nx: int = w + 3
	var nz: int = h + 3
	var pos: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	pos.resize(nx * nz)
	uv.resize(nx * nz)
	for j: int in nz:
		for i2: int in nx:
			var cx: float = float(ox + i2 - 1) * ViewConsts.CELL_M
			var cz: float = float(oy + j - 1) * ViewConsts.CELL_M
			pos[j * nx + i2] = Vector3(cx, _v.ground_at(cx, cz) + GRID_LIFT_M, cz)
			uv[j * nx + i2] = Vector2(float(i2 - 1), float(j - 1))
	var idx: PackedInt32Array = PackedInt32Array()
	for j2: int in nz - 1:
		for i3: int in nx - 1:
			var a: int = j2 * nx + i3
			idx.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	_grid_mesh.clear_surfaces()
	_grid_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_grid.visible = true
	_grid_x.visible = true


func _update_label(ox: int, oy: int, w: int, h: int, reason: String) -> void:
	if reason.is_empty():
		_label.visible = false
		return
	var cx: float = (float(ox) + float(w) * 0.5) * ViewConsts.CELL_M
	var cz: float = (float(oy) + float(h) * 0.5) * ViewConsts.CELL_M
	_label.text = reason
	_label.position = Vector3(cx, _v.ground_at(cx, cz) + maxf(_model.info.height, 2.0) + 1.4, cz)
	_label.visible = true


## Test hooks.
func grid_mesh() -> ArrayMesh:
	return _grid_mesh


func rig() -> MeshInstance3D:
	return _rig


func label() -> Label3D:
	return _label


func grid_material() -> ShaderMaterial:
	return _grid_mat
