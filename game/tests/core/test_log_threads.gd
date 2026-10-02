extends RefCounted
## HARD1: `Log` is called from worker threads (map generation thread, WorkerThreadPool model builds, the engine Logger hook) while the main thread
## logs and reads the ring. The ring append / trim is under a lock now (a PackedStringArray appended and re-sliced by two threads at once corrupts the heap).

const WORKERS: int = 8
const LINES: int = 600


func _log_task(i: int) -> void:
	for n: int in LINES:
		Log.debug("thread", "worker %d line %d" % [i, n])


func test_concurrent_logging_keeps_the_ring_consistent(t: TestCtx) -> void:
	var old_quiet: bool = Log.quiet
	var old_ring: PackedStringArray = Log.ring
	Log.quiet = true  # the ring still records
	Log.ring = PackedStringArray()
	var gid: int = WorkerThreadPool.add_group_task(_log_task, WORKERS, -1, true, "log threads")
	var main_lines: int = 0
	while not WorkerThreadPool.is_group_task_completed(gid):
		Log.info("main", "main line %d" % main_lines)
		var tail: PackedStringArray = Log.ring_tail(20)
		for line: String in tail:
			if line.is_empty():
				t.fail("an empty ring line (torn write)")
				break
		main_lines += 1
	WorkerThreadPool.wait_for_group_task_completion(gid)
	t.check(main_lines > 0, "the main thread logged while the workers did")
	t.le(Log.ring.size(), Log.RING_SIZE, "the ring stays bounded")
	t.eq(Log.ring.size(), Log.RING_SIZE, "and full")
	for line: String in Log.ring:
		t.check(line.begins_with("DEBUG [thread] worker ") or line.begins_with("INFO [main] main line "), "intact line: " + line)
		if not (line.begins_with("DEBUG [thread] worker ") or line.begins_with("INFO [main] main line ")):
			break
	Log.ring = old_ring
	Log.quiet = old_quiet


func test_ring_push_and_tail(t: TestCtx) -> void:
	var old_ring: PackedStringArray = Log.ring
	Log.ring = PackedStringArray()
	for i: int in Log.RING_SIZE + 10:
		Log.ring_push("L%d" % i)
	t.eq(Log.ring.size(), Log.RING_SIZE)
	t.eq(Log.ring_tail(2), PackedStringArray(["L%d" % (Log.RING_SIZE + 8), "L%d" % (Log.RING_SIZE + 9)]))
	t.eq(Log.ring_tail(100000).size(), Log.RING_SIZE)
	Log.ring = old_ring
