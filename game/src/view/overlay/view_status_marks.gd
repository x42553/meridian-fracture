class_name ViewStatusMarks
extends Node3D
## Status marks of entities (render spec 5.9.7): a row of constant-screen-size glyphs above the health bar anchor (EMP bolt, suppression
## chevrons, cloak ring on own / allied cloaked units, "no power" plug, decoy identified, repair wrench), electric arcs and a cloak
## ping through the FX port, and the capture progress ring around a structure that is being captured (0.4 m stroke in the
## capturer's colour, dim for the missing part). The per-entity truth is the mirrored sim flags (ViewEntity.sim_flags: F_EMP_SHUT,
## F_SUPPRESSED, F_CLOAKED, F_REPAIR_ON, F_DECOY) and ViewSimReader.capture_progress_permille; scanned at 5 Hz, drawn every frame.
## There is no veterancy in this game, so there is no veterancy mark. Presentation only.

const G_EMP: int = 0
const G_SUPPRESSED: int = 1
const G_CLOAK: int = 2
const G_NO_POWER: int = 3
const G_DECOY: int = 4
const G_REPAIR: int = 5
const G_BUFF: int = 6
const G_MARKED: int = 7
const GLYPH_CAP: int = 384
const RING_CAP: int = 32
const SCAN_S: float = 0.2
const SLOT_PX: float = 25.0
const ROW_LIFT_PX: float = 26.0
const ANCHOR_ABOVE_M: float = 0.6
const SHADER_PATH: String = "res://assets/shaders/status_mark.gdshader"
const ARC_INTERVAL_S: float = 0.42
const REPAIR_SPARK_S: float = 0.3

## sRGB tint per glyph id.
const TINTS: Array[Color] = [
	Color(0.35, 0.95, 1.0), Color(1.0, 0.86, 0.22), Color(0.70, 0.88, 1.0), Color(1.0, 0.62, 0.15), Color(0.30, 1.0, 0.85),
	Color(0.55, 0.85, 1.0), Color(0.40, 0.65, 1.0), Color(1.0, 0.30, 0.25),
]

var count: int = 0  ## glyphs drawn last update
var ring_count: int = 0

var _v: ViewWorld = null
var _glyphs: ViewInstanceBuffer = null
var _rings: ViewInstanceBuffer = null
var _marked: Array[ViewEntity] = []
var _masks: PackedInt32Array = PackedInt32Array()
var _caps: Array[Vector4] = []  # x id, y progress 0..1, z capturer team index, w half footprint z
var _cap_ent: Array[ViewStructure] = []
var _scan_t: float = 1.0e9
var _cloak_prev: Dictionary = {}  # entity id -> bool
var _arc_t: float = 0.0
var _spark_t: float = 0.0
var _phase: float = 0.0


func setup(v: ViewWorld) -> void:
	_v = v
	var shader: Shader = load(SHADER_PATH) as Shader
	var glyph_mat: ShaderMaterial = ShaderMaterial.new()
	glyph_mat.shader = shader
	glyph_mat.render_priority = ViewLayers.PRIO_BARS
	glyph_mat.set_shader_parameter(&"mode", 0)
	var ring_shader: Shader = Shader.new()
	ring_shader.code = "#define RING 1\n" + shader.code
	var ring_mat: ShaderMaterial = ShaderMaterial.new()
	ring_mat.shader = ring_shader
	ring_mat.render_priority = ViewLayers.PRIO_RINGS
	ring_mat.set_shader_parameter(&"mode", 1)
	var gq: QuadMesh = QuadMesh.new()
	gq.size = Vector2(1.0, 1.0)
	var rq: QuadMesh = QuadMesh.new()
	rq.size = Vector2(2.0, 2.0)
	rq.orientation = PlaneMesh.FACE_Y
	_glyphs = ViewInstanceBuffer.new()
	_glyphs.setup(self, gq, glyph_mat, GLYPH_CAP)
	_rings = ViewInstanceBuffer.new()
	_rings.setup(self, rq, ring_mat, RING_CAP)
	for b: ViewInstanceBuffer in [_glyphs, _rings]:
		b.node.layers = ViewLayers.MASK_OVERLAYS
		b.node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if v.terrain != null:
			b.set_bounds(Rect2(Vector2.ZERO, v.terrain.world_size()))


