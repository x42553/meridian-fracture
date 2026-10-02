class_name ViewTurntable
extends SubViewportContainer
## Field Manual / lobby model viewer (spec ui 11, UI-12): a rotatable turntable of one unit or structure in the faction style of a roster,
## with the team colour and an idle animation. The model is the real one (`ViewModelBuilder` through the shared icon baker's recipe book,
## the unit shader through its own `ViewMaterials`, one `ViewModelRig` per viewer), drawn in a private SubViewport world. Drag = rotate
## (the auto spin pauses while dragging), wheel = zoom, double click = reset, `paused` stops the spin and the idle animation. The
## icon baker is untouched: this class only reads its recipe book and model cache. Presentation only.

signal paused_changed(paused: bool)
signal model_shown(ok: bool)

const FOV_DEG: float = 30.0
const PITCH_DEG: float = 20.0
const FRAME_MARGIN: float = 0.95
const SPIN_DEG_S: float = 16.0
const DRAG_DEG_PER_PX: float = 0.55
const ZOOM_MIN: float = 0.45
const ZOOM_MAX: float = 1.8
const RESUME_AFTER_S: float = 2.0

var paused: bool = false : set = set_paused
var yaw_deg: float = 150.0
var zoom: float = 1.0
var team_color: Color = Color(0.0, 0.0, 0.0, 0.0)  ## alpha 0 = the style accent
var def_id: String = ""

var _vp: SubViewport = null
var _cam: Camera3D = null
var _pivot: Node3D = null
var _rig: ViewModelRig = null
var _disc: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _blob: MeshInstance3D = null
var _mats: ViewMaterials = null
var _baker: ViewIconBake = null
var _mat: ShaderMaterial = null
var _dist: float = 6.0
var _target: Vector3 = Vector3.ZERO
var _radius: float = 1.5
var _t: float = 0.0
var _drag: bool = false
var _hold_s: float = 0.0
var _shown: bool = false
var _anim_phase: float = 0.0
var _kind_structure: bool = false
var _framed: AABB = AABB()

static var _shared_mats: ViewMaterials = null


## Forgets the shared material set (orderly quit, tests).
static func release_shared() -> void:
	_shared_mats = null


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(160.0, 120.0)
	mouse_default_cursor_shape = Control.CURSOR_MOVE


func _ensure_stage() -> bool:
	if _vp != null:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	ViewGlobals.ensure()
	_baker = ViewIconBake.shared()
	if _baker == null or _baker.recipe_book() == null:
		return false
	if _shared_mats == null:
		_shared_mats = ViewMaterials.new()  # one material set for every viewer: a card change must not recompile the unit shader
		_shared_mats.setup(_baker.recipe_book(), ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH))
	_mats = _shared_mats
	_vp = SubViewport.new()
	_vp.name = "Turntable"
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_vp.positional_shadow_atlas_size = 0
	add_child(_vp)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.12
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.05
	_cam = Camera3D.new()
	_cam.fov = FOV_DEG
	_cam.near = 0.2
	_cam.far = 300.0
	_cam.environment = env
	_vp.add_child(_cam)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.96, 0.9)
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 60.0
	key.shadow_bias = 0.04
	key.shadow_normal_bias = 1.2
	_vp.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22.0, 145.0, 0.0)
	fill.light_energy = 0.9
	fill.light_color = Color(0.72, 0.8, 1.0)
	_vp.add_child(fill)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_disc = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.04
	cyl.height = 0.08
	cyl.radial_segments = 48
	cyl.rings = 1
	_disc.mesh = cyl
	var dm: StandardMaterial3D = StandardMaterial3D.new()
	dm.albedo_color = Color(0.09, 0.1, 0.12)
	dm.metallic = 0.5
	dm.roughness = 0.55
	_disc.material_override = dm
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(_disc)
	_ring = MeshInstance3D.new()
	var tor: TorusMesh = TorusMesh.new()
	tor.inner_radius = 0.985
	tor.outer_radius = 1.0
	tor.rings = 64
	tor.ring_segments = 4
	_ring.mesh = tor
	var rm: StandardMaterial3D = StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.6, 0.2)
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(_ring)
	_blob = _make_blob()
	_vp.add_child(_blob)
	return true


