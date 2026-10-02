class_name UiPickData
extends RefCounted
## The fixture adapter's picking data (ui.md 4.4.3): structure-of-arrays of pick spheres, one slot per rendered entity.
## Entities the viewer cannot see (fog, camouflage, contained) are simply never added, so they can never be picked.
## Production picking is `ViewPicker`; this is the reference for its rules.

const F_STRUCTURE: int = 1
const F_GHOST: int = 2
const F_AIR: int = 4
const F_WRECK: int = 8
const F_NEUTRAL: int = 16
const F_OWN: int = 32
const F_ALLY: int = 64

var count: int = 0
var ids: PackedInt32Array = PackedInt32Array()
var pos: PackedVector3Array = PackedVector3Array()  ## rendered ground point under the entity (bar / bracket anchor base)
var center: PackedVector3Array = PackedVector3Array()  ## centre of the pick sphere (includes altitude for aircraft)
var radius: PackedFloat32Array = PackedFloat32Array()  ## pick radius, world metres
var height: PackedFloat32Array = PackedFloat32Array()  ## metres above `pos` where the 2D stand-in bar anchors
var flags: PackedInt32Array = PackedInt32Array()

var _slot: Dictionary = {}  ## eid -> slot


## count = 0; the arrays keep their capacity.
func clear() -> void:
	count = 0
	_slot.clear()


## Appends one entity and returns its slot.
func add(eid: int, p: Vector3, c: Vector3, r: float, h: float, fl: int) -> int:
	if count >= ids.size():
		var n: int = maxi(count * 2, 64)
		ids.resize(n)
		pos.resize(n)
		center.resize(n)
		radius.resize(n)
		height.resize(n)
		flags.resize(n)
	ids[count] = eid
	pos[count] = p
	center[count] = c
	radius[count] = r
	height[count] = h
	flags[count] = fl
	_slot[eid] = count
	count += 1
	return count - 1


## Slot of `eid`, -1 when not rendered; O(1).
func slot_of(eid: int) -> int:
	return int(_slot.get(eid, -1))


## True when slot `i` passes a `UiViewPort.PICK_*` filter (kind, relation, air and ghost bits; an unset group of bits allows all).
func allows(i: int, filter: int) -> bool:
	var f: int = flags[i]
	if (f & F_GHOST) != 0 and (filter & 128) == 0:
		return false
	if (f & F_AIR) != 0 and (filter & 64) == 0:
		return false
	var km: int = filter & 7  # PICK_UNITS | PICK_STRUCTURES | PICK_WRECKS
	if km != 0:
		var bit: int = 1
		if (f & F_STRUCTURE) != 0:
			bit = 2
		elif (f & F_WRECK) != 0:
			bit = 4
		if (km & bit) == 0:
			return false
	var rm: int = filter & (8 | 16 | 32)  # PICK_OWN | PICK_ENEMY | PICK_NEUTRAL
	if rm != 0:
		var rbit: int = 16
		if (f & (F_OWN | F_ALLY)) != 0:
			rbit = 8
		elif (f & F_NEUTRAL) != 0:
			rbit = 32
		if (rm & rbit) == 0:
			return false
	return true
