extends RefCounted
## DefLayer3.checksum() is cached (it is hashed into the state checkpoint of every player every CHECKSUM_PERIOD ticks: ~1.2 ms per player when
## recomputed): the cache must be invisible - equal to a fresh computation, and dropped by apply_research.


func test_cached_checksum_equals_a_fresh_computation_and_follows_research(t: TestCtx) -> void:
	var d: GameData = GameData.load_default()
	var roster: DefRoster = d.rosters[0]
	var v: DefPlayerView = DefPlayerView.new(d, roster)
	var l3: DefLayer3 = v.layer3
	var c0: int = l3.checksum()
	t.eq(l3.checksum(), c0, "second call (cache hit) is identical")
	t.eq(l3._compute_checksum(), c0, "cache == fresh computation")
	var idx: int = -1
	for i: int in roster.research_list:
		idx = i
		break
	if idx < 0:
		t.skip("roster has no research")
		return
	l3.apply_research(idx)
	var c1: int = l3.checksum()
	t.ne(c1, c0, "apply_research changes the checksum (the cache was dropped)")
	t.eq(c1, l3._compute_checksum(), "and the new cached value equals a fresh computation")
	t.eq(l3.checksum(), c1, "stable again")
