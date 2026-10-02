class_name AiCommandBuilder
extends RefCounted
## THE only encoder of commands in the AI (ai.md 3.4): modules call the intent API, `flush(out)` appends the raw
## `PackedInt32Array [type, args...]` commands net injects. Layouts come exclusively from the sim's SimCmd builders (no
## numeric command types anywhere else in src/ai: lint). Features: APM token bucket in Q8 with a 30 % reserve for the
## emergency and economy classes, priority classes (0 emergency, 1 economy/production, 2 operations, 3 micro), one order
## per unit per think (last intent wins), unit lists chunked to <= 48 ids, duplicate suppression, no-effect back-off and
## blacklist, per-intent statistics.
##
## Every intent method returns true when the intent was QUEUED for emission this think (false: throttled by APM, back-off,
## blacklist or duplicate). The blacklist KEY of an intent (used by note_no_effect / is_blocked): BUILD_START struct_def;
## BUILD_PLACE key2(struct_def, cell(cx, cy)); TRAIN key2(producer_eid, unit_def); RESEARCH res_def; SET_RALLY producer_eid;
## unit orders: the target entity id, or the target cell for point orders.

const RESERVE_PCT: int = 30
const TOKEN: int = 256  ## one command costs 256 Q8 tokens
const BLACKLIST_TICKS: int = 1200
const BACKOFF_TICKS: int = 60
const RECENT_MAX: int = 64

## Intents that address units (ids list, chunked, deduplicated per unit).
const UNIT_INTENTS: PackedInt32Array = [
	AiTypes.Intent.MOVE, AiTypes.Intent.ATTACK_MOVE, AiTypes.Intent.ATTACK, AiTypes.Intent.FORCE_FIRE, AiTypes.Intent.GUARD,
	AiTypes.Intent.STOP, AiTypes.Intent.SCATTER, AiTypes.Intent.DEPLOY, AiTypes.Intent.PACK, AiTypes.Intent.SET_MODE,
	AiTypes.Intent.USE_ABILITY, AiTypes.Intent.LOAD, AiTypes.Intent.GARRISON, AiTypes.Intent.CAPTURE, AiTypes.Intent.REPAIR,
	AiTypes.Intent.SALVAGE, AiTypes.Intent.HARVEST, AiTypes.Intent.RETURN_TO_BASE, AiTypes.Intent.HOLD, AiTypes.Intent.UNLOAD,
	AiTypes.Intent.SET_STANCE,
]

var exec_lag_est: int = AiTypes.AI_EXEC_LAG

var _pid: int = 0
var _diff: AiDifficultyProfile = null
var _telemetry: Callable = Callable()
var _tokens: int = 0
var _cap: int = 0
var _tick: int = 0
var _classes: Array = [[], [], [], []]  ## per priority class: Array[_Pending]
var _unit_entry: Dictionary = {}  ## unit id -> _Pending holding it this think
var _seen: Dictionary = {}  ## dedup key of non-unit intents this think
var _black: Dictionary = {}  ## (intent, key) -> tick until which it is blocked
var _strikes: Dictionary = {}  ## (intent, key) -> consecutive no-effect count
var _stats: Dictionary = {"throttled": 0, "no_effect": 0, "emitted": 0}
var _recent: PackedInt32Array = PackedInt32Array()  ## last RECENT_MAX (intent, key) pairs emitted


class _Pending extends RefCounted:
	var intent: int = 0
	var key: int = 0
	var cls: int = 2
	var args: PackedInt32Array = PackedInt32Array()
	var ids: PackedInt32Array = PackedInt32Array()
	var dead: Dictionary = {}  ## unit ids taken over by a later intent this think

	func live_ids() -> PackedInt32Array:
		if dead.is_empty():
			return ids
		var out: PackedInt32Array = PackedInt32Array()
		for id: int in ids:
			if not dead.has(id):
				out.append(id)
		return out


func _init(p_pid: int, p_diff: AiDifficultyProfile, p_telemetry: Callable = Callable()) -> void:
	_pid = p_pid
	_diff = p_diff
	_telemetry = p_telemetry
	_cap = _diff.cmd_burst * TOKEN
	_tokens = _cap


## Combines two ints into one blacklist key.
static func key2(a: int, b: int) -> int:
	return a * 1000003 + b


static func cell_key(x: int, y: int) -> int:
	return key2(x >> SimConfig.CELL_SHIFT, y >> SimConfig.CELL_SHIFT)


