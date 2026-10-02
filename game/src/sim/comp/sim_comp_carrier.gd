class_name SimCompCarrier
extends SimComponent
## Slot `e.carrier`: drone bays of a carrier (combat 5.13). Allocated by SimCombatSystem.on_spawn; the launch /
## dock / replace logic is task CBC.

const HASH_EXEMPT: PackedStringArray = []

var wing: int = 0
var wing_req: int = -1
var wing_switch_until: int = 0
var bay_id: PackedInt32Array = PackedInt32Array()  ## per bay: drone entity id or -1
var bay_state: PackedInt32Array = PackedInt32Array()  ## BAY_*
var bay_timer: PackedInt32Array = PackedInt32Array()
var next_launch: int = 0
var recall_at: int = 0


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(wing)
	buf.append(wing_req)
	buf.append(wing_switch_until)
	buf.append(bay_id.size())
	buf.append_array(bay_id)
	buf.append(bay_state.size())
	buf.append_array(bay_state)
	buf.append(bay_timer.size())
	buf.append_array(bay_timer)
	buf.append(next_launch)
	buf.append(recall_at)
