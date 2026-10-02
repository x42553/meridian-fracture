class_name MapData
extends RefCounted
## The map (terrain_movement 3.3 / 4.1 + sim_core 7.2b): static terrain layers, derived layers, structure
## occupancy, per-cell deposits, view layers, incremental hashes, serialisation and the MapNav it owns.
##
## Lifecycle: `create` / `make_flat` / `from_bytes` -> (generator fills the public arrays) -> `finalize()` ->
## `clone_fresh()` per SimWorld. After finalize() the static layers are immutable BY CONVENTION (GDScript cannot
## lock a PackedArray): only occupy / vacate / harvest_* / regrow_field mutate the dynamic state, which is the
## only thing hashed each tick (`checksum_dynamic`, O(1)). Integer only; positions leave through cell indices.

const RIM_W: int = 6  ## unplayable rim (open / urban: 2 MOUNTAIN + 4 CLIFF; coast: DEEP)
const NAV_BORDER: int = 2  ## cells at Chebyshev distance < 2 from the edge are impassable in every nav profile
# ---- static flag bits (MapData.flags) ----
const SF_SHORE: int = 1  ## land cell 4-adjacent to water (dock / landing / foam)
const SF_NOBUILD: int = 2  ## static no-build (deposit ring, neutral lots, rim)
const SF_BLOCK: int = 4  ## static blocker prop (boulder, barricade): impassable to ALL profiles
const SF_START: int = 8  ## inside a start disc (analysis only; no rule effect)
const SF_RAMP: int = 16  ## cliff ramp cell (view mesh)
# ---- list strides ----
const SPAWN_STRIDE: int = 6  ## [start_index, cell, facing (toward centre), orbit, team_hint (index & 1), reserved]
const NEUTRAL_STRIDE: int = 8  ## [kind, cell (top-left), w, h, variant, flags, orbit, reserved]
const FIELD_STRIDE: int = 10  ## [id (1-based), center_cell, radius, cells, total, kind, orbit, hint_cell, klass, owner_start]
const FK_START: int = 0
const FK_NATURAL: int = 1
const FK_NATURAL_RICH: int = 2
const FK_FURTHER: int = 3
const FK_CONTESTED: int = 4
# ---- SimEntity.Layer values (mirrored: map must not reference sim) ----
const LAYER_GROUND: int = 0
const LAYER_AIR: int = 1
const LAYER_SURFACE: int = 2
const LAYER_UNDERWATER: int = 3
## Index space of `neutrals[kind]` for test maps (terrain_movement 4.3, order binding).
const NEUTRAL_IDS_DEFAULT: PackedStringArray = [
	"neutral.civilian_garrison", "neutral.substation", "neutral.salvage_depot", "neutral.field_hospital",
	"neutral.observation_tower", "neutral.harbor_terminal",
]
const FORMAT_MAGIC: int = 0x314D464D  ## "MFM1" little endian
const FORMAT_VERSION: int = 1
const _M: int = 0xFFFFFFFF

# ---- identity ----
var w: int = 0
var h: int = 0
var n: int = 0  ## w * h
## u32 hash of the static layers (finalize()); lobby / replay handshake. NOTE: the kernel reads it through the
## METHOD `map_hash()` (sim_core 7.2b), so the field carries a different name than terrain_movement 3.3's.
var static_hash: int = 0
var start_cells: PackedInt32Array = PackedInt32Array()  ## [cx0, cy0, ...] START ORDER; derived from `spawns`
var objects: Array = []  ## [{def_id: String, cx: int, cy: int}] derived from `neutrals`; deposits are `fields`
var seed_value: int = 0
var family: int = 0
var biome: int = 0
var slots: int = 0
var players: int = 0
var gen_version: int = 0
var neutral_ids: PackedStringArray = PackedStringArray()
var gen_params: PackedInt32Array = PackedInt32Array()
var tt: MapTerrain = null
var nav: MapNav = null
var nav_version: int = 0
# ---- static layers ----
var terrain: PackedByteArray = PackedByteArray()
var kind: PackedByteArray = PackedByteArray()  ## derived: TerrainKind
var flags: PackedByteArray = PackedByteArray()  ## SF_* bits
var buildable: PackedByteArray = PackedByteArray()  ## derived: 0 no, 1 standard, 2 shore-only
var water_comp: PackedInt32Array = PackedInt32Array()  ## derived: 4-connected water component id, -1 on land
var water_size: PackedInt32Array = PackedInt32Array()  ## derived: cells per component
var field_of: PackedByteArray = PackedByteArray()  ## 0 none, 1..64 field id
var deposit_max: PackedInt32Array = PackedInt32Array()
var spawns: PackedInt32Array = PackedInt32Array()
var neutrals: PackedInt32Array = PackedInt32Array()
var fields: PackedInt32Array = PackedInt32Array()
var height: PackedByteArray = PackedByteArray()  ## generator-internal 0..255 (source of `heights`)
# ---- view layers (not in map_hash) ----
var heights: PackedInt32Array = PackedInt32Array()  ## (w+1)*(h+1) lattice-corner heights in 1/32 m
var moisture: PackedByteArray = PackedByteArray()
var shore_dist: PackedByteArray = PackedByteArray()  ## chamfer 3-4 distance from land in 1/3 cell, 0 on land
var roads: Array = []  ## Array[PackedInt32Array] polylines [x0, y0, ...] in 1/16 cell
var water_level_u: int = 0
var deco: PackedByteArray = PackedByteArray()
var deco_seed: int = 0
# ---- dynamic state ----
var deposit: PackedInt32Array = PackedInt32Array()
var field_left: PackedInt32Array = PackedInt32Array()  ## by field id (index 0 unused)
var occ: PackedInt32Array = PackedInt32Array()  ## structure entity id or -1
var structs: Dictionary = {}  ## sid -> sorted PackedInt32Array of its cells (keyed lookups only)
var deposit_hash: int = 0
var occ_hash: int = 0

