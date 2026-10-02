class_name FxEventRouter
extends RefCounted
## VIEW-F4: turns the kernel's event batch into effects (render spec 5.9, 6.2). Table driven: `TABLE` maps the REAL event constants
## (core 1-9, movement 100-109, combat 200-220, abilities 230-259, economy 300-410; the render spec's DIED / DAMAGE / STATE names do
## not exist in the kernel, see docs/DEVIATIONS) to handler ids, `IGNORED` lists the codes that have no world visual on purpose, so
## the coverage test can prove that every SimEvent code is either handled or consciously skipped.
##
## Plug-in: `attach(view)` sets `view.router.extra_handler`, which calls `handle(events, o)` for every record right after the
## entity mirror handled it (so `ViewEntity.dead / dying_kind / hp` are already up to date). `process_batch(events)` runs a whole
## batch without the mirror (tests). Records are read by payload; the live sim is only consulted for geometry the events do not
## carry (zone shapes, warning records, the projectile pool).
##
## Rules (5.9): visibility gating with the local fog (`allowed`), explosion dedupe (a death next to a detonation of radius >= 2 m
## drops its own fireball), hit / miss of instant weapons from EV_FIRE.result (fallback: EV_HIT of the same attacker / victim in the
## batch), camera shake through the effects themselves (FxManager.camera_shake), damage emitters capped at 24 (FxAmbient).

const H_NONE: int = 0
const H_SPAWNED: int = 1
const H_REMOVED: int = 2
const H_OWNER: int = 3
const H_FIRE: int = 10
const H_PROJ_SPAWN: int = 11
const H_PROJ_END: int = 12
const H_IMPACT: int = 13
const H_HIT: int = 14
const H_BEAM_START: int = 15
const H_BEAM_END: int = 16
const H_SWEEP: int = 17
const H_DEATH: int = 18
const H_WRECK_ADD: int = 19
const H_WRECK_REMOVE: int = 20
const H_INTERCEPT: int = 21
const H_EMP: int = 22
const H_REARM: int = 23
const H_DRONE: int = 24
const H_EJECT: int = 25
const H_CRASH: int = 26
const H_TAKEOFF: int = 27
const H_LANDED: int = 28
const H_MEDIUM: int = 29
const H_LAYER: int = 30
const H_CLOAK: int = 40
const H_MODE_DONE: int = 41
const H_FX_APPLIED: int = 42
const H_UNLOADED: int = 43
const H_DROWNED: int = 44
const H_ZONE_SPAWNED: int = 45
const H_ZONE_ENDED: int = 46
const H_SUMMONED: int = 47
const H_SUMMON_EXPIRED: int = 48
const H_SALVAGE_DONE: int = 49
const H_CAPTURE_DONE: int = 50
const H_REPAIR_PULSE: int = 51
const H_DECOY_ID: int = 52
const H_SWARM: int = 53
const H_ENGINE: int = 54
const H_MARKED: int = 55
const H_BUFF: int = 56
const H_STRUCT_PLACED: int = 60
const H_STRUCT_ACTIVE: int = 61
const H_UNIT_PRODUCED: int = 62
const H_CREDITS: int = 63
const H_HQ_DEPLOYED: int = 64
const H_SALVAGE_STARTED: int = 65
const H_STRUCT_CAPTURED: int = 66
const H_POWER_USED: int = 70
const H_WARNING: int = 71
const H_SW_CANCELLED: int = 72
const H_SW_EXEC: int = 73
const H_SW_IMPACT: int = 74
const H_SW_DONE: int = 75
const H_SUMMON_EXPIRED_ECON: int = 76

## [handler, constant class, constant name]. The class names resolve through `_constants_of`.
const TABLE: Array[Array] = [
	[H_SPAWNED, "SimEvent", "SPAWNED"], [H_REMOVED, "SimEvent", "REMOVED"], [H_OWNER, "SimEvent", "OWNER_CHANGED"],
	[H_TAKEOFF, "SimAirMove", "EV_AIR_TAKEOFF"], [H_LANDED, "SimAirMove", "EV_AIR_LANDED"],
	[H_MEDIUM, "SimMoveConfig", "EV_MEDIUM_CHANGED"], [H_LAYER, "SimMoveConfig", "EV_LAYER_CHANGED"],
	[H_FIRE, "SimCombatConsts", "EV_FIRE"], [H_PROJ_SPAWN, "SimCombatConsts", "EV_PROJ_SPAWN"], [H_PROJ_END, "SimCombatConsts", "EV_PROJ_END"],
	[H_IMPACT, "SimCombatConsts", "EV_IMPACT"], [H_HIT, "SimCombatConsts", "EV_HIT"], [H_BEAM_START, "SimCombatConsts", "EV_BEAM_START"],
	[H_BEAM_END, "SimCombatConsts", "EV_BEAM_END"], [H_SWEEP, "SimCombatConsts", "EV_SWEEP"], [H_DEATH, "SimCombatConsts", "EV_DEATH"],
	[H_WRECK_ADD, "SimCombatConsts", "EV_WRECK_ADD"], [H_WRECK_REMOVE, "SimCombatConsts", "EV_WRECK_REMOVE"],
	[H_INTERCEPT, "SimCombatConsts", "EV_INTERCEPT"], [H_EMP, "SimCombatConsts", "EV_EMP"], [H_REARM, "SimCombatConsts", "EV_REARM"],
	[H_DRONE, "SimCombatConsts", "EV_DRONE"], [H_EJECT, "SimCombatConsts", "EV_EJECT"], [H_CRASH, "SimCombatConsts", "EV_CRASH"],
	[H_CLOAK, "SimAbilityConsts", "EV_CLOAK_CHANGED"], [H_MODE_DONE, "SimAbilityConsts", "EV_MODE_CHANGED"],
	[H_FX_APPLIED, "SimAbilityConsts", "EV_FX_APPLIED"], [H_UNLOADED, "SimAbilityConsts", "EV_UNLOADED"],
	[H_UNLOADED, "SimAbilityConsts", "EV_EJECTED"], [H_DROWNED, "SimAbilityConsts", "EV_DROWNED"],
	[H_ZONE_SPAWNED, "SimZoneConsts", "EV_ZONE_SPAWNED"], [H_ZONE_ENDED, "SimZoneConsts", "EV_ZONE_ENDED"],
	[H_SUMMONED, "SimZoneConsts", "EV_SUMMONED"], [H_SUMMON_EXPIRED, "SimZoneConsts", "EV_SUMMON_EXPIRED"],
	[H_SALVAGE_DONE, "SimAbilityConsts", "EV_SALVAGE_DONE"], [H_CAPTURE_DONE, "SimAbilityConsts", "EV_CAPTURE_DONE"],
	[H_REPAIR_PULSE, "SimAbilityConsts", "EV_REPAIR_PULSE"], [H_DECOY_ID, "SimAbilityConsts", "EV_DECOY_IDENTIFIED"],
	[H_SWARM, "SimZoneConsts", "EV_SWARM_LAUNCHED"], [H_ENGINE, "SimZoneConsts", "EV_ENGINE_ASSEMBLED"],
	[H_MARKED, "SimAbilityConsts", "EV_MARKED"], [H_BUFF, "SimAbilityConsts", "EV_BUFF_APPLIED"],
	[H_STRUCT_PLACED, "SimEconConst", "EVT_STRUCTURE_PLACED"], [H_STRUCT_ACTIVE, "SimEconConst", "EVT_STRUCTURE_ACTIVE"],
	[H_UNIT_PRODUCED, "SimEconConst", "EVT_UNIT_PRODUCED"], [H_CREDITS, "SimEconConst", "EVT_CREDITS_GAINED"],
	[H_CREDITS, "SimEconConst", "EVT_SALVAGE_PAID"], [H_HQ_DEPLOYED, "SimEconConst", "EVT_HQ_DEPLOYED"],
	[H_SALVAGE_STARTED, "SimEconConst", "EVT_SALVAGE_STARTED"], [H_STRUCT_CAPTURED, "SimEconConst", "EVT_STRUCTURE_CAPTURED"],
	[H_POWER_USED, "SimEconConst", "EVT_POWER_ACTIVATED"], [H_WARNING, "SimEconConst", "EVT_WARNING"],
	[H_SW_CANCELLED, "SimEconConst", "EVT_SW_CANCELLED"], [H_SW_EXEC, "SimEconConst", "EVT_SW_EXEC_START"],
	[H_SW_IMPACT, "SimEconConst", "EVT_SW_IMPACT"], [H_SW_DONE, "SimEconConst", "EVT_SW_DONE"],
	[H_SUMMON_EXPIRED_ECON, "SimEconConst", "EVT_SUMMON_EXPIRED"],
]

