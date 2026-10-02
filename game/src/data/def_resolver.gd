class_name DefResolver
extends RefCounted
## Selector compilation + matching and the static modifier fold (data_balance 5.4 / 5.5 / 5.9). `compile_selector` is
## called by DefLoader for every named selector (bible + balance) and by DefLoaderEffects for inline ones; the fold
## (`apply_modifiers`) is called by DefRosterBuilder once per roster on the roster's own clones.

const UNMATCHABLE: int = 1 << 62  ## a tag bit no namespace ever uses (bits 0..61): `all` clause that can never hold
const _KIND_OF: Dictionary = {
	"unit": DefEnums.Kind.UNIT, "structure": DefEnums.Kind.STRUCTURE, "weapon": DefEnums.Kind.WEAPON_ARCH,
	"projectile": DefEnums.Kind.PROJECTILE,
}
const _CLASS_OF: Dictionary = {
	"service": DefEnums.UnitClass.SERVICE, "baseline": DefEnums.UnitClass.BASELINE, "unique": DefEnums.UnitClass.UNIQUE,
	"summon": DefEnums.UnitClass.SUMMON, "drone": DefEnums.UnitClass.DRONE,
}
const U1_TEXT: String = "Carrier-launched drones are also unmanned, but their pricing/replacement costs are unspecified."
const U2_TEXT: String = "Thermal-beam weapons and defenses; exact weapon registry is not yet specified."
const U3_TEXT: String = "Ordinary guided-missile projectile templates; exact weapon registry is not yet specified."
const _UNIT_LEVEL_STATS: PackedInt32Array = [
	DefEnums.Stat.COST, DefEnums.Stat.BUILD_TIME, DefEnums.Stat.HEALTH, DefEnums.Stat.SPEED, DefEnums.Stat.SIGHT,
	DefEnums.Stat.REARM, DefEnums.Stat.POWER, DefEnums.Stat.REPAIR_RATE, DefEnums.Stat.REPAIR_COST,
]


