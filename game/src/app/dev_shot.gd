extends Node
## DevShot autoload: viewport screenshots for `tools/gd shot`.
##
## Inert unless the user args (everything after `--`) contain `--shot=<png>`, and always inert in release
## export templates (a shipped game must not write files named on its command line):
##   --shot=<path.png>    absolute output path (or user://); enables the hook
##   --frames=<n>         process frames to wait before capturing (default 30)
## After the capture the process quits: exit 0 on success, 1 when the image could not be saved,
## 2 when there was no image to capture (headless/dummy renderer). One result line is printed:
##   SHOT_OK <path> <w>x<h>     or     SHOT_FAIL <reason>
## No `class_name` on purpose: the autoload name `DevShot` is the global handle.

const DEFAULT_FRAMES: int = 30
## Safety net: never wait longer than this many frames even if a scene stalls the loop.
const MAX_FRAMES: int = 36000

var _png_path: String = ""
var _frames: int = DEFAULT_FRAMES


func _ready() -> void:
	if not OS.is_debug_build():
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_png_path = arg.substr("--shot=".length())
		elif arg.begins_with("--frames="):
			_frames = clampi(arg.substr("--frames=".length()).to_int(), 1, MAX_FRAMES)
	if _png_path.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		# The dummy renderer never emits frame_post_draw, so waiting would hang forever.
		# lint-allow: L006 result line is parsed by tools/gd
		print("SHOT_FAIL headless display server has no renderer; run without --headless")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_after_frames()


func _capture_after_frames() -> void:
	for _i: int in _frames:
		await get_tree().process_frame
	# frame_post_draw guarantees the viewport texture holds the frame that was just rendered.
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		# lint-allow: L006 result line is parsed by tools/gd
		print("SHOT_FAIL no image (headless/dummy renderer?)")
		get_tree().quit(2)
		return
	var err: Error = image.save_png(_png_path)
	if err != OK:
		# lint-allow: L006 result line is parsed by tools/gd
		print("SHOT_FAIL save_png(%s) -> error %d (%s)" % [_png_path, err, error_string(err)])
		get_tree().quit(1)
		return
	# lint-allow: L006 result line is parsed by tools/gd
	print("SHOT_OK %s %dx%d" % [_png_path, image.get_width(), image.get_height()])
	get_tree().quit(0)