## Glyph bit mask of an entity right now (bit g = glyph id g). Also used by tests.
func mask_of(ve: ViewEntity) -> int:
	var m: int = 0
	var sf: int = ve.sim_flags
	if ve.dead or ve.sim_gone:
		return 0
	if (sf & SimFlags.F_EMP_SHUT) != 0:
		m |= 1 << G_EMP
	if (sf & SimFlags.F_SUPPRESSED) != 0:
		m |= 1 << G_SUPPRESSED
	if (sf & SimFlags.F_CLOAKED) != 0 and _friendly(ve):
		m |= 1 << G_CLOAK
	if ve is ViewStructure:
		var st: ViewStructure = ve as ViewStructure
		if st.phase == ViewConsts.PH_ACTIVE and st.needs_power and not st.powered and _friendly(ve):
			m |= 1 << G_NO_POWER
		if (sf & SimFlags.F_REPAIR_ON) != 0 and ve.hp < ve.max_hp and _friendly(ve):
			m |= 1 << G_REPAIR
	if (ve.flags & ViewConsts.UF_DECOY_ID) != 0:
		m |= 1 << G_DECOY
	return m


func _friendly(ve: ViewEntity) -> bool:
	return _v.observer or ve.owner == _v.local_pid or (ve.owner >= 0 and _v.sim.are_allied(_v.local_pid, ve.owner))


func update(dt: float) -> void:
	if _v == null or _glyphs == null:
		return
	_phase += dt
	_scan_t += dt
	if _scan_t >= SCAN_S:
		_scan_t = 0.0
		_scan()
	_arc_t += dt
	_spark_t += dt
	var do_arc: bool = _arc_t >= ARC_INTERVAL_S
	var do_spark: bool = _spark_t >= REPAIR_SPARK_S
	if do_arc:
		_arc_t = 0.0
	if do_spark:
		_spark_t = 0.0
	_glyphs.begin()
	_rings.begin()
	for i: int in _marked.size():
		var ve: ViewEntity = _marked[i]
		if ve.active_idx < 0 or ve.vs == ViewConsts.VS_HIDDEN or ve.dead:
			continue
		var mask: int = _masks[i]
		_draw_row(ve, mask)
		if do_arc and (mask & (1 << G_EMP)) != 0:
			_emp_arcs(ve)
		if do_spark and (mask & (1 << G_REPAIR)) != 0:
			_repair_spark(ve)
	for c: Vector4 in _caps:
		_draw_capture(c)
	_glyphs.commit()
	_rings.commit()
	count = _glyphs.count
	ring_count = _rings.count


func _scan() -> void:
	_marked.clear()
	_masks.resize(0)
	_caps.clear()
	_cap_ent.clear()
	var ents: Array[ViewEntity] = _v.entities()
	var cloak_now: Dictionary = {}
	for ve: ViewEntity in ents:
		if ve.vs == ViewConsts.VS_HIDDEN:
			continue
		# decoy identification is a fog / detection fact of the local player: enemy decoys the local team has unmasked
		if (ve.sim_flags & SimFlags.F_DECOY) != 0 and not _friendly(ve) and _v.local_pid >= 0:
			var se: SimEntity = _v.sim.get_entity(ve.id)
			var ident: bool = se != null and _v.sim.fog.decoy_identified(_v.local_pid, se)
			if ident != ((ve.flags & ViewConsts.UF_DECOY_ID) != 0):
				ve.flags = (ve.flags | ViewConsts.UF_DECOY_ID) if ident else (ve.flags & ~ViewConsts.UF_DECOY_ID)
				ve._dirty = true
		var cloaked: bool = (ve.sim_flags & SimFlags.F_CLOAKED) != 0
		var was: Variant = _cloak_prev.get(ve.id)
		if was != null and (was as bool) != cloaked and ve.in_view:
			_cloak_ping(ve)  # the toggle itself, not the initial state
		cloak_now[ve.id] = cloaked
		var m: int = mask_of(ve)
		if m != 0 and ve.in_view:
			_marked.append(ve)
			_masks.append(m)
		if ve is ViewStructure and ve.in_view:
			var pm: int = ViewSimReader.capture_progress_permille(_v.sim.get_entity(ve.id))
			if pm >= 0 and _caps.size() < RING_CAP:
				var pid: int = ViewSimReader.capture_pid(_v.sim.get_entity(ve.id))
				var team_i: int = _v.sim.players[pid].color if pid >= 0 and pid < _v.sim.players.size() else -1
				_caps.append(Vector4(float(ve.id), float(pm) / 1000.0, float(team_i), 0.0))
	_cloak_prev = cloak_now


