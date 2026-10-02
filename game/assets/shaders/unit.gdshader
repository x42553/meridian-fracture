shader_type spatial;
// Meridian unit / structure / wreck / ghost shader (render spec 4.2-4.4, 5.8.8). One source, four compile variants selected
// by a `#define` prefix that ViewMaterials prepends to the code:
//   (none)  node backend: per-instance animation state through instance uniforms (Forward+, Mobile)
//   MM      batch backend: MultiMesh INSTANCE_CUSTOM = (roll_m, turret_yaw, recoil, damage); fixed-rate rotors / radars
//   MATU    plain uniforms with the instance names (one ShaderMaterial duplicate per entity; Compat structures, icon baking)
//   GHOST   placement ghost: blend_mix, alpha + tint uniforms
// Team colour is a plain per-material uniform (one material per style x player colour) in EVERY variant: instance uniforms
// are capped at ~256 users on Compatibility and are not sRGB-converted (terrain spike pitfall 2).
//
// Per-vertex data (ViewMeshBuilder): COLOR = paint rgb (sRGB) + team mask, UV = planar metres (tracks: lateral, arc),
//   UV2 = barrel (trunnion_y, trunnion_z) | gait parts (member_index, member_count), CUSTOM0 = (ao4<<4|wear<<3|mat, part, param, unused),
//   CUSTOM1 = (pivot xyz, extra).   NEVER read CUSTOM0.w: the Compatibility renderer does not deliver it.
// Per-instance state (vec4):
//   u_anim  x structure sink depth m | y move 0..1 | z roll metres | w turret yaw rad (Godot: CCW seen from above)
//   u_aux   x recoil 0..1 | y deploy / door / activity 0..1 | z spin angle rad | w barrel elevation 0..1
//   u_state x damage 0..1 | y selected 0..1 | z flags + cloak/1.001 (float-encoded, see UF_*) | w hit flash 0..1
//   u_mnt1..3 (yaw, elevation, recoil) of extra mounts (part kinds 19..24)
// Part kinds: 1 TURRET, 2 BARREL, 3 WHEEL, 4 TRACK, 5 ROTOR, 6 TAIL_ROTOR, 7 RADAR, 8/9 LEG_A/B, 10/11 ARM_A/B, 12 BODY_BOB,
//   13 DOOR, 14 BLINK, 15 DEPLOY, 16 DEPLOY_Z, 17 SLIDE_Y, 18 SLIDE_Z, 19..24 TURRET1/BARREL1..TURRET3/BARREL3.

#ifdef GHOST
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#else
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#endif

#include "res://assets/shaders/view_common.gdshaderinc"
#include "res://assets/shaders/fog_of_war.gdshaderinc"

#if defined(MM)
// batch path: INSTANCE_CUSTOM carries the animation, nothing else per instance
#elif defined(MATU)
uniform vec4 u_anim = vec4(0.0);
uniform vec4 u_aux = vec4(0.0);
uniform vec4 u_state = vec4(0.0);
uniform vec4 u_mnt1 = vec4(0.0);
uniform vec4 u_mnt2 = vec4(0.0);
uniform vec4 u_mnt3 = vec4(0.0);
#else
instance uniform vec4 u_anim = vec4(0.0);
instance uniform vec4 u_aux = vec4(0.0);
instance uniform vec4 u_state = vec4(0.0);
instance uniform vec4 u_mnt1 = vec4(0.0);
instance uniform vec4 u_mnt2 = vec4(0.0);
instance uniform vec4 u_mnt3 = vec4(0.0);
#endif

uniform vec3 team_color : source_color = vec3(0.85, 0.23, 0.23);
uniform float wear_amount : hint_range(0.0, 1.0) = 0.5;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.5;
uniform float panel_amount : hint_range(0.0, 1.0) = 0.65;
uniform vec3 wear_color : source_color = vec3(0.78, 0.74, 0.66);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.24, 0.17);
uniform float emissive_strength = 2.5;
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.7);
uniform float quality : hint_range(0.0, 1.0) = 1.0;
#ifdef GHOST
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.55;
uniform vec3 ghost_tint : source_color = vec3(0.3, 1.0, 0.4);
#endif

