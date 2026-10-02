extends RefCounted
## AiFactory / AiThinker contract with net (ai.md 3.2, 10.1 test_ai_thinker) and the takeover bootstrap.


func test_factory_contract(t: TestCtx) -> void:
	t.eq(AiFactory.level_count(), 4)
	t.eq(AiFactory.style_count(), 4)
	t.eq(AiFactory.level_names().size(), AiFactory.level_count())
	t.eq(AiFactory.style_names().size(), AiFactory.style_count())
	t.eq(AiFactory.level_names()[3], "ai.level.brutal")
	t.eq(AiFactory.style_names()[0], "ai.style.doctrine")
	t.eq([AiFactory.level_handicap_pct(0), AiFactory.level_handicap_pct(1), AiFactory.level_handicap_pct(2), AiFactory.level_handicap_pct(3)], [100, 100, 100, 120] as Array)
	t.eq(AiFactory.takeover_level(), 1)
	var f: AiFactory = AiFactory.new()
	var thinker_call: Callable = f.make(2, 1, 0, 99)
	t.check(thinker_call.is_valid(), "make returns a valid Callable")
	t.not_null(f.thinker(2))
	t.eq(f.thinker(2).cfg.wu_share, AiTypes.GLOBAL_WU_PER_TICK, "one AI gets the whole governor budget")
	for pid: int in [3, 4, 5, 6, 7, 0, 1]:
		f.make(pid, 3, 0, 100 + pid)
	t.eq(f.thinker(2).cfg.wu_share, 300, "8 AIs => 300 wu/tick each")
	f.release(2)
	t.is_null(f.thinker(2))
	t.eq(f.live_count(), 7)
	t.check(f.debug_frame(3) == null, "no debug frame below debug level 2")
	t.check(f.state_hash() != 0)


func test_second_think_in_the_same_tick_is_harmless(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 3, "bots": false})
	var w: SimWorld = m["world"]
	var f: AiFactory = AiFactory.new()
	var thinker_call: Callable = f.make(0, 2, 0, 5)
	var out: Array = []
	thinker_call.call(w, out)
	t.check(f.thinker(0).controller.is_ready(), "the first think bootstraps")
	var out2: Array = []
	thinker_call.call(w, out2)
	t.eq(out2.size(), 0, "dt 0 does nothing")
	t.eq(f.thinker(0).thinks, 1)
	w.run(10)
	var out3: Array = []
	thinker_call.call(w, out3)
	t.eq(f.thinker(0).thinks, 2)
	for c: Variant in out + out3:
		var cmd: PackedInt32Array = c
		t.check(cmd.size() >= 1 and cmd.size() <= 1024 and cmd[0] <= 255, "sanitiser-clean command")


func test_takeover_bootstraps_from_a_running_match(t: TestCtx) -> void:
	# player 0 is played by a scripted bot for 600 ticks, then the AI takes the slot over (dropped human)
	var m: Dictionary = SimMatchKit.make_match({"seed": 4, "rules": {"fog": true, "victory": 0}})
	var w: SimWorld = m["world"]
	var bots: Array = m["bots"]
	for _i: int in 600:
		for b: SimBot in bots:
			b.think(w)
		w.step()
	var f: AiFactory = AiFactory.new()
	var thinker_call: Callable = f.make(0, AiFactory.takeover_level(), 0, AiRng.thinker_seed(1, 0))
	var out: Array = []
	thinker_call.call(w, out)
	var c: AiController = f.thinker(0).controller
	t.check(c.is_ready())
	t.eq(c.ctx.kb.own.count, w.own_ids(0).size(), "the own table reflects the running match")
	t.gt(c.ctx.kb.own.count, 1, "structures and units were already there")
	t.eq(out.size(), 0, "no module registered => no commands, but the knowledge is built")
	t.gt(c.ctx.kb.sites.count, 0, "resource sites known")
	# keep stepping: the tables track the sim without any events
	for _i: int in 300:
		for b: SimBot in bots:
			b.think(w)
		w.step()
		if w.tick % 10 == 0:
			thinker_call.call(w, out)
	t.eq(c.ctx.kb.own.count, w.own_ids(0).size(), "still in sync 300 ticks later")


func test_two_thinkers_do_not_share_threat_state(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 3, "bots": false})
	var w: SimWorld = m["world"]
	var f: AiFactory = AiFactory.new()
	var c0: Callable = f.make(0, 2, 0, 1)
	var c1: Callable = f.make(1, 2, 0, 2)
	var out: Array = []
	c0.call(w, out)
	c1.call(w, out)
	var k0: AiKnowledge = f.thinker(0).controller.ctx.kb
	var k1: AiKnowledge = f.thinker(1).controller.ctx.kb
	t.check(k0.route.threat == k0.threat, "each AI routes over its own threat map")
	t.check(k1.route.threat == k1.threat)
	t.check(k0.threat != k1.threat)
	t.check(f.shared.route != k0.route, "a forked handle on the shared grids")
	t.eq(k0.route.bw, k1.route.bw)
	t.ne(f.thinker(0).controller.ctx.rng.state(), f.thinker(1).controller.ctx.rng.state(), "private seeded RNGs")


func test_every_roster_bootstraps_and_thinks(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("%s: %s" % [tag, msg])
	for rid: String in d.roster_ids():
		var m: Dictionary = SimMatchKit.make_match({"seed": 2, "bots": false, "rosters": PackedStringArray([rid, "roster.def.vanilla"])})
		var w: SimWorld = m["world"]
		var f: AiFactory = AiFactory.new()
		var thinker_call: Callable = f.make(0, AiTypes.Difficulty.MEDIUM, 0, 42)
		var out: Array = []
		for _i: int in 12:
			thinker_call.call(w, out)
			w.run(4)
		var c: AiController = f.thinker(0).controller
		if not t.check(c.is_ready(), "%s bootstrapped" % rid):
			continue
		t.eq(c.ctx.res.missing_roles, PackedInt32Array(), "%s roles" % rid)
		t.check(c.ctx.store.has_personality(rid), "%s personality" % rid)
		t.eq(c.ctx.kb.own.count, w.own_ids(0).size(), "%s own table" % rid)
	Log.sink = old_sink
	t.eq(errors, PackedStringArray(), "no warnings or errors while bootstrapping 32 rosters")
