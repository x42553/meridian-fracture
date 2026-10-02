// Fog-of-war sampling shared by terrain, water, decor, unit and minimap shaders.
// The CPU feeds ONE byte per cell (0 = shroud, 1 = fog, 2 = visible) into an R8 texture at 10 Hz.
// Two textures ping-pong (prev / curr) so the GPU cross-fades the last update at frame rate.
// Globals are registered by ViewGlobals.ensure() before any material compiles (ViewFogOfWar writes them).
global uniform sampler2D fow_curr;
global uniform sampler2D fow_prev;
global uniform float fow_blend;      // 0..1 cross-fade prev -> curr
global uniform vec4 fow_rect;        // xy = map origin (m), zw = 1 / map size (1/m)
global uniform vec2 fow_cells;       // grid size in cells
global uniform float fow_fog_dim;    // 1: state 1 (fog) is dimmed, 0: state 1 renders like visible

float fow_cell_state(sampler2D t, ivec2 c) {
	ivec2 hi = ivec2(fow_cells) - ivec2(1);
	c = max(min(c, hi), ivec2(0));
	return floor(texelFetch(t, c, 0).r * 255.0 + 0.5);
}

// Smoothed (explored, visible) in 0..1 for one texture; bilinear over the decoded binary states.
vec2 fow_sample_one(sampler2D t, vec2 cellf) {
	vec2 p = cellf - 0.5;
	vec2 fl = floor(p);
	vec2 f = p - fl;
	ivec2 i0 = ivec2(fl);
	float s00 = fow_cell_state(t, i0);
	float s10 = fow_cell_state(t, i0 + ivec2(1, 0));
	float s01 = fow_cell_state(t, i0 + ivec2(0, 1));
	float s11 = fow_cell_state(t, i0 + ivec2(1, 1));
	vec2 w = f * f * (3.0 - 2.0 * f);
	float e = mix(mix(step(0.5, s00), step(0.5, s10), w.x), mix(step(0.5, s01), step(0.5, s11), w.x), w.y);
	float v = mix(mix(step(1.5, s00), step(1.5, s10), w.x), mix(step(1.5, s01), step(1.5, s11), w.x), w.y);
	return vec2(e, v);
}

// (explored, visible) at a world XZ position, cross-faded over the last update interval.
vec2 fow_sample(vec2 world_xz) {
	vec2 cellf = (world_xz - fow_rect.xy) * fow_rect.zw * fow_cells;
	return mix(fow_sample_one(fow_prev, cellf), fow_sample_one(fow_curr, cellf), fow_blend);
}

// Nearest-cell state 0 / 1 / 2 (no smoothing: agrees exactly with sim visibility). Used by UF_FOG_DIM.
float fow_state_nearest(vec2 world_xz) {
	vec2 cellf = (world_xz - fow_rect.xy) * fow_rect.zw * fow_cells;
	return fow_cell_state(fow_curr, ivec2(floor(cellf)));
}

// Brightness multiplier for a neutral object standing in a cell of the given state (UF_FOG_DIM).
float fow_dim_factor(float state) {
	if (state > 1.5) {
		return 1.0;
	}
	if (state > 0.5) {
		return mix(1.0, 0.45, fow_fog_dim);
	}
	return 0.45;
}
