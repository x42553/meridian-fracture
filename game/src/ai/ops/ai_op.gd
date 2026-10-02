class_name AiOp
extends RefCounted
## Abstract operation (ai.md 3.5 / 2.5): a state machine that owns one or more squads and emits intents through
## ctx.cmd. AiBrain assigns `id`, calls `start` (claims units; false discards the op), then `update` whenever
## `next_update_tick` is reached and finally `abort` / the end of the state machine (DONE / FAILED), after which the brain
## forgets the op. Units are only borrowed: `release` returns them to the reserve squad.

var id: int = 0
var type: int = AiTypes.OpType.NONE
var state: int = AiTypes.OpState.NEW
var priority: int = 50
var created_tick: int = 0
var next_update_tick: int = 0
var timeout_tick: int = 0
var squads: PackedInt32Array = PackedInt32Array()
var tx: int = 0  ## target position (sub-cell)
var ty: int = 0
var target_ghost: int = -1  ## ghost eid of the target or -1
var committed_value: int = 0  ## credit value of the units claimed at start
var period: int = 10  ## ticks between updates
var state_since: int = 0

# measurements of the last measure() call
var alive: int = 0
var cx: int = 0
var cy: int = 0
var value_now: int = 0
var hp_frac_q8: int = 256
var radius: int = 0
var ids: PackedInt32Array = PackedInt32Array()  ## live unit ids
var ground: PackedInt32Array = PackedInt32Array()  ## ... that are not aircraft (all of them when there is no ground unit)
var airc: PackedInt32Array = PackedInt32Array()


## Claims the op's units. False => discard the op.
func start(_ctx: AiContext) -> bool:
	return false


func update(_ctx: AiContext, _budget: AiBudget) -> void:
	pass


## Returns the units to the reserve and ends the op as FAILED.
func abort(ctx: AiContext, _reason: int) -> void:
	release(ctx)
	state = AiTypes.OpState.FAILED


## `list` without the units micro / a handler controls at the moment (they must not be re-ordered by the op).
func free_ids(ctx: AiContext, list: PackedInt32Array) -> PackedInt32Array:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return list
	var out: PackedInt32Array = PackedInt32Array()
	for eid: int in list:
		if not b.leased(eid, ctx.tick):
			out.append(eid)
	return out


## A unit worth `value` credits left the op on purpose (it retreated to the repair point): it must not count as a loss.
func note_detached(_value: int) -> void:
	pass


## Asks the op to re-issue its orders at its next update (micro ended a control lease).
func nudge() -> void:
	pass


func is_over() -> bool:
	return state == AiTypes.OpState.DONE or state == AiTypes.OpState.FAILED


func set_state(ctx: AiContext, s: int) -> void:
	state = s
	state_since = ctx.tick


func brain(ctx: AiContext) -> AiBrain:
	return ctx.brain as AiBrain


## Returns every squad of the op to the reserve.
func release(ctx: AiContext) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	if b == null:
		return
	var sm: AiSquadManager = b.squads()
	for sid: int in squads:
		sm.release(sid, true)
	squads.resize(0)


## Refreshes alive / centroid / value / hp fraction / radius and the ground / air split from the knowledge base.
func measure(ctx: AiContext, budget: AiBudget) -> void:
	var b: AiBrain = ctx.brain as AiBrain
	var sm: AiSquadManager = b.squads()
	var t: AiEntityTable = ctx.kb.own
	ids.resize(0)
	ground.resize(0)
	airc.resize(0)
	var sx: int = 0
	var sy: int = 0
	var hp: int = 0
	var hpm: int = 0
	var val: int = 0
	for sid: int in squads:
		var sq: AiSquad = sm.squad(sid)
		if sq == null:
			continue
		budget.spend(1 + sq.units.size() / 8)
		for eid: int in sq.units:
			var r: int = t.row(eid)
			if r < 0:
				continue
			ids.append(eid)
			if AiForce.is_air(ctx, t.def[r]):
				airc.append(eid)
			else:
				ground.append(eid)
			sx += t.x[r]
			sy += t.y[r]
			hp += t.hp[r]
			hpm += t.hp_max[r]
			val += t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1)
	alive = ids.size()
	value_now = val
	hp_frac_q8 = hp * 256 / maxi(hpm, 1)
	if ground.is_empty():
		ground = ids.duplicate()
		airc.resize(0)
	if alive == 0:
		return
	# centroid of the ground units (they set the pace)
	sx = 0
	sy = 0
	for eid2: int in ground:
		var r2: int = t.row(eid2)
		sx += t.x[r2]
		sy += t.y[r2]
	cx = sx / maxi(ground.size(), 1)
	cy = sy / maxi(ground.size(), 1)
	var rad2: int = 0
	for eid3: int in ground:
		var r3: int = t.row(eid3)
		var dx: int = t.x[r3] - cx
		var dy: int = t.y[r3] - cy
		rad2 = maxi(rad2, dx * dx + dy * dy)
	radius = Fp.isqrt(rad2)


## Number of `list` units within `r` of (x, y).
func count_within(ctx: AiContext, list: PackedInt32Array, x: int, y: int, r: int) -> int:
	var t: AiEntityTable = ctx.kb.own
	var n: int = 0
	var r2: int = r * r
	for eid: int in list:
		var row: int = t.row(eid)
		if row < 0:
			continue
		var dx: int = t.x[row] - x
		var dy: int = t.y[row] - y
		if dx * dx + dy * dy <= r2:
			n += 1
	return n


## The unit of `list` nearest to (x, y), -1 when empty.
func nearest_unit(ctx: AiContext, list: PackedInt32Array, x: int, y: int) -> int:
	var t: AiEntityTable = ctx.kb.own
	var best: int = -1
	var best_d: int = 1 << 60
	for eid: int in list:
		var row: int = t.row(eid)
		if row < 0:
			continue
		var dx: int = t.x[row] - x
		var dy: int = t.y[row] - y
		var d: int = dx * dx + dy * dy
		if d < best_d or (d == best_d and eid < best):
			best_d = d
			best = eid
	return best


func state_hash() -> int:
	return AiRng.hash_ints(PackedInt32Array([id, type, state, priority, created_tick, squads.size(), tx, ty, alive, cx, cy]))
