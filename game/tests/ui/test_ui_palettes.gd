extends RefCounted
## Colour-vision simulation, CIEDE2000 and the team-palette verdicts of ui.md 5.19.3 (`test_ui_palettes`).
## `A01_MODE` is QA's decision switch: `literal` = A-01 as written (>= 20 normal AND >= 12 under each simulation for every
## shipped set), `narrow` = the default set is judged under normal vision only (the recorded R28 deviation).

const A01_MODE: String = "narrow"
const DEFAULT_HEX: PackedStringArray = ["D8323B", "2C86F0", "2FAE5E", "F5C13A", "7250D8", "25CDE0", "F47B2A", "E0489F"]
const MODES: Array[int] = [UiA11y.Cvd.NONE, UiA11y.Cvd.PROTANOPIA, UiA11y.Cvd.DEUTERANOPIA, UiA11y.Cvd.TRITANOPIA]


func _near_rgb(t: TestCtx, got: Color, want: String, msg: String) -> void:
	var w: Color = Color(want)
	for ch in 3:
		t.check(absf(got[ch] * 255.0 - w[ch] * 255.0) <= 1.5, "%s: %s vs #%s" % [msg, got.to_html(false), want])


func test_cvd_simulation_goldens(t: TestCtx) -> void:
	var red := Color("#FF0000")
	var green := Color("#00FF00")
	var blue := Color("#0000FF")
	_near_rgb(t, UiA11y.simulate(red, UiA11y.Cvd.DEUTERANOPIA), "A39000", "red deut")
	_near_rgb(t, UiA11y.simulate(red, UiA11y.Cvd.PROTANOPIA), "6D5F00", "red prot")
	_near_rgb(t, UiA11y.simulate(red, UiA11y.Cvd.TRITANOPIA), "FF000F", "red trit")
	_near_rgb(t, UiA11y.simulate(green, UiA11y.Cvd.DEUTERANOPIA), "EFD63A", "green deut")
	_near_rgb(t, UiA11y.simulate(green, UiA11y.Cvd.PROTANOPIA), "FFE500", "green prot")
	_near_rgb(t, UiA11y.simulate(green, UiA11y.Cvd.TRITANOPIA), "00F7D9", "green trit")
	_near_rgb(t, UiA11y.simulate(blue, UiA11y.Cvd.DEUTERANOPIA), "003DFB", "blue deut")
	_near_rgb(t, UiA11y.simulate(blue, UiA11y.Cvd.PROTANOPIA), "0059FF", "blue prot")
	_near_rgb(t, UiA11y.simulate(blue, UiA11y.Cvd.TRITANOPIA), "006B96", "blue trit")
	t.check(UiA11y.simulate(red, UiA11y.Cvd.NONE).is_equal_approx(red), "NONE is the identity")


func test_ciede2000_reference_pairs(t: TestCtx) -> void:
	# Sharma, Wu, Dalal (2005) supplementary test data
	t.near(UiA11y.delta_e2000_lab(Vector3(50.0, 2.6772, -79.7751), Vector3(50.0, 0.0, -82.7485)), 2.0425, 0.0001)
	t.near(UiA11y.delta_e2000_lab(Vector3(50.0, 3.1571, -77.2803), Vector3(50.0, 0.0, -82.7485)), 2.8615, 0.0001)
	t.near(UiA11y.delta_e2000_lab(Vector3(50.0, 2.5, 0.0), Vector3(50.0, 0.0, -2.5)), 4.3065, 0.0001)
	t.near(UiA11y.delta_e2000_lab(Vector3(60.2574, -34.0099, 36.2677), Vector3(60.4626, -34.1751, 39.4387)), 1.2644, 0.0001)


func test_ciede2000_red_green(t: TestCtx) -> void:
	var r := Color("#FF0000")
	var g := Color("#00FF00")
	t.near(UiA11y.delta_e(r, g, UiA11y.Cvd.NONE), 86.6, 0.15, "normal")
	t.near(UiA11y.delta_e(r, g, UiA11y.Cvd.DEUTERANOPIA), 19.4, 0.3, "deuteranopia")
	t.near(UiA11y.delta_e(r, g, UiA11y.Cvd.PROTANOPIA), 42.4, 0.3, "protanopia")
	t.near(UiA11y.delta_e(r, g, UiA11y.Cvd.TRITANOPIA), 75.7, 0.3, "tritanopia")


func _minima(hexes: PackedStringArray) -> Array[float]:
	var cols: PackedColorArray = UiA11y.colors_from_hex(hexes)
	var out: Array[float] = []
	for m in MODES:
		out.append(UiA11y.min_pairwise_delta_e(cols, m))
	return out


