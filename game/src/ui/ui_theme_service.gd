class_name UiThemeService
extends RefCounted
## Holds the current `Theme`, rebuilds it (`rebuild`) and hands it to every registered `UiLayerRoot` (ui.md 5.19.5).
## Custom-drawn widgets need no signal wiring: assigning a new theme fires NOTIFICATION_THEME_CHANGED on every Control
## below the layer roots (they `queue_redraw()` there). `theme_changed` is for non-Control listeners (audio, view tint).
## Rebuild triggers: entering / leaving a match, colour mode, high-contrast toggle, font option.

signal theme_changed(theme: Theme)

static var _instance: UiThemeService = null


static func release_statics() -> void:
	_instance = null

var _theme: Theme = null
var _skin: UiSkin = null
var _a11y: Dictionary = {}
var _roots: Array[UiLayerRoot] = []


static func instance() -> UiThemeService:
	if _instance == null:
		_instance = UiThemeService.new()
	return _instance


## The current theme (built from the neutral skin on first use).
static func current() -> Theme:
	var s: UiThemeService = instance()
	if s._theme == null:
		s._rebuild(UiSkinSet.shared().neutral_skin())
	return s._theme


## The skin the current theme was built from.
static func current_skin() -> UiSkin:
	current()
	return instance()._skin


## UiTheme.build + assignment to every layer root; returns the new theme.
static func rebuild(skin: UiSkin) -> Theme:
	return instance()._rebuild(skin)


## Accessibility options of the next builds: `{high_contrast: bool, cvd: bool}`; rebuilds when they changed.
static func set_a11y(options: Dictionary) -> void:
	var s: UiThemeService = instance()
	if s._a11y == options:
		return
	s._a11y = options.duplicate()
	if s._skin != null:
		s._rebuild(s._skin)


static func a11y_options() -> Dictionary:
	return instance()._a11y


func _rebuild(skin: UiSkin) -> Theme:
	if _skin == null or _skin.cache_key() != skin.cache_key():
		UiStyleBox.clear_cache()
	_skin = skin
	_theme = UiTheme.build(skin, _a11y)
	for i in range(_roots.size() - 1, -1, -1):
		if is_instance_valid(_roots[i]):
			_roots[i].theme = _theme
		else:
			_roots.remove_at(i)
	theme_changed.emit(_theme)
	return _theme


## Called by `UiLayerRoot` on entering the tree.
func register_root(root: UiLayerRoot) -> void:
	if not _roots.has(root):
		_roots.append(root)
	root.theme = current()


func unregister_root(root: UiLayerRoot) -> void:
	_roots.erase(root)


func root_count() -> int:
	return _roots.size()
