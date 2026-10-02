class_name ViewMacrosLandmarks
extends RefCounted
## Superweapon landmarks (8) and advanced-defence silhouettes (8) of art_direction 5.9.4, as native macros
## (`sw_*`, `adv_*`). They are reached through ViewMacrosStructures.signature() / run(), so recipes just
## `{"call": "sw_halo_tower"}`. Each macro paints with the style palette only (no colour arguments), stands on a plinth
## (foundation() is the recipe's job; bodies start at y = 0.16) and stays inside the 11.5 m (superweapon) / 5.5 m
## (defence) plinth; only slewing parts (TURRET / BARREL / RADAR) sweep beyond it. Heights: superweapon landmark <= 14 m,
## defence <= 6 m. Armed macros declare sockets muzzle0_0 (and muzzle0_1 for twin launchers) on their barrel part.
## Superweapon charge segments are BLINK parts (the 8-segment progress display of the spec needs a per-instance channel that
## the unit shader does not have; see the M4 report).

const Mat := ViewMeshBuilder.Mat
const Pt := ViewMeshBuilder.Part
const Y0: float = 0.16

const SIGS: Dictionary = {
	"sw_halo_tower": "center:v",
	"sw_billboard": "center:v",
	"sw_sunflower": "center:v",
	"sw_gantry_silo": "center:v",
	"sw_hive_tower": "center:v",
	"sw_assembly_hall": "center:v",
	"sw_long_barrel": "center:v",
	"sw_three_masts": "center:v",
	"adv_bulwark_cannon": "center:v",
	"adv_lance_rail": "center:v",
	"adv_sunwall": "center:v",
	"adv_citadel_mortar": "center:v",
	"adv_sea_spear": "center:v",
	"adv_dragon_tooth": "center:v",
	"adv_forge_cannon": "center:v",
	"adv_bastion_tower": "center:v",
}


static func run(macro: String, b: ViewMeshBuilder, a: Dictionary, pal: Dictionary) -> String:
	var c: Vector3 = a["center"] as Vector3
	b.push(Transform3D(Basis.IDENTITY, c))
	match macro:
		"sw_halo_tower": _halo_tower(b, pal, c)
		"sw_billboard": _billboard(b, pal, c)
		"sw_sunflower": _sunflower(b, pal, c)
		"sw_gantry_silo": _gantry_silo(b, pal, c)
		"sw_hive_tower": _hive_tower(b, pal, c)
		"sw_assembly_hall": _assembly_hall(b, pal, c)
		"sw_long_barrel": _long_barrel(b, pal, c)
		"sw_three_masts": _three_masts(b, pal, c)
		"adv_bulwark_cannon": _bulwark(b, pal, c)
		"adv_lance_rail": _lance(b, pal, c)
		"adv_sunwall": _sunwall(b, pal, c)
		"adv_citadel_mortar": _citadel(b, pal, c)
		"adv_sea_spear": _sea_spear(b, pal, c)
		"adv_dragon_tooth": _dragon_tooth(b, pal, c)
		"adv_forge_cannon": _forge(b, pal, c)
		"adv_bastion_tower": _bastion(b, pal, c)
		_:
			b.pop()
			return "unknown macro '%s'" % macro
	b.pop()
	b.clear_part()
	return ""


# ---------------------------------------------------------------------------------------------- helpers
static func _p(pal: Dictionary, k: String) -> Color:
	return pal.get(k, Color(0.5, 0.5, 0.5)) as Color


static func _beam(b: ViewMeshBuilder, p0: Vector3, p1: Vector3, w: float, d: float = -1.0) -> void:
	ViewMacrosStructures._beam(b, p0, p1, w, d, 0.0)


## Ring of `n` boxes (tangent segments) of radius r around Y at height y, in the current transform.
static func _ring(b: ViewMeshBuilder, r: float, n: int, y: float, thick: float, depth: float, first_seg: int = 0, seg_count: int = -1) -> void:
	var cnt: int = n if seg_count < 0 else seg_count
	var seg: float = TAU * r / float(n) * 1.04
	for i in cnt:
		var ang: float = TAU * float(first_seg + i) / float(n)
		b.push(ViewMeshBuilder.xf(Vector3(cos(ang) * r, y, sin(ang) * r), Vector3(0.0, -rad_to_deg(ang) + 90.0, 0.0)))
		b.box(Vector3.ZERO, Vector3(seg, thick, depth), 0.0)
		b.pop()


## Team plate on a roof: dark gasket, pale quiet ring, dark inner gasket, team surface (art_direction 5.4.3).
static func _team(b: ViewMeshBuilder, pal: Dictionary, pos: Vector3, size: Vector2) -> void:
	b.brush(_p(pal, "plate"))
	b.box(pos, Vector3(size.x + 0.24, 0.03, size.y + 0.24), 0.0)
	b.brush(_p(pal, "sec"))
	b.box(pos + Vector3(0.0, 0.004, 0.0), Vector3(size.x + 0.12, 0.03, size.y + 0.12), 0.0)
	b.brush(_p(pal, "plate"))
	b.box(pos + Vector3(0.0, 0.008, 0.0), Vector3(size.x + 0.04, 0.03, size.y + 0.04), 0.0)
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(pos + Vector3(0.0, 0.012, 0.0), Vector3(size.x, 0.03, size.y), 0.0)


static func _lamp(b: ViewMeshBuilder, pos: Vector3, size: Vector3, col: Color, phase: float) -> void:
	b.set_part(Pt.BLINK, Vector3.ZERO, phase, 0.0)
	b.brush(col, Mat.EMISSIVE)
	b.box(pos, size, 0.0)
	b.clear_part()


## BARREL part of mount 0. Pivots are MODEL-space (the macro's `center` push does not move them), so `c` is added here.
static func _barrel_rig(b: ViewMeshBuilder, c: Vector3, pivot: Vector3, ty: float, tz: float, recoil: float) -> void:
	b.set_part(Pt.BARREL, pivot + c, 1.0, recoil, Vector2(ty + c.y, tz + c.z))


