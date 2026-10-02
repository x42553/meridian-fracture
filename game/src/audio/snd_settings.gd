class_name SndSettings
extends RefCounted
## The user-facing audio options (audio spec 4.4 / 3.9): sliders 0..100, announcer / unit voice / music modes, dynamic
## range, quality, focus muting, captions, output device, OS text-to-speech. Loads from and saves to the `[audio]` and
## `[access]` sections of a ConfigFile, or from the flat `{"audio/master": 70, ...}` dictionary the settings layer hands over.

const ANN_FACTION: int = 0
const ANN_COMPUTER: int = 1
const ANN_OFF: int = 2
const UV_SYNTH: int = 0
const UV_VOICE: int = 1
const UV_MIXED: int = 2
const UV_OFF: int = 3
const MUSIC_DYNAMIC: int = 0
const MUSIC_CALM_ONLY: int = 1
const MUSIC_OFF: int = 2
const DR_FULL: int = 0
const DR_NIGHT: int = 1
const Q_LOW: int = 0
const Q_MEDIUM: int = 1
const Q_HIGH: int = 2

const INT_KEYS: PackedStringArray = ["master", "music", "sfx", "voice", "ui", "ambience"]
## slider name -> bus name
const SLIDER_BUS: Dictionary = {"master": "Master", "music": "Music", "sfx": "Sfx", "voice": "Voice", "ui": "Ui", "ambience": "Ambience"}

var master: int = 100
var music: int = 70
var sfx: int = 90
var voice: int = 100
var ui: int = 80
var ambience: int = 70
var announcer_mode: int = ANN_FACTION
var unit_voice_mode: int = UV_SYNTH
var music_mode: int = MUSIC_DYNAMIC
var dynamic_range: int = DR_FULL
var quality: int = Q_MEDIUM
var mute_unfocused: bool = true
var captions: bool = true
var output_device: String = "Default"
var announcer_tts: bool = false


## (v/100)^2, exactly 0 for 0 (mute).
static func slider_to_linear(v: int) -> float:
	if v <= 0:
		return 0.0
	var f: float = clampf(float(v) / 100.0, 0.0, 1.0)
	return f * f


## Bus gain in dB for a slider: the bus's default level plus the slider curve; muted sliders give -80.
static func slider_to_db(v: int, default_db: float = 0.0) -> float:
	var lin: float = slider_to_linear(v)
	if lin <= 0.0:
		return SndConfig.SILENT_DB
	return default_db + linear_to_db(lin)


func slider_of(name: String) -> int:
	return int(get(name))


func load_from(cfg: ConfigFile) -> void:
	for k: String in INT_KEYS:
		set(k, clampi(int(cfg.get_value("audio", k, get(k))), 0, 100))
	announcer_mode = clampi(int(cfg.get_value("audio", "announcer", announcer_mode)), 0, 2)
	unit_voice_mode = clampi(int(cfg.get_value("audio", "unit_voices", unit_voice_mode)), 0, 3)
	music_mode = clampi(int(cfg.get_value("audio", "music_mode", music_mode)), 0, 2)
	dynamic_range = clampi(int(cfg.get_value("audio", "dynamic_range", dynamic_range)), 0, 1)
	quality = clampi(int(cfg.get_value("audio", "quality", quality)), 0, 2)
	mute_unfocused = bool(cfg.get_value("audio", "mute_unfocused", mute_unfocused))
	captions = bool(cfg.get_value("audio", "captions", captions))
	output_device = str(cfg.get_value("audio", "output_device", output_device))
	announcer_tts = bool(cfg.get_value("access", "announcer_tts", announcer_tts))


func save_to(cfg: ConfigFile) -> void:
	for k: String in INT_KEYS:
		cfg.set_value("audio", k, int(get(k)))
	cfg.set_value("audio", "announcer", announcer_mode)
	cfg.set_value("audio", "unit_voices", unit_voice_mode)
	cfg.set_value("audio", "music_mode", music_mode)
	cfg.set_value("audio", "dynamic_range", dynamic_range)
	cfg.set_value("audio", "quality", quality)
	cfg.set_value("audio", "mute_unfocused", mute_unfocused)
	cfg.set_value("audio", "captions", captions)
	cfg.set_value("audio", "output_device", output_device)
	cfg.set_value("access", "announcer_tts", announcer_tts)


## From the flat dictionary of `AppApply.audio_values` ("audio/master", ..., "access/announcer_tts"). Unknown keys are ignored.
func load_values(values: Dictionary) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	save_to(cfg)
	for id: Variant in values.keys():
		var parts: PackedStringArray = str(id).split("/")
		if parts.size() == 2 and (parts[0] == "audio" or parts[0] == "access"):
			cfg.set_value(parts[0], parts[1], values[id])
	load_from(cfg)


func duplicate_settings() -> SndSettings:
	var s: SndSettings = SndSettings.new()
	var cfg: ConfigFile = ConfigFile.new()
	save_to(cfg)
	s.load_from(cfg)
	return s
