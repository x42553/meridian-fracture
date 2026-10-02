class_name Checksum
extends RefCounted
## FNV-1a 32-bit primitives, overflow-safe 64-bit folding and an MD5-based fast digest for packed arrays
## (sim_core 3.2.4). The FNV parameters equal data's DefHash (one algorithm across the code base).
##
## Instance use: `var c := Checksum.new(); c.add(v); ...; c.value()`. The statics are stateless helpers.

const FNV_OFFSET: int = 0x811C9DC5
const FNV_PRIME: int = 0x01000193
## First four bytes of MD5("") as a little-endian u32; HashingContext.update() errors on empty input.
const EMPTY_DIGEST: int = 0xD98C1DD4
const _M: int = 0xFFFFFFFF

## Scratch MD5 context; start() resets it on every use, so it carries no state between calls.
static var _md5: HashingContext = HashingContext.new()

## Accumulator state (raw FNV-1a value, not yet finalised).
var h: int = FNV_OFFSET


func reset() -> void:
	h = FNV_OFFSET


## FNV-1a over the 4 little-endian bytes of (v & 0xFFFFFFFF).
func add(v: int) -> void:
	h = mix(h, v)


## Overflow-safe 64-bit value: low 32 bits, then bits 32..63.
func add64(v: int) -> void:
	h = mix64(h, v)


## Mixes the size, then the MD5 digest of the array contents.
func add_packed(a: PackedInt32Array) -> void:
	h = mix(h, a.size())
	h = mix(h, digest32(a))


## Finalised accumulator (murmur3 fmix32), 0..2^32-1.
func value() -> int:
	return finalize(h)


## One FNV-1a word step (4 LE bytes of v & 0xFFFFFFFF); returns the new state.
static func mix(hv: int, v: int) -> int:
	var u: int = v & _M
	hv = ((hv ^ (u & 0xFF)) * FNV_PRIME) & _M
	hv = ((hv ^ ((u >> 8) & 0xFF)) * FNV_PRIME) & _M
	hv = ((hv ^ ((u >> 16) & 0xFF)) * FNV_PRIME) & _M
	return ((hv ^ (u >> 24)) * FNV_PRIME) & _M


## Two word steps: low 32 bits, then bits 32..63 (arithmetic shift, masked), so negative values are fine.
static func mix64(hv: int, v: int) -> int:
	return mix(mix(hv, v & _M), (v >> 32) & _M)


## Classic byte-wise FNV-1a. fnv("foobar") = 0xBF9CF968, fnv("a") = 0xE40C292C.
static func fnv_bytes(b: PackedByteArray, hv: int = FNV_OFFSET) -> int:
	var r: int = hv
	for i: int in b.size():
		r = ((r ^ b[i]) * FNV_PRIME) & _M
	return r


## Byte-wise FNV-1a over the UTF-8 bytes of s.
static func fnv_string(s: String, hv: int = FNV_OFFSET) -> int:
	return fnv_bytes(s.to_utf8_buffer(), hv)


## murmur3 fmix32 avalanche.
static func finalize(hv: int) -> int:
	var z: int = hv & _M
	z = ((z ^ (z >> 16)) * 0x85EBCA6B) & _M
	z = ((z ^ (z >> 13)) * 0xC2B2AE35) & _M
	return z ^ (z >> 16)


## Fast path: MD5 of the little-endian bytes of `a`, first 4 digest bytes as an LE u32. Empty -> EMPTY_DIGEST.
static func digest32(a: PackedInt32Array) -> int:
	if a.is_empty():
		return EMPTY_DIGEST
	return digest32_bytes(a.to_byte_array())


## Same as digest32 for raw bytes.
static func digest32_bytes(a: PackedByteArray) -> int:
	if a.is_empty():
		return EMPTY_DIGEST
	_md5.start(HashingContext.HASH_MD5)
	_md5.update(a)
	var d: PackedByteArray = _md5.finish()
	return d[0] | (d[1] << 8) | (d[2] << 16) | (d[3] << 24)
