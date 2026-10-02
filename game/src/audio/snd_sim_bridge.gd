class_name SndSimBridge
extends RefCounted
## Drains one frame's SimEvent batch (stride 10: [type, tick, x, y, a..f]) into sounds (audio spec 3.6 / 5.4 / 6.2):
## audibility (fog / ownership / distance), candidate ranking under the per-frame start cap, per-source throttles, and the
## announcer / combat-meter / countdown / loop triggers derived from the events. Reads the sim only through SndWorldReader.
## The event layout and codes are the REAL kernel ones (domain blocks), mirrored by SndEventCodes.

enum { R_IGNORE = 0, R_LIFECYCLE = 1, R_DIED = 2, R_STATE = 3, R_CARGO = 4, R_DAMAGE = 5, R_FIRED = 6, R_PROJECTILE = 7,
	R_EXPLOSION = 8, R_BEAM = 9, R_INTERCEPT = 10, R_ECONOMY = 11, R_POWER_GRID = 12, R_PRODUCTION = 13, R_SUPPORT_POWER = 14,
	R_SUPERWEAPON = 15, R_ALERT = 16, R_ORDER_FEEDBACK = 17, R_MATCH = 18 }

const STRIDE: int = 10
const AIR_LAYER: int = 1
const FOG_DROP: int = 0
const FOG_OK: int = 1
const FOG_MUFFLED: int = 2

## Announcer line ids and event ids this bridge can request (checked against the data by `SndEventMap.missing`).
const LINES_USED: PackedStringArray = [
	"unit_lost", "structure_lost", "collector_lost", "superweapon_destroyed", "structure_sold", "low_power", "power_restored",
	"construction_complete", "unit_ready", "research_complete", "insufficient_funds", "unit_cap_reached", "on_hold", "power_ready",
	"base_under_attack", "collector_under_attack", "unit_under_attack", "aircraft_under_attack", "ally_under_attack",
	"building_captured", "structure_captured", "systems_disabled", "defenses_offline", "sw_ready", "sw_launched", "sw_cancelled",
	"sw_launch_detected", "sw_incoming_strike", "scan_detected", "unable_to_comply", "cannot_deploy", "ally_defeated",
	"enemy_defeated", "player_disconnected", "victory", "defeat",
]
const EVENTS_USED: PackedStringArray = [
	"snd.death.infantry", "snd.death.ship", "snd.death.sub", "snd.death.drone", "snd.death.decoy", "snd.air.crash_fall",
	"snd.air.takeoff", "snd.air.landing", "snd.explosion.small", "snd.explosion.medium", "snd.explosion.large", "snd.explosion.huge",
	"snd.explosion.water.small", "snd.explosion.water.medium", "snd.explosion.water.large", "snd.collapse.s1", "snd.collapse.s2",
	"snd.collapse.s3", "snd.collapse.s4", "snd.impact.energy.small", "snd.impact.energy.large", "snd.impact.rail", "snd.impact.kinetic",
	"snd.impact.emp", "snd.intercept.aps", "snd.intercept.zone", "snd.emp.hit", "snd.struct.sell", "snd.struct.repair",
	"snd.struct.power_down", "snd.struct.power_up", "snd.struct.defense_offline", "snd.struct.captured", "snd.struct.hq_deploy",
	"snd.struct.unit_out.infantry", "snd.struct.unit_out.vehicle", "snd.struct.unit_out.aircraft", "snd.struct.unit_out.ship",
	"snd.eco.cash", "snd.eco.cash_big", "snd.alarm.base_attack", "snd.alarm.incoming", "snd.alarm.sw_siren", "snd.alarm.countdown_tick",
	"snd.alarm.countdown_final", "snd.ui.error", "snd.ui.place_fail", "snd.ui.build_ready", "snd.ui.confirm", "snd.power.cloak.activate",
	"snd.power.cloak.end", "snd.proj.missile", "snd.proj.torpedo", "snd.proj.shell_whistle", "snd.proj.bomb_whistle",
]

static var _routes: Dictionary = {}

# wiring
var reader: SndWorldReader = null
var bank: SndSoundBank = null
var pool: SndVoicePool = null
var loops: SndLoopManager = null
var meter: SndCombatMeter = null
var announcer: SndAnnouncer = null
var countdown: SndCountdown = null
var scheduler: SndScheduler = null
var responses: SndUnitResponse = null
var map: SndEventMap = null
var mix: SndMixConfig = null
var on_match_end: Callable = Callable()  ## func(result: int)
var on_urgent: Callable = Callable()  ## func() - an alert that should push the music to combat

var decision_log: PackedStringArray = PackedStringArray()
var log_decisions: bool = false
var lines_said: PackedStringArray = PackedStringArray()
var record_lines: bool = false
var stats: SndStats = SndStats.new()
var observer: bool = false
var zoom_scale: float = 1.0

# per-frame candidate table (parallel arrays, capacity MAX_CANDIDATES)
var _c_def: Array[SndEventDef] = []
var _c_pos: PackedVector3Array = PackedVector3Array()
var _c_score: PackedFloat32Array = PackedFloat32Array()
var _c_gain: PackedFloat32Array = PackedFloat32Array()
var _c_flav: Array[StringName] = []
var _c_delay: PackedInt32Array = PackedInt32Array()
var _c_low: PackedFloat32Array = PackedFloat32Array()
var _c_pitch: PackedFloat32Array = PackedFloat32Array()
var _c_n: int = 0
var _last_fire_ms: PackedInt32Array = PackedInt32Array()
var _last_hit_ms: PackedInt32Array = PackedInt32Array()
var _throttle: Dictionary = {}  ## "key" -> ms
var _boom_key: PackedInt32Array = PackedInt32Array()
var _boom_tick: PackedInt32Array = PackedInt32Array()
var _boom_n: int = 0
var _proj_arch: Dictionary = {}  ## projectile serial -> arch (bounded)
var _now: int = 0
var _focus: Vector3 = Vector3.ZERO
var _batch_tick: int = 0
var _defense_line_ms: int = -1000000


