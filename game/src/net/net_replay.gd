class_name NetReplay
extends RefCounted
## Replay files on disk (docs/spec/net.md 5.8): where recordings go, rotating autosave of the last matches, crash
## recovery, manual saves, the replay list with metadata and the version gate. Every function takes an optional `dir`
## (default `replay_dir()` = "user://replays") so tests and tools can work in their own folder.

const EXT: String = "mfreplay"
const DEFAULT_DIR: String = "user://replays"
const AUTOSAVE_PREFIX: String = "autosave_"
const CRASH_PREFIX: String = "crash_"
const TMP_PREFIX: String = "_recording"
const TMP_SUFFIX: String = ".mfreplay.tmp"
const NAME_MAX: int = 48
const CRASH_KEEP: int = 5
const MAX_AUTOSAVES: int = 50
## Default size cap of all autosave_N files together (the newest one is always kept).
const AUTOSAVE_MAX_BYTES: int = 256 * 1024 * 1024
## Result levels of check_versions().
const GATE_OK: int = 0
const GATE_WARN: int = 1
const GATE_REFUSE: int = 2

## Recording temp files that live recorders of this process own (so recover_orphans never touches them).
static var _active_tmp: Dictionary = {}


## The folder games record into: the user argument `--replay-dir=<dir>` when given, else "user://replays", except in headless
## processes (tests, tools), which write no replay files unless started with `--record-replays`, so a test run never
## rotates the player's autosaves.
static func default_dir() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--replay-dir="):
			return a.substr(13)
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--record-replays"):
		return ""
	return DEFAULT_DIR


## The replay directory (created on demand). `dir` "" = "user://replays".
static func replay_dir(dir: String = "") -> String:
	var d: String = dir if dir != "" else DEFAULT_DIR
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


## A fresh temp path for a recording: `<dir>/_recording_<process id>[_n].mfreplay.tmp` (unique per process and per live
## recorder, so two game instances or two in-process sessions never write the same file).
static func begin_recording_path(dir: String = "") -> String:
	var d: String = replay_dir(dir)
	var n: int = 1
	var p: String = "%s/%s_%d%s" % [d, TMP_PREFIX, OS.get_process_id(), TMP_SUFFIX]
	while _active_tmp.has(p):
		n += 1
		p = "%s/%s_%d_%d%s" % [d, TMP_PREFIX, OS.get_process_id(), n, TMP_SUFFIX]
	_active_tmp[p] = true
	return p


## Forgets a temp path (finalize_autosave / discard_recording call it).
static func release_recording_path(tmp_path: String) -> void:
	_active_tmp.erase(tmp_path)


## Deletes an unwanted recording (e.g. a match that never reached a first CHECK).
static func discard_recording(tmp_path: String) -> void:
	release_recording_path(tmp_path)
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)


## Path of autosave number `index` (1 = newest).
static func autosave_path(index: int, dir: String = "") -> String:
	return "%s/%s%d.%s" % [replay_dir(dir), AUTOSAVE_PREFIX, index, EXT]


## Rotates autosave_<keep> .. autosave_1 (delete the last, rename i -> i+1) and renames `tmp_path` to autosave_1.mfreplay in
## the temp file's folder. Files above `keep` are removed, and the oldest autosaves go while their total size exceeds
## `max_total_bytes` (0 = AUTOSAVE_MAX_BYTES; the newest is always kept). Returns the new path or "" on failure.
static func finalize_autosave(tmp_path: String, keep: int, max_total_bytes: int = 0) -> String:
	release_recording_path(tmp_path)
	if not FileAccess.file_exists(tmp_path):
		return ""
	var dir: String = tmp_path.get_base_dir()
	var k: int = clampi(keep, 1, MAX_AUTOSAVES)
	for i: int in range(MAX_AUTOSAVES, k - 1, -1):
		var old: String = autosave_path(i, dir)
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
	for i: int in range(k - 1, 0, -1):
		var src: String = autosave_path(i, dir)
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(src, autosave_path(i + 1, dir))
	var dst: String = autosave_path(1, dir)
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	if DirAccess.rename_absolute(tmp_path, dst) != OK:
		return ""
	_enforce_cap(dir, k, max_total_bytes if max_total_bytes > 0 else AUTOSAVE_MAX_BYTES)
	return dst


