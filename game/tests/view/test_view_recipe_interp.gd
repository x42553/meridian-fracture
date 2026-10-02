extends RefCounted
## VIEW-M2 acceptance: recipe interpreter (every op, slots, error paths with op text), builder (placeholder, threaded == single
## thread content hash), macros smoke, veh_tank / inf_squad proofs from the real archetype files.

const Pt := ViewMeshBuilder.Part
const A_ALL: Dictionary = {
	"schema": "meridian.archetype/1", "id": "t_all", "size_class": "light",
	"defaults": {"n": 3, "w": 1.0, "kind": "b", "flag": true},
	"derive": {"h": "w*0.5"},
	"slots": {"extra": [["box", [0, 3, 0], [0.2, 0.2, 0.2], 0]]},
	"ops": [
		["brush", "base"], ["box", [0, "h", 0], ["w", 1, 1], 0.05],
		{"for": "i", "n": "n", "do": [["box", ["i*2", 0.5, 0], [0.5, 0.5, 0.5], 0]]},
		{"if": "flag", "then": [["cyl", [0, 0, 0], [0, 1, 0], 0.2, 8]], "else": [["box", [0, 0, 0], [1, 1, 1]]]},
		{"switch": "kind", "cases": {"a": [["box", [0, 0, 5], [1, 1, 1]]], "b": [["dome", [0, 0, 0], [0, 1, 0], 0.5, 0.5, 8, 2]]}},
		{"mirror_x": [["box", [1, 0.5, 0], [0.3, 0.3, 0.3], 0]]},
		{"push": {"pos": [0, 1, 0], "euler": [0, 45, 0]}, "do": [["box", [0, 0, 0], [0.2, 0.2, 0.2], 0]]},
		{"part": {"kind": "turret", "pivot": [0, 1, 0]}, "do": [["box", [0, 1, 0], [0.3, 0.3, 0.3], 0]]},
		{"call": "hatch", "args": {"c": [0, 1, 0]}},
		{"slot": "extra"},
		{"let": {"q": "n*2"}}, ["box", ["q", 0, 0], [0.1, 0.1, 0.1], 0],
		["socket", "s0", [0, 1, 0], [0, 0, -1]], ["meta", "hover", 2.5],
	],
}

func teardown(_t: TestCtx) -> void:
	Log.sink = Callable()
	Log.quiet = false
	ViewExpr.quiet = false


func _book(arch: Dictionary, params: Dictionary = {}, rslots: Dictionary = {}, styles: Dictionary = {}, after: Array = []) -> ViewRecipeBook:
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.add_archetype(arch, "test")
	bk.add_recipe({"schema": "meridian.recipe/1", "id": "t.r", "archetype": arch["id"], "params": params, "slots": rslots, "ops_after": after}, "test")
	if not styles.is_empty():
		bk.add_styles({"schema": "meridian.styles/1", "styles": styles}, "test")
	bk.link()
	return bk


func _run(bk: ViewRecipeBook, style_id: StringName = &"") -> Array:
	var b: ViewMeshBuilder = ViewMeshBuilder.new()
	b.seed_rng(7)
	var ip: ViewRecipeInterpreter = ViewRecipeInterpreter.new()
	ip.seed_base = 7
	ip.run(bk.recipe(&"t.r"), bk.style(style_id), b)
	return [ip, b]


