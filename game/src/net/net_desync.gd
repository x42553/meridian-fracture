class_name NetDesync
extends RefCounted
## Desync detection and diagnostics (docs/spec/net.md 3.7, 5.7, 7.5). Every CHECKSUM_PERIOD_TICKS each peer stores a
## snapshot (tick, checksum, input chain, sub-checksums) in a ring of 64; clients send CHECKSUM_REPORTs, the host
## compares each report with its own snapshot on arrival (reports for ticks the host has not reached yet wait in a
## pending list). The first mismatch is classified (chain / state / both), the session is told through `on_detected`
## and a diagnostic package is written to `dir` (JSON report, sim state dump, replay file, checksum CSV) with
## newest-N retention. This class does no networking and never touches the sim except through the adapter.

const RING: int = 64
const PENDING_MAX: int = 256
const LOG_LINES_MAX: int = 400
const PACKAGE_EXTS: PackedStringArray = ["json", "state.txt", "mfreplay", "checks.csv"]
const INDEX_FILE: String = "desync_index.txt"

## Host only: (tick: int, kind: int, entries: Array) -> void; entries are PackedInt64Array [pid, checksum, chain],
## the host's own entry first.
var on_detected: Callable = Callable()
## Output directory of the packages.
var dir: String = "user://desync"
## Newest packages kept.
var keep: int = 10
## Filled by the session: {peer_id, role ("host"/"client"/"local"), versions:{}, delay, rtt_ms:{}, violations, dup_in, late_in}.
var context: Dictionary = {}

var _adapter: NetSimAdapter = null
var _is_host: bool = false
var _local_pid: int = -1
var _match_id: String = ""
var _config_json: String = ""
var _ring: Dictionary = {}
var _order: PackedInt32Array = PackedInt32Array()
var _newest: int = -1
var _pending: Array = []
var _detected: bool = false
var _tick: int = -1
var _kind: int = NetProtocol.DesyncKind.NONE
var _entries: Array = []
var _parts: Dictionary = {}
var _written: Dictionary = {}


func setup(adapter: NetSimAdapter, is_host: bool, local_pid: int, match_id: String, config_json: String) -> void:
	_adapter = adapter
	_is_host = is_host
	_local_pid = local_pid
	_match_id = match_id
	_config_json = config_json
	_ring.clear()
	_order = PackedInt32Array()
	_newest = -1
	_pending.clear()
	_detected = false
	_tick = -1
	_kind = NetProtocol.DesyncKind.NONE
	_entries = []
	_parts.clear()
	_written = {}


## chain differs and checksum equal => INPUT_CHAIN; chain equal and checksum differs => SIM; both => BOTH.
static func classify(local_chain: int, remote_chain: int, local_sum: int, remote_sum: int) -> int:
	var chain_diff: bool = (local_chain & 0xFFFFFFFF) != (remote_chain & 0xFFFFFFFF)
	var sum_diff: bool = (local_sum & 0xFFFFFFFF) != (remote_sum & 0xFFFFFFFF)
	if chain_diff and sum_diff:
		return NetProtocol.DesyncKind.BOTH
	if chain_diff:
		return NetProtocol.DesyncKind.INPUT_CHAIN
	if sum_diff:
		return NetProtocol.DesyncKind.SIM
	return NetProtocol.DesyncKind.NONE


static func kind_name(kind: int) -> String:
	match kind:
		NetProtocol.DesyncKind.SIM:
			return "sim"
		NetProtocol.DesyncKind.INPUT_CHAIN:
			return "input_chain"
		NetProtocol.DesyncKind.BOTH:
			return "both"
	return "none"


func is_detected() -> bool:
	return _detected


func detected_tick() -> int:
	return _tick


func detected_kind() -> int:
	return _kind


func snapshot_count() -> int:
	return _order.size()


func has_snapshot(tick: int) -> bool:
	return _ring.has(tick)


## [checksum, chain] of a stored snapshot ([] when the ring no longer holds it).
func snapshot(tick: int) -> Array:
	if not _ring.has(tick):
		return []
	var s: Dictionary = _ring[tick] as Dictionary
	return [int(s["checksum"]), int(s["chain"])]


