extends UiLayerRoot
## Widget style sheet lab (UI-01a / UI-02a): every design-system widget on a faux battlefield backdrop.
##   tools/gd shot res://tests/visual/lab_widgets.tscn out.png --size 1920x1080 -- --faction=napc --ui-scale=1.0
## Options: --faction=<code|neutral> (skin), --ui-scale=<x> (video/ui_scale), --mode=sheet|dialog|cvd|hc.
## No class_name on purpose (labs never take real class names).

var _faction: String = "napc"
var _ui_scale: float = 1.0
var _mode: String = "sheet"
var _dialogs: UiDialogStack = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--faction="):
			_faction = arg.substr(10)
		elif arg.begins_with("--ui-scale="):
			_ui_scale = arg.substr(11).to_float()
		elif arg.begins_with("--mode="):
			_mode = arg.substr(7)
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	UiLayout.apply(win, _ui_scale)
	var skins: UiSkinSet = UiSkinSet.shared()
	skins.setup_from_json()
	if _mode == "cvd":
		skins.set_colour_mode(UiSkinSet.ColourMode.CVD)
	var opts: Dictionary = {"cvd": _mode == "cvd", "high_contrast": _mode == "hc"}
	UiThemeService.set_a11y(opts)
	UiThemeService.rebuild(skins.skin_for(_faction))
	_build()
	if _mode == "dialog":
		_dialogs = UiDialogStack.new()
		add_child(_dialogs)
		_dialogs.attach(self)
		var d: UiDialog = UiDialog.confirm(&"ui.confirm", &"ui.confirm", {})
		d.set_title("Surrender match?")
		_dialogs.push(UiDialog.message(&"ui.ok", "Autosave written. You can resume this match from the main menu at any time."))
		var d2 := UiDialog.new("Leave match?")
		d2.add_text("The match is still running for the other players. Leaving now counts as a surrender and the AI takes over your base.")
		d2.add_button("Stay", 0)
		d2.add_button("Surrender", 1, &"danger")
		_dialogs.push(d2)
		_dialogs.close_top(1)


# ---------------------------------------------------------------------------------------------------------- layout

