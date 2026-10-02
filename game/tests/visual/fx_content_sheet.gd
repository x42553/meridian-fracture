extends "res://tests/visual/fx_sheet.gd"
## VIEW-F3 acceptance: contact sheets of the shipped fx.json content (weapons, impacts, deaths, powers, zones, superweapons, misc).
##   tools/gd run res://tests/visual/fx_content_sheet.tscn --gui --size 1280x720 -- --group=weapons --sheet=0 --per=6 --out=/abs/w0.png
##   tools/gd run res://tests/visual/fx_content_sheet.tscn --gui --size 1280x720 -- --group=impacts --list        (prints the ids of the group)
## Groups: weapons (27 archetypes: muzzle + projectile + impact through the same tables the router uses), impacts, deaths, powers,
## zones, superweapons, misc. --sheet=N pages of --per=6 rows; each row = 3 time offsets. Also --mode=single --group=g --id=<row id>.

# archetype tables (DefWeaponArch index): splash radius in cells, speed in cells per second (0 = instant), range class
const SPLASH: Array[float] = [0, 0, 0, 0.5, 1.2, 2.5, 0, 0, 1.6, 1.6, 1.3, 1.4, 0.7, 0, 0, 0, 2.5, 2.2, 0, 0, 1.2, 1.2, 0, 0.9, 2.0, 1.5, 0]
const SPEED: Array[float] = [40, 40, 30, 16, 14, 12, 10, 14, 20, 9, 10, 9, 12, 0, 0, 8, 6, 8, 14, 0, 30, 12, 0, 14, 10, 12, 14]
const RANGE_M: Array[float] = [16, 18, 20, 26, 28, 12, 26, 30, 24, 44, 36, 32, 48, 26, 36, 22, 10, 6, 18, 8, 10, 10, 3, 28, 56, 60, 14]
const NAMES: Array[String] = ["small_arms", "machine_gun", "autocannon", "tank_cannon", "siege_gun", "demolition_cannon", "at_missile",
	"aa_missile", "flak", "artillery_shell", "rocket_barrage", "mortar", "missile_artillery", "beam_thermal", "rail_gun", "torpedo",
	"depth_charge", "bomb", "air_missile", "emp_pulse", "canister", "grenade_launcher", "breach_charge", "naval_gun", "naval_bombard",
	"cruise_missile", "drone_missile"]

var catalog: FxCatalog = null
var _emu: Node3D = null


func _table() -> Array[Dictionary]:
	if catalog == null:
		catalog = FxCatalog.new(book)
	match str(_args.get("group", "weapons")):
		"weapons":
			return _weapons()
		"impacts":
			return _impacts()
		"deaths":
			return _deaths()
		"powers":
			return _powers()
		"zones":
			return _zones()
		"superweapons":
			return _superweapons()
		"misc":
			return _misc()
	return []


func _row(id: String, dist: float, times: Array, s: float = 1.0, extra: Dictionary = {}) -> Dictionary:
	var e: Dictionary = {"id": StringName(id), "a": Vector3.ZERO, "b": Vector3.ZERO, "s": s, "look": Vector3(0, 1, 0), "dist": dist, "times": times}
	e.merge(extra, true)
	return e


# ------------------------------------------------------------------ weapons
func _weapons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 27:
		var rng: float = RANGE_M[i]
		var e: Dictionary = _row("shot:%d" % i, clampf(rng * 1.5 + 14.0, 22.0, 90.0), [0.05, 0.25, 0.7])
		var half: float = rng * 0.5
		e.a = Vector3(-half, 1.6 if i != 17 and i != 16 else 14.0, 0.0)
		e.b = Vector3(half, 0.5, -2.0)
		e.look = Vector3(0, 1.0 + minf(rng * 0.06, 5.0), -1.0)
		var flight: float = 0.0
		if SPEED[i] > 0.0:
			flight = rng / (SPEED[i] * 3.0)
		e.flight = maxf(flight, 0.05)
		e.arch = i
		# timing: muzzle, mid flight, after the impact
		var t2: float = clampf(e.flight * 0.55, 0.12, 2.0)
		var t3: float = clampf(e.flight + 0.3, 0.35, 3.5)
		e.times = [0.06, t2, t3]
		if i <= 2 or i == 20 or i == 14:
			var tf: float = rng / 150.0
			e.times = [0.04, 0.03 + tf * 0.5, tf + 0.14]
			e.dist = 17.0 if i != 14 else 34.0
			e.look = Vector3(0, 0.8, -1.0)
		if i == 13:
			e.times = [0.2, 0.8, 1.6]
		if i == 15 or i == 16:
			e.site = "water"
			e.a = Vector3(-half, 0.4, 0.0)
			e.b = Vector3(half, 0.0, -2.0)
			if i == 16:
				e.a = Vector3(-half, 6.0, 0.0)
		if i == 9 or i == 24 or i == 25 or i == 12:
			e.look = Vector3(0, 8.0, -1.0)
		out.append(e)
	return out


