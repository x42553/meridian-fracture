class_name SndAmbience
extends Node
## Biome beds (audio spec 5.11): six looped stereo beds on the Ambience bus whose levels follow a terrain histogram around
## the camera focus, the map family and biome, and the far-battle heat. Every level is continuous in its inputs; a bed is
## started only when audible and stopped after a quiet period, so muted beds cost no decoding.

const BEDS: PackedStringArray = ["wind_open", "city_hum", "coast_waves", "river_flow", "forest", "battle_far"]

var targets: Dictionary = {}  ## bed name -> target dB (SILENT_DB = off)
var f_water: float = 0.0
var f_forest: float = 0.0

var _map: SndEventMap = null
var _reader: SndWorldReader = null
var _amb: Dictionary = {}
var _family: int = 0
var _biome: int = 0
var _grid_w: int = 0
var _grid_h: int = 0
var _cell: int = 8
var _water_grid: PackedByteArray = PackedByteArray()
var _forest_grid: PackedByteArray = PackedByteArray()
var _beds: Dictionary = {}  ## name -> {player, cur_db, below_s}
var _scan_left: float = 0.0
var _enabled: bool = false
var _master_gain_db: float = 0.0


func setup(store: SndDataStore, map: SndEventMap, reader: SndWorldReader) -> void:
	_amb = store.mix.ambience
	_map = map
	_reader = reader
	_cell = int(_amb.get("grid_cells", 8))


static func amp_db(x: float, x_full: float) -> float:
	var f: float = clampf(x / maxf(x_full, 0.0001), 0.0, 1.0)
	if f <= 0.0:
		return SndConfig.SILENT_DB
	return 20.0 * log(f) / log(10.0)


## Builds the 8x8-cell summary grid of water / forest fractions from the map's terrain bytes.
func set_environment(family: int, biome: int) -> void:
	_family = family
	_biome = biome
	var size: Vector2i = _reader.map_size() if _reader != null else Vector2i.ZERO
	var bytes: PackedByteArray = _reader.terrain_bytes() if _reader != null else PackedByteArray()
	_grid_w = maxi((size.x + _cell - 1) / _cell, 0)
	_grid_h = maxi((size.y + _cell - 1) / _cell, 0)
	_water_grid.resize(_grid_w * _grid_h)
	_forest_grid.resize(_grid_w * _grid_h)
	_water_grid.fill(0)
	_forest_grid.fill(0)
	if bytes.size() != size.x * size.y or size.x == 0:
		return
	var ww: Array = _amb.get("water_weight", [1.0, 1.0, 0.5])
	var forest_id: int = int(_amb.get("forest_id", 8))
	for gy: int in _grid_h:
		for gx: int in _grid_w:
			var wsum: float = 0.0
			var fsum: float = 0.0
			var n: int = 0
			for cy: int in range(gy * _cell, mini((gy + 1) * _cell, size.y)):
				for cx: int in range(gx * _cell, mini((gx + 1) * _cell, size.x)):
					var t: int = bytes[cy * size.x + cx]
					if t < ww.size():
						wsum += float(ww[t])
					if t == forest_id:
						fsum += 1.0
					n += 1
			if n > 0:
				_water_grid[gy * _grid_w + gx] = int(255.0 * wsum / float(n))
				_forest_grid[gy * _grid_w + gx] = int(255.0 * fsum / float(n))


func set_fractions(water: float, forest: float) -> void:
	f_water = water
	f_forest = forest


## Fractions inside `radius_m * zoom` of the focus, from the summary grid (cell centres inside the circle, equally weighted).
func histogram(focus: Vector3, zoom_scale: float) -> void:
	if _grid_w == 0:
		return
	var radius_cells: float = float(_amb.get("radius_m", 24.0)) * zoom_scale / 3.0
	var fx: float = focus.x / 3.0 / float(_cell)
	var fz: float = focus.z / 3.0 / float(_cell)
	var rb: float = radius_cells / float(_cell)
	var w: float = 0.0
	var f: float = 0.0
	var n: int = 0
	for gy: int in range(maxi(int(floor(fz - rb)), 0), mini(int(ceil(fz + rb)) + 1, _grid_h)):
		for gx: int in range(maxi(int(floor(fx - rb)), 0), mini(int(ceil(fx + rb)) + 1, _grid_w)):
			var dx: float = float(gx) + 0.5 - fx
			var dz: float = float(gy) + 0.5 - fz
			if dx * dx + dz * dz > (rb + 0.7) * (rb + 0.7):
				continue
			w += float(_water_grid[gy * _grid_w + gx]) / 255.0
			f += float(_forest_grid[gy * _grid_w + gx]) / 255.0
			n += 1
	if n > 0:
		f_water = w / float(n)
		f_forest = f / float(n)
	else:
		f_water = 0.0
		f_forest = 0.0