## Sub-checksums the local peer stored for `tick` (sent in PARTS_REQUEST by the host).
func parts_at(tick: int) -> PackedInt32Array:
	if not _ring.has(tick):
		return PackedInt32Array()
	return (_ring[tick] as Dictionary)["parts"] as PackedInt32Array


## Called from NetLockstep.on_checksum: stores checksum + chain + parts (ring of 64) and releases pending reports.
func local_snapshot(tick: int, checksum: int, chain: int) -> void:
	var parts: PackedInt32Array = PackedInt32Array()
	if _adapter != null:
		parts = _adapter.checksum_parts_at(tick)
	if not _ring.has(tick):
		_order.append(tick)
	_ring[tick] = {"checksum": checksum & 0xFFFFFFFF, "chain": chain & 0xFFFFFFFF, "parts": parts}
	_newest = maxi(_newest, tick)
	while _order.size() > RING:
		_ring.erase(_order[0])
		_order.remove_at(0)
	if _is_host and not _pending.is_empty():
		var rest: Array = []
		for p: Variant in _pending:
			var a: Array = p as Array
			if int(a[1]) <= _newest:
				if _ring.has(int(a[1])):
					_compare(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
			else:
				rest.append(a)
		_pending = rest


## Host: a CHECKSUM_REPORT from `pid`.
func on_report(pid: int, tick: int, checksum: int, chain: int) -> void:
	if not _is_host:
		return
	if _ring.has(tick):
		_compare(pid, tick, checksum, chain)
	elif tick > _newest:
		if _pending.size() >= PENDING_MAX:
			_pending.pop_front()
		_pending.append([pid, tick, checksum, chain])
	# older than the ring: ignored


func _compare(pid: int, tick: int, checksum: int, chain: int) -> void:
	var local: Dictionary = _ring[tick] as Dictionary
	var kind: int = classify(int(local["chain"]), chain, int(local["checksum"]), checksum)
	if _detected:
		if tick == _tick and kind != NetProtocol.DesyncKind.NONE and _entries.size() < 8:
			_entries.append(PackedInt64Array([pid, checksum & 0xFFFFFFFF, chain & 0xFFFFFFFF]))
		return
	if kind == NetProtocol.DesyncKind.NONE:
		return
	_detected = true
	_tick = tick
	_kind = kind
	_entries = [
		PackedInt64Array([_local_pid, int(local["checksum"]), int(local["chain"])]),
		PackedInt64Array([pid, checksum & 0xFFFFFFFF, chain & 0xFFFFFFFF]),
	]
	if on_detected.is_valid():
		on_detected.call(tick, kind, _entries.duplicate())


## Client: DESYNC_NOTICE from the host (entries: PackedInt64Array [pid, checksum, chain]).
func on_notice(tick: int, kind: int, entries: Array) -> void:
	if _detected:
		return
	_detected = true
	_tick = tick
	_kind = kind
	_entries = entries.duplicate()


## Host: PARTS_REPORT of a client; client: the host's parts from PARTS_REQUEST (`pid` = the host's pid).
func on_parts(pid: int, tick: int, parts: PackedInt32Array) -> void:
	if tick != _tick:
		return
	_parts[pid] = parts


## Pids (other than the local one) whose parts are still missing.
func missing_parts(expected: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for pid: int in expected:
		if not _parts.has(pid):
			out.append(pid)
	return out


## Names of the sub-checksums that differ between the local snapshot of the detected tick and any received parts.
func parts_diff() -> PackedStringArray:
	var names: PackedStringArray = _adapter.checksum_part_names() if _adapter != null else PackedStringArray()
	var mine: PackedInt32Array = parts_at(_tick)
	var out: PackedStringArray = PackedStringArray()
	if mine.is_empty():
		return out
	for i: int in mine.size():
		for pid: Variant in _parts:
			var theirs: PackedInt32Array = _parts[pid] as PackedInt32Array
			if i < theirs.size() and (theirs[i] & 0xFFFFFFFF) != (mine[i] & 0xFFFFFFFF):
				var nm: String = names[i] if i < names.size() else "part%d" % i
				if not out.has(nm):
					out.append(nm)
	return out


## Highest stored snapshot tick below the detected tick (0 when none).
func last_good_tick() -> int:
	var best: int = 0
	for t: int in _order:
		if t < _tick and t > best:
			best = t
	return best


func _platform() -> Dictionary:
	var v: Dictionary = Engine.get_version_info()
	return {
		"os": OS.get_name(), "arch": Engine.get_architecture_name(),
		"engine": "%d.%d.%d-%s" % [int(v.get("major", 0)), int(v.get("minor", 0)), int(v.get("patch", 0)), str(v.get("status", ""))],
		"cpus": OS.get_processor_count(),
	}


func _message() -> String:
	var secs: int = _tick / 20
	var when: String = "%02d:%02d (tick %d)" % [secs / 60, secs % 60, _tick]
	var diff: PackedStringArray = parts_diff()
	match _kind:
		NetProtocol.DesyncKind.INPUT_CHAIN:
			return "The players executed different command streams at %s." % when
		_:
			if diff.is_empty():
				return "The game states diverged at %s." % when
			return "The game states diverged at %s in: %s." % [when, ", ".join(diff)]


## The §7.5 report dictionary (without file names; write_package adds them).
func build_report(log_lines: PackedStringArray = PackedStringArray()) -> Dictionary:
	var local: Dictionary = (_ring.get(_tick, {}) as Dictionary)
	var reports: Array = []
	for e: Variant in _entries:
		var v: PackedInt64Array = e as PackedInt64Array
		if int(v[0]) == _local_pid:
			continue
		var r: Dictionary = {"pid": int(v[0]), "checksum": int(v[1]), "chain": int(v[2])}
		if _parts.has(int(v[0])):
			r["parts"] = Array(_parts[int(v[0])] as PackedInt32Array)
		reports.append(r)
	var ctx: Dictionary = context
	var names: PackedStringArray = _adapter.checksum_part_names() if _adapter != null else PackedStringArray()
	var lines: Array = Array(log_lines.slice(maxi(log_lines.size() - LOG_LINES_MAX, 0)))
	return {
		"format": 1, "kind": kind_name(_kind), "tick": _tick, "time": Time.get_datetime_string_from_system(false, true),
		"match_id": _match_id,
		"local": {
			"peer": int(ctx.get("peer_id", 1)), "pid": _local_pid, "checksum": int(local.get("checksum", 0)),
			"chain": int(local.get("chain", 0)), "parts": Array(local.get("parts", PackedInt32Array()) as PackedInt32Array),
		},
		"reports": reports, "part_names": Array(names), "parts_diff": Array(parts_diff()), "last_good_tick": last_good_tick(),
		"versions": (ctx.get("versions", {}) as Dictionary).duplicate(), "platform": _platform(),
		"net": {
			"role": str(ctx.get("role", "host" if _is_host else "client")), "delay": int(ctx.get("delay", 0)),
			"rtt_ms": (ctx.get("rtt_ms", {}) as Dictionary).duplicate(), "violations": int(ctx.get("violations", 0)),
			"dup_in": int(ctx.get("dup_in", 0)), "late_in": int(ctx.get("late_in", 0)),
		},
		"files": {}, "message": _message(), "log": lines,
	}


func _base_name() -> String:
	return "desync_%s_p%d_t%d" % [_match_id.substr(0, 8), _local_pid if _local_pid >= 0 else 255, _tick]


func _checks_csv() -> String:
	var names: PackedStringArray = _adapter.checksum_part_names() if _adapter != null else PackedStringArray()
	var rows: PackedStringArray = PackedStringArray()
	var header: PackedStringArray = PackedStringArray(["tick", "checksum", "chain"])
	header.append_array(names)
	rows.append(",".join(header))
	var ticks: Array = Array(_order)
	ticks.sort()
	for t: Variant in ticks:
		var s: Dictionary = _ring[int(t)] as Dictionary
		var cols: PackedStringArray = PackedStringArray([str(int(t)), str(int(s["checksum"])), str(int(s["chain"]))])
		for p: int in s["parts"] as PackedInt32Array:
			cols.append(str(p & 0xFFFFFFFF))
		rows.append(",".join(cols))
	return "\n".join(rows) + "\n"


func _write_text(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


## Writes the package (`<dir>/desync_<match8>_p<pid>_t<tick>.{json,state.txt,mfreplay,checks.csv}`, the replay only when
## `replay_bytes` is non-empty), applies the retention and returns the report dictionary (with `files` and `dir`).
## Writing is idempotent per (match, pid, tick).
func write_package(replay_bytes: PackedByteArray, log_lines: PackedStringArray) -> Dictionary:
	var report: Dictionary = build_report(log_lines)
	if not _detected:
		return report
	var base: String = _base_name()
	if _written.has(base):
		return _written[base] as Dictionary
	DirAccess.make_dir_recursive_absolute(dir)
	var files: Dictionary = {}
	var state_text: String = _adapter.dump_state() if _adapter != null else ""
	if _write_text(dir.path_join(base + ".state.txt"), state_text):
		files["state"] = base + ".state.txt"
	if not replay_bytes.is_empty():
		var rf: FileAccess = FileAccess.open(dir.path_join(base + ".mfreplay"), FileAccess.WRITE)
		if rf != null:
			rf.store_buffer(replay_bytes)
			rf.close()
			files["replay"] = base + ".mfreplay"
	if _write_text(dir.path_join(base + ".checks.csv"), _checks_csv()):
		files["checks"] = base + ".checks.csv"
	report["files"] = files
	report["dir"] = ProjectSettings.globalize_path(dir)
	report["config_hash"] = NetProtocol.fnv1a32(_config_json.to_utf8_buffer())
	if _write_text(dir.path_join(base + ".json"), JSON.stringify(report, "  ", true)):
		files["json"] = base + ".json"
	_record_and_retain(base)
	_written[base] = report
	return report


# ---- retention --------------------------------------------------------------------------------------------

static func _package_base(file: String) -> String:
	for ext: String in PACKAGE_EXTS:
		if file.begins_with("desync_") and file.ends_with("." + ext):
			var base: String = file.substr(0, file.length() - ext.length() - 1)
			var parts: PackedStringArray = base.split("_")
			if parts.size() == 4 and parts[2].begins_with("p") and parts[3].begins_with("t"):
				return base
	return ""


## Bases in creation order: those listed in the index file first (in file order), any unlisted ones before them by
## modified time then name.
func _bases_in_order() -> PackedStringArray:
	var on_disk: Dictionary = {}
	for f: String in DirAccess.get_files_at(dir):
		var b: String = _package_base(f)
		if not b.is_empty():
			var mt: int = FileAccess.get_modified_time(dir.path_join(f))
			on_disk[b] = maxi(int(on_disk.get(b, 0)), mt)
	var listed: PackedStringArray = PackedStringArray()
	var idx: FileAccess = FileAccess.open(dir.path_join(INDEX_FILE), FileAccess.READ)
	if idx != null:
		for line: String in idx.get_as_text().split("\n", false):
			if on_disk.has(line) and not listed.has(line):
				listed.append(line)
		idx.close()
	var unlisted: Array = []
	for b: Variant in on_disk:
		if not listed.has(str(b)):
			unlisted.append(str(b))
	unlisted.sort_custom(func(a: String, c: String) -> bool:
		var ta: int = int(on_disk[a])
		var tc: int = int(on_disk[c])
		return ta < tc or (ta == tc and a < c))
	var out: PackedStringArray = PackedStringArray()
	for b: Variant in unlisted:
		out.append(str(b))
	out.append_array(listed)
	return out


func _record_and_retain(new_base: String) -> void:
	var bases: PackedStringArray = _bases_in_order()
	if bases.has(new_base):
		bases.remove_at(bases.find(new_base))
	bases.append(new_base)
	while bases.size() > maxi(keep, 1):
		var old: String = bases[0]
		bases.remove_at(0)
		for ext: String in PACKAGE_EXTS:
			var p: String = dir.path_join(old + "." + ext)
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	_write_text(dir.path_join(INDEX_FILE), "\n".join(bases) + "\n")


## Package base names currently in `dir`, oldest first.
func package_bases() -> PackedStringArray:
	return _bases_in_order()
