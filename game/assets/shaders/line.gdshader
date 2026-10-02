shader_type spatial;
// Ground-following ribbons of constant pixel width (render spec 5.10): order / rally lines, range rings, the build-radius ring.
// Mesh contract (ViewRibbon): VERTEX = point on the ground (world m), NORMAL = unit tangent, UV = (side -1..+1, distance m),
// UV2 = (style, width multiplier), COLOR = sRGB colour + opacity.
//   style 0 marching dashes (order lines)   1 solid   2 static long dashes (range rings)   3 static short dashes (min range)
//   4 static long dashes, slow march (build radius)
// The vertex stage offsets each vertex sideways by `side * width_px / 2` perpendicular to the PROJECTED tangent, so the stroke
// keeps its screen size at any zoom; a dark outline of `outline_px` on both sides keeps it readable on bright ground.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

#include "res://assets/shaders/view_common.gdshaderinc"

uniform float width_px = 4.0;
uniform float outline_px = 1.0;
uniform float pull_m = 0.35;      // vertex pull toward the camera against z-fighting on slopes
uniform float intensity = 0.85;
uniform float dash_speed = 3.0;   // metres per second of the marching dashes
uniform float dash_period = 1.2;

varying vec2 v_uv;
varying vec4 v_col;
varying vec2 v_style;

void vertex() {
	vec3 vp = (VIEW_MATRIX * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	vec3 vt = (VIEW_MATRIX * (MODEL_MATRIX * vec4(VERTEX + NORMAL, 1.0))).xyz;
	vec3 pulled = vp - normalize(vp) * pull_m;
	vec4 c0 = PROJECTION_MATRIX * vec4(pulled, 1.0);
	vec4 c1 = PROJECTION_MATRIX * vec4(vt - normalize(vp) * pull_m, 1.0);
	v_uv = UV;
	v_col = COLOR;
	v_style = UV2;
	if (c0.w <= 0.05) {
		POSITION = vec4(3.0, 3.0, 1.0, 1.0);
	} else {
		vec2 s0 = c0.xy / c0.w;
		vec2 s1 = c1.xy / max(c1.w, 0.05);
		vec2 d = (s1 - s0) * VIEWPORT_SIZE;
		float len = length(d);
		vec2 dir = len > 0.0001 ? d / len : vec2(1.0, 0.0);
		vec2 perp = vec2(-dir.y, dir.x);
		float w = (width_px + 2.0 * outline_px) * UV2.y;
		vec2 off_px = perp * UV.x * w * 0.5;
		POSITION = vec4(c0.xy + off_px * 2.0 / VIEWPORT_SIZE * c0.w, c0.z, c0.w);
	}
}

void fragment() {
	float side = abs(v_uv.x);
	float w_tot = (width_px + 2.0 * outline_px) * v_style.y;
	float core = (width_px * v_style.y) / w_tot;
	float aa = 1.5 / max(w_tot, 1.0);
	float in_core = 1.0 - smoothstep(core - aa, core, side);
	float in_all = 1.0 - smoothstep(1.0 - aa, 1.0, side);
	float style = v_style.x;
	float mask = 1.0;
	if (style < 0.5) {
		float ph = fract((v_uv.y - view_time * dash_speed) / dash_period);
		mask = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.55, 0.63, ph));
	} else if (style > 1.5 && style < 2.5) {
		float ph2 = fract(v_uv.y / 2.6);
		mask = smoothstep(0.0, 0.05, ph2) * (1.0 - smoothstep(0.66, 0.71, ph2));
	} else if (style > 2.5 && style < 3.5) {
		float ph3 = fract(v_uv.y / 1.0);
		mask = smoothstep(0.0, 0.08, ph3) * (1.0 - smoothstep(0.4, 0.48, ph3));
	} else if (style > 3.5) {
		float ph4 = fract((v_uv.y - view_time * 0.9) / 3.0);
		mask = smoothstep(0.0, 0.05, ph4) * (1.0 - smoothstep(0.7, 0.75, ph4));
	}
	float a_core = in_core * mask;
	float a_out = max(in_all * mask - a_core, 0.0) * 0.6;
	float alpha = a_core * v_col.a + a_out * v_col.a;
	if (alpha < 0.01) {
		discard;
	}
	vec3 col = vc_to_lin(v_col.rgb) * intensity;
	float k = a_core * v_col.a / max(alpha, 0.0001);
	ALBEDO = mix(vec3(0.0), col, k);
	ALPHA = alpha;
}
