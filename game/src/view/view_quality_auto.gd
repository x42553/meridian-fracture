class_name ViewQualityAuto
extends RefCounted
## Frame-time window sampler with hysteresis (render spec 5.12). Wall-clock frame time is the only signal
## (GPU timestamps read 0.0 on Metal). Windows of 3 s; step DOWN one preset when p95 > 1.25 * target for 2 consecutive
## windows; step UP when p95 < 0.6 * target for 10 consecutive windows, at most once per 30 s, never above the user's cap
## and never within 120 s of a down-step. Below LOW the render scale steps 0.75 -> 0.65 -> 0.55 (and back up first).

const WINDOW_S: float = 3.0
const HITCH_S: float = 0.25  ## frames longer than this (alt-tab, load) are ignored
const DOWN_RATIO: float = 1.25
const UP_RATIO: float = 0.6
const DOWN_WINDOWS: int = 2
const UP_WINDOWS: int = 10
const UP_MIN_INTERVAL_S: float = 30.0
const UP_AFTER_DOWN_S: float = 120.0
const MAX_SCALE_STEP: int = 2

var enabled: bool = true
var target_ms: float = 16.667
var last_p95_ms: float = 0.0

var _q: ViewQuality = null
var _on_change: Callable = Callable()
var _samples: PackedFloat32Array = PackedFloat32Array()
var _win_t: float = 0.0
var _now: float = 0.0
var _bad: int = 0
var _good: int = 0
var _last_down_at: float = -1.0e9
var _last_up_at: float = -1.0e9


## on_change(new_preset: int, reason: String) is called after every step.
func setup(q: ViewQuality, on_change: Callable) -> void:
	_q = q
	_on_change = on_change
	target_ms = 1000.0 / float(maxi(q.target_fps, 1))
	_samples.clear()
	_win_t = 0.0
	_bad = 0
	_good = 0


## Feed every frame's delta (seconds, real time).
func sample(dt: float) -> void:
	if not enabled or _q == null:
		return
	if dt > HITCH_S:
		return
	_now += dt
	_win_t += dt
	_samples.append(dt * 1000.0)
	if _win_t >= WINDOW_S - 0.0005:
		_close_window()


func _p95(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s: PackedFloat32Array = a.duplicate()
	s.sort()
	return s[clampi(int(ceil(0.95 * float(s.size()))) - 1, 0, s.size() - 1)]


func _close_window() -> void:
	last_p95_ms = _p95(_samples)
	_samples.clear()
	_win_t = 0.0
	if last_p95_ms > DOWN_RATIO * target_ms:
		_bad += 1
		_good = 0
		if _bad >= DOWN_WINDOWS:
			_bad = 0
			_step_down()
	elif last_p95_ms < UP_RATIO * target_ms:
		_good += 1
		_bad = 0
		if _good >= UP_WINDOWS:
			_good = 0
			_step_up()
	else:
		_bad = 0
		_good = 0


func _step_down() -> void:
	_last_down_at = _now
	if _q.preset > ViewQuality.Preset.LOW:
		_q.set_preset(_q.preset - 1)
		_notify("p95 %.1f ms > %.1f ms, preset down" % [last_p95_ms, DOWN_RATIO * target_ms])
	elif _q.auto_scale_step < MAX_SCALE_STEP:
		_q.auto_scale_step += 1
		_q.resolve()
		_notify("p95 %.1f ms > %.1f ms, render scale %.2f" % [last_p95_ms, DOWN_RATIO * target_ms, _q.get_float(&"render_scale")])


func _step_up() -> void:
	if _now - _last_up_at < UP_MIN_INTERVAL_S or _now - _last_down_at < UP_AFTER_DOWN_S:
		return
	if _q.preset == ViewQuality.Preset.LOW and _q.auto_scale_step > 0:
		_q.auto_scale_step -= 1
		_q.resolve()
		_last_up_at = _now
		_notify("p95 %.1f ms, render scale %.2f" % [last_p95_ms, _q.get_float(&"render_scale")])
	elif _q.preset < _q.preset_cap:
		_q.set_preset(_q.preset + 1)
		_last_up_at = _now
		_notify("p95 %.1f ms < %.1f ms, preset up" % [last_p95_ms, UP_RATIO * target_ms])


func _notify(reason: String) -> void:
	if _on_change.is_valid():
		_on_change.call(_q.preset, reason)