func _build() -> void:
	var back := Backdrop.new()
	add_child(back)
	UiLayerRoot.fill(back)
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	UiLayerRoot.fill(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	margin.add_child(cols)
	var compact: bool = get_viewport_rect().size.y < 1000.0
	if compact:
		margin.add_theme_constant_override("margin_left", 16)
		cols.add_theme_constant_override("separation", 12)
	var col_a: Array[Control] = [_typography(), _tokens(), _skins_panel()]
	if not compact:
		col_a.append(_select_panel())
	cols.add_child(_column(col_a, 430))
	cols.add_child(_column([_buttons(), _icon_buttons(), _tabs_panel(), _dialog_sample()], 480))
	cols.add_child(_column([_lists(), _feedback()], 450))
	var side: Control = _hud_mock()
	add_child(side)
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -(float(UiMetrics.SIDEBAR_W) + 20.0)
	side.offset_right = -20.0
	side.offset_top = 20.0
	side.offset_bottom = -20.0
	margin.add_theme_constant_override("margin_right", UiMetrics.SIDEBAR_W + 44)
	var vig := UiVignette.new(0.55, 0.0, 0.0, 0.0)
	add_child(vig)


func _column(items: Array[Control], width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = width
	v.add_theme_constant_override("separation", 14)
	for it in items:
		v.add_child(it)
	return v


func _panel(title: String, right: String = "", variation: StringName = &"") -> VBoxContainer:
	var p := PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UiPanelHeader.new(title, right))
	# the panel node is the returned handle's parent: keep a reference through metadata
	v.set_meta("panel", p)
	return v


func _done(v: VBoxContainer) -> Control:
	return v.get_meta("panel") as Control


func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if variation != &"":
		l.theme_type_variation = variation
	return l


# ------------------------------------------------------------------------------------------------- column A panels

func _typography() -> Control:
	var v: VBoxContainer = _panel("Typography", "Rajdhani / Orbitron / Share Tech Mono")
	v.add_child(_label("FRACTURE", &"TitleLabel"))
	v.add_child(_label("MERIDIAN COMMAND // HEADER 14", &"HeaderLabel"))
	v.add_child(_label("Sub-heading 18: Liberty Arsenal Engineers", &"SubLabel"))
	v.add_child(_label("Body 15: Harvesters return to the refinery when the silo is full."))
	v.add_child(_label("Dim 14: requires Radar Uplink and a second Power Node", &"DimLabel"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(_label("12,450", &"CreditsLabel"))
	row.add_child(_label("+1,860 / min", &"NumLabel"))
	row.add_child(_label("READY", &"OkLabel"))
	row.add_child(_label("LOW POWER", &"WarnLabel"))
	row.add_child(_label("DENIED", &"DangerLabel"))
	v.add_child(row)
	return _done(v)


func _tokens() -> Control:
	var v: VBoxContainer = _panel("Colour tokens", "18 tokens")
	var names: Array[String] = ["BG_DEEP", "BG_PANEL", "BG_RAISED", "BG_CONTROL", "BG_HOVER", "LINE_DIM", "LINE", "LINE_BRIGHT", "TEXT", "TEXT_DIM", "TEXT_MUTE", "TEXT_DISABLED", "CREDITS", "OK", "WARN", "DANGER", "POWER"]
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for n in names:
		grid.add_child(Swatch.new(UiPalette.token(StringName(n)), n.replace("_", " ")))
	v.add_child(grid)
	return _done(v)


func _skins_panel() -> Control:
	var v: VBoxContainer = _panel("Faction skins + team colours", "accent / accent2 / tint")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var skins: UiSkinSet = UiSkinSet.shared()
	for code in UiSkin.CODES:
		var s: UiSkin = skins.skin_for(code)
		grid.add_child(SkinChip.new(code.to_upper(), s))
	v.add_child(grid)
	v.add_child(TeamRow.new())
	return _done(v)


# ------------------------------------------------------------------------------------------------- column B panels

func _buttons() -> Control:
	var v: VBoxContainer = _panel("Buttons and inputs", "normal / hover / pressed / disabled")
	for recipe: Array in [["Button", "Deploy"], ["PrimaryButton", "Build"], ["DangerButton", "Surrender"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for st: String in ["normal", "hover", "pressed", "disabled"]:
			row.add_child(StateBox.new(recipe[0], st, String(recipe[1])))
		v.add_child(row)
	var hero := Button.new()
	hero.theme_type_variation = &"HeroButton"
	hero.text = "SKIRMISH"
	hero.custom_minimum_size = Vector2(0.0, 54.0)
	v.add_child(hero)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	var b1 := Button.new()
	b1.text = "Options"
	var b2 := Button.new()
	b2.theme_type_variation = &"PrimaryButton"
	b2.text = "Start match"
	var b3 := Button.new()
	b3.theme_type_variation = &"GhostButton"
	b3.text = "Ghost"
	var cb := CheckBox.new()
	cb.text = "Fog of war"
	cb.button_pressed = true
	var cb2 := CheckBox.new()
	cb2.text = "Shroud"
	var tg := CheckButton.new()
	tg.text = "Captions"
	tg.button_pressed = true
	for c: Control in [b1, b2, b3]:
		row2.add_child(c)
	v.add_child(row2)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 16)
	for c: Control in [cb, cb2, tg]:
		row3.add_child(c)
	v.add_child(row3)
	var sl := HSlider.new()
	sl.value = 62.0
	sl.custom_minimum_size = Vector2(0.0, 22.0)
	var opt := OptionButton.new()
	opt.add_item("Liberty Arsenal (vanilla)")
	opt.add_item("Coastal Defence Wing")
	opt.custom_minimum_size = Vector2(0.0, 36.0)
	var le := LineEdit.new()
	le.text = "192.168.1.14:27615"
	var bar := ProgressBar.new()
	bar.value = 64.0
	bar.custom_minimum_size = Vector2(0.0, 18.0)
	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 12)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row4.add_child(opt)
	row4.add_child(le)
	v.add_child(row4)
	v.add_child(sl)
	v.add_child(bar)
	return _done(v)


func _icon_buttons() -> Control:
	var v: VBoxContainer = _panel("Icon buttons", "UiIconButton")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.COMMAND_GAP)
	var specs: Array[Dictionary] = [
		{"g": UiDraw.G_STOP, "hk": "S"}, {"g": UiDraw.G_PLUS, "hk": "A", "active": true}, {"g": UiDraw.G_WARNING, "badge": "3"},
		{"g": UiDraw.G_CHECK, "cap": "READY"}, {"g": UiDraw.G_CLOSE, "off": true}, {"g": UiDraw.G_INFO, "hk": "F1"},
		{"g": UiDraw.G_MINUS, "cap": "SELL", "hk": "V"},
	]
	for s in specs:
		var b := UiIconButton.new()
		b.glyph = int(s["g"])
		b.hotkey = String(s.get("hk", ""))
		b.badge = String(s.get("badge", ""))
		b.caption = String(s.get("cap", ""))
		b.toggle_mode = s.has("active")
		b.active = bool(s.get("active", false))
		if s.has("off"):
			b.set_enabled(false)
		b.set_tip({"title": "Attack move [A]", "tag": "ORDER", "text": "Move to a location and engage anything met on the way."})
		row.add_child(b)
	v.add_child(row)
	return _done(v)


func _tabs_panel() -> Control:
	var v: VBoxContainer = _panel("Tab bars", "UiTabBar")
	var tb := UiTabBar.new()
	var tabs: Array[Dictionary] = [{"id": &"build", "text": "BUILD", "badge": "2"}, {"id": &"units", "text": "UNITS"}, {"id": &"defence", "text": "DEFENCE"}, {"id": &"powers", "text": "POWERS", "enabled": false}]
	tb.set_tabs(tabs)
	tb.select(1)
	v.add_child(tb)
	var gb := UiTabBar.new()
	var gt: Array[Dictionary] = []
	for g: int in [UiDraw.G_PLUS, UiDraw.G_INFO, UiDraw.G_WARNING, UiDraw.G_CHECK, UiDraw.G_MINUS, UiDraw.G_CLOSE, UiDraw.G_CHEVRON_UP, UiDraw.G_CHEVRON_DOWN]:
		gt.append({"id": StringName("g%d" % g), "glyph": g})
	gb.set_tabs(gt)
	gb.select(2)
	gt[0]["badge"] = "1"
	v.add_child(gb)
	return _done(v)


# ------------------------------------------------------------------------------------------------- column C panels

func _lists() -> Control:
	var v: VBoxContainer = _panel("Data list", "UiListRow, one canvas item per row")
	var widths := PackedFloat32Array([116.0, 92.0, 86.0, 72.0])
	var head := UiListRow.new()
	head.is_header = true
	head.set_cells([{"text": "GAME"}, {"text": "MAP"}, {"text": "SLOTS"}, {"text": "PING"}], widths)
	v.add_child(head)
	var rows: Array = [["Saturday LAN", "Dust Basin", "3/4", "12 ms"], ["Simon's game", "Twin Rivers", "1/2", "4 ms"], ["Ranked 2v2", "Iron Ridge", "4/4", "38 ms"], ["Old build", "Dust Basin", "2/8", "9 ms"]]
	for i in rows.size():
		var r := UiListRow.new()
		r.odd = i % 2 == 1
		var d: Array = rows[i]
		r.set_cells([{"text": d[0]}, {"text": d[1], "color": UiPalette.TEXT_DIM}, {"text": d[2], "mono": true}, {"text": d[3], "mono": true, "color": UiPalette.OK}], widths)
		r.is_selected = i == 1
		r.dimmed = i == 3
		v.add_child(r)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(UiProgressChip.new("Loading", "64 %", 0.64, &"accent"))
	chips.add_child(UiProgressChip.new("Ready", "OK", 1.0, &"ok"))
	chips.add_child(UiProgressChip.new("Power", "-45", 0.3, &"danger"))
	for c in chips.get_children():
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(chips)
	return _done(v)


func _feedback() -> Control:
	var v: VBoxContainer = _panel("Toasts and tooltip", "UiToast / UiTooltipBody")
	var t1: UiToast = UiToast.make("Settings saved. Restart to apply the renderer change.", UiToast.Severity.INFO)
	var acts: Array[Dictionary] = [{"label": "Open logs folder", "call": Callable()}, {"label": "Copy report", "call": Callable()}]
	var t2: UiToast = UiToast.make("The last session ended unexpectedly.", UiToast.Severity.WARN, acts)
	var t3: UiToast = UiToast.make("Could not reach the host 192.168.1.14.", UiToast.Severity.ERROR)
	for t: UiToast in [t1, t2, t3]:
		t.hold_s = 9999.0
		t.custom_minimum_size = Vector2(0.0, 44.0)
		v.add_child(t)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiThemeService.current().get_stylebox("panel", "TooltipPanel"))
	var tip: UiTooltipBody = UiTooltipBody.make({
		"title": "Aegis Frigate", "tag": "TIER 2 // NAVAL",
		"stats": [{"label": "Cost", "value": "1,200"}, {"label": "Time", "value": "0:45", "delta": "-10%", "tone": "ok"}, {"label": "Power", "value": "-30", "delta": "+5", "tone": "danger"}, {"label": "Hotkey", "value": "F"}],
		"text": "Escort vessel with a rapid-fire flak battery. Excellent against aircraft and missiles, weak against submarines.",
		"warn": "Requires Naval Yard", "hint": "LMB build  /  RMB hold  /  Shift x5"})
	frame.add_child(tip)
	v.add_child(frame)
	return _done(v)


func _dialog_sample() -> Control:
	var d := UiDialog.new("Leave match?")
	d.add_text("The match is still running for the other players. Leaving now counts as a surrender and the AI takes over your base.")
	d.add_button("Stay", 0)
	d.add_button("Surrender", 1, &"danger")
	return d


func _select_panel() -> Control:
	var v: VBoxContainer = _panel("Drag select", "UiSelectRect + world overlay")
	var bm := BattleMock.new()
	bm.custom_minimum_size = Vector2(0.0, 150.0)
	v.add_child(bm)
	var sr := UiSelectRect.new()
	sr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bm.add_child(sr)
	sr.show_rect(Rect2(Vector2(40.0, 26.0), Vector2(150.0, 90.0)))
	return _done(v)


# ------------------------------------------------------------------------------------------------- column D (HUD mock)

func _hud_mock() -> Control:
	var side := PanelContainer.new()
	side.theme_type_variation = &"SidebarPanel"
	side.custom_minimum_size = Vector2(float(UiMetrics.SIDEBAR_W), 0.0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	side.add_child(v)
	v.add_child(UiPanelHeader.new(UiSkinSet.shared().skin_for(_faction).code + " // command", "sidebar"))
	var mm := BattleMock.new()
	mm.custom_minimum_size = Vector2(0.0, 180.0)
	v.add_child(mm)
	var eco := HBoxContainer.new()
	eco.add_theme_constant_override("separation", 8)
	eco.add_child(_label("12,450", &"CreditsLabel"))
	eco.add_child(UiProgressChip.new("Power", "265/300", 0.88, &"power"))
	eco.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(eco)
	var tb := UiTabBar.new()
	tb.stretch = true
	var tabs: Array[Dictionary] = []
	for g: int in [UiDraw.G_PLUS, UiDraw.G_INFO, UiDraw.G_WARNING, UiDraw.G_CHECK, UiDraw.G_MINUS, UiDraw.G_CLOSE, UiDraw.G_CHEVRON_UP, UiDraw.G_CHEVRON_DOWN]:
		tabs.append({"id": StringName("t%d" % g), "glyph": g})
	tb.set_tabs(tabs)
	tb.select(0)
	v.add_child(tb)
	var grid := GridContainer.new()
	grid.columns = UiMetrics.GRID_COLS
	grid.add_theme_constant_override("h_separation", UiMetrics.GRID_GAP)
	grid.add_theme_constant_override("v_separation", UiMetrics.GRID_GAP)
	var names: Array[String] = ["Power Node", "Refinery", "Barracks", "War Factory", "Radar Uplink", "Airpad"]
	for i in names.size():
		grid.add_child(CardMock.new(names[i], 300 + i * 150, i))
	v.add_child(grid)
	var pri := Button.new()
	pri.theme_type_variation = &"PrimaryButton"
	pri.text = "PLACE STRUCTURE"
	pri.custom_minimum_size = Vector2(0.0, 40.0)
	v.add_child(pri)
	var rib := PanelContainer.new()
	rib.theme_type_variation = &"RibbonPanel"
	var rl := _label("BASE UNDER ATTACK   Sector 4", &"WarnLabel")
	rib.add_child(rl)
	v.add_child(rib)
	return side


# ------------------------------------------------------------------------------------------------- helper controls

## Faux battlefield backdrop: dusk gradient, faint grid, a few dark blobs (so translucent panels read as in game).
class Backdrop extends Control:
	func _draw() -> void:
		var h: float = size.y
		var steps: int = 48
		for i in steps:
			var t: float = float(i) / float(steps - 1)
			var c: Color = Color("#2a3444").lerp(Color("#0b0f15"), t)
			draw_rect(Rect2(0.0, h * float(i) / float(steps), size.x, h / float(steps) + 1.0), c)
		var gc := Color(1.0, 1.0, 1.0, 0.035)
		var x: float = 0.0
		while x < size.x:
			draw_line(Vector2(x, 0.0), Vector2(x, h), gc, 1.0)
			x += 64.0
		var y: float = 0.0
		while y < h:
			draw_line(Vector2(0.0, y), Vector2(size.x, y), gc, 1.0)
			y += 64.0
		for k in 7:
			var p := Vector2(size.x * (0.1 + 0.14 * float(k)), h * (0.25 + 0.5 * fmod(float(k) * 0.37, 1.0)))
			draw_circle(p, 140.0 + 30.0 * float(k % 3), Color(0.9, 0.55, 0.25, 0.035))


class Swatch extends Control:
	var col: Color
	var cap: String

	func _init(c: Color, caption: String) -> void:
		col = c
		cap = caption
		custom_minimum_size = Vector2(54.0, 50.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0.0, 0.0, size.x, 30.0), col)
		draw_rect(Rect2(0.0, 0.0, size.x, 30.0), UiPalette.LINE_BRIGHT, false, 1.0)
		var f: Font = UiFonts.get_font(UiFonts.Role.BODY)
		draw_string(f, Vector2(0.0, 45.0), UiDraw.ellipsize(f, cap, 14, size.x), HORIZONTAL_ALIGNMENT_LEFT, size.x, 14, UiPalette.TEXT_DIM)


class SkinChip extends Control:
	var label_text: String
	var skin: UiSkin

	func _init(text: String, s: UiSkin) -> void:
		label_text = text
		skin = s
		custom_minimum_size = Vector2(70.0, 54.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, skin.tint)
		draw_rect(r, UiPalette.LINE, false, 1.0)
		draw_rect(Rect2(0.0, 0.0, size.x, 6.0), skin.accent)
		draw_rect(Rect2(size.x - 22.0, 12.0, 14.0, 14.0), skin.accent2)
		draw_string(UiFonts.get_font(UiFonts.Role.HEAD), Vector2(8.0, 40.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 10.0, 14, skin.accent)


class TeamRow extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 40.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n: int = UiSkinSet.shared().team_color_count()
		var w: float = size.x / float(n)
		var f: Font = UiFonts.get_font(UiFonts.Role.NUM)
		for i in n:
			var c: Color = UiPalette.team(i)
			var cx: float = w * (float(i) + 0.5)
			draw_rect(Rect2(w * float(i) + 2.0, 0.0, w - 4.0, 20.0), c)
			UiA11y.draw_pip(self, i, Vector2(cx, 10.0), 5.0, UiPalette.BG_DEEP)
			draw_string(f, Vector2(w * float(i), 38.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, w, 14, UiPalette.TEXT_DIM)


## A button state drawn statically (hover / pressed cannot be forced on a real Button).
class StateBox extends Control:
	var variation: StringName
	var state: StringName
	var caption: String

	func _init(v: StringName, st: StringName, text: String) -> void:
		variation = v
		state = st
		caption = text
		custom_minimum_size = Vector2(0.0, 40.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(get_theme_stylebox(state, variation), r)
		var col: Color = get_theme_color(&"font_color" if state == &"normal" else StringName("font_%s_color" % state), variation)
		var f: Font = get_theme_font(&"font", variation)
		var w: float = f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + 5.5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


class BattleMock extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(get_theme_stylebox(&"panel", &"InsetPanel"), r)
		var inner: Rect2 = r.grow(-4.0)
		draw_rect(inner, Color("#1a2419"))
		for i in 30:
			var p := Vector2(inner.position.x + fmod(float(i) * 37.3, inner.size.x), inner.position.y + fmod(float(i) * 23.9, inner.size.y))
			draw_circle(p, 9.0 + fmod(float(i) * 3.1, 14.0), Color("#26331f") if i % 2 == 0 else Color("#151d15"))
		for i in 9:
			var c: Color = UiPalette.team(1) if i < 5 else UiPalette.team(0)
			draw_rect(Rect2(inner.position + Vector2(20.0 + float(i) * 17.0, 30.0 + float(i % 3) * 22.0), Vector2(5.0, 5.0)), c)
		draw_rect(Rect2(inner.position + Vector2(50.0, 40.0), Vector2(70.0, 44.0)), Color("#e6eef6", 0.9), false, 1.5)


class CardMock extends Control:
	var title: String
	var cost: int
	var idx: int

	func _init(t: String, c: int, i: int) -> void:
		title = t
		cost = c
		idx = i
		custom_minimum_size = UiMetrics.CARD
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var st: StringName = &"hover" if idx == 1 else (&"disabled" if idx == 5 else &"normal")
		draw_style_box(get_theme_stylebox(st, &"CommandButton"), Rect2(Vector2.ZERO, size))
		var icon := Rect2(6.0, 6.0, size.x - 12.0, float(UiMetrics.CARD_ICON_H))
		draw_rect(icon, Color("#0b1016"))
		draw_colored_polygon(PackedVector2Array([icon.position + Vector2(10.0, 46.0), icon.position + Vector2(icon.size.x * 0.5, 8.0), icon.end - Vector2(10.0, 16.0)]), acc.darkened(0.35 if idx != 5 else 0.7))
		var f: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
		var txt: String = UiDraw.ellipsize(f, title, 14, size.x - 8.0)
		draw_string(f, Vector2(4.0, 88.0), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, 14, UiPalette.TEXT if idx != 5 else UiPalette.TEXT_DISABLED)
		var num: Font = UiFonts.get_font(UiFonts.Role.NUM)
		draw_string(num, Vector2(4.0, 101.0), "%d" % cost, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, 14, UiPalette.CREDITS if idx != 5 else UiPalette.TEXT_DISABLED)
		if idx == 2:
			draw_rect(Rect2(0.0, 0.0, size.x, 3.0), UiPalette.OK)
