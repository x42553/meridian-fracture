class_name ViewWater
extends Node3D
## One large flat water plane (sea + lakes + rivers). The look comes entirely from the shader and two rasters:
## the vertex-resolution depth texture owned by ViewTerrain and the per-cell shore-distance field from MapTerrainData.

var material: ShaderMaterial
var plane: MeshInstance3D


func build(terrain: ViewTerrain, tex: ViewDetailTextures, extent_m: float = 6000.0) -> void:
	var data: MapTerrainData = terrain.data
	var size: Vector2 = data.size_m()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(extent_m, extent_m)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	plane = MeshInstance3D.new()
	plane.name = "WaterPlane"
	plane.mesh = pm
	plane.position = Vector3(size.x * 0.5, float(data.water_level_u) / float(MapTerrainData.HEIGHT_UNITS_PER_M), size.y * 0.5)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(plane)

	var shore_img: Image = Image.create_from_data(data.width, data.height, false, Image.FORMAT_R8, data.shore_dist)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	material.set_shader_parameter("water_depth", terrain.water_depth_tex)
	material.set_shader_parameter("shore_dist", ImageTexture.create_from_image(shore_img))
	material.set_shader_parameter("detail", tex.detail)
	material.set_shader_parameter("detail_nrm", tex.normals)
	material.set_shader_parameter("map_size", size)
	material.set_shader_parameter("depth_scale", Vector2(1.0 / (terrain.step_m * terrain.vw), 1.0 / (terrain.step_m * terrain.vh)))
	material.set_shader_parameter("depth_offset", Vector2(0.5 / terrain.vw, 0.5 / terrain.vh))
	plane.material_override = material


func apply_mood(mood: ViewMoodDef) -> void:
	material.set_shader_parameter("shallow_color", mood.water_shallow)
	material.set_shader_parameter("deep_color", mood.water_deep)
	material.set_shader_parameter("absorb", mood.water_absorb)
