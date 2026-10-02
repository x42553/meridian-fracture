class_name DefMissionObjective
extends RefCounted
## A mission objective (declaration order = index). States are SimMissionConst.OBJ_*.

enum Kind { PRIMARY = 0, SECONDARY = 1, HIDDEN = 2 }
const KIND_NAMES: PackedStringArray = ["primary", "secondary", "hidden"]
const STATE_NAMES: PackedStringArray = ["hidden", "active", "completed", "failed"]

var id: String = ""
var kind: int = 0
var initial: int = 1
var ui_text: String = ""
