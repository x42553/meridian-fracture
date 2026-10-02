class_name SndAssetIndex
extends RefCounted
## `res://assets/audio` path resolution from `asset_index.json`, mono/stereo choice, bank loading and the stream cache
## (audio spec 3.3). A file that cannot be loaded yields a short silent placeholder (and one warning) so a partial
## asset set never breaks a match; `missing_files` counts them.

const PLACEHOLDER_MS: int = 60

var assets: Dictionary = {}  ## id -> {f, b, c, l, n}
var groups: Dictionary = {}  ## group -> variant count
var base_dir: String = SndConfig.ASSET_DIR
var allow_placeholders: bool = true
var missing_files: int = 0
var loaded_files: int = 0
var errors: PackedStringArray = PackedStringArray()

var _cache: Dictionary = {}  ## "path|loop" -> AudioStream
var _pending: PackedStringArray = PackedStringArray()
var _requested: int = 0
var _warned: Dictionary = {}
var _placeholder: Dictionary = {}


func setup(index_path: String = SndConfig.INDEX_PATH) -> bool:
	assets.clear()
	groups.clear()
	errors = PackedStringArray()
	if not FileAccess.file_exists(index_path):
		errors.append("asset index not found: %s" % index_path)
		return false
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(index_path)) != OK or not (json.data is Dictionary):
		errors.append("asset index unreadable: %s" % index_path)
		return false
	var d: Dictionary = json.data
	assets = d.get("assets", {})
	groups = d.get("groups", {})
	base_dir = index_path.get_base_dir()
	return true


func has_asset(id: String) -> bool:
	return assets.has(id)


func group_size(group: String) -> int:
	return int(groups.get(group, 0))


func group_members(group: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var n: int = group_size(group)
	for i: int in range(1, n + 1):
		out.append("%s_%d" % [group, i])
	return out


func bank_of(id: String) -> StringName:
	var a: Variant = assets.get(id)
	return StringName(str((a as Dictionary).get("b", ""))) if a is Dictionary else &""


func is_loop(id: String) -> bool:
	var a: Variant = assets.get(id)
	return a is Dictionary and int((a as Dictionary).get("l", 0)) == 1


func channels_of(id: String) -> int:
	var a: Variant = assets.get(id)
	return int((a as Dictionary).get("c", 1)) if a is Dictionary else 0


## "<base>/<file>" for the asset; with want_mono the `.mono.ogg` twin when the index flags one (`m` = 1 on a stereo file).
func resolve_path(id: String, want_mono: bool) -> String:
	var a: Variant = assets.get(id)
	if not (a is Dictionary):
		return ""
	var ad: Dictionary = a
	var f: String = str(ad.get("f", ""))
	if want_mono and int(ad.get("m", 0)) == 1 and f.ends_with(".ogg") and not f.ends_with(".mono.ogg"):
		return base_dir.path_join(f.trim_suffix(".ogg") + ".mono.ogg")
	return base_dir.path_join(f)


## Asks the resource loader to start reading every file of the banks (threaded).
func request_banks(banks: PackedStringArray) -> void:
	var want: Dictionary = {}
	for b: String in banks:
		want[b] = true
	for id: Variant in assets.keys():
		var a: Dictionary = assets[id]
		if not want.has(str(a.get("b", ""))):
			continue
		for mono: bool in [true, false]:
			var p: String = resolve_path(str(id), mono)
			if p == "" or _cache.has(p + "|0") or _cache.has(p + "|1") or _pending.has(p):
				continue
			if ResourceLoader.exists(p) and ResourceLoader.load_threaded_request(p) == OK:
				_pending.append(p)
				_requested += 1


func load_progress() -> float:
	if _requested == 0:
		return 1.0
	var left: int = 0
	for p: String in _pending:
		var st: int = ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			left += 1
	return 1.0 - float(left) / float(_requested)


func banks_ready() -> bool:
	return load_progress() >= 1.0


## Cached stream of an asset; a loop asset comes back as a looping duplicate. Null only when the id is unknown.
func get_stream(id: String, want_mono: bool) -> AudioStream:
	var a: Variant = assets.get(id)
	if not (a is Dictionary):
		_warn_once("unknown:" + id, "unknown audio asset '%s'" % id)
		return null
	var loop: bool = int((a as Dictionary).get("l", 0)) == 1
	var path: String = resolve_path(id, want_mono)
	var key: String = path + ("|1" if loop else "|0")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		var res: Resource = null
		if _pending.has(path):
			res = ResourceLoader.load_threaded_get(path)
			_pending.erase(path)
		else:
			res = ResourceLoader.load(path)
		s = res as AudioStream
	if s == null:
		missing_files += 1
		_warn_once("file:" + path, "audio file missing or unreadable: %s" % path)
		s = _make_placeholder(loop) if allow_placeholders else null
	else:
		loaded_files += 1
		if loop:
			s = apply_loop(s, true)
	if s != null:
		_cache[key] = s
	return s


## Loop metadata goes on a duplicate, never on the cached resource (audio spec 3.10).
static func apply_loop(s: AudioStream, loop: bool) -> AudioStream:
	if s is AudioStreamOggVorbis:
		var d: AudioStreamOggVorbis = (s as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
		d.loop = loop
		return d
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			w.loop_begin = 0
			w.loop_end = w.data.size() / (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1)
		return w
	return s


func release_banks(_banks: PackedStringArray) -> void:
	# a threaded load keeps its result in the resource loader until it is fetched: hand every unfetched one back (it is dropped right here), otherwise
	# the streams of a bank nobody asked for stay alive until the engine exits (`ObjectDB instances were leaked at exit`)
	for p: String in _pending:
		ResourceLoader.load_threaded_get(p)
	_cache.clear()
	_pending.clear()
	_requested = 0


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key) or _warned.size() > 40:
		return
	_warned[key] = true
	Log.warn("snd", msg)


func _make_placeholder(loop: bool) -> AudioStream:
	if _placeholder.has(loop):
		return _placeholder[loop]
	var rate: int = 22050
	var n: int = rate * PLACEHOLDER_MS / 1000
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * 2)  # 16-bit mono silence
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	_placeholder[loop] = w
	return w
