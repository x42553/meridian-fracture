extends RefCounted
## VQ2B: the `--scenario=showcase` debug scenario (AppScenario), the camera-shake ceilings of the FX stage and the
## loading screen that builds from the match config before the world exists.

const H := preload("res://tests/ui/ui_harness.gd")


func test_scenario_flags_parse(t: TestCtx) -> void:
	t.check(AppScenario.from_args(AppLaunchArgs.parse(PackedStringArray(["--autostart=match"]))) == null, "no flag, no scenario")
	var s: AppScenario = AppScenario.from_args(AppLaunchArgs.parse(PackedStringArray(["--scenario=showcase", "--sw-at=33", "--sw-pids=0,2",
		"--sw-target=10,12", "--battle=naval", "--battle-n=24", "--army=5", "--credits=1234"])))
	t.check(s != null, "showcase scenario parsed")
	t.eq(s.sw_at, 33)
	t.eq(Array(s.sw_pids), [0, 2])
	t.eq(s.sw_target, Vector2i(10, 12))
	t.eq(s.battle, "naval")
	t.eq(s.battle_n, 24)
	t.eq(s.army, 5)
	t.eq(s.credits, 1234)
	var all: AppScenario = AppScenario.from_args(AppLaunchArgs.parse(PackedStringArray(["--scenario=showcase", "--sw-pids=all"])))
	t.check(all.sw_all, "--sw-pids=all")


func test_scenario_builds_tech_and_launches_the_superweapon(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"rosters": PackedStringArray(["roster.def.vanilla", "roster.nec.vanilla"]), "seed": 3, "size": 96, "bots": false})
	var w: SimWorld = m["world"] as SimWorld
	t.check(w != null, "world built")
	if w == null:
		return
	var s: AppScenario = AppScenario.from_args(AppLaunchArgs.parse(PackedStringArray(["--scenario=showcase", "--sw-at=30", "--credits=90000"])))
	var structs_before: int = w.structures_of(0).size()
	var launched_warning: bool = false
	for _i: int in 90:
		s.step(w)
		w.step()
		for wr: SimWarning in w.strategic.warnings:
			if wr.kind == SimEconConst.WK_SUPER and wr.owner == 0:
				launched_warning = true
	t.gt(w.structures_of(0).size(), structs_before + 5, "generators, Radar, Laboratory and the launcher were placed instantly")
	t.check(w.players[0].credits >= 90000 - 100, "rich credits")
	t.check(launched_warning, "the superweapon of player 0 was charged and launched (a WK_SUPER warning opened)")
	t.eq(w.players[1].econ.slots[SimEconConst.SLOT_SW].sw_state, SimEconConst.SW_CHARGING, "player 1 was not told to launch: its weapon charges")


func test_staged_ground_battle_spawns_two_armies(t: TestCtx) -> void:
	var m: Dictionary = SimMatchKit.make_match({"rosters": PackedStringArray(["roster.han.vanilla", "roster.def.vanilla"]), "seed": 3, "size": 96, "bots": false})
	var w: SimWorld = m["world"] as SimWorld
	if w == null:
		t.check(false, "world built")
		return
	var s: AppScenario = AppScenario.from_args(AppLaunchArgs.parse(PackedStringArray(["--scenario=showcase", "--sw-at=0", "--battle=ground", "--battle-n=20", "--battle-at=3"])))
	var units_before: int = w.units.size()
	for _i: int in 8:
		s.step(w)
		w.step()
	t.gt(w.units.size(), units_before + 30, "about 20 units per side appeared")


func test_shake_ceilings_keep_a_big_battle_from_pinning_the_camera(t: TestCtx) -> void:
	var trauma: float = 0.0
	for _i: int in 100:
		trauma += FxStage.shake_increment(0.15, trauma)  # a hundred tier-2 impacts in a row
	t.check(trauma <= FxStage.AMBIENT_CAP + 0.0001, "small impacts stop at the ambient ceiling (%.2f)" % trauma)
	t.check(FxStage.shake_increment(0.35, 0.28) > 0.0 and FxStage.shake_increment(0.35, 0.6) == 0.0, "medium impacts lift to the medium ceiling only")
	t.eq(FxStage.shake_increment(1.0, 0.6), 0.4, "a superweapon impact can still reach full trauma")


func test_loading_screen_builds_from_the_config_before_the_world(t: TestCtx) -> void:
	var h: H.Rig = await H.make(Vector2i(1280, 720))
	var scr: UiScreenLoading = UiScreenLoading.new()
	h.root.add_child(scr)
	UiLayerRoot.fill(scr)
	scr.enter({"title": "Skirmish"})
	t.check(scr._build_pending or scr.ctx != null, "no match context yet: the screen waits for the config instead of showing 0 x 0")
	var ctx: AppMatchContext = AppMatchContext.new()
	ctx.config = {"map": {"family": 0, "size": 144, "seed": 77, "params": {}}, "rules": {"start_credits": 7500, "fog": true},
		"players": [{"pid": 0, "kind": "human", "name": "A", "roster": "roster.napc.vanilla", "color": 0}, {"pid": 1, "kind": "ai", "name": "B", "roster": "roster.nec.vanilla", "color": 1}]}
	scr.ctx = ctx
	scr._process(0.05)
	t.check(not scr._build_pending, "built as soon as the config exists")
	t.check(scr._family_line().contains("144 x 144"), "the configured size shows immediately: " + scr._family_line())
	t.eq(scr._rows.size(), 2, "both commanders are listed")
	scr.exit()
	H.done(h)
