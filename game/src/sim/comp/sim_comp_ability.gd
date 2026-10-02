class_name SimCompAbility
extends SimComponent
## Slot `e.abil` (abilities 4.2), allocated only for entities whose def has an ability kind executed by the abilities
## domain, a timed effect, a bound condition or a watch need. Ints and packed int arrays only. Every field is
## authoritative and hashed.

const HASH_EXEMPT: PackedStringArray = []

var n_slots: int = 0
## MAX_SLOTS * SLOT_STRIDE ints: [kind, ab_idx, state, t_end, n, aux0, aux1, sflags] per slot.
var slots: PackedInt32Array = PackedInt32Array()
## MAX_FX * FX_STRIDE ints: [fx_idx, src_key, expire_tick, aux]; fx_idx -1 = empty.
var fx: PackedInt32Array = PackedInt32Array()
var n_fx: int = 0
var cond_bits: int = 0  ## bit i = bound conditional effect stats.cond_fx[i] currently true
var cond_ext: int = 0  ## bit c = condition code c currently true (pushed by SimMode / SimTransport / auras / pulled by the watch pass)
var aura_bits: int = 0
var watch: int = 0  ## SimAbilityConsts.WF_*
var last_cell: int = -1
var spawn_tick: int = 0
var heal_frac: int = 0
var repair_frac: int = 0
var granted_mask: int = 0
var tn_target: int = -1
var disembark_until: int = 0
var moved_t: int = 0  ## last tick the entity was seen moving by the camouflage pass (spawn tick - 1 at creation)


func _init() -> void:
	slots.resize(SimAbilityConsts.MAX_SLOTS * SimAbilityConsts.SLOT_STRIDE)
	fx.resize(SimAbilityConsts.MAX_FX * SimAbilityConsts.FX_STRIDE)
	fx.fill(-1)


## Slot index of the ability kind, -1 when absent.
func slot_of_kind(kind: int) -> int:
	for s: int in n_slots:
		if slots[s * SimAbilityConsts.SLOT_STRIDE] == kind:
			return s
	return -1


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(n_slots)
	buf.append_array(slots)
	buf.append_array(fx)
	buf.append(n_fx)
	buf.append(cond_bits)
	buf.append(cond_ext)
	buf.append(aura_bits)
	buf.append(watch)
	buf.append(last_cell)
	buf.append(spawn_tick)
	buf.append(heal_frac)
	buf.append(repair_frac)
	buf.append(granted_mask)
	buf.append(tn_target)
	buf.append(disembark_until)
	buf.append(moved_t)
