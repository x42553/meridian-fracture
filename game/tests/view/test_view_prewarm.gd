extends RefCounted
## The model prewarm of the loading screen (ViewWorld.build_async): every unit, structure, summon, HQ / MCV and projectile mesh a match can show
## is built on worker threads BEFORE the first frame. A model built synchronously mid-match is a 20-30 ms hitch (measured: 21 builds = 557 ms in an
## 8-player match before the structures were prewarmed); `ViewModelBuilder.stat_sync_builds` counts them.

const Fx := preload("res://tests/fixtures/view_terrain_fixture.gd")


func test_no_model_is_built_synchronously_after_the_prewarm(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"seed": 3, "size": 96, "bots": false,
		"rosters": ["roster.napc.vanilla", "roster.nec.vanilla", "roster.han.vanilla", "roster.sap.vanilla"]})
	var w: SimWorld = m["world"] as SimWorld
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.MEDIUM)
	var vw: ViewWorld = ViewWorld.create(q)
	var ter: ViewTerrain = ViewTerrain.new()
	ter.build(Fx.source(96, func(_x: int, _y: int) -> int: return 0), 2, ViewDetailTextures.build(64), false, false)
	vw.add_child(ter)
	vw.terrain = ter
	var cam: ViewCamera = ViewCamera.new()
	cam.auto_input = false
	cam.edge_scroll_enabled = false
	cam.view_size_override = Vector2(1920.0, 1080.0)
	vw.add_child(cam)
	vw.camera = cam
	vw.drive_camera = false
	var opts: ViewBuildOptions = ViewBuildOptions.new()
	opts.build_terrain = false
	opts.create_camera = false
	opts.prewarm_scope = 1
	opts.screenshot_mode = true
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(vw)
	await vw.build_async(w, 0, opts)
	var before: int = vw.models.stat_sync_builds
	var made: int = 0
	var next_id: int = 900000
	var styles: Dictionary = {}
	for p: SimPlayer in w.players:
		if p.roster == null:
			continue
		var kinds: Array = []
		for ui: int in p.roster.producible_units:
			kinds.append([SimEntity.Kind.UNIT, ui])
		for ui: int in p.roster.spawnables:
			kinds.append([SimEntity.Kind.UNIT, ui])
		for si: int in p.roster.producible_structures:
			kinds.append([SimEntity.Kind.STRUCTURE, si])
		kinds.append([SimEntity.Kind.STRUCTURE, p.roster.hq_idx])
		for k: Variant in kinds:
			var ka: Array = k as Array
			var ve: ViewEntity = vw.create_entity(next_id, ka[0] as int, ka[1] as int, p.pid, 4096, 4096, 0, SimEvent.SPAWN_PRODUCED, 1)
			next_id += 1
			made += 1
			if ve != null:
				styles[ve.style_id] = true
			if ve == null:
				t.fail("create_entity returned null for kind %d def %d" % [ka[0], ka[1]])
	t.gt(made, 100, "entities of every producible def were created")
	for rid: String in vw.book.ids():  # projectile meshes, styled by the shooter
		if rid.begins_with("proj."):
			for sid: Variant in styles:
				vw.models.get_model(StringName(rid), sid as StringName, 10000)
	t.eq(vw.models.stat_sync_builds, before, "no model was built on the main thread after the prewarm (last: %s)" % vw.models.stat_sync_last)
	tree.root.remove_child(vw)
	vw.teardown()
	vw.free()
