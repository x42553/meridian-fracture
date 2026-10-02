extends RefCounted
## AB-08 research: a GENERATED test over every effect of every entry of research_effects.json (40 entries). Each effect is
## applied to a live unit / structure of a roster that can use it, through the same path production uses (DefLayer3 +
## economy knobs + the abilities hook), and the effect must appear in sim state: a stat on the entity, a combat weapon
## number, a resistance, an ability parameter, a granted slot, a flag, an economy knob - or, for conditional effects, a
## bound condition that becomes true once the condition is arranged.

const K := preload("res://src/sim/abilities/sim_ability_consts.gd")
const A := preload("res://tests/support/ab2_kit.gd")
const C := preload("res://src/sim/combat/sim_combat_consts.gd")

const CELL: int = 1024

var _counts: Dictionary = {}


func _note(kind: String) -> void:
	_counts[kind] = int(_counts.get(kind, 0)) + 1


## A roster (any faction, the research's own first) in which the effect's selector matches something.
func _roster_for(d: GameData, r: DefResearch, fx: DefEffect) -> DefRoster:
	var fac: String = r.id.split(".")[1]
	var best: DefRoster = null
	var best_n: int = 0
	for ro: DefRoster in d.rosters:
		var n: int = 0
		if fx.selector >= 0:
			n = ro.selector_units(fx.selector).size() + ro.selector_structures(fx.selector).size()
		var own: bool = ro.id.begins_with("roster.%s." % fac)
		var score: int = n * 2 + (1 if own else 0) if n > 0 else 0
		if score > best_n:
			best = ro
			best_n = score
	return best


func _enemy_roster(mine: DefRoster) -> String:
	return "roster.nec.vanilla" if not mine.id.contains(".nec.") else "roster.napc.vanilla"


func _first_unit(ro: DefRoster, fx: DefEffect) -> int:
	for u: int in ro.selector_units(fx.selector):
		var du: DefUnit = ro.units[u]
		if not du.id.begins_with("summon.") and du.pop >= 0:
			return u
	return -1


func _complete(w: SimWorld, r_idx: int) -> void:
	# exactly production's completion path (SimProductionSystem._complete_research)
	var p: SimPlayer = w.players[0]
	p.econ.researched[r_idx] = 1
	p.view.apply_research(r_idx)
	w.production.apply_research_knobs(w, 0, r_idx)
	w.abilities.on_research_complete(0, r_idx)


func _spawn_def(w: SimWorld, ro: DefRoster, fx: DefEffect, cx: int, cy: int) -> SimEntity:
	var u: int = _first_unit(ro, fx)
	if u >= 0:
		return A.spawn(w, ro.units[u].id, 0, cx, cy)
	for s: int in ro.selector_structures(fx.selector):
		return A.structure(w, ro.structures[s].id, 0, cx, cy)
	return null


func _world(ro: DefRoster, rows: PackedStringArray = PackedStringArray()) -> SimWorld:
	var o: Dictionary = {"rosters": [ro.id, _enemy_roster(ro)], "movement": false}
	if not rows.is_empty():
		o["rows"] = rows
	return A.world(o)


func _bound(w: SimWorld, e: SimEntity, fx: DefEffect) -> bool:
	var idx: int = w.abilities.fx_table.index_of(fx)
	return e.stats != null and idx >= 0 and e.stats.cond_fx.has(idx)


func _cond_active(w: SimWorld, e: SimEntity, fx: DefEffect) -> bool:
	var idx: int = w.abilities.fx_table.index_of(fx)
	if e.stats == null or e.abil == null:
		return false
	var pos: int = e.stats.cond_fx.find(idx)
	return pos >= 0 and ((e.abil.cond_bits >> pos) & 1) == 1


func _first_int(v: Variant) -> int:
	if v is Array and not (v as Array).is_empty():
		return int((v as Array)[0])
	if v is PackedInt32Array and not (v as PackedInt32Array).is_empty():
		return (v as PackedInt32Array)[0]
	return -1


