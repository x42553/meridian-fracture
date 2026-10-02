extends RefCounted
## INT1 seam tests: the hooks and registrations of separately built domains that only matter in a REAL match (real data,
## generated map, every real system): footprints and neutral defs on a real MapData, start state, power-gated defences,
## rally / exit, wrecks, Dock placement and naval production on a coast map, aircraft on pads, the berth rule.

const CELL: int = SimConfig.CELL
const NAPC_NEC: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla"]
const SANDBOX: Dictionary = {"start_mode": 2, "victory": 0, "neutral_structures": 0, "unit_cap": 300}


func _sandbox(o: Dictionary = {}) -> SimWorld:
	var oo: Dictionary = {"seed": 3, "rosters": NAPC_NEC, "bots": false, "rules": SANDBOX}
	oo.merge(o, true)
	return SimMatchKit.make_world(oo)


func _cell_xy(w: SimWorld, slot: int) -> Vector2i:
	var cell: int = w.map.spawns[slot * MapData.SPAWN_STRIDE + 1]
	return Vector2i(cell % w.map.w, cell / w.map.w)


func _events_of(w: SimWorld, type: int, a: int = -1) -> int:
	var n: int = 0
	var d: PackedInt32Array = w.events.data
	for i: int in d.size() / SimEvent.STRIDE:
		if d[i * SimEvent.STRIDE] == type and (a < 0 or d[i * SimEvent.STRIDE + SimEvent.I_A] == a):
			n += 1
	return n


func test_footprints_and_neutrals_are_registered(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 4, "bots": false})
	var w: SimWorld = m["world"]
	var d: GameData = w.data
	for s: DefStructure in d.structures:
		var fp: MapFootprint = w.map.footprint_of(SimEntity.Kind.STRUCTURE, s.index)
		if not t.not_null(fp, s.id):
			continue
		t.eq([fp.w, fp.h], [s.fp_w, s.fp_h] as Array, "%s footprint size" % s.id)
	for n: DefNeutral in d.neutrals:
		t.not_null(w.map.footprint_of(SimEntity.Kind.NEUTRAL, n.index), n.id)
	for nk: int in w.map.neutral_ids.size():
		var ni: int = w.map.neutral_def_for_kind(nk)
		t.eq(ni, d.neutral_idx(w.map.neutral_ids[nk]), "neutral kind %d maps to its DefNeutral" % nk)
		t.eq(w.map.neutral_ent_kind(nk), SimEntity.Kind.NEUTRAL, "neutral kind %d spawns Kind.NEUTRAL" % nk)
	t.gt(w.neutrals.size(), 0, "the generated map's neutral structures were spawned")
	for e: SimEntity in w.neutrals:
		t.eq(e.owner, -1, "neutral owner")
		t.gt(e.hp, 0, "neutral hp from DefNeutral")
		var fp: MapFootprint = w.map.footprint_of(SimEntity.Kind.NEUTRAL, e.def_idx)
		var cx: int = (e.x - fp.w * (CELL / 2)) >> SimConfig.CELL_SHIFT
		var cy: int = (e.y - fp.h * (CELL / 2)) >> SimConfig.CELL_SHIFT
		t.eq(w.struct_at(cx, cy), e.id, "neutral %d occupies its footprint" % e.id)
	# every player's HQ stands on its generated start cell and occupies 3x3
	for pid: int in 2:
		var hq: SimEntity = w.structures_of(pid)[0]
		var st: Vector2i = _cell_xy(w, w.config.players[pid].start)
		t.eq([hq.x >> SimConfig.CELL_SHIFT, hq.y >> SimConfig.CELL_SHIFT], [st.x, st.y] as Array, "P%d HQ on its start cell" % pid)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				t.eq(w.struct_at(st.x + dx, st.y + dy), hq.id, "P%d HQ cell %d,%d" % [pid, dx, dy])


func test_start_state(t: TestCtx) -> void:
	var w: SimWorld = SimMatchKit.make_world({"seed": 4, "bots": false})
	w.run(2)
	for pid: int in 2:
		var p: SimPlayer = w.players[pid]
		t.eq(p.credits, 7500, "P%d bible preset credits" % pid)
		var hq: SimEntity = w.structures_of(pid)[0]
		t.eq(hq.def_idx, p.roster.hq_idx, "P%d starts with its roster's HQ" % pid)
		t.eq(hq.econ.st, SimEconConst.ST_ACTIVE, "HQ deployed / active")
		t.check((hq.flags & SimFlags.F_UNDER_CONSTRUCTION) == 0, "HQ is not in build-up")
		t.eq(p.econ.active_hq_count, 1, "one construction anchor")
		t.check(w.production.has_active_hq(w, pid), "production sees the HQ")
		t.eq(w.units_of(pid).size(), 0, "no free units at the start (the refinery brings the Collector)")
	t.eq(w.rules.start_credits, SimConfig.DEFAULT_START_CREDITS, "default rules")


