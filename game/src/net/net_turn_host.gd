class_name NetTurnHost
extends RefCounted
## Host-only turn assembly (docs/spec/net.md 3.4, 4.6, 5.5.4-5.5.10): collects every human's TURN_INPUT (and the
## host's own fill-up plus AI commands), closes turn bundles in strict order once the barrier is satisfied, owns
## the delay policy, stall bookkeeping, pause budget, speed and drop / AI-takeover decisions. The host's
## authority is order-only: it stamps the pid from the connection, orders groups ascending by pid and picks the turn a
## late-but-legal input lands in; it never inspects ints[1:].
##
## Hooks the session wires (all optional Callables, called synchronously from evaluate()/drop_player()):
##   on_stall_info(turn: int, entries: Array)   entries = Array[PackedInt32Array [pid, StallReason, wait_ms]]; [] = clear
##   on_stall_prompt(pids: PackedInt32Array)    offer WAIT / DROP_RESIGN / DROP_AI (answer via drop_player / stall_wait)
##   on_status(pid: int, status: int, aux: int) host-local PlayerNetStatus detection (ctrl records are queued separately)
##   on_resume(resume_turn: int, by_pid: int)   send RESUME to the clients and call lockstep.resume(resume_turn) locally
##   on_takeover(pid: int)                      an AI must now play `pid` (session: NetAiRunner.add_ai(pid, TAKEOVER_AI_LEVEL, 0))
##   on_delay_changed(d: int)                   the policy queued CK_INPUT_DELAY(d)

enum InputResult { OK = 0, DUPLICATE = 1, LATE = 2, TOO_FAR = 3, WRONG_PLAYER = 4, TOO_BIG = 5, BUFFERED = 6 }

const MAX_CLOSE_PER_CALL: int = 16
const MAX_CTRL_PER_BUNDLE: int = 8
const WAIT_HOLD_MS: int = 30000
const SLOW_CPU_TURNS_BEHIND: int = 3

var on_stall_info: Callable = Callable()
var on_stall_prompt: Callable = Callable()
var on_status: Callable = Callable()
var on_resume: Callable = Callable()
var on_takeover: Callable = Callable()
var on_delay_changed: Callable = Callable()

var _clock: NetClock = null
var _role: PackedInt32Array = PackedInt32Array()
var _peer_of: PackedInt32Array = PackedInt32Array()
var _recv_through: PackedInt32Array = PackedInt32Array()
var _inputs: Array[Dictionary] = []
var _next_close: int = 0
var _inject_through: int = -1
var _ai_cmds: Dictionary = {}
var _ctrl_queue: Array[PackedInt32Array] = []
var _resign_queue: Dictionary = {}
var _delay: int = 2
var _delay_min: int = NetProtocol.D_MIN_LAN
var _delay_max: int = NetProtocol.D_MAX
var _fixed_delay: int = 0
var _d0: int = 2
var _policy: NetDelayPolicy = NetDelayPolicy.new()
var _speed_pct: int = 100
var _pause_policy: int = NetProtocol.PausePolicy.ANY_PLAYER
var _auto_drop_ms: int = NetProtocol.AUTO_DROP_DEFAULT_MS
var _on_disconnect: int = NetProtocol.OnDisconnect.RESIGN
var _paused_from: int = -1
var _pause_by: int = 255
var _pause_started_us: int = 0
var _pauses_used: PackedInt32Array = PackedInt32Array()
var _block_since_us: Dictionary = {}
var _prompted: Dictionary = {}
var _prompt_hold_until_us: Dictionary = {}
var _disc_since_us: Dictionary = {}
var _last_exec_turn: Dictionary = {}  # peer_id -> last reported exec_turn
var _block_turn: int = -1
var _last_stall_info_us: int = 0
var _stall_info_active: bool = false
var _last_eval_us: int = 0
var _last_policy_us: int = 0
var _dup_in: int = 0
var _late_in: int = 0
var _too_far_in: int = 0
var _too_big_in: int = 0
var _wrong_player_in: int = 0
var _buffered_in: int = 0
var _dropped_cmds: int = 0
var _closed_total: int = 0