## Starts a think: refills the APM bucket (apm_cap x 256 x dt / 1200, capacity cmd_burst x 256) and drops anything not flushed.
## `tick` (optional) is the world tick; without it the builder's clock advances by dt.
func begin_think(dt: int, tick: int = -1) -> void:
	_tokens = mini(_cap, _tokens + _diff.apm_cap * TOKEN * dt / 1200)
	_tick = tick if tick >= 0 else _tick + dt
	for c: Array in _classes:
		c.clear()
	_unit_entry.clear()
	_seen.clear()


func tokens() -> int:
	return _tokens


func now() -> int:
	return _tick


## Appends the queued commands (class order, then insertion order), at most AI_MAX_CMDS_PER_THINK; returns the count.
func flush(out: Array) -> int:
	var n: int = 0
	for cls: int in 4:
		for p: _Pending in _classes[cls]:
			if p.intent in UNIT_INTENTS:
				var ids: PackedInt32Array = p.live_ids()
				var i: int = 0
				while i < ids.size():
					if n >= AiTypes.AI_MAX_CMDS_PER_THINK:
						_stats["throttled"] = int(_stats["throttled"]) + 1
						return n
					var chunk: PackedInt32Array = ids.slice(i, i + AiTypes.AI_MAX_IDS_PER_CMD)
					out.append(_encode(p, chunk))
					n += 1
					i += AiTypes.AI_MAX_IDS_PER_CMD
					_count(p)
			else:
				if n >= AiTypes.AI_MAX_CMDS_PER_THINK:
					_stats["throttled"] = int(_stats["throttled"]) + 1
					return n
				out.append(_encode(p, PackedInt32Array()))
				n += 1
				_count(p)
	for c: Array in _classes:
		c.clear()
	_unit_entry.clear()
	return n


func _count(p: _Pending) -> void:
	_stats[p.intent] = int(_stats.get(p.intent, 0)) + 1
	_stats["emitted"] = int(_stats["emitted"]) + 1
	_recent.append(p.intent)
	_recent.append(p.key)
	if _recent.size() > RECENT_MAX * 2:
		_recent = _recent.slice(_recent.size() - RECENT_MAX * 2)


## {intent code: emitted commands, "throttled": n, "no_effect": n, "emitted": n}.
func stats() -> Dictionary:
	return _stats


## The last <= 64 emitted (intent, key) pairs flattened (state-hash input).
func recent() -> PackedInt32Array:
	return _recent


func state_hash() -> int:
	return AiRng.hash_ints(_recent, AiRng.mix32(_tokens))


# ------------------------------------------------------------------------------------- effect verification
func _bk(intent: int, key: int) -> int:
	return key2(intent, key)


## True while (intent, key) is in back-off or blacklisted.
func is_blocked(intent: int, key: int, tick: int = -1) -> bool:
	var t: int = tick if tick >= 0 else _tick
	return int(_black.get(_bk(intent, key), -1)) > t


## An issued intent showed no observable effect (ai.md 5.15): the first strike backs off for BACKOFF_TICKS, further strikes
## blacklist the key for BLACKLIST_TICKS.
func note_no_effect(intent: int, key: int, tick: int) -> void:
	var k: int = _bk(intent, key)
	var n: int = int(_strikes.get(k, 0)) + 1
	_strikes[k] = n
	_black[k] = tick + (BACKOFF_TICKS if n < 2 else BLACKLIST_TICKS)
	_stats["no_effect"] = int(_stats["no_effect"]) + 1
	if n >= 2 and _telemetry.is_valid():
		_telemetry.call(_pid, AiTypes.Tele.CMD_REJECTED, intent, key, tick)


## An intent showed its effect: clears the strikes of (intent, key).
func note_effect(intent: int, key: int) -> void:
	_strikes.erase(_bk(intent, key))


## Adapts the emit-to-effect delay estimate (EMA, clamped 4..20 ticks).
func observe_lag(ticks: int) -> void:
	exec_lag_est = clampi((exec_lag_est * 3 + ticks) / 4, 4, 20)


# ---------------------------------------------------------------------------------------------- queueing
func _afford(cost_cmds: int, cls: int) -> bool:
	var need: int = cost_cmds * TOKEN
	var floor_tokens: int = 0 if cls <= 1 else _cap * RESERVE_PCT / 100
	if _tokens - need < floor_tokens:
		_stats["throttled"] = int(_stats["throttled"]) + 1
		return false
	_tokens -= need
	return true