## Codes that never draw anything in the world (UI cues, bookkeeping, state that the entity mirror or another view module shows).
## Every entry says why in `IGNORE_WHY`; the coverage test requires that TABLE + IGNORED cover every kernel event constant.
const IGNORED: Array[Array] = [
	["SimEvent", "CASH"], ["SimEvent", "CMD_REJECTED"], ["SimEvent", "ORDER_FAILED"], ["SimEvent", "PLAYER_ELIMINATED"],
	["SimEvent", "MATCH_END"], ["SimEvent", "NAV_CHANGED"],
	["SimMoveConfig", "EV_MOVE_FAILED"], ["SimMoveConfig", "EV_STUCK"],
	["SimCombatConsts", "EV_SUPPRESS"], ["SimCombatConsts", "EV_ATTACK_ALERT"], ["SimCombatConsts", "EV_AIR_STATE"],
	["SimCombatConsts", "EV_WEAPON_LOCK"],
	["SimAbilityConsts", "EV_VIS_CHANGED"], ["SimAbilityConsts", "EV_GHOST_ADDED"], ["SimAbilityConsts", "EV_GHOST_REMOVED"],
	["SimAbilityConsts", "EV_MODE_STARTED"], ["SimAbilityConsts", "EV_ABILITY_USED"], ["SimAbilityConsts", "EV_ABILITY_READY"],
	["SimAbilityConsts", "EV_FX_REMOVED"], ["SimAbilityConsts", "EV_LOADED"], ["SimAbilityConsts", "EV_UNLOAD_BLOCKED"],
	["SimAbilityConsts", "EV_GARRISON_CHANGED"], ["SimAbilityConsts", "EV_SCAN_WARNING"],
	["SimEconConst", "EVT_CMD_REJECTED"], ["SimEconConst", "EVT_PLACE_REJECTED"], ["SimEconConst", "EVT_STRUCTURE_READY"],
	["SimEconConst", "EVT_QUEUE_STATE"], ["SimEconConst", "EVT_RESEARCH_COMPLETE"], ["SimEconConst", "EVT_INSUFFICIENT_FUNDS"],
	["SimEconConst", "EVT_UNIT_CAP_REACHED"], ["SimEconConst", "EVT_POWER_SHORTAGE"], ["SimEconConst", "EVT_POWER_RESTORED"],
	["SimEconConst", "EVT_SAP_RESERVE_EMPTY"], ["SimEconConst", "EVT_STRUCTURE_SOLD"], ["SimEconConst", "EVT_STRUCTURE_SELLING"],
	["SimEconConst", "EVT_REPAIR_STATE"], ["SimEconConst", "EVT_HQ_UNDEPLOYED"], ["SimEconConst", "EVT_ORDER_FAILED"],
	["SimEconConst", "EVT_COLLECTOR_ATTACKED"], ["SimEconConst", "EVT_NO_REFINERY"], ["SimEconConst", "EVT_DEPOSIT_DEPLETED"],
	["SimEconConst", "EVT_DEPOSIT_REGROWN"], ["SimEconConst", "EVT_CAPTURE_PROGRESS"], ["SimEconConst", "EVT_CAPTURE_CONTESTED"],
	["SimEconConst", "EVT_WRECKS_HIGHLIGHTED"], ["SimEconConst", "EVT_POWER_UNLOCKED"], ["SimEconConst", "EVT_POWER_READY"],
	["SimEconConst", "EVT_POWER_EFFECT_END"], ["SimEconConst", "EVT_SW_READY"],
]
const IGNORE_WHY: String = "UI / audio cue, sim bookkeeping, or shown by another view module (ViewEventRouter flags, RI2 structure states, zones and status marks)"

const PK_HITSCAN: int = 0
const PK_BEAM: int = 7
const PK_STRIKE: int = 5
const ARCH_RAIL: int = 14
const ARCH_EMP: int = 19
const ARCH_BOMB: int = 17
const DK_VEHICLE: int = 1
const DK_INFANTRY: int = 2
const DK_CRASH: int = 3
const DK_AIR_EXPLODE: int = 4
const DK_SINK: int = 5
const DK_STRUCTURE: int = 6
const DK_DRONE: int = 7
const DK_SILENT: int = 8
const M_PER_UNIT: float = 3.0 / 1024.0
const DEDUPE_RADIUS_U: int = 1536  ## 1.5 cells
const DEDUPE_MIN_SPLASH_U: int = 683  ## 2 m
const TICK_S: float = 0.05
const HITSCAN_SPEED: float = 150.0

## Public switches / hooks.
var warnings_enabled: bool = true  ## false when a ViewWarnings owner draws the warning markers itself
var enabled: bool = true
var catalog: FxCatalog = null
var fx: FxManager = null
var ambient: FxAmbient = null
var strategic: FxStrategic = null
var projectiles: ViewProjectiles = null
var port: ViewFxPort = null  ## optional: suppressed ids are registered here so state views do not double-spawn
var record: bool = false  ## tests: append every spawn to `spawn_log` as [id, a, b, scale, delay_s]
var spawn_log: Array = []

var v: ViewWorld = null
var sim: SimWorld = null
var _chain: Callable = Callable()
var _chain_entry: Callable = Callable()
var _table: Dictionary = {}  # code -> handler
var _ignored: Dictionary = {}  # code -> true
var _sock: PackedStringArray = PackedStringArray()
var _batch_impacts: PackedInt32Array = PackedInt32Array()  # x, y pairs of explosions >= 2 m in the current batch
var _hit_fire: Dictionary = {}  # hit-scan fire position (x << 16 ^ y) -> weapon arch of the batch
var _hits_seen: Dictionary = {}  # attacker << 20 ^ victim -> true (EV_HIT lookahead for fallback hit inference)
var _recent_impacts: PackedInt32Array = PackedInt32Array()  # x, y, tick triples of explosions already drawn
var _beams: Dictionary = {}  # shooter * 8 + mount -> tracker handle
var _emp: Dictionary = {}  # victim id -> tracker handle
var _wreck_loops: Dictionary = {}  # wreck id -> Array[int] emitter handles
var _dedupe_tick: Dictionary = {}  # (id << 4) ^ kind -> last tick (capture / repair flash throttles)
var stats: Dictionary = {"events": 0, "handled": 0, "ignored": 0, "unknown": 0, "gated": 0, "spawns": 0, "deduped": 0, "handle_us": 0}
var unknown_codes: Dictionary = {}
var const_maps: Dictionary = {}  ## test seam: class name -> constant map


