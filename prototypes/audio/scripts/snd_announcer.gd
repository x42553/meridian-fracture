class_name SndAnnouncer
extends Node
## Announcer queue: one line at a time, priority pre-emption, per-line cooldown (no spam), optional faction voice pack.
## Lines are ordinary events "voice.<line>" (+ "@<faction>" overrides) on the Voice bus; Music ducks via the bus sidechain.

const MAX_QUEUE: int = 4

var faction: StringName = &""
var cooldown_ms: int = 6000
var _map: SndEventMap
var _player: AudioStreamPlayer
var _queue: Array[Dictionary] = []
var _current_priority: int = -1
var _last_said: Dictionary = {}


func setup(map: SndEventMap) -> void:
	_map = map
	_player = AudioStreamPlayer.new()
	_player.bus = &"Voice"
	add_child(_player)


## Returns true if the line was played or queued.
func say(line: StringName, priority: int = 50) -> bool:
	var id: StringName = StringName("voice.%s" % line)
	var def: SndEventDef = _map.get_def(id, faction)
	if def == null:
		return false
	var now: int = Time.get_ticks_msec()
	if priority < 90 and now - int(_last_said.get(id, -1000000)) < cooldown_ms:
		return false
	if _player.playing:
		if priority >= _current_priority + 20:
			_player.stop()  # urgent line pre-empts a routine one
		else:
			_enqueue({"id": id, "priority": priority})
			return true
	_play(id, priority)
	return true


func is_speaking() -> bool:
	return _player.playing


func _enqueue(item: Dictionary) -> void:
	_queue.append(item)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["priority"]) > int(b["priority"]))
	while _queue.size() > MAX_QUEUE:
		_queue.pop_back()


func _play(id: StringName, priority: int) -> void:
	var def: SndEventDef = _map.get_def(id, faction)
	_player.stream = def.streams[def.pick_variant(RandomNumberGenerator.new())]
	_player.volume_db = def.volume_db
	_player.play()
	_current_priority = priority
	_last_said[id] = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _player.playing and not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		_play(next["id"], int(next["priority"]))
