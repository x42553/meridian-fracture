shader_type spatial;
// Interception dome (Trident, render spec 5.9.7 / art_direction 5.9.4): a translucent hemisphere with a hex lattice, rising energy
// bands and a bright fresnel rim. Brightness follows the remaining charges (charge01 = charges / 24); it turns amber when nearly
// spent. The mesh is a unit hemisphere scaled by the zone radius.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled;

#include "res://assets/shaders/view_common.gdshaderinc"
#include "res://assets/shaders/fog_of_war.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.35, 0.85, 1.0);
uniform float charge01 = 1.0;
uniform float t_anim = 0.0;
uniform float fade = 1.0;
uniform float hostile = 0.0;
uniform float use_fog = 0.0;
uniform float intensity = 0.9;

varying vec3 v_obj;
varying vec3 v_w;

void vertex() {
	v_obj = VERTEX;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// hexagon lattice edge factor in 0..1 (1 on an edge) for a 2D coordinate
float hex_edge(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	float c = max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
	float y = 0.5 - c;
	return 1.0 - smoothstep(0.0, 0.07, y);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - clamp(abs(dot(n, VIEW)), 0.0, 1.0), 2.2);
	vec3 o = normalize(v_obj);
	float lon = atan(o.z, o.x);
	float lat = asin(clamp(o.y, -1.0, 1.0));
	vec2 hp = vec2(lon * 5.0, lat * 5.0);
	float he = hex_edge(hp);
	float charge = clamp(charge01, 0.0, 1.0);
	// rising bands
	float band = smoothstep(0.85, 1.0, sin((lat * 6.0 - t_anim * 1.2) * 1.5) * 0.5 + 0.5);
	float low = smoothstep(0.0, 0.25, o.y);  // fade out at the ground ring
	vec3 col = mix(vec3(1.0, 0.6, 0.15), tint, smoothstep(0.1, 0.4, charge));
	col = mix(col, vec3(1.0, 0.35, 0.28), hostile * 0.5);
	float a = (0.05 + fres * 0.55 + he * 0.22 + band * 0.18) * mix(0.35, 1.0, charge);
	a *= mix(0.4, 1.0, low) * fade;
	if (use_fog > 0.5) {
		vec2 fs = fow_sample(v_w.xz);
		a *= mix(0.0, mix(0.35, 1.0, fs.y), fs.x);
	}
	// VQ2B: the dome read as a milky veil at close range (a = 0.05 base + fresnel was also used as coverage, so the terrain under the dome was
	// washed out toward the tint, twice because both faces draw). Now it is almost purely additive glow: a small coverage keeps only a trace of
	// the veil, the inner face is a quarter as bright, and the glow fades out where the camera is within a few metres of the shell.
	float outer = FRONT_FACING ? 1.0 : 0.25;
	float near_fade = smoothstep(2.0, 10.0, length(VERTEX));
	ALBEDO = col * intensity * a * outer * near_fade * 0.9;
	ALPHA = a * 0.12 * outer * near_fade;
}