func _init() -> void:
	for mount: int in 4:
		for barrel: int in 4:
			_sock.append("muzzle%d_%d" % [mount, barrel])


## Binds to a view world and its FX manager, builds the table and installs the router hook.
func setup(view: ViewWorld, manager: FxManager, proj: ViewProjectiles = null) -> void:
	v = view
	fx = manager
	sim = view.sim
	catalog = FxCatalog.new(manager.recipe_book())
	projectiles = proj
	ambient = FxAmbient.new()
	strategic = FxStrategic.new()
	strategic.setup(self)
	rebuild_table()
	var bad: PackedStringArray = validate_codes()
	for n: String in bad:
		Log.error("view.fx", "consumed event constant missing in the kernel: %s (handler ignored)" % n)


## Sets `view.router.extra_handler` so every record reaches `handle`. An extra_handler that is already installed keeps running first
## (chained), so other view modules can listen to the same records. One FX router per view.
func attach(view: ViewWorld) -> void:
	var prev: Callable = view.router.extra_handler
	_chain = Callable() if (not prev.is_valid() or prev == _chain_entry) else prev
	_chain_entry = _handle_chained
	view.router.extra_handler = _chain_entry


## Restores the handler that was installed before `attach`.
func detach(view: ViewWorld) -> void:
	if view.router.extra_handler == _chain_entry:
		view.router.extra_handler = _chain
	_chain = Callable()


## Drops every reference the router holds (router <-> strategic <-> projectile mirror form reference cycles that would otherwise keep
## the projectile models' meshes alive until the process exits). Call after `detach`; the router is unusable afterwards.
func teardown() -> void:
	_chain = Callable()
	_chain_entry = Callable()
	strategic = null
	ambient = null
	catalog = null
	projectiles = null
	port = null
	fx = null
	v = null
	sim = null
	spawn_log.clear()


func _handle_chained(events: PackedInt32Array, o: int) -> void:
	if _chain.is_valid():
		_chain.call(events, o)
	handle(events, o)


func rebuild_table() -> void:
	_table.clear()
	_ignored.clear()
	for row: Array in TABLE:
		var code: Variant = _constants_of(row[1] as String).get(row[2] as String)
		if code is int:
			_table[code as int] = row[0] as int
	for row2: Array in IGNORED:
		var code2: Variant = _constants_of(row2[0] as String).get(row2[1] as String)
		if code2 is int:
			_ignored[code2 as int] = true


## "Class.NAME" entries of TABLE / IGNORED that do not exist in the (possibly injected) constant maps.
func validate_codes() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row: Array in TABLE:
		if not _constants_of(row[1] as String).has(row[2] as String):
			out.append("%s.%s" % [row[1], row[2]])
	for row2: Array in IGNORED:
		if not _constants_of(row2[0] as String).has(row2[1] as String):
			out.append("%s.%s" % [row2[0], row2[1]])
	return out


func handler_of(code: int) -> int:
	return _table.get(code, H_NONE) as int


func is_ignored(code: int) -> bool:
	return _ignored.has(code)


static func class_names() -> PackedStringArray:
	return PackedStringArray(["SimEvent", "SimMoveConfig", "SimAirMove", "SimCombatConsts", "SimAbilityConsts", "SimZoneConsts", "SimEconConst"])


func _constants_of(cls: String) -> Dictionary:
	if const_maps.has(cls):
		return const_maps[cls] as Dictionary
	match cls:
		"SimEvent":
			return (SimEvent as GDScript).get_script_constant_map()
		"SimMoveConfig":
			return (SimMoveConfig as GDScript).get_script_constant_map()
		"SimAirMove":
			return (SimAirMove as GDScript).get_script_constant_map()
		"SimCombatConsts":
			return (SimCombatConsts as GDScript).get_script_constant_map()
		"SimAbilityConsts":
			return (SimAbilityConsts as GDScript).get_script_constant_map()
		"SimZoneConsts":
			return (SimZoneConsts as GDScript).get_script_constant_map()
		"SimEconConst":
			return (SimEconConst as GDScript).get_script_constant_map()
	return {}


# ---------------------------------------------------------------------------------------------- batch entry points
## Runs a whole batch (tests, tools). With the ViewEventRouter hook `handle` is called per record instead.
func process_batch(events: PackedInt32Array) -> void:
	var o: int = 0
	var n: int = events.size()
	while o + SimEvent.STRIDE <= n:
		handle(events, o)
		o += SimEvent.STRIDE


## The extra_handler of the entity mirror: `(events, o)` for record `o`.
func handle(events: PackedInt32Array, o: int) -> void:
	if not enabled:
		return
	if o == 0:
		_prescan(events)
	var code: int = events[o]
	stats["events"] = (stats["events"] as int) + 1
	var h: int = _table.get(code, H_NONE) as int
	if h == H_NONE:
		if _ignored.has(code):
			stats["ignored"] = (stats["ignored"] as int) + 1
		else:
			stats["unknown"] = (stats["unknown"] as int) + 1
			unknown_codes[code] = (unknown_codes.get(code, 0) as int) + 1
		return
	stats["handled"] = (stats["handled"] as int) + 1
	var t0: int = Time.get_ticks_usec()
	_dispatch(h, events, o)
	stats["handle_us"] = (stats["handle_us"] as int) + Time.get_ticks_usec() - t0


## Damage thresholds of `fx.json -> mappings.damage_emitters` (hp fraction below which smoke / fire start).
func fx_damage_threshold(key: String) -> float:
	var m: Variant = fx.recipe_book().mappings.get("damage_emitters", {})
	if m is Dictionary:
		return float((m as Dictionary).get(key, 0.66 if key == "smoke_below" else 0.33))
	return 0.66 if key == "smoke_below" else 0.33


## Per-frame upkeep: damage emitters, locomotion stamping, projectile mirror.
func frame(dt: float) -> void:
	if not enabled:
		return
	ambient.frame(self, dt)
	if projectiles != null:
		projectiles.frame(dt)


# ---------------------------------------------------------------------------------------------- lookahead
func _prescan(events: PackedInt32Array) -> void:
	_batch_impacts.resize(0)
	_hit_fire.clear()
	_hits_seen.clear()
	var o: int = 0
	var n: int = events.size()
	var t_impact: int = SimCombatConsts.EV_IMPACT
	var t_fire: int = SimCombatConsts.EV_FIRE
	var t_hit: int = SimCombatConsts.EV_HIT
	while o + SimEvent.STRIDE <= n:
		var code: int = events[o]
		if code == t_impact:
			if events[o + 7] >= DEDUPE_MIN_SPLASH_U:
				_batch_impacts.append(events[o + 2])
				_batch_impacts.append(events[o + 3])
		elif code == t_fire:
			if ((events[o + 6] >> 8) & 15) == PK_HITSCAN:
				_hit_fire[(events[o + 8] << 16) ^ events[o + 9]] = events[o + 5]
		elif code == t_hit:
			_hits_seen[(events[o + 6] << 20) ^ events[o + 4]] = true
		o += SimEvent.STRIDE


