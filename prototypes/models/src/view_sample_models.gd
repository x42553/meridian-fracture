class_name ViewSampleModels
extends RefCounted
## Sample procedural recipes proving the builder: medium tank (4 faction styles), wheeled APC, howitzer, infantry squad,
## gunship, patrol boat, factory. Coordinates: +X right, +Y up, -Z forward, metres, origin on the ground.

const Mat := ViewMeshBuilder.Mat
const Pt := ViewMeshBuilder.Part
const IDS: Array[StringName] = [&"tank", &"apc", &"howitzer", &"infantry", &"gunship", &"boat", &"factory"]


# ------------------------------------------------------------------ palettes / styles
static func palette(faction: StringName) -> Dictionary:
	match faction:
		&"nec":
			return {"base": Color(0.27, 0.36, 0.50), "dark": Color(0.16, 0.21, 0.30), "sec": Color(0.90, 0.92, 0.94), "acc": Color(0.95, 0.62, 0.10),
				"metal": Color(0.30, 0.32, 0.36), "rubber": Color(0.06, 0.06, 0.07), "glass": Color(0.15, 0.30, 0.42), "light": Color(1.0, 0.75, 0.3)}
		&"def":
			return {"base": Color(0.55, 0.22, 0.15), "dark": Color(0.30, 0.31, 0.32), "sec": Color(0.88, 0.82, 0.50), "acc": Color(0.88, 0.80, 0.40),
				"metal": Color(0.33, 0.33, 0.33), "rubber": Color(0.06, 0.06, 0.06), "glass": Color(0.18, 0.28, 0.30), "light": Color(1.0, 0.85, 0.5)}
		&"han":
			return {"base": Color(0.20, 0.48, 0.36), "dark": Color(0.12, 0.28, 0.22), "sec": Color(0.92, 0.90, 0.84), "acc": Color(0.70, 0.12, 0.16),
				"metal": Color(0.34, 0.34, 0.33), "rubber": Color(0.06, 0.06, 0.06), "glass": Color(0.14, 0.30, 0.34), "light": Color(1.0, 0.8, 0.5)}
	return {"base": Color(0.30, 0.35, 0.18), "dark": Color(0.17, 0.20, 0.10), "sec": Color(0.84, 0.78, 0.60), "acc": Color(0.93, 0.37, 0.06),
		"metal": Color(0.32, 0.33, 0.31), "rubber": Color(0.07, 0.07, 0.065), "glass": Color(0.09, 0.20, 0.25), "light": Color(1.0, 0.85, 0.55)}


static func tank_style(faction: StringName) -> Dictionary:
	var s: Dictionary = palette(faction)
	match faction:
		&"nec":
			s.merge({"len": 3.8, "hull_w": 1.80, "hull_top": 0.98, "glacis": 1.25, "track_w": 0.40, "track_x": 0.82, "wheel_n": 6, "wheel_r": 0.25,
				"skirt": "slab", "turret_n": 6, "turret_rot": 30.0, "turret_hw": 0.62, "turret_hl": 1.15, "turret_h": 0.30, "turret_top": 0.55, "turret_z": 0.42,
				"turret_shift": 0.15, "barrel_len": 2.7, "barrel_r": 0.058, "muzzle": "plain", "roof": "mast", "deck": "none", "seed": 11})
		&"def":
			s.merge({"len": 3.4, "hull_w": 2.06, "hull_top": 1.24, "glacis": 0.40, "track_w": 0.50, "track_x": 0.95, "wheel_n": 6, "wheel_r": 0.34,
				"skirt": "none", "turret_n": 4, "turret_rot": 45.0, "turret_hw": 0.86, "turret_hl": 0.86, "turret_h": 0.52, "turret_top": 0.90, "turret_z": 0.10,
				"turret_shift": 0.0, "barrel_len": 1.85, "barrel_r": 0.098, "muzzle": "brake", "roof": "cupola", "deck": "container", "seed": 21})
		&"han":
			s.merge({"len": 3.0, "hull_w": 1.72, "hull_top": 1.06, "glacis": 0.85, "track_w": 0.40, "track_x": 0.80, "wheel_n": 4, "wheel_r": 0.27,
				"skirt": "modules", "turret_n": 12, "turret_rot": 15.0, "turret_hw": 0.70, "turret_hl": 0.70, "turret_h": 0.36, "turret_top": 0.78, "turret_z": 0.10,
				"turret_shift": 0.0, "barrel_len": 1.75, "barrel_r": 0.068, "muzzle": "sleeve", "roof": "crown", "deck": "drone_rack", "seed": 31})
		_:
			s.merge({"len": 3.5, "hull_w": 1.92, "hull_top": 1.16, "glacis": 0.75, "track_w": 0.46, "track_x": 0.88, "wheel_n": 5, "wheel_r": 0.30,
				"skirt": "modules", "turret_n": 8, "turret_rot": 22.5, "turret_hw": 0.74, "turret_hl": 0.96, "turret_h": 0.42, "turret_top": 0.72, "turret_z": 0.18,
				"turret_shift": 0.06, "barrel_len": 2.0, "barrel_r": 0.075, "muzzle": "brake", "roof": "cupola", "deck": "none", "seed": 7})
	return s


## Framing / placement metadata: bounding radius (m), height (m), hover offset (m).
static func info(id: StringName) -> Dictionary:
	match id:
		&"tank": return {"radius": 2.9, "height": 2.0, "hover": 0.0, "name": "Guardian Tank"}
		&"apc": return {"radius": 2.4, "height": 1.9, "hover": 0.0, "name": "Pathfinder APC"}
		&"howitzer": return {"radius": 4.2, "height": 2.6, "hover": 0.0, "name": "Paladin Howitzer"}
		&"infantry": return {"radius": 1.2, "height": 1.2, "hover": 0.0, "name": "Rifle Squad"}
		&"gunship": return {"radius": 3.0, "height": 2.6, "hover": 2.6, "name": "Titan Gunship"}
		&"boat": return {"radius": 3.2, "height": 2.4, "hover": 0.0, "name": "Riverwatch Patrol Boat"}
		&"factory": return {"radius": 6.5, "height": 6.5, "hover": 0.0, "name": "Factory"}
	return {"radius": 3.0, "height": 2.0, "hover": 0.0, "name": String(id)}


static func build(id: StringName, style: Dictionary = {}) -> ArrayMesh:
	return make_builder(id, style).build(String(id))


static func make_builder(id: StringName, style: Dictionary = {}) -> ViewMeshBuilder:
	match id:
		&"tank": return _tank(style if not style.is_empty() else tank_style(&"napc"))
		&"apc": return _apc(style if not style.is_empty() else palette(&"napc"))
		&"howitzer": return _howitzer(style if not style.is_empty() else palette(&"napc"))
		&"infantry": return _infantry(style if not style.is_empty() else palette(&"napc"))
		&"gunship": return _gunship(style if not style.is_empty() else palette(&"napc"))
		&"boat": return _boat(style if not style.is_empty() else palette(&"napc"))
		&"factory": return _factory(style if not style.is_empty() else palette(&"napc"))
	push_error("ViewSampleModels: unknown model id %s" % id)
	return ViewMeshBuilder.new()


