extends SceneTree
## BAL2 equal-spend army fights in the REAL sim (FRAMEWORK 5.17 experiment 2), independent of the AI economy: two rosters each buy an
## army of `budget` credits from their own producible units by role, both armies are placed on a flat map `dist` cells apart with a
## seeded jitter, attack-move at each other, and the fight runs until one side has no combat unit left or `ticks` passed. The metric is
## share(A) - share(B) where share = remaining cost / spent cost (each unit counts paid_cost x hp / hp_max).
##
##   tools/gd run --allow-errors res://tests/scenarios/bal2_fight.gd -- mode=pair a=roster.ae.vanilla b=roster.han.vanilla comp=mid seeds=3
##   ... -- mode=grid comps=mid,heavy seeds=2 shard=0/8 out=grid.jsonl        all 32 x 32 unordered pairs (a != b), one JSON line per fight
##   ... -- mode=list list=roster.a,roster.b comp=mid                          prints the composition only
## Args: budget=12000 dist=24 ticks=4000 maxtier=2 (comp mid) size=128
## Compositions: mid (tier <= 2 tank line, infantry, AT, artillery), heavy (tier <= 3: heaviest tank line + AT + artillery + infantry),
## inf (infantry mass + AT), arty (artillery with a tank + infantry screen), air (fighters + attack aircraft + mobile AA, fights fly over the flat map).

const CELL: int = 1024

var _args: Dictionary = {}
var _data: GameData = null


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	if _args.has("bal"):
		GameData._cache = GameData.load_from_paths(GameData.BIBLE_PATH, str(_args["bal"]))  # bal=<dir>: a variant copy of game/data/balance (experiments)
	_data = SimMatchKit.data()
	match str(_args.get("mode", "pair")):
		"list":
			_list()
		"grid":
			_grid()
		"units":
			_units()
		_:
			_pair()
	quit(0)


func _i(k: String, d: int) -> int:
	return int(_args[k]) if _args.has(k) else d


# ------------------------------------------------------------------------------------------------ composition
func _is_ground(u: DefUnit) -> bool:
	return (u.tags & (DefEnums.UT_AIRCRAFT | DefEnums.UT_SHIP)) == 0 and (u.tags & DefEnums.UT_COMBAT) != 0 and u.speed > 0


func _pick(r: DefRoster, pred: Callable, max_tier: int, prefer_high: bool) -> int:
	var best: int = -1
	for ui: int in r.producible_units:
		var u: DefUnit = r.units[ui]
		if u.unit_class == DefEnums.UnitClass.SERVICE or u.tier > max_tier or u.cost <= 0:
			continue
		if not (pred.call(u) as bool):
			continue
		if best < 0:
			best = ui
			continue
		var b: DefUnit = r.units[best]
		if prefer_high:
			if u.tier > b.tier or (u.tier == b.tier and u.cost > b.cost):
				best = ui
		elif u.cost < b.cost:
			best = ui
	return best