static func _enforce_cap(dir: String, keep: int, cap: int) -> void:
	var total: int = 0
	var sizes: PackedInt64Array = PackedInt64Array()
	for i: int in range(1, keep + 1):
		var s: int = _file_size(autosave_path(i, dir))
		sizes.append(maxi(s, 0))
		total += maxi(s, 0)
	var i2: int = keep
	while i2 > 1 and total > cap:
		var p: String = autosave_path(i2, dir)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		total -= sizes[i2 - 1]
		i2 -= 1


static func _file_size(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n: int = f.get_length()
	f.close()
	return n


## Boot-time recovery: every `_recording*.mfreplay.tmp` left by a crashed or killed run (not owned by a live recorder of
## this process, and not written to during the last `min_age_s` seconds: another running instance flushes about once per
## second of game time) becomes `crash_<unix>.mfreplay` (truncated but playable). Recordings without a single turn or
## check are deleted. At most CRASH_KEEP crash files are kept. Returns the new paths.
static func recover_orphans(dir: String = "", min_age_s: int = 120) -> PackedStringArray:
	var d: String = replay_dir(dir)
	var out: PackedStringArray = PackedStringArray()
	var da: DirAccess = DirAccess.open(d)
	if da == null:
		return out
	var now: int = int(Time.get_unix_time_from_system())
	for f: String in da.get_files():
		if not (f.begins_with(TMP_PREFIX) and f.ends_with(TMP_SUFFIX)):
			continue
		var path: String = d.path_join(f)
		if _active_tmp.has(path) or now - FileAccess.get_modified_time(path) < min_age_s:
			continue
		var data: NetReplayData = NetReplayData.load_file(path)
		if data == null or (data.turns.is_empty() and data.checks.is_empty()):
			DirAccess.remove_absolute(path)
			continue
		var dst: String = "%s/%s%d.%s" % [d, CRASH_PREFIX, now, EXT]
		var n: int = 1
		while FileAccess.file_exists(dst):
			n += 1
			dst = "%s/%s%d_%d.%s" % [d, CRASH_PREFIX, now, n, EXT]
		if DirAccess.rename_absolute(path, dst) == OK:
			out.append(dst)
	_prune_crash(d)
	return out


static func _prune_crash(dir: String) -> void:
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	var items: Array = []
	for f: String in da.get_files():
		if f.begins_with(CRASH_PREFIX) and f.ends_with("." + EXT):
			items.append([FileAccess.get_modified_time(dir.path_join(f)), f])
	items.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) > str(b[1])))
	for i: int in range(CRASH_KEEP, items.size()):
		DirAccess.remove_absolute(dir.path_join(str((items[i] as Array)[1])))


