class_name AiRng
extends RefCounted
## Deterministic xorshift32 PRNG + FNV-1a string hash + murmur3 mix32 (ai.md 3.5, 5.14.3). Independent of SimRng (using
## the sim's RNG would mutate sim state) and of net/ (mix32 is identical to NetProtocol.mix32). All values are masked to
## 32 bits; the state is never 0.

const MASK: int = 0xFFFFFFFF
const FALLBACK_STATE: int = 0x9E3779B9

var _s: int = FALLBACK_STATE


## FNV-1a 32-bit over the UTF-8 bytes of `s`.
static func hash_str(s: String) -> int:
	var h: int = 0x811C9DC5
	for b: int in s.to_utf8_buffer():
		h ^= b
		h = (h * 0x01000193) & MASK
	return h


## murmur3 fmix32, identical to NetProtocol.mix32.
static func mix32(x: int) -> int:
	var h: int = x & MASK
	h ^= h >> 16
	h = (h * 0x85EBCA6B) & MASK
	h ^= h >> 13
	h = (h * 0xC2B2AE35) & MASK
	h ^= h >> 16
	return h


## What net passes to ai_factory: mix32(match_seed ^ ((pid + 1) * 0x9E3779B9)), 32-bit masked.
static func thinker_seed(match_seed: int, pid: int) -> int:
	return mix32((match_seed ^ ((pid + 1) * 0x9E3779B9)) & MASK)


## FNV-1a over a list of ints (state hashing helper).
static func hash_ints(values: PackedInt32Array, seed_h: int = 0x811C9DC5) -> int:
	var h: int = seed_h
	for v: int in values:
		for sh: int in [0, 8, 16, 24]:
			h ^= (v >> sh) & 0xFF
			h = (h * 0x01000193) & MASK
	return h


func seed_from(p_seed: int) -> void:
	_s = p_seed & MASK
	if _s == 0:
		_s = FALLBACK_STATE


func next_u32() -> int:
	var s: int = _s
	s ^= (s << 13) & MASK
	s ^= s >> 17
	s ^= (s << 5) & MASK
	_s = s
	return s


## Inclusive range; lo when hi <= lo.
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)


func chance(pct: int) -> bool:
	return range_i(0, 99) < pct


## Index drawn with probability proportional to the weights; sum == 0 => 0 (no draw).
func pick_weighted(weights: PackedInt32Array) -> int:
	var total: int = 0
	for w: int in weights:
		total += maxi(w, 0)
	if total <= 0:
		return 0
	var r: int = next_u32() % total
	for i: int in weights.size():
		r -= maxi(weights[i], 0)
		if r < 0:
			return i
	return weights.size() - 1


func state() -> int:
	return _s
