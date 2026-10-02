class_name UiScreenOptions
extends UiScreen
## Options (ui.md 5.18, UI-06b): a tab per page (Graphics, Audio, Controls, Interface, Network, Storage), every page generated
## from `AppSettingsSchema` by a `UiOptionsPage` subclass. Every change applies at once through the settings node (live
## preview, debounced save); window mode, resolution and vsync open the 15-second "Keep these settings?" dialog that reverts
## itself. Footer: Revert (the values seen when the page opened), Reset page, Back (flushes the settings file).
## Params: `{page: StringName = &"graphics"}`. Other screens call `UiScreenOptions.open(page)`; the in-match game menu
## (`UiDlgGameMenu`) closes itself first and then calls it, because dialogs sit above pushed screens.

const CONTENT_W: float = 1120.0
const PAGE_CLASSES: Dictionary = {
	&"graphics": "UiOptionsPageGraphics", &"audio": "UiOptionsPageAudio", &"controls": "UiOptionsPageControls",
	&"interface": "UiOptionsPageInterface", &"network": "UiOptionsPageNetwork", &"storage": "UiOptionsPageStorage",
}

## The settings node: the `AppSettings` autoload unless a test injects a double before `enter`.
var settings: Node = null
## Shows a dialog; default = the `AppScenes` modal stack, else added to this screen. Tests replace it.
var modal_opener: Callable = Callable()
## Optional audio port for the slider tick.
var audio_port: UiAudioPort = null

var current: StringName = &"graphics"
var page: UiOptionsPage = null
var keep_dialog: UiDlgKeepSettings = null

var _tabs: UiTabBar = null
var _scroll: ScrollContainer = null
var _title_page: Label = null
var _revert_btn: Button = null
var _reset_btn: Button = null
var _back_btn: Button = null
var _notice: Label = null
var _pending_keep: Dictionary = {}  ## id -> value before, while the keep dialog is open


func _init() -> void:
	super._init()
	screen_id = &"options"


## Opens the options overlay over the current screen (main menu, lobby or a running match); false when the app shell is not there.
static func open(page_id: StringName = &"graphics") -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("AppState") if tree != null else null
	if state == null:
		return false
	state.call("push_mode", AppFlow.Mode.OPTIONS, {"page": page_id})
	return true


func enter(params: Dictionary) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if settings == null:
		settings = get_tree().root.get_node_or_null("AppSettings")
	var want: StringName = StringName(str(params.get("page", "graphics")))
	_build()
	open_page(want if UiOptionsLayout.is_page(want) else &"graphics")


func exit() -> void:
	if settings != null and settings.has_method("flush"):
		settings.call("flush")
	if keep_dialog != null and not keep_dialog.is_closed():
		keep_dialog.close(UiDlgKeepSettings.KEEP)


func default_focus() -> Control:
	return _tabs


func on_escape() -> bool:
	if page is UiOptionsPageControls:
		var kb: UiOptionsKeybinds = (page as UiOptionsPageControls).keybinds
		if kb != null and not kb.capturing.is_empty():
			kb.cancel_capture()
			return true
	return false


# ---------------------------------------------------------------------------------------------------------------- layout

func _build() -> void:
	UiScreenKit.backdrop(self, Color(UiPalette.BG_DEEP, 0.97))
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	UiLayerRoot.fill(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_3)
	margin.add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", UiMetrics.SP_5)
	col.add_child(head)
	var title: Label = UiScreenKit.wordmark("OPTIONS", 40, 800, 4, UiPalette.TEXT)
	head.add_child(title)
	_title_page = UiScreenKit.label("", &"SubLabel")
	_title_page.add_theme_color_override("font_color", UiScreenKit.accent(self))
	_title_page.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_title_page)
	head.add_child(UiScreenKit.spacer(0.0, true))
	_notice = UiScreenKit.label("", &"CaptionLabel")
	_notice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_notice)
	_tabs = UiTabBar.new()
	_tabs.set_focusable(true)
	var tabs: Array[Dictionary] = []
	for p: Dictionary in UiOptionsLayout.PAGES:
		tabs.append({"id": p["id"], "text": str(p["title"]).to_upper()})
	_tabs.set_tabs(tabs)
	_tabs.tab_selected.connect(func(_i: int, id: StringName) -> void: open_page(id))
	col.add_child(_tabs)
	var mid: HBoxContainer = HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mid)
	mid.add_child(UiScreenKit.spacer(0.0, true))
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(CONTENT_W, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(panel)
	mid.add_child(UiScreenKit.spacer(0.0, true))
	var pm: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pm.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pm)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm.add_child(_scroll)
	var foot: HBoxContainer = HBoxContainer.new()
	foot.add_theme_constant_override("separation", UiMetrics.SP_3)
	col.add_child(foot)
	_back_btn = UiScreenKit.button("BACK", &"GhostButton", Vector2(150.0, 44.0))
	_back_btn.pressed.connect(func() -> void: back_requested.emit())
	foot.add_child(_back_btn)
	foot.add_child(UiScreenKit.spacer(0.0, true))
	_revert_btn = UiScreenKit.button("Revert changes", &"", Vector2(180.0, 44.0))
	_revert_btn.tooltip_text = "Restores the values this page had when you opened it."
	_revert_btn.pressed.connect(revert_page)
	foot.add_child(_revert_btn)
	_reset_btn = UiScreenKit.button("Reset page to defaults", &"", Vector2(230.0, 44.0))
	_reset_btn.pressed.connect(reset_page)
	foot.add_child(_reset_btn)


