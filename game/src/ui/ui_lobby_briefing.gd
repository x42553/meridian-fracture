class_name UiLobbyBriefing
extends PanelContainer
## Faction briefing panel of the lobby (ui.md 5.14.7): all text comes from the bible through the resolved defs
## (`DefFaction`, `DefRoster`, `DefModifier`, `DefUnit`, `DefPower`), never from JSON files. Tabs: OVERVIEW (emblem, name, motto,
## identity, subfaction title and lore, the modifier list with up / down arrows classed good / bad, traits, opening and
## counterplay), UNITS (the producible roster with tier pips, cost and UNIQUE badges for subfaction replacements, plus the
## roster delta list) and POWERS (support powers and the superweapon).

const TAB_IDS: Array[StringName] = [&"overview", &"units", &"powers"]
## Stats where a negative delta is an improvement (cost, times, reload).
const LOWER_IS_BETTER: Array[int] = [DefEnums.Stat.COST, DefEnums.Stat.BUILD_TIME, DefEnums.Stat.RELOAD, DefEnums.Stat.REARM, DefEnums.Stat.REPAIR_COST]

var _data: GameData = null
var _tabs: UiTabBar = null
var _body: Control = null
var _scroll: ScrollContainer = null
var _header: UiPanelHeader = null
var _tab: StringName = &"overview"
var _roster: DefRoster = null
var _random_note: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	_header = UiPanelHeader.new("Faction briefing", "FROM THE DESIGN BIBLE")
	v.add_child(_header)
	_tabs = UiTabBar.new()
	var list: Array[Dictionary] = [{"id": &"overview", "text": "OVERVIEW"}, {"id": &"units", "text": "UNITS"}, {"id": &"powers", "text": "POWERS"}]
	_tabs.set_tabs(list)
	_tabs.set_focusable(true)
	_tabs.tab_selected.connect(func(_i: int, id: StringName) -> void:
		_tab = id
		_rebuild())
	v.add_child(_tabs)
	# a scroll container: its minimum height is 0, so a long tab never pushes the screen's bottom bar off the window
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = MarginContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


## Selects a tab by id (`overview`, `units`, `powers`).
func select_tab(id: StringName) -> void:
	_tab = id
	_tabs.select_id(id)
	_rebuild()


func setup(data: GameData) -> void:
	_data = data


## Shows the roster a slot stands for (`roster` null = random pick with `note`).
func show_roster(roster: DefRoster, note: String = "") -> void:
	if roster == _roster and note == _random_note and _body.get_child_count() > 0:
		return
	_roster = roster
	_random_note = note
	_rebuild()


func _rebuild() -> void:
	for c: Node in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	if _data == null:
		return
	var view: Control = null
	if _roster == null:
		view = _random_view()
	else:
		match _tab:
			&"units":
				view = _units_view()
			&"powers":
				view = _powers_view()
			_:
				view = _overview_view()
	_body.add_child(view)
	_scroll.scroll_vertical = 0


func _faction() -> DefFaction:
	return _data.factions[_roster.faction] if _roster != null and _roster.faction >= 0 else null


func _accent_of(f: DefFaction) -> Color:
	return UiSkinSet.shared().skin_for(f.code.to_lower()).accent if f != null else UiScreenKit.accent(self)


func _random_view() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiScreenKit.label("RANDOM ROSTER", &"HeaderLabel"))
	v.add_child(UiScreenKit.label(_random_note if _random_note != "" else "A roster is drawn when the match starts.", &"SubLabel", true))
	v.add_child(UiScreenKit.label("Rosters are atomic: a faction with one of its subfactions, or the vanilla package. The loading screen shows the drawn roster.",
		&"DimLabel", true))
	return v


# ---------------------------------------------------------------- overview

func _overview_view() -> Control:
	return _overview_core()


# ---------------------------------------------------------------- 3D showcase