func _impacts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var flat: Array = [["hit_bullet", 9.0, 1.0], ["hit_bullet_hv", 9.0, 1.0], ["hit_bullet_structure", 9.0, 1.0], ["hit_infantry", 9.0, 1.0],
		["hit_flak_small", 14.0, 1.0], ["hit_armor", 9.0, 1.0], ["hit_ground_miss", 9.0, 1.0], ["hit_rail", 16.0, 1.0],
		["beam_thermal_hit", 16.0, 1.0], ["aps_flash", 14.0, 1.0], ["expl_small", 20.0, 1.0], ["expl_medium", 28.0, 1.0],
		["expl_large", 50.0, 1.0], ["expl_air_burst", 22.0, 1.0], ["expl_kinetic", 60.0, 5.0], ["expl_strategic_large", 90.0, 9.0],
		["expl_fragment_ring", 90.0, 19.0], ["emp_pulse", 38.0, 10.0], ["impact_ground", 8.0, 1.0]]
	for r: Array in flat:
		var e: Dictionary = _row(r[0] as String, r[1] as float, [0.06, 0.3, 1.0], r[2] as float)
		if r[0] == "expl_air_burst" or r[0] == "hit_flak_small" or r[0] == "aps_flash":
			e.a = Vector3(0, 10, 0)
			e.look = Vector3(0, 10, 0)
		if r[0] == "expl_large" or r[0] == "expl_kinetic" or r[0] == "expl_strategic_large":
			e.times = [0.12, 0.55, 1.8]
		if r[0] == "emp_pulse":
			e.prop = "tanks"
			e.times = [0.12, 0.45, 0.95]
		if r[0] == "hit_infantry" or r[0] == "hit_bullet" or r[0] == "hit_bullet_hv" or r[0] == "hit_armor":
			e.a = Vector3(0, 0.8, 0)
		out.append(e)
	for w: Array in [["expl_underwater", 22.0, 1.0], ["expl_underwater_big", 34.0, 1.0], ["impact_water", 12.0, 1.0], ["water_spray", 12.0, 1.0]]:
		var e2: Dictionary = _row(w[0] as String, w[1] as float, [0.1, 0.45, 1.3], w[2] as float, {"site": "water"})
		e2.a = Vector3(0, 0.05, 0)
		out.append(e2)
	return out


func _deaths() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Array in [["death_vehicle_light", 22.0], ["death_vehicle_medium", 28.0], ["death_vehicle_heavy", 36.0]]:
		out.append(_row(v[0] as String, v[1] as float, [0.12, 0.7, 3.0], 1.0, {"prop": "tank_destroy", "wreck": true}))
	out.append(_row("death_infantry", 12.0, [0.06, 0.3, 0.9]))
	out.append(_row("death_drone", 14.0, [0.08, 0.3, 1.0], 1.0, {"a": Vector3(0, 6, 0), "look": Vector3(0, 6, 0)}))
	out.append(_row("death_air_explode", 26.0, [0.1, 0.5, 1.8], 1.0, {"a": Vector3(0, 12, 0), "look": Vector3(0, 12, 0)}))
	out.append(_row("aircraft_crash", 88.0, [0.5, 1.3, 2.4], 1.0, {"a": Vector3(-30, 40, 0), "b": Vector3(15, 0, -5), "look": Vector3(-6, 12, -2), "prop": "plane_crash"}))
	out.append(_row("aircraft_impact", 50.0, [0.12, 0.7, 2.6]))
	out.append(_row("death_silent", 12.0, [0.08, 0.35, 0.9], 1.0, {"a": Vector3(0, 0.5, 0)}))
	out.append(_row("death_sink_small", 34.0, [0.15, 0.8, 3.0], 1.0, {"site": "water", "a": Vector3(0, 0.05, 0)}))
	out.append(_row("death_sink_large", 52.0, [0.15, 0.9, 3.5], 1.0, {"site": "water", "a": Vector3(0, 0.05, 0)}))
	out.append(_row("building_collapse", 58.0, [0.35, 1.1, 3.2], 1.0, {"look": Vector3(0, 3, 0), "prop": "building_collapse"}))
	out.append(_row("wreck_start", 22.0, [0.5, 2.5, 6.0], 1.0, {"prop": "tank_destroy"}))
	out.append(_row("damage_fire", 16.0, [0.3, 1.0, 2.0], 1.5, {"loop": ["damage_fire", 0.4, 6.0, 1.5], "prop": "tanks"}))
	out.append(_row("damage_smoke", 16.0, [0.5, 1.5, 3.0], 1.5, {"loop": ["damage_smoke", 0.4, 8.0, 1.5], "prop": "tanks"}))
	out.append(_row("oil_fire_tick", 22.0, [0.5, 2.0, 5.0], 1.5, {"loop": ["oil_fire_tick", 0.3, 8.0, 1.5], "site": "water", "a": Vector3(0, 0.05, 0)}))
	return out


