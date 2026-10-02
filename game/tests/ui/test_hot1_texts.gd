extends RefCounted
## HOT1: every key the shipped texts name (the tutorial, the missions, the loading tips, the HUD hints) is a default binding of a registered
## action that is probed in `test_hot1_keys.gd`. The tutorial used to say "press F5, Y and Space" for keys nothing handled.

const KEYS := preload("res://tests/ui/test_hot1_keys.gd")

## Key text -> the action it must be bound to by default. A key a text names that is missing here fails: check the binding, then add it.
const ACTION_OF: Dictionary = {
	"F1": "open_field_manual", "F5": "power_1", "F8": "superweapon", "Space": "cam_jump_alert", "Home": "cam_center_base",
	"Delete": "tool_sell", "Ctrl+1": "group_assign_1", "Ctrl+A": "sel_all_military", "PageUp": "cam_tilt_up", "PageDown": "cam_tilt_down",
	"A": "cmd_attack_move", "Y": "cmd_force_fire_mode", "S": "cmd_stop", "X": "cmd_scatter", "H": "cmd_hold", "F": "tool_rally",
	"C": "sel_collector_next", "R": "tool_repair", "W": "tool_waypoint", "Q": "cam_rotate_left", "E": "cam_rotate_right",
}

const ALIAS: Dictionary = {"Ctrl+number": "Ctrl+1"}  ## generic wording for a family of keys: checked through its first member

const MISSION_DIR: String = "res://data/missions"
const TIPS: String = "res://data/text/tips_en.json"


func _strings(v: Variant, out: Array[String]) -> void:
	if v is String:
		out.append(v as String)
	elif v is Dictionary:
		for k: Variant in (v as Dictionary):
			_strings((v as Dictionary)[k], out)
	elif v is Array:
		for x: Variant in v as Array:
			_strings(x, out)


## Key names inside one text: named keys, Ctrl/Alt/Shift chords, "press X" / "hold X" and "X stops|scatters|holds|selects".
func keys_in(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var res: Array[String] = [
		"\\b(F\\d{1,2}|Space|Home|Delete|Page ?Up|Page ?Down|(?:Ctrl|Alt|Shift)\\+[A-Za-z0-9]+)\\b",
		"\\b(?:[Pp]ress|[Hh]old|[Tt]oggle it with) ([A-Z])\\b",
		"(?:^|[ .,;(])([A-Z]) (?:stops|scatters|holds|selects)\\b",
		"\\b([QE]) and ([QE])\\b",
	]
	for pat: String in res:
		var rx: RegEx = RegEx.new()
		rx.compile(pat)
		for m: RegExMatch in rx.search_all(text):
			for g: int in range(1, m.get_group_count() + 1):
				if m.get_string(g) != "":
					out.append(m.get_string(g).replace(" ", ""))
	return out


func test_keys_named_in_texts_are_bound_and_handled(t: TestCtx) -> void:
	var texts: Array[String] = []
	for f: String in DirAccess.get_files_at(MISSION_DIR):
		if f.ends_with(".json"):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MISSION_DIR.path_join(f)))
			if t.check(d != null, "%s parses" % f):
				_strings(d, texts)
	_strings(JSON.parse_string(FileAccess.get_file_as_string(TIPS)), texts)
	var km: UiKeymap = UiKeymap.instance()
	var probes: Dictionary = KEYS.new()._player_probes()
	var named: int = 0
	for text: String in texts:
		for key: String in keys_in(text):
			named += 1
			key = String(ALIAS.get(key, key))
			if not t.check(ACTION_OF.has(key), "the texts name the key '%s' (\"%s ...\"): add it to ACTION_OF after checking its binding" % [key, text.left(60)]):
				continue
			var action: String = ACTION_OF[key]
			var want: int = UiActions.parse_chord(key)
			t.check(km.bindings(StringName(action)).has(want), "'%s' is a default key of %s (\"%s ...\")" % [key, action, text.left(50)])
			t.check(probes.has(action), "%s, named by a text, has a key probe in test_hot1_keys.gd" % action)
	t.ge(named, 15, "the texts name at least the keys the tutorial teaches")


func test_texts_do_not_claim_what_does_not_exist(t: TestCtx) -> void:
	var texts: Array[String] = []
	for f: String in DirAccess.get_files_at(MISSION_DIR):
		if f.ends_with(".json"):
			_strings(JSON.parse_string(FileAccess.get_file_as_string(MISSION_DIR.path_join(f))), texts)
	_strings(JSON.parse_string(FileAccess.get_file_as_string(TIPS)), texts)
	for text: String in texts:
		t.check(not text.to_lower().contains("hold the space"), "no text asks to hold Space (a press jumps): %s" % text.left(60))
		t.check(not text.to_lower().contains("not connected"), "no text mentions an unconnected key: %s" % text.left(60))
