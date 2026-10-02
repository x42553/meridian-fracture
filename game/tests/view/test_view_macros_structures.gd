extends RefCounted
## VIEW-M4 acceptance: the structure / ship / landmark macros (ViewMacrosStructures + ViewMacrosLandmarks). Every macro runs with
## its signature defaults, emits geometry inside its documented bounding box, leaves no part / tier / transform open, declares
## the sockets it promises, and the interpreter dispatches to it (`{"call": name}`). Bounding boxes are upper bounds derived from
## the macro's arguments (footprint (fw*3-0.5) m, spec 5.9 height caps), not snapshots.

const Pt := ViewMeshBuilder.Part
## name -> [x0, x1, y0, y1, z0, z1] the default-argument output must stay inside (metres, macro-local frame).
const BOX: Dictionary = {
	"foundation": [-4.3, 4.3, -1.25, 0.55, -4.3, 4.3], "wall_block": [-2.2, 2.2, -1.55, 1.65, -2.2, 2.2],
	"roller_door": [-3.85, 3.85, 0.0, 3.65, -0.55, 0.35], "window_strip": [-1.95, 1.95, -0.4, 0.4, -0.1, 0.1],
	"stack": [-0.55, 0.55, 0.0, 3.2, -0.55, 0.55], "silo": [-0.95, 0.95, 0.0, 5.8, -0.95, 0.95],
	"silo_cluster": [-2.5, 2.5, 0.0, 5.8, -2.5, 2.5], "crane": [-1.6, 5.1, 0.0, 5.7, -0.6, 0.6],
	"pad": [-1.25, 1.25, 0.0, 0.1, -1.25, 1.25], "dome_shell": [-2.15, 2.15, 0.0, 2.05, -2.15, 2.15],
	"pylon_ring": [-3.3, 3.3, 0.0, 2.7, -3.3, 3.3], "launch_rail": [-0.8, 0.8, -0.45, 2.1, -3.3, 0.8],
	"turret_base": [-1.1, 1.1, 0.0, 1.0, -1.1, 1.1], "pennant": [-0.1, 0.7, 0.0, 2.1, -0.1, 0.1],
	"beacon": [-0.1, 0.1, 0.0, 0.2, -0.1, 0.1], "roof_plate": [-1.0, 1.0, -0.05, 0.08, -0.9, 0.9],
	"conveyor": [-0.4, 0.4, -0.15, 0.25, 0.0, 3.05], "funnel": [-0.95, 0.95, 0.0, 0.95, -0.95, 0.95],
	"lattice": [-0.9, 0.9, -0.05, 8.1, -0.9, 0.9], "hull_ship": [-1.05, 1.05, -0.45, 0.9, -2.55, 2.55],
	"superstructure": [-0.8, 0.8, 0.0, 1.95, -1.1, 1.1], "vls": [-0.45, 0.45, 0.0, 0.12, -0.8, 0.8],
	"ship_turret": [-0.4, 0.4, 0.0, 0.55, -1.75, 0.4], "flight_deck": [-1.6, 1.6, 0.0, 0.25, -4.05, 4.05],
	"deck_drones": [-0.85, 0.85, 0.0, 0.2, -0.55, 0.55], "sail": [-0.95, 0.95, 0.0, 1.85, -0.95, 0.95],
}
const SW_BOX: Array = [-5.9, 5.9, 0.1, 14.0, -5.9, 5.9]  ## superweapon: plinth 11.5 m, landmark <= 14 m
const ADV_BOX: Array = [-3.1, 3.1, 0.1, 6.0, -3.1, 3.1]  ## advanced defence: plinth 5.5 m, landmark <= 6 m

var _pal: Dictionary = {}


func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false
	ViewExpr.quiet = false


func _palette() -> Dictionary:
	if _pal.is_empty():
		for k: Variant in ViewRecipeInterpreter.DEFAULT_PALETTE:
			_pal[k] = Color(str(ViewRecipeInterpreter.DEFAULT_PALETTE[k]))
	return _pal