func _powers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_row("power_cast_ring", 60.0, [0.15, 0.5, 1.0], 12.0, {"prop": "tanks"}))
	out.append(_row("power_scan_ring", 90.0, [0.4, 1.0, 2.2], 24.0))
	for n: String in ["damage", "speed", "defense", "range", "camo", "penalty"]:
		out.append(_row("power_aura_" + n, 14.0, [0.15, 0.6, 1.2], 2.4, {"prop": "tanks"}))
	out.append(_row("power_struct_glow", 20.0, [0.2, 0.7, 1.4], 4.0))
	out.append(_row("power_mark_ring", 20.0, [0.3, 1.5, 3.0], 1.6, {"prop": "tanks"}))
	out.append(_row("decoy_spawn", 14.0, [0.06, 0.25, 0.7]))
	out.append(_row("summon_arrive", 28.0, [0.1, 0.4, 1.0], 3.0))
	out.append(_row("repair_pulse", 20.0, [0.1, 0.4, 0.9], 4.0, {"prop": "tanks"}))
	out.append(_row("capture_flash", 30.0, [0.1, 0.4, 0.9], 5.0))
	out.append(_row("build_complete", 30.0, [0.1, 0.5, 1.2], 6.0))
	out.append(_row("power_down", 26.0, [0.1, 0.5, 1.4], 5.0))
	out.append(_row("power_restore", 26.0, [0.1, 0.4, 1.0], 5.0))
	out.append(_row("status_emp_tick", 16.0, [0.4, 1.0, 1.8], 3.0, {"loop": ["status_emp_tick", 0.12, 3.0, 3.0], "prop": "tanks"}))
	return out


func _zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z: Array in [["smoke", 9.0, 60.0, 5.0], ["repair", 9.0, 50.0, 3.0], ["shelter", 3.6, 30.0, 2.5], ["cover", 3.6, 30.0, 2.5], ["puck", 12.0, 60.0, 4.0],
			["buff", 9.0, 50.0, 3.0], ["reveal", 12.0, 60.0, 4.0], ["debris", 12.0, 60.0, 5.0], ["intercept", 18.0, 100.0, 4.0], ["decoy", 3.0, 22.0, 2.0]]:
		var kind: String = z[0] as String
		var cfg: Dictionary = (book.mappings.get("zones", {}) as Dictionary).get(str(["buff", "smoke", "intercept", "debris", "decoy", "puck", "shelter", "cover", "repair", "reveal"].find(kind)), {}) as Dictionary
		var e: Dictionary = _row("zone_%s_burst" % kind, z[2] as float, [0.4, 2.0, z[3] as float + 1.0], z[1] as float, {"prop": "tanks"})
		e.loop = [str(cfg.get("tick", "zone_%s_tick" % kind)), float(cfg.get("interval", 0.5)), 12.0, z[1] as float]
		out.append(e)
	return out


