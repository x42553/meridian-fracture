class_name UiDlgKeyConflict
extends UiDialog
## "Key already in use" dialog of the key-binding table (ui.md 5.18.1, QA A-05): names the action(s) that own the chord and
## offers Swap (the other action gets this slot's previous key), Replace (the other action becomes unbound) or Cancel.
## Result codes: 0 cancel, 1 swap, 2 replace.

const CANCEL: int = 0
const SWAP: int = 1
const REPLACE: int = 2


func _init(key_text: String = "", action_name: String = "", others: PackedStringArray = PackedStringArray(), can_swap: bool = true) -> void:
	super._init("Key already in use", 500)
	var who: String = ", ".join(others) if not others.is_empty() else "another action"
	add_text("%s is already assigned to %s." % [key_text, who])
	add_text("Assign it to \"%s\" anyway?" % action_name, &"DimLabel")
	add_button("Cancel", CANCEL)
	var rep: Button = add_button("Unbind the other", REPLACE, &"danger")
	rep.custom_minimum_size = Vector2(150.0, 38.0)
	if can_swap:
		add_button("Swap keys", SWAP, &"primary")