## File-name safe version of a display name: validate_filename, then only [A-Za-z0-9 _.-], no leading or trailing
## dots/spaces, at most NAME_MAX characters; "replay" when nothing is left.
static func sanitize_name(display_name: String) -> String:
	var s: String = display_name.strip_edges().validate_filename()
	var out: String = ""
	for i: int in s.length():
		var c: String = s[i]
		var u: int = c.unicode_at(0)
		var ok: bool = (u >= 48 and u <= 57) or (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or c == " " or c == "_" or c == "." or c == "-"
		out += c if ok else "_"
	while out.begins_with(".") or out.begins_with(" "):
		out = out.substr(1)
	out = out.left(NAME_MAX)
	while out.ends_with(".") or out.ends_with(" "):
		out = out.left(out.length() - 1)
	return out if out != "" else "replay"


## Copies a replay file under a sanitised name into the source file's folder (collision => name_2, name_3 ...). Returns
## the new path or "".
static func save_copy(from_path: String, display_name: String) -> String:
	if not FileAccess.file_exists(from_path):
		return ""
	var dir: String = from_path.get_base_dir()
	var base: String = sanitize_name(display_name)
	var dst: String = "%s/%s.%s" % [dir, base, EXT]
	var n: int = 1
	while FileAccess.file_exists(dst):
		n += 1
		dst = "%s/%s_%d.%s" % [dir, base, n, EXT]
	if DirAccess.copy_absolute(from_path, dst) != OK:
		return ""
	return dst


## Deletes a replay: only files named *.mfreplay directly inside the replay directory.
static func delete_replay(path: String, dir: String = "") -> bool:
	if path.get_extension() != EXT or ".." in path:
		return false
	var d: String = dir if dir != "" else DEFAULT_DIR
	if path.get_base_dir() != d.trim_suffix("/") or not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


# ---- version gate ----------------------------------------------------------------------------------------------------

## The versions this build plays (for check_versions): sim, proto, data_hash, data_ids, data_format from the session
## options; keys that are unknown stay out (and are not compared).
static func local_versions(opts: NetSessionOptions, data_ids: int = -1, data_format: int = -1) -> Dictionary:
	var v: Dictionary = {"sim": opts.sim_version, "proto": NetProtocol.PROTO_VERSION, "data_hash": opts.data_hash}
	if opts.data_handshake.is_valid():
		var hs: Dictionary = opts.data_handshake.call(false) as Dictionary
		var tables: Dictionary = hs.get("tables", {}) as Dictionary
		if tables.has("ids"):
			v["data_ids"] = int(tables["ids"])
		if hs.has("format"):
			v["data_format"] = int(hs["format"])
	if data_ids >= 0:
		v["data_ids"] = data_ids
	if data_format >= 0:
		v["data_format"] = data_format
	return v


## Compares a replay's config.versions with `local` ({} = no gate). Result {level: GATE_*, key, text}: REFUSE for a
## different sim / protocol / data format / id table (key "net.err.replay_version"), WARN when only the balance hash
## differs (key "net.warn.replay_balance"). `strict` turns every difference into a refusal.
static func check_versions(recorded: Dictionary, local: Dictionary, strict: bool = false) -> Dictionary:
	var res: Dictionary = {"level": GATE_OK, "key": "", "text": ""}
	if local.is_empty():
		return res
	for k: String in ["sim", "proto", "data_format", "data_ids"]:
		if local.has(k) and int(recorded.get(k, -1)) != int(local[k]):
			var what: String = {"sim": "simulation version", "proto": "protocol version", "data_format": "game data format", "data_ids": "game content"}[k]
			res["level"] = GATE_REFUSE
			res["key"] = "net.err.replay_version"
			res["text"] = "This replay was recorded with a different %s (recorded %d, this build %d) and cannot be played." % [what, int(recorded.get(k, -1)), int(local[k])]
			return res
	if local.has("data_hash") and (int(recorded.get("data_hash", -1)) & 0xFFFFFFFF) != (int(local["data_hash"]) & 0xFFFFFFFF):
		if strict:
			res["level"] = GATE_REFUSE
			res["key"] = "net.err.replay_version"
			res["text"] = "This replay was recorded with different game data (%08X, this build %08X)." % [int(recorded.get("data_hash", 0)) & 0xFFFFFFFF, int(local["data_hash"]) & 0xFFFFFFFF]
		else:
			res["level"] = GATE_WARN
			res["key"] = "net.warn.replay_balance"
			res["text"] = "Balance changed since recording; playback may diverge."
	return res


# ---- listing ---------------------------------------------------------------------------------------------------------

## Metadata of every *.mfreplay in `dir`, newest first (by modification time, then name). Each entry comes from
## read_info(); unreadable files are listed with valid = false.
static func list_replays(dir: String = "", local: Dictionary = {}) -> Array[Dictionary]:
	var d: String = replay_dir(dir)
	var out: Array[Dictionary] = []
	var da: DirAccess = DirAccess.open(d)
	if da == null:
		return out
	for f: String in da.get_files():
		if f.get_extension() == EXT:
			out.append(read_info(d.path_join(f), local))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["mtime"]) != int(b["mtime"]):
			return int(a["mtime"]) > int(b["mtime"])
		return str(a["path"]) < str(b["path"]))
	return out


