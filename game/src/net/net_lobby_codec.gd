class_name NetLobbyCodec
extends RefCounted
## Static encode/decode of the lobby, chat and launch messages (docs/spec/net.md 3.9, 4.4): LOBBY_SNAPSHOT,
## LOBBY_ACTION, CHAT, LEAVE, KICKED, MAP_PING, LAUNCH_COUNTDOWN / ABORT / CONFIG, LOAD_PROGRESS / STATUS /
## DONE / FAILED, START, RETURN_TO_LOBBY. Same contract as NetCodec: encoders return EMPTY bytes on
## invalid input, decoders return EMPTY dictionaries (null for decode_snapshot) on any failure and never
## raise an engine error, and accepted buffers re-encode to identical bytes.
##
## The snapshot has a plain-Dictionary form (encode_snapshot_dict / decode_snapshot_dict; keys mirror the
## NetLobbyState / NetPlayerSlot fields of spec 4.5) so the codec compiles and is testable without the lobby
## model; encode_snapshot / decode_snapshot are thin adapters that read/build NetLobbyState objects by
## duck typing.

const _LAYOUTS: PackedInt32Array = [2, 4, 6, 8]
static var _class_paths: Dictionary = {}


static func _i(d: Dictionary, key: String, def: int = 0) -> int:
	return NetCodec._i(d, key, def)


static func _s(d: Dictionary, key: String) -> String:
	return NetCodec._s(d, key)


static func _w(type: int) -> NetWriter:
	return NetWriter.new().u8(type)


static func _finish(w: NetWriter, type: int) -> PackedByteArray:
	return NetCodec._finish(w, type)


static func _opt_int(opts: Variant, key: String, def: int) -> int:
	if opts == null or not (opts is Object):
		return def
	var v: Variant = (opts as Object).get(key)
	return int(v) if typeof(v) == TYPE_INT and int(v) > 0 else def


# ---- LOBBY_SNAPSHOT -------------------------------------------------------------------------------------

## Dictionary form of NetLobbyState: revision, phase, password_set, allow_spectators, host_name, map_family,
## map_size (cells), map_seed, layout_players, rules:{String->int} (<=16), speed_code, pause_policy,
## on_disconnect, auto_drop_ms, slots:Array[Dictionary] (exactly 8: kind, peer_id, name, roster_id, team,
## color, start (-1 random), handicap_pct, ready, connected, ai_level, ai_style, ai_flags, ping_ms),
## spectators:Array[Dictionary{peer_id, name}] (<=8).
static func encode_snapshot_dict(d: Dictionary) -> PackedByteArray:
	var slots: Array = d.get("slots", []) as Array
	var specs: Array = d.get("spectators", []) as Array
	var rules: Dictionary = d.get("rules", {}) as Dictionary
	var layout: int = _i(d, "layout_players", 4)
	if slots.size() != 8 or specs.size() > 8 or rules.size() > 16 or not _LAYOUTS.has(layout):
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.LOBBY_SNAPSHOT)
	w.u32(_i(d, "revision")).u8(_i(d, "phase"))
	w.u8((1 if bool(d.get("password_set", false)) else 0) | (2 if bool(d.get("allow_spectators", true)) else 0))
	w.str_(_s(d, "host_name"), 48).u8(_i(d, "map_family"))
	w.u8(clampi(_i(d, "map_size", 128) / 8, 12, 32)).u32(_i(d, "map_seed")).u8(layout).u8(rules.size())
	for k: Variant in rules:
		w.str_(str(k), 24).i32(int(rules[k]))
	w.u8(_i(d, "speed_code", 2)).u8(_i(d, "pause_policy", 1)).u8(_i(d, "on_disconnect"))
	w.u16(clampi(_i(d, "auto_drop_ms", 60000) / 1000, 0, 65535))
	for sv: Variant in slots:
		var s: Dictionary = sv as Dictionary
		w.u8(_i(s, "kind")).u16(_i(s, "peer_id")).str_(_s(s, "name"), 48).str_(_s(s, "roster_id"), 40)
		w.u8(_i(s, "team")).u8(_i(s, "color")).u8(255 if _i(s, "start", -1) < 0 else _i(s, "start"))
		w.u8(clampi(_i(s, "handicap_pct", 100) / 5, 10, 40))
		w.u8((1 if bool(s.get("ready", false)) else 0) | (2 if bool(s.get("connected", false)) else 0))
		w.u8(_i(s, "ai_level")).u8(_i(s, "ai_style")).u8(_i(s, "ai_flags")).u16(clampi(_i(s, "ping_ms"), 0, 65535))
	w.u8(specs.size())
	for spv: Variant in specs:
		var sp: Dictionary = spv as Dictionary
		w.u16(_i(sp, "peer_id")).str_(_s(sp, "name"), 48)
	return _finish(w, NetProtocol.Msg.LOBBY_SNAPSHOT)


