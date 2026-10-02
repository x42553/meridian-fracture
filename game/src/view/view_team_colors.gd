class_name ViewTeamColors
extends RefCounted
## The 12 lobby colours (+4 derived), colour-blind palette modes, shape-pip ids and contrast helpers (render spec 5.8.4, 5.12).
## Static: one palette per process. `version` increments whenever the published palette changes so that consumers
## (ViewWorld, ViewMaterials.refresh_team_colors) can rewrite team colours exactly once.

enum Mode { NORMAL, PROTAN, DEUTAN, TRITAN, HIGH_CONTRAST }

const MODE_NORMAL: int = 0
const MODE_PROTAN: int = 1
const MODE_DEUTAN: int = 2
const MODE_TRITAN: int = 3
const MODE_HIGH_CONTRAST: int = 4

const COUNT: int = 16
## Lobby swatches (sRGB), net.md lobby colour ids 0..11.
const LOBBY: Array[Color] = [
	Color("D93A3A"), Color("2F7DE1"), Color("2DB56A"), Color("F2B234"), Color("8B5CD6"), Color("27C4D6"),
	Color("F0782A"), Color("D9479B"), Color("9BD13B"), Color("8A97A8"), Color("8C5A3B"), Color("ECECEC"),
]
## Okabe-Ito based set for ids 0..7 in the three colour-blind modes.
const OKABE_ITO: Array[Color] = [
	Color("0072B2"), Color("E69F00"), Color("56B4E9"), Color("009E73"), Color("F0E442"), Color("D55E00"), Color("CC79A7"), Color("F2F2F2"),
]
## Colour of neutral ownership (owner = -1).
const NEUTRAL: Color = Color(0.62, 0.62, 0.60)
const LIGHTEN_DERIVED: float = 0.25
const HIGH_CONTRAST_CHROMA: float = 1.2

static var version: int = 0
static var _mode: int = MODE_NORMAL
static var _palette: Array[Color] = []


static func mode() -> int:
	return _mode


## Switches the palette mode; a no-op (no version bump) when unchanged.
static func set_mode(m: int) -> void:
	var mm: int = clampi(m, MODE_NORMAL, MODE_HIGH_CONTRAST)
	if mm == _mode and not _palette.is_empty():
		return
	_mode = mm
	_rebuild()
	version += 1


static func _rebuild() -> void:
	var base: Array[Color] = []
	for i in 12:
		base.append(LOBBY[i])
	if _mode == MODE_PROTAN or _mode == MODE_DEUTAN or _mode == MODE_TRITAN:
		for i in 8:
			base[i] = OKABE_ITO[i]
	elif _mode == MODE_HIGH_CONTRAST:
		for i in 12:
			var c: Color = base[i]
			c.s = minf(c.s * HIGH_CONTRAST_CHROMA, 1.0)
			base[i] = c
	_palette.clear()
	_palette.append_array(base)
	for i in 4:
		_palette.append(base[i].lerp(Color.WHITE, LIGHTEN_DERIVED))


## Player colour for id 0..15 (SimPlayer.color); -1 (or any negative id) is neutral.
static func color(id: int) -> Color:
	if id < 0:
		return NEUTRAL
	if _palette.is_empty():
		_rebuild()
	return _palette[id % COUNT]


## Shape pip id: 0 circle, 1 triangle, 2 square, 3 diamond, 4 cross, 5 hexagon, 6 star, 7 bar; ids 8..15 repeat.
static func pip_shape(id: int) -> int:
	return maxi(id, 0) % 8


## True for ids 8..15, whose pip is drawn with an outline to tell it from ids 0..7.
static func pip_outlined(id: int) -> bool:
	return id >= 8


## Perceptual distance (CIE76 delta E) between two sRGB colours.
static func delta_e(a: Color, b: Color) -> float:
	var la: Vector3 = _lab(a)
	var lb: Vector3 = _lab(b)
	return la.distance_to(lb)


