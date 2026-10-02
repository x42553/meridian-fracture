class_name UiScreenMissionBriefing
extends UiScreen
## The mission briefing (MIS2): the mission title and faction, the briefing text blocks (heading, text, and a Field Manual link for
## a block that names a bible entry), a map preview thumbnail with the start positions of every player, the objectives preview
## (primary and optional; hidden ones stay hidden), the difficulty selector (the AI levels: Easy, Medium, Hard, Brutal) and START.
## START launches the mission as a LOCAL match through `AppMission.start` and shows the loading screen. Params: `{mission: id}`.

const PREVIEW_PX: float = 330.0
const PREVIEW_PX_COMPACT: float = 250.0

var mission_id: String = ""
var difficulty: int = AppMission.DEFAULT_DIFFICULTY
var def: DefMission = null

var _data: GameData = null
var _campaign: AppCampaign = null
var _start: Button = null
var _back: Button = null
var _diff_buttons: Array[Button] = []
var _diff_blurb: Label = null
var _preview: UiMapPreview = null
var _job: MapGenJob = null
var _preview_cfg: Dictionary = {}
var _entry: UiCampaignModel.Entry = null

## Baked previews by map key (the map is the same on every visit).
static var _cache: Dictionary = {}


static func release_statics() -> void:
	_cache.clear()


func _init() -> void:
	super._init()
	screen_id = &"mission_briefing"


func enter(params: Dictionary) -> void:
	mission_id = str(params.get("mission", ""))
	var state: Node = get_tree().root.get_node_or_null("AppState")
	_data = state.get("data") as GameData if state != null else null
	_campaign = (state.get("profile") as AppProfile).campaign if state != null and state.get("profile") is AppProfile else AppCampaign.new()
	def = AppMission.def_of(_data, mission_id)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if def == null:
		_build_missing()
		return
	_entry = UiCampaignModel.build(_data, _campaign).entry(mission_id)
	difficulty = _campaign.last_difficulty(mission_id, AppMission.DEFAULT_DIFFICULTY)
	if params.has("difficulty"):
		difficulty = AppMission.clamp_difficulty(int(params["difficulty"]))
	UiThemeService.rebuild(UiSkinSet.shared().skin_for(_entry.faction_code if _entry != null else ""))
	_build()
	_select_difficulty(difficulty)
	_begin_preview()
	setup_menu_focus()


func exit() -> void:
	if _job != null:
		_job.cancel()
		_job = null
	set_process(false)


func default_focus() -> Control:
	return _start


## Escape and the back button return to the campaign with this mission still selected.
func on_escape() -> bool:
	_leave()
	return true


func _leave() -> void:
	navigate.emit(&"campaign", {"select": mission_id})


# ---------------------------------------------------------------- construction

## The map preview edge: smaller on a short window (720p) so the whole page fits.
func preview_px() -> float:
	var h: float = size.y if size.y > 0.0 else float(get_viewport_rect().size.y)
	return PREVIEW_PX_COMPACT if h < 900.0 else PREVIEW_PX


func _build_missing() -> void:
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	var l: Label = UiScreenKit.label("This mission is not installed.", &"SubLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_back = UiScreenKit.button("CAMPAIGN", &"PrimaryButton", Vector2(220.0, 52.0))
	_back.pressed.connect(func() -> void: back_requested.emit())
	add_child(_back)
	_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_back.position.y += 70.0


func _build() -> void:
	var acc: Color = UiScreenKit.accent(self)
	UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	add_child(UiVignette.new(0.8, 0.05, 0.35, 0.02, acc))
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	UiLayerRoot.fill(margin)
	margin.add_theme_constant_override("margin_left", int(UiMetrics.SCREEN_MARGIN.x))
	margin.add_theme_constant_override("margin_top", int(UiMetrics.SCREEN_MARGIN.y))
	margin.add_theme_constant_override("margin_right", int(UiMetrics.SCREEN_MARGIN.z))
	margin.add_theme_constant_override("margin_bottom", int(UiMetrics.SCREEN_MARGIN.w))
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", UiMetrics.SP_3)
	margin.add_child(page)
	page.add_child(_header(acc))
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiMetrics.SP_5)
	page.add_child(body)
	body.add_child(_briefing_panel())
	body.add_child(_side_column())
	page.add_child(_footer())