static func _build_routes() -> void:
	if not _routes.is_empty():
		return
	var r: Dictionary = _routes
	r[SndEventCodes.CASH] = R_ECONOMY
	r[SndEventCodes.CMD_REJECTED] = R_ORDER_FEEDBACK
	r[SndEventCodes.ORDER_FAILED] = R_ORDER_FEEDBACK
	r[SndEventCodes.PLAYER_ELIMINATED] = R_MATCH
	r[SndEventCodes.MATCH_END] = R_MATCH
	r[SndEventCodes.EV_MOVE_FAILED] = R_ORDER_FEEDBACK
	r[SndEventCodes.EV_AIR_TAKEOFF] = R_STATE
	r[SndEventCodes.EV_AIR_LANDED] = R_STATE
	r[SndEventCodes.EV_FIRE] = R_FIRED
	r[SndEventCodes.EV_PROJ_SPAWN] = R_PROJECTILE
	r[SndEventCodes.EV_PROJ_END] = R_PROJECTILE
	r[SndEventCodes.EV_IMPACT] = R_EXPLOSION
	r[SndEventCodes.EV_HIT] = R_DAMAGE
	r[SndEventCodes.EV_BEAM_START] = R_BEAM
	r[SndEventCodes.EV_BEAM_END] = R_BEAM
	r[SndEventCodes.EV_DEATH] = R_DIED
	r[SndEventCodes.EV_INTERCEPT] = R_INTERCEPT
	r[SndEventCodes.EV_EMP] = R_STATE
	r[SndEventCodes.EV_ATTACK_ALERT] = R_ALERT
	r[SndEventCodes.EV_EJECT] = R_CARGO
	r[SndEventCodes.EV_CRASH] = R_DIED
	r[SndEventCodes.EV_WEAPON_LOCK] = R_STATE
	r[SndEventCodes.EV_CLOAK_CHANGED] = R_STATE
	r[SndEventCodes.EV_LOADED] = R_CARGO
	r[SndEventCodes.EV_UNLOADED] = R_CARGO
	r[SndEventCodes.EV_SCAN_WARNING] = R_SUPERWEAPON
	r[SndEventCodes.EVT_STRUCTURE_READY] = R_PRODUCTION
	r[SndEventCodes.EVT_STRUCTURE_PLACED] = R_LIFECYCLE
	r[SndEventCodes.EVT_UNIT_PRODUCED] = R_PRODUCTION
	r[SndEventCodes.EVT_QUEUE_STATE] = R_PRODUCTION
	r[SndEventCodes.EVT_RESEARCH_COMPLETE] = R_PRODUCTION
	r[SndEventCodes.EVT_CREDITS_GAINED] = R_ECONOMY
	r[SndEventCodes.EVT_INSUFFICIENT_FUNDS] = R_PRODUCTION
	r[SndEventCodes.EVT_UNIT_CAP_REACHED] = R_PRODUCTION
	r[SndEventCodes.EVT_POWER_SHORTAGE] = R_POWER_GRID
	r[SndEventCodes.EVT_POWER_RESTORED] = R_POWER_GRID
	r[SndEventCodes.EVT_STRUCTURE_SOLD] = R_ECONOMY
	r[SndEventCodes.EVT_STRUCTURE_SELLING] = R_STATE
	r[SndEventCodes.EVT_REPAIR_STATE] = R_STATE
	r[SndEventCodes.EVT_HQ_DEPLOYED] = R_LIFECYCLE
	r[SndEventCodes.EVT_ORDER_FAILED] = R_ORDER_FEEDBACK
	r[SndEventCodes.EVT_COLLECTOR_ATTACKED] = R_ALERT
	r[SndEventCodes.EVT_STRUCTURE_CAPTURED] = R_LIFECYCLE
	r[SndEventCodes.EVT_SALVAGE_PAID] = R_ECONOMY
	r[SndEventCodes.EVT_POWER_READY] = R_SUPPORT_POWER
	r[SndEventCodes.EVT_POWER_ACTIVATED] = R_SUPPORT_POWER
	r[SndEventCodes.EVT_WARNING] = R_SUPERWEAPON
	r[SndEventCodes.EVT_SW_READY] = R_SUPERWEAPON
	r[SndEventCodes.EVT_SW_CANCELLED] = R_SUPERWEAPON
	r[SndEventCodes.EVT_SW_EXEC_START] = R_SUPERWEAPON
	r[SndEventCodes.EVT_SW_IMPACT] = R_SUPERWEAPON


static func route_of(code: int) -> int:
	_build_routes()
	return int(_routes.get(code, R_IGNORE))


static func is_cosmetic(route: int) -> bool:
	return route == R_FIRED or route == R_PROJECTILE or route == R_EXPLOSION or route == R_DAMAGE or route == R_BEAM or route == R_INTERCEPT


func setup(p_reader: SndWorldReader, p_bank: SndSoundBank, p_pool: SndVoicePool, p_loops: SndLoopManager, p_meter: SndCombatMeter,
		p_announcer: SndAnnouncer, p_countdown: SndCountdown, p_scheduler: SndScheduler, p_mix: SndMixConfig, p_map: SndEventMap) -> void:
	reader = p_reader
	bank = p_bank
	pool = p_pool
	loops = p_loops
	meter = p_meter
	announcer = p_announcer
	countdown = p_countdown
	scheduler = p_scheduler
	mix = p_mix
	map = p_map
	_build_routes()
	var cap: int = SndConfig.MAX_CANDIDATES
	_c_def.resize(cap)
	_c_pos.resize(cap)
	_c_score.resize(cap)
	_c_gain.resize(cap)
	_c_flav.resize(cap)
	_c_delay.resize(cap)
	_c_low.resize(cap)
	_c_pitch.resize(cap)
	_last_fire_ms.resize(SndConfig.SOURCE_THROTTLE_SLOTS)
	_last_fire_ms.fill(-100000)
	_last_hit_ms.resize(SndConfig.SOURCE_THROTTLE_SLOTS)
	_last_hit_ms.fill(-100000)
	_boom_key.resize(64)
	_boom_tick.resize(64)
	_boom_tick.fill(-1)


func reset() -> void:
	_c_n = 0
	_throttle.clear()
	_proj_arch.clear()
	_boom_n = 0
	_boom_tick.fill(-1)
	decision_log = PackedStringArray()
	lines_said = PackedStringArray()


# ------------------------------------------------------------------ entry point

## The whole of audio spec 3.2 step 4 for one batch.
func process(batch: PackedInt32Array, _alpha: float, now_ms: int) -> void:
	if reader == null or not reader.is_bound():
		return
	_now = now_ms
	_focus = pool.listener_focus() if pool != null else Vector3.ZERO
	_c_n = 0
	var n: int = batch.size() / STRIDE
	var first_cosmetic: int = maxi(n - SndConfig.MAX_EVENTS_SCANNED, 0)
	for i: int in n:
		var o: int = i * STRIDE
		var t: int = batch[o]
		var route: int = route_of(t)
		if route == R_IGNORE:
			continue
		if is_cosmetic(route) and i < first_cosmetic:
			stats.add(&"cull_scan")
			continue
		_dispatch(t, route, batch, o)
	_flush_candidates()


