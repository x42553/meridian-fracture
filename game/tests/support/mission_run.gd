class_name MissionRun
extends RefCounted
## MIS3 mission harness: plays a shipped mission through the REAL sim (MissionKit.world = SimMissionSetup -> MapGenerator ->
## SimMatchSetup.create_world), the AI players with the production AI (AiFactory / AiThinker, production think cadence, commands sanitised and
## submitted with submit_raw like the lockstep host does) and the HUMAN slot with one of three drivers:
##   "ai"    the full AI at `human_level` (default HARD) plays the human slot (the "scripted bot" of the acceptance test: it builds, expands
##           and attacks on its own; mission-specific help comes only from `assist` callables registered in ASSISTS)
##   "bot"   the scripted macro bot (MissionBot over SimBot, steered by MissionGoals) plays the human slot
##   "idle"  nobody commands the human slot (the mission must not be trivially won: it must be lost or stall)
##   "none"  like idle but the AI players are off too (pure script, used for trigger checks)
##   var m: Dictionary = MissionRun.make(d, "op_napc", {"driver": "ai", "ai_seed": 777, "sim_seed": 5})
##   var r: Dictionary = MissionRun.play(m, 20 * 60 * 20)      # {"outcome": "win"|"lose"|"timeout", "tick", "seconds", "objectives": {...}, ...}
## make options: driver, human_level (2), ai_seed (777), sim_seed (-1 = the mission's), human_pid (the mission's human slot), assist (Callable(world, tick, ctx)),
## ai_level_bonus (added to every AI player's level, 0), watch (Array of [kind, id] samples; unused).

const PERIOD_TURNS: PackedInt32Array = [5, 3, 2, 1]  ## think period in 2-tick turns per difficulty level (same as AiSoakKit)
const TPS: int = 20


static func make(d: GameData, id: String, o: Dictionary = {}) -> Dictionary:
	var cfg_d: Dictionary = SimMissionSetup.build_config(d, id)
	if cfg_d.is_empty():
		return {}
	if int(o.get("sim_seed", -1)) >= 0:
		cfg_d["seed"] = int(o["sim_seed"])
	var map: MapData = MissionKit.map_for(cfg_d, d)
	var cfg: SimMatchConfig = SimMatchConfig.from_dict(cfg_d)
	var w: SimWorld = SimMatchSetup.create_world(d, cfg, map, {"events": bool(o.get("events", true))})
	if w == null:
		return {}
	var driver: String = str(o.get("driver", "ai"))
	var human_level: int = int(o.get("human_level", AiTypes.Difficulty.HARD))
	var ai_seed: int = int(o.get("ai_seed", 777))
	var factory: AiFactory = AiFactory.new(null, Callable())
	var calls: Dictionary = {}
	var levels: Dictionary = {}
	var human_pid: int = -1
	var bot: MissionBot = null
	for pd: Variant in cfg_d["players"]:
		var pdict: Dictionary = pd as Dictionary
		var pid: int = int(pdict["pid"])
		var lv: int = 0
		var st: int = 0
		if str(pdict["kind"]) == "human":
			human_pid = pid
			if driver == "bot":
				var gc: Dictionary = MissionGoals.config(id)
				var bo: Dictionary = (gc["opts"] as Dictionary).duplicate()
				bo.merge((o.get("bot_opts", {}) as Dictionary), true)
				bot = MissionBot.new(pid, bo)
				bot.goals = (gc["goals"] as Array).duplicate(true)
				continue
			if driver != "ai":
				continue
			lv = human_level
		else:
			if driver == "none":
				continue
			var aid: Dictionary = pdict.get("ai", {}) as Dictionary
			lv = clampi(int(aid.get("level", 1)) + int(o.get("ai_level_bonus", 0)), 0, 3)
			st = int(aid.get("style", 0))
		levels[pid] = lv
		calls[pid] = factory.make(pid, lv, st, AiRng.thinker_seed(ai_seed, pid))
	return {"world": w, "config": cfg, "cfg_dict": cfg_d, "data": d, "map": map, "factory": factory, "calls": calls, "levels": levels,
		"human_pid": human_pid, "driver": driver, "label": str(o.get("label", driver)), "bot": bot, "assist": o.get("assist", Callable()), "ctx": {}, "id": id, "errors": PackedStringArray(),
		"samples": [], "ticks_run": 0}


static func dispose(m: Dictionary) -> void:
	var f: AiFactory = m.get("factory") as AiFactory
	if f != null:
		for pid: int in (m.get("calls", {}) as Dictionary).keys():
			f.release(pid)
	m.clear()


