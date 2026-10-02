extends RefCounted
## Selection model (ui.md 5.11, 10.2 `test_ui_selection`): modes, cap, prune, survival of death, successor rule.

const RIFLE: String = "unit.napc.rifle_squad"
const TANK: String = "unit.napc.guardian_tank"
const MCV: String = "unit.shared.mobile_construction_vehicle"
const BARRACKS: String = "structure.shared.barracks"
const HQ: String = "structure.shared.headquarters"


func _fx() -> UiSimPortFixture:
	var f: UiSimPortFixture = UiSimPortFixture.blank()
	f.add_player(0, "Me", 1, "roster.napc.canada", 1000)
	f.add_player(1, "Foe", 2, "roster.napc.canada")
	f.set_viewer(0)
	return f


func _ids(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


func test_replace_add_toggle(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var a: int = f.spawn(RIFLE, 0, 1000, 1000, 11).id
	var b: int = f.spawn(RIFLE, 0, 2000, 1000, 12).id
	var c: int = f.spawn(TANK, 0, 3000, 1000, 13).id
	var sel := UiSelection.new()
	var fired: Array[int] = []
	sel.changed.connect(func(m: int) -> void: fired.append(m))
	sel.replace(_ids([a, b]), f)
	t.eq(sel.ids, _ids([a, b]))
	t.eq(sel.mode, UiSelection.Mode.UNITS)
	t.eq(sel.size(), 2)
	sel.add(_ids([c]), f)
	t.eq(sel.ids, _ids([a, b, c]), "selection order is kept")
	sel.add(_ids([a]), f)
	t.eq(sel.size(), 3, "adding an already selected id changes nothing")
	sel.toggle(b, f)
	t.eq(sel.ids, _ids([a, c]))
	sel.toggle(b, f)
	t.eq(sel.ids, _ids([a, c, b]), "toggle adds at the end")
	sel.replace(_ids([c]), f)
	t.eq(sel.ids, _ids([c]))
	sel.clear()
	t.eq(sel.mode, UiSelection.Mode.NONE)
	t.eq(sel.primary, -1)
	t.gt(fired.size(), 4, "changed is emitted on each change")
	sel.clear()
	var n: int = fired.size()
	sel.clear()
	t.eq(fired.size(), n, "clearing an empty selection is silent")


func test_units_win_over_structures(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var u: int = f.spawn(RIFLE, 0, 1000, 1000, 11).id
	var s: int = f.spawn(BARRACKS, 0, 5000, 5000, 20).id
	var s2: int = f.spawn(BARRACKS, 0, 8000, 5000, 21).id
	var sel := UiSelection.new()
	sel.replace(_ids([s, u]), f)
	t.eq(sel.ids, _ids([u]))
	t.eq(sel.mode, UiSelection.Mode.UNITS)
	sel.replace(_ids([s, s2]), f)
	t.eq(sel.mode, UiSelection.Mode.STRUCTURES)
	t.eq(sel.ids, _ids([s, s2]), "several structures are allowed")
	sel.add(_ids([u]), f)
	t.eq(sel.ids, _ids([u]), "adding a unit to a structure selection replaces it")
	sel.add(_ids([s]), f)
	t.eq(sel.ids, _ids([s]), "adding a structure to a unit selection replaces it")


func test_foreign_selection_is_single(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var e1: int = f.spawn(TANK, 1, 1000, 1000, 31).id
	var e2: int = f.spawn(TANK, 1, 2000, 1000, 32).id
	var own: int = f.spawn(TANK, 0, 3000, 1000, 33).id
	var sel := UiSelection.new()
	sel.replace(_ids([e1, e2]), f)
	t.eq(sel.mode, UiSelection.Mode.FOREIGN)
	t.eq(sel.ids, _ids([e1]), "exactly one foreign entity")
	sel.add(_ids([e2]), f)
	t.eq(sel.ids, _ids([e2]), "adding to a foreign selection replaces it")
	sel.replace(_ids([e1, own]), f)
	t.eq(sel.mode, UiSelection.Mode.UNITS, "own entities beat foreign ones")
	t.eq(sel.ids, _ids([own]))
	sel.toggle(e1, f)
	t.eq(sel.mode, UiSelection.Mode.FOREIGN)


func test_cap_500(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var all: PackedInt32Array = PackedInt32Array()
	for i: int in 501:
		all.append(f.spawn(RIFLE, 0, 1000 + i, 1000, 100 + i).id)
	var sel := UiSelection.new()
	sel.replace(all, f)
	t.eq(sel.size(), UiSelection.MAX_SELECT, "the 501st unit is refused")
	t.check(not sel.has(all[500]))
	sel.add(PackedInt32Array([all[500]]), f)
	t.eq(sel.size(), UiSelection.MAX_SELECT, "and stays refused when added")


func test_sorted_ids_cached_and_ascending(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var ids: PackedInt32Array = PackedInt32Array()
	for id: int in [30, 12, 21]:
		ids.append(f.spawn(RIFLE, 0, id * 100, 0, id).id)
	var sel := UiSelection.new()
	sel.replace(ids, f)
	t.eq(sel.ids, _ids([30, 12, 21]))
	t.eq(sel.sorted_ids(), _ids([12, 21, 30]))
	var first: PackedInt32Array = sel.sorted_ids()
	t.eq(sel.sorted_ids(), first, "cached until the next change")
	sel.remove(21)
	t.eq(sel.sorted_ids(), _ids([12, 30]), "cache invalidated by a change")


func test_prune_dead_foreign_and_contained(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var a: UiEntityRow = f.spawn(RIFLE, 0, 1000, 1000, 11)
	var b: UiEntityRow = f.spawn(RIFLE, 0, 2000, 1000, 12)
	var c: UiEntityRow = f.spawn(RIFLE, 0, 3000, 1000, 13)
	var d: UiEntityRow = f.spawn(RIFLE, 0, 4000, 1000, 14)
	var sel := UiSelection.new()
	sel.replace(_ids([a.id, b.id, c.id, d.id]), f)
	t.eq(sel.primary, 11)
	t.check(not sel.prune(f), "nothing changed, nothing pruned")
	f.remove_entity(a.id)
	b.owner = 1
	c.flags |= UiEntityRow.F_LOADED
	t.check(sel.prune(f), "prune reports the change")
	t.eq(sel.ids, _ids([14]), "dead, captured and contained ids are dropped")
	t.eq(sel.primary, 14, "the primary is re-picked")
	f.remove_entity(d.id)
	sel.prune(f)
	t.eq(sel.mode, UiSelection.Mode.NONE, "an empty selection is NONE")
	t.eq(sel.primary, -1)


func test_removed_event_hook(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var sel := UiSelection.new()
	sel.replace(_ids([f.spawn(RIFLE, 0, 1, 1, 11).id, f.spawn(RIFLE, 0, 2, 1, 12).id]), f)
	sel.on_removed(11, 0, -1)
	t.eq(sel.ids, _ids([12]), "REMOVED(KILLED) drops the id at once")
	sel.on_removed(99, 0, -1)
	t.eq(sel.ids, _ids([12]), "unknown ids are ignored")
	sel.on_removed(12, 0, -1)
	t.eq(sel.size(), 0)


func test_successor_rule_with_parent(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	f.spawn(MCV, 0, 1000, 1000, 5)
	var sel := UiSelection.new()
	sel.replace(_ids([5]), f)
	t.eq(sel.mode, UiSelection.Mode.UNITS)
	var recs: PackedInt32Array = PackedInt32Array([
		UiEv.REMOVED, 100, 0, 0, 5, 0, 20, 0, UiEv.REM_DEPLOYED, 0,
		UiEv.SPAWNED, 100, 0, 0, 9, 1, 30, 0, 0, UiEv.SPAWN_DEPLOYED])
	var succ: Dictionary = {}
	UiSelection.successors_of(recs, succ, func(spawned: int) -> int: return 5 if spawned == 9 else 0)
	t.eq(succ, {5: 9})
	sel.on_removed(5, UiEv.REM_DEPLOYED, int(succ[5]))
	t.eq(sel.ids, _ids([9]), "the selection follows the MCV to its Headquarters")
	t.eq(sel.mode, UiSelection.Mode.STRUCTURES)


func test_successor_pairing_by_emission_order(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	f.spawn(MCV, 0, 1000, 1000, 5)
	f.spawn(MCV, 0, 2000, 1000, 6)
	var sel := UiSelection.new()
	sel.replace(_ids([5, 6]), f)
	# two MCVs of owner 0 deploy in one batch; the parent field is 0, plus a deployment of owner 1
	var recs: PackedInt32Array = PackedInt32Array([
		UiEv.REMOVED, 100, 0, 0, 5, 0, 20, 0, UiEv.REM_DEPLOYED, 0,
		UiEv.REMOVED, 100, 0, 0, 77, 0, 20, 1, UiEv.REM_DEPLOYED, 0,
		UiEv.REMOVED, 100, 0, 0, 6, 0, 20, 0, UiEv.REM_DEPLOYED, 0,
		UiEv.SPAWNED, 100, 0, 0, 9, 1, 30, 0, 0, UiEv.SPAWN_DEPLOYED,
		UiEv.SPAWNED, 100, 0, 0, 10, 1, 30, 0, 0, UiEv.SPAWN_DEPLOYED,
		UiEv.SPAWNED, 100, 0, 0, 88, 1, 30, 1, 0, UiEv.SPAWN_DEPLOYED])
	var succ: Dictionary = {}
	UiSelection.successors_of(recs, succ, func(_s: int) -> int: return 0)
	t.eq(succ, {5: 9, 6: 10, 77: 88}, "5 -> 9 and 6 -> 10 keep their order; owner 1 pairs on its own")
	sel.on_removed(5, UiEv.REM_DEPLOYED, int(succ[5]))
	sel.on_removed(6, UiEv.REM_DEPLOYED, int(succ[6]))
	t.eq(sel.sorted_ids(), _ids([9, 10]))
	t.eq(sel.mode, UiSelection.Mode.STRUCTURES)


func test_successor_of_another_owner_is_ignored(t: TestCtx) -> void:
	var recs: PackedInt32Array = PackedInt32Array([
		UiEv.REMOVED, 100, 0, 0, 5, 0, 20, 0, UiEv.REM_DEPLOYED, 0,
		UiEv.SPAWNED, 100, 0, 0, 9, 1, 30, 1, 0, UiEv.SPAWN_DEPLOYED])
	var succ: Dictionary = {}
	UiSelection.successors_of(recs, succ)
	t.check(not succ.has(5), "no successor across owners")
	var f: UiSimPortFixture = _fx()
	f.spawn(MCV, 0, 1000, 1000, 5)
	var sel := UiSelection.new()
	sel.replace(_ids([5]), f)
	sel.on_removed(5, UiEv.REM_DEPLOYED, -1)
	t.eq(sel.size(), 0, "a DEPLOYED removal without a successor just drops the id")


func test_successor_with_other_units_keeps_units(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	f.spawn(MCV, 0, 1000, 1000, 5)
	f.spawn(RIFLE, 0, 2000, 1000, 6)
	var sel := UiSelection.new()
	sel.replace(_ids([5, 6]), f)
	sel.on_removed(5, UiEv.REM_DEPLOYED, 9)
	t.check(sel.settle(), "a mixed selection is resolved by settle")
	t.eq(sel.ids, _ids([6]), "units win over the new structure")
	t.eq(sel.mode, UiSelection.Mode.UNITS)


func test_primary_and_subgroups(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var d: GameData = f.data()
	var rifle_def: int = d.unit_idx(RIFLE)
	var tank_def: int = d.unit_idx(TANK)
	var r1: int = f.spawn(RIFLE, 0, 1, 1, 21).id
	var r2: int = f.spawn(RIFLE, 0, 2, 1, 22).id
	var k1: int = f.spawn(TANK, 0, 3, 1, 23).id
	var k2: int = f.spawn(TANK, 0, 4, 1, 24).id
	var sel := UiSelection.new()
	sel.replace(_ids([r1, r2, k2, k1]), f)
	var rank_tank: int = d.units[tank_def].tier * 1048576 + d.units[tank_def].cost
	var rank_rifle: int = d.units[rifle_def].tier * 1048576 + d.units[rifle_def].cost
	var want_def: int = tank_def if rank_tank > rank_rifle else rifle_def
	if rank_tank == rank_rifle:
		want_def = mini(tank_def, rifle_def)
	t.eq(sel.active_def, want_def, "active subgroup = highest (tier, cost), ties lowest def")
	var first_of_def: int = -1
	for id: int in sel.ids:
		if sel.def_of(id) == want_def:
			first_of_def = id
			break
	t.eq(sel.primary, first_of_def, "primary = first selected id of the active subgroup")
	var other_def: int = rifle_def if want_def == tank_def else tank_def
	sel.cycle_subgroup(1)
	t.eq(sel.active_def, other_def, "Ctrl+Tab cycles to the other def")
	t.eq(sel.def_of(sel.primary), other_def)
	sel.cycle_subgroup(1)
	t.eq(sel.active_def, want_def, "and wraps around")
	sel.cycle_subgroup(-1)
	t.eq(sel.active_def, other_def, "backwards works")
	t.eq(sel.count_of_def(rifle_def), 2)


func test_info_builds_from_selection(t: TestCtx) -> void:
	var f: UiSimPortFixture = _fx()
	var k: int = f.spawn(TANK, 0, 1, 1, 21).id
	var r: int = f.spawn(RIFLE, 0, 2, 1, 22).id
	var sel := UiSelection.new()
	sel.replace(_ids([r, k]), f)
	var info: UiSelectionInfo = UiSelectionInfo.build(sel, f)
	t.eq(info.ids, _ids([21, 22]), "info ids are ascending")
	t.eq(info.count, 2)
	t.check((info.caps_any & UiUnitCaps.CAP_ARMED) != 0)
	t.check((info.caps_all & UiUnitCaps.CAP_MOBILE) != 0)
	t.check(info.move_mask != 0)
	t.eq(info.ids_with(UiUnitCaps.CAP_INFANTRY), _ids([22]))
	t.eq(info.ids_without(UiUnitCaps.CAP_INFANTRY), _ids([21]))
	t.eq(info.ids_with(UiUnitCaps.CAP_INFANTRY | UiUnitCaps.CAP_VEHICLE, false), _ids([21, 22]))
	t.eq(info.ids_with(UiUnitCaps.CAP_INFANTRY | UiUnitCaps.CAP_VEHICLE, true), PackedInt32Array())
