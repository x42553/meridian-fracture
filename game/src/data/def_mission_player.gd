class_name DefMissionPlayer
extends RefCounted
## One player of a mission (sorted by slot == pid).

var slot: int = 0  ## pid 0..7
var human: bool = false
var ui_name: String = ""
var roster: String = ""  ## roster id
var roster_idx: int = -1
var team: int = 1  ## 1..4
var color: int = 0  ## 0..11
var start_slot: int = 0  ## map spawn slot (unique per player)
var handicap: int = 100
var credits: int = -1  ## -1 = rules.start_credits
var ai_level: int = 1
var ai_style: int = 0
var ai_active: bool = true
var ai_aggr: int = 50
var start_mode: int = 0  ## 0 hq, 1 mcv, 2 none
var start_kinds: PackedInt32Array = PackedInt32Array()  ## 0 unit, 1 structure
var start_def_idx: PackedInt32Array = PackedInt32Array()
var start_count: PackedInt32Array = PackedInt32Array()
var start_dx: PackedInt32Array = PackedInt32Array()  ## cells from the player's spawn cell
var start_dy: PackedInt32Array = PackedInt32Array()
var start_placed: PackedInt32Array = PackedInt32Array()  ## placed-structure index or -1
