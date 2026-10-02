extends RefCounted
## E7 / E8 on REAL matches (SimMatchKit: generated map, real HQ, fog on): a base is built through the real placement and
## lifecycle (find_site -> place -> BUILDUP -> ACTIVE), then every power of the roster is fired with CMD_USE_POWER under real
## vision, and the superweapon is charged, launched and executed. One roster per power set covers all 48 powers.

const M := preload("res://tests/support/sim_match_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")


func _place(w: SimWorld, pid: int, id: String, near_x: int, near_y: int) -> SimEntity:
	var s_idx: int = w.data.structure_idx(id)
	var cell: PackedInt32Array = PackedInt32Array()
	if s_idx < 0 or not SimPlacement.find_site(w, pid, s_idx, near_x, near_y, 9, cell):
		return null
	return w.economy.life.place(w, pid, s_idx, cell[0], cell[1], 0, w.data.structures[s_idx].cost)


## Powered base near the HQ of `pid` (+ optionally the launcher and an Airfield), settled through real BUILDUP.
func _base(w: SimWorld, pid: int, launcher: bool, airfield: bool) -> SimEntity:
	var hq: SimEntity = null
	for e: SimEntity in w.structures_of(pid):
		if w.data.structures[e.def_idx].id == "structure.shared.headquarters":
			hq = e
	var hx: int = hq.x >> 10
	var hy: int = hq.y >> 10
	for _i: int in 5:
		_place(w, pid, "structure.shared.generator", hx, hy)
	_place(w, pid, "structure.shared.radar", hx, hy)
	_place(w, pid, "structure.shared.laboratory", hx, hy)
	if launcher and w.players[pid].econ.slots[SimEconConst.SLOT_SW].def_idx >= 0:
		var sw: DefSuperweapon = w.data.superweapons[w.players[pid].econ.slots[SimEconConst.SLOT_SW].def_idx]
		_place(w, pid, w.data.structures[sw.launcher].id, hx, hy)
	if airfield:
		_place(w, pid, "structure.shared.airfield", hx, hy)
	w.players[pid].credits = 40000
	for _j: int in 45:
		w.step()
	# a few units of the roster around the HQ so that the buffs have someone to buff
	var n: int = 0
	for u: DefUnit in w.data.units:
		if n >= 10:
			break
		if u.cost > 0 and w.players[pid].roster.has_unit(u.index) and not u.id.begins_with("summon.") and u.home_layer == SimEntity.Layer.GROUND:
			w.spawn_unit(u.index, pid, hq.x + (n % 5 - 2) * 1400, hq.y + 5000 + (n / 5) * 1400, 0, 0, u.cost, 0, SimEvent.SPAWN_PRODUCED)
			n += 1
	w.step()
	return hq


## Smallest greedy list of rosters whose power lists cover all 48 powers.
func _cover(d: GameData) -> Array[String]:
	var need: Dictionary = {}
	for p: DefPower in d.powers:
		need[p.index] = true
	var out: Array[String] = []
	while not need.is_empty():
		var best: DefRoster = null
		var best_n: int = 0
		for r: DefRoster in d.rosters:
			var n: int = 0
			for pi: int in r.power_list:
				if need.has(pi):
					n += 1
			if n > best_n:
				best = r
				best_n = n
		for pi2: int in best.power_list:
			need.erase(pi2)
		out.append(best.id)
	return out


func test_all_48_powers_on_real_matches(t: TestCtx) -> void:
	var d: GameData = M.data()
	var seen: Dictionary = {}
	var rosters: Array[String] = _cover(d)
	t.gt(rosters.size(), 0, "rosters chosen")
	for rid: String in rosters:
		var foe: String = "roster.nec.vanilla" if not rid.contains(".nec.") else "roster.napc.vanilla"
		var m: Dictionary = M.make_match({"rosters": PackedStringArray([rid, foe]), "bots": false, "rules": {"fog": true}, "seed": 5})
		var w: SimWorld = m["world"]
		var hq: SimEntity = _base(w, 0, false, true)
		var art_id: String = "unit.nec.archer_spg" if foe.contains(".nec.") else "unit.napc.paladin_howitzer"
		var art: SimEntity = w.spawn_unit(d.unit_idx(art_id), 1, hq.x + 1000, hq.y + 3500, 0, 0, 0, 0, SimEvent.SPAWN_PRODUCED)
		w.step()
		for slot: int in 3:
			art.combat.last_fire_tick = w.tick  # an enemy artillery piece that just fired (the fire-log powers mark it)
			var pi: int = w.players[0].econ.slots[slot].def_idx
			var p: DefPower = d.powers[pi]
			var target: int = 0
			if p.params.has("target_structure_idx"):
				for e: SimEntity in w.structures_of(0):
					if (p.params["target_structure_idx"] as PackedInt32Array).has(e.def_idx):
						target = e.id
			var credits: int = w.players[0].credits
			var r: int = w.strategic.can_activate(w, 0, slot, hq.x, hq.y + 3000, 0, target)
			t.eq(r, SimEconConst.RSN_OK, "%s (%s) validates under real fog" % [p.id, rid])
			w.clear_events()
			w.submit_raw(0, SimCmd.use_power(pi, hq.x, hq.y + 3000, 0, target))
			w.step()
			for _k: int in 3:
				w.step()
			t.eq(w.players[0].econ.slots[slot].uses, 1, "%s: used" % p.id)
			t.eq(w.players[0].credits, credits - p.cost, "%s: charged" % p.id)
			t.eq(S.kind_effect(w, p, pi), "", "%s: effect present in sim state" % p.id)
			seen[pi] = true
		t.eq(w.zones.debug_validate(w), PackedStringArray(), "%s: zones validate" % rid)
	t.eq(seen.size(), 48, "all 48 powers activated on real matches")


func test_superweapon_charges_launches_and_executes_in_a_real_match(t: TestCtx) -> void:
	var d: GameData = M.data()
	var fired: int = 0
	for f: String in ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]:
		var m: Dictionary = M.make_match({"rosters": PackedStringArray(["roster.%s.vanilla" % f, "roster.%s.vanilla" % ("nec" if f != "nec" else "napc")]), "bots": false, "rules": {"fog": true}, "seed": 5})
		var w: SimWorld = m["world"]
		var hq: SimEntity = _base(w, 0, true, false)
		var s: SimPowerSlot = w.players[0].econ.slots[SimEconConst.SLOT_SW]
		t.eq(s.sw_state, SimEconConst.SW_CHARGING, "%s: charging" % f)
		t.check(s.charge < 60, "%s: started empty" % f)
		S.force_ready(w, 0)
		var sw: DefSuperweapon = d.superweapons[s.def_idx]
		w.clear_events()
		w.submit_raw(0, SimCmd.launch_superweapon(hq.x, hq.y + 9000, 0))
		w.step()
		t.eq(w.strategic.warnings.size(), 1, "%s: warning opened (target explored near the HQ)" % f)
		var wr: SimWarning = w.strategic.warnings[0]
		while w.tick < wr.exec_tick + 2:
			w.step()
		t.eq(wr.phase != SimEconConst.AT_WARNING, true, "%s: executed" % f)
		t.eq(S.n_events(w, SimEconConst.EVT_SW_EXEC_START), 1, "%s: EVT_SW_EXEC_START" % f)
		t.eq(s.recharge_ticks, sw.recharge_t, "%s: recharge from data" % f)
		fired += 1
	t.eq(fired, 8, "all eight superweapons in real matches")
