class_name UiMissionMessage
extends VBoxContainer
## Caption feed of a scripted mission (MIS2): the mission's messages as plates with the speaker and the text, newest at the bottom
## of the stack (at most `MAX_PLATES`; a further message pushes the oldest out), each held for a reading time
## (`UiMissionModel.message_seconds`) and faded out. The plates are non-interactive. The announcer line of a message is played by
## the HUD coordinator through the audio port; this control only shows the text. Never reads the sim.

const MAX_PLATES: int = 3
const PLATE_W: float = 640.0
const BODY_PX: int = 17
const FADE_IN_S: float = 0.18
const FADE_OUT_S: float = 0.6

var _plates: Array[Dictionary] = []  ## {node, text, speaker, born_msec, life_s}
## Posted since the control exists (statistics for the tests).
var posted: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	custom_minimum_size = Vector2(PLATE_W, 0.0)
	set_process(false)


## Shows a message; `life_s` < 0 = reading time of the text. Returns the plate.
func post(text: String, speaker: String = "", life_s: float = -1.0) -> Control:
	posted += 1
	while _plates.size() >= MAX_PLATES:
		_drop(0)
	var plate: PanelContainer = PanelContainer.new()
	plate.theme_type_variation = &"RibbonPanel"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 8)
	plate.add_child(m)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	m.add_child(v)
	if speaker != "":
		var who: Label = UiScreenKit.label(speaker.to_upper(), &"CaptionLabel")
		who.add_theme_color_override("font_color", get_theme_color(&"accent", UiTheme.ACCENT_TYPE))
		v.add_child(who)
	var body: Label = UiScreenKit.label(text, &"", true)
	var font: Font = UiFonts.get_font(UiFonts.Role.BODY)
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_PX).x + 6.0
	body.add_theme_font_size_override("font_size", BODY_PX)
	var speaker_w: float = font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1.0, UiMetrics.FS_CAPTION).x * 1.2
	body.custom_minimum_size = Vector2(clampf(maxf(text_w, speaker_w), 220.0, PLATE_W - 32.0), 0.0)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(body)
	add_child(plate)
	plate.modulate.a = 0.0
	UiMotion.fade(self, plate, 1.0, FADE_IN_S)
	_plates.append({"node": plate, "text": text, "speaker": speaker, "born": Time.get_ticks_msec(),
		"life": life_s if life_s >= 0.0 else UiMissionModel.message_seconds(text)})
	set_process(true)
	return plate


func plate_count() -> int:
	return _plates.size()


func plate_text(i: int) -> String:
	return str(_plates[i]["text"])


func plate_speaker(i: int) -> String:
	return str(_plates[i]["speaker"])


func clear() -> void:
	while not _plates.is_empty():
		_drop(0)


func _drop(i: int) -> void:
	var node: Node = _plates[i]["node"] as Node
	_plates.remove_at(i)
	if node != null and is_instance_valid(node):
		remove_child(node)
		node.queue_free()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for i: int in range(_plates.size() - 1, -1, -1):
		var age: float = float(now - int(_plates[i]["born"])) / 1000.0
		var life: float = float(_plates[i]["life"])
		var node: Control = _plates[i]["node"] as Control
		if age >= life:
			_drop(i)
		elif age > life - FADE_OUT_S and node != null:
			node.modulate.a = clampf((life - age) / FADE_OUT_S, 0.0, 1.0)
	if _plates.is_empty():
		set_process(false)
