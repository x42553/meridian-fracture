class_name SimCommandCodec
extends RefCounted
## Total decoder / encoder between the wire ints and SimCommand (sim_core 3.5 / 5.5 step 3). Malformed input is
## an error code, never an engine error.


## Decodes c.raw into c's fields. Err.OK, UNKNOWN_OP or BAD_FIELD: size 1..1024, known op, at least k fields, ids
## only for M_IDS ops (n <= 512, each > 0; sorted and de-duplicated), no trailing ints otherwise.
static func decode(c: SimCommand) -> int:
	var r: PackedInt32Array = c.raw
	var n: int = r.size()
	if n < 1 or n > SimConfig.MAX_CMD_INTS:
		return SimCommand.Err.BAD_FIELD
	var op: int = r[0]
	c.op = op
	if not SimCmd.is_known(op):
		return SimCommand.Err.UNKNOWN_OP
	var lay: PackedInt32Array = SimCmd.layout_of(op)
	var k: int = lay.size()
	if n < 1 + k:
		return SimCommand.Err.BAD_FIELD
	c.target = 0
	c.x = 0
	c.y = 0
	c.def = 0
	c.count = 0
	c.mode = 0
	c.flags = 0
	c.angle = 0
	for i: int in k:
		var v: int = r[1 + i]
		match lay[i]:
			SimCmd.FT_TARGET:
				c.target = v
			SimCmd.FT_X:
				c.x = v
			SimCmd.FT_Y:
				c.y = v
			SimCmd.FT_DEF:
				c.def = v
			SimCmd.FT_COUNT:
				c.count = v
			SimCmd.FT_MODE:
				c.mode = v
			SimCmd.FT_FLAGS:
				c.flags = v
			_:
				c.angle = v
	var ids: PackedInt32Array = PackedInt32Array()
	if (SimCmd.meta_of(op) & SimCmd.M_IDS) != 0:
		var m: int = n - 1 - k
		if m > SimConfig.MAX_CMD_IDS:
			return SimCommand.Err.BAD_FIELD
		if m > 0:
			ids = r.slice(1 + k)
			for id: int in ids:
				if id <= 0:
					return SimCommand.Err.BAD_FIELD
			ids.sort()
			var w: int = 1
			for j: int in range(1, m):
				if ids[j] != ids[w - 1]:
					ids[w] = ids[j]
					w += 1
			if w != m:
				ids.resize(w)
	elif n != 1 + k:
		return SimCommand.Err.BAD_FIELD
	c.ids = ids
	return SimCommand.Err.OK


## [op, fields in layout order..., ids...].
static func encode(c: SimCommand) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.append(c.op)
	var lay: PackedInt32Array = SimCmd.layout_of(c.op)
	for ft: int in lay:
		match ft:
			SimCmd.FT_TARGET:
				out.append(c.target)
			SimCmd.FT_X:
				out.append(c.x)
			SimCmd.FT_Y:
				out.append(c.y)
			SimCmd.FT_DEF:
				out.append(c.def)
			SimCmd.FT_COUNT:
				out.append(c.count)
			SimCmd.FT_MODE:
				out.append(c.mode)
			SimCmd.FT_FLAGS:
				out.append(c.flags)
			_:
				out.append(c.angle)
	if (SimCmd.meta_of(c.op) & SimCmd.M_IDS) != 0:
		out.append_array(c.ids)
	return out
