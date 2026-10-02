class_name DefZone
extends DefBase
## Area-effect / decoy / puck / shelter / smoke / repair-station template (data_balance 4.2).

var zone_kind: int = 0  ## DefEnums.ZoneKind
var shape: int = 0  ## DefEnums.ZoneShape
var radius: int = 0
var length: int = 0
var width: int = 0
var duration_t: int = 0
var affects: int = 3  ## DefEnums.AFFECTS_*
var follow_source: bool = false
var hp: int = 0  ## 0 = indestructible
var target_mask: int = 0
var visible_to_enemy: bool = false
var max_per_owner: int = 0  ## 0 = unlimited
var effects: Array[DefEffect] = []
var pres_recipe: String = ""


func _init() -> void:
	kind = DefEnums.Kind.ZONE
