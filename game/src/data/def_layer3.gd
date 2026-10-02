class_name DefLayer3
extends RefCounted
## Per-player runtime overlay of completed research (data_balance 3.7 / 5.8); owned by the player's DefPlayerView.
## Accumulates the permanent effects of every completed research: unconditional stat / resist deltas, param mods, flags
## and granted abilities; conditional effects (`cond_codes` != empty, fire-mode / arc filters) are exposed through
## `cond_effects_of_*` for the abilities domain. Same-stack-group effects count once per (def, stat): the larger |amount|
## wins, ties keep the earlier one (DefStatMath.stack_pick). Integer only; iteration is in completion / file order.

const _RESIST_N: int = DefEnums.DamageType.COUNT

var _cs_ok: bool = false  ## `_cs` is current (the accumulators only change in apply_research; hashing ~2000 ints per player cost 1.2 ms every checkpoint)
var _cs: int = 0
var data: GameData = null  ## not owned; GameData never references it (no cycle)
var roster: DefRoster = null
var version: int = 0  ## ++ on every apply_research
var completed: PackedInt32Array = PackedInt32Array()  ## research indices in completion order

var _unit_bp: PackedInt32Array = PackedInt32Array()  ## [def * STAT_COUNT + stat]
var _struct_bp: PackedInt32Array = PackedInt32Array()
var _unit_res: PackedInt32Array = PackedInt32Array()  ## [def * 7 + damage type]
var _struct_res: PackedInt32Array = PackedInt32Array()
var _best: Dictionary = {}  ## stack-group slot key -> best amount so far
var _cond_units: Dictionary = {}  ## unit idx -> Array[DefEffect]
var _cond_structs: Dictionary = {}
var _params: Array[Dictionary] = []  ## param records in completion order
var _flags: Dictionary = {}  ## "u<idx>" / "s<idx>" -> {flag: true}
var _granted_units: Dictionary = {}  ## unit idx -> Array[DefAbility]
var _granted_structs: Dictionary = {}


func _init(d: GameData, r: DefRoster) -> void:
	data = d
	roster = r
	_unit_bp.resize(d.units.size() * DefEnums.Stat.COUNT)
	_struct_bp.resize(d.structures.size() * DefEnums.Stat.COUNT)
	_unit_res.resize(d.units.size() * _RESIST_N)
	_struct_res.resize(d.structures.size() * _RESIST_N)


func is_done(research_idx: int) -> bool:
	return completed.has(research_idx)


## Applies every effect of a completed research (a second call for the same index is a no-op + push_error).
func apply_research(research_idx: int) -> void:
	if is_done(research_idx):
		push_error("DefLayer3.apply_research: research %d already completed" % research_idx)
		return
	if research_idx < 0 or research_idx >= data.research.size():
		push_error("DefLayer3.apply_research: unknown research %d" % research_idx)
		return
	completed.append(research_idx)
	version += 1
	for e: DefEffect in data.research[research_idx].effects:
		_apply_effect(e)
	_cs_ok = false  # the accumulators changed: the cached checksum is stale


func _apply_effect(e: DefEffect) -> void:
	match e.op:
		DefEnums.EffectOp.STAT_MOD:
			if e.stat < 0 or e.stat >= DefEnums.Stat.COUNT:
				return
			if not e.cond_codes.is_empty():
				_add_cond(e)
				return
			for u: int in _units_of(e):
				_accum(_unit_bp, 0, u * DefEnums.Stat.COUNT + e.stat, e.delta_bp, e.stack_group)
			for s: int in _structs_of(e):
				_accum(_struct_bp, 1, s * DefEnums.Stat.COUNT + e.stat, e.delta_bp, e.stack_group)
		DefEnums.EffectOp.RESIST_MOD:
			if not e.cond_codes.is_empty() or e.fire_mode_mask != 0 or e.frontal_arc_a != 0:
				_add_cond(e)
				return
			for dt: int in _RESIST_N:
				if not _resist_hits(e, dt):
					continue
				for u2: int in _units_of(e):
					_accum(_unit_res, 2, u2 * _RESIST_N + dt, e.delta_bp, e.stack_group)
				for s2: int in _structs_of(e):
					_accum(_struct_res, 3, s2 * _RESIST_N + dt, e.delta_bp, e.stack_group)
		DefEnums.EffectOp.PARAM_MOD:
			_params.append({"e": e, "units": _units_of(e), "structs": _structs_of(e)})
		DefEnums.EffectOp.GRANT_ABILITY:
			_grant(e)
		DefEnums.EffectOp.SET_FLAG:
			for u3: int in _units_of(e):
				_set_flag("u%d" % u3, e.flag)
			for s3: int in _structs_of(e):
				_set_flag("s%d" % s3, e.flag)


