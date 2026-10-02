class_name DefLoaderEffects
extends RefCounted
## Effects, conditions, inline selectors and superweapon compilation (data_balance 5.10.3 / 7.5 / 7.11). The effect
## compiler (`compile_effect`) is used by DefLoaderRules for research, powers, zones and trait grants; `build()` is the
## loader hook that compiles the eight superweapons from `global.json -> superweapons` and the bible.

const _SW_KEY: Dictionary = {
	"superweapon.napc.atlas_kinetic_array": "atlas", "superweapon.nec.aurora_microwave_array": "aurora",
	"superweapon.olm.helios_reflector": "helios", "superweapon.def.perun_missile_complex": "perun",
	"superweapon.pd.tempest_swarm_hub": "tempest", "superweapon.han.dragonfall_field_foundry": "dragonfall",
	"superweapon.ae.horizon_mass_driver": "horizon", "superweapon.sap.trident_interception_array": "trident",
}
const _OPS: Dictionary = {
	"stat_mod": DefEnums.EffectOp.STAT_MOD, "resist_mod": DefEnums.EffectOp.RESIST_MOD,
	"param_mod": DefEnums.EffectOp.PARAM_MOD, "grant_ability": DefEnums.EffectOp.GRANT_ABILITY,
	"set_flag": DefEnums.EffectOp.SET_FLAG, "immunity": DefEnums.EffectOp.IMMUNITY, "heal": DefEnums.EffectOp.HEAL,
	"camouflage": DefEnums.EffectOp.CAMOUFLAGE, "reveal": DefEnums.EffectOp.REVEAL, "disable": DefEnums.EffectOp.DISABLE,
	"mark": DefEnums.EffectOp.MARK, "spawn_zone": DefEnums.EffectOp.SPAWN_ZONE,
}
const _COND_CODES: Dictionary = {
	"on_water": DefEnums.Cond.ON_WATER_RT, "in_garrison": DefEnums.Cond.IN_CIVILIAN_GARRISON,
	"near_friendly_unit": DefEnums.Cond.NEAR_FRIENDLY_UNIT, "near_friendly_structure": DefEnums.Cond.NEAR_FRIENDLY_STRUCTURE,
	"target_near_friendly_unit": DefEnums.Cond.TARGET_NEAR_FRIENDLY_UNIT, "in_relay_field": DefEnums.Cond.IN_RELAY_FIELD,
	"stationary": DefEnums.Cond.STATIONARY, "out_of_combat": DefEnums.Cond.OUT_OF_COMBAT,
	"recently_disembarked": DefEnums.Cond.RECENTLY_DISEMBARKED, "deployed": DefEnums.Cond.DEPLOYED,
	"camouflaged": DefEnums.Cond.CAMOUFLAGED, "in_zone": DefEnums.Cond.IN_ZONE,
	"structure_powered": DefEnums.Cond.STRUCTURE_POWERED, "behind_cover": DefEnums.Cond.BEHIND_COVER,
}
const _COMMON_KEYS: PackedStringArray = ["op", "selector", "cond", "stack_group", "duration_s", "membership"]
const _OP_KEYS: Dictionary = {
	"stat_mod": ["stat", "delta_pct"], "resist_mod": ["pct", "groups", "fire_modes", "frontal_arc_deg"],
	"param_mod": ["scope", "ability", "key", "set", "add", "mul_pct", "filter"], "grant_ability": ["ability", "replace"],
	"set_flag": ["flag"], "spawn_zone": ["zone"],
}


## Per-load context of the effect compiler.
class Fx:
	extends RefCounted
	var src: DefSources
	var data: GameData
	var rep: DefLoadReport
	var kinds: DefAbilityKinds
	var inline_n: Dictionary = {}  ## owner id -> inline selectors created so far
	var g: Dictionary = {}


static func make_ctx(src: DefSources, data: GameData, rep: DefLoadReport) -> Fx:
	var fx: Fx = Fx.new()
	fx.src = src
	fx.data = data
	fx.rep = rep
	fx.g = src.balance.get("global.json", {})
	fx.kinds = DefAbilityKinds.from_json(src.balance.get("ability_kinds.json", {}), DefLoadReport.new())
	return fx