## Smallest delta E between `c` and any Color value in `palette` (Dictionary of key -> Color). Faction-paint collision
## helper for tests: below about 20 the player colour is hard to separate from that paint.
static func contrast_against(c: Color, palette: Dictionary) -> float:
	var best: float = INF
	for k: Variant in palette:
		var v: Variant = palette[k]
		if v is Color:
			best = minf(best, delta_e(c, v as Color))
	return best

## CIEDE2000 distance between two sRGB colours (Sharma 2005 reference formulation): the metric of art_direction 5.4 (dE00 >= 20 is
## "separable at a glance"; the CVD set keeps >= 14 from every faction primary).
static func delta_e00(a: Color, b: Color) -> float:
	return delta_e00_lab(_lab(a), _lab(b))


## CIEDE2000 between two CIELAB triples (L, a, b).
static func delta_e00_lab(la: Vector3, lb: Vector3) -> float:
	var c1: float = sqrt(la.y * la.y + la.z * la.z)
	var c2: float = sqrt(lb.y * lb.y + lb.z * lb.z)
	var cbar: float = 0.5 * (c1 + c2)
	var cbar7: float = pow(cbar, 7.0)
	var g: float = 0.5 * (1.0 - sqrt(cbar7 / (cbar7 + 6103515625.0)))  # 25^7
	var a1: float = (1.0 + g) * la.y
	var a2: float = (1.0 + g) * lb.y
	var cp1: float = sqrt(a1 * a1 + la.z * la.z)
	var cp2: float = sqrt(a2 * a2 + lb.z * lb.z)
	var h1: float = _hue_deg(la.z, a1)
	var h2: float = _hue_deg(lb.z, a2)
	var dl: float = lb.x - la.x
	var dc: float = cp2 - cp1
	var dh: float = 0.0
	if cp1 * cp2 > 0.0:
		dh = h2 - h1
		if dh > 180.0:
			dh -= 360.0
		elif dh < -180.0:
			dh += 360.0
	var dhh: float = 2.0 * sqrt(cp1 * cp2) * sin(deg_to_rad(dh * 0.5))
	var lbar: float = 0.5 * (la.x + lb.x)
	var cpbar: float = 0.5 * (cp1 + cp2)
	var hbar: float = h1 + h2
	if cp1 * cp2 > 0.0:
		if absf(h1 - h2) > 180.0:
			hbar += 360.0 if (h1 + h2) < 360.0 else -360.0
		hbar *= 0.5
	var t: float = 1.0 - 0.17 * cos(deg_to_rad(hbar - 30.0)) + 0.24 * cos(deg_to_rad(2.0 * hbar)) + 0.32 * cos(deg_to_rad(3.0 * hbar + 6.0)) \
		- 0.20 * cos(deg_to_rad(4.0 * hbar - 63.0))
	var dtheta: float = 30.0 * exp(-pow((hbar - 275.0) / 25.0, 2.0))
	var cp7: float = pow(cpbar, 7.0)
	var rc: float = 2.0 * sqrt(cp7 / (cp7 + 6103515625.0))
	var l50: float = (lbar - 50.0) * (lbar - 50.0)
	var sl: float = 1.0 + 0.015 * l50 / sqrt(20.0 + l50)
	var sc: float = 1.0 + 0.045 * cpbar
	var sh: float = 1.0 + 0.015 * cpbar * t
	var rt: float = -sin(deg_to_rad(2.0 * dtheta)) * rc
	var tl: float = dl / sl
	var tc: float = dc / sc
	var th: float = dhh / sh
	return sqrt(tl * tl + tc * tc + th * th + rt * tc * th)


static func _hue_deg(b: float, a: float) -> float:
	if a == 0.0 and b == 0.0:
		return 0.0
	var h: float = rad_to_deg(atan2(b, a))
	return h + 360.0 if h < 0.0 else h



static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func lab_of(c: Color) -> Vector3:
	return _lab(c)


static func _lab(c: Color) -> Vector3:
	var r: float = _lin(c.r)
	var g: float = _lin(c.g)
	var b: float = _lin(c.b)
	var x: float = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
	var y: float = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
	var z: float = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
	var fx: float = _lab_f(x)
	var fy: float = _lab_f(y)
	var fz: float = _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