# ---------------------------------------------------------------------------------------------- superweapons
## NAPC Atlas Kinetic Array: 14 m lattice mast carrying an 8 m ring tilted 20 degrees skyward with three emitter rods,
## orange hazard collar at the base; ring segments light amber.
static func _halo_tower(b: ViewMeshBuilder, pal: Dictionary, _c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	b.brush(_p(pal, "base"))
	b.tapered_box(Vector3(0.0, Y0 + 0.8, 0.0), Vector2(9.0, 9.0), Vector2(7.2, 7.2), 1.6, Vector2.ZERO, 0.06)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 1.7, 0.0), Vector3(6.6, 0.2, 6.6), 0.03)
	_team(b, pal, Vector3(0.0, Y0 + 1.82, 2.6), Vector2(4.4, 1.6))
	b.tier = 1
	for i in 12:
		b.brush(acc if i % 2 == 0 else Color(0.11, 0.11, 0.10))
		b.box(Vector3((float(i) - 5.5) * 0.55, Y0 + 1.83, 3.05), Vector3(0.42, 0.02, 0.6), 0.0)
	b.tier = 0
	ViewMacrosStructures.run("lattice", b, {"center": Vector3(0.0, Y0 + 1.8, 0.0), "h": 10.0, "w0": 2.4, "w1": 0.9, "bays": 6, "col": sec, "brace": _p(pal, "metal")}, pal)
	# orange collar + hub
	b.brush(acc)
	b.cylinder(Vector3(0.0, Y0 + 1.8, 0.0), Vector3(0.0, Y0 + 2.5, 0.0), 1.9, 12, 0.03)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(0.0, Y0 + 11.3, 0.0), Vector3(0.0, Y0 + 12.0, 0.0), 0.5, 10, 0.02)
	# tilted halo ring with three emitter rods
	b.push(ViewMeshBuilder.xf(Vector3(0.0, Y0 + 12.0, 0.0), Vector3(-20.0, 0.0, 0.0)))
	b.brush(sec)
	_ring(b, 4.0, 24, 0.0, 0.34, 0.5, 0, 24)
	b.set_part(Pt.BLINK, Vector3.ZERO, 0.0, 0.0)
	b.brush(Color(1.0, 0.72, 0.18), Mat.EMISSIVE)
	_ring(b, 4.0, 24, 0.19, 0.06, 0.3, 0, 24)
	b.clear_part()
	b.brush(_p(pal, "metal"), Mat.METAL)
	for k in 3:
		var ang: float = TAU * float(k) / 3.0 + 0.5
		_beam(b, Vector3(cos(ang) * 4.0, 0.0, sin(ang) * 4.0), Vector3(cos(ang) * 1.2, 0.0, sin(ang) * 1.2), 0.16, 0.16)
		b.brush(acc)
		b.box(Vector3(cos(ang) * 1.0, 0.0, sin(ang) * 1.0), Vector3(0.36, 0.36, 0.36), 0.03)
		b.brush(_p(pal, "metal"), Mat.METAL)
	b.pop()
	_lamp(b, Vector3(0.0, Y0 + 11.4, 1.0), Vector3(0.16, 0.16, 0.16), Color(1.0, 0.35, 0.05), 0.0)
	b.socket(&"top", Vector3(0.0, Y0 + 12.0, 0.0), Vector3.UP)


## NEC Aurora Microwave Array: white pedestal carrying an 8 x 8 m phased-array panel tilted 55 degrees with a 24-cell amber
## grid; four fold-out corner masts (SLIDE_Y).
static func _billboard(b: ViewMeshBuilder, pal: Dictionary, _c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 1.5, 0.0), Vector3(10.0, 3.0, 8.4), 0.08)
	b.brush(_p(pal, "base"))
	b.box(Vector3(0.0, Y0 + 0.55, 0.0), Vector3(10.2, 1.1, 8.6), 0.06)
	_team(b, pal, Vector3(0.0, Y0 + 3.03, 2.9), Vector2(5.0, 1.6))
	b.tier = 1
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	b.box(Vector3(0.0, Y0 + 2.4, 4.22), Vector3(8.6, 0.16, 0.04), 0.0)
	b.tier = 0
	# panel supports and the tilted panel
	b.brush(_p(pal, "metal"), Mat.METAL)
	for sx: float in [-2.6, 2.6]:
		b.box(Vector3(sx, Y0 + 3.7, -0.6), Vector3(0.5, 1.5, 0.6), 0.03)
	b.push(ViewMeshBuilder.xf(Vector3(0.0, Y0 + 6.1, -0.6), Vector3(55.0, 0.0, 0.0)))
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, -0.1, 0.0), Vector3(8.0, 0.36, 8.0), 0.04)
	b.brush(sec)
	b.box(Vector3(0.0, 0.14, 0.0), Vector3(7.6, 0.12, 7.6), 0.02)
	b.set_part(Pt.BLINK, Vector3.ZERO, 0.0, 0.0)
	b.brush(Color(1.0, 0.68, 0.10), Mat.EMISSIVE)
	for i in 6:
		for k in 4:
			b.box(Vector3((float(i) - 2.5) * 1.22, 0.22, (float(k) - 1.5) * 1.75), Vector3(0.98, 0.05, 1.45), 0.0)
	b.clear_part()
	b.brush(_p(pal, "acc"))
	b.box(Vector3(0.0, 0.2, 4.0), Vector3(8.0, 0.1, 0.1), 0.0)
	b.pop()
	# fold-out corner masts
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base: Vector3 = Vector3(sx * 4.6, Y0 + 3.0, sz * 3.7)
			b.brush(_p(pal, "metal"), Mat.METAL)
			b.cylinder(base, base + Vector3(0.0, 1.6, 0.0), 0.09, 8, 0.0)
			b.set_part(Pt.SLIDE_Y, base, 0.0, 3.2)
			b.cylinder(base + Vector3(0.0, 1.0, 0.0), base + Vector3(0.0, 2.6, 0.0), 0.06, 6, 0.0)
			b.brush(_p(pal, "acc"))
			b.box(base + Vector3(0.0, 2.65, 0.0), Vector3(0.5, 0.06, 0.1), 0.0)
			b.brush(_p(pal, "light"), Mat.EMISSIVE)
			b.box(base + Vector3(0.0, 2.75, 0.0), Vector3(0.12, 0.08, 0.12), 0.0)
			b.clear_part()