# ------------------------------------------------------------------------------------------- compilation
## Compiles a bible selector (`entity_kinds` shape) or an inline selector (`kinds` shape) into a DefSelector.
static func compile_selector(data: GameData, src: Dictionary, id: String, rep: DefLoadReport) -> DefSelector:
	var s: DefSelector = DefSelector.new()
	s.id = id
	var bible: bool = src.has("entity_kinds")
	var kinds: Array = _arr(src, "entity_kinds" if bible else "kinds").duplicate()
	var all_names: Array = _arr(src, "all_tags" if bible else "tags_all")
	var any_names: Array = _arr(src, "any_tags" if bible else "tags_any")
	var none_names: Array = _arr(src, "exclude_tags" if bible else "tags_none")
	var unit_ids: Array = []
	var struct_ids: Array = []
	if bible:
		for e: Variant in _arr(src, "explicit_entity_ids"):
			var es: String = str(e)
			if es.begins_with("structure."):
				struct_ids.append(es)
			else:
				unit_ids.append(es)
	else:
		unit_ids = _arr(src, "unit_ids")
		struct_ids = _arr(src, "structure_ids")
		if kinds.is_empty():
			if not unit_ids.is_empty():
				kinds.append("unit")
			if not struct_ids.is_empty():
				kinds.append("structure")
			if kinds.is_empty():
				kinds.append("unit")
	for k: Variant in kinds:
		if not _KIND_OF.has(str(k)):
			rep.error("V-SCH-03", id, "unknown selector entity kind '%s'" % str(k))
			continue
		s.kind_mask |= 1 << int(_KIND_OF[str(k)])
	var dead_kinds: int = 0
	var live_kinds: int = 0
	for kk: int in [DefEnums.Kind.UNIT, DefEnums.Kind.STRUCTURE, DefEnums.Kind.WEAPON_ARCH, DefEnums.Kind.PROJECTILE]:
		if (s.kind_mask & (1 << kk)) == 0:
			continue
		var all_m: int = 0
		var dead: bool = false
		for n: Variant in all_names:
			var b: int = _tag_bit(data, kk, str(n))
			if b == 0:
				dead = true
			all_m |= b
		var any_m: int = _mask_ignoring_unknown(data, kk, any_names, id, "any_tags", rep)
		var none_m: int = _mask_ignoring_unknown(data, kk, none_names, id, "exclude_tags", rep)
		if dead:
			all_m |= UNMATCHABLE
			dead_kinds += 1
		else:
			live_kinds += 1
		_store_clauses(s, kk, all_m, any_m, none_m)
	if dead_kinds > 0 and live_kinds == 0:
		rep.error("V-MOD-02", id, "selector can never match: an all_tags member is unknown in every listed namespace")
	var eu: PackedInt32Array = PackedInt32Array()
	for e: Variant in unit_ids:
		var ix: int = data.ids.index_of(DefEnums.Kind.UNIT, str(e))
		if ix < 0:
			rep.error("V-REF-01", id, "unknown unit id '%s'" % str(e))
		else:
			eu.append(ix)
	eu.sort()
	s.explicit_units = eu
	var es2: PackedInt32Array = PackedInt32Array()
	for e: Variant in struct_ids:
		var ix2: int = data.ids.index_of(DefEnums.Kind.STRUCTURE, str(e))
		if ix2 < 0:
			rep.error("V-REF-01", id, "unknown structure id '%s'" % str(e))
		else:
			es2.append(ix2)
	es2.sort()
	s.explicit_structs = es2
	s.include_replacements = DefLoaderBalance.truthy(src.get("include_replacements"))
	for c: Variant in _arr(src, "classes"):
		if _CLASS_OF.has(str(c)):
			s.unit_class_mask |= 1 << int(_CLASS_OF[str(c)])
		else:
			rep.error("V-SCH-03", id, "unknown unit class '%s'" % str(c))
	var hw: Array = _arr(src, "has_weapon_tags")
	for t: Variant in hw:
		var wb: int = data.tags.weapon_bit(str(t))
		if wb == 0:
			rep.error("V-MOD-02", id, "unknown weapon tag '%s' in has_weapon_tags" % str(t))
		s.has_weapon_mask |= wb
	var sw: PackedInt32Array = PackedInt32Array()
	for e: Variant in _arr(src, "additional_superweapon_ids"):
		var sx: int = data.ids.index_of(DefEnums.Kind.SUPERWEAPON, str(e))
		if sx < 0:
			rep.error("V-REF-01", id, "unknown superweapon id '%s'" % str(e))
		else:
			sw.append(sx)
	sw.sort()
	s.extra_superweapons = sw
	s.cond = _cond_code(src.get("conditions", []), id, rep)
	var dom: Variant = src.get("unresolved_target_domain")
	if dom != null:
		match str(dom):
			U1_TEXT:
				s.unresolved = 1
			U2_TEXT:
				s.unresolved = 2
				s.weapon_all |= DefEnums.WT_THERMAL_BEAM
				s.proj_all |= DefEnums.WT_THERMAL_BEAM
			U3_TEXT:
				s.unresolved = 3
				s.weapon_all |= DefEnums.WT_GUIDED_MISSILE
				s.proj_all |= DefEnums.WT_GUIDED_MISSILE
			_:
				rep.error("V-MOD-05", id, "unknown unresolved_target_domain '%s'" % str(dom))
	return s


## `d[key]` when it is an array, else an empty one (a junk / null value is reported by the shape guard).
static func _arr(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key)
	return v if v is Array else []


static func _tag_bit(data: GameData, kind: int, name: String) -> int:
	match kind:
		DefEnums.Kind.UNIT:
			return data.tags.unit_bit(name)
		DefEnums.Kind.STRUCTURE:
			return data.tags.structure_bit(name)
		DefEnums.Kind.WEAPON_ARCH:
			return data.tags.weapon_bit(name)
	return data.tags.projectile_bit(name)


static func _mask_ignoring_unknown(data: GameData, kind: int, names: Array, id: String, clause: String, rep: DefLoadReport) -> int:
	var m: int = 0
	for n: Variant in names:
		var b: int = _tag_bit(data, kind, str(n))
		if b == 0:
			rep.warn("V-MOD-02", id, "%s: tag '%s' is unknown in the %s namespace and is ignored" % [clause, str(n), DefEnums.KIND_NAMES[kind]])
		m |= b
	return m


static func _store_clauses(s: DefSelector, kind: int, all_m: int, any_m: int, none_m: int) -> void:
	match kind:
		DefEnums.Kind.UNIT:
			s.unit_all |= all_m
			s.unit_any |= any_m
			s.unit_none |= none_m
		DefEnums.Kind.STRUCTURE:
			s.struct_all |= all_m
			s.struct_any |= any_m
			s.struct_none |= none_m
		DefEnums.Kind.WEAPON_ARCH:
			s.weapon_all |= all_m
			s.weapon_any |= any_m
			s.weapon_none |= none_m
		_:
			s.proj_all |= all_m
			s.proj_any |= any_m
			s.proj_none |= none_m


