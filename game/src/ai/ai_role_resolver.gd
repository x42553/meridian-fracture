class_name AiRoleResolver
extends RefCounted
## Roles resolved from bible tags for ONE roster (ai.md 5.5.1). A role is a BIT on a def (AiTypes.R_*); the per-role def lists
## come from DefRoster.producible_units (ascending (tier, cost, index), replaced units excluded, so a replaced unit can never
## be picked), the rules from ai_roles.json (tags never ids, except the explicit `ids` / `unit_roles` lists). A missing role
## means the role is excluded from composition (`missing_roles`), never a crash.

var roster: DefRoster = null
var role_units: Array[PackedInt32Array] = []  ## by role bit; producible defs, roster order
var role_mask: PackedInt64Array = PackedInt64Array()  ## by unit def index: OR of 1 << role (any roster unit, also non-producible)
var handler_mask: PackedInt32Array = PackedInt32Array()  ## by unit def index: OR of 1 << handler
var struct_kind: PackedInt32Array = PackedInt32Array()  ## by structure def index: AiTypes.StructKind (-1 = not in the roster)
var missing_roles: PackedInt32Array = PackedInt32Array()  ## essential roles with no producible def


## The roles every playable roster must have (ai.md 10.1 test_ai_roles).
const ESSENTIAL: PackedInt32Array = [
	AiTypes.R_INFANTRY_BASIC, AiTypes.R_INFANTRY_AT, AiTypes.R_SCOUT_LIGHT, AiTypes.R_TANK_MAIN, AiTypes.R_AA_MOBILE, AiTypes.R_FIGHTER,
]


static func resolve(data: GameData, p_roster: DefRoster, store: AiDataStore) -> AiRoleResolver:
	var r: AiRoleResolver = AiRoleResolver.new()
	r.roster = p_roster
	for _i: int in AiTypes.ROLE_COUNT:
		r.role_units.append(PackedInt32Array())
	var nu: int = data.units.size()
	r.role_mask.resize(nu)
	r.role_mask.fill(0)
	r.handler_mask.resize(nu)
	r.handler_mask.fill(0)
	var cfg: Dictionary = store.roles_cfg
	var rules: Dictionary = cfg.get("roles", {})
	var lists: Dictionary = cfg.get("unit_roles", {})
	# ---- tag / id rules ----
	for rn: String in rules:
		var bit: int = AiTypes.role_bit(rn)
		if bit < 0:
			continue
		var rule: Dictionary = rules[rn]
		r._apply_rule(data, bit, rule)
	# ---- explicit lists ----
	for rn2: String in lists:
		var bit2: int = AiTypes.role_bit(rn2)
		if bit2 < 0:
			continue
		for uid: Variant in lists[rn2]:
			var ui: int = data.unit_idx(str(uid))
			if ui >= 0 and r._in_roster(ui):
				r._add(bit2, ui, r._producible(ui))
	# ---- global masks: COMBAT bit already by rule; STRUCTURE bit belongs to structure profiles ----
	# ---- handlers ----
	var hcfg: Dictionary = cfg.get("unit_handlers", {})
	for uid2: String in hcfg:
		var ui2: int = data.unit_idx(uid2)
		if ui2 < 0 or ui2 >= nu:
			continue
		for hn: Variant in hcfg[uid2]:
			var hb: int = AiTypes.handler_bit(str(hn))
			if hb >= 0:
				r.handler_mask[ui2] |= 1 << hb
	r._seed_handlers(data, p_roster)
	# ---- structure kinds ----
	r.struct_kind.resize(data.structures.size())
	for si: int in data.structures.size():
		r.struct_kind[si] = classify_structure(data, p_roster, si) if p_roster.has_structure(si) else -1
	for e: int in ESSENTIAL:
		if r.role_units[e].is_empty():
			r.missing_roles.append(e)
	return r


