class_name UiReplayBar
extends PanelContainer
## The replay transport of the observer HUD (ui.md 5.16.3, task REP2): play / pause, the speed chips 1/4 1/2 1 2 4 8 MAX, a seek bar
## (drag or click -> `seek_requested`, tick marks every 30 s, the part up to `verified_through` filled, markers for the recorded
## events and the first divergence), the current and the total time, a spinner with the progress while a seek runs, jump-to-event
## buttons, the "Verified through mm:ss" badge and the divergence banner. A dumb widget: the screen copies the state of the
## `AppReplaySession` into it with `set_state` and wires the signals back. Never touches the sim.

signal pause_toggled()
signal speed_chosen(multiplier: float)
signal seek_requested(tick: int)
signal seek_relative(seconds: int)
signal event_jump(direction: int)

## Speed chips: label and multiplier (0 = MAX, as `NetReplayPlayer.set_speed`).
const SPEEDS: Array[Dictionary] = [
	{"label": "1/4", "value": 0.25}, {"label": "1/2", "value": 0.5}, {"label": "1x", "value": 1.0}, {"label": "2x", "value": 2.0},
	{"label": "4x", "value": 4.0}, {"label": "8x", "value": 8.0}, {"label": "MAX", "value": 0.0},
]
const MARK_EVERY_TICKS: int = 600
const SKIP_SECONDS: int = 10

var tick: int = 0
var end_tick: int = 1
var speed: float = 1.0
var paused: bool = false
var finished: bool = false
var seeking: bool = false
var seek_pct: int = 0
var verified_through: int = 0
var diverged_tick: int = -1

var _seek: SeekBar = null
var _cur: Label = null
var _total: Label = null
var _play: Button = null
var _chips: Array[Button] = []
var _badge: Label = null
var _spinner: Label = null
var _banner: Label = null
var _prev_ev: Button = null
var _next_ev: Button = null
var _marks: Array[Dictionary] = []


