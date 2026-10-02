class_name ViewStructure
extends ViewEntity
## Structures and neutral structures (render spec 4.5 / 5.2 structure state machine, art_direction 5.9.6). VIEW-W2 full version:
##   BUILDUP   the model rises out of the ground inside a scaffold cage (ViewScaffolds) with weld sparks and a dust ring;
##             completion flashes, cycles the door and rings.  SELLING is the same in reverse.
##   ACTIVE    door cycle on production, refinery unload arm while a collector is docked, radar spin, steam puffs, emissives
##             fade to 20 % over 0.4 s when the power fails (radars decelerate over 2 s) and come back the same way.
##   DAMAGE    stage 1 (< 66 % hp) smoke, stage 2 (< 33 %) fire (ViewStateOverlays emits, capped at 24 scene-wide); the shader
##             shows soot, paint loss and cracks from `damage` (UF_STRUCT).
##   DYING     shake and darken (0.35 s), then the model sinks into a rubble heap (ViewRubble) behind the building_collapse FX.
## Hooks other views call: begin_phase(), open_door(), on_state(). Presentation only: reads the sim through ViewSimReader.

const DEFAULT_BUILDUP_TICKS: int = 30
const DEFAULT_SELL_TICKS: int = 40
const DOOR_OPEN_S: float = 0.6
const DOOR_HOLD_S: float = 1.0
const DOOR_CLOSE_S: float = 0.6
const RADAR_RATE: float = 1.2
const RADAR_SPINUP_S: float = 1.0
const RADAR_SPINDOWN_S: float = 2.0
const SHAKE_M: float = 0.1
const SHAKE_S: float = 0.35  ## shake and darken before the collapse starts (7 ticks)
const COLLAPSE_S: float = 1.0  ## total time the record stays alive after DIED (shake + sink)
const POWER_FADE_S: float = 0.4
const WELD_INTERVAL_S: float = 0.3
const STEAM_INTERVAL_S: float = 0.6
const DOCK_CYCLE_S: float = 2.0  ## unload arm: 0.5 Hz
const REPAIR_TEXT_S: float = 1.0
const DAMAGE_ON_1: float = 0.66
const DAMAGE_ON_2: float = 0.33
const HYSTERESIS: float = 0.05

var phase: int = ViewConsts.PH_ACTIVE
var phase_t0: int = 0
var phase_ticks: int = DEFAULT_BUILDUP_TICKS
var footprint: Vector2i = Vector2i(1, 1)
var rot: int = 0
var door_t: float = 0.0
var door_dir: int = 0  ## 0 idle, +1 opening, -1 closing
var activity: float = 0.0  ## u_aux.y: door / unload arm 0..1
var powered: bool = true
var needs_power: bool = false
var power_fade: float = 0.0  ## u_anim.y: 0 powered .. 1 dark, eased over POWER_FADE_S
var damage_stage: int = 0  ## 0 none, 1 smoke (< 66 % hp), 2 fire (< 33 %)
var occupants: int = 0
var dock_busy: bool = false  ## a collector is docked (refinery)
var repairing: bool = false

var placeholder_scale: Vector3 = Vector3.ONE  ## stretches the placeholder box to the footprint until a structure recipe exists
var _door_hold: float = 0.0
var _has_radar: bool = false
var _has_door: bool = false
var _has_arm: bool = false
var _base_y: float = 0.0
var _vw: ViewWorld = null
var _weld_acc: float = 0.0
var _weld_i: int = 0
var _steam_acc: float = 0.0
var _dock_t: float = 0.0
var _collapse_t0: float = -1.0
var _repair_acc: int = 0
var _repair_t: float = 0.0
var _hp_seen: int = -1
var _done_flash: bool = false
var _sunk: bool = false
var _has_steam: bool = false