## Handler bits seeded from the resolved defs' abilities (ai.md 5.9.5); the explicit `unit_handlers` list of ai_roles.json is OR-ed
## on top. Applies to every unit of the roster (also non-producible ones such as summons).
func _seed_handlers(_data: GameData, p_roster: DefRoster) -> void:
	for d: DefUnit in p_roster.units:
		if d == null or d.index < 0 or d.index >= handler_mask.size():
			continue
		var m: int = 0
		var armed: bool = not d.weapons.is_empty()
		var aircraft: bool = (d.tags & DefEnums.UT_AIRCRAFT) != 0
		if d.has_ability(DefEnums.AbilityKind.DEPLOY):
			if d.has_ability(DefEnums.AbilityKind.COMMAND_FIELD):
				m |= _hb("ESCORT_PROVIDER")
			elif armed and ((d.tags & (DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE)) != 0 or d.min_range > 0 or d.max_range >= 8 * Fp.CELL):
				m |= _hb("DEPLOY_SIEGE")
			elif armed:
				m |= _hb("COVER_DEPLOY")
		if d.has_ability(DefEnums.AbilityKind.MODE_SWITCH):
			if aircraft:
				m |= _hb("LOADOUT")
			elif (d.tags & DefEnums.UT_CARRIER) != 0:
				m |= _hb("WING_SWITCH")
			else:
				m |= _hb("MODE_SWITCH")
		if d.has_ability(DefEnums.AbilityKind.CAMOUFLAGE):
			m |= _hb("CAMO_HOLD")
		if d.has_ability(DefEnums.AbilityKind.INTERCEPTOR):
			m |= _hb("AP_INTERCEPT")
		if d.has_ability(DefEnums.AbilityKind.TRANSPORT):
			m |= _hb("TRANSPORT_SHUTTLE")
		if d.has_ability(DefEnums.AbilityKind.DISEMBARK_BUFF):
			m |= _hb("LANDING_BONUS")
		if d.has_ability(DefEnums.AbilityKind.CARRIER):
			m |= _hb("CARRIER_ESCORT")
		if d.has_ability(DefEnums.AbilityKind.HEAL):
			m |= _hb("HEALER_FOLLOW")
		if d.has_ability(DefEnums.AbilityKind.REPAIR) and d.index != data_engineer_idx(_data):
			m |= _hb("REPAIR_FOLLOW")
		if d.has_ability(DefEnums.AbilityKind.SALVAGE):
			m |= _hb("SALVAGE")
		if d.has_ability(DefEnums.AbilityKind.COMMAND_FIELD):
			m |= _hb("ESCORT_PROVIDER")
		if d.has_ability(DefEnums.AbilityKind.SENSOR_MAST):
			m |= _hb("MAST_DEPLOY")
		if d.has_ability(DefEnums.AbilityKind.SPOTTER):
			m |= _hb("SPOTTER_LINK")
		if d.has_ability(DefEnums.AbilityKind.DECOY_SPAWN):
			m |= _hb("DECOY_PLACE")
		if d.has_ability(DefEnums.AbilityKind.SENSOR_PUCK):
			m |= _hb("PUCK_PLACE")
		if d.has_ability(DefEnums.AbilityKind.PORTABLE_COVER):
			m |= _hb("COVER_DEPLOY")
		if d.has_ability(DefEnums.AbilityKind.SMOKE_LAUNCHER):
			m |= _hb("SMOKE_ON_RETREAT")
		if d.has_ability(DefEnums.AbilityKind.EW_JAMMER):
			m |= _hb("EW_ESCORT")
		handler_mask[d.index] |= m


static func _hb(hname: String) -> int:
	var b: int = AiTypes.handler_bit(hname)
	return 1 << b if b >= 0 else 0


static func data_engineer_idx(data: GameData) -> int:
	return data.unit_idx("unit.shared.engineer")


func _in_roster(u: int) -> bool:
	return roster.has_unit(u)


func _producible(u: int) -> bool:
	return roster.producible_units.has(u)


func _replaced(u: int) -> bool:
	return roster.replaced_by.has(u)


## Adds def `u` to a role: the mask always, the role list only for producible defs.
func _add(role: int, u: int, producible: bool) -> void:
	role_mask[u] = role_mask[u] | (1 << role)
	if producible and not role_units[role].has(u):
		role_units[role].append(u)


func _apply_rule(data: GameData, role: int, rule: Dictionary) -> void:
	var ids: Array = rule.get("ids", [])
	if not ids.is_empty():
		for uid: Variant in ids:
			var ui: int = data.unit_idx(str(uid))
			if ui >= 0 and _in_roster(ui):
				_add(role, ui, _producible(ui))
		return
	var all_m: int = data.tags.unit_mask(_names(rule.get("all", [])))
	var none_m: int = data.tags.unit_mask(_names(rule.get("none", [])))
	var tier_max: int = int(rule.get("tier_max", 0))
	var lowest: bool = str(rule.get("pick", "")) == "lowest_tier"
	var matched: Array[int] = []
	var best_tier: int = 1 << 20
	for u: int in roster.producible_units:
		var d: DefUnit = roster.unit(u)
		if d == null or (d.tags & all_m) != all_m or (d.tags & none_m) != 0:
			continue
		if tier_max > 0 and d.tier > tier_max:
			continue
		matched.append(u)
		best_tier = mini(best_tier, d.tier)
	for u2: int in matched:
		if lowest and roster.unit(u2).tier != best_tier:
			continue
		_add(role, u2, true)
	# non-producible roster units (summons, drones, service) get the mask bit from the tag rule alone
	for d2: DefUnit in roster.units:
		if d2 == null or _producible(d2.index) or _replaced(d2.index):
			continue
		if (d2.tags & all_m) == all_m and (d2.tags & none_m) == 0 and (tier_max <= 0 or d2.tier <= tier_max):
			_add(role, d2.index, false)