varying vec3 v_opos;
varying vec3 v_onrm;
varying vec3 v_paint;
varying vec4 v_misc;   // x team mask, y wear, z ao, w param 0..1
varying vec2 v_uv;
varying vec4 v_anim;
varying vec4 v_state;  // x damage, y selected, z fog dim factor, w hit flash
varying vec2 v_kind;   // x material class, y part kind
varying vec3 v_flags;  // x flags (int as float), y cloak level, z wreck burn 0..1 (embers fade out over the first 14 s)

const int UF_FOG_DIM = 1;
const int UF_GHOST = 2;
const int UF_SUBMERGED = 4;
const int UF_UNPOWERED = 8;
const int UF_CLOAKED = 16;
const int UF_EMP = 32;
const int UF_WRECK = 64;
const int UF_SUPPRESSED = 128;
const int UF_DECOY_ID = 256;
const int UF_STRUCT = 512;  // structure: cracks and paint loss from `damage`; u_anim.y = power-fade depth (0 powered .. 1 dark)

float panel_lines(vec2 uv, float cell, float px) {
	// 1 on a panel seam, 0 elsewhere; constant ~px pixel width, fades out when cells become sub-pixel
	vec2 g = uv / cell;
	vec2 w = fwidth(g) + vec2(1.0e-5);
	vec2 d = abs(fract(g - 0.5) - 0.5) / w;
	float line = 1.0 - smoothstep(px - 0.5, px + 0.5, min(d.x, d.y));
	return line * (1.0 - smoothstep(0.05, 0.16, max(w.x, w.y)));
}

vec3 rot_axis_apply(mat3 m, vec3 pivot, vec3 p) {
	return pivot + m * (p - pivot);
}