# ------------------------------------------------------------------ shared helpers
## Antenna whip: thin metal cylinder (tier 1 detail).
static func _whip(b: ViewMeshBuilder, base: Vector3, tip: Vector3, r: float, col: Color) -> void:
	var t: int = b.tier
	b.tier = 1
	b.brush(col, Mat.METAL)
	b.cylinder(base, tip, r, 5, 0.0, false)
	b.tier = t


## Circular hatch: chamfered disc with an accent ring.
static func _hatch(b: ViewMeshBuilder, c: Vector3, r: float, body: Color, ring: Color) -> void:
	b.brush(ring)
	b.cylinder(c, c + Vector3(0.0, 0.05, 0.0), r * 1.12, 14, 0.01)
	b.brush(body)
	b.cylinder(c + Vector3(0.0, 0.05, 0.0), c + Vector3(0.0, 0.085, 0.0), r * 0.92, 14, 0.012)


# ------------------------------------------------------------------ tank
static func _tank(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(int(s.get("seed", 7)))
	b.default_bevel = 0.04
	var base: Color = s["base"]
	var dark: Color = s["dark"]
	var sec: Color = s["sec"]
	var acc: Color = s["acc"]
	var metal: Color = s["metal"]
	var rubber: Color = s["rubber"]
	var glass: Color = s["glass"]
	var light: Color = s["light"]
	var L: float = s.get("len", 3.5)
	var hl: float = L * 0.5
	var hw: float = float(s.get("hull_w", 1.92)) * 0.5
	var hull_top: float = s.get("hull_top", 1.16)
	var glacis: float = s.get("glacis", 0.75)
	var tw: float = s.get("track_w", 0.46)
	var tx: float = s.get("track_x", 0.88)
	var wr: float = s.get("wheel_r", 0.30)
	var wn: int = int(s.get("wheel_n", 5))
	var tk: float = 0.07
	var skirt: String = s.get("skirt", "modules")
	var roof: String = s.get("roof", "cupola")
	var deck: String = s.get("deck", "none")

	# --- running gear (built for +X side, mirrored) ---
	var m0: PackedInt32Array = b.mark()
	b.brush(rubber, Mat.RUBBER)
	b.set_part(Pt.TRACK)
	var circles: Array[Vector3] = [Vector3(hl - 0.42, 0.40 + tk, 0.40), Vector3(-hl + 0.44, 0.40 + tk, 0.40)]
	b.track_belt(tx, tw, circles, tk)
	b.clear_part()
	b.ao = 0.75
	b.wheel(Vector3(tx, 0.40 + tk, hl - 0.42), 0.34, tw * 0.78, rubber, metal, 1, 12)
	b.wheel(Vector3(tx, 0.40 + tk, -hl + 0.44), 0.34, tw * 0.78, rubber, metal, 1, 12)
	for i in wn:
		var z: float = lerpf(-hl + 1.0, hl - 1.0, float(i) / float(maxi(wn - 1, 1)))
		b.wheel(Vector3(tx, wr + tk, z), wr, tw * 0.8, rubber, metal, 1 if wr > 0.32 else 0, 10)
	b.ao = 1.0
	# fender over the belt
	b.brush(dark)
	b.box(Vector3(tx, 0.955, 0.0), Vector3(tw + 0.16, 0.045, L - 0.30), 0.015)
	# side skirts
	match skirt:
		"modules":
			var n: int = 6 if L > 3.2 else 5
			var seg: float = (L - 0.5) / float(n)
			for i in n:
				var z: float = -hl + 0.25 + seg * (float(i) + 0.5)
				var front: bool = i == 0
				b.brush(base if i % 2 == 0 else sec, Mat.PAINT, 1.0 if front else 0.0)
				b.box(Vector3(tx + tw * 0.5 + 0.06, 0.70, z), Vector3(0.09, 0.40, seg - 0.07), 0.02)
				b.brush(acc)
				b.box(Vector3(tx + tw * 0.5 + 0.06, 0.915, z), Vector3(0.10, 0.04, seg - 0.07), 0.0)
		"slab":
			b.brush(base)
			b.box(Vector3(tx + tw * 0.5 + 0.05, 0.72, 0.15), Vector3(0.06, 0.36, L * 0.72), 0.02)
			b.brush(acc)
			b.box(Vector3(tx + tw * 0.5 + 0.055, 0.91, 0.15), Vector3(0.07, 0.03, L * 0.72), 0.0)
	b.mirror_x(m0)

	# --- hull ---
	b.brush(dark)
	b.ao = 0.7
	b.box(Vector3(0.0, 0.58, 0.0), Vector3((tx - tw * 0.5 - 0.02) * 2.0, 0.55, L - 0.15), 0.03)
	b.ao = 1.0
	b.brush(base)
	var prof := PackedVector2Array([Vector2(-hl, 0.86), Vector2(-hl, hull_top - 0.10), Vector2(-hl + 0.5, hull_top), Vector2(hl - glacis, hull_top), Vector2(hl, 0.92), Vector2(hl - 0.05, 0.86)])
	b.extrude(prof, -hw, hw, 0.05)
	# engine deck louvres (pocketed slab) + front team band + lights
	b.brush(metal, Mat.METAL)
	var pk: Array[Rect2] = [Rect2(0.08, 0.10, 0.84, 0.22), Rect2(0.08, 0.40, 0.84, 0.22), Rect2(0.08, 0.70, 0.84, 0.20)]
	b.pocket_box(Vector3(0.0, hull_top + 0.025, hl * 0.42), Vector3(hw * 1.25, 0.05, hl * 0.55), pk, 0.03)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, hull_top + 0.014, -(hl - glacis) * 0.5 - 0.35), Vector3(hw * 1.2, 0.03, 0.34), 0.0)
	b.brush(light, Mat.EMISSIVE)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw - 0.28), 0.97, -hl + 0.02), Vector3(0.20, 0.09, 0.05), 0.0)
	b.brush(Color(1.0, 0.08, 0.04), Mat.EMISSIVE)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw - 0.22), hull_top - 0.16, hl + 0.01), Vector3(0.16, 0.07, 0.04), 0.0)

	# --- turret ---
	var tz: float = s.get("turret_z", 0.18)
	var th: float = s.get("turret_h", 0.42)
	var tn: int = int(s.get("turret_n", 8))
	var t_hw: float = s.get("turret_hw", 0.72)
	var t_hl: float = s.get("turret_hl", 0.95)
	var t_top: float = s.get("turret_top", 0.72)
	var t_rot: float = s.get("turret_rot", 22.5)
	var t_shift: float = s.get("turret_shift", 0.06)
	var ty0: float = hull_top + 0.07
	var pv := Vector3(0.0, hull_top, tz)
	b.brush(dark, Mat.METAL)
	b.cylinder(Vector3(0.0, hull_top - 0.02, tz), Vector3(0.0, ty0, tz), 0.62, 18, 0.01)
	b.set_part(Pt.TURRET, pv)
	b.brush(base)
	var cn: float = cos(PI / float(tn))
	b.prism(ViewMeshBuilder.ngon(Vector3(0.0, ty0, tz), t_hw / cn, t_hl / cn, tn, t_rot),
		ViewMeshBuilder.ngon(Vector3(0.0, ty0 + th, tz + t_shift), t_hw / cn * t_top, t_hl / cn * t_top, tn, t_rot), 0.04)
	var top_y: float = ty0 + th
	var gy: float = ty0 + th * 0.5
	var fz: float = tz - t_hl * (1.0 + t_top) * 0.5 + t_shift * 0.5
	# roof team stripe + bustle
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, top_y + 0.012, tz + t_shift - 0.02), Vector3(t_hw * t_top * 0.75, 0.03, t_hl * t_top * 1.2), 0.0)
	b.brush(base)
	b.box(Vector3(0.0, ty0 + th * 0.42, tz + t_hl * 0.98), Vector3(t_hw * 1.45, th * 0.80, 0.40), 0.03)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, ty0 + th * 0.42, tz + t_hl * 0.98 + 0.205), Vector3(t_hw * 1.05, th * 0.36, 0.02), 0.0)
	# mantlet
	b.brush(dark)
	b.box(Vector3(0.0, gy, fz - 0.02), Vector3(0.58, th * 0.66, 0.30), 0.03)
	# hatches / cupola
	_hatch(b, Vector3(t_hw * 0.36, top_y, tz + t_hl * 0.30), 0.15, sec, acc)
	b.brush(base)
	b.cylinder(Vector3(-t_hw * 0.38, top_y, tz + t_hl * 0.15), Vector3(-t_hw * 0.38, top_y + 0.13, tz + t_hl * 0.15), 0.17, 12, 0.02)
	b.brush(glass, Mat.GLASS)
	b.cylinder(Vector3(-t_hw * 0.38, top_y + 0.07, tz + t_hl * 0.15), Vector3(-t_hw * 0.38, top_y + 0.115, tz + t_hl * 0.15), 0.178, 12, 0.0)
	# smoke dischargers
	b.tier = 1
	b.brush(metal, Mat.METAL)
	for sx in [-1.0, 1.0]:
		for i in 3:
			var z: float = tz - 0.20 + 0.10 * float(i)
			b.cylinder(Vector3(sx * t_hw * 0.80, ty0 + th * 0.66, z), Vector3(sx * (t_hw * 0.80 + 0.13), ty0 + th * 0.72, z), 0.032, 8, 0.0)
	b.tier = 0
	# roof gadget
	match roof:
		"mast":
			b.brush(metal, Mat.METAL)
			b.cylinder(Vector3(-t_hw * 0.35, top_y, tz + t_hl * 0.45), Vector3(-t_hw * 0.35, top_y + 0.55, tz + t_hl * 0.45), 0.035, 8, 0.0)
			b.set_part(Pt.RADAR, Vector3(-t_hw * 0.35, top_y + 0.6, tz + t_hl * 0.45))
			b.brush(sec)
			b.dome(Vector3(-t_hw * 0.35, top_y + 0.56, tz + t_hl * 0.45), Vector3.UP, 0.02, 0.01, 4, 1)
			b.box(Vector3(-t_hw * 0.35, top_y + 0.62, tz + t_hl * 0.45), Vector3(0.62, 0.06, 0.10), 0.01)
			b.brush(acc)
			b.box(Vector3(-t_hw * 0.35, top_y + 0.66, tz + t_hl * 0.45), Vector3(0.62, 0.02, 0.05), 0.0)
			b.set_part(Pt.TURRET, pv)
		"crown":
			b.brush(metal, Mat.METAL)
			b.cylinder(Vector3(0.0, top_y, tz + 0.05), Vector3(0.0, top_y + 0.18, tz + 0.05), 0.08, 8, 0.0)
			b.brush(acc)
			for i in 6:
				var a: float = TAU * float(i) / 6.0
				b.box(Vector3(cos(a) * 0.16, top_y + 0.24, tz + 0.05 + sin(a) * 0.16), Vector3(0.05, 0.16, 0.05), 0.0)
			b.brush(light, Mat.EMISSIVE)
			b.box(Vector3(0.0, top_y + 0.31, tz + 0.05), Vector3(0.10, 0.03, 0.10), 0.0)
		"cupola":
			_whip(b, Vector3(-t_hw * 0.6, top_y, tz + t_hl * 0.85), Vector3(-t_hw * 0.62, top_y + 1.15, tz + t_hl * 0.9), 0.011, metal)
	# gun
	b.set_part(Pt.BARREL, pv, 0.0, 0.32, Vector2(gy, fz))
	var bl: float = s.get("barrel_len", 2.0)
	var br: float = s.get("barrel_r", 0.075)
	var z0: float = fz - 0.14
	b.brush(metal, Mat.METAL)
	b.cylinder(Vector3(0.0, gy, z0 + 0.32), Vector3(0.0, gy, z0 - 0.15), br * 1.55, 12, 0.01)
	b.cylinder(Vector3(0.0, gy, z0), Vector3(0.0, gy, z0 - bl), br, 10, 0.0, true)
	match s.get("muzzle", "brake"):
		"brake":
			b.cylinder(Vector3(0.0, gy, z0 - bl * 0.55 + 0.13), Vector3(0.0, gy, z0 - bl * 0.55 - 0.13), br * 1.75, 10, 0.012)
			b.cylinder(Vector3(0.0, gy, z0 - bl + 0.02), Vector3(0.0, gy, z0 - bl - 0.26), br * 1.7, 10, 0.014)
			b.brush(acc)
			b.cylinder(Vector3(0.0, gy, z0 - bl + 0.34), Vector3(0.0, gy, z0 - bl + 0.28), br * 1.18, 10, 0.0)
		"sleeve":
			b.brush(sec)
			b.cylinder(Vector3(0.0, gy, z0 - 0.10), Vector3(0.0, gy, z0 - bl * 0.66), br * 1.5, 10, 0.01)
			b.brush(acc)
			b.cylinder(Vector3(0.0, gy, z0 - bl * 0.66), Vector3(0.0, gy, z0 - bl * 0.66 - 0.05), br * 1.55, 10, 0.0)
			b.brush(metal, Mat.METAL)
			b.cylinder(Vector3(0.0, gy, z0 - bl + 0.02), Vector3(0.0, gy, z0 - bl - 0.10), br * 1.3, 8, 0.008)
		_:
			b.cylinder(Vector3(0.0, gy, z0 - bl + 0.02), Vector3(0.0, gy, z0 - bl - 0.14), br * 1.35, 8, 0.008)
			b.brush(acc)
			b.cylinder(Vector3(0.0, gy, z0 - bl * 0.5 + 0.03), Vector3(0.0, gy, z0 - bl * 0.5 - 0.03), br * 1.12, 8, 0.0)
	b.clear_part()

	# --- rear deck equipment ---
	var dz: float = hl * 0.55
	match deck:
		"container":
			b.brush(sec)
			b.box(Vector3(0.0, hull_top + 0.32, dz + 0.30), Vector3(hw * 1.5, 0.55, 1.0), 0.02)
			b.brush(dark)
			for i in 6:
				b.box(Vector3(-hw * 0.72 + hw * 1.44 * float(i) / 5.0, hull_top + 0.32, dz + 0.30), Vector3(0.05, 0.53, 1.02), 0.0)
			b.brush(acc)
			b.box(Vector3(0.0, hull_top + 0.605, dz + 0.30), Vector3(hw * 1.5, 0.03, 0.16), 0.0)
		"drone_rack":
			b.brush(metal, Mat.METAL)
			for sx in [-1.0, 1.0]:
				b.box(Vector3(sx * hw * 0.55, hull_top + 0.22, dz + 0.25), Vector3(0.05, 0.36, 0.72), 0.0)
			b.box(Vector3(0.0, hull_top + 0.40, dz + 0.25), Vector3(hw * 1.2, 0.05, 0.72), 0.0)
			for i in 4:
				b.brush(sec)
				var cx: float = -0.36 + 0.24 * float(i)
				b.box(Vector3(cx, hull_top + 0.30, dz + 0.25), Vector3(0.14, 0.05, 0.36), 0.0)
				b.brush(acc)
				b.box(Vector3(cx, hull_top + 0.335, dz + 0.16), Vector3(0.14, 0.02, 0.06), 0.0)
		_:
			b.tier = 1
			b.brush(metal, Mat.METAL)
			b.greebles(Vector3(0.0, hull_top + 0.05, hl * 0.42 + 0.0), Vector3.UP, Vector3(hw * 0.6, 0, 0), Vector3(0, 0, hl * 0.27), 0, 0.1, 0.2, 0.03, 0.08)
			b.tier = 0
	return b


