class_name SimCompStats
extends SimComponent
## Slot `e.stats` (abilities 4.3), allocated for every UNIT / STRUCTURE / NEUTRAL: the local stat cache
## [SPEED, SIGHT, HEALTH], derived flags and the bound conditional effects. Ints only.

const HASH_EXEMPT: PackedStringArray = []

var vals: PackedInt32Array = PackedInt32Array()  ## effective [SPEED, SIGHT, HEALTH]
var extra: PackedInt32Array = PackedInt32Array()  ## temporary extra_bp per local stat
var dirty: int = 0  ## bit k = recompute local stat k
var flags: int = 0  ## SimAbilityConsts.DF_*
var hp_max_last: int = 0
var l3_version: int = 0
## Indices into SimEffectTable.effects of the conditional DefEffects bound to this entity (at most MAX_COND_FX).
var cond_fx: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	vals.resize(SimAbilityConsts.K_COUNT)
	extra.resize(SimAbilityConsts.K_COUNT)


func hash_into(buf: PackedInt32Array) -> void:
	buf.append_array(vals)
	buf.append_array(extra)
	buf.append(dirty)
	buf.append(flags)
	buf.append(hp_max_last)
	buf.append(l3_version)
	buf.append(cond_fx.size())
	buf.append_array(cond_fx)
