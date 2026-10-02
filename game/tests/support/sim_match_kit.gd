class_name SimMatchKit
extends RefCounted
## THE full-match harness (integration task INT1): the REAL GameData (all balance files), a REAL generated map
## (MapGenerator), the REAL SimWorld with every real system, each player's starting deployed HQ at its generated
## start cell with the bible preset credits (7500), and scripted SimBots (tests/support/sim_bot.gd) that play through
## public commands only. Nothing here is a stand-in; `SimTestKit` remains the small-data kernel kit.
##
## Match options `o` (all optional):
##   family (0 open / 1 urban / 2 coast), size (96), seed (1)          the map (MapGenerator config)
##   rosters (["roster.napc.vanilla", "roster.nec.vanilla"])             one entry per player, pid = index
##   teams (PackedInt32Array, default i + 1), credits (7500), handicaps
##   rules ({}: merged over {"fog": false, "victory": 1}), opts (SimWorld opts), bots (true), bot_opts ({})
##   layout_players (= player count rounded up to a legal slot count 2/3/4/6/8)
## Typical use:
##   var m: Dictionary = SimMatchKit.make_match({"seed": 3})       # {"world", "bots", "map", "data"}
##   var r: Dictionary = SimMatchKit.run(m, 3600)                   # steps with the bots thinking
##   r -> {"ticks", "ms_avg", "ms_max", "worst_tick" (world tick after the slowest step), "errors", "checksum", ...}; SimMatchKit.report(w, pid) for statistics.

const DEFAULT_ROSTERS: PackedStringArray = ["roster.napc.vanilla", "roster.nec.vanilla"]
const SLOT_COUNTS: PackedInt32Array = [2, 3, 4, 6, 8]

static var _data: GameData = null
static var _maps: Dictionary = {}  ## cache key -> template MapData (never mutated after registration)


static func data() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


## Map config dictionary for MapGenerator.generate from the match options.
static func map_config(o: Dictionary) -> Dictionary:
	var n: int = (o.get("rosters", DEFAULT_ROSTERS) as PackedStringArray).size()
	var slots: int = int(o.get("layout_players", 0))
	if slots == 0:
		slots = 8
		for s: int in SLOT_COUNTS:
			if s >= n:
				slots = s
				break
	return {
		"family": int(o.get("family", 0)), "seed": int(o.get("seed", 1)), "layout_players": slots,
		"size": int(o.get("size", 96)), "params": (o.get("map_params", {}) as Dictionary).duplicate(),
	}


## The generated template map with footprints registered (cached per map config; the world clones it).
static func make_map(o: Dictionary) -> MapData:
	var cfg: Dictionary = map_config(o)
	var key: String = JSON.stringify(cfg, "", true)
	if not _maps.has(key):
		var m: MapData = MapGenerator.generate(cfg)
		SimMatchSetup.register_map_defs(m, data())
		_maps[key] = m
	return _maps[key]


## The SimMatchConfig for the options: pid i plays rosters[i] from start slot i (AI kind), team i + 1 unless given.
static func make_config(o: Dictionary) -> SimMatchConfig:
	var rosters: PackedStringArray = o.get("rosters", DEFAULT_ROSTERS)
	var teams: PackedInt32Array = o.get("teams", PackedInt32Array())
	var pl: Array = []
	for i: int in rosters.size():
		var hc: PackedInt32Array = o.get("handicaps", PackedInt32Array())
		pl.append({
			"pid": i, "kind": "ai", "name": "Bot%d" % i, "roster": rosters[i], "team": teams[i] if i < teams.size() else i + 1,
			"color": i, "start": i, "handicap": hc[i] if i < hc.size() else 100, "ai": {"level": 1, "style": 0, "flags": 0},
		})
	var rules: Dictionary = {"fog": false, "victory": 1, "start_credits": int(o.get("credits", SimConfig.DEFAULT_START_CREDITS))}
	rules.merge(o.get("rules", {}) as Dictionary, true)
	return SimMatchConfig.from_dict({"seed": int(o.get("sim_seed", 20260930)), "map": map_config(o), "rules": rules, "players": pl})


