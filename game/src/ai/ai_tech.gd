class_name AiTech
extends RefCounted
## Slot 6 (ai.md 5.5.3 - 5.5.5): tier goals (Laboratory timing), counter-tech switching (enemy-composition triggers with a 300 s
## hysteresis that AiComposition turns into role multipliers and that create COUNTER structure wants: AA battery when air is
## seen, AT turret against heavy armor, Watchtower against infantry masses / camouflage), tech pull for roles that are wanted
## but not producible yet, EMERGENCY rebuild of lost tech-critical structures, and the research queue (gates from the doctrine,
## default gate = a real army; only bought when the economy is healthy and the funds pass AiEconomy.try_fund).

const REBUILD_KINDS: PackedInt32Array = [
	AiTypes.StructKind.REFINERY, AiTypes.StructKind.BARRACKS, AiTypes.StructKind.FACTORY, AiTypes.StructKind.RADAR,
]
const REFRESH_TICKS: int = 100  ## deadline of a refreshed COUNTER / TECH want
const DEFAULT_RESEARCH_PRIO: int = 60
const DEFAULT_ARMY_UNITS: int = 10

var until: PackedInt32Array = PackedInt32Array()  ## by AiTypes.Cat: trigger active until this tick
var strong_until: PackedInt32Array = PackedInt32Array()
var switches: int = 0  ## number of trigger activations (telemetry TECH_SWITCH)
var requested: Dictionary = {}  ## research id -> prio (opener research steps)
var researched_n: int = 0
var ever: PackedInt32Array = PackedInt32Array()  ## by StructKind: owned at least once
var _mult_norm: Array[PackedInt32Array] = []
var _mult_strong: Array[PackedInt32Array] = []
var _share_ge: PackedInt32Array = PackedInt32Array()
var _strong_ge: PackedInt32Array = PackedInt32Array()
var _or_seen: PackedInt32Array = PackedInt32Array()
var _structs: Array = []  ## by cat: Array of {kind, max}
var _hub: WeakRef = null
var _hyst: int = 6000


func setup(_ctx: AiContext) -> void:
	var eco: AiEconomy = _hub.get_ref() if _hub != null else null
	var n: int = AiTypes.Cat.COUNT
	until.resize(n)
	until.fill(AiTypes.NEVER)
	strong_until.resize(n)
	strong_until.fill(AiTypes.NEVER)
	ever.resize(AiTypes.StructKind.OTHER + 1)
	_share_ge.resize(n)
	_share_ge.fill(101)  # 101 = the category has no share trigger
	_strong_ge.resize(n)
	_strong_ge.fill(101)
	_or_seen.resize(n)
	_or_seen.fill(0)
	_mult_norm.clear()
	_mult_strong.clear()
	_structs.clear()
	for _c: int in n:
		_mult_norm.append(_role_table({}))
		_mult_strong.append(_role_table({}))
		_structs.append([])
	_hyst = eco.doctrine.hysteresis_ticks if eco != null else 6000
	var cnt: Dictionary = eco.doctrine.counters if eco != null else {}
	for cname: String in cnt:
		var cat: int = AiDoctrine.cat_of(cname)
		if cat < 0:
			continue
		var cfg: Dictionary = cnt[cname]
		var trig: Dictionary = cfg.get("trigger", {})
		_share_ge[cat] = int(trig.get("share_ge", 101))
		_or_seen[cat] = int(trig.get("or_seen", 0))
		_mult_norm[cat] = _role_table(cfg.get("mult", {}))
		if cfg.has("strong"):
			var st: Dictionary = cfg["strong"]
			_strong_ge[cat] = int(st.get("share_ge", 101))
			_mult_strong[cat] = _role_table(st.get("mult", {}))
		else:
			_strong_ge[cat] = 101
			_mult_strong[cat] = _mult_norm[cat]
		for s: Variant in cfg.get("structs", []):
			(_structs[cat] as Array).append(s)


func bind(hub: AiEconomy) -> void:
	_hub = weakref(hub)


static func _role_table(mult: Dictionary) -> PackedInt32Array:
	var t: PackedInt32Array = PackedInt32Array()
	t.resize(AiTypes.ROLE_COUNT)
	t.fill(256)
	for rn: String in mult:
		var b: int = AiTypes.role_bit(rn)
		if b >= 0:
			t[b] = int(mult[rn])
	return t


func trigger_active(cat: int) -> bool:
	return _hub != null and until[cat] > (_hub.get_ref() as AiEconomy).now_tick()


func trigger_strong(cat: int) -> bool:
	return _hub != null and strong_until[cat] > (_hub.get_ref() as AiEconomy).now_tick()