func _superweapons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_row("sw_warning_marker", 60.0, [0.5, 5.0, 9.5], 12.0, {"b": Vector3(10, 0, 0), "prop": "tanks", "raw_b": true}))
	out.append(_row("sw_atlas_pre", 82.0, [0.4, 1.0, 1.9], 1.0, {"b": Vector3(1.0, 0.0, 0.0), "raw_b": true, "look": Vector3(0, 8, 0),
		"extra": [{"t": 1.0, "id": "sw_atlas_impact", "off": Vector3(-9, 0, 0)}, {"t": 1.2, "id": "sw_atlas_impact"}, {"t": 1.4, "id": "sw_atlas_impact", "off": Vector3(9, 0, 0)}]}))
	out.append(_row("sw_charge_dome", 70.0, [0.4, 1.4, 3.2], 5.0, {"b": Vector3(1.2, 0, 0), "raw_b": true, "look": Vector3(0, 5, 0),
		"extra": [{"t": 1.3, "id": "sw_microwave_dome", "s": 1.0}]}))
	out.append(_row("sw_helios_start", 70.0, [0.5, 1.6, 3.4], 1.0, {"b": Vector3(1.0, 0, 0), "raw_b": true, "look": Vector3(0, 8, 0), "tracker": "beam_helios_tick"}))
	out.append(_row("sw_perun_streak", 104.0, [0.5, 1.3, 2.2], 1.2, {"a": Vector3(-140, 90, 0), "b": Vector3(0.01, 0, 0), "look": Vector3(-20, 10, 0),
		"extra": [{"t": 1.2, "id": "sw_perun_core", "at_b": true}, {"t": 1.5, "id": "sw_perun_wave", "at_b": true}]}))
	out.append(_row("sw_shockwave", 110.0, [0.15, 0.7, 1.9], 1.0, {"look": Vector3(0, 2, 0)}))
	out.append(_row("sw_tempest_launch", 60.0, [0.2, 0.8, 2.0], 1.0, {"look": Vector3(0, 4, 0)}))
	out.append(_row("sw_dragonfall_capsule", 60.0, [0.25, 0.5, 1.4], 1.0, {"look": Vector3(0, 6, 0), "extra": [{"t": 3.0, "id": "sw_assemble_burst"}]}))
	out.append(_row("sw_horizon_pre", 96.0, [0.5, 1.2, 2.4], 1.0, {"b": Vector3(1.0, 0, 0), "raw_b": true, "look": Vector3(0, 6, 0),
		"extra": [{"t": 1.0, "id": "sw_horizon_impact", "off": Vector3(-15, 0, 0), "s": 1.0}, {"t": 5.5, "id": "sw_horizon_impact", "s": 1.0}]}))
	out.append(_row("sw_intercept_dome", 100.0, [0.6, 2.0, 5.0], 18.0, {"look": Vector3(0, 5, 0), "loop": ["sw_intercept_pulse", 3.0, 12.0, 18.0],
		"extra": [{"t": 1.2, "id": "sw_intercept_flash", "off": Vector3(8, 9, -6), "s": 1.6}, {"t": 2.0, "id": "sw_intercept_flash", "off": Vector3(-10, 6, 8), "s": 1.6}]}))
	return out


func _misc() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Array in [["build_dust", 40.0, 8.0], ["sell_dust", 40.0, 8.0], ["exit_dust", 16.0, 1.0], ["unload_puff", 12.0, 1.0], ["rotor_wash", 20.0, 1.0],
			["landing_dust", 20.0, 1.0], ["spawn_shimmer", 14.0, 1.0], ["cloak_flash", 14.0, 1.0], ["rearm_sparks", 10.0, 1.0], ["repair_mote", 10.0, 1.0],
			["credit_sparkle", 12.0, 1.0], ["salvage_sparkle", 12.0, 1.0], ["construction_sparks", 9.0, 1.0], ["weld_tick", 8.0, 1.0],
			["aircraft_contrail", 105.0, 1.0], ["vehicle_dust", 42.0, 1.0], ["wake_foam", 30.0, 1.0]]:
		var e: Dictionary = _row(m[0] as String, m[1] as float, [0.15, 0.7, 1.8], m[2] as float)
		e.a = Vector3(0, 0.3, 0)
		if m[0] == "construction_sparks":
			e.a = Vector3(0, 1.2, 0)
			e.prop = "welder"
		if m[0] == "aircraft_contrail":
			e.prop = "plane_line"
			e.nospawn = true
			e.a = Vector3(0, 22, 0)
			e.look = Vector3(0, 12, 0)
			e.times = [0.7, 1.4, 2.4]
		if m[0] == "vehicle_dust":
			e.prop = "tank_move"
			e.nospawn = true
			e.times = [0.9, 1.8, 3.0]
		if m[0] == "wake_foam":
			e.site = "water"
			e.a = Vector3(0, 0.05, 0)
		if m[0] == "rotor_wash" or m[0] == "landing_dust":
			e.a = Vector3(0, 0.3, 0)
		out.append(e)
	return out


