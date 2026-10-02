class_name UiLobbyMapPanel
extends PanelContainer
## Map panel of the skirmish lobby (ui.md 5.14.5): family, size, layout (start positions), the seed as 8 hex digits with Re-roll,
## the cosmetic map name and a live preview. The preview runs `MapGenJob` (threaded generation), is polled once per frame
## and baked with the view's minimap source; results are cached by (family, size, seed, layout) and a change of any value
## cancels the running job. Start markers show the slots' colours at their start positions.

signal changed()

const DEBOUNCE_S: float = 0.25

var _state: UiLobbyState = null
var _name: Label = null
var _family: OptionButton = null
var _size: OptionButton = null
var _layout: OptionButton = null
var _seed: LineEdit = null
var _preview: UiMapPreview = null
var _job: MapGenJob = null
var _job_key: String = ""
var _cache: Dictionary = {}
var _cur: Dictionary = {}
var _wait: float = -1.0
var _building: bool = false
var _hint: Label = null
var _reroll: Button = null
var _editable: bool = true


## `compact`: the LAN layout gives the middle column less room, so the preview is smaller.
func setup(state: UiLobbyState, compact: bool = false) -> void:
	_state = state
	var m: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	v.add_child(UiPanelHeader.new("Map", "PROCEDURAL  //  SEEDED"))
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	_preview = UiMapPreview.new()
	_preview.custom_minimum_size = Vector2(270.0, 270.0) if not compact else Vector2(226.0, 226.0)
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(_preview)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(UiScreenKit.label("NAME", &"CaptionLabel"))
	_name = UiScreenKit.label("", &"NameLabel")
	col.add_child(_name)
	col.add_child(UiScreenKit.label("FAMILY", &"CaptionLabel"))
	_family = _dropdown(col)
	for f: int in 3:
		_family.add_item(UiMapNames.family_name(f), f)
	var size_parent: Control = col
	var layout_parent: Control = col
	if compact:
		# the LAN layout is short of height: size and start positions share a row
		var pair: HBoxContainer = HBoxContainer.new()
		pair.add_theme_constant_override("separation", 8)
		col.add_child(pair)
		size_parent = VBoxContainer.new()
		layout_parent = VBoxContainer.new()
		size_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.add_child(size_parent)
		pair.add_child(layout_parent)
	size_parent.add_child(UiScreenKit.label("SIZE", &"CaptionLabel"))
	_size = _dropdown(size_parent)
	for s: int in UiLobbyState.SIZES:
		_size.add_item(("%d x %d cells" % [s, s]) if not compact else ("%d x %d" % [s, s]), s)
	layout_parent.add_child(UiScreenKit.label("START POSITIONS" if not compact else "STARTS", &"CaptionLabel"))
	_layout = _dropdown(layout_parent)
	for n: int in [2, 4, 6, 8]:
		_layout.add_item("%d players" % n, n)
	col.add_child(UiScreenKit.label("SEED", &"CaptionLabel"))
	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	col.add_child(seed_row)
	_seed = LineEdit.new()
	_seed.max_length = 8
	_seed.custom_minimum_size = Vector2(140.0, 36.0)
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.add_theme_font_override("font", UiFonts.get_font(UiFonts.Role.NUM))
	seed_row.add_child(_seed)
	var reroll: Button = UiScreenKit.button("RE-ROLL", &"", Vector2(96.0, 36.0))
	_reroll = reroll
	seed_row.add_child(reroll)
	_hint = UiScreenKit.label("", &"CaptionLabel", true)
	col.add_child(_hint)
	_family.item_selected.connect(func(i: int) -> void:
		if _building:
			return
		_state.family = _family.get_item_id(i)
		_edited())
	_size.item_selected.connect(func(i: int) -> void:
		if _building:
			return
		_state.size = _size.get_item_id(i)
		_edited())
	_layout.item_selected.connect(func(i: int) -> void:
		if _building:
			return
		_state.set_layout_players(_layout.get_item_id(i))
		_edited())
	_seed.text_submitted.connect(func(_t: String) -> void: _commit_seed())
	_seed.focus_exited.connect(_commit_seed)
	_seed.text_changed.connect(_on_seed_typing)
	reroll.pressed.connect(func() -> void:
		_state.seed_value = randi() & 0xFFFFFFFF
		_edited())
	refresh()


func _dropdown(parent: Control) -> OptionButton:
	var o: OptionButton = OptionButton.new()
	o.fit_to_longest_item = false
	o.clip_text = true
	o.custom_minimum_size = Vector2(0.0, 36.0)
	parent.add_child(o)
	return o


func _edited() -> void:
	_state.fix_size()
	refresh()
	changed.emit()


func _on_seed_typing(text: String) -> void:
	# keep only hex digits while typing
	var clean: String = ""
	for ch: String in text:
		if "0123456789abcdefABCDEF".contains(ch):
			clean += ch
	if clean != text:
		var pos: int = _seed.caret_column
		_seed.text = clean
		_seed.caret_column = mini(pos, clean.length())


