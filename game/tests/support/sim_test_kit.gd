class_name SimTestKit
extends RefCounted
## Minimal kernel test kit (sim_core 3.9 subset): a world from the data domain's `DefTestKit.small_data()` and a
## flat 96x96 test map, spawn / submit / run helpers, the S-CORE-1 scenario, a double-run helper, and the
## hash-coverage reflection check. Domain scenario tests build on this; it never lives under `src/`.
##
## Cast: 2 rosters (alpha, vanilla) x 8 spawn slots of a 96x96 map. Structures have footprints registered
## (HQ 3x3, barracks / generator 2x2, factory 3x2 rotatable, refinery 3x3, turret 1x1); neutral kind 0 maps to the
## barracks def (2x2). Stage 8 is the `CombatStub` (wrecks for enemy kills, DEBUG mode 5) and T_MOVE / T_PATROL get
## the `MoveHandler` (speed 300) unless a world option turns them off.

const MAP_SIZE: int = 96
const MAP_HASH: int = 0x5678EF01
## Fixture spawn cells as [cx, cy] pairs (sim_core 7.1).
const SPAWNS_XY: PackedInt32Array = [20, 20, 70, 70, 20, 70, 70, 20, 45, 10, 45, 80, 10, 45, 80, 45]
const CELL: int = SimConfig.CELL
const SEED: int = 424242
## Pinned so the goldens do not follow every change of the data hasher / small_data() tables (sim_core 7.1).
const DATA_HASH: int = 0x1234ABCD

static var _data: GameData = null
static var _map_plain: MapData = null


## Wrecks for enemy kills, DEBUG mode 5 (= combat's "set hp of target to count"). Stand-in for the combat domain.
class CombatStub:
	extends SimCombatSystem
	var dying: PackedInt32Array = PackedInt32Array()  ## ids in on_dying order

	# The real SimCombatSystem allocates components and hashes state; this stand-in must stay inert so the kernel
	# goldens do not depend on the combat domain.
	func init_world(_world: SimWorld) -> void:
		pass

	func update(_world: SimWorld) -> void:
		pass

	func on_spawn(_world: SimWorld, _e: SimEntity) -> void:
		pass

	func on_remove(_world: SimWorld, _e: SimEntity, _reason: int) -> void:
		pass

	func on_owner_changed(_world: SimWorld, _e: SimEntity, _old_owner: int) -> void:
		pass

	func on_player_eliminated(_world: SimWorld, _pid: int) -> void:
		pass

	func cleanup(_world: SimWorld) -> void:
		pass

	func hash_state(_world: SimWorld, _buf: PackedInt32Array) -> void:
		pass

	func on_dying(world: SimWorld, e: SimEntity, cause: int, _killer_id: int, killer_pid: int) -> void:
		dying.append(e.id)
		if cause == SimWorld.Cause.DAMAGE and e.kind == SimEntity.Kind.UNIT:
			world.spawn_wreck(e, killer_pid >= 0 and killer_pid != e.owner, 50, 1200)

	func on_debug(world: SimWorld, _pid: int, mode: int, target: int, _def_idx: int, count: int, _x: int, _y: int) -> int:
		if mode != 5:
			return -1
		var t: SimEntity = world.get_entity(target)
		if t == null:
			return SimCommand.Err.NO_TARGET
		t.hp = clampi(count, 1, maxi(t.hp_max, 1))
		return SimCommand.Err.OK


## Speed-300 mover for T_MOVE / T_PATROL: snaps on arrival, else faces the target and steps.
class MoveHandler:
	extends SimOrderHandler
	const SPEED: int = 300

	func on_update(world: SimWorld, e: SimEntity, o: SimOrder) -> int:
		var dx: int = o.x - e.x
		var dy: int = o.y - e.y
		if dx * dx + dy * dy <= SPEED * SPEED:
			world.set_pos(e, o.x, o.y)
			return SimOrder.DONE
		e.facing = Fp.atan2(dy, dx)
		world.set_pos(e, e.x + Fp.step_x(e.facing, SPEED), e.y + Fp.step_y(e.facing, SPEED))
		return SimOrder.RUNNING


