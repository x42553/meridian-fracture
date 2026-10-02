class_name UiScreenLan
extends Control
## LAN lobby browser mock-up: discovered games (UDP broadcast on port 27615), filters, detail card with the
## player list and version/data-hash compatibility, chat, direct connect by IP.

const GAMES: Array[Dictionary] = [
	{"name": "Simon's Skirmish", "host": "MBP-M5", "map": "Ridgeline Crossing", "players": "3 / 8", "rules": "7.5k  1.0x  SW", "ping": 2, "ver": "0.1.0", "ok": true},
	{"name": "Ladder night #12", "host": "DESKTOP-4090", "map": "Salt Flats 4P", "players": "4 / 4", "rules": "10k  1.5x  SW", "ping": 6, "ver": "0.1.0", "ok": true, "full": true},
	{"name": "Coastal Clash", "host": "debian-nuc", "map": "Estuary Gate", "players": "5 / 6", "rules": "7.5k  1.0x", "ping": 14, "ver": "0.1.0", "ok": true},
	{"name": "LAN party (old build)", "host": "steamdeck", "map": "Dry River", "players": "2 / 4", "rules": "5k  1.0x", "ping": 31, "ver": "0.0.9", "ok": false},
	{"name": "Noobs only", "host": "laptop-lena", "map": "Twin Valleys", "players": "1 / 2", "rules": "20k  0.75x  SW", "ping": 9, "ver": "0.1.0", "ok": true},
	{"name": "Friday 4v4", "host": "gaming-rig", "map": "Salt Flats 8P", "players": "6 / 8", "rules": "10k  1.0x  SW", "ping": 3, "ver": "0.1.0", "ok": true},
	{"name": "Peaceful builders", "host": "mac-mini", "map": "Estuary Gate", "players": "1 / 6", "rules": "20k  0.5x", "ping": 5, "ver": "0.1.0", "ok": true},
	{"name": "Data mod test", "host": "win-dev", "map": "Ridgeline Crossing", "players": "2 / 8", "rules": "7.5k  1.0x", "ping": 4, "ver": "0.1.0", "ok": false, "hash": true},
]
const COLS: Array = [["GAME", 250.0], ["HOST", 170.0], ["MAP", 200.0], ["PLAYERS", 100.0], ["RULES", 170.0], ["PING", 80.0], ["BUILD", 110.0]]

var faction: String = "napc"
var skin: UiSkin
var _selected: int = 0
var _rows: Array[UiListRow] = []
var _detail_box: VBoxContainer
var _spin: Control

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
	left.add_child(_browser())
	left.add_child(_chat())
	cols.add_child(left)
	cols.add_child(_detail())
	root.add_child(_bottom())
	_select(0)

func _process(delta: float) -> void:
	if _spin != null:
		_spin.rotation += delta * 4.0

func _title_bar() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.text = "LAN MULTIPLAYER"
	t.add_theme_font_override("font", UiFonts.variable("res://fonts/orbitron_variable.ttf", 800, 5))
	t.add_theme_font_size_override("font_size", 34)
	v.add_child(t)
	var s := Label.new()
	s.theme_type_variation = &"DimLabel"
	s.text = "UDP BROADCAST 27615  //  ENET LOCKSTEP  //  2-8 PLAYERS, HUMANS AND AI"
	v.add_child(s)
	h.add_child(v)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"InsetPanel"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_spin = _Spinner.new()
	_spin.custom_minimum_size = Vector2(22.0, 22.0)
	(_spin as _Spinner).color = skin.accent
	_spin.pivot_offset = Vector2(11.0, 11.0)
	hb.add_child(_spin)
	var l := Label.new()
	l.theme_type_variation = &"NumLabel"
	l.text = "SCANNING...   %d GAMES FOUND" % GAMES.size()
	l.add_theme_font_size_override("font_size", 14)
	hb.add_child(l)
	chip.add_child(hb)
	h.add_child(chip)
	return h

