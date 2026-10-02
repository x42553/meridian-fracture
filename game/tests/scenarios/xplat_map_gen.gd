extends SceneTree
## Cross-platform determinism scenario for the map generator (TM-07, phase A): 3 seeds x 3 families, covering an exact
## group (D2, 4 slots), a rotation group (DN3) and D4 (8 slots, the largest seed). Each line hashes the generated terrain,
## flag, height and moisture layers of one map; `tick` is the map index (seed-major). Run:
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_map_gen.gd
## Prints `HASH tick=<n> <8 hex digits>`; the chains must be identical on macOS / linux-amd64 / linux-arm64. Two runs in
## one process are compared first (SELFCHECK).

const SEEDS: Array[int] = [1, 424242, 4294967295]
const SLOTS: Array[int] = [4, 3, 8]
const SIZES: Array[int] = [128, 112, 192]


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


func _run() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var tt: MapTerrain = MapTerrain.load_default()
	var tables: MapGenTables = MapGenTables.load_default()
	var idx: int = 0
	for si: int in SEEDS.size():
		for fam: int in 3:
			var p: MapGenParams = MapGenParams.from_config({"family": fam, "layout_players": SLOTS[si], "size": SIZES[si],
				"seed": SEEDS[si], "params": {"biome": si if fam == 0 else 0}})
			var g: MapGenTerrain = MapGenTerrain.generate(tt, p, tables, SEEDS[si])
			var h: int = Checksum.mix(Checksum.FNV_OFFSET, tables.table_hash())
			h = Checksum.mix(h, Checksum.digest32_bytes(g.terrain_base))
			h = Checksum.mix(h, Checksum.digest32_bytes(g.flags_base))
			h = Checksum.mix(h, Checksum.digest32_bytes(g.height))
			h = Checksum.mix(h, Checksum.digest32_bytes(g.moisture))
			h = Checksum.mix(h, Checksum.digest32_bytes(g.plateau))
			out.append("HASH tick=%d %08x" % [idx, Checksum.finalize(h)])
			idx += 1
	return out
