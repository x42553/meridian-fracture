class_name DefLoader
extends RefCounted
## Pipeline driver P0..P9 (data_balance 5.1): reads DefSources, verifies the frozen vocabulary, assigns ids, ingests
## the bible into base defs, merges balance, resolves rosters, validates, hashes and publishes a GameData.
## Returns null when the report has errors (GameData.last_report explains).
##
## Phases owned here: P1 (source validation), P2 (vocabularies from global.json), P3 (ids), the bible ingestion of
## P4/P5-lite/P6-lite/P7 (structures, units, research, powers, superweapons, factions, rosters, modifiers, selector
## shells) and P9 (hash). The balance-dependent phases plug in through OPTIONAL HOOKS: a script that exists at
##   res://src/data/<name>.gd  is called with a static method of the documented signature, in this order:
##   def_resolver.compile_selector(data, raw, id, rep) -> DefSelector      (DefResolver; per selector, bible + balance)
##   def_loader_balance.build(src, data, rep)                                (units / structures / weapons / abilities numbers)
##   def_loader_rules.build(src, data, rep)                                  (research, powers, factions, neutrals, zones)
##   def_loader_effects.build(src, data, rep)                                (effects, conditions, superweapon compilation)
##   def_roster_builder.build_all(data, rep)                                 (DefRosterBuilder: fills data.rosters + base_roster)
## A missing hook script is skipped, so those classes can land independently of this file.

const _HOOK_DIR: String = "res://src/data/%s.gd"
const _QUEUE_OF: Dictionary = {
	"barracks": 1, "factory": 2, "airfield": 3, "dock": 4, "refinery": 5,
}


static func build(src: DefSources, level: int, compilers: Array[DefDomainCompiler]) -> GameData:
	var rep: DefLoadReport = DefLoadReport.new()
	GameData.last_report = rep
	var comps: Array[DefDomainCompiler] = _sorted_compilers(compilers, rep)
	var extra_files: PackedStringArray = PackedStringArray()
	for c: DefDomainCompiler in comps:
		extra_files.append_array(c.file_names())
	# P0 happened in DefSources; P1 source validation.
	DefValidator.validate_sources(src, rep, level, extra_files)
	if rep.is_ok():
		DefLoaderBalance.check_shapes(src, rep)  # DATA-04: container / element types of every balance file (V-SCH-03)
	if not rep.is_ok() or not src.balance.has("global.json"):
		return null
	var data: GameData = GameData.new()
	data.report = rep
	data._compilers = comps
	data._sources = src
	# P2 vocabularies
	_phase_vocab(src, data, rep)
	if not rep.is_ok():
		return null
	# P3 ids
	_phase_ids(src, data, rep)
	for c: DefDomainCompiler in comps:
		c.collect_ids(src, data.ids, rep)
	if not rep.is_ok():
		return null
	# P4..P7 bible ingestion
	_ingest_structures(src, data, rep)
	_ingest_units(src, data, rep)
	_ingest_rules(src, data, rep)
	_ingest_factions_rosters(src, data, rep)
	_ingest_selectors_modifiers(src, data, rep)
	_derive(data)
	if not rep.is_ok():
		return null
	for hook: String in ["def_loader_balance", "def_loader_rules", "def_loader_effects"]:
		_call_hook(hook, "build", [src, data, rep])
		if not rep.is_ok():
			return null
	_call_hook("def_roster_builder", "build_all", [data, rep])
	for c: DefDomainCompiler in comps:
		c.compile(src, data, rep)
	if not rep.is_ok():
		return null
	# P9 validate + hash + freeze
	DefValidator.validate_data(data, rep, level)
	for c: DefDomainCompiler in comps:
		c.validate(data, rep, level)
	if not rep.is_ok():
		return null
	data.finalize_hashes()
	return data


