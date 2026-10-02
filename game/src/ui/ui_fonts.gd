class_name UiFonts
extends RefCounted
## Font roles. Widgets ask for a role, never a family, so a swap is a one-line change here (ui.md 4.6.2, spike 6).
##   BODY       Rajdhani SemiBold: running UI text (dense, high x-height)
##   BODY_BOLD  Rajdhani Bold: names, button labels
##   HEAD       Orbitron variable, wght 700, +1 px glyph spacing: CAPS headers and numerals only
##   HEAD_LIGHT Orbitron wght 500 (menu wordmark, sub-titles)
##   NUM        Share Tech Mono: tabular digits (credits, timers, costs, hotkeys)
## Every role is a `FontVariation` whose fallback chain ends in a `SystemFont`, so CJK / Arabic / emoji player
## names render (tofu is tolerated, never a crash, QA X-16). All families are OFL (assets/fonts/*/OFL.txt).
## `set_alt_body(true)` swaps BODY / BODY_BOLD for the dyslexia-friendly family when its file is vendored.
enum Role { BODY, BODY_BOLD, HEAD, HEAD_LIGHT, NUM }

const PATH_BODY: String = "res://assets/fonts/rajdhani/rajdhani_semibold.ttf"
const PATH_BODY_BOLD: String = "res://assets/fonts/rajdhani/rajdhani_bold.ttf"
const PATH_HEAD: String = "res://assets/fonts/orbitron/orbitron_variable.ttf"
const PATH_NUM: String = "res://assets/fonts/share_tech_mono/share_tech_mono.ttf"
const PATH_ALT: String = "res://assets/fonts/%s" % "atkinson_hyperlegible/atkinson_hyperlegible_regular.ttf"

static var _cache: Dictionary = {}
static var _system: SystemFont = null
static var _alt_body: bool = false


## Orderly quit: drop the cached fonts (see AppShutdown).
static func release_statics() -> void:
	_cache.clear()
	_system = null


## The font of a role (cached `FontVariation`).
static func get_font(role: int) -> Font:
	if _cache.has(role):
		return _cache[role]
	var f: Font
	match role:
		Role.BODY:
			f = _make(PATH_ALT if _alt_body_available() else PATH_BODY, -1, 0)
		Role.BODY_BOLD:
			f = _make(PATH_ALT if _alt_body_available() else PATH_BODY_BOLD, -1, 0)
		Role.HEAD:
			f = _make(PATH_HEAD, 700, 1)
		Role.HEAD_LIGHT:
			f = _make(PATH_HEAD, 500, 1)
		_:
			f = _make(PATH_NUM, -1, 0)
	_cache[role] = f
	return f


## Switch the BODY roles to the alternative family (`access/ui_font`); ignored while the font file is missing.
static func set_alt_body(on: bool) -> void:
	if on == _alt_body:
		return
	_alt_body = on
	_cache.erase(Role.BODY)
	_cache.erase(Role.BODY_BOLD)


static func _alt_body_available() -> bool:
	return _alt_body and ResourceLoader.exists(PATH_ALT)


## `FontVariation` over a font file. `weight` < 0 = no variation axis; `glyph_spacing` = extra px between glyphs.
static func _make(path: String, weight: int, glyph_spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(path) as Font
	if weight >= 0:
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = glyph_spacing
	fv.fallbacks = [_system_font()]
	return fv


static func _system_font() -> SystemFont:
	if _system == null:
		_system = SystemFont.new()
		_system.font_names = PackedStringArray(["sans-serif", "Arial", "Noto Sans", "Segoe UI"])
		_system.allow_system_fallback = true
	return _system


## The role of a theme type-scale token (`caption`, `small`, `body`, `sub`, `list`, `head`, `hero`, `title`, `logo`, `numerals`).
static func role_of(token: StringName) -> int:
	match token:
		&"caption", &"numerals", &"num": return Role.NUM
		&"list": return Role.BODY_BOLD
		&"head", &"hero", &"title", &"logo": return Role.HEAD
	return Role.BODY


## Size in logical px of a type-scale token.
static func size_of(token: StringName) -> int:
	match token:
		&"caption": return UiMetrics.FS_CAPTION
		&"small": return UiMetrics.FS_SMALL
		&"body": return UiMetrics.FS_BODY
		&"sub": return UiMetrics.FS_SUB
		&"list": return UiMetrics.FS_LIST
		&"head": return UiMetrics.FS_HEAD
		&"hero": return UiMetrics.FS_HERO
		&"title": return UiMetrics.FS_TITLE
		&"logo": return UiMetrics.FS_LOGO
		&"numerals", &"num": return UiMetrics.FS_NUM
	return UiMetrics.FS_BODY
