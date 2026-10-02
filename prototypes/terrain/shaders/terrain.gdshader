// Procedural terrain splat shader: 6 layers from per-cell control weights + slope + noise-modulated blending,
// triplanar rock, asphalt roads with lane markings from a 4 texel/cell raster, salvage-field scrap, wet sand,
// underwater caustics, scorch stamps, cavity AO, cloud shadows, fog of war. Zero external art.
// Compile with #define TERRAIN_LOW (ViewTerrain.create_material(low = true)) for the cheap variant.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/fog_of_war.gdshaderinc"
#include "res://shaders/atmosphere.gdshaderinc"

uniform sampler2D ctrl_a : filter_linear, repeat_disable;       // grass, dirt, rock, sand
uniform sampler2D ctrl_b : filter_linear, repeat_disable;       // snow, salvage, -, moisture
uniform sampler2D roads : filter_linear, repeat_disable;        // 255-dist/6m, signed lateral, sin/cos phase
uniform sampler2D stamps : filter_linear, repeat_disable;       // scorch overlay RGB tint, A opacity
uniform sampler2D water_depth : filter_linear, repeat_disable;  // (depth + 2 m) / 8 m at vertex resolution
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;      // fbm lo, fbm hi, cracks, cell id
uniform sampler2D detail_nrm : filter_linear_mipmap_anisotropic, repeat_enable;  // ground xy, rock xy

uniform vec2 map_size = vec2(576.0);
uniform vec2 depth_scale = vec2(0.005);
uniform vec2 depth_offset = vec2(0.0);
uniform float dryness : hint_range(0.0, 1.0) = 0.0;
uniform float road_half_width = 3.1;
uniform float bump_strength = 1.0;
uniform float fow_enabled = 1.0;
uniform float cloud_enabled = 1.0;

uniform vec3 grass_a : source_color = vec3(0.20, 0.36, 0.11);
uniform vec3 grass_b : source_color = vec3(0.36, 0.52, 0.17);
uniform vec3 dry_a : source_color = vec3(0.48, 0.42, 0.22);
uniform vec3 dry_b : source_color = vec3(0.62, 0.55, 0.30);
uniform vec3 dirt_a : source_color = vec3(0.30, 0.21, 0.13);
uniform vec3 dirt_b : source_color = vec3(0.46, 0.34, 0.21);
uniform vec3 rock_a : source_color = vec3(0.31, 0.30, 0.29);
uniform vec3 rock_b : source_color = vec3(0.54, 0.51, 0.47);
uniform vec3 sand_a : source_color = vec3(0.72, 0.65, 0.46);
uniform vec3 sand_b : source_color = vec3(0.86, 0.79, 0.59);
uniform vec3 snow_c : source_color = vec3(0.93, 0.96, 1.0);

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_cavity;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cavity = COLOR.r;
}

