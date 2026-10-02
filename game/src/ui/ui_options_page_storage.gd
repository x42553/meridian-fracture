class_name UiOptionsPageStorage
extends UiOptionsPage
## Storage page (ui.md 5.18.1): sizes of logs, crash reports, replays, screenshots and caches under `user://` (a `DirAccess`
## walk cached for 5 s) with Open-folder buttons and Clear caches, and a warning line above 1 GB in total.

const FOLDERS: Array[Dictionary] = [
	{"id": "logs", "title": "Logs", "path": "user://logs"},
	{"id": "crashes", "title": "Crash reports", "path": "user://crashes"},
	{"id": "replays", "title": "Replays", "path": "user://replays"},
	{"id": "screenshots", "title": "Screenshots", "path": "user://screenshots"},
	{"id": "cache", "title": "Caches", "path": "user://cache"},
]
const WARN_BYTES: int = 1 << 30
const CACHE_S: float = 5.0

static var _cached_at_ms: int = -100000
static var _cached: Dictionary = {}

var _labels: Dictionary = {}
var _total: Label = null
var _warn: Label = null


func special_row(id: String) -> Control:
	if id != "@storage":
		return null
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	for f: Dictionary in FOLDERS:
		var h: HBoxContainer = HBoxContainer.new()
		h.add_theme_constant_override("separation", UiMetrics.SP_3)
		var title: Label = UiScreenKit.label(str(f["title"]))
		title.custom_minimum_size = Vector2(UiOptRow.LABEL_W, 0.0)
		h.add_child(title)
		var size_l: Label = UiScreenKit.label("...", &"DimLabel")
		size_l.custom_minimum_size = Vector2(140.0, 0.0)
		h.add_child(size_l)
		_labels[f["id"]] = size_l
		var open_b: Button = UiScreenKit.button("Open folder", &"", Vector2(140.0, 34.0))
		var path: String = str(f["path"])
		open_b.pressed.connect(func() -> void: open_folder(path))
		h.add_child(open_b)
		if f["id"] == "cache":
			var clear_b: Button = UiScreenKit.button("Clear caches", &"", Vector2(140.0, 34.0))
			clear_b.pressed.connect(func() -> void:
				clear_caches()
				refresh_sizes(true))
			h.add_child(clear_b)
		col.add_child(h)
	_total = UiScreenKit.label("", &"SubLabel")
	col.add_child(_total)
	_warn = UiScreenKit.label("", &"DimLabel", true)
	_warn.add_theme_color_override("font_color", UiPalette.WARN)
	col.add_child(_warn)
	refresh_sizes()
	return col


func on_refresh() -> void:
	refresh_sizes()


## Sizes in bytes per folder id, cached for `CACHE_S` seconds unless `force`.
static func sizes(force: bool = false) -> Dictionary:
	var now: int = Time.get_ticks_msec()
	if not force and now - _cached_at_ms < int(CACHE_S * 1000.0) and not _cached.is_empty():
		return _cached
	var out: Dictionary = {}
	for f: Dictionary in FOLDERS:
		out[f["id"]] = folder_bytes(str(f["path"]))
	_cached = out
	_cached_at_ms = now
	return out


static func folder_bytes(path: String, depth: int = 0) -> int:
	var total: int = 0
	var d: DirAccess = DirAccess.open(path)
	if d == null or depth > 6:
		return 0
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		var full: String = path.path_join(entry)
		if d.current_is_dir():
			total += folder_bytes(full, depth + 1)
		else:
			var f: FileAccess = FileAccess.open(full, FileAccess.READ)
			if f != null:
				total += f.get_length()
		entry = d.get_next()
	d.list_dir_end()
	return total


## "12.4 MB" (one decimal, integer maths).
static func bytes_text(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	if n < 1024 * 1024:
		return "%s KB" % DefFormat.tenths_text(n * 10 / 1024)
	if n < 1 << 30:
		return "%s MB" % DefFormat.tenths_text(n * 10 / (1024 * 1024))
	return "%s GB" % DefFormat.tenths_text(n * 10 / (1 << 30))


func refresh_sizes(force: bool = false) -> void:
	if _total == null:
		return
	var s: Dictionary = sizes(force)
	var total: int = 0
	for id: String in s:
		total += int(s[id])
		if _labels.has(id):
			(_labels[id] as Label).text = bytes_text(int(s[id]))
	_total.text = "Total  %s" % bytes_text(total)
	_warn.text = "The game files use more than 1 GB. Clear the caches or delete old replays." if total > WARN_BYTES else ""


static func open_folder(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	OS.shell_open(ProjectSettings.globalize_path(path))


## Deletes the files under `user://cache` (folders stay).
static func clear_caches() -> void:
	_clear_dir(ProjectSettings.globalize_path("user://cache"))


static func _clear_dir(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		var full: String = path.path_join(entry)
		if d.current_is_dir():
			_clear_dir(full)
		else:
			DirAccess.remove_absolute(full)
		entry = d.get_next()
	d.list_dir_end()
