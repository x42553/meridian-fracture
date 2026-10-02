class_name UiLobbyRulesPanel
extends PanelContainer
## Match rules of the lobby (ui.md 5.14.6): starting credits, unit cap, game speed, superweapons, fog of war, shared ally vision
## (there is no veterancy switch: the rule is stored in the sim but has no effect, so the UI does not offer it). Every control writes straight into the `UiLobbyState` and announces `changed()`. With `lan = true` (the LAN roles) the
## panel is more compact and adds the host-only network options of net.md 7.2: pause policy, what happens to a disconnected player,
## the auto-drop timeout and spectators in the lobby. `set_editable(false)` makes the whole panel read-only (a LAN client sees the
## host's rules). A rule value outside the offered lists (a host with another build) is shown as an extra item, never dropped.

signal changed()

const PAUSE_POLICIES: PackedStringArray = ["Host only", "Any player", "Disabled"]
const DISCONNECT_POLICIES: PackedStringArray = ["Player resigns", "AI takes over"]
const AUTO_DROP: PackedInt32Array = [0, 30000, 60000, 120000]

var _state: UiLobbyState = null
var _lan: bool = false
var _credits: OptionButton = null
var _cap: OptionButton = null
var _speed: OptionButton = null
var _pause: OptionButton = null
var _disc: OptionButton = null
var _drop: OptionButton = null
var _checks: Dictionary = {}
var _building: bool = false


func setup(state: UiLobbyState, lan: bool = false) -> void:
	_state = state
	_lan = lan
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6 if lan else 8)
	m.add_child(v)
	v.add_child(UiPanelHeader.new("Rules", "HOST SETTINGS" if lan else "MATCH RULES"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4 if lan else 8)
	v.add_child(grid)
	_credits = _option(grid, "STARTING CREDITS")
	for c: int in UiLobbyState.CREDITS:
		_credits.add_item(UiFormatLite.credits(c) + ("  (preset)" if c == 7500 else ""), c)
	_cap = _option(grid, "UNIT CAP")
	for c: int in UiLobbyState.UNIT_CAPS:
		_cap.add_item(str(c) + ("  (default)" if c == 150 else ""), c)
	_speed = _option(grid, "GAME SPEED")
	var names: Dictionary = {50: "Very slow", 75: "Slow", 100: "Medium", 125: "Fast", 150: "Faster", 200: "Turbo"}
	for s: int in UiLobbyState.SPEEDS:
		_speed.add_item("%s  %d%%" % [names[s], s], s)
	_credits.item_selected.connect(func(i: int) -> void: _set_rule("start_credits", _credits.get_item_id(i)))
	_cap.item_selected.connect(func(i: int) -> void: _set_rule("unit_cap", _cap.get_item_id(i)))
	_speed.item_selected.connect(func(i: int) -> void: _set_rule("speed_pct", _speed.get_item_id(i)))
	if lan:
		_pause = _option(grid, "PAUSING")
		for i: int in PAUSE_POLICIES.size():
			_pause.add_item(PAUSE_POLICIES[i], i)
		_disc = _option(grid, "ON DISCONNECT")
		for i: int in DISCONNECT_POLICIES.size():
			_disc.add_item(DISCONNECT_POLICIES[i], i)
		_drop = _option(grid, "AUTO-DROP STALLED")
		for ms: int in AUTO_DROP:
			_drop.add_item("Never" if ms == 0 else "After %d s" % (ms / 1000), ms)
		_pause.item_selected.connect(func(i: int) -> void: _set_rule("pause_policy", _pause.get_item_id(i)))
		_disc.item_selected.connect(func(i: int) -> void: _set_rule("on_disconnect", _disc.get_item_id(i)))
		_drop.item_selected.connect(func(i: int) -> void: _set_rule("auto_drop_ms", _drop.get_item_id(i)))
		var toggles: GridContainer = GridContainer.new()
		toggles.columns = 2
		toggles.add_theme_constant_override("h_separation", 16)
		toggles.add_theme_constant_override("v_separation", 0)
		v.add_child(toggles)
		_toggle(toggles, "superweapons", "Superweapons")
		_toggle(toggles, "fog", "Fog of war")
		_toggle(toggles, "shared_vision", "Shared ally vision")
		_toggle(toggles, "allow_spectators", "Spectators in the lobby")
	else:
		_toggle(grid, "superweapons", "SUPERWEAPONS", true)
		_toggle(grid, "fog", "FOG OF WAR", true)
		_toggle(grid, "shared_vision", "SHARED ALLY VISION", true)
	refresh()


func _option(grid: GridContainer, caption: String) -> OptionButton:
	grid.add_child(UiScreenKit.label(caption, &"DimLabel"))
	var o: OptionButton = OptionButton.new()
	o.fit_to_longest_item = false
	o.clip_text = true
	o.custom_minimum_size = Vector2(230.0 if not _lan else 200.0, 36.0 if not _lan else 30.0)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(o)
	return o


## `captioned`: the skirmish layout puts a caption label in the first grid column and the check box in the second.
func _toggle(grid: GridContainer, key: String, caption: String, captioned: bool = false) -> void:
	var c: CheckBox = CheckBox.new()
	c.custom_minimum_size = Vector2(0.0, 30.0 if captioned else 26.0)
	if captioned:
		grid.add_child(UiScreenKit.label(caption, &"DimLabel"))
		c.text = "On"
	else:
		c.text = caption
	c.toggled.connect(func(on: bool) -> void:
		if _building:
			return
		_state.set(key, on)
		if captioned:
			c.text = "On" if on else "Off"
		changed.emit())
	grid.add_child(c)
	_checks[key] = c
	c.set_meta(&"captioned", captioned)


func _set_rule(key: String, value: int) -> void:
	if _building:
		return
	_state.set(key, value)
	changed.emit()


## The item index of `value`, adding an extra item when the list does not offer it.
func _select_value(o: OptionButton, value: int, label: String) -> void:
	var idx: int = o.get_item_index(value)
	if idx < 0:
		o.add_item(label, value)
		idx = o.get_item_index(value)
	o.select(idx)


func refresh() -> void:
	_building = true
	_select_value(_credits, _state.start_credits, UiFormatLite.credits(_state.start_credits))
	_select_value(_cap, _state.unit_cap, str(_state.unit_cap))
	_select_value(_speed, _state.speed_pct, "%d%%" % _state.speed_pct)
	if _lan:
		_select_value(_pause, _state.pause_policy, "Policy %d" % _state.pause_policy)
		_select_value(_disc, _state.on_disconnect, "Policy %d" % _state.on_disconnect)
		_select_value(_drop, _state.auto_drop_ms, "%d ms" % _state.auto_drop_ms)
	for key: String in _checks:
		var c: CheckBox = _checks[key] as CheckBox
		c.button_pressed = bool(_state.get(key))
		if bool(c.get_meta(&"captioned", false)):
			c.text = "On" if c.button_pressed else "Off"
	_building = false


## Read-only for a LAN client (the host's rules), editable for the host and in the skirmish.
func set_editable(on: bool) -> void:
	for o: OptionButton in [_credits, _cap, _speed, _pause, _disc, _drop]:
		if o != null:
			o.disabled = not on
	for key: String in _checks:
		(_checks[key] as CheckBox).disabled = not on
