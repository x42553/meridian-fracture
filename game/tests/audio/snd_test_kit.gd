class_name SndTestKit
extends RefCounted
## Shared helpers of the audio tests: the real data + asset index + event map (cached), a fake clock, event record
## builders, a virtual voice pool and a bridge wired over a real SimWorld.

const FIXTURE_INDEX: String = "res://tests/fixtures/audio/asset_index.json"

static var _store: SndDataStore = null
static var _index: SndAssetIndex = null
static var _map: SndEventMap = null


class FakeClock:
	extends RefCounted
	var ms: int = 100000

	func now() -> int:
		return ms

	func advance(d: int) -> void:
		ms += d


## Real data (game/data/audio) with the real asset index; built once per process.
static func real() -> Dictionary:
	if _map == null:
		_store = SndDataStore.new()
		_store.load_all(SndConfig.DATA_DIR)
		_index = SndAssetIndex.new()
		_index.setup(SndConfig.INDEX_PATH)
		_map = SndEventMap.new()
		_map.build(_store, _index)
	return {"store": _store, "index": _index, "map": _map}


static func fresh_map(dir: String = SndConfig.DATA_DIR) -> Dictionary:
	var st: SndDataStore = SndDataStore.new()
	st.load_all(dir)
	var ix: SndAssetIndex = SndAssetIndex.new()
	ix.setup(SndConfig.INDEX_PATH)
	var mp: SndEventMap = SndEventMap.new()
	mp.build(st, ix)
	return {"store": st, "index": ix, "map": mp}


## A pool over the real map in virtual mode (no players) with a fake clock; 3D region attached.
static func virtual_pool(clock: FakeClock, voices_3d: int = 48, seed_value: int = 99) -> SndVoicePool:
	var r: Dictionary = real()
	reset_defs(r["map"])
	var pool: SndVoicePool = SndVoicePool.new()
	pool.virtual_mode = true
	pool.setup(r["map"], (r["store"] as SndDataStore).mix, seed_value, Callable(clock, "now"))
	pool.attach_3d(Node3D.new(), voices_3d)
	return pool


## The cached map is shared by every test: clear the per-event bookkeeping the pool keeps on the defs.
static func reset_defs(map: SndEventMap) -> void:
	for id: StringName in map.event_ids():
		var d: SndEventDef = map.get_def(id)
		d.active_count = 0
		d.last_play_ms = -1000000
		d._last_variant.clear()


