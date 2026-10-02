class_name MapGenerator
extends RefCounted
## Map generator entry points (terrain_movement 3.7 / 5.12.6): a PURE function of `config.map` (same dictionary =>
## byte-identical map on every platform). Orchestrates phase A (terrain, expensive, once per attempt), phase B (layout,
## retried at level 0..2), finalize, validation and the safe template, and reports monotonic progress.
##
## `Runner` is the staged form (one atomic stage per `step()`), used by `generate` and by MapGenJob for time slicing.
## No RNG state, no hidden globals, no Time in any decision (telemetry only): reentrant and safe on a worker thread.

const ST_HEIGHT: int = 0
const ST_CLASSIFY: int = 1
const ST_WATER: int = 2
const ST_CLIFFS: int = 3
const ST_LAYOUT: int = MapGenLayout.ST_LAYOUT
const ST_FIELDS: int = MapGenLayout.ST_FIELDS
const ST_NEUTRALS: int = MapGenLayout.ST_NEUTRALS
const ST_FINALIZE: int = MapGenLayout.ST_FINALIZE
const ST_VALIDATE: int = MapGenLayout.ST_VALIDATE
const ST_DONE: int = MapGenLayout.ST_DONE
const SEED_TAG: int = 0x51ED


## net XR-12 / lobby check: "" = ok.
static func validate_params(family: int, size: int, layout_players: int) -> String:
	return MapGenParams.validate_basic(family, size, layout_players)


## Never returns null (worst case the safe template); null only if the terrain tables cannot be loaded.
static func generate(map_cfg: Dictionary, tables: MapGenTables = null, progress: Callable = Callable()) -> MapData:
	var r: Runner = make_runner(map_cfg, tables, progress)
	if r == null:
		return null
	r.run_all()
	return r.map


static func generate_params(tt: MapTerrain, params: MapGenParams, tables: MapGenTables, progress: Callable = Callable()) -> MapData:
	var r: Runner = Runner.new(tt, params, tables, progress)
	r.run_all()
	return r.map


## {"map": MapData, "attempts": int, "layout_level": int, "template": bool, "failures": Array[String], "ms": Dictionary}
static func generate_report(map_cfg: Dictionary, tables: MapGenTables = null) -> Dictionary:
	var r: Runner = make_runner(map_cfg, tables, Callable())
	if r == null:
		return {}
	r.run_all()
	return {"map": r.map, "attempts": r.attempts, "layout_level": r.layout_level, "template": r.template,
		"failures": r.failures, "ms": r.ms}


## Runner for a lobby dictionary; parameters outside the legal ranges are clamped (the lobby validates first).
static func make_runner(map_cfg: Dictionary, tables: MapGenTables = null, progress: Callable = Callable()) -> Runner:
	var tt: MapTerrain = MapTerrain.load_default()
	var tb: MapGenTables = tables if tables != null else MapGenTables.load_default()
	if tt == null or tb == null:
		push_error("MapGenerator: terrain or generator tables unavailable")
		return null
	var p: MapGenParams = MapGenParams.from_config(map_cfg)
	sanitize(p)
	return Runner.new(tt, p, tb, progress)


## Clamps every parameter into its legal range (a lobby-validated config passes unchanged).
static func sanitize(p: MapGenParams) -> void:
	p.family = clampi(p.family, 0, 2)
	p.slots = MapGenParams.slots_for(clampi(p.slots, 1, 8)) if not [2, 3, 4, 6, 8].has(p.slots) else p.slots
	p.size = clampi((p.size + 7) / 8 * 8, maxi(MapGenParams.SIZE_MIN, MapGenParams.min_size(p.slots)), MapGenParams.SIZE_MAX)
	p.seed_value = p.seed_value & MapGenParams.SEED_MAX
	p.water_pct = clampi(p.water_pct, -1, 40)
	p.density = clampi(p.density, -1, 100)
	p.resources = clampi(p.resources, 0, 100)
	p.neutrals = clampi(p.neutrals, 0, 100)
	p.biome = clampi(p.biome, 0, 2)


