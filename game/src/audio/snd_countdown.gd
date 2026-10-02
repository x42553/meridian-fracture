class_name SndCountdown
extends RefCounted
## Superweapon / hostile power warning timeline (audio spec 5.12): a siren loop for the AFFECTED viewer, a beep on every
## whole second of the last five (three for powers) with rising pitch, and a final tone at zero. "Affected" = the viewer's
## team has an alive entity within `extent + 3 cells`, re-tested every 0.5 s (so the siren follows units in and out).

const TPS: int = 20
const REFRESH_S: float = 0.5
const TICK_PITCH: Array[float] = [1.00, 1.06, 1.12, 1.19, 1.26]

var reader: SndWorldReader = null
var pool: SndVoicePool = null
var map: SndEventMap = null
var stats: SndStats = SndStats.new()

var _w: Dictionary = {}  ## key -> warning record
var _refresh_left: float = 0.0
var _charge_handle: int = 0


func setup(p_reader: SndWorldReader, p_pool: SndVoicePool, p_map: SndEventMap) -> void:
	reader = p_reader
	pool = p_pool
	map = p_map


func active_count() -> int:
	return _w.size()


func has_siren(key: int) -> bool:
	return _w.has(key) and pool.is_active(int((_w[key] as Dictionary)["siren"]))


func siren_playing() -> bool:
	for k: Variant in _w.keys():
		if pool.is_active(int((_w[k] as Dictionary)["siren"])):
			return true
	return false


func on_warning(owner_pid: int, sw_idx: int, x: int, y: int, exec_tick: int, extent: int, launcher_id: int, hostile: bool) -> void:
	var key: int = owner_pid * 64 + sw_idx
	_w[key] = {"kind": 0, "x": x, "y": y, "exec": exec_tick, "extent": extent, "launcher": launcher_id, "hostile": hostile,
		"siren": 0, "affected": false, "last_sec": 99, "final": false, "ticks": 5}
	_evaluate(key, true)


func on_power_warning(power_idx: int, x: int, y: int, exec_tick: int, radius: int, hostile: bool) -> void:
	var key: int = 100000 + power_idx * 4096 + (x >> 10)
	_w[key] = {"kind": 1, "x": x, "y": y, "exec": exec_tick, "extent": radius, "launcher": 0, "hostile": hostile,
		"siren": 0, "affected": false, "last_sec": 99, "final": false, "ticks": 3}
	_evaluate(key, true)


func on_cancelled(owner_pid: int, sw_idx: int) -> void:
	var key: int = owner_pid * 64 + sw_idx
	if not _w.has(key):
		return
	pool.stop(int((_w[key] as Dictionary)["siren"]), 300)
	_w.erase(key)


func clear() -> void:
	for k: Variant in _w.keys():
		pool.stop(int((_w[k] as Dictionary)["siren"]), 0)
	_w.clear()
	if _charge_handle != 0:
		pool.stop(_charge_handle, 0)
		_charge_handle = 0


func _evaluate(key: int, first: bool) -> void:
	var w: Dictionary = _w[key]
	var affected: bool = bool(w["hostile"]) and reader.team_within(int(w["x"]), int(w["y"]), int(w["extent"]) + 3072)
	if affected and not pool.is_active(int(w["siren"])) and (first or not bool(w["affected"]) or int(w["siren"]) == 0):
		var def: SndEventDef = map.get_def(&"snd.alarm.sw_siren") if int(w["kind"]) == 0 else null
		if def != null:
			w["siren"] = pool.play_def(def, Vector3.ZERO, &"", 0.0)
	elif not affected and pool.is_active(int(w["siren"])):
		pool.stop(int(w["siren"]), 300)
		w["siren"] = 0
	w["affected"] = affected


## sim_tick_f = world.tick + alpha. Drives siren re-tests, the beeps and the final tone.
func update(sim_tick_f: float, dt: float) -> void:
	if _w.is_empty():
		return
	_refresh_left -= dt
	var refresh: bool = _refresh_left <= 0.0
	if refresh:
		_refresh_left = REFRESH_S
	var done: Array = []
	for k: Variant in _w.keys():
		var w: Dictionary = _w[k]
		if refresh:
			_evaluate(int(k), false)
		var left_s: float = (float(w["exec"]) - sim_tick_f) / float(TPS)
		var sec: int = int(ceil(left_s))
		if bool(w["affected"]) and sec <= int(w["ticks"]) and sec >= 1 and sec < int(w["last_sec"]):
			w["last_sec"] = sec
			var tick_def: SndEventDef = map.get_def(&"snd.alarm.countdown_tick")
			if tick_def != null:
				pool.play_def(tick_def, Vector3.ZERO, &"", 0.0, TICK_PITCH[clampi(5 - sec, 0, 4)])
		if left_s <= 0.0:
			if bool(w["affected"]) and not bool(w["final"]) and int(w["kind"]) == 0:
				var fin: SndEventDef = map.get_def(&"snd.alarm.countdown_final")
				if fin != null:
					pool.play_def(fin, Vector3.ZERO, &"", 0.0)
			w["final"] = true
			pool.stop(int(w["siren"]), 300)
			done.append(k)
	for k2: Variant in done:
		_w.erase(k2)


## Own superweapon charge hum: pitch 0.8 + 0.4 * fraction; frozen and 6 dB down during a power shortage.
func set_charge(fraction: float, shortage: bool, sw_name: String) -> void:
	if sw_name == "":
		return
	if _charge_handle == 0 or not pool.is_active(_charge_handle):
		var def: SndEventDef = map.get_def(StringName("snd.sw.%s.charge" % sw_name))
		if def == null:
			return
		_charge_handle = pool.play_def(def, Vector3.ZERO, &"", -6.0 if shortage else 0.0)
	if _charge_handle != 0:
		if not shortage:
			pool.set_pitch(_charge_handle, 0.8 + 0.4 * clampf(fraction, 0.0, 1.0))
		pool.set_gain_db(_charge_handle, -6.0 if shortage else 0.0)


func stop_charge() -> void:
	if _charge_handle != 0:
		pool.stop(_charge_handle)
		_charge_handle = 0
