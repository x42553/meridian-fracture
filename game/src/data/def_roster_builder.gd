class_name DefRosterBuilder
extends RefCounted
## Roster resolution (data_balance 5.7): availability, spawnables, deep clones, unit overrides, static modifier fold
## (DefResolver), trait grants, research / power lists, producible orderings and the V-ROS-01 self-check against the
## bible's derived `resolved` block (incl. the 158 golden modifier applications). Hook
## `def_roster_builder.build_all(data, rep)`.

const _COND_TEXT: Dictionary = {
	DefEnums.Cond.ON_WATER: DefEnums.COND_TEXT_ON_WATER,
	DefEnums.Cond.IN_CIVILIAN_GARRISON: DefEnums.COND_TEXT_GARRISON,
	DefEnums.Cond.PAID_VEHICLE_REPAIR: DefEnums.COND_TEXT_PAID_REPAIR,
}
const _UNRESOLVED_TEXT: Array = ["", DefResolver.U1_TEXT, DefResolver.U2_TEXT, DefResolver.U3_TEXT]


static func build_all(data: GameData, rep: DefLoadReport) -> void:
	for i: int in data.rosters.size():
		build_one(data, i, rep)
	build_base(data)
	for i2: int in data.rosters.size():
		for line: String in golden_mismatches(data, data.rosters[i2]):
			rep.error("V-ROS-01", data.rosters[i2].id, line)


## Resolves roster `roster_idx` in place (the shell created by DefLoader) and returns it.
static func build_one(data: GameData, roster_idx: int, rep: DefLoadReport) -> DefRoster:
	var r: DefRoster = data.rosters[roster_idx]
	r.bind(data)
	var f: DefFaction = data.factions[r.faction]
	var braw: Dictionary = {}
	if data._sources != null:
		braw = (data._sources.bible.get("rosters", {}) as Dictionary).get(r.id, {})
	if braw.is_empty():
		rep.error("V-ROS-01", r.id, "the bible roster record is not available")
		return r
	_reset(r, data)
	# 1. availability -------------------------------------------------------------------------------
	var roster_delta: Dictionary = braw.get("delta", {})
	var repl: Dictionary = {}
	var removed: Dictionary = {}
	_check_delta(data, r, f, roster_delta, repl, removed, rep)
	var unit_list: Array[int] = []
	for u: int in f.baseline_units:
		if removed.has(u):
			continue
		unit_list.append(int(repl.get(u, u)))
	for du: DefUnit in data.units:
		if du.unit_class == DefEnums.UnitClass.SERVICE:
			unit_list.append(du.index)
	r.replaced_by = repl
	# lists (5) needed early: spawnables depend on the powers / superweapon of the roster
	r.research_list = f.shared_research.duplicate()
	var ex_r: Variant = braw.get("exclusive_research_id")
	if ex_r != null:
		r.research_list.append(_idx(data, DefEnums.Kind.RESEARCH, str(ex_r), r.id, rep))
	r.power_list = f.shared_powers.duplicate()
	var ex_p: Variant = braw.get("exclusive_support_power_id")
	if ex_p != null:
		r.power_list.append(_idx(data, DefEnums.Kind.POWER, str(ex_p), r.id, rep))
	r.superweapon = f.superweapon
	if r.superweapon >= 0:
		r.superweapon_def = data.superweapons[r.superweapon].copy_resolved()
	var spawn: Array[int] = _spawnables(data, r, unit_list)
	# 2. clone ---------------------------------------------------------------------------------------
	for ui: int in unit_list:
		r.units[ui] = data.units[ui].copy_resolved()
	for si: int in f.structures:
		r.structures[si] = data.structures[si].copy_resolved()
	for sp: int in spawn:
		r.units[sp] = data.units[sp].copy_resolved()
	r.spawnables = PackedInt32Array(spawn)
	_unit_overrides(data, r, braw, rep)
	# 3. modifiers -----------------------------------------------------------------------------------
	r.modifier_list = f.passive_modifiers.duplicate()
	for m: DefModifier in data.modifiers:
		if m.owner_is_roster and m.owner == r.index:
			r.modifier_list.append(m.index)
	DefResolver.apply_modifiers(data, r, rep)
	# 4. trait grants --------------------------------------------------------------------------------
	_apply_grants(data, r, f, rep)
	r.player_params = f.player_params.duplicate(true)
	for u2: DefUnit in r.units:
		if u2 != null:
			DefLoaderBalance.derive_unit(data, u2)
	# 5. producible orderings --------------------------------------------------------------------------
	_producible(data, r)
	return r


