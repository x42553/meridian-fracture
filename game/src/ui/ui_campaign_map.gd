class_name UiCampaignMap
extends Control
## The campaign map (MIS2): a stylised theatre map (graticule, range rings) with one card per mission at its position from
## `UiCampaignModel` (the tutorial hub in the middle, the operations on a ring, other groups along the lower edge) and the supply
## lines between them. A card shows the faction emblem, the mission title and its state (locked, ready, completed with the best
## time and difficulty). Click selects, double click / Enter opens the briefing, arrows move the selection between cards
## (Godot's focus navigation). Presentation only.

signal mission_selected(id: String)
signal mission_activated(id: String)

const CARD := Vector2(196.0, 112.0)
const PAD: float = 28.0

var model: UiCampaignModel = null
var selected_id: String = ""

var _cards: Dictionary = {}  ## mission id -> _Card
var _recommended: String = ""
var _t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)


func setup(m: UiCampaignModel) -> void:
	model = m
	for c: Node in get_children():
		c.queue_free()
	_cards.clear()
	for e: UiCampaignModel.Entry in m.entries:
		var card: _Card = _Card.new()
		card.entry = e
		card.map = self
		card.pressed.connect(func(id: String, double: bool) -> void:
			select(id)
			if double:
				mission_activated.emit(id))
		card.activated.connect(func(id: String) -> void: mission_activated.emit(id))
		add_child(card)
		_cards[e.id] = card
	refresh()
	_layout()
	resized.connect(_layout)
	set_process(true)


## After the campaign changed (a result was recorded): states and the recommended mission again.
func refresh() -> void:
	if model == null:
		return
	_recommended = model.recommended()
	for id: Variant in _cards:
		(_cards[id] as _Card).queue_redraw()
	queue_redraw()


func select(id: String) -> void:
	if not _cards.has(id) or id == selected_id:
		return
	selected_id = id
	for k: Variant in _cards:
		(_cards[k] as _Card).queue_redraw()
	queue_redraw()
	mission_selected.emit(id)


func card_for(id: String) -> Control:
	return _cards.get(id) as Control


func card_count() -> int:
	return _cards.size()


## The card to take keyboard focus first: the selected one.
func focus_card() -> Control:
	return card_for(selected_id) if selected_id != "" else (card_for(_recommended) if _recommended != "" else null)


func recommended_id() -> String:
	return _recommended


func _layout() -> void:
	if model == null:
		return
	var area: Rect2 = Rect2(Vector2(PAD, PAD + 22.0), size - Vector2(PAD * 2.0, PAD * 2.0 + 22.0))
	for e: UiCampaignModel.Entry in model.entries:
		var card: _Card = _cards[e.id] as _Card
		card.size = CARD
		var centre: Vector2 = area.position + Vector2(e.pos.x * area.size.x, e.pos.y * area.size.y)
		card.position = (centre - CARD * 0.5).round()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _recommended != "" and _cards.has(_recommended):
		(_cards[_recommended] as _Card).queue_redraw()


