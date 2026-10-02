class_name UiHudPresenter
extends RefCounted
## The one place that pulls from `UiSimPort` and pushes to the HUD widgets (ui.md 3.4, cadences of 5.10.1), and turns
## HUD gestures into `UiCommandBus` calls. `on_events` (AppEvents consumer, order 20) prunes the selection and raises
## the basic alerts; `on_ticks` runs the cadences (economy, progress and dock every tick batch, card states / queue /
## badges at 2 Hz, minimap feed and selection panel every 2 ticks); `on_frame` does the per-frame work (camera quad, ribbon
## countdowns, deferred selection refresh). World gestures of an active placement / targeting are routed through
## `world_motion` / `world_press` / `world_release` / `cancel_modes`, which the input controller calls first.
## The view, the notifier and the icon cache are injected as `Object`s and probed with `has_method`, so the presenter
## runs against the fixture, the real adapters or nothing at all.

signal menu_requested()
signal camera_center_requested(sim_x: int, sim_y: int, instant: bool)

const FULL_EVERY: int = 10  ## ticks between full card-state refreshes (2 Hz)
const FEED_EVERY: int = 2  ## minimap feed and selection panel (10 Hz)
const SLOW_EVERY: int = 20  ## top strip, income, minimap fog placeholder
const ALERT_COOLDOWN_MSEC: int = 8000
const PICK_OWN_ENTITY: int = 11  ## PICK_UNITS | PICK_STRUCTURES | PICK_OWN

## Optional collaborators set by the screen.
var modes: UiModes = null
var auto_place: bool = true  ## a finished structure opens placement when Structures / Defense is the active tab
var icon_provider: Callable = Callable()  ## (item: UiBuildItem) -> Texture2D (null = keep the glyph placeholder)
var groups_summary: Callable = Callable()  ## (index 0..9) -> {count: int, glyph: int}
var show_score: bool = false
## Observer HUD (replays, spectating; task REP2): no build model, no placement, no power dock, no per-player alerts; the viewer is
## `UiSimPort.viewer_pid()` (-1 = everyone).
var observer: bool = false

var _sim: UiSimPort = null
var _view: Object = null
var _audio: UiAudioPort = null
var _roster: DefRoster = null
var _data: GameData = null
var _hud: UiHud = null
var _sel: UiSelection = null
var _groups: Object = null
var _bus: UiCommandBus = null
var _placement: UiPlacement = null
var _targeting: UiTargeting = null
var _notifier: Object = null
var _model: UiBuildModel = UiBuildModel.new()
var _feed: UiMinimapFeed = UiMinimapFeed.new()
var _info: UiSelectionInfo = null
var _caps: UiUnitCaps = null
var _row: UiEntityRow = UiEntityRow.new()
var _tmp: PackedInt32Array = PackedInt32Array()
var _q: PackedInt32Array = PackedInt32Array()
var _qi: PackedInt32Array = PackedInt32Array()
var _cs: PackedInt32Array = PackedInt32Array()
var _rs: PackedInt32Array = PackedInt32Array()
var _stats: Dictionary = {}
var _tab: int = UiBuildModel.Tab.STRUCTURES
var _since_full: int = 1 << 20
var _since_feed: int = 1 << 20
var _since_slow: int = 1 << 20
var _sel_dirty: bool = true
var _queue_producer: int = -1
var _income_hist: Array[Vector2i] = []
var _fog_img: Image = null
var _fog_tex: ImageTexture = null
var _quad_accum: float = 0.0
var _cool: Dictionary = {}  ## rule -> wall msec of the last post
var _lost_pending: int = 0
var _lost_flush_msec: int = 0
var _warn_ids: PackedInt32Array = PackedInt32Array()
var _sw_ready_shown: bool = false
## Sim position of the latest alert of the viewer (attack, base lost, enemy superweapon); (-1, -1) = none yet. Space jumps there.
var last_alert: Vector2i = Vector2i(-1, -1)
var _ticks_seen: int = 0
var _auto_offered: Dictionary = {}  ## structure def -> true once its READY state was offered for placement


## Ports variant of `setup`: everything explicit (tests, labs and the screen glue use this).
func setup_ports(sim: UiSimPort, view: Object, audio: UiAudioPort, roster: DefRoster, hud: UiHud, selection: UiSelection, groups: Object,
		bus: UiCommandBus, placement: UiPlacement, targeting: UiTargeting, notifier: Object, icons: Callable = Callable()) -> void:
	_sim = sim
	_view = view
	_audio = audio
	_roster = roster
	_data = sim.data()
	_hud = hud
	_sel = selection
	_groups = groups
	_bus = bus
	_placement = placement
	_targeting = targeting
	_notifier = notifier
	icon_provider = icons
	_caps = UiUnitCaps.shared_for(sim)
	_model.rebuild(sim, roster)
	_wire()
	_hud.overlay().setup(view, sim)
	if view != null and view.has_method(&"minimap_texture"):
		_hud.minimap().set_source(view.call(&"minimap_texture") as Texture2D, view.call(&"minimap_material") as Material if view.has_method(&"minimap_material") else null)
	_hud.minimap().set_feed(_feed)
	if view != null and view.has_signal(&"icon_ready") and not view.is_connected(&"icon_ready", _on_icon_ready):
		view.connect(&"icon_ready", _on_icon_ready)
	refresh_all()
	if _view_has_icons() and view.has_method(&"prewarm"):
		view.call(&"prewarm")


## `AppMatchContext` variant (ui.md 3.4): reads `sim`, `view`, `audio`, `roster` from the context and forwards the audio
## caption stream to the notifier.
func setup(ctx: Object, hud: UiHud, selection: UiSelection, groups: Object, bus: UiCommandBus, placement: UiPlacement,
		targeting: UiTargeting, notifier: Object, icons: Object) -> void:
	var audio: UiAudioPort = ctx.get(&"audio") as UiAudioPort
	var provider: Callable = Callable()
	if icons != null and icons.has_method(&"item_icon"):
		provider = Callable(icons, &"item_icon")
	setup_ports(ctx.get(&"sim") as UiSimPort, ctx.get(&"view") as Object, audio, ctx.get(&"roster") as DefRoster, hud, selection, groups, bus, placement, targeting, notifier, provider)
	if audio != null and notifier != null and notifier.has_method(&"on_caption"):
		audio.caption.connect(Callable(notifier, &"on_caption"))


func model() -> UiBuildModel:
	return _model


func active_tab() -> int:
	return _tab


func _wire() -> void:
	_hud.tab_changed.connect(_on_tab_changed)
	_hud.build_requested.connect(_on_build_requested)
	_hud.build_hold_requested.connect(_on_hold_requested)
	_hud.build_cancel_requested.connect(_on_cancel_requested)
	_hud.place_requested.connect(func(it: UiBuildItem) -> void: begin_placement(it.def_idx))
	_hud.power_pressed.connect(_on_power_pressed)
	_hud.tool_pressed.connect(_on_tool)
	_hud.command_pressed.connect(_on_command)
	_hud.ability_pressed.connect(_on_ability)
	_hud.ability_right_pressed.connect(_on_ability_right)
	_hud.tile_pressed.connect(_on_tile)
	_hud.group_pressed.connect(_on_group)
	_hud.camera_requested.connect(func(n: Vector2) -> void: _center_on_norm(n, false))
	_hud.camera_snap.connect(func(n: Vector2) -> void: _center_on_norm(n, true))
	_hud.minimap_order.connect(_on_minimap_order)
	_hud.queue_slot_pressed.connect(_on_queue_slot)
	_hud.queue_slot_right_pressed.connect(_on_queue_slot_right)
	_hud.queue_hold_toggled.connect(_on_queue_hold)
	_hud.queue_primary_pressed.connect(_on_queue_primary)
	_hud.producer_cycled.connect(_on_producer_cycled)
	_hud.layout_changed.connect(_apply_margins)
	_sel.changed.connect(func(_m: int) -> void: _on_selection_changed())
	if _groups != null and _groups.has_signal(&"changed"):
		_groups.connect(&"changed", func(_i: int) -> void: _update_groups())
	_placement.ended.connect(func(_c: bool, _d: int) -> void: _model.placing_def = -1)
	if modes != null and not modes.changed.is_connected(_on_mode_changed):
		modes.changed.connect(_on_mode_changed)


## Connects an `UiModes` after `setup` (the screen owns it).
func set_modes(m: UiModes) -> void:
	modes = m
	if not m.changed.is_connected(_on_mode_changed):
		m.changed.connect(_on_mode_changed)


