class_name UiSidebar
extends PanelContainer
## Right sidebar (ui.md 2.6, 5.10): faction header, minimap with the camera pad, tool row, credits + power panel, the 8
## tabs, the scrolling 3-column card grid (min 12 slots, ghost slots), the queue strip and the footer. Data in through
## `set_items` / `refresh_item` / `set_footer`; actions out through signals. Never reads the sim.

signal card_pressed(item: UiBuildItem, shift: bool)
signal card_right_pressed(item: UiBuildItem)
signal tab_changed(tab: int)
signal tool_pressed(id: StringName)
signal camera_requested(norm: Vector2)
signal camera_snap(norm: Vector2)
signal minimap_order(norm: Vector2, mods: int)
signal pad_pressed(id: StringName)
signal queue_slot_pressed(index: int)
signal queue_slot_right_pressed(index: int)
signal queue_hold_toggled()
signal queue_primary_pressed()
signal producer_cycled(direction: int)

const TOOLS: Array[Dictionary] = [
	{"id": &"repair", "glyph": UiGlyphs.Glyph.REPAIR, "title": "Repair", "text": "Click a structure to toggle repair. Hotkey R."},
	{"id": &"sell", "glyph": UiGlyphs.Glyph.SELL, "title": "Sell", "text": "Click a structure to sell it for a refund. Hotkey Delete."},
	{"id": &"rally", "glyph": UiGlyphs.Glyph.RALLY, "title": "Rally point", "text": "Click the ground to set the rally point of the selected producers."},
	{"id": &"waypoint", "glyph": UiGlyphs.Glyph.WAYPOINT, "title": "Waypoint mode", "text": "Queue every following order (W). Esc clears it."},
	{"id": &"menu", "glyph": UiGlyphs.Glyph.GEAR, "title": "Menu", "text": "Game menu (Esc)."},
]

var _header: _Header = null
var _minimap: UiMinimap = null
var _pad: UiCameraPad = null
var _tools: Dictionary = {}
var _tools_row: HBoxContainer = null
var _credits: UiCreditTicker = null
var _power: UiPowerBar = null
var _eco: PanelContainer = null
var _tabs: UiTabBar = null
var _title: Label = null
var _info: Label = null
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _queue: UiQueueStrip = null
var _footer: Label = null
var _cards: Dictionary = {}  ## UiBuildItem -> UiBuildCard
var _tab: int = 0
var _pulse_tab: int = -1
var _vbox: VBoxContainer = null
var _observer: Control = null


## Faction header: emblem plate + two text lines.
class _Header extends Control:
	var title: String = ""
	var subtitle: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, 42.0)

	func _draw() -> void:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var plate := Rect2(0.0, 2.0, 38.0, 38.0)
		draw_colored_polygon(UiDraw.chamfer_points(plate, Vector4(8.0, 0.0, 8.0, 0.0)), Color(acc, 0.16))
		var outline: PackedVector2Array = UiDraw.chamfer_points(plate.grow(-0.5), Vector4(8.0, 0.0, 8.0, 0.0))
		outline.append(outline[0])
		draw_polyline(outline, Color(acc, 0.9), 1.5, true)
		UiGlyphs.draw(self, UiGlyphs.Glyph.COMMAND, plate.grow(-8.0), acc.lightened(0.2), 1.6)
		var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
		var txt: String = title.to_upper()
		var fs: int = 13
		var room: float = size.x - 52.0
		while fs > 11 and head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		if head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			# a very long faction name ("Order of the Levant and Mediterranean"): the condensed body face keeps it whole
			head = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
			fs = 16
			while fs > 11 and head.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
				fs -= 1
		draw_string(head, Vector2(50.0, 17.0), txt, HORIZONTAL_ALIGNMENT_LEFT, room, fs, acc.lightened(0.15))
		draw_string(UiFonts.get_font(UiFonts.Role.BODY), Vector2(50.0, 35.0), subtitle.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 52.0, 14, UiPalette.TEXT_DIM)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
			queue_redraw()


