class_name UiScreenSkirmish
extends Control
## Skirmish setup: 8 player slots (type / faction / subfaction / team / colour), map preview with start
## positions, rules, and a faction detail card fed by the bible slice.

const PLAYER_COLORS: Array[Color] = [Color("#e0503a"), Color("#33a0ec"), Color("#33c98a"), Color("#f3c022"), Color("#9a6ae6"), Color("#f07f2c"), Color("#26d6e8"), Color("#e65aa6")]
const TYPES: Array[String] = ["Human", "AI - Easy", "AI - Medium", "AI - Hard", "AI - Brutal", "Open", "Closed"]

var faction: String = "napc"
var skin: UiSkin
var _rows: Array[Dictionary] = []
var _focus: int = 0
var _detail: Dictionary = {}
var _map_tex: TextureRect
var _roster: UiRosterStrip
var _baker: UiIconBaker
var _bake_token: int = 0

func _init(f: String) -> void:
	faction = f

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skin = UiSkin.for_faction(faction)
	theme = UiTheme.build(skin)
	var bg := ColorRect.new()
	bg.color = UiPalette.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var deco := _Backdrop.new()
	deco.skin = skin
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(deco)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(_title_bar())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_players_panel())
	left.add_child(_detail_panel())
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.custom_minimum_size = Vector2(640.0, 0.0)
	right.add_child(_map_panel())
	right.add_child(_rules_panel())
	cols.add_child(right)
	root.add_child(_bottom_bar())
	_set_focus(0)

# --- sections ------------------------------------------------------------------------------------------------

func _title_bar() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var em := UiEmblemView.new(52.0)
	em.code = faction
	em.color = skin.accent
	h.add_child(em)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.text = "SKIRMISH"
	t.add_theme_font_override("font", UiFonts.variable("res://fonts/orbitron_variable.ttf", 800, 5))
	t.add_theme_font_size_override("font_size", 34)
	v.add_child(t)
	var s := Label.new()
	s.theme_type_variation = &"DimLabel"
	s.text = "NEW MATCH  //  UP TO 8 COMMANDERS  //  HOST-AUTHORITATIVE LOCKSTEP"
	v.add_child(s)
	h.add_child(v)
	return h

func _panel(title: String, tag: String = "") -> Array:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.theme_type_variation = &"HeaderLabel"
	l.text = title
	hb.add_child(l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	if tag != "":
		var tg := Label.new()
		tg.theme_type_variation = &"NumLabel"
		tg.add_theme_font_size_override("font_size", 12)
		tg.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		tg.text = tag
		hb.add_child(tg)
	v.add_child(hb)
	return [p, v]

func _players_panel() -> Control:
	var pv: Array = _panel("PLAYERS", "8 SLOTS  //  TEAM GAMES SUPPORTED")
	var v: VBoxContainer = pv[1]
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	for spec in [["", 76], ["PLAYER", 158], ["FACTION", 232], ["SUBFACTION", 190], ["TEAM", 118], ["STATUS", 90]]:
		var l := Label.new()
		l.theme_type_variation = &"DimLabel"
		l.text = spec[0]
		l.custom_minimum_size = Vector2(float(spec[1]), 0.0)
		l.add_theme_font_size_override("font_size", 11)
		hdr.add_child(l)
	v.add_child(hdr)
	var defaults: Array = [[0, 0, 2, 0], [3, 1, 1, 1], [3, 2, 0, 1], [3, 3, 1, 2], [2, 4, 3, 2], [3, 5, 2, 2], [5, 6, 0, 0], [6, 7, 0, 0]]
	var facs: Array = DemoData.slice()["factions"]
	var codes: Array = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]
	for i in 8:
		var d: Array = defaults[i]
		var r := _slot_row(i, d[0], codes.find(facs[i]["code"]) if false else i, d[2], d[3])
		v.add_child(r)
	return pv[0]