# ------------------------------------------------------------------ wheeled APC
static func _apc(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(3)
	b.default_bevel = 0.04
	var base: Color = s["base"]
	var dark: Color = s["dark"]
	var sec: Color = s["sec"]
	var acc: Color = s["acc"]
	var metal: Color = s["metal"]
	var rubber: Color = s["rubber"]
	var glass: Color = s["glass"]
	var light: Color = s["light"]
	var wx: float = 0.88
	var wzs: Array[float] = [-1.18, 0.10, 1.22]
	# wheels + arches (+X side, mirrored)
	var m0: PackedInt32Array = b.mark()
	b.ao = 0.7
	for z in wzs:
		b.wheel(Vector3(wx, 0.40, z), 0.40, 0.32, rubber, metal, 2, 14)
		b.brush(metal, Mat.METAL)
		b.box(Vector3(0.62, 0.42, z), Vector3(0.36, 0.06, 0.10), 0.0)
	b.ao = 1.0
	b.brush(dark)
	for z in wzs:
		b.box(Vector3(wx - 0.02, 0.86, z), Vector3(0.34, 0.06, 0.96), 0.02)
	b.mirror_x(m0)
	# chassis + body
	b.brush(dark)
	b.ao = 0.7
	b.box(Vector3(0.0, 0.58, 0.0), Vector3(1.50, 0.34, 3.5), 0.03)
	b.ao = 1.0
	b.brush(base)
	b.extrude(PackedVector2Array([Vector2(-1.85, 0.55), Vector2(-1.85, 1.50), Vector2(0.30, 1.62), Vector2(1.05, 1.24), Vector2(1.10, 0.55)]), -0.72, 0.72, 0.05)
	b.extrude(PackedVector2Array([Vector2(0.55, 0.62), Vector2(0.55, 1.10), Vector2(1.75, 1.00), Vector2(1.90, 0.80), Vector2(1.80, 0.62)]), -0.66, 0.66, 0.04)
	# windshield + side windows
	b.brush(glass, Mat.GLASS)
	b.extrude(PackedVector2Array([Vector2(0.34, 1.60), Vector2(1.00, 1.27), Vector2(0.98, 1.23), Vector2(0.32, 1.56)]), -0.52, 0.52, 0.0)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.725, 1.28, -0.35), Vector3(0.03, 0.30, 0.78), 0.0)
		b.box(Vector3(sx * 0.725, 1.28, 0.55), Vector3(0.03, 0.26, 0.52), 0.0)
	# orange stripe + team panels
	b.brush(acc)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.73, 0.92, 0.3), Vector3(0.025, 0.09, 2.8), 0.0)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 1.015, -1.20), Vector3(0.86, 0.03, 0.55), 0.0)
	b.box(Vector3(0.0, 1.635, 0.70), Vector3(0.9, 0.03, 0.9), 0.0)
	# lights, bumper
	b.brush(light, Mat.EMISSIVE)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.48, 0.86, -1.91), Vector3(0.22, 0.10, 0.05), 0.0)
	b.brush(Color(1.0, 0.08, 0.04), Mat.EMISSIVE)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.58, 0.80, 1.86), Vector3(0.14, 0.08, 0.04), 0.0)
	b.brush(dark, Mat.METAL)
	b.box(Vector3(0.0, 0.62, -1.90), Vector3(1.5, 0.16, 0.14), 0.02)
	# roof: hatch, remote weapon (turret), rotating sensor, whips, greebles
	_hatch(b, Vector3(-0.28, 1.62, 0.95), 0.27, sec, acc)
	var rp := Vector3(0.30, 1.63, -0.15)
	b.brush(metal, Mat.METAL)
	b.cylinder(rp, rp + Vector3(0.0, 0.10, 0.0), 0.20, 12, 0.01)
	b.set_part(Pt.TURRET, rp)
	b.brush(dark)
	b.box(rp + Vector3(0.0, 0.22, 0.0), Vector3(0.30, 0.20, 0.42), 0.03)
	b.brush(metal, Mat.METAL)
	b.set_part(Pt.BARREL, rp, 0.0, 0.10, Vector2(rp.y + 0.24, rp.z))
	b.cylinder(rp + Vector3(0.0, 0.24, -0.15), rp + Vector3(0.0, 0.24, -0.85), 0.035, 8, 0.0)
	b.clear_part()
	var sp := Vector3(-0.32, 1.62, 0.35)
	b.brush(metal, Mat.METAL)
	b.cylinder(sp, sp + Vector3(0.0, 0.22, 0.0), 0.03, 8, 0.0)
	b.set_part(Pt.RADAR, sp + Vector3(0.0, 0.26, 0.0))
	b.brush(sec)
	b.box(sp + Vector3(0.0, 0.26, 0.0), Vector3(0.56, 0.05, 0.11), 0.01)
	b.brush(acc)
	b.box(sp + Vector3(0.20, 0.30, 0.0), Vector3(0.14, 0.04, 0.09), 0.0)
	b.clear_part()
	_whip(b, Vector3(0.55, 1.5, 1.7), Vector3(0.50, 2.55, 1.85), 0.012, metal)
	_whip(b, Vector3(-0.55, 1.5, 1.7), Vector3(-0.52, 2.15, 1.80), 0.010, metal)
	b.tier = 1
	b.brush(metal, Mat.METAL)
	b.greebles(Vector3(0.25, 1.60, 1.05), Vector3.UP, Vector3(0.35, 0, 0), Vector3(0, 0, 0.55), 3, 0.10, 0.20, 0.03, 0.07)
	b.tier = 0
	return b


