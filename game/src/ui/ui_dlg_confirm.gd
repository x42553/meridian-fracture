class_name UiDlgConfirm
extends UiDialog
## Yes / No confirmation (ui.md 2.7): `closed(1)` on yes, `closed(0)` on no or Escape. `danger` styles the confirming button as
## destructive (leave match, delete preset). The focus starts on the safe answer.


func _init(title_text: String = "", body: String = "", yes_text: String = "Yes", no_text: String = "No", danger: bool = false, width: int = 460) -> void:
	super._init(title_text, width)
	add_text(body)
	add_button(no_text, 0)
	add_button(yes_text, 1, &"danger" if danger else &"primary")


## Builds the dialog, shows it on the modal stack and calls `on_result(confirmed: bool)` when it closes.
static func ask(title_text: String, body: String, on_result: Callable, yes_text: String = "Yes", no_text: String = "No", danger: bool = false) -> UiDlgConfirm:
	var d: UiDlgConfirm = UiDlgConfirm.new(title_text, body, yes_text, no_text, danger)
	d.closed.connect(func(result_code: int) -> void: on_result.call(result_code == 1))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scenes: Node = tree.root.get_node_or_null("AppScenes") if tree != null else null
	if scenes != null:
		scenes.call("modal", d)
	return d
