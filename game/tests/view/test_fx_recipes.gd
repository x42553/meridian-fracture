extends RefCounted
## VIEW-F2 acceptance: fx.json compiles, errors carry the layer path, inheritance, expressions, spike batch sets, cost per spawn.

const Kit := preload("res://tests/view/fx_kit.gd")


func _book(doc: Dictionary) -> FxRecipeBook:
	var b: FxRecipeBook = FxRecipeBook.new()
	b.load_dict(doc)
	return b


func _errors_of(doc: Dictionary) -> String:
	return "\n".join(_book(doc).errors())


func _doc(effects: Dictionary) -> Dictionary:
	return {"schema": "meridian.fx/1", "effects": effects}


func test_shipped_fx_json_compiles(t: TestCtx) -> void:
	var b: FxRecipeBook = FxRecipeBook.new()
	t.check(b.load_file(), "fx.json compiles: %s" % "; ".join(b.errors()))
	t.gt(b.ids().size(), 30, "at least the 34 spike lineage effects")
	for id: String in ["expl_small", "expl_medium", "expl_large", "muzzle_cannon", "emp_pulse", "sw_shockwave", "building_collapse"]:
		t.check(b.has(StringName(id)), "%s registered" % id)
	t.check(not b.has(&"tpl_explosion"), "templates are not spawnable")
	t.is_null(b.def(&"tpl_explosion"), "def() of a template is null")
	t.eq(b.class_table.size(), 6, "class table loaded")


func test_errors_name_the_layer_path(t: TestCtx) -> void:
	var e: String = _errors_of(_doc({"boom": {"class": "medium", "kind": "point", "layers": [
		{"op": "sprites", "batch": "fire", "size": "1", "life": 1},
		{"op": "sprites", "batch": "fire", "size": "r*2", "life": 1},
	]}}))
	t.check(e.begins_with("boom/layers[1]/sprites/size:"), "path of the bad expression: %s" % e)
	t.check(e.contains("unknown identifier 'r'"), "message says why")
	e = _errors_of(_doc({"x": {"layers": [{"op": "for", "var": "i", "n": 2, "do": [{"op": "puff", "batch": "puff_dust", "size": "q", "life": 1}]}]}}))
	t.check(e.begins_with("x/layers[0]/for/do[0]/puff/size:"), "nested path: %s" % e)
	e = _errors_of(_doc({"x": {"layers": [{"op": "warp"}]}}))
	t.check(e.contains("x/layers[0]: unknown op 'warp'"), e)
	e = _errors_of(_doc({"x": {"layers": [{"op": "sprites", "batch": "fire", "size": 1}]}}))
	t.check(e.contains("x/layers[0]/sprites: missing required key 'life'"), e)
	e = _errors_of(_doc({"x": {"layers": [{"op": "sprites", "batch": "fyre", "size": 1, "life": 1}]}}))
	t.check(e.contains("unknown batch 'fyre'"), e)
	e = _errors_of(_doc({"x": {"layers": [{"op": "sprites", "batch": "ring_add", "size": 1, "life": 1}]}}))
	t.check(e.contains("cannot be used by 'sprites'"), e)
	e = _errors_of(_doc({"x": {"layers": [{"op": "sprites", "batch": "fire", "size": 1, "life": 1, "sise": 3}]}}))
	t.check(e.contains("unknown key 'sise'"), e)
	e = _errors_of(_doc({"x": {"class": "huge", "layers": []}}))
	t.check(e.contains("x: unknown class 'huge'"), e)


func test_bad_effect_is_not_registered_but_others_are(t: TestCtx) -> void:
	var b: FxRecipeBook = _book(_doc({
		"bad": {"layers": [{"op": "shake", "amount": "nope"}]},
		"good": {"layers": [{"op": "shake", "amount": 1}]},
	}))
	t.check(b.has(&"good"), "good effect registered")
	t.check(not b.has(&"bad"), "bad effect dropped")
	t.eq(b.errors().size(), 1, "one error")