func test_every_op_matches_direct_builder_calls(t: TestCtx) -> void:
	var res: Array = _run(_book(A_ALL))
	var ip: ViewRecipeInterpreter = res[0] as ViewRecipeInterpreter
	var b: ViewMeshBuilder = res[1] as ViewMeshBuilder
	t.eq(ip.error, "", "interpreter error")
	var d: ViewMeshBuilder = ViewMeshBuilder.new()
	d.seed_rng(7)
	d.brush(Color("#6b7280"))
	d.box(Vector3(0, 0.5, 0), Vector3(1, 1, 1), 0.05)
	for i in 3:
		d.box(Vector3(float(i) * 2.0, 0.5, 0), Vector3(0.5, 0.5, 0.5), 0.0)
	d.cylinder(Vector3.ZERO, Vector3(0, 1, 0), 0.2, 8)
	d.dome(Vector3.ZERO, Vector3(0, 1, 0), 0.5, 0.5, 8, 2)
	var m: PackedInt32Array = d.mark()
	d.box(Vector3(1, 0.5, 0), Vector3(0.3, 0.3, 0.3), 0.0)
	d.mirror_x(m)
	d.push(ViewMeshBuilder.xf(Vector3(0, 1, 0), Vector3(0, 45, 0)))
	d.box(Vector3.ZERO, Vector3(0.2, 0.2, 0.2), 0.0)
	d.pop()
	d.set_part(Pt.TURRET, Vector3(0, 1, 0))
	d.box(Vector3(0, 1, 0), Vector3(0.3, 0.3, 0.3), 0.0)
	d.clear_part()
	var pal: Dictionary = {"c": Vector3(0, 1, 0)}
	ViewRecipeMacros.run("hatch", d, {"c": pal["c"], "r": 0.15, "body": Color("#d9d4c5"), "ring": Color("#e07b1a")}, {})
	d.brush(Color("#6b7280"))  # the interpreter restores the brush after a macro call
	d.box(Vector3(0, 3, 0), Vector3(0.2, 0.2, 0.2), 0.0)
	d.box(Vector3(6, 0, 0), Vector3(0.1, 0.1, 0.1), 0.0)
	t.eq(b.vertex_count(), d.vertex_count(), "vertex count equals the hand-written build")
	t.eq(b.triangle_count(), d.triangle_count(), "triangle count")
	d.socket(&"s0", Vector3(0, 1, 0), Vector3(0, 0, -1))
	var da: Dictionary = d.build_arrays()
	var ba: Dictionary = b.build_arrays()
	t.eq(b.info().content_hash, d.info().content_hash, "content hash equals the hand-written build")
	t.check(da.size() > 0 and ba.size() > 0, "arrays")
	t.check(b.info().has_part(Pt.TURRET), "turret part present")
	t.check(b.info().has_socket(&"s0"), "socket recorded")
	t.near(b.info().hover, 2.5, 0.0001, "meta hover written to the info")
	t.eq(ip.prims, 12, "executed primitive count")


func test_slot_precedence_recipe_over_style_over_archetype(t: TestCtx) -> void:
	var arch: Dictionary = {"schema": "meridian.archetype/1", "id": "t_slot", "slots": {"s": [["box", [0, 0, 0], [1, 1, 1], 0]]},
		"ops": [{"slot": "s"}, {"slot": "missing"}]}
	var n_arch: int = ((_run(_book(arch))[1]) as ViewMeshBuilder).vertex_count()
	t.gt(n_arch, 0, "archetype slot used")
	var style: Dictionary = {"st": {"slots": {"s": [["box", [0, 0, 0], [1, 1, 1], 0], ["box", [0, 2, 0], [1, 1, 1], 0]]}}}
	var n_style: int = ((_run(_book(arch, {}, {}, style), &"st")[1]) as ViewMeshBuilder).vertex_count()
	t.eq(n_style, n_arch * 2, "style slot wins over the archetype slot")
	var rs: Dictionary = {"s": [["box", [0, 0, 0], [1, 1, 1], 0], ["box", [0, 2, 0], [1, 1, 1], 0], ["box", [0, 4, 0], [1, 1, 1], 0]]}
	var n_rec: int = ((_run(_book(arch, {}, rs, style), &"st")[1]) as ViewMeshBuilder).vertex_count()
	t.eq(n_rec, n_arch * 3, "recipe slot wins over the style slot")