func _init() -> void:
	_role.resize(NetProtocol.MAX_PLAYERS)
	_peer_of.resize(NetProtocol.MAX_PLAYERS)
	_recv_through.resize(NetProtocol.MAX_PLAYERS)
	_pauses_used.resize(NetProtocol.MAX_PLAYERS)
	for i: int in NetProtocol.MAX_PLAYERS:
		_recv_through[i] = -1
		_inputs.append({})


## cfg: {initial_delay, min_delay, max_delay, fixed_delay, speed_pct, pause_policy, auto_drop_ms, on_disconnect}
## (every key optional). Turns 0 .. initial_delay-1 are the implicit pre-roll: the first bundle this host closes
## is turn initial_delay.
func setup(clock: NetClock, cfg: Dictionary) -> void:
	_clock = clock
	_fixed_delay = int(cfg.get("fixed_delay", 0))
	_delay_min = int(cfg.get("min_delay", NetProtocol.D_MIN_LAN))
	_delay_max = int(cfg.get("max_delay", NetProtocol.D_MAX))
	_d0 = _fixed_delay if _fixed_delay > 0 else int(cfg.get("initial_delay", _delay_min))
	_d0 = clampi(_d0, 1, NetProtocol.D_MAX)
	_delay = _d0
	_speed_pct = int(cfg.get("speed_pct", 100))
	_pause_policy = int(cfg.get("pause_policy", NetProtocol.PausePolicy.ANY_PLAYER))
	_auto_drop_ms = int(cfg.get("auto_drop_ms", NetProtocol.AUTO_DROP_DEFAULT_MS))
	_on_disconnect = int(cfg.get("on_disconnect", NetProtocol.OnDisconnect.RESIGN))
	_next_close = _d0
	_inject_through = _d0 - 1
	_policy = NetDelayPolicy.new()
	_policy.configure(_delay_min, _delay_max, _turn_ms())
	_policy.reset(_clock.now_ms(), _delay)
	_last_eval_us = _clock.now_us()
	_last_policy_us = _clock.now_us()
	for i: int in NetProtocol.MAX_PLAYERS:
		if _role[i] == NetProtocol.PlayerRole.PR_HUMAN:
			_recv_through[i] = _d0 - 1


func _turn_ms() -> int:
	return maxi(NetProtocol.TURN_MS * 100 / maxi(_speed_pct, 1), 1)


## role: NetProtocol.PlayerRole. Humans start with inputs received through D0-1 (the pre-roll).
func set_player(pid: int, role: int, peer_id: int) -> void:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS:
		return
	_role[pid] = role
	_peer_of[pid] = peer_id if role == NetProtocol.PlayerRole.PR_HUMAN else 0
	if role == NetProtocol.PlayerRole.PR_HUMAN:
		_recv_through[pid] = maxi(_d0, _next_close) - 1
	else:
		_recv_through[pid] = -1
		_inputs[pid].clear()
	_disc_since_us.erase(pid)


func role_of(pid: int) -> int:
	return _role[pid]


func pid_of_peer(peer_id: int) -> int:
	for i: int in NetProtocol.MAX_PLAYERS:
		if _role[i] == NetProtocol.PlayerRole.PR_HUMAN and _peer_of[i] == peer_id:
			return i
	return -1


func _host_pid() -> int:
	return pid_of_peer(1)


func _needs_inject() -> bool:
	for i: int in NetProtocol.MAX_PLAYERS:
		if _role[i] == NetProtocol.PlayerRole.PR_AI:
			return true
		if _role[i] == NetProtocol.PlayerRole.PR_HUMAN and _peer_of[i] == 1:
			return true
	return false


