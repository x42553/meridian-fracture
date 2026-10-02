class_name UiOptionsPageNetwork
extends UiOptionsPage
## Network page (ui.md 5.18.1): commander name, port, discovery and match networking rows, plus "Show the network help again".

var _help_button: Button = null


func special_row(id: String) -> Control:
	if id != "@net_help":
		return null
	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", UiMetrics.SP_3)
	var l: Label = UiScreenKit.label("Network help")
	l.custom_minimum_size = Vector2(UiOptRow.LABEL_W, 0.0)
	box.add_child(l)
	_help_button = UiScreenKit.button("Show the network help again", &"", Vector2(UiOptRow.CONTROL_W, 34.0))
	_help_button.tooltip_text = "The first-time hosting and joining hints appear again."
	_help_button.pressed.connect(func() -> void:
		settings.call("set_value", &"net/help_shown", false))
	box.add_child(_help_button)
	return box


func apply(id: String, value: Variant) -> void:
	if id == "net/player_name":
		var clean: String = AppProfile.sanitize_name(str(value))
		value = clean if not clean.is_empty() else AppProfile.default_name()
	super.apply(id, value)
