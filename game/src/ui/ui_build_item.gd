class_name UiBuildItem
extends RefCounted
## View-model of one sidebar card (ui.md 4.2): structure, unit, research, support power or superweapon. Built by
## `UiBuildModel`, drawn by `UiBuildCard`; cards never read the sim.

enum Kind { STRUCTURE = 0, UNIT = 1, RESEARCH = 2, POWER = 3, SUPERWEAPON = 4 }
enum State { AVAILABLE = 0, BUILDING = 1, QUEUED = 2, READY = 3, ON_HOLD = 4, LOCKED = 5, UNAFFORDABLE = 6, COOLDOWN = 7, BLOCKED = 8, PLACING = 9, DONE = 10 }

var kind: int = Kind.UNIT
var def_idx: int = -1  ## per-kind def index (TRAIN / BUILD_START / research / power index)
var id: String = ""  ## canonical id, labels only
var display_name: String = ""
var tier: int = 1  ## 1-3 (0 for powers)
var cost: int = 0
var total_seconds: float = 0.0  ## build / research / cooldown / recharge time
var power_delta: int = 0  ## structures: + supply / - demand
var state: int = State.AVAILABLE
var progress_permille: int = 0
var eta_ticks: int = -1
var rate_pct: int = 100
var queued: int = 0  ## units of this def in the chosen queue (incl. the one in progress)
var pending: int = 0  ## optimistic local increments not yet confirmed
var blocked_reason: int = 0  ## UiSimPort.Rule when LOCKED / BLOCKED / UNAFFORDABLE
var queue_state: int = 0  ## UiSimPort.QueueState of the queue the item sits in
var requires_text: String = ""  ## "Radar", "Radar + Laboratory"
var hotkey_label: String = ""  ## "Alt+Q"
var slot: int = -1
var recipe: String = ""
var glyph: int = UiGlyphs.Glyph.VEHICLES  ## class glyph, the icon fallback
var role_glyph: int = UiGlyphs.Glyph.VEHICLES
var icon: Texture2D = null
var replaced_by_roster: bool = false  ## subfaction unique (UNIQUE badge)
var producer_eid: int = -1  ## chosen producer for units
var queue_kind: int = 0  ## DefEnums.QueueKind of the producing structure (units)
var tab: int = 0  ## UiBuildModel.Tab holding the card
var description: String = ""
var reason_text: String = ""  ## warning line of a BLOCKED / LOCKED card ("Radar offline: low power")
var power_idx: int = -1  ## POWER: roster power def index (== def_idx); SUPERWEAPON: DefSuperweapon index
var target_mode: int = 0  ## DefEnums.TargetMode of a power


## BUILDING / ON_HOLD / COOLDOWN: the states that show a clock sweep.
func is_sweeping() -> bool:
	return state == State.BUILDING or state == State.ON_HOLD or state == State.COOLDOWN


## Locked-out states: a click starts nothing (UNAFFORDABLE never blocks a click).
func is_locked_out() -> bool:
	return state == State.LOCKED or state == State.BLOCKED


## Seconds left: the sim's eta when known, else total x (1 - p) / rate (5.10.7).
func remaining_seconds() -> float:
	if eta_ticks >= 0:
		return float(eta_ticks) / 20.0
	var r: float = maxf(float(rate_pct), 1.0) / 100.0
	return total_seconds * (1.0 - float(progress_permille) / 1000.0) / r


## Whole seconds shown on the card (ceil), 0 when finished.
func remaining_whole_seconds() -> int:
	return int(ceilf(remaining_seconds() - 0.0001))


## 0..1 progress.
func progress() -> float:
	return clampf(float(progress_permille) / 1000.0, 0.0, 1.0)


## "12,450" grouping.
static func group_digits(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## "m:ss" of whole seconds.
static func mmss(sec: int) -> String:
	sec = maxi(sec, 0)
	return "%d:%02d" % [sec / 60, sec % 60]


## Ticks (20 per second) to whole seconds, rounded up.
static func ticks_to_seconds(ticks: int) -> int:
	return int(ceili(float(maxi(ticks, 0)) / 20.0))


## Compact text for test failure messages.
func describe() -> String:
	return "%s[%d] state=%s p=%d q=%d" % [display_name, def_idx, State.find_key(state), progress_permille, queued]
