class_name UiScreenHud
extends Control
## Full in-game HUD mock-up over the procedural 3D battlefield. Also the harness for icon baking and the
## sidebar/minimap/overlay data feeds (one place where sim-side data would be pushed into the widgets).

const KIND_NAMES: Dictionary = {
	"tank_medium": "Medium Tank", "tank_heavy": "Heavy Tank", "tank_light": "Light Tank", "apc": "APC", "artillery": "Howitzer",
	"aa": "AA Tank", "recon": "Scout Buggy", "collector": "Collector", "infantry": "Rifle Squad", "gunship": "Gunship",
}
const ICON_SIZE := Vector2i(188, 124)

var host: Node
var faction: String = "napc"
var roster_index: int = 2
var backend: UiCooldownSweep.Backend = UiCooldownSweep.Backend.SHADER
var skin: UiSkin
var world: DemoWorld
var baker: UiIconBaker
var hud: UiHud
var bake_done: bool = false
var preview: PackedStringArray = PackedStringArray()

func _init(h: Node, f: String, r: int, b: UiCooldownSweep.Backend) -> void:
	host = h
	faction = f
	roster_index = r
	backend = b

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiHotkeys.install()
	skin = UiSkin.for_faction(faction)
	var t0: int = Time.get_ticks_usec()
	theme = UiTheme.build(skin)
	print("PERF theme_build_ms=", (Time.get_ticks_usec() - t0) / 1000.0)
	t0 = Time.get_ticks_usec()
	world = DemoWorld.new()
	world.build(DemoWorld.Mode.BATTLEFIELD, skin.accent, Color("#e0503a") if faction != "def" else Color("#33a0ec"))
	host.add_child(world)
	host.move_child(world, 0)
	print("PERF world_build_ms=", (Time.get_ticks_usec() - t0) / 1000.0, " entities=", world.entities.size())
	baker = UiIconBaker.new()
	add_child(baker)
	add_child(UiVignette.new(0.42, 0.0, 0.0, 0.0, skin.accent))
	hud = UiHud.new()
	hud.sweep_backend = backend
	add_child(hud)
	hud.setup(skin, faction, roster_index)
	_feed_static()
	await _bake_icons()

func _feed_static() -> void:
	hud.overlay.camera = world.camera
	hud.overlay.entities = world.entities
	hud.credits.set_credits(12450, true)
	hud.credits.income_per_min = 1860
	hud.power.capacity = 300
	hud.power.usage = 265
	var t0: int = Time.get_ticks_usec()
	hud.minimap.terrain = ImageTexture.create_from_image(world.minimap_image(160))
	print("PERF minimap_image_ms=", (Time.get_ticks_usec() - t0) / 1000.0)
	hud.minimap.fog = _fog_texture()
	_feed_minimap()
	hud.add_ribbon(UiRibbon.Severity.DANGER, "ENEMY SUPERWEAPON DETECTED", "PERUN MISSILE COMPLEX  //  DEF-2  //  SECTOR F6", UiGlyphs.Glyph.MISSILE, 107.0)
	hud.add_ribbon(UiRibbon.Severity.OK, "ATLAS KINETIC ARRAY", "Orbital magazine charging", UiGlyphs.Glyph.BOLT, -1.0, 0.74, "74%")
	hud.add_ribbon(UiRibbon.Severity.WARN, "BASE UNDER ATTACK", "Refinery  //  north-east ridge", UiGlyphs.Glyph.WARNING, -1.0, -1.0, "ALERT")
	hud.log_line("Construction complete: Barracks. Ready to place.", UiPalette.OK)
	hud.log_line("Guardian Tank x3 queued at Factory 2.")
	hud.log_line("Ally Nordics: \"Covering your north flank.\"", hud.skin.accent2)
	hud.minimap.add_ping(Vector2(0.78, 0.36), UiPalette.DANGER)