func _cloak_ping(ve: ViewEntity) -> void:
	_v.fx.ring(&"ring_distort", Vector3(ve.wx, ve.wy + 0.1, ve.wz), maxf(ve.radius_m * 1.6, 1.6), 0.6, 0)


func _draw_row(ve: ViewEntity, mask: int) -> void:
	var ids: Array[int] = []
	for g: int in 8:
		if (mask & (1 << g)) != 0:
			ids.append(g)
	var n: int = ids.size()
	var anchor: Vector3 = Vector3(ve.wx, ve.wy + ve.height_m + ANCHOR_ABOVE_M - ve.sink_m, ve.wz)
	var x0: float = -SLOT_PX * float(n - 1) * 0.5
	for k: int in n:
		var col: Color = TINTS[ids[k]]
		col.a = 1.0
		var custom: Color = Color(float(ids[k]), x0 + SLOT_PX * float(k), ROW_LIFT_PX, float(ve.id % 7) * 0.7)
		_glyphs.push(Transform3D(Basis.IDENTITY, anchor), col, custom)


func _draw_capture(c: Vector4) -> void:
	var st: ViewStructure = _v.entity_view(int(c.x)) as ViewStructure
	if st == null:
		return
	var ext: Vector2 = st.extent_m() * 0.5
	var col: Color = ViewTeamColors.color(int(c.z)) if c.z >= -1.0 else Color(1.0, 0.9, 0.3)
	col.a = 0.95
	var margin: float = 0.8
	var y: float = _v.ground_at(st.wx, st.wz) + 0.25
	var b: Basis = Basis.IDENTITY.scaled(Vector3(ext.x + margin, 1.0, ext.y + margin))
	_rings.push(Transform3D(b, Vector3(st.wx, y, st.wz)), col, Color(c.y, ext.x, ext.y, 0.0))


func _emp_arcs(ve: ViewEntity) -> void:
	var h: float = maxf(ve.height_m, 1.0)
	var r: float = maxf(ve.radius_m, 0.8)
	var s: int = (ve.id * 2654435761 + _v.frame_no * 40503) & 0xFFFF
	var a: Vector3 = Vector3(ve.wx + (float(s & 15) / 15.0 - 0.5) * r, ve.wy + h * 0.3, ve.wz + (float((s >> 4) & 15) / 15.0 - 0.5) * r)
	var b: Vector3 = Vector3(ve.wx + (float((s >> 8) & 15) / 15.0 - 0.5) * r * 1.6, ve.wy + h * (0.6 + 0.3 * float((s >> 12) & 3) / 3.0), ve.wz + (float((s >> 2) & 15) / 15.0 - 0.5) * r * 1.6)
	_v.fx.arc(a, b)


func _repair_spark(ve: ViewEntity) -> void:
	var r: float = maxf(ve.radius_m, 1.0)
	var s: int = (ve.id * 40503 + _v.frame_no * 2654435761) & 0xFFFF
	var p: Vector3 = Vector3(ve.wx + (float(s & 15) / 15.0 - 0.5) * r * 1.4, ve.wy + maxf(ve.height_m * 0.4, 0.6), ve.wz + (float((s >> 4) & 15) / 15.0 - 0.5) * r * 1.4)
	_v.fx.sprites(&"sparks", p, 0.55, 0.4, 0.8, 2)
