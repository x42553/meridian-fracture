class_name VfxBench
extends Node
## Particle-strategy benchmark: N simultaneous "explosion-lite" effects (fire 14 + smoke 10 + sparks 16 quads)
## rendered by different mechanisms with the same fragment cost, to isolate system overhead.
## Approaches: multimesh (FxBatch ring buffers), cluster_nodes (MeshInstance3D per cluster, instance uniforms),
## gpu (GPUParticles3D x3 per effect), cpu (CPUParticles3D x3), quads (one MeshInstance3D per quad).

const LIFE_FIRE: float = 1.5
const LIFE_SMOKE: float = 2.2
const LIFE_SPARK: float = 1.0
const PERIOD: float = 2.3

var _main: Node3D
var _root: Node3D
var _t_spawn: float = 0.0


func run(main: Node3D, args: Dictionary) -> void:
	_main = main
	var counts: PackedStringArray = String(args.get("counts", "60,240,720")).split(",")
	var approaches: PackedStringArray = String(args.get("approaches", "none,multimesh,cluster_nodes,gpu,cpu,quads")).split(",")
	var warm: float = float(args.get("warm", "2.0"))
	var measure: float = float(args.get("measure", "4.0"))
	main.fx.visible = false
	main._place_camera(Vector3.ZERO, 70.0, 55.0, 10.0)
	var results: Array = []
	for ap in approaches:
		for cs in counts:
			var n: int = int(cs)
			if ap == "none" and cs != counts[0]:
				continue
			if ap == "quads" and n > 60:
				continue
			_root = Node3D.new()
			add_child(_root)
			var setup: Callable = _setup(ap, n)
			await get_tree().process_frame
			var t_begin: float = Time.get_ticks_msec() / 1000.0
			var next_spawn: float = 0.0
			var spawn_us: int = 0
			var spawn_count: int = 0
			var eff_i: int = 0
			main._reset_samples()
			var recording: bool = false
			var t_total: float = warm + measure
			while true:
				var now: float = Time.get_ticks_msec() / 1000.0 - t_begin
				if now >= t_total:
					break
				if not recording and now >= warm:
					recording = true
					main._reset_samples()
					main._record = true
				# steady state: N effects per PERIOD seconds
				var interval: float = PERIOD / float(maxi(n, 1))
				while ap != "none" and now >= next_spawn:
					var t0: int = Time.get_ticks_usec()
					setup.call(eff_i % n, now)
					spawn_us += Time.get_ticks_usec() - t0
					spawn_count += 1
					eff_i += 1
					next_spawn += interval
				await get_tree().process_frame
			main._record = false
			var packed: Dictionary = main._pack_samples()
			packed["approach"] = ap
			packed["n"] = n if ap != "none" else 0
			packed["spawn_us_avg"] = snappedf(float(spawn_us) / maxf(float(spawn_count), 1.0), 0.1)
			packed["nodes"] = _count_nodes(_root)
			results.append(packed)
			print("RESULT|bench|", JSON.stringify(packed))
			_root.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
	var res: Dictionary = {"renderer": String(RenderingServer.get_current_rendering_method()), "results": results}
	var f := FileAccess.open(main._out_path("bench_%s%s.json" % [RenderingServer.get_current_rendering_method(), String(args.get("tag", ""))]), FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()


func _count_nodes(n: Node) -> int:
	var c: int = 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _rand_pos() -> Vector3:
	return _main._rand_ground()


func _setup(ap: String, n: int) -> Callable:
	match ap:
		"multimesh":
			return _setup_multimesh(n)
		"cluster_nodes":
			return _setup_cluster_nodes(n)
		"gpu":
			return _setup_gpu(n)
		"cpu":
			return _setup_cpu(n)
		"quads":
			return _setup_quads(n)
	return Callable()


func _fire_mat(node_mode: bool, mode: int, soft: float = 0.8) -> ShaderMaterial:
	return FxAssets.sprite_material(mode, Color.WHITE, mode, soft, 1.0, node_mode)


# ---- multimesh: FxBatch ring buffers (production path)
func _setup_multimesh(n: int) -> Callable:
	var cap_f: int = int(ceil(float(n) * LIFE_FIRE / PERIOD)) + 8
	var cap_s: int = int(ceil(float(n) * LIFE_SMOKE / PERIOD)) + 8
	var cap_p: int = int(ceil(float(n) * LIFE_SPARK / PERIOD)) + 8
	var fire := FxBatch.new(&"b_fire", FxAssets.cluster_mesh(14, 1), _fire_mat(false, 0), cap_f, _root)
	var smoke := FxBatch.new(&"b_smoke", FxAssets.cluster_mesh(10, 2), _fire_mat(false, 1), cap_s, _root)
	var spark := FxBatch.new(&"b_spark", FxAssets.cluster_mesh(16, 3), _fire_mat(false, 3, 0.0), cap_p, _root)
	fire.node.visible = true
	smoke.node.visible = true
	spark.node.visible = true
	var clock: FxManager = _main.fx
	return func(_i: int, _now: float) -> void:
		var p: Vector3 = _rand_pos()
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * 4.0), p)
		var t: float = clock.now()
		fire.emit(xf, t, LIFE_FIRE, randf() * 0.99, 1.0)
		smoke.emit(xf, t, LIFE_SMOKE, randf() * 0.99, 1.0)
		spark.emit(xf, t, LIFE_SPARK, randf() * 0.99, 1.0)


