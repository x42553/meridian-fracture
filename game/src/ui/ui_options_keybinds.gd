class_name UiOptionsKeybinds
extends VBoxContainer
## Key-binding table of the Controls page (ui.md 5.6.2, 5.18.1, QA A-05): every rebindable action by category with two slots,
## a filter box, a per-action reset arrow and "Reset all". Click a slot, press the new chord (Esc cancels, Delete unbinds, a right
## click also unbinds). A chord that is refused (modifier alone, OS-reserved, Esc) shows the reason inline; a chord used by an
## action with an overlapping context opens `UiDlgKeyConflict` (swap / unbind the other / cancel). Changes go to the shared
## `UiKeymap`, are written to `[keys]` of the settings store and announced to `AppApply.input_sink`.

## The screen shows the dialog (modal stack).
signal dialog_requested(dlg: UiDialog)
signal bindings_saved()

const NAME_W: float = 310.0
const SLOT_W: float = 168.0

var keymap: UiKeymap = null
var store: AppSettingsStore = null
var settings: Node = null
## Set while a slot waits for a key: `{action, slot}`.
var capturing: Dictionary = {}
## Last inline message (refusal reason).
var message: String = ""

var _filter: LineEdit = null
var _msg: Label = null
var _rows: Dictionary = {}  ## action -> {box, slots: [Button, Button], reset: Button, name: Label, cat: String}
var _heads: Dictionary = {}  ## category -> Label
var _pending: Dictionary = {}  ## the conflict being asked about


func setup(km: UiKeymap, settings_store: AppSettingsStore, settings_node: Node) -> void:
	keymap = km
	store = settings_store
	settings = settings_node
	add_theme_constant_override("separation", 2)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	keymap.bindings_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if keymap != null and keymap.bindings_changed.is_connected(_refresh):
		keymap.bindings_changed.disconnect(_refresh)


func _build() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", UiMetrics.SP_3)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter actions or keys"
	_filter.clear_button_enabled = true
	_filter.custom_minimum_size = Vector2(NAME_W, 34.0)
	_filter.text_changed.connect(apply_filter)
	bar.add_child(_filter)
	var reset_all_b: Button = UiScreenKit.button("Reset all bindings", &"", Vector2(190.0, 34.0))
	reset_all_b.pressed.connect(reset_all)
	bar.add_child(reset_all_b)
	_msg = UiScreenKit.label("", &"CaptionLabel")
	_msg.add_theme_color_override("font_color", UiPalette.WARN)
	_msg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_msg)
	add_child(bar)
	var by_cat: Dictionary = {}
	for id: StringName in keymap.action_ids():
		var cat: String = String(keymap.def_of(id).category)
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(id)
	var order: Array = Array(UiActionNames.CATEGORY_ORDER)
	for c: String in by_cat:
		if not order.has(c):
			order.append(c)
	for cat2: String in order:
		if not by_cat.has(cat2):
			continue
		var head: Label = UiScreenKit.label(UiActionNames.title_of(cat2).to_upper(), &"CaptionLabel")
		var pad: Control = UiScreenKit.spacer(6.0)
		add_child(pad)
		add_child(head)
		_heads[cat2] = [head, pad]
		for id2: StringName in by_cat[cat2]:
			_add_row(id2, cat2)


