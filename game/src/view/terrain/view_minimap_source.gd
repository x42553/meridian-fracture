class_name ViewMinimapSource
extends RefCounted
## In-game minimap texture (render spec 3.4 / 5.5): one texel per cell, terrain palette x hillshade, water tinted by the shore
## distance, deposit cells gold (re-tinted when they deplete). Baked once per map (CPU, ~20-100 ms at 192-256 cells) and shown by
## the UI through `make_material()` (minimap_fog.gdshader = the world's fog state). Unit dots and the camera quad are drawn by the
## UI. Presentation only.

const SHADER_PATH: String = "res://assets/shaders/minimap_fog.gdshader"
const LIGHT: Vector3 = Vector3(-0.55, 0.75, -0.45)
const GOLD: Color = Color(0.95, 0.72, 0.16)
const UPLOAD_INTERVAL_S: float = 0.5  ## deposit re-tint uploads at <= 2 Hz

var texture: ImageTexture = null
var width: int = 0
var height: int = 0
var bake_ms: float = 0.0
var uploads: int = 0

var _size_m: Vector2 = Vector2(576.0, 576.0)
var _base: PackedByteArray = PackedByteArray()  # RGBA8 per cell, deposits not included
var _bytes: PackedByteArray = PackedByteArray()  # what the texture shows
var _dirty: bool = false
var _since_upload: float = 0.0


## One texel per cell. `src` supplies terrain ids, corner heights, shore distance, deposits; `mood` the palette and water colours.
func bake(src: ViewTerrainSource, mood: ViewMoodDef) -> ImageTexture:
	var t0: int = Time.get_ticks_usec()
	width = src.width
	height = src.height
	_size_m = src.size_m()
	var pal: Dictionary = mood.palette
	var arctic: bool = src.biome == 2
	var grass: Color = _pc(pal, "dry_b" if mood.dryness > 0.5 else "grass_b").darkened(0.12)
	var snow: Color = _pc(pal, "snow_c")
	var rock: Color = _pc(pal, "rock_b")
	var cols: Array[Color] = [
		mood.water_deep, mood.water_shallow, mood.water_shallow.lerp(_pc(pal, "sand_b"), 0.45), _pc(pal, "sand_b"),
		snow if arctic else grass, _pc(pal, "dirt_b"), _pc(pal, "sand_b"), rock,
		(snow.darkened(0.15) if arctic else grass.darkened(0.3)), Color(0.24, 0.24, 0.26), Color(0.5, 0.5, 0.52), Color(0.36, 0.31, 0.27),
		Color(0.42, 0.42, 0.47), _pc(pal, "rock_a").lightened(0.12), snow if arctic else rock, grass.lerp(Color(0.2, 0.4, 0.4), 0.35),
	]
	var w: int = width
	var h: int = height
	var light: Vector3 = LIGHT.normalized()
	_base = PackedByteArray()
	_base.resize(w * h * 4)
	for cy: int in h:
		for cx: int in w:
			var c: int = cy * w + cx
			var h00: float = src.corner_at(cx, cy)
			var h10: float = src.corner_at(cx + 1, cy)
			var h01: float = src.corner_at(cx, cy + 1)
			var h11: float = src.corner_at(cx + 1, cy + 1)
			var dzdx: float = ((h10 + h11) - (h00 + h01)) * 0.5 / ViewConsts.CELL_M
			var dzdz: float = ((h01 + h11) - (h00 + h10)) * 0.5 / ViewConsts.CELL_M
			var shade: float = clampf(0.55 + 0.75 * Vector3(-dzdx * 2.2, 1.0, -dzdz * 2.2).normalized().dot(light), 0.35, 1.3)
			var t: int = clampi(src.terrain[c], 0, cols.size() - 1)
			var col: Color = cols[t]
			if t <= ViewTerrainSource.T_SHALLOW:
				col = mood.water_shallow.lerp(mood.water_deep, clampf(float(src.shore_dist[c]) / 40.0, 0.0, 1.0)) if t == ViewTerrainSource.T_SHALLOW \
					else mood.water_shallow.lerp(mood.water_deep, clampf(0.35 + float(src.shore_dist[c]) / 40.0, 0.0, 1.0))
				shade = 1.0
			elif t == ViewTerrainSource.T_FORD:
				shade = 1.0
			_write(_base, c, col, shade)
	_bytes = _base.duplicate()
	var deps: PackedInt32Array = PackedInt32Array()
	src.deposit_cells(deps)
	for c: int in deps:
		_tint_deposit(src, c)
	texture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _bytes))
	_dirty = false
	bake_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return texture


## Re-tints deposit texels (gold -> base as the deposit depletes). Cells come from src.drain_deposit_changes. The texture is
## uploaded by `flush` (<= 2 Hz).
func update_deposits(src: ViewTerrainSource, cells: PackedInt32Array, n: int) -> void:
	for k: int in mini(n, cells.size()):
		_tint_deposit(src, cells[k])
	if n > 0:
		_dirty = true


## Uploads pending re-tints when at least UPLOAD_INTERVAL_S has passed since the last upload (`force` skips the wait).
## True when an upload happened. Call once per frame with the frame time.
func flush(dt: float = 0.0, force: bool = false) -> bool:
	_since_upload += dt
	if not _dirty or texture == null or (not force and _since_upload < UPLOAD_INTERVAL_S):
		return false
	texture.update(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, _bytes))
	_dirty = false
	_since_upload = 0.0
	uploads += 1
	return true


## canvas_item material applying the shared fog state; `local_fog` false = no fog (lobby preview, observers).
func make_material(local_fog: bool = true) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(SHADER_PATH) as Shader
	m.set_shader_parameter("map_size", _size_m)
	m.set_shader_parameter("fow_enabled", 1.0 if local_fog else 0.0)
	return m


## World position -> minimap UV (0..1, x right, v down = world z).
func world_to_uv(p: Vector3) -> Vector2:
	return Vector2(p.x / _size_m.x, p.z / _size_m.y)


func uv_to_world(uv: Vector2) -> Vector3:
	return Vector3(uv.x * _size_m.x, 0.0, uv.y * _size_m.y)


## RGBA of one cell as currently shown (test hook).
func texel(cx: int, cy: int) -> Color:
	var o: int = (cy * width + cx) * 4
	return Color8(_bytes[o], _bytes[o + 1], _bytes[o + 2], _bytes[o + 3])


func _tint_deposit(src: ViewTerrainSource, c: int) -> void:
	var f: float = src.deposit_fraction(c)
	var o: int = c * 4
	if f <= 0.0:
		for k: int in 4:
			_bytes[o + k] = _base[o + k]
		return
	var base: Color = Color8(_base[o], _base[o + 1], _base[o + 2])
	var col: Color = base.lerp(GOLD, 0.35 + 0.65 * f)
	_bytes[o] = clampi(int(col.r * 255.0), 0, 255)
	_bytes[o + 1] = clampi(int(col.g * 255.0), 0, 255)
	_bytes[o + 2] = clampi(int(col.b * 255.0), 0, 255)
	_bytes[o + 3] = 255


static func _write(buf: PackedByteArray, c: int, col: Color, shade: float) -> void:
	var o: int = c * 4
	buf[o] = clampi(int(col.r * shade * 255.0), 0, 255)
	buf[o + 1] = clampi(int(col.g * shade * 255.0), 0, 255)
	buf[o + 2] = clampi(int(col.b * shade * 255.0), 0, 255)
	buf[o + 3] = 255


static func _pc(pal: Dictionary, key: String) -> Color:
	var v: Variant = pal.get(key)
	return v as Color if v is Color else Color(0.5, 0.5, 0.5)
