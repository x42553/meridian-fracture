class_name AppCrashReporter
extends RefCounted
## Session sentinel, crash report files, report header and retention (ui.md 5.20.3, QA-XR-12).
## `start_session()` writes `user://.session` and, when the previous run left one behind, `crash_<utc>_unclean.txt`;
## `on_crash()` (NOTIFICATION_CRASH) writes `crash_<utc>.txt` best-effort. The header never contains peer addresses or chat.

const KEEP_REPORTS: int = 20
const TAIL_LINES: int = 60
const PREV_LOG_LINES: int = 200
const GPU_TYPES: PackedStringArray = ["other", "integrated", "discrete", "virtual", "cpu"]

var files: AppFileLayer = AppFileLayer.new()
var session_path: String = AppPaths.SESSION
var crash_dir: String = AppPaths.CRASH_DIR
var logs_dir: String = AppPaths.LOGS_DIR
## `func() -> int`: pid of this process (injectable).
var pid_provider: Callable = Callable()
## `func() -> Dictionary`: match/net facts for the header. Only the whitelisted keys below are ever printed:
## `rosters`, `map_family`, `map_size`, `map_seed`, `tick`, `checksum`, `net_role`.
var info_provider: Callable = Callable()
## Current phase name: "boot", "menu", "lobby", "loading", "match", "end", ... (set by `AppState`).
var phase: String = "boot"
## Globalised `user://` path override for tests (empty = the real one).
var user_path_override: String = ""

var _ip_regex: RegEx = null


func _pid() -> int:
	return int(pid_provider.call()) if pid_provider.is_valid() else OS.get_process_id()


## Writes the sentinel. Returns `{}` when the previous run ended cleanly, else that run's `{pid, start_utc, version}` plus
## `report` (the `crash_<utc>_unclean.txt` path that was written).
func start_session() -> Dictionary:
	var prev: Dictionary = {}
	if files.exists(session_path):
		var parsed: Variant = JSON.parse_string(files.read_text(session_path))
		if parsed is Dictionary and int((parsed as Dictionary).get("pid", -1)) != _pid():
			prev = (parsed as Dictionary).duplicate()
			prev["report"] = _write_unclean(prev)
		elif not (parsed is Dictionary):
			prev = {"pid": -1, "start_utc": "", "version": ""}
			prev["report"] = _write_unclean(prev)
	var rec: Dictionary = {"pid": _pid(), "start_utc": AppPaths.utc_iso(), "version": AppInfo.version()}
	files.write_text(session_path, JSON.stringify(rec))
	return prev


## Deletes the sentinel (clean quit, WM_CLOSE_REQUEST).
func end_session() -> void:
	if files.exists(session_path):
		files.remove(session_path)


## NOTIFICATION_CRASH: best-effort report file (no allocation-heavy work beyond the text). Returns the path or "".
func on_crash() -> String:
	return write_report("crash", _crash_text())


func _crash_text() -> String:
	return report_header(phase) + "\nreason: engine crash (NOTIFICATION_CRASH)\n\n" + _tail_block(TAIL_LINES)


func _write_unclean(prev: Dictionary) -> String:
	var text: String = report_header("previous session (unclean exit)")
	text += "\nprevious session: pid=%s start_utc=%s version=%s\n" % [str(int(prev.get("pid", -1))), str(prev.get("start_utc", "?")),
		str(prev.get("version", "?"))]
	text += "reason: the previous run did not end cleanly (no clean shutdown recorded)\n\n"
	text += "--- previous engine log (tail) ---\n" + _previous_engine_log() + "\n"
	return write_report("unclean", text)


func _previous_engine_log() -> String:
	var best: String = ""
	var best_t: int = -1
	for f: String in files.list_files(logs_dir):
		if not (f.begins_with("godot") and f.ends_with(".log")) or f == "godot.log":
			continue
		var t: int = files.modified_time(logs_dir.path_join(f))
		if t > best_t:
			best_t = t
			best = f
	if best.is_empty():
		return "(no previous engine log)"
	var lines: PackedStringArray = files.read_text(logs_dir.path_join(best)).split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - PREV_LOG_LINES)))


