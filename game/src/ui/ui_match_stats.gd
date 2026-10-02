class_name UiMatchStats
extends RefCounted
## Match statistics for the end screen (ui.md 4.9): per-player counters read from `SimPlayer` / `SimPlayerEcon` (read only), a
## time series sampled every `SAMPLE_TICKS` ticks while the match runs (the recorder lives in the `AppMatchContext`, fed once per
## rendered frame), and `build()` which assembles the result summary of 4.9.2.
##
## Sim counters that do not exist yet are reported as -1 (`value_destroyed`, `powers_used`, `sw_launched`); `UiScore` and the end
## screen treat -1 as "not available" and hide or estimate them.

const SAMPLE_TICKS: int = 200
const OUTCOME_VICTORY: int = 0
const OUTCOME_DEFEAT: int = 1
const OUTCOME_DRAW: int = 2
const OUTCOME_OBSERVED: int = 3
const SERIES_KEYS: PackedStringArray = ["harvested", "spent", "army", "kills"]

## pid -> {key: PackedInt32Array} (one sample per SAMPLE_TICKS, the first at tick 0).
var series: Dictionary = {}
var _next: int = 0


## Records one sample per `SAMPLE_TICKS` boundary; idempotent within a tick.
func sample(w: SimWorld) -> void:
	if w == null or w.tick < _next:
		return
	_next = (w.tick / SAMPLE_TICKS + 1) * SAMPLE_TICKS
	for p: SimPlayer in w.players:
		if p.controller == SimPlayer.Controller.NONE:
			continue
		if not series.has(p.pid):
			var row: Dictionary = {}
			for k: String in SERIES_KEYS:
				row[k] = PackedInt32Array()
			series[p.pid] = row
		var st: Dictionary = player_stats(w, p.pid)
		var row2: Dictionary = series[p.pid] as Dictionary
		_push(row2, "harvested", int(st["harvested"]))
		_push(row2, "spent", int(st["spent"]))
		_push(row2, "army", p.unit_count)
		_push(row2, "kills", int(st["units_killed"]) + int(st["structures_destroyed"]))


## Packed arrays are values: the grown copy goes back into the dictionary.
static func _push(row: Dictionary, key: String, v: int) -> void:
	var a: PackedInt32Array = row[key] as PackedInt32Array
	a.append(v)
	row[key] = a


func sample_count() -> int:
	var n: int = 0
	for pid: Variant in series:
		n = maxi(n, ((series[pid] as Dictionary)["harvested"] as PackedInt32Array).size())
	return n


## The counters of ui.md 4.9.1 for one player (all ints).
static func player_stats(w: SimWorld, pid: int) -> Dictionary:
	var p: SimPlayer = w.players[pid]
	var harvested: int = p.st_credits_earned
	var research: int = 0
	if p.econ != null:
		harvested = maxi(harvested, p.econ.stat_harvested + p.econ.stat_salvaged)
		for b: int in p.econ.researched:
			research += 1 if b != 0 else 0
	return {"units_built": p.st_units_built, "units_lost": p.st_units_lost, "units_killed": p.st_units_killed,
		"structures_built": p.st_structs_built, "structures_lost": p.st_structs_lost, "structures_destroyed": p.st_structs_killed,
		"harvested": harvested, "spent": p.st_credits_spent, "damage_dealt": p.st_damage_dealt, "damage_taken": p.st_damage_taken,
		"commands": p.st_cmds, "peak_units": p.st_peak_units, "research_done": research,
		"value_destroyed": -1, "value_lost": -1, "powers_used": -1, "sw_launched": -1}