func _units_of(e: DefEffect) -> PackedInt32Array:
	return roster.selector_units(e.selector) if e.selector >= 0 else PackedInt32Array()


func _structs_of(e: DefEffect) -> PackedInt32Array:
	return roster.selector_structures(e.selector) if e.selector >= 0 else PackedInt32Array()


## group_mask 0 = every weapon group except EMP; else any shared bit.
func _resist_hits(e: DefEffect, dtype: int) -> bool:
	var gm: int = data.damage.group_mask[dtype]
	if e.group_mask == 0:
		return (gm & ~DefEnums.RG_EMP) != 0
	return (gm & e.group_mask) != 0


func _accum(arr: PackedInt32Array, arr_id: int, at: int, amount: int, group: int) -> void:
	if group < 0:
		arr[at] += amount
		return
	var key: int = ((arr_id * 4000000) + at) * 1024 + group
	if not _best.has(key):
		_best[key] = amount
		arr[at] += amount
		return
	var cur: int = _best[key]
	var pick: int = DefStatMath.stack_pick(cur, amount)
	if pick != cur:
		arr[at] += pick - cur
		_best[key] = pick


func _add_cond(e: DefEffect) -> void:
	for u: int in _units_of(e):
		if not _cond_units.has(u):
			_cond_units[u] = []
		(_cond_units[u] as Array).append(e)
	for s: int in _structs_of(e):
		if not _cond_structs.has(s):
			_cond_structs[s] = []
		(_cond_structs[s] as Array).append(e)


func _set_flag(key: String, flag: String) -> void:
	if not _flags.has(key):
		_flags[key] = {}
	(_flags[key] as Dictionary)[flag] = true


func _grant(e: DefEffect) -> void:
	if e.ability == null:
		return
	var replace: bool = bool(e.params.get("replace", false))
	for u: int in _units_of(e):
		var clone: DefUnit = roster.unit(u)
		if clone == null:
			continue
		if _may_grant(clone.ability_slot_of_kind, _granted_units.get(u, []), e.ability.kind, replace):
			_put_grant(_granted_units, u, e.ability)
	for s: int in _structs_of(e):
		var sc: DefStructure = roster.structure(s)
		if sc == null:
			continue
		if _may_grant(sc.ability_slot_of_kind, _granted_structs.get(s, []), e.ability.kind, replace):
			_put_grant(_granted_structs, s, e.ability)


func _may_grant(slots: PackedInt32Array, granted: Array, kind: int, replace: bool) -> bool:
	if replace:
		return true
	if kind >= 0 and kind < slots.size() and slots[kind] >= 0:
		return false
	for a: DefAbility in granted:
		if a.kind == kind:
			return false
	return true


func _put_grant(store: Dictionary, idx: int, ability: DefAbility) -> void:
	var list: Array = store.get(idx, [])
	for i: int in list.size():
		if (list[i] as DefAbility).kind == ability.kind:
			list[i] = ability.copy_resolved()
			store[idx] = list
			return
	list.append(ability.copy_resolved())
	store[idx] = list


# ---------------------------------------------------------------------------------------- stat accumulators
## Sigma unconditional research amount (bp) for (stat, def); no temporary effects.
func unit_stat_bp(stat: int, unit_idx: int) -> int:
	if unit_idx < 0 or stat < 0 or stat >= DefEnums.Stat.COUNT or unit_idx * DefEnums.Stat.COUNT + stat >= _unit_bp.size():
		return 0
	return _unit_bp[unit_idx * DefEnums.Stat.COUNT + stat]


func struct_stat_bp(stat: int, struct_idx: int) -> int:
	if struct_idx < 0 or stat < 0 or stat >= DefEnums.Stat.COUNT or struct_idx * DefEnums.Stat.COUNT + stat >= _struct_bp.size():
		return 0
	return _struct_bp[struct_idx * DefEnums.Stat.COUNT + stat]


## Sigma unconditional research resistance whose group mask intersects the damage type's, before the 50 % cap.
func unit_resist_bp(dtype: int, unit_idx: int) -> int:
	if unit_idx < 0 or dtype < 0 or dtype >= _RESIST_N or unit_idx * _RESIST_N + dtype >= _unit_res.size():
		return 0
	return _unit_res[unit_idx * _RESIST_N + dtype]


func struct_resist_bp(dtype: int, struct_idx: int) -> int:
	if struct_idx < 0 or dtype < 0 or dtype >= _RESIST_N or struct_idx * _RESIST_N + dtype >= _struct_res.size():
		return 0
	return _struct_res[struct_idx * _RESIST_N + dtype]


