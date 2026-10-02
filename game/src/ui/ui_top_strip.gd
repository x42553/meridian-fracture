class_name UiTopStrip
extends PanelContainer
## Top-left strip (ui.md 5.10.10): `mm:ss` game time (`h:mm:ss` past an hour), KILLS n / LOST n, optional SCORE n, a speed
## badge when the speed is not 100 %, PAUSED while paused and a latency dot in LAN. An InsetPanel that only touches its
## labels when a displayed value changes (once per game second at most).

var _time: Label = null
var _kills: Label = null
var _lost: Label = null
var _score: Label = null
var _ents: Label = null
var _speed: Label = null
var _pause: Label = null
var _dot: Control = null
var _latency_ms: int = -1


func _init() -> void:
	theme_type_variation = &"InsetPanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	add_child(hb)
	_time = _label(hb, UiPalette.TEXT)
	_time.text = "0:00"
	_kills = _label(hb, UiPalette.TEXT_DIM)
	_kills.text = "KILLS 0"
	_lost = _label(hb, UiPalette.TEXT_DIM)
	_lost.text = "LOST 0"
	_score = _label(hb, UiPalette.CREDITS)
	_score.visible = false
	_ents = _label(hb, UiPalette.TEXT_MUTE)
	_ents.visible = false
	_speed = _label(hb, UiPalette.WARN)
	_speed.visible = false
	_pause = _label(hb, UiPalette.WARN)
	_pause.text = "PAUSED"
	_pause.visible = false
	_dot = Control.new()
	_dot.custom_minimum_size = Vector2(12.0, 12.0)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.visible = false
	_dot.draw.connect(_draw_dot)
	hb.add_child(_dot)


func _label(parent: Control, col: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"NumLabel"
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## "m:ss" / "h:mm:ss" of `tick / 20` seconds.
static func format_time(tick: int) -> String:
	var s: int = maxi(tick, 0) / 20
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


func set_time(tick: int) -> void:
	var t: String = format_time(tick)
	if _time.text != t:
		_time.text = t


func set_stats(kills: int, lost: int) -> void:
	var k: String = "KILLS %d" % kills
	if _kills.text != k:
		_kills.text = k
	var l: String = "LOST %d" % lost
	if _lost.text != l:
		_lost.text = l


## Observer HUD: no kills / lost counters (they would be the viewer's, and there is none).
func set_observer(on: bool) -> void:
	_kills.visible = not on
	_lost.visible = not on


## Observer HUD: the live entity count of the whole match (a hint of how heavy the scene is); hidden until first set.
func set_entities(n: int) -> void:
	_ents.visible = true
	var txt: String = "ENTITIES %d" % n
	if _ents.text != txt:
		_ents.text = txt


## Replays: a free-form speed badge ("1/4x", "MAX"); "" hides it.
func set_speed_label(text: String) -> void:
	_speed.visible = text != ""
	_speed.text = text


func set_score(value: int, shown: bool) -> void:
	_score.visible = shown
	if shown:
		_score.text = "SCORE %s" % UiBuildItem.group_digits(value)


## Speed badge ("1.5x") only when `pct` != 100.
func set_speed(pct: int) -> void:
	_speed.visible = pct != 100
	if pct != 100:
		_speed.text = "%s x" % String.num(float(pct) / 100.0, 2).rstrip("0").rstrip(".")


func set_paused(paused: bool) -> void:
	_pause.visible = paused


## LAN latency dot: green < 60 ms, yellow < 150 ms, red otherwise; -1 hides it.
func set_latency(ms: int) -> void:
	if ms != _latency_ms:
		_latency_ms = ms
		_dot.visible = ms >= 0
		_dot.queue_redraw()


func latency_color() -> Color:
	if _latency_ms < 60:
		return UiPalette.OK
	if _latency_ms < 150:
		return UiPalette.WARN
	return UiPalette.DANGER


func _draw_dot() -> void:
	_dot.draw_circle(Vector2(6.0, 6.0), 5.0, latency_color())