## Writes `crash_<utc>[_kind].txt` (kind "crash" = no suffix) into the crash folder; returns the path ("" on failure).
func write_report(kind: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(crash_dir)
	var suffix: String = "" if kind == "crash" else "_" + kind
	var base: String = "crash_%s%s" % [AppPaths.utc_stamp(), suffix]
	var path: String = crash_dir.path_join(base + ".txt")
	var n: int = 2
	while files.exists(path):
		path = crash_dir.path_join("%s_%d.txt" % [base, n])
		n += 1
	if files.write_text(path, text) != OK:
		return ""
	prune()
	return path


## The CPU model. `OS.get_processor_name()` prints an engine ERROR on Linux/aarch64 (no "model name" in /proc/cpuinfo), so Linux reads
## /proc/cpuinfo itself and falls back to the architecture name.
static func cpu_name() -> String:
	if OS.get_name() != "Linux":
		return OS.get_processor_name()
	var f: FileAccess = FileAccess.open("/proc/cpuinfo", FileAccess.READ)
	var name: String = parse_cpuinfo(f.get_as_text()) if f != null else ""
	return name if not name.is_empty() else "unknown (%s)" % Engine.get_architecture_name()


## First "model name" / "Hardware" / "Model" / "cpu model" value of a /proc/cpuinfo text ("" when none).
static func parse_cpuinfo(text: String) -> String:
	for line: String in text.split("\n", false):
		var colon: int = line.find(":")
		if colon < 0:
			continue
		var key: String = line.substr(0, colon).strip_edges().to_lower()
		if key == "model name" or key == "hardware" or key == "model" or key == "cpu model":
			var v: String = line.substr(colon + 1).strip_edges()
			if not v.is_empty():
				return v
	return ""


## The required header fields of 5.20.3 as `key: value` lines.
func report_header(phase_name: String = "") -> String:
	var info: Dictionary = info_provider.call() as Dictionary if info_provider.is_valid() else {}
	var mem: Dictionary = OS.get_memory_info()
	var ram_mb: int = int(int(mem.get("physical", 0)) / 1048576)
	var scr: int = DisplayServer.get_primary_screen()
	var gpu_type: int = int(RenderingServer.get_video_adapter_type())
	var lines: PackedStringArray = PackedStringArray()
	lines.append("MERIDIAN FRACTURE crash report")
	lines.append("version: %s (build %s)" % [AppInfo.version(), AppInfo.build_id()])
	lines.append("godot: %s" % AppInfo.engine_string())
	lines.append("os: %s" % AppInfo.platform_string())
	lines.append("arch: %s" % Engine.get_architecture_name())
	lines.append("cpu: %s (%d cores)" % [cpu_name(), OS.get_processor_count()])
	lines.append("ram_mb: %d" % ram_mb)
	lines.append("gpu: %s | vendor: %s | type: %s | api: %s" % [RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), GPU_TYPES[clampi(gpu_type, 0, GPU_TYPES.size() - 1)],
		RenderingServer.get_video_adapter_api_version()])
	lines.append("renderer: %s | driver: %s" % [RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()])
	lines.append("display_server: %s" % DisplayServer.get_name())
	lines.append("screen: %dx%d | scale: %.2f | refresh: %.1f" % [DisplayServer.screen_get_size(scr).x,
		DisplayServer.screen_get_size(scr).y, DisplayServer.screen_get_scale(scr), DisplayServer.screen_get_refresh_rate(scr)])
	lines.append("locale: %s" % OS.get_locale())
	lines.append("user_dir: %s" % (user_path_override if not user_path_override.is_empty() else AppPaths.globalize("user://")))
	lines.append("uptime_s: %.1f" % (float(Time.get_ticks_msec()) / 1000.0))
	lines.append("phase: %s" % (phase_name if not phase_name.is_empty() else phase))
	lines.append("match: rosters=%s | map=%s/%s | seed=%s" % [_field(info, "rosters"), _field(info, "map_family"),
		_field(info, "map_size"), _field(info, "map_seed")])
	lines.append("sim: tick=%s | checksum=%s" % [_field(info, "tick"), _field(info, "checksum")])
	lines.append("net_role: %s" % _field(info, "net_role"))
	return "\n".join(lines) + "\n"


func _field(info: Dictionary, key: String) -> String:
	if not info.has(key):
		return "n/a"
	var v: Variant = info[key]
	var s: String = ", ".join(PackedStringArray(v)) if v is Array else str(v)
	return _redact(s)


## Defence in depth: dotted-quad addresses never reach a report.
func _redact(s: String) -> String:
	if _ip_regex == null:
		_ip_regex = RegEx.create_from_string("\\b\\d{1,3}(\\.\\d{1,3}){3}(:\\d+)?\\b")
	return _ip_regex.sub(s, "<addr>", true)


func _tail_block(n: int) -> String:
	return "--- last %d log lines ---\n%s\n" % [n, "\n".join(Log.ring_tail(n))]


## Header + reason + detail + the `Log.ring` tail (fatal screen, "Copy report").
func report_text(reason: int, detail: String) -> String:
	return report_header(phase) + "\nreason: %s\n\ndetail:\n%s\n\n%s" % [AppCrash.reason_name(reason), detail, _tail_block(TAIL_LINES)]


## Keeps the newest `KEEP_REPORTS` crash text files.
func prune() -> void:
	var names: PackedStringArray = PackedStringArray()
	for f: String in files.list_files(crash_dir):
		if f.begins_with("crash_") and f.ends_with(".txt"):
			names.append(f)
	names.sort()
	while names.size() > KEEP_REPORTS:
		files.remove(crash_dir.path_join(names[0]))
		names.remove_at(0)


## Toast actions of the unclean-exit toast: Open logs folder, Copy report (+ Watch recovered replay when the net module
## left one). `prev` is the dictionary `start_session` returned.
func toast_actions(prev: Dictionary, watch_replay: Callable = Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"label_key": &"ui.crash.open_logs", "label": "Open logs folder",
		"call": func() -> void: OS.shell_open(AppPaths.globalize(logs_dir))})
	var report: String = str(prev.get("report", ""))
	out.append({"label_key": &"ui.crash.copy_report", "label": "Copy report",
		"call": func() -> void: DisplayServer.clipboard_set(files.read_text(report))})
	if watch_replay.is_valid():
		out.append({"label_key": &"ui.crash.watch_replay", "label": "Watch recovered replay", "call": watch_replay})
	return out
