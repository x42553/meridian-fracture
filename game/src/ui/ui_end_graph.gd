class_name UiEndGraph
extends Control
## The line graph of the end screen (ui.md 5.16.4, Graphs tab): one line per player in the team colour, a pip shape at the line end
## (circle, square, triangle, diamond by pid: the second channel of ui.md 5.19.3, so lines stay tellable in every colour mode), x = time,
## y = the chosen metric. Data: `UiMatchStats.series` (`{pid: {metric: PackedInt32Array}}`, one sample per `sample_ticks`).

const PAD_L: float = 64.0
const PAD_R: float = 40.0
const PAD_T: float = 16.0
const PAD_B: float = 34.0

var series: Dictionary = {}
var metric: String = "harvested":
	set(v):
		metric = v
		queue_redraw()
## pid -> Color (team colours).
var colors: Dictionary = {}
var sample_ticks: int = UiMatchStats.SAMPLE_TICKS


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(480.0, 260.0)


func set_data(p_series: Dictionary, p_colors: Dictionary) -> void:
	series = p_series
	colors = p_colors
	queue_redraw()


## Largest value of the metric over all players (>= 1).
func max_value() -> int:
	var m: int = 1
	for pid: Variant in series:
		for v: int in (series[pid] as Dictionary).get(metric, PackedInt32Array()) as PackedInt32Array:
			m = maxi(m, v)
	return m


func _draw() -> void:
	var plot: Rect2 = Rect2(PAD_L, PAD_T, size.x - PAD_L - PAD_R, size.y - PAD_T - PAD_B)
	var font: Font = get_theme_default_font()
	var fs: int = 13
	draw_rect(plot, UiPalette.BG_DEEP)
	var top: int = _nice_max(max_value())
	for i: int in 5:
		var y: float = plot.position.y + plot.size.y * (1.0 - float(i) / 4.0)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), UiPalette.LINE_DIM if i > 0 else UiPalette.LINE, 1.0)
		var label: String = UiFormatLite.credits(top * i / 4)
		draw_string(font, Vector2(4.0, y + 4.0), label, HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 10.0, fs, UiPalette.TEXT_MUTE)
	var samples: int = 0
	for pid: Variant in series:
		samples = maxi(samples, ((series[pid] as Dictionary).get(metric, PackedInt32Array()) as PackedInt32Array).size())
	if samples < 2:
		draw_string(font, plot.get_center() - Vector2(90.0, 0.0), "Not enough data yet", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 16, UiPalette.TEXT_MUTE)
		return
	var last_s: int = (samples - 1) * sample_ticks * SimConfig.TICK_MS / 1000
	for i2: int in 5:
		var x: float = plot.position.x + plot.size.x * float(i2) / 4.0
		draw_string(font, Vector2(x - 24.0, plot.end.y + 20.0), UiFormatLite.clock(last_s * i2 / 4), HORIZONTAL_ALIGNMENT_CENTER, 48.0, fs, UiPalette.TEXT_MUTE)
	var pids: Array = series.keys()
	pids.sort()
	for pid2: Variant in pids:
		var data: PackedInt32Array = (series[pid2] as Dictionary).get(metric, PackedInt32Array()) as PackedInt32Array
		var col: Color = colors.get(pid2, UiPalette.TEXT) as Color
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in data.size():
			pts.append(Vector2(plot.position.x + plot.size.x * float(k) / float(samples - 1),
				plot.end.y - plot.size.y * float(data[k]) / float(top)))
		if pts.size() >= 2:
			draw_polyline(pts, col, 2.5, true)
		if not pts.is_empty():
			draw_pip(pts[pts.size() - 1], int(pid2), col)


## The pip of a player at the line end: 0 circle, 1 square, 2 triangle, 3 diamond (repeating).
func draw_pip(at: Vector2, pid: int, col: Color) -> void:
	var r: float = 6.0
	match pid % 4:
		0:
			draw_circle(at, r, col)
		1:
			draw_rect(Rect2(at - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), col)
		2:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -r - 1.0), at + Vector2(r + 1.0, r), at + Vector2(-r - 1.0, r)]), col)
		_:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -r - 2.0), at + Vector2(r + 2.0, 0.0), at + Vector2(0.0, r + 2.0), at + Vector2(-r - 2.0, 0.0)]), col)


## Rounds a maximum up to 1, 2, 5 x 10^n so the grid labels stay readable.
static func _nice_max(v: int) -> int:
	var mag: int = 1
	while mag * 10 <= v:
		mag *= 10
	for m: int in [1, 2, 5, 10]:
		if m * mag >= v:
			return m * mag
	return 10 * mag
