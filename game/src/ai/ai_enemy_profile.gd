class_name AiEnemyProfile
extends RefCounted
## Per-enemy observed composition (ai.md 4.2): seen value per AiTypes.Cat bucket (decayed x7/8 every 200 ticks), the
## blended share (observation vs. a roster PRIOR that fades as more value is observed) and a few alert flags. Drives
## counter-tech (AiTech / AiComposition, later tasks).

const NCAT: int = AiTypes.Cat.COUNT
const DECAY_PERIOD: int = 200
const PRIOR_FADE_VALUE: int = 4000  ## observed credits at which the prior weight reaches 0

var seen_value: PackedInt32Array = PackedInt32Array()
var share_q8: PackedInt32Array = PackedInt32Array()
var first_seen_tick: PackedInt32Array = PackedInt32Array()  ## -1 = never seen
var observed_value: int = 0  ## total, for the prior fade
var air_peak: int = 0
var arty_fired_recent: int = 0  ## tick of the last artillery shot seen (0 none)
var camo_seen: bool = false
var sub_seen: bool = false
var sw_known_tick: int = -1  ## tick a superweapon structure was first seen (-1 none)
var prior_q8: PackedInt32Array = PackedInt32Array()  ## roster prior shares (sum 256); empty = flat
var _last_decay: int = 0


func _init() -> void:
	seen_value.resize(NCAT)
	share_q8.resize(NCAT)
	first_seen_tick.resize(NCAT)
	first_seen_tick.fill(-1)
	prior_q8.resize(NCAT)


## Registers a sighting of `paid` credits worth of a unit of category `cat`.
func observe(cat: int, paid: int, tick: int) -> void:
	if cat < 0 or cat >= NCAT:
		return
	seen_value[cat] += paid
	observed_value += paid
	if first_seen_tick[cat] < 0:
		first_seen_tick[cat] = tick
	if cat == AiTypes.Cat.AIR:
		air_peak = maxi(air_peak, seen_value[cat])
	if cat == AiTypes.Cat.SUB:
		sub_seen = true


## x7/8 decay every DECAY_PERIOD ticks; recomputes the shares.
func decay(tick: int) -> void:
	while tick - _last_decay >= DECAY_PERIOD:
		_last_decay += DECAY_PERIOD
		for c: int in NCAT:
			seen_value[c] = seen_value[c] * 7 / 8
	recompute()


func set_prior(shares: PackedInt32Array) -> void:
	for c: int in mini(NCAT, shares.size()):
		prior_q8[c] = shares[c]
	recompute()


## share = blend of the observed distribution and the prior, the prior weight fading linearly with observed_value.
func recompute() -> void:
	var total: int = 0
	for v: int in seen_value:
		total += v
	var prior_w: int = clampi(256 - observed_value * 256 / PRIOR_FADE_VALUE, 0, 256)
	for c: int in NCAT:
		var obs: int = seen_value[c] * 256 / maxi(total, 1) if total > 0 else 0
		var obs_w: int = 256 - prior_w if total > 0 else 0
		var pri_w: int = 256 - obs_w
		share_q8[c] = (obs * obs_w + prior_q8[c] * pri_w) >> 8


func share(cat: int) -> int:
	return share_q8[cat]


func state_hash() -> int:
	return AiRng.hash_ints(seen_value, observed_value)
