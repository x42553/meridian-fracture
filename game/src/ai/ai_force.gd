class_name AiForce
extends RefCounted
## Stateless strength and geometry helpers shared by the strategy modules and the ops (ai.md 5.3.4 / 5.8.1). Everything is
## integer maths over the knowledge base; nothing here reads the sim.

const AIR_MOVE: int = AiTypes.MoveClass.AIR
const AIR_HOVER: int = 7  ## DefEnums.MoveClass.AIR_HOVER: helicopters / gunships


## True for the structure kinds that shoot (their ghosts join the defender group of a target).
static func is_defense_kind(k: int) -> bool:
	return k == AiTypes.StructKind.WATCHTOWER or k == AiTypes.StructKind.AT_TURRET or k == AiTypes.StructKind.AA_BATTERY \
		or k == AiTypes.StructKind.ADV_DEFENSE


static func is_air(ctx: AiContext, def_idx: int) -> bool:
	var p: AiUnitProfile = ctx.unit_profile(def_idx)
	return p != null and (p.move_class == AIR_MOVE or p.move_class == AIR_HOVER)


static func is_sea(ctx: AiContext, def_idx: int) -> bool:
	var p: AiUnitProfile = ctx.unit_profile(def_idx)
	return p != null and (p.move_class == AiTypes.MoveClass.NAVAL or p.move_class == AiTypes.MoveClass.SUBMERGED)


## Strength group of own units (current hp; credit value = paid cost x hp fraction).
static func own_group(ctx: AiContext, eids: PackedInt32Array) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	var t: AiEntityTable = ctx.kb.own
	for eid: int in eids:
		var r: int = t.row(eid)
		if r < 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p == null:
			continue
		g.add(p, 1, t.hp[r], t.paid[r] * t.hp[r] / maxi(t.hp_max[r], 1))
	return g


## Own defensive structures within `r` of (x, y) (they add to my side of a defense ratio).
static func own_defenses_group(ctx: AiContext, x: int, y: int, r: int) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	var t: AiEntityTable = ctx.kb.own
	var r2: int = r * r
	for i: int in t.count:
		if t.kind[i] != AiTypes.KIND_STRUCTURE or (t.flags[i] & (AiTypes.EF_UNDER_CONSTRUCTION | AiTypes.EF_UNPOWERED)) != 0:
			continue
		var dx: int = t.x[i] - x
		var dy: int = t.y[i] - y
		if dx * dx + dy * dy > r2 or not is_defense_kind(ctx.res.kind_of_structure(t.def[i])):
			continue
		var p: AiUnitProfile = ctx.struct_profile(t.def[i])
		if p != null and p.is_combat():
			g.add(p, 1, t.hp[i], p.value * t.hp[i] / maxi(t.hp_max[i], 1))
	return g


## Rows of kb.enemy_units within `r` of (x, y) that are armed, not decoys and seen within `fresh` ticks (unordered).
static func armed_enemy_rows(ctx: AiContext, x: int, y: int, r: int, fresh: int, out: PackedInt32Array) -> int:
	out.resize(0)
	var t: AiEntityTable = ctx.kb.enemy_units
	var r2: int = r * r
	var now: int = ctx.tick
	for i: int in t.count:
		var dx: int = t.x[i] - x
		if dx > r or dx < -r:
			continue
		var dy: int = t.y[i] - y
		if dx * dx + dy * dy > r2 or now - t.last_seen[i] > fresh or (t.flags[i] & AiTypes.EF_DECOY) != 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(t.owner[i], t.def[i])
		if p != null and p.is_combat():
			out.append(i)
	return out.size()


## Defender group at (x, y): armed enemy units within `r` seen within `fresh` ticks + defensive structure ghosts that cover the point (within their own weapon range + 3 cells, and within `r`).
static func enemy_group(ctx: AiContext, x: int, y: int, r: int, fresh: int) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	var t: AiEntityTable = ctx.kb.enemy_units
	var rows: PackedInt32Array = PackedInt32Array()
	armed_enemy_rows(ctx, x, y, r, fresh, rows)
	for i: int in rows:
		var p: AiUnitProfile = ctx.unit_profile_of(t.owner[i], t.def[i])
		g.add(p, 1, t.hp[i], p.value * t.hp[i] / maxi(t.hp_max[i], 1))
	var gt: AiGhostTable = ctx.kb.ghosts
	for j: int in gt.count:
		if not is_defense_kind(gt.kind[j]) or gt.owner[j] < 0:
			continue
		var dx: int = gt.x[j] - x
		var dy: int = gt.y[j] - y
		var d2: int = dx * dx + dy * dy
		if d2 > r * r:
			continue
		var sp: AiUnitProfile = ctx.struct_profile_of(gt.owner[j], gt.def[j])
		if sp == null or not sp.is_combat():
			continue
		# a defensive structure only fights what is inside its own range (+ 3 cells of slack)
		var reach: int = sp.range + 3 * Fp.CELL
		if d2 <= reach * reach:
			g.add_pct(sp, sp.hp * maxi(gt.hp_pct[j], 1) / 100, sp.value, ctx.tune("strength.static_mult_pct", 100))
	return g


