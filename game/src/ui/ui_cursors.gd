class_name UiCursors
extends RefCounted
## Procedural mouse cursors (ui.md 3.5, 5.7.3, 7.7, art 5.12.6): 17 base images registered once, each on its own
## `Input.CursorShape` slot, so a state change is a one-call `Input.set_default_cursor_shape` (1 us). Two reticle variants
## (power, superweapon) are swapped into the CROSS slot while a power is targeted; the eight edge-scroll arrows are swapped
## onto the ARROW slot while the pointer rests in the scroll band. Images come from vector recipes (32 x 32 design space,
## rasterised by the engine's SVG loader at 32 / 48 / 64 px, `access/cursor_scale` 100 / 150 / 200) with the art rule of a
## white stroke and a dark outline around a token-coloured core (a wider white ring under `access/high_contrast_hud`).
## `ui/cursor_style == 1` and headless runs use the system cursors (no registration).

enum State { DEFAULT = 0, TEXT = 1, HAND = 2, ATTACK = 3, MOVE = 4, SELECT = 5, DENIED = 6, ATTACK_MOVE = 7, FORCE_FIRE = 8, GUARD = 9,
	DEPLOY = 10, SELL = 11, REPAIR = 12, RALLY = 13, INSPECT = 14, BUSY = 15, INTERACT = 16, POWER = 17, SUPERWEAPON = 18, PLACE_OK = 19,
	PLACE_BAD = 20, SCROLL_N = 21, SCROLL_NE = 22, SCROLL_E = 23, SCROLL_SE = 24, SCROLL_S = 25, SCROLL_SW = 26, SCROLL_W = 27, SCROLL_NW = 28 }

const DATA_PATH: String = "res://data/ui/cursors.json"
const SLOT_NAMES: Dictionary = {
	"ARROW": Input.CURSOR_ARROW, "IBEAM": Input.CURSOR_IBEAM, "POINTING_HAND": Input.CURSOR_POINTING_HAND, "CROSS": Input.CURSOR_CROSS,
	"WAIT": Input.CURSOR_WAIT, "BUSY": Input.CURSOR_BUSY, "DRAG": Input.CURSOR_DRAG, "CAN_DROP": Input.CURSOR_CAN_DROP,
	"FORBIDDEN": Input.CURSOR_FORBIDDEN, "VSIZE": Input.CURSOR_VSIZE, "HSIZE": Input.CURSOR_HSIZE, "BDIAGSIZE": Input.CURSOR_BDIAGSIZE,
	"FDIAGSIZE": Input.CURSOR_FDIAGSIZE, "MOVE": Input.CURSOR_MOVE, "VSPLIT": Input.CURSOR_VSPLIT, "HSPLIT": Input.CURSOR_HSPLIT,
	"HELP": Input.CURSOR_HELP,
}
const DARK: String = "#080c12"
const WHITE: String = "#ffffff"
const OUTLINE_EXTRA: float = 4.0  ## dark outline: 2 px each side of the core stroke in the 32-unit design space
const RING_EXTRA: float = 2.0  ## white ring: 1 px each side

## Test hook: force registration in headless runs.
static var enabled_override: bool = false
## Counts `Input` calls made by `register_all` / `set_state` / `set_scroll` (tests assert "no call when unchanged").
static var apply_calls: int = 0

static var _table: Dictionary = {}  ## state name -> entry
static var _images: Dictionary = {}  ## "state@px@hc" -> Image


## Orderly quit: hands the custom cursor textures back while the RenderingServer still exists (the DisplayServer keeps its own reference and
## frees it after the server is gone: 17 `RenderingServer::get_singleton() is null` errors at exit otherwise).
static func release_all() -> void:
	for shape: int in 17:
		Input.set_custom_mouse_cursor(null, shape as Input.CursorShape)
	_images.clear()
	_current = -1
static var _size_px: int = 32
static var _hc: bool = false
static var _enabled: bool = false
static var _current: int = -1
static var _cross_state: int = State.ATTACK  ## image on the CROSS slot: ATTACK, or POWER / SUPERWEAPON while targeting
static var _arrow_variant: int = -1  ## scroll arrow swapped into ARROW, -1 = the default arrow


# ---------------------------------------------------------------------------------------------------------------- data