## Product (Q8) of the multipliers of every active trigger for a role.
func counter_mult_q8(role: int) -> int:
	var eco: AiEconomy = _hub.get_ref()
	var now: int = eco.now_tick()
	var m: int = 256
	for c: int in AiTypes.Cat.COUNT:
		if until[c] <= now:
			continue
		var tbl: PackedInt32Array = _mult_strong[c] if strong_until[c] > now else _mult_norm[c]
		m = m * tbl[role] >> 8
	return m


func step(ctx: AiContext, budget: AiBudget) -> void:
	var eco: AiEconomy = _hub.get_ref()
	if eco == null or not budget.spend(6):
		return
	eco.refresh(ctx, budget)
	_triggers(ctx, budget)
	_counter_wants(ctx, eco)
	_lab_goal(ctx, eco)
	_tech_pull(ctx, eco)
	_rebuild(ctx, eco)
	_research(ctx, budget, eco)


# ---------------------------------------------------------------------------------------------- triggers
func _triggers(ctx: AiContext, budget: AiBudget) -> void:
	var kb: AiKnowledge = ctx.kb
	var now: int = ctx.tick
	for c: int in AiTypes.Cat.COUNT:
		if _share_ge[c] > 100 and _or_seen[c] == 0 and c != AiTypes.Cat.SUB and c != AiTypes.Cat.CAMO:
			continue
		if not budget.spend(2):
			return
		var active: bool = false
		var strong: bool = false
		match c:
			AiTypes.Cat.SUB:
				for p: int in kb.enemy_pids:
					if kb.profiles[p].sub_seen:
						active = true
			AiTypes.Cat.CAMO:
				var alert: PackedInt32Array = PackedInt32Array()
				if kb.camo_alert(alert) and now - alert[2] < _hyst:
					active = true
				for p2: int in kb.enemy_pids:
					if kb.profiles[p2].camo_seen:
						active = true
			AiTypes.Cat.STATIC_DEF:
				var st: int = _static_share_pct(kb)
				active = st >= _share_ge[c]
			_:
				var best: int = 0
				for p3: int in kb.enemy_pids:
					var pr: AiEnemyProfile = kb.profiles[p3]
					if pr.seen_value[c] > 0:
						best = maxi(best, pr.share_q8[c] * 100 / 256)
				active = best >= _share_ge[c]
				strong = best >= _strong_ge[c]
				if not active and _or_seen[c] > 0 and _seen_units(ctx, c) >= _or_seen[c]:
					active = true
		if active:
			if until[c] <= now:
				switches += 1
				ctx.telemetry.emit(AiTypes.Tele.TECH_SWITCH, c, 1, now)
			until[c] = now + _hyst
		if strong:
			strong_until[c] = now + _hyst


## Currently tracked enemy units of a category (rows are dropped 100 ticks after the last sighting).
func _seen_units(ctx: AiContext, cat: int) -> int:
	var t: AiEntityTable = ctx.kb.enemy_units
	var n: int = 0
	for r: int in t.count:
		var pr: AiUnitProfile = ctx.unit_profile_of(t.owner[r], t.def[r])
		if pr != null and pr.category == cat:
			n += 1
	return n


func _static_share_pct(kb: AiKnowledge) -> int:
	var g: AiGhostTable = kb.ghosts
	var total: int = 0
	var stat: int = 0
	for r: int in g.count:
		total += g.value[r]
		var k: int = g.kind[r]
		if k == AiTypes.StructKind.WATCHTOWER or k == AiTypes.StructKind.AT_TURRET or k == AiTypes.StructKind.AA_BATTERY \
				or k == AiTypes.StructKind.ADV_DEFENSE:
			stat += g.value[r]
	return stat * 100 / maxi(total, 1) if total >= 3000 else 0


# ------------------------------------------------------------------------------------------- structure wants
func _counter_wants(ctx: AiContext, eco: AiEconomy) -> void:
	if eco.refineries_active <= 0 or not eco.opener_done():
		return
	for c: int in AiTypes.Cat.COUNT:
		if until[c] <= ctx.tick:
			continue
		for s: Variant in _structs[c]:
			var sd: Dictionary = s
			var kind: int = AiDoctrine.struct_kind_of(str(sd.get("struct", "")))
			var def: int = ctx.res.structure_of_kind(kind)
			if def < 0:
				continue
			var target: int = mini(int(sd.get("max", 1)), 1 + eco.refineries_active)
			if eco.struct_own[def] + eco.struct_q[def] >= target:
				continue
			var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, def, -1, target, AiEconomy.P_COUNTER, AiTypes.WantOrigin.COUNTER)
			w.site_kind = AiPlacer.Site.FIELD if kind != AiTypes.StructKind.AT_TURRET else AiPlacer.Site.FRONT
			eco.site_hint_refinery(w, eco.struct_own[def])
			w.deadline = ctx.tick + REFRESH_TICKS
			eco.add_want(w)