# ---- refresh ----------------------------------------------------------------------------------------------------------
## After a tab switch, viewer change or theme change: rebuilds the model and re-pushes everything.
func refresh_all() -> void:
	_since_full = FULL_EVERY
	_since_feed = FEED_EVERY
	_since_slow = SLOW_EVERY
	_sel_dirty = true
	if observer:
		_income_hist.clear()
		_update_economy()
		_update_top_strip()
		_update_feed()
		_update_selection_panel()
		_update_alert_state()
		_since_full = 0
		_since_feed = 0
		_since_slow = 0
		return
	_model.rebuild(_sim, _roster)
	_apply_icons()
	_full_refresh()
	_show_tab(_tab)
	_update_economy()
	_update_top_strip()
	_update_feed()
	_update_selection_panel()
	_update_groups()
	_update_power_dock()
	_update_queue()
	_update_fog_placeholder()
	_since_full = 0
	_since_feed = 0
	_since_slow = 0


## AppEvents consumer: selection prune + successor rule, then the basic alerts.
func on_events(records: PackedInt32Array) -> void:
	if records.is_empty():
		return
	var succ: Dictionary = {}
	UiSelection.successors_of(records, succ)
	for i: int in UiEv.count(records):
		if UiEv.field(records, i, UiEv.I_TYPE) == UiEv.REMOVED:
			var eid: int = UiEv.field(records, i, UiEv.I_A)
			if _sel.has(eid):
				_sel.on_removed(eid, UiEv.field(records, i, UiEv.I_E), int(succ.get(eid, -1)))
	_sel.prune(_sim)
	if observer:
		return  # no per-player alerts without a player
	for i2: int in UiEv.count(records):
		var rec: PackedInt32Array = records.slice(i2 * UiEv.STRIDE, (i2 + 1) * UiEv.STRIDE)
		if _notifier != null and _notifier.has_method(&"on_event"):
			_notifier.call(&"on_event", rec)
		else:
			_basic_alert(rec)
	if _lost_pending > 0 and Time.get_ticks_msec() >= _lost_flush_msec:
		_flush_lost()


## 20 Hz entry (`ticks` sim ticks were executed this frame).
func on_ticks(ticks: int) -> void:
	if _sim == null:
		return
	_ticks_seen += ticks
	_since_full += ticks
	_since_feed += ticks
	_since_slow += ticks
	_update_economy()
	if observer:
		_observer_ticks()
		return
	_model.refresh_progress(_sim)
	_apply_changes()
	_update_power_dock()
	if _placement.active:
		var ready: PackedInt32Array = PackedInt32Array()
		_sim.construction_state(ready)
		if _placement.check_ready(ready[UiSimPort.CS_READY_DEF] if ready[UiSimPort.CS_STATE] == UiSimPort.Construction.READY_TO_PLACE else -1):
			_toast("Placement cancelled: the structure is no longer ready.", UiPalette.WARN)
	_model.placing_def = _placement.card_def()
	if _since_full >= FULL_EVERY:
		_since_full = 0
		_full_refresh()
	if _since_feed >= FEED_EVERY:
		_since_feed = 0
		_update_feed()
		_update_selection_panel()
		_update_queue_progress()
	if _since_slow >= SLOW_EVERY:
		_since_slow = 0
		_update_top_strip()
		_update_groups()
		_update_fog_placeholder()
	if _lost_pending > 0 and Time.get_ticks_msec() >= _lost_flush_msec:
		_flush_lost()


## The observer HUD's slow cadences (no build model).
func _observer_ticks() -> void:
	if _since_feed >= FEED_EVERY:
		_since_feed = 0
		_update_feed()
		_update_selection_panel()
	if _since_slow >= SLOW_EVERY:
		_since_slow = 0
		_update_top_strip()
		_update_fog_placeholder()
		_update_alert_state()


## Per-frame work: camera quad at <= 30 Hz, deferred selection refresh, ribbon countdowns.
func on_frame(delta: float) -> void:
	if _sim == null:
		return
	_quad_accum += delta
	if _quad_accum >= 1.0 / float(UiMetrics.MINIMAP_HZ):
		_quad_accum = 0.0
		if _view != null and _view.has_method(&"frustum_ground_quad"):
			_hud.minimap().set_camera_quad(_view.call(&"frustum_ground_quad") as PackedVector2Array)
	if _sel_dirty:
		_update_selection_panel()
	_update_ribbon_countdowns()


# ---- economy / strip ---------------------------------------------------------------------------------------------------
func _update_economy() -> void:
	var sb: UiSidebar = _hud.sidebar()
	sb.credits().set_credits(_sim.credits())
	sb.power_bar().capacity = _sim.power_supply()
	sb.power_bar().usage = _sim.power_demand()
	if observer:
		sb.set_economy_visible(_sim.viewer_pid() >= 0)
	else:
		sb.set_footer("UNIT CAP %d / %d     BUILD RADIUS %d" % [_sim.unit_count(), _sim.unit_cap(), _build_radius_cells()])
	var t: int = _sim.tick()
	if _income_hist.is_empty() or t - _income_hist[_income_hist.size() - 1].x >= 20:
		_income_hist.append(Vector2i(t, _sim.harvested_total()))
		while _income_hist.size() > 2 and t - _income_hist[0].x > 1200:
			_income_hist.remove_at(0)
		var first: Vector2i = _income_hist[0]
		var last: Vector2i = _income_hist[_income_hist.size() - 1]
		if last.x > first.x:
			sb.credits().income_per_min = (last.y - first.y) * 1200 / (last.x - first.x)


## Build radius of the roster's HQ in cells (the footer number).
func _build_radius_cells() -> int:
	if _roster == null or _data == null:
		return 0
	var hq: DefStructure = _roster.structure(_roster.hq_idx)
	return hq.build_radius / 1024 if hq != null else 0


func _update_top_strip() -> void:
	var ts: UiTopStrip = _hud.top_strip()
	ts.set_time(_sim.tick())
	var pid: int = _sim.viewer_pid()
	if pid >= 0:
		_sim.player_stats(pid, _stats)
		ts.set_stats(int(_stats.get("units_killed", 0)), int(_stats.get("units_lost", 0)))


func _update_feed() -> void:
	_feed.rebuild(_sim, _caps)
	_hud.minimap().map_cells = Vector2i(_sim.map_w(), _sim.map_h())


func _update_fog_placeholder() -> void:
	if _view != null and _view.has_method(&"minimap_material") and _view.call(&"minimap_material") is ShaderMaterial:
		return  # the view's fog shader draws the fog itself
	if not _sim.rule_flag(UiSimPort.RF_FOG):
		return
	_fog_img = UiMinimapFeed.bake_fog(_sim, _fog_img)
	if _fog_tex == null or _fog_tex.get_width() != _fog_img.get_width() or _fog_tex.get_height() != _fog_img.get_height():
		_fog_tex = ImageTexture.create_from_image(_fog_img)
	else:
		_fog_tex.update(_fog_img)
	_hud.minimap().set_fog(_fog_tex)


func _apply_margins(m: Vector4) -> void:
	if _view != null and _view.has_method(&"set_camera_margins"):
		var f: float = 1.0
		var w: Window = _hud.get_window() if _hud.is_inside_tree() else null
		if w != null:
			f = w.content_scale_factor
		_view.call(&"set_camera_margins", m.x * f, m.y * f, m.z * f, m.w * f)


# ---- build model -> sidebar --------------------------------------------------------------------------------------------
func _selected_producers() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _sel.mode == UiSelection.Mode.STRUCTURES:
		out.append_array(_sel.ids)
	return out


func _full_refresh() -> void:
	_model.placing_def = _placement.card_def()
	_model.refresh(_sim, _selected_producers())
	_apply_icons()
	_apply_changes()
	var sb: UiSidebar = _hud.sidebar()
	for t: int in UiBuildModel.TAB_COUNT:
		var n: int = _model.ready_count(t)
		sb.set_tab_badge(t, str(n) if n > 0 else "")
	_hud.sidebar().set_tab_info(_model.items(_tab).size(), _model.ready_count(_tab))
	_update_queue()
	_update_power_dock()
	_update_alert_state()
	if auto_place and not _placement.active and (_tab == UiBuildModel.Tab.STRUCTURES or _tab == UiBuildModel.Tab.DEFENSE):
		for it: UiBuildItem in _model.items(UiBuildModel.Tab.STRUCTURES) + _model.items(UiBuildModel.Tab.DEFENSE):
			if it.state == UiBuildItem.State.READY and not _auto_offered.has(it.def_idx):
				_auto_offered[it.def_idx] = true
				begin_placement(it.def_idx)
				break
	for k: int in _auto_offered.keys():
		var itm: UiBuildItem = _model.item_for(UiBuildItem.Kind.STRUCTURE, k)
		if itm == null or itm.state != UiBuildItem.State.READY and itm.state != UiBuildItem.State.PLACING:
			_auto_offered.erase(k)