## Range-checked decode to the Dictionary form ({} on failure). `opts` (NetSessionOptions or null) supplies
## color_count / ai_level_count / ai_style_count upper bounds (defaults 256).
static func decode_snapshot_dict(bytes: PackedByteArray, opts: Variant = null) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LOBBY_SNAPSHOT)
	if r == null:
		return {}
	var color_count: int = _opt_int(opts, "color_count", 256)
	var level_count: int = _opt_int(opts, "ai_level_count", 256)
	var style_count: int = _opt_int(opts, "ai_style_count", 256)
	var out: Dictionary = {}
	out["revision"] = r.u32()
	out["phase"] = r.u8()
	var flags: int = r.u8()
	out["password_set"] = (flags & 1) != 0
	out["allow_spectators"] = (flags & 2) != 0
	out["host_name"] = r.str_(48)
	out["map_family"] = r.u8()
	out["map_size"] = r.u8() * 8
	out["map_seed"] = r.u32()
	out["layout_players"] = r.u8()
	var rule_count: int = r.u8()
	if not r.ok or flags > 3 or int(out["phase"]) > NetProtocol.LobbyPhase.ENDED or int(out["map_family"]) > 2 \
			or not NetCodec._in(int(out["map_size"]), 96, 256) or not _LAYOUTS.has(int(out["layout_players"])) or rule_count > 16:
		return {}
	var rules: Dictionary = {}
	for _k in rule_count:
		var key: String = r.str_(24)
		var val: int = r.i32()
		if not r.ok or rules.has(key):
			return {}
		rules[key] = val
	out["rules"] = rules
	out["speed_code"] = r.u8()
	out["pause_policy"] = r.u8()
	out["on_disconnect"] = r.u8()
	out["auto_drop_ms"] = r.u16() * 1000
	if not r.ok or int(out["speed_code"]) >= NetProtocol.SPEED_PCT.size() or int(out["pause_policy"]) > NetProtocol.PausePolicy.DISABLED \
			or int(out["on_disconnect"]) > NetProtocol.OnDisconnect.AI:
		return {}
	var slots: Array = []
	for i in 8:
		var s: Dictionary = {"index": i}
		s["kind"] = r.u8()
		s["peer_id"] = r.u16()
		s["name"] = r.str_(48)
		s["roster_id"] = r.str_(40)
		s["team"] = r.u8()
		s["color"] = r.u8()
		var st: int = r.u8()
		s["start"] = -1 if st == 255 else st
		s["handicap_pct"] = r.u8() * 5
		var sf: int = r.u8()
		s["ready"] = (sf & 1) != 0
		s["connected"] = (sf & 2) != 0
		s["ai_level"] = r.u8()
		s["ai_style"] = r.u8()
		s["ai_flags"] = r.u8()
		s["ping_ms"] = r.u16()
		if not r.ok or int(s["kind"]) > NetProtocol.SlotKind.AI or int(s["team"]) > 4 or int(s["color"]) >= color_count \
				or not (st <= 7 or st == 255) or not NetCodec._in(int(s["handicap_pct"]), 50, 200) or sf > 3 \
				or int(s["ai_level"]) >= level_count or int(s["ai_style"]) >= style_count:
			return {}
		slots.append(s)
	out["slots"] = slots
	var sc: int = r.u8()
	if sc > 8:
		return {}
	var specs: Array = []
	for _k in sc:
		var pid: int = r.u16()
		var nm: String = r.str_(48)
		specs.append({"peer_id": pid, "name": nm})
	out["spectators"] = specs
	return out if r.done() else {}