## Effective value: clamp(apply_bp(resolved, research bp + extra_bp)). `extra_bp` = sum of distinct-source temporary deltas.
func effective_unit_stat(stat: int, unit_idx: int, extra_bp: int = 0) -> int:
	var base_def: DefUnit = data.units[unit_idx]
	var res_def: DefUnit = roster.unit(unit_idx)
	if res_def == null:
		res_def = base_def
	return DefStatMath.effective(stat, unit_stat_value(stat, base_def), unit_stat_value(stat, res_def), unit_stat_bp(stat, unit_idx) + extra_bp, data.economy)


func effective_struct_stat(stat: int, struct_idx: int, extra_bp: int = 0) -> int:
	var base_def: DefStructure = data.structures[struct_idx]
	var res_def: DefStructure = roster.structure(struct_idx)
	if res_def == null:
		res_def = base_def
	return DefStatMath.effective(stat, struct_stat_value(stat, base_def), struct_stat_value(stat, res_def), struct_stat_bp(stat, struct_idx) + extra_bp, data.economy)


## The def value a layered stat scales (weapon stats: slot 0; RANGE: the unit's max range).
static func unit_stat_value(stat: int, u: DefUnit) -> int:
	var w: DefWeaponSlot = u.weapons[0] if not u.weapons.is_empty() else null
	match stat:
		DefEnums.Stat.COST:
			return u.cost
		DefEnums.Stat.BUILD_TIME:
			return u.build_ticks
		DefEnums.Stat.HEALTH:
			return u.health
		DefEnums.Stat.SPEED:
			return u.speed
		DefEnums.Stat.SIGHT:
			return u.sight
		DefEnums.Stat.REARM:
			return u.rearm_t
		DefEnums.Stat.REPAIR_COST:
			return u.repair_cost_bp
		DefEnums.Stat.RANGE:
			return u.max_range
		DefEnums.Stat.DAMAGE:
			return w.damage if w != null else 0
		DefEnums.Stat.RELOAD:
			return w.reload_mt if w != null else 0
		DefEnums.Stat.PROJ_SPEED:
			return w.proj_speed if w != null else 0
	return 0


static func struct_stat_value(stat: int, s: DefStructure) -> int:
	var w: DefWeaponSlot = s.weapons[0] if not s.weapons.is_empty() else null
	match stat:
		DefEnums.Stat.COST:
			return s.cost
		DefEnums.Stat.BUILD_TIME:
			return s.build_ticks
		DefEnums.Stat.HEALTH:
			return s.health
		DefEnums.Stat.SIGHT:
			return s.sight
		DefEnums.Stat.POWER:
			return s.power
		DefEnums.Stat.REPAIR_RATE:
			return s.repair_rate_bp
		DefEnums.Stat.REPAIR_COST:
			return s.repair_cost_bp
		DefEnums.Stat.RANGE:
			var m: int = 0
			for x: DefWeaponSlot in s.weapons:
				m = maxi(m, x.range)
			return m
		DefEnums.Stat.DAMAGE:
			return w.damage if w != null else 0
		DefEnums.Stat.RELOAD:
			return w.reload_mt if w != null else 0
		DefEnums.Stat.PROJ_SPEED:
			return w.proj_speed if w != null else 0
	return 0


# ------------------------------------------------------------------------------------------------ params
## Ability parameter after completed PARAM_MODs (order: every set (last wins) -> every add -> every mul_bp).
func ability_param(unit_idx: int, kind: int, key: String, base: int) -> int:
	return _fold_params(_records(DefEnums.ParamScope.ABILITY, kind, key, unit_idx, -1), base)


func struct_ability_param(struct_idx: int, kind: int, key: String, base: int) -> int:
	return _fold_params(_records(DefEnums.ParamScope.ABILITY, kind, key, -1, struct_idx), base)


func def_param(unit_idx: int, key: String, base: int) -> int:
	return _fold_params(_records(DefEnums.ParamScope.DEF, -1, key, unit_idx, -1), base)


func struct_def_param(struct_idx: int, key: String, base: int) -> int:
	return _fold_params(_records(DefEnums.ParamScope.DEF, -1, key, -1, struct_idx), base)


## Player-scope parameter; `key` is the runtime key ("reserve_t") or the full "defense_power_reserve.reserve_t".
func player_param(key: String, base: int) -> int:
	var recs: Array[DefEffect] = []
	for r: Dictionary in _params:
		var e: DefEffect = r["e"]
		if e.scope == DefEnums.ParamScope.PLAYER and (e.key == key or e.key.ends_with("." + key)):
			recs.append(e)
	return _fold_params(recs, base)


