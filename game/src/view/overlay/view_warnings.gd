class_name ViewWarnings
extends Node3D
## Strategic warning zones (render spec 5.9.5, art_direction 5.9.4, task VIEW-O3): superweapon and strike-power warnings drawn on the
## ground for every player they affect (`SimStrategicSystem.warnings_affecting(pid, out)`: the owner's team, players with an entity within
## 3 cells of the zone, everybody for the Trident). Warnings IGNORE the fog and decoys. Geometry comes from the SimWarning record and the
## compiled superweapon (`sim.data.superweapons[src_idx]`):
##   Atlas    three impact circles on the committed axis (packet offsets) joined by a dashed axis
##   Helios   the beam capsule with flowing chevrons and, in execution, a sweep bar that traverses it
##   Horizon  the strike capsule plus three impact circles that flash when their packet lands
##   Perun    outer fragmentation ring plus the solid core
##   Aurora, Tempest (plus the approach trail), Dragonfall, Trident, strike powers, Wideband scan: a circle
## WARN amber for the owner's team, DANGER red for hostile viewers; dashed outline vs solid outline + corner ticks (never colour alone).
## A screen-constant countdown label sits at the centre. Cancelled warnings flash and fade. Presentation only.

const SHADER_PATH: String = "res://assets/shaders/warning.gdshader"
const SYNC_S: float = 0.1
const FADE_IN_S: float = 0.25
const FADE_OUT_S: float = 0.45
const LIFT_M: float = 0.24
const MODE_AREA: int = 0
const MODE_CORE: int = 1
const MODE_IMPACT: int = 2
const MODE_LINE: int = 3
const MODE_TRAIL: int = 4
const LABEL_PIXEL_SIZE: float = 0.00058
const WARN_COL: Color = Color(1.0, 0.72, 0.15)
const DANGER_COL: Color = Color(1.0, 0.22, 0.18)
## Countdown text fills: lighter than the disc colours so the digits do not vanish into them (the outline is dark).
const LABEL_WARN_COL: Color = Color(1.0, 0.95, 0.72)
const LABEL_HOSTILE_COL: Color = Color(1.0, 0.86, 0.84)
const BEACON_S: float = 0.9  ## the light column is re-issued in short pieces so a cancelled warning does not leave one behind

class Prim extends RefCounted:
	var mode: int = 0
	var center: Vector2 = Vector2.ZERO  ## world xz metres
	var yaw: float = 0.0
	var hl: float = 0.0
	var r: float = 1.0
	var delay_ticks: int = 0  ## impact circles: ticks after exec_tick when the packet lands
	var node: MeshInstance3D = null
	var mat: ShaderMaterial = null


class Rec extends RefCounted:
	var id: int = 0
	var kind: int = 0
	var src_idx: int = 0
	var owner: int = 0
	var hostile: bool = false
	var start_tick: int = 0
	var exec_tick: int = 0
	var end_tick: int = 0
	var phase: int = 0
	var prims: Array[Prim] = []
	var label: Label3D = null
	var fade: float = 0.0
	var dying: bool = false
	var cancelled: bool = false
	var seen: int = 0
	var beacon_t: float = 1.0e9
	var traverse_ticks: int = 240
	var center: Vector3 = Vector3.ZERO


var count: int = 0  ## warnings drawn last update
var created: int = 0

var _v: ViewWorld = null
var _recs: Dictionary = {}  # warning id -> Rec
var _shader: Shader = null
var _t: float = 1.0e9
var _stamp: int = 0
var _tmp: Array = []


func setup(v: ViewWorld) -> void:
	_v = v
	_shader = load(SHADER_PATH) as Shader


## Re-reads the warning list at the next update (an EVT_WARNING / EXEC / CANCELLED event arrived).
func request_sync() -> void:
	_t = 1.0e9


func warning_ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: Variant in _recs:
		out.append(k as int)
	out.sort()
	return out


func rec_of(warning_id: int) -> Rec:
	return _recs.get(warning_id) as Rec


func clear() -> void:
	for k: Variant in _recs.keys():
		_free(_recs[k] as Rec)
	_recs.clear()
	count = 0


func update(dt: float) -> void:
	if _v == null or _v.sim == null or _v.sim.strategic == null:
		return
	_t += dt
	if _t >= SYNC_S:
		_t = 0.0
		_sync()
	var now: float = float(_v.tick) + _v.alpha
	var gone: Array[int] = []
	var n: int = 0
	for k: Variant in _recs:
		var rec: Rec = _recs[k] as Rec
		var target: float = 0.0 if rec.dying else 1.0
		var rate: float = (1.0 / (FADE_OUT_S if not rec.cancelled else 0.7)) if rec.dying else (1.0 / FADE_IN_S)
		rec.fade = move_toward(rec.fade, target, dt * rate)
		if rec.dying and rec.fade <= 0.0:
			gone.append(k as int)
			continue
		_animate(rec, now)
		rec.beacon_t += dt
		if rec.beacon_t >= BEACON_S and not rec.dying and not _v.fx.event_router_active and rec.phase == SimEconConst.AT_WARNING:
			rec.beacon_t = 0.0
			_v.fx.column(&"beacon", rec.center, 0.6, 60.0, BEACON_S + 0.2)
		n += 1
	for id: int in gone:
		_free(_recs[id] as Rec)
		_recs.erase(id)
	count = n


