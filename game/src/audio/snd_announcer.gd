class_name SndAnnouncer
extends Node
## EVA-style single-voice announcer (audio spec 5.9): priority queue of four, pre-emption, per-line cooldowns and per-
## category gaps, expiry, faction / computer packs, captions and an optional OS text-to-speech mode. Time comes from the
## injected clock (tests use a fake one); `update` advances the state machine.

signal started(line_id: StringName, text: String, priority: int)
signal finished(line_id: StringName)

class Item:
	extends RefCounted
	var line: StringName = &""
	var priority: int = 0
	var enq_ms: int = 0
	var expire_ms: int = 0
	var args: Dictionary = {}

var fade_ms: int = 40
## Test seam: line id -> duration in ms (otherwise the stream length).
var duration_override: Dictionary = {}
## TTS seams (default: DisplayServer). `is_speaking` polled on update.
var tts_available_fn: Callable = Callable()
var tts_speak_fn: Callable = Callable()
var tts_stop_fn: Callable = Callable()
var tts_speaking_fn: Callable = Callable()
var warned_lines: Dictionary = {}
var last_error: String = ""

var _store: SndDataStore = null
var _index: SndAssetIndex = null
var _clock: Callable = Callable()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _mode: int = SndSettings.ANN_FACTION
var _pack: StringName = &"computer"
var _tts: bool = false
var _lines: Dictionary = {}
var _cats: Dictionary = {}
var _defaults: Dictionary = {}
var _queue: Array[Item] = []
var _current: Item = null
var _cur_end_ms: int = 0
var _cur_tts: bool = false
var _gap_until_ms: int = 0
var _start_not_before_ms: int = 0
var _last_said: Dictionary = {}
var _cat_last: Dictionary = {}
var _player: AudioStreamPlayer = null
var _stop_at_ms: int = -1
var _duck_music_cb: Callable = Callable()


func setup(store: SndDataStore, index: SndAssetIndex, clock: Callable, seed_value: int) -> void:
	_store = store
	_index = index
	_clock = clock
	_rng.seed = seed_value
	var a: Dictionary = store.announcer
	_lines = a.get("lines", {})
	_cats = a.get("categories", {})
	_defaults = a.get("defaults", {})
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "AnnouncerPlayer"
		_player.bus = SndBus.ANNOUNCER
		add_child(_player)


func release() -> void:
	clear_queue()
	_current = null
	if _player != null:
		_player.stop()
		_player.stream = null


func set_duck_callback(cb: Callable) -> void:
	_duck_music_cb = cb


func _now() -> int:
	return int(_clock.call()) if _clock.is_valid() else SndConfig.now_ms()


func set_pack(p_pack: StringName) -> void:
	_pack = p_pack if p_pack != &"" else &"computer"


func pack() -> StringName:
	return _pack


func set_mode(mode: int) -> void:
	_mode = mode
	if mode == SndSettings.ANN_OFF:
		clear_queue()


func set_tts(enabled: bool) -> bool:
	if enabled and not tts_available():
		_tts = false
		return false
	_tts = enabled
	return _tts


func tts_available() -> bool:
	if tts_available_fn.is_valid():
		return bool(tts_available_fn.call())
	return not DisplayServer.tts_get_voices_for_language("en").is_empty()


func is_speaking() -> bool:
	return _current != null


func queue_size() -> int:
	return _queue.size()


func queued_lines() -> Array[StringName]:
	var out: Array[StringName] = []
	for it: Item in _queue:
		out.append(it.line)
	return out


func current_line() -> StringName:
	return _current.line if _current != null else &""


func clear_queue() -> void:
	_queue.clear()


func has_line(line: StringName) -> bool:
	return _lines.has(String(line))


func _line_num(line: StringName, key: String, dflt: Variant) -> Variant:
	var l: Dictionary = _lines.get(String(line), {})
	return l.get(key, _defaults.get(key, dflt))


## Asset id of a spoken variant, pack first then the computer pack; "" when no file exists anywhere.
func resolve_asset(line: StringName) -> String:
	var packs: Array[String] = []
	if _mode == SndSettings.ANN_FACTION and _pack != &"computer":
		packs.append(String(_pack))
	packs.append("computer")
	for p: String in packs:
		var base: String = "vox/%s/%s" % [p, String(line)]
		var found: PackedStringArray = PackedStringArray()
		for cand: String in [base, base + "_1", base + "_2", base + "_3"]:
			if _index.has_asset(cand):
				found.append(cand)
		if not found.is_empty():
			return found[_rng.randi() % found.size()]
	return ""


