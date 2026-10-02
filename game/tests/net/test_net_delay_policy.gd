extends RefCounted
## NET-4: NetDelayPolicy (spec 5.5.6), cases (a)-(g) of the test plan.


func _policy(turn_ms: int = 100, d_min: int = 2, d_max: int = 8) -> NetDelayPolicy:
	var p: NetDelayPolicy = NetDelayPolicy.new()
	p.configure(d_min, d_max, turn_ms)
	p.reset(0, d_min)
	return p


## Runs 500 ms cadence: a PONG at every step (values from `sample`), then evaluate. Returns the final D.
func _run(p: NetDelayPolicy, d0: int, from_ms: int, to_ms: int, sample: Callable, peer: int = 2) -> int:
	var d: int = d0
	var now: int = from_ms
	var i: int = 0
	while now <= to_ms:
		var s: Array = sample.call(i, now) as Array
		p.feed_pong(peer, now, int(s[0]), int(s[1]), int(s[2]), 0, bool(s[3]))
		d = p.evaluate(now, d)
		now += 500
		i += 1
	return d


func test_a_lan_keeps_two(t: TestCtx) -> void:
	var p: NetDelayPolicy = _policy()
	var d: int = _run(p, 2, 0, 60000, func(i: int, _n: int) -> Array: return [20 + (4 if i % 2 == 0 else -4), 190, 0, false])
	t.eq(d, 2)
	t.check(p.peer_rtt_ms(2) >= 17 and p.peer_rtt_ms(2) <= 23)
	t.check(p.peer_jitter_ms(2) >= 2 and p.peer_jitter_ms(2) <= 6)


func test_b_high_rtt_raises_within_two_evaluations(t: TestCtx) -> void:
	var p: NetDelayPolicy = _policy()
	# warm the estimator: rtt 250 +- 50 (alternating 200 / 300) without asking for a decision
	for i: int in 60:
		p.feed_pong(2, i * 100, 200 if i % 2 == 0 else 300, 100, 0, 0, false)
	t.check(p.peer_rtt_ms(2) >= 240 and p.peer_rtt_ms(2) <= 260)
	t.check(p.peer_jitter_ms(2) >= 45 and p.peer_jitter_ms(2) <= 55)
	p.reset(5900, 2)
	t.eq(p.evaluate(6400, 2), 2, "1 s cooldown after the last change")
	t.eq(p.evaluate(6900, 2), 4, "ceil((250 + 2 * 50 + 34) / 100) = 4")
	t.eq(p.evaluate(7400, 4), 4)
	# capped at d_max
	var q: NetDelayPolicy = _policy(100, 2, 3)
	q.feed_pong(2, 0, 900, 0, 0, 0, false)
	t.eq(q.evaluate(1500, 2), 3)


func test_c_hitch_and_huge_rtt_are_quarantined(t: TestCtx) -> void:
	var p: NetDelayPolicy = _policy()
	p.feed_pong(2, 1000, 20, 150, 0, 0, false)
	p.feed_pong(2, 1500, 20, 150, 0, 1, true)
	for i: int in 5:
		p.feed_pong(2, 1600 + i * 500, 400, 0, 500, 3, false)
	t.eq(p.evaluate(4400, 2), 2, "samples inside the 3 s quarantine are ignored")
	var q: NetDelayPolicy = _policy()
	q.feed_pong(2, 1000, 20, 150, 0, 0, false)
	q.feed_pong(2, 1500, 3000, 150, 0, 0, false)
	q.feed_pong(2, 2000, 300, 150, 0, 0, false)
	t.eq(q.evaluate(3000, 2), 2, "rtt 3000 quarantines the peer")
	q.feed_pong(2, 4600, 300, 150, 0, 0, false)
	t.eq(q.evaluate(5000, 2), 2, "after 3 s one sample cannot move the average much")
	q.feed_pong(2, 4600, 300, 150, 0, 0, false)
	for i: int in 30:
		q.feed_pong(2, 4700 + i * 100, 400, 150, 0, 0, false)
	t.eq(q.evaluate(8000, 2), 5, "the peer counts again once the quarantine is over")