# ============================================================================================ selectors
## Selector indices of a `selector` field: string id, array (union) or inline object. Inline objects are compiled to
## `inline.<owner>#<n>` and appended to data.selectors. An empty result means "no selector".
static func compile_selectors(fx: Fx, sel: Variant, owner: String, where: String) -> Array[int]:
	var out: Array[int] = []
	if sel == null:
		return out
	if sel is String:
		var i: int = fx.data.selector_idx(str(sel))
		if i < 0:
			fx.rep.error("V-REF-01", where, "unknown selector '%s'" % str(sel))
		else:
			out.append(i)
	elif sel is Array:
		for e: Variant in sel:
			for i2: int in compile_selectors(fx, e, owner, where):
				if not out.has(i2):
					out.append(i2)
	elif sel is Dictionary:
		var n: int = fx.inline_n.get(owner, 0)
		fx.inline_n[owner] = n + 1
		var id: String = "inline.%s#%d" % [owner, n]
		var s: DefSelector = DefResolver.compile_selector(fx.data, sel, id, fx.rep)
		s.index = fx.data.selectors.size()
		s.kind = DefEnums.Kind.SELECTOR
		fx.data.selectors.append(s)
		out.append(s.index)
	else:
		fx.rep.error("V-SCH-03", where, "selector must be an id, an array or an object")
	return out


# ============================================================================================= conditions
static func _compile_conds(fx: Fx, e: DefEffect, conds: Array, owner: String, where: String) -> void:
	e.cond_codes = PackedInt32Array()
	e.cond_params = []
	for c: Variant in conds:
		var cd: Dictionary = (c as Dictionary).duplicate()
		var code: String = str(cd.get("code", ""))
		cd.erase("code")
		if code == "paid_repair":
			fx.rep.error("V-EFF-01", where, "condition 'paid_repair' is only allowed in bible selectors")
			continue
		if not _COND_CODES.has(code):
			fx.rep.error("V-MOD-04", where, "unknown effect condition '%s'" % code)
			continue
		var sel_idx: int = -1
		if cd.has("selector"):
			var l: Array[int] = compile_selectors(fx, cd["selector"], owner, where)
			sel_idx = l[0] if not l.is_empty() else -1
			cd.erase("selector")
		var params: Dictionary = DefLoaderBalance.convert_blob(cd, where + " cond " + code, fx.data, fx.rep)
		if sel_idx >= 0 or (c as Dictionary).has("selector"):
			params["selector_idx"] = sel_idx
		e.cond_codes.append(int(_COND_CODES[code]))
		e.cond_params.append(params)


