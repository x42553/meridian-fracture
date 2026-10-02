extends RefCounted
## AB-01: the 1024-slot absolute-tick wheel (abilities 10.1 test_timer_wheel).


func test_fires_at_the_due_tick(t: TestCtx) -> void:
	var w: SimTimerWheel = SimTimerWheel.new()
	w.schedule(5, 1, 10, 0)
	w.schedule(1024, 2, 11, 0)
	w.schedule(2500, 3, 12, 7)
	var out: PackedInt32Array = PackedInt32Array()
	var fired: Dictionary = {}
	for tick: int in range(0, 2600):
		w.pop_due(tick, out)
		for i: int in range(0, out.size(), 3):
			fired[out[i]] = tick
			if out[i] == 3:
				t.eq([out[i + 1], out[i + 2]], [12, 7] as Array, "kind and gen travel with the timer")
	t.eq(fired.get(1), 5, "+5")
	t.eq(fired.get(2), 1024, "+1024 waits a full lap")
	t.eq(fired.get(3), 2500, "+2500")
	t.eq(w.size(), 0, "nothing pending")


func test_bucket_collisions_keep_insertion_order(t: TestCtx) -> void:
	var w: SimTimerWheel = SimTimerWheel.new()
	w.schedule(5, 30, 1, 0)
	w.schedule(1029, 31, 1, 0)  # same slot, a lap later
	w.schedule(5, 32, 1, 0)
	w.schedule(5, 33, 2, 0)
	var out: PackedInt32Array = PackedInt32Array()
	w.pop_due(5, out)
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in range(0, out.size(), 3):
		ids.append(out[i])
	t.eq(ids, PackedInt32Array([30, 32, 33]), "due timers in insertion order, the lap-later one stays")
	t.eq(w.size(), 1, "one left")
	w.pop_due(1029, out)
	t.eq(out[0], 31, "and fires a lap later")


func test_late_schedule_is_never_lost(t: TestCtx) -> void:
	var w: SimTimerWheel = SimTimerWheel.new()
	var out: PackedInt32Array = PackedInt32Array()
	w.pop_due(10, out)
	w.schedule(8, 1, 1, 0)  # already in the past
	w.pop_due(11, out)
	t.eq(out.size(), 3, "fires at the next pop")
