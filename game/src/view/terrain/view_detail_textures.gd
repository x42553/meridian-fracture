class_name ViewDetailTextures
extends RefCounted
## Tileable procedural detail data built at boot from stock FastNoiseLite (no external art).
##   detail  (RGBA8, mipmapped): R fbm low, G fbm high, B cellular crack edges (F2-F1), A cellular cell value.
##   normals (RGBA8, mipmapped): RG = ground bump normal xy, BA = rock bump normal xy.
## Two textures cover every terrain layer, water waves/foam, caustics and cloud shadows.

var detail: ImageTexture
var normals: ImageTexture
var build_ms: float = 0.0


static func build(size: int = 256) -> ViewDetailTextures:
	var t0: int = Time.get_ticks_usec()
	var out: ViewDetailTextures = ViewDetailTextures.new()
	var r: PackedByteArray = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 101, 0.011, 4, FastNoiseLite.FRACTAL_FBM, size, -1)
	var g: PackedByteArray = _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 202, 0.046, 3, FastNoiseLite.FRACTAL_FBM, size, -1)
	var b: PackedByteArray = _noise(FastNoiseLite.TYPE_CELLULAR, 303, 0.032, 1, FastNoiseLite.FRACTAL_NONE, size, FastNoiseLite.RETURN_DISTANCE2_SUB)
	var a: PackedByteArray = _noise(FastNoiseLite.TYPE_CELLULAR, 404, 0.032, 1, FastNoiseLite.FRACTAL_NONE, size, FastNoiseLite.RETURN_CELL_VALUE)
	var px: PackedByteArray = PackedByteArray()
	px.resize(size * size * 4)
	for p: int in size * size:
		var o: int = p * 4
		px[o] = r[p]
		px[o + 1] = g[p]
		px[o + 2] = b[p]
		px[o + 3] = a[p]
	var img: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, px)
	img.generate_mipmaps()
	out.detail = ImageTexture.create_from_image(img)

	var ground: PackedByteArray = _normal_bytes(_noise_image(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 505, 0.05, 4, FastNoiseLite.FRACTAL_FBM, size, -1), 3.0)
	var rock: PackedByteArray = _normal_bytes(_noise_image(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 606, 0.024, 5, FastNoiseLite.FRACTAL_RIDGED, size, -1), 5.0)
	var npx: PackedByteArray = PackedByteArray()
	npx.resize(size * size * 4)
	for p: int in size * size:
		var o: int = p * 4
		npx[o] = ground[o]
		npx[o + 1] = ground[o + 1]
		npx[o + 2] = rock[o]
		npx[o + 3] = rock[o + 1]
	var nimg: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, npx)
	nimg.generate_mipmaps()
	out.normals = ImageTexture.create_from_image(nimg)
	out.build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return out


static func _noise_image(type: int, seed_v: int, freq: float, octaves: int, fractal: int, size: int, cell_ret: int) -> Image:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = type as FastNoiseLite.NoiseType
	n.seed = seed_v
	n.frequency = freq
	n.fractal_type = fractal as FastNoiseLite.FractalType
	n.fractal_octaves = octaves
	if cell_ret >= 0:
		n.cellular_return_type = cell_ret as FastNoiseLite.CellularReturnType
		n.cellular_jitter = 1.0
	var img: Image = n.get_seamless_image(size, size, false, false, 0.1, true)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img


static func _noise(type: int, seed_v: int, freq: float, octaves: int, fractal: int, size: int, cell_ret: int) -> PackedByteArray:
	return _noise_image(type, seed_v, freq, octaves, fractal, size, cell_ret).get_data()


## Bump (L8) -> RGBA8 normal-map bytes, wrapping at the tile edge.
static func _normal_bytes(bump: Image, strength: float) -> PackedByteArray:
	var img: Image = bump.duplicate()
	img.bump_map_to_normal_map(strength)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img.get_data()
