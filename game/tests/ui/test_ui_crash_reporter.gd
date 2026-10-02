extends RefCounted
## `AppCrashReporter`, `AppCrash` (ui.md 10.2 `test_app_crash_report_fields`, 5.20.3, 5.20.4).

const U := preload("res://tests/ui/app_test_util.gd")


func _reporter(dir: String, pid: int = 4242) -> AppCrashReporter:
	var r: AppCrashReporter = AppCrashReporter.new()
	r.session_path = dir.path_join(".session")
	r.crash_dir = dir.path_join("crash")
	r.logs_dir = dir.path_join("logs")
	r.pid_provider = func() -> int: return pid
	r.user_path_override = "/home/tester/.local/share/MeridianFracture"
	DirAccess.make_dir_recursive_absolute(r.crash_dir)
	DirAccess.make_dir_recursive_absolute(r.logs_dir)
	return r


## Every required field of 5.20.3 is in the header; peer addresses and chat text never are.
func test_cpu_name_parsing_and_no_engine_error(t: TestCtx) -> void:
	t.eq(AppCrashReporter.parse_cpuinfo("processor\t: 0\nmodel name\t: Intel(R) Core(TM) i7\n"), "Intel(R) Core(TM) i7", "x86 model name")
	t.eq(AppCrashReporter.parse_cpuinfo("processor : 0\nBogoMIPS : 50.00\nCPU part : 0xd08\n"), "", "aarch64 cpuinfo has no model name")
	t.eq(AppCrashReporter.parse_cpuinfo("Hardware\t: BCM2711\nModel\t: Raspberry Pi 4\n"), "BCM2711", "ARM board")
	t.check(not AppCrashReporter.cpu_name().is_empty(), "the live CPU name is never empty (and prints no engine error on Linux/arm64)")


func test_app_crash_report_fields(t: TestCtx) -> void:
	var dir: String = U.sandbox("hdr")
	var r: AppCrashReporter = _reporter(dir)
	r.info_provider = func() -> Dictionary:
		return {"rosters": ["roster.napc.vanilla", "roster.han.vanilla"], "map_family": 2, "map_size": 3, "map_seed": "5A17C3E9",
			"tick": 1200, "checksum": "9F3AC21E", "net_role": "HOST 192.168.1.20:27615",
			"peers": ["192.168.1.21:27615", "10.0.0.7"], "chat": "hello secret chat message", "player_names": ["Ann"]}
	var h: String = r.report_header("match")
	for label: String in ["version:", "build ", "godot:", "os:", "arch:", "cpu:", "ram_mb:", "gpu:", "vendor:", "type:", "api:",
			"renderer:", "driver:", "display_server:", "screen:", "scale:", "refresh:", "locale:", "user_dir:", "uptime_s:",
			"phase: match", "match:", "rosters=", "map=", "seed=", "sim:", "tick=1200", "checksum=9F3AC21E", "net_role:"]:
		t.check(h.contains(label), "header has '%s'" % label)
	t.check(h.contains("0.1.0"), "game version")
	t.check(h.contains(AppInfo.engine_string()), "Godot version")
	t.check(h.contains("/home/tester/.local/share/MeridianFracture"), "user:// path")
	t.check(h.contains("roster.napc.vanilla, roster.han.vanilla"), "rosters")
	t.check(not h.contains("192.168.1.2") and not h.contains("10.0.0.7"), "no IP address anywhere")
	t.check(not h.contains("hello secret chat message") and not h.contains("chat"), "no chat text")
	t.check(h.contains("HOST <addr>"), "an address inside an allowed field is redacted")
	t.check(not h.contains("Ann"), "no player names")
	r.info_provider = Callable()
	t.check(r.report_header("boot").contains("tick=n/a"), "without a match the fields read n/a")
	U.cleanup(dir)


func test_report_text_has_reason_detail_and_log_tail(t: TestCtx) -> void:
	var dir: String = U.sandbox("txt")
	var r: AppCrashReporter = _reporter(dir)
	Log.ring = PackedStringArray()
	for i: int in 80:
		Log.ring.append("INFO [app] line %d" % i)
	var text: String = r.report_text(AppCrash.Reason.DATA_LOAD_FAILED, "def X is broken")
	t.check(text.contains("reason: DATA_LOAD_FAILED") and text.contains("def X is broken"))
	t.check(text.contains("line 79") and text.contains("line 20") and not text.contains("line 19 "), "the last 60 lines")
	U.cleanup(dir)


