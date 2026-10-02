class_name MissionKit
extends RefCounted
## Test harness of the mission system (MIS1): GameData with extra in-memory mission files (never touches the shared data files),
## and a REAL world built exactly like the game does (SimMissionSetup config -> MapGenerator -> SimMatchSetup.create_world).
##   var d: GameData = MissionKit.data({"t_a": {...mission dict...}, ...})
##   var w: SimWorld = MissionKit.world(d, "t_a")
##   MissionKit.run(w, 200)

static var _data_cache: Dictionary = {}  ## key -> GameData
static var _maps: Dictionary = {}  ## json key -> template MapData


## Drops the static caches (scenario scripts call it before quit so the engine reports no resources still in use at exit).
static func release() -> void:
	_data_cache.clear()
	_maps.clear()


## The real data (balance + bible + shipped missions) plus `extra` missions: id -> parsed Dictionary (file "<id>.json").
## Cached per distinct content.
static func data(extra: Dictionary = {}) -> GameData:
	var key: String = JSON.stringify(extra, "", true)
	if _data_cache.has(key):
		return _data_cache[key]
	var src: DefSources = DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR)
	for id: Variant in extra.keys():
		var f: String = "%s.json" % str(id)
		src.missions[f] = (extra[id] as Dictionary).duplicate(true)
		if not src.mission_files.has(f):
			src.mission_files.append(f)
	var sorted: Array = Array(src.mission_files)
	sorted.sort()
	src.mission_files = PackedStringArray(sorted)
	var d: GameData = GameData.load_from_sources(src)
	if d == null:
		Log.error("mission_kit", GameData.last_report.text(30))
	_data_cache[key] = d
	return d


## Like data() but returns the load report text on failure ("" on success) for negative tests.
static func load_error(extra: Dictionary) -> String:
	var src: DefSources = DefSources.from_disk(GameData.BIBLE_PATH, GameData.BALANCE_DIR)
	for id: Variant in extra.keys():
		var f: String = "%s.json" % str(id)
		src.missions[f] = (extra[id] as Dictionary).duplicate(true)
		if not src.mission_files.has(f):
			src.mission_files.append(f)
	var sorted: Array = Array(src.mission_files)
	sorted.sort()
	src.mission_files = PackedStringArray(sorted)
	var d: GameData = GameData.load_from_sources(src)
	return "" if d != null else GameData.last_report.text(60)


static func map_for(cfg: Dictionary, d: GameData) -> MapData:
	var mcfg: Dictionary = cfg["map"]
	var key: String = JSON.stringify(mcfg, "", true)
	if not _maps.has(key):
		var m: MapData = MapGenerator.generate(mcfg)
		SimMatchSetup.register_map_defs(m, d)
		_maps[key] = m
	return _maps[key]


## World of mission `id`; `opts` = SimWorld options (events etc.). null (+ Log.error) when invalid.
static func world(d: GameData, id: String, opts: Dictionary = {}) -> SimWorld:
	var cfg: Dictionary = SimMissionSetup.build_config(d, id)
	if cfg.is_empty():
		return null
	var map: MapData = map_for(cfg, d)
	return SimMatchSetup.create_world(d, SimMatchConfig.from_dict(cfg), map, opts)


## A valid two-player mission skeleton (NAPC human on slot 0, NEC AI on slot 1 with nothing and its AI off, open 96 map seed 3, fog
## off, 5000 credits) with the top-level keys of `patch` replacing the defaults. Four areas: a_base (circle at player 0's start,
## r 10), a_far (circle at player 1's start, r 8), a_mid (circle at the map centre, r 6), a_rect (rect at the centre, 6 x 4).
static func base(id: String, patch: Dictionary = {}) -> Dictionary:
	var m: Dictionary = {
		"schema": "meridian.mission/1", "id": id, "title": "Test " + id, "map": {"family": "open", "size": 96, "seed": 3},
		"rules": {"fog": false, "start_credits": 5000},
		"players": [
			{"slot": 0, "kind": "human", "roster": "roster.napc.vanilla", "team": 1, "start": {"mode": "hq"}},
			{"slot": 1, "kind": "ai", "roster": "roster.nec.vanilla", "team": 2, "ai": {"active": false}, "start": {"mode": "none"}},
		],
		"areas": [
			{"id": "a_base", "shape": "circle", "anchor": "start:0", "x": 0, "y": 0, "r": 10},
			{"id": "a_far", "shape": "circle", "anchor": "start:1", "x": 0, "y": 0, "r": 8},
			{"id": "a_mid", "shape": "circle", "anchor": "map", "x": 500, "y": 500, "r": 6},
			{"id": "a_rect", "shape": "rect", "anchor": "map", "x": 500, "y": 500, "w": 6, "h": 4},
		],
	}
	for k: Variant in patch.keys():
		m[k] = patch[k]
	return m


## Index of trigger `trigger_id` in the sorted trigger list of the world's mission.
static func trig(w: SimWorld, trigger_id: String) -> int:
	for i: int in w.mission.def.triggers.size():
		if w.mission.def.triggers[i].id == trigger_id:
			return i
	return -1


## Enables trigger `trigger_id` and steps until the next evaluation pass has run (at most 5 ticks).
static func fire(w: SimWorld, trigger_id: String) -> void:
	w.mission.trig_enabled[trig(w, trigger_id)] = 1
	var target: int = w.mission.passes + 1
	var guard: int = 0
	while w.mission.passes < target and guard < 10 and w.match_state == SimWorld.MATCH_RUNNING:
		w.step()
		guard += 1


static func run(w: SimWorld, ticks: int) -> void:
	for _i: int in ticks:
		if w.match_state != SimWorld.MATCH_RUNNING:
			break
		w.step()


## Events of type `type` recorded so far (each [tick, x, y, a, b, c, d, e, f]); does not drain the buffer.
static func events_of(w: SimWorld, type: int) -> Array:
	var out: Array = []
	var d: PackedInt32Array = w.events.data
	var i: int = 0
	while i + SimEvent.STRIDE <= d.size():
		if d[i] == type:
			out.append(d.slice(i + 1, i + SimEvent.STRIDE))
		i += SimEvent.STRIDE
	return out