static func _slot_dict(slot: Object) -> Dictionary:
	var d: Dictionary = {}
	for k: String in ["kind", "peer_id", "name", "roster_id", "team", "color", "start", "handicap_pct", "ready", "connected", "ai_level", "ai_style", "ai_flags", "ping_ms"]:
		d[k] = slot.get(k)
	return d


## Dictionary view of a NetLobbyState (duck typed; see spec 4.5 for the field names).
static func state_to_dict(state: Object) -> Dictionary:
	var d: Dictionary = {}
	for k: String in ["revision", "phase", "host_name", "password_set", "allow_spectators", "map_family", "map_size", "map_seed", "layout_players", "speed_code", "pause_policy", "on_disconnect", "auto_drop_ms"]:
		d[k] = state.get(k)
	d["rules"] = (state.get("rules") as Dictionary).duplicate()
	var slots: Array = []
	for sv: Variant in (state.get("slots") as Array):
		slots.append(_slot_dict(sv as Object))
	d["slots"] = slots
	d["spectators"] = (state.get("spectators") as Array).duplicate(true)
	return d


static func _class_path(cls: String) -> String:
	if _class_paths.is_empty():
		for e: Variant in ProjectSettings.get_global_class_list():
			_class_paths[str((e as Dictionary).get("class", ""))] = str((e as Dictionary).get("path", ""))
	return str(_class_paths.get(cls, ""))


static func _instantiate(cls: String) -> Object:
	var path: String = _class_path(cls)
	if path.is_empty():
		return null
	var scr: GDScript = load(path) as GDScript
	return null if scr == null else (scr.new() as Object)


## Builds a NetLobbyState from the Dictionary form (null when the lobby model classes are not available).
static func dict_to_state(d: Dictionary) -> Object:
	var st: Object = _instantiate("NetLobbyState")
	if st == null or d.is_empty():
		return null
	for k: String in ["revision", "phase", "host_name", "password_set", "allow_spectators", "map_family", "map_size", "map_seed", "layout_players", "rules", "speed_code", "pause_policy", "on_disconnect", "auto_drop_ms"]:
		st.set(k, d[k])
	var slots: Array = st.get("slots") as Array
	slots.clear()
	for i in 8:
		var slot: Object = _instantiate("NetPlayerSlot")
		if slot == null:
			return null
		var sd: Dictionary = (d["slots"] as Array)[i] as Dictionary
		for k: Variant in sd:
			slot.set(str(k), sd[k])
		slots.append(slot)
	st.set("spectators", d["spectators"])
	return st


## `state`: a NetLobbyState (duck typed). Empty when invalid or over MAX_SNAPSHOT.
static func encode_snapshot(state: Object) -> PackedByteArray:
	if state == null:
		return PackedByteArray()
	return encode_snapshot_dict(state_to_dict(state))


## Decodes and range-checks a snapshot into a NetLobbyState (null on any failure or out-of-range field).
static func decode_snapshot(bytes: PackedByteArray, opts: Variant = null) -> Object:
	var d: Dictionary = decode_snapshot_dict(bytes, opts)
	return null if d.is_empty() else dict_to_state(d)


# ---- LOBBY_ACTION ---------------------------------------------------------------------------------------

## args by op: SET_ROSTER {roster}, SET_TEAM {team}, SET_COLOR {color}, SET_START {start (-1 or 255 random)},
## SET_READY {ready}, SET_NAME {name}, MOVE_TO_SLOT {slot}; TO_SPECTATOR / TO_PLAYER take none.
static func encode_action(op: int, args: Dictionary) -> PackedByteArray:
	var w: NetWriter = _w(NetProtocol.Msg.LOBBY_ACTION).u8(op)
	match op:
		NetProtocol.LobbyOp.SET_ROSTER:
			w.str_(_s(args, "roster"), 40)
		NetProtocol.LobbyOp.SET_TEAM:
			w.u8(_i(args, "team"))
		NetProtocol.LobbyOp.SET_COLOR:
			w.u8(_i(args, "color"))
		NetProtocol.LobbyOp.SET_START:
			var st: int = _i(args, "start", -1)
			w.u8(255 if st < 0 else st)
		NetProtocol.LobbyOp.SET_READY:
			w.u8(1 if bool(args.get("ready", false)) else 0)
		NetProtocol.LobbyOp.SET_NAME:
			w.str_(_s(args, "name"), 48)
		NetProtocol.LobbyOp.MOVE_TO_SLOT:
			w.u8(_i(args, "slot"))
		NetProtocol.LobbyOp.TO_SPECTATOR, NetProtocol.LobbyOp.TO_PLAYER:
			pass
		_:
			return PackedByteArray()
	return _finish(w, NetProtocol.Msg.LOBBY_ACTION)


