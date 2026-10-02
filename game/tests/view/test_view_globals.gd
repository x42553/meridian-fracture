extends RefCounted
## VIEW-01 acceptance: globals register twice without error and agree with the .gdshaderinc declarations.

const INC_DIR: String = "res://assets/shaders/"


## Every `global uniform <type> <name>;` name found in a shader / include source, following #include lines.
static func declared_globals(path: String, out: Array[String]) -> void:
	var src: String = FileAccess.get_file_as_string(path)
	var re: RegEx = RegEx.new()
	re.compile("(?m)^\\s*global\\s+uniform\\s+\\w+\\s+(\\w+)\\s*;")
	for m: RegExMatch in re.search_all(src):
		out.append(m.get_string(1))
	var inc: RegEx = RegEx.new()
	inc.compile("(?m)^\\s*#include\\s+\"([^\"]+)\"")
	for m: RegExMatch in inc.search_all(src):
		declared_globals(m.get_string(1), out)


func test_ensure_twice_is_harmless(t: TestCtx) -> void:
	ViewGlobals.ensure()
	ViewGlobals.ensure()
	t.check(ViewGlobals.is_ready(), "ready after ensure()")
	t.eq(ViewGlobals.names().size(), 15, "15 globals of spec 4.6")
	ViewGlobals.set_value(ViewGlobals.G_ATM_NIGHT, 0.5)
	ViewGlobals.set_value(ViewGlobals.G_FOW_RECT, Vector4(0.0, 0.0, 0.01, 0.01))
	ViewGlobals.tick(0.016)
	t.gt(ViewGlobals.view_time(), 0.0, "view_time advances")
	ViewGlobals.screenshot_mode = true
	ViewGlobals.tick(0.016)
	t.eq(ViewGlobals.view_time(), 0.0, "view_time frozen at 0 in screenshot mode")
	ViewGlobals.screenshot_mode = false


func test_definitions_have_defaults(t: TestCtx) -> void:
	var defs: Array = ViewGlobals.definitions()
	t.eq(defs.size(), ViewGlobals.ALL_NAMES.size(), "one definition per name")
	for d: Array in defs:
		t.check(ViewGlobals.ALL_NAMES.has(d[0] as StringName), "%s listed" % d[0])
		t.not_null(d[2], "%s has a default" % d[0])


func test_includes_declare_each_global_once(t: TestCtx) -> void:
	var all: Array[String] = []
	for f: String in ["view_common.gdshaderinc", "fog_of_war.gdshaderinc", "atmosphere.gdshaderinc"]:
		declared_globals(INC_DIR + f, all)
	var seen: Dictionary = {}
	for n: String in all:
		t.check(not seen.has(n), "%s declared exactly once across the includes" % n)
		seen[n] = true
		t.check(ViewGlobals.ALL_NAMES.has(StringName(n)), "%s is registered by ViewGlobals" % n)
	for n: StringName in ViewGlobals.ALL_NAMES:
		if n != ViewGlobals.G_FX_LOD:  # declared by fx_common.gdshaderinc (VIEW-F1)
			t.check(seen.has(String(n)), "%s is declared by an include" % n)


func test_unit_shader_declares_each_global_once(t: TestCtx) -> void:
	var all: Array[String] = []
	declared_globals(INC_DIR + "unit.gdshader", all)
	var seen: Dictionary = {}
	for n: String in all:
		t.check(not seen.has(n), "unit.gdshader: %s declared once" % n)
		seen[n] = true
	for n: String in ["fx_time", "atm_night", "fow_curr", "fow_prev", "fow_blend", "fow_rect", "fow_cells", "fow_fog_dim"]:
		t.check(seen.has(n), "unit.gdshader sees %s" % n)
