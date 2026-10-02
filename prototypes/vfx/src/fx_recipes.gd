class_name FxRecipes
extends RefCounted
## Effect recipes: pure compositions of FxManager primitives. Signature of every recipe:
##   static func name(m: FxManager, a: Vector3, b: Vector3, s: float) -> void
## a = origin, b = destination (LINE effects; b.x = duration for some AREA effects), s = effect-specific scale
## (documented per recipe). Distances are metres (1 sim cell = 3 m), times are seconds.
## Recipes never read or write simulation state and use randf() freely (presentation only).

const UP: Vector3 = Vector3.UP


static func _dir(a: Vector3, b: Vector3) -> Vector3:
	var d: Vector3 = b - a
	var l: float = d.length()
	return d / l if l > 0.001 else Vector3.FORWARD


static func _disc(radius: float) -> Vector3:
	var ang: float = randf() * TAU
	var r: float = sqrt(randf()) * radius
	return Vector3(cos(ang) * r, 0.25, sin(ang) * r)


## Generic ground explosion. r = fireball radius in metres. Composition scales with r.
static func explode(m: FxManager, p: Vector3, r: float, shake_amt: float, scorch_life: float = 45.0) -> void:
	var up: Vector3 = Vector3(0.0, r * 0.3, 0.0)
	m.sprites(&"glow", p + up, r * 1.7, 0.16 + 0.012 * r, 0.7, 0)
	m.sprites(&"flash", p + up, r * 2.2, 0.13, 1.0, 0)
	m.sprites(&"gglow", p, r * 2.2, 0.45 + 0.05 * r, 1.0, 6)
	m.sprites(&"fire", p, r, 0.55 + 0.11 * r, 1.0, 0)
	m.sprites(&"smoke", p, r, 1.7 + 0.3 * r, 1.0, 0)
	m.sprites(&"sparks", p, r, 0.65 + 0.04 * r, 1.0, 0)
	if r >= 1.2:
		m.sprites(&"debris", p, r, 1.0 + 0.06 * r, 1.0, 0)
	if r >= 2.4:
		m.ring(&"ring_distort", p, r * 2.4, 0.5 + 0.03 * r, 0)
		m.ring(&"ring_add", p, r * 2.2, 0.55 + 0.02 * r, 0)
		m.sprites(&"dustring", p, r * 1.25, 1.1 + 0.08 * r, 1.0, 0)
	if r >= 4.5:
		m.sprites(&"dustcol", p, r, 2.2 + 0.2 * r, 1.0, 0)
	m.light_flash(p + Vector3(0.0, r * 0.8, 0.0), Color(1.0, 0.62, 0.25), 3.0 + r * 0.9, 6.0 + r * 3.0, 0.2 + 0.02 * r)
	if scorch_life > 0.0:
		m.scorch(p, r * 0.95, scorch_life, 1.0 if r >= 1.2 else 0.0)
	m.shake(shake_amt, p)


