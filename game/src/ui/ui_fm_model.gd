class_name UiFmModel
extends RefCounted
## Field Manual model (ui.md 3.6, 5.17): pure, caches the cards of one roster once, the screen only renders them. The spec's
## `DefBrowser` does not exist in the data module yet, so the cards are built here from `GameData` + `DefRoster` (the layers 1-2
## resolved clone the sim uses) + `DefPlayerView` (layer 3 = completed research; empty in menus, live values in a match).
## Every stat row is `{key, label, value, text, base, base_text, delta_bp, delta_text, tone, floor, conditional, tip}`:
## `tone` is "good" / "bad" / "" (a lower cost is good), `floor` marks a value sitting on a bible floor (cost / build time 60 %,
## reload 50 %), `conditional` marks a value that a conditional modifier changes at run time (asterisk + tooltip).
## References are `{kind, index, name}` dictionaries the screen turns into chips that open the target card.

const SUMMARY_KINDS: Array[int] = [DefEnums.Kind.UNIT, DefEnums.Kind.STRUCTURE, DefEnums.Kind.RESEARCH, DefEnums.Kind.POWER, DefEnums.Kind.SUPERWEAPON]

var data: GameData = null
var roster: DefRoster = null
var view: DefPlayerView = null
## true while `view` carries completed research of a running match (badge LIVE).
var live: bool = false

var _cards: Dictionary = {}  ## (kind << 24 | index) -> card
var _index: Array[Dictionary] = []  ## search index rows
var _cond_of: Dictionary = {}  ## modifier index -> DefCondApplication
var _others: Dictionary = {}  ## roster index -> UiFmModel (comparison side B)


## Resolves all cards lazily for `roster`. `view_override` (live match view) replaces the empty-research view.
func build(game_data: GameData, r: DefRoster, view_override: DefPlayerView = null) -> void:
	data = game_data
	roster = r
	live = view_override != null
	view = view_override if view_override != null else DefPlayerView.new(data, roster)
	_cards.clear()
	_cond_of.clear()
	_others.clear()
	for ca: DefCondApplication in roster.cond_apps:
		_cond_of[ca.modifier] = ca
	_build_index()


func roster_id() -> String:
	return roster.id if roster != null else ""


# ---------------------------------------------------------------------------------------------------------------- overview

## `{faction, roster, traits[], modifiers[], replacements[], opening, counterplay, lore, motto, identity, hq}`.
func overview() -> Dictionary:
	var f: DefFaction = data.factions[roster.faction]
	var subname: String = roster_sub_name(roster.id)
	var mods: Array[Dictionary] = []
	for mi: int in roster.modifier_list:
		var m: DefModifier = data.modifiers[mi]
		if m.layer != 2:
			continue
		mods.append(_modifier_row(m))
	var repl: Array[Dictionary] = []
	var keys: Array = roster.replaced_by.keys()
	keys.sort()
	for k: int in keys:
		repl.append({"baseline": ref(DefEnums.Kind.UNIT, k), "replacement": ref(DefEnums.Kind.UNIT, int(roster.replaced_by[k]))})
	var removed: Array[Dictionary] = []
	for u: DefUnit in data.units:
		if u.unit_class == DefEnums.UnitClass.BASELINE and u.faction == roster.faction and not roster.has_unit(u.index) \
				and not roster.replaced_by.has(u.index):
			removed.append(ref(DefEnums.Kind.UNIT, u.index))
	return {
		"faction": {"index": f.index, "code": f.code, "name": f.ui_name, "motto": f.ui_motto, "identity": f.ui_identity,
			"lore": f.ui_lore, "opening": f.ui_opening, "counterplay": f.ui_counterplay, "traits": f.ui_traits.duplicate()},
		"roster": {"index": roster.index, "id": roster.id, "sub": subname, "title": roster.ui_title, "identity": roster.ui_identity,
			"lore": roster.ui_lore, "opening": roster.ui_opening, "counterplay": roster.ui_counterplay, "vanilla": roster.is_vanilla},
		"modifiers": mods, "replacements": repl, "removed": removed,
		"counts": {"units": roster.producible_units.size(), "structures": roster.producible_structures.size(),
			"research": roster.research_list.size(), "powers": roster.power_list.size()},
	}


## "roster.napc.canada" -> "Canada", "roster.napc.usa" -> "USA".
static func roster_sub_name(roster_id_text: String) -> String:
	var key: String = roster_id_text.get_slice(".", 2)
	if key.length() <= 3 and key != "":
		return key.to_upper()
	return UiFmText.humanize(key)


# ---------------------------------------------------------------------------------------------------------------- lists

## Cards of the producible units in (tier, cost) order followed by the summons / drones the roster can spawn.
func units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u: int in roster.producible_units:
		out.append(card_for(DefEnums.Kind.UNIT, u))
	for u2: int in roster.spawnables:
		out.append(card_for(DefEnums.Kind.UNIT, u2))
	return out


## Cards of the buildable structures (HQ first, then build tier / cost order).
func structures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if roster.hq_idx >= 0:
		out.append(card_for(DefEnums.Kind.STRUCTURE, roster.hq_idx))
	for s: int in roster.producible_structures:
		out.append(card_for(DefEnums.Kind.STRUCTURE, s))
	return out


func research() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: int in roster.research_list:
		out.append(card_for(DefEnums.Kind.RESEARCH, r))
	return out


## The three support powers followed by the superweapon.
func powers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: int in roster.power_list:
		out.append(card_for(DefEnums.Kind.POWER, p))
	if roster.superweapon >= 0:
		out.append(card_for(DefEnums.Kind.SUPERWEAPON, roster.superweapon))
	return out


