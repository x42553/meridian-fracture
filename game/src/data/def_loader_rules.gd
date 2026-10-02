class_name DefLoaderRules
extends RefCounted
## Rules loader (data_balance 5.10 / 7.9 / 7.10 / 7.12 / 7.13 / 7.14 and docs/RULES_DATA_NOTES.md): research effects,
## support powers (with their zones), zone templates, neutral structures and faction traits (ability grants, player
## params). Hook `def_loader_rules.build(src, data, rep)`; effects are compiled by DefLoaderEffects.

const _TARGET_MODES: PackedStringArray = ["none", "point", "line", "own_structure"]
const _TARGET_VISION: PackedStringArray = ["any", "explored", "current"]
const _ZONE_KINDS: PackedStringArray = ["buff", "smoke", "intercept", "debris", "decoy", "puck", "shelter", "cover", "repair", "reveal"]
const _NEUTRAL_KINDS: PackedStringArray = [
	"civilian_garrison", "power_substation", "observation_post", "salvage_depot", "deposit", "field_hospital", "harbor_terminal",
]
const _NEUTRAL_HANDLED: PackedStringArray = [
	"kind", "health", "armor_class", "footprint", "sight_cells", "capturable", "capture_s", "garrison_squads_n", "reward",
	"pres", "ability", "berth",
]
const _ZONE_HANDLED: PackedStringArray = [
	"kind", "shape", "radius_cells", "length_cells", "width_cells", "duration_s", "affects", "follow_source", "hp",
	"targets", "visible_to_enemy", "max_per_owner_n", "effects", "params", "pres",
]


static func build(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var fx: DefLoaderEffects.Fx = DefLoaderEffects.make_ctx(src, data, rep)
	_research(fx)
	_zone_templates(fx)
	_powers(fx)
	_neutrals(fx)
	_factions(fx)


# ================================================================================================ research
static func _research(fx: DefLoaderEffects.Fx) -> void:
	var doc: Dictionary = fx.src.balance.get("research_effects.json", {}).get("research", {})
	for id: Variant in doc.keys():
		if fx.data.research_idx(str(id)) < 0:
			fx.rep.error("V-REF-01", fx.src.where("research_effects.json", str(id)), "'%s' is not a bible research upgrade" % str(id))
	for r: DefResearch in fx.data.research:
		var where: String = fx.src.where("research_effects.json", r.id)
		if not doc.has(r.id):
			fx.rep.error("V-CMP-03", "research_effects.json", "research '%s' has no effect entry" % r.id)
			continue
		var e: Dictionary = doc[r.id]
		r.effects = DefLoaderEffects.compile_effects(fx, e.get("effects", []), r.id, where)
		if r.effects.is_empty():
			fx.rep.error("V-CMP-03", where, "research '%s' compiles to no effect" % r.id)


# ================================================================================================== zones
static func _zone_templates(fx: DefLoaderEffects.Fx) -> void:
	var data: GameData = fx.data
	data.zones.clear()
	for i: int in data.ids.count(DefEnums.Kind.ZONE):
		var z: DefZone = DefZone.new()
		z.id = data.ids.id_of(DefEnums.Kind.ZONE, i)
		z.index = i
		z.pres_recipe = z.id
		data.zones.append(z)
	var doc: Dictionary = fx.src.balance.get("zone_templates.json", {}).get("zones", {})
	for z: DefZone in data.zones:
		if doc.has(z.id):
			fill_zone(fx, z, doc[z.id], fx.src.where("zone_templates.json", z.id))


## Fills a zone def from a template / inline dict (data_balance 7.12).
static func fill_zone(fx: DefLoaderEffects.Fx, z: DefZone, raw: Dictionary, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	z.zone_kind = _ZONE_KINDS.find(str(raw.get("kind", "")))
	if z.zone_kind < 0:
		rep.error("V-SCH-07", where, "unknown zone kind '%s'" % str(raw.get("kind", "")))
		z.zone_kind = 0
	z.shape = DefEnums.ZoneShape.LINE if str(raw.get("shape", "circle")) == "line" else DefEnums.ZoneShape.CIRCLE
	z.radius = _cells(raw, "radius_cells", where, rep)
	z.length = _cells(raw, "length_cells", where, rep)
	z.width = _cells(raw, "width_cells", where, rep)
	z.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw.get("duration_s", 0), where + " duration_s", rep))
	match str(raw.get("affects", "all")):
		"friendly":
			z.affects = DefEnums.AFFECTS_FRIENDLY
		"enemy":
			z.affects = DefEnums.AFFECTS_ENEMY
		_:
			z.affects = DefEnums.AFFECTS_ALL
	z.follow_source = DefLoaderBalance.truthy(raw.get("follow_source"))
	z.hp = DefNumParse.whole(raw.get("hp", 0), where + " hp", rep)
	for l: Variant in raw.get("targets", []):
		z.target_mask |= DefEnums.layer_bit(str(l))
	z.visible_to_enemy = DefLoaderBalance.truthy(raw.get("visible_to_enemy"), true)
	z.max_per_owner = DefNumParse.whole(raw.get("max_per_owner_n", 0), where + " max_per_owner_n", rep)
	z.effects = DefLoaderEffects.compile_effects(fx, raw.get("effects", []), z.id, where)
	if raw.has("params"):
		z.params = DefLoaderBalance.convert_blob(raw["params"], where + " params", fx.data, rep)
	z.pres_recipe = str((raw.get("pres", {}) as Dictionary).get("recipe", z.id))


