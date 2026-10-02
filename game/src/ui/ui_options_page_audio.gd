class_name UiOptionsPageAudio
extends UiOptionsPage
## Audio page (ui.md 5.18.1 / 5.18.5): the six bus sliders, announcer / unit response / music modes, quality, output device and
## focus behaviour. Every change reaches `AppApply.apply_audio`; while a slider is dragged the page plays `snd.ui.slider_tick`
## at most every 0.1 s so the player hears the bus being edited. The output device drop-down lists `AudioServer` devices.

const TICK_GAP_MS: int = 100

## Optional audio port for the slider tick; null in tests and while audio is not wired.
var audio_port: UiAudioPort = null
var _last_tick_ms: int = -1000


func has_custom(id: String) -> bool:
	return id == "audio/output_device"


func special_row(id: String) -> Control:
	if id != "audio/output_device":
		return null
	var schema: Dictionary = AppSettingsSchema.entry(&"audio/output_device").duplicate()
	schema["type"] = AppSettingsSchema.T.CHOICE
	var choices: Array[Dictionary] = []
	var seen: Dictionary = {}
	for dev: String in devices():
		if not seen.has(dev):
			seen[dev] = true
			choices.append({"value": dev, "label_key": &"", "guard": &""})
	var current: String = str(store().get_value(&"audio/output_device"))
	if not seen.has(current):
		choices.append({"value": current, "label_key": &"", "guard": &""})
	schema["choices"] = choices
	return make_row(id, schema)


## Output devices the audio server offers ("Default" first).
static func devices() -> PackedStringArray:
	var out: PackedStringArray = AudioServer.get_output_device_list()
	if out.is_empty():
		out = PackedStringArray(["Default"])
	return out


func apply(id: String, value: Variant) -> void:
	super.apply(id, value)
	if id.begins_with("audio/") and UiOptionsText.unit(id) == "%":
		tick()


## Plays the slider tick, rate limited to one per `TICK_GAP_MS`; returns whether it played.
func tick() -> bool:
	var now: int = Time.get_ticks_msec()
	if audio_port == null or now - _last_tick_ms < TICK_GAP_MS:
		return false
	_last_tick_ms = now
	audio_port.ui(UiAudioPort.SLIDER_TICK)
	return true