func _apply_changes() -> void:
	var sb: UiSidebar = _hud.sidebar()
	for it: UiBuildItem in _model.take_changed():
		if it.tab == _tab:
			sb.refresh_item(it, _tip_of)


func _tip_of(it: UiBuildItem) -> Dictionary:
	return _model.tooltip_spec(it)


func _apply_icons() -> void:
	var provider: Callable = icon_provider if icon_provider.is_valid() else (_default_icon if _view_has_icons() else Callable())
	if not provider.is_valid():
		return
	for t: int in UiBuildModel.TAB_COUNT:
		for it: UiBuildItem in _model.items(t):
			if it.icon == null:
				it.icon = provider.call(it) as Texture2D


## True for a view that bakes real icons (`UiViewPortWorld`); the fixture view keeps the glyph placeholders.
func _view_has_icons() -> bool:
	return _view != null and _view.has_method(&"icons_available") and bool(_view.call(&"icons_available"))


## Baked CARD icon of a structure / unit card in the local roster's faction style; null until ready and for powers / research.
func _default_icon(it: UiBuildItem) -> Texture2D:
	if it.kind != UiBuildItem.Kind.STRUCTURE and it.kind != UiBuildItem.Kind.UNIT:
		return null
	return _view.call(&"request_icon", it.id, _roster.id, UiViewPort.ICON_SIZE_CARD) as Texture2D


## A baked icon finished: card images, queue strip and the selection panel pick it up.
func _on_icon_ready(_key: StringName) -> void:
	_apply_icons()
	var sb: UiSidebar = _hud.sidebar()
	for it: UiBuildItem in _model.items(_tab):
		sb.refresh_item(it, _tip_of)
	_update_queue()
	_sel_dirty = true


func _show_tab(tab: int) -> void:
	_tab = tab
	var sb: UiSidebar = _hud.sidebar()
	if sb.active_tab() != tab:
		sb.select_tab(tab)
	sb.set_items(_model.items(tab), _tip_of)
	sb.set_tab_info(_model.items(tab).size(), _model.ready_count(tab))
	_update_queue()


func _on_tab_changed(tab: int) -> void:
	_show_tab(tab)


func _update_power_dock() -> void:
	var list: Array[UiBuildItem] = []
	var powers: Array[UiBuildItem] = []
	for it: UiBuildItem in _model.items(UiBuildModel.Tab.POWERS):
		if it.kind == UiBuildItem.Kind.POWER:
			powers.append(it)
	powers.sort_custom(func(a: UiBuildItem, b: UiBuildItem) -> bool: return _sim.power_slot(a.def_idx) < _sim.power_slot(b.def_idx))
	list.append_array(powers)
	var sw: UiBuildItem = null
	for it2: UiBuildItem in _model.items(UiBuildModel.Tab.POWERS):
		if it2.kind == UiBuildItem.Kind.SUPERWEAPON:
			sw = it2
	if sw != null:
		list.append(sw)
	_hud.power_dock().set_items(list)


# ---- queue strip -------------------------------------------------------------------------------------------------------
static func queue_kind_of_tab(tab: int) -> int:
	match tab:
		UiBuildModel.Tab.INFANTRY:
			return DefEnums.QueueKind.INFANTRY
		UiBuildModel.Tab.VEHICLES:
			return DefEnums.QueueKind.VEHICLE
		UiBuildModel.Tab.AIRCRAFT:
			return DefEnums.QueueKind.AIRCRAFT
		UiBuildModel.Tab.NAVAL:
			return DefEnums.QueueKind.NAVAL
	return DefEnums.QueueKind.NONE


func _is_unit_tab() -> bool:
	return queue_kind_of_tab(_tab) != DefEnums.QueueKind.NONE


## Producer shown in the queue strip: a selected producer of the tab's kind, else the primary, else the first.
func _pick_queue_producer() -> void:
	var qk: int = queue_kind_of_tab(_tab)
	if qk == DefEnums.QueueKind.NONE:
		_queue_producer = -1
		return
	var all: PackedInt32Array = PackedInt32Array()
	_sim.producers(qk, all)
	if all.is_empty():
		_queue_producer = -1
		return
	if all.has(_queue_producer):
		return
	for p: int in _selected_producers():
		if all.has(p):
			_queue_producer = p
			return
	for p2: int in all:
		if _sim.read(p2, _row) and _row.is_primary:
			_queue_producer = p2
			return
	_queue_producer = all[0]


func _update_queue() -> void:
	var strip: UiQueueStrip = _hud.sidebar().queue()
	var slots: Array[Dictionary] = []
	var title: String = ""
	var held: bool = false
	var primary: bool = false
	var can_cycle: bool = false
	if _is_unit_tab():
		_pick_queue_producer()
		if _queue_producer > 0 and _sim.read(_queue_producer, _row):
			var all: PackedInt32Array = PackedInt32Array()
			_sim.producers(queue_kind_of_tab(_tab), all)
			can_cycle = all.size() > 1
			var s: DefStructure = _roster.structure(_row.def_idx)
			title = "%s %d  //  QUEUE" % [(s.ui_name if s != null else "PRODUCER").to_upper(), all.find(_queue_producer) + 1]
			primary = _row.is_primary
			_sim.queue_info(_queue_producer, _qi)
			held = _qi[UiSimPort.QI_QSTATE] == UiSimPort.QueueState.HELD
			var n: int = _sim.queue_of(_queue_producer, _q)
			for i: int in n:
				var it: UiBuildItem = _model.item_for(UiBuildItem.Kind.UNIT, _q[i])
				if it != null:
					slots.append({"item": it, "progress": float(_qi[UiSimPort.QI_PROGRESS]) / 1000.0 if i == 0 else 0.0})
		else:
			title = "NO PRODUCER"
	elif _tab == UiBuildModel.Tab.STRUCTURES or _tab == UiBuildModel.Tab.DEFENSE:
		title = "BUILD  //  QUEUE"
		_sim.construction_state(_cs)
		held = _cs[UiSimPort.CS_QSTATE] == UiSimPort.QueueState.HELD
		if _cs[UiSimPort.CS_STATE] != UiSimPort.Construction.IDLE and _cs[UiSimPort.CS_DEF] >= 0:
			var head: UiBuildItem = _model.item_for(UiBuildItem.Kind.STRUCTURE, _cs[UiSimPort.CS_DEF])
			if head != null:
				slots.append({"item": head, "progress": float(_cs[UiSimPort.CS_PROGRESS]) / 1000.0})
			var nq: int = _sim.construction_queue(_tmp)
			for i2: int in nq:
				var it2: UiBuildItem = _model.item_for(UiBuildItem.Kind.STRUCTURE, _tmp[i2])
				if it2 != null:
					slots.append({"item": it2, "progress": 0.0})
	elif _tab == UiBuildModel.Tab.RESEARCH:
		title = "RESEARCH  //  QUEUE"
		_sim.research_state(_rs)
		held = _rs.size() > 3 and _rs[3] == UiSimPort.QueueState.HELD
		if _rs.size() > 0 and _rs[0] >= 0:
			var ra: UiBuildItem = _model.item_for(UiBuildItem.Kind.RESEARCH, _rs[0])
			if ra != null:
				slots.append({"item": ra, "progress": float(_rs[1]) / 1000.0})
			var rq: int = _rs[4] if _rs.size() > 4 else 0
			for i3: int in rq:
				var rit: UiBuildItem = _model.item_for(UiBuildItem.Kind.RESEARCH, _rs[5 + i3])
				if rit != null:
					slots.append({"item": rit, "progress": 0.0})
	else:
		title = "POWERS"
	strip.set_data(title, slots, held, primary, can_cycle)


func _update_queue_progress() -> void:
	if _hud.sidebar().queue().visible:
		_update_queue()


func _on_producer_cycled(direction: int) -> void:
	var all: PackedInt32Array = PackedInt32Array()
	_sim.producers(queue_kind_of_tab(_tab), all)
	if all.size() < 2:
		return
	var i: int = all.find(_queue_producer)
	_queue_producer = all[posmod(i + direction, all.size())]
	_update_queue()


