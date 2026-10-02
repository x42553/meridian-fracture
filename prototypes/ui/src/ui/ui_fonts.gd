class_name UiFonts
extends RefCounted
## Font roles. Widgets ask for a role, never a family, so swapping a font is a one-line change here.
##   BODY      Rajdhani SemiBold: all running UI text (12-18 px, condensed, high x-height)
##   BODY_BOLD Rajdhani Bold: names, button labels
##   HEAD      Orbitron (variable, wght 700): panel headers, big numerals, menu titles
##   NUM       Share Tech Mono: tabular numbers (credits, timers, costs) so digits do not jitter
enum Role { BODY, BODY_BOLD, HEAD, HEAD_LIGHT, NUM }

const _PATH_BODY := "res://fonts/rajdhani_semibold.ttf"
const _PATH_BODY_BOLD := "res://fonts/rajdhani_bold.ttf"
const _PATH_HEAD := "res://fonts/orbitron_variable.ttf"
const _PATH_NUM := "res://fonts/share_tech_mono.ttf"

static var _cache: Dictionary = {}

static func get_font(role: Role) -> Font:
	if _cache.has(role):
		return _cache[role]
	var f: Font
	match role:
		Role.BODY:
			f = load(_PATH_BODY)
		Role.BODY_BOLD:
			f = load(_PATH_BODY_BOLD)
		Role.HEAD:
			f = variable(_PATH_HEAD, 700, 1)
		Role.HEAD_LIGHT:
			f = variable(_PATH_HEAD, 500, 1)
		Role.NUM:
			f = load(_PATH_NUM)
	_cache[role] = f
	return f

## FontVariation over a variable font. `weight` is the wght axis value, `glyph_spacing` extra px between glyphs.
static func variable(path: String, weight: int, glyph_spacing: int = 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = glyph_spacing
	return fv
