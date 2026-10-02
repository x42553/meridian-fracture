class_name MapGenTemplate
extends RefCounted
## The safe fallback map (terrain_movement 5.12.6): a dry GRASS / DIRT map (folded hash scatter) with the rim, the same
## starts / gates / fields code at level 2 (17-cell discs, 9-wide corridors), one small ROCK cluster per image at
## 0.35 R, no neutrals and no bays. It validates by construction (V1..V10; V11 is never requested: the template's
## gen_params carry start_near_water = 0). Deterministic, integer only.


## `p_params` is copied (start_near_water cleared); tt / tables default to the cached loaders.
static func make(p_params: MapGenParams, p_tt: MapTerrain = null, p_tables: MapGenTables = null) -> MapData:
	var tt: MapTerrain = p_tt if p_tt != null else MapTerrain.load_default()
	var tables: MapGenTables = p_tables if p_tables != null else MapGenTables.load_default()
	var p: MapGenParams = MapGenParams.from_config({})
	p.size = p_params.size
	p.family = p_params.family
	p.seed_value = p_params.seed_value
	p.slots = p_params.slots
	p.water_pct = p_params.water_pct
	p.density = p_params.density
	p.resources = p_params.resources
	p.neutrals = p_params.neutrals
	p.biome = p_params.biome
	p.start_near_water = false
	var size: int = p.size
	var m: MapData = MapData.create(tt, size, MapTerrain.T_GRASS)
	var sym: MapGenSymmetry = MapGenSymmetry.new(p.slots, size)
	var rim: int = MapData.RIM_W
	var s: int = p.seed_value
	var dirt: int = MapTerrain.T_DIRT
	for y: int in range(rim, size - rim):
		var y2: int = 2 * y + 1 - size
		for x: int in range(rim, size - rim):
			var f: int = sym.fold(2 * x + 1 - size, y2)
			var fu: int = MapGenSymmetry.fold_u(f)
			var fv: int = MapGenSymmetry.fold_v(f)
			if p.biome == 1 or (MapGenNoise.hash2(fu, fv, s + 5) & 7) == 0:
				m.terrain[y * size + x] = dirt
	m.seed_value = p.seed_value
	m.family = p.family
	m.biome = 3 if p.family == MapGenParams.FAM_URBAN else p.biome
	m.slots = p.slots
	m.players = p.slots
	m.gen_version = MapGenParams.VERSION
	m.gen_params = p.to_ints()
	var l: MapGenLayout = MapGenLayout.run(m, tt, tables, p, s, 2, true)
	if not l.ok:
		push_error("MapGenTemplate.make: layout failed (%s)" % l.failure)
	m.finalize()
	MapGenView.fill_heights(m, m.height, PackedByteArray(), -1000)
	MapGenView.fill_deco(m)
	return m