func _on_queue_slot(index: int) -> void:
	if _is_unit_tab():
		if _queue_producer > 0:
			_bus.train_cancel(_queue_producer, index)
	elif _tab == UiBuildModel.Tab.RESEARCH:
		_bus.research_cancel(index)
	else:
		_bus.build_cancel(index)
	_since_full = FULL_EVERY


## RMB on a slot: every queued instance of that def in the same queue, highest index first (<= 5 commands).
func _on_queue_slot_right(index: int) -> void:
	if _is_unit_tab():
		if _queue_producer <= 0:
			return
		var n: int = _sim.queue_of(_queue_producer, _q)
		if index >= n:
			return
		var def: int = _q[index]
		var idxs: Array[int] = []
		for i: int in n:
			if _q[i] == def:
				idxs.append(i)
		idxs.reverse()
		for i2: int in idxs:
			_bus.train_cancel(_queue_producer, i2)
	else:
		_on_queue_slot(index)
	_since_full = FULL_EVERY


func _on_queue_hold() -> void:
	var on_now: bool = _hud.sidebar().queue().held
	if _is_unit_tab():
		if _queue_producer > 0:
			_bus.queue_hold(UiCmdCodec.Hold.PRODUCER, PackedInt32Array([_queue_producer]), not on_now)
	elif _tab == UiBuildModel.Tab.RESEARCH:
		_bus.queue_hold(UiCmdCodec.Hold.RESEARCH, PackedInt32Array(), not on_now)
	else:
		_bus.queue_hold(UiCmdCodec.Hold.CONSTRUCTION, PackedInt32Array(), not on_now)
	_since_full = FULL_EVERY


func _on_queue_primary() -> void:
	if _queue_producer > 0:
		_bus.set_primary(_queue_producer)
	_since_full = FULL_EVERY


# ---- card interactions (5.10.4) ----------------------------------------------------------------------------------------
func _deny(text: String) -> void:
	if _audio != null:
		_audio.ui(UiAudioPort.ERROR)
	_toast(text, UiPalette.WARN)


func _toast(text: String, col: Color = UiPalette.TEXT_DIM) -> void:
	_hud.log_feed().add(text, col)


func _hold_kind(it: UiBuildItem) -> int:
	match it.kind:
		UiBuildItem.Kind.STRUCTURE:
			return UiCmdCodec.Hold.CONSTRUCTION
		UiBuildItem.Kind.RESEARCH:
			return UiCmdCodec.Hold.RESEARCH
	return UiCmdCodec.Hold.PRODUCER


func _hold_ids(it: UiBuildItem) -> PackedInt32Array:
	return PackedInt32Array([it.producer_eid]) if it.kind == UiBuildItem.Kind.UNIT else PackedInt32Array()


func _on_build_requested(it: UiBuildItem, count: int) -> void:
	if it.state == UiBuildItem.State.LOCKED or it.state == UiBuildItem.State.BLOCKED:
		var why: String = ("Requires " + it.requires_text) if it.requires_text != "" else (it.reason_text if it.reason_text != "" else "Not available")
		_deny(why)
		_hud.sidebar().pulse_tab(UiBuildModel.Tab.STRUCTURES)
		return
	if it.state == UiBuildItem.State.ON_HOLD:
		_bus.queue_hold(_hold_kind(it), _hold_ids(it), false)
		_since_full = FULL_EVERY
		return
	match it.kind:
		UiBuildItem.Kind.STRUCTURE:
			if it.state == UiBuildItem.State.PLACING:
				return
			if _bus.build_start(it.def_idx, 1) and _audio != null:
				_audio.ui(UiAudioPort.QUEUE_ADD)
		UiBuildItem.Kind.UNIT:
			var p: int = it.producer_eid if it.producer_eid > 0 else UiProducerPicker.pick(_sim, it.queue_kind, it.def_idx, _selected_producers())
			if p <= 0:
				_deny("No producer available")
				return
			if _bus.train(p, it.def_idx, count) and _audio != null:
				_audio.ui(UiAudioPort.QUEUE_ADD)
		UiBuildItem.Kind.RESEARCH:
			if it.state != UiBuildItem.State.DONE and _bus.research(it.def_idx) and _audio != null:
				_audio.ui(UiAudioPort.QUEUE_ADD)
	_since_full = FULL_EVERY


func _on_hold_requested(it: UiBuildItem) -> void:
	match it.kind:
		UiBuildItem.Kind.UNIT:
			var p: int = it.producer_eid
			if p <= 0:
				return
			if it.queued >= 2:
				_bus.train_cancel_def(p, it.def_idx)
			elif it.state == UiBuildItem.State.BUILDING:
				_bus.queue_hold(UiCmdCodec.Hold.PRODUCER, PackedInt32Array([p]), true)
				_cue(UiAudioPort.QUEUE_HOLD)
			elif it.state == UiBuildItem.State.QUEUED:
				var n: int = _sim.queue_of(p, _q)
				for i: int in range(n - 1, -1, -1):
					if _q[i] == it.def_idx:
						_bus.train_cancel(p, i)
						break
		UiBuildItem.Kind.STRUCTURE:
			if it.state == UiBuildItem.State.BUILDING and it.queued < 2:
				_bus.queue_hold(UiCmdCodec.Hold.CONSTRUCTION, PackedInt32Array(), true)
				_cue(UiAudioPort.QUEUE_HOLD)
			else:
				var nq: int = _sim.construction_queue(_tmp)
				for i2: int in range(nq - 1, -1, -1):
					if _tmp[i2] == it.def_idx:
						_bus.build_cancel(1 + i2)
						break
		UiBuildItem.Kind.RESEARCH:
			if it.state == UiBuildItem.State.BUILDING:
				_bus.queue_hold(UiCmdCodec.Hold.RESEARCH, PackedInt32Array(), true)
				_cue(UiAudioPort.QUEUE_HOLD)
			elif it.state == UiBuildItem.State.QUEUED:
				_sim.research_state(_rs)
				var rq: int = _rs[4] if _rs.size() > 4 else 0
				for i3: int in rq:
					if _rs[5 + i3] == it.def_idx:
						_bus.research_cancel(1 + i3)
						break
	_since_full = FULL_EVERY


func _on_cancel_requested(it: UiBuildItem) -> void:
	match it.kind:
		UiBuildItem.Kind.UNIT:
			if it.producer_eid > 0:
				_bus.train_cancel(it.producer_eid, 0)
		UiBuildItem.Kind.STRUCTURE:
			_bus.build_cancel(0)
		UiBuildItem.Kind.RESEARCH:
			_bus.research_cancel(0)
	_since_full = FULL_EVERY


func _cue(id: StringName) -> void:
	if _audio != null:
		_audio.ui(id)


# ---- placement and targeting -------------------------------------------------------------------------------------------
func begin_placement(def_idx: int) -> bool:
	if _targeting.active:
		_targeting.cancel()
	var ok: bool = _placement.begin(def_idx)
	if ok:
		_model.placing_def = def_idx
		if modes != null:
			modes.arm(UiModes.Armed.PLACE, def_idx)
	return ok


func _on_power_pressed(idx: int) -> void:
	if _placement.active:
		_placement.cancel()
	if idx == UiPowerDock.SUPERWEAPON:
		if _sim.sw_status() != UiSimPort.SwStatus.READY:
			_deny("Superweapon not ready")
			return
		_targeting.begin_superweapon()
		return
	var st: int = _sim.power_status(idx)
	if st != UiSimPort.PowerStatus.READY:
		var it: UiBuildItem = _model.item_for(UiBuildItem.Kind.POWER, idx)
		_deny(it.reason_text if it != null and it.reason_text != "" else "Power not ready")
		return
	_targeting.begin_power(idx)


## Sim position under a screen point ((-1, -1) = off the map).
func ground_sim_at(screen: Vector2) -> Vector2i:
	return _view_ground_sim(screen)


func _view_ground_sim(screen: Vector2) -> Vector2i:
	if _view == null or not _view.has_method(&"pick_ground"):
		return Vector2i(-1, -1)
	var g: Vector3 = _view.call(&"pick_ground", screen)
	if not g.is_finite():
		return Vector2i(-1, -1)
	return _view.call(&"world_to_sim", g)


## Pointer motion over the world while a placement or a targeting is active.
func world_motion(screen: Vector2) -> void:
	if _placement.active:
		_placement.update_pointer(screen)
	elif _targeting.active:
		var s: Vector2i = _view_ground_sim(screen)
		if s.x >= 0:
			_targeting.update(s.x, s.y, _own_under(screen))


