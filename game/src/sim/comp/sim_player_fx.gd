class_name SimPlayerFx
extends SimComponent
## Slot `p.fx` (abilities 4.8): the active windows of a player's global-effect powers. The numbers themselves live where
## they act (aura windows for Treaty Coordination / Central Priority / Reserve Bandwidth, economy knobs for
## Mobilization Order and Recovery Priority's salvage time, timed effects on the affected units); this record keeps the
## list of running windows so that units spawned or unloaded inside a window receive the effect, and so that the AI and
## the UI can read what is active. Ints only; every field is authoritative and hashed.

const HASH_EXEMPT: PackedStringArray = []

const MAX_ACTIVE: int = 8
const STRIDE: int = 4
const E_FX: int = 0  ## fx table index of the effect, -1 = empty
const E_UNTIL: int = 1  ## first tick the window no longer applies
const E_SRC: int = 2  ## src_key of the timed effects it applies (FXK(SRC_POWER, power idx))
const E_TARGET: int = 3  ## chosen target entity (Rapid Turnaround), -1 none

var active: PackedInt32Array = PackedInt32Array()  ## MAX_ACTIVE * STRIDE
var n_active: int = 0


func _init() -> void:
	active.resize(MAX_ACTIVE * STRIDE)
	active.fill(-1)


## Adds (or extends) a window; false when the table is full of longer-lived windows.
func add(fx_idx: int, until_tick: int, src_key: int, target_eid: int) -> bool:
	var free_i: int = -1
	var min_i: int = 0
	var min_until: int = 0x7FFFFFFF
	for i: int in MAX_ACTIVE:
		var b: int = i * STRIDE
		if active[b + E_FX] == fx_idx and active[b + E_SRC] == src_key:
			active[b + E_UNTIL] = maxi(active[b + E_UNTIL], until_tick)
			active[b + E_TARGET] = target_eid
			return true
		if active[b + E_FX] < 0:
			if free_i < 0:
				free_i = i
		elif active[b + E_UNTIL] < min_until:
			min_until = active[b + E_UNTIL]
			min_i = i
	var slot: int = free_i
	if slot < 0:
		if until_tick <= min_until:
			return false
		slot = min_i
		n_active -= 1
	var w: int = slot * STRIDE
	active[w + E_FX] = fx_idx
	active[w + E_UNTIL] = until_tick
	active[w + E_SRC] = src_key
	active[w + E_TARGET] = target_eid
	n_active += 1
	return true


## Drops the windows whose end has come. true when anything changed.
func prune(tick: int) -> bool:
	var changed: bool = false
	for i: int in MAX_ACTIVE:
		var b: int = i * STRIDE
		if active[b + E_FX] >= 0 and active[b + E_UNTIL] <= tick:
			active[b + E_FX] = -1
			active[b + E_UNTIL] = -1
			active[b + E_SRC] = -1
			active[b + E_TARGET] = -1
			n_active -= 1
			changed = true
	return changed


func remove_src(src_key: int) -> void:
	for i: int in MAX_ACTIVE:
		var b: int = i * STRIDE
		if active[b + E_FX] >= 0 and active[b + E_SRC] == src_key:
			active[b + E_FX] = -1
			active[b + E_UNTIL] = -1
			active[b + E_SRC] = -1
			active[b + E_TARGET] = -1
			n_active -= 1


## true while a window of effect fx_idx runs.
func has_fx(fx_idx: int, tick: int) -> bool:
	for i: int in MAX_ACTIVE:
		var b: int = i * STRIDE
		if active[b + E_FX] == fx_idx and active[b + E_UNTIL] > tick:
			return true
	return false


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(n_active)
	buf.append_array(active)
