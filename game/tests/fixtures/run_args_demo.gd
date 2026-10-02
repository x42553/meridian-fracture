extends SceneTree
## FIXTURE used by docs/spec/qa_tooling.md and tools/py/tests: prints its user args and exits with a chosen code.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	print("ARGS=", ",".join(args))
	var code: int = 0
	for a: String in args:
		if a.begins_with("--exit="):
			code = a.substr(7).to_int()
	quit(code)
