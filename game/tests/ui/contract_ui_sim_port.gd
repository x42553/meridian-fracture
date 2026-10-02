extends RefCounted
## Shared contract test of `UiSimPort` adapters (ui.md 4.4, 10.2 `test_ui_fixture_port`): run against the fixture and
## the world adapter so both obey the same rules. Not a test file (no `test_*` functions): call `check(t, port, label)`.


static func check(t: TestCtx, port: UiSimPort, label: String) -> void:
	_identity(t, port, label)
	_entities(t, port, label)
	_snapshot(t, port, label)
	_economy(t, port, label)
	_map_and_events(t, port, label)


static func _identity(t: TestCtx, port: UiSimPort, label: String) -> void:
	t.ge(port.tick(), 0, "%s tick" % label)
	t.gt(port.player_count(), 0, "%s players" % label)
	t.not_null(port.data(), "%s data" % label)
	t.gt(port.map_w(), 0, "%s map_w" % label)
	t.gt(port.map_h(), 0, "%s map_h" % label)
	var v: int = port.viewer_pid()
	t.eq(port.rel(v, v), UiSimPort.Rel.SELF, "%s rel self" % label)
	t.eq(port.rel(v, -1), UiSimPort.Rel.NEUTRAL, "%s rel neutral" % label)
	t.check(port.name_of(v) != "", "%s name" % label)
	t.not_null(port.roster_of(v), "%s roster" % label)
	t.eq(port.table_idx(UiSimPort.KIND_UNIT, 7), 7, "%s table_idx identity" % label)
	t.eq(port.sim_def(UiSimPort.KIND_UNIT, 7), 7, "%s sim_def identity" % label)
	t.ge(port.color_of(v), 0, "%s color" % label)
	t.check(port.player_active(v), "%s viewer active" % label)


static func _entities(t: TestCtx, port: UiSimPort, label: String) -> void:
	var all: PackedInt32Array = PackedInt32Array()
	var units: PackedInt32Array = PackedInt32Array()
	var structs: PackedInt32Array = PackedInt32Array()
	port.own_ids(UiSimPort.KM_UNIT | UiSimPort.KM_STRUCTURE, all)
	port.own_ids(UiSimPort.KM_UNIT, units)
	port.own_ids(UiSimPort.KM_STRUCTURE, structs)
	t.eq(units.size() + structs.size(), all.size(), "%s unit + structure ids = all own ids" % label)
	t.check(_ascending(all), "%s own ids ascending unique" % label)
	var row := UiEntityRow.new()
	var viewer: int = port.viewer_pid()
	for id: int in all:
		t.check(port.alive(id), "%s alive %d" % [label, id])
		t.check(port.read(id, row), "%s read %d" % [label, id])
		t.eq(row.id, id, "%s row id" % label)
		t.eq(row.owner, viewer, "%s row owner" % label)
		t.check(row.hp_max >= 0 and row.hp >= 0 and row.hp <= maxi(row.hp_max, row.hp), "%s hp sane" % label)
		var is_struct: bool = structs.has(id)
		t.eq(row.kind == UiEntityRow.K_STRUCTURE, is_struct, "%s kind matches mask for %d" % [label, id])
		t.eq((row.flags & UiEntityRow.F_STRUCT) != 0, is_struct, "%s F_STRUCT" % label)
		t.check(port.can_target(id), "%s own can_target" % label)
		t.check(row.order_kind >= 0 and row.order_kind <= UiEntityRow.O_OTHER, "%s order_kind range" % label)
		var again := UiEntityRow.new()
		port.read(id, again)
		t.check(again.x == row.x and again.y == row.y and again.hp == row.hp, "%s reads are pure" % label)
		var q: PackedInt32Array = PackedInt32Array()
		var n: int = port.order_queue(id, q)
		t.eq(q.size(), n * UiSimPort.OQ_STRIDE, "%s order_queue stride" % label)
	t.check(not port.alive(987654), "%s bogus not alive" % label)
	t.check(not port.read(987654, row), "%s bogus read false" % label)
	t.check(not port.can_target(987654), "%s bogus not targetable" % label)
	var idle: PackedInt32Array = PackedInt32Array()
	port.idle_units(idle)
	t.check(_ascending(idle), "%s idle ascending" % label)
	for id: int in idle:
		t.check(units.has(id), "%s idle unit is an own unit" % label)
	if not units.is_empty():
		port.read(units[0], row)
		var same: PackedInt32Array = PackedInt32Array()
		port.ids_of_def(UiSimPort.KIND_UNIT, row.def_idx, same)
		t.check(same.has(units[0]), "%s ids_of_def contains the unit" % label)
		t.check(_ascending(same), "%s ids_of_def ascending" % label)
		t.check(port.def_flags(UiSimPort.KIND_UNIT, row.def_idx) >= 0, "%s def_flags" % label)
		t.ge(port.range_max(units[0]), 0, "%s range_max" % label)
		t.ge(port.detect_radius(units[0]), 0, "%s detect_radius" % label)
	if not structs.is_empty():
		port.read(structs[0], row)
		t.check((port.def_flags(UiSimPort.KIND_STRUCTURE, row.def_idx) & UiSimPort.DF_STRUCTURE) != 0, "%s structure def flag" % label)
		t.ge(port.sell_value(structs[0]), 0, "%s sell_value" % label)


