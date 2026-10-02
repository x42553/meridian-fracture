extends RefCounted
## HARD1: a map-generation worker thread must never outlive an orderly quit. `MapGenJob.cancel_all()` (called by AppShutdown.join_workers) cancels and
## joins every running job even when nobody holds the cancel handle any more; a job freed while its thread runs is joined by its PREDELETE hook.


func _cfg(size: int) -> Dictionary:
	return {"family": 0, "size": size, "seed": 99, "layout_players": 2}


func test_cancel_all_joins_running_jobs(t: TestCtx) -> void:
	var a: MapGenJob = MapGenJob.begin(_cfg(192))
	var b: MapGenJob = MapGenJob.begin(_cfg(192))
	t.check(a.step(0) == false or a.result() != null, "the job is running (or finished on a fast machine)")
	var n: int = MapGenJob.cancel_all()
	t.le(n, 2)
	t.check(a.step(0), "cancelled jobs report finished")
	t.is_null(a.result(), "and carry no map")
	t.is_null(b.result())
	t.eq(MapGenJob.cancel_all(), 0, "nothing left to cancel")


func test_freeing_a_running_job_does_not_error_or_hang(t: TestCtx) -> void:
	var j: MapGenJob = MapGenJob.begin(_cfg(160))
	var ref: WeakRef = weakref(j)
	OS.delay_msec(30)  # the worker is really running (dropping the handle before the thread started is an engine error of its own)
	j = null
	var guard: int = 0
	while ref.get_ref() != null and guard < 2000:
		OS.delay_msec(2)
		guard += 1
	t.is_null(ref.get_ref(), "the job was freed (its worker was joined by the PREDELETE hook)")
	t.eq(MapGenJob.cancel_all(), 0)