func setup_structure(v: ViewWorld) -> void:
	_vw = v
	footprint = Vector2i(maxi(vdef.fp_w, 1), maxi(vdef.fp_h, 1))
	needs_power = vdef.needs_power
	_tilt = 0.0
	if model != null:
		_has_radar = model.info.has_part(ViewMeshBuilder.Part.RADAR)
		_has_door = model.info.has_part(ViewMeshBuilder.Part.DOOR)
		_has_arm = model.info.has_part(ViewMeshBuilder.Part.SLIDE_Z) or model.info.has_part(ViewMeshBuilder.Part.SLIDE_Y)
		_has_steam = model.info.has_socket(&"steam0")
		if model.info.footprint != Vector2i.ZERO and vdef.fp_w <= 1 and vdef.fp_h <= 1:
			footprint = model.info.footprint
	if model != null and model.placeholder:
		var box: Vector3 = model.info.rest_aabb.size
		var fw_m: float = float(footprint.x) * ViewConsts.CELL_M - 0.5
		var fh_m: float = float(footprint.y) * ViewConsts.CELL_M - 0.5
		placeholder_scale = Vector3(fw_m / maxf(box.x, 0.1), 2.4, fh_m / maxf(box.z, 0.1))
		height_m = model.info.height * placeholder_scale.y
	rot = ViewConsts.struct_rot(facing_cur) if vdef.rotatable else 0
	yaw = -float(rot) * PI * 0.5
	always_active = _has_radar
	derive_flags()
	_layout(v)


## Footprint centre, mean ground height (centre + 4 corners), sunk into the ground by the build phase.
func _layout(v: ViewWorld) -> void:
	wx = float(x_cur) * ViewConsts.M_PER_UNIT
	wz = float(y_cur) * ViewConsts.M_PER_UNIT
	var hx: float = float(footprint.x) * ViewConsts.CELL_M * 0.5
	var hz: float = float(footprint.y) * ViewConsts.CELL_M * 0.5
	var g: float = v.ground_at(wx, wz)
	g += v.ground_at(wx - hx, wz - hz) + v.ground_at(wx + hx, wz - hz) + v.ground_at(wx - hx, wz + hz) + v.ground_at(wx + hx, wz + hz)
	_base_y = g / 5.0 + ViewConsts.GROUND_LIFT_M
	wy = _base_y
	_snap = false
	_placed = false
	_dirty = true


## Footprint extent in metres after the placement rotation (x, z), plinth margin included.
func extent_m() -> Vector2:
	var w: float = float(footprint.x) * ViewConsts.CELL_M
	var d: float = float(footprint.y) * ViewConsts.CELL_M
	return Vector2(d, w) if (rot & 1) == 1 else Vector2(w, d)


## Static remembered record (ViewGhosts): placed once, frozen (UF_GHOST), damage look from the remembered hp percentage.
func set_ghost(v: ViewWorld, hp_pct: int) -> void:
	_vw = v
	hp = hp_pct
	max_hp = 100
	_damage_channel()
	powered = true
	vs = ViewConsts.VS_GHOST
	always_active = false
	flags = flags | ViewConsts.UF_GHOST | ViewConsts.UF_STRUCT
	if not _placed:
		_layout(v)
		_place(v)
		_placed = true
	_dirty = false
	_push(v)


func base_y() -> float:
	return _base_y


## Model height as rendered (placeholder stretch included).
func top_m() -> float:
	return height_m


func begin_phase(ph: int, tick: int, ticks: int) -> void:
	var was: int = phase
	phase = ph
	phase_t0 = tick
	phase_ticks = maxi(ticks, 1)
	always_active = ph != ViewConsts.PH_ACTIVE or _has_radar
	_done_flash = false
	_sunk = false
	if ph == ViewConsts.PH_BUILDUP:
		build = 0.0
		sink_m = height_m + 1.5
		_weld_acc = WELD_INTERVAL_S
		_fx_dust(false)
	elif ph == ViewConsts.PH_SELLING:
		build = 1.0
		_fx_dust(false)
	if _vw != null and ph != ViewConsts.PH_ACTIVE:
		_vw.note_phase(self)
		if _vw.scaffolds != null:
			_vw.scaffolds.track(self)
	if was != ph:
		_dirty = true


func on_state(st: int, value: int, ticks: int) -> void:
	super.on_state(st, value, ticks)
	if st == ST_SELLING:
		begin_phase(ViewConsts.PH_SELLING, phase_t0, ticks if ticks > 0 else DEFAULT_SELL_TICKS)


## Ownership changed (capture): the plate and pennant take the new colour (material swap by ViewWorld) with a white flash.
func on_captured(v: ViewWorld) -> void:
	flash = 1.0
	_dirty = true
	var c: Vector3 = Vector3(wx, _base_y + maxf(height_m, 1.0) * 0.6, wz)
	v.fx.ring(&"ring_add", Vector3(wx, _base_y + 0.3, wz), maxf(extent_m().x, extent_m().y) * 0.6, 0.5, 0)
	v.fx.spawn(&"capture_flash", c, Vector3.ZERO, 1.0)