# ------------------------------------------------------------------ self-propelled howitzer
static func _howitzer(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(5)
	b.default_bevel = 0.04
	var base: Color = s["base"]
	var dark: Color = s["dark"]
	var sec: Color = s["sec"]
	var acc: Color = s["acc"]
	var metal: Color = s["metal"]
	var rubber: Color = s["rubber"]
	var L: float = 3.9
	var hl: float = L * 0.5
	var tx: float = 0.90
	var tw: float = 0.46
	var tk: float = 0.07
	var m0: PackedInt32Array = b.mark()
	b.brush(rubber, Mat.RUBBER)
	b.set_part(Pt.TRACK)
	var circles: Array[Vector3] = [Vector3(hl - 0.40, 0.38 + tk, 0.38), Vector3(-hl + 0.42, 0.38 + tk, 0.38)]
	b.track_belt(tx, tw, circles, tk)
	b.clear_part()
	b.ao = 0.75
	b.wheel(Vector3(tx, 0.38 + tk, hl - 0.40), 0.32, tw * 0.78, rubber, metal, 1, 12)
	b.wheel(Vector3(tx, 0.38 + tk, -hl + 0.42), 0.32, tw * 0.78, rubber, metal, 1, 12)
	for i in 6:
		b.wheel(Vector3(tx, 0.26 + tk, lerpf(-hl + 0.95, hl - 0.95, float(i) / 5.0)), 0.26, tw * 0.8, rubber, metal, 0, 10)
	b.ao = 1.0
	b.brush(dark)
	b.box(Vector3(tx, 0.95, 0.0), Vector3(tw + 0.14, 0.05, L - 0.3), 0.015)
	b.mirror_x(m0)
	b.brush(dark)
	b.ao = 0.7
	b.box(Vector3(0.0, 0.58, 0.0), Vector3(1.22, 0.55, L - 0.15), 0.03)
	b.ao = 1.0
	b.brush(base)
	b.extrude(PackedVector2Array([Vector2(-hl, 0.86), Vector2(-hl, 1.18), Vector2(hl - 0.9, 1.20), Vector2(hl, 0.98), Vector2(hl - 0.05, 0.86)]), -0.97, 0.97, 0.05)
	b.brush(acc)
	b.box(Vector3(0.0, 1.215, hl * 0.72), Vector3(1.0, 0.03, 0.14), 0.0)
	# spades (deploy parts): stowed vertical at the rear, rotate down/back when deployed
	for sx in [-0.62, 0.62]:
		b.set_part(Pt.DEPLOY, Vector3(sx, 0.55, hl + 0.06), 1.0, 0.0)
		b.brush(dark, Mat.METAL)
		b.box(Vector3(sx, 0.55 + 0.42, hl + 0.10), Vector3(0.70, 0.84, 0.07), 0.02)
		b.brush(acc)
		b.box(Vector3(sx, 0.55 + 0.80, hl + 0.10), Vector3(0.72, 0.08, 0.09), 0.0)
	b.clear_part()
	# turret (box casemate) with team roof stripe
	var tz: float = 0.55
	var pv := Vector3(0.0, 1.20, tz)
	b.brush(dark, Mat.METAL)
	b.cylinder(Vector3(0.0, 1.16, tz), Vector3(0.0, 1.27, tz), 0.85, 18, 0.01)
	b.set_part(Pt.TURRET, pv)
	b.brush(base)
	b.tapered_box(Vector3(0.0, 1.27 + 0.36, tz + 0.10), Vector2(1.75, 2.4), Vector2(1.35, 1.85), 0.72, Vector2(0.0, 0.20), 0.05)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 2.005, tz + 0.25), Vector3(0.6, 0.03, 0.8), 0.0)
	b.brush(sec)
	b.box(Vector3(0.0, 2.015, tz + 0.75), Vector3(1.0, 0.05, 0.26), 0.01)
	b.brush(dark)
	b.box(Vector3(0.0, 1.62, tz - 0.95), Vector3(0.85, 0.5, 0.30), 0.04)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 1.60, tz + 1.31), Vector3(0.9, 0.30, 0.03), 0.0)
	_hatch(b, Vector3(0.45, 1.99, tz + 0.55), 0.17, sec, acc)
	b.tier = 1
	b.brush(metal, Mat.METAL)
	b.greebles(Vector3(-0.35, 1.995, tz + 0.05), Vector3.UP, Vector3(0.35, 0, 0), Vector3(0, 0, 0.55), 3, 0.10, 0.22, 0.04, 0.09)
	b.tier = 0
	_whip(b, Vector3(-0.60, 1.99, tz + 0.85), Vector3(-0.64, 3.0, tz + 0.95), 0.012, metal)
	# gun: cradle + barrel, trunnion at the mantlet, elevates with the deploy channel (param 0.62 ~ 56 deg)
	var gy: float = 1.62
	var gz: float = tz - 1.10
	b.set_part(Pt.BARREL, pv, 0.62, 0.55, Vector2(gy, gz + 0.1))
	b.brush(metal, Mat.METAL)
	b.cylinder(Vector3(0.0, gy, gz + 0.5), Vector3(0.0, gy, gz - 1.5), 0.15, 12, 0.012)
	b.cylinder(Vector3(0.0, gy, gz - 1.0), Vector3(0.0, gy, gz - 3.35), 0.095, 10, 0.0)
	b.cylinder(Vector3(0.0, gy, gz - 2.35), Vector3(0.0, gy, gz - 2.75), 0.17, 10, 0.012)
	b.cylinder(Vector3(0.0, gy, gz - 3.33), Vector3(0.0, gy, gz - 3.66), 0.16, 10, 0.014)
	b.brush(acc)
	b.cylinder(Vector3(0.0, gy, gz - 1.2), Vector3(0.0, gy, gz - 1.3), 0.105, 10, 0.0)
	b.clear_part()
	b.brush(Color(1.0, 0.08, 0.04), Mat.EMISSIVE)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.78, 1.0, hl + 0.01), Vector3(0.16, 0.07, 0.04), 0.0)
	return b