func _own_under(screen: Vector2) -> int:
	if _view != null and _view.has_method(&"pick") and _targeting.target_mode == DefEnums.TargetMode.OWN_STRUCTURE:
		return int(_view.call(&"pick", screen, PICK_OWN_ENTITY))
	return 0


## LMB / RMB press over the world. Returns true when a placement / targeting consumed it.
func world_press(screen: Vector2, button: int) -> bool:
	if _placement.active:
		if button == MOUSE_BUTTON_LEFT:
			_placement.update_pointer(screen)
			_placement.commit()
		elif button == MOUSE_BUTTON_RIGHT:
			_placement.cancel()
		return true
	if _targeting.active:
		if button == MOUSE_BUTTON_LEFT:
			var s: Vector2i = _view_ground_sim(screen)
			if s.x >= 0:
				if _targeting.is_pressing():
					_targeting.release(s.x, s.y)  # a line power: the first click set the start, this one commits the angle
				else:
					_targeting.press(s.x, s.y, _own_under(screen))
		elif button == MOUSE_BUTTON_RIGHT:
			_targeting.cancel()
		return true
	return false


func world_release(screen: Vector2, button: int) -> bool:
	if _targeting.active and button == MOUSE_BUTTON_LEFT:
		var s: Vector2i = _view_ground_sim(screen)
		if s.x >= 0:
			return _targeting.release(s.x, s.y)
	return false


## Esc chain entry: cancels an active placement / targeting; true when one was cancelled.
## F5..F7 (`slot` 0..2): the power of that dock slot, the same path as a click on its card (not ready / no credits are denied with the
## reason). False when the roster has no power in the slot.
func press_power_slot(slot: int) -> bool:
	var dock: UiPowerDock = _hud.power_dock()
	for i: int in dock.item_count():
		var it: UiBuildItem = dock.item_at(i)
		if it.kind == UiBuildItem.Kind.POWER and _sim.power_slot(it.def_idx) == slot:
			_on_power_pressed(it.def_idx)
			return true
	_deny("No support power in slot %d" % (slot + 1))
	return false


## F8: starts the superweapon targeting (the same path as its dock button; a charging one is denied with a toast).
func press_superweapon() -> bool:
	if _roster == null or _roster.superweapon_def == null:
		_deny("This faction has no superweapon")
		return false
	_on_power_pressed(UiPowerDock.SUPERWEAPON)
	return true


## I / O / K / L (`n` 0..3): the n-th ability button of the active subgroup (the slot the bar shows that hotkey on).
func press_ability_hotkey(n: int) -> bool:
	var k: int = 0
	for b: Dictionary in _ability_buttons():
		if int(b.get("slot", -1)) < 0:
			continue
		if k == n:
			_on_ability(int(b["slot"]))
			return true
		k += 1
	return false


## Alt+<key> / Alt+Shift+<key>: the card in grid slot `slot` of the active tab (`five` = the x5 variant of a unit card).
func press_card_slot(slot: int, five: bool) -> bool:
	var list: Array[UiBuildItem] = _model.items(_tab)
	if slot < 0 or slot >= list.size():
		return false
	_hud.press_card(list[slot], five)
	return true


## Space: centres the camera on the latest alert (false = none yet).
func jump_to_alert() -> bool:
	if last_alert.x < 0:
		_toast("No alert to jump to yet.", UiPalette.TEXT_DIM)
		return false
	camera_center_requested.emit(last_alert.x, last_alert.y, false)
	return true


## A one-line message in the log feed (hotkey feedback).
func notice(text: String, col: Color = UiPalette.TEXT_DIM) -> void:
	_toast(text, col)


## A ping on the minimap and a marker in the world: the local player's own ping (`ally` false) or a teammate's (`ally` true).
func show_ping(sim_x: int, sim_y: int, ally: bool) -> void:
	var m: UiMinimap = _hud.minimap()
	var cells: Vector2i = m.map_cells
	var col: Color = UiPalette.semantic(&"ok") if ally else UiPalette.TEXT
	m.add_ping(Vector2(float(sim_x) / float(cells.x * 1024), float(sim_y) / float(cells.y * 1024)), col, UiMinimap.PING_KIND_ALLY)
	_hud.overlay().add_order_marker(UiOrderIntent.MK_MOVE, sim_x, sim_y)


func cancel_modes() -> bool:
	if _placement.active:
		_placement.cancel()
		return true
	if _targeting.active:
		_targeting.cancel()
		return true
	return false


# ---- tools and commands -------------------------------------------------------------------------------------------------
func _toggle_mode(m: int) -> void:
	if modes == null:
		return
	if modes.armed == m:
		modes.disarm()
	else:
		modes.arm(m)


func _on_tool(id: StringName) -> void:
	match id:
		&"repair":
			_toggle_mode(UiModes.Armed.REPAIR)
		&"sell":
			_toggle_mode(UiModes.Armed.SELL)
		&"rally":
			_toggle_mode(UiModes.Armed.RALLY)
		&"waypoint":
			if modes != null:
				modes.toggle_waypoint()
		&"menu":
			menu_requested.emit()


func _on_mode_changed(armed: int, _prev: int) -> void:
	var cb: UiCommandBar = _hud.bottom().commands()
	cb.set_armed(&"attack_move", armed == UiModes.Armed.ATTACK_MOVE)
	cb.set_armed(&"guard", armed == UiModes.Armed.GUARD)
	cb.set_armed(&"sell", armed == UiModes.Armed.SELL)
	cb.set_armed(&"repair", armed == UiModes.Armed.REPAIR)
	var sb: UiSidebar = _hud.sidebar()
	sb.set_tool_armed(&"repair", armed == UiModes.Armed.REPAIR)
	sb.set_tool_armed(&"sell", armed == UiModes.Armed.SELL)
	sb.set_tool_armed(&"rally", armed == UiModes.Armed.RALLY)
	sb.set_tool_armed(&"waypoint", modes != null and modes.waypoint_latch)


func _unit_ids() -> PackedInt32Array:
	return _sel.sorted_ids() if _sel.mode == UiSelection.Mode.UNITS else PackedInt32Array()


func _on_command(id: StringName) -> void:
	var ids: PackedInt32Array = _unit_ids()
	match id:
		&"attack_move":
			_toggle_mode(UiModes.Armed.ATTACK_MOVE)
		&"guard":
			_toggle_mode(UiModes.Armed.GUARD)
		&"patrol":
			_toggle_mode(UiModes.Armed.PATROL)
		&"move":
			_toggle_mode(UiModes.Armed.MOVE)
		&"force_fire":
			_toggle_mode(UiModes.Armed.FORCE_FIRE)
		&"follow":
			_toggle_mode(UiModes.Armed.FOLLOW)
		&"sell":
			_toggle_mode(UiModes.Armed.SELL)
		&"repair":
			_toggle_mode(UiModes.Armed.REPAIR)
		&"stop":
			if not ids.is_empty():
				_bus.simple(UiOrderIntent.Kind.STOP, ids)
		&"scatter":
			if not ids.is_empty():
				_bus.simple(UiOrderIntent.Kind.SCATTER, ids)
		&"hold":
			if not ids.is_empty():
				_bus.hold(ids)
		&"deploy":
			if not ids.is_empty():
				_bus.deploy_toggle(ids)
			elif _sel.mode == UiSelection.Mode.STRUCTURES:
				_bus.undeploy_hq(_sel.sorted_ids())
		&"stance":
			if not ids.is_empty() and _sim.read(_sel.primary, _row):
				_bus.stance(ids, (maxi(_row.stance, 0) + 1) % 4)
		&"return":
			if not ids.is_empty():
				var c: int = _info.caps_any if _info != null else 0
				if (c & UiUnitCaps.CAP_COLLECTOR) != 0:
					_bus.simple(UiOrderIntent.Kind.RETURN_CASH, ids)
				else:
					_bus.return_to_base(ids, 0)
		&"unload":
			if not ids.is_empty():
				_bus.unload(ids)


func _active_def_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: int in _sel.sorted_ids():
		if _sel.def_of(id) == _sel.active_def:
			out.append(id)
	return out


func _on_ability(slot: int) -> void:
	var ids: PackedInt32Array = _active_def_ids()
	if ids.is_empty():
		return
	var u: DefUnit = _roster.unit(_sel.active_def)
	if u == null or slot < 0 or slot >= u.abilities.size():
		return
	if u.abilities[slot].kind == DefEnums.AbilityKind.MODE_SWITCH:
		_sim.read(_sel.primary, _row)
		_bus.set_mode(ids, slot, 1 - clampi(_row.mode, 0, 1))
	else:
		_bus.use_ability(ids, slot)


