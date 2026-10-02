class_name UiAudioPortSnd
extends UiAudioPort
## Forwards to the `Snd` autoload (audio.md 3.1). The autoload is looked up by name at call time and every call
## degrades to a no-op while it is absent (the audio module lands later).

var _snd: Object = null


func _init(snd: Object = null) -> void:
	_snd = snd


## The bound facade: the explicit object, else /root/Snd, else null.
func facade() -> Object:
	if _snd != null and is_instance_valid(_snd):
		return _snd
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("Snd")


func ui(id: StringName, gain_db: float = 0.0) -> void:
	var s: Object = facade()
	if s != null:
		s.call("ui", id, gain_db)


func announce(line: StringName) -> bool:
	var s: Object = facade()
	return s != null and bool(s.call("announce", line))


func music_state(state: StringName) -> void:
	var s: Object = facade()
	if s == null or not s.has_method("music"):
		return
	var director: Object = s.call("music") as Object
	if director == null:
		return
	match state:
		&"calm":
			director.call("request_state", SndMusicDirector.State.CALM, true)
		&"combat", &"tense":
			director.call("request_state", SndMusicDirector.State.COMBAT, true)


func unit_selected(def_idx: int, is_structure: bool, count: int) -> void:
	var s: Object = facade()
	if s != null:
		s.call("unit_selected", def_idx, is_structure, count)


func unit_ordered(order: int, def_idx: int) -> void:
	var s: Object = facade()
	if s != null:
		s.call("unit_ordered", order, def_idx)


func order_denied(def_idx: int, is_structure: bool = false) -> void:
	var s: Object = facade()
	if s != null:
		s.call("order_denied", def_idx, is_structure)


func set_time_scale(x: float) -> void:
	var s: Object = facade()
	if s != null:
		s.call("set_time_scale", x)


func captions_enabled() -> bool:
	var s: Object = facade()
	return s != null and bool(s.call("captions_enabled"))