static func rec(type: int, tick: int, x: int, y: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> PackedInt32Array:
	return PackedInt32Array([type, tick, x, y, a, b, c, d, e, f])


static func batch(records: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: Variant in records:
		out.append_array(r as PackedInt32Array)
	return out


static func sub_cell(cells: float) -> int:
	return int(cells * 1024.0)


## A reader over hand-made entities: fog, relations, positions are all settable. No SimWorld involved.
class StubReader:
	extends SndWorldReader
	var entities: Dictionary = {}
	var visible_cells: Dictionary = {}  ## "cx,cy" -> true
	var everything_visible: bool = false
	var rel: Dictionary = {}  ## owner pid -> relation
	var team_cells: Array[Vector3i] = []  ## x, y, r of places where the viewer's team has units
	var stub_tick: int = 100
	var stub_viewer: int = 0
	var dtypes: Dictionary = {}
	var terrain: int = 4
	var low_power: Dictionary = {}

	func is_bound() -> bool:
		return true

	func tick() -> int:
		return stub_tick

	func viewer_pid() -> int:
		return stub_viewer

	func viewer_team() -> int:
		return 1

	func entity(id: int) -> SimEntity:
		return entities.get(id)

	func add_entity(id: int, kind: int, def_idx: int, owner: int, x: int, y: int, layer: int = 0, flags: int = 0) -> SimEntity:
		var e: SimEntity = SimEntity.new()
		e.id = id
		e.kind = kind
		e.def_idx = def_idx
		e.owner = owner
		e.x = x
		e.y = y
		e.layer = layer
		e.flags = flags
		entities[id] = e
		return e

	func cell_visible(cx: int, cy: int) -> bool:
		return omniscient or everything_visible or visible_cells.has("%d,%d" % [cx, cy])

	func show_cell(cx: int, cy: int) -> void:
		visible_cells["%d,%d" % [cx, cy]] = true

	func relation_of(owner: int) -> int:
		if owner < 0:
			return SndWorldReader.REL_NEUTRAL
		return int(rel.get(owner, SndWorldReader.REL_ENEMY))

	func entity_visible(e: SimEntity) -> bool:
		return omniscient or everything_visible or relation_of(e.owner) <= SndWorldReader.REL_ALLY or cell_visible(e.x >> 10, e.y >> 10)

	func team_within(x: int, y: int, r: int) -> bool:
		for c: Vector3i in team_cells:
			var dx: int = c.x - x
			var dy: int = c.y - y
			if dx * dx + dy * dy <= r * r:
				return true
		return false

	func query_radius(x: int, y: int, r: int, out: PackedInt32Array) -> int:
		out.clear()
		var ids: Array = entities.keys()
		ids.sort()
		for id: Variant in ids:
			var e: SimEntity = entities[id]
			if (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y) <= r * r:
				out.append(int(id))
		return out.size()

	func structure_armor(_def_idx: int) -> int:
		return 9

	func terrain_id(_cx: int, _cy: int) -> int:
		return terrain

	func warhead_dtype(_pid: int, idx: int) -> int:
		return int(dtypes.get(idx, -1))

	func faction_code_of_owner(pid: int) -> String:
		return ["napc", "han", "nec"][pid % 3] if pid >= 0 else ""

	func power_low(pid: int) -> bool:
		return bool(low_power.get(pid, false))

	func player(_pid: int) -> SimPlayer:
		return null


static var _data: GameData = null


static func game_data() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


class Rig:
	extends RefCounted
	var reader: StubReader = StubReader.new()
	var clock: FakeClock = FakeClock.new()
	var pool: SndVoicePool = null
	var bank: SndSoundBank = null
	var bridge: SndSimBridge = null
	var meter: SndCombatMeter = SndCombatMeter.new()
	var scheduler: SndScheduler = SndScheduler.new()
	var countdown: SndCountdown = null
	var map: SndEventMap = null
	var mix: SndMixConfig = null

	func _init() -> void:
		var r: Dictionary = SndTestKit.real()
		map = r["map"]
		mix = (r["store"] as SndDataStore).mix
		meter.configure((r["store"] as SndDataStore).music.get("meter", {}))
		pool = SndTestKit.virtual_pool(clock)
		pool.set_listener(Vector3.ZERO, 1.0)
		bank = SndSoundBank.new()
		bank.bake(SndTestKit.game_data(), map, mix)
		countdown = SndCountdown.new()
		countdown.setup(reader, pool, map)
		bridge = SndSimBridge.new()
		bridge.setup(reader, bank, pool, null, meter, null, countdown, scheduler, mix, map)
		bridge.record_lines = true
		bridge.log_decisions = true

	var loops: SndLoopManager = null

	func enable_loops() -> SndLoopManager:
		loops = SndLoopManager.new()
		loops.setup(reader, bank, pool, mix, map)
		loops.set_view(Vector3.ZERO, 1.0)
		bridge.loops = loops
		return loops

	## Processes one batch; delayed (propagation) sounds are released right away so tests count them.
	func run(records: Array, alpha: float = 0.0) -> void:
		bridge.process(SndTestKit.batch(records), alpha, clock.ms)
		bridge.run_scheduler(clock.ms + 1000)

	func started() -> int:
		return pool.stats.starts

	func events_played() -> PackedStringArray:
		var out: PackedStringArray = PackedStringArray()
		for line: String in bridge.decision_log:
			if line.ends_with(" 1"):
				out.append(line.get_slice("@", 0))
		return out