## Dashed empty grid slot (the tree teaches itself, free slots keep the grid steady).
class _GhostSlot extends Control:
	func _init() -> void:
		custom_minimum_size = UiBuildCard.CARD_SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size).grow(-1.0)
		draw_rect(r, Color(UiPalette.BG_DEEP, 0.55))
		draw_rect(r, Color(UiPalette.LINE_DIM, 0.9), false, 1.0)
		var c: Vector2 = r.get_center()
		draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), Color(UiPalette.LINE, 0.7), 1.0)
		draw_line(c + Vector2(0, -5), c + Vector2(0, 5), Color(UiPalette.LINE, 0.7), 1.0)


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	custom_minimum_size = Vector2(float(UiMetrics.SIDEBAR_W), 0.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_vbox = v
	_header = _Header.new()
	v.add_child(_header)
	_minimap = UiMinimap.new()
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_minimap.custom_minimum_size = Vector2(float(UiMetrics.MINIMAP_MAX), float(UiMetrics.MINIMAP_MAX))
	_minimap.camera_requested.connect(func(n: Vector2) -> void: camera_requested.emit(n))
	_minimap.camera_snap.connect(func(n: Vector2) -> void: camera_snap.emit(n))
	_minimap.order_requested.connect(func(n: Vector2, m: int) -> void: minimap_order.emit(n, m))
	v.add_child(_minimap)
	_pad = UiCameraPad.new()
	_pad.pad_pressed.connect(func(id: StringName) -> void: pad_pressed.emit(id))
	v.add_child(_pad)
	_tools_row = HBoxContainer.new()
	_tools_row.add_theme_constant_override("separation", 5)
	for t: Dictionary in TOOLS:
		var b := UiIconButton.new()
		b.glyph = int(t["glyph"])
		b.custom_minimum_size = Vector2(0.0, float(UiMetrics.TOOL_H))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_tip({"title": String(t["title"]), "text": String(t["text"])})
		var id: StringName = t["id"]
		b.pressed.connect(func() -> void: tool_pressed.emit(id))
		_tools_row.add_child(b)
		_tools[id] = b
	v.add_child(_tools_row)
	_eco = PanelContainer.new()
	_eco.theme_type_variation = &"InsetPanel"
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 4)
	_eco.add_child(ev)
	_credits = UiCreditTicker.new()
	ev.add_child(_credits)
	_power = UiPowerBar.new()
	ev.add_child(_power)
	v.add_child(_eco)
	_tabs = UiTabBar.new()
	_tabs.stretch = true
	var tab_defs: Array[Dictionary] = []
	for i: int in UiBuildModel.TAB_COUNT:
		tab_defs.append({"id": UiBuildModel.TAB_IDS[i], "text": "", "glyph": UiBuildModel.TAB_GLYPHS[i], "badge": "", "tip": UiBuildModel.TAB_TITLES[i].capitalize() + "  [" + str(i + 1) + "]", "enabled": true})
	_tabs.set_tabs(tab_defs)
	_tabs.tab_selected.connect(func(idx: int, _id: StringName) -> void: _on_tab(idx))
	v.add_child(_tabs)
	var title_row := HBoxContainer.new()
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	title_row.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(sp)
	_info = Label.new()
	_info.theme_type_variation = &"DimLabel"
	title_row.add_child(_info)
	v.add_child(title_row)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	_grid = GridContainer.new()
	_grid.columns = UiMetrics.GRID_COLS
	_grid.add_theme_constant_override("h_separation", UiMetrics.GRID_GAP)
	_grid.add_theme_constant_override("v_separation", UiMetrics.GRID_GAP)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	v.add_child(_scroll)
	_queue = UiQueueStrip.new()
	_queue.slot_pressed.connect(func(i: int) -> void: queue_slot_pressed.emit(i))
	_queue.slot_right_pressed.connect(func(i: int) -> void: queue_slot_right_pressed.emit(i))
	_queue.hold_toggled.connect(func() -> void: queue_hold_toggled.emit())
	_queue.primary_pressed.connect(func() -> void: queue_primary_pressed.emit())
	_queue.cycled.connect(func(d: int) -> void: producer_cycled.emit(d))
	v.add_child(_queue)
	_footer = Label.new()
	_footer.theme_type_variation = &"CaptionLabel"
	_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_footer)
	_tabs.select(0)


# ---- accessors --------------------------------------------------------------------------------------------------------
func minimap() -> UiMinimap:
	return _minimap


func credits() -> UiCreditTicker:
	return _credits


func power_bar() -> UiPowerBar:
	return _power


func tabs() -> UiTabBar:
	return _tabs


func queue() -> UiQueueStrip:
	return _queue


func camera_pad() -> UiCameraPad:
	return _pad


func active_tab() -> int:
	return _tab


func card_for(item: UiBuildItem) -> UiBuildCard:
	return _cards.get(item) as UiBuildCard


func card_count() -> int:
	return _cards.size()


func grid_slot_count() -> int:
	return _grid.get_child_count()


func tool_button(id: StringName) -> UiIconButton:
	return _tools.get(id) as UiIconButton


## Tool row toggle highlight (armed repair / sell / rally / waypoint latch).
func set_tool_armed(id: StringName, armed: bool) -> void:
	var b: UiIconButton = tool_button(id)
	if b != null:
		b.active = armed


