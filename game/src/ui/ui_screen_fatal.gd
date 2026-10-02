class_name UiScreenFatal
extends UiScreen
## Fatal-error screen (ui.md 5.2 / 5.20.3): what happened in one plain sentence, the technical report in a read-only monospace
## box (header, reason, detail, log tail), and Copy report, Open logs folder, Retry (back to the main menu, only for reasons
## that can recover) and Quit. Danger-toned but calm. Params: the `AppCrash.build` model `{reason, message, detail, text, retry}`.

var _params: Dictionary = {}
var _first: Button = null


func _init() -> void:
	super._init()
	screen_id = &"fatal"


func enter(params: Dictionary) -> void:
	_params = params
	mouse_filter = Control.MOUSE_FILTER_STOP
	var danger: Color = UiPalette.semantic(&"danger")
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.95, 0.06, 0.0, 0.05, danger))
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	UiLayerRoot.fill(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(920.0, 0.0)
	center.add_child(panel)
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 32)
	for side: String in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(m)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	m.add_child(col)
	var stripe: ColorRect = ColorRect.new()
	stripe.color = danger
	stripe.custom_minimum_size = Vector2(0.0, 4.0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stripe)
	col.add_child(UiScreenKit.wordmark("SOMETHING WENT WRONG", 34, 800, 3, UiPalette.TEXT))
	var reason: int = int(_params.get("reason", AppCrash.Reason.UNKNOWN))
	col.add_child(UiScreenKit.label(str(_params.get("message", AppCrash.message(reason))), &"SubLabel", true))
	col.add_child(UiScreenKit.label("TECHNICAL REPORT", &"CaptionLabel"))
	var box: TextEdit = TextEdit.new()
	box.editable = false
	box.custom_minimum_size = Vector2(0.0, 300.0)
	box.text = str(_params.get("text", _params.get("detail", "")))
	box.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	box.add_theme_font_size_override("font_size", 13)
	col.add_child(box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_first = _button(row, "COPY REPORT", &"PrimaryButton", func() -> void: DisplayServer.clipboard_set(box.text))
	_button(row, "OPEN LOGS FOLDER", &"", func() -> void: OS.shell_open(AppPaths.globalize(AppPaths.LOGS_DIR)))
	var sp: Control = UiScreenKit.spacer(0.0, true)
	row.add_child(sp)
	if bool(_params.get("retry", false)):
		_button(row, "RETRY", &"", func() -> void: navigate.emit(&"main_menu", {}))
	_button(row, "QUIT", &"DangerButton", func() -> void: navigate.emit(&"quit", {}))


func _button(row: HBoxContainer, text: String, kind: StringName, on_press: Callable) -> Button:
	var b: Button = UiScreenKit.button(text, kind, Vector2(170.0, 42.0))
	b.pressed.connect(on_press)
	row.add_child(b)
	return b


func default_focus() -> Control:
	return _first


func on_escape() -> bool:
	return true


func can_leave() -> bool:
	return false
