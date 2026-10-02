extends RefCounted
## Field Manual model (ui.md 3.6 / 5.17): golden comparison of the cards against the resolved defs (roster clone + DefPlayerView)
## for three rosters, structure / research / power / superweapon cards, roster comparison, search and the ability wording.

const ROSTERS: Array[String] = ["roster.napc.vanilla", "roster.napc.canada", "roster.han.china"]

var _data: GameData = null


func _gd() -> GameData:
	if _data == null:
		_data = GameData.load_default()
	return _data


func _model(roster_id: String) -> UiFmModel:
	var d: GameData = _gd()
	var m: UiFmModel = UiFmModel.new()
	m.build(d, d.rosters[d.roster_idx(roster_id)])
	return m


static func _stat(card: Dictionary, key: String) -> Dictionary:
	for s: Variant in card["stats"] as Array:
		if (s as Dictionary)["key"] == key:
			return s as Dictionary
	return {}


func test_unit_cards_match_resolved_defs(t: TestCtx) -> void:
	var d: GameData = _gd()
	for rid: String in ROSTERS:
		var r: DefRoster = d.rosters[d.roster_idx(rid)]
		var m: UiFmModel = _model(rid)
		var view: DefPlayerView = DefPlayerView.new(d, r)
		var cards: Array[Dictionary] = m.units()
		t.eq(cards.size(), r.producible_units.size() + r.spawnables.size(), "%s: one card per producible unit and summon" % rid)
		for c: Dictionary in cards:
			var idx: int = int(c["index"])
			var u: DefUnit = r.units[idx]
			t.eq(c["name"], UiFmText.def_name(u), "%s name" % u.id)
			t.eq(c["text"], u.ui_text, "%s role text" % u.id)
			var hp: Dictionary = _stat(c, "health")
			t.eq(int(hp["value"]), view.resolved_stats(DefEnums.Kind.UNIT, idx)[DefEnums.Stat.HEALTH], "%s health = resolved" % u.id)
			t.eq(hp["text"], DefFormat.credits_text(u.health), "%s health text" % u.id)
			var bt: Dictionary = _stat(c, "build_time")
			t.eq(int(bt["value"]), view.unit_ticks[idx], "%s build time = player view" % u.id)
			t.eq(bt["text"], DefFormat.seconds_text(view.unit_ticks[idx]) + " s")
			if u.cost > 0:
				var cost: Dictionary = _stat(c, "cost")
				t.eq(int(cost["value"]), view.unit_cost[idx], "%s cost = player view" % u.id)
				t.eq(int(cost["base"]), d.units[idx].cost, "%s base cost" % u.id)
				var expect_delta: int = UiFmText.delta_bp(d.units[idx].cost, view.unit_cost[idx])
				t.check(absi(int(cost["delta_bp"]) - expect_delta) <= 150 and (int(cost["delta_bp"]) > 0) == (expect_delta > 0), "%s cost delta %d vs measured %d" % [u.id, int(cost["delta_bp"]), expect_delta])
				if int(cost["delta_bp"]) > 0:
					t.eq(cost["tone"], "bad", "%s: a higher cost is bad" % u.id)
				elif int(cost["delta_bp"]) < 0:
					t.eq(cost["tone"], "good", "%s: a lower cost is good" % u.id)
				else:
					t.eq(cost["delta_text"], "")
			var ws: Array = c["weapons"] as Array
			t.eq(ws.size(), u.weapons.size(), "%s weapon rows" % u.id)
			for i: int in ws.size():
				var w: Dictionary = ws[i]
				var slot: DefWeaponSlot = u.weapons[i]
				var dmg: int = view.effective_slot_value(idx, i, DefEnums.Stat.DAMAGE)
				var rel: int = view.effective_slot_value(idx, i, DefEnums.Stat.RELOAD)
				t.eq(int(w["damage"]), dmg, "%s weapon %d damage" % [u.id, i])
				t.eq(int(w["dps_x10"]), UiFmText.dps_x10(dmg, slot.hits_per_volley, rel), "%s weapon %d dps" % [u.id, i])
				t.eq(int(w["range"]), view.effective_slot_value(idx, i, DefEnums.Stat.RANGE), "%s weapon %d range" % [u.id, i])
			t.eq((c["abilities"] as Array).size(), u.abilities.size(), "%s ability rows" % u.id)


