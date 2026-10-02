extends RefCounted
## VQ2A: collector docking presentation on a REAL SimWorld. The sim glides a collector into the refinery's dock cell (inside the
## footprint) and back out; the view must make that readable: the hull turns around so the collector REVERSES into the bay (wheels roll
## backwards), sinks into the bay floor and is hidden while unloading, rises and drives out forwards, and never writes to the sim.

const Kit := preload("res://tests/view/w2_kit.gd")
const C: int = SimConfig.CELL


func _collector(w: SimWorld, cx: int, cy: int) -> SimEntity:
	var idx: int = w.data.unit_idx("unit.shared.collector")
	return w.spawn_unit(idx, 0, cx * C + C / 2, cy * C + C / 2, 1024, 0, 500)


## Puts the collector at the refinery's dock cell centre (what the sim glide does) and returns that point in sim units.
func _at_dock(w: SimWorld, r: SimEntity, c: SimEntity) -> void:
	var cell: int = w.economy.docks.dock_cell(w, r)
	c.x = w.map.center_x(cell)
	c.y = w.map.center_y(cell)


func _frames(vw: ViewWorld, n: int) -> void:
	for i: int in n:
		vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())


## Makes the view re-read the sim (a new tick number) without running any sim system, so the forced harvest states stay as set.
func _poke(vw: ViewWorld) -> void:
	vw.sim.tick += 1
	vw.frame(1.0 / 60.0, 1.0, PackedInt32Array())


func test_collector_reverses_into_the_bay_sinks_while_unloading_and_re_emerges(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var r: SimEntity = Kit.place(w, "structure.shared.refinery", 0, 40, 40)
	var c: SimEntity = _collector(w, 40, 47)
	Kit.tick(vw, 4)
	var cv: ViewUnit = vw.entity_view(c.id) as ViewUnit
	t.check(cv != null, "the collector has a view record")
	if cv == null:
		Kit.free_view(vw)
		return
	t.check(cv.vdef.cargo_cap > 0, "recognised as a collector")
	t.near(cv.dock_flip, 0.0, 0.001, "free driving: not flipped")
	t.near(cv.dock_sink, 0.0, 0.001, "free driving: not sunk")
	# the sim enters the dock-in phase and moves the collector to the dock cell
	c.econ.h_refinery = r.id
	c.econ.h_state = SimEconConst.H_DOCK_IN
	r.econ.dock_occupant = c.id
	_at_dock(w, r, c)
	_poke(vw)
	_frames(vw, 60)
	t.gt(cv.dock_flip, 0.99, "the hull has turned around to reverse in (%.2f)" % cv.dock_flip)
	t.near(cv.roll_dir, -1.0, 0.001, "the wheels roll backwards while reversing in")
	t.gt(cv.dock_sink, 0.9, "at the dock cell the collector is sunk into the bay floor (%.2f)" % cv.dock_sink)
	# unloading: stays hidden
	c.econ.h_state = SimEconConst.H_UNLOAD
	_poke(vw)
	_frames(vw, 30)
	t.near(cv.dock_sink, 1.0, 0.01, "hidden while unloading")
	t.near(cv.sink_m, cv.height_m + 0.4, 0.05, "the instance sink depth covers the whole hull")
	# dock out: rises and drives out forwards
	c.econ.h_state = SimEconConst.H_DOCK_OUT
	r.econ.dock_occupant = 0
	_poke(vw)
	_frames(vw, 6)
	t.near(cv.dock_flip, 0.0, 0.01, "driving out: the sim heading already points away from the bay")
	t.near(cv.roll_dir, 1.0, 0.001, "driving out forwards")
	_frames(vw, 60)
	t.lt(cv.dock_sink, 0.05, "re-emerged after %.2f" % cv.dock_sink)
	# back to harvesting: nothing left over
	c.econ.h_state = SimEconConst.H_SEEK
	c.econ.h_refinery = 0
	_poke(vw)
	_frames(vw, 60)
	t.near(cv.dock_sink, 0.0, 0.001, "normal driving again")
	t.near(cv.dock_flip, 0.0, 0.001, "normal heading again")
	Kit.free_view(vw)


func test_docking_never_writes_the_sim(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var r: SimEntity = Kit.place(w, "structure.shared.refinery", 0, 40, 40)
	var c: SimEntity = _collector(w, 40, 47)
	Kit.tick(vw, 4)
	c.econ.h_refinery = r.id
	c.econ.h_state = SimEconConst.H_UNLOAD
	r.econ.dock_occupant = c.id
	_at_dock(w, r, c)
	var before: int = w.state_hash() if w.has_method("state_hash") else 0
	var x: int = c.x
	var f: int = c.facing
	_frames(vw, 90)
	t.eq(c.x, x, "position untouched")
	t.eq(c.facing, f, "heading untouched")
	t.eq(c.econ.h_state, SimEconConst.H_UNLOAD, "harvest state untouched")
	if w.has_method("state_hash"):
		t.eq(w.state_hash(), before, "state hash untouched")
	Kit.free_view(vw)


func test_non_collectors_never_flip_or_sink(t: TestCtx) -> void:
	var w: SimWorld = Kit.sim(2)
	var vw: ViewWorld = Kit.view(w)
	var tank: SimEntity = Kit.unit(w, 0, false, 30, 30)
	Kit.tick(vw, 4)
	var uv: ViewUnit = vw.entity_view(tank.id) as ViewUnit
	_frames(vw, 30)
	t.check(uv != null, "tank record")
	if uv != null:
		t.near(uv.dock_flip, 0.0, 0.0001, "no flip")
		t.near(uv.dock_sink, 0.0, 0.0001, "no sink")
	Kit.free_view(vw)
