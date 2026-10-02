class_name AppPlaceholderScreen
extends UiScreen
## Stand-in for a screen whose real class (`UiScreen<Name>`) is not in the project yet. It shows the screen id and a button
## for every legal next mode of the flow graph, so the whole flow can be walked before the real screens land. For
## `fatal` it is a working fatal screen: technical report, Copy report, Open logs folder, Retry, Quit.

var _params: Dictionary = {}


func enter(params: Dictionary) -> void:
	_params = params
	UiLayerRoot.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back: ColorRect = ColorRect.new()
	back.color = UiPalette.BG_DEEP
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	UiLayerRoot.fill(back)
	add_child(UiVignette.new(0.7, 0.06, 0.0, 0.0, get_theme_color(&"accent", UiTheme.ACCENT_TYPE)))
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	UiLayerRoot.fill(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	center.add_child(panel)
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(pad)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	pad.add_child(col)
	if screen_id == &"fatal":
		_build_fatal(col)
	else:
		_build_placeholder(col)
	setup_menu_focus()


func default_focus() -> Control:
	return _first_button


var _first_button: Button = null


func _title(col: Control, text: String, sub: String) -> void:
	var t: Label = Label.new()
	t.text = text
	t.theme_type_variation = &"TitleLabel"
	col.add_child(t)
	var s: Label = Label.new()
	s.text = sub
	s.theme_type_variation = &"DimLabel"
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(s)
	col.add_child(HSeparator.new())


func _button(text: String, kind: StringName, on_press: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = kind
	b.custom_minimum_size = Vector2(0.0, 44.0)
	b.pressed.connect(on_press)
	if _first_button == null:
		_first_button = b
	return b


func _build_placeholder(col: VBoxContainer) -> void:
	_title(col, String(screen_id).replace("_", " ").to_upper(), "This screen is delivered by a later UI task. The flow is live: pick a legal next step.")
	var mode: int = AppFlow.mode_of_screen(screen_id, _params)
	var targets: Array = []
	for m: int in AppFlow.Mode.values():
		if m != AppFlow.Mode.BOOT and AppFlow.can_go(mode, m) and m != AppFlow.Mode.FATAL:
			targets.append(m)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	for m: int in targets:
		var to: int = m
		var b: Button = _button(AppFlow.mode_name(to).replace("_", " "), &"PrimaryButton" if to == AppFlow.Mode.MAIN_MENU else &"HeroButton",
			func() -> void: _go(to))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	if AppFlow.is_overlay(mode):
		col.add_child(_button("BACK", &"GhostButton", func() -> void: back_requested.emit()))


func _go(to: int) -> void:
	var target: StringName = AppFlow.screen_id_of(to)
	var p: Dictionary = {}
	if to == AppFlow.Mode.LAN_LOBBY:
		p["lan"] = true
	if to == AppFlow.Mode.REPLAY_PLAYBACK:
		p["replay"] = true
	if to == AppFlow.Mode.QUIT:
		navigate.emit(&"quit", {})
		return
	navigate.emit(target, p)


func _build_fatal(col: VBoxContainer) -> void:
	var model: Dictionary = _params
	var reason: int = int(model.get("reason", AppCrash.Reason.UNKNOWN))
	_title(col, "SOMETHING WENT WRONG", str(model.get("message", AppCrash.message(reason))))
	var box: TextEdit = TextEdit.new()
	box.editable = false
	box.custom_minimum_size = Vector2(0.0, 300.0)
	box.text = str(model.get("text", model.get("detail", "")))
	box.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	box.add_theme_font_size_override("font_size", 13)
	col.add_child(box)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(_button("COPY REPORT", &"PrimaryButton", func() -> void: DisplayServer.clipboard_set(box.text)))
	row.add_child(_button("OPEN LOGS FOLDER", &"Button", func() -> void: OS.shell_open(AppPaths.globalize(AppPaths.LOGS_DIR))))
	if bool(model.get("retry", false)):
		row.add_child(_button("RETRY", &"Button", func() -> void: navigate.emit(&"main_menu", {})))
	row.add_child(_button("QUIT", &"DangerButton", func() -> void: navigate.emit(&"quit", {})))


func on_escape() -> bool:
	return screen_id == &"fatal"


func can_leave() -> bool:
	return AppFlow.is_overlay(AppFlow.mode_of_screen(screen_id, _params))
