extends RefCounted
## MIS3: the shipped missions (game/data/missions): the tutorial 'Field Training' and the eight faction operations. Fast structural smoke for every
## mission (loads through the real path, starts, first triggers fire, objectives, map quality, doctrine pieces) plus the tutorial played by a
## scripted player with real commands (no timeout needed). The slow acceptance runs (a scripted bot reaches the win, an idle player does not)
## are in test_mis3_completion.gd.

const TUTORIAL: String = "tut_field_training"
const OPS: PackedStringArray = ["op_napc", "op_nec", "op_olm", "op_def", "op_pd", "op_han", "op_ae", "op_sap"]
const FAMILIES: Dictionary = {"op_napc": 0, "op_nec": 1, "op_olm": 0, "op_def": 0, "op_pd": 2, "op_han": 0, "op_ae": 0, "op_sap": 2, "tut_field_training": 0}
const ROSTERS: Dictionary = {"op_napc": "roster.napc.vanilla", "op_nec": "roster.nec.vanilla", "op_olm": "roster.olm.vanilla", "op_def": "roster.def.vanilla",
	"op_pd": "roster.pd.vanilla", "op_han": "roster.han.vanilla", "op_ae": "roster.ae.vanilla", "op_sap": "roster.sap.vanilla", "tut_field_training": "roster.napc.vanilla"}


func _all() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray([TUTORIAL])
	out.append_array(OPS)
	return out


func test_all_nine_missions_are_shipped_in_order(t: TestCtx) -> void:
	var d: GameData = MissionKit.data()
	if d == null:
		t.fail("data does not load")
		return
	var ids: PackedStringArray = SimMissionSetup.ids_in_order(d)
	for id: String in _all():
		t.check(ids.has(id), "%s is listed in the manifest and loads" % id)
	var tab: DefMissionTable = DefMissionTable.of(d)
	t.eq(tab.get_mission(TUTORIAL).group, "tutorial")
	for i: int in OPS.size():
		var m: DefMission = tab.get_mission(OPS[i])
		t.eq(m.group, "operation", OPS[i])
		t.eq(m.order, i + 1, "%s menu order" % OPS[i])
		t.check(m.ui_title.begins_with("Operation "), "%s title" % OPS[i])
		t.check(m.ui_briefing.size() >= 3, "%s has a situation, an opponent and orders section" % OPS[i])
	# the 8 operations cover the 8 factions once each, and the human always plays the faction of its operation
	var seen: Dictionary = {}
	for id: String in _all():
		var m2: DefMission = tab.get_mission(id)
		for p: DefMissionPlayer in m2.players:
			if p.human:
				t.eq(p.roster, ROSTERS[id], "%s human roster" % id)
				seen[p.roster] = true
	t.eq(seen.size(), 8, "eight different faction rosters are played")


func test_every_mission_starts_and_its_first_triggers_fire(t: TestCtx) -> void:
	var d: GameData = MissionKit.data()
	for id: String in _all():
		var w: SimWorld = MissionKit.world(d, id, {"events": false})
		if not t.not_null(w, "%s: world" % id):
			continue
		var m: SimMissionSystem = w.mission
		t.check(m.def.objectives.size() >= 3, "%s objectives" % id)
		var primaries: int = 0
		var secondaries: int = 0
		for o: DefMissionObjective in m.def.objectives:
			if o.kind == DefMissionObjective.Kind.PRIMARY:
				primaries += 1
			elif o.kind == DefMissionObjective.Kind.SECONDARY:
				secondaries += 1
		if id != TUTORIAL:
			t.check(primaries >= 2 and primaries <= 3, "%s: 2-3 primary objectives (%d)" % [id, primaries])
			t.check(secondaries >= 1 and secondaries <= 2, "%s: 1-2 secondary objectives (%d)" % [id, secondaries])
		MissionKit.run(w, 12)
		var fired: int = 0
		for i: int in m.def.triggers.size():
			fired += m.trig_fired[i]
		t.gt(fired, 0, "%s: a trigger fires in the first ticks" % id)
		t.eq(w.match_state, SimWorld.MATCH_RUNNING, "%s keeps running" % id)
		var hq: int = 0
		for s: SimEntity in w.structures_of(0):
			if s.def_idx == w.players[0].roster.hq_idx:
				hq += 1
		t.eq(hq, 1, "%s: the player starts with a headquarters" % id)
		# every area lies on the map and is not empty
		for ai: int in m.def.areas.size():
			var c: int = m.area_center_cell(w, ai)
			t.check(c >= 0 and c < w.map.n, "%s: area %s resolves" % [id, m.def.areas[ai].id])


