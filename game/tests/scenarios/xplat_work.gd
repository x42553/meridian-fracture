extends SceneTree
## Cross-platform determinism scenario for the engineer / neutral slice (EC3A): a fogged 96x96 open-map bot match, African
## Empire vs NAPC, 25000 start credits, with Engineers driven by SimWorkDriver (capture of neutral structures, salvage of
## enemy wrecks, paid repair of damaged vehicles) and an MCV deploying into a second HQ, 5000 ticks:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_work.gd
## `HASH tick=<n> <hex>`: every checkpoint of world.checksum_log, then final checksum, event digest, dump digest. Also
## prints `WORK ...` statistics for the balance team (salvage share of income, captured structures).

const TICKS: int = 5000


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	var a: PackedStringArray = PackedStringArray()
	var b: PackedStringArray = PackedStringArray()
	for l: String in first:
		if l.begins_with("HASH"):
			a.append(l)
	for l2: String in second:
		if l2.begins_with("HASH"):
			b.append(l2)
	if a != b:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	quit(0)


func _run() -> PackedStringArray:
	var m: Dictionary = SimMatchKit.make_match({"family": 0, "size": 96, "seed": 2, "rosters": PackedStringArray(["roster.ae.vanilla", "roster.napc.vanilla"]),
		"credits": 25000, "rules": {"fog": true, "unit_cap": 300}, "bot_opts": {"first_attack_tick": 1200, "wave_size": 6, "wave_growth_ticks": 1000000}})
	var w: SimWorld = m["world"]
	var drv: SimWorkDriver = SimWorkDriver.new(PackedInt32Array([0, 1]))
	SimWorkDriver.spawn_engineers(w, 0, 4)
	SimWorkDriver.spawn_engineers(w, 1, 2)
	var mcv: SimEntity = null
	var hq: SimEntity = w.structures_of(0)[0]
	var mcv_cell: int = SimMovement.find_free_cell_near(w, w.map.idx((hq.x >> SimConfig.CELL_SHIFT) + 10, (hq.y >> SimConfig.CELL_SHIFT) + 10), SimEntity.Layer.GROUND, 10)
	if mcv_cell >= 0:
		mcv = w.spawn_unit(w.players[0].roster.mcv_idx, 0, w.map.center_x(mcv_cell), w.map.center_y(mcv_cell), 0, 0, 3000)
	var on_tick: Callable = func(ww: SimWorld, t: int) -> void:
		drv.think(ww)
		if t == 100 and mcv != null:
			ww.submit_raw(0, SimCmd.deploy(PackedInt32Array([mcv.id])))
	SimMatchKit.run(m, TICKS, on_tick)
	var out: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=9001 %08x" % w.checksum())
	out.append("HASH tick=9002 %08x" % w.events.digest())
	out.append("HASH tick=9003 %08x" % Checksum.fnv_string(w.dump_state()))
	var owned: int = 0
	for n: SimEntity in w.neutrals:
		if n.owner >= 0:
			owned += 1
	var pe: SimPlayerEcon = w.players[0].econ
	out.append("WORK ae_salvaged=%d ae_depot=%d ae_harvested=%d share_bp=%d neutrals_owned=%d/%d repair_spent=%d/%d orders salvage=%d capture=%d repair=%d hqs=%d" % [
		pe.stat_salvaged, pe.stat_depot, pe.stat_harvested, w.economy.q_salvage_share_bp(0), owned, w.neutrals.size(),
		pe.stat_spent_repair, w.players[1].econ.stat_spent_repair, drv.salvaged_orders, drv.capture_orders, drv.repair_orders, pe.active_hq_count])
	return out