## True = played or queued.
func say(line: StringName, priority: int = -1, args: Dictionary = {}) -> bool:
	if _mode == SndSettings.ANN_OFF or _store == null:
		return false
	if not _lines.has(String(line)):
		if not warned_lines.has(line):
			warned_lines[line] = true
			Log.debug("snd", "announcer: unknown line '%s'" % String(line))
		return false
	var now: int = _now()
	var asset: String = resolve_asset(line)
	if asset == "" and not _tts:
		if not warned_lines.has(line):
			warned_lines[line] = true
			Log.debug("snd", "announcer: no voice file for '%s'" % String(line))
		return false
	var prio: int = priority if priority >= 0 else int(_line_num(line, "priority", 50))
	var cooldown: int = int(_line_num(line, "cooldown_ms", 6000))
	if _last_said.has(line) and now - int(_last_said[line]) < cooldown:
		return false
	var expire: int = int(_line_num(line, "expire_ms", 8000))
	var margin: int = int(_defaults.get("preempt_margin", 20))
	if _current != null:
		if prio >= _current.priority + margin:
			_interrupt(now)
			var forced: Item = _make_item(line, prio, now, expire, args)
			_queue.push_front(forced)
			_start_not_before_ms = now + fade_ms
			return true
		return _enqueue(line, prio, now, expire, args)
	var item: Item = _make_item(line, prio, now, expire, args)
	if now < _gap_until_ms or now < _start_not_before_ms or _cat_blocked(item, now):
		return _enqueue(line, prio, now, expire, args)
	_play(item, now)
	return true


## The category gap delays the START of a line of the same category (alerts >= 90 ignore it).
func _cat_blocked(item: Item, now: int) -> bool:
	var cat: String = str(_line_num(item.line, "category", ""))
	if cat == "" or item.priority >= 90 or not _cat_last.has(cat):
		return false
	var gap: int = int((_cats.get(cat, {}) as Dictionary).get("gap_ms", 0))
	return now - int(_cat_last[cat]) < gap


func _make_item(line: StringName, prio: int, now: int, expire: int, args: Dictionary) -> Item:
	var it: Item = Item.new()
	it.line = line
	it.priority = prio
	it.enq_ms = now
	it.expire_ms = now + expire
	it.args = args
	return it


func _enqueue(line: StringName, prio: int, now: int, expire: int, args: Dictionary) -> bool:
	for it: Item in _queue:
		if it.line == line:
			it.priority = maxi(it.priority, prio)
			it.enq_ms = now
			it.expire_ms = now + expire
			_sort_queue()
			return true
	var item: Item = _make_item(line, prio, now, expire, args)
	var max_q: int = int(_defaults.get("max_queue", 4))
	_queue.append(item)
	_sort_queue()
	if _queue.size() > max_q:
		var dropped: Item = _queue.pop_back()
		if dropped == item:
			return false
	return true


func _sort_queue() -> void:
	_queue.sort_custom(func(a: Item, b: Item) -> bool:
		if a.priority != b.priority:
			return a.priority > b.priority
		return a.enq_ms < b.enq_ms)


func _interrupt(now: int) -> void:
	if _current == null:
		return
	var l: StringName = _current.line
	_current = null
	_stop_at_ms = now + fade_ms
	if _cur_tts and tts_stop_fn.is_valid():
		tts_stop_fn.call()
	finished.emit(l)


func _play(item: Item, now: int) -> void:
	_current = item
	_last_said[item.line] = now
	var cat: String = str(_line_num(item.line, "category", ""))
	if cat != "":
		_cat_last[cat] = now
	var text: String = str(_line_num(item.line, "text", ""))
	var dur_ms: int = int(duration_override.get(item.line, 0))
	_cur_tts = _tts
	if _tts:
		if tts_speak_fn.is_valid():
			tts_speak_fn.call(text)
		if dur_ms <= 0:
			dur_ms = maxi(1200, int(75.0 * float(text.length())))
		if _duck_music_cb.is_valid():
			_duck_music_cb.call(true)
	else:
		var asset: String = resolve_asset(item.line)
		var stream: AudioStream = _index.get_stream(asset, false) if asset != "" else null
		if stream != null and _player != null and _player.is_inside_tree():
			_player.stream = stream
			_player.volume_db = 0.0
			_player.play()
			if dur_ms <= 0:
				dur_ms = int(stream.get_length() * 1000.0)
	_cur_end_ms = now + maxi(dur_ms, 50)
	started.emit(item.line, text, item.priority)


## Advances the state machine (ends lines, applies the gap, starts the next queued line).
func update(_dt: float, now_ms: int) -> void:
	if _stop_at_ms >= 0 and now_ms >= _stop_at_ms:
		_stop_at_ms = -1
		if _player != null and _player.is_inside_tree():
			_player.stop()
	if _current != null:
		var over: bool = now_ms >= _cur_end_ms
		if _cur_tts and tts_speaking_fn.is_valid() and now_ms > _current.enq_ms + 200:
			over = over or not bool(tts_speaking_fn.call())
		if over:
			var l: StringName = _current.line
			_current = null
			_gap_until_ms = now_ms + int(_defaults.get("gap_ms", 250))
			if _cur_tts and _duck_music_cb.is_valid():
				_duck_music_cb.call(false)
			finished.emit(l)
	if _current == null and now_ms >= _gap_until_ms and now_ms >= _start_not_before_ms:
		var i: int = 0
		while i < _queue.size():
			var it: Item = _queue[i]
			if now_ms > it.expire_ms:
				_queue.remove_at(i)
				continue
			if _cat_blocked(it, now_ms):
				i += 1
				continue
			_queue.remove_at(i)
			_play(it, now_ms)
			break
