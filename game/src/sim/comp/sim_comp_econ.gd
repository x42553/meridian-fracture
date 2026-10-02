class_name SimCompEcon
extends SimComponent
## Slot `e.econ` (economy 4.3): per-entity economy state. Structures always carry one (lifecycle `st`, power,
## repair, capture, dock, income); Collector / Engineer-class units carry one for the harvest and work state
## machines. Ints and packed int arrays only; every field is hashed.

const HASH_EXEMPT: PackedStringArray = []

var flags: int = 0  ## EF_*
var paid_cost: int = 0  ## credits actually paid; basis for salvage, sell and repair (mirrors SimEntity.paid_cost)
# structure lifecycle
var st: int = SimEconConst.ST_ACTIVE
var st_until: int = 0  ## tick when BUILDUP / SELLING / UNDEPLOYING ends
var power_class: int = SimEconConst.PC_NONE
var power_delta: int = 0  ## delta registered with the owner while ACTIVE (+supply / -demand); 0 if unregistered
var registered: bool = false  ## counted in struct_count / power / producer lists
var mcv_paid_cost: int = 0  ## HQ only: paid cost of the MCV it came from (restored on undeploy)
var shutdown_until: int = 0  ## EMP shutdown end tick (written by the abilities domain, read here)
var repair_on: bool = false  ## wrench mode
var repair_acc_hp: int = 0
var repair_acc_cost: int = 0
var repair_src_mask: int = 0
var unit_repairer_id: int = 0
var unit_repairer_tick: int = 0
# capture (capturable structures)
var cap_pid: int = -1
var cap_progress: int = 0
var cap_last_tick: int = 0
var cap_chan: PackedInt32Array = PackedInt32Array()  ## size 8: channelers per pid this tick
var depot_next_tick: int = 0
var income_acc: int = 0  ## neutral income accumulator, milli-credits (economy slice E2)
# collector unit
var cargo: int = 0
var h_state: int = SimEconConst.H_IDLE
var h_mode: int = 0
var h_field: int = -1
var h_last_field: int = -1
var h_refinery: int = 0
var h_timer: int = 0
var h_bad_until: int = 0
var h_bad_field: int = -1
var h_flee_until: int = 0
var h_last_hp: int = 0
var h_scan_tick: int = 0
var h_unload_total: int = 0
# refinery dock
var dock_occupant: int = 0
var dock_queue: PackedInt32Array = PackedInt32Array()
var dock_timer: int = 0
var dock_since: int = 0
# engineer-class units
var w_kind: int = SimEconConst.W_NONE
var w_target: int = 0
var w_progress: int = 0


func _init() -> void:
	cap_chan.resize(8)


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(flags)
	buf.append(paid_cost)
	buf.append(st)
	buf.append(st_until)
	buf.append(power_class)
	buf.append(power_delta)
	buf.append(1 if registered else 0)
	buf.append(mcv_paid_cost)
	buf.append(shutdown_until)
	buf.append(1 if repair_on else 0)
	buf.append(repair_acc_hp)
	buf.append(repair_acc_cost)
	buf.append(repair_src_mask)
	buf.append(unit_repairer_id)
	buf.append(unit_repairer_tick)
	buf.append(cap_pid)
	buf.append(cap_progress)
	buf.append(cap_last_tick)
	buf.append(cap_chan.size())
	buf.append_array(cap_chan)
	buf.append(depot_next_tick)
	buf.append(income_acc)
	buf.append(cargo)
	buf.append(h_state)
	buf.append(h_mode)
	buf.append(h_field)
	buf.append(h_last_field)
	buf.append(h_refinery)
	buf.append(h_timer)
	buf.append(h_bad_until)
	buf.append(h_bad_field)
	buf.append(h_flee_until)
	buf.append(h_last_hp)
	buf.append(h_scan_tick)
	buf.append(h_unload_total)
	buf.append(dock_occupant)
	buf.append(dock_queue.size())
	buf.append_array(dock_queue)
	buf.append(dock_timer)
	buf.append(dock_since)
	buf.append(w_kind)
	buf.append(w_target)
	buf.append(w_progress)