# ---- cluster_nodes: one MeshInstance3D per cluster with instance uniforms
func _setup_cluster_nodes(n: int) -> Callable:
	var meshes: Array[ArrayMesh] = [FxAssets.cluster_mesh(14, 1), FxAssets.cluster_mesh(10, 2), FxAssets.cluster_mesh(16, 3)]
	var mats: Array[ShaderMaterial] = [_fire_mat(true, 0), _fire_mat(true, 1), _fire_mat(true, 3, 0.0)]
	var lives: Array[float] = [LIFE_FIRE, LIFE_SMOKE, LIFE_SPARK]
	var pool: Array[MeshInstance3D] = []
	for i in n * 3:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i % 3]
		mi.material_override = mats[i % 3]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter(&"inst_data", Vector4(-1000.0, 1.0, 0.0, 1.0))
		mi.custom_aabb = FxAssets.BIG_AABB
		_root.add_child(mi)
		pool.append(mi)
	var clock: FxManager = _main.fx
	return func(i: int, _now: float) -> void:
		var p: Vector3 = _rand_pos()
		var t: float = clock.now()
		for k in 3:
			var mi: MeshInstance3D = pool[i * 3 + k]
			mi.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 4.0), p)
			mi.set_instance_shader_parameter(&"inst_data", Vector4(t, lives[k], randf() * 0.99, 1.0))


# ---- gpu: GPUParticles3D x3 per effect (the "textbook" approach)
func _setup_gpu(n: int) -> Callable:
	var draw_mat := ShaderMaterial.new()
	draw_mat.shader = FxAssets.shader_from("fx_gpu_bench")
	draw_mat.set_shader_parameter(&"noise_tex", FxAssets.noise_atlas())
	draw_mat.set_shader_parameter(&"ramp_tex", FxAssets.fire_ramp())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var pm_fire := _particle_material(9.0, 0.9, Vector2(0.9, 2.2))
	var pm_smoke := _particle_material(4.0, 0.6, Vector2(1.2, 3.0))
	var pm_spark := _particle_material(14.0, 0.15, Vector2(0.15, 0.4))
	var defs: Array = [[14, LIFE_FIRE, pm_fire], [10, LIFE_SMOKE, pm_smoke], [16, LIFE_SPARK, pm_spark]]
	var pool: Array[GPUParticles3D] = []
	for i in n * 3:
		var d: Array = defs[i % 3]
		var gp := GPUParticles3D.new()
		gp.amount = d[0]
		gp.lifetime = d[1]
		gp.one_shot = true
		gp.explosiveness = 1.0
		gp.emitting = false
		gp.local_coords = false
		gp.fixed_fps = 0
		gp.interpolate = false
		gp.visibility_aabb = AABB(Vector3(-12, -2, -12), Vector3(24, 16, 24))
		gp.process_material = d[2]
		gp.draw_pass_1 = quad
		gp.material_override = draw_mat
		gp.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
		_root.add_child(gp)
		pool.append(gp)
	return func(i: int, _now: float) -> void:
		var p: Vector3 = _rand_pos()
		for k in 3:
			var gp: GPUParticles3D = pool[i * 3 + k]
			gp.global_position = p
			gp.restart()
			gp.emitting = true