static func _valid_cmds(cmds: Array) -> bool:
	if cmds.size() > NetProtocol.MAX_CMDS_PER_TURN:
		return false
	for c: Variant in cmds:
		if not (c is PackedInt32Array):
			return false
		var a: PackedInt32Array = c as PackedInt32Array
		if a.is_empty() or a.size() > NetProtocol.MAX_CMD_INTS or a[0] < 0 or a[0] > 255:
			return false
	return true


## A network TURN_INPUT (pid stamped by the caller from the peer record) or the host's own fill-up. Spec 5.5.5.
## The caller scores violations: DUPLICATE +1, TOO_FAR +3, TOO_BIG +3 (WRONG_PLAYER: none for a former player).
func on_input(pid: int, turn: int, _exec_turn: int, cmds: Array) -> int:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or _role[pid] != NetProtocol.PlayerRole.PR_HUMAN:
		_wrong_player_in += 1
		return InputResult.WRONG_PLAYER
	var inputs: Dictionary = _inputs[pid]
	if turn <= _recv_through[pid] or inputs.has(turn):
		_dup_in += 1
		return InputResult.DUPLICATE
	if turn < _next_close:
		_late_in += 1
		return InputResult.LATE
	if turn > _recv_through[pid] + NetProtocol.REORDER_WINDOW or turn > _next_close + NetProtocol.INPUT_LOOKAHEAD:
		_too_far_in += 1
		return InputResult.TOO_FAR
	if not _valid_cmds(cmds):
		_too_big_in += 1
		_store(pid, turn, [])
		return InputResult.TOO_BIG
	return InputResult.BUFFERED if _store(pid, turn, cmds) else InputResult.OK


## A TURN_INPUT of `pid` whose header (turn) was decodable but whose body was oversize / malformed: the turn counts
## as an EMPTY input so the stream stays gap-free (I1); the caller scores the sender. Undecodable header: do not call.
func on_bad_input(pid: int, turn: int) -> int:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or _role[pid] != NetProtocol.PlayerRole.PR_HUMAN:
		_wrong_player_in += 1
		return InputResult.WRONG_PLAYER
	_too_big_in += 1
	if turn > _recv_through[pid] and turn >= _next_close and not (_inputs[pid] as Dictionary).has(turn) \
			and turn <= _recv_through[pid] + NetProtocol.REORDER_WINDOW and turn <= _next_close + NetProtocol.INPUT_LOOKAHEAD:
		_store(pid, turn, [])
	return InputResult.TOO_BIG


## Stores an accepted input and drains buffered successors. Returns true when the input was out of order (buffered).
func _store(pid: int, turn: int, cmds: Array) -> bool:
	var inputs: Dictionary = _inputs[pid]
	inputs[turn] = cmds.duplicate()
	if turn != _recv_through[pid] + 1:
		_buffered_in += 1
		return true
	_recv_through[pid] = turn
	while inputs.has(_recv_through[pid] + 1):
		_recv_through[pid] += 1
	return false


## The host-local fill-up frontier: local human and AI inputs exist through `turn`.
func note_injection_through(turn: int) -> void:
	_inject_through = maxi(_inject_through, turn)


## AI commands for the bundle of `turn` (the runner calls this with target = E + D).
func add_ai_commands(turn: int, pid: int, cmds: Array) -> void:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or _role[pid] != NetProtocol.PlayerRole.PR_AI or turn < _next_close:
		_dropped_cmds += cmds.size()
		return
	if not _ai_cmds.has(turn):
		_ai_cmds[turn] = []
	(_ai_cmds[turn] as Array).append([pid, cmds])


func queue_ctrl(rec: PackedInt32Array) -> void:
	_ctrl_queue.append(rec)