## The completed PARAM_MOD effects that apply to a unit / structure def's ability param (for `filter` evaluation).
func param_effects_for(unit_idx: int, kind: int, key: String) -> Array[DefEffect]:
	return _records(DefEnums.ParamScope.ABILITY, kind, key, unit_idx, -1)


func _records(scope: int, kind: int, key: String, unit_idx: int, struct_idx: int) -> Array[DefEffect]:
	var out: Array[DefEffect] = []
	for r: Dictionary in _params:
		var e: DefEffect = r["e"]
		if e.scope != scope or e.key != key or (scope == DefEnums.ParamScope.ABILITY and e.ability_kind != kind):
			continue
		if unit_idx >= 0 and (r["units"] as PackedInt32Array).has(unit_idx):
			out.append(e)
		elif struct_idx >= 0 and (r["structs"] as PackedInt32Array).has(struct_idx):
			out.append(e)
	return out


static func _fold_params(recs: Array[DefEffect], base: int) -> int:
	var v: int = base
	for e: DefEffect in recs:
		if e.param_op == DefEnums.ParamOp.SET:
			v = e.value
	for e2: DefEffect in recs:
		if e2.param_op == DefEnums.ParamOp.ADD:
			v += e2.value
	for e3: DefEffect in recs:
		if e3.param_op == DefEnums.ParamOp.MUL_BP:
			v = DefStatMath.apply_bp(v, e3.value - 10000)
	return v


func has_flag(unit_idx: int, flag: String) -> bool:
	return (_flags.get("u%d" % unit_idx, {}) as Dictionary).has(flag)


func struct_has_flag(struct_idx: int, flag: String) -> bool:
	return (_flags.get("s%d" % struct_idx, {}) as Dictionary).has(flag)


## Research-granted (runtime) abilities of a unit def.
func granted_abilities(unit_idx: int) -> Array[DefAbility]:
	var out: Array[DefAbility] = []
	for a: Variant in _granted_units.get(unit_idx, []):
		out.append(a as DefAbility)
	return out


func struct_granted_abilities(struct_idx: int) -> Array[DefAbility]:
	var out: Array[DefAbility] = []
	for a: Variant in _granted_structs.get(struct_idx, []):
		out.append(a as DefAbility)
	return out


## Conditional research effects that target this def; the abilities domain evaluates cond_codes / cond_params.
func cond_effects_of_unit(unit_idx: int) -> Array[DefEffect]:
	var out: Array[DefEffect] = []
	for e: Variant in _cond_units.get(unit_idx, []):
		out.append(e as DefEffect)
	return out


func cond_effects_of_struct(struct_idx: int) -> Array[DefEffect]:
	var out: Array[DefEffect] = []
	for e: Variant in _cond_structs.get(struct_idx, []):
		out.append(e as DefEffect)
	return out


## Hash over version, completed and every accumulator; the sim mixes it into its checksum.
func checksum() -> int:
	if _cs_ok:
		return _cs
	_cs = _compute_checksum()
	_cs_ok = true
	return _cs


func _compute_checksum() -> int:
	var h: int = DefHash.mix_int(DefHash.OFFSET, version)
	h = DefHash.mix_variant(h, completed)
	h = DefHash.mix_variant(h, _unit_bp)
	h = DefHash.mix_variant(h, _struct_bp)
	h = DefHash.mix_variant(h, _unit_res)
	h = DefHash.mix_variant(h, _struct_res)
	for r: Dictionary in _params:
		var e: DefEffect = r["e"]
		h = DefHash.mix_int(h, e.scope)
		h = DefHash.mix_int(h, e.ability_kind)
		h = DefHash.mix_str(h, e.key)
		h = DefHash.mix_int(h, e.param_op)
		h = DefHash.mix_int(h, e.value)
		h = DefHash.mix_variant(h, r["units"])
		h = DefHash.mix_variant(h, r["structs"])
	h = DefHash.mix_variant(h, _flags)
	var uk: Array = _granted_units.keys()
	uk.sort()
	for k: int in uk:
		h = DefHash.mix_int(h, k)
		for a: DefAbility in _granted_units[k]:
			h = DefHash.mix_variant(h, a)
	var sk: Array = _granted_structs.keys()
	sk.sort()
	for k2: int in sk:
		h = DefHash.mix_int(h, k2)
		for a2: DefAbility in _granted_structs[k2]:
			h = DefHash.mix_variant(h, a2)
	var ck: Array = _cond_units.keys()
	ck.sort()
	for k3: int in ck:
		h = DefHash.mix_int(DefHash.mix_int(h, k3), (_cond_units[k3] as Array).size())
	return h
