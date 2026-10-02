class_name DefConvert
extends RefCounted
## Integer-only designer-unit -> runtime-unit conversions on milli values (data_balance 5.2.2). Every function here has
## a Python twin in `tools/py/balance_lib/convert.py`; parity is enforced by `tests/golden/convert_vectors.json`.

## Suffix table, longest first: [file suffix, runtime suffix, conversion code].
const _SUFFIXES: Array = [
	["_cells_s", "_upt", 1], ["_deg_s", "_apt", 2], ["_seq_ids", "_idx", 20], ["_cells", "_u", 3], ["_credits", "_cr", 4],
	["_pcts", "_bps", 5], ["_crps", "_mcpt", 6], ["_x100", "_x100", 7], ["_smt", "_mt", 8], ["_pct", "_bp", 9],
	["_deg", "_a", 10], ["_ids", "_idx", 21], ["_tags", "_mask", 22], ["_types", "_mask", 23], ["_groups", "_mask", 24],
	["_hp", "_hp", 11], ["_bp", "_bp", 12], ["_id", "_idx", 25], ["_n", "_n", 13], ["_x", "_x", 14], ["_s", "_t", 15],
]
const _ID_WORDS: Array = [
	["summon", 0], ["unit", 0], ["collector", 0], ["drone", 0], ["structure", 1], ["research", 4], ["power", 5],
	["zone", 7], ["neutral", 8], ["faction", 9], ["roster", 10], ["ability", 13], ["weapon", 2],
]


## Round-half-away-from-zero division, d > 0 (== roundi semantics), integer math only.
static func rdiv(n: int, d: int) -> int:
	if n < 0:
		return -((2 * -n + d) / (2 * d))
	return (2 * n + d) / (2 * d)


## n >= 0, d > 0.
static func ceil_div(n: int, d: int) -> int:
	return (n + d - 1) / d


static func cells_to_units(cells_milli: int) -> int:
	return rdiv(cells_milli * Fp.CELL, 1000)


static func cells_s_to_upt(cps_milli: int) -> int:
	return rdiv(cps_milli * Fp.CELL, 1000 * SimConfig.TPS)


static func seconds_to_ticks(sec_milli: int) -> int:
	return ceil_div(sec_milli * SimConfig.TPS, 1000)


## Reload only: milli-ticks, exact (1 tick = 1000 mt).
static func seconds_to_mt(sec_milli: int) -> int:
	return sec_milli * SimConfig.TPS


static func pct_to_bp(pct_milli: int) -> int:
	return rdiv(pct_milli * 100, 1000)


static func deg_to_angle(deg_milli: int) -> int:
	return rdiv(deg_milli * Fp.TURN, 360000)


## Degrees/second -> angle units per tick, minimum 1 for a positive input.
static func deg_s_to_apt(deg_per_s_milli: int) -> int:
	if deg_per_s_milli <= 0:
		return 0
	return maxi(1, rdiv(deg_per_s_milli * Fp.TURN, 360000 * SimConfig.TPS))


static func crps_to_mcpt(credits_per_s_milli: int) -> int:
	return rdiv(credits_per_s_milli, SimConfig.TPS)


static func pcts_to_bps(pct_per_s_milli: int) -> int:
	return rdiv(pct_per_s_milli * 100, 1000)


## Splits a params key into [stem, file_suffix, runtime_suffix, code]; code 0 = no known suffix.
static func split_suffix(key: String) -> Array:
	for row: Array in _SUFFIXES:
		var suf: String = row[0]
		if key.length() > suf.length() and key.ends_with(suf):
			return [key.substr(0, key.length() - suf.length()), suf, row[1], row[2]]
	return [key, "", "", 0]


## Suffix-driven blob conversion (data_balance 5.10.1). Returns {runtime_key: value} with keys inserted in sorted
## order. `data` may be under construction: only .ids, .tags and .damage are read (null tolerated: ids resolve to -1).
static func convert_params(raw: Dictionary, ctx: String, data: GameData, rep: DefLoadReport) -> Dictionary:
	var keys: Array = raw.keys()
	var out_pairs: Array = []
	for k: Variant in keys:
		var key: String = str(k)
		var rv: Variant = _convert_entry(key, raw[k], ctx, data, rep)
		out_pairs.append([str(rv[0]), rv[1]])
	out_pairs.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	var out: Dictionary = {}
	for pr: Array in out_pairs:
		out[pr[0]] = pr[1]
	return out


