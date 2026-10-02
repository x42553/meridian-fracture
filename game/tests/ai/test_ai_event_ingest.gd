extends RefCounted
## AiEventIngest on a scripted world (ai.md 5.3.2): derived records, tables, reaction delay, unseen hits.

const C: int = Fp.CELL

var _v: AiMockWorldView = null
var _ctx: AiContext = null
var _ing: AiEventIngest = null
var _rifle: int = 0
var _tank: int = 0
var _barracks: int = 0


func _boot() -> void:
	_v = AiMockWorldView.new(0)
	_v.add_player(0, "roster.napc.vanilla", Vector2i(15, 15))
	_v.add_player(1, "roster.nec.vanilla", Vector2i(80, 80))
	var d: GameData = _v.game_data()
	_rifle = d.unit_idx("unit.napc.rifle_squad")
	_tank = d.unit_idx("unit.nec.leopard_tank")
	_barracks = d.structure_idx("structure.shared.barracks")
	_v.add_entity(1, 0, AiTypes.KIND_STRUCTURE, d.structure_idx("structure.shared.headquarters"), 15 * C, 15 * C, 5000, 5000)
	_v.add_entity(2, 0, AiTypes.KIND_UNIT, _rifle, 17 * C, 15 * C, 100, 100, 0, 0, 100)
	_v.add_entity(3, 0, AiTypes.KIND_UNIT, _rifle, 18 * C, 15 * C, 100, 100, 0, 0, 100)
	_ctx = AiMockWorldView.make_ctx(_v)
	_ing = AiEventIngest.new()
	_ing.setup(_ctx)


func _step(tick: int, dt: int = 10) -> Array[PackedInt32Array]:
	_v.mock_tick = tick
	_ctx.tick = tick
	_ctx.dt = dt
	var b: AiBudget = AiBudget.new()
	b.reset(100000, 100000)
	_ing.step(_ctx, b)
	return _ctx.kb.events


func _codes(ev: Array[PackedInt32Array]) -> Array:
	var out: Array = []
	for r: PackedInt32Array in ev:
		out.append(r[0])
	return out


func test_priming_is_silent_and_spawn_loss_are_state_records(t: TestCtx) -> void:
	_boot()
	t.eq(_ctx.kb.own.count, 3, "primed rows")
	t.eq(_step(10).size(), 0, "no events on a quiet world")
	_v.add_entity(4, 0, AiTypes.KIND_UNIT, _rifle, 19 * C, 15 * C, 100, 100, 0, 0, 100)
	var ev: Array[PackedInt32Array] = _step(20)
	t.eq(_codes(ev), [AiTypes.Ev.OWN_SPAWNED] as Array)
	t.eq(ev[0][1], 4)
	t.eq(ev[0][5], 100, "paid cost carried")
	_v.remove_entity(2)
	ev = _step(30)
	t.eq(_codes(ev), [AiTypes.Ev.OWN_LOST] as Array)
	t.eq(_ctx.kb.own.count, 3)
	t.check_false(_ctx.kb.own.has(2))
	t.check(_ctx.kb.own.role_mask[_ctx.kb.own.row(3)] != 0, "role mask cached from the profile")


func test_enemy_sighting_threat_profile_and_reaction_delay(t: TestCtx) -> void:
	_boot()
	_v.add_entity(50, 1, AiTypes.KIND_UNIT, _tank, 40 * C, 40 * C, 900, 900, 0, 0, 0)
	var ev: Array[PackedInt32Array] = _step(100)
	t.eq(_ctx.kb.enemy_units.count, 1)
	var r: int = _ctx.kb.enemy_units.row(50)
	t.gt(_ctx.kb.enemy_units.paid[r], 0, "value = unit cost of the enemy roster")
	t.gt(_ctx.kb.threat_at(40 * C, 40 * C), 0, "threat map written")
	t.eq(_ctx.kb.threat_at(10 * C, 10 * C), 0)
	t.gt(_ctx.kb.profiles[1].seen_value[AiTypes.Cat.ARMOR], 0, "composition profile fed")
	t.eq(_ctx.kb.profiles[1].first_seen_tick[AiTypes.Cat.ARMOR], 100)
	t.check_false(_codes(ev).has(AiTypes.Ev.ENEMY_SEEN), "alerts wait for the reaction delay (Hard 12 ticks)")
	ev = _step(105, 5)
	t.check_false(_codes(ev).has(AiTypes.Ev.ENEMY_SEEN))
	ev = _step(112, 7)
	t.check(_codes(ev).has(AiTypes.Ev.ENEMY_SEEN), "delivered at the first think at or after tick + delay")
	ev = _step(122)
	t.check_false(_codes(ev).has(AiTypes.Ev.ENEMY_SEEN), "delivered once")


func test_enemy_gone_when_the_cell_is_visible(t: TestCtx) -> void:
	_boot()
	_v.add_entity(50, 1, AiTypes.KIND_UNIT, _tank, 40 * C, 40 * C, 900, 900)
	_step(100)
	_v.remove_entity(50)
	_step(110)
	var ev: Array[PackedInt32Array] = _step(125)
	t.check(_codes(ev).has(AiTypes.Ev.ENEMY_GONE), "absent + cell visible => presumed dead")
	t.eq(_ctx.kb.enemy_units.count, 0)
	# out of sight: the row is kept until it is stale
	_v.add_entity(51, 1, AiTypes.KIND_UNIT, _tank, 60 * C, 60 * C, 900, 900)
	_step(200)
	_v.hidden[51] = true
	_v.visible_fn = func(_cx: int, _cy: int) -> bool: return false
	_step(210)
	t.eq(_ctx.kb.enemy_units.count, 1, "out of sight but not stale")
	_step(320)
	t.eq(_ctx.kb.enemy_units.count, 0, "unit rows unseen for 100 ticks are dropped")


