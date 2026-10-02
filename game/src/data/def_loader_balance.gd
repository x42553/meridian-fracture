class_name DefLoaderBalance
extends RefCounted
## P4 of the loader (data_balance 5.1 / 7.6 / 7.7 / 7.8): unit sheets, weapon instances, summons and drones,
## structure numbers (`global.json` structures / defenses + `structures.json` overlay), ability instantiation from the
## registry (`ability_kinds.json`) and the derived per-def caches. Called by DefLoader as the hook
## `def_loader_balance.build(src, data, rep)`; also home of the registry-typed parameter conversion that the effects
## loader reuses (`make_ability`, `convert_typed`, `convert_blob`).
##
## The vocabulary (P2: damage / move / body tables, 27 weapon archetypes, economy) is built by the DefDamageTable /
## DefMoveTable / DefBodyTable / DefWeaponArch / DefEconomy `from_global` functions that DefLoader calls, so there is no
## separate vocabulary file (DATA-04 `def_loader_vocab.gd` is folded into those classes).

const _TYPE_SUFFIX: Dictionary = {
	"cells": ["_cells", "_u"], "cells_s": ["_cells_s", "_upt"], "s": ["_s", "_t"], "smt": ["_smt", "_mt"],
	"n": ["_n", "_n"], "x": ["_x", "_x"], "pct": ["_pct", "_bp"], "pcts": ["_pct_per_s", "_bps"],
	"deg": ["_deg", "_a"], "deg_s": ["_deg_s", "_apt"], "credits": ["_credits", "_cr"], "hp": ["_hp", "_hp"],
	"bp": ["_bp", "_bp"], "crps": ["_crps", "_mcpt"], "x100": ["_x100", "_x100"],
}
const _LOCKED_WEAPON_KEYS: PackedStringArray = [
	"damage_type", "fire_mode", "projectile_kind", "interceptable", "interceptable_by", "homing", "proj_speed",
	"projectile_speed_cells_s",
]
const _WEAPON_FLAGS: Dictionary = {
	"stationary_fire": DefEnums.WF_STATIONARY_FIRE, "needs_los": DefEnums.WF_NEEDS_LOS,
	"point_defense": DefEnums.WF_POINT_DEFENSE,
}
const _STRUCT_FLAGS: Dictionary = {
	"powered_defense": DefEnums.SF_POWERED_DEFENSE, "sellable": DefEnums.SF_SELLABLE, "repairable": DefEnums.SF_REPAIRABLE,
	"capture_immune": DefEnums.SF_CAPTURE_IMMUNE, "relay": DefEnums.SF_RELAY, "production": DefEnums.SF_PRODUCTION,
}
const _SUMMON_FACTION_PREFIX: String = "faction."
const _ID_KIND_OF_TYPE: Dictionary = {
	"unit_id": DefEnums.Kind.UNIT, "summon_id": DefEnums.Kind.UNIT, "structure_id": DefEnums.Kind.STRUCTURE,
	"zone_id": DefEnums.Kind.ZONE, "unit_ids": DefEnums.Kind.UNIT, "structure_ids": DefEnums.Kind.STRUCTURE,
}


## Shared per-load context.
class Ctx:
	extends RefCounted
	var src: DefSources
	var data: GameData
	var rep: DefLoadReport
	var g: Dictionary = {}
	var kinds: DefAbilityKinds
	var weapons: Dictionary = {}  ## weapon instance id -> raw dict
	var weapon_file: Dictionary = {}  ## id -> file (messages)
	var built: Dictionary = {}  ## unit id -> true (sheet seen)


