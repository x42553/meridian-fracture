extends RefCounted
## INT1 full-match scenarios on the REAL data, REAL generated maps and every REAL system (SimMatchKit + SimBot):
## a 2-player NAPC-vs-NEC 10-minute match on a 96x96 open map (economy, production, placement, harvest band, combat,
## deaths, invariants, double-run determinism), a roster/family sweep and an 8-player free-for-all.

const TEN_MINUTES: int = 12000
const ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla"]


static func opts_10min() -> Dictionary:
	return {"family": 0, "size": 96, "seed": 1, "rosters": ROSTERS, "opts": {"invariants_every": 200}}


## One full run: the match plus a sampled count of collector-ticks per player (for the harvest band).
static func run_match(o: Dictionary, ticks: int) -> Dictionary:
	var m: Dictionary = SimMatchKit.make_match(o)
	var w: SimWorld = m["world"]
	var coll_ticks: PackedInt32Array = PackedInt32Array()
	coll_ticks.resize(w.players.size())
	var r: Dictionary = SimMatchKit.run(m, ticks, func(world: SimWorld, tick: int) -> void:
		if tick % 100 == 0:
			var n: PackedInt32Array = PackedInt32Array()
			for pid: int in world.players.size():
				world.economy.q_collectors(pid, n)
				coll_ticks[pid] += n.size() * 100)
	r["match"] = m
	r["coll_ticks"] = coll_ticks
	r["dump"] = Checksum.fnv_string(w.dump_state())
	r["events"] = w.events.digest()
	return r


func test_ten_minute_match_is_deterministic(t: TestCtx) -> void:
	var a: Dictionary = run_match(opts_10min(), TEN_MINUTES)
	var w: SimWorld = (a["match"] as Dictionary)["world"]
	t.eq(a["errors"], PackedStringArray(), "no Log warning / error / invariant violation in 12000 ticks")
	t.eq(a["ticks"], TEN_MINUTES, "the match ran the whole ten minutes (nobody eliminated)")
	t.note("10 min: %.3f ms/tick average, %.2f ms worst tick (bots included)" % [a["ms_avg"], a["ms_max"]])
	t.lt(a["ms_avg"], 5.0, "average tick cost")
	var coll: PackedInt32Array = a["coll_ticks"]
	for pid: int in 2:
		var rp: Dictionary = SimMatchKit.report(w, pid)
		t.gt(rp["harvested"], 4000, "P%d harvested credits" % pid)
		t.gt(rp["spent_construction"], 5000, "P%d spent credits on structures" % pid)
		t.gt(rp["spent_units"], 3000, "P%d spent credits on units" % pid)
		t.ge(rp["structures_built"], 5, "P%d placed structures" % pid)
		t.ge(rp["built"], 15, "P%d produced units" % pid)
		# income per collector-minute against the economy framework band (766/min on a 10-cell field, 735 measured)
		var per_min: float = float(rp["harvested"]) * 1200.0 / float(maxi(coll[pid], 1))
		t.note("P%d: %d credits harvested, %.0f per collector-minute" % [pid, rp["harvested"], per_min])
		t.check(per_min > 500.0 and per_min < 900.0, "P%d harvest income %.0f per collector-minute inside the band 500..900" % [pid, per_min])
	var r0: Dictionary = SimMatchKit.report(w, 0)
	var r1: Dictionary = SimMatchKit.report(w, 1)
	t.gt(int(r0["killed"]) + int(r1["killed"]), 5, "combat happened: kills")
	t.gt(int(r0["lost"]) + int(r1["lost"]), 5, "combat happened: losses")
	t.eq(SimInvariants.check(w), PackedStringArray(), "invariants clean at the end")
	# identical second run: checksum chain, events, final checksum and the full state dump
	var b: Dictionary = run_match(opts_10min(), TEN_MINUTES)
	t.eq(b["chain"], a["chain"], "checksum chain identical on a second run")
	t.eq(b["checksum"], a["checksum"], "final checksum identical")
	t.eq(b["events"], a["events"], "event digest identical")
	t.eq(b["dump"], a["dump"], "state dump identical")
	t.eq(b["errors"], PackedStringArray(), "second run clean")


func test_rosters_and_families_sweep(t: TestCtx) -> void:
	var pairs: Array = [
		["roster.ae.vanilla", "roster.def.vanilla"], ["roster.han.vanilla", "roster.olm.vanilla"], ["roster.pd.vanilla", "roster.sap.vanilla"],
		["roster.napc.usa", "roster.nec.eurocorps"], ["roster.ae.kongo", "roster.han.china"], ["roster.def.russia", "roster.olm.saudi_arabia"],
		["roster.pd.japan", "roster.sap.india"], ["roster.napc.canada", "roster.nec.nordics"],
	]
	for i: int in pairs.size():
		var o: Dictionary = {"family": i % 3, "seed": 40 + i, "rosters": PackedStringArray(pairs[i]), "opts": {"invariants_every": 300}, "bot_opts": {"first_attack_tick": 1500, "wave_size": 6}}
		var r: Dictionary = run_match(o, 3000)
		var w: SimWorld = (r["match"] as Dictionary)["world"]
		var tag: String = "%s vs %s (family %d)" % [pairs[i][0], pairs[i][1], i % 3]
		t.eq(r["errors"], PackedStringArray(), "%s: no errors" % tag)
		for pid: int in 2:
			var rp: Dictionary = SimMatchKit.report(w, pid)
			t.gt(rp["harvested"], 900, "%s: P%d harvested" % [tag, pid])
			t.ge(rp["structures_built"], 3, "%s: P%d structures placed" % [tag, pid])
			t.ge(rp["built"], 5, "%s: P%d units produced" % [tag, pid])


