extends RefCounted
## VIEW-F3/F4: the eight superweapon sequences (warning marker, pre-impact timeline, execution) driven by the REAL sim: each
## superweapon is launched through CMD_LAUNCH_SUPERWEAPON on the real data, the kernel's own events reach the router through
## ViewWorld.frame, and the effects that appear are checked against render spec 5.9.5.

const A := preload("res://tests/support/ab2_kit.gd")
const S := preload("res://tests/support/strat_kit.gd")
const Kit := preload("res://tests/view/vw_kit.gd")

## roster -> [expected counts {effect id: min}, exact counts {effect id: n}]
const CASES: Array = [
	["roster.napc.usa", "atlas", {"sw_warning_marker": 2, "sw_atlas_pre": 1}, {"sw_atlas_impact": 3}],
	["roster.nec.vanilla", "aurora", {"sw_warning_marker": 1}, {"sw_charge_dome": 1, "sw_microwave_dome": 1}],
	["roster.olm.vanilla", "helios", {"sw_warning_marker": 2}, {"sw_helios_start": 1}],
	["roster.def.vanilla", "perun", {"sw_warning_marker": 1}, {"sw_perun_streak": 1, "sw_perun_core": 1, "sw_perun_wave": 1}],
	["roster.pd.vanilla", "tempest", {"sw_warning_marker": 1}, {"sw_tempest_launch": 1}],
	["roster.han.vanilla", "dragonfall", {"sw_warning_marker": 1, "sw_dragonfall_capsule": 1}, {}],
	["roster.ae.vanilla", "horizon", {"sw_warning_marker": 2}, {"sw_horizon_pre": 1, "sw_horizon_impact": 3}],
	["roster.sap.vanilla", "trident", {"sw_warning_marker": 1, "zone_intercept_burst": 1, "sw_intercept_dome": 1}, {}],
]


func _run(roster: String, ticks: int) -> Dictionary:
	var other: String = "roster.nec.vanilla" if roster != "roster.nec.vanilla" else "roster.def.vanilla"
	var w: SimWorld = A.world({"rosters": [roster, other], "movement": false, "invariants_every": 25})
	S.base(w, 0, 10, 10)
	S.base(w, 1, 44, 44)
	var vw: ViewWorld = Kit.view(w, 0, Vector2(30.0, 30.0), 0.5)
	var book: FxRecipeBook = FxRecipeBook.new()
	book.load_file()
	var fx: FxManager = FxManager.new()
	fx.viewport_size_override = Vector2(1920.0, 1080.0)
	fx.camera_focus_dist = 60.0
	fx.setup(vw.camera.camera, FxManager.Quality.HIGH, book, vw.terrain, null)
	fx.force = true
	var router: FxEventRouter = FxEventRouter.new()
	router.setup(vw, fx, null)
	router.record = true
	router.attach(vw)
	var proj: ViewProjectiles = ViewProjectiles.new()
	proj.setup(vw, fx, router.catalog)
	router.projectiles = proj
	S.force_ready(w, 0)
	w.clear_events()
	S.launch(w, 0, 30, 30, 0)
	var max_trackers: int = 0
	var max_emitters: int = 0
	for i: int in ticks:
		w.step()
		vw.frame(1.0 / 60.0, 1.0, w.events.take())
		router.frame(0.05)
		fx.advance(0.05)
		max_trackers = maxi(max_trackers, int(fx.get_stats()["trackers"]))
		max_emitters = maxi(max_emitters, fx.emitter_count())
	var counts: Dictionary = {}
	for rec: Variant in router.spawn_log:
		var id: StringName = (rec as Array)[0] as StringName
		counts[id] = (counts.get(id, 0) as int) + 1
	var out: Dictionary = {"counts": counts, "trackers": max_trackers, "emitters": max_emitters, "unknown": router.stats["unknown"], "world": w}
	proj.teardown()
	fx.free()
	Kit.free_view(vw)
	return out


func test_all_eight_sequences_from_the_real_sim(t: TestCtx) -> void:
	for row: Array in CASES:
		var res: Dictionary = _run(row[0] as String, 780)
		var counts: Dictionary = res.counts as Dictionary
		var name_: String = row[1] as String
		for id: Variant in (row[2] as Dictionary):
			t.ge(counts.get(id, 0) as int, (row[2] as Dictionary)[id] as int, "%s: at least %d x %s (got %s)" % [name_, (row[2] as Dictionary)[id], id, counts.get(id, 0)])
		for id2: Variant in (row[3] as Dictionary):
			t.eq(counts.get(id2, 0) as int, (row[3] as Dictionary)[id2] as int, "%s: exactly %d x %s" % [name_, (row[3] as Dictionary)[id2], id2])
		t.eq(res.unknown, 0, "%s: every emitted event is routed or ignored" % name_)
		if name_ == "helios":
			t.gt(res.trackers as int, 0, "helios: the sweep tracker ran")
		if name_ == "trident":
			t.gt(res.emitters as int, 0, "trident: dome pulses / tick loops ran")
		if name_ == "dragonfall":
			t.gt(counts.get(&"sw_assemble_burst", 0) as int, 0, "dragonfall: capsule unfold burst (%s)" % counts)
