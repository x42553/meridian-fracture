class_name DefCondApplication
extends RefCounted
## One conditional bible modifier of a roster with its resolved target sets (data_balance 4.2 / 5.5.5).

var modifier: int = -1
var cond: int = 0  ## DefEnums.Cond
var stat: int = 0
var delta_bp: int = 0
var layer: int = 0  ## 1 parent, 2 subfaction
var units: PackedInt32Array = PackedInt32Array()
var structures: PackedInt32Array = PackedInt32Array()


func copy_resolved() -> DefCondApplication:
	return DefBase.deep_copy(self) as DefCondApplication