## Slots [[unit index, weight_pct], ...] for a roster and a composition.
func _slots(r: DefRoster, comp: String) -> Array:
	var t2: int = _i("maxtier", 2)
	var inf_line: Callable = func(u: DefUnit) -> bool: return _is_ground(u) and (u.tags & DefEnums.UT_INFANTRY) != 0 and (u.tags & (DefEnums.UT_ANTI_TANK | DefEnums.UT_SPECIALIST | DefEnums.UT_ANTI_AIR)) == 0
	var inf_at: Callable = func(u: DefUnit) -> bool: return _is_ground(u) and (u.tags & DefEnums.UT_INFANTRY) != 0 and (u.tags & DefEnums.UT_ANTI_TANK) != 0
	var tank: Callable = func(u: DefUnit) -> bool: return _is_ground(u) and (u.tags & DefEnums.UT_TANK) != 0
	var arty: Callable = func(u: DefUnit) -> bool: return _is_ground(u) and (u.tags & (DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE)) != 0 and (u.tags & DefEnums.UT_TANK) == 0
	var veh_any: Callable = func(u: DefUnit) -> bool: return _is_ground(u) and (u.tags & DefEnums.UT_LAND_VEHICLE) != 0 and (u.tags & (DefEnums.UT_TANK | DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE | DefEnums.UT_ANTI_AIR | DefEnums.UT_SCOUT | DefEnums.UT_TRANSPORT)) == 0
	var aa: Callable = func(u: DefUnit) -> bool: return _is_ground(u) and (u.tags & DefEnums.UT_ANTI_AIR) != 0 and (u.tags & DefEnums.UT_INFANTRY) == 0
	var fighter: Callable = func(u: DefUnit) -> bool: return (u.tags & DefEnums.UT_AIRCRAFT) != 0 and (u.tags & DefEnums.UT_ANTI_AIR) != 0 and (u.tags & DefEnums.UT_COMBAT) != 0
	var attack_air: Callable = func(u: DefUnit) -> bool: return (u.tags & DefEnums.UT_AIRCRAFT) != 0 and (u.tags & DefEnums.UT_GROUND_ATTACK) != 0 and (u.tags & DefEnums.UT_COMBAT) != 0
	var out: Array = []
	match comp:
		"heavy":
			out = [[_pick(r, inf_line, 1, false), 10], [_pick(r, inf_at, 1, true), 15], [_pick(r, tank, 3, true), 50], [_pick(r, arty, 2, true), 15]]
		"inf":
			out = [[_pick(r, inf_line, 1, false), 65], [_pick(r, inf_at, 1, true), 35]]
		"arty":
			out = [[_pick(r, arty, 3, true), 40], [_pick(r, tank, 2, true), 30], [_pick(r, inf_line, 1, false), 15], [_pick(r, inf_at, 1, true), 15]]
		"air":
			out = [[_pick(r, fighter, 3, true), 40], [_pick(r, attack_air, 3, true), 40], [_pick(r, aa, 2, false), 20]]
		_:
			out = [[_pick(r, inf_line, 1, false), 15], [_pick(r, inf_at, 1, true), 15], [_pick(r, tank, t2, true), 40], [_pick(r, arty, t2, true), 15], [_pick(r, veh_any, t2, true), 10]]
	# rosters without a T1/T2 tank (7 of them) use the best tank they have below the cap, else their cheapest tank/heavy
	if comp == "mid" and int((out[2] as Array)[0]) < 0:
		(out[2] as Array)[0] = _pick(r, tank, 3, false)
	# drop empty slots; renormalise
	var slots: Array = []
	var tot: int = 0
	for s: Variant in out:
		var sa: Array = s
		if int(sa[0]) >= 0:
			slots.append(sa)
			tot += int(sa[1])
	for s2: Variant in slots:
		(s2 as Array)[1] = int((s2 as Array)[1]) * 100 / maxi(tot, 1)
	return slots


## unit index -> count for a roster / budget; the leftover goes to the biggest slot.
func _buy(r: DefRoster, comp: String, budget: int, view: DefPlayerView) -> Dictionary:
	var slots: Array = _slots(r, comp)
	var buy: Dictionary = {}
	var spent: int = 0
	var biggest: int = -1
	var bw: int = -1
	for s: Variant in slots:
		var sa: Array = s
		var ui: int = sa[0]
		var cost: int = view.unit_cost[ui]
		var n: int = maxi((budget * int(sa[1]) / 100) / cost, 1)
		buy[ui] = n
		spent += n * cost
		if int(sa[1]) > bw:
			bw = int(sa[1])
			biggest = ui
	while biggest >= 0 and spent + view.unit_cost[biggest] <= budget:
		buy[biggest] = int(buy[biggest]) + 1
		spent += view.unit_cost[biggest]
	return {"buy": buy, "spent": spent}


