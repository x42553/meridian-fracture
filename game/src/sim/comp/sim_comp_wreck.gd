class_name SimCompWreck
extends SimComponent
## Wreck data (economy 4.3): paid-cost basis, owner, killer, salvage claim. The kernel has no wreck slot in
## SimEntity, so this record is owned by the salvage domain (E6), which decides where it hangs (all fields hashed).

const HASH_EXEMPT: PackedStringArray = []

var paid_cost: int = 0
var owner_pid: int = -1
var killer_pid: int = -1
var src_u_idx: int = -1
var flags: int = 0  ## WF_*
var expire_tick: int = 0  ## spawn tick + 1200; frozen while salvage_by != 0
var salvage_by: int = 0  ## entity id of the claiming salvager
var salvage_end_tick: int = 0


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(paid_cost)
	buf.append(owner_pid)
	buf.append(killer_pid)
	buf.append(src_u_idx)
	buf.append(flags)
	buf.append(expire_tick)
	buf.append(salvage_by)
	buf.append(salvage_end_tick)
