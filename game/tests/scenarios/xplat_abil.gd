extends SceneTree
## Cross-platform determinism scenario for the abilities / vision domain (abilities 10.3 D3).
##   python3 tools/py/xplat_determinism.py res://tests/scenarios/xplat_abil.gd
## The composite scenario of tests/support/abil_scenario.gd (4 players: camouflage, detectors, submarine, turrets,
## timed and conditional effects, temporary reveals, a capture and a kill; 1200 ticks) with fog on, then a short run with
## fog off. `HASH tick=<n> <hex>` lines: every checkpoint of `world.checksum_log` (run 2 offset by 5000) plus the final
## checksum, the event digest, a digest of dump_state() and the vision digests (ticks 9001-9006). Self-check: two runs.

const S := preload("res://tests/support/abil_scenario.gd")


func _initialize() -> void:
	var first: PackedStringArray = _run()
	var second: PackedStringArray = _run()
	if first != second:
		printerr("SELFCHECK FAILED: two runs in one process differ")
		quit(1)
		return
	for line: String in first:
		print(line)
	print("SCENARIO_DONE lines=%d" % first.size())
	quit(0)


func _run() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var w1: SimWorld = S.build(true)
	for s: int in 1200:
		S.script(w1, s)
		w1.step()
	_report(out, w1, 0, 9000)
	var digest: int = Checksum.FNV_OFFSET
	for g: int in w1.vision.n_groups():
		digest = Checksum.mix(digest, w1.vision.vis[g].digest)
		digest = Checksum.mix(digest, w1.vision.det[g].digest)
		digest = Checksum.mix(digest, w1.vision.explored_digest[g])
		digest = Checksum.mix(digest, Checksum.fnv_string(w1.vision.fog[g].hex_encode()))
	out.append("HASH tick=9004 %08x" % (digest & 0xFFFFFFFF))
	out.append("HASH tick=9005 %08x" % w1.abilities.timer_digest)
	out.append("HASH tick=9006 %08x" % w1.vision.debug_rebuild_compare(w1))
	var w2: SimWorld = S.build(false)
	for s2: int in 300:
		S.script(w2, s2)
		w2.step()
	_report(out, w2, 5000, 9100)
	return out


func _report(out: PackedStringArray, w: SimWorld, tick_offset: int, tail_base: int) -> void:
	var i: int = 0
	while i + 1 < w.checksum_log.size():
		out.append("HASH tick=%d %08x" % [tick_offset + w.checksum_log[i], w.checksum_log[i + 1]])
		i += 2
	out.append("HASH tick=%d %08x" % [tail_base + 1, w.checksum()])
	out.append("HASH tick=%d %08x" % [tail_base + 2, w.events.digest()])
	out.append("HASH tick=%d %08x" % [tail_base + 3, Checksum.fnv_string(w.dump_state())])
