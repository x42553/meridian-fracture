class_name UiLayout
extends RefCounted
## Scale factor and size-class maths (ui.md 5.4). `Window.size` is in pixels even on Retina, so no screen-scale term.
## The project uses `display/window/stretch/mode = disabled` (the factor is applied through
## `Window.content_scale_factor`), so a screen under test is laid out in `logical_size(window_px, factor)`.

enum SizeClass { COMPACT = 0, REGULAR = 1, LARGE = 2 }

const COMPACT_BELOW: float = 800.0
const LARGE_FROM: float = 1300.0
const RESIZE_DEBOUNCE_S: float = 0.1

static var _pending: bool = false


## 5.4.1: `clamp(h/1080, 0.75, 2.0) * ui_scale`, then `min(_, h/540)` (logical height >= 540), then clamp 0.5 .. 4.0.
static func factor(window_px: Vector2i, ui_scale: float) -> float:
	var h: float = float(window_px.y)
	var f: float = clampf(h / float(UiMetrics.DESIGN_H), 0.75, 2.0) * ui_scale
	f = minf(f, h / 540.0)
	return clampf(f, 0.5, 4.0)


## Logical size of a window under a factor.
static func logical_size(window_px: Vector2i, f: float) -> Vector2:
	return Vector2(window_px) / f


## Sets `Window.content_scale_factor` and `Window.min_size`; returns the factor.
static func apply(window: Window, ui_scale: float) -> float:
	var f: float = factor(window.size, ui_scale)
	window.content_scale_factor = f
	window.min_size = UiMetrics.MIN_WINDOW
	return f


## Re-applies the scale after window resizes, debounced 100 ms (a live drag-resize does not re-layout every frame).
## `ui_scale_getter` is `func() -> float` (settings `video/ui_scale` / 100). Call once at boot.
static func watch(window: Window, ui_scale_getter: Callable) -> void:
	window.size_changed.connect(func() -> void:
		if _pending:
			return
		_pending = true
		var tree: SceneTree = window.get_tree()
		if tree == null:
			_pending = false
			return
		await tree.create_timer(RESIZE_DEBOUNCE_S).timeout
		_pending = false
		if is_instance_valid(window):
			apply(window, float(ui_scale_getter.call())))


static func size_class(logical_h: float) -> int:
	if logical_h < COMPACT_BELOW:
		return SizeClass.COMPACT
	if logical_h >= LARGE_FROM:
		return SizeClass.LARGE
	return SizeClass.REGULAR


## Minimap side: `clamp((logical_h - 420) * 0.55, 180, 300)`.
static func minimap_size(logical_h: float) -> float:
	return clampf((logical_h - 420.0) * 0.55, float(UiMetrics.MINIMAP_MIN), float(UiMetrics.MINIMAP_MAX))


## Width of the bottom selection panel: `clamp(playfield_w - 40, 600, 900)` (1000 max in LARGE).
static func bottom_panel_width(playfield_w: float, klass: int = SizeClass.REGULAR) -> float:
	var top: float = float(UiMetrics.BOTTOM_W_MAX_LARGE if klass == SizeClass.LARGE else UiMetrics.BOTTOM_W_MAX)
	return clampf(playfield_w - 40.0, float(UiMetrics.BOTTOM_W_MIN), top)


## Playfield width = logical width minus the sidebar.
static func playfield_width(logical_w: float) -> float:
	return logical_w - float(UiMetrics.SIDEBAR_W)


## Width of the centred content column of menus (<= 1920, side gutters show the vignette on ultrawide).
static func content_column(logical_w: float) -> float:
	return minf(logical_w, 1920.0)


## Number of log lines by size class (ui.md 5.4.2).
static func log_lines(klass: int) -> int:
	if klass == SizeClass.COMPACT:
		return 4
	return 10 if klass == SizeClass.LARGE else UiMetrics.LOG_MAX
