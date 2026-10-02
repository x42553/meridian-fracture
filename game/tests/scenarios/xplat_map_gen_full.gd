extends SceneTree
## Cross-platform determinism scenario for the complete map generator (TM-08): 10 maps covering D1X / D2 / D4 and the
## rotation groups, all three families, a bay map, a repaired map (needs level 1+) and the safe template. Each line
## hashes map_hash, visual_hash and the field / neutral lists of one finished map; `tick` is the map index. Run:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_map_gen_full.gd
## Prints `HASH tick=<n> <8 hex digits>`; the chains must be identical on macOS / linux-amd64 / linux-arm64. Two runs in
## one process are compared first (SELFCHECK).

# [family, slots, size, seed, start_near_water, biome]
const CASES: Array = [
	[0, 2, 96, 1, false, 0], [0, 4, 128, 424242, false, 1], [0, 8, 192, 4294967295, false, 0],
	[1, 3, 112, 7, false, 0], [1, 6, 160, 12345, false, 0], [2, 2, 96, 3, true, 0],
	[2, 4, 128, 99, true, 0], [2, 8, 192, 20240517, false, 0], [2, 3, 192, 40595, false, 0], [2, 6, 160, 5, true, 0]]


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE maps=%d" % first.size())
	quit(0)


func _hash_map(m: MapData) -> int:
	var h: int = Checksum.mix(Checksum.FNV_OFFSET, m.map_hash())
	h = Checksum.mix(h, m.visual_hash())
	h = Checksum.mix(h, Checksum.digest32(m.fields))
	h = Checksum.mix(h, Checksum.digest32(m.neutrals))
	h = Checksum.mix(h, Checksum.digest32(m.spawns))
	h = Checksum.mix(h, Checksum.digest32_bytes(m.terrain))
	return Checksum.finalize(h)


func _run() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var idx: int = 0
	for c: Array in CASES:
		var cfg: Dictionary = {"family": c[0], "layout_players": c[1], "size": c[2], "seed": c[3],
			"params": {"start_near_water": c[4], "biome": c[5]}}
		var m: MapData = MapGenerator.generate(cfg)
		out.append("HASH tick=%d %08x" % [idx, _hash_map(m)])
		idx += 1
	var p: MapGenParams = MapGenParams.from_config({"family": 2, "layout_players": 4, "size": 128, "seed": 8})
	out.append("HASH tick=%d %08x" % [idx, _hash_map(MapGenTemplate.make(p))])
	return out
