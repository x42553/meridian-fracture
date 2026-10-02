class_name UiDlgFirstRun
extends UiDialog
## First-run dialog (ui.md 5.2.2): one compact dialog on the very first start. Commander name (the sanitised OS user name),
## graphics preset pre-set to the view's recommendation with the adapter name shown, interface scale (Auto = 100 %) and the
## colour-vision safe palette with a live swatch of the eight team colours. Confirming writes the settings and clears
## `meta/first_run`; nothing else is asked (no account, no telemetry). Escape does not dismiss it: "Use defaults" is the way out.
## Result codes: 1 confirmed, 2 defaults.

const CONFIRM: int = 1
const DEFAULTS: int = 2
const SCALES: Array[int] = [100, 125, 150, 175, 200]

var settings: Node = null
var name_edit: LineEdit = null
var quality_pick: OptionButton = null
var scale_pick: OptionButton = null
var cvd_check: CheckBox = null
var swatch: UiTeamSwatch = null


func _init(settings_node: Node = null) -> void:
	super._init("Welcome, Commander", 620)
	settings = settings_node
	dismiss_on_escape = false
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_3)
	set_content(col)
	col.add_child(UiScreenKit.label("Three quick choices. You can change all of them later in Options.", &"DimLabel", true))
	name_edit = LineEdit.new()
	name_edit.max_length = AppSettingsSchema.NAME_MAX
	name_edit.text = AppProfile.default_name()
	name_edit.custom_minimum_size = Vector2(300.0, 36.0)
	name_edit.accessibility_name = "Commander name"
	col.add_child(_row("Commander name", name_edit))
	quality_pick = OptionButton.new()
	quality_pick.custom_minimum_size = Vector2(300.0, 36.0)
	quality_pick.accessibility_name = "Graphics quality"
	for p: int in 5:
		quality_pick.add_item(AppGraphics.preset_name(p) + (" (recommended)" if p == AppGraphics.recommend() else ""), p)
	quality_pick.select(AppGraphics.recommend())
	col.add_child(_row("Graphics", quality_pick))
	col.add_child(UiScreenKit.label("Detected: %s" % RenderingServer.get_video_adapter_name(), &"CaptionLabel"))
	scale_pick = OptionButton.new()
	scale_pick.custom_minimum_size = Vector2(300.0, 36.0)
	scale_pick.accessibility_name = "Interface scale"
	for s: int in SCALES:
		scale_pick.add_item("Auto (100%)" if s == 100 else "%d%%" % s, s)
	col.add_child(_row("Interface scale", scale_pick))
	cvd_check = CheckBox.new()
	cvd_check.text = "Colour-vision safe palette"
	cvd_check.focus_mode = Control.FOCUS_ALL
	cvd_check.tooltip_text = "Separates the eight team colours for red-green and blue-yellow colour blindness."
	col.add_child(cvd_check)
	col.add_child(UiScreenKit.label("Separates the team colours for red-green and blue-yellow colour blindness.", &"CaptionLabel", true))
	swatch = UiTeamSwatch.new(146.0)
	cvd_check.toggled.connect(func(on: bool) -> void: swatch.set_mode("cvd" if on else "normal"))
	col.add_child(swatch)
	add_button("Use defaults", DEFAULTS)
	add_button("Start", CONFIRM, &"primary")
	closed.connect(_on_closed)


static func _row(caption: String, ctl: Control) -> Control:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", UiMetrics.SP_3)
	var l: Label = UiScreenKit.label(caption)
	l.custom_minimum_size = Vector2(150.0, 0.0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	h.add_child(ctl)
	return h


func default_focus() -> Control:
	return name_edit


## Opens the dialog on the modal stack of `AppScenes` (no-op without it); returns the dialog.
static func open(settings_node: Node = null) -> UiDlgFirstRun:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var node: Node = settings_node
	if node == null and tree != null:
		node = tree.root.get_node_or_null("AppSettings")
	var d: UiDlgFirstRun = UiDlgFirstRun.new(node)
	var scenes: Node = tree.root.get_node_or_null("AppScenes") if tree != null else null
	if scenes != null:
		scenes.call("modal", d)
	return d


## Values the dialog would write: `{id: value}` (the tests and `apply` share it).
func chosen() -> Dictionary:
	var name_text: String = AppProfile.sanitize_name(name_edit.text)
	return {
		"net/player_name": name_text,
		"video/quality": quality_pick.get_selected_id(),
		"video/ui_scale": scale_pick.get_selected_id(),
		"access/colour_mode": "cvd" if cvd_check.button_pressed else "normal",
	}


## Writes the chosen values (or leaves the defaults for `use_defaults`) and clears the first-run flag.
func apply(use_defaults: bool = false) -> void:
	if settings == null:
		return
	if not use_defaults:
		var values: Dictionary = chosen()
		for id: String in values:
			settings.call("set_value", StringName(id), values[id])
	settings.call("set_value", &"meta/first_run", false)
	settings.call("flush")


func _on_closed(result_code: int) -> void:
	apply(result_code != CONFIRM)
