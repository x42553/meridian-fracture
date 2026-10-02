extends SceneTree
## Static checker behind `tools/gd check`: load()s every script (and scene/resource) below the given
## roots so parse and compile errors surface with file:line, without running any game code.
##
##   godot --headless --path game --script res://tests/harness/check_scripts.gd -- [args]
##
## User args:
##   --paths=<csv>    res:// files or directories to check (default res://src,res://tests).
##                    Directories named `fixtures` and hidden directories are skipped while recursing.
##   --warnings       promote every WARN-level GDScript warning to an error before loading, so warnings
##                    are reported too (as errors ending in "(Warning treated as error.)"). tools/gd runs
##                    the checker twice (with and without) and diffs the results to separate them.
##   --no-scenes      do not load .tscn/.tres/.res files
##
## Output protocol, one record per line (parsed by tools/gd):
##   CHECK_ERR <res://file>:<line>: <message>
##   CHECK_DONE files=<scripts> scenes=<resources> errors=<n>
## Exit code: 0 clean, 1 errors, 2 the checker itself broke.

const DEFAULT_PATHS: PackedStringArray = ["res://src", "res://tests"]
const SKIP_DIRS: Array[String] = ["fixtures"]
const SECONDARY_PREFIX: String = "Failed to load script"

var _finished: bool = false
var _missing: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	# See runner.gd: a runtime error in _initialize would otherwise leave the tree idling forever.
	process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)
	var code: int = _run(OS.get_cmdline_user_args())
	_finished = true
	quit(code)


func _on_first_frame() -> void:
	if _finished:
		return
	printerr("CHECKER ABORTED: check_scripts.gd hit an internal error (see SCRIPT ERROR above)")
	quit(2)


func _run(args: PackedStringArray) -> int:
	var roots: PackedStringArray = DEFAULT_PATHS
	var promote: bool = false
	var scenes: bool = true
	for arg: String in args:
		if arg.begins_with("--paths="):
			roots = arg.substr("--paths=".length()).split(",", false)
		elif arg == "--warnings":
			promote = true
		elif arg == "--no-scenes":
			scenes = false
		else:
			printerr("check_scripts: unknown argument '%s'" % arg)
			return 2
	if promote:
		_promote_warnings()

	var scripts: PackedStringArray = PackedStringArray()
	var resources: PackedStringArray = PackedStringArray()
	for root: String in roots:
		_collect(root, scripts, resources)
	scripts.sort()
	resources.sort()

	var logger: TestLogger = TestLogger.new()
	OS.add_logger(logger)
	# Unique errors keyed by "file:line:message" so a broken dependency is reported once, not once
	# per dependent. Each value: {file, line, message, secondary}.
	var found: Dictionary = {}
	for path: String in scripts:
		var mark: int = logger.mark()
		var loaded: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		var gd: GDScript = loaded as GDScript
		var entries: Array[Dictionary] = logger.entries_since(mark)
		_absorb(found, entries, path)
		if (gd == null or not gd.can_instantiate()) and not _has_error_for(found, path):
			_add(found, path, 0, "script could not be compiled (no engine message captured)", false)
	if scenes:
		for path: String in resources:
			var mark: int = logger.mark()
			var loaded: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			_absorb(found, logger.entries_since(mark), path)
			if loaded == null and not _has_error_for(found, path):
				_add(found, path, 0, "resource failed to load", false)
	OS.remove_logger(logger)
	for path: String in _missing:
		_add(found, path, 0, "path to check does not exist", false)

	var errors: int = _print_findings(found)
	print("CHECK_DONE files=%d scenes=%d errors=%d" % [scripts.size(), resources.size() if scenes else 0, errors])
	return 1 if errors > 0 else 0


func _promote_warnings() -> void:
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = prop["name"]
		if pname.begins_with("debug/gdscript/warnings/") and prop["type"] == TYPE_INT:
			if ProjectSettings.get_setting(pname) == 1:
				ProjectSettings.set_setting(pname, 2)
	# GDScript caches the warning levels; this signal makes it re-read them.
	ProjectSettings.settings_changed.emit()


