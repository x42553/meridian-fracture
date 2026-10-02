class_name MapTerrainGen
extends RefCounted
## Deterministic procedural terrain (integer math only, identical on every platform for a seed):
## rolling hills, sea border, lake + river, mountain range, a cliff-ringed mesa with a ramp,
## a flattened start plateau, asphalt roads, salvage fields and a shore-distance field.
## Feature layout is expressed in percent of the map size so it scales from 96 to 256 cells.

const M: int = MapTerrainData.HEIGHT_UNITS_PER_M


static func _q8(size: int, pct: int) -> int:
	return size * pct / 100 * 256


static func generate(seed_value: int, w: int, h: int) -> MapTerrainData:
	var d: MapTerrainData = MapTerrainData.new()
	d.width = w
	d.height = h
	d.seed_value = seed_value
	var cw: int = w + 1
	var ch: int = h + 1
	var f_base: MapFbm = MapFbm.new().setup(seed_value + 11, w, h, 64, 4)
	var f_det: MapFbm = MapFbm.new().setup(seed_value + 23, w, h, 10, 2)
	var f_warp: MapFbm = MapFbm.new().setup(seed_value + 37, w, h, 20, 2)
	var f_ridge: MapFbm = MapFbm.new().setup(seed_value + 41, w, h, 34, 3)
	var f_moist: MapFbm = MapFbm.new().setup(seed_value + 53, w, h, 32, 3)
	var f_patch: MapFbm = MapFbm.new().setup(seed_value + 67, w, h, 9, 2)

	# --- feature layout (Q8 cells) ---
	var lake_x: int = _q8(w, 30)
	var lake_y: int = _q8(h, 61)
	var lake_r: int = w * 115 / 1000 * 256
	var mtn_x: int = _q8(w, 78)
	var mtn_y: int = _q8(h, 25)
	var mtn_r: int = _q8(w, 25)
	var mesa_x: int = _q8(w, 72)
	var mesa_y: int = _q8(h, 66)
	var mesa_r: int = w * 125 / 1000 * 256
	var ba_x: int = _q8(w, 24)
	var ba_y: int = _q8(h, 24)
	var arid_x: int = _q8(w, 55)
	var arid_y: int = _q8(h, 85)
	var river: Array[Vector2i] = [
		Vector2i(_q8(w, 30), _q8(h, 61)), Vector2i(_q8(w, 39), _q8(h, 73)),
		Vector2i(_q8(w, 42), _q8(h, 86)), Vector2i(_q8(w, 51), _q8(h, 99))]

	# --- corner heights ---
	d.heights.resize(cw * ch)
	for cy in ch:
		for cx in cw:
			var i: int = cy * cw + cx
			var x: int = cx * 256
			var y: int = cy * 256
			var warp: int = f_warp.sample_q8(x, y) - 32768
			var hu: int = 6 * M + ((f_base.sample_q8(x, y) - 32768) * 22 * M) / 65536
			var det: int = f_det.sample_q8(x, y) - 32768
			hu += (det * M) / 65536

			# Mountain range: additive ridged noise under a warped radial mask.
			var dx: int = x - mtn_x
			var dy: int = y - mtn_y
			if absi(dx) < mtn_r and absi(dy) < mtn_r:
				var md: int = MapNoise.isqrt(dx * dx + dy * dy) + (warp * 10 * 256) / 65536
				var mask: int = 65536 - MapNoise.smooth_q16(md, mtn_r / 4, mtn_r)
				if mask > 0:
					var rv: int = f_ridge.sample_q8(x, y)
					var ridge: int = clampi(65535 - absi(2 * rv - 65535) * 3, 0, 65535)
					var m2: int = (mask * mask) >> 16
					hu += (m2 * (3 * M + (ridge * 30 * M) / 65536)) / 65536

			# Mesa: flat top ringed by a ~1.5 cell cliff band, with a ramp corridor on the west side.
			var ex: int = x - mesa_x
			var ey: int = y - mesa_y
			var lim: int = mesa_r + 5 * 256
			if absi(ex) < lim and absi(ey) < lim:
				var ed: int = MapNoise.isqrt(ex * ex + ey * ey) + (warp * 4 * 256) / 65536
				var mt: int = MapNoise.smooth_q16(ed, mesa_r - 154, mesa_r + 231)
				var top: int = 15 * M + (det * M) / 262144
				var mesa_h: int = MapNoise.lerp_q16(top, hu, mt)
				var rx0: int = mesa_x - mesa_r - 14 * 256
				var rw: int = 65536 - MapNoise.smooth_q16(absi(ey), 460, 1075)
				if rw > 0 and x > rx0:
					var t_along: int = MapNoise.smooth_q16(x, rx0, mesa_x - mesa_r + 4 * 256)
					mesa_h = MapNoise.lerp_q16(mesa_h, MapNoise.lerp_q16(hu, top, t_along), rw)
				hu = mesa_h

			# Flattened start plateau.
			var bx: int = x - ba_x
			var by: int = y - ba_y
			if absi(bx) < 21 * 256 and absi(by) < 21 * 256:
				var bd: int = MapNoise.isqrt(bx * bx + by * by)
				hu = MapNoise.lerp_q16(hu, 5 * M, 65536 - MapNoise.smooth_q16(bd, 9 * 256, 20 * 256))

			# Lake basin and river channel (only ever lower the terrain).
			var lx: int = x - lake_x
			var ly: int = y - lake_y
			var llim: int = lake_r + 24 * 256
			if absi(lx) < llim and absi(ly) < llim:
				var ld: int = MapNoise.isqrt(lx * lx + ly * ly) + (warp * 12 * 256) / 65536
				var lt: int = MapNoise.smooth_q16(ld, lake_r - 7 * 256, lake_r + 4 * 256)
				hu = mini(hu, MapNoise.lerp_q16(-6 * M, hu, lt))
			if x > lake_x - 10 * 256 and y > lake_y - 10 * 256:
				var rd: int = 1 << 30
				for s in 3:
					rd = mini(rd, MapNoise.dist_point_segment(x, y, river[s].x, river[s].y, river[s + 1].x, river[s + 1].y))
				rd += (warp * 3 * 256) / 65536
				var rt: int = 65536 - MapNoise.smooth_q16(rd, 384, 1280)
				if rt > 0:
					hu = mini(hu, MapNoise.lerp_q16(hu, -3 * M, rt))

			# Sea border with a wobbly coastline.
			var edge: int = mini(mini(cx, cy), mini(w - cx, h - cy)) * 256 + (warp * 9 * 256) / 65536
			hu = MapNoise.lerp_q16(-8 * M, hu, MapNoise.smooth_q16(edge, 5 * 256, 20 * 256))
			d.heights[i] = clampi(hu, -12 * M, 42 * M)

	# --- roads and salvage fields (layout in percent; roads stored in 1/16 cell) ---
	d.roads.append(_polyline(w, h, [24, 24, 32, 27, 40, 33, 46, 42, 49, 51, 52, 58, 55, 64, 60, 66, 68, 66]))
	d.roads.append(_polyline(w, h, [46, 42, 54, 38, 61, 34, 66, 32]))
	d.salvage_fields.append(Vector3i(w * 52 / 100, h * 31 / 100, w * 36 / 1000))
	d.salvage_fields.append(Vector3i(w * 48 / 100, h * 78 / 100, w * 40 / 1000))
	d.salvage_fields.append(Vector3i(w * 78 / 100, h * 47 / 100, w * 31 / 1000))
	d.salvage_fields.append(Vector3i(w * 18 / 100, h * 38 / 100, w * 31 / 1000))
	d.start_cells.append(Vector2i(w * 24 / 100, h * 24 / 100))
	d.start_cells.append(Vector2i(w * 72 / 100, h * 66 / 100))

	# --- per-cell classification ---
	d.types.resize(w * h)
	d.flags.resize(w * h)
	d.moisture.resize(w * h)
	var hs: PackedInt32Array = d.heights
	var arid_r0: int = w * 8 / 100 * 256
	var arid_r1: int = w * 26 / 100 * 256
	for cy in h:
		for cx in w:
			var c: int = cy * w + cx
			var i00: int = cy * cw + cx
			var h00: int = hs[i00]
			var h10: int = hs[i00 + 1]
			var h01: int = hs[i00 + cw]
			var h11: int = hs[i00 + cw + 1]
			var span: int = maxi(maxi(h00, h10), maxi(h01, h11)) - mini(mini(h00, h10), mini(h01, h11))
			var avg: int = (h00 + h10 + h01 + h11) / 4
			var x: int = cx * 256 + 128
			var y: int = cy * 256 + 128
			var mo: int = f_moist.sample_q8(x, y)
			var patch: int = f_patch.sample_q8(x, y)
			d.moisture[c] = mo >> 8
			var fl: int = 0
			var t: int = MapTerrainData.T_GRASS
			var ax: int = x - arid_x
			var ay: int = y - arid_y
			var arid: int = 65536 - MapNoise.smooth_q16(MapNoise.isqrt(ax * ax + ay * ay) + ((patch - 32768) * 6 * 256) / 65536, arid_r0, arid_r1)
			var mdx: int = x - mtn_x
			var mdy: int = y - mtn_y
			var m_in: int = 0
			if absi(mdx) < mtn_r and absi(mdy) < mtn_r:
				m_in = 65536 - MapNoise.smooth_q16(MapNoise.isqrt(mdx * mdx + mdy * mdy), mtn_r / 4, mtn_r)
			var near_start: bool = false
			for sc in d.start_cells:
				var sdx: int = cx - sc.x
				var sdy: int = cy - sc.y
				if sdx * sdx + sdy * sdy < 100:
					near_start = true
			if avg <= d.water_level_u:
				fl |= MapTerrainData.F_WATER
				t = MapTerrainData.T_SAND
			elif avg < (M * 9) / 10:
				t = MapTerrainData.T_SAND
			elif near_start:
				t = MapTerrainData.T_DIRT
			elif span >= (M * 3) / 2:
				t = MapTerrainData.T_ROCK
			elif m_in > 12000 and avg > 19 * M + ((patch - 32768) * 4 * M) / 65536:
				t = MapTerrainData.T_SNOW
			elif m_in > 12000 and avg > 10 * M:
				t = MapTerrainData.T_ROCK
			elif arid > 36000:
				t = MapTerrainData.T_SAND if patch > 26000 else MapTerrainData.T_DIRT
			elif mo < 22000 or patch < 9000:
				t = MapTerrainData.T_DIRT
			if span >= (M * 5) / 2:
				fl |= MapTerrainData.F_CLIFF
			d.types[c] = t
			d.flags[c] = fl

	for pl in d.roads:
		for k in range(0, pl.size() - 2, 2):
			var ax: int = pl[k] * 16
			var ay: int = pl[k + 1] * 16
			var bx: int = pl[k + 2] * 16
			var by: int = pl[k + 3] * 16
			var x0: int = maxi(0, (mini(ax, bx) >> 8) - 3)
			var x1: int = mini(w - 1, (maxi(ax, bx) >> 8) + 3)
			var y0: int = maxi(0, (mini(ay, by) >> 8) - 3)
			var y1: int = mini(h - 1, (maxi(ay, by) >> 8) + 3)
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					var c: int = cy * w + cx
					if MapNoise.dist_point_segment(cx * 256 + 128, cy * 256 + 128, ax, ay, bx, by) < 384 and (d.flags[c] & MapTerrainData.F_WATER) == 0:
						d.flags[c] = d.flags[c] | MapTerrainData.F_ROAD
						d.types[c] = MapTerrainData.T_ASPHALT

	for sf in d.salvage_fields:
		var r: int = sf.z
		for cy in range(maxi(0, sf.y - r - 3), mini(h, sf.y + r + 4)):
			for cx in range(maxi(0, sf.x - r - 3), mini(w, sf.x + r + 4)):
				var c: int = cy * w + cx
				var ddx: int = (cx - sf.x) * 256
				var ddy: int = (cy - sf.y) * 256
				var wob: int = f_patch.sample_q8(cx * 256, cy * 256) - 32768
				var dd: int = MapNoise.isqrt(ddx * ddx + ddy * ddy) + (wob * 3 * 256) / 65536
				if dd < r * 256 and (d.flags[c] & (MapTerrainData.F_WATER | MapTerrainData.F_ROAD)) == 0:
					d.flags[c] = d.flags[c] | MapTerrainData.F_SALVAGE
					d.types[c] = MapTerrainData.T_SALVAGE

	_compute_shore(d)
	return d


