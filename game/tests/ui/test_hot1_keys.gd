extends RefCounted
## HOT1 key-probe regression: every action of `data/ui/keymap_defaults.json` is pressed as a real `InputEventKey` (its default
## binding, both bindings where it has two) into a live `UiScreenGame` that runs a real LOCAL match on the real ports (the real
## `NetSession`, `UiSimPortWorld`, command bus, presenter and input controller), and each press must have an OBSERVABLE effect: a command
## the net port saw, an armed mode, a camera move, a selection, a dialog, a toast. The class of gap DOC2 found (about 45 registered
## actions that nothing handled) cannot come back: a new action without a probe or an entry in `EXEMPT` fails
## `test_every_action_is_probed_or_exempt`, and a probe that causes nothing fails its own check.
##
## Pass 1 (a player match) probes every action of the GAME and GLOBAL contexts. Pass 2 (the golden replay, an observer HUD) probes the
## OBSERVER-context actions. Pass 3 (a scripted mission) probes `toggle_objectives`. `EXEMPT` lists what is deliberately not probed
## through a key event, with the reason and the test that covers it instead.

const H := preload("res://tests/ui/ui_harness.gd")
const REPLAY: String = "res://tests/fixtures/net/replays/app_ai_2p_3min.mfreplay"
const MATCH_ROSTERS: PackedStringArray = ["roster.nec.vanilla", "roster.napc.vanilla"]

## Actions without a key-event probe by design: id -> why, and where the behaviour is asserted instead.
const EXEMPT: Dictionary = {
	"cam_orbit": "mouse-only by default (middle button drag, `mouse: [3]`, no key): UiInputController orbit states are asserted in the input controller tests",
}

## Observer-context actions probed in pass 2 (they are not installed in a player match).
const OBSERVER_PASS: PackedStringArray = [
	"obs_player_1", "obs_player_2", "obs_player_3", "obs_player_4", "obs_player_5", "obs_player_6", "obs_player_7", "obs_player_8",
	"obs_all", "obs_next_player", "obs_toggle_fog", "obs_pause", "obs_speed_up", "obs_speed_down", "obs_follow", "obs_event_next",
	"obs_event_prev", "obs_seek_back", "obs_seek_fwd", "toggle_scoreboard",
]
## Probed in the mission pass (pass 3).
const MISSION_PASS: PackedStringArray = ["toggle_objectives"]
## Probed in pass 1 AND (for the observer HUD) in pass 2.
const SHARED_PASS: PackedStringArray = ["hide_ui", "cmd_ping"]


## Net port that records every command and still forwards it to the real session adapter.
class SpyNet extends UiNetPort:
	var inner: UiNetPort = null
	var sent: Array[PackedInt32Array] = []
	var chats: Array[String] = []
	var pings: Array[Vector2i] = []

	func submit(cmd: PackedInt32Array) -> bool:
		sent.append(cmd.duplicate())
		return inner.submit(cmd)

	func can_submit() -> bool:
		return inner.can_submit()

	func local_pid() -> int:
		return inner.local_pid()

	func tick() -> int:
		return inner.tick()

	func is_observer() -> bool:
		return inner.is_observer()

	func pending_count() -> int:
		return inner.pending_count()

	func request_pause(want_paused: bool) -> int:
		return inner.request_pause(want_paused)

	func surrender() -> bool:
		return inner.surrender()

	func send_chat(text: String, team_only: bool) -> void:
		chats.append(("[team] " if team_only else "") + text)

	func send_map_ping(cell_x: int, cell_y: int) -> void:
		pings.append(Vector2i(cell_x, cell_y))
		inner.send_map_ping(cell_x, cell_y)

	func has_op(op: int) -> bool:
		for c: PackedInt32Array in sent:
			if c[0] == op:
				return true
		return false

	func ids_of(op: int) -> PackedInt32Array:
		for c: PackedInt32Array in sent:
			if c[0] == op:
				return c.slice(1 + SimCmd.layout_of(op).size())
		return PackedInt32Array()


## Everything a probe needs: the match, the game screen, the spies and the entities the probes select.
class Rig extends RefCounted:
	var ctx: AppMatchContext = null
	var game: UiScreenGame = null
	var h: Variant = null
	var spy: SpyNet = null
	var rec: UiAudioPortRecorder = null
	var view: UiViewPortFixture = null
	var sim: UiSimPort = null
	var w: SimWorld = null
	var hq: int = 0
	var units_a: PackedInt32Array = PackedInt32Array()
	var units_b: PackedInt32Array = PackedInt32Array()
	var ability_units: PackedInt32Array = PackedInt32Array()
	var collector: int = 0
	var mcv: int = 0
	var transport: int = 0
	var producer: int = 0
	var def_a: int = -1
	var def_b: int = -1
	var nav: Array = []
	var powers_ready: bool = false

	func press(packed: int) -> void:
		for down: bool in [true, false]:
			var ev: InputEventKey = UiKeymap.unpack(packed)
			ev.pressed = down
			h.vp.push_input(ev)

	func select(ids: PackedInt32Array) -> void:
		game.selection.replace(ids, sim)

	func log_text() -> String:
		var out: PackedStringArray = PackedStringArray()
		var feed: UiLogFeed = game.hud.log_feed()
		for i: int in feed.line_count():
			out.append(feed.line_text(i))
		return " | ".join(out)

	func eid_xy(eid: int) -> Vector2i:
		var row: UiEntityRow = UiEntityRow.new()
		return Vector2i(row.x, row.y) if sim.read(eid, row) else Vector2i(-1, -1)

	func step_ticks(n: int) -> void:
		var t0: int = ctx.tick()
		var guard: int = 0
		while ctx.tick() < t0 + n and guard < 4000:
			ctx.frame()
			OS.delay_msec(1)
			guard += 1

	## Runs match frames until `cond` holds (at most 60): a pause request takes effect on the next turn.
	func until(cond: Callable) -> void:
		var guard: int = 0
		while not cond.call() and guard < 60:
			ctx.frame()
			OS.delay_msec(1)
			guard += 1

	func away() -> void:
		view.focus_on_sim(12 * 1024, 12 * 1024)

	func world_of(eid: int) -> Vector3:
		var p: Vector2i = eid_xy(eid)
		return view.sim_to_world(p.x, p.y)

	func focus_near(eid: int) -> bool:
		var p: Vector3 = world_of(eid)
		return Vector2(view.focus.x, view.focus.z).distance_to(Vector2(p.x, p.z)) < 2.0

	func reset() -> void:
		var scenes: Node = Engine.get_main_loop().root.get_node_or_null("AppScenes")
		if scenes != null:
			var stack: UiDialogStack = scenes.get("dialogs") as UiDialogStack
			var guard: int = 0
			while stack != null and stack.has_modal_over_input() and guard < 5:
				stack.close_top(0)
				guard += 1
		game._menu = null
		game.scuttle_dialog = null
		game.modes.disarm()
		game.modes.clear_latch()
		game.targeting.cancel()
		game.placement.cancel()
		if game.chat != null:
			game.chat.close()
		game.selection.clear()
		game.groups.clear_all()
		game.bookmarks = UiBookmarks.new()
		game._group_cursor = -1
		game.hud.set_chrome_visible(true)
		game.hud.minimap().clear_pings()
		game.hud.log_feed().clear()
		game.presenter.last_alert = Vector2i(-1, -1)
		game.controller.edge_scroll = false
		game.controller.enabled = true
		view.reset_camera_orientation()
		var hp: Vector2i = eid_xy(hq)
		view.focus_on_sim(hp.x, hp.y)
		if not spy.sent.is_empty():
			step_ticks(2)  # a new turn: the command bus allows a handful of commands per turn and drops an exact repeat
		spy.sent.clear()
		spy.chats.clear()
		spy.pings.clear()
		rec.clear()
		nav.clear()


# ---------------------------------------------------------------- the rig

func _gd() -> GameData:
	var app: Node = H.tree().root.get_node_or_null("AppState")
	var d: GameData = app.get("data") as GameData if app != null else null
	if d == null:
		d = GameData.load_default()
		if app != null:
			app.set("data", d)
	return d