static func _load() -> void:
	if not _table.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary and (parsed as Dictionary).get("cursors") is Dictionary:
		_table = (parsed as Dictionary)["cursors"] as Dictionary
	else:
		Log.error("ui", "cursors: cannot read %s" % DATA_PATH)
		_table = {}


static func state_name(state: int) -> String:
	var keys: Array = State.keys()
	return str(keys[state]) if state >= 0 and state < keys.size() else ""


## The table entry of a state with aliases resolved (`PLACE_OK` -> `DEFAULT`).
static func entry_of(state: int) -> Dictionary:
	_load()
	var e: Dictionary = _table.get(state_name(state), {}) as Dictionary
	if e.has("alias"):
		e = _table.get(str(e["alias"]), {}) as Dictionary
	return e


## `Input.CursorShape` slot of a state.
static func slot_of(state: int) -> int:
	var e: Dictionary = entry_of(state)
	if e.is_empty():
		return Input.CURSOR_ARROW
	if state >= State.SCROLL_N:
		return Input.CURSOR_ARROW
	return int(SLOT_NAMES.get(str(e.get("slot", "ARROW")), Input.CURSOR_ARROW))


## Sizes of the source images (`access/cursor_scale` 100 / 150 / 200).
static func sizes() -> PackedInt32Array:
	_load()
	return PackedInt32Array([32, 48, 64])


static func size_for_scale(scale_pct: int) -> int:
	if scale_pct >= 200:
		return 64
	if scale_pct >= 150:
		return 48
	return 32


# ---------------------------------------------------------------------------------------------------------------- images

## Hotspot in pixels of the image of `state` at `px` (fractions of the image, rotated for the scroll arrows).
static func hotspot_of(state: int, px: int) -> Vector2:
	var e: Dictionary = entry_of(state)
	var h: Array = e.get("hotspot", [0.5, 0.5]) as Array
	var f: Vector2 = Vector2(float(h[0]), float(h[1]))
	var rot: float = float(e.get("rotate_deg", 0))
	if rot != 0.0:
		f = Vector2(0.5, 0.5) + (f - Vector2(0.5, 0.5)).rotated(deg_to_rad(rot))
	return (f * float(px)).round()


## The cursor image of `state` at `px` pixels; cached per (state, size, contrast mode). Null when the recipe fails to rasterise.
static func image_for(state: int, px: int = -1, high_contrast: bool = false) -> Image:
	var e: Dictionary = entry_of(state)
	if e.is_empty():
		return null
	var size: int = px if px > 0 else _size_px
	var key: String = "%s@%d@%d@%s" % [state_name(state), size, int(high_contrast), UiThemeService.current_skin().accent.to_html(false)]
	if _images.has(key):
		return _images[key] as Image
	var svg: String = svg_of(state, size, high_contrast)
	var img: Image = Image.new()
	if img.load_svg_from_string(svg) != OK or img.is_empty():
		Log.error("ui", "cursors: recipe '%s' did not rasterise" % e.get("recipe", "?"))
		return null
	img.convert(Image.FORMAT_RGBA8)
	_images[key] = img
	return img


## The SVG source of a state's cursor (a test and debugging aid).
static func svg_of(state: int, px: int, high_contrast: bool = false) -> String:
	var e: Dictionary = entry_of(state)
	var shapes: Array = recipe(str(e.get("recipe", "arrow")))
	return compose(shapes, _color_of(str(e.get("color", "text"))), px, high_contrast, float(e.get("rotate_deg", 0)))


static func _color_of(token: String) -> Color:
	match token:
		"danger":
			return UiPalette.semantic(&"danger")
		"ok":
			return UiPalette.semantic(&"ok")
		"warn":
			return UiPalette.semantic(&"warn")
		"power":
			return UiPalette.semantic(&"power")
		"accent":
			return UiThemeService.current_skin().accent
		"disabled":
			return Color("#9aa6b4")
		"orange":
			return Color("#ff9a2e")
	return UiPalette.TEXT


# ---------------------------------------------------------------------------------------------------------------- recipes

static func _line(d: String, w: float = 2.4) -> Dictionary:
	return {"d": d, "fill": false, "w": w}