func open_door() -> void:
	door_dir = 1
	_door_hold = 0.0


## u_state flags: the base set plus UF_STRUCT; the unpowered look is held while the fade runs (so it eases both ways).
func derive_flags() -> void:
	super.derive_flags()
	var f: int = flags | ViewConsts.UF_STRUCT
	f &= ~ViewConsts.UF_UNPOWERED
	if needs_power and power_fade > 0.001:
		f |= ViewConsts.UF_UNPOWERED
	flags = f


## Damage channel of the structure shader: soot from 66 % hp, paint loss from about 50 %, cracks and embers below 25 %.
func _damage_channel() -> void:
	if max_hp <= 0:
		damage = 0.0
		return
	var frac: float = float(hp) / float(max_hp)
	damage = clampf((0.85 - frac) / 0.85, 0.0, 1.0)


func sample(v: ViewWorld, e: SimEntity, shift: bool) -> void:
	var was_hp: int = hp
	super.sample(v, e, shift)
	_vw = v
	powered = (sim_flags & SimFlags.F_POWERED) != 0 or phase != ViewConsts.PH_ACTIVE
	dock_busy = ViewSimReader.dock_occupied(e)
	repairing = ViewSimReader.repair_on(e)
	var frac: float = float(hp) / float(maxi(max_hp, 1))
	if max_hp > 0:
		if damage_stage < 2 and frac < DAMAGE_ON_2:
			damage_stage = 2
		elif damage_stage < 1 and frac < DAMAGE_ON_1:
			damage_stage = 1
		elif damage_stage == 2 and frac > DAMAGE_ON_2 + HYSTERESIS:
			damage_stage = 1
		elif damage_stage == 1 and frac > DAMAGE_ON_1 + HYSTERESIS:
			damage_stage = 0
	# repair numbers: hp gained while active and owned by the local player, aggregated per second
	if _hp_seen >= 0 and hp > was_hp and phase == ViewConsts.PH_ACTIVE and not dead and owner == v.local_pid:
		_repair_acc += hp - was_hp
	_hp_seen = hp
	# the sim leads: a missed SELLING event (reconcile, replay seek) is repaired here
	var st: int = ViewSimReader.struct_state(e)
	if st == SimEconConst.ST_SELLING and phase != ViewConsts.PH_SELLING:
		var until: int = ViewSimReader.struct_state_until(e)
		begin_phase(ViewConsts.PH_SELLING, v.tick, maxi(until - v.tick, 1) if until > v.tick else DEFAULT_SELL_TICKS)
	elif st == SimEconConst.ST_BUILDUP and phase == ViewConsts.PH_BUILDUP:
		var until2: int = ViewSimReader.struct_state_until(e)
		if until2 > phase_t0:
			phase_ticks = maxi(until2 - phase_t0, 1)


func update(v: ViewWorld, e: SimEntity, dt: float, _alpha: float, in_view_now: bool) -> void:
	in_view = in_view_now
	var animating: bool = phase != ViewConsts.PH_ACTIVE or door_dir != 0 or spin > 0.0 or dead or _has_radar or power_fade != _power_target() \
			or dock_busy or _dock_t > 0.0 or _repair_acc > 0 or damage_stage > 0
	if not _placed:
		_layout(v)
		_place(v)
		_placed = true
	if animating:
		_animate(v, dt)
	_channels(v, dt)
	if _dirty:
		_dirty = false
		_push(v)
	if e == null and sim_gone:
		return


func _power_target() -> float:
	return 1.0 if (needs_power and not powered and phase == ViewConsts.PH_ACTIVE and not dead) else 0.0


