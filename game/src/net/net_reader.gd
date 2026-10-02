class_name NetReader
extends RefCounted
## Bounds-checked cursor over a PackedByteArray (docs/spec/net.md 3.9, 4.3). Every accessor checks bounds; on
## overrun or a malformed field `ok` becomes false (sticky), the cursor moves to the end and 0 / "" / empty
## is returned. Never calls the engine out of range, so it never raises an engine error on hostile input.

## Sticky: false after ANY overrun or malformed field.
var ok: bool = true
var _b: PackedByteArray
var _p: int = 0
var _end: int = 0


func _init(buf: PackedByteArray, start: int = 0, end: int = -1) -> void:
	_b = buf
	_end = buf.size() if end < 0 or end > buf.size() else end
	_p = clampi(start, 0, _end)


func left() -> int:
	return _end - _p


func pos() -> int:
	return _p


## True when nothing failed and every byte was consumed (the decoder's success test).
func done() -> bool:
	return ok and _p == _end


func _fail() -> void:
	ok = false
	_p = _end


func u8() -> int:
	if _p + 1 > _end:
		_fail()
		return 0
	var v: int = _b[_p]
	_p += 1
	return v


func u16() -> int:
	if _p + 2 > _end:
		_fail()
		return 0
	var v: int = _b[_p] | (_b[_p + 1] << 8)
	_p += 2
	return v


func u32() -> int:
	if _p + 4 > _end:
		_fail()
		return 0
	var v: int = _b[_p] | (_b[_p + 1] << 8) | (_b[_p + 2] << 16) | (_b[_p + 3] << 24)
	_p += 4
	return v


func i8() -> int:
	var v: int = u8()
	return v - 256 if v >= 128 else v


func i16() -> int:
	var v: int = u16()
	return v - 65536 if v >= 32768 else v


func i32() -> int:
	var v: int = u32()
	return v - 0x100000000 if v >= 0x80000000 else v


## Canonical LEB128 only: overlong forms, more than 5 bytes or values above 0xFFFFFFFF set ok = false.
func varint() -> int:
	var result: int = 0
	var shift: int = 0
	for i in 5:
		if _p >= _end:
			_fail()
			return 0
		var b: int = _b[_p]
		_p += 1
		if i == 4 and b > 0x0F:
			_fail()
			return 0
		result |= (b & 0x7F) << shift
		if b < 0x80:
			if b == 0 and i > 0:
				_fail()
				return 0
			return result
		shift += 7
	_fail()
	return 0


func zvarint() -> int:
	var v: int = varint()
	return (v >> 1) ^ -(v & 1)


## u8 length + UTF-8 validated with NetProtocol.is_valid_utf8 BEFORE the engine decoder runs.
func str_(max_bytes: int) -> String:
	var n: int = u8()
	if not ok:
		return ""
	if n > max_bytes or _p + n > _end:
		_fail()
		return ""
	if n == 0:
		return ""
	if not NetProtocol.is_valid_utf8(_b, _p, n):
		_fail()
		return ""
	var s: String = _b.slice(_p, _p + n).get_string_from_utf8()
	_p += n
	return s


## varint length + raw bytes (length above max_len or the remaining bytes => ok = false).
func bytes_(max_len: int) -> PackedByteArray:
	var n: int = varint()
	if not ok:
		return PackedByteArray()
	if n > max_len or _p + n > _end:
		_fail()
		return PackedByteArray()
	return raw(n)


## n raw bytes.
func raw(n: int) -> PackedByteArray:
	if n < 0 or _p + n > _end:
		_fail()
		return PackedByteArray()
	var out: PackedByteArray = _b.slice(_p, _p + n)
	_p += n
	return out