## Adds the armed enemy units seen within `fresh` ticks in the ring r_in .. r_out around (x, y) to `g`, each weighted `pct` percent: the
## reinforcements of a defended point (AIT: they were not counted at all unless the point was in their reach).
static func add_ring(ctx: AiContext, g: AiStrengthGroup, x: int, y: int, r_in: int, r_out: int, fresh: int, pct: int) -> void:
	var t: AiEntityTable = ctx.kb.enemy_units
	var in2: int = r_in * r_in
	var out2: int = r_out * r_out
	var now: int = ctx.tick
	for i: int in t.count:
		var dx: int = t.x[i] - x
		var dy: int = t.y[i] - y
		var d2: int = dx * dx + dy * dy
		if d2 <= in2 or d2 > out2 or now - t.last_seen[i] > fresh or (t.flags[i] & AiTypes.EF_DECOY) != 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile_of(t.owner[i], t.def[i])
		if p != null and p.is_combat():
			g.add_pct(p, t.hp[i], p.value * t.hp[i] / maxi(t.hp_max[i], 1), pct)


## The defensive-structure ghosts alone of enemy_group (same reach rule): the part of a defender group that artillery can shell.
static func static_defense_group(ctx: AiContext, x: int, y: int, r: int) -> AiStrengthGroup:
	var g: AiStrengthGroup = AiStrengthGroup.new()
	var gt: AiGhostTable = ctx.kb.ghosts
	for j: int in gt.count:
		if not is_defense_kind(gt.kind[j]) or gt.owner[j] < 0 or gt.kind[j] == AiTypes.StructKind.AA_BATTERY:
			continue
		var dx: int = gt.x[j] - x
		var dy: int = gt.y[j] - y
		var d2: int = dx * dx + dy * dy
		if d2 > r * r:
			continue
		var sp: AiUnitProfile = ctx.struct_profile_of(gt.owner[j], gt.def[j])
		if sp == null or not sp.is_combat():
			continue
		var reach: int = sp.range + 3 * Fp.CELL
		if d2 <= reach * reach:
			g.add(sp, 1, sp.hp * maxi(gt.hp_pct[j], 1) / 100, sp.value)
	return g


## Adds an assumed reserve worth `value` credits of the enemy's main battle unit (stale information, ai.md 5.3.4).
static func add_reserve(ctx: AiContext, g: AiStrengthGroup, enemy_pid: int, value: int) -> void:
	if value <= 0 or enemy_pid < 0:
		return
	var ridx: int = ctx.view.roster_of(enemy_pid)
	var rr: AiRoleResolver = ctx.shared.resolver(ridx)
	var def_idx: int = rr.first(AiTypes.R_TANK_MAIN)
	if def_idx < 0:
		def_idx = rr.first(AiTypes.R_INFANTRY_BASIC)
	if def_idx < 0:
		return
	var p: AiUnitProfile = ctx.shared.unit_profile(ridx, def_idx)
	if p != null and p.cost > 0:
		g.add(p, maxi(1, value / p.cost))


## Adds an unseen defender of the given threat `power` (hp x dps scale of AiUnitProfile.power) as copies of the enemy's main battle unit.
static func add_power(ctx: AiContext, g: AiStrengthGroup, enemy_pid: int, power: int) -> void:
	if power <= 0 or enemy_pid < 0:
		return
	var ridx: int = ctx.view.roster_of(enemy_pid)
	var rr: AiRoleResolver = ctx.shared.resolver(ridx)
	var def_idx: int = rr.first(AiTypes.R_TANK_MAIN)
	if def_idx < 0:
		def_idx = rr.first(AiTypes.R_INFANTRY_BASIC)
	if def_idx < 0:
		return
	var p: AiUnitProfile = ctx.shared.unit_profile(ridx, def_idx)
	if p != null and p.power > 0:
		g.add(p, maxi(1, power / p.power))


## Q8 strength ratio attacker / defender with the home advantage and the epoch-stable estimate noise of the difficulty.
static func ratio(ctx: AiContext, att: AiStrengthGroup, dfn: AiStrengthGroup, noise_key: int) -> int:
	var noise: int = AiStrength.noise_q8(ctx.tick, noise_key, ctx.diff.est_noise_pct, ctx.tune("strength.noise_epoch_ticks", 200))
	return AiStrength.ratio_q8(att, dfn, ctx.tune("strength.home_adv_pct", 10), noise)


## Sum of the unit profile powers (hp x dps) - the scale the threat map is written in.
static func power_of(ctx: AiContext, eids: PackedInt32Array) -> int:
	var t: AiEntityTable = ctx.kb.own
	var s: int = 0
	for eid: int in eids:
		var r: int = t.row(eid)
		if r < 0:
			continue
		var p: AiUnitProfile = ctx.unit_profile(t.def[r])
		if p != null:
			s += p.power * t.hp[r] / maxi(t.hp_max[r], 1)
	return s


## Octile distance in cells between two sub-cell points.
static func cells(ax: int, ay: int, bx: int, by: int) -> int:
	var dx: int = absi(ax - bx)
	var dy: int = absi(ay - by)
	return (maxi(dx, dy) + mini(dx, dy) * 4 / 10) / Fp.CELL


## Euclidean distance in sub-cell units.
static func dist(ax: int, ay: int, bx: int, by: int) -> int:
	return Fp.dist(ax - bx, ay - by)


## Nearest enemy player start cell to (x, y) as sub-cells; false when there is none.
static func nearest_enemy_start(ctx: AiContext, x: int, y: int, out: PackedInt32Array) -> bool:
	var es: PackedInt32Array = ctx.kb.enemy_starts
	var best: int = -1
	var best_d: int = 1 << 60
	for i: int in es.size() / 2:
		var sx: int = es[2 * i] * Fp.CELL + Fp.CELL / 2
		var sy: int = es[2 * i + 1] * Fp.CELL + Fp.CELL / 2
		var d: int = (sx - x) * (sx - x) + (sy - y) * (sy - y)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	out.resize(2)
	out[0] = es[2 * best] * Fp.CELL + Fp.CELL / 2
	out[1] = es[2 * best + 1] * Fp.CELL + Fp.CELL / 2
	return true
