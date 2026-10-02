shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Meridian unit/structure shader. One ShaderMaterial per paint style (faction/subfaction), shared by every model.
//
// Per-vertex data (see ViewMeshBuilder):  COLOR = paint rgb + team mask, UV = planar metres (tracks: lateral, arc),
//   UV2 = (trunnion_y, trunnion_z), CUSTOM0 = (ao4<<4|wear<<3|mat, part kind, param, unused), CUSTOM1 = (pivot xyz, extra)
// Per-instance state (GeometryInstance3D.set_instance_shader_parameter) - or INSTANCE_CUSTOM when compiled with MM:
//   u_team  rgb  team colour (sRGB)
//   u_anim  x time s | y move 0..1 | z roll metres (wheels/tracks/walk) | w turret yaw rad (Godot: CCW from above)
//   u_aux   x recoil 0..1 | y deploy/door/elevation 0..1 | z rotor/radar rad/s | w spare
//   u_state x damage 0..1 | y selected 0..1 | z fog mode (0 = ignore, 1 = apply fog texture) | w hit flash 0..1
// Part kinds: 1 TURRET yaw, 2 BARREL yaw+recoil+elevation, 3 WHEEL roll (extra = radius), 4 TRACK (fragment scroll),
//   5 ROTOR, 6 TAIL_ROTOR, 7 RADAR, 8/9 LEG_A/B, 10/11 ARM_A/B, 12 BODY_BOB, 13 DOOR (extra = travel m), 14 BLINK, 15 DEPLOY.

global uniform sampler2D fow_tex;
global uniform vec4 fow_rect; // xy = world origin (m), zw = 1 / world size (m)

#ifdef MM
uniform vec3 mm_team = vec3(0.9, 0.45, 0.05);
#else
instance uniform vec4 u_team = vec4(0.9, 0.45, 0.05, 1.0);
instance uniform vec4 u_anim = vec4(0.0);
instance uniform vec4 u_aux = vec4(0.0);
instance uniform vec4 u_state = vec4(0.0);
#endif

uniform float wear_amount : hint_range(0.0, 1.0) = 0.5;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.5;
uniform float panel_amount : hint_range(0.0, 1.0) = 0.65;
uniform vec3 wear_color = vec3(0.78, 0.74, 0.66);
uniform vec3 dirt_color = vec3(0.30, 0.24, 0.17);
uniform float emissive_strength = 2.5;
uniform vec3 rim_color = vec3(1.0, 0.92, 0.7);
uniform float quality : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_opos;
varying vec3 v_onrm;
varying vec3 v_paint;
varying vec4 v_misc;  // x team mask, y wear, z ao, w param 0..1
varying vec2 v_uv;
varying vec3 v_team;
varying vec4 v_anim;
varying vec4 v_state;
varying vec2 v_kind;  // x material class, y part kind

const float TAU_F = 6.28318530718;