# ---------------------------------------------------------------------------------------------- gating and helpers
## true when an event at sim position (x, y) touching entities `ida` / `idb` may draw (no information leak through fog).
func allowed(x: int, y: int, ida: int = -1, idb: int = -1) -> bool:
	if v.observer or v.local_pid < 0:
		return true
	if ida > 0:
		var a: ViewEntity = v.entity_view(ida)
		if a != null and a.vs == ViewConsts.VS_VISIBLE:
			return true
	if idb > 0:
		var b: ViewEntity = v.entity_view(idb)
		if b != null and b.vs == ViewConsts.VS_VISIBLE:
			return true
	return sim.cell_visible(v.local_pid, x >> 10, y >> 10)


func gpos(x: int, y: int) -> Vector3:
	return v.sim_to_world(x, y)


## Effect spawn through the manager; counts and ignores empty ids.
func spawn(id: StringName, a: Vector3, b: Vector3 = Vector3.ZERO, s: float = 1.0) -> int:
	if id == &"" or fx == null:
		return -1
	stats["spawns"] = (stats["spawns"] as int) + 1
	if record:
		spawn_log.append([id, a, b, s, 0.0])
	return fx.spawn(id, a, b, s)


## Delayed spawn (re-culled when it fires).
func spawn_later(delay: float, id: StringName, a: Vector3, b: Vector3 = Vector3.ZERO, s: float = 1.0) -> void:
	if id == &"" or fx == null:
		return
	stats["spawns"] = (stats["spawns"] as int) + 1
	if record:
		spawn_log.append([id, a, b, s, delay])
	fx.schedule(delay, id, a, b, s)


func logged(id: StringName) -> int:
	var n: int = 0
	for rec: Variant in spawn_log:
		if (rec as Array)[0] == id:
			n += 1
	return n


## Muzzle world position: model socket "muzzle{mount}_{barrel}" (falls back to muzzle{mount}_0, muzzle, then the sim position).
func muzzle_pos(ve: ViewEntity, mount: int, barrel: int, x: int, y: int) -> Vector3:
	if ve != null and ve.model != null:
		var info: ViewModelInfo = ve.model.info
		var nm: StringName = StringName(_sock[(mount & 3) * 4 + (barrel & 3)])
		if info.has_socket(nm):
			return v.entity_socket(ve.id, nm)
		nm = StringName(_sock[(mount & 3) * 4])
		if info.has_socket(nm):
			return v.entity_socket(ve.id, nm)
		if info.has_socket(&"muzzle"):
			return v.entity_socket(ve.id, &"muzzle")
	var p: Vector3 = gpos(x, y)
	p.y += (ve.height_m * 0.7) if ve != null else 1.4
	return p


## Aim / impact point of an event: the aim height is the target's mid height when it is an entity, else 0.9 m above the ground.
func aim_pos(x: int, y: int, target_id: int) -> Vector3:
	var p: Vector3 = gpos(x, y)
	var t: ViewEntity = v.entity_view(target_id) if target_id > 0 else null
	if t != null:
		p.y = maxf(p.y, t.wy) + t.height_m * 0.5 if t.motion >= ViewConsts.MOTION_AIR_FIXED and t.motion <= ViewConsts.MOTION_AIR_HOVER else p.y + t.height_m * 0.5
	else:
		p.y += 0.9
	return p


## true when a detonation of radius >= 2 m already happened / happens in this batch within 1.5 cells of (x, y).
func explosion_near(x: int, y: int) -> bool:
	var i: int = 0
	while i + 1 < _batch_impacts.size():
		if absi(_batch_impacts[i] - x) <= DEDUPE_RADIUS_U and absi(_batch_impacts[i + 1] - y) <= DEDUPE_RADIUS_U:
			return true
		i += 2
	return false


func _throttled(id: int, kind: int, tick: int, gap: int) -> bool:
	var key: int = (id << 4) ^ kind
	if tick - (_dedupe_tick.get(key, -1000) as int) < gap:
		return true
	_dedupe_tick[key] = tick
	if _dedupe_tick.size() > 512:
		_dedupe_tick.clear()
	return false


# ---------------------------------------------------------------------------------------------- dispatch
func _dispatch(h: int, ev: PackedInt32Array, o: int) -> void:
	match h:
		H_FIRE:
			_on_fire(ev, o)
		H_PROJ_SPAWN:
			_on_proj_spawn(ev, o)
		H_PROJ_END:
			_on_proj_end(ev, o)
		H_IMPACT:
			_on_impact(ev, o)
		H_HIT:
			_on_hit(ev, o)
		H_BEAM_START:
			_on_beam_start(ev, o)
		H_BEAM_END:
			_on_beam_end(ev, o)
		H_SWEEP:
			strategic.on_sweep(self, ev, o)
		H_DEATH:
			_on_death(ev, o)
		H_WRECK_ADD:
			_on_wreck_add(ev, o)
		H_WRECK_REMOVE:
			_on_wreck_remove(ev, o)
		H_INTERCEPT:
			_on_intercept(ev, o)
		H_EMP:
			_on_emp(ev, o)
		H_REARM:
			_on_rearm(ev, o)
		H_DRONE:
			_on_drone(ev, o)
		H_EJECT:
			_on_eject(ev, o)
		H_CRASH:
			_on_crash(ev, o)
		H_SPAWNED:
			_on_spawned(ev, o)
		H_REMOVED:
			_on_removed(ev, o)
		H_OWNER:
			_on_owner(ev, o)
		H_TAKEOFF, H_LANDED:
			_on_air_move(ev, o, h == H_TAKEOFF)
		H_MEDIUM:
			_on_medium(ev, o)
		H_LAYER:
			_on_layer(ev, o)
		H_CLOAK:
			_on_cloak(ev, o)
		H_MODE_DONE:
			_on_mode_done(ev, o)
		H_FX_APPLIED:
			_on_fx_applied(ev, o)
		H_UNLOADED:
			_on_unloaded(ev, o)
		H_DROWNED:
			_on_drowned(ev, o)
		H_SUMMONED:
			strategic.on_summoned(self, ev, o)
		H_SUMMON_EXPIRED, H_SUMMON_EXPIRED_ECON:
			_on_summon_expired(ev, o, h == H_SUMMON_EXPIRED_ECON)
		H_SALVAGE_DONE:
			_on_spark_at(ev, o, &"salvage_sparkle", 1.0)
		H_CAPTURE_DONE:
			_on_captured(ev, o, ev[o + 5])
		H_STRUCT_CAPTURED:
			_on_captured(ev, o, ev[o + 5])
		H_REPAIR_PULSE:
			_on_repair_pulse(ev, o)
		H_DECOY_ID:
			_on_cloak_like(ev, o)
		H_MARKED:
			strategic.on_marked(self, ev, o)
		H_STRUCT_PLACED:
			_on_struct_placed(ev, o)
		H_STRUCT_ACTIVE:
			_on_struct_active(ev, o)
		H_UNIT_PRODUCED:
			_on_unit_produced(ev, o)
		H_CREDITS:
			_on_credits(ev, o)
		H_HQ_DEPLOYED:
			_on_hq_deployed(ev, o)
		H_SALVAGE_STARTED:
			_on_salvage_started(ev, o)
		H_ZONE_SPAWNED:
			strategic.on_zone_spawned(self, ev, o)
		H_ZONE_ENDED:
			strategic.on_zone_ended(self, ev, o)
		H_SWARM:
			strategic.on_swarm(self, ev, o)
		H_ENGINE:
			strategic.on_engine(self, ev, o)
		H_BUFF:
			strategic.on_buff(self, ev, o)
		H_POWER_USED:
			strategic.on_power_used(self, ev, o)
		H_WARNING:
			strategic.on_warning(self, ev, o)
		H_SW_CANCELLED:
			strategic.on_sw_cancelled(self, ev, o)
		H_SW_EXEC:
			strategic.on_sw_exec(self, ev, o)
		H_SW_IMPACT:
			strategic.on_sw_impact(self, ev, o)
		H_SW_DONE:
			strategic.on_sw_done(self, ev, o)


