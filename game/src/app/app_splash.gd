class_name AppSplash
extends UiScreen
## Boot splash shown while `AppBoot` loads (ui.md 5.2.1). Placeholder-quality but final-look: dark backdrop with a faint
## grid and an accent glow, shield emblem, wide-tracked wordmark, tagline, a chamfered progress bar and a status line.
## `UiScreenSplash` (UI-06a) replaces it: `AppScreens.make(&"splash")` prefers that class when the project has it and
## `AppBoot` only calls `set_status` / `set_progress` if they exist.

const WORD_SIZE: int = 96
const SUB_SIZE: int = 40
const BAR_W: float = 620.0
const BAR_H: float = 10.0

var _status: Label
var _pct: Label
var _bar: Control
var _shown: float = 0.0
var _target: float = 0.0
var _time: float = 0.0
var _emblem: Control
var _glow: TextureRect


func _init() -> void:
	super._init()
	screen_id = &"splash"
	handles_escape = false


func enter(params: Dictionary) -> void:
	_build()
	if params.has("status"):
		set_status(str(params["status"]))
	if params.has("progress"):
		_target = clampf(str(params["progress"]).to_float(), 0.0, 1.0)
		_shown = _target
		_pct.text = "%d%%" % roundi(_shown * 100.0)
	set_process(true)
	modulate.a = 0.0
	UiMotion.fade(self, self, 1.0, 0.35)


func default_focus() -> Control:
	return null


## Text of the status line ("Loading game data").
func set_status(text: String) -> void:
	if _status != null:
		_status.text = text.to_upper()


## Progress 0..1 (the displayed bar eases toward it).
func set_progress(value: float) -> void:
	_target = clampf(value, 0.0, 1.0)


func progress_shown() -> float:
	return _shown


func _accent() -> Color:
	return get_theme_color(&"accent", UiTheme.ACCENT_TYPE)


func _build() -> void:
	var accent: Color = _accent()
	var back: ColorRect = ColorRect.new()
	back.color = UiPalette.BG_DEEP
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	UiLayerRoot.fill(back)
	add_child(_make_glow(accent))
	add_child(_make_grid())
	add_child(UiVignette.new(0.85, 0.09, 0.0, 0.03, accent))
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.offset_top = -170.0
	# wordmark row: emblem + two lines
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 34)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_emblem = Emblem.new()
	_emblem.custom_minimum_size = Vector2(150.0, 176.0)
	row.add_child(_emblem)
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	words.add_child(_word("MERIDIAN", WORD_SIZE, 900, 8, UiPalette.TEXT))
	words.add_child(_word("FRACTURE", SUB_SIZE, 500, 34, accent))
	var rule: Rule = Rule.new()
	rule.custom_minimum_size = Vector2(0.0, 30.0)
	column.add_child(rule)
	var tag: Label = Label.new()
	tag.text = "REAL-TIME STRATEGY   //   2086   //   EIGHT POWERS, ONE NETWORK"
	tag.theme_type_variation = &"MuteLabel"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_constant_override("outline_size", 0)
	tag.custom_minimum_size = Vector2(0.0, 24.0)
	column.add_child(tag)
	# progress block
	var block: VBoxContainer = VBoxContainer.new()
	block.add_theme_constant_override("separation", 10)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)
	block.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	block.grow_horizontal = Control.GROW_DIRECTION_BOTH
	block.grow_vertical = Control.GROW_DIRECTION_BEGIN
	block.offset_bottom = -132.0
	block.custom_minimum_size = Vector2(BAR_W, 0.0)
	var head: HBoxContainer = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(head)
	_status = Label.new()
	_status.theme_type_variation = &"HeaderLabel"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text = "STARTING"
	head.add_child(_status)
	_pct = Label.new()
	_pct.theme_type_variation = &"CaptionLabel"
	_pct.text = "0%"
	head.add_child(_pct)
	_bar = Bar.new()
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	(_bar as Bar).owner_splash = self
	block.add_child(_bar)
	# footer line
	var foot: Label = Label.new()
	foot.theme_type_variation = &"CaptionLabel"
	foot.text = "v%s // %s // %s" % [AppInfo.version(), AppInfo.engine_string().to_upper(),
		RenderingServer.get_current_rendering_method().to_upper()]
	foot.add_theme_color_override("font_color", UiPalette.TEXT_MUTE)
	add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 44.0
	foot.offset_top = -52.0
	var legal: Label = Label.new()
	legal.theme_type_variation = &"CaptionLabel"
	legal.text = "BUILD %s" % AppInfo.build_id().to_upper()
	legal.add_theme_color_override("font_color", UiPalette.TEXT_MUTE)
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(legal)
	legal.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	legal.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legal.offset_right = -44.0
	legal.offset_top = -52.0


