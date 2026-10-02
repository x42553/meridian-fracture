class_name UiNetPortLoopback
extends UiNetPort
## Single-player / offline adapter: commands go straight into a `SimWorld` (`submit_raw`, executed by the next
## `step()`), stamped with the local pid. It stands in for `NetSession` until the net module lands and is what
## the tests use to prove that UI commands have the expected sim effect. Chat, pings and pause are no-ops.

const MAX_INTS: int = 1024
const MAX_PENDING: int = 256

var _world: SimWorld = null
var _pid: int = 0
var _pending: int = 0
var _pending_tick: int = -1


func _init(world: SimWorld = null, pid: int = 0) -> void:
	_world = world
	_pid = pid


func submit(cmd: PackedInt32Array) -> bool:
	if not can_submit() or cmd.is_empty() or cmd.size() > MAX_INTS:
		return false
	if _pending_tick != _world.tick:
		_pending_tick = _world.tick
		_pending = 0
	if _pending >= MAX_PENDING:
		return false
	_pending += 1
	_world.submit_raw(_pid, cmd)
	return true


func can_submit() -> bool:
	return _world != null and _pid >= 0 and _world.match_state == SimWorld.MATCH_RUNNING


func local_pid() -> int:
	return _pid


func tick() -> int:
	return _world.tick if _world != null else 0


func is_observer() -> bool:
	return _pid < 0


func pending_count() -> int:
	return _pending if _pending_tick == tick() else 0


## Surrender = RESIGN with reason 0.
func surrender() -> bool:
	return submit(SimCmd.resign(0))