## Base roster: every def, no replacements, no modifiers / grants / lists.
static func build_base(data: GameData) -> void:
	var b: DefRoster = data.base_roster
	b.bind(data)
	b.units = []
	b.units.resize(data.units.size())
	b.structures = []
	b.structures.resize(data.structures.size())
	b.producible_units = PackedInt32Array()
	b.producible_structures = PackedInt32Array()
	for u: DefUnit in data.units:
		b.units[u.index] = u.copy_resolved()
	for s: DefStructure in data.structures:
		b.structures[s.index] = s.copy_resolved()
	_producible(data, b)


static func _reset(r: DefRoster, data: GameData) -> void:
	r.units = []
	r.units.resize(data.units.size())
	r.structures = []
	r.structures.resize(data.structures.size())
	r.producible_units = PackedInt32Array()
	r.producible_structures = PackedInt32Array()
	r.spawnables = PackedInt32Array()
	r.modifier_list = PackedInt32Array()
	r.player_params = {}
	r.replaced_by = {}
	r.cond_apps = []
	r._sel_cache.clear()


static func _idx(data: GameData, kind: int, id: String, where: String, rep: DefLoadReport) -> int:
	var i: int = data.ids.index_of(kind, id)
	if i < 0:
		rep.error("V-ROS-02", where, "unknown %s id '%s'" % [DefEnums.KIND_NAMES[kind], id])
	return i


## V-ROS-02 / 03 / 04 on the roster roster_delta; fills `repl` (baseline -> replacement) and `removed` (set of unit indices).
static func _check_delta(data: GameData, r: DefRoster, f: DefFaction, roster_delta: Dictionary, repl: Dictionary, removed: Dictionary, rep: DefLoadReport) -> void:
	var reps: Array = roster_delta.get("replacements", [])
	for d: Variant in reps:
		var a: int = _idx(data, DefEnums.Kind.UNIT, str((d as Dictionary).get("replaced_unit_id", "")), r.id, rep)
		var b: int = _idx(data, DefEnums.Kind.UNIT, str((d as Dictionary).get("replacement_unit_id", "")), r.id, rep)
		if a < 0 or b < 0:
			continue
		repl[a] = b
		if not f.baseline_units.has(a):
			rep.error("V-ROS-02", r.id, "replaced unit '%s' is not a baseline unit of the faction" % data.units[a].id)
		if data.units[b].replaces != a:
			rep.error("V-ROS-02", r.id, "'%s' does not declare replaces '%s'" % [data.units[b].id, data.units[a].id])
		if data.units[b].introduced_by != r.index:
			rep.error("V-ROS-02", r.id, "'%s' is not introduced by this roster" % data.units[b].id)
		if data.units[b].faction != r.faction:
			rep.error("V-ROS-02", r.id, "replacement '%s' belongs to another faction" % data.units[b].id)
		if (data.units[b].tags & data.units[a].tags) != data.units[a].tags:
			rep.error("V-ROS-06", r.id, "replacement '%s' lacks role tags of '%s'" % [data.units[b].id, data.units[a].id])
	for id: Variant in roster_delta.get("removed_without_replacement_unit_ids", []):
		var x: int = _idx(data, DefEnums.Kind.UNIT, str(id), r.id, rep)
		if x >= 0:
			removed[x] = true
			if not f.baseline_units.has(x):
				rep.error("V-ROS-02", r.id, "removed unit '%s' is not a baseline unit of the faction" % str(id))
	for k: Variant in repl.keys():
		if removed.has(k):
			rep.error("V-ROS-03", r.id, "unit '%s' is both replaced and removed" % data.units[int(k)].id)
	var want_repl: int = 0 if r.is_vanilla else 2
	var want_rem: int = 0 if r.is_vanilla else 1
	if repl.size() != want_repl or removed.size() != want_rem:
		rep.error("V-ROS-03", r.id, "expected %d replacements + %d removals, found %d + %d" % [want_repl, want_rem, repl.size(), removed.size()])
	var unavail: Array = roster_delta.get("unavailable_support_power_ids", [])
	var want_un: Array = [] if r.is_vanilla else [data.powers[f.vanilla_power].id if f.vanilla_power >= 0 else ""]
	if unavail != want_un:
		rep.error("V-ROS-04", r.id, "unavailable_support_power_ids %s differ from the faction's vanilla-only power %s" % [str(unavail), str(want_un)])


