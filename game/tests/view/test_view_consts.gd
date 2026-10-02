extends RefCounted
## VIEW-01 acceptance: ViewConsts conversions and angle helpers (render spec 4.1, 10.1).


func test_sim_world_conversion(t: TestCtx) -> void:
	var w: Vector2 = ViewConsts.sim_to_world_xz(51200, 30720)
	t.near(w.x, 150.0, 1.0e-4, "x 51200 -> 150 m")
	t.near(w.y, 90.0, 1.0e-4, "y 30720 -> 90 m")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var bad: int = 0
	for i in 1000:
		var x: int = rng.randi_range(0, 300000)
		var y: int = rng.randi_range(0, 300000)
		var back: Vector2i = ViewConsts.world_to_sim_xz(ViewConsts.sim_to_world_xz(x, y))
		if absi(back.x - x) > 1 or absi(back.y - y) > 1:
			bad += 1
	t.eq(bad, 0, "world_to_sim(sim_to_world(x, y)) round-trips within 1 unit for 1000 random ints")


func test_interpolation_example(t: TestCtx) -> void:
	var x: float = 51200.0 + (51302.0 - 51200.0) * 0.5
	t.near(x * ViewConsts.M_PER_UNIT, 150.15, 0.01, "x_prev 51200, x_cur 51302, alpha 0.5")


func test_yaw_helpers(t: TestCtx) -> void:
	t.near(ViewConsts.yaw_of_bat(0), -PI / 2.0, 1.0e-6, "yaw_of_bat(0)")
	t.near(ViewConsts.yaw_of_bat(1024), -PI, 1.0e-6, "yaw_of_bat(1024)")
	t.near(ViewConsts.yaw_of_bat(2048), -3.0 * PI / 2.0, 1.0e-6, "yaw_of_bat(2048)")
	t.near(ViewConsts.turret_yaw(512), -0.7854, 1.0e-4, "turret_yaw(512)")
	t.near(ViewConsts.turret_yaw(3900), 0.3007, 1.0e-4, "turret_yaw(3900)")
	t.near(ViewConsts.rel_yaw(1536, 1024), -0.7854, 1.0e-4, "rel_yaw(1536, 1024)")
	t.near(ViewConsts.rel_yaw(3900, 200), 0.6075, 1.0e-4, "rel_yaw(3900, 200)")


func test_bat_arithmetic(t: TestCtx) -> void:
	t.eq(ViewConsts.wrap_bat(3700), -396, "wrap_bat(3700)")
	t.eq(ViewConsts.wrap_bat(-2049), 2047, "wrap_bat(-2049)")
	t.eq(ViewConsts.wrap_bat(2048), -2048, "wrap_bat(2048)")
	t.near(ViewConsts.lerp_bat(4090, 10, 0.5), 4098.0, 1.0e-6, "lerp_bat goes the short way round")
	t.near(ViewConsts.lerp_bat(10, 4090, 0.5), 10.0 + ViewConsts.wrap_bat(4080) * 0.5, 1.0e-6, "lerp_bat the other direction")


func test_struct_rot(t: TestCtx) -> void:
	t.eq(ViewConsts.struct_rot(0), 0, "struct_rot(0)")
	t.eq(ViewConsts.struct_rot(700), 1, "struct_rot(700)")
	t.eq(ViewConsts.struct_rot(1024), 1, "struct_rot(1024)")
	t.eq(ViewConsts.struct_rot(3072), 3, "struct_rot(3072)")
	t.eq(ViewConsts.struct_rot(4096 + 1024), 1, "struct_rot wraps")


func test_flag_bits_are_distinct_powers_of_two(t: TestCtx) -> void:
	var bits: Array[int] = [ViewConsts.UF_FOG_DIM, ViewConsts.UF_GHOST, ViewConsts.UF_SUBMERGED, ViewConsts.UF_UNPOWERED,
		ViewConsts.UF_CLOAKED, ViewConsts.UF_EMP, ViewConsts.UF_WRECK, ViewConsts.UF_SUPPRESSED, ViewConsts.UF_DECOY_ID]
	var seen: int = 0
	for b: int in bits:
		t.eq(b & (b - 1), 0, "power of two %d" % b)
		t.eq(seen & b, 0, "distinct %d" % b)
		seen |= b
	t.eq(ViewConsts.UF_CLOAKED, 16, "UF_CLOAKED = 16 (shader contract)")


func test_layers(t: TestCtx) -> void:
	t.eq(ViewLayers.MASK_MAIN_CAMERA & ViewLayers.MASK_ICON_STUDIO, 0, "icon studio layer is isolated from the main camera")
	t.eq(ViewLayers.MASK_MAIN_CAMERA & ViewLayers.MASK_MINIMAP_ONLY, 0, "minimap-only layer is not drawn by the main camera")
	t.lt(ViewLayers.PRIO_WATER, ViewLayers.PRIO_REFRACT_A, "water before refraction")
	t.lt(ViewLayers.PRIO_REFRACT_B, ViewLayers.PRIO_FX_MIN, "refraction before FX sprites")
	t.lt(ViewLayers.PRIO_GHOST, ViewLayers.PRIO_BARS, "bars last")