func _list() -> void:
	for rid: String in str(_args.get("list", "roster.napc.vanilla")).split(","):
		var r: DefRoster = _data.rosters[_data.roster_idx(rid)]
		var w: SimWorld = _make_world(rid, rid, 1)
		var view: DefPlayerView = w.players[0].view
		var b: Dictionary = _buy(r, str(_args.get("comp", "mid")), _i("budget", 12000), view)
		var parts: PackedStringArray = PackedStringArray()
		for ui: int in b["buy"]:
			parts.append("%dx %s(%d)" % [b["buy"][ui], _data.units[ui].id.get_slice(".", 2), view.unit_cost[ui]])
		print("%-26s spent %5d  %s" % [rid.replace("roster.", ""), b["spent"], ", ".join(parts)])


# ------------------------------------------------------------------------------------------------ fights
func _make_world(ra: String, rb: String, sim_seed: int) -> SimWorld:
	var n: int = _i("size", 128)
	var cfg: SimMatchConfig = SimMatchKit.make_config({"rosters": PackedStringArray([ra, rb]), "credits": 0, "sim_seed": 5000 + sim_seed,
		"rules": {"fog": _i("fog", 1) == 1, "victory": 0, "unit_cap": 500}})
	var starts: PackedInt32Array = PackedInt32Array([10, 10, n - 11, n - 11])
	var map: MapData = MapData.make_flat(n, n, starts, 424242)
	return SimMatchSetup.create_world(_data, cfg, map, {})


class Rng:
	var s: int = 1

	func _init(seed_: int) -> void:
		s = (seed_ * 2654435761 + 12345) & 0x7fffffff

	func next(m: int) -> int:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return (s >> 8) % m


func _alive_value(w: SimWorld, _pid: int, ids: Array) -> float:
	var v: float = 0.0
	for id: int in ids:
		var e: SimEntity = w.get_entity(id)
		if e == null or (e.flags & SimFlags.F_GONE) != 0 or e.hp <= 0:
			continue
		v += float(e.paid_cost) * float(e.hp) / float(maxi(e.hp_max, 1))
	return v


func _alive_units(w: SimWorld, ids: Array) -> int:
	var n: int = 0
	for id: int in ids:
		var e: SimEntity = w.get_entity(id)
		if e != null and (e.flags & SimFlags.F_GONE) == 0 and e.hp > 0:
			n += 1
	return n


