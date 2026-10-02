class_name UiDlgReplayName
extends UiDialog
## "Save replay" / "Rename replay" (ui.md 5.16.6): one name field. `closed(1)` = confirmed (read `chosen()`), `closed(0)` = cancel. The
## file name is the net module's `NetReplay.sanitize_name` of the text (the preview line shows the result), so the player sees what
## the file will be called. The confirm button stays disabled while the name is empty.

const RESULT_OK: int = 1

var _edit: LineEdit = null
var _preview: Label = null
var _ok: Button = null


func _init(title_text: String = "Save replay", initial: String = "", confirm_text: String = "Save") -> void:
	super._init(title_text, 520)
	add_text("Name the replay. It is stored in the replay folder and listed under Replays.", &"DimLabel")
	_edit = LineEdit.new()
	_edit.max_length = NetReplay.NAME_MAX
	_edit.text = initial
	_edit.select_all_on_focus = true
	_edit.placeholder_text = "Replay name"
	_edit.custom_minimum_size = Vector2(0.0, 38.0)
	_edit.accessibility_name = "Replay name"
	set_content(_edit)
	_preview = add_text("", &"CaptionLabel")
	add_button("Cancel", 0)
	_ok = add_button(confirm_text, RESULT_OK, &"primary")
	_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	_edit.text_submitted.connect(func(_t: String) -> void:
		if not _ok.disabled:
			close(RESULT_OK))
	_refresh()


func default_focus() -> Control:
	return _edit


## The display name typed (trimmed).
func chosen() -> String:
	return _edit.text.strip_edges()


## The file name the text becomes (without extension).
func file_name() -> String:
	return NetReplay.sanitize_name(chosen())


func _refresh() -> void:
	var empty: bool = chosen() == ""
	_ok.disabled = empty
	_preview.text = "" if empty else "FILE  %s.%s" % [file_name(), NetReplay.EXT]


## Shows the dialog on the modal stack of `AppScenes` and calls `on_done(name: String)` when confirmed.
static func ask(title_text: String, initial: String, confirm_text: String, on_done: Callable) -> UiDlgReplayName:
	var d: UiDlgReplayName = UiDlgReplayName.new(title_text, initial, confirm_text)
	d.closed.connect(func(result_code: int) -> void:
		if result_code == RESULT_OK:
			on_done.call(d.chosen()))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scenes: Node = tree.root.get_node_or_null("AppScenes") if tree != null else null
	if scenes != null:
		scenes.call("modal", d)
	return d
