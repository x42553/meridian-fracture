class_name UiMissionModel
extends RefCounted
## Presentation model of a running scripted mission (MIS2): the mission's texts (DefMission, from GameData) plus the live state the
## UI reads through `UiSimPort.mission_state` (objective states, timers, result). Pure: no nodes, no sim access, so it is unit-tested
## and also builds the objective list of the result screen. The state is authoritative per snapshot (`sync`), so a replay seek or a
## rebuilt world just re-syncs; events (`MISSION_*` records) only add the moments (what flashes, which message to show).

# objective states (= SimMissionConst.OBJ_*, asserted by the unit test)
const S_HIDDEN: int = 0
const S_ACTIVE: int = 1
const S_COMPLETED: int = 2
const S_FAILED: int = 3
# timer states (= SimMissionConst.TM_*)
const T_STOPPED: int = 0
const T_RUNNING: int = 1
const T_EXPIRED: int = 2
# result (= SimMissionConst.RES_*)
const R_NONE: int = 0
const R_WIN: int = 1
const R_LOSE: int = 2

const KIND_PRIMARY: int = 0
const KIND_SECONDARY: int = 1
const KIND_HIDDEN: int = 2

const STATE_TEXT: PackedStringArray = ["HIDDEN", "ACTIVE", "COMPLETE", "FAILED"]

var def: DefMission = null
var obj_state: PackedInt32Array = PackedInt32Array()
var timer_state: PackedInt32Array = PackedInt32Array()
var timer_end: PackedInt32Array = PackedInt32Array()
var timer_len: PackedInt32Array = PackedInt32Array()
var result: int = R_NONE
var result_tick: int = 0
## Tick of the last `sync` (the clock the timers count against).
var tick: int = 0
var synced: bool = false
## Real time (msec) of the last change of each objective; 0 = never changed since the model exists (drives the flash).
var changed_msec: PackedInt32Array = PackedInt32Array()


func setup(d: DefMission) -> void:
	def = d
	var n: int = d.objectives.size() if d != null else 0
	obj_state = PackedInt32Array()
	obj_state.resize(n)
	changed_msec = PackedInt32Array()
	changed_msec.resize(n)
	var nt: int = d.timers.size() if d != null else 0
	timer_state = PackedInt32Array()
	timer_state.resize(nt)
	timer_end = PackedInt32Array()
	timer_end.resize(nt)
	timer_len = PackedInt32Array()
	timer_len.resize(nt)
	synced = false


## Takes the snapshot (`UiSimPort.mission_state` layout) and returns the objective indices whose state changed since the last sync
## (none for the first one: nothing flashes when the screen opens or a replay seeks). `now_tick` is the world tick.
func sync(snap: PackedInt32Array, now_tick: int, now_msec: int = 0) -> PackedInt32Array:
	var changed: PackedInt32Array = PackedInt32Array()
	if snap.size() < 3 or def == null:
		return changed
	tick = now_tick
	result = snap[0]
	result_tick = snap[1]
	var n: int = mini(snap[2], obj_state.size())
	for i: int in n:
		var st: int = snap[3 + i]
		if synced and st != obj_state[i]:
			changed.append(i)
			changed_msec[i] = maxi(now_msec, 1)
		obj_state[i] = st
	var base: int = 3 + snap[2]
	if snap.size() > base:
		var nt: int = mini(snap[base], timer_state.size())
		for j: int in nt:
			var o: int = base + 1 + j * 3
			if o + 2 >= snap.size():
				break
			timer_state[j] = snap[o]
			timer_end[j] = snap[o + 1]
			timer_len[j] = snap[o + 2]
	synced = true
	return changed


# ---------------------------------------------------------------- objectives

func objective_count() -> int:
	return obj_state.size()


## An objective as shown: {idx, id, kind, text, state}; state text via `STATE_TEXT`.
func objective(i: int) -> Dictionary:
	var o: DefMissionObjective = def.objectives[i]
	return {"idx": i, "id": o.id, "kind": o.kind, "text": o.ui_text, "state": obj_state[i]}


## The visible objectives: primaries first, then secondaries (a revealed hidden-kind objective counts as secondary), each in
## declaration order; objectives that are still hidden are left out.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	for pass_idx: int in 2:
		for i: int in def.objectives.size():
			var o: DefMissionObjective = def.objectives[i]
			var is_primary: bool = o.kind == KIND_PRIMARY
			if is_primary != (pass_idx == 0) or obj_state[i] == S_HIDDEN:
				continue
			out.append(objective(i))
	return out