## {op, ...args} with the keys of encode_action ({} on failure; start 255 decodes to -1).
static func decode_action(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LOBBY_ACTION)
	if r == null:
		return {}
	var op: int = r.u8()
	var out: Dictionary = {"op": op}
	match op:
		NetProtocol.LobbyOp.SET_ROSTER:
			out["roster"] = r.str_(40)
		NetProtocol.LobbyOp.SET_TEAM:
			out["team"] = r.u8()
		NetProtocol.LobbyOp.SET_COLOR:
			out["color"] = r.u8()
		NetProtocol.LobbyOp.SET_START:
			var st: int = r.u8()
			if st > 7 and st != 255:
				return {}
			out["start"] = -1 if st == 255 else st
		NetProtocol.LobbyOp.SET_READY:
			var v: int = r.u8()
			if v > 1:
				return {}
			out["ready"] = v == 1
		NetProtocol.LobbyOp.SET_NAME:
			out["name"] = r.str_(48)
		NetProtocol.LobbyOp.MOVE_TO_SLOT:
			out["slot"] = r.u8()
			if int(out["slot"]) > 7:
				return {}
		NetProtocol.LobbyOp.TO_SPECTATOR, NetProtocol.LobbyOp.TO_PLAYER:
			pass
		_:
			return {}
	return out if r.done() else {}


# ---- CHAT -----------------------------------------------------------------------------------------------

static func _chat_text(r: NetReader) -> String:
	var b: PackedByteArray = r.bytes_(NetProtocol.CHAT_MAX_BYTES)
	if not r.ok:
		return ""
	if not b.is_empty() and not NetProtocol.is_valid_utf8(b, 0, b.size()):
		r.ok = false
		return ""
	return b.get_string_from_utf8()


static func _put_chat_text(w: NetWriter, text: String) -> void:
	w.bytes_(NetProtocol.truncate_utf8(text, NetProtocol.CHAT_MAX_BYTES).to_utf8_buffer())


## fields: channel (0 all, 1 team), text (<=200 UTF-8 bytes, truncated).
static func encode_chat_c2h(f: Dictionary) -> PackedByteArray:
	var ch: int = _i(f, "channel")
	if ch > 1 or ch < 0:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.CHAT).u8(ch)
	_put_chat_text(w, _s(f, "text"))
	return _finish(w, NetProtocol.Msg.CHAT)


static func decode_chat_c2h(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.CHAT)
	if r == null:
		return {}
	var ch: int = r.u8()
	var text: String = _chat_text(r)
	return {"channel": ch, "text": text} if r.done() and ch <= 1 else {}


## fields: channel, from_slot (255 = system), from_name (<=48 B), text.
static func encode_chat_h2c(f: Dictionary) -> PackedByteArray:
	var ch: int = _i(f, "channel")
	if ch > 1 or ch < 0:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.CHAT).u8(ch).u8(_i(f, "from_slot", 255)).str_(_s(f, "from_name"), 48)
	_put_chat_text(w, _s(f, "text"))
	return _finish(w, NetProtocol.Msg.CHAT)


static func decode_chat_h2c(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.CHAT)
	if r == null:
		return {}
	var ch: int = r.u8()
	var slot: int = r.u8()
	var nm: String = r.str_(48)
	var text: String = _chat_text(r)
	if not r.done() or ch > 1 or not (slot <= 7 or slot == 255):
		return {}
	return {"channel": ch, "from_slot": slot, "from_name": nm, "text": text}


# ---- LEAVE / KICKED / MAP_PING ------------------------------------------------------------------------------

## fields: reason (0 normal).
static func encode_leave(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.LEAVE).u8(_i(f, "reason")), NetProtocol.Msg.LEAVE)


static func decode_leave(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LEAVE)
	if r == null:
		return {}
	var out: Dictionary = {"reason": r.u8()}
	return out if r.done() else {}