void vertex() {
	vec4 c0 = CUSTOM0;
	// CUSTOM0.x = (ao4 << 4) | (wear << 3) | mat; .w is NOT used (gl_compatibility does not deliver it).
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
	vec4 anim = vec4(0.0, 1.0, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y);
	vec4 aux = vec4(INSTANCE_CUSTOM.z, 0.0, 0.0, 0.0);
	vec4 st = vec4(INSTANCE_CUSTOM.w, 0.0, 0.0, 0.0);
	vec4 mnt1 = vec4(0.0);
	vec4 mnt2 = vec4(0.0);
	vec4 mnt3 = vec4(0.0);
	// no per-instance spin on this path: rotors and radars turn at a fixed rate from the global clock
	aux.z = fract(fx_time * (part == 7 ? 1.2 : 28.0) / VC_TAU) * VC_TAU;
#else
	vec4 anim = u_anim;
	vec4 aux = u_aux;
	vec4 st = u_state;
	vec4 mnt1 = u_mnt1;
	vec4 mnt2 = u_mnt2;
	vec4 mnt3 = u_mnt3;
#endif
	int flags = int(floor(st.z));
	float cloak = 0.0;
	if ((flags & UF_CLOAKED) != 0) {
		float fr = fract(st.z);
		cloak = fr > 0.001 ? clamp(fr / 0.999, 0.0, 1.0) : 1.0;
	}
	float burn = 1.0;
	if ((flags & UF_WRECK) != 0) {
		float fw = fract(st.z);
		burn = fw > 0.001 ? clamp(fw / 0.999, 0.0, 1.0) : 1.0;
	}
	if ((flags & UF_GHOST) != 0) {
		// remembered structure: animations frozen
		anim = vec4(anim.x, 0.0, 0.0, 0.0);
		aux = vec4(0.0);
		mnt1 = vec4(0.0);
		mnt2 = vec4(0.0);
		mnt3 = vec4(0.0);
	}

	vec3 p = VERTEX;
	vec3 n = NORMAL;
	v_opos = VERTEX;
	v_onrm = NORMAL;

	bool barrel = part == 2 || part == 20 || part == 22 || part == 24;
	bool turret = part == 1 || part == 19 || part == 21 || part == 23;
	if (barrel || turret) {
		float yaw = anim.w;
		float elev = aux.w;
		float rec = aux.x;
		if (part >= 19) {
			vec4 m = part <= 20 ? mnt1 : (part <= 22 ? mnt2 : mnt3);
			yaw = m.x;
			elev = m.y;
			rec = m.z;
		}
		vec3 q = p - pivot;
		vec3 nn = n;
		if (barrel) {
			vec3 tr = vec3(0.0, UV2.x - pivot.y, UV2.y - pivot.z);
			vec3 r = q - tr;
			r.z += rec * extra; // recoil along the barrel axis (+Z is backwards)
			mat3 e = vc_rot_x(elev * param * 1.5707963);
			q = tr + e * r;
			nn = e * nn;
		}
		mat3 y = vc_rot_y(yaw);
		p = pivot + y * q;
		n = y * nn;
	} else if (part == 3) {
		mat3 r = vc_rot_x(-anim.z / max(extra, 0.05));
		p = rot_axis_apply(r, pivot, p);
		n = r * n;
	} else if (part == 5 || part == 7) {
		float rate = (part == 7 && extra > 0.01) ? extra : 1.0;
		mat3 r = vc_rot_y(aux.z * rate);
		p = rot_axis_apply(r, pivot, p);
		n = r * n;
	} else if (part == 6) {
		mat3 r = vc_rot_x(aux.z * 1.7);
		p = rot_axis_apply(r, pivot, p);
		n = r * n;
	} else if (part >= 8 && part <= 12) {
		float stride = extra > 0.01 ? extra : 0.9;
		float ph = anim.z * VC_TAU / stride + param * VC_TAU;
		float sw = sin(ph) * anim.y * 0.75;
		float ang = 0.0;
		if (part == 8) ang = sw;
		else if (part == 9) ang = -sw;
		else if (part == 10) ang = -sw * 0.8;
		else if (part == 11) ang = sw * 0.8;
		if (part != 12) {
			mat3 r = vc_rot_x(ang);
			p = rot_axis_apply(r, pivot, p);
			n = r * n;
		}
		p.y += abs(sin(ph)) * 0.035 * anim.y;
		if ((flags & UF_SUPPRESSED) != 0 && part >= 10) {
			p.y -= 0.22; // crouch: torso and arms drop
		}
		// squad members fall as hp drops: member i hides when hp fraction <= i / count (member 0 never hides)
		if (UV2.y > 0.5 && UV2.x > 0.5 && (1.0 - st.x) <= UV2.x / UV2.y) {
			p = vec3(0.0, -50.0, 0.0);
		}
	} else if (part == 13 || part == 17) {
		p.y += aux.y * extra;
	} else if (part == 18) {
		p.z += aux.y * extra;
	} else if (part == 15 || part == 16) {
		float a = aux.y * (param * 2.0 - 1.0) * 2.2;
		mat3 r = part == 15 ? vc_rot_x(a) : vc_rot_z(a);
		p = rot_axis_apply(r, pivot, p);
		n = r * n;
	}

	p.y -= anim.x; // structure construction sink
	if ((flags & UF_SUBMERGED) != 0) {
		p.y -= 0.3;
	}

	float fogf = 1.0;
	if ((flags & UF_FOG_DIM) != 0) {
		fogf = fow_dim_factor(fow_state_nearest(MODEL_MATRIX[3].xz));
	}

	VERTEX = p;
	NORMAL = normalize(n);
	v_paint = vc_to_lin(COLOR.rgb);
	v_misc = vec4(COLOR.a, wear, ao, param);
	v_uv = UV;
	v_anim = anim;
	v_state = vec4(st.x, st.y, fogf, st.w);
	v_kind = vec2(float(mat_id), float(part));
	v_flags = vec3(float(flags), cloak, burn);
}

