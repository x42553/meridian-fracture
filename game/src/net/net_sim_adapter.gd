class_name NetSimAdapter
extends RefCounted
## The seam between net and the simulation (docs/spec/net.md 3.3). Abstract: NetSimAdapterWorld forwards to a
## real SimWorld, NetSimAdapterFake is the test double. Net never touches sim internals except through this
## class. Every base method reports NOT IMPLEMENTED and returns a neutral value.


## The underlying SimWorld / fake, for view and AI reads.
func world() -> RefCounted:
	_unimplemented()
	return null


## 0 right after world construction; the number of completed ticks.
func current_tick() -> int:
	_unimplemented()
	return 0


## Queues a command for the NEXT step(); applied by the command system in that tick. Tolerates malformed ints
## deterministically (ignore + count).
func submit_command(_pid: int, _ints: PackedInt32Array) -> void:
	_unimplemented()


## Runs exactly ONE tick of the pipeline, including the every-20-ticks checksum snapshot.
func step() -> void:
	_unimplemented()


## u32 snapshot taken at the end of `tick` (tick % 20 == 0); -1 if not retained (>= 64 snapshots are kept).
func checksum_at(_tick: int) -> int:
	_unimplemented()
	return -1


## Per-system sub-checksums of that snapshot (same length and order on every peer); empty when not retained.
func checksum_parts_at(_tick: int) -> PackedInt32Array:
	_unimplemented()
	return PackedInt32Array()


func checksum_part_names() -> PackedStringArray:
	_unimplemented()
	return PackedStringArray()


## Full checksum of the current state (tick 0 and match end).
func checksum_now() -> int:
	_unimplemented()
	return 0


## u32 hash of all static + initial map layers (compared in LOAD_DONE).
func map_hash() -> int:
	_unimplemented()
	return 0


func is_match_over() -> bool:
	_unimplemented()
	return false


## {winner_team: int (-1 = none), reason: int}.
func match_result() -> Dictionary:
	_unimplemented()
	return {"winner_team": -1, "reason": 0}


## false when defeated / resigned (the AI runner stops thinking for them).
func is_player_active(_pid: int) -> bool:
	_unimplemented()
	return false


## Deterministic text dump (entities sorted by id) for desync diffs.
func dump_state() -> String:
	_unimplemented()
	return ""


func clear_events() -> void:
	_unimplemented()


func _unimplemented() -> void:
	push_error("NOT IMPLEMENTED")