void fragment() {
	vec3 P = v_wpos;
	vec2 muv = P.xz / map_size;
	// Domain-warp the control lookup (~2 m) so 3 m cell steps become organic boundaries.
	vec2 warp = (texture(detail, P.xz * 0.055 + vec2(0.13, 0.61)).rg - 0.5) * (5.0 / map_size);
	vec4 ca = texture(ctrl_a, muv + warp);
	vec4 cb = texture(ctrl_b, muv + warp);
	vec3 Ng = normalize(v_wnrm);

	// Detail noise at three scales (macro hides tiling).
	vec4 n0 = texture(detail, P.xz * 0.0117);
	vec4 n1 = texture(detail, P.xz * 0.043 + vec2(0.37, 0.11));
	vec4 n2 = texture(detail, P.xz * 0.19 + vec2(0.71, 0.53));
	vec2 gn = texture(detail_nrm, P.xz * 0.21).rg * 2.0 - 1.0;
	vec4 n3 = texture(detail, P.xz * 0.83 + vec2(0.29, 0.91));                 // ~1.2 m grain
	vec2 gn2 = texture(detail_nrm, P.xz * 0.97).rg * 2.0 - 1.0;                // fine bump

	float depth = texture(water_depth, P.xz * depth_scale + depth_offset).r * 8.0 - 2.0; // > 0 underwater
	float slope = 1.0 - Ng.y;
	float steep = smoothstep(0.20, 0.40, slope + (n1.g - 0.5) * 0.10);

	// ---- layer weights: control map x slope, then noise-modulated ("height") blending ----
	float w_grass = ca.r * (1.0 - steep);
	float w_dirt = ca.g * (1.0 - steep * 0.7);
	float w_rock = max(ca.b, steep);
	float w_sand = ca.a * (1.0 - steep);
	float w_snow = cb.r * (1.0 - steep);
	float w_salv = cb.g * (1.0 - steep * 0.6);
	float e0 = w_grass + (n1.r * 0.5 + n2.g * 0.5) * 0.75;
	float e1 = w_dirt + (n1.g * 0.6 + n2.r * 0.4) * 0.75;
	float e2 = w_rock + (n0.r * 0.4 + n1.g * 0.6) * 0.75;
	float e3 = w_sand + n2.g * 0.55;
	float e4 = w_snow + n1.r * 0.55;
	float e5 = w_salv + (n2.r * 0.5 + n1.g * 0.5) * 0.75;
	float mx = max(max(max(e0, e1), max(e2, e3)), max(e4, e5)) - 0.34;
	float b0 = max(e0 - mx, 0.0);
	float b1 = max(e1 - mx, 0.0);
	float b2 = max(e2 - mx, 0.0);
	float b3 = max(e3 - mx, 0.0);
	float b4 = max(e4 - mx, 0.0);
	float b5 = max(e5 - mx, 0.0);
	float inv = 1.0 / (b0 + b1 + b2 + b3 + b4 + b5 + 1e-4);
	b0 *= inv; b1 *= inv; b2 *= inv; b3 *= inv; b4 *= inv; b5 *= inv;

	// ---- per-layer colour ----
	float dry = clamp(dryness + (cb.a - 0.5) * 0.5, 0.0, 1.0);
	float gmix = 0.22 + 0.56 * n1.r;
	vec3 c_grass = mix(mix(grass_a, grass_b, gmix), mix(dry_a, dry_b, gmix), dry);
	c_grass *= (0.84 + 0.30 * n2.g) * (0.86 + 0.28 * n3.g);
	c_grass = mix(c_grass, c_grass * 1.35, step(0.90, n3.a) * smoothstep(0.05, 0.2, n3.b) * 0.5);   // bright tufts
	c_grass *= 0.92;
	c_grass = mix(c_grass, c_grass * vec3(1.14, 1.05, 0.78), smoothstep(0.58, 0.85, n0.r) * 0.35);

	vec3 c_dirt = mix(dirt_a, dirt_b, n1.g) * (0.78 + 0.44 * n2.r) * (0.88 + 0.24 * n3.g);
	float pebble = step(0.80, n2.a) * smoothstep(0.05, 0.2, n2.b);
	c_dirt = mix(c_dirt, c_dirt * 1.5 + 0.02, pebble * 0.55);

	vec3 c_sand = mix(sand_a, sand_b, n1.r * 0.6 + 0.2);
	float ripple = sin((P.x * 0.55 + P.z * 0.3) * 2.2 + n1.r * 7.0) * 0.5 + 0.5;
	c_sand *= 0.90 + 0.14 * ripple + 0.06 * (n2.g - 0.5);

	vec3 c_snow = snow_c * (0.80 + 0.12 * n2.g + 0.08 * n3.g) * mix(0.9, 1.0, n1.r);

	// Rock: triplanar strata + cracks (steep faces would stretch a planar projection).
	vec3 tw = pow(abs(Ng), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z + 1e-5);
	float ts = 0.052;
#ifdef TERRAIN_LOW
	vec4 rk = texture(detail, P.xz * ts + vec2(P.y * 0.05, 0.0));
	vec3 rock_pert = vec3(0.0);
#else
	vec4 rk = texture(detail, P.zy * ts) * tw.x + texture(detail, P.xz * ts) * tw.y + texture(detail, P.xy * ts) * tw.z;
	vec2 rnx = texture(detail_nrm, P.zy * ts * 1.6).ba * 2.0 - 1.0;
	vec2 rny = texture(detail_nrm, P.xz * ts * 1.6).ba * 2.0 - 1.0;
	vec2 rnz = texture(detail_nrm, P.xy * ts * 1.6).ba * 2.0 - 1.0;
	vec3 rock_pert = vec3(0.0, rnx.y, rnx.x) * tw.x + vec3(rny.x, 0.0, rny.y) * tw.y + vec3(rnz.x, rnz.y, 0.0) * tw.z;
#endif
	float band = mix(0.5, 0.5 + 0.5 * sin(P.y * 2.4 + rk.r * 5.0 + rk.g * 2.5), smoothstep(0.15, 0.5, slope));
	float crack = smoothstep(0.0, 0.14, rk.b);
	vec3 c_rock = mix(rock_a, rock_b, clamp(band * 0.5 + rk.g * 0.5, 0.0, 1.0));
	c_rock *= (0.68 + 0.32 * crack) * (0.78 + 0.44 * rk.a) * (0.85 + 0.3 * n0.r) * mix(1.0, 0.72, smoothstep(0.25, 0.6, slope));

	// Salvage field: dark soil, scrap plates (steel/rust), teal credit glints.
	vec4 ns = texture(detail, P.xz * 0.47 + vec2(0.11, 0.37));                  // fine scrap-scale cells
	float plate = smoothstep(0.05, 0.14, ns.b);
	vec3 steel = vec3(0.17, 0.18, 0.20) * (0.8 + 0.5 * n1.g);
	vec3 rust = vec3(0.20, 0.09, 0.045) * (0.7 + 0.6 * n1.r);
	vec3 soil = vec3(0.05, 0.043, 0.04) * (0.7 + 0.6 * n2.r);
	vec3 c_salv = mix(soil, mix(rust, steel, step(0.62, ns.a)), plate * step(0.30, ns.a));
	float glint = smoothstep(0.985, 1.0, ns.a) * plate * step(0.5, n1.g);

	vec3 albedo = c_grass * b0 + c_dirt * b1 + c_rock * b2 + c_sand * b3 + c_snow * b4 + c_salv * b5;
	float rough = b0 * 0.93 + b1 * 0.90 + b2 * 0.82 + b3 * 0.86 + b4 * 0.55 + b5 * 0.45;
	float spec = b0 * 0.20 + b1 * 0.25 + b2 * 0.35 + b3 * 0.30 + b4 * 0.60 + b5 * 0.70;
	float metallic = b5 * plate * 0.55;
	vec3 emis = vec3(0.05, 0.95, 0.75) * 1.6 * glint * b5 * (0.9 + 0.5 * sin(TIME * 2.5 + ns.a * 40.0));

	// ---- roads (asphalt, dirt shoulder, lane markings) ----
	vec4 rt = texture(roads, muv);
	float rd = (1.0 - rt.r) * 6.0;
	float wob = (n2.g - 0.5) * 0.35;
	float road = 1.0 - smoothstep(road_half_width - 0.10, road_half_width + 0.10, rd + wob);
	float shoulder = 1.0 - smoothstep(road_half_width, road_half_width + 1.7, rd + wob * 3.0);
	vec3 asphalt = vec3(0.105, 0.105, 0.115) * (0.75 + 0.5 * n2.g);
	asphalt = mix(asphalt, asphalt * 0.55, (1.0 - smoothstep(0.0, 0.08, n1.b)) * 0.6);   // cracks
	asphalt = mix(asphalt, asphalt * 1.5, smoothstep(0.55, 0.9, n0.r) * 0.35);          // wear patches
	float lat = (rt.g - 0.5) * 12.0;
	float ph = atan(rt.b - 0.5, rt.a - 0.5) / TAU + 0.5;
	float dash = step(fract(ph * 2.0), 0.5);
	float centre = (1.0 - smoothstep(0.09, 0.17, abs(lat))) * dash;
	float edge = 1.0 - smoothstep(0.07, 0.14, abs(abs(lat) - (road_half_width - 0.40)));
	float wear = 0.55 + 0.45 * n2.g;
	vec3 paint = vec3(0.80, 0.68, 0.22) * centre + vec3(0.78, 0.78, 0.74) * edge;
	asphalt = mix(asphalt, paint / max(centre + edge, 1e-3), clamp(centre + edge, 0.0, 1.0) * wear * 0.85);
	albedo = mix(albedo, mix(albedo, dirt_a * 0.9, 0.6), shoulder * (1.0 - road) * 0.7);
	albedo = mix(albedo, asphalt, road);
	rough = mix(rough, 0.72, road);
	spec = mix(spec, 0.45, road);
	metallic *= 1.0 - road;

	// ---- wet sand at the waterline, underwater darkening + caustics ----
	float above = -depth;
	float wet = 1.0 - smoothstep(0.0, 0.55, above);
	float uw = smoothstep(0.02, 0.30, depth);
	albedo = mix(albedo, albedo * vec3(0.52, 0.58, 0.60), wet * 0.85);
	rough = mix(rough, 0.28, wet * (1.0 - uw) * 0.8);
	albedo *= mix(1.0, 0.62, uw);
#ifndef TERRAIN_LOW
	float cA = texture(detail, P.xz * 0.16 + vec2(TIME * 0.021, TIME * 0.013)).b;
	float cB = texture(detail, P.xz * 0.11 - vec2(TIME * 0.017, -TIME * 0.023)).b;
	float caustic = ((1.0 - smoothstep(0.0, 0.24, cA)) + (1.0 - smoothstep(0.0, 0.30, cB))) * 0.5;
	emis += vec3(0.55, 0.85, 0.80) * caustic * caustic * uw * (1.0 - smoothstep(0.4, 3.2, depth)) * 0.18;
#endif

	// ---- scorch stamps (CPU-painted layer): tint + bump from the alpha gradient ----
	vec4 st = texture(stamps, muv);
	albedo = mix(albedo, st.rgb, st.a * 0.94);
	rough = mix(rough, 1.0, st.a);
	spec *= 1.0 - st.a * 0.8;
#ifndef TERRAIN_LOW
	vec2 stx = 1.0 / vec2(textureSize(stamps, 0));
	float sgx = texture(stamps, muv + vec2(stx.x, 0.0)).a - texture(stamps, muv - vec2(stx.x, 0.0)).a;
	float sgz = texture(stamps, muv + vec2(0.0, stx.y)).a - texture(stamps, muv - vec2(0.0, stx.y)).a;
	vec3 stamp_pert = vec3(-sgx, 0.0, -sgz) * 3.0;
#else
	vec3 stamp_pert = vec3(0.0);
#endif

	// ---- normal ----
	float flat_w = b0 + b1 + b3 + b4;
	vec3 Nw = normalize(Ng + (vec3(gn.x + gn2.x * 0.6, 0.0, gn.y + gn2.y * 0.6) * 0.30 * flat_w + rock_pert * 0.9 * b2 + stamp_pert) * bump_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(Nw, 0.0)).xyz);

	// ---- baked cavity, cloud shadows ----
	float cav = clamp(v_cavity * 2.0, 0.0, 1.3);
	albedo *= mix(1.0, clamp(cav, 0.8, 1.15), 0.85);
	AO = clamp(cav, 0.7, 1.0);
	float cl = texture(detail, P.xz * atm_cloud.y + atm_cloud.zw * TIME * atm_cloud.y).r;
#ifndef TERRAIN_LOW
	cl = cl * 0.65 + texture(detail, (P.xz * atm_cloud.y + atm_cloud.zw * TIME * atm_cloud.y) * 2.7 + 0.37).r * 0.35;
#endif
	albedo *= mix(1.0, 1.0 - atm_cloud.x * smoothstep(0.45, 0.75, cl), cloud_enabled);

	// ---- fog of war ----
	if (fow_enabled > 0.5) {
		vec2 fs = fow_sample(P.xz);
		float nz = (n1.g - 0.5) * 0.35;
		float explored = smoothstep(0.32, 0.68, fs.x + nz);
		float visible = smoothstep(0.32, 0.68, fs.y + nz);
		float luma = dot(albedo, vec3(0.299, 0.587, 0.114));
		vec3 fogged = mix(vec3(luma), albedo, 0.45) * 0.42;
		albedo = mix(fogged, albedo, visible) * explored;
		emis *= visible;
		rough = mix(1.0, rough, explored);
		spec *= explored;
		metallic *= visible;
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = spec;
	METALLIC = metallic;
	EMISSION = emis;
}
