extends "res://tests/visual/lineup_models.gd"
## VIEW-M2 visual acceptance: the four spike tank looks (NAPC / NEC / DEF / HAN) and the rifle squad built by the REAL recipe
## pipeline (ViewRecipeBook -> ViewModelBuilder -> ViewNodeBackend) from ONE `veh_tank` archetype + style dictionaries.
## `tools/gd shot res://tests/visual/recipe_tanks.tscn out.png --size 1920x1080` (recipe_squads.tscn: squads at hp 100/74/49/24 %).

var _book: ViewRecipeBook = null
var _builder: ViewModelBuilder = null


func _mesh(id: StringName, faction: StringName) -> Object:
	if _builder == null:
		_book = ViewRecipeBook.new()
		_book.load_all()
		_book.add_recipe({"schema": "meridian.recipe/1", "id": "proof.veh_tank", "archetype": "veh_tank"}, "shot")
		_book.add_recipe({"schema": "meridian.recipe/1", "id": "proof.inf_squad", "archetype": "inf_squad"}, "shot")
		_book.link()
		var q: ViewQuality = ViewQuality.create(ViewQuality.load_presets(), ViewQuality.Preset.HIGH)
		_builder = ViewModelBuilder.new()
		_builder.setup(_book, q)
		_mats.setup(_book, q)
	if id == &"tank":
		return _builder.get_model(&"proof.veh_tank", faction)
	if id == &"infantry":
		return _builder.get_model(&"proof.inf_squad", faction)
	return super._mesh(id, faction)


func _ready() -> void:
	super._ready()
	var dist: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 24.0
	var tx: float = 0.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			dist = a.substr(6).to_float()
		elif a.begins_with("--yaw="):
			yaw = a.substr(6).to_float()
		elif a.begins_with("--pitch="):
			pitch = a.substr(8).to_float()
		elif a.begins_with("--tx="):
			tx = a.substr(5).to_float()
	if dist > 0.0:
		_aim(Vector3(tx, 0.9, 0.0), dist, pitch, yaw, 34.0)
