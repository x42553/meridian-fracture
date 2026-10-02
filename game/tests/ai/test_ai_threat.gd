extends RefCounted
## AiThreatMap (ai.md 5.3.3 / 10.1): linear decay over 600 ticks, sweep commit keeps max(decayed, frame).

const C: int = Fp.CELL


func _map() -> AiThreatMap:
	var m: AiThreatMap = AiThreatMap.new()
	m.setup(96, 96)
	return m


func test_decay(t: TestCtx) -> void:
	var m: AiThreatMap = _map()
	m.add_sighting(20 * C, 20 * C, 500)
	m.commit(0)
	t.eq(m.at(20 * C, 20 * C, 0), 500)
	t.eq(m.at(20 * C, 20 * C, 300), 250, "half decayed at 300")
	t.eq(m.at(20 * C, 20 * C, 600), 0, "gone at 600")
	t.eq(m.at(70 * C, 70 * C, 0), 0, "elsewhere is quiet")


func test_commit_keeps_the_max(t: TestCtx) -> void:
	var m: AiThreatMap = _map()
	m.add_sighting(10 * C, 10 * C, 400)
	m.commit(0)
	m.add_sighting(10 * C, 10 * C, 100)
	m.commit(300)  # decayed stored = 200 > frame 100
	t.eq(m.at(10 * C, 10 * C, 300), 200)
	m.add_sighting(10 * C, 10 * C, 900)
	m.commit(310)
	t.eq(m.at(10 * C, 10 * C, 310), 900, "a stronger frame wins")


func test_frame_sums_within_a_sweep_and_circle_query(t: TestCtx) -> void:
	var m: AiThreatMap = _map()
	m.add_sighting(9 * C, 9 * C, 100)
	m.add_sighting(10 * C, 10 * C, 150)  # same 8-cell block
	m.add_sighting(20 * C, 9 * C, 70)  # neighbouring block
	m.commit(50)
	t.eq(m.at(9 * C, 9 * C, 50), 250, "one block accumulates the sweep")
	t.eq(m.circle(12 * C, 9 * C, 6 * C, 50), 320, "circle sums the overlapped blocks")
	t.eq(m.circle(80 * C, 80 * C, 3 * C, 50), 0)
