class_name SndBusFader
extends RefCounted
## Ramps bus volumes and effect toggles per frame; a bus never jumps in one step (audio spec 5.1 rule 4). Volumes are
## dB targets; the ramp is linear in dB and at most `MAX_DB_PER_S` steep unless a shorter ramp is requested.

const MAX_STEP_DB: float = 6.0

var _bus: Dictionary = {}  ## StringName -> {from, to, t, dur} (seconds)
var _fx: Dictionary = {}  ## "bus|effect" -> {bus, idx, target, ...}


## Ramps the bus volume to `db` over `ramp_ms` (0 = next update). `db <= -80` mutes.
func set_target_db(bus: StringName, db: float, ramp_ms: int = 100) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var cur: float = AudioServer.get_bus_volume_db(idx)
	if _bus.has(bus):
		cur = float((_bus[bus] as Dictionary).get("cur", cur))
	_bus[bus] = {"from": cur, "cur": cur, "to": maxf(db, SndConfig.SILENT_DB), "t": 0.0, "dur": maxf(float(ramp_ms) / 1000.0, 0.0)}


func target_of(bus: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus)
	if _bus.has(bus):
		return float((_bus[bus] as Dictionary)["to"])
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else SndConfig.SILENT_DB


## Enabling flips the flag immediately (the effect ramps itself); disabling waits `ramp_ms` first.
func set_effect_enabled(bus: StringName, effect_id: StringName, enabled: bool, ramp_ms: int = 100) -> void:
	var bi: int = AudioServer.get_bus_index(bus)
	var ei: int = SndBus.effect_index(bus, effect_id)
	if bi < 0 or ei < 0:
		return
	var key: String = "%s|%s" % [str(bus), str(effect_id)]
	if enabled:
		AudioServer.set_bus_effect_enabled(bi, ei, true)
		_fx.erase(key)
	else:
		_fx[key] = {"bus": bi, "idx": ei, "left": float(ramp_ms) / 1000.0}


func update(dt: float) -> void:
	for bus: Variant in _bus.keys():
		var r: Dictionary = _bus[bus]
		var idx: int = AudioServer.get_bus_index(bus)
		if idx < 0:
			_bus.erase(bus)
			continue
		var dur: float = r["dur"]
		var t: float = float(r["t"]) + dt
		var cur: float
		if dur <= 0.0 or t >= dur:
			cur = r["to"]
		else:
			cur = lerpf(r["from"], r["to"], t / dur)
		var prev: float = r["cur"]
		cur = clampf(cur, prev - MAX_STEP_DB, prev + MAX_STEP_DB)
		r["t"] = t
		r["cur"] = cur
		AudioServer.set_bus_volume_db(idx, cur)
		if is_equal_approx(cur, float(r["to"])):
			_bus.erase(bus)
	for key: Variant in _fx.keys():
		var f: Dictionary = _fx[key]
		f["left"] = float(f["left"]) - dt
		if float(f["left"]) <= 0.0:
			AudioServer.set_bus_effect_enabled(f["bus"], f["idx"], false)
			_fx.erase(key)


func is_idle() -> bool:
	return _bus.is_empty() and _fx.is_empty()
