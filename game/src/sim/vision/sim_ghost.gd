class_name SimGhost
extends RefCounted
## Remembered enemy structure record (abilities 4.10 / 5.9.7): display and pathing memory only. Ints only.

var eid: int = 0
var def_idx: int = -1
var owner: int = -1
var x: int = 0
var y: int = 0
var facing: int = 0
var hp_pct: int = 100
var seen_tick: int = 0
var cell: int = 0  ## cy * map.w + cx


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(eid)
	buf.append(def_idx)
	buf.append(owner)
	buf.append(x)
	buf.append(y)
	buf.append(facing)
	buf.append(hp_pct)
	buf.append(seen_tick)
	buf.append(cell)
