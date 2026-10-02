extends SceneTree
## INT2 ROSTER SHOWCASE (slow, NOT part of the default suite): for each of the 32 rosters, both players get EVERY producible
## structure of their roster spawned around the HQ (power first), 100000 credits (the rules cap), and every producible unit is queued through
## the real production commands (SimCmd.train). Then the two armies attack-move at the enemy base for a while. It finds
## what the bot-vs-bot soak cannot reach: units no producer offers or can queue, defs that break a component, engine
## errors when a unit type moves / fights / dies, and stuck units. Prints per roster:
##   UNITS <roster> vs <opp> producible=<n> offered=<n> queued=<n> delivered=<n> alive_end=<n> errors=<n> stuck=<n>
## followed by NOTE lines (unoffered / refused / undelivered units, missing structure sites, abilities per kind).
##
##   tools/gd run res://tests/scenarios/soak_units.gd                       all 32 rosters
##   tools/gd run res://tests/scenarios/soak_units.gd -- first=4 count=2    a slice
##   tools/gd run res://tests/scenarios/soak_units.gd -- fight=3000 build=4000 family=2
## Args: abilities (AB2: also DRIVE the ability kinds during the fight - deploy / pack, mode switches, loading and unloading of
## transports - and print the ABILITY_EVENTS line), norally (skip the rally: produced units pile up on the exit cell and block later production, see the known gaps), first, count, build (ticks to build, default 6000), fight (ticks of attack-move, default 3000), family (default 2 =
## coast, so Docks and ships work), seed.

const CELL: int = SimConfig.CELL

var _args: Dictionary = {}
var _errors_total: int = 0
var _kinds: Dictionary = {}  ## ability kind name -> unit ids carrying it (all rosters)
var _delivered_defs: Dictionary = {}  ## unit def id -> true
var _all_producible: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			_args[kv[0]] = kv[1]
	var d: GameData = SimMatchKit.data()
	var ids: PackedStringArray = d.roster_ids()
	var first: int = int(_args.get("first", 0))
	var count: int = int(_args.get("count", ids.size()))
	for i: int in range(first, mini(first + count, ids.size())):
		_roster(ids[i], ids[(i + 8) % ids.size()], i)
	var never: PackedStringArray = PackedStringArray()
	for k: Variant in _all_producible.keys():
		if not _delivered_defs.has(k):
			never.append(str(k))
	print("UNITS_SUMMARY errors=%d producible_defs_seen=%d never_delivered=%d: %s" % [_errors_total, _all_producible.size(), never.size(), ", ".join(never)])
	var kinds: Array = _kinds.keys()
	kinds.sort()
	for k: Variant in kinds:
		print("ABILITY_KIND %s carried_by=%d units" % [k, (_kinds[k] as Dictionary).size()])
	print("UNITS_DONE")
	quit(1 if _errors_total > 0 else 0)


func _place_all(w: SimWorld, pid: int, notes: PackedStringArray) -> void:
	var roster: DefRoster = w.players[pid].roster
	var hq: SimEntity = w.structures_of(pid)[0]
	var hx: int = hq.x >> SimConfig.CELL_SHIFT
	var hy: int = hq.y >> SimConfig.CELL_SHIFT
	var site: PackedInt32Array = PackedInt32Array([0, 0])
	var gens: Array[int] = []
	var others: Array[int] = []
	for s_idx: int in roster.producible_structures:
		var sd: DefStructure = w.data.structures[s_idx]
		if sd.power > 0:
			gens.append(s_idx)
		else:
			others.append(s_idx)
	# power: the grid must cover every consumer or production crawls (the power system only counts at the next tick)
	var view: DefPlayerView = w.players[pid].view
	var need: int = 0
	for s_idx: int in others:
		need += maxi(-view.struct_power[s_idx], 0)
	var n_gens: int = 1
	if not gens.is_empty():
		n_gens = need / maxi(view.struct_power[gens[0]], 1) + 2
	var order: Array[int] = []
	for i: int in n_gens:
		if not gens.is_empty():
			order.append(gens[0])
	order.append_array(others)
	for s_idx: int in order:
		var sd: DefStructure = w.data.structures[s_idx]
		var placed: bool = false
		for rot: int in 4:
			if (sd.place_mask & DefEnums.PLACE_SHORELINE) == 0 and rot > 0:
				break
			for ring: int in [8, 14, 20]:
				if SimPlacement.find_site_rot(w, pid, s_idx, hx, hy, ring, rot, site):
					w.spawn_structure(s_idx, pid, SimPlacement.footprint_center_x(w, s_idx, site[0], rot), SimPlacement.footprint_center_y(w, s_idx, site[1], rot), rot * 1024, 0, 0, 0, SimEvent.SPAWN_PLACED)
					placed = true
					break
			if placed:
				break
		if not placed:
			notes.append("P%d no site for structure %s" % [pid, sd.id])