func _dispatch(t: int, route: int, b: PackedInt32Array, o: int) -> void:
	_batch_tick = b[o + 1]
	match route:
		R_FIRED:
			_on_fire(b, o)
		R_PROJECTILE:
			_on_projectile(t, b, o)
		R_EXPLOSION:
			_on_impact(b, o)
		R_DAMAGE:
			_on_hit(b, o)
		R_BEAM:
			_on_beam(t, b, o)
		R_INTERCEPT:
			_on_intercept(b, o)
		R_DIED:
			_on_died(t, b, o)
		R_STATE:
			_on_state(t, b, o)
		R_CARGO:
			_on_cargo(t, b, o)
		R_ECONOMY:
			_on_economy(t, b, o)
		R_POWER_GRID:
			_on_power_grid(t, b, o)
		R_PRODUCTION:
			_on_production(t, b, o)
		R_SUPPORT_POWER:
			_on_support_power(t, b, o)
		R_SUPERWEAPON:
			_on_superweapon(t, b, o)
		R_ALERT:
			_on_alert(t, b, o)
		R_ORDER_FEEDBACK:
			_on_order_feedback(t, b, o)
		R_MATCH:
			_on_match(t, b, o)
		R_LIFECYCLE:
			_on_lifecycle(t, b, o)


# ------------------------------------------------------------------ helpers

func _is_viewer(pid: int) -> bool:
	return not observer and pid == reader.viewer_pid()


func _say(line: String, prio: int = -1) -> void:
	if observer:
		return
	if record_lines:
		lines_said.append(line)
	if announcer != null:
		announcer.say(StringName(line), prio)


func _ground_dist_m(pos: Vector3) -> float:
	return Vector2(pos.x - _focus.x, pos.z - _focus.z).length()


func _height_for(layer: int) -> float:
	return mix.source_height_air_m if layer == AIR_LAYER else mix.source_height_ground_m


func _pos_of(x: int, y: int, layer: int = 0) -> Vector3:
	return SndUnits.to_world(x, y, _height_for(layer))


## Fog rule of audio spec 5.5. Returns FOG_DROP / FOG_OK / FOG_MUFFLED.
func _audibility(def: SndEventDef, owner: int, x: int, y: int, pos: Vector3) -> int:
	if def.spatial != SndEventDef.Spatial.WORLD_3D:
		return FOG_OK
	if reader.omniscient:
		return FOG_OK
	var rel: int = reader.relation_of(owner) if owner >= 0 else SndWorldReader.REL_ENEMY
	if rel == SndWorldReader.REL_SELF or rel == SndWorldReader.REL_ALLY:
		return FOG_OK
	if reader.cell_visible(x >> SndConfig.CELL_SHIFT, y >> SndConfig.CELL_SHIFT):
		return FOG_OK
	match def.fog:
		SndEventDef.Fog.AUDIBLE:
			return FOG_OK
		SndEventDef.Fog.MUFFLED:
			return FOG_MUFFLED if _ground_dist_m(pos) <= mix.loud_fog_radius_m else FOG_DROP
	return FOG_DROP


## Queues a positional (or flat) sound; returns false when it was culled before ranking.
func _cand(def: SndEventDef, pos: Vector3, flavour: StringName, gain_db: float, owner: int, x: int, y: int, delay_ms: int = 0, pitch: float = 1.0) -> bool:
	if def == null:
		return false
	var low: float = 0.0
	var g: float = gain_db
	if def.spatial == SndEventDef.Spatial.WORLD_3D:
		if _ground_dist_m(pos) > mix.max_scan_m * zoom_scale:
			stats.add(&"cull_far")
			return false
		var a: int = _audibility(def, owner, x, y, pos)
		if a == FOG_DROP:
			stats.add(&"cull_fog")
			return false
		if a == FOG_MUFFLED:
			g += def.fog_gain_db
			low = minf(def.lowpass_hz, def.fog_lowpass_hz)
	if _c_n >= SndConfig.MAX_CANDIDATES:
		stats.add(&"cull_capacity")
		return false
	var wait_ms: int = delay_ms
	if def.propagation and wait_ms == 0 and def.spatial == SndEventDef.Spatial.WORLD_3D:
		wait_ms = mini(int(_ground_dist_m(pos) / maxf(mix.speed_of_sound_mps, 1.0) * 1000.0), mix.max_delay_ms)
	var est: float = pool.estimate_db(def, pos, g) if pool != null else def.volume_db + g
	var i: int = _c_n
	_c_def[i] = def
	_c_pos[i] = pos
	_c_gain[i] = g
	_c_flav[i] = flavour
	_c_delay[i] = wait_ms
	_c_low[i] = low
	_c_pitch[i] = pitch
	_c_score[i] = float(def.priority) + 0.5 * est
	_c_n += 1
	return true