## The card of (kind, def index) for this roster; `{}` for a def the roster does not have.
func card_for(kind: int, def_idx: int) -> Dictionary:
	var key: int = (kind << 24) | def_idx
	if _cards.has(key):
		return _cards[key]
	var card: Dictionary = {}
	match kind:
		DefEnums.Kind.UNIT:
			card = _unit_card(def_idx)
		DefEnums.Kind.STRUCTURE:
			card = _structure_card(def_idx)
		DefEnums.Kind.RESEARCH:
			card = _research_card(def_idx)
		DefEnums.Kind.POWER:
			card = _power_card(def_idx)
		DefEnums.Kind.SUPERWEAPON:
			card = _superweapon_card(def_idx)
	_cards[key] = card
	return card


## Reference chip data.
func ref(kind: int, def_idx: int) -> Dictionary:
	var d: DefBase = data.def_of(kind, def_idx)
	return {"kind": kind, "index": def_idx, "name": UiFmText.def_name(d), "in_roster": _in_roster(kind, def_idx)}


func _in_roster(kind: int, def_idx: int) -> bool:
	match kind:
		DefEnums.Kind.UNIT:
			return roster.has_unit(def_idx)
		DefEnums.Kind.STRUCTURE:
			return roster.has_structure(def_idx)
		DefEnums.Kind.RESEARCH:
			return roster.research_list.has(def_idx)
		DefEnums.Kind.POWER:
			return roster.power_list.has(def_idx)
		DefEnums.Kind.SUPERWEAPON:
			return roster.superweapon == def_idx
	return false


# ---------------------------------------------------------------------------------------------------------------- unit card

func _unit_card(idx: int) -> Dictionary:
	if idx < 0 or idx >= data.units.size():
		return {}
	var u: DefUnit = roster.unit(idx)
	if u == null:
		return {}
	var base: DefUnit = data.units[idx]
	var st: PackedInt32Array = view.resolved_stats(DefEnums.Kind.UNIT, idx)
	var bs: PackedInt32Array = view.base_stats(DefEnums.Kind.UNIT, idx)
	var stats: Array[Dictionary] = []
	if u.cost > 0:
		stats.append(_stat_row(DefEnums.Kind.UNIT, idx, "cost", DefEnums.Stat.COST, st[DefEnums.Stat.COST], bs[DefEnums.Stat.COST]))
	stats.append(_stat_row(DefEnums.Kind.UNIT, idx, "build_time", DefEnums.Stat.BUILD_TIME, st[DefEnums.Stat.BUILD_TIME], bs[DefEnums.Stat.BUILD_TIME]))
	stats.append(_stat_row(DefEnums.Kind.UNIT, idx, "health", DefEnums.Stat.HEALTH, st[DefEnums.Stat.HEALTH], bs[DefEnums.Stat.HEALTH]))
	if u.speed > 0:
		stats.append(_stat_row(DefEnums.Kind.UNIT, idx, "speed", DefEnums.Stat.SPEED, st[DefEnums.Stat.SPEED], bs[DefEnums.Stat.SPEED]))
	if u.speed_water > 0 and u.speed_water != u.speed:
		stats.append(_plain_row("water_speed", u.speed_water, base.speed_water, DefFormat.speed_text(u.speed_water) + " cells/s", DefFormat.speed_text(base.speed_water) + " cells/s", DefEnums.Stat.SPEED, DefEnums.Kind.UNIT, idx))
	stats.append(_stat_row(DefEnums.Kind.UNIT, idx, "sight", DefEnums.Stat.SIGHT, st[DefEnums.Stat.SIGHT], bs[DefEnums.Stat.SIGHT]))
	var weapons: Array[Dictionary] = []
	for si: int in u.weapons.size():
		weapons.append(_weapon_row(idx, si, u.weapons[si], base.weapons[si] if si < base.weapons.size() else u.weapons[si]))
	var abilities: Array[Dictionary] = []
	for a: DefAbility in u.abilities:
		abilities.append({"kind": a.kind, "name": UiFmText.ability_name(a.kind), "text": UiFmText.ability_text(a, data)})
	var reqs: Array[Dictionary] = []
	for rq: int in u.requires:
		reqs.append(ref(DefEnums.Kind.STRUCTURE, rq))
	var replaced_by: Array[Dictionary] = []
	for rb: int in u.replaced_by:
		if roster.has_unit(rb):
			replaced_by.append(ref(DefEnums.Kind.UNIT, rb))
	var flags: PackedStringArray = PackedStringArray()
	if u.flags & DefEnums.UF_UNARMED != 0 or u.weapons.is_empty():
		flags.append("Unarmed")
	if u.flags & DefEnums.UF_FIRE_STATIONARY != 0:
		flags.append("Fires only while stationary")
	if u.flags & DefEnums.UF_NO_CAPTURE != 0:
		flags.append("Cannot be captured")
	if u.flags & DefEnums.UF_NO_REPAIR != 0:
		flags.append("Cannot be repaired")
	if u.lifetime_t > 0:
		flags.append("Expires after %s" % UiFmText.secs(u.lifetime_t))
	var producible: bool = (u.flags & DefEnums.UF_PRODUCIBLE) != 0
	var cls: String = UiFmText.unit_class_name(u.unit_class)
	var kinds: Dictionary = _defense_profile(u.armor_class)
	return {
		"kind": DefEnums.Kind.UNIT, "index": idx, "id": u.id, "name": UiFmText.def_name(u), "text": u.ui_text, "glyph": UiFmText.unit_glyph(u),
		"class": cls, "unit_class": u.unit_class, "unique": u.unit_class == DefEnums.UnitClass.UNIQUE,
		"summon": u.unit_class == DefEnums.UnitClass.SUMMON or u.unit_class == DefEnums.UnitClass.DRONE, "tier": u.tier,
		"producible": producible, "cost": st[DefEnums.Stat.COST] if u.cost > 0 else 0,
		"stats": stats, "pop": u.pop, "armor": UiFmText.armor_name(u.armor_class), "armor_class": u.armor_class,
		"move": UiFmText.move_name(u.move_class), "layers": UiFmText.layer_text(u.layer_mask),
		"producer": ref(DefEnums.Kind.STRUCTURE, u.producer) if u.producer >= 0 else {}, "requires": reqs,
		"replaces": ref(DefEnums.Kind.UNIT, u.replaces) if u.replaces >= 0 else {}, "replaced_by": replaced_by,
		"weapons": weapons, "abilities": abilities, "modifiers": _modifiers_for(DefEnums.Kind.UNIT, idx), "flags": flags,
		"takes_full": kinds["full"], "resists": kinds["resists"], "effective_vs": _offense_profile(u, true), "poor_vs": _offense_profile(u, false),
		"radius_text": UiFmText.cells(u.radius), "detect_text": UiFmText.cells(u.detect_radius) if u.detect_radius > 0 else "",
		"introduced_by": data.rosters[u.introduced_by].id if u.introduced_by >= 0 and u.introduced_by < data.rosters.size() else "",
	}


