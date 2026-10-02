class_name ViewDef
extends RefCounted
## Plain presentation record of one sim def (unit, structure, zone, neutral, wreck source). Built only by
## ViewDefAdapter, which is the one view file that reads Def* fields; every other view file reads this record.
## Floats are metres, integers are sim units unless noted. Presentation only.

var kind: int = 0  ## SimEntity.Kind
var def_idx: int = -1  ## sim index (per-kind table) the record was built from
var id: String = ""  ## bible / balance id ("unit.napc.guardian")
var faction_code: String = ""  ## "napc"; "" = shared or unknown
var recipe_id: StringName = &""  ## pres_recipe (defaults to the def id)
var icon_id: StringName = &""  ## pres_icon (defaults to the def id)
var scale_bp: int = 10000  ## pres_scale_bp
var unit_class: int = 0  ## DefEnums.UnitClass (units)
var move_class: int = 0  ## DefEnums.MoveClass (units)
var size_class: int = 0  ## DefEnums.SizeClass
var layer: int = 0  ## SimEntity.Layer at spawn
var radius_m: float = 0.0
var fp_w: int = 1  ## structures / neutrals: footprint cells of orientation 0
var fp_h: int = 1
var rotatable: bool = false
var needs_power: bool = false
var is_hq: bool = false
var is_defense: bool = false
var cargo_cap: int = 0  ## collector capacity in credits (0 = not a collector)
var warch: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])  ## DefWeaponArch index per mount 0..3, -1 = none
## Anchors in metres from the footprint centre (+Z = south); pads are (x, z) pairs.
var door_cx: float = 0.0
var door_cz: float = 0.0
var exit_dir: int = 1024  ## facing units of the exit direction (1024 = south)
var dock_cx: float = 0.0
var dock_cz: float = 0.0
var dock_dir: int = 1024
var pads: PackedFloat32Array = PackedFloat32Array()
# zones only
var zone_kind: int = 0
var zone_shape: int = 0
var zone_radius_m: float = 0.0
var zone_length_m: float = 0.0
var zone_width_m: float = 0.0
var visible_to_enemy: bool = false
var placeholder: bool = false  ## true for the record returned for an unknown def
