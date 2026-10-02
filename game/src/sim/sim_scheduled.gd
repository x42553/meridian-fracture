class_name SimScheduled
extends RefCounted
## One entry of the strategic effect scheduler, ordered by (tick, seq) (economy 4.4).

const HASH_EXEMPT: PackedStringArray = []

var tick: int = 0
var seq: int = 0
var kind: int = 0  ## SK_*
var owner: int = 0
var src_idx: int = 0
var attack_id: int = 0
var x: int = 0
var y: int = 0
var r: int = 0
var a: int = 0
var b: int = 0
var c: int = 0
var d: int = 0
var ids: PackedInt32Array = PackedInt32Array()


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(tick)
	buf.append(seq)
	buf.append(kind)
	buf.append(owner)
	buf.append(src_idx)
	buf.append(attack_id)
	buf.append(x)
	buf.append(y)
	buf.append(r)
	buf.append(a)
	buf.append(b)
	buf.append(c)
	buf.append(d)
	buf.append(ids.size())
	buf.append_array(ids)