func test_structure_ghosts_and_presumed_hq(t: TestCtx) -> void:
	_boot()
	var d: GameData = _v.game_data()
	t.check(_ctx.kb.ghosts.has(-2), "presumed HQ seeded for the enemy start")
	var hq_def: int = d.structure_idx("structure.shared.headquarters")
	_v.add_entity(60, 1, AiTypes.KIND_STRUCTURE, hq_def, 81 * C, 80 * C, 4000, 5000)
	var fact: int = d.structure_idx("structure.shared.factory")
	_v.add_entity(61, 1, AiTypes.KIND_STRUCTURE, fact, 70 * C, 76 * C, 1000, 2000)
	_step(50)
	var g: AiGhostTable = _ctx.kb.ghosts
	t.check_false(g.has(-2), "replaced by the real HQ")
	t.eq(g.kind[g.row(60)], AiTypes.StructKind.HQ)
	t.eq(g.kind[g.row(61)], AiTypes.StructKind.FACTORY)
	t.eq(g.hp_pct[g.row(61)], 50)
	t.gt(g.value[g.row(61)], 0)
	# the structure is destroyed while its cell is visible: the KB upkeep removes the ghost
	_v.remove_entity(61)
	_step(60)
	var b: AiBudget = AiBudget.new()
	b.reset(100000, 100000)
	_ctx.tick = 70
	_v.mock_tick = 70
	_ctx.kb.step(_ctx, b)
	t.check_false(g.has(61), "ghost validation removes destroyed structures")
	t.check(g.has(60))


func test_damage_alerts_unseen_hits_and_camo_alert(t: TestCtx) -> void:
	_boot()
	_step(10)
	# damage with an enemy in sight => OWN_DAMAGED + hostile mark, no unseen hit
	_v.add_entity(70, 1, AiTypes.KIND_UNIT, _tank, 22 * C, 15 * C, 900, 900)
	_v.set_hp(2, 60)
	_step(20)
	var ev: Array[PackedInt32Array] = _step(35)
	t.check(_codes(ev).has(AiTypes.Ev.OWN_DAMAGED))
	t.check_false(_codes(ev).has(AiTypes.Ev.UNSEEN_HIT))
	t.eq(_ctx.kb.attacked_by_tick[1], 20, "hostile mark of the enemy owner")
	# hidden attacker: three unseen hits within 6 cells => camo alert
	_v.remove_entity(70)
	_step(40)
	var seen: Array = []
	var tick: int = 50
	for hp: int in [50, 40, 30]:
		_v.set_hp(3, hp)
		tick += 10
		seen.append_array(_codes(_step(tick)))
	seen.append_array(_codes(_step(tick + 30, 30)))
	t.gt(seen.count(AiTypes.Ev.UNSEEN_HIT), 1, "unseen hits derived from hp loss without enemies in range")
	t.check(seen.has(AiTypes.Ev.CAMO_ALERT), "three within a 6 cell radius raise the camouflage alert")
	var alert: PackedInt32Array = PackedInt32Array()
	t.check(_ctx.kb.camo_alert(alert))
	t.eq(alert[0], 18 * C)


func test_polls_power_income_research_construction(t: TestCtx) -> void:
	_boot()
	_step(10)
	_v.mock_demand = 300
	_v.mock_income_total = 500
	_v.mock_research_active = 4
	var all: Array = _codes(_step(30))
	var ev: Array[PackedInt32Array] = _step(50)
	all.append_array(_codes(ev))
	t.eq(_ctx.kb.income_ema_q8 > 0, true, "income EMA moved")
	_v.mock_research_active = -1
	_v.mock_research_done[4] = true
	_v.mock_cstate = PackedInt32Array([2, 5, 100, 5])
	ev = _step(60)
	all.append_array(_codes(ev))
	t.check(all.has(AiTypes.Ev.POWER_STATE), "shortage flip")
	t.check(all.has(AiTypes.Ev.RESEARCH_DONE))
	t.check(all.has(AiTypes.Ev.CONSTRUCTION_READY))
	_v.players[1]["alive"] = false
	ev = _step(70)
	t.check(_codes(ev).has(AiTypes.Ev.PLAYER_DEFEATED))


func test_budget_exhaustion_resumes(t: TestCtx) -> void:
	_boot()
	for i: int in 30:
		_v.add_entity(200 + i, 1, AiTypes.KIND_UNIT, _tank, (30 + i) * C, 40 * C, 900, 900)
	_v.mock_tick = 100
	_ctx.tick = 100
	var b: AiBudget = AiBudget.new()
	var thinks: int = 0
	while _ctx.kb.enemy_units.count < 30 and thinks < 40:
		b.reset(40, 40)
		_ing.step(_ctx, b)
		thinks += 1
	t.eq(_ctx.kb.enemy_units.count, 30, "a small budget only slows the sweep down")
	t.gt(thinks, 2)
