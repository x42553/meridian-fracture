class_name AppLaunchArgs
extends RefCounted
## Parsed `OS.get_cmdline_user_args()` (ui.md 5.2.3). Pure and unit-tested. `--key=value` and bare `--flag` (= true) forms;
## unknown pairs land in `extras` (passed to screens, e.g. `--preview=`, `--page=`). Arguments without a leading `--`
## are kept in `positional`.

var smoke: bool = false
var selfcheck: bool = false
var qa_job: String = ""
var screen: StringName = &""
var autostart: StringName = &""
var config_path: String = ""
var fixture: String = ""
var ticks: int = 0
var quit_on_end: bool = false
var fresh_settings: bool = false
var no_audio: bool = false
var no_prewarm: bool = false
var with_ui: bool = false
## `--speed=<pct>`: 0 = unpaced, else percent (default 100).
var speed_pct: int = 100
var faction: String = ""
var roster: String = ""
## `--ui-scale=1.5` (0 = not given).
var ui_scale: float = 0.0
## `--palette=normal|cvd` ("" = not given).
var palette: String = ""
var renderer_relaunched: bool = false
var timeout_s: int = 600
## `--shot=<png>` present (DevShot): the window must not be resized by the saved settings.
var shot: bool = false
var extras: Dictionary = {}
var positional: PackedStringArray = PackedStringArray()


static func parse(args: PackedStringArray) -> AppLaunchArgs:
	var a: AppLaunchArgs = AppLaunchArgs.new()
	for raw: String in args:
		if not raw.begins_with("--"):
			if not raw.is_empty():
				a.positional.append(raw)
			continue
		var body: String = raw.substr(2)
		if body.is_empty():
			continue
		var key: String = body
		var value: String = ""
		var has_value: bool = false
		var eq: int = body.find("=")
		if eq >= 0:
			key = body.substr(0, eq)
			value = body.substr(eq + 1)
			has_value = true
		a._apply_arg(key, value, has_value)
	return a


func _apply_arg(key: String, value: String, has_value: bool) -> void:
	match key:
		"smoke":
			smoke = _truthy(value, has_value)
		"selfcheck":
			selfcheck = _truthy(value, has_value)
		"qa":
			qa_job = value
		"screen":
			screen = StringName(value)
		"autostart":
			autostart = StringName(value)
		"config":
			config_path = value
		"fixture":
			fixture = value
		"ticks":
			ticks = maxi(0, value.to_int())
		"quit-on-end":
			quit_on_end = _truthy(value, has_value)
		"fresh-settings":
			fresh_settings = _truthy(value, has_value)
		"no-audio":
			no_audio = _truthy(value, has_value)
		"no-prewarm":
			no_prewarm = _truthy(value, has_value)
		"with-ui":
			with_ui = _truthy(value, has_value)
		"speed":
			speed_pct = maxi(0, value.to_int())
		"faction":
			faction = value
		"roster":
			roster = value
		"ui-scale":
			ui_scale = clampf(value.to_float(), 0.0, 4.0)
		"palette":
			palette = value
		"renderer-relaunched":
			renderer_relaunched = _truthy(value, has_value)
		"timeout-s":
			timeout_s = maxi(1, value.to_int())
		"shot":
			shot = true
			extras[key] = value
		_:
			if has_value:
				extras[key] = value
			else:
				extras[key] = true


static func _truthy(value: String, has_value: bool) -> bool:
	if not has_value:
		return true
	return not (value == "0" or value.to_lower() == "false" or value.to_lower() == "off")


## Whether the process may resize / move the window from saved settings (screenshots and headless runs may not).
func manages_window() -> bool:
	return not shot


## Test and tool modes never write the `.session` sentinel or the user settings.
func is_test_mode() -> bool:
	return smoke or selfcheck or shot or not qa_job.is_empty() or not autostart.is_empty() or fresh_settings