## Summon / drone defs reachable from the roster's abilities, structures, powers and superweapon (transitive).
static func _spawnables(data: GameData, r: DefRoster, unit_list: Array[int]) -> Array[int]:
	var seen: Dictionary = {}
	var queue: Array[int] = []
	for ui: int in unit_list:
		_collect_from_abilities(data.units[ui].abilities, queue, seen)
	for si: int in data.factions[r.faction].structures:
		_collect_from_abilities(data.structures[si].abilities, queue, seen)
	for p: int in r.power_list:
		if p >= 0:
			for a: DefPowerAction in data.powers[p].actions:
				if a.op == DefEnums.PowerOp.SUMMON:
					_add_spawn(a.summon, queue, seen)
	if r.superweapon_def != null:
		_add_spawn(r.superweapon_def.summon, queue, seen)
		_add_spawn(int(r.superweapon_def.params.get("capsule_summon_idx", -1)), queue, seen)
	var head: int = 0
	while head < queue.size():
		_collect_from_abilities(data.units[queue[head]].abilities, queue, seen)
		head += 1
	var out: Array[int] = []
	for i: int in queue:
		var u: DefUnit = data.units[i]
		if u.faction == r.faction or u.faction < 0:
			out.append(i)
	out.sort()
	return out


static func _add_spawn(idx: int, queue: Array[int], seen: Dictionary) -> void:
	if idx >= 0 and not seen.has(idx):
		seen[idx] = true
		queue.append(idx)


static func _collect_from_abilities(abilities: Array[DefAbility], queue: Array[int], seen: Dictionary) -> void:
	for a: DefAbility in abilities:
		for k: Variant in a.params.keys():
			var v: Variant = a.params[k]
			if v is Array:
				for e: Variant in v:
					if e is Dictionary and (e as Dictionary).has("drone_idx"):
						_add_spawn(int((e as Dictionary)["drone_idx"]), queue, seen)


static func _unit_overrides(data: GameData, r: DefRoster, braw: Dictionary, rep: DefLoadReport) -> void:
	var uo: Dictionary = (braw.get("resolved", {}) as Dictionary).get("unit_overrides", {})
	for id: Variant in uo.keys():
		var i: int = data.unit_idx(str(id))
		var u: DefUnit = r.unit(i)
		if u == null:
			rep.error("V-ROS-02", r.id, "unit override for '%s', which is not in the roster" % str(id))
			continue
		var o: Dictionary = uo[id]
		for t: Variant in o.get("add_tags", []):
			var b: int = data.tags.unit_bit(str(t))
			if b == 0:
				rep.error("V-CNF-05", r.id, "unit override adds unknown tag '%s'" % str(t))
			u.tags |= b
		if o.has("water_speed_fraction_of_land_speed"):
			u.deep_speed_bp = DefNumParse.milli(o["water_speed_fraction_of_land_speed"], r.id, rep) * 10
			if u.move_class == DefEnums.MoveClass.WHEELED or u.move_class == DefEnums.MoveClass.TRACKED:
				u.move_class = DefEnums.MoveClass.AMPHIBIOUS
				u.layer_mask = data.moves.layer_mask[u.move_class]


## Trait grants: adds the ability to every matching roster clone unless it already has that kind (then only when
## `replace` is set the params are overwritten).
static func _apply_grants(data: GameData, r: DefRoster, f: DefFaction, rep: DefLoadReport) -> void:
	for e: DefEffect in f.grants:
		if e.ability == null or e.selector < 0:
			continue
		var sel: DefSelector = data.selectors[e.selector]
		var replace: bool = bool(e.params.get("replace", false))
		for u: DefUnit in r.units:
			if u != null and DefResolver.unit_matches(data, sel, u):
				_grant(u, e.ability, replace, rep, u.id)
		for s: DefStructure in r.structures:
			if s != null and DefResolver.matches_structure(sel, s.tags, s.index, s.weapon_tags):
				_grant(s, e.ability, replace, rep, s.id)