class Runner extends RefCounted:
	const S_A: int = 0
	const S_B: int = 1
	const S_T: int = 2

	var tt: MapTerrain = null
	var params: MapGenParams = null
	var tables: MapGenTables = null
	var progress: Callable = Callable()
	var done: bool = false
	var map: MapData = null
	var attempts: int = 0
	var layout_level: int = 0
	var template: bool = false
	var failures: Array[String] = []
	var ms: Dictionary = {}  ## telemetry only (microseconds per phase): never read by a decision
	var pct: int = 0  ## monotonic 0..100
	var _stage: int = S_A
	var _attempt: int = 0
	var _level: int = 0
	var _g: MapGenTerrain = null
	var _seed_a: int = 0

	func _init(p_tt: MapTerrain, p_params: MapGenParams, p_tables: MapGenTables, p_progress: Callable = Callable()) -> void:
		tt = p_tt
		params = p_params
		tables = p_tables
		progress = p_progress
		MapGenLayout.neutral_dims()  # load the shared footprint table on the constructing thread

	func _emit(stage: int, p: int) -> void:
		pct = maxi(pct, p)
		if progress.is_valid():
			progress.call(stage, pct)

	func _tick(key: String, t0: int) -> void:
		ms[key] = (ms.get(key, 0) as int) + Time.get_ticks_usec() - t0  # lint-allow: L003 telemetry only, never read by a decision

	func _now() -> int:
		return Time.get_ticks_usec()  # lint-allow: L003 telemetry only, never read by a decision

	func run_all() -> void:
		while not step():
			pass

	## One atomic stage (phase A of an attempt, one phase-B level with finalize + validation, or the template).
	## True when the map is complete (`map` set, finalized, nav prepared).
	func step() -> bool:
		if done:
			return true
		var t0: int = _now()
		match _stage:
			S_A:
				_seed_a = params.seed_value if _attempt == 0 else MapGenNoise.mix32(params.seed_value, _attempt, SEED_TAG)
				_g = MapGenTerrain.generate(tt, params, tables, _seed_a, _emit)
				_stage = S_B
				_level = 0
				_tick("phase_a", t0)
			S_B:
				_phase_b()
			_:
				_emit(ST_LAYOUT, 70)
				map = MapGenTemplate.make(params, tt, tables)
				template = true
				attempts = tables.lay("max_attempts")
				layout_level = 2
				done = true
				_emit(ST_DONE, 100)
				_tick("template", t0)
		if done:
			ms["total"] = 0
			for k: String in ["phase_a", "layout", "finalize", "validate", "view", "template"]:
				ms["total"] = (ms["total"] as int) + (ms.get(k, 0) as int)
		return done

	func _phase_b() -> void:
		var t0: int = _now()
		var m: MapData = _g.make_map()
		var l: MapGenLayout = MapGenLayout.run(m, tt, tables, params, _seed_a, _level, false, _emit)
		_tick("layout", t0)
		var why: String = l.failure
		if l.ok:
			t0 = _now()
			_emit(ST_FINALIZE, 70)
			m.finalize()
			_emit(ST_FINALIZE, 92)
			_tick("finalize", t0)
			t0 = _now()
			var fails: PackedStringArray = MapGenValidate.validate(m, tables)
			_tick("validate", t0)
			if fails.is_empty():
				t0 = _now()
				MapGenView.fill_heights(m, _g.height, _g.plateau, _g.t_water)
				MapGenView.fill_deco(m)
				_tick("view", t0)
				map = m
				attempts = _attempt + 1
				layout_level = _level
				done = true
				_emit(ST_DONE, 100)
				return
			why = ", ".join(fails)
		failures.append("attempt %d level %d: %s" % [_attempt, _level, why])
		_level += 1
		if _level > 2:
			_attempt += 1
			_stage = S_A if _attempt < tables.lay("max_attempts") else S_T
