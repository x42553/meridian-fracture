extends Node3D
## Demo / regression scene for `tools/gd shot`: a lit box on a plane, a UI label and a user arg.
##   tools/gd shot res://tests/scenarios/shot_demo.tscn /tmp/demo.png --size 800x450 -- --label=hello
## Everything is built in code (no assets), the way the game's procedural art is.


func _ready() -> void:
	var text: String = "shot_demo"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			text = arg.substr("--label=".length())
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(4.0, 3.5, 6.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.5, 0.0))
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(sun)
	add_child(_mesh(PlaneMesh.new(), Color(0.25, 0.3, 0.22), Vector3.ZERO))
	add_child(_mesh(BoxMesh.new(), Color(0.9, 0.35, 0.1), Vector3(0.0, 0.5, 0.0)))
	var label: Label = Label.new()
	label.text = text
	label.position = Vector2(24.0, 20.0)
	label.add_theme_font_size_override("font_size", 48)
	add_child(label)


func _mesh(mesh: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = at
	if mesh is PlaneMesh:
		(mesh as PlaneMesh).size = Vector2(12.0, 12.0)
	return mi