func _particle_material(vel: float, radius: float, scale_range: Vector2) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = vel * 0.3
	pm.initial_velocity_max = vel
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.gravity = Vector3(0.0, 2.0, 0.0)
	pm.scale_min = scale_range.x * 2.0
	pm.scale_max = scale_range.y * 2.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	return pm


# ---- cpu: CPUParticles3D x3 per effect
func _setup_cpu(n: int) -> Callable:
	var draw_mat := ShaderMaterial.new()
	draw_mat.shader = FxAssets.shader_from("fx_gpu_bench")
	draw_mat.set_shader_parameter(&"noise_tex", FxAssets.noise_atlas())
	draw_mat.set_shader_parameter(&"ramp_tex", FxAssets.fire_ramp())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = draw_mat
	var defs: Array = [[14, LIFE_FIRE, 9.0, Vector2(0.9, 2.2)], [10, LIFE_SMOKE, 4.0, Vector2(1.2, 3.0)], [16, LIFE_SPARK, 14.0, Vector2(0.15, 0.4)]]
	var pool: Array[CPUParticles3D] = []
	for i in n * 3:
		var d: Array = defs[i % 3]
		var cp := CPUParticles3D.new()
		cp.amount = d[0]
		cp.lifetime = d[1]
		cp.one_shot = true
		cp.explosiveness = 1.0
		cp.emitting = false
		cp.local_coords = false
		cp.fixed_fps = 0
		cp.mesh = quad
		cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		cp.emission_sphere_radius = 0.8
		cp.direction = Vector3.UP
		cp.spread = 180.0
		cp.initial_velocity_min = float(d[2]) * 0.3
		cp.initial_velocity_max = float(d[2])
		cp.damping_min = 3.0
		cp.damping_max = 5.0
		cp.gravity = Vector3(0.0, 2.0, 0.0)
		cp.scale_amount_min = (d[3] as Vector2).x * 2.0
		cp.scale_amount_max = (d[3] as Vector2).y * 2.0
		cp.angle_min = 0.0
		cp.angle_max = 360.0
		_root.add_child(cp)
		pool.append(cp)
	return func(i: int, _now: float) -> void:
		var p: Vector3 = _rand_pos()
		for k in 3:
			var cp: CPUParticles3D = pool[i * 3 + k]
			cp.global_position = p
			cp.restart()
			cp.emitting = true


# ---- quads: one MeshInstance3D per quad (14 + 10 + 16 per effect)
func _setup_quads(n: int) -> Callable:
	var mats: Array[ShaderMaterial] = [_fire_mat(true, 0), _fire_mat(true, 1), _fire_mat(true, 3, 0.0)]
	var counts: Array[int] = [14, 10, 16]
	var lives: Array[float] = [LIFE_FIRE, LIFE_SMOKE, LIFE_SPARK]
	var variants: Array[ArrayMesh] = []
	for i in 16:
		variants.append(FxAssets.cluster_mesh(1, 100 + i))
	var pool: Array[MeshInstance3D] = []
	for i in n * 40:
		var mi := MeshInstance3D.new()
		mi.mesh = variants[i % 16]
		var kind: int = 0 if (i % 40) < 14 else (1 if (i % 40) < 24 else 2)
		mi.material_override = mats[kind]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter(&"inst_data", Vector4(-1000.0, 1.0, 0.0, 1.0))
		mi.custom_aabb = FxAssets.BIG_AABB
		_root.add_child(mi)
		pool.append(mi)
	var clock: FxManager = _main.fx
	return func(i: int, _now: float) -> void:
		var p: Vector3 = _rand_pos()
		var t: float = clock.now()
		for q in 40:
			var kind: int = 0 if q < 14 else (1 if q < 24 else 2)
			var mi: MeshInstance3D = pool[i * 40 + q]
			mi.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 4.0), p)
			mi.set_instance_shader_parameter(&"inst_data", Vector4(t, lives[kind], randf() * 0.99, 1.0))