func test_pinned_values(t: TestCtx) -> void:
	var m: UiFmModel = _model("roster.napc.vanilla")
	var d: GameData = _gd()
	var rifle: Dictionary = m.card_for(DefEnums.Kind.UNIT, d.unit_idx("unit.napc.rifle_squad"))
	t.eq(rifle["name"], "Rifle Squad")
	t.eq(_stat(rifle, "cost")["text"], "250")
	t.eq(_stat(rifle, "build_time")["text"], "9.0 s", "180 ticks = 9.0 s")
	t.eq(_stat(rifle, "health")["text"], "402")
	var w: Dictionary = (rifle["weapons"] as Array)[0]
	t.eq(w["dps_text"], "52.0", "26 damage x 2 hits per 1.0 s")
	t.eq(w["range_text"], "5.5", "5632 u = 5.5 cells")
	t.eq(rifle["armor"], "Infantry")
	# NAPC vehicles: health +10 %, cost +10 % (faction trait)
	var tank: Dictionary = {}
	for c: Dictionary in m.units():
		if (c["stats"] as Array).any(func(s: Dictionary) -> bool: return s["key"] == "cost" and int(s["delta_bp"]) == 1000):
			tank = c
			break
	t.check(not tank.is_empty(), "a NAPC vehicle shows +10 % cost")
	if not tank.is_empty():
		t.eq(_stat(tank, "cost")["delta_text"], "+10%")
		t.eq(_stat(tank, "cost")["tone"], "bad")
		t.eq(_stat(tank, "health")["delta_text"], "+10%")
		t.eq(_stat(tank, "health")["tone"], "good")
		t.check(str(_stat(tank, "cost")["tip"]).contains("Base"), "tooltip names the base value")
		t.check(str(_stat(tank, "cost")["tip"]).contains("Land combat vehicles"), "tooltip names the modifier")


func test_structure_research_power_cards(t: TestCtx) -> void:
	var d: GameData = _gd()
	var m: UiFmModel = _model("roster.napc.canada")
	var r: DefRoster = m.roster
	var structs: Array[Dictionary] = m.structures()
	t.eq(structs.size(), r.producible_structures.size() + 1, "HQ plus the buildable structures")
	t.check(bool(structs[0]["start"]), "the HQ comes first and is a start structure")
	var gen: Dictionary = m.card_for(DefEnums.Kind.STRUCTURE, d.structure_idx("structure.shared.generator"))
	t.eq(gen["power"], 150)
	t.eq(_stat(gen, "power")["text"], "+150 power")
	t.eq((gen["stats"] as Array).size() > 3, true)
	t.eq(m.research().size(), r.research_list.size())
	for rc: Dictionary in m.research():
		t.check(int(rc["cost"]) > 0 and str(rc["text"]) != "", "research %s has cost and effect text" % rc["id"])
		t.check(bool(rc["exclusive"]) == (d.research[int(rc["index"])].introduced_by == r.index), "exclusive flag")
	var p: Array[Dictionary] = m.powers()
	t.eq(p.size(), r.power_list.size() + 1, "three powers and the superweapon")
	t.eq(p[p.size() - 1]["kind"], DefEnums.Kind.SUPERWEAPON)
	var sw: Dictionary = p[p.size() - 1]
	t.eq(_stat(sw, "recharge")["value"], r.superweapon_def.recharge_t)
	t.eq(_stat(sw, "warning")["text"], UiFmText.secs(r.superweapon_def.warning_t))
	t.check(str(p[0]["text"]) != "" and str(p[0]["targeting"]) != "", "power text and targeting")
	t.eq(_stat(p[0], "cooldown")["value"], d.powers[int(p[0]["index"])].cooldown_t)


