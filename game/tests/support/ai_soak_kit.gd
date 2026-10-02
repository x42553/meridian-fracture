class_name AiSoakKit
extends RefCounted
## AI-vs-AI match harness (ai.md 10.3, lean): a REAL SimMatchKit match (real data, generated map, every real system) in which
## every player is driven by a full AiBrain-equipped AiController through AiFactory / AiThinker with the production think cadence
## (level periods in 2-tick turns, sanitised commands, submit_raw). An observer samples the public read API and the telemetry
## sink; nothing here steers the AIs.
##   var m: Dictionary = AiSoakKit.make({"seed": 3, "rosters": [...], "levels": [1, 1], "family": 0, "fog": true})
##   var r: Dictionary = AiSoakKit.play(m, 24000)     # runs until elimination / cap; returns the result record (JSON-able)
## make options: everything SimMatchKit.make_match takes (bots is forced off) plus pers_over (pid -> {personality field: int}), tuning (dotted path -> value overrides), levels (Array per pid or one int, default
## MEDIUM), styles (same), fog (bool, default true), credits (7500), ai_seed (777), size (96), unit_cap (150).

const PERIOD_TURNS: PackedInt32Array = [5, 3, 2, 1]  ## think period in 2-tick turns per difficulty level
const SAMPLE: int = 100  ## ticks between metric samples
const IDLE_FROM: int = 60 * 20
const IDLE_TO: int = 900 * 20
const FIRST_KEYS: Dictionary = {
	"scout": AiTypes.Tele.FIRST_SCOUT_SENT, "barracks": AiTypes.Tele.FIRST_BARRACKS, "factory": AiTypes.Tele.FIRST_FACTORY,
	"radar": AiTypes.Tele.FIRST_RADAR, "lab": AiTypes.Tele.FIRST_LAB, "tank": AiTypes.Tele.FIRST_TANK, "aa": AiTypes.Tele.FIRST_AA,
	"opener_done": AiTypes.Tele.OPENER_DONE, "attack": AiTypes.Tele.ATTACK_LAUNCHED, "contact": AiTypes.Tele.ATTACK_CONTACT,
	"defend": AiTypes.Tele.DEFEND_STARTED, "expansion": AiTypes.Tele.EXPANSION_DEPLOYED,
}


static func make(o: Dictionary) -> Dictionary:
	var opts: Dictionary = o.duplicate()
	opts["bots"] = false
	var rules: Dictionary = (opts.get("rules", {}) as Dictionary).duplicate()
	rules["fog"] = bool(o.get("fog", true))
	if o.has("unit_cap"):
		rules["unit_cap"] = int(o["unit_cap"])
	opts["rules"] = rules
	var levels: Variant = o.get("levels", AiTypes.Difficulty.MEDIUM)
	var n: int = (o.get("rosters", SimMatchKit.DEFAULT_ROSTERS) as PackedStringArray).size()
	var hc: PackedInt32Array = PackedInt32Array()
	for pid: int in n:
		var lv0: int = int(levels[pid]) if levels is Array else int(levels)
		hc.append(AiFactory.level_handicap_pct(lv0))
	if not opts.has("handicaps"):
		opts["handicaps"] = hc
	var m: Dictionary = SimMatchKit.make_match(opts)
	var events: Array = []
	var sink: Callable = func(pid2: int, code: int, a: int, b: int, tick: int) -> void:
		events.append([pid2, code, a, b, tick])
	var factory: AiFactory = AiFactory.new(null, sink)
	factory.perf = true
	factory.tuning_override = (o.get("tuning", {}) as Dictionary).duplicate()
	factory.personality_overrides = (o.get("pers_over", {}) as Dictionary).duplicate(true)
	var styles: Variant = o.get("styles", 0)
	var calls: Dictionary = {}
	var brains: Dictionary = {}
	var lv_of: Dictionary = {}
	for s: SimPlayerSlot in (m["config"] as SimMatchConfig).players:
		var lv: int = int(levels[s.pid]) if levels is Array else int(levels)
		var st: int = int(styles[s.pid]) if styles is Array else int(styles)
		lv_of[s.pid] = lv
		calls[s.pid] = factory.make(s.pid, lv, st, AiRng.thinker_seed(int(o.get("ai_seed", 777)), s.pid))
		brains[s.pid] = AiBrain.install(factory.thinker(s.pid).controller)
	m["factory"] = factory
	m["calls"] = calls
	m["brains"] = brains
	m["levels"] = lv_of
	m["events"] = events
	m["samples"] = {}
	m["ticks_run"] = 0
	m["family"] = int(o.get("family", 0))
	m["seed"] = int(o.get("seed", 1))
	m["errors"] = PackedStringArray()
	m["rejected"] = {}
	m["slow"] = []
	m["idle"] = {}
	return m


