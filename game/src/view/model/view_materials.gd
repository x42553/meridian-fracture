class_name ViewMaterials
extends RefCounted
## Unit materials per look and compile variant (render spec 3.5, 4.4).
##
## One unit.gdshader source, four compile variants selected by a `#define` prefix (NODE = no define, BATCH = MM,
## MATERIAL_UNIFORMS = MATU, GHOST). Team colour is a plain per-material uniform (`team_color`), so a NODE material exists
## per (style, team_index): Forward+ still auto-instances per (mesh, material) and Compatibility never hits the
## instance-uniform cap (terrain spike pitfall 2). Animation / state stay per-instance (instance uniforms, node backend).
##
## ViewGlobals.ensure() runs in setup() and before the first material: the shader reads fx_time, atm_night, fow_*.

enum Variant { NODE, BATCH, MATERIAL_UNIFORMS, GHOST }

const SHADER_PATH: String = "res://assets/shaders/unit.gdshader"
const DEFINES: Array[String] = ["", "#define MM 1\n", "#define MATU 1\n", "#define GHOST 1\n"]
const P_TEAM: StringName = &"team_color"

var _source: Object = null  # anything with `style(style_id: StringName) -> Dictionary` (ViewRecipeBook); optional
var _styles: Dictionary = {}  # StringName -> style Dictionary registered through set_style()
var _quality: ViewQuality = null
var _shaders: Array[Shader] = [null, null, null, null]
var _cache: Dictionary = {}  # key String -> ShaderMaterial
var _team_of: Dictionary = {}  # key String -> team_index (materials that carry a team colour)
var _scaffold: ShaderMaterial = null


## `style_source` may be a ViewRecipeBook or null (default look, styles registered through set_style()).
func setup(style_source: Object, q: ViewQuality) -> void:
	ViewGlobals.ensure()
	_source = style_source
	_quality = q


## Registers a style Dictionary (`material{wear, dirt, panel, wear_color, dirt_color, emissive}` per spec 4.10). Wins over the
## style source. Clears cached materials of that style so the next request picks the new values up.
func set_style(style_id: StringName, style: Dictionary) -> void:
	_styles[style_id] = style
	var prefix: String = "%s|" % style_id
	for k: String in _cache.keys():
		if k.begins_with(prefix):
			_cache.erase(k)
			_team_of.erase(k)


func _style(style_id: StringName) -> Dictionary:
	if _styles.has(style_id):
		return _styles[style_id] as Dictionary
	if _source != null and _source.has_method("style"):
		var s: Variant = _source.call("style", style_id)
		if s is Dictionary:
			return s as Dictionary
	return {}


func shader(variant: int = Variant.NODE) -> Shader:
	var v: int = clampi(variant, 0, 3)
	if _shaders[v] == null:
		ViewGlobals.ensure()
		var base: Shader = load(SHADER_PATH) as Shader
		if v == Variant.NODE:
			_shaders[v] = base
		else:
			var sh: Shader = Shader.new()
			sh.code = DEFINES[v] + base.code
			_shaders[v] = sh
	return _shaders[v]


## Cached material for (style, variant, team_index). NODE / BATCH / MATERIAL_UNIFORMS are per team_index (>= -1; -1 = neutral
## owner); GHOST has no team. The MATERIAL_UNIFORMS entry is a prototype: use new_entity_material() for a per-entity copy.
func unit_material(style_id: StringName, variant: int = Variant.NODE, team_index: int = 0) -> ShaderMaterial:
	var ti: int = -2 if variant == Variant.GHOST else team_index
	var key: String = "%s|%d|%d" % [style_id, variant, ti]
	var m: ShaderMaterial = _cache.get(key) as ShaderMaterial
	if m != null:
		return m
	m = ShaderMaterial.new()
	m.shader = shader(variant)
	m.resource_name = key
	_apply_style(m, _style(style_id))
	if variant != Variant.GHOST:
		m.set_shader_parameter(P_TEAM, plate_color(style_id, team_index))
		_team_of[key] = team_index
	if _quality != null:
		m.set_shader_parameter(&"quality", _quality.get_float(&"unit_shader_quality"))
	_cache[key] = m
	return m


