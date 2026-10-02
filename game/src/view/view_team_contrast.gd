class_name ViewTeamContrast
extends RefCounted
## Team-colour contrast against the faction paint (VQ2A, art_direction 5.4.3 / 5.4.4). The player colour reaches a model only through
## mask > 0 plate fields painted with the neutral key (rendered colour = player colour x KEY_FACTOR, 5.4.3), bounded by a light hairline
## and a dark gasket. That keeps every plate visible, but at distance (a plate is 7 px at MAX) the HUE still has to separate from the
## dominant paint of the style: this class measures the CIEDE2000 distance between the rendered plate colour and the style's dominant
## paints (palette roles base / sec / concrete / dark, i.e. hull, turret, roof, walls and the dark mass) and, where it falls below MIN_DE, derives a
## per-(style, player colour) plate colour whose LIGHTNESS is shifted (hue kept) until the pair separates. Faction palettes are never
## touched; the shift is bounded (MAX_SHIFT_L) so the colour stays recognisable as the player's. Pure functions + one cache.

const KEY_FACTOR: float = 0.909  ## rendered plate colour = player colour x neutral-key factor (art direction 5.4.3)
const MIN_DE: float = 20.0  ## reference score (= the dE00 20 of art direction 5.4.4 for the primary paint)
const FLOOR_DE: float = 12.0  ## no (style, colour) pair may stay below this score after the adjustment (tests)
const MAX_SHIFT_L: float = 30.0  ## largest lightness shift (CIELAB L) the adjustment may apply
const STEP_L: float = 2.0
## Role -> dE00 the rendered plate must keep from that palette role. Hull paint (base) and structure roofs / walls (concrete) are what a
## plate sits on; sec is the minor trim colour (6-13 % of the plan view, probe: tests/visual/paint_share_probe.gd), so it needs less.
const NEED_DE: Dictionary = {"base": 20.0, "concrete": 16.0, "sec": 12.0}

static var enabled: bool = true  ## QA switch (before / after shots, tests); never a setting
static var _cache: Dictionary = {}


## Dominant hull / roof / trim paints of a merged style dictionary (ViewRecipeBook.style()) as [color, needed dE00] pairs.
static func paints_of(style: Dictionary) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var pal: Dictionary = style.get("palette", {}) as Dictionary
	for role: String in NEED_DE:
		if pal.has(role):
			var c: Color = Color(str(pal[role]))
			out.append(Vector4(c.r, c.g, c.b, float(NEED_DE[role])))
	return out


## The colour a plate field renders with for player colour `tc` (neutral key paint).
static func plate_rendered(tc: Color) -> Color:
	return Color(clampf(tc.r * KEY_FACTOR, 0.0, 1.0), clampf(tc.g * KEY_FACTOR, 0.0, 1.0), clampf(tc.b * KEY_FACTOR, 0.0, 1.0))


## Separation score of the rendered plate of `tc` against `paints`: the smallest dE00 / needed dE00 x MIN_DE over the paints, i.e. a score
## >= MIN_DE means every role keeps its required distance (INF without paints).
static func min_de(paints: Array[Vector4], tc: Color) -> float:
	var plate: Color = plate_rendered(tc)
	var best: float = INF
	for p: Vector4 in paints:
		best = minf(best, ViewTeamColors.delta_e00(plate, Color(p.x, p.y, p.z)) * MIN_DE / p.w)
	return best


## Player colour to feed the plates of `style`: `tc` itself when it already separates (>= MIN_DE), else the closest lightness shift
## (hue and chroma kept, at most MAX_SHIFT_L) that does; when none reaches MIN_DE the one with the best separation. Cached per style id.
static func plate_color(style_id: StringName, style: Dictionary, tc: Color) -> Color:
	if not enabled:
		return tc
	var key: String = "%s|%d" % [style_id, tc.to_rgba32()]
	var hit: Variant = _cache.get(key)
	if hit != null:
		return hit as Color
	var out: Color = adjust(paints_of(style), tc)
	_cache[key] = out
	return out


static func clear_cache() -> void:
	_cache.clear()


## Pure form of plate_color().
static func adjust(paints: Array[Vector4], tc: Color) -> Color:
	if paints.is_empty() or min_de(paints, tc) >= MIN_DE:
		return tc
	var lab: Vector3 = ViewTeamColors.lab_of(tc)
	var best: Color = tc
	var best_de: float = min_de(paints, tc)
	var k: int = 1
	while float(k) * STEP_L <= MAX_SHIFT_L:
		for sgn: float in [1.0, -1.0]:
			var cand: Color = srgb_of_lab(Vector3(clampf(lab.x + sgn * float(k) * STEP_L, 8.0, 97.0), lab.y, lab.z))
			var de: float = min_de(paints, cand)
			if de >= MIN_DE:
				return cand
			if de > best_de + 0.05:
				best_de = de
				best = cand
		k += 1
	return best


## CIELAB (D65) -> sRGB, clipped to the gamut.
static func srgb_of_lab(lab: Vector3) -> Color:
	var fy: float = (lab.x + 16.0) / 116.0
	var fx: float = fy + lab.y / 500.0
	var fz: float = fy - lab.z / 200.0
	var x: float = 0.95047 * _finv(fx)
	var y: float = _finv(fy)
	var z: float = 1.08883 * _finv(fz)
	var r: float = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
	var g: float = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
	var b: float = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
	return Color(_gamma(r), _gamma(g), _gamma(b))


static func _finv(t: float) -> float:
	var t3: float = t * t * t
	return t3 if t3 > 0.008856 else (t - 16.0 / 116.0) / 7.787


static func _gamma(v: float) -> float:
	var c: float = clampf(v, 0.0, 1.0)
	return 12.92 * c if c <= 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055
