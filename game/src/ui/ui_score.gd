class_name UiScore
extends RefCounted
## The end-of-match score (ui.md 5.16.5): integer, presentation only, never fed back into the sim.
##   military   = value_destroyed / 10
##   economy    = harvested / 20
##   technology = 100 * research_done + 50 * powers_used + 250 * (1 if sw_launched > 0 else 0)
##   score      = military + economy + technology
##   apm        = commands * 60 / max(1, duration_ticks / 20)
## `value_destroyed` is the sum of `paid` of the enemy entities the player destroyed (`st_value_killed`); until the sim keeps that counter
## the caller passes -1 and `military` is estimated from the kill counts (`KILL_UNIT_VALUE`, `KILL_STRUCT_VALUE` credits per kill).

const MILITARY_DIV: int = 10
const ECONOMY_DIV: int = 20
const KILL_UNIT_VALUE: int = 600
const KILL_STRUCT_VALUE: int = 1500


## `st`: a `UiMatchStats.player_stats` dictionary. Returns {military, economy, technology, total, estimated}.
static func compute(st: Dictionary) -> Dictionary:
	var vd: int = int(st.get("value_destroyed", -1))
	var estimated: bool = vd < 0
	if estimated:
		vd = int(st.get("units_killed", 0)) * KILL_UNIT_VALUE + int(st.get("structures_destroyed", 0)) * KILL_STRUCT_VALUE
	var military: int = vd / MILITARY_DIV
	var economy: int = int(st.get("harvested", 0)) / ECONOMY_DIV
	# -1 = a counter the sim does not keep yet: worth nothing
	var tech: int = 100 * maxi(int(st.get("research_done", 0)), 0) + 50 * maxi(int(st.get("powers_used", 0)), 0) \
			+ (250 if int(st.get("sw_launched", 0)) > 0 else 0)
	return {"military": military, "economy": economy, "technology": tech, "total": military + economy + tech, "estimated": estimated}


static func score(st: Dictionary) -> int:
	return int(compute(st)["total"])


## Actions per minute over the match (integer division).
static func apm(commands: int, duration_ticks: int) -> int:
	return commands * 60 / maxi(1, duration_ticks / 20)
