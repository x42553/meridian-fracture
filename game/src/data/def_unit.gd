class_name DefUnit
extends DefBase
## Unit / service unit / summon / drone definition (base and roster-resolved clone; data_balance 4.2).
## Cross references are indices (-1 = none). Distances u, speeds upt, times t (ticks) or mt, percentages bp.

var faction: int = -1  ## DefFaction index; -1 shared
var introduced_by: int = -1  ## roster index (unique units)
var replaces: int = -1  ## unit index this unit replaces
var replaced_by: PackedInt32Array = PackedInt32Array()  ## derived, ascending
var unit_class: int = 1  ## DefEnums.UnitClass
var tier: int = 0
var producer: int = -1  ## structure index
var requires: PackedInt32Array = PackedInt32Array()  ## structure indices, ascending
var requires_mask: int = 0  ## bit i = structure index i
var cost: int = 0  ## credits; -1 when not purchasable; DRONE = replacement cost
var build_ticks: int = 0
var pop: int = 1  ## unit-cap weight (0 = exempt)
var health: int = 0
var armor_class: int = 0
var move_class: int = 0
var size_class: int = 0
var layer_mask: int = 1
var home_layer: int = 0
var speed: int = 0  ## upt on nominal terrain; 0 = immobile
var deep_speed_bp: int = 0  ## per-unit DEEP multiplier override, 0 = use DefMoveTable
var water_mult_bp: int = 10000  ## multiplier on SHALLOW/DEEP cells (carries resolved ON_WATER modifiers)
var accel_t: int = 0
var turn_rate: int = 0  ## apt
var radius: int = 0  ## u
var sight: int = 0  ## u
var flags: int = 0  ## DefEnums.UF_*
var repair_cost_bp: int = 5000
var lifetime_t: int = 0  ## 0 = permanent
var rearm_t: int = 0  ## aircraft pad rearm ticks
var weapons: Array[DefWeaponSlot] = []
var abilities: Array[DefAbility] = []
var ability_slot_of_kind: PackedInt32Array = PackedInt32Array()  ## size AbilityKind.COUNT, slot or -1
var cond_vals: Array[DefCondVal] = []
# derived caches (P5)
var ability_mask: int = 0
var detect_radius: int = 0
var cloak_delay_t: int = 0
var max_range: int = 0
var min_range: int = 0
var attack_layer_mask: int = 0
var weapon_tags: int = 0
var transport_squads: int = 0
var transport_vehicles: int = 0
var speed_water: int = 0  ## speed on deep water via DefMoveTable.effective_speed
# presentation (not hashed)
var pres_recipe: String = ""
var pres_icon: String = ""
var pres_snd_profile: String = ""
var pres_ai_role: String = ""
var pres_scale_bp: int = 10000


func _init() -> void:
	kind = DefEnums.Kind.UNIT


func copy_resolved() -> DefUnit:
	return DefBase.deep_copy(self) as DefUnit


## The ability of `ability_kind` or null.
func ability_of(ability_kind: int) -> DefAbility:
	if ability_slot_of_kind.size() <= ability_kind or ability_kind < 0:
		return null
	var s: int = ability_slot_of_kind[ability_kind]
	return abilities[s] if s >= 0 and s < abilities.size() else null


func has_ability(ability_kind: int) -> bool:
	return ability_kind >= 0 and ability_kind < 62 and (ability_mask >> ability_kind) & 1 == 1
