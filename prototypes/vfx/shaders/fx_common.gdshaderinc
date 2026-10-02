// Shared helpers for every Fx* shader (include with #include "res://shaders/fx_common.gdshaderinc").
//
// fx_time is the FxManager clock in seconds. It honours pause, game speed and fixed-step capture, so the
// shaders must never read TIME. fx_lod (0..1) thins clustered sprites for the quality presets.
global uniform float fx_time;
global uniform float fx_lod;

float fx_hash(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

vec2 fx_rot(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Direction on the upper hemisphere from two uniform randoms; min_el is the minimum sin(elevation).
vec3 fx_hemi(float r0, float r1, float min_el) {
	float phi = r0 * TAU;
	float el = mix(min_el, 1.0, r1);
	float c = sqrt(max(1.0 - el * el, 0.0));
	return vec3(cos(phi) * c, el, sin(phi) * c);
}
