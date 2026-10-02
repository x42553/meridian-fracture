class_name NetBundle
extends RefCounted
## One executed turn (docs/spec/net.md 3.4): every player's commands of turn `turn` in canonical order (pid
## ascending; within a pid, submission order) plus optional net control records. Treat as immutable after
## build()/NetCodec.decode_bundle(); the derived byte strings are cached on first use.

## Turn number (u32).
var turn: int = 0
## bit0 = has_ctrl (other bits are always 0).
var flags: int = 0
## Strictly ascending pids that have >= 1 command.
var pids: PackedInt32Array = PackedInt32Array()
## Array[Array[PackedInt32Array]] parallel to `pids`: command int arrays [type, args...].
var group_cmds: Array = []
## Array[PackedInt32Array]: control records [kind, args...] (NetProtocol.CtrlKind).
var ctrl: Array = []

var _core: PackedByteArray = PackedByteArray()
var _core_ready: bool = false
var _wire: PackedByteArray = PackedByteArray()
var _wire_ready: bool = false


## Builds a bundle (copies the containers). Invalid content is accepted here; wire_bytes() returns an
## empty array for a bundle that cannot be encoded (see is_encodable()).
static func build(turn_: int, pids_: PackedInt32Array, group_cmds_: Array, ctrl_: Array) -> NetBundle:
	var b: NetBundle = NetBundle.new()
	b.turn = turn_ & 0xFFFFFFFF
	b.pids = pids_.duplicate()
	b.group_cmds = []
	for g: Variant in group_cmds_:
		b.group_cmds.append((g as Array).duplicate())
	b.ctrl = ctrl_.duplicate()
	b.flags = 1 if not ctrl_.is_empty() else 0
	return b


## Canonical sim-relevant bytes: u32 turn | u8 groups | groups (no flags / ctrl / hash). Feeds input_chain and replay.
func core_bytes() -> PackedByteArray:
	if not _core_ready:
		_core = NetCodec.encode_turn_core(turn, pids, group_cmds)
		_core_ready = true
	return _core


## The full TURN_BUNDLE message including the trailing FNV (empty when the content is not encodable).
func wire_bytes() -> PackedByteArray:
	if not _wire_ready:
		_wire = NetCodec.encode_bundle(self)
		_wire_ready = true
	return _wire


func is_encodable() -> bool:
	return not wire_bytes().is_empty()


func command_count() -> int:
	var n: int = 0
	for g: Variant in group_cmds:
		n += (g as Array).size()
	return n


## Commands of `pid` in submission order (empty when the pid has none).
func commands_of(pid: int) -> Array:
	var i: int = pids.find(pid)
	return [] if i < 0 else (group_cmds[i] as Array)


## FNV-1a of the wire message (bytes after `type`, before the trailing hash); 0 when not encodable.
func hash32() -> int:
	var w: PackedByteArray = wire_bytes()
	if w.size() < 6:
		return 0
	return w.decode_u32(w.size() - 4)


## Seeds the caches from an already-canonical decode (used by NetCodec.decode_bundle).
func _prime(core_: PackedByteArray, wire_: PackedByteArray) -> void:
	_core = core_
	_core_ready = true
	_wire = wire_
	_wire_ready = true
