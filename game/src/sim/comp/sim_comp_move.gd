class_name SimCompMove
extends SimComponent
## Slot `e.move` (terrain_movement 4.4; the spec calls it SimMoveComp). Ints and one packed int array only.
## Profile copies and per-cell caches are derived (exempt); everything else is hashed in declaration order.

const HASH_EXEMPT: PackedStringArray = ["mc", "np", "nav_size", "radius", "mass", "turn_mode", "turn_rate", "accel_q4", "decel_q4", "reverse_pct", "speed_base", "hl", "cell", "cell_kind", "vcur_q4"]

# --- profile copy: derived from SimMoveProfiles[def_idx] at on_spawn (exempt: recomputed from the def) ---
var mc: int = 0
var np: int = -1
var nav_size: int = 1
var radius: int = 0
var mass: int = 1
var turn_mode: int = 0
var turn_rate: int = 0
var accel_q4: int = 1
var decel_q4: int = 1
var reverse_pct: int = 0
var speed_base: int = 0  ## base units/tick (DefUnit.speed): used only when abilities.speed_units is unavailable
# --- dynamic state ---
var state: int = 0  ## SimMoveConfig.MS_*
var flags: int = 0  ## MF_*
var spd_q4: int = 0  ## signed (negative = reversing)
var hl: int = 0  ## current separation layer (HL_*), derived (exempt)
var speed_cap_q4: int = 0  ## 0 = none (formation speed match)
var cell: int = 0  ## derived caches (exempt): current cell index, its TerrainKind, last top speed (Q4)
var cell_kind: int = 0
var vcur_q4: int = 0
var vx: int = 0  ## displacement applied in the last tick (units)
var vy: int = 0
# --- goal and path ---
var goal_kind: int = 0
var goal_x: int = 0  ## GK_FACE: the target facing (binary angle)
var goal_y: int = 0
var goal_range: int = 0
var goal_target: int = -1
var goal_cell: int = -1
var goal_opts: int = 0
var path: PackedInt32Array = PackedInt32Array()
var wp: int = 0
var path_ver: int = -1
var req_id: int = 0
var wait: int = 0
var repath_at: int = 0
var result: int = 0
var goal_tick: int = 0
var fslot_x: int = 0  ## formation slot written by the group leader's T_MOVE begin (task MV2)
var fslot_y: int = 0
var fslot_tick: int = -1
var route_x: int = -1  ## path target when it differs from the goal (formation slots share the group target's path); -1 = none
var route_y: int = -1
# --- stuck / blocking ---
var stuck_x: int = 0
var stuck_y: int = 0
var stuck_cnt: int = 0
var nudge_t: int = 0
var nudge_dir: int = 0
var blocked_by: int = -1
var blocked_t: int = 0
var water_t: int = -100  ## tick of the last accepted F_ON_WATER flip
# --- scripted glide and layer change ---
var g_x0: int = 0
var g_y0: int = 0
var g_x1: int = 0
var g_y1: int = 0
var g_t: int = 0
var g_n: int = 0
var lr_layer: int = -1
var lr_t: int = 0
# --- aircraft (unused = 0 for ground; task MV2) ---
var air_mode: int = 0
var alt: int = 0
var alt_goal: int = 0
var orbit_x: int = 0
var orbit_y: int = 0
var orbit_r: int = 0
var orbit_dir: int = 1
var land_x: int = 0
var land_y: int = 0
var land_heading: int = -1
var air_phase: int = 0
# --- additions of this implementation (hashed) ---
var pack_t: int = -100  ## tick of the last abstract request_pack call (rate limit)
var side_t: int = -100  ## tick of the last accepted sidestep


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(state)
	buf.append(flags)
	buf.append(spd_q4)
	buf.append(speed_cap_q4)
	buf.append(vx)
	buf.append(vy)
	buf.append(goal_kind)
	buf.append(goal_x)
	buf.append(goal_y)
	buf.append(goal_range)
	buf.append(goal_target)
	buf.append(goal_cell)
	buf.append(goal_opts)
	buf.append(path.size())
	buf.append_array(path)
	buf.append(wp)
	buf.append(path_ver)
	buf.append(req_id)
	buf.append(wait)
	buf.append(repath_at)
	buf.append(result)
	buf.append(goal_tick)
	buf.append(fslot_x)
	buf.append(fslot_y)
	buf.append(fslot_tick)
	buf.append(route_x)
	buf.append(route_y)
	buf.append(stuck_x)
	buf.append(stuck_y)
	buf.append(stuck_cnt)
	buf.append(nudge_t)
	buf.append(nudge_dir)
	buf.append(blocked_by)
	buf.append(blocked_t)
	buf.append(water_t)
	buf.append(g_x0)
	buf.append(g_y0)
	buf.append(g_x1)
	buf.append(g_y1)
	buf.append(g_t)
	buf.append(g_n)
	buf.append(lr_layer)
	buf.append(lr_t)
	buf.append(air_mode)
	buf.append(alt)
	buf.append(alt_goal)
	buf.append(orbit_x)
	buf.append(orbit_y)
	buf.append(orbit_r)
	buf.append(orbit_dir)
	buf.append(land_x)
	buf.append(land_y)
	buf.append(land_heading)
	buf.append(air_phase)
	buf.append(pack_t)
	buf.append(side_t)
