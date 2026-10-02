class_name DefMissionTrigger
extends RefCounted
## A mission trigger: `when` condition tree, `then` actions. Triggers are stored sorted by id (evaluation order).

var id: String = ""
var once: bool = true  ## fire at most once, then disable itself
var enabled: bool = true  ## initial state
var edge: bool = false  ## fire only when the condition turns true (false -> true), not while it stays true
var cooldown: int = 0  ## ticks that must pass between two fires (repeating triggers)
var when: DefMissionCond = null
var then: Array[DefMissionAction] = []