# ================================================================================================ entry
static func build(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var c: Ctx = Ctx.new()
	c.src = src
	c.data = data
	c.rep = rep
	c.g = src.balance.get("global.json", {})
	if not src.balance.has("ability_kinds.json"):
		rep.error("V-SCH-01", "ability_kinds.json", "ability registry is missing: unit abilities cannot be built")
		return
	check_shapes(src, rep)
	if not rep.is_ok():
		return
	register_inline_zone_ids(src, data, rep)
	data.stack_groups = collect_stack_groups(src)
	c.kinds = DefAbilityKinds.from_json(src.balance["ability_kinds.json"], rep)
	_build_templates(c)
	_collect_weapons(c)
	for f: String in src.manifest_files:
		if f.begins_with("units_") and src.balance.has(f):
			_build_sheet(c, f)
	for u: DefUnit in data.units:
		if u.id.begins_with("unit.") and not c.built.has(u.id):
			rep.error("V-CMP-01", "units_*.json", "bible unit '%s' has no entry in any unit sheet" % u.id)
	for u: DefUnit in data.units:
		derive_unit(data, u)
	_build_structures(c)


# ============================================================================================ shape guard
const _T_ARR: int = TYPE_ARRAY
const _T_DICT: int = TYPE_DICTIONARY
const _UNIT_FIELDS: Dictionary = {
	"weapons": TYPE_ARRAY, "abilities": TYPE_ARRAY, "ability_params": TYPE_DICTIONARY, "pres": TYPE_DICTIONARY,
	"flags": TYPE_ARRAY, "tags_add": TYPE_ARRAY, "params": TYPE_DICTIONARY, "modes": TYPE_ARRAY, "unit_tags": TYPE_ARRAY,
	"tags": TYPE_ARRAY,
}
const _STRUCT_FIELDS: Dictionary = {
	"abilities": TYPE_ARRAY, "ability_params": TYPE_DICTIONARY, "flags": TYPE_ARRAY, "footprint_mask": TYPE_ARRAY,
	"exit": TYPE_DICTIONARY, "params": TYPE_DICTIONARY, "tags_add": TYPE_ARRAY, "pres": TYPE_DICTIONARY,
}
const _EFFECT_FIELDS: Dictionary = {"cond": TYPE_ARRAY, "groups": TYPE_ARRAY, "fire_modes": TYPE_ARRAY, "filter": TYPE_DICTIONARY}
const _ZONE_FIELDS: Dictionary = {"effects": TYPE_ARRAY, "params": TYPE_DICTIONARY, "targets": TYPE_ARRAY, "pres": TYPE_DICTIONARY}
const _GLOBAL_DICTS: PackedStringArray = [
	"archetypes", "unit_assignments", "service_units", "structures", "defenses", "movement_defaults", "economy",
	"superweapons", "support_power_damage", "carriers", "weapon_archetypes",
]


## Structural type check of every balance file the loaders walk (V-SCH-03): a wrong or null container / element type
## is reported here once, so the loaders never index into the wrong kind of value. Deeper value errors are reported by
## the converters (V-SCH-04..07) and references (V-REF-01). Runs in P1 (DefLoader.build) before any file is read.
static func check_shapes(src: DefSources, rep: DefLoadReport) -> void:
	for f: String in src.manifest_files:
		if not src.balance.has(f):
			continue
		var d: Dictionary = src.balance[f]
		if f == "global.json":
			_global_shape(d, rep)
		elif f.begins_with("units_"):
			for key: String in ["units", "weapons", "summons"]:
				for e: Dictionary in _dicts(d.get(key, []), f, key, rep):
					var w: String = f + " " + str(e.get("id", key))
					_fields(e, w, _UNIT_FIELDS, rep)
					_each_dict(e.get("ability_params"), w, "ability_params", rep)
		elif f == "structures.json":
			for e2: Dictionary in _dicts(d.get("structures", []), f, "structures", rep):
				_fields(e2, f + " " + str(e2.get("id", "")), _STRUCT_FIELDS, rep)
				_each_dict(e2.get("ability_params"), f, "ability_params", rep)
		elif f == "ability_kinds.json":
			_fields(d, f, {"kinds": _T_DICT, "templates": _T_DICT, "aliases": _T_DICT, "implicit": _T_ARR, "def_params": _T_DICT}, rep)
			for kn: Variant in _dict_map(d.get("kinds", {}), f, "kinds", rep).keys():
				var kd: Dictionary = d["kinds"][kn]
				_fields(kd, f + " kinds." + str(kn), {"params": _T_DICT, "scopes": _T_ARR}, rep)
				if not DefNumParse.is_number(kd.get("id")):
					rep.error("V-SCH-03", f + " kinds." + str(kn), "'id' must be a number")
				_each_dict(kd.get("params"), f + " kinds." + str(kn), "params", rep)
				if kd.get("params") is Dictionary:
					for pn: Variant in (kd["params"] as Dictionary).keys():
						var ps: Variant = kd["params"][pn]
						if ps is Dictionary:
							_fields(ps, f + " kinds." + str(kn) + "." + str(pn), {"items": _T_DICT, "type": TYPE_STRING}, rep)
							_each_dict((ps as Dictionary).get("items"), f + " kinds." + str(kn), "items", rep)
			for tn: Variant in _dict_map(d.get("templates", {}), f, "templates", rep).keys():
				_fields(d["templates"][tn], f + " templates." + str(tn), {"params": _T_DICT}, rep)
			_dict_map(d.get("def_params", {}), f, "def_params", rep)
			for row: Dictionary in _dicts(d.get("implicit", []), f, "implicit", rep):
				_fields(row, f + " implicit", {"templates": _T_ARR, "when": TYPE_STRING}, rep)
		elif f == "research_effects.json":
			var doc: Dictionary = _dict_map(d.get("research", {}), f, "research", rep)
			for id: Variant in doc.keys():
				var e3: Dictionary = d["research"][id]
				_fields(e3, f + " " + str(id), {"effects": _T_ARR}, rep)
				_effects_shape(e3.get("effects", []), f + " " + str(id), rep)
			_dict_map(d.get("selectors", {}), f, "selectors", rep)
		elif f == "power_actions.json":
			var pdoc: Dictionary = _dict_map(d.get("powers", {}), f, "powers", rep)
			for id2: Variant in pdoc.keys():
				var pw: Dictionary = d["powers"][id2]
				var pwhere: String = f + " " + str(id2)
				_fields(pw, pwhere, {"target": _T_DICT, "actions": _T_ARR}, rep)
				if pw.get("target") is Dictionary:
					_fields(pw["target"], pwhere + " target", {"structure_ids": _T_ARR}, rep)
				for a: Dictionary in _dicts(pw.get("actions", []), pwhere, "actions", rep):
					_fields(a, pwhere, {"inline": _T_DICT, "effects": _T_ARR, "then_strike": _T_DICT, "params": _T_DICT}, rep)
					_effects_shape(a.get("effects", []), pwhere, rep)
					if a.get("inline") is Dictionary:
						_fields(a["inline"], pwhere + " inline", _ZONE_FIELDS, rep)
						_effects_shape((a["inline"] as Dictionary).get("effects", []), pwhere, rep)
		elif f == "zone_templates.json":
			var zdoc: Dictionary = _dict_map(d.get("zones", {}), f, "zones", rep)
			for id3: Variant in zdoc.keys():
				var z: Dictionary = d["zones"][id3]
				_fields(z, f + " " + str(id3), _ZONE_FIELDS, rep)
				_effects_shape(z.get("effects", []), f + " " + str(id3), rep)
		elif f == "faction_traits.json":
			var fdoc: Dictionary = _dict_map(d.get("factions", {}), f, "factions", rep)
			for id4: Variant in fdoc.keys():
				var fd: Dictionary = d["factions"][id4]
				_fields(fd, f + " " + str(id4), {"traits": _T_DICT, "player_params": _T_DICT, "pres": _T_DICT}, rep)
				var tdoc: Dictionary = _dict_map(fd.get("traits", {}), f, "traits", rep)
				for tid: Variant in tdoc.keys():
					_fields(fd["traits"][tid], f + " " + str(tid), {"covers": _T_ARR, "encoded_in": _T_DICT}, rep)
					if fd["traits"][tid].get("encoded_in") is Dictionary:
						_fields(fd["traits"][tid]["encoded_in"], f + " " + str(tid), {"modifier_ids": _T_ARR, "unit_ids": _T_ARR}, rep)
					var tab: Variant = fd["traits"][tid].get("ability")
					if tab is Dictionary:
						_fields(tab, f + " " + str(tid) + " ability", {"params": _T_DICT}, rep)
		elif f == "neutral_structures.json":
			var ndoc: Dictionary = _dict_map(d.get("neutrals", {}), f, "neutrals", rep)
			for id5: Variant in ndoc.keys():
				_fields(d["neutrals"][id5], f + " " + str(id5), {"footprint": _T_DICT, "reward": _T_DICT, "ability": _T_DICT, "berth": _T_ARR, "pres": _T_DICT}, rep)
				if d["neutrals"][id5].get("ability") is Dictionary:
					_fields(d["neutrals"][id5]["ability"], f + " " + str(id5), {"params": _T_DICT}, rep)


static func _global_shape(g: Dictionary, rep: DefLoadReport) -> void:
	for k: String in _GLOBAL_DICTS:
		if g.has(k) and not (g[k] is Dictionary):
			rep.error("V-SCH-03", "global.json", "'%s' must be an object" % k)
	if not rep.is_ok():
		return
	for name: Variant in (g.get("archetypes", {}) as Dictionary).keys():
		var a: Variant = g["archetypes"][name]
		if not (a is Dictionary):
			rep.error("V-SCH-03", "global.json", "archetype '%s' must be an object" % str(name))
		else:
			_fields(a, "global.json archetypes." + str(name), {"weapons": _T_ARR, "drone_weapon": _T_DICT}, rep)
			for w: Dictionary in _dicts((a as Dictionary).get("weapons", []), "global.json archetypes." + str(name), "weapons", rep):
				_fields(w, "global.json archetypes." + str(name), {"flags": _T_ARR, "modes": _T_ARR}, rep)
	_dict_map(g.get("unit_assignments", {}), "global.json", "unit_assignments", rep)
	_dict_map(g.get("service_units", {}), "global.json", "service_units", rep)
	_dict_map(g.get("structures", {}), "global.json", "structures", rep)
	_dict_map(g.get("superweapons", {}), "global.json", "superweapons", rep)
	_dict_map(g.get("support_power_damage", {}), "global.json", "support_power_damage", rep)
	for k2: String in ["shared", "advanced"]:
		var def_d: Variant = (g.get("defenses", {}) as Dictionary).get(k2)
		if def_d != null and not (def_d is Dictionary):
			rep.error("V-SCH-03", "global.json", "defenses.%s must be an object" % k2)
	var eco: Variant = (g.get("economy", {}) as Dictionary).get("collector")
	if eco != null and not (eco is Dictionary):
		rep.error("V-SCH-03", "global.json", "economy.collector must be an object")


static func _each_dict(v: Variant, where: String, key: String, rep: DefLoadReport) -> void:
	if v is Dictionary:
		for k: Variant in (v as Dictionary).keys():
			if not ((v as Dictionary)[k] is Dictionary):
				rep.error("V-SCH-03", where, "'%s.%s' must be an object" % [key, str(k)])


## A JSON boolean, else `dflt` (never a script error on junk values; the schema validators report those).
static func truthy(v: Variant, dflt: bool = false) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	return dflt


static func _effects_shape(list: Variant, where: String, rep: DefLoadReport) -> void:
	for e: Dictionary in _dicts(list, where, "effects", rep):
		_fields(e, where, _EFFECT_FIELDS, rep)
		if e.get("ability") is Dictionary:
			_fields(e["ability"], where + " ability", {"params": _T_DICT}, rep)
		if e.get("selector") != null and not (e["selector"] is String or e["selector"] is Array or e["selector"] is Dictionary):
			rep.error("V-SCH-03", where, "selector must be an id, an array or an object")
		for c: Variant in e.get("cond", []) if e.get("cond") is Array else []:
			if not (c is Dictionary):
				rep.error("V-SCH-03", where, "every cond entry must be an object")


static func _dicts(v: Variant, file: String, key: String, rep: DefLoadReport) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (v is Array):
		rep.error("V-SCH-03", file, "'%s' must be an array" % key)
		return out
	for e: Variant in v:
		if e is Dictionary:
			out.append(e)
		else:
			rep.error("V-SCH-03", file, "every entry of '%s' must be an object" % key)
	return out


static func _dict_map(v: Variant, file: String, key: String, rep: DefLoadReport) -> Dictionary:
	var out: Dictionary = {}
	if not (v is Dictionary):
		rep.error("V-SCH-03", file, "'%s' must be an object" % key)
		return out
	for k: Variant in (v as Dictionary).keys():
		if (v as Dictionary)[k] is Dictionary:
			out[k] = true
		else:
			rep.error("V-SCH-03", file, "entry '%s' of '%s' must be an object" % [str(k), key])
	return out


## Reports every key of `types` that is present with another Variant type (a JSON null counts as the wrong type).
static func _fields(d: Dictionary, where: String, types: Dictionary, rep: DefLoadReport) -> void:
	for k: Variant in types.keys():
		if d.has(k) and typeof(d[k]) != int(types[k]):
			rep.error("V-SCH-03", where, "'%s' has the wrong type (expected %s)" % [str(k), type_string(int(types[k]))])


## `zone.<power id without "power.">` ids of the inline zones of power_actions.json, added to the ZONE id space before
## any def is built (indices of zones may still shift here).
static func register_inline_zone_ids(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	if not src.balance.has("power_actions.json"):
		return
	var powers: Dictionary = src.balance["power_actions.json"].get("powers", {})
	var extra: PackedStringArray = PackedStringArray()
	var keys: Array = powers.keys()
	keys.sort()
	for pid: Variant in keys:
		var n: int = 0
		for act: Variant in (powers[pid] as Dictionary).get("actions", []):
			if (act as Dictionary).has("inline"):
				extra.append(inline_zone_id(str(pid), n))
				n += 1
	if not extra.is_empty():
		data.ids.extend(DefEnums.Kind.ZONE, extra, rep)


static func inline_zone_id(power_id: String, n: int) -> String:
	var base: String = "zone." + power_id.trim_prefix("power.")
	return base if n == 0 else "%s_%d" % [base, n + 1]


## Sorted unique names of every `stack_group` string found anywhere in the balance files (effects, abilities, traits).
static func collect_stack_groups(src: DefSources) -> PackedStringArray:
	var found: Dictionary = {}
	for f: String in src.manifest_files:
		if src.balance.has(f) and f != "global.json":
			_scan_groups(src.balance[f], found)
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in found.keys():
		out.append(str(k))
	out.sort()
	return out


static func _scan_groups(v: Variant, found: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d.keys():
			if str(k) == "stack_group" and d[k] is String:
				found[str(d[k])] = true
			else:
				_scan_groups(d[k], found)
	elif v is Array:
		for e: Variant in v:
			_scan_groups(e, found)


# ============================================================================================== abilities
static func _build_templates(c: Ctx) -> void:
	c.data.abilities.clear()
	for tid: String in c.kinds.template_ids:
		var t: Dictionary = c.kinds.templates[tid]
		var scratch: DefLoadReport = DefLoadReport.new()
		var a: DefAbility = make_ability(c.kinds, str(t.get("kind", "")), t.get("params", {}), -1, "ability_kinds.json " + tid, c.data, scratch, false)
		a.id = tid
		a.index = c.data.abilities.size()
		c.rep.merge(_only_errors(scratch))
		c.data.abilities.append(a)


static func _only_errors(r: DefLoadReport) -> DefLoadReport:
	var o: DefLoadReport = DefLoadReport.new()
	o.errors = r.errors
	return o


## One ability instance of `kind_name`: registry defaults < `file_params` (file units), validated against the kind
## spec (unknown key / missing required key = V-ABL-01), converted by REGISTRY TYPE (`rate_pct_per_s` is `pcts`).
static func make_ability(kinds: DefAbilityKinds, kind_name: String, file_params: Dictionary, template_idx: int, ctx: String, data: GameData, rep: DefLoadReport, check_required: bool) -> DefAbility:
	var a: DefAbility = DefAbility.new()
	if not kinds.kinds.has(kind_name):
		rep.error("V-ABL-01", ctx, "unknown ability kind '%s'" % kind_name)
		return a
	var spec: Dictionary = (kinds.kinds[kind_name] as Dictionary).get("params", {})
	var merged: Dictionary = {}
	for k: Variant in spec.keys():
		var ps: Dictionary = spec[k]
		if ps.has("def"):
			merged[k] = ps["def"]
	for k: Variant in file_params.keys():
		if not spec.has(k):
			rep.error("V-ABL-01", ctx, "ability kind '%s': unknown param '%s'" % [kind_name, str(k)])
			continue
		merged[k] = file_params[k]
	if check_required:
		for k: Variant in spec.keys():
			if truthy((spec[k] as Dictionary).get("req")) and not merged.has(k):
				rep.error("V-ABL-01", ctx, "ability kind '%s': required param '%s' is missing" % [kind_name, str(k)])
	a.kind = kinds.kind_id(kind_name)
	a.template = template_idx
	var pairs: Array = []
	for k: Variant in merged.keys():
		var pair: Array = convert_typed(str((spec[k] as Dictionary).get("type", "str")), str(k), merged[k], spec[k], "%s %s" % [ctx, str(k)], data, rep)
		pairs.append(pair)
	a.params = _sorted_dict(pairs)
	if merged.has("stack_group") and merged["stack_group"] is String:
		a.stack_group = data.stack_groups.find(str(merged["stack_group"]))
	return a


static func _sorted_dict(pairs: Array) -> Dictionary:
	pairs.sort_custom(func(x: Array, y: Array) -> bool: return str(x[0]) < str(y[0]))
	var out: Dictionary = {}
	for p: Array in pairs:
		out[p[0]] = p[1]
	return out


## Runtime key of a file key under registry type `t` (`rate_pct_per_s` + pcts -> `rate_bps`, `radius_cells` -> `radius_u`).
static func runtime_key(t: String, key: String) -> String:
	if t.begins_with("[") or t == "bool" or t == "str" or t.begins_with("enum:"):
		return key
	if t == "pcts" and key.ends_with("_pcts"):
		return key.substr(0, key.length() - 5) + "_bps"
	if _ID_KIND_OF_TYPE.has(t):
		if key.ends_with("_ids"):
			return key.substr(0, key.length() - 4) + "_idx"
		if key.ends_with("_id"):
			return key.substr(0, key.length() - 3) + "_idx"
		return key
	if _TYPE_SUFFIX.has(t):
		var row: Array = _TYPE_SUFFIX[t]
		var suf: String = row[0]
		if key.ends_with(suf):
			return key.substr(0, key.length() - suf.length()) + str(row[1])
	return key


## Number of registry type `t` (cells, s, pct, ...) -> runtime int.
static func convert_number(t: String, v: Variant, where: String, rep: DefLoadReport) -> int:
	if typeof(v) == TYPE_BOOL:
		return 1 if v else 0
	match t:
		"cells":
			return DefConvert.cells_to_units(DefNumParse.milli(v, where, rep))
		"cells_s":
			return DefConvert.cells_s_to_upt(DefNumParse.milli(v, where, rep))
		"s":
			return DefConvert.seconds_to_ticks(DefNumParse.milli(v, where, rep))
		"smt":
			return DefConvert.seconds_to_mt(DefNumParse.milli(v, where, rep))
		"pct":
			return DefConvert.pct_to_bp(DefNumParse.milli_pct(v, where, rep))
		"pcts":
			return DefConvert.pcts_to_bps(DefNumParse.milli_pct(v, where, rep))
		"deg":
			return DefConvert.deg_to_angle(DefNumParse.milli(v, where, rep))
		"deg_s":
			return DefConvert.deg_s_to_apt(DefNumParse.milli(v, where, rep))
		"crps":
			return DefConvert.crps_to_mcpt(DefNumParse.milli(v, where, rep))
	return DefNumParse.whole(v, where, rep)  # n x hp bp credits x100


## Converts one param under registry type `t`: returns [runtime_key, value]. `spec` is the param spec (for `[{}]`
## items and enum options).
static func convert_typed(t: String, key: String, v: Variant, spec: Dictionary, where: String, data: GameData, rep: DefLoadReport) -> Array:
	var rk: String = runtime_key(t, key)
	if (t.begins_with("[") or t.ends_with("_ids")) and not (v is Array):
		rep.error("V-SCH-07", where, "expected a list for a '%s' parameter" % t)
		if t.ends_with("_ids"):
			return [rk, PackedInt32Array()]
		return [rk, []]
	if t == "bool":
		return [rk, truthy(v)]
	if t == "str":
		return [rk, str(v)]
	if t.begins_with("enum:"):
		var opts: PackedStringArray = t.substr(5).split("|")
		if not opts.has(str(v)):
			rep.error("V-ABL-01", where, "'%s' is not one of %s" % [str(v), t.substr(5)])
		return [rk, str(v)]
	if _ID_KIND_OF_TYPE.has(t):
		var kind: int = _ID_KIND_OF_TYPE[t]
		if t.ends_with("_ids"):
			var idxs: PackedInt32Array = PackedInt32Array()
			for e: Variant in v:
				idxs.append(_lookup(data, kind, str(e), where, rep))
			idxs.sort()
			return [rk, idxs]
		if str(v) == "":
			return [rk, -1]
		return [rk, _lookup(data, kind, str(v), where, rep)]
	if t == "[{}]":
		var items: Dictionary = spec.get("items", {})
		var out: Array = []
		for e: Variant in v:
			if not (e is Dictionary):
				rep.error("V-SCH-07", where, "every list entry must be an object")
				continue
			var pairs: Array = []
			var ed: Dictionary = e
			for k: Variant in ed.keys():
				var sub: Dictionary = items.get(k, {})
				if sub.is_empty():
					rep.error("V-ABL-01", where, "unknown item field '%s'" % str(k))
					continue
				pairs.append(convert_typed(str(sub.get("type", "str")), str(k), ed[k], sub, where + "." + str(k), data, rep))
			out.append(_sorted_dict(pairs))
		return [rk, out]
	if t == "[n]":
		var ints: Array = []
		for e: Variant in v:
			ints.append(DefNumParse.whole(e, where, rep))
		return [rk, ints]
	if t == "[str]" or t.begins_with("[enum:"):
		var names: PackedStringArray = PackedStringArray()
		for e: Variant in v:
			names.append(str(e))
		if key.ends_with("_tags") or key.ends_with("_groups"):
			return [key.substr(0, key.rfind("_")) + "_mask", _mask_of_names(key, names, where, data, rep)]
		var arr: Array = []
		for nm: String in names:
			arr.append(nm)
		return [rk, arr]
	return [rk, convert_number(t, v, where, rep)]


static func _mask_of_names(key: String, names: PackedStringArray, where: String, data: GameData, rep: DefLoadReport) -> int:
	var m: int = 0
	for n: String in names:
		var bit: int = 0
		if key.ends_with("_groups"):
			bit = DefEnums.resist_group_bit(n)
		elif key.contains("structure"):
			bit = data.tags.structure_bit(n)
		elif key.contains("weapon"):
			bit = data.tags.weapon_bit(n)
		else:
			bit = data.tags.unit_bit(n)
		if bit == 0:
			rep.error("V-SCH-07", where, "unknown name '%s'" % n)
		m |= bit
	return m


static func _lookup(data: GameData, kind: int, id: String, where: String, rep: DefLoadReport) -> int:
	var i: int = data.ids.index_of(kind, id)
	if i < 0:
		var msg: String = "unknown %s id '%s'" % [DefEnums.KIND_NAMES[kind], id]
		if kind == DefEnums.Kind.ZONE:
			rep.warn("V-REF-01", where, msg + " (zone reference left unresolved: -1)")  # a dangling zone is not fatal for the load
		else:
			rep.error("V-REF-01", where, msg)
	return i


## Suffix-driven blob conversion that also understands `<x>_pct_per_s` (percent per second -> `<x>_bps`).
static func convert_blob(raw: Dictionary, where: String, data: GameData, rep: DefLoadReport) -> Dictionary:
	var pairs: Array = []
	for k: Variant in raw.keys():
		var key: String = str(k)
		var v: Variant = raw[k]
		if key.ends_with("_pct_per_s") and DefNumParse.is_number(v):
			pairs.append([key.substr(0, key.length() - 10) + "_bps", convert_number("pcts", v, where + "." + key, rep)])
		elif v is Dictionary:
			pairs.append([key, convert_blob(v, where + "." + key, data, rep)])
		else:
			var one: Dictionary = DefConvert.convert_params({key: v}, where, data, rep)
			for rk: Variant in one.keys():
				pairs.append([str(rk), one[rk]])
	return _sorted_dict(pairs)


## Ability of a sheet / effect entry: an `ability.*` template id or a bare framework name (via `aliases`).
## Returns null for entries that produce no ability (`amphibious`, `breach_charge`, ...); reports unknown entries.
static func instantiate_entry(c: Ctx, entry: String, overrides: Dictionary, where: String) -> DefAbility:
	if not c.kinds.known_entry(entry):
		c.rep.error("V-ABL-01", where, "unknown ability '%s' (neither an alias nor a template id)" % entry)
		return null
	var tid: String = c.kinds.resolve_entry(entry)
	if tid == "":
		return null
	return instantiate_template(c.kinds, tid, overrides, where, c.data, c.rep)


static func instantiate_template(kinds: DefAbilityKinds, tid: String, overrides: Dictionary, where: String, data: GameData, rep: DefLoadReport) -> DefAbility:
	if not kinds.templates.has(tid):
		rep.error("V-ABL-01", where, "unknown ability template '%s'" % tid)
		return DefAbility.new()
	var t: Dictionary = kinds.templates[tid]
	var fp: Dictionary = (t.get("params", {}) as Dictionary).duplicate()
	for k: Variant in overrides.keys():
		fp[k] = overrides[k]
	return make_ability(kinds, str(t.get("kind", "")), fp, kinds.template_index(tid), "%s %s" % [where, tid], data, rep, true)


## Adds / replaces (same kind: in place, keeping the slot) an ability on a unit or structure.
static func put_ability(owner: Object, a: DefAbility) -> void:
	var abilities: Array[DefAbility] = owner.get("abilities")
	var slots: PackedInt32Array = owner.get("ability_slot_of_kind")
	if slots.size() < DefEnums.AbilityKind.COUNT:
		slots.resize(DefEnums.AbilityKind.COUNT)
		slots.fill(-1)
	if a.kind >= 0 and a.kind < slots.size() and slots[a.kind] >= 0:
		a.slot = slots[a.kind]
		abilities[a.slot] = a
	else:
		a.slot = abilities.size()
		abilities.append(a)
		slots[a.kind] = a.slot
	owner.set("ability_slot_of_kind", slots)
	var mask: int = 0
	for x: DefAbility in abilities:
		mask |= 1 << x.kind
	owner.set("ability_mask", mask)


# ============================================================================================== weapons
static func _collect_weapons(c: Ctx) -> void:
	for f: String in c.src.manifest_files:
		if not f.begins_with("units_") or not c.src.balance.has(f):
			continue
		for w: Variant in c.src.balance[f].get("weapons", []):
			var wd: Dictionary = w
			var id: String = str(wd.get("id", ""))
			if c.weapons.has(id):
				c.rep.error("V-SCH-03", c.src.where(f, id), "duplicate weapon instance id '%s' (also in %s)" % [id, c.weapon_file[id]])
				continue
			c.weapons[id] = wd
			c.weapon_file[id] = f


## Compiles a weapon instance dict (§7.6) into one DefWeaponSlot. `is_turret_owner` = owner is neither infantry nor
## aircraft (structures: true).
static func build_slot(data: GameData, w: Dictionary, slot_idx: int, is_turret_owner: bool, where: String, rep: DefLoadReport) -> DefWeaponSlot:
	var s: DefWeaponSlot = DefWeaponSlot.new()
	for k: String in _LOCKED_WEAPON_KEYS:
		if w.has(k):
			rep.error("V-CNF-08", where, "weapon instance sets '%s', which the archetype locks" % k)
	var an: String = str(w.get("archetype", ""))
	var ai: int = DefEnums.WEAPON_ARCH_NAMES.find(an)
	if ai < 0:
		rep.error("V-REF-01", where, "unknown weapon archetype '%s'" % an)
		return s
	var a: DefWeaponArch = data.weapon_archs[ai]
	s.arch = ai
	s.slot = slot_idx
	s.ui_label = str(w.get("id", ""))
	s.damage = DefNumParse.whole(w.get("damage", 0), where + " damage", rep)
	s.hits_per_volley = DefNumParse.whole(w.get("hits_per_volley", 1), where + " hits_per_volley", rep)
	s.dtype = a.dtype
	s.fire_mode = a.fire_mode
	s.interceptable = a.interceptable
	s.proj_kind = a.proj_kind
	s.proj_speed = a.proj_speed
	s.homing = a.homing
	s.reload_mt = DefConvert.seconds_to_mt(DefNumParse.milli(w.get("reload_s", 0), where + " reload_s", rep))
	s.reload_ticks = maxi(1, DefConvert.ceil_div(s.reload_mt, 1000))
	s.range = DefConvert.cells_to_units(DefNumParse.milli(w.get("range_cells", 0), where + " range_cells", rep))
	s.min_range = _opt_cells(w, "min_range_cells", a.min_range, where, rep)
	s.splash_radius = _opt_cells(w, "splash_cells", a.splash_radius, where, rep)
	s.scatter = _opt_cells(w, "scatter_cells", a.scatter, where, rep)
	s.splash_edge_bp = a.splash_edge_bp
	if w.has("splash_edge_pct"):
		s.splash_edge_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(w["splash_edge_pct"], where + " splash_edge_pct", rep))
	s.target_mask = a.target_mask
	if w.get("targets_override") != null:
		var tm: int = 0
		for l: Variant in w["targets_override"]:
			var lb: int = DefEnums.layer_bit(str(l))
			if lb == 0:
				rep.error("V-SCH-07", where, "unknown layer '%s' in targets_override" % str(l))
			tm |= lb
		s.target_mask = tm
	s.turret_turn = a.turret_turn
	if w.has("turret_deg_s"):
		s.turret_turn = DefConvert.deg_s_to_apt(DefNumParse.milli(w["turret_deg_s"], where + " turret_deg_s", rep))
	s.fire_arc = DefConvert.deg_to_angle(DefNumParse.milli(w.get("arc_deg", 360), where + " arc_deg", rep))
	var supp: bool = truthy(w.get("suppressive"), a.suppressive_default)
	if supp:
		s.flags |= DefEnums.WF_SUPPRESSIVE
	if a.homing:
		s.flags |= DefEnums.WF_HOMING
	for f: Variant in w.get("flags", []):
		if _WEAPON_FLAGS.has(str(f)):
			s.flags |= int(_WEAPON_FLAGS[str(f)])
		else:
			rep.error("V-SCH-07", where, "unknown weapon flag '%s'" % str(f))
	if w.has("deploy_s"):
		s.deploy_t = DefConvert.seconds_to_ticks(DefNumParse.milli(w["deploy_s"], where + " deploy_s", rep))
	s.ammo_volleys = DefNumParse.whole(w.get("ammo_volleys", 0), where + " ammo_volleys", rep)
	if w.has("ramp_seconds"):
		s.ramp_t = DefConvert.seconds_to_ticks(DefNumParse.milli(w["ramp_seconds"], where + " ramp_seconds", rep))
	if w.has("ramp_max_pct"):
		s.ramp_max_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(w["ramp_max_pct"], where + " ramp_max_pct", rep))
	if w.has("requires_surface_s"):
		s.requires_surface_t = DefConvert.seconds_to_ticks(DefNumParse.milli(w["requires_surface_s"], where + " requires_surface_s", rep))
	var mount: int = 1 if (s.turret_turn > 0 and is_turret_owner) else 0
	if w.has("mount"):
		mount = 1 if str(w["mount"]) == "turret" else 0
	s.mount = mount
	for m: Variant in w.get("modes", []):
		s.mode_mask |= 1 << DefNumParse.whole(m, where + " modes", rep)
	return s


static func _opt_cells(w: Dictionary, key: String, dflt: int, where: String, rep: DefLoadReport) -> int:
	if not w.has(key):
		return dflt
	return DefConvert.cells_to_units(DefNumParse.milli(w[key], where + " " + key, rep))


# ================================================================================================== units
static func _build_sheet(c: Ctx, file: String) -> void:
	var sheet: Dictionary = c.src.balance[file]
	for e: Variant in sheet.get("units", []):
		var sh: Dictionary = e
		var id: String = str(sh.get("id", ""))
		var idx: int = c.data.unit_idx(id)
		if idx < 0 or not id.begins_with("unit."):
			c.rep.error("V-REF-01", c.src.where(file, id), "sheet unit '%s' is not a bible unit" % id)
			continue
		if c.built.has(id):
			c.rep.error("V-SCH-03", c.src.where(file, id), "unit '%s' appears twice in the unit sheets" % id)
			continue
		c.built[id] = true
		_fill_unit(c, c.data.units[idx], sh, file, false)
	for e: Variant in sheet.get("summons", []):
		var sh2: Dictionary = e
		var id2: String = str(sh2.get("id", ""))
		var idx2: int = c.data.unit_idx(id2)
		if idx2 < 0:
			c.rep.error("V-REF-01", c.src.where(file, id2), "summon '%s' has no id" % id2)
			continue
		_fill_unit(c, c.data.units[idx2], sh2, file, true)


static func _archetype(c: Ctx, name: String) -> Dictionary:
	if name.begins_with("service."):
		return (c.g.get("service_units", {}) as Dictionary).get(name.substr(8), {})
	return (c.g.get("archetypes", {}) as Dictionary).get(name, {})


static func _pick(sh: Dictionary, arch: Dictionary, key: String) -> Variant:
	if sh.get(key) != null:
		return sh[key]
	return arch.get(key)


static func _enum_index(names: PackedStringArray, v: Variant, what: String, where: String, rep: DefLoadReport) -> int:
	var i: int = names.find(str(v))
	if i < 0:
		rep.error("V-REF-01", where, "unknown %s '%s'" % [what, str(v)])
		return 0
	return i


## Bible (+) balance merge of one numeric unit field (data_balance 5.2.4); `code` picks the converter.
static func _merged(c: Ctx, where: String, field: String, code: String, bible_v: Variant, sheet_v: Variant, arch_v: Variant, required: bool) -> int:
	var bh: bool = bible_v != null
	var sv: Variant = sheet_v
	if not bh and sv == null and arch_v != null:
		sv = arch_v
	var bal_has: bool = sv != null
	var bi: int = _conv(code, bible_v, where + " " + field, c.rep) if bh else 0
	var si: int = _conv(code, sv, where + " " + field, c.rep) if bal_has else 0
	return DefLoader.merge_field(bh, bi, bal_has, si, where, field, required, c.rep)


static func _conv(code: String, v: Variant, where: String, rep: DefLoadReport) -> int:
	match code:
		"secs":
			return DefConvert.seconds_to_ticks(DefNumParse.milli(v, where, rep))
		"cps":
			return DefConvert.cells_s_to_upt(DefNumParse.milli(v, where, rep))
	return DefNumParse.whole(v, where, rep)


static func _fill_unit(c: Ctx, u: DefUnit, sh: Dictionary, file: String, is_summon: bool) -> void:
	var data: GameData = c.data
	var rep: DefLoadReport = c.rep
	var where: String = c.src.where(file, u.id)
	var arch_name: String = str(sh.get("archetype", ""))
	var arch: Dictionary = {}
	if not is_summon:
		arch = _archetype(c, arch_name)
		if arch.is_empty():
			rep.error("V-REF-01", where, "unknown archetype '%s' of %s" % [arch_name, u.id])
	var bible_unit: Dictionary = (c.src.bible.get("units", {}) as Dictionary).get(u.id, {})
	var bs: Dictionary = bible_unit.get("base_stats", {})
	if is_summon:
		_fill_summon_class(c, u, sh, where)
	elif sh.get("tier") != null and DefNumParse.whole(sh["tier"], where + " tier", rep) != u.tier:
		rep.error("V-CNF-01", where, "tier: bible says %d, sheet says %s" % [u.tier, str(sh["tier"])])
	var size_name: String = str(_pick(sh, arch, "size_class"))
	var mc_name: String = str(_pick(sh, arch, "movement_class"))
	var entries: Array = []
	if sh.has("abilities"):
		entries = sh["abilities"]
	elif not is_summon:
		entries = ((c.g.get("unit_assignments", {}) as Dictionary).get(u.id, {}) as Dictionary).get("abilities", [])
	if entries.has("amphibious") and sh.get("movement_class") == null and ["foot", "wheeled", "tracked"].has(mc_name):
		mc_name = "amphibious"
	u.size_class = _enum_index(DefEnums.SIZE_NAMES, size_name, "size class", where, rep)
	u.armor_class = _enum_index(DefEnums.ARMOR_NAMES, _pick(sh, arch, "armor_class"), "armor class", where, rep)
	u.move_class = _enum_index(DefEnums.MOVE_NAMES, mc_name, "movement class", where, rep)
	u.home_layer = _enum_index(DefEnums.LAYER_NAMES, _pick(sh, arch, "layer"), "layer", where, rep)
	u.layer_mask = data.moves.layer_mask[u.move_class] if u.move_class < data.moves.layer_mask.size() else DefEnums.L_GROUND
	# numbers (merge policy for bible-specified ones)
	if not is_summon or sh.has("cost_credits"):
		u.cost = _merged(c, where, "cost_credits", "whole", bs.get("cost_credits"), sh.get("cost_credits"), arch.get("cost_credits"), not is_summon)
	if not is_summon or sh.has("build_time_s"):
		u.build_ticks = _merged(c, where, "build_time_s", "secs", bs.get("build_time_seconds"), sh.get("build_time_s"), arch.get("build_time_s"), not is_summon)
	u.health = _merged(c, where, "health", "whole", bs.get("health"), sh.get("health"), arch.get("health"), true)
	if u.move_class == DefEnums.MoveClass.STATIC and sh.get("speed_cells_s") == null:
		u.speed = 0
	else:
		u.speed = _merged(c, where, "speed_cells_s", "cps", bs.get("movement_speed"), sh.get("speed_cells_s"), arch.get("speed_cells_s"), true)
	u.sight = DefConvert.cells_to_units(DefNumParse.milli(_req(sh, arch, "vision_cells", where, rep), where + " vision_cells", rep))
	var rad: Variant = _pick(sh, arch, "radius_cells")
	u.radius = DefConvert.cells_to_units(DefNumParse.milli(rad, where + " radius_cells", rep)) if rad != null else data.bodies.radius_u[u.size_class]
	u.turn_rate = data.bodies.turn_apt[u.size_class]
	if sh.has("turn_deg_s"):
		u.turn_rate = DefConvert.deg_s_to_apt(DefNumParse.milli(sh["turn_deg_s"], where + " turn_deg_s", rep))
	var accel: Dictionary = (c.g.get("movement_defaults", {}) as Dictionary).get("accel_ticks", {})
	u.accel_t = DefNumParse.whole(sh.get("accel_ticks", accel.get(size_name, 0)), where + " accel_ticks", rep)
	if sh.get("deep_speed_pct") != null:
		u.deep_speed_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(sh["deep_speed_pct"], where + " deep_speed_pct", rep))
	if arch.has("rearm_s_full") or sh.has("rearm_s_full"):
		u.rearm_t = DefConvert.seconds_to_ticks(DefNumParse.milli(_pick(sh, arch, "rearm_s_full"), where + " rearm_s_full", rep))
	u.pop = DefNumParse.whole(sh.get("pop_n", 0 if is_summon else 1), where + " pop_n", rep)
	if sh.has("lifetime_s"):
		u.lifetime_t = DefConvert.seconds_to_ticks(DefNumParse.milli(sh["lifetime_s"], where + " lifetime_s", rep))
	for f: Variant in sh.get("flags", []):
		var fi: int = DefEnums.UNIT_FLAG_NAMES.find(str(f))
		if fi < 0:
			rep.error("V-SCH-07", where, "unknown unit flag '%s'" % str(f))
		else:
			u.flags |= 1 << fi
	for t: Variant in sh.get("tags_add", []):
		var tb: int = data.tags.unit_bit(str(t))
		if tb == 0:
			rep.error("V-SCH-08", where, "tag '%s' is not registered" % str(t))
		u.tags |= tb
	var pres: Dictionary = sh.get("pres", {})
	u.pres_recipe = str(pres.get("recipe", u.id))
	u.pres_icon = str(pres.get("icon", u.id))
	u.pres_snd_profile = str(pres.get("snd_profile", ""))
	u.pres_ai_role = str(pres.get("ai_role", ""))
	if pres.has("scale_pct"):
		u.pres_scale_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(pres["scale_pct"], where + " scale_pct", rep))
	if sh.has("params"):
		u.params = convert_blob(sh["params"], where + " params", data, rep)
	# weapons
	var wlist: Array = []
	if sh.has("weapons"):
		for wid: Variant in sh["weapons"]:
			if not c.weapons.has(str(wid)):
				rep.error("V-REF-01", where, "unknown weapon instance '%s'" % str(wid))
			else:
				wlist.append(c.weapons[str(wid)])
	else:
		wlist = arch.get("weapons", [])
	var turret_owner: bool = (u.tags & (DefEnums.UT_INFANTRY | DefEnums.UT_AIRCRAFT)) == 0 and u.home_layer != DefEnums.Layer.AIR
	u.weapons.clear()
	for i: int in wlist.size():
		u.weapons.append(build_slot(data, wlist[i], i, turret_owner, where + " " + str((wlist[i] as Dictionary).get("id", "weapon %d" % i)), rep))
	# a non-null bible damage / range binds slot 0 (5.2.4)
	if not u.weapons.is_empty():
		var w0: DefWeaponSlot = u.weapons[0]
		if bs.get("damage") != null:
			w0.damage = DefLoader.merge_field(true, DefNumParse.whole(bs["damage"], where, rep), true, w0.damage, where, "weapon damage", false, rep)
		if bs.get("weapon_range_cells") != null:
			w0.range = DefLoader.merge_field(true, DefConvert.cells_to_units(DefNumParse.milli(bs["weapon_range_cells"], where, rep)), true, w0.range, where, "weapon range", false, rep)
	_build_unit_abilities(c, u, sh, arch, arch_name, entries, where)


