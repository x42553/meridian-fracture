class_name SimSummonBrain
extends RefCounted
## Read side of the autonomous superweapon summons (economy 5.21, task EC3B / E8): the Tempest drone swarm and the Dragonfall
## capsules / engines. The behaviour itself (the drivers SD_SWARM, SD_CAPSULE, SD_ENGINE: fly to the zone, attack ground and
## surface enemies inside it for 400 ticks from the first arrival, unfold after 5 s, advance on the nearest enemy structure,
## expire silently, die with the launcher's warning) is SimSummons.step, run by the zone system (AB3); this class gives the AI,
## the UI and the tests one place to ask what is out there. Stateless, integer-only, never mutates.

const PHASE_NONE: int = 0
const PHASE_APPROACH: int = 1  ## drones flying to the zone / capsule not yet landed
const PHASE_ATTACK: int = 2  ## drones fighting / engines advancing
const PHASE_ASSEMBLING: int = 3  ## capsules unfolding (attackable, hp 400)


## Live Tempest drones of `pid` (ascending entity id).
static func swarm_drones(world: SimWorld, pid: int, out: PackedInt32Array) -> void:
	_collect(world, pid, SimZoneConsts.SD_SWARM, out)


## Live Dragonfall capsules of `pid`.
static func capsules(world: SimWorld, pid: int, out: PackedInt32Array) -> void:
	_collect(world, pid, SimZoneConsts.SD_CAPSULE, out)


## Live Dragonfall engines of `pid`.
static func engines(world: SimWorld, pid: int, out: PackedInt32Array) -> void:
	_collect(world, pid, SimZoneConsts.SD_ENGINE, out)


static func _collect(world: SimWorld, pid: int, driver: int, out: PackedInt32Array) -> void:
	out.resize(0)
	for id: int in world.zones.sum_ids:
		var e: SimEntity = world.by_id[id]
		if e != null and e.owner == pid and (e.flags & SimFlags.F_GONE) == 0 and e.summon != null and e.summon.driver == driver:
			out.append(id)


## PHASE_* of an autonomous summon (PHASE_NONE for anything else).
static func phase_of(e: SimEntity) -> int:
	if e == null or e.summon == null:
		return PHASE_NONE
	match e.summon.driver:
		SimZoneConsts.SD_SWARM:
			return PHASE_ATTACK if e.summon.state == SimZoneConsts.SS_ATTACK else PHASE_APPROACH
		SimZoneConsts.SD_CAPSULE:
			return PHASE_ASSEMBLING
		SimZoneConsts.SD_ENGINE:
			return PHASE_ATTACK
	return PHASE_NONE


## Absolute tick the summon disappears (0 = no lifetime). Drones: 400 ticks after their first arrival (hard cap 1200 after
## spawn) - not known before they arrive; engines: 1200 ticks after they unfold.
static func expires_at(e: SimEntity) -> int:
	return e.expire_tick if e != null and e.summon != null else 0


## The zone the autonomous summon works in: centre x, y and radius (units), false when `e` is not one.
static func work_area(e: SimEntity, out: PackedInt32Array) -> bool:
	if e == null or e.summon == null or phase_of(e) == PHASE_NONE:
		return false
	out.resize(0)
	out.append(e.summon.ax)
	out.append(e.summon.ay)
	out.append(e.summon.ar)
	return true