# ---- data / map / config ----
static func data() -> GameData:
	if _data == null:
		_data = DefTestKit.small_data()
		_data._data_hash = DATA_HASH  # the kit owns this private copy
	return _data


static func unit_def(id: String) -> int:
	return data().unit_idx(id)


static func structure_def(id: String) -> int:
	return data().structure_idx(id)


## Flat 96x96 map with 8 spawns; `neutral_records` (whole 8-int records) optional. Footprints registered.
static func make_map(neutral_records: PackedInt32Array = PackedInt32Array()) -> MapData:
	if neutral_records.is_empty() and _map_plain != null:
		return _map_plain
	var cells: PackedInt32Array = PackedInt32Array()
	for i: int in SPAWNS_XY.size() / 2:
		cells.append(SPAWNS_XY[i * 2 + 1] * MAP_SIZE + SPAWNS_XY[i * 2])
	var m: MapData = MapData.for_test(MAP_SIZE, MAP_SIZE, cells, neutral_records, MAP_HASH)
	var d: GameData = data()
	var S: int = SimEntity.Kind.STRUCTURE
	m.set_footprint(S, d.structure_idx(DefTestKit.S_HQ), MapFootprint.new(3, 3))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_BARRACKS), MapFootprint.new(2, 2))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_FACTORY), MapFootprint.new(3, 2, PackedByteArray(), true))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_GENERATOR), MapFootprint.new(2, 2))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_REFINERY), MapFootprint.new(3, 3))
	m.set_footprint(S, d.structure_idx(DefTestKit.S_TURRET), MapFootprint.new(1, 1))
	m.set_neutral_def(0, d.structure_idx(DefTestKit.S_BARRACKS))
	if neutral_records.is_empty():
		_map_plain = m
	return m


## `n` players (pid 0 human, the rest AI; rosters alpha / vanilla alternating; team i + 1 unless `teams` given;
## start slot = pid).
static func make_config(n: int = 2, seed_value: int = SEED, rules: Dictionary = {}, teams: PackedInt32Array = PackedInt32Array()) -> SimMatchConfig:
	var pl: Array = []
	for i: int in n:
		pl.append({
			"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i,
			"roster": DefTestKit.R_ALPHA if i % 2 == 0 else DefTestKit.R_VANILLA,
			"team": teams[i] if i < teams.size() else i + 1, "color": i, "start": i, "handicap": 100,
		})
	var r: Dictionary = rules.duplicate()
	if not r.has("fog"):
		r["fog"] = false  # the domain tests of economy / movement / combat assume everything is visible and explored
	return SimMatchConfig.from_dict({"seed": seed_value, "map": {"id": "sim_test_kit"}, "rules": r, "players": pl})


## Builds a world. `o` keys: players (2), seed (SEED), rules ({}), teams, neutrals (records), movers (true),
## combat_stub (true), real_movement (false: the MoveHandler stand-in disables the movement stage), opts ({} = SimWorld
## opts; `systems` entries are appended to the stand-in).
static func make_world(o: Dictionary = {}) -> SimWorld:
	var cfg: SimMatchConfig = make_config(int(o.get("players", 2)), int(o.get("seed", SEED)), o.get("rules", {}), o.get("teams", PackedInt32Array()))
	var opts: Dictionary = (o.get("opts", {}) as Dictionary).duplicate()
	if bool(o.get("combat_stub", true)):
		var sys: Array = (opts.get("systems", []) as Array).duplicate()
		sys.append(CombatStub.new())
		opts["systems"] = sys
	if bool(o.get("movers", true)) and not bool(o.get("real_movement", false)):
		# the speed-300 stand-in replaces the movement domain: keep the real stage 6 (and its components) out of it
		var dis: Array = []
		for n: Variant in opts.get("disable", []):
			dis.append(n)
		if not dis.has("SimMovementSystem"):
			dis.append("SimMovementSystem")
		opts["disable"] = dis
	var w: SimWorld = SimWorld.create(data(), cfg, make_map(o.get("neutrals", PackedInt32Array())), opts)
	if w != null and bool(o.get("movers", true)):
		install_movers(w)
	return w


static func install_movers(w: SimWorld) -> void:
	var mh: MoveHandler = MoveHandler.new()
	w.orders.register_handler(SimOrder.T_MOVE, mh)
	w.orders.register_handler(SimOrder.T_PATROL, mh)