static func _req(sh: Dictionary, arch: Dictionary, key: String, where: String, rep: DefLoadReport) -> Variant:
	var v: Variant = _pick(sh, arch, key)
	if v == null:
		rep.error("V-CMP-04", where, "%s is missing in the sheet and the archetype" % key)
		return 0
	return v


static func _fill_summon_class(c: Ctx, u: DefUnit, sh: Dictionary, where: String) -> void:
	var cls: String = str(sh.get("class", ""))
	if cls == "summon":
		u.unit_class = DefEnums.UnitClass.SUMMON
		u.flags |= DefEnums.UF_NO_COMBAT_MODS
		u.cost = -1
	elif cls == "drone":
		u.unit_class = DefEnums.UnitClass.DRONE
	else:
		c.rep.error("V-SCH-03", where, "summon class must be 'summon' or 'drone', found '%s'" % cls)
	u.tier = 0
	u.producer = -1
	var names: PackedStringArray = PackedStringArray()
	for t: Variant in sh.get("unit_tags", []):
		names.append(str(t))
	u.tags = 0
	for n: String in names:
		var b: int = c.data.tags.unit_bit(n)
		if b == 0:
			c.rep.error("V-SCH-08", where, "unit tag '%s' is not registered" % n)
		u.tags |= b
	var code: String = u.id.get_slice(".", 1)
	u.faction = c.data.ids.index_of(DefEnums.Kind.FACTION, _SUMMON_FACTION_PREFIX + code)


