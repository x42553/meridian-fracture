class_name UiSpikeApp
extends Node
## Spike harness. Builds the screen named by `--screen=` (after `--`), optionally saves a real-renderer
## screenshot (`--shot=`) and quits. Extra args: --res=WxH --scale=1.5 --faction=napc --frames=N
## --crop=x,y,w,h --zoom=2 (writes <shot>_crop.png). Everything else lives in the screens.

var _args: Dictionary = {}
var screen: Node

func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	var win: Window = get_window()
	if _args.has("res"):
		var p: PackedStringArray = String(_args["res"]).split("x")
		win.size = Vector2i(int(p[0]), int(p[1]))
	win.content_scale_factor = float(_args.get("scale", "1.0"))
	print("ENV ", Engine.get_version_info()["string"], " method=", RenderingServer.get_current_rendering_method(),
		" driver=", RenderingServer.get_current_rendering_driver_name(), " gpu=", RenderingServer.get_video_adapter_name(),
		" screen_scale=", DisplayServer.screen_get_scale(), " win=", win.size, " csf=", win.content_scale_factor)
	var faction: String = String(_args.get("faction", "napc"))
	screen = _make_screen(String(_args.get("screen", "hud")), faction)
	if screen == null:
		get_tree().quit(2)
		return
	var layer := CanvasLayer.new()
	layer.name = "ScreenLayer"
	add_child(layer)
	layer.add_child(screen)
	if _args.has("shot"):
		_capture.call_deferred()

func _make_screen(screen_name: String, faction: String) -> Node:
	match screen_name:
		"fonts":
			return UiScreenFonts.new()
		"hud":
			var b: UiCooldownSweep.Backend = UiCooldownSweep.Backend.SHADER
			match String(_args.get("sweep", "shader")):
				"tp":
					b = UiCooldownSweep.Backend.TEXTURE_PROGRESS
				"polygon":
					b = UiCooldownSweep.Backend.POLYGON
			var hud_screen := UiScreenHud.new(self, faction, int(_args.get("roster", "2")), b)
			hud_screen.preview = String(_args.get("preview", "")).split(",", false)
			return hud_screen
		"bench":
			return UiBench.new(self, faction)
		"input_lab":
			return UiInputLab.new()
		"menu":
			return UiScreenMainMenu.new(self, faction)
		"skirmish":
			return UiScreenSkirmish.new(faction)
		"lan":
			return UiScreenLan.new(faction)
		_:
			push_error("unknown screen '%s'" % screen_name)
			return null

func _capture() -> void:
	var frames: int = int(_args.get("frames", "8"))
	for i in frames:
		await get_tree().process_frame
		if i == 5 and _args.has("popup") and screen.has_method("open_popup"):
			screen.call("open_popup")
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if screen.has_method("layout_debug"):
		print("LAYOUT ", screen.call("layout_debug"))
	var path: String = _resolve(String(_args["shot"]))
	img.save_png(path)
	print("SHOT ", path, " size=", img.get_size(), " viewport=", get_viewport().get_visible_rect().size)
	if _args.has("crop"):
		var c: PackedStringArray = String(_args["crop"]).split(",")
		var r := Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
		var part: Image = img.get_region(r)
		var z: int = int(_args.get("zoom", "2"))
		part.resize(r.size.x * z, r.size.y * z, Image.INTERPOLATE_NEAREST)
		part.save_png(path.replace(".png", "_crop.png"))
	get_tree().quit()

func _resolve(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") else ProjectSettings.globalize_path("res://").path_join(p)

func _parse_args(list: PackedStringArray) -> Dictionary:
	var d: Dictionary = {}
	for a in list:
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return d