static func _cond_code(conds: Variant, id: String, rep: DefLoadReport) -> int:
	if not (conds is Array) or (conds as Array).is_empty():
		return DefEnums.Cond.NONE
	var arr: Array = conds
	if arr.size() > 1:
		rep.error("V-MOD-04", id, "more than one condition on a selector")
	match str(arr[0]):
		DefEnums.COND_TEXT_ON_WATER:
			return DefEnums.Cond.ON_WATER
		DefEnums.COND_TEXT_GARRISON:
			return DefEnums.Cond.IN_CIVILIAN_GARRISON
		DefEnums.COND_TEXT_PAID_REPAIR:
			return DefEnums.Cond.PAID_VEHICLE_REPAIR
	rep.error("V-MOD-04", id, "unknown condition string '%s'" % str(arr[0]))
	return DefEnums.Cond.NONE


# ----------------------------------------------------------------------------------------------- matching
static func _clauses_hold(t: int, all_m: int, any_m: int, none_m: int) -> bool:
	return (t & all_m) == all_m and (any_m == 0 or (t & any_m) != 0) and (t & none_m) == 0


static func matches_unit(sel: DefSelector, unit_tags: int, unit_idx: int, unit_class: int, weapon_tags: int) -> bool:
	if (sel.kind_mask & (1 << DefEnums.Kind.UNIT)) == 0:
		return false
	if not sel.explicit_units.is_empty() and not sel.explicit_units.has(unit_idx):
		return false
	return _unit_clauses(sel, unit_tags, unit_class, weapon_tags)


static func _unit_clauses(sel: DefSelector, unit_tags: int, unit_class: int, weapon_tags: int) -> bool:
	if not _clauses_hold(unit_tags, sel.unit_all, sel.unit_any, sel.unit_none):
		return false
	if sel.unit_class_mask != 0 and (sel.unit_class_mask & (1 << unit_class)) == 0:
		return false
	return sel.has_weapon_mask == 0 or (weapon_tags & sel.has_weapon_mask) != 0


static func matches_structure(sel: DefSelector, struct_tags: int, struct_idx: int, weapon_tags: int) -> bool:
	if (sel.kind_mask & (1 << DefEnums.Kind.STRUCTURE)) == 0:
		return false
	if not sel.explicit_structs.is_empty() and not sel.explicit_structs.has(struct_idx):
		return false
	if not _clauses_hold(struct_tags, sel.struct_all, sel.struct_any, sel.struct_none):
		return false
	return sel.has_weapon_mask == 0 or (weapon_tags & sel.has_weapon_mask) != 0


static func matches_weapon(sel: DefSelector, weapon_tags: int) -> bool:
	if (sel.kind_mask & (1 << DefEnums.Kind.WEAPON_ARCH)) == 0:
		return false
	return _clauses_hold(weapon_tags, sel.weapon_all, sel.weapon_any, sel.weapon_none)


static func matches_projectile(sel: DefSelector, proj_tags: int) -> bool:
	if (sel.kind_mask & (1 << DefEnums.Kind.PROJECTILE)) == 0:
		return false
	return _clauses_hold(proj_tags, sel.proj_all, sel.proj_any, sel.proj_none)


## Unit match including the `include_replacements` closure (an explicit id also matches every unit whose `replaces`
## chain reaches it; depth cap 4). `u` is a base def or a roster clone (tags = roster-effective mask).
static func unit_matches(data: GameData, sel: DefSelector, u: DefUnit) -> bool:
	if matches_unit(sel, u.tags, u.index, u.unit_class, u.weapon_tags):
		return true
	if not sel.include_replacements or sel.explicit_units.is_empty() or (sel.kind_mask & (1 << DefEnums.Kind.UNIT)) == 0:
		return false
	var cur: int = u.replaces
	var depth: int = 0
	while cur >= 0 and depth < 4:
		if sel.explicit_units.has(cur):
			# the explicit id is satisfied through the chain: the remaining clauses use the unit's own values
			return _unit_clauses(sel, u.tags, u.unit_class, u.weapon_tags)
		cur = data.units[cur].replaces
		depth += 1
	return false


