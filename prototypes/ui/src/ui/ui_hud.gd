class_name UiHud
extends Control
## The in-game HUD, assembled from widgets. Full-rect, mouse_filter IGNORE (clicks on empty HUD space must reach
## the input controller). Data in through setters/`items`, actions out through signals.
##   right sidebar   header, minimap, tools, credits+power, tabs, scrolling build grid, footer
##   bottom-centre   control groups + selection panel (portrait, tiles, command bar)
##   top-centre      alert / superweapon ribbons     top-left  mission strip     bottom-left  message log

signal build_requested(item: UiBuildItem)
signal build_cancel_requested(item: UiBuildItem)
signal command(id: StringName)
signal camera_requested(norm: Vector2)

const SIDEBAR_W := 348.0
const MINIMAP_SIZE := 300.0

var skin: UiSkin
var items: Dictionary = {}
var sweep_backend: UiCooldownSweep.Backend = UiCooldownSweep.Backend.SHADER
var current_tab: String = "vehicles"

var sidebar: PanelContainer
var minimap: UiMinimap
var credits: UiCreditTicker
var power: UiPowerBar
var tab_buttons: Dictionary = {}
var grid: GridContainer
var scroll: ScrollContainer
var tab_title: Label
var tab_info: Label
var selection: UiSelectionPanel
var groups: UiGroupBar
var ribbon_box: VBoxContainer
var overlay: UiWorldOverlay
var select_rect: UiSelectRect
var play_area: Control
var cards: Array[UiBuildCard] = []
var faction_code: String = "napc"
var subfaction_label: String = ""
var queue: UiQueueStrip
var footer: Label
var _log_box: VBoxContainer

func setup(s: UiSkin, faction: String, roster_index: int) -> void:
	skin = s
	faction_code = faction
	var roster: Dictionary = DemoData.roster(faction, roster_index)
	subfaction_label = "%s  //  %s" % [String(roster["name"]).to_upper(), String(roster["title"]).to_upper()]
	items = DemoData.build_items(faction, roster_index)
	DemoData.apply_demo_states(items)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = UiWorldOverlay.new()
	overlay.skin = skin
	add_child(overlay)
	select_rect = UiSelectRect.new()
	add_child(select_rect)
	play_area = Control.new()
	play_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_area.offset_right = -SIDEBAR_W
	play_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(play_area)
	_build_sidebar()
	_build_bottom()
	_build_top()
	_build_log()
	select_tab(current_tab)
	_apply_size_class.call_deferred()
	_on_play_area_resized.call_deferred()

# --- sidebar ------------------------------------------------------------------------------------------------