## fields: reason (KickReason), detail (<=96 B).
static func encode_kicked(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.KICKED).u8(_i(f, "reason")).str_(_s(f, "detail"), 96), NetProtocol.Msg.KICKED)


static func decode_kicked(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.KICKED)
	if r == null:
		return {}
	var out: Dictionary = {"reason": r.u8(), "detail": r.str_(96)}
	return out if r.done() and int(out["reason"]) <= NetProtocol.KickReason.VERSION else {}


## C->H: cell_x, cell_y.
static func encode_map_ping_c2h(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.MAP_PING).u16(_i(f, "cell_x")).u16(_i(f, "cell_y")), NetProtocol.Msg.MAP_PING)


static func decode_map_ping_c2h(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.MAP_PING)
	if r == null:
		return {}
	var out: Dictionary = {"cell_x": r.u16(), "cell_y": r.u16()}
	return out if r.done() else {}


## H->C (team only): from_pid, cell_x, cell_y.
static func encode_map_ping_h2c(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.MAP_PING).u8(_i(f, "from_pid")).u16(_i(f, "cell_x")).u16(_i(f, "cell_y")), NetProtocol.Msg.MAP_PING)


static func decode_map_ping_h2c(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.MAP_PING)
	if r == null:
		return {}
	var out: Dictionary = {"from_pid": r.u8(), "cell_x": r.u16(), "cell_y": r.u16()}
	return out if r.done() and int(out["from_pid"]) <= 7 else {}


# ---- launch ---------------------------------------------------------------------------------------------

## fields: seconds_left (0 = aborted).
static func encode_launch_countdown(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.LAUNCH_COUNTDOWN).u8(_i(f, "seconds_left")), NetProtocol.Msg.LAUNCH_COUNTDOWN)


static func decode_launch_countdown(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LAUNCH_COUNTDOWN)
	if r == null:
		return {}
	var out: Dictionary = {"seconds_left": r.u8()}
	return out if r.done() else {}


## fields: reason (AbortReason), pid (255 none), detail (<=96 B).
static func encode_launch_abort(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.LAUNCH_ABORT).u8(_i(f, "reason")).u8(_i(f, "pid", 255)).str_(_s(f, "detail"), 96), NetProtocol.Msg.LAUNCH_ABORT)


static func decode_launch_abort(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LAUNCH_ABORT)
	if r == null:
		return {}
	var out: Dictionary = {"reason": r.u8(), "pid": r.u8(), "detail": r.str_(96)}
	if not r.done() or int(out["reason"]) > NetProtocol.AbortReason.HOST_CANCEL or not (int(out["pid"]) <= 7 or int(out["pid"]) == 255):
		return {}
	return out


