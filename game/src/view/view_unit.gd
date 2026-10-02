class_name ViewUnit
extends ViewEntity
## Units and wrecks (render spec 4.5 / 5.2 motion table): ground alignment, aircraft altitude / bank / pitch / rotors, naval bob,
## submarine sink, amphibious hover, wreck pose and sinking. Presentation only.

const ALT_RATE_MPS: float = 2.5
const SPIN_RATE: float = 28.0
const SPIN_EASE_S: float = 1.0
const SINK_EASE_S: float = 1.5
const WRECK_SINK_M: float = 0.6
const WRECK_SINK_TICKS: int = 30
const WRECK_BURN_S: float = 14.0
const BOB_AMP: Array[float] = [0.05, 0.03, 0.018]  ## small / medium / large hull (rad; metres = x 2)
const AMPH_BOB_M: float = 0.05

var alt: float = 0.0
var alt_target: float = 0.0
var bank: float = 0.0
var pitch_air: float = 0.0
var airborne: bool = false
var sink: float = 0.0  ## 0..1 sinking ships / submerged subs
var bob_phase: float = 0.0
var hover_m: float = 12.0

## Collector docking (VQ2A): the sim glides a collector into the refinery's dock cell (inside the footprint), unloads, and glides it
## out again. The view turns the hull around so the collector REVERSES into the bay (wheels roll backwards), sinks into the bay floor
## while it is inside (hidden under the canopy, only the unload arm and the sparkles show), and rises and drives out forwards.
const DOCK_FLIP_S: float = 0.6
const DOCK_RISE_S: float = 0.55
const DOCK_SINK_RADIUS_M: float = 2.6
const DOCK_SPARKLE_S: float = 0.22
const H_DOCK_IN: int = 6
const H_UNLOAD: int = 7
const H_DOCK_OUT: int = 8

var dock_flip: float = 0.0  ## 0..1: the heading is turned by PI (nose away from the bay)
var dock_sink: float = 0.0  ## 0..1: how far the collector has sunk into the bay floor
var dock_state: int = -1
var _is_collector: bool = false
var _dock_anchor: Vector2 = Vector2.ZERO  ## world xz of the dock cell centre
var _dock_known: bool = false
var _dock_fx_t: float = 0.0
var _dock_seen_unload: bool = false
var _last_yaw: float = 0.0
var _last_alt: float = 0.0
var _naval_amp: float = 0.03
var _wreck_basis: Basis = Basis.IDENTITY
var _burn_seen: bool = false


## Called once by ViewWorld after identity / model are set.
func setup_motion() -> void:
	bob_phase = float((id * 2654435761) & 0xFFFF) / 65535.0 * TAU
	hover_m = model.info.hover if model != null and model.info.hover > 0.0 else 12.0
	_is_collector = vdef != null and vdef.cargo_cap > 0 and kind == SimEntity.Kind.UNIT
	match motion:
		ViewConsts.MOTION_TRACKED:
			_tilt = TILT_TRACKED
		ViewConsts.MOTION_WHEELED:
			_tilt = TILT_WHEELED
		ViewConsts.MOTION_AMPHIBIOUS:
			_tilt = TILT_AMPHIBIOUS
			always_active = true
		ViewConsts.MOTION_NAVAL, ViewConsts.MOTION_SUB:
			always_active = true
			var sc: int = vdef.size_class if vdef != null else DefEnums.SizeClass.SHIP_MEDIUM
			_naval_amp = BOB_AMP[clampi(sc - DefEnums.SizeClass.SHIP_SMALL, 0, 2)]
		ViewConsts.MOTION_AIR_FIXED, ViewConsts.MOTION_AIR_HOVER:
			always_active = true
			alt = 0.0
	if kind == SimEntity.Kind.WRECK:
		_tilt = 0.0
		always_active = false
		var h: float = float((id * 40503) & 0xFF) / 255.0
		turret_yaw = (h - 0.5) * 1.2
		_wreck_basis = Basis.from_euler(Vector3(deg_to_rad(3.0), 0.0, deg_to_rad(-6.0)))
		_dirty = true


func sample(v: ViewWorld, e: SimEntity, shift: bool) -> void:
	super.sample(v, e, shift)
	if _is_collector:
		_dock_sample(v, e)
		if dock_flip > 0.0 or dock_sink > 0.0 or (dock_state >= H_DOCK_IN and dock_state <= H_DOCK_OUT):
			_still = false  # keep the full update path until the turn / the sink has settled