## Closes every turn whose barrier is satisfied (bounded: 16 per call). Spec 5.5.4.
func close_ready() -> Array[NetBundle]:
	var out: Array[NetBundle] = []
	var now: int = _clock.now_us()
	var need_inject: bool = _needs_inject()
	while out.size() < MAX_CLOSE_PER_CALL:
		var n: int = _next_close
		if _paused_from >= 0 and n >= _paused_from:
			break
		var blocked: PackedInt32Array = PackedInt32Array()
		for pid: int in NetProtocol.MAX_PLAYERS:
			if _role[pid] == NetProtocol.PlayerRole.PR_HUMAN and _recv_through[pid] < n:
				blocked.append(pid)
		if not blocked.is_empty():
			if n != _block_turn:  # a new turn starts a new wait
				_block_since_us.clear()
				_prompted.clear()
				_block_turn = n
			_note_blocked(blocked, now)
			break
		_block_since_us.clear()
		_prompted.clear()
		if need_inject and _inject_through < n:
			break
		var pids: PackedInt32Array = PackedInt32Array()
		var groups: Array = []
		var ai_now: Array = _ai_cmds.get(n, []) as Array
		_ai_cmds.erase(n)
		for pid: int in NetProtocol.MAX_PLAYERS:
			var cmds: Array = []
			if _resign_queue.has(pid):
				cmds.append(PackedInt32Array([NetProtocol.T_RESIGN, int(_resign_queue[pid])]))
				_resign_queue.erase(pid)
			if _role[pid] == NetProtocol.PlayerRole.PR_HUMAN:
				cmds.append_array((_inputs[pid] as Dictionary).get(n, []) as Array)
				(_inputs[pid] as Dictionary).erase(n)
			elif _role[pid] == NetProtocol.PlayerRole.PR_AI:
				for g: Variant in ai_now:
					if int((g as Array)[0]) == pid:
						cmds.append_array((g as Array)[1] as Array)
			if cmds.size() > NetProtocol.MAX_CMDS_PER_TURN:
				_dropped_cmds += cmds.size() - NetProtocol.MAX_CMDS_PER_TURN
				cmds = cmds.slice(0, NetProtocol.MAX_CMDS_PER_TURN)
			if not cmds.is_empty():
				pids.append(pid)
				groups.append(cmds)
		var ctrl: Array = []
		while not _ctrl_queue.is_empty() and ctrl.size() < MAX_CTRL_PER_BUNDLE:
			ctrl.append(_ctrl_queue.pop_front())
		out.append(NetBundle.build(n, pids, groups, ctrl))
		_next_close = n + 1
		_closed_total += 1
		for c: Variant in ctrl:
			if (c as PackedInt32Array)[0] == NetProtocol.CtrlKind.PAUSE:
				_paused_from = n + 1
				_pause_started_us = now
	# drop AI commands that can no longer be used
	for t: Variant in _ai_cmds.keys():
		if int(t) < _next_close:
			_ai_cmds.erase(t)
	return out


func _note_blocked(blocked: PackedInt32Array, now: int) -> void:
	for pid: int in blocked:
		if not _block_since_us.has(pid):
			_block_since_us[pid] = now
	for k: Variant in _block_since_us.keys():
		if not blocked.has(int(k)):
			_block_since_us.erase(k)
			_prompted.erase(k)


## Called by the session for each PONG of a remote human. sample: {rtt_ms, slack_min_ms, stall_ms, episodes, hitch,
## exec_turn, load_pct}.
func on_pong(peer_id: int, sample: Dictionary) -> void:
	_last_exec_turn[peer_id] = int(sample.get("exec_turn", 0))
	if _fixed_delay > 0:
		return
	_policy.feed_pong(peer_id, _clock.now_ms(), int(sample.get("rtt_ms", 0)), int(sample.get("slack_min_ms", 0)),
		int(sample.get("stall_ms", 0)), int(sample.get("episodes", 0)), bool(sample.get("hitch", false)))