# ================================================================================================= effects
## Compiles one raw effect record into one DefEffect per selector of its `selector` union (usually exactly one).
static func compile_effect(fx: Fx, raw: Dictionary, owner: String, where: String) -> Array[DefEffect]:
	var out: Array[DefEffect] = []
	var opn: String = str(raw.get("op", ""))
	if not _OPS.has(opn):
		fx.rep.error("V-EFF-01", where, "unknown effect op '%s'" % opn)
		return out
	var e: DefEffect = DefEffect.new()
	e.op = _OPS[opn]
	var rep: DefLoadReport = fx.rep
	if raw.has("stack_group"):
		e.stack_group = fx.data.stack_groups.find(str(raw["stack_group"]))
	if raw.has("duration_s"):
		e.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw["duration_s"], where + " duration_s", rep))
	if str(raw.get("membership", "continuous")) == "latched":
		e.membership = DefEnums.Membership.LATCHED
	_compile_conds(fx, e, raw.get("cond", []), owner, where)
	match e.op:
		DefEnums.EffectOp.STAT_MOD:
			e.stat = DefEnums.STAT_NAMES.find(str(raw.get("stat", "")))
			if e.stat < 0:
				rep.error("V-EFF-01", where, "unknown stat '%s'" % str(raw.get("stat", "")))
			e.delta_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(raw.get("delta_pct", 0), where + " delta_pct", rep))
		DefEnums.EffectOp.RESIST_MOD:
			e.delta_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(raw.get("pct", 0), where + " pct", rep))
			for g: Variant in raw.get("groups", []):
				var gb: int = DefEnums.resist_group_bit(str(g))
				if gb == 0:
					rep.error("V-EFF-01", where, "unknown resist group '%s'" % str(g))
				e.group_mask |= gb
			for f: Variant in raw.get("fire_modes", []):
				var fi: int = DefEnums.FIRE_NAMES.find(str(f))
				if fi < 0:
					rep.error("V-EFF-01", where, "unknown fire mode '%s'" % str(f))
				else:
					e.fire_mode_mask |= 1 << fi
			if raw.has("frontal_arc_deg"):
				e.frontal_arc_a = DefConvert.deg_to_angle(DefNumParse.milli(raw["frontal_arc_deg"], where + " frontal_arc_deg", rep))
		DefEnums.EffectOp.PARAM_MOD:
			_compile_param_mod(fx, e, raw, where)
		DefEnums.EffectOp.GRANT_ABILITY:
			_compile_grant(fx, e, raw, where)
		DefEnums.EffectOp.SET_FLAG:
			e.flag = str(raw.get("flag", ""))
	# every other key becomes a converted param (heal rate, camouflage max_s, disable what, spawn_zone zone ...)
	var handled: PackedStringArray = _COMMON_KEYS.duplicate()
	handled.append_array(PackedStringArray(_OP_KEYS.get(opn, [])))
	var rest: Dictionary = {}
	for k: Variant in raw.keys():
		if not handled.has(str(k)) and not str(k).begins_with("_"):
			rest[k] = raw[k]
	if opn == "spawn_zone":
		var zi: int = fx.data.zone_idx(str(raw.get("zone", "")))
		if zi < 0:
			rep.error("V-REF-01", where, "unknown zone '%s'" % str(raw.get("zone", "")))
		e.params["zone_idx"] = zi
	if not rest.is_empty():
		var conv: Dictionary = DefLoaderBalance.convert_blob(rest, where, fx.data, rep)
		for k: Variant in conv.keys():
			e.params[k] = conv[k]
	if opn == "grant_ability" and raw.has("replace"):
		e.params["replace"] = DefLoaderBalance.truthy(raw["replace"])
	var sels: Array[int] = compile_selectors(fx, raw.get("selector"), owner, where)
	if sels.is_empty():
		out.append(e)
		return out
	for i: int in sels.size():
		var c: DefEffect = e if i == 0 else e.copy_resolved()
		c.selector = sels[i]
		out.append(c)
	return out


