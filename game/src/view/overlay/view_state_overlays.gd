class_name ViewStateOverlays
extends Node3D
## Owner of the VIEW-W2 / VIEW-O3 state views and their frame contract: scaffolds, rubble, ghosts, zones, status marks, warnings,
## float text, the debug overlay and the FX port. ViewWorld creates ONE of these, calls setup(v) at the end of its build, consume(events)
## right after the router and update(dt) with the overlays (render spec 3.0 steps 9-10). It also runs the structure damage emitters
## (smoke below 66 % hp, fire below 33 %, capped at DAMAGE_CAP scene-wide, the nearest to the camera win, re-ranked at 2 Hz) and turns
## income / sale events into floating numbers. Presentation only.

const DAMAGE_CAP: int = 24
const RANK_S: float = 0.5
const SMOKE_S: float = 0.42
const FIRE_S: float = 0.34
const WRECK_SCAN_S: float = 0.25
const WRECK_FIRE_S: float = 14.0
const WRECK_THIN_S: float = 1.5
const WRECK_SMOKE_END_S: float = 8.0

var fx: ViewFxPort = ViewFxPort.new()
var scaffolds: ViewScaffolds = null
var rubble: ViewRubble = null
var ghosts: ViewGhosts = null
var zones: ViewZones = null
var marks: ViewStatusMarks = null
var warnings: ViewWarnings = null
var float_text: ViewFloatText = null
var debug: ViewDebugOverlay = null
## true: this class emits the structure damage smoke / fire, unless an FX event router is attached (ViewFxPort.event_router_active).
var owns_structure_damage_fx: bool = true
## true: this class emits the wreck smoke / embers (wreck_start for the first WRECK_FIRE_S, thin smoke until WRECK_SMOKE_END_S before
## the expiry), unless an FX event router is attached.
var owns_wreck_fx: bool = true

var damage_emitters: int = 0  ## structures emitting last rank
var ms_last: float = 0.0

var _v: ViewWorld = null
var _rank_t: float = 1.0e9
var _dmg: Array[ViewStructure] = []
var _dmg_acc: Dictionary = {}  # structure id -> [smoke accumulator, fire accumulator]
var _built: bool = false
var _wreck_t: float = 0.0
var _wreck_fire: Dictionary = {}  # wreck id -> true once wreck_start ran
var _wreck_thin: Dictionary = {}  # wreck id -> next thin smoke time (view seconds)


func setup(v: ViewWorld) -> void:
	if _built:
		return
	_built = true
	_v = v
	scaffolds = _child(ViewScaffolds.new(), "Scaffolds") as ViewScaffolds
	rubble = _child(ViewRubble.new(), "Rubble") as ViewRubble
	ghosts = _child(ViewGhosts.new(), "Ghosts") as ViewGhosts
	zones = _child(ViewZones.new(), "Zones") as ViewZones
	marks = _child(ViewStatusMarks.new(), "StatusMarks") as ViewStatusMarks
	warnings = _child(ViewWarnings.new(), "Warnings") as ViewWarnings
	float_text = _child(ViewFloatText.new(), "FloatText") as ViewFloatText
	debug = _child(ViewDebugOverlay.new(), "Debug") as ViewDebugOverlay
	scaffolds.setup(v)
	rubble.setup(v)
	ghosts.setup(v)
	zones.setup(v)
	marks.setup(v)
	warnings.setup(v)
	float_text.setup(v)
	debug.setup(v)


func _child(n: Node3D, nm: String) -> Node3D:
	n.name = nm
	add_child(n)
	return n


func is_built() -> bool:
	return _built