func _queue_plain(intent: int, key: int, cls: int, args: PackedInt32Array) -> bool:
	var dk: int = _bk(intent, key) * 31 + args.size() * 7 + (args[0] if not args.is_empty() else 0)
	if is_blocked(intent, key) or _seen.has(dk):
		if not _seen.has(dk):
			_stats["throttled"] = int(_stats["throttled"]) + 1
		return false
	if not _afford(1, cls):
		return false
	_seen[dk] = true
	var p: _Pending = _Pending.new()
	p.intent = intent
	p.key = key
	p.cls = cls
	p.args = args
	_classes[cls].append(p)
	return true


func _queue_units(intent: int, key: int, cls: int, units: PackedInt32Array, args: PackedInt32Array) -> bool:
	if units.is_empty() or is_blocked(intent, key):
		return false
	var chunks: int = (units.size() + AiTypes.AI_MAX_IDS_PER_CMD - 1) / AiTypes.AI_MAX_IDS_PER_CMD
	if not _afford(chunks, cls):
		return false
	var p: _Pending = _Pending.new()
	p.intent = intent
	p.key = key
	p.cls = cls
	p.args = args
	p.ids = units.duplicate()
	if intent != AiTypes.Intent.SET_STANCE:
		for id: int in units:
			if _unit_entry.has(id):
				var old: _Pending = _unit_entry[id]
				old.dead[id] = true  # last intent wins
			_unit_entry[id] = p
	_classes[cls].append(p)
	return true


# -------------------------------------------------------------------------------------- economy (class 1)
func build_start(struct_def: int, prio_class: int = 1) -> bool:
	return _queue_plain(AiTypes.Intent.BUILD_START, struct_def, prio_class, PackedInt32Array([struct_def]))


func build_place(struct_def: int, cx: int, cy: int, rot: int = 0) -> bool:
	return _queue_plain(AiTypes.Intent.BUILD_PLACE, key2(struct_def, key2(cx, cy)), 1, PackedInt32Array([struct_def, cx, cy, rot]))


func build_cancel() -> bool:
	return _queue_plain(AiTypes.Intent.BUILD_CANCEL, 0, 1, PackedInt32Array([0]))


func train(producer_eid: int, unit_def: int, count: int = 1, prio_class: int = 1) -> bool:
	return _queue_plain(AiTypes.Intent.TRAIN, key2(producer_eid, unit_def), prio_class, PackedInt32Array([producer_eid, unit_def, count]))


func train_cancel(producer_eid: int, slot: int) -> bool:
	return _queue_plain(AiTypes.Intent.TRAIN_CANCEL, key2(producer_eid, slot), 1, PackedInt32Array([producer_eid, slot]))


func queue_hold(producer_eid: int, on_hold: bool) -> bool:
	return _queue_plain(AiTypes.Intent.QUEUE_HOLD, producer_eid, 1, PackedInt32Array([producer_eid, 1 if on_hold else 0]))


func research(res_def: int) -> bool:
	return _queue_plain(AiTypes.Intent.RESEARCH, res_def, 1, PackedInt32Array([res_def]))


func set_rally(producer_eid: int, x: int, y: int) -> bool:
	return _queue_plain(AiTypes.Intent.SET_RALLY, producer_eid, 1, PackedInt32Array([producer_eid, x, y]))


func set_structure_repair(struct_eid: int, on: bool) -> bool:
	return _queue_plain(AiTypes.Intent.STRUCT_REPAIR, struct_eid, 1, PackedInt32Array([struct_eid, 1 if on else 0]))


# ------------------------------------------------------------------------------------------ unit orders
func move(units: PackedInt32Array, x: int, y: int, queued: bool = false, prio_class: int = 2) -> bool:
	return _queue_units(AiTypes.Intent.MOVE, cell_key(x, y), prio_class, units, PackedInt32Array([x, y, 1 if queued else 0]))


func attack_move(units: PackedInt32Array, x: int, y: int, queued: bool = false, prio_class: int = 2) -> bool:
	return _queue_units(AiTypes.Intent.ATTACK_MOVE, cell_key(x, y), prio_class, units, PackedInt32Array([x, y, 1 if queued else 0]))


func attack(units: PackedInt32Array, target_eid: int, queued: bool = false, prio_class: int = 2) -> bool:
	return _queue_units(AiTypes.Intent.ATTACK, target_eid, prio_class, units, PackedInt32Array([target_eid, 1 if queued else 0]))