var _finalized: bool = false
var _pinned: bool = false
var _field_cells: Array[PackedInt32Array] = []  ## by field id: ascending cell list (static)
var _dirty: PackedInt32Array = PackedInt32Array()
var _dirty_mark: PackedByteArray = PackedByteArray()
var _fp: Dictionary = {}  ## (kind << 16 | def_idx) -> MapFootprint
var _neutral_defs: PackedInt32Array = PackedInt32Array()
var _neutral_ent_kinds: PackedInt32Array = PackedInt32Array()  ## per neutral kind: SimEntity.Kind of the spawned entity (default 1 = STRUCTURE)


# ---- construction / lifecycle --------------------------------------------------------------------------------

func _alloc(size_w: int, size_h: int) -> void:
	w = size_w
	h = size_h
	n = size_w * size_h
	terrain.resize(n)
	kind.resize(n)
	flags.resize(n)
	buildable.resize(n)
	field_of.resize(n)
	deposit_max.resize(n)
	height.resize(n)
	moisture.resize(n)
	deco.resize(n)
	heights.resize((size_w + 1) * (size_h + 1))
	occ.resize(n)
	occ.fill(-1)


## Zeroed layers, uniform terrain, RIM_W rim (outer 2 MOUNTAIN, next 4 CLIFF, all SF_NOBUILD). Used by the
## generator, templates and tests; call finalize() when the layers are filled.
static func create(p_tt: MapTerrain, size: int, fill_type: int = MapTerrain.T_GRASS) -> MapData:
	var m: MapData = MapData.new()
	m.tt = p_tt
	m._alloc(size, size)
	m.terrain.fill(fill_type)
	for y: int in size:
		for x: int in size:
			var d: int = mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			if d < RIM_W:
				var i: int = y * size + x
				m.terrain[i] = MapTerrain.T_MOUNTAIN if d < 2 else MapTerrain.T_CLIFF
				m.flags[i] = SF_NOBUILD
	return m


## sim_core R7 test map: all GRASS, no rim (only NAV_BORDER), the given start cells ([cx0, cy0, ...]), finalized,
## `map_hash()` pinned to the argument (finalize does not overwrite it).
static func make_flat(p_w: int, p_h: int, p_start_cells: PackedInt32Array, p_map_hash: int) -> MapData:
	var m: MapData = _flat_raw(p_w, p_h, p_start_cells, p_map_hash)
	if m != null:
		m.finalize()
	return m


## sim_core R7 fixture: a flat map with 8 (or any number of) spawn CELL INDICES `spawn_cells`, whole
## NEUTRAL_STRIDE `neutral_records`, default neutral_ids, pinned hash; finalized. Attach footprints / neutral
## defs with `set_footprint` / `set_neutral_def`.
static func for_test(p_w: int, p_h: int, spawn_cells: PackedInt32Array, neutral_records: PackedInt32Array,
		p_map_hash: int) -> MapData:
	var pairs: PackedInt32Array = PackedInt32Array()
	for c: int in spawn_cells:
		pairs.append(c % p_w)
		pairs.append(c / p_w)
	var m: MapData = _flat_raw(p_w, p_h, pairs, p_map_hash)
	if m == null:
		return null
	if neutral_records.size() % NEUTRAL_STRIDE != 0:
		push_error("MapData.for_test: neutral_records must be whole records of %d ints" % NEUTRAL_STRIDE)
		return null
	m.neutrals = neutral_records.duplicate()
	m.neutral_ids = NEUTRAL_IDS_DEFAULT.duplicate()
	m.finalize()
	return m


static func _flat_raw(p_w: int, p_h: int, p_start_cells: PackedInt32Array, p_map_hash: int) -> MapData:
	var t: MapTerrain = MapTerrain.load_default()
	if t == null or p_w < 8 or p_h < 8 or p_start_cells.size() % 2 != 0:
		push_error("MapData.make_flat: bad arguments or terrain tables unavailable")
		return null
	var m: MapData = MapData.new()
	m.tt = t
	m._alloc(p_w, p_h)
	m.terrain.fill(MapTerrain.T_GRASS)
	var ns: int = p_start_cells.size() / 2
	for k: int in ns:
		var cx: int = p_start_cells[k * 2]
		var cy: int = p_start_cells[k * 2 + 1]
		if cx < 0 or cy < 0 or cx >= p_w or cy >= p_h:
			push_error("MapData.make_flat: start cell (%d,%d) outside the map" % [cx, cy])
			return null
		m.spawns.append_array(PackedInt32Array([k, cy * p_w + cx, Fp.atan2(p_h / 2 - cy, p_w / 2 - cx), 0, k & 1, 0]))
	m.slots = ns
	m.players = ns
	m._pinned = true
	m.static_hash = p_map_hash & _M
	return m


## Once, after generation / load: SF_SHORE, kind + buildable layers, water components, shore_dist (if absent),
## map_hash (unless pinned), derived views (start_cells, objects), dynamic init (deposit = deposit_max, field
## state, occ = -1, hashes), MapNav weights + clearance + graphs.
func finalize() -> void:
	if _finalized:
		push_error("MapData.finalize: already finalized")
		return
	if tt == null or terrain.size() != w * h or w < 8 or h < 8:
		push_error("MapData.finalize: map not allocated")
		return
	_compute_shore_flags()
	_derive_kind_and_buildable()
	_derive_water_components()
	if shore_dist.size() != n:
		_derive_shore_dist()
	_derive_lists()
	if not _pinned:
		static_hash = content_hash()
	_init_dynamic()
	nav = MapNav.new(tt, w, h, terrain, flags, occ)
	nav.rebuild()
	nav.prepare_all()
	_finalized = true


func _compute_shore_flags() -> void:
	var kt: PackedByteArray = tt.kind_table()
	for i: int in n:
		var f: int = flags[i] & ~SF_SHORE
		var k: int = kt[terrain[i]]
		if k != MapTerrain.TK_SHALLOW and k != MapTerrain.TK_DEEP:
			var x: int = i % w
			var y: int = i / w
			if (x > 0 and _water_kind(kt[terrain[i - 1]])) or (x < w - 1 and _water_kind(kt[terrain[i + 1]])) \
					or (y > 0 and _water_kind(kt[terrain[i - w]])) or (y < h - 1 and _water_kind(kt[terrain[i + w]])):
				f |= SF_SHORE
		flags[i] = f


