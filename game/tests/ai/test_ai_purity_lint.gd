extends RefCounted
## AI purity lint (ai.md 10.1): the AI never mutates the sim, draws only from AiRng, never reads the clock outside AiPerf,
## only AiWorldView touches the sim classes, only AiCommandBuilder knows command layouts, no net/ import outside harness/.

const DIR: String = "res://src/ai/"
## Regex patterns (a method call such as Fp.sin( or Fp.isqrt( is fine: the lookbehind rejects a preceding word char or dot).
const FORBIDDEN: PackedStringArray = [
	"(?<![\\w.])randi\\(", "(?<![\\w.])randf\\(", "(?<![\\w.])randomize\\(", "(?<![\\w.])shuffle\\(", "pick_random\\(", "\\bTime\\.",
	"OS\\.get_ticks", "(?<![\\w.])sin\\(", "(?<![\\w.])cos\\(", "(?<![\\w.])sqrt\\(", "(?<![\\w.])pow\\(", "\\bSimRng\\b",
	"world\\.events",
]
const SIM_CLASSES: PackedStringArray = ["SimWorld", "SimEntity", "SimVision", "SimCombatSystem"]
const SIM_OK: PackedStringArray = ["ai_world_view.gd", "ai_thinker.gd", "ai_controller.gd"]


func _files() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: DirAccess = DirAccess.open(DIR)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(f)
	out.sort()
	return out


func _code(path: String) -> PackedStringArray:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var out: PackedStringArray = PackedStringArray()
	for l: String in lines:
		var s: String = l.strip_edges()
		if s.begins_with("#"):
			continue
		var hash_at: int = s.find("  #")
		if hash_at >= 0:
			s = s.substr(0, hash_at)
		out.append(s)
	return out


func test_forbidden_tokens(t: TestCtx) -> void:
	var files: PackedStringArray = _files()
	t.gt(files.size(), 20, "src/ai files found")
	for f: String in files:
		if f == "ai_perf.gd":
			continue
		for line: String in _code(DIR + f):
			for tok: String in FORBIDDEN:
				var rx: RegEx = RegEx.new()
				rx.compile(tok)
				if rx.search(line) != null:
					t.fail("%s: forbidden '%s' in: %s" % [f, tok, line])


func test_no_world_writes(t: TestCtx) -> void:
	var rx: RegEx = RegEx.new()
	rx.compile("\\bworld\\.\\w+(\\.\\w+)*\\s*(=[^=]|\\+=|-=)")
	var rx2: RegEx = RegEx.new()
	rx2.compile("\\b_w\\.\\w+(\\.\\w+)*\\s*(=[^=]|\\+=|-=)")
	for f: String in _files():
		for line: String in _code(DIR + f):
			if rx.search(line) != null or rx2.search(line) != null:
				t.fail("%s assigns into the world: %s" % [f, line])


func test_sim_access_only_through_the_view(t: TestCtx) -> void:
	for f: String in _files():
		if SIM_OK.has(f):
			continue
		for line: String in _code(DIR + f):
			for c: String in SIM_CLASSES:
				if line.contains(c):
					t.fail("%s mentions %s outside ai_world_view.gd: %s" % [f, c, line])


func test_command_layouts_only_in_the_builder(t: TestCtx) -> void:
	for f: String in _files():
		if f == "ai_command_builder.gd":
			continue
		for line: String in _code(DIR + f):
			if line.contains("SimCmd.") or line.contains("SimCommand"):
				t.fail("%s encodes/decodes commands outside ai_command_builder.gd: %s" % [f, line])


func test_no_net_or_presentation_imports(t: TestCtx) -> void:
	for f: String in _files():
		for line: String in _code(DIR + f):
			if line.contains("res://src/net"):
				t.fail("%s references net/: %s" % [f, line])
			for pfx: String in ["View", "Ui", "Snd", "App", "Net"]:
				var rx: RegEx = RegEx.new()
				rx.compile("\\b" + pfx + "[A-Z]\\w*")
				if rx.search(line) != null:
					t.fail("%s references %s*: %s" % [f, pfx, line])
