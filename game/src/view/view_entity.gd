class_name ViewEntity
extends RefCounted
## One mirrored sim entity (render spec 4.5 / 5.2). The view keeps a two-sample snapshot (`*_prev` / `*_cur`, ints copied from the
## sim) because the kernel stores no previous values, and interpolates between them. Presentation only: it reads the sim through
## ViewWorld and never writes it. update() never allocates; ViewUnit and ViewStructure add their state machines.

## STATE codes of render spec 6.2.2 (the kernel has no STATE event: ViewEventRouter derives them from its own events / flags).
const ST_DEPLOYING: int = 1
const ST_DEPLOYED: int = 2
const ST_PACKING: int = 3
const ST_PACKED: int = 4
const ST_CLOAKED: int = 5
const ST_DECLOAKED: int = 6
const ST_EMP: int = 7
const ST_SHUTDOWN: int = 8
const ST_SUPPRESSED: int = 9
const ST_LANDED: int = 10
const ST_TAKEOFF: int = 11
const ST_SELLING: int = 12
const ST_POWERED: int = 13
const ST_MODE_SWITCH: int = 14
const ST_REPAIRING: int = 15
const TILT_TRACKED: float = 0.85
const TILT_WHEELED: float = 0.8
const TILT_AMPHIBIOUS: float = 0.5
const RECOIL_S: float = 0.28
const MOVE_EASE_S: float = 0.15
const CLOAK_LEVEL: float = 0.85
const CLOAK_EASE_S: float = 0.6
const MOVE_MIN_SPEED: float = 0.25  ## m/s: below this the gait / track scroll fades out

# identity (set once from the SPAWNED payload: the sim entity may already be gone)
var id: int = 0
var def_idx: int = -1
var kind: int = 0
var owner: int = -1
var layer: int = 0
var vdef: ViewDef = null
var recipe_id: StringName = &""
var style_id: StringName = &""
var model: ViewModel = null
var team_index: int = -1
var team_color: Color = Color.WHITE
var motion: int = ViewConsts.MOTION_WHEELED
var radius_m: float = 1.0
var height_m: float = 1.5
var pick_half: Vector3 = Vector3(1.0, 0.75, 1.0)
var members: int = 1

# backend handle
var rig: ViewModelRig = null
var slot: int = -1
var active_idx: int = -1  ## index in ViewWorld._active (swap-remove)

# visibility
var vs: int = ViewConsts.VS_HIDDEN
var in_view: bool = true
var next_full_frame: int = 0
var vis_ver: int = -1
var last_frame: int = 0
var stamp: int = 0
var next_vis_frame: int = 0

# two-sample snapshot
var x_prev: int = 0
var y_prev: int = 0
var x_cur: int = 0
var y_cur: int = 0
var facing_prev: int = 0
var facing_cur: int = 0
var mnt_prev: PackedInt32Array = PackedInt32Array()
var mnt_cur: PackedInt32Array = PackedInt32Array()
var sim_gone: bool = false  ## REMOVED seen or the sim entity is gone: animate from cached samples until dying_until_tick
var dead: bool = false  ## DIED seen

# interpolated placement (world space)
var wx: float = 0.0
var wy: float = 0.0
var wz: float = 0.0
var yaw: float = 0.0
var normal: Vector3 = Vector3.UP
var normal_frame: int = 0
var xf: Transform3D = Transform3D.IDENTITY

# animation channels (mirror the instance uniforms)
var roll_m: float = 0.0
var move01: float = 0.0
var roll_dir: float = 1.0  ## -1 while the model drives backwards (collector reversing into a refinery bay): the wheels roll the other way
var turret_yaw: float = 0.0
var elevation: float = 0.0
var recoil: float = 0.0  ## shader value (recoil_t ^ 1.6)
var recoil_t: float = 0.0
var deploy: float = 0.0
var spin: float = 0.0
var spin_angle: float = 0.0
var build: float = 1.0
var damage: float = 0.0
var selected: float = 0.0
var selected_target: float = 0.0
var flash: float = 0.0
var flags: int = 0
var cloak: float = 0.0
var mnt: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var sink_m: float = 0.0  ## u_anim.x: structure sink depth / wreck sinking (metres)
var has_mounts: bool = false  ## the model has TURRET1..3 / BARREL1..3 parts

# mirrored gameplay snapshots
var hp: int = 0
var max_hp: int = 0
var sim_flags: int = 0
var holder: int = -1
var expires: int = 0
var dying_until_tick: int = -1
var dying_start_tick: int = 0
var killer_id: int = 0
var death_x: int = 0
var death_y: int = 0
var scale_k: float = 1.0  ## silent-removal shrink 1..0
var dying_kind: int = 0
var born_tick: int = 0

# fx handles (FX wave)
var stamper: int = -1
var damage_emitter: int = -1
var wake: int = -1

