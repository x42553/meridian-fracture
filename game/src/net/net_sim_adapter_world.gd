class_name NetSimAdapterWorld
extends NetSimAdapter
## The real adapter: a thin forwarding shim over a SimWorld (docs/spec/net.md 3.3). The only net file that
## changes if the sim renames something. Real matches must build the world through
## SimMatchSetup.create_world (start-area reveal, footprints) before wrapping it here.

var _w: SimWorld = null
## Number of empty command arrays ignored by submit_command (identical on every peer).
var malformed_count: int = 0


func _init(world_: SimWorld = null) -> void:
	_w = world_


func world() -> RefCounted:
	return _w


func current_tick() -> int:
	return _w.tick


func submit_command(pid: int, ints: PackedInt32Array) -> void:
	if ints.is_empty() or ints.size() > NetProtocol.MAX_CMD_INTS:
		malformed_count += 1
		return
	_w.submit_raw(pid, ints)


func step() -> void:
	_w.step()


func checksum_at(tick: int) -> int:
	return _w.checksum_at(tick)


func checksum_parts_at(tick: int) -> PackedInt32Array:
	return _w.checksum_parts_at(tick)


func checksum_part_names() -> PackedStringArray:
	return SimWorld.CHECKSUM_PART_NAMES


func checksum_now() -> int:
	return _w.checksum()


func map_hash() -> int:
	return _w.map_hash()


func is_match_over() -> bool:
	return _w.is_match_over()


func match_result() -> Dictionary:
	return _w.match_result()


func is_player_active(pid: int) -> bool:
	return _w.is_player_active(pid)


func dump_state() -> String:
	return _w.dump_state()


func clear_events() -> void:
	_w.clear_events()
