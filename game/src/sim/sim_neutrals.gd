class_name SimNeutrals
extends RefCounted
## The neutral structure effects catalog of the economy (economy 5.13, task EC3A): what a captured (or standing)
## neutral structure does beyond the generic ownership hooks of SimStructureLife.
##
##   Grid Substation      +power_n power while owned          SimStructureLife.activate registers it (power_delta)
##   Salvage Depot        +income every 200 ticks             SimEconomySystem._neutral_income (CR_DEPOT)
##   Field Hospital       free heal aura on friendly infantry  `update` below (local aura, see below)
##   Observation Tower    sight 14 cells while owned           the vision system stamps the owner's sight (DefNeutral.sight)
##   Civilian Block       marked civilian garrison, 4 squads   `garrison_squads` / `is_civilian_garrison`; the container
##                                                             mechanics belong to the transports / garrison domain
##   Harbor Terminal      forward Dock queue                   `on_spawn` gives it a SimCompProd (PROD_DOCK); production
##                                                             asks `forward_prereqs_ok`, `exit_cell`
##
## Field Hospital aura: the abilities aura primitive (AB-05) does not exist yet, so this is a local minimal aura. Every
## tick each hospital owned by a player heals friendly (own or allied) infantry within its radius by
## floor(hp_max * rate * (t + 1) / D) - floor(hp_max * rate * t / D) (t = the absolute tick, D = 10000 * TPS), which is exactly
## rate bp of max health per second with no per-unit state. A unit in range of several hospitals is healed once, by the
## highest rate (the same-source rule). Stateless statics; nothing here is hashed.

const HARBOR_RINGS: int = 12

static var _seen: Dictionary = {}
static var _buf: PackedInt32Array = PackedInt32Array()


static func def_of(world: SimWorld, e: SimEntity) -> DefNeutral:
	if e.kind != SimEntity.Kind.NEUTRAL or e.def_idx < 0 or e.def_idx >= world.data.neutrals.size():
		return null
	return world.data.neutrals[e.def_idx]


static func kind_of(world: SimWorld, e: SimEntity) -> int:
	var d: DefNeutral = def_of(world, e)
	return d.neutral_kind if d != null else -1


static func is_civilian_garrison(world: SimWorld, e: SimEntity) -> bool:
	return kind_of(world, e) == DefEnums.NeutralKind.CIVILIAN_GARRISON


## Squads a civilian garrison holds (0 for every other entity).
static func garrison_squads(world: SimWorld, e: SimEntity) -> int:
	var d: DefNeutral = def_of(world, e)
	if d == null or d.neutral_kind != DefEnums.NeutralKind.CIVILIAN_GARRISON:
		return 0
	return d.garrison_squads if d.garrison_squads > 0 else world.data.economy.garrison_squads_n


## PROD_DOCK for a Harbor Terminal, PROD_NONE for every other neutral.
static func producer_kind(world: SimWorld, e: SimEntity) -> int:
	return SimEconConst.PROD_DOCK if kind_of(world, e) == DefEnums.NeutralKind.HARBOR_TERMINAL else SimEconConst.PROD_NONE


## Economy on_spawn hook for a NEUTRAL entity (after its SimCompEcon exists): a Harbor Terminal gets its queue component.
static func on_spawn(world: SimWorld, e: SimEntity) -> void:
	if producer_kind(world, e) != SimEconConst.PROD_NONE and e.prod == null:
		var pr: SimCompProd = SimCompProd.new()
		pr.kind = SimEconConst.PROD_DOCK
		e.prod = pr


## Structure index a Harbor Terminal counts as for its forward queue (structure.shared.dock), -1 if none.
static func forward_structure(world: SimWorld, e: SimEntity) -> int:
	var d: DefNeutral = def_of(world, e)
	if d == null:
		return -1
	var fq: Variant = d.params.get("forward_queue", null)
	return int((fq as Dictionary).get("counts_as_structure_idx", -1)) if fq is Dictionary else -1


## A forward queue only builds units whose prerequisites are just the dock (patrol boat, Landing Transport).
static func forward_prereqs_ok(world: SimWorld, terminal: SimEntity, ud: DefUnit) -> bool:
	var dock: int = forward_structure(world, terminal)
	if dock < 0:
		return false
	var d: DefNeutral = def_of(world, terminal)
	var fq: Dictionary = d.params.get("forward_queue", {}) as Dictionary
	var cap: int = int(fq.get("tier_cap_n", 1))
	if ud.tier > cap:
		return false
	for r: int in ud.requires:
		if r != dock:
			return false
	return true


