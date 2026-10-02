class_name UiA11y
extends RefCounted
## Accessibility maths and helpers (ui.md 5.19.3 / 5.19.4): WCAG contrast, colour-vision simulation (Machado 2009,
## severity 1.0, linear RGB), CIEDE2000, minimum pairwise palette distance (QA A-01), the shared pip shapes and
## `accessibility_name` helpers. Pure functions except `name` / `live`.

enum Cvd { NONE = 0, DEUTERANOPIA = 1, PROTANOPIA = 2, TRITANOPIA = 3 }

const _DEUT: Array[float] = [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]
const _PROT: Array[float] = [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]
const _TRIT: Array[float] = [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900]

## Fallback wording until `UiText` (UI-01b) is installed.
const _FALLBACK_TEXT: Dictionary = {
	&"ui.ok": "OK", &"ui.yes": "Yes", &"ui.no": "No", &"ui.cancel": "Cancel", &"ui.close": "Close",
	&"ui.back": "Back", &"ui.apply": "Apply", &"ui.confirm": "Confirm",
}

static var _text_script: Script = null
static var _text_probed: bool = false


# --- colour maths ---

static func srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func linear_to_srgb(c: float) -> float:
	var v: float = clampf(c, 0.0, 1.0)
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


## WCAG relative luminance.
static func luminance(c: Color) -> float:
	return 0.2126 * srgb_to_linear(c.r) + 0.7152 * srgb_to_linear(c.g) + 0.0722 * srgb_to_linear(c.b)


## WCAG contrast ratio (1 .. 21) of two opaque colours.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Colour as seen under a colour-vision deficiency (Machado 2009, severity 1.0).
static func simulate(c: Color, mode: int) -> Color:
	if mode == Cvd.NONE:
		return c
	var m: Array[float] = _DEUT
	if mode == Cvd.PROTANOPIA:
		m = _PROT
	elif mode == Cvd.TRITANOPIA:
		m = _TRIT
	var r: float = srgb_to_linear(c.r)
	var g: float = srgb_to_linear(c.g)
	var b: float = srgb_to_linear(c.b)
	return Color(linear_to_srgb(m[0] * r + m[1] * g + m[2] * b), linear_to_srgb(m[3] * r + m[4] * g + m[5] * b), linear_to_srgb(m[6] * r + m[7] * g + m[8] * b), c.a)


## CIE Lab (D65) of an sRGB colour: Vector3(L, a, b).
static func to_lab(c: Color) -> Vector3:
	var r: float = srgb_to_linear(c.r)
	var g: float = srgb_to_linear(c.g)
	var b: float = srgb_to_linear(c.b)
	var x: float = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
	var y: float = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
	var z: float = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
	var fx: float = _lab_f(x)
	var fy: float = _lab_f(y)
	var fz: float = _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856451679 else 7.787037037 * t + 16.0 / 116.0


## CIEDE2000 between two Lab colours (Sharma, Wu, Dalal 2005; kL = kC = kH = 1).
static func delta_e2000_lab(l1: Vector3, l2: Vector3) -> float:
	var c1: float = sqrt(l1.y * l1.y + l1.z * l1.z)
	var c2: float = sqrt(l2.y * l2.y + l2.z * l2.z)
	var cbar: float = (c1 + c2) * 0.5
	var cbar7: float = pow(cbar, 7.0)
	var g: float = 0.5 * (1.0 - sqrt(cbar7 / (cbar7 + 6103515625.0)))
	var a1p: float = (1.0 + g) * l1.y
	var a2p: float = (1.0 + g) * l2.y
	var c1p: float = sqrt(a1p * a1p + l1.z * l1.z)
	var c2p: float = sqrt(a2p * a2p + l2.z * l2.z)
	var h1p: float = _hue(l1.z, a1p)
	var h2p: float = _hue(l2.z, a2p)
	var dlp: float = l2.x - l1.x
	var dcp: float = c2p - c1p
	var dhp: float = 0.0
	if c1p * c2p != 0.0:
		dhp = h2p - h1p
		if dhp > 180.0:
			dhp -= 360.0
		elif dhp < -180.0:
			dhp += 360.0
	var dh_big: float = 2.0 * sqrt(c1p * c2p) * sin(deg_to_rad(dhp) * 0.5)
	var lbp: float = (l1.x + l2.x) * 0.5
	var cbp: float = (c1p + c2p) * 0.5
	var hbp: float = h1p + h2p
	if c1p * c2p != 0.0:
		if absf(h1p - h2p) > 180.0:
			hbp = (h1p + h2p + 360.0) * 0.5 if h1p + h2p < 360.0 else (h1p + h2p - 360.0) * 0.5
		else:
			hbp = (h1p + h2p) * 0.5
	var t: float = 1.0 - 0.17 * cos(deg_to_rad(hbp - 30.0)) + 0.24 * cos(deg_to_rad(2.0 * hbp)) + 0.32 * cos(deg_to_rad(3.0 * hbp + 6.0)) - 0.20 * cos(deg_to_rad(4.0 * hbp - 63.0))
	var d_theta: float = 30.0 * exp(-pow((hbp - 275.0) / 25.0, 2.0))
	var cbp7: float = pow(cbp, 7.0)
	var rc: float = 2.0 * sqrt(cbp7 / (cbp7 + 6103515625.0))
	var sl: float = 1.0 + 0.015 * pow(lbp - 50.0, 2.0) / sqrt(20.0 + pow(lbp - 50.0, 2.0))
	var sc: float = 1.0 + 0.045 * cbp
	var sh: float = 1.0 + 0.015 * cbp * t
	var rt: float = -sin(deg_to_rad(2.0 * d_theta)) * rc
	var a: float = dlp / sl
	var b: float = dcp / sc
	var c: float = dh_big / sh
	return sqrt(a * a + b * b + c * c + rt * b * c)


