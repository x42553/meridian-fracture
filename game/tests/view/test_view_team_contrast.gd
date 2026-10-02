extends RefCounted
## VQ2A: team-colour contrast of ALL 32 rosters (8 factions x vanilla + 3 subfactions) against all 8 player colours in the five colour
## modes (normal, protan, deutan, tritan, high contrast): CIEDE2000 between the rendered plate colour and the style's dominant paints
## (ViewTeamContrast), the plate adjustment that fixes conflicts (lightness shift, hue kept, faction palettes untouched) and the Sharma
## reference vectors of the metric.

const SHARMA: Array = [
	[Vector3(50.0, 2.6772, -79.7751), Vector3(50.0, 0.0, -82.7485), 2.0425],
	[Vector3(50.0, 3.1571, -77.2803), Vector3(50.0, 0.0, -82.7485), 2.8615],
	[Vector3(50.0, 2.5, 0.0), Vector3(50.0, 0.0, -2.5), 4.3065],
	[Vector3(60.2574, -34.0099, 36.2677), Vector3(60.4626, -34.1751, 39.4387), 1.2644],
	[Vector3(22.7233, 20.0904, -46.694), Vector3(23.0331, 14.973, -42.5619), 2.0373],
]
const FACTIONS: PackedStringArray = ["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"]

var _book: ViewRecipeBook = null


func _load() -> void:
	if _book == null:
		_book = ViewRecipeBook.new()
		_book.load_all()


func _rosters() -> PackedStringArray:
	_load()
	var out: PackedStringArray = PackedStringArray()
	for sid: String in _book.style_ids():
		if FACTIONS.has(sid.get_slice(".", 0)):
			out.append(sid)
	return out


func teardown(_t: TestCtx) -> void:
	ViewTeamColors.set_mode(ViewTeamColors.MODE_NORMAL)
	ViewTeamContrast.clear_cache()


func test_ciede2000_matches_the_sharma_reference_vectors(t: TestCtx) -> void:
	for v: Array in SHARMA:
		var d: float = ViewTeamColors.delta_e00_lab(v[0] as Vector3, v[1] as Vector3)
		t.near(d, float(v[2]), 0.0002, "dE00 %s vs %s" % [v[0], v[1]])
		t.near(ViewTeamColors.delta_e00_lab(v[1] as Vector3, v[0] as Vector3), d, 0.0002, "symmetric")
	t.near(ViewTeamColors.delta_e00(Color("D8323B"), Color("D8323B")), 0.0, 0.0001, "identity")


func test_lab_round_trip(t: TestCtx) -> void:
	for c: Color in [Color("D93A3A"), Color("2F7DE1"), Color("9BD13B"), Color("8C5A3B"), Color("ECECEC")]:
		var back: Color = ViewTeamContrast.srgb_of_lab(ViewTeamColors.lab_of(c))
		t.lt(ViewTeamColors.delta_e00(c, back), 0.5, "round trip of %s" % c.to_html(false))


func test_all_32_rosters_exist_with_a_base_paint(t: TestCtx) -> void:
	var r: PackedStringArray = _rosters()
	t.eq(r.size(), 32, "8 factions x 4 rosters")
	for sid: String in r:
		t.gt(ViewTeamContrast.paints_of(_book.style(StringName(sid))).size(), 0, "%s has paint roles" % sid)


func test_every_roster_separates_from_every_player_colour_in_every_mode(t: TestCtx) -> void:
	var worst: float = INF
	var worst_s: String = ""
	var shifted: int = 0
	var below_target: int = 0
	var total: int = 0
	for sid: String in _rosters():
		var paints: Array[Vector4] = ViewTeamContrast.paints_of(_book.style(StringName(sid)))
		for mode: int in 5:
			ViewTeamColors.set_mode(mode)
			for cid: int in 8:
				var tc: Color = ViewTeamColors.color(cid)
				var adj: Color = ViewTeamContrast.adjust(paints, tc)
				var score: float = ViewTeamContrast.min_de(paints, adj)
				total += 1
				if adj != tc:
					shifted += 1
					t.le(ViewTeamColors.delta_e00(tc, adj), ViewTeamContrast.MAX_SHIFT_L + 4.0, "%s mode %d colour %d keeps the player's identity" % [sid, mode, cid])
					t.ge(score, ViewTeamContrast.min_de(paints, tc), "%s mode %d colour %d: the shift never makes it worse" % [sid, mode, cid])
				if score < ViewTeamContrast.MIN_DE:
					below_target += 1
				if score < worst:
					worst = score
					worst_s = "%s mode %d colour %d" % [sid, mode, cid]
	t.eq(total, 32 * 5 * 8, "pairs checked")
	t.ge(worst, ViewTeamContrast.FLOOR_DE, "worst adjusted separation %.1f at %s" % [worst, worst_s])
	t.lt(below_target, total / 20, "pairs under the %.0f target after the adjustment: %d of %d" % [ViewTeamContrast.MIN_DE, below_target, total])
	t.note("plates shifted: %d of %d; below target: %d; worst %.1f (%s)" % [shifted, total, below_target, worst, worst_s])


func test_authored_low_contrast_pairs_are_fixed_by_the_plate_adjustment(t: TestCtx) -> void:
	_load()
	# the authored conflicts of art_direction 5.4.4 (faction, colour id): the plate must end up at >= 20 from the faction primary
	var authored: Array = [["nec", 4], ["olm", 5], ["def", 0], ["def", 6], ["pd", 1], ["pd", 5], ["han", 2], ["ae", 6], ["sap", 3]]
	ViewTeamColors.set_mode(ViewTeamColors.MODE_NORMAL)
	for pair: Array in authored:
		var sid: StringName = StringName(str(pair[0]))
		var paints: Array[Vector4] = ViewTeamContrast.paints_of(_book.style(sid))
		var tc: Color = ViewTeamColors.color(int(pair[1]))
		var adj: Color = ViewTeamContrast.plate_color(sid, _book.style(sid), tc)
		t.ge(ViewTeamContrast.min_de(paints, adj), 18.0, "%s x colour %d separates after the plate adjustment" % [sid, int(pair[1])])
	# neutral ownership is never shifted by ViewMaterials
	var m: ViewMaterials = ViewMaterials.new()
	t.eq(m.plate_color(&"napc", -1), ViewTeamColors.NEUTRAL, "neutral owner keeps the neutral grey")