func _slot_row(i: int, type_idx: int, fac_idx: int, sub_idx: int, team_idx: int) -> Control:
	var pc := PanelContainer.new()
	pc.theme_type_variation = &"InsetPanel"
	pc.add_theme_stylebox_override("panel", _row_box(i == 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var swatch := ColorRect.new()
	swatch.color = PLAYER_COLORS[i]
	swatch.custom_minimum_size = Vector2(6.0, 40.0)
	h.add_child(swatch)
	var num := Label.new()
	num.theme_type_variation = &"NumLabel"
	num.text = str(i + 1)
	num.custom_minimum_size = Vector2(14.0, 0.0)
	num.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	h.add_child(num)
	var em := UiEmblemView.new(34.0)
	var facs: Array = DemoData.slice()["factions"]
	em.code = facs[fac_idx]["code"]
	em.color = UiSkin.for_faction(em.code).accent if type_idx < 5 else UiPalette.TEXT_MUTE
	h.add_child(em)
	var type_ob := _option(TYPES, type_idx, 158.0)
	h.add_child(type_ob)
	var fac_names: Array[String] = []
	for f in facs:
		fac_names.append("%s  %s" % [String(f["code"]).to_upper(), f["name"]])
	fac_names.append("Random")
	var fac_ob := _option(fac_names, fac_idx, 232.0)
	h.add_child(fac_ob)
	var sub_ob := _option(_sub_names(fac_idx), sub_idx, 190.0)
	h.add_child(sub_ob)
	var team_ob := _option(["None", "Team 1", "Team 2", "Team 3", "Team 4"], team_idx, 110.0)
	h.add_child(team_ob)
	var status := Label.new()
	status.theme_type_variation = &"NumLabel"
	status.custom_minimum_size = Vector2(90.0, 0.0)
	status.text = "READY" if type_idx in [0, 1, 2, 3, 4] else ("OPEN" if type_idx == 5 else "CLOSED")
	status.add_theme_color_override("font_color", UiPalette.OK if status.text == "READY" else UiPalette.TEXT_MUTE)
	h.add_child(status)
	var row: Dictionary = {"panel": pc, "emblem": em, "fac": fac_ob, "sub": sub_ob, "type": type_ob}
	_rows.append(row)
	var idx: int = _rows.size() - 1
	fac_ob.item_selected.connect(func(k: int) -> void:
		var use: int = mini(k, 7)
		em.code = facs[use]["code"]
		em.color = UiSkin.for_faction(em.code).accent
		sub_ob.clear()
		for s in _sub_names(use):
			sub_ob.add_item(s)
		_set_focus(idx))
	sub_ob.item_selected.connect(func(_k: int) -> void: _set_focus(idx))
	pc.mouse_entered.connect(func() -> void: _set_focus(idx))
	return pc

func _row_box(mine: bool) -> UiStyleBox:
	var sb: UiStyleBox = UiTheme.inset_box(skin)
	sb.set_padding(0.0, 4.0, 10.0, 4.0)
	if mine:
		sb.border_color = skin.accent.darkened(0.2)
		sb.fill_top = Color(skin.accent, 0.10)
	return sb

func _sub_names(fac_idx: int) -> Array[String]:
	var out: Array[String] = ["Vanilla"]
	var facs: Array = DemoData.slice()["factions"]
	for r in (facs[fac_idx]["rosters"] as Array).slice(1):
		out.append(String(r["name"]))
	return out

func _option(items: Array, selected: int, width: float) -> OptionButton:
	var ob := OptionButton.new()
	for s in items:
		ob.add_item(String(s))
	ob.selected = selected
	ob.custom_minimum_size = Vector2(width, 40.0)
	ob.focus_mode = Control.FOCUS_NONE
	ob.clip_text = true
	ob.fit_to_longest_item = false
	return ob

func _detail_panel() -> Control:
	var pv: Array = _panel("FACTION BRIEFING", "FROM THE DESIGN BIBLE")
	var v: VBoxContainer = pv[1]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	v.add_child(h)
	var em := UiEmblemView.new(120.0)
	em.line_width = 3.0
	h.add_child(em)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var name_l := Label.new()
	name_l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	name_l.add_theme_font_size_override("font_size", 19)
	mid.add_child(name_l)
	var motto := Label.new()
	motto.add_theme_font_size_override("font_size", 17)
	mid.add_child(motto)
	var ident := Label.new()
	ident.theme_type_variation = &"DimLabel"
	ident.add_theme_font_size_override("font_size", 14)
	ident.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(ident)
	var sub := Label.new()
	sub.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	sub.add_theme_font_size_override("font_size", 13)
	mid.add_child(sub)
	var mods := Label.new()
	mods.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mods.add_theme_font_size_override("font_size", 14)
	mid.add_child(mods)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330.0, 0.0)
	right.add_theme_constant_override("separation", 3)
	h.add_child(right)
	var rh := Label.new()
	rh.theme_type_variation = &"HeaderLabel"
	rh.text = "ROSTER DELTA"
	right.add_child(rh)
	var delta := Label.new()
	delta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	delta.add_theme_font_size_override("font_size", 14)
	right.add_child(delta)
	var rh2 := Label.new()
	rh2.theme_type_variation = &"HeaderLabel"
	rh2.text = "ROSTER"
	v.add_child(rh2)
	_roster = UiRosterStrip.new()
	_roster.skin = skin
	v.add_child(_roster)
	_baker = UiIconBaker.new()
	add_child(_baker)
	_detail = {"emblem": em, "name": name_l, "motto": motto, "ident": ident, "sub": sub, "mods": mods, "delta": delta}
	pv[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	return pv[0]

func _set_focus(i: int) -> void:
	_focus = i
	for k in _rows.size():
		var pc: PanelContainer = _rows[k]["panel"]
		pc.add_theme_stylebox_override("panel", _row_box(k == i))
	var facs: Array = DemoData.slice()["factions"]
	var fi: int = mini((_rows[i]["fac"] as OptionButton).selected, 7)
	var f: Dictionary = facs[fi]
	var si: int = maxi((_rows[i]["sub"] as OptionButton).selected, 0)
	var r: Dictionary = f["rosters"][si]
	var fs: UiSkin = UiSkin.for_faction(f["code"])
	(_detail["emblem"] as UiEmblemView).code = f["code"]
	(_detail["emblem"] as UiEmblemView).color = fs.accent
	var nl: Label = _detail["name"]
	nl.text = String(f["name"]).to_upper()
	nl.add_theme_color_override("font_color", fs.accent)
	(_detail["motto"] as Label).text = "\"%s\"" % f["motto"]
	(_detail["ident"] as Label).text = String(f["identity"])
	var sl: Label = _detail["sub"]
	sl.text = "VANILLA" if si == 0 else "%s  //  %s" % [String(r["name"]).to_upper(), String(r["title"]).to_upper()]
	sl.add_theme_color_override("font_color", fs.accent2)
	var lines: PackedStringArray = PackedStringArray()
	for m in r["modifiers"]:
		lines.append("- " + String(m))
	if lines.is_empty():
		lines.append("Baseline roster: %s." % String(r["identity"]))
	(_detail["mods"] as Label).text = "\n".join(lines)
	var units: Dictionary = DemoData.slice()["units"]
	var dl := PackedStringArray()
	for rep in r["replacements"]:
		dl.append("%s  ->  %s" % [units[rep["replaced_unit_id"]]["name"], units[rep["replacement_unit_id"]]["name"]])
	for rem in r["removed"]:
		dl.append("REMOVED  %s" % units[rem]["name"])
	if dl.is_empty():
		dl.append("No unit changes (vanilla roster).")
	(_detail["delta"] as Label).text = "\n".join(dl)
	_refresh_roster(r, fs)

func _refresh_roster(r: Dictionary, fs: UiSkin) -> void:
	_bake_token += 1
	var token: int = _bake_token
	var units: Dictionary = DemoData.slice()["units"]
	var unique_ids: Array = []
	for rep in r["replacements"]:
		unique_ids.append(rep["replacement_unit_id"])
	var kinds := PackedStringArray()
	var list: Array[Dictionary] = []
	for uid in r["units"]:
		var u: Dictionary = units[uid]
		var kind: String = DemoModels.kind_for(u["name"], DemoData.category_of(String(u["producer"])))
		list.append({"name": u["name"], "kind": kind, "tier": int(u["tier"]) if u["tier"] != null else 1, "unique": unique_ids.has(uid)})
		if not kinds.has(kind):
			kinds.append(kind)
	var size := Vector2i(176, 120)
	await _baker.bake(kinds, size, fs.accent, fs.accent2)
	if token != _bake_token:
		return
	for e in list:
		e["icon"] = _baker.get_icon(e["kind"], size, fs.accent)
	_roster.skin = fs
	_roster.set_entries(list)

func _map_panel() -> Control:
	var pv: Array = _panel("MAP", "PROCEDURAL  //  SEEDED")
	var v: VBoxContainer = pv[1]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"InsetPanel"
	_map_tex = TextureRect.new()
	_map_tex.custom_minimum_size = Vector2(280.0, 280.0)
	_map_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_map_tex.texture = ImageTexture.create_from_image(DemoWorld.preview_image(DemoWorld.Mode.BATTLEFIELD, 140))
	_map_tex.draw.connect(_draw_starts)
	frame.add_child(_map_tex)
	h.add_child(frame)
	var f := VBoxContainer.new()
	f.add_theme_constant_override("separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(f)
	for spec in [["NAME", "Ridgeline Crossing"], ["FAMILY", "Mixed coast / river"], ["SIZE", "192 x 192 cells"], ["SEED", "0x5A17C3E9"], ["EXITS", "2 per start area"]]:
		var l := Label.new()
		l.theme_type_variation = &"DimLabel"
		l.text = spec[0]
		l.add_theme_font_size_override("font_size", 11)
		f.add_child(l)
		var val := Label.new()
		val.text = spec[1]
		val.add_theme_font_size_override("font_size", 16)
		f.add_child(val)
	var b := Button.new()
	b.text = "RE-ROLL SEED"
	b.focus_mode = Control.FOCUS_NONE
	f.add_child(b)
	return pv[0]

func _draw_starts() -> void:
	var s: Vector2 = _map_tex.size
	var font: Font = UiFonts.get_font(UiFonts.Role.HEAD)
	for i in 8:
		var a: float = float(i) / 8.0 * TAU + 0.4
		var p: Vector2 = s * 0.5 + Vector2(cos(a), sin(a)) * s * 0.36
		_map_tex.draw_circle(p, 11.0, Color(0, 0, 0, 0.7))
		_map_tex.draw_circle(p, 9.0, PLAYER_COLORS[i])
		_map_tex.draw_string(font, p + Vector2(-8.0, 4.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 16.0, 11, Color("#0b1016"))

func _rules_panel() -> Control:
	var pv: Array = _panel("RULES", "MATCH RULES")
	var v: VBoxContainer = pv[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	_rule_label(grid, "STARTING CREDITS")
	grid.add_child(_option(["2,500", "5,000", "7,500  (preset)", "10,000", "20,000"], 2, 250.0))
	_rule_label(grid, "GAME SPEED")
	var sl := HSlider.new()
	sl.min_value = 0.5
	sl.max_value = 2.0
	sl.step = 0.25
	sl.value = 1.0
	sl.custom_minimum_size = Vector2(250.0, 24.0)
	sl.focus_mode = Control.FOCUS_NONE
	grid.add_child(sl)
	_rule_label(grid, "UNIT CAP")
	grid.add_child(_option(["100", "150  (default)", "200", "300"], 1, 250.0))
	for spec in [["SUPERWEAPONS", true], ["FOG OF WAR", true], ["SHARED ALLY VISION", true], ["CRATES / SALVAGE BONUS", false]]:
		_rule_label(grid, spec[0])
		var cb := CheckButton.new()
		cb.button_pressed = spec[1]
		cb.focus_mode = Control.FOCUS_NONE
		cb.text = "ON" if spec[1] else "OFF"
		cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.add_child(cb)
	pv[0].size_flags_vertical = Control.SIZE_EXPAND_FILL
	return pv[0]

func _rule_label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"DimLabel"
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)

func _bottom_bar() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "< BACK"
	back.custom_minimum_size = Vector2(180.0, 50.0)
	back.focus_mode = Control.FOCUS_NONE
	h.add_child(back)
	var save := Button.new()
	save.text = "SAVE PRESET"
	save.custom_minimum_size = Vector2(180.0, 50.0)
	save.focus_mode = Control.FOCUS_NONE
	h.add_child(save)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "6 PLAYERS  //  2 OPEN  //  DATA HASH 9F3A-C21E"
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hint)
	var go := Button.new()
	go.theme_type_variation = &"PrimaryButton"
	go.text = "START GAME"
	go.custom_minimum_size = Vector2(300.0, 54.0)
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	go.add_theme_font_size_override("font_size", 17)
	h.add_child(go)
	return h

## For screenshots: opens the faction dropdown of the first slot.
func open_popup() -> void:
	(_rows[0]["fac"] as OptionButton).show_popup()

class _Backdrop extends Control:
	var skin: UiSkin
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var step: float = 48.0
		var c := Color(1, 1, 1, 0.022)
		var x: float = 0.0
		while x < size.x:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), c, 1.0)
			x += step
		var y: float = 0.0
		while y < size.y:
			draw_line(Vector2(0.0, y), Vector2(size.x, y), c, 1.0)
			y += step
		var g := PackedColorArray([Color(skin.accent, 0.10), Color(skin.accent, 0.0), Color(skin.accent, 0.0), Color(skin.accent, 0.10)])
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, 160.0), Vector2(0, 160.0)]), PackedColorArray([Color(skin.accent, 0.12), Color(skin.accent, 0.12), Color(skin.accent, 0.0), Color(skin.accent, 0.0)]))