# ------------------------------------------------------------------ spawning
func _entry_points(e: Dictionary) -> Array:
	var pts: Array = super._entry_points(e)
	if e.get("raw_b", false):
		pts[2] = e.b  # area effects carry a duration in b.x: no ground conversion
	return pts


func _capture_entry(e: Dictionary) -> Array[Image]:
	fx.clear_all()
	_clear_props()
	scorch.setup(terrain.world_size(), 1024)  # fresh ground marks for every row
	terrain.set_scorch_texture(scorch.texture)
	var pts: Array = _entry_points(e)
	var site: Vector3 = pts[0] as Vector3
	_place_camera(pts[3] as Vector3, e.dist as float)
	label.text = _label_of(e)
	await _frames(3)
	var t0: float = fx.now()
	_apply_prop(str(e.get("prop", "")), e, site)
	_mover_t0 = t0
	_spawn_entry(e, pts)
	var out: Array[Image] = []
	for tt: Variant in e.times as Array:
		while fx.now() - t0 < float(tt) - 0.0005:
			_step(1.0 / 60.0)
		label.text = "%s   t=%.2fs" % [_label_of(e), float(tt)]
		await RenderingServer.frame_post_draw
		out.append(get_viewport().get_texture().get_image())
	return out


func _label_of(e: Dictionary) -> String:
	if e.has("arch"):
		return "%d %s" % [e.arch, NAMES[e.arch as int]]
	return String(e.id)


func _run_single() -> void:
	var group: String = str(_args.get("group", "weapons"))
	var want: String = str(_args.get("id", ""))
	var table: Array[Dictionary] = _table()
	var e: Dictionary = table[0] if not table.is_empty() else {}
	for row: Dictionary in table:
		if String(row.id) == want or (row.has("arch") and str(row.arch) == want):
			e = row
	if _args.has("s"):
		e.s = float(_args["s"])
	if _args.has("dist"):
		e.dist = float(_args["dist"])
	var t_hold: float = float(_args.get("t", str((e.times as Array)[1])))
	fx.force = true
	fx.prewarm()
	await _frames(6)
	fx.clear_all()
	fx.force = false
	var pts: Array = _entry_points(e)
	_place_camera(pts[3] as Vector3, e.dist as float)
	await _frames(2)
	var t0: float = fx.now()
	_apply_prop(str(e.get("prop", "")), e, pts[0] as Vector3)
	_mover_t0 = t0
	_spawn_entry(e, pts)
	while fx.now() - t0 < t_hold - 0.0005:
		_step(1.0 / 60.0)
	label.text = "%s   t=%.2fs" % [_label_of(e), t_hold]
	print("FX_SINGLE ", group, " ", _label_of(e), " t=", t_hold, " live=", fx.live_instances())


func _spawn_entry(e: Dictionary, pts: Array) -> void:
	var a: Vector3 = pts[1] as Vector3
	var b: Vector3 = pts[2] as Vector3
	if e.has("arch"):
		_spawn_shot(e, a, b)
		return
	if not e.get("nospawn", false):
		fx.spawn(e.id as StringName, a, b, e.s as float)
	if e.has("loop"):
		var l: Array = e.loop as Array
		fx.start_loop(StringName(l[0] as String), a, Vector3.ZERO, l[3] as float, l[1] as float, l[2] as float, 0.0)
	if e.has("tracker"):
		# Helios: the hot spot crosses 24 m in 3 s; the beam comes down from 80 m above the spot
		var t_start: float = fx.now()
		var p0: Vector3 = a + Vector3(-12, 0, 0)
		var p1: Vector3 = a + Vector3(12, 0, 0)
		var from_cb: Callable = func() -> Vector3:
			return p0.lerp(p1, clampf((fx.now() - t_start - 1.0) / 3.0, 0.0, 1.0)) + Vector3(0, 80, 0)
		var to_cb: Callable = func() -> Vector3:
			return p0.lerp(p1, clampf((fx.now() - t_start - 1.0) / 3.0, 0.0, 1.0))
		fx.schedule_call(1.0, func() -> void: fx.start_tracker(StringName(e.tracker as String), from_cb, to_cb, 0.07, 3.0, 1.0))
	for x: Variant in e.get("extra", []) as Array:
		var d: Dictionary = x as Dictionary
		var off: Vector3 = d.get("off", Vector3.ZERO) as Vector3
		var base: Vector3 = b if d.get("at_b", false) else a
		fx.schedule(float(d.t), StringName(d.id as String), base + off, d.get("b", b) as Vector3, float(d.get("s", 1.0)))