## LAUNCH_CONFIG packet: [0x12][u32 json_len][u32 json_fnv][DEFLATE(json UTF-8)]. Empty when the JSON exceeds
## MAX_CONFIG_JSON or the packet exceeds MAX_LAUNCH_PACKET.
static func deflate_config(json: String) -> PackedByteArray:
	var raw: PackedByteArray = json.to_utf8_buffer()
	if raw.is_empty() or raw.size() > NetProtocol.MAX_CONFIG_JSON:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.LAUNCH_CONFIG).u32(raw.size()).u32(NetProtocol.fnv1a32(raw))
	w.raw(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return _finish(w, NetProtocol.Msg.LAUNCH_CONFIG)


## The inflated JSON text, or "" on ANY failure (type, sizes, bounded inflate, length and FNV verified, UTF-8).
## A corrupt DEFLATE stream makes the engine log one error (callers/tests that feed garbage declare it).
static func inflate_config(packet: PackedByteArray) -> String:
	var r: NetReader = NetCodec.open(packet, NetProtocol.Msg.LAUNCH_CONFIG)
	if r == null:
		return ""
	var json_len: int = r.u32()
	var json_fnv: int = r.u32()
	if not r.ok or json_len < 1 or json_len > NetProtocol.MAX_CONFIG_JSON or r.left() < 1:
		return ""
	var packed: PackedByteArray = r.raw(r.left())
	if not NetProtocol.looks_like_zlib(packed):
		return ""
	var raw: PackedByteArray = packed.decompress_dynamic(NetProtocol.MAX_CONFIG_JSON, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != json_len or NetProtocol.fnv1a32(raw) != json_fnv or not NetProtocol.is_valid_utf8(raw, 0, raw.size()):
		return ""
	return raw.get_string_from_utf8()


## fields: pct.
static func encode_load_progress(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.LOAD_PROGRESS).u8(clampi(_i(f, "pct"), 0, 100)), NetProtocol.Msg.LOAD_PROGRESS)


static func decode_load_progress(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LOAD_PROGRESS)
	if r == null:
		return {}
	var out: Dictionary = {"pct": r.u8()}
	return out if r.done() and int(out["pct"]) <= 100 else {}


## fields: entries:Array[PackedInt32Array [pid, pct]] (<=8).
static func encode_load_status(f: Dictionary) -> PackedByteArray:
	var entries: Array = f.get("entries", []) as Array
	if entries.size() > 8:
		return PackedByteArray()
	var w: NetWriter = _w(NetProtocol.Msg.LOAD_STATUS).u8(entries.size())
	for e: Variant in entries:
		var v: PackedInt32Array = e as PackedInt32Array
		if v.size() != 2:
			return PackedByteArray()
		w.u8(v[0]).u8(clampi(v[1], 0, 100))
	return _finish(w, NetProtocol.Msg.LOAD_STATUS)


static func decode_load_status(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LOAD_STATUS)
	if r == null:
		return {}
	var n: int = r.u8()
	if n > 8:
		return {}
	var entries: Array = []
	for _k in n:
		var pid: int = r.u8()
		var pct: int = r.u8()
		if pid > 7 or pct > 100:
			return {}
		entries.append(PackedInt32Array([pid, pct]))
	return {"entries": entries} if r.done() else {}


## fields: map_hash, checksum0.
static func encode_load_done(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.LOAD_DONE).u32(_i(f, "map_hash")).u32(_i(f, "checksum0")), NetProtocol.Msg.LOAD_DONE)


static func decode_load_done(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LOAD_DONE)
	if r == null:
		return {}
	var out: Dictionary = {"map_hash": r.u32(), "checksum0": r.u32()}
	return out if r.done() else {}


## fields: reason (AbortReason), detail (<=96 B).
static func encode_load_failed(f: Dictionary) -> PackedByteArray:
	return _finish(_w(NetProtocol.Msg.LOAD_FAILED).u8(_i(f, "reason")).str_(_s(f, "detail"), 96), NetProtocol.Msg.LOAD_FAILED)


static func decode_load_failed(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.LOAD_FAILED)
	if r == null:
		return {}
	var out: Dictionary = {"reason": r.u8(), "detail": r.str_(96)}
	return out if r.done() and int(out["reason"]) <= NetProtocol.AbortReason.HOST_CANCEL else {}


## fields: config_hash, input_delay (1..8), speed_pct (50..200).
static func encode_start(f: Dictionary) -> PackedByteArray:
	if not NetCodec._in(_i(f, "input_delay"), 1, NetProtocol.D_MAX) or not NetCodec._in(_i(f, "speed_pct", 100), 50, 200):
		return PackedByteArray()
	return _finish(_w(NetProtocol.Msg.START).u32(_i(f, "config_hash")).u8(_i(f, "input_delay")).u16(_i(f, "speed_pct", 100)), NetProtocol.Msg.START)


static func decode_start(bytes: PackedByteArray) -> Dictionary:
	var r: NetReader = NetCodec.open(bytes, NetProtocol.Msg.START)
	if r == null:
		return {}
	var out: Dictionary = {"config_hash": r.u32(), "input_delay": r.u8(), "speed_pct": r.u16()}
	if not r.done() or not NetCodec._in(int(out["input_delay"]), 1, NetProtocol.D_MAX) or not NetCodec._in(int(out["speed_pct"]), 50, 200):
		return {}
	return out


static func encode_return_to_lobby(_f: Dictionary = {}) -> PackedByteArray:
	return PackedByteArray([NetProtocol.Msg.RETURN_TO_LOBBY])


## {"type": 0x17} for a valid RETURN_TO_LOBBY (a field-less message), else {}.
static func decode_return_to_lobby(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() == 1 and bytes[0] == NetProtocol.Msg.RETURN_TO_LOBBY:
		return {"type": NetProtocol.Msg.RETURN_TO_LOBBY}
	return {}
