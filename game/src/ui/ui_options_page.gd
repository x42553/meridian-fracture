class_name UiOptionsPage
extends VBoxContainer
## Base of the schema-driven options pages (ui.md 5.18): builds the sections of `UiOptionsLayout.sections(page)` from
## `AppSettingsSchema` rows, applies every change through the settings node (`set_value`: validate, apply live, debounced save),
## evaluates the capability guards (5.18.4), and keeps the "values seen when the page opened" snapshot for Revert.
## Subclasses override `special_row(id)` for the pseudo rows (`@adapter`, `@keys`, ...) and rows that need a custom control, and
## `on_refresh()` for dependencies between rows. The page emits `setting_changed(id, value, before)`; the screen decides whether
## the change needs the 15-second confirmation.

signal setting_changed(id: String, value: Variant, before: Variant)

var page_id: StringName = &""
## The `AppSettings` node (or any node with `store: AppSettingsStore` and `set_value(id, value)`).
var settings: Node = null

var _rows: Dictionary = {}  ## schema id -> UiOptRow
var _snapshot: Dictionary = {}  ## schema id -> value seen when the page opened
var _folds: Array[Control] = []
var _presets: Dictionary = {}
var _heads: Array[Label] = []


## Builds the page. `settings_node` is the settings autoload (or a test double).
func setup(page: StringName, settings_node: Node) -> void:
	page_id = page
	settings = settings_node
	add_theme_constant_override("separation", UiMetrics.SP_2)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sec: Dictionary in UiOptionsLayout.sections(page):
		_build_section(sec)
	_snapshot = snapshot()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_THEME_CHANGED:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		for h: Label in _heads:
			h.add_theme_color_override("font_color", acc)


func store() -> AppSettingsStore:
	return settings.get("store") as AppSettingsStore


## The row widget of a schema id (null when the id is not on this page).
func row_for(id: String) -> UiOptRow:
	return _rows.get(id) as UiOptRow


func row_ids() -> PackedStringArray:
	return PackedStringArray(_rows.keys())


func _build_section(sec: Dictionary) -> void:
	var head: Label = UiScreenKit.label(str(sec["title"]).to_upper(), &"CaptionLabel")
	_heads.append(head)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(sec["foldout"]):
		var fold: Button = UiScreenKit.button("▸  " + str(sec["title"]).to_upper(), &"GhostButton")
		fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
		fold.focus_mode = Control.FOCUS_ALL
		fold.pressed.connect(func() -> void:
			body.visible = not body.visible
			fold.text = ("▾  " if body.visible else "▸  ") + str(sec["title"]).to_upper())
		add_child(_gap())
		add_child(fold)
		head.visible = false
		add_child(head)  # kept in the tree (hidden): an orphan Label leaked at exit
		body.visible = false
		_folds.append(body)
	else:
		add_child(_gap())
		add_child(head)
		add_child(_rule())
	add_child(body)
	for id: String in sec["rows"] as PackedStringArray:
		var w: Control = null
		if id.begins_with("@") or has_custom(id):
			w = special_row(id)
		else:
			var r: UiOptRow = make_row(id)
			if r != null:
				w = r
		if w != null:
			body.add_child(w)


func _gap() -> Control:
	return UiScreenKit.spacer(10.0)