# ---------------------------------------------------------------------------------------- modifier folding
## Applies the roster's modifier list (r.modifier_list) to the roster's own clones (data_balance 5.5): accumulates the
## layer sums per (target, slot, stat), folds with ONE rounding (DefStatMath.resolve_static), handles the three
## supported conditional combinations and scales the superweapon packets. Fills r.sums_s1/sums_s2, r.cond_apps.
static func apply_modifiers(data: GameData, r: DefRoster, rep: DefLoadReport) -> void:
	var acc: Dictionary = {}
	var order: Array[int] = []
	var seen: Dictionary = {}
	var apps: Array[DefCondApplication] = []
	var sw_sums: PackedInt32Array = PackedInt32Array([0, 0])
	var sw_hit: bool = false
	var triples: Dictionary = {}
	for mi: int in r.modifier_list:
		var m: DefModifier = data.modifiers[mi]
		if m.selector < 0:
			continue
		var triple: String = "%d:%d:%d:%d" % [1 if m.owner_is_roster else 0, m.owner, m.stat, m.selector]
		if triples.has(triple):
			rep.error("V-MOD-09", m.id, "same (owner, stat, selector) as '%s' in roster %s" % [str(triples[triple]), r.id])
		triples[triple] = m.id
		var sel: DefSelector = data.selectors[m.selector]
		var cond: int = m.cond
		if cond == DefEnums.Cond.PAID_VEHICLE_REPAIR and m.stat == DefEnums.Stat.REPAIR_COST:
			cond = DefEnums.Cond.NONE  # inherently true where the stat is used: folded statically (5.5.5)
		elif cond != DefEnums.Cond.NONE and not _cond_supported(cond, m.stat):
			rep.error("V-MOD-07", m.id, "unsupported conditional modifier combination (cond %d, stat %d)" % [cond, m.stat])
			continue
		var app: DefCondApplication = null
		if m.cond != DefEnums.Cond.NONE:
			app = DefCondApplication.new()
			app.modifier = mi
			app.cond = m.cond
			app.stat = m.stat
			app.delta_bp = m.delta_bp
			app.layer = m.layer
			apps.append(app)
		var ctx: Dictionary = {"acc": acc, "order": order, "seen": seen, "mi": mi, "m": m, "cond": cond, "rep": rep}
		if (sel.kind_mask & (1 << DefEnums.Kind.UNIT)) != 0:
			for u: DefUnit in r.units:
				if u != null and unit_matches(data, sel, u):
					_touch(ctx, 0, u.index, u.weapons.size(), -1)
					if app != null:
						app.units.append(u.index)
		if (sel.kind_mask & (1 << DefEnums.Kind.STRUCTURE)) != 0:
			for s: DefStructure in r.structures:
				if s != null and matches_structure(sel, s.tags, s.index, s.weapon_tags):
					_touch(ctx, 1, s.index, s.weapons.size(), -1)
					if app != null:
						app.structures.append(s.index)
		var by_weapon: bool = (sel.kind_mask & (1 << DefEnums.Kind.WEAPON_ARCH)) != 0
		var by_proj: bool = (sel.kind_mask & (1 << DefEnums.Kind.PROJECTILE)) != 0
		if by_weapon or by_proj:
			for u2: DefUnit in r.units:
				if u2 != null:
					_touch_weapons(data, ctx, sel, 0, u2.index, u2.weapons, by_weapon, by_proj)
			for s2: DefStructure in r.structures:
				if s2 != null:
					_touch_weapons(data, ctx, sel, 1, s2.index, s2.weapons, by_weapon, by_proj)
		if not sel.extra_superweapons.is_empty() and r.superweapon >= 0 and sel.extra_superweapons.has(r.superweapon):
			if m.stat != DefEnums.Stat.DAMAGE:
				rep.error("V-MOD-01", m.id, "a superweapon can only be targeted by DAMAGE modifiers")
			else:
				sw_sums[m.layer - 1] += m.delta_bp
				sw_hit = true
	var n_ok: int = 0
	var n_noop: int = 0
	var d_count: int = maxi(data.units.size(), data.structures.size())
	r.sums_d = d_count
	r.sums_s1 = _zeros(2 * d_count * DefEnums.STAT_COUNT_BIBLE)
	r.sums_s2 = _zeros(2 * d_count * DefEnums.STAT_COUNT_BIBLE)
	for key: int in order:
		var e: PackedInt32Array = acc[key]
		var stat: int = key % 16
		var slot1: int = (key / 16) % 32
		var def_idx: int = (key / 512) % 32768
		var kind_slot: int = key / (512 * 32768)
		if _fold_entry(data, r, kind_slot, def_idx, slot1 - 1, stat, e, rep):
			n_ok += 1
		else:
			n_noop += 1
		var si: int = (kind_slot * d_count + def_idx) * DefEnums.STAT_COUNT_BIBLE + stat
		if slot1 <= 1 and e[5] > 0:
			r.sums_s1[si] = e[0]
			r.sums_s2[si] = e[1]
	if sw_hit and r.superweapon_def != null:
		for p: DefImpactPacket in r.superweapon_def.packets:
			p.damage = DefStatMath.resolve_static(DefEnums.Stat.DAMAGE, p.damage, sw_sums[0], sw_sums[1], data.economy)
	r.cond_apps = apps
	r.applied_count = n_ok
	r.noop_count = n_noop


