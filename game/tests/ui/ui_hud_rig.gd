extends RefCounted
## HUD rig for labs and tests (UI-08 / UI-10): a REAL `SimWorld` (SimMatchKit) behind `UiSimPortWorld`, the fixture view
## (`UiViewPortFixture` battlefield + 2D overlay), the loopback net port, selection / groups / bus / placement / targeting,
## a `UiHud` and its `UiHudPresenter`. `pump(ticks)` is the screen's game loop in miniature: sim steps -> events ->
## presenter cadences -> view refresh. Not a test file. No class_name (rigs never take real class names).
##   var r = _Self.new(); r.build(host, {"seed": 3, "warm": 900}); r.pump(10)

const _MK := preload("res://tests/support/sim_match_kit.gd")

var world: SimWorld = null
var data: GameData = null
var match_info: Dictionary = {}
var sim: UiSimPort = null
var view: UiViewPortFixture = null
var net: UiNetPort = null  ## UiNetPortLoopback over the world, UiNetPortRecorder over a fixture
var audio: UiAudioPortRecorder = null
var selection: UiSelection = null
var groups: UiControlGroups = null
var bus: UiCommandBus = null
var placement: UiPlacement = null
var targeting: UiTargeting = null
var feedback: UiFeedback = null
var presenter: UiHudPresenter = null
var hud: UiHud = null
var modes: UiModes = null
var roster: DefRoster = null
var pid: int = 0
var errors: PackedStringArray = PackedStringArray()


## Options: seed (1), size (96), rosters (2 vanilla NAPC / NEC), warm (bot ticks played before the HUD starts, default 0),
## faction (skin code, default the local roster's), render (true builds the 3D fixture battlefield), bots_after (bots keep
## playing every pump tick for pid 1 only when true).
func build(host: Control, o: Dictionary = {}) -> void:
	if o.has("fixture"):
		_build_common(host, o, o["fixture"] as UiSimPortFixture)
		return
	var mo: Dictionary = {"seed": int(o.get("seed", 1)), "size": int(o.get("size", 96)), "bots": true}
	if o.has("rosters"):
		mo["rosters"] = o["rosters"]
	if o.has("rules"):
		mo["rules"] = o["rules"]
	match_info = _MK.make_match(mo)
	world = match_info["world"] as SimWorld
	data = match_info["data"] as GameData
	var warm: int = int(o.get("warm", 0))
	if warm > 0:
		_MK.run(match_info, warm)
	if not bool(o.get("bots_after", false)):
		(match_info["bots"] as Array).clear()
	var sp := UiSimPortWorld.new(world, pid)
	sp.take_events()  # the warm-up's history is not news
	net = UiNetPortLoopback.new(world, pid)
	_build_common(host, o, sp)


func _build_common(host: Control, o: Dictionary, port: UiSimPort) -> void:
	sim = port
	if net == null:
		net = UiNetPortRecorder.new()
	pid = port.local_pid()
	data = port.data()
	roster = sim.roster_of(pid)
	var skins: UiSkinSet = UiSkinSet.shared()
	skins.setup_from_json()
	var fac: String = String(o.get("faction", ""))
	if fac == "":
		fac = data.factions[roster.faction].code.to_lower() if roster.faction >= 0 and roster.faction < data.factions.size() else "napc"
	UiThemeService.rebuild(skins.skin_for(fac))
	var render: bool = bool(o.get("render", true))
	view = UiViewPortFixture.new(sim, 0.0, render)
	if host.get_viewport() != null:
		view.attach(host)
	audio = UiAudioPortRecorder.new()
	selection = UiSelection.new()
	groups = UiControlGroups.new()
	modes = UiModes.new()
	hud = UiHud.new()
	if render:
		host.add_child(view.overlay)
		UiLayerRoot.fill(view.overlay)
	host.add_child(hud)
	UiLayerRoot.fill(hud)
	hud.setup(skins.skin_for(fac), data, roster, UiHud.MODE_PLAYER)
	feedback = UiFeedback.new()
	bus = UiCommandBus.new()
	bus.setup(net, sim, view, audio, feedback)
	placement = UiPlacement.new()
	placement.setup(sim, view, bus, audio, roster)
	targeting = UiTargeting.new()
	targeting.setup(sim, bus, hud.overlay(), audio, roster)
	presenter = UiHudPresenter.new()
	presenter.set_modes(modes)
	presenter.setup_ports(sim, view, audio, roster, hud, selection, groups, bus, placement, targeting, null)
	feedback.setup(presenter, presenter, audio, null)
	view.refresh()


## Where the local player's start is (sim units), for camera focus.
func base_center() -> Vector2i:
	var best: Vector2i = Vector2i(sim.map_w() * 512, sim.map_h() * 512)
	var ids: PackedInt32Array = PackedInt32Array()
	sim.own_ids(UiSimPort.KM_STRUCTURE, ids)
	if ids.is_empty():
		return best
	var row := UiEntityRow.new()
	var sx: int = 0
	var sy: int = 0
	for id: int in ids:
		sim.read(id, row)
		sx += row.x
		sy += row.y
	return Vector2i(sx / ids.size(), sy / ids.size())


func focus_base() -> void:
	var c: Vector2i = base_center()
	view.focus_on_sim(c.x, c.y, true)
	view.set_camera_smoothing(false)
	view.refresh()


## `ticks` sim ticks (in one presenter batch), then the per-frame work.
func pump(ticks: int = 1, delta: float = 0.05) -> void:
	for _i: int in ticks:
		if world != null:
			for b: Object in (match_info["bots"] as Array):
				b.call(&"think", world)
			world.step()
		else:
			(sim as UiSimPortFixture).advance(1)
	var ev: PackedInt32Array = sim.take_events()
	presenter.on_events(ev)
	presenter.on_ticks(ticks)
	presenter.on_frame(delta)
	view.refresh()


## Own entity ids of a kind mask (UiSimPort.KIND_*).
func own(kind_mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	sim.own_ids(kind_mask, out)
	return out


## The card of a display name in the model (any tab), or null.
func card(display_name: String) -> UiBuildItem:
	for tab: int in UiBuildModel.TAB_COUNT:
		for it: UiBuildItem in presenter.model().items(tab):
			if it.display_name == display_name:
				return it
	return null


## A left click on a card (count 5 = shift click), as the sidebar would emit it.
func click_card(display_name: String, count: int = 1) -> bool:
	var it: UiBuildItem = card(display_name)
	if it == null:
		return false
	presenter.model().refresh(sim, PackedInt32Array())
	if count > 1:
		hud.build_requested.emit(it, count)
	elif it.kind == UiBuildItem.Kind.STRUCTURE and it.state == UiBuildItem.State.READY:
		hud.place_requested.emit(it)
	else:
		hud.build_requested.emit(it, 1)
	return true
