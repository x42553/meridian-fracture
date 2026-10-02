class_name SimCompTemp
extends SimComponent
## Temporary / summoned entity data (economy 4.3). The kernel has no slot for it (the summon slot belongs to the
## abilities domain), so the strategic domain (E7 / E8) decides where it hangs (all fields hashed).

const HASH_EXEMPT: PackedStringArray = []

var expire_tick: int = 0
var script_kind: int = SimEconConst.TS_NONE  ## TS_* (spec name `script` collides with Object.script)
var src_kind: int = 0  ## 0 = support power, 1 = superweapon
var src_idx: int = -1
var src_pid: int = -1
var attack_id: int = 0
var brain: int = SimEconConst.BR_NONE  ## BR_*
var zx: int = 0
var zy: int = 0
var zr: int = 0
var state: int = 0
var state_until: int = 0
var bound_zone: int = 0


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(expire_tick)
	buf.append(script_kind)
	buf.append(src_kind)
	buf.append(src_idx)
	buf.append(src_pid)
	buf.append(attack_id)
	buf.append(brain)
	buf.append(zx)
	buf.append(zy)
	buf.append(zr)
	buf.append(state)
	buf.append(state_until)
	buf.append(bound_zone)
