class_name SimZone
extends RefCounted
## One zone instance (abilities 4.7): smoke, cover, shelter, debris, repair station, sensor puck, reveal source, decoy
## group, Trident dome, buff marker or warning marker. Ints and packed int arrays only; every field is authoritative
## and hashed. Owned and written by SimZoneSystem; presentation reads `SimZoneSystem.active_zones()`.
##
## Geometry: SHAPE_DISC uses (x, y) and `radius`. SHAPE_CAPSULE uses the segment (ax, ay)-(bx, by) and `radius` as the
## half width; (x, y) is its centre (length = 2 x dist(centre, b)).

const HASH_EXEMPT: PackedStringArray = []

var id: int = 0  ## monotonic, never reused
var zone_idx: int = -1  ## DefZone template index (-1 for warnings)
var kind: int = 0  ## DefEnums.ZoneKind, or SimZoneConsts.ZK_WARNING
var shape: int = 0  ## DefEnums.ZoneShape (0 disc, 1 capsule)
var owner_pid: int = -1
var team: int = -1
var x: int = 0
var y: int = 0
var ax: int = 0
var ay: int = 0
var bx: int = 0
var by: int = 0
var radius: int = 0  ## units (disc radius or capsule half width)
var angle: int = 0
var affects: int = 3  ## DefEnums.AFFECTS_*
var membership: int = 0  ## DefEnums.Membership
var state: int = SimZoneConsts.ZS_ACTIVE
var t_start: int = 0
var t_warn_end: int = 0  ## end of the WARMUP state (== t_start when there is none)
var t_end: int = 0
var charges: int = 0  ## Trident
var body_eid: int = -1  ## shootable body entity, -1 none
var bind_eid: int = -1  ## the zone ends when this entity dies (and follows it when ZF_FOLLOW)
var src_eid: int = -1  ## the entity that created the zone (builder, caster, launcher)
var vis_handle: int = -1  ## temporary vision source, -1 none
var slot: int = -1  ## interception slot 0..7, -1 none
var power_idx: int = -1  ## support power (+1 based in events) or -1
var pa: int = 0  ## kind parameter: intercept packet cost / warning kind
var pb: int = 0  ## kind parameter: intercept reduction bp / warning width
var occ_max: int = 0  ## cover / shelter occupants
var n_members: int = 0
var members: PackedInt32Array = PackedInt32Array()  ## ascending ids (decoys: the decoy entities), capacity MAX_MEMBERS
var excl: PackedInt32Array = PackedInt32Array()  ## entities that left a stop-on-move repair zone
var warn_vis: int = 0  ## player bit mask that sees a warning marker
var flags: int = 0


func has_flag(f: int) -> bool:
	return (flags & f) != 0


func is_active() -> bool:
	return state == SimZoneConsts.ZS_ACTIVE


## Centre of the zone (capsule: the middle of the segment).
func center_x() -> int:
	return x


func center_y() -> int:
	return y


## Half length of a capsule (0 for discs), in units.
func half_length() -> int:
	if shape == 0:
		return 0
	var dx: int = bx - x
	var dy: int = by - y
	return Fp.isqrt(dx * dx + dy * dy)


func is_member(eid: int) -> bool:
	var lo: int = 0
	var hi: int = members.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if members[mid] < eid:
			lo = mid + 1
		else:
			hi = mid
	return lo < members.size() and members[lo] == eid


func contains_point(px: int, py: int) -> bool:
	if shape == DefEnums.ZoneShape.LINE:
		return SimShape.capsule_contains(ax, ay, bx, by, radius, px, py)
	return SimShape.circle_contains(x, y, radius, px, py)


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(id)
	buf.append(zone_idx)
	buf.append(kind)
	buf.append(shape)
	buf.append(owner_pid)
	buf.append(team)
	buf.append(x)
	buf.append(y)
	buf.append(ax)
	buf.append(ay)
	buf.append(bx)
	buf.append(by)
	buf.append(radius)
	buf.append(angle)
	buf.append(affects)
	buf.append(membership)
	buf.append(state)
	buf.append(t_start)
	buf.append(t_warn_end)
	buf.append(t_end)
	buf.append(charges)
	buf.append(body_eid)
	buf.append(bind_eid)
	buf.append(src_eid)
	buf.append(vis_handle)
	buf.append(slot)
	buf.append(power_idx)
	buf.append(pa)
	buf.append(pb)
	buf.append(occ_max)
	buf.append(n_members)
	buf.append(members.size())
	buf.append_array(members)
	buf.append(excl.size())
	buf.append_array(excl)
	buf.append(warn_vis)
	buf.append(flags)
