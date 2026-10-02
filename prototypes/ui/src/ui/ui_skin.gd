class_name UiSkin
extends RefCounted
## Faction skin: the only faction-dependent inputs of the UI theme. Derived from the bible's
## `visual_direction` strings (e.g. NAPC "olive, cream and rescue orange").

var code: String = ""
var display_name: String = ""
## Main highlight: borders on hover, active tab underline, progress fills, title accents.
var accent: Color = Color.WHITE
## Secondary detail colour: badges, small ticks, secondary glow.
var accent2: Color = Color.WHITE
## Dark tint mixed into panel gradients so each faction's chrome feels different.
var tint: Color = Color.BLACK

const _DEFS: Dictionary = {
	"napc": ["North American Peace Corps", "#f07f2c", "#c9d27a", "#2a2f16"],
	"nec": ["New European Confederation", "#5b93e0", "#ffb733", "#14243d"],
	"olm": ["Order of the Levant and Mediterranean", "#2fc9bb", "#d9803f", "#0f2b2c"],
	"def": ["Democratic Eurasian Federation", "#e0503a", "#f0dc8c", "#341612"],
	"pd": ["Pacific Dominion", "#33a0ec", "#ff7f5c", "#0f2740"],
	"han": ["Han Empire", "#33c98a", "#e0424f", "#0f2f22"],
	"ae": ["African Empire", "#26d6e8", "#e0aa3c", "#11292d"],
	"sap": ["South Asian Protectorate", "#f3a622", "#7a72e6", "#2c2412"],
}

static func codes() -> PackedStringArray:
	return PackedStringArray(["napc", "nec", "olm", "def", "pd", "han", "ae", "sap"])

static func for_faction(faction_code: String) -> UiSkin:
	var s := UiSkin.new()
	var d: Array = _DEFS.get(faction_code, _DEFS["napc"])
	s.code = faction_code if _DEFS.has(faction_code) else "napc"
	s.display_name = d[0]
	s.accent = Color(d[1])
	s.accent2 = Color(d[2])
	s.tint = Color(d[3])
	return s

## Panel gradient stops (top, bottom) so all panels share one recipe.
func panel_top(alpha: float = 0.94) -> Color:
	var c: Color = UiPalette.BG_RAISED.lerp(tint, 0.55)
	c.a = alpha
	return c

func panel_bottom(alpha: float = 0.96) -> Color:
	var c: Color = UiPalette.BG_PANEL.lerp(tint, 0.25)
	c.a = alpha
	return c
