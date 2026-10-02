class_name DefEffect
extends RefCounted
## One effect record (research, faction traits, zone effects, power global effects, superweapon secondary effects;
## data_balance 4.2 / 5.10.3). Op-specific fields are documented in data_balance 7.5.

var op: int = 0  ## DefEnums.EffectOp
var stat: int = -1  ## DefEnums.Stat
var delta_bp: int = 0  ## STAT_MOD delta / RESIST_MOD reduction
var group_mask: int = 0  ## RESIST_MOD ResistGroup bits; 0 = every weapon group except EMP
var fire_mode_mask: int = 0  ## bit per FireMode; 0 = any
var frontal_arc_a: int = 0  ## 0 = none
var selector: int = -1  ## DefSelector index, -1 none
var cond_codes: PackedInt32Array = PackedInt32Array()
var cond_params: Array[Dictionary] = []  ## parallel to cond_codes
var duration_t: int = 0  ## 0 = permanent
var stack_group: int = -1  ## index into GameData.stack_groups
var membership: int = 0  ## DefEnums.Membership
var scope: int = 0  ## DefEnums.ParamScope
var param_op: int = 0  ## DefEnums.ParamOp
var key: String = ""  ## runtime key, e.g. cooldown_t
var value: int = 0
var ability_kind: int = -1
var ability: DefAbility = null  ## GRANT_ABILITY payload
var flag: String = ""
var filter: Dictionary = {}
var params: Dictionary = {}


func copy_resolved() -> DefEffect:
	return DefBase.deep_copy(self) as DefEffect