## Frees a finished match: releases every brain (ctx.brain -> module -> ctx is a reference cycle, see AiFactory.release) and empties the record,
## so a process that ends right after (xplat scenarios, soaks) exits without the "resources still in use at exit" engine error.
static func dispose(m: Dictionary) -> void:
	var f: AiFactory = m.get("factory") as AiFactory
	if f != null:
		for pid: int in (m.get("brains", {}) as Dictionary).keys():
			f.release(pid)
	m.clear()


## One tick of the loop: the AIs that are due think (every 2 ticks, staggered by pid), then the world steps.
static func step_once(m: Dictionary, on_tick: Callable = Callable()) -> void:
	var w: SimWorld = m["world"]
	var calls: Dictionary = m["calls"]
	var levels: Dictionary = m["levels"]
	if on_tick.is_valid():
		on_tick.call(w, w.tick)
	if w.tick % 2 == 0:
		for pid: int in calls:
			if (w.tick / 2 + pid) % PERIOD_TURNS[int(levels[pid])] != 0:
				continue
			var out: Array = []
			var t0: int = Time.get_ticks_usec()
			(calls[pid] as Callable).call(w, out)
			var us: int = Time.get_ticks_usec() - t0
			if us > 12000:
				var slow: Array = m["slow"]
				if slow.size() < 8:
					var c: AiController = (m["factory"] as AiFactory).thinker(pid).controller
					slow.append({"pid": pid, "tick": w.tick, "us": us, "slot_wu": Array(c.scheduler.last_wu), "wu": c.last_wu})
			for c: Variant in out:
				var cmd: PackedInt32Array = c
				if cmd.size() < 1 or cmd.size() > 1024 or cmd[0] < 0 or cmd[0] > 255:
					continue
				w.submit_raw(pid, cmd)
	w.step()
	m["ticks_run"] = int(m["ticks_run"]) + 1


## Plays until the match ends or `max_ticks` passed; returns the result record.
static func play(m: Dictionary, max_ticks: int, on_sample: Callable = Callable()) -> Dictionary:
	var w: SimWorld = m["world"]
	var errors: PackedStringArray = m["errors"]
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("[%d] %s: %s (tick %d)" % [lv, tag, msg, w.tick])
	var t0: int = Time.get_ticks_usec()
	var start_tick: int = w.tick
	while w.tick - start_tick < max_ticks and w.match_state == SimWorld.MATCH_RUNNING:
		step_once(m)
		if w.tick % SAMPLE == 0:
			_sample(m)
			if on_sample.is_valid():
				on_sample.call(m)
	Log.sink = old_sink
	m["wall_ms"] = (Time.get_ticks_usec() - t0) / 1000
	return result(m)


