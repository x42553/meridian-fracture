class_name SndProfileDef
extends RefCounted
## Resolved `snd.profile.*` entry: unit/structure voice class, entity loops and per-archetype weapon variants (audio spec 4.4).

enum When { ALWAYS = 0, MOVING = 1, AIRBORNE = 2, STRUCTURE_ACTIVE = 3, CHARGING = 4 }
const WHEN_NAMES: PackedStringArray = ["always", "moving", "airborne", "structure_active", "charging"]

var id: StringName = &""
var parent: StringName = &""
var voice_class: int = -1  ## SndUnits.VoiceClass; -1 = inherit, resolved to VEHICLE when nobody sets it
var loops: Array[Dictionary] = []  ## [{event: StringName, when: int, gain_db: float, pitch_speed: bool}]
var weapon_variant: Dictionary = {}  ## weapon archetype name -> suffix ("medium")
var die: StringName = &""
var spawn: StringName = &""
var select_fx: StringName = &""
var scalars: Dictionary = {}
var loops_explicit: bool = false
