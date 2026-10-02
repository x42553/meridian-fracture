class_name DefTags
extends RefCounted
## Per-namespace tag registries (unit, structure, weapon, projectile): bible tags have the fixed bits of DefEnums,
## balance extras take the next free bits in sorted-name order (data_balance 4.1 / 5.4.1).

var _names: Array = []  ## per namespace 0..3: PackedStringArray, index == bit
var _bits: Array = []  ## per namespace: Dictionary name -> bit


func _init() -> void:
	var fixed: Array = [DefEnums.UNIT_TAG_NAMES, DefEnums.STRUCT_TAG_NAMES, DefEnums.WEAPON_TAG_NAMES, DefEnums.WEAPON_TAG_NAMES]
	for ns: int in 4:
		var names: PackedStringArray = (fixed[ns] as PackedStringArray).duplicate()
		var m: Dictionary = {}
		for i: int in names.size():
			m[names[i]] = i
		_names.append(names)
		_bits.append(m)


## Adds free tags of a namespace (0 unit, 1 structure, 2 weapon, 3 projectile) in sorted-name order; returns
## false (and reports V-SCH-08) when the 62-bit budget is exceeded. Locked tags are never accepted (V-CNF-03).
func add_extras(ns: int, names: PackedStringArray, rep: DefLoadReport, where: String) -> bool:
	var sorted_names: PackedStringArray = names.duplicate()
	sorted_names.sort()
	var ok: bool = true
	for n: String in sorted_names:
		var m: Dictionary = _bits[ns]
		if DefEnums.LOCKED_TAGS.has(n):
			rep.error("V-CNF-03", where, "tag '%s' is locked and cannot be added" % n)
			ok = false
			continue
		if m.has(n):
			continue
		var arr: PackedStringArray = _names[ns]
		if arr.size() >= DefEnums.MAX_TAG_BITS:
			rep.error("V-SCH-08", where, "more than %d tags in one namespace" % DefEnums.MAX_TAG_BITS)
			return false
		m[n] = arr.size()
		arr.append(n)
		_names[ns] = arr
	return ok


func _bit(ns: int, name: String) -> int:
	var m: Dictionary = _bits[ns]
	if not m.has(name):
		return 0
	var b: int = m[name]
	return 1 << b


func _mask(ns: int, names: PackedStringArray) -> int:
	var r: int = 0
	for n: String in names:
		r |= _bit(ns, n)
	return r


func _list(ns: int, mask: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var arr: PackedStringArray = _names[ns]
	for i: int in arr.size():
		if (mask >> i) & 1 == 1:
			out.append(arr[i])
	return out


func unit_bit(name: String) -> int:
	return _bit(0, name)


func unit_mask(names: PackedStringArray) -> int:
	return _mask(0, names)


func unit_names(mask: int) -> PackedStringArray:
	return _list(0, mask)


func structure_bit(name: String) -> int:
	return _bit(1, name)


func structure_mask(names: PackedStringArray) -> int:
	return _mask(1, names)


func structure_names(mask: int) -> PackedStringArray:
	return _list(1, mask)


func weapon_bit(name: String) -> int:
	return _bit(2, name)


func weapon_mask(names: PackedStringArray) -> int:
	return _mask(2, names)


func weapon_names(mask: int) -> PackedStringArray:
	return _list(2, mask)


func projectile_bit(name: String) -> int:
	return _bit(3, name)


func projectile_mask(names: PackedStringArray) -> int:
	return _mask(3, names)


func projectile_names(mask: int) -> PackedStringArray:
	return _list(3, mask)


func unit_extra_first_bit() -> int:
	return DefEnums.UNIT_TAG_EXTRA_FIRST


func structure_extra_first_bit() -> int:
	return DefEnums.STRUCT_TAG_EXTRA_FIRST


## Hash of all registries (names in bit order).
func hash_all() -> int:
	var h: int = DefHash.OFFSET
	for ns: int in 4:
		h = DefHash.mix_int(h, ns)
		for n: String in _names[ns]:
			h = DefHash.mix_str(h, n)
	return h