func _within(actual: int, expected: int, tol_bp: int) -> bool:
	return absi(actual - expected) * 10000 <= maxi(absi(expected), 1) * tol_bp + 10000


func test_every_research_effect_appears_in_sim_state(t: TestCtx) -> void:
	var d: GameData = A.data()
	t.eq(d.research.size(), 40, "40 research entries")
	for r_idx: int in d.research.size():
		var r: DefResearch = d.research[r_idx]
		t.check(not r.effects.is_empty(), "%s has effects" % r.id)
		var applied_knobs: bool = false
		for fx: DefEffect in r.effects:
			var ro: DefRoster = _roster_for(d, r, fx) if fx.selector >= 0 else d.rosters[d.roster_idx("roster.nec.vanilla")]
			if not t.not_null(ro, "%s: a roster whose selector matches" % r.id):
				continue
			match fx.op:
				DefEnums.EffectOp.STAT_MOD:
					_stat_mod(t, d, r, r_idx, fx, ro)
				DefEnums.EffectOp.RESIST_MOD:
					_resist_mod(t, d, r, r_idx, fx, ro)
				DefEnums.EffectOp.PARAM_MOD:
					_param_mod(t, d, r, r_idx, fx, ro)
				DefEnums.EffectOp.GRANT_ABILITY:
					_grant(t, d, r, r_idx, fx, ro)
				DefEnums.EffectOp.SET_FLAG:
					_flag(t, d, r, r_idx, fx, ro)
				_:
					t.fail("%s: unexpected research op %d" % [r.id, fx.op])
		if applied_knobs:
			_note("knob")
	var keys: Array = _counts.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k: Variant in keys:
		parts.append("%s=%d" % [str(k), int(_counts[k])])
	t.note("research effects verified: " + ", ".join(parts))


# ---- STAT_MOD -----------------------------------------------------------------------------------------------------

func _stat_mod(t: TestCtx, d: GameData, r: DefResearch, r_idx: int, fx: DefEffect, ro: DefRoster) -> void:
	var w: SimWorld = _world(ro)
	var label: String = "%s %s" % [r.id, DefEnums.STAT_NAMES[fx.stat]]
	var e: SimEntity = _spawn_def(w, ro, fx, 30, 30)
	if not t.not_null(e, label + ": an entity to apply it to"):
		return
	A.hold_fire(w)
	A.run(w, 1)
	if not fx.cond_codes.is_empty():
		t.check(not _bound(w, e, fx), label + ": not bound before the research")
		_complete(w, r_idx)
		A.run(w, 2)
		t.check(_bound(w, e, fx), label + ": the conditional effect is bound after the research")
		_note("cond_bound")
		if _arrange_condition(t, w, d, ro, fx, label):
			t.check(_cond_active(w, e, fx), label + ": active once its condition holds")
			_note("cond_active")
		return
	var before: int = _stat_probe(w, e, fx.stat)
	_complete(w, r_idx)
	A.run(w, 2)
	var after: int = _stat_probe(w, e, fx.stat)
	var l3: DefLayer3 = w.players[0].view.layer3
	var bp: int = l3.struct_stat_bp(fx.stat, e.def_idx) if e.kind == SimEntity.Kind.STRUCTURE else l3.unit_stat_bp(fx.stat, e.def_idx)
	t.check(bp != 0 and (bp > 0) == (fx.delta_bp > 0), label + ": the research layer holds %d bp" % bp)
	if before <= 0:
		_note("stat_layer")
		return
	match fx.stat:
		DefEnums.Stat.HEALTH, DefEnums.Stat.SPEED, DefEnums.Stat.SIGHT, DefEnums.Stat.DAMAGE, DefEnums.Stat.RANGE:
			t.check((after > before) == (fx.delta_bp > 0) and after != before, label + ": %d -> %d in sim state" % [before, after])
			t.check(_within(after * 10000 / before, 10000 + fx.delta_bp, 250), label + ": magnitude %d bp (got %d)" % [fx.delta_bp, after * 10000 / before - 10000])
		DefEnums.Stat.RELOAD:
			t.check(after < before, label + ": reload interval shortens (%d -> %d)" % [before, after])
		_:
			t.check(after != before or bp != 0, label + ": changed")
	_note("stat_" + DefEnums.STAT_NAMES[fx.stat])


