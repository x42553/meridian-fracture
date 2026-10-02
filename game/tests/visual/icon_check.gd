extends Node
## VIEW-M9 render check (V-12). Needs a real renderer:  tools/gd run res://tests/visual/icon_check.tscn --gui
## Bakes a mixed set of models in two faction styles at every size, then asserts: corner alpha 0, a filled body, framing
## (the alpha bounds cover most of the frame), PNG files written, and a second pass served from the disk cache in < 2 ms per icon.
## Prints RESULT lines and exits 0 / 1.

const RECIPES: PackedStringArray = ["unit.napc.rifle_squad", "unit.napc.bastion_heavy_tank", "unit.napc.falcon_interceptor",
	"unit.napc.aegis_frigate", "structure.shared.factory", "structure.shared.radar", "structure.napc.atlas_kinetic_array",
	"unit.def.hammer_tank", "unit.han.collector"]

var _fails: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", msg)


func _run() -> void:
	var bake: ViewIconBake = ViewIconBake.new()
	bake.setup_standalone()
	bake.cache_dir = "user://cache/icons_check"
	add_child(bake)
	print("RESULT clear: %d files" % bake.clear_disk_cache())
	var book: ViewRecipeBook = bake.recipe_book()
	var ids: Array[String] = []
	for rid: String in RECIPES:
		if book.has_recipe(StringName(rid)):
			ids.append(rid)
	_check(ids.size() >= 5, "enough recipes exist (%d)" % ids.size())
	var reqs: Array = []
	for rid2: String in ids:
		var st: StringName = book.style_for_def(rid2, "roster.napc.canada")
		for sz: int in 4:
			reqs.append({"tag": StringName("%s|%d" % [rid2, sz]), "recipe": StringName(rid2), "style": st, "scale_bp": 10000, "size": sz})
	var t0: int = Time.get_ticks_usec()
	bake.prewarm(reqs)
	await bake.wait_idle()
	var cold_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	print("RESULT cold bake: %d icons in %.0f ms (%.1f ms each), bakes=%d" % [reqs.size(), cold_ms, cold_ms / float(reqs.size()), bake.stats["bakes"]])
	_check(int(bake.stats["bakes"]) > 0, "something was baked")
	for r: Dictionary in reqs:
		var tex: Texture2D = bake.peek(r["recipe"] as StringName, r["style"] as StringName, 10000, r["size"] as int)
		_check(tex != null, "texture for %s" % r["tag"])
		if tex == null:
			continue
		var px: Vector2i = ViewIconBake.SIZES[r["size"] as int]
		var img: Image = tex.get_image()
		_check(img.get_width() == px.x and img.get_height() == px.y, "size of %s" % r["tag"])
		for c: Vector2i in [Vector2i(0, 0), Vector2i(px.x - 1, 0), Vector2i(0, px.y - 1), Vector2i(px.x - 1, px.y - 1)]:
			_check(img.get_pixelv(c).a == 0.0, "corner alpha 0 at %s of %s (%.3f)" % [c, r["tag"], img.get_pixelv(c).a])
		var lo: Vector2i = Vector2i(px.x, px.y)
		var hi: Vector2i = Vector2i(-1, -1)
		var solid: int = 0
		for y: int in px.y:
			for x: int in px.x:
				var a: float = img.get_pixel(x, y).a
				if a > 0.5:
					solid += 1
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		var cover: float = maxf(float(hi.x - lo.x) / float(px.x), float(hi.y - lo.y) / float(px.y))
		_check(solid > px.x * px.y / 40, "%s has a body (%d px)" % [r["tag"], solid])
		_check(cover > 0.5 and cover <= 1.0, "%s is framed to fill the icon (%.2f)" % [r["tag"], cover])
		_check(lo.x > 0 and lo.y > 0 and hi.x < px.x - 1 and hi.y < px.y - 1, "%s is not clipped by the frame" % r["tag"])
	bake.flush()
	var files: int = 0
	var da: DirAccess = DirAccess.open(bake.cache_dir)
	if da != null:
		for f: String in da.get_files():
			if f.ends_with(".png"):
				files += 1
	print("RESULT %d PNG files in the cache" % files)
	_check(files >= reqs.size() - 4, "PNG files written (%d)" % files)
	# second pass from the disk cache
	bake.clear_memory()
	var bakes0: int = int(bake.stats["bakes"])
	var hits0: int = int(bake.stats["hits"])
	var sum0: int = int(bake.stats["hit_us_sum"])
	var t1: int = Time.get_ticks_usec()
	bake.prewarm(reqs)
	await bake.wait_idle()
	var warm_ms: float = float(Time.get_ticks_usec() - t1) / 1000.0
	var hits: int = int(bake.stats["hits"]) - hits0
	var avg_us: float = float(int(bake.stats["hit_us_sum"]) - sum0) / float(maxi(hits, 1))
	print("RESULT cache pass: %d hits, %.1f ms total, avg %.0f us per icon, max %d us, bakes=%d" % [hits, warm_ms, avg_us, bake.stats["hit_us_max"], int(bake.stats["bakes"]) - bakes0])
	_check(int(bake.stats["bakes"]) == bakes0, "the second pass rendered nothing")
	_check(hits >= reqs.size() - 4, "second pass served from disk")
	_check(avg_us < 2000.0, "cache hit under 2 ms per icon (%.0f us)" % avg_us)
	print("RESULT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
