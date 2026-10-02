class_name NetLockstep
extends RefCounted
## Pacing + barrier + execution of the lockstep protocol (docs/spec/net.md 3.4, 4.6, 5.5.2, 5.5.3). The same
## code runs on host, client and (later) spectator. It never looks at wall time except through the injected
## NetClock, and never feeds anything time-dependent into the simulation: only (turn, pid, ints) in bundle order.
##
## Turn N = ticks 2N and 2N+1. Turns 0 .. D0-1 (the pre-roll) are implicit empty bundles created by start().

## (turn: int, exec_turn: int, cmds: Array) -> void. cmds: Array[PackedInt32Array]. Host wires it to NetTurnHost.on_input.
var on_send_input: Callable = Callable()
## (turn: int, bundle: NetBundle) -> void. Recorder, AI runner, status display. Fires for real bundles and pre-roll.
var on_turn_begin: Callable = Callable()
## (tick: int, checksum: int, chain: int) -> void. Every CHECKSUM_PERIOD_TICKS and once more at match end.
var on_checksum: Callable = Callable()
## (stalled: bool, stall_ms: int) -> void. stall_ms counts from the moment the bundle was due.
var on_stall_changed: Callable = Callable()
var on_match_over: Callable = Callable()
## (turn: int, target_turn: int) -> void. After the local fill-up (host: AI production + injection frontier).
var on_boundary: Callable = Callable()
## (turn: int, ctrl: PackedInt32Array) -> void. Every ctrl record as it is applied.
var on_ctrl: Callable = Callable()
## (paused: bool) -> void.
var on_pause: Callable = Callable()

var _sim: NetSimAdapter = null
var _clock: NetClock = null
var _local_pid: int = -1
var _tick_us: int = NetProtocol.TICK_US
var _speed_pct: int = 100
var _unpaced: bool = false
var _delay: int = 2
var _acc_us: int = 0
var _last_us: int = 0
var _tick: int = 0
var _queue: Dictionary = {}
var _arrival_us: Dictionary = {}
var _next_push: int = 0
var _ooo: Dictionary = {}
var _sent_through: int = -1
var _pending: Array[PackedInt32Array] = []
var _chain: int = 0x811C9DC5
var _paused: bool = false
var _pause_after_turn: int = -1
var _paused_at_turn: int = -1
var _resume_turn: int = -1
var _stall_since_us: int = -1
var _stall_is_hitch: bool = false
var _stall_ui: bool = false
var _rep_slack_min_ms: int = 32767
var _rep_stall_ms: int = 0
var _rep_episodes: int = 0
var _rep_hitch: bool = false
var _step_cost_us_ewma: int = 0
var _step_cost_total_us: int = 0  ## sum / max / count of every sim step (QA soak: avg and worst ms per tick)
var _step_cost_max_us: int = 0
var _steps_timed: int = 0
var _over: bool = false
var _started: bool = false
var _dup_in: int = 0
var _ooo_in: int = 0
var _stall_total_ms: int = 0
var _stall_episodes_total: int = 0


func setup(sim: NetSimAdapter, clock: NetClock, local_pid: int, initial_delay: int, speed_pct: int) -> void:
	_sim = sim
	_clock = clock
	_local_pid = local_pid
	_delay = clampi(initial_delay, 1, NetProtocol.D_MAX)
	_tick = sim.current_tick()
	set_speed_pct(speed_pct)


## Pre-roll: turns 0 .. D0-1 are implicit empty bundles; sent_through = D0-1. Call once, when the match starts.
func start() -> void:
	_last_us = _clock.now_us()
	_acc_us = 0
	_queue.clear()
	_arrival_us.clear()
	_ooo.clear()
	for t: int in _delay:
		_queue[t] = NetBundle.build(t, PackedInt32Array(), [], [])
	_next_push = _delay
	_sent_through = _delay - 1
	_started = true


## Accepts a bundle in order or buffers it within REORDER_WINDOW (spec 5.5.5). Returns NetProtocol.BundleResult.
func push_bundle(b: NetBundle) -> int:
	if b == null:
		return NetProtocol.BundleResult.MALFORMED
	if _over or not _started:
		return NetProtocol.BundleResult.WRONG_STATE
	var t: int = b.turn
	if t < _next_push:
		_dup_in += 1
		return NetProtocol.BundleResult.DUPLICATE
	if t > _next_push + NetProtocol.REORDER_WINDOW:
		return NetProtocol.BundleResult.TOO_FAR
	if t > _next_push:
		if _ooo.has(t):
			_dup_in += 1
			return NetProtocol.BundleResult.DUPLICATE
		_ooo[t] = b
		_ooo_in += 1
		return NetProtocol.BundleResult.OK
	var now: int = _clock.now_us()
	_accept(b, now)
	while _ooo.has(_next_push):
		var nb: NetBundle = _ooo[_next_push] as NetBundle
		_ooo.erase(_next_push)
		_accept(nb, now)
	return NetProtocol.BundleResult.OK