# ------------------------------------------------------------------ infantry squad (4 soldiers, walk cycle in shader)
static func _soldier(b: ViewMeshBuilder, x0: float, z0: float, phase: float, pal: Dictionary) -> void:
	var base: Color = pal["base"]
	var dark: Color = pal["dark"]
	var sec: Color = pal["sec"]
	var acc: Color = pal["acc"]
	var metal: Color = pal["metal"]
	var glass: Color = pal["glass"]
	var skin := Color(0.72, 0.52, 0.38)
	b.push(ViewMeshBuilder.xf(Vector3(x0, 0.0, z0)))
	for sx in [-1.0, 1.0]:
		b.set_part(Pt.LEG_A if sx < 0.0 else Pt.LEG_B, Vector3(x0 + sx * 0.075, 0.45, z0), phase, 0.0)
		b.brush(dark)
		b.box(Vector3(sx * 0.075, 0.225, 0.0), Vector3(0.12, 0.45, 0.15), 0.0)
		b.brush(Color(0.10, 0.09, 0.08), Mat.RUBBER)
		b.box(Vector3(sx * 0.075, 0.04, -0.03), Vector3(0.13, 0.08, 0.22), 0.0)
	b.set_part(Pt.BODY_BOB, Vector3.ZERO, phase, 0.0)
	b.brush(base)
	b.box(Vector3(0.0, 0.62, 0.0), Vector3(0.36, 0.36, 0.21), 0.012)
	b.brush(dark)
	b.box(Vector3(0.0, 0.50, -0.01), Vector3(0.38, 0.10, 0.23), 0.0)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 0.66, 0.175), Vector3(0.26, 0.32, 0.14), 0.015)
	b.brush(skin)
	b.box(Vector3(0.0, 0.88, 0.0), Vector3(0.14, 0.13, 0.15), 0.0)
	b.brush(sec)
	b.dome(Vector3(0.0, 0.92, 0.0), Vector3.UP, 0.125, 0.11, 10, 3)
	b.brush(acc)
	b.box(Vector3(0.0, 0.955, 0.0), Vector3(0.05, 0.03, 0.26), 0.0)
	b.brush(glass, Mat.GLASS)
	b.box(Vector3(0.0, 0.89, -0.078), Vector3(0.13, 0.045, 0.02), 0.0)
	b.brush(dark)
	b.box(Vector3(0.235, 0.60, -0.10), Vector3(0.09, 0.09, 0.30), 0.0)
	b.brush(metal, Mat.METAL)
	b.box(Vector3(0.20, 0.64, -0.28), Vector3(0.05, 0.07, 0.70), 0.0)
	b.box(Vector3(0.20, 0.57, -0.15), Vector3(0.04, 0.10, 0.07), 0.0)
	b.set_part(Pt.ARM_A, Vector3(x0 - 0.235, 0.78, z0), phase, 0.0)
	b.brush(base)
	b.box(Vector3(-0.235, 0.62, 0.0), Vector3(0.09, 0.30, 0.10), 0.0)
	b.brush(skin)
	b.box(Vector3(-0.235, 0.45, 0.0), Vector3(0.08, 0.07, 0.09), 0.0)
	b.clear_part()
	b.pop()


