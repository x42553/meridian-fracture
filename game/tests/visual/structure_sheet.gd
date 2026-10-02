extends "res://tests/visual/lineup_models.gd"
## VIEW-M7 contact sheet: structure / neutral / summon / projectile archetypes (`str_*`, `neu_building`, `sum_*`, `proj_*`) through the
## REAL pipeline (ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend). Structures are instantiated at several footprints:
## one column per footprint, one row per archetype, so the footprint discipline is visible.
##   tools/gd shot res://tests/visual/structure_sheet.tscn out.png --size 1920x1080 -- --arch=str_factory,str_radar
##     [--fp=2x2,3x3,4x3] [--params=kit=lance_rail] [--style=napc] [--team=1] [--pose=rest|action] [--damage=0.0] [--sink=0.0]
##     [--flags=8] [--cam=N --yaw=N --pitch=N --tx=N --tz=N] [--cell=N] [--lift=N] [--list]
## `--arch` may also be `all_str`, `all_neu`, `all_sum`, `all_proj`. Default footprints per archetype come from FOOTPRINTS.

const ROW_LABEL_PREFIX: String = "rc."
## archetype -> [footprints (min, nominal, max)]. Nominal = the shipped def footprint (footprints.json).
const FOOTPRINTS: Dictionary = {
	"str_headquarters": [[2, 2], [3, 3], [4, 4]], "str_generator": [[1, 1], [2, 2], [3, 3]], "str_refinery": [[2, 2], [3, 3], [4, 3]],
	"str_barracks": [[1, 1], [2, 2], [3, 3]], "str_factory": [[2, 2], [3, 3], [4, 4]], "str_dock": [[2, 2], [3, 3], [4, 3]],
	"str_radar": [[1, 1], [2, 2], [3, 3]], "str_airfield": [[4, 3], [6, 3], [6, 4]], "str_laboratory": [[2, 2], [3, 3], [4, 4]],
	"str_watchtower": [[1, 1], [2, 2], [3, 3]], "str_at_turret": [[1, 1], [2, 2], [3, 3]], "str_aa_battery": [[1, 1], [2, 2], [3, 3]],
	"str_relay": [[1, 1], [2, 2], [3, 3]], "str_defense_adv": [[2, 2], [3, 3], [4, 4]], "str_superweapon": [[3, 3], [4, 4], [5, 5]],
	"neu_building": [[1, 1], [2, 2], [3, 3]],
}
const DOCK_INSIDE: PackedStringArray = ["str_refinery"]

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null
var _rows: Array = []  # [archetype, fw, fh, recipe id]
var _style_arg: String = "napc"
var _params: Dictionary = {}