## Shows a page (creates it on first use, keeps it afterwards so its snapshot survives tab switches).
func open_page(id: StringName) -> void:
	if not UiOptionsLayout.is_page(id):
		return
	current = id
	if page != null:
		if page.get_parent() != null:
			page.get_parent().remove_child(page)
		page.queue_free()
		page = null
	var script: Script = UiDraw.optional_script(StringName(PAGE_CLASSES[id]))
	page = script.new() as UiOptionsPage if script != null else UiOptionsPage.new()
	page.setup(id, settings)
	if page is UiOptionsPageAudio:
		(page as UiOptionsPageAudio).audio_port = audio_port if audio_port != null else _facade_port()
	page.setting_changed.connect(_on_setting_changed)
	if page is UiOptionsPageControls and (page as UiOptionsPageControls).keybinds != null:
		(page as UiOptionsPageControls).keybinds.dialog_requested.connect(show_dialog)
	_scroll.add_child(page)
	_scroll.scroll_vertical = 0
	_title_page.text = UiOptionsLayout.title_of(id).to_upper()
	_tabs.select_id(id)
	_update_footer()
	if is_inside_tree():
		UiFocusPolicy.apply_menu(page)


func page_ids() -> Array[StringName]:
	return UiOptionsLayout.page_ids()


# ---------------------------------------------------------------------------------------------------------------- footer actions

func _update_footer() -> void:
	if _revert_btn != null and page != null:
		_revert_btn.disabled = page.changed_count() == 0
		var storage: bool = current == &"storage"
		_revert_btn.visible = not storage
		_reset_btn.visible = not storage


## Restores the values this page had when it opened.
func revert_page() -> int:
	if page == null:
		return 0
	var n: int = page.revert()
	_update_footer()
	_say("Reverted %d setting%s." % [n, "" if n == 1 else "s"] if n > 0 else "Nothing to revert.")
	return n


func reset_page() -> void:
	if page == null:
		return
	page.reset_defaults()
	_update_footer()
	_say("Page reset to defaults.")


func _say(text: String) -> void:
	if _notice != null:
		_notice.text = text


# ---------------------------------------------------------------------------------------------------------------- keep dialog

## The `Snd` facade as a UI audio port when audio is installed (`AppAudio`), else null (silent, tests).
func _facade_port() -> UiAudioPort:
	var tree: SceneTree = get_tree()
	var snd: Node = tree.root.get_node_or_null("Snd") if tree != null else null
	if snd == null or not snd.has_method("is_ready") or not bool(snd.call("is_ready")):
		return null
	return UiAudioPortSnd.new(snd)


func _on_setting_changed(id: String, _value: Variant, before: Variant) -> void:
	_update_footer()
	if not UiOptionsLayout.KEEP_IDS.has(id):
		return
	if not _pending_keep.has(id):  # a second change while the dialog is up keeps the first "before"
		_pending_keep[id] = before
	if keep_dialog != null and not keep_dialog.is_closed():
		return
	keep_dialog = UiDlgKeepSettings.new(_keep_summary())
	keep_dialog.closed.connect(_on_keep_closed)
	show_dialog(keep_dialog)


func _keep_summary() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: String in _pending_keep:
		lines.append("%s: %s" % [UiOptionsText.label(id), UiOptionsText.choice(id, page.store().get_value(StringName(id))) if id != "video/resolution" \
			else str(page.store().get_value(&"video/resolution"))])
	return "\n".join(lines)


func _on_keep_closed(result: int) -> void:
	if result != UiDlgKeepSettings.KEEP:
		for id: String in _pending_keep:
			settings.call("set_value", StringName(id), _pending_keep[id])
		if page != null:
			page.refresh()
		_say("Display settings reverted.")
	else:
		if page != null:
			page.commit_snapshot()
		_say("Display settings kept.")
	_pending_keep.clear()


## Answers the open keep dialog (tests, and the countdown uses `tick`).
func answer_keep(keep: bool) -> void:
	if keep_dialog != null and not keep_dialog.is_closed():
		keep_dialog.close(UiDlgKeepSettings.KEEP if keep else UiDlgKeepSettings.REVERT)


func show_dialog(dlg: UiDialog) -> void:
	if modal_opener.is_valid():
		modal_opener.call(dlg)
		return
	var scenes: Node = get_tree().root.get_node_or_null("AppScenes") if is_inside_tree() else null
	if scenes != null:
		scenes.call("modal", dlg)
		return
	var cc: CenterContainer = CenterContainer.new()
	add_child(cc)
	UiLayerRoot.fill(cc)
	cc.add_child(dlg)
	dlg.closed.connect(func(_r: int) -> void: cc.queue_free())
