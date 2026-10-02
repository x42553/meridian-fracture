class_name AiWant
extends RefCounted
## One thing the AI wants to own (ai.md 4.3): a structure, a unit role / def. Wants are kept sorted by (prio, created, id) by
## AiEconomy, which grants them one at a time under the burn-rate rules (ai.md 5.4.1). `count` is an ABSOLUTE target
## ("have + queued >= count"; for structures the finished-structure count), so a want heals itself after losses.
## `site_kind` is an AiPlacer.Site value, `site_x/site_y` an optional placement hint in sub-cells (-1 = none).

var id: int = 0
var kind: int = AiTypes.WantKind.STRUCT
var def: int = -1
var role: int = -1
var count: int = 1
var prio: int = 20
var origin: int = AiTypes.WantOrigin.ECONOMY
var created: int = 0
var deadline: int = 0
var site_kind: int = 0
var site_x: int = -1
var site_y: int = -1
var issued_tick: int = -1
var state: int = AiTypes.WantState.OPEN
var fail_count: int = 0
var block_until: int = 0
var step_id: String = ""  ## opener / target step that created it ("" = dynamic)


static func make(p_kind: int, p_def: int, p_role: int, p_count: int, p_prio: int, p_origin: int) -> AiWant:
	var w: AiWant = AiWant.new()
	w.kind = p_kind
	w.def = p_def
	w.role = p_role
	w.count = p_count
	w.prio = p_prio
	w.origin = p_origin
	return w


## Sort order of AiEconomy.wants.
static func before(a: AiWant, b: AiWant) -> bool:
	if a.prio != b.prio:
		return a.prio < b.prio
	if a.created != b.created:
		return a.created < b.created
	return a.id < b.id


func is_open() -> bool:
	return state == AiTypes.WantState.OPEN or state == AiTypes.WantState.ISSUED