static func _build_unit_abilities(c: Ctx, u: DefUnit, sh: Dictionary, arch: Dictionary, arch_name: String, entries: Array, where: String) -> void:
	u.abilities.clear()
	u.ability_slot_of_kind = _fresh_slots()
	u.ability_mask = 0
	var tag_names: PackedStringArray = c.data.tags.unit_names(u.tags)
	var params: Dictionary = sh.get("ability_params", {})
	var plan: Array = []  # [entry name (for ability_params), template id | ""]
	for tid: String in _implicit(c.kinds, tag_names, str(arch.get("family", "")), arch_name):
		plan.append([tid, tid])
	for e: Variant in entries:
		plan.append([str(e), str(e)])
	for p: Array in plan:
		var name: String = p[0]
		var ov: Dictionary = params.get(name, {})
		var a: DefAbility = instantiate_entry(c, name, ov, where)
		if a != null:
			put_ability(u, a)
	for k: Variant in params.keys():
		var known: bool = false
		for p2: Array in plan:
			if p2[0] == str(k):
				known = true
		if not known:
			c.rep.error("V-ABL-01", where, "ability_params key '%s' matches no ability entry" % str(k))


static func _fresh_slots() -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(DefEnums.AbilityKind.COUNT)
	a.fill(-1)
	return a


