class_name ViewWater
extends Node3D
## One large flat water plane (sea + lakes + rivers), render spec 3.4 / 5.5. The look comes from water.gdshader and two rasters:
## the vertex-resolution depth raster owned by ViewTerrain and the per-cell shore-distance field. A map without water gets no
## plane (`visible = false`). Presentation only.

const SHADER_PATH: String = "res://assets/shaders/water.gdshader"

var material: ShaderMaterial = null
var plane: MeshInstance3D = null
var sea_level_m: float = ViewTerrainSource.NO_WATER


## `low_shader` compiles WATER_LOW (one normal layer, no foam lace). `extent_m`: side of the plane (the sea surrounds the island).
func build(t: ViewTerrain, tex: ViewDetailTextures, low_shader: bool, extent_m: float = 6000.0) -> void:
	ViewGlobals.ensure()
	var src: ViewTerrainSource = t.src
	var size: Vector2 = src.size_m()
	sea_level_m = src.sea_level_m
	if plane != null:
		plane.queue_free()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(extent_m, extent_m)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	plane = MeshInstance3D.new()
	plane.name = "WaterPlane"
	plane.mesh = pm
	plane.position = Vector3(size.x * 0.5, sea_level_m, size.y * 0.5)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	plane.layers = ViewLayers.MASK_WORLD
	add_child(plane)
	var base: Shader = load(SHADER_PATH) as Shader
	var shader: Shader = base
	if low_shader:
		shader = Shader.new()
		shader.code = base.code.replace("shader_type spatial;", "shader_type spatial;\n#define WATER_LOW")
	material = ShaderMaterial.new()
	material.shader = shader
	material.render_priority = ViewLayers.PRIO_WATER
	material.set_shader_parameter("water_depth", t.water_depth_tex)
	material.set_shader_parameter("shore_dist", t.layers.shore_dist_tex)
	material.set_shader_parameter("detail", tex.detail)
	material.set_shader_parameter("detail_nrm", tex.normals)
	material.set_shader_parameter("map_size", size)
	material.set_shader_parameter("depth_scale", Vector2(1.0 / (t.step_m * float(t.vw)), 1.0 / (t.step_m * float(t.vh))))
	material.set_shader_parameter("depth_offset", Vector2(0.5 / float(t.vw), 0.5 / float(t.vh)))
	plane.material_override = material
	visible = src.has_water()


func apply_mood(m: ViewMoodDef) -> void:
	if material == null:
		return
	material.set_shader_parameter("shallow_color", m.water_shallow)
	material.set_shader_parameter("deep_color", m.water_deep)
	material.set_shader_parameter("absorb", m.water_absorb)


## Fog of war affects water like terrain; turned off for the lobby preview or debugging.
func set_fog_enabled(on: bool) -> void:
	if material != null:
		material.set_shader_parameter("fow_enabled", 1.0 if on else 0.0)
