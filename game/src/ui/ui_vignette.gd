class_name UiVignette
extends ColorRect
## Full-screen overlay in one canvas shader (ui.md 2.3): vignette, optional letterbox bars, left text scrim and faint scanlines
## (spike 11). One quad; `MOUSE_FILTER_IGNORE`. `lite` (gl_compatibility / Low preset) and `UiMotion.reduce_motion` drop the
## scanlines and the time term; `set_time` is only needed while scanlines animate.

const CODE: String = """
shader_type canvas_item;
uniform float strength = 0.6;
uniform float bars = 0.0;
uniform float left_scrim = 0.0;
uniform float scan = 0.0;
uniform float time_s = 0.0;
uniform vec4 tint : source_color = vec4(0.95, 0.5, 0.2, 1.0);
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float v = smoothstep(0.35, 1.4, length(uv * vec2(0.85, 1.05)));
	float bar = bars > 0.0 ? smoothstep(bars, 0.0, min(UV.y, 1.0 - UV.y)) : 0.0;
	float left = smoothstep(0.62, 0.0, UV.x) * left_scrim;
	float s = scan * 0.5 * sin(UV.y * 1400.0 + time_s * 4.0);
	float a = clamp(v * strength + bar + left + s, 0.0, 1.0);
	vec3 c = mix(vec3(0.0, 0.01, 0.02), tint.rgb * 0.08, v * 0.3);
	COLOR = vec4(c, a);
}
"""

static var _shader: Shader = null


static func release_statics() -> void:
	_shader = null

var _mat: ShaderMaterial
var _scan: float = 0.0


## `strength` vignette darkness, `bars` letterbox height (fraction of the screen, 0 = off), `left_scrim` text scrim
## strength, `scan` scanline strength, `tint` the faction tint of the dark corners.
func _init(strength: float = 0.6, bars: float = 0.0, left_scrim: float = 0.0, scan: float = 0.0, tint: Color = Color(0.95, 0.5, 0.2)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("bars", bars)
	_mat.set_shader_parameter("left_scrim", left_scrim)
	_scan = scan
	_mat.set_shader_parameter("scan", 0.0 if UiMotion.reduce_motion else scan)
	_mat.set_shader_parameter("tint", tint)
	material = _mat


## Scanline animation clock (skipped under reduce-motion).
func set_time(t: float) -> void:
	if _scan > 0.0 and not UiMotion.reduce_motion:
		_mat.set_shader_parameter("time_s", t)


## Removes the scanlines (lite mode / reduce motion).
func set_lite(on: bool) -> void:
	_mat.set_shader_parameter("scan", 0.0 if on or UiMotion.reduce_motion else _scan)
