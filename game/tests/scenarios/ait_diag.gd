extends SceneTree
## AIT diagnostic (slow, NOT part of the suite): one AI-vs-AI match with a per-minute timeline (army, structures, credits, ops) and the
## attack telemetry. tools/gd run res://tests/scenarios/ait_diag.gd -- a=roster.x b=roster.y lv=1 family=0 seed=1000 size=112 cap_min=20 [every=1200]

var _args: Dictionary = {}
var _ev_seen: int = 0
var _hv: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	var rosters: PackedStringArray = PackedStringArray([str(_args.get("a", "roster.ae.vanilla")), str(_args.get("b", "roster.han.vanilla"))])
	if _args.has("rosters"):
		rosters = PackedStringArray(str(_args["rosters"]).split(","))
	var lv: int = _i("lv", 1)
	var m: Dictionary = AiSoakKit.make({"rosters": rosters, "levels": _levels(rosters.size(), lv), "family": _i("family", 0), "seed": _i("seed", 1000),
		"size": _i("size", 112), "fog": _i("fog", 1) == 1, "credits": 7500, "ai_seed": 777, "unit_cap": 150, "tuning": _tuning()})
	var w: SimWorld = m["world"]
	var cap: int = _i("cap_min", 20) * 1200
	var every: int = _i("every", 1200)
	var last: int = 0
	while w.tick < cap and w.match_state == SimWorld.MATCH_RUNNING:
		AiSoakKit.step_once(m)
		if w.tick % 100 == 0:
			AiSoakKit._sample(m)
		_events(m)
		if _i("wave", 0) == 1 and w.tick % _i("wave_every", 60) == 0:
			_wave(m)
		if _i("structlog", 0) == 1 and w.tick % 20 == 0:
			_structlog(m)
		if w.tick - last >= every:
			last = w.tick
			_line(m)
	_line(m)
	for pid: int in m["brains"]:
		print("STATS p%d %s" % [pid, str((m["brains"][pid] as AiBrain).stats)])
	var rec: Dictionary = AiSoakKit.result(m)
	print("RESULT how=%s winner=%d ticks=%d errors=%d" % [rec["how"], rec["winner"], rec["ticks"], rec["error_count"]])
	quit(0)


func _tuning() -> Dictionary:
	var out: Dictionary = {}
	if _args.has("tune"):
		for kv: String in str(_args["tune"]).split(","):
			var p: PackedStringArray = kv.split("=")
			if p.size() == 2:
				out[p[0]] = int(p[1])
	return out


func _i(k: String, d: int) -> int:
	return int(_args[k]) if _args.has(k) else d


func _events(m: Dictionary) -> void:
	var ev: Array = m["events"]
	while _ev_seen < ev.size():
		var e: Array = ev[_ev_seen]
		_ev_seen += 1
		var code: int = int(e[1])
		if code == AiTypes.Tele.ATTACK_LAUNCHED and _i("launch", 0) == 1:
			var lb: AiBrain = m["brains"][int(e[0])]
			var lc: AiContext = (m["factory"] as AiFactory).thinker(int(e[0])).controller.ctx
			var dgp: AiStrengthGroup = lb.attack.defenders(lc, lb.attack.last_target_x, lb.attack.last_target_y, lc.kb.primary)
			print("  LAUNCH p%d units=%d ratio=%d target(%d,%d) defenders: hp=%d value=%d dps=%d count=%d | est_enemy_army=%d assumed=%d my_army=%d" % [int(e[0]), int(e[2]), int(e[3]), lb.attack.last_target_x >> 10, lb.attack.last_target_y >> 10, dgp.hp, dgp.value, dgp.total_dps_x100(), dgp.count, lc.kb.est_enemy_army_value(lc.kb.primary), AiAttackPlanner.assumed_army(lc), lb.eco().army_value])
		if code in [AiTypes.Tele.ATTACK_LAUNCHED, AiTypes.Tele.ATTACK_CONTACT, AiTypes.Tele.ATTACK_ABORTED, AiTypes.Tele.SIEGE_STARTED, AiTypes.Tele.SW_LAUNCHED, AiTypes.Tele.DEFEND_STARTED, AiTypes.Tele.RETREAT_ORDERED] or (_i("stalls", 0) == 1 and code in [AiTypes.Tele.STALL, AiTypes.Tele.CMD_REJECTED, AiTypes.Tele.AI_ERROR]):
			print("  EV t=%d.%02d p%d %s a=%d b=%d" % [int(e[4]) / 1200, (int(e[4]) % 1200) / 20, int(e[0]), AiTypes.Tele.keys()[AiTypes.Tele.values().find(code)], int(e[2]), int(e[3])])


