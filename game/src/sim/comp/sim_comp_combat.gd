class_name SimCompCombat
extends SimComponent
## Slot `e.combat`, allocated for EVERY entity by SimCombatSystem.on_spawn (combat 4.3). Ints and packed int arrays
## only. Writers: combat (everything), abilities / movement (only the inbox `ext_*` fields and leases through
## SimCombatMods). Derived / per-tick scratch fields are listed in HASH_EXEMPT and recomputed identically.

const HASH_EXEMPT: PackedStringArray = [
	"agg_dmg_bp", "agg_reload_bp", "agg_range_bp", "mods_dirty", "mods_next_expiry",
	"taken_stamp", "taken_cache", "hit_stamp", "hit_dmg", "hit_flags", "hit_atk", "hit_hp0",
]

# ---- identity ----
var n_mounts: int = 0  ## from the def; 0 for unarmed
var cflags: int = 0  ## CF_*
# ---- stance / target ----
var stance: int = 0
var hold_pos: int = 0
var target_id: int = -1
var target_src: int = 0
var target_since: int = 0
var seen_x: int = 0
var seen_y: int = 0
var seen_tick: int = 0
var ground_on: int = 0
var ground_x: int = 0
var ground_y: int = 0
var anchor_on: int = 0
var anchor_x: int = 0
var anchor_y: int = 0
var scan_next: int = 0
var focus_mask: int = 0
var focus_tick: int = 0
var inflight_est: int = 0
var last_attacker_id: int = -1
var last_attacker_pid: int = -1
var last_assist_tick: int = 0
var still_ticks: int = 0
var mnt: PackedInt32Array = PackedInt32Array()  ## n_mounts * SimCombatConsts.MS ints
# ---- timestamps (read by abilities / vision) ----
var last_fire_tick: int = SimCombatConsts.NEVER
var last_hit_tick: int = SimCombatConsts.NEVER
var last_dealt_tick: int = SimCombatConsts.NEVER
# ---- statuses ----
var emp_until: int = 0
var wlock_until: int = 0
var sup_left_q8: int = 0
var sup_t0: int = SimCombatConsts.NEVER
var sup_t1: int = SimCombatConsts.NEVER
var sup_t2: int = SimCombatConsts.NEVER
var sup_i: int = 0
# ---- leases (empty until the first SimCombatMods.apply, then MAX_MODS * MODS_STRIDE ints) ----
var mods: PackedInt32Array = PackedInt32Array()
var mods_dirty: int = 0
var mods_next_expiry: int = 0
var agg_dmg_bp: int = 0
var agg_reload_bp: int = 0
var agg_range_bp: int = 0
# ---- point defence ----
var aps_next: PackedInt32Array = PackedInt32Array()
# ---- requests to abilities ----
var want_deploy: int = -1
var want_mode: int = -1
var want_surface: int = -1
# ---- inbox (written by movement / abilities before step 8) ----
var ext_moving: int = 0
var ext_deployed: int = 0
var ext_mode: int = 0
# ---- wreck (KIND_WRECK only) ----
var wreck_value: int = 0
var wreck_expire: int = 0
var wreck_flags: int = 0
var wreck_owner_pid: int = -1
var wreck_src_def: int = -1
# ---- dying ----
var dying_until: int = 0
var death_kind: int = 0
var crash_vx: int = 0
var crash_vy: int = 0
# ---- per-tick scratch (not hashed) ----
var taken_stamp: int = -1
var taken_cache: PackedInt32Array = PackedInt32Array()
var hit_stamp: int = -1
var hit_dmg: int = 0
var hit_flags: int = 0
var hit_atk: int = -1
var hit_hp0: int = 0


func hash_into(buf: PackedInt32Array) -> void:
	buf.append(n_mounts)
	buf.append(cflags)
	buf.append(stance)
	buf.append(hold_pos)
	buf.append(target_id)
	buf.append(target_src)
	buf.append(target_since)
	buf.append(seen_x)
	buf.append(seen_y)
	buf.append(seen_tick)
	buf.append(ground_on)
	buf.append(ground_x)
	buf.append(ground_y)
	buf.append(anchor_on)
	buf.append(anchor_x)
	buf.append(anchor_y)
	buf.append(scan_next)
	buf.append(focus_mask)
	buf.append(focus_tick)
	buf.append(inflight_est)
	buf.append(last_attacker_id)
	buf.append(last_attacker_pid)
	buf.append(last_assist_tick)
	buf.append(still_ticks)
	buf.append(mnt.size())
	buf.append_array(mnt)
	buf.append(last_fire_tick)
	buf.append(last_hit_tick)
	buf.append(last_dealt_tick)
	buf.append(emp_until)
	buf.append(wlock_until)
	buf.append(sup_left_q8)
	buf.append(sup_t0)
	buf.append(sup_t1)
	buf.append(sup_t2)
	buf.append(sup_i)
	buf.append(mods.size())
	buf.append_array(mods)
	buf.append(aps_next.size())
	buf.append_array(aps_next)
	buf.append(want_deploy)
	buf.append(want_mode)
	buf.append(want_surface)
	buf.append(ext_moving)
	buf.append(ext_deployed)
	buf.append(ext_mode)
	buf.append(wreck_value)
	buf.append(wreck_expire)
	buf.append(wreck_flags)
	buf.append(wreck_owner_pid)
	buf.append(wreck_src_def)
	buf.append(dying_until)
	buf.append(death_kind)
	buf.append(crash_vx)
	buf.append(crash_vy)
