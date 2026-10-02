class_name DemoModels
extends RefCounted
## Primitive-only procedural placeholder models. They exist to prove the icon-baking + battlefield pipeline;
## the game itself will build models from JSON recipes (ViewModelBuilder). Forward is -Z, ground is y = 0.

const KINDS_INFANTRY := ["infantry", "infantry_at", "medic", "engineer"]

## Maps a bible unit/structure name to a model kind by keyword (demo heuristic).
static func kind_for(name: String, category: String) -> String:
	var n: String = name.to_lower()
	match category:
		"structures":
			for k in ["headquarters", "generator", "refinery", "barracks", "factory", "dock", "radar", "airfield", "laboratory"]:
				if n.contains(k):
					return k
			return "superweapon"
		"defense":
			if n.contains("watchtower"):
				return "tower"
			if n.contains("aa"):
				return "aa_battery"
			if n.contains("anti-tank"):
				return "turret"
			return "cannon"
		"infantry":
			if n.contains("medic") or n.contains("operator") or n.contains("relay"):
				return "medic"
			if n.contains("engineer"):
				return "engineer"
			if n.contains("javelin") or n.contains("lance") or n.contains("team") or n.contains("launcher"):
				return "infantry_at"
			return "infantry"
		"vehicles":
			if n.contains("collector"):
				return "collector"
			if n.contains("mobile construction"):
				return "mcv"
			for k in ["aa", "sam", "flak"]:
				if n.contains(k) and not n.contains("carrier"):
					return "aa"
			for k in ["howitzer", "artillery", "mortar", "rocket", "missile", "launcher", "siege", "mass driver"]:
				if n.contains(k):
					return "artillery"
			for k in ["apc", "carrier", "transport", "ifv", "walker"]:
				if n.contains(k):
					return "apc"
			for k in ["scout", "recon", "ranger", "runner", "pathfinder", "buggy", "raider"]:
				if n.contains(k) and not n.contains("apc"):
					return "recon"
			if n.contains("heavy") or n.contains("bastion") or n.contains("citadel") or n.contains("emperor"):
				return "tank_heavy"
			if n.contains("light") or n.contains("hussar"):
				return "tank_light"
			return "tank_medium"
		"aircraft":
			if n.contains("gunship") or n.contains("heli") or n.contains("rotor"):
				return "gunship"
			if n.contains("bomber") or n.contains("drone"):
				return "bomber"
			return "jet"
		"naval":
			if n.contains("landing") or n.contains("transport"):
				return "barge"
			if n.contains("arsenal") or n.contains("carrier") or n.contains("drone ship"):
				return "arsenal"
			if n.contains("frigate") or n.contains("escort") or n.contains("destroyer") or n.contains("cruiser"):
				return "frigate"
			return "boat"
	return "tank_medium"

static func build(kind: String, team: Color) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var pal := _Pal.new(team)
	match kind:
		"infantry", "infantry_at", "medic", "engineer":
			_infantry(root, kind, pal)
		"tank_light":
			_tank(root, pal, 2.6, 1.5, 0.8, 1.3, false)
		"tank_medium":
			_tank(root, pal, 3.3, 1.9, 1.0, 1.9, false)
		"tank_heavy":
			_tank(root, pal, 3.8, 2.3, 1.2, 2.2, true)
		"apc":
			_apc(root, pal)
		"artillery":
			_artillery(root, pal)
		"aa":
			_aa(root, pal)
		"recon":
			_recon(root, pal)
		"collector":
			_collector(root, pal)
		"mcv":
			_mcv(root, pal)
		"jet":
			_jet(root, pal)
		"gunship":
			_gunship(root, pal)
		"bomber":
			_bomber(root, pal)
		"boat":
			_ship(root, pal, 7.0, 2.2, 1)
		"frigate":
			_ship(root, pal, 11.0, 3.0, 2)
		"arsenal":
			_ship(root, pal, 15.0, 4.2, 4)
		"barge":
			_barge(root, pal)
		_:
			_structure(root, kind, pal)
	return root

# --- palette + primitive kit ---------------------------------------------------------------------------

class _Pal:
	var hull: StandardMaterial3D
	var hull2: StandardMaterial3D
	var accent: StandardMaterial3D
	var dark: StandardMaterial3D
	var metal: StandardMaterial3D
	var glass: StandardMaterial3D
	var glow: StandardMaterial3D
	var team: Color
	func _init(t: Color) -> void:
		team = t
		var body: Color = t.lerp(Color(0.30, 0.32, 0.29), 0.86)
		hull = DemoModels._mat(body, 0.30, 0.55)
		hull2 = DemoModels._mat(body.darkened(0.30), 0.4, 0.5)
		accent = DemoModels._mat(t.darkened(0.12), 0.15, 0.45)
		dark = DemoModels._mat(Color(0.07, 0.075, 0.08), 0.2, 0.85)
		metal = DemoModels._mat(Color(0.20, 0.21, 0.23), 0.85, 0.35)
		glass = DemoModels._mat(Color(0.25, 0.75, 0.95), 0.6, 0.1, 0.6)
		glow = DemoModels._mat(t.lightened(0.3), 0.0, 0.3, 2.2)