func _err_of(ops: Array, params: Dictionary = {}, defaults: Dictionary = {}) -> String:
	var arch: Dictionary = {"schema": "meridian.archetype/1", "id": "t_err", "defaults": defaults, "ops": ops}
	return (_run(_book(arch, params))[0] as ViewRecipeInterpreter).error


func test_error_paths_carry_the_op_path(t: TestCtx) -> void:
	var e: String = _err_of([["brush", "base"], ["box", [0, 0, 0], [1, 1, 1]], ["tier", 0],
		{"for": "i", "n": 2, "do": [["tier", 0], ["box", [0, "nosuch*2", 0], [1, 1, 1]]]}])
	t.eq(e.split(":")[0], "t.r/ops[3]/for[1]/box", "path of a bad expression inside a loop: " + e)
	t.check(e.contains("nosuch"), "message names the identifier")
	t.check(_err_of([["frobnicate", 1]]).begins_with("t.r/ops[0]/frobnicate:"), "unknown op")
	t.check(_err_of([["box", [0, 0], [1, 1, 1]]]).begins_with("t.r/ops[0]/box:"), "vector of the wrong length")
	t.check(_err_of([{"call": "nosuchmacro"}]).contains("unknown macro"), "unknown macro")
	t.check(_err_of([{"call": "hatch", "args": {"bogus": 1}}]).contains("no argument 'bogus'"), "unknown macro argument")
	t.check(_err_of([{"if": "1", "then": [], "bogus": 1}]).contains("unexpected key"), "unexpected block key")
	t.check(_err_of([["brush", "base"], ["brush", "nosuchcolour"]]).begins_with("t.r/ops[1]/brush:"), "unknown colour")
	t.check(_err_of([], {"zz": 1}).begins_with("t.r/params/zz: unknown parameter"), "unknown recipe parameter")
	t.check(_err_of([], {"n": "abc"}, {"n": 3}).contains("params/n"), "a string is not a number for a numeric param unless it compiles")
	t.check(_err_of([], {"n": true}, {"n": 3}).contains("expected a number"), "wrong parameter type")


func test_loop_and_budget_limits(t: TestCtx) -> void:
	t.check(_err_of([{"for": "i", "n": 65, "do": []}]).contains("outside 0..64"), "for n = 65 rejected at compile time")
	t.check(_err_of([{"for": "i", "n": "n", "do": []}], {"n": 65}, {"n": 3}).contains("outside 0..64"), "for n = 65 rejected at run time")
	var nest4: Array = [{"for": "a", "n": 1, "do": [{"for": "b", "n": 1, "do": [{"for": "c", "n": 1, "do": [{"for": "d", "n": 1, "do": []}]}]}]}]
	t.check(_err_of(nest4).contains("nesting exceeds 3"), "for nesting > 3 rejected")
	var deep: Array = [["tier", 0]]
	for i in 9:
		deep = [{"if": "1", "then": deep}]
	t.check(_err_of(deep).contains("depth exceeds 8"), "op-list depth > 8 rejected")
	var cap: Array = [{"for": "i", "n": 64, "do": [{"for": "j", "n": 64, "do": [["box", [0, 0, 0], [0.1, 0.1, 0.1], 0]]}]}]
	t.check(_err_of(cap).contains("executed-primitive cap 4000"), "4000-primitive cap")


func test_colour_forms_and_expression_colours(t: TestCtx) -> void:
	var arch: Dictionary = {"schema": "meridian.archetype/1", "id": "t_col", "defaults": {"k": 1},
		"ops": [["brush", "base*0.5"], ["box", [0, 0, 0], [1, 1, 1]], ["brush", "mix(base,acc,0.5)"], ["box", [2, 0, 0], [1, 1, 1]],
			["brush", "#102030"], ["box", [4, 0, 0], [1, 1, 1]], ["brush", "k == 1 ? 'sec' : 'acc'"], ["box", [6, 0, 0], [1, 1, 1]], ["brush", "1 == 1 ? 'nope' : 'acc'"]]}
	var res: Array = _run(_book(arch))
	t.check((res[0] as ViewRecipeInterpreter).error.begins_with("t.r/ops[8]/brush: expression result 'nope' is not a colour"), "bad expression colour reported at run time: " + (res[0] as ViewRecipeInterpreter).error)


