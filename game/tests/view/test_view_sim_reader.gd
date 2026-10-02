extends RefCounted
## VIEW-S1: ViewSimReader defaults without components, values with fixture components, no allocation, and the seam
## discipline (no other view file reads Def* fields or component internals).


func test_defaults_without_components(t: TestCtx) -> void:
	var e: SimEntity = ViewFixtureWorld.bare_entity()
	var out: PackedInt32Array = PackedInt32Array()
	t.eq(ViewSimReader.turret_rel_bat(e, 0), -1, "turret_rel_bat")
	t.eq(ViewSimReader.mount_count(e), 0, "mount_count")
	t.eq(ViewSimReader.collector_fill_permille(e), -1, "collector fill")
	t.eq(ViewSimReader.zone_charges(e), -1, "zone charges")
	t.eq(ViewSimReader.capture_progress_permille(e), -1, "capture")
	t.check_false(ViewSimReader.rally_of(e, out), "no rally")
	t.eq(ViewSimReader.turret_rel_bat(null, 0), -1, "null entity")
	t.eq(ViewSimReader.mount_count(null), 0, "null mount count")


func test_values_from_components(t: TestCtx) -> void:
	var e: SimEntity = ViewFixtureWorld.bare_entity()
	ViewFixtureWorld.with_combat(e, PackedInt32Array([512, 3900]))
	t.eq(ViewSimReader.mount_count(e), 2, "two mounts")
	t.eq(ViewSimReader.turret_rel_bat(e, 0), 512, "mount 0")
	t.eq(ViewSimReader.turret_rel_bat(e, 1), 3900, "mount 1")
	t.eq(ViewSimReader.turret_rel_bat(e, 2), -1, "no mount 2")
	t.eq(ViewSimReader.turret_rel_bat(e, -1), -1, "negative mount")
	ViewFixtureWorld.with_econ(e, 300, 2500)
	ViewSimReader.default_collector_capacity = 0
	t.eq(ViewSimReader.collector_fill_permille(e, 600), 500, "half full")
	t.eq(ViewSimReader.collector_fill_permille(e, 0), -1, "unknown capacity")
	t.eq(ViewSimReader.capture_progress_permille(e), 250, "capture permille")
	ViewSimReader.default_collector_capacity = 1200
	t.eq(ViewSimReader.collector_fill_permille(e), 250, "default capacity")
	ViewSimReader.default_collector_capacity = 0
	var s: SimEntity = ViewFixtureWorld.bare_entity(SimEntity.Kind.STRUCTURE)
	ViewFixtureWorld.with_rally(s, 1000, 2000, 5)
	var out: PackedInt32Array = PackedInt32Array()
	t.check(ViewSimReader.rally_of(s, out), "rally on")
	t.eq(out, PackedInt32Array([1000, 2000, 5]), "rally payload")


func test_weapon_ranges_use_combat_queries(t: TestCtx) -> void:
	var w: SimWorld = ViewFixtureWorld.make_world()
	t.not_null(w, "real world")
	if w == null:
		return
	var tank: SimEntity = ViewFixtureWorld.spawn_unit(w, ViewFixtureWorld.UNIT_TANK, 0, 20, 20)
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = ViewSimReader.weapon_ranges(w, tank, out)
	t.eq(out.size(), n * 2, "two ints per mount")
	t.eq(ViewSimReader.weapon_ranges(null, tank, out), n, "null world keeps the mount count")


func test_no_allocation(t: TestCtx) -> void:
	var e: SimEntity = ViewFixtureWorld.bare_entity()
	ViewFixtureWorld.with_combat(e, PackedInt32Array([1, 2]))
	ViewFixtureWorld.with_econ(e, 10, 100)
	ViewFixtureWorld.with_rally(e, 1, 2, 3)
	var out: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var acc: int = 0
	for i: int in 200000:
		acc += ViewSimReader.turret_rel_bat(e, i & 1) + ViewSimReader.mount_count(e) + ViewSimReader.collector_fill_permille(e, 100)
		acc += ViewSimReader.capture_progress_permille(e) + (1 if ViewSimReader.rally_of(e, out) else 0) + ViewSimReader.zone_charges(e)
	var after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	t.check(acc != 0, "used")
	t.check(absf(after - before) < 8.0, "object count flat (%d -> %d)" % [int(before), int(after)])


## No other view file reads Def* fields or component internals: grep test over res://src/view.
func test_seam_discipline(t: TestCtx) -> void:
	var files: Array[String] = []
	_collect("res://src/view", files)
	var def_re: RegEx = RegEx.new()
	def_re.compile("\\b(Def(Unit|Structure|Zone|Neutral|Faction|Roster|WeaponArch|WeaponSlot)|GameData)\\b")
	var comp_re: RegEx = RegEx.new()
	comp_re.compile("\\b(e|ent|entity|w|world)\\.(combat|econ|abil|prod|move|air|carrier|cargo|summon|stats|vis)\\b")
	var bad: PackedStringArray = PackedStringArray()
	for f: String in files:
		var base: String = f.get_file()
		var src: String = FileAccess.get_file_as_string(f)
		if base != "view_def_adapter.gd" and def_re.search(src) != null:
			# a type mention in a doc comment is fine; code lines are not
			for line: String in src.split("\n"):
				var s: String = _code_of(line)
				if def_re.search(s) != null:
					bad.append("%s: %s" % [base, s.left(90)])
					break
		if base != "view_sim_reader.gd" and base != "view_def_adapter.gd":
			for line: String in src.split("\n"):
				var s2: String = _code_of(line)
				if comp_re.search(s2) != null:
					bad.append("%s: %s" % [base, s2.left(90)])
					break
	t.eq(bad, PackedStringArray(), "only ViewDefAdapter reads Def*, only ViewSimReader reads components")


## The code part of a line (comment stripped, strings are not a concern for these patterns).
static func _code_of(line: String) -> String:
	var p: int = line.find("#")
	return (line.substr(0, p) if p >= 0 else line).strip_edges()


static func _collect(dir: String, out: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d: String in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
