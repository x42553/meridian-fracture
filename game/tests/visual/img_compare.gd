extends SceneTree
## VQ2A tool: stacks the same crop of several PNGs (before / after) vertically, scaled up, with nearest filtering.
## `tools/gd run res://tests/visual/img_compare.gd -- out.png x,y,w,h scale in1.png in2.png ...` (absolute paths)

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 4:
		print("usage: out.png x,y,w,h scale in1 [in2 ...]")
		quit(2)
		return
	var r: PackedStringArray = a[1].split(",")
	var rect: Rect2i = Rect2i(r[0].to_int(), r[1].to_int(), r[2].to_int(), r[3].to_int())
	var sc: int = a[2].to_int()
	var n: int = a.size() - 3
	var out: Image = Image.create(rect.size.x * sc, (rect.size.y * sc + 6) * n, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.1, 0.1, 0.1))
	for i: int in n:
		var img: Image = Image.load_from_file(a[3 + i])
		if img == null:
			continue
		var c: Image = img.get_region(rect)
		c.resize(rect.size.x * sc, rect.size.y * sc, Image.INTERPOLATE_NEAREST)
		c.convert(Image.FORMAT_RGBA8)
		out.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(0, i * (rect.size.y * sc + 6)))
	print("saved ", a[0], " err ", out.save_png(a[0]))
	quit()