func test_defence_needs_power(t: TestCtx) -> void:
	var counts: PackedInt32Array = PackedInt32Array()
	for powered: bool in [true, false]:
		var w: SimWorld = _sandbox()
		var at: Vector2i = _cell_xy(w, 0)
		var d: GameData = w.data
		var gen: int = d.structure_idx("structure.shared.generator")
		var tower: int = d.structure_idx("structure.shared.watchtower")
		if powered:
			w.spawn_structure(gen, 0, (at.x - 6) * CELL + CELL, (at.y - 6) * CELL + CELL, 0, 0, 600)
		var tw: SimEntity = w.spawn_structure(tower, 0, at.x * CELL + CELL / 2, at.y * CELL + CELL / 2, 0, 0, 450)
		# an enemy Javelin team just inside the watchtower's range
		var jav: int = d.unit_idx("unit.nec.spike_team")
		var enemy: SimEntity = w.spawn_unit(jav, 1, at.x * CELL + 4 * CELL, at.y * CELL + CELL / 2, 0, 0, 350)
		w.run(300)
		var fired: int = _events_of(w, SimCombatConsts.EV_FIRE, tw.id)
		counts.append(fired)
		if powered:
			t.check((tw.flags & SimFlags.F_POWERED) != 0, "the watchtower is powered by the generator")
			t.gt(fired, 0, "a powered watchtower fires (%d shots)" % fired)
			t.lt(enemy.hp, enemy.hp_max, "and hurts the enemy")
		else:
			t.check((tw.flags & SimFlags.F_POWERED) == 0, "no generator: not powered")
			t.eq(fired, 0, "an unpowered watchtower never fires")


func test_produced_units_exit_and_rally(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 2, "bots": true})
	var w: SimWorld = m["world"]
	var bot: SimBot = (m["bots"] as Array)[0]
	var only0: Dictionary = {"world": w, "bots": [bot]}
	SimMatchKit.run(only0, 4200)
	var rally: Vector2i = bot.rally_point()
	var produced: int = 0
	var near: int = 0
	for u: SimEntity in w.units_of(0):
		var ud: DefUnit = w.data.units[u.def_idx]
		if (ud.tags & DefEnums.UT_COMBAT) == 0:
			continue
		produced += 1
		var dx: int = (u.x - rally.x) >> SimConfig.CELL_SHIFT
		var dy: int = (u.y - rally.y) >> SimConfig.CELL_SHIFT
		if dx * dx + dy * dy <= 8 * 8:
			near += 1
	t.gt(produced, 3, "the bot produced combat units")
	t.ge(near * 100 / maxi(produced, 1), 75, "at least 75%% of them left the factory yard and reached the rally point (%d of %d)" % [near, produced])
	# nothing stands inside a structure footprint
	for u: SimEntity in w.units_of(0):
		t.eq(w.struct_at(u.x >> SimConfig.CELL_SHIFT, u.y >> SimConfig.CELL_SHIFT), 0, "unit %d is not inside a structure" % u.id)


## The cheapest combat tank of a player's roster.
func _tank_of(w: SimWorld, pid: int) -> int:
	var best: int = -1
	for u: int in w.players[pid].roster.producible_units:
		var ud: DefUnit = w.data.units[u]
		if (ud.tags & DefEnums.UT_TANK) != 0 and (ud.tags & DefEnums.UT_COMBAT) != 0 and (best < 0 or ud.cost < w.data.units[best].cost):
			best = u
	return best


## Wrecks exist only in matches where some roster can salvage (SimCombatSystem.salvage_enabled: the African Empire),
## so the duel is AE against NEC; without an AE player no wreck must appear.
func test_tank_duel_leaves_wrecks_only_with_salvage(t: TestCtx) -> void:
	_duel(t, PackedStringArray(["roster.ae.vanilla", "roster.nec.vanilla"]), true)
	_duel(t, NAPC_NEC, false)


