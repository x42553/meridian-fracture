extends RefCounted
## The wiring `UiScreenGame` will do (UI-15), reduced to what the input tests need: controller signals -> selection,
## control groups, armed modes, resolver and command bus. The UI never mutates the sim; every effect is a command via the
## bus. Not a test file (no `test_*` functions).

const V := preload("res://src/ui/ui_view_port.gd")
const KM_BOX_UNITS: int = V.PICK_UNITS | V.PICK_OWN | V.PICK_AIR

var port: UiSimPort
var view: UiViewPortFixture
var sel: UiSelection = UiSelection.new()
var bus: UiCommandBus
var groups: UiControlGroups = UiControlGroups.new()
var bookmarks: UiBookmarks = UiBookmarks.new()
var modes: UiModes = UiModes.new()
var actions: UiSelectionActions = UiSelectionActions.new()
var ctl: UiInputController
var viewer: int = 0
var empty_ticks: int = 0  ## how often a recalled group was empty (the soft tick)


func setup(p_port: UiSimPort, p_view: UiViewPortFixture, p_bus: UiCommandBus, p_ctl: UiInputController) -> void:
	port = p_port
	view = p_view
	bus = p_bus
	ctl = p_ctl
	viewer = port.viewer_pid()
	actions.setup(port, view, sel, null)
	ctl.select_box.connect(on_select_box)
	ctl.select_click.connect(on_select_click)
	ctl.context_click.connect(on_context_click)
	ctl.armed_click.connect(on_armed_click)
	ctl.cancel_armed.connect(func() -> void: modes.disarm())
	ctl.action.connect(on_action)
	modes.changed.connect(func(a: int, _prev: int) -> void: ctl.armed = a)
	sel.changed.connect(func(_m: int) -> void: view.set_selection(sel.ids))


func on_select_box(rect: Rect2, mode: int) -> void:
	var out: PackedInt32Array = PackedInt32Array()
	view.pick_box(rect, KM_BOX_UNITS, out)
	if out.is_empty():
		view.pick_box(rect, V.PICK_STRUCTURES | V.PICK_OWN, out)
	if mode == 1:
		sel.add(out, port)
	else:
		sel.replace(out, port)


func on_select_click(pos: Vector2, mode: int, dbl: bool) -> void:
	var eid: int = view.pick(pos, V.PICK_ANY)
	var row := UiEntityRow.new()
	if eid < 0 or not port.read(eid, row):
		if mode == 0:
			sel.clear()
		return
	var own: bool = row.owner == viewer
	if dbl and own and row.kind == UiEntityRow.K_UNIT:
		sel.replace(actions.same_type_on_screen(UiSimPort.KIND_UNIT, row.def_idx), port)
	elif mode == 1 and own:
		sel.toggle(eid, port)
	else:
		sel.replace(PackedInt32Array([eid]), port)


func _resolve_and_dispatch(pos: Vector2, mods: int, armed: int) -> int:
	var tgt: UiTarget = UiContextResolver.make_target(port, view, pos, viewer)
	var info: UiSelectionInfo = UiSelectionInfo.build(sel, port)
	var m: int = modes.effective_mods(((UiContextResolver.MOD_QUEUE if (mods & UiKeymap.MOD_SHIFT) != 0 else 0)
		| (UiContextResolver.MOD_FORCE if (mods & UiKeymap.MOD_CTRL) != 0 else 0)))
	return bus.dispatch(UiContextResolver.resolve(info, tgt, m, armed))


func on_context_click(pos: Vector2, mods: int) -> void:
	_resolve_and_dispatch(pos, mods, UiModes.Armed.NONE)


func on_armed_click(pos: Vector2, mods: int) -> void:
	var armed: int = modes.armed
	if _resolve_and_dispatch(pos, mods, armed) > 0:
		modes.consume((mods & UiKeymap.MOD_SHIFT) != 0)


func on_action(id: StringName) -> void:
	var n: int = UiActions.indexed(id, "group_select_")
	if n >= 0:
		var ids: PackedInt32Array = groups.recall(n, port)
		if ids.is_empty():
			empty_ticks += 1
		else:
			sel.replace(ids, port)
		if groups.register_press(n, ctl.time_override_ms):
			var c: Vector2i = groups.centroid_sim(n, port)
			if c.x >= 0:
				view.focus_on_sim(c.x, c.y)
		return
	n = UiActions.indexed(id, "group_assign_")
	if n >= 0:
		groups.assign(n, sel.sorted_ids())
		return
	n = UiActions.indexed(id, "group_add_")
	if n >= 0:
		groups.add_to(n, sel.sorted_ids())
		return
	n = UiActions.indexed(id, "group_append_")
	if n >= 0:
		sel.add(groups.recall(n, port), port)
		return
	n = UiActions.indexed(id, "cam_bookmark_set_")
	if n >= 1:
		bookmarks.set_slot(n - 1, view.camera_state())
		return
	n = UiActions.indexed(id, "cam_bookmark_")
	if n >= 1:
		view.set_camera_state(bookmarks.get_slot(n - 1))
		return
	match id:
		&"cmd_attack_move":
			modes.arm(UiModes.Armed.ATTACK_MOVE)
		&"cmd_stop":
			bus.simple(UiOrderIntent.Kind.STOP, sel.sorted_ids())
		&"sel_all_military":
			sel.replace(actions.all_military(false), port)
		&"toggle_menu":
			modes.disarm()
