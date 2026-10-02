class_name SimPlayer
extends RefCounted
## The player record (sim_core 4.6). Identity / config fields are set by the world's constructor; counters and
## the credits ledger are kernel-owned (credits only through world.add_credits / try_spend). Tech, research,
## powers and the production / research queues live in SimPlayerEcon (economy), not here.

enum Controller { HUMAN = 0, AI = 1, NONE = 2 }  ## NONE = vacant pid
enum Elim { NONE = 0, NO_ASSETS = 1, RESIGN = 2, DISCONNECT = 3, KICKED = 4, TIMEOUT = 5, DESYNC = 6, SCRIPT = 7 }

## Fields that are deliberately not hashed. `roster` is immutable data, `view` is covered by view.checksum(),
## `name` is a label only.
const HASH_EXEMPT: PackedStringArray = ["name", "roster", "view"]

var pid: int = 0
var team: int = 0  ## the config's final team id (1..15)
var roster_idx: int = -1
var faction_idx: int = -1
var color: int = 0
var controller: int = Controller.NONE
var ai_level: int = 0
var ai_style: int = 0
var ai_flags: int = 0
var handicap: int = 100  ## percent 50..200
var name: String = ""  ## label only, never hashed
var roster: DefRoster = null
var view: DefPlayerView = null  ## data's per-player facade; production calls view.apply_research(idx); view.checksum() is hashed

var eliminated: int = 0  ## 0/1; vacant pids start at 1
var elim_tick: int = 0
var elim_reason: int = Elim.NONE
var credits: int = 0
var income_frac: int = 0  ## handicap remainder carry 0..99
var power_supply: int = 0  ## mirrored by the power system for HUD / AI reads
var power_demand: int = 0
var unit_count: int = 0  ## cap weight of live capped units
var struct_count: int = 0  ## live non-temporary structures
var rebuilders: int = 0  ## live non-temporary MCV-class units
var st_units_built: int = 0
var st_units_lost: int = 0
var st_units_killed: int = 0
var st_structs_built: int = 0
var st_structs_lost: int = 0
var st_structs_killed: int = 0
var st_credits_earned: int = 0
var st_credits_spent: int = 0
var st_damage_dealt: int = 0
var st_damage_taken: int = 0
var st_cmds: int = 0
var st_rejected: int = 0
var st_peak_units: int = 0

var econ: SimPlayerEcon = null
var fx: SimPlayerFx = null
var vis: SimPlayerVision = null


## Appends the players-part stream of sim_core 8.2 for this player.
func hash_into(buf: PackedInt32Array) -> void:
	buf.append(pid)
	buf.append(team)
	buf.append(roster_idx)
	buf.append(faction_idx)
	buf.append(color)
	buf.append(controller)
	buf.append(ai_level)
	buf.append(ai_style)
	buf.append(ai_flags)
	buf.append(handicap)
	buf.append(eliminated)
	buf.append(elim_tick)
	buf.append(elim_reason)
	buf.append(credits)
	buf.append(income_frac)
	buf.append(power_supply)
	buf.append(power_demand)
	buf.append(unit_count)
	buf.append(struct_count)
	buf.append(rebuilders)
	buf.append(st_units_built)
	buf.append(st_units_lost)
	buf.append(st_units_killed)
	buf.append(st_structs_built)
	buf.append(st_structs_lost)
	buf.append(st_structs_killed)
	buf.append(st_credits_earned)
	buf.append(st_credits_spent)
	buf.append(st_damage_dealt)
	buf.append(st_damage_taken)
	buf.append(st_cmds)
	buf.append(st_rejected)
	buf.append(st_peak_units)
	buf.append(view.checksum() if view != null else 0)
	var mask: int = 0
	if econ != null:
		mask |= 1
	if fx != null:
		mask |= 2
	if vis != null:
		mask |= 4
	buf.append(mask)
	if econ != null:
		econ.hash_into(buf)
	if fx != null:
		fx.hash_into(buf)
	if vis != null:
		vis.hash_into(buf)
