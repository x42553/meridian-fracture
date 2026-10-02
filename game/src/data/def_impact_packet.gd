class_name DefImpactPacket
extends RefCounted
## One strategic impact packet (superweapons, strike powers; data_balance 4.2). Offsets are in the local frame:
## +x along the committed line / orientation.

var damage: int = 0
var dtype: int = 0
var radius: int = 0
var edge_bp: int = 0
var delay_t: int = 0
var offset_x: int = 0
var offset_y: int = 0
var target_mask: int = 0
var non_lethal: bool = false
var params: Dictionary = {}


func copy_resolved() -> DefImpactPacket:
	return DefBase.deep_copy(self) as DefImpactPacket
