class_name UiNetPortNull
extends UiNetPort
## Refusing adapter: observers, replays and the main-menu showcase. `can_submit()` is false.


func submit(_cmd: PackedInt32Array) -> bool:
	return false


func can_submit() -> bool:
	return false


func is_observer() -> bool:
	return true
