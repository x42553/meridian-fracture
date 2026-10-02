shader_type spatial;
render_mode cull_back;
// Showcase ground: 3 m cells (1 cell = 3 m, the sim constant) with mottling and faint grid lines.

uniform vec3 col_a = vec3(0.43, 0.40, 0.34);
uniform vec3 col_b = vec3(0.36, 0.34, 0.29);
uniform float cell = 3.0;
uniform float water_mix : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_w;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = v_w.xz / cell;
	vec2 id = floor(g);
	float h = hash12(id);
	float m = vnoise2(v_w.xz * 0.35) * 0.6 + vnoise2(v_w.xz * 2.7) * 0.4;
	vec3 c = mix(col_a, col_b, clamp(h * 0.45 + m * 0.65, 0.0, 1.0));
	vec2 f = abs(fract(g) - 0.5);
	vec2 w = fwidth(g);
	float lx = smoothstep(0.5 - 1.5 * w.x, 0.5, f.x);
	float ly = smoothstep(0.5 - 1.5 * w.y, 0.5, f.y);
	c *= 1.0 - 0.10 * max(lx, ly);
	vec3 albedo = pow(c, vec3(2.2));
	float rough = 0.93;
	float spec = 0.15;
	float metallic = 0.0;
	if (water_mix > 0.5) {
		float t = TIME * 0.4;
		float rip = vnoise2(v_w.xz * 0.8 + vec2(t, t * 0.6)) * 0.6 + vnoise2(v_w.xz * 2.3 - vec2(t * 0.7, t)) * 0.4;
		albedo = mix(vec3(0.012, 0.07, 0.10), vec3(0.03, 0.16, 0.21), rip);
		rough = 0.34;
		spec = 0.30;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metallic;
}
