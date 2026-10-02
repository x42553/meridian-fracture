class_name DefMissionMessage
extends RefCounted
## A mission message (declaration order = index): on-screen text plus an optional announcer line id (data/audio/announcer.json).

var id: String = ""
var announcer: String = ""
var announcer_idx: int = -1  ## index into DefMission.announcers
var ui_text: String = ""
var ui_speaker: String = ""