func _word(text: String, font_px: int, weight: int, spacing: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	var fv: FontVariation = FontVariation.new()
	fv.base_font = load(UiFonts.PATH_HEAD) as Font
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing
	fv.fallbacks = [UiFonts.get_font(UiFonts.Role.HEAD)]
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(col, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_glow(accent: Color) -> TextureRect:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(accent, 0.30))
	grad.set_color(1, Color(accent, 0.0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512
	_glow = TextureRect.new()
	_glow.texture = tex
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_glow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_glow.grow_vertical = Control.GROW_DIRECTION_BOTH
	_glow.offset_left = -900.0
	_glow.offset_right = 900.0
	_glow.offset_top = -640.0
	_glow.offset_bottom = 380.0
	return _glow


func _make_grid() -> Control:
	var g: Grid = Grid.new()
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return g


func _process(delta: float) -> void:
	_time += delta
	if absf(_target - _shown) > 0.0005:
		_shown = move_toward(_shown, _target, maxf(delta * 1.4, (_target - _shown) * delta * 6.0))
		if _pct != null:
			_pct.text = "%d%%" % roundi(_shown * 100.0)
	if _bar != null:
		_bar.queue_redraw()


## The shield-and-star emblem (vector, crisp at any scale).
class Emblem extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var accent: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var c: Vector2 = size * 0.5
		var s: float = minf(size.x * 0.5, size.y * 0.44)
		var shield: PackedVector2Array = PackedVector2Array([c + Vector2(-s, -s * 0.72), c + Vector2(0.0, -s * 1.0),
			c + Vector2(s, -s * 0.72), c + Vector2(s, s * 0.32), c + Vector2(0.0, s * 1.0), c + Vector2(-s, s * 0.32)])
		draw_colored_polygon(shield, Color(accent, 0.12))
		var closed: PackedVector2Array = shield.duplicate()
		closed.append(shield[0])
		draw_polyline(closed, accent, 3.0, true)
		var inner: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in shield:
			inner.append(c + (p - c) * 0.82)
		inner.append(inner[0])
		draw_polyline(inner, Color(accent, 0.35), 1.5, true)
		var star: PackedVector2Array = PackedVector2Array()
		for i: int in 10:
			var r: float = s * (0.46 if i % 2 == 0 else 0.19)
			var a: float = -PI * 0.5 + float(i) * PI / 5.0
			star.append(c + Vector2(cos(a), sin(a)) * r + Vector2(0.0, s * 0.02))
		draw_colored_polygon(star, accent)


## Short chamfered accent rule under the wordmark.
class Rule extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var accent: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var y: float = size.y * 0.5
		var w: float = minf(size.x, 720.0)
		var x0: float = (size.x - w) * 0.5
		var cols: PackedColorArray = PackedColorArray([Color(accent, 0.0), Color(accent, 0.9), Color(accent, 0.9), Color(accent, 0.0)])
		var pts: PackedVector2Array = PackedVector2Array([Vector2(x0, y), Vector2(x0 + w * 0.3, y), Vector2(x0 + w * 0.7, y), Vector2(x0 + w, y)])
		draw_polyline_colors(pts, cols, 2.0)
		draw_rect(Rect2(Vector2(size.x * 0.5 - 5.0, y - 5.0), Vector2(10.0, 10.0)), Color(accent, 1.0))


## Faint blueprint grid with brighter major lines and HUD corner brackets.
class Grid extends Control:
	const STEP: float = 48.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var col: Color = Color(UiPalette.LINE_DIM, 0.32)
		var strong: Color = Color(UiPalette.LINE_DIM, 0.6)
		var x: float = 0.0
		var i: int = 0
		while x <= size.x:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), strong if i % 4 == 0 else col, 1.0)
			x += STEP
			i += 1
		var y: float = 0.0
		i = 0
		while y <= size.y:
			draw_line(Vector2(0.0, y), Vector2(size.x, y), strong if i % 4 == 0 else col, 1.0)
			y += STEP
			i += 1
		var accent: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var inset: Vector2 = Vector2(48.0, size.y * 0.115)
		var arm: float = 44.0
		for corner: Vector2 in [inset, Vector2(size.x - inset.x, inset.y), Vector2(inset.x, size.y - inset.y), size - inset]:
			var sx: float = 1.0 if corner.x < size.x * 0.5 else -1.0
			var sy: float = 1.0 if corner.y < size.y * 0.5 else -1.0
			draw_polyline(PackedVector2Array([corner + Vector2(arm * sx, 0.0), corner, corner + Vector2(0.0, arm * sy)]), Color(accent, 0.55), 2.0)


## Chamfered progress bar with a moving highlight.
class Bar extends Control:
	var owner_splash: AppSplash = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var accent: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var cut: float = size.y * 0.5
		var track: PackedVector2Array = UiDraw.chamfer_points(Rect2(Vector2.ZERO, size), Vector4(cut, 0.0, cut, 0.0))
		draw_colored_polygon(track, Color(UiPalette.BG_CONTROL, 0.9))
		var frac: float = owner_splash.progress_shown() if owner_splash != null else 0.0
		var w: float = size.x * frac
		if w > 2.0:
			var fill: PackedVector2Array = UiDraw.chamfer_points(Rect2(Vector2.ZERO, Vector2(w, size.y)), Vector4(cut, 0.0, minf(cut, w * 0.5), 0.0))
			var cols: PackedColorArray = PackedColorArray()
			for p: Vector2 in fill:
				cols.append(accent.lightened(0.25) if p.y < size.y * 0.5 else accent.darkened(0.35))
			var drawable: bool = not Geometry2D.triangulate_polygon(fill).is_empty()  # a bar shorter than its own chamfer is degenerate (engine error otherwise)
			if drawable:
				draw_polygon(fill, cols)
			if drawable and not UiMotion.reduce_motion:
				var t: float = fmod(float(Time.get_ticks_msec()) * 0.0009, 1.6) - 0.3
				var hx: float = t * w
				var hl: PackedVector2Array = PackedVector2Array([Vector2(hx, 0.0), Vector2(hx + 46.0, 0.0),
					Vector2(hx + 30.0, size.y), Vector2(hx - 16.0, size.y)])
				var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(hl, fill)
				for poly: PackedVector2Array in clipped:
					if poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty():  # a sliver (highlight edge on the fill edge) fails to triangulate: an engine error otherwise
						draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, 0.22))
		var outline: PackedVector2Array = track.duplicate()
		outline.append(track[0])
		draw_polyline(outline, UiPalette.LINE, 1.0, true)
