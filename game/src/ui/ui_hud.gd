class_name UiHud
extends Control
## The in-game HUD root (ui.md 3.4): composes the sidebar, bottom panel, top strip, power dock, ribbon stack, log feed,
## select rectangle and the 2D world overlay, and lays them out per size class. Full rect and MOUSE_FILTER_IGNORE so a
## click on empty HUD space reaches the input controller (spike input lab A). Data in through the presenter, actions
## out through the signals below; it never reads the sim.

signal build_requested(item: UiBuildItem, count: int)  ## LMB (count 1) / Shift+LMB (count 5) on a card
signal build_hold_requested(item: UiBuildItem)  ## RMB on a building / queued card
signal build_cancel_requested(item: UiBuildItem)  ## RMB on a held card
signal place_requested(item: UiBuildItem)  ## LMB on a READY structure card
signal power_pressed(power_idx: int)  ## LMB on a power / superweapon card or dock button (`UiPowerDock.SUPERWEAPON` = the superweapon)
signal tab_changed(tab: int)
signal tool_pressed(id: StringName)  ## repair / sell / rally / waypoint / menu
signal command_pressed(id: StringName)  ## command bar and utility buttons
signal ability_pressed(slot: int)
signal ability_right_pressed(slot: int)
signal group_pressed(index: int, double: bool)
signal tile_pressed(index: int, mods: int)
signal camera_requested(norm: Vector2)
signal camera_snap(norm: Vector2)
signal minimap_order(norm: Vector2, mods: int)
signal producer_cycled(direction: int)
signal queue_slot_pressed(index: int)
signal queue_slot_right_pressed(index: int)
signal queue_hold_toggled()
signal queue_primary_pressed()
signal pad_pressed(id: StringName)
signal ribbon_activated(rule_id: StringName)
signal layout_changed(margins: Vector4)  ## occluded logical px (left, top, right, bottom): the camera's free-area margins

const RIBBON_W: float = 560.0  ## wider than UiMetrics.RIBBON.x: "ENEMY SUPERWEAPON DETECTED" + the countdown must not clip
const MODE_PLAYER: int = 0
const MODE_OBSERVER: int = 1
const REPLAY_BAR_H: int = 100  ## replay transport height (two rows, the divergence banner adds a line)

var mode: int = MODE_PLAYER
var size_class: int = UiLayout.SizeClass.REGULAR
var lite: bool = false

var _sidebar: UiSidebar = null
var _bottom: UiBottomPanel = null
var _overlay: UiWorldOverlay = null
var _select_rect: UiSelectRect = null
var _play: Control = null
var _top_strip: UiTopStrip = null
var _dock: UiPowerDock = null
var _ribbons: UiRibbonStack = null
var _log: UiLogFeed = null
var _skin: UiSkin = null
var _data: GameData = null
var _roster: DefRoster = null
var _observer_bar: UiObserverBar = null
var _scoreboard: UiScoreboard = null
var _replay_bar: UiReplayBar = null
var _chrome_visible: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func setup(skin: UiSkin, data: GameData, roster: DefRoster, p_mode: int) -> void:
	_skin = skin
	_data = data
	_roster = roster
	mode = p_mode
	UiLayerRoot.fill(self)
	_overlay = UiWorldOverlay.new()
	add_child(_overlay)
	UiLayerRoot.fill(_overlay)
	_select_rect = UiSelectRect.new()
	add_child(_select_rect)
	_play = Control.new()
	_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_play)
	UiLayerRoot.fill(_play)
	_play.offset_right = -float(UiMetrics.SIDEBAR_W)
	_build_sidebar()
	_build_bottom()
	_build_top()
	if mode == MODE_OBSERVER:
		_build_observer()
	if roster != null and data != null and mode != MODE_OBSERVER:
		var fac: DefFaction = data.factions[roster.faction] if roster.faction >= 0 and roster.faction < data.factions.size() else null
		_sidebar.set_header(fac.ui_name if fac != null else "", roster.ui_title)
	resized.connect(_relayout)
	_relayout.call_deferred()


# ---- accessors --------------------------------------------------------------------------------------------------------
func sidebar() -> UiSidebar:
	return _sidebar


func bottom() -> UiBottomPanel:
	return _bottom


func minimap() -> UiMinimap:
	return _sidebar.minimap()


func overlay() -> UiWorldOverlay:
	return _overlay


