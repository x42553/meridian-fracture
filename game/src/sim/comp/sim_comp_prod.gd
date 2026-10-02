class_name SimCompProd
extends SimComponent
## Slot `e.prod` (economy 4.3): the unit queue of one producer structure (Barracks, Factory, Airfield, Dock,
## Refinery collector queue). Created by the economy's on_spawn for structures with a queue kind. Every field is
## hashed.

const HASH_EXEMPT: PackedStringArray = []

var kind: int = SimEconConst.PROD_NONE  ## PROD_* of this structure
var q_def: PackedInt32Array = PackedInt32Array()  ## u_idx, head at [0]; length <= queue_len (5)
var q_cost: PackedInt32Array = PackedInt32Array()  ## locked at enqueue
var q_ticks: PackedInt32Array = PackedInt32Array()  ## locked at enqueue
var head_progress: int = 0  ## bp-ticks: += rate_bp each tick; complete at q_ticks[0] * 10000
var head_paid: int = 0
var head_state: int = SimEconConst.QS_EMPTY
var head_cap_reserved: bool = false
var hold: bool = false
var exit_retry_tick: int = 0
var is_primary: bool = false
var rally_on: bool = false
var rally_x: int = 0
var rally_y: int = 0
var rally_target: int = 0  ## entity id, or -(deposit idx + 1) = harvest that deposit
var pad_ent: PackedInt32Array = PackedInt32Array()  ## Airfield only: occupant aircraft id per pad (0 = free)
var rearm_boost_until: int = 0
var rearm_boost_bp: int = 10000


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(kind)
	buf.append(q_def.size())
	buf.append_array(q_def)
	buf.append(q_cost.size())
	buf.append_array(q_cost)
	buf.append(q_ticks.size())
	buf.append_array(q_ticks)
	buf.append(head_progress)
	buf.append(head_paid)
	buf.append(head_state)
	buf.append(1 if head_cap_reserved else 0)
	buf.append(1 if hold else 0)
	buf.append(exit_retry_tick)
	buf.append(1 if is_primary else 0)
	buf.append(1 if rally_on else 0)
	buf.append(rally_x)
	buf.append(rally_y)
	buf.append(rally_target)
	buf.append(pad_ent.size())
	buf.append_array(pad_ent)
	buf.append(rearm_boost_until)
	buf.append(rearm_boost_bp)