func _draw() -> void:
	var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(UiPalette.BG_PANEL, 0.78))
	# graticule
	var step: float = 64.0
	var x: float = fposmod(size.x * 0.5, step)
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(UiPalette.LINE_DIM, 0.55), 1.0)
		x += step
	var y: float = fposmod(size.y * UiCampaignModel.HUB_Y, step)
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(UiPalette.LINE_DIM, 0.55), 1.0)
		y += step
	var area: Rect2 = Rect2(Vector2(PAD, PAD + 22.0), size - Vector2(PAD * 2.0, PAD * 2.0 + 22.0))
	var hub: Vector2 = area.position + Vector2(0.5 * area.size.x, UiCampaignModel.HUB_Y * area.size.y)
	# range rings (ellipses: the ring layout is wider than tall)
	for k: int in 3:
		var rad: float = area.size.y * UiCampaignModel.RING_R * (0.45 + 0.55 * float(k) / 2.0)
		draw_set_transform(hub, 0.0, Vector2(1.18, 1.0))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 96, Color(UiPalette.LINE, 0.55 if k == 2 else 0.3), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if model != null:
		_draw_lines(hub)
	var cap: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	draw_string(cap, Vector2(PAD, 30.0), "THEATRE OF OPERATIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, UiMetrics.FS_HEAD, Color(acc, 0.9))
	draw_rect(Rect2(PAD - 14.0, 17.0, 4.0, 15.0), acc)
	draw_rect(r, Color(UiPalette.LINE, 0.8), false, 1.0)


func _draw_lines(hub: Vector2) -> void:
	var hub_card: _Card = null
	for e: UiCampaignModel.Entry in model.entries:
		if e.group == UiCampaignModel.GROUP_TUTORIAL:
			hub_card = _cards[e.id] as _Card
			break
	var from: Vector2 = hub
	if hub_card != null:
		from = hub_card.position + CARD * 0.5
	for e: UiCampaignModel.Entry in model.entries:
		if e.group != UiCampaignModel.GROUP_OPERATION:
			continue
		var to: Vector2 = (_cards[e.id] as _Card).position + CARD * 0.5
		var col: Color = UiPalette.LINE_BRIGHT
		match e.state:
			UiCampaignModel.State.LOCKED:
				draw_dashed_line(from, to, Color(UiPalette.LINE, 0.8), 2.0, 8.0)
			UiCampaignModel.State.COMPLETED:
				draw_line(from, to, Color(UiPalette.semantic(&"ok"), 0.55), 2.0, true)
			_:
				draw_line(from, to, Color(col, 0.75), 2.0, true)


# ---------------------------------------------------------------- card

class _Card extends Control:
	signal pressed(id: String, double: bool)
	signal activated(id: String)

	var entry: UiCampaignModel.Entry = null
	var map: UiCampaignMap = null
	var _badge: UiFactionBadge = null
	var _hover: bool = false

	func _init() -> void:
		custom_minimum_size = UiCampaignMap.CARD
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _ready() -> void:
		_badge = UiFactionBadge.new(entry.faction_code, 56.0)
		_badge.muted = entry.state == UiCampaignModel.State.LOCKED
		_badge.position = Vector2(12.0, 14.0)
		add_child(_badge)
		accessibility_name = "%s, %s" % [entry.title, _state_word()]

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER:
				_hover = true
				queue_redraw()
			NOTIFICATION_MOUSE_EXIT:
				_hover = false
				queue_redraw()
			NOTIFICATION_FOCUS_ENTER:
				map.select(entry.id)
				queue_redraw()
			NOTIFICATION_FOCUS_EXIT, NOTIFICATION_THEME_CHANGED:
				queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(entry.id, mb.double_click)
			accept_event()
		elif event.is_action_pressed(&"ui_accept") and has_focus():
			activated.emit(entry.id)
			accept_event()

	func _state_word() -> String:
		match entry.state:
			UiCampaignModel.State.LOCKED:
				return "LOCKED"
			UiCampaignModel.State.COMPLETED:
				return "COMPLETE"
		return "READY"

	func _accent() -> Color:
		return UiSkinSet.shared().skin_for(entry.faction_code).accent

	func _draw() -> void:
		if _badge != null:
			_badge.muted = entry.state == UiCampaignModel.State.LOCKED
		var acc: Color = _accent()
		var locked: bool = entry.state == UiCampaignModel.State.LOCKED
		var sel: bool = map.selected_id == entry.id
		var rec: bool = map.recommended_id() == entry.id
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var poly: PackedVector2Array = UiDraw.chamfer_points(r.grow(-1.0), Vector4(0.0, 12.0, 0.0, 12.0))
		var fill: Color = Color(UiPalette.BG_RAISED, 0.96)
		if sel:
			fill = fill.lerp(acc, 0.16)
		elif _hover and not locked:
			fill = fill.lerp(acc, 0.08)
		draw_colored_polygon(poly, fill)
		var edge: Color = UiPalette.LINE if locked else Color(acc, 0.85)
		if sel:
			edge = UiPalette.TEXT
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, edge, 2.0 if sel else 1.5, true)
		if rec and not sel and not UiMotion.reduce_flash:
			var pulse: float = 0.35 + 0.35 * sin(float(Time.get_ticks_msec()) / 1000.0 * 3.0)
			draw_polyline(closed, Color(acc, pulse), 3.0, true)
		draw_rect(Rect2(1.0, 1.0, 4.0, size.y - 2.0), Color(acc, 0.35 if locked else 1.0))
		var head: Font = UiFonts.get_font(UiFonts.Role.HEAD)
		var body: Font = UiFonts.get_font(UiFonts.Role.BODY_BOLD)
		var dim: Color = UiPalette.TEXT_DISABLED if locked else UiPalette.TEXT_DIM
		var text_col: Color = UiPalette.TEXT_MUTE if locked else UiPalette.TEXT
		var tx: float = 78.0
		var tw: float = size.x - tx - 12.0
		draw_string(head, Vector2(tx, 28.0), UiCampaignModel.group_label(entry.group, entry.order), HORIZONTAL_ALIGNMENT_LEFT, tw, 12, Color(acc, 0.55 if locked else 1.0))
		var lines: PackedStringArray = _wrap(body, entry.title, 16, tw, 2)
		for i: int in lines.size():
			draw_string(body, Vector2(tx, 48.0 + float(i) * 19.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, tw, 16, text_col)
		# state line
		var base: float = size.y - 12.0
		var sw: String = _state_word()
		if entry.state == UiCampaignModel.State.COMPLETED:
			var ok: Color = UiPalette.semantic(&"ok")
			UiDraw.glyph(self, UiGlyphs.Glyph.CHECK, Rect2(Vector2(12.0, base - 13.0), Vector2(15.0, 15.0)), ok, 2.0)
			var extra: String = sw
			if entry.best_ticks > 0:
				extra = "%s   %s" % [UiFormatLite.clock(entry.best_ticks * SimConfig.TICK_MS / 1000), AppMission.difficulty_name(entry.best_difficulty).to_upper()]
			draw_string(head, Vector2(32.0, base), extra, HORIZONTAL_ALIGNMENT_LEFT, size.x - 40.0, 12, ok)
		elif locked:
			UiDraw.glyph(self, UiGlyphs.Glyph.LOCK, Rect2(Vector2(12.0, base - 13.0), Vector2(15.0, 15.0)), dim, 1.8)
			draw_string(head, Vector2(32.0, base), sw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
		else:
			draw_string(head, Vector2(14.0, base), "START HERE" if rec else sw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, acc)
		if has_focus():
			draw_style_box(get_theme_stylebox(&"focus", &"Button"), r)

	## Word wrap of `text` into at most `max_lines` lines of width `w` (the last one ellipsized).
	static func _wrap(font: Font, text: String, fs: int, w: float, max_lines: int) -> PackedStringArray:
		var out: PackedStringArray = PackedStringArray()
		var words: PackedStringArray = text.split(" ", false)
		var line: String = ""
		for i: int in words.size():
			var trial: String = words[i] if line == "" else line + " " + words[i]
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w or line == "":
				line = trial
			else:
				out.append(line)
				line = words[i]
				if out.size() == max_lines - 1:
					line = " ".join(words.slice(i))
					break
		if line != "":
			out.append(UiDraw.ellipsize(font, line, fs, w))
		return out