## target_eid 0 (no target) fires at the ground point (x, y).
func force_fire(units: PackedInt32Array, x: int, y: int, count: int = 0, target_eid: int = 0) -> bool:
	return _queue_units(AiTypes.Intent.FORCE_FIRE, cell_key(x, y), 2, units, PackedInt32Array([target_eid, x, y, count]))


## target_eid <= 0 guards the point (x, y).
func guard(units: PackedInt32Array, target_eid: int, x: int = 0, y: int = 0) -> bool:
	return _queue_units(AiTypes.Intent.GUARD, target_eid if target_eid > 0 else cell_key(x, y), 2, units, PackedInt32Array([maxi(target_eid, 0), x, y]))


func hold(units: PackedInt32Array, prio_class: int = 2) -> bool:
	return _queue_units(AiTypes.Intent.HOLD, 0, prio_class, units, PackedInt32Array())


func set_stance(units: PackedInt32Array, stance: int) -> bool:
	return _queue_units(AiTypes.Intent.SET_STANCE, stance, 3, units, PackedInt32Array([stance]))


func stop(units: PackedInt32Array, prio_class: int = 2) -> bool:
	return _queue_units(AiTypes.Intent.STOP, 0, prio_class, units, PackedInt32Array())


func scatter(units: PackedInt32Array, prio_class: int = 0) -> bool:
	return _queue_units(AiTypes.Intent.SCATTER, 0, prio_class, units, PackedInt32Array())


func deploy(units: PackedInt32Array) -> bool:
	return _queue_units(AiTypes.Intent.DEPLOY, 0, 2, units, PackedInt32Array())


func pack(units: PackedInt32Array) -> bool:
	return _queue_units(AiTypes.Intent.PACK, 0, 2, units, PackedInt32Array())


func set_mode(units: PackedInt32Array, mode_idx: int) -> bool:
	return _queue_units(AiTypes.Intent.SET_MODE, mode_idx, 2, units, PackedInt32Array([mode_idx]))


func use_ability(units: PackedInt32Array, ability_idx: int, x: int, y: int, target_eid: int = -1) -> bool:
	return _queue_units(AiTypes.Intent.USE_ABILITY, key2(ability_idx, cell_key(x, y)), 2, units, PackedInt32Array([ability_idx, maxi(target_eid, 0), x, y]))


func load_units(units: PackedInt32Array, transport_eid: int) -> bool:
	return _queue_units(AiTypes.Intent.LOAD, transport_eid, 2, units, PackedInt32Array([transport_eid]))


func unload(transport_eid: int, x: int, y: int) -> bool:
	return _queue_units(AiTypes.Intent.UNLOAD, transport_eid, 2, PackedInt32Array([transport_eid]), PackedInt32Array([x, y]))


func garrison(units: PackedInt32Array, building_eid: int) -> bool:
	return _queue_units(AiTypes.Intent.GARRISON, building_eid, 2, units, PackedInt32Array([building_eid]))


func capture(units: PackedInt32Array, target_eid: int) -> bool:
	return _queue_units(AiTypes.Intent.CAPTURE, target_eid, 2, units, PackedInt32Array([target_eid]))


func repair(units: PackedInt32Array, target_eid: int) -> bool:
	return _queue_units(AiTypes.Intent.REPAIR, target_eid, 2, units, PackedInt32Array([target_eid]))


func salvage(units: PackedInt32Array, wreck_id: int) -> bool:
	return _queue_units(AiTypes.Intent.SALVAGE, wreck_id, 2, units, PackedInt32Array([wreck_id]))


## Sends collectors to a deposit FIELD; (x, y) = the field centre in sub-cells (the sim resolves the field from the point).
func harvest(units: PackedInt32Array, deposit_id: int, x: int, y: int) -> bool:
	return _queue_units(AiTypes.Intent.HARVEST, deposit_id, 2, units, PackedInt32Array([x, y]))


func return_to_base(units: PackedInt32Array) -> bool:
	return _queue_units(AiTypes.Intent.RETURN_TO_BASE, 0, 2, units, PackedInt32Array())


# -------------------------------------------------------------------------------------------- powers (class 0)
## The sim's USE_POWER carries one point; (x2, y2) of two-point powers is not representable and is ignored.
func use_power(power_def: int, x: int, y: int, angle: int = 0, _x2: int = 0, _y2: int = 0) -> bool:
	return _queue_plain(AiTypes.Intent.USE_POWER, power_def, 0, PackedInt32Array([power_def, x, y, angle & Fp.ANGLE_MASK]))


