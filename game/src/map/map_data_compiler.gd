class_name MapDataCompiler
extends DefDomainCompiler
## Brings the map module's sim-critical balance files (terrain.json, map_gen.json) under the data pipeline
## (data_balance 5.11 / 7.2): they are manifest files, parsed here from the loader's DefSources, folded into the
## data hash as table "map" and into the per-file hashes of the lobby handshake. The map generator itself still
## reads the same files through MapTerrain.load_default() / MapGenTables.load_default() (identical bytes on one disk).

const FILES: PackedStringArray = ["map_gen.json", "terrain.json"]


func domain_id() -> String:
	return "map"


func file_names() -> PackedStringArray:
	return FILES


func compile(src: DefSources, data: GameData, rep: DefLoadReport) -> void:
	var td: Dictionary = src.balance.get("terrain.json", {})
	var tt: MapTerrain = MapTerrain.from_dict(td, data.moves)
	if tt == null:
		rep.error("V-SCH-03", "terrain.json", "rejected by MapTerrain (see the error log above)")
		return
	var gd: Dictionary = src.balance.get("map_gen.json", {})
	var err: String = MapGenTables.error_of(gd)
	if err != "":
		rep.error("V-SCH-03", "map_gen.json", err)
		return
	var gt: MapGenTables = MapGenTables.from_dict(gd)
	if gt == null:
		rep.error("V-SCH-03", "map_gen.json", "rejected by MapGenTables")
		return
	data.ext["map"] = MapDataTables.new(tt, gt)


func table_hashes(data: GameData) -> Dictionary:
	var m: Variant = data.ext.get("map")
	if not (m is MapDataTables):
		return {"map": 0}
	var mt: MapDataTables = m
	var h: int = DefHash.mix_int(DefHash.OFFSET, mt.terrain.table_hash())
	h = DefHash.mix_int(h, mt.gen.table_hash())
	return {"map": h}