func _ground(v: ViewWorld, dt: float) -> void:
	if _is_collector:
		_dock_step(v, dt)
	match motion:
		ViewConsts.MOTION_AIR_FIXED, ViewConsts.MOTION_AIR_HOVER:
			_air(v, dt)
		ViewConsts.MOTION_NAVAL:
			_naval(v, dt, false)
		ViewConsts.MOTION_SUB:
			_naval(v, dt, true)
		ViewConsts.MOTION_AMPHIBIOUS:
			super._ground(v, dt)
			wy += AMPH_BOB_M * sin(v.time * 2.1 + bob_phase)
		_:
			super._ground(v, dt)


func _channels(v: ViewWorld, dt: float) -> void:
	super._channels(v, dt)
	if kind == SimEntity.Kind.WRECK:
		_wreck_burn(v)
		if expires > 0:
			_wreck_sink(v)


## Embers of a fresh wreck burn out over WRECK_BURN_S (the shader reads the level from the cloak channel of UF_WRECK records).
func _wreck_burn(v: ViewWorld) -> void:
	var age_s: float = maxf((float(v.tick) + v.alpha - float(born_tick)) * 0.05, 0.0)
	var burn: float = clampf(1.0 - age_s / WRECK_BURN_S, 0.0, 1.0)
	_cloak_target = maxf(burn * burn, 0.004)
	if not _burn_seen:
		_burn_seen = true
		cloak = _cloak_target  # no fade-in: a wreck that appears already burns at its age's level


func _wreck_sink(v: ViewWorld) -> void:
	var remaining: float = float(expires) - (float(v.tick) + v.alpha)
	if remaining <= float(WRECK_SINK_TICKS):
		sink_m = WRECK_SINK_M * clampf(1.0 - remaining / float(WRECK_SINK_TICKS), 0.0, 1.0)
		_dirty = true


func _air(v: ViewWorld, dt: float) -> void:
	airborne = (sim_flags & SimFlags.F_AIRBORNE) != 0 or layer == SimEntity.Layer.AIR
	if dead:
		alt_target = 0.0  # the fall of a crashing aircraft is driven by dying_pose()
	else:
		alt_target = hover_m if airborne else 0.0
		alt = move_toward(alt, alt_target, ALT_RATE_MPS * dt)
	var g: float = v.ground_at(wx, wz)
	wy = g + alt + ViewConsts.GROUND_LIFT_M
	if dead:
		return  # bank / pitch / rotors belong to dying_pose()
	# bank from the yaw rate, pitch from the vertical speed (eased)
	var dyaw: float = wrapf(yaw - _last_yaw, -PI, PI)
	_last_yaw = yaw
	var rate: float = dyaw / maxf(dt, 0.0001)
	bank = lerpf(bank, clampf(rate * 0.35, -0.5, 0.5), clampf(dt * 4.0, 0.0, 1.0))
	var vspd: float = (alt - _last_alt) / maxf(dt, 0.0001)
	_last_alt = alt
	pitch_air = lerpf(pitch_air, clampf(vspd * 0.05, -0.25, 0.25), clampf(dt * 4.0, 0.0, 1.0))
	# rotors ease up once airborne or moving, the angle is integrated on the CPU (wrapped at 8 pi)
	var want: float = SPIN_RATE if (airborne or move01 > 0.1) else 0.0
	spin = move_toward(spin, want, SPIN_RATE / SPIN_EASE_S * dt)
	if spin > 0.0:
		spin_angle = fposmod(spin_angle + spin * dt, 4.0 * TAU)
		_dirty = true


func _naval(v: ViewWorld, dt: float, is_sub: bool) -> void:
	var sea: float = v.sea_level()
	var t: float = v.time
	var bob: float = _naval_amp * 2.0 * sin(t * 1.3 + bob_phase)
	if is_sub:
		var want: float = 1.0 if layer == SimEntity.Layer.UNDERWATER else 0.0
		sink = move_toward(sink, want, dt / SINK_EASE_S)
		wy = sea + bob * (1.0 - sink) - (0.75 * height_m - 0.15) * sink
	else:
		wy = sea + bob
	pitch_air = 0.6 * _naval_amp * sin(t * 1.1 + bob_phase + 1.0)
	bank = 0.8 * _naval_amp * sin(t * 0.9 + bob_phase + 2.0)
	_dirty = true