## One fight; returns {share_a, share_b, diff, ticks, spent_a, spent_b, n_a, n_b}.
func _fight(ra: String, rb: String, comp: String, sd: int, custom: Dictionary = {}) -> Dictionary:
	var w: SimWorld = _make_world(ra, rb, sd)
	var budget: int = _i("budget", 12000)
	var dist: int = _i("dist", 24)
	var n: int = _i("size", 128)
	var rng: Rng = Rng.new(sd * 7919 + 13)
	var ids: Array = [[], []]  ## per side: Array of entity ids
	var spent: Array = [0, 0]
	var counts: Array = [0, 0]
	var cx: int = n / 2
	var cy: int = n / 2
	for pid: int in 2:
		var r: DefRoster = w.players[pid].roster
		var view: DefPlayerView = w.players[pid].view
		var b: Dictionary
		if custom.has(pid):
			var sp: int = 0
			for cui: int in custom[pid]:
				sp += int(custom[pid][cui]) * view.unit_cost[cui]
			b = {"buy": custom[pid], "spent": sp}
		else:
			b = _buy(r, comp, budget, view)
		spent[pid] = b["spent"]
		# formation: sorted by role rank (front: tanks / infantry, back: artillery); rows of up to 14
		var order: Array = []
		for ui: int in b["buy"]:
			var u: DefUnit = _data.units[ui]
			var rank: int = 0
			if (u.tags & (DefEnums.UT_ARTILLERY | DefEnums.UT_SIEGE)) != 0 and (u.tags & DefEnums.UT_TANK) == 0:
				rank = 2
			elif (u.tags & DefEnums.UT_ANTI_AIR) != 0:
				rank = 3
			for k: int in int(b["buy"][ui]):
				order.append([rank, ui])
		order.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]) or (int(x[0]) == int(y[0]) and int(x[1]) < int(y[1])))
		var dir: int = 1 if pid == 0 else -1
		var front_x: int = cx - dir * dist / 2
		var per_row: int = 14
		for i: int in order.size():
			var row: int = i / per_row
			var col: int = i % per_row
			var jx: int = int(rng.next(6 * CELL)) - 3 * CELL
			var jy: int = int(rng.next(6 * CELL)) - 3 * CELL
			var x: int = front_x * CELL - dir * (row * 2 * CELL + CELL) + jx / 3
			var y: int = cy * CELL + (col - per_row / 2) * 2 * CELL + jy / 3
			var ui2: int = order[i][1]
			var u2: SimEntity = w.spawn_unit(ui2, pid, x, y, 0 if dir == 1 else 2048, 0, view.unit_cost[ui2])
			if u2 != null:
				(ids[pid] as Array).append(u2.id)
		counts[pid] = (ids[pid] as Array).size()
	# orders: attack-move to a point just past the middle (units acquire targets when the order ends and chase like idle units;
	# a far destination makes the armies walk through each other without stopping)
	for pid2: int in 2:
		var tx: int = (cx + dist / 6) * CELL if pid2 == 0 else (cx - dist / 6) * CELL
		w.submit_raw(pid2, SimCmd.attack_move(PackedInt32Array(ids[pid2]), tx, cy * CELL))
	var max_ticks: int = _i("ticks", 4000)
	var t0: int = w.tick
	while w.tick - t0 < max_ticks:
		w.step()
		if _i("verbose", 0) == 1 and (w.tick - t0) % 200 == 0:
			var pos: PackedStringArray = PackedStringArray()
			for pid3: int in 2:
				var sx: int = 0
				var cnt: int = 0
				for id3: int in ids[pid3]:
					var e3: SimEntity = w.get_entity(id3)
					if e3 != null and e3.hp > 0 and (e3.flags & SimFlags.F_GONE) == 0:
						sx += e3.x / CELL
						cnt += 1
				pos.append("p%d alive %d avg_x %d" % [pid3, cnt, sx / maxi(cnt, 1)])
			print("  t=%d %s | %s" % [w.tick - t0, pos[0], pos[1]])
		if (w.tick - t0) % 20 == 0:
			if _alive_units(w, ids[0]) == 0 or _alive_units(w, ids[1]) == 0:
				break
	var sa: float = _alive_value(w, 0, ids[0]) / float(maxi(spent[0], 1))
	var sb: float = _alive_value(w, 1, ids[1]) / float(maxi(spent[1], 1))
	return {"a": ra, "b": rb, "comp": comp, "seed": sd, "share_a": snappedf(sa, 0.001), "share_b": snappedf(sb, 0.001), "diff": snappedf(sa - sb, 0.001),
		"ticks": w.tick - t0, "spent_a": spent[0], "spent_b": spent[1], "n_a": counts[0], "n_b": counts[1]}