func test_compare_and_unit_rows(t: TestCtx) -> void:
	var d: GameData = _gd()
	var usa: UiFmModel = _model("roster.napc.usa")
	var canada: DefRoster = d.rosters[d.roster_idx("roster.napc.canada")]
	var cmp: Dictionary = usa.compare(canada)
	t.eq(cmp["a"], "roster.napc.usa")
	t.eq(cmp["b"], "roster.napc.canada")
	var only_a: PackedStringArray = PackedStringArray((cmp["only_a"] as Array).map(func(r: Dictionary) -> String: return str(r["name"])))
	var only_b: PackedStringArray = PackedStringArray((cmp["only_b"] as Array).map(func(r: Dictionary) -> String: return str(r["name"])))
	t.check(only_a.has("Condor Stealth Bomber"), "USA only: Condor (%s)" % ", ".join(only_a))
	t.check(only_b.has("Bastion Heavy Tank"), "Canada only: Bastion (%s)" % ", ".join(only_b))
	var found: bool = false
	for rp: Dictionary in cmp["replaced"] as Array:
		if (rp["a"] as Dictionary)["name"] == "Guardian Tank" and (rp["b"] as Dictionary)["name"] == "Narwhal Amphibious Tank":
			found = true
	t.check(found, "Guardian Tank is replaced by the Narwhal")
	t.check(not (cmp["modifier_diffs"] as Array).is_empty(), "modifier differences listed")
	var sides: Dictionary = {}
	for md: Dictionary in cmp["modifier_diffs"] as Array:
		sides[md["side"]] = true
	t.check(sides.has("a") and sides.has("b"), "differences from both sides")
	var guardian: int = d.unit_idx("unit.napc.guardian_tank")
	var rows: Array[Dictionary] = usa.compare_unit(guardian, canada)
	t.check(rows.size() >= 5, "stat rows: %d" % rows.size())
	var cost_row: Dictionary = {}
	for r: Dictionary in rows:
		if r["label"] == "Cost":
			cost_row = r
	t.check(not cost_row.is_empty() and int(cost_row["a"]) > 0 and int(cost_row["b"]) > 0, "cost of both versions")
	t.eq(int(cost_row["delta_bp"]), UiFmText.delta_bp(int(cost_row["a"]), int(cost_row["b"])))
	t.check(not (cmp["units"] as Array).is_empty(), "unit comparison rows")


func test_search_ranks_name_before_text(t: TestCtx) -> void:
	var m: UiFmModel = _model("roster.napc.vanilla")
	t.eq(m.search("", 20).size(), 0, "empty text finds nothing")
	var res: Array[Dictionary] = m.search("rifle", 20)
	t.check(not res.is_empty() and res[0]["name"] == "Rifle Squad", "Rifle Squad first: %s" % (res[0]["name"] if not res.is_empty() else "-"))
	t.check(m.search("e", 3).size() == 3, "limit respected")
	t.check(m.search("zzzzqq", 20).is_empty())
	var upper: Array[Dictionary] = m.search("RIFLE", 20)
	t.eq(upper.size(), res.size(), "case-insensitive")
	var gen: Array[Dictionary] = m.search("generator", 5)
	t.check(not gen.is_empty() and gen[0]["kind"] == DefEnums.Kind.STRUCTURE)


func test_tech_tree_depths(t: TestCtx) -> void:
	var m: UiFmModel = _model("roster.han.china")
	var tree: Dictionary = m.tech_tree()
	var nodes: Array = tree["nodes"] as Array
	t.eq(nodes.size(), m.roster.producible_structures.size() + 1)
	var hq: Dictionary = {}
	for n: Dictionary in nodes:
		if int(n["index"]) == m.roster.hq_idx:
			hq = n
	t.eq(int(hq["depth"]), 0, "HQ is depth 0")
	var by_idx: Dictionary = {}
	for n2: Dictionary in nodes:
		by_idx[int(n2["index"])] = n2
	for n3: Dictionary in nodes:
		for rq: Variant in n3["requires"] as Array:
			t.check(int((by_idx[int(rq)] as Dictionary)["depth"]) < int(n3["depth"]), "%s deeper than its requirement" % n3["name"])
	t.check((tree["edges"] as Array).size() > 0)


func test_every_roster_builds_readable_cards(t: TestCtx) -> void:
	var d: GameData = _gd()
	var seen_kinds: Dictionary = {}
	for r: DefRoster in d.rosters:
		var m: UiFmModel = UiFmModel.new()
		m.build(d, r)
		var all: Array[Dictionary] = []
		all.append_array(m.units())
		all.append_array(m.structures())
		all.append_array(m.research())
		all.append_array(m.powers())
		for c: Dictionary in all:
			seen_kinds[int(c["kind"])] = true
			t.check(not str(c["name"]).is_empty(), "%s: card without name (%s)" % [r.id, c.get("id", "?")])
			for a: Dictionary in c.get("abilities", []) as Array:
				var txt: String = str(a["text"])
				t.check(not txt.contains("%s") and not txt.contains("%d") and not txt.contains("%%"), "%s ability text has no format leftovers: %s" % [c["id"], txt])
				t.check(txt != "Ability." and not txt.is_empty(), "%s ability %s has wording" % [c["id"], a["name"]])
		var ov: Dictionary = m.overview()
		t.check(not str((ov["faction"] as Dictionary)["name"]).is_empty() and not str((ov["roster"] as Dictionary)["title"]).is_empty(), "%s overview" % r.id)
	t.eq(seen_kinds.size(), 5, "unit, structure, research, power, superweapon cards")
