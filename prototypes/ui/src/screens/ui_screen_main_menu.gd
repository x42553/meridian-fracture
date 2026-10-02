class_name UiScreenMainMenu
extends Control
## Cinematic main menu: a live 3D hero scene (dusk desert, heavy tank in the foreground, drifting dust) under
## a vignette + letterbox shader, with the logo block, menu stack and a featured-faction card on top.

signal navigate(screen: String)

var host: Node
var faction: String = "napc"
var skin: UiSkin
var world: DemoWorld
var _t: float = 0.0
var _vig: UiVignette

func _init(h: Node, f: String) -> void:
	host = h
	faction = f

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	skin = UiSkin.for_faction(faction)
	theme = UiTheme.build(skin)
	world = DemoWorld.new()
	world.build(DemoWorld.Mode.HERO, skin.accent, skin.accent2)
	host.add_child(world)
	host.move_child(world, 0)
	_vig = UiVignette.new(0.8, 0.075, 0.6, 0.06, skin.accent)
	add_child(_vig)
	_build_logo()
	_build_menu()
	_build_featured()
	_build_chrome()

func _process(delta: float) -> void:
	_t += delta
	world.yaw_deg = 28.0 + sin(_t * 0.17) * 9.0
	world.distance = 21.0 + sin(_t * 0.11) * 2.0
	world.focus = Vector3(0.0, 2.2 + sin(_t * 0.13) * 0.3, 0.0)
	world.apply_camera()
	_vig.set_time(_t)

func _build_logo() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(104.0, 96.0)
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var em := UiEmblemView.new(96.0)
	em.code = faction
	em.color = skin.accent
	em.line_width = 3.0
	row.add_child(em)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -6)
	var t1 := Label.new()
	t1.text = "MERIDIAN"
	t1.add_theme_font_override("font", UiFonts.variable("res://fonts/orbitron_variable.ttf", 900, 9))
	t1.add_theme_font_size_override("font_size", 84)
	t1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t1.add_theme_constant_override("shadow_offset_y", 3)
	titles.add_child(t1)
	var t2 := Label.new()
	t2.text = "FRACTURE"
	t2.add_theme_font_override("font", UiFonts.variable("res://fonts/orbitron_variable.ttf", 500, 26))
	t2.add_theme_font_size_override("font_size", 40)
	t2.add_theme_color_override("font_color", skin.accent)
	titles.add_child(t2)
	row.add_child(titles)
	box.add_child(row)
	var tag := Label.new()
	tag.theme_type_variation = &"DimLabel"
	tag.text = "REAL-TIME STRATEGY  //  2086  //  EIGHT POWERS, ONE NETWORK"
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_constant_override("outline_size", 0)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0.0, 14.0)
	box.add_child(sp)
	box.add_child(tag)

func _build_menu() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(104.0, 470.0)
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var line := ColorRect.new()
	line.color = skin.accent
	line.custom_minimum_size = Vector2(3.0, 0.0)
	line.position = Vector2(92.0, 470.0)
	line.size = Vector2(3.0, 398.0)
	add_child(line)
	var entries: Array = [["SKIRMISH", "skirmish"], ["LAN MULTIPLAYER", "lan"], ["REPLAYS", "replays"], ["OPTIONS", "options"], ["CREDITS", "credits"], ["QUIT", "quit"]]
	for e in entries:
		var b := Button.new()
		b.theme_type_variation = &"HeroButton"
		b.text = String(e[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(420.0, 54.0)
		b.focus_mode = Control.FOCUS_NONE
		var dest: String = e[1]
		b.pressed.connect(func() -> void: navigate.emit(dest))
		v.add_child(b)

func _build_featured() -> void:
	var f: Dictionary = DemoData.faction("def" if faction != "def" else "pd")
	var fskin: UiSkin = UiSkin.for_faction(f["code"])
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(520.0, 0.0)
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -72.0
	p.offset_bottom = -84.0
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var em := UiEmblemView.new(84.0)
	em.code = f["code"]
	em.color = fskin.accent
	h.add_child(em)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var k := Label.new()
	k.theme_type_variation = &"HeaderLabel"
	k.text = "FEATURED POWER"
	v.add_child(k)
	var n := Label.new()
	n.text = String(f["name"]).to_upper()
	n.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.HEAD))
	n.add_theme_font_size_override("font_size", 17)
	n.add_theme_color_override("font_color", fskin.accent)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	var m := Label.new()
	m.text = "\"%s\"" % f["motto"]
	m.add_theme_color_override("font_color", UiPalette.TEXT)
	m.add_theme_font_size_override("font_size", 17)
	v.add_child(m)
	var d := Label.new()
	d.text = String(f["identity"])
	d.theme_type_variation = &"DimLabel"
	d.add_theme_font_size_override("font_size", 14)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	for r in (f["rosters"] as Array).slice(1):
		var c := Label.new()
		c.text = " %s " % String(r["name"]).to_upper()
		c.theme_type_variation = &"NumLabel"
		c.add_theme_font_size_override("font_size", 12)
		c.add_theme_color_override("font_color", fskin.accent2)
		chips.add_child(c)
	v.add_child(chips)

func _build_chrome() -> void:
	var top := PanelContainer.new()
	top.theme_type_variation = &"InsetPanel"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_right = -48.0
	top.offset_top = 36.0
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	for spec in [["LAN", "3 GAMES FOUND", UiPalette.OK], ["PROFILE", "COMMANDER", UiPalette.TEXT], ["DATA", "HASH 9F3A-C21E", UiPalette.TEXT_DIM]]:
		var l := Label.new()
		l.theme_type_variation = &"NumLabel"
		l.add_theme_font_size_override("font_size", 13)
		l.text = "%s  %s" % [spec[0], spec[1]]
		l.add_theme_color_override("font_color", spec[2])
		hb.add_child(l)
	top.add_child(hb)
	add_child(top)
	var foot := Label.new()
	foot.theme_type_variation = &"DimLabel"
	foot.text = "v0.1.0 UI SPIKE   //   GODOT %s   //   %s / %s" % [Engine.get_version_info()["string"].split(" ")[0], RenderingServer.get_current_rendering_method().to_upper(), RenderingServer.get_current_rendering_driver_name().to_upper()]
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	foot.offset_left = 104.0
	foot.offset_bottom = -76.0
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(foot)