func _accept(b: NetBundle, now: int) -> void:
	_queue[b.turn] = b
	_arrival_us[b.turn] = now
	_next_push = b.turn + 1


## Queues a local command for the next boundary (FIFO, at most LOCAL_QUEUE_MAX pending). false = rejected.
func submit_local(ints: PackedInt32Array) -> bool:
	if _local_pid < 0 or ints.is_empty() or ints.size() > NetProtocol.MAX_CMD_INTS:
		return false
	if ints[0] < 0 or ints[0] > 255 or _pending.size() >= NetProtocol.LOCAL_QUEUE_MAX:
		return false
	_pending.append(ints)
	return true


## Runs 0..max_ticks sim ticks (spec 5.5.2). speed_pct 0 = unpaced: the accumulator is ignored, the barrier is not.
func update(max_ticks: int = NetProtocol.MAX_TICKS_PER_POLL) -> int:
	var now: int = _clock.now_us()
	var elapsed: int = clampi(now - _last_us, 0, NetProtocol.MAX_ELAPSED_US)
	_last_us = now
	if _over or _paused or not _started:
		return 0
	if not _unpaced:
		_acc_us += elapsed * _speed_pct / 100
	var ticks: int = 0
	while ticks < max_ticks and (_unpaced or _acc_us >= _tick_us):
		if _tick % 2 == 0:
			var e: int = _tick / 2
			if _pause_after_turn >= 0 and _pause_after_turn == e - 1:
				if _resume_turn >= e:
					_pause_after_turn = -1
				else:
					_paused = true
					_paused_at_turn = e
					_call1(on_pause, true)
					break
			var b: NetBundle = _queue.get(e) as NetBundle
			if b == null:
				_stall_begin(now)
				break
			_stall_end(now)
			_begin_turn(e, b, now)
		var t0: int = Time.get_ticks_usec()
		_sim.step()
		var cost: int = Time.get_ticks_usec() - t0
		_step_cost_us_ewma += (cost - _step_cost_us_ewma) / 8
		_step_cost_total_us += cost
		_step_cost_max_us = maxi(_step_cost_max_us, cost)
		_steps_timed += 1
		_tick += 1
		_acc_us -= _tick_us
		ticks += 1
		if _sim.is_match_over():
			_finish()
			break
		if _tick % NetProtocol.CHECKSUM_PERIOD_TICKS == 0:
			_call3(on_checksum, _tick, _sim.checksum_at(_tick), _chain)
	if _unpaced:
		_acc_us = 0
	else:
		_acc_us = mini(_acc_us, NetProtocol.ACC_CAP_TICKS * _tick_us)
	return ticks


func _begin_turn(e: int, b: NetBundle, now: int) -> void:
	# 1. slack: how long before it was due the bundle became executable
	if _arrival_us.has(e):
		var due_us: int = now - (_acc_us - _tick_us) if not _unpaced else now
		var slack_ms: int = clampi((due_us - int(_arrival_us[e])) / 1000, -32768, 32767)
		_rep_slack_min_ms = mini(_rep_slack_min_ms, slack_ms)
	# 2. recorder / status hook
	_call2(on_turn_begin, e, b)
	# 3. input chain
	_chain = NetProtocol.fnv1a32(b.core_bytes(), _chain)
	# 4. commands in bundle order
	for gi: int in b.pids.size():
		var pid: int = b.pids[gi]
		for c: Variant in (b.group_cmds[gi] as Array):
			_sim.submit_command(pid, c as PackedInt32Array)
	# 5. control records in order
	for cv: Variant in b.ctrl:
		var c: PackedInt32Array = cv as PackedInt32Array
		match c[0]:
			NetProtocol.CtrlKind.INPUT_DELAY:
				_delay = clampi(c[1], 1, NetProtocol.D_MAX)
			NetProtocol.CtrlKind.SPEED:
				if not _unpaced:
					_speed_pct = c[1]
			NetProtocol.CtrlKind.PAUSE:
				_pause_after_turn = e
		_call2(on_ctrl, e, c)
	# 6. fill-up and boundary hook
	var target: int = e + _delay
	_fill_up(e, target)
	_call2(on_boundary, e, target)
	# 7.
	_queue.erase(e)
	_arrival_us.erase(e)


## Spec 5.5.3: one packet per turn on average, never a gap. Commands ride only on the last packet of the loop.
func _fill_up(e: int, target: int) -> void:
	if _local_pid < 0:
		_sent_through = maxi(_sent_through, target)
		return
	while _sent_through < target:
		_sent_through += 1
		var cmds: Array = []
		if _sent_through == target:
			cmds = _take_pending()
		_call3(on_send_input, _sent_through, e, cmds)


func _take_pending() -> Array:
	var out: Array = []
	var bytes: int = 10
	while not _pending.is_empty() and out.size() < NetProtocol.MAX_CMDS_PER_TURN:
		var sz: int = _cmd_bytes(_pending[0])
		if not out.is_empty() and bytes + sz > 6144:
			break
		bytes += sz
		out.append(_pending.pop_front())
	return out


