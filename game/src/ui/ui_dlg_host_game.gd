class_name UiDlgHostGame
extends UiDialog
## "Host a LAN game" (ui.md 5.15): lobby name (at most 24 characters, sanitised like every name on the wire), an optional password,
## the game port (default `net/port`, 27615) and the two switches "Advertise on the LAN" (`net/discovery`) and "Allow spectators".
## `closed(1)` = Host (read `values()`), `closed(0)` = Cancel / Esc. The HOST button stays disabled while `validate` reports a problem.

const RESULT_HOST: int = 1
const NAME_MAX: int = 24
const PASSWORD_MAX: int = 32

var _name: LineEdit = null
var _password: LineEdit = null
var _port: SpinBox = null
var _advertise: CheckBox = null
var _spectators: CheckBox = null
var _problem: Label = null
var _host_button: Button = null


## `defaults`: lobby_name, password, port, advertise, spectators.
func _init(defaults: Dictionary = {}) -> void:
	super._init("Host a LAN game", 520)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	set_content(grid)
	grid.add_child(UiScreenKit.label("GAME NAME", &"CaptionLabel"))
	_name = LineEdit.new()
	_name.max_length = NAME_MAX
	_name.text = str(defaults.get("lobby_name", ""))
	_name.placeholder_text = "Name shown in the LAN browser"
	_name.custom_minimum_size = Vector2(300.0, 36.0)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_name)
	grid.add_child(UiScreenKit.label("PASSWORD", &"CaptionLabel"))
	_password = LineEdit.new()
	_password.max_length = PASSWORD_MAX
	_password.secret = true
	_password.text = str(defaults.get("password", ""))
	_password.placeholder_text = "Optional"
	_password.custom_minimum_size = Vector2(0.0, 36.0)
	grid.add_child(_password)
	grid.add_child(UiScreenKit.label("PORT", &"CaptionLabel"))
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.step = 1
	_port.value = int(defaults.get("port", NetProtocol.DEFAULT_PORT))
	_port.custom_minimum_size = Vector2(0.0, 36.0)
	grid.add_child(_port)
	grid.add_child(UiScreenKit.label("", &"CaptionLabel"))
	_advertise = CheckBox.new()
	_advertise.text = "Advertise on the LAN"
	_advertise.button_pressed = bool(defaults.get("advertise", true))
	grid.add_child(_advertise)
	grid.add_child(UiScreenKit.label("", &"CaptionLabel"))
	_spectators = CheckBox.new()
	_spectators.text = "Allow spectators in the lobby"
	_spectators.button_pressed = bool(defaults.get("spectators", true))
	grid.add_child(_spectators)
	_problem = add_text("", &"DangerLabel")
	add_text("Other computers find the game in the LAN browser, or join directly with your address and this port.", &"DimLabel")
	add_button("Cancel", 0)
	_host_button = add_button("Host game", RESULT_HOST, &"primary")
	_name.text_changed.connect(func(_t: String) -> void: _revalidate())
	_port.value_changed.connect(func(_v: float) -> void: _revalidate())
	_revalidate()


func default_focus() -> Control:
	return _name


## The chosen settings: lobby_name (trimmed; the session sanitises it), password, port, advertise, spectators.
func values() -> Dictionary:
	return {"lobby_name": _name.text.strip_edges(), "password": _password.text, "port": int(_port.value),
		"advertise": _advertise.button_pressed, "spectators": _spectators.button_pressed}


## "" when `v` (as `values()`) can be hosted, else the reason. Pure and tested.
static func validate(v: Dictionary) -> String:
	if str(v.get("lobby_name", "")).strip_edges().is_empty():
		return "Give the game a name."
	var port: int = int(v.get("port", 0))
	if port < 1024 or port > 65535:
		return "The port must be between 1024 and 65535."
	if str(v.get("password", "")).length() > PASSWORD_MAX:
		return "The password is too long."
	return ""


func _revalidate() -> void:
	var msg: String = validate(values())
	_problem.text = msg
	_problem.visible = not msg.is_empty()
	if _host_button != null:
		_host_button.disabled = not msg.is_empty()
