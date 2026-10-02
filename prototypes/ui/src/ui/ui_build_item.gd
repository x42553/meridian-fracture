class_name UiBuildItem
extends RefCounted
## View-model for one build card (structure, unit, research or support power). The HUD builds these from
## SimWorld queries each production tick; cards never read the sim themselves.

enum State { AVAILABLE, BUILDING, QUEUED, READY, ON_HOLD, LOCKED, UNAFFORDABLE, COOLDOWN }

var id: String = ""
var display_name: String = ""
var cost: int = 0
var build_seconds: float = 0.0
var hotkey: String = ""
var tier: int = 1
var glyph: UiGlyphs.Glyph = UiGlyphs.Glyph.VEHICLES
var model_kind: String = ""
var icon: Texture2D
var state: State = State.AVAILABLE
## 0..1 progress of the item currently in production (or cooldown charge for powers).
var progress: float = 0.0
var queued: int = 0
var requires: String = ""
var description: String = ""
var power_delta: int = 0