# ---- helpers ----
static func spawn_unit_id(w: SimWorld, id: String, owner: int, x: int, y: int, paid: int = 0) -> SimEntity:
	return w.spawn_unit(unit_def(id), owner, x, y, 0, 0, paid, 0, SimEvent.SPAWN_PRODUCED)


static func spawn_rifle(w: SimWorld, owner: int, x: int, y: int, paid: int = 250) -> SimEntity:
	return spawn_unit_id(w, DefTestKit.U_RIFLEMAN, owner, x, y, paid)


static func spawn_tank(w: SimWorld, owner: int, x: int, y: int, paid: int = 850) -> SimEntity:
	return spawn_unit_id(w, DefTestKit.U_TANK, owner, x, y, paid)


## Pop-0 unit (exempt from the unit cap).
static func spawn_collector(w: SimWorld, owner: int, x: int, y: int) -> SimEntity:
	return spawn_unit_id(w, DefTestKit.U_COLLECTOR, owner, x, y, 0)


static func submit(w: SimWorld, pid: int, ints: PackedInt32Array) -> void:
	w.submit_raw(pid, ints)


static func ids_of(list: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for e: SimEntity in list:
		out.append(e.id)
	return out


## Runs `steps` steps; `script` (optional) = func(world, s) called before step number s + 1.
static func run_script(w: SimWorld, steps: int, script: Callable = Callable()) -> void:
	for s: int in steps:
		if script.is_valid():
			script.call(w, s)
		w.step()


## Runs the same build + script twice; identical chains, event digests, final checksums and dump_state texts.
## {ok, chain, events, final, dump}.
static func double_run(build: Callable, script: Callable, steps: int) -> Dictionary:
	var a: SimWorld = build.call()
	var b: SimWorld = build.call()
	run_script(a, steps, script)
	run_script(b, steps, script)
	var ok: bool = a.checksum_log == b.checksum_log and a.events.digest() == b.events.digest() \
		and a.checksum() == b.checksum() and a.dump_state() == b.dump_state()
	return {"ok": ok, "chain": a.checksum_log, "events": a.events.digest(), "final": a.checksum(), "dump": a.dump_state()}


# ---- S-CORE-1 (sim_core 10.3, on small_data): 2 players, 200 steps of orders / scuttle / kill / resign ----
## The kernel golden must not move whenever the abilities / vision / zones domains change their hashed state, so those
## stages stay stubs here (like CombatWK.ISOLATE for the combat tests); pass `isolate: false` in `extra` to run them.
static func s_core_1_world(extra: Dictionary = {}) -> SimWorld:
	var ex: Dictionary = extra.duplicate(true)
	if bool(ex.get("isolate", true)):
		var opts: Dictionary = (ex.get("opts", {}) as Dictionary).duplicate()
		var dis: Array = (opts.get("disable", []) as Array).duplicate()
		for n: String in ["SimAbilitySystem", "SimVisionSystem", "SimZoneSystem"]:
			if not dis.has(n):
				dis.append(n)
		opts["disable"] = dis
		ex["opts"] = opts
	var w: SimWorld = make_world(ex)
	for i: int in 5:
		spawn_rifle(w, 0, 21 * CELL + i * 700, 22 * CELL, 250)
	for i: int in 2:
		spawn_tank(w, 0, 24 * CELL, 20 * CELL + i * 1500, 850)
	for i: int in 3:
		spawn_rifle(w, 1, 69 * CELL + i * 700, 68 * CELL, 250)
	spawn_tank(w, 1, 66 * CELL, 70 * CELL, 850)
	return w


## Script action before step s + 1 (ids: HQs 1, 2; P0 rifles 3-7, tanks 8-9; P1 rifles 10-12, tank 13).
static func s_core_1_script(w: SimWorld, s: int) -> void:
	match s:
		2:
			w.submit_raw(0, SimCmd.move(PackedInt32Array([3, 4, 5, 6, 7, 8, 9]), 30 * CELL, 30 * CELL))
		5:
			w.submit_raw(1, SimCmd.move(PackedInt32Array([13]), 50 * CELL, 50 * CELL))
			w.submit_raw(1, SimCmd.move(PackedInt32Array([13]), 60 * CELL, 40 * CELL, SimOrder.QM_APPEND))
		8:
			w.submit_raw(0, SimCmd.scatter(PackedInt32Array([3, 4])))
		30:
			w.submit_raw(0, SimCmd.scuttle(PackedInt32Array([8])))
		40:
			w.submit_raw(1, SimCmd.scuttle(PackedInt32Array([9])))  # not P1's unit: rejected NO_ACTORS
		60:
			w.kill(w.get_entity(13), SimWorld.Cause.DAMAGE, 3, 0)
		100:
			w.submit_raw(1, SimCmd.resign(0))


# ---- brawl: 4-player sandbox (victory 0) with a seeded pseudo-random command stream; the soak of the xplat scenario ----
static func brawl_world() -> SimWorld:
	var w: SimWorld = make_world({"players": 4, "seed": 20240929, "rules": {"victory": 0}})
	for p: int in 4:
		var hq: SimEntity = w.get_entity(p + 1)
		for i: int in 10:
			spawn_rifle(w, p, hq.x + (i - 5) * 500, hq.y + 3000)
		for i: int in 6:
			spawn_tank(w, p, hq.x + (i - 3) * 900, hq.y - 3500)
	return w


## Every 10 ticks a random player orders a random subset of its units (move / patrol / scatter / stop /
## append); every 50 ticks a random unit is killed by damage. Deterministic: the only randomness is `rng`.
static func brawl_run(w: SimWorld, steps: int, seed_value: int = 777) -> void:
	var rng: SimRng = SimRng.new(seed_value)
	for s: int in steps:
		if s % 10 == 0:
			var pid: int = rng.next_int(4)
			var own: PackedInt32Array = w.own_ids(pid)
			var pick: PackedInt32Array = PackedInt32Array()
			for id: int in own:
				if w.get_entity(id).kind == SimEntity.Kind.UNIT and rng.next_int(3) != 0:
					pick.append(id)
			if not pick.is_empty():
				var x: int = rng.next_int(90 * CELL) + 3 * CELL
				var y: int = rng.next_int(90 * CELL) + 3 * CELL
				match rng.next_int(5):
					0:
						w.submit_raw(pid, SimCmd.move(pick, x, y))
					1:
						w.submit_raw(pid, SimCmd.patrol(pick, x, y, SimOrder.QM_APPEND, 1))
					2:
						w.submit_raw(pid, SimCmd.scatter(pick))
					3:
						w.submit_raw(pid, SimCmd.stop(pick))
					_:
						w.submit_raw(pid, SimCmd.move(pick, x, y, SimOrder.QM_APPEND, 2))
		if s % 50 == 25:
			var pid2: int = rng.next_int(4)
			var own2: PackedInt32Array = w.own_ids(pid2)
			if own2.size() > 1:
				var victim: SimEntity = w.get_entity(own2[1 + rng.next_int(own2.size() - 1)])
				w.kill(victim, SimWorld.Cause.DAMAGE, 0, (pid2 + 1) % 4)
		w.step()


# ---- reflection guard of DR-13 ----
## Perturbs every int / String script variable of a fresh `cls` instance and requires the digest of hash_into to
## change exactly for the non-exempt ones. Returns the problems (empty = ok).
static func check_hash_coverage(cls: GDScript, exempt: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var o: Object = cls.new()
	var buf: PackedInt32Array = PackedInt32Array()
	o.call("hash_into", buf)
	var base: int = Checksum.digest32(buf)
	for p: Dictionary in o.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p["name"]
		var v: Variant = o.get(n)
		if typeof(v) == TYPE_INT:
			o.set(n, (v as int) + 1)
		elif typeof(v) == TYPE_STRING:
			o.set(n, (v as String) + "x")
		else:
			continue
		buf = PackedInt32Array()
		o.call("hash_into", buf)
		var changed: bool = Checksum.digest32(buf) != base
		o.set(n, v)
		if changed and exempt.has(n):
			problems.append("%s is exempt but hashed" % n)
		elif not changed and not exempt.has(n):
			problems.append("%s is not hashed" % n)
	return problems