func _add_row(id: StringName, cat: String) -> void:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", UiMetrics.SP_2)
	h.custom_minimum_size = Vector2(0.0, 36.0)
	var nm: Label = UiScreenKit.label(UiActionNames.label(String(id)), &"", false, HORIZONTAL_ALIGNMENT_LEFT, true)
	nm.custom_minimum_size = Vector2(NAME_W, 0.0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	var slots: Array[Button] = []
	for s: int in 2:
		var b: Button = Button.new()
		b.custom_minimum_size = Vector2(SLOT_W, 32.0)
		b.focus_mode = Control.FOCUS_ALL
		b.clip_text = true
		b.pressed.connect(begin_capture.bind(id, s))
		b.gui_input.connect(_slot_input.bind(id, s))
		slots.append(b)
		h.add_child(b)
	var rs: Button = Button.new()
	rs.text = "↺"
	rs.flat = true
	rs.custom_minimum_size = Vector2(34.0, 32.0)
	rs.tooltip_text = "Reset to the default key"
	rs.pressed.connect(func() -> void: reset_action(id))
	h.add_child(rs)
	add_child(h)
	_rows[id] = {"box": h, "slots": slots, "reset": rs, "name": nm, "cat": cat}


func _slot_input(ev: InputEvent, id: StringName, slot: int) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			unbind(id, slot)


func _refresh() -> void:
	for id: StringName in _rows:
		var r: Dictionary = _rows[id]
		var binds: PackedInt32Array = keymap.bindings(id)
		for s: int in 2:
			var b: Button = (r["slots"] as Array)[s]
			if not capturing.is_empty() and capturing["action"] == id and int(capturing["slot"]) == s:
				b.text = "Press a key..."
				continue
			b.text = UiKeymap.key_label(binds[s]) if s < binds.size() else "Unbound"
			b.modulate = Color.WHITE if s < binds.size() else Color(1, 1, 1, 0.55)
			b.tooltip_text = "Click to rebind, right click to unbind."
		var mod: bool = keymap.is_modified(id)
		(r["reset"] as Button).modulate.a = 1.0 if mod else 0.0
		(r["reset"] as Button).disabled = not mod
		(r["name"] as Label).add_theme_color_override("font_color", UiPalette.TEXT if not mod else UiPalette.CREDITS)
	_msg.text = message


## Shows only actions whose name, id or key label contains `text` (empty = all); empty categories hide their heading.
func apply_filter(text: String) -> void:
	var q: String = text.strip_edges().to_lower()
	var any_in: Dictionary = {}
	for id: StringName in _rows:
		var r: Dictionary = _rows[id]
		var hit: bool = q.is_empty() or (r["name"] as Label).text.to_lower().contains(q) or String(id).contains(q)
		if not hit:
			for packed: int in keymap.bindings(id):
				if UiKeymap.key_label(packed).to_lower().contains(q):
					hit = true
		(r["box"] as Control).visible = hit
		if hit:
			any_in[r["cat"]] = true
	for cat: String in _heads:
		for c: Control in _heads[cat]:
			c.visible = any_in.has(cat)


func visible_actions() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: StringName in _rows:
		if ((_rows[id] as Dictionary)["box"] as Control).visible:
			out.append(String(id))
	return out


func action_count() -> int:
	return _rows.size()


func slot_button(id: StringName, slot: int) -> Button:
	if not _rows.has(id):
		return null
	return ((_rows[id] as Dictionary)["slots"] as Array)[slot] as Button


# ---------------------------------------------------------------------------------------------------------------- editing

## Starts waiting for a chord for `slot` of `id`.
func begin_capture(id: StringName, slot: int) -> void:
	capturing = {"action": id, "slot": slot}
	message = ""
	set_process_input(true)
	_refresh()


func cancel_capture() -> void:
	capturing = {}
	_refresh()


func _input(event: InputEvent) -> void:
	if capturing.is_empty():
		return
	var id: StringName = capturing["action"]
	var slot: int = int(capturing["slot"])
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		get_viewport().set_input_as_handled()
		var code: int = ke.physical_keycode if ke.physical_keycode != KEY_NONE else ke.keycode
		if UiKeymap.MOD_KEYS.has(code):
			return
		if code == KEY_ESCAPE and id != &"toggle_menu":
			cancel_capture()
			return
		if code == KEY_DELETE:
			capturing = {}
			unbind(id, slot)
			return
		capturing = {}
		try_bind(id, slot, UiKeymap.pack(ke))
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		# left / right clicks belong to the UI itself; only extra buttons can be bound, and only where allowed
		if mb.button_index >= MOUSE_BUTTON_MIDDLE and keymap.def_of(id).allow_mouse and mb.button_index != MOUSE_BUTTON_WHEEL_UP \
				and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()
			capturing = {}
			try_bind(id, slot, -int(mb.button_index))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			cancel_capture()


## Binds `packed` in `slot` of `id`: inline reason when refused, `UiDlgKeyConflict` when another action owns the chord.
## Returns true when the binding was made right away (false: refused or waiting for the conflict answer).
func try_bind(id: StringName, slot: int, packed: int) -> bool:
	var def: UiActions.Def = keymap.def_of(id)
	if def == null:
		return false
	var why: String = keymap.refused_reason(id, packed)
	if not why.is_empty():
		message = "%s cannot be used: %s." % [UiKeymap.key_label(packed), why]
		_refresh()
		return false
	var others: PackedStringArray = keymap.conflicts(packed, def.contexts, id)
	if others.is_empty():
		return _commit(id, slot, packed, UiKeymap.Conflict.REFUSE)
	var names: PackedStringArray = PackedStringArray()
	for o: String in others:
		names.append("\"%s\"" % UiActionNames.label(o))
	var current: PackedInt32Array = keymap.bindings(id)
	var can_swap: bool = slot < current.size()
	var dlg: UiDlgKeyConflict = UiDlgKeyConflict.new(UiKeymap.key_label(packed), UiActionNames.label(String(id)), names, can_swap)
	_pending = {"action": id, "slot": slot, "packed": packed, "dialog": dlg}
	dlg.closed.connect(_on_conflict_closed.bind(id, slot, packed), CONNECT_ONE_SHOT)
	dialog_requested.emit(dlg)
	return false


func _on_conflict_closed(result: int, id: StringName, slot: int, packed: int) -> void:
	_pending = {}
	match result:
		UiDlgKeyConflict.SWAP:
			_commit(id, slot, packed, UiKeymap.Conflict.SWAP)
		UiDlgKeyConflict.REPLACE:
			_commit(id, slot, packed, UiKeymap.Conflict.REPLACE)


func pending_conflict() -> Dictionary:
	return _pending


func _commit(id: StringName, slot: int, packed: int, mode: int) -> bool:
	var ok: bool = keymap.bind(id, slot, packed, mode)
	message = "" if ok else "Could not bind: %s." % keymap.last_error
	if ok:
		_save()
	_refresh()
	return ok


func unbind(id: StringName, slot: int) -> void:
	keymap.unbind(id, slot)
	_save()


func reset_action(id: StringName) -> void:
	keymap.reset(id)
	message = ""
	_save()


func reset_all() -> void:
	keymap.reset_all()
	message = ""
	_save()


func _save() -> void:
	keymap.save_to(store)
	AppApply.on_changed(&"controls/*", store)
	if settings != null and settings.has_method("flush"):
		settings.call("flush")
	bindings_saved.emit()
