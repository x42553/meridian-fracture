class_name UiVignette
extends ColorRect
## Full-screen post overlay in one canvas shader: vignette, optional letterbox bars, left-side text scrim and
## faint scanlines. mouse_filter IGNORE. Cheap (one quad); use to glue a HUD or menu onto the 3D scene.

const CODE := """
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

var _mat: ShaderMaterial

func _init(strength: float = 0.6, bars: float = 0.0, left_scrim: float = 0.0, scan: float = 0.0, tint: Color = Color(0.95, 0.5, 0.2)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("bars", bars)
	_mat.set_shader_parameter("left_scrim", left_scrim)
	_mat.set_shader_parameter("scan", scan)
	_mat.set_shader_parameter("tint", tint)
	material = _mat

func set_time(t: float) -> void:
	_mat.set_shader_parameter("time_s", t)
