class_name SimWarning
extends RefCounted
## Queryable warning-zone record of a superweapon / warned power (economy 4.4). State, not an event (DR-12).

const HASH_EXEMPT: PackedStringArray = []

var id: int = 0
var kind: int = 0  ## WK_*
var src_idx: int = 0
var owner: int = 0
var launcher_id: int = 0
var x: int = 0
var y: int = 0
var x2: int = 0
var y2: int = 0
var radius: int = 0
var width: int = 0
var angle: int = 0
var start_tick: int = 0
var exec_tick: int = 0
var end_tick: int = 0
var phase: int = SimEconConst.AT_WARNING  ## AT_*
var affected_mask: int = 0
var refresh_tick: int = 0
var payload_ids: PackedInt32Array = PackedInt32Array()


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(id)
	buf.append(kind)
	buf.append(src_idx)
	buf.append(owner)
	buf.append(launcher_id)
	buf.append(x)
	buf.append(y)
	buf.append(x2)
	buf.append(y2)
	buf.append(radius)
	buf.append(width)
	buf.append(angle)
	buf.append(start_tick)
	buf.append(exec_tick)
	buf.append(end_tick)
	buf.append(phase)
	buf.append(affected_mask)
	buf.append(refresh_tick)
	buf.append(payload_ids.size())
	buf.append_array(payload_ids)