# ------------------------------------------------------------------------------------------------ sampling
static func _sample(m: Dictionary) -> void:
	var w: SimWorld = m["world"]
	var samples: Dictionary = m["samples"]
	var brains: Dictionary = m["brains"]
	var factory: AiFactory = m["factory"]
	var dmg_total: int = 0
	for pid0: int in brains:
		var rp0: Dictionary = SimMatchKit.report(w, pid0)
		dmg_total += int(rp0["killed"]) + int(rp0["structures_lost"]) + int(rp0["lost"])
	if dmg_total != int(m.get("dmg_total", -1)):
		m["dmg_total"] = dmg_total
		if dmg_total > 0:
			m["dmg_last"] = w.tick
	# the stalemate gap only counts once the first blood is drawn
	if int(m.get("dmg_last", -1)) >= 0:
		m["stall_gap"] = maxi(int(m.get("stall_gap", 0)), w.tick - int(m["dmg_last"]))
	for pid: int in brains:
		var rec: Dictionary = samples.get(pid, {"t": [], "harv": [], "army": [], "cred": [], "structs": [], "units": [], "idle_prod": 0, "prod_n": 0, "idle_con": 0, "con_n": 0})
		var rp: Dictionary = SimMatchKit.report(w, pid)
		(rec["t"] as Array).append(w.tick)
		(rec["harv"] as Array).append(int(rp["harvested"]))
		(rec["cred"] as Array).append(int(rp["credits"]))
		(rec["structs"] as Array).append(int(rp["structures"]))
		(rec["units"] as Array).append(int(rp["combat_units"]))
		var ctrl: AiController = factory.thinker(pid).controller
		var eco: AiEconomy = (brains[pid] as AiBrain).eco()
		(rec["army"] as Array).append(eco.army_value)
		if w.tick >= IDLE_FROM and w.tick <= IDLE_TO and ctrl.booted and int(rp["eliminated"]) == 0:
			for i: int in eco.prod_eid.size():
				if eco.prod_kind[i] == AiTypes.StructKind.BARRACKS or eco.prod_kind[i] == AiTypes.StructKind.FACTORY:
					rec["prod_n"] = int(rec["prod_n"]) + 1
					if eco.prod_qlen[i] == 0 and int(rp["credits"]) >= 500:
						rec["idle_prod"] = int(rec["idle_prod"]) + 1
			var cs: PackedInt32Array = PackedInt32Array()
			ctrl.ctx.view.construction_state(cs)
			rec["con_n"] = int(rec["con_n"]) + 1
			if cs.size() > 0 and cs[0] == 0 and int(rp["credits"]) >= 500 and not eco.wants.is_empty():
				rec["idle_con"] = int(rec["idle_con"]) + 1
		samples[pid] = rec


static func _score(w: SimWorld, pid: int, income_last_min: int) -> int:
	var sv: int = 0
	for s: SimEntity in w.structures_of(pid):
		if (s.flags & SimFlags.F_GONE) == 0:
			sv += w.data.structures[s.def_idx].cost
	var av: int = 0
	for u: SimEntity in w.units_of(pid):
		if (u.flags & SimFlags.F_GONE) == 0:
			av += u.paid_cost
	return (sv * 5 + av * 3 + income_last_min * 10) / 10