func _sync() -> void:
	_stamp += 1
	var live: Array = []
	if _v.observer:
		for w: SimWarning in _v.sim.strategic.warnings:
			if w.phase <= SimEconConst.AT_EXEC:
				live.append(w)
	else:
		_v.sim.strategic.warnings_affecting(_v.local_pid, live)
	for wv: Variant in live:
		var w2: SimWarning = wv as SimWarning
		var rec: Rec = _recs.get(w2.id) as Rec
		if rec == null:
			rec = _create(w2)
			_recs[w2.id] = rec
		rec.seen = _stamp
		rec.phase = w2.phase
		rec.exec_tick = w2.exec_tick
		rec.end_tick = w2.end_tick
		rec.dying = false
	for k: Variant in _recs:
		var r2: Rec = _recs[k] as Rec
		if r2.seen == _stamp:
			continue
		if not r2.dying:
			r2.dying = true
			var w3: SimWarning = _v.sim.strategic.get_warning(r2.id)
			if w3 != null:
				r2.phase = w3.phase
				r2.cancelled = w3.phase == SimEconConst.AT_CANCELLED


## Geometry plan of a warning record: an array of Prim (mode, centre, yaw, half length, radius, delay). No nodes are created.
func plan(w: SimWarning) -> Array[Prim]:
	var out: Array[Prim] = []
	var m: float = ViewConsts.M_PER_UNIT
	var a: Vector2 = Vector2(float(w.x), float(w.y)) * m
	var b: Vector2 = Vector2(float(w.x2), float(w.y2)) * m
	var r: float = float(w.radius) * m
	var sw: DefSuperweapon = null
	if w.kind == SimEconConst.WK_SUPER and w.src_idx >= 0 and w.src_idx < _v.sim.data.superweapons.size():
		sw = _v.sim.data.superweapons[w.src_idx]
	if w.width > 0:
		var mid: Vector2 = (a + b) * 0.5
		var dir: Vector2 = (b - a)
		var half: float = dir.length() * 0.5
		var yaw: float = atan2(dir.y, dir.x)
		var axis: Vector2 = dir.normalized() if half > 0.001 else Vector2.RIGHT
		if sw != null and sw.action_kind == DefEnums.SwAction.KINETIC_VOLLEY:
			out.append(_prim(MODE_TRAIL, mid, yaw, half, 0.45))
			for pk: DefImpactPacket in sw.packets:
				var p: Prim = _prim(MODE_IMPACT, mid + axis * (float(pk.offset_x) * m), yaw, 0.0, float(pk.radius) * m)
				p.delay_ticks = pk.delay_t
				out.append(p)
		elif sw != null and sw.action_kind == DefEnums.SwAction.RAIL_STRIKE:
			out.append(_prim(MODE_LINE, mid, yaw, half, r))
			for pk2: DefImpactPacket in sw.packets:
				var p2: Prim = _prim(MODE_IMPACT, mid + axis * (float(pk2.offset_x) * m), yaw, 0.0, float(pk2.radius) * m)
				p2.delay_ticks = pk2.delay_t
				out.append(p2)
		else:
			out.append(_prim(MODE_LINE, mid, yaw, half, r))
		return out
	# circle warnings
	if sw != null and sw.action_kind == DefEnums.SwAction.BUNKER_BUSTER and sw.packets.size() >= 2:
		var core_r: float = 0.0
		for pk3: DefImpactPacket in sw.packets:
			core_r = maxf(core_r, float(pk3.radius) * m) if pk3.radius < w.radius else core_r
		out.append(_prim(MODE_AREA, a, 0.0, 0.0, r))
		out.append(_prim(MODE_CORE, a, 0.0, 0.0, maxf(core_r, 1.0)))
		return out
	out.append(_prim(MODE_AREA, a, 0.0, 0.0, r))
	if sw != null and sw.action_kind == DefEnums.SwAction.DRONE_SWARM and b.distance_to(a) > 1.0:
		var d: Vector2 = a - b
		out.append(_prim(MODE_TRAIL, (a + b) * 0.5, atan2(d.y, d.x), d.length() * 0.5, 0.5))
	return out


static func _prim(mode_: int, center: Vector2, yaw: float, hl: float, r: float) -> Prim:
	var p: Prim = Prim.new()
	p.mode = mode_
	p.center = center
	p.yaw = yaw
	p.hl = hl
	p.r = r
	return p