## The sim-state reading of a stat: local stats through the abilities facade, weapon numbers through combat's compiled
## slot stats, the rest through the research layer.
func _stat_probe(w: SimWorld, e: SimEntity, stat: int) -> int:
	match stat:
		DefEnums.Stat.HEALTH:
			return e.hp_max
		DefEnums.Stat.SPEED:
			return w.abilities.speed_units(e)
		DefEnums.Stat.SIGHT:
			return w.abilities.sight_units(e)
		DefEnums.Stat.DAMAGE, DefEnums.Stat.RANGE, DefEnums.Stat.RELOAD:
			var cd: SimCombatDef = w.combat.def_for(w, e)
			if cd == null or cd.n_mounts == 0:
				return 0
			return w.combat.slot_stat(w, e, cd, 0, stat)
	var l3: DefLayer3 = w.players[0].view.layer3
	return l3.effective_struct_stat(stat, e.def_idx) if e.kind == SimEntity.Kind.STRUCTURE else l3.effective_unit_stat(stat, e.def_idx)


## Arranges a research condition around e; false when the condition needs a scenario this test does not build (the
## binding is still asserted; the condition itself has its own tests in test_abil_cond / test_ab2_auras).
func _arrange_condition(t: TestCtx, w: SimWorld, d: GameData, ro: DefRoster, fx: DefEffect, label: String) -> bool:
	var code: int = fx.cond_codes[0]
	var cp: Dictionary = fx.cond_params[0]
	match code:
		DefEnums.Cond.NEAR_FRIENDLY_STRUCTURE:
			var radius: int = int(cp.get("radius_u", 6144))
			var sid: int = -1
			var list: Variant = cp.get("structure_idx", [])
			if _first_int(list) >= 0:
				sid = _first_int(list)
			elif int(cp.get("selector_idx", -1)) >= 0:
				var ss: PackedInt32Array = ro.selector_structures(int(cp["selector_idx"]))
				if not ss.is_empty():
					sid = ss[0]
			if not t.check(sid >= 0, label + ": a structure for the near-structure condition"):
				return false
			var s: SimEntity = A.structure(w, d.structures[sid].id, 0, 30 + 1 + radius / CELL / 2, 30)
			s.flags &= ~SimFlags.F_UNDER_CONSTRUCTION
			A.run(w, 30)
			return true
		DefEnums.Cond.NEAR_FRIENDLY_UNIT:
			var uid: int = _first_int(cp.get("unit_idx", []))
			if not t.check(uid >= 0, label + ": a unit for the near-unit condition"):
				return false
			A.spawn(w, d.units[uid].id, 0, 33, 30)
			A.run(w, 30)
			return true
		DefEnums.Cond.STATIONARY, DefEnums.Cond.OUT_OF_COMBAT:
			A.run(w, int(cp.get("for_t", 0)) + 40)
			return true
	return false


# ---- RESIST_MOD ---------------------------------------------------------------------------------------------------