static func _fill(d: String) -> Dictionary:
	return {"d": d, "fill": true, "w": 0.0}


static func _dot() -> Dictionary:
	return {"d": "M16 16 h0.01", "fill": false, "w": 3.6}


const RING_R11: String = "M5 16 A11 11 0 1 0 27 16 A11 11 0 1 0 5 16"
const RING_R10: String = "M6 16 A10 10 0 1 0 26 16 A10 10 0 1 0 6 16"
const RING_R9: String = "M7 16 A9 9 0 1 0 25 16 A9 9 0 1 0 7 16"


## Shape list of a recipe in the 32 x 32 design space: `[{d, fill, w, edge?}]`.
static func recipe(name: String) -> Array:
	match name:
		"arrow":
			return [{"d": "M6 3 L6 26 L11.5 21 L15.5 29.5 L19.5 27.6 L15.6 19.4 L23 19 Z", "fill": true, "w": 0.0, "edge": true}]
		"crosshair":
			return [_line(RING_R10), _line("M16 1.5 V9 M16 23 V30.5 M1.5 16 H9 M23 16 H30.5"), _dot()]
		"chevron_ring":
			return [_line(RING_R11), _line("M10.5 19.5 L16 13 L21.5 19.5", 2.8)]
		"no_entry":
			return [_line(RING_R11, 2.8), _line("M8.4 8.4 L23.6 23.6", 2.8)]
		"flag":
			return [_line("M9 3 V29.5", 2.4), _fill("M9 4 L26 10 L9 16 Z")]
		"reticle":
			return [_line(RING_R9), _line("M16 2 V9 M16 23 V30 M2 16 H9 M23 16 H30"), _dot()]
		"reticle_x2":
			return [_line("M3 16 A13 13 0 1 0 29 16 A13 13 0 1 0 3 16"), _line("M10 16 A6 6 0 1 0 22 16 A6 6 0 1 0 10 16"),
				_line("M16 2 V8 M16 24 V30 M2 16 H8 M24 16 H30"), _dot()]
		"brackets":
			return [_line("M5 12 V5 H12 M20 5 H27 V12 M27 20 V27 H20 M12 27 H5 V20", 2.6)]
		"inward_brackets":
			return [_line("M4 11 V4 H11 M21 4 H28 V11 M28 21 V28 H21 M11 28 H4 V21", 2.6), _line("M11 11 L14.5 14.5 M21 11 L17.5 14.5 M11 21 L14.5 17.5 M21 21 L17.5 17.5", 2.4)]
		"ibeam":
			return [_line("M11 4.5 H21 M16 4.5 V27.5 M11 27.5 H21", 2.4)]
		"hand":
			return [{"d": "M13 4.5 C13 3.3 14 2.5 15.2 2.5 C16.4 2.5 17.4 3.3 17.4 4.5 V13 H18 C18.4 12 19.3 11.6 20.2 11.6 C21.3 11.6 22 12.3 22 13.3 V14 C22.5 13.6 23.3 13.4 24 13.6 C25.1 13.9 25.7 14.7 25.7 15.8 V22 C25.7 25.2 23.2 28.6 19.8 28.6 H15.6 C13 28.6 11.4 27.2 10.2 25.4 L5.9 18.4 C5.3 17.4 5.9 16.3 7 16.1 C8 15.9 8.8 16.4 9.4 17.2 L13 21.4 Z",
				"fill": true, "w": 0.0, "edge": true}]
		"shield":
			return [_fill("M16 3.5 L26 7.5 V16 C26 22 21.5 26.5 16 29 C10.5 26.5 6 22 6 16 V7.5 Z")]
		"wrench":
			return [_fill("M22.5 3.5 C18.8 3.5 16.4 6.8 17.4 10.4 L5.8 22 C4.5 23.3 4.5 25.2 5.8 26.4 C7 27.6 8.9 27.6 10.2 26.3 L21.7 14.7 C25.3 15.7 28.6 13.2 28.6 9.5 L24.7 12.3 L21.6 10.4 L19.8 7.3 L23.7 4.6 C23.4 3.9 23 3.5 22.5 3.5 Z")]
		"dollar":
			return [_line("M21 9.5 C21 5.5 11 5.5 11 11 C11 16.5 21 15.5 21 21 C21 26.5 11 26.5 11 22.5", 2.8), _line("M16 3 V29", 2.4)]
		"magnifier":
			return [_line("M5 13 A8 8 0 1 0 21 13 A8 8 0 1 0 5 13", 2.6), _line("M19 19 L27.5 27.5", 3.6)]
		"spinner":
			return [_line("M16 5 A11 11 0 1 1 5 16", 3.2)]
		"chevron_box":
			return [_line("M12 6 H26 V26 H12", 2.6), _line("M3 16 H18 M13 11 L18 16 L13 21", 2.8)]
		"crosshair_arrows":
			return [_line("M10 16 A6 6 0 1 0 22 16 A6 6 0 1 0 10 16"), _line("M12 6 L16 2 L20 6 M12 26 L16 30 L20 26 M6 12 L2 16 L6 20 M26 12 L30 16 L26 20"), _dot()]
		"ground_reticle":
			return [_line("M3 16 A13 8 0 1 0 29 16 A13 8 0 1 0 3 16"), _line("M16 3 V9 M16 23 V29 M1.5 16 H7 M25 16 H30.5"), _dot()]
		"scroll_arrow":
			return [_fill("M16 3 L26 15.5 H19.5 V28 H12.5 V15.5 H6 Z")]
	return [_line(RING_R10)]