func _duel(t: TestCtx, rosters: PackedStringArray, want_wrecks: bool) -> void:
	var w: SimWorld = _sandbox({"seed": 3, "rosters": rosters})
	t.eq(w.combat.salvage_enabled != 0, want_wrecks, "salvage_enabled follows the rosters")
	var tank0: int = _tank_of(w, 0)
	var tank1: int = _tank_of(w, 1)
	var a: Vector2i = _cell_xy(w, 0)
	var ids0: PackedInt32Array = PackedInt32Array()
	var ids1: PackedInt32Array = PackedInt32Array()
	for i: int in 4:
		ids0.append(w.spawn_unit(tank0, 0, (a.x - 12) * CELL, (a.y + i * 2) * CELL, 0, 0, 935).id)
		ids1.append(w.spawn_unit(tank1, 1, (a.x - 22) * CELL, (a.y + i * 2) * CELL, 0, 0, 1000).id)
	w.step()
	w.submit_raw(0, SimCmd.attack_move(ids0, (a.x - 22) * CELL, (a.y + 3) * CELL))
	w.submit_raw(1, SimCmd.attack_move(ids1, (a.x - 12) * CELL, (a.y + 3) * CELL))
	var wreck_seen: int = 0
	for _i: int in 1500:
		w.step()
		wreck_seen = maxi(wreck_seen, w.wrecks.size())
	var dead0: int = w.players[0].st_units_lost
	var dead1: int = w.players[1].st_units_lost
	t.gt(dead0 + dead1, 2, "tanks died (%d + %d)" % [dead0, dead1])
	if want_wrecks:
		t.gt(wreck_seen, 0, "dead combat vehicles left wrecks (max %d alive at once)" % wreck_seen)
	else:
		t.eq(wreck_seen, 0, "no salvage in the match: no wrecks")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants clean")


func test_dock_on_a_coast_map_builds_ships(t: TestCtx) -> void:
	var lad: PackedStringArray = ["power", "refinery", "dock"]
	var m: Dictionary = SimMatchKit.make_match({
		"family": 2, "seed": 1, "size": 128, "map_params": {"start_near_water": true}, "credits": 12000,
		"bot_opts": {"ladder": lad, "naval": true, "first_attack_tick": 100000}, "opts": {"invariants_every": 300}})
	var w: SimWorld = m["world"]
	var r: Dictionary = SimMatchKit.run(m, 3600)
	t.eq(r["errors"], PackedStringArray(), "no errors")
	for pid: int in 2:
		var dock: SimEntity = null
		for s: SimEntity in w.structures_of(pid):
			if w.data.structures[s.def_idx].queue_kind == DefEnums.QueueKind.NAVAL:
				dock = s
		if not t.not_null(dock, "P%d built a Dock next to the water" % pid):
			continue
		# the berth strip beyond the footprint passes the map's own berth rule (was refused for EVERY real dock)
		var d: DefStructure = w.data.structures[dock.def_idx]
		var fp: MapFootprint = SimPlacement.footprint_of_def(w, dock.def_idx)
		var org: PackedInt32Array = PackedInt32Array([0, 0])
		SimPlacement.entity_origin(w, dock, org)
		var orient: int = ((dock.facing >> 10) & 3) if fp.rotatable else 0
		var berth: PackedInt32Array = PackedInt32Array()
		var o: PackedInt32Array = PackedInt32Array([0, 0])
		for dy: int in range(d.fp_h, d.fp_h + SimPlacement.DOCK_BERTH_ROWS):
			for dx: int in d.fp_w:
				MapFootprint.rotate_offset(fp.w, fp.h, orient, dx, dy, o)
				berth.append(w.map.idx(org[0] + o[0], org[1] + o[1]))
		t.eq(MapBuildRules.check_berth(w.map, berth, SimPlacement.MIN_WATER_BODY), MapBuildRules.PR_OK, "P%d dock berth passes MapBuildRules.check_berth" % pid)
		var ships: int = 0
		for u: SimEntity in w.units_of(pid):
			var ud: DefUnit = w.data.units[u.def_idx]
			if (ud.tags & DefEnums.UT_SHIP) != 0:
				ships += 1
				t.eq(u.layer, SimEntity.Layer.SURFACE, "a ship floats")
				var k: int = w.map.kind[(u.y >> SimConfig.CELL_SHIFT) * w.map.w + (u.x >> SimConfig.CELL_SHIFT)]
				t.check(k == MapTerrain.TK_DEEP or k == MapTerrain.TK_SHALLOW, "a ship is on water (kind %d)" % k)
		t.gt(ships, 0, "P%d's dock produced a ship" % pid)


func test_aircraft_park_on_pads_and_sortie(t: TestCtx) -> void:
	var lad: PackedStringArray = ["power", "refinery", "barracks", "factory", "tech", "airfield"]
	var m: Dictionary = SimMatchKit.make_match({
		"seed": 6, "credits": 25000, "rules": {"unit_cap": 300},
		"bot_opts": {"ladder": lad, "air": true, "first_attack_tick": 100000}, "opts": {"invariants_every": 300}})
	var w: SimWorld = m["world"]
	var r: Dictionary = SimMatchKit.run(m, 6000)
	t.eq(r["errors"], PackedStringArray(), "no errors")
	var flown: int = 0
	for pid: int in 2:
		var af: SimEntity = null
		for s: SimEntity in w.structures_of(pid):
			if w.data.structures[s.def_idx].queue_kind == DefEnums.QueueKind.AIRCRAFT:
				af = s
		if not t.not_null(af, "P%d built an Airfield" % pid):
			continue
		var parked: int = 0
		for u: SimEntity in w.units_of(pid):
			if u.air != null and u.air.is_airfield == 0:
				flown += 1
				if u.air.home_id == af.id and u.air.pad >= 0:
					parked += 1
		t.gt(parked, 0, "P%d aircraft are bound to their airfield's pads (SimAirSortie.on_aircraft_spawned)" % pid)
	t.gt(flown, 1, "aircraft were produced")