static func _mat(c: Color, metal: float = 0.25, rough: float = 0.6, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m

static func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi

static func _cyl(p: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, seg: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi

static func _sph(p: Node3D, r: float, pos: Vector3, mat: Material, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	p.add_child(mi)
	return mi

static func _prism(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi

static func _caps(p: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	return mi

# --- vehicles ----------------------------------------------------------------------------------------------

static func _tank(root: Node3D, pal: _Pal, length: float, width: float, height: float, barrel: float, heavy: bool) -> void:
	var tw: float = width * 0.27
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(tw, height * 0.42, length), Vector3(sx * (width * 0.5 - tw * 0.5), height * 0.28, 0.0), pal.dark)
		_box(root, Vector3(tw * 0.55, height * 0.10, length * 0.9), Vector3(sx * (width * 0.5 - tw * 0.5), height * 0.52, 0.0), pal.hull2)
		for i in 5:
			_cyl(root, height * 0.17, height * 0.17, tw * 1.02, Vector3(sx * (width * 0.5 - tw * 0.5), height * 0.2, (float(i) - 2.0) * length * 0.2), pal.metal, Vector3(0, 0, 90))
	_box(root, Vector3(width - tw * 1.2, height * 0.34, length * 0.86), Vector3(0.0, height * 0.55, 0.0), pal.hull)
	_box(root, Vector3(width * 0.78, height * 0.06, length * 0.30), Vector3(0.0, height * 0.66, -length * 0.36), pal.hull, Vector3(-24.0, 0, 0))
	_box(root, Vector3(width * 0.66, height * 0.08, length * 0.34), Vector3(0.0, height * 0.73, length * 0.33), pal.hull2)
	_box(root, Vector3(width * 0.26, height * 0.05, length * 0.12), Vector3(-width * 0.2, height * 0.71, -length * 0.05), pal.accent)
	var ty: float = height * 0.72
	_box(root, Vector3(width * 0.66, height * 0.30, length * 0.44), Vector3(0.0, ty + height * 0.14, length * 0.03), pal.hull)
	_box(root, Vector3(width * 0.6, height * 0.13, length * 0.30), Vector3(0.0, ty + height * 0.34, length * 0.02), pal.hull2, Vector3(0, 0, 0))
	_box(root, Vector3(width * 0.70, height * 0.07, length * 0.16), Vector3(0.0, ty + height * 0.05, length * 0.04), pal.accent)
	_cyl(root, width * 0.13, width * 0.13, height * 0.12, Vector3(width * 0.16, ty + height * 0.46, length * 0.10), pal.hull2)
	var barrel_y: float = ty + height * 0.22
	_cyl(root, width * 0.055, width * 0.055, barrel, Vector3(0.0, barrel_y, -length * 0.22 - barrel * 0.5), pal.metal, Vector3(90, 0, 0), 10)
	_cyl(root, width * 0.09, width * 0.09, length * 0.13, Vector3(0.0, barrel_y, -length * 0.2), pal.hull2, Vector3(90, 0, 0), 10)
	_cyl(root, width * 0.075, width * 0.075, length * 0.07, Vector3(0.0, barrel_y, -length * 0.22 - barrel), pal.metal, Vector3(90, 0, 0), 10)
	if heavy:
		_box(root, Vector3(width * 0.2, height * 0.16, length * 0.32), Vector3(-width * 0.28, ty + height * 0.16, length * 0.08), pal.hull2)
		_box(root, Vector3(width * 0.2, height * 0.16, length * 0.32), Vector3(width * 0.28, ty + height * 0.16, length * 0.08), pal.hull2)
	_cyl(root, 0.015, 0.015, height * 0.9, Vector3(width * 0.28, ty + height * 0.62, length * 0.28), pal.dark)

static func _wheels(root: Node3D, pal: _Pal, count: int, x: float, z0: float, z1: float, r: float, y: float) -> void:
	for sx in [-1.0, 1.0]:
		for i in count:
			var z: float = lerpf(z0, z1, float(i) / float(maxi(count - 1, 1)))
			_cyl(root, r, r, r * 0.8, Vector3(sx * x, y, z), pal.dark, Vector3(0, 0, 90), 14)
			_cyl(root, r * 0.5, r * 0.5, r * 0.85, Vector3(sx * x, y, z), pal.metal, Vector3(0, 0, 90), 10)

static func _apc(root: Node3D, pal: _Pal) -> void:
	_wheels(root, pal, 3, 0.98, -1.35, 1.35, 0.42, 0.42)
	_box(root, Vector3(1.75, 0.75, 3.7), Vector3(0.0, 0.85, 0.0), pal.hull)
	_box(root, Vector3(1.6, 0.06, 1.0), Vector3(0.0, 1.14, -1.55), pal.hull, Vector3(-28, 0, 0))
	_box(root, Vector3(1.55, 0.45, 1.9), Vector3(0.0, 1.4, 0.55), pal.hull2)
	_box(root, Vector3(1.2, 0.06, 0.8), Vector3(0.0, 1.62, 0.4), pal.accent)
	_box(root, Vector3(1.5, 0.28, 0.06), Vector3(0.0, 1.44, -0.42), pal.glass, Vector3(-18, 0, 0))
	_cyl(root, 0.36, 0.36, 0.22, Vector3(0.0, 1.5, -0.7), pal.hull2)
	_cyl(root, 0.045, 0.045, 1.2, Vector3(0.0, 1.55, -1.35), pal.metal, Vector3(90, 0, 0), 8)
	_box(root, Vector3(0.14, 0.4, 0.1), Vector3(-0.45, 1.6, -0.7), pal.hull2)

static func _artillery(root: Node3D, pal: _Pal) -> void:
	_wheels(root, pal, 3, 1.0, -1.5, 1.5, 0.44, 0.44)
	_box(root, Vector3(1.9, 0.6, 4.3), Vector3(0.0, 0.85, 0.0), pal.hull)
	_box(root, Vector3(1.6, 0.06, 0.9), Vector3(0.0, 1.05, -2.0), pal.hull, Vector3(-25, 0, 0))
	_box(root, Vector3(1.3, 0.75, 1.2), Vector3(0.0, 1.55, 1.15), pal.hull2)
	_box(root, Vector3(1.2, 0.05, 0.5), Vector3(0.0, 1.95, 1.15), pal.accent)
	_box(root, Vector3(1.2, 0.3, 0.8), Vector3(0.0, 1.35, -0.2), pal.hull2)
	_cyl(root, 0.20, 0.20, 0.5, Vector3(0.0, 1.62, -0.1), pal.hull, Vector3(0, 0, 90))
	_cyl(root, 0.075, 0.075, 3.6, Vector3(0.0, 2.25, -1.32), pal.metal, Vector3(58, 0, 0), 10)
	_cyl(root, 0.11, 0.11, 0.5, Vector3(0.0, 3.08, -2.6), pal.hull2, Vector3(58, 0, 0), 10)
	_box(root, Vector3(0.14, 0.5, 0.3), Vector3(0.0, 1.5, -0.7), pal.dark)

static func _aa(root: Node3D, pal: _Pal) -> void:
	_tank(root, pal, 3.0, 1.8, 0.85, 0.2, false)
	for sx in [-1.0, 1.0]:
		_cyl(root, 0.06, 0.06, 1.9, Vector3(sx * 0.32, 1.85, -0.7), pal.metal, Vector3(55, 0, 0), 10)
		_cyl(root, 0.10, 0.10, 0.5, Vector3(sx * 0.32, 1.42, -0.15), pal.hull2, Vector3(55, 0, 0), 10)
	_box(root, Vector3(1.0, 0.5, 0.9), Vector3(0.0, 1.35, 0.35), pal.hull2)
	_cyl(root, 0.42, 0.42, 0.06, Vector3(0.0, 1.85, 0.55), pal.metal, Vector3(0, 0, 0), 20)
	_box(root, Vector3(0.05, 0.4, 0.05), Vector3(0.0, 1.62, 0.55), pal.dark)

static func _recon(root: Node3D, pal: _Pal) -> void:
	_wheels(root, pal, 2, 0.95, -1.0, 1.0, 0.5, 0.5)
	_box(root, Vector3(1.5, 0.45, 2.9), Vector3(0.0, 0.85, 0.0), pal.hull)
	_box(root, Vector3(1.3, 0.05, 0.9), Vector3(0.0, 1.0, -1.35), pal.hull, Vector3(-22, 0, 0))
	_box(root, Vector3(1.2, 0.4, 1.1), Vector3(0.0, 1.3, 0.15), pal.hull2)
	_box(root, Vector3(1.05, 0.22, 0.05), Vector3(0.0, 1.36, -0.42), pal.glass, Vector3(-20, 0, 0))
	_cyl(root, 0.02, 0.02, 1.7, Vector3(0.45, 1.9, 0.9), pal.dark)
	_box(root, Vector3(0.6, 0.35, 0.05), Vector3(0.0, 1.75, 0.9), pal.accent, Vector3(0, 0, 0))
	_box(root, Vector3(1.0, 0.1, 0.9), Vector3(0.0, 1.05, 1.0), pal.hull2)

static func _collector(root: Node3D, pal: _Pal) -> void:
	_wheels(root, pal, 3, 1.05, -1.7, 1.5, 0.5, 0.5)
	_box(root, Vector3(1.9, 0.5, 4.6), Vector3(0.0, 0.95, 0.0), pal.hull2)
	_box(root, Vector3(1.8, 1.0, 1.3), Vector3(0.0, 1.55, -1.6), pal.hull)
	_box(root, Vector3(1.6, 0.5, 0.06), Vector3(0.0, 1.85, -2.26), pal.glass, Vector3(-12, 0, 0))
	_box(root, Vector3(1.7, 0.9, 2.5), Vector3(0.0, 1.65, 0.85), pal.dark)
	_box(root, Vector3(1.55, 0.06, 2.3), Vector3(0.0, 2.12, 0.85), pal.accent)
	for i in 5:
		_box(root, Vector3(1.3, 0.3, 0.3), Vector3(0.0, 2.0 + float(i % 2) * 0.05, 0.1 + float(i) * 0.4), pal.accent.duplicate() as Material)
	_cyl(root, 0.5, 0.5, 0.3, Vector3(0.0, 0.6, 2.5), pal.metal, Vector3(90, 0, 0))

static func _mcv(root: Node3D, pal: _Pal) -> void:
	_wheels(root, pal, 4, 1.15, -1.9, 1.9, 0.5, 0.5)
	_box(root, Vector3(2.2, 0.6, 5.4), Vector3(0.0, 0.95, 0.0), pal.hull)
	_box(root, Vector3(2.0, 1.0, 1.3), Vector3(0.0, 1.6, -2.0), pal.hull2)
	_box(root, Vector3(1.8, 0.45, 0.06), Vector3(0.0, 1.9, -2.66), pal.glass, Vector3(-14, 0, 0))
	_box(root, Vector3(2.0, 1.5, 3.2), Vector3(0.0, 1.95, 0.9), pal.hull2)
	_box(root, Vector3(1.9, 0.1, 3.0), Vector3(0.0, 2.75, 0.9), pal.accent)
	_box(root, Vector3(0.3, 0.3, 2.2), Vector3(-0.7, 3.0, 0.9), pal.metal)
	_cyl(root, 0.6, 0.6, 0.12, Vector3(0.4, 3.1, 1.6), pal.metal, Vector3(0, 0, 0), 20)

static func _infantry(root: Node3D, kind: String, pal: _Pal) -> void:
	var offs: Array[Vector3] = [Vector3(0, 0, 0), Vector3(-0.9, 0, 0.55), Vector3(0.9, 0, 0.55)]
	if kind == "engineer" or kind == "medic":
		offs = [Vector3(0, 0, 0), Vector3(0.9, 0, 0.55)]
	for i in offs.size():
		var o: Vector3 = offs[i]
		_caps(root, 0.26, 1.15, o + Vector3(0, 0.85, 0), pal.hull2 if i > 0 else pal.hull)
		_sph(root, 0.2, o + Vector3(0, 1.62, 0), pal.dark)
		_sph(root, 0.23, o + Vector3(0, 1.66, 0), pal.hull, Vector3(1.0, 0.72, 1.0))
		_box(root, Vector3(0.14, 0.42, 0.34), o + Vector3(0, 1.1, 0.24), pal.accent)
		_box(root, Vector3(0.09, 0.09, 0.9), o + Vector3(0.25, 1.15, -0.35), pal.metal)
		_box(root, Vector3(0.22, 0.6, 0.16), o + Vector3(-0.1, 0.32, 0.0), pal.dark)
		_box(root, Vector3(0.22, 0.6, 0.16), o + Vector3(0.1, 0.32, 0.0), pal.dark)
	if kind == "infantry_at":
		_cyl(root, 0.11, 0.11, 1.3, Vector3(0.0, 1.55, 0.05), pal.metal, Vector3(78, 0, 0), 10)
		_cyl(root, 0.16, 0.16, 0.25, Vector3(0.0, 1.5, -0.55), pal.accent, Vector3(78, 0, 0), 10)
	elif kind == "medic":
		_box(root, Vector3(0.5, 0.5, 0.05), Vector3(0.0, 1.15, 0.3), _mat(Color(0.95, 0.95, 0.95)))
		_box(root, Vector3(0.3, 0.1, 0.06), Vector3(0.0, 1.15, 0.33), _mat(Color(0.9, 0.15, 0.15)))
		_box(root, Vector3(0.1, 0.3, 0.06), Vector3(0.0, 1.15, 0.33), _mat(Color(0.9, 0.15, 0.15)))
	elif kind == "engineer":
		_box(root, Vector3(0.45, 0.4, 0.3), Vector3(0.0, 1.0, 0.35), pal.accent)
		_sph(root, 0.26, Vector3(0.0, 1.76, 0.0), _mat(Color(0.95, 0.75, 0.1)), Vector3(1.0, 0.6, 1.0))

# --- aircraft ------------------------------------------------------------------------------------------------

static func _jet(root: Node3D, pal: _Pal) -> void:
	var y: float = 1.6
	_cyl(root, 0.32, 0.4, 5.0, Vector3(0.0, y, 0.0), pal.hull, Vector3(90, 0, 0), 14)
	_cyl(root, 0.05, 0.32, 1.6, Vector3(0.0, y, -3.2), pal.hull2, Vector3(90, 0, 0), 14)
	_sph(root, 0.36, Vector3(0.0, y + 0.3, -0.9), pal.glass, Vector3(0.9, 0.7, 2.2))
	_box(root, Vector3(4.3, 0.09, 1.9), Vector3(-1.75, y - 0.05, 0.5), pal.hull2, Vector3(0, -32, 4))
	_box(root, Vector3(4.3, 0.09, 1.9), Vector3(1.75, y - 0.05, 0.5), pal.hull2, Vector3(0, 32, -4))
	_box(root, Vector3(0.6, 0.5, 0.06), Vector3(-3.4, y - 0.05, 1.5), pal.accent)
	_box(root, Vector3(0.6, 0.5, 0.06), Vector3(3.4, y - 0.05, 1.5), pal.accent)
	_box(root, Vector3(2.0, 0.07, 0.9), Vector3(-0.85, y, 2.2), pal.hull2, Vector3(0, -28, 0))
	_box(root, Vector3(2.0, 0.07, 0.9), Vector3(0.85, y, 2.2), pal.hull2, Vector3(0, 28, 0))
	_box(root, Vector3(0.07, 1.0, 1.0), Vector3(-0.25, y + 0.55, 2.3), pal.accent, Vector3(0, 0, -12))
	_box(root, Vector3(0.07, 1.0, 1.0), Vector3(0.25, y + 0.55, 2.3), pal.accent, Vector3(0, 0, 12))
	_cyl(root, 0.24, 0.3, 0.5, Vector3(0.0, y, 2.6), pal.glow, Vector3(90, 0, 0), 12)
	_cyl(root, 0.02, 0.02, 1.6, Vector3(0.0, 0.8, 0.0), pal.dark)

static func _gunship(root: Node3D, pal: _Pal) -> void:
	var y: float = 1.7
	_sph(root, 0.9, Vector3(0.0, y, 0.0), pal.hull, Vector3(0.9, 0.85, 1.9))
	_sph(root, 0.55, Vector3(0.0, y + 0.15, -1.15), pal.glass, Vector3(0.95, 0.75, 1.0))
	_cyl(root, 0.12, 0.28, 2.8, Vector3(0.0, y + 0.1, 2.5), pal.hull2, Vector3(90, 0, 0), 10)
	_box(root, Vector3(0.06, 0.8, 0.5), Vector3(0.0, y + 0.55, 3.75), pal.accent, Vector3(-18, 0, 0))
	var rotor: MeshInstance3D = _cyl(root, 3.2, 3.2, 0.02, Vector3(0.0, y + 1.05, 0.0), _mat(Color(0.05, 0.05, 0.06, 0.22), 0.0, 1.0), Vector3.ZERO, 32)
	(rotor.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rotor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(root, 0.12, 0.12, 0.35, Vector3(0.0, y + 0.95, 0.0), pal.metal)
	_box(root, Vector3(2.4, 0.09, 0.6), Vector3(0.0, y + 0.1, 0.1), pal.hull2)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.7, 0.16, 0.16), Vector3(sx * 1.15, y - 0.1, -0.1), pal.metal)
		_cyl(root, 0.12, 0.12, 0.55, Vector3(sx * 1.3, y - 0.05, -0.55), pal.accent, Vector3(90, 0, 0), 8)
		_box(root, Vector3(0.09, 0.09, 3.0), Vector3(sx * 0.75, 0.35, 0.0), pal.dark)
		_box(root, Vector3(0.08, y - 0.4, 0.08), Vector3(sx * 0.75, 0.95, -0.7), pal.dark)
		_box(root, Vector3(0.08, y - 0.4, 0.08), Vector3(sx * 0.75, 0.95, 0.8), pal.dark)

static func _bomber(root: Node3D, pal: _Pal) -> void:
	var y: float = 1.7
	_prism(root, Vector3(9.0, 0.5, 5.0), Vector3(0.0, y, 0.0), pal.hull, Vector3(-90, 0, 0))
	_sph(root, 0.5, Vector3(0.0, y + 0.25, -0.9), pal.glass, Vector3(1.2, 0.6, 1.8))
	_box(root, Vector3(0.9, 0.06, 0.5), Vector3(-2.2, y + 0.29, 0.8), pal.accent)
	_box(root, Vector3(0.9, 0.06, 0.5), Vector3(2.2, y + 0.29, 0.8), pal.accent)
	for sx in [-1.0, 1.0]:
		_cyl(root, 0.22, 0.26, 1.2, Vector3(sx * 0.9, y + 0.1, 1.2), pal.hull2, Vector3(90, 0, 0), 10)
		_cyl(root, 0.18, 0.2, 0.2, Vector3(sx * 0.9, y + 0.1, 1.85), pal.glow, Vector3(90, 0, 0), 10)

# --- naval -------------------------------------------------------------------------------------------------

static func _ship(root: Node3D, pal: _Pal, length: float, width: float, tier: int) -> void:
	var h: float = width * 0.55
	_box(root, Vector3(width, h, length * 0.78), Vector3(0.0, h * 0.5 + 0.1, length * 0.11), pal.hull)
	_prism(root, Vector3(width, length * 0.26, h), Vector3(0.0, h * 0.5 + 0.1, -length * 0.39), pal.hull, Vector3(-90, 0, 0))
	_box(root, Vector3(width * 1.02, 0.12, length * 0.78), Vector3(0.0, h + 0.14, length * 0.11), pal.dark)
	_box(root, Vector3(width * 0.94, 0.06, length * 0.7), Vector3(0.0, h + 0.19, length * 0.11), pal.hull2)
	_box(root, Vector3(width * 0.9, h * 0.06, length * 0.6), Vector3(0.0, h * 0.2 + 0.1, length * 0.11), pal.accent)
	var sh: float = width * 0.7
	_box(root, Vector3(width * 0.62, sh, length * 0.24), Vector3(0.0, h + 0.2 + sh * 0.5, length * 0.14), pal.hull)
	_box(root, Vector3(width * 0.52, sh * 0.5, length * 0.14), Vector3(0.0, h + 0.2 + sh * 1.2, length * 0.16), pal.hull2)
	_box(root, Vector3(width * 0.5, sh * 0.16, 0.06), Vector3(0.0, h + 0.2 + sh * 1.16, length * 0.16 - length * 0.07), pal.glass)
	_cyl(root, 0.03, 0.03, sh * 1.5, Vector3(0.0, h + 0.2 + sh * 1.9, length * 0.16), pal.dark)
	_box(root, Vector3(width * 0.4, 0.06, 0.06), Vector3(0.0, h + 0.2 + sh * 1.7, length * 0.16), pal.metal)
	for i in tier:
		var z: float = -length * 0.30 + float(i) * length * 0.16 * (1.0 if tier < 3 else 0.85)
		if i % 2 == 0:
			z = -length * 0.28 - float(i) * 0.4
		_cyl(root, width * 0.16, width * 0.18, 0.22, Vector3(0.0, h + 0.3, z), pal.hull2)
		_cyl(root, 0.06, 0.06, width * 0.9, Vector3(0.0, h + 0.4, z - width * 0.45), pal.metal, Vector3(90, 0, 0), 8)
	if tier >= 2:
		for j in 4:
			_box(root, Vector3(width * 0.5, 0.14, 0.5), Vector3(0.0, h + 0.28, length * 0.42 - float(j) * 0.6), pal.dark)
	if tier >= 4:
		_box(root, Vector3(width * 0.8, 0.3, length * 0.28), Vector3(0.0, h + 0.3, length * 0.36), pal.hull2)

static func _barge(root: Node3D, pal: _Pal) -> void:
	_box(root, Vector3(3.6, 1.0, 8.0), Vector3(0.0, 0.6, 0.6), pal.hull)
	_box(root, Vector3(3.2, 0.1, 7.6), Vector3(0.0, 1.14, 0.6), pal.hull2)
	_box(root, Vector3(3.2, 0.1, 2.4), Vector3(0.0, 0.9, -4.5), pal.metal, Vector3(-20, 0, 0))
	_box(root, Vector3(3.0, 1.6, 1.8), Vector3(0.0, 1.9, 3.4), pal.hull2)
	_box(root, Vector3(2.8, 0.4, 0.06), Vector3(0.0, 2.2, 2.5), pal.glass)
	_box(root, Vector3(3.0, 0.16, 5.4), Vector3(0.0, 1.22, -0.4), pal.accent)

# --- structures -----------------------------------------------------------------------------------------------

static func _structure(root: Node3D, kind: String, pal: _Pal) -> void:
	match kind:
		"headquarters":
			_box(root, Vector3(9.0, 3.2, 8.0), Vector3(0, 1.6, 0), pal.hull)
			_box(root, Vector3(7.0, 2.0, 6.0), Vector3(0, 4.2, 0.4), pal.hull2)
			_box(root, Vector3(5.0, 1.4, 4.0), Vector3(0, 5.9, 0.6), pal.hull)
			_box(root, Vector3(9.2, 0.35, 8.2), Vector3(0, 3.3, 0), pal.accent)
			_box(root, Vector3(3.4, 2.2, 0.3), Vector3(0, 1.1, -4.05), pal.dark)
			_box(root, Vector3(6.2, 0.5, 0.2), Vector3(0, 4.6, -2.65), pal.glass)
			_cyl(root, 1.6, 0.4, 0.5, Vector3(-1.5, 7.0, 0.6), pal.metal, Vector3(0, 0, 0), 20)
			_cyl(root, 0.1, 0.1, 2.6, Vector3(2.0, 7.9, 0.6), pal.dark)
			_box(root, Vector3(1.4, 0.7, 0.05), Vector3(2.75, 8.8, 0.6), pal.accent)
		"generator":
			_box(root, Vector3(6.0, 1.2, 6.0), Vector3(0, 0.6, 0), pal.hull2)
			for sx in [-1.0, 1.0]:
				_cyl(root, 1.1, 1.3, 3.4, Vector3(sx * 1.6, 2.9, 0), pal.hull, Vector3.ZERO, 20)
				_cyl(root, 1.15, 1.15, 0.3, Vector3(sx * 1.6, 4.65, 0), pal.accent, Vector3.ZERO, 20)
				_cyl(root, 0.5, 0.5, 0.5, Vector3(sx * 1.6, 5.0, 0), pal.glow, Vector3.ZERO, 12)
			_box(root, Vector3(4.6, 0.2, 0.3), Vector3(0, 2.2, 0), pal.metal)
			_box(root, Vector3(1.6, 1.4, 1.6), Vector3(0, 1.9, 2.0), pal.dark)
		"refinery":
			_box(root, Vector3(8.0, 1.0, 8.0), Vector3(0, 0.5, 0), pal.hull2)
			_box(root, Vector3(4.0, 3.0, 5.0), Vector3(-1.5, 2.5, 0.5), pal.hull)
			_cyl(root, 1.4, 1.4, 4.4, Vector3(2.5, 3.2, -2.0), pal.hull, Vector3.ZERO, 20)
			_cyl(root, 1.4, 1.4, 4.4, Vector3(2.5, 3.2, 2.0), pal.hull, Vector3.ZERO, 20)
			_cyl(root, 1.45, 1.45, 0.4, Vector3(2.5, 4.2, -2.0), pal.accent, Vector3.ZERO, 20)
			_cyl(root, 1.45, 1.45, 0.4, Vector3(2.5, 4.2, 2.0), pal.accent, Vector3.ZERO, 20)
			_cyl(root, 0.3, 0.3, 4.4, Vector3(2.5, 5.0, 0.0), pal.metal, Vector3(90, 0, 0), 10)
			_box(root, Vector3(3.6, 0.3, 3.0), Vector3(-1.5, 4.15, 0.5), pal.accent)
			_cyl(root, 0.35, 0.5, 3.2, Vector3(-3.0, 5.6, 1.6), pal.dark)
		"barracks":
			_box(root, Vector3(9.0, 2.6, 5.0), Vector3(0, 1.3, 0), pal.hull)
			_prism(root, Vector3(9.4, 1.2, 5.4), Vector3(0, 3.2, 0), pal.hull2)
			_box(root, Vector3(9.1, 0.3, 5.1), Vector3(0, 2.6, 0), pal.accent)
			for i in 4:
				_box(root, Vector3(0.9, 1.2, 0.1), Vector3(-3.0 + float(i) * 2.0, 1.4, -2.55), pal.glass)
			_box(root, Vector3(1.6, 2.0, 0.15), Vector3(0, 1.0, 2.55), pal.dark)
		"factory":
			_box(root, Vector3(11.0, 4.0, 9.0), Vector3(0, 2.0, 0), pal.hull)
			_box(root, Vector3(11.2, 0.5, 9.2), Vector3(0, 4.15, 0), pal.accent)
			_box(root, Vector3(11.0, 1.6, 3.0), Vector3(0, 5.0, -2.0), pal.hull2)
			_box(root, Vector3(6.0, 3.2, 0.3), Vector3(0, 1.6, -4.55), pal.dark)
			for sx in [-1.0, 1.0]:
				_cyl(root, 0.5, 0.6, 4.0, Vector3(sx * 4.0, 6.0, 2.5), pal.metal)
				_cyl(root, 0.62, 0.62, 0.3, Vector3(sx * 4.0, 8.0, 2.5), pal.accent)
			_box(root, Vector3(12.0, 0.4, 0.5), Vector3(0, 6.2, 3.4), pal.metal)
		"dock":
			_box(root, Vector3(12.0, 0.8, 7.0), Vector3(0, 0.4, 0), pal.hull2)
			_box(root, Vector3(6.0, 3.0, 3.0), Vector3(-2.5, 2.3, 1.8), pal.hull)
			_box(root, Vector3(0.5, 6.0, 0.5), Vector3(3.5, 3.8, 2.5), pal.accent)
			_box(root, Vector3(0.4, 0.4, 7.0), Vector3(3.5, 6.8, -0.8), pal.accent)
			_box(root, Vector3(0.12, 4.0, 0.12), Vector3(3.5, 4.7, -3.8), pal.dark)
			_box(root, Vector3(2.0, 0.3, 2.0), Vector3(5.0, 0.6, -1.0), pal.dark)
		"radar":
			_box(root, Vector3(6.0, 3.0, 6.0), Vector3(0, 1.5, 0), pal.hull)
			_box(root, Vector3(6.2, 0.35, 6.2), Vector3(0, 3.1, 0), pal.accent)
			_cyl(root, 0.5, 0.7, 1.6, Vector3(0, 4.0, 0), pal.metal)
			_cyl(root, 3.2, 0.6, 0.9, Vector3(0, 5.5, 0), pal.hull2, Vector3(-52, 0, 20), 28)
			_cyl(root, 0.12, 0.12, 2.4, Vector3(0.0, 6.2, -1.2), pal.metal, Vector3(-52, 0, 20))
		"airfield":
			_box(root, Vector3(9.0, 0.3, 16.0), Vector3(0, 0.15, 0), pal.dark)
			for i in 5:
				_box(root, Vector3(0.3, 0.05, 1.6), Vector3(0, 0.32, -6.0 + float(i) * 3.0), pal.accent)
			_box(root, Vector3(5.0, 3.0, 6.0), Vector3(-6.5, 1.5, 3.0), pal.hull)
			_cyl(root, 2.5, 2.5, 6.0, Vector3(-6.5, 3.0, 3.0), pal.hull2, Vector3(90, 0, 0), 20)
			_box(root, Vector3(1.4, 4.2, 1.4), Vector3(5.5, 2.1, -4.5), pal.hull)
			_box(root, Vector3(2.4, 1.2, 2.4), Vector3(5.5, 4.8, -4.5), pal.glass)
		"laboratory":
			_box(root, Vector3(8.0, 2.2, 8.0), Vector3(0, 1.1, 0), pal.hull)
			_sph(root, 3.0, Vector3(0, 2.2, 0), pal.hull2, Vector3(1.0, 0.9, 1.0))
			_cyl(root, 3.6, 3.6, 0.3, Vector3(0, 2.3, 0), pal.accent, Vector3.ZERO, 32)
			_cyl(root, 0.25, 0.25, 3.0, Vector3(0, 6.0, 0), pal.metal)
			_sph(root, 0.5, Vector3(0, 7.6, 0), pal.glow)
		"tower":
			_box(root, Vector3(2.4, 0.6, 2.4), Vector3(0, 0.3, 0), pal.hull2)
			_cyl(root, 0.45, 0.7, 5.0, Vector3(0, 3.1, 0), pal.hull)
			_box(root, Vector3(2.0, 1.2, 2.0), Vector3(0, 6.2, 0), pal.hull2)
			_box(root, Vector3(2.1, 0.16, 2.1), Vector3(0, 6.9, 0), pal.accent)
			_box(root, Vector3(1.7, 0.45, 0.06), Vector3(0, 6.3, -1.02), pal.glass)
			_cyl(root, 0.03, 0.03, 1.8, Vector3(0.8, 7.9, 0.8), pal.dark)
		"turret":
			_cyl(root, 1.7, 2.0, 0.9, Vector3(0, 0.45, 0), pal.hull2, Vector3.ZERO, 8)
			_cyl(root, 1.0, 1.2, 0.8, Vector3(0, 1.3, 0), pal.hull, Vector3.ZERO, 8)
			_box(root, Vector3(1.3, 0.6, 1.4), Vector3(0, 1.9, 0.1), pal.hull2)
			_cyl(root, 0.11, 0.11, 2.6, Vector3(0, 1.9, -1.9), pal.metal, Vector3(90, 0, 0), 10)
			_box(root, Vector3(1.4, 0.1, 0.6), Vector3(0, 2.25, 0.4), pal.accent)
		"aa_battery":
			_cyl(root, 1.8, 2.1, 0.8, Vector3(0, 0.4, 0), pal.hull2, Vector3.ZERO, 8)
			_box(root, Vector3(2.6, 0.9, 2.2), Vector3(0, 1.3, 0), pal.hull)
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.7, 0.7, 2.4), Vector3(sx * 0.9, 2.3, -0.3), pal.dark, Vector3(-38, 0, 0))
				_cyl(root, 0.22, 0.22, 0.3, Vector3(sx * 0.9, 2.95, -1.35), pal.accent, Vector3(52, 0, 0), 8)
			_cyl(root, 0.4, 0.4, 0.1, Vector3(0, 1.85, 0.8), pal.metal)
		"cannon":
			_cyl(root, 2.2, 2.5, 1.0, Vector3(0, 0.5, 0), pal.hull2, Vector3.ZERO, 10)
			_box(root, Vector3(2.6, 1.4, 2.8), Vector3(0, 1.7, 0), pal.hull)
			_cyl(root, 0.24, 0.24, 4.6, Vector3(0, 2.1, -3.0), pal.metal, Vector3(90, 0, 0), 12)
			_cyl(root, 0.4, 0.4, 1.4, Vector3(0, 2.1, -1.0), pal.hull2, Vector3(90, 0, 0), 12)
			_box(root, Vector3(2.8, 0.14, 1.2), Vector3(0, 2.45, 0.6), pal.accent)
		_:
			_cyl(root, 3.2, 3.6, 1.4, Vector3(0, 0.7, 0), pal.hull2, Vector3.ZERO, 12)
			_cyl(root, 2.2, 2.6, 4.0, Vector3(0, 3.4, 0), pal.hull, Vector3.ZERO, 12)
			_cyl(root, 2.7, 2.7, 0.35, Vector3(0, 5.5, 0), pal.accent, Vector3.ZERO, 12)
			_box(root, Vector3(0.5, 6.0, 0.5), Vector3(0, 8.0, 0), pal.metal)
			_cyl(root, 1.5, 1.5, 0.25, Vector3(0, 6.3, 0), pal.glow, Vector3.ZERO, 24)
			_sph(root, 0.5, Vector3(0, 11.2, 0), pal.glow)
