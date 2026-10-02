class_name UiOptionsPageInterface
extends UiOptionsPage
## Interface page (ui.md 5.18.1): interface scale with the effective value shown, tooltips, sidebar, cursors, the accessibility
## block (colour mode with a live swatch preview of the eight team colours in both sets, high contrast, reduce motion and
## flashes, font, cursor size) and the camera speeds with edge scrolling.

var _scale_note: Label = null
var _swatch: UiTeamSwatch = null


func special_row(id: String) -> Control:
	if id == "@swatch":
		_swatch = UiTeamSwatch.new()
		return _swatch
	return null


func make_row(id: String, override_schema: Dictionary = {}) -> UiOptRow:
	var r: UiOptRow = super.make_row(id, override_schema)
	if id == "video/ui_scale" and r != null:
		_scale_note = UiScreenKit.label("", &"CaptionLabel")
		_scale_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_scale_note.custom_minimum_size = Vector2(120.0, 0.0)
		r.add_child(_scale_note)
	return r


func on_refresh() -> void:
	if _scale_note != null:
		var win: Vector2i = Vector2i(get_window().size) if is_inside_tree() else Vector2i(1920, 1080)
		var pct: int = int(store().get_value(&"video/ui_scale"))
		var eff: int = AppApply.effective_pct(win, pct)
		_scale_note.text = "effective %d%%" % eff if eff != pct else ""
	var tip: UiOptRow = row_for("ui/tooltip_delay_ms")
	if tip != null:
		tip.set_enabled(bool(store().get_value(&"ui/tooltips")))
	var speed: UiOptRow = row_for("access/edge_scroll_speed")
	if speed != null:
		speed.set_enabled(bool(store().get_value(&"access/edge_scroll_enabled")))
	if _swatch != null:
		_swatch.set_mode(str(store().get_value(&"access/colour_mode")))


func apply(id: String, value: Variant) -> void:
	super.apply(id, value)
	# cursor size, style and contrast are baked into the images: re-register them (5.18.3)
	if id == "access/cursor_scale" or id == "ui/cursor_style" or id == "access/high_contrast_hud" or id == "access/colour_mode":
		UiCursors.refresh()