func _browser() -> Control:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	var hl := Label.new()
	hl.theme_type_variation = &"HeaderLabel"
	hl.text = "GAMES ON YOUR NETWORK"
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(hl)
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter by name or map..."
	filter.custom_minimum_size = Vector2(260.0, 34.0)
	tools.add_child(filter)
	for txt in ["Hide full", "Hide incompatible"]:
		var cb := CheckBox.new()
		cb.text = txt
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = txt == "Hide incompatible" and false
		tools.add_child(cb)
	var refresh := Button.new()
	refresh.text = "REFRESH"
	refresh.focus_mode = Control.FOCUS_NONE
	tools.add_child(refresh)
	v.add_child(tools)
	var widths := PackedFloat32Array()
	var head_cells: Array[Dictionary] = []
	for c in COLS:
		widths.append(float(c[1]))
		head_cells.append({"text": c[0]})
	var header := UiListRow.new()
	header.skin = skin
	header.is_header = true
	header.cells = head_cells
	header.widths = widths
	header.custom_minimum_size = Vector2(0.0, 30.0)
	v.add_child(header)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	for i in GAMES.size():
		var g: Dictionary = GAMES[i]
		var row := UiListRow.new()
		row.skin = skin
		row.widths = widths
		row.dimmed = bool(g.get("full", false))
		var ok: bool = g["ok"]
		var ping: int = g["ping"]
		row.cells = [
			{"text": g["name"]}, {"text": g["host"], "color": UiPalette.TEXT_DIM}, {"text": g["map"], "color": UiPalette.TEXT_DIM},
			{"text": g["players"], "color": UiPalette.WARN if g.get("full", false) else UiPalette.OK},
			{"text": g["rules"], "color": UiPalette.TEXT_DIM},
			{"text": "%d ms" % ping, "color": UiPalette.OK if ping < 20 else UiPalette.WARN},
			{"text": ("v%s  OK" % g["ver"]) if ok else ("v%s  %s" % [g["ver"], "DATA" if g.get("hash", false) else "OLD"]), "color": UiPalette.OK if ok else UiPalette.DANGER},
		]
		var idx: int = i
		row.selected.connect(func() -> void: _select(idx))
		list.add_child(row)
		_rows.append(row)
	return p

func _chat() -> Control:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 0.5
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var hl := Label.new()
	hl.theme_type_variation = &"HeaderLabel"
	hl.text = "LOBBY CHAT"
	v.add_child(hl)
	var log := VBoxContainer.new()
	log.add_theme_constant_override("separation", 2)
	log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for line in [["MBP-M5", "Anyone up for a 3v3 on Ridgeline?", skin.accent], ["debian-nuc", "Joining in 1 min, finishing a match.", UiPalette.TEXT_DIM], ["laptop-lena", "Is Han balanced against Pacific yet?", UiPalette.TEXT_DIM], ["SYSTEM", "win-dev advertises different game data (hash 3C1B-77A0). Cannot join.", UiPalette.WARN]]:
		var l := Label.new()
		l.text = "[%s]  %s" % [line[0], line[1]]
		l.add_theme_color_override("font_color", line[2])
		l.add_theme_font_size_override("font_size", 15)
		log.add_child(l)
	v.add_child(log)
	var le := LineEdit.new()
	le.placeholder_text = "Press Enter to chat..."
	le.custom_minimum_size = Vector2(0.0, 34.0)
	v.add_child(le)
	return p

func _detail() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(560.0, 0.0)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 8)
	p.add_child(_detail_box)
	return p