func _on_ability_right(slot: int) -> void:
	var ids: PackedInt32Array = _active_def_ids()
	if not ids.is_empty():
		_bus.set_autocast(ids, slot, true)


# ---- minimap / camera / groups / tiles ------------------------------------------------------------------------------------
func _center_on_norm(norm: Vector2, instant: bool) -> void:
	var s: Vector2i = _hud.minimap().norm_to_sim(norm)
	if _view != null and _view.has_method(&"focus_on_sim"):
		_view.call(&"focus_on_sim", s.x, s.y, instant)
	camera_center_requested.emit(s.x, s.y, instant)


func _on_minimap_order(norm: Vector2, mods: int) -> void:
	if _sel.is_empty():
		return
	var s: Vector2i = _hud.minimap().norm_to_sim(norm)
	var info: UiSelectionInfo = UiSelectionInfo.build(_sel, _sim, _caps)
	var armed: int = modes.armed if modes != null else UiModes.Armed.NONE
	var m: int = (UiContextResolver.MOD_QUEUE if (mods & 1) != 0 else 0) | (UiContextResolver.MOD_FORCE if (mods & 2) != 0 else 0)
	if modes != null:
		m = modes.effective_mods(m)
	var intent: UiOrderIntent = UiContextResolver.resolve(info, UiTarget.ground(s.x, s.y), m, armed)
	if intent.kind != UiOrderIntent.Kind.NONE and intent.kind != UiOrderIntent.Kind.DENIED:
		_bus.dispatch(intent)
		if modes != null:
			modes.consume((mods & 1) != 0)


func _on_group(index: int, double: bool) -> void:
	if _groups == null or not _groups.has_method(&"recall"):
		return
	var ids: PackedInt32Array = _groups.call(&"recall", index, _sim)
	if ids.is_empty():
		_cue(UiAudioPort.GROUP_RECALL)
		return
	_sel.replace(ids, _sim)
	_cue(UiAudioPort.GROUP_RECALL)
	if double and _groups.has_method(&"centroid_sim"):
		var c: Vector2i = _groups.call(&"centroid_sim", index, _sim)
		if c.x >= 0 and _view != null and _view.has_method(&"focus_on_sim"):
			_view.call(&"focus_on_sim", c.x, c.y, false)


func _on_tile(index: int, mods: int) -> void:
	var view: UiSelectionView = _hud.bottom().selection_view()
	if index < 0 or index >= view.entries.size():
		return
	var eid: int = int(view.entries[index].get("id", -1))
	if eid < 0:
		return
	if (mods & UiSelectionView.MOD_SHIFT) != 0:
		_sel.remove(eid)
	elif (mods & UiSelectionView.MOD_CTRL) != 0:
		var def: int = _sel.def_of(eid)
		var same := PackedInt32Array()
		for id: int in _sel.ids:
			if _sel.def_of(id) == def:
				same.append(id)
		_sel.replace(same, _sim)
	else:
		_sel.replace(PackedInt32Array([eid]), _sim)


func _update_groups() -> void:
	var g: Array[Dictionary] = []
	for i: int in 10:
		g.append(_groups_summary_of(i))
	_hud.bottom().group_bar().set_groups(g)


## {count, glyph} of control group `i` (empty Dictionary = empty group): the alive count and the glyph of the first member.
func _groups_summary_of(i: int) -> Dictionary:
	if groups_summary.is_valid():
		return groups_summary.call(i)
	if _groups == null or not _groups.has_method(&"count"):
		return {}
	var n: int = int(_groups.call(&"count", i, _sim))
	if n <= 0:
		return {}
	var glyph: int = UiGlyphs.Glyph.VEHICLES
	var members: PackedInt32Array = _groups.call(&"members", i)
	for id: int in members:
		if _sim.read(id, _row):
			glyph = UiGlyphs.role_glyph_structure(_roster.structure(_row.def_idx)) if _row.is_structure() else UiGlyphs.role_glyph_unit(_roster.unit(_row.def_idx))
			break
	return {"count": n, "glyph": glyph}


# ---- selection panel ------------------------------------------------------------------------------------------------------
func _on_selection_changed() -> void:
	_sel_dirty = true
	_info = null
	if _sel.mode == UiSelection.Mode.STRUCTURES:
		_queue_producer = -1  # a newly selected producer takes over the queue strip
	if _view != null and _view.has_method(&"set_selection"):
		_view.call(&"set_selection", _sel.ids)
	if _view != null and _view.has_method(&"set_rally_sources"):
		_view.call(&"set_rally_sources", _selected_producers())
	_push_overlay_sources()
	_update_selection_panel()
	_since_full = FULL_EVERY  # the producer of a card may have changed


## Range rings (`ui/range_rings`, same ids as the Options row): 0 the selection (every selected armed entity, the view caps at 12),
## 1 never, 2 always: the selection plus the armed entity under the pointer.
const RINGS_SELECTION: int = 0
const RINGS_NEVER: int = 1
const RINGS_HOVER: int = 2
var range_ring_mode: int = RINGS_SELECTION
var _hover_ring: int = 0


## Sets the mode from the setting value and refreshes the rings.
func set_range_ring_mode(mode: int) -> void:
	range_ring_mode = clampi(mode, RINGS_SELECTION, RINGS_HOVER)
	_push_overlay_sources()


## The entity under the pointer (0 none); it gets a ring in mode RINGS_HOVER.
func set_hover_entity(eid: int) -> void:
	var e: int = maxi(eid, 0)
	if e == _hover_ring:
		return
	_hover_ring = e
	if range_ring_mode == RINGS_HOVER:
		_push_overlay_sources()


## Tells the view which selected entities get range rings and queued-order (waypoint) lines. The view filters: unarmed
## entities have no ring, only own units draw orders.
func _push_overlay_sources() -> void:
	if _view == null:
		return
	if _view.has_method(&"set_range_rings"):
		var rings: PackedInt32Array = PackedInt32Array()
		if range_ring_mode != RINGS_NEVER:
			rings = _sel.ids.duplicate()
			if range_ring_mode == RINGS_HOVER and _hover_ring > 0 and not rings.has(_hover_ring):
				rings.append(_hover_ring)
		_view.call(&"set_range_rings", rings)
	if _view.has_method(&"set_order_sources"):
		_view.call(&"set_order_sources", _sel.ids if _sel.mode == UiSelection.Mode.UNITS else PackedInt32Array())


const _ROLE_LABELS: Array = [
	[DefEnums.UT_COLLECTOR, "COLLECTOR"], [DefEnums.UT_CONSTRUCTION, "CONSTRUCTION"], [DefEnums.UT_CAPTURE, "ENGINEER"],
	[DefEnums.UT_TRANSPORT, "TRANSPORT"], [DefEnums.UT_CARRIER, "CARRIER"], [DefEnums.UT_SUBMARINE, "SUBMARINE"],
	[DefEnums.UT_ANTI_AIR, "ANTI-AIR"], [DefEnums.UT_ARTILLERY, "ARTILLERY"], [DefEnums.UT_SIEGE, "SIEGE"],
	[DefEnums.UT_SCOUT, "SCOUT"], [DefEnums.UT_TANK, "BATTLE TANK"], [DefEnums.UT_SHIP, "WARSHIP"],
	[DefEnums.UT_AIRCRAFT, "AIRCRAFT"], [DefEnums.UT_INFANTRY, "INFANTRY"],
]


## Role line of a def (CAPS): the first matching capability tag, else the class.
func role_label(kind: int, def_idx: int) -> String:
	if kind == UiSimPort.KIND_STRUCTURE:
		var s: DefStructure = _roster.structure(def_idx)
		if s == null:
			return "STRUCTURE"
		if (s.tags & DefEnums.ST_SUPERWEAPON) != 0:
			return "SUPERWEAPON"
		if (s.tags & (DefEnums.ST_DEFENSE | DefEnums.ST_ADVANCED_DEFENSE)) != 0:
			return "DEFENSE STRUCTURE"
		if (s.flags & DefEnums.SF_PRODUCTION) != 0:
			return "PRODUCTION"
		return "STRUCTURE"
	var u: DefUnit = _roster.unit(def_idx)
	if u == null:
		return "UNIT"
	for pair: Array in _ROLE_LABELS:
		if (u.tags & int(pair[0])) != 0:
			return String(pair[1])
	return "UNIT"


