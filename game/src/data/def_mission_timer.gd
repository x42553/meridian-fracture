class_name DefMissionTimer
extends RefCounted
## A mission timer (declaration order = index).

var id: String = ""
var ticks: int = 0  ## duration
var repeat: bool = false  ## restart automatically when it expires
var autostart: bool = false
var ui_label: String = ""