static func _infantry(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(9)
	b.model_scale = 1.25
	var pts: Array[Vector3] = [Vector3(-0.50, 0, -0.30), Vector3(0.50, 0, -0.34), Vector3(-0.28, 0, 0.46), Vector3(0.58, 0, 0.42)]
	var ph: Array[float] = [0.0, 0.31, 0.62, 0.87]
	for i in 4:
		_soldier(b, pts[i].x, pts[i].z, ph[i], s)
	return b


# ------------------------------------------------------------------ gunship
static func _gunship(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(13)
	b.default_bevel = 0.04
	var base: Color = s["base"]
	var dark: Color = s["dark"]
	var sec: Color = s["sec"]
	var acc: Color = s["acc"]
	var metal: Color = s["metal"]
	var glass: Color = s["glass"]
	var light: Color = s["light"]
	# fuselage
	b.brush(base)
	b.extrude(PackedVector2Array([Vector2(-1.5, 0.85), Vector2(-1.5, 1.50), Vector2(0.1, 1.90), Vector2(1.55, 1.45), Vector2(2.05, 1.10), Vector2(1.45, 0.70), Vector2(-0.4, 0.62)]), -0.56, 0.56, 0.05)
	b.brush(dark)
	b.extrude(PackedVector2Array([Vector2(-1.3, 0.62), Vector2(-1.3, 0.90), Vector2(1.2, 0.90), Vector2(1.5, 0.66), Vector2(1.3, 0.56), Vector2(-1.0, 0.56)]), -0.42, 0.42, 0.03)
	# canopy
	b.brush(glass, Mat.GLASS)
	b.extrude(PackedVector2Array([Vector2(0.55, 1.96), Vector2(1.45, 1.62), Vector2(2.02, 1.17), Vector2(1.0, 1.12)]), -0.40, 0.40, 0.02)
	b.brush(sec)
	b.box(Vector3(0.0, 1.905, 0.05), Vector3(0.72, 0.05, 0.45), 0.01)
	# team spine + tail fin
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 1.905, -0.85), Vector3(0.5, 0.03, 1.4), 0.0)
	# engine nacelles
	for sx in [-1.0, 1.0]:
		b.brush(metal, Mat.METAL)
		b.cylinder(Vector3(sx * 0.70, 1.62, -0.35), Vector3(sx * 0.70, 1.62, -1.75), 0.26, 14, 0.02)
		b.brush(dark)
		b.cylinder(Vector3(sx * 0.70, 1.62, -0.30), Vector3(sx * 0.70, 1.62, 0.55), 0.24, 14, 0.02)
		b.brush(Color(1.0, 0.45, 0.10), Mat.EMISSIVE)
		b.cylinder(Vector3(sx * 0.70, 1.62, -1.76), Vector3(sx * 0.70, 1.62, -1.80), 0.17, 12, 0.0)
	# stub wings, pods, missiles
	b.brush(base)
	b.box(Vector3(0.0, 1.25, 0.25), Vector3(2.9, 0.10, 0.85), 0.02)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 1.31, 0.25), Vector3(2.5, 0.02, 0.5), 0.0)
	for sx in [-1.0, 1.0]:
		b.brush(dark, Mat.METAL)
		b.cylinder(Vector3(sx * 1.05, 1.06, 0.55), Vector3(sx * 1.05, 1.06, -0.55), 0.13, 12, 0.01)
		b.brush(acc)
		b.frustum(Vector3(sx * 1.05, 1.06, -0.55), Vector3(sx * 1.05, 1.06, -0.75), 0.13, 0.05, 10)
		b.brush(sec)
		b.cylinder(Vector3(sx * 1.35, 1.10, 0.45), Vector3(sx * 1.35, 1.10, -0.85), 0.055, 8, 0.0)
		b.brush(acc)
		b.frustum(Vector3(sx * 1.35, 1.10, -0.85), Vector3(sx * 1.35, 1.10, -1.05), 0.055, 0.0, 8)
		b.brush(Color(1.0, 0.1, 0.05) if sx < 0.0 else Color(0.1, 1.0, 0.3), Mat.EMISSIVE)
		b.box(Vector3(sx * 1.47, 1.27, 0.25), Vector3(0.06, 0.06, 0.08), 0.0)
	# tail boom, fin, stabilisers
	b.brush(base)
	b.prism(PackedVector3Array([Vector3(-0.24, 1.05, 1.3), Vector3(0.24, 1.05, 1.3), Vector3(0.24, 1.75, 1.3), Vector3(-0.24, 1.75, 1.3)]),
		PackedVector3Array([Vector3(-0.10, 1.30, 4.2), Vector3(0.10, 1.30, 4.2), Vector3(0.10, 1.62, 4.2), Vector3(-0.10, 1.62, 4.2)]), 0.03)
	b.extrude(PackedVector2Array([Vector2(-4.2, 1.55), Vector2(-4.35, 2.45), Vector2(-3.75, 2.45), Vector2(-3.35, 1.55)]), -0.04, 0.04, 0.01)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 2.15, 4.05), Vector3(0.09, 0.35, 0.42), 0.0)
	b.brush(base)
	b.box(Vector3(0.0, 1.50, 3.9), Vector3(1.5, 0.05, 0.5), 0.01)
	b.brush(light, Mat.EMISSIVE)
	b.set_part(Pt.BLINK, Vector3.ZERO, 0.0, 0.0)
	b.box(Vector3(0.0, 2.48, 4.08), Vector3(0.09, 0.09, 0.09), 0.0)
	b.clear_part()
	# tail rotor
	b.set_part(Pt.TAIL_ROTOR, Vector3(0.16, 2.0, 4.18))
	b.brush(metal, Mat.METAL)
	b.box(Vector3(0.16, 2.0, 4.18), Vector3(0.02, 0.85, 0.09), 0.0)
	b.box(Vector3(0.16, 2.0, 4.18), Vector3(0.02, 0.09, 0.85), 0.0)
	b.clear_part()
	# main rotor (4 blades, orange tips) + mast
	b.brush(metal, Mat.METAL)
	b.cylinder(Vector3(0.0, 1.85, 0.25), Vector3(0.0, 2.36, 0.25), 0.10, 10, 0.0)
	var hub := Vector3(0.0, 2.42, 0.25)
	b.set_part(Pt.ROTOR, hub)
	b.brush(dark, Mat.METAL)
	b.cylinder(hub + Vector3(0.0, -0.06, 0.0), hub + Vector3(0.0, 0.10, 0.0), 0.22, 12, 0.02)
	for i in 4:
		b.push(ViewMeshBuilder.xf(hub, Vector3(0.0, 90.0 * float(i), 0.0)))
		b.brush(dark, Mat.METAL)
		b.box(Vector3(1.4, 0.0, 0.0), Vector3(2.5, 0.035, 0.24), 0.0)
		b.brush(acc)
		b.box(Vector3(2.52, 0.0, 0.0), Vector3(0.34, 0.038, 0.24), 0.0)
		b.pop()
	b.clear_part()
	# chin cannon (turret) + skids
	var cp := Vector3(0.0, 0.64, -1.4)
	b.set_part(Pt.TURRET, cp)
	b.brush(dark, Mat.METAL)
	b.box(cp + Vector3(0.0, -0.04, 0.0), Vector3(0.30, 0.20, 0.42), 0.02)
	b.set_part(Pt.BARREL, cp, 0.0, 0.12, Vector2(cp.y - 0.05, cp.z))
	b.cylinder(cp + Vector3(0.0, -0.05, -0.15), cp + Vector3(0.0, -0.05, -1.05), 0.045, 8, 0.0)
	b.clear_part()
	b.brush(metal, Mat.METAL)
	for sx in [-1.0, 1.0]:
		b.cylinder(Vector3(sx * 0.62, 0.30, 1.0), Vector3(sx * 0.62, 0.30, -1.3), 0.04, 6, 0.0)
		for z in [-0.6, 0.6]:
			b.cylinder(Vector3(sx * 0.62, 0.30, z), Vector3(sx * 0.48, 0.66, z), 0.03, 6, 0.0, false)
	b.brush(light, Mat.EMISSIVE)
	b.box(Vector3(0.0, 0.58, -1.55), Vector3(0.14, 0.04, 0.10), 0.0)
	return b


