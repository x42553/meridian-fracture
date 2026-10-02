extends SceneTree
## Cross-platform determinism scenario of the ability core / auras / containers (task AB2):
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_ab2.gd
## Three players on the REAL balance data (NAPC, NEC Nordics, Han China; teams 1 / 2 / 1), a lake map, real movement,
## combat and economy: deployed howitzers and a Fen mast, a NEC Relay that loses its power, a Han command field with
## drones, a medic, a Factory apron, transports loading and unloading over the lake, a civilian garrison that fires, an
## EW jammer, a submarine surfacing, a mode switch. `HASH tick=<n> <hex>`: every world checkpoint plus the final checksum,
## the event digest and a digest of dump_state(). Self-check: two runs in one process must agree.

const A := preload("res://tests/support/ab2_kit.gd")
const TICKS: int = 1200


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	quit(0)


func _run() -> PackedStringArray:
	var rows: PackedStringArray = A.MV.grid(64)
	A.MV.rect(rows, 40, 10, 58, 40, "~")
	var w: SimWorld = A.world({
		"rosters": ["roster.napc.usa", "roster.nec.nordics", "roster.han.china"], "teams": [1, 2, 1], "rows": rows, "seed": 77,
		"rules": {"fog": true},
	})
	var ids: Dictionary = _setup(w)
	for s: int in TICKS:
		_script(w, s, ids)
		w.step()
	var out: PackedStringArray = PackedStringArray()
	out.append_array(_coverage_note(w))
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [9001, w.checksum()])
	out.append("HASH tick=%d %08x" % [9002, w.events.digest()])
	out.append("HASH tick=%d %08x" % [9003, Checksum.fnv_string(w.dump_state())])
	out.append("HASH tick=%d %08x" % [9004, w.abilities.timer_digest])
	return out