## Reacts to one frame of events (after ViewEventRouter.process). Records are [type, tick, x, y, a, b, c, d, e, f].
func consume(events: PackedInt32Array) -> void:
	if not _built:
		return
	var o: int = 0
	var n: int = events.size()
	while o + SimEvent.STRIDE <= n:
		var code: int = events[o]
		match code:
			SimEconConst.EVT_CREDITS_GAINED:
				if events[o + 4] == _v.local_pid and events[o + 5] > 0:
					var key: int = events[o + 2] * 73856093 ^ events[o + 3] * 19349663
					var p: Vector2 = Vector2(float(events[o + 2]), float(events[o + 3])) * ViewConsts.M_PER_UNIT
					float_text.add_income(key, events[o + 5], Vector3(p.x, _v.ground_at(p.x, p.y), p.y))
			SimEconConst.EVT_STRUCTURE_SOLD:
				if events[o + 4] == _v.local_pid and events[o + 6] > 0:
					var q: Vector2 = Vector2(float(events[o + 2]), float(events[o + 3])) * ViewConsts.M_PER_UNIT
					float_text.popup("+$%d" % events[o + 6], Vector3(q.x, _v.ground_at(q.x, q.y) + 3.0, q.y), ViewFloatText.GOLD)
			SimEconConst.EVT_WARNING, SimEconConst.EVT_SW_EXEC_START, SimEconConst.EVT_SW_CANCELLED, SimEconConst.EVT_SW_DONE:
				warnings.request_sync()
			SimZoneConsts.EV_ZONE_SPAWNED, SimZoneConsts.EV_ZONE_ENDED:
				zones.request_sync()
			SimAbilityConsts.EV_GHOST_ADDED, SimAbilityConsts.EV_GHOST_REMOVED:
				ghosts.invalidate()
			_:
				pass
		o += SimEvent.STRIDE


## Per rendered frame, after the entity loop.
func update(dt: float) -> void:
	if not _built:
		return
	var t0: int = Time.get_ticks_usec()
	scaffolds.update(dt)
	rubble.update(dt)
	ghosts.update(dt)
	zones.update(dt)
	marks.update(dt)
	warnings.update(dt)
	float_text.update(dt)
	debug.update(dt)
	fx.event_router_active = _v.router != null and _v.router.extra_handler.is_valid()
	if owns_structure_damage_fx and fx.active() and not fx.event_router_active:
		_damage_fx(dt)
	if owns_wreck_fx and fx.active() and not fx.event_router_active:
		_wreck_fx(dt)
	ms_last = float(Time.get_ticks_usec() - t0) / 1000.0


func clear() -> void:
	if not _built:
		return
	rubble.clear()
	ghosts.clear()
	zones.clear()
	warnings.clear()
	float_text.clear()
	_dmg.clear()
	_dmg_acc.clear()


# ---- structure damage emitters ---------------------------------------------------------------------------------------

func _damage_fx(dt: float) -> void:
	_rank_t += dt
	if _rank_t >= RANK_S:
		_rank_t = 0.0
		_rank()
	for st: ViewStructure in _dmg:
		if st.active_idx < 0 or st.dead or st.vs == ViewConsts.VS_HIDDEN:
			continue
		var acc: Array = _dmg_acc.get(st.id, [0.0, 0.0]) as Array
		acc[0] = (acc[0] as float) + dt
		acc[1] = (acc[1] as float) + dt
		var top: float = st.base_y() + st.top_m() * 0.8
		var ext: Vector2 = st.extent_m()
		if (acc[0] as float) >= SMOKE_S:
			acc[0] = 0.0
			var j: int = _v.frame_no * 31 + st.id * 17
			var jx: float = (float(j % 7) / 6.0 - 0.5) * ext.x * 0.4
			var jz: float = (float((j / 7) % 7) / 6.0 - 0.5) * ext.y * 0.4
			var size: float = (2.6 if st.damage_stage == 1 else 4.0) * clampf(sqrt(ext.x * ext.y) / 6.0, 0.7, 1.6)
			_fx_pos(st, jx, top, jz, size)
		if st.damage_stage >= 2 and (acc[1] as float) >= FIRE_S:
			acc[1] = 0.0
			var j2: int = _v.frame_no * 13 + st.id * 29
			var fx_x: float = (float(j2 % 5) / 4.0 - 0.5) * ext.x * 0.5
			var fx_z: float = (float((j2 / 5) % 5) / 4.0 - 0.5) * ext.y * 0.5
			fx.sprites(&"fire", Vector3(st.wx + fx_x, top - 0.6, st.wz + fx_z), 1.1, 0.8, 0.9, 0)
		_dmg_acc[st.id] = acc


