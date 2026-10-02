// Applies the shared fog-of-war state to a minimap texture (CPU-baked ViewMinimapSource or a SubViewport): shroud black,
// explored fogged / desaturated, visible untouched. Same cell smoothing as the world shaders, so both agree.
shader_type canvas_item;

#include "res://assets/shaders/fog_of_war.gdshaderinc"

uniform vec2 map_size = vec2(576.0);
uniform float fow_enabled = 1.0;

void fragment() {
	if (fow_enabled > 0.5) {
		vec2 fs = fow_sample(fow_rect.xy + UV * map_size);
		float e = smoothstep(0.32, 0.68, fs.x);
		float v = smoothstep(0.32, 0.68, fs.y);
		vec3 c = COLOR.rgb;
		float luma = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 fogged = mix(mix(vec3(luma), c, 0.5) * 0.45, c, 1.0 - fow_fog_dim);
		COLOR.rgb = mix(fogged, c, v) * e;
	}
}
