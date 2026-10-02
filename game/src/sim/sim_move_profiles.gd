class_name SimMoveProfiles
extends RefCounted
## Per-def movement profile (terrain_movement 4.6), built once in SimMovementSystem.init_world from the frozen data
## objects. Parallel arrays indexed by the UNIT def index; every entry is -1 / 0 for a def that cannot move.
## `movement.json` turn_mode_override is not implemented (the file does not exist yet).

var count: int = 0
var mc: PackedInt32Array = PackedInt32Array()
var np: PackedInt32Array = PackedInt32Array()
var nav_size: PackedInt32Array = PackedInt32Array()
var radius: PackedInt32Array = PackedInt32Array()
var home_layer: PackedInt32Array = PackedInt32Array()
var mass: PackedInt32Array = PackedInt32Array()
var speed_base: PackedInt32Array = PackedInt32Array()
var turn_rate: PackedInt32Array = PackedInt32Array()
var accel_q4: PackedInt32Array = PackedInt32Array()
var decel_q4: PackedInt32Array = PackedInt32Array()
var reverse_pct: PackedInt32Array = PackedInt32Array()
var turn_mode: PackedInt32Array = PackedInt32Array()
var hl_default: PackedInt32Array = PackedInt32Array()
var deep_speed_bp: PackedInt32Array = PackedInt32Array()
var water_mult_bp: PackedInt32Array = PackedInt32Array()
var can_move: PackedByteArray = PackedByteArray()


## `tt` is accepted for signature parity with the spec (the profile helpers are static on MapTerrain).
static func build(data: GameData, _tt: MapTerrain = null) -> SimMoveProfiles:
	var p: SimMoveProfiles = SimMoveProfiles.new()
	var n: int = data.units.size()
	p.count = n
	for arr: PackedInt32Array in [p.mc, p.np, p.nav_size, p.radius, p.home_layer, p.mass, p.speed_base, p.turn_rate, p.accel_q4,
			p.decel_q4, p.reverse_pct, p.turn_mode, p.hl_default, p.deep_speed_bp, p.water_mult_bp]:
		arr.resize(n)
	p.can_move.resize(n)
	var masses: PackedInt32Array = data.bodies.mass
	for i: int in n:
		var u: DefUnit = data.units[i]
		var c: int = u.move_class
		p.mc[i] = c
		p.radius[i] = u.radius
		p.home_layer[i] = u.home_layer
		p.np[i] = MapTerrain.profile_of(c, u.radius)
		p.nav_size[i] = MapTerrain.nav_size(c, u.radius)
		p.mass[i] = maxi(1, masses[u.size_class] if u.size_class < masses.size() else 1)
		p.speed_base[i] = u.speed
		p.turn_rate[i] = u.turn_rate
		p.deep_speed_bp[i] = u.deep_speed_bp
		p.water_mult_bp[i] = u.water_mult_bp
		var accel_t: int = maxi(1, u.accel_t)
		var decel_t: int = maxi(1, (accel_t * SimMoveConfig.DECEL_PCT_OF_ACCEL + 50) / 100)
		p.accel_q4[i] = maxi(1, (u.speed * 16 + accel_t / 2) / accel_t)
		p.decel_q4[i] = maxi(1, (u.speed * 16 + decel_t / 2) / decel_t)
		var ground: bool = c == MapTerrain.MC_WHEELED or c == MapTerrain.MC_TRACKED or c == MapTerrain.MC_AMPHIBIOUS
		p.reverse_pct[i] = SimMoveConfig.REVERSE_SPEED_PCT if ground else 0
		var tm: int = SimMoveConfig.TM_ARC
		var hl: int = SimMoveConfig.HL_GROUND
		match c:
			MapTerrain.MC_FOOT:
				tm = SimMoveConfig.TM_INSTANT
			MapTerrain.MC_TRACKED:
				tm = SimMoveConfig.TM_PIVOT
			MapTerrain.MC_AMPHIBIOUS:
				tm = SimMoveConfig.TM_ARC if u.size_class <= DefEnums.SizeClass.LIGHT else SimMoveConfig.TM_PIVOT
			MapTerrain.MC_NAVAL:
				hl = SimMoveConfig.HL_WATER
			MapTerrain.MC_SUBMERGED:
				hl = SimMoveConfig.HL_SUB
			MapTerrain.MC_AIR_FIXED:
				tm = SimMoveConfig.TM_BANK
				hl = SimMoveConfig.HL_AIR_HIGH
			MapTerrain.MC_AIR_HOVER:
				tm = SimMoveConfig.TM_INSTANT
				hl = SimMoveConfig.HL_AIR_LOW
		p.turn_mode[i] = tm
		p.hl_default[i] = hl
		p.can_move[i] = 1 if (c != MapTerrain.MC_STATIC and u.speed > 0) else 0
	return p


func is_air(def_idx: int) -> bool:
	var c: int = mc[def_idx]
	return c == MapTerrain.MC_AIR_FIXED or c == MapTerrain.MC_AIR_HOVER


## Copies the def's profile into a fresh component.
func fill(m: SimCompMove, def_idx: int) -> void:
	m.mc = mc[def_idx]
	m.np = np[def_idx]
	m.nav_size = nav_size[def_idx]
	m.radius = radius[def_idx]
	m.mass = mass[def_idx]
	m.turn_mode = turn_mode[def_idx]
	m.turn_rate = turn_rate[def_idx]
	m.accel_q4 = accel_q4[def_idx]
	m.decel_q4 = decel_q4[def_idx]
	m.reverse_pct = reverse_pct[def_idx]
	m.speed_base = speed_base[def_idx]
	m.hl = hl_default[def_idx]