## Metadata of one file from its header and trailer (the record stream is only scanned when the file was never
## finalised). Keys: path, name, kind ("autosave" | "crash" | "manual"), size, mtime, valid, error, match_id, map {family,
## size, seed, layout_players}, rules {start_credits, fog, ...}, players [{pid, name, roster, team, kind, color, start}], duration_ticks, duration_s, finalized,
## truncated, game_version, versions, started_unix, os, result {reason, winner_team, final_tick} ({} when not finalised),
## compatible, incompatible_reason, warning.
static func read_info(path: String, local: Dictionary = {}) -> Dictionary:
	var base: String = path.get_file().get_basename()
	var info: Dictionary = {
		"path": path, "name": base, "kind": "manual", "size": 0, "mtime": FileAccess.get_modified_time(path), "valid": false, "error": "",
		"match_id": "", "map": {}, "players": [], "duration_ticks": 0, "duration_s": 0, "finalized": false, "truncated": false,
		"game_version": "", "versions": {}, "started_unix": 0, "os": "", "result": {}, "compatible": false, "incompatible_reason": "", "warning": "",
	}
	if base.begins_with(AUTOSAVE_PREFIX):
		info["kind"] = "autosave"
	elif base.begins_with(CRASH_PREFIX):
		info["kind"] = "crash"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		info["error"] = "cannot open the file"
		return info
	var size: int = f.get_length()
	info["size"] = size
	var head: PackedByteArray = f.get_buffer(mini(size, NetReplayRecorder.HEADER_SIZE))
	var hdr_len: int = NetReplayRecorder.HEADER_SIZE
	if head.size() == NetReplayRecorder.HEADER_SIZE:
		var jl: int = head.decode_u32(8)
		if jl >= 2 and jl <= NetReplayRecorder.MAX_HEADER_JSON and hdr_len + jl <= size:
			head.append_array(f.get_buffer(jl))
	var data: NetReplayData = NetReplayData.from_header(head)
	if data == null:
		f.close()
		info["error"] = NetReplayData.last_error
		return info
	var end_info: Dictionary = {}
	if size >= hdr_len + 8 + NetReplayRecorder.END_RECORD_SIZE:
		f.seek(size - 8 - NetReplayRecorder.END_RECORD_SIZE)
		var tail: PackedByteArray = f.get_buffer(8 + NetReplayRecorder.END_RECORD_SIZE)
		end_info = _parse_tail(tail)
	f.close()
	var ticks: int = 0
	if not end_info.is_empty():
		info["finalized"] = true
		info["result"] = {"reason": int(end_info["reason"]), "winner_team": int(end_info["winner_team"]), "final_tick": int(end_info["final_tick"])}
		ticks = int(end_info["final_tick"])
	else:
		var full: NetReplayData = NetReplayData.from_bytes(FileAccess.get_file_as_bytes(path))
		if full != null:
			ticks = full.end_tick()
			info["finalized"] = full.finalized
			info["truncated"] = full.truncated
	info["valid"] = true
	info["match_id"] = data.match_id()
	info["map"] = (data.config["map"] as Dictionary).duplicate()
	info["rules"] = (data.config.get("rules", {}) as Dictionary).duplicate()
	var pl: Array = []
	for pv: Variant in data.config["players"] as Array:
		var p: Dictionary = pv as Dictionary
		pl.append({"pid": int(p["pid"]), "name": str(p["name"]), "roster": str(p["roster"]), "team": int(p["team"]), "kind": str(p["kind"]), "color": int(p["color"]), "start": int(p.get("start", p["pid"]))})
	info["players"] = pl
	info["duration_ticks"] = ticks
	info["duration_s"] = ticks / 20
	var ver: Dictionary = data.versions()
	info["versions"] = ver.duplicate()
	info["game_version"] = str(ver.get("game", ""))
	info["started_unix"] = int(data.replay_meta.get("started_unix", int(data.config.get("created_unix", 0))))
	info["os"] = str(data.replay_meta.get("os", ""))
	var gate: Dictionary = check_versions(ver, local)
	info["compatible"] = int(gate["level"]) != GATE_REFUSE
	if int(gate["level"]) == GATE_REFUSE:
		info["incompatible_reason"] = str(gate["text"])
	elif int(gate["level"]) == GATE_WARN:
		info["warning"] = str(gate["text"])
	return info


## {final_tick, reason, winner_team} when `tail` = END record + trailer, else {}.
static func _parse_tail(tail: PackedByteArray) -> Dictionary:
	if tail.size() != 8 + NetReplayRecorder.END_RECORD_SIZE:
		return {}
	var n: int = NetReplayRecorder.END_RECORD_SIZE
	if tail.decode_u32(n) != n or tail.slice(n + 4, n + 8).get_string_from_ascii() != NetReplayRecorder.END_MAGIC:
		return {}
	if tail[0] != NetProtocol.ReplayRec.END or tail[1] != NetReplayRecorder.END_PAYLOAD:
		return {}
	var r: NetReader = NetReader.new(tail, 2, n)
	var out: Dictionary = {"final_tick": r.u32(), "final_checksum": r.u32(), "final_chain": r.u32(), "reason": r.u8(), "winner_team": r.i8(), "total_turns": r.u32()}
	return out if r.ok else {}