func _find_roster_with_ability_unit(d: GameData) -> String:
	for r: DefRoster in d.rosters:
		if not r.id.ends_with(".vanilla") or r.id.begins_with("roster.napc"):
			continue
		for u: DefUnit in r.units:
			if u == null:
				continue
			for a: DefAbility in u.abilities:
				if a.kind in [DefEnums.AbilityKind.MODE_SWITCH, DefEnums.AbilityKind.PORTABLE_COVER, DefEnums.AbilityKind.DECOY_SPAWN,
						DefEnums.AbilityKind.SENSOR_PUCK, DefEnums.AbilityKind.SMOKE_LAUNCHER]:
					return r.id
	return ""


func _spawn(r: Rig, id: String, cx: int, cy: int) -> int:
	var idx: int = r.w.data.unit_idx(id)
	if idx < 0:
		return 0
	var e: SimEntity = r.w.spawn_unit(idx, 0, cx * 1024 + 512, cy * 1024 + 512, 0, 0, r.w.data.units[idx].cost, 0, SimEvent.SPAWN_PRODUCED)
	r.w.call("_flush_spawns")
	return e.id


func _spawn_def(r: Rig, def_idx: int, cx: int, cy: int) -> int:
	var e: SimEntity = r.w.spawn_unit(def_idx, 0, cx * 1024 + 512, cy * 1024 + 512, 0, 0, r.w.data.units[def_idx].cost, 0, SimEvent.SPAWN_PRODUCED)
	r.w.call("_flush_spawns")
	return e.id


## Unit defs of the roster by capability: [armed mobile ground without ability buttons] x2, [ability buttons], collector, MCV, transport.
func _pick_defs(r: Rig) -> Dictionary:
	var caps: UiUnitCaps = UiUnitCaps.shared_for(r.sim)
	var out: Dictionary = {"armed": [], "ability": -1, "collector": -1, "mcv": -1, "transport": -1}
	for i: int in r.ctx.roster.units.size():
		if r.ctx.roster.units[i] == null or not r.ctx.roster.units[i].id.begins_with("unit."):
			continue  # summons (drones, balloons) expire on their own
		var c: int = caps.caps_of(UiSimPort.KIND_UNIT, i)
		var ground: bool = (c & (UiUnitCaps.CAP_AIR | UiUnitCaps.CAP_NAVAL)) == 0
		var armed_mobile: bool = (c & UiUnitCaps.CAP_ARMED) != 0 and (c & UiUnitCaps.CAP_MOBILE) != 0 and ground
		if (c & UiUnitCaps.CAP_HAS_ABILITY_BUTTONS) != 0 and (c & UiUnitCaps.CAP_MOBILE) != 0 and ground and int(out["ability"]) < 0:
			out["ability"] = i
		elif armed_mobile and (c & (UiUnitCaps.CAP_SERVICE | UiUnitCaps.CAP_COLLECTOR | UiUnitCaps.CAP_MCV)) == 0 and (out["armed"] as Array).size() < 2:
			(out["armed"] as Array).append(i)
		if (c & UiUnitCaps.CAP_COLLECTOR) != 0 and int(out["collector"]) < 0:
			out["collector"] = i
		if (c & UiUnitCaps.CAP_MCV) != 0 and int(out["mcv"]) < 0:
			out["mcv"] = i
		if (c & UiUnitCaps.CAP_TRANSPORT) != 0 and ground and int(out["transport"]) < 0:
			out["transport"] = i
	return out


## A LOCAL match of the roster list, the game screen in a 1920x1080 harness, spies on net and audio, and own units around the HQ.
func _make_rig(rosters: PackedStringArray) -> Rig:
	var r: Rig = Rig.new()
	var cfg: Dictionary = AppMatch.simple_config(rosters, 6, 96)
	r.ctx = AppMatch.start_local(cfg, {"with_view": false, "bind": false, "unpaced": true})
	var guard: int = 0
	while r.ctx.session.phase == NetSession.Phase.LOADING and guard < 4000:
		r.ctx.session.poll()
		OS.delay_msec(2)
		guard += 1
	r.ctx.session.opts.max_ticks_per_poll = 1  # one tick per ctx.frame(): `step_ticks` is exact, the match does not run away
	r.w = r.ctx.world()
	r.sim = r.ctx.sim
	r.spy = SpyNet.new()
	r.spy.inner = r.ctx.net
	r.ctx.net = r.spy
	r.rec = UiAudioPortRecorder.new()
	r.ctx.audio = r.rec
	r.view = r.ctx.view as UiViewPortFixture
	return r


func _enter(r: Rig) -> void:
	r.h = await H.make()
	r.game = UiScreenGame.new()
	r.h.root.add_child(r.game)
	UiLayerRoot.fill(r.game)
	r.game.enter({"ctx": r.ctx})
	r.game.navigate.connect(func(target: StringName, p: Dictionary) -> void: r.nav.append([target, p]))
	r.view.attach(r.h.vp)
	await H.frames(3)


func _populate(r: Rig, full: bool = true) -> void:
	var hq_e: SimEntity = r.w.structures_of(0)[0]
	r.hq = hq_e.id
	if not full:
		return
	var hx: int = hq_e.x >> 10
	var hy: int = hq_e.y >> 10
	var defs: Dictionary = _pick_defs(r)
	var armed: Array = defs["armed"] as Array
	r.def_a = int(armed[0])
	r.def_b = int(armed[1]) if armed.size() > 1 else int(armed[0])
	for i: int in 3:
		r.units_a.append(_spawn_def(r, r.def_a, hx + 6 + i, hy + 5))
	r.units_b.append(_spawn_def(r, r.def_b, hx + 6, hy + 7))
	if int(defs["ability"]) >= 0:
		for i2: int in 2:
			r.ability_units.append(_spawn_def(r, int(defs["ability"]), hx + 6 + i2, hy + 9))
	if int(defs["collector"]) >= 0:
		r.collector = _spawn_def(r, int(defs["collector"]), hx + 9, hy + 5)
	if int(defs["mcv"]) >= 0:
		r.mcv = _spawn_def(r, int(defs["mcv"]), hx + 9, hy + 7)
	if int(defs["transport"]) >= 0:
		r.transport = _spawn_def(r, int(defs["transport"]), hx + 9, hy + 9)
	var bi: int = r.w.data.structure_idx("structure.shared.barracks")
	var b: SimEntity = r.w.spawn_structure(bi, 0, (hx - 7) * 1024 + 512, (hy + 3) * 1024 + 512, 0, 0, r.w.data.structures[bi].cost)
	r.w.call("_flush_spawns")
	r.producer = b.id
	r.step_ticks(3)
	r.view.refresh()


func _leave(r: Rig) -> void:
	r.game.exit()
	r.ctx.dispose()
	AppState.match_ctx = null
	r.game.queue_free()
	H.done(r.h)
	await H.frames(2)


# ---------------------------------------------------------------- the probe table