## start_mode MCV: the DEPLOY command unfolds the MCV of each start into its HQ (T_DEPLOY_MCV order), then the match
## runs as usual. Nobody had registered the DEPLOY executor before INT1.
func test_mcv_start_deploys(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 1, "rules": {"start_mode": 1}, "opts": {"invariants_every": 200}})
	var w: SimWorld = m["world"]
	for pid: int in 2:
		t.eq(w.structures_of(pid).size(), 0, "P%d starts without structures" % pid)
		t.eq(w.units_of(pid).size(), 1, "P%d starts with its MCV" % pid)
		t.eq(w.units_of(pid)[0].def_idx, w.players[pid].roster.mcv_idx, "the MCV")
	var r: Dictionary = SimMatchKit.run(m, 3000)
	t.eq(r["errors"], PackedStringArray(), "no errors")
	t.gt(_events_of(w, SimEconConst.EVT_HQ_DEPLOYED), 1, "both MCVs deployed (EVT_HQ_DEPLOYED)")
	for pid: int in 2:
		var rp: Dictionary = SimMatchKit.report(w, pid)
		t.ge(rp["structures_built"], 4, "P%d built its base after deploying" % pid)
		t.gt(rp["harvested"], 500, "P%d harvested" % pid)
	# an ordinary unit refuses DEPLOY
	var rifle: SimEntity = w.spawn_unit(w.data.unit_idx("unit.napc.rifle_squad"), 0, 40 * CELL, 40 * CELL)
	var before: int = w.players[0].st_rejected
	w.submit_raw(0, SimCmd.deploy(PackedInt32Array([rifle.id])))
	w.step()
	t.eq(w.players[0].st_rejected, before + 1, "DEPLOY on a rifle squad is rejected")


## INT2: with fog on, the start area is explored at tick 0 (SimMatchSetup.reveal_start_areas), so a Collector finds the
## generator's two start fields (11 cells from the spawn) at once. Before, a fogged start left every field unexplored and the
## first Collector idled in H_SEEK for ~600 ticks until something walked near a field.
func test_fogged_start_explores_the_start_fields(t: TestCtx) -> void:
	for fam: int in 3:
		var m: Dictionary = SimMatchKit.make_match({"seed": 100 + fam, "family": fam, "rules": {"fog": true}, "bots": false})
		var w: SimWorld = m["world"]
		SimMatchKit.run(m, 3)
		var deps: SimDepositTable = w.economy.deposits
		for pid: int in 2:
			var st: Vector2i = _cell_xy(w, w.config.players[pid].start)
			var near: int = 0
			for f: int in deps.count:
				var fx: int = deps.x[f] >> SimConfig.CELL_SHIFT
				var fy: int = deps.y[f] >> SimConfig.CELL_SHIFT
				var d2: int = (fx - st.x) * (fx - st.x) + (fy - st.y) * (fy - st.y)
				if d2 <= 12 * 12:
					near += 1
					t.check(w.cell_explored(pid, fx, fy), "family %d P%d: the start field %d (%d,%d) is explored at the start" % [fam, pid, f, fx, fy])
			t.ge(near, 2, "family %d P%d has its two start fields within 12 cells" % [fam, pid])
			var far: Vector2i = _cell_xy(w, w.config.players[1 - pid].start)
			t.check(not w.cell_explored(pid, far.x, far.y), "family %d P%d has not explored the enemy start" % [fam, pid])


func test_fogged_collectors_harvest_promptly(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 100, "rules": {"fog": true}, "opts": {"invariants_every": 200}})
	var r: Dictionary = SimMatchKit.run(m, 2800)
	var w: SimWorld = m["world"]
	t.eq(r["errors"], PackedStringArray(), "no errors")
	for pid: int in 2:
		var seek_ticks: int = 0
		for u: SimEntity in w.units_of(pid):
			if u.econ != null and u.econ.h_state == SimEconConst.H_SEEK:
				seek_ticks += 1
		t.eq(seek_ticks, 0, "P%d: no Collector is left searching for a field" % pid)
		t.gt(SimMatchKit.report(w, pid)["harvested"], 0, "P%d has harvested by tick 2800" % pid)