func _resist_mod(t: TestCtx, d: GameData, r: DefResearch, r_idx: int, fx: DefEffect, ro: DefRoster) -> void:
	var w: SimWorld = _world(ro)
	var label: String = "%s resist" % r.id
	var e: SimEntity = _spawn_def(w, ro, fx, 30, 30)
	if not t.not_null(e, label + ": an entity"):
		return
	A.hold_fire(w)
	A.run(w, 1)
	if not fx.cond_codes.is_empty() or fx.fire_mode_mask != 0 or fx.frontal_arc_a != 0:
		_complete(w, r_idx)
		A.run(w, 2)
		t.check(_bound(w, e, fx), label + ": bound as a conditional effect")
		_note("cond_bound")
		if fx.cond_codes.has(DefEnums.Cond.ON_WATER_RT) or fx.cond_codes.has(DefEnums.Cond.ON_WATER):
			var rows: PackedStringArray = A.MV.grid(64)
			A.MV.rect(rows, 20, 20, 44, 44, "~")
			var w2: SimWorld = _world(ro, rows)
			var e2: SimEntity = _spawn_def(w2, ro, fx, 30, 30)
			A.hold_fire(w2)
			_complete(w2, r_idx)
			A.run(w2, 40)
			if e2 != null and _bound(w2, e2, fx):
				t.check(_cond_active(w2, e2, fx), label + ": active while on water")
				_note("cond_active")
		elif _arrange_condition(t, w, d, ro, fx, label):
			t.check(_cond_active(w, e, fx), label + ": active once its condition holds")
			_note("cond_active")
		return
	var dtypes: PackedInt32Array = PackedInt32Array()
	for dt: int in DefEnums.DamageType.COUNT:
		if dt != DefEnums.DamageType.EMP and (fx.group_mask == 0 or (d.damage.group_mask[dt] & fx.group_mask) != 0):
			dtypes.append(dt)
	var base: int = w.combat.research_resist_bp(w, e, dtypes[0])
	_complete(w, r_idx)
	A.run(w, 2)
	var got: int = w.combat.research_resist_bp(w, e, dtypes[0])
	t.eq(got - base, fx.delta_bp, label + ": combat reads %d bp against damage type %d" % [fx.delta_bp, dtypes[0]])
	_note("resist")


# ---- PARAM_MOD ----------------------------------------------------------------------------------------------------

func _fold(base: int, fx: DefEffect) -> int:
	match fx.param_op:
		DefEnums.ParamOp.SET:
			return fx.value
		DefEnums.ParamOp.ADD:
			return base + fx.value
	return DefStatMath.apply_bp(base, fx.value - 10000)


func _param_mod(t: TestCtx, _d: GameData, r: DefResearch, r_idx: int, fx: DefEffect, ro: DefRoster) -> void:
	var label: String = "%s %s.%s" % [r.id, DefEnums.ABILITY_NAMES[fx.ability_kind] if fx.ability_kind >= 0 else "def", fx.key]
	var base: int = 1000  # an arbitrary base: the fold is what is verified
	if fx.scope == DefEnums.ParamScope.PLAYER:
		var wp: SimWorld = _world(ro)
		_complete(wp, r_idx)
		var lp: DefLayer3 = wp.players[0].view.layer3
		t.eq(lp.player_param(fx.key, base), _fold(base, fx), label + ": player parameter")
		# the economy owns this one: the SAP reserve knob
		if r.id == "research.sap.reserve_capacitors":
			t.eq(wp.economy.knob(0, SimEconConst.K_SAP_RESERVE_TICKS), 700, label + ": the reserve knob reads 35 s")
			_note("knob")
		_note("param_player")
		return
	var w: SimWorld = _world(ro)
	var e: SimEntity = _spawn_def(w, ro, fx, 30, 30)
	if not t.not_null(e, label + ": an entity"):
		return
	A.hold_fire(w)
	_complete(w, r_idx)
	A.run(w, 2)
	var l3: DefLayer3 = w.players[0].view.layer3
	if fx.scope == DefEnums.ParamScope.DEF:
		var got_d: int = l3.struct_def_param(e.def_idx, fx.key, base) if e.kind == SimEntity.Kind.STRUCTURE else l3.def_param(e.def_idx, fx.key, base)
		t.eq(got_d, _fold(base, fx), label + ": def parameter")
		_note("param_def")
	else:
		var got: int = w.abilities.ability_param(w, e, fx.ability_kind, fx.key, base)
		if fx.filter.is_empty():
			t.eq(got, _fold(base, fx), label + ": ability parameter through the abilities facade")
		else:
			t.check(got == _fold(base, fx) or got == base, label + ": filtered parameter is folded or left (filter applies at the consumer)")
		_note("param_ability")
	# economy-side effects of the same entry
	var knob_hits: Dictionary = {
		"research.napc.dispersed_runways": [SimEconConst.K_PAD_EXTRA, 2], "research.pd.integrated_flight_decks": [SimEconConst.K_REARM_RATE_BP, 11765],
		"research.ae.recovery_winches": [SimEconConst.K_SALVAGE_TICKS, 100], "research.def.standardized_parts": [SimEconConst.K_REPAIR_COST_ENG_VEH_BP, 8500],
		"research.nec.tunnel_workshops": [SimEconConst.K_REPAIR_RATE_DEF_BP, 12500], "research.pd.expeditionary_maintenance": [SimEconConst.K_REPAIR_RATE_TECH_BP, 12500],
		"research.han.modular_servicing": [SimEconConst.K_REPAIR_RATE_TENDER_BP, 15000], "research.def.buried_command_lines": [SimEconConst.K_EMP_RECOVERY_STRUCT_BP, 7500],
		"research.han.resilient_mesh": [SimEconConst.K_EMP_RECOVERY_UNMANNED_BP, 7500], "research.nec.distributed_control": [SimEconConst.K_RELAY_RADIUS_CELLS, 8],
		"research.han.distributed_cognition": [SimEconConst.K_CMD_RADIUS_CELLS, 7],
	}
	if knob_hits.has(r.id):
		var kv: Array = knob_hits[r.id]
		t.eq(w.economy.knob(0, int(kv[0])), int(kv[1]), label + ": economy knob %d" % int(kv[0]))
		_note("knob")