func _fx_pos(st: ViewStructure, jx: float, top: float, jz: float, size: float) -> void:
	fx.puff(&"puff_smoke", Vector3(st.wx + jx, top, st.wz + jz), size, 4.5, 0.55 if st.damage_stage == 1 else 0.8)


func _rank() -> void:
	_dmg.clear()
	var cand: Array[ViewStructure] = []
	for ve: ViewEntity in _v.entities():
		if ve is ViewStructure:
			var st: ViewStructure = ve as ViewStructure
			if st.damage_stage > 0 and not st.dead and st.vs != ViewConsts.VS_HIDDEN and st.in_view and st.phase == ViewConsts.PH_ACTIVE:
				cand.append(st)
	var focus: Vector3 = Vector3.ZERO
	if _v.camera != null:
		focus = _v.camera.current_focus()
	if cand.size() > DAMAGE_CAP:
		cand.sort_custom(func(a: ViewStructure, b: ViewStructure) -> bool:
			return Vector2(a.wx - focus.x, a.wz - focus.z).length_squared() < Vector2(b.wx - focus.x, b.wz - focus.z).length_squared())
		cand.resize(DAMAGE_CAP)
	_dmg = cand
	damage_emitters = _dmg.size()
	var keep: Dictionary = {}
	for st2: ViewStructure in _dmg:
		keep[st2.id] = true
	for k: Variant in _dmg_acc.keys():
		if not keep.has(k):
			_dmg_acc.erase(k)


# ---- wreck smoke and embers --------------------------------------------------------------------------------------------

## wreck_start (smoke + embers loop, 12 s) when a wreck first shows younger than WRECK_FIRE_S, then a thin smoke puff every 1.5 s until
## 8 s before the wreck expires. Scanned at 4 Hz over the visible wreck records.
func _wreck_fx(dt: float) -> void:
	_wreck_t += dt
	if _wreck_t < WRECK_SCAN_S:
		return
	_wreck_t = 0.0
	var now_s: float = _v.time
	var seen: Dictionary = {}
	for ve: ViewEntity in _v.entities():
		if ve.kind != SimEntity.Kind.WRECK or ve.vs == ViewConsts.VS_HIDDEN or ve.dead or not ve.in_view:
			continue
		seen[ve.id] = true
		var age_s: float = (float(_v.tick) - float(ve.born_tick)) * 0.05
		var left_s: float = (float(ve.expires) - float(_v.tick)) * 0.05 if ve.expires > 0 else 1.0e6
		var pos: Vector3 = Vector3(ve.wx, ve.wy + 0.8, ve.wz)
		if not _wreck_fire.has(ve.id):
			_wreck_fire[ve.id] = true
			if age_s < WRECK_FIRE_S:
				var sc: float = clampf(ve.radius_m / 1.6, 0.5, 1.6)
				fx.spawn(&"wreck_start", pos, Vector3.ZERO, sc)
				continue
		if age_s >= WRECK_FIRE_S and left_s > WRECK_SMOKE_END_S and now_s >= (_wreck_thin.get(ve.id, 0.0) as float):
			_wreck_thin[ve.id] = now_s + WRECK_THIN_S
			fx.puff(&"puff_smoke", pos + Vector3(0.0, 0.6, 0.0), 1.8 * clampf(ve.radius_m / 1.6, 0.6, 1.5), 3.0, 0.32)
	if _wreck_fire.size() > 256:
		for k: Variant in _wreck_fire.keys():
			if not seen.has(k):
				_wreck_fire.erase(k)
				_wreck_thin.erase(k)