func set_header(title: String, subtitle: String) -> void:
	_header.title = title
	_header.subtitle = subtitle
	_header.queue_redraw()


func set_footer(text: String) -> void:
	_footer.text = text


func set_tab_badge(tab: int, text: String) -> void:
	if tab >= 0 and tab < UiBuildModel.TAB_COUNT:
		_tabs.set_badge(UiBuildModel.TAB_IDS[tab], text)


## Pulses the tab holding a missing prerequisite for 1.5 s (locked card clicked).
func pulse_tab(tab: int) -> void:
	_pulse_tab = tab
	_tabs.modulate = Color.WHITE
	var tw: Tween = create_tween()
	for i: int in 3:
		tw.tween_callback(func() -> void: set_tab_badge(tab, "!"))
		tw.tween_interval(0.25)
		tw.tween_callback(func() -> void: set_tab_badge(tab, ""))
		tw.tween_interval(0.25)


## Layout per size class: minimap size from the logical height, queue strip / footer hidden in COMPACT.
func set_size_class(klass: int, logical_h: float) -> void:
	var m: float = UiLayout.minimap_size(logical_h)
	_minimap.custom_minimum_size = Vector2(m, m)
	var compact: bool = klass == UiLayout.SizeClass.COMPACT
	_queue.visible = not compact and _observer == null
	_footer.visible = not compact and _observer == null


## Observer HUD (task REP2): the build area (tool row, tabs, card grid, queue strip, footer) gives way to `content` (the
## `UiObserverBar`). The minimap, the camera pad and the credits / power panel stay.
func enter_observer(content: Control) -> void:
	_observer = content
	_tools_row.visible = false
	_tabs.visible = false
	_title.get_parent().visible = false
	_scroll.visible = false
	_queue.visible = false
	_footer.visible = false
	_vbox.add_child(content)


func observer_content() -> Control:
	return _observer


## The credits / power panel of the viewed player (hidden while an observer watches everyone).
func set_economy_visible(on: bool) -> void:
	_eco.visible = on


# ---- tabs and cards ---------------------------------------------------------------------------------------------------
func select_tab(tab: int, emit: bool = false) -> void:
	_tabs.select(tab, emit)
	_tab = clampi(tab, 0, UiBuildModel.TAB_COUNT - 1)
	_title.text = UiBuildModel.TAB_TITLES[_tab]


## Tab / Shift+Tab: the next or previous enabled tab (wraps); the same signals as a click.
func cycle_tab(direction: int) -> bool:
	return _tabs.step(direction, true)


func _on_tab(idx: int) -> void:
	_tab = idx
	_title.text = UiBuildModel.TAB_TITLES[idx]
	tab_changed.emit(idx)


## Rebuilds the card grid for the active tab (min 12 slots, ghost slots fill up). `tip_of` builds a card's tooltip spec.
func set_items(list: Array[UiBuildItem], tip_of: Callable = Callable()) -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	var ready_n: int = 0
	for it: UiBuildItem in list:
		var card := UiBuildCard.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.setup(it)
		card.pressed.connect(func(i: UiBuildItem, s: bool) -> void: card_pressed.emit(i, s))
		card.right_pressed.connect(func(i: UiBuildItem) -> void: card_right_pressed.emit(i))
		if tip_of.is_valid():
			card.tooltip_text = UiTooltipBody.encode(tip_of.call(it))
		_grid.add_child(card)
		_cards[it] = card
		if it.state == UiBuildItem.State.READY or it.state == UiBuildItem.State.PLACING:
			ready_n += 1
	var slots: int = maxi(UiMetrics.GRID_SLOTS, int(ceili(float(list.size()) / float(UiMetrics.GRID_COLS))) * UiMetrics.GRID_COLS)
	for i2: int in slots - list.size():
		_grid.add_child(_GhostSlot.new())
	_scroll.scroll_vertical = 0
	_info.text = "%d ITEMS   //   %d READY" % [list.size(), ready_n]


## Updates one card after its view-model changed (and its tooltip when the requirement text changed).
func refresh_item(it: UiBuildItem, tip_of: Callable = Callable()) -> void:
	var card: UiBuildCard = card_for(it)
	if card == null:
		return
	card.refresh()
	if tip_of.is_valid():
		card.tooltip_text = UiTooltipBody.encode(tip_of.call(it))


## "N ITEMS // M READY" line of the current tab.
func set_tab_info(items_n: int, ready_n: int) -> void:
	_info.text = "%d ITEMS   //   %d READY" % [items_n, ready_n]