## Implicit template ids of a unit: `tag:` matches first, then `family:`, then `archetype:` (data_balance 7.4).
static func _implicit(kinds: DefAbilityKinds, tags: PackedStringArray, family: String, archetype: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for prefix: String in ["tag:", "family:", "archetype:"]:
		for row: Variant in kinds.implicit:
			var when: String = str((row as Dictionary).get("when", ""))
			if not when.begins_with(prefix):
				continue
			var key: String = when.substr(prefix.length())
			var hit: bool = (prefix == "tag:" and tags.has(key)) or (prefix == "family:" and family == key) or (prefix == "archetype:" and archetype == key)
			if hit:
				for t: Variant in (row as Dictionary).get("templates", []):
					out.append(str(t))
	return out


## Recomputes every derived cache of a unit def from its slots / abilities / numbers (also used by roster grants).
static func derive_unit(data: GameData, u: DefUnit) -> void:
	u.ability_slot_of_kind = _fresh_slots()
	u.ability_mask = 0
	for i: int in u.abilities.size():
		var a: DefAbility = u.abilities[i]
		a.slot = i
		u.ability_slot_of_kind[a.kind] = i
		u.ability_mask |= 1 << a.kind
	u.max_range = 0
	u.min_range = 0
	u.attack_layer_mask = 0
	u.weapon_tags = 0
	var first: bool = true
	for w: DefWeaponSlot in u.weapons:
		u.max_range = maxi(u.max_range, w.range)
		u.min_range = w.min_range if first else mini(u.min_range, w.min_range)
		first = false
		u.attack_layer_mask |= w.target_mask
		u.weapon_tags |= data.weapon_archs[w.arch].tags
	if u.weapons.is_empty():
		u.flags |= DefEnums.UF_UNARMED
	else:
		u.flags &= ~DefEnums.UF_UNARMED
	u.detect_radius = _param_of(u, DefEnums.AbilityKind.DETECTOR, "radius_u")
	u.cloak_delay_t = _param_of(u, DefEnums.AbilityKind.CAMOUFLAGE, "delay_t")
	u.transport_squads = _param_of(u, DefEnums.AbilityKind.TRANSPORT, "capacity_squads_n")
	u.transport_vehicles = _param_of(u, DefEnums.AbilityKind.TRANSPORT, "capacity_vehicles_n")
	u.speed_water = DefMoveTable.effective_speed(data.moves, u.speed, u.move_class, DefEnums.TerrainKind.DEEP, u.deep_speed_bp, u.water_mult_bp)


static func _param_of(u: DefUnit, kind: int, key: String) -> int:
	var a: DefAbility = u.ability_of(kind)
	if a == null:
		return 0
	return int(a.params.get(key, 0))


# ============================================================================================ structures
static func _build_structures(c: Ctx) -> void:
	var data: GameData = c.data
	var overlay: Dictionary = {}
	if c.src.balance.has("structures.json"):
		for e: Variant in c.src.balance["structures.json"].get("structures", []):
			overlay[str((e as Dictionary).get("id", ""))] = e
	for id: Variant in overlay.keys():
		if data.structure_idx(str(id)) < 0:
			c.rep.error("V-REF-01", c.src.where("structures.json", str(id)), "overlay entry '%s' is not a bible structure" % str(id))
	var gs: Dictionary = c.g.get("structures", {})
	for s: DefStructure in data.structures:
		var where: String = c.src.where("structures.json", s.id)
		var short: String = s.id.get_slice(".", 2)
		var block: Dictionary = {}
		var adv: Dictionary = {}
		if gs.has(short):
			block = gs[short]
		elif (s.tags & DefEnums.ST_ADVANCED_DEFENSE) != 0:
			block = gs.get("advanced_defense", {})
			adv = _advanced_entry(c, s.id.get_slice(".", 1))
		elif (s.tags & DefEnums.ST_SUPERWEAPON) != 0:
			block = gs.get("superweapon", {})
		if block.is_empty():
			c.rep.error("V-CMP-02", where, "no global.json structures block for '%s'" % s.id)
			continue
		if not overlay.has(s.id):
			c.rep.warn("V-CMP-02", "structures.json", "structure '%s' has no overlay entry" % s.id)
		_fill_structure(c, s, block, adv, overlay.get(s.id, {}), where)
	for s2: DefStructure in data.structures:
		s2.weapon_tags = 0
		for w: DefWeaponSlot in s2.weapons:
			s2.weapon_tags |= data.weapon_archs[w.arch].tags
		for pair: Array in [[DefEnums.WT_ANTI_AIR, "anti_air"], [DefEnums.WT_ANTI_GROUND, "anti_ground"], [DefEnums.WT_ANTI_SUB, "anti_sub"]]:
			if (s2.weapon_tags & int(pair[0])) != 0:
				s2.tags |= data.tags.structure_bit(str(pair[1]))


static func _advanced_entry(c: Ctx, faction_code: String) -> Dictionary:
	var adv: Dictionary = (c.g.get("defenses", {}) as Dictionary).get("advanced", {})
	for k: Variant in adv.keys():
		if str((adv[k] as Dictionary).get("faction", "")) == faction_code:
			return adv[k]
	return {}


static func _fill_structure(c: Ctx, s: DefStructure, block: Dictionary, adv: Dictionary, ov: Dictionary, where: String) -> void:
	var data: GameData = c.data
	var rep: DefLoadReport = c.rep
	var bible: Dictionary = (c.src.bible.get("structures", {}) as Dictionary).get(s.id, {})
	s.cost = _merged(c, where, "cost_credits", "whole", bible.get("cost_credits"), block.get("cost_credits"), null, true)
	s.power = _merged(c, where, "power_delta", "whole", bible.get("power_supply_delta"), block.get("power_delta"), null, true)
	var bt: Variant = bible.get("build_time_seconds")
	var bal_bt: Variant = block.get("build_time_s")
	if bt != null or bal_bt != null:
		s.build_ticks = _merged(c, where, "build_time_s", "secs", bt, bal_bt, null, false)
	s.health = DefNumParse.whole(adv.get("health", block.get("health", 0)), where + " health", rep)
	s.armor_class = _enum_index(DefEnums.ARMOR_NAMES, block.get("armor_class", ""), "armor class", where, rep)
	var fp: Array = block.get("footprint", [1, 1])
	s.fp_w = DefNumParse.whole(fp[0], where + " footprint", rep)
	s.fp_h = DefNumParse.whole(fp[1], where + " footprint", rep)
	s.size_class = DefEnums.SizeClass.S1 + clampi(maxi(s.fp_w, s.fp_h), 1, 4) - 1
	s.radius = DefConvert.cells_to_units(DefNumParse.milli(block.get("radius_cells", 0), where + " radius_cells", rep))
	s.sight = DefConvert.cells_to_units(DefNumParse.milli(block.get("vision_cells", 0), where + " vision_cells", rep))
	if block.get("deploy_s") != null:
		s.deploy_t = DefConvert.seconds_to_ticks(DefNumParse.milli(block["deploy_s"], where + " deploy_s", rep))
	s.exit_dx = 0
	s.exit_dy = s.fp_h
	# weapons: shared defenses by short name, advanced by faction
	var wl: Array = []
	var short: String = s.id.get_slice(".", 2)
	var shared: Dictionary = (c.g.get("defenses", {}) as Dictionary).get("shared", {})
	if shared.has(short):
		wl = shared[short]
	elif not adv.is_empty():
		var w: Dictionary = (adv.get("weapon", {}) as Dictionary).duplicate()
		if adv.has("turret_deg_s") and not w.has("turret_deg_s"):
			w["turret_deg_s"] = adv["turret_deg_s"]
		wl = [w]
	s.weapons.clear()
	for i: int in wl.size():
		s.weapons.append(build_slot(data, wl[i], i, true, where + " weapon %d" % i, rep))
	# abilities: derived from the block, then the overlay
	s.abilities.clear()
	s.ability_slot_of_kind = _fresh_slots()
	s.ability_mask = 0
	if block.get("detector_radius_cells") != null:
		var d: DefAbility = instantiate_template(c.kinds, "ability.detector.default", {"radius_cells": block["detector_radius_cells"]}, where, data, rep)
		put_ability(s, d)
		s.detect_radius = int(d.params.get("radius_u", 0))
	if block.get("pads") != null:
		put_ability(s, instantiate_template(c.kinds, "ability.service_pads.default", {"pads_n": block["pads"]}, where, data, rep))
		s.pads = DefNumParse.whole(block["pads"], where + " pads", rep)
	if short == "refinery":
		var slots: Variant = ((c.g.get("economy", {}) as Dictionary).get("collector", {}) as Dictionary).get("refinery_unload_slots", 1)
		put_ability(s, instantiate_template(c.kinds, "ability.refinery.default", {"free_collector_id": "unit.shared.collector", "unload_slots_n": slots}, where, data, rep))
	var oparams: Dictionary = ov.get("ability_params", {})
	for e: Variant in ov.get("abilities", []):
		var a: DefAbility = instantiate_entry(c, str(e), oparams.get(str(e), {}), where)
		if a != null:
			put_ability(s, a)
			if a.kind == DefEnums.AbilityKind.DETECTOR:
				s.detect_radius = int(a.params.get("radius_u", 0))
	# overlay scalars
	if ov.has("exit"):
		var ex: Dictionary = ov["exit"]
		s.exit_dx = DefNumParse.whole(ex.get("dx", 0), where + " exit", rep)
		s.exit_dy = DefNumParse.whole(ex.get("dy", s.fp_h), where + " exit", rep)
	if ov.has("footprint_mask"):
		var rows: Array = ov["footprint_mask"]
		var mask: PackedByteArray = PackedByteArray()
		for r: Variant in rows:
			for ch: String in str(r):
				mask.append(1 if ch == "X" else 0)
		if rows.size() != s.fp_h or mask.size() != s.fp_w * s.fp_h:
			rep.error("V-RNG-04", where, "footprint_mask must have fp_h rows of fp_w characters")
		s.fp_mask = mask
	s.queues = DefNumParse.whole(ov.get("queues_n", 1), where + " queues_n", rep)
	for f: Variant in ov.get("flags", []):
		if _STRUCT_FLAGS.has(str(f)):
			s.flags |= int(_STRUCT_FLAGS[str(f)])
		else:
			rep.error("V-SCH-07", where, "unknown structure flag '%s'" % str(f))
	if ov.has("sell_pct"):
		s.sell_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(ov["sell_pct"], where + " sell_pct", rep))
	if ov.has("repair_rate_pct"):
		s.repair_rate_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(ov["repair_rate_pct"], where + " repair_rate_pct", rep))
	for t: Variant in ov.get("tags_add", []):
		var tb: int = data.tags.structure_bit(str(t))
		if tb == 0:
			rep.error("V-SCH-08", where, "structure tag '%s' is not registered" % str(t))
		s.tags |= tb
	var pres: Dictionary = ov.get("pres", {})
	s.pres_recipe = str(pres.get("recipe", s.id))
	s.pres_icon = str(pres.get("icon", s.id))
	s.pres_snd_profile = str(pres.get("snd_profile", ""))
	if ov.has("params"):
		s.params = convert_blob(ov["params"], where + " params", data, rep)