static func _cells(d: Dictionary, key: String, where: String, rep: DefLoadReport) -> int:
	if not d.has(key):
		return 0
	return DefConvert.cells_to_units(DefNumParse.milli(d[key], where + " " + key, rep))


# ================================================================================================== powers
static func _powers(fx: DefLoaderEffects.Fx) -> void:
	var doc: Dictionary = fx.src.balance.get("power_actions.json", {}).get("powers", {})
	for id: Variant in doc.keys():
		if fx.data.power_idx(str(id)) < 0:
			fx.rep.error("V-REF-01", fx.src.where("power_actions.json", str(id)), "'%s' is not a bible support power" % str(id))
	for p: DefPower in fx.data.powers:
		var where: String = fx.src.where("power_actions.json", p.id)
		if not doc.has(p.id):
			fx.rep.error("V-CMP-03", "power_actions.json", "power '%s' has no action entry" % p.id)
			continue
		_fill_power(fx, p, doc[p.id], where)


static func _fill_power(fx: DefLoaderEffects.Fx, p: DefPower, raw: Dictionary, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	var t: Dictionary = raw.get("target", {})
	p.target_mode = _TARGET_MODES.find(str(t.get("mode", "none")))
	p.target_vision = _TARGET_VISION.find(str(t.get("vision", "current")))
	if p.target_mode < 0 or p.target_vision < 0:
		rep.error("V-SCH-07", where, "unknown target mode / vision")
		p.target_mode = maxi(p.target_mode, 0)
		p.target_vision = maxi(p.target_vision, 0)
	p.radius = _cells(t, "radius_cells", where, rep)
	p.length = _cells(t, "length_cells", where, rep)
	p.width = _cells(t, "width_cells", where, rep)
	if raw.has("warning_s"):
		p.warning_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw["warning_s"], where + " warning_s", rep))
	var pp: Dictionary = {}
	if t.has("structure_ids"):
		var sl: PackedInt32Array = PackedInt32Array()
		for s: Variant in t["structure_ids"]:
			var si: int = fx.data.structure_idx(str(s))
			if si < 0:
				rep.error("V-REF-01", where, "unknown structure '%s'" % str(s))
			sl.append(si)
		sl.sort()
		pp["target_structure_idx"] = sl
	if t.has("powered_required"):
		pp["target_powered_required"] = DefLoaderBalance.truthy(t["powered_required"])
	p.params = pp
	p.actions.clear()
	var n_inline: int = 0
	var acts: Array = raw.get("actions", [])
	if acts.is_empty():
		rep.error("V-CMP-03", where, "power '%s' has no action" % p.id)
	for i: int in acts.size():
		var a: Dictionary = acts[i]
		var aw: String = "%s action %d" % [where, i]
		var inline_id: String = ""
		if a.has("inline"):
			inline_id = DefLoaderBalance.inline_zone_id(p.id, n_inline)
			n_inline += 1
		p.actions.append(_power_action(fx, p, a, inline_id, aw))