## Builds {"world", "bots" (Array[SimBot], empty when bots == false), "log" (SimCommandLog of every bot command), "map", "data", "config"}. world is null (and
## Log.error has fired) on an invalid configuration.
static func make_match(o: Dictionary = {}) -> Dictionary:
	var d: GameData = data()
	var m: MapData = make_map(o)
	var cfg: SimMatchConfig = make_config(o)
	var w: SimWorld = SimMatchSetup.create_world(d, cfg, m, (o.get("opts", {}) as Dictionary).duplicate())
	var bots: Array[SimBot] = []
	var cmd_log: SimCommandLog = SimCommandLog.new()
	if w != null and bool(o.get("bots", true)):
		for s: SimPlayerSlot in cfg.players:
			var b: SimBot = SimBot.new(s.pid, (o.get("bot_opts", {}) as Dictionary).duplicate())
			b.cmd_log = cmd_log  # every bot command is recorded: m["log"] replays the match without any bot
			bots.append(b)
	return {"world": w, "bots": bots, "map": m, "data": d, "config": cfg, "log": cmd_log}


static func make_world(o: Dictionary = {}) -> SimWorld:
	return make_match(o)["world"] as SimWorld


## Steps `ticks` ticks; every bot thinks before every step. Returns {ticks, ms_avg, ms_max, ms_total, errors (Log
## errors and warnings captured, PackedStringArray), checksum, chain}. `on_tick` (Callable(world, tick), optional) runs
## before the bots. Log.sink is restored afterwards.
static func run(m: Dictionary, ticks: int, on_tick: Callable = Callable()) -> Dictionary:
	var w: SimWorld = m["world"]
	var bots: Array = m["bots"]
	var errors: PackedStringArray = PackedStringArray()
	var old_sink: Callable = Log.sink
	Log.sink = func(lv: int, tag: String, msg: String) -> void:
		if lv >= Log.Level.WARN:
			errors.append("[%d] %s: %s (tick %d)" % [lv, tag, msg, w.tick])
	var total: int = 0
	var worst: int = 0
	var worst_tick: int = 0
	var done: int = 0
	for _i: int in ticks:
		if w.match_state != SimWorld.MATCH_RUNNING:
			break
		var t0: int = Time.get_ticks_usec()
		if on_tick.is_valid():
			on_tick.call(w, w.tick)
		for b: SimBot in bots:
			b.think(w)
		w.step()
		var dt: int = Time.get_ticks_usec() - t0
		total += dt
		if dt > worst:
			worst = dt
			worst_tick = w.tick
		done += 1
	Log.sink = old_sink
	return {
		"ticks": done, "ms_avg": float(total) / 1000.0 / float(maxi(done, 1)), "ms_max": float(worst) / 1000.0,
		"ms_total": float(total) / 1000.0, "worst_tick": worst_tick, "errors": errors, "checksum": w.checksum(), "chain": w.checksum_log,
	}


## Per-player statistics for assertions and reports.
static func report(w: SimWorld, pid: int) -> Dictionary:
	var p: SimPlayer = w.players[pid]
	var pe: SimPlayerEcon = p.econ
	var n_units: int = 0
	var n_combat: int = 0
	var n_coll: int = 0
	for u: SimEntity in w.units_of(pid):
		if (u.flags & SimFlags.F_GONE) != 0:
			continue
		n_units += 1
		var ud: DefUnit = w.data.units[u.def_idx]
		if (ud.tags & DefEnums.UT_COMBAT) != 0:
			n_combat += 1
		if (ud.tags & DefEnums.UT_COLLECTOR) != 0:
			n_coll += 1
	var n_struct: int = 0
	for s: SimEntity in w.structures_of(pid):
		if (s.flags & SimFlags.F_GONE) == 0:
			n_struct += 1
	return {
		"credits": p.credits, "harvested": pe.stat_harvested, "spent_construction": pe.stat_spent_construction,
		"spent_units": pe.stat_spent_units, "units": n_units, "combat_units": n_combat, "collectors": n_coll,
		"structures": n_struct, "built": p.st_units_built, "lost": p.st_units_lost, "killed": p.st_units_killed,
		"structures_lost": p.st_structs_lost, "structures_built": p.st_structs_built, "power": [pe.power_supply, pe.power_demand],
		"eliminated": p.eliminated,
	}


## Number of events of `type` in the world's event buffer so far.
static func count_events(w: SimWorld, type: int) -> int:
	var n: int = 0
	var d: PackedInt32Array = w.events.data
	for i: int in d.size() / SimEvent.STRIDE:
		if d[i * SimEvent.STRIDE] == type:
			n += 1
	return n