func _rule() -> Control:
	var r: ColorRect = ColorRect.new()
	r.color = UiPalette.LINE_DIM
	r.custom_minimum_size = Vector2(0.0, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Whether `id` is a schema row the subclass builds itself.
func has_custom(_id: String) -> bool:
	return false


## Virtual: the control for a pseudo row (`@...`) or a custom schema row; null hides the row.
func special_row(_id: String) -> Control:
	return null


## Generic schema row: registers the widget and wires its signals.
func make_row(id: String, override_schema: Dictionary = {}) -> UiOptRow:
	var schema: Dictionary = override_schema if not override_schema.is_empty() else AppSettingsSchema.entry(StringName(id))
	if schema.is_empty():
		return null
	var r: UiOptRow = UiOptRow.make(schema, value_of(id), store().is_default(StringName(id)))
	_rows[id] = r
	r.changed.connect(_on_row_changed)
	r.reset_requested.connect(func(rid: String) -> void: reset_row(rid))
	return r


func register_row(id: String, r: UiOptRow) -> void:
	_rows[id] = r
	r.changed.connect(_on_row_changed)
	r.reset_requested.connect(func(rid: String) -> void: reset_row(rid))


## The value to show for `id`: the stored value, or (preset rows that are unset) the preset's own value.
func value_of(id: String) -> Variant:
	var v: Variant = store().get_value(StringName(id))
	if v == null and bool(AppSettingsSchema.entry(StringName(id)).get("preset", false)):
		return preset_value(id.get_slice("/", 1))
	return v


## The value the current preset gives a quality key (what an unset preset row means).
func preset_value(key: String) -> Variant:
	var p: int = int(store().get_value(&"video/quality"))
	if p == AppGraphics.Preset.AUTO:
		p = AppGraphics.recommend()
	if _presets.is_empty():
		_presets = ViewQuality.load_presets()
	var q: ViewQuality = ViewQuality.create(_presets, clampi(p, 0, 3), ViewQuality.detect_renderer())
	return q.values.get(key)


func _on_row_changed(id: String, value: Variant) -> void:
	apply(id, value)


## Sets a value through the settings node and refreshes dependent rows.
func apply(id: String, value: Variant) -> void:
	var before: Variant = store().get_value(StringName(id))
	settings.call("set_value", StringName(id), value)
	var after: Variant = store().get_value(StringName(id))
	refresh()
	if before != after:
		setting_changed.emit(id, after, before)


func reset_row(id: String) -> void:
	apply(id, null)


## Re-reads every row from the store and re-evaluates the guards.
func refresh() -> void:
	var st: AppSettingsStore = store()
	for id: String in _rows:
		var r: UiOptRow = _rows[id]
		r.show_value(value_of(id), st.is_default(StringName(id)))
		_guard_row(id, r)
	on_refresh()


## Virtual: dependencies between rows (a page-specific enable rule); called after every refresh.
func on_refresh() -> void:
	pass


func _guard_row(id: String, r: UiOptRow) -> void:
	var schema: Dictionary = r.row
	var guard: StringName = StringName(schema.get("guard", &""))
	if guard == &"":
		r.set_enabled(true)
		return
	var ok: bool = guard_ok(guard)
	if id == "video/renderer" and not ok:
		r.visible = false
		return
	r.visible = true
	r.set_enabled(ok, UiOptionsText.guard_reason(guard))


## Capability predicate; `windowed_only` follows the setting (the window mode is applied live).
func guard_ok(guard: StringName) -> bool:
	if guard == &"windowed_only":
		return store().get_value(&"video/window_mode") == 0
	return AppSettingsSchema.guard_ok(guard)


# ---------------------------------------------------------------------------------------------------------------- snapshot

## `{id: value}` of every row on the page (preset rows keep null = unset).
func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _rows:
		out[id] = store().get_value(StringName(id))
	return out


## Restores the values seen when the page opened; returns the number of rows that changed.
func revert() -> int:
	return restore(_snapshot)


func restore(snap: Dictionary) -> int:
	var n: int = 0
	for id: String in snap:
		var now: Variant = store().get_value(StringName(id))
		if now != snap[id]:
			settings.call("set_value", StringName(id), snap[id])
			n += 1
	refresh()
	return n


## Marks the current values as the new "seen when opened" state (after the player kept a change).
func commit_snapshot() -> void:
	_snapshot = snapshot()


## Number of rows differing from the opening snapshot.
func changed_count() -> int:
	var n: int = 0
	for id: String in _snapshot:
		if store().get_value(StringName(id)) != _snapshot[id]:
			n += 1
	return n


## Resets every row of the page to its default.
func reset_defaults() -> void:
	for id: String in _rows:
		settings.call("set_value", StringName(id), null)
	on_reset_defaults()
	refresh()


## Virtual: extra work when the page is reset (e.g. the key table).
func on_reset_defaults() -> void:
	pass