func _weapon_row(unit_idx: int, slot_idx: int, w: DefWeaponSlot, b: DefWeaponSlot) -> Dictionary:
	var dmg: int = view.effective_slot_value(unit_idx, slot_idx, DefEnums.Stat.DAMAGE)
	var rng: int = view.effective_slot_value(unit_idx, slot_idx, DefEnums.Stat.RANGE)
	var rel: int = view.effective_slot_value(unit_idx, slot_idx, DefEnums.Stat.RELOAD)
	var dps: int = UiFmText.dps_x10(dmg, w.hits_per_volley, rel)
	var base_dps: int = UiFmText.dps_x10(b.damage, b.hits_per_volley, b.reload_mt)
	var label: String = w.ui_label.get_slice(".", w.ui_label.get_slice_count(".") - 1)
	var tags: PackedStringArray = PackedStringArray()
	if w.flags & DefEnums.WF_SUPPRESSIVE != 0:
		tags.append("Suppressive")
	if w.fire_mode == DefEnums.FireMode.INDIRECT:
		tags.append("Indirect fire")
	elif w.fire_mode == DefEnums.FireMode.MELEE:
		tags.append("Melee")
	if w.homing and (w.proj_kind == DefEnums.ProjKind.MISSILE or w.proj_kind == DefEnums.ProjKind.ROCKET or w.proj_kind == DefEnums.ProjKind.TORPEDO):
		tags.append("Guided")
	if w.flags & DefEnums.WF_STATIONARY_FIRE != 0:
		tags.append("Fires stationary")
	if w.flags & DefEnums.WF_POINT_DEFENSE != 0:
		tags.append("Point defense")
	var dps_delta: int = UiFmText.delta_bp(base_dps, dps)
	return {
		"slot": slot_idx, "name": UiFmText.humanize(label), "label_id": w.ui_label, "damage": dmg, "hits": w.hits_per_volley,
		"dps_x10": dps, "dps_text": UiFmText.dps_text(dps), "base_dps_x10": base_dps, "dps_delta_bp": dps_delta,
		"dps_tone": _tone(DefEnums.Stat.DAMAGE, dps_delta),
		"range": rng, "range_text": UiFmText.cells(rng), "min_range": w.min_range, "min_range_text": UiFmText.cells(w.min_range) if w.min_range > 0 else "",
		"reload_mt": rel, "reload_text": DefFormat.mt_seconds_text(rel) + " s", "burst": w.hits_per_volley,
		"dtype": w.dtype, "dtype_text": UiFmText.damage_name(w.dtype), "targets": UiFmText.target_text(w.target_mask),
		"splash": w.splash_radius, "splash_text": UiFmText.cells(w.splash_radius) if w.splash_radius > 0 else "",
		"suppressive": w.flags & DefEnums.WF_SUPPRESSIVE != 0, "indirect": w.fire_mode == DefEnums.FireMode.INDIRECT,
		"tags": tags, "ammo": w.ammo_volleys,
		"damage_delta_bp": UiFmText.delta_bp(b.damage, dmg), "range_delta_bp": UiFmText.delta_bp(b.range, rng), "reload_delta_bp": UiFmText.delta_bp(b.reload_mt, rel),
	}


## Damage types that hurt `armor_class` fully (>= 100 %) and those it resists (<= 40 %).
func _defense_profile(armor_class: int) -> Dictionary:
	var full: PackedStringArray = PackedStringArray()
	var resists: PackedStringArray = PackedStringArray()
	for dt: int in DefEnums.DamageType.COUNT:
		var pct: int = data.damage.pct(dt, armor_class)
		if dt == DefEnums.DamageType.EMP:
			if pct == 0:
				resists.append("EMP (immune)")
			continue
		if pct >= 100:
			full.append(UiFmText.damage_name(dt))
		elif pct <= 40:
			resists.append("%s (%d%%)" % [UiFmText.damage_name(dt), pct])
	return {"full": full, "resists": resists}


## Armor classes the unit's weapons hurt fully (`good` = true, >= 100 %) or poorly (<= 40 %).
func _offense_profile(u: DefUnit, good: bool) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if u.weapons.is_empty():
		return out
	for ac: int in DefEnums.ArmorClass.COUNT:
		var best: int = 0
		for w: DefWeaponSlot in u.weapons:
			if w.damage > 0 and _can_target_armor(w, ac):
				best = maxi(best, data.damage.pct(w.dtype, ac))
		if good and best >= 100 or not good and best <= 40 and _any_targetable(u, ac):
			out.append(UiFmText.armor_name(ac))
	return out


func _any_targetable(u: DefUnit, ac: int) -> bool:
	for w: DefWeaponSlot in u.weapons:
		if w.damage > 0 and _can_target_armor(w, ac):
			return true
	return false


