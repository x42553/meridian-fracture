class_name DefPowerAction
extends RefCounted
## One action of a support power (data_balance 4.2).

var op: int = 0  ## DefEnums.PowerOp
var zone: int = -1
var summon: int = -1  ## unit index
var count: int = 0
var radius: int = 0
var duration_t: int = 0
var warning_t: int = 0
var effects: Array[DefEffect] = []
var impacts: Array[DefImpactPacket] = []
var params: Dictionary = {}


func copy_resolved() -> DefPowerAction:
	return DefBase.deep_copy(self) as DefPowerAction
