class_name UiScreenMainMenu
extends UiScreen
## Main menu (ui.md 5.1.3 / 10.6): the 3D showcase backdrop (`AppShowcase`: the real view on a small generated map with a few of
## the featured faction's units, slow camera orbit), a vignette with letterbox bars, the wordmark, the hero button stack, status
## chips and a "featured power" card that rotates every 30 s with a 0.6 s cross-fade (the skin accent follows the faction).
## Buttons whose target screen is not in the project yet (LAN browser, replays, options) are disabled with a hint.
## Params: `{first_run: bool}` (opens the first-run dialog, `UiDlgFirstRun`, once the menu is up).

const FEATURE_EVERY_S: float = 30.0

var _featured: int = 0
var _data: GameData = null
var _buttons: Array[Button] = []
var _card: PanelContainer = null
var _card_badge: UiFactionBadge = null
var _card_name: Label = null
var _card_motto: Label = null
var _card_identity: Label = null
var _card_tags: HBoxContainer = null
var _logo_badge: UiFactionBadge = null
var _subtitle: Label = null
var _feature_t: float = 0.0
var _curtain: ColorRect = null
var _vignette: UiVignette = null
var _showcase: AppShowcase = null
var _first: Button = null
var _rule: ColorRect = null


func _init() -> void:
	super._init()
	screen_id = &"main_menu"


func enter(params: Dictionary) -> void:
	var state: Node = get_tree().root.get_node_or_null("AppState")
	_data = state.get("data") as GameData if state != null else null
	if state != null and state.get("match_ctx") is AppMatchContext:
		(state.get("match_ctx") as AppMatchContext).dispose()
		state.set("match_ctx", null)
	_featured = _pick_featured(params)
	_apply_skin()
	_build()
	_fill_card()
	_start_showcase()
	set_process(true)
	if bool(params.get("first_run", false)):
		_open_first_run.call_deferred()
	if str(params.get("message", "")) != "":
		UiDlgMessage.open("Game closed", str(params["message"]))  # a LAN game that ended while loading


func exit() -> void:
	set_process(false)


## First launch (`meta/first_run`): name, quality, UI scale and colour mode. Start or Use defaults clears the flag.
func _open_first_run() -> void:
	if is_inside_tree():
		UiDlgFirstRun.open()


func default_focus() -> Control:
	return _first


func on_escape() -> bool:
	return true  # the main menu never quits on Escape


func can_leave() -> bool:
	return false


func _pick_featured(params: Dictionary) -> int:
	if _data == null or _data.factions.is_empty():
		return 0
	var want: String = str(params.get("faction", AppLaunchArgs.parse(OS.get_cmdline_user_args()).faction))
	for i: int in _data.factions.size():
		if _data.factions[i].code.to_lower() == want.to_lower():
			return i
	return int(Time.get_unix_time_from_system() / 60.0) % _data.factions.size()


func _faction_code() -> String:
	return _data.factions[_featured].code.to_lower() if _data != null and _featured < _data.factions.size() else ""


func _apply_skin() -> void:
	UiThemeService.rebuild(UiSkinSet.shared().skin_for(_faction_code()))


# ---------------------------------------------------------------- construction

func _build() -> void:
	var acc: Color = UiScreenKit.accent(self)
	_curtain = UiScreenKit.backdrop(self, UiPalette.BG_DEEP)
	_vignette = UiVignette.new(0.75, 0.065, 0.55, 0.02, acc)
	add_child(_vignette)
	_build_logo()
	_build_buttons()
	_build_status()
	_build_card()
	_build_footer()


func _build_logo() -> void:
	var box: HBoxContainer = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 26)
	add_child(box)
	box.position = Vector2(100.0, 92.0)
	_logo_badge = UiFactionBadge.new(_faction_code(), 96.0)
	_logo_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_logo_badge)
	var words: VBoxContainer = VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", -6)
	box.add_child(words)
	words.add_child(UiScreenKit.wordmark("MERIDIAN", 92, 900, 6, UiPalette.TEXT))
	_subtitle = UiScreenKit.wordmark("FRACTURE", 40, 500, 30, UiScreenKit.accent(self))
	words.add_child(_subtitle)
	var tag: Label = UiScreenKit.label("REAL-TIME STRATEGY   //   2086   //   EIGHT POWERS, ONE NETWORK", &"DimLabel")
	add_child(tag)
	tag.position = Vector2(104.0, 262.0)


func _build_buttons() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	column.position = UiMetrics.MENU_POS
	var entries: Array = [
		["CAMPAIGN", &"campaign", {}, DefMissionTable.of(_data) != null and not DefMissionTable.of(_data).missions.is_empty(), "No missions are installed."],
		["SKIRMISH", &"lobby", {"role": "local", "back": &"main_menu"}, true, "Play against the computer on a generated map."],
		["LAN MULTIPLAYER", &"lan_browser", {}, UiDraw.optional_script(&"UiScreenLanBrowser") != null, "Available with the network module."],
		["REPLAYS", &"replays", {}, UiDraw.optional_script(&"UiScreenReplays") != null, "Available with the replay browser."],
		["OPTIONS", &"options", {}, UiDraw.optional_script(&"UiScreenOptions") != null, "Available with the options pages."],
		["FIELD MANUAL", &"field_manual", {}, UiDraw.optional_script(&"UiScreenFieldManual") != null, "Available with the Field Manual."],
		["CREDITS", &"credits", {}, true, ""],
		["QUIT", &"quit", {}, true, ""]]
	for e: Array in entries:
		var b: Button = UiScreenKit.button(String(e[0]), &"HeroButton", UiMetrics.MENU_BTN)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var target: StringName = e[1]
		var p: Dictionary = e[2]
		b.disabled = not bool(e[3])
		if b.disabled:
			b.tooltip_text = String(e[4])
		b.pressed.connect(func() -> void: navigate.emit(target, p))
		column.add_child(b)
		_buttons.append(b)
		if _first == null and not b.disabled:
			_first = b
	_rule = ColorRect.new()
	var rule: ColorRect = _rule
	rule.color = UiScreenKit.accent(self)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = UiMetrics.MENU_POS + Vector2(-12.0, 0.0)
	rule.size = Vector2(3.0, float(entries.size()) * (UiMetrics.MENU_BTN.y + 10.0) - 10.0)
	add_child(rule)


