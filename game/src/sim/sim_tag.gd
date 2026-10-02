class_name SimTag
extends RefCounted
## Spatial-hash tag layout (sim_core 4.10): one-hot fields, so `need` / `avoid` masks express set logic.
##   bits 0-4 kind (1 << kind) | bit 5 ALIVE | bits 6-9 layer (1 << (6 + layer)) | bits 10-18 owner slot (1 << (10 + slot))
## There are no team bits: teams are arbitrary ids up to 15, so the world precomputes per-owner ally masks and
## `world.non_enemy_mask(pid)` is the `avoid` mask of "enemies only". Example, alive enemy ground units of player 0:
##   need = ALIVE | kind_bit(SimEntity.Kind.UNIT) | layer_bit(SimEntity.Layer.GROUND); avoid = world.non_enemy_mask(0)

const ALL_KINDS: int = 31
const ALIVE: int = 1 << 5
const ALL_LAYERS: int = 0xF << 6
const ALL_OWNERS: int = 0x1FF << 10
## Owner slot 8 (owner -1).
const NEUTRAL_OWNER: int = 1 << 18


## Full tag of an entity; ALIVE is cleared as soon as F_DEAD or F_REMOVING is set.
static func of(e: SimEntity) -> int:
	var t: int = (1 << e.kind) | (1 << (6 + e.layer)) | (1 << (10 + SimConfig.slot_of(e.owner)))
	if (e.flags & SimFlags.F_GONE) == 0:
		t |= ALIVE
	return t


static func kind_bit(kind: int) -> int:
	return 1 << kind


static func layer_bit(layer: int) -> int:
	return 1 << (6 + layer)


## Owner bit of a pid (0..7) or -1 (neutral, bit 18).
static func owner_bit(owner: int) -> int:
	return 1 << (10 + SimConfig.slot_of(owner))