func _init() -> void:
	theme_type_variation = &"SidebarPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var m: MarginContainer = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	add_child(m)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	m.add_child(col)
	_banner = UiScreenKit.label("", &"DangerLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.visible = false
	col.add_child(_banner)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	_cur = UiScreenKit.label("0:00", &"NumLabel")
	_cur.custom_minimum_size = Vector2(64.0, 0.0)
	_cur.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_cur)
	_seek = SeekBar.new()
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.seek_requested.connect(func(t: int) -> void: seek_requested.emit(t))
	top.add_child(_seek)
	_total = UiScreenKit.label("0:00", &"NumLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	_total.custom_minimum_size = Vector2(64.0, 0.0)
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_total)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	_play = UiScreenKit.button("PAUSE", &"PrimaryButton", Vector2(96.0, 34.0))
	_play.pressed.connect(func() -> void: pause_toggled.emit())
	_play.tooltip_text = "Pause / resume (Space)"
	row.add_child(_play)
	var back: Button = UiScreenKit.button("-%ds" % SKIP_SECONDS, &"", Vector2(56.0, 34.0))
	back.pressed.connect(func() -> void: seek_relative.emit(-SKIP_SECONDS))
	back.tooltip_text = "Back 10 seconds (,)"
	row.add_child(back)
	var fwd: Button = UiScreenKit.button("+%ds" % SKIP_SECONDS, &"", Vector2(56.0, 34.0))
	fwd.pressed.connect(func() -> void: seek_relative.emit(SKIP_SECONDS))
	fwd.tooltip_text = "Forward 10 seconds (.)"
	row.add_child(fwd)
	row.add_child(VSeparator.new())
	for i: int in SPEEDS.size():
		var b: Button = UiScreenKit.button(str(SPEEDS[i]["label"]), &"", Vector2(46.0, 34.0))
		b.toggle_mode = true
		b.tooltip_text = "Playback speed ([ slower, ] faster)"
		var v: float = float(SPEEDS[i]["value"])
		b.pressed.connect(func() -> void: speed_chosen.emit(v))
		row.add_child(b)
		_chips.append(b)
	var sp: Control = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	_spinner = UiScreenKit.label("", &"WarnLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	_spinner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_spinner)
	_badge = UiScreenKit.label("", &"OkLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_badge)
	_prev_ev = UiScreenKit.button("< EVENT", &"", Vector2(86.0, 34.0))
	_prev_ev.pressed.connect(func() -> void: event_jump.emit(-1))
	_prev_ev.tooltip_text = "Jump to the previous event (B)"
	row.add_child(_prev_ev)
	_next_ev = UiScreenKit.button("EVENT >", &"", Vector2(86.0, 34.0))
	_next_ev.pressed.connect(func() -> void: event_jump.emit(1))
	_next_ev.tooltip_text = "Jump to the next event (N)"
	row.add_child(_next_ev)
	set_state(0, 1, 1.0, false, 0, -1, false, 0, false)


# ---- pure helpers (tested) ----------------------------------------------------------------------------------------

## "12:34" for a tick count.
static func clock(t: int) -> String:
	return UiFormatLite.clock(maxi(t, 0) * SimConfig.TICK_MS / 1000)


## Index into SPEEDS of a multiplier (0 = MAX is the last); the nearest chip for anything else.
static func speed_index(multiplier: float) -> int:
	if multiplier <= 0.0:
		return SPEEDS.size() - 1
	var best: int = 0
	var best_d: float = 1.0e9
	for i: int in SPEEDS.size() - 1:
		var d: float = absf(float(SPEEDS[i]["value"]) - multiplier)
		if d < best_d:
			best_d = d
			best = i
	return best


## The multiplier one chip up (`dir` 1) or down (-1), clamped to the ends.
static func step_speed(multiplier: float, dir: int) -> float:
	var i: int = clampi(speed_index(multiplier) + dir, 0, SPEEDS.size() - 1)
	return float(SPEEDS[i]["value"])


## The tick under pixel `x` of a bar `width` wide.
static func tick_at(x: float, width: float, end_tick_value: int) -> int:
	if width <= 0.0:
		return 0
	return clampi(roundi(clampf(x / width, 0.0, 1.0) * float(end_tick_value)), 0, end_tick_value)


## The tick-mark spacing (a multiple of 600) that keeps the marks at least `min_px` apart.
static func mark_step(end_tick_value: int, width: float, min_px: float = 9.0) -> int:
	var step: int = MARK_EVERY_TICKS
	while end_tick_value > 0 and width > 0.0 and float(end_tick_value) / float(step) * min_px > width and step < (1 << 24):
		step *= 2
	return step


## The next recorded mark after / before `t` (`dir` 1 / -1): its tick, or -1.
static func event_after(marks: Array[Dictionary], t: int, dir: int) -> int:
	var best: int = -1
	for mk: Dictionary in marks:
		var mt: int = int(mk["tick"])
		if dir > 0 and mt > t + 20 and (best < 0 or mt < best):
			best = mt
		elif dir < 0 and mt < t - 20 and mt > best:
			best = mt
	return best


# ---- state ------------------------------------------------------------------------------------------------------------

func set_state(p_tick: int, p_end: int, p_speed: float, p_paused: bool, p_verified: int, p_diverged: int, p_seeking: bool, p_seek_pct: int, p_finished: bool) -> void:
	tick = p_tick
	end_tick = maxi(p_end, 1)
	speed = p_speed
	paused = p_paused
	verified_through = p_verified
	diverged_tick = p_diverged
	seeking = p_seeking
	seek_pct = p_seek_pct
	finished = p_finished
	_cur.text = clock(tick)
	_total.text = clock(end_tick)
	_play.text = "REPLAY" if finished and tick >= end_tick else ("PLAY" if paused else "PAUSE")
	var idx: int = speed_index(speed)
	for i: int in _chips.size():
		_chips[i].set_pressed_no_signal(i == idx)
	_seek.set_state(tick, end_tick, verified_through, diverged_tick, seeking)
	_spinner.text = "SEEKING %d%%" % seek_pct if seeking else ""
	if diverged_tick >= 0:
		_badge.text = ""
		_banner.visible = true
		_banner.text = "Replay diverged at %s - recorded on a different build?" % clock(diverged_tick)
	else:
		_banner.visible = false
		_badge.text = "VERIFIED THROUGH %s" % clock(verified_through) if verified_through > 0 else ""
	_prev_ev.disabled = event_after(_marks, tick, -1) < 0
	_next_ev.disabled = event_after(_marks, tick, 1) < 0


func set_marks(marks: Array[Dictionary]) -> void:
	_marks = marks
	_seek.marks = marks
	_seek.queue_redraw()


func marks() -> Array[Dictionary]:
	return _marks


## The widgets, for tests.
func seek_bar() -> Control:
	return _seek


func play_button() -> Button:
	return _play


func speed_button(i: int) -> Button:
	return _chips[i]


func banner_text() -> String:
	return _banner.text if _banner.visible else ""


func badge_text() -> String:
	return _badge.text


func spinner_text() -> String:
	return _spinner.text


## The seek track.
class SeekBar extends Control:
	signal seek_requested(tick: int)

	var tick: int = 0
	var end_tick: int = 1
	var verified: int = 0
	var diverged: int = -1
	var seeking: bool = false
	var marks: Array[Dictionary] = []
	var _drag: bool = false
	var _drag_tick: int = 0
	var _hover_x: float = -1.0

	func _init() -> void:
		custom_minimum_size = Vector2(120.0, 30.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func set_state(t: int, e: int, v: int, d: int, s: bool) -> void:
		tick = t
		end_tick = maxi(e, 1)
		verified = v
		diverged = d
		seeking = s
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_tick = UiReplayBar.tick_at(mb.position.x, size.x, end_tick)
			elif _drag:
				_drag = false
				seek_requested.emit(_drag_tick)
			queue_redraw()
			accept_event()
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm != null:
			_hover_x = mm.position.x
			if _drag:
				_drag_tick = UiReplayBar.tick_at(mm.position.x, size.x, end_tick)
			tooltip_text = _mark_at(mm.position.x)
			queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			_hover_x = -1.0
			queue_redraw()

	## The text of the event marker within 6 px of `x` ("" = none).
	func _mark_at(x: float) -> String:
		for mk: Dictionary in marks:
			var mx: float = float(int(mk["tick"])) / float(end_tick) * size.x
			if absf(mx - x) <= 6.0:
				return "%s  %s" % [UiReplayBar.clock(int(mk["tick"])), str(mk["text"])]
		return ""

	func _draw() -> void:
		var acc: Color = get_theme_color(&"accent", UiTheme.ACCENT_TYPE)
		var w: float = size.x
		var cy: float = size.y * 0.5 + 2.0
		var track: Rect2 = Rect2(0.0, cy - 4.0, w, 8.0)
		draw_rect(track, Color(0.0, 0.0, 0.0, 0.55))
		var vx: float = float(clampi(verified, 0, end_tick)) / float(end_tick) * w
		draw_rect(Rect2(0.0, cy - 4.0, vx, 8.0), Color(acc, 0.30))
		var shown: int = _drag_tick if _drag else tick
		var px: float = float(clampi(shown, 0, end_tick)) / float(end_tick) * w
		draw_rect(Rect2(0.0, cy - 4.0, px, 8.0), Color(acc, 0.95))
		var step: int = UiReplayBar.mark_step(end_tick, w)
		var t: int = step
		while t < end_tick:
			var x: float = float(t) / float(end_tick) * w
			var major: bool = (t / step) % 2 == 0
			draw_rect(Rect2(x - 0.5, cy - (11.0 if major else 9.0), 1.0, 5.0 if major else 4.0), Color(1.0, 1.0, 1.0, 0.35))
			t += step
		for mk: Dictionary in marks:
			var mx: float = float(int(mk["tick"])) / float(end_tick) * w
			var c: Color = UiReplayBar.mark_color(str(mk["kind"]))
			var pts: PackedVector2Array = PackedVector2Array([Vector2(mx, cy - 15.0), Vector2(mx + 4.0, cy - 11.0), Vector2(mx, cy - 7.0), Vector2(mx - 4.0, cy - 11.0)])
			draw_colored_polygon(pts, c)
		if diverged >= 0:
			var dx: float = float(diverged) / float(end_tick) * w
			draw_colored_polygon(PackedVector2Array([Vector2(dx, cy + 5.0), Vector2(dx + 5.0, cy + 13.0), Vector2(dx - 5.0, cy + 13.0)]), UiPalette.semantic(&"danger"))
		draw_circle(Vector2(px, cy), 8.0, Color(0.0, 0.0, 0.0, 0.6))
		draw_circle(Vector2(px, cy), 6.0, UiPalette.TEXT if not seeking else UiPalette.semantic(&"warn"))
		draw_arc(Vector2(px, cy), 6.0, 0.0, TAU, 16, acc, 1.5, true)
		if _drag or (_hover_x >= 0.0 and not _drag):
			var hx: float = _hover_x if not _drag else px
			var ht: int = UiReplayBar.tick_at(hx, w, end_tick) if not _drag else _drag_tick
			var txt: String = UiReplayBar.clock(ht)
			var font: Font = UiFonts.get_font(UiFonts.Role.NUM)
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var tx: float = clampf(hx - tw * 0.5, 0.0, maxf(w - tw, 0.0))
			draw_rect(Rect2(tx - 4.0, 0.0, tw + 8.0, 15.0), Color(0.0, 0.0, 0.0, 0.7))
			draw_string(font, Vector2(tx, 12.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.TEXT)


## Marker colour of an event kind.
static func mark_color(kind: String) -> Color:
	match kind:
		"defeated":
			return UiPalette.semantic(&"danger")
		"resigned", "left":
			return UiPalette.semantic(&"warn")
		"chat":
			return Color("#7fb0e6")
	return UiPalette.TEXT_DIM