static func _grant(target: Object, ability: DefAbility, replace: bool, rep: DefLoadReport, name: String) -> void:
	var slots: PackedInt32Array = target.get("ability_slot_of_kind")
	if slots.size() > ability.kind and slots[ability.kind] >= 0 and not replace:
		rep.info("V-ROS-08", name, "trait grant skipped: the def already has ability kind %d" % ability.kind)
		return
	DefLoaderBalance.put_ability(target, ability.copy_resolved())


static func _producible(data: GameData, r: DefRoster) -> void:
	var us: Array[int] = []
	for u: DefUnit in r.units:
		if u != null and (u.flags & DefEnums.UF_PRODUCIBLE) != 0:
			us.append(u.index)
	us.sort_custom(func(a: int, b: int) -> bool:
		var ua: DefUnit = r.units[a]
		var ub: DefUnit = r.units[b]
		if ua.tier != ub.tier:
			return ua.tier < ub.tier
		if ua.cost != ub.cost:
			return ua.cost < ub.cost
		return a < b)
	r.producible_units = PackedInt32Array(us)
	var depth: Dictionary = {}
	var ss: Array[int] = []
	for s: DefStructure in r.structures:
		if s != null and (s.flags & DefEnums.SF_NO_BUILD) == 0:
			ss.append(s.index)
	ss.sort_custom(func(a: int, b: int) -> bool:
		var da: int = _depth(data, a, depth, 0)
		var db: int = _depth(data, b, depth, 0)
		if da != db:
			return da < db
		var sa: DefStructure = r.structures[a]
		var sb: DefStructure = r.structures[b]
		if sa.cost != sb.cost:
			return sa.cost < sb.cost
		return a < b)
	r.producible_structures = PackedInt32Array(ss)


## Longest prerequisite chain of a structure (0 = none).
static func _depth(data: GameData, s: int, memo: Dictionary, guard: int) -> int:
	if memo.has(s):
		return memo[s]
	var d: int = 0
	if guard < 16:
		for q: int in data.structures[s].requires:
			d = maxi(d, 1 + _depth(data, q, memo, guard + 1))
	memo[s] = d
	return d


# ============================================================================================ self check
## Compares a resolved roster with the bible's derived block; one line per mismatch (empty = V-ROS-01 clean).
static func golden_mismatches(data: GameData, r: DefRoster) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if data._sources == null:
		return out
	var braw: Dictionary = (data._sources.bible.get("rosters", {}) as Dictionary).get(r.id, {})
	var res: Dictionary = braw.get("resolved", {})
	if res.is_empty():
		out.append("no resolved block in the bible")
		return out
	var combat: Array = []
	var service: Array = []
	for u: DefUnit in r.units:
		if u == null:
			continue
		if u.unit_class == DefEnums.UnitClass.SERVICE:
			service.append(u.id)
		elif u.unit_class == DefEnums.UnitClass.BASELINE or u.unit_class == DefEnums.UnitClass.UNIQUE:
			combat.append(u.id)
	_cmp_set(out, "combat_unit_ids", combat, res.get("combat_unit_ids", []))
	_cmp_set(out, "service_unit_ids", service, res.get("service_unit_ids", []))
	var structs: Array = []
	for s: DefStructure in r.structures:
		if s != null:
			structs.append(s.id)
	_cmp_set(out, "structure_ids", structs, res.get("structure_ids", []))
	_cmp_list(out, "research_ids", _ids_of(data, DefEnums.Kind.RESEARCH, r.research_list), res.get("research_ids", []))
	_cmp_list(out, "support_power_ids", _ids_of(data, DefEnums.Kind.POWER, r.power_list), res.get("support_power_ids", []))
	if data.ids.id_of(DefEnums.Kind.SUPERWEAPON, r.superweapon) != str(res.get("superweapon_id", "")):
		out.append("superweapon_id differs")
	_cmp_list(out, "modifier_ids", _ids_of(data, DefEnums.Kind.MODIFIER, r.modifier_list), res.get("modifier_ids", []))
	_check_applications(data, r, res, out)
	_check_tech(data, r, res, out)
	return out