func test_book_styles_and_lookup(t: TestCtx) -> void:
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.add_styles({"schema": "meridian.styles/1", "styles": {
		"napc": {"palette": {"base": "#4d592e", "acc": "#ed5e0f"}, "kit": {"len": 3.5}, "slots": {"a": [], "b": [["tier", 1]]}},
		"napc.canada": {"extends": "napc", "palette": {"acc": "#e8e8e8"}, "slots": {"a": [["tier", 0]]}},
		"neutral": {}}}, "test")
	bk.link()
	var s: Dictionary = bk.style(&"napc.canada")
	t.eq(s["palette"]["base"], "#4d592e", "parent palette inherited")
	t.eq(s["palette"]["acc"], "#e8e8e8", "child overrides")
	t.eq((s["slots"] as Dictionary).size(), 2, "slots merged per name")
	t.eq(((s["slots"] as Dictionary)["a"] as Array).size(), 1, "child slot replaces the parent's")
	t.eq(bk.style_for_roster("roster.napc.canada"), &"napc.canada", "roster -> subfaction style")
	t.eq(bk.style_for_roster("roster.napc.usa"), &"napc", "unknown subfaction falls back to the faction")
	t.eq(bk.style_for_roster("roster.xyz.q"), &"neutral", "unknown faction -> neutral")
	t.eq(bk.style_for_def("unit.napc.guardian_tank", "roster.napc.canada"), &"napc.canada", "faction unit of the owner's faction -> roster style (VQ2A)")
	t.eq(bk.style_for_def("unit.napc.guardian_tank", "roster.napc.usa"), &"napc", "roster without a style of its own -> faction style")
	t.eq(bk.style_for_def("unit.napc.guardian_tank", "roster.nec.eurocorps"), &"napc", "foreign owner -> the unit's faction style")
	t.eq(bk.style_for_def("structure.shared.factory", "roster.napc.canada"), &"napc.canada", "shared def -> owner style")
	t.eq(bk.style_for_def("neutral.field_hospital", "roster.napc.canada"), &"neutral", "neutral def")
	bk.add_styles({"schema": "meridian.styles/1", "styles": {"loop_a": {"extends": "loop_b"}, "loop_b": {"extends": "loop_a"}}}, "test")
	bk.link()
	t.check(bk.errors().size() > 0, "an extends cycle is an error")


func test_placeholder_for_missing_recipe_warns_once(t: TestCtx) -> void:
	var warns: Array = []
	Log.sink = func(level: int, _tag: String, msg: String) -> void:
		if level == Log.Level.WARN:
			warns.append(msg)
	var mb: ViewModelBuilder = ViewModelBuilder.new()
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.link()
	mb.setup(bk, ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH))
	var m: ViewModel = mb.get_model(&"unit.nope.tank", &"napc")
	t.check(m.placeholder and m.mesh != null and m.info.verts > 0, "placeholder box built")
	t.check(m.info.height > 1.0, "placeholder has a size")
	mb.get_model(&"unit.nope.tank", &"nec")
	mb.get_model(&"unit.nope.tank", &"napc")
	t.eq(warns.size(), 1, "exactly one Log.warn for the missing recipe: %s" % [warns])
	t.check(mb.get_model(&"unit.nope.tank", &"napc") == m, "cached")