## OLM Helios Reflector: ivory annex, 9 m teal pylon, a 9 m heliostat disc with a copper rim slewing on TURRET and a slender
## copper arm to a gold receiver (top at ~14 m when tilted).
static func _sunflower(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	var teal: Color = _p(pal, "dark")
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 1.25, 2.6), Vector3(9.4, 2.5, 5.4), 0.07)
	b.brush(acc)
	b.box(Vector3(0.0, Y0 + 2.58, 2.6), Vector3(9.6, 0.16, 5.6), 0.03)
	_team(b, pal, Vector3(0.0, Y0 + 2.68, 3.4), Vector2(5.0, 1.8))
	b.brush(teal)
	for i in 5:
		b.box(Vector3((float(i) - 2.0) * 1.8, Y0 + 1.1, 5.32), Vector3(1.0, 1.9, 0.06), 0.0)
	b.tier = 1
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	for i in 5:
		b.box(Vector3((float(i) - 2.0) * 1.8, Y0 + 2.0, 5.36), Vector3(0.8, 0.14, 0.03), 0.0)
	b.tier = 0
	# pylon
	b.brush(teal)
	b.tapered_box(Vector3(0.0, Y0 + 5.4, -1.4), Vector2(1.7, 1.7), Vector2(0.9, 0.9), 5.8, Vector2.ZERO, 0.04)
	b.brush(acc)
	b.cylinder(Vector3(0.0, Y0 + 8.2, -1.4), Vector3(0.0, Y0 + 8.5, -1.4), 0.75, 12, 0.0)
	var pv: Vector3 = Vector3(0.0, Y0 + 8.6, -1.4)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(pv + Vector3(0.0, -0.1, 0.0), pv + Vector3(0.0, 0.4, 0.0), 0.5, 12, 0.02)
	b.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(38.0)), pv + Vector3(0.0, 0.6, 0.0)))
	b.brush(acc)
	b.cylinder(Vector3(0.0, -0.14, 0.0), Vector3(0.0, 0.2, 0.0), 4.5, 24, 0.05)
	b.brush(_p(pal, "glass").lightened(0.25), Mat.GLASS)
	b.cylinder(Vector3(0.0, 0.2, 0.0), Vector3(0.0, 0.26, 0.0), 4.2, 24, 0.0)
	b.brush(acc)
	b.cylinder(Vector3(0.0, 0.26, 0.0), Vector3(0.0, 0.3, 0.0), 0.5, 12, 0.0)
	# copper arm and gold receiver
	b.brush(acc, Mat.METAL)
	_beam(b, Vector3(0.0, 0.3, 0.0), Vector3(0.0, 4.6, 0.6), 0.09)
	b.brush(Color(1.0, 0.82, 0.30), Mat.EMISSIVE)
	b.box(Vector3(0.0, 4.8, 0.62), Vector3(0.42, 0.42, 0.42), 0.03)
	b.pop()
	b.clear_part()
	b.socket(&"top", Vector3(0.0, Y0 + 13.6, -0.8), Vector3.UP)


## DEF Perun Missile Complex: oxide block with sliding silo doors (SLIDE_Z), a 14 m gantry tower with a pale-banded vertical
## missile that rises with the door activity (SLIDE_Y).
static func _gantry_silo(b: ViewMeshBuilder, pal: Dictionary, _c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	b.brush(_p(pal, "base"))
	b.box(Vector3(0.0, Y0 + 1.6, 1.2), Vector3(10.6, 3.2, 8.4), 0.08)
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, Y0 + 3.3, 1.2), Vector3(10.8, 0.2, 8.6), 0.03)
	_team(b, pal, Vector3(0.0, Y0 + 3.42, 3.7), Vector2(5.0, 1.6))
	# silo doors (two leaves sliding apart along Z) over the launch shaft
	b.brush(Color(0.03, 0.03, 0.03))
	b.box(Vector3(0.0, Y0 + 3.36, -1.4), Vector3(3.0, 0.08, 3.0), 0.0)
	for sz: float in [-1.0, 1.0]:
		b.set_part(Pt.SLIDE_Z, Vector3.ZERO, 0.0, sz * 1.5)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.box(Vector3(0.0, Y0 + 3.5, -1.4 + sz * 0.78), Vector3(3.1, 0.16, 1.56), 0.02)
		b.clear_part()
	b.tier = 1
	for i in 10:
		b.brush(sec if i % 2 == 0 else Color(0.10, 0.10, 0.09))
		b.box(Vector3((float(i) - 4.5) * 1.0, Y0 + 3.4, 5.1), Vector3(0.8, 0.02, 0.8), 0.0)
	b.tier = 0
	# gantry tower
	b.brush(sec)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(Vector3(sx * 1.35, Y0 + 8.35, -1.4 + sz * 1.35), Vector3(0.3, 10.3, 0.3), 0.02)
	b.tier = 1
	b.brush(_p(pal, "metal"), Mat.METAL)
	for k in 7:
		var y: float = Y0 + 3.6 + 1.6 * float(k)
		for s in 4:
			var ang: float = PI * 0.5 * float(s)
			var mid: Vector3 = Vector3(cos(ang) * 1.35, y, -1.4 + sin(ang) * 1.35)
			_beam(b, mid + Vector3(-sin(ang), 0.0, cos(ang)) * 1.35, mid - Vector3(-sin(ang), 0.0, cos(ang)) * 1.35, 0.1)
	b.tier = 0
	b.brush(_p(pal, "acc"))
	b.box(Vector3(0.0, Y0 + 13.4, -1.4), Vector3(3.3, 0.3, 3.3), 0.03)
	# missile on a lift
	b.set_part(Pt.SLIDE_Y, Vector3.ZERO, 0.0, 1.2)
	b.brush(sec)
	b.cylinder(Vector3(0.0, Y0 + 3.5, -1.4), Vector3(0.0, Y0 + 10.2, -1.4), 0.55, 14, 0.02)
	b.brush(_p(pal, "acc"))
	for k in 3:
		b.cylinder(Vector3(0.0, Y0 + 4.4 + 2.0 * float(k), -1.4), Vector3(0.0, Y0 + 4.9 + 2.0 * float(k), -1.4), 0.57, 14, 0.0)
	b.brush(_p(pal, "base"))
	b.frustum(Vector3(0.0, Y0 + 10.2, -1.4), Vector3(0.0, Y0 + 11.8, -1.4), 0.55, 0.05, 14, false)
	b.brush(_p(pal, "dark"))
	for k in 4:
		var ang: float = PI * 0.5 * float(k) + PI * 0.25
		b.box(Vector3(cos(ang) * 0.7, Y0 + 4.0, -1.4 + sin(ang) * 0.7), Vector3(0.05, 1.2, 0.5), 0.0)
	b.clear_part()
	_lamp(b, Vector3(1.35, Y0 + 13.65, -0.05), Vector3(0.16, 0.16, 0.16), Color(1.0, 0.1, 0.05), 0.0)
	b.socket(&"top", Vector3(0.0, Y0 + 11.8, -1.4), Vector3.UP)