static func _rest(raw: Dictionary, handled: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in raw.keys():
		if not handled.has(str(k)) and not str(k).begins_with("_"):
			out[k] = raw[k]
	return out


static func _power_action(fx: DefLoaderEffects.Fx, p: DefPower, raw: Dictionary, inline_id: String, where: String) -> DefPowerAction:
	var rep: DefLoadReport = fx.rep
	var data: GameData = fx.data
	var a: DefPowerAction = DefPowerAction.new()
	var op: String = str(raw.get("op", ""))
	var handled: PackedStringArray = PackedStringArray(["op"])
	var pairs: Dictionary = {}
	match op:
		"zone":
			a.op = DefEnums.PowerOp.ZONE
			handled.append_array(PackedStringArray(["zone", "inline", "radius_cells", "duration_s", "count_n"]))
			if inline_id != "":
				var zi: int = data.zone_idx(inline_id)
				if zi >= 0:
					fill_zone(fx, data.zones[zi], raw["inline"], where + " inline zone")
				a.zone = zi
			else:
				a.zone = data.zone_idx(str(raw.get("zone", "")))
				if a.zone < 0:
					rep.error("V-REF-01", where, "unknown zone '%s'" % str(raw.get("zone", "")))
			a.radius = _cells(raw, "radius_cells", where, rep)
			a.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw.get("duration_s", 0), where, rep))
			a.count = DefNumParse.whole(raw.get("count_n", 1), where, rep)
		"summon":
			a.op = DefEnums.PowerOp.SUMMON
			handled.append_array(PackedStringArray(["summon_id", "count_n", "lifetime_s"]))
			var sid: String = str(raw.get("summon_id", ""))
			a.summon = data.unit_idx(sid)
			if a.summon < 0:
				rep.warn("V-REF-01", where, "summon '%s' is not defined in any unit sheet yet" % sid)
			a.count = DefNumParse.whole(raw.get("count_n", 1), where, rep)
			a.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw.get("lifetime_s", 0), where, rep))
		"strike":
			a.op = DefEnums.PowerOp.STRIKE
			handled.append_array(PackedStringArray(["damage_ref", "pattern"]))
			_strike(fx, a, str(raw.get("damage_ref", "")), where)
			pairs["pattern"] = str(raw.get("pattern", "random_in_radius"))
		"mark":
			a.op = DefEnums.PowerOp.MARK
			handled.append_array(PackedStringArray(["find_radius_cells", "find_selector", "lookback_s", "mark_s", "damage_bonus_pct", "bonus_from_selector", "reveal", "then_strike"]))
			a.radius = _cells(raw, "find_radius_cells", where, rep)
			a.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw.get("mark_s", 0), where, rep))
			pairs["lookback_t"] = DefConvert.seconds_to_ticks(DefNumParse.milli(raw.get("lookback_s", 0), where, rep))
			if raw.has("damage_bonus_pct"):
				pairs["damage_bonus_bp"] = DefConvert.pct_to_bp(DefNumParse.milli_pct(raw["damage_bonus_pct"], where, rep))
			for k: String in ["find_selector", "bonus_from_selector"]:
				if raw.has(k):
					var l: Array[int] = DefLoaderEffects.compile_selectors(fx, raw[k], p.id, where)
					pairs[k + "_idx"] = l[0] if not l.is_empty() else -1
			pairs["reveal"] = DefLoaderBalance.truthy(raw.get("reveal"))
			if raw.has("then_strike"):
				var ts: Dictionary = raw["then_strike"]
				_strike(fx, a, str(ts.get("damage_ref", "")), where)
				pairs["strike_pattern"] = str(ts.get("pattern", "fixed"))
				pairs["strike_at"] = str(ts.get("at", "marked_positions"))
		"global_effect":
			a.op = DefEnums.PowerOp.GLOBAL_EFFECT
			handled.append_array(PackedStringArray(["duration_s", "effects", "params"]))
			a.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw.get("duration_s", 0), where, rep))
			a.effects = DefLoaderEffects.compile_effects(fx, raw.get("effects", []), p.id, where)
			if raw.has("params"):
				var pc: Dictionary = DefLoaderBalance.convert_blob(raw["params"], where + " params", data, rep)
				for k2: Variant in pc.keys():
					pairs[k2] = pc[k2]
		_:
			rep.error("V-EFF-01", where, "unknown power action op '%s'" % op)
	var rest: Dictionary = _rest(raw, handled)
	if not rest.is_empty():
		var conv: Dictionary = DefLoaderBalance.convert_blob(rest, where, data, rep)
		for k3: Variant in conv.keys():
			pairs[k3] = conv[k3]
	for k5: Variant in a.params.keys():
		pairs[k5] = a.params[k5]
	var keys: Array = pairs.keys()
	keys.sort()
	a.params = {}
	for k4: Variant in keys:
		a.params[k4] = pairs[k4]
	return a


