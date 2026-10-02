class_name DefAbility
extends RefCounted
## Ability instance or template (data_balance 4.2): `kind`, template ref, converted params with every default
## materialised. Templates live in GameData.abilities (id "ability.<kind>.<variant>", index >= 0); instances on a
## unit / structure have id "" and index -1.

var id: String = ""
var index: int = -1
var kind: int = 0  ## DefEnums.AbilityKind
var template: int = -1  ## template index the instance came from, else -1
var slot: int = -1  ## position in the owner's `abilities`
var stack_group: int = -1  ## index into GameData.stack_groups, -1 none
var params: Dictionary = {}  ## runtime-suffixed keys, sorted


func copy_resolved() -> DefAbility:
	return DefBase.deep_copy(self) as DefAbility
