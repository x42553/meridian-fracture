class_name ViewMinimap
extends RefCounted
## Two minimap sources for comparison (both get fog of war from the shared global texture via minimap_fog.gdshader):
##  A) SubViewport + orthographic top-down Camera3D re-rendering the real scene (shadows, water, trees).
##  B) CPU-painted Image: per-cell palette colour + hillshade, baked once per map, fog applied on the GPU.

var bake_ms: float = 0.0
var cpu_texture: ImageTexture
var viewport: SubViewport
var _cam: Camera3D


## B) One texel per cell. Colours follow the terrain palette so both minimaps agree with the world.
func bake_cpu(terrain: ViewTerrain, mood: ViewMoodDef) -> ImageTexture:
	var t0: int = Time.get_ticks_usec()
	var d: MapTerrainData = terrain.data
	var w: int = d.width
	var h: int = d.height
	var cw: int = w + 1
	var pal: Dictionary = mood.palette
	var grass: Color = (pal["dry_b"] as Color) if mood.dryness > 0.5 else (pal["grass_b"] as Color)
	var cols: Array[Color] = [grass.darkened(0.15), pal["dirt_b"], pal["rock_b"], pal["sand_b"], pal["snow_c"], Color(0.42, 0.20, 0.10), Color(0.20, 0.20, 0.22)]
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(w * h * 4)
	var light: Vector3 = Vector3(-0.55, 0.75, -0.45).normalized()
	var inv_m: float = 1.0 / float(MapTerrainData.HEIGHT_UNITS_PER_M)
	var wl: float = float(d.water_level_u) * inv_m
	for cy in h:
		for cx in w:
			var c: int = cy * w + cx
			var i00: int = cy * cw + cx
			var h00: float = float(d.heights[i00]) * inv_m
			var h10: float = float(d.heights[i00 + 1]) * inv_m
			var h01: float = float(d.heights[i00 + cw]) * inv_m
			var h11: float = float(d.heights[i00 + cw + 1]) * inv_m
			var dzdx: float = ((h10 + h11) - (h00 + h01)) * 0.5 / MapTerrainData.CELL_M
			var dzdz: float = ((h01 + h11) - (h00 + h10)) * 0.5 / MapTerrainData.CELL_M
			var shade: float = clampf(0.55 + 0.75 * Vector3(-dzdx * 2.2, 1.0, -dzdz * 2.2).normalized().dot(light), 0.35, 1.3)
			var col: Color
			if (d.flags[c] & MapTerrainData.F_WATER) != 0:
				var deep: float = clampf(float(d.shore_dist[c]) / 40.0, 0.0, 1.0)
				col = mood.water_shallow.lerp(mood.water_deep, deep)
				shade = 1.0
			else:
				col = cols[d.types[c]]
			var o: int = c * 4
			bytes[o] = clampi(int(col.r * shade * 255.0), 0, 255)
			bytes[o + 1] = clampi(int(col.g * shade * 255.0), 0, 255)
			bytes[o + 2] = clampi(int(col.b * shade * 255.0), 0, 255)
			bytes[o + 3] = 255
	cpu_texture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes))
	bake_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return cpu_texture


## A) Adds a SubViewport (sharing the host's World3D) with an orthographic top-down camera to `host`.
## Keep UPDATE_DISABLED / UPDATE_ONCE for a static minimap; UPDATE_ALWAYS re-renders the scene every frame.
func make_viewport(host: Node, map_size_m: Vector2, px: int) -> SubViewport:
	viewport = SubViewport.new()
	viewport.name = "MinimapViewport"
	viewport.size = Vector2i(px, px)
	viewport.own_world_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.use_debanding = true
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = map_size_m.x
	_cam.near = 1.0
	_cam.far = 900.0
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam.environment = env
	viewport.add_child(_cam)
	host.add_child(viewport)
	_cam.look_at_from_position(Vector3(map_size_m.x * 0.5, 500.0, map_size_m.y * 0.5), Vector3(map_size_m.x * 0.5, 0.0, map_size_m.y * 0.5), Vector3(0.0, 0.0, -1.0))
	return viewport


## Wraps a texture in a TextureRect with the fog-of-war canvas shader.
static func make_rect(tex: Texture2D, size_px: Vector2, map_size_m: Vector2) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = size_px
	r.size = size_px
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://shaders/minimap_fog.gdshader")
	m.set_shader_parameter("map_size", map_size_m)
	r.material = m
	return r
