class_name UiAudioPort
extends RefCounted
## Thin mirror of the `Snd` facade (ui.md 3.2.3, audio.md 3.1): UI-INITIATED cues only. Gameplay announcer lines,
## alarms and sim-event cues are event-driven inside audio. Adapters: `UiAudioPortSnd`, `UiAudioPortNull`,
## `UiAudioPortRecorder`.

signal caption(line_id: StringName, text: String, priority: int)

## = SndUnitResponse.Order.
enum Order { MOVE = 0, ATTACK = 1, GUARD = 2, DEPLOY = 3, CAPTURE = 4, REPAIR = 5, LOAD = 6, UNLOAD = 7, HARVEST = 8, STOP = 9, SCATTER = 10, SELL = 11 }

const CLICK := &"snd.ui.click"
const HOVER := &"snd.ui.hover"
const CONFIRM := &"snd.ui.confirm"
const BACK := &"snd.ui.back"
const TAB := &"snd.ui.tab"
const TOGGLE_ON := &"snd.ui.toggle_on"
const TOGGLE_OFF := &"snd.ui.toggle_off"
const SLIDER_TICK := &"snd.ui.slider_tick"
const ERROR := &"snd.ui.error"
const QUEUE_ADD := &"snd.ui.queue_add"
const QUEUE_HOLD := &"snd.ui.queue_hold"
const PLACE_OK := &"snd.ui.place_ok"
const PLACE_FAIL := &"snd.ui.place_fail"
const SELL_MODE := &"snd.ui.sell_mode"
const REPAIR_MODE := &"snd.ui.repair_mode"
const WAYPOINT := &"snd.ui.waypoint"
const RALLY_SET := &"snd.ui.rally_set"
const GROUP_SET := &"snd.ui.group_set"
const GROUP_RECALL := &"snd.ui.group_recall"
const MINIMAP_CLICK := &"snd.ui.minimap_click"
const MINIMAP_PING := &"snd.ui.minimap_ping"
const ALERT := &"snd.ui.alert"
const NOTIFY := &"snd.ui.notify"
const CHAT := &"snd.ui.chat"
const MENU_TRANSITION := &"snd.ui.menu_transition"
const LOBBY_JOIN := &"snd.ui.lobby_join"
const LOBBY_LEAVE := &"snd.ui.lobby_leave"
const LOBBY_READY := &"snd.ui.lobby_ready"
const LOBBY_COUNTDOWN_TICK := &"snd.ui.lobby_countdown_tick"
const LOBBY_START := &"snd.ui.lobby_start"


## Snd.ui(&"snd.ui.*"): ids are the constants above.
func ui(_id: StringName, _gain_db: float = 0.0) -> void:
	push_error("NOT IMPLEMENTED: UiAudioPort.ui")


## UI / lobby originated announcer lines only; never for events the sim emits.
func announce(_line: StringName) -> bool:
	return false


## Scripted missions (MIS2): a mission's `music_state` action (`DefMissionAction.MUSIC_NAMES`: auto, calm, combat, tense, victory, defeat).
## The music director only knows calm and combat; the others are left to its own rules.
func music_state(_state: StringName) -> void:
	pass


## Once per COMMITTED selection change; def = primary (highest tier, ties lowest def index).
func unit_selected(_def_idx: int, _is_structure: bool, _count: int) -> void:
	pass


## Snd.unit_ordered(Order, primary def).
func unit_ordered(_order: int, _def_idx: int) -> void:
	pass


## UI pre-check refusals only (the sim's ORDER_FAILED / CMD_REJECTED are voiced by audio itself).
func order_denied(_def_idx: int, _is_structure: bool = false) -> void:
	pass


## Replays.
func set_time_scale(_x: float) -> void:
	pass


func captions_enabled() -> bool:
	return false
