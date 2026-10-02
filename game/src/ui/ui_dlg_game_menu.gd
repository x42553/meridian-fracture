class_name UiDlgGameMenu
extends UiDialog
## The Esc game menu (ui.md 5.16.1): Resume, Options, Field Manual, Surrender, Leave match. Surrender and Leave ask for confirmation
## inside the dialog (the same dialog swaps to a two-button page, so the pause the menu holds in a LOCAL match lasts until the
## answer). `closed(result)`: 0 = Esc (resume), `RESULT_RESUME`, `RESULT_OPTIONS`, `RESULT_MANUAL`, `RESULT_SURRENDER`, `RESULT_LEAVE`.
## The footer says whether the game keeps running behind the menu (LAN) or is paused (LOCAL).

const RESULT_RESUME: int = 1
const RESULT_SURRENDER: int = 2
const RESULT_LEAVE: int = 3
const RESULT_OPTIONS: int = 4
const RESULT_MANUAL: int = 5

var _page: VBoxContainer = null
var _main: VBoxContainer = null
var _confirm: VBoxContainer = null
var _confirm_text: Label = null
var _confirm_yes: Button = null
var _footer_text: String = ""


## `paused_while_open`: LOCAL (the menu holds a pause). `can_surrender`: false for observers and defeated players.
func _init(paused_while_open: bool = true, can_surrender: bool = true, replay: bool = false) -> void:
	super._init("Replay menu" if replay else "Game menu", 400)
	_footer_text = "The game is paused while this menu is open." if paused_while_open else "The game continues while this menu is open."
	if replay:
		_footer_text = "The replay is paused while this menu is open." if paused_while_open else "The replay keeps playing while this menu is open."
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", UiMetrics.SP_2)
	set_content(_page)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", UiMetrics.SP_2)
	_page.add_child(_main)
	var resume: Button = _item("Resume", &"PrimaryButton", RESULT_RESUME)
	if UiDraw.optional_script(&"UiScreenOptions") != null:
		_item("Options", &"", RESULT_OPTIONS)
	if UiDraw.optional_script(&"UiScreenFieldManual") != null:
		_item("Field Manual", &"", RESULT_MANUAL)
	if not replay:
		var sur: Button = _item("Surrender", &"", -1)
		sur.disabled = not can_surrender
		sur.pressed.connect(_ask.bind("Surrender the match? You become an observer of your own match.", "Surrender", RESULT_SURRENDER))
		var leave: Button = _item("Leave match", &"DangerButton", -1)
		leave.pressed.connect(_ask.bind("Leave the match and return to the main menu? The match is abandoned.", "Leave match", RESULT_LEAVE))
	else:
		_item("Leave replay", &"DangerButton", RESULT_LEAVE)
	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", UiMetrics.SP_3)
	_confirm.visible = false
	_page.add_child(_confirm)
	_confirm_text = _add_confirm_text()
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", UiMetrics.SP_2)
	_confirm.add_child(row)
	var back: Button = UiScreenKit.button("Back", &"", Vector2(120.0, 38.0))
	back.pressed.connect(_show_main)
	row.add_child(back)
	_confirm_yes = UiScreenKit.button("Yes", &"DangerButton", Vector2(140.0, 38.0))
	row.add_child(_confirm_yes)
	_page.add_child(UiScreenKit.label(_footer_text, &"DimLabel", true))
	_default_button = resume


func _add_confirm_text() -> Label:
	var l: Label = UiScreenKit.label("", &"", true)
	l.custom_minimum_size = Vector2(340.0, 0.0)
	_confirm.add_child(l)
	return l


func _item(text: String, kind: StringName, result_code: int) -> Button:
	var b: Button = UiScreenKit.button(text, kind, Vector2(0.0, 44.0))
	b.focus_mode = Control.FOCUS_ALL
	b.accessibility_name = text
	if result_code >= 0:
		b.pressed.connect(close.bind(result_code))
	_main.add_child(b)
	return b


func _ask(text: String, yes_text: String, result_code: int) -> void:
	_main.visible = false
	_confirm.visible = true
	_confirm_text.text = text
	_confirm_yes.text = yes_text
	for c: Dictionary in _confirm_yes.pressed.get_connections():
		_confirm_yes.pressed.disconnect(c["callable"] as Callable)
	_confirm_yes.pressed.connect(close.bind(result_code))
	_confirm_yes.grab_focus.call_deferred()


func _show_main() -> void:
	_confirm.visible = false
	_main.visible = true
	if _default_button != null:
		_default_button.grab_focus.call_deferred()


## true while the confirmation page is showing.
func is_confirming() -> bool:
	return _confirm.visible


func footer() -> String:
	return _footer_text
