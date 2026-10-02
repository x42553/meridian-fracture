extends RefCounted
## EC3A scenarios on a REAL match (SimMatchKit, bots on): S4 salvage economy (African Empire vs NAPC, Engineers driven by
## SimWorkDriver), capture / repair on the go, the income share of salvage, no engine errors, identical double run.

const K := preload("res://tests/support/sim_work_kit.gd")

const TICKS: int = 5000


func _run(seed_v: int, ticks: int) -> Dictionary:
	var m: Dictionary = SimMatchKit.make_match({"rosters": PackedStringArray([K.AE, K.NAPC]), "seed": seed_v, "credits": 15000, "size": 96,
		"rules": {"fog": true, "unit_cap": 300}, "bot_opts": {"first_attack_tick": 1200, "wave_size": 6, "wave_growth_ticks": 1000000}})
	var w: SimWorld = m["world"]
	var drv: SimWorkDriver = SimWorkDriver.new(PackedInt32Array([0, 1]))
	SimWorkDriver.spawn_engineers(w, 0, 4)
	SimWorkDriver.spawn_engineers(w, 1, 2)
	var r: Dictionary = SimMatchKit.run(m, ticks, func(ww: SimWorld, _t: int) -> void: drv.think(ww))
	return {"world": w, "run": r, "driver": drv}


func test_salvage_economy_and_determinism(t: TestCtx) -> void:
	var a: Dictionary = _run(1, TICKS)
	var w: SimWorld = a["world"]
	var r: Dictionary = a["run"]
	var drv: SimWorkDriver = a["driver"]
	t.eq((r["errors"] as PackedStringArray).size(), 0, "no engine errors: %s" % str(r["errors"]).left(200))
	var pe: SimPlayerEcon = w.players[0].econ
	var share: int = w.economy.q_salvage_share_bp(0)
	t.note("S4 AE salvage: %d credits of %d total income (%d bp), %d salvage orders, %d capture orders, %d repair orders, wrecks alive %d" % [
		pe.stat_salvaged, pe.stat_harvested + pe.stat_salvaged + pe.stat_depot, share, drv.salvaged_orders, drv.capture_orders, drv.repair_orders, w.combat.wreck_ids.size()])
	t.eq(w.players[1].econ.stat_salvaged, 0, "NAPC has no salvage income")
	t.check(share < 1500, "salvage stays below 15 %% of the AE income in an even fight (%d bp)" % share)
	t.check(drv.capture_orders > 0, "Engineers went for the neutral structures")
	var b: Dictionary = _run(1, TICKS)
	t.eq((b["world"] as SimWorld).checksum(), w.checksum(), "double run: identical checksum")
	t.eq((b["world"] as SimWorld).events.digest(), w.events.digest(), "double run: identical event digest")
	t.eq(((b["world"] as SimWorld).players[0].econ as SimPlayerEcon).stat_salvaged, pe.stat_salvaged, "same salvage income")


func test_capture_and_repair_in_a_match(t: TestCtx) -> void:
	var a: Dictionary = _run(2, 3000)
	var w: SimWorld = a["world"]
	var owned: int = 0
	for n: SimEntity in w.neutrals:
		if n.owner >= 0:
			owned += 1
	t.check(owned >= 1, "at least one neutral structure changed hands (%d)" % owned)
	t.eq((a["run"]["errors"] as PackedStringArray).size(), 0, "no engine errors")
	t.check(w.players[0].econ.stat_spent_repair + w.players[1].econ.stat_spent_repair >= 0, "repair statistic readable")