# ---------------------------------------------------------------------------------------------- combat
## EV_FIRE: x, y muzzle . a shooter . b weapon arch . c mount | barrel << 4 | kind << 8 | result << 12 | burst << 16 . d target . e, f aim / impact
func _on_fire(ev: PackedInt32Array, o: int) -> void:
	var c: int = ev[o + 6]
	var kind: int = (c >> 8) & 15
	if kind == PK_BEAM:
		return  # continuous beams are trackers (EV_BEAM_START)
	var shooter: int = ev[o + 4]
	var arch: int = ev[o + 5]
	var target: int = ev[o + 7]
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, shooter, target) and not allowed(ev[o + 8], ev[o + 9], -1, target):
		stats["gated"] = (stats["gated"] as int) + 1
		return
	var ve: ViewEntity = v.entity_view(shooter)
	var from: Vector3 = muzzle_pos(ve, c & 15, (c >> 4) & 15, x, y)
	var to: Vector3 = aim_pos(ev[o + 8], ev[o + 9], target)
	var mz: StringName = catalog.muzzle_id(arch)
	spawn(mz, from, to, 1.0)
	if kind != PK_HITSCAN:
		return  # projectile kinds: ViewProjectiles (EV_PROJ_SPAWN) draws the flight, EV_IMPACT the detonation
	var result: int = (c >> 12) & 15
	if result == 0:
		result = 1 if _hits_seen.has((shooter << 20) ^ target) else 2  # fallback inference: an EV_HIT of this attacker on the target
	_hitscan_visual(arch, result, from, to, target, ve)


func _hitscan_visual(arch: int, result: int, from: Vector3, to: Vector3, target: int, _shooter: ViewEntity) -> void:
	var row: Dictionary = _proj_row(arch)
	var look: String = str(row.get("look", "none"))
	if look == "none":
		return
	var trace: StringName = StringName(str(row.get("fx", "")))
	var dist: float = from.distance_to(to)
	if trace != &"":
		var pellets: int = int(row.get("pellets", 1))
		for k: int in pellets:
			var aim: Vector3 = to
			if pellets > 1:
				aim += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (0.5 + 0.2 * float(k))
			spawn(trace, from, aim, maxf(dist / HITSCAN_SPEED, 0.02))
	var hit_id: StringName = &"hit_ground_miss"
	if result == 1:
		hit_id = _hit_effect(arch, target)
	if hit_id != &"":
		var delay: float = dist / HITSCAN_SPEED
		var at: Vector3 = to
		if result == 2:
			at.y = v.ground_at(to.x, to.z) + 0.1
		if delay > 0.03:
			spawn_later(delay, hit_id, at, Vector3.ZERO, 1.25)
		else:
			spawn(hit_id, at, Vector3.ZERO, 1.25)


func _hit_effect(arch: int, target: int) -> StringName:
	if arch == ARCH_RAIL:
		return &"hit_rail"
	if arch == ARCH_EMP:
		return &""  # the field effect comes with EV_IMPACT / EV_EMP
	var t: ViewEntity = v.entity_view(target) if target > 0 else null
	if t == null:
		return &"hit_bullet_hv" if arch == 2 else &"hit_bullet"
	if t.kind == SimEntity.Kind.STRUCTURE or t.kind == SimEntity.Kind.NEUTRAL:
		return &"hit_bullet_structure"
	if t.motion >= ViewConsts.MOTION_AIR_FIXED and t.motion <= ViewConsts.MOTION_AIR_HOVER:
		return &"hit_flak_small"
	if t.motion == ViewConsts.MOTION_FOOT:
		return &"hit_infantry"
	return &"hit_bullet_hv" if arch == 2 else &"hit_armor"


func _proj_row(arch: int) -> Dictionary:
	if fx == null or arch < 0 or arch >= FxCatalog.FAMILIES.size():
		return {}
	var m: Variant = fx.recipe_book().mappings.get("projectiles", {})
	if m is Dictionary:
		return (m as Dictionary).get(FxCatalog.FAMILIES[arch], {}) as Dictionary
	return {}


## EV_PROJ_SPAWN -> ViewProjectiles (mirror + tracer / arc / mesh visuals).
func _on_proj_spawn(ev: PackedInt32Array, o: int) -> void:
	if projectiles == null:
		return
	var vis: bool = allowed(ev[o + 2], ev[o + 3], ev[o + 7]) or allowed(ev[o + 8], ev[o + 9])
	projectiles.on_launch(ev, o, vis)


func _on_proj_end(ev: PackedInt32Array, o: int) -> void:
	if projectiles != null:
		projectiles.on_end(ev[o + 4], ev[o + 1])