static func _convert_entry(key: String, v: Variant, ctx: String, data: GameData, rep: DefLoadReport) -> Array:
	var where: String = "%s.%s" % [ctx, key]
	var sp: Array = split_suffix(key)
	var stem: String = sp[0]
	var code: int = sp[3]
	var t: int = typeof(v)
	if t == TYPE_DICTIONARY:
		return [key, convert_params(v, where, data, rep)]
	if t == TYPE_ARRAY:
		return _convert_array(key, v, where, sp, data, rep)
	if t == TYPE_BOOL:
		return [key, v]
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		var s: String = str(v)
		if code == 25:
			return [stem + "_idx", _lookup_id(stem, s, where, data, rep)]
		if code == 22 or code == 23 or code == 24:
			return [stem + "_mask", _mask_of(code, stem, PackedStringArray([s]), where, data, rep)]
		return [key, s]
	if not DefNumParse.is_number(v):
		if rep != null:
			rep.error("V-SCH-07", where, "unsupported value type %d" % t)
		return [key, 0]
	if code == 0 or code >= 20:
		if rep != null:
			rep.error("V-SCH-07", where, "numeric key without a known unit suffix")
		return [key, 0]
	return [stem + sp[2], _convert_number(code, v, where, rep)]


static func _convert_number(code: int, v: Variant, where: String, rep: DefLoadReport) -> int:
	if code == 9 or code == 5:
		var pm: int = DefNumParse.milli_pct(v, where, rep)
		return pct_to_bp(pm) if code == 9 else pcts_to_bps(pm)
	var m: int = DefNumParse.milli(v, where, rep)
	match code:
		1:
			return cells_s_to_upt(m)
		2:
			return deg_s_to_apt(m)
		3:
			return cells_to_units(m)
		6:
			return crps_to_mcpt(m)
		8:
			return seconds_to_mt(m)
		10:
			return deg_to_angle(m)
		15:
			return seconds_to_ticks(m)
	# integral kinds: _credits, _hp, _n, _x, _x100, _bp
	if m % 1000 != 0:
		if rep != null:
			rep.error("V-SCH-05", where, "expected an integer")
		return 0
	return m / 1000


static func _convert_array(key: String, arr: Array, where: String, sp: Array, data: GameData, rep: DefLoadReport) -> Array:
	var stem: String = sp[0]
	var code: int = sp[3]
	if code == 21 or code == 20:
		var idxs: PackedInt32Array = PackedInt32Array()
		var kind: int = _id_kind(stem)
		for e: Variant in arr:
			idxs.append(_lookup_id_kind(kind, str(e), where, data, rep))
		if code == 21:
			idxs.sort()
		return [stem + "_idx", idxs]
	if code == 22 or code == 23 or code == 24:
		var names: PackedStringArray = PackedStringArray()
		for e: Variant in arr:
			names.append(str(e))
		return [stem + "_mask", _mask_of(code, stem, names, where, data, rep)]
	var out: Array = []
	var new_key: String = key if code == 0 or code >= 20 else stem + str(sp[2])
	for e: Variant in arr:
		var et: int = typeof(e)
		if et == TYPE_DICTIONARY:
			out.append(convert_params(e, where, data, rep))
		elif et == TYPE_ARRAY:
			out.append(_convert_array(key, e, where, sp, data, rep)[1])
		elif DefNumParse.is_number(e) and code > 0 and code < 20:
			out.append(_convert_number(code, e, where, rep))
		else:
			out.append(e)
	return [new_key, out]


static func _id_kind(stem: String) -> int:
	for row: Array in _ID_WORDS:
		if stem.contains(str(row[0])):
			return row[1]
	return -1


static func _lookup_id(stem: String, id: String, where: String, data: GameData, rep: DefLoadReport) -> int:
	return _lookup_id_kind(_id_kind(stem), id, where, data, rep)


static func _lookup_id_kind(kind: int, id: String, where: String, data: GameData, rep: DefLoadReport) -> int:
	if id == "":
		return -1
	if kind < 0:
		if rep != null:
			rep.error("V-SCH-07", where, "cannot infer the def kind of id key for '%s'" % id)
		return -1
	if data == null or data.ids == null:
		return -1
	var i: int = data.ids.index_of(kind, id)
	if i < 0 and rep != null:
		rep.error("V-REF-01", where, "unknown %s id '%s'" % [DefEnums.KIND_NAMES[kind], id])
	return i


static func _mask_of(code: int, stem: String, names: PackedStringArray, where: String, data: GameData, rep: DefLoadReport) -> int:
	var m: int = 0
	for n: String in names:
		var bit: int = 0
		if code == 23:
			var di: int = DefEnums.DAMAGE_NAMES.find(n)
			bit = 0 if di < 0 else (1 << di)
		elif code == 24:
			bit = DefEnums.resist_group_bit(n)
		elif data != null and data.tags != null:
			if stem.contains("structure"):
				bit = data.tags.structure_bit(n)
			elif stem.contains("weapon"):
				bit = data.tags.weapon_bit(n)
			elif stem.contains("projectile"):
				bit = data.tags.projectile_bit(n)
			else:
				bit = data.tags.unit_bit(n)
		if bit == 0 and rep != null:
			rep.error("V-SCH-07", where, "unknown name '%s'" % n)
		m |= bit
	return m
