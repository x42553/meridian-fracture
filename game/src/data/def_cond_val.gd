class_name DefCondVal
extends RefCounted
## Conditional stat variant {stat, cond, value} (e.g. Gate Guard damage inside a civilian garrison).

var stat: int = 0  ## DefEnums.Stat
var cond: int = 0  ## DefEnums.Cond
var value: int = 0  ## the resolved value when the condition holds


func copy_resolved() -> DefCondVal:
	return DefBase.deep_copy(self) as DefCondVal
