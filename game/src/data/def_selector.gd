class_name DefSelector
extends DefBase
## Compiled selector (bible / balance / inline; data_balance 4.2 / 5.4). The loader creates the shell (id, index);
## `DefResolver.compile_selector` fills the clauses.

var kind_mask: int = 0  ## bit per DefEnums.Kind: UNIT, STRUCTURE, WEAPON_ARCH, PROJECTILE
var unit_all: int = 0
var unit_any: int = 0
var unit_none: int = 0
var struct_all: int = 0
var struct_any: int = 0
var struct_none: int = 0
var weapon_all: int = 0
var weapon_any: int = 0
var weapon_none: int = 0
var proj_all: int = 0
var proj_any: int = 0
var proj_none: int = 0
var has_weapon_mask: int = 0
var explicit_units: PackedInt32Array = PackedInt32Array()
var explicit_structs: PackedInt32Array = PackedInt32Array()
var include_replacements: bool = false
var unit_class_mask: int = 0  ## 0 = any
var extra_superweapons: PackedInt32Array = PackedInt32Array()
var cond: int = 0
var unresolved: int = 0  ## 0 none, 1 carrier drones, 2 thermal-beam, 3 guided missiles


func _init() -> void:
	kind = DefEnums.Kind.SELECTOR
