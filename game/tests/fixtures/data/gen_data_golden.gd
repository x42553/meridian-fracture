extends SceneTree
## Regenerates tests/golden/data_hash.json (the pinned hashes of DefTestKit.small_data()).
## Run only after an INTENDED change of the data model or of the kit: tools/gd run res://tests/fixtures/data/gen_data_golden.gd

const OUT: String = "res://tests/golden/data_hash.json"


func _init() -> void:
	var f: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(DefTestKit.golden_dict(), "  ", true) + "\n")
	f.close()
	quit(0)