var always_active: bool = false  ## air / naval / amphibious / spinning: never takes the idle fast path
var _still: bool = false  ## the last sample changed neither position, facing nor mount angles
var _placed: bool = false  ## the transform already reflects the final (still) sample
var _dirty: bool = true
var _deploy_target: float = 0.0
var _deploy_rate: float = 1.0
var _tilt: float = 0.0
var _tilt_basis: Basis = Basis.IDENTITY
var _snap: bool = true
var _cloak_target: float = 0.0


## Copies the placement / identity common to every entity. `e` may be null (payload only).
func init_placement(x: int, y: int, facing: int) -> void:
	x_prev = x
	y_prev = y
	x_cur = x
	y_cur = y
	facing_prev = facing
	facing_cur = facing


## Frame-granular sampling (render spec 3.0 step 6): shift cur into prev, then read cur. `shift` false = the exact
## capture_prev mode already stored prev.
func sample(_v: ViewWorld, e: SimEntity, shift: bool) -> void:
	if shift:
		x_prev = x_cur
		y_prev = y_cur
		facing_prev = facing_cur
	x_cur = e.x
	y_cur = e.y
	facing_cur = e.facing
	if absi(x_cur - x_prev) > ViewConsts.TELEPORT_SNAP_UNITS or absi(y_cur - y_prev) > ViewConsts.TELEPORT_SNAP_UNITS:
		x_prev = x_cur
		y_prev = y_cur
		facing_prev = facing_cur
	var old_flags: int = sim_flags
	var old_hp: int = hp
	hp = e.hp
	max_hp = e.hp_max
	sim_flags = e.flags
	holder = e.container_id
	expires = e.expire_tick
	layer = e.layer
	var n: int = ViewSimReader.mount_count(e)
	if n > 0 or mnt_cur.size() > 0:
		var fresh: bool = mnt_cur.size() != n
		if fresh:
			mnt_cur.resize(n)
			mnt_prev.resize(n)
		for m: int in n:
			var a: int = maxi(ViewSimReader.turret_rel_bat(e, m), 0)
			if fresh:
				mnt_prev[m] = a
			elif shift:
				mnt_prev[m] = mnt_cur[m]
			mnt_cur[m] = a
	derive_flags()
	_still = x_prev == x_cur and y_prev == y_cur and facing_prev == facing_cur and mnt_prev == mnt_cur
	if not _still:
		_placed = false
	if hp != old_hp or sim_flags != old_flags:
		_dirty = true
		_damage_channel()


func _damage_channel() -> void:
	if max_hp <= 0:
		damage = 0.0
		return
	var lost: float = 1.0 - float(hp) / float(max_hp)
	if members > 1:
		damage = clampf(lost, 0.0, 1.0)
	else:
		damage = clampf((lost - 0.2) / 0.8, 0.0, 1.0)


## Exact mode: store the state immediately before a world step into `prev`.
func capture(e: SimEntity) -> void:
	x_prev = e.x
	y_prev = e.y
	facing_prev = e.facing
	for m: int in mini(mnt_cur.size(), mnt_prev.size()):
		var a: int = ViewSimReader.turret_rel_bat(e, m)
		mnt_prev[m] = a if a >= 0 else 0


## UF_* shader flags from the mirrored sim flags (also called at creation, before the first sample).
func derive_flags() -> void:
	var f: int = 0
	var sf: int = sim_flags
	if (sf & SimFlags.F_CLOAKED) != 0:
		f |= ViewConsts.UF_CLOAKED
		_cloak_target = CLOAK_LEVEL
	else:
		_cloak_target = 0.0
	if (sf & SimFlags.F_EMP_SHUT) != 0:
		f |= ViewConsts.UF_EMP
	if (sf & SimFlags.F_SUPPRESSED) != 0:
		f |= ViewConsts.UF_SUPPRESSED
	if layer == SimEntity.Layer.UNDERWATER:
		f |= ViewConsts.UF_SUBMERGED
	if kind == SimEntity.Kind.WRECK:
		f |= ViewConsts.UF_WRECK
	if vdef != null and vdef.needs_power and kind != SimEntity.Kind.UNIT and (sf & SimFlags.F_POWERED) == 0:
		f |= ViewConsts.UF_UNPOWERED
	if (sf & SimFlags.F_DEPLOYED) != 0:
		_deploy_target = 1.0
	elif (sf & SimFlags.F_DEPLOYING) == 0:
		_deploy_target = 0.0
	flags = (flags & (ViewConsts.UF_GHOST | ViewConsts.UF_FOG_DIM | ViewConsts.UF_DECOY_ID)) | f