static func archetype_ids(group: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open("res://data/recipes/archetypes")
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(".json") and f.begins_with(group):
			out.append(f.get_basename())
	out.sort()
	return out


## Footprint anchors of a synthetic structure: door in the front-left cell (like the shipped data); refinery: dock cell inside.
static func footprint_entry(arch: String, fw: int, fh: int) -> Dictionary:
	var dz: float = (float(fh) * 0.5 + 0.5) * 3.0
	if DOCK_INSIDE.has(arch):
		dz = (float(fh) * 0.5 - 0.5) * 3.0
	var dx: float = (0.5 - float(fw) * 0.5) * 3.0
	var pads: int = 4 if arch == "str_airfield" else 0
	return {"fw": fw, "fh": fh, "door_cx": dx, "door_cz": dz, "exit_dir": 1024, "dock_cx": dx, "dock_cz": dz, "dock_dir": 1024, "pads_n": pads}


static func rid_of(arch: String, fw: int, fh: int, kit: String = "") -> String:
	return "%s%s%s.%dx%d" % [ROW_LABEL_PREFIX, arch, ("@" + kit) if kit != "" else "", fw, fh]


## Builds a book holding the shipped recipes plus one synthetic recipe per (archetype, footprint).
static func make_book(rows: Array, params: Dictionary) -> ViewRecipeBook:
	var book: ViewRecipeBook = ViewRecipeBook.new()
	book.load_all()
	var fps: Dictionary = {}
	for r: Variant in rows:
		var row: Array = r as Array
		var arch: String = row[0] as String
		var rid: String = row[3] as String
		var rec: Dictionary = {"schema": "meridian.recipe/1", "id": rid, "archetype": arch, "style": "auto"}
		var rp: Dictionary = params.duplicate()
		if row.size() > 4 and (row[4] as String) != "":
			rp[_kit_key(arch)] = row[4]
		if not rp.is_empty():
			rec["params"] = rp
		book.add_recipe(rec, "sheet")
		if int(row[1]) > 0:
			fps[rid] = footprint_entry(arch, int(row[1]), int(row[2]))
	if not fps.is_empty():
		book.add_footprints({"schema": "meridian.footprints/1", "structures": fps}, "sheet")
	book.link()
	return book


## The archetype parameter a `--kits` entry sets.
static func _kit_key(arch: String) -> String:
	return "weapon" if arch == "str_aa_battery" else "kit"


func _mesh(id: StringName, faction: StringName) -> Object:
	return _builder.get_model(id, faction)


func _ready() -> void:
	var arch_arg: String = "all_str"
	var fp_arg: String = ""
	var cell: float = 0.0
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 50.0
	var tx: float = 0.0
	var tz: float = 0.0
	var lift: float = 3.0
	var pose_arg: String = "rest"
	var damage: float = 0.0
	var sink: float = 0.0
	var flags: int = 0
	var list_only: bool = false
	var kits_arg: String = ""
	var cols: int = 4
	var model_yaw: float = 0.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--arch="):
			arch_arg = a.substr(7)
		elif a.begins_with("--fp="):
			fp_arg = a.substr(5)
		elif a.begins_with("--params="):
			for kv: String in a.substr(9).split(",", false):
				var p: PackedStringArray = kv.split("=")
				if p[1].is_valid_float():
					_params[p[0]] = p[1].to_float()
				else:
					_params[p[0]] = p[1]
		elif a.begins_with("--style="):
			_style_arg = a.substr(8)
		elif a.begins_with("--cell="):
			cell = a.substr(7).to_float()
		elif a.begins_with("--cam="):
			dist = a.substr(6).to_float()
		elif a.begins_with("--yaw="):
			yaw = a.substr(6).to_float()
		elif a.begins_with("--pitch="):
			pitch = a.substr(8).to_float()
		elif a.begins_with("--tx="):
			tx = a.substr(5).to_float()
		elif a.begins_with("--tz="):
			tz = a.substr(5).to_float()
		elif a.begins_with("--lift="):
			lift = a.substr(7).to_float()
		elif a.begins_with("--pose="):
			pose_arg = a.substr(7)
		elif a.begins_with("--team="):
			team_id = a.substr(7).to_int()
		elif a.begins_with("--damage="):
			damage = a.substr(9).to_float()
		elif a.begins_with("--sink="):
			sink = a.substr(7).to_float()
		elif a.begins_with("--flags="):
			flags = a.substr(8).to_int()
		elif a.begins_with("--kits="):
			kits_arg = a.substr(7)
		elif a.begins_with("--cols="):
			cols = a.substr(7).to_int()
		elif a.begins_with("--modelyaw="):
			model_yaw = a.substr(11).to_float()
		elif a == "--list":
			list_only = true
	pose = pose_arg
	layout = 0
	ViewGlobals.ensure()
	ViewGlobals.screenshot_mode = true
	var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
	q.apply_to_viewport(get_viewport())
	# archetype list
	var archs: PackedStringArray = PackedStringArray()
	for tok: String in arch_arg.split(",", false):
		match tok:
			"all_str":
				archs.append_array(archetype_ids("str_"))
			"all_neu":
				archs.append_array(archetype_ids("neu_"))
			"all_sum":
				archs.append_array(archetype_ids("sum_"))
			"all_proj":
				archs.append_array(archetype_ids("proj_"))
			_:
				archs.append(tok)
	for ar: String in archs:
		var fps: Array = FOOTPRINTS.get(ar, []) as Array
		if not fp_arg.is_empty():
			fps = []
			for t: String in fp_arg.split(",", false):
				var wh: PackedStringArray = t.split("x")
				fps.append([wh[0].to_int(), wh[1].to_int()])
		var kit_list: PackedStringArray = kits_arg.split(",", false) if kits_arg != "" else PackedStringArray([""])
		for kit: String in kit_list:
			if fps.is_empty():
				_rows.append([ar, 0, 0, rid_of(ar, 0, 0, kit), kit])
			else:
				for f: Variant in fps:
					_rows.append([ar, (f as Array)[0], (f as Array)[1], rid_of(ar, (f as Array)[0] as int, (f as Array)[1] as int, kit), kit])
	_book = make_book(_rows, _params)
	_builder = ViewModelBuilder.new()
	_builder.setup(_book, q)
	_mats.setup(_book, q)
	_backend.setup(self, _mats, q)
	_environment()
	_ground()
	# layout: structures = one row per archetype, one column per footprint; everything else = a grid
	var per_arch: Dictionary = {}
	for r: Variant in _rows:
		var row: Array = r as Array
		var key: String = (row[0] as String) + ("@" + (row[4] as String) if (row[4] as String) != "" else "")
		per_arch[key] = (per_arch.get(key, []) as Array) + [row]
	var grid_mode: bool = true
	for k: Variant in per_arch:
		if (per_arch[k] as Array).size() > 1:
			grid_mode = false
	var n_cols: int = 1
	var n_rows: int = per_arch.size()
	if grid_mode:
		n_cols = mini(cols, per_arch.size())
		n_rows = ceili(float(per_arch.size()) / float(n_cols))
	else:
		for k: Variant in per_arch:
			n_cols = maxi(n_cols, (per_arch[k] as Array).size())
	var ext: float = 0.0
	for r: Variant in _rows:
		var row: Array = r as Array
		ext = maxf(ext, float(maxi(int(row[1]), int(row[2]))) * 3.0)
	var pitch_m: float = cell if cell > 0.0 else maxf(ext + 3.0, 8.0)
	var ri: int = 0
	var slot_i: int = 0
	var worst_h: float = 0.0
	for k: Variant in per_arch:
		var ci: int = 0
		for r: Variant in per_arch[k] as Array:
			var row: Array = r as Array
			var gx: int = ci
			var gz: int = ri
			if grid_mode:
				gx = slot_i % n_cols
				gz = slot_i / n_cols
			var rid: String = row[3] as String
			var sid: StringName = StringName(_style_arg) if _style_arg != "" else _book.style_for_def(rid, "roster.napc")
			var pos: Vector3 = Vector3((float(gx) - float(n_cols - 1) * 0.5) * pitch_m, 0.0, (float(gz) - float(n_rows - 1) * 0.5) * pitch_m)
			var ent: Object = Entity.new()
			ent.style_id = sid
			ent.team_index = team_id
			var m: ViewModel = _builder.get_model(StringName(rid), sid)
			_backend.add(ent, m, sid, ViewTeamColors.color(ent.team_index), ent.team_index)
			ent.rig.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(model_yaw)), pos + Vector3(0.0, minf(m.info.hover, lift), 0.0))
			ent.damage = damage
			ent.sink_m = sink * (m.info.height + 1.5)
			ent.flags = flags
			if pose == "action":
				ent.deploy = 1.0
				ent.turret_yaw = deg_to_rad(-25.0)
				ent.recoil = 0.5
				ent.elevation = 0.6
				ent.spin_angle = 1.1
			_push(ent)
			_ents.append(ent)
			worst_h = maxf(worst_h, m.info.height)
			print("  %s@%s fp=%dx%d tris=%s verts=%d h=%.1f ext=[%.1f..%.1f x %.1f..%.1f] build=%.1fms%s" % [String(k), sid, int(row[1]), int(row[2]),
				m.info.tris, m.info.verts, m.info.height, m.info.rest_aabb.position.x, m.info.rest_aabb.end.x, m.info.rest_aabb.position.z,
				m.info.rest_aabb.end.z, m.info.build_ms, " PLACEHOLDER " + m.error if m.placeholder else ""])
			ci += 1
			slot_i += 1
		ri += 1
	if list_only:
		return
	var span: float = maxf(float(n_cols) * pitch_m, float(n_rows) * pitch_m * 0.85)
	if grid_mode and cell <= 0.0:
		span = maxf(float(n_cols) * pitch_m, float(n_rows) * pitch_m * 0.9)
	_aim(Vector3(tx, worst_h * 0.25, tz), dist if dist > 0.0 else span * 1.35 + worst_h * 1.2, pitch, yaw, 34.0)