## [done, total] of the visible objectives of a kind (`KIND_PRIMARY`, or `KIND_SECONDARY` for secondary + revealed hidden ones).
func progress(primary: bool) -> Vector2i:
	var done: int = 0
	var total: int = 0
	for r: Dictionary in rows():
		if (int(r["kind"]) == KIND_PRIMARY) == primary:
			total += 1
			done += 1 if int(r["state"]) == S_COMPLETED else 0
	return Vector2i(done, total)


func any_failed_primary() -> bool:
	for r: Dictionary in rows():
		if int(r["kind"]) == KIND_PRIMARY and int(r["state"]) == S_FAILED:
			return true
	return false


## Objective list of the result screen: the same rows, an objective that was still active when the mission ended is "not completed".
func final_rows() -> Array[Dictionary]:
	return rows()


static func state_word(state: int, final: bool = false) -> String:
	if final and state == S_ACTIVE:
		return "NOT COMPLETED"
	return STATE_TEXT[clampi(state, 0, STATE_TEXT.size() - 1)]


# ---------------------------------------------------------------- timers

## The visible timers: running, with a label (an unlabelled timer is the script's own business). {idx, label, left_ticks, len_ticks}
func visible_timers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	for j: int in def.timers.size():
		var t: DefMissionTimer = def.timers[j]
		if t.ui_label == "" or timer_state[j] != T_RUNNING:
			continue
		out.append({"idx": j, "label": t.ui_label, "left_ticks": maxi(timer_end[j] - tick, 0), "len_ticks": timer_len[j]})
	return out


## "m:ss" of a tick count (rounded up to whole seconds, so a timer shows 0:01 until it expires).
static func clock_of(ticks: int) -> String:
	var s: int = (maxi(ticks, 0) + SimConfig.TPS - 1) / SimConfig.TPS
	return UiFormatLite.clock(s)


# ---------------------------------------------------------------- messages

## The message of a MISSION_MESSAGE record: {text, speaker, announcer} (announcer = line id or "").
func message_of(msg_idx: int, ann_idx: int) -> Dictionary:
	if def == null or msg_idx < 0 or msg_idx >= def.messages.size():
		return {}
	var m: DefMissionMessage = def.messages[msg_idx]
	var line: String = ""
	if ann_idx >= 0 and ann_idx < def.announcers.size():
		line = def.announcers[ann_idx]
	return {"text": m.ui_text, "speaker": m.ui_speaker, "announcer": line}


## Seconds a message stays on screen: reading speed, at least 5 s, at most 16 s.
static func message_seconds(text: String) -> float:
	return clampf(3.0 + float(text.length()) / 16.0, 5.0, 16.0)


# ---------------------------------------------------------------- events

## The mission records of `records` as plain dictionaries in order: {type: &"objective"|&"message"|&"camera"|&"music"|&"timer"|&"result", ...}.
static func decode(records: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in UiEv.count(records):
		var t: int = UiEv.field(records, i, UiEv.I_TYPE)
		if t < UiEv.MISSION_OBJECTIVE or t > UiEv.MISSION_MUSIC:
			continue
		var a: int = UiEv.field(records, i, UiEv.I_A)
		var b: int = UiEv.field(records, i, UiEv.I_B)
		var c: int = UiEv.field(records, i, UiEv.I_C)
		var tk: int = UiEv.field(records, i, UiEv.I_TICK)
		match t:
			UiEv.MISSION_OBJECTIVE:
				out.append({"type": &"objective", "tick": tk, "idx": a, "state": b, "kind": c, "prev": UiEv.field(records, i, UiEv.I_D)})
			UiEv.MISSION_MESSAGE:
				out.append({"type": &"message", "tick": tk, "idx": a, "announcer": b})
			UiEv.MISSION_CAMERA:
				out.append({"type": &"camera", "tick": tk, "x": UiEv.field(records, i, UiEv.I_X), "y": UiEv.field(records, i, UiEv.I_Y), "area": a, "ticks": b})
			UiEv.MISSION_MUSIC:
				out.append({"type": &"music", "tick": tk, "state": a})
			UiEv.MISSION_TIMER:
				out.append({"type": &"timer", "tick": tk, "idx": a, "what": b, "len": c})
			UiEv.MISSION_RESULT:
				out.append({"type": &"result", "tick": tk, "pid": a, "result": b})
	return out