func _feed_minimap() -> void:
	var pos := PackedVector2Array()
	var col := PackedColorArray()
	var sz := PackedFloat32Array()
	for e in world.entities:
		pos.append(world.world_to_norm(e["pos"]))
		var t: int = int(e["team"])
		col.append([skin.accent.lightened(0.15), Color("#ff5a4a"), Color("#4fc3ff")][t])
		sz.append(5.0 if e["struct"] else 3.0)
	hud.minimap.set_dots(pos, col, sz)
	var quad: PackedVector2Array = world.frustum_polygon(get_viewport_rect().size)
	var qn := PackedVector2Array()
	for v in quad:
		qn.append(world.world_to_norm(Vector3(v.x, 0.0, v.y)))
	hud.minimap.camera_quad = qn

func _fog_texture() -> ImageTexture:
	var n: int = 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var w: Vector2 = world.norm_to_world(Vector2((x + 0.5) / n, (y + 0.5) / n))
			var best: float = 9999.0
			for e in world.entities:
				if int(e["team"]) == 0:
					best = minf(best, Vector2((e["pos"] as Vector3).x, (e["pos"] as Vector3).z).distance_to(w))
			var a: float = clampf((best - 44.0) / 14.0, 0.0, 1.0) * 0.72
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a))
	return ImageTexture.create_from_image(img)

func _bake_icons() -> void:
	var kinds := PackedStringArray()
	for tab in hud.items:
		for it in hud.items[tab]:
			var k: String = (it as UiBuildItem).model_kind
			if k != "" and k != "power" and not kinds.has(k):
				kinds.append(k)
	for e in world.entities:
		var k2: String = e["kind"]
		if e["team"] == 0 and not kinds.has(k2):
			kinds.append(k2)
	await baker.bake(kinds, ICON_SIZE, skin.accent, skin.accent2)
	print("PERF icons kinds=", baker.last_count, " build_ms=", snappedf(baker.last_build_ms, 0.1), " gpu_wait_ms=", snappedf(baker.last_wait_ms, 0.1), " readback_ms=", snappedf(baker.last_readback_ms, 0.1))
	for tab in hud.items:
		for it in hud.items[tab]:
			var bi := it as UiBuildItem
			if bi.model_kind != "" and bi.model_kind != "power":
				bi.icon = baker.get_icon(bi.model_kind, ICON_SIZE, skin.accent)
	for c in hud.cards:
		c.refresh()
	_refresh_selection()
	var veh: Array = hud.items["vehicles"]
	var qs: Array[Dictionary] = []
	for k in 5:
		qs.append({"item": veh[1], "progress": 0.62} if k < 3 else {})
	hud.queue.slots = qs
	hud.queue.queue_redraw()
	_setup_input()
	if preview.has("drag"):
		hud.select_rect.show_rect(Rect2(600.0, 470.0, 470.0, 280.0))
	if preview.has("simdrag") or preview.has("simrelease"):
		simulate_drag(preview.has("simrelease"))
	if preview.has("tip"):
		_preview_tooltip()
	if preview.has("lowpower"):
		hud.power.usage = 355
		hud.credits.set_credits(11020)
		hud.log_line("LOW POWER: production and research at 50%.", UiPalette.WARN)
	bake_done = true

func _preview_tooltip() -> void:
	var card: UiBuildCard = hud.cards[1]
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", theme.get_stylebox("panel", "TooltipPanel"))
	pc.add_child(UiUnitTooltip.create(card.item, skin))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pc)
	await get_tree().process_frame
	pc.position = Vector2(hud.sidebar.global_position.x - pc.size.x - 10.0, card.global_position.y - 10.0)

func _process(delta: float) -> void:
	if hud == null:
		return
	hud.animate(delta)
	hud.overlay.queue_redraw()
	if _minimap_dirty and Engine.get_process_frames() % 3 == 0:
		_minimap_dirty = false
		_feed_minimap()

func layout_debug() -> String:
	return "screen=%s hud=%s play_area=%s sidebar=%s(pos %s) selection=%s(pos %s) ribbons=%s(pos %s) win=%s" % [size, hud.size, hud.play_area.size, hud.sidebar.size, hud.sidebar.position, hud.selection.size, hud.selection.global_position, hud.ribbon_box.size, hud.ribbon_box.global_position, get_window().size]