## Non-hash INFO lines: how much of each feature actually happened (a scenario that exercises nothing proves nothing).
func _coverage_note(w: SimWorld) -> PackedStringArray:
	var names: Dictionary = {234: "mode_started", 235: "mode_changed", 240: "loaded", 241: "unloaded", 243: "garrison", 244: "ejected", 208: "death", 200: "fire", 6: "order_failed", 245: "drowned"}
	var counts: Dictionary = {}
	var d: PackedInt32Array = w.events.data
	for i: int in d.size() / SimEvent.STRIDE:
		var t: int = d[i * SimEvent.STRIDE + SimEvent.I_TYPE]
		counts[t] = int(counts.get(t, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for t2: Variant in names:
		parts.append("%s=%d" % [names[t2], int(counts.get(t2, 0))])
	var out: PackedStringArray = PackedStringArray()
	out.append("INFO events " + " ".join(parts))
	return out


func _setup(w: SimWorld) -> Dictionary:
	var d: Dictionary = {}
	# --- P0 (NAPC): howitzers, a hurt tank beside a factory, an APC with two squads, a medic, and a garrison
	d["pal"] = A.spawn(w, "unit.napc.paladin_howitzer", 0, 12, 12).id
	d["pal2"] = A.spawn(w, "unit.napc.paladin_howitzer", 0, 14, 12).id
	A.structure(w, "structure.shared.generator", 0, 10, 20)
	A.structure(w, "structure.shared.factory", 0, 20, 20)
	var g: SimEntity = A.spawn(w, "unit.napc.guardian_tank", 0, 24, 20)
	g.hp = g.hp_max / 2
	d["apc"] = A.spawn(w, "unit.napc.pathfinder_apc", 0, 12, 30).id
	d["sq1"] = A.spawn(w, "unit.napc.rifle_squad", 0, 14, 32).id
	d["sq2"] = A.spawn(w, "unit.napc.rifle_squad", 0, 15, 32).id
	A.spawn(w, "unit.napc.combat_medic", 0, 16, 30)
	var hurt: SimEntity = A.spawn(w, "unit.napc.rifle_squad", 0, 17, 30)
	hurt.hp = hurt.hp_max / 3
	d["lt"] = A.spawn(w, "unit.shared.landing_transport", 0, 38, 30).id
	for i: int in 3:
		d["ls%d" % i] = A.spawn(w, "unit.napc.rifle_squad", 0, 34, 28 + i).id
	d["garr"] = A.neutral(w, "neutral.civilian_garrison", 30, 45).id
	d["gsq"] = A.spawn(w, "unit.napc.rifle_squad", 0, 26, 44).id
	# --- P1 (NEC Nordics): relay + power, leopards, a Fen mast, an EW jammer
	d["gen1"] = A.structure(w, "structure.shared.generator", 1, 50, 50).id
	d["relay"] = A.structure(w, "structure.nec.relay", 1, 52, 50).id
	for i2: int in 3:
		A.spawn(w, "unit.nec.leopard_tank", 1, 50 + i2, 52)
	d["fen"] = A.spawn(w, "unit.nec.fen_recon_carrier", 1, 48, 54).id
	A.spawn(w, "unit.nec.aster_ew_aircraft", 1, 36, 44)
	# --- P2 (Han): a command field
	A.spawn(w, "unit.han.link_operator", 2, 20, 8)
	A.spawn(w, "unit.han.nest_rocket_drone", 2, 22, 8)
	A.spawn(w, "unit.han.nest_rocket_drone", 2, 25, 8)
	A.spawn(w, "unit.han.long_command_walker", 2, 10, 44)
	return d


func _script(w: SimWorld, s: int, d: Dictionary) -> void:
	match s:
		0:
			w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([d["pal"]])))
			w.submit_raw(1, SimCmd.build(SimCmd.DEPLOY, [(w.get_entity(d["fen"]) as SimEntity).abil.slot_of_kind(20)], PackedInt32Array([d["fen"]])))
		5:
			var ids: PackedInt32Array = PackedInt32Array([d["sq1"], d["sq2"]])
			w.submit_raw(0, SimCmd.build(SimCmd.LOAD, [d["apc"], 0], ids))
			var ls: PackedInt32Array = PackedInt32Array([d["ls0"], d["ls1"], d["ls2"]])
			w.submit_raw(0, SimCmd.build(SimCmd.LOAD, [d["lt"], 0], ls))
			w.submit_raw(0, SimCmd.build(SimCmd.GARRISON, [d["garr"], 0], PackedInt32Array([d["gsq"]])))
		150:
			w.submit_raw(0, SimCmd.build(SimCmd.MOVE, [30 * 1024, 30 * 1024, 0, 0], PackedInt32Array([d["apc"]])))
			w.submit_raw(0, SimCmd.build(SimCmd.UNDEPLOY, [-1], PackedInt32Array([d["pal"]])))
		320:
			var apc: SimEntity = w.get_entity(d["apc"])
			if apc != null:
				w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, apc.x, apc.y], PackedInt32Array([apc.id])))
			var lt: SimEntity = w.get_entity(d["lt"])
			if lt != null:
				w.submit_raw(0, SimCmd.build(SimCmd.MOVE, [36 * 1024, 30 * 1024, 0, 0], PackedInt32Array([lt.id])))
		420:
			var lt2: SimEntity = w.get_entity(d["lt"])
			if lt2 != null:
				w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, lt2.x, lt2.y], PackedInt32Array([lt2.id])))
		500:
			var gen: SimEntity = w.get_entity(d["gen1"])
			if gen != null:
				w.remove_entity(gen.id, SimEvent.REM_SCRIPT)  # the NEC relay loses its power
		700:
			w.submit_raw(0, SimCmd.build(SimCmd.DEPLOY, [-1], PackedInt32Array([d["pal2"]])))
		760:
			var gr: SimEntity = w.get_entity(d["garr"])
			if gr != null and gr.cargo != null:
				w.submit_raw(0, SimCmd.build(SimCmd.UNLOAD, [0, 0, gr.x, gr.y], PackedInt32Array([gr.id])))