# ---------------------------------------------------------------------------------------------- merge policy
## Bible (+) balance merge of ONE numeric field, both already in runtime units (data_balance 5.2.4).
## non-null/absent -> bible; equal -> bible + V-CNF-02 info; different -> V-CNF-01 error; null/present -> balance;
## null/absent -> V-CMP-04 error when `required`, else 0.
static func merge_field(bible_has: bool, bible_v: int, bal_has: bool, bal_v: int, where: String, field: String, required: bool, rep: DefLoadReport) -> int:
	if bible_has and not bal_has:
		return bible_v
	if bible_has and bal_has:
		if bible_v == bal_v:
			rep.info("V-CNF-02", where, "%s: balance repeats the bible value %d" % [field, bible_v])
		else:
			rep.error("V-CNF-01", where, "%s: bible says %d, balance says %d" % [field, bible_v, bal_v])
		return bible_v
	if bal_has:
		return bal_v
	if required:
		rep.error("V-CMP-04", where, "%s is null in the bible and missing in the balance files" % field)
	return 0


## True when `hook` exists as a script under res://src/data/.
static func has_hook(hook: String) -> bool:
	return ResourceLoader.exists(_HOOK_DIR % hook)


static func _hook_script(hook: String) -> Script:
	var path: String = _HOOK_DIR % hook
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script


static func _call_hook(hook: String, method: String, args: Array) -> Variant:
	var sc: Script = _hook_script(hook)
	if sc == null:
		return null
	return sc.callv(method, args)


static func _sorted_compilers(compilers: Array[DefDomainCompiler], rep: DefLoadReport) -> Array[DefDomainCompiler]:
	var out: Array[DefDomainCompiler] = compilers.duplicate()
	out.sort_custom(func(a: DefDomainCompiler, b: DefDomainCompiler) -> bool: return a.domain_id() < b.domain_id())
	for i: int in range(1, out.size()):
		if out[i].domain_id() == out[i - 1].domain_id():
			rep.error("V-SCH-03", "compilers", "duplicate compiler domain '%s'" % out[i].domain_id())
	return out