static func _water_kind(k: int) -> bool:
	return k == MapTerrain.TK_SHALLOW or k == MapTerrain.TK_DEEP


func _derive_kind_and_buildable() -> void:
	var kt: PackedByteArray = tt.kind_table()
	for i: int in n:
		var t: int = terrain[i]
		kind[i] = kt[t]
		var b: int = 0
		var tf: int = tt.flags(t)
		var x: int = i % w
		var y: int = i / w
		if (flags[i] & (SF_NOBUILD | SF_BLOCK)) == 0 and x >= NAV_BORDER and y >= NAV_BORDER \
				and x < w - NAV_BORDER and y < h - NAV_BORDER:
			if (tf & MapTerrain.TF_BUILD) != 0:
				b = 1
			elif (tf & MapTerrain.TF_BUILD_SHORE) != 0:
				b = 2
		buildable[i] = b


func _derive_water_components() -> void:
	water_comp.resize(n)
	water_comp.fill(-1)
	water_size = PackedInt32Array()
	var stack: PackedInt32Array = PackedInt32Array()
	for s: int in n:
		if water_comp[s] != -1 or not _water_kind(kind[s]):
			continue
		var id: int = water_size.size()
		var cnt: int = 0
		stack.clear()
		stack.append(s)
		water_comp[s] = id
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cnt += 1
			var x: int = c % w
			var y: int = c / w
			if x > 0 and water_comp[c - 1] == -1 and _water_kind(kind[c - 1]):
				water_comp[c - 1] = id
				stack.append(c - 1)
			if x < w - 1 and water_comp[c + 1] == -1 and _water_kind(kind[c + 1]):
				water_comp[c + 1] = id
				stack.append(c + 1)
			if y > 0 and water_comp[c - w] == -1 and _water_kind(kind[c - w]):
				water_comp[c - w] = id
				stack.append(c - w)
			if y < h - 1 and water_comp[c + w] == -1 and _water_kind(kind[c + w]):
				water_comp[c + w] = id
				stack.append(c + w)
		water_size.append(cnt)


## Chamfer 3-4 distance from land in 1/3 cell (0 on land, saturating 255). Skipped (all 0) on a dry map.
func _derive_shore_dist() -> void:
	shore_dist.resize(n)
	if water_size.is_empty():
		shore_dist.fill(0)
		return
	var d: PackedInt32Array = PackedInt32Array()
	d.resize(n)
	for i: int in n:
		d[i] = 255 if _water_kind(kind[i]) else 0
	for y: int in h:
		for x: int in w:
			var i: int = y * w + x
			var v: int = d[i]
			if v == 0:
				continue
			if x > 0:
				v = mini(v, d[i - 1] + 3)
			if y > 0:
				v = mini(v, d[i - w] + 3)
				if x > 0:
					v = mini(v, d[i - w - 1] + 4)
				if x < w - 1:
					v = mini(v, d[i - w + 1] + 4)
			d[i] = v
	for y: int in range(h - 1, -1, -1):
		for x: int in range(w - 1, -1, -1):
			var i: int = y * w + x
			var v: int = d[i]
			if v == 0:
				continue
			if x < w - 1:
				v = mini(v, d[i + 1] + 3)
			if y < h - 1:
				v = mini(v, d[i + w] + 3)
				if x < w - 1:
					v = mini(v, d[i + w + 1] + 4)
				if x > 0:
					v = mini(v, d[i + w - 1] + 4)
			d[i] = v
	for i: int in n:
		shore_dist[i] = mini(d[i], 255)


func _derive_lists() -> void:
	start_cells = PackedInt32Array()
	for k: int in spawns.size() / SPAWN_STRIDE:
		var cell: int = spawns[k * SPAWN_STRIDE + 1]
		start_cells.append(cell % w)
		start_cells.append(cell / w)
	objects = []
	for k: int in neutrals.size() / NEUTRAL_STRIDE:
		var nk: int = neutrals[k * NEUTRAL_STRIDE]
		var cell: int = neutrals[k * NEUTRAL_STRIDE + 1]
		var id: String = neutral_ids[nk] if nk >= 0 and nk < neutral_ids.size() else ""
		objects.append({"def_id": id, "cx": cell % w, "cy": cell / w})


func _init_dynamic() -> void:
	deposit = deposit_max.duplicate()
	occ.resize(n)
	occ.fill(-1)
	structs = {}
	occ_hash = 0
	nav_version = 0
	var nf: int = 0
	for k: int in fields.size() / FIELD_STRIDE:
		nf = maxi(nf, fields[k * FIELD_STRIDE])
	_field_cells = []
	for f: int in nf + 1:
		_field_cells.append(PackedInt32Array())
	field_left = PackedInt32Array()
	field_left.resize(nf + 1)
	deposit_hash = 0
	for i: int in n:
		var f: int = field_of[i]
		if f > 0 and f <= nf:
			_field_cells[f].append(i)
			field_left[f] += deposit_max[i]
		if deposit_max[i] > 0:
			deposit_hash = (deposit_hash + _dep_term(i, deposit[i])) & _M
	_dirty = PackedInt32Array()
	_dirty_mark = PackedByteArray()
	_dirty_mark.resize(n)