## EV_IMPACT: x, y centre . a warhead . b serial . c hit_kind | reduced << 4 | miss << 5 . d splash radius . e damage . f pid | victims << 4
func _on_impact(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var serial: int = ev[o + 5]
	var arch: int = -1
	var pkind: int = -1
	if projectiles != null:
		var rec: ViewProjectiles.Rec = projectiles.record_of(serial)
		if rec != null:
			arch = rec.arch
			pkind = rec.kind
		projectiles.on_impact(serial, ev[o + 1])
	if pkind == PK_STRIKE:
		return  # strategic strikes are drawn by EVT_SW_IMPACT (superweapon sequences)
	if arch < 0 and serial < 0:
		arch = _hit_fire.get((x << 16) ^ y, -1) as int
	if not allowed(x, y):
		stats["gated"] = (stats["gated"] as int) + 1
		return
	var splash: int = ev[o + 7]
	var hk: int = ev[o + 6] & 15
	var res: int = 2
	var target_air: bool = hk == 3
	if hk != 0 and hk != 5:
		res = FxCatalog.RESULT_ENTITY
	var p: Vector3 = gpos(x, y)
	if hk == 0 or hk == 5 or hk == 4:
		if v.terrain != null and v.terrain.is_water_at(p.x, p.z):
			res = FxCatalog.RESULT_WATER
		elif hk == 5:
			res = FxCatalog.RESULT_WATER
	var id: StringName
	var s: float = 1.0
	if arch >= 0:
		id = catalog.impact_id(arch, res, splash, target_air)
		if splash <= 8 and id == &"hit_bullet" and FxCatalog.DEFAULT_IMPACTS[arch].begins_with("expl_"):
			id = StringName(FxCatalog.DEFAULT_IMPACTS[arch])
		if arch == ARCH_EMP:
			s = clampf(float(splash) * M_PER_UNIT, 3.0, 40.0)
	else:
		id = catalog.explosion_id(0, splash, 2)
	if id == &"expl_kinetic" or id == &"expl_strategic_large":
		s = clampf(0.55 * float(splash) * M_PER_UNIT + 0.5, 1.0, 12.0)
	elif s == 1.0:
		s = catalog.explosion_scale(id, splash)
	if id == &"expl_air_burst":
		p.y += 8.0
	if id == &"impact_water" or id == &"expl_underwater" or id == &"expl_underwater_big":
		p.y = v.sea_level() if v.sea_level() > -900.0 else p.y
	if (ev[o + 6] & 16) != 0:
		return  # packet reduced by an interception zone (EV_INTERCEPT draws the flash)
	spawn(id, p, Vector3.ZERO, s)
	_remember_impact(x, y, ev[o + 1])


func _remember_impact(x: int, y: int, tick: int) -> void:
	if _recent_impacts.size() >= 48:
		_recent_impacts = _recent_impacts.slice(24)
	_recent_impacts.append(x)
	_recent_impacts.append(y)
	_recent_impacts.append(tick)


## EV_HIT: a victim . b damage . c attacker . d dtype | dc << 8 | flags << 16 . e hp . f hp max. The entity mirror flashes and sets hp;
## the FX side feeds the damage emitters.
func _on_hit(ev: PackedInt32Array, o: int) -> void:
	ambient.note_damaged(ev[o + 4])


## EV_BEAM_START: x, y muzzle . a shooter . b arch . c mount . d target . e beam max ticks
func _on_beam_start(ev: PackedInt32Array, o: int) -> void:
	var shooter: int = ev[o + 4]
	var target: int = ev[o + 7]
	if not allowed(ev[o + 2], ev[o + 3], shooter, target):
		stats["gated"] = (stats["gated"] as int) + 1
		return
	var mount: int = ev[o + 6]
	var arch: int = ev[o + 5]
	var ve: ViewEntity = v.entity_view(shooter)
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var seg: StringName = StringName(str(_proj_row(arch).get("fx", "beam_thermal_seg")))
	spawn(catalog.muzzle_id(arch), muzzle_pos(ve, mount, 0, x, y), aim_pos(x, y, target), 1.0)
	var life_s: float = 20.0 if ev[o + 8] <= 0 else clampf(float(ev[o + 8]) * TICK_S, 1.0, 30.0)
	var vw: ViewWorld = v
	var me: FxEventRouter = self
	var last_to: Array = [aim_pos(x, y, target)]
	var from_cb: Callable = func() -> Vector3:
		return me.muzzle_pos(vw.entity_view(shooter), mount, 0, x, y)
	var to_cb: Callable = func() -> Vector3:
		var t: ViewEntity = vw.entity_view(target)
		if t != null and not t.sim_gone:
			last_to[0] = Vector3(t.wx, t.wy + t.height_m * 0.5, t.wz)
		return last_to[0] as Vector3
	var key: int = shooter * 8 + (mount & 7)
	var old: int = _beams.get(key, -1) as int
	if old > 0:
		fx.stop_emitter(old)
	var h: int = fx.start_tracker(seg, from_cb, to_cb, 0.07, life_s, 1.0)
	if h > 0:
		_beams[key] = h


## EV_BEAM_END: a shooter . b reason . c mount
func _on_beam_end(ev: PackedInt32Array, o: int) -> void:
	var key: int = ev[o + 4] * 8 + (ev[o + 6] & 7)
	var h: int = _beams.get(key, -1) as int
	if h > 0:
		fx.stop_emitter(h)
	_beams.erase(key)


## EV_DEATH: x, y . a id . b def . c death_kind | cause << 4 | flags << 8 . d killer . e pids . f facing | layer << 12 | dying << 16
func _on_death(ev: PackedInt32Array, o: int) -> void:
	var id: int = ev[o + 4]
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var c: int = ev[o + 6]
	var dk: int = c & 15
	ambient.forget(id)
	if not allowed(x, y, id, ev[o + 7]):
		stats["gated"] = (stats["gated"] as int) + 1
		return
	var ve: ViewEntity = v.entity_view(id)
	var p: Vector3 = gpos(x, y)
	if ve != null and (ve.motion >= ViewConsts.MOTION_AIR_FIXED and ve.motion <= ViewConsts.MOTION_AIR_HOVER):
		p = Vector3(ve.wx, maxf(ve.wy, p.y), ve.wz)
	var size_class: int = ve.vdef.size_class if (ve != null and ve.vdef != null) else FxCatalog.SC_MEDIUM
	var deduped: bool = explosion_near(x, y)
	var fid: StringName
	var s: float = 1.0
	if deduped:
		stats["deduped"] = (stats["deduped"] as int) + 1
	match dk:
		DK_VEHICLE:
			if deduped:
				fid = &"death_secondary"
				s = 2.6 if size_class <= FxCatalog.SC_LIGHT else (3.6 if size_class == FxCatalog.SC_MEDIUM else 5.0)
			else:
				fid = catalog.death_id(dk, size_class)
		DK_INFANTRY:
			fid = catalog.death_id(dk, size_class)
			s = clampf(0.8 + 0.25 * float(ve.members - 1), 0.8, 2.2) if ve != null else 1.0
		DK_CRASH:
			ambient.start_crash_trail(self, ve)
			return  # the ground impact comes with EV_CRASH
		DK_AIR_EXPLODE:
			fid = catalog.death_id(dk, size_class)
			s = clampf(float(size_class - 4) * 0.5 + 1.0, 0.8, 2.0)
		DK_SINK:
			fid = catalog.death_id(dk, size_class)
			p.y = v.sea_level() if v.sea_level() > -900.0 else p.y
			s = 1.0 if size_class < FxCatalog.SC_SHIP_MEDIUM else 1.15
		DK_STRUCTURE:
			var fw: int = ve.vdef.fp_w if (ve != null and ve.vdef != null) else 3
			var fh: int = ve.vdef.fp_h if (ve != null and ve.vdef != null) else 3
			s = clampf(float(maxi(fw, fh)) * 1.5 / 7.0, 0.5, 2.6)
			fid = &"collapse_secondary" if deduped else catalog.death_id(dk, size_class)
		DK_DRONE:
			fid = catalog.death_id(dk, size_class)
		DK_SILENT:
			fid = catalog.death_id(dk, size_class)
		_:
			return
	spawn(fid, p, Vector3.ZERO, s)
	if not deduped and dk != DK_INFANTRY and dk != DK_SILENT and dk != DK_DRONE:
		_remember_impact(x, y, ev[o + 1])


func _on_wreck_add(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var wid: int = ev[o + 4]
	if not allowed(x, y, wid):
		return
	var p: Vector3 = gpos(x, y)
	var life_s: float = maxf(float(ev[o + 6] - ev[o + 1]) * TICK_S, 8.0)
	var handles: Array = []
	handles.append(fx.start_loop(&"wreck_tick", p, Vector3.ZERO, 1.0, 0.22, minf(14.0, life_s), 0.05))
	if life_s > 24.0:
		handles.append(fx.start_loop(&"wreck_smoke", p, Vector3.ZERO, 1.0, 1.5, life_s - 22.0, 14.0))
	_wreck_loops[wid] = handles


func _on_wreck_remove(ev: PackedInt32Array, o: int) -> void:
	var handles: Array = _wreck_loops.get(ev[o + 4], []) as Array
	for h: Variant in handles:
		fx.stop_emitter(h as int)
	_wreck_loops.erase(ev[o + 4])


## EV_INTERCEPT: x, y . a serial . b interceptor . c kind (0 APS, 1 zone, 2 packet) . d charges / ready . e proj owner . f interceptor owner
func _on_intercept(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y):
		return
	var p: Vector3 = gpos(x, y)
	var kind: int = ev[o + 6]
	if kind == 0:
		var t: ViewEntity = v.entity_view(ev[o + 5])
		p.y += (t.height_m * 0.7) if t != null else 3.0
		spawn(&"aps_flash", p, Vector3.ZERO, 1.0)
	else:
		p.y += 6.0
		spawn(&"sw_intercept_flash", p, Vector3.ZERO, 1.6 if kind == 1 else 2.4)
	if projectiles != null:
		projectiles.on_end(ev[o + 4], ev[o + 1])


## EV_EMP: x, y . a victim . b duration ticks . c 0 weapons off / 1 shutdown . d attacker pid . e 1 = blocked
func _on_emp(ev: PackedInt32Array, o: int) -> void:
	if ev[o + 8] != 0 or ev[o + 5] <= 0:
		return
	var id: int = ev[o + 4]
	if not allowed(ev[o + 2], ev[o + 3], id):
		return
	var ve: ViewEntity = v.entity_view(id)
	if ve == null:
		return
	var old: int = _emp.get(id, -1) as int
	if old > 0:
		fx.stop_emitter(old)
	var vw: ViewWorld = v
	var pos_cb: Callable = func() -> Vector3:
		var t: ViewEntity = vw.entity_view(id)
		return Vector3(t.wx, t.wy, t.wz) if t != null else Vector3.ZERO
	var s: float = clampf(ve.radius_m * 0.8, 1.0, 5.0)
	var h: int = fx.start_tracker(&"status_emp_tick", pos_cb, pos_cb, 0.14, clampf(float(ev[o + 5]) * TICK_S, 0.5, 12.0), s)
	if h > 0:
		_emp[id] = h


func _on_rearm(ev: PackedInt32Array, o: int) -> void:
	if ev[o + 5] != 1 or not allowed(ev[o + 2], ev[o + 3], ev[o + 4]):
		return
	var ve: ViewEntity = v.entity_view(ev[o + 4])
	var p: Vector3 = Vector3(ve.wx, ve.wy + 0.5, ve.wz) if ve != null else gpos(ev[o + 2], ev[o + 3])
	spawn(&"rearm_sparks", p, Vector3.ZERO, 1.2)


## EV_DRONE: a carrier . b drone . c 0 launch, 1 dock, 2 lost, 3 replace start, 4 replace done, 5 wing switched
func _on_drone(ev: PackedInt32Array, o: int) -> void:
	var kind: int = ev[o + 6]
	if kind != 0 and kind != 1 and kind != 4:
		return
	var ve: ViewEntity = v.entity_view(ev[o + 5])
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE:
		return
	spawn(&"spawn_shimmer", Vector3(ve.wx, ve.wy + 0.5, ve.wz), Vector3.ZERO, 0.8)


func _on_eject(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if allowed(x, y, ev[o + 4]):
		spawn(&"unload_puff", gpos(x, y), Vector3.ZERO, 1.4)


## EV_CRASH: x, y . a aircraft . b 0 start / 1 ground impact
func _on_crash(ev: PackedInt32Array, o: int) -> void:
	if ev[o + 5] != 1:
		return
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, ev[o + 4]):
		return
	var ve: ViewEntity = v.entity_view(ev[o + 4])
	ambient.stop_crash_trail(self, ve)
	var size_class: int = ve.vdef.size_class if (ve != null and ve.vdef != null) else 5
	spawn(&"aircraft_impact", gpos(x, y), Vector3.ZERO, 0.8 if size_class <= 5 else 1.1)


# ---------------------------------------------------------------------------------------------- lifecycle
## SPAWNED: x, y . a id . b kind . c def . d owner . e facing . f reason
func _on_spawned(ev: PackedInt32Array, o: int) -> void:
	var reason: int = ev[o + 9]
	var kind: int = ev[o + 5]
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	match reason:
		SimEvent.SPAWN_DEPLOYED:
			if kind == SimEntity.Kind.STRUCTURE and allowed(x, y, ev[o + 4]):
				var ve: ViewEntity = v.entity_view(ev[o + 4])
				spawn(&"build_dust", gpos(x, y), Vector3.ZERO, _struct_radius(ve))
		SimEvent.SPAWN_SUMMONED:
			pass  # EV_SUMMONED draws the arrival
		_:
			pass


func _struct_radius(ve: ViewEntity) -> float:
	if ve == null or ve.vdef == null:
		return 4.0
	return clampf(float(maxi(ve.vdef.fp_w, ve.vdef.fp_h)) * 1.5, 2.5, 14.0)


## REMOVED: x, y . a id . b kind . c def . d owner . e reason
func _on_removed(ev: PackedInt32Array, o: int) -> void:
	var reason: int = ev[o + 8]
	var kind: int = ev[o + 5]
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var id: int = ev[o + 4]
	ambient.forget(id)
	if reason == SimEvent.REM_SOLD:
		if allowed(x, y, id):
			var ve: ViewEntity = v.entity_view(id)
			spawn(&"sell_dust", gpos(x, y), Vector3.ZERO, _struct_radius(ve))
		return
	if reason == SimEvent.REM_EXPIRED or reason == SimEvent.REM_CONSUMED or reason == SimEvent.REM_SCRIPT:
		if kind != SimEntity.Kind.UNIT or not allowed(x, y, id):
			return
		var ve2: ViewEntity = v.entity_view(id)
		if ve2 != null and ve2.dying_kind == ViewConsts.DK_SILENT:
			var p: Vector3 = Vector3(ve2.wx, ve2.wy, ve2.wz)
			spawn(&"death_silent", p, Vector3.ZERO, clampf(ve2.radius_m * 0.8, 0.6, 2.5))


func _on_owner(ev: PackedInt32Array, o: int) -> void:
	if _throttled(ev[o + 4], 1, ev[o + 1], 20):
		return
	var ve: ViewEntity = v.entity_view(ev[o + 4])
	if ve == null or ve.kind == SimEntity.Kind.UNIT or not allowed(ev[o + 2], ev[o + 3], ev[o + 4]):
		return
	spawn(&"capture_flash", gpos(ev[o + 2], ev[o + 3]), Vector3.ZERO, _struct_radius(ve))


func _on_captured(ev: PackedInt32Array, o: int, sid: int) -> void:
	if _throttled(sid, 1, ev[o + 1], 20):
		return
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, sid):
		return
	var ve: ViewEntity = v.entity_view(sid)
	spawn(&"capture_flash", gpos(x, y), Vector3.ZERO, _struct_radius(ve))


func _on_spark_at(ev: PackedInt32Array, o: int, id: StringName, s: float) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if allowed(x, y):
		spawn(id, gpos(x, y), Vector3.ZERO, s)


func _on_struct_placed(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, ev[o + 5]):
		return
	spawn(&"build_dust", gpos(x, y), Vector3.ZERO, _struct_radius(v.entity_view(ev[o + 5])))


func _on_struct_active(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, ev[o + 5]):
		return
	var ve: ViewEntity = v.entity_view(ev[o + 5])
	var p: Vector3 = gpos(x, y)
	spawn(&"build_complete", p, Vector3.ZERO, _struct_radius(ve) * 0.7)


func _on_unit_produced(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, ev[o + 5], ev[o + 7]):
		return
	var ve: ViewEntity = v.entity_view(ev[o + 5])
	spawn(&"exit_dust", gpos(x, y), Vector3.ZERO, clampf((ve.radius_m if ve != null else 1.5) / 1.5, 0.7, 2.2))


## EVT_CREDITS_GAINED / EVT_SALVAGE_PAID: a pid . b amount . c, d position (also the header)
func _on_credits(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if ev[o + 5] <= 0 or not allowed(x, y):
		return
	if _throttled((x >> 9) * 4096 + (y >> 9), 2, ev[o + 1], 12):
		return
	var p: Vector3 = gpos(x, y)
	p.y += 3.0
	spawn(&"credit_sparkle", p, Vector3.ZERO, 1.0)


func _on_hq_deployed(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if allowed(x, y, ev[o + 5]):
		spawn(&"build_dust", gpos(x, y), Vector3.ZERO, 7.0)


## EVT_SALVAGE_STARTED: a pid . b salvager . c wreck . d end tick
func _on_salvage_started(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, ev[o + 5]):
		return
	var dur: float = clampf(float(ev[o + 7] - ev[o + 1]) * TICK_S, 0.5, 30.0)
	fx.start_loop(&"salvage_sparkle", gpos(x, y), Vector3.ZERO, 0.6, 0.45, dur, 0.0)


# ---------------------------------------------------------------------------------------------- movement and abilities
func _on_air_move(ev: PackedInt32Array, o: int, takeoff: bool) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if not allowed(x, y, ev[o + 4]):
		return
	var ve: ViewEntity = v.entity_view(ev[o + 4])
	if ve == null or ve.motion != ViewConsts.MOTION_AIR_HOVER:
		if not takeoff:
			return  # fixed wings land on runways: dust only for rotor craft and VTOL
	spawn(&"landing_dust", gpos(x, y), Vector3.ZERO, 1.0)


func _on_medium(ev: PackedInt32Array, o: int) -> void:
	if not allowed(ev[o + 2], ev[o + 3], ev[o + 4]):
		return
	var p: Vector3 = gpos(ev[o + 2], ev[o + 3])
	if v.sea_level() > -900.0:
		p.y = maxf(p.y, v.sea_level())
	spawn(&"water_spray", p, Vector3.ZERO, 1.4)


func _on_layer(ev: PackedInt32Array, o: int) -> void:
	if not allowed(ev[o + 2], ev[o + 3], ev[o + 4]):
		return
	var p: Vector3 = gpos(ev[o + 2], ev[o + 3])
	if v.sea_level() > -900.0:
		p.y = v.sea_level()
	spawn(&"water_spray", p, Vector3.ZERO, 2.4)
	spawn(&"impact_water", p, Vector3.ZERO, 1.2)


## EV_CLOAK_CHANGED: a id . b 1 concealed / 0 revealed . c reason
func _on_cloak(ev: PackedInt32Array, o: int) -> void:
	var id: int = ev[o + 4]
	if _throttled(id, 3, ev[o + 1], 10):
		return
	var ve: ViewEntity = v.entity_view(id)
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE:
		return
	spawn(&"cloak_flash", Vector3(ve.wx, ve.wy + 0.3, ve.wz), Vector3.ZERO, clampf(ve.radius_m / 1.5, 0.7, 2.0))


func _on_cloak_like(ev: PackedInt32Array, o: int) -> void:
	var ve: ViewEntity = v.entity_view(ev[o + 4])
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE or _throttled(ev[o + 4], 4, ev[o + 1], 20):
		return
	spawn(&"decoy_spawn", Vector3(ve.wx, ve.wy + 0.5, ve.wz), Vector3.ZERO, 0.8)


## EV_MODE_CHANGED: a id . b slot . c new mode (deploy / pack complete, submarine surfaced)
func _on_mode_done(ev: PackedInt32Array, o: int) -> void:
	var id: int = ev[o + 4]
	var ve: ViewEntity = v.entity_view(id)
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE or _throttled(id, 5, ev[o + 1], 20):
		return
	if ve.motion == ViewConsts.MOTION_SUB or ve.motion == ViewConsts.MOTION_NAVAL:
		return  # EV_LAYER_CHANGED draws surfacing
	spawn(&"unload_puff", Vector3(ve.wx, ve.wy + 0.2, ve.wz), Vector3.ZERO, clampf(ve.radius_m / 1.2, 0.8, 2.6))


## EV_FX_APPLIED: a id . b fx idx . c expire tick (a timed effect landed on the entity): a throttled aura ring
func _on_fx_applied(ev: PackedInt32Array, o: int) -> void:
	var id: int = ev[o + 4]
	var ve: ViewEntity = v.entity_view(id)
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE or _throttled(id, 6, ev[o + 1], 40):
		return
	spawn(&"power_aura_defense", Vector3(ve.wx, ve.wy, ve.wz), Vector3.ZERO, clampf(ve.radius_m * 1.1, 1.2, 4.0))


func _on_unloaded(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if x == 0 and y == 0:
		return
	if allowed(x, y, ev[o + 4]):
		spawn(&"unload_puff", gpos(x, y), Vector3.ZERO, 1.0)


func _on_drowned(ev: PackedInt32Array, o: int) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	if allowed(x, y, ev[o + 4]):
		spawn(&"water_spray", gpos(x, y), Vector3.ZERO, 1.0)


func _on_summon_expired(ev: PackedInt32Array, o: int, econ: bool) -> void:
	var x: int = ev[o + 2]
	var y: int = ev[o + 3]
	var id: int = ev[o + 4]
	if _throttled(id, 7, ev[o + 1], 20):
		return
	if not allowed(x, y, id):
		return
	var ve: ViewEntity = v.entity_view(id)
	var p: Vector3 = Vector3(ve.wx, ve.wy, ve.wz) if ve != null else gpos(x, y)
	if econ and ve == null:
		p = gpos(x, y)
	spawn(&"death_silent", p, Vector3.ZERO, 1.2)


## EV_REPAIR_PULSE: a target . b healer or -1 . c hp gained
func _on_repair_pulse(ev: PackedInt32Array, o: int) -> void:
	var id: int = ev[o + 4]
	if _throttled(id, 8, ev[o + 1], 30):
		return
	var ve: ViewEntity = v.entity_view(id)
	if ve == null or ve.vs != ViewConsts.VS_VISIBLE:
		return
	spawn(&"repair_pulse", Vector3(ve.wx, ve.wy, ve.wz), Vector3.ZERO, clampf(ve.radius_m * 1.3, 1.6, 6.0))
