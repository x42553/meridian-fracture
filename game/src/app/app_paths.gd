class_name AppPaths
extends RefCounted
## Every `user://` and `res://` path constant of the app layer, in one place (exact case), plus `ensure_user_dirs()` and
## the compact UTC stamp used in file names (ui.md 2.1, 5.20). `user://` resolves to the OS profile folder named by
## `config/custom_user_dir_name`; the app never writes anywhere else.

const SETTINGS: String = "user://settings.cfg"
const SETTINGS_BAK: String = "user://settings.cfg.bak"
const SETTINGS_TMP: String = "user://settings.cfg.tmp"
const SESSION: String = "user://.session"
const CAMPAIGN: String = "user://campaign.cfg"  ## campaign progress (AppCampaign); the .bak / .tmp siblings follow the settings rules
const LOGS_DIR: String = "user://logs"
const CRASH_DIR: String = "user://logs/crash"
const ENGINE_LOG: String = "user://logs/godot.log"
const CACHE_ICONS: String = "user://cache/icons"
const CACHE_MODELS: String = "user://cache/models"
const SCREENSHOTS_DIR: String = "user://screenshots"
const BOOT_SCENE: String = "res://src/app/boot.tscn"
# lint-allow: L001,L005 the QA hook of qa.md QA-XR-11: the file exists only in QA builds
const QA_ENTRY: String = "res://tests/harness/qa_entry.gd"
const STYLE_JSON: String = "res://data/recipes/style.json"
# lint-allow: L001 written by the exporter, absent in development
const BUILD_ID_FILE: String = "res://data/build_id.txt"

const USER_DIRS: PackedStringArray = [LOGS_DIR, CRASH_DIR, CACHE_ICONS, CACHE_MODELS, SCREENSHOTS_DIR]


## Creates the standard user folders; returns the number of folders that could not be created (0 = all present).
static func ensure_user_dirs() -> int:
	var failed: int = 0
	for dir: String in USER_DIRS:
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			failed += 1
	return failed


## Compact UTC time stamp `20260929T140311Z` (file names). `unix < 0` = now.
static func utc_stamp(unix: int = -1) -> String:
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix if unix >= 0 else int(Time.get_unix_time_from_system()))
	return "%04d%02d%02dT%02d%02d%02dZ" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]


## ISO form `2026-09-29T14:03:11Z` (the `.session` record). `unix < 0` = now.
static func utc_iso(unix: int = -1) -> String:
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix if unix >= 0 else int(Time.get_unix_time_from_system()))
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]


## Absolute filesystem path of a `user://` path (report headers, "Open logs folder").
static func globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path)
