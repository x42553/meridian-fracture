class_name DefSuperweapon
extends DefBase
## Strategic weapon geometry, packets, timings (data_balance 4.2). Recharge and warning are bible-only.

var faction: int = -1
var launcher: int = -1  ## structure index
var requires_mask: int = 0
var recharge_t: int = 0
var warning_t: int = 0
var max_charges: int = 1
var starts_charged: bool = false
var target_vision: int = DefEnums.TargetVision.EXPLORED
var action_kind: int = 0  ## DefEnums.SwAction
var packets: Array[DefImpactPacket] = []
var zone: int = -1
var summon: int = -1
var summon_count: int = 0
var radius: int = 0
var duration_t: int = 0


func _init() -> void:
	kind = DefEnums.Kind.SUPERWEAPON


func copy_resolved() -> DefSuperweapon:
	return DefBase.deep_copy(self) as DefSuperweapon
