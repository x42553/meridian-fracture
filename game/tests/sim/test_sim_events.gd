extends RefCounted
## SimEventBuffer / SimEvent (sim_core 10.1 test_sim_events).


func test_record_layout(t: TestCtx) -> void:
	var b: SimEventBuffer = SimEventBuffer.new()
	b.tick = 7
	b.emit(SimEvent.SPAWNED, 100, 200, 1, 2, 3, 4, 5, 6)
	b.emit(SimEvent.CASH)
	t.eq(b.count(), 2, "two records")
	t.eq(b.data.size(), 20, "stride 10")
	t.eq(b.data.slice(0, 10), PackedInt32Array([1, 7, 100, 200, 1, 2, 3, 4, 5, 6]), "[type, tick, x, y, a..f]")
	t.eq(b.data.slice(10, 20), PackedInt32Array([4, 7, 0, 0, 0, 0, 0, 0, 0, 0]), "defaults 0")
	t.eq(SimEvent.STRIDE, SimConfig.EVENT_STRIDE, "SimEvent.STRIDE == SimConfig.EVENT_STRIDE")
	t.eq(SimEvent.I_F, 9, "last index")


func test_throttle(t: TestCtx) -> void:
	var b: SimEventBuffer = SimEventBuffer.new()
	b.tick = 100
	b.emit_throttled(SimEvent.CMD_REJECTED, 0, 10)
	b.tick = 105
	b.emit_throttled(SimEvent.CMD_REJECTED, 0, 10)
	b.emit_throttled(SimEvent.CMD_REJECTED, 1, 10)  # other pid unaffected
	b.tick = 109
	b.emit_throttled(SimEvent.CMD_REJECTED, 0, 10)
	t.eq(b.count(), 2, "pid 0 once, pid 1 once so far")
	b.tick = 110
	b.emit_throttled(SimEvent.CMD_REJECTED, 0, 10)
	t.eq(b.count(), 3, "allowed again after the gap")
	b.emit_throttled(SimEvent.CMD_REJECTED + 1, 0, 10)
	t.eq(b.count(), 4, "other type unaffected")
	b.emit_throttled(SimEvent.CMD_REJECTED, -1, 10)
	t.eq(b.count(), 5, "neutral pid has its own slot")
	b.tick = 0
	b.emit_throttled(SimEvent.CMD_REJECTED, 3, 10)  # tick 0 must still emit (last = NEVER)
	t.eq(b.count(), 6, "first emission at tick 0")


func test_soft_cap(t: TestCtx) -> void:
	var b: SimEventBuffer = SimEventBuffer.new()
	for i: int in 131072:
		b.emit(1, i)
	t.eq(b.count(), 131072, "131072 kept")
	t.eq(b.dropped, 0, "none dropped yet")
	b.emit(1)
	t.eq(b.count(), 131072, "the 131073rd is not stored")
	t.eq(b.dropped, 1, "and is counted")
	b.emit_throttled(2, 0, 1)
	t.eq(b.dropped, 2, "throttled emits obey the cap")


func test_take(t: TestCtx) -> void:
	var b: SimEventBuffer = SimEventBuffer.new()
	b.emit(1, 5)
	var got: PackedInt32Array = b.take()
	t.eq(got.size(), 10, "take hands over the records")
	t.eq(b.count(), 0, "and empties the buffer")
	b.emit(2)
	t.eq(got.size(), 10, "the taken array is not aliased by later emits")
	b.clear()
	t.eq(b.count(), 0, "clear")


func test_disabled(t: TestCtx) -> void:
	var b: SimEventBuffer = SimEventBuffer.new()
	b.enabled = false
	b.emit(1)
	b.emit_throttled(1, 0, 5)
	t.eq(b.count(), 0, "no-op when disabled")
	t.eq(b.dropped, 0, "not counted as dropped")


func test_digest(t: TestCtx) -> void:
	var b: SimEventBuffer = SimEventBuffer.new()
	t.eq(b.digest(), Checksum.EMPTY_DIGEST, "empty buffer digest")
	b.emit(1, 2, 3)
	var d1: int = b.digest()
	t.ne(d1, Checksum.EMPTY_DIGEST, "non-empty digest differs")
	var c: SimEventBuffer = SimEventBuffer.new()
	c.emit(1, 2, 3)
	t.eq(c.digest(), d1, "same emissions, same digest")


func test_event_registry(t: TestCtx) -> void:
	var codes: PackedInt32Array = [SimEvent.SPAWNED, SimEvent.REMOVED, SimEvent.OWNER_CHANGED, SimEvent.CASH, SimEvent.CMD_REJECTED,
		SimEvent.ORDER_FAILED, SimEvent.PLAYER_ELIMINATED, SimEvent.MATCH_END, SimEvent.NAV_CHANGED]
	t.eq(codes, PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 9]), "core codes 1..9")
	t.eq([SimEvent.CASH_START, SimEvent.CASH_HARVEST, SimEvent.CASH_SALVAGE, SimEvent.CASH_REFUND, SimEvent.CASH_SELL, SimEvent.CASH_SPEND, SimEvent.CASH_SCRIPT],
		[0, 1, 2, 3, 4, 5, 6] as Array, "cash reasons")
	t.eq([SimEvent.SPAWN_INITIAL, SimEvent.SPAWN_PRODUCED, SimEvent.SPAWN_PLACED, SimEvent.SPAWN_DEPLOYED, SimEvent.SPAWN_SUMMONED, SimEvent.SPAWN_WRECK, SimEvent.SPAWN_SCRIPT],
		[0, 1, 2, 3, 4, 5, 6] as Array, "spawn reasons")
	t.eq([SimEvent.REM_KILLED, SimEvent.REM_SOLD, SimEvent.REM_EXPIRED, SimEvent.REM_DEPLOYED, SimEvent.REM_CONSUMED, SimEvent.REM_SCRIPT],
		[0, 1, 2, 3, 4, 5] as Array, "remove reasons")
	t.check(SimEvent.BLOCK_CORE_LAST < SimEvent.BLOCK_MOVEMENT_FIRST and SimEvent.BLOCK_MOVEMENT_LAST < SimEvent.BLOCK_COMBAT_FIRST, "blocks ordered")
	t.check(SimEvent.BLOCK_COMBAT_LAST < SimEvent.BLOCK_ABILITIES_FIRST and SimEvent.BLOCK_ABILITIES_LAST < SimEvent.BLOCK_ECONOMY_FIRST, "blocks ordered")
	t.check(SimEvent.BLOCK_ECONOMY_LAST < SimEvent.BLOCK_PRESENTATION_FIRST, "presentation block last")
