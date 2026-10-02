extends RefCounted
## AiDataStore / difficulty profiles / personalities (ai.md 5.14, 7): schema, cheats only for Brutal (V10), 32 rosters.

const STORE_DIR: String = "res://data/balance/ai/"


func test_store_loads_clean(t: TestCtx) -> void:
	var s: AiDataStore = AiDataStore.load_default()
	t.eq(s.errors, PackedStringArray(), "no load or validation errors")
	t.eq(s.difficulty_rows.size(), 4)
	t.ne(s.data_hash, 0)
	t.eq(s.tune("strength.launch_ratio_x100"), 130)
	t.eq(s.tune("no.such.key", 7), 7, "missing key => default")
	t.eq(s.tune_by_level("econ.margin_min", AiTypes.Difficulty.HARD), 20)
	var o: AiDataStore = s.with_overrides({"strength.launch_ratio_x100": 150})
	t.eq(o.tune("strength.launch_ratio_x100"), 150, "override wins")
	t.eq(s.tune("strength.launch_ratio_x100"), 130, "the shared store is untouched")


func test_only_brutal_cheats_and_is_labelled(t: TestCtx) -> void:
	var s: AiDataStore = AiDataStore.load_default()
	for lv: int in 3:
		var p: AiDifficultyProfile = s.difficulty(lv)
		t.check_false(p.info_omniscient, "level %d is not omniscient" % lv)
		t.eq(p.handicap_pct, 100)
		t.check_false(p.has_cheats())
		t.eq(p.label_cheats, "")
	var b: AiDifficultyProfile = s.difficulty(AiTypes.Difficulty.BRUTAL)
	t.check(b.info_omniscient)
	t.eq(b.handicap_pct, 120, "Brutal's resource bonus")
	t.eq(b.label_cheats, "ai.cheats.brutal", "the cheat is labelled")
	t.check(b.cheats_text.contains("+20 %"))
	t.check(b.has_cheats())
	t.eq(AiFactory.level_handicap_pct(3), 120)
	t.eq(AiFactory.level_cheat_key(3), "ai.cheats.brutal")
	t.eq(AiFactory.level_cheat_key(2), "")


func test_negative_v10_cheating_easy_row(t: TestCtx) -> void:
	var s: AiDataStore = AiDataStore.new()
	s.difficulty_rows = AiDataStore.load_default().difficulty_rows.duplicate()
	var bad: AiDifficultyProfile = AiDifficultyProfile.from_dict(AiDataStore.load_default().difficulty(0).dump())
	bad.handicap_pct = 120
	s.difficulty_rows[0] = bad
	var errs: PackedStringArray = s.validate()
	var found: bool = false
	for e: String in errs:
		if e.begins_with("V10"):
			found = true
	t.check(found, "V10 fires for an Easy row with handicap_pct 120")


func test_table_5_14_1_values(t: TestCtx) -> void:
	var s: AiDataStore = AiDataStore.load_default()
	var cols: Dictionary = {
		"think_period_ticks": [30, 20, 10, 6], "micro_period_ticks": [0, 10, 4, 2], "apm_cap": [40, 90, 180, 320],
		"cmd_burst": [4, 8, 16, 28], "reaction_delay_ticks": [60, 30, 12, 4], "queue_depth": [1, 2, 3, 3],
		"wu_per_tick": [220, 350, 500, 600], "call_cap_wu": [1500, 2400, 3000, 3000], "unit_cap_pct": [60, 85, 100, 100],
		"first_attack_min_s": [900, 600, 420, 330], "sw_min_time_s": [1800, 960, 660, 540],
	}
	for k: String in cols:
		for lv: int in 4:
			t.eq(s.difficulty(lv).get(k), (cols[k] as Array)[lv], "%s level %d" % [k, lv])


func test_32_personalities_match_the_roster_ids(t: TestCtx) -> void:
	var d: GameData = SimMatchKit.data()
	var s: AiDataStore = AiDataStore.load_default()
	var rows: Dictionary = s.personality.get("rosters", {})
	t.eq(rows.size(), 32)
	for rid: String in d.roster_ids():
		t.check(s.has_personality(rid), "personality row for %s" % rid)


func test_personality_is_seeded_and_styled(t: TestCtx) -> void:
	var s: AiDataStore = AiDataStore.load_default()
	var hard: AiDifficultyProfile = s.difficulty(2)
	var a: AiRng = AiRng.new()
	a.seed_from(99)
	var p1: AiPersonality = AiPersonality.build(s, "roster.olm.algeria", 0, hard, a)
	var b: AiRng = AiRng.new()
	b.seed_from(99)
	var p2: AiPersonality = AiPersonality.build(s, "roster.olm.algeria", 0, hard, b)
	t.eq(p1.state_hash(), p2.state_hash(), "same seed => same personality")
	t.eq(a.state(), b.state(), "same draws")
	t.check(p1.has_flag(AiTypes.doctrine_bit("COLLECTOR_RAID")), "Algeria raids collectors")
	t.gt(p1.harass_pct, 50, "Algeria: harass 80 +- jitter")
	t.eq(p1.retreat_hp_pct, 35)
	var na: AiPersonality = AiPersonality.build(s, "roster.napc.usa", 0, s.difficulty(0), a)
	t.eq(na.retreat_hp_pct, 50, "NAPC apron retreat")
	var c: AiRng = AiRng.new()
	c.seed_from(5)
	var base: AiPersonality = AiPersonality.build(s, "roster.napc.vanilla", 0, hard, c, {"aggression": 50})
	var d: AiRng = AiRng.new()
	d.seed_from(5)
	var aggr: AiPersonality = AiPersonality.build(s, "roster.napc.vanilla", 1, hard, d, {"aggression": 50})
	t.eq(base.aggression, aggr.aggression, "override wins over the style")
	t.eq(aggr.first_attack_scale_pct, 80, "aggressive: first attack x0.80")
	t.eq(aggr.posture_threshold_shift, -10)
	var e: AiRng = AiRng.new()
	e.seed_from(5)
	var defn: AiPersonality = AiPersonality.build(s, "roster.napc.vanilla", 2, hard, e)
	t.eq(defn.wave_interval_scale_pct, 120)
	t.le(defn.defense_pct, 40)
	# wildcard resolves to one of the three modes and an attack style 0..4
	var w: AiRng = AiRng.new()
	w.seed_from(31)
	var wp: AiPersonality = AiPersonality.build(s, "roster.nec.vanilla", 3, hard, w)
	t.check(wp.style_mode >= 0 and wp.style_mode <= 2)
	t.check(wp.attack_style >= 0 and wp.attack_style <= 4)
