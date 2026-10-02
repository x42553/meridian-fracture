class_name UiBookmarks
extends RefCounted
## Four camera bookmarks (Ctrl+F9..F12 store, F9..F12 recall; ui.md 5.5.5). A slot holds the dictionary of
## `UiViewPort.camera_state()`; the screen restores it with `set_camera_state(state, false)` (smooth).

const SLOTS: int = 4

signal changed(slot: int)

var _slots: Array[Dictionary] = []


func _init() -> void:
	for i: int in SLOTS:
		_slots.append({})


func set_slot(i: int, state: Dictionary) -> void:
	if i < 0 or i >= SLOTS:
		return
	_slots[i] = state.duplicate()
	changed.emit(i)


## The stored state, empty if unset.
func get_slot(i: int) -> Dictionary:
	if i < 0 or i >= SLOTS or _slots[i].is_empty():
		return {}
	return _slots[i].duplicate()


func has_slot(i: int) -> bool:
	return i >= 0 and i < SLOTS and not _slots[i].is_empty()


func clear(i: int) -> void:
	if i >= 0 and i < SLOTS and not _slots[i].is_empty():
		_slots[i] = {}
		changed.emit(i)