func _queue_all(w: SimWorld, pid: int, offered: Dictionary, refused: Dictionary) -> int:
	var n: int = 0
	var buf: PackedInt32Array = PackedInt32Array()
	for id: int in w.players[pid].econ.producer_flat:
		var e: SimEntity = w.get_entity(id)
		if e == null or e.prod == null:
			continue
		w.production.q_buildable_units(w, pid, id, buf, false)
		for u: int in buf:
			offered[u] = true
		var room: int = w.data.economy.queue_length_n - e.prod.q_def.size()  # commands land next tick: never more than the free slots
		for u: int in buf:
			if room <= 0:
				break
			if refused.has(-u - 1):  # negative keys mark "queued once already"
				continue
			var rsn: int = w.production.can_queue_unit(w, pid, id, u)
			if rsn != SimEconConst.RSN_OK:
				refused[u] = rsn
				continue
			if w.unit_cap_room(pid) - n <= 0:
				return n
			w.submit_raw(pid, SimCmd.train(id, u, 1))
			refused[-u - 1] = true  # queued once (on the first producer that offers it)
			room -= 1
			n += 1
	return n


var _ev_seen: int = 0


## Every ground producer rallies 14 cells from the HQ toward the enemy (otherwise produced units pile up on the exit cell).
func _rally_all(w: SimWorld) -> void:
	for pid: int in 2:
		var hq: SimEntity = w.structures_of(pid)[0]
		var foe: SimEntity = w.structures_of(1 - pid)[0]
		var dx: int = foe.x - hq.x
		var dy: int = foe.y - hq.y
		var dist: int = maxi(Fp.dist(dx, dy), 1)
		var rx: int = hq.x + dx * (14 * CELL) / dist
		var ry: int = hq.y + dy * (14 * CELL) / dist
		var ids: PackedInt32Array = PackedInt32Array()
		for id: int in w.players[pid].econ.producer_flat:
			var pe: SimEntity = w.get_entity(id)
			if pe != null and pe.prod != null and pe.prod.kind != SimEconConst.PROD_AIRFIELD and pe.prod.kind != SimEconConst.PROD_DOCK:
				ids.append(id)
		if not ids.is_empty():
			ids.sort()
			w.submit_raw(pid, SimCmd.set_rally(ids, rx, ry))


func _note_rejections(w: SimWorld, notes: PackedStringArray) -> void:
	var d: PackedInt32Array = w.events.data
	var n: int = d.size() / SimEvent.STRIDE
	if n < _ev_seen:
		_ev_seen = 0
	for i: int in range(_ev_seen, n):
		var b: int = i * SimEvent.STRIDE
		if d[b] == SimEvent.CMD_REJECTED and notes.size() < 40:
			notes.append("command rejected tick %d: pid=%d op=%d err=%s detail=%d target/def=%d" % [d[b + SimEvent.I_TICK], d[b + SimEvent.I_A], d[b + SimEvent.I_B],
				SimCommand.Err.keys()[d[b + SimEvent.I_C]], d[b + SimEvent.I_D], d[b + SimEvent.I_E]])
	_ev_seen = n


