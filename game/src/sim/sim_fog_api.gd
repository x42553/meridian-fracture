class_name SimFogApi
extends RefCounted
## Narrow visibility interface (sim_core 3.3.2). The default implementation makes everything visible and knows
## nothing else, so a world without the vision domain still runs; the vision domain replaces `world.fog` in its
## `init_world()`. Consumers call the world wrappers (`world.cell_visible / cell_explored / entity_visible`),
## never the stage object.


## Currently visible to pid's team (shared vision included).
func cell_visible(_pid: int, _cx: int, _cy: int) -> bool:
	return true


func cell_explored(_pid: int, _cx: int, _cy: int) -> bool:
	return true


## Fog AND camouflage / detection.
func entity_visible(_pid: int, _e: SimEntity) -> bool:
	return true


## Camouflage / detection only (fog ignored): omniscient AI reads.
func entity_revealed(_pid: int, _e: SimEntity) -> bool:
	return true


## w*h bytes: 0 shroud, 1 fog (explored), 2 visible -- for the view (the vision domain provides it).
func fog_bytes(_pid: int) -> PackedByteArray:
	return PackedByteArray()


## Increments whenever fog_bytes changed (texture upload gate).
func fog_version(_pid: int) -> int:
	return 0


## Remembered structures of pid: records {eid, def_idx, owner, x, y, facing, hp_pct, seen_tick} (vision's type).
func ghosts(_pid: int) -> Array:
	return []


## Increments on any change of ghosts(pid) (view upload gate).
func ghost_version(_pid: int) -> int:
	return 0


## pid has identified e as a decoy (detector contact).
func decoy_identified(_pid: int, _e: SimEntity) -> bool:
	return false