func _entry_of(id: int) -> Dictionary:
	if not _sim.read(id, _row):
		return {}
	var structure: bool = _row.is_structure()
	var kind: int = UiSimPort.KIND_STRUCTURE if structure else UiSimPort.KIND_UNIT
	var sd: DefStructure = null
	var ud: DefUnit = null
	if structure:
		sd = _roster.structure(_row.def_idx)
		if sd == null and _data != null and _row.def_idx >= 0 and _row.def_idx < _data.structures.size():
			sd = _data.structures[_row.def_idx]
	else:
		ud = _roster.unit(_row.def_idx)
		if ud == null and _data != null and _row.def_idx >= 0 and _row.def_idx < _data.units.size():
			ud = _data.units[_row.def_idx]
	var glyph: int = UiGlyphs.role_glyph_structure(sd) if structure else UiGlyphs.role_glyph_unit(ud)
	var nm: String = "?"
	var id_of_def: String = ""
	if structure and sd != null:
		nm = sd.ui_name
		id_of_def = sd.id
	elif ud != null:
		nm = ud.ui_name
		id_of_def = ud.id
	var vet: int = _row.vet if _sim.rule_flag(UiSimPort.RF_VETERANCY) else 0
	return {
		"id": id, "def": _row.def_idx, "name": nm, "role": role_label(kind, _row.def_idx),
		"hp": _row.hp_permille(), "hp_now": _row.hp, "hp_max": _row.hp_max, "vet": vet, "squad": _row.squad, "squad_max": _row.squad_max,
		"glyph": glyph, "icon": _icon_for(structure, _row.def_idx, id_of_def), "portrait": _portrait_for(id_of_def, _row.owner), "tip": "",
	}


## Tile icon: the card of the local roster when it has one, else a baked CARD icon in the owner's faction style (enemy units).
func _icon_for(structure: bool, def_idx: int, def_id: String = "") -> Texture2D:
	var it: UiBuildItem = _model.item_for(UiBuildItem.Kind.STRUCTURE if structure else UiBuildItem.Kind.UNIT, def_idx)
	if it != null and it.icon != null:
		return it.icon
	if def_id != "" and _view_has_icons():
		return _view.call(&"request_icon", def_id, _owner_roster_id(_row.owner), UiViewPort.ICON_SIZE_CARD) as Texture2D
	return null


## Large selection portrait (BANNER 2:1) in the style of the entity's owner; null until baked.
func _portrait_for(def_id: String, owner: int) -> Texture2D:
	if def_id == "" or not _view_has_icons():
		return null
	return _view.call(&"request_icon", def_id, _owner_roster_id(owner), UiViewPort.ICON_SIZE_BANNER) as Texture2D


func _owner_roster_id(owner: int) -> String:
	var r: DefRoster = _sim.roster_of(owner) if owner >= 0 else null
	return r.id if r != null else (_roster.id if _roster != null else "")


func _update_selection_panel() -> void:
	_sel_dirty = false
	var panel: UiBottomPanel = _hud.bottom()
	var view: UiSelectionView = panel.selection_view()
	var n: int = _sel.size()
	if n == 0:
		view.set_selection([], 0, 0, UiSelection.Mode.NONE)
		view.set_details(PackedStringArray(), [])
		panel.commands().apply_caps(0, UiSelection.Mode.NONE, false)
		panel.abilities().set_buttons([])
		if observer:
			panel.visible = false  # the observer's panel only exists while something is selected
		return
	if _info == null:
		_info = UiSelectionInfo.build(_sel, _sim, _caps)
	var cap: int = view.capacity()
	var entries: Array[Dictionary] = []
	var primary_i: int = 0
	for i: int in mini(n, cap):
		var id: int = _sel.ids[i]
		var e: Dictionary = _entry_of(id)
		if e.is_empty():
			continue
		if id == _sel.primary:
			primary_i = entries.size()
		entries.append(e)
	if _sel.primary >= 0 and not _has_entry(entries, _sel.primary):
		var pe: Dictionary = _entry_of(_sel.primary)
		if not pe.is_empty():
			if entries.size() >= cap and cap > 0:
				entries.pop_back()
			entries.append(pe)
			primary_i = entries.size() - 1
	view.set_selection(entries, n, primary_i, _sel.mode)
	var primary_row_ok: bool = _sim.read(_sel.primary, _row)
	if n == 1 or _sel.mode == UiSelection.Mode.FOREIGN or _sel.mode == UiSelection.Mode.STRUCTURES:
		_single_details(view, primary_row_ok)
	else:
		view.set_details(PackedStringArray(), [])
	if observer:
		panel.visible = true
		panel.commands().apply_caps(0, UiSelection.Mode.FOREIGN, false)  # an observer inspects, it does not command
		panel.abilities().set_buttons([])
		return
	panel.commands().apply_caps(_info.caps_any, _sel.mode, (_info.caps_any & UiUnitCaps.CAP_SELLABLE) != 0)
	panel.abilities().set_buttons(_ability_buttons())


func _has_entry(entries: Array[Dictionary], id: int) -> bool:
	for e: Dictionary in entries:
		if int(e.get("id", -1)) == id:
			return true
	return false


func _single_details(view: UiSelectionView, ok: bool) -> void:
	var chips := PackedStringArray()
	var lines: Array[Dictionary] = []
	if not ok:
		view.set_details(chips, lines)
		return
	if _sel.mode == UiSelection.Mode.FOREIGN:
		view.owner_text = _sim.name_of(_row.owner) if _row.owner >= 0 else "Neutral"
		view.owner_color = UiPalette.team(_sim.color_of(_row.owner)) if _row.owner >= 0 else UiPalette.TEXT_MUTE
		view.set_details(chips, lines)
		return
	if _row.has_flag(UiEntityRow.F_EMP):
		chips.append("EMP")
	if _row.has_flag(UiEntityRow.F_SUPPRESSED):
		chips.append("SUPPRESSED")
	if _row.has_flag(UiEntityRow.F_CAMO):
		chips.append("CAMOUFLAGED")
	if _row.has_flag(UiEntityRow.F_DEPLOYED):
		chips.append("DEPLOYED")
	if _row.has_flag(UiEntityRow.F_SELLING):
		chips.append("SELLING")
	if _row.is_structure():
		chips.append("OFFLINE" if _row.has_flag(UiEntityRow.F_UNPOWERED) else "POWERED")
		if _row.queue_len > 0:
			lines.append({"text": "%d queued" % _row.queue_len, "color": UiPalette.TEXT_DIM})
		var sv: int = _sim.sell_value(_sel.primary)
		if sv > 0:
			lines.append({"text": "Sell for $%s" % UiBuildItem.group_digits(sv), "color": UiPalette.CREDITS})
	else:
		if _row.cargo_cap > 0:
			lines.append({"text": "Cargo %d / %d" % [_row.cargo, _row.cargo_cap], "color": UiPalette.TEXT_DIM})
		if _row.ammo >= 0:
			lines.append({"text": "Ammo %d" % _row.ammo, "color": UiPalette.TEXT_DIM})
		var st: PackedStringArray = ["Aggressive", "Defensive", "Hold fire", "Guard"]
		if _row.stance >= 0 and _row.stance < st.size():
			lines.append({"text": "Stance: " + st[_row.stance], "color": UiPalette.TEXT_MUTE})
	view.set_details(chips, lines)


## Utility row + ability slots for the active subgroup (5.11.5 / 5.11.6), five buttons at most.
func _ability_buttons() -> Array[Dictionary]:
	return UiAbilityButtons.build(_sel, _info, _roster, _sim, _row)


# ---- alerts (basics; a UiNotifier replaces them) ------------------------------------------------------------------------
func _sector(sim_x: int, sim_y: int) -> String:
	var w: int = maxi(_sim.map_w(), 1)
	var h: int = maxi(_sim.map_h(), 1)
	var col: int = clampi((sim_x >> 10) * 8 / w, 0, 7)
	var row: int = clampi((sim_y >> 10) * 8 / h, 0, 7)
	return "%s%d" % [char(65 + col), row + 1]


func _cooled(rule: StringName, msec: int) -> bool:
	var now: int = Time.get_ticks_msec()
	if now - int(_cool.get(rule, -1000000)) < msec:
		return false
	_cool[rule] = now
	return true


## `UiFeedback` duck-typing: the screen passes the presenter as both `overlay` and `minimap` of `UiFeedback.setup`.
func add_marker(marker_kind: int, sim_x: int, sim_y: int, _target_eid: int = -1) -> void:
	_hud.overlay().add_order_marker(marker_kind, sim_x, sim_y)