func _lab_goal(ctx: AiContext, eco: AiEconomy) -> void:
	var lab: int = ctx.res.structure_of_kind(AiTypes.StructKind.LAB)
	if lab < 0 or eco.struct_own[lab] + eco.struct_q[lab] > 0 or not eco.healthy():
		return
	var from_ticks: int = 420 * SimConfig.TPS * ctx.diff.tech_delay_x100 / 100 * (150 - ctx.pers.tech) / 100
	if ctx.tick < from_ticks:
		return
	var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, lab, -1, 1, AiEconomy.P_LAB, AiTypes.WantOrigin.TECH)
	w.site_kind = AiPlacer.Site.BACK
	w.deadline = ctx.tick + REFRESH_TICKS
	eco.add_want(w)


## A role with >= 15 % of the weight that cannot be built yet pulls the first missing structure of its def.
func _tech_pull(ctx: AiContext, eco: AiEconomy) -> void:
	if not eco.healthy():
		return
	for r: int in eco.comp.pull:
		var d: int = ctx.res.first(r)
		if d < 0:
			continue
		var miss: PackedInt32Array = ctx.tech.missing_for_unit(d, ctx.view.struct_counts(), eco.struct_q)
		if miss.is_empty():
			continue
		var s: int = miss[0]
		var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, s, -1, eco.struct_own[s] + 1, AiEconomy.P_TECH, AiTypes.WantOrigin.TECH)
		w.site_kind = AiPlacer.Site.BACK
		w.deadline = ctx.tick + REFRESH_TICKS
		eco.add_want(w)


func _rebuild(ctx: AiContext, eco: AiEconomy) -> void:
	for k: int in REBUILD_KINDS:
		var s: int = ctx.res.structure_of_kind(k)
		if s < 0:
			continue
		if eco.struct_own[s] > 0:
			ever[k] = 1
		elif ever[k] == 1 and eco.struct_q[s] == 0:
			var w: AiWant = AiWant.make(AiTypes.WantKind.STRUCT, s, -1, 1, AiEconomy.P_EMERGENCY, AiTypes.WantOrigin.EMERGENCY)
			w.site_kind = AiPlacer.Site.BACK if k != AiTypes.StructKind.REFINERY else AiPlacer.Site.FIELD
			eco.site_hint_refinery(w, 0)
			w.deadline = ctx.tick + REFRESH_TICKS
			eco.add_want(w)


# --------------------------------------------------------------------------------------------------- research
func _research(ctx: AiContext, budget: AiBudget, eco: AiEconomy) -> void:
	var v: AiWorldView = ctx.view
	if v.research_active() >= 0 or not eco.healthy():
		return
	var out: PackedInt32Array = PackedInt32Array()
	v.researchable(out)
	var best: int = -1
	var best_prio: int = 1 << 20
	var best_cost: int = 0
	for idx: int in out:
		if not budget.spend(3):
			return
		var rd: DefResearch = v.research_def(idx)
		if rd == null or v.research_done(idx):
			continue
		var prio: int = _gate(ctx, rd.id, eco)
		if prio < 0 or v.can_research(idx) != AiTypes.Rule.OK:
			continue
		if prio < best_prio or (prio == best_prio and rd.cost < best_cost):
			best = idx
			best_prio = prio
			best_cost = rd.cost
	if best < 0:
		return
	var rd2: DefResearch = v.research_def(best)
	var fund_prio: int = mini(best_prio, AiEconomy.P_TECH)  # an upgrade is funded like a tech structure (one slow line)
	if eco.avail_for(fund_prio) < rd2.cost / 4 or not eco.try_fund(fund_prio, rd2.cost, rd2.time_t):
		return
	if ctx.cmd.research(best):
		researched_n += 1


## Prio of a research (lower first) or -1 when its gate is closed.
func _gate(ctx: AiContext, rid: String, eco: AiEconomy) -> int:
	if requested.has(rid):
		return int(requested[rid])
	for e: Variant in eco.doctrine.research:
		var ed: Dictionary = e
		if str(ed.get("id", "")) == rid:
			if ed.has("when") and not eco.planner.eval_cond(ctx, ed["when"]):
				return -1
			return int(ed.get("prio", DEFAULT_RESEARCH_PRIO))
	return DEFAULT_RESEARCH_PRIO if eco.army_units >= DEFAULT_ARMY_UNITS else -1


func state_hash() -> int:
	var v: PackedInt32Array = PackedInt32Array([switches, researched_n])
	v.append_array(until)
	return AiRng.hash_ints(v)