## The result record (plain Dictionary / Array / int / String / float values only, JSON-able).
static func result(m: Dictionary) -> Dictionary:
	var w: SimWorld = m["world"]
	var cfg: SimMatchConfig = m["config"]
	var factory: AiFactory = m["factory"]
	var brains: Dictionary = m["brains"]
	var samples: Dictionary = m["samples"]
	var ended: bool = w.match_state != SimWorld.MATCH_RUNNING
	var players: Array = []
	var alive: Array = []
	var scores: Dictionary = {}
	for s: SimPlayerSlot in cfg.players:
		var pid: int = s.pid
		var rp: Dictionary = SimMatchKit.report(w, pid)
		var th: AiThinker = factory.thinker(pid)
		var ctrl: AiController = th.controller
		var brain: AiBrain = brains[pid]
		var rec: Dictionary = samples.get(pid, {})
		var first: Dictionary = {}
		for k: String in FIRST_KEYS:
			var code: int = int(FIRST_KEYS[k])
			if ctrl.ctx.telemetry.first_tick.has(code):
				first[k] = int(ctrl.ctx.telemetry.first_tick[code])
		var harv: Array = rec.get("harv", [])
		var per_min: Array = []
		var tt: Array = rec.get("t", [])
		var last_mark: int = 0
		var last_val: int = 0
		for i: int in tt.size():
			if int(tt[i]) - last_mark >= 1200:
				per_min.append(int(harv[i]) - last_val)
				last_val = int(harv[i])
				last_mark = int(tt[i])
		var income_last: int = 0
		if harv.size() >= 13:
			income_last = int(harv[harv.size() - 1]) - int(harv[harv.size() - 13])
		var stalls: Dictionary = {}
		var telem_counts: Dictionary = ctrl.ctx.telemetry.counts
		for ev: Variant in (m["events"] as Array):
			var e: Array = ev
			if int(e[0]) == pid and int(e[1]) == AiTypes.Tele.STALL:
				stalls[str(e[2])] = int(stalls.get(str(e[2]), 0)) + 1
		var st_cmds: int = w.players[pid].st_cmds
		var st_rej: int = w.players[pid].st_rejected
		var alive_p: bool = int(rp["eliminated"]) == 0
		if alive_p:
			alive.append(pid)
		scores[pid] = _score(w, pid, income_last)
		players.append({
			"pid": pid, "roster": s.roster, "level": int(m["levels"][pid]), "eliminated": int(rp["eliminated"]), "first": first,
			"income_per_min": per_min, "army_curve": rec.get("army", []), "credits": int(rp["credits"]), "harvested": int(rp["harvested"]),
			"built": int(rp["built"]), "lost": int(rp["lost"]), "killed": int(rp["killed"]), "structures": int(rp["structures"]),
			"structures_lost": int(rp["structures_lost"]), "collectors": int(rp["collectors"]), "combat_units": int(rp["combat_units"]),
			"idle_production": float(int(rec.get("idle_prod", 0))) / float(maxi(int(rec.get("prod_n", 0)), 1)),
			"idle_construction": float(int(rec.get("idle_con", 0))) / float(maxi(int(rec.get("con_n", 0)), 1)),
			"stalls": stalls, "brain": brain.summary(), "cmds": ctrl.ctx.cmd.stats(), "st_cmds": st_cmds, "st_rejected": st_rej,
			"ai_us_avg": ctrl.perf.total_us / maxi(ctrl.total_ticks, 1), "ai_us_worst_think": ctrl.perf.worst_us,
			"wu_avg": ctrl.total_wu / maxi(ctrl.total_ticks, 1), "telemetry": telem_counts.size(), "score": scores[pid],
			"ai_hash": th.state_hash(),
		})
	var winner: int = -1
	var how: String = "timeout"
	if ended and alive.size() == 1:
		winner = alive[0]
		how = "elimination"
	elif ended:
		how = "ended"
	if winner < 0 and cfg.players.size() == 2:
		var a: int = int(scores[0])
		var b: int = int(scores[1])
		if a * 100 >= b * 125:
			winner = 0
		elif b * 100 >= a * 125:
			winner = 1
	return {
		"rosters": Array((cfg.players.map(func(s: SimPlayerSlot) -> String: return s.roster))), "family": int(m.get("family", 0)),
		"ticks": w.tick, "how": how, "winner": winner, "adjudicated": how != "elimination" and winner >= 0,
		"players": players, "errors": Array(m["errors"]), "error_count": (m["errors"] as PackedStringArray).size(),
		"stalemate_gap": int(m.get("stall_gap", 0)), "slow_thinks": m["slow"], "wall_ms": int(m.get("wall_ms", 0)), "checksum": w.checksum(), "ai_hash": factory.state_hash(),
		"ms_per_tick": float(int(m.get("wall_ms", 0))) / float(maxi(w.tick, 1)),
	}