## Exit cell (map index) of a Harbor Terminal: the middle cell of the first row of its berth strip. -1 outside the map.
static func exit_cell(world: SimWorld, e: SimEntity) -> int:
	var d: DefNeutral = def_of(world, e)
	if d == null:
		return -1
	var ox: int = (e.x - d.fp_w * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	var oy: int = (e.y - d.fp_h * (SimConfig.CELL / 2)) >> SimConfig.CELL_SHIFT
	var berth: Array = d.params.get("berth", [0, d.fp_h, d.fp_w, 1]) as Array
	var x: int = ox + int(berth[0]) + int(berth[2]) / 2
	var y: int = oy + int(berth[1])
	if not world.map.in_bounds(x, y):
		return -1
	return world.map.idx(x, y)


## Free cell where a unit of `layer` leaves a Harbor Terminal: around the berth strip first, else the nearest suitable cell
## within HARBOR_RINGS of the terminal (the generator only guarantees deep water within 5 cells of it). -1 if none.
static func spawn_cell(world: SimWorld, e: SimEntity, layer: int, near_rings: int) -> int:
	var ec: int = exit_cell(world, e)
	var cell: int = SimMovement.find_free_cell_near(world, ec, layer, near_rings) if ec >= 0 else -1
	if cell < 0:
		var cc: int = world.map.idx(clampi(e.x >> SimConfig.CELL_SHIFT, 0, world.map.w - 1), clampi(e.y >> SimConfig.CELL_SHIFT, 0, world.map.h - 1))
		cell = SimMovement.find_free_cell_near(world, cc, layer, HARBOR_RINGS)
	return cell


# ------------------------------------------------------------------------------------------------------- stage 3
static func update(world: SimWorld) -> void:
	_hospitals(world)


## The abilities aura primitive (SimAbilitySystem.aura, AB-05) heals neutral Field Hospitals with its virtual heal slot as soon
## as it is wired into the world; the local aura below then steps aside so nobody is healed twice.
static func aura_primitive_present(world: SimWorld) -> bool:
	return world.abilities != null and world.abilities.get("aura") != null


static func _hospitals(world: SimWorld) -> void:
	if aura_primitive_present(world):
		return
	var any: bool = false
	for e: SimEntity in world.neutrals:
		if e.owner >= 0 and e.econ != null and e.econ.registered and (e.flags & SimFlags.F_GONE) == 0 and kind_of(world, e) == DefEnums.NeutralKind.FIELD_HOSPITAL:
			any = true
			break
	if not any:
		return
	_seen.clear()
	for e2: SimEntity in world.neutrals:
		if e2.owner < 0 or e2.econ == null or not e2.econ.registered or (e2.flags & SimFlags.F_GONE) != 0:
			continue
		var d: DefNeutral = def_of(world, e2)
		if d.neutral_kind != DefEnums.NeutralKind.FIELD_HOSPITAL or not d.params.has("ability"):
			continue
		var ap: Dictionary = (d.params["ability"] as Dictionary).get("params", {}) as Dictionary
		var rate: int = int(ap.get("rate_bps", 0))
		var radius: int = int(ap.get("radius_u", 0))
		var mask: int = int(ap.get("target_unit_mask", 0))
		if rate <= 0 or radius <= 0:
			continue
		var n: int = world.query_circle(e2.x, e2.y, radius, _buf, SimTag.ALIVE | SimTag.kind_bit(SimEntity.Kind.UNIT))
		for i: int in n:
			var u: SimEntity = world.get_entity(_buf[i])
			if u == null or (u.flags & (SimFlags.F_GONE | SimFlags.F_INSIDE)) != 0 or u.hp >= u.hp_max or u.hp_max <= 0:
				continue
			if not world.are_allied(e2.owner, u.owner) or (world.data.units[u.def_idx].tags & mask) == 0:
				continue
			if int(_seen.get(u.id, 0)) < rate:
				_seen[u.id] = rate
	for id: Variant in _seen:
		var t: SimEntity = world.get_entity(int(id))
		var m: int = t.hp_max * int(_seen[id])
		var den: int = 10000 * SimConfig.TPS
		var amount: int = m * (world.tick + 1) / den - m * world.tick / den
		if amount > 0:
			world.combat.heal(world, t, amount)
