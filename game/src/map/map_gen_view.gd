class_name MapGenView
extends RefCounted
## View layers of a generated map (terrain_movement 5.14): lattice-corner heights (1/32 m), sea plane, decor variation.
## Roads (polylines) are recorded by MapGenLayout, moisture by phase A, shore distance by MapData.finalize. None of
## these enter map_hash (visual_hash only). Integer only.

const RAMP_LOW: int = -64  ## corner height at the map edge (-2 m), below every sea plane


## `height` = H 0..255 per cell, `plateau` = 1 on terraced cells (or empty), `t_water` = phase-A water threshold
## (-1000 = dry). Fills map.heights and map.water_level_u.
static func fill_heights(map: MapData, height: PackedByteArray, plateau: PackedByteArray, t_water: int) -> void:
	var w: int = map.w
	var h: int = map.h
	var eff: PackedInt32Array = PackedInt32Array()
	eff.resize(map.n)
	var has_plateau: bool = plateau.size() == map.n
	for i: int in map.n:
		var v: int = height[i]
		if has_plateau and plateau[i] != 0:
			v = ((v >> 5) << 5) + ((v & 31) >> 2)
		eff[i] = v
	var hs: PackedInt32Array = map.heights
	hs.resize((w + 1) * (h + 1))
	var rim: int = MapData.RIM_W
	for cy: int in h + 1:
		for cx: int in w + 1:
			var sum: int = 0
			var cnt: int = 0
			if cx > 0 and cy > 0:
				sum += eff[(cy - 1) * w + cx - 1]
				cnt += 1
			if cx < w and cy > 0:
				sum += eff[(cy - 1) * w + cx]
				cnt += 1
			if cx > 0 and cy < h:
				sum += eff[cy * w + cx - 1]
				cnt += 1
			if cx < w and cy < h:
				sum += eff[cy * w + cx]
				cnt += 1
			var v: int = 2 * sum / cnt
			var d: int = mini(mini(cx, cy), mini(w - cx, h - cy))
			if d < rim:
				v = RAMP_LOW + (v - RAMP_LOW) * d / rim
			hs[cy * (w + 1) + cx] = v
	map.water_level_u = 0 if t_water <= -1000 else maxi(1, 2 * t_water + 1)


## Decor variation byte on forest / rough / cliff / marsh cells (needs the derived `kind` layer: after finalize).
static func fill_deco(map: MapData) -> void:
	var s: int = map.deco_seed
	for i: int in map.n:
		var k: int = map.kind[i]
		if k == MapTerrain.TK_FOREST or k == MapTerrain.TK_ROUGH or k == MapTerrain.TK_CLIFF or k == MapTerrain.TK_MARSH:
			map.deco[i] = MapGenNoise.hash2(i % map.w, i / map.w, s) & 255
