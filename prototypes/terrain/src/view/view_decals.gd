class_name ViewDecals
extends Node3D
## Pool of Decal nodes for scorch marks / craters (Forward+ and Mobile only). Ring buffer: the oldest decal is
## recycled when the pool is full. All decals share one texture. Cost model: clustered elements (shared with lights
## and reflection probes, project setting rendering/limits/cluster_builder/max_clustered_elements, default 512) plus
## per-pixel work for every decal volume overlapping a pixel.

var pool: Array[Decal] = []
var capacity: int = 0
var _next: int = 0
var _tex: ImageTexture


func setup(cap: int) -> void:
	capacity = cap
	_tex = ImageTexture.create_from_image(ViewScorchLayer.make_stamp_image(96, 77))


## world position on the ground, radius in metres. The decal box is 8 m tall so it projects onto slopes.
func add(pos: Vector3, radius_m: float, yaw: float) -> void:
	var d: Decal
	if pool.size() < capacity:
		d = Decal.new()
		d.texture_albedo = _tex
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.normal_fade = 0.3
		d.distance_fade_enabled = true
		d.distance_fade_begin = 140.0
		d.distance_fade_length = 40.0
		add_child(d)
		pool.append(d)
	else:
		d = pool[_next]
		_next = (_next + 1) % capacity
	d.size = Vector3(radius_m * 2.0, 8.0, radius_m * 2.0)
	d.global_position = pos + Vector3(0.0, 1.0, 0.0)
	d.rotation = Vector3(0.0, yaw, 0.0)


func clear() -> void:
	for d in pool:
		d.queue_free()
	pool.clear()
	_next = 0