func _collect(path: String, scripts: PackedStringArray, resources: PackedStringArray) -> void:
	if DirAccess.dir_exists_absolute(path):
		var dir: DirAccess = DirAccess.open(path)
		if dir == null:
			return
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			var child: String = path.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with(".") and not SKIP_DIRS.has(entry):
					_collect(child, scripts, resources)
			else:
				_classify(child, scripts, resources)
			entry = dir.get_next()
		dir.list_dir_end()
	elif FileAccess.file_exists(path):
		_classify(path, scripts, resources)
	else:
		_missing.append(path)


func _classify(path: String, scripts: PackedStringArray, resources: PackedStringArray) -> void:
	var ext: String = path.get_extension()
	if ext == "gd":
		scripts.append(path)
	elif ext == "tscn" or ext == "tres" or ext == "res":
		resources.append(path)


## Attributes logged engine errors to files. Errors whose location is not a res:// script (push_error,
## resource loader messages) are attributed to `current`, the file being loaded.
func _absorb(found: Dictionary, entries: Array[Dictionary], current: String) -> void:
	var self_path: String = get_script().resource_path
	var location: RegEx = RegEx.new()
	location.compile("^(res://[^:]+):(\\d+) - (.*)$")

	for e: Dictionary in entries:
		var file: String = e["file"]
		var line: int = e["line"]
		var message: String = e["message"]
		var secondary: bool = message.begins_with(SECONDARY_PREFIX)
		if secondary:
			# `Failed to load script "res://x.gd" with error "Parse error".` -> file x.gd, no line.
			var q1: int = message.find("\"")
			var q2: int = message.find("\"", q1 + 1)
			file = message.substr(q1 + 1, q2 - q1 - 1) if q1 >= 0 and q2 > q1 else current
			line = 0
			message = "script failed to load (broken dependency or earlier error)"
		elif not file.begins_with("res://") or file == self_path:
			# engine-side error raised while this checker called load(): blame the file being loaded
			file = current
			line = 0
			message = _engine_sentence(message)
			var m: RegExMatch = location.search(message)
			if m != null:  # `res://file.tres:4 - Parse Error: ...`
				file = m.get_string(1)
				line = m.get_string(2).to_int()
				message = m.get_string(3)
		_add(found, file, line, message, secondary)


## `Condition "x" is true. Returning: y (the human sentence)` -> `the human sentence`.
func _engine_sentence(message: String) -> String:
	if not message.begins_with("Condition \"") or not message.ends_with(")"):
		return message
	var start: int = message.find(" (", message.find("Returning:"))
	if start < 0:
		return message
	return message.substr(start + 2, message.length() - start - 3)


func _add(found: Dictionary, file: String, line: int, message: String, secondary: bool) -> void:
	var clean: String = message.replace("\n", " | ").strip_edges()
	var key: String = "%s:%d:%s" % [file, line, clean]
	if not found.has(key):
		found[key] = {"file": file, "line": line, "message": clean, "secondary": secondary}


func _has_error_for(found: Dictionary, path: String) -> bool:
	for key: String in found:
		if found[key]["file"] == path:
			return true
	return false


## Prints CHECK_ERR lines sorted by file then line. Secondary "failed to load" records are dropped
## for files that already have a primary error of their own. Returns the printed count.
func _print_findings(found: Dictionary) -> int:
	var primary_files: Dictionary = {}
	for key: String in found:
		var rec: Dictionary = found[key]
		if not (rec["secondary"] as bool):
			primary_files[rec["file"]] = true
	var rows: Array[Dictionary] = []
	for key: String in found:
		var rec: Dictionary = found[key]
		if (rec["secondary"] as bool) and primary_files.has(rec["file"]):
			continue
		rows.append(rec)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["file"] != b["file"]:
			return (a["file"] as String) < (b["file"] as String)
		if a["line"] != b["line"]:
			return (a["line"] as int) < (b["line"] as int)
		return (a["message"] as String) < (b["message"] as String))
	for rec: Dictionary in rows:
		print("CHECK_ERR %s:%d: %s" % [rec["file"], rec["line"], rec["message"]])
	return rows.size()
