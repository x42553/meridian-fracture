class_name UiScreenLoading
extends UiScreen
## Loading screen (ui.md 5.3 step 5): map card (name, family, size, seed as 8 hex digits), the player list with colour,
## emblem, roster name and a per-player progress bar, one big progress bar with the job's phase label, rotating tips
## (`data/text/tips_en.json`, every 6 s) and a Cancel button. Reads the `AppMatchContext` in `AppState.match_ctx` (session job
## progress); when the session reports 100 % the flow (AppMatch) moves on by itself.
## Params: `{kind: "match"|"replay", title: String}`.

const TIPS_PATH: String = "res://data/text/tips_en.json"
const TIP_EVERY_S: float = 6.0

var ctx: AppMatchContext = null

var _bar: ProgressBar = null
var _phase: Label = null
var _pct: Label = null
var _tip: Label = null
var _tips: PackedStringArray = PackedStringArray()
var _tip_i: int = 0
var _tip_t: float = 0.0
var _shown: float = 0.0
var _rows: Array[Dictionary] = []
var _time: float = 0.0
var _title: String = "Skirmish"
var _preview: UiMapPreview = null
var _preview_done: bool = false
## LAN: the loading percentages the session reports per pid (`NetSession.load_progress`), and a build that waits for the match config
## (a joining client only gets it after the host's launch message).
var _remote: Dictionary = {}
var _build_pending: bool = false


func _init() -> void:
	super._init()
	screen_id = &"loading"
	handles_escape = false


func enter(params: Dictionary) -> void:
	_title = str(params.get("title", "Skirmish"))
	_fetch_ctx()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tips = _load_tips()
	_connect_progress()
	_build_pending = ctx == null or ctx.config.is_empty()  # no config yet (LAN client / a context that appears a frame later): build once it exists
	if not _build_pending:
		_apply_local_skin()
		_build()
	set_process(true)


func _fetch_ctx() -> void:
	var state: Node = get_tree().root.get_node_or_null("AppState")
	ctx = state.get("match_ctx") as AppMatchContext if state != null else null


func _connect_progress() -> void:
	if ctx != null and ctx.session != null and ctx.session.role != NetSession.Role.LOCAL and not ctx.session.load_progress.is_connected(_on_load_progress):
		ctx.session.load_progress.connect(_on_load_progress)


func exit() -> void:
	set_process(false)
	if ctx != null and ctx.session != null and ctx.session.load_progress.is_connected(_on_load_progress):
		ctx.session.load_progress.disconnect(_on_load_progress)


func _on_load_progress(pids: PackedInt32Array, percents: PackedInt32Array) -> void:
	for i: int in mini(pids.size(), percents.size()):
		_remote[pids[i]] = percents[i]


func default_focus() -> Control:
	return null


## The loading screen wears the local player's faction skin.
func _apply_local_skin() -> void:
	if ctx == null or ctx.data == null:
		return
	if ctx.is_replay:
		UiThemeService.rebuild(UiSkinSet.shared().neutral_skin())  # replays are watched in the neutral observer skin
		return
	for pd: Variant in _cfg().get("players", []) as Array:
		if (pd as Dictionary).get("kind", "human") == "human":
			var code: String = _faction_code(str((pd as Dictionary).get("roster", "")))
			UiThemeService.rebuild(UiSkinSet.shared().skin_for(code))
			return


func _accent() -> Color:
	return UiScreenKit.accent(self)


func _load_tips() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var f: FileAccess = FileAccess.open(TIPS_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).get("tips") is Array:
			for t: Variant in (parsed as Dictionary)["tips"] as Array:
				out.append(str(t))
	if out.is_empty():
		out.append("Build power before you build anything else.")
	return out


func _build() -> void:
	var acc: Color = _accent()
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.9, 0.08, 0.0, 0.04, acc))
	var compact: bool = _is_compact()
	var m: MarginContainer = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 56 if compact else 104)
	m.add_theme_constant_override("margin_right", 56 if compact else 104)
	m.add_theme_constant_override("margin_top", 36 if compact else 84)
	m.add_theme_constant_override("margin_bottom", 32 if compact else 76)
	add_child(m)
	UiLayerRoot.fill(m)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12 if compact else 22)
	m.add_child(col)
	# title row
	var head: VBoxContainer = VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	col.add_child(head)
	head.add_child(UiScreenKit.label("LOADING", &"DimLabel"))
	var t: Label = UiScreenKit.label(_map_name().to_upper(), &"TitleLabel")
	t.add_theme_font_size_override("font_size", 38 if compact else 52)
	head.add_child(t)
	head.add_child(UiScreenKit.label("%s  //  %s" % [_title.to_upper(), _family_line()], &"HeaderLabel"))
	# two columns: map card + players
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cols)
	cols.add_child(_map_card())
	cols.add_child(_players_panel())
	# tip + progress
	col.add_child(_progress_block())


