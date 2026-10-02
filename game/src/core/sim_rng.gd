class_name SimRng
extends RefCounted
## Deterministic xorshift128 with 32-bit lanes (sim_core 3.2.3 / 5.2). Exactly one instance per world
## (`world.rng`); draws happen in a fixed system order (DR-2). Seeded through splitmix-style fmix32 so any
## int64 seed (negative included) yields a well-mixed, never all-zero state.

const _M: int = 0xFFFFFFFF

## Four uint32 lanes (part of the checksum).
var s0: int = 0
var s1: int = 0
var s2: int = 0
var s3: int = 0


func _init(seed_value: int = 1) -> void:
	reseed(seed_value)


## Any int64 seed; the state is never left all-zero.
func reseed(seed_value: int) -> void:
	var lo: int = seed_value & _M
	var hi: int = (seed_value >> 32) & _M
	var st: int = (lo ^ mul32(hi, 0x9E3779B1)) & _M
	st = (st + 0x9E3779B9) & _M
	s0 = _smix(st)
	st = (st + 0x9E3779B9) & _M
	s1 = _smix(st)
	st = (st + 0x9E3779B9) & _M
	s2 = _smix(st)
	st = (st + 0x9E3779B9) & _M
	s3 = _smix(st)
	if (s0 | s1 | s2 | s3) == 0:
		s0 = 1


## Uniform 0 .. 2^32-1.
func next_u32() -> int:
	var t: int = s0 ^ ((s0 << 11) & _M)
	s0 = s1
	s1 = s2
	s2 = s3
	s3 = (s3 ^ (s3 >> 19)) ^ (t ^ (t >> 8))
	return s3


## Uniform [0, n), 1 <= n <= 2^30 (Lemire multiply-shift; bias < n / 2^32).
func next_int(n: int) -> int:
	return (next_u32() * n) >> 32


## Uniform in [lo, hi], both inclusive.
func range_i(lo: int, hi: int) -> int:
	return lo + ((next_u32() * (hi - lo + 1)) >> 32)


## true with probability p / 100 (one draw).
func chance_pct(p: int) -> bool:
	return next_int(100) < p


## true with probability p / 10000 (one draw).
func chance_bp(p: int) -> bool:
	return next_int(10000) < p


## In-place Fisher-Yates, i = n-1 .. 1, j = next_int(i + 1).
func shuffle(a: Array) -> void:
	var i: int = a.size() - 1
	while i >= 1:
		var j: int = next_int(i + 1)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
		i -= 1


## Appends the four lanes to a checksum stream.
func hash_into(buf: PackedInt32Array) -> void:
	buf.append(s0)
	buf.append(s1)
	buf.append(s2)
	buf.append(s3)


## The four lanes (int32-wrapped by PackedInt32Array).
func get_state() -> PackedInt32Array:
	var st: PackedInt32Array = PackedInt32Array()
	hash_into(st)
	return st


## Restores the lanes written by get_state (masks & 0xFFFFFFFF); an all-zero state is repaired to s0 = 1.
func set_state(st: PackedInt32Array) -> void:
	s0 = st[0] & _M
	s1 = st[1] & _M
	s2 = st[2] & _M
	s3 = st[3] & _M
	if (s0 | s1 | s2 | s3) == 0:
		s0 = 1


## (a * c) mod 2^32 for a, c < 2^32 without int64 overflow.
static func mul32(a: int, c: int) -> int:
	return (((((a >> 16) * c) & 0xFFFF) << 16) + (a & 0xFFFF) * c) & _M


## murmur3 fmix32 finaliser.
static func _smix(z: int) -> int:
	z = mul32(z ^ (z >> 16), 0x85EBCA6B)
	z = mul32(z ^ (z >> 13), 0xC2B2AE35)
	return z ^ (z >> 16)
