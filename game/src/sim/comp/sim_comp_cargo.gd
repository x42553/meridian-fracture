class_name SimCompCargo
extends SimComponent
## Slot `e.cargo` (abilities 4.5): passenger list of transports and civilian garrison buildings. Allocated by
## SimAbilitySystem when a transport slot is instantiated or a garrison neutral spawns; only SimTransport writes it.
## Ints and packed int arrays only; every field is authoritative and hashed.

const HASH_EXEMPT: PackedStringArray = []
const MAX_PAX: int = 8  ## squads (Landing Transport: 4 squads or 2 vehicles of 2 slots)

var cap_slots: int = 0
var used_slots: int = 0
var pax: PackedInt32Array = PackedInt32Array()  ## passenger ids in load order, -1 empty (compacted: pax[0..n_pax-1])
var pax_slots: PackedInt32Array = PackedInt32Array()  ## slots used by pax[i]
var n_pax: int = 0
var unload_mode: int = 0  ## 0 none, 1 all, 2 one
var unload_target: int = -1  ## passenger id for mode 2
var unload_x: int = -1  ## requested unload point, -1 = the carrier's cell
var unload_y: int = -1
var unload_next: int = 0  ## tick of the next exit
var claim_team: int = -1  ## garrison only: occupying team, -1 free
var regen_frac: int = 0  ## Okapi cargo regeneration accumulator (1/1000 hp) shared by the passengers' turn
var load_until: int = 0  ## the carrier stays immobile until this tick after a boarding


func _init() -> void:
	pax.resize(MAX_PAX)
	pax.fill(-1)
	pax_slots.resize(MAX_PAX)


func index_of(id: int) -> int:
	for i: int in n_pax:
		if pax[i] == id:
			return i
	return -1


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(cap_slots)
	buf.append(used_slots)
	buf.append_array(pax)
	buf.append_array(pax_slots)
	buf.append(n_pax)
	buf.append(unload_mode)
	buf.append(unload_target)
	buf.append(unload_x)
	buf.append(unload_y)
	buf.append(unload_next)
	buf.append(claim_team)
	buf.append(regen_frac)
	buf.append(load_until)