## Wraps a shape list into layered SVG: dark outline, white ring, token-coloured core (`rotate_deg` turns the whole picture).
static func compose(shapes: Array, col: Color, px: int, high_contrast: bool = false, rotate_deg: float = 0.0) -> String:
	var core: String = "#" + col.to_html(false)
	var out: PackedStringArray = PackedStringArray()
	out.append("<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 32 32'>" % [px, px])
	if rotate_deg != 0.0:
		out.append("<g transform='rotate(%s 16 16)'>" % String.num(rotate_deg, 1))
	var layers: Array = []
	if high_contrast:
		layers.append([WHITE, OUTLINE_EXTRA + RING_EXTRA * 3.0, true])
	layers.append([DARK, OUTLINE_EXTRA + RING_EXTRA, true])
	layers.append([WHITE, RING_EXTRA, true])
	layers.append([core, 0.0, false])
	for layer: Array in layers:
		for s: Variant in shapes:
			out.append(_shape_svg(s as Dictionary, str(layer[0]), float(layer[1]), bool(layer[2])))
	if rotate_deg != 0.0:
		out.append("</g>")
	out.append("</svg>")
	return "".join(out)


static func _shape_svg(s: Dictionary, colour: String, extra: float, halo: bool) -> String:
	var w: float = float(s["w"])
	if bool(s["fill"]):
		if halo:
			# the halo of a filled shape is its outline stroked wide; the shape itself is filled in the halo colour
			return "<path d='%s' fill='%s' stroke='%s' stroke-width='%s' stroke-linejoin='round'/>" % [s["d"], colour, colour, String.num(extra + 1.6, 1)]
		if bool(s.get("edge", false)):
			return "<path d='%s' fill='#f6f9fc' stroke='%s' stroke-width='1.6' stroke-linejoin='round'/>" % [s["d"], colour]
		return "<path d='%s' fill='%s' stroke='%s' stroke-width='1.2' stroke-linejoin='round'/>" % [s["d"], colour, colour]
	return "<path d='%s' fill='none' stroke='%s' stroke-width='%s' stroke-linecap='round' stroke-linejoin='round'/>" % [s["d"], colour, String.num(w + extra, 1)]


# ---------------------------------------------------------------------------------------------------------------- registration

## True when cursors are registered with the engine (game cursors on, not headless, or forced by tests).
static func is_active() -> bool:
	return _enabled


static func current_state() -> int:
	return _current


