class_name SndCombatMeter
extends RefCounted
## Leaky-integrator "heat" of the battle in earshot (audio spec 5.7): feeds the music (calm/combat requests, stem
## intensity) and the far-battle ambience bed, never the sound effects.

var heat: float = 0.0
var intensity: float = 0.0
var far_heat: float = 0.0
var urgent: bool = false

var tau_s: float = 6.0
var h_ref: float = 25.0
var attack_s: float = 0.6
var release_s: float = 4.0
var radius_m: float = 80.0
var min_dist_weight: float = 0.15
var far_weight: float = 0.25
var combat_on: float = 0.40
var combat_on_hold_s: float = 1.0
var combat_off: float = 0.15
var combat_off_hold_s: float = 18.0
var min_combat_s: float = 25.0
var weights: Dictionary = {}

var _above_since_ms: int = -1
var _below_since_ms: int = -1
var _combat_since_ms: int = -1
var _combat: bool = false


func configure(cfg: Dictionary) -> void:
	tau_s = float(cfg.get("tau_s", tau_s))
	h_ref = float(cfg.get("h_ref", h_ref))
	attack_s = float(cfg.get("attack_s", attack_s))
	release_s = float(cfg.get("release_s", release_s))
	radius_m = float(cfg.get("radius_m", radius_m))
	min_dist_weight = float(cfg.get("min_dist_weight", min_dist_weight))
	far_weight = float(cfg.get("far_weight", far_weight))
	combat_on = float(cfg.get("combat_on", combat_on))
	combat_on_hold_s = float(cfg.get("combat_on_hold_s", combat_on_hold_s))
	combat_off = float(cfg.get("combat_off", combat_off))
	combat_off_hold_s = float(cfg.get("combat_off_hold_s", combat_off_hold_s))
	min_combat_s = float(cfg.get("min_combat_s", min_combat_s))
	weights = cfg.get("weights", {})


func weight(name: String, dflt: float = 0.0) -> float:
	return float(weights.get(name, dflt))


## `weight` is already class-weighted; it is scaled by distance here. Own-side action beyond earshot feeds `far_heat`.
func add(w: float, dist_m: float, own: bool) -> void:
	var r: float = maxf(radius_m, 1.0)
	heat += w * clampf(1.0 - dist_m / r, min_dist_weight, 1.0)
	if own and dist_m > r:
		far_heat += w * far_weight


## Strategic events: full weight, and the music switches to combat without waiting for the hold.
func add_urgent(w: float) -> void:
	heat += w
	urgent = true


func update(dt: float) -> void:
	var k: float = exp(-dt / maxf(tau_s, 0.01))
	heat *= k
	far_heat *= k
	var raw: float = 1.0 - exp(-heat / maxf(h_ref, 0.01))
	var tc: float = attack_s if raw > intensity else release_s
	intensity += (raw - intensity) * (1.0 - exp(-dt / maxf(tc, 0.01)))


## Level-triggered request: true while the music should be in COMBAT (hysteresis with holds).
func wants_combat(now_ms: int) -> bool:
	if urgent:
		urgent = false
		_combat = true
		_combat_since_ms = now_ms
		_below_since_ms = -1
		return true
	if not _combat:
		if intensity >= combat_on:
			if _above_since_ms < 0:
				_above_since_ms = now_ms
			if now_ms - _above_since_ms >= int(combat_on_hold_s * 1000.0):
				_combat = true
				_combat_since_ms = now_ms
				_below_since_ms = -1
		else:
			_above_since_ms = -1
	else:
		if intensity < combat_off:
			if _below_since_ms < 0:
				_below_since_ms = now_ms
			if now_ms - _below_since_ms >= int(combat_off_hold_s * 1000.0) and now_ms - _combat_since_ms >= int(min_combat_s * 1000.0):
				_combat = false
				_above_since_ms = -1
		else:
			_below_since_ms = -1
	return _combat


func in_combat() -> bool:
	return _combat


func reset() -> void:
	heat = 0.0
	intensity = 0.0
	far_heat = 0.0
	urgent = false
	_above_since_ms = -1
	_below_since_ms = -1
	_combat_since_ms = -1
	_combat = false