func _build_sidebar() -> void:
	sidebar = PanelContainer.new()
	sidebar.theme_type_variation = &"SidebarPanel"
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	sidebar.offset_left = -SIDEBAR_W
	sidebar.offset_right = 0.0
	add_child(sidebar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sidebar.add_child(v)
	v.add_child(_header())
	minimap = UiMinimap.new()
	minimap.skin = skin
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	minimap.camera_requested.connect(func(n: Vector2) -> void: camera_requested.emit(n))
	v.add_child(minimap)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 5)
	for spec in [[UiGlyphs.Glyph.REPAIR, &"repair", "Repair mode"], [UiGlyphs.Glyph.SELL, &"sell", "Sell mode"], [UiGlyphs.Glyph.WAYPOINT, &"rally", "Set rally point"], [UiGlyphs.Glyph.RADAR, &"radar", "Toggle radar sweep"], [UiGlyphs.Glyph.GEAR, &"options", "Options"]]:
		var b := UiIconButton.new()
		b.glyph = spec[0]
		b.accent = skin.accent
		b.toggle_mode = spec[1] in [&"repair", &"sell", &"rally"]
		b.tooltip_text = spec[2]
		b.custom_minimum_size = Vector2(0.0, 32.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: StringName = spec[1]
		b.pressed.connect(func() -> void: command.emit(id))
		tools.add_child(b)
	v.add_child(tools)
	var eco := PanelContainer.new()
	eco.theme_type_variation = &"InsetPanel"
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 4)
	eco.add_child(ev)
	credits = UiCreditTicker.new()
	ev.add_child(credits)
	power = UiPowerBar.new()
	ev.add_child(power)
	v.add_child(eco)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	for t in DemoData.TABS:
		var tb := UiIconButton.new()
		tb.glyph = DemoData.TAB_GLYPHS[t]
		tb.accent = skin.accent
		tb.custom_minimum_size = Vector2(42.0, 42.0)
		tb.tooltip_text = String(DemoData.TAB_TITLES[t]).capitalize()
		tb.hotkey = str(DemoData.TABS.find(t) + 1)
		var name: String = t
		tb.pressed.connect(func() -> void: select_tab(name))
		tabs.add_child(tb)
		tab_buttons[t] = tb
	v.add_child(tabs)
	var title_row := HBoxContainer.new()
	tab_title = Label.new()
	tab_title.theme_type_variation = &"HeaderLabel"
	title_row.add_child(tab_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(sp)
	tab_info = Label.new()
	tab_info.theme_type_variation = &"DimLabel"
	title_row.add_child(tab_info)
	v.add_child(title_row)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	v.add_child(scroll)
	queue = UiQueueStrip.new()
	queue.skin = skin
	queue.title = "FACTORY 2  //  QUEUE"
	v.add_child(queue)
	var foot := Label.new()
	foot.theme_type_variation = &"DimLabel"
	foot.text = "UNIT CAP 87 / 150     BUILD RADIUS 8"
	foot.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	foot.add_theme_font_size_override("font_size", 12)
	footer = foot
	v.add_child(foot)

func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var em := UiEmblemView.new(38.0)
	em.code = faction_code
	em.color = skin.accent
	h.add_child(em)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var n := Label.new()
	n.theme_type_variation = &"HeaderLabel"
	n.text = skin.display_name.to_upper()
	n.add_theme_font_size_override("font_size", 11)
	n.clip_text = true
	n.custom_minimum_size = Vector2(250.0, 0.0)
	col.add_child(n)
	var sub := Label.new()
	sub.theme_type_variation = &"DimLabel"
	sub.text = subfaction_label
	sub.clip_text = true
	sub.custom_minimum_size = Vector2(250.0, 0.0)
	col.add_child(sub)
	h.add_child(col)
	return h

func select_tab(t: String) -> void:
	current_tab = t
	for k in tab_buttons:
		(tab_buttons[k] as UiIconButton).active = (k == t)
	tab_title.text = DemoData.TAB_TITLES[t]
	var list: Array = items[t]
	var ready: int = 0
	for it in list:
		if (it as UiBuildItem).state == UiBuildItem.State.READY:
			ready += 1
	tab_info.text = "%d ITEMS   //   %d READY" % [list.size(), ready]
	for c in grid.get_children():
		c.queue_free()
	cards.clear()
	for it in list:
		var card := UiBuildCard.new().setup(it, skin, sweep_backend)
		card.pressed.connect(func(i: UiBuildItem) -> void: build_requested.emit(i))
		card.right_pressed.connect(func(i: UiBuildItem) -> void: build_cancel_requested.emit(i))
		grid.add_child(card)
		cards.append(card)
	var filler: int = maxi(12, int(ceilf(float(list.size()) / 3.0)) * 3) - list.size()
	for f in filler:
		grid.add_child(UiEmptySlot.new())
	scroll.scroll_vertical = 0
	for k2 in tab_buttons:
		var lst: Array = items[k2]
		var n: int = 0
		for it2 in lst:
			if (it2 as UiBuildItem).state == UiBuildItem.State.READY:
				n += 1
		(tab_buttons[k2] as UiIconButton).badge = str(n) if n > 0 else ""

# --- bottom + top -------------------------------------------------------------------------------------------

func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	play_area.add_child(box)
	groups = UiGroupBar.new()
	groups.skin = skin
	groups.groups = [{"count": 12, "glyph": UiGlyphs.Glyph.VEHICLES}, {"count": 6, "glyph": UiGlyphs.Glyph.INFANTRY}, {"count": 3, "glyph": UiGlyphs.Glyph.AIRCRAFT}, {}, {"count": 2, "glyph": UiGlyphs.Glyph.NAVAL}, {"count": 1, "glyph": UiGlyphs.Glyph.STRUCTURES}, {}, {}, {}, {"count": 4, "glyph": UiGlyphs.Glyph.DEFENSE}]
	groups.active = 0
	groups.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(groups)
	selection = UiSelectionPanel.new().setup(skin)
	selection.custom_minimum_size = Vector2(880.0, 160.0)
	play_area.resized.connect(_on_play_area_resized)
	resized.connect(_apply_size_class)
	box.add_child(selection)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -10.0
	selection.command.connect(func(id: StringName) -> void: command.emit(id))

## Responsive rules (logical px): the selection panel shrinks with the playfield, the minimap shrinks and the
## queue strip / footer disappear on short screens so the sidebar never overflows (UI scale 150% at 1080p
## means a 1280x720 logical canvas).
func _on_play_area_resized() -> void:
	selection.custom_minimum_size.x = clampf(play_area.size.x - 40.0, 600.0, 900.0)

func _apply_size_class() -> void:
	var m: float = clampf((size.y - 420.0) * 0.55, 180.0, MINIMAP_SIZE)
	minimap.custom_minimum_size = Vector2(m, m)
	var tall: bool = size.y >= 800.0
	queue.visible = tall
	footer.visible = tall

func _build_top() -> void:
	ribbon_box = VBoxContainer.new()
	ribbon_box.add_theme_constant_override("separation", 6)
	play_area.add_child(ribbon_box)
	ribbon_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	ribbon_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ribbon_box.offset_top = 12.0
	var strip := PanelContainer.new()
	strip.theme_type_variation = &"InsetPanel"
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	for txt in ["12:41", "37 KILLS", "9 LOST"]:
		var l := Label.new()
		l.theme_type_variation = &"NumLabel"
		l.add_theme_font_size_override("font_size", 13)
		l.text = txt
		l.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		hb.add_child(l)
	strip.add_child(hb)
	strip.position = Vector2(12.0, 12.0)
	play_area.add_child(strip)

func add_ribbon(sev: UiRibbon.Severity, title: String, sub: String, glyph: UiGlyphs.Glyph, countdown: float = -1.0, charge: float = -1.0, tag: String = "") -> UiRibbon:
	var r := UiRibbon.new()
	r.skin = skin
	r.severity = sev
	r.title = title
	r.subtitle = sub
	r.glyph = glyph
	r.countdown = countdown
	r.charge = charge
	r.tag = tag
	ribbon_box.add_child(r)
	return r

func _build_log() -> void:
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 2)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_area.add_child(_log_box)
	_log_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_log_box.offset_left = 14.0
	_log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_box.offset_bottom = -232.0

func log_line(text: String, col: Color = UiPalette.TEXT_DIM) -> void:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	_log_box.add_child(l)

## Demo animation: fast-forwards production and cooldown so the HUD shows motion in real-time runs.
func animate(delta: float, speed: float = 7.0) -> void:
	for c in cards:
		var it: UiBuildItem = c.item
		if it.state == UiBuildItem.State.BUILDING or it.state == UiBuildItem.State.COOLDOWN:
			var p: float = it.progress + delta * speed / maxf(it.build_seconds, 1.0)
			if p >= 1.0:
				p = 0.0 if it.state == UiBuildItem.State.COOLDOWN else 1.0
				if it.state == UiBuildItem.State.BUILDING:
					it.state = UiBuildItem.State.READY
					c.refresh()
			c.set_progress(p)