## Per-world instance (sim_core `clone_fresh`): static arrays shared, dynamic arrays and the nav layers / graphs
## copied. SimWorld MUST own its own instance (two worlds side by side, DR-9).
func clone_for_world() -> MapData:
	if not _finalized:
		push_error("MapData.clone_for_world: map is not finalized")
		return null
	var c: MapData = MapData.new()
	c.w = w
	c.h = h
	c.n = n
	c.static_hash = static_hash
	c.start_cells = start_cells
	c.objects = objects
	c.seed_value = seed_value
	c.family = family
	c.biome = biome
	c.slots = slots
	c.players = players
	c.gen_version = gen_version
	c.neutral_ids = neutral_ids
	c.gen_params = gen_params
	c.tt = tt
	c.terrain = terrain
	c.kind = kind
	c.flags = flags
	c.buildable = buildable
	c.water_comp = water_comp
	c.water_size = water_size
	c.field_of = field_of
	c.deposit_max = deposit_max
	c.spawns = spawns
	c.neutrals = neutrals
	c.fields = fields
	c.height = height
	c.heights = heights
	c.moisture = moisture
	c.shore_dist = shore_dist
	c.roads = roads
	c.water_level_u = water_level_u
	c.deco = deco
	c.deco_seed = deco_seed
	c._field_cells = _field_cells
	c._fp = _fp
	c._neutral_defs = _neutral_defs
	c._neutral_ent_kinds = _neutral_ent_kinds
	c._pinned = _pinned
	c.deposit = deposit.duplicate()
	c.field_left = field_left.duplicate()
	c.occ = occ.duplicate()
	c.structs = structs.duplicate()
	c.deposit_hash = deposit_hash
	c.occ_hash = occ_hash
	c.nav_version = nav_version
	c._dirty = _dirty.duplicate()
	c._dirty_mark = _dirty_mark.duplicate()
	c.nav = nav.clone_for(c.occ)
	c._finalized = true
	return c


## sim_core R7 name: the kernel calls this once per world (the template is never mutated, so a copy is fresh).
func clone_fresh() -> MapData:
	return clone_for_world()


## sim_core R7: the u32 handshake hash (lobby / replay); set by finalize(), pinned on make_flat / for_test maps.
func map_hash() -> int:
	return static_hash


func is_finalized() -> bool:
	return _finalized


## sim_core R7: appends [w, h, deposit_hash, occ_hash, nav_version] (mutable state only; O(1)).
func hash_state(buf: PackedInt32Array) -> void:
	buf.append(w)
	buf.append(h)
	buf.append(deposit_hash)
	buf.append(occ_hash)
	buf.append(nav_version)


## Recomputes the u32 hash of all static layers from scratch; equals map_hash() for an unmodified, unpinned map.
func content_hash() -> int:
	var c: Checksum = Checksum.new()
	for v: int in [w, h, seed_value, family, biome, slots, players, gen_version]:
		c.add64(v)
	c.add_packed(gen_params)
	c.add(Checksum.digest32_bytes(terrain))
	c.add(Checksum.digest32_bytes(flags))
	c.add(Checksum.digest32_bytes(field_of))
	c.add_packed(deposit_max)
	c.add_packed(spawns)
	c.add_packed(neutrals)
	c.add_packed(fields)
	for s: String in neutral_ids:
		c.h = Checksum.fnv_string(s, c.h)
	return c.value()


## FNV-1a-32 style digest over the view layers (heights / moisture / roads / deco); a mismatch is a warning, not
## a desync.
func visual_hash() -> int:
	var c: Checksum = Checksum.new()
	c.add_packed(heights)
	c.add(Checksum.digest32_bytes(moisture))
	c.add(Checksum.digest32_bytes(deco))
	c.add(Checksum.digest32_bytes(height))
	c.add(roads.size())
	for r: Variant in roads:
		c.add_packed(r as PackedInt32Array)
	c.add(water_level_u)
	c.add64(deco_seed)
	return c.value()


## O(n) from scratch (deposit terms, structure terms from `occ`, field_left); tests assert
## `== checksum_dynamic()`. An inconsistent field_left / structs table poisons the result.
func recompute_dynamic_hash() -> int:
	var dh: int = 0
	var fl: PackedInt32Array = PackedInt32Array()
	fl.resize(field_left.size())
	var acc: Dictionary = {}
	for i: int in n:
		if deposit_max[i] > 0:
			dh = (dh + _dep_term(i, deposit[i])) & _M
		var f: int = field_of[i]
		if f > 0 and f < fl.size():
			fl[f] += deposit[i]
		var s: int = occ[i]
		if s >= 0:
			acc[s] = Checksum.mix(acc.get(s, Checksum.FNV_OFFSET) as int, i)
	var oh: int = 0
	for s: int in acc:
		oh = (oh + _occ_term(s, acc[s] as int)) & _M
	if fl != field_left or acc.size() != structs.size():
		dh ^= _M
	return _fold_dynamic(dh, oh, nav_version)


## O(1): mix(deposit_hash, occ_hash, nav_version).
func checksum_dynamic() -> int:
	return _fold_dynamic(deposit_hash, occ_hash, nav_version)


static func _fold_dynamic(dh: int, oh: int, ver: int) -> int:
	return Checksum.finalize(Checksum.mix(Checksum.mix(Checksum.mix(Checksum.FNV_OFFSET, dh), oh), ver))


static func _dep_term(cell: int, amount: int) -> int:
	return Checksum.mix(Checksum.mix(Checksum.FNV_OFFSET, cell), amount)


static func _occ_term(sid: int, cells_fnv: int) -> int:
	return Checksum.mix(Checksum.mix(Checksum.FNV_OFFSET, sid), cells_fnv)


## Start indices to fill for `players` (< slots), in pick order: greedy farthest-point from index 0 (squared
## Euclidean distance between spawn cells), ties -> lowest index. Lobby helper.
func fair_slot_order(p_players: int) -> PackedInt32Array:
	var ns: int = spawns.size() / SPAWN_STRIDE
	var out: PackedInt32Array = PackedInt32Array()
	if ns == 0 or p_players <= 0:
		return out
	var chosen: PackedByteArray = PackedByteArray()
	chosen.resize(ns)
	out.append(0)
	chosen[0] = 1
	var mind: PackedInt32Array = PackedInt32Array()
	mind.resize(ns)
	for k: int in ns:
		mind[k] = _spawn_d2(0, k)
	while out.size() < mini(p_players, ns):
		var best: int = -1
		for k: int in ns:
			if chosen[k] == 0 and (best < 0 or mind[k] > mind[best]):
				best = k
		out.append(best)
		chosen[best] = 1
		for k: int in ns:
			mind[k] = mini(mind[k], _spawn_d2(best, k))
	return out


