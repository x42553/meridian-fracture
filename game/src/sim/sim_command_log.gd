class_name SimCommandLog
extends RefCounted
## In-memory command record + replay driver for tests / tools (sim_core 3.8). The replay FILE belongs to net
## (NetReplay). Records must be added in non-decreasing tick order (which `submit` guarantees).

var ticks: PackedInt32Array = PackedInt32Array()
var pids: PackedInt32Array = PackedInt32Array()
var cmds: Array[PackedInt32Array] = []
## Copy of world.checksum_log: pairs [tick, checksum].
var checkpoints: PackedInt64Array = PackedInt64Array()


func record(tick: int, pid: int, ints: PackedInt32Array) -> void:
	ticks.append(tick)
	pids.append(pid)
	cmds.append(ints.duplicate())


## Records under world.tick AND submits.
func submit(world: SimWorld, pid: int, ints: PackedInt32Array) -> void:
	record(world.tick, pid, ints)
	world.submit_raw(pid, ints)


## Copies world.checksum_log.
func finish(world: SimWorld) -> void:
	checkpoints = world.checksum_log.duplicate()


## [n, (tick, pid, len, ints...) x n]
func to_ints() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.append(cmds.size())
	for i: int in cmds.size():
		out.append(ticks[i])
		out.append(pids[i])
		out.append(cmds[i].size())
		out.append_array(cmds[i])
	return out


## Inverse of to_ints (checkpoints are not part of the flat form); null when malformed.
static func from_ints(a: PackedInt32Array) -> SimCommandLog:
	var out: SimCommandLog = SimCommandLog.new()
	if a.is_empty() or a[0] < 0:
		return null
	var pos: int = 1
	for _i: int in a[0]:
		if pos + 3 > a.size():
			return null
		var n: int = a[pos + 2]
		if n < 0 or pos + 3 + n > a.size():
			return null
		out.record(a[pos], a[pos + 1], a.slice(pos + 3, pos + 3 + n))
		pos += 3 + n
	if pos != a.size():
		return null
	return out


## Replays the recorded commands into `world` (freshly built from the same inputs) for n_ticks steps and compares
## every recorded checkpoint. {ok, mismatch_tick (-1 none), final (checksum after the last step)}.
func play(world: SimWorld, n_ticks: int) -> Dictionary:
	var i: int = 0
	var n: int = cmds.size()
	for t: int in n_ticks:
		while i < n and ticks[i] <= t:
			world.submit_raw(pids[i], cmds[i])
			i += 1
		world.step()
	var mismatch: int = -1
	var k: int = 0
	while k + 1 < checkpoints.size():
		var ct: int = checkpoints[k]
		if ct <= world.tick and world.checksum_at(ct) != checkpoints[k + 1]:
			mismatch = ct
			break
		k += 2
	return {"ok": mismatch == -1, "mismatch_tick": mismatch, "final": world.checksum()}
