class_name DefPower
extends DefBase
## Support power (data_balance 4.2). Cost, tier and cooldown are bible-only.

var faction: int = -1
var introduced_by: int = -1
var tier: int = 2
var cost: int = 0
var cooldown_t: int = 0
var requires_mask: int = 0
var requires_powered: bool = false
var target_mode: int = 0  ## DefEnums.TargetMode
var target_vision: int = 0  ## DefEnums.TargetVision
var radius: int = 0
var length: int = 0
var width: int = 0
var warning_t: int = 0
var actions: Array[DefPowerAction] = []
var ui_effect_text: String = ""


func _init() -> void:
	kind = DefEnums.Kind.POWER
