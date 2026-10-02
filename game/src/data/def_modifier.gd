class_name DefModifier
extends DefBase
## Compiled bible typed modifier (data_balance 4.2).

var owner_is_roster: bool = false
var owner: int = -1  ## faction or roster index
var layer: int = 1  ## 1 parent, 2 subfaction
var stat: int = 0  ## DefEnums.Stat
var delta_bp: int = 0  ## bible percent x 100
var selector: int = -1
var cond: int = 0  ## DefEnums.Cond
var ui_source_text: String = ""


func _init() -> void:
	kind = DefEnums.Kind.MODIFIER
