class_name DefResearch
extends DefBase
## Research upgrade (bible fields + effects; data_balance 4.2).

var faction: int = -1
var introduced_by: int = -1  ## roster index
var tier: int = 2  ## 2 | 3
var cost: int = 0
var time_t: int = 0
var requires_mask: int = 0
var inherited: bool = false
var effects: Array[DefEffect] = []
var ui_effect_text: String = ""


func _init() -> void:
	kind = DefEnums.Kind.RESEARCH
