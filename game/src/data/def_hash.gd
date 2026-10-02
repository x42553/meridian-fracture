class_name DefHash
extends RefCounted
## 32-bit FNV-1a mixing, canonical JSON hash and the reflection-based Def hash (data_hash, lobby handshake;
## data_balance 3.5 / 5.11). All hashes live in `int` (never PackedInt32Array: it wraps at 2^31).

const OFFSET: int = 2166136261  ## 0x811C9DC5
const PRIME: int = 16777619  ## 0x01000193
const _M: int = 0xFFFFFFFF

## Debug counter: mix_variant saw a float (V-DET-01). Diagnostic only, never read by the sim.
static var float_hits: int = 0
static var _shapes: Dictionary = {}


static func mix_byte(h: int, b: int) -> int:
	return ((h ^ (b & 0xFF)) * PRIME) & _M


## LEB128 of z = (|v| << 1) | (v < 0), 7 bits per byte low first, 0x80 = more. Requires |v| < 2^62.
static func mix_int(h: int, v: int) -> int:
	var z: int = (-v << 1) | 1 if v < 0 else (v << 1)
	while z >= 0x80:
		h = mix_byte(h, (z & 0x7F) | 0x80)
		z >>= 7
	return mix_byte(h, z)


## UTF-8 bytes then the 0xFF terminator.
static func mix_str(h: int, s: String) -> int:
	for b: int in s.to_utf8_buffer():
		h = mix_byte(h, b)
	return mix_byte(h, 0xFF)


## Tagged mix: nil 0, true 1, false 2, int 3, float 4 (bug: counted, no arithmetic), String 5, Array 6+size,
## Dictionary 7+size+(key,value) by sorted key, PackedInt32Array 9+size, PackedByteArray 10+size, PackedStringArray 11+size,
## Object 12 (null 0) via hash_def.
static func mix_variant(h: int, v: Variant) -> int:
	var t: int = typeof(v)
	match t:
		TYPE_NIL:
			return mix_byte(h, 0)
		TYPE_BOOL:
			return mix_byte(h, 1 if v else 2)
		TYPE_INT:
			return mix_int(mix_byte(h, 3), v)
		TYPE_FLOAT:
			float_hits += 1
			return mix_byte(h, 4)
		TYPE_STRING, TYPE_STRING_NAME:
			return mix_str(mix_byte(h, 5), str(v))
		TYPE_ARRAY:
			var a: Array = v
			h = mix_int(mix_byte(h, 6), a.size())
			for e: Variant in a:
				h = mix_variant(h, e)
			return h
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = []
			for k: Variant in d.keys():
				keys.append(str(k))
			keys.sort()
			h = mix_int(mix_byte(h, 7), keys.size())
			for ks: String in keys:
				h = mix_str(h, ks)
				h = mix_variant(h, d[ks] if d.has(ks) else null)
			return h
		TYPE_PACKED_INT32_ARRAY:
			var pa: PackedInt32Array = v
			h = mix_int(mix_byte(h, 9), pa.size())
			for x: int in pa:
				h = mix_int(h, x)
			return h
		TYPE_PACKED_BYTE_ARRAY:
			var pb: PackedByteArray = v
			h = mix_int(mix_byte(h, 10), pb.size())
			for x: int in pb:
				h = mix_byte(h, x)
			return h
		TYPE_PACKED_STRING_ARRAY:
			var ps: PackedStringArray = v
			h = mix_int(mix_byte(h, 11), ps.size())
			for s: String in ps:
				h = mix_str(h, s)
			return h
		TYPE_OBJECT:
			if v == null:
				return mix_byte(h, 0)
			return hash_def(mix_byte(h, 12), v as Object)
	return mix_byte(h, 255)


## Names of the hashed script variables of `d`'s script, in get_property_list() order (skips "_", "ui_", "pres_").
static func hashed_props(d: Object) -> PackedStringArray:
	var sc: Object = d.get_script()
	var key: int = sc.get_instance_id() if sc != null else 0
	if _shapes.has(key):
		return _shapes[key]
	var names: PackedStringArray = PackedStringArray()
	for p: Dictionary in d.get_property_list():
		var usage: int = p["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		if n.begins_with("_") or n.begins_with("ui_") or n.begins_with("pres_"):
			continue
		names.append(n)
	_shapes[key] = names
	return names


## Reflection hash: the ordered hashed-property-name list (once per script, folded to one int) then every value.
static func hash_def(h: int, d: Object) -> int:
	if d == null:
		return mix_byte(h, 0)
	var names: PackedStringArray = hashed_props(d)
	var shape: int = OFFSET
	for n: String in names:
		shape = mix_str(shape, n)
	h = mix_int(h, shape)
	for n: String in names:
		h = mix_variant(h, d.get(n))
	return h


## Canonical JSON hash: numbers via DefNumParse (exact milli), dictionary keys sorted, independent of whitespace,
## CRLF and key order. A 1-milli change changes the hash.
static func hash_json(v: Variant) -> int:
	return _mix_json(OFFSET, v)


static func _mix_json(h: int, v: Variant) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return mix_int(mix_byte(h, 3), DefNumParse.milli_raw(v))
	if t == TYPE_ARRAY:
		var a: Array = v
		h = mix_int(mix_byte(h, 6), a.size())
		for e: Variant in a:
			h = _mix_json(h, e)
		return h
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = []
		for k: Variant in d.keys():
			keys.append(str(k))
		keys.sort()
		h = mix_int(mix_byte(h, 7), keys.size())
		for ks: String in keys:
			h = _mix_json(mix_str(h, ks), d[ks] if d.has(ks) else null)
		return h
	return mix_variant(h, v)
