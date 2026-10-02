class_name ViewSimReader
extends RefCounted
## Static, null-safe, allocation-free reads of data that lives inside another domain's component (render spec 3.2).
## The ONLY view file that touches `e.combat`, `e.econ`, `e.prod`, `e.abil` internals and `world.combat` range queries;
## a sim-side rename costs one file. Every reader returns its documented default when the component is missing.

## Collector capacity (credits) used when the caller passes none; ViewDefAdapter.setup writes it from the economy table.
static var default_collector_capacity: int = 0


## Turret bat (0..4095) relative to the hull of `mount`; -1 when the entity has no such mount.
static func turret_rel_bat(e: SimEntity, mount: int) -> int:
	var c: SimCompCombat = e.combat if e != null else null
	if c == null or mount < 0 or mount >= c.n_mounts:
		return -1
	var i: int = mount * SimCombatConsts.MS + SimCombatConsts.M_ANGLE
	if i >= c.mnt.size():
		return -1
	return c.mnt[i]


## Number of weapon mounts, 0..4.
static func mount_count(e: SimEntity) -> int:
	if e == null or e.combat == null:
		return 0
	return clampi(e.combat.n_mounts, 0, 4)


## Cargo / capacity in permille (0..1000); -1 when the entity is not a collector (no econ component, or no capacity known).
## `capacity_cr` is ViewDef.cargo_cap; 0 falls back to `default_collector_capacity`.
static func collector_fill_permille(e: SimEntity, capacity_cr: int = 0) -> int:
	if e == null or e.econ == null or e.kind != SimEntity.Kind.UNIT:
		return -1
	var cap: int = capacity_cr if capacity_cr > 0 else default_collector_capacity
	if cap <= 0:
		return -1
	return clampi(e.econ.cargo * 1000 / cap, 0, 1000)


## Fills `out` = [x, y, target_id] and returns true when the structure has an active rally point.
static func rally_of(e: SimEntity, out: PackedInt32Array) -> bool:
	if e == null or e.prod == null or not e.prod.rally_on:
		return false
	if out.size() < 3:
		out.resize(3)
	out[0] = e.prod.rally_x
	out[1] = e.prod.rally_y
	out[2] = e.prod.rally_target
	return true


## Capture progress 0..1000; -1 when no capture is running. Only meaningful while the economy emits progress.
static func capture_progress_permille(e: SimEntity) -> int:
	if e == null or e.econ == null or e.econ.cap_progress <= 0:
		return -1
	return clampi(e.econ.cap_progress / 10, 0, 1000)


## [max0, min0, max1, min1, ...] in sim units through the combat range queries; returns the mount count.
## Call on selection change only (it computes lease-adjusted ranges).
static func weapon_ranges(w: SimWorld, e: SimEntity, out: PackedInt32Array) -> int:
	var n: int = mount_count(e)
	out.resize(n * 2)
	if w == null or w.combat == null:
		out.fill(0)
		return n
	for m: int in n:
		out[m * 2] = w.combat.range_max_eff(w, e, m)
		out[m * 2 + 1] = w.combat.range_min_of(w, e, m)
	return n


## Remaining interception charges of a zone / structure ability; -1 when unreadable (the abilities component is a
## stub until that domain lands, so the value is read reflectively by name).
static func zone_charges(e: SimEntity) -> int:
	if e == null or e.abil == null:
		return -1
	var v: Variant = e.abil.get(&"charges")
	if v is int:
		return v as int
	return -1


# ---- structure lifecycle and work state (VIEW-W2 additions) ----

## Economy lifecycle of a structure: SimEconConst.ST_BUILDUP 0 / ACTIVE 1 / SELLING 2 / UNDEPLOYING 3; -1 when unreadable.
static func struct_state(e: SimEntity) -> int:
	if e == null or e.econ == null:
		return -1
	return e.econ.st


## Tick at which a BUILDUP / SELLING / UNDEPLOYING phase ends (0 = not in a timed phase).
static func struct_state_until(e: SimEntity) -> int:
	if e == null or e.econ == null:
		return 0
	return e.econ.st_until


## A collector is docked at this refinery (the unload arm works).
static func dock_occupied(e: SimEntity) -> bool:
	return e != null and e.econ != null and e.econ.dock_occupant != 0


## Collector harvest state machine (SimEconConst.H_*): H_DOCK_IN 6 / H_UNLOAD 7 / H_DOCK_OUT 8 are the dock phases; -1 when unreadable.
static func harvest_state(e: SimEntity) -> int:
	if e == null or e.econ == null:
		return -1
	return e.econ.h_state


## Entity id of the refinery a collector works on (0 = none).
static func harvest_refinery(e: SimEntity) -> int:
	if e == null or e.econ == null:
		return 0
	return e.econ.h_refinery


## Wrench mode (auto repair) is on.
static func repair_on(e: SimEntity) -> bool:
	return e != null and e.econ != null and e.econ.repair_on


## Player id currently capturing this structure (-1 none).
static func capture_pid(e: SimEntity) -> int:
	if e == null or e.econ == null or e.econ.cap_progress <= 0:
		return -1
	return e.econ.cap_pid


## EMP shutdown end tick of a structure (0 = none).
static func shutdown_until(e: SimEntity) -> int:
	if e == null or e.econ == null:
		return 0
	return e.econ.shutdown_until


## Remaining lifetime / owner of a wreck's salvage window: absolute expiry tick (0 = none).
static func wreck_expire(e: SimEntity) -> int:
	if e == null:
		return 0
	if e.combat != null and e.combat.wreck_expire > 0:
		return e.combat.wreck_expire
	return e.expire_tick
