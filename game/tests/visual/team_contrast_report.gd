extends SceneTree
## VQ2A report: team-colour contrast of every style (32 rosters + neutral) x every player colour (default ids 0..7, the CVD set and the
## protan / deutan / tritan / high-contrast modes), before and after the per-style plate adjustment (ViewTeamContrast).
## `tools/gd run res://tests/visual/team_contrast_report.gd -- [out.csv]` prints a summary + the worst pairs and writes a CSV
## (style, mode, colour id, raw min dE00, adjusted min dE00, shift dE00, dominant paint hex, nearest paint).

const MODES: PackedStringArray = ["normal", "protan", "deutan", "tritan", "high_contrast"]


func _init() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var ids: PackedStringArray = book.style_ids()
	var rows: PackedStringArray = PackedStringArray(["style,mode,colour,raw_de00,adj_de00,shift_de00,nearest_paint"])
	var raw_low: int = 0
	var adj_low: int = 0
	var total: int = 0
	var worst_raw: float = INF
	var worst_adj: float = INF
	var worst_s: String = ""
	var changed: int = 0
	for sid: String in ids:
		var st: Dictionary = book.style(StringName(sid))
		var paints: Array[Vector4] = ViewTeamContrast.paints_of(st)
		for m: int in MODES.size():
			ViewTeamColors.set_mode(m)
			var count: int = 8
			for cid: int in count:
				var tc: Color = ViewTeamColors.color(cid)
				var raw: float = ViewTeamContrast.min_de(paints, tc)
				var adj_c: Color = ViewTeamContrast.adjust(paints, tc)
				var adj: float = ViewTeamContrast.min_de(paints, adj_c)
				total += 1
				if raw < ViewTeamContrast.MIN_DE:
					raw_low += 1
				if adj < ViewTeamContrast.MIN_DE:
					adj_low += 1
				if adj_c != tc:
					changed += 1
				if adj < worst_adj:
					worst_adj = adj
					worst_s = "%s %s colour %d" % [sid, MODES[m], cid]
				worst_raw = minf(worst_raw, raw)
				rows.append("%s,%s,%d,%.1f,%.1f,%.1f,%s" % [sid, MODES[m], cid, raw, adj, ViewTeamColors.delta_e00(tc, adj_c), _nearest(paints, tc)])
	ViewTeamColors.set_mode(0)
	print("styles=%d pairs=%d | raw < %.0f: %d (worst %.1f) | adjusted < %.0f: %d (worst %.1f at %s) | plates shifted: %d" % [ids.size(), total,
		ViewTeamContrast.MIN_DE, raw_low, worst_raw, ViewTeamContrast.MIN_DE, adj_low, worst_adj, worst_s, changed])
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(rows) + "\n")
		f.close()
	quit()


func _nearest(paints: Array[Vector4], tc: Color) -> String:
	var plate: Color = ViewTeamContrast.plate_rendered(tc)
	var best: float = INF
	var hex: String = ""
	for p: Vector4 in paints:
		var pc: Color = Color(p.x, p.y, p.z)
		var d: float = ViewTeamColors.delta_e00(plate, pc) * ViewTeamContrast.MIN_DE / p.w
		if d < best:
			best = d
			hex = pc.to_html(false)
	return hex
