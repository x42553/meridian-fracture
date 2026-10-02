class_name AppInfo
extends RefCounted
## Version and platform strings (QA-XR-14): the extended `MERIDIAN_BOOT` smoke line and the report headers.


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Short build identifier: `data/build_id.txt` when the exporter wrote one, else "dev".
static func build_id() -> String:
	if FileAccess.file_exists(AppPaths.BUILD_ID_FILE):
		var id: String = FileAccess.get_file_as_string(AppPaths.BUILD_ID_FILE).strip_edges()
		if not id.is_empty():
			return id.substr(0, 16)
	return "dev"


## "macOS 27.0 arm64", "Debian GNU/Linux 12 x86_64", "Windows 11 x86_64".
static func platform_string() -> String:
	var name: String = OS.get_name()
	var ver: String = OS.get_version_alias()
	if ver.is_empty() or ver.contains("Unknown"):
		ver = _short_version(OS.get_version())
	var distro: String = OS.get_distribution_name()
	if name == "Linux" and not distro.is_empty():
		return "%s %s %s" % [distro, ver, Engine.get_architecture_name()]
	if name == "macOS" or name == "Windows":
		if ver.begins_with(name):
			return "%s %s" % [ver, Engine.get_architecture_name()]
		return "%s %s %s" % [name, ver, Engine.get_architecture_name()]
	return "%s %s %s" % [name, ver, Engine.get_architecture_name()]


## "27.0.0" -> "27.0" (major.minor of the OS version string; anything else is returned as is).
static func _short_version(v: String) -> String:
	var parts: PackedStringArray = v.split(".")
	if parts.size() >= 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return "%s.%s" % [parts[0], parts[1]]
	return v


## "4.7.2-stable".
static func engine_string() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%d.%d.%d-%s" % [info["major"], info["minor"], info["patch"], info["status"]]


## Number of failed `Fp.self_test()` checks (0 = ok).
static func selftest_failures() -> int:
	return Fp.self_test().size()


## `MERIDIAN_BOOT engine=… renderer=… os=… debug=… version=… build=… selftest=<ok|N>`. `selftest` = number of failed checks.
## export.py parses by prefix and the leading keys never change.
static func smoke_line(selftest: int) -> String:
	return "MERIDIAN_BOOT engine=%s renderer=%s os=%s debug=%d version=%s build=%s selftest=%s" % [
		engine_string(), RenderingServer.get_current_rendering_method(), OS.get_name(),
		1 if OS.is_debug_build() else 0, version(), build_id(), "ok" if selftest == 0 else str(selftest)]