## id -> Callable(rig, t, id, packed) for pass 1; indexed families are generated.
func _player_probes() -> Dictionary:
	var p: Dictionary = {}
	p["cam_tilt_up"] = _p_tilt
	p["cam_tilt_down"] = _p_tilt
	p["cam_zoom_in"] = _p_zoom
	p["cam_zoom_out"] = _p_zoom
	p["cam_center_base"] = _p_center_base
	p["cam_center_selection"] = _p_center_selection
	p["cam_jump_alert"] = _p_jump_alert
	p["cam_reset"] = _p_cam_reset
	p["toggle_edge_scroll"] = _p_edge_scroll
	for id: String in ["cam_pan_left", "cam_pan_right", "cam_pan_up", "cam_pan_down", "cam_rotate_left", "cam_rotate_right"]:
		p[id] = _p_polled_camera
	for k: int in range(1, 5):
		p["cam_bookmark_%d" % k] = _p_bookmark_recall
		p["cam_bookmark_set_%d" % k] = _p_bookmark_set
	for n: int in 10:
		p["group_select_%d" % n] = _p_group_select
		p["group_assign_%d" % n] = _p_group_assign
		p["group_add_%d" % n] = _p_group_add
		p["group_append_%d" % n] = _p_group_append
	p["sel_all_military"] = _p_sel_all_military
	p["sel_all_military_screen"] = _p_sel_all_military
	p["sel_same_screen"] = _p_sel_same
	p["sel_same_map"] = _p_sel_same
	p["sel_idle_next"] = _p_sel_idle
	p["sel_idle_prev"] = _p_sel_idle
	p["sel_collector_next"] = _p_sel_collector
	p["sel_producer_next"] = _p_sel_producer
	p["sel_hq"] = _p_sel_hq
	p["sel_subgroup_next"] = _p_sel_subgroup
	p["sel_group_next"] = _p_sel_group_next
	for id2: String in ["cmd_attack_move", "cmd_move", "cmd_guard", "cmd_patrol", "cmd_follow", "cmd_force_fire_mode"]:
		p[id2] = _p_arm_mode
	for id3: String in ["cmd_stop", "cmd_scatter", "cmd_hold", "cmd_stance_cycle", "cmd_return", "cmd_deploy", "cmd_unload"]:
		p[id3] = _p_order_command
	for k2: int in range(1, 5):
		p["cmd_ability_%d" % k2] = _p_ability
	p["cmd_scuttle"] = _p_scuttle
	p["cmd_ping"] = _p_ping
	p["tool_repair"] = _p_tool_mode
	p["tool_sell"] = _p_tool_mode
	p["tool_rally"] = _p_tool_mode
	p["tool_waypoint"] = _p_waypoint
	p["place_rotate"] = _p_place_rotate
	p["tab_next"] = _p_tab
	p["tab_prev"] = _p_tab
	for k3: int in range(1, 13):
		p["card_%d" % k3] = _p_card
		p["card_5x_%d" % k3] = _p_card
	for k4: int in range(1, 4):
		p["power_%d" % k4] = _p_power
	p["superweapon"] = _p_superweapon
	p["toggle_menu"] = _p_menu
	p["pause_game"] = _p_pause
	p["chat_all"] = _p_chat
	p["chat_team"] = _p_chat
	p["open_field_manual"] = _p_field_manual
	p["toggle_net_overlay"] = _p_net_overlay
	p["hide_ui"] = _p_hide_ui
	p["screenshot"] = _p_screenshot
	p["toggle_fullscreen"] = _p_fullscreen
	return p


func test_every_action_is_probed_or_exempt(t: TestCtx) -> void:
	var km: UiKeymap = UiKeymap.instance()
	var probes: Dictionary = _player_probes()
	var seen: Dictionary = {}
	for id: StringName in km.action_ids():
		var s: String = String(id)
		var d: UiActions.Def = km.def_of(id)
		var where: int = 0
		where += 1 if probes.has(s) else 0
		where += 1 if OBSERVER_PASS.has(s) else 0
		where += 1 if MISSION_PASS.has(s) else 0
		where += 1 if EXEMPT.has(s) else 0
		t.check(where >= 1, "action '%s' has no key probe and is not in EXEMPT: add a probe (or a reasoned exemption) in test_hot1_keys.gd" % s)
		seen[s] = true
		var ctxs: int = d.contexts
		if probes.has(s):
			t.check((ctxs & (UiActions.CTX_GAME | UiActions.CTX_GLOBAL)) != 0, "'%s' is probed in a player match but its context is not GAME or GLOBAL" % s)
		if OBSERVER_PASS.has(s):
			t.check((ctxs & (UiActions.CTX_OBSERVER | UiActions.CTX_GLOBAL)) != 0, "'%s' is probed in the observer pass but its context has no OBSERVER" % s)
		if not EXEMPT.has(s) and not OBSERVER_PASS.has(s) and not MISSION_PASS.has(s):
			t.check(not km.bindings(id).is_empty() or EXEMPT.has(s), "'%s' has no default key: bind it or exempt it" % s)
	for e: Variant in EXEMPT:
		t.check(seen.has(str(e)), "EXEMPT lists '%s', which is not in the keymap any more" % str(e))
	for s2: String in probes:
		t.check(seen.has(s2), "a probe exists for '%s', which is not in the keymap any more" % s2)
	for s3: String in OBSERVER_PASS:
		t.check(seen.has(s3), "the observer pass probes '%s', which is not in the keymap any more" % s3)


## Pass 1: every action of the GAME / GLOBAL contexts through a key event in a live player match.
func test_player_match_every_key_has_an_effect(t: TestCtx) -> void:
	t.set_timeout(600.0)
	var d: GameData = _gd()
	var roster: String = _find_roster_with_ability_unit(d)
	if not t.check(roster != "", "a vanilla roster has a unit with an ability button (HOT1 ability probe)"):
		return
	var r: Rig = _make_rig(PackedStringArray([roster, "roster.napc.vanilla"]))
	await _enter(r)
	_populate(r)
	r.game.controller.edge_scroll = false
	var probes: Dictionary = _player_probes()
	var km: UiKeymap = UiKeymap.instance()
	var ids: Array = probes.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = 1 if (a.begins_with("power_") or a == "superweapon") else 0  # the tech-up changes the world: powers go last
		var pb: int = 1 if (b.begins_with("power_") or b == "superweapon") else 0
		return pa < pb or (pa == pb and a < b))
	var pressed: int = 0
	var expected: int = 0
	for id0: String in ids:
		expected += km.bindings(StringName(id0)).size()
	for id: String in ids:
		var packs: PackedInt32Array = km.bindings(StringName(id))
		if not t.check(not packs.is_empty(), "'%s' has a default key" % id):
			continue
		for packed: int in packs:
			r.reset()
			await H.frames(1)
			var c: Callable = probes[id] as Callable
			await c.call(r, t, id, packed)
			pressed += 1
	t.eq(pressed, expected, "every default binding of every probed action was pressed")
	t.ge(pressed, 130, "the keymap has well over 130 player-match bindings")
	await _leave(r)


# ---------------------------------------------------------------- probes: camera