func _animate(v: ViewWorld, dt: float) -> void:
	var now_t: float = float(v.tick) + v.alpha
	match phase:
		ViewConsts.PH_BUILDUP:
			var prog: float = clampf((now_t - float(phase_t0)) / float(phase_ticks), 0.0, 1.0)
			build = prog
			sink_m = (1.0 - _ease(build)) * (height_m + 1.5)
			_weld_acc += dt
			if _weld_acc >= WELD_INTERVAL_S and build < 1.0:
				_weld_acc = 0.0
				_fx_weld(v)
			if build >= 1.0:
				_finish_build(v)
		ViewConsts.PH_SELLING:
			build = 1.0 - clampf((now_t - float(phase_t0)) / float(phase_ticks), 0.0, 1.0)
			sink_m = (1.0 - _ease(build)) * (height_m + 1.5)
			_weld_acc += dt
			if _weld_acc >= WELD_INTERVAL_S and build > 0.0:
				_weld_acc = 0.0
				_fx_weld(v)
			if build <= 0.0 and not _sunk:
				_sunk = true
				_fx_dust(true)
	if dead and dying_kind == ViewConsts.DK_STRUCTURE:
		_animate_dying(v, now_t)
	# emissives fade over 0.4 s when the power fails / returns; the flag is held until the fade has run out
	var pt: float = _power_target()
	if power_fade != pt:
		power_fade = move_toward(power_fade, pt, dt / POWER_FADE_S)
		derive_flags()
		_dirty = true
	move01 = power_fade  # u_anim.y (the structure shader reads it as the fade depth)
	if door_dir != 0:
		activity = _step_door(dt)
	elif _has_arm and (dock_busy or _dock_t > 0.0) and powered:
		activity = _step_dock(dt)
	if _has_radar:
		var want: float = RADAR_RATE if powered else 0.0
		var rate: float = RADAR_RATE / RADAR_SPINUP_S if want > spin else RADAR_RATE / RADAR_SPINDOWN_S
		spin = move_toward(spin, want, rate * dt)
		if spin > 0.0:
			spin_angle = fposmod(spin_angle + spin * dt, 4.0 * TAU)
	if phase == ViewConsts.PH_ACTIVE and not dead and in_view:
		_ambient_fx(v, dt)
	if _repair_acc > 0:
		_repair_t += dt
		if _repair_t >= REPAIR_TEXT_S:
			_repair_popup(v)
	_dirty = true


func _finish_build(v: ViewWorld) -> void:
	phase = ViewConsts.PH_ACTIVE
	sink_m = 0.0
	build = 1.0
	always_active = _has_radar
	if not _done_flash:
		_done_flash = true
		flash = 1.0  # the plate flashes white for a moment (hit-flash channel u_state.w)
		if _has_door:
			open_door()
		var c: Vector3 = Vector3(wx, _base_y + 0.3, wz)
		var span: float = maxf(extent_m().x, extent_m().y)
		v.fx.ring(&"ring_add", c, span * 0.7, 0.6, 0)
		v.fx.sprites(&"flash", c + Vector3(0.0, height_m * 0.5, 0.0), span * 0.8, 0.12, 0.7, 0)
		v.fx.spawn(&"build_complete", c, Vector3.ZERO, span / 6.0)


## Collapse: shake and darken for SHAKE_S, then sink into the rubble heap. The record is kept alive for COLLAPSE_S in total.
func _animate_dying(v: ViewWorld, now_t: float) -> void:
	damage = 1.0
	if _collapse_t0 < 0.0:
		_collapse_t0 = now_t
		_start_collapse(v)
	var age_s: float = (now_t - _collapse_t0) * 0.05
	var shake_k: float = clampf(1.0 - age_s / SHAKE_S, 0.0, 1.0)
	wy = _base_y + SHAKE_M * sin(v.time * 90.0) * shake_k
	if age_s > SHAKE_S:
		var k: float = clampf((age_s - SHAKE_S) / (COLLAPSE_S - SHAKE_S), 0.0, 1.0)
		sink_m = _ease(k) * (height_m * 0.92)
	_place(v)


func _start_collapse(v: ViewWorld) -> void:
	# the record outlives the sim window so the sink can be seen; the sim entity is long gone by then
	var span_ticks: int = int(COLLAPSE_S * 20.0)
	dying_until_tick = maxi(dying_until_tick, dying_start_tick + span_ticks)
	var ext: Vector2 = extent_m()
	var tier: float = 0.5 + 0.2 * sqrt(float(footprint.x * footprint.y))
	var c: Vector3 = Vector3(wx, _base_y + 1.0, wz)
	if not v.fx.event_router_active:  # with an FX event router attached it spawns the collapse from the EV_DEATH record
		v.fx.spawn(&"building_collapse", c, Vector3.ZERO, tier)
		v.fx.shake(0.35 * tier, c)
	if v.rubble != null:
		v.rubble.add(id, Vector3(wx, _base_y, wz), ext, rot, height_m, style_id, team_index)