# ---------------------------------------------------------------------------------------------------- P2
static func _phase_vocab(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var g: Dictionary = src.balance["global.json"]
	var conv: Dictionary = g.get("conventions", {})
	if int(conv.get("tps", 0)) != SimConfig.TPS:
		rep.error("V-CNF-05", "global.json conventions.tps", "must equal SimConfig.TPS (%d)" % SimConfig.TPS)
	if int(conv.get("cell_units", 0)) != Fp.CELL:
		rep.error("V-CNF-05", "global.json conventions.cell_units", "must equal Fp.CELL (%d)" % Fp.CELL)
	_verify_names(g.get("layers", []), DefEnums.LAYER_NAMES, "layers", rep)
	_verify_names(g.get("fire_modes", []), DefEnums.FIRE_NAMES, "fire_modes", rep)
	data.damage = DefDamageTable.from_global(g, rep)
	data.moves = DefMoveTable.from_global(g, rep)
	data.bodies = DefBodyTable.from_global(g, rep)
	data.weapon_archs = DefWeaponArch.build_all(g, rep)
	data.economy = DefEconomy.from_global(g, src.bible, rep)
	data.tags = DefTags.new()
	# free tags: sheets' tags_add + the derived structure weapon tags, registered in sorted-name order
	var unit_extra: PackedStringArray = PackedStringArray()
	var struct_extra: PackedStringArray = PackedStringArray(["anti_air", "anti_ground", "anti_sub"])
	for f: String in src.manifest_files:
		if not f.begins_with("units_") or not src.balance.has(f):
			continue
		var d: Dictionary = src.balance[f]
		for u: Variant in d.get("units", []):
			var add: Array = (u as Dictionary).get("tags_add", [])
			data.tags.add_extras(0, PackedStringArray(add), rep, "%s %s tags_add" % [f, str((u as Dictionary).get("id", ""))])
		for s: Variant in d.get("summons", []):
			for t: Variant in (s as Dictionary).get("unit_tags", []):
				if not DefEnums.UNIT_TAG_NAMES.has(str(t)) and not unit_extra.has(str(t)):
					unit_extra.append(str(t))
	if src.balance.has("structures.json"):
		for s: Variant in src.balance["structures.json"].get("structures", []):
			var sd: Dictionary = s
			for t: Variant in sd.get("tags_add", []):
				if not struct_extra.has(str(t)):
					struct_extra.append(str(t))
	data.tags.add_extras(0, unit_extra, rep, "units summons unit_tags")
	data.tags.add_extras(1, struct_extra, rep, "structures tags_add")


static func _verify_names(have: Array, want: PackedStringArray, what: String, rep: DefLoadReport) -> void:
	var ok: bool = have.size() == want.size()
	if ok:
		for i: int in want.size():
			if str(have[i]) != want[i]:
				ok = false
	if not ok:
		rep.error("V-CNF-05", "global.json " + what, "differs from the frozen vocabulary %s" % str(want))


# ---------------------------------------------------------------------------------------------------- P3
static func _keys_of(d: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if d is Dictionary:
		for k: Variant in (d as Dictionary).keys():
			out.append(str(k))
	return out


static func _phase_ids(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var b: Dictionary = src.bible
	var ids: DefIds = data.ids
	var unit_ids: PackedStringArray = _keys_of(b.get("units", {}))
	for f: String in src.manifest_files:
		if f.begins_with("units_") and src.balance.has(f):
			for s: Variant in src.balance[f].get("summons", []):
				unit_ids.append(str((s as Dictionary).get("id", "")))
	ids.assign(DefEnums.Kind.UNIT, unit_ids, rep)
	ids.assign(DefEnums.Kind.STRUCTURE, _keys_of(b.get("structures", {})), rep)
	var wa: PackedStringArray = PackedStringArray()
	for n: String in DefEnums.WEAPON_ARCH_NAMES:
		wa.append("warch." + n)
	ids.assign_frozen(DefEnums.Kind.WEAPON_ARCH, wa, rep)
	ids.assign(DefEnums.Kind.RESEARCH, _keys_of(b.get("research", {})), rep)
	ids.assign(DefEnums.Kind.POWER, _keys_of(b.get("support_powers", {})), rep)
	ids.assign(DefEnums.Kind.SUPERWEAPON, _keys_of(b.get("superweapons", {})), rep)
	ids.assign(DefEnums.Kind.FACTION, _keys_of(b.get("factions", {})), rep)
	ids.assign(DefEnums.Kind.ROSTER, _keys_of(b.get("rosters", {})), rep)
	ids.assign(DefEnums.Kind.MODIFIER, _keys_of(b.get("modifiers", {})), rep)
	var sel: PackedStringArray = _keys_of(b.get("selectors", {}))
	for f: String in ["research_effects.json", "power_actions.json", "zone_templates.json", "faction_traits.json"]:
		if src.balance.has(f):
			sel.append_array(_keys_of(src.balance[f].get("selectors", {})))
	ids.assign(DefEnums.Kind.SELECTOR, sel, rep)
	if src.balance.has("ability_kinds.json"):
		ids.assign(DefEnums.Kind.ABILITY, _keys_of(src.balance["ability_kinds.json"].get("templates", {})), rep)
	if src.balance.has("zone_templates.json"):
		ids.assign(DefEnums.Kind.ZONE, _keys_of(src.balance["zone_templates.json"].get("zones", {})), rep)
	if src.balance.has("neutral_structures.json"):
		ids.assign(DefEnums.Kind.NEUTRAL, _keys_of(src.balance["neutral_structures.json"].get("neutrals", {})), rep)


# ------------------------------------------------------------------------------------ ingestion helpers
static func _ref(data: GameData, kind: int, id: Variant, where: String, rep: DefLoadReport, src: DefSources) -> int:
	if id == null:
		return -1
	var i: int = data.ids.index_of(kind, str(id))
	if i < 0:
		rep.error("V-REF-01", src.where(src.bible_path, where), "unknown %s id '%s'" % [DefEnums.KIND_NAMES[kind], str(id)])
	return i


static func _ref_list(data: GameData, kind: int, arr: Variant, where: String, rep: DefLoadReport, src: DefSources, sort_asc: bool) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if arr is Array:
		for e: Variant in arr:
			out.append(_ref(data, kind, e, where, rep, src))
	if sort_asc:
		out.sort()
	return out


static func _mask_of_structs(list: PackedInt32Array) -> int:
	var m: int = 0
	for i: int in list:
		if i >= 0 and i < DefEnums.MAX_TAG_BITS:
			m |= 1 << i
	return m


static func _tag_mask(names: Variant, ns: int, data: GameData, where: String, rep: DefLoadReport, src: DefSources) -> int:
	var m: int = 0
	if names is Array:
		for t: Variant in names:
			var n: String = str(t)
			var bit: int = data.tags.unit_bit(n) if ns == 0 else data.tags.structure_bit(n)
			if bit == 0:
				rep.error("V-CNF-05", src.where(src.bible_path, where), "bible tag '%s' is not in the fixed tag table" % n)
			m |= bit
	return m


static func _secs(v: Variant, where: String, rep: DefLoadReport) -> int:
	return DefConvert.seconds_to_ticks(DefNumParse.milli(v, where, rep))


static func _entries(src: DefSources, section: String) -> Dictionary:
	return src.bible.get(section, {})


static func _fresh_ability_slots() -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(DefEnums.AbilityKind.COUNT)
	a.fill(-1)
	return a


# ---------------------------------------------------------------------------------------- structures
static func _ingest_structures(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var b: Dictionary = _entries(src, "structures")
	for i: int in data.ids.count(DefEnums.Kind.STRUCTURE):
		var id: String = data.ids.id_of(DefEnums.Kind.STRUCTURE, i)
		var e: Dictionary = b[id]
		var s: DefStructure = DefStructure.new()
		s.id = id
		s.index = i
		s.ui_name = str(e.get("name", ""))
		s.ui_text = str(e.get("description", ""))
		s.tags = _tag_mask(e.get("tags", []), 1, data, id, rep, src)
		s.faction = _ref(data, DefEnums.Kind.FACTION, e.get("faction_id"), id, rep, src)
		s.requires = _ref_list(data, DefEnums.Kind.STRUCTURE, e.get("requires_all_structure_ids", []), id, rep, src, true)
		s.requires_mask = _mask_of_structs(s.requires)
		s.cost = DefNumParse.whole(e.get("cost_credits", 0), id + " cost_credits", rep)
		s.power = DefNumParse.whole(e.get("power_supply_delta", 0), id + " power_supply_delta", rep)
		var bt: Variant = e.get("build_time_seconds")
		if bt != null:
			s.build_ticks = _secs(bt, id + " build_time_seconds", rep)
		elif s.cost == 0:
			s.flags |= DefEnums.SF_NO_BUILD
		for c: Variant in e.get("conditions", []):
			match str(c):
				DefEnums.PLACE_TEXT_SHORELINE:
					s.place_mask |= DefEnums.PLACE_SHORELINE
				DefEnums.PLACE_TEXT_STRATEGIC:
					s.place_mask |= DefEnums.PLACE_MAX_ONE_STRATEGIC
					s.max_per_player = 1
				DefEnums.PLACE_TEXT_NO_EXTENSION:
					s.place_mask |= DefEnums.PLACE_NO_RADIUS_EXTENSION
				_:
					rep.error("V-MOD-04", src.where(src.bible_path, id), "unknown structure condition '%s'" % str(c))
		s.deploy_unit = _ref(data, DefEnums.Kind.UNIT, e.get("deployment_unit_id"), id, rep, src)
		s.starts_deployed = bool(e.get("can_start_deployed", false))
		s.repair_rate_bp = 10000
		s.repair_cost_bp = data.economy.repair_cost_bp
		s.sell_bp = data.economy.sell_refund_bp
		s.ability_slot_of_kind = _fresh_ability_slots()
		s.pres_recipe = id
		s.pres_icon = id
		data.structures.append(s)


# --------------------------------------------------------------------------------------------- units
static func _ingest_units(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var b: Dictionary = _entries(src, "units")
	var class_of: Dictionary = {"service": 0, "baseline_combat": 1, "unique_subfaction": 2}
	for i: int in data.ids.count(DefEnums.Kind.UNIT):
		var id: String = data.ids.id_of(DefEnums.Kind.UNIT, i)
		var u: DefUnit = DefUnit.new()
		u.id = id
		u.index = i
		u.ability_slot_of_kind = _fresh_ability_slots()
		u.pres_recipe = id
		u.pres_icon = id
		data.units.append(u)
		if not b.has(id):
			continue  # balance-owned summon / drone: filled by the balance loader
		var e: Dictionary = b[id]
		u.ui_name = str(e.get("name", ""))
		u.ui_text = str(e.get("role_and_abilities", ""))
		u.tags = _tag_mask(e.get("tags", []), 0, data, id, rep, src)
		u.faction = _ref(data, DefEnums.Kind.FACTION, e.get("faction_id"), id, rep, src)
		u.introduced_by = _ref(data, DefEnums.Kind.ROSTER, e.get("introduced_by_roster_id"), id, rep, src)
		u.replaces = _ref(data, DefEnums.Kind.UNIT, e.get("replaces_unit_id"), id, rep, src)
		var rc: String = str(e.get("roster_class", ""))
		if not class_of.has(rc):
			rep.error("V-SCH-03", src.where(src.bible_path, id), "unknown roster_class '%s'" % rc)
		u.unit_class = class_of.get(rc, 1)
		u.tier = DefNumParse.whole(e.get("tier", 1), id + " tier", rep)
		u.producer = _ref(data, DefEnums.Kind.STRUCTURE, e.get("producer_structure_id"), id, rep, src)
		u.requires = _ref_list(data, DefEnums.Kind.STRUCTURE, e.get("requires_all_structure_ids", []), id, rep, src, true)
		u.requires_mask = _mask_of_structs(u.requires)
		var bs: Dictionary = e.get("base_stats", {})
		if bs.get("cost_credits") != null:
			u.cost = DefNumParse.whole(bs["cost_credits"], id + " cost_credits", rep)
		if bs.get("build_time_seconds") != null:
			u.build_ticks = _secs(bs["build_time_seconds"], id + " build_time_seconds", rep)
		if bs.get("health") != null:
			u.health = DefNumParse.whole(bs["health"], id + " health", rep)
		if bs.get("movement_speed") != null:
			u.speed = DefConvert.cells_s_to_upt(DefNumParse.milli(bs["movement_speed"], id + " movement_speed", rep))
		u.repair_cost_bp = data.economy.repair_cost_bp


# ------------------------------------------------------------------- research / powers / superweapons
static func _ingest_rules(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var br: Dictionary = _entries(src, "research")
	for i: int in data.ids.count(DefEnums.Kind.RESEARCH):
		var id: String = data.ids.id_of(DefEnums.Kind.RESEARCH, i)
		var e: Dictionary = br[id]
		var r: DefResearch = DefResearch.new()
		r.id = id
		r.index = i
		r.ui_name = str(e.get("name", ""))
		r.ui_effect_text = str(e.get("effect_text", ""))
		r.faction = _ref(data, DefEnums.Kind.FACTION, e.get("faction_id"), id, rep, src)
		r.introduced_by = _ref(data, DefEnums.Kind.ROSTER, e.get("introduced_by_roster_id"), id, rep, src)
		r.tier = DefNumParse.whole(e.get("tier", 2), id + " tier", rep)
		r.cost = DefNumParse.whole(e.get("cost_credits", 0), id + " cost_credits", rep)
		r.time_t = _secs(e.get("research_time_seconds", 0), id + " research_time_seconds", rep)
		r.requires_mask = _mask_of_structs(_ref_list(data, DefEnums.Kind.STRUCTURE, e.get("requires_all_structure_ids", []), id, rep, src, true))
		r.inherited = bool(e.get("inherited_by_all_subfactions", false))
		data.research.append(r)
	var bp: Dictionary = _entries(src, "support_powers")
	for i: int in data.ids.count(DefEnums.Kind.POWER):
		var id: String = data.ids.id_of(DefEnums.Kind.POWER, i)
		var e: Dictionary = bp[id]
		var p: DefPower = DefPower.new()
		p.id = id
		p.index = i
		p.ui_name = str(e.get("name", ""))
		p.ui_effect_text = str(e.get("effect_text", ""))
		p.faction = _ref(data, DefEnums.Kind.FACTION, e.get("faction_id"), id, rep, src)
		p.introduced_by = _ref(data, DefEnums.Kind.ROSTER, e.get("introduced_by_roster_id"), id, rep, src)
		p.tier = DefNumParse.whole(e.get("tier", 2), id + " tier", rep)
		p.cost = DefNumParse.whole(e.get("cost_credits", 0), id + " cost_credits", rep)
		p.cooldown_t = _secs(e.get("cooldown_seconds", 0), id + " cooldown_seconds", rep)
		p.requires_mask = _mask_of_structs(_ref_list(data, DefEnums.Kind.STRUCTURE, e.get("requires_all_structure_ids", []), id, rep, src, true))
		p.requires_powered = bool(e.get("requires_powered_prerequisites", false))
		data.powers.append(p)
	var bs: Dictionary = _entries(src, "superweapons")
	for i: int in data.ids.count(DefEnums.Kind.SUPERWEAPON):
		var id: String = data.ids.id_of(DefEnums.Kind.SUPERWEAPON, i)
		var e: Dictionary = bs[id]
		var w: DefSuperweapon = DefSuperweapon.new()
		w.id = id
		w.index = i
		w.ui_name = str(e.get("name", ""))
		w.ui_text = str(e.get("effect_text", ""))
		w.faction = _ref(data, DefEnums.Kind.FACTION, e.get("faction_id"), id, rep, src)
		w.launcher = _ref(data, DefEnums.Kind.STRUCTURE, e.get("launcher_structure_id"), id, rep, src)
		w.requires_mask = _mask_of_structs(_ref_list(data, DefEnums.Kind.STRUCTURE, e.get("requires_all_structure_ids", []), id, rep, src, true))
		w.recharge_t = _secs(e.get("recharge_seconds", 0), id + " recharge_seconds", rep)
		w.warning_t = _secs(e.get("warning_seconds", 0), id + " warning_seconds", rep)
		w.max_charges = DefNumParse.whole(e.get("maximum_stored_charges", 1), id + " maximum_stored_charges", rep)
		w.starts_charged = bool(e.get("starts_charged", false))
		if w.launcher >= 0:
			data.structures[w.launcher].superweapon = i
		data.superweapons.append(w)


# -------------------------------------------------------------------------------- factions / rosters
static func _ingest_factions_rosters(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var bf: Dictionary = _entries(src, "factions")
	for i: int in data.ids.count(DefEnums.Kind.FACTION):
		var id: String = data.ids.id_of(DefEnums.Kind.FACTION, i)
		var e: Dictionary = bf[id]
		var f: DefFaction = DefFaction.new()
		f.id = id
		f.index = i
		f.ui_name = str(e.get("name", ""))
		f.code = str(e.get("code", ""))
		f.ui_motto = str(e.get("motto", ""))
		f.ui_lore = str(e.get("lore", ""))
		f.ui_identity = str(e.get("identity", ""))
		f.ui_opening = str(e.get("opening", ""))
		f.ui_counterplay = str(e.get("counterplay", ""))
		f.pres_palette = str(e.get("visual_direction", ""))
		var traits: Variant = e.get("traits_text", [])
		if traits is Array:
			for t: Variant in traits:
				f.ui_traits.append(str(t))
		f.baseline_units = _ref_list(data, DefEnums.Kind.UNIT, e.get("baseline_combat_unit_ids", []), id, rep, src, false)
		f.structures = _ref_list(data, DefEnums.Kind.STRUCTURE, e.get("structure_ids", []), id, rep, src, false)
		f.shared_research = _ref_list(data, DefEnums.Kind.RESEARCH, e.get("shared_research_ids", []), id, rep, src, false)
		f.shared_powers = _ref_list(data, DefEnums.Kind.POWER, e.get("shared_support_power_ids", []), id, rep, src, false)
		f.vanilla_power = _ref(data, DefEnums.Kind.POWER, e.get("vanilla_only_support_power_id"), id, rep, src)
		f.superweapon = _ref(data, DefEnums.Kind.SUPERWEAPON, e.get("superweapon_id"), id, rep, src)
		f.vanilla_roster = _ref(data, DefEnums.Kind.ROSTER, e.get("vanilla_roster_id"), id, rep, src)
		f.sub_rosters = _ref_list(data, DefEnums.Kind.ROSTER, e.get("subfaction_roster_ids", []), id, rep, src, false)
		f.passive_modifiers = _ref_list(data, DefEnums.Kind.MODIFIER, e.get("passive_modifier_ids", []), id, rep, src, false)
		data.factions.append(f)
	var br: Dictionary = _entries(src, "rosters")
	var nu: int = data.units.size()
	var ns: int = data.structures.size()
	var hq: int = -1
	for s: DefStructure in data.structures:
		if (s.flags & DefEnums.SF_NO_BUILD) != 0:
			hq = s.index
	for i: int in data.ids.count(DefEnums.Kind.ROSTER):
		var id: String = data.ids.id_of(DefEnums.Kind.ROSTER, i)
		var e: Dictionary = br[id]
		var r: DefRoster = DefRoster.new()
		_shape_roster(r, nu, ns)
		r.id = id
		r.index = i
		r.faction = _ref(data, DefEnums.Kind.FACTION, e.get("faction_id"), id, rep, src)
		r.parent = _ref(data, DefEnums.Kind.ROSTER, e.get("parent_roster_id"), id, rep, src)
		r.is_vanilla = str(e.get("kind", "")) == "vanilla"
		r.ui_title = str(e.get("title", ""))
		r.ui_identity = str(e.get("identity", ""))
		r.ui_lore = str(e.get("lore", ""))
		r.ui_opening = str(e.get("opening", ""))
		r.ui_counterplay = str(e.get("counterplay", ""))
		_set_start(data, r, hq)
		data.rosters.append(r)
	data.base_roster = DefRoster.new()
	_shape_roster(data.base_roster, nu, ns)
	data.base_roster.id = "roster.base"
	_set_start(data, data.base_roster, hq)


static func _shape_roster(r: DefRoster, nu: int, ns: int) -> void:
	r.units.resize(nu)
	r.structures.resize(ns)


static func _set_start(data: GameData, r: DefRoster, hq: int) -> void:
	r.hq_idx = hq
	r.mcv_idx = data.structures[hq].deploy_unit if hq >= 0 else -1


# ------------------------------------------------------------------------------ selectors / modifiers
static func _cond_of(conds: Variant, where: String, rep: DefLoadReport, src: DefSources) -> int:
	if not (conds is Array) or (conds as Array).is_empty():
		return DefEnums.Cond.NONE
	var arr: Array = conds
	if arr.size() > 1:
		rep.error("V-MOD-04", src.where(src.bible_path, where), "more than one condition on a selector")
	match str(arr[0]):
		DefEnums.COND_TEXT_ON_WATER:
			return DefEnums.Cond.ON_WATER
		DefEnums.COND_TEXT_GARRISON:
			return DefEnums.Cond.IN_CIVILIAN_GARRISON
		DefEnums.COND_TEXT_PAID_REPAIR:
			return DefEnums.Cond.PAID_VEHICLE_REPAIR
	rep.error("V-MOD-04", src.where(src.bible_path, where), "unknown condition string '%s'" % str(arr[0]))
	return DefEnums.Cond.NONE


static func _ingest_selectors_modifiers(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var raw: Dictionary = {}
	for k: Variant in _entries(src, "selectors").keys():
		raw[str(k)] = _entries(src, "selectors")[k]
	for f: String in ["research_effects.json", "power_actions.json", "zone_templates.json", "faction_traits.json"]:
		if src.balance.has(f):
			var sd: Dictionary = src.balance[f].get("selectors", {})
			for k: Variant in sd.keys():
				raw[str(k)] = sd[k]
	var resolver: Script = _hook_script("def_resolver")
	for i: int in data.ids.count(DefEnums.Kind.SELECTOR):
		var id: String = data.ids.id_of(DefEnums.Kind.SELECTOR, i)
		var sel: DefSelector = null
		if resolver != null:
			sel = resolver.call("compile_selector", data, raw[id], id, rep) as DefSelector
		if sel == null:
			sel = DefSelector.new()
		sel.id = id
		sel.index = i
		sel.kind = DefEnums.Kind.SELECTOR
		data.selectors.append(sel)
	var bm: Dictionary = _entries(src, "modifiers")
	var bsel: Dictionary = _entries(src, "selectors")
	for i: int in data.ids.count(DefEnums.Kind.MODIFIER):
		var id: String = data.ids.id_of(DefEnums.Kind.MODIFIER, i)
		var e: Dictionary = bm[id]
		var m: DefModifier = DefModifier.new()
		m.id = id
		m.index = i
		m.ui_source_text = str(e.get("source_text", ""))
		var oid: String = str(e.get("owner_id", ""))
		m.owner_is_roster = oid.begins_with("roster.")
		m.owner = data.ids.index_of(DefEnums.Kind.ROSTER if m.owner_is_roster else DefEnums.Kind.FACTION, oid)
		if m.owner < 0:
			rep.error("V-REF-01", src.where(src.bible_path, id), "unknown modifier owner '%s'" % oid)
		var layer: String = str(e.get("layer", ""))
		m.layer = 2 if layer == "subfaction" else 1
		if layer != "subfaction" and layer != "parent_faction":
			rep.error("V-MOD-03", src.where(src.bible_path, id), "unknown layer '%s'" % layer)
		if str(e.get("operation", "")) != "add_percent_within_layer":
			rep.error("V-SCH-03", src.where(src.bible_path, id), "unknown operation '%s'" % str(e.get("operation", "")))
		m.stat = DefEnums.STAT_NAMES.find(str(e.get("stat", "")))
		if m.stat < 0 or m.stat >= DefEnums.STAT_COUNT_BIBLE:
			rep.error("V-MOD-01", src.where(src.bible_path, id), "unknown stat '%s'" % str(e.get("stat", "")))
			m.stat = 0
		m.delta_bp = DefNumParse.whole(e.get("delta_percent", 0), id + " delta_percent", rep) * 100
		var sid: String = str(e.get("selector_id", ""))
		m.selector = data.ids.index_of(DefEnums.Kind.SELECTOR, sid)
		if m.selector < 0:
			rep.error("V-REF-01", src.where(src.bible_path, id), "unknown selector '%s'" % sid)
		elif bsel.has(sid):
			m.cond = _cond_of((bsel[sid] as Dictionary).get("conditions", []), sid, rep, src)
		data.modifiers.append(m)


# ------------------------------------------------------------------------------------ derived (P5-lite)
static func _derive(data: GameData) -> void:
	var producers: Dictionary = {}
	for u: DefUnit in data.units:
		if u.replaces >= 0:
			var t: DefUnit = data.units[u.replaces]
			t.replaced_by.append(u.index)
		if u.unit_class <= DefEnums.UnitClass.UNIQUE and u.producer >= 0:
			u.flags |= DefEnums.UF_PRODUCIBLE
			producers[u.producer] = true
	for s: DefStructure in data.structures:
		var short: String = s.id.get_slice(".", 2)
		var is_hq: bool = (s.flags & DefEnums.SF_NO_BUILD) != 0
		if (s.tags & DefEnums.ST_DEFENSE) != 0:
			s.flags |= DefEnums.SF_POWERED_DEFENSE
		if (s.tags & DefEnums.ST_SUPERWEAPON) != 0:
			s.flags |= DefEnums.SF_STRATEGIC
		if (s.tags & DefEnums.ST_RELAY) != 0:
			s.flags |= DefEnums.SF_RELAY
		if producers.has(s.index):
			s.flags |= DefEnums.SF_PRODUCTION
		if not is_hq:
			s.flags |= DefEnums.SF_SELLABLE | DefEnums.SF_REPAIRABLE
		if is_hq or producers.has(s.index) or (s.flags & DefEnums.SF_STRATEGIC) != 0:
			s.flags |= DefEnums.SF_CAPTURE_IMMUNE
		if is_hq:
			s.build_radius = data.economy.build_radius_u
		if s.faction < 0 and _QUEUE_OF.has(short) and producers.has(s.index):
			s.queue_kind = _QUEUE_OF[short]
