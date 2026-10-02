class_name DefStructure
extends DefBase
## Structure definition (base and resolved clone; data_balance 4.2).

var faction: int = -1
var requires: PackedInt32Array = PackedInt32Array()
var requires_mask: int = 0
var cost: int = 0
var build_ticks: int = 0  ## 0 with SF_NO_BUILD
var power: int = 0  ## signed: + supply, - demand
var health: int = 0
var armor_class: int = 0
var size_class: int = 0  ## s1..s4
var radius: int = 0  ## u
var fp_w: int = 1  ## cells
var fp_h: int = 1
var fp_mask: PackedByteArray = PackedByteArray()  ## empty = solid rectangle, else row-major fp_w*fp_h, 1 = blocked
var exit_dx: int = 0
var exit_dy: int = 0
var sight: int = 0
var flags: int = 0  ## DefEnums.SF_*
var queue_kind: int = 0
var queues: int = 1
var max_per_player: int = 0  ## 0 = unlimited
var place_mask: int = 0  ## DefEnums.PLACE_*
var build_radius: int = 0  ## u (HQ = 8 cells)
var deploy_unit: int = -1  ## unit index (HQ <- MCV)
var deploy_t: int = 0
var starts_deployed: bool = false
var superweapon: int = -1
var repair_rate_bp: int = 10000
var repair_cost_bp: int = 5000
var sell_bp: int = 5000
var detect_radius: int = 0
var pads: int = 0
var weapon_tags: int = 0
var weapons: Array[DefWeaponSlot] = []
var abilities: Array[DefAbility] = []
var ability_slot_of_kind: PackedInt32Array = PackedInt32Array()
var ability_mask: int = 0
var cond_vals: Array[DefCondVal] = []
var pres_recipe: String = ""
var pres_icon: String = ""
var pres_snd_profile: String = ""


func _init() -> void:
	kind = DefEnums.Kind.STRUCTURE


func copy_resolved() -> DefStructure:
	return DefBase.deep_copy(self) as DefStructure


func ability_of(ability_kind: int) -> DefAbility:
	if ability_slot_of_kind.size() <= ability_kind or ability_kind < 0:
		return null
	var s: int = ability_slot_of_kind[ability_kind]
	return abilities[s] if s >= 0 and s < abilities.size() else null