## Weld sparks at the rim of the growing (or shrinking) cage, three corners in turn.
func _fx_weld(v: ViewWorld) -> void:
	var ext: Vector2 = extent_m()
	var top: float = _base_y + maxf(height_m * _ease(build), 0.3)
	var corner: int = _weld_i % 4
	_weld_i += 1
	var sx: float = 1.0 if (corner & 1) == 0 else -1.0
	var sz: float = 1.0 if (corner & 2) == 0 else -1.0
	v.fx.weld_spark(Vector3(wx + sx * ext.x * 0.5, top, wz + sz * ext.y * 0.5))


func _fx_dust(end: bool) -> void:
	if _vw == null:
		return
	var span: float = maxf(extent_m().x, extent_m().y)
	_vw.fx.sprites(&"dustring", Vector3(wx, _base_y + 0.2, wz), span * (0.55 if end else 0.7), 2.4, 1.0, 0)
	_vw.fx.spawn(&"sell_dust" if end else &"build_dust", Vector3(wx, _base_y + 0.2, wz), Vector3.ZERO, span / 6.0)


## Steam puffs from the stacks while powered (generator, refinery, factory: socket steam0 / steam1).
func _ambient_fx(v: ViewWorld, dt: float) -> void:
	if not _has_steam or not powered or v.fx == null or not v.fx.active():
		return
	_steam_acc += dt
	if _steam_acc < STEAM_INTERVAL_S:
		return
	_steam_acc = 0.0
	for sname: StringName in [&"steam0", &"steam1"]:
		if model.info.has_socket(sname):
			var p: Vector3 = model.info.socket_world(sname, xf, 0.0, 0.0, 0.0)
			v.fx.puff(&"puff_white", p, 1.6, 2.4, 0.55)


func _repair_popup(v: ViewWorld) -> void:
	_repair_t = 0.0
	if _repair_acc > 0 and v.float_text != null:
		v.float_text.popup("+%d" % _repair_acc, Vector3(wx, _base_y + height_m + 0.6, wz), Color(0.55, 0.85, 1.0))
	_repair_acc = 0


## 0.6 s open, 1.0 s hold, 0.6 s close; the value goes to u_aux.y.
func _step_door(dt: float) -> float:
	if door_dir > 0:
		door_t = minf(door_t + dt / DOOR_OPEN_S, 1.0)
		if door_t >= 1.0:
			_door_hold += dt
			if _door_hold >= DOOR_HOLD_S:
				door_dir = -1
	else:
		door_t = maxf(door_t - dt / DOOR_CLOSE_S, 0.0)
		if door_t <= 0.0:
			door_dir = 0
	deploy = door_t
	return door_t


## Unload arm of a refinery: cycles 0 -> 1 -> 0 at 0.5 Hz while a collector is docked and finishes the running cycle afterwards.
func _step_dock(dt: float) -> float:
	var prev: float = _dock_t
	_dock_t += dt
	if not dock_busy and floorf(_dock_t / DOCK_CYCLE_S) > floorf(prev / DOCK_CYCLE_S):
		_dock_t = 0.0
		deploy = 0.0
		return 0.0
	var phase01: float = fposmod(_dock_t / DOCK_CYCLE_S, 1.0)
	deploy = 0.5 - 0.5 * cos(phase01 * TAU)
	return deploy


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _place(v: ViewWorld) -> void:
	var b: Basis = Basis(Vector3.UP, yaw)
	if dead and _collapse_t0 >= 0.0 and dying_kind == ViewConsts.DK_STRUCTURE:
		var age_s: float = ((float(v.tick) + v.alpha) - _collapse_t0) * 0.05
		var lean: float = clampf((age_s - SHAKE_S) / (COLLAPSE_S - SHAKE_S), 0.0, 1.0)
		var axis: Vector3 = Vector3(1.0, 0.0, float((id * 7) % 5 - 2) * 0.35).normalized()
		b = Basis(axis, deg_to_rad(4.5) * _ease(lean)) * b
	if placeholder_scale != Vector3.ONE:
		b = b.scaled_local(placeholder_scale)
	xf = Transform3D(b, Vector3(wx, wy, wz))
	v.backend.set_xform(self, xf)


func dispose(v: ViewWorld) -> void:
	if v.scaffolds != null:
		v.scaffolds.untrack(self)
	super.dispose(v)