func test_reference_and_cycle_checks(t: TestCtx) -> void:
	var e: String = _errors_of(_doc({"a": {"layers": [{"op": "fx", "id": "ghost"}]}}))
	t.check(e.contains("a: fx/loop references unknown effect 'ghost'"), e)
	e = _errors_of(_doc({
		"a": {"layers": [{"op": "fx", "id": "b", "delay": 1}]},
		"b": {"layers": [{"op": "loop", "id": "a", "interval": 1, "duration": 2}]},
	}))
	t.check(e.contains("fx cycle: a -> b -> a"), e)
	e = _errors_of(_doc({"a": {"extends": "b"}, "b": {"extends": "a"}}))
	t.check(e.contains("extends cycle"), e)
	e = _errors_of(_doc({"tpl": {"template": true, "layers": []}, "a": {"layers": [{"op": "fx", "id": "tpl"}]}}))
	t.check(e.contains("references template 'tpl'"), e)
	t.eq(_errors_of(_doc({"tpl": {"template": true, "layers": []}, "a": {"layers": [{"op": "fx", "id": "tpl", "inline": true}]}})), "", "inline may target a template")


func test_inheritance_vars_override_layers_replace(t: TestCtx) -> void:
	var doc: Dictionary = _doc({
		"tpl": {"template": true, "class": "large", "kind": "line", "radius": 5.0, "vars": {"r": "s*2", "k": "r+1"},
			"layers": [{"op": "sprites", "batch": "fire", "size": "k", "life": 1.0}]},
		"kid": {"extends": "tpl", "vars": {"r": "s*10"}},
		"own": {"extends": "tpl", "layers": [{"op": "sprites", "batch": "smoke", "size": 1, "life": 1}]},
	})
	var b: FxRecipeBook = _book(doc)
	t.eq(b.errors().size(), 0, "compiles: %s" % "; ".join(b.errors()))
	var kid: FxRecipeBook.FxDef = b.def(&"kid")
	t.eq(kid.cls, FxManager.Cls.LARGE, "class inherited")
	t.eq(kid.kind, FxManager.Kind.LINE, "kind inherited")
	t.near(kid.radius, 5.0, 1.0e-6, "radius inherited")
	t.check(not kid.template, "template flag is not inherited")
	t.eq(kid.layers.size(), 1, "layers inherited")
	t.eq(b.def(&"own").layers.size(), 1, "own layers replace")
	# the child override changes the derived var: size = s*10 + 1
	var k: Kit = Kit.make(FxManager.Quality.HIGH, 60.0, doc) as Kit
	k.fx.force = true
	k.fx.trace_emits = true
	k.fx.spawn(&"kid", k.on_axis(60.0), Vector3.ZERO, 2.0)
	var sz: float = ((k.fx.emit_log[0] as Array)[1] as Transform3D).basis.x.length()
	t.near(sz, 21.0, 1.0e-3, "kid size = (s*10)+1 = 21")
	k.free_all()


func test_expression_scope_and_anchors(t: TestCtx) -> void:
	var doc: Dictionary = _doc({"probe": {"class": "medium", "kind": "line", "radius": 2.0, "vars": {"speed": 10},
		"layers": [
			{"op": "sprites", "batch": "flash", "at": "b", "along": 2, "off": [0, 1, 0], "size": "dist", "life": "flight", "param": "s", "pal": 3},
		]}})
	var k: Kit = Kit.make(FxManager.Quality.HIGH, 60.0, doc) as Kit
	t.eq(k.book.errors().size(), 0, "compiles")
	k.fx.force = true
	k.fx.trace_emits = true
	k.fx.spawn(&"probe", Vector3(0, 0, 0), Vector3(30, 0, 0), 0.5)
	var e: Array = k.fx.emit_log[0] as Array
	var xf: Transform3D = e[1] as Transform3D
	t.near(xf.origin.x, 32.0, 1.0e-4, "at b, 2 m along the a->b direction")
	t.near(xf.origin.y, 1.0, 1.0e-4, "off y")
	t.near(xf.basis.x.length(), 30.0, 1.0e-4, "size = dist")
	t.near(e[3] as float, 3.0, 1.0e-4, "life = flight = dist / speed")
	t.near(e[5] as float, 0.5, 1.0e-4, "param = s")
	t.eq(int(floor(e[4] as float)), 3, "palette")
	k.free_all()