static func _varint_len(v: int) -> int:
	var n: int = 1
	while v >= 128:
		v >>= 7
		n += 1
	return n


## Encoded size of one command inside TURN_INPUT: varint(n) + zvarint per int.
static func _cmd_bytes(c: PackedInt32Array) -> int:
	var n: int = _varint_len(c.size())
	for v: int in c:
		n += _varint_len(((v << 1) ^ (v >> 31)) & 0xFFFFFFFF)
	return n


func _stall_begin(now: int) -> void:
	if _stall_since_us < 0:
		var due_us: int = now - (_acc_us - _tick_us) if not _unpaced else now
		_stall_since_us = mini(due_us, now)
		_stall_is_hitch = false
		_stall_ui = false
	var ms: int = (now - _stall_since_us) / 1000
	if ms > NetProtocol.HITCH_MS:
		_stall_is_hitch = true
	if not _stall_ui and ms >= NetProtocol.STALL_UI_MS:
		_stall_ui = true
		_call2(on_stall_changed, true, ms)


func _stall_end(now: int) -> void:
	if _stall_since_us < 0:
		return
	var ms: int = maxi((now - _stall_since_us) / 1000, 0)
	if _stall_is_hitch or ms > NetProtocol.HITCH_MS:
		_rep_hitch = true
	else:
		_rep_stall_ms += ms
		_rep_episodes += 1
	_stall_total_ms += ms
	_stall_episodes_total += 1
	var was_ui: bool = _stall_ui
	_stall_since_us = -1
	_stall_is_hitch = false
	_stall_ui = false
	if was_ui:
		_call2(on_stall_changed, false, ms)


func _finish() -> void:
	_over = true
	_call3(on_checksum, _tick, _sim.checksum_now(), _chain)
	if on_match_over.is_valid():
		on_match_over.call()


## View-only interpolation factor in [0, 1).
func tick_alpha() -> float:
	if _unpaced or _paused:
		return 0.0
	return clampf(float(_acc_us) / float(_tick_us), 0.0, 0.9999)


## pct 0 = unpaced (ignores the wall-clock accumulator, barrier still enforced); else the pacing multiplier.
func set_speed_pct(pct: int) -> void:
	if pct <= 0:
		_unpaced = true
		_speed_pct = 0
	else:
		_unpaced = false
		_speed_pct = clampi(pct, 1, 1000)


## RESUME(R) watermark (spec 5.5.8).
func resume(resume_turn: int) -> void:
	_resume_turn = maxi(_resume_turn, resume_turn)
	if _paused and _resume_turn >= _paused_at_turn:
		_paused = false
		_pause_after_turn = -1
		_last_us = _clock.now_us()
		_call1(on_pause, false)


## The turn about to begin at a boundary (current_tick / 2).
func exec_turn() -> int:
	return _tick / 2


func current_tick() -> int:
	return _tick


func delay_turns() -> int:
	return _delay


func get_speed_pct() -> int:
	return _speed_pct


func is_paused() -> bool:
	return _paused


func is_stalled() -> bool:
	return _stall_since_us >= 0


func is_over() -> bool:
	return _over


## FNV-1a chain over core_bytes of every executed turn (pre-roll included).
func input_chain() -> int:
	return _chain


## Number of local commands waiting for the next boundary.
func pending_count() -> int:
	return _pending.size()


## PONG payload since the last call, then the window restarts.
func take_report() -> Dictionary:
	var load_pct: int = clampi(_step_cost_us_ewma * 100 / _tick_us, 0, 255)
	var out: Dictionary = {
		"slack_min_ms": _rep_slack_min_ms, "stall_ms": _rep_stall_ms, "episodes": _rep_episodes,
		"hitch": _rep_hitch, "load_pct": load_pct, "exec_turn": exec_turn(),
	}
	_rep_slack_min_ms = 32767
	_rep_stall_ms = 0
	_rep_episodes = 0
	_rep_hitch = false
	return out


func stats() -> Dictionary:
	return {
		"tick": _tick, "exec_turn": exec_turn(), "delay": _delay, "speed_pct": _speed_pct, "paused": _paused,
		"stalled": is_stalled(), "over": _over, "queued": _queue.size(), "ooo": _ooo.size(), "dup_in": _dup_in,
		"ooo_in": _ooo_in, "sent_through": _sent_through, "next_push": _next_push, "chain": _chain,
		"stall_ms_total": _stall_total_ms, "stall_episodes": _stall_episodes_total,
		"step_cost_us": _step_cost_us_ewma, "pending": _pending.size(),
		"step_cost_total_us": _step_cost_total_us, "step_cost_max_us": _step_cost_max_us, "steps_timed": _steps_timed,
	}


func _call1(c: Callable, a: Variant) -> void:
	if c.is_valid():
		c.call(a)


func _call2(c: Callable, a: Variant, b: Variant) -> void:
	if c.is_valid():
		c.call(a, b)


func _call3(c: Callable, a: Variant, b: Variant, d: Variant) -> void:
	if c.is_valid():
		c.call(a, b, d)