func _flat(event_id: String, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	if observer:
		return
	var def: SndEventDef = map.get_def(StringName(event_id))
	_cand(def, Vector3.ZERO, &"", gain_db, -1, 0, 0, 0, pitch)


func _at(event_id: String, x: int, y: int, owner: int, layer: int = 0, gain_db: float = 0.0, flavour: StringName = &"", delay_ms: int = 0, pitch: float = 1.0) -> bool:
	var def: SndEventDef = map.get_def(StringName(event_id))
	if def == null:
		return false
	return _cand(def, _pos_of(x, y, layer), flavour, gain_db, owner, x, y, delay_ms, pitch)


func _throttled(key: String, gap_ms: int) -> bool:
	var last: int = int(_throttle.get(key, -100000))
	if _now - last < gap_ms:
		return true
	_throttle[key] = _now
	if _throttle.size() > 512:
		_throttle.clear()
	return false


func _flush_candidates() -> void:
	if _c_n == 0:
		return
	var order: Array[int] = []
	order.resize(_c_n)
	for i: int in _c_n:
		order[i] = i
	order.sort_custom(func(a: int, b: int) -> bool:
		if _c_score[a] != _c_score[b]:
			return _c_score[a] > _c_score[b]
		return _c_def[a].index < _c_def[b].index)
	var cap: int = mix.max_starts_per_frame
	for k: int in order.size():
		var i: int = order[k]
		if k >= cap:
			stats.add(&"cull_frame")
			continue
		var d: SndEventDef = _c_def[i]
		if _c_delay[i] > 0 and scheduler != null:
			var queued: bool = scheduler.push(_now + _c_delay[i], d, _c_pos[i], _c_flav[i], _c_gain[i], 0)
			if not queued:
				stats.add(&"cull_sched")
			if log_decisions:
				decision_log.append("%s@%.1f,%.1f %.1f %s %d" % [String(d.id), _c_pos[i].x, _c_pos[i].z, _c_gain[i], String(_c_flav[i]), 1 if queued else 0])
			continue
		var h: int = pool.play_def(d, _c_pos[i], _c_flav[i], _c_gain[i], _c_pitch[i], 0, _c_low[i])
		if log_decisions:
			decision_log.append("%s@%.1f,%.1f %.1f %s %d" % [String(d.id), _c_pos[i].x, _c_pos[i].z, _c_gain[i], String(_c_flav[i]), 1 if h != 0 else 0])
	_c_n = 0


## Plays due scheduled sounds (call once per frame).
func run_scheduler(now_ms: int) -> void:
	if scheduler == null or scheduler.size() == 0:
		return
	var due: Array[Dictionary] = []
	scheduler.pop_due(now_ms, due)
	for it: Dictionary in due:
		pool.play_def(it["def"], it["pos"], it["flavour"], it["gain"])


# ------------------------------------------------------------------ combat

func _flavour_for(e: SimEntity) -> StringName:
	if e == null:
		return &""
	var f: String = bank.faction_of(e.kind, e.def_idx)
	if f == "":
		f = reader.faction_code_of_owner(e.owner)
	return StringName(f)


func _on_fire(b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var shooter: int = b[o + 4]
	var arch: int = b[o + 5]
	var result: int = (b[o + 6] >> 12) & 15
	if result == 3:
		return  # beam weapons are voiced by BEAM_START / BEAM_END
	var slot: int = shooter & (SndConfig.SOURCE_THROTTLE_SLOTS - 1)
	if _now - _last_fire_ms[slot] < 40:
		stats.add(&"cull_source")
		return
	var e: SimEntity = reader.entity(shooter)
	var variant: String = ""
	if e != null:
		var prof: SndProfileDef = bank.profile_of(e.kind, e.def_idx)
		if prof != null:
			variant = str(prof.weapon_variant.get(SndUnits.arch_name(arch), ""))
	var def: SndEventDef = bank.fire_def(arch, variant)
	if def == null:
		return
	var owner: int = e.owner if e != null else -1
	var layer: int = e.layer if e != null else 0
	if _cand(def, _pos_of(x, y, layer), _flavour_for(e), 0.0, owner, x, y):
		_last_fire_ms[slot] = _now
		_meter_fire(def, _pos_of(x, y, layer), owner)


func _meter_fire(def: SndEventDef, pos: Vector3, owner: int) -> void:
	if meter == null:
		return
	var w: float
	if def.priority < 40:
		w = meter.weight("fire_small", 0.3)
	elif def.priority < 55:
		w = meter.weight("fire_medium", 0.6)
	elif def.priority < 65:
		w = meter.weight("fire_heavy", 1.0)
	else:
		w = meter.weight("fire_artillery", 1.2)
	var rel: int = reader.relation_of(owner) if owner >= 0 else SndWorldReader.REL_ENEMY
	meter.add(w, _ground_dist_m(pos), rel == SndWorldReader.REL_SELF or rel == SndWorldReader.REL_ALLY)


func _on_projectile(t: int, b: PackedInt32Array, o: int) -> void:
	var serial: int = b[o + 4]
	if t == SndEventCodes.EV_PROJ_END:
		if loops != null:
			loops.remove_path_voice(serial, 60)
		return
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var arch: int = b[o + 5]
	var c: int = b[o + 6]
	var owner: int = c & 15
	var flight_ticks: int = c >> 16
	var ex: int = b[o + 8]
	var ey: int = b[o + 9]
	if _proj_arch.size() > 512:
		_proj_arch.clear()
	_proj_arch[serial] = arch
	var fclass: int = int(bank.arch_flight[arch]) if arch >= 0 and arch < bank.arch_flight.size() else 0
	var ms_per_tick: int = 50
	match fclass:
		SndUnits.FLIGHT_MISSILE, SndUnits.FLIGHT_TORPEDO:
			var id: StringName = &"snd.proj.missile" if fclass == SndUnits.FLIGHT_MISSILE else &"snd.proj.torpedo"
			var def: SndEventDef = map.get_def(id)
			if def != null and loops != null and _audibility(def, owner, x, y, _pos_of(x, y)) != FOG_DROP:
				loops.add_path_voice(serial, def, _pos_of(x, y, 0), _pos_of(ex, ey, 0), _now, flight_ticks * ms_per_tick, &"", 0.0)
		SndUnits.FLIGHT_ARC:
			if flight_ticks >= 24:
				var wdef: SndEventDef = map.get_def(&"snd.proj.shell_whistle")
				if wdef != null and _audibility(wdef, owner, ex, ey, _pos_of(ex, ey)) != FOG_DROP:
					_cand(wdef, _pos_of(ex, ey), &"", 0.0, owner, ex, ey, (flight_ticks - 20) * ms_per_tick)
		SndUnits.FLIGHT_BOMB:
			var bdef: SndEventDef = map.get_def(&"snd.proj.bomb_whistle")
			if bdef != null:
				_cand(bdef, _pos_of(ex, ey), &"", 0.0, owner, ex, ey, maxi(flight_ticks * ms_per_tick - 800, 0))


func _boom_seen(tick: int, x: int, y: int) -> bool:
	var key: int = ((x >> 9) << 16) ^ (y >> 9)
	for i: int in 64:
		if _boom_tick[i] == tick and _boom_key[i] == key:
			return true
	_boom_key[_boom_n & 63] = key
	_boom_tick[_boom_n & 63] = tick
	_boom_n += 1
	return false


func _size_of(radius: int) -> int:
	return SndUnits.size_of_radius(radius, mix.size_small, mix.size_medium, mix.size_large)


func _explosion_event(size: int, water: bool) -> String:
	var nm: String = SndUnits.SIZE_NAMES[size]
	if water and size != SndUnits.Size.HUGE:
		return "snd.explosion.water." + nm
	return "snd.explosion." + nm


func _terrain_material_at(x: int, y: int) -> int:
	return mix.material_of_terrain(reader.terrain_id(x >> SndConfig.CELL_SHIFT, y >> SndConfig.CELL_SHIFT))


func _on_impact(b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var wh: int = b[o + 4]
	var serial: int = b[o + 5]
	var hit_kind: int = b[o + 6] & 15
	var radius: int = b[o + 7]
	var owner: int = b[o + 9] & 15
	if loops != null and serial >= 0:
		loops.remove_path_voice(serial, 60)
	var kind: int = SndUnits.Kind.EXPLOSIVE
	if serial >= 0 and _proj_arch.has(serial):
		kind = SndUnits.arch_kind(int(_proj_arch[serial]))
		_proj_arch.erase(serial)
	else:
		var dt: int = reader.warhead_dtype(owner, wh)
		if dt >= 0:
			kind = SndUnits.kind_of_dtype(dt)
	var size: int = _size_of(radius)
	var mat: int = _terrain_material_at(x, y)
	var id: String = ""
	match kind:
		SndUnits.Kind.EXPLOSIVE:
			if _boom_seen(_batch_tick, x, y):
				return
			id = _explosion_event(size, mat == SndUnits.Mat.WATER or hit_kind == 4)
		SndUnits.Kind.BULLET:
			if hit_kind == 0 or hit_kind == 4:
				id = "snd.impact.bullet." + SndUnits.MAT_NAMES[mat]
		SndUnits.Kind.ENERGY:
			id = "snd.impact.energy." + ("small" if size <= SndUnits.Size.MEDIUM else "large")
		SndUnits.Kind.RAIL:
			id = "snd.impact.rail"
		SndUnits.Kind.KINETIC:
			id = "snd.impact.kinetic"
		SndUnits.Kind.EMP:
			id = "snd.impact.emp"
	if id == "":
		return
	if _at(id, x, y, owner) and meter != null:
		meter.add(meter.weight("impact_base", 0.3) + meter.weight("impact_per_size", 0.25) * float(size), _ground_dist_m(_pos_of(x, y)), _is_viewer(owner))


func _on_hit(b: PackedInt32Array, o: int) -> void:
	var d: int = b[o + 7]
	var dtype: int = d & 255
	var dc: int = (d >> 8) & 255
	if (dc & SndEventCodes.DC_SPLASH) != 0:
		return
	var kind: int = SndUnits.kind_of_dtype(dtype)
	if kind != SndUnits.Kind.BULLET and kind != SndUnits.Kind.ENERGY:
		return
	var victim: int = b[o + 4]
	var slot: int = victim & (SndConfig.SOURCE_THROTTLE_SLOTS - 1)
	var gap: int = 60 if kind == SndUnits.Kind.BULLET else 150
	if _now - _last_hit_ms[slot] < gap:
		stats.add(&"cull_source")
		return
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var e: SimEntity = reader.entity(victim)
	var owner: int = e.owner if e != null else -1
	var id: String
	if kind == SndUnits.Kind.BULLET:
		var mat: int = SndUnits.Mat.METAL
		if e != null:
			mat = SndUnits.material_of_armor(bank.unit_armor[e.def_idx] if e.kind == SimEntity.Kind.UNIT and e.def_idx < bank.unit_armor.size() else reader.structure_armor(e.def_idx))
		id = "snd.impact.bullet." + SndUnits.MAT_NAMES[mat]
	else:
		id = "snd.impact.energy.small"
	if _at(id, x, y, owner, e.layer if e != null else 0):
		_last_hit_ms[slot] = _now


func _on_beam(t: int, b: PackedInt32Array, o: int) -> void:
	var shooter: int = b[o + 4]
	if t == SndEventCodes.EV_BEAM_END:
		if loops != null:
			loops.stop_beams_of(shooter)
		return
	var arch: int = b[o + 5]
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var e: SimEntity = reader.entity(shooter)
	var def: SndEventDef = bank.fire_def(arch, "")
	if def == null:
		return
	var owner: int = e.owner if e != null else -1
	var pos: Vector3 = _pos_of(x, y, e.layer if e != null else 0)
	if _audibility(def, owner, x, y, pos) == FOG_DROP:
		return
	if loops != null:
		loops.start_beam(shooter, arch, def, _flavour_for(e))
	if meter != null:
		meter.add(meter.weight("beam_start", 0.5), _ground_dist_m(pos), _is_viewer(owner))


func _on_intercept(b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var interceptor: int = b[o + 5]
	var e: SimEntity = reader.entity(interceptor)
	var zone: bool = e != null and e.kind == SimEntity.Kind.ZONE
	var kind: int = b[o + 6]
	_at("snd.intercept.zone" if (zone or kind == 1) else "snd.intercept.aps", x, y, e.owner if e != null else -1)


func _on_died(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	if t == SndEventCodes.EV_CRASH:
		if b[o + 5] == 1 and not _boom_seen(_batch_tick, x, y):
			_at("snd.explosion.medium", x, y, -1, 0)
		return
	var id: int = b[o + 4]
	var def_idx: int = b[o + 5]
	var c: int = b[o + 6]
	var dk: int = c & 15
	var flags: int = (c >> 8) & 255
	var owner: int = ((b[o + 8] >> 8) & 255) - 1
	var f: int = b[o + 9]
	var layer: int = (f >> 12) & 15
	var is_struct: bool = (flags & 16) != 0
	var kind: int = SimEntity.Kind.STRUCTURE if is_struct else SimEntity.Kind.UNIT
	var tags: int = bank.tags_of(kind, def_idx)
	var own: bool = _is_viewer(owner)
	if own:
		if is_struct:
			if (tags & SndSoundBank.TAG_LAUNCHER) != 0:
				_say("superweapon_destroyed")
			else:
				_say("structure_lost")
		elif (tags & SndSoundBank.TAG_COLLECTOR) != 0:
			_say("collector_lost")
		else:
			_say("unit_lost")
	var pos: Vector3 = _pos_of(x, y, layer)
	if meter != null:
		var w: float = meter.weight("death_structure", 8.0) if is_struct else (meter.weight("death_unit_own", 4.0) if own else meter.weight("death_unit_enemy", 2.0))
		meter.add(w, _ground_dist_m(pos), own or reader.relation_of(owner) == SndWorldReader.REL_ALLY)
	var ev: String = ""
	if (flags & 4) != 0:
		ev = "snd.death.decoy"
	else:
		match dk:
			SndEventCodes.DK_INFANTRY:
				ev = "snd.death.infantry"
			SndEventCodes.DK_VEHICLE:
				ev = _vehicle_boom(def_idx)
			SndEventCodes.DK_CRASH:
				ev = "snd.air.crash_fall"
			SndEventCodes.DK_AIR_EXPLODE:
				ev = "snd.explosion.medium"
			SndEventCodes.DK_SINK:
				ev = "snd.death.sub" if layer == SimEntity.Layer.UNDERWATER else "snd.death.ship"
			SndEventCodes.DK_STRUCTURE:
				var area: int = int(bank.struct_area[def_idx]) if def_idx >= 0 and def_idx < bank.struct_area.size() else 1
				ev = "snd.collapse.s%d" % (area + 1)
			SndEventCodes.DK_DRONE:
				ev = "snd.death.drone"
	if ev == "":
		return
	if ev.begins_with("snd.explosion") and _boom_seen(_batch_tick, x, y):
		return
	_at(ev, x, y, owner, layer)
	if id == 0:
		return


func _vehicle_boom(def_idx: int) -> String:
	var armor: int = int(bank.unit_armor[def_idx]) if def_idx >= 0 and def_idx < bank.unit_armor.size() else 2
	if armor <= DefEnums.ArmorClass.LIGHT_VEHICLE:
		return "snd.explosion.small"
	if armor == DefEnums.ArmorClass.MEDIUM_ARMOR:
		return "snd.explosion.medium"
	return "snd.explosion.large"


# ------------------------------------------------------------------ state, cargo

func _on_state(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	match t:
		SndEventCodes.EV_EMP:
			if b[o + 8] == 0:  # not blocked by immunity
				var e: SimEntity = reader.entity(b[o + 4])
				_at("snd.emp.hit", x, y, e.owner if e != null else -1)
		SndEventCodes.EV_WEAPON_LOCK:
			if b[o + 5] != 1:
				return
			var e2: SimEntity = reader.entity(b[o + 4])
			if e2 == null or e2.kind != SimEntity.Kind.STRUCTURE or not _is_viewer(e2.owner):
				return
			var tags: int = bank.tags_of(e2.kind, e2.def_idx)
			if (tags & SndSoundBank.TAG_DEFENSE) == 0:
				return
			if not _throttled("defoff%d" % e2.id, 2000):
				_at("snd.struct.defense_offline", e2.x, e2.y, e2.owner)
			if b[o + 6] == 0:
				_say("systems_disabled")
			elif b[o + 6] == 2 and _now - _defense_line_ms > 30000:
				_defense_line_ms = _now
				_say("defenses_offline")
		SndEventCodes.EV_CLOAK_CHANGED:
			var e3: SimEntity = reader.entity(b[o + 4])
			if e3 != null and reader.entity_visible(e3):
				_at("snd.power.cloak.activate" if b[o + 5] == 1 else "snd.power.cloak.end", e3.x, e3.y, e3.owner, e3.layer, -8.0)
		SndEventCodes.EV_AIR_TAKEOFF, SndEventCodes.EV_AIR_LANDED:
			var e4: SimEntity = reader.entity(b[o + 4])
			if e4 != null:
				_at("snd.air.takeoff" if t == SndEventCodes.EV_AIR_TAKEOFF else "snd.air.landing", x, y, e4.owner, 1)
		SndEventCodes.EVT_STRUCTURE_SELLING:
			_at("snd.struct.sell", x, y, b[o + 4])
		SndEventCodes.EVT_REPAIR_STATE:
			var id: int = b[o + 5]
			var e5: SimEntity = reader.entity(id)
			if loops == null or e5 == null:
				return
			if b[o + 6] == 1:
				loops.bind_loop(id * 8 + 1, id, map.get_def(&"snd.struct.repair"), _flavour_for(e5))
			else:
				loops.unbind_loop(id * 8 + 1)


func _on_cargo(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var carrier: SimEntity = null
	var gain: float = 0.0
	if t == SndEventCodes.EV_LOADED:
		carrier = reader.entity(b[o + 5])
		gain = -4.0
	elif t == SndEventCodes.EV_UNLOADED:
		carrier = reader.entity(b[o + 5])
	else:
		carrier = reader.entity(b[o + 4])
	if carrier != null:
		x = carrier.x
		y = carrier.y
	if x == 0 and y == 0:
		return
	_at("snd.struct.unit_out.infantry", x, y, carrier.owner if carrier != null else -1, 0, gain)


# ------------------------------------------------------------------ economy, production, power

func _on_lifecycle(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	match t:
		SndEventCodes.EVT_STRUCTURE_PLACED:
			var owner: int = b[o + 4]
			var e: SimEntity = reader.entity(b[o + 5])
			var kind: String = _online_kind(b[o + 6])
			if kind == "" or kind == "hq":
				return
			_at("snd.struct.online." + kind, x, y, owner, 0, 0.0, _flavour_for(e))
		SndEventCodes.EVT_HQ_DEPLOYED:
			_at("snd.struct.hq_deploy", x, y, b[o + 4])
		SndEventCodes.EVT_STRUCTURE_CAPTURED:
			var new_pid: int = b[o + 4]
			var old_pid: int = b[o + 6]
			if _is_viewer(new_pid):
				_say("building_captured")
				_at("snd.struct.captured", x, y, new_pid)
			elif _is_viewer(old_pid):
				_say("structure_captured")
				_flat("snd.alarm.base_attack")
				if meter != null:
					meter.add_urgent(meter.weight("alert_own", 20.0))
				_urgent()


## snd.struct.online.<kind> for a structure def index (profile id decides; launchers and advanced defences are generic classes).
func _online_kind(s_idx: int) -> String:
	if bank == null or s_idx < 0 or s_idx >= bank.struct_profile.size():
		return ""
	var pid: String = String(bank.struct_profile[s_idx].id)
	var k: String = pid.get_slice(".", pid.get_slice_count(".") - 1)
	if pid.begins_with("snd.profile.struct."):
		k = pid.trim_prefix("snd.profile.struct.")
		if k.begins_with("sw_"):
			return "superweapon"
		if k.begins_with("adv_"):
			return "adv_defense"
		return k
	return ""


func _urgent() -> void:
	if on_urgent.is_valid():
		on_urgent.call()


func _on_economy(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	match t:
		SndEventCodes.CASH:
			# reasons SELL / harvest / salvage are voiced by their own events; only refunds tick here
			if _is_viewer(b[o + 4]) and b[o + 5] > 0 and b[o + 7] == 3:
				_flat("snd.eco.cash")
		SndEventCodes.EVT_CREDITS_GAINED, SndEventCodes.EVT_SALVAGE_PAID:
			var amount: int = b[o + 5]
			if not _is_viewer(b[o + 4]) or amount <= 0:
				return
			var px: int = b[o + 6] if b[o + 6] != 0 else x
			var py: int = b[o + 7] if b[o + 7] != 0 else y
			if _throttled("cash", 120):
				return
			var big: bool = amount > 500
			_at("snd.eco.cash_big" if big else "snd.eco.cash", px, py, b[o + 4], 0, 0.0, &"", 0, 1.0 + minf(float(amount), 1000.0) / 1000.0 * 0.12)
		SndEventCodes.EVT_STRUCTURE_SOLD:
			if _is_viewer(b[o + 4]):
				_flat("snd.eco.cash_big")
				_say("structure_sold")


func _on_power_grid(t: int, b: PackedInt32Array, _o: int) -> void:
	var pid: int = b[_o + 4]
	if not _is_viewer(pid):
		return
	if t == SndEventCodes.EVT_POWER_SHORTAGE:
		_flat("snd.struct.power_down")
		_say("low_power")
	else:
		_flat("snd.struct.power_up")
		_say("power_restored")


func _on_production(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var pid: int = b[o + 4]
	if not _is_viewer(pid):
		if t == SndEventCodes.EVT_UNIT_PRODUCED:
			pass
		else:
			return
	match t:
		SndEventCodes.EVT_STRUCTURE_READY:
			_say("construction_complete")
			_flat("snd.ui.build_ready")
		SndEventCodes.EVT_UNIT_PRODUCED:
			if _is_viewer(pid):
				_say("unit_ready")
			var producer: SimEntity = reader.entity(b[o + 7])
			var px: int = producer.x if producer != null else x
			var py: int = producer.y if producer != null else y
			if not _throttled("unitout%d" % b[o + 7], 250):
				_at("snd.struct.unit_out." + _unit_out_class(b[o + 6]), px, py, pid)
		SndEventCodes.EVT_RESEARCH_COMPLETE:
			_say("research_complete")
			_flat("snd.ui.build_ready")
		SndEventCodes.EVT_INSUFFICIENT_FUNDS:
			_say("insufficient_funds")
			_flat("snd.ui.error")
		SndEventCodes.EVT_UNIT_CAP_REACHED:
			_say("unit_cap_reached")
		SndEventCodes.EVT_QUEUE_STATE:
			if b[o + 6] == SndEventCodes.QS_HOLD:
				_say("on_hold")


func _unit_out_class(u_idx: int) -> String:
	if u_idx < 0 or u_idx >= bank.unit_layer.size():
		return "vehicle"
	var layer: int = bank.unit_layer[u_idx]
	if layer == SimEntity.Layer.AIR:
		return "aircraft"
	if layer == SimEntity.Layer.SURFACE or layer == SimEntity.Layer.UNDERWATER:
		return "ship"
	if bank.unit_armor[u_idx] == DefEnums.ArmorClass.INFANTRY:
		return "infantry"
	return "vehicle"


func _on_support_power(t: int, b: PackedInt32Array, o: int) -> void:
	match t:
		SndEventCodes.EVT_POWER_READY:
			if _is_viewer(b[o + 4]):
				_say("power_ready")
		SndEventCodes.EVT_POWER_ACTIVATED:
			_on_power_activated(b, o)


func _on_power_activated(b: PackedInt32Array, o: int) -> void:
	var pid: int = b[o + 4]
	var slot: int = b[o + 5]
	var idx: int = b[o + 6]
	var x: int = b[o + 7]
	var y: int = b[o + 8]
	var own: bool = _is_viewer(pid)
	if slot == SndEventCodes.SLOT_SW:
		var rel: int = reader.relation_of(pid)
		if rel == SndWorldReader.REL_SELF or rel == SndWorldReader.REL_ALLY:
			_say("sw_launched")
		return
	if idx < 0 or idx >= bank.power_cue.size():
		return
	var cues: Dictionary = bank.power_cue[idx]
	var act: SndEventDef = cues.get(&"activate")
	if act != null:
		_cand(act, _pos_of(x, y), &"", 0.0, pid, x, y)
	if own:
		_flat("snd.ui.confirm")
	var wt: int = bank.power_warning_ticks[idx]
	if wt > 0 and not own and reader.relation_of(pid) != SndWorldReader.REL_ALLY and countdown != null:
		countdown.on_power_warning(idx, x, y, _batch_tick + wt, bank.power_radius[idx], true)
		if reader.team_within(x, y, bank.power_radius[idx] + 3072):
			_say("sw_incoming_strike")
			_flat("snd.alarm.incoming")


# ------------------------------------------------------------------ superweapons

func _sw_extent(sw_idx: int) -> int:
	if sw_idx >= 0 and sw_idx < bank.sw_radius.size() and bank.sw_radius[sw_idx] > 0:
		return bank.sw_radius[sw_idx]
	return 8 * SndConfig.UNITS_PER_CELL


func _on_superweapon(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	match t:
		SndEventCodes.EVT_WARNING:
			_on_warning(b[o + 5], b[o + 6], b[o + 7], x, y)
		SndEventCodes.EV_SCAN_WARNING:
			var owner: int = b[o + 7]
			if reader.relation_of(owner) == SndWorldReader.REL_ENEMY and not _is_viewer(owner):
				var rad: int = b[o + 6] * SndConfig.UNITS_PER_CELL
				if reader.team_within(x, y, rad + 3072):
					_say("scan_detected")
		SndEventCodes.EVT_SW_READY:
			if _is_viewer(b[o + 4]):
				_say("sw_ready")
		SndEventCodes.EVT_SW_CANCELLED:
			var owner2: int = b[o + 4]
			var sw: int = b[o + 5]
			if countdown != null:
				countdown.on_cancelled(owner2, sw)
			if reader.team_within(x, y, _sw_extent(sw) + 3072) or _is_viewer(owner2):
				_say("sw_cancelled")
		SndEventCodes.EVT_SW_EXEC_START:
			var owner3: int = b[o + 4]
			var sw3: int = b[o + 5]
			if countdown != null:
				countdown.on_cancelled(owner3, sw3)
			_on_sw_launch(owner3, sw3, x, y)
		SndEventCodes.EVT_SW_IMPACT:
			_on_sw_impact(b[o + 4], x, y, b[o + 7], b[o + 8])


func _on_warning(owner: int, kind: int, src_idx: int, x: int, y: int) -> void:
	var rel: int = reader.relation_of(owner)
	var hostile: bool = rel == SndWorldReader.REL_ENEMY or rel == SndWorldReader.REL_NEUTRAL
	if kind == SndEventCodes.WK_SUPER:
		var wt: int = int(bank.sw_warning_ticks[src_idx]) if src_idx >= 0 and src_idx < bank.sw_warning_ticks.size() else 200
		var extent: int = _sw_extent(src_idx)
		if hostile:
			_say("sw_launch_detected")
			if countdown != null:
				countdown.on_warning(owner, src_idx, x, y, _batch_tick + wt, extent, 0, true)
		if meter != null and reader.team_within(x, y, extent + 3072):
			meter.add_urgent(meter.weight("strategic", 30.0))
			_urgent()
	elif kind == SndEventCodes.WK_POWER:
		if hostile:
			var wtp: int = int(bank.power_warning_ticks[src_idx]) if src_idx >= 0 and src_idx < bank.power_warning_ticks.size() else 0
			var rad: int = int(bank.power_radius[src_idx]) if src_idx >= 0 and src_idx < bank.power_radius.size() else 0
			if reader.team_within(x, y, rad + 3072):
				_say("sw_incoming_strike")
				_flat("snd.alarm.incoming")
			if countdown != null and wtp > 0:
				countdown.on_power_warning(src_idx, x, y, _batch_tick + wtp, rad, true)
	elif kind == SndEventCodes.WK_SCAN and hostile:
		_say("scan_detected")


func _on_sw_launch(owner: int, sw_idx: int, x: int, y: int) -> void:
	if sw_idx < 0 or sw_idx >= bank.sw_cue.size():
		return
	var cues: Dictionary = bank.sw_cue[sw_idx]
	var launch: SndEventDef = cues.get(&"launch")
	if launch != null:
		var pos: Vector3 = _pos_of(x, y)
		var lx: int = x
		var ly: int = y
		if launch.spatial == SndEventDef.Spatial.WORLD_3D:
			var l: SimEntity = reader.find_structure(owner, int(bank.sw_launcher[sw_idx])) if sw_idx < bank.sw_launcher.size() else null
			if l != null:
				lx = l.x
				ly = l.y
				pos = _pos_of(lx, ly)
		_cand(launch, pos, &"", 0.0, owner, lx, ly)
	var lp: SndEventDef = cues.get(&"loop")
	if lp != null and loops != null:
		var dur_ms: int = int(bank.sw_duration_ticks[sw_idx]) * 50
		loops.play_timed_loop(lp, _pos_of(x, y), maxi(dur_ms, 1000), sw_idx + 1000)


func _on_sw_impact(kind_id: int, x: int, y: int, radius: int, dtype: int) -> void:
	if kind_id >= 100:
		var size: int = _size_of(radius)
		if _boom_seen(_batch_tick, x, y):
			return
		_at(_explosion_event(size, false), x, y, -1)
		return
	if kind_id < 0 or kind_id >= bank.sw_cue.size():
		return
	var imp: SndEventDef = bank.sw_cue[kind_id].get(&"impact")
	if imp != null:
		_cand(imp, _pos_of(x, y), &"", 0.0, -1, x, y)
	if meter != null:
		meter.add_urgent(meter.weight("strategic", 30.0))
	if dtype < -1:
		return


# ------------------------------------------------------------------ alerts, feedback, match

func _on_alert(t: int, b: PackedInt32Array, o: int) -> void:
	var x: int = b[o + 2]
	var y: int = b[o + 3]
	var victim_pid: int = b[o + 4]
	var cls: int = -1
	if t == SndEventCodes.EV_ATTACK_ALERT:
		cls = b[o + 7]
	else:
		cls = 2  # collector
	var pos: Vector3 = _pos_of(x, y)
	var offscreen: bool = _ground_dist_m(pos) > mix.offscreen_alert_m * maxf(zoom_scale, 0.6)
	if _is_viewer(victim_pid):
		match cls:
			1:
				_say("base_under_attack")
				_flat("snd.alarm.base_attack")
				if meter != null:
					meter.add_urgent(meter.weight("alert_own", 20.0))
				_urgent()
			2:
				_say("collector_under_attack")
			3:
				if offscreen:
					_say("aircraft_under_attack")
			_:
				if offscreen:
					_say("unit_under_attack")
	elif not observer and reader.relation_of(victim_pid) == SndWorldReader.REL_ALLY and offscreen:
		_say("ally_under_attack")


func _voice_class_of(e: SimEntity) -> int:
	var p: SndProfileDef = bank.profile_of(e.kind, e.def_idx)
	return p.voice_class if p != null else SndUnits.VoiceClass.VEHICLE


func _on_order_feedback(t: int, b: PackedInt32Array, o: int) -> void:
	match t:
		SndEventCodes.ORDER_FAILED, SndEventCodes.EV_MOVE_FAILED:
			var e: SimEntity = reader.entity(b[o + 4])
			if e != null and _is_viewer(e.owner) and responses != null:
				responses.on_denied(_voice_class_of(e), _now)
		SndEventCodes.EVT_ORDER_FAILED:
			var e2: SimEntity = reader.entity(b[o + 5])
			if e2 != null and _is_viewer(e2.owner) and responses != null:
				responses.on_denied(_voice_class_of(e2), _now)
		SndEventCodes.CMD_REJECTED:
			if not _is_viewer(b[o + 4]):
				return
			var err: int = b[o + 6]
			if err == SndEventCodes.ERR_NO_CREDITS or err == SndEventCodes.ERR_UNIT_CAP:
				return  # voiced by the production events
			if err == SndEventCodes.ERR_BAD_SITE:
				_flat("snd.ui.place_fail")
				_say("cannot_deploy")
			else:
				_flat("snd.ui.error")
				_say("unable_to_comply")


func _on_match(t: int, b: PackedInt32Array, o: int) -> void:
	if t == SndEventCodes.PLAYER_ELIMINATED:
		var pid: int = b[o + 4]
		var reason: int = b[o + 5]
		if _is_viewer(pid):
			return
		if reason == SndEventCodes.ELIM_DISCONNECT:
			_say("player_disconnected")
		elif reader.relation_of(pid) == SndWorldReader.REL_ALLY:
			_say("ally_defeated")
		else:
			_say("enemy_defeated")
	elif t == SndEventCodes.MATCH_END:
		var winner_team: int = b[o + 4]
		var result: int = SndMatchConfig.RESULT_DRAW
		if winner_team >= 0:
			result = SndMatchConfig.RESULT_VICTORY if winner_team == reader.viewer_team() else SndMatchConfig.RESULT_DEFEAT
		if on_match_end.is_valid():
			on_match_end.call(result)
