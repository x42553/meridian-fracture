class_name AiOpKit
extends RefCounted
## Small shared helpers of the AIX1 ops (engineer pool, snapping to passable ground, cell conversions). Stateless statics.


## Nearest idle Engineer (role ENGINEER, not borrowed by another op) to (x, y) that stands on the map; -1 when none. Marks it as
## borrowed by `op_id`.
static func claim_engineer(ctx: AiContext, b: AiBrain, op_id: int, x: int, y: int) -> int:
	var t: AiEntityTable = ctx.kb.own
	var bit: int = 1 << AiTypes.R_ENGINEER
	var best: int = -1
	var best_d: int = 1 << 60
	for r: int in t.count:
		if t.kind[r] != AiTypes.KIND_UNIT or (t.role_mask[r] & bit) == 0 or (t.flags[r] & AiTypes.EF_LOADED) != 0:
			continue
		if b.eng_claim.has(t.eid[r]):
			continue
		var d: int = AiForce.dist(t.x[r], t.y[r], x, y)
		if d < best_d or (d == best_d and t.eid[r] < best):
			best_d = d
			best = t.eid[r]
	if best >= 0:
		b.eng_claim[best] = op_id
	return best


static func release_engineers(b: AiBrain, op_id: int) -> void:
	for eid: int in b.eng_claim.keys():
		if int(b.eng_claim[eid]) == op_id:
			b.eng_claim.erase(eid)


## Number of borrowed / idle engineers alive.
static func engineer_count(ctx: AiContext) -> int:
	var t: AiEntityTable = ctx.kb.own
	var n: int = 0
	var bit: int = 1 << AiTypes.R_ENGINEER
	for r: int in t.count:
		if t.kind[r] == AiTypes.KIND_UNIT and (t.role_mask[r] & bit) != 0:
			n += 1
	return n


## Nearest passable cell (for move class `mc`) around the sub-cell point, as a sub-cell point at the cell centre; the input when
## nothing within `radius` cells is passable.
static func snap(ctx: AiContext, x: int, y: int, mc: int, radius: int = 5) -> PackedInt32Array:
	var v: AiWorldView = ctx.view
	var cx: int = clampi(x >> Fp.CELL_SHIFT, 1, v.map_w() - 2)
	var cy: int = clampi(y >> Fp.CELL_SHIFT, 1, v.map_h() - 2)
	for ring: int in radius + 1:
		for oy: int in range(-ring, ring + 1):
			for ox: int in range(-ring, ring + 1):
				if maxi(absi(ox), absi(oy)) == ring and v.passable(cx + ox, cy + oy, mc):
					return PackedInt32Array([(cx + ox) * Fp.CELL + Fp.CELL / 2, (cy + oy) * Fp.CELL + Fp.CELL / 2])
	return PackedInt32Array([x, y])


## Frees the units of `squad` that are not combat units (Engineers, MCVs, Landing Transports) so that releasing the squad does not
## put them into the reserve, where the wave planner would send them to the front.
static func detach_support(ctx: AiContext, sq: AiSquad) -> void:
	var t: AiEntityTable = ctx.kb.own
	var bit: int = 1 << AiTypes.R_COMBAT
	var i: int = sq.units.size() - 1
	while i >= 0:
		var eid: int = sq.units[i]
		var r: int = t.row(eid)
		if r >= 0 and (t.role_mask[r] & bit) == 0:
			t.squad[r] = -1
			sq.units.remove_at(i)
		i -= 1