## Delay policy, stall info / prompts, pause budget, auto-drop, disconnect grace. Call every poll (cheap).
func evaluate(now_us: int) -> void:
	var now_ms: int = now_us / 1000
	# 1. delay policy
	if _fixed_delay <= 0 and now_us - _last_policy_us >= NetProtocol.DELAY_EVAL_MS * 1000:
		_last_policy_us = now_us
		var want: int = _policy.evaluate(now_ms, _delay)
		if want != _delay:
			_delay = want
			_ctrl_queue.append(PackedInt32Array([NetProtocol.CtrlKind.INPUT_DELAY, want]))
			if on_delay_changed.is_valid():
				on_delay_changed.call(want)
	# 2. stall info (every 250 ms while someone blocks >= 400 ms) + clear message
	var entries: Array = []
	for k: Variant in _block_since_us:
		var wait_ms: int = (now_us - int(_block_since_us[k])) / 1000
		if wait_ms >= NetProtocol.STALL_UI_MS:
			entries.append(PackedInt32Array([int(k), _reason_of(int(k)), wait_ms]))
	if not entries.is_empty():
		if now_us - _last_stall_info_us >= NetProtocol.STALL_INFO_PERIOD_MS * 1000 or not _stall_info_active:
			_last_stall_info_us = now_us
			_stall_info_active = true
			if on_stall_info.is_valid():
				on_stall_info.call(_next_close, entries)
	elif _stall_info_active:
		_stall_info_active = false
		if on_stall_info.is_valid():
			on_stall_info.call(_next_close, [])
	# 3. prompts
	var prompt: PackedInt32Array = PackedInt32Array()
	for pid: int in NetProtocol.MAX_PLAYERS:
		if _role[pid] != NetProtocol.PlayerRole.PR_HUMAN or _prompted.has(pid):
			continue
		if int(_prompt_hold_until_us.get(pid, 0)) > now_us:
			continue
		var blocked_ms: int = (now_us - int(_block_since_us[pid])) / 1000 if _block_since_us.has(pid) else -1
		if blocked_ms >= NetProtocol.STALL_PROMPT_MS or _disc_since_us.has(pid):
			_prompted[pid] = true
			prompt.append(pid)
	if not prompt.is_empty() and on_stall_prompt.is_valid():
		on_stall_prompt.call(prompt)
	# 4. automatic drop
	if _auto_drop_ms > 0:
		for pid: int in NetProtocol.MAX_PLAYERS:
			if _role[pid] != NetProtocol.PlayerRole.PR_HUMAN:
				continue
			if _disc_since_us.has(pid):
				if (now_us - int(_disc_since_us[pid])) / 1000 >= mini(_auto_drop_ms, NetProtocol.DISCONNECT_ACT_MS):
					_auto_drop(pid, NetProtocol.ResignReason.DISCONNECT)
			elif _block_since_us.has(pid) and (now_us - int(_block_since_us[pid])) / 1000 >= _auto_drop_ms:
				_auto_drop(pid, NetProtocol.ResignReason.TIMEOUT)
	# 5. pause expiry
	if _paused_from >= 0 and (now_us - _pause_started_us) / 1000 >= NetProtocol.MAX_PAUSE_MS:
		resume_pause(255)


func _auto_drop(pid: int, reason: int) -> void:
	var mode: int = NetProtocol.StallAction.STALL_DROP_AI if _on_disconnect == NetProtocol.OnDisconnect.AI \
			else NetProtocol.StallAction.STALL_DROP_RESIGN
	drop_player(pid, mode, reason)


func _reason_of(pid: int) -> int:
	if _disc_since_us.has(pid):
		return NetProtocol.StallReason.DISCONNECTED
	var peer: int = _peer_of[pid]
	if _last_exec_turn.has(peer) and int(_last_exec_turn[peer]) <= _next_close - _delay - SLOW_CPU_TURNS_BEHIND:
		return NetProtocol.StallReason.SLOW_CPU
	return NetProtocol.StallReason.NETWORK