func test_random_functions(t: TestCtx) -> void:
	var doc: Dictionary = _doc({"rnd": {"layers": [
		{"op": "for", "var": "i", "n": 40, "do": [
			{"op": "sprites", "batch": "flash", "off": ["rsq()*10", 0, 0], "size": "randr(2, 4)", "life": "1+rand()", "param": 1, "pal": 0}]}]}})
	var k: Kit = Kit.make(FxManager.Quality.HIGH, 60.0, doc) as Kit
	t.eq(k.book.errors().size(), 0, "compiles: %s" % "; ".join(k.book.errors()))
	k.fx.force = true
	k.fx.trace_emits = true
	k.fx.spawn(&"rnd", Vector3.ZERO)
	var lo: float = 100.0
	var hi: float = -100.0
	var xs: Dictionary = {}
	for i: int in 40:
		var xf: Transform3D = (k.fx.emit_log[i] as Array)[1] as Transform3D
		var sz: float = xf.basis.x.length()
		lo = minf(lo, sz)
		hi = maxf(hi, sz)
		xs[snappedf(xf.origin.x, 0.001)] = true
		t.check(absf(xf.origin.x) <= 10.0 + 1.0e-4, "rsq within [-1, 1] x 10")
		var life: float = (k.fx.emit_log[i] as Array)[3] as float
		t.check(life >= 1.0 and life <= 2.0, "1 + rand() in [1, 2]")
	t.check(lo >= 2.0 - 1.0e-4 and hi <= 4.0 + 1.0e-4, "randr(2, 4) stays in range (%f..%f)" % [lo, hi])
	t.gt(xs.size(), 30, "fresh value on every evaluation")
	k.free_all()


func test_delay_becomes_schedule_and_when_skips(t: TestCtx) -> void:
	var doc: Dictionary = _doc({"d": {"layers": [
		{"op": "sprites", "batch": "flash", "size": 1, "life": 1, "delay": 0.5},
		{"op": "sprites", "batch": "glow", "size": 1, "life": 1, "when": "s > 1"},
	]}})
	var k: Kit = Kit.make(FxManager.Quality.HIGH, 60.0, doc) as Kit
	k.fx.force = true
	k.fx.spawn(&"d", Vector3.ZERO, Vector3.ZERO, 1.0)
	t.eq(k.fx.batch(&"flash").active_count(k.fx.now()), 0, "delayed layer not yet drawn")
	t.eq(k.fx.pending_scheduled(), 1, "one scheduled layer")
	t.eq(k.fx.batch(&"glow").active_count(k.fx.now()), 0, "when=false skipped")
	k.fx.advance(0.6)
	t.eq(k.fx.batch(&"flash").active_count(k.fx.now()), 1, "drawn after the delay")
	k.fx.spawn(&"d", Vector3.ZERO, Vector3.ZERO, 2.0)
	t.eq(k.fx.batch(&"glow").active_count(k.fx.now()), 1, "when=true drawn")
	k.free_all()


func test_native_escape_hatch(t: TestCtx) -> void:
	var hits: Array[float] = []
	var b: FxRecipeBook = FxRecipeBook.new()
	b.natives["probe"] = func(_m: FxManager, _a: Vector3, _b: Vector3, s: float, args: Array) -> void: hits.append(s + float(args[0]) + float(args[1]))
	b.load_dict(_doc({"n": {"layers": [{"op": "native", "name": "probe", "args": [1, "s*10"]}]}}))
	t.eq(b.errors().size(), 0, "native compiles")
	var k: Kit = Kit.make() as Kit
	k.fx.setup(k.cam, FxManager.Quality.HIGH, b, null, null)
	k.fx.force = true
	k.fx.spawn(&"n", Vector3.ZERO, Vector3.ZERO, 2.0)
	t.eq(hits.size(), 1, "native called")
	t.near(hits[0], 2.0 + 1.0 + 20.0, 1.0e-6, "args evaluated")
	t.check("unknown native" in _errors_of(_doc({"n": {"layers": [{"op": "native", "name": "nope", "args": []}]}})), "unknown native rejected")
	k.free_all()