func _spawn_d2(a: int, b: int) -> int:
	var ca: int = spawns[a * SPAWN_STRIDE + 1]
	var cb: int = spawns[b * SPAWN_STRIDE + 1]
	var dx: int = ca % w - cb % w
	var dy: int = ca / w - cb / w
	return dx * dx + dy * dy


# ---- coordinates -----------------------------------------------------------------------------------------------

func idx(cx: int, cy: int) -> int:
	return cy * w + cx


func cell_x(i: int) -> int:
	return i % w


func cell_y(i: int) -> int:
	return i / w


func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < w and cy < h


## Inside the playable interior (outside the NAV_BORDER cells): where air units fly and structures may stand.
func in_interior(cx: int, cy: int) -> bool:
	return cx >= NAV_BORDER and cy >= NAV_BORDER and cx < w - NAV_BORDER and cy < h - NAV_BORDER


## Cell index of a position in units, clamped into the map.
func idx_of_units(x: int, y: int) -> int:
	return clampi(y >> 10, 0, h - 1) * w + clampi(x >> 10, 0, w - 1)


func center_x(i: int) -> int:
	return (i % w) * 1024 + 512


func center_y(i: int) -> int:
	return (i / w) * 1024 + 512


# ---- terrain, kinds, speeds ------------------------------------------------------------------------------------

func terrain_at(i: int) -> int:
	return terrain[i]


func kind_at(i: int) -> int:
	return kind[i]


func kind_at_units(x: int, y: int) -> int:
	return kind[idx_of_units(x, y)]


## tt.speed_bp(mc, terrain[i]); 0 = impassable (static terrain only).
func speed_bp_at(mc: int, i: int) -> int:
	return tt.speed_bp(mc, terrain[i])


# ---- predicates ------------------------------------------------------------------------------------------------

## Kind SHALLOW or DEEP (fords are water). False outside the map.
func is_water(cx: int, cy: int) -> bool:
	return in_bounds(cx, cy) and _water_kind(kind[cy * w + cx])


## Not water (cliffs are land). False outside the map.
func is_land(cx: int, cy: int) -> bool:
	return in_bounds(cx, cy) and not _water_kind(kind[cy * w + cx])


## Static: TF_BUILD terrain, no SF_NOBUILD / SF_BLOCK, inside the interior. Ignores structures, units, deposits.
func is_buildable(cx: int, cy: int) -> bool:
	return in_bounds(cx, cy) and buildable[cy * w + cx] == 1


## TF_BUILD or TF_BUILD_SHORE terrain, no SF_NOBUILD / SF_BLOCK, inside the interior (dock footprints).
func is_shore_buildable(cx: int, cy: int) -> bool:
	return in_bounds(cx, cy) and buildable[cy * w + cx] != 0


## Static terrain: foot profile weight != 0 (SF_BLOCK props count as blocked); ignores structures and NAV_BORDER.
func is_passable_ground(cx: int, cy: int) -> bool:
	if not in_bounds(cx, cy):
		return false
	var i: int = cy * w + cx
	return tt.weight(MapTerrain.NP_FOOT, terrain[i]) != 0 and (flags[i] & SF_BLOCK) == 0


## LIVE: nav weight != 0 of profile_of(mc, 500) (the small-hull profile for NAVAL; clearance is not tested),
## includes structures and NAV_BORDER; air classes -> inside the interior; static -> false.
func passable(cx: int, cy: int, mc: int) -> bool:
	if not in_bounds(cx, cy):
		return false
	if mc == MapTerrain.MC_AIR_FIXED or mc == MapTerrain.MC_AIR_HOVER:
		return in_interior(cx, cy)
	var np: int = MapTerrain.profile_of(mc, 500)
	if np == MapTerrain.NP_NONE:
		return false
	return nav.w_at(np, cy * w + cx) != 0


## No static blocker and no structure for an entity of `layer` (LAYER_*): GROUND = foot profile passable and
## occ < 0; SURFACE = naval passable; UNDERWATER = sub passable; AIR = inside the interior.
func is_clear(cx: int, cy: int, layer: int) -> bool:
	if not in_bounds(cx, cy):
		return false
	var i: int = cy * w + cx
	match layer:
		LAYER_GROUND:
			return nav.w_at(MapTerrain.NP_FOOT, i) != 0 and occ[i] < 0
		LAYER_SURFACE:
			return nav.w_at(MapTerrain.NP_NAVAL, i) != 0 and occ[i] < 0
		LAYER_UNDERWATER:
			return nav.w_at(MapTerrain.NP_SUB, i) != 0 and occ[i] < 0
		LAYER_AIR:
			return in_interior(cx, cy)
	return false


## Cells of the 4-connected water component (SHALLOW + DEEP + FORD) containing the cell, 0 on land.
func water_body_size(cx: int, cy: int) -> int:
	if not in_bounds(cx, cy):
		return 0
	var c: int = water_comp[cy * w + cx]
	return water_size[c] if c >= 0 else 0


## SF_SHORE: land cell 4-adjacent to water.
func has_adjacent_water(cx: int, cy: int) -> bool:
	return in_bounds(cx, cy) and (flags[cy * w + cx] & SF_SHORE) != 0


## Abstract-graph component id of the cell for the class's (profile, default size); -1 if blocked / no graph.
func region(cx: int, cy: int, mc: int) -> int:
	if not in_bounds(cx, cy):
		return -1
	var np: int = MapTerrain.profile_of(mc, 500)
	if np == MapTerrain.NP_NONE:
		return -1
	return nav.region_id(np, MapTerrain.nav_size(mc, 500), cy * w + cx)


## FAM_OPEN 0 / FAM_URBAN 1 / FAM_COAST 2 (== `family`; a method because ai.md calls family()).
func get_family() -> int:
	return family


# ---- structures ------------------------------------------------------------------------------------------------

