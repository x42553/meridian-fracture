shader_type spatial;
// Ground overlay rings / brackets (render spec 4.7, 5.10). One quad in XZ spanning [-1, 1], one MultiMesh instance per ring:
//   instance transform = terrain-aligned basis * scale(sx, 1, sz) at the ground point (lifted by the CPU)
//   COLOR (rgb sRGB, a = opacity)   INSTANCE_CUSTOM = (a, b, style, seed)
//   mode 0 SELECT_RING : a = unused, b = unused. Outline ring at 0.9 of the quad, 4 gaps.
//   mode 1 SELECT_RECT : corner brackets; a, b = rectangle half extents in metres, seed = arm length m (quad = rectangle + margin)
// style (custom.z): 0 selection, 1 hover (thin, translucent), 2 aura (soft pulse)
// Modes 2-5, 7, 8 (range, build radius, warnings, ping, zone discs) belong to VIEW-O2/O3.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://assets/shaders/view_common.gdshaderinc"

uniform int mode = 0;
uniform float pull_m = 0.15;   // vertex pull toward the camera against z-fighting on slopes
uniform float intensity = 0.75;  // compensates the tone mapper so overlay colours stay saturated
uniform float margin = 0.25;  // metres of quad around a SELECT_RECT rectangle (room for the halo)

varying vec2 v_p;
varying vec4 v_col;
varying vec4 v_cus;

void vertex() {
	v_p = VERTEX.xz;
	v_col = COLOR;
	v_cus = INSTANCE_CUSTOM;
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vp -= normalize(vp) * pull_m;
	VERTEX = vp;
}

float band(float c, float lo, float hi, float aa) {
	return smoothstep(lo - aa, lo, c) * (1.0 - smoothstep(hi - aa, hi, c));
}

void fragment() {
	vec2 p = v_p;
	float style = v_cus.z;
	float a = 0.0;
	float shadow = 0.0;
	if (mode == 0) {
		float r = length(p);
		float aa = max(fwidth(r), 0.0005);
		float stroke = style > 1.5 ? 0.12 : (style > 0.5 ? 0.05 : 0.10);
		stroke = max(stroke, aa * 3.4);
		float outer = 0.9;
		float ring = smoothstep(outer - stroke - aa, outer - stroke, r) * (1.0 - smoothstep(outer - aa, outer, r));
		// dark halo around the stroke for contrast on bright ground
		float halo = smoothstep(outer - stroke - aa * 3.5, outer - stroke - aa, r) * (1.0 - smoothstep(outer + aa, outer + aa * 3.5, r));
		halo = max(halo - ring, 0.0);
		// four gaps on the diagonals (selection only)
		float g = abs(fract(atan(p.y, p.x) / VC_TAU * 4.0) - 0.5);
		float gap = style > 0.5 ? 1.0 : smoothstep(0.045, 0.085, g);
		a = ring * gap;
		shadow = halo * gap * 0.55;
		if (style > 1.5) {
			float pulse = 0.6 + 0.4 * sin(view_time * 3.0 + v_cus.w * 6.0);
			float soft = smoothstep(0.35, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
			a = max(a * pulse, soft * 0.35 * pulse);
			shadow = 0.0;
		}
	} else {
		vec2 hxz = v_cus.xy;
		vec2 m = p * (hxz + vec2(margin));
		vec2 c = hxz - abs(m);           // negative outside the rectangle
		float arm = max(v_cus.w, 0.4);
		float aa = max(fwidth(m.x), 0.001);
		float thick = max(0.16, aa * 3.2);
		a = max(band(c.x, 0.0, thick, aa) * band(c.y, 0.0, arm, aa), band(c.y, 0.0, thick, aa) * band(c.x, 0.0, arm, aa));
		float hl = 0.09;
		float sh = max(band(c.x, -hl, thick + hl, aa) * band(c.y, -hl, arm + hl, aa), band(c.y, -hl, thick + hl, aa) * band(c.x, -hl, arm + hl, aa));
		shadow = max(sh - a, 0.0) * 0.55;
		if (style > 0.5) {
			a *= 0.7;
		}
	}
	vec3 col = vc_to_lin(v_col.rgb) * intensity;
	float alpha = a * v_col.a;
	float dark = shadow * v_col.a;
	if (alpha + dark < 0.004) {
		discard;
	}
	// premultiplied output: coloured stroke over a translucent dark halo
	ALBEDO = col * alpha;
	ALPHA = alpha + dark * (1.0 - alpha);
}