func _emit(rec: Dictionary) -> void:
	var line: String = JSON.stringify(rec)
	print("FIGHT_JSON ", line)
	var out: String = str(_args.get("out", ""))
	if out != "":
		var f: FileAccess = FileAccess.open(out, FileAccess.READ_WRITE if FileAccess.file_exists(out) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()


func _pair() -> void:
	var a: String = str(_args.get("a", "roster.napc.vanilla"))
	var b: String = str(_args.get("b", "roster.han.vanilla"))
	var comp: String = str(_args.get("comp", "mid"))
	var tot: float = 0.0
	var n: int = _i("seeds", 3)
	for sd: int in n:
		var rec: Dictionary = _fight(a, b, comp, sd + 1)
		tot += float(rec["diff"])
		print("  seed %d: %s share %.2f vs %.2f (n %d vs %d, %d ticks) diff %+.2f" % [sd + 1, comp, rec["share_a"], rec["share_b"], rec["n_a"], rec["n_b"], rec["ticks"], rec["diff"]])
	print("MEAN %s vs %s %s diff %+.3f" % [a, b, comp, tot / float(n)])


func _grid() -> void:
	var ids: PackedStringArray = _data.roster_ids()
	var shard: PackedStringArray = str(_args.get("shard", "0/1")).split("/")
	var si: int = int(shard[0])
	var sn: int = int(shard[1])
	var k: int = 0
	var comps: PackedStringArray = str(_args.get("comps", "mid")).split(",")
	var n_seeds: int = _i("seeds", 2)
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			if k % sn == si:
				for comp: String in comps:
					for sd: int in n_seeds:
						# alternate the sides between seeds (slot 0 is the west army) to cancel the map-side bias
						var rec: Dictionary
						if sd % 2 == 0:
							rec = _fight(ids[i], ids[j], comp, sd + 1)
						else:
							var r2: Dictionary = _fight(ids[j], ids[i], comp, sd + 1)
							rec = {"a": ids[i], "b": ids[j], "comp": comp, "seed": sd + 1, "share_a": r2["share_b"], "share_b": r2["share_a"], "diff": -float(r2["diff"]),
								"ticks": r2["ticks"], "spent_a": r2["spent_b"], "spent_b": r2["spent_a"], "n_a": r2["n_b"], "n_b": r2["n_a"]}
						_emit(rec)
			k += 1


## mode=units: every ground combat unit of the vanilla rosters plus the units a sub-roster introduces, as a mono army of `budget` (default
## 6000) credits against mono armies of the reference units (ref=unit ids, default guardian tank / rifle squad / paladin howitzer of NAPC
## vanilla). One JSON line per (unit, reference, seed); diff > 0 means the unit's army wins.
func _units() -> void:
	var refs: PackedStringArray = str(_args.get("ref", "unit.napc.guardian_tank,unit.napc.rifle_squad,unit.napc.paladin_howitzer")).split(",")
	var budget: int = _i("budget", 6000)
	var n_seeds: int = _i("seeds", 4)
	var shard: PackedStringArray = str(_args.get("shard", "0/1")).split("/")
	var k: int = 0
	var cases: Array = []
	for r: DefRoster in _data.rosters:
		for ui: int in r.producible_units:
			var u: DefUnit = r.units[ui]
			if not _is_ground(u) or u.cost <= 0 or u.unit_class == DefEnums.UnitClass.SERVICE:
				continue
			var own: bool = r.is_vanilla or u.introduced_by == r.index
			if not own:
				continue
			cases.append([r.id, ui])
	var napc: String = "roster.napc.vanilla"
	for c: Variant in cases:
		if k % int(shard[1]) == int(shard[0]):
			var rid: String = (c as Array)[0]
			var ui2: int = (c as Array)[1]
			for ref_id: String in refs:
				var ref_ui: int = _data.unit_idx(ref_id)
				for sd: int in n_seeds:
					var w0: SimWorld = _make_world(rid, napc, 1)
					var cost_u: int = w0.players[0].view.unit_cost[ui2]
					var cost_r: int = w0.players[1].view.unit_cost[ref_ui]
					var rec: Dictionary
					var cu: Dictionary = {0: {ui2: maxi(budget / cost_u, 1)}, 1: {ref_ui: maxi(budget / cost_r, 1)}}
					if sd % 2 == 0:
						rec = _fight(rid, napc, "units", sd + 1, cu)
					else:
						var cu2: Dictionary = {0: cu[1], 1: cu[0]}
						var r2: Dictionary = _fight(napc, rid, "units", sd + 1, cu2)
						rec = {"a": rid, "b": napc, "comp": "units", "seed": sd + 1, "share_a": r2["share_b"], "share_b": r2["share_a"], "diff": -float(r2["diff"]),
							"ticks": r2["ticks"], "spent_a": r2["spent_b"], "spent_b": r2["spent_a"], "n_a": r2["n_b"], "n_b": r2["n_a"]}
					rec["unit"] = _data.units[ui2].id
					rec["ref"] = ref_id
					rec["tier"] = _data.units[ui2].tier
					rec["cost"] = cost_u
					_emit(rec)
		k += 1