static func _zeros(n: int) -> PackedInt32Array:
	var a: PackedInt32Array = PackedInt32Array()
	a.resize(n)
	return a


static func _cond_supported(cond: int, stat: int) -> bool:
	if cond == DefEnums.Cond.ON_WATER:
		return stat == DefEnums.Stat.SPEED
	if cond == DefEnums.Cond.IN_CIVILIAN_GARRISON:
		return stat == DefEnums.Stat.DAMAGE
	return false


static func _touch_weapons(data: GameData, ctx: Dictionary, sel: DefSelector, kind_slot: int, def_idx: int, slots: Array, by_weapon: bool, by_proj: bool) -> void:
	for i: int in slots.size():
		var w: DefWeaponSlot = slots[i]
		var tags: int = data.weapon_archs[w.arch].tags
		if (by_weapon and matches_weapon(sel, tags)) or (by_proj and matches_projectile(sel, tags)):
			_touch(ctx, kind_slot, def_idx, slots.size(), i)


## Records one (modifier, target[, slot]) application in the accumulator. `only_slot` < 0 expands a weapon stat to every
## slot of the target; unit-level stats use slot index 0 of the key.
static func _touch(ctx: Dictionary, kind_slot: int, def_idx: int, slot_count: int, only_slot: int) -> void:
	var m: DefModifier = ctx["m"]
	var acc: Dictionary = ctx["acc"]
	var seen: Dictionary = ctx["seen"]
	var slot_stat: bool = m.stat == DefEnums.Stat.DAMAGE or m.stat == DefEnums.Stat.RANGE or m.stat == DefEnums.Stat.RELOAD or m.stat == DefEnums.Stat.PROJ_SPEED
	var slots: Array[int] = []
	if not slot_stat:
		slots.append(-1)
	elif only_slot >= 0:
		slots.append(only_slot)
	else:
		for i: int in slot_count:
			slots.append(i)
		if slots.is_empty():
			slots.append(-1)  # weapon stat on an unarmed target: folds as a no-op (base 0)
	for sl: int in slots:
		var slot1: int = maxi(sl, -1) + 1
		var key: int = (((kind_slot * 32768 + def_idx) * 32) + slot1) * 16 + m.stat
		var dedupe: int = key * 1000 + int(ctx["mi"])
		if seen.has(dedupe):
			continue
		seen[dedupe] = true
		var e: PackedInt32Array
		if acc.has(key):
			e = acc[key]
		else:
			e = PackedInt32Array([0, 0, 0, 0, 0, 0])
			acc[key] = e
			(ctx["order"] as Array[int]).append(key)
		var cond: int = ctx["cond"]
		var li: int = m.layer - 1
		if cond == DefEnums.Cond.NONE:
			e[li] += m.delta_bp
			e[5] += 1
		else:
			if e[4] != DefEnums.Cond.NONE and e[4] != cond:
				(ctx["rep"] as DefLoadReport).error("V-MOD-08", m.id, "two different conditions on one (target, stat)")
			e[4] = cond
			e[2 + li] += m.delta_bp


