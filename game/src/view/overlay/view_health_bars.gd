class_name ViewHealthBars
extends Node3D
## Constant-screen-size health bars with a per-player shape pip (render spec 3.7 / 5.10), drawn by health_bar.gdshader from one
## ViewInstanceBuffer (cap 512). Default mode DAMAGED: selected or hovered entities, entities hurt within the last 8 s (fade 0.5 s)
## and every structure under construction / being sold. Enemy bars only while selected or hovered. Presentation only.

enum Mode { NEVER, SELECTED, DAMAGED, ALWAYS }

const CAP: int = 512
const SHOW_TICKS: int = 160  ## 8 s at 20 TPS
const FADE_TICKS: int = 10  ## 0.5 s
const ANCHOR_ABOVE_M: float = 0.6
const SHADER_PATH: String = "res://assets/shaders/health_bar.gdshader"
const COL_GREEN: int = 0
const COL_YELLOW: int = 1
const COL_RED: int = 2
const COL_BUILD: int = 3

var mode: int = Mode.DAMAGED
var count: int = 0  ## bars drawn last update

var _v: ViewWorld = null
var _buf: ViewInstanceBuffer = null
var _marks: Dictionary = {}  # id -> last damage tick
var _hover: int = -1


func setup(v: ViewWorld) -> void:
	_v = v
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.render_priority = ViewLayers.PRIO_BARS
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	_buf = ViewInstanceBuffer.new()
	_buf.setup(self, qm, mat, CAP)
	_buf.node.layers = ViewLayers.MASK_OVERLAYS
	_buf.node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if v.terrain != null:
		_buf.set_bounds(Rect2(Vector2.ZERO, v.terrain.world_size()))


func set_mode(m: int) -> void:
	mode = clampi(m, Mode.NEVER, Mode.ALWAYS)


func set_hover(id: int) -> void:
	_hover = id


func mark_damaged(id: int, at_tick: int) -> void:
	_marks[id] = at_tick


## Bar width in pixels by size class (spec 5.10).
static func width_px(ve: ViewEntity) -> float:
	if ve.kind == SimEntity.Kind.STRUCTURE or ve.kind == SimEntity.Kind.NEUTRAL:
		var fw: int = maxi(ve.vdef.fp_w, 1) if ve.vdef != null else 2
		return clampf(float(fw) * 22.0, 44.0, 130.0)
	var sc: int = ve.vdef.size_class if ve.vdef != null else DefEnums.SizeClass.MEDIUM
	match sc:
		DefEnums.SizeClass.INFANTRY:
			return 28.0
		DefEnums.SizeClass.LIGHT:
			return 36.0
		DefEnums.SizeClass.MEDIUM:
			return 44.0
		DefEnums.SizeClass.HEAVY:
			return 56.0
		DefEnums.SizeClass.HUGE:
			return 72.0
		DefEnums.SizeClass.AIR_MEDIUM, DefEnums.SizeClass.AIR_LARGE:
			return 36.0
		DefEnums.SizeClass.SHIP_SMALL:
			return 40.0
		DefEnums.SizeClass.SHIP_MEDIUM:
			return 60.0
		DefEnums.SizeClass.SHIP_LARGE:
			return 84.0
	return 44.0


static func colour_id(frac: float, building: bool) -> int:
	if building:
		return COL_BUILD
	if frac > 0.6:
		return COL_GREEN
	if frac >= 0.3:
		return COL_YELLOW
	return COL_RED


func update(_dt: float) -> void:
	if _v == null or _buf == null:
		return
	_buf.begin()
	if mode != Mode.NEVER:
		var shown: Dictionary = {}
		var sel: PackedInt32Array = _v.selection.selection() if _v.selection != null else PackedInt32Array()
		for id: int in sel:
			_bar(id, 1.0, shown)
		if _hover >= 0:
			_bar(_hover, 1.0, shown)
		if mode == Mode.ALWAYS:
			for ve: ViewEntity in _v.entities():
				_bar(ve.id, 1.0, shown)
		elif mode == Mode.DAMAGED:
			var stale: Array = []
			for id2: int in _marks:
				var age: int = _v.tick - (_marks[id2] as int)
				if age > SHOW_TICKS:
					stale.append(id2)
					continue
				var fade: float = 1.0
				if age > SHOW_TICKS - FADE_TICKS:
					fade = clampf(float(SHOW_TICKS - age) / float(FADE_TICKS), 0.0, 1.0)
				_bar(id2, fade, shown, true)
			for s: Variant in stale:
				_marks.erase(s)
			var done: Array[int] = []
			for id3: int in _v.phase_ids:
				var sv: ViewStructure = _v.entity_view(id3) as ViewStructure
				if sv == null or sv.phase == ViewConsts.PH_ACTIVE:
					done.append(id3)
				else:
					_bar(id3, 1.0, shown)
			for d: int in done:
				_v.phase_ids.erase(d)
	_buf.commit()
	count = _buf.count


## Pushes one bar unless it was already shown or must not be visible.
func _bar(id: int, fade: float, shown: Dictionary, only_own: bool = false) -> void:
	if shown.has(id):
		return
	var ve: ViewEntity = _v.entity_view(id)
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE or ve.kind == SimEntity.Kind.WRECK or ve.max_hp <= 0:
		return
	var enemy: bool = ve.owner >= 0 and ve.owner != _v.local_pid and _v.sim != null and not _v.sim.are_allied(_v.local_pid, ve.owner)
	if only_own and enemy and not (_v.selection != null and _v.selection.selection().has(id)):
		# damaged-recently bars are for the local team; enemies show only when selected or hovered
		if id != _hover:
			return
	shown[id] = true
	var building: bool = false
	var frac: float = clampf(float(ve.hp) / float(ve.max_hp), 0.0, 1.0)
	if ve is ViewStructure and (ve as ViewStructure).phase != ViewConsts.PH_ACTIVE:
		building = true
		frac = clampf((ve as ViewStructure).build, 0.0, 1.0)
	var pos: Vector3 = Vector3(ve.wx, ve.wy + ve.height_m + ANCHOR_ABOVE_M - ve.sink_m, ve.wz)
	var col: Color = ve.team_color
	var shape: int = ViewTeamColors.pip_shape(maxi(ve.team_index, 0))
	col.a = float(shape + (8 if ViewTeamColors.pip_outlined(maxi(ve.team_index, 0)) else 0)) / 16.0
	var members: int = clampi(ve.members - 1, 0, 15) if ve.members > 1 else 0
	var b: Basis = Basis.IDENTITY.scaled(Vector3(fade, fade, fade))
	_buf.push(Transform3D(b, pos), col, Color(frac, width_px(ve), float(colour_id(frac, building)), float(members)))