## Bakes the 17 base cursors at the size of `access/cursor_scale` and registers each on its own slot. `scale_pct` -1 and `style`
## -1 read the settings (`access/cursor_scale`, `ui/cursor_style`). Style 1 or headless: system cursors, nothing is registered.
static func register_all(scale_pct: int = -1, style: int = -1) -> void:
	_load()
	var settings: Node = null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		settings = tree.root.get_node_or_null("AppSettings")
	if scale_pct < 0:
		scale_pct = int(settings.call("get_int", &"access/cursor_scale")) if settings != null else 100
	if style < 0:
		style = int(settings.call("get_int", &"ui/cursor_style")) if settings != null else 0
	_hc = bool(settings.call("get_bool", &"access/high_contrast_hud")) if settings != null else false
	_size_px = size_for_scale(scale_pct)
	_enabled = style == 0 and (enabled_override or DisplayServer.get_name() != "headless")
	_current = -1
	_cross_state = State.ATTACK
	_arrow_variant = -1
	if not _enabled:
		for slot: int in SLOT_NAMES.values():
			Input.set_custom_mouse_cursor(null, slot as Input.CursorShape)
		apply_calls += 1
		return
	for st: int in State.PLACE_OK:
		if st == State.POWER or st == State.SUPERWEAPON:
			continue
		var img: Image = image_for(st, _size_px, _hc)
		if img != null:
			Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), slot_of(st) as Input.CursorShape, hotspot_of(st, _size_px))
			apply_calls += 1


## Re-registers after a settings change (cursor size, style, contrast, skin accent).
static func refresh() -> void:
	_images.clear()
	register_all()


## Shows the cursor of `state`: a slot switch (1 us); nothing happens when the state is unchanged. POWER / SUPERWEAPON swap
## their reticle into the CROSS slot, leaving them restores the crosshair; a scroll arrow on the ARROW slot is restored first.
static func set_state(state: int) -> void:
	if state == _current:
		return
	if state >= State.SCROLL_N and state <= State.SCROLL_NW:
		_current = state
		_swap_arrow(state)
		return
	_current = state
	if not _enabled:
		return
	_restore_arrow()
	if slot_of(state) == Input.CURSOR_CROSS:
		var want: int = state if state == State.POWER or state == State.SUPERWEAPON else State.ATTACK
		if want != _cross_state:
			_cross_state = want
			_put(want, Input.CURSOR_CROSS)
	Input.set_default_cursor_shape(slot_of(state) as Input.CursorShape)
	apply_calls += 1


static func _put(state: int, slot: int) -> void:
	var img: Image = image_for(state, _size_px, _hc)
	if img != null:
		Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), slot as Input.CursorShape, hotspot_of(state, _size_px))
		apply_calls += 1


## Edge-scroll arrow for a direction in {-1, 0, 1}^2 (x east, y south); `Vector2i.ZERO` restores the default arrow.
## Swaps the image only when the direction changed.
static func set_scroll(dir: Vector2i) -> void:
	var st: int = scroll_state(dir)
	if st < 0:
		if _arrow_variant != -1:
			_restore_arrow()
			_current = State.DEFAULT
			if _enabled:
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				apply_calls += 1
		return
	if st == _arrow_variant and _current == st:
		return
	_current = st
	_swap_arrow(st)


## The SCROLL_* state of a direction, -1 for no direction.
static func scroll_state(dir: Vector2i) -> int:
	var d: Vector2i = Vector2i(signi(dir.x), signi(dir.y))
	match d:
		Vector2i(0, -1):
			return State.SCROLL_N
		Vector2i(1, -1):
			return State.SCROLL_NE
		Vector2i(1, 0):
			return State.SCROLL_E
		Vector2i(1, 1):
			return State.SCROLL_SE
		Vector2i(0, 1):
			return State.SCROLL_S
		Vector2i(-1, 1):
			return State.SCROLL_SW
		Vector2i(-1, 0):
			return State.SCROLL_W
		Vector2i(-1, -1):
			return State.SCROLL_NW
	return -1


static func _swap_arrow(st: int) -> void:
	if not _enabled:
		_arrow_variant = st
		return
	if st != _arrow_variant:
		_arrow_variant = st
		_put(st, Input.CURSOR_ARROW)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	apply_calls += 1


static func _restore_arrow() -> void:
	if _arrow_variant == -1:
		return
	_arrow_variant = -1
	if _enabled:
		_put(State.DEFAULT, Input.CURSOR_ARROW)


## Test hook: forgets registration state.
static func reset() -> void:
	_images.clear()
	_enabled = false
	_current = -1
	_cross_state = State.ATTACK
	_arrow_variant = -1
	apply_calls = 0