## PAUSE_REQUEST from human `pid`. Returns NetProtocol.PauseError.
func request_pause(pid: int, want_paused: bool) -> int:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or _role[pid] != NetProtocol.PlayerRole.PR_HUMAN:
		return NetProtocol.PauseError.NOT_ALLOWED
	var is_host: bool = pid == _host_pid()
	if not want_paused:
		if pid != _pause_by and not is_host:
			return NetProtocol.PauseError.NOT_ALLOWED
		return resume_pause(pid)
	match _pause_policy:
		NetProtocol.PausePolicy.DISABLED:
			return NetProtocol.PauseError.NOT_ALLOWED
		NetProtocol.PausePolicy.HOST_ONLY:
			if not is_host:
				return NetProtocol.PauseError.NOT_ALLOWED
	if _paused_from >= 0 or _pause_pending():
		return NetProtocol.PauseError.ALREADY
	if not is_host and _pauses_used[pid] >= NetProtocol.MAX_PAUSES_PER_PLAYER:
		return NetProtocol.PauseError.BUDGET_EXHAUSTED
	_pauses_used[pid] += 1
	_pause_by = pid
	_ctrl_queue.append(PackedInt32Array([NetProtocol.CtrlKind.PAUSE, pid]))
	return NetProtocol.PauseError.OK


func _pause_pending() -> bool:
	for c: PackedInt32Array in _ctrl_queue:
		if c[0] == NetProtocol.CtrlKind.PAUSE:
			return true
	return false


## Cancels a pause still waiting in the ctrl queue (the pause never happens) or resumes an active one
## (RESUME(resume_turn = paused_from)). Nothing pending, nothing active: NOT_ALLOWED.
func resume_pause(by_pid: int) -> int:
	for i: int in _ctrl_queue.size():
		if _ctrl_queue[i][0] == NetProtocol.CtrlKind.PAUSE:
			_ctrl_queue.remove_at(i)
			_pause_by = 255
			return NetProtocol.PauseError.OK
	if _paused_from >= 0:
		var r: int = _paused_from
		_paused_from = -1
		_pause_by = 255
		if on_resume.is_valid():
			on_resume.call(r, by_pid)
		return NetProtocol.PauseError.OK
	return NetProtocol.PauseError.NOT_ALLOWED


func pauses_used(pid: int) -> int:
	return _pauses_used[pid]


func is_pause_active() -> bool:
	return _paused_from >= 0


## Queues CK_SPEED(pct) (pct must be one of NetProtocol.SPEED_PCT).
func set_speed(speed_pct: int) -> void:
	if not NetProtocol.SPEED_PCT.has(speed_pct):
		return
	_speed_pct = speed_pct
	_policy.configure(_delay_min, _delay_max, _turn_ms())
	_ctrl_queue.append(PackedInt32Array([NetProtocol.CtrlKind.SPEED, speed_pct]))


## mode: NetProtocol.StallAction (STALL_DROP_RESIGN / STALL_DROP_AI); reason: NetProtocol.ResignReason.
## RESIGN: T_RESIGN goes first into the pid's group of the next closable turn, together with
## CK_PLAYER_STATUS(pid, DROPPED, reason). AI: the pid leaves the barrier, buffered inputs are discarded and the
## takeover status is queued; on_takeover(pid) tells the session to create the AI.
func drop_player(pid: int, mode: int, reason: int) -> void:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or _role[pid] != NetProtocol.PlayerRole.PR_HUMAN:
		return
	if mode == NetProtocol.StallAction.STALL_WAIT:
		stall_wait(pid)
		return
	var peer: int = _peer_of[pid]
	_recv_through[pid] = -1
	(_inputs[pid] as Dictionary).clear()
	_block_since_us.erase(pid)
	_prompted.erase(pid)
	_disc_since_us.erase(pid)
	_peer_of[pid] = 0
	_policy.remove_peer(peer)
	if mode == NetProtocol.StallAction.STALL_DROP_AI:
		_role[pid] = NetProtocol.PlayerRole.PR_AI
		_ctrl_queue.append(PackedInt32Array([NetProtocol.CtrlKind.PLAYER_STATUS, pid, NetProtocol.PlayerNetStatus.AI_TAKEOVER,
			NetProtocol.TAKEOVER_AI_LEVEL]))
		_notify_status(pid, NetProtocol.PlayerNetStatus.AI_TAKEOVER, NetProtocol.TAKEOVER_AI_LEVEL)
		if on_takeover.is_valid():
			on_takeover.call(pid)
	else:
		_role[pid] = NetProtocol.PlayerRole.PR_DROPPED
		_resign_queue[pid] = reason
		var status: int = NetProtocol.PlayerNetStatus.DROPPED
		_ctrl_queue.append(PackedInt32Array([NetProtocol.CtrlKind.PLAYER_STATUS, pid, status, reason]))
		_notify_status(pid, status, reason)


