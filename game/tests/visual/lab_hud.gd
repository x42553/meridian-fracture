extends UiLayerRoot
## In-game HUD lab (UI-08 / UI-10): the full HUD on a REAL SimWorld (SimMatchKit match, the local player's bot-built base)
## over the fixture battlefield.
##   tools/gd shot res://tests/visual/lab_hud.tscn out.png --size 1920x1080 -- --scenario=mid
## Options: --scenario=mid|select|placement|targeting|lowpower|factories|alert|strategic, --seed=N, --warm=ticks,
## --tab=0..3, --rosters=a,b (roster ids), --ui-scale=x. No class_name on purpose.

const _Rig := preload("res://tests/ui/ui_hud_rig.gd")

var rig: RefCounted = null
var _args: Dictionary = {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	UiLayout.apply(win, float(_args.get("ui-scale", "1.0")))
	rig = _Rig.new()
	var o: Dictionary = {"seed": int(_args.get("seed", "3")), "warm": int(_args.get("warm", "2400"))}
	if _args.has("fog"):
		o["rules"] = {"fog": true}
	if _args.has("rosters"):
		o["rosters"] = PackedStringArray((_args["rosters"] as String).split(","))
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	UiLayerRoot.fill(host)
	if _args.has("fixture"):
		o = {"fixture": UiSimPortFixture.load_file(str(_args["fixture"]))}
	rig.call(&"build", host, o)
	rig.call(&"focus_base")
	if _args.has("fixture"):
		_fixture_scenario(str(_args.get("scenario", "mid")))
	else:
		_scenario(str(_args.get("scenario", "mid")))
	for _i: int in 3:
		rig.call(&"pump", 1)
	var sim: UiSimPort = rig.get(&"sim")
	print("LAB_HUD tick=", sim.tick(), " credits=", sim.credits(), " power=", sim.power_supply(), "/", sim.power_demand(), " roster=", sim.roster_of(0).id)


func _pump(n: int) -> void:
	for _i: int in n:
		rig.call(&"pump", 1)


func _cred(v: int) -> void:
	((rig.get(&"world") as SimWorld).players[0] as SimPlayer).credits = v


## Fixture-driven states (every card state at once): selection of the fixture's `selected` units, tab from --tab.
func _fixture_scenario(scenario: String) -> void:
	var f: UiSimPortFixture = rig.get(&"sim") as UiSimPortFixture
	var pres: UiHudPresenter = rig.get(&"presenter")
	var sel: UiSelection = rig.get(&"selection")
	sel.replace(f.selected, f)
	if scenario == "vehicles":
		pres.call(&"_show_tab", UiBuildModel.Tab.VEHICLES)
	if _args.has("tab"):
		pres.call(&"_show_tab", int(_args["tab"]))
	if scenario == "sw":
		f.advance(1750)
		f.push_event(PackedInt32Array([UiEv.ATTACK_ALERT, 0, 70000, 60000, 0, 89, 1, 1]))
		pres.call(&"_show_tab", UiBuildModel.Tab.POWERS)
	f.advance(20)
	rig.call(&"pump", 20)


func _world() -> SimWorld:
	return rig.get(&"world") as SimWorld


## Spawns one of every producible structure of the local roster in a grid beside the base (unlocks everything).
func _spawn_all(power: bool = true, skip: PackedStringArray = PackedStringArray()) -> void:
	var w: SimWorld = _world()
	var c: Vector2i = rig.call(&"base_center")
	var roster: DefRoster = (rig.get(&"sim") as UiSimPortWorld).roster_of(0)
	var have: Dictionary = {}
	for e: SimEntity in w.structures_of(0):
		have[e.def_idx] = true
	var n: int = 0
	for si: int in roster.producible_structures:
		var sd: DefStructure = roster.structures[si]
		if have.has(si) or skip.has(sd.id) or (sd.tags & DefEnums.ST_SUPERWEAPON) != 0 and false:
			continue
		var gx: int = c.x - (12 + (n % 4) * 8) * 1024
		var gy: int = c.y + (-16 + (n / 4) * 8) * 1024
		w.spawn_structure(si, 0, gx, gy, 0, 0, 0, 0, SimEvent.SPAWN_PLACED)
		n += 1
	if power:
		var gi: int = sim_data_idx("structure.shared.generator")
		for k: int in 6:
			w.spawn_structure(gi, 0, c.x - (12 + k * 3) * 1024, c.y + 14 * 1024, 0, 0, 0, 0, SimEvent.SPAWN_PLACED)


func sim_data_idx(id: String) -> int:
	return (rig.get(&"sim") as UiSimPortWorld).data().structure_idx(id)


## An army of the roster's armed units in a block in front of the base.
func _spawn_army(n: int = 14) -> PackedInt32Array:
	var w: SimWorld = _world()
	var c: Vector2i = rig.call(&"base_center")
	var roster: DefRoster = (rig.get(&"sim") as UiSimPortWorld).roster_of(0)
	var armed: Array[int] = []
	for ui: int in roster.producible_units:
		var u: DefUnit = roster.units[ui]
		if not u.weapons.is_empty() and u.pop > 0 and (u.move_class == DefEnums.MoveClass.FOOT or u.move_class == DefEnums.MoveClass.TRACKED or u.move_class == DefEnums.MoveClass.WHEELED):
			armed.append(ui)
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var e: SimEntity = w.spawn_unit(armed[i % armed.size()], 0, c.x - (5 + i % 5 * 2) * 1024, c.y + (2 + i / 5 * 2) * 1024, (i * 300) & 4095)
		if e != null:
			out.append(e.id)
	return out


func _scenario(scenario: String) -> void:
	var r: Object = rig
	var sim: UiSimPortWorld = r.get(&"sim")
	var sel: UiSelection = r.get(&"selection")
	var pres: UiHudPresenter = r.get(&"presenter")
	var w: SimWorld = _world()
	pres.auto_place = false
	_cred(int(_args.get("credits", "7000")))
	match scenario:
		"mid":
			r.call(&"click_card", "Generator")
			_pump(420)
			r.call(&"click_card", "Barracks")
			r.call(&"click_card", "Refinery")
			_pump(40)
		"select":
			_spawn_army()
			_pump(2)
			var ids: PackedInt32Array = r.call(&"own", UiSimPort.KM_UNIT)
			sel.replace(ids.slice(0, 12), sim)
			(r.get(&"groups") as UiControlGroups).assign(0, ids.slice(0, 6))
			(r.get(&"groups") as UiControlGroups).assign(2, ids.slice(6, 12))
			_pump(4)
		"units":
			_spawn_all()
			_pump(5)
			pres.call(&"_show_tab", UiBuildModel.Tab.VEHICLES)
			var n: int = 0
			for it: UiBuildItem in pres.model().items(UiBuildModel.Tab.VEHICLES):
				if it.state == UiBuildItem.State.AVAILABLE and n < 4:
					r.call(&"click_card", it.display_name, 3 if n == 0 else 1)
					n += 1
			_pump(60)
		"factories":
			_spawn_all(true)
			var c3: Vector2i = r.call(&"base_center")
			var fi: int = sim_data_idx("structure.shared.factory")
			w.spawn_structure(fi, 0, c3.x - 12 * 1024, c3.y + 20 * 1024, 0, 0, 0, 0, SimEvent.SPAWN_PLACED)
			_pump(5)
			pres.call(&"_show_tab", UiBuildModel.Tab.VEHICLES)
			var k: int = 0
			for it3: UiBuildItem in pres.model().items(UiBuildModel.Tab.VEHICLES):
				if it3.state == UiBuildItem.State.AVAILABLE and k < 3:
					r.call(&"click_card", it3.display_name, 2 if k == 0 else 1)
					k += 1
			_pump(40)
			var fids: PackedInt32Array = PackedInt32Array()
			sim.producers(DefEnums.QueueKind.VEHICLE, fids)
			if fids.size() > 1:
				pres.call(&"_on_producer_cycled", 1)
				r.call(&"click_card", "Guardian Tank")
			sel.replace(fids.slice(0, 1), sim)
			_pump(30)
		"lowpower":
			_spawn_all(false)
			_pump(30)
		"placement":
			_spawn_all()
			var c: Vector2i = r.call(&"base_center")
			var clicked: bool = false
			for _k: int in 60:
				_pump(10)
				for it0: UiBuildItem in pres.model().items(UiBuildModel.Tab.STRUCTURES):
					if it0.state == UiBuildItem.State.READY:
						r.call(&"click_card", it0.display_name)
						clicked = true
						break
				if clicked:
					break
			var pl: UiPlacement = r.get(&"placement")
			pl.update_cell(c.x / 1024 - 6, c.y / 1024 + 3)
			_pump(2)
		"targeting":
			_spawn_all()
			_pump(60)
			pres.call(&"_show_tab", UiBuildModel.Tab.POWERS)
			for it2: UiBuildItem in pres.model().items(UiBuildModel.Tab.POWERS):
				if it2.kind == UiBuildItem.Kind.POWER and it2.state == UiBuildItem.State.AVAILABLE and it2.target_mode != 0:
					(r.get(&"targeting") as UiTargeting).begin_power(it2.power_idx)
					break
			var c2: Vector2i = r.call(&"base_center")
			(r.get(&"targeting") as UiTargeting).update(c2.x - 9000, c2.y + 2000)
			_pump(2)
	if _args.has("tab"):
		pres.call(&"_show_tab", int(_args["tab"]))
