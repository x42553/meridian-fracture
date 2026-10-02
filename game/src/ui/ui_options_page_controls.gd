class_name UiOptionsPageControls
extends UiOptionsPage
## Controls page (ui.md 5.18.1): the key-binding table (`UiOptionsKeybinds`) followed by the pointer, behaviour and order rows.

var keybinds: UiOptionsKeybinds = null


func special_row(id: String) -> Control:
	if id != "@keys":
		return null
	keybinds = UiOptionsKeybinds.new()
	keybinds.setup(UiKeymap.instance(), store(), settings)
	return keybinds


func on_reset_defaults() -> void:
	if keybinds != null:
		keybinds.reset_all()