func test_failed_recipe_gets_placeholder_and_logs_error_with_path(t: TestCtx) -> void:
	var errs: Array = []
	Log.sink = func(level: int, _tag: String, msg: String) -> void:
		if level == Log.Level.ERROR:
			errs.append(msg)
	var arch: Dictionary = {"schema": "meridian.archetype/1", "id": "t_bad", "size_class": "heavy", "ops": [["box", [0, 0, 0], ["oops", 1, 1]]]}
	var bk: ViewRecipeBook = _book(arch)
	var mb: ViewModelBuilder = ViewModelBuilder.new()
	mb.setup(bk, null)
	var m: ViewModel = mb.get_model(&"t.r", &"neutral")
	t.check(m.placeholder and m.error.begins_with("t.r/ops[0]/box"), "placeholder with the op-path error: " + m.error)
	t.eq(errs.size(), 1, "one Log.error")
	t.gt(m.info.radius, 1.5, "heavy size class placeholder")


func _real_book() -> ViewRecipeBook:
	var bk: ViewRecipeBook = ViewRecipeBook.new()
	bk.load_all()
	for id: String in ["proof.veh_tank", "proof.inf_squad"]:
		bk.add_recipe({"schema": "meridian.recipe/1", "id": id, "archetype": id.trim_prefix("proof.")}, "test")
	bk.link()
	return bk


func test_real_archetypes_load(t: TestCtx) -> void:
	var bk: ViewRecipeBook = _real_book()
	t.eq(bk.errors().size(), 0, "no load errors: %s" % [bk.errors()])
	t.check(bk.archetype(&"veh_tank") != null and bk.archetype(&"inf_squad") != null, "archetypes present")
	for s: String in ["napc", "nec", "def", "han", "neutral"]:
		t.check(bk.has_style(StringName(s)), "style " + s)


func test_threaded_build_equals_single_thread_hash(t: TestCtx) -> void:
	var bk: ViewRecipeBook = _real_book()
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	var single: ViewModelBuilder = ViewModelBuilder.new()
	single.setup(bk, q)
	var threaded: ViewModelBuilder = ViewModelBuilder.new()
	threaded.setup(bk, q)
	var combos: Array = []
	for rid: String in ["proof.veh_tank", "proof.inf_squad"]:
		for st: String in ["napc", "nec", "def", "han"]:
			combos.append([StringName(rid), StringName(st)])
	for c: Array in combos:
		threaded.request(c[0] as StringName, c[1] as StringName)
	t.gt(threaded.pending(), 0, "requests pending")
	var t0: int = Time.get_ticks_msec()
	while threaded.pending() > 0 and Time.get_ticks_msec() - t0 < 20000:
		threaded.pump(4.0)
		OS.delay_msec(2)
	t.eq(threaded.pending(), 0, "all background builds finished")
	for c: Array in combos:
		var a: ViewModel = single.get_model(c[0] as StringName, c[1] as StringName)
		var b: ViewModel = threaded.get_model(c[0] as StringName, c[1] as StringName)
		t.check(not a.placeholder, "built: %s %s" % [c[0], a.error])
		t.eq(b.info.content_hash, a.info.content_hash, "threaded == single-thread hash for %s@%s" % [c[0], c[1]])
	var again: ViewModelBuilder = ViewModelBuilder.new()
	again.setup(bk, q)
	t.eq(again.get_model(&"proof.veh_tank", &"napc").info.content_hash, single.get_model(&"proof.veh_tank", &"napc").info.content_hash, "deterministic across builders")
	t.ne(single.get_model(&"proof.veh_tank", &"nec").info.content_hash, single.get_model(&"proof.veh_tank", &"napc").info.content_hash, "styles differ")


