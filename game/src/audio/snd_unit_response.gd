class_name SndUnitResponse
extends RefCounted
## Selection and order acknowledgements: radio bleeps (optionally TTS barks) per faction x voice class x response type
## (audio spec 5.10). Two dedicated players on the Voice bus, outside the pool, so responses are never stolen and never
## duck the music.

enum Order { MOVE = 0, ATTACK = 1, GUARD = 2, DEPLOY = 3, CAPTURE = 4, REPAIR = 5, LOAD = 6, UNLOAD = 7, HARVEST = 8, STOP = 9, SCATTER = 10, SELL = 11 }
enum RType { SELECT = 0, MOVE = 1, ATTACK = 2, DENY = 3, SPECIAL = 4 }

const TYPE_NAMES: PackedStringArray = ["select", "move", "attack", "deny", "special"]
## Order -> response type; -1 = silent (STOP).
const ORDER_TYPE: PackedInt32Array = [1, 2, 2, 4, 4, 4, 4, 4, 4, -1, 4, 4]

var last_played: String = ""  ## asset id of the last response (tests, debug)
var plays: int = 0

var _index: SndAssetIndex = null
var _clock: Callable = Callable()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _faction: String = ""
var _mode: int = SndSettings.UV_SYNTH
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _gaps: Dictionary = {}
var _counts: Dictionary = {}
var _mix_pct: int = 60
var _last_global_ms: int = -100000
var _last_same: Dictionary = {}  ## "class|type" -> ms
var _bag: Dictionary = {}  ## "class|type" -> Array[int] remaining variant order
var _recent: Dictionary = {}  ## "class|type" -> last two picks
var _fatigue: Dictionary = {}  ## type -> Array[int] request times
var _fatigue_skip: Dictionary = {}
var _structure_counts: Dictionary = {}


func setup(store: SndDataStore, index: SndAssetIndex, host: Node, clock: Callable, seed_value: int) -> void:
	_index = index
	_clock = clock
	_rng.seed = seed_value
	var r: Dictionary = store.responses
	_gaps = r.get("gaps", {})
	_counts = r.get("types", {})
	_structure_counts = r.get("structure_types", {})
	_mix_pct = int(r.get("voice_mix_pct", 60))
	if host != null and _players.is_empty():
		for i: int in 2:
			var p: AudioStreamPlayer = AudioStreamPlayer.new()
			p.name = "Response%d" % i
			p.bus = SndBus.VOICE
			host.add_child(p)
			_players.append(p)


func set_faction(faction: String) -> void:
	_faction = faction


func set_mode(mode: int) -> void:
	_mode = mode


func _now() -> int:
	return int(_clock.call()) if _clock.is_valid() else SndConfig.now_ms()


func on_selected(voice_class: int, is_structure: bool, _count: int, now_ms: int = -1) -> bool:
	return _respond(SndUnits.VoiceClass.STRUCTURE if is_structure else voice_class, RType.SELECT, now_ms)


func on_order(order: int, voice_class: int, now_ms: int = -1) -> bool:
	if order < 0 or order >= ORDER_TYPE.size():
		return false
	var t: int = ORDER_TYPE[order]
	if t < 0:
		return false
	return _respond(voice_class, t, now_ms)


func on_denied(voice_class: int, now_ms: int = -1) -> bool:
	return _respond(voice_class, RType.DENY, now_ms)


func _variant_count(cls: int, t: int) -> int:
	var tn: String = TYPE_NAMES[t]
	if cls == SndUnits.VoiceClass.STRUCTURE:
		return int(_structure_counts.get(tn, 3)) if t == RType.SELECT else 0
	return int(_counts.get(tn, 1))


## Applies the gap rules and plays a bleep (or bark). Returns true when a clip was started.
func _respond(cls: int, t: int, now_ms: int) -> bool:
	if _mode == SndSettings.UV_OFF or _faction == "" or cls < 0:
		return false
	var now: int = now_ms if now_ms >= 0 else _now()
	var n: int = _variant_count(cls, t)
	if n <= 0:
		return false
	if now - _last_global_ms < int(_gaps.get("global_ms", 250)):
		return false
	var key: String = "%d|%d" % [cls, t]
	if now - int(_last_same.get(key, -100000)) < int(_gaps.get("same_ms", 700)):
		return false
	# fatigue guard: >= N requests of the same type inside the window -> only every second one plays
	var win: int = int(float(_gaps.get("fatigue_window_s", 3.0)) * 1000.0)
	var hist: Array = _fatigue.get(t, [])
	hist = hist.filter(func(ms: int) -> bool: return now - ms <= win)
	hist.append(now)
	_fatigue[t] = hist
	if hist.size() >= int(_gaps.get("fatigue_count", 4)):
		var skip: bool = bool(_fatigue_skip.get(t, false))
		_fatigue_skip[t] = not skip
		if skip:
			return false
	var use_bark: bool = _mode == SndSettings.UV_VOICE or (_mode == SndSettings.UV_MIXED and (t == RType.SELECT or t == RType.ATTACK) and _rng.randi() % 100 < _mix_pct)
	var pick: int = _pick(key, n)
	var cname: String = SndUnits.VOICE_CLASS_NAMES[cls]
	var base: String = "%s_%s_%d" % [cname, TYPE_NAMES[t], pick + 1]
	var asset: String = ""
	if use_bark:
		var bark: String = "resp/%s/voice/%s" % [_faction, base]
		if _index.has_asset(bark):
			asset = bark
	if asset == "":
		var bleep: String = "resp/%s/%s" % [_faction, base]
		if _index.has_asset(bleep):
			asset = bleep
	if asset == "":
		return false
	_last_global_ms = now
	_last_same[key] = now
	last_played = asset
	plays += 1
	_play(asset)
	return true


## Shuffled bag per (class, type): never the same as the last two picks when the bag allows it.
func _pick(key: String, n: int) -> int:
	if n == 1:
		return 0
	var bag: Array = _bag.get(key, [])
	var recent: Array = _recent.get(key, [])
	if bag.is_empty():
		for i: int in n:
			bag.append(i)
		for i: int in range(bag.size() - 1, 0, -1):
			var j: int = _rng.randi() % (i + 1)
			var tmp: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
	var idx: int = 0
	if n > 2:
		for i: int in bag.size():
			if not recent.has(bag[i]):
				idx = i
				break
	else:
		for i: int in bag.size():
			if not recent.is_empty() and bag[i] != recent[recent.size() - 1]:
				idx = i
				break
	var v: int = bag[idx]
	bag.remove_at(idx)
	_bag[key] = bag
	recent.append(v)
	if recent.size() > 2:
		recent.pop_front()
	_recent[key] = recent
	return v


func _play(asset: String) -> void:
	if _players.is_empty():
		return
	var s: AudioStream = _index.get_stream(asset, false)
	if s == null:
		return
	var p: AudioStreamPlayer = _players[_next_player]
	if not p.is_inside_tree():
		return
	_next_player = (_next_player + 1) % _players.size()
	p.stream = s
	p.play()
