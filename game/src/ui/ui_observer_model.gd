class_name UiObserverModel
extends RefCounted
## The live numbers of the observer HUD (ui.md 5.16.3, task REP2): one row per player with credits, income per minute (a rolling
## 60 s window of the harvested total), army value and size, units, structures, kills, losses, score and APM, plus the follow-camera
## target. Pure: it reads a `UiSimPort` (`player_overview`, `player_stats`) at 2 Hz and holds only its own history; a rewind (replay
## seek backwards) clears the history. Presentation only.

const SAMPLE_EVERY: int = 10
const WINDOW_TICKS: int = 1200

## Rows of the last sample: `[{pid, name, color, team, faction, roster_id, credits, earned, income, army_value, army_n, units, structs,
## kills, losses, active, score, apm, share (army value 0..1000 of the largest), army_x, army_y, base_x, base_y}]` ascending by pid.
var rows: Array[Dictionary] = []

var _hist: Dictionary = {}
var _last_tick: int = -1
var _ov: Dictionary = {}
var _st: Dictionary = {}


## Re-samples when `SAMPLE_EVERY` ticks passed (or `force`). True when `rows` changed.
func update(sim: UiSimPort, force: bool = false) -> bool:
	var t: int = sim.tick()
	if t < _last_tick:
		_hist.clear()
		_last_tick = -1
	if not force and _last_tick >= 0 and t - _last_tick < SAMPLE_EVERY:
		return false
	_last_tick = t
	rows.clear()
	var top: int = 1
	for pid: int in sim.player_count():
		sim.player_overview(pid, _ov)
		if _ov.is_empty() or int(_ov.get("present", 1)) == 0:
			continue
		sim.player_stats(pid, _st)
		var earned: int = int(_ov["earned"])
		var h: Array = _hist.get(pid, []) as Array
		if h.is_empty() or t - (h[h.size() - 1] as Vector2i).x >= 20:
			h.append(Vector2i(t, earned))
			while h.size() > 2 and t - (h[0] as Vector2i).x > WINDOW_TICKS:
				h.remove_at(0)
			_hist[pid] = h
		var income: int = 0
		if h.size() >= 2:
			var first: Vector2i = h[0] as Vector2i
			var last: Vector2i = h[h.size() - 1] as Vector2i
			if last.x > first.x:
				income = (last.y - first.y) * 1200 / (last.x - first.x)
		var score: Dictionary = UiScore.compute({"units_killed": int(_st.get("units_killed", 0)), "structures_destroyed": int(_st.get("structs_killed", 0)),
			"harvested": earned, "value_destroyed": -1, "research_done": 0, "powers_used": -1, "sw_launched": -1})
		var row: Dictionary = {"pid": pid, "name": sim.name_of(pid), "color": sim.color_of(pid), "team": sim.team_of(pid), "faction": "", "roster_id": "",
			"credits": int(_ov["credits"]), "earned": earned, "income": income, "army_value": int(_ov["army_value"]), "army_n": int(_ov["army_n"]),
			"units": int(_ov["units"]), "structs": int(_ov["structs"]), "kills": int(_ov["kills"]), "losses": int(_ov["losses"]),
			"active": int(_ov["active"]) != 0, "score": int(score["total"]), "apm": UiScore.apm(int(_st.get("cmds", 0)), t), "share": 0,
			"army_x": int(_ov["army_x"]), "army_y": int(_ov["army_y"]), "base_x": int(_ov["base_x"]), "base_y": int(_ov["base_y"])}
		var ro: DefRoster = sim.roster_of(pid)
		if ro != null:
			row["roster_id"] = ro.id
			var parts: PackedStringArray = ro.id.split(".")
			row["faction"] = parts[1] if parts.size() >= 2 else ""
		top = maxi(top, int(row["army_value"]))
		rows.append(row)
	for r: Dictionary in rows:
		r["share"] = int(r["army_value"]) * 1000 / top
	return true


## The row of a pid ({} = none).
func row_of(pid: int) -> Dictionary:
	for r: Dictionary in rows:
		if int(r["pid"]) == pid:
			return r
	return {}


## Where the follow camera looks for a player (sim units): the centre of the army, else of the base, else (-1, -1).
func follow_target(pid: int) -> Vector2i:
	var r: Dictionary = row_of(pid)
	if r.is_empty():
		return Vector2i(-1, -1)
	if int(r["army_x"]) >= 0:
		return Vector2i(int(r["army_x"]), int(r["army_y"]))
	if int(r["base_x"]) >= 0:
		return Vector2i(int(r["base_x"]), int(r["base_y"]))
	return Vector2i(-1, -1)


## The pid after / before `pid` among the players still in the game (wraps); -1 when none. `pid` -1 starts from the first / last.
func next_pid(pid: int, direction: int = 1) -> int:
	if rows.is_empty():
		return -1
	var order: Array[int] = []
	for r: Dictionary in rows:
		order.append(int(r["pid"]))
	var i: int = order.find(pid)
	for step: int in order.size():
		var j: int = (i + direction * (step + 1) + order.size() * 2) % order.size() if i >= 0 else (step if direction > 0 else order.size() - 1 - step)
		if bool(row_of(order[j])["active"]):
			return order[j]
	return order[0]
