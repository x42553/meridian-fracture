class_name NetWriter
extends RefCounted
## Append-only little-endian byte builder for the wire format (docs/spec/net.md 3.9). Integer writers mask
## to their width and never error; every method returns self for chaining.

var _buf: PackedByteArray = PackedByteArray()


func u8(v: int) -> NetWriter:
	_buf.append(v & 0xFF)
	return self


func u16(v: int) -> NetWriter:
	_buf.append(v & 0xFF)
	_buf.append((v >> 8) & 0xFF)
	return self


func u32(v: int) -> NetWriter:
	_buf.append(v & 0xFF)
	_buf.append((v >> 8) & 0xFF)
	_buf.append((v >> 16) & 0xFF)
	_buf.append((v >> 24) & 0xFF)
	return self


func i8(v: int) -> NetWriter:
	return u8(v)


func i16(v: int) -> NetWriter:
	return u16(v)


func i32(v: int) -> NetWriter:
	return u32(v)


## Canonical LEB128 of 0 <= v <= 0xFFFFFFFF (out-of-range values are masked to 32 bits).
func varint(v: int) -> NetWriter:
	var x: int = v & 0xFFFFFFFF
	while x >= 0x80:
		_buf.append((x & 0x7F) | 0x80)
		x >>= 7
	_buf.append(x)
	return self


## int32 -> zigzag -> varint.
func zvarint(v: int) -> NetWriter:
	var s: int = ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000
	return varint(((s << 1) ^ (s >> 31)) & 0xFFFFFFFF)


## u8 length + UTF-8; truncated on a code-point boundary at max_bytes (and never above 255).
func str_(s: String, max_bytes: int) -> NetWriter:
	var b: PackedByteArray = s.to_utf8_buffer()
	var cap: int = clampi(max_bytes, 0, 255)
	var cut: int = b.size()
	if cut > cap:
		cut = cap
		while cut > 0 and (b[cut] & 0xC0) == 0x80:
			cut -= 1
		b = b.slice(0, cut)
	_buf.append(cut)
	_buf.append_array(b)
	return self


## varint length + raw bytes.
func bytes_(b: PackedByteArray) -> NetWriter:
	varint(b.size())
	_buf.append_array(b)
	return self


## Raw bytes, no length prefix.
func raw(b: PackedByteArray) -> NetWriter:
	_buf.append_array(b)
	return self


func size() -> int:
	return _buf.size()


func to_bytes() -> PackedByteArray:
	return _buf.duplicate()
