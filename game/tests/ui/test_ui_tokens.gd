extends RefCounted
## Design tokens vs `style.json` (art test U-1) and the contrast ratios of ui.md 4.6.4 / 5.19.4 (`test_ui_tokens`).

const STYLE: String = "res://data/recipes/style.json"


func _style() -> Dictionary:
	var f: FileAccess = FileAccess.open(STYLE, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d as Dictionary if d is Dictionary else {}


func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k: Variant in da:
			if not db.has(k) or not _same(da[k], db[k]):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _same(aa[i], ab[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) < 0.00001
	return a == b


func test_palette_equals_style_tokens(t: TestCtx) -> void:
	var tokens: Dictionary = (_style().get("ui", {}) as Dictionary).get("tokens", {})
	if not t.check(tokens.size() == 18, "style.ui.tokens has 18 entries"):
		return
	for n: String in tokens:
		var want: Color = Color(String(tokens[n]))
		var got: Color = UiPalette.token(StringName(n))
		t.check(got.is_equal_approx(want), "%s: palette %s vs json %s" % [n, got.to_html(), want.to_html()])
	t.eq(UiPalette.TOKEN_NAMES.size(), 18)


func test_skins_equal_style(t: TestCtx) -> void:
	var st: Dictionary = _style()
	var skin_defs: Dictionary = (st.get("ui", {}) as Dictionary).get("skins", {})
	var skins := UiSkinSet.new()
	skins.setup_from_json()
	for code: String in skin_defs:
		var d: Dictionary = skin_defs[code]
		var s: UiSkin = skins.skin_for(code)
		t.check(s.accent.is_equal_approx(Color(String(d["accent"]))), "%s accent" % code)
		t.check(s.accent2.is_equal_approx(Color(String(d["accent2"]))), "%s accent2" % code)
		t.check(s.tint.is_equal_approx(Color(String(d["tint"]))), "%s tint" % code)
		var b: UiSkin = UiSkin.builtin(code)
		t.check(b.accent.is_equal_approx(s.accent) and b.tint.is_equal_approx(s.tint), "%s builtin == json" % code)
	t.eq(skin_defs.size(), UiSkin.CODES.size())
	t.check(UiSkin.neutral().accent.is_equal_approx(Color("#7fb0e6")), "neutral accent")


func test_chrome_equals_style(t: TestCtx) -> void:
	var chrome: Dictionary = (_style().get("ui", {}) as Dictionary).get("chrome", {})
	var s: UiSkin = UiSkin.neutral()
	t.check(_same(UiTheme.chrome(s), chrome), "UiTheme.chrome (defaults) equals style.ui.chrome")
	var skins := UiSkinSet.new()
	skins.setup_from_json()
	t.check(_same(UiTheme.chrome(skins.skin_for("han")), chrome), "chrome through the JSON-backed skin set")
	# a JSON lacking a key still yields the full table
	var merged: Dictionary = UiSkin.merge_chrome({"grid_px": 8, "button": {"cut_px": 9}})
	t.eq(int(merged["grid_px"]), 8)
	t.eq(int((merged["button"] as Dictionary)["cut_px"]), 9)
	t.check((merged["button"] as Dictionary).has("hover"), "unspecified button keys kept")


func test_contrast_ratios(t: TestCtx) -> void:
	var c: Dictionary = UiTheme.colors()
	var tk: Dictionary = c["tokens"]
	var panel: Color = tk["BG_PANEL"]
	t.near(UiA11y.contrast_ratio(tk["TEXT"], panel), 16.30, 0.05, "TEXT on BG_PANEL")
	t.near(UiA11y.contrast_ratio(tk["TEXT_DIM"], panel), 7.82, 0.05, "TEXT_DIM")
	t.near(UiA11y.contrast_ratio(tk["TEXT_MUTE"], panel), 5.53, 0.05, "TEXT_MUTE")
	t.near(UiA11y.contrast_ratio(tk["TEXT_MUTE"], tk["BG_CONTROL"]), 4.64, 0.05, "TEXT_MUTE on BG_CONTROL")
	t.near(UiA11y.contrast_ratio(tk["LINE_BRIGHT"], panel), 4.28, 0.05, "LINE_BRIGHT")
	t.near(UiA11y.contrast_ratio(tk["TEXT_DISABLED"], panel), 3.70, 0.05, "TEXT_DISABLED")
	t.near(UiA11y.contrast_ratio(tk["TEXT"], tk["BG_HOVER"]), 11.27, 0.05, "TEXT on BG_HOVER")
	t.near(UiA11y.contrast_ratio(tk["TEXT_DIM"], tk["BG_HOVER"]), 5.41, 0.05, "TEXT_DIM on BG_HOVER")
	t.near(UiA11y.contrast_ratio(tk["LINE"], panel), 1.98, 0.05, "LINE")
	t.near(UiA11y.contrast_ratio(tk["CREDITS"], panel), 13.39, 0.05, "CREDITS")
	t.near(UiA11y.contrast_ratio(tk["DANGER"], panel), 6.08, 0.05, "DANGER")
	# TEXT_MUTE stays >= 4.5 on panel surfaces; the documented exception is BG_HOVER
	t.check(UiA11y.contrast_ratio(tk["TEXT_MUTE"], tk["BG_HOVER"]) < 4.5, "TEXT_MUTE is not used on BG_HOVER (3.83)")


func test_accent_contrast(t: TestCtx) -> void:
	var c: Dictionary = UiTheme.colors()
	var accents: Dictionary = c["accents"]
	var worst: float = 99.0
	var worst_on: float = 99.0
	for code: String in accents:
		var a: Color = accents[code]
		var r: float = UiA11y.contrast_ratio(a, UiPalette.BG_PANEL)
		worst = minf(worst, r)
		t.check(r >= 4.5, "%s accent %.2f >= 4.5 on BG_PANEL" % [code, r])
		worst_on = minf(worst_on, UiA11y.contrast_ratio(UiPalette.TEXT_ON_ACCENT, a))
	t.near(UiA11y.contrast_ratio(accents["def"], UiPalette.BG_PANEL), 4.89, 0.05, "def is the minimum")
	t.near(worst, 4.89, 0.05)
	t.near(worst_on, 4.66, 0.05, "dark text on the DEF accent")
	t.check(worst_on >= 4.5, "dark text on accent fill >= 4.5")
	t.near(UiA11y.contrast_ratio(accents["ae"], UiPalette.BG_PANEL), 10.79, 0.05)
	t.eq(UiSkinSet.shared().contrast_failures().size(), 0)


func test_state_contrast(t: TestCtx) -> void:
	var c: Dictionary = UiTheme.colors()
	var st: Dictionary = c["states"]
	var btn: Dictionary = st["button"]
	for state: String in ["normal", "hover", "pressed"]:
		var d: Dictionary = btn[state]
		for fill: Color in [d["fill_top"], d["fill_bottom"]]:
			t.check(UiA11y.contrast_ratio(d["text"], fill) >= 9.0, "button %s text/fill %.2f >= 9" % [state, UiA11y.contrast_ratio(d["text"], fill)])
	var dis: Dictionary = btn["disabled"]
	t.check(UiA11y.contrast_ratio(dis["text"], dis["fill_top"]) >= 3.0, "disabled text >= 3:1 (graphics bound)")
	var foc: Dictionary = btn["focus"]
	t.check(UiA11y.contrast_ratio(foc["border"], UiPalette.BG_PANEL) >= 3.0, "focus ring >= 3:1")
	var prim: Dictionary = st["primary"]
	for state: String in ["normal", "hover", "pressed"]:
		var d: Dictionary = prim[state]
		t.check(UiA11y.contrast_ratio(d["text"], d["fill_top"]) >= 4.5, "primary %s text on lit half >= 4.5" % state)


func test_semantic_modes(t: TestCtx) -> void:
	t.check(UiPalette.semantic_for(&"ok", false).is_equal_approx(UiPalette.OK))
	t.check(UiPalette.semantic_for(&"danger", true).is_equal_approx(UiPalette.CVD_DANGER))
	var normal: Theme = UiTheme.build(UiSkin.builtin("napc"))
	var cvd: Theme = UiTheme.build(UiSkin.builtin("napc"), {"cvd": true})
	t.check(normal.get_color("font_color", "OkLabel").is_equal_approx(UiPalette.OK))
	t.check(cvd.get_color("font_color", "OkLabel").is_equal_approx(UiPalette.CVD_OK))
	t.check(cvd.get_color("danger", UiTheme.ACCENT_TYPE).is_equal_approx(UiPalette.CVD_DANGER))
	var hc: Theme = UiTheme.build(UiSkin.builtin("napc"), {"high_contrast": true})
	t.check(hc.get_color("text_mute", UiTheme.ACCENT_TYPE).is_equal_approx(UiPalette.TEXT_DIM), "high contrast promotes TEXT_MUTE to TEXT_DIM")
	var hb: UiStyleBox = UiTheme.box(UiSkin.builtin("napc"), &"panel", &"normal", {"high_contrast": true})
	t.eq(hb.fill_top.a, 1.0, "high contrast panels are opaque")
	t.eq(hb.border_width, 2.0)
	t.check(hb.border_color.is_equal_approx(UiPalette.LINE_BRIGHT))
