class_name ViewQuality
extends RefCounted
## Preset tables, renderer capability clamps and their application (render spec 3.8, 4.9, 5.12, 7.7).
## The tables live ONLY in res://data/recipes/quality.json; nothing here duplicates them. Resolution order:
## preset table -> user overrides (settings.cfg) -> auto render-scale steps -> renderer clamps (never by OS name).

enum Preset { LOW, MEDIUM, HIGH, ULTRA }
enum Renderer { FORWARD_PLUS, MOBILE, COMPATIBILITY }

const JSON_PATH: String = "res://data/recipes/quality.json"
const PRESET_KEYS: Array[String] = ["low", "medium", "high", "ultra"]
const AUTO_PRESET: int = 4  ## `[video] quality = 4` means "auto"
## Keys of the preset table that settings.cfg [video] may override.
const OVERRIDE_KEYS: Array[String] = [
	"render_scale", "scaling_mode", "msaa", "fxaa", "shadow_mode", "ssao", "ssil", "glow", "decor_density",
]
## Other [video] keys the view reads that are not part of the preset table.
const PASSTHROUGH_KEYS: Array[String] = [
	"quality", "renderer", "fps_cap", "health_bars", "night_maps", "wide_view", "camera_wasd", "unit_backend", "look",
]
const FX_QUALITY_NAMES: Array[String] = ["low", "medium", "high", "ultra"]

var preset: int = Preset.HIGH
var renderer: int = Renderer.FORWARD_PLUS
var values: Dictionary = {}  ## resolved key -> value table (spec 4.9), overrides applied, caps clamped
var reduce_flash: bool = false
var reduce_motion: bool = false
var colour_mode: int = ViewTeamColors.MODE_NORMAL
var preset_cap: int = Preset.ULTRA  ## highest preset the auto ladder may reach (the user's choice)
var auto_mode: bool = false  ## `[video] quality = 4`
var auto_scale_step: int = 0  ## 0..2: render-scale steps below LOW (0.75 -> 0.65 -> 0.55), moved by ViewQualityAuto
var target_fps: int = 60
var extras: Dictionary = {}  ## passthrough [video] keys (fps_cap, health_bars, night_maps, ...)

var _presets: Dictionary = {}  ## the whole quality.json
var _overrides: Dictionary = {}
var _adapter_is_metal: bool = false


