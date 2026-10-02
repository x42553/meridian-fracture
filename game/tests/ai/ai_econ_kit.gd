class_name AiEconKit
extends RefCounted
## AI-04/05 match harness: a REAL SimMatchKit match (real data, generated map, every real system) in which each player is driven
## by an AiController with the AiEconomy module set installed. A tiny test-only `Waves` module (OPS slot) sends the reserve
## squad at the enemy every `every` ticks, so the economies get attacked and have to cope. Only public AI APIs are used.
##   var m: Dictionary = AiEconKit.make({"seed": 3, "rosters": [...], "credits": 7500, "level": 2, "fog": false})
##   var r: Dictionary = AiEconKit.run(m, 6000)     # {ticks, ai_us_per_tick, errors, checksum, ...}
## Options: everything of SimMatchKit.make_match (bots is forced off) plus level (int or Array per pid, default HARD), fog (bool),
## waves (bool, default true), first_wave (3600), wave_every (1200), on_think (Callable(pid, ctrl, eco, tick)).

const PERIOD_TURNS: PackedInt32Array = [5, 3, 2, 1]  ## think period in 2-tick turns per difficulty level


class Waves extends RefCounted:
	var first_tick: int = 3600
	var every: int = 1200
	var min_units: int = 6
	var waves: int = 0
	var _last: int = -100000
	var _hub: WeakRef = null

	func setup(_ctx: AiContext) -> void:
		pass

	func step(ctx: AiContext, budget: AiBudget) -> void:
		var eco: AiEconomy = _hub.get_ref()
		if eco == null or ctx.tick < first_tick or ctx.tick - _last < every or not budget.spend(10):
			return
		var hq: PackedInt32Array = PackedInt32Array()
		if not (ctx.kb.primary >= 0 and ctx.kb.enemy_hq(ctx.kb.primary, hq)):
			if ctx.kb.enemy_starts.size() < 2:
				return
			hq = PackedInt32Array([ctx.kb.enemy_starts[0] * Fp.CELL + Fp.CELL / 2, ctx.kb.enemy_starts[1] * Fp.CELL + Fp.CELL / 2])
		if eco.squads.reserve.units.size() >= min_units:
			var sq: AiSquad = eco.squads.create(AiTypes.SquadKind.MAIN, -1)
			eco.squads.claim(0, 999, ctx.kb.sites.home_x, ctx.kb.sites.home_y, 0, 100, sq)
		_last = ctx.tick
		for id: int in eco.squads.squads:
			var s: AiSquad = eco.squads.squads[id]
			if s.kind == AiTypes.SquadKind.MAIN and not s.units.is_empty():
				ctx.cmd.attack_move(s.units, hq[0], hq[1])
				waves += 1

	func state_hash() -> int:
		return waves


static func make(o: Dictionary) -> Dictionary:
	var opts: Dictionary = o.duplicate()
	opts["bots"] = false
	var rules: Dictionary = (opts.get("rules", {}) as Dictionary).duplicate()
	if o.has("fog"):
		rules["fog"] = bool(o["fog"])
	opts["rules"] = rules
	var m: Dictionary = SimMatchKit.make_match(opts)
	var factory: AiFactory = AiFactory.new()
	factory.perf = true
	factory.install_brain = false  # this kit plugs the economy modules in by hand
	var levels: Variant = o.get("level", AiTypes.Difficulty.HARD)
	var calls: Dictionary = {}
	var ecos: Dictionary = {}
	var waves: Dictionary = {}
	var lv_of: Dictionary = {}
	for s: SimPlayerSlot in (m["config"] as SimMatchConfig).players:
		var lv: int = int(levels[s.pid]) if levels is Array else int(levels)
		lv_of[s.pid] = lv
		calls[s.pid] = factory.make(s.pid, lv, 0, AiRng.thinker_seed(int(o.get("ai_seed", 777)), s.pid))
		var ctrl: AiController = factory.thinker(s.pid).controller
		var eco: AiEconomy = AiEconomy.install(ctrl)
		ecos[s.pid] = eco
		if bool(o.get("waves", true)):
			var wv: Waves = Waves.new()
			wv.first_tick = int(o.get("first_wave", 3600))
			wv.every = int(o.get("wave_every", 1200))
			wv._hub = weakref(eco)
			ctrl.register(AiScheduler.Slot.OPS, wv)
			waves[s.pid] = wv
	m["factory"] = factory
	m["calls"] = calls
	m["ecos"] = ecos
	m["waves"] = waves
	m["levels"] = lv_of
	m["ai_us"] = 0
	m["ai_worst_us"] = 0
	m["emitted"] = 0
	m["ticks_run"] = 0
	return m