## Strike shells of `global.json -> support_power_damage[ref]` (shell count, waves, duration, prototype packet).
static func _strike(fx: DefLoaderEffects.Fx, a: DefPowerAction, ref: String, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	var dmg: Dictionary = (fx.g.get("support_power_damage", {}) as Dictionary).get(ref, {})
	if dmg.is_empty():
		rep.error("V-REF-01", where, "unknown support_power_damage entry '%s'" % ref)
		return
	var shell: Dictionary = dmg.get("shell", {})
	a.count = DefNumParse.whole(dmg.get("shells", dmg.get("shells_per_wave", dmg.get("shells_per_mark", 1))), where, rep)
	if dmg.has("over_s"):
		a.duration_t = DefConvert.seconds_to_ticks(DefNumParse.milli(dmg["over_s"], where, rep))
	if a.radius == 0 and dmg.has("zone_radius_cells"):
		a.radius = DefConvert.cells_to_units(DefNumParse.milli(dmg["zone_radius_cells"], where, rep))
	if dmg.has("waves"):
		a.params["waves_n"] = DefNumParse.whole(dmg["waves"], where, rep)
	if dmg.has("shell_gap_s"):
		a.params["shell_gap_t"] = DefConvert.seconds_to_ticks(DefNumParse.milli(dmg["shell_gap_s"], where, rep))
	if dmg.has("max_marks"):
		a.params["max_marks_n"] = DefNumParse.whole(dmg["max_marks"], where, rep)
	a.impacts.clear()
	a.impacts.append(DefLoaderEffects.build_packet(fx.data, shell, where + " shell", rep))


# ================================================================================================ neutrals
static func _neutrals(fx: DefLoaderEffects.Fx) -> void:
	var data: GameData = fx.data
	data.neutrals.clear()
	var doc: Dictionary = fx.src.balance.get("neutral_structures.json", {}).get("neutrals", {})
	for i: int in data.ids.count(DefEnums.Kind.NEUTRAL):
		var n: DefNeutral = DefNeutral.new()
		n.id = data.ids.id_of(DefEnums.Kind.NEUTRAL, i)
		n.index = i
		n.pres_recipe = n.id
		data.neutrals.append(n)
		_fill_neutral(fx, n, doc.get(n.id, {}), fx.src.where("neutral_structures.json", n.id))


static func _fill_neutral(fx: DefLoaderEffects.Fx, n: DefNeutral, raw: Dictionary, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	n.neutral_kind = _NEUTRAL_KINDS.find(str(raw.get("kind", "")))
	if n.neutral_kind < 0:
		rep.error("V-SCH-07", where, "unknown neutral kind '%s'" % str(raw.get("kind", "")))
		n.neutral_kind = 0
	n.health = DefNumParse.whole(raw.get("health", 0), where + " health", rep)
	n.armor_class = DefEnums.ARMOR_NAMES.find(str(raw.get("armor_class", "building_light")))
	var fp: Dictionary = raw.get("footprint", {})
	n.fp_w = DefNumParse.whole(fp.get("w", 1), where + " footprint", rep)
	n.fp_h = DefNumParse.whole(fp.get("h", 1), where + " footprint", rep)
	n.radius = maxi(n.fp_w, n.fp_h) * Fp.CELL / 2
	n.sight = _cells(raw, "sight_cells", where, rep)
	n.capturable = DefLoaderBalance.truthy(raw.get("capturable"))
	if raw.has("capture_s"):
		n.capture_t = DefConvert.seconds_to_ticks(DefNumParse.milli(raw["capture_s"], where + " capture_s", rep))
	n.garrison_squads = DefNumParse.whole(raw.get("garrison_squads_n", 0), where + " garrison_squads_n", rep)
	var rw: Dictionary = raw.get("reward", {})
	var reward: Dictionary = {}
	if rw.has("credits"):
		reward["credits_cr"] = DefNumParse.whole(rw["credits"], where, rep)
	if rw.has("power_n"):
		reward["power_n"] = DefNumParse.whole(rw["power_n"], where, rep)
	if rw.has("reveal_radius_cells"):
		reward["reveal_radius_u"] = DefConvert.cells_to_units(DefNumParse.milli(rw["reveal_radius_cells"], where, rep))
	if rw.has("income_crps"):
		reward["income_mcpt"] = DefConvert.crps_to_mcpt(DefNumParse.milli(rw["income_crps"], where, rep))
	if rw.has("credits_per_cell"):
		reward["credits_per_cell_cr"] = DefNumParse.whole(rw["credits_per_cell"], where, rep)
	if rw.has("cells_n"):
		reward["cells_n"] = DefNumParse.whole(rw["cells_n"], where, rep)
	n.reward = reward
	var pairs: Dictionary = {}
	if raw.has("berth"):
		var berth: Array = []
		for b: Variant in raw["berth"]:
			berth.append(DefNumParse.whole(b, where + " berth", rep))
		pairs["berth"] = berth
	if raw.has("ability"):
		var ad: Dictionary = raw["ability"]
		var a: DefAbility = DefLoaderBalance.instantiate_template(fx.kinds, str(ad.get("ref", "")), ad.get("params", {}), where, fx.data, rep)
		pairs["ability"] = {"kind": a.kind, "params": a.params}
	var rest: Dictionary = _rest(raw, _NEUTRAL_HANDLED)
	if not rest.is_empty():
		var conv: Dictionary = DefLoaderBalance.convert_blob(rest, where, fx.data, rep)
		for k: Variant in conv.keys():
			pairs[k] = conv[k]
	var keys: Array = pairs.keys()
	keys.sort()
	n.params = {}
	for k2: Variant in keys:
		n.params[k2] = pairs[k2]
	n.pres_recipe = str((raw.get("pres", {}) as Dictionary).get("recipe", n.id))


# ================================================================================================ factions
static func _factions(fx: DefLoaderEffects.Fx) -> void:
	var doc: Dictionary = fx.src.balance.get("faction_traits.json", {}).get("factions", {})
	var bible_f: Dictionary = fx.src.bible.get("factions", {})
	for f: DefFaction in fx.data.factions:
		var where: String = fx.src.where("faction_traits.json", f.id)
		if not doc.has(f.id):
			fx.rep.error("V-CMP-03", "faction_traits.json", "faction '%s' has no trait entry" % f.id)
			continue
		var fd: Dictionary = doc[f.id]
		var pal: String = str((fd.get("pres", {}) as Dictionary).get("palette", ""))
		if pal != "":
			f.pres_palette = pal
		f.grants.clear()
		f.player_params = {}
		var texts: Array = (bible_f.get(f.id, {}) as Dictionary).get("traits_text", [])
		var covered: Dictionary = {}
		var traits: Dictionary = fd.get("traits", {})
		var tkeys: Array = traits.keys()
		tkeys.sort()
		for tk: Variant in tkeys:
			var t: Dictionary = traits[tk]
			var tw: String = fx.src.where("faction_traits.json", str(tk))
			for c: Variant in t.get("covers", []):
				var ci: int = DefNumParse.whole(c, tw + " covers", fx.rep)
				covered[ci] = int(covered.get(ci, 0)) + 1
			_trait(fx, f, str(tk), t, tw)
		for i: int in texts.size():
			if int(covered.get(i, 0)) != 1:
				fx.rep.error("V-CMP-03", where, "bible trait text %d of %s is covered %d times (must be exactly once)" % [i, f.id, int(covered.get(i, 0))])
		if fd.has("player_params"):
			var pc: Dictionary = DefLoaderBalance.convert_blob(fd["player_params"], where + " player_params", fx.data, fx.rep)
			for k: Variant in pc.keys():
				f.player_params[k] = pc[k]
		var keys: Array = f.player_params.keys()
		keys.sort()
		var sorted_pp: Dictionary = {}
		for k2: Variant in keys:
			sorted_pp[k2] = f.player_params[k2]
		f.player_params = sorted_pp


static func _trait(fx: DefLoaderEffects.Fx, f: DefFaction, tid: String, t: Dictionary, where: String) -> void:
	var rep: DefLoadReport = fx.rep
	var data: GameData = fx.data
	match str(t.get("encoding", "")):
		"grant":
			var raw: Dictionary = {"op": "grant_ability", "ability": t.get("ability"), "selector": t.get("selector")}
			if t.has("replace"):
				raw["replace"] = t["replace"]
			f.grants.append_array(DefLoaderEffects.compile_effect(fx, raw, tid, where))
		"player":
			if not (t.get("ability") is Dictionary):
				rep.error("V-SCH-03", where, "a player trait needs an 'ability' object {ref, params}")
				return
			var ad: Dictionary = t["ability"]
			var a: DefAbility = DefLoaderBalance.instantiate_template(fx.kinds, str(ad.get("ref", "")), ad.get("params", {}), where, data, rep)
			var kname: String = DefEnums.ABILITY_NAMES[a.kind] if a.kind > 0 and a.kind < DefEnums.ABILITY_NAMES.size() else ""
			for k: Variant in a.params.keys():
				f.player_params["%s.%s" % [kname, str(k)]] = a.params[k]
		"encoded_in":
			var enc: Dictionary = t.get("encoded_in", {})
			for m: Variant in enc.get("modifier_ids", []):
				if data.ids.index_of(DefEnums.Kind.MODIFIER, str(m)) < 0:
					rep.error("V-REF-01", where, "unknown modifier '%s'" % str(m))
			for u: Variant in enc.get("unit_ids", []):
				if data.unit_idx(str(u)) < 0:
					rep.error("V-REF-01", where, "unknown unit '%s'" % str(u))
			if enc.has("structure_id") and data.structure_idx(str(enc["structure_id"])) < 0:
				rep.error("V-REF-01", where, "unknown structure '%s'" % str(enc["structure_id"]))
		"text_only":
			pass
		_:
			rep.error("V-SCH-03", where, "unknown trait encoding '%s'" % str(t.get("encoding", "")))