static func _snapshot(t: TestCtx, port: UiSimPort, label: String) -> void:
	var snap := UiEntitySnapshot.new()
	port.snapshot(snap)
	var own: PackedInt32Array = PackedInt32Array()
	port.own_ids(3, own)
	t.ge(snap.count, own.size(), "%s snapshot lists at least the own entities" % label)
	for id: int in own:
		t.check(snap.index_of(id) >= 0, "%s snapshot has own %d" % [label, id])
	for i: int in snap.count:
		t.check(snap.hp_pct[i] <= 100, "%s hp_pct" % label)
	var first: int = snap.count
	port.snapshot(snap)
	t.eq(snap.count, first, "%s snapshot clears before refilling" % label)


static func _economy(t: TestCtx, port: UiSimPort, label: String) -> void:
	t.ge(port.credits(), 0, "%s credits" % label)
	t.ge(port.power_supply(), 0, "%s supply" % label)
	t.ge(port.power_demand(), 0, "%s demand" % label)
	t.ge(port.harvested_total(), 0, "%s harvested" % label)
	t.ge(port.unit_count(), 0, "%s unit_count" % label)
	var cs := PackedInt32Array()
	port.construction_state(cs)
	t.eq(cs.size(), 7, "%s construction_state size" % label)
	t.check(cs[UiSimPort.CS_STATE] >= 0 and cs[UiSimPort.CS_STATE] <= UiSimPort.Construction.PAUSED, "%s construction state range" % label)
	t.check(cs[UiSimPort.CS_QSTATE] >= 0 and cs[UiSimPort.CS_QSTATE] <= UiSimPort.QueueState.SHUTDOWN, "%s construction qstate range" % label)
	t.check(cs[UiSimPort.CS_PROGRESS] >= 0 and cs[UiSimPort.CS_PROGRESS] <= 1000, "%s construction progress range" % label)
	var cq := PackedInt32Array()
	port.construction_queue(cq)
	for qk: int in range(1, 6):
		var prods := PackedInt32Array()
		port.producers(qk, prods)
		t.check(_ascending(prods), "%s producers ascending" % label)
		for p: int in prods:
			var q := PackedInt32Array()
			t.le(port.queue_of(p, q), 5, "%s queue length <= 5" % label)
			var info := PackedInt32Array()
			port.queue_info(p, info)
			t.eq(info.size(), 4, "%s queue_info size" % label)
			t.check(info[UiSimPort.QI_PROGRESS] >= 0 and info[UiSimPort.QI_PROGRESS] <= 1000, "%s queue progress range" % label)
	var rs := PackedInt32Array()
	port.research_state(rs)
	t.ge(rs.size(), 5, "%s research_state size" % label)
	t.eq(rs.size(), 5 + rs[4], "%s research_state queued count" % label)
	var centers := PackedInt32Array()
	t.eq(port.build_radius_centers(centers) * 2, centers.size(), "%s build radius centres pairs" % label)
	for fn: int in [port.check_build(0), port.check_research(0)]:
		t.check(fn >= 0 and fn <= UiSimPort.Rule.INSIDE, "%s rule in range" % label)
	var pl: int = port.check_place(0, 0, 0)
	t.check(pl == UiSimPort.Rule.OK or pl == UiSimPort.Rule.BAD_SITE or pl == UiSimPort.Rule.NOT_ALLOWED or pl == UiSimPort.Rule.NO_PREREQ, "%s check_place result" % label)
	t.check(port.place_reason() >= 0 and port.place_reason() <= 5, "%s place_reason range" % label)
	var sw: int = port.sw_status()
	t.check(sw >= 0 and sw <= UiSimPort.SwStatus.WARNING, "%s sw_status range" % label)
	t.check(port.sw_charge_permille() >= 0 and port.sw_charge_permille() <= 1000, "%s sw charge range" % label)
	var w := PackedInt32Array()
	t.eq(port.strategic_warnings(w) * UiSimPort.WARN_STRIDE, w.size(), "%s warnings stride" % label)
	t.eq(port.power_slot(-5), -1, "%s power_slot of a non-roster power" % label)


static func _map_and_events(t: TestCtx, port: UiSimPort, label: String) -> void:
	var v: int = port.visibility(0, 0)
	t.check(v >= UiSimPort.Vis.SHROUD and v <= UiSimPort.Vis.VISIBLE, "%s visibility range" % label)
	t.check(not port.passable(-1, 0, 0), "%s off-map impassable" % label)
	t.check(not port.passable(port.map_w(), 0, 0), "%s off-map impassable (x)" % label)
	t.ge(port.deposit_at(0, 0), 0, "%s deposit_at" % label)
	t.eq(port.deposit_at(-1, -1), 0, "%s deposit off-map" % label)
	var ev: PackedInt32Array = port.take_events()
	t.eq(ev.size() % UiEv.STRIDE, 0, "%s events are whole records" % label)
	t.eq(port.take_events().size(), 0, "%s events are taken once" % label)


static func _ascending(a: PackedInt32Array) -> bool:
	for i: int in range(1, a.size()):
		if a[i] <= a[i - 1]:
			return false
	return true
