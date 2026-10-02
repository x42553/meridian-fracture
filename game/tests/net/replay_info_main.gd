extends SceneTree
## Prints what a .mfreplay contains: tools/gd run res://tests/net/replay_info_main.gd -- <file> [turns=N]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ""
	var d: NetReplayData = NetReplayData.load_file(path)
	if d == null:
		print("REPLAYINFO error=%s" % NetReplayData.last_error)
		quit(1)
		return
	print("REPLAYINFO turns=%d checks=%d parts=%d events=%d finalized=%s truncated=%s end=%s" % [d.turns.size(), d.check_count(), d.parts.size(), d.events.size(), str(d.finalized), str(d.truncated), str(d.end)])
	print("REPLAYINFO meta=%s" % str(d.replay_meta))
	print("REPLAYINFO map=%s versions=%s" % [str(d.config["map"]), str(d.versions())])
	for p: Variant in d.config["players"] as Array:
		print("REPLAYINFO player=%s" % str(p))
	var shown: int = 5
	for a: String in args:
		if a.begins_with("turns="):
			shown = int(a.substr(6))
	for i: int in mini(shown, d.turns.size()):
		print("REPLAYINFO turn=%d groups=%s" % [d.turns[i], str(d.groups_at(i))])
	quit(0)