func _line(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	for pid: int in m["brains"]:
		var rp: Dictionary = SimMatchKit.report(w, pid)
		var b: AiBrain = m["brains"][pid]
		var ops: String = ""
		for o: AiOp in b.ops:
			if o.is_over():
				continue
			ops += " %s/%d(%d,%d u%d)" % ["ATK" if o.type == AiTypes.OpType.ATTACK else str(o.type), o.state, o.tx >> 10, o.ty >> 10, o.committed_value]
		var sv: int = 0
		var sn: int = 0
		for s: SimEntity in w.structures_of(pid):
			if (s.flags & SimFlags.F_GONE) == 0:
				sv += w.data.structures[s.def_idx].cost
				sn += 1
		var kinds: Dictionary = {}
		for s2: SimEntity in w.structures_of(pid):
			if (s2.flags & SimFlags.F_GONE) == 0:
				var sid: String = (w.data.structures[s2.def_idx].id as String).get_slice(".", 2)
				kinds[sid] = int(kinds.get(sid, 0)) + 1
		var hv: int = int(rp["harvested"])
		print("t=%2d p%d %s cred=%5d coll=%d units=%3d army=%5d structs=%2d(%5d) lost=%d killed=%d waves=%d/%d why=%d force=%d/%d%s" % [w.tick / 1200, pid, "E" if int(rp["eliminated"]) == 1 else " ", rp["credits"], rp["collectors"], rp["combat_units"], b.eco().army_value, sn, sv, rp["lost"], rp["killed"], b.waves_launched, b.waves_won, b.attack.why, b.attack.last_force_units, b.attack.last_min_units, ops])
		if _i("kinds", 0) == 1:
			print("      harv=%d(+%d) spentU=%d spentC=%d %s" % [hv, hv - int(_hv.get(pid, 0)), w.players[pid].econ.stat_spent_units, w.players[pid].econ.stat_spent_construction, str(kinds)])
		_hv[pid] = hv
		if _i("exp", 0) == 1:
			var ex: AiExpansion = b.eco().expansion
			var cx0: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
			print("      EXP en=%s st=%d started=%d done=%d failed=%d max=%d score=%d mainleft=%d%% opener=%s tier=%d need_c=%s pick=%d style=%d" % [str(ex.enabled), ex.state, ex.started, ex.done, ex.failed, cx0.diff.expansions_max, ex.score(cx0), ex._main_left_pct(cx0), str(b.eco().opener_done()), b.eco().planner.tier(cx0), str(b.eco().need_collector), ex._pick_site(cx0), cx0.pers.expand])
		if _i("queues", 0) == 1:
			var cq: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
			var eq: AiEconomy = b.eco()
			var qs: String = ""
			for i2: int in eq.prod_eid.size():
				var qq: PackedInt32Array = PackedInt32Array()
				cq.view.queue_of(eq.prod_eid[i2], qq)
				var names: String = ""
				for u: int in qq:
					names += (w.data.units[u].id as String).get_slice(".", 2) + ","
				qs += " [%d k%d held=%s q=%s]" % [eq.prod_eid[i2], eq.prod_kind[i2], str(eq._held.has(eq.prod_eid[i2])), names]
			print("      QUEUES%s bank_hold=%s struct_wait=%s collapse=%s" % [qs, str(eq._bank_hold), str(eq.struct_wait), str(eq.collapse)])
		if _i("edge", 0) == 1:
			var mw: int = w.map.w
			var edge: int = 0
			var tot: int = 0
			var pos: String = ""
			for u: SimEntity in w.units_of(pid):
				if (u.flags & SimFlags.F_GONE) != 0 or u.def_idx < 0 or (w.data.units[u.def_idx].tags & DefEnums.UT_COMBAT) == 0 or (w.data.units[u.def_idx].tags & DefEnums.UT_AIRCRAFT) != 0:
					continue
				tot += 1
				var cx: int = u.x >> 10
				var cy: int = u.y >> 10
				if cx < 10 or cy < 10 or cx >= mw - 10 or cy >= mw - 10:
					edge += 1
				pos += " (%d,%d)" % [cx, cy]
			print("      EDGE %d/%d within 10 cells of the border:%s" % [edge, tot, pos])
		if _i("planner", 0) == 1:
			var cp: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
			var pl: AiBuildPlanner = b.eco().planner
			var cs: PackedInt32Array = PackedInt32Array()
			cp.view.construction_state(cs)
			print("      PLANNER cstate=%s job_def=%d job_res=%s ready_def=%d nosite=%d place_tick=%d fails=%d blocked=%s" % [str(cs), pl._job_def, str(pl._job_res), pl._ready_def, pl._no_site_since, pl._place_tick, pl.place_fails, str(b.eco()._blocked_defs)])
		if _i("placetest", 0) == 1 and w.tick >= _i("placetest_at", 12400) and w.tick < _i("placetest_at", 12400) + 100:
			var cp2: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
			var rdef: int = cp2.res.structure_of_kind(AiTypes.StructKind.REFINERY)
			var ks2: AiResourceSites = cp2.kb.sites
			var hqs: String = ""
			for s3: SimEntity in w.structures_of(pid):
				if (s3.flags & SimFlags.F_GONE) == 0 and (w.data.structures[s3.def_idx].id as String).ends_with("headquarters"):
					hqs += " (%d,%d uc=%d)" % [s3.x >> 10, s3.y >> 10, 1 if (s3.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0 else 0]
			for i3: int in ks2.count:
				var fx: int = ks2.x[i3] >> 10
				var fy: int = ks2.y[i3] >> 10
				if absi(fx - (ks2.home_x >> 10)) + absi(fy - (ks2.home_y >> 10)) < 20:
					continue
				var okc: int = 0
				var nearest: String = ""
				var best: int = 999
				for oy3: int in range(-12, 13):
					for ox3: int in range(-12, 13):
						if cp2.view.can_place(rdef, fx + ox3, fy + oy3, 0):
							okc += 1
							if absi(ox3) + absi(oy3) < best:
								best = absi(ox3) + absi(oy3)
								nearest = "(%d,%d)" % [fx + ox3, fy + oy3]
				print("      PLACETEST p%d HQs%s field(%d,%d) left=%d valid_cells=%d nearest=%s" % [pid, hqs, fx, fy, ks2.left[i3], okc, nearest])
		if _i("comp", 0) == 1:
			var hist: Dictionary = {}
			for u4: SimEntity in w.units_of(pid):
				if (u4.flags & SimFlags.F_GONE) == 0:
					var nm4: String = (w.data.units[u4.def_idx].id as String).get_slice(".", 2)
					hist[nm4] = int(hist.get(nm4, 0)) + 1
			print("      COMP %s" % str(hist))
		if _i("stage", 0) == 1:
			var pr: AiProduction = b.eco().production
			var cs2: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
			print("      STAGE home=(%d,%d) stage=(%d,%d) map=%d primary=%d dist_border_home=%d dist_border_stage=%d" % [cs2.kb.sites.home_x >> 10, cs2.kb.sites.home_y >> 10, pr.stage_x >> 10, pr.stage_y >> 10, cs2.view.map_w(), cs2.kb.primary, mini(mini(cs2.kb.sites.home_x >> 10, cs2.kb.sites.home_y >> 10), mini(cs2.view.map_w() - (cs2.kb.sites.home_x >> 10), cs2.view.map_h() - (cs2.kb.sites.home_y >> 10))), mini(mini(pr.stage_x >> 10, pr.stage_y >> 10), mini(cs2.view.map_w() - (pr.stage_x >> 10), cs2.view.map_h() - (pr.stage_y >> 10)))])
		if _i("safe", 0) == 1:
			var cx5: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
			print("      SAFE=%s army=%d units=%d assumed=%d peak=%d need60=%d col=%d/%d(base %d) want=%s" % [str(b.eco().econ_safe(cx5)), b.eco().army_value, b.eco().army_units, AiAttackPlanner.assumed_army(cx5), b.strategy.enemy_peak, maxi(AiAttackPlanner.assumed_army(cx5), b.strategy.enemy_peak) * 60 / 100, b.eco().collectors_alive, b.eco().collector_target, b.eco().collector_base, str(b.eco().want_collectors)])
		if _i("swlog", 0) == 1:
			var sw: AiSuperweapon = b.powers.sw
			print("      SW has=%s launches=%d build_why=%s built_tick=%d min_start=%d held_since=%s why=%d own=%d" % [str(sw.has_weapon()), sw.launches, sw.build_why, sw.built_tick, sw.min_start_tick((m["factory"] as AiFactory).thinker(pid).controller.ctx), "st=%d ready_since=%d best_seen=%d last_score=%d active=%d" % [(m["factory"] as AiFactory).thinker(pid).controller.ctx.view.sw_status(), sw.ready_since, sw.best_seen, sw.last_score, sw.active_tick], sw.why, b.eco().struct_own[sw.launcher_def] if sw.launcher_def >= 0 else -1])
		if _i("sites", 0) == 1:
			var ks: AiResourceSites = (m["factory"] as AiFactory).thinker(pid).controller.ctx.kb.sites
			var st: String = ""
			for i: int in ks.count:
				st += " [(%d,%d) left=%d k%d cl=%d h=%d path=%d]" % [ks.x[i] >> 10, ks.y[i] >> 10, ks.left[i], ks.kind[i], ks.claimed_refinery_eid[i], ks.collectors_assigned[i], ks.path_len_c[i]]
			print("      SITES home=(%d,%d)%s" % [ks.home_x >> 10, ks.home_y >> 10, st])
		if _i("wants", 0) == 1:
			var eco: AiEconomy = b.eco()
			var ws: String = ""
			for wn: AiWant in eco.wants:
				var nm: String = ""
				if wn.kind == AiTypes.WantKind.STRUCT and wn.def >= 0:
					nm = (w.data.structures[wn.def].id as String).get_slice(".", 2)
				elif wn.def >= 0 and wn.def < w.data.units.size():
					nm = (w.data.units[wn.def].id as String).get_slice(".", 2)
				ws += " [%s k%d n%d p%d st%d f%d]" % [nm, wn.kind, wn.count, wn.prio, wn.state, wn.fail_count]
			print("      cancels=%d place_fails=%d placed=%d stalls=%d" % [eco.cancels, eco.planner.place_fails, eco.planner.placed, eco.planner.stalls])
			print("      refs=%d/%d ctarget=%d need=%s margin=%d avail=%d burn=%d/%d wants:%s" % [eco.refineries_active, eco.refineries_total, eco.collector_target, str(eco.need_collector), eco.margin, eco.avail, eco.burn_total, eco.burn_cap, ws])


var _sl: Dictionary = {}


func _structlog(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	var now: Dictionary = {}
	for pid: int in m["brains"]:
		for s: SimEntity in w.structures_of(pid):
			if (s.flags & SimFlags.F_GONE) != 0:
				continue
			now[s.id] = true
			if not _sl.has(s.id):
				_sl[s.id] = true
				print("  ST+ t=%d.%02d p%d %s id=%d at (%d,%d) uc=%d" % [w.tick / 1200, (w.tick % 1200) / 20, pid, (w.data.structures[s.def_idx].id as String).get_slice(".", 2), s.id, s.x >> 10, s.y >> 10, 1 if (s.flags & SimFlags.F_UNDER_CONSTRUCTION) != 0 else 0])
	for id: int in _sl.keys():
		if not now.has(id):
			var e: SimEntity = w.get_entity(id)
			print("  ST- t=%d.%02d id=%d %s" % [w.tick / 1200, (w.tick % 1200) / 20, id, (w.data.structures[e.def_idx].id as String).get_slice(".", 2) if e != null else "?"])
			_sl.erase(id)


func _levels(n: int, lv: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(_i("lv%d" % i, lv))
	return out


func _wave(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	for pid: int in m["brains"]:
		var b: AiBrain = m["brains"][pid]
		var cx0: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
		for o: AiOp in b.ops:
			if o.type != AiTypes.OpType.ATTACK or o.is_over():
				continue
			var a: AiOpAttack = o as AiOpAttack
			var rows: PackedInt32Array = PackedInt32Array()
			var n: int = AiForce.armed_enemy_rows(cx0, a.cx, a.cy, 16 * Fp.CELL, 100, rows)
			var eg: AiStrengthGroup = AiForce.enemy_group(cx0, a.cx, a.cy, 16 * Fp.CELL, 100)
			var defs: int = 0
			var g: AiGhostTable = cx0.kb.ghosts
			for j: int in g.count:
				if g.owner[j] >= 0 and AiForce.is_defense_kind(g.kind[j]) and AiForce.dist(g.x[j], g.y[j], a.cx, a.cy) <= 22 * Fp.CELL:
					defs += 1
			if _i("truth", 0) == 1:
				var tru: String = ""
				for q: int in w.players.size():
					if q == pid:
						continue
					for e: SimEntity in w.units_of(q):
						if (e.flags & SimFlags.F_GONE) == 0 and AiForce.dist(e.x, e.y, a.cx, a.cy) <= 22 * Fp.CELL:
							tru += " U:%s(%d,%d hp%d)" % [(w.data.units[e.def_idx].id as String).get_slice(".", 2), e.x >> 10, e.y >> 10, e.hp * 100 / maxi(e.hp_max, 1)]
					for e2: SimEntity in w.structures_of(q):
						if (e2.flags & SimFlags.F_GONE) == 0 and AiForce.dist(e2.x, e2.y, a.cx, a.cy) <= 22 * Fp.CELL:
							tru += " S:%s(%d,%d)" % [(w.data.structures[e2.def_idx].id as String).get_slice(".", 2), e2.x >> 10, e2.y >> 10]
				print("    TRUTH" + tru)
			if _i("units", 0) == 1:
				var no_order: int = 0
				var with_target: int = 0
				var firing: int = 0
				var ids: String = ""
				for eid: int in a.ids:
					var u: SimEntity = w.get_entity(eid)
					if u == null:
						continue
					if u.orders.is_empty():
						no_order += 1
					if u.combat != null and u.combat.target_id > 0:
						with_target += 1
						if w.tick - u.combat.last_fire_tick < 40:
							firing += 1
				print("    UNITS no_order=%d with_target=%d firing=%d" % [no_order, with_target, firing])
			print("  WAVE t=%d.%02d p%d st=%d alive=%d val=%d/%d at(%d,%d) tgt(%d,%d) enemies=%d egroup_val=%d defs22=%d r_now=%d gv=%d" % [w.tick / 1200, (w.tick % 1200) / 20, pid, a.state, a.alive, a.value_now, a.initial_value, a.cx >> 10, a.cy >> 10, a.tx >> 10, a.ty >> 10, n, eg.value, defs, a.r_now_q8, a._near_ghost_value(cx0)])