## sim_core R7: occupies the footprint `fp` (MapFootprint) rotated by `orient` with the top-left cell (cx, cy)
## of its ORIENTED bounding box. Returns the packed changed bbox or -1 (+push_error) on a bad call.
func occupy(sid: int, fp: MapFootprint, cx: int, cy: int, orient: int) -> int:
	if fp == null:
		push_error("MapData.occupy: null footprint")
		return -1
	var cells: PackedInt32Array = PackedInt32Array()
	if fp.cells_at(orient, cx, cy, cells, w, h) < 0:
		push_error("MapData.occupy: footprint of structure %d leaves the map at (%d,%d)" % [sid, cx, cy])
		return -1
	return occupy_cells(sid, cells)


## terrain_movement 3.3 form: occupies exactly `cells`. occ[cell] = sid, weight 0 in ALL nav profiles there,
## MapNav.on_cells_changed(bbox), nav_version++. Precondition (checked): cells in bounds and free, sid unused.
## Returns the changed bbox packed as (cx0 << 24) | (cy0 << 16) | (cx1 << 8) | cy1, or -1 (+push_error).
func occupy_cells(sid: int, cells: PackedInt32Array) -> int:
	if not _finalized or sid < 0 or cells.is_empty() or structs.has(sid):
		push_error("MapData.occupy: bad call (finalized=%s sid=%d cells=%d)" % [str(_finalized), sid, cells.size()])
		return -1
	var sorted: PackedInt32Array = cells.duplicate()
	sorted.sort()
	var prev: int = -1
	for c: int in sorted:
		if c < 0 or c >= n or c == prev or occ[c] >= 0:
			push_error("MapData.occupy: cell %d of structure %d is outside the map, repeated or occupied" % [c, sid])
			return -1
		prev = c
	var x0: int = w
	var y0: int = h
	var x1: int = 0
	var y1: int = 0
	var hh: int = Checksum.FNV_OFFSET
	for c: int in sorted:
		occ[c] = sid
		hh = Checksum.mix(hh, c)
		x0 = mini(x0, c % w)
		x1 = maxi(x1, c % w)
		y0 = mini(y0, c / w)
		y1 = maxi(y1, c / w)
	structs[sid] = sorted
	occ_hash = (occ_hash + _occ_term(sid, hh)) & _M
	nav.on_cells_changed(x0, y0, x1, y1)
	nav_version += 1
	return _pack_bbox(x0, y0, x1, y1)


## Exact inverse of occupy (stored cell list); weights restored from terrain / flags; returns the packed bbox,
## or -1 when the structure occupies nothing (no error: the kernel may vacate footprint-less entities).
func vacate(sid: int) -> int:
	if not structs.has(sid):
		return -1
	var sorted: PackedInt32Array = structs[sid]
	var x0: int = w
	var y0: int = h
	var x1: int = 0
	var y1: int = 0
	var hh: int = Checksum.FNV_OFFSET
	for c: int in sorted:
		occ[c] = -1
		hh = Checksum.mix(hh, c)
		x0 = mini(x0, c % w)
		x1 = maxi(x1, c % w)
		y0 = mini(y0, c / w)
		y1 = maxi(y1, c / w)
	structs.erase(sid)
	occ_hash = (occ_hash - _occ_term(sid, hh)) & _M
	nav.on_cells_changed(x0, y0, x1, y1)
	nav_version += 1
	return _pack_bbox(x0, y0, x1, y1)


static func _pack_bbox(x0: int, y0: int, x1: int, y1: int) -> int:
	return (x0 << 24) | (y0 << 16) | (x1 << 8) | y1


## Structure entity id or -1 (= the world's structure grid; there is exactly one copy).
func structure_at(i: int) -> int:
	return occ[i]


## sim_core R7 name of structure_at; -1 = free or outside the map (the kernel's struct_at maps < 0 to 0).
func occupant_at(i: int) -> int:
	if i < 0 or i >= n:
		return -1
	return occ[i]


## sim_core R7: the def's footprint or null (occupies nothing). Registered with set_footprint.
func footprint_of(p_kind: int, def_idx: int) -> MapFootprint:
	return _fp.get((p_kind << 16) | def_idx) as MapFootprint


func set_footprint(p_kind: int, def_idx: int, fp: MapFootprint) -> void:
	_fp[(p_kind << 16) | def_idx] = fp


## sim_core R7: STRUCTURE def index of a neutral kind (index into `neutral_ids`), -1 = scenery / unmapped.
func neutral_def_for_kind(nk: int) -> int:
	if nk < 0 or nk >= _neutral_defs.size():
		return -1
	return _neutral_defs[nk]


## `ent_kind` = SimEntity.Kind of the entity the world spawns for this neutral kind: 1 (STRUCTURE, `def_idx` indexes
## GameData.structures, the kernel test kit's convention) or 4 (NEUTRAL, `def_idx` indexes GameData.neutrals: real matches).
func set_neutral_def(nk: int, def_idx: int, ent_kind: int = 1) -> void:
	if nk < 0:
		return
	while _neutral_defs.size() <= nk:
		_neutral_defs.append(-1)
		_neutral_ent_kinds.append(1)
	_neutral_defs[nk] = def_idx
	_neutral_ent_kinds[nk] = ent_kind


## SimEntity.Kind spawned for a neutral kind (1 = STRUCTURE unless set_neutral_def said otherwise).
func neutral_ent_kind(nk: int) -> int:
	if nk < 0 or nk >= _neutral_ent_kinds.size():
		return 1
	return _neutral_ent_kinds[nk]


# ---- deposits --------------------------------------------------------------------------------------------------

func deposit_at(i: int) -> int:
	return deposit[i]


## 0 = none else the 1-based field id.
func field_of_cell(i: int) -> int:
	return field_of[i]


func field_remaining(field_id: int) -> int:
	if field_id <= 0 or field_id >= field_left.size():
		return 0
	return field_left[field_id]


func _set_deposit(i: int, amount: int) -> void:
	var old: int = deposit[i]
	deposit[i] = amount
	if deposit_max[i] > 0:
		deposit_hash = (deposit_hash - _dep_term(i, old) + _dep_term(i, amount)) & _M
	var f: int = field_of[i]
	if f > 0 and f < field_left.size():
		field_left[f] += amount - old
	if _dirty_mark[i] == 0:
		_dirty_mark[i] = 1
		_dirty.append(i)


