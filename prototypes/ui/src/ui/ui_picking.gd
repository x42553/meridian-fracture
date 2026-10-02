class_name UiPicking
extends RefCounted
## Screen -> world picking without the physics engine (the simulation is headless and there are no colliders).
## Entities are snapshots {pos: Vector3, radius: float, ...}; results are indices into that array.

## Nearest entity hit by the camera ray through `screen_pos` (ray vs bounding sphere), or -1.
static func ray_pick(camera: Camera3D, entities: Array[Dictionary], screen_pos: Vector2) -> int:
	var o: Vector3 = camera.project_ray_origin(screen_pos)
	var d: Vector3 = camera.project_ray_normal(screen_pos)
	var best: int = -1
	var best_t: float = INF
	for i in entities.size():
		var e: Dictionary = entities[i]
		var c: Vector3 = (e["pos"] as Vector3) + Vector3(0.0, float(e["radius"]) * 0.5, 0.0)
		var oc: Vector3 = o - c
		var r: float = float(e["radius"])
		var b: float = oc.dot(d)
		var disc: float = b * b - (oc.dot(oc) - r * r)
		if disc < 0.0:
			continue
		var t: float = -b - sqrt(disc)
		if t > 0.0 and t < best_t:
			best_t = t
			best = i
	return best

## Indices of entities whose projected position lies inside `rect` (screen space) and in front of the camera.
static func box_select(camera: Camera3D, entities: Array[Dictionary], rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in entities.size():
		var p: Vector3 = entities[i]["pos"]
		if camera.is_position_behind(p):
			continue
		if rect.has_point(camera.unproject_position(p + Vector3(0.0, 0.8, 0.0))):
			out.append(i)
	return out
