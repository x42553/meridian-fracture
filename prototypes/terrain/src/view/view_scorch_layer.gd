class_name ViewScorchLayer
extends RefCounted
## Persistent scorch marks / craters as a CPU-painted RGBA8 overlay (RGB tint, A opacity) sampled by the terrain
## shader. Cost is independent of the mark count (unlike Decal nodes): one blend_rect per mark + one texture upload
## per flush. Only affects terrain (not buildings/units), which is exactly what persistent battlefield damage needs.

var texture: ImageTexture
var resolution: int = 512
var painted: int = 0
var last_paint_us: int = 0
var last_flush_us: int = 0

var _img: Image
var _stamps: Array[Image] = []
var _stamp_px: PackedInt32Array = PackedInt32Array([14, 28, 56])
var _map_size: Vector2
var _dirty: bool = false


func setup(map_size_m: Vector2, res: int = 512) -> void:
	_map_size = map_size_m
	resolution = res
	_img = Image.create_empty(res, res, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(_img)
	for i in _stamp_px.size():
		_stamps.append(make_stamp_image(_stamp_px[i], 31 + i))


## Radial scorch with irregular edge and a lighter debris rim (also reused for the Decal textures).
static func make_stamp_image(size: int, seed_v: int) -> Image:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 3.5 / float(size)
	n.fractal_octaves = 3
	var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half: float = float(size) * 0.5
	for y in size:
		for x in size:
			var dx: float = (float(x) + 0.5 - half) / half
			var dy: float = (float(y) + 0.5 - half) / half
			var d: float = sqrt(dx * dx + dy * dy) + n.get_noise_2d(float(x), float(y)) * 0.30
			var a: float = (1.0 - smoothstep(0.45, 1.0, d)) * 0.96
			var rim: float = smoothstep(0.50, 0.68, d) * (1.0 - smoothstep(0.68, 0.92, d))
			var col: Color = Color(0.045, 0.04, 0.036).lerp(Color(0.19, 0.14, 0.10), rim * 0.75)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return img


## Paints one mark. radius_m is the visual radius in metres.
func paint(world_xz: Vector2, radius_m: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var px_per_m: float = float(resolution) / _map_size.x
	var want: float = radius_m * 2.0 * px_per_m
	var pick: int = 0
	for i in _stamp_px.size():
		if float(_stamp_px[i]) <= want * 1.25:
			pick = i
	var s: int = _stamp_px[pick]
	var cx: int = int(world_xz.x * px_per_m) - s / 2
	var cy: int = int(world_xz.y * px_per_m) - s / 2
	_img.blend_rect(_stamps[pick], Rect2i(0, 0, s, s), Vector2i(cx, cy))
	_dirty = true
	painted += 1
	last_paint_us = Time.get_ticks_usec() - t0


## Uploads the layer if anything changed (call at most a few times per second).
func flush() -> void:
	if not _dirty:
		return
	var t0: int = Time.get_ticks_usec()
	texture.update(_img)
	_dirty = false
	last_flush_us = Time.get_ticks_usec() - t0
