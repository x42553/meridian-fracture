class_name DefNeutral
extends DefBase
## Neutral map structure (garrison, capturable, deposit; data_balance 4.2).

var neutral_kind: int = 0  ## DefEnums.NeutralKind
var health: int = 0
var armor_class: int = 0
var fp_w: int = 1
var fp_h: int = 1
var radius: int = 0  ## u, derived from the footprint (the kernel reads it)
var sight: int = 0
var capturable: bool = false
var capture_t: int = 0
var garrison_squads: int = 0
var reward: Dictionary = {}  ## credits_cr, power_n, reveal_radius_u, income_mcpt; deposits: credits_per_cell_cr, cells_n
var pres_recipe: String = ""


func _init() -> void:
	kind = DefEnums.Kind.NEUTRAL