## Whether a weapon can attack the layer an armor class lives on (air armor -> air layer, ship -> water, the rest -> ground).
static func _can_target_armor(w: DefWeaponSlot, armor_class: int) -> bool:
	var need: int = DefEnums.L_GROUND
	if armor_class == DefEnums.ArmorClass.AIR_LIGHT or armor_class == DefEnums.ArmorClass.AIR_HEAVY:
		need = DefEnums.L_AIR
	elif armor_class == DefEnums.ArmorClass.SHIP_LIGHT or armor_class == DefEnums.ArmorClass.SHIP_HEAVY:
		need = DefEnums.L_WATER
	return w.target_mask == 0 or (w.target_mask & need) != 0


# ---------------------------------------------------------------------------------------------------------------- structure card

func _structure_card(idx: int) -> Dictionary:
	if idx < 0 or idx >= data.structures.size():
		return {}
	var s: DefStructure = roster.structure(idx)
	if s == null:
		return {}
	var st: PackedInt32Array = view.resolved_stats(DefEnums.Kind.STRUCTURE, idx)
	var bs: PackedInt32Array = view.base_stats(DefEnums.Kind.STRUCTURE, idx)
	var stats: Array[Dictionary] = []
	var no_build: bool = (s.flags & DefEnums.SF_NO_BUILD) != 0
	if not no_build:
		stats.append(_stat_row(DefEnums.Kind.STRUCTURE, idx, "cost", DefEnums.Stat.COST, st[DefEnums.Stat.COST], bs[DefEnums.Stat.COST]))
		stats.append(_stat_row(DefEnums.Kind.STRUCTURE, idx, "build_time", DefEnums.Stat.BUILD_TIME, st[DefEnums.Stat.BUILD_TIME], bs[DefEnums.Stat.BUILD_TIME]))
	stats.append(_stat_row(DefEnums.Kind.STRUCTURE, idx, "health", DefEnums.Stat.HEALTH, st[DefEnums.Stat.HEALTH], bs[DefEnums.Stat.HEALTH]))
	stats.append(_stat_row(DefEnums.Kind.STRUCTURE, idx, "sight", DefEnums.Stat.SIGHT, s.sight, bs[DefEnums.Stat.SIGHT]))
	var power: int = view.struct_power[idx] if idx < view.struct_power.size() else s.power
	var power_row: Dictionary = _plain_row("power", power, data.structures[idx].power, _power_text(power), _power_text(data.structures[idx].power), DefEnums.Stat.POWER, DefEnums.Kind.STRUCTURE, idx)
	if power != 0:
		stats.append(power_row)
	var produces: Array[Dictionary] = []
	for u: int in roster.units_produced_by(idx):
		produces.append(ref(DefEnums.Kind.UNIT, u))
	var unlocks: Array[Dictionary] = []
	for other: int in roster.producible_structures:
		if other != idx and roster.structures[other].requires.has(idx):
			unlocks.append(ref(DefEnums.Kind.STRUCTURE, other))
	for u2: int in roster.producible_units:
		var ud: DefUnit = roster.units[u2]
		if ud.requires.has(idx) and ud.producer != idx:
			unlocks.append(ref(DefEnums.Kind.UNIT, u2))
	var reqs: Array[Dictionary] = []
	for rq: int in s.requires:
		reqs.append(ref(DefEnums.Kind.STRUCTURE, rq))
	var weapons: Array[Dictionary] = []
	for si: int in s.weapons.size():
		weapons.append(_struct_weapon_row(idx, si, s.weapons[si], data.structures[idx].weapons[si] if si < data.structures[idx].weapons.size() else s.weapons[si]))
	var abilities: Array[Dictionary] = []
	for a: DefAbility in s.abilities:
		abilities.append({"kind": a.kind, "name": UiFmText.ability_name(a.kind), "text": UiFmText.ability_text(a, data)})
	var flags: PackedStringArray = PackedStringArray()
	if s.flags & DefEnums.SF_SELLABLE != 0:
		flags.append("Can be sold for %s%% of its cost" % DefFormat.percent_text(s.sell_bp))
	if s.flags & DefEnums.SF_CAPTURE_IMMUNE != 0:
		flags.append("Cannot be captured")
	if s.flags & DefEnums.SF_POWERED_DEFENSE != 0:
		flags.append("Needs power to fire")
	if s.flags & DefEnums.SF_STRATEGIC != 0:
		flags.append("Strategic structure")
	if s.max_per_player > 0:
		flags.append("Maximum %d per player" % s.max_per_player)
	if s.build_radius > 0:
		flags.append("Build radius %s cells" % UiFmText.cells(s.build_radius))
	return {
		"kind": DefEnums.Kind.STRUCTURE, "index": idx, "id": s.id, "name": UiFmText.def_name(s), "text": s.ui_text, "glyph": UiFmText.structure_glyph(s),
		"tier": _struct_tier(s), "cost": st[DefEnums.Stat.COST] if not no_build else 0, "stats": stats, "power": power,
		"armor": UiFmText.armor_name(s.armor_class), "footprint": "%d x %d cells" % [s.fp_w, s.fp_h], "requires": reqs,
		"produces": produces, "unlocks": unlocks, "weapons": weapons, "abilities": abilities, "flags": flags,
		"placement": UiFmText.place_flags_text(s.place_mask), "modifiers": _modifiers_for(DefEnums.Kind.STRUCTURE, idx),
		"start": no_build, "queues": s.queues, "detect_text": UiFmText.cells(s.detect_radius) if s.detect_radius > 0 else "",
	}


