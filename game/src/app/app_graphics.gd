class_name AppGraphics
extends RefCounted
## Thin graphics glue (ui.md 4.7): the presets and clamps are the view's (`ViewQuality`); the app only persists the
## player's choices under `[video]` and reports whether the page shows "Custom (based on ...)".

enum Preset { LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3, AUTO = 4 }


## First-run preset from the GPU class (`ViewQuality.recommend`, 5.18.2).
static func recommend() -> int:
	return ViewQuality.recommend()


## Quality keys present besides `quality` (the ids' key part): non-empty means "Custom (based on ...)".
static func overrides(store: AppSettingsStore) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: String in ViewQuality.OVERRIDE_KEYS:
		if store.is_explicit(StringName("video/" + key)):
			out.append(key)
	return out


## Choosing a preset in the dropdown drops every override so the preset's values apply again.
static func clear_overrides(store: AppSettingsStore) -> void:
	for key: String in ViewQuality.OVERRIDE_KEYS:
		store.reset(StringName("video/" + key))


static func preset_name(p: int) -> String:
	match p:
		Preset.LOW:
			return "Low"
		Preset.MEDIUM:
			return "Medium"
		Preset.HIGH:
			return "High"
		Preset.ULTRA:
			return "Ultra"
	return "Auto"


## Dropdown text: the preset name, or "Custom (based on High)" while overrides exist.
static func preset_label(store: AppSettingsStore) -> String:
	var p: int = int(store.get_value(&"video/quality"))
	if p != Preset.AUTO and not overrides(store).is_empty():
		return "Custom (based on %s)" % preset_name(p)
	return preset_name(p)


## Adapter description shown next to the first-run recommendation.
static func adapter_name() -> String:
	return RenderingServer.get_video_adapter_name()