static func _compile_param_mod(fx: Fx, e: DefEffect, raw: Dictionary, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	var scope: String = str(raw.get("scope", "ability"))
	var kind_name: String = str(raw.get("ability", ""))
	var key: String = str(raw.get("key", ""))
	var spec: Dictionary = {}
	match scope:
		"ability", "player":
			e.scope = DefEnums.ParamScope.ABILITY if scope == "ability" else DefEnums.ParamScope.PLAYER
			if not fx.kinds.kinds.has(kind_name):
				rep.error("V-ABL-01", where, "param_mod: unknown ability kind '%s'" % kind_name)
			else:
				e.ability_kind = fx.kinds.kind_id(kind_name)
				spec = ((fx.kinds.kinds[kind_name] as Dictionary).get("params", {}) as Dictionary).get(key, {})
		"def":
			e.scope = DefEnums.ParamScope.DEF
			spec = fx.kinds.def_params.get(key, {})
		_:
			rep.error("V-EFF-01", where, "param_mod: unknown scope '%s'" % scope)
	if spec.is_empty():
		rep.error("V-ABL-01", where, "param_mod: unknown parameter '%s' of '%s'" % [key, kind_name if kind_name != "" else scope])
		return
	var t: String = str(spec.get("type", "n"))
	var rk: String = DefLoaderBalance.runtime_key(t, key)
	e.key = ("%s.%s" % [kind_name, rk]) if e.scope == DefEnums.ParamScope.PLAYER else rk
	var n_ops: int = int(raw.has("set")) + int(raw.has("add")) + int(raw.has("mul_pct"))
	if n_ops != 1:
		rep.error("V-EFF-01", where, "param_mod needs exactly one of set / add / mul_pct")
		return
	if raw.has("mul_pct"):
		e.param_op = DefEnums.ParamOp.MUL_BP
		e.value = DefConvert.pct_to_bp(DefNumParse.milli_pct(raw["mul_pct"], where + " mul_pct", rep))
	else:
		e.param_op = DefEnums.ParamOp.SET if raw.has("set") else DefEnums.ParamOp.ADD
		var v: Variant = raw["set"] if raw.has("set") else raw["add"]
		if v is String:
			e.params["value_str"] = str(v)
		else:
			e.value = DefLoaderBalance.convert_number(t, v, where + " " + key, rep)
	if raw.has("filter"):
		e.filter = DefLoaderBalance.convert_blob(raw["filter"], where + " filter", fx.data, rep)


static func _compile_grant(fx: Fx, e: DefEffect, raw: Dictionary, where: String) -> void:
	var ab: Variant = raw.get("ability")
	var a: DefAbility = null
	if ab is String:
		a = _entry_ability(fx, str(ab), {}, where)
	elif ab is Dictionary:
		var ad: Dictionary = ab
		var params: Dictionary = ad.get("params", {})
		if ad.has("ref"):
			a = _entry_ability(fx, str(ad["ref"]), params, where)
		elif ad.has("kind"):
			a = DefLoaderBalance.make_ability(fx.kinds, str(ad["kind"]), params, -1, where, fx.data, fx.rep, true)
	if a == null:
		fx.rep.error("V-ABL-01", where, "grant_ability: no ability could be built from the 'ability' field")
		return
	e.ability = a
	e.ability_kind = a.kind
	e.stack_group = a.stack_group if e.stack_group < 0 else e.stack_group


static func _entry_ability(fx: Fx, entry: String, params: Dictionary, where: String) -> DefAbility:
	if not fx.kinds.known_entry(entry):
		fx.rep.error("V-ABL-01", where, "unknown ability '%s'" % entry)
		return null
	var tid: String = fx.kinds.resolve_entry(entry)
	if tid == "":
		return null
	return DefLoaderBalance.instantiate_template(fx.kinds, tid, params, where, fx.data, fx.rep)


static func compile_effects(fx: Fx, list: Array, owner: String, where: String) -> Array[DefEffect]:
	var out: Array[DefEffect] = []
	for i: int in list.size():
		out.append_array(compile_effect(fx, list[i], owner, "%s effect %d" % [where, i]))
	return out


# ============================================================================================ impact packets
## A packet from a `global.json` packet / shell dict. Missing keys default to the neutral value.
static func build_packet(data: GameData, d: Dictionary, where: String, rep: DefLoadReport) -> DefImpactPacket:
	var p: DefImpactPacket = DefImpactPacket.new()
	p.damage = DefNumParse.whole(d.get("damage", 0), where + " damage", rep)
	var dt: String = str(d.get("damage_type", ""))
	if d.has("archetype"):
		var ai: int = DefEnums.WEAPON_ARCH_NAMES.find(str(d["archetype"]))
		p.dtype = data.weapon_archs[ai].dtype if ai >= 0 else 0
	else:
		p.dtype = DefEnums.DAMAGE_NAMES.find(dt)
		if p.dtype < 0:
			rep.error("V-CNF-05", where, "unknown damage type '%s'" % dt)
			p.dtype = 0
	var rc: Variant = d.get("radius_cells", d.get("splash_cells", 0))
	p.radius = DefConvert.cells_to_units(DefNumParse.milli(rc, where + " radius", rep))
	var edge: Variant = d.get("edge_pct", 100)
	p.edge_bp = DefConvert.pct_to_bp(DefNumParse.milli_pct(edge, where + " edge_pct", rep))
	if d.has("offset_cells"):
		p.offset_x = DefConvert.cells_to_units(DefNumParse.milli(d["offset_cells"], where + " offset_cells", rep))
	if d.has("delay_ticks"):
		p.delay_t = DefNumParse.whole(d["delay_ticks"], where + " delay_ticks", rep)
	elif d.has("at_s"):
		p.delay_t = DefConvert.seconds_to_ticks(DefNumParse.milli(d["at_s"], where + " at_s", rep))
	p.non_lethal = DefLoaderBalance.truthy(d.get("non_lethal"), (data.damage.nonlethal_mask >> p.dtype) & 1 == 1)
	return p


## Delay tick of shell `k` of `n` over `duration_t` (data_balance 7.10: truncating k * duration_t / n).
static func strike_delay(duration_t: int, n: int, k: int) -> int:
	return (k * duration_t) / maxi(1, n)


# ============================================================================================ superweapons
static func build(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var fx: Fx = make_ctx(src, data, rep)
	var gsw: Dictionary = fx.g.get("superweapons", {})
	for w: DefSuperweapon in data.superweapons:
		var key: String = str(_SW_KEY.get(w.id, ""))
		var where: String = "global.json superweapons.%s (%s)" % [key, w.id]
		if key == "" or not gsw.has(key):
			rep.error("V-CMP-02", "global.json superweapons", "no compile rule / data for '%s'" % w.id)
			continue
		var d: Dictionary = gsw[key]
		_check_timing(fx, w, d, where)
		_compile_superweapon(fx, w, key, d, where)


static func _check_timing(fx: Fx, w: DefSuperweapon, d: Dictionary, where: String) -> void:
	var rc: int = DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("recharge_s", 0), where + " recharge_s", fx.rep))
	var wt: int = DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("warning_s", 0), where + " warning_s", fx.rep))
	if rc != w.recharge_t:
		fx.rep.error("V-CNF-05", where, "recharge_s gives %d ticks, the bible says %d" % [rc, w.recharge_t])
	if wt != w.warning_t:
		fx.rep.error("V-CNF-05", where, "warning_s gives %d ticks, the bible says %d" % [wt, w.warning_t])


