class_name DefMissionCond
extends RefCounted
## One node of a mission trigger's condition tree (mission schema `when`, see DefMission). A node is either a combinator
## (OP_ALL / OP_ANY / OP_NOT with `children`) or a leaf (every other op). Ints only; every cross reference is an index
## resolved at load time (-1 = none). Evaluated by SimMissionConds.

enum Op {
	ALL = 0, ANY = 1, NOT = 2,
	TIME = 3,  ## world.tick (cmp) value
	TIMER = 4,  ## timer `ref` has expired
	OBJECTIVE = 5,  ## objective `ref` is in state `state` (SimMissionConst.OBJ_*)
	COUNT = 6,  ## entities of owner (of_kind / def_idx / tag_mask / area) (cmp) value
	STRUCTURE = 7,  ## `state` (STRUCT_*) of structure def_idx for owner, or of the placed structure `ref`
	AREA_LEFT = 8,  ## owner had units in `area` and now has none
	CREDITS = 9,  ## owner's credits (cmp) value (summed over the selector)
	RESEARCH = 10,  ## owner researched research def `ref`
	POWER = 11,  ## owner's power supply - demand (cmp) value
	SUPPORT_POWER = 12,  ## owner's support power slot `ref` is READY (state 0) or USED (state 1; uses >= value)
	SUPERWEAPON = 13,  ## owner's superweapon FIRED (state 0) or READY (state 1)
	DEFEATED = 14,  ## every player of the selector is eliminated
	NO_ASSETS = 15,  ## every player of the selector has no structure and no MCV-class unit
	WAVE = 16,  ## wave `ref` SPAWNED (state 0) or CLEARED (state 1)
	TRIGGER = 17,  ## trigger `ref` has fired (cmp) value times
}
enum Cmp { GE = 0, LE = 1, EQ = 2, GT = 3, LT = 4, NE = 5 }
const OP_NAMES: PackedStringArray = ["all", "any", "not", "time", "timer", "objective", "count", "structure", "area_left", "credits",
	"research", "power", "support_power", "superweapon", "defeated", "no_assets", "wave", "trigger"]
const CMP_NAMES: PackedStringArray = [">=", "<=", "==", ">", "<", "!="]
## Owner selector modes (DefMissionCond.owner_mode / DefMissionAction.owner_mode).
const OWN_PID: int = 0  ## owner_val = pid
const OWN_NEUTRAL: int = 1
const OWN_TEAM: int = 2  ## owner_val = team id
const OWN_ENEMIES_OF: int = 3  ## players whose team differs from the team of pid owner_val
const OWN_ALLIES_OF: int = 4  ## players on the team of pid owner_val, owner_val itself excluded
const OWN_ALL: int = 5  ## every player
## Entity class of a count (of_kind).
const OF_UNIT: int = 0
const OF_STRUCTURE: int = 1
const OF_ANY: int = 2  ## units + structures (def_idx / tag_mask must then be -1 / 0)

var op: int = 0
var children: Array[DefMissionCond] = []
var owner_mode: int = 0
var owner_val: int = 0
var of_kind: int = 0
var def_idx: int = -1  ## unit or structure index according to of_kind (STRUCTURE: structure index)
var tag_mask: int = 0  ## DefTags mask of the namespace of of_kind (0 = any)
var cmp: int = 0
var value: int = 0
var area: int = -1
var ref: int = -1
var state: int = 0


static func is_combinator(o: int) -> bool:
	return o == Op.ALL or o == Op.ANY or o == Op.NOT