func test_d_stalls_raise_once_then_wind_up_protection(t: TestCtx) -> void:
	var p: NetDelayPolicy = _policy()
	p.feed_pong(2, 500, 20, 100, 250, 1, false)
	p.feed_pong(2, 1000, 20, 100, 250, 1, false)
	p.feed_pong(2, 1500, 20, 100, 0, 0, false)
	t.eq(p.evaluate(1500, 2), 2, "the 2 s cooldown since the reset applies")
	t.eq(p.evaluate(2000, 2), 3, "250 + 250 ms of stalls within 10 s")
	# rings were cleared: the old stalls cannot trigger a second raise
	t.eq(p.evaluate(4500, 3), 3)
	p.feed_pong(2, 2500, 20, 100, 250, 1, false)
	p.feed_pong(2, 3000, 20, 100, 250, 1, false)
	t.eq(p.evaluate(3500, 3), 3, "no second raise for 2 s")
	t.eq(p.evaluate(4000, 3), 4, "new stalls after the cooldown raise again")
	# stall_ms that is too small never raises
	var q: NetDelayPolicy = _policy()
	for i: int in 40:
		q.feed_pong(2, i * 500, 20, 100, 190, 1, false)
	t.check(q.evaluate(20000, 2) == 3, "190 ms per sample adds up inside the 10 s window")
	var r: NetDelayPolicy = _policy()
	r.feed_pong(2, 0, 20, 100, 390, 1, false)
	t.eq(r.evaluate(5000, 2), 2, "390 ms < DELAY_RAISE_STALL_MS")


func test_e_lowering_needs_headroom_and_holds(t: TestCtx) -> void:
	var p: NetDelayPolicy = _policy()
	p.reset(0, 4)
	var changes: Array = []
	var d: int = 4
	var now: int = 0
	while now <= 20000:
		p.feed_pong(2, now, 20, 160, 0, 0, false)
		var nd: int = p.evaluate(now, d)
		if nd != d:
			changes.append([now, nd])
		d = nd
		now += 500
	t.eq(changes, [[8000, 3], [16000, 2]], "3 at t >= 8 s, 2 at t >= 16 s")
	# 159 ms of slack is not enough
	var q: NetDelayPolicy = _policy()
	q.reset(0, 4)
	var d2: int = 4
	for i: int in 60:
		q.feed_pong(2, i * 500, 20, 159, 0, 0, false)
		d2 = q.evaluate(i * 500, d2)
	t.eq(d2, 4)
	# any stall in the last 8 s blocks lowering
	var r: NetDelayPolicy = _policy()
	r.reset(0, 4)
	var d3: int = 4
	for i: int in 34:
		r.feed_pong(2, i * 500, 20, 400, 30 if i == 14 else 0, 0, false)
		d3 = r.evaluate(i * 500, d3)
	t.eq(d3, 3, "lowered once, after the stall left the window")


func test_f_configure_and_remove_peer(t: TestCtx) -> void:
	var p: NetDelayPolicy = _policy(100, 1, 8)
	p.feed_pong(2, 0, 20, 100, 0, 0, false)
	p.reset(0, 1)
	t.eq(p.evaluate(1000, 1), 1, "d_min 1 is honoured (local sessions)")
	p.feed_pong(2, 1000, 900, 100, 0, 0, false)
	p.remove_peer(2)
	t.eq(p.peer_rtt_ms(2), 0)
	t.eq(p.evaluate(3000, 1), 1, "a removed peer no longer counts")
	t.eq(p.get_turn_ms(), 100)


func test_g_double_speed_needs_more_turns(t: TestCtx) -> void:
	var slow: NetDelayPolicy = _policy(100)
	var fast: NetDelayPolicy = _policy(50)
	slow.feed_pong(2, 0, 250, 100, 0, 0, false)
	fast.feed_pong(2, 0, 250, 100, 0, 0, false)
	t.eq(fast.get_turn_ms(), 50)
	t.eq(slow.evaluate(1000, 2), 3, "ceil(284 / 100)")
	t.eq(fast.evaluate(1000, 2), 6, "ceil(284 / 50)")
	# through the host: turn_ms = 100 * 100 / speed_pct
	var h: NetTurnHost = NetTurnHost.new()
	h.setup(NetClock.manual(), {"initial_delay": 2, "speed_pct": 100})
	h.set_speed(200)
	t.eq(h._turn_ms(), 50)
	h.set_speed(50)
	t.eq(h._turn_ms(), 200)
