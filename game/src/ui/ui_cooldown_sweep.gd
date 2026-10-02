class_name UiCooldownSweep
extends Control
## Clockwise clock wipe over a rectangle (ui.md 5.10.7): the not-yet-finished part is shaded, a bright edge marks the
## current angle. Default back-end is one canvas_item shader with a `progress` uniform (0.11 ms for 100 sweeps
## changing every frame, spike 7); the POLYGON back-end (GDScript fan) is the fallback for renderers where the
## shader path is unavailable. Progress semantics: 0 = just started (all shaded), 1 = finished (nothing shaded).

enum Backend { SHADER, POLYGON }

const SHADE := Color(0.0, 0.0, 0.0, 0.62)
const EDGE := Color(1.0, 1.0, 1.0, 0.9)

static var _shader: Shader = null


static func release_statics() -> void:
	_shader = null

var backend: int = Backend.SHADER
var progress: float = 0.0:
	set = set_progress
var shade_color: Color = SHADE:
	set(v):
		shade_color = v
		if _mat != null:
			_mat.set_shader_parameter("shade", v)
		queue_redraw()
var _mat: ShaderMaterial = null


func _init(b: int = Backend.SHADER) -> void:
	backend = b
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if backend == Backend.SHADER:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = _SHADER_CODE
		_mat = ShaderMaterial.new()
		_mat.shader = _shader
		material = _mat


func set_progress(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if is_equal_approx(v, progress) and is_node_ready():
		return
	progress = v
	if backend == Backend.SHADER:
		if _mat != null:
			_mat.set_shader_parameter("progress", v)
	else:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _mat != null:
		_mat.set_shader_parameter("rect_size", size)
		queue_redraw()


func _draw() -> void:
	if backend == Backend.SHADER:
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		return
	if progress >= 1.0:
		return
	var r := Rect2(Vector2.ZERO, size)
	var poly: PackedVector2Array = UiDraw.rect_sector(r, progress, 1.0)
	if poly.size() >= 3:
		draw_colored_polygon(poly, shade_color)
	if progress > 0.0:
		draw_line(r.get_center(), UiDraw.rect_boundary(r, progress * TAU), EDGE, 1.5, true)


const _SHADER_CODE := """
shader_type canvas_item;
uniform float progress = 0.0;
uniform vec2 rect_size = vec2(96.0, 64.0);
uniform vec4 shade : source_color = vec4(0.0, 0.0, 0.0, 0.62);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_size;
	float a = atan(p.x, -p.y);
	if (a < 0.0) { a += TAU; }
	float t = a / TAU;
	float dark = step(progress, t);
	float px = abs(t - progress) * TAU * length(p);
	float ed = (1.0 - smoothstep(0.6, 1.6, px)) * step(0.001, progress) * step(progress, 0.999);
	vec4 c = vec4(shade.rgb, shade.a * dark);
	COLOR = mix(c, edge_color, ed * edge_color.a);
}
"""