static func _polyline(w: int, h: int, pct: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k in range(0, pct.size(), 2):
		out.append(w * int(pct[k]) / 100 * 16)
		out.append(h * int(pct[k + 1]) / 100 * 16)
	return out


## 3-4 chamfer distance from land, in 1/3 cell, for water cells (deterministic int passes).
static func _compute_shore(d: MapTerrainData) -> void:
	var w: int = d.width
	var h: int = d.height
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(w * h)
	for c in w * h:
		dist[c] = (1 << 20) if (d.flags[c] & MapTerrainData.F_WATER) != 0 else 0
	for cy in h:
		for cx in w:
			var c: int = cy * w + cx
			var v: int = dist[c]
			if v == 0:
				continue
			if cx > 0:
				v = mini(v, dist[c - 1] + 3)
			if cy > 0:
				v = mini(v, dist[c - w] + 3)
				if cx > 0:
					v = mini(v, dist[c - w - 1] + 4)
				if cx < w - 1:
					v = mini(v, dist[c - w + 1] + 4)
			dist[c] = v
	for cy in range(h - 1, -1, -1):
		for cx in range(w - 1, -1, -1):
			var c: int = cy * w + cx
			var v: int = dist[c]
			if v == 0:
				continue
			if cx < w - 1:
				v = mini(v, dist[c + 1] + 3)
			if cy < h - 1:
				v = mini(v, dist[c + w] + 3)
				if cx < w - 1:
					v = mini(v, dist[c + w + 1] + 4)
				if cx > 0:
					v = mini(v, dist[c + w - 1] + 4)
			dist[c] = v
	d.shore_dist.resize(w * h)
	for c in w * h:
		d.shore_dist[c] = mini(dist[c], 255)