func test_map_quality_of_every_mission(t: TestCtx) -> void:
	var d: GameData = MissionKit.data()
	for id: String in _all():
		var cfg: Dictionary = SimMissionSetup.build_config(d, id)
		var mc: Dictionary = cfg["map"]
		var rep: Dictionary = MapGenerator.generate_report(mc)
		var m: MapData = rep["map"]
		t.eq(int(mc["family"]), int(FAMILIES[id]), "%s map family" % id)
		t.check(not bool(rep["template"]), "%s: the generator did not fall back to the safe template" % id)
		t.eq(int(rep["attempts"]), 1, "%s: valid on the first attempt" % id)
		t.eq(MapGenValidate.validate(m).size(), 0, "%s: validator clean (%s)" % [id, str(MapGenValidate.validate(m))])
		var met: Dictionary = MapGenValidate.metrics(m)
		for e: Variant in met["exits_per_start"]:
			t.ge(int(e), 2, "%s: every start has at least two exits" % id)
		t.le(int(met["fairness_spread_permille"]), 50, "%s: fair starts" % id)
		t.ge(int(met["route_pct"]), 50, "%s: routes" % id)
		if int(mc["family"]) == 2:
			for ds: Variant in met["dock_sites"]:
				t.gt(int(ds), 0, "%s: coast starts have dock sites" % id)


func test_scripted_data_shape_per_operation(t: TestCtx) -> void:
	var d: GameData = MissionKit.data()
	var tab: DefMissionTable = DefMissionTable.of(d)
	for id: String in OPS:
		var m: DefMission = tab.get_mission(id)
		# a defeat condition, a win, an AI opponent, scripted waves, a twist (trigger with a camera hint, reveal or music change), texts for debriefs
		var wins: int = 0
		var loses: int = 0
		var waves: int = 0
		for trg: DefMissionTrigger in m.triggers:
			for a: DefMissionAction in trg.then:
				if a.op == DefMissionAction.Op.WIN:
					wins += 1
				elif a.op == DefMissionAction.Op.LOSE:
					loses += 1
				elif a.op == DefMissionAction.Op.SPAWN_UNITS and a.wave >= 0:
					waves += 1
		t.ge(wins, 1, "%s has a win action" % id)
		t.ge(loses, 1, "%s has a defeat action" % id)
		t.ge(waves, 3, "%s has scripted waves" % id)
		var ai_players: int = 0
		for p: DefMissionPlayer in m.players:
			if not p.human:
				ai_players += 1
		t.ge(ai_players, 1, "%s has an AI opponent" % id)
		var debrief: int = 0
		for msg: DefMissionMessage in m.messages:
			if msg.ui_speaker == "Debrief":
				debrief += 1
		t.ge(debrief, 2, "%s has a victory and a defeat debrief" % id)
		var fault: bool = false
		for b: Dictionary in m.ui_briefing:
			if str(b.get("heading", "")) == "Orders":
				fault = true
		t.check(fault, "%s briefing has an Orders section" % id)


## The tutorial played with real commands by TutorialPlayer (and the real AI of the scripted rival, so its array can fire): every gate of the course
## opens by playing, in far less time than the timeouts allow.
func test_tutorial_is_passable_by_playing(t: TestCtx) -> void:
	var d: GameData = MissionKit.data()
	var p: TutorialPlayer = TutorialPlayer.new()
	var assist: Callable = func(w0: SimWorld, _tick: int, _ctx: Dictionary) -> void: p.act(w0)
	var run: Dictionary = MissionRun.make(d, TUTORIAL, {"driver": "idle", "assist": assist, "events": false})
	if run.is_empty():
		t.fail("tutorial world")
		return
	var r: Dictionary = MissionRun.play(run, 40 * 60 * MissionRun.TPS)
	var w: SimWorld = run["world"]
	t.eq(r["outcome"], "win", "the course ends in a win")
	t.lt(w.tick / 20, 16 * 60, "a quick player finishes in under 16 minutes (%d s)" % (w.tick / 20))
	t.eq((r["errors"] as Array).size(), 0, "no warnings or errors")
	var m: SimMissionSystem = w.mission
	# the gates that need an action of the player (not UI-only information steps) were passed by that action, not by their timeout
	var gated: PackedStringArray = ["t02", "t03", "t05", "t06", "t07", "t09", "t10", "t11", "t12", "t13", "t15", "t16", "t17", "t18", "t19", "t20"]
	for pre: String in gated:
		var gate: int = MissionKit.trig(w, pre + "b_gate")
		var to: int = MissionKit.trig(w, pre + "c_timeout")
		t.check(gate >= 0 and m.trig_fired[gate] == 1, "%s: the gate opened by playing" % pre)
		t.check(to < 0 or m.trig_fired[to] == 0, "%s: no timeout was needed" % pre)
	t.eq(m.trig_fired[MissionKit.trig(w, "t80_sw_fired")], 1, "the superweapon warning drill really happened (the rival's array fired)")
	MissionRun.dispose(run)


## Idle tutorial: still safe. Nothing makes the course unwinnable or soft-locks: every step has a timeout that helps.
func test_tutorial_timeouts_never_leave_a_step_open(t: TestCtx) -> void:
	var d: GameData = MissionKit.data()
	var m: DefMission = DefMissionTable.of(d).get_mission(TUTORIAL)
	var steps: int = 0
	for i: int in m.objectives.size():
		var oid: String = m.objectives[i].id
		if oid.begins_with("s") and oid.length() == 3:
			steps += 1
			var found: bool = false
			for trg: DefMissionTrigger in m.triggers:
				if trg.id.ends_with("c_timeout") and trg.id.begins_with("t%02d" % int(oid.substr(1))):
					found = true
			t.check(found, "%s has a timeout trigger" % oid)
	t.eq(steps, 21)
	t.ge(m.messages.size(), 21, "a hint per step")
