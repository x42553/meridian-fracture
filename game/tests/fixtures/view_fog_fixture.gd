extends RefCounted
## Fog byte-grid fixtures for the VIEW-03 tests and labs (until the vision domain feeds SimFogApi): 0 shroud, 1 fog, 2 visible.


## w * h bytes: cells within `r_vis` of any centre (cell units) are visible, within `r_fog` explored, the rest shroud.
static func discs(w: int, h: int, centers: Array[Vector2i], r_vis: float, r_fog: float) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for cy: int in h:
		for cx: int in w:
			var best: float = 1.0e9
			for c: Vector2i in centers:
				best = minf(best, Vector2(float(cx - c.x), float(cy - c.y)).length())
			out[cy * w + cx] = 2 if best <= r_vis else (1 if best <= r_fog else 0)
	return out


static func uniform(w: int, h: int, state: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	out.fill(state)
	return out


## SimFogApi double serving fixed bytes with a version counter.
class Api extends SimFogApi:
	var bytes: PackedByteArray = PackedByteArray()
	var version: int = 0

	func set_bytes(b: PackedByteArray) -> void:
		bytes = b
		version += 1

	func fog_bytes(_pid: int) -> PackedByteArray:
		return bytes

	func fog_version(_pid: int) -> int:
		return version