## Folds one accumulator entry into the clone. Returns false for a no-op (base 0 / not applicable).
static func _fold_entry(data: GameData, r: DefRoster, kind_slot: int, def_idx: int, slot: int, stat: int, e: PackedInt32Array, rep: DefLoadReport) -> bool:
	var eco: DefEconomy = data.economy
	var u: DefUnit = r.units[def_idx] if kind_slot == 0 else null
	var s: DefStructure = r.structures[def_idx] if kind_slot == 1 else null
	var s1: int = e[0]
	var s2: int = e[1]
	var has_s: bool = e[5] > 0
	var cond: int = e[4]
	if slot >= 0:
		var slots: Array = u.weapons if u != null else s.weapons
		if slot >= slots.size():
			rep.info("V-MOD-06", _name_of(u, s), "modifier on stat %d has no weapon slot to act on" % stat)
			return false
		var w: DefWeaponSlot = slots[slot]
		return _fold_slot(data, w, stat, s1, s2, e, has_s, cond, _name_of(u, s), rep)
	var base: int = 0
	var name: String = _name_of(u, s)
	match stat:
		DefEnums.Stat.COST:
			base = u.cost if u != null else s.cost
		DefEnums.Stat.BUILD_TIME:
			base = u.build_ticks if u != null else s.build_ticks
		DefEnums.Stat.HEALTH:
			base = u.health if u != null else s.health
		DefEnums.Stat.SPEED:
			base = u.speed if u != null else 0
		DefEnums.Stat.SIGHT:
			base = u.sight if u != null else s.sight
		DefEnums.Stat.REARM:
			base = u.rearm_t if u != null else 0
		DefEnums.Stat.POWER:
			base = s.power if s != null else 0
			if base <= 0:
				base = 0  # only generators (power > 0) take POWER modifiers
		DefEnums.Stat.REPAIR_RATE:
			base = s.repair_rate_bp if s != null else 0
		DefEnums.Stat.REPAIR_COST:
			base = u.repair_cost_bp if u != null else s.repair_cost_bp
	if cond == DefEnums.Cond.ON_WATER and u != null:
		u.water_mult_bp = DefStatMath.fold2(10000, e[2], e[3])
		if has_s and base > 0:
			u.speed = DefStatMath.resolve_static(stat, base, s1, s2, eco)
		return true
	if base <= 0:
		rep.info("V-MOD-06", name, "modifier on stat %d is a no-op (base value 0)" % stat)
		return false
	var v: int = DefStatMath.resolve_static(stat, base, s1, s2, eco)
	match stat:
		DefEnums.Stat.COST:
			if u != null:
				u.cost = v
			else:
				s.cost = v
		DefEnums.Stat.BUILD_TIME:
			if u != null:
				u.build_ticks = v
			else:
				s.build_ticks = v
		DefEnums.Stat.HEALTH:
			if u != null:
				u.health = v
			else:
				s.health = v
		DefEnums.Stat.SPEED:
			u.speed = v
		DefEnums.Stat.SIGHT:
			if u != null:
				u.sight = v
			else:
				s.sight = v
		DefEnums.Stat.REARM:
			u.rearm_t = v
		DefEnums.Stat.POWER:
			s.power = v
		DefEnums.Stat.REPAIR_RATE:
			s.repair_rate_bp = v
		DefEnums.Stat.REPAIR_COST:
			if u != null:
				u.repair_cost_bp = v
			else:
				s.repair_cost_bp = v
	return true


static func _fold_slot(data: GameData, w: DefWeaponSlot, stat: int, s1: int, s2: int, e: PackedInt32Array, has_s: bool, cond: int, name: String, rep: DefLoadReport) -> bool:
	var eco: DefEconomy = data.economy
	match stat:
		DefEnums.Stat.DAMAGE:
			var base: int = w.damage
			if base <= 0:
				rep.info("V-MOD-06", name, "weapon damage modifier on an unarmed slot")
				return false
			if has_s:
				w.damage = DefStatMath.resolve_static(stat, base, s1, s2, eco)
			if cond == DefEnums.Cond.IN_CIVILIAN_GARRISON:
				var cv: DefCondVal = DefCondVal.new()
				cv.stat = DefEnums.Stat.DAMAGE
				cv.cond = cond
				cv.value = DefStatMath.resolve_static(stat, base, s1 + e[2], s2 + e[3], eco)
				w.cond_vals.append(cv)
			return true
		DefEnums.Stat.RANGE:
			if w.range <= 0:
				return false
			w.range = maxi(DefStatMath.resolve_static(stat, w.range, s1, s2, eco), w.min_range + 1)
			return true
		DefEnums.Stat.RELOAD:
			if w.reload_mt <= 0:
				return false
			w.reload_mt = DefStatMath.resolve_static(stat, w.reload_mt, s1, s2, eco)
			w.reload_ticks = maxi(1, DefConvert.ceil_div(w.reload_mt, 1000))
			return true
		DefEnums.Stat.PROJ_SPEED:
			if w.proj_speed <= 0:
				rep.info("V-MOD-06", name, "projectile-speed modifier on a hitscan slot")
				return false
			w.proj_speed = DefStatMath.resolve_static(stat, w.proj_speed, s1, s2, eco)
			return true
	return false


static func _name_of(u: DefUnit, s: DefStructure) -> String:
	return u.id if u != null else s.id
