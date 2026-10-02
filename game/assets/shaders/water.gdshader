// Stylised RTS water (VIEW-03): depth-tinted body from the terrain's vertex-resolution depth raster + the shore-distance field,
// three scrolling normal layers, analytic sky reflection + sun glitter (atm_* globals, no probes), pulsing shoreline foam with
// lace, fog of war. No screen / depth-texture reads, so no extra full-screen copy pass. Compile with #define WATER_LOW (one
// normal layer, no lace) via ViewWater.build(low_shader = true).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/view_common.gdshaderinc"
#include "res://assets/shaders/fog_of_war.gdshaderinc"
#include "res://assets/shaders/atmosphere.gdshaderinc"

uniform sampler2D water_depth : filter_linear, repeat_disable;  // (sea - h + 2 m) / 8 m at vertex resolution
uniform sampler2D shore_dist : filter_linear, repeat_disable;   // chamfer distance from land, 1/3-cell units / 255
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec2 map_size = vec2(576.0);
uniform vec2 depth_scale = vec2(0.005);
uniform vec2 depth_offset = vec2(0.0);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.58, 0.62);
uniform vec3 deep_color : source_color = vec3(0.03, 0.18, 0.34);
uniform float absorb = 0.42;
uniform float wave_strength = 1.0;
uniform float foam_strength = 1.0;
uniform float glitter_strength = 1.0;
uniform float reflect_boost = 2.4;
uniform float fow_enabled = 1.0;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 P = v_wpos;
	float t = view_time;
	vec2 muv = P.xz / map_size;
	float depth = texture(water_depth, P.xz * depth_scale + depth_offset).r * 8.0 - 2.0;
	float shore = texture(shore_dist, muv).r * 85.0;          // cells from land
	vec2 outside = max(abs(muv - 0.5) - 0.5, vec2(0.0));
	float out_f = smoothstep(0.0, 0.02, max(outside.x, outside.y));
	depth = mix(depth, 6.0, out_f);
	shore = mix(shore, 40.0, out_f);
	float dsh = max(depth, 0.0);

	float deepness = max(1.0 - exp(-dsh * absorb), smoothstep(1.0, 12.0, shore));

	// Moving normals (three scales), calmer close to shore.
	vec2 w1 = texture(detail_nrm, P.xz * 0.085 + vec2(t * 0.018, t * 0.011)).rg * 2.0 - 1.0;
	float calm = mix(0.35, 1.0, smoothstep(0.0, 3.0, dsh));
#ifdef WATER_LOW
	vec2 nn = w1 * 0.9 * wave_strength * calm;
	vec2 w2 = w1;
#else
	vec2 w2 = texture(detail_nrm, P.xz * 0.19 + vec2(-t * 0.023, t * 0.017)).rg * 2.0 - 1.0;
	vec2 w3 = texture(detail_nrm, P.xz * 0.53 + vec2(t * 0.05, -t * 0.041)).rg * 2.0 - 1.0;
	vec2 nn = (w1 * 0.55 + w2 * 0.35 + w3 * 0.22) * wave_strength * calm;
#endif
	vec3 N = normalize(vec3(nn.x, 1.0, nn.y));

	vec3 V = normalize(CAMERA_POSITION_WORLD - P);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = 0.05 + 0.95 * pow(1.0 - ndv, 3.0);

	// Analytic sky reflection + sun halo + glitter.
	vec3 R = reflect(-V, N);
	vec3 sky = mix(atm_sky_horizon, atm_sky_zenith, pow(clamp(R.y, 0.0, 1.0), 0.6));
	float sd = max(dot(R, atm_sun_dir), 0.0);
	float sparkle = smoothstep(0.35, 0.8, texture(detail, P.xz * 0.9 + vec2(t * 0.06, -t * 0.04)).g);
	float glit = pow(sd, 700.0) * 16.0 * (0.4 + 0.6 * sparkle) + pow(sd, 260.0) * 0.18;
	vec3 refl = sky * fres * reflect_boost + atm_sun_color * (pow(sd, 24.0) * 0.025 + glit) * glitter_strength;

	// Shoreline foam: pulsing waterline band + lacy trail.
	float breathe = sin(t * 0.85 + w1.x * 3.0 + P.x * 0.05) * 0.5 + 0.5;
	float foam_w = mix(0.14, 0.5, breathe);
	float f_break = texture(detail, P.xz * 0.33 + vec2(t * 0.01, 0.0)).b;
	float f_edge = (1.0 - smoothstep(0.0, foam_w, dsh + w2.y * 0.25)) * mix(0.45, 1.0, smoothstep(0.25, 0.65, f_break));
#ifdef WATER_LOW
	float lace = 0.0;
#else
	float fn2 = texture(detail, P.xz * 0.47 - vec2(0.0, t * 0.010)).g;
	float fpat = fn2 * 0.6 + texture(detail, P.xz * 0.21 + vec2(-t * 0.008, t * 0.006)).r * 0.4;
	float thr = mix(0.38, 0.80, smoothstep(0.0, 1.0, dsh + breathe * 0.35));
	float lace = smoothstep(thr, thr + 0.10, fpat) * (1.0 - smoothstep(0.0, 1.1, dsh + breathe * 0.35)) * 0.55;
#endif
	float foam = clamp(f_edge * 0.7 + lace * 0.6, 0.0, 1.0) * foam_strength;

	vec3 body = mix(shallow_color, deep_color, deepness);
	float a = mix(0.30, 0.97, smoothstep(0.0, 2.8, dsh));
	a = max(a, fres * 0.8);

	vec3 albedo = mix(body, vec3(0.80, 0.86, 0.88), foam);
	vec3 emis = refl * (1.0 - foam * 0.85);
	float alpha = clamp(max(a, foam), 0.0, 1.0);
	float spec = 0.5;

	if (fow_enabled > 0.5) {
		vec2 fs = fow_sample(P.xz);
		float nz = (texture(detail, P.xz * 0.043 + vec2(0.37, 0.11)).g - 0.5) * 0.35;
		float explored = smoothstep(0.32, 0.68, fs.x + nz);
		float visible = smoothstep(0.32, 0.68, fs.y + nz);
		float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
		vec3 fogged = mix(vec3(luma), albedo, 0.45) * 0.42;
		albedo = mix(mix(albedo, fogged, fow_fog_dim), albedo, visible) * explored;
		emis *= visible;
		spec *= explored * mix(0.3, 1.0, visible);  // no sky reflection over shroud
		alpha = mix(1.0, alpha, explored);
	}

	ALBEDO = albedo;
	EMISSION = emis;
	ROUGHNESS = mix(0.06, 0.65, foam);
	SPECULAR = spec;
	ALPHA = alpha;
}