func _default_args(name: String) -> Dictionary:
	var sig: Dictionary = ViewMacrosStructures.signature(name)
	var args: Dictionary = {}
	for an: Variant in sig:
		var spec: Array = sig[an] as Array
		var dv: Variant = spec[1]
		match spec[0] as String:
			"n", "s":
				args[an] = dv
			"v":
				args[an] = Vector3((dv as Array)[0] as float, (dv as Array)[1] as float, (dv as Array)[2] as float)
			"w":
				args[an] = Vector2((dv as Array)[0] as float, (dv as Array)[1] as float)
			"c":
				args[an] = _colour(dv as String)
	return args


## Palette key, "#rrggbb" or "mix(a,b,t)" (the forms macro signatures use as defaults).
func _colour(s: String) -> Color:
	var pal: Dictionary = _palette()
	if pal.has(s):
		return pal[s] as Color
	if s.begins_with("mix("):
		var parts: PackedStringArray = s.substr(4, s.length() - 5).split(",")
		return _colour(parts[0]).lerp(_colour(parts[1]), parts[2].to_float())
	return Color(s)


func _inside(bb: AABB, box: Array, tol: float = 0.02) -> bool:
	return bb.position.x >= (box[0] as float) - tol and bb.end.x <= (box[1] as float) + tol \
		and bb.position.y >= (box[2] as float) - tol and bb.end.y <= (box[3] as float) + tol \
		and bb.position.z >= (box[4] as float) - tol and bb.end.z <= (box[5] as float) + tol


func test_all_macros_are_registered_and_dispatched(t: TestCtx) -> void:
	var names: PackedStringArray = ViewMacrosStructures.macro_names()
	t.eq(names.size(), 26 + 16, "19 structure + 7 ship macros, 8 superweapons, 8 defences")
	for n: String in names:
		t.check(not ViewRecipeMacros.signature(n).is_empty(), "%s is reachable through ViewRecipeMacros.signature" % n)
		t.check(not ViewRecipeMacros.macro_names().has(n), "%s is not duplicated in ViewRecipeMacros" % n)
	t.eq(ViewRecipeMacros.run("nope", ViewMeshBuilder.new(), {}, _palette()), "unknown macro 'nope'", "unknown names still fail")


