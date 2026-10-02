class_name SimCommand
extends RefCounted
## The DECODED command record (sim_core 3.5 / 4.8); the canonical transport form is the int array
## `[op, fields..., ids...]` (see SimCmd). The pid is stamped by the caller (net: from the connection).

## Result codes of validation and executors (the integers are part of the CMD_REJECTED contract).
enum Err {
	OK = 0, UNKNOWN_OP, BAD_PLAYER, ELIMINATED, MATCH_ENDED, BAD_FIELD, NO_ACTORS, NO_TARGET, WRONG_KIND,
	NOT_AVAILABLE, NO_PREREQ, NO_CREDITS, QUEUE_FULL, BAD_SITE, NO_VISION, NOT_READY, UNIT_CAP, BLOCKED,
	DISABLED, NOT_ALLOWED, BAD_ORDER, INSIDE,
}

var op: int = 0
var pid: int = 0
var ids: PackedInt32Array = PackedInt32Array()  ## ascending, unique, > 0
# the 8 field slots; a field the op's layout does not carry is 0
var target: int = 0
var x: int = 0
var y: int = 0
var def: int = 0
var count: int = 0
var mode: int = 0
var flags: int = 0
var angle: int = 0
## An executor may set a domain-specific reason next to the Err it returns (surfaces in CMD_REJECTED.d).
var detail: int = 0
# RUNTIME: the submitted ints; actors are filled by SimCommandSystem after ownership / existence filtering.
var raw: PackedInt32Array = PackedInt32Array()
var actors: Array[SimEntity] = []
## Submission counter of the world's pending list (canonical order is (pid, _ord)).
@warning_ignore("unused_private_class_variable")  # written by SimWorld.submit_raw
var _ord: int = 0


## `[op, fields in layout order..., ids...]` (the canonical form).
func to_ints() -> PackedInt32Array:
	return SimCommandCodec.encode(self)


## Decodes `ints` for `pid`; null if malformed.
static func from_ints(p_pid: int, ints: PackedInt32Array) -> SimCommand:
	var c: SimCommand = SimCommand.new()
	c.pid = p_pid
	c.raw = ints
	if SimCommandCodec.decode(c) != Err.OK:
		return null
	return c