mat3 rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 rot_y(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

// 1 on a panel seam, 0 elsewhere; constant ~px pixel width, fades out when cells become sub-pixel.
float panel_lines(vec2 uv, float cell, float px) {
	vec2 g = uv / cell;
	vec2 w = fwidth(g) + vec2(1.0e-5);
	vec2 d = abs(fract(g - 0.5) - 0.5) / w;
	float line = 1.0 - smoothstep(px - 0.5, px + 0.5, min(d.x, d.y));
	return line * (1.0 - smoothstep(0.05, 0.16, max(w.x, w.y)));
}

vec3 to_lin(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	vec4 c0 = CUSTOM0;
	// CUSTOM0.x = (ao4 << 4) | (wear << 3) | mat; .w is NOT used (gl_compatibility does not deliver it). Float decode only.
	float f_pack = floor(c0.x * 255.0 + 0.5);
	float f_hi = floor(f_pack / 16.0);
	float f_lo = f_pack - f_hi * 16.0;
	float wear = floor(f_lo / 8.0);
	int mat_id = int(f_lo - wear * 8.0 + 0.5);
	float ao = f_hi / 15.0;
	int part = int(c0.y * 255.0 + 0.5);
	float param = c0.z;
	vec3 pivot = CUSTOM1.xyz;
	float extra = CUSTOM1.w;

#ifdef MM
	vec4 anim = vec4(TIME, 1.0, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y);
	vec4 aux = vec4(INSTANCE_CUSTOM.z, 0.0, 25.0, 0.0);
	vec4 st = vec4(0.0);
	vec3 team = mm_team;
#else
	vec4 anim = u_anim;
	vec4 aux = u_aux;
	vec4 st = u_state;
	vec3 team = u_team.rgb;
#endif

	vec3 p = VERTEX;
	vec3 n = NORMAL;
	v_opos = VERTEX;
	v_onrm = NORMAL;

	if (part == 1 || part == 2) {
		vec3 q = p - pivot;
		vec3 nn = n;
		if (part == 2) {
			vec3 tr = vec3(0.0, UV2.x - pivot.y, UV2.y - pivot.z);
			vec3 r = q - tr;
			r.z += aux.x * extra; // recoil along the barrel axis (+Z is backwards)
			mat3 e = rot_x(aux.y * param * 1.5708);
			q = tr + e * r;
			nn = e * nn;
		}
		mat3 y = rot_y(anim.w);
		p = pivot + y * q;
		n = y * nn;
	} else if (part == 3) {
		mat3 r = rot_x(-anim.z / max(extra, 0.05));
		p = pivot + r * (p - pivot);
		n = r * n;
	} else if (part == 5) {
		mat3 r = rot_y(aux.z * anim.x);
		p = pivot + r * (p - pivot);
		n = r * n;
	} else if (part == 6) {
		mat3 r = rot_x(aux.z * 1.7 * anim.x);
		p = pivot + r * (p - pivot);
		n = r * n;
	} else if (part == 7) {
		mat3 r = rot_y(aux.z * anim.x);
		p = pivot + r * (p - pivot);
		n = r * n;
	} else if (part >= 8 && part <= 12) {
		float ph = anim.z * TAU_F / 0.9 + param * TAU_F;
		float sw = sin(ph) * anim.y * 0.75;
		float ang = 0.0;
		if (part == 8) ang = sw;
		else if (part == 9) ang = -sw;
		else if (part == 10) ang = -sw * 0.8;
		else if (part == 11) ang = sw * 0.8;
		if (part != 12) {
			mat3 r = rot_x(ang);
			p = pivot + r * (p - pivot);
			n = r * n;
		}
		p.y += abs(sin(ph)) * 0.035 * anim.y;
	} else if (part == 13) {
		p.y += aux.y * extra;
	} else if (part == 15) {
		mat3 r = rot_x(aux.y * (param * 2.0 - 1.0) * 2.2);
		p = pivot + r * (p - pivot);
		n = r * n;
	}

	// fog-of-war hook: sample the per-player visibility texture once per unit (object origin); collapse hidden units.
	float vis = 1.0;
	if (st.z > 0.5) {
		vec2 fuv = (MODEL_MATRIX[3].xz - fow_rect.xy) * fow_rect.zw;
		vis = textureLod(fow_tex, fuv, 0.0).r;
		if (vis < 0.08) {
			p = vec3(0.0);
		}
	}

	VERTEX = p;
	NORMAL = normalize(n);
	v_paint = to_lin(COLOR.rgb);
	v_misc = vec4(COLOR.a, wear, ao, param);
	v_uv = UV;
	v_team = to_lin(team);
	v_anim = anim;
	v_state = vec4(st.x, st.y, vis, st.w);
	v_kind = vec2(float(mat_id), float(part));
}

void fragment() {
	int mat_id = int(v_kind.x + 0.5);
	int part = int(v_kind.y + 0.5);
	vec3 paint = v_paint;
	float team_mask = v_misc.x;
	float wear_mask = v_misc.y;
	float ao = v_misc.z;
	vec3 P = v_opos;

	float n_lo = 0.5;
	float n_hi = 0.5;
	if (quality > 0.5) {
		n_lo = vnoise(P * 2.3 + vec3(11.0));
		n_hi = vnoise(P * 9.0 + vec3(3.7));
	}

	vec3 albedo = paint * (0.9 + 0.2 * n_lo);
	float metallic = 0.0;
	float rough = 0.6;
	float spec = 0.5;
	vec3 emis = vec3(0.0);

	if (mat_id == 0) {
		// PAINT
		float luma = dot(paint, vec3(0.3, 0.55, 0.15));
		albedo = mix(albedo, v_team * (0.30 + 0.9 * luma + 0.10), team_mask);
		rough = 0.5 + 0.18 * n_hi;
		metallic = 0.04;
		float cell = mix(0.45, 1.4, v_misc.w);
		float pl = panel_lines(v_uv, cell, 0.9) + 0.45 * panel_lines(v_uv + vec2(7.3), cell * 0.33, 0.7);
		albedo *= 1.0 - clamp(pl, 0.0, 1.0) * 0.5 * panel_amount;
		if (wear_mask > 0.01) {
			float chip = smoothstep(0.34, 0.6, n_hi * 0.65 + vnoise(P * 26.0) * 0.5 - 0.1) * wear_mask * wear_amount;
			albedo = mix(albedo * (1.0 + 0.3 * wear_mask), to_lin(wear_color), chip);
			metallic = mix(metallic, 0.85, chip);
			rough = mix(rough, 0.38, chip);
		}
	} else if (mat_id == 1) {
		// METAL
		albedo = paint * (0.85 + 0.3 * n_hi);
		metallic = 0.9;
		rough = 0.36 + 0.24 * n_hi;
		spec = 0.7;
	} else if (mat_id == 2) {
		// GLASS
		albedo = paint * 0.35;
		metallic = 0.0;
		rough = 0.05;
		spec = 1.0;
		emis = paint * 0.12;
	} else if (mat_id == 3) {
		// RUBBER (tracks use part 4)
		albedo = paint;
		rough = 0.92;
		spec = 0.2;
		if (part == 4) {
			float s = v_uv.y - v_anim.z;
			float f = fract(s / 0.14);
			float ridge = smoothstep(0.0, 0.12, f) * (1.0 - smoothstep(0.5, 0.7, f));
			albedo = paint * mix(0.5, 1.5, ridge);
			metallic = 0.4 * ridge;
			rough = mix(0.9, 0.55, ridge);
		}
	} else {
		// EMISSIVE
		float blink = 1.0;
		if (part == 14) {
			blink = step(0.55, fract(v_anim.x * 0.9 + v_misc.w));
		}
		albedo = paint * 0.15;
		emis = paint * emissive_strength * blink;
		rough = 0.4;
	}

	// dirt: heavier low on the model and on vertical/downward faces
	float lowness = smoothstep(1.1, 0.0, P.y);
	float dirt = lowness * dirt_amount * (0.3 + 0.9 * n_hi) * (0.55 + 0.45 * (1.0 - max(v_onrm.y, 0.0)));
	if (mat_id != 4 && mat_id != 2) {
		albedo = mix(albedo, to_lin(dirt_color), clamp(dirt, 0.0, 0.85));
		rough = mix(rough, 0.95, clamp(dirt, 0.0, 1.0));
	}

	// damage: soot + embers
	float d = v_state.x;
	if (d > 0.001) {
		float soot = smoothstep(0.1, 0.85, d * (0.35 + 1.1 * n_lo + 0.5 * n_hi));
		albedo = mix(albedo, vec3(0.012), soot * 0.9);
		rough = mix(rough, 0.9, soot);
		metallic = mix(metallic, 0.0, soot);
		emis += vec3(1.0, 0.32, 0.05) * pow(n_hi, 6.0) * smoothstep(0.55, 1.0, d) * 3.0;
	}

	// selection rim + hit flash
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	emis += to_lin(rim_color) * rim * v_state.y * 1.6;
	emis += vec3(1.0, 0.85, 0.6) * v_state.w;

	// fog of war: v_state.z carries the sampled visibility (1.0 when the unit ignores fog), dim explored-but-hidden units
	albedo *= mix(0.45, 1.0, smoothstep(0.1, 0.9, v_state.z));

	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
	AO = ao;
	AO_LIGHT_AFFECT = 0.45;
}
