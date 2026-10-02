extends RefCounted
## Shared fixture of the FX tests: a camera looking down at the origin, an FxManager stepped explicitly and the real fx.json.

var cam: Camera3D = null
var fx: FxManager = null
var book: FxRecipeBook = null


static func make(quality: FxManager.Quality = FxManager.Quality.HIGH, focus: float = 60.0, doc: Dictionary = {}) -> RefCounted:
	var kit: RefCounted = (load("res://tests/view/fx_kit.gd") as GDScript).new() as RefCounted
	kit.set("cam", Camera3D.new())
	var c: Camera3D = kit.get("cam") as Camera3D
	c.fov = 38.0
	c.far = 1000.0
	# 52 degrees down, 60 m out, looking at the origin
	var pos: Vector3 = Vector3(0.0, 60.0 * sin(deg_to_rad(52.0)), 60.0 * cos(deg_to_rad(52.0)))
	c.transform = Transform3D(Basis.IDENTITY, pos).looking_at(Vector3.ZERO, Vector3.UP)
	var b: FxRecipeBook = FxRecipeBook.new()
	if doc.is_empty():
		b.load_file()
	else:
		b.load_dict(doc)
	kit.set("book", b)
	var m: FxManager = FxManager.new()
	m.viewport_size_override = Vector2(1920.0, 1080.0)
	m.camera_focus_dist = focus
	m.setup(c, quality, b, null, null)
	kit.set("fx", m)
	return kit


func free_all() -> void:
	fx.free()
	cam.free()


## Point on the camera axis `d` metres in front of the camera.
func on_axis(d: float) -> Vector3:
	return cam.transform.origin + (-cam.transform.basis.z) * d
