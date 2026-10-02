class_name ViewScorchLayer
extends RefCounted
## Persistent battlefield damage as a CPU-painted RGBA8 overlay (RGB tint, A opacity) sampled by the terrain shader (render spec
## 5.5 "Scorch/tread layer"): scorch marks, craters, rubble stains and vehicle tread marks. Cost is independent of the mark count
## (unlike Decal nodes): one Image.blend_rect per mark (2-4 us) plus one texture upload per `flush` (0.65-1.2 ms, at <= 2 Hz).
## Only affects terrain, works on every renderer. Presentation only: called from the FX event router and the unit backend.

enum Kind { SCORCH, CRATER, TREAD, RUBBLE_STAIN }

const STAMP_PX: Array[int] = [12, 24, 48, 96]
const TREAD_ALPHA: float = 0.16

var texture: ImageTexture = null
var resolution: int = 1024
var painted: int = 0
var last_paint_us: int = 0
var last_flush_us: int = 0
var flushes: int = 0

var _img: Image = null
var _stamps: Array = []  # per Kind: Array[Image] by STAMP_PX index (TREAD: built on demand in _tread)
var _tread: Dictionary = {}  # px -> Image
var _map_size: Vector2 = Vector2(576.0, 576.0)
var _dirty: bool = false


func setup(map_size_m: Vector2, res: int = 1024) -> void:
	_map_size = map_size_m
	resolution = res
	_img = Image.create_empty(res, res, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(_img)
	_stamps.clear()
	_tread.clear()
	for kind: int in Kind.size():
		var per_size: Array[Image] = []
		if kind != Kind.TREAD:
			for i: int in STAMP_PX.size():
				per_size.append(make_stamp_image(kind, STAMP_PX[i], 31 + i + kind * 7))
		_stamps.append(per_size)


## Stamp image of one kind: SCORCH radial black with a lighter debris rim, CRATER dark bowl with a raised light rim,
## RUBBLE_STAIN soft brown-grey blotch, TREAD soft dark dot. Irregular edge from FastNoiseLite.
static func make_stamp_image(kind: int, size: int, seed_v: int) -> Image:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 3.5 / float(maxi(size, 4))
	n.fractal_octaves = 3
	var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half: float = float(size) * 0.5
	for y: int in size:
		for x: int in size:
			var dx: float = (float(x) + 0.5 - half) / half
			var dy: float = (float(y) + 0.5 - half) / half
			var r: float = sqrt(dx * dx + dy * dy)
			var d: float = r + n.get_noise_2d(float(x), float(y)) * (0.12 if kind == Kind.TREAD else 0.30)
			var col: Color = Color(0.045, 0.04, 0.036)
			var a: float = 0.0
			match kind:
				Kind.SCORCH:
					# soot: sharp irregular edge, darkest in the middle, a faint lighter debris fringe
					a = (1.0 - smoothstep(0.58, 0.93, d))
					var fringe: float = smoothstep(0.55, 0.75, d) * (1.0 - smoothstep(0.75, 0.95, d))
					col = Color(0.008, 0.007, 0.007).lerp(Color(0.05, 0.042, 0.035), smoothstep(0.1, 0.8, d)).lerp(Color(0.16, 0.12, 0.09), fringe * 0.45)
				Kind.CRATER:
					a = (1.0 - smoothstep(0.66, 0.96, d))
					var ring: float = smoothstep(0.52, 0.70, d) * (1.0 - smoothstep(0.70, 0.92, d))
					col = Color(0.02, 0.016, 0.013).lerp(Color(0.06, 0.048, 0.038), smoothstep(0.1, 0.5, d)).lerp(Color(0.30, 0.23, 0.17), ring * 0.85)
				Kind.RUBBLE_STAIN:
					a = (1.0 - smoothstep(0.25, 1.0, d)) * 0.62
					col = Color(0.20, 0.17, 0.15).lerp(Color(0.30, 0.27, 0.24), smoothstep(0.4, 0.9, d))
				_:
					a = (1.0 - smoothstep(0.35, 1.0, d)) * TREAD_ALPHA
					col = Color(0.035, 0.03, 0.026)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return img


## Paints one mark. `radius_m` is the visual radius in metres; the stamp size is the largest one that is at most 1.25x the
## wanted pixel diameter (the smallest when none is). TREAD kind paints a single dot of that radius.
func paint(world_xz: Vector2, radius_m: float, kind: int = Kind.SCORCH) -> void:
	var t0: int = Time.get_ticks_usec()
	var px_per_m: float = float(resolution) / _map_size.x
	var want: float = radius_m * 2.0 * px_per_m
	var s: int = 0
	var stamp: Image = null
	if kind == Kind.TREAD:
		s = clampi(roundi(want), 3, 16)
		stamp = _tread_stamp(s)
	else:
		var pick: int = 0
		for i: int in STAMP_PX.size():
			if float(STAMP_PX[i]) <= want * 1.25:
				pick = i
		s = STAMP_PX[pick]
		stamp = (_stamps[clampi(kind, 0, Kind.size() - 1)] as Array)[pick] as Image
	var cx: int = int(world_xz.x * px_per_m) - s / 2
	var cy: int = int(world_xz.y * float(resolution) / _map_size.y) - s / 2
	_img.blend_rect(stamp, Rect2i(0, 0, s, s), Vector2i(cx, cy))
	_dirty = true
	painted += 1
	last_paint_us = Time.get_ticks_usec() - t0


## Tread marks: soft dots of `width_m` along the segment a -> b (one mark per vehicle every ~1.2 m travelled, never on roads).
func paint_tread(a_xz: Vector2, b_xz: Vector2, width_m: float) -> void:
	var seg_len: float = a_xz.distance_to(b_xz)
	var step: float = maxf(width_m * 0.75, 0.3)
	var n: int = maxi(1, ceili(seg_len / step))
	for i: int in n:
		paint(a_xz.lerp(b_xz, (float(i) + 0.5) / float(n)), width_m * 0.5, Kind.TREAD)


## Uploads the layer when anything was painted (call at most a few times per second). True when an upload happened.
func flush() -> bool:
	if not _dirty:
		return false
	var t0: int = Time.get_ticks_usec()
	texture.update(_img)
	_dirty = false
	flushes += 1
	last_flush_us = Time.get_ticks_usec() - t0
	return true


## Opacity (0..255 scale 0..1) at a world position (test hook).
func alpha_at(world_xz: Vector2) -> float:
	var x: int = clampi(int(world_xz.x * float(resolution) / _map_size.x), 0, resolution - 1)
	var y: int = clampi(int(world_xz.y * float(resolution) / _map_size.y), 0, resolution - 1)
	return _img.get_pixel(x, y).a


func _tread_stamp(px: int) -> Image:
	if not _tread.has(px):
		_tread[px] = make_stamp_image(Kind.TREAD, px, 97 + px)
	return _tread[px] as Image