## Colour the plates of `style_id` receive for a player colour: the player colour itself, lightness-shifted where it would not separate
## from the style's dominant paint (ViewTeamContrast, VQ2A). Neutral ownership (-1) is never shifted.
func plate_color(style_id: StringName, team_index: int) -> Color:
	var tc: Color = ViewTeamColors.color(team_index)
	if team_index < 0:
		return tc
	return ViewTeamContrast.plate_color(style_id, _style(style_id), tc)


## Per-entity duplicate of the MATERIAL_UNIFORMS material (Compatibility structures, icon baking): the plain u_* uniforms are
## then set on the returned material itself.
func new_entity_material(style_id: StringName, team_index: int = 0) -> ShaderMaterial:
	return unit_material(style_id, Variant.MATERIAL_UNIFORMS, team_index).duplicate() as ShaderMaterial


func _apply_style(m: ShaderMaterial, style: Dictionary) -> void:
	var mat: Dictionary = style.get("material", {}) as Dictionary
	if mat.has("wear"):
		m.set_shader_parameter(&"wear_amount", float(mat["wear"]))
	if mat.has("dirt"):
		m.set_shader_parameter(&"dirt_amount", float(mat["dirt"]))
	if mat.has("panel"):
		m.set_shader_parameter(&"panel_amount", float(mat["panel"]))
	if mat.has("wear_color"):
		m.set_shader_parameter(&"wear_color", _color(mat["wear_color"]))
	if mat.has("dirt_color"):
		m.set_shader_parameter(&"dirt_color", _color(mat["dirt_color"]))
	if mat.has("emissive"):
		m.set_shader_parameter(&"emissive_strength", float(mat["emissive"]))


static func _color(v: Variant) -> Color:
	if v is Color:
		return v as Color
	return Color(str(v))


## Writes the `quality` uniform (unit_shader_quality) on every cached material.
func set_quality(q: ViewQuality) -> void:
	_quality = q
	var v: float = q.get_float(&"unit_shader_quality")
	for k: String in _cache:
		(_cache[k] as ShaderMaterial).set_shader_parameter(&"quality", v)


## Re-publishes player colours after ViewTeamColors.set_mode(): rewrites `team_color` of every cached material once.
func refresh_team_colors() -> void:
	for k: String in _team_of:
		(_cache[k] as ShaderMaterial).set_shader_parameter(P_TEAM, plate_color(StringName(k.get_slice("|", 0)), _team_of[k] as int))


## Night factor 0..1 (emissive multiplier 1 + 1.2 * night); a global, so no material is touched.
func set_night(k: float) -> void:
	ViewGlobals.set_value(ViewGlobals.G_ATM_NIGHT, clampf(k, 0.0, 1.0))


func material_count() -> int:
	return _cache.size()


func cached_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for k: String in _cache:
		out.append(_cache[k] as ShaderMaterial)
	return out


## Construction scaffold: `res://assets/shaders/scaffold.gdshader` when VIEW-W2 has delivered it, otherwise a minimal
## translucent orange cage-like fallback so the API is usable earlier.
func scaffold_material() -> ShaderMaterial:
	if _scaffold != null:
		return _scaffold
	_scaffold = ShaderMaterial.new()
	var path: String = "res://assets/shaders/%s.gdshader" % "scaffold"  # owned by VIEW-W2, may not exist yet
	if ResourceLoader.exists(path):
		_scaffold.shader = load(path) as Shader
	else:
		var sh: Shader = Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, cull_disabled, depth_draw_never;\n" \
			+ "void fragment() { vec3 p = fract(VERTEX * 1.5); float g = step(0.9, max(p.x, max(p.y, p.z)));" \
			+ " ALBEDO = vec3(1.0, 0.55, 0.1); ALPHA = 0.15 + 0.6 * g; }\n"
		_scaffold.shader = sh
	return _scaffold