func _struct_weapon_row(sidx: int, slot_idx: int, w: DefWeaponSlot, b: DefWeaponSlot) -> Dictionary:
	var rel: int = w.reload_mt
	var dps: int = UiFmText.dps_x10(w.damage, w.hits_per_volley, rel)
	var base_dps: int = UiFmText.dps_x10(b.damage, b.hits_per_volley, b.reload_mt)
	var label: String = w.ui_label.get_slice(".", w.ui_label.get_slice_count(".") - 1)
	return {
		"slot": slot_idx, "name": UiFmText.humanize(label), "label_id": w.ui_label, "damage": w.damage, "hits": w.hits_per_volley,
		"dps_x10": dps, "dps_text": UiFmText.dps_text(dps), "base_dps_x10": base_dps, "dps_delta_bp": UiFmText.delta_bp(base_dps, dps),
		"dps_tone": _tone(DefEnums.Stat.DAMAGE, UiFmText.delta_bp(base_dps, dps)),
		"range": w.range, "range_text": UiFmText.cells(w.range), "min_range": w.min_range, "min_range_text": UiFmText.cells(w.min_range) if w.min_range > 0 else "",
		"reload_mt": rel, "reload_text": DefFormat.mt_seconds_text(rel) + " s", "burst": w.hits_per_volley, "dtype": w.dtype,
		"dtype_text": UiFmText.damage_name(w.dtype), "targets": UiFmText.target_text(w.target_mask), "splash": w.splash_radius,
		"splash_text": UiFmText.cells(w.splash_radius) if w.splash_radius > 0 else "", "suppressive": w.flags & DefEnums.WF_SUPPRESSIVE != 0,
		"indirect": w.fire_mode == DefEnums.FireMode.INDIRECT, "tags": PackedStringArray(), "ammo": w.ammo_volleys,
		"damage_delta_bp": 0, "range_delta_bp": 0, "reload_delta_bp": 0, "structure": sidx,
	}


func _struct_tier(s: DefStructure) -> int:
	var depth: int = 0
	for rq: int in s.requires:
		var r: DefStructure = roster.structure(rq)
		if r != null and rq != s.index:
			depth = maxi(depth, 1 + _struct_tier(r))
	return depth


static func _power_text(p: int) -> String:
	return ("+%d" % p if p > 0 else "%d" % p) + " power"


# ---------------------------------------------------------------------------------------------------------------- research, powers

func _research_card(idx: int) -> Dictionary:
	if idx < 0 or idx >= data.research.size():
		return {}
	var r: DefResearch = data.research[idx]
	var exclusive: bool = r.introduced_by == roster.index
	var reqs: Array[Dictionary] = _mask_refs(r.requires_mask)
	return {
		"kind": DefEnums.Kind.RESEARCH, "index": idx, "id": r.id, "name": UiFmText.def_name(r), "text": r.ui_effect_text, "glyph": UiGlyphs.Glyph.GEAR,
		"tier": r.tier, "cost": r.cost, "stats": [_value_row("cost", r.cost, DefFormat.credits_text(r.cost)),
			_value_row("build_time", r.time_t, UiFmText.secs(r.time_t))], "requires": reqs, "exclusive": exclusive,
		"inherited": r.inherited, "slot": roster.research_slot(idx),
		"scope": "Exclusive to this subfaction" if exclusive else "Shared by the faction",
	}


func _power_card(idx: int) -> Dictionary:
	if idx < 0 or idx >= data.powers.size():
		return {}
	var p: DefPower = data.powers[idx]
	var exclusive: bool = p.introduced_by == roster.index
	var stats: Array[Dictionary] = [_value_row("cost", p.cost, DefFormat.credits_text(p.cost)), _value_row("cooldown", p.cooldown_t, UiFmText.secs(p.cooldown_t))]
	if p.radius > 0:
		stats.append(_value_row("radius", p.radius, UiFmText.cells(p.radius) + " cells"))
	if p.warning_t > 0:
		stats.append(_value_row("warning", p.warning_t, UiFmText.secs(p.warning_t)))
	return {
		"kind": DefEnums.Kind.POWER, "index": idx, "id": p.id, "name": UiFmText.def_name(p), "text": p.ui_effect_text, "glyph": UiGlyphs.Glyph.POWERS,
		"tier": p.tier, "cost": p.cost, "stats": stats, "requires": _mask_refs(p.requires_mask), "targeting": UiFmText.target_mode_text(p.target_mode),
		"vision": UiFmText.target_vision_text(p.target_vision), "needs_power": p.requires_powered, "exclusive": exclusive, "slot": roster.power_slot(idx),
		"scope": "Exclusive to this subfaction" if exclusive else "Shared by the faction",
	}


func _superweapon_card(idx: int) -> Dictionary:
	if idx < 0 or idx >= data.superweapons.size():
		return {}
	var sw: DefSuperweapon = roster.superweapon_def if roster.superweapon == idx and roster.superweapon_def != null else data.superweapons[idx]
	var stats: Array[Dictionary] = [_value_row("recharge", sw.recharge_t, UiFmText.secs(sw.recharge_t)), _value_row("warning", sw.warning_t, UiFmText.secs(sw.warning_t))]
	if sw.radius > 0:
		stats.append(_value_row("radius", sw.radius, UiFmText.cells(sw.radius) + " cells"))
	var launcher: Dictionary = ref(DefEnums.Kind.STRUCTURE, sw.launcher) if sw.launcher >= 0 else {}
	return {
		"kind": DefEnums.Kind.SUPERWEAPON, "index": idx, "id": sw.id, "name": UiFmText.def_name(sw), "text": sw.ui_text, "glyph": UiGlyphs.Glyph.MISSILE,
		"tier": 3, "cost": 0, "stats": stats, "requires": _mask_refs(sw.requires_mask), "launcher": launcher,
		"targeting": UiFmText.target_vision_text(sw.target_vision), "charges": sw.max_charges, "starts_charged": sw.starts_charged,
		"scope": "Superweapon of the faction",
	}