func _refresh_selection() -> void:
	var entries: Array[Dictionary] = []
	for e in world.entities:
		if e["selected"]:
			entries.append({"name": KIND_NAMES.get(e["kind"], String(e["kind"]).capitalize()), "role": "Main battle unit" if String(e["kind"]).begins_with("tank") else "Support", "hp": e["hp"], "hp_max": 520, "vet": (1 if entries.size() % 3 == 0 else 0) + (1 if entries.size() == 2 else 0), "squad": 1, "icon": baker.get_icon(e["kind"], ICON_SIZE, skin.accent)})
	hud.selection.view.set_entries(entries, 0)

# --- interactive wiring (also the reference integration of UiInputController + UiPicking) -------------------

var controller: UiInputController
var _minimap_dirty: bool = true

func _setup_input() -> void:
	controller = UiInputController.new()
	controller.select_rect = hud.select_rect
	add_child(controller)
	controller.select_box.connect(_on_select_box)
	controller.select_click.connect(_on_select_click)
	controller.context_order.connect(_on_context_order)
	controller.camera_pan.connect(_on_pan)
	controller.camera_rotate.connect(func(dir: float, delta: float) -> void:
		world.yaw_deg += dir * 90.0 * delta
		world.apply_camera()
		_minimap_dirty = true)
	controller.camera_zoom.connect(func(step: float) -> void:
		world.distance = clampf(world.distance + step * 4.0, 25.0, 110.0)
		world.apply_camera()
		_minimap_dirty = true)
	controller.action_triggered.connect(func(a: StringName) -> void: hud.log_line("hotkey action: %s" % a))
	hud.camera_requested.connect(func(n: Vector2) -> void:
		var w: Vector2 = world.norm_to_world(n)
		world.focus = Vector3(w.x, 0.0, w.y)
		world.apply_camera()
		_minimap_dirty = true)
	hud.command.connect(func(id: StringName) -> void: hud.log_line("command: %s" % id))
	hud.selection.tile_clicked.connect(func(i: int, _s: bool, _c: bool) -> void: hud.log_line("tile %d clicked" % i))

func _on_select_box(rect: Rect2, additive: bool) -> void:
	if not additive:
		for e in world.entities:
			e["selected"] = false
	for i in UiPicking.box_select(world.camera, world.entities, rect):
		var e: Dictionary = world.entities[i]
		if int(e["team"]) == 0 and not e["struct"]:
			e["selected"] = true
	_refresh_selection()

func _on_select_click(pos: Vector2, additive: bool, _double: bool) -> void:
	var i: int = UiPicking.ray_pick(world.camera, world.entities, pos)
	if not additive:
		for e in world.entities:
			e["selected"] = false
	if i >= 0 and int(world.entities[i]["team"]) == 0:
		world.entities[i]["selected"] = true
	_refresh_selection()

func _on_context_order(pos: Vector2, _queued: bool) -> void:
	var hit: Variant = world.ground_point(pos)
	if hit != null:
		hud.minimap.add_ping(world.world_to_norm(hit), UiPalette.OK)
		hud.log_line("move order to (%.0f, %.0f)" % [hit.x, hit.z], UiPalette.OK)

func _on_pan(dir: Vector2, delta: float) -> void:
	var yaw: float = deg_to_rad(world.yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	world.focus += (right * dir.x + back * dir.y) * 45.0 * delta * (world.distance / 60.0)
	world.focus.x = clampf(world.focus.x, -DemoWorld.HALF, DemoWorld.HALF)
	world.focus.z = clampf(world.focus.z, -DemoWorld.HALF, DemoWorld.HALF)
	world.apply_camera()
	_minimap_dirty = true

func _push_button(pos: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = pos
	b.global_position = pos
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(b)

func _push_motion(pos: Vector2, mask: int) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.button_mask = mask
	Input.parse_input_event(m)

## Screenshot helper: injects a real drag-select through the whole input pipeline (Input.parse_input_event).
func simulate_drag(release: bool) -> void:
	_push_motion(Vector2(560.0, 420.0), 0)
	await get_tree().process_frame
	_push_button(Vector2(560.0, 420.0), true)
	await get_tree().process_frame
	_push_motion(Vector2(900.0, 600.0), MOUSE_BUTTON_MASK_LEFT)
	await get_tree().process_frame
	_push_motion(Vector2(1150.0, 790.0), MOUSE_BUTTON_MASK_LEFT)
	await get_tree().process_frame
	if release:
		_push_button(Vector2(1150.0, 790.0), false)