## `UiFeedback` duck-typing (see `add_marker`): a minimap ping at a sim point.
func add_ping(kind: int, sim_x: int, sim_y: int) -> void:
	var cells: Vector2i = _hud.minimap().map_cells
	var col: Color = UiPalette.DANGER if kind == UiMinimap.PING_KIND_ALERT else UiPalette.TEXT
	_hud.minimap().add_ping(Vector2(float(sim_x) / float(cells.x * 1024), float(sim_y) / float(cells.y * 1024)), col, kind)


func _ping_at(sim_x: int, sim_y: int, kind: int, col: Color) -> void:
	last_alert = Vector2i(sim_x, sim_y)
	var m: UiMinimap = _hud.minimap()
	var cells: Vector2i = m.map_cells
	var n := Vector2(float(sim_x) / float(cells.x * 1024), float(sim_y) / float(cells.y * 1024))
	m.add_ping(n, col, kind)
	_hud.overlay().add_edge_alert(sim_x, sim_y, kind)
	_cue(UiAudioPort.ALERT)


func _basic_alert(ev: PackedInt32Array) -> void:
	var viewer: int = _sim.viewer_pid()
	var x: int = ev[UiEv.I_X]
	var y: int = ev[UiEv.I_Y]
	match ev[UiEv.I_TYPE]:
		UiEv.ATTACK_ALERT:
			if ev[UiEv.I_A] != viewer:
				return
			var cls: int = ev[UiEv.I_D]
			if cls == 1:
				if _cooled(&"base_attack", ALERT_COOLDOWN_MSEC):
					var nm: String = "Structure"
					if _sim.read(ev[UiEv.I_B], _row):
						var s: DefStructure = _roster.structure(_row.def_idx)
						nm = s.ui_name if s != null else nm
					_hud.ribbons().post(&"base_attack", UiRibbon.Severity.WARN, "BASE UNDER ATTACK", "%s  //  %s" % [nm, _sector(x, y)], UiGlyphs.Glyph.WARNING, -1.0, -1.0, "ALERT", 6.0, x, y)
					_toast("Base under attack at %s" % _sector(x, y), UiPalette.WARN)
					_ping_at(x, y, UiMinimap.PING_KIND_ALERT, UiPalette.WARN)
			elif cls == 2:
				if _cooled(&"collector_attack", 10000):
					_toast("Collector under attack at %s" % _sector(x, y), UiPalette.WARN)
					_ping_at(x, y, UiMinimap.PING_KIND_ALERT, UiPalette.WARN)
			elif _cooled(&"unit_attack", 10000):
				_toast("Unit under attack at %s" % _sector(x, y))
				_ping_at(x, y, UiMinimap.PING_KIND_ALERT, UiPalette.WARN)
		UiEv.DEATH:
			if UiEv.death_owner(ev[UiEv.I_E]) != viewer:
				return
			var fl: int = UiEv.death_flags(ev[UiEv.I_C])
			if (fl & 16) != 0:
				if ev[UiEv.I_B] == _roster.hq_idx:
					_hud.ribbons().post(&"hq_lost", UiRibbon.Severity.DANGER, "HEADQUARTERS DESTROYED", _sector(x, y), UiGlyphs.Glyph.WARNING, -1.0, -1.0, "", 8.0, x, y)
					_ping_at(x, y, UiMinimap.PING_KIND_ALERT, UiPalette.DANGER)
				elif _cooled(&"structure_lost", 4000):
					_toast("Structure lost at %s" % _sector(x, y), UiPalette.WARN)
			elif (fl & 64) != 0 and (fl & (4 | 8)) == 0 and (_sim.def_flags(UiSimPort.KIND_UNIT, ev[UiEv.I_B]) & UiSimPort.DF_COUNTS_FOR_CAP) != 0:
				_lost_pending += 1
				if _lost_flush_msec == 0 or Time.get_ticks_msec() >= _lost_flush_msec:
					_lost_flush_msec = Time.get_ticks_msec() + 3000
		UiEv.STRUCTURE_READY:
			if ev[UiEv.I_A] != viewer:
				return
			var sd: DefStructure = _roster.structure(ev[UiEv.I_B])
			_toast("Construction complete: %s. Ready to place." % (sd.ui_name if sd != null else "structure"), UiPalette.OK)
			_since_full = FULL_EVERY
		UiEv.RESEARCH_COMPLETE:
			if ev[UiEv.I_A] == viewer and _data != null and ev[UiEv.I_B] < _data.research.size():
				_toast("Research complete: %s" % _data.research[ev[UiEv.I_B]].ui_name, UiPalette.OK)
		UiEv.INSUFFICIENT_FUNDS:
			if ev[UiEv.I_A] == viewer and _cooled(&"funds", 6000):
				_toast("Insufficient funds.", UiPalette.WARN)
		UiEv.UNIT_CAP_REACHED:
			if ev[UiEv.I_A] == viewer and _cooled(&"unit_cap", 6000):
				_toast("Unit cap reached.", UiPalette.WARN)
		UiEv.STRUCTURE_SOLD:
			if ev[UiEv.I_A] == viewer:
				_toast("Structure sold: +$%s" % UiBuildItem.group_digits(ev[UiEv.I_C]), UiPalette.CREDITS)


func _flush_lost() -> void:
	if _lost_pending > 0:
		_toast("%d unit%s lost" % [_lost_pending, "" if _lost_pending == 1 else "s"], UiPalette.TEXT_DIM)
	_lost_pending = 0
	_lost_flush_msec = 0


## State-driven ribbons (edge-triggered, polled at 2 Hz): low power, own superweapon ready, enemy superweapon warnings.
func _update_alert_state() -> void:
	if _notifier != null and _notifier.has_method(&"on_event"):
		return
	var rs: UiRibbonStack = _hud.ribbons()
	if _sim.power_demand() > _sim.power_supply() and not observer:
		rs.post(&"low_power", UiRibbon.Severity.WARN, "LOW POWER", "Production and research at 50%", UiGlyphs.Glyph.BOLT, -1.0, -1.0, "")
	else:
		rs.clear(&"low_power")
	var sw_ready: bool = not observer and _sim.sw_status() == UiSimPort.SwStatus.READY
	var sw_key: String = UiKeymap.instance().label(&"superweapon")
	if sw_ready and _roster.superweapon_def != null:
		rs.post(&"sw_ready", UiRibbon.Severity.OK, _roster.superweapon_def.ui_name.to_upper(), ("Superweapon ready  //  %s to target" % sw_key if sw_key != "" else "Superweapon ready  //  click its button"), UiGlyphs.Glyph.MISSILE, -1.0, -1.0, "READY")
		_sw_ready_shown = true
	elif _sw_ready_shown:
		rs.clear(&"sw_ready")
		_sw_ready_shown = false
	var n: int = _sim.strategic_warnings(_tmp)
	var seen: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var b: int = i * UiSimPort.WARN_STRIDE
		if _tmp[b + 2] != 0 or _sim.rel(_sim.viewer_pid(), _tmp[b + 1]) == UiSimPort.Rel.SELF:
			continue
		var wid: int = _tmp[b]
		seen.append(wid)
		var name: String = "SUPERWEAPON"
		if _data != null and _tmp[b + 3] >= 0 and _tmp[b + 3] < _data.superweapons.size():
			name = _data.superweapons[_tmp[b + 3]].ui_name
		var rid := StringName("sw_warning_%d" % wid)
		var left: float = maxf(float(_tmp[b + 11] - _sim.tick()) / 20.0, 0.0)
		rs.post(rid, UiRibbon.Severity.DANGER, "ENEMY SUPERWEAPON DETECTED", "%s  //  %s  //  %s" % [name, _sim.name_of(_tmp[b + 1]), _sector(_tmp[b + 4], _tmp[b + 5])], UiGlyphs.Glyph.MISSILE, left, -1.0, "", 0.0, _tmp[b + 4], _tmp[b + 5])
		if not _warn_ids.has(wid):
			_ping_at(_tmp[b + 4], _tmp[b + 5], UiMinimap.PING_KIND_SUPERWEAPON, UiPalette.DANGER)
	for old: int in _warn_ids:
		if not seen.has(old):
			rs.clear(StringName("sw_warning_%d" % old))
	_warn_ids = seen


func _update_ribbon_countdowns() -> void:
	if _warn_ids.is_empty():
		return
	var n: int = _sim.strategic_warnings(_tmp)
	for i: int in n:
		var b: int = i * UiSimPort.WARN_STRIDE
		var r: UiRibbon = _hud.ribbons().get_ribbon(StringName("sw_warning_%d" % _tmp[b]))
		if r != null:
			r.countdown_seconds = maxf(float(_tmp[b + 11] - _sim.tick()) / 20.0, 0.0)
