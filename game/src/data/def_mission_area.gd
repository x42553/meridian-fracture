class_name DefMissionArea
extends RefCounted
## A named map area in CELLS. The anchor is resolved against the generated map when the world is built (SimMissionSystem),
## so the same mission works on any seed: "abs" = absolute cell, "map" = permille of the map size, "start" = offset from the
## spawn cell of mission player `anchor_pid`.

enum Shape { CIRCLE = 0, RECT = 1 }
enum Anchor { ABS = 0, MAP = 1, START = 2 }

var id: String = ""
var shape: int = 0
var anchor: int = 0
var anchor_pid: int = 0
var x: int = 0  ## circle: centre; rect: top-left (after the anchor offset)
var y: int = 0
var r: int = 0  ## circle radius in cells (0 = the single cell)
var w: int = 1  ## rect size in cells
var h: int = 1
