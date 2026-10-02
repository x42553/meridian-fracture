// Shared helpers for view shaders (include with #include "res://assets/shaders/view_common.gdshaderinc").
// Declares the time / night globals; ViewGlobals.ensure() must have registered them before a shader compiles.
// A global must be declared by exactly one include per shader: do not redeclare these elsewhere.
global uniform float fx_time;     // FxManager clock (pause / game speed aware); shaders never read TIME
global uniform float view_time;   // ViewGlobals.tick (frozen at 0 in screenshot mode)
global uniform float atm_night;   // 0 day .. 1 night; emissive multiplier 1 + 1.2 * atm_night

const float VC_TAU = 6.28318530718;

mat3 vc_rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 vc_rot_y(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

mat3 vc_rot_z(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

float vc_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vc_hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vc_vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(vc_hash13(i), vc_hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(vc_hash13(i + vec3(0.0, 1.0, 0.0)), vc_hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(vc_hash13(i + vec3(0.0, 0.0, 1.0)), vc_hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(vc_hash13(i + vec3(0.0, 1.0, 1.0)), vc_hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

// sRGB-authored colour -> linear (the engine does not convert instance / plain vec3 uniforms).
vec3 vc_to_lin(vec3 c) {
	return pow(c, vec3(2.2));
}
