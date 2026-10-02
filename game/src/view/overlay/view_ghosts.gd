class_name ViewGhosts
extends Node3D
## Remembered enemy structures under fog (render spec 5.10 "Remembered structures", 5.3): the sim keeps a SimGhost per structure the
## local team once saw and no longer sees (`sim.fog.ghosts(pid)`, `ghost_version(pid)`). Each record is drawn as the model of that def
## in the owner's style with UF_GHOST (desaturated, dark, frozen animation) and the damage look of its remembered hp. Reconciled on
## a ghost_version change or every RECONCILE_S. A ghost never draws while the live structure record is visible. Presentation only.

const RECONCILE_S: float = 0.5

class Rec extends RefCounted:
	var eid: int = 0
	var st: ViewStructure = null
	var hp_pct: int = 100
	var seen_tick: int = 0
	var def_idx: int = -1
	var cell_x: int = 0
	var cell_y: int = 0


var count: int = 0  ## ghosts drawn last update
var created: int = 0
var removed: int = 0

var _v: ViewWorld = null
var _recs: Dictionary = {}  # eid -> Rec
var _ver: int = -1
var _t: float = 1.0e9
var _local: int = -2


func setup(v: ViewWorld) -> void:
	_v = v


## Remembered structure ids currently drawn (ascending).
func ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: Variant in _recs:
		out.append(k as int)
	out.sort()
	return out


func has_ghost(eid: int) -> bool:
	return _recs.has(eid)


func ghost_view(eid: int) -> ViewStructure:
	var r: Rec = _recs.get(eid) as Rec
	return r.st if r != null else null


## Entity id of the remembered structure whose footprint contains the world point (x, z) in metres, -1 when none. For the picker
## (PICK_GHOSTS): a ghost is drawn only while its live record is hidden, so the point test skips ghosts that are not shown.
func ghost_at(wx: float, wz: float) -> int:
	for k: Variant in _recs:
		var r: Rec = _recs[k] as Rec
		var live: ViewEntity = _v.entity_view(r.eid)
		if live != null and live.vs != ViewConsts.VS_HIDDEN:
			continue
		var ext: Vector2 = r.st.extent_m() * 0.5
		if absf(wx - r.st.wx) <= ext.x and absf(wz - r.st.wz) <= ext.y:
			return r.eid
	return -1


## Forces a reconcile at the next update (local player changed, replay seek).
func invalidate() -> void:
	_ver = -1
	_t = 1.0e9


func update(dt: float) -> void:
	if _v == null or _v.sim == null:
		return
	if _v.local_pid != _local:
		_local = _v.local_pid
		clear()
	if _v.observer or _v.local_pid < 0 or _v.sim.fog == null:
		return
	_t += dt
	var ver: int = _v.sim.fog.ghost_version(_v.local_pid)
	if ver != _ver or _t >= RECONCILE_S:
		_ver = ver
		_t = 0.0
		reconcile()
	_show_hide()


func clear() -> void:
	for k: Variant in _recs.keys():
		_drop(k as int)
	_recs.clear()
	count = 0


func reconcile() -> void:
	var list: Array = _v.sim.fog.ghosts(_v.local_pid)
	var live: Dictionary = {}
	for gv: Variant in list:
		var g: SimGhost = gv as SimGhost
		if g == null:
			continue
		live[g.eid] = true
		var r: Rec = _recs.get(g.eid) as Rec
		if r == null or r.def_idx != g.def_idx:
			if r != null:
				_drop(g.eid)
			r = _make(g)
			if r == null:
				continue
			_recs[g.eid] = r
		_refresh(r, g)
	for k: Variant in _recs.keys():
		if not live.has(k):
			_drop(k as int)


func _make(g: SimGhost) -> Rec:
	var vd: ViewDef = _v.defs.def_for(SimEntity.Kind.STRUCTURE, g.def_idx)
	if vd == null or vd.placeholder:
		return null
	var roster: String = ""
	if g.owner >= 0 and g.owner < _v.sim.players.size():
		roster = _v.defs.roster_id(_v.sim.players[g.owner].roster_idx)
	var recipe: StringName = vd.recipe_id
	var style: StringName = _v.book.style_for_def(vd.id, roster)
	var model: ViewModel = _v.models.get_model(recipe, style, vd.scale_bp)
	var st: ViewStructure = ViewStructure.new()
	st.id = -g.eid  # never collides with a live record id
	st.kind = SimEntity.Kind.STRUCTURE
	st.def_idx = g.def_idx
	st.owner = g.owner
	st.vdef = vd
	st.recipe_id = recipe
	st.style_id = style
	st.model = model
	st.team_index = _v.sim.players[g.owner].color if g.owner >= 0 and g.owner < _v.sim.players.size() else -1
	st.team_color = ViewTeamColors.color(st.team_index)
	st.motion = ViewConsts.MOTION_STATIC
	st.height_m = maxf(model.info.height, 0.5)
	st.radius_m = maxf(vd.radius_m, 1.5)
	st.init_placement(g.x, g.y, g.facing)
	st.hp = 100
	st.max_hp = 100
	st.derive_flags()
	_v.backend.add(st, model, style, st.team_color, st.team_index)
	st.setup_structure(_v)
	st.flags |= ViewConsts.UF_GHOST
	st.always_active = false
	var r: Rec = Rec.new()
	r.eid = g.eid
	r.st = st
	r.def_idx = g.def_idx
	r.cell_x = g.x >> 10
	r.cell_y = g.y >> 10
	created += 1
	st.set_ghost(_v, g.hp_pct)
	_v.backend.set_visible(st, false)
	_v.backend.set_shadow(st, false)  # a memory casts no shadow
	return r


func _refresh(r: Rec, g: SimGhost) -> void:
	r.seen_tick = g.seen_tick
	if r.hp_pct != g.hp_pct:
		r.hp_pct = g.hp_pct
		r.st.set_ghost(_v, g.hp_pct)


func _drop(eid: int) -> void:
	var r: Rec = _recs.get(eid) as Rec
	if r == null:
		return
	_recs.erase(eid)
	if r.st != null:
		_v.backend.remove(r.st)
	removed += 1


## A ghost is hidden while its live record is visible (the fog test lags a few frames behind the sim's ghost list).
func _show_hide() -> void:
	var n: int = 0
	for k: Variant in _recs:
		var r: Rec = _recs[k] as Rec
		var live: ViewEntity = _v.entity_view(r.eid)
		var show: bool = live == null or live.vs == ViewConsts.VS_HIDDEN
		if r.st.rig != null:
			_v.backend.set_visible(r.st, show)
		if show:
			n += 1
	count = n
