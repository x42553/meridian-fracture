class_name UiScreenFonts
extends Control
## Font specimen: candidate OFL fonts at 12-18 px with real HUD strings on the real panel colours.

const SAMPLES: Array[String] = [
	"GUARDIAN TANK   $1,200   00:45   x3",
	"Rifle Squad / Javelin Team / Combat Medic  0123456789",
]
const SIZES: Array[int] = [12, 14, 16, 18]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiPalette.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.offset_left = 10
	grid.offset_top = 10
	grid.offset_right = -10
	grid.offset_bottom = -10
	add_child(grid)
	var fonts: Array = [
		["Rajdhani SemiBold  (BODY)", load("res://fonts/rajdhani_semibold.ttf")],
		["Rajdhani Bold  (BODY_BOLD)", load("res://fonts/rajdhani_bold.ttf")],
		["Orbitron wght 700  (HEAD)", UiFonts.variable("res://fonts/orbitron_variable.ttf", 700)],
		["Share Tech Mono  (NUM)", load("res://fonts/share_tech_mono.ttf")],
		["Orbitron weight axis  400 / 500 / 700 / 900", null],
	]
	for entry in fonts:
		var f: Font = entry[1]
		if f == null:
			grid.add_child(_weights_panel(entry[0]))
			continue
		grid.add_child(_panel(entry[0], f))
		print("FONT ", entry[0], " w(", SAMPLES[0].substr(0, 14), "@16)=", snapped(f.get_string_size(SAMPLES[0].substr(0, 14), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, 0.1),
			" ascent16=", f.get_ascent(16), " h16=", f.get_height(16))
	var f700: Font = UiFonts.variable("res://fonts/orbitron_variable.ttf", 700)
	var f400: Font = UiFonts.variable("res://fonts/orbitron_variable.ttf", 400)
	var fstr := FontVariation.new()
	fstr.base_font = load("res://fonts/orbitron_variable.ttf")
	fstr.variation_opentype = {"wght": 900}
	print("VARFONT orbitron width MERIDIAN@32: w400=", f400.get_string_size("MERIDIAN", 0, -1, 32).x, " w700=", f700.get_string_size("MERIDIAN", 0, -1, 32).x,
		" str-key w900=", fstr.get_string_size("MERIDIAN", 0, -1, 32).x)

func _weights_panel(title: String) -> Control:
	var pc: PanelContainer = _panel(title, UiFonts.get_font(UiFonts.Role.BODY_BOLD)) as PanelContainer
	var v: VBoxContainer = pc.get_child(0)
	for c in v.get_children().slice(1):
		c.queue_free()
	for w in [400, 500, 700, 900]:
		var l := Label.new()
		l.text = "%d  MERIDIAN FRACTURE 0123456789" % w
		l.add_theme_font_override("font", UiFonts.variable("res://fonts/orbitron_variable.ttf", w))
		l.add_theme_font_size_override("font_size", 22)
		v.add_child(l)
		print("VARFONT wght=", w, " width@22=", UiFonts.variable("res://fonts/orbitron_variable.ttf", w).get_string_size("MERIDIAN FRACTURE 0123456789", 0, -1, 22).x)
	return pc

func _panel(title: String, f: Font) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.BG_PANEL
	sb.border_color = UiPalette.LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", f)
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color("#f07f2c"))
	v.add_child(t)
	for px in SIZES:
		for s in SAMPLES:
			var l := Label.new()
			l.text = "%d  %s" % [px, s]
			l.add_theme_font_override("font", f)
			l.add_theme_font_size_override("font_size", px)
			l.add_theme_color_override("font_color", UiPalette.TEXT if px % 4 == 0 else UiPalette.TEXT_DIM)
			v.add_child(l)
	return pc