## The roster's units worth showing, best first: subfaction replacements, then by tier and cost (at most 8 ids).
func _showcase_ids() -> PackedStringArray:
	var unique: Dictionary = {}
	for k: Variant in _roster.replaced_by:
		unique[int(_roster.replaced_by[k])] = true
	var entries: Array[Dictionary] = []
	for ui: int in _roster.producible_units:
		var u: DefUnit = _roster.units[ui]
		if u != null and u.weapons.size() > 0:
			entries.append({"id": u.id, "rank": (1000 if unique.has(ui) else 0) + u.tier * 100 + mini(u.cost / 50, 99)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rank"]) > int(b["rank"]))
	var out: PackedStringArray = PackedStringArray()
	for e: Dictionary in entries:
		out.append(str(e["id"]))
		if out.size() >= 8:
			break
	return out


## A turntable of the roster's units (UiModelViewer, previous / next in its strip); null when no renderer is available.
func _showcase_viewer() -> UiModelViewer:
	var ids: PackedStringArray = _showcase_ids()
	if ids.is_empty():
		return null
	var names: PackedStringArray = PackedStringArray()
	for id: String in ids:
		var i: int = _data.unit_idx(id)
		names.append(_data.units[i].ui_name if i >= 0 else id)
	var viewer: UiModelViewer = UiModelViewer.new(Vector2(230.0, 146.0))
	if not viewer.set_list(ids, names, _roster.id):
		viewer.free()
		return null
	viewer.name = "RosterShowcase"
	viewer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	viewer.tooltip_text = "A unit of this roster. Drag to rotate, wheel to zoom, < > to browse."
	return viewer


func _overview_core() -> Control:
	var f: DefFaction = _faction()
	var acc: Color = _accent_of(f)
	var viewer: UiModelViewer = _showcase_viewer()  # the 3D turntable replaces the big badge (the badge shrinks next to the name)
	var h: Container = null
	if viewer != null:
		# a flow: viewer + text on the first row, the modifier column wraps below it when the panel is narrow (720p lobby)
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 22)
		flow.add_theme_constant_override("v_separation", 12)
		h = flow
	else:
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", 22)
		h = box
	var badge: UiFactionBadge = UiFactionBadge.new(f.code.to_lower() if f != null else "", 40.0 if viewer != null else 112.0)
	badge.sub_key = _sub_key()
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if viewer != null:
		h.add_child(viewer)
	else:
		h.add_child(badge)
	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", 5)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if viewer != null:
		left.custom_minimum_size = Vector2(360.0, 0.0)
	h.add_child(left)
	var name_l: Label = UiScreenKit.label(f.ui_name.to_upper() if f != null else "", &"HeaderLabel")
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", acc)
	if viewer != null:
		var title_row: HBoxContainer = HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 10)
		title_row.add_child(badge)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(name_l)
		left.add_child(title_row)
	else:
		left.add_child(name_l)
	if f != null:
		left.add_child(UiScreenKit.label("\"%s\"" % f.ui_motto, &"SubLabel", true))
		left.add_child(UiScreenKit.label(f.ui_identity, &"DimLabel", true))
	if not _roster.is_vanilla:
		var sub: Label = UiScreenKit.label("%s  //  %s" % [_roster.id.get_slice(".", 2).replace("_", " ").to_upper(), _roster.ui_title.to_upper()], &"HeaderLabel")
		sub.add_theme_color_override("font_color", UiPalette.CREDITS)
		left.add_child(sub)
		var lore: Label = UiScreenKit.label(_roster.ui_lore, &"DimLabel", true)
		lore.max_lines_visible = 3
		lore.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left.add_child(lore)
	else:
		left.add_child(UiScreenKit.label("Vanilla roster: the faction without subfaction changes.", &"DimLabel", true))
	var tips: Label = UiScreenKit.label("OPENING  " + _roster.ui_opening, &"DimLabel", true)
	tips.max_lines_visible = 2
	tips.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(tips)
	# right column: modifiers and traits
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size = Vector2(300.0, 0.0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.9
	h.add_child(right)
	right.add_child(UiScreenKit.label("MODIFIERS", &"CaptionLabel"))
	for line: Dictionary in modifier_lines(_data, _roster):
		right.add_child(_modifier_row(line))
	if f != null:
		right.add_child(UiScreenKit.spacer(4.0))
		right.add_child(UiScreenKit.label("TRAITS", &"CaptionLabel"))
		for t: String in f.ui_traits:
			if t.begins_with("Strengths"):
				continue
			var tl: Label = UiScreenKit.label(t, &"DimLabel", true)
			tl.max_lines_visible = 2
			tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			right.add_child(tl)
	return h


func _modifier_row(line: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var good: bool = bool(line["good"])
	var arrow: Label = UiScreenKit.label("+" if int(line["delta_bp"]) > 0 else "-", &"OkLabel" if good else &"DangerLabel")
	arrow.text = "▲" if int(line["delta_bp"]) > 0 else "▼"
	arrow.custom_minimum_size = Vector2(16.0, 0.0)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(arrow)
	var t: Label = UiScreenKit.label(String(line["text"]) + ("  (conditional)" if bool(line["conditional"]) else ""), &"DimLabel", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size = Vector2(240.0, 0.0)
	row.add_child(t)
	return row


func _sub_key() -> String:
	if _roster == null or _roster.is_vanilla:
		return ""
	var p: PackedStringArray = _roster.id.split(".")
	return "%s.%s" % [p[1], p[2]] if p.size() >= 3 else ""


## The modifiers that make `roster` different, subfaction layer first: {text, delta_bp, stat, good, conditional}.
static func modifier_lines(data: GameData, roster: DefRoster) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for layer: int in [2, 1]:
		var seen: Dictionary = {}
		for mi: int in roster.modifier_list:
			var m: DefModifier = data.modifiers[mi]
			if m.layer != layer or m.ui_source_text == "" or seen.has(m.ui_source_text):
				continue
			seen[m.ui_source_text] = true
			if layer == 1 and not roster.is_vanilla:
				continue  # the subfaction card lists its own changes; the faction rows are in the faction traits
			var better: bool = (m.delta_bp < 0) == LOWER_IS_BETTER.has(m.stat)
			out.append({"text": m.ui_source_text.split(" Strengths")[0], "delta_bp": m.delta_bp, "stat": m.stat, "good": better, "conditional": m.cond != 0})
	return out


# ---------------------------------------------------------------- units

func _units_view() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	var unique: Dictionary = {}
	for k: Variant in _roster.replaced_by:
		unique[int(_roster.replaced_by[k])] = int(k)
	for ui: int in _roster.producible_units:
		var u: DefUnit = _roster.units[ui]
		if u == null:
			continue
		var tile: Control = _unit_tile(u, unique.has(ui))
		_make_clickable(tile, u.id)
		flow.add_child(tile)
	v.add_child(flow)
	var delta: Array[String] = roster_delta(_data, _roster)
	if not delta.is_empty():
		v.add_child(UiScreenKit.label("ROSTER DELTA", &"CaptionLabel"))
		for line: String in delta:
			v.add_child(UiScreenKit.label(line, &"DimLabel"))
	return v


func _unit_tile(u: DefUnit, is_unique: bool) -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = &"InsetPanel"
	p.custom_minimum_size = Vector2(176.0, 54.0)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var top: HBoxContainer = HBoxContainer.new()
	v.add_child(top)
	var name_l: Label = UiScreenKit.label(u.ui_name, &"SubLabel", false, HORIZONTAL_ALIGNMENT_LEFT, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.custom_minimum_size = Vector2(60.0, 0.0)
	top.add_child(name_l)
	var bottom: HBoxContainer = HBoxContainer.new()
	v.add_child(bottom)
	var pips: Label = UiScreenKit.label("■".repeat(clampi(u.tier, 1, 3)), &"CaptionLabel")
	pips.add_theme_color_override("font_color", UiScreenKit.accent(self))
	bottom.add_child(pips)
	var cost: Label = UiScreenKit.label(UiFormatLite.credits(maxi(u.cost, 0)), &"CreditsLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.add_theme_font_size_override("font_size", 13)
	bottom.add_child(cost)
	if is_unique:
		var badge: Label = UiScreenKit.label("UNIQUE", &"CaptionLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
		badge.add_theme_color_override("font_color", UiPalette.CREDITS)
		top.add_child(badge)
	return p


## A click on a unit tile or power row opens the Field Manual at that card (`UiScreenFieldManual.open`, pushed as an overlay).
func _make_clickable(c: Control, def_id: String) -> void:
	if def_id == "" or UiDraw.optional_script(&"UiScreenFieldManual") == null:
		return
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.tooltip_text = "Open in the Field Manual"
	c.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			open_manual(def_id))


## Opens the Field Manual on the roster shown in the briefing, focused on `def_id`. False when it cannot be pushed.
func open_manual(def_id: String) -> bool:
	if _roster == null:
		return false
	return UiScreenFieldManual.open({"roster_id": _roster.id, "focus_id": def_id})


## Replacement lines ("Pathfinder APC -> Beaver Amphibious APC") of a subfaction roster.
static func roster_delta(data: GameData, roster: DefRoster) -> Array[String]:
	var out: Array[String] = []
	var keys: Array = roster.replaced_by.keys()
	keys.sort()
	for k: Variant in keys:
		out.append("%s  ->  %s" % [data.units[int(k)].ui_name, data.units[int(roster.replaced_by[k])].ui_name])
	if roster.parent >= 0:
		var base: DefRoster = data.rosters[roster.parent]
		for ui: int in base.producible_units:
			if not roster.producible_units.has(ui) and not roster.replaced_by.has(ui):
				out.append("REMOVED  %s" % data.units[ui].ui_name)
	return out


# ---------------------------------------------------------------- powers

func _powers_view() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	for pi: int in _roster.power_list:
		if pi < 0 or pi >= _data.powers.size():
			continue
		var p: DefPower = _data.powers[pi]
		var prow: Control = _power_row(p.ui_name, "%s credits  //  %d s cooldown" % [UiFormatLite.credits(p.cost), p.cooldown_t * SimConfig.TICK_MS / 1000],
			p.ui_effect_text)
		_make_clickable(prow, p.id)
		v.add_child(prow)
	if _roster.superweapon_def != null:
		var s: DefSuperweapon = _roster.superweapon_def
		var row: Control = _power_row("SUPERWEAPON  //  " + s.ui_name, "%d s recharge  //  %d s warning" % [s.recharge_t * SimConfig.TICK_MS / 1000,
			s.warning_t * SimConfig.TICK_MS / 1000], s.ui_text)
		_make_clickable(row, s.id)
		v.add_child(row)
	return v


func _power_row(title: String, meta: String, text: String) -> Control:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = &"InsetPanel"
	var c: VBoxContainer = VBoxContainer.new()
	c.add_theme_constant_override("separation", 1)
	p.add_child(c)
	var head: HBoxContainer = HBoxContainer.new()
	c.add_child(head)
	var t: Label = UiScreenKit.label(title, &"NameLabel")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiScreenKit.label(meta, &"CaptionLabel"))
	if text != "":
		var d: Label = UiScreenKit.label(text, &"DimLabel", true)
		d.max_lines_visible = 2
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.add_child(d)
	return p