func test_interpreted_expl_matches_spike_batch_sets(t: TestCtx) -> void:
	# the spike's explode(): glow, flash, gglow, fire, smoke, sparks always; debris r >= 1.2; ring_distort, ring_add, dustring r >= 2.4; dustcol r >= 4.5
	var base: Array[StringName] = [&"glow", &"flash", &"gglow", &"fire", &"smoke", &"sparks", &"debris", &"ring_distort", &"ring_add", &"dustring"]
	var sets: Dictionary = {
		&"expl_small": [&"glow", &"flash", &"gglow", &"fire", &"smoke", &"sparks", &"debris"],
		&"expl_medium": base,
		&"expl_large": base + [&"dustcol"],
	}
	var k: Kit = Kit.make() as Kit
	k.fx.force = true
	for id: StringName in sets:
		k.fx.clear_all()
		k.fx.reset_stats()
		k.fx.spawn(id, k.on_axis(60.0))
		var got: Array[StringName] = []
		for n: StringName in k.fx.batch_names():
			if k.fx.batch(n).spawned > 0:
				got.append(n)
		var want: Array = sets[id]
		got.sort()
		want = want.duplicate()
		want.sort()
		t.eq(got, want, "%s batch set" % id)
		t.eq(k.fx.live_lights(), 1, "%s: one light" % id)
	k.free_all()


func test_composite_spawn_cost_under_100us(t: TestCtx) -> void:
	var k: Kit = Kit.make() as Kit
	k.fx.force = true
	var p: Vector3 = k.on_axis(60.0)
	for warm: int in 30:
		k.fx.spawn(&"expl_medium", p)
	var samples: Array[float] = []
	for round_i: int in 15:
		var t0: int = Time.get_ticks_usec()
		for i: int in 40:
			k.fx.spawn(&"expl_medium", p)
		samples.append(float(Time.get_ticks_usec() - t0) / 40.0)
		k.fx.advance(0.05)
	samples.sort()
	var median: float = samples[samples.size() / 2]
	t.note("expl_medium: median %.1f us per composite spawn (min %.1f)" % [median, samples[0]])
	t.lt(median, 100.0 * TestCtx.perf_factor(), "median composite spawn < 100 us (x perf_factor)")
	k.free_all()


func test_catalog_resolves_the_spec_vocabulary(t: TestCtx) -> void:
	var k: Kit = Kit.make() as Kit
	var c: FxCatalog = FxCatalog.new(k.book)
	t.eq(c.muzzle_id(0), &"muzzle_small_arms", "small_arms muzzle")
	t.eq(c.muzzle_id(3), &"muzzle_cannon", "tank cannon muzzle")
	t.eq(c.muzzle_id(9), &"muzzle_artillery", "artillery muzzle")
	t.eq(c.muzzle_id(14), &"muzzle_rail", "rail muzzle")
	t.eq(c.muzzle_id(13), &"muzzle_beam_thermal", "thermal muzzle")
	t.eq(c.impact_id(0, 1, 0), &"hit_bullet", "no splash bullet")
	t.eq(c.impact_id(14, 1, 0), &"hit_rail", "rail no splash")
	t.eq(c.impact_id(3, 2, 1024), &"expl_small", "1-cell splash = 3 m -> small")
	t.eq(c.impact_id(4, 2, 1300), &"expl_medium", "3.8 m splash -> medium")
	t.eq(c.impact_id(9, 2, 2300), &"expl_large", "6.7 m splash -> large")
	t.eq(c.impact_id(3, 3, 0), &"impact_water", "result 3 water")
	t.eq(c.explosion_id(0, 4000, 6), &"emp_pulse", "EMP damage type")
	t.eq(c.explosion_id(0, 4000, 2), &"expl_large", "HE 11.7 m")
	t.eq(c.death_id(FxCatalog.DK_VEHICLE, 1), &"death_vehicle_light", "light vehicle death")
	t.eq(c.death_id(FxCatalog.DK_VEHICLE, 3), &"death_vehicle_heavy", "heavy vehicle death")
	t.eq(c.death_id(FxCatalog.DK_STRUCTURE, 0), &"building_collapse", "structure death")
	t.eq(c.death_id(FxCatalog.DK_CRASH, 0), &"aircraft_crash", "crash")
	t.near(c.arc_apex(9), 0.25, 1.0e-6, "artillery arc apex from mappings")
	k.free_all()
