extends UiLayerRoot
## Overlay / picking alignment lab (UI-04b) and input feedback lab (UI-09a): the fixture battlefield with its 2D stand-in
## overlay, an in-flight drag rectangle, hover ring, selection brackets and a control-group strip.
##   tools/gd shot res://tests/visual/lab_input.tscn out.png --size 1920x1080 -- --scenario=drag
## Options: --scenario=idle|select|drag|hover, --amp=<metres> (terrain amplitude, default 2.5), --seed=N.
## No class_name on purpose.

var _args: Dictionary = {}
var view: UiViewPortFixture = null
var sim: UiSimPortFixture = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	UiLayout.apply(win, 1.0)
	var skins: UiSkinSet = UiSkinSet.shared()
	skins.setup_from_json()
	UiThemeService.rebuild(skins.skin_for("napc"))
	sim = UiSimPortFixture.load_file("hud_mid_match")
	view = UiViewPortFixture.new(sim, float(_args.get("amp", "2.5")), true)
	var host := Node3D.new()
	add_child(host)
	view.attach(host)
	add_child(view.overlay)
	view.focus_on_sim(66000, 62000, true)
	view.refresh()
	var rect := UiSelectRect.new()
	add_child(rect)
	match str(_args.get("scenario", "drag")):
		"select":
			view.set_selection(PackedInt32Array([1001, 1002]))
		"hover":
			view.set_selection(PackedInt32Array([1001]))
			view.set_hover(1002)
		"drag":
			view.set_selection(PackedInt32Array([1001]))
			rect.show_rect(Rect2(Vector2(560.0, 300.0), Vector2(620.0, 380.0)))
		_:
			pass
	view.overlay.queue_redraw()