func test_tank_proof_budgets_and_parts(t: TestCtx) -> void:
	var bk: ViewRecipeBook = _real_book()
	var mb: ViewModelBuilder = ViewModelBuilder.new()
	mb.setup(bk, null)
	for st: String in ["napc", "nec", "def", "han"]:
		var m: ViewModel = mb.get_model(&"proof.veh_tank", StringName(st))
		t.check(not m.placeholder, "%s builds: %s" % [st, m.error])
		var i: ViewModelInfo = m.info
		t.le(i.tris.x, 5000, "%s LOD0 tris %d <= 5000" % [st, i.tris.x])
		t.le(i.tris.y, 2800, "%s LOD1 tris %d <= 2800" % [st, i.tris.y])
		t.lt(i.verts, 65535, "%s vertex cap" % st)
		t.le(i.height, 2.4 * i.boost, "%s height %.2f" % [st, i.height])  # design cap x the VQ2A boost
		t.check(i.radius > 1.7 and i.radius < 3.6 * i.boost, "%s radius %.2f in the medium band" % [st, i.radius])
		for p: int in [Pt.TURRET, Pt.BARREL, Pt.TRACK, Pt.WHEEL]:
			t.check(i.has_part(p), "%s has part %d" % [st, p])
		t.check(i.has_socket(&"muzzle0_0") and i.has_socket(&"top") and i.has_socket(&"exhaust0"), "%s sockets" % st)
		t.eq(m.meta.get("motion"), "tracked", "archetype meta carried")
		t.lt(i.build_ms, 60.0, "%s build %.1f ms (hard 60)" % [st, i.build_ms])


func test_squad_proof(t: TestCtx) -> void:
	var bk: ViewRecipeBook = _real_book()
	var mb: ViewModelBuilder = ViewModelBuilder.new()
	mb.setup(bk, null)
	var m: ViewModel = mb.get_model(&"proof.inf_squad", &"napc")
	t.check(not m.placeholder, "squad builds: %s" % m.error)
	t.eq(m.info.members, 4, "four members")
	t.le(m.info.tris.x, 1400, "squad LOD0 tris %d" % m.info.tris.x)
	t.le(m.info.tris.y, 800, "squad LOD1 tris %d" % m.info.tris.y)
	t.le(m.info.height, 1.6 * m.info.boost, "squad height %.2f" % m.info.height)
	t.le(m.info.radius, 1.45 * m.info.boost, "squad disc radius %.2f" % m.info.radius)
	for p: int in [Pt.LEG_A, Pt.LEG_B, Pt.ARM_A, Pt.BODY_BOB]:
		t.check(m.info.has_part(p), "gait part %d" % p)
	var m2: ViewModel = mb.get_model(&"proof.inf_squad", &"napc", 8000)
	t.check(m2.info.height < m.info.height * 0.85, "scale_bp scales the model")


func test_every_macro_builds_with_defaults_and_keeps_state_balanced(t: TestCtx) -> void:
	var pal: Dictionary = {}
	for k: Variant in ViewRecipeInterpreter.DEFAULT_PALETTE:
		pal[k] = Color(str(ViewRecipeInterpreter.DEFAULT_PALETTE[k]))
	for name: String in ViewRecipeMacros.macro_names():
		var sig: Dictionary = ViewRecipeMacros.signature(name)
		var args: Dictionary = {}
		for an: Variant in sig:
			var spec: Array = sig[an] as Array
			var dv: Variant = spec[1]
			match spec[0] as String:
				"n":
					args[an] = dv
				"v":
					args[an] = Vector3((dv as Array)[0] as float, (dv as Array)[1] as float, (dv as Array)[2] as float)
				"w":
					args[an] = Vector2((dv as Array)[0] as float, (dv as Array)[1] as float)
				"c":
					args[an] = pal[dv]
				"s":
					args[an] = dv
				"A":
					var zs: Array[float] = [-0.8, 0.0, 0.8]
					args[an] = zs
		var b: ViewMeshBuilder = ViewMeshBuilder.new()
		var err: String = ViewRecipeMacros.run(name, b, args, pal)
		t.eq(err, "", "macro %s runs" % name)
		t.gt(b.vertex_count(), 0, "macro %s emits geometry" % name)
		t.eq(b.part, Pt.STATIC, "macro %s leaves no part open" % name)
		b.build_arrays()
		t.check(is_finite(b.info().rest_aabb.size.x) and b.info().rest_aabb.size.length() < 60.0, "macro %s bounded" % name)