## PD Tempest Swarm Hub: cerulean base ring with coral landing ring, white cylinder tower (12 m) with a honeycomb crown of 24
## drone bays under coral caps.
static func _hive_tower(b: ViewMeshBuilder, pal: Dictionary, _c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	b.brush(_p(pal, "base"))
	b.cylinder(Vector3(0.0, Y0, 0.0), Vector3(0.0, Y0 + 1.3, 0.0), 4.9, 32, 0.08)
	b.brush(acc)
	b.cylinder(Vector3(0.0, Y0 + 1.3, 0.0), Vector3(0.0, Y0 + 1.42, 0.0), 4.7, 32, 0.0)
	b.brush(sec)
	b.cylinder(Vector3(0.0, Y0 + 1.42, 0.0), Vector3(0.0, Y0 + 1.5, 0.0), 4.0, 32, 0.0)
	_team(b, pal, Vector3(0.0, Y0 + 1.53, 3.3), Vector2(2.6, 0.9))
	b.tier = 1
	for k in 8:
		var ang: float = TAU * float(k) / 8.0
		b.brush(acc)
		b.box(Vector3(cos(ang) * 3.3, Y0 + 1.52, sin(ang) * 3.3), Vector3(0.8, 0.03, 0.3), 0.0)
	b.tier = 0
	b.brush(sec)
	b.cylinder(Vector3(0.0, Y0 + 1.4, 0.0), Vector3(0.0, Y0 + 11.0, 0.0), 2.5, 24, 0.06)
	b.brush(acc)
	for y: float in [3.2, 6.0, 8.8]:
		b.cylinder(Vector3(0.0, Y0 + y, 0.0), Vector3(0.0, Y0 + y + 0.2, 0.0), 2.56, 24, 0.0)
	b.tier = 1
	b.brush(_p(pal, "glass"), Mat.GLASS)
	for k in 6:
		var ang: float = TAU * float(k) / 6.0 + 0.3
		b.box(Vector3(cos(ang) * 2.5, Y0 + 5.0, sin(ang) * 2.5), Vector3(0.12, 3.2, 0.5), 0.0)
	b.tier = 0
	b.brush(_p(pal, "dark"))
	b.cylinder(Vector3(0.0, Y0 + 11.0, 0.0), Vector3(0.0, Y0 + 11.4, 0.0), 2.9, 24, 0.03)
	# honeycomb crown: 24 drone bays in three rings
	var idx: int = 0
	for ring: Array in [[2.05, 12], [1.3, 8], [0.55, 4]]:
		var rr: float = ring[0] as float
		var cnt: int = ring[1] as int
		for k in cnt:
			var ang: float = TAU * float(k) / float(cnt) + (0.26 if rr < 1.5 else 0.0)
			var p: Vector3 = Vector3(cos(ang) * rr, Y0 + 11.4, sin(ang) * rr)
			b.brush(sec)
			b.cylinder(p, p + Vector3(0.0, 0.45, 0.0), 0.36, 6, 0.0)
			b.brush(acc)
			b.cylinder(p + Vector3(0.0, 0.43, 0.0), p + Vector3(0.0, 0.55, 0.0), 0.31, 6, 0.0)
			if idx % 3 == 0:
				_lamp(b, p + Vector3(0.0, 0.62, 0.0), Vector3(0.1, 0.06, 0.1), _p(pal, "light"), float(idx) / 24.0)
			idx += 1
	b.socket(&"top", Vector3(0.0, Y0 + 12.0, 0.0), Vector3.UP)


## HAN Dragonfall Field Foundry: jade assembly hall with porcelain caps, a crimson gantry arch, three porcelain capsule
## cradles in a row and a chimney crown.
static func _assembly_hall(b: ViewMeshBuilder, pal: Dictionary, _c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	b.brush(_p(pal, "base"))
	b.box(Vector3(0.0, Y0 + 2.2, -2.3), Vector3(10.6, 4.4, 5.6), 0.08)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 4.5, -2.3), Vector3(11.0, 0.3, 6.0), 0.05)
	b.brush(acc)
	b.box(Vector3(0.0, Y0 + 4.7, -2.3), Vector3(11.2, 0.12, 6.2), 0.02)
	_team(b, pal, Vector3(0.0, Y0 + 4.78, -1.0), Vector2(6.0, 2.2))
	b.tier = 1
	b.brush(_p(pal, "dark"))
	for i in 4:
		b.box(Vector3((float(i) - 1.5) * 2.7, Y0 + 2.0, 0.53), Vector3(1.5, 2.6, 0.08), 0.0)
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	for i in 8:
		b.box(Vector3((float(i) - 3.5) * 1.3, Y0 + 3.6, 0.53), Vector3(0.16, 0.6, 0.04), 0.0)
	b.tier = 0
	# crimson gantry arch across the front
	b.brush(acc)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 5.0, Y0 + 3.2, 2.2), Vector3(0.5, 6.4, 0.5), 0.03)
	b.box(Vector3(0.0, Y0 + 6.5, 2.2), Vector3(10.8, 0.6, 0.6), 0.04)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 6.9, 2.2), Vector3(11.2, 0.16, 0.9), 0.03)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(-1.5, Y0 + 6.2, 2.2), Vector3(-1.5, Y0 + 4.0, 2.2), 0.03, 5, 0.0, false)
	b.brush(acc)
	b.box(Vector3(-1.5, Y0 + 3.8, 2.2), Vector3(0.6, 0.3, 0.5), 0.03)
	# three capsule cradles
	for i in 3:
		var x: float = (float(i) - 1.0) * 3.4
		b.brush(_p(pal, "dark"))
		b.box(Vector3(x, Y0 + 0.4, 3.0), Vector3(1.9, 0.5, 4.2), 0.04)
		b.brush(sec)
		b.cylinder(Vector3(x, Y0 + 1.25, 4.5), Vector3(x, Y0 + 1.25, 1.5), 0.68, 14, 0.04)
		b.dome(Vector3(x, Y0 + 1.25, 1.5), Vector3(0.0, 0.0, -1.0), 0.68, 0.55, 14, 3)
		b.brush(acc)
		b.cylinder(Vector3(x, Y0 + 1.25, 3.2), Vector3(x, Y0 + 1.25, 3.5), 0.7, 14, 0.0)
	# chimney crown
	ViewMacrosStructures.run("stack", b, {"center": Vector3(-3.6, Y0 + 4.6, -4.2), "r": 0.5, "h": 4.6, "col": _p(pal, "metal"), "band": sec, "bands": 2, "cap": 1.0}, pal)
	ViewMacrosStructures.run("stack", b, {"center": Vector3(-1.6, Y0 + 4.6, -4.2), "r": 0.5, "h": 4.0, "col": _p(pal, "metal"), "band": sec, "bands": 2, "cap": 1.0}, pal)
	_lamp(b, Vector3(4.6, Y0 + 7.1, 2.2), Vector3(0.16, 0.16, 0.16), Color(1.0, 0.1, 0.05), 0.0)
	b.socket(&"top", Vector3(0.0, Y0 + 7.0, 2.2), Vector3.UP)