static func _hue(b: float, ap: float) -> float:
	if b == 0.0 and ap == 0.0:
		return 0.0
	var h: float = rad_to_deg(atan2(b, ap))
	return h + 360.0 if h < 0.0 else h


## CIEDE2000 between two sRGB colours, both seen through the deficiency `mode`.
static func delta_e(a: Color, b: Color, mode: int = Cvd.NONE) -> float:
	return delta_e2000_lab(to_lab(simulate(a, mode)), to_lab(simulate(b, mode)))


## Minimum pairwise CIEDE2000 of a colour set under `mode` (QA `QaContrast.min_pairwise_delta_e`).
static func min_pairwise_delta_e(colors: PackedColorArray, mode: int = Cvd.NONE) -> float:
	var labs: Array[Vector3] = []
	for c in colors:
		labs.append(to_lab(simulate(c, mode)))
	var best: float = INF
	for i in labs.size():
		for j in range(i + 1, labs.size()):
			best = minf(best, delta_e2000_lab(labs[i], labs[j]))
	return best


## Colour array from hex strings ("D8323B" or "#D8323B").
static func colors_from_hex(hexes: PackedStringArray) -> PackedColorArray:
	var out := PackedColorArray()
	for h in hexes:
		out.append(Color(h))
	return out


# --- pip shapes (second channel next to colour; art 5.4.2: 0 circle, 1 triangle, 2 square, 3 diamond, 4 cross, 5 hexagon, 6 star, 7 bar) ---

## Draws pip shape `shape` (0-7; 8-15 repeat 0-7 with an outline ring) centred at `center`, `radius` px.
static func draw_pip(ci: CanvasItem, shape: int, center: Vector2, radius: float, col: Color) -> void:
	var s: int = shape % 8
	var r: float = radius
	match s:
		0:
			ci.draw_circle(center, r, col)
		1:
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -r), center + Vector2(r * 0.95, r * 0.8), center + Vector2(-r * 0.95, r * 0.8)]), col)
		2:
			ci.draw_rect(Rect2(center - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), col)
		3:
			ci.draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -r), center + Vector2(r, 0.0), center + Vector2(0.0, r), center + Vector2(-r, 0.0)]), col)
		4:
			ci.draw_rect(Rect2(center + Vector2(-r, -r * 0.3), Vector2(r * 2.0, r * 0.6)), col)
			ci.draw_rect(Rect2(center + Vector2(-r * 0.3, -r), Vector2(r * 0.6, r * 2.0)), col)
		5:
			var hex := PackedVector2Array()
			for i in 6:
				hex.append(center + Vector2(cos(TAU * float(i) / 6.0), sin(TAU * float(i) / 6.0)) * r)
			ci.draw_colored_polygon(hex, col)
		6:
			var star := PackedVector2Array()
			for i in 10:
				var rr: float = r if i % 2 == 0 else r * 0.45
				var a: float = -PI * 0.5 + TAU * float(i) / 10.0
				star.append(center + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(star, col)
		_:
			ci.draw_rect(Rect2(center + Vector2(-r, -r * 0.3), Vector2(r * 2.0, r * 0.6)), col)
	if shape >= 8:
		ci.draw_arc(center, r + 1.5, 0.0, TAU, 20, col, 1.0, true)


# --- text / accessibility ---

## Resolved UI string for `key`: `UiText.t` when the text module exists, else a small fallback table, else the key.
static func resolve_text(key: StringName, args: Dictionary = {}) -> String:
	if not _text_probed:
		_text_probed = true
		_text_script = UiDraw.optional_script(&"UiText")
	if _text_script != null:
		return String(_text_script.call(&"t", key, args))
	var s: String = String(_FALLBACK_TEXT.get(key, key))
	for k: Variant in args:
		s = s.replace("{%s}" % k, str(args[k]))
	return s


## Sets `accessibility_name` (resolved from a text key) on a control (A-13).
static func name(control: Control, key: StringName, args: Dictionary = {}) -> void:
	control.accessibility_name = resolve_text(key, args)


## Sets the accessibility name from an already resolved string.
static func name_text(control: Control, text: String) -> void:
	control.accessibility_name = text


## Marks a control as a polite live region (notification feed, lobby chat, loading status).
static func live(control: Control) -> void:
	control.accessibility_live = AccessibilityServer.LIVE_POLITE
