class_name AppCrash
extends RefCounted
## Fatal/crash report model (ui.md 3.1, 5.20.4): reason codes, plain-language sentence, the report text for the fatal screen
## ("Copy report") and `show()` that writes `crash_<utc>_fatal.txt` and moves the app to the FATAL screen.

enum Reason { DATA_LOAD_FAILED = 0, WORLD_BUILD_FAILED = 1, ERROR_STORM = 2, NET_FATAL = 3, RENDERER = 4, DISK = 5, UNKNOWN = 15 }

## The reporter used by `show` (set by `AppBoot`; a default instance is created lazily).
static var reporter: AppCrashReporter = null
## Settings digest lines appended to the report when the boot code sets them.
static var settings_digest: String = ""


static func reason_name(reason: int) -> String:
	match reason:
		Reason.DATA_LOAD_FAILED:
			return "DATA_LOAD_FAILED"
		Reason.WORLD_BUILD_FAILED:
			return "WORLD_BUILD_FAILED"
		Reason.ERROR_STORM:
			return "ERROR_STORM"
		Reason.NET_FATAL:
			return "NET_FATAL"
		Reason.RENDERER:
			return "RENDERER"
		Reason.DISK:
			return "DISK"
	return "UNKNOWN"


## One plain-language sentence for the fatal screen.
static func message(reason: int) -> String:
	match reason:
		Reason.DATA_LOAD_FAILED:
			return "The game data could not be loaded. Reinstalling the game usually fixes this."
		Reason.WORLD_BUILD_FAILED:
			return "The match could not be created. You can go back to the menu and try again."
		Reason.ERROR_STORM:
			return "The game hit a flood of errors while loading and stopped to protect your data."
		Reason.NET_FATAL:
			return "The network session failed and cannot continue."
		Reason.RENDERER:
			return "The graphics system reported a fatal problem. Try another renderer in the launch options."
		Reason.DISK:
			return "The game could not read or write its files. Check the free disk space and permissions."
	return "Something went wrong that the game could not recover from."


## Retry (back to the menu) is offered only for these reasons.
static func can_retry(reason: int) -> bool:
	return reason == Reason.WORLD_BUILD_FAILED or reason == Reason.NET_FATAL


## The full model handed to `UiScreenFatal`: `{reason, name, message, detail, text, retry}`.
static func build(reason: int, detail: String) -> Dictionary:
	var rep: AppCrashReporter = _reporter()
	var text: String = rep.report_text(reason, detail)
	if not settings_digest.is_empty():
		text += "\nsettings:\n" + settings_digest + "\n"
	return {"reason": reason, "name": reason_name(reason), "message": message(reason), "detail": detail, "text": text,
		"retry": can_retry(reason)}


## Detail text of a failed `GameData.load_default()`.
static func data_failure_detail() -> String:
	if GameData.last_report != null:
		return GameData.last_report.text()
	return "GameData.load_default() returned null without a report"


## Writes `crash_<utc>_fatal.txt` and asks `AppState` (autoload, looked up by path) to show the FATAL screen.
## Returns the model. Safe to call before the autoloads exist (only the file is written).
static func show(reason: int, detail: String) -> Dictionary:
	var model: Dictionary = build(reason, detail)
	Log.error("app", "FATAL %s: %s" % [model["name"], detail.substr(0, 400)])
	model["file"] = _reporter().write_report("fatal", str(model["text"]))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("AppState") if tree != null else null
	if state != null and state.has_method("go"):
		state.call("go", AppFlow.Mode.FATAL, model)
	return model


static func _reporter() -> AppCrashReporter:
	if reporter == null:
		reporter = AppCrashReporter.new()
	return reporter
