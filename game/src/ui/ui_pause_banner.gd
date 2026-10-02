class_name UiPauseBanner
extends PanelContainer
## The pause banner (ui.md 5.16.2): "PAUSED - {name} paused the game ({left} pauses left)" with a Resume button when the local player
## may resume (`pause_changed(true, by_pid)`); in a LOCAL match "PAUSED - press {key} to resume". Hidden while the game runs.

signal resume_requested()

## `--no-banner` (screenshots of a paused match: the banner would cover the scene). Never set by the game itself.
static var suppressed: bool = false

var _title: Label = null
var _sub: Label = null
var _resume: Button = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiMetrics.SP_2)
	add_child(col)
	_title = UiScreenKit.wordmark("PAUSED", 34, 800, 8, UiPalette.WARN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_sub = UiScreenKit.label("", &"SubLabel", false, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_sub)
	_resume = UiScreenKit.button("Resume", &"PrimaryButton", Vector2(160.0, 38.0))
	_resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	col.add_child(_resume)


## `by_name` "" = unknown; `left` < 0 hides the counter; `key` is the label of the pause binding; `can_resume` shows the button.
func show_paused(by_name: String, left: int, key: String, can_resume: bool, local: bool) -> void:
	if local or by_name == "":
		_sub.text = "Press %s to resume" % key if key != "" else "The game is paused"
	else:
		_sub.text = "%s paused the game%s" % [by_name, " (%d pauses left)" % left if left >= 0 else ""]
	_resume.visible = can_resume
	visible = not suppressed
	reset_size()


func hide_banner() -> void:
	visible = false


## The line under the title (tests, screenshots).
func sub_text() -> String:
	return _sub.text