## A logical height below 1000 px (a 1280 x 720 window runs at UI scale 0.75 = 960 logical px): smaller margins, title and map preview.
func _is_compact() -> bool:
	return is_inside_tree() and get_viewport_rect().size.y < 1000.0


func _cfg() -> Dictionary:
	return ctx.config if ctx != null else {}


func _map_cfg() -> Dictionary:
	var m: Variant = _cfg().get("map", {})
	return m as Dictionary if m is Dictionary else {}


func _map_name() -> String:
	var mc: Dictionary = _map_cfg()
	return UiMapNames.name_for(int(mc.get("family", 0)), int(mc.get("seed", 0)))


func _family_line() -> String:
	var mc: Dictionary = _map_cfg()
	var n: int = int(mc.get("size", 0))
	return "%s  //  %d x %d CELLS" % [UiMapNames.family_name(int(mc.get("family", 0))).to_upper(), n, n]


func _map_card() -> Control:
	var d: Dictionary = UiScreenKit.panel("Map", "PROCEDURAL", &"", 14, 10)
	var p: PanelContainer = d["panel"] as PanelContainer
	p.custom_minimum_size = Vector2(420.0, 0.0)
	var body: VBoxContainer = d["body"] as VBoxContainer
	var mc: Dictionary = _map_cfg()
	var rules: Dictionary = _cfg().get("rules", {}) as Dictionary
	var rows: Array = [["NAME", _map_name()], ["FAMILY", UiMapNames.family_name(int(mc.get("family", 0)))],
			["SIZE", "%d x %d cells" % [int(mc.get("size", 0)), int(mc.get("size", 0))]], ["SEED", "0x" + UiScreenKit.hex8(int(mc.get("seed", 0)))],
			["START CREDITS", UiFormatLite.credits(int(rules.get("start_credits", 7500)))],
			["FOG OF WAR", "On" if bool(rules.get("fog", true)) else "Off"]]
	if _is_compact():
		rows = rows.slice(2)  # the title already shows the name and the family
	for row: Array in rows:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_child(UiScreenKit.label(String(row[0]), &"CaptionLabel"))
		var v: Label = UiScreenKit.label(String(row[1]), &"SubLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(v)
		body.add_child(line)
	_preview = UiMapPreview.new()
	var side: float = 250.0 if _is_compact() else 380.0  # 720p: the map card must leave room for the progress bar below it
	_preview.custom_minimum_size = Vector2(side, side)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.busy = true
	body.add_child(_preview)
	return p


func _players_panel() -> Control:
	var players: Array = _cfg().get("players", []) as Array
	var d: Dictionary = UiScreenKit.panel("Commanders", "%d PLAYERS" % players.size(), &"", 14, 8)
	var p: PanelContainer = d["panel"] as PanelContainer
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = d["body"] as VBoxContainer
	for pd: Variant in players:
		body.add_child(_player_row(pd as Dictionary))
	return p


func _player_row(pd: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.theme_type_variation = &"InsetPanel"
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var bar: ColorRect = ColorRect.new()
	bar.color = UiPalette.team(int(pd.get("color", 0)))
	bar.custom_minimum_size = Vector2(6.0, 48.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var code: String = _faction_code(str(pd.get("roster", "")))
	var badge: UiFactionBadge = UiFactionBadge.new(code, 44.0)
	badge.sub_key = _sub_key(str(pd.get("roster", "")))
	h.add_child(badge)
	var names: VBoxContainer = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	h.add_child(names)
	var human: bool = str(pd.get("kind", "human")) == "human"
	names.add_child(UiScreenKit.label(str(pd.get("name", "Commander")), &"NameLabel"))
	names.add_child(UiScreenKit.label(_roster_line(str(pd.get("roster", ""))), &"DimLabel"))
	var replay: bool = ctx != null and ctx.is_replay
	var mine: bool = human and not replay and (ctx == null or ctx.session == null or ctx.session.role == NetSession.Role.LOCAL or int(pd.get("pid", 0)) == ctx.local_pid)
	var status: Label = UiScreenKit.label("YOU" if mine else ("PLAYER" if human else "AI"), &"CaptionLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	status.custom_minimum_size = Vector2(60.0, 0.0)
	h.add_child(status)
	var pb: ProgressBar = ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(220.0, 12.0)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.max_value = 100.0
	h.add_child(pb)
	_rows.append({"pid": int(pd.get("pid", 0)), "bar": pb, "human": human, "mine": mine})
	return row


func _progress_block() -> Control:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_tip = UiScreenKit.label("", &"SubLabel", true)
	_tip.custom_minimum_size = Vector2(0.0, 52.0)
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(_tip)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_phase = UiScreenKit.label("PREPARING", &"HeaderLabel")
	_phase.custom_minimum_size = Vector2(360.0, 0.0)
	row.add_child(_phase)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 100.0
	_bar.custom_minimum_size = Vector2(0.0, 18.0)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_bar)
	_pct = UiScreenKit.label("0%", &"NumLabel", false, HORIZONTAL_ALIGNMENT_RIGHT)
	_pct.custom_minimum_size = Vector2(70.0, 0.0)
	row.add_child(_pct)
	var cancel: Button = UiScreenKit.button("CANCEL", &"GhostButton", Vector2(160.0, 40.0))
	cancel.pressed.connect(_on_cancel)
	row.add_child(cancel)
	_show_tip(0)
	return v


func _faction_code(roster_id: String) -> String:
	var p: PackedStringArray = roster_id.split(".")
	return p[1] if p.size() >= 2 else ""


func _sub_key(roster_id: String) -> String:
	var p: PackedStringArray = roster_id.split(".")
	return "%s.%s" % [p[1], p[2]] if p.size() >= 3 and p[2] != "vanilla" else ""


func _roster_line(roster_id: String) -> String:
	var data: GameData = ctx.data if ctx != null else null
	if data == null:
		return roster_id
	var idx: int = data.roster_idx(roster_id)
	if idx < 0:
		return roster_id
	var r: DefRoster = data.rosters[idx]
	var fac: String = data.factions[r.faction].ui_name if r.faction >= 0 else ""
	return fac if r.is_vanilla else "%s  //  %s" % [fac, r.ui_title]


## A fill narrower than the bar's chamfer is a degenerate polygon for `UiStyleBox` (Linux dummy renderer logs an engine error), so
## tiny values show as empty.
func _drawable(v: float) -> float:
	return 0.0 if v < 4.0 else v


## Once the map exists: its terrain bake with the start markers in the players' colours.
func _update_preview() -> void:
	if _preview_done or ctx == null or ctx.job == null:
		return
	var m: MapData = ctx.job.map
	if m == null:
		return
	_preview_done = true
	_preview.texture = AppViewStage.bake_preview(m)
	_preview.busy = false
	var pos: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var txt: PackedStringArray = PackedStringArray()
	for pd: Variant in _cfg().get("players", []) as Array:
		var d: Dictionary = pd as Dictionary
		var rec: int = int(d.get("start", 0)) * MapData.SPAWN_STRIDE
		if rec + 1 < m.spawns.size():
			var cell: int = m.spawns[rec + 1]
			pos.append(Vector2((float(cell % m.w) + 0.5) / float(m.w), (float(cell / m.w) + 0.5) / float(m.h)))
			cols.append(UiPalette.team(int(d.get("color", 0))))
			txt.append(str(int(d.get("pid", 0)) + 1))
	_preview.set_markers(pos, cols, txt)


func _show_tip(i: int) -> void:
	_tip_i = i % _tips.size()
	_tip.text = "TIP  //  " + _tips[_tip_i]
	_tip.modulate.a = 0.0
	UiMotion.fade(self, _tip, 1.0, 0.4)


func _on_cancel() -> void:
	if ctx != null:
		if ctx.session != null and ctx.session.role != NetSession.Role.LOCAL:
			ctx.session.leave()  # LAN: tell the host (a client sends LEAVE, a host closes the game) before the context goes
		ctx.dispose()
		if ctx.is_replay:
			navigate.emit(&"replays", {})
			return
		if ctx.mission_id() != "":
			navigate.emit(&"campaign", {"select": ctx.mission_id()})  # a mission goes back to the campaign
			return
	navigate.emit(&"main_menu", {})


func on_escape() -> bool:
	return false


func _process(delta: float) -> void:
	_time += delta
	if _build_pending:
		if ctx == null:
			_fetch_ctx()
		if ctx == null or ctx.config.is_empty():
			return
		_connect_progress()
		_build_pending = false
		_apply_local_skin()
		_build()
	var target: float = 0.0
	var label: String = "Preparing"
	if ctx != null and ctx.job != null:
		var job: AppMatchJob = ctx.job
		target = float(job.progress_pct())
		label = job.phase_name()
	_update_preview()
	_shown = move_toward(_shown, target, delta * 160.0)
	_bar.value = _drawable(_shown)
	_pct.text = "%d%%" % roundi(_shown)
	_phase.text = label.to_upper()
	for r: Dictionary in _rows:
		var v: float = _shown if bool(r["human"]) else minf(_shown + 6.0, 100.0)
		if bool(r["human"]) and not bool(r["mine"]) and ctx != null and ctx.session != null and ctx.session.role != NetSession.Role.LOCAL:
			v = float(_remote.get(int(r["pid"]), 0))  # another computer: what it reported
		(r["bar"] as ProgressBar).value = _drawable(v)
	_tip_t += delta
	if _tip_t >= TIP_EVERY_S:
		_tip_t = 0.0
		_show_tip(_tip_i + 1)