## The target dB of every bed for the current fractions (audio spec 5.11 formulas).
func compute_targets(far_heat: float, zoom_scale: float) -> Dictionary:
	var full: Dictionary = _amb.get("full", {})
	var trim: Dictionary = _amb.get("trim_db", {})
	var fam: Array = _amb.get("family_wind_db", [0.0, -9.0, -3.0])
	var biomes: Array = _amb.get("biome", [])
	var b: Dictionary = biomes[clampi(_biome, 0, maxi(biomes.size() - 1, 0))] if not biomes.is_empty() else {}
	var off: float = SndConfig.SILENT_DB
	var detail: float = float(_amb.get("detail_zoom_db_per_unit", -6.0)) * maxf(zoom_scale - 1.0, 0.0)
	var t: Dictionary = {}
	t["wind_open"] = float(fam[clampi(_family, 0, fam.size() - 1)]) + float(b.get("wind_db", 0.0))
	t["city_hum"] = 0.0 if _family == 1 else off
	var coast: float = amp_db(f_water, float(full.get("coast", 0.25)))
	if _family == 2:
		coast = maxf(coast, float(_amb.get("coast_floor_db", -9.0)))
	t["coast_waves"] = coast
	if _family == 2:
		t["river_flow"] = off
	else:
		t["river_flow"] = maxf(amp_db(f_water, float(full.get("river", 0.15))) + float(trim.get("river", -3.0)) + detail, off)
	t["forest"] = maxf(amp_db(f_forest, float(full.get("forest", 0.33))) + float(trim.get("forest", -3.0)) + float(b.get("forest_db", 0.0)) + detail, off)
	t["battle_far"] = maxf(amp_db(far_heat, float(full.get("far_heat", 40.0))) + float(trim.get("battle_far", -6.0)), off)
	return t


func wind_pitch() -> float:
	var biomes: Array = _amb.get("biome", [])
	if biomes.is_empty():
		return 1.0
	return float((biomes[clampi(_biome, 0, biomes.size() - 1)] as Dictionary).get("wind_pitch", 1.0))


func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		stop(500)


func set_gain_db(db: float) -> void:
	_master_gain_db = db


func update(dt: float, focus: Vector3, zoom_scale: float, far_heat: float) -> void:
	if not _enabled:
		return
	_scan_left -= dt
	if _scan_left <= 0.0:
		_scan_left = float(_amb.get("scan_period_s", 0.5))
		histogram(focus, zoom_scale)
		targets = compute_targets(far_heat, zoom_scale)
	var start_db: float = float(_amb.get("start_db", -40.0))
	var stop_db: float = float(_amb.get("stop_db", -46.0))
	var stop_after: float = float(_amb.get("stop_after_s", 3.0))
	var fade_in: float = maxf(float(_amb.get("fade_in_s", 1.5)), 0.05)
	var fade_out: float = maxf(float(_amb.get("fade_out_s", 2.5)), 0.05)
	for bed: String in BEDS:
		var tgt: float = float(targets.get(bed, SndConfig.SILENT_DB)) + _master_gain_db
		var st: Variant = _beds.get(bed)
		if st == null:
			if tgt > start_db:
				_start_bed(bed)
			continue
		var s: Dictionary = st
		if tgt < stop_db:
			s["below_s"] = float(s["below_s"]) + dt
		else:
			s["below_s"] = 0.0
		var goal: float = tgt if float(s["below_s"]) < stop_after else SndConfig.SILENT_DB
		var tau: float = fade_in if goal > float(s["cur_db"]) else fade_out
		var step: float = (goal - float(s["cur_db"])) * (1.0 - exp(-dt / (tau * 0.4)))
		s["cur_db"] = float(s["cur_db"]) + clampf(step, -SndConfig.RAMP_MAX_STEP_DB_PER_FRAME, SndConfig.RAMP_MAX_STEP_DB_PER_FRAME)
		var p: AudioStreamPlayer = s["player"]
		p.volume_db = float(s["cur_db"])
		if bed == "wind_open":
			p.pitch_scale = wind_pitch()
		if float(s["below_s"]) >= stop_after and float(s["cur_db"]) < SndConfig.SILENT_DB + 3.0:
			p.stop()
			p.queue_free()
			_beds.erase(bed)


func _start_bed(bed: String) -> void:
	var def: SndEventDef = _map.get_def(StringName("snd.amb." + bed)) if _map != null else null
	if def == null:
		return
	var stream: AudioStream = def.pick_stream(RandomNumberGenerator.new(), &"")
	if stream == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = "Amb_" + bed
	p.bus = def.bus
	p.stream = stream
	p.volume_db = SndConfig.LOOP_START_DB
	add_child(p)
	var len_s: float = stream.get_length()
	p.play(randf() * len_s if len_s > 1.0 else 0.0)
	_beds[bed] = {"player": p, "cur_db": SndConfig.LOOP_START_DB, "below_s": 0.0}


func active_beds() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _beds.keys():
		out.append(str(k))
	out.sort()
	return out


func stop(_fade_ms: int) -> void:
	for k: Variant in _beds.keys():
		var p: AudioStreamPlayer = (_beds[k] as Dictionary)["player"]
		p.stop()
		p.queue_free()
	_beds.clear()