## Per-frame update (render spec 5.2). `e` is the live sim entity or null (record animates from its cached samples).
func update(v: ViewWorld, _e: SimEntity, dt: float, alpha: float, in_view_now: bool) -> void:
	in_view = in_view_now
	var still: bool = _still and _placed and not _snap and not always_active
	if still:
		if move01 > 0.0:
			move01 = move_toward(move01, 0.0, dt / MOVE_EASE_S)
			_dirty = true
	else:
		var a: float = alpha
		var nwx: float = (float(x_prev) + float(x_cur - x_prev) * a) * ViewConsts.M_PER_UNIT
		var nwz: float = (float(y_prev) + float(y_cur - y_prev) * a) * ViewConsts.M_PER_UNIT
		var step: float = 0.0
		if not _snap:
			var dx: float = nwx - wx
			var dz: float = nwz - wz
			step = sqrt(dx * dx + dz * dz)
		wx = nwx
		wz = nwz
		roll_m += step * roll_dir
		var moving: float = 1.0 if (dt > 0.0 and step / dt > MOVE_MIN_SPEED) else 0.0
		move01 = move_toward(move01, moving, dt / MOVE_EASE_S)
		yaw = -ViewConsts.lerp_bat(facing_prev, facing_cur, a) * ViewConsts.BAT_TO_RAD - PI * 0.5
		if mnt_cur.size() > 0:
			turret_yaw = -ViewConsts.lerp_bat(mnt_prev[0], mnt_cur[0], a) * ViewConsts.BAT_TO_RAD
			if has_mounts:
				for m: int in mini(mnt_cur.size() - 1, 3):
					mnt[m * 3] = -ViewConsts.lerp_bat(mnt_prev[m + 1], mnt_cur[m + 1], a) * ViewConsts.BAT_TO_RAD
		_ground(v, dt)
		_place(v)
		_placed = _still
		_dirty = true
		_snap = false
	_channels(v, dt)
	if _dirty:
		_dirty = false
		_push(v)


## Ground height, alignment and the base transform; subclasses override for air / naval.
func _ground(v: ViewWorld, dt: float) -> void:
	wy = v.ground_at(wx, wz) + ViewConsts.GROUND_LIFT_M
	if _tilt > 0.0:
		if v.frame_no % 3 == id % 3 or normal_frame == 0:
			var nt: Vector3 = v.ground_normal(wx, wz)
			var k: float = 1.0 - exp(-30.0 * dt) if normal_frame != 0 else 1.0
			if normal.dot(nt) < 0.99996:
				normal = normal.slerp(nt, k)
			normal_frame = v.frame_no
			_tilt_basis = Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(normal, _tilt).normalized()))


func _channels(_v: ViewWorld, dt: float) -> void:
	if recoil_t > 0.0:
		recoil_t = maxf(recoil_t - dt / RECOIL_S, 0.0)
		recoil = pow(recoil_t, 1.6)
		_dirty = true
	if has_mounts:
		for m: int in 3:
			var r: float = mnt[m * 3 + 2]
			if r > 0.0:
				mnt[m * 3 + 2] = maxf(r - dt / RECOIL_S, 0.0)
				_dirty = true
	if flash > 0.0:
		flash = maxf(flash - dt * 8.0, 0.0)
		_dirty = true
	if selected != selected_target:
		selected = move_toward(selected, selected_target, dt * 8.0)
		_dirty = true
	if cloak != _cloak_target:
		cloak = move_toward(cloak, _cloak_target, dt / CLOAK_EASE_S * CLOAK_LEVEL)
		_dirty = true
	if deploy != _deploy_target:
		deploy = move_toward(deploy, _deploy_target, _deploy_rate * dt)
		_dirty = true


func _place(v: ViewWorld) -> void:
	xf = Transform3D(_tilt_basis * Basis(Vector3.UP, yaw), Vector3(wx, wy, wz))
	v.backend.set_xform(self, xf)


func _push(v: ViewWorld) -> void:
	var be: ViewUnitBackend = v.backend
	be.push_anim(self)
	be.push_aux(self)
	be.push_state(self)
	if has_mounts:
		be.push_mounts(self)


## Recoil kick (WEAPON_FIRED). Mount 0 uses the hull recoil, mounts 1..3 their own channel.
func on_fire(mount: int, _barrel: int) -> void:
	if mount <= 0 or not has_mounts:
		recoil_t = 1.0
		recoil = 1.0
	elif mount <= 3:
		mnt[(mount - 1) * 3 + 2] = 1.0


## Hit flash (DAMAGE): none on the kill blow, whose death effect replaces it.
func on_hit(_hp_lost: int, dmg_flags: int) -> void:
	if (dmg_flags & 1) == 0:
		flash = 1.0


## State events (deploy / pack ease over `ticks`, cloak, EMP, ...). Persistent truth is re-read from the sim flags at every sample.
func on_state(st: int, value: int, ticks: int) -> void:
	match st:
		ST_DEPLOYING, ST_PACKING:
			_deploy_target = 1.0 if st == ST_DEPLOYING else 0.0
			_deploy_rate = 1.0 / maxf(float(ticks) * 0.05, 0.05)
		ST_DEPLOYED:
			_deploy_target = 1.0
			deploy = 1.0
		ST_PACKED:
			_deploy_target = 0.0
			deploy = 0.0
		_:
			pass
	if value < 0:
		return


func dispose(v: ViewWorld) -> void:
	if rig != null:
		v.backend.remove(self)


## World-space centre of the pick volume.
func pick_centre() -> Vector3:
	return Vector3(wx, wy + height_m * 0.5, wz)