func _make_blob() -> MeshInstance3D:
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	var sh: Shader = Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\n" \
		+ "void fragment() { float r = length(UV * 2.0 - 1.0); float a = (1.0 - smoothstep(0.3, 1.0, r)); ALBEDO = vec3(0.0); ALPHA = a * a * 0.55; }\n"
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = sh
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Shows the model of a resolved def in the style of `roster_id`. `team` with alpha 0 = the faction accent. False when there is nothing to draw
## (headless / no recipe) - the caller keeps its glyph or baked icon.
func show_def(vd: ViewDef, roster_id: String, team: Color = Color(0.0, 0.0, 0.0, 0.0)) -> bool:
	_shown = false
	if vd == null or vd.placeholder or not _ensure_stage():
		model_shown.emit(false)
		return false
	def_id = vd.id
	var book: ViewRecipeBook = _baker.recipe_book()
	var style_id: StringName = book.style_for_def(vd.id, roster_id)
	var model: ViewModel = _baker.model_builder().get_model(vd.recipe_id, style_id, vd.scale_bp)
	if model == null or model.mesh == null or model.placeholder:
		model_shown.emit(false)
		return false
	_kind_structure = vd.id.begins_with("structure.")
	team_color = team
	var acc: Color = team
	if acc.a <= 0.0:
		var pal: Dictionary = (book.style(style_id).get("palette", {}) as Dictionary)
		acc = Color(str(pal.get("acc", "#e0b020")))
	if _rig != null:
		_rig.queue_free()
		_rig = null
	_mat = _mats.new_entity_material(style_id, 0)
	_mat.set_shader_parameter(ViewMaterials.P_TEAM, acc)
	_rig = ViewModelRig.new()
	_rig.plain = true
	_rig.setup(model.mesh, _mat)
	_rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_pivot.add_child(_rig)
	var box: AABB = model.info.rest_aabb
	if box.size.length() < 0.01:
		box = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 1.5, 2.0))
	var c: Vector3 = box.get_center()
	_rig.position = Vector3(-c.x, -box.position.y, -c.z)  # the model's centre on the turntable axis, its base on the disc
	var diag: float = Vector2(box.size.x, box.size.z).length() * 0.5
	_radius = maxf(maxf(maxf(box.size.x, box.size.z) * 0.55, diag * 0.86), 0.6)  # between the inscribed and the circumscribed circle: tight, with the corners still inside while turning
	var d_r: float = _radius * 1.18
	_framed = AABB(Vector3(-d_r, 0.0, -d_r), Vector3(d_r * 2.0, box.size.y, d_r * 2.0))  # the disc must fit too
	_frame()
	_disc.scale = Vector3(d_r, 1.0, d_r)
	_disc.position = Vector3(0.0, -0.04, 0.0)
	_ring.scale = Vector3(d_r, 1.0, d_r)
	_ring.position = Vector3(0.0, 0.005, 0.0)
	(_ring.material_override as StandardMaterial3D).albedo_color = acc.lightened(0.15)
	_blob.scale = Vector3(_radius * 1.1, 1.0, _radius * 0.9)
	_blob.position = Vector3(0.0, 0.01, 0.0)
	_t = 0.0
	_apply_camera()
	_apply_anim()
	_shown = true
	model_shown.emit(true)
	return true


## Distance and target of the camera for the current control size (the aspect changes when the layout does).
func _frame() -> void:
	if _framed.size == Vector3.ZERO:
		return
	var aspect: float = maxf(size.x, 1.0) / maxf(size.y, 1.0) if size.x > 8.0 and size.y > 8.0 else 1.33
	var pose: Dictionary = ViewIconBake.frame_camera(_framed, 0.0, PITCH_DEG, FOV_DEG, aspect, FRAME_MARGIN, 0.1)  # 10 % free at the bottom: the control strip
	_dist = float(pose["distance"])
	_target = pose["target"] as Vector3
	_apply_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _shown:
		_frame()


func set_team_color(c: Color) -> void:
	team_color = c
	if _mat != null:
		_mat.set_shader_parameter(ViewMaterials.P_TEAM, c if c.a > 0.0 else Color(1.0, 0.6, 0.2))


func set_paused(v: bool) -> void:
	if paused == v:
		return
	paused = v
	paused_changed.emit(v)


func has_model() -> bool:
	return _shown


func reset_view() -> void:
	yaw_deg = 150.0
	zoom = 1.0
	_apply_camera()


func _apply_camera() -> void:
	if _cam == null:
		return
	var cb: Basis = Basis(Vector3.RIGHT, deg_to_rad(-PITCH_DEG))
	_cam.global_transform = Transform3D(cb, _target + cb.z * (_dist / zoom))
	if _pivot != null:
		_pivot.rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)


## The idle animation of the live game's channels: rotors / dishes spin, turrets sweep, doors cycle.
func _apply_anim() -> void:
	if _rig == null:
		return
	var turret: float = sin(_anim_phase * 0.55) * 0.5
	var spin: float = _anim_phase * 2.4
	var deploy: float = 0.5 + 0.5 * sin(_anim_phase * 0.4) if _kind_structure else 0.0
	_rig.push_anim(0.0, 0.0, 0.0, turret)
	_rig.push_aux(0.0, deploy, spin, 0.35 + 0.25 * sin(_anim_phase * 0.7))
	_rig.push_state(0.0, 0.0, 0, 0.0)


func _process(delta: float) -> void:
	if not _shown or not is_visible_in_tree():
		return
	if _hold_s > 0.0:
		_hold_s -= delta
	if not paused:
		_anim_phase += delta
		if not _drag and _hold_s <= 0.0:
			yaw_deg = fmod(yaw_deg + SPIN_DEG_S * delta, 360.0)
		_apply_anim()
	_apply_camera()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click and mb.pressed:
				reset_view()
			else:
				_drag = mb.pressed
				_hold_s = RESUME_AFTER_S
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.1, ZOOM_MIN, ZOOM_MAX)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.1, ZOOM_MIN, ZOOM_MAX)
			accept_event()
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _drag:
		yaw_deg = fmod(yaw_deg + mm.relative.x * DRAG_DEG_PER_PX, 360.0)
		_hold_s = RESUME_AFTER_S
		accept_event()