## The result summary of ui.md 4.9.2 for a finished (or abandoned) match.
## `end`: the `match_ended` dictionary ({reason, sim_reason, winner_team, final_tick, final_checksum}; empty when the player left).
## `net`: a NetSession (or null) for the per-player status; `local_pid` < 0 = observer.
func build(w: SimWorld, config: Dictionary, end: Dictionary, local_pid: int, net: NetSession = null) -> Dictionary:
	var out: Dictionary = {"outcome": OUTCOME_OBSERVED, "result": "observed", "reason": int(end.get("reason", 0)),
		"winner_team": int(end.get("winner_team", -1)), "duration_ticks": 0, "final_checksum": int(end.get("final_checksum", 0)),
		"players": [], "series": {}, "replay_path": "", "can_save_replay": false, "can_return_to_lobby": false, "left": end.is_empty()}
	if w == null:
		return out
	var ticks: int = int(end.get("final_tick", w.tick))
	out["duration_ticks"] = ticks
	out["tick"] = ticks
	out["duration_s"] = ticks * SimConfig.TICK_MS / 1000
	var local_team: int = w.players[local_pid].team if local_pid >= 0 and local_pid < w.players.size() else -1
	var winner: int = int(out["winner_team"])
	if local_pid >= 0:
		if w.players[local_pid].eliminated != 0 and winner != local_team:
			out["outcome"] = OUTCOME_DEFEAT  # surrendered or wiped out: a lost game even when the match ended without a winner
			out["result"] = "defeat"
		elif winner < 0:
			out["outcome"] = OUTCOME_DRAW
			out["result"] = "draw"
		elif winner == local_team:
			out["outcome"] = OUTCOME_VICTORY
			out["result"] = "victory"
		else:
			out["outcome"] = OUTCOME_DEFEAT
			out["result"] = "defeat"
	if bool(out["left"]):
		out["result"] = "left"
	var cfg_players: Dictionary = {}
	for pv: Variant in config.get("players", []) as Array:
		cfg_players[int((pv as Dictionary).get("pid", -1))] = pv
	var rows: Array = []
	for p: SimPlayer in w.players:
		if p.controller == SimPlayer.Controller.NONE:
			continue
		var st: Dictionary = player_stats(w, p.pid)
		var cp: Dictionary = cfg_players.get(p.pid, {}) as Dictionary
		var alive_ticks: int = p.elim_tick if p.eliminated != 0 and p.elim_tick > 0 else ticks
		var sc: Dictionary = UiScore.compute(st)
		var faction_code: String = ""
		if p.faction_idx >= 0 and p.faction_idx < w.data.factions.size():
			faction_code = w.data.factions[p.faction_idx].code
		rows.append({"pid": p.pid, "name": p.name, "roster_id": p.roster.id if p.roster != null else str(cp.get("roster", "")),
			"faction_code": faction_code, "team": p.team, "color": p.color,
			"status": net.player_status(p.pid) if net != null else 0, "is_local": p.pid == local_pid,
			"is_ai": p.controller == SimPlayer.Controller.AI or str(cp.get("kind", "")) == "ai", "ai_level": p.ai_level,
			"eliminated": p.eliminated != 0, "elim_reason": p.elim_reason, "alive_ticks": alive_ticks, "credits": p.credits,
			"stats": st, "score": int(sc["total"]), "score_parts": sc, "apm": UiScore.apm(int(st["commands"]), ticks),
			# flat aliases used by the older summary consumers
			"units_built": st["units_built"], "units_lost": st["units_lost"], "units_killed": st["units_killed"],
			"structures_built": st["structures_built"], "structures_lost": st["structures_lost"]})
	out["players"] = rows
	out["series"] = series.duplicate(true)
	if net != null:
		out["replay_path"] = net.replay_path()
		out["can_save_replay"] = AppReplay.can_save(net)
	var mcfg: Dictionary = config.get("map", {}) as Dictionary
	out["map_family"] = int(mcfg.get("family", 0))
	out["map_size"] = int(mcfg.get("size", 0))
	out["map_seed"] = int(mcfg.get("seed", 0))
	out["map_name"] = UiMapNames.name_for(int(mcfg.get("family", 0)), int(mcfg.get("seed", 0)))
	return out