# ------------------------------------------------------------------ patrol boat
static func _boat(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(17)
	b.default_bevel = 0.035
	var base: Color = s["base"]
	var dark: Color = s["dark"]
	var sec: Color = s["sec"]
	var acc: Color = s["acc"]
	var metal: Color = s["metal"]
	var glass: Color = s["glass"]
	var light: Color = s["light"]
	var top: Array[Vector2] = [Vector2(-0.85, 2.0), Vector2(0.85, 2.0), Vector2(1.0, 0.2), Vector2(0.35, -1.9), Vector2(0.0, -2.5), Vector2(-0.35, -1.9), Vector2(-1.0, 0.2)]
	var bot: Array[Vector2] = [Vector2(-0.45, 1.9), Vector2(0.45, 1.9), Vector2(0.5, 0.2), Vector2(0.12, -1.9), Vector2(0.0, -2.35), Vector2(-0.12, -1.9), Vector2(-0.5, 0.2)]
	var la := PackedVector3Array()
	var lm := PackedVector3Array()
	var lt := PackedVector3Array()
	for i in top.size():
		la.append(Vector3(bot[i].x, -0.25, bot[i].y))
		lt.append(Vector3(top[i].x, 0.55, top[i].y))
		lm.append(Vector3(lerpf(bot[i].x, top[i].x, 0.4), 0.05, lerpf(bot[i].y, top[i].y, 0.4)))
	b.brush(Color(0.42, 0.10, 0.08))
	b.ao = 0.6
	b.prism(la, lm, 0.03)
	b.ao = 1.0
	b.brush(base)
	b.prism(lm, lt, 0.03)
	# deck + cabin
	b.brush(dark)
	b.box(Vector3(0.0, 0.575, 0.2), Vector3(1.9, 0.05, 3.6), 0.0)
	b.brush(base)
	b.tapered_box(Vector3(0.0, 1.05, 0.55), Vector2(1.15, 1.6), Vector2(0.85, 1.2), 0.9, Vector2(0.0, -0.05), 0.04)
	b.brush(glass, Mat.GLASS)
	b.box(Vector3(0.0, 1.15, -0.28), Vector3(0.78, 0.30, 0.04), 0.0)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.56, 1.15, 0.55), Vector3(0.03, 0.28, 0.9), 0.0)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 1.515, 0.52), Vector3(0.7, 0.03, 0.9), 0.0)
	b.brush(acc)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.60, 0.95, 0.55), Vector3(0.03, 0.10, 1.4), 0.0)
	# radar mast + rotating radar + beacon
	b.brush(metal, Mat.METAL)
	b.cylinder(Vector3(0.0, 1.5, 0.75), Vector3(0.0, 2.2, 0.75), 0.05, 8, 0.0)
	b.set_part(Pt.RADAR, Vector3(0.0, 2.25, 0.75))
	b.brush(sec)
	b.box(Vector3(0.0, 2.25, 0.75), Vector3(0.95, 0.05, 0.12), 0.01)
	b.brush(acc)
	b.box(Vector3(0.38, 2.29, 0.75), Vector3(0.18, 0.04, 0.10), 0.0)
	b.clear_part()
	b.set_part(Pt.BLINK, Vector3.ZERO, 0.3, 0.0)
	b.brush(Color(1.0, 0.1, 0.05), Mat.EMISSIVE)
	b.box(Vector3(0.0, 2.34, 0.75), Vector3(0.07, 0.07, 0.07), 0.0)
	b.clear_part()
	# bow gun turret with twin barrels
	var gp := Vector3(0.0, 0.60, -1.25)
	b.brush(metal, Mat.METAL)
	b.cylinder(gp, gp + Vector3(0.0, 0.14, 0.0), 0.34, 14, 0.01)
	b.set_part(Pt.TURRET, gp)
	b.brush(base)
	b.tapered_box(gp + Vector3(0.0, 0.32, 0.0), Vector2(0.50, 0.70), Vector2(0.38, 0.55), 0.36, Vector2(0.0, 0.05), 0.03)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(gp + Vector3(0.0, 0.505, 0.03), Vector3(0.22, 0.02, 0.30), 0.0)
	b.set_part(Pt.BARREL, gp, 0.0, 0.14, Vector2(gp.y + 0.36, gp.z))
	b.brush(metal, Mat.METAL)
	for sx in [-0.10, 0.10]:
		b.cylinder(Vector3(sx, gp.y + 0.36, gp.z - 0.30), Vector3(sx, gp.y + 0.36, gp.z - 1.10), 0.038, 8, 0.0)
	b.clear_part()
	# stern: outboards + life-raft canisters (rescue orange)
	b.brush(dark, Mat.METAL)
	for sx in [-0.45, 0.45]:
		b.box(Vector3(sx, 0.35, 2.12), Vector3(0.30, 0.65, 0.34), 0.03)
		b.cylinder(Vector3(sx, -0.05, 2.30), Vector3(sx, -0.05, 2.45), 0.12, 8, 0.0)
	b.brush(acc)
	for sx in [-0.28, 0.28]:
		b.cylinder(Vector3(sx - 0.30, 0.78, 1.55), Vector3(sx + 0.30, 0.78, 1.55), 0.15, 10, 0.02)
	b.brush(light, Mat.EMISSIVE)
	b.box(Vector3(0.0, 1.32, -0.30), Vector3(0.30, 0.06, 0.06), 0.0)
	_whip(b, Vector3(0.3, 1.5, 1.05), Vector3(0.36, 2.4, 1.12), 0.010, metal)
	return b


