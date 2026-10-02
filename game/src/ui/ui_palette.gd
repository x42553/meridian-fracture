class_name UiPalette
extends RefCounted
## Colour tokens of the UI (the 18 tokens of `style.ui.tokens`, ui.md 4.6.4; test `test_ui_tokens` asserts them equal
## to `game/data/recipes/style.json`) plus the colour-vision-safe semantic set (ui.md 5.19.3 / 7.5).
## With `ui_skin.gd` the only UI files allowed to hold colour literals (lint L011, art R-25).
## Widgets read tokens from here, skin colours from the theme (`UiTheme.ACCENT_TYPE`).

const BG_DEEP := Color("#06080b")
const BG_PANEL := Color("#0b1016")
const BG_RAISED := Color("#121a23")
const BG_CONTROL := Color("#182230")
const BG_HOVER := Color("#213145")
const TEXT := Color("#e6eef6")
const TEXT_DIM := Color("#95a8bb")
const TEXT_MUTE := Color("#7a8ca0")
const TEXT_DISABLED := Color("#5d6f83")
const LINE_DIM := Color("#212d3b")
const LINE := Color("#35465a")
const LINE_BRIGHT := Color("#5f7a96")
const CREDITS := Color("#ffd35c")
const OK := Color("#5ce383")
const WARN := Color("#ffb52a")
const DANGER := Color("#ff5555")
const POWER := Color("#49d0ff")
const BLACK_A := Color("#0000008c")

## Semantic colours in colour mode `cvd` (ui.md 5.19.3).
const CVD_OK := Color("#4DB8FF")
const CVD_WARN := Color("#F5E663")
const CVD_DANGER := Color("#E8590C")
const CVD_POWER := Color("#A8E6FF")

## Dark text on an accent fill (`style.ui.chrome.button.label_on_accent`).
const TEXT_ON_ACCENT := Color("#10161d")

## Documentation constant, not used at run time: the UI proposal `P-default` for ids 0-7 (ui.md 7.5).
const P_DEFAULT_0_7: PackedStringArray = ["AD0410", "1E69C6", "53AC7A", "DDF514", "B892FD", "65FDFA", "CD6D04", "87386B"]

## Fallback team colours (ids 0-11 / 0-7) when no `ViewStyle` was injected; the same values as `style.player_colors`.
const TEAM_DEFAULT: PackedStringArray = ["D8323B", "2C86F0", "2FAE5E", "F5C13A", "7250D8", "25CDE0", "F47B2A", "E0489F", "9BD13B", "8A97A8", "8C5A3B", "ECECEC"]
const TEAM_CVD: PackedStringArray = ["CE251A", "6D99FA", "86C280", "E4CD19", "7957CD", "3CE0EA", "E9711E", "9E3773"]

## The 18 token names in `style.ui.tokens` order.
const TOKEN_NAMES: PackedStringArray = ["BG_DEEP", "BG_PANEL", "BG_RAISED", "BG_CONTROL", "BG_HOVER", "LINE_DIM", "LINE", "LINE_BRIGHT", "TEXT", "TEXT_DIM", "TEXT_MUTE", "TEXT_DISABLED", "CREDITS", "OK", "WARN", "DANGER", "POWER", "BLACK_A"]


## Token by name (`&"TEXT"`), the values of the consts above. Unknown name -> magenta + error log.
static func token(token_name: StringName) -> Color:
	match token_name:
		&"BG_DEEP": return BG_DEEP
		&"BG_PANEL": return BG_PANEL
		&"BG_RAISED": return BG_RAISED
		&"BG_CONTROL": return BG_CONTROL
		&"BG_HOVER": return BG_HOVER
		&"TEXT": return TEXT
		&"TEXT_DIM": return TEXT_DIM
		&"TEXT_MUTE": return TEXT_MUTE
		&"TEXT_DISABLED": return TEXT_DISABLED
		&"LINE_DIM": return LINE_DIM
		&"LINE": return LINE
		&"LINE_BRIGHT": return LINE_BRIGHT
		&"CREDITS": return CREDITS
		&"OK": return OK
		&"WARN": return WARN
		&"DANGER": return DANGER
		&"POWER": return POWER
		&"BLACK_A": return BLACK_A
	Log.error("ui", "UiPalette.token: unknown token '%s'" % token_name)
	return Color.MAGENTA


## Player colour `id` for the active colour mode (ui.md 5.19.3): `UiSkinSet.team_color`.
static func team(id: int) -> Color:
	return UiSkinSet.shared().team_color(id)


## Semantic colour `&"ok" &"warn" &"danger" &"power"` for the active colour mode.
static func semantic(kind: StringName) -> Color:
	return semantic_for(kind, UiSkinSet.shared().colour_mode() == UiSkinSet.ColourMode.CVD)


## Semantic colour for an explicit mode (pure; used by tests and the theme builder).
static func semantic_for(kind: StringName, cvd: bool) -> Color:
	match kind:
		&"ok": return CVD_OK if cvd else OK
		&"warn": return CVD_WARN if cvd else WARN
		&"danger": return CVD_DANGER if cvd else DANGER
		&"power": return CVD_POWER if cvd else POWER
	Log.error("ui", "UiPalette.semantic: unknown kind '%s'" % kind)
	return TEXT
