class_name ViewLivery
extends RefCounted
## Subfaction livery post-pass (VQ2A). A subfaction style (`napc.usa`, `han.china`, ...) used to differ from its faction only by a
## slightly different accent and a few kit slots that most archetypes never expose, so a Raptor, a Beaver or a Buffalo of a
## subfaction could look identical to the vanilla model. After the recipe ran, this pass reads the static hull of the model
## (ViewMeshBuilder.static_vertices(): no turrets, wheels or tracks) and adds a livery that every unit archetype gets, independent of
## its recipe: a flank flash on both sides of ground vehicles and ships (a panel in the subfaction accent, framed in the secondary
## colour, carrying the style's `emblem` as dark bars / chevrons / ring / diamond / wedge / notch), and wing-tip flashes on aircraft.
## Pure geometry from data (`style.emblem`, `palette.acc / sec / dark`): deterministic, thread-safe, a few dozen triangles: the accent panel is tier 1 (24 LOD0 / LOD1 triangles per unit), frame and emblem are tier 2 (LOD0 only).
## Faction (vanilla) styles are not touched; infantry carry their insignia on the soldier macro.

const MIN_VERTS: int = 24


## Subfaction styles are the ones whose id has a dot ("napc.usa"); they must declare an emblem.
static func is_subfaction(style_id: String, style: Dictionary) -> bool:
	return style_id.contains(".") and str(style.get("emblem", "none")) != "none"


## Adds the livery of `style` to `b`. `arch_id` is the archetype id (veh_ / ship_ / air_ only), `pal` the palette (role -> Color).
static func apply(b: ViewMeshBuilder, style: Dictionary, style_id: String, arch_id: String, pal: Dictionary) -> Vector3i:
	if not is_subfaction(style_id, style):
		return Vector3i.ZERO
	var kind: int = 0
	if arch_id.begins_with("veh_") or arch_id.begins_with("ship_"):
		kind = 1
	elif arch_id.begins_with("air_"):
		kind = 2
	if kind == 0:
		return Vector3i.ZERO
	var sv: PackedVector3Array = b.static_vertices()
	if sv.size() < MIN_VERTS:
		return Vector3i.ZERO
	var emblem: String = str(style.get("emblem", "bar"))
	var acc: Color = pal.get("acc", Color(0.9, 0.5, 0.1)) as Color
	var sec: Color = pal.get("sec", Color(0.85, 0.85, 0.8)) as Color
	var dark: Color = pal.get("dark", Color(0.1, 0.1, 0.1)) as Color
	var before: Vector3i = b.tier_triangle_counts()
	b.clear_part()
	b.tier = 1
	if kind == 1:
		_flank(b, sv, emblem, acc, sec, dark)
	else:
		_wingtips(b, sv, acc, sec, dark)
	b.tier = 0
	return b.tier_triangle_counts() - before


# ---------------------------------------------------------------------------------------------- ground vehicles and ships
static func _flank(b: ViewMeshBuilder, sv: PackedVector3Array, emblem: String, acc: Color, sec: Color, dark: Color) -> void:
	# hull flank = the outermost static x (97th percentile, antennas and barrels are thinner than the hull)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	for v: Vector3 in sv:
		xs.append(absf(v.x))
		zs.append(v.z)
	xs.sort()
	zs.sort()
	var n: int = xs.size()
	var z0: float = zs[int(float(n) * 0.04)]
	var z1: float = zs[mini(int(float(n) * 0.96), n - 1)]
	var hull_len: float = z1 - z0
	# hull flank = the outermost static x (97th percentile: antennas and barrels are thinner than the hull); when that is only a thin
	# fender / skirt lip (vertical span < 0.3 m) fall back to the 88th and 75th percentile
	var xmax: float = 0.0
	var ylo: float = INF
	var yhi: float = -INF
	for q: float in [0.97, 0.88, 0.75]:
		xmax = xs[mini(int(float(n) * q), n - 1)]
		ylo = INF
		yhi = -INF
		for v: Vector3 in sv:
			if absf(v.x) > xmax * 0.9:
				ylo = minf(ylo, v.y)
				yhi = maxf(yhi, v.y)
		if yhi - ylo >= 0.3:
			break
	if xmax < 0.25 or hull_len < 0.8 or yhi - ylo < 0.3:
		return
	var h: float = clampf((yhi - ylo) * 0.5, 0.2, 0.5)
	var cy: float = ylo + (yhi - ylo) * 0.5
	var len: float = clampf(hull_len * 0.5, 0.7, 2.4)
	var cz: float = z0 + hull_len * 0.5
	for side: float in [-1.0, 1.0]:
		var x: float = side * (xmax + 0.012)
		b.tier = 2
		b.brush(sec)
		b.box(Vector3(x, cy, cz), Vector3(0.024, h + 0.08, len + 0.08), 0.0)
		b.tier = 1
		b.brush(acc)
		b.box(Vector3(x + side * 0.006, cy, cz), Vector3(0.024, h, len), 0.0)
		b.tier = 2
		_emblem(b, emblem, Vector3(x + side * 0.014, cy, cz), h, len, dark)