# ------------------------------------------------------------------ factory (3x3 cells = 9 m footprint), door faces -Z
static func _factory(s: Dictionary) -> ViewMeshBuilder:
	var b := ViewMeshBuilder.new()
	b.seed_rng(23)
	b.default_bevel = 0.06
	var base: Color = s["base"]
	var dark: Color = s["dark"]
	var sec: Color = s["sec"]
	var acc: Color = s["acc"]
	var metal: Color = s["metal"]
	var glass: Color = s["glass"]
	var light: Color = s["light"]
	var concrete := Color(0.50, 0.49, 0.46)
	# plinth + apron hazard stripes
	b.brush(concrete)
	b.box(Vector3(0.0, 0.07, 0.0), Vector3(9.0, 0.14, 9.0), 0.03)
	b.tier = 1
	for i in 9:
		b.brush(acc if i % 2 == 0 else Color(0.12, 0.12, 0.11))
		b.box(Vector3(-2.0 + 0.5 * float(i), 0.145, -3.85), Vector3(0.38, 0.012, 0.9), 0.0)
	b.tier = 0
	# hall: main volume + front wall pieces around the door opening
	b.brush(base)
	b.box(Vector3(0.0, 1.94, 1.25), Vector3(7.6, 3.6, 5.5), 0.06)
	b.box(Vector3(-2.85, 1.94, -2.75), Vector3(1.9, 3.6, 0.5), 0.05)
	b.box(Vector3(2.85, 1.94, -2.75), Vector3(1.9, 3.6, 0.5), 0.05)
	b.box(Vector3(0.0, 3.44, -2.75), Vector3(3.8, 0.60, 0.5), 0.05)
	# interior backdrop + lights visible through the open door
	b.brush(Color(0.05, 0.05, 0.05), Mat.METAL)
	b.box(Vector3(0.0, 1.64, -2.45), Vector3(3.7, 3.0, 0.05), 0.0)
	b.brush(light, Mat.EMISSIVE)
	b.box(Vector3(0.0, 2.75, -2.55), Vector3(3.0, 0.08, 0.04), 0.0)
	b.box(Vector3(0.0, 1.4, -2.55), Vector3(3.0, 0.05, 0.04), 0.0)
	b.brush(Color(0.20, 0.19, 0.17), Mat.METAL)
	b.box(Vector3(0.0, 0.17, -1.6), Vector3(3.7, 0.06, 2.0), 0.0)
	# door frame, roller housing
	b.brush(sec)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 2.0, 1.64, -3.05), Vector3(0.24, 3.0, 0.26), 0.03)
	b.box(Vector3(0.0, 3.30, -3.10), Vector3(4.25, 0.36, 0.42), 0.04)
	b.brush(acc)
	b.box(Vector3(0.0, 3.52, -3.10), Vector3(4.25, 0.07, 0.44), 0.0)
	# door slats compress into the housing: slat i travels (2.88 - 0.25 i) so they stack up under the lintel
	for i in 10:
		b.set_part(Pt.DOOR, Vector3.ZERO, 0.0, 2.88 - 0.25 * float(i))
		b.brush(sec if i % 3 != 0 else Color(0.66, 0.61, 0.46))
		b.box(Vector3(0.0, 0.29 + 0.30 * float(i), -2.97), Vector3(3.76, 0.28, 0.07), 0.01)
	b.clear_part()
	# side pilasters + emissive windows
	for sx in [-1.0, 1.0]:
		for i in 4:
			var z: float = -1.6 + 1.5 * float(i)
			b.brush(sec)
			b.box(Vector3(sx * 3.86, 1.94, z + 0.75), Vector3(0.14, 3.6, 0.28), 0.02)
			b.brush(light, Mat.EMISSIVE)
			b.box(Vector3(sx * 3.83, 2.55, z), Vector3(0.04, 0.55, 0.85), 0.0)
	# roof slab with skylight pockets, team stripe, front parapet
	b.brush(sec)
	var pk: Array[Rect2] = [Rect2(0.10, 0.12, 0.24, 0.30), Rect2(0.38, 0.12, 0.24, 0.30), Rect2(0.66, 0.12, 0.24, 0.30), Rect2(0.10, 0.55, 0.80, 0.16)]
	b.pocket_box(Vector3(0.0, 3.85, 0.9), Vector3(7.9, 0.24, 6.6), pk, 0.08)
	b.brush(base, Mat.PAINT, 1.0)
	b.box(Vector3(0.0, 4.0, -2.55), Vector3(6.8, 0.06, 0.5), 0.0)
	b.box(Vector3(0.0, 3.92, -3.32), Vector3(3.0, 0.34, 0.08), 0.0)
	b.brush(sec)
	b.box(Vector3(0.0, 4.0, -2.75), Vector3(7.9, 0.16, 0.16), 0.03)
	# stacks, rotating vent fan, crane, roof machinery
	for sx in [-2.7, 2.7]:
		b.brush(metal, Mat.METAL)
		b.cylinder(Vector3(sx, 3.95, 3.0), Vector3(sx, 5.5, 3.0), 0.34, 14, 0.02)
		b.brush(acc)
		b.cylinder(Vector3(sx, 5.28, 3.0), Vector3(sx, 5.42, 3.0), 0.40, 14, 0.0)
	b.brush(dark, Mat.METAL)
	b.cylinder(Vector3(-1.9, 3.97, 1.7), Vector3(-1.9, 4.18, 1.7), 0.85, 16, 0.03)
	b.set_part(Pt.RADAR, Vector3(-1.9, 4.2, 1.7))
	b.brush(metal, Mat.METAL)
	for i in 3:
		b.push(ViewMeshBuilder.xf(Vector3(-1.9, 4.21, 1.7), Vector3(0.0, 60.0 * float(i), 0.0)))
		b.box(Vector3.ZERO, Vector3(1.5, 0.03, 0.22), 0.0)
		b.pop()
	b.clear_part()
	b.brush(sec)
	b.box(Vector3(3.3, 5.3, -0.4), Vector3(0.5, 2.7, 0.5), 0.04)
	b.brush(acc)
	b.box(Vector3(0.9, 6.55, -0.4), Vector3(6.0, 0.34, 0.42), 0.03)
	b.brush(metal, Mat.METAL)
	b.box(Vector3(-1.4, 6.5, -0.4), Vector3(0.6, 0.5, 0.5), 0.03)
	b.cylinder(Vector3(-1.9, 6.4, -0.4), Vector3(-1.9, 5.2, -0.4), 0.02, 5, 0.0, false)
	b.set_part(Pt.BLINK, Vector3.ZERO, 0.0, 0.0)
	b.brush(Color(1.0, 0.1, 0.05), Mat.EMISSIVE)
	b.box(Vector3(3.3, 6.75, -0.4), Vector3(0.14, 0.14, 0.14), 0.0)
	b.clear_part()
	b.set_part(Pt.BLINK, Vector3.ZERO, 0.5, 0.0)
	b.box(Vector3(-2.7, 5.6, 3.0), Vector3(0.12, 0.12, 0.12), 0.0)
	b.clear_part()
	b.tier = 1
	b.brush(metal, Mat.METAL)
	b.greebles(Vector3(1.6, 3.98, 2.0), Vector3.UP, Vector3(1.8, 0, 0), Vector3(0, 0, 1.6), 9, 0.25, 0.7, 0.15, 0.5)
	b.tier = 0
	# glowing sign over the door
	b.brush(light, Mat.EMISSIVE)
	b.box(Vector3(0.0, 3.92, -3.38), Vector3(2.4, 0.10, 0.03), 0.0)
	return b