func test_every_macro_emits_inside_its_box_and_keeps_state_balanced(t: TestCtx) -> void:
	var pal: Dictionary = _palette()
	for n: String in ViewMacrosStructures.macro_names():
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		var args: Dictionary = _default_args(n)
		var err: String = ViewMacrosStructures.run(n, b, args, pal)
		t.eq(err, "", "macro %s runs" % n)
		t.gt(b.vertex_count(), 0, "macro %s emits geometry" % n)
		t.eq(b.part, Pt.STATIC, "macro %s leaves no part open" % n)
		t.eq(b.tier, 0, "macro %s restores tier 0" % n)
		t.eq(b.ao, 1.0, "macro %s restores ao" % n)
		b.socket(&"probe", Vector3.ZERO, Vector3.UP)  # a leaked push() would move this
		b.build_arrays()
		var info: ViewModelInfo = b.info()
		var sk: ViewModelInfo.ViewSocket = info.sockets[&"probe"] as ViewModelInfo.ViewSocket
		t.near(sk.pos.length(), 0.0, 0.0001, "macro %s keeps the transform stack balanced" % n)
		var box: Array = []
		if BOX.has(n):
			box = BOX[n] as Array
		elif n.begins_with("sw_"):
			box = SW_BOX
		else:
			box = ADV_BOX
		var bb: AABB = info.rest_aabb
		t.check(_inside(bb, box), "macro %s inside its bounding box: got x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % [n, bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z])
		t.check(info.tris.x <= 9000, "macro %s stays cheap (%d tris)" % [n, info.tris.x])


func test_macros_honour_the_center_argument(t: TestCtx) -> void:
	# landmarks and structure macros with a `center` move as a whole, pivots included
	for n: String in ["sw_halo_tower", "adv_bulwark_cannon", "silo", "dome_shell", "wall_block"]:
		var a0: Dictionary = _default_args(n)
		var a1: Dictionary = _default_args(n)
		a1["center"] = Vector3(3.0, 0.0, -2.0)
		var b0: ViewMeshBuilder = ViewMeshBuilder.new()
		var b1: ViewMeshBuilder = ViewMeshBuilder.new()
		ViewMacrosStructures.run(n, b0, a0, _palette())
		ViewMacrosStructures.run(n, b1, a1, _palette())
		b0.build_arrays()
		b1.build_arrays()
		var d: Vector3 = b1.info().rest_aabb.position - b0.info().rest_aabb.position
		t.near(d.x, 3.0, 0.05, "%s shifts x" % n)
		t.near(d.z, -2.0, 0.05, "%s shifts z" % n)


func test_sockets_and_parts_promised_by_the_macros(t: TestCtx) -> void:
	var pal: Dictionary = _palette()
	var cases: Array = [
		["launch_rail", &"muzzle0_0", Pt.BARREL], ["ship_turret", &"muzzle0_0", Pt.BARREL], ["adv_bulwark_cannon", &"muzzle0_0", Pt.BARREL],
		["adv_lance_rail", &"muzzle0_0", Pt.BARREL], ["adv_citadel_mortar", &"muzzle0_0", Pt.BARREL], ["adv_sea_spear", &"muzzle0_0", Pt.BARREL],
		["adv_dragon_tooth", &"muzzle0_0", Pt.BARREL], ["adv_forge_cannon", &"muzzle0_0", Pt.BARREL], ["adv_bastion_tower", &"muzzle0_1", Pt.BARREL],
		["adv_sunwall", &"muzzle0_0", Pt.TURRET], ["sw_long_barrel", &"muzzle0_0", Pt.BARREL],
	]
	for c: Array in cases:
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		ViewMacrosStructures.run(c[0] as String, b, _default_args(c[0] as String), pal)
		b.build_arrays()
		var info: ViewModelInfo = b.info()
		t.check(info.has_socket(c[1] as StringName), "%s declares %s" % [c[0], c[1]])
		if info.has_socket(c[1] as StringName):
			t.eq((info.sockets[c[1]] as ViewModelInfo.ViewSocket).part, c[2] as int, "%s socket rides its weapon part" % c[0])
	# a mount index moves the weapon parts to TURRET1 / BARREL1
	var a: Dictionary = _default_args("ship_turret")
	a["mount"] = 1.0
	a["barrels"] = 3.0
	var b2: ViewMeshBuilder = ViewMeshBuilder.new()
	ViewMacrosStructures.run("ship_turret", b2, a, pal)
	b2.build_arrays()
	t.check(b2.info().has_part(Pt.TURRET1) and b2.info().has_part(Pt.BARREL1), "mount 1 uses TURRET1 / BARREL1")
	t.check(b2.info().has_socket(&"muzzle1_2"), "three barrels give muzzle1_0..2")
	# animated structure parts
	var animated: Dictionary = {"roller_door": Pt.DOOR, "crane": Pt.SLIDE_Y, "beacon": Pt.BLINK, "flight_deck": Pt.SLIDE_Y, "sail": Pt.RADAR,
		"sw_billboard": Pt.SLIDE_Y, "sw_gantry_silo": Pt.SLIDE_Z, "sw_three_masts": Pt.RADAR, "sw_sunflower": Pt.TURRET, "adv_bastion_tower": Pt.RADAR}
	for n: String in animated:
		var b3: ViewMeshBuilder = ViewMeshBuilder.new()
		ViewMacrosStructures.run(n, b3, _default_args(n), pal)
		b3.build_arrays()
		t.check(b3.info().has_part(animated[n] as int), "%s carries part kind %d" % [n, animated[n]])


func test_roller_door_slats_stack_inside_the_header(t: TestCtx) -> void:
	# open door (aux.y = 1): every slat ends between the opening top (h) and the facade top (wall_h), behind the lintel
	var a: Dictionary = _default_args("roller_door")
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	ViewMacrosStructures.run("roller_door", b, a, _palette())
	b.build_arrays()
	var bb: AABB = b.info().rest_aabb
	t.check(bb.end.y <= 3.6 + 0.15, "the swept bounding box (slats travel) stays under the facade top: %.2f" % bb.end.y)
	# slats: the rest position of each is inside the opening (y 0..h); travel puts them above h
	t.check(b.info().has_part(Pt.DOOR), "door slats are DOOR parts")


func test_hull_ship_bows_and_errors(t: TestCtx) -> void:
	for bow: String in ["sharp", "blunt", "round"]:
		var a: Dictionary = _default_args("hull_ship")
		a["bow"] = bow
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		t.eq(ViewMacrosStructures.run("hull_ship", b, a, _palette()), "", "bow " + bow)
		b.build_arrays()
		t.check(b.info().rest_aabb.size.z <= 5.01 and b.info().rest_aabb.size.z >= 4.9, "bow %s spans the requested length" % bow)
	var bad: Dictionary = _default_args("hull_ship")
	bad["bow"] = "spoon"
	t.check(ViewMacrosStructures.run("hull_ship", ViewMeshBuilder.new(), bad, _palette()).contains("unknown bow"), "unknown bow is an error")


func test_landmarks_carry_a_team_surface(t: TestCtx) -> void:
	for n: String in ViewMacrosStructures.macro_names():
		if not (n.begins_with("sw_") or n.begins_with("adv_")) and n not in ["roof_plate", "pennant"]:
			continue
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		ViewMacrosStructures.run(n, b, _default_args(n), _palette())
		var arrays: Dictionary = b.build_arrays()
		var cols: PackedColorArray = (arrays["arrays"] as Array)[Mesh.ARRAY_COLOR] as PackedColorArray
		var team: int = 0
		for c: Color in cols:
			if c.a > 0.5:
				team += 1
		t.gt(team, 8, "%s has a team-coloured surface" % n)


func test_macros_through_the_interpreter(t: TestCtx) -> void:
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.add_archetype({"schema": "meridian.archetype/1", "id": "t_s", "size_class": "structure", "ops": [
		{"call": "foundation", "args": {"fw": 2, "fh": 2}},
		{"call": "wall_block", "args": {"center": [0, 1.5, 0], "size": [4, 3, 3.5]}},
		{"call": "roller_door", "args": {"center": [0, 0, 1.75], "w": 2.0, "h": 2.2, "slats": 6, "wall_l": 2.0, "wall_r": 2.0, "wall_h": 3.0}},
		{"call": "hull_ship", "args": {"bow": "blunt"}},
	]}, "test")
	bk.add_recipe({"schema": "meridian.recipe/1", "id": "t.s", "archetype": "t_s"}, "test")
	bk.link()
	var ip: ViewRecipeInterpreter = ViewRecipeInterpreter.new()
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	ip.run(bk.recipe(&"t.s"), bk.style(&""), b)
	t.eq(ip.error, "", "structure macros run through the interpreter")
	# argument errors carry the op path
	bk.add_archetype({"schema": "meridian.archetype/1", "id": "t_e", "size_class": "structure", "ops": [{"call": "roller_door", "args": {"bogus": 1}}]}, "test")
	bk.add_recipe({"schema": "meridian.recipe/1", "id": "t.e", "archetype": "t_e"}, "test")
	bk.link()
	var ip2: ViewRecipeInterpreter = ViewRecipeInterpreter.new()
	ip2.run(bk.recipe(&"t.e"), bk.style(&""), ViewMeshBuilder.new())
	t.check(ip2.error.contains("t.e/ops[0]") and ip2.error.contains("no argument 'bogus'"), "bad argument names are reported with the op path: %s" % ip2.error)