func _p_tilt(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var before: float = r.view.pitch_deg
	r.press(packed)
	await H.frames(1)
	if id == "cam_tilt_up":
		t.gt(r.view.pitch_deg, before, "%s tilts the camera up" % id)
	else:
		t.lt(r.view.pitch_deg, before, "%s tilts the camera down" % id)


func _p_zoom(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var before: float = r.view.distance
	r.press(packed)
	await H.frames(1)
	if id == "cam_zoom_in":
		t.lt(r.view.distance, before, "%s moves the camera closer" % id)
	else:
		t.gt(r.view.distance, before, "%s moves the camera away" % id)


func _p_center_base(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.away()
	t.check(not r.focus_near(r.hq), "(setup) the camera starts away from the base")
	r.press(packed)
	await H.frames(1)
	t.check(r.focus_near(r.hq), "%s centres the camera on the headquarters" % id)


func _p_center_selection(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.select(PackedInt32Array([r.units_a[1]]))
	r.away()
	r.press(packed)
	await H.frames(1)
	t.check(r.focus_near(r.units_a[1]), "%s centres the camera on the selection" % id)


func _p_jump_alert(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.check(r.log_text().contains("No alert"), "%s with no alert says so (%s)" % [id, r.log_text()])
	var tick: int = r.ctx.tick()
	var ax: int = 40 * 1024 + 512
	var ay: int = 30 * 1024 + 512
	r.game.presenter.on_events(PackedInt32Array([UiEv.ATTACK_ALERT, tick, ax, ay, 0, r.hq, 0, 1, 0, 0]))
	t.eq(r.game.presenter.last_alert, Vector2i(ax, ay), "(setup) a base-attack event records the alert position")
	r.away()
	r.press(packed)
	await H.frames(1)
	var w: Vector3 = r.view.sim_to_world(ax, ay)
	t.check(Vector2(r.view.focus.x, r.view.focus.z).distance_to(Vector2(w.x, w.z)) < 2.0, "%s jumps the camera to the last alert" % id)


func _p_cam_reset(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.view.tilt(10.0)
	r.view.rotate_yaw(40.0)
	t.ne(r.view.pitch_deg, UiViewPortFixture.DEFAULT_PITCH, "(setup) tilted")
	r.press(packed)
	await H.frames(1)
	t.near(r.view.pitch_deg, UiViewPortFixture.DEFAULT_PITCH, 0.01, "%s restores the pitch" % id)
	t.near(r.view.yaw_deg, 30.0, 0.01, "%s restores the yaw" % id)


func _p_edge_scroll(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.game.controller.edge_scroll = true
	r.press(packed)
	await H.frames(1)
	t.check(not r.game.controller.edge_scroll, "%s switches edge scrolling off" % id)
	r.press(packed)
	await H.frames(1)
	t.check(r.game.controller.edge_scroll, "%s switches it on again" % id)
	r.game.controller.edge_scroll = false


## Pan / rotate keys are polled each frame (`Input.is_action_pressed`): a parsed key event updates the action state like the OS does.
func _p_polled_camera(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var yaw0: float = r.view.yaw_deg
	var f0: Vector3 = r.view.focus
	r.game.controller.assume_focused = true
	var down: InputEventKey = UiKeymap.unpack(packed)
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	r.game.controller.tick(0.1)
	var up: InputEventKey = UiKeymap.unpack(packed)
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await H.frames(1)
	if id.begins_with("cam_rotate"):
		t.ne(r.view.yaw_deg, yaw0, "%s rotates the camera" % id)
		t.check((r.view.yaw_deg > yaw0) == (id == "cam_rotate_right") or absf(r.view.yaw_deg - yaw0) > 180.0, "%s rotates the right way" % id)
	else:
		t.check(r.view.focus.distance_to(f0) > 0.01, "%s pans the camera" % id)


func _p_bookmark_set(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var slot: int = int(id.get_slice("_", 3)) - 1
	r.view.focus_on_sim(20 * 1024, 15 * 1024)
	var want: Dictionary = r.view.camera_state()
	r.press(packed)
	await H.frames(1)
	var got: Dictionary = r.game.bookmarks.get_slot(slot)
	t.check(not got.is_empty(), "%s stores the camera in the slot" % id)
	t.near(float(got.get("focus_x", -1.0)), float(want["focus_x"]), 0.01, "%s stores the focus" % id)


func _p_bookmark_recall(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var slot: int = int(id.get_slice("_", 2)) - 1
	r.view.focus_on_sim(20 * 1024, 15 * 1024)
	var stored: Dictionary = r.view.camera_state()
	r.game.bookmarks.set_slot(slot, stored)
	r.away()
	r.press(packed)
	await H.frames(1)
	t.near(r.view.focus.x, float(stored["focus_x"]), 0.01, "%s returns to the stored camera" % id)


# ---------------------------------------------------------------- probes: selection

func _digit(id: String) -> int:
	return int(id.get_slice("_", 2))


func _p_group_assign(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var n: int = _digit(id)
	r.select(r.units_a)
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.groups.members(n), r.game.selection.sorted_ids(), "%s stores the selection in group %d" % [id, n])


func _p_group_select(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var n: int = _digit(id)
	r.game.groups.assign(n, r.units_a)
	r.game.selection.clear()
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.selection.sorted_ids(), r.units_a, "%s recalls group %d" % [id, n])


func _p_group_add(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var n: int = _digit(id)
	r.game.groups.assign(n, PackedInt32Array([r.units_a[0]]))
	r.select(PackedInt32Array([r.units_a[1], r.units_a[2]]))
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.groups.members(n).size(), 3, "%s adds the selection to group %d" % [id, n])


func _p_group_append(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var n: int = _digit(id)
	r.game.groups.assign(n, PackedInt32Array([r.units_a[0]]))
	r.select(PackedInt32Array([r.units_a[1]]))
	r.press(packed)
	await H.frames(1)
	t.check(r.game.selection.has(r.units_a[0]) and r.game.selection.has(r.units_a[1]), "%s adds group %d to the selection" % [id, n])


func _p_sel_all_military(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	var sel: PackedInt32Array = r.game.selection.sorted_ids()
	t.ge(sel.size(), 1, "%s selects combat units" % id)
	if id == "sel_all_military":
		for u: int in r.units_a:
			t.check(r.game.selection.has(u), "%s includes unit %d" % [id, u])


func _p_sel_same(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.select(PackedInt32Array([r.units_a[0]]))
	if id == "sel_same_map":
		r.away()  # the others are off the screen: only the map-wide variant finds them
	r.press(packed)
	await H.frames(1)
	var n: int = 0
	for u: int in r.units_a:
		n += 1 if r.game.selection.has(u) else 0
	t.eq(n, 3, "%s selects every unit of the type" % id)


func _p_sel_idle(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.selection.size(), 1, "%s selects one idle unit" % id)
	t.check(r.game.selection.mode == UiSelection.Mode.UNITS, "%s selects a unit" % id)


func _p_sel_collector(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	if not t.ne(r.collector, 0, "(setup) the roster has a collector"):
		return
	r.press(packed)
	await H.frames(1)
	t.check(r.game.selection.has(r.collector), "%s selects the collector" % id)


func _p_sel_producer(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.selection.mode, UiSelection.Mode.STRUCTURES, "%s selects a structure" % id)
	t.check(r.game.selection.has(r.producer) or r.game.selection.has(r.hq), "%s selects a production structure" % id)


func _p_sel_hq(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.selection.sorted_ids(), PackedInt32Array([r.hq]), "%s selects the headquarters" % id)


func _p_sel_subgroup(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var mixed: PackedInt32Array = r.units_a.duplicate()
	mixed.append_array(r.units_b)
	if r.def_a == r.def_b:
		mixed.append(r.collector)
	r.select(mixed)
	var before: int = r.game.selection.active_def
	r.press(packed)
	await H.frames(1)
	t.ne(r.game.selection.active_def, before, "%s moves to the next subgroup of a mixed selection" % id)


func _p_sel_group_next(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.game.groups.assign(1, PackedInt32Array([r.units_a[0]]))
	r.game.groups.assign(2, r.units_b)
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.selection.sorted_ids(), PackedInt32Array([r.units_a[0]]), "%s selects the first assigned group" % id)
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.selection.sorted_ids(), r.units_b, "%s then the next one" % id)


# ---------------------------------------------------------------- probes: orders

const _MODE_OF: Dictionary = {
	"cmd_attack_move": UiModes.Armed.ATTACK_MOVE, "cmd_move": UiModes.Armed.MOVE, "cmd_guard": UiModes.Armed.GUARD,
	"cmd_patrol": UiModes.Armed.PATROL, "cmd_follow": UiModes.Armed.FOLLOW, "cmd_force_fire_mode": UiModes.Armed.FORCE_FIRE,
}


const _CLICK_OP: Dictionary = {
	"cmd_attack_move": SimCmd.ATTACK_MOVE, "cmd_move": SimCmd.MOVE, "cmd_guard": SimCmd.GUARD, "cmd_patrol": SimCmd.PATROL,
	"cmd_force_fire_mode": SimCmd.FORCE_FIRE,
}


func _p_arm_mode(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.select(r.units_a)
	var want: int = int(_MODE_OF[id])
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.modes.armed, want, "%s arms its click mode" % id)
	t.eq(r.game.controller.armed, want, "%s tells the input controller" % id)
	if _CLICK_OP.has(id):  # the armed click turns into the order the key names
		r.game._on_armed_click(Vector2(700.0, 500.0), 0)
		t.check(r.spy.has_op(int(_CLICK_OP[id])), "%s then a click on the ground sends %s (sent %d commands)" % [id, SimCmd.name_of(int(_CLICK_OP[id])), r.spy.sent.size()])
		t.eq(r.game.modes.armed, UiModes.Armed.NONE, "and the mode ends after the order")
		return
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.modes.armed, UiModes.Armed.NONE, "%s a second press disarms" % id)


const _OP_OF: Dictionary = {
	"cmd_stop": SimCmd.STOP, "cmd_scatter": SimCmd.SCATTER, "cmd_hold": SimCmd.HOLD, "cmd_stance_cycle": SimCmd.SET_STANCE,
	"cmd_return": SimCmd.RETURN_CARGO, "cmd_deploy": SimCmd.DEPLOY, "cmd_unload": SimCmd.UNLOAD,
}


func _p_order_command(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	match id:
		"cmd_return":
			r.select(PackedInt32Array([r.collector]))
		"cmd_deploy":
			r.select(PackedInt32Array([r.mcv]))
		"cmd_unload":
			r.select(PackedInt32Array([r.transport]))
		_:
			r.select(r.units_a)
	r.press(packed)
	await H.frames(1)
	var op: int = int(_OP_OF[id])
	t.check(r.spy.has_op(op), "%s sends %s (sent: %s)" % [id, SimCmd.name_of(op), str(r.spy.sent.size())])


func _p_ability(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	if not t.ne(r.ability_units.size(), 0, "(setup) the roster has a unit with an ability button"):
		return
	r.select(r.ability_units)
	var k: int = int(id.get_slice("_", 2))
	r.press(packed)
	await H.frames(1)
	if k == 1:
		t.check(r.spy.has_op(SimCmd.SET_MODE) or r.spy.has_op(SimCmd.USE_ABILITY), "%s uses the first ability button" % id)
	else:
		# no shipped unit has more than one ability-bar ability (checked in test_no_unit_has_two_bar_abilities): the key finds no button
		t.eq(r.spy.sent.size(), 0, "%s: the selected unit has no ability button %d, so the key sends nothing" % [id, k])


func _p_scuttle(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var hp: Vector2i = r.eid_xy(r.hq)
	var victims: PackedInt32Array = PackedInt32Array([_spawn_def(r, r.def_a, (hp.x >> 10) + 12, (hp.y >> 10) + 2), _spawn_def(r, r.def_a, (hp.x >> 10) + 13, (hp.y >> 10) + 2)])
	r.step_ticks(1)
	r.select(victims)
	r.press(packed)
	await H.frames(1)
	if not t.not_null(r.game.scuttle_dialog, "%s asks for a confirmation" % id):
		return
	t.eq(r.spy.sent.size(), 0, "nothing is sent before the answer")
	var scenes: Node = H.tree().root.get_node("AppScenes")
	(scenes.get("dialogs") as UiDialogStack).close_top(0)
	await H.frames(1)
	t.check(not r.spy.has_op(SimCmd.SCUTTLE), "Cancel scuttles nothing")
	r.press(packed)
	await H.frames(1)
	(scenes.get("dialogs") as UiDialogStack).close_top(1)
	await H.frames(1)
	t.eq(r.spy.ids_of(SimCmd.SCUTTLE), victims, "Scuttle sends SCUTTLE for the selected units")
	r.step_ticks(6)
	var row: UiEntityRow = UiEntityRow.new()
	t.check(not r.sim.read(victims[0], row) and not r.sim.read(victims[1], row), "and the units are gone from the match")


func _p_ping(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.modes.armed, UiModes.Armed.PING, "%s arms the ping" % id)
	t.check(r.game.hud.minimap().ping_armed, "and the minimap takes the next click as a ping")
	r.game._on_armed_click(Vector2(700.0, 500.0), 0)
	t.check(r.game.last_ping.x >= 0, "a click on the world places the ping")
	t.eq(r.game.hud.minimap().ping_count(), 1, "with a marker on the minimap")
	t.eq(r.spy.pings.size(), 1, "and relays it through the net port (MAP_PING to the team)")
	t.eq(r.game.modes.armed, UiModes.Armed.NONE, "the ping mode ends after one ping")


func _p_tool_mode(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var want: int = {"tool_repair": UiModes.Armed.REPAIR, "tool_sell": UiModes.Armed.SELL, "tool_rally": UiModes.Armed.RALLY}[id]
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.modes.armed, want, "%s arms its tool" % id)


func _p_waypoint(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.check(r.game.modes.waypoint_latch, "%s latches the waypoint (queue) mode" % id)


func _p_place_rotate(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var def: int = -1
	for i: int in r.ctx.roster.structures.size():
		if r.ctx.roster.structures[i] != null and r.sim.footprint_rotatable(i):
			def = i
			break
	if not t.ne(def, -1, "(setup) a rotatable structure exists"):
		return
	r.game.placement.begin(def)
	var before: int = r.game.placement.orient
	r.press(packed)
	await H.frames(1)
	t.ne(r.game.placement.orient, before, "%s rotates the structure being placed" % id)


# ---------------------------------------------------------------- probes: sidebar

func _p_tab(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var before: int = r.game.presenter.active_tab()
	r.press(packed)
	await H.frames(1)
	t.ne(r.game.presenter.active_tab(), before, "%s switches the sidebar tab" % id)
	r.press(packed)
	await H.frames(1)
	t.check(r.game.hud.sidebar().active_tab() == r.game.presenter.active_tab(), "the sidebar and the presenter agree on the tab")


## The tab with enough cards for slot `n`; -1 when no tab has one.
func _tab_with_slot(r: Rig, n: int) -> int:
	for tab: int in UiBuildModel.TAB_COUNT:
		if r.game.presenter.model().items(tab).size() >= n:
			return tab
	return -1


func _p_card(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var five: bool = id.begins_with("card_5x_")
	var n: int = int(id.get_slice("_", 2 if five else 1))
	var tab: int = _tab_with_slot(r, n)
	var got: Array = []
	var hud: UiHud = r.game.hud
	var on_build: Callable = func(it: UiBuildItem, count: int) -> void: got.append(["build", it, count])
	var on_place: Callable = func(it: UiBuildItem) -> void: got.append(["place", it, 1])
	var on_power: Callable = func(idx: int) -> void: got.append(["power", null, idx])
	hud.build_requested.connect(on_build)
	hud.place_requested.connect(on_place)
	hud.power_pressed.connect(on_power)
	if tab >= 0:
		hud.sidebar().select_tab(tab, true)
		await H.frames(1)
		var item: UiBuildItem = r.game.presenter.model().items(tab)[n - 1]
		r.press(packed)
		await H.frames(1)
		t.eq(got.size(), 1, "%s presses the card in slot %d of the %s tab" % [id, n, UiBuildModel.TAB_TITLES[tab]])
		if got.size() == 1 and got[0][0] == "build":
			t.eq(got[0][2], 5 if five else 1, "%s asks for %d" % [id, 5 if five else 1])
			t.check(got[0][1] == item, "%s presses the right card" % id)
	else:
		# no tab of this roster has a card in this slot: the key must do nothing (and not fail)
		r.press(packed)
		await H.frames(1)
		t.eq(got.size(), 0, "%s: no tab has a card %d, so the key does nothing" % [id, n])
	hud.build_requested.disconnect(on_build)
	hud.place_requested.disconnect(on_place)
	hud.power_pressed.disconnect(on_power)
	hud.sidebar().select_tab(UiBuildModel.Tab.STRUCTURES, true)


# ---------------------------------------------------------------- probes: powers

func _p_power(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	_ensure_powers_ready(r)
	await _power_probe(r, t, id, packed, int(id.get_slice("_", 1)) - 1)


func _p_superweapon(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	_ensure_powers_ready(r)
	await _power_probe(r, t, id, packed, -2)


## The showcase scenario's instant tech base (generators, Radar, Laboratory, the superweapon launcher), 60000 credits and a charged
## superweapon: the supports are READY without playing 10 minutes. Applied once, to the live match.
func _ensure_powers_ready(r: Rig) -> void:
	if r.powers_ready:
		return
	r.powers_ready = true
	var scn: AppScenario = AppScenario.from_args(AppLaunchArgs.parse(PackedStringArray(["--scenario=showcase", "--sw-at=0"])))
	r.step_ticks(3)
	scn.step(r.w)
	r.step_ticks(2)
	scn.step(r.w)
	r.step_ticks(4)


## `slot` 0..2 = F5..F7, -2 = the superweapon. A READY power starts its targeting (or casts at once when it needs no target); a power that
## is not ready is denied with a message and the error cue.
func _power_probe(r: Rig, t: TestCtx, id: String, packed: int, slot: int) -> void:
	var idx: int = -1
	if slot == -2:
		idx = r.ctx.roster.superweapon
	else:
		for it: UiBuildItem in r.game.presenter.model().items(UiBuildModel.Tab.POWERS):
			if it.kind == UiBuildItem.Kind.POWER and r.sim.power_slot(it.def_idx) == slot:
				idx = it.def_idx
	if not t.ne(idx, -1, "(setup) %s has a power in its slot" % id):
		return
	var ready: bool = (r.sim.sw_status() == UiSimPort.SwStatus.READY) if slot == -2 else (r.sim.power_status(idx) == UiSimPort.PowerStatus.READY)
	t.check(ready, "(setup) %s: the power is ready after the tech-up (status %d)" % [id, r.sim.sw_status() if slot == -2 else r.sim.power_status(idx)])
	r.press(packed)
	var tg: UiTargeting = r.game.targeting
	if slot == -2:
		t.check(tg.active and tg.kind == UiTargeting.Kind.SUPERWEAPON, "%s starts the superweapon targeting" % id)
		t.check(r.game.hover_cursor(Vector2(500.0, 500.0)) == UiCursors.State.SUPERWEAPON, "with the superweapon cursor")
	else:
		var immediate: bool = r.w.data.powers[idx].target_mode == DefEnums.TargetMode.NONE
		if immediate:
			t.check(r.spy.has_op(SimCmd.USE_POWER), "%s casts the target-less power at once" % id)
			r.step_ticks(3)
			t.eq(r.sim.power_status(idx), UiSimPort.PowerStatus.COOLDOWN, "and the power recharges (the sim executed it)")
		else:
			t.check(tg.active and tg.kind == UiTargeting.Kind.POWER and tg.power_idx == idx, "%s starts the targeting of its power" % id)
	await H.frames(1)


# ---------------------------------------------------------------- probes: interface

func _p_menu(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(2)
	t.not_null(r.game._menu, "%s opens the game menu" % id)
	r.until(func() -> bool: return r.ctx.session.is_paused())
	t.check(r.ctx.session.is_paused(), "a local match pauses behind the menu")
	var scenes: Node = H.tree().root.get_node("AppScenes")
	(scenes.get("dialogs") as UiDialogStack).close_top(0)
	await H.frames(1)
	r.until(func() -> bool: return not r.ctx.session.is_paused())
	t.check(not r.ctx.session.is_paused(), "closing the menu resumes the match")


func _p_pause(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	t.check(not r.ctx.session.is_paused(), "(setup) running")
	r.press(packed)
	r.until(func() -> bool: return r.ctx.session.is_paused())
	t.check(r.ctx.session.is_paused(), "%s pauses the match" % id)
	r.press(packed)
	r.until(func() -> bool: return not r.ctx.session.is_paused())
	t.check(not r.ctx.session.is_paused(), "%s resumes it" % id)
	await H.frames(1)


func _p_chat(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var team: bool = id == "chat_team"
	# a single-player match has nobody to talk to: the key says so and opens nothing
	r.press(packed)
	await H.frames(1)
	t.check(r.log_text().contains("LAN"), "%s in a single-player match says chat needs a LAN match (%s)" % [id, r.log_text()])
	t.check(not r.game.chat.is_open(), "and opens no input")
	# in a LAN match (any role but LOCAL) the key opens the chat input; typing then never reaches the keymap
	var role0: int = r.ctx.session.role
	r.ctx.session.role = NetSession.Role.HOST
	r.press(packed)  # (synchronous; the role is put back before any frame runs the host timers of a session that has no host side)
	r.ctx.session.role = role0
	await H.frames(1)
	t.check(r.game.chat.is_open(), "%s opens the chat input in a LAN match" % id)
	t.check(not r.game.controller.keys_ok(), "while typing the hotkeys are off (S does not stop units)")
	r.game.chat.set_input_text("  attack at dawn ")
	r.game.chat.submit_current(team)
	await H.frames(1)
	t.eq(r.spy.chats, [("[team] " if team else "") + "attack at dawn"], "%s sends the text through the net port" % id)
	t.check(not r.game.chat.is_open(), "the input closes after sending")
	t.check(r.game.controller.keys_ok(), "and the hotkeys work again")


func _p_field_manual(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.eq(r.nav.size(), 1, "%s navigates" % id)
	if r.nav.size() == 1:
		t.eq(r.nav[0][0], &"field_manual", "%s opens the Field Manual" % id)


func _p_net_overlay(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var before: bool = r.game.overlays.net_overlay.visible
	r.press(packed)
	await H.frames(1)
	t.ne(r.game.overlays.net_overlay.visible, before, "%s toggles the network overlay" % id)
	r.press(packed)
	await H.frames(1)
	t.eq(r.game.overlays.net_overlay.visible, before, "and back")


func _p_hide_ui(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	r.press(packed)
	await H.frames(1)
	t.check(not r.game.hud.chrome_visible() and not r.game.hud.sidebar().visible, "%s hides the panels" % id)
	r.press(packed)
	await H.frames(1)
	t.check(r.game.hud.chrome_visible() and r.game.hud.sidebar().visible, "and shows them again")


func _p_screenshot(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var img: Image = Image.create(48, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.5, 0.8))
	r.game.screenshot_source = func() -> Image: return img
	r.game.last_screenshot = ""
	r.press(packed)
	await H.frames(1)
	var path: String = r.game.last_screenshot
	if t.check(path != "" and FileAccess.file_exists(path), "%s writes a PNG under user://screenshots/ (%s)" % [id, path]):
		t.check(path.begins_with(UiScreenGame.SCREENSHOT_DIR), "in the screenshots folder")
		var back: Image = Image.load_from_file(path)
		t.check(back != null and back.get_size() == Vector2i(48, 32), "the file holds the frame")
		DirAccess.remove_absolute(path)
	t.check(r.log_text().contains("Screenshot saved"), "and a message says where")
	r.game.screenshot_source = Callable()


func _p_fullscreen(r: Rig, t: TestCtx, id: String, packed: int) -> void:
	var st: Node = H.tree().root.get_node("AppSettings")
	st.call("configure", "user://hot1_keys_settings.cfg", true)  # in memory: the real settings file is never touched
	t.eq(int(st.call("get_int", &"video/window_mode")), 0, "(setup) windowed")
	r.press(packed)
	await H.frames(1)
	t.eq(int(st.call("get_int", &"video/window_mode")), 1, "%s switches to fullscreen" % id)
	r.press(packed)
	await H.frames(1)
	t.eq(int(st.call("get_int", &"video/window_mode")), 0, "and back to a window")
	st.call("configure")


# ---------------------------------------------------------------- more behaviour around the keys

func test_powers_that_are_not_ready_are_denied_with_a_reason(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Rig = _make_rig(MATCH_ROSTERS)
	await _enter(r)
	_populate(r, false)
	var km: UiKeymap = UiKeymap.instance()
	for id: String in ["power_1", "power_2", "power_3", "superweapon"]:
		r.reset()
		r.press(km.bindings(StringName(id))[0])
		await H.frames(1)
		t.check(not r.game.targeting.active, "%s: a power that is not ready starts no targeting" % id)
		t.check(not r.spy.has_op(SimCmd.USE_POWER) and not r.spy.has_op(SimCmd.LAUNCH_SUPERWEAPON), "%s sends nothing" % id)
		t.check(r.rec.count_of(&"ui") >= 1 and r.log_text() != "", "%s says why (%s)" % [id, r.log_text()])
	await _leave(r)


func test_a_ready_support_power_is_cast_after_f5_and_a_click(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Rig = _make_rig(MATCH_ROSTERS)
	await _enter(r)
	_populate(r, false)
	_ensure_powers_ready(r)
	var km: UiKeymap = UiKeymap.instance()
	var cast: int = 0
	for slot: int in 3:
		var idx: int = -1
		for it: UiBuildItem in r.game.presenter.model().items(UiBuildModel.Tab.POWERS):
			if it.kind == UiBuildItem.Kind.POWER and r.sim.power_slot(it.def_idx) == slot:
				idx = it.def_idx
		if idx < 0 or r.w.data.powers[idx].target_mode != DefEnums.TargetMode.POINT:
			continue
		r.reset()
		r.press(km.bindings(StringName("power_%d" % (slot + 1)))[0])
		await H.frames(1)
		if not t.check(r.game.targeting.active, "F%d starts targeting" % (5 + slot)):
			continue
		var hq: Vector2i = r.eid_xy(r.hq)
		t.check(r.game.targeting.press(hq.x + 4096, hq.y, 0), "a click near the base commits the power")
		t.check(r.spy.has_op(SimCmd.USE_POWER), "the cast is a USE_POWER command")
		t.check(not r.game.targeting.active, "targeting ends after the cast")
		cast += 1
		break
	t.ge(cast, 1, "at least one support power of the roster was cast through its key")
	r.reset()
	r.press(km.bindings(&"superweapon")[0])
	await H.frames(1)
	t.check(r.game.targeting.active and r.game.targeting.kind == UiTargeting.Kind.SUPERWEAPON, "F8 starts the superweapon targeting")
	var hq2: Vector2i = r.eid_xy(r.hq)
	t.check(r.game.targeting.press(hq2.x + 6144, hq2.y, 0) or r.game.targeting.is_pressing(), "and a click on a visible cell commits (or starts the angle of a line weapon)")
	await _leave(r)


func test_chat_lines_and_map_pings_of_the_session_are_shown(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Rig = _make_rig(MATCH_ROSTERS)
	await _enter(r)
	_populate(r, false)
	var s: NetSession = r.ctx.session
	s.chat_received.emit(0, 1, "Mara", "hello all")
	s.chat_received.emit(1, 1, "Mara", "psst")
	s.chat_received.emit(0, 255, "", "Player left")
	t.eq(r.game.chat.line_count(), 3, "three chat lines")
	t.eq(r.game.chat.line_text(0), "Mara: hello all", "everybody")
	t.eq(r.game.chat.line_text(1), "Mara (team): psst", "team")
	t.eq(r.game.chat.line_text(2), "[SYSTEM] Player left", "system")
	t.eq(r.game.hud.minimap().ping_count(), 0, "(setup) no pings")
	s.map_ping.emit(0, 40, 30)
	t.eq(r.game.hud.minimap().ping_count(), 0, "the echo of the own ping is not shown twice")
	s.map_ping.emit(1, 40, 30)
	t.eq(r.game.hud.minimap().ping_count(), 1, "a teammate's ping appears on the minimap")
	await _leave(r)


func test_ping_mode_takes_a_minimap_click(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Rig = _make_rig(MATCH_ROSTERS)
	await _enter(r)
	_populate(r, false)
	r.press(UiKeymap.instance().bindings(&"cmd_ping")[0])
	await H.frames(1)
	var mm: UiMinimap = r.game.hud.minimap()
	var rect: Rect2 = mm.map_rect()
	H.click(r.h.vp, mm.get_global_rect().position + rect.get_center())
	await H.frames(1)
	t.eq(r.spy.pings.size(), 1, "a click on the minimap pings the team through the net port")
	t.eq(r.spy.pings[0], Vector2i(mm.map_cells.x / 2, mm.map_cells.y / 2), "at the clicked cell")
	t.eq(mm.ping_count(), 1, "with a ring on the minimap")
	t.eq(r.game.modes.armed, UiModes.Armed.NONE, "and the ping mode ends")
	await _leave(r)


func test_camera_pad_buttons_move_the_camera(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var r: Rig = _make_rig(MATCH_ROSTERS)
	await _enter(r)
	_populate(r, false)
	r.reset()
	var pad: UiCameraPad = r.game.hud.sidebar().camera_pad()
	t.check(pad.is_visible_in_tree() and pad.size.x > 0.0, "(setup) the pad is shown")
	var ids: PackedStringArray = PackedStringArray()
	for b: Dictionary in UiCameraPad.BUTTONS:
		ids.append(String(b["id"]))
	var press: Callable = func(id: String) -> void:
		var i: int = ids.find(id)
		H.click(r.h.vp, pad.get_global_rect().position + pad.button_rect(i).get_center())
	var yaw: float = r.view.yaw_deg
	press.call("rotate_right")
	await H.frames(1)
	t.gt(r.view.yaw_deg, yaw, "the pad rotates right")
	yaw = r.view.yaw_deg
	press.call("rotate_left")
	await H.frames(1)
	t.lt(r.view.yaw_deg, yaw, "and left")
	var pitch: float = r.view.pitch_deg
	press.call("tilt_up")
	await H.frames(1)
	t.gt(r.view.pitch_deg, pitch, "tilts up")
	pitch = r.view.pitch_deg
	press.call("tilt_down")
	await H.frames(1)
	t.lt(r.view.pitch_deg, pitch, "and down")
	var dist: float = r.view.distance
	press.call("zoom_in")
	await H.frames(1)
	t.lt(r.view.distance, dist, "zooms in")
	dist = r.view.distance
	press.call("zoom_out")
	await H.frames(1)
	t.gt(r.view.distance, dist, "and out")
	r.away()
	press.call("centre_base")
	await H.frames(1)
	t.check(r.focus_near(r.hq), "centres on the base")
	r.game.presenter.last_alert = Vector2i(40 * 1024, 30 * 1024)
	r.away()
	press.call("jump_alert")
	await H.frames(1)
	var w: Vector3 = r.view.sim_to_world(40 * 1024, 30 * 1024)
	t.check(Vector2(r.view.focus.x, r.view.focus.z).distance_to(Vector2(w.x, w.z)) < 2.0, "and jumps to the last alert")
	await _leave(r)


func test_no_unit_has_two_ability_bar_abilities(t: TestCtx) -> void:
	# cmd_ability_2..4 (O, K, L) address the 2nd..4th ability button of the selected unit; no shipped unit has more than one, so the
	# probe can only assert "nothing happens". When data adds such a unit this fails: replace the no-effect branch of `_p_ability`.
	var d: GameData = _gd()
	for u: DefUnit in d.units:
		var n: int = 0
		for a: DefAbility in u.abilities:
			if a.kind in [DefEnums.AbilityKind.MODE_SWITCH, DefEnums.AbilityKind.PORTABLE_COVER, DefEnums.AbilityKind.DECOY_SPAWN,
					DefEnums.AbilityKind.SENSOR_PUCK, DefEnums.AbilityKind.SMOKE_LAUNCHER]:
				n += 1
		t.le(n, 1, "%s has %d ability-bar abilities: give cmd_ability_%d a real probe" % [u.id, n, n])


func test_default_hotkey_labels_of_the_hud_match_the_keymap(t: TestCtx) -> void:
	var km: UiKeymap = UiKeymap.instance()
	var by_cmd: Dictionary = {"attack_move": "cmd_attack_move", "guard": "cmd_guard", "stop": "cmd_stop", "scatter": "cmd_scatter",
		"deploy": "cmd_deploy", "sell": "tool_sell", "repair": "tool_repair", "stance": "cmd_stance_cycle"}
	for c: Dictionary in UiCommandBar.COMMANDS:
		var label: String = km.label(StringName(by_cmd[String(c["id"])]))
		var shown: String = String(c["key"])
		t.check(label == shown or (shown == "Del" and label == "Delete"), "command bar %s shows %s, the keymap says %s" % [c["id"], shown, label])
	var dock: Array = ["power_1", "power_2", "power_3", "superweapon"]
	for i: int in dock.size():
		t.eq(km.label(StringName(dock[i])), UiPowerDock.KEYS[i], "power dock key %d" % (i + 1))
	var abil: Array = ["cmd_ability_1", "cmd_ability_2", "cmd_ability_3", "cmd_ability_4"]
	for i2: int in abil.size():
		t.eq(km.label(StringName(abil[i2])), UiAbilityBar.ABILITY_KEYS[i2], "ability key %d" % (i2 + 1))
	for i3: int in UiBuildModel.CARD_KEYS.size():
		var card: String = km.label(StringName("card_%d" % (i3 + 1)))
		t.check(card == "Alt+" + UiBuildModel.CARD_KEYS[i3] or card == "Option+" + UiBuildModel.CARD_KEYS[i3], "card hotkey %d is %s" % [i3 + 1, card])


# ---------------------------------------------------------------- pass 2: the observer HUD (the golden replay)

func _drive(ctx: AppMatchContext, until: Callable, max_ms: int = 60000) -> bool:
	var t0: int = Time.get_ticks_msec()
	while not until.call() and Time.get_ticks_msec() - t0 < max_ms:
		ctx.frame()
		OS.delay_msec(1)
	return until.call()


func _seek(ctx: AppMatchContext, tick: int) -> void:
	ctx.replay.set_speed(NetReplayPlayer.MAX)
	ctx.replay.seek(tick)
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	ctx.replay.set_speed(1.0)
	ctx.replay.set_paused(true)


func test_observer_hud_every_observer_key_has_an_effect(t: TestCtx) -> void:
	t.set_timeout(300.0)
	var ctx: AppMatchContext = AppReplay.start(REPLAY, {"with_view": false, "bind": false, "local_versions": {}})
	if not t.not_null(ctx, "the golden replay starts: %s" % AppReplay.last_error):
		return
	_drive(ctx, func() -> bool: return ctx.replay.is_ready or ctx.replay.is_failed)
	var r: Rig = Rig.new()
	r.ctx = ctx
	r.view = ctx.view as UiViewPortFixture
	r.h = await H.make()
	r.game = UiScreenGame.new()
	r.h.root.add_child(r.game)
	UiLayerRoot.fill(r.game)
	r.game.enter({"ctx": ctx})
	r.view.attach(r.h.vp)
	await H.frames(3)
	r.game.controller.edge_scroll = false
	var km: UiKeymap = UiKeymap.instance()
	var pressed: Dictionary = {}
	var key: Callable = func(id: String) -> void:
		pressed[id] = true
		r.press(km.bindings(StringName(id))[0])
	var oc: UiObserverController = r.game.observer_ctl
	ctx.replay.set_paused(true)
	# players 1..8: only the two players of the recording exist
	for k: int in range(1, 9):
		oc.set_perspective(-1)
		key.call("obs_player_%d" % k)
		await H.frames(1)
		t.eq(oc.perspective, k - 1 if k <= 2 else -1, "obs_player_%d %s" % [k, "watches that player" if k <= 2 else "does nothing: no such player"])
	oc.set_perspective(1)
	key.call("obs_all")
	await H.frames(1)
	t.eq(oc.perspective, -1, "obs_all watches everybody")
	var before: int = oc.perspective
	key.call("obs_next_player")
	await H.frames(1)
	t.ne(oc.perspective, before, "obs_next_player goes to the next player")
	oc.set_perspective(1)
	key.call("obs_toggle_fog")
	await H.frames(1)
	t.eq(oc.perspective, -1, "obs_toggle_fog switches the fog off")
	key.call("obs_toggle_fog")
	await H.frames(1)
	t.eq(oc.perspective, 1, "and back to that player")
	key.call("obs_follow")
	await H.frames(1)
	t.check(oc.follow, "obs_follow starts the follow camera")
	key.call("obs_follow")
	await H.frames(1)
	t.check(not oc.follow, "and stops it")
	var paused: bool = ctx.replay.is_paused()
	key.call("obs_pause")
	await H.frames(1)
	t.ne(ctx.replay.is_paused(), paused, "obs_pause toggles the playback")
	ctx.replay.set_paused(true)
	ctx.replay.set_speed(1.0)
	key.call("obs_speed_up")
	await H.frames(1)
	t.gt(ctx.replay.speed(), 1.0, "obs_speed_up is one speed chip up")
	ctx.replay.set_speed(1.0)
	key.call("obs_speed_down")
	await H.frames(1)
	t.lt(ctx.replay.speed(), 1.0, "obs_speed_down is one chip down")
	_seek(ctx, 800)
	key.call("obs_seek_back")
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.lt(ctx.tick(), 800, "obs_seek_back goes back 10 seconds")
	var low: int = ctx.tick()
	ctx.replay.set_paused(true)
	key.call("obs_seek_fwd")
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.gt(ctx.tick(), low, "obs_seek_fwd goes forward 10 seconds")
	oc._discovered[1] = 1500
	_seek(ctx, 100)
	key.call("obs_event_next")
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.eq(ctx.tick(), 1500 - UiObserverController.JUMP_LEAD_TICKS, "obs_event_next jumps to just before the next event")
	_seek(ctx, 2000)
	key.call("obs_event_prev")
	_drive(ctx, func() -> bool: return not ctx.replay.is_seeking())
	t.lt(ctx.tick(), 2000, "obs_event_prev jumps back to the previous event")
	var sb: bool = r.game.hud.scoreboard().visible
	key.call("toggle_scoreboard")
	await H.frames(1)
	t.ne(r.game.hud.scoreboard().visible, sb, "toggle_scoreboard shows the scoreboard")
	key.call("hide_ui")
	await H.frames(1)
	t.check(not r.game.hud.chrome_visible(), "hide_ui hides the observer panels too")
	key.call("hide_ui")
	key.call("cmd_ping")
	await H.frames(1)
	t.eq(r.game.modes.armed, UiModes.Armed.PING, "cmd_ping arms a ping for an observer too (local marker only: there is no net port)")
	for id: String in OBSERVER_PASS:
		t.check(pressed.has(id), "the observer pass pressed %s" % id)
	r.game.exit()
	ctx.dispose()
	AppState.match_ctx = null
	r.game.queue_free()
	H.done(r.h)
	await H.frames(2)


# ---------------------------------------------------------------- pass 3: a scripted mission

func test_mission_hud_toggle_objectives_key(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var ctx: AppMatchContext = AppMission.start("tut_field_training", 1, {"with_view": false, "bind": false, "discard_events": false})
	if not t.not_null(ctx, "the tutorial starts"):
		return
	var guard: int = 0
	while ctx.sim == null and guard < 4000:
		ctx.frame()
		OS.delay_msec(2)
		guard += 1
	var r: Rig = Rig.new()
	r.ctx = ctx
	r.view = ctx.view as UiViewPortFixture
	r.h = await H.make()
	r.game = UiScreenGame.new()
	r.h.root.add_child(r.game)
	UiLayerRoot.fill(r.game)
	r.game.enter({"ctx": ctx})
	await H.frames(3)
	if t.not_null(r.game.mission_hud, "the mission layer exists"):
		var before: bool = r.game.mission_hud.objectives.collapsed
		r.press(UiKeymap.instance().bindings(&"toggle_objectives")[0])
		await H.frames(1)
		t.ne(r.game.mission_hud.objectives.collapsed, before, "toggle_objectives collapses / opens the objectives panel")
	# the tutorial says "Press F5 ... UAV Sweep": that power sits in the first support slot of the tutorial's roster
	var uav: int = -1
	for i: int in ctx.data.powers.size():
		if ctx.data.powers[i].id.contains("uav") and ctx.sim.power_slot(i) >= 0:
			uav = i
	t.ne(uav, -1, "the tutorial roster has a UAV sweep power")
	if uav >= 0:
		t.eq(ctx.sim.power_slot(uav), 0, "and it is in slot 1, the F5 slot the tutorial names")
	r.game.exit()
	ctx.dispose()
	AppState.match_ctx = null
	r.game.queue_free()
	H.done(r.h)
	await H.frames(2)


func test_line_power_commits_on_a_drag_or_on_the_second_click(t: TestCtx) -> void:
	t.set_timeout(120.0)
	var d: GameData = _gd()
	var pidx: int = d.power_idx("power.pd.maritime_patrol")
	if not t.ne(pidx, -1, "(setup) the data has the PD line power"):
		return
	var r: Rig = _make_rig(PackedStringArray(["roster.pd.vanilla", "roster.napc.vanilla"]))
	await _enter(r)
	_populate(r, false)
	_ensure_powers_ready(r)
	var slot: int = r.sim.power_slot(pidx)
	if not t.check(slot >= 0 and slot < 3, "(setup) the PD roster has the line power in a support slot"):
		await _leave(r)
		return
	var key: int = UiKeymap.instance().bindings(StringName("power_%d" % (slot + 1)))[0]
	var hq: Vector2i = r.eid_xy(r.hq)
	for variant: String in ["two clicks", "drag"]:
		r.reset()
		r.w.players[0].econ.slots[slot].ready_tick = 0
		r.w.players[0].credits = 60000
		r.step_ticks(1)
		r.press(key)
		await H.frames(1)
		if not t.check(r.game.targeting.active and r.game.targeting.is_line(), "%s: the key starts a line power" % variant):
			continue
		var a: Vector2 = Vector2(700.0, 500.0)
		var b: Vector2 = Vector2(900.0, 560.0)
		if variant == "drag":
			r.game._on_select_box(Rect2(a, b - a), 0)
		else:
			r.game._on_select_click(a, 0, false)
			t.check(r.game.targeting.is_pressing(), "the first click sets the start point")
			t.check(not r.spy.has_op(SimCmd.USE_POWER), "and casts nothing yet")
			r.game.presenter.world_motion(b)
			r.game._on_select_click(b, 0, false)
		t.check(r.spy.has_op(SimCmd.USE_POWER), "%s: the power is cast" % variant)
		t.check(not r.game.targeting.active, "%s: targeting ends" % variant)
		t.check(r.game.selection.is_empty(), "%s: aiming never changes the selection" % variant)
		r.step_ticks(4)  # the command executes on the next turn: wait for it before the next variant resets the cooldown
	t.ge(hq.x, 0, "(the base exists)")
	await _leave(r)