func test_session_sentinel_and_unclean_report(t: TestCtx) -> void:
	var dir: String = U.sandbox("sess")
	var r1: AppCrashReporter = _reporter(dir, 100)
	t.eq(r1.start_session(), {}, "a first start has no previous run")
	t.check(FileAccess.file_exists(r1.session_path), "sentinel written")
	var rec: Variant = JSON.parse_string(U.read(r1.session_path))
	t.eq(int((rec as Dictionary)["pid"]), 100)
	t.eq((rec as Dictionary)["version"], "0.1.0")
	t.check(String((rec as Dictionary)["start_utc"]).ends_with("Z"), "ISO UTC start")
	# a previous engine log to tail
	U.write(dir.path_join("logs/godot2026-09-29T10.00.00.log"), "engine line 1\nlast engine line\n")
	# the process "died": a new process finds the sentinel
	var r2: AppCrashReporter = _reporter(dir, 200)
	var prev: Dictionary = r2.start_session()
	t.eq(int(prev["pid"]), 100, "the previous run is reported")
	var report: String = String(prev["report"])
	t.check(report.contains("_unclean.txt") and FileAccess.file_exists(report), "crash_<utc>_unclean.txt written")
	var text: String = U.read(report)
	t.check(text.contains("pid=100") and text.contains("did not end cleanly"), "names the dead session")
	t.check(text.contains("version:") and text.contains("gpu:"), "carries the header")
	t.check(text.contains("last engine line"), "and the previous engine log tail")
	var actions: Array[Dictionary] = r2.toast_actions(prev)
	t.eq(actions.size(), 2, "Open logs folder + Copy report")
	t.check(String(actions[0]["label"]).begins_with("Open") and String(actions[1]["label"]).begins_with("Copy"))
	t.eq(r2.toast_actions(prev, func() -> void: pass).size(), 3, "a recovered replay adds Watch")
	var rec2: Variant = JSON.parse_string(U.read(r2.session_path))
	t.eq(int((rec2 as Dictionary)["pid"]), 200, "the sentinel now belongs to the new process")
	r2.end_session()
	t.check(not FileAccess.file_exists(r2.session_path), "a clean quit removes it")
	t.eq(_reporter(dir, 300).start_session(), {}, "and the next start is clean")
	# same pid = the same process restarting its session (no report)
	var r4: AppCrashReporter = _reporter(dir, 300)
	t.eq(r4.start_session(), {}, "own sentinel is not a crash")
	U.cleanup(dir)


func test_crash_notification_writes_a_report(t: TestCtx) -> void:
	var dir: String = U.sandbox("crash")
	var r: AppCrashReporter = _reporter(dir)
	r.phase = "match"
	var path: String = r.on_crash()
	t.check(path.ends_with(".txt") and not path.contains("_unclean") and FileAccess.file_exists(path), "crash_<utc>.txt")
	t.check(U.read(path).contains("phase: match") and U.read(path).contains("NOTIFICATION_CRASH"))
	U.cleanup(dir)


func test_prune_keeps_the_newest_20(t: TestCtx) -> void:
	var dir: String = U.sandbox("prune")
	var r: AppCrashReporter = _reporter(dir)
	for i: int in 25:
		U.write(r.crash_dir.path_join("crash_202609%02dT120000Z.txt" % (i + 1)), "x")
	U.write(r.crash_dir.path_join("crash_1700000000.mfreplay"), "replay")
	r.prune()
	var names: PackedStringArray = DirAccess.get_files_at(r.crash_dir)
	var txt: int = 0
	for n: String in names:
		txt += 1 if n.ends_with(".txt") else 0
	t.eq(txt, 20, "20 reports remain")
	t.check(not names.has("crash_20260901T120000Z.txt") and names.has("crash_20260925T120000Z.txt"), "the oldest went first")
	t.check(names.has("crash_1700000000.mfreplay"), "replays are not pruned here")
	U.cleanup(dir)


func test_fatal_model(t: TestCtx) -> void:
	var dir: String = U.sandbox("fatal")
	var old: AppCrashReporter = AppCrash.reporter
	AppCrash.reporter = _reporter(dir)
	var m: Dictionary = AppCrash.build(AppCrash.Reason.NET_FATAL, "peer vanished")
	t.eq(m["name"], "NET_FATAL")
	t.check(bool(m["retry"]) and AppCrash.can_retry(AppCrash.Reason.WORLD_BUILD_FAILED))
	t.check(not AppCrash.can_retry(AppCrash.Reason.DATA_LOAD_FAILED))
	t.check(String(m["text"]).contains("peer vanished") and String(m["message"]).length() > 20)
	for r: int in [0, 1, 2, 3, 4, 5, 15]:
		t.check(AppCrash.message(r).length() > 10 and AppCrash.reason_name(r) != "", "reason %d has text" % r)
	AppCrash.reporter = old
	U.cleanup(dir)
