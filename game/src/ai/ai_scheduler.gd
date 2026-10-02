class_name AiScheduler
extends RefCounted
## Fixed slot table with COUNT-based time slicing (ai.md 5.2): identical behaviour at any simulation speed because nothing
## reads the wall clock. Slots are evaluated in this order in every think; a slot is DUE when at least one multiple of its
## period (offset by `phase`) lies in (last_tick, tick]; a due slot runs ONCE per think with quota x min(4, ceil(dt/period))
## work units. A due slot skipped for lack of budget is `late` and runs first next think; after 3 consecutive skips its quota
## is reserved (it runs even into debt), so no module starves.

enum Slot { INGEST = 0, KB = 1, WATCHDOG = 2, DISPERSAL = 3, ECONOMY = 4, BUILD = 5, TECH = 6, PRODUCTION = 7, STRATEGY = 8,
	DEFENSE = 9, ATTACK = 10, OPS = 11, POWERS = 12, MICRO = 13, SUPPORT = 14 }
const SLOT_COUNT: int = 15
## Period codes: positive = fixed ticks; PER_THINK = think_period_ticks; PER_THINK2 = max(5, think/2); PER_THINK4 = think x 4;
## PER_MICRO = micro_period_ticks (0 disables the slot).
const PER_THINK: int = -1
const PER_THINK2: int = -2
const PER_THINK4: int = -3
const PER_MICRO: int = -4
const PERIODS: PackedInt32Array = [1, 5, 100, 2, PER_THINK, PER_THINK, 40, PER_THINK2, 40, 10, PER_THINK4, 1, 10, PER_MICRO, 20]
const PHASES: PackedInt32Array = [0, 1, 7, 0, 2, 4, 6, 3, 8, 5, 9, 0, 7, 1, 11]
const QUOTAS: PackedInt32Array = [120, 40, 20, 40, 50, 80, 30, 60, 60, 40, 60, 80, 60, 60, 40]
const SLOT_NAMES: PackedStringArray = [
	"ingest", "kb", "watchdog", "dispersal", "economy", "build", "tech", "production", "strategy", "defense", "attack", "ops",
	"powers", "micro", "support",
]
const SKIP_RESERVE: int = 3  ## consecutive skips before the quota is reserved

var period: PackedInt32Array = PackedInt32Array()  ## effective period per slot (0 = disabled)
var modules: Array = []  ## per slot: duck-typed module (setup / step(ctx, budget) / state_hash) or null
var late: PackedByteArray = PackedByteArray()
var skips: PackedInt32Array = PackedInt32Array()
var runs: PackedInt32Array = PackedInt32Array()  ## diagnostics: how often each slot ran
var last_wu: PackedInt32Array = PackedInt32Array()  ## wu used by each slot in the last think
var _last_tick: int = -1
var _slot_budget: AiBudget = AiBudget.new()


func _init(diff: AiDifficultyProfile) -> void:
	period.resize(SLOT_COUNT)
	for s: int in SLOT_COUNT:
		period[s] = slot_period(s, diff)
	modules.resize(SLOT_COUNT)
	late.resize(SLOT_COUNT)
	skips.resize(SLOT_COUNT)
	runs.resize(SLOT_COUNT)
	last_wu.resize(SLOT_COUNT)


## Effective period of a slot for a difficulty (ticks; 0 = the slot is disabled).
static func slot_period(slot: int, diff: AiDifficultyProfile) -> int:
	var p: int = PERIODS[slot]
	var think: int = diff.think_period_ticks
	match p:
		PER_THINK:
			return think
		PER_THINK2:
			return maxi(5, think / 2)
		PER_THINK4:
			return think * 4
		PER_MICRO:
			return diff.micro_period_ticks
	return p


## Registers a module on a slot (replaces the previous one). The module needs `step(ctx, budget)`.
func register(slot: int, module: Object) -> void:
	modules[slot] = module


## Due arithmetic: a multiple of `per` (offset `phase`) lies in (last, tick].
static func is_due(per: int, phase: int, last: int, tick: int) -> bool:
	if per <= 0:
		return false
	return Fp.floor_div(tick - phase, per) > Fp.floor_div(last - phase, per)


func due(slot: int, tick: int) -> bool:
	return is_due(period[slot], PHASES[slot], _last_tick, tick)


## Runs every due slot once, in slot order (late slots first). `budget` is the think's budget; each slot gets its own
## quota (scaled by dt) and is charged for what it used. Returns the number of slots that ran.
func run(tick: int, dt: int, ctx: Object, budget: AiBudget) -> int:
	var order: PackedInt32Array = PackedInt32Array()
	for s: int in SLOT_COUNT:
		if late[s] != 0:
			order.append(s)
	for s2: int in SLOT_COUNT:
		if late[s2] == 0 and due(s2, tick):
			order.append(s2)
	var ran: int = 0
	last_wu.fill(0)
	for s3: int in order:
		var per: int = maxi(period[s3], 1)
		var quota: int = QUOTAS[s3] * mini(4, (dt + per - 1) / per)
		var reserved: bool = skips[s3] >= SKIP_RESERVE
		if budget.left <= 0 and not reserved:
			late[s3] = 1
			skips[s3] += 1
			continue
		late[s3] = 0
		skips[s3] = 0
		var m: Object = modules[s3]
		var used: int = 0
		if m != null:
			_slot_budget.left = quota if reserved else mini(quota, budget.left)
			_slot_budget.debt = 0
			_slot_budget.used = 0
			m.call("step", ctx, _slot_budget)
			used = _slot_budget.used
		else:
			used = 1  # an empty slot still costs its dispatch
		budget.spend(used)
		last_wu[s3] = used
		runs[s3] += 1
		ran += 1
	_last_tick = tick
	return ran


func last_tick() -> int:
	return _last_tick


## Marks the clock so the first think treats slots relative to `tick` (bootstrap).
func start_at(tick: int) -> void:
	_last_tick = tick - 1


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array()
	v.append(_last_tick)
	v.append_array(skips)
	return AiRng.hash_ints(v)