## AE Horizon Mass Driver: charcoal mount with a ~10.5 m rail barrel at 25 degrees (TURRET + BARREL, slews to the target)
## and six cyan capacitor rings lighting base to muzzle.
static func _long_barrel(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var cyan: Color = _p(pal, "acc")
	var dark: Color = _p(pal, "dark")
	b.brush(dark)
	b.box(Vector3(0.0, Y0 + 1.2, 2.5), Vector3(9.4, 2.4, 6.0), 0.08)
	b.brush(_p(pal, "base"))
	b.box(Vector3(0.0, Y0 + 2.5, 3.5), Vector3(8.6, 0.24, 4.2), 0.04)
	_team(b, pal, Vector3(-3.1, Y0 + 2.65, 3.5), Vector2(1.6, 3.0))
	b.tier = 1
	b.brush(_p(pal, "base"))
	for i in 5:
		b.box(Vector3((float(i) - 2.0) * 1.8, Y0 + 1.2, 5.83), Vector3(1.5, 1.8, 0.06), 0.0)
	b.brush(cyan, Mat.EMISSIVE)
	for i in 5:
		b.box(Vector3((float(i) - 2.0) * 1.8, Y0 + 0.5, 5.87), Vector3(1.2, 0.08, 0.03), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(0.0, Y0 + 3.5, 4.4)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(pv + Vector3(0.0, -0.9, 0.0), pv + Vector3(0.0, 0.2, 0.0), 1.2, 20, 0.03)
	b.brush(_p(pal, "base"))
	for sx: float in [-1.0, 1.0]:
		b.box(pv + Vector3(sx * 1.05, 0.9, 0.2), Vector3(0.5, 2.0, 1.6), 0.05)
	b.set_part(Pt.BARREL, pv + c, 0.0, 0.8, Vector2(pv.y + 1.1 + c.y, pv.z + c.z))
	b.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(25.0)), pv + Vector3(0.0, 1.1, 0.0)))
	b.brush(_p(pal, "metal"), Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.42, 0.0, -4.7), Vector3(0.36, 0.5, 10.6), 0.04)
	b.brush(dark)
	b.box(Vector3(0.0, -0.05, -4.7), Vector3(0.5, 0.5, 10.4), 0.02)
	b.brush(_p(pal, "base"))
	b.box(Vector3(0.0, 0.0, 0.3), Vector3(1.5, 1.0, 1.6), 0.06)
	for k in 6:
		var z: float = -1.5 - 1.55 * float(k)
		b.brush(cyan, Mat.EMISSIVE)
		b.box(Vector3(0.0, 0.0, z), Vector3(1.28, 0.1, 0.34), 0.0)
		b.box(Vector3(0.0, 0.32, z), Vector3(1.28, 0.1, 0.34), 0.0)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.64, 0.16, z), Vector3(0.1, 0.5, 0.34), 0.0)
		b.brush(_p(pal, "base"))
		b.box(Vector3(0.0, 0.16, z), Vector3(1.1, 0.5, 0.2), 0.02)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.box(Vector3(0.0, 0.05, -10.1), Vector3(1.3, 0.8, 0.5), 0.04)
	b.socket(&"muzzle0_0", Vector3(0.0, 0.05, -10.45), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.pop()
	b.clear_part()


## SAP Trident Interception Array: stepped ziggurat base with three 14 m sensor masts in a triangle, each topped by a
## rotating saffron-rimmed paddle.
static func _three_masts(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	var dark: Color = _p(pal, "dark")
	b.brush(dark)
	b.box(Vector3(0.0, Y0 + 0.75, 0.0), Vector3(11.0, 1.5, 11.0), 0.08)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 2.0, 0.0), Vector3(8.6, 1.0, 8.6), 0.06)
	b.brush(dark)
	b.box(Vector3(0.0, Y0 + 3.0, 0.0), Vector3(6.2, 1.0, 6.2), 0.06)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 3.6, 0.0), Vector3(5.4, 0.3, 5.4), 0.04)
	b.brush(acc)
	b.box(Vector3(0.0, Y0 + 1.53, 5.52), Vector3(8.4, 0.05, 0.04), 0.0)
	_team(b, pal, Vector3(0.0, Y0 + 2.55, 3.9), Vector2(5.6, 0.7))
	b.tier = 1
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			b.box(Vector3(sx * 2.5 + (float(i) - 1.0) * 0.55, Y0 + 1.1, 5.53), Vector3(0.3, 0.6, 0.03), 0.0)
	b.tier = 0
	for k in 3:
		var ang: float = TAU * float(k) / 3.0 - PI * 0.5
		var mx: float = cos(ang) * 2.3
		var mz: float = sin(ang) * 2.3
		# buttresses
		b.brush(dark)
		for j in 2:
			var off: float = (-1.0 if j == 0 else 1.0) * 0.8
			_beam(b, Vector3(mx + cos(ang + PI * 0.5) * off * 1.6, Y0 + 3.6, mz + sin(ang + PI * 0.5) * off * 1.6), Vector3(mx + cos(ang + PI * 0.5) * off * 0.4, Y0 + 8.0, mz + sin(ang + PI * 0.5) * off * 0.4), 0.25)
		b.brush(sec)
		b.tapered_box(Vector3(mx, Y0 + 8.6, mz), Vector2(1.0, 1.0), Vector2(0.5, 0.5), 10.4, Vector2.ZERO, 0.03)
		b.brush(acc)
		b.cylinder(Vector3(mx, Y0 + 7.0, mz), Vector3(mx, Y0 + 7.15, mz), 0.62, 10, 0.0)
		var pv: Vector3 = Vector3(mx, Y0 + 13.35, mz)
		b.set_part(Pt.RADAR, pv + c, 0.0, 0.5)
		b.push(ViewMeshBuilder.xf(pv, Vector3(0.0, 0.0, 0.0)))
		b.brush(sec)
		b.box(Vector3(0.0, 0.0, 0.0), Vector3(2.6, 0.5, 0.16), 0.03)
		b.brush(acc)
		b.box(Vector3(0.0, 0.0, 0.1), Vector3(2.7, 0.56, 0.05), 0.0)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.box(Vector3(0.0, -0.2, 0.0), Vector3(0.2, 0.4, 0.2), 0.0)
		b.pop()
		b.clear_part()
		_lamp(b, Vector3(mx, Y0 + 13.4, mz + 0.45), Vector3(0.12, 0.12, 0.12), Color(1.0, 0.1, 0.05), float(k) / 3.0)


