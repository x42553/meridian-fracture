class_name UiProducerPicker
extends RefCounted
## Deterministic producer choice for unit cards (ui.md 5.10.3). The sim always receives an explicit producer id.


## Producer eid for training `unit_def` in `queue_kind`, or -1 when no producer can take it. Candidates are the
## viewer's producers of the queue kind whose `check_train` is OK or UNIT_CAP, ascending ids; then: a selected
## producer wins, else the sim's primary building, else the shortest queue, then the soonest free head, then the
## lowest id.
static func pick(port: UiSimPort, queue_kind: int, unit_def: int, selected: PackedInt32Array) -> int:
	var all: PackedInt32Array = PackedInt32Array()
	port.producers(queue_kind, all)
	var cands: PackedInt32Array = PackedInt32Array()
	for p: int in all:
		var r: int = port.check_train(p, unit_def)
		if r == UiSimPort.Rule.OK or r == UiSimPort.Rule.UNIT_CAP:
			cands.append(p)
	if cands.is_empty():
		return -1
	for p: int in selected:
		if cands.has(p):
			return p
	var row := UiEntityRow.new()
	for p: int in cands:
		if port.read(p, row) and row.is_primary:
			return p
	var best: int = -1
	var best_len: int = 1 << 30
	var best_eta: int = 1 << 30
	var q := PackedInt32Array()
	var info := PackedInt32Array()
	for p: int in cands:
		var n: int = port.queue_of(p, q)
		var eta: int = 0
		if n > 0:
			port.queue_info(p, info)
			eta = info[UiSimPort.QI_ETA] if info.size() > UiSimPort.QI_ETA else 0
		if n < best_len or (n == best_len and eta < best_eta):
			best = p
			best_len = n
			best_eta = eta
	return best
