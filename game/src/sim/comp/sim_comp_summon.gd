class_name SimCompSummon
extends SimComponent
## Slot `e.summon` (abilities 4.6): the record of a temporary unit created through SimSummons (UAV, drones, balloon,
## delivery aircraft, pontoon, zone bodies, decoys, Tempest drones, Dragonfall capsules and engines, the Lagos repair
## drone). The lifetime lives in SimEntity.expire_tick (single copy); the flags mirror onto the kernel flags, the combat
## flags and the economy flags at spawn. Ints only; every field is authoritative and hashed.

const HASH_EXEMPT: PackedStringArray = []

var parent_eid: int = -1  ## summoner / owner entity, -1 none
var group_id: int = 0  ## Dragonfall trio, Tempest swarm: the power / superweapon activation that made it
var flags: int = 0  ## SimZoneConsts.SM_*
var driver: int = 0  ## SimZoneConsts.SD_*
var ax: int = 0  ## attack area centre / orbit centre (units)
var ay: int = 0
var ar: int = 0  ## attack area radius / orbit radius (units)
var state: int = 0  ## SimZoneConsts.SS_*
var t0: int = 0  ## tick of the state entry
var t1: int = 0  ## tick the state ends (capsule assembly), 0 none
var effect_idx: int = -1  ## engine def (capsule) or fx table index of a bound effect, -1 none
var zone_id: int = 0  ## zone the entity is the body / a decoy of (0 none)
var src_kind: int = 0  ## 0 power, 1 superweapon, 2 unit ability
var src_idx: int = -1
var src_pid: int = -1
var angle: int = 0  ## orbit phase (binary angle)
var target_eid: int = 0  ## current work target (the Lagos drone's patient), 0 none


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(parent_eid)
	buf.append(group_id)
	buf.append(flags)
	buf.append(driver)
	buf.append(ax)
	buf.append(ay)
	buf.append(ar)
	buf.append(state)
	buf.append(t0)
	buf.append(t1)
	buf.append(effect_idx)
	buf.append(zone_id)
	buf.append(src_kind)
	buf.append(src_idx)
	buf.append(src_pid)
	buf.append(angle)
	buf.append(target_eid)