func _select(i: int) -> void:
	_selected = i
	for k in _rows.size():
		_rows[k].is_selected = (k == i)
	for c in _detail_box.get_children():
		c.queue_free()
	var g: Dictionary = GAMES[i]
	var hl := Label.new()
	hl.theme_type_variation = &"HeaderLabel"
	hl.text = "GAME DETAILS"
	_detail_box.add_child(hl)
	var name_l := Label.new()
	name_l.text = String(g["name"]).to_upper()
	name_l.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	name_l.add_theme_font_size_override("font_size", 22)
	_detail_box.add_child(name_l)
	var sub := Label.new()
	sub.theme_type_variation = &"DimLabel"
	sub.text = "HOSTED BY %s  //  %s  //  %s" % [String(g["host"]).to_upper(), String(g["map"]).to_upper(), String(g["rules"]).to_upper()]
	_detail_box.add_child(sub)
	var ok: bool = g["ok"]
	var compat := PanelContainer.new()
	compat.theme_type_variation = &"InsetPanel"
	var cl := Label.new()
	cl.theme_type_variation = &"NumLabel"
	cl.text = ("BUILD %s  //  DATA HASH 9F3A-C21E  //  COMPATIBLE" % g["ver"]) if ok else ("BUILD %s  //  DATA HASH %s  //  CANNOT JOIN" % [g["ver"], "3C1B-77A0" if g.get("hash", false) else "0000-0000"])
	cl.add_theme_color_override("font_color", UiPalette.OK if ok else UiPalette.DANGER)
	cl.add_theme_font_size_override("font_size", 13)
	compat.add_child(cl)
	_detail_box.add_child(compat)
	var mp := TextureRect.new()
	mp.custom_minimum_size = Vector2(0.0, 150.0)
	mp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mp.texture = ImageTexture.create_from_image(DemoWorld.preview_image(DemoWorld.Mode.BATTLEFIELD, 120))
	_detail_box.add_child(mp)
	var ph := Label.new()
	ph.theme_type_variation = &"HeaderLabel"
	ph.text = "PLAYERS  %s" % g["players"]
	_detail_box.add_child(ph)
	var names: Array = ["MBP-M5", "AI Hard", "steam-jules", "AI Medium", "debian-nuc", "AI Brutal"]
	var codes: Array = ["napc", "nec", "def", "pd", "han", "ae"]
	var subs: Array = ["Canada", "Vanilla", "Russia", "Japan", "Vietnam", "Nigeria"]
	var pings: Array = [2, 0, 11, 0, 14, 0]
	var count: int = int(String(g["players"]).split(" / ")[0])
	for k in 8:
		if k >= count:
			var op := Label.new()
			op.theme_type_variation = &"DimLabel"
			op.text = "  OPEN SLOT %d" % (k + 1)
			op.custom_minimum_size = Vector2(0.0, 28.0)
			_detail_box.add_child(op)
			continue
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		var sw := ColorRect.new()
		sw.color = UiScreenSkirmish.PLAYER_COLORS[k]
		sw.custom_minimum_size = Vector2(5.0, 28.0)
		hb.add_child(sw)
		var em := UiEmblemView.new(28.0)
		em.code = codes[k]
		em.color = UiSkin.for_faction(codes[k]).accent
		hb.add_child(em)
		var nm := Label.new()
		nm.text = names[k]
		nm.custom_minimum_size = Vector2(150.0, 0.0)
		nm.add_theme_font_size_override("font_size", 16)
		hb.add_child(nm)
		var fl := Label.new()
		fl.theme_type_variation = &"DimLabel"
		fl.text = "%s / %s" % [String(codes[k]).to_upper(), subs[k]]
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(fl)
		var pl := Label.new()
		pl.theme_type_variation = &"NumLabel"
		pl.text = "%d ms" % pings[k] if pings[k] > 0 else "AI"
		pl.add_theme_color_override("font_color", UiPalette.OK if pings[k] < 20 else UiPalette.WARN)
		hb.add_child(pl)
		_detail_box.add_child(hb)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(fill)
	var join := Button.new()
	join.theme_type_variation = &"PrimaryButton"
	join.text = "JOIN GAME" if ok else "INCOMPATIBLE"
	join.disabled = not ok or g.get("full", false)
	join.custom_minimum_size = Vector2(0.0, 52.0)
	join.focus_mode = Control.FOCUS_NONE
	join.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	join.add_theme_font_size_override("font_size", 16)
	_detail_box.add_child(join)

func _bottom() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "< BACK"
	back.custom_minimum_size = Vector2(180.0, 50.0)
	back.focus_mode = Control.FOCUS_NONE
	h.add_child(back)
	var host := Button.new()
	host.text = "HOST NEW GAME"
	host.custom_minimum_size = Vector2(220.0, 50.0)
	host.focus_mode = Control.FOCUS_NONE
	h.add_child(host)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var dl := Label.new()
	dl.theme_type_variation = &"DimLabel"
	dl.text = "DIRECT CONNECT"
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dl)
	var ip := LineEdit.new()
	ip.text = "192.168.1.42"
	ip.custom_minimum_size = Vector2(190.0, 44.0)
	h.add_child(ip)
	var port := LineEdit.new()
	port.text = "27615"
	port.custom_minimum_size = Vector2(90.0, 44.0)
	h.add_child(port)
	var go := Button.new()
	go.text = "CONNECT"
	go.custom_minimum_size = Vector2(160.0, 50.0)
	go.focus_mode = Control.FOCUS_NONE
	h.add_child(go)
	return h

class _Spinner extends Control:
	var color: Color = Color.WHITE
	func _draw() -> void:
		draw_arc(size * 0.5, 9.0, 0.0, TAU * 0.72, 24, color, 3.0, true)