## Removes min(want, deposit[i]); updates deposit_hash, field_left, the dirty list; returns the amount taken.
func harvest_cell(i: int, want: int) -> int:
	if i < 0 or i >= n or want <= 0:
		return 0
	var take: int = mini(want, deposit[i])
	if take <= 0:
		return 0
	_set_deposit(i, deposit[i] - take)
	return take


## Takes up to `want` from the NON-EMPTY cell of the field nearest to `from_cell` (Chebyshev, then lowest index),
## one cell per call; returns the amount taken (0 = field empty).
func harvest_field(field_id: int, from_cell: int, want: int) -> int:
	if field_id <= 0 or field_id >= _field_cells.size() or want <= 0:
		return 0
	var fx: int = from_cell % w
	var fy: int = from_cell / w
	var best: int = -1
	var best_d: int = 1 << 30
	for c: int in _field_cells[field_id]:
		if deposit[c] > 0:
			var d: int = maxi(absi(c % w - fx), absi(c / w - fy))
			if d < best_d:
				best_d = d
				best = c
	if best < 0:
		return 0
	return harvest_cell(best, want)


## Adds up to `amount` to the lowest-index cells below deposit_max; returns the amount added.
func regrow_field(field_id: int, amount: int) -> int:
	if field_id <= 0 or field_id >= _field_cells.size() or amount <= 0:
		return 0
	var left: int = amount
	for c: int in _field_cells[field_id]:
		var room: int = deposit_max[c] - deposit[c]
		if room > 0:
			var add: int = mini(room, left)
			_set_deposit(c, deposit[c] + add)
			left -= add
			if left == 0:
				break
	return amount - left


## Deterministic ring search (ring 0..max_ring, then row-major inside the ring) for a non-empty cell; -1 if none.
func nearest_deposit(from_i: int, max_ring: int) -> int:
	var cx: int = from_i % w
	var cy: int = from_i / w
	for r: int in range(0, max_ring + 1):
		for y: int in range(cy - r, cy + r + 1):
			if y < 0 or y >= h:
				continue
			if absi(y - cy) == r:
				for x: int in range(maxi(cx - r, 0), mini(cx + r, w - 1) + 1):
					if deposit[y * w + x] > 0:
						return y * w + x
			else:
				if cx - r >= 0 and deposit[y * w + cx - r] > 0:
					return y * w + cx - r
				if cx + r < w and deposit[y * w + cx + r] > 0:
					return y * w + cx + r
	return -1


## Output-only list for the view: `out` receives the cells changed since the last drain (each once); clears the
## list; NOT checksummed. Returns the count.
func drain_deposit_dirty(out: PackedInt32Array) -> int:
	out.clear()
	out.append_array(_dirty)
	for c: int in _dirty:
		_dirty_mark[c] = 0
	_dirty.clear()
	return out.size()


## Array[Dictionary] {id, cx, cy, radius, klass_economy (0 start, 1 expansion, 2 rich), kind, cells, total}: the
## economy's SimDepositTable build input. `cells` / `total` are counted from the layers.
func deposit_fields() -> Array:
	var out: Array = []
	for k: int in fields.size() / FIELD_STRIDE:
		var r: int = k * FIELD_STRIDE
		var id: int = fields[r]
		var fk: int = fields[r + 5]
		var total: int = 0
		for c: int in _field_cells[id]:
			total += deposit_max[c]
		var ke: int = 1
		if fk == FK_START:
			ke = 0
		elif fk == FK_NATURAL_RICH or fields[r + 8] == 1:
			ke = 2
		out.append({"id": id, "cx": fields[r + 1] % w, "cy": fields[r + 1] / w, "radius": fields[r + 2],
			"klass_economy": ke, "kind": fk, "cells": _field_cells[id].size(), "total": total})
	return out


## Array[Dictionary] {type: String, cx, cy} = `objects` (economy.md 13-13 name).
func neutral_spawns() -> Array:
	var out: Array = []
	for o: Variant in objects:
		var d: Dictionary = o
		out.append({"type": d["def_id"], "cx": d["cx"], "cy": d["cy"]})
	return out


# ---- serialisation ---------------------------------------------------------------------------------------------

static func _put_ints(sb: StreamPeerBuffer, a: PackedInt32Array) -> void:
	sb.put_u32(a.size())
	if not a.is_empty():
		sb.put_data(a.to_byte_array())


static func _put_bytes(sb: StreamPeerBuffer, a: PackedByteArray) -> void:
	sb.put_u32(a.size())
	if not a.is_empty():
		sb.put_data(a)


static func _get_ints(sb: StreamPeerBuffer, max_count: int) -> Variant:
	if sb.get_available_bytes() < 4:
		return null
	var cnt: int = sb.get_u32()
	if cnt > max_count or sb.get_available_bytes() < cnt * 4:
		return null
	if cnt == 0:
		return PackedInt32Array()
	return (sb.get_data(cnt * 4)[1] as PackedByteArray).to_int32_array()


static func _get_bytes(sb: StreamPeerBuffer, max_count: int) -> Variant:
	if sb.get_available_bytes() < 4:
		return null
	var cnt: int = sb.get_u32()
	if cnt > max_count or sb.get_available_bytes() < cnt:
		return null
	if cnt == 0:
		return PackedByteArray()
	return sb.get_data(cnt)[1] as PackedByteArray


