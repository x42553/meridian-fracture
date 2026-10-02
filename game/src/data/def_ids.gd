class_name DefIds
extends RefCounted
## Sorted-id -> dense index registry per kind (data_balance 5.3). Ids of a kind are sorted by code point (GDScript
## Array[String].sort()), duplicates and malformed ids are errors, and the position is the dense index. Frozen
## enumerations (weapon archetypes) use `assign_frozen`, which keeps the given order.

var _ids: Array = []  ## per Kind: PackedStringArray
var _map: Array = []  ## per Kind: Dictionary id -> index


func _init() -> void:
	for k: int in DefEnums.Kind.COUNT:
		_ids.append(PackedStringArray())
		_map.append({})


## True when `id` matches ^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$ .
static func valid_id(id: String) -> bool:
	if id.length() < 3 or id.unicode_at(0) < 97 or id.unicode_at(0) > 122:
		return false
	var dots: int = 0
	var prev_dot: bool = false
	for i: int in id.length():
		var c: int = id.unicode_at(i)
		if c == 46:
			if prev_dot or i == id.length() - 1:
				return false
			dots += 1
			prev_dot = true
			continue
		prev_dot = false
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return dots >= 1


## Sorts, rejects duplicates and bad ids/prefixes (V-SCH-03) and builds the maps of `kind`.
func assign(kind: int, id_list: PackedStringArray, rep: DefLoadReport) -> void:
	var sorted_ids: PackedStringArray = id_list.duplicate()
	sorted_ids.sort()
	_store(kind, sorted_ids, rep)


## Adds ids to a kind that already holds some (domain compilers in P3): re-sorts the union, so existing indices of
## the kind may shift; call before any def is built.
func extend(kind: int, more: PackedStringArray, rep: DefLoadReport) -> void:
	var all: PackedStringArray = _ids[kind].duplicate()
	all.append_array(more)
	assign(kind, all, rep)


## Like assign but keeps the order given (frozen enumerations).
func assign_frozen(kind: int, id_list: PackedStringArray, rep: DefLoadReport) -> void:
	_store(kind, id_list, rep)


func _store(kind: int, id_list: PackedStringArray, rep: DefLoadReport) -> void:
	var out: PackedStringArray = PackedStringArray()
	var m: Dictionary = {}
	var prefix: String = DefEnums.KIND_PREFIX[kind]
	for id: String in id_list:
		if not valid_id(id):
			rep.error("V-SCH-03", id, "malformed id (expected ^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$)")
			continue
		var pref_ok: bool = prefix == "" or id.begins_with(prefix)
		if kind == DefEnums.Kind.UNIT and id.begins_with("summon."):
			pref_ok = true
		if not pref_ok:
			rep.error("V-SCH-03", id, "id prefix does not match kind '%s' (expected '%s')" % [DefEnums.KIND_NAMES[kind], prefix])
			continue
		if m.has(id):
			rep.error("V-SCH-03", id, "duplicate %s id" % DefEnums.KIND_NAMES[kind])
			continue
		m[id] = out.size()
		out.append(id)
	_ids[kind] = out
	_map[kind] = m


func index_of(kind: int, id: String) -> int:
	if kind < 0 or kind >= _map.size():
		return -1
	var m: Dictionary = _map[kind]
	return m.get(id, -1)


func id_of(kind: int, index: int) -> String:
	if kind < 0 or kind >= _ids.size():
		return ""
	var a: PackedStringArray = _ids[kind]
	return a[index] if index >= 0 and index < a.size() else ""


func ids(kind: int) -> PackedStringArray:
	return _ids[kind]


func count(kind: int) -> int:
	return (_ids[kind] as PackedStringArray).size()


## Hash of all ids in Kind order (table "ids", data_balance 5.11).
func hash_all() -> int:
	var h: int = DefHash.OFFSET
	for k: int in DefEnums.Kind.COUNT:
		h = DefHash.mix_str(h, DefEnums.KIND_NAMES[k])
		for id: String in _ids[k]:
			h = DefHash.mix_str(h, id)
	return h