func _create(w: SimWarning) -> Rec:
	var rec: Rec = Rec.new()
	rec.id = w.id
	rec.kind = w.kind
	rec.src_idx = w.src_idx
	rec.owner = w.owner
	rec.start_tick = w.start_tick
	rec.exec_tick = w.exec_tick
	rec.end_tick = w.end_tick
	rec.phase = w.phase
	var team: int = _v.sim.team_of(_v.local_pid) if _v.local_pid >= 0 else -1
	rec.hostile = not _v.observer and _v.sim.team_of(w.owner) != team
	if w.kind == SimEconConst.WK_SUPER and w.src_idx >= 0 and w.src_idx < _v.sim.data.superweapons.size():
		var sw: DefSuperweapon = _v.sim.data.superweapons[w.src_idx]
		if sw.action_kind == DefEnums.SwAction.INTERCEPT_ZONE:
			rec.hostile = false  # the dome is defensive: amber for everyone
		if sw.action_kind == DefEnums.SwAction.BEAM_SWEEP:
			rec.traverse_ticks = int(sw.params.get("traverse_t", 240))
	if w.kind == SimEconConst.WK_SCAN:
		rec.hostile = false
	rec.prims = plan(w)
	var cen: Vector2 = Vector2(float(w.x) + float(w.x2), float(w.y) + float(w.y2)) * 0.5 * ViewConsts.M_PER_UNIT
	rec.center = Vector3(cen.x, _v.ground_at(cen.x, cen.y), cen.y)
	for p: Prim in rec.prims:
		_build_node(rec, p)
	rec.label = _make_label(rec)
	add_child(rec.label)
	rec.label.position = rec.center + Vector3(0.0, 2.2, 0.0)
	created += 1
	return rec


func _build_node(rec: Rec, p: Prim) -> void:
	p.mat = ShaderMaterial.new()
	p.mat.shader = _shader
	p.mat.render_priority = 6 + (1 if p.mode == MODE_IMPACT else 0)
	p.mat.set_shader_parameter(&"mode", p.mode)
	p.mat.set_shader_parameter(&"warn_col", WARN_COL)
	p.mat.set_shader_parameter(&"danger_col", DANGER_COL)
	p.mat.set_shader_parameter(&"geom", Vector4(p.hl, p.r, 0.0, 0.0))
	p.node = MeshInstance3D.new()
	var margin: float = 1.6
	var half: Vector2 = Vector2(p.hl + p.r + margin, p.r + margin)
	var step: float = clampf(maxf(half.x, half.y) / 40.0, 0.6, 1.0)
	p.node.mesh = ViewGroundMesh.build_flat(_v, p.center, p.yaw, half, step, LIFT_M)
	p.node.material_override = p.mat
	p.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.node.layers = ViewLayers.MASK_OVERLAYS
	add_child(p.node)
	if rec == null:
		return


func _make_label(rec: Rec) -> Label3D:
	var l: Label3D = Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.font_size = 80
	l.pixel_size = LABEL_PIXEL_SIZE
	l.outline_size = 28  # a thick dark outline keeps the countdown readable on the amber / red disc
	l.outline_modulate = Color(0.04, 0.03, 0.03, 1.0)
	l.modulate = LABEL_HOSTILE_COL if rec.hostile else LABEL_WARN_COL
	l.render_priority = 12
	l.layers = ViewLayers.MASK_OVERLAYS
	l.text = ""
	return l


func _animate(rec: Rec, now: float) -> void:
	var span: float = maxf(float(rec.exec_tick - rec.start_tick), 1.0)
	var remaining: float = clampf((float(rec.exec_tick) - now) / span, 0.0, 1.0)
	var phase_f: float = float(rec.phase)
	if rec.dying:
		phase_f = 3.0 if rec.cancelled else 2.0
	var t: float = _v.time
	var exec_age: float = now - float(rec.exec_tick)
	for p: Prim in rec.prims:
		var hit: float = 0.0
		var sweep: float = 0.0
		if p.mode == MODE_IMPACT:
			var landed: float = exec_age - float(p.delay_ticks)
			hit = clampf(1.0 - landed / 30.0, 0.0, 1.0) if landed >= 0.0 else 0.0
		elif p.mode == MODE_LINE and exec_age >= 0.0:
			sweep = clampf(exec_age / float(maxi(rec.traverse_ticks, 1)), 0.0, 1.0)
		p.mat.set_shader_parameter(&"st", Vector4(t, remaining, phase_f, 1.0 if rec.hostile else 0.0))
		p.mat.set_shader_parameter(&"geom", Vector4(p.hl, p.r, hit if p.mode == MODE_IMPACT else sweep, 0.0))
		p.mat.set_shader_parameter(&"fade", rec.fade)
	var secs: float = maxf((float(rec.exec_tick) - now) * 0.05, 0.0)
	if rec.phase == SimEconConst.AT_WARNING and not rec.dying:
		rec.label.text = ("!! %.1f" if rec.hostile else "%.1f") % secs
	elif rec.dying and rec.cancelled:
		rec.label.text = "X"
	else:
		rec.label.text = "!!"
	var lc: Color = LABEL_HOSTILE_COL if rec.hostile else LABEL_WARN_COL
	lc.a = rec.fade
	rec.label.modulate = lc
	rec.label.outline_modulate = Color(0.04, 0.03, 0.03, rec.fade)


func _free(rec: Rec) -> void:
	for p: Prim in rec.prims:
		if p.node != null:
			p.node.queue_free()
			p.node = null
	if rec.label != null:
		rec.label.queue_free()
		rec.label = null
