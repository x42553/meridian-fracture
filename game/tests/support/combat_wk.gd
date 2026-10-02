class_name CombatWK
extends RefCounted
## Test helpers for weapons / projectiles / targeting (CB-03..05): a world on a PRIVATE copy of the small test data
## (rosters and weapon slots may be edited freely), both players on the vanilla roster (so both own U_TANK), mount and
## warhead editors, event collectors and a fake zone system.

const CELL: int = SimConfig.CELL
## Combat tests run without the abilities and vision stages (default fog: everything visible), so they stay independent
## of those domains while they are being built.
const ISOLATE: Dictionary = {"disable": ["SimAbilitySystem", "SimVisionSystem"]}


## 2 players (pid 0 human, pid 1 ai; teams 1 / 2; both roster vanilla), real combat system, test movers installed.
static func world(n_players: int = 2, seed_value: int = 4242, teams: PackedInt32Array = PackedInt32Array()) -> SimWorld:
	var d: GameData = DefTestKit.small_data()
	d._data_hash = SimTestKit.DATA_HASH
	var pl: Array = []
	for i: int in n_players:
		pl.append({"pid": i, "kind": "human" if i == 0 else "ai", "name": "P%d" % i, "roster": DefTestKit.R_VANILLA,
			"team": teams[i] if i < teams.size() else i + 1, "color": i, "start": i, "handicap": 100})
	var cfg: SimMatchConfig = SimMatchConfig.from_dict({"seed": seed_value, "map": {"id": "sim_test_kit"}, "rules": {}, "players": pl})
	var w: SimWorld = SimWorld.create(d, cfg, SimTestKit.make_map(), ISOLATE)
	return w


## Appends a weapon slot to a unit def (base + every roster clone) and recompiles the combat tables. Spawn afterwards.
static func add_weapon(w: SimWorld, unit_id: String, arch: int, damage: int, reload_mt: int, range_u: int, mount: int) -> void:
	var ui: int = w.data.unit_idx(unit_id)
	var defs: Array[DefUnit] = [w.data.units[ui]]
	for p: SimPlayer in w.players:
		if p.view != null and p.view.roster.has_unit(ui) and not defs.has(p.view.roster.unit(ui)):
			defs.append(p.view.roster.unit(ui))
	for u: DefUnit in defs:
		u.weapons.append(DefTestKit._slot(w.data, arch, damage, reload_mt, range_u, mount))
	w.combat.init_world(w)


