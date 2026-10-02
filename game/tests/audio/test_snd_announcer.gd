extends RefCounted
## Announcer: the worked example of audio spec 5.9 on a fake clock, packs, modes, expiry, queue cap, TTS seams.


func _index() -> SndAssetIndex:
	var base: SndAssetIndex = SndTestKit.real()["index"]
	var ix: SndAssetIndex = SndAssetIndex.new()
	for k: Variant in base.assets.keys():
		if not str(k).begins_with("vox/"):
			ix.assets[k] = base.assets[k]
	var lines: Dictionary = (SndTestKit.real()["store"] as SndDataStore).announcer.get("lines", {})
	for l: Variant in lines.keys():
		ix.assets["vox/computer/%s" % l] = {"f": "vox/computer/%s.ogg" % l, "b": "vox_computer", "c": 1, "l": 0}
		if str(l) != "canceled":
			ix.assets["vox/napc/%s" % l] = {"f": "vox/napc/%s.ogg" % l, "b": "vox_napc", "c": 1, "l": 0}
	return ix


func _ann(clock: SndTestKit.FakeClock) -> SndAnnouncer:
	var a: SndAnnouncer = SndAnnouncer.new()
	a.setup(SndTestKit.real()["store"], _index(), Callable(clock, "now"), 3)
	a.set_pack(&"napc")
	a.duration_override = {&"construction_complete": 1300, &"base_under_attack": 1600, &"unit_ready": 900, &"low_power": 900}
	return a


func _step(a: SndAnnouncer, clock: SndTestKit.FakeClock, until_ms: int) -> void:
	# drive update() every 10 ms like frames would
	while clock.ms < until_ms:
		clock.advance(10)
		a.update(0.01, clock.ms)


func test_queue_worked_example(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var a: SndAnnouncer = _ann(clock)
	var started: Array = []
	a.started.connect(func(l: StringName, _text: String, _p: int) -> void: started.append([l, clock.ms]))
	var t0: int = clock.ms
	t.check(a.say(&"construction_complete"), "t=0 plays")
	_step(a, clock, t0 + 300)
	t.check(a.say(&"unit_ready"), "t=300 queued")
	t.eq(a.queue_size(), 1, "one queued")
	_step(a, clock, t0 + 500)
	t.check(a.say(&"base_under_attack"), "t=500 pre-empts (92 >= 60 + 20)")
	_step(a, clock, t0 + 540)
	t.eq(a.current_line(), &"base_under_attack", "alert speaking after the 40 ms fade")
	var alert_start: int = int(started[1][1]) - t0
	t.le(absi(alert_start - 540), 10, "alert starts at ~540 ms (%d)" % alert_start)
	_step(a, clock, t0 + 2500)
	t.check(not a.say(&"base_under_attack"), "second alert at 2.5 s is dropped (12 s cooldown)")
	var ready_start: int = -1
	for s: Array in started:
		if s[0] == &"unit_ready":
			ready_start = int(s[1]) - t0
	t.le(absi(ready_start - 2390), 15, "unit_ready starts at ~2390 ms (%d)" % ready_start)
	_step(a, clock, t0 + 2600)
	t.check(a.say(&"low_power"), "t=2.6 s low_power (75 >= 45 + 20) pre-empts the running unit_ready")
	_step(a, clock, t0 + 2700)
	t.eq(a.current_line(), &"low_power", "low_power speaking")


func test_queue_cap_and_expiry(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var a: SndAnnouncer = _ann(clock)
	a.duration_override = {&"base_under_attack": 5000}
	a.say(&"base_under_attack", 50)
	for l: StringName in [&"unit_ready", &"research_complete", &"new_construction_options", &"insufficient_funds", &"unit_cap_reached"]:
		a.say(l)
	t.le(a.queue_size(), 4, "queue never exceeds 4")
	# an item older than expire_ms is skipped when it reaches the front
	var clock2: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var b: SndAnnouncer = _ann(clock2)
	b.duration_override = {&"base_under_attack": 20000}
	b.say(&"base_under_attack")
	b.say(&"unit_ready")
	_step(b, clock2, clock2.ms + 12000)
	_step(b, clock2, clock2.ms + 12000)
	t.eq(b.current_line(), &"", "expired item was dropped, nothing speaks after the long line")


func test_identical_line_refreshes(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var a: SndAnnouncer = _ann(clock)
	a.duration_override = {&"base_under_attack": 5000}
	a.say(&"base_under_attack")
	a.say(&"unit_ready")
	a.say(&"unit_ready", 55)
	t.eq(a.queue_size(), 1, "an identical queued line is refreshed, not duplicated")


func test_packs_and_modes(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var a: SndAnnouncer = _ann(clock)
	t.eq(a.resolve_asset(&"unit_ready").begins_with("vox/napc/"), true, "faction pack first")
	t.eq(a.resolve_asset(&"canceled"), "vox/computer/canceled", "line missing in the faction pack falls back to computer")
	a.set_mode(SndSettings.ANN_COMPUTER)
	t.check(a.resolve_asset(&"unit_ready").begins_with("vox/computer/"), "computer mode")
	a.set_mode(SndSettings.ANN_OFF)
	t.check(not a.say(&"unit_ready"), "off is silent")
	a.set_mode(SndSettings.ANN_FACTION)
	t.check(not a.say(&"no_such_line"), "unknown line")
	var ix2: SndAssetIndex = SndAssetIndex.new()
	var b: SndAnnouncer = SndAnnouncer.new()
	b.setup(SndTestKit.real()["store"], ix2, Callable(clock, "now"), 3)
	t.check(not b.say(&"unit_ready"), "missing everywhere -> false")


func test_tts_mode(t: TestCtx) -> void:
	var clock: SndTestKit.FakeClock = SndTestKit.FakeClock.new()
	var a: SndAnnouncer = _ann(clock)
	var spoken: Array[String] = []
	var ducked: Array[bool] = []
	a.tts_available_fn = func() -> bool: return true
	a.tts_speak_fn = func(text: String) -> void: spoken.append(text)
	a.tts_stop_fn = func() -> void: pass
	a.tts_speaking_fn = func() -> bool: return clock.ms < 100000 + 600
	a.set_duck_callback(func(on: bool) -> void: ducked.append(on))
	t.check(a.set_tts(true), "tts available")
	a.say(&"unit_ready")
	t.eq(spoken.size(), 1, "the caption was spoken")
	t.eq(spoken[0], "Unit ready.", "caption text")
	t.eq(ducked, [true], "music ducked while speaking")
	_step(a, clock, clock.ms + 1500)
	t.eq(ducked, [true, false], "music restored after the utterance")
	var b: SndAnnouncer = _ann(clock)
	b.tts_available_fn = func() -> bool: return false
	t.check(not b.set_tts(true), "no voice available: stays off")
