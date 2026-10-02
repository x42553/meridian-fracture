class_name AiSharedData
extends RefCounted
## Per-match immutable derived data shared by all controllers (ai.md 2.2 / 3.7): per-roster role tables, tech graphs, unit
## and structure profiles, and the coarse route graph. Built lazily from the first bound world view; tables only ever
## grow (caches), values never change once built. One instance per AiFactory (no global state).

var store: AiDataStore = null
var data: GameData = null
var route: AiRouteGraph = null
var _res: Dictionary = {}  ## roster idx -> AiRoleResolver
var _tech: Dictionary = {}  ## roster idx -> AiTechGraph
var _uprof: Dictionary = {}  ## roster idx -> Dictionary def -> AiUnitProfile
var _sprof: Dictionary = {}


func _init(p_store: AiDataStore = null) -> void:
	store = p_store if p_store != null else AiDataStore.load_default()


## Binds the GameData (first call wins) and creates the route graph shell.
func bind(view: AiWorldView) -> void:
	if data == null:
		data = view.game_data()
	if route == null:
		route = AiRouteGraph.new(store)


func resolver(roster_idx: int) -> AiRoleResolver:
	if not _res.has(roster_idx):
		_res[roster_idx] = AiRoleResolver.resolve(data, data.rosters[roster_idx], store)
	return _res[roster_idx]


func tech_graph(roster_idx: int) -> AiTechGraph:
	if not _tech.has(roster_idx):
		_tech[roster_idx] = AiTechGraph.build(data, data.rosters[roster_idx])
	return _tech[roster_idx]


func unit_profile(roster_idx: int, def_idx: int) -> AiUnitProfile:
	if not _uprof.has(roster_idx):
		_uprof[roster_idx] = {}
	var m: Dictionary = _uprof[roster_idx]
	if not m.has(def_idx):
		m[def_idx] = AiUnitProfile.build_unit(data, data.rosters[roster_idx], def_idx, resolver(roster_idx))
	return m[def_idx]


func struct_profile(roster_idx: int, def_idx: int) -> AiUnitProfile:
	if not _sprof.has(roster_idx):
		_sprof[roster_idx] = {}
	var m: Dictionary = _sprof[roster_idx]
	if not m.has(def_idx):
		m[def_idx] = AiUnitProfile.build_structure(data, data.rosters[roster_idx], def_idx, resolver(roster_idx))
	return m[def_idx]


## Route graph for one move class over the bound view's map (built on first use; see AiRouteGraph).
func route_graph(view: AiWorldView) -> AiRouteGraph:
	route.ensure_map(view)
	return route