static func unit(w: SimWorld, id: String, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_unit(w.data.unit_idx(id), owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2)


static func tank(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return unit(w, DefTestKit.U_TANK, owner, cx, cy)


static func rifle(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return unit(w, DefTestKit.U_RIFLEMAN, owner, cx, cy)


static func turret(w: SimWorld, owner: int, cx: int, cy: int) -> SimEntity:
	return w.spawn_structure(w.data.structure_idx(DefTestKit.S_TURRET), owner, cx * CELL + CELL / 2, cy * CELL + CELL / 2)


static func cd(w: SimWorld, e: SimEntity) -> SimCombatDef:
	return w.combat.def_for(w, e)


## Edits DefWeaponSlot fields of weapon `si` of a unit def in the base def and every roster clone.
static func slot_set(w: SimWorld, unit_id: String, si: int, vals: Dictionary) -> void:
	var ui: int = w.data.unit_idx(unit_id)
	var slots: Array[DefWeaponSlot] = [w.data.units[ui].weapons[si]]
	for p: SimPlayer in w.players:
		if p.view != null and p.view.roster.has_unit(ui):
			var s: DefWeaponSlot = p.view.roster.unit(ui).weapons[si]
			if not slots.has(s):
				slots.append(s)
	for s: DefWeaponSlot in slots:
		for k: String in vals:
			s.set(k, vals[k])
		if vals.has("reload_mt"):
			s.reload_ticks = maxi(1, Fp.ceil_div(int(vals["reload_mt"]), 1000))
	w.combat.invalidate_stats()


## Edits profile columns (SimWeaponProfile.PF_*) of mount `m` of the compiled def of `e`.
static func prof_set(w: SimWorld, e: SimEntity, m: int, vals: Dictionary) -> void:
	var c: SimCombatDef = cd(w, e)
	for col: int in vals:
		c.prof[m * SimWeaponProfile.PN + col] = int(vals[col])


## Edits mount table columns (SimCombatDef.MT_*).
static func mt_set(w: SimWorld, e: SimEntity, m: int, vals: Dictionary) -> void:
	var c: SimCombatDef = cd(w, e)
	for col: int in vals:
		c.mounts[m * SimCombatDef.MT + col] = int(vals[col])


static func wh_of(w: SimWorld, e: SimEntity, m: int) -> SimCombatWarhead:
	var c: SimCombatDef = cd(w, e)
	return SimProjectiles.warhead_of(w, e.owner, w.combat.warhead_ref(w, e, c, m))


## Hitscan mount (fixed-hit, no splash) on mount 0 of `e`'s def.
static func make_hitscan(w: SimWorld, e: SimEntity, damage: int, reload_ticks: int, range_u: int, unit_id: String = DefTestKit.U_TANK) -> void:
	slot_set(w, unit_id, 0, {"damage": damage, "reload_mt": reload_ticks * 1000, "range": range_u, "splash_radius": 0})
	prof_set(w, e, 0, {SimWeaponProfile.PF_KIND: SimCombatConsts.PK_HITSCAN, SimWeaponProfile.PF_ACC: 10000, SimWeaponProfile.PF_BURST: 1})
	var wh: SimCombatWarhead = wh_of(w, e, 0)
	wh.splash_r = 0
	wh.damage = damage


static func set_matrix_all(w: SimWorld, bp: int) -> void:
	for i: int in w.combat.matrix_bp.size():
		w.combat.matrix_bp[i] = bp


static func set_hp(e: SimEntity, hp: int) -> void:
	e.hp = hp
	e.hp_max = hp


## Steps `n` ticks.
static func run(w: SimWorld, n: int) -> void:
	for _i: int in n:
		w.step()


## Records of `type` collected so far (buffer is not cleared by steps).
static func evs(w: SimWorld, type: int) -> Array[PackedInt32Array]:
	return CombatKit.events(w, type)


static func dead(e: SimEntity) -> bool:
	return (e.flags & SimFlags.F_GONE) != 0


## Fake zone system: an intercepting bubble with `charges`; records calls (combat 5.7 semantics).
class FakeZones extends SimZoneSystem:
	var charges: int = 0
	var cx: int = 0
	var cy: int = 0
	var radius: int = 0
	var ordinary_calls: int = 0
	var packet_calls: int = 0

	func inside(px: int, py: int) -> bool:
		var dx: int = px - cx
		var dy: int = py - cy
		return dx * dx + dy * dy <= radius * radius

	func intercept_ordinary(_world: SimWorld, _team: int, x0: int, y0: int, x1: int, y1: int, sx: int, sy: int, _fl: int) -> int:
		ordinary_calls += 1
		if charges <= 0 or inside(sx, sy) or inside(x0, y0):
			return -1
		if inside(x1, y1) or SimProjectiles.swept_hit(x0, y0, x1, y1, cx, cy, radius, PackedInt32Array([0, 0])):
			charges -= 1
			return 77
		return -1

	func intercept_packet(_world: SimWorld, _team: int, px: int, py: int) -> int:
		packet_calls += 1
		if charges >= 8 and inside(px, py):
			charges -= 8
			return 5000
		return 0


## Fog that reports listed decoys as identified.
class DecoyFog extends SimFogApi:
	var identified: PackedInt32Array = PackedInt32Array()

	func decoy_identified(_pid: int, e: SimEntity) -> bool:
		return identified.has(e.id)


## Fog that hides the listed entity ids from everybody.
class HideFog extends SimFogApi:
	var hidden: PackedInt32Array = PackedInt32Array()

	func entity_visible(_pid: int, e: SimEntity) -> bool:
		return not hidden.has(e.id)