func test_eight_player_free_for_all(t: TestCtx) -> void:
	var ros: PackedStringArray = PackedStringArray()
	for code: String in ["napc", "nec", "ae", "def", "han", "olm", "pd", "sap"]:
		ros.append("roster.%s.vanilla" % code)
	var o: Dictionary = {"family": 0, "size": 192, "seed": 5, "rosters": ros, "opts": {"invariants_every": 300}, "bot_opts": {"first_attack_tick": 1800, "wave_size": 6}}
	var r: Dictionary = run_match(o, 3000)
	var w: SimWorld = (r["match"] as Dictionary)["world"]
	t.eq(r["errors"], PackedStringArray(), "8 players on 192x192: no errors")
	t.note("8-player FFA: %.3f ms/tick, worst %.2f ms" % [r["ms_avg"], r["ms_max"]])
	for pid: int in 8:
		var rp: Dictionary = SimMatchKit.report(w, pid)
		t.gt(rp["harvested"], 1000, "P%d harvested" % pid)
		t.ge(rp["structures_built"], 3, "P%d structures placed" % pid)
		t.ge(rp["built"], 4, "P%d units produced" % pid)


## The lockstep contract: the recorded command stream ALONE (no bots, no read queries) reproduces the whole match,
## checkpoint for checkpoint, including through the flat int form a replay file / the network would carry.
func test_replay_from_the_command_log(t: TestCtx) -> void:
	var o: Dictionary = {"family": 0, "size": 96, "seed": 2, "rosters": ROSTERS, "bot_opts": {"first_attack_tick": 2400, "wave_size": 6}}
	var m: Dictionary = SimMatchKit.make_match(o)
	var w: SimWorld = m["world"]
	SimMatchKit.run(m, 6000)
	var rec: SimCommandLog = m["log"]
	rec.finish(w)
	t.gt(rec.cmds.size(), 40, "the bots issued commands (%d)" % rec.cmds.size())
	var log2: SimCommandLog = SimCommandLog.from_ints(rec.to_ints())
	if not t.not_null(log2, "flat form round-trips"):
		return
	log2.checkpoints = rec.checkpoints
	var fresh: SimWorld = SimMatchKit.make_world(o)
	var res: Dictionary = log2.play(fresh, 6000)
	t.check(res["ok"], "replay matches every checkpoint (first mismatch %d)" % res["mismatch_tick"])
	t.eq(res["final"], w.checksum(), "final checksum of the replay")
	t.eq(fresh.events.digest(), w.events.digest(), "event digest of the replay")


func test_match_with_fog_of_war(t: TestCtx) -> void:
	var o: Dictionary = {"family": 0, "size": 96, "seed": 1, "rosters": ROSTERS, "rules": {"fog": true}, "opts": {"invariants_every": 300},
		"bot_opts": {"first_attack_tick": 2400, "wave_size": 5, "wave_growth_ticks": 1000000}}
	var r: Dictionary = run_match(o, 9000)
	var w: SimWorld = (r["match"] as Dictionary)["world"]
	t.eq(r["errors"], PackedStringArray(), "fog on: no errors")
	for pid: int in 2:
		var rp: Dictionary = SimMatchKit.report(w, pid)
		t.gt(rp["harvested"], 3000, "P%d harvested under fog" % pid)
		t.ge(rp["built"], 8, "P%d produced units under fog" % pid)
	var seen: int = 0
	for b: SimBot in (r["match"] as Dictionary)["bots"]:
		seen += b.known_structures()
	t.gt(seen, 0, "at least one bot discovered an enemy structure through the fog")


func test_research_and_a_laboratory(t: TestCtx) -> void:
	var lad: PackedStringArray = ["power", "refinery", "barracks", "factory", "tech", "tech", "power"]
	var o: Dictionary = {"seed": 1, "credits": 30000, "rules": {"unit_cap": 300}, "opts": {"invariants_every": 300},
		"bot_opts": {"ladder": lad, "research": true, "first_attack_tick": 100000}}
	var r: Dictionary = run_match(o, 9000)
	var w: SimWorld = (r["match"] as Dictionary)["world"]
	t.eq(r["errors"], PackedStringArray(), "no errors")
	for pid: int in 2:
		var pe: SimPlayerEcon = w.players[pid].econ
		var n: int = 0
		for i: int in pe.researched.size():
			n += pe.researched[i]
		t.ge(n, 2, "P%d completed research" % pid)
		t.gt(pe.stat_spent_research, 1000, "P%d paid for research" % pid)