func _commit_seed() -> void:
	if _building:
		return
	var t: String = _seed.text.strip_edges()
	if t == "":
		_seed.text = UiScreenKit.hex8(_state.seed_value)
		return
	var v: int = t.hex_to_int() & 0xFFFFFFFF
	if v != _state.seed_value:
		_state.seed_value = v
		_edited()
	else:
		_seed.text = UiScreenKit.hex8(_state.seed_value)


## Widgets <- state; restarts the (debounced) preview when the map values changed.
func refresh() -> void:
	_building = true
	_family.select(_family.get_item_index(_state.family))
	_size.select(_size.get_item_index(_state.size))
	var minimum: int = _state.min_size()
	for i: int in _size.item_count:
		_size.set_item_disabled(i, _size.get_item_id(i) < minimum)
	var lp: int = _state.layout_players()
	_layout.select(_layout.get_item_index(lp if lp != 3 else 4))
	if not _seed.has_focus():
		_seed.text = UiScreenKit.hex8(_state.seed_value)
	_name.text = UiMapNames.name_for(_state.family, _state.seed_value)
	_hint.text = "%d start positions on this layout. Minimum size %d." % [lp, minimum]
	_building = false
	_schedule_preview()
	_update_markers()


## LAN clients see the host's map read-only (ui.md 5.14.2): the pickers, the seed and Re-roll are disabled.
func set_editable(on: bool) -> void:
	_editable = on
	for c: Control in [_family, _size, _layout, _reroll]:
		if c is OptionButton:
			(c as OptionButton).disabled = not on
		elif c is Button:
			(c as Button).disabled = not on
	_seed.editable = on
	if on:
		refresh()


func highlight_error() -> void:
	var tw: Tween = create_tween()
	for _i: int in 2:
		tw.tween_property(self, "modulate", Color(1.0, 0.55, 0.55), 0.18)
		tw.tween_property(self, "modulate", Color.WHITE, 0.25)


func _key() -> String:
	return "%d|%d|%d|%d" % [_state.family, _state.size, _state.seed_value, _state.layout_players()]


func _schedule_preview() -> void:
	var key: String = _key()
	if key == _job_key and (_job != null or _cache.has(key)):
		return
	if _job != null:
		_job.cancel()
		_job = null
	_job_key = key
	if _cache.has(key):
		_show(_cache[key] as Dictionary)
		return
	_preview.busy = true
	_preview.note = ""
	_wait = DEBOUNCE_S
	set_process(true)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_wait = -1.0
			var err: String = MapGenerator.validate_params(_state.family, _state.size, _state.layout_players())
			if err != "":
				_preview.busy = false
				_preview.texture = null
				_preview.note = "Size too small for %d players" % _state.layout_players()
				set_process(false)
				return
			_preview.note = ""
			_job = MapGenJob.begin({"family": _state.family, "size": _state.size, "seed": _state.seed_value, "layout_players": _state.layout_players(),
				"params": {}}, null, true)
		return
	if _job != null and _job.step(0):
		var m: MapData = _job.result()
		_job = null
		if m != null:
			var starts: Dictionary = {}
			for r: int in m.spawns.size() / MapData.SPAWN_STRIDE:
				starts[m.spawns[r * MapData.SPAWN_STRIDE]] = Vector2((float(m.spawns[r * MapData.SPAWN_STRIDE + 1] % m.w) + 0.5) / float(m.w),
					(float(m.spawns[r * MapData.SPAWN_STRIDE + 1] / m.w) + 0.5) / float(m.h))
			var entry: Dictionary = {"tex": AppViewStage.bake_preview(m), "starts": starts}
			_cache[_job_key] = entry
			_show(entry)
		else:
			_preview.busy = false
	if _job == null and _wait < 0.0:
		set_process(false)


func _show(entry: Dictionary) -> void:
	_cur = entry
	_preview.texture = entry["tex"] as Texture2D
	_preview.busy = false
	_update_markers()


func _update_markers() -> void:
	if _cur.is_empty() or _preview == null:
		return
	var starts: Dictionary = _cur["starts"] as Dictionary
	var pos: PackedVector2Array = PackedVector2Array()
	var cols: PackedColorArray = PackedColorArray()
	var txt: PackedStringArray = PackedStringArray()
	var resolved: PackedInt32Array = _state.resolved_starts()
	for i: int in UiLobbyState.MAX_SLOTS:
		if not _state.slots[i].active() or not starts.has(resolved[i]):
			continue
		pos.append(starts[resolved[i]] as Vector2)
		cols.append(UiPalette.team(_state.slots[i].color))
		txt.append(str(i + 1))
	_preview.set_markers(pos, cols, txt)


func set_highlight(slot: int) -> void:
	if _preview == null:
		return
	var idx: int = -1
	var n: int = 0
	for i: int in UiLobbyState.MAX_SLOTS:
		if _state.slots[i].active():
			if i == slot:
				idx = n
			n += 1
	_preview.highlight = idx


func cancel() -> void:
	if _job != null:
		_job.cancel()
		_job = null
