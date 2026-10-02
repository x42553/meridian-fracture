class_name UiCooldownSweep
extends Control
## Clockwise "clock wipe" over a rectangle: the not-yet-finished part is shaded, a bright edge marks the
## current angle. Three interchangeable back-ends so the benchmark can compare them:
##   SHADER            one canvas_item shader, progress is a uniform -> zero per-frame GDScript geometry
##   TEXTURE_PROGRESS  built-in TextureProgressBar in radial mode (C++), only `value` changes per frame
##   POLYGON           GDScript builds a fan polygon each frame (needs a canvas redraw every frame)

enum Backend { SHADER, TEXTURE_PROGRESS, POLYGON }

const SHADE := Color(0.0, 0.0, 0.0, 0.62)
const EDGE := Color(1.0, 1.0, 1.0, 0.9)

static var _shader: Shader
static var _solid: ImageTexture

var backend: Backend = Backend.SHADER
var progress: float = 0.0:
	set = set_progress
var _mat: ShaderMaterial
var _bar: TextureProgressBar

func _init(b: Backend = Backend.SHADER) -> void:
	backend = b
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	match backend:
		Backend.SHADER:
			if _shader == null:
				_shader = Shader.new()
				_shader.code = _SHADER_CODE
			_mat = ShaderMaterial.new()
			_mat.shader = _shader
			material = _mat
		Backend.TEXTURE_PROGRESS:
			if _solid == null:
				var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
				img.fill(Color.WHITE)
				_solid = ImageTexture.create_from_image(img)
			_bar = TextureProgressBar.new()
			_bar.texture_progress = _solid
			_bar.tint_progress = SHADE
			_bar.fill_mode = TextureProgressBar.FILL_COUNTER_CLOCKWISE
			_bar.nine_patch_stretch = true
			_bar.max_value = 100.0
			_bar.value = 100.0
			_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(_bar)

func set_progress(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if is_equal_approx(v, progress) and is_node_ready():
		return
	progress = v
	match backend:
		Backend.SHADER:
			if _mat != null:
				_mat.set_shader_parameter("progress", v)
		Backend.TEXTURE_PROGRESS:
			if _bar != null:
				_bar.value = (1.0 - v) * 100.0
		Backend.POLYGON:
			queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _mat != null:
		_mat.set_shader_parameter("rect_size", size)
		queue_redraw()

func _draw() -> void:
	match backend:
		Backend.SHADER:
			draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		Backend.POLYGON:
			if progress >= 1.0:
				return
			var r := Rect2(Vector2.ZERO, size)
			var poly: PackedVector2Array = UiDraw.rect_sector(r, progress, 1.0)
			if poly.size() >= 3:
				draw_colored_polygon(poly, SHADE)
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
