class_name SimSystem
extends RefCounted
## Base of every pipeline stage (sim_core 3.3.1). The default hooks do nothing, so a system implements only
## what it needs. Systems never store the SimWorld (a RefCounted cycle would leak): every hook receives it.
##
## Hook rules: (1) on_spawn may touch ONLY the system's own component; (2) hooks run in stage order 1 -> 11 for every
## system; (3) a hook must not spawn an entity of the kind being removed without a terminating condition (cleanup
## runs <= 16 rounds per tick); (4) kill hooks run at stage 11, not at the kill() call: in between the entity is
## F_DEAD, hp == 0, invisible to spatial queries and no longer counted, so systems that run in between skip it.

## Stage names in pipeline order (stage_no - 1 indexes it).
const STAGE_NAMES: PackedStringArray = ["commands", "production", "economy", "power", "orders", "movement", "abilities", "combat", "zones", "vision", "cleanup"]

## 1..11; the stage runs when stride == 1 or (world.tick + stride_offset) % stride == 0.
var stage_no: int = 0
var stride: int = 1
var stride_offset: int = 0


func system_name() -> String:
	if stage_no >= 1 and stage_no <= STAGE_NAMES.size():
		return STAGE_NAMES[stage_no - 1]
	return "stage%d" % stage_no


## Once, after ALL systems are constructed and players exist, BEFORE initial entities: create player components,
## register executors / handlers, replace world.fog.
func init_world(_world: SimWorld) -> void:
	pass


## The stage body.
func update(_world: SimWorld) -> void:
	pass


## Synchronously inside spawn_entity: fields set, e in by_id / spatial hash / counters and (STRUCTURE / NEUTRAL)
## already occupying its map footprint, SPAWNED already emitted, NOT yet in the lists. Allocate your component here.
func on_spawn(_world: SimWorld, _e: SimEntity) -> void:
	pass


## Stage 11, once per kill(), ascending id, BEFORE removal: wreck creation, cargo ejection, claims, EV_DEATH. May
## call world.kill() on others (processed in the same cleanup) and world.remove_deferred() to keep the corpse.
## `cause` is a SimWorld.Cause.
func on_dying(_world: SimWorld, _e: SimEntity, _cause: int, _killer_id: int, _killer_pid: int) -> void:
	pass


## Just before the entity leaves the world (dead or silently removed): drop every reference to it. `reason` is a
## SimEvent.REM_* code.
func on_remove(_world: SimWorld, _e: SimEntity, _reason: int) -> void:
	pass


func on_owner_changed(_world: SimWorld, _e: SimEntity, _old_owner: int) -> void:
	pass


## Clear queues, cancel superweapon, ...
func on_player_eliminated(_world: SimWorld, _pid: int) -> void:
	pass


## Veto a new order: return a SimCommand.Err (0 = OK, the default), e.g. "uncontrollable while packing", EMP.
func order_gate(_world: SimWorld, _e: SimEntity, _o: SimOrder) -> int:
	return 0


## Start of stage 11 after the defeat cascade: expire wrecks, finish dying entities, hand removals to the world.
func cleanup(_world: SimWorld) -> void:
	pass


## Append ALL authoritative system-private ints (fixed order, ints only). A stub appends nothing, which the world
## digests as Checksum.EMPTY_DIGEST.
func hash_state(_world: SimWorld, _buf: PackedInt32Array) -> void:
	pass


## DEBUG command modes >= 4 (needs rules.allow_debug): return -1 = "not my mode", else a SimCommand.Err (0 = done).
## Offered to the stages in order until one answers (vision: 4 reveal, combat: 5 set hp, economy: 6 charge).
func on_debug(_world: SimWorld, _pid: int, _mode: int, _target: int, _def_idx: int, _count: int, _x: int, _y: int) -> int:
	return -1