## The emblem as dark marks on the panel (x thickness 0.012 above the panel face, z along the hull).
static func _emblem(b: ViewMeshBuilder, emblem: String, c: Vector3, h: float, len: float, dark: Color) -> void:
	b.brush(dark)
	var th: float = 0.012
	var side: float = signf(c.x)
	match emblem:
		"triple_bar":
			for i: int in 3:
				b.box(Vector3(c.x, c.y, c.z + (float(i) - 1.0) * len * 0.26), Vector3(th, h * 0.8, len * 0.1), 0.0)
		"chevron", "double_chevron", "wedge":
			var reps: int = 2 if emblem == "double_chevron" else 1
			for r: int in reps:
				var oz: float = (float(r) - float(reps - 1) * 0.5) * len * 0.34
				for k: float in [-1.0, 1.0]:
					b.push(ViewMeshBuilder.xf(Vector3(c.x, c.y + k * h * 0.2, c.z + oz), Vector3(k * 38.0 * side, 0.0, 0.0)))
					b.box(Vector3.ZERO, Vector3(th, h * 0.12, len * 0.34 if emblem != "wedge" else len * 0.46), 0.0)
					b.pop()
		"ring":
			var rz: float = len * 0.22
			var rh: float = h * 0.36
			b.box(Vector3(c.x, c.y + rh, c.z), Vector3(th, h * 0.1, rz * 2.0), 0.0)
			b.box(Vector3(c.x, c.y - rh, c.z), Vector3(th, h * 0.1, rz * 2.0), 0.0)
			b.box(Vector3(c.x, c.y, c.z - rz), Vector3(th, rh * 2.0, h * 0.1), 0.0)
			b.box(Vector3(c.x, c.y, c.z + rz), Vector3(th, rh * 2.0, h * 0.1), 0.0)
		"diamond", "hex_notch":
			var d: float = minf(h * 0.8, len * 0.3)
			b.push(ViewMeshBuilder.xf(c, Vector3(45.0 * side, 0.0, 0.0)))
			b.box(Vector3.ZERO, Vector3(th, d * 0.7, d * 0.7), 0.0)
			b.pop()
			if emblem == "hex_notch":
				b.brush(Color(0.0, 0.0, 0.0, 1.0).lerp(dark, 0.5))
				b.box(Vector3(c.x + side * 0.004, c.y, c.z), Vector3(th, d * 0.2, d * 0.5), 0.0)
		"bar_notch":
			b.box(Vector3(c.x, c.y, c.z - len * 0.12), Vector3(th, h * 0.8, len * 0.42), 0.0)
			b.box(Vector3(c.x, c.y + h * 0.28, c.z + len * 0.3), Vector3(th, h * 0.24, len * 0.16), 0.0)
		_:
			b.box(Vector3(c.x, c.y, c.z), Vector3(th, h * 0.8, len * 0.3), 0.0)


# ---------------------------------------------------------------------------------------------------------------- aircraft
static func _wingtips(b: ViewMeshBuilder, sv: PackedVector3Array, acc: Color, sec: Color, dark: Color) -> void:
	var xmax: float = 0.0
	for v: Vector3 in sv:
		xmax = maxf(xmax, absf(v.x))
	if xmax < 0.6:
		return
	# the wing tip: vertices in the outer 22 % of the span
	for side: float in [-1.0, 1.0]:
		var ytop: float = -INF
		var zlo: float = INF
		var zhi: float = -INF
		for v: Vector3 in sv:
			if v.x * side > xmax * 0.78:
				ytop = maxf(ytop, v.y)
				zlo = minf(zlo, v.z)
				zhi = maxf(zhi, v.z)
		if ytop == -INF or zhi - zlo < 0.2:
			continue
		var zc: float = (zlo + zhi) * 0.5
		var ln: float = clampf((zhi - zlo) * 0.7, 0.3, 1.1)
		var x0: float = side * xmax * 0.80
		var x1: float = side * xmax * 0.995
		var cx: float = (x0 + x1) * 0.5
		var wd: float = absf(x1 - x0)
		b.tier = 2
		b.brush(sec)
		b.box(Vector3(cx, ytop + 0.006, zc), Vector3(wd + 0.06, 0.012, ln + 0.06), 0.0)
		b.tier = 1
		b.brush(acc)
		b.box(Vector3(cx, ytop + 0.014, zc), Vector3(wd, 0.012, ln), 0.0)
		b.tier = 2
		b.brush(dark)
		b.box(Vector3(cx, ytop + 0.022, zc), Vector3(wd * 0.5, 0.01, ln * 0.2), 0.0)
