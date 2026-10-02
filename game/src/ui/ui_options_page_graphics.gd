class_name UiOptionsPageGraphics
extends UiOptionsPage
## Graphics page (ui.md 5.18.1): adapter info line, window / vsync / frame-cap rows, the preset drop-down with the
## "Custom (based on High)" note, the advanced quality foldout and the renderer row with its Apply-and-restart button.
## Choosing a preset drops every quality override (`AppGraphics.clear_overrides`) so the preset's own values apply again;
## touching an advanced row stores that one key only.

var _custom: Label = null
var _restart: Button = null


func has_custom(id: String) -> bool:
	return id == "video/quality" or id == "video/renderer"


func special_row(id: String) -> Control:
	match id:
		"@adapter":
			return _adapter_line()
		"video/quality":
			var r: UiOptRow = make_row(id)
			_custom = UiScreenKit.label("", &"CaptionLabel")
			_custom.add_theme_color_override("font_color", UiPalette.WARN)
			_custom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(_custom)
			return r
		"video/renderer":
			var rr: UiOptRow = make_row(id)
			_restart = UiScreenKit.button("Apply and restart", &"", Vector2(170.0, 34.0))
			_restart.pressed.connect(_restart_pressed)
			_restart.visible = false
			rr.add_child(_restart)
			return rr
	return null


func _adapter_line() -> Control:
	var l: Label = UiScreenKit.label(adapter_text(), &"DimLabel", true)
	l.custom_minimum_size = Vector2(UiOptRow.LABEL_W + UiOptRow.CONTROL_W, 0.0)
	return l


## "Apple M3 Pro (Integrated GPU), Metal 3.1 - Forward+ on metal".
static func adapter_text() -> String:
	var kinds: PackedStringArray = ["Other", "Integrated GPU", "Discrete GPU", "Virtual GPU", "CPU"]
	var t: int = RenderingServer.get_video_adapter_type()
	var kind: String = kinds[t] if t >= 0 and t < kinds.size() else "Other"
	var api: String = RenderingServer.get_video_adapter_api_version()
	var adapter: String = RenderingServer.get_video_adapter_name()
	if adapter.is_empty():
		adapter = "Unknown adapter"
	var method: String = RenderingServer.get_current_rendering_method()
	var driver: String = RenderingServer.get_current_rendering_driver_name()
	var pretty: String = {"forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibility"}.get(method, method)
	return "%s (%s)%s. Rendering method %s, driver %s." % [adapter, kind, ", API " + api if not api.is_empty() else "", pretty, driver]


func _on_row_changed(id: String, value: Variant) -> void:
	if id == "video/quality":
		# a preset choice removes the overrides; the store then equals the preset's values again
		AppGraphics.clear_overrides(store())
		var before: Variant = store().get_value(&"video/quality")
		settings.call("set_value", &"video/quality", value)
		AppApply.on_changed(&"video/quality", store(), settings.get("overrides") as Dictionary)
		settings.call("flush")
		refresh()
		setting_changed.emit(id, value, before)
		return
	super._on_row_changed(id, value)


func on_refresh() -> void:
	if _custom != null:
		var label: String = AppGraphics.preset_label(store())
		_custom.text = label if label.begins_with("Custom") else ""
	var res: UiOptRow = row_for("video/resolution")
	if res != null:
		res.set_enabled(store().get_value(&"video/window_mode") == 0, UiOptionsText.guard_reason(&"windowed_only"))
	if _restart != null:
		var want: String = str(store().get_value(&"video/renderer"))
		var cur: String = RenderingServer.get_current_rendering_method()
		_restart.visible = want != "" and want != cur and AppRelaunch.supported()


func _restart_pressed() -> void:
	settings.call("flush")
	var method: String = str(store().get_value(&"video/renderer"))
	if AppRelaunch.METHODS.has(method):
		AppRelaunch.relaunch(method)
