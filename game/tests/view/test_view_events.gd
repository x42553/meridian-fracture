extends RefCounted
## VIEW-W1: the event router (lifecycle, death windows, hit / fire, structure phases) driven by synthetic batches built with
## ViewTestEvents on a real SimWorld, plus the table check over every render reaction and the constant validation.

const Kit := preload("res://tests/view/vw_kit.gd")


func _rec(type: int, tick: int, x: int, y: int, a: int, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0) -> PackedInt32Array:
	return ViewTestEvents.make(type, tick, x, y, a, b, c, d, e, f)


func _tank_idx(w: SimWorld) -> int:
	return w.data.unit_idx(DefTestKit.U_TANK)


func _spawn_rec(w: SimWorld, id: int, tick: int, reason: int, kind: int = SimEntity.Kind.UNIT, def: int = -1, x: int = 30 * 3072, y: int = 30 * 3072) -> PackedInt32Array:
	return _rec(SimEvent.SPAWNED, tick, x, y, id, kind, _tank_idx(w) if def < 0 else def, 0, 0, reason)


func test_spawned_creates_from_payload_and_ignores_duplicates(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	# an id the sim never allocated: the record is built from the payload alone
	var n0: int = vw.entity_count()
	vw.router.process(_spawn_rec(w, 900, 5, SimEvent.SPAWN_PRODUCED))
	var ve: ViewEntity = vw.entity_view(900)
	if t.not_null(ve, "record exists"):
		t.eq(ve.kind, SimEntity.Kind.UNIT, "kind")
		t.eq(ve.def_idx, _tank_idx(w), "def")
		t.eq(ve.x_cur, 30 * 3072, "x from the payload")
		t.check(ve.model != null and ve.rig != null, "model and backend rig")
		t.check(ve is ViewUnit, "unit subclass")
	vw.router.process(_spawn_rec(w, 900, 5, SimEvent.SPAWN_PRODUCED))
	t.eq(vw.entity_count(), n0 + 1, "duplicate ignored")
	t.eq(vw.router.stats()["duplicates"], 1, "duplicate counted")
	Kit.free_view(vw)


func test_death_window_and_wreck(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	vw.router.process(_spawn_rec(w, 901, 10, SimEvent.SPAWN_PRODUCED))
	# DIED + REMOVED(KILLED) + wreck SPAWNED in one batch: DK_VEHICLE window = 2 ticks
	var died: PackedInt32Array = _rec(SimCombatConsts.EV_DEATH, 10, 30 * 3072, 30 * 3072, 901, _tank_idx(w), ViewConsts.DK_VEHICLE | (SimDeath.DK_FLAG_WRECK << 8), 7, 1, 1)
	var removed: PackedInt32Array = _rec(SimEvent.REMOVED, 10, 30 * 3072, 30 * 3072, 901, SimEntity.Kind.UNIT, _tank_idx(w), 0, SimEvent.REM_KILLED)
	var wreck: PackedInt32Array = _rec(SimEvent.SPAWNED, 10, 30 * 3072, 30 * 3072, 902, SimEntity.Kind.WRECK, _tank_idx(w), 0, 0, SimEvent.SPAWN_WRECK)
	vw.router.process(ViewTestEvents.batch([wreck, died, removed]))
	var ve: ViewEntity = vw.entity_view(901)
	t.check(ve != null and ve.dead and ve.sim_gone, "record kept for the dying window")
	t.eq(ve.dying_until_tick, 12, "vehicle window is 2 ticks")
	var wr: ViewEntity = vw.entity_view(902)
	if t.not_null(wr, "wreck record"):
		t.check((wr.flags & ViewConsts.UF_WRECK) != 0, "UF_WRECK")
		t.check(wr is ViewUnit, "wreck is a ViewUnit")
	w.tick = 11
	Kit.frame(vw)
	t.check(vw.has_entity(901), "still there at tick 11")
	w.tick = 12
	Kit.frame(vw)
	t.check(not vw.has_entity(901), "disposed at the end of the window")
	Kit.free_view(vw)


func test_death_windows_by_kind(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	var want: Dictionary = {ViewConsts.DK_INFANTRY: 2, ViewConsts.DK_CRASH: 30, ViewConsts.DK_AIR_EXPLODE: 1, ViewConsts.DK_SINK: 60, ViewConsts.DK_STRUCTURE: 7, ViewConsts.DK_DRONE: 1, ViewConsts.DK_SILENT: 8}
	var id: int = 950
	for dk: int in want:
		id += 1
		vw.router.process(_spawn_rec(w, id, 0, SimEvent.SPAWN_PRODUCED))
		vw.router.process(_rec(SimCombatConsts.EV_DEATH, 100, 0, 0, id, _tank_idx(w), dk, 0, 0, 0))
		t.eq(vw.entity_view(id).dying_until_tick, 100 + (want[dk] as int), "death kind %d window" % dk)
	Kit.free_view(vw)


func test_fire_and_hit_channels(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	vw.router.process(_spawn_rec(w, 903, 1, SimEvent.SPAWN_INITIAL))
	var ve: ViewEntity = vw.entity_view(903)
	vw.router.process(_rec(SimCombatConsts.EV_FIRE, 2, 0, 0, 903, 9, 0x0010, 5, 0, 0))
	t.near(ve.recoil, 1.0, 1e-6, "WEAPON_FIRED kicks the recoil")
	vw.router.process(_rec(SimCombatConsts.EV_HIT, 2, 0, 0, 903, 40, 5, 2 << 16, 60, 200))
	t.near(ve.flash, 1.0, 1e-6, "DAMAGE flashes")
	t.eq(ve.hp, 60, "hp mirrored from the payload")
	ve.flash = 0.0
	vw.router.process(_rec(SimCombatConsts.EV_HIT, 2, 0, 0, 903, 40, 5, (SimCombatConsts.HITF_KILLED | 2) << 16, 20, 200))
	t.near(ve.flash, 0.0, 1e-6, "a kill blow does not flash")
	Kit.free_view(vw)


func test_structure_phases(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	var fac: int = w.data.structure_idx(DefTestKit.S_FACTORY)
	vw.router.process(_spawn_rec(w, 904, 40, SimEvent.SPAWN_PLACED, SimEntity.Kind.STRUCTURE, fac, 40 * 3072, 40 * 3072))
	var st: ViewStructure = vw.entity_view(904) as ViewStructure
	if not t.not_null(st, "structure record"):
		return
	t.eq(st.phase, ViewConsts.PH_BUILDUP, "PLACED starts BUILDUP")
	t.eq(st.phase_t0, 40, "t0 is the event tick")
	t.eq(st.phase_ticks, 30, "30 ticks default")
	vw.router.process(_spawn_rec(w, 905, 40, SimEvent.SPAWN_INITIAL, SimEntity.Kind.STRUCTURE, fac, 50 * 3072, 40 * 3072))
	t.eq((vw.entity_view(905) as ViewStructure).phase, ViewConsts.PH_ACTIVE, "INITIAL is ACTIVE")
	# PRODUCTION_COMPLETE equivalent: EVT_UNIT_PRODUCED names the producer in d
	vw.router.process(_rec(SimEconConst.EVT_UNIT_PRODUCED, 60, 0, 0, 0, 77, _tank_idx(w), 905))
	t.eq((vw.entity_view(905) as ViewStructure).door_dir, 1, "producer door opens")
	# selling: reverse phase over the announced ticks, REMOVED(SOLD) disposes at once
	vw.router.process(_rec(SimEconConst.EVT_STRUCTURE_SELLING, 70, 0, 0, 0, 905, 110))
	var s2: ViewStructure = vw.entity_view(905) as ViewStructure
	t.eq(s2.phase, ViewConsts.PH_SELLING, "SELLING")
	t.eq(s2.phase_ticks, 40, "duration from the announced end tick")
	vw.router.process(_rec(SimEvent.REMOVED, 110, 0, 0, 905, SimEntity.Kind.STRUCTURE, fac, 0, SimEvent.REM_SOLD))
	t.check(not vw.has_entity(905), "SOLD disposes at once")
	Kit.free_view(vw)


func test_owner_change_recolours(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	vw.router.process(_spawn_rec(w, 906, 1, SimEvent.SPAWN_INITIAL))
	var ve: ViewEntity = vw.entity_view(906)
	var before: int = ve.team_index
	vw.router.process(_rec(SimEvent.OWNER_CHANGED, 3, 0, 0, 906, 0, 1, 0))
	t.eq(ve.owner, 1, "owner mirrored")
	t.ne(ve.team_index, before, "team index follows the new owner")
	Kit.free_view(vw)


func test_validate_codes_reports_removed_constant_once(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	t.eq(vw.router._validate_codes(), PackedStringArray(), "all consumed constants exist in the kernel")
	var fake: Dictionary = (SimEvent as GDScript).get_script_constant_map().duplicate()
	fake.erase("REMOVED")
	vw.router.const_maps = {"SimEvent": fake}
	t.eq(vw.router._validate_codes(), PackedStringArray(["SimEvent.REMOVED"]), "exactly the removed constant, once")
	vw.router.rebuild_table()
	vw.router.process(_rec(SimEvent.REMOVED, 1, 0, 0, 1))  # ignored: no handler, no crash
	t.eq(vw.router.stats()["unknown"], 1, "the orphaned code is counted unknown")
	Kit.free_view(vw)


func test_every_render_reaction_is_handled_or_documented(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	# the reactions this router (lifecycle + hit / fire) implements; the rest belongs to the FX wave and must be skipped cleanly
	var mine: PackedStringArray = ["SPAWNED", "REMOVED", "DIED", "OWNER_CHANGED", "DAMAGE", "WEAPON_FIRED", "PRODUCTION_COMPLETE", "MATCH_END"]
	for name_: String in ViewTestEvents.REACTIONS:
		var codes: Array = ViewTestEvents.codes_of(name_)
		var known: int = vw.router.stats()["events"] as int
		var unk: int = vw.router.stats()["unknown"] as int
		for code: int in codes:
			vw.router.process(ViewTestEvents.sample(code, 3))
		var handled_all: bool = true
		if name_ in mine:
			handled_all = (vw.router.stats()["unknown"] as int) == unk
		t.check(handled_all, "%s is routed by the lifecycle router" % name_)
		t.eq(vw.router.stats()["events"], known + codes.size(), "%s: every record was walked" % name_)
	Kit.free_view(vw)


func test_crash_and_sink_dying_poses(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim()
	var vw: ViewWorld = Kit.view(w)
	# an aircraft and a ship: test seam, the small data set has neither (motion class is set on the record)
	vw.router.process(_spawn_rec(w, 960, 0, SimEvent.SPAWN_PRODUCED))
	vw.router.process(_spawn_rec(w, 961, 0, SimEvent.SPAWN_PRODUCED))
	var air: ViewUnit = vw.entity_view(960) as ViewUnit
	air.motion = ViewConsts.MOTION_AIR_FIXED
	air.setup_motion()
	air.alt = 12.0
	air.sim_flags |= SimFlags.F_AIRBORNE
	var ship: ViewUnit = vw.entity_view(961) as ViewUnit
	ship.motion = ViewConsts.MOTION_NAVAL
	ship.setup_motion()
	vw.router.process(_rec(SimCombatConsts.EV_DEATH, 0, 0, 0, 960, _tank_idx(w), ViewConsts.DK_CRASH, 0, 0, 30 << 16))
	vw.router.process(_rec(SimCombatConsts.EV_DEATH, 0, 0, 0, 961, _tank_idx(w), ViewConsts.DK_SINK, 0, 0, 0))
	t.eq(air.dying_until_tick, 30, "crash window 30 ticks")
	t.eq(ship.dying_until_tick, 60, "sink window 60 ticks")
	var last_alt: float = air.alt
	w.tick = 25
	for f: int in 20:
		vw.frame(1.0 / 20.0, 0.0, PackedInt32Array())
	t.lt(air.alt, last_alt, "the aircraft loses altitude while crashing")
	t.gt(air.bank, 0.5, "and rolls")
	t.gt(ship.sink_m, 0.0, "the ship sinks")
	Kit.free_view(vw)