## A human left cleanly (LEAVE): the on_disconnect policy applies (resign or AI takeover); status LEFT for resign.
func player_left(pid: int) -> void:
	if pid < 0 or pid >= NetProtocol.MAX_PLAYERS or _role[pid] != NetProtocol.PlayerRole.PR_HUMAN:
		return
	if _on_disconnect == NetProtocol.OnDisconnect.AI:
		drop_player(pid, NetProtocol.StallAction.STALL_DROP_AI, NetProtocol.ResignReason.DISCONNECT)
		return
	drop_player(pid, NetProtocol.StallAction.STALL_DROP_RESIGN, NetProtocol.ResignReason.DISCONNECT)
	# replace the DROPPED status record by LEFT
	for i: int in range(_ctrl_queue.size() - 1, -1, -1):
		var c: PackedInt32Array = _ctrl_queue[i]
		if c[0] == NetProtocol.CtrlKind.PLAYER_STATUS and c[1] == pid:
			c[2] = NetProtocol.PlayerNetStatus.LEFT
			_ctrl_queue[i] = c
			_notify_status(pid, NetProtocol.PlayerNetStatus.LEFT, NetProtocol.ResignReason.DISCONNECT)
			break


## The host chose WAIT in the stall prompt: suppress this pid's prompt for 30 s.
func stall_wait(pid: int) -> void:
	_prompted.erase(pid)
	_prompt_hold_until_us[pid] = _clock.now_us() + WAIT_HOLD_MS * 1000


## The transport lost `peer_id`: the human stays in the barrier (reason DISCONNECTED) until it is dropped.
func peer_disconnected(peer_id: int) -> void:
	var pid: int = pid_of_peer(peer_id)
	if pid < 0:
		return
	if not _disc_since_us.has(pid):
		_disc_since_us[pid] = _clock.now_us()
		_notify_status(pid, NetProtocol.PlayerNetStatus.DISCONNECTED, 0)
	_policy.remove_peer(peer_id)


func _notify_status(pid: int, status: int, aux: int) -> void:
	if on_status.is_valid():
		on_status.call(pid, status, aux)


## Players that blocked the last close_ready() attempt: Array[{pid, reason (StallReason), wait_ms}].
func waiting() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now: int = _clock.now_us()
	for pid: int in NetProtocol.MAX_PLAYERS:
		if _block_since_us.has(pid):
			out.append({"pid": pid, "reason": _reason_of(pid), "wait_ms": (now - int(_block_since_us[pid])) / 1000})
	return out


func next_close_turn() -> int:
	return _next_close


func delay_turns() -> int:
	return _delay


func recv_through(pid: int) -> int:
	return _recv_through[pid]


func stats() -> Dictionary:
	return {
		"next_close": _next_close, "delay": _delay, "speed_pct": _speed_pct, "closed": _closed_total,
		"recv_through": _recv_through.duplicate(), "dup_in": _dup_in, "late_in": _late_in, "too_far_in": _too_far_in,
		"too_big_in": _too_big_in, "wrong_player_in": _wrong_player_in, "buffered_in": _buffered_in,
		"dropped_cmds": _dropped_cmds, "paused_from": _paused_from, "pause_by": _pause_by,
		"pauses_used": _pauses_used.duplicate(), "waiting": _block_since_us.size(), "inject_through": _inject_through,
	}


## Virtual hook: called for every bundle sent to a client; tests override it to inject relay faults (e.g. swap two
## commands => INPUT_CHAIN desync). Default: identity.
func _bundle_for_peer(b: NetBundle, _peer_id: int) -> NetBundle:
	return b