## s = size multiplier (1 = infantry rifle / MG).
static func rifle_shot(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		return
	var dir: Vector3 = _dir(a, b)
	const SPEED: float = 150.0
	m.cone(a, dir, 1.8 * s, 0.9 * s, 0.075)
	m.sprites(&"flash", a + dir * 0.35 * s, 0.9 * s, 0.07, 1.0, 0)
	m.tracer(a + dir * 0.9 * s, b, SPEED, 3.4, 0.11 * s, 0)
	m.schedule(dist / SPEED, &"impact_ground", b, Vector3.ZERO, 0.7 * s)


static func mg_burst(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	for i in 6:
		var jitter: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.9
		m.schedule(float(i) * 0.065, &"rifle_shot", a, b + jitter, s)


## s = calibre multiplier (1 = main battle tank).
static func cannon_shot(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		return
	var dir: Vector3 = _dir(a, b)
	const SPEED: float = 120.0
	m.cone(a, dir, 4.6 * s, 2.4 * s, 0.11)
	m.sprites(&"flash", a + dir * 0.9 * s, 3.0 * s, 0.10, 1.0, 0)
	m.sprites(&"glow", a + dir * 0.6 * s, 6.0 * s, 0.16, 1.0, 0)
	m.sprites(&"sparks", a + dir * 0.8 * s, 0.6 * s, 0.25, 0.6, 0)
	m.puff(&"puff_smoke", a + dir * 1.4 * s + Vector3(0.0, 0.2, 0.0), 2.6 * s, 1.5, 0.55)
	m.puff(&"puff_smoke", a + dir * 2.6 * s + Vector3(0.0, 0.3, 0.0), 3.4 * s, 1.9, 0.4)
	m.light_flash(a + dir * 1.5 * s + Vector3(0.0, 0.8, 0.0), Color(1.0, 0.7, 0.35), 2.2, 9.0 * s, 0.12)
	m.tracer(a + dir * 3.0 * s, b, SPEED, 6.0, 0.30 * s, 1)
	m.shake(0.10 * s, a)
	m.schedule(dist / SPEED, &"cannon_impact", b, Vector3.ZERO, s)


static func cannon_impact(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	explode(m, a, 1.7 * s, 0.10 * s)
	m.puff(&"puff_dust", a + Vector3(0.0, 0.3, 0.0), 3.4 * s, 1.5, 0.75)


static func explosion_small(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	explode(m, a, 1.8 * s, 0.12 * s)


static func explosion_medium(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	explode(m, a, 3.6 * s, 0.30 * s)


static func explosion_large(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	explode(m, a, 8.0 * s, 0.70 * s, 90.0)


## s = size multiplier.
static func missile_launch(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		return
	var dir: Vector3 = _dir(a, b)
	const SPEED: float = 55.0
	var flight: float = dist / SPEED
	var arc: Vector3 = Vector3(0.0, dist * 0.10, 0.0)
	m.sprites(&"flash", a, 1.8 * s, 0.10, 1.0, 0)
	m.sprites(&"glow", a, 4.0 * s, 0.25, 1.0, 6)
	m.cone(a, -dir, 3.2 * s, 1.7 * s, 0.14)
	m.puff(&"puff_white", a - dir * 1.0 * s + Vector3(0.0, 0.3, 0.0), 2.6 * s, 1.8, 0.75)
	m.puff(&"puff_white", a - dir * 2.4 * s + Vector3(0.0, 0.4, 0.0), 3.4 * s, 2.2, 0.55)
	m.light_flash(a + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.65, 0.3), 2.5, 10.0 * s, 0.25)
	m.trail(a, b, flight, 2.8, 0.55 * s, arc)
	m.tracer(a, b, SPEED, 2.6, 0.45 * s, 6, arc)
	m.schedule(flight, &"explosion_medium", b, Vector3.ZERO, s)


static func artillery_shell(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		return
	var dir: Vector3 = _dir(a, b)
	var flight: float = clampf(dist / 30.0, 1.5, 3.2)
	var arc: Vector3 = Vector3(0.0, 8.0 + dist * 0.35, 0.0)
	m.cone(a, dir, 6.0 * s, 3.2 * s, 0.14)
	m.sprites(&"flash", a + dir * 1.2 * s, 4.0 * s, 0.12, 1.0, 0)
	m.sprites(&"glow", a + dir * 0.8 * s, 8.0 * s, 0.2, 1.0, 0)
	m.puff(&"puff_smoke", a + dir * 2.0 * s + Vector3(0.0, 0.5, 0.0), 4.0 * s, 2.2, 0.6)
	m.puff(&"puff_smoke", a + dir * 3.6 * s + Vector3(0.0, 0.8, 0.0), 5.0 * s, 2.6, 0.45)
	m.light_flash(a + Vector3(0.0, 1.5, 0.0), Color(1.0, 0.7, 0.35), 3.0, 14.0 * s, 0.18)
	m.tracer(a, b, dist / flight, 9.0, 0.24 * s, 5, arc)
	m.trail(a, b, flight, 2.4, 0.16 * s, arc)
	m.shake(0.18 * s, a)
	m.schedule(flight, &"explosion_large", b, Vector3.ZERO, s)


## s = width multiplier. Continuous ~1.8 s beam with heat shimmer and a hot impact.
static func beam_thermal(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	const LIFE: float = 1.8
	m.beam(a, b, LIFE, 0.9 * s)
	m.shimmer(a, b, LIFE, 4.2 * s)
	m.scorch(b, 2.0 * s, 40.0, 1.0)
	m.light_flash(b + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.55, 0.2), 3.0, 10.0 * s, LIFE)
	m.start_loop(&"beam_tick", a, b, s, 0.1, LIFE)


static func beam_tick(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	m.sprites(&"glow", b + Vector3(0.0, 0.5, 0.0), 4.0 * s, 0.28, 0.9, 6)
	m.sprites(&"gglow", b, 6.0 * s, 0.30, 0.9, 6)
	m.sprites(&"sparks", b, 0.9 * s, 0.5, 0.7, 0)
	m.sprites(&"glow", a, 2.4 * s, 0.28, 0.8, 6)
	if randf() < 0.35:
		var j: Vector3 = Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))
		m.puff(&"puff_smoke", b + j, 1.8 * s, 1.4, 0.45)


static func beam_rail(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var dir: Vector3 = _dir(a, b)
	m.rail(a, b, 0.5, 0.75 * s)
	m.sprites(&"flash", a + dir * 0.5 * s, 2.4 * s, 0.14, 1.0, 4)
	m.sprites(&"glow", a, 3.2 * s, 0.2, 1.0, 4)
	m.light_flash(a + Vector3(0.0, 1.0, 0.0), Color(0.55, 0.75, 1.0), 2.5, 9.0 * s, 0.2)
	m.schedule(0.03, &"rail_impact", b, Vector3.ZERO, s)


static func rail_impact(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.ring(&"ring_add", a, 5.0 * s, 0.45, 4)
	m.sprites(&"flash", a + Vector3(0.0, 0.5, 0.0), 3.4 * s, 0.15, 1.0, 4)
	m.sprites(&"sparks", a, 1.5 * s, 0.6, 1.0, 4)
	m.sprites(&"debris", a, 1.3 * s, 0.9, 0.5, 0)
	m.puff(&"puff_dust", a + Vector3(0.0, 0.3, 0.0), 2.8 * s, 1.2, 0.6)
	m.light_flash(a + Vector3(0.0, 1.0, 0.0), Color(0.55, 0.75, 1.0), 3.0, 10.0 * s, 0.2)
	m.scorch(a, 1.2 * s, 40.0, 0.0)
	m.shake(0.10 * s, a)


## s = pulse radius in metres.
static func emp_pulse(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.ring(&"ring_emp", a, s, 1.15, 7)
	m.ring(&"ring_emp", a, s * 0.7, 0.85, 4)
	m.ring(&"ring_distort", a, s, 0.9, 0)
	m.sprites(&"glow", a + Vector3(0.0, 0.6, 0.0), s * 0.5, 0.2, 0.6, 7)
	m.sprites(&"gglow", a, s * 1.2, 0.6, 0.5, 7)
	m.sprites(&"sparks", a, s * 0.28, 0.9, 1.4, 7)
	m.light_flash(a + Vector3(0.0, s * 0.6, 0.0), Color(0.45, 0.6, 1.0), 4.0, s * 2.0, 0.5)
	for i in 14:
		m.schedule(randf() * 0.8, &"emp_arc", a + _disc(s * 0.9), a + _disc(s * 0.9), 1.0)


static func emp_arc(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	m.bolt(a, b, randf_range(0.18, 0.4), 0.5 * s, randf_range(0.6, 2.0))


## s = size multiplier (1 = main battle tank).
static func vehicle_destroy(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	explode(m, a + Vector3(0.0, 0.6 * s, 0.0), 3.6 * s, 0.45 * s, 90.0)
	m.sprites(&"fire", a + Vector3(0.0, 1.8 * s, 0.0), 1.5 * s, 1.2, 1.0, 0)
	m.start_loop(&"wreck_tick", a, a, s, 0.22, 14.0)


static func wreck_tick(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	var j: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.8 * s
	m.puff(&"puff_smoke", a + j + Vector3(0.0, 1.2 * s, 0.0), 4.2 * s, 5.0, 0.8)
	if randf() < 0.45:
		m.sprites(&"fire", a + j + Vector3(0.0, 0.8 * s, 0.0), 1.3 * s, 0.8, 0.9, 0)


static func wreck_start(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.start_loop(&"wreck_tick", a, a, s, 0.22, 12.0)


## s = footprint multiplier (1 = 7 m radius structure).
static func building_collapse(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	var r: float = 7.0 * s
	explode(m, a + Vector3(0.0, r * 0.25, 0.0), r * 0.5, 0.9, 0.0)
	m.sprites(&"debris", a, r, 2.6, 1.8, 0)
	m.sprites(&"debris", a, r * 0.6, 2.2, 1.3, 0)
	m.sprites(&"rubble", a, r * 0.7, 30.0, 1.7, 0)
	m.sprites(&"dustring", a, r * 2.8, 3.6, 1.0, 0)
	for i in 4:
		m.schedule(0.05 + float(i) * 0.22, &"collapse_burst", a, Vector3.ZERO, s)
	for i in 6:
		m.puff(&"puff_dust", a + _disc(r * 0.7) + Vector3(0.0, r * 0.3, 0.0), r * 2.2, 4.5, 0.95)
	m.scorch(a, r * 1.25, 120.0, 0.0)
	m.shake(0.85, a)


static func collapse_burst(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	var r: float = 7.0 * s
	var o: Vector3 = _disc(r * 0.6)
	m.sprites(&"dustcol", a + o, r * 1.4, 4.8, 1.0, 0)
	m.sprites(&"dustring", a + o, r * 2.0, 2.8, 1.0, 0)
	m.shake(0.3, a)


static func infantry_hit(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.sprites(&"sparks", a, 0.9 * s, 0.35, 0.5, 0)
	m.sprites(&"flash", a, 0.6 * s, 0.05, 0.8, 0)
	m.puff(&"puff_dust", a, 1.0 * s, 0.6, 0.55)


static func contrail_puff(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.puff(&"puff_white", a, 5.5 * s, 4.5, 0.5)


## a = start (high), b = ground impact. s = size multiplier.
static func aircraft_crash(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var dist: float = a.distance_to(b)
	var flight: float = clampf(dist / 40.0, 1.0, 2.5)
	var arc: Vector3 = Vector3(0.0, -dist * 0.06, 0.0)
	m.trail(a, b, flight, 4.0, 1.5 * s, arc, &"trail_dark")
	m.ribbon(&"firetrail", a, b, flight + 0.7, 1.3 * s, 0.0, flight, 0.7, arc, 0)
	m.schedule(flight, &"explosion_large", b, Vector3.ZERO, 0.8 * s)
	m.schedule(flight + 0.05, &"wreck_start", b, Vector3.ZERO, 1.4)


static func impact_ground(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.puff(&"puff_dust", a + Vector3(0.0, 0.1, 0.0), 0.9 * s, 0.55, 0.7)
	m.sprites(&"debris", a, 0.55 * s, 0.6, 0.35, 0)
	m.sprites(&"sparks", a, 0.45 * s, 0.25, 0.6, 0)


static func impact_water(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.sprites(&"splash", a, 2.0 * s, 1.0, 1.0, 0)
	m.ring(&"ripple", a, 4.0 * s, 1.4, 0)
	m.puff(&"puff_white", a + Vector3(0.0, 0.3, 0.0), 2.6 * s, 1.0, 0.85)


static func vehicle_dust(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.puff(&"puff_dust", a + Vector3(0.0, 0.2, 0.0), 4.6 * s, 2.0, 0.85)


static func construction_sparks(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.start_loop(&"weld_tick", a, a, s, 0.08, 3.0)


static func weld_tick(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	m.sprites(&"sparks", a, 0.8 * s, 0.45, 0.9, 1)
	m.sprites(&"flash", a + Vector3(0.0, 0.15, 0.0), 0.7 * s, 0.06, 0.9, 1)
	if randf() < 0.3:
		m.puff(&"puff_white", a + Vector3(0.0, 0.4, 0.0), 0.9 * s, 1.0, 0.35)


## s = marker radius (m); b.x = warning duration in seconds (default 10). Returns a cancelable handle.
static func sw_warning_marker(m: FxManager, a: Vector3, b: Vector3, s: float) -> void:
	var life: float = b.x if b.x > 0.0 else 10.0
	m.ring(&"marker", a, s, life, 2)
	m.column(&"beacon", a, 0.5, 80.0, life)


## Three guided penetrators, 3 cells (9 m) apart, 2 cell (6 m) damage radius. s = multiplier.
static func sw_orbital_strike(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	for i in 3:
		m.schedule(float(i) * 0.28, &"strike_one", a + Vector3(float(i - 1) * 9.0 * s, 0.0, 0.0), Vector3.ZERO, s)


static func strike_one(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	const LIFE: float = 1.8
	m.column(&"strike", a, 3.2 * s, 90.0, LIFE)
	m.schedule(0.15 * LIFE, &"explosion_large", a, Vector3.ZERO, 0.85 * s)


## 3-cell core + 7-cell fragmentation ring (Perun-style). s = multiplier.
static func sw_shockwave(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	explode(m, a, 9.0 * s, 1.0, 120.0)
	m.ring(&"ring_distort", a, 21.0 * s, 1.6, 0)
	m.ring(&"ring_add", a, 21.0 * s, 1.7, 0)
	m.ring(&"ring_add", a, 11.0 * s, 0.9, 0)
	m.sprites(&"dustring", a, 19.0 * s, 3.4, 1.0, 0)
	m.sprites(&"dustcol", a, 14.0 * s, 8.0, 1.0, 0)
	m.sprites(&"smoke", a + Vector3(0.0, 6.0 * s, 0.0), 12.0 * s, 6.0, 1.0, 0)
	m.sprites(&"glow", a + Vector3(0.0, 6.0 * s, 0.0), 40.0 * s, 0.45, 0.6, 1)
	m.light_flash(a + Vector3(0.0, 10.0 * s, 0.0), Color(1.0, 0.85, 0.6), 14.0, 80.0 * s, 0.7)


## 8-cell radius (24 m) energy dome (Aurora-style). s = multiplier.
static func sw_microwave_dome(m: FxManager, a: Vector3, _b: Vector3, s: float) -> void:
	var r: float = 24.0 * s
	m.dome(a, r, 4.5)
	m.ring(&"ring_emp", a, r, 2.2, 6)
	m.ring(&"haze", a, r, 4.2, 0)
	m.sprites(&"gglow", a, r * 2.0, 2.5, 1.0, 6)
	m.light_flash(a + Vector3(0.0, 8.0 * s, 0.0), Color(1.0, 0.5, 0.2), 5.0, 50.0 * s, 1.5)
	for i in 8:
		var ang: float = randf() * TAU
		var edge: Vector3 = a + Vector3(cos(ang), 0.2, sin(ang)) * r * 0.95
		m.schedule(0.4 + randf() * 3.0, &"emp_arc", edge, a + Vector3(0.0, 9.0 * s, 0.0), 1.6)
