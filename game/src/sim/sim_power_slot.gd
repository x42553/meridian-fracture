class_name SimPowerSlot
extends RefCounted
## One of the 4 per-player strategic slots (3 support powers + the superweapon; economy 4.4). Ints only, all hashed
## through SimPlayerEcon.hash_into.

const HASH_EXEMPT: PackedStringArray = []

var kind: int = 0  ## 0 = support power, 1 = superweapon
var def_idx: int = -1  ## p_idx / w_idx (-1: roster has none)
var ready_tick: int = 0  ## support power: absolute tick when the cooldown ends; 0 = ready since unlock
var uses: int = 0
var launcher_id: int = 0  ## superweapon: entity id of the ACTIVE launcher (0 none)
var sw_state: int = SimEconConst.SW_NONE
var charge: int = 0  ## ticks accumulated toward recharge_ticks
var recharge_ticks: int = 0
var last_activation_tick: int = -1
var pending_attack: int = 0  ## SimWarning id, 0 none
var announced: bool = false  ## EVT_POWER_UNLOCKED already sent


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(kind)
	buf.append(def_idx)
	buf.append(ready_tick)
	buf.append(uses)
	buf.append(launcher_id)
	buf.append(sw_state)
	buf.append(charge)
	buf.append(recharge_ticks)
	buf.append(last_activation_tick)
	buf.append(pending_attack)
	buf.append(1 if announced else 0)
