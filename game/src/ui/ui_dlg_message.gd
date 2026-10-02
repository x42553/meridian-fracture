class_name UiDlgMessage
extends UiDialog
## One-button message dialog (ui.md 2.7): title, wrapped body, OK. `closed(1)` on OK, `closed(0)` on Escape.


func _init(title_text: String = "", body: String = "", ok_text: String = "OK", width: int = 460) -> void:
	super._init(title_text, width)
	add_text(body)
	add_button(ok_text, 1, &"primary")


## Builds the dialog and puts it on the modal stack of the `AppScenes` autoload (no-op without it); returns the dialog.
static func open(title_text: String, body: String, ok_text: String = "OK") -> UiDlgMessage:
	var d: UiDlgMessage = UiDlgMessage.new(title_text, body, ok_text)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scenes: Node = tree.root.get_node_or_null("AppScenes") if tree != null else null
	if scenes != null:
		scenes.call("modal", d)
	return d