## Reads quality.json. Returns {} (after Log.error) when it is missing or malformed.
static func load_presets(path: String = JSON_PATH) -> Dictionary:
	var txt: String = FileAccess.get_file_as_string(path)
	if txt.is_empty():
		Log.error("view", "ViewQuality: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("presets"):
		Log.error("view", "ViewQuality: %s is not a valid quality table" % path)
		return {}
	return parsed as Dictionary


## Renderer of the running process, from the engine (never from the OS name).
static func detect_renderer() -> int:
	var m: String = RenderingServer.get_current_rendering_method()
	if m == "mobile":
		return Renderer.MOBILE
	if m == "gl_compatibility":
		return Renderer.COMPATIBILITY
	return Renderer.FORWARD_PLUS


## First-run preset from the GPU class (spec 5.12). `adapter_type` is a RenderingDevice.DeviceType value.
static func recommend(adapter_type: int = -1, for_renderer: int = -1, adapter_name: String = "") -> int:
	var at: int = adapter_type if adapter_type >= 0 else int(RenderingServer.get_video_adapter_type())
	var an: String = adapter_name if adapter_name != "" else (RenderingServer.get_video_adapter_name() if adapter_type < 0 else "")
	var rr: int = for_renderer if for_renderer >= 0 else detect_renderer()
	var p: int = Preset.MEDIUM
	match at:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			p = Preset.HIGH
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			# Apple Silicon reports as integrated but is a full desktop-class GPU (VQ1: MEDIUM left it without antialiasing and with
			# thin decor); every other integrated GPU stays on MEDIUM.
			p = Preset.HIGH if an.begins_with("Apple M") else Preset.MEDIUM
		RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_OTHER:
			p = Preset.LOW
		_:
			p = Preset.MEDIUM
	if rr != Renderer.FORWARD_PLUS:
		p = mini(p, Preset.MEDIUM)
	return p


## Builds a quality object from user://settings.cfg ([video] and [access]). `renderer_override` >= 0 forces the renderer
## (tests); otherwise it is detected. Unknown [video] keys are ignored with one warning each.
static func from_settings(cfg: ConfigFile, presets_json: Dictionary, renderer_override: int = -1) -> ViewQuality:
	var q: ViewQuality = ViewQuality.new()
	q._presets = presets_json
	q.renderer = renderer_override if renderer_override >= 0 else detect_renderer()
	ViewMeshBuilder.default_compat_layout = q.renderer == Renderer.COMPATIBILITY
	q._adapter_is_metal = RenderingServer.get_current_rendering_driver_name() == "metal"
	var qv: int = int(cfg.get_value("video", "quality", recommend(-1, q.renderer))) if cfg != null else recommend(-1, q.renderer)
	if qv >= AUTO_PRESET:
		q.auto_mode = true
		q.preset = recommend(-1, q.renderer)
		q.preset_cap = Preset.ULTRA
	else:
		q.preset = clampi(qv, Preset.LOW, Preset.ULTRA)
		q.preset_cap = q.preset
	if cfg != null:
		for key: String in cfg.get_section_keys("video") if cfg.has_section("video") else PackedStringArray():
			var v: Variant = cfg.get_value("video", key)
			if OVERRIDE_KEYS.has(key):
				q._overrides[key] = v
			elif PASSTHROUGH_KEYS.has(key):
				q.extras[key] = v
			else:
				Log.warn("view", "ViewQuality: unknown [video] key '%s' ignored" % key)
		q.reduce_flash = bool(cfg.get_value("access", "reduce_flash", false))
		q.reduce_motion = bool(cfg.get_value("access", "reduce_motion", false))
		q.colour_mode = colour_mode_from_name(str(cfg.get_value("access", "colour_mode", "normal")))
		var fps: int = int(cfg.get_value("video", "fps_cap", 0))
		if fps > 0:
			q.target_fps = fps
	q.resolve()
	return q


## A quality object for a fixed preset and renderer without any settings file (tests, tools, icon baking).
static func create(presets_json: Dictionary, preset_id: int, for_renderer: int = Renderer.FORWARD_PLUS) -> ViewQuality:
	var q: ViewQuality = ViewQuality.new()
	q._presets = presets_json
	q.renderer = for_renderer
	q.preset = clampi(preset_id, Preset.LOW, Preset.ULTRA)
	q.preset_cap = q.preset
	q.resolve()
	return q


static func colour_mode_from_name(n: String) -> int:
	match n.to_lower():
		"protan":
			return ViewTeamColors.MODE_PROTAN
		"deutan":
			return ViewTeamColors.MODE_DEUTAN
		"tritan":
			return ViewTeamColors.MODE_TRITAN
		"high_contrast":
			return ViewTeamColors.MODE_HIGH_CONTRAST
	return ViewTeamColors.MODE_NORMAL


## Changes the preset (auto ladder or the options menu) and re-resolves the table; overrides are kept.
func set_preset(p: int) -> void:
	preset = clampi(p, Preset.LOW, Preset.ULTRA)
	if preset != Preset.LOW:
		auto_scale_step = 0
	resolve()


## User override of one table key (options menu); persists across preset changes.
func set_override(key: String, value: Variant) -> void:
	_overrides[key] = value
	resolve()


func clear_overrides() -> void:
	_overrides.clear()
	resolve()


## Rebuilds `values` from the preset table, overrides, auto steps and renderer clamps.
func resolve() -> void:
	values = {}
	var presets: Dictionary = _presets.get("presets", {}) as Dictionary
	var table: Dictionary = presets.get(PRESET_KEYS[preset], {}) as Dictionary
	for k: Variant in table:
		values[k] = table[k]
	for k: Variant in _overrides:
		values[k] = _overrides[k]
	if extras.has("unit_backend"):
		var ub: int = int(extras["unit_backend"])
		values["unit_backend"] = "nodes" if ub == 0 else ("batch" if ub == 1 else "auto")
	if preset == Preset.LOW and auto_scale_step > 0:
		var steps: Array = _presets.get("auto_render_scale_steps", [0.75, 0.65, 0.55]) as Array
		values["render_scale"] = float(steps[clampi(auto_scale_step, 0, steps.size() - 1)])
	_apply_clamps()


func _apply_clamps() -> void:
	var clamps: Dictionary = _presets.get("renderer_clamps", {}) as Dictionary
	var key: String = ""
	if renderer == Renderer.MOBILE:
		key = "mobile"
	elif renderer == Renderer.COMPATIBILITY:
		key = "compatibility"
	if not key.is_empty():
		var c: Dictionary = clamps.get(key, {}) as Dictionary
		for k: Variant in c:
			if k == "msaa_by_preset":
				var arr: Array = c[k] as Array
				# only ever lowers or sets a nonzero value where the preset had none (Mobile: MSAA is nearly free)
				values["msaa"] = int(arr[clampi(preset, 0, arr.size() - 1)])
			else:
				values[k] = c[k]
	# temporal upscalers replace MSAA and need render_scale <= 1; MetalFX exists on the Metal driver only
	var sm: String = str(values.get("scaling_mode", "bilinear"))
	if sm.begins_with("metalfx") and not _adapter_is_metal:
		values["scaling_mode"] = "bilinear"
		sm = "bilinear"
	if sm == "fsr2" or sm == "metalfx_temporal":
		values["msaa"] = 0
		values["render_scale"] = minf(float(values.get("render_scale", 1.0)), 1.0)


func get_int(key: StringName) -> int:
	var v: Variant = values.get(key, 0)
	return int(v) if (v is int or v is float or v is bool) else 0


func get_float(key: StringName) -> float:
	var v: Variant = values.get(key, 0.0)
	return float(v) if (v is int or v is float or v is bool) else 0.0


func get_bool(key: StringName) -> bool:
	var v: Variant = values.get(key, false)
	if v is String:
		return (v as String) != "off" and (v as String) != "false"
	return bool(v)


func get_string(key: StringName) -> String:
	return str(values.get(key, ""))


## "nodes" or "batch": the unit backend actually used (AUTO = nodes on Forward+, batch on Mobile and Compatibility).
func unit_backend() -> String:
	var b: String = get_string(&"unit_backend")
	if b == "nodes" or b == "batch":
		return b
	return "nodes" if renderer == Renderer.FORWARD_PLUS else "batch"


## FxManager.Quality value (LOW 0, MEDIUM 1, HIGH 2, ULTRA 3).
func fx_quality() -> int:
	var i: int = FX_QUALITY_NAMES.find(get_string(&"fx_quality"))
	return i if i >= 0 else preset


## Viewport-level settings: msaa, fxaa, taa, scaling mode / scale, debanding, mesh LOD threshold.
func apply_to_viewport(vp: Viewport) -> void:
	vp.msaa_3d = clampi(get_int(&"msaa"), 0, 3) as Viewport.MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if get_bool(&"fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = get_bool(&"taa")
	vp.use_debanding = true
	vp.mesh_lod_threshold = get_float(&"mesh_lod_threshold") if values.has("mesh_lod_threshold") else 1.0
	vp.scaling_3d_mode = scaling_mode_enum(get_string(&"scaling_mode"))
	vp.scaling_3d_scale = clampf(get_float(&"render_scale") if values.has("render_scale") else 1.0, 0.25, 2.0)


## RenderingServer-level settings: directional shadow atlas, soft shadow filter, SSAO quality. Forward+ / Mobile only where
## the engine supports them; harmless elsewhere.
func apply_to_rendering_server() -> void:
	if values.has("shadow_atlas"):
		RenderingServer.directional_shadow_atlas_set_size(get_int(&"shadow_atlas"), true)
	if values.has("shadow_filter"):
		RenderingServer.directional_soft_shadow_filter_set_quality(shadow_filter_enum(get_string(&"shadow_filter")))
	var ssao: String = get_string(&"ssao")
	if ssao != "off" and ssao != "":
		var parts: PackedStringArray = ssao.split("_")
		var lvl: int = RenderingServer.ENV_SSAO_QUALITY_MEDIUM
		match parts[0]:
			"low":
				lvl = RenderingServer.ENV_SSAO_QUALITY_LOW
			"high":
				lvl = RenderingServer.ENV_SSAO_QUALITY_HIGH
		var half: bool = parts.size() > 1 and parts[1] == "half"
		RenderingServer.environment_set_ssao_quality(lvl as RenderingServer.EnvironmentSSAOQuality, half, 0.5, 2, 50.0, 300.0)


## SSAO settings resolved from the `ssao` key: {enabled, level 0..3, half_size}.
func ssao_settings() -> Dictionary:
	var s: String = get_string(&"ssao")
	if s == "off" or s == "":
		return {"enabled": false, "level": 0, "half_size": true}
	var parts: PackedStringArray = s.split("_")
	var lvl: int = ["low", "medium", "high"].find(parts[0]) + 1
	return {"enabled": true, "level": lvl, "half_size": parts.size() > 1 and parts[1] == "half"}


static func scaling_mode_enum(name: String) -> Viewport.Scaling3DMode:
	match name:
		"fsr1":
			return Viewport.SCALING_3D_MODE_FSR
		"fsr2":
			return Viewport.SCALING_3D_MODE_FSR2
		"metalfx_spatial":
			return Viewport.SCALING_3D_MODE_METALFX_SPATIAL
		"metalfx_temporal":
			return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL
	return Viewport.SCALING_3D_MODE_BILINEAR


static func shadow_filter_enum(name: String) -> RenderingServer.ShadowQuality:
	match name:
		"hard":
			return RenderingServer.SHADOW_QUALITY_HARD
		"soft_low":
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		"soft_high":
			return RenderingServer.SHADOW_QUALITY_SOFT_HIGH
		"soft_ultra":
			return RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
	return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM


## Shadow cascade count from `shadow_mode`: 0 = blob shadows (no shadow maps), 2 or 4.
func shadow_cascades() -> int:
	match get_string(&"shadow_mode"):
		"cascades2":
			return 2
		"cascades4":
			return 4
	return 0


## Reduce-flash multipliers (spec 5.12): FX light energy x0.4, flash sprites 60 % size and 50 % alpha.
func flash_light_scale() -> float:
	return 0.4 if reduce_flash else 1.0


func flash_size_cap() -> float:
	return 0.6 if reduce_flash else 1.0


func flash_alpha_cap() -> float:
	return 0.5 if reduce_flash else 1.0


## Camera shake multiplier: reduce_motion x0.2 (reduce_flash additionally silences shake entirely).
func shake_scale() -> float:
	if reduce_flash:
		return 0.0
	return 0.2 if reduce_motion else 1.0