## Muzzle + projectile + impact of weapon archetype `e.arch`, through the same catalog / mapping tables as the router.
func _spawn_shot(e: Dictionary, a: Vector3, b: Vector3) -> void:
	var i: int = e.arch as int
	var flight: float = e.flight as float
	var proj: Dictionary = (book.mappings.get("projectiles", {}) as Dictionary).get(NAMES[i], {}) as Dictionary
	var look: String = str(proj.get("look", "tracer"))
	var mz: StringName = catalog.muzzle_id(i)
	var burst: int = 4 if (i == 1 or i == 10) else (5 if i == 20 else 1)
	for k: int in burst:
		var jitter: Vector3 = Vector3(0, 0, (float(k) - 1.5) * 0.7) if burst > 1 else Vector3.ZERO
		var delay: float = float(k) * (0.07 if i == 1 else 0.12)
		var aim: Vector3 = b + jitter
		if mz != &"":
			if delay > 0.0:
				fx.schedule(delay, mz, a, aim, 1.0)
			else:
				fx.spawn(mz, a, aim, 1.0)
		var fl: float = flight
		match look:
			"tracer", "rail":
				var id: StringName = StringName(str(proj.fx))
				if look == "rail":
					fx.schedule(delay, id, a, aim, 1.0)
				else:
					fx.schedule(delay + 0.001, id, a + Vector3(0, 0, 0), aim, fl if SPEED[i] > 0.0 and SPEED[i] < 35.0 else a.distance_to(aim) / 150.0)
			"arc":
				fx.schedule(delay + 0.001, StringName(str(proj.fx)), a, aim, fl)
			"mesh":
				if k == 0:
					_emu_projectile(i, a, aim, fl, proj)
			"beam":
				if k == 0:
					fx.start_tracker(&"beam_thermal_seg", func() -> Vector3: return a, func() -> Vector3: return b, 0.07, 1.4, 1.0)
					fx.schedule(0.02, &"muzzle_beam_thermal", a, b, 1.0)
		if look != "beam" and look != "none":
			var splash_u: int = int(SPLASH[i] * 1024.0)
			var res: int = 3 if e.get("site", "") == "water" else 2
			var imp: StringName = catalog.impact_id(i, res, splash_u)
			if i == 7 or i == 8 or i == 18:
				imp = catalog.impact_id(i, 1, splash_u, true)
			var sc: float = catalog.explosion_scale(imp, splash_u) if str(imp).begins_with("expl_") else 1.0
			var hit_at: float = maxf(fl, 0.02) + delay
			fx.schedule(hit_at, imp, aim, Vector3.ZERO, sc)
		elif look == "none" and i == 19:
			fx.schedule(0.05, &"emp_pulse", b, Vector3.ZERO, 10.0)


func _emu_projectile(_i: int, a: Vector3, b: Vector3, flight: float, proj: Dictionary) -> void:
	# a small dark body flies the arc; the trail effect is stamped behind it exactly as ViewProjectiles does
	var body: Node3D = Node3D.new()
	_box(Vector3(0.28, 0.28, 1.5), Vector3.ZERO, Color(0.25, 0.26, 0.28), body)
	add_child(body)
	_props.append(body)
	_emu = body
	body.global_position = a
	var apex: float = float(proj.get("apex", 0.0)) * a.distance_to(b)
	var t0: float = fx.now()
	var upd: Callable = func() -> void:
		if not is_instance_valid(body):
			return
		var u: float = clampf((fx.now() - t0) / maxf(flight, 0.05), 0.0, 1.0)
		var p: Vector3 = a.lerp(b, u) + Vector3(0, 4.0 * apex * u * (1.0 - u), 0)
		body.look_at_from_position(p, p + (b - a).normalized() + Vector3(0, (1.0 - 2.0 * u) * apex * 0.02, 0), Vector3.UP)
		body.visible = u < 1.0
	_mover_upd = upd
	fx.spawn(StringName(str(proj.trail)), a, b, flight)


var _mover_upd: Callable = Callable()


func _step(dt: float) -> void:
	super._step(dt)
	if _mover_upd.is_valid():
		_mover_upd.call()


func _clear_props() -> void:
	super._clear_props()
	_mover_upd = Callable()
	_emu = null


func _run() -> void:
	if _args.has("list"):
		for e: Dictionary in _table():
			print("FX_ROW ", _label_of(e))
		get_tree().quit(0)
		return
	if str(_args.get("mode", "sheet")) == "single":
		await _run_single()
		return
	await super._run()