static func step_once(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	var calls: Dictionary = m["calls"]
	var levels: Dictionary = m["levels"]
	var assist: Callable = m["assist"]
	if assist.is_valid():
		assist.call(w, w.tick, m["ctx"])
	var bot: MissionBot = m.get("bot") as MissionBot
	if bot != null:
		bot.think(w)
	if w.tick % 2 == 0:
		for pid: int in calls:
			if (w.tick / 2 + pid) % PERIOD_TURNS[int(levels[pid])] != 0:
				continue
			var out: Array = []
			(calls[pid] as Callable).call(w, out)
			for c: Variant in out:
				var cmd: PackedInt32Array = c
				if cmd.size() < 1 or cmd.size() > 1024 or cmd[0] < 0 or cmd[0] > 255:
					continue
				w.submit_raw(pid, cmd)
	w.step()
	m["ticks_run"] = int(m["ticks_run"]) + 1


## Plays until the match ends or `max_ticks` passed. Samples the human's economy every 10 s.
static func play(m: Dictionary, max_ticks: int, on_sample: Callable = Callable()) -> Dictionary:
	var w: SimWorld = m["world"]
	var errors: PackedStringArray = m["errors"]
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("[%d] %s: %s (tick %d)" % [lv, tag, msg, w.tick])
	var t0: int = Time.get_ticks_usec()
	var start_tick: int = w.tick
	var hp: int = int(m["human_pid"])
	while w.tick - start_tick < max_ticks and w.match_state == SimWorld.MATCH_RUNNING:
		step_once(m)
		if w.tick % (10 * TPS) == 0:
			var rec: Dictionary = sample(w, hp)
			rec["t"] = w.tick / TPS
			(m["samples"] as Array).append(rec)
			if on_sample.is_valid():
				on_sample.call(m, rec)
	Log.sink = old_sink
	m["wall_ms"] = (Time.get_ticks_usec() - t0) / 1000
	return result(m)


static func sample(w: SimWorld, pid: int) -> Dictionary:
	var units: int = 0
	var combat: int = 0
	for e: SimEntity in w.units_of(pid):
		if (e.flags & SimFlags.F_GONE) == 0:
			units += 1
	var structs: int = 0
	for s: SimEntity in w.structures_of(pid):
		if (s.flags & SimFlags.F_GONE) == 0:
			structs += 1
	var enemy_structs: int = 0
	var enemy_units: int = 0
	for p: SimPlayer in w.players:
		if p.pid != pid and p.team != w.players[pid].team:
			for s2: SimEntity in w.structures_of(p.pid):
				if (s2.flags & SimFlags.F_GONE) == 0:
					enemy_structs += 1
			for u2: SimEntity in w.units_of(p.pid):
				if (u2.flags & SimFlags.F_GONE) == 0:
					enemy_units += 1
	return {"cred": w.players[pid].credits, "units": units, "combat": combat, "structs": structs, "e_structs": enemy_structs, "e_units": enemy_units}


static func objective_states(w: SimWorld) -> Dictionary:
	var out: Dictionary = {}
	var names: PackedStringArray = PackedStringArray(["hidden", "active", "completed", "failed"])
	for i: int in w.mission.def.objectives.size():
		var st: int = w.mission.obj_state[i]
		out[w.mission.def.objectives[i].id] = names[st] if st >= 0 and st < names.size() else str(st)
	return out


static func result(m: Dictionary) -> Dictionary:
	var w: SimWorld = m["world"]
	var outcome: String = "timeout"
	if w.match_state != SimWorld.MATCH_RUNNING:
		outcome = "win" if w.end_reason == SimWorld.EndReason.MISSION_WIN else ("lose" if w.end_reason == SimWorld.EndReason.MISSION_LOSE else "ended_%d" % w.end_reason)
	var fired: Dictionary = {}
	var fired_at: Dictionary = {}  ## trigger id -> seconds of its LAST firing
	for i: int in w.mission.def.triggers.size():
		if w.mission.trig_fired[i] > 0:
			fired[w.mission.def.triggers[i].id] = w.mission.trig_fired[i]
			fired_at[w.mission.def.triggers[i].id] = w.mission.trig_last_tick[i] / TPS
	return {"id": m["id"], "outcome": outcome, "tick": w.tick, "seconds": w.tick / TPS, "objectives": objective_states(w), "fired": fired, "fired_at": fired_at,
		"errors": Array(m["errors"]).slice(0, 6), "driver": m.get("label", m["driver"]), "wall_ms": int(m.get("wall_ms", 0)), "samples": (m["samples"] as Array).size()}