func _place(v: ViewWorld) -> void:
	var b: Basis
	match motion:
		ViewConsts.MOTION_AIR_FIXED, ViewConsts.MOTION_AIR_HOVER:
			b = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, bank) * Basis(Vector3.RIGHT, pitch_air)
		ViewConsts.MOTION_NAVAL, ViewConsts.MOTION_SUB:
			b = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, bank) * Basis(Vector3.RIGHT, pitch_air)
		_:
			if kind == SimEntity.Kind.WRECK:
				b = _wreck_basis * Basis(Vector3.UP, yaw)
			else:
				b = _tilt_basis * Basis(Vector3.UP, yaw + dock_flip * PI)
	xf = Transform3D(b, Vector3(wx, wy, wz))
	v.backend.set_xform(self, xf)


## Crash / sink animations of the dying window (called by ViewWorld before update while `dead`).
func dying_pose(v: ViewWorld, dt: float) -> void:
	var left: float = float(dying_until_tick) - (float(v.tick) + v.alpha)
	match dying_kind:
		ViewConsts.DK_CRASH:
			bank += 2.5 * dt
			alt = maxf(alt - 16.0 * dt * (2.0 - clampf(left / 30.0, 0.0, 1.0)), 0.0)
			damage = 1.0
			_dirty = true
		ViewConsts.DK_SINK:
			sink = clampf(1.0 - left / 60.0, 0.0, 1.0)
			sink_m = sink * 0.9 * height_m
			pitch_air = sink * 0.35
			_dirty = true
		_:
			pass


# ---- collector docking (VQ2A) --------------------------------------------------------------------------------------

## Reads the dock phase of the sim (read-only) and the dock cell of the refinery it points at.
func _dock_sample(v: ViewWorld, e: SimEntity) -> void:
	dock_state = ViewSimReader.harvest_state(e)
	if dock_state < H_DOCK_IN or dock_state > H_DOCK_OUT:
		return
	var rv: ViewEntity = v.entity_view(ViewSimReader.harvest_refinery(e))
	if rv != null and rv.vdef != null and rv.kind == SimEntity.Kind.STRUCTURE:
		_dock_anchor = Vector2(float(rv.x_cur) * ViewConsts.M_PER_UNIT + rv.vdef.dock_cx, float(rv.y_cur) * ViewConsts.M_PER_UNIT + rv.vdef.dock_cz)
		_dock_known = true
	else:
		_dock_known = false


## Per frame (full update path): flip, sink and the sparkle stream. Keeps the entity out of the idle fast path until it has settled.
func _dock_step(v: ViewWorld, dt: float) -> void:
	var docking: bool = dock_state >= H_DOCK_IN and dock_state <= H_DOCK_OUT
	var flip_t: float = 1.0 if (dock_state == H_DOCK_IN or dock_state == H_UNLOAD) else 0.0
	var sink_t: float = 0.0
	var rise: float = 1.0 / DOCK_RISE_S
	if dock_state == H_UNLOAD:
		sink_t = 1.0
	elif dock_state == H_DOCK_IN and _dock_known:
		sink_t = clampf(1.1 - Vector2(wx, wz).distance_to(_dock_anchor) / DOCK_SINK_RADIUS_M, 0.0, 1.0)
	if docking:
		if flip_t > dock_flip:
			dock_flip = move_toward(dock_flip, flip_t, dt / DOCK_FLIP_S)
		else:
			dock_flip = flip_t  # driving out: the sim heading already points away from the bay, no turn
		if sink_t >= dock_sink:
			dock_sink = sink_t if dock_state == H_DOCK_IN else move_toward(dock_sink, sink_t, dt * 3.0)
		else:
			dock_sink = move_toward(dock_sink, sink_t, dt * rise)
	else:
		dock_flip = move_toward(dock_flip, 0.0, dt / DOCK_FLIP_S)
		dock_sink = move_toward(dock_sink, 0.0, dt * rise)
	roll_dir = -1.0 if (dock_state == H_DOCK_IN and dock_flip > 0.5) else 1.0
	sink_m = dock_sink * (height_m + 0.4)
	if dock_state == H_UNLOAD and in_view and v.fx != null:
		_dock_fx_t -= dt
		if _dock_fx_t <= 0.0:
			_dock_fx_t = DOCK_SPARKLE_S
			v.fx.spawn(&"credit_sparkle", Vector3(wx, wy + 1.6 + 2.2 * randf(), wz), Vector3.ZERO, 0.55)
		_dock_seen_unload = true
	elif _dock_seen_unload and dock_state == H_DOCK_OUT and in_view and v.fx != null:
		_dock_seen_unload = false
		v.fx.spawn(&"exit_dust", Vector3(wx, wy + 0.2, wz), Vector3.ZERO, 0.9)
	if dock_flip > 0.0 or dock_sink > 0.0 or docking:
		_still = false  # keep the full update path until the turn / the sink has settled
	_dirty = true