# ---------------------------------------------------------------------------------------------- advanced defences
## NAPC Bulwark Cannon: armoured cream / olive casemate with orange lift rings and a 3 m cannon.
static func _bulwark(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var base: Color = _p(pal, "base")
	var acc: Color = _p(pal, "acc")
	b.brush(base)
	b.tapered_box(Vector3(0.0, Y0 + 0.8, 0.0), Vector2(4.6, 4.4), Vector2(3.6, 3.4), 1.6, Vector2(0.0, -0.1), 0.08)
	b.brush(_p(pal, "sec"))
	b.box(Vector3(0.0, Y0 + 1.68, -0.1), Vector3(3.4, 0.16, 3.2), 0.04)
	_team(b, pal, Vector3(0.0, Y0 + 1.78, 1.05), Vector2(2.4, 0.7))
	b.brush(acc)
	for sx: float in [-1.0, 1.0]:
		b.cylinder(Vector3(sx * 1.9, Y0 + 1.2, -0.1), Vector3(sx * 1.94, Y0 + 1.5, -0.1), 0.22, 10, 0.0)
	b.tier = 1
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, Y0 + 0.7, 2.2), Vector3(2.2, 1.2, 0.08), 0.0)
	b.brush(acc)
	for i in 5:
		b.box(Vector3((float(i) - 2.0) * 0.55, Y0 + 0.08, 2.35), Vector3(0.4, 0.02, 0.5), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(0.0, Y0 + 1.86, 0.55)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.16, 0.0), 1.2, 16, 0.02)
	b.brush(base)
	b.tapered_box(pv + Vector3(0.0, 0.62, 0.0), Vector2(1.9, 2.2), Vector2(1.4, 1.6), 0.9, Vector2(0.0, 0.1), 0.05)
	b.brush(_p(pal, "base"), Mat.PAINT, 1.0)
	b.box(pv + Vector3(0.0, 1.09, 0.1), Vector3(0.9, 0.03, 1.0), 0.0)
	_barrel_rig(b, c, pv, pv.y + 0.7, pv.z - 0.3, 0.5)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(0.0, pv.y + 0.7, pv.z - 0.3), Vector3(0.0, pv.y + 0.7, pv.z - 3.4), 0.17, 12, 0.0)
	b.cylinder(Vector3(0.0, pv.y + 0.7, pv.z - 2.9), Vector3(0.0, pv.y + 0.7, pv.z - 3.05), 0.3, 12, 0.02)
	b.brush(acc)
	b.cylinder(Vector3(0.0, pv.y + 0.7, pv.z - 3.4), Vector3(0.0, pv.y + 0.7, pv.z - 3.46), 0.2, 12, 0.0)
	b.socket(&"muzzle0_0", Vector3(0.0, pv.y + 0.7, pv.z - 3.46), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.clear_part()


## NEC Lance Rail Emplacement: low white bunker under a very long thin rail (4.2 m) with an amber tip.
static func _lance(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 0.65, 0.3), Vector3(4.8, 1.3, 4.2), 0.08)
	b.brush(_p(pal, "base"))
	b.box(Vector3(0.0, Y0 + 1.36, 0.3), Vector3(4.9, 0.14, 4.3), 0.03)
	_team(b, pal, Vector3(1.4, Y0 + 1.46, 1.55), Vector2(1.5, 0.8))
	b.tier = 1
	b.brush(acc, Mat.EMISSIVE)
	b.box(Vector3(0.0, Y0 + 0.9, 2.42), Vector3(4.0, 0.16, 0.04), 0.0)
	b.brush(_p(pal, "base"))
	for i in 5:
		b.box(Vector3((float(i) - 2.0) * 0.9, Y0 + 0.5, 2.41), Vector3(0.06, 0.8, 0.03), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(0.0, Y0 + 1.6, 1.5)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.24, 0.0), 0.95, 16, 0.02)
	b.brush(sec)
	b.tapered_box(pv + Vector3(0.0, 0.55, 0.3), Vector2(1.5, 1.9), Vector2(1.1, 1.5), 0.62, Vector2.ZERO, 0.05)
	_barrel_rig(b, c, pv, pv.y + 0.7, pv.z - 0.2, 0.6)
	b.brush(_p(pal, "metal"), Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.11, pv.y + 0.72, pv.z - 2.2), Vector3(0.09, 0.16, 4.2), 0.01)
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, pv.y + 0.64, pv.z - 2.2), Vector3(0.28, 0.12, 4.0), 0.0)
	b.brush(acc, Mat.EMISSIVE)
	b.box(Vector3(0.0, pv.y + 0.72, pv.z - 4.3), Vector3(0.34, 0.2, 0.24), 0.0)
	b.socket(&"muzzle0_0", Vector3(0.0, pv.y + 0.72, pv.z - 4.4), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.clear_part()


## OLM Sunwall Projector: teal cowl over a copper prism / lens tower with heat fins and a gold emitter.
static func _sunwall(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var cu: Color = _p(pal, "acc")
	var teal: Color = _p(pal, "dark")
	b.brush(sec)
	b.tapered_box(Vector3(0.0, Y0 + 0.6, 0.0), Vector2(4.6, 4.6), Vector2(3.4, 3.4), 1.2, Vector2.ZERO, 0.08)
	b.brush(cu)
	b.box(Vector3(0.0, Y0 + 1.25, 0.0), Vector3(3.5, 0.12, 3.5), 0.03)
	_team(b, pal, Vector3(0.0, Y0 + 1.33, 1.3), Vector2(1.8, 0.6))
	# heat fins
	b.tier = 1
	b.brush(cu)
	for sx: float in [-1.0, 1.0]:
		for i in 6:
			b.box(Vector3(sx * 1.9, Y0 + 0.75, (float(i) - 2.5) * 0.5), Vector3(0.1, 0.9, 0.34), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(0.0, Y0 + 1.3, 0.0)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(teal)
	b.tapered_box(pv + Vector3(0.0, 1.5, 0.0), Vector2(2.3, 2.3), Vector2(1.7, 1.9), 2.6, Vector2(0.0, -0.1), 0.06)
	b.brush(cu)
	b.frustum(pv + Vector3(0.0, 2.8, 0.0), pv + Vector3(0.0, 3.2, 0.0), 1.2, 1.0, 14, true)
	b.dome(pv + Vector3(0.0, 3.2, 0.0), Vector3.UP, 1.0, 0.7, 14, 3)
	# lens assembly facing forward (-Z)
	b.brush(cu, Mat.METAL)
	b.frustum(pv + Vector3(0.0, 1.9, -1.0), pv + Vector3(0.0, 1.9, -1.9), 0.6, 0.85, 14, true)
	b.brush(Color(1.0, 0.85, 0.35), Mat.EMISSIVE)
	b.cylinder(pv + Vector3(0.0, 1.9, -1.88), pv + Vector3(0.0, 1.9, -1.96), 0.62, 14, 0.0)
	b.socket(&"muzzle0_0", pv + Vector3(0.0, 1.9, -1.98), Vector3(0.0, 0.0, -1.0), Pt.TURRET)
	b.clear_part()


## DEF Citadel Mortar: squat armoured pit with a fat mortar tube at 70 degrees and ammunition stacks.
static func _citadel(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var base: Color = _p(pal, "base")
	var sec: Color = _p(pal, "sec")
	b.brush(base)
	for s in 4:
		var ang: float = PI * 0.5 * float(s)
		var horiz: bool = s % 2 == 0
		b.box(Vector3(cos(ang) * 2.0, Y0 + 0.6, sin(ang) * 2.0), Vector3(4.6 if not horiz else 1.0, 1.2, 4.6 if horiz else 1.0), 0.06)
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, Y0 + 0.1, 0.0), Vector3(3.4, 0.2, 3.4), 0.0)
	b.brush(sec)
	for s in 4:
		var ang: float = PI * 0.5 * float(s)
		b.box(Vector3(cos(ang) * 2.0, Y0 + 1.27, sin(ang) * 2.0), Vector3(4.7 if s % 2 else 1.1, 0.12, 1.1 if s % 2 else 4.7), 0.02)
	# ammo stacks
	_team(b, pal, Vector3(0.7, Y0 + 1.36, 2.0), Vector2(1.6, 0.5))
	b.tier = 1
	b.brush(_p(pal, "acc"))
	for i in 3:
		b.box(Vector3(-1.8 + 0.42 * float(i), Y0 + 1.5, 1.95), Vector3(0.36, 0.36, 0.5), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(0.0, Y0 + 0.4, 0.2)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.5, 0.0), 1.0, 14, 0.03)
	_barrel_rig(b, c, pv, pv.y + 0.6, pv.z, 0.4)
	b.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(70.0)), pv + Vector3(0.0, 0.6, 0.0)))
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -3.4), 0.34, 14, 0.02)
	b.brush(base)
	b.cylinder(Vector3(0.0, 0.0, -1.5), Vector3(0.0, 0.0, -2.0), 0.46, 14, 0.03)
	b.brush(sec)
	b.cylinder(Vector3(0.0, 0.0, -3.3), Vector3(0.0, 0.0, -3.45), 0.4, 14, 0.0)
	b.socket(&"muzzle0_0", Vector3(0.0, 0.0, -3.5), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.pop()
	b.clear_part()


## PD Sea Spear Battery: white sealed box, six coral-capped tubes angled 50 degrees and a small drone pad.
static func _sea_spear(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	b.brush(_p(pal, "base"))
	b.cylinder(Vector3(0.0, Y0, 0.0), Vector3(0.0, Y0 + 0.3, 0.0), 2.55, 24, 0.04)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 1.1, -0.2), Vector3(3.6, 1.6, 3.4), 0.12)
	b.brush(acc)
	b.box(Vector3(0.0, Y0 + 0.5, 1.5), Vector3(3.2, 0.14, 0.05), 0.0)
	_team(b, pal, Vector3(0.0, Y0 + 1.93, 1.15), Vector2(2.4, 0.32))
	b.tier = 1
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, Y0 + 0.9, 1.55), Vector3(1.6, 1.0, 0.06), 0.0)
	b.tier = 0
	ViewMacrosStructures.run("pad", b, {"center": Vector3(1.6, Y0 + 0.3, 1.5), "size": Vector3(1.4, 0.05, 1.4), "mark": "ring", "col": acc, "base": _p(pal, "dark")}, pal)
	var pv: Vector3 = Vector3(0.0, Y0 + 1.9, -0.2)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.2, 0.0), 1.1, 14, 0.02)
	_barrel_rig(b, c, pv, pv.y + 0.3, pv.z, 0.2)
	b.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(50.0)), pv + Vector3(0.0, 0.3, 0.0)))
	b.brush(sec)
	b.box(Vector3(0.0, 0.0, -0.9), Vector3(2.2, 0.5, 1.9), 0.06)
	for col_i in 3:
		for row_i in 2:
			var tp: Vector3 = Vector3((float(col_i) - 1.0) * 0.68, 0.2, -0.2 - 0.6 * float(row_i) - 0.4)
			b.brush(_p(pal, "metal"), Mat.METAL)
			b.cylinder(tp, tp + Vector3(0.0, 0.0, -1.0), 0.24, 10, 0.0)
			b.brush(acc)
			b.cylinder(tp + Vector3(0.0, 0.0, -0.96), tp + Vector3(0.0, 0.0, -1.06), 0.27, 10, 0.0)
	b.socket(&"muzzle0_0", Vector3(0.0, 0.2, -1.9), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.pop()
	b.clear_part()


## HAN Dragon Tooth Launcher: jade tower with six missile teeth up-forward on a crimson-capped rack.
static func _dragon_tooth(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var base: Color = _p(pal, "base")
	var sec: Color = _p(pal, "sec")
	var acc: Color = _p(pal, "acc")
	b.brush(base)
	b.tapered_box(Vector3(0.0, Y0 + 1.3, 0.0), Vector2(3.6, 3.6), Vector2(2.4, 2.4), 2.6, Vector2.ZERO, 0.08)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 2.66, 0.0), Vector3(2.7, 0.14, 2.7), 0.03)
	_team(b, pal, Vector3(0.0, Y0 + 2.76, 1.1), Vector2(2.0, 0.3))
	b.tier = 1
	b.brush(_p(pal, "dark"))
	for k in 3:
		b.box(Vector3(0.0, Y0 + 0.9 + 0.7 * float(k), 1.75 - 0.15 * float(k)), Vector3(1.6, 0.06, 0.06), 0.0)
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	for k in 3:
		b.box(Vector3(0.0, Y0 + 0.7 + 0.7 * float(k), 1.7 - 0.15 * float(k)), Vector3(0.1, 0.45, 0.03), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(0.0, Y0 + 2.75, 0.0)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "dark"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.2, 0.0), 0.9, 12, 0.02)
	_barrel_rig(b, c, pv, pv.y + 0.4, pv.z, 0.2)
	b.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(55.0)), pv + Vector3(0.0, 0.4, 0.0)))
	b.brush(base)
	b.box(Vector3(0.0, 0.0, -0.3), Vector3(1.8, 0.4, 1.0), 0.05)
	for k in 6:
		var x: float = ((k % 3) - 1.0) * 0.5
		var y: float = 0.28 if k < 3 else -0.05
		b.brush(sec)
		b.cylinder(Vector3(x, y, -0.5), Vector3(x, y, -2.4), 0.18, 8, 0.0)
		b.brush(acc)
		b.frustum(Vector3(x, y, -2.4), Vector3(x, y, -2.95), 0.18, 0.02, 8, false)
	b.socket(&"muzzle0_0", Vector3(0.0, 0.1, -2.9), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.pop()
	b.clear_part()


## AE Forge Cannon: patchwork base, a rapid-cycling turret with a visible ammo drum and cyan cooling collars on the barrel.
static func _forge(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var base: Color = _p(pal, "base")
	var cyan: Color = _p(pal, "acc")
	b.brush(base)
	b.box(Vector3(-0.6, Y0 + 0.5, 0.0), Vector3(3.2, 1.0, 4.6), 0.06)
	b.brush(base.lightened(0.14))
	b.box(Vector3(1.8, Y0 + 0.4, 0.4), Vector3(1.6, 0.8, 3.8), 0.05)
	b.brush(_p(pal, "dark"))
	b.box(Vector3(0.0, Y0 + 1.02, 0.0), Vector3(4.4, 0.08, 4.6), 0.0)
	_team(b, pal, Vector3(-0.6, Y0 + 1.1, 1.75), Vector2(2.4, 0.6))
	b.tier = 1
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(1.2, Y0 + 0.8, -1.8), Vector3(1.2, Y0 + 2.0, -1.8), 0.09, 6, 0.0)
	b.cylinder(Vector3(1.6, Y0 + 0.8, -1.8), Vector3(1.6, Y0 + 1.6, -1.8), 0.09, 6, 0.0)
	b.brush(cyan, Mat.EMISSIVE)
	b.box(Vector3(-0.6, Y0 + 0.5, 2.32), Vector3(2.4, 0.12, 0.03), 0.0)
	b.tier = 0
	var pv: Vector3 = Vector3(-0.4, Y0 + 1.1, 0.2)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.2, 0.0), 1.05, 16, 0.02)
	b.brush(base)
	b.tapered_box(pv + Vector3(0.0, 0.6, 0.0), Vector2(1.7, 2.0), Vector2(1.3, 1.5), 0.8, Vector2.ZERO, 0.05)
	b.brush(_p(pal, "sec"))
	b.cylinder(pv + Vector3(-0.85, 0.65, 0.35), pv + Vector3(-1.35, 0.65, 0.35), 0.5, 14, 0.03)
	b.brush(cyan, Mat.EMISSIVE)
	b.cylinder(pv + Vector3(-1.35, 0.65, 0.35), pv + Vector3(-1.4, 0.65, 0.35), 0.3, 10, 0.0)
	_barrel_rig(b, c, pv, pv.y + 0.75, pv.z - 0.5, 0.35)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(0.0, pv.y + 0.75, pv.z - 0.5), Vector3(0.0, pv.y + 0.75, pv.z - 2.6), 0.13, 10, 0.0)
	for k in 3:
		b.brush(cyan, Mat.EMISSIVE)
		b.cylinder(Vector3(0.0, pv.y + 0.75, pv.z - 1.0 - 0.55 * float(k)), Vector3(0.0, pv.y + 0.75, pv.z - 1.15 - 0.55 * float(k)), 0.24, 10, 0.0)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(0.0, pv.y + 0.75, pv.z - 2.5), Vector3(0.0, pv.y + 0.75, pv.z - 2.7), 0.2, 10, 0.0)
	b.socket(&"muzzle0_0", Vector3(0.0, pv.y + 0.75, pv.z - 2.72), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.clear_part()


## SAP Bastion Missile Tower: 6 m stepped tower with a twin-tube launcher on top, saffron caps and a paddle sensor.
static func _bastion(b: ViewMeshBuilder, pal: Dictionary, c: Vector3) -> void:
	var sec: Color = _p(pal, "sec")
	var dark: Color = _p(pal, "dark")
	var acc: Color = _p(pal, "acc")
	b.brush(dark)
	b.box(Vector3(0.0, Y0 + 0.7, 0.0), Vector3(4.6, 1.4, 4.6), 0.08)
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 2.0, 0.0), Vector3(3.6, 1.2, 3.6), 0.06)
	b.brush(dark)
	b.box(Vector3(0.0, Y0 + 3.15, 0.0), Vector3(2.6, 1.1, 2.6), 0.06)
	_team(b, pal, Vector3(0.0, Y0 + 2.62, 1.55), Vector2(2.6, 0.3))
	b.brush(sec)
	b.box(Vector3(0.0, Y0 + 3.8, 0.0), Vector3(3.0, 0.2, 3.0), 0.04)
	b.tier = 1
	b.brush(_p(pal, "light"), Mat.EMISSIVE)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.7, Y0 + 2.2, 1.81), Vector3(0.2, 0.6, 0.03), 0.0)
	b.tier = 0
	b.brush(dark)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_beam(b, Vector3(sx * 2.3, Y0 + 0.2, sz * 2.3), Vector3(sx * 1.6, Y0 + 2.6, sz * 1.6), 0.24)
	var pv: Vector3 = Vector3(0.0, Y0 + 3.9, 0.0)
	b.set_part(Pt.TURRET, pv + c)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(pv, pv + Vector3(0.0, 0.2, 0.0), 0.9, 12, 0.02)
	b.brush(sec)
	b.box(pv + Vector3(0.0, 0.5, 0.0), Vector3(1.6, 0.55, 1.5), 0.05)
	_barrel_rig(b, c, pv, pv.y + 0.8, pv.z, 0.2)
	b.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(30.0)), pv + Vector3(0.0, 0.8, 0.0)))
	for k in 2:
		var x: float = (-0.38 if k == 0 else 0.38)
		b.brush(_p(pal, "metal"), Mat.METAL)
		b.cylinder(Vector3(x, 0.0, 0.3), Vector3(x, 0.0, -1.5), 0.26, 10, 0.0)
		b.brush(acc)
		b.cylinder(Vector3(x, 0.0, -1.5), Vector3(x, 0.0, -1.62), 0.29, 10, 0.0)
		b.socket(StringName("muzzle0_%d" % k), Vector3(x, 0.0, -1.64), Vector3(0.0, 0.0, -1.0), Pt.BARREL)
	b.pop()
	b.clear_part()
	# paddle sensor on a short mast
	var sv: Vector3 = Vector3(-1.3, Y0 + 4.5, -0.9)
	b.brush(_p(pal, "metal"), Mat.METAL)
	b.cylinder(Vector3(sv.x, Y0 + 3.9, sv.z), sv, 0.05, 6, 0.0)
	b.set_part(Pt.RADAR, sv + c, 0.0, 0.7)
	b.brush(sec)
	b.box(sv + Vector3(0.0, 0.15, 0.0), Vector3(0.9, 0.34, 0.06), 0.02)
	b.brush(acc)
	b.box(sv + Vector3(0.0, 0.15, 0.05), Vector3(0.96, 0.4, 0.03), 0.0)
	b.clear_part()
