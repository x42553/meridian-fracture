extends Node
## Autoload `AppSettings` (no class_name, ui.md 2.1 / 3.1): owns one `AppSettingsStore`, the debounced save (0.5 s), the flush
## on quit / focus-out, the `changed(id)` signal and the `AppApply` calls. Initialises lazily (`_init` and every accessor call
## `ensure_loaded()`), so it also works where `_ready` has not run. It touches neither scenes nor sessions.
## CLI overrides (`set_overrides`) win over the store and are never persisted.

signal changed(id: StringName)
signal graphics_quality_changed()
## Human-readable problem with the settings file (corrupt / not writable): a toast text for the boot code.
signal notice(text: String)

const SAVE_DEBOUNCE_S: float = 0.5

var store: AppSettingsStore = null
var path: String = AppPaths.SETTINGS
## true = never touches the disk (`--fresh-settings`, tests).
var in_memory: bool = false
var files: AppFileLayer = null
var overrides: Dictionary = {}

var _loaded: bool = false
var _save_left: float = -1.0
var _write_failed: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_loaded()


## Idempotent; loads `user://settings.cfg` on first use.
func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	store = AppSettingsStore.with_defaults()
	if files == null:
		files = AppFileLayer.new()
	if in_memory:
		return
	store.load_from(path, files)
	for note: String in store.load_notes:
		notice.emit(note)


## Re-targets the store (tests, sandboxes, `--fresh-settings`): a fresh store, optionally in memory, optionally another file.
func configure(new_path: String = AppPaths.SETTINGS, memory: bool = false, file_layer: AppFileLayer = null) -> void:
	path = new_path
	in_memory = memory
	files = file_layer if file_layer != null else AppFileLayer.new()
	_loaded = false
	_save_left = -1.0
	_write_failed = false
	set_process(false)
	ensure_loaded()


func _value(id: StringName) -> Variant:
	ensure_loaded()
	return AppApply.value(store, id, overrides)


func get_int(id: StringName) -> int:
	return int(_value(id))


func get_bool(id: StringName) -> bool:
	return bool(_value(id))


func get_float(id: StringName) -> float:
	return float(_value(id))


func get_str(id: StringName) -> String:
	return str(_value(id))


## Validate + clamp -> store -> schedule the save (0.5 s debounce) -> `AppApply.on_changed`.
func set_value(id: StringName, value: Variant) -> void:
	ensure_loaded()
	var before: Variant = store.get_value(id)
	if not store.set_value(id, value):
		Log.warn("app", "settings: rejected %s" % id)
		return
	if store.get_value(id) == before:
		return
	_schedule_save()
	AppApply.on_changed(id, store, overrides)
	changed.emit(id)
	var row: Dictionary = AppSettingsSchema.entry(id)
	if not row.is_empty() and StringName(row["apply"]) == &"quality":
		graphics_quality_changed.emit()


## Boot: display, audio, input, UI scale, quality. `manage_window = false` leaves the window rectangle alone.
func apply_all(manage_window: bool = true) -> void:
	ensure_loaded()
	AppApply.apply_all(store, overrides, manage_window)


## CLI/test overrides keyed by id (`{"video/ui_scale": 150}`); never persisted.
func set_overrides(o: Dictionary) -> void:
	overrides = o.duplicate()


## Saves immediately when there is something to write (quit, focus-out, before a match).
func flush() -> void:
	ensure_loaded()
	_save_left = -1.0
	set_process(false)
	if in_memory:
		return
	AppApply.capture_window(store)
	if not store.dirty() and files.exists(path):
		return
	var err: int = store.save_to(path, files)
	if err != OK and not _write_failed:
		_write_failed = true
		notice.emit("Settings could not be saved (%s). Changes are kept for this session." % error_string(err))


func _schedule_save() -> void:
	if in_memory:
		return
	_save_left = SAVE_DEBOUNCE_S
	set_process(true)


func _process(delta: float) -> void:
	if _save_left < 0.0:
		set_process(false)
		return
	_save_left -= delta
	if _save_left <= 0.0:
		flush()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			flush()
			var bg: int = get_int(&"video/background_fps")
			if bg > 0:
				Engine.max_fps = bg
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = get_int(&"video/fps_cap")
		NOTIFICATION_WM_CLOSE_REQUEST:
			flush()