# ---- GRANT_ABILITY / SET_FLAG -------------------------------------------------------------------------------------

func _grant(t: TestCtx, _d: GameData, r: DefResearch, r_idx: int, fx: DefEffect, ro: DefRoster) -> void:
	var w: SimWorld = _world(ro)
	var label: String = "%s grant %s" % [r.id, DefEnums.ABILITY_NAMES[fx.ability_kind]]
	var e: SimEntity = _spawn_def(w, ro, fx, 30, 30)
	if not t.not_null(e, label + ": an entity"):
		return
	A.run(w, 1)
	var had: bool = e.abil != null and e.abil.slot_of_kind(fx.ability_kind) >= 0
	_complete(w, r_idx)
	A.run(w, 2)
	var executed: bool = ((K.EXECUTED_MASK >> fx.ability_kind) & 1) != 0
	if executed:
		t.check(e.abil != null and e.abil.slot_of_kind(fx.ability_kind) >= 0, label + ": the entity has the slot now (had it before: %s)" % str(had))
	else:
		t.check(w.players[0].view.layer3.granted_abilities(e.def_idx).size() > 0 or w.players[0].view.layer3.struct_granted_abilities(e.def_idx).size() > 0 or had,
			label + ": recorded in the research layer (executed by its own domain)")
	# a unit spawned AFTER the research gets it as well
	var e2: SimEntity = _spawn_def(w, ro, fx, 32, 30)
	A.run(w, 2)
	if executed:
		t.check(e2.abil != null and e2.abil.slot_of_kind(fx.ability_kind) >= 0, label + ": units created later get the slot too")
	_note("grant")


func _flag(t: TestCtx, _d: GameData, r: DefResearch, r_idx: int, fx: DefEffect, ro: DefRoster) -> void:
	var w: SimWorld = _world(ro)
	var e: SimEntity = _spawn_def(w, ro, fx, 30, 30)
	if not t.not_null(e, "%s flag: an entity" % r.id):
		return
	var l3: DefLayer3 = w.players[0].view.layer3
	var before: bool = l3.struct_has_flag(e.def_idx, fx.flag) if e.kind == SimEntity.Kind.STRUCTURE else l3.has_flag(e.def_idx, fx.flag)
	_complete(w, r_idx)
	var after: bool = l3.struct_has_flag(e.def_idx, fx.flag) if e.kind == SimEntity.Kind.STRUCTURE else l3.has_flag(e.def_idx, fx.flag)
	t.check(not before and after, "%s: flag '%s' set for the unit" % [r.id, fx.flag])
	_note("flag")