void fragment() {
	int mat_id = int(v_kind.x + 0.5);
	int part = int(v_kind.y + 0.5);
	int flags = int(v_flags.x + 0.5);
	bool wreck = (flags & UF_WRECK) != 0;
	vec3 paint = v_paint;
	float team_mask = wreck ? 0.0 : v_misc.x;
	float wear_mask = v_misc.y;
	float ao = v_misc.z;
	vec3 P = v_opos;

	float n_lo = 0.5;
	float n_hi = 0.5;
	if (quality > 0.5) {
		n_lo = vc_vnoise(P * 2.3 + vec3(11.0));
		n_hi = vc_vnoise(P * 9.0 + vec3(3.7));
	}

	vec3 albedo = paint * (0.9 + 0.2 * n_lo);
	float metallic = 0.0;
	float rough = 0.6;
	float spec = 0.5;
	vec3 emis = vec3(0.0);
	float night = 1.0 + 1.2 * atm_night;

	if (mat_id == 0) {
		// PAINT
		float luma = dot(paint, vec3(0.3, 0.55, 0.15));
		albedo = mix(albedo, team_color * (0.30 + 0.9 * luma + 0.10), team_mask);
		rough = 0.5 + 0.18 * n_hi;
		metallic = 0.04;
		float cell = mix(0.45, 1.4, v_misc.w);
		float pl = panel_lines(v_uv, cell, 0.9) + 0.45 * panel_lines(v_uv + vec2(7.3), cell * 0.33, 0.7);
		albedo *= 1.0 - clamp(pl, 0.0, 1.0) * 0.5 * panel_amount;
		if (wear_mask > 0.01) {
			float chip = smoothstep(0.34, 0.6, n_hi * 0.65 + vc_vnoise(P * 26.0) * 0.5 - 0.1) * wear_mask * wear_amount;
			albedo = mix(albedo * (1.0 + 0.3 * wear_mask), wear_color, chip);
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
		// RUBBER (tracks are part 4)
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
			float rate = (flags & UF_UNPOWERED) != 0 ? 0.225 : 0.9;
			blink = step(0.55, fract(fx_time * rate + v_misc.w));
		}
		albedo = paint * 0.15;
		emis = paint * emissive_strength * blink * night;
		if ((flags & UF_UNPOWERED) != 0) {
			emis *= mix(1.0, 0.2, v_anim.y);  // eased by ViewStructure over 0.4 s (batch path: constant 1 = dark)
		}
		rough = 0.4;
	}

	// dirt: heavier low on the model and on vertical / downward faces
	float lowness = smoothstep(1.1, 0.0, P.y);
	float dirt = lowness * dirt_amount * (0.3 + 0.9 * n_hi) * (0.55 + 0.45 * (1.0 - max(v_onrm.y, 0.0)));
	if (mat_id != 4 && mat_id != 2) {
		albedo = mix(albedo, dirt_color, clamp(dirt, 0.0, 0.85));
		rough = mix(rough, 0.95, clamp(dirt, 0.0, 1.0));
	}

	// damage: soot + embers
	float d = v_state.x;
	if (d > 0.001) {
		float soot = smoothstep(0.1, 0.85, d * (0.35 + 1.1 * n_lo + 0.5 * n_hi));
		albedo = mix(albedo, vec3(0.012), soot * (((flags & UF_STRUCT) != 0) ? 0.6 : 0.9));
		rough = mix(rough, 0.9, soot);
		metallic = mix(metallic, 0.0, soot);
		emis += vec3(1.0, 0.32, 0.05) * pow(n_hi, 9.0) * smoothstep(0.6, 1.0, d) * (((flags & UF_STRUCT) != 0) ? 0.8 : 2.4);
		if ((flags & UF_STRUCT) != 0) {
			// paint loss: armour plates flake off in blotches (a hide-by-hp mask that grows as hp falls) and cracks spread
			vec3 nn = normalize(v_onrm);
			vec2 pp = abs(nn.y) > 0.7 ? P.xz : (abs(nn.x) > abs(nn.z) ? P.zy : P.xy);
			float blot = vc_vnoise(P * 0.85 + vec3(4.1)) * 0.65 + vc_vnoise(P * 2.7 + vec3(9.3)) * 0.35;
			float thr = smoothstep(0.30, 1.0, d) * 0.46 + 0.05;
			float kept = smoothstep(thr - 0.012, thr + 0.02, blot);
			float lost = (1.0 - kept) * step(0.34, d);
			float edge = (1.0 - smoothstep(0.0, 0.022, abs(blot - thr - 0.004))) * step(0.34, d);
			albedo = mix(albedo, vec3(0.022, 0.02, 0.02), lost * 0.94);
			metallic = mix(metallic, 0.55, lost);
			rough = mix(rough, 0.62, lost);
			emis += vec3(1.0, 0.36, 0.06) * edge * smoothstep(0.75, 1.0, d) * (0.6 + 0.4 * sin(fx_time * 4.0 + P.x * 3.0)) * 0.3;
			// cellular cracks: distance to the nearest cell edge, only in patches the damage has reached (a low-frequency mask grows with d)
			if (quality > 0.5 && d > 0.15) {
				vec2 cp = pp * 0.5;
				vec2 ci = floor(cp);
				vec2 cf = fract(cp);
				float f1 = 8.0;
				float f2 = 8.0;
				for (int j = -1; j <= 1; j++) {
					for (int i = -1; i <= 1; i++) {
						vec2 g = vec2(float(i), float(j));
						vec2 o = vec2(vc_hash21(ci + g), vc_hash21(ci + g + vec2(17.0, 3.0)));
						float dd = length(g + o - cf);
						if (dd < f1) {
							f2 = f1;
							f1 = dd;
						} else if (dd < f2) {
							f2 = dd;
						}
					}
				}
				float cw = mix(0.010, 0.030, d);
				float patch = smoothstep(1.0 - d * 0.95, 1.0 - d * 0.95 + 0.2, vc_vnoise(P * 0.55 + vec3(2.7)) * 0.7 + n_lo * 0.3);
				float crack = (1.0 - smoothstep(cw, cw * 2.4, f2 - f1)) * patch;
				albedo = mix(albedo, vec3(0.008), crack * 0.9);
				emis += vec3(1.0, 0.3, 0.04) * crack * smoothstep(0.8, 1.0, d) * 0.25;
			}
		}
	}

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);

	// state flags
	if (wreck) {
		albedo *= 0.25;
		rough = 0.9;
		metallic *= 0.3;
		emis = vec3(1.0, 0.3, 0.05) * pow(n_hi, 10.0) * (0.5 + 0.5 * sin(fx_time * 3.0 + P.x * 7.0 + P.z * 5.0)) * 2.0 * v_flags.z;
		albedo *= mix(1.0, 0.62, v_flags.z);  // freshly burnt wrecks are blackest, they weather to charcoal grey
	}
	if ((flags & UF_SUBMERGED) != 0) {
		albedo = mix(albedo, vec3(0.03, 0.10, 0.18), 0.4);
		spec = 0.0;
	}
	if ((flags & UF_EMP) != 0) {
		float flick = step(0.62, fract(fx_time * 5.3 + vc_hash13(floor(P * 7.0))));
		albedo = mix(albedo, vec3(0.05, 0.25, 0.4), 0.25);
		emis += vec3(0.1, 0.7, 1.0) * flick * 0.5;
	}
	if ((flags & UF_DECOY_ID) != 0) {
		float scan = step(0.5, fract(P.y * 10.0 - fx_time * 1.5));
		albedo = mix(albedo, vec3(0.1, 0.8, 0.7), 0.35);
		emis += vec3(0.1, 1.0, 0.85) * (0.25 + 0.5 * scan);
	}
	float cloak = v_flags.y;
	if (cloak > 0.001) {
		float shim = 0.5 + 0.5 * vc_vnoise(P * 7.0 + vec3(0.0, fx_time * 1.3, 0.0));
		albedo *= mix(1.0, 0.35, cloak);
		emis += vec3(0.35, 0.6, 0.8) * cloak * (0.15 * shim + 1.4 * fres);
		rough = mix(rough, 0.2, cloak);
	}
	if ((flags & UF_GHOST) != 0) {
		// remembered structure: desaturated, dark, with a faint cold rim and slow scan bands so it never passes for a live building
		float lum = dot(albedo, vec3(0.3, 0.55, 0.15));
		albedo = mix(albedo, vec3(lum) * vec3(0.85, 0.95, 1.1), 0.78) * 0.5;
		float band = smoothstep(0.35, 0.5, abs(fract(P.y * 1.3 - fx_time * 0.15) - 0.5));
		emis = vec3(0.10, 0.22, 0.34) * (0.9 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0) + 0.10 * band + 0.05);
	}

	// selection rim + hit flash
	emis += rim_color * fres * v_state.y * 1.6;
	emis += (vec3(1.0, 0.85, 0.6) * 0.22 + albedo * 0.5) * v_state.w;  // a tint, not a white-out, in a 200-unit fight

	// neutral objects in explored-but-fogged cells (UF_FOG_DIM)
	albedo *= v_state.z;

#ifdef GHOST
	albedo = mix(albedo, ghost_tint, 0.45);
	emis = ghost_tint * 0.15;
	ALPHA = ghost_alpha;
#endif

	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emis;
	AO = ao;
	AO_LIGHT_AFFECT = 0.45;
}
