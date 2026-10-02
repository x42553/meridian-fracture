class_name SimCompAir
extends SimComponent
## Slot `e.air`: aircraft / drones (sortie state machine) and airfields (pads). Allocated by SimCombatSystem.on_spawn;
## the state machine itself is task CBB/CBC (combat 5.12).

const HASH_EXEMPT: PackedStringArray = []

var is_airfield: int = 0
# aircraft
var state: int = 0  ## SimCombatConsts.AIR_*
var sub: int = 0
var state_t0: int = 0
var mission: int = 0  ## MI_*
var m_target: int = -1
var m_x: int = 0
var m_y: int = 0
var m_r: int = 0
var resume_mission: int = 0
var resume_target: int = -1
var resume_x: int = 0
var resume_y: int = 0
var home_id: int = -1
var home_kind: int = 0
var pad: int = -1
var fuel: int = 0
var rearm_prog: int = 0  ## bp accumulator, 10000 = one tick at base speed
var pass_count: int = 0
var run_ux: int = 0
var run_uy: int = 0
var wx: int = 0
var wy: int = 0
var release_left: int = 0
var next_logic: int = 0
var orphan_deadline: int = -1
var forced_return: int = 0
var search_until: int = 0  ## MI_ATTACK: tick until which the aircraft waits for a next target (0 = not searching)
var sub_t0: int = 0  ## tick the current attack sub-state began
# airfield
var pad_occ: PackedInt32Array = PackedInt32Array()  ## per pad: occupant id or -1 (a reservation counts as occupied)


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(is_airfield)
	buf.append(state)
	buf.append(sub)
	buf.append(state_t0)
	buf.append(mission)
	buf.append(m_target)
	buf.append(m_x)
	buf.append(m_y)
	buf.append(m_r)
	buf.append(resume_mission)
	buf.append(resume_target)
	buf.append(resume_x)
	buf.append(resume_y)
	buf.append(home_id)
	buf.append(home_kind)
	buf.append(pad)
	buf.append(fuel)
	buf.append(rearm_prog)
	buf.append(pass_count)
	buf.append(run_ux)
	buf.append(run_uy)
	buf.append(wx)
	buf.append(wy)
	buf.append(release_left)
	buf.append(next_logic)
	buf.append(orphan_deadline)
	buf.append(forced_return)
	buf.append(search_until)
	buf.append(sub_t0)
	buf.append(pad_occ.size())
	buf.append_array(pad_occ)
