class_name ViewSelection
extends Node3D
## Selection rings, structure brackets, hover ring and auras (render spec 3.7 / 5.10). One ViewInstanceBuffer per mode
## (ring, rect), terrain-aligned quads lifted above the ground, drawn by ring.gdshader. Also drives the shader rim of the
## selected models (ViewEntity.selected). Presentation only: it never touches sim state.

const CAP: int = 512
const RING_MIN_R_M: float = 0.9
const RING_GROW: float = 1.25
const RING_QUAD_PER_R: float = 1.0 / 0.9  ## the stroke sits at 0.9 of the quad, the rest is the halo
const RECT_MARGIN_M: float = 0.3  ## brackets sit this far outside the footprint
const QUAD_PAD_M: float = 0.25  ## quad margin around the bracket rectangle (ring.gdshader `margin`, room for the halo)
const HOVER_ALPHA: float = 0.6
const COL_OWN: Color = Color(0.55, 1.0, 0.6)
const COL_ALLY: Color = Color(0.35, 0.62, 1.0)
const COL_ENEMY: Color = Color(1.0, 0.30, 0.25)
const COL_NEUTRAL: Color = Color(0.95, 0.9, 0.5)
const COL_HOVER: Color = Color(1.0, 1.0, 1.0)
const SHADER_PATH: String = "res://assets/shaders/ring.gdshader"

var _v: ViewWorld = null
var _ring: ViewInstanceBuffer = null
var _rect: ViewInstanceBuffer = null
var _ring_mat: ShaderMaterial = null
var _rect_mat: ShaderMaterial = null
var _sel: PackedInt32Array = PackedInt32Array()
var _hover: int = -1
var _auras: Dictionary = {}  # id -> [Color, until_tick]
var count: int = 0  ## instances drawn last update (both buffers)


func setup(v: ViewWorld) -> void:
	_v = v
	var shader: Shader = load(SHADER_PATH) as Shader
	_ring_mat = _material(shader, 0)
	_rect_mat = _material(shader, 1)
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	qm.orientation = PlaneMesh.FACE_Y
	_ring = ViewInstanceBuffer.new()
	_ring.setup(self, qm, _ring_mat, CAP)
	_rect = ViewInstanceBuffer.new()
	_rect.setup(self, qm, _rect_mat, CAP)
	for b: ViewInstanceBuffer in [_ring, _rect]:
		b.node.layers = ViewLayers.MASK_OVERLAYS
		b.node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if v.terrain != null:
		var ws: Vector2 = v.terrain.world_size()
		_ring.set_bounds(Rect2(Vector2.ZERO, ws))
		_rect.set_bounds(Rect2(Vector2.ZERO, ws))


func _material(shader: Shader, mode: int) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = shader
	m.render_priority = ViewLayers.PRIO_RINGS
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"margin", QUAD_PAD_M)
	return m


## UI calls on change. Also drives the shader rim of the selected models.
func set_selection(ids: PackedInt32Array) -> void:
	if _v != null:
		for old: int in _sel:
			var ve0: ViewEntity = _v.entity_view(old)
			if ve0 != null:
				ve0.selected_target = 0.0
		for id: int in ids:
			var ve1: ViewEntity = _v.entity_view(id)
			if ve1 != null:
				ve1.selected_target = 1.0
	_sel = ids.duplicate()


func selection() -> PackedInt32Array:
	return _sel


func set_hover(id: int) -> void:
	_hover = id


func set_aura(id: int, color: Color, until_tick: int) -> void:
	_auras[id] = [color, until_tick]


## Called by ViewWorld when a record is disposed.
func entity_gone(id: int) -> void:
	var i: int = _sel.find(id)
	if i >= 0:
		_sel.remove_at(i)
	if _hover == id:
		_hover = -1
	_auras.erase(id)


func update(_dt: float) -> void:
	if _v == null or _ring == null:
		return
	_ring.begin()
	_rect.begin()
	for id: int in _sel:
		_push(id, 0.0, 1.0)
	if _hover >= 0 and not _sel.has(_hover):
		_push(_hover, 1.0, HOVER_ALPHA)
	if not _auras.is_empty():
		var expired: Array = []
		for id2: int in _auras:
			var rec: Array = _auras[id2] as Array
			if _v.tick > (rec[1] as int):
				expired.append(id2)
			else:
				_push(id2, 2.0, 0.9, rec[0] as Color)
		for id3: Variant in expired:
			_auras.erase(id3)
	_ring.commit()
	_rect.commit()
	count = _ring.count + _rect.count


func _color_of(ve: ViewEntity) -> Color:
	if ve.owner < 0:
		return COL_NEUTRAL
	if ve.owner == _v.local_pid:
		return COL_OWN
	if _v.sim != null and _v.sim.are_allied(_v.local_pid, ve.owner):
		return COL_ALLY
	return COL_ENEMY


func _push(id: int, style: float, alpha: float, tint: Color = Color(0, 0, 0, 0)) -> void:
	var ve: ViewEntity = _v.entity_view(id)
	if ve == null or ve.vs == ViewConsts.VS_HIDDEN or ve.sim_gone:
		return
	var col: Color = tint if tint.a > 0.0 else _color_of(ve)
	if style == 1.0:
		col = COL_HOVER
	col.a = alpha
	var structural: bool = ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL
	var n: Vector3 = _v.ground_normal(ve.wx, ve.wz)
	if structural:
		var st: ViewStructure = ve as ViewStructure
		var hx: float = float(st.footprint.x) * ViewConsts.CELL_M * 0.5 + RECT_MARGIN_M
		var hz: float = float(st.footprint.y) * ViewConsts.CELL_M * 0.5 + RECT_MARGIN_M
		var arm: float = minf(float(st.footprint.x), float(st.footprint.y)) * ViewConsts.CELL_M * 0.3
		# structures stay level: brackets at the ground height of the footprint centre, lifted above the slope
		var y: float = maxf(ve.wy, _v.ground_at(ve.wx, ve.wz)) + ViewLayers.RING_LIFT_M + 0.25 * (absf(n.x) + absf(n.z))
		var b: Basis = Basis(Vector3.UP, ve.yaw).scaled_local(Vector3(hx + QUAD_PAD_M, 1.0, hz + QUAD_PAD_M))
		_rect.push(Transform3D(b, Vector3(ve.wx, y, ve.wz)), col, Color(hx, hz, style, arm))
	else:
		var r: float = maxf(ve.radius_m * RING_GROW, RING_MIN_R_M)
		var qr: float = r * RING_QUAD_PER_R
		var ground: float = _v.ground_at(ve.wx, ve.wz)
		# aligned to the terrain normal and lifted so the uphill half of the ring is not buried on a slope
		var lift: float = ViewLayers.RING_LIFT_M + r * (1.0 - n.y) * 0.5
		var tilt: Basis = Basis(Quaternion(Vector3.UP, n))
		_ring.push(Transform3D(tilt.scaled_local(Vector3(qr, 1.0, qr)), Vector3(ve.wx, ground + lift, ve.wz)), col, Color(0.0, 0.0, style, float(id & 255) / 255.0))


