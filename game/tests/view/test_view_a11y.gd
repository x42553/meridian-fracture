extends RefCounted
## VIEW-01 acceptance: team-colour palette modes, shape pips, contrast helper, reduce_* scaling (render spec 5.12, 10.1).

const OKABE: Array[String] = ["0072B2", "E69F00", "56B4E9", "009E73", "F0E442", "D55E00", "CC79A7", "F2F2F2"]


func teardown(_t: TestCtx) -> void:
	ViewTeamColors.set_mode(ViewTeamColors.MODE_NORMAL)


func test_normal_palette_is_the_lobby_swatches(t: TestCtx) -> void:
	ViewTeamColors.set_mode(ViewTeamColors.MODE_NORMAL)
	var lobby: Array[String] = ["D93A3A", "2F7DE1", "2DB56A", "F2B234", "8B5CD6", "27C4D6", "F0782A", "D9479B", "9BD13B", "8A97A8", "8C5A3B", "ECECEC"]
	for i in 12:
		t.eq(ViewTeamColors.color(i), Color(lobby[i]), "colour %d" % i)
	for i in 4:
		t.eq(ViewTeamColors.color(12 + i), Color(lobby[i]).lerp(Color.WHITE, 0.25), "colour %d = colour %d lightened 25 percent" % [12 + i, i])
	t.eq(ViewTeamColors.color(-1), ViewTeamColors.NEUTRAL, "owner -1 is neutral grey")


func test_deutan_publishes_okabe_ito(t: TestCtx) -> void:
	var v0: int = ViewTeamColors.version
	ViewTeamColors.set_mode(ViewTeamColors.MODE_DEUTAN)
	t.gt(ViewTeamColors.version, v0, "version bumps on a mode change")
	for i in 8:
		t.eq(ViewTeamColors.color(i), Color(OKABE[i]), "Okabe-Ito colour %d" % i)
	t.eq(ViewTeamColors.color(8), Color("9BD13B"), "id 8 keeps its normal colour")
	t.eq(ViewTeamColors.color(11), Color("ECECEC"), "id 11 keeps its normal colour")
	var v1: int = ViewTeamColors.version
	ViewTeamColors.set_mode(ViewTeamColors.MODE_DEUTAN)
	t.eq(ViewTeamColors.version, v1, "setting the same mode is a no-op")
	ViewTeamColors.set_mode(ViewTeamColors.MODE_NORMAL)
	t.eq(ViewTeamColors.color(0), Color("D93A3A"), "normal restores the lobby swatches exactly")
	t.eq(ViewTeamColors.color(1), Color("2F7DE1"), "normal restores id 1")


func test_all_three_colour_blind_modes_share_the_set(t: TestCtx) -> void:
	for m: int in [ViewTeamColors.MODE_PROTAN, ViewTeamColors.MODE_DEUTAN, ViewTeamColors.MODE_TRITAN]:
		ViewTeamColors.set_mode(m)
		t.eq(ViewTeamColors.color(2), Color(OKABE[2]), "mode %d colour 2" % m)
	# the eight colours are mutually distinguishable (delta E), which is the point of the set
	var worst: float = INF
	for i in 8:
		for j in range(i + 1, 8):
			worst = minf(worst, ViewTeamColors.delta_e(ViewTeamColors.color(i), ViewTeamColors.color(j)))
	t.gt(worst, 12.0, "Okabe-Ito colours stay apart (min delta E %.1f)" % worst)


func test_high_contrast_raises_chroma(t: TestCtx) -> void:
	var base: Color = ViewTeamColors.color(2)
	ViewTeamColors.set_mode(ViewTeamColors.MODE_HIGH_CONTRAST)
	var hc: Color = ViewTeamColors.color(2)
	t.near(hc.s, minf(base.s * 1.2, 1.0), 1.0e-5, "saturation x1.2")
	t.near(hc.h, base.h, 1.0e-5, "hue kept")


func test_shape_pips(t: TestCtx) -> void:
	var seen: Dictionary = {}
	for i in 8:
		seen[ViewTeamColors.pip_shape(i)] = true
		t.check(not ViewTeamColors.pip_outlined(i), "id %d plain" % i)
	t.eq(seen.size(), 8, "the shape pip differs for ids 0-7")
	for i in range(8, 16):
		t.eq(ViewTeamColors.pip_shape(i), ViewTeamColors.pip_shape(i - 8), "id %d repeats" % i)
		t.check(ViewTeamColors.pip_outlined(i), "id %d outlined" % i)


func test_contrast_helper(t: TestCtx) -> void:
	var palette: Dictionary = {"base": Color("4d592e"), "sec": Color("d6c799"), "acc": Color("ed5e0f"), "name": "napc"}
	var red_on_oxide: float = ViewTeamColors.contrast_against(Color("D93A3A"), {"base": Color("8c3826")})
	t.lt(red_on_oxide, 35.0, "crimson team vs DEF oxide hull is a low-contrast pair (%.1f)" % red_on_oxide)
	var blue_on_olive: float = ViewTeamColors.contrast_against(Color("2F7DE1"), palette)
	t.gt(blue_on_olive, 35.0, "azure team stays separable from NAPC paint (%.1f)" % blue_on_olive)
	t.eq(ViewTeamColors.contrast_against(Color.RED, {}), INF, "empty palette -> INF")
	t.near(ViewTeamColors.delta_e(Color.WHITE, Color.WHITE), 0.0, 1.0e-6, "same colour -> 0")


func test_reduce_scaling(t: TestCtx) -> void:
	var j: Dictionary = ViewQuality.load_presets()
	var q: ViewQuality = ViewQuality.create(j, ViewQuality.Preset.HIGH)
	t.near(q.flash_light_scale(), 1.0, 1.0e-9, "default light")
	t.near(q.shake_scale(), 1.0, 1.0e-9, "default shake")
	q.reduce_flash = true
	t.near(q.flash_light_scale(), 0.4, 1.0e-9, "reduce_flash light x0.4")
	t.near(q.flash_size_cap(), 0.6, 1.0e-9, "reduce_flash sprite size x0.6")
	t.near(q.flash_alpha_cap(), 0.5, 1.0e-9, "reduce_flash alpha x0.5")
	t.near(q.shake_scale(), 0.0, 1.0e-9, "reduce_flash silences shake")
	q.reduce_flash = false
	q.reduce_motion = true
	t.near(q.shake_scale(), 0.2, 1.0e-9, "reduce_motion shake x0.2")
