class_name DefFaction
extends DefBase
## Faction: membership lists, trait grants, player-scope params (data_balance 4.2). All lists are index arrays.

var code: String = ""  ## "NAPC"
var baseline_units: PackedInt32Array = PackedInt32Array()  ## bible order
var structures: PackedInt32Array = PackedInt32Array()
var shared_research: PackedInt32Array = PackedInt32Array()
var shared_powers: PackedInt32Array = PackedInt32Array()
var vanilla_power: int = -1
var superweapon: int = -1
var vanilla_roster: int = -1
var sub_rosters: PackedInt32Array = PackedInt32Array()
var passive_modifiers: PackedInt32Array = PackedInt32Array()
var grants: Array[DefEffect] = []  ## GRANT_ABILITY records applied to roster clones at build time
var player_params: Dictionary = {}
var ui_motto: String = ""
var ui_lore: String = ""
var ui_identity: String = ""
var ui_opening: String = ""
var ui_counterplay: String = ""
var ui_traits: PackedStringArray = PackedStringArray()
var pres_palette: String = ""


func _init() -> void:
	kind = DefEnums.Kind.FACTION