func _build_status() -> void:
	var chip: PanelContainer = PanelContainer.new()
	chip.theme_type_variation = &"InsetPanel"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	chip.add_child(h)
	var lan: Label = UiScreenKit.label("LAN  READY" if UiDraw.optional_script(&"UiScreenLanBrowser") != null else "LAN  OFFLINE", &"CaptionLabel")
	h.add_child(lan)
	var profile: String = "COMMANDER"
	var st: Node = get_tree().root.get_node_or_null("AppSettings")
	if st != null and st.get("store") is AppSettingsStore:
		var nm: Variant = (st.get("store") as AppSettingsStore).get_value(&"net/player_name")
		if nm != null and str(nm) != "":
			profile = str(nm).to_upper()
	h.add_child(UiScreenKit.label("PROFILE  " + profile, &"CaptionLabel"))
	var hash_text: String = UiFormatLite.hash8(_data.data_hash()) if _data != null else "----"
	h.add_child(UiScreenKit.label("DATA HASH  " + hash_text, &"CaptionLabel"))
	add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.offset_top = 40.0
	chip.offset_right = -48.0


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(540.0, 0.0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	_card.add_child(m)
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	m.add_child(h)
	_card_badge = UiFactionBadge.new(_faction_code(), 104.0)
	_card_badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(_card_badge)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiScreenKit.label("FEATURED POWER", &"CaptionLabel"))
	_card_name = UiScreenKit.label("", &"HeaderLabel", true)
	_card_name.add_theme_font_size_override("font_size", 20)
	v.add_child(_card_name)
	_card_motto = UiScreenKit.label("", &"SubLabel", true)
	v.add_child(_card_motto)
	_card_identity = UiScreenKit.label("", &"DimLabel", true)
	v.add_child(_card_identity)
	_card_tags = HBoxContainer.new()
	_card_tags.add_theme_constant_override("separation", 14)
	v.add_child(_card_tags)
	add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -56.0
	_card.offset_bottom = -64.0


func _build_footer() -> void:
	var foot: Label = UiScreenKit.label("v%s   //   %s   //   %s" % [AppInfo.version(), AppInfo.engine_string().to_upper(),
		RenderingServer.get_current_rendering_method().to_upper()], &"CaptionLabel")
	add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 104.0
	foot.offset_top = -52.0


func _fill_card() -> void:
	if _data == null or _featured >= _data.factions.size():
		return
	var f: DefFaction = _data.factions[_featured]
	_card_name.text = f.ui_name.to_upper()
	_card_motto.text = "\"%s\"" % f.ui_motto
	_card_identity.text = f.ui_identity
	_card_badge.faction_code = f.code.to_lower()
	_logo_badge.faction_code = f.code.to_lower()
	var acc: Color = UiScreenKit.accent(self)
	_subtitle.add_theme_color_override("font_color", acc)
	_subtitle.add_theme_color_override("font_shadow_color", Color(acc, 0.35))
	_rule.color = acc
	for c: Node in _card_tags.get_children():
		c.queue_free()
	for ri: int in f.sub_rosters:
		var tag: Label = UiScreenKit.label(_data.rosters[ri].id.get_slice(".", 2).replace("_", " ").to_upper(), &"CaptionLabel")
		tag.add_theme_color_override("font_color", UiScreenKit.accent(self))
		_card_tags.add_child(tag)


# ---------------------------------------------------------------- showcase and rotation

func _start_showcase() -> void:
	if _data == null or DisplayServer.get_name() == "headless":
		_curtain.color.a = 0.0
		return
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes")
	if scenes == null:
		return
	_showcase = AppShowcase.new()
	_showcase.name = "Showcase"
	scenes.call("set_backdrop", _showcase)
	_showcase.ready_to_show.connect(func() -> void: UiMotion.fade(self, _curtain, 0.0, 0.9))
	_showcase.begin(_data, _faction_code())


func _process(delta: float) -> void:
	_feature_t += delta
	if _feature_t >= FEATURE_EVERY_S:
		_feature_t = 0.0
		_rotate_featured()
	_vignette.set_time(Time.get_ticks_msec() / 1000.0)


func _rotate_featured() -> void:
	if _data == null or _data.factions.size() < 2:
		return
	_featured = (_featured + 1) % _data.factions.size()
	var tw: Tween = create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		_apply_skin()
		_fill_card())
	tw.tween_property(_card, "modulate:a", 1.0, 0.3)