func _mask_refs(mask: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in mini(data.structures.size(), 62):
		if (mask >> i) & 1 == 1:
			out.append(ref(DefEnums.Kind.STRUCTURE, i))
	return out


# ---------------------------------------------------------------------------------------------------------------- stat rows

func _tone(stat: int, delta_bp: int) -> String:
	if delta_bp == 0:
		return ""
	var good: bool = delta_bp < 0 if UiFmText.LOWER_IS_BETTER.has(stat) else delta_bp > 0
	return "good" if good else "bad"


func _stat_text(key: String, value: int) -> String:
	match key:
		"cost":
			return DefFormat.credits_text(value)
		"build_time":
			return UiFmText.secs(value)
		"health":
			return DefFormat.credits_text(value)
		"speed":
			return DefFormat.speed_text(value) + " cells/s"
		"sight":
			return UiFmText.cells(value) + " cells"
	return str(value)


## Combined static modifier of a stat in bp: exactly the bible's "+10 %" (the measured change of an integer stat can read
## +9.92 %). Falls back to the measured change with research applied (live view), at a floor, or when no modifier touches it.
func _delta_of(kind: int, def_idx: int, stat: int, base: int, value: int) -> int:
	var measured: int = UiFmText.delta_bp(base, value)
	if live or stat < 0 or stat >= DefEnums.STAT_COUNT_BIBLE or base <= 0:
		return measured
	var sums: PackedInt32Array = roster.static_sums(kind, def_idx, stat)
	if sums[0] == 0 and sums[1] == 0:
		return measured
	var nominal: int = ((10000 + sums[0]) * (10000 + sums[1]) + 5000) / 10000 - 10000
	if absi(nominal - measured) > 150 or (nominal > 0) != (measured > 0):
		return measured
	return nominal


func _stat_row(kind: int, def_idx: int, key: String, stat: int, value: int, base: int) -> Dictionary:
	var d_bp: int = _delta_of(kind, def_idx, stat, base, value)
	var floor_hit: bool = false
	var eco: DefEconomy = data.economy
	if base > 0 and value < base:
		if stat == DefEnums.Stat.COST:
			floor_hit = value == DefConvert.ceil_div(base * eco.floor_cost_bp, 10000)
		elif stat == DefEnums.Stat.BUILD_TIME:
			floor_hit = value == DefConvert.ceil_div(base * eco.floor_build_bp, 10000)
	var mods: Array[Dictionary] = _stat_modifiers(kind, def_idx, stat)
	var conditional: bool = false
	var lines: PackedStringArray = PackedStringArray()
	for m: Dictionary in mods:
		if bool(m["conditional"]):
			conditional = true
		lines.append("%s (%s%s)" % [m["text"], m["source"], ", " + str(m["condition"]) if str(m["condition"]) != "" else ""])
	var tip: String = ""
	if d_bp != 0 or conditional:
		tip = "Base %s -> %s" % [_stat_text(key, base), _stat_text(key, value)] if d_bp != 0 else "Base %s" % _stat_text(key, base)
		if not lines.is_empty():
			tip += ": " + "; ".join(lines)
		if floor_hit:
			tip += ". At the bible floor (%s%% of base)." % DefFormat.percent_text(eco.floor_cost_bp if stat == DefEnums.Stat.COST else eco.floor_build_bp)
	return {"key": key, "label": UiFmText.STAT_LABELS.get(key, key), "value": value, "text": _stat_text(key, value), "base": base,
		"base_text": _stat_text(key, base), "delta_bp": d_bp, "delta_text": UiFmText.delta_text(d_bp) if d_bp != 0 else "",
		"tone": _tone(stat, d_bp), "floor": floor_hit, "conditional": conditional, "tip": tip, "stat": stat}


func _plain_row(key: String, value: int, base: int, text: String, base_text: String, stat: int, kind: int, def_idx: int) -> Dictionary:
	var row: Dictionary = _stat_row(kind, def_idx, key, stat, value, base)
	row["text"] = text
	row["base_text"] = base_text
	if str(row["tip"]) != "":
		row["tip"] = str(row["tip"]).replace(_stat_text(key, value), text).replace(_stat_text(key, base), base_text)
	return row


static func _value_row(key: String, value: int, text: String) -> Dictionary:
	return {"key": key, "label": UiFmText.STAT_LABELS.get(key, UiFmText.humanize(key)), "value": value, "text": text, "base": value, "base_text": text,
		"delta_bp": 0, "delta_text": "", "tone": "", "floor": false, "conditional": false, "tip": "", "stat": -1}


# ---------------------------------------------------------------------------------------------------------------- modifiers

func _matches(m: DefModifier, kind: int, def_idx: int) -> bool:
	if _cond_of.has(m.index):
		var ca: DefCondApplication = _cond_of[m.index]
		return (ca.units if kind == DefEnums.Kind.UNIT else ca.structures).has(def_idx)
	if m.selector < 0:
		return false
	if kind == DefEnums.Kind.UNIT:
		return roster.selector_units(m.selector).has(def_idx)
	return roster.selector_structures(m.selector).has(def_idx)


func _modifier_row(m: DefModifier) -> Dictionary:
	var cond_text: String = UiFmText.cond_text(m.cond) if m.cond != DefEnums.Cond.NONE else ""
	return {"index": m.index, "id": m.id, "text": m.ui_source_text, "stat": m.stat, "stat_text": UiFmText.stat_text(m.stat),
		"delta_bp": m.delta_bp, "delta_text": UiFmText.delta_text(m.delta_bp), "layer": m.layer, "source": UiFmText.layer_source_text(m.layer),
		"conditional": m.cond != DefEnums.Cond.NONE, "condition": cond_text, "tone": _tone(m.stat, m.delta_bp)}


func _modifiers_for(kind: int, def_idx: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for mi: int in roster.modifier_list:
		var m: DefModifier = data.modifiers[mi]
		if _matches(m, kind, def_idx) and not seen.has(m.ui_source_text + str(m.layer)):
			seen[m.ui_source_text + str(m.layer)] = true
			out.append(_modifier_row(m))
	return out


func _stat_modifiers(kind: int, def_idx: int, stat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mi: int in roster.modifier_list:
		var m: DefModifier = data.modifiers[mi]
		if m.stat == stat and _matches(m, kind, def_idx):
			out.append(_modifier_row(m))
	return out


# ---------------------------------------------------------------------------------------------------------------- tech tree

## `{nodes: [{kind, index, name, depth, column, row, requires: []}], edges: [[from_key, to_key]]}`: structures by
## `depth = 1 + max(depth(requirement))` (HQ = 0) and the units each structure produces as leaves (5.17).
func tech_tree() -> Dictionary:
	var nodes: Array[Dictionary] = []
	var edges: Array = []
	var depth_of: Dictionary = {}
	var ids: Array[int] = []
	if roster.hq_idx >= 0:
		ids.append(roster.hq_idx)
	for s: int in roster.producible_structures:
		ids.append(s)
	for s: int in ids:
		depth_of[s] = _struct_tier(roster.structures[s])
	var per_col: Dictionary = {}
	for s: int in ids:
		var d: int = int(depth_of[s])
		var row: int = int(per_col.get(d, 0))
		per_col[d] = row + 1
		var reqs: Array = []
		for rq: int in roster.structures[s].requires:
			if depth_of.has(rq) and rq != s:
				reqs.append(rq)
				edges.append([(DefEnums.Kind.STRUCTURE << 24) | rq, (DefEnums.Kind.STRUCTURE << 24) | s])
		nodes.append({"kind": DefEnums.Kind.STRUCTURE, "index": s, "name": roster.structures[s].ui_name, "depth": d, "column": d, "row": row, "requires": reqs})
	return {"nodes": nodes, "edges": edges, "columns": per_col.size()}


# ---------------------------------------------------------------------------------------------------------------- compare

## Roster comparison (5.17): `{a, b, only_a[], only_b[], replaced[], modifier_diffs[], units[]}`. `units` compares every unit
## present in either roster by baseline: `{baseline, a, b, rows[]}` with `rows` from `compare_unit`.
func compare(other: DefRoster) -> Dictionary:
	var only_a: Array[Dictionary] = []
	var only_b: Array[Dictionary] = []
	var replaced: Array[Dictionary] = []
	var rows: Array[Dictionary] = []
	var seen_base: Dictionary = {}
	for u: int in roster.producible_units:
		var base_idx: int = data.units[u].replaces if data.units[u].replaces >= 0 else u
		if seen_base.has(base_idx):
			continue
		seen_base[base_idx] = true
		var mine: int = _version_in(roster, base_idx)
		var theirs: int = _version_in(other, base_idx)
		if mine >= 0 and theirs >= 0 and mine != theirs:
			replaced.append({"baseline": ref(DefEnums.Kind.UNIT, base_idx), "a": ref(DefEnums.Kind.UNIT, mine), "b": ref(DefEnums.Kind.UNIT, theirs)})
		elif mine >= 0 and theirs < 0:
			only_a.append(ref(DefEnums.Kind.UNIT, mine))
		rows.append({"baseline": ref(DefEnums.Kind.UNIT, base_idx), "a": ref(DefEnums.Kind.UNIT, mine) if mine >= 0 else {}, "b": ref(DefEnums.Kind.UNIT, theirs) if theirs >= 0 else {},
			"rows": compare_unit(base_idx, other)})
	for u2: int in other.producible_units:
		var base2: int = data.units[u2].replaces if data.units[u2].replaces >= 0 else u2
		if not seen_base.has(base2):
			seen_base[base2] = true
			var theirs2: int = _version_in(other, base2)
			only_b.append(ref(DefEnums.Kind.UNIT, theirs2))
			rows.append({"baseline": ref(DefEnums.Kind.UNIT, base2), "a": {}, "b": ref(DefEnums.Kind.UNIT, theirs2), "rows": compare_unit(base2, other)})
	for s: int in roster.producible_structures:
		if not other.has_structure(s):
			only_a.append(ref(DefEnums.Kind.STRUCTURE, s))
	for s2: int in other.producible_structures:
		if not roster.has_structure(s2):
			only_b.append(ref(DefEnums.Kind.STRUCTURE, s2))
	for r: int in roster.research_list:
		if not other.research_list.has(r):
			only_a.append(ref(DefEnums.Kind.RESEARCH, r))
	for r2: int in other.research_list:
		if not roster.research_list.has(r2):
			only_b.append(ref(DefEnums.Kind.RESEARCH, r2))
	for p: int in roster.power_list:
		if not other.power_list.has(p):
			only_a.append(ref(DefEnums.Kind.POWER, p))
	for p2: int in other.power_list:
		if not roster.power_list.has(p2):
			only_b.append(ref(DefEnums.Kind.POWER, p2))
	var mod_diffs: Array[Dictionary] = []
	var a_texts: Dictionary = {}
	var b_texts: Dictionary = {}
	for mi: int in roster.modifier_list:
		a_texts[data.modifiers[mi].ui_source_text] = mi
	for mj: int in other.modifier_list:
		b_texts[data.modifiers[mj].ui_source_text] = mj
	for t: String in a_texts:
		if not b_texts.has(t):
			var row_a: Dictionary = _modifier_row(data.modifiers[int(a_texts[t])])
			row_a["side"] = "a"
			mod_diffs.append(row_a)
	for t2: String in b_texts:
		if not a_texts.has(t2):
			var row_b: Dictionary = _modifier_row(data.modifiers[int(b_texts[t2])])
			row_b["side"] = "b"
			mod_diffs.append(row_b)
	return {"a": roster.id, "b": other.id, "only_a": only_a, "only_b": only_b, "replaced": replaced, "modifier_diffs": mod_diffs, "units": rows}


## The unit index `r` fields for baseline unit `base_idx` (its replacement when it has one), -1 when the roster lacks both.
func _version_in(r: DefRoster, base_idx: int) -> int:
	var v: int = int(r.replaced_by.get(base_idx, base_idx))
	if r.has_unit(v) and (data.units[v].flags & DefEnums.UF_PRODUCIBLE) != 0:
		return v
	return -1


## Side-by-side stat rows of a unit (`base_idx` = the baseline unit index) in this roster and `other`:
## `[{label, a_text, b_text, a, b, delta_bp, tone}]` (tone: "good" when B is better than A for that stat).
func compare_unit(base_idx: int, other: DefRoster) -> Array[Dictionary]:
	var ob: UiFmModel = _model_of(other)
	var ia: int = _version_in(roster, base_idx)
	var ib: int = _version_in(other, base_idx)
	var ca: Dictionary = card_for(DefEnums.Kind.UNIT, ia) if ia >= 0 else {}
	var cb: Dictionary = ob.card_for(DefEnums.Kind.UNIT, ib) if ib >= 0 else {}
	var out: Array[Dictionary] = []
	if ca.is_empty() and cb.is_empty():
		return out
	for key: String in ["cost", "build_time", "health", "speed", "sight"]:
		var ra: Dictionary = _find_stat(ca, key)
		var rb: Dictionary = _find_stat(cb, key)
		if ra.is_empty() and rb.is_empty():
			continue
		var stat: int = int((ra if not ra.is_empty() else rb).get("stat", -1))
		var va: int = int(ra.get("value", 0))
		var vb: int = int(rb.get("value", 0))
		var d_bp: int = UiFmText.delta_bp(va, vb) if not ra.is_empty() and not rb.is_empty() else 0
		out.append({"label": UiFmText.STAT_LABELS.get(key, key), "a_text": str(ra.get("text", "-")), "b_text": str(rb.get("text", "-")), "a": va, "b": vb,
			"delta_bp": d_bp, "tone": _tone(stat, d_bp)})
	var wa: Dictionary = _first_weapon(ca)
	var wb: Dictionary = _first_weapon(cb)
	if not wa.is_empty() or not wb.is_empty():
		var da: int = int(wa.get("dps_x10", 0))
		var db: int = int(wb.get("dps_x10", 0))
		var dd: int = UiFmText.delta_bp(da, db) if da > 0 and db > 0 else 0
		out.append({"label": "DPS", "a_text": str(wa.get("dps_text", "-")), "b_text": str(wb.get("dps_text", "-")), "a": da, "b": db, "delta_bp": dd,
			"tone": _tone(DefEnums.Stat.DAMAGE, dd)})
		var range_a: int = int(wa.get("range", 0))
		var range_b: int = int(wb.get("range", 0))
		var rd: int = UiFmText.delta_bp(range_a, range_b) if range_a > 0 and range_b > 0 else 0
		out.append({"label": "Range", "a_text": str(wa.get("range_text", "-")), "b_text": str(wb.get("range_text", "-")), "a": range_a, "b": range_b,
			"delta_bp": rd, "tone": _tone(DefEnums.Stat.RANGE, rd)})
	return out


## Cached model of another roster (the comparison side B).
func _model_of(other: DefRoster) -> UiFmModel:
	if other == roster:
		return self
	if not _others.has(other.index):
		var m: UiFmModel = UiFmModel.new()
		m.build(data, other)
		_others[other.index] = m
	return _others[other.index]


static func _find_stat(card: Dictionary, key: String) -> Dictionary:
	for r: Dictionary in card.get("stats", []) as Array:
		if r["key"] == key:
			return r
	return {}


static func _first_weapon(card: Dictionary) -> Dictionary:
	var ws: Array = card.get("weapons", []) as Array
	return ws[0] as Dictionary if not ws.is_empty() else {}


# ---------------------------------------------------------------------------------------------------------------- search

func _build_index() -> void:
	_index.clear()
	for u: int in roster.producible_units:
		_add_index(DefEnums.Kind.UNIT, u, UiFmText.def_name(data.units[u]), "Unit", data.units[u].ui_text)
	for u2: int in roster.spawnables:
		_add_index(DefEnums.Kind.UNIT, u2, UiFmText.def_name(data.units[u2]), "Summon", data.units[u2].ui_text)
	if roster.hq_idx >= 0:
		_add_index(DefEnums.Kind.STRUCTURE, roster.hq_idx, data.structures[roster.hq_idx].ui_name, "Structure", data.structures[roster.hq_idx].ui_text)
	for s: int in roster.producible_structures:
		_add_index(DefEnums.Kind.STRUCTURE, s, data.structures[s].ui_name, "Structure", data.structures[s].ui_text)
	for r: int in roster.research_list:
		_add_index(DefEnums.Kind.RESEARCH, r, data.research[r].ui_name, "Research", data.research[r].ui_effect_text)
	for p: int in roster.power_list:
		_add_index(DefEnums.Kind.POWER, p, data.powers[p].ui_name, "Power", data.powers[p].ui_effect_text)
	if roster.superweapon >= 0:
		_add_index(DefEnums.Kind.SUPERWEAPON, roster.superweapon, data.superweapons[roster.superweapon].ui_name, "Superweapon", data.superweapons[roster.superweapon].ui_text)


func _add_index(kind: int, idx: int, nm: String, what: String, text: String) -> void:
	_index.append({"kind": kind, "index": idx, "name": nm, "lower": nm.to_lower(), "what": what, "text": text.to_lower()})


## Ranked matches for `text` (case-insensitive): name prefix, word prefix, name substring, then description; ties keep list order.
## Rows: `{kind, index, name, what, score}`.
func search(text: String, limit: int = 20) -> Array[Dictionary]:
	var q: String = text.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	if q.is_empty():
		return out
	for i: int in _index.size():
		var row: Dictionary = _index[i]
		var lower: String = row["lower"]
		var score: int = 0
		if lower.begins_with(q):
			score = 400
		elif (" " + lower).contains(" " + q):
			score = 300
		elif lower.contains(q):
			score = 200
		elif str(row["text"]).contains(q):
			score = 100
		if score > 0:
			out.append({"kind": row["kind"], "index": row["index"], "name": row["name"], "what": row["what"], "score": score * 1000 - i})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["score"]) > int(y["score"]))
	if out.size() > limit:
		out.resize(limit)
	return out