## Header (magic, version, raw size, body FNV) + DEFLATE(all static layers + lists + view layers). Byte-stable
## for equal maps.
func to_bytes() -> PackedByteArray:
	var sb: StreamPeerBuffer = StreamPeerBuffer.new()
	sb.put_u32(w)
	sb.put_u32(h)
	sb.put_64(seed_value)
	for v: int in [family, biome, slots, players, gen_version, water_level_u, deco_seed]:
		sb.put_64(v)
	sb.put_u8(1 if _pinned else 0)
	sb.put_u32(static_hash)
	_put_ints(sb, gen_params)
	_put_bytes(sb, terrain)
	_put_bytes(sb, flags)
	_put_bytes(sb, field_of)
	_put_ints(sb, deposit_max)
	_put_ints(sb, spawns)
	_put_ints(sb, neutrals)
	_put_ints(sb, fields)
	sb.put_u32(neutral_ids.size())
	for s: String in neutral_ids:
		sb.put_utf8_string(s)
	_put_bytes(sb, height)
	_put_bytes(sb, moisture)
	_put_bytes(sb, shore_dist)
	_put_bytes(sb, deco)
	_put_ints(sb, heights)
	sb.put_u32(roads.size())
	for r: Variant in roads:
		_put_ints(sb, r as PackedInt32Array)
	var raw: PackedByteArray = sb.data_array
	var body: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var hd: StreamPeerBuffer = StreamPeerBuffer.new()
	hd.put_u32(FORMAT_MAGIC)
	hd.put_u32(FORMAT_VERSION)
	hd.put_u32(raw.size())
	hd.put_u32(Checksum.fnv_bytes(body))
	var out: PackedByteArray = hd.data_array
	out.append_array(body)
	return out


## null (+push_error) if corrupt / version mismatch; calls finalize().
static func from_bytes(p_tt: MapTerrain, b: PackedByteArray) -> MapData:
	if b.size() < 16:
		push_error("MapData.from_bytes: truncated header")
		return null
	var hd: StreamPeerBuffer = StreamPeerBuffer.new()
	hd.data_array = b.slice(0, 16)
	if hd.get_u32() != FORMAT_MAGIC or hd.get_u32() != FORMAT_VERSION:
		push_error("MapData.from_bytes: bad magic or version")
		return null
	var raw_size: int = hd.get_u32()
	var body_fnv: int = hd.get_u32()
	var body: PackedByteArray = b.slice(16)
	if Checksum.fnv_bytes(body) != body_fnv or raw_size <= 0 or raw_size > (1 << 28):
		push_error("MapData.from_bytes: corrupt data (checksum mismatch)")
		return null
	var raw: PackedByteArray = body.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		push_error("MapData.from_bytes: corrupt data (inflate failed)")
		return null
	var m: MapData = _read_payload(p_tt, raw)
	if m == null:
		push_error("MapData.from_bytes: corrupt payload")
		return null
	m.finalize()
	if not m._finalized or (not m._pinned and m.static_hash != m.content_hash()):
		push_error("MapData.from_bytes: static hash mismatch")
		return null
	return m


static func _read_payload(p_tt: MapTerrain, raw: PackedByteArray) -> MapData:
	var sb: StreamPeerBuffer = StreamPeerBuffer.new()
	sb.data_array = raw
	if sb.get_available_bytes() < 8 + 8 + 8 * 7 + 1 + 4:
		return null
	var m: MapData = MapData.new()
	m.tt = p_tt
	var pw: int = sb.get_u32()
	var ph: int = sb.get_u32()
	if pw < 8 or ph < 8 or pw > 1024 or ph > 1024:
		return null
	m._alloc(pw, ph)
	m.seed_value = sb.get_64()
	m.family = sb.get_64()
	m.biome = sb.get_64()
	m.slots = sb.get_64()
	m.players = sb.get_64()
	m.gen_version = sb.get_64()
	m.water_level_u = sb.get_64()
	m.deco_seed = sb.get_64()
	m._pinned = sb.get_u8() == 1
	m.static_hash = sb.get_u32()
	var cap: int = m.n * 4 + 4096
	var gp: Variant = _get_ints(sb, 1 << 16)
	var trn: Variant = _get_bytes(sb, m.n)
	var fl: Variant = _get_bytes(sb, m.n)
	var fo: Variant = _get_bytes(sb, m.n)
	var dm: Variant = _get_ints(sb, m.n)
	var sp: Variant = _get_ints(sb, cap)
	var ne: Variant = _get_ints(sb, cap)
	var fi: Variant = _get_ints(sb, cap)
	if gp == null or trn == null or fl == null or fo == null or dm == null or sp == null or ne == null or fi == null:
		return null
	if (trn as PackedByteArray).size() != m.n or (fl as PackedByteArray).size() != m.n \
			or (fo as PackedByteArray).size() != m.n or (dm as PackedInt32Array).size() != m.n:
		return null
	m.gen_params = gp
	m.terrain = trn
	m.flags = fl
	m.field_of = fo
	m.deposit_max = dm
	m.spawns = sp
	m.neutrals = ne
	m.fields = fi
	if sb.get_available_bytes() < 4:
		return null
	var nn: int = sb.get_u32()
	if nn > 4096:
		return null
	for k: int in nn:
		if sb.get_available_bytes() < 4:
			return null
		m.neutral_ids.append(sb.get_utf8_string())
	var hgt: Variant = _get_bytes(sb, m.n)
	var moi: Variant = _get_bytes(sb, m.n)
	var shd: Variant = _get_bytes(sb, m.n)
	var dec: Variant = _get_bytes(sb, m.n)
	var hts: Variant = _get_ints(sb, cap)
	if hgt == null or moi == null or shd == null or dec == null or hts == null:
		return null
	if (hgt as PackedByteArray).size() != m.n or (moi as PackedByteArray).size() != m.n \
			or (dec as PackedByteArray).size() != m.n or (hts as PackedInt32Array).size() != m.heights.size() \
			or ((shd as PackedByteArray).size() != m.n and not (shd as PackedByteArray).is_empty()):
		return null
	m.height = hgt
	m.moisture = moi
	m.shore_dist = shd
	m.deco = dec
	m.heights = hts
	if sb.get_available_bytes() < 4:
		return null
	var nr: int = sb.get_u32()
	if nr > 4096:
		return null
	for k: int in nr:
		var r: Variant = _get_ints(sb, 1 << 20)
		if r == null:
			return null
		m.roads.append(r)
	if sb.get_available_bytes() != 0:
		return null
	return m
