class_name SimCompVision
extends SimComponent
## Slot `e.vis` (abilities 4.4), allocated by SimVisionSystem.on_spawn for every UNIT / STRUCTURE / NEUTRAL. Ints only.

const HASH_EXEMPT: PackedStringArray = []

var group: int = -1  ## vision group of the owner, -1 neutral
var cx: int = -1  ## stamped sight disc cell; cx == -1 when not stamped
var cy: int = -1
var r_cells: int = 0
var det_cx: int = -1  ## stamped detection disc (detector-bearing entities)
var det_cy: int = -1
var det_r: int = 0
var vis_mask: int = 0  ## bit g = group g currently sees this entity (own group always while active)
var ever_mask: int = 0  ## bit g = group g has seen it at least once (drives structure ghosts)
var stealth_kind: int = 0  ## SimAbilityConsts.SK_* it can have
var concealed: int = 0
var revealed_until: int = 0
var vflags: int = 0  ## SimAbilityConsts.VF_*
var decoy_mask: int = 0  ## bit g = group g has identified this decoy at least once
var mcell: int = -1  ## cell (cy * w + cx) at which vis_mask was last evaluated, -1 never / inactive


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(group)
	buf.append(cx)
	buf.append(cy)
	buf.append(r_cells)
	buf.append(det_cx)
	buf.append(det_cy)
	buf.append(det_r)
	buf.append(vis_mask)
	buf.append(ever_mask)
	buf.append(stealth_kind)
	buf.append(concealed)
	buf.append(revealed_until)
	buf.append(vflags)
	buf.append(decoy_mask)
	buf.append(mcell)
