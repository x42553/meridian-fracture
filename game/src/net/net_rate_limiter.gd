class_name NetRateLimiter
extends RefCounted
## Token buckets per message class plus a decaying violation score, one instance per remote peer
## (docs/spec/net.md 3.9, 5.12). Bucket arithmetic is integer (micro-tokens) so refill never drifts.

enum Class { INPUT = 0, PONG = 1, CHECK = 2, LOBBY = 3, CHAT = 4, PAUSE = 5, MISC = 6 }

## Per class rate per second / burst (index = Class): INPUT 40/64, PONG 8/16, CHECK 4/8, LOBBY 10/20, CHAT 1/5 (5 per 5 s), PAUSE 1/2, MISC 5/10.
const RATE_PER_S: PackedInt32Array = [40, 8, 4, 10, 1, 1, 5]
const BURST: PackedInt32Array = [64, 16, 8, 20, 5, 2, 10]
const _MICRO: int = 1_000_000

# per class: current tokens in micro-tokens, and the time of the last refill
var _tokens: PackedInt64Array = PackedInt64Array()
var _stamp: PackedInt64Array = PackedInt64Array()
var _violation: float = 0.0
var _violation_at_us: int = -1


func _init() -> void:
	_tokens.resize(BURST.size())
	_stamp.resize(BURST.size())
	for i in BURST.size():
		_tokens[i] = BURST[i] * _MICRO
		_stamp[i] = -1


## Takes one token of class `cls` at time `now_us`; false when the bucket is empty (message should be dropped and scored).
func allow(cls: int, now_us: int) -> bool:
	var c: int = cls if cls >= 0 and cls < BURST.size() else Class.MISC
	var rate: int = RATE_PER_S[c]
	var cap: int = BURST[c] * _MICRO
	if _stamp[c] >= 0 and now_us > _stamp[c]:
		_tokens[c] = mini(cap, _tokens[c] + (now_us - _stamp[c]) * rate)
	_stamp[c] = maxi(_stamp[c], now_us)
	if _tokens[c] >= _MICRO:
		_tokens[c] -= _MICRO
		return true
	return false


## Adds `weight` to the violation score (after decaying it by 1 point per VIOLATION_DECAY_MS) and returns the new score.
func add_violation(weight: float, now_us: int) -> float:
	_decay(now_us)
	_violation += weight
	return _violation


## Current decayed score.
func score(now_us: int) -> float:
	_decay(now_us)
	return _violation


func _decay(now_us: int) -> void:
	if _violation_at_us >= 0 and now_us > _violation_at_us:
		var dec: float = float(now_us - _violation_at_us) / float(NetProtocol.VIOLATION_DECAY_MS * 1000)
		_violation = maxf(0.0, _violation - dec)
	_violation_at_us = maxi(_violation_at_us, now_us)


func reset() -> void:
	_init()
	_violation = 0.0
	_violation_at_us = -1
