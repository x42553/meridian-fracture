extends UiLayerRoot
## Options / first-run dialogs sheet (UI-06b, UI-06a polish): tools/gd shot res://tests/visual/app3_dialogs.tscn out.png -- --dlg=first|keep|conflict
## No class_name on purpose (labs never take real class names).


func _ready() -> void:
	var which: String = "first"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dlg="):
			which = arg.substr(6)
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	UiLayout.apply(win, 1.0)
	UiSkinSet.shared().setup_from_json()
	UiThemeService.rebuild(UiSkinSet.shared().skin_for("napc"))
	var back: ColorRect = ColorRect.new()
	back.color = Color("#0b1016")
	add_child(back)
	UiLayerRoot.fill(back)
	var stack: UiDialogStack = UiDialogStack.new()
	add_child(stack)
	stack.attach(self)
	match which:
		"keep":
			stack.push(UiDlgKeepSettings.new("Window mode: Borderless fullscreen\nResolution: 1920 x 1080"))
		"conflict":
			var names: PackedStringArray = ["\"Centre on base\""]
			stack.push(UiDlgKeyConflict.new("Home", "Reset camera", names, true))
		_:
			stack.push(UiDlgFirstRun.new(null))