func ribbons() -> UiRibbonStack:
	return _ribbons


func log_feed() -> UiLogFeed:
	return _log


func top_strip() -> UiTopStrip:
	return _top_strip


func power_dock() -> UiPowerDock:
	return _dock


func select_rect() -> UiSelectRect:
	return _select_rect


func observer_bar() -> UiObserverBar:
	return _observer_bar


func scoreboard() -> UiScoreboard:
	return _scoreboard


## The replay transport (null unless `add_replay_bar` was called).
func replay_bar() -> UiReplayBar:
	return _replay_bar


## The world area not covered by the sidebar (logical px).
func playfield_rect() -> Rect2:
	return Rect2(0.0, 0.0, maxf(size.x - float(UiMetrics.SIDEBAR_W), 0.0), size.y)


# ---- construction -----------------------------------------------------------------------------------------------------
func _build_sidebar() -> void:
	_sidebar = UiSidebar.new()
	add_child(_sidebar)
	_sidebar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_sidebar.offset_left = -float(UiMetrics.SIDEBAR_W)
	_sidebar.offset_right = 0.0
	_sidebar.card_pressed.connect(_on_card)
	_sidebar.card_right_pressed.connect(_on_card_right)
	_sidebar.tab_changed.connect(func(t: int) -> void: tab_changed.emit(t))
	_sidebar.tool_pressed.connect(func(id: StringName) -> void: tool_pressed.emit(id))
	_sidebar.camera_requested.connect(func(n: Vector2) -> void: camera_requested.emit(n))
	_sidebar.camera_snap.connect(func(n: Vector2) -> void: camera_snap.emit(n))
	_sidebar.minimap_order.connect(func(n: Vector2, m: int) -> void: minimap_order.emit(n, m))
	_sidebar.pad_pressed.connect(func(id: StringName) -> void: pad_pressed.emit(id))
	_sidebar.producer_cycled.connect(func(d: int) -> void: producer_cycled.emit(d))
	_sidebar.queue_slot_pressed.connect(func(i: int) -> void: queue_slot_pressed.emit(i))
	_sidebar.queue_slot_right_pressed.connect(func(i: int) -> void: queue_slot_right_pressed.emit(i))
	_sidebar.queue_hold_toggled.connect(func() -> void: queue_hold_toggled.emit())
	_sidebar.queue_primary_pressed.connect(func() -> void: queue_primary_pressed.emit())


func _build_bottom() -> void:
	_bottom = UiBottomPanel.new()
	_play.add_child(_bottom)
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.offset_bottom = -float(UiMetrics.BOTTOM_MARGIN)
	_bottom.group_pressed.connect(func(i: int, d: bool) -> void: group_pressed.emit(i, d))
	_bottom.tile_pressed.connect(func(i: int, m: int) -> void: tile_pressed.emit(i, m))
	_bottom.command_pressed.connect(func(id: StringName) -> void: command_pressed.emit(id))
	_bottom.utility_pressed.connect(func(id: StringName) -> void: command_pressed.emit(id))
	_bottom.ability_pressed.connect(func(s: int) -> void: ability_pressed.emit(s))
	_bottom.ability_right_pressed.connect(func(s: int) -> void: ability_right_pressed.emit(s))


func _build_top() -> void:
	_ribbons = UiRibbonStack.new()
	_play.add_child(_ribbons)
	_ribbons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_ribbons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ribbons.offset_top = float(UiMetrics.RIBBON_TOP)
	_ribbons.custom_minimum_size = Vector2(RIBBON_W, 0.0)
	_ribbons.ribbon_activated.connect(func(id: StringName) -> void: ribbon_activated.emit(id))
	_top_strip = UiTopStrip.new()
	_play.add_child(_top_strip)
	_top_strip.position = UiMetrics.TOP_STRIP_POS
	_dock = UiPowerDock.new()
	_play.add_child(_dock)
	_dock.position = UiMetrics.DOCK_POS + Vector2(0.0, 6.0)
	_dock.power_pressed.connect(func(idx: int) -> void: power_pressed.emit(idx))
	_log = UiLogFeed.new()
	_play.add_child(_log)
	_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log.offset_left = 14.0
	_log.offset_bottom = -float(UiMetrics.LOG_BOTTOM)