static func _summon_idx(fx: Fx, id: String, where: String) -> int:
	var i: int = fx.data.unit_idx(id)
	if i < 0:
		fx.rep.warn("V-REF-01", where, "superweapon summon '%s' is not defined in any unit sheet yet" % id)
	return i


static func _compile_superweapon(fx: Fx, w: DefSuperweapon, key: String, d: Dictionary, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	var data: GameData = fx.data
	w.packets.clear()
	match key:
		"atlas":
			w.action_kind = DefEnums.SwAction.KINETIC_VOLLEY
			for p: Variant in d.get("packets", []):
				w.packets.append(build_packet(data, p, where, rep))
		"aurora":
			w.action_kind = DefEnums.SwAction.EMP_BURST
			w.radius = DefConvert.cells_to_units(DefNumParse.milli(d.get("radius_cells", 0), where, rep))
			w.packets.append(build_packet(data, d.get("damage", {}), where, rep))
			w.params = DefLoaderBalance.convert_blob({
				"weapon_disable_s": d.get("weapon_disable_s", 0), "structure_shutdown_s": d.get("structure_shutdown_s", 0),
				"infantry_unaffected": DefLoaderBalance.truthy(d.get("infantry_unaffected"), true), "bypasses_trident": DefLoaderBalance.truthy(d.get("bypasses_trident"), true),
				"affects_vehicles": true, "affects_aircraft": true, "affects_powered_structures": true,
			}, where, data, rep)
		"helios":
			w.action_kind = DefEnums.SwAction.BEAM_SWEEP
			var width: int = DefConvert.cells_to_units(DefNumParse.milli(d.get("line_width_cells", 0), where, rep))
			var pk: DefImpactPacket = DefImpactPacket.new()
			pk.damage = DefNumParse.whole(d.get("dps", 0), where + " dps", rep)
			pk.dtype = DefEnums.DAMAGE_NAMES.find(str(d.get("damage_type", "thermal")))
			pk.radius = width / 2
			pk.edge_bp = 10000
			pk.params = {"per_second": true}
			w.packets.append(pk)
			w.params = {
				"hit_every_t": 5, "line_len_u": DefConvert.cells_to_units(DefNumParse.milli(d.get("line_length_cells", 0), where, rep)),
				"traverse_t": DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("traverse_s", 0), where, rep)), "width_u": width,
				"bypasses_trident": DefLoaderBalance.truthy(d.get("bypasses_trident"), true),
			}
		"perun":
			w.action_kind = DefEnums.SwAction.BUNKER_BUSTER
			for p2: Variant in d.get("packets", []):
				w.packets.append(build_packet(data, p2, where, rep))
		"tempest":
			w.action_kind = DefEnums.SwAction.DRONE_SWARM
			w.summon = _summon_idx(fx, "summon.pd.tempest_strike_drone", where)
			w.summon_count = DefNumParse.whole(d.get("drone_count", 0), where, rep)
			w.radius = DefConvert.cells_to_units(DefNumParse.milli(d.get("zone_radius_cells", 0), where, rep))
			w.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("attack_window_s", 0), where, rep))
		"dragonfall":
			w.action_kind = DefEnums.SwAction.ENGINE_DROP
			w.summon = _summon_idx(fx, "summon.han.dragonfall_engine", where)
			w.summon_count = DefNumParse.whole(d.get("capsule_count", 0), where, rep)
			w.radius = DefConvert.cells_to_units(DefNumParse.milli(d.get("zone_radius_cells", 0), where, rep))
			w.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("engine_lifetime_s", 0), where, rep))
			var cap: int = _summon_idx(fx, "summon.han.dragonfall_capsule", where)
			w.params = {
				"capsule_health": DefNumParse.whole(d.get("capsule_health", 0), where, rep),
				"capsule_armor": DefEnums.ARMOR_NAMES.find(str(d.get("capsule_armor_class", "heavy_armor"))),
				"capsule_summon_idx": cap,
				"unfold_t": DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("unfold_s", 0), where, rep)),
			}
		"horizon":
			w.action_kind = DefEnums.SwAction.RAIL_STRIKE
			for p3: Variant in d.get("packets", []):
				w.packets.append(build_packet(data, p3, where, rep))
			w.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("duration_s", 0), where, rep))
			w.zone = data.zone_idx("zone.horizon_debris")
			if w.zone < 0:
				rep.error("V-REF-01", where, "zone 'zone.horizon_debris' is not defined")
			var deb: Dictionary = d.get("debris", {})
			w.params = {
				"debris_duration_t": DefConvert.seconds_to_ticks(DefNumParse.milli(deb.get("duration_s", 0), where, rep)),
				"debris_speed_bp": DefConvert.pct_to_bp(DefNumParse.milli_pct(deb.get("land_vehicle_speed_pct", 100), where, rep)),
				"blocks_construction": DefLoaderBalance.truthy(deb.get("blocks_new_construction")),
				"line_len_u": DefConvert.cells_to_units(DefNumParse.milli(d.get("line_length_cells", 0), where, rep)),
			}
		"trident":
			w.action_kind = DefEnums.SwAction.INTERCEPT_ZONE
			w.zone = data.zone_idx("zone.trident_interception")
			if w.zone < 0:
				rep.error("V-REF-01", where, "zone 'zone.trident_interception' is not defined")
			w.radius = DefConvert.cells_to_units(DefNumParse.milli(d.get("zone_radius_cells", 0), where, rep))
			w.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(d.get("duration_s", 0), where, rep))
			var bypass: Array = []
			for b: Variant in d.get("bypass", []):
				bypass.append(str(b))
			w.params = {
				"charges_n": DefNumParse.whole(d.get("charges", 0), where, rep),
				"charges_per_ordinary_projectile_n": DefNumParse.whole(d.get("charges_per_ordinary_projectile", 1), where, rep),
				"charges_per_strategic_packet_n": DefNumParse.whole(d.get("charges_per_strategic_packet", 8), where, rep),
				"strategic_reduction_bp": DefConvert.pct_to_bp(DefNumParse.milli_pct(d.get("strategic_reduction_pct", 0), where, rep)),
				"bypass": bypass,
			}
	w.params = _sorted(w.params)


static func _sorted(d: Dictionary) -> Dictionary:
	var keys: Array = d.keys()
	keys.sort()
	var out: Dictionary = {}
	for k: Variant in keys:
		out[k] = d[k]
	return out