## Own-structure powers (Rapid Turnaround): the target entity travels with the command.
func use_power_on(power_def: int, target_eid: int, x: int = 0, y: int = 0) -> bool:
	return _queue_plain(AiTypes.Intent.USE_POWER, power_def, 0, PackedInt32Array([power_def, x, y, 0, target_eid]))


func launch_superweapon(x: int, y: int, angle: int = 0) -> bool:
	return _queue_plain(AiTypes.Intent.LAUNCH_SW, 0, 0, PackedInt32Array([x, y, angle & Fp.ANGLE_MASK]))


# --------------------------------------------------------------------------------------------- encoding
## Intent -> wire command through the sim's SimCmd builders (the only place that knows command layouts).
func _encode(p: _Pending, ids: PackedInt32Array) -> PackedInt32Array:
	var a: PackedInt32Array = p.args
	match p.intent:
		AiTypes.Intent.BUILD_START:
			return SimCmd.build_start(a[0], 1)
		AiTypes.Intent.BUILD_PLACE:
			return SimCmd.build_place(a[0], a[1], a[2], a[3])
		AiTypes.Intent.BUILD_CANCEL:
			return SimCmd.build_cancel(0)
		AiTypes.Intent.TRAIN:
			return SimCmd.train(a[0], a[1], a[2])
		AiTypes.Intent.TRAIN_CANCEL:
			return SimCmd.train_cancel(a[0], a[1])
		AiTypes.Intent.QUEUE_HOLD:
			return SimCmd.queue_hold(PackedInt32Array([a[0]]), a[1])
		AiTypes.Intent.RESEARCH:
			return SimCmd.research(a[0])
		AiTypes.Intent.SET_RALLY:
			return SimCmd.set_rally(PackedInt32Array([a[0]]), a[1], a[2])
		AiTypes.Intent.STRUCT_REPAIR:
			return SimCmd.set_struct_repair(PackedInt32Array([a[0]]), 1 if a[1] != 0 else 0)
		AiTypes.Intent.MOVE:
			return SimCmd.move(ids, a[0], a[1], a[2])
		AiTypes.Intent.ATTACK_MOVE:
			return SimCmd.attack_move(ids, a[0], a[1], a[2])
		AiTypes.Intent.ATTACK:
			return SimCmd.attack(ids, a[0], a[1])
		AiTypes.Intent.FORCE_FIRE:
			return SimCmd.force_fire(ids, a[0], a[1], a[2], a[3])
		AiTypes.Intent.GUARD:
			return SimCmd.guard(ids, a[0], a[1], a[2])
		AiTypes.Intent.HOLD:
			return SimCmd.hold(ids)
		AiTypes.Intent.SET_STANCE:
			return SimCmd.set_stance(ids, a[0])
		AiTypes.Intent.STOP:
			return SimCmd.stop(ids)
		AiTypes.Intent.SCATTER:
			return SimCmd.scatter(ids)
		AiTypes.Intent.DEPLOY:
			return SimCmd.deploy(ids)
		AiTypes.Intent.PACK:
			return SimCmd.undeploy(ids)
		AiTypes.Intent.SET_MODE:
			return SimCmd.set_mode(ids, -1, a[0])
		AiTypes.Intent.USE_ABILITY:
			return SimCmd.use_ability(ids, a[0], 0, a[1], a[2], a[3])
		AiTypes.Intent.LOAD:
			return SimCmd.load(ids, a[0])
		AiTypes.Intent.UNLOAD:
			return SimCmd.unload(ids, 0, 0, a[0], a[1])
		AiTypes.Intent.GARRISON:
			return SimCmd.garrison(ids, a[0])
		AiTypes.Intent.CAPTURE:
			return SimCmd.capture(ids, a[0])
		AiTypes.Intent.REPAIR:
			return SimCmd.repair(ids, a[0])
		AiTypes.Intent.SALVAGE:
			return SimCmd.salvage(ids, a[0])
		AiTypes.Intent.HARVEST:
			return SimCmd.harvest(ids, 0, a[0], a[1])
		AiTypes.Intent.RETURN_TO_BASE:
			return SimCmd.return_to_base(ids)
		AiTypes.Intent.USE_POWER:
			return SimCmd.use_power(a[0], a[1], a[2], a[3], a[4] if a.size() > 4 else 0)
		AiTypes.Intent.LAUNCH_SW:
			return SimCmd.launch_superweapon(a[0], a[1], a[2])
	return PackedInt32Array()