static func _names(a: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: Variant in a:
		out.append(str(n))
	return out


# ---------------------------------------------------------------------------------------------------- queries
func units_of(role: int) -> PackedInt32Array:
	return role_units[role]


func has_role(role: int) -> bool:
	return not role_units[role].is_empty()


## First producible def of the role (lowest tier, cost, index) or -1.
func first(role: int) -> int:
	var l: PackedInt32Array = role_units[role]
	return l[0] if not l.is_empty() else -1


## Tier at which the role first becomes producible (the AiTechGraph.reachable_tier basis), -1 when the roster lacks it.
func min_tier(role: int) -> int:
	var best: int = -1
	for u: int in role_units[role]:
		var t: int = roster.unit(u).tier
		if best < 0 or t < best:
			best = t
	return best


func mask_of(def_idx: int) -> int:
	return role_mask[def_idx] if def_idx >= 0 and def_idx < role_mask.size() else 0


func handlers_of(def_idx: int) -> int:
	return handler_mask[def_idx] if def_idx >= 0 and def_idx < handler_mask.size() else 0


func has_bit(def_idx: int, role: int) -> bool:
	return (mask_of(def_idx) & (1 << role)) != 0


func kind_of_structure(s_idx: int) -> int:
	return struct_kind[s_idx] if s_idx >= 0 and s_idx < struct_kind.size() else AiTypes.StructKind.OTHER


## First structure def of the roster with the given kind (lowest index among producible ones, HQ allowed), -1 if none.
func structure_of_kind(kind: int) -> int:
	for s: int in roster.producible_structures:
		if struct_kind[s] == kind:
			return s
	if kind == AiTypes.StructKind.HQ:
		return roster.hq_idx
	return -1


## StructKind of a structure def from its DATA (queue kind, power, defense weapons, requirements); no ids.
static func classify_structure(data: GameData, p_roster: DefRoster, s_idx: int) -> int:
	var s: DefStructure = p_roster.structure(s_idx)
	if s == null:
		return AiTypes.StructKind.OTHER
	if s.build_radius > 0 or (s.flags & DefEnums.SF_NO_BUILD) != 0:
		return AiTypes.StructKind.HQ
	if s.superweapon >= 0 or (s.tags & DefEnums.ST_SUPERWEAPON) != 0:
		return AiTypes.StructKind.SUPERWEAPON
	if s.power > 0:
		return AiTypes.StructKind.GENERATOR
	match s.queue_kind:
		DefEnums.QueueKind.COLLECTOR:
			return AiTypes.StructKind.REFINERY
		DefEnums.QueueKind.INFANTRY:
			return AiTypes.StructKind.BARRACKS
		DefEnums.QueueKind.VEHICLE:
			return AiTypes.StructKind.FACTORY
		DefEnums.QueueKind.NAVAL:
			return AiTypes.StructKind.DOCK
		DefEnums.QueueKind.AIRCRAFT:
			return AiTypes.StructKind.AIRFIELD
	if (s.flags & DefEnums.SF_RELAY) != 0 or (s.tags & DefEnums.ST_RELAY) != 0:
		return AiTypes.StructKind.RELAY
	if (s.tags & DefEnums.ST_ADVANCED_DEFENSE) != 0:
		return AiTypes.StructKind.ADV_DEFENSE
	if (s.tags & DefEnums.ST_DEFENSE) != 0 or (s.flags & DefEnums.SF_POWERED_DEFENSE) != 0:
		if (s.weapon_tags & DefEnums.WT_ANTI_AIR) != 0 and (s.weapon_tags & DefEnums.WT_ANTI_GROUND) == 0:
			return AiTypes.StructKind.AA_BATTERY
		if _requires_kind(data, s, DefEnums.QueueKind.VEHICLE):
			return AiTypes.StructKind.AT_TURRET
		return AiTypes.StructKind.WATCHTOWER
	# the two tech buildings: Radar requires a Factory, the Laboratory requires the Radar
	for q: int in s.requires:
		var rq: DefStructure = data.structures[q]
		if rq.queue_kind == DefEnums.QueueKind.VEHICLE:
			return AiTypes.StructKind.RADAR
		if rq.queue_kind == DefEnums.QueueKind.NONE and rq.power <= 0 and rq.build_radius == 0:
			for q2: int in rq.requires:
				if data.structures[q2].queue_kind == DefEnums.QueueKind.VEHICLE:
					return AiTypes.StructKind.LAB
	return AiTypes.StructKind.OTHER


static func _requires_kind(data: GameData, s: DefStructure, queue_kind: int) -> bool:
	for q: int in s.requires:
		if data.structures[q].queue_kind == queue_kind:
			return true
	return false