static func _ids_of(data: GameData, kind: int, list: PackedInt32Array) -> Array:
	var out: Array = []
	for i: int in list:
		out.append(data.ids.id_of(kind, i))
	return out


static func _cmp_list(out: PackedStringArray, what: String, have: Array, want: Array) -> void:
	if have != want:
		out.append("%s differ: %s vs bible %s" % [what, str(have), str(want)])


static func _cmp_set(out: PackedStringArray, what: String, have: Array, want: Array) -> void:
	var a: Array = have.duplicate()
	var b: Array = want.duplicate()
	a.sort()
	b.sort()
	if a != b:
		out.append("%s differ (%d vs bible %d)" % [what, a.size(), b.size()])


static func _check_applications(data: GameData, r: DefRoster, res: Dictionary, out: PackedStringArray) -> void:
	var apps: Array = res.get("modifier_applications", [])
	var seen: Array = []
	for a: Variant in apps:
		var ad: Dictionary = a
		var mid: String = str(ad.get("modifier_id", ""))
		seen.append(mid)
		var mi: int = data.ids.index_of(DefEnums.Kind.MODIFIER, mid)
		if mi < 0:
			out.append("application of unknown modifier '%s'" % mid)
			continue
		var m: DefModifier = data.modifiers[mi]
		var sel: DefSelector = data.selectors[m.selector]
		var units: Array = []
		for ui: int in r.selector_units(m.selector):
			if r.units[ui].id.begins_with("unit."):
				units.append(r.units[ui].id)
		_cmp_set(out, mid + " eligible_unit_ids", units, ad.get("eligible_unit_ids", []))
		var structs: Array = []
		for si: int in r.selector_structures(m.selector):
			structs.append(r.structures[si].id)
		_cmp_set(out, mid + " eligible_structure_ids", structs, ad.get("eligible_structure_ids", []))
		var sw: Array = []
		if r.superweapon >= 0 and sel.extra_superweapons.has(r.superweapon):
			sw.append(data.ids.id_of(DefEnums.Kind.SUPERWEAPON, r.superweapon))
		if sw != ad.get("eligible_superweapon_ids", []):
			out.append("%s eligible_superweapon_ids differ" % mid)
		var conds: Array = []
		if sel.cond != DefEnums.Cond.NONE:
			conds.append(_COND_TEXT[sel.cond])
		if conds != ad.get("conditions", []):
			out.append("%s conditions differ" % mid)
		var dom: Variant = ad.get("unresolved_target_domain")
		if str(_UNRESOLVED_TEXT[sel.unresolved]) != ("" if dom == null else str(dom)):
			out.append("%s unresolved_target_domain differs" % mid)
	var want_ids: Array = _ids_of(data, DefEnums.Kind.MODIFIER, r.modifier_list)
	seen.sort()
	want_ids.sort()
	if seen != want_ids:
		out.append("modifier_applications cover %d modifiers, the roster has %d" % [seen.size(), want_ids.size()])


static func _check_tech(data: GameData, r: DefRoster, res: Dictionary, out: PackedStringArray) -> void:
	for n: Variant in res.get("technology_nodes", []):
		var nd: Dictionary = n
		var u: DefUnit = r.unit(data.unit_idx(str(nd.get("unit_id", ""))))
		if u == null:
			out.append("technology node for a unit that is not in the roster: %s" % str(nd.get("unit_id", "")))
			continue
		if data.ids.id_of(DefEnums.Kind.STRUCTURE, u.producer) != str(nd.get("producer_structure_id", "")):
			out.append("%s producer differs from the technology node" % u.id)
		var want: Array = []
		for q: Variant in nd.get("requires_all_structure_ids", []):
			want.append(data.structure_idx(str(q)))
		want.sort()
		var have: Array = []
		for q2: int in u.requires:
			have.append(q2)
		have.sort()
		if have != want:
			out.append("%s prerequisites differ from the technology node" % u.id)