## Observer mode (ui.md 5.16.3): the sidebar's build area becomes the `UiObserverBar`, the power dock goes, the F2 scoreboard joins.
func _build_observer() -> void:
	_observer_bar = UiObserverBar.new()
	_sidebar.enter_observer(_observer_bar)
	_sidebar.set_header("OBSERVER", "ALL PLAYERS")
	_dock.visible = false
	_bottom.set_observer(true)
	_top_strip.set_observer(true)
	_scoreboard = UiScoreboard.new()
	_play.add_child(_scoreboard)
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH


## The replay transport is as wide as the free playfield allows (at most 1000 px, at least the width its buttons need).
func _size_replay_bar() -> void:
	if _replay_bar != null:
		_replay_bar.custom_minimum_size = Vector2(clampf(size.x - float(UiMetrics.SIDEBAR_W) - 40.0, 880.0, 1000.0), 0.0)


## Adds the replay transport at the bottom of the playfield (replays only); the selection panel moves up above it.
func add_replay_bar() -> UiReplayBar:
	if _replay_bar != null:
		return _replay_bar
	_replay_bar = UiReplayBar.new()
	_play.add_child(_replay_bar)
	_replay_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_replay_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_replay_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_size_replay_bar()
	_replay_bar.offset_bottom = -float(UiMetrics.BOTTOM_MARGIN)
	_bottom.offset_bottom = -float(UiMetrics.BOTTOM_MARGIN + REPLAY_BAR_H + 8)
	_log.offset_bottom = -float(UiMetrics.LOG_BOTTOM + REPLAY_BAR_H + 8)
	layout_changed.emit(occluded_margins())
	return _replay_bar


## The card hotkeys (Alt+Q ..., Alt+Shift+Q ...): the same routing as a click on the card (`shift` = the x5 variant).
func press_card(item: UiBuildItem, shift: bool) -> void:
	_on_card(item, shift)


## F4: hides (or shows) every panel, keeping the world overlay and the selection rectangle for a clean view of the battlefield.
func set_chrome_visible(on: bool) -> void:
	_chrome_visible = on
	if _play != null:
		_play.visible = on  # bottom panel, top strip, power dock, ribbons, log feed, scoreboard, replay bar
	if _sidebar != null:
		_sidebar.visible = on


func chrome_visible() -> bool:
	return _chrome_visible


# ---- card routing -----------------------------------------------------------------------------------------------------
func _on_card(item: UiBuildItem, shift: bool) -> void:
	if item.kind == UiBuildItem.Kind.POWER:
		power_pressed.emit(item.def_idx)
	elif item.kind == UiBuildItem.Kind.SUPERWEAPON:
		power_pressed.emit(UiPowerDock.SUPERWEAPON)
	elif item.kind == UiBuildItem.Kind.STRUCTURE and item.state == UiBuildItem.State.READY:
		place_requested.emit(item)
	else:
		build_requested.emit(item, 5 if shift else 1)


func _on_card_right(item: UiBuildItem) -> void:
	if item.state == UiBuildItem.State.ON_HOLD:
		build_cancel_requested.emit(item)
	else:
		build_hold_requested.emit(item)


# ---- layout -----------------------------------------------------------------------------------------------------------
func set_size_class(klass: int) -> void:
	size_class = klass
	_ribbons.max_visible = 3 if klass == UiLayout.SizeClass.COMPACT else UiMetrics.RIBBON_MAX
	_log.max_lines = UiLayout.log_lines(klass)
	_sidebar.set_size_class(klass, size.y)
	_bottom.set_playfield(playfield_rect().size.x, klass)
	_size_replay_bar()
	layout_changed.emit(occluded_margins())


func _relayout() -> void:
	if _sidebar == null:
		return
	set_size_class(UiLayout.size_class(size.y))


## Logical px covered by HUD chrome that the camera should avoid: (left, top, right, bottom).
func occluded_margins() -> Vector4:
	var bottom_h: float = float(UiMetrics.BOTTOM_H + UiMetrics.GROUP_BADGE.y + 6.0 + float(UiMetrics.BOTTOM_MARGIN))
	var extra: float = float(REPLAY_BAR_H + 8) if _replay_bar != null else 0.0
	var bottom: float = bottom_h + extra if _bottom != null and _bottom.visible else extra
	return Vector4(0.0, 0.0, float(UiMetrics.SIDEBAR_W), bottom)