## AB2: exercises the ability kinds of pid's units (deploy / pack, mode switch, transports).
func _drive_abilities(w: SimWorld, pid: int, tick: int) -> void:
	var deploy_ids: PackedInt32Array = PackedInt32Array()
	var pack_ids: PackedInt32Array = PackedInt32Array()
	var mode_ids: PackedInt32Array = PackedInt32Array()
	var infantry: PackedInt32Array = PackedInt32Array()
	var carriers: Array[SimEntity] = []
	for u: SimEntity in w.units_of(pid):
		if (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or u.abil == null:
			continue
		if u.abil.slot_of_kind(SimAbilityConsts.AK_DEPLOY) >= 0 or u.abil.slot_of_kind(SimAbilityConsts.AK_SENSOR_MAST) >= 0:
			(deploy_ids if tick % 1000 == 200 else pack_ids).append(u.id)
		if u.abil.slot_of_kind(SimAbilityConsts.AK_MODE_SWITCH) >= 0:
			mode_ids.append(u.id)
		if u.cargo != null and u.kind == SimEntity.Kind.UNIT:
			carriers.append(u)
	for u2: SimEntity in w.units_of(pid):
		if (u2.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or u2.cargo != null:
			continue
		if (w.data.units[u2.def_idx].tags & DefEnums.UT_INFANTRY) != 0 and u2.orders.is_empty():
			infantry.append(u2.id)
	if tick % 1000 == 200 and not deploy_ids.is_empty():
		w.submit_raw(pid, SimCmd.deploy(deploy_ids, -1))
	elif tick % 1000 == 700 and not pack_ids.is_empty():
		w.submit_raw(pid, SimCmd.undeploy(pack_ids, -1))
	if tick % 1000 == 300 and not mode_ids.is_empty():
		w.submit_raw(pid, SimCmd.set_mode(mode_ids, -1, -1))
	if tick % 1000 == 0 and not carriers.is_empty():
		for c: SimEntity in carriers:
			if c.cargo.n_pax == 0 and not infantry.is_empty():
				w.submit_raw(pid, SimCmd.load(infantry.slice(0, 2), c.id))
	elif tick % 1000 == 600 and not carriers.is_empty():
		for c2: SimEntity in carriers:
			if c2.cargo.n_pax > 0:
				w.submit_raw(pid, SimCmd.unload(PackedInt32Array([c2.id]), 0, 0, c2.x, c2.y))


func _note_delivered(w: SimWorld, delivered: Array[Dictionary]) -> void:
	for pid: int in 2:
		for u: SimEntity in w.units_of(pid):
			if (u.flags & SimFlags.F_GONE) == 0:
				var id: String = w.data.units[u.def_idx].id
				delivered[pid][id] = true
				_delivered_defs[id] = true


func _roster(ra: String, rb: String, idx: int) -> void:
	var errs: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errs.append("[%d] %s: %s" % [lv, tag, msg])
	var fam: int = int(_args.get("family", 2))
	var m: Dictionary = SimMatchKit.make_match({"family": fam, "size": 128, "seed": 200 + idx + int(_args.get("seed", 0)), "rosters": PackedStringArray([ra, rb]),
		"bots": false, "credits": 100000, "map_params": {"start_near_water": true},
		"rules": {"fog": true, "unit_cap": 500, "victory": 0}, "opts": {"invariants_every": 500}})
	var w: SimWorld = m["world"]
	if w == null:
		Log.sink = old_sink
		_errors_total += 1
		print("UNITS %s WORLD NOT CREATED %s" % [ra, errs])
		return
	var notes: PackedStringArray = PackedStringArray()
	var offered: Array[Dictionary] = [{}, {}]
	var refused: Array[Dictionary] = [{}, {}]
	var queued: PackedInt32Array = PackedInt32Array([0, 0])
	for pid: int in 2:
		_place_all(w, pid, notes)
	# static data check: every producible unit of the roster should be offered by some structure of the roster
	var t0: int = Time.get_ticks_usec()
	var build_ticks: int = int(_args.get("build", 6000))
	var delivered: Array[Dictionary] = [{}, {}]
	_ev_seen = 0
	for tick: int in build_ticks:
		if tick % 40 == 0:
			for pid: int in 2:
				queued[pid] += _queue_all(w, pid, offered[pid], refused[pid])
		if tick == 2 and not _args.has("norally"):
			_rally_all(w)
		if tick % 20 == 0:
			_note_delivered(w, delivered)
		w.step()
		_note_rejections(w, notes)
	# fight: everything that can attack attack-moves at the enemy HQ, the rest moves there
	var hq_pos: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 0)]
	for pid: int in 2:
		var hq: SimEntity = w.structures_of(pid)[0]
		hq_pos[pid] = Vector2i(hq.x, hq.y)
	var fight: int = int(_args.get("fight", 3000))
	var stuck_units: Dictionary = {}
	var anchor: Dictionary = {}
	for tick: int in fight:
		if tick % 100 == 0:
			_note_delivered(w, delivered)
			for pid: int in 2:
				var ids: PackedInt32Array = PackedInt32Array()
				for u: SimEntity in w.units_of(pid):
					if (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0:
						continue
					var ud: DefUnit = w.data.units[u.def_idx]
					if (ud.tags & DefEnums.UT_COLLECTOR) != 0 or u.orders.size() > 0:
						continue
					ids.append(u.id)
				if not ids.is_empty():
					var tgt: Vector2i = hq_pos[1 - pid]
					w.submit_raw(pid, SimCmd.attack_move(ids, tgt.x, tgt.y))
				if _args.has("abilities"):
					_drive_abilities(w, pid, tick)
			# stuck sampling: a unit with a move-type order that has not moved a cell in 30 s and is not fighting
			for pid: int in 2:
				for u: SimEntity in w.units_of(pid):
					if (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or u.orders.is_empty() or u.layer == SimEntity.Layer.AIR:
						anchor.erase(u.id)
						continue
					var ty: int = u.orders[0].type
					if ty != SimOrder.T_ATTACK_MOVE and ty != SimOrder.T_MOVE:
						anchor.erase(u.id)
						continue
					if u.combat != null and (u.combat.target_id > 0 or w.tick - u.combat.last_fire_tick < 100):
						anchor.erase(u.id)
						continue
					var a: Variant = anchor.get(u.id)
					if a == null or absi(u.x - int(a[0])) + absi(u.y - int(a[1])) >= CELL:
						anchor[u.id] = [u.x, u.y, w.tick]
					elif w.tick - int(a[2]) >= 600:
						stuck_units[w.data.units[u.def_idx].id] = int(stuck_units.get(w.data.units[u.def_idx].id, 0)) + 1
						anchor[u.id] = [u.x, u.y, w.tick]
						if u.move != null and notes.size() < 60:
							var near_ids: PackedInt32Array = PackedInt32Array()
							w.query_circle(u.x, u.y, 2500, near_ids)
							var near_txt: PackedStringArray = PackedStringArray()
							for nid: int in near_ids:
								var ne: SimEntity = w.by_id[nid]
								if ne != u:
									near_txt.append("%s%s@%d,%d%s" % [w.data.units[ne.def_idx].id if ne.kind == SimEntity.Kind.UNIT else "S" + str(ne.def_idx), "(P%d)" % ne.owner, ne.x >> 10, ne.y >> 10, "!imm" if ne.kind == SimEntity.Kind.UNIT and w.abilities.is_immobile(ne) else ""])
							notes.append("stuck near %s" % [", ".join(near_txt)])
							var blk: SimEntity = w.get_entity(u.move.blocked_by) if u.move.blocked_by > 0 else null
							notes.append("stuck detail %s tick %d state=%d result=%d blocked_by=%s immobile=%s order=%d cell=%d,%d spd=%d vcur=%d path=%d wp=%d goal=%d,%d flags=%x dfl=%d" % [w.data.units[u.def_idx].id, w.tick, u.move.state, u.move.result,
								w.data.units[blk.def_idx].id if blk != null and blk.kind == SimEntity.Kind.UNIT else "-", str(w.abilities.is_immobile(u)), u.orders[0].type, u.x >> 10, u.y >> 10,
								u.move.spd_q4, u.move.vcur_q4, u.move.path.size(), u.move.wp, u.move.goal_x >> 10, u.move.goal_y >> 10, u.flags, u.stats.flags if u.stats != null else -1])
		w.step()
	Log.sink = old_sink
	if _args.has("abilities"):
		var ec: Dictionary = {}
		var evd: PackedInt32Array = w.events.data
		for ei: int in evd.size() / SimEvent.STRIDE:
			var et: int = evd[ei * SimEvent.STRIDE]
			if et >= 234 and et <= 245:
				ec[et] = int(ec.get(et, 0)) + 1
		print("  ABILITY_EVENTS %s mode_started=%d mode_changed=%d loaded=%d unloaded=%d blocked=%d ejected=%d drowned=%d" % [ra,
			int(ec.get(234, 0)), int(ec.get(235, 0)), int(ec.get(240, 0)), int(ec.get(241, 0)), int(ec.get(242, 0)), int(ec.get(244, 0)), int(ec.get(245, 0))])
	if _args.has("queues"):
		for pid: int in 2:
			var an: PackedStringArray = PackedStringArray()
			for u: SimEntity in w.units_of(pid):
				an.append("%s%s" % [w.data.units[u.def_idx].id.trim_prefix("unit."), "(gone)" if (u.flags & SimFlags.F_GONE) != 0 else ""])
			print("  ALIVE P%d %s" % [pid, an])
			print("  REJECTED P%d cmds=%d rejected=%d built=%d lost=%d" % [pid, w.players[pid].st_cmds, w.players[pid].st_rejected, w.players[pid].st_units_built, w.players[pid].st_units_lost])
			print("  POWER P%d supply=%d demand=%d credits=%d rate_bp(inf)=%d" % [pid, w.power.supply(pid), w.power.demand(pid), w.players[pid].credits, w.production.q_rate_bp(pid, SimEconConst.PROD_BARRACKS)])
			for id: int in w.players[pid].econ.producer_flat:
				var pe: SimEntity = w.get_entity(id)
				var qn: PackedStringArray = PackedStringArray()
				for q: int in pe.prod.q_def:
					qn.append(w.data.units[q].id)
				print("  QUEUE P%d %s kind=%d state=%d hold=%s progress=%d q=%s" % [pid, w.data.structures[pe.def_idx].id, pe.prod.kind, pe.prod.head_state, pe.prod.hold, pe.prod.head_progress, qn])
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(build_ticks + fight)
	# per player accounting
	var st: Dictionary = {}
	for pid: int in 2:
		var roster: DefRoster = w.players[pid].roster
		var prod_n: int = roster.producible_units.size()
		var off_n: int = 0
		var missing: PackedStringArray = PackedStringArray()
		var not_delivered: PackedStringArray = PackedStringArray()
		for u: int in roster.producible_units:
			_all_producible[w.data.units[u].id] = true
			if offered[pid].has(u):
				off_n += 1
			else:
				missing.append("%s" % w.data.units[u].id)
			if not delivered[pid].has(w.data.units[u].id):
				if offered[pid].has(u):
					var why: String = "refused rsn=%d" % int(refused[pid].get(u, -1)) if refused[pid].has(u) else "queued but never delivered"
					not_delivered.append("%s (%s)" % [w.data.units[u].id, why])
		var rp: Dictionary = SimMatchKit.report(w, pid)
		st[pid] = [prod_n, off_n, queued[pid], delivered[pid].size(), rp["units"], missing, not_delivered]
		for u: DefUnit in roster.units:
			if u != null:
				for ab: DefAbility in u.abilities:
					var key: String = DefEnums.ABILITY_NAMES[ab.kind] if ab.kind >= 0 and ab.kind < DefEnums.ABILITY_NAMES.size() else str(ab.kind)
					if not _kinds.has(key):
						_kinds[key] = {}
					(_kinds[key] as Dictionary)[u.id] = true
	var n_stuck: int = 0
	for k: Variant in stuck_units.keys():
		n_stuck += int(stuck_units[k])
	print("UNITS %s vs %s producible=%d/%d offered=%d/%d queued=%d/%d delivered_types=%d/%d units_end=%d/%d ms/tick=%.3f errors=%d stuck=%d digest=%08x" % [
		ra, rb, st[0][0], st[1][0], st[0][1], st[1][1], st[0][2], st[1][2], st[0][3], st[1][3], st[0][4], st[1][4], ms, errs.size(), n_stuck,
		(Checksum.fnv_string(str(w.checksum_log)) ^ w.checksum()) & 0xFFFFFFFF])
	for pid: int in 2:
		if not (st[pid][5] as PackedStringArray).is_empty():
			print("  NOTE P%d units no structure offers: %s" % [pid, ", ".join(st[pid][5])])
		if not (st[pid][6] as PackedStringArray).is_empty():
			print("  NOTE P%d units offered but not delivered: %s" % [pid, ", ".join(st[pid][6])])
	for s: String in notes:
		print("  NOTE %s" % s)
	for k: Variant in stuck_units.keys():
		print("  NOTE stuck %s x%d" % [k, stuck_units[k]])
	for e: String in errs.slice(0, 6):
		print("  ERR %s" % e)
	_errors_total += errs.size()