func _header(acc: Color) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var code: String = _entry.faction_code if _entry != null else ""
	var badge: UiFactionBadge = UiFactionBadge.new(code, 84.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var group: String = UiCampaignModel.group_label(def.group, def.order)
	var cap: Label = UiScreenKit.label("MISSION BRIEFING  //  " + group, &"CaptionLabel")
	cap.add_theme_color_override("font_color", acc)
	box.add_child(cap)
	var title: Label = UiScreenKit.wordmark(def.ui_title.to_upper(), 48, 850, 6, UiPalette.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(title)
	var who: String = _entry.faction_name.to_upper() if _entry != null and _entry.faction_name != "" else ""
	var line: Label = UiScreenKit.label(who, &"HeaderLabel")
	line.add_theme_font_size_override("font_size", 16)
	box.add_child(line)
	return row


func _briefing_panel() -> Control:
	var made: Dictionary = UiScreenKit.panel("Briefing", "CLASSIFIED  //  EYES ONLY", &"", 16, 12)
	var panel: PanelContainer = made["panel"] as PanelContainer
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = made["body"] as VBoxContainer
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var blocks: VBoxContainer = VBoxContainer.new()
	blocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blocks.add_theme_constant_override("separation", 18)
	scroll.add_child(blocks)
	for bv: Variant in def.ui_briefing:
		var b: Dictionary = bv as Dictionary
		var blk: VBoxContainer = VBoxContainer.new()
		blk.add_theme_constant_override("separation", 6)
		blocks.add_child(blk)
		if str(b.get("heading", "")) != "":
			var h: Label = UiScreenKit.label(str(b["heading"]).to_upper(), &"HeaderLabel")
			h.add_theme_color_override("font_color", UiScreenKit.accent(self))
			blk.add_child(h)
		var t: Label = UiScreenKit.label(str(b.get("text", "")), &"", true)
		t.add_theme_font_size_override("font_size", 20)
		blk.add_child(t)
		var lore: String = str(b.get("lore", ""))
		if lore != "":
			var link: Button = UiScreenKit.button("FIELD MANUAL  //  %s" % lore_name(lore), &"GhostButton", Vector2(0.0, 36.0))
			link.alignment = HORIZONTAL_ALIGNMENT_LEFT
			link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			link.pressed.connect(func() -> void: navigate.emit(&"field_manual", lore_params(_data, lore, _entry.roster_id if _entry != null else "")))
			blk.add_child(link)
	if def.ui_briefing.is_empty():
		blocks.add_child(UiScreenKit.label("No briefing is available for this mission.", &"DimLabel"))
	return panel


func _side_column() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	var px: float = preview_px()
	col.custom_minimum_size = Vector2(px + 40.0, 0.0)
	col.add_theme_constant_override("separation", UiMetrics.SP_3)
	# map preview
	var mp: Dictionary = UiScreenKit.panel("Theatre", UiMapNames.family_name(def.map_family).to_upper() + "  //  %d x %d" % [def.map_size, def.map_size], &"", 12, 8)
	col.add_child(mp["panel"] as Control)
	_preview = UiMapPreview.new()
	_preview.custom_minimum_size = Vector2(px, px)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	(mp["body"] as VBoxContainer).add_child(_preview)
	# objectives
	var ob: Dictionary = UiScreenKit.panel("Objectives", "", &"", 12, 6)
	col.add_child(ob["panel"] as Control)
	_fill_objectives(ob["body"] as VBoxContainer)
	return col


func _fill_objectives(v: VBoxContainer) -> void:
	var any: bool = false
	for pass_idx: int in 2:
		for o: DefMissionObjective in def.objectives:
			var primary: bool = o.kind == DefMissionObjective.Kind.PRIMARY
			if o.kind == DefMissionObjective.Kind.HIDDEN or o.initial == 0 or primary != (pass_idx == 0):
				continue
			any = true
			var h: HBoxContainer = HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			var tag: Label = UiScreenKit.label("PRIMARY" if primary else "OPTIONAL", &"CaptionLabel")
			tag.custom_minimum_size = Vector2(76.0, 0.0)
			tag.add_theme_color_override("font_color", UiScreenKit.accent(self) if primary else UiPalette.TEXT_MUTE)
			tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			h.add_child(tag)
			var t: Label = UiScreenKit.label(o.ui_text, &"", true)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(t)
			v.add_child(h)
	var hidden: int = 0
	for o2: DefMissionObjective in def.objectives:
		hidden += 1 if o2.initial == 0 or o2.kind == DefMissionObjective.Kind.HIDDEN else 0
	if hidden > 0:
		v.add_child(UiScreenKit.label(("%d further objective%s revealed during the mission." if any else "%d objective%s revealed during the mission.") % [hidden, " is" if hidden == 1 else "s are"], &"DimLabel", true))


func _footer() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiMetrics.SP_4)
	_back = UiScreenKit.button("CAMPAIGN", &"", Vector2(190.0, 56.0))
	_back.pressed.connect(_leave)
	row.add_child(_back)
	# difficulty: the four AI levels as one segmented row with the blurb under it
	var dv: VBoxContainer = VBoxContainer.new()
	dv.add_theme_constant_override("separation", 2)
	row.add_child(dv)
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	dv.add_child(chips)
	var cap: Label = UiScreenKit.label("DIFFICULTY", &"CaptionLabel")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.custom_minimum_size = Vector2(100.0, 0.0)
	chips.add_child(cap)
	var grp: ButtonGroup = ButtonGroup.new()
	for i: int in AppMission.difficulty_count():
		var b: Button = UiScreenKit.button(AppMission.difficulty_name(i).to_upper(), &"TabButton", Vector2(92.0, 40.0))
		b.toggle_mode = true
		b.button_group = grp
		var idx: int = i
		b.pressed.connect(func() -> void: _select_difficulty(idx))
		chips.add_child(b)
		_diff_buttons.append(b)
	_diff_blurb = UiScreenKit.label("", &"CaptionLabel")
	_diff_blurb.custom_minimum_size = Vector2(0.0, 16.0)
	dv.add_child(_diff_blurb)
	var record: Label = UiScreenKit.label(_record_text(), &"DimLabel")
	record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(record)
	_start = UiScreenKit.button("START MISSION", &"PrimaryButton", Vector2(280.0, 56.0))
	_start.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_start.pressed.connect(start_mission)
	row.add_child(_start)
	return row


func _record_text() -> String:
	if _campaign.completed(mission_id):
		return "COMPLETED  //  BEST %s  //  HIGHEST DIFFICULTY %s" % [UiFormatLite.clock(_campaign.best_ticks(mission_id) * SimConfig.TICK_MS / 1000),
			AppMission.difficulty_name(_campaign.best_difficulty(mission_id)).to_upper()]
	var plays: int = _campaign.plays(mission_id)
	return "ATTEMPTS  %d" % plays if plays > 0 else ""


# ---------------------------------------------------------------- difficulty and start

func _select_difficulty(d: int) -> void:
	difficulty = AppMission.clamp_difficulty(d)
	for i: int in _diff_buttons.size():
		_diff_buttons[i].set_pressed_no_signal(i == difficulty)
	if _diff_blurb != null:
		_diff_blurb.text = AppMission.DIFFICULTY_BLURBS[difficulty]
	_campaign.remember_difficulty(mission_id, difficulty)


## Launches the mission (the START button); the loading screen follows.
func start_mission() -> void:
	var ctx: AppMatchContext = AppMission.start(mission_id, difficulty, {})
	if ctx == null:
		UiDlgMessage.open("Mission could not start", NetSession.last_create_error if NetSession.last_create_error != "" else "The match could not be created.")
		return
	navigate.emit(&"loading", {"kind": "match", "title": def.ui_title, "mission": mission_id})


# ---------------------------------------------------------------- map preview

func _begin_preview() -> void:
	if DisplayServer.get_name() == "headless" or _preview == null:
		return
	var cfg: Dictionary = AppMission.build_config(_data, mission_id, difficulty)
	_preview_cfg = cfg["map"] as Dictionary
	var key: String = JSON.stringify(_preview_cfg, "", true)
	if _cache.has(key):
		_show_preview(_cache[key] as Dictionary)
		return
	_preview.busy = true
	_job = MapGenJob.begin(_preview_cfg, null, true)
	set_process(true)


func _process(_delta: float) -> void:
	if _job == null:
		set_process(false)
		return
	if not _job.step(0):
		return
	var m: MapData = _job.result()
	_job = null
	set_process(false)
	if m == null:
		_preview.busy = false
		return
	var starts: Dictionary = {}
	for r: int in m.spawns.size() / MapData.SPAWN_STRIDE:
		var cell: int = m.spawns[r * MapData.SPAWN_STRIDE + 1]
		starts[m.spawns[r * MapData.SPAWN_STRIDE]] = Vector2((float(cell % m.w) + 0.5) / float(m.w), (float(cell / m.w) + 0.5) / float(m.h))
	var entry: Dictionary = {"tex": AppViewStage.bake_preview(m), "starts": starts}
	_cache[JSON.stringify(_preview_cfg, "", true)] = entry
	_show_preview(entry)


func _show_preview(entry: Dictionary) -> void:
	_preview.texture = entry["tex"] as Texture2D
	_preview.busy = false
	var starts: Dictionary = entry["starts"] as Dictionary
	var pos: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var txt: PackedStringArray = PackedStringArray()
	for p: DefMissionPlayer in def.players:
		if starts.has(p.start_slot):
			pos.append(starts[p.start_slot] as Vector2)
			cols.append(UiPalette.team(p.color))
			txt.append(str(p.slot + 1))
	_preview.set_markers(pos, cols, txt)


# ---------------------------------------------------------------- helpers

## "unit.napc.guardian_tank" -> "GUARDIAN TANK"; "faction.nec" -> "NEC".
static func lore_name(lore_id: String) -> String:
	var parts: PackedStringArray = lore_id.split(".")
	return parts[parts.size() - 1].replace("_", " ").to_upper()


## Field Manual params for a lore id: the roster to open and the entry to focus.
static func lore_params(data: GameData, lore_id: String, human_roster: String) -> Dictionary:
	var out: Dictionary = {"focus_id": lore_id}
	var roster: String = human_roster
	if lore_id.begins_with("roster."):
		roster = lore_id
	elif lore_id.begins_with("faction.") and data != null:
		var code: String = lore_id.get_slice(".", 1)
		for f: DefFaction in data.factions:
			if f.code.to_lower() == code and f.vanilla_roster >= 0 and f.vanilla_roster < data.rosters.size():
				roster = data.rosters[f.vanilla_roster].id
	if roster != "":
		out["roster_id"] = roster
	return out
