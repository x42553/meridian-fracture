extends RefCounted
## CB-06 / CB-07 end-to-end: two small armies (infantry + tanks) fight to the death through REAL commands and the real
## SimCombatSystem (real movement, orders, targeting, weapons, damage, death), deterministic double run.

const C: int = SimConfig.CELL


func _army(w: SimWorld, pid: int, cx: int, cy: int) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in 3:
		ids.append(CombatWK.rifle(w, pid, cx, cy + i * 2).id)
	for i: int in 2:
		ids.append(CombatWK.tank(w, pid, cx + (2 if pid == 0 else -2), cy + 1 + i * 3).id)
	return ids


func _alive(w: SimWorld, ids: PackedInt32Array) -> int:
	var n: int = 0
	for id: int in ids:
		if w.is_alive(id):
			n += 1
	return n


## Bot: every 40 ticks each side sends its idle units (attack-move) at the nearest enemy unit.
func _bot(w: SimWorld, mine: PackedInt32Array, theirs: PackedInt32Array, pid: int) -> void:
	var idle: PackedInt32Array = PackedInt32Array()
	for id: int in mine:
		var e: SimEntity = w.get_entity(id)
		if e != null and (e.flags & SimFlags.F_GONE) == 0 and e.orders.is_empty():
			idle.append(id)
	if idle.is_empty():
		return
	var lead: SimEntity = w.get_entity(idle[0])
	var best: SimEntity = null
	var best_d: int = 0
	for id: int in theirs:
		var t2: SimEntity = w.get_entity(id)
		if t2 == null or (t2.flags & SimFlags.F_GONE) != 0:
			continue
		var d: int = Fp.dist(t2.x - lead.x, t2.y - lead.y)
		if best == null or d < best_d:
			best = t2
			best_d = d
	if best != null:
		w.submit_raw(pid, SimCmd.attack_move(idle, best.x, best.y))


## Runs the battle; returns [checksum log, survivors of A, survivors of B, tick of the end].
func _battle() -> Array:
	var w: SimWorld = CombatWK.world(2, 777)
	var a: PackedInt32Array = _army(w, 0, 30, 40)
	var b: PackedInt32Array = _army(w, 1, 52, 40)
	w.submit_raw(0, SimCmd.attack_move(a, 52 * C, 42 * C))
	w.submit_raw(1, SimCmd.attack_move(b, 30 * C, 42 * C))
	var end: int = -1
	for i: int in 6000:
		w.step()
		if i % 40 == 39:
			_bot(w, a, b, 0)
			_bot(w, b, a, 1)
		if _alive(w, a) == 0 or _alive(w, b) == 0:
			end = w.tick
			break
	return [w.checksum_log, _alive(w, a), _alive(w, b), end, w.checksum(), w.events.digest(), w.combat.verify_indexes(w)]


func test_two_armies_fight_to_the_death(t: TestCtx) -> void:
	var r: Array = _battle()
	t.gt(int(r[3]), 0, "the battle ended inside 6000 ticks")
	t.check((int(r[1]) == 0) != (int(r[2]) == 0), "exactly one side was wiped out (A %d, B %d)" % [r[1], r[2]])
	t.eq(r[6], PackedStringArray(), "combat id lists consistent at the end")


func test_two_armies_deterministic_double_run(t: TestCtx) -> void:
	var r1: Array = _battle()
	var r2: Array = _battle()
	t.eq(r1[0], r2[0], "identical checkpoint chain")
	t.eq(r1[4], r2[4], "identical final checksum")
	t.eq(r1[5], r2[5], "identical event digest")
	t.eq([r1[1], r1[2], r1[3]], [r2[1], r2[2], r2[3]], "same survivors and end tick")