func test_authored_palette_minima(t: TestCtx) -> void:
	var d: Array[float] = _minima(DEFAULT_HEX)
	t.note("default set minima (normal/prot/deut/trit): %.1f / %.1f / %.1f / %.1f" % [d[0], d[1], d[2], d[3]])
	var want_d: Array[float] = [22.6, 8.5, 9.0, 8.7]
	for i in 4:
		t.near(d[i], want_d[i], 0.5, "art default set, mode %d" % i)
	var c: Array[float] = _minima(UiPalette.TEAM_CVD)
	t.note("cvd set minima: %.1f / %.1f / %.1f / %.1f" % [c[0], c[1], c[2], c[3]])
	var want_c: Array[float] = [20.8, 14.5, 13.8, 13.5]
	for i in 4:
		t.near(c[i], want_c[i], 0.5, "art CVD set, mode %d" % i)
	# the fallback tables equal the style file
	var skins := UiSkinSet.new()
	skins.setup_from_json()
	for i in 8:
		t.check(skins.team_color_for(i, false).is_equal_approx(Color(UiPalette.TEAM_DEFAULT[i])), "default %d == fallback" % i)
		t.check(skins.team_color_for(i, true).is_equal_approx(Color(UiPalette.TEAM_CVD[i])), "cvd %d == fallback" % i)
	for i in range(8, 12):
		t.check(skins.team_color_for(i, true).is_equal_approx(skins.team_color_for(i, false)), "ids 8-11 have no CVD variant")
	t.eq(skins.team_color_count(), 12)
	skins.set_colour_mode(UiSkinSet.ColourMode.CVD)
	t.eq(skins.team_color_count(), 8)


func test_p_default_proposal(t: TestCtx) -> void:
	var p: Array[float] = _minima(UiPalette.P_DEFAULT_0_7)
	t.note("P-default minima: %.1f / %.1f / %.1f / %.1f" % [p[0], p[1], p[2], p[3]])
	var want: Array[float] = [26.1, 17.8, 17.8, 17.8]
	for i in 4:
		t.near(p[i], want[i], 0.5, "P-default, mode %d" % i)


## QA A-01: >= 20 normal and >= 12 under each simulation. `narrow` judges the default set on normal vision only.
func _a01(minima: Array[float], is_default: bool, mode: String) -> bool:
	if minima[0] < 20.0:
		return false
	if is_default and mode == "narrow":
		return true
	return minima[1] >= 12.0 and minima[2] >= 12.0 and minima[3] >= 12.0


func test_a01_verdicts(t: TestCtx) -> void:
	var d: Array[float] = _minima(DEFAULT_HEX)
	var c: Array[float] = _minima(UiPalette.TEAM_CVD)
	var p: Array[float] = _minima(UiPalette.P_DEFAULT_0_7)
	t.check_false(_a01(d, true, "literal"), "art's default set fails A-01 as written under simulation (recorded R28 deviation)")
	t.check(_a01(d, true, "narrow"), "default set passes the narrowed A-01")
	t.check(_a01(c, false, "literal") and _a01(c, false, "narrow"), "CVD set passes both readings")
	t.check(_a01(p, true, "literal"), "P-default meets A-01 as written")
	t.check(_a01(d, true, A01_MODE) and _a01(c, false, A01_MODE), "shipped sets pass in mode %s" % A01_MODE)


func test_cvd_semantic_set(t: TestCtx) -> void:
	var cvd := PackedColorArray([UiPalette.CVD_OK, UiPalette.CVD_WARN, UiPalette.CVD_DANGER])
	var normal := PackedColorArray([UiPalette.OK, UiPalette.WARN, UiPalette.DANGER])
	var got_c: Array[float] = []
	var got_n: Array[float] = []
	for m in MODES:
		got_c.append(UiA11y.min_pairwise_delta_e(cvd, m))
		got_n.append(UiA11y.min_pairwise_delta_e(normal, m))
	t.note("semantic normal: %.1f / %.1f / %.1f / %.1f ; cvd: %.1f / %.1f / %.1f / %.1f" % [got_n[0], got_n[1], got_n[2], got_n[3], got_c[0], got_c[1], got_c[2], got_c[3]])
	t.near(got_c[0], 44.9, 0.5, "cvd normal")
	for i in range(1, 4):
		t.check(got_c[i] >= 21.9 - 0.3, "cvd semantic set >= 21.9 under simulation %d (%.1f)" % [i, got_c[i]])
	t.near(got_c[3], 33.3, 0.5, "cvd tritan")
	t.near(got_c[2], 21.9, 0.5, "cvd deut")
	t.near(got_n[0], 38.3, 0.5, "normal set")


func test_pip_shapes_and_names(t: TestCtx) -> void:
	# draw_pip is exercised through a real canvas item in the lab; here the wrap rule and text helpers
	t.eq(UiA11y.resolve_text(&"ui.yes"), "Yes")
	t.eq(UiA11y.resolve_text(&"ui.unknown_key"), "ui.unknown_key")
	var b := Button.new()
	UiA11y.name(b, &"ui.ok")
	t.eq(b.accessibility_name, "OK")
	UiA11y.live(b)
	t.eq(b.accessibility_live, AccessibilityServer.LIVE_POLITE)
	b.free()