## Steps `ticks` ticks with every AI thinking on its own period. `on_tick` (Callable(world, tick)) runs before the AIs.
static func run(m: Dictionary, ticks: int, on_tick: Callable = Callable(), on_think: Callable = Callable()) -> Dictionary:
	var w: SimWorld = m["world"]
	var calls: Dictionary = m["calls"]
	var levels: Dictionary = m["levels"]
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("[%d] %s: %s (tick %d)" % [lv, tag, msg, w.tick])
	var us_total: int = 0
	var us_worst: int = 0
	var bad: int = 0
	var emitted: int = 0
	var t_all0: int = Time.get_ticks_usec()
	var done: int = 0
	for _i: int in ticks:
		if w.match_state != SimWorld.MATCH_RUNNING:
			break
		if on_tick.is_valid():
			on_tick.call(w, w.tick)
		if w.tick % 2 == 0:
			for pid: int in calls:
				if (w.tick / 2 + pid) % PERIOD_TURNS[int(levels[pid])] != 0:
					continue
				var out: Array = []
				var t0: int = Time.get_ticks_usec()
				(calls[pid] as Callable).call(w, out)
				var dt: int = Time.get_ticks_usec() - t0
				us_total += dt
				us_worst = maxi(us_worst, dt)
				for c: Variant in out:
					var cmd: PackedInt32Array = c
					if cmd.size() < 1 or cmd.size() > 1024 or cmd[0] < 0 or cmd[0] > 255:
						bad += 1
						continue
					emitted += 1
					w.submit_raw(pid, cmd)
				if on_think.is_valid():
					on_think.call(pid, w.tick)
		w.step()
		done += 1
	Log.sink = old_sink
	var total_us: int = Time.get_ticks_usec() - t_all0
	m["ai_us"] = int(m["ai_us"]) + us_total
	m["ai_worst_us"] = maxi(int(m["ai_worst_us"]), us_worst)
	m["emitted"] = int(m["emitted"]) + emitted
	m["ticks_run"] = int(m["ticks_run"]) + done
	return {
		"ticks": done, "errors": errors, "bad": bad, "emitted": emitted, "checksum": w.checksum(),
		"ai_us_per_tick": us_total / maxi(done, 1), "ai_worst_us": us_worst, "ms_per_tick": float(total_us) / 1000.0 / float(maxi(done, 1)),
	}


static func ctx_of(m: Dictionary, pid: int) -> AiContext:
	return (m["factory"] as AiFactory).thinker(pid).controller.ctx


static func eco_of(m: Dictionary, pid: int) -> AiEconomy:
	return (m["ecos"] as Dictionary)[pid]


## One-line summary of a player's economy for debugging and notes.
static func summary(m: Dictionary, pid: int) -> String:
	var eco: AiEconomy = (m["ecos"] as Dictionary)[pid]
	var rep: Dictionary = SimMatchKit.report(m["world"] as SimWorld, pid)
	var ctx: AiContext = (m["factory"] as AiFactory).thinker(pid).controller.ctx
	var kinds: Dictionary = {}
	for sd: int in eco.struct_own.size():
		if eco.struct_own[sd] > 0:
			var nm: String = AiTypes.StructKind.keys()[ctx.res.kind_of_structure(sd)]
			kinds[nm] = int(kinds.get(nm, 0)) + eco.struct_own[sd]
	var ws: PackedStringArray = PackedStringArray()
	for wt: AiWant in eco.wants:
		ws.append("%s/%d/p%d/o%d/s%d" % [("S" if wt.kind == 0 else "U"), wt.def, wt.prio, wt.origin, wt.state])
	return "%s | %s | %s" % [_line(m, pid, eco, rep), str(kinds), " ".join(ws)]


static func _line(m: Dictionary, pid: int, eco: AiEconomy, rep: Dictionary) -> String:
	var w: SimWorld = m["world"]
	return "p%d t=%d cred=%d harv=%d refs=%d/%d col=%d(+%d)/%d units=%d army=%d structs=%d power=%s spent=%s wants=%d phase=%d cancels=%d" % [
		pid, w.tick, rep["credits"], rep["harvested"], eco.refineries_active, eco.refineries_total, eco.collectors_alive,
		eco.collectors_queued, eco.collector_target, rep["units"], eco.army_units, rep["structures"], str(rep["power"]),
		str(eco.spent), eco.wants.size(), eco.comp.phase, eco.cancels]
